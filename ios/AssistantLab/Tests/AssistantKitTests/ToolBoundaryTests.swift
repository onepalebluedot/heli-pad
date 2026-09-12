import XCTest
@testable import AssistantKit
import AssistantMocks

/// A03: what the model is allowed to name, and what happens when it names
/// something else.
final class ToolBoundaryTests: XCTestCase {
    private func call(_ name: String, _ arguments: [String: Any]) -> RawToolCall {
        let data = try! JSONSerialization.data(withJSONObject: arguments, options: [.sortedKeys])
        return RawToolCall(callID: "c1", name: name, argumentsJSON: String(data: data, encoding: .utf8)!)
    }

    private var validFind: [String: Any] {
        [
            "start_date": "2026-09-07", "end_date": "2026-09-13",
            "person_ids": [], "categories": [], "only_unassigned": false,
            "text_contains": NSNull()
        ]
    }

    func testCatalogIsExactlyTheAllowlist() {
        XCTAssertEqual(
            Set(ToolName.allCases.map(\.rawValue)),
            ["find_events", "get_event", "list_household_people", "list_saved_places",
             "preview_create_events", "preview_assign_tasks", "get_schedule_trends", "get_app_help"]
        )
        // Nothing in the catalog writes. Confirmation is a UI action.
        XCTAssertTrue(ToolCatalog.all.allSatisfy { definition in
            definition.name.isReadOnly || definition.name.rawValue.hasPrefix("preview_")
        })
    }

    func testEverySchemaIsStrictShaped() throws {
        for definition in ToolCatalog.all {
            let parameters = definition.parameters.json
            XCTAssertEqual(parameters["additionalProperties"] as? Bool, false, definition.name.rawValue)
            let properties = try XCTUnwrap(parameters["properties"] as? [String: Any])
            let required = try XCTUnwrap(parameters["required"] as? [String])
            XCTAssertEqual(Set(required), Set(properties.keys), definition.name.rawValue)
            XCTAssertEqual(definition.wireFormat["strict"] as? Bool, true)
        }
    }

    func testUnknownToolIsRefused() {
        XCTAssertThrowsError(try ToolArgumentParser.validate(call("admin_export_all", [:]))) { error in
            XCTAssertEqual(error as? ToolRejection, .unknownTool("admin_export_all"))
        }
        // Including near-misses of real names.
        XCTAssertThrowsError(try ToolArgumentParser.validate(call("find_events_v2", validFind)))
    }

    func testUnknownFieldIsRefusedNotIgnored() {
        var arguments = validFind
        arguments["household_id"] = "hh-somebody-else"
        XCTAssertThrowsError(try ToolArgumentParser.validate(call("find_events", arguments))) { error in
            XCTAssertEqual(error as? ToolRejection, .unknownField(tool: "find_events", field: "household_id"))
        }
    }

    func testMissingFieldIsRefused() {
        var arguments = validFind
        arguments.removeValue(forKey: "only_unassigned")
        XCTAssertThrowsError(try ToolArgumentParser.validate(call("find_events", arguments))) { error in
            XCTAssertEqual(error as? ToolRejection, .missingField(tool: "find_events", field: "only_unassigned"))
        }
    }

    func testMalformedAndOutOfRangeValues() {
        var badDate = validFind
        badDate["start_date"] = "September 7"
        XCTAssertThrowsError(try ToolArgumentParser.validate(call("find_events", badDate)))

        var backwards = validFind
        backwards["start_date"] = "2026-09-13"
        backwards["end_date"] = "2026-09-07"
        XCTAssertThrowsError(try ToolArgumentParser.validate(call("find_events", backwards)))

        var sweep = validFind
        sweep["start_date"] = "2020-01-01"
        sweep["end_date"] = "2026-12-31"
        XCTAssertThrowsError(try ToolArgumentParser.validate(call("find_events", sweep))) { error in
            guard case .rangeTooLong = error as? ToolRejection else {
                return XCTFail("expected rangeTooLong, got \(error)")
            }
        }

        var badCategory = validFind
        badCategory["categories"] = ["Espionage"]
        XCTAssertThrowsError(try ToolArgumentParser.validate(call("find_events", badCategory)))

        XCTAssertThrowsError(try ToolArgumentParser.validate(
            RawToolCall(callID: "c", name: "find_events", argumentsJSON: "not json")
        ))
    }

    func testHelpTopicsAreBounded() {
        XCTAssertThrowsError(try ToolArgumentParser.validate(call("get_app_help", ["topic": "how_to_build_a_bomb"])))
        XCTAssertThrowsError(try ToolArgumentParser.validate(call("get_app_help", ["topic": "general_knowledge"])))
        XCTAssertNoThrow(try ToolArgumentParser.validate(call("get_app_help", ["topic": "recurring_events"])))
    }

    // MARK: - preview_create_events shape rules

    private var validCreate: [String: Any] {
        [
            "title": "Swimming", "start_date": "2026-09-15",
            "start_time": "16:00", "end_time": "17:00",
            "location_name": "Eastside Pool", "kind": "practice",
            "child_ids": [], "owner_id": NSNull(),
            "repeat_mode": "weekly", "weekdays": [1],
            "week_count": 30, "end_date": NSNull()
        ]
    }

    func testSeriesNeedsExactlyOneBound() {
        var both = validCreate
        both["end_date"] = "2027-04-06"
        XCTAssertThrowsError(try ToolArgumentParser.validate(call("preview_create_events", both)))

        var neither = validCreate
        neither["week_count"] = NSNull()
        XCTAssertThrowsError(try ToolArgumentParser.validate(call("preview_create_events", neither)))
    }

    func testSingleEventCannotCarrySeriesBounds() {
        var single = validCreate
        single["repeat_mode"] = "none"
        single["weekdays"] = []
        XCTAssertThrowsError(try ToolArgumentParser.validate(call("preview_create_events", single)))
    }

    func testEndTimeMustFollowStartTime() {
        var backwards = validCreate
        backwards["end_time"] = "15:00"
        XCTAssertThrowsError(try ToolArgumentParser.validate(call("preview_create_events", backwards)))
    }

    func testWeekCountCeilingMatchesTheEditor() {
        var tooLong = validCreate
        tooLong["week_count"] = 53
        XCTAssertThrowsError(try ToolArgumentParser.validate(call("preview_create_events", tooLong)))
    }

    func testDuplicateEventIDsAreCollapsedNotCounted() throws {
        let validated = try ToolArgumentParser.validate(call("preview_assign_tasks", [
            "event_ids": ["evt-a", "evt-a", "evt-b"], "owner_id": "p-alex"
        ]))
        guard case .previewAssignTasks(let ids, _) = validated else { return XCTFail("wrong case") }
        XCTAssertEqual(ids, ["evt-a", "evt-b"])
    }
}

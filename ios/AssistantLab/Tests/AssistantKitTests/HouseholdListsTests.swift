import XCTest
@testable import AssistantKit
import AssistantMocks

final class HouseholdListsTests: XCTestCase {
    private func call(_ name: String, _ args: [String: Any]) throws -> ValidatedToolCall {
        let data = try JSONSerialization.data(withJSONObject: args)
        return try ToolArgumentParser.validate(RawToolCall(callID: "c", name: name, argumentsJSON: String(decoding: data, as: UTF8.self)), in: Fixtures.session)
    }

    func testListsReadPreviewConfirmAndRetryWithoutCalendarEvents() async throws {
        let household = Fixtures.household()
        household.cloudReachable = false
        let client = ProgrammedLunaClient(replies: [
            ProgrammedLunaClient.toolCall("read_household_lists", ["kind": "groceries", "include_completed": false]),
            ProgrammedLunaClient.toolCall("preview_add_list_items", ["kind": "groceries", "section": NSNull(), "items": [["text": "Milk", "quantity": "2 cartons"]]]),
            .final(FinalDecision(outcome: .result, resultTemplate: .reviewReady))
        ])
        let engine = AssistantEngine(client: client, router: ToolRouter(query: household),
                                     proposals: ProposalStore(query: household, command: household), query: household,
                                     configuration: AssistantConfiguration(relayBaseURL: URL(string: "https://relay.invalid")!))
        let eventsBefore = try await household.events(in: Fixtures.session)
        let turn = await engine.send("Add 2 cartons of milk to groceries", in: Fixtures.session)
        XCTAssertEqual(turn.executedTools, [.readHouseholdLists, .previewAddListItems])
        XCTAssertEqual(household.applyCount, 0)
        let id = try XCTUnwrap(turn.pendingProposalID)
        let confirmed = await engine.confirm(proposalID: id, in: Fixtures.session)
        guard case .receipt(let receipt)? = confirmed.cards.first else { return XCTFail("missing receipt") }
        XCTAssertEqual(receipt.headline, "Added 1 list item")
        XCTAssertTrue(receipt.syncLabel.contains("pending"))
        _ = await engine.confirm(proposalID: id, in: Fixtures.session)
        XCTAssertEqual(household.applyCount, 1)
        let crossHousehold = await engine.confirm(proposalID: id, in: Fixtures.otherSession)
        XCTAssertFalse(crossHousehold.cards.contains { if case .receipt = $0 { return true }; return false },
                       "cached receipts must not expose another household's list items")
        let lists = try await household.householdLists(in: Fixtures.session)
        XCTAssertEqual(lists.first(where: { $0.kind == .groceries })?.items.first?.quantity, "2 cartons")
        let eventsAfter = try await household.events(in: Fixtures.session)
        XCTAssertEqual(eventsBefore, eventsAfter)
        let foreign = try await household.householdLists(in: Fixtures.otherSession)
        XCTAssertTrue(foreign.allSatisfy { $0.items.isEmpty })

        let read = try await ToolRouter(query: household).run(call("read_household_lists", ["kind": "groceries", "include_completed": false]), in: Fixtures.session)
        guard case .householdList(let card)? = read.cards.first else { return XCTFail("missing list card") }
        XCTAssertEqual(card.list.items.first?.text, "Milk")
        XCTAssertEqual(card.list.syncLabel, "Waiting to sync")
    }

    func testListBoundaryRejectsForeignScopeUnknownSectionAndOversizedItems() async throws {
        XCTAssertThrowsError(try call("read_household_lists", ["kind": "todos", "include_completed": false, "household_id": "someone-else"]))
        XCTAssertThrowsError(try call("preview_add_list_items", ["kind": "todos", "section": NSNull(), "items": []]))
        XCTAssertThrowsError(try call("preview_add_list_items", ["kind": "todos", "section": NSNull(), "items": [["text": String(repeating: "x", count: 201), "quantity": NSNull()]]]))
        let badSection = try call("preview_add_list_items", ["kind": "todos", "section": "Invented", "items": [["text": "Tidy up", "quantity": NSNull()]]])
        do {
            _ = try await ToolRouter(query: Fixtures.household()).run(badSection, in: Fixtures.session)
            XCTFail("unknown section should not silently redirect")
        } catch is ToolRejection {}
    }

    func testTimeOnlyPianoDefaultsToTodayAndOneHourWithVisibleAssumptions() async throws {
        let args: [String: Any] = [
            "title": "piano lesson", "start_date": NSNull(), "start_time": "15:00", "end_time": NSNull(),
            "location_name": NSNull(), "lookup_location": false, "context": NSNull(), "kind": "lesson",
            "child_ids": [], "owner_id": NSNull(), "repeat_mode": "none", "weekdays": [], "week_count": NSNull(), "end_date": NSNull()
        ]
        let validated = try call("preview_create_events", args)
        guard case .previewCreateEvents(let parsed) = validated else { return XCTFail("wrong tool") }
        XCTAssertEqual(parsed.rule.startDate, Fixtures.today)
        XCTAssertEqual(parsed.endTime, "16:00")
        XCTAssertTrue(parsed.dateWasAssumed && parsed.durationWasAssumed)
        let outcome = try await ToolRouter(query: Fixtures.household()).run(validated, in: Fixtures.session)
        guard case .proposal(let card)? = outcome.cards.first else { return XCTFail("no proposal") }
        XCTAssertTrue(card.assumptions.contains { $0.contains("today") })
        XCTAssertTrue(card.assumptions.contains { $0.contains("60 minutes") })
        var explicit = args
        explicit["start_date"] = "2026-10-10"
        explicit["end_time"] = "15:30"
        guard case .previewCreateEvents(let stated) = try call("preview_create_events", explicit) else { return XCTFail("wrong tool") }
        XCTAssertEqual(stated.rule.startDate, "2026-10-10")
        XCTAssertEqual(stated.endTime, "15:30")
        XCTAssertFalse(stated.dateWasAssumed || stated.durationWasAssumed)
    }
}

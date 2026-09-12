import XCTest
@testable import AssistantKit
import AssistantMocks

/// The three gaps the first live run exposed: an invented duration, an
/// unconsulted place list, and a lowercase title. Each fix has to be visible
/// to the user, not just correct.
final class AssumptionTests: XCTestCase {
    private var household: MockHousehold!
    private var router: ToolRouter!

    override func setUp() {
        super.setUp()
        household = Fixtures.household()
        router = ToolRouter(query: household)
    }

    private func call(_ arguments: [String: Any]) -> RawToolCall {
        let data = try! JSONSerialization.data(withJSONObject: arguments, options: [.sortedKeys])
        return RawToolCall(callID: "c1", name: "preview_create_events", argumentsJSON: String(data: data, encoding: .utf8)!)
    }

    private func create(
        title: String = "swimming",
        start: String = "16:00",
        end: Any = NSNull(),
        place: Any = NSNull(),
        kind: String = "practice"
    ) -> [String: Any] {
        [
            "title": title, "start_date": "2026-09-15",
            "start_time": start, "end_time": end,
            "location_name": place, "kind": kind,
            "child_ids": [], "owner_id": NSNull(),
            "repeat_mode": "none", "weekdays": [],
            "week_count": NSNull(), "end_date": NSNull()
        ]
    }

    private func card(_ outcome: ToolOutcome) throws -> ProposalCard {
        for card in outcome.cards { if case .proposal(let c) = card { return c } }
        throw XCTSkip("no proposal card")
    }

    // MARK: - 1. Duration

    func testAMissingEndTimeUsesTheAppsDefaultForThatKind() throws {
        let validated = try ToolArgumentParser.validate(call(create(kind: "practice")))
        guard case .previewCreateEvents(let args) = validated else { return XCTFail("wrong case") }

        // A practice is 90 minutes in the app's table.
        XCTAssertEqual(args.endTime, "17:30")
        XCTAssertTrue(args.durationWasAssumed)
    }

    func testEachKindGetsItsOwnDefault() throws {
        let expected: [(String, String)] = [
            ("pickup", "16:30"),    // 30
            ("lesson", "16:45"),    // 45
            ("practice", "17:30"),  // 90
            ("clinic", "17:00"),    // 60
            ("play", "18:00")       // 120
        ]
        for (kind, end) in expected {
            let validated = try ToolArgumentParser.validate(call(create(kind: kind)))
            guard case .previewCreateEvents(let args) = validated else { return XCTFail("wrong case") }
            XCTAssertEqual(args.endTime, end, kind)
        }
    }

    func testAStatedEndTimeIsNotOverridden() throws {
        let validated = try ToolArgumentParser.validate(call(create(end: "16:20")))
        guard case .previewCreateEvents(let args) = validated else { return XCTFail("wrong case") }

        XCTAssertEqual(args.endTime, "16:20")
        XCTAssertFalse(args.durationWasAssumed)
    }

    func testADefaultThatWouldCrossMidnightIsRefusedNotClamped() {
        // 23:30 plus a 90-minute practice lands on the next day, which the
        // record format cannot express.
        XCTAssertThrowsError(try ToolArgumentParser.validate(call(create(start: "23:30", kind: "practice"))))
    }

    func testTheAssumedDurationIsStatedOnTheReview() async throws {
        let validated = try ToolArgumentParser.validate(call(create()))
        let outcome = try await router.run(validated, in: Fixtures.session)
        let card = try card(outcome)

        let line = try XCTUnwrap(card.assumptions.first { $0.contains("No end time") })
        XCTAssertTrue(line.contains("90 minutes"), line)
        XCTAssertTrue(line.contains("17:30"), line)
        // The internal category name is not user-facing copy.
        XCTAssertFalse(line.contains("other"), line)
    }

    // MARK: - 2. Saved places

    func testFallingBackToHomeIsStatedAndListsTheAlternatives() async throws {
        let validated = try ToolArgumentParser.validate(call(create(place: NSNull())))
        let outcome = try await router.run(validated, in: Fixtures.session)
        let card = try card(outcome)

        let line = try XCTUnwrap(card.assumptions.first { $0.contains("No place was named") })
        XCTAssertTrue(line.contains("at Home"), line)
        // The user can see what they could have picked instead.
        XCTAssertTrue(line.contains("Eastside Pool"), line)
        XCTAssertFalse(line.contains("Home,"), "home should not be offered as an alternative to itself")
    }

    func testANamedPlaceProducesNoAssumption() async throws {
        let validated = try ToolArgumentParser.validate(call(create(place: "Eastside Pool")))
        let outcome = try await router.run(validated, in: Fixtures.session)
        let card = try card(outcome)

        XCTAssertEqual(card.rows.first?.locationName, "Eastside Pool")
        XCTAssertFalse(card.assumptions.contains { $0.contains("No place") })
    }

    func testPlaceMatchingIsCaseInsensitiveButStoresTheSavedSpelling() async throws {
        let validated = try ToolArgumentParser.validate(call(create(place: "eastside POOL")))
        let outcome = try await router.run(validated, in: Fixtures.session)
        XCTAssertEqual(try card(outcome).rows.first?.locationName, "Eastside Pool")
    }

    func testTheKindSchemaExplainsWhichValueToPick() {
        guard case .object(_, let properties) = ToolCatalog.definition(for: .previewCreateEvents).parameters,
              let kind = properties.first(where: { $0.0 == "kind" })?.1 else {
            return XCTFail("no kind property")
        }
        let description = kind.json["description"] as? String ?? ""
        // The enum values alone do not say that swimming is a "practice", and
        // getting this wrong changes both the category and the duration.
        XCTAssertTrue(description.contains("swimming"), description)
        XCTAssertTrue(description.contains("other only when"), description)
    }

    func testTheInstructionTellsTheModelToLookPlacesUp() {
        let text = Instructions.text(for: Fixtures.session, planning: Fixtures.planning)
        XCTAssertTrue(text.contains("list_saved_places"))
        XCTAssertTrue(text.contains("end_time null"))
    }

    // MARK: - 3. Title casing

    func testALowercaseTitleIsCapitalised() throws {
        let validated = try ToolArgumentParser.validate(call(create(title: "swimming")))
        guard case .previewCreateEvents(let args) = validated else { return XCTFail("wrong case") }
        XCTAssertEqual(args.title, "Swimming")
    }

    func testDeliberateCasingSurvives() {
        XCTAssertEqual(TitleNormalizer.normalize("iPad setup"), "iPad setup")
        XCTAssertEqual(TitleNormalizer.normalize("LEGO club"), "LEGO club")
        XCTAssertEqual(TitleNormalizer.normalize("School pickup"), "School pickup")
    }

    func testOnlyTheFirstWordIsTouched() {
        // Sentence case, matching how the household's own events are written.
        XCTAssertEqual(TitleNormalizer.normalize("theo soccer practice"), "Theo soccer practice")
    }

    func testWhitespaceIsTidied() {
        XCTAssertEqual(TitleNormalizer.normalize("  swim   team  "), "Swim team")
        XCTAssertEqual(TitleNormalizer.normalize(""), "")
    }

    // MARK: - The model is told what the app filled in

    func testThePayloadReportsTheDefaultsSoTheModelCannotRestateThem() async throws {
        let validated = try ToolArgumentParser.validate(call(create()))
        let outcome = try await router.run(validated, in: Fixtures.session)

        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(outcome.modelPayload.utf8)) as? [String: Any])
        XCTAssertEqual(root["end_time"] as? String, "17:30")
        XCTAssertEqual(root["place"] as? String, "Home")
        XCTAssertEqual((root["app_supplied_defaults"] as? [String])?.count, 2)
    }
}

import XCTest
@testable import AssistantKit
import AssistantMocks

/// Prose is allowed now, so the guarantee moved: the assistant may phrase
/// things itself, but it may not assert a figure the app did not compute.
final class ProseTests: XCTestCase {
    private let evidence = ["{\"total_matches\":12,\"events\":[{\"date\":\"2026-09-15\",\"start\":\"16:00\"}]}"]

    // MARK: - Grounding

    func testPlainSentencesPass() {
        for line in [
            "Here's what's on this week.",
            "Alex has the school run most days.",
            "Nothing's saved until you confirm."
        ] {
            XCTAssertEqual(ProseValidator.validate(line, evidence: evidence), .accepted(line), line)
        }
    }

    func testAFigureFromTheToolOutputPasses() {
        XCTAssertNotNil(ProseValidator.validate("You've got 12 on this week.", evidence: evidence).text)
        XCTAssertNotNil(ProseValidator.validate("First one is Sep 15 at 16:00.", evidence: evidence).text)
    }

    func testAnInventedFigureIsRejected() {
        // find_events returned 12. Saying 14 is the failure that matters.
        XCTAssertEqual(
            ProseValidator.validate("You've got 14 on this week.", evidence: evidence),
            .rejected(.ungroundedNumber("14"))
        )
    }

    func testNumbersAreRefusedWhenNothingWasLookedUp() {
        XCTAssertEqual(
            ProseValidator.validate("You have 3 things today.", evidence: []),
            .rejected(.numericWithoutEvidence("3"))
        )
        // A greeting is fine with no evidence, because it claims nothing.
        XCTAssertNotNil(ProseValidator.validate("Hi, what would you like to look at?", evidence: []).text)
    }

    func testLeadingZerosAndDateFormsCompareEqual() {
        XCTAssertEqual(ProseValidator.numbers(in: "at 09:05"), ["9", "5"])
        XCTAssertEqual(ProseValidator.numbers(in: "2026-09-15"), ["2026", "9", "15"])
        // So "Sep 9" grounds against a payload containing "2026-09-09".
        XCTAssertNotNil(
            ProseValidator.validate("Starts Sep 9.", evidence: ["{\"date\":\"2026-09-09\"}"]).text
        )
    }

    func testEmptyAndOverlongAreRejected() {
        XCTAssertEqual(ProseValidator.validate(nil, evidence: evidence), .rejected(.empty))
        XCTAssertEqual(ProseValidator.validate("   ", evidence: evidence), .rejected(.empty))
        let long = String(repeating: "a", count: ProseValidator.maxLength + 1)
        XCTAssertEqual(ProseValidator.validate(long, evidence: evidence), .rejected(.tooLong(long.count)))
    }

    func testControlCharactersAreStripped() {
        let text = ProseValidator.validate("Here's\u{0007} what's\n\non.", evidence: evidence).text
        XCTAssertEqual(text, "Here's what's on.")
    }

    // MARK: - End to end

    private func engine(_ client: LunaClient, _ household: MockHousehold) -> AssistantEngine {
        AssistantEngine(
            client: client,
            router: ToolRouter(query: household),
            proposals: ProposalStore(query: household, command: household),
            query: household,
            configuration: AssistantConfiguration(relayBaseURL: URL(string: "https://relay.invalid")!)
        )
    }

    private func summary(_ cards: [AssistantCard]) -> String? {
        for card in cards { if case .summary(let s) = card { return s.text } }
        return nil
    }

    func testTheModelsOwnWordingIsShownWhenItHoldsUp() async {
        let household = Fixtures.household()
        let client = ProgrammedLunaClient(replies: [
            ProgrammedLunaClient.toolCall("find_events", [
                "start_date": "2026-09-07", "end_date": "2026-09-13", "person_ids": [],
                "categories": [], "only_unassigned": false, "text_contains": NSNull()
            ]),
            .final(FinalDecision(
                outcome: .result, resultTemplate: .foundEvents,
                message: "Busy one \u{2014} the school run every day and soccer on Wednesday."
            ))
        ])
        let turn = await engine(client, household).send("what's on?", in: Fixtures.session)
        XCTAssertEqual(summary(turn.cards), "Busy one \u{2014} the school run every day and soccer on Wednesday.")
    }

    func testAnInventedCountFallsBackToTheAppsSentence() async {
        let household = Fixtures.household()
        let client = ProgrammedLunaClient(replies: [
            ProgrammedLunaClient.toolCall("find_events", [
                "start_date": "2026-09-07", "end_date": "2026-09-13", "person_ids": [],
                "categories": [], "only_unassigned": false, "text_contains": NSNull()
            ]),
            // There are 12 that week.
            .final(FinalDecision(outcome: .result, resultTemplate: .foundEvents, message: "You have 97 events this week."))
        ])
        let turn = await engine(client, household).send("what's on?", in: Fixtures.session)

        XCTAssertEqual(summary(turn.cards), "12 events in Sep 7\u{2013}Sep 13.")
        XCTAssertFalse(summary(turn.cards)?.contains("97") ?? true)
        // The card is untouched either way.
        XCTAssertTrue(turn.cards.contains { if case .eventList = $0 { return true }; return false })
    }

    func testConverseStillCannotAssertScheduleFacts() async {
        let household = Fixtures.household()
        let client = ProgrammedLunaClient(replies: [
            .final(FinalDecision(outcome: .converse, message: "Morning! You've got 5 things on today."))
        ])
        let turn = await engine(client, household).send("morning", in: Fixtures.session)

        XCTAssertTrue(turn.executedTools.isEmpty)
        XCTAssertNil(summary(turn.cards))
        XCTAssertTrue(turn.cards.contains { if case .refusal = $0 { return true }; return false })
    }

    func testAGreetingGetsAConversationalReplyNotARefusal() async {
        let household = Fixtures.household()
        let turn = await engine(ScriptedLunaClient(), household).send("hi", in: Fixtures.session)

        XCTAssertTrue(turn.executedTools.isEmpty)
        XCTAssertNotNil(summary(turn.cards))
        XCTAssertFalse(turn.cards.contains { if case .refusal = $0 { return true }; return false })
    }

    func testOffScopeIsStillRefusedHoweverItIsWorded() async {
        let household = Fixtures.household()
        let client = ProgrammedLunaClient(replies: [
            .final(FinalDecision(
                outcome: .refuse, refusalReason: .generalKnowledge,
                message: "That's outside what I can see here."
            ))
        ])
        let turn = await engine(client, household).send("weather in Paris?", in: Fixtures.session)

        guard case .refusal(let card)? = turn.cards.first else { return XCTFail("expected a refusal") }
        // The model's wording, but still a refusal, and the capability list is
        // app-owned rather than something the model made up.
        XCTAssertEqual(card.text, "That's outside what I can see here.")
        XCTAssertEqual(card.suggestions, AssistantCopy.capabilities)
    }

    func testProseCannotSubstituteForHavingLookedAnythingUp() async {
        let household = Fixtures.household()
        let client = ProgrammedLunaClient(replies: [
            .final(FinalDecision(outcome: .result, resultTemplate: .foundEvents, message: "Looks like a quiet week."))
        ])
        let turn = await engine(client, household).send("what's on?", in: Fixtures.session)

        // No operation ran, so there is nothing to narrate - still a refusal.
        XCTAssertTrue(turn.cards.contains { if case .refusal = $0 { return true }; return false })
        XCTAssertNil(summary(turn.cards))
    }
}

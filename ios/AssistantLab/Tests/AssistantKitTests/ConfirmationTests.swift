import XCTest
@testable import AssistantKit
import AssistantMocks

/// A04: reviewed, idempotent actions, and what happens when the schedule moves
/// underneath one.
final class ConfirmationTests: XCTestCase {
    private var household: MockHousehold!
    private var clock: Date!

    override func setUp() {
        super.setUp()
        household = Fixtures.household()
        clock = Date(timeIntervalSince1970: 1_789_000_000)
    }

    private func makeEngine() -> (AssistantEngine, ProposalStore) {
        let now: @Sendable () -> Date = { [self] in clock }
        let store = ProposalStore(query: household, command: household, now: now)
        let engine = AssistantEngine(
            client: ScriptedLunaClient(),
            router: ToolRouter(query: household, now: now),
            proposals: store,
            query: household,
            configuration: AssistantConfiguration(relayBaseURL: URL(string: "https://relay.invalid")!),
            now: now
        )
        return (engine, store)
    }

    private func receipt(_ cards: [AssistantCard]) -> ReceiptCard? {
        for card in cards { if case .receipt(let r) = card { return r } }
        return nil
    }

    private func failureReason(_ cards: [AssistantCard]) -> FailureCard.Reason? {
        for card in cards { if case .failure(let f) = card { return f.reason } }
        return nil
    }

    // MARK: - The plan's worked examples

    func testThirtyWeekSeriesIsReviewedThenCreated() async throws {
        let (engine, _) = makeEngine()
        let before = household.snapshot(household: Fixtures.householdID).count

        let review = await engine.send("Schedule swimming every Tuesday at 4pm for 30 weeks", in: Fixtures.session)
        let proposalID = try XCTUnwrap(review.pendingProposalID)

        // Nothing is written by the review itself.
        XCTAssertEqual(household.snapshot(household: Fixtures.householdID).count, before)
        guard case .proposal(let card)? = review.cards.first(where: { if case .proposal = $0 { return true }; return false }) else {
            return XCTFail("expected a review card")
        }
        XCTAssertEqual(card.affectedCount, 30)
        XCTAssertEqual(card.ruleDescription, "Every Tuesday for 30 weeks")
        XCTAssertEqual(card.rows.first?.date, "2026-09-15")
        XCTAssertEqual(card.rows.last?.date, "2027-04-06")
        XCTAssertTrue(card.destinationNote.contains("not sent to an external calendar"))

        let confirmed = await engine.confirm(proposalID: proposalID, in: Fixtures.session)
        let receipt = try XCTUnwrap(receipt(confirmed.cards))
        XCTAssertEqual(receipt.headline, "Added 30 events")
        XCTAssertEqual(household.snapshot(household: Fixtures.householdID).count, before + 30)

        let created = household.snapshot(household: Fixtures.householdID).filter { $0.title == "Swimming" }
        XCTAssertEqual(created.count, 30)
        XCTAssertEqual(Set(created.map(\.seriesId)).count, 1, "one series id across the set")
        XCTAssertTrue(created.allSatisfy { $0.time == "16:00" && $0.location == "Eastside Pool" })
    }

    func testAssigningNextWeeksPickupsResolvesARealCaregiver() async throws {
        let (engine, _) = makeEngine()
        let review = await engine.send("Assign next week's pickups to Alex", in: Fixtures.session)
        let proposalID = try XCTUnwrap(review.pendingProposalID)

        guard case .proposal(let card)? = review.cards.first(where: { if case .proposal = $0 { return true }; return false }) else {
            return XCTFail("expected a review card")
        }
        XCTAssertEqual(card.affectedCount, 5)
        XCTAssertEqual(card.headline, "Assign 5 events to Alex")

        _ = await engine.confirm(proposalID: proposalID, in: Fixtures.session)
        let pickups = household.snapshot(household: Fixtures.householdID).filter {
            $0.title == "School pickup" && $0.date >= "2026-09-14" && $0.date <= "2026-09-18"
        }
        XCTAssertEqual(pickups.count, 5)
        XCTAssertTrue(pickups.allSatisfy { $0.owner == "Alex" })
        // Revisions moved, so a second stale review cannot silently reapply.
        XCTAssertTrue(pickups.allSatisfy { $0.revision == 2 })
    }

    // MARK: - Idempotency

    func testDuplicateConfirmationCannotDoubleCreate() async throws {
        let (engine, _) = makeEngine()
        let review = await engine.send("Schedule karate every Thursday at 17:00 for 4 weeks", in: Fixtures.session)
        let proposalID = try XCTUnwrap(review.pendingProposalID)

        let first = await engine.confirm(proposalID: proposalID, in: Fixtures.session)
        let applyCountAfterFirst = household.applyCount
        let second = await engine.confirm(proposalID: proposalID, in: Fixtures.session)

        XCTAssertEqual(household.applyCount, applyCountAfterFirst, "the store was written twice")
        XCTAssertEqual(household.snapshot(household: Fixtures.householdID).filter { $0.title == "Karate" }.count, 4)
        // The repeat tells the truth: it succeeded, and here is that outcome.
        XCTAssertEqual(receipt(first.cards)?.headline, receipt(second.cards)?.headline)
    }

    func testRetryAfterATransportFailureAppliesExactlyOnce() async throws {
        let (engine, _) = makeEngine()
        let review = await engine.send("Schedule karate every Thursday at 17:00 for 4 weeks", in: Fixtures.session)
        let proposalID = try XCTUnwrap(review.pendingProposalID)

        household.nextWriteError = .transportFailed(reason: "connection lost")
        let failed = await engine.confirm(proposalID: proposalID, in: Fixtures.session)
        XCTAssertEqual(failureReason(failed.cards), .saveFailed)
        XCTAssertTrue(household.snapshot(household: Fixtures.householdID).filter { $0.title == "Karate" }.isEmpty)

        let retried = await engine.confirm(proposalID: proposalID, in: Fixtures.session)
        XCTAssertNotNil(receipt(retried.cards))
        XCTAssertEqual(household.snapshot(household: Fixtures.householdID).filter { $0.title == "Karate" }.count, 4)
    }

    // MARK: - Staleness

    func testAnEventEditedElsewhereForcesAFreshReview() async throws {
        let (engine, _) = makeEngine()
        let review = await engine.send("Assign next week's pickups to Alex", in: Fixtures.session)
        let proposalID = try XCTUnwrap(review.pendingProposalID)

        // The other phone edits one of the same rows.
        household.bumpRevision(eventID: "evt-school-pick-2026-09-16", household: Fixtures.householdID)

        let turn = await engine.confirm(proposalID: proposalID, in: Fixtures.session)
        XCTAssertEqual(failureReason(turn.cards), .proposalStale)
        // Nothing partially applied.
        let pickups = household.snapshot(household: Fixtures.householdID).filter {
            $0.title == "School pickup" && $0.date >= "2026-09-14" && $0.date <= "2026-09-18"
        }
        XCTAssertTrue(pickups.allSatisfy { $0.owner == "TBD" })
    }

    func testADeletedEventForcesAFreshReview() async throws {
        let (engine, _) = makeEngine()
        let review = await engine.send("Assign next week's pickups to Alex", in: Fixtures.session)
        let proposalID = try XCTUnwrap(review.pendingProposalID)

        household.delete(eventID: "evt-school-pick-2026-09-16", household: Fixtures.householdID)

        let turn = await engine.confirm(proposalID: proposalID, in: Fixtures.session)
        XCTAssertEqual(failureReason(turn.cards), .proposalStale)
        XCTAssertEqual(household.applyCount, 0)
    }

    // MARK: - Expiry and cancel

    func testAnExpiredReviewCannotBeApplied() async throws {
        let (engine, _) = makeEngine()
        let review = await engine.send("Schedule karate every Thursday at 17:00 for 4 weeks", in: Fixtures.session)
        let proposalID = try XCTUnwrap(review.pendingProposalID)

        clock = clock.addingTimeInterval(ProposalStore.lifetime + 1)

        let turn = await engine.confirm(proposalID: proposalID, in: Fixtures.session)
        XCTAssertEqual(failureReason(turn.cards), .proposalExpired)
        XCTAssertEqual(household.applyCount, 0)
    }

    func testCancelLeavesTheHouseholdUntouched() async throws {
        let (engine, _) = makeEngine()
        let before = household.snapshot(household: Fixtures.householdID)
        let review = await engine.send("Schedule karate every Thursday at 17:00 for 4 weeks", in: Fixtures.session)
        let proposalID = try XCTUnwrap(review.pendingProposalID)

        await engine.cancelProposal(proposalID)
        let turn = await engine.confirm(proposalID: proposalID, in: Fixtures.session)

        XCTAssertEqual(failureReason(turn.cards), .proposalExpired)
        XCTAssertEqual(household.snapshot(household: Fixtures.householdID), before)
        XCTAssertEqual(household.applyCount, 0)
    }

    func testAReviewCannotBeAppliedFromAnotherHousehold() async throws {
        let (engine, store) = makeEngine()
        let review = await engine.send("Schedule karate every Thursday at 17:00 for 4 weeks", in: Fixtures.session)
        let proposalID = try XCTUnwrap(review.pendingProposalID)

        do {
            _ = try await store.confirm(proposalID, in: Fixtures.otherSession)
            XCTFail("expected a refusal")
        } catch {
            XCTAssertEqual(error as? ConfirmationError, .wrongHousehold)
        }
        XCTAssertEqual(household.applyCount, 0)
    }

    // MARK: - Honest reporting

    func testAPendingSyncIsNotReportedAsSynced() async throws {
        let (engine, _) = makeEngine()
        household.cloudReachable = false

        let review = await engine.send("Schedule karate every Thursday at 17:00 for 4 weeks", in: Fixtures.session)
        let proposalID = try XCTUnwrap(review.pendingProposalID)
        let confirmed = await engine.confirm(proposalID: proposalID, in: Fixtures.session)

        let receipt = try XCTUnwrap(receipt(confirmed.cards))
        XCTAssertEqual(receipt.syncLabel, "Saved on this device \u{2014} sync pending")
        XCTAssertEqual(receipt.externalCalendarLabel, "Saved in HeliPad only \u{2014} not sent to an external calendar")
    }

    // MARK: - Conflicts

    func testAConflictIsShownRatherThanResolved() async throws {
        let (engine, _) = makeEngine()
        // Soccer already runs 17:30-19:00 on Wednesdays for Theo, and the
        // household protects the dinner hour from 18:30.
        let review = await engine.send("Schedule basketball for Theo every Wednesday at 18:00 for 3 weeks", in: Fixtures.session)

        guard case .proposal(let card)? = review.cards.first(where: { if case .proposal = $0 { return true }; return false }) else {
            return XCTFail("expected a review card")
        }
        XCTAssertFalse(card.conflicts.isEmpty)
        XCTAssertTrue(card.conflicts.contains { $0.cause == .childDoubleBooked })
        XCTAssertTrue(card.conflicts.contains { $0.cause == .dinnerWindow })

        // The conflicting occurrences are still in the review, not dropped.
        XCTAssertEqual(card.affectedCount, 3)

        // The conflicts themselves are app-computed and on the card, which is
        // what has to be true regardless of how the model words its sentence.
        XCTAssertTrue(card.conflicts.allSatisfy { !$0.detail.isEmpty })
        guard case .summary(let summary)? = review.cards.first else { return XCTFail("expected a summary") }
        XCTAssertFalse(summary.text.isEmpty)
    }
}

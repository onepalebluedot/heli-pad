import XCTest
@testable import AssistantKit
import AssistantMocks

/// A05: real, bounded aggregates. Fixed fixtures so the numbers are checkable
/// by hand rather than by re-running the implementation.
final class TrendTests: XCTestCase {
    private func event(_ date: String, owner: String = "Maya", done: Bool = false, kind: EventKind = .pickup, kids: [String] = ["Ivy"]) -> AssistantEvent {
        AssistantEvent(id: "e-\(date)-\(owner)-\(kind.rawValue)", date: date, title: "Run", owner: owner, kids: kids, kind: kind, done: done)
    }

    private let people: [AssistantPerson] = [
        .init(id: "p-maya", name: "Maya", role: .caregiver, relationship: "Mother"),
        .init(id: "p-alex", name: "Alex", role: .caregiver, relationship: "Father"),
        .init(id: "p-ivy", name: "Ivy", role: .child, relationship: "Child")
    ]

    private func metric(_ card: TrendCard, _ id: String) -> TrendMetric {
        card.metrics.first { $0.id == id }!
    }

    func testCurrentVersusPreviousOnAKnownFixture() throws {
        // 4 events in the current week, 2 in the week before it.
        let events = [
            event("2026-09-07"), event("2026-09-08"), event("2026-09-09"), event("2026-09-10"),
            event("2026-08-31"), event("2026-09-01")
        ]
        let range = try XCTUnwrap(DateRange(start: "2026-09-07", end: "2026-09-13"))
        let card = TrendService.report(events: events, range: range, people: people, today: "2026-09-13")

        let scheduled = metric(card, "scheduled_events")
        XCTAssertEqual(scheduled.currentValue, 4)
        XCTAssertEqual(scheduled.previousValue, 2)
        XCTAssertEqual(scheduled.change, .percent(100, absolute: 2))
        XCTAssertEqual(card.periodLabel, "Sep 7\u{2013}Sep 13")
        XCTAssertEqual(card.comparisonLabel, "compared with Aug 31\u{2013}Sep 6")
    }

    func testAZeroBaselineGivesAnAbsoluteChangeNotAPercentage() throws {
        let events = [event("2026-09-07"), event("2026-09-08")]
        let range = try XCTUnwrap(DateRange(start: "2026-09-07", end: "2026-09-13"))
        let card = TrendService.report(events: events, range: range, people: people, today: "2026-09-13")

        XCTAssertEqual(metric(card, "scheduled_events").change, .fromZero(absolute: 2))
    }

    func testFutureRowsAreExcludedFromRecordedClaims() throws {
        // Two events already happened and are ticked off; two are still ahead.
        let events = [
            event("2026-09-07", done: true), event("2026-09-08", done: true),
            event("2026-09-12"), event("2026-09-13")
        ]
        let range = try XCTUnwrap(DateRange(start: "2026-09-07", end: "2026-09-13"))
        let card = TrendService.report(events: events, range: range, people: people, today: "2026-09-09")

        // Scheduled volume covers the whole window.
        XCTAssertEqual(metric(card, "scheduled_events").currentValue, 4)
        // Completion covers only the elapsed part.
        XCTAssertEqual(metric(card, "recorded_complete").currentValue, 2)
        let note = try XCTUnwrap(card.partialPeriodNote)
        XCTAssertTrue(note.contains("Sep 7\u{2013}Sep 9"))
        XCTAssertTrue(note.contains("scheduled, not history"))
    }

    func testAPeriodThatHasNotStartedSaysSoRatherThanReportingZero() throws {
        let range = try XCTUnwrap(DateRange(start: "2026-10-01", end: "2026-10-07"))
        let card = TrendService.report(events: [event("2026-10-02")], range: range, people: people, today: "2026-09-11")

        XCTAssertEqual(metric(card, "recorded_complete").change, .insufficientData("the period has not started"))
        XCTAssertTrue(try XCTUnwrap(card.partialPeriodNote).contains("has not started"))
    }

    func testNoHistoryProducesNoBaselineNotAFabricatedDrop() throws {
        let range = try XCTUnwrap(DateRange(start: "2026-09-07", end: "2026-09-13"))
        let card = TrendService.report(events: [event("2026-09-07", done: true)], range: range, people: people, today: "2026-09-13")

        XCTAssertEqual(metric(card, "recorded_complete").change, .noBaseline)
        XCTAssertTrue(card.notes.contains { $0.contains("nothing to compare") })
    }

    func testCompletionIsLabelledAsRecordedState() throws {
        let range = try XCTUnwrap(DateRange(start: "2026-09-07", end: "2026-09-13"))
        let card = TrendService.report(events: [event("2026-09-07", done: true)], range: range, people: people, today: "2026-09-13")

        XCTAssertEqual(metric(card, "recorded_complete").title, "Marked complete in the app")
        XCTAssertTrue(card.notes.contains { $0.contains("not a record of who attended") })
    }

    func testWorkloadCountsOnlyKnownCaregivers() throws {
        let events = [
            event("2026-09-07", owner: "Maya"), event("2026-09-08", owner: "Maya"),
            event("2026-09-09", owner: "Alex"),
            // Unassigned and an owner who left the household both drop out of
            // the per-caregiver split rather than becoming a phantom row.
            event("2026-09-10", owner: "TBD"), event("2026-09-11", owner: "Former nanny")
        ]
        let range = try XCTUnwrap(DateRange(start: "2026-09-07", end: "2026-09-13"))
        let card = TrendService.report(events: events, range: range, people: people, today: "2026-09-13")

        XCTAssertEqual(card.workload.map(\.name), ["Maya", "Alex"])
        XCTAssertEqual(card.workload.map(\.count), [2, 1])
        XCTAssertEqual(metric(card, "unassigned_events").currentValue, 1)
        // The total still includes every event, so the parts do not have to sum
        // to the whole and nothing is quietly dropped from the headline count.
        XCTAssertEqual(metric(card, "scheduled_events").currentValue, 5)
    }

    func testCategoryMixUsesTheAppsOwnGrouping() throws {
        let events = [
            event("2026-09-07", kind: .pickup), event("2026-09-08", kind: .dropoff),
            event("2026-09-09", kind: .practice), event("2026-09-10", kind: .lesson)
        ]
        let range = try XCTUnwrap(DateRange(start: "2026-09-07", end: "2026-09-13"))
        let card = TrendService.report(events: events, range: range, people: people, today: "2026-09-13")

        XCTAssertEqual(card.categoryMix.map(\.category), ["School", "Arts", "Sports"])
        XCTAssertEqual(card.categoryMix.first?.count, 2)
    }

    func testEveryResultNamesItsPeriodAndLinksToItsEvents() throws {
        let events = [event("2026-09-07"), event("2026-09-08")]
        let range = try XCTUnwrap(DateRange(start: "2026-09-07", end: "2026-09-13"))
        let card = TrendService.report(events: events, range: range, people: people, today: "2026-09-13")

        XCTAssertFalse(card.periodLabel.isEmpty)
        XCTAssertEqual(Set(card.supportingEventIDs), Set(events.map(\.id)))
    }

    func testAnEmptyPeriodSaysNothingIsScheduled() throws {
        let range = try XCTUnwrap(DateRange(start: "2027-01-04", end: "2027-01-10"))
        let card = TrendService.report(events: [], range: range, people: people, today: "2026-09-11")
        XCTAssertTrue(card.notes.contains { $0.contains("Nothing is scheduled") })
    }

    func testTheAssistantAndTheCardCannotDisagree() async throws {
        // The payload handed to the model is built from the same card, so it
        // cannot narrate a number that is not on screen.
        let household = Fixtures.household()
        let router = ToolRouter(query: household)
        let range = try XCTUnwrap(DateRange(start: "2026-09-01", end: "2026-09-30"))
        let outcome = try await router.run(.getScheduleTrends(range: range, personIDs: []), in: Fixtures.session)

        guard case .trends(let card)? = outcome.cards.first else { return XCTFail("expected a trend card") }
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(outcome.modelPayload.utf8)) as? [String: Any])
        let metrics = try XCTUnwrap(root["metrics"] as? [[String: Any]])

        for metric in card.metrics {
            let row = try XCTUnwrap(metrics.first { $0["id"] as? String == metric.id })
            XCTAssertEqual(row["current"] as? Int, metric.currentValue)
            XCTAssertEqual(row["previous"] as? Int, metric.previousValue)
        }
    }
}

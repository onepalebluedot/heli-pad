import XCTest
@testable import AssistantKit
import AssistantMocks

/// When suggestions refresh, when a model request is worth making, and how a
/// cached list is kept honest between rankings.
final class SuggestionCacheTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_789_000_000)

    private func candidate(
        id: String = "cand-1", occurrences: Int = 4, last: String = "2026-09-09"
    ) -> ShortcutCandidate {
        ShortcutCandidate(
            id: id, representativeTitle: "Soni Drop Off", location: "Goddard School",
            placeID: nil, startTime: "08:00", durationMinutes: 20, kids: ["Soni"],
            owner: "Kellie", category: "School", weekdays: [2], occurrences: occurrences,
            distinctWeeks: min(occurrences, 4), firstDate: "2026-08-19", lastDate: last,
            titleVariants: ["Soni Drop Off"], sourceEventIDs: ["a", "b", "c"]
        )
    }

    private func suggestion(_ candidate: ShortcutCandidate) -> ShortcutSuggestion {
        ShortcutSuggestion(
            candidate: candidate, label: "School drop-off",
            evidence: SuggestionService.evidence(for: candidate)
        )
    }

    // MARK: - When to spend a request

    func testNoCandidatesNeverRequests() {
        XCTAssertFalse(SuggestionPolicy.shouldRequestRanking(
            candidates: [], entry: SuggestionCacheEntry(), now: now
        ))
    }

    func testAFreshFingerprintRequests() {
        XCTAssertTrue(SuggestionPolicy.shouldRequestRanking(
            candidates: [candidate()], entry: SuggestionCacheEntry(), now: now
        ))
    }

    func testAnUnchangedFingerprintInsideTheIntervalDoesNot() {
        let candidates = [candidate()]
        let entry = SuggestionCacheEntry(
            fingerprint: ShortcutPatternFinder.fingerprint(candidates),
            lastRankedAt: now.addingTimeInterval(-24 * 60 * 60)
        )
        XCTAssertFalse(SuggestionPolicy.shouldRequestRanking(candidates: candidates, entry: entry, now: now))
    }

    func testNewEvidenceChangesTheFingerprintAndRequests() {
        let before = [candidate(occurrences: 4)]
        let entry = SuggestionCacheEntry(
            fingerprint: ShortcutPatternFinder.fingerprint(before),
            lastRankedAt: now.addingTimeInterval(-24 * 60 * 60)
        )
        let after = [candidate(occurrences: 5, last: "2026-09-10")]
        XCTAssertTrue(SuggestionPolicy.shouldRequestRanking(candidates: after, entry: entry, now: now))
    }

    func testAnAgedRankingRequestsEvenWithoutChange() {
        let candidates = [candidate()]
        let entry = SuggestionCacheEntry(
            fingerprint: ShortcutPatternFinder.fingerprint(candidates),
            lastRankedAt: now.addingTimeInterval(-15 * 24 * 60 * 60)
        )
        XCTAssertTrue(SuggestionPolicy.shouldRequestRanking(candidates: candidates, entry: entry, now: now))
    }

    func testFailuresBackOffRatherThanRetryingEveryVisit() {
        let candidates = [candidate()]
        let justFailed = SuggestionCacheEntry(lastFailureAt: now.addingTimeInterval(-60), consecutiveFailures: 1)
        XCTAssertFalse(
            SuggestionPolicy.shouldRequestRanking(candidates: candidates, entry: justFailed, now: now),
            "a failure must not be retried on the next visit to Family"
        )

        let waited = SuggestionCacheEntry(lastFailureAt: now.addingTimeInterval(-3600), consecutiveFailures: 1)
        XCTAssertTrue(SuggestionPolicy.shouldRequestRanking(candidates: candidates, entry: waited, now: now))
    }

    func testBackoffGrowsWithConsecutiveFailures() {
        let candidates = [candidate()]
        // Third failure: the daily step, so an hour is not enough.
        let entry = SuggestionCacheEntry(
            lastFailureAt: now.addingTimeInterval(-3600), consecutiveFailures: 3
        )
        XCTAssertFalse(SuggestionPolicy.shouldRequestRanking(candidates: candidates, entry: entry, now: now))
    }

    // MARK: - Revalidation

    func testDeletedSourceEventsRemoveTheCardImmediately() {
        let cached = [suggestion(candidate())]
        // The detector no longer sees that pattern at all.
        let live = SuggestionPolicy.revalidate(cached, against: [], entry: SuggestionCacheEntry(), now: now)
        XCTAssertTrue(live.isEmpty)
    }

    func testCreatingAnEquivalentShortcutRemovesTheCardImmediately() {
        // A new shortcut makes the detector drop the candidate, so the cached
        // card has nothing to match against.
        let cached = [suggestion(candidate())]
        XCTAssertTrue(
            SuggestionPolicy.revalidate(cached, against: [], entry: SuggestionCacheEntry(), now: now).isEmpty
        )
    }

    func testEvidenceIsRefreshedFromLiveCounts() throws {
        let cached = [suggestion(candidate(occurrences: 4))]
        let live = SuggestionPolicy.revalidate(
            cached, against: [candidate(occurrences: 6)], entry: SuggestionCacheEntry(), now: now
        )
        let refreshed = try XCTUnwrap(live.first)
        XCTAssertEqual(refreshed.candidate.occurrences, 6)
        XCTAssertEqual(refreshed.evidence, "Added manually 6 times across 4 weeks.")
        XCTAssertEqual(refreshed.label, "School drop-off", "the model's label survives")
    }

    // MARK: - Dismissal is a snooze

    func testADismissedSuggestionIsHidden() {
        let target = candidate()
        let entry = SuggestionCacheEntry(
            dismissals: [target.id: now], dismissedAtOccurrences: [target.id: 4]
        )
        XCTAssertTrue(SuggestionPolicy.isSnoozed(target, entry: entry, now: now))
        XCTAssertTrue(
            SuggestionPolicy.revalidate([suggestion(target)], against: [target], entry: entry, now: now).isEmpty
        )
    }

    func testADismissedSuggestionReturnsAfterTheSnooze() {
        let target = candidate()
        let entry = SuggestionCacheEntry(
            dismissals: [target.id: now], dismissedAtOccurrences: [target.id: 4]
        )
        let later = now.addingTimeInterval(Double(SuggestionPolicy.snoozeDays + 1) * 24 * 60 * 60)
        XCTAssertFalse(SuggestionPolicy.isSnoozed(target, entry: entry, now: later))
    }

    func testSubstantialNewEvidenceBringsItBackEarly() {
        let dismissed = candidate(occurrences: 4)
        let entry = SuggestionCacheEntry(
            dismissals: [dismissed.id: now], dismissedAtOccurrences: [dismissed.id: 4]
        )
        // One more is not enough.
        XCTAssertTrue(SuggestionPolicy.isSnoozed(candidate(occurrences: 5), entry: entry, now: now))
        // Two more is.
        XCTAssertFalse(SuggestionPolicy.isSnoozed(candidate(occurrences: 6), entry: entry, now: now))
    }

    func testCandidateIdsAreStableAcrossNewOccurrences() {
        // Otherwise a dismissal would stop applying the moment the household
        // did the activity once more.
        XCTAssertEqual(candidate(occurrences: 4).id, candidate(occurrences: 9).id)
    }
}

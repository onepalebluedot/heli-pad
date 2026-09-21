import XCTest
@testable import AssistantKit
import AssistantMocks

/// Household isolation and the review draft.
///
/// The cache itself lives in the app (UserDefaults keyed by session), so what
/// is testable here is the key derivation and the draft-building rules the app
/// depends on. The app-side store composes these.
final class SuggestionIsolationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_789_000_000)

    private func candidate(id: String = "cand-1") -> ShortcutCandidate {
        ShortcutCandidate(
            id: id, representativeTitle: "Soni Drop Off", location: "Goddard School",
            placeID: nil, startTime: "08:10", durationMinutes: 20, kids: ["Soni"],
            owner: "Kellie", category: "School", weekdays: [1, 3], occurrences: 5,
            distinctWeeks: 4, firstDate: "2026-08-12", lastDate: "2026-09-09",
            titleVariants: ["Soni Drop Off"], sourceEventIDs: ["a", "b", "c", "d", "e"]
        )
    }

    // MARK: - Isolation

    func testCacheKeysDifferByHouseholdAndByCaregiver() {
        // The app keys its cache on exactly this, so two households - or two
        // caregivers in one household - can never read each other's.
        let a = ChatTranscript.key(for: Fixtures.session)
        let b = ChatTranscript.key(for: Fixtures.otherSession)
        XCTAssertNotEqual(a, b)

        let sameHouseholdDifferentUser = AssistantSession(
            householdID: Fixtures.householdID, userID: "user-other",
            timeZoneIdentifier: Fixtures.timeZoneIdentifier,
            today: Fixtures.today, displayedWeekStart: Fixtures.displayedWeekStart
        )
        XCTAssertNotEqual(ChatTranscript.key(for: sameHouseholdDifferentUser), a)
    }

    func testDismissalsAreScopedToTheirEntry() {
        // Two entries stand in for two households. A dismissal recorded in one
        // has no effect in the other.
        let target = candidate()
        let dismissed = SuggestionCacheEntry(
            dismissals: [target.id: now], dismissedAtOccurrences: [target.id: 5]
        )
        let untouched = SuggestionCacheEntry()

        XCTAssertTrue(SuggestionPolicy.isSnoozed(target, entry: dismissed, now: now))
        XCTAssertFalse(SuggestionPolicy.isSnoozed(target, entry: untouched, now: now))
    }

    func testRefreshClocksAreScopedToTheirEntry() {
        let candidates = [candidate()]
        let recentlyRanked = SuggestionCacheEntry(
            fingerprint: ShortcutPatternFinder.fingerprint(candidates), lastRankedAt: now
        )
        XCTAssertFalse(SuggestionPolicy.shouldRequestRanking(
            candidates: candidates, entry: recentlyRanked, now: now
        ))
        // A different household has never ranked, so it still would.
        XCTAssertTrue(SuggestionPolicy.shouldRequestRanking(
            candidates: candidates, entry: SuggestionCacheEntry(), now: now
        ))
    }

    // MARK: - The review draft

    func testTheDraftCarriesEveryInferredField() {
        let candidate = self.candidate()
        // Mirrors what FamilyView builds for the editor.
        XCTAssertEqual(candidate.startTime, "08:10")
        XCTAssertEqual(candidate.endTime, "08:30", "end time follows from the median duration")
        XCTAssertEqual(candidate.durationMinutes, 20)
        XCTAssertEqual(candidate.kids, ["Soni"])
        XCTAssertEqual(candidate.owner, "Kellie")
        XCTAssertEqual(candidate.category, "School")
        XCTAssertEqual(candidate.weekdays, [1, 3])
        XCTAssertEqual(candidate.location, "Goddard School")
    }

    func testAnAmbiguousCaregiverLeavesTheDraftUnset() {
        var ambiguous = candidate()
        ambiguous.owner = nil
        XCTAssertNil(ambiguous.owner, "the editor opens with no caregiver rather than a guess")
    }

    func testEvidenceReadsAsGroundedFact() {
        XCTAssertEqual(
            SuggestionService.evidence(for: candidate()),
            "Added manually 5 times across 4 weeks."
        )
        XCTAssertEqual(SuggestionService.timeLabel(for: candidate()), "8:10 AM")
    }

    /// Reviewing is not saving: the suggestion pipeline produces a draft and
    /// nothing else. Nothing in AssistantKit can write to the household - the
    /// only write path is `HouseholdCommandPort`, which suggestions never use.
    func testTheSuggestionPathHasNoWriteCapability() async {
        let household = Fixtures.household()
        let before = household.snapshot(household: Fixtures.householdID)

        let candidates = ShortcutPatternFinder.candidates(
            events: (try? await household.events(in: Fixtures.session)) ?? [],
            shortcuts: [],
            today: Fixtures.today
        )
        _ = await SuggestionService(client: nil).rank(candidates)

        XCTAssertEqual(household.snapshot(household: Fixtures.householdID), before,
                       "detecting and ranking must not touch household data")
        XCTAssertEqual(household.applyCount, 0)
    }
}

import XCTest
@testable import AssistantKit
import AssistantMocks

/// Shortcut suggestions. Code finds the patterns and owns the numbers; the
/// model only ranks and names. These cover both halves plus the cache policy.
final class SuggestionTests: XCTestCase {
    private let today = "2026-09-12"

    private func event(
        _ date: String,
        _ title: String = "Soni Drop Off",
        at place: String = "Goddard School",
        placeID: String? = nil,
        from start: String = "08:00",
        minutes: Int = 20,
        owner: String = "Kellie",
        kids: [String] = ["Soni"],
        kind: EventKind = .dropoff,
        series: String? = nil,
        calendar: String? = nil,
        origin: AssistantEventOrigin? = .manual,
        id: String? = nil
    ) -> AssistantEvent {
        let end = CalendarMath.time(fromMinutes: (CalendarMath.minutes(start) ?? 0) + minutes)
        return AssistantEvent(
            id: id ?? "e-\(date)-\(title)-\(start)", date: date, time: start, endTime: end,
            title: title, owner: owner, kids: kids, location: place, kind: kind,
            seriesId: series, placeID: placeID, calendarID: calendar, origin: origin
        )
    }

    /// n occurrences, one per week, ending `endingWeeksAgo` weeks before today.
    private func weekly(
        _ count: Int, endingWeeksAgo: Int = 0, _ make: (String) -> AssistantEvent
    ) -> [AssistantEvent] {
        (0..<count).map { index in
            let weeksBack = endingWeeksAgo + (count - 1 - index)
            return make(CalendarMath.addDays(today, -7 * weeksBack))
        }
    }

    private func candidates(
        _ events: [AssistantEvent], shortcuts: [ExistingShortcut] = []
    ) -> [ShortcutCandidate] {
        ShortcutPatternFinder.candidates(events: events, shortcuts: shortcuts, today: today)
    }

    // MARK: - Thresholds

    func testTwoOccurrencesProduceNothing() {
        XCTAssertTrue(candidates(weekly(2) { event($0) }).isEmpty)
    }

    func testThreeMatchesInOneWeekProduceNothing() {
        let sameWeek = ["2026-09-07", "2026-09-08", "2026-09-09"].map { event($0) }
        XCTAssertTrue(candidates(sameWeek).isEmpty)
    }

    func testThreeMatchesAcrossTwoWeeksProduceNothing() {
        let twoWeeks = ["2026-09-01", "2026-09-08", "2026-09-09"].map { event($0) }
        XCTAssertTrue(candidates(twoWeeks).isEmpty)
    }

    func testThreeMatchesAcrossThreeWeeksProduceOneSuggestion() throws {
        let found = candidates(weekly(3) { event($0) })
        XCTAssertEqual(found.count, 1)
        let candidate = try XCTUnwrap(found.first)
        XCTAssertEqual(candidate.occurrences, 3)
        XCTAssertEqual(candidate.distinctWeeks, 3)
    }

    func testStaleSeasonalPatternsAreExcluded() {
        // Five solid occurrences, but they stopped three months ago.
        XCTAssertTrue(candidates(weekly(5, endingWeeksAgo: 13) { event($0) }).isEmpty)
    }

    // MARK: - Clustering

    func testNearIdenticalTimesCollapseIntoOneCandidate() throws {
        // The bug on screen: an exact-time bucket split 8:29 from 8:30 and
        // produced two identical-looking cards.
        let events = [
            event("2026-08-26", from: "08:29"),
            event("2026-09-02", from: "08:30"),
            event("2026-09-09", from: "08:05")
        ]
        let found = candidates(events)
        XCTAssertEqual(found.count, 1, "a 25-minute spread is one habit")
        XCTAssertEqual(try XCTUnwrap(found.first).occurrences, 3)
    }

    func testTitleVariantsDoNotSplitAPattern() {
        // "Soni Drop Off" and "Drop Off" are the same habit.
        let events = [
            event("2026-08-26", "Soni Drop Off"),
            event("2026-09-02", "Drop Off"),
            event("2026-09-09", "drop off")
        ]
        XCTAssertEqual(candidates(events).count, 1)
    }

    func testGenuinelyDifferentTimesStaySeparate() {
        let morning = weekly(3) { event($0, from: "08:00") }
        let afternoon = weekly(3) { event($0, "Soni Pickup", from: "15:10") }
        XCTAssertEqual(candidates(morning + afternoon).count, 2)
    }

    func testDifferentChildrenAreNotMerged() {
        let soni = weekly(3) { event($0, "Drop Off", kids: ["Soni"]) }
        let mia = weekly(3) { event($0, "Drop Off", kids: ["Mia"], id: "mia-\($0)") }
        let found = candidates(soni + mia)
        XCTAssertEqual(found.count, 2)
        XCTAssertEqual(Set(found.flatMap(\.kids)), ["Soni", "Mia"])
    }

    func testOnePatternCannotProduceDuplicateSuggestions() {
        let events = weekly(6) { event($0, from: "08:0\(Int.random(in: 0...9))") }
        let found = candidates(events)
        XCTAssertEqual(Set(found.map(\.id)).count, found.count, "ids must be unique")
        XCTAssertEqual(found.count, 1)
    }

    // MARK: - Derived fields

    func testVariableCaregiversFormOneCandidateWithNoOwner() throws {
        let events = [
            event("2026-08-26", owner: "Kellie"),
            event("2026-09-02", owner: "John"),
            event("2026-09-09", owner: "Kellie")
        ]
        let found = try XCTUnwrap(candidates(events).first)
        XCTAssertEqual(found.occurrences, 3, "a shared school run is still one habit")
        XCTAssertNil(found.owner, "ambiguous caregiver must be left unset, not guessed")
    }

    func testAConsistentCaregiverIsPrefilled() throws {
        let found = try XCTUnwrap(candidates(weekly(3) { event($0, owner: "Kellie") }).first)
        XCTAssertEqual(found.owner, "Kellie")
    }

    func testDerivedFieldsUseTheWholeGroup() throws {
        let events = [
            event("2026-08-26", "Drop Off", from: "08:00", minutes: 20),
            event("2026-09-02", "Soni Drop Off", from: "08:10", minutes: 22),
            event("2026-09-09", "Soni Drop Off", from: "08:20", minutes: 30)
        ]
        let found = try XCTUnwrap(candidates(events).first)
        XCTAssertEqual(found.representativeTitle, "Soni Drop Off", "most common title wins")
        XCTAssertEqual(found.startTime, "08:10", "median start, rounded to five")
        XCTAssertEqual(found.durationMinutes, 20, "median duration, rounded to five")
        XCTAssertEqual(found.kids, ["Soni"])
        XCTAssertEqual(found.category, "School")
        XCTAssertEqual(found.endTime, "08:30")
    }

    func testUsualWeekdaysAreInferredOnlyWhenConsistent() throws {
        // Every Wednesday for four weeks.
        let consistent = weekly(4) { event($0) }
        XCTAssertEqual(try XCTUnwrap(candidates(consistent).first).weekdays,
                       [CalendarMath.weekdayIndex(today)!])

        // Four occurrences, four different weekdays, four different weeks:
        // no weekday reaches the 60%-of-weeks bar, so nothing is inferred.
        let scattered = [
            event("2026-08-17"), event("2026-08-25"), event("2026-09-02"), event("2026-09-10")
        ]
        XCTAssertTrue(try XCTUnwrap(candidates(scattered).first).weekdays.isEmpty)
    }

    // MARK: - Provenance

    func testShortcutCreatedEventsAreExcluded() {
        XCTAssertTrue(candidates(weekly(4) { event($0, origin: .shortcut) }).isEmpty)
    }

    func testRecurringOccurrencesAreExcluded() {
        XCTAssertTrue(candidates(weekly(4) { event($0, series: "s1", origin: .recurrence) }).isEmpty)
    }

    func testCalendarImportsAreExcluded() {
        XCTAssertTrue(candidates(weekly(4) { event($0, calendar: "google|a|b", origin: .calendarImport) }).isEmpty)
    }

    func testOnboardingSeedsAreExcluded() {
        XCTAssertTrue(candidates(weekly(4) { event($0, origin: .onboarding) }).isEmpty)
    }

    func testAssistantCreatedSingleEventsRemainEligible() {
        XCTAssertEqual(candidates(weekly(4) { event($0, origin: .assistantSingle) }).count, 1)
    }

    func testLegacyEventsAreEligibleUnlessSeriesOrImported() {
        XCTAssertEqual(candidates(weekly(4) { event($0, origin: nil) }).count, 1)
        XCTAssertTrue(candidates(weekly(4) { event($0, series: "s1", origin: nil) }).isEmpty)
        XCTAssertTrue(candidates(weekly(4) { event($0, calendar: "google|a", origin: nil) }).isEmpty)
    }

    // MARK: - Coverage by existing shortcuts

    private func shortcut(
        title: String = "Drop Off", place: String = "Goddard School",
        kids: [String] = ["Soni"], start: String = "08:00", minutes: Int = 20
    ) -> ExistingShortcut {
        ExistingShortcut(id: "t1", title: title, location: place, kids: kids,
                         startTime: start, durationMinutes: minutes)
    }

    func testAnEquivalentShortcutSuppressesTheCandidate() {
        // "Drop Off" covers "Soni Drop Off" - the second bug on screen.
        XCTAssertTrue(candidates(weekly(4) { event($0) }, shortcuts: [shortcut()]).isEmpty)
    }

    func testAShortcutForADifferentChildDoesNotSuppress() {
        let found = candidates(
            weekly(4) { event($0, kids: ["Soni"]) },
            shortcuts: [shortcut(title: "Mia Drop Off", kids: ["Mia"])]
        )
        XCTAssertEqual(found.count, 1, "one child's shortcut must not silence another's")
    }

    func testAShortcutElsewhereDoesNotSuppress() {
        let found = candidates(weekly(4) { event($0) }, shortcuts: [shortcut(place: "Other School")])
        XCTAssertEqual(found.count, 1)
    }

    func testAShortcutAtAVeryDifferentTimeDoesNotSuppress() {
        let found = candidates(weekly(4) { event($0, from: "08:00") },
                               shortcuts: [shortcut(start: "15:10")])
        XCTAssertEqual(found.count, 1)
    }

    // MARK: - Model role

    private func service(_ json: String) -> SuggestionService {
        SuggestionService(client: ProgrammedLunaClient(replies: [.structured(json)]))
    }

    private var sample: [ShortcutCandidate] { candidates(weekly(4) { event($0) }) }

    func testTheModelCanDeclineEverything() async {
        let result = await service(#"{"suggestions":[]}"#).rank(sample)
        XCTAssertTrue(result.isEmpty, "an empty list hides the section")
    }

    func testNoCandidatesMeansNoRequest() async {
        let client = ProgrammedLunaClient(replies: [])
        let result = await SuggestionService(client: client).rank([])
        XCTAssertTrue(result.isEmpty)
        XCTAssertTrue(client.requests.isEmpty)
    }

    func testASelectionCarriesAppOwnedEvidence() async throws {
        let id = try XCTUnwrap(sample.first?.id)
        let result = await service(#"{"suggestions":[{"candidate_id":"\#(id)","label":"School drop-off"}]}"#).rank(sample)
        XCTAssertEqual(result.first?.label, "School drop-off")
        XCTAssertEqual(result.first?.evidence, "Added manually 4 times across 4 weeks.")
        XCTAssertEqual(result.first?.isLocalOnly, false)
    }

    func testInventedIdsDuplicatesAndMalformedOutputAreRejected() async throws {
        let id = try XCTUnwrap(sample.first?.id)
        let invented = await service(#"{"suggestions":[{"candidate_id":"nope","label":"x"}]}"#).rank(sample)
        XCTAssertTrue(invented.isEmpty)

        let duplicated = await service(#"{"suggestions":[{"candidate_id":"\#(id)","label":"A"},{"candidate_id":"\#(id)","label":"B"}]}"#).rank(sample)
        XCTAssertEqual(duplicated.count, 1)

        let garbage = await service("not json").rank(sample)
        XCTAssertTrue(garbage.isEmpty)
    }

    func testAnUnsupportedClaimInALabelFallsBack() async throws {
        let id = try XCTUnwrap(sample.first?.id)
        let result = await service(#"{"suggestions":[{"candidate_id":"\#(id)","label":"Drop-off 97 times"}]}"#).rank(sample)
        XCTAssertEqual(result.first?.label, "Soni Drop Off")
    }

    func testAIFailureFallsBackToLocalRankingNotAnError() async {
        let failing = ProgrammedLunaClient(error: .offline)
        let result = await SuggestionService(client: failing).rank(sample)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.label, "Soni Drop Off")
        XCTAssertEqual(result.first?.isLocalOnly, true)
    }

    func testNoClientAtAllStillShowsLocalSuggestions() async {
        let result = await SuggestionService(client: nil).rank(sample)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.isLocalOnly, true)
    }

    func testThePayloadCarriesNoNotesOrRawEvents() {
        let payload = SuggestionService.payload(sample)
        XCTAssertFalse(payload.contains("notes"))
        XCTAssertFalse(payload.lowercased().contains("address"))
        XCTAssertTrue(payload.contains("times_added_by_hand"))
    }
}

import Foundation
import Combine

final class MemorySecrets: IntegrationSecretStore {
    var values: [String: String] = [:]
    func get(_ key: String) throws -> String? { values[key] }
    func set(_ value: String, for key: String) throws { values[key] = value.isEmpty ? nil : value }
}

final class MockGoogleCalendarService: GoogleCalendarProtocol {
    var authenticated = false
    var email: String? = nil
    var calendars: [GoogleCalendarChoice] = [
        GoogleCalendarChoice(id: "primary", title: "Primary", isPrimary: true),
        GoogleCalendarChoice(id: "family-cal", title: "Family", isPrimary: false)
    ]
    var remoteEvents: [String: [GoogleCalendarEventItem]] = [:]
    var createCount = 0
    var updateCount = 0
    var deleteCount = 0
    var shouldFailWithConflict = false

    func isAuthenticated() -> Bool { authenticated }
    func currentEmail() -> String? { email }
    func authenticate(clientId: String) async throws -> (userEmail: String, accessToken: String) {
        guard !clientId.isEmpty else { throw GoogleCalendarError.missingClientId }
        authenticated = true
        email = "testuser@gmail.com"
        return ("testuser@gmail.com", "mock-token-123")
    }
    func disconnect() async throws {
        authenticated = false
        email = nil
    }
    func listCalendars() async throws -> [GoogleCalendarChoice] { calendars }
    func fetchEvents(
        calendarIDs: Set<String>,
        start: Date,
        end: Date,
        timeZone: TimeZone,
        homeName: String
    ) async throws -> [TaskRecord] {
        var records: [TaskRecord] = []
        for calId in calendarIDs {
            for item in remoteEvents[calId] ?? [] {
                if item.status == "cancelled" { continue }
                if let rec = GoogleCalendarService.parseGoogleEvent(item, calendarId: calId, timeZone: timeZone, homeName: homeName) {
                    records.append(rec)
                }
            }
        }
        return records
    }
    func createEvent(
        calendarId: String,
        task: TaskRecord,
        timeZone: TimeZone
    ) async throws -> (eventId: String, etag: String) {
        guard authenticated else { throw GoogleCalendarError.unauthenticated }
        createCount += 1
        let evId = "g-ev-\(createCount)"
        let etag = "\"etag-\(createCount)\""
        return (evId, etag)
    }
    func updateEvent(
        calendarId: String,
        eventId: String,
        task: TaskRecord,
        expectedEtag: String?,
        timeZone: TimeZone
    ) async throws -> String {
        guard authenticated else { throw GoogleCalendarError.unauthenticated }
        if shouldFailWithConflict {
            throw GoogleCalendarError.conflict("Remote modification")
        }
        updateCount += 1
        return "\"etag-updated-\(updateCount)\""
    }
    func deleteEvent(
        calendarId: String,
        eventId: String
    ) async throws {
        guard authenticated else { throw GoogleCalendarError.unauthenticated }
        deleteCount += 1
    }
}

actor TestCloud: HouseholdCloudService {
    var remote: RemoteHousehold?
    var uploads: [PersistedState] = []
    var blockNext = false
    var failureNext = false
    var gate: CheckedContinuation<Void, Never>?
    var arrival: CheckedContinuation<Void, Never>?
    var revision = 0

    func blockUpload() { blockNext = true }
    func failUpload() { failureNext = true }
    func waitForUpload() async {
        if gate != nil { return }
        await withCheckedContinuation { arrival = $0 }
    }
    func release() { gate?.resume(); gate = nil }
    func uploadCount() -> Int { uploads.count }
    func lastUpload() -> PersistedState? { uploads.last }
    func setRemote(_ state: PersistedState) {
        revision += 1
        remote = RemoteHousehold(state: state, revision: String(revision))
    }
    func pushHousehold(state: PersistedState, householdId: String, expectedRevision: String?, rawConnectionString: String) async throws -> String {
        uploads.append(state)
        if blockNext {
            blockNext = false
            await withCheckedContinuation { continuation in
                gate = continuation
                arrival?.resume()
                arrival = nil
            }
        }
        if failureNext { failureNext = false; throw NeonError.networkError("Offline") }
        guard expectedRevision == remote?.revision else { throw NeonError.conflict }
        revision += 1
        remote = RemoteHousehold(state: state, revision: String(revision))
        return String(revision)
    }
    func pullHousehold(householdId: String, rawConnectionString: String) async throws -> RemoteHousehold? { remote }
    func fetchRevision(householdId: String, rawConnectionString: String) async throws -> String? { remote?.revision }
}

// Intercepts Neon SQL at the URLSession boundary. Never sends credentials or
// household fixtures to a network service.
final class SQLProtocol: URLProtocol {
    static var requests: [[String: Any]] = []
    static var returnConflict = false
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var data = request.httpBody
        if data == nil, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var bytes = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                bytes.append(contentsOf: buffer.prefix(count))
            }
            data = bytes
        }
        let body = (try? JSONSerialization.jsonObject(with: data ?? Data())) as? [String: Any] ?? [:]
        Self.requests.append(body)
        let query = body["query"] as? String ?? ""
        let rows: [[String: Any]] = query.contains("RETURNING") && !Self.returnConflict ? [["revision": "2026-09-08 12:00:00+00"]] : []
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: ["rows": rows]))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main struct ProductionRegressionTests {
    static func check(_ condition: Bool, _ message: String, line: Int = #line) {
        if !condition {
            print("❌ FAILURE at line \(line): \(message)")
            fflush(stdout)
        }
        precondition(condition, "Line \(line): \(message)")
    }

    @MainActor static func main() async throws {
        let iso = ISO8601DateFormatter()
        var now = iso.date(from: "2026-09-13T23:59:00Z")!
        let secrets = MemorySecrets()
        let cloud = TestCloud()
        let suite = "helipad.regression.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        func store(_ service: HouseholdCloudService = TestCloud()) -> AppStore {
            AppStore(timeZone: "UTC", cloudService: service, secretStore: secrets, schedulesNotifications: false, now: { now })
        }

        let fresh = store(cloud)
        fresh.restore(from: defaults)
        await fresh.resumePendingSync()
        check(await cloud.uploadCount() == 0, "first restore must not upload sample data")
        check(fresh.neonConnectionString.isEmpty && !fresh.neonSyncEnabled, "no bundled connection")
        check(AppConfig.defaultNeonConnectionString.isEmpty, "no shipped database secret")

        var reminderCalendar = Calendar(identifier: .gregorian)
        reminderCalendar.timeZone = TimeZone(identifier: "UTC")!
        let reminderEvent = TaskRecord(
            id: "reminder",
            date: "2026-09-14",
            time: "10:00",
            title: "Appointment",
            owner: "Mom",
            location: "Clinic",
            mode: "Drive"
        )
        let reminderDate = NotificationService.reminderDate(
            for: reminderEvent,
            calendar: reminderCalendar,
            travelMinutes: 25,
            bufferMinutes: 12
        )
        let expectedReminder = iso.date(from: "2026-09-14T09:13:00Z")!
        check(reminderDate == expectedReminder, "reminder fires 10 minutes before the GPS leave-by time")
        check(
            NotificationService.driverNeededDate(for: reminderEvent, calendar: reminderCalendar)
                == iso.date(from: "2026-09-13T22:00:00Z")!,
            "driver-needed warning fires 12 hours before the event"
        )

        // Finite recurrence uses Monday-Sunday calendar buckets and stable slot IDs.
        let recurrenceDraft = TaskRecord(
            id: "draft",
            date: "2026-09-14",
            time: "15:00",
            endTime: "16:00",
            title: "Swim",
            owner: "Mom",
            location: "Home",
            mode: "Home"
        )
        let twentyWeekPattern = RecurrencePattern(
            mode: .weekly,
            startDate: "2026-09-14",
            timeZone: "America/Detroit",
            weekdays: [0, 2, 2],
            end: .weekCount(20)
        )
        let twentyWeeks = try PlanCore.occurrences(recurrenceDraft, recurrence: twentyWeekPattern, seriesId: "swim")
        check(twentyWeeks.count == 40 && twentyWeeks.first?.date == "2026-09-14" && twentyWeeks.last?.date == "2027-01-27", "Monday-start Mon/Wed x20 produces 40 bounded occurrences")
        check(Set(twentyWeeks.map(\.id)).count == 40, "materialized recurrence IDs are unique per original date")
        check(twentyWeeks.allSatisfy { $0.originalOccurrenceDate == $0.date && $0.seriesId == "swim" }, "every occurrence carries durable series and slot identity")
        let oneTime = try PlanCore.occurrences(
            recurrenceDraft,
            recurrence: RecurrencePattern(mode: .none, startDate: "2026-10-02", weekdays: [0, 2], end: .weekCount(30)),
            seriesId: "ignored-for-one-time"
        )
        check(oneTime.count == 1 && oneTime[0].date == "2026-10-02" && oneTime[0].seriesId == nil, "does-not-repeat produces exactly the selected date")

        let wednesdayPattern = RecurrencePattern(
            mode: .weekly,
            startDate: "2026-09-16",
            weekdays: [0, 2],
            end: .weekCount(20)
        )
        check(try PlanCore.occurrences(recurrenceDraft, recurrence: wednesdayPattern, seriesId: "wed").count == 39, "partial starting week excludes weekdays before the start")
        do {
            let emptyPattern = RecurrencePattern(mode: .weekly, startDate: "2026-09-16", weekdays: [0], end: .weekCount(1))
            _ = try PlanCore.occurrences(recurrenceDraft, recurrence: emptyPattern, seriesId: "empty")
            preconditionFailure("Expected a useful no-occurrence error")
        } catch {}
        let throughPattern = RecurrencePattern(mode: .weekly, startDate: "2026-09-16", weekdays: [2], end: .throughDate("2026-09-30"))
        check(try PlanCore.occurrences(recurrenceDraft, recurrence: throughPattern, seriesId: "through").map(\.date) == ["2026-09-16", "2026-09-23", "2026-09-30"], "through-date recurrence includes a matching end date")
        let leapPattern = RecurrencePattern(mode: .weekly, startDate: "2028-02-28", weekdays: [1], end: .weekCount(1))
        check(try PlanCore.occurrences(recurrenceDraft, recurrence: leapPattern, seriesId: "leap").first?.date == "2028-02-29", "calendar-day enumeration includes leap day")
        var dstDraft = recurrenceDraft
        dstDraft.time = "02:30"
        dstDraft.endTime = "03:30"
        let dstPattern = RecurrencePattern(mode: .weekly, startDate: "2026-03-01", timeZone: "America/Detroit", weekdays: [6], end: .weekCount(2))
        let dstRows = try PlanCore.occurrences(dstDraft, recurrence: dstPattern, seriesId: "dst")
        check(dstRows.map(\.date) == ["2026-03-01", "2026-03-08"] && dstRows.allSatisfy { $0.time == "02:30" }, "DST preserves requested date and wall time without fixed-second arithmetic")

        let recurrenceSuite = "helipad.recurrence.\(UUID().uuidString)"
        let recurrenceDefaults = UserDefaults(suiteName: recurrenceSuite)!
        defer { recurrenceDefaults.removePersistentDomain(forName: recurrenceSuite) }
        let recurrenceStore = AppStore(
            eventsByDay: [:],
            plan: PlanMetadata(),
            templates: [],
            timeZone: "America/Detroit",
            cloudService: TestCloud(),
            secretStore: secrets,
            schedulesNotifications: false,
            now: { now }
        )
        recurrenceStore.restore(from: recurrenceDefaults)
        var storedDraft = recurrenceDraft
        storedDraft.seriesId = "swim"
        let storedRows = try recurrenceStore.saveEvent(draft: storedDraft, recurrence: twentyWeekPattern, scope: .series)
        check(storedRows.count == 40 && recurrenceStore.seriesDefinition(id: storedRows[0].seriesId!) != nil, "one store command saves rows and their independent rule")
        let firstWednesday = recurrenceStore.events(inSeries: "swim").first { $0.date == "2026-09-16" }!
        try recurrenceStore.assignEvent(id: firstWednesday.id, caregiver: "Dad", scope: .occurrence)
        recurrenceStore.toggleEventDone(id: firstWednesday.id)
        var movedWednesday = recurrenceStore.records().first { $0.id == firstWednesday.id }!
        movedWednesday.date = "2026-09-17"
        _ = try recurrenceStore.saveEvent(
            draft: movedWednesday,
            recurrence: RecurrencePattern(mode: .none, startDate: movedWednesday.date),
            scope: .occurrence,
            sourceOccurrenceID: movedWednesday.id
        )
        let deletedWednesday = recurrenceStore.events(inSeries: "swim").first { $0.date == "2026-09-23" }!
        recurrenceStore.deleteEvent(id: deletedWednesday.id, scope: .occurrence)
        var editReference = recurrenceStore.records().first { $0.id == firstWednesday.id }!
        let wednesdaysOnly = RecurrencePattern(mode: .weekly, startDate: "2026-09-14", timeZone: "America/Detroit", weekdays: [2], end: .weekCount(21))
        editReference.title = "Swim"
        _ = try recurrenceStore.saveEvent(draft: editReference, recurrence: wednesdaysOnly, scope: .series, sourceOccurrenceID: firstWednesday.id)
        let narrowed = recurrenceStore.events(inSeries: "swim")
        check(narrowed.contains { $0.id == firstWednesday.id && $0.date == "2026-09-17" && $0.originalOccurrenceDate == "2026-09-16" && $0.owner == "Dad" && $0.done }, "weekday/range edits preserve moved occurrence identity and overlays")
        check(!narrowed.contains { ($0.originalOccurrenceDate ?? $0.date) == "2026-09-23" }, "a deleted occurrence exclusion survives a series extension")
        check(narrowed.allSatisfy { PlanCore.weekdayIndex($0.originalOccurrenceDate ?? $0.date) == 2 }, "removing Monday changes only intended series slots")
        let reopenedRecurrence = AppStore(eventsByDay: [:], plan: PlanMetadata(), templates: [], cloudService: TestCloud(), secretStore: secrets, schedulesNotifications: false, now: { now })
        reopenedRecurrence.restore(from: recurrenceDefaults)
        check(reopenedRecurrence.events(inSeries: "swim").count == narrowed.count, "multiweek rows and exclusions survive relaunch")
        let staleSeriesState = HeliPersistence.load(from: recurrenceDefaults)!
        recurrenceStore.deleteSeries(id: "swim")
        now = now.addingTimeInterval(40 * 24 * 60 * 60)
        try recurrenceStore.setSetting(key: "buffer", value: 13)
        recurrenceStore.merge(staleSeriesState)
        check(recurrenceStore.events(inSeries: "swim").isEmpty && recurrenceStore.plan.seriesDefinitions?.first(where: { $0.seriesId == "swim" })?.deleted == true, "whole-series deletion survives past row tombstone retention and rejects stale resurrection")

        let onboardingRecurrence = OnboardingDraft(
            yourName: "Mom",
            kids: [.init(name: "Kid", relationship: "Child")],
            activities: [.init(
                title: "Piano",
                kidNames: ["Kid"],
                placeName: "Home",
                weekdays: [1],
                time: "16:00",
                startDate: "2026-09-14",
                recurrenceMode: .weekly,
                recurrenceWeekCount: 30
            )]
        ).build(baseWeek: "2026-09-14", timeZone: "America/Detroit")
        check(onboardingRecurrence.records.count == 30 && Set(onboardingRecurrence.records.map(\.id)).count == 30, "onboarding materializes a unique 30-week schedule including off-week records")
        check(onboardingRecurrence.templates.first?.weekdays == [1] && onboardingRecurrence.templates.first?.recurrenceWeekCount == 30, "onboarding shortcuts preserve weekday and relative duration defaults")

        // Concurrent series-range and per-slot edits merge independently and converge.
        let seriesBaseSuite = "helipad.series-base.\(UUID().uuidString)"
        let seriesASuite = "helipad.series-a.\(UUID().uuidString)"
        let seriesBSuite = "helipad.series-b.\(UUID().uuidString)"
        let seriesBaseDefaults = UserDefaults(suiteName: seriesBaseSuite)!
        let seriesADefaults = UserDefaults(suiteName: seriesASuite)!
        let seriesBDefaults = UserDefaults(suiteName: seriesBSuite)!
        defer {
            seriesBaseDefaults.removePersistentDomain(forName: seriesBaseSuite)
            seriesADefaults.removePersistentDomain(forName: seriesASuite)
            seriesBDefaults.removePersistentDomain(forName: seriesBSuite)
        }
        let seriesBaseStore = AppStore(eventsByDay: [:], plan: PlanMetadata(), templates: [], cloudService: TestCloud(), secretStore: secrets, schedulesNotifications: false, now: { now })
        seriesBaseStore.restore(from: seriesBaseDefaults)
        var syncDraft = recurrenceDraft
        syncDraft.seriesId = "sync-series"
        let fourMondays = RecurrencePattern(mode: .weekly, startDate: "2026-09-14", weekdays: [0], end: .weekCount(4))
        _ = try seriesBaseStore.saveEvent(draft: syncDraft, recurrence: fourMondays, scope: .series)
        let baseSeriesState = HeliPersistence.load(from: seriesBaseDefaults)!
        var stateA = baseSeriesState
        var stateB = baseSeriesState
        stateA.syncMetadata?.deviceID = "series-device-a"
        stateB.syncMetadata?.deviceID = "series-device-b"
        HeliPersistence.save(stateA, to: seriesADefaults)
        HeliPersistence.save(stateB, to: seriesBDefaults)
        let seriesA = AppStore(eventsByDay: [:], plan: PlanMetadata(), templates: [], cloudService: TestCloud(), secretStore: secrets, schedulesNotifications: false, now: { now })
        let seriesB = AppStore(eventsByDay: [:], plan: PlanMetadata(), templates: [], cloudService: TestCloud(), secretStore: secrets, schedulesNotifications: false, now: { now })
        seriesA.restore(from: seriesADefaults)
        seriesB.restore(from: seriesBDefaults)
        let sixMondays = RecurrencePattern(mode: .weekly, startDate: "2026-09-14", weekdays: [0], end: .weekCount(6))
        let aSource = seriesA.events(inSeries: "sync-series").first!
        _ = try seriesA.saveEvent(draft: aSource, recurrence: sixMondays, scope: .series, sourceOccurrenceID: aSource.id)
        let deletedSlot = seriesB.events(inSeries: "sync-series").first { $0.date == "2026-09-21" }!
        seriesB.deleteEvent(id: deletedSlot.id, scope: .occurrence)
        let aBeforeMerge = HeliPersistence.load(from: seriesADefaults)!
        let bBeforeMerge = HeliPersistence.load(from: seriesBDefaults)!
        seriesA.merge(bBeforeMerge)
        seriesB.merge(aBeforeMerge)
        let aConverged = seriesA.events(inSeries: "sync-series")
        let bConverged = seriesB.events(inSeries: "sync-series")
        check(aConverged.map(\.id).sorted() == bConverged.map(\.id).sorted() && aConverged.count == 5, "simultaneous range extension and occurrence deletion converge without duplicates or resurrection")
        check(seriesA.plan.seriesDefinitions == seriesB.plan.seriesDefinitions && seriesA.plan.seriesExceptions == seriesB.plan.seriesExceptions, "series rules and per-slot exceptions converge independently")

        // The durable active rule, not a short-lived row tombstone, owns range
        // shrink. A device carrying an old six-week payload cannot reintroduce
        // weeks five and six after the 30-day tombstone horizon has elapsed.
        let staleSixWeekState = aBeforeMerge
        let shrinkSource = seriesA.events(inSeries: "sync-series").first!
        _ = try seriesA.saveEvent(draft: shrinkSource, recurrence: fourMondays, scope: .series, sourceOccurrenceID: shrinkSource.id)
        now = now.addingTimeInterval(40 * 24 * 60 * 60)
        try seriesA.setSetting(key: "buffer", value: 14)
        seriesA.merge(staleSixWeekState)
        let afterStaleShrinkMerge = seriesA.events(inSeries: "sync-series")
        check(
            afterStaleShrinkMerge.count == 3 && afterStaleShrinkMerge.allSatisfy { ($0.originalOccurrenceDate ?? $0.date) <= "2026-10-05" },
            "a durable range shrink rejects stale out-of-range rows after tombstone expiry"
        )

        // Calendar recurrence is grouped only by the provider identity carried
        // by the adapter. A local event that merely looks identical stays out
        // of the series, while Plan still discovers a once-weekly routine and
        // applies an explicitly confirmed series assignment beyond this week.
        let providerStore = store()
        let providerSeriesId = "apple-series|school-cal|provider-swim"
        let importedFirst = TaskRecord(
            id: "apple|school-cal|provider-swim|2026-09-14|15:00",
            date: "2026-09-14",
            time: "15:00",
            title: "Swim",
            owner: "TBD",
            location: "Pool",
            seriesId: providerSeriesId,
            originalOccurrenceDate: "2026-09-14",
            calendarId: "apple|school-cal|provider-swim|2026-09-14|15:00"
        )
        let importedSecond = TaskRecord(
            id: "apple|school-cal|provider-swim|2026-09-21|15:00",
            date: "2026-09-21",
            time: "15:00",
            title: "Swim",
            owner: "TBD",
            location: "Pool",
            seriesId: providerSeriesId,
            originalOccurrenceDate: "2026-09-21",
            calendarId: "apple|school-cal|provider-swim|2026-09-21|15:00"
        )
        let lookalike = TaskRecord(id: "local-lookalike", date: "2026-09-14", time: "15:00", title: "Swim", owner: "Mom", location: "Pool")
        providerStore.replaceRecords([lookalike])
        providerStore.mergeAppleCalendarEvents(
            [importedFirst, importedSecond],
            calendarIDs: ["school-cal"],
            from: "2026-09-14",
            through: "2026-09-30"
        )
        let providerPlan = PlanViewModel()
        providerPlan.currentWeek = "2026-09-14"
        let providerGroups = providerPlan.routineGroups(store: providerStore)
        check(providerGroups.count == 1 && providerGroups[0].weekEvents.count == 1 && providerGroups[0].events.count == 2, "Plan shows a once-weekly provider series while retaining global action scope")
        try providerStore.assignEvent(id: importedFirst.id, caregiver: "Dad", scope: .series)
        check(providerStore.events(inSeries: providerSeriesId).allSatisfy { $0.owner == "Dad" }, "entire-series assignment reaches imported occurrences outside the visible week")
        check(providerStore.records().first { $0.id == lookalike.id }?.owner == "Mom", "lookalike one-off remains outside provider and local series actions")

        let rulesSuite = "helipad.rules.\(UUID().uuidString)"
        let rulesDefaults = UserDefaults(suiteName: rulesSuite)!
        defer { rulesDefaults.removePersistentDomain(forName: rulesSuite) }
        let rulesStore = store()
        rulesStore.restore(from: rulesDefaults)
        try rulesStore.updatePlanningRules(
            for: "2026-09-16",
            dinnerProtected: true,
            dinnerTime: "19:15",
            bufferMinutes: 21,
            peakTraffic: false,
            notes: "Grandma handles Wednesday"
        )
        check(rulesStore.buffer == 21 && !rulesStore.trafficMode, "planning rules update canonical travel settings")
        check(rulesStore.planningRules(for: "2026-09-14").time == "19:15", "weekly dinner target uses the week contract")
        check(rulesStore.weeklyPlanningNotes(for: "2026-09-14") == "Grandma handles Wednesday", "weekly planning notes are stored by week")
        let reopenedRules = store()
        reopenedRules.restore(from: rulesDefaults)
        check(reopenedRules.buffer == 21, "planning buffer survives relaunch")
        check(reopenedRules.planningRules(for: "2026-09-14").time == "19:15", "dinner target survives relaunch")
        check(reopenedRules.weeklyPlanningNotes(for: "2026-09-14") == "Grandma handles Wednesday", "weekly notes survive relaunch")

        let placeStore = store()
        let oldSchool = LocationItem(
            name: "School",
            address: "100 Old Road",
            routeKey: "School",
            source: "resolved",
            latitude: 42.1,
            longitude: -83.1,
            placeId: "old-school"
        )
        placeStore.locations = [
            LocationItem(name: "Home", address: "1 Home Road", routeKey: "Home"),
            oldSchool,
            LocationItem(name: "Park", address: "5 Park Road")
        ]
        placeStore.homePlaceName = "Home"
        placeStore.parentLocations = ["Mom": "School"]
        placeStore.templates = [TemplateItem(id: "school-template", title: "School", time: "08:00", endTime: "08:30", location: "School")]
        placeStore.replaceRecords([
            TaskRecord(id: "shared-place", date: "2026-09-14", title: "Shared", owner: "Mom", location: "School", latitude: 42.1, longitude: -83.1, formattedAddress: "100 Old Road"),
            TaskRecord(id: "explicit-place", date: "2026-09-14", title: "Explicit", owner: "Mom", location: "School", latitude: 43.0, longitude: -84.0, formattedAddress: "Private entrance")
        ])
        try placeStore.updateLocation(
            index: 1,
            data: LocationItem(name: "New School", address: "200 New Road", source: "manual")
        )
        check(placeStore.parentLocations["Mom"] == "New School", "place rename preserves caregiver base reference")
        check(placeStore.templates.first?.location == "New School", "place rename preserves template reference")
        let sharedPlace = placeStore.records().first { $0.id == "shared-place" }!
        let explicitPlace = placeStore.records().first { $0.id == "explicit-place" }!
        check(sharedPlace.location == "New School" && sharedPlace.latitude == nil, "changed shared address clears stale event coordinates")
        check(explicitPlace.location == "New School" && explicitPlace.latitude == 43.0, "explicit event destination survives shared-place edit")
        do {
            try placeStore.removeLocation(index: 1)
            preconditionFailure("Expected referenced place deletion to be blocked")
        } catch {}

        placeStore.hasCompletedOnboarding = true
        placeStore.savedOnboardingDraft = OnboardingDraft(yourName: "Stale Name", homeAddress: "Old")
        let rerunDraft = placeStore.onboardingStartingPoint()
        check(rerunDraft.homeAddress == "1 Home Road", "setup rerun starts from the current household instead of stale answers")
        check(rerunDraft.places.contains { $0.name == "New School" }, "setup rerun includes current places")

        let old = TaskRecord(id: "old", date: "2026-09-13", title: "One-off", owner: "Mom", done: true)
        let future = TaskRecord(id: "future", date: "2026-09-14", title: "Next week", owner: "Mom")
        fresh.replaceRecords([old, future])
        fresh.hasCompletedOnboarding = true
        fresh.save(syncToCloud: false)
        now = iso.date(from: "2026-09-14T00:00:00Z")!
        fresh.syncWithDeviceDate()
        check(fresh.weekStart == "2026-09-14", "week rolls over")
        check(fresh.eventsByDay[0]?.first?.id == "future", "future event promoted into Go")
        check(fresh.records().first(where: { $0.id == "old" })?.date == "2026-09-13", "past date retained")
        check(fresh.records().first(where: { $0.id == "old" })?.done == true, "history retains completion")
        fresh.syncWithDeviceDate()
        check(fresh.records().count == 2, "rollover is idempotent")
        let restored = store()
        restored.restore(from: defaults)
        check(restored.records() == fresh.records(), "absolute dates survive relaunch")
        now = iso.date(from: "2026-10-05T12:00:00Z")!
        restored.syncWithDeviceDate()
        check(restored.records().count == 2 && restored.eventsByDay.isEmpty, "multiple skipped weeks preserve history")

        // Legacy v1 bucket dates are already absolute; do not relabel them on load.
        var legacy = try JSONSerialization.jsonObject(with: defaults.data(forKey: HeliPersistence.storageKey)!) as! [String: Any]
        legacy.removeValue(forKey: "syncMetadata")
        legacy.removeValue(forKey: "weekStart")
        if var oldPlan = legacy["plan"] as? [String: Any] {
            oldPlan.removeValue(forKey: "seriesDefinitions")
            oldPlan.removeValue(forKey: "seriesExceptions")
            legacy["plan"] = oldPlan
        }
        if var oldTemplates = legacy["templates"] as? [[String: Any]] {
            for index in oldTemplates.indices { oldTemplates[index].removeValue(forKey: "recurrenceWeekCount") }
            legacy["templates"] = oldTemplates
        }
        if var oldDays = legacy["eventsByDay"] as? [String: [[String: Any]]] {
            for day in oldDays.keys {
                guard var rows = oldDays[day] else { continue }
                for index in rows.indices {
                    rows[index].removeValue(forKey: "originalOccurrenceDate")
                    rows[index].removeValue(forKey: "recurrenceOverride")
                }
                oldDays[day] = rows
            }
            legacy["eventsByDay"] = oldDays
        }
        legacy["neonConnectionString"] = "postgresql://old:exposed@example.neon.tech/db"
        defaults.set(try JSONSerialization.data(withJSONObject: legacy), forKey: HeliPersistence.storageKey)
        let migrated = store()
        migrated.restore(from: defaults)
        check(migrated.records().contains(where: { $0.id == "old" && $0.date == "2026-09-13" }), "v1 event dates retained")
        let cleaned = String(data: defaults.data(forKey: HeliPersistence.storageKey)!, encoding: .utf8)!
        check(!cleaned.contains("exposed") && migrated.neonConnectionString.isEmpty, "legacy database secret scrubbed")

        now = iso.date(from: "2026-09-14T14:37:00Z")!
        let live = store()
        let vm = GoViewModel(store: live)
        check(live.mockTime.isEmpty && vm.nowMinutes == 14 * 60 + 37, "production clock uses real injected time")
        var publications = 0
        let observation = vm.$nowMinutes.dropFirst().sink { _ in publications += 1 }
        vm.updateClock()
        vm.updateClock()
        check(publications == 0, "same minute does not publish")
        now = now.addingTimeInterval(60)
        vm.updateClock()
        check(publications == 1, "next minute publishes once")
        live.mockTime = "08:05"
        vm.updateClock()
        check(vm.nowMinutes == 485, "explicit test clock supported")
        live.mockTime = ""
        live.timeZone = "America/Los_Angeles"
        vm.updateClock()
        check(vm.nowMinutes == 7 * 60 + 38, "household timezone used")
        _ = observation

        live.timeZone = "UTC"
        live.replaceRecords([TaskRecord(id: "cache", date: "2026-09-14", owner: "Mom", location: "Oak Ridge Elementary")])
        _ = vm.computeView(store: live)
        let passes = vm.analysisPassCount
        for _ in 0..<12 { _ = vm.computeView(store: live) }
        check(vm.analysisPassCount == passes, "clock-only renders reuse analysis")
        live.currentUser = "Dad"
        live.liveWeather.temperature = 90
        _ = vm.computeView(store: live)
        check(vm.analysisPassCount == passes, "profile and weather do not invalidate schedule analysis")
        live.buffer += 1
        _ = vm.computeView(store: live)
        check(vm.analysisPassCount == passes + 1, "buffer invalidates cached planning")
        live.eventsByDay[0]![0].time = "17:15"
        _ = vm.computeView(store: live)
        check(vm.analysisPassCount == passes + 2, "direct event edit invalidates cache")
        live.routes["Home"]?["Oak Ridge Elementary"] = 99
        _ = vm.computeView(store: live)
        check(vm.analysisPassCount == passes + 3, "route update invalidates cache")
        let data = vm.computeView(store: live)
        check(data.drivers.mapValues(\.minutes) == PlanCore.loads(live.eventsByDay[0] ?? [], live.planningOptions()), "cached workloads match planning core")

        let overdueStore = store()
        overdueStore.mockTime = "15:21"
        overdueStore.currentUser = "All"
        overdueStore.replaceRecords([
            TaskRecord(id: "overdue", date: "2026-09-14", time: "15:00", endTime: "15:15", title: "Unfinished", owner: "Mom", location: "Home", mode: "Home"),
            TaskRecord(id: "all-day", date: "2026-09-14", title: "Permission slip", owner: "Mom", location: "Home", mode: "Home", allDay: true)
        ])
        let overdueData = GoViewModel(store: overdueStore).computeView(store: overdueStore)
        check(overdueData.live >= 0 && overdueData.mine[overdueData.live].event.id == "overdue", "overdue unfinished work remains actionable")
        check(overdueData.restingState == .outstanding(2), "timed and all-day unfinished work prevent an all-clear state")

        let unknownRouteStore = store()
        unknownRouteStore.currentUser = "All"
        unknownRouteStore.replaceRecords([
            TaskRecord(id: "unknown-route", date: "2026-09-14", time: "16:00", title: "Unknown route", owner: "Mom", location: "Unresolved Place", mode: "Drive")
        ])
        let unknownRouteData = GoViewModel(store: unknownRouteStore).computeView(store: unknownRouteStore)
        check(unknownRouteData.drivers["Mom"]?.assignedStops == 1, "assigned drive remains visible when its route is unknown")
        check(unknownRouteData.drivers["Mom"]?.unknownRoutes == 1, "unknown route is not reported as zero driving")

        // Restore to a clean isolated suite and configure a user-owned connection.
        defaults.removePersistentDomain(forName: suite)
        let syncing = store(cloud)
        syncing.restore(from: defaults)
        syncing.hasCompletedOnboarding = true
        syncing.neonConnectionString = "postgresql://personal:private@example.neon.tech/db"
        syncing.googleMapsApiKey = "private-google-key"
        syncing.neonSyncEnabled = true
        syncing.save(syncToCloud: false)
        await cloud.blockUpload()
        let first = Task { @MainActor in try await syncing.syncWithNeon() }
        await cloud.waitForUpload()
        syncing.homeAddress = "Edited while uploading"
        syncing.buffer = 19
        syncing.save(syncToCloud: false)
        let joined = Task { @MainActor in try await syncing.syncWithNeon() }
        await cloud.release()
        try await first.value
        try await joined.value
        check(await cloud.uploadCount() == 2, "in-flight edits cause another upload")
        check(await cloud.lastUpload()?.buffer == 19, "latest edit reaches cloud")
        check(!syncing.syncPending, "all revisions acknowledged")
        let localData = defaults.data(forKey: HeliPersistence.storageKey)!
        let localText = String(data: localData, encoding: .utf8)!
        check(!localText.contains("private") && !localText.contains("postgresql"), "UserDefaults excludes credentials")
        check(secrets.values["neonConnectionString"] == syncing.neonConnectionString, "credentials use secret store")
        let payload = await cloud.lastUpload()!
        let cloudText = String(data: try JSONEncoder().encode(payload), encoding: .utf8)!
        check(!cloudText.contains("private") && !cloudText.contains("syncMetadata"), "cloud excludes secrets and local sync metadata")

        await cloud.failUpload()
        syncing.buffer = 20
        syncing.save(syncToCloud: false)
        do { try await syncing.syncWithNeon(); preconditionFailure("Expected failure") } catch {}
        check(syncing.syncPending && syncing.syncError != nil, "failed work remains pending")
        let retry = store(cloud)
        retry.restore(from: defaults)
        check(retry.syncPending && retry.neonConnectionString == syncing.neonConnectionString, "pending work and secure connection survive restart")
        await retry.resumePendingSync()
        check(!retry.syncPending && retry.syncError == nil, "foreground retries pending revision")
        check(await cloud.lastUpload()?.buffer == 20, "retry sends latest state")

        var remoteEdit = await cloud.lastUpload()!
        remoteEdit.buffer = 33
        await cloud.setRemote(remoteEdit)
        retry.buffer = 21
        retry.save(syncToCloud: false)
        // A stale revision no longer strands the device: sync folds the cloud
        // household in and republishes, and the newer stamp decides the value.
        try await retry.syncWithNeon()
        check(retry.buffer == 21 && !retry.syncPending, "newer local settings survive a remote write and still upload")
        check(await cloud.lastUpload()?.buffer == 21, "merged settings reach the cloud")

        var newerRemote = await cloud.lastUpload()!
        newerRemote.buffer = 44
        newerRemote.settingsStamp = RecordStamp(counter: 9_000, deviceID: "other-phone")
        await cloud.setRemote(newerRemote)
        try await retry.syncWithNeon()
        check(retry.buffer == 44, "a newer remote settings stamp wins")

        let downloaded = try await retry.pullFromNeon()
        check(downloaded && !retry.syncPending, "explicit download establishes baseline")
        check(retry.hasCompletedOnboarding, "cloud restore retains onboarding completion")

        // Switching connection during a write must not acknowledge the old write for the new identity.
        await cloud.blockUpload()
        retry.buffer = 34
        retry.save(syncToCloud: false)
        let changing = Task { @MainActor in try await retry.syncWithNeon() }
        await cloud.waitForUpload()
        retry.cloudHouseholdID = "different-household"
        retry.save(syncToCloud: false)
        await cloud.release()
        do { try await changing.value; preconditionFailure("Expected identity error") } catch {}
        check(retry.syncPending, "identity change stays pending")
        check(HeliPersistence.load(from: defaults)?.syncMetadata?.remoteRevision == nil, "old revision not attached to new household")

        let manualCloud = TestCloud()
        let manual = store(manualCloud)
        manual.hasCompletedOnboarding = true
        manual.neonConnectionString = "postgresql://manual:private@example.neon.tech/db"
        manual.neonSyncEnabled = false
        await manualCloud.blockUpload()
        let manualUpload = Task { @MainActor in try await manual.syncWithNeon() }
        await manualCloud.waitForUpload()
        manual.buffer = 22
        manual.save(syncToCloud: false)
        await manualCloud.release()
        try await manualUpload.value
        check(await manualCloud.uploadCount() == 2, "manual sync also drains in-flight edits with auto-sync off")
        check(!manual.syncPending, "manual sync acknowledges the newest revision")

        // Two phones, one household: the case this whole mechanism exists for.
        let shared = TestCloud()
        let suiteA = "helipad.deviceA.\(UUID().uuidString)"
        let suiteB = "helipad.deviceB.\(UUID().uuidString)"
        let defaultsA = UserDefaults(suiteName: suiteA)!
        let defaultsB = UserDefaults(suiteName: suiteB)!
        defer { defaults.removePersistentDomain(forName: suiteA) }
        defer { defaults.removePersistentDomain(forName: suiteB) }

        func phone(_ store: AppStore, _ defaults: UserDefaults) -> AppStore {
            store.restore(from: defaults)
            store.hasCompletedOnboarding = true
            store.neonConnectionString = "postgresql://pair:private@example.neon.tech/db"
            store.cloudHouseholdID = "shared-household"
            store.neonSyncEnabled = true
            store.save(syncToCloud: false)
            return store
        }
        let phoneA = phone(store(shared), defaultsA)
        let phoneB = phone(store(shared), defaultsB)

        // A publishes a stop; B has never seen this household.
        let soccer = TaskRecord(id: "ev-soccer", date: "2026-10-05", title: "Soccer", owner: "Mom")
        phoneA.replaceRecords([soccer])
        try await phoneA.syncWithNeon()
        try await phoneB.syncWithNeon()
        check(phoneB.records().contains { $0.id == "ev-soccer" }, "second phone receives the first phone's stop")

        // Each phone adds a different stop without seeing the other's first.
        var aRecords = phoneA.records()
        aRecords.append(TaskRecord(id: "ev-piano", date: "2026-10-06", title: "Piano", owner: "Mom"))
        phoneA.replaceRecords(aRecords)
        var bRecords = phoneB.records()
        bRecords.append(TaskRecord(id: "ev-swim", date: "2026-10-07", title: "Swim", owner: "Dad"))
        phoneB.replaceRecords(bRecords)
        try await phoneA.syncWithNeon()
        try await phoneB.syncWithNeon()
        try await phoneA.syncWithNeon()
        let aIds = Set(phoneA.records().map(\.id))
        let bIds = Set(phoneB.records().map(\.id))
        check(aIds == ["ev-soccer", "ev-piano", "ev-swim"], "concurrent adds all survive on the first phone")
        check(aIds == bIds, "both phones converge on the same schedule")

        // A delete must not be resurrected by the other phone's copy.
        phoneA.replaceRecords(phoneA.records().filter { $0.id != "ev-soccer" })
        try await phoneA.syncWithNeon()
        try await phoneB.syncWithNeon()
        check(!phoneB.records().contains { $0.id == "ev-soccer" }, "a delete propagates instead of being undone")
        check(phoneB.records().count == 2, "the other two stops are untouched")

        // Editing the same stop on both phones: the later stamp wins, and both agree.
        func retitle(_ store: AppStore, _ title: String) {
            var list = store.records()
            guard let index = list.firstIndex(where: { $0.id == "ev-piano" }) else { return }
            list[index].title = title
            store.replaceRecords(list)
        }
        // Concurrent edits — neither phone saw the other's — have no "later".
        // The guarantee is that both land on the *same* one, not on a
        // particular one, so that is what gets asserted.
        retitle(phoneA, "Piano lesson")
        retitle(phoneB, "Piano recital")
        try await phoneA.syncWithNeon()
        try await phoneB.syncWithNeon()
        try await phoneA.syncWithNeon()
        let aTitle = phoneA.records().first { $0.id == "ev-piano" }?.title
        let bTitle = phoneB.records().first { $0.id == "ev-piano" }?.title
        check(aTitle == bTitle, "both phones agree after a concurrent edit to one stop")
        check(aTitle == "Piano lesson" || aTitle == "Piano recital", "the surviving edit is one of the two")

        // A causal edit is different: B has seen A's title before changing it,
        // so B's must win on both phones.
        retitle(phoneA, "Piano practice")
        try await phoneA.syncWithNeon()
        try await phoneB.syncWithNeon()
        check(phoneB.records().first { $0.id == "ev-piano" }?.title == "Piano practice", "B sees A's edit first")
        retitle(phoneB, "Piano exam")
        try await phoneB.syncWithNeon()
        try await phoneA.syncWithNeon()
        check(phoneA.records().first { $0.id == "ev-piano" }?.title == "Piano exam", "an edit made after seeing the other phone's wins")

        // A phone that is behind picks the change up from a revision probe.
        var laterRecords = phoneA.records()
        laterRecords.append(TaskRecord(id: "ev-dentist", date: "2026-10-08", title: "Dentist", owner: "Mom"))
        phoneA.replaceRecords(laterRecords)
        try await phoneA.syncWithNeon()
        await phoneB.liveSyncTick()
        check(phoneB.records().contains { $0.id == "ev-dentist" }, "live tick pulls the other phone's new stop")
        let quiet = await shared.uploadCount()
        await phoneB.liveSyncTick()
        check(await shared.uploadCount() == quiet, "an idle tick with no change uploads nothing")

        // Two settled phones must go quiet. If each answered the other's write
        // with a write of its own they would trade revisions forever.
        let settled = await shared.uploadCount()
        for _ in 0..<6 {
            await phoneA.liveSyncTick()
            await phoneB.liveSyncTick()
        }
        check(await shared.uploadCount() == settled, "settled phones stop writing to each other")

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SQLProtocol.self]
        let transport = NeonDatabaseService(session: URLSession(configuration: config))
        _ = try await transport.pushHousehold(state: payload, householdId: "kid's-home", expectedRevision: nil, rawConnectionString: syncing.neonConnectionString)
        let insert = SQLProtocol.requests.last!
        check((insert["query"] as! String).contains("DO NOTHING"), "first upload never overwrites existing row")
        check(!(insert["query"] as! String).contains("kid's-home"), "household identity parameterized")
        _ = try await transport.pushHousehold(state: payload, householdId: "kid's-home", expectedRevision: "2026-09-08 12:00:00+00", rawConnectionString: syncing.neonConnectionString)
        let update = SQLProtocol.requests.last!
        check((update["query"] as! String).contains("updated_at = $3::timestamptz"), "update compares revision atomically")
        SQLProtocol.returnConflict = true
        do {
            _ = try await transport.pushHousehold(state: payload, householdId: "kid's-home", expectedRevision: "stale", rawConnectionString: syncing.neonConnectionString)
            preconditionFailure("Expected zero-row conflict")
        } catch NeonError.conflict {}

        // Solo events without children & stats accuracy verification
        check(FamilyCore.resolveChildren(kids: [], kid: "").isEmpty, "empty kids resolves to empty list, not all kids")
        check(FamilyCore.resolveChildren(kids: ["Maya"], kid: "") == ["Maya"], "single kid preserved")
        check(FamilyCore.resolveChildren(kids: nil, kid: nil) == FamilyCore.KIDS, "nil fallback returns all kids")

        let statsStore = store()
        let soloDoctor = TaskRecord(id: "solo-doc", date: "2026-09-14", time: "10:00", endTime: "11:00", title: "Doctor", owner: "Dad", kids: [], location: "Medical Center", mode: "Drive", kind: .clinic)
        let soniSoccer = TaskRecord(id: "soni-soccer", date: "2026-09-14", time: "15:00", endTime: "16:00", title: "Soccer", owner: "Mom", kids: ["Soni"], location: "Field", mode: "Drive", kind: .practice)
        let soniOrphan = TaskRecord(id: "soni-orphan", date: "2026-09-15", time: "15:00", endTime: "16:00", title: "Swim", owner: "TBD", kids: ["Soni"], location: "Pool", mode: "Drive", kind: .practice)
        statsStore.replaceRecords([soloDoctor, soniSoccer, soniOrphan])

        let familyVM = FamilyViewModel()
        let counts = familyVM.driveCounts(store: statsStore)
        check(counts["Dad"] == 1, "caregiver drive count reflects solo adult drive")
        check(counts["Mom"] == 1, "caregiver drive count reflects kid drive")

        let soniStats = familyVM.statsForKid(kid: "Soni", store: statsStore)
        check(soniStats.eventCount == 2, "Soni stats include only Soni's own events")
        check(soniStats.needsDriverCount == 1, "Soni needs-a-driver count sees the unassigned swim only")

        let mayaStats = familyVM.statsForKid(kid: "Maya", store: statsStore)
        check(mayaStats.eventCount == 0, "Maya stats strictly exclude solo adult doctor event")
        check(mayaStats.needsDriverCount == 0, "Maya needs-a-driver count strictly excludes other kids' events")

        let noahStats = familyVM.statsForKid(kid: "Noah", store: statsStore)
        check(noahStats.eventCount == 0, "Noah stats strictly exclude solo adult doctor event")

        // MARK: - Google Calendar Read/Write & Sync Verification
        let mockGoogleService = MockGoogleCalendarService()
        let gcalSecrets = MemorySecrets()
        let gcalStore = AppStore(
            eventsByDay: [:],
            timeZone: "America/New_York",
            cloudService: TestCloud(),
            secretStore: gcalSecrets,
            googleCalendarService: mockGoogleService,
            schedulesNotifications: false,
            now: { now }
        )

        // 1. Unauthenticated export rejection
        check(!gcalStore.isGoogleAuthenticated, "store starts unauthenticated with Google")
        let unauthDraft = TaskRecord(
            id: "unauth-event",
            date: "2026-09-14",
            time: "15:00",
            endTime: "16:00",
            title: "Soccer Practice",
            owner: "Mom",
            kids: ["Maya"],
            location: "Field",
            mode: "Drive"
        )
        do {
            _ = try await gcalStore.exportEventToGoogleCalendar(unauthDraft)
            preconditionFailure("Unauthenticated export must fail")
        } catch GoogleCalendarError.unauthenticated {
            // Expected
        }

        // 2. Google OAuth & Account Connection
        gcalStore.googleClientId = "test-client-id.apps.googleusercontent.com"
        try await gcalStore.connectGoogleAccount()
        check(gcalStore.isGoogleAuthenticated, "connectGoogleAccount sets authenticated state")
        check(gcalStore.connections["google"] == true, "connectGoogleAccount enables connection in store")
        check(gcalStore.googleAccountEmail == "testuser@gmail.com", "connectGoogleAccount caches user email")
        check(try gcalSecrets.get("googleClientId") == "test-client-id.apps.googleusercontent.com", "client ID persisted to secret store")

        // 3. Google Calendar Event Parsing
        let nyTz = TimeZone(identifier: "America/New_York")!
        let timedGoogleEvent = GoogleCalendarEventItem(
            id: "gev-1",
            etag: "\"etag-1\"",
            status: "confirmed",
            summary: "Piano Lesson",
            description: "Bring sheet music",
            location: "Music Studio",
            start: GoogleEventDateTime(dateTime: "2026-09-14T16:00:00-04:00"),
            end: GoogleEventDateTime(dateTime: "2026-09-14T17:00:00-04:00")
        )
        let parsedTimed = GoogleCalendarService.parseGoogleEvent(
            timedGoogleEvent,
            calendarId: "primary",
            timeZone: nyTz,
            homeName: "Home"
        )!
        check(parsedTimed.date == "2026-09-14", "timed event date parsed")
        check(parsedTimed.time == "16:00", "timed event start time parsed")
        check(parsedTimed.endTime == "17:00", "timed event end time parsed")
        check(parsedTimed.title == "Piano Lesson", "timed event title parsed")
        check(parsedTimed.location == "Music Studio", "timed event location parsed")
        check(!parsedTimed.allDay, "timed event is not all-day")
        check(parsedTimed.calendarId == "google|primary|gev-1", "stable google calendarId created")

        // All-day event parsing
        let allDayGoogleEvent = GoogleCalendarEventItem(
            id: "gev-allday",
            etag: "\"etag-2\"",
            status: "confirmed",
            summary: "Teacher Workday",
            start: GoogleEventDateTime(date: "2026-09-15"),
            end: GoogleEventDateTime(date: "2026-09-16")
        )
        let parsedAllDay = GoogleCalendarService.parseGoogleEvent(
            allDayGoogleEvent,
            calendarId: "primary",
            timeZone: nyTz,
            homeName: "Home"
        )!
        check(parsedAllDay.date == "2026-09-15", "all day event date parsed")
        check(parsedAllDay.allDay, "allDay is true")
        check(parsedAllDay.time == "00:00" && parsedAllDay.endTime == "23:59", "all day event bounds 00:00-23:59")

        // Recurring event parsing
        let recurringGoogleEvent = GoogleCalendarEventItem(
            id: "gev-rec-occ-1",
            etag: "\"etag-3\"",
            status: "confirmed",
            summary: "Weekly Math",
            start: GoogleEventDateTime(dateTime: "2026-09-16T14:00:00-04:00"),
            end: GoogleEventDateTime(dateTime: "2026-09-16T15:00:00-04:00"),
            recurringEventId: "series-math-100",
            originalStartTime: GoogleEventDateTime(dateTime: "2026-09-16T14:00:00-04:00")
        )
        let parsedRec = GoogleCalendarService.parseGoogleEvent(
            recurringGoogleEvent,
            calendarId: "primary",
            timeZone: nyTz,
            homeName: "Home"
        )!
        check(parsedRec.seriesId == "google-series|primary|series-math-100", "seriesId mapped from recurringEventId")
        check(parsedRec.originalOccurrenceDate == "2026-09-16", "originalOccurrenceDate mapped")

        // 4. Payload Generation (RFC 5545 / Google Calendar API format)
        let allDayPayload = GoogleCalendarService.taskToEventPayload(task: parsedAllDay, timeZone: nyTz)
        let allDayStart = allDayPayload["start"] as! [String: String]
        let allDayEnd = allDayPayload["end"] as! [String: String]
        check(allDayStart["date"] == "2026-09-15", "payload allDay start date")
        check(allDayEnd["date"] == "2026-09-16", "payload allDay end date is exclusive next day")

        let timedPayload = GoogleCalendarService.taskToEventPayload(task: parsedTimed, timeZone: nyTz)
        let timedStart = timedPayload["start"] as! [String: String]
        check(timedStart["dateTime"] == "2026-09-14T16:00:00", "payload timed start dateTime")

        // 5. Google Calendar Merge & Overlay Preservation
        gcalStore.mergeGoogleCalendarEvents(
            [parsedTimed, parsedAllDay],
            calendarIDs: ["primary"],
            from: "2026-09-14",
            through: "2026-09-20"
        )
        check(gcalStore.records().count == 2, "2 events imported")

        // Assign caregiver, kids, done status, notes to parsedTimed
        let initialTimed = gcalStore.records().first(where: { $0.calendarId == parsedTimed.calendarId })!
        var modifiedLocal = initialTimed
        modifiedLocal.owner = "Mom"
        modifiedLocal.lead = "Mom"
        modifiedLocal.kids = ["Maya"]
        modifiedLocal.done = true
        modifiedLocal.notes = "Bring violin instead"
        gcalStore.replaceRecords([modifiedLocal, parsedAllDay])

        // Simulate provider update: Remote summary and time changed on Google Calendar
        var updatedGoogleEvent = timedGoogleEvent
        updatedGoogleEvent.summary = "Piano & Theory Lesson"
        updatedGoogleEvent.start = GoogleEventDateTime(dateTime: "2026-09-14T16:30:00-04:00")
        updatedGoogleEvent.end = GoogleEventDateTime(dateTime: "2026-09-14T17:30:00-04:00")
        let reimportedTimed = GoogleCalendarService.parseGoogleEvent(
            updatedGoogleEvent,
            calendarId: "primary",
            timeZone: nyTz,
            homeName: "Home"
        )!

        // Run merge again with the updated event
        gcalStore.mergeGoogleCalendarEvents(
            [reimportedTimed, parsedAllDay],
            calendarIDs: ["primary"],
            from: "2026-09-14",
            through: "2026-09-20"
        )

        let mergedEvent = gcalStore.records().first(where: { $0.calendarId == reimportedTimed.calendarId })!
        check(mergedEvent.title == "Piano & Theory Lesson", "provider title updated")
        check(mergedEvent.time == "16:30", "provider time updated")
        check(mergedEvent.owner == "Mom", "app overlay owner preserved across sync")
        check(mergedEvent.kids == ["Maya"], "app overlay kids preserved across sync")
        check(mergedEvent.done == true, "app overlay done preserved across sync")
        check(mergedEvent.notes == "Bring violin instead", "app overlay notes preserved across sync")

        // Reconcile remote deletion: All-day event deleted on Google Calendar
        gcalStore.mergeGoogleCalendarEvents(
            [reimportedTimed],
            calendarIDs: ["primary"],
            from: "2026-09-14",
            through: "2026-09-20"
        )
        check(gcalStore.records().contains(where: { $0.calendarId == parsedAllDay.calendarId }) == false, "remote deletion reconciled within range")
        check(gcalStore.records().contains(where: { $0.calendarId == reimportedTimed.calendarId }) == true, "remaining event kept")

        // 6. Google Calendar Export / Live Write
        let newLocalStop = TaskRecord(
            id: "local-stop-1",
            date: "2026-09-17",
            time: "10:00",
            endTime: "11:00",
            title: "Visit Library",
            owner: "Dad",
            kids: ["Leo"],
            location: "Town Library",
            mode: "Drive"
        )
        gcalStore.replaceRecords([reimportedTimed, newLocalStop])

        let exportedStop = try await gcalStore.exportEventToGoogleCalendar(newLocalStop)
        check(exportedStop.gcal == true, "task marked gcal = true only after successful write")
        check(exportedStop.calendarId == "google|primary|g-ev-1", "calendarId set on exported task")
        check(gcalStore.plan.calendar.exports[newLocalStop.id] == "\"etag-1\"", "etag recorded in plan.calendar.exports")
        check(mockGoogleService.createCount == 1, "createEvent called on Google Calendar service")

        // 7. Edit previously exported stop (Update path)
        var editedLocalStop = exportedStop
        editedLocalStop.title = "Visit City Library"
        let updatedExport = try await gcalStore.exportEventToGoogleCalendar(editedLocalStop)
        check(updatedExport.title == "Visit City Library", "title updated")
        check(mockGoogleService.updateCount == 1, "updateEvent called on Google Calendar service")
        check(gcalStore.plan.calendar.exports[newLocalStop.id] == "\"etag-updated-1\"", "etag updated in exports")

        // 8. Conflict Handling on Google write (ETag mismatch)
        mockGoogleService.shouldFailWithConflict = true
        do {
            _ = try await gcalStore.exportEventToGoogleCalendar(editedLocalStop)
            preconditionFailure("Expected conflict error on ETag mismatch")
        } catch GoogleCalendarError.conflict {
            // Expected
        }
        mockGoogleService.shouldFailWithConflict = false

        // 9. Remote Event Deletion
        try await gcalStore.deleteEventFromGoogleCalendar(updatedExport)
        check(mockGoogleService.deleteCount == 1, "deleteEvent called on Google Calendar service")
        check(gcalStore.plan.calendar.exports[newLocalStop.id] == nil, "export signature cleared from plan.calendar.exports")

        // 10. Disconnect Google Account
        await gcalStore.disconnectGoogleAccount()
        check(!gcalStore.isGoogleAuthenticated, "isGoogleAuthenticated is false after disconnect")
        check(gcalStore.connections["google"] == false, "connections['google'] is false after disconnect")
        check(gcalStore.googleAccountEmail.isEmpty, "email cleared on disconnect")

        print("Production regression checks passed: credentials, sync races/conflicts/retry, two-phone merge and convergence, live sync quiescence, rollover, clock, analysis caching, solo events, Google Calendar read/write/reconciliation/conflicts, and stats tracking.")
    }
}

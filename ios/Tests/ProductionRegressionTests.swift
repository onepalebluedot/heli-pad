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
    static var requireListsSchema = false
    static var listsSchemaExists = false
    static var failListsSetup = false
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
        let listsSetup = query.contains("CREATE TABLE IF NOT EXISTS helipad_household_lists")
        let schemaFailure = (listsSetup && Self.failListsSetup) ||
            (Self.requireListsSchema && !Self.listsSchemaExists && query.contains("FROM helipad_household_lists"))
        if listsSetup && !Self.failListsSetup { Self.listsSchemaExists = true }
        let rows: [[String: Any]] = query.contains("AS lists_ready")
            ? [["lists_ready": Self.listsSchemaExists]]
            : (query.contains("RETURNING") && !Self.returnConflict ? [["revision": "2026-09-08 12:00:00+00"]] : [])
        let response = HTTPURLResponse(url: request.url!, statusCode: schemaFailure ? 400 : 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: ["rows": rows]))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

// MARK: - Lists test doubles

/// Stands in for the `helipad_household_lists` record: one document, one
/// revision, compare-and-swap enforcement, and counters so a test can prove a
/// call did or did not happen.
final class MockListsCloud: HouseholdListsCloudService {
    var document: HouseholdListsArchive?
    var revision: String?
    var pushCount = 0
    var pullCount = 0
    var revisionCount = 0
    var failPulls = false
    var failPushes = false
    var onPush: (() async -> Void)?
    var onRevision: (() async -> Void)?
    private var counter = 0

    func fetchListsRevision(householdId: String, rawConnectionString: String) async throws -> String? {
        revisionCount += 1
        if let hook = onRevision { onRevision = nil; await hook() }
        if failPulls { throw NeonError.networkError("offline") }
        return revision
    }

    func pullLists(householdId: String, rawConnectionString: String) async throws -> RemoteHouseholdLists? {
        pullCount += 1
        if failPulls { throw NeonError.networkError("offline") }
        guard let document, let revision else { return nil }
        return RemoteHouseholdLists(archive: try document.migrated(), revision: revision,
                                    needsMigrationUpload: document.version != HouseholdListsArchive.currentVersion)
    }

    func pushLists(
        _ archive: HouseholdListsArchive,
        householdId: String,
        expectedRevision: String?,
        rawConnectionString: String
    ) async throws -> String {
        pushCount += 1
        if let hook = onPush { onPush = nil; await hook() }
        if failPushes { throw NeonError.networkError("offline") }
        guard expectedRevision == revision else { throw NeonError.conflict }
        counter += 1
        revision = "r\(counter)"
        document = archive
        return revision!
    }
}

/// Stands in for `AppStore`: the shared logical clock, the household identity,
/// and the storage switch — without a whole household.
final class MockListsHost: HouseholdListsHost {
    var householdID: String
    var defaults: UserDefaults
    var enabled = true
    var connection: String?
    var lamport = 0
    var deviceID: String

    init(householdID: String, defaults: UserDefaults, deviceID: String, connection: String? = "postgres://test") {
        self.householdID = householdID
        self.defaults = defaults
        self.deviceID = deviceID
        self.connection = connection
    }

    func listsNextStamp() -> RecordStamp {
        lamport += 1
        return RecordStamp(counter: lamport, deviceID: deviceID)
    }

    func listsObserve(_ stamp: RecordStamp) {
        if stamp.counter > lamport { lamport = stamp.counter }
    }

    var listsHouseholdID: String { householdID }
    var listsPersistenceDefaults: UserDefaults { defaults }
    var listsPersistenceEnabled: Bool { enabled }
    func listsCloudContext() -> ListsCloudContext? {
        connection.map { ListsCloudContext(householdID: householdID, connection: $0) }
    }
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
        check(
            NotificationService.overdueDate(for: reminderEvent, calendar: reminderCalendar)
                == iso.date(from: "2026-09-14T19:00:00Z")!,
            "overdue check-in fires two hours after the stop's end"
        )
        check(
            NotificationService.overdueDate(
                for: reminderEvent,
                calendar: reminderCalendar,
                snoozedUntil: iso.date(from: "2026-09-14T20:30:00Z")!
            ) == iso.date(from: "2026-09-14T20:30:00Z")!,
            "a snooze pushes the check-in back"
        )
        check(
            NotificationService.overdueDate(
                for: reminderEvent,
                calendar: reminderCalendar,
                snoozedUntil: iso.date(from: "2026-09-14T18:00:00Z")!
            ) == iso.date(from: "2026-09-14T19:00:00Z")!,
            "a snooze never brings the check-in forward"
        )
        let overnight = TaskRecord(id: "overnight", date: "2026-09-14", time: "22:00", endTime: "01:00", title: "Late shift", owner: "Mom")
        check(
            NotificationService.overdueDate(for: overnight, calendar: reminderCalendar)
                == iso.date(from: "2026-09-15T03:00:00Z")!,
            "an end past midnight lands on the next day"
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
        movedWednesday.notes = "Bring goggles"
        _ = try recurrenceStore.saveEvent(
            draft: movedWednesday,
            recurrence: RecurrencePattern(mode: .none, startDate: movedWednesday.date),
            scope: .occurrence,
            sourceOccurrenceID: movedWednesday.id,
            updateNotes: true
        )
        check(recurrenceStore.records().first { $0.id == movedWednesday.id }?.notes == "Bring goggles", "event context can be explicitly edited on an occurrence")
        let deletedWednesday = recurrenceStore.events(inSeries: "swim").first { $0.date == "2026-09-23" }!
        recurrenceStore.deleteEvent(id: deletedWednesday.id, scope: .occurrence)
        var editReference = recurrenceStore.records().first { $0.id == firstWednesday.id }!
        let wednesdaysOnly = RecurrencePattern(mode: .weekly, startDate: "2026-09-14", timeZone: "America/Detroit", weekdays: [2], end: .weekCount(21))
        editReference.title = "Swim"
        _ = try recurrenceStore.saveEvent(draft: editReference, recurrence: wednesdaysOnly, scope: .series, sourceOccurrenceID: firstWednesday.id)
        let narrowed = recurrenceStore.events(inSeries: "swim")
        check(narrowed.first { $0.id == movedWednesday.id }?.notes == "Bring goggles", "unrelated series edits preserve occurrence context")
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
        check(overdueData.live == -1, "an ended stop does not hold the hero")
        check(overdueData.looseEndEvents.map(\.id) == ["overdue"], "ended unfinished work remains actionable as a loose end")
        check(overdueData.restingState == .outstanding(2), "timed and all-day unfinished work prevent an all-clear state")

        // A stop nobody ticked off must not hide the one that is actually next.
        overdueStore.replaceRecords([
            TaskRecord(id: "next", date: "2026-09-14", time: "19:30", endTime: "20:00", title: "Pickup", owner: "Mom", location: "Home", mode: "Home"),
            TaskRecord(id: "overdue", date: "2026-09-14", time: "15:00", endTime: "15:15", title: "Unfinished", owner: "Mom", location: "Home", mode: "Home")
        ])
        let movedOn = GoViewModel(store: overdueStore).computeView(store: overdueStore)
        check(movedOn.live >= 0 && movedOn.mine[movedOn.live].event.id == "next", "hero moves on to the next stop")
        check(movedOn.looseEndEvents.map(\.id) == ["overdue"], "the skipped stop is kept as a loose end")
        check(overdueStore.eventsByDay[0]?.map(\.id) == ["overdue", "next"], "day buckets are kept in time order")

        check(overdueStore.reminderOwners() == nil, "the All profile is reminded about every stop")
        try? overdueStore.setActiveUser("Mom")
        check(overdueStore.reminderOwners() == ["Mom", "Family"], "a caregiver's phone reminds about their own and family stops only")
        try? overdueStore.setActiveUser("All")

        overdueStore.setEventDone(id: "overdue", done: true)
        overdueStore.setEventDone(id: "overdue", done: true)
        check(overdueStore.records().first { $0.id == "overdue" }?.done == true, "marking done twice leaves it done")

        // An all-day event owns the date, not a slot in it: it must not collide
        // with the timed stops around it, and must not raise timing risks itself.
        let allDayOptions = overdueStore.planningOptions()
        let allDayWithTimed = [
            TaskRecord(id: "timed", date: "2026-09-14", time: "15:00", endTime: "16:00", title: "Soccer", owner: "Mom", location: "Home", mode: "Home"),
            TaskRecord(id: "spirit-week", date: "2026-09-14", title: "Spirit week", owner: "Mom", location: "Home", mode: "Home", allDay: true)
        ]
        let allDayAnalyzed = PlanCore.analyze(allDayWithTimed, allDayOptions)
        let timedRow = allDayAnalyzed.first { $0.event.id == "timed" }!
        let allDayRow = allDayAnalyzed.first { $0.event.id == "spirit-week" }!
        check(!timedRow.risks.contains { $0.type == "overlap" }, "all-day event does not overlap the timed stop beside it")
        check(allDayRow.risks.isEmpty && allDayRow.status == "ready", "all-day event raises no timing risk of its own")
        check(!allDayRow.detail.conflict, "all-day event is never in conflict")
        check(!PlanCore.candidate(allDayWithTimed[0], "Mom", allDayWithTimed, allDayOptions).conflict, "all-day event is invisible to the timed plan")

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

        // The poll paces itself: quiet ticks widen the gap, anything happening
        // snaps it back. A phone left open on the counter must not keep asking
        // every couple of seconds for an answer that is always "no".
        check(AppStore.liveSyncInterval < AppStore.liveSyncIdleInterval,
              "the active poll is faster than the idle one")
        let pacer = phoneB
        pacer.stopLiveSync()
        check(pacer.liveSyncGap == AppStore.liveSyncInterval, "a fresh watcher starts at the active gap")
        var previousGap = pacer.liveSyncGap
        for _ in 0..<3 {
            check(await pacer.liveSyncTick() == .quiet, "a settled phone reports quiet")
            check(pacer.liveSyncGap > previousGap, "each quiet tick widens the gap")
            previousGap = pacer.liveSyncGap
        }
        for _ in 0..<12 { await pacer.liveSyncTick() }
        check(pacer.liveSyncGap == AppStore.liveSyncIdleInterval, "the gap settles at the idle interval, no wider")

        // News from the other phone brings it straight back.
        var wokenRecords = phoneA.records()
        wokenRecords.append(TaskRecord(id: "ev-swim", date: "2026-10-09", title: "Swim", owner: "Mom"))
        phoneA.replaceRecords(wokenRecords)
        try await phoneA.syncWithNeon()
        check(await pacer.liveSyncTick() == .changed, "a tick that finds news reports changed")
        check(pacer.liveSyncGap == AppStore.liveSyncInterval, "news snaps the gap back to the active interval")

        // So does an edit made here, because the other phone tends to answer it.
        for _ in 0..<12 { await pacer.liveSyncTick() }
        check(pacer.liveSyncGap == AppStore.liveSyncIdleInterval, "back to idle while nothing happens")
        retitle(pacer, "Piano recital")
        check(pacer.liveSyncGap == AppStore.liveSyncInterval, "a local edit re-quickens the poll")

        // A household with sync switched off has nothing to ask about.
        let dormant = phone(store(shared), UserDefaults(suiteName: "helipad.dormant.\(UUID().uuidString)")!)
        dormant.neonSyncEnabled = false
        check(await dormant.liveSyncTick() == .dormant, "sync switched off reports dormant")
        check(dormant.liveSyncGap == AppStore.liveSyncIdleInterval, "and goes straight to the idle gap")
        check(await shared.uploadCount() != -1, "dormant ticks reach no network")

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
        // Lists must initialise their own table before their very first read.
        // A missing table is an HTTP 400 from Neon, not an empty household.
        SQLProtocol.returnConflict = false
        SQLProtocol.requireListsSchema = true
        SQLProtocol.listsSchemaExists = false
        SQLProtocol.requests = []
        let freshListsTransport = NeonListsCloudService(database: transport)
        _ = try await freshListsTransport.fetchListsRevision(householdId: "new-home", rawConnectionString: syncing.neonConnectionString)
        _ = try await freshListsTransport.pullLists(householdId: "new-home", rawConnectionString: syncing.neonConnectionString)
        check(SQLProtocol.listsSchemaExists, "fresh list reads prepare the schema before querying it")
        check(SQLProtocol.requests.filter { ($0["query"] as? String)?.contains("CREATE TABLE") == true }.count == 1,
              "list reads share successful setup instead of issuing DDL on every poll")
        check(SQLProtocol.requests.allSatisfy { $0["params"] is [Any] }, "every SQL request includes a params array")
        SQLProtocol.failListsSetup = true
        let readWriteOnlyTransport = NeonListsCloudService(database: transport)
        _ = try await readWriteOnlyTransport.pullLists(householdId: "new-home", rawConnectionString: syncing.neonConnectionString)
        check(SQLProtocol.requests.filter { ($0["query"] as? String)?.contains("CREATE TABLE") == true }.count == 1,
              "existing tables can sync without CREATE permission")
        let permissionBody = Data(#"{"code":"42501","message":"secret postgres://private@host/db"}"#.utf8)
        let safeError = NeonDatabaseService.safeServerError(permissionBody)
        check(safeError.contains("permission") && !safeError.contains("private"), "sync errors explain permissions without exposing the raw response")
        SQLProtocol.listsSchemaExists = false
        SQLProtocol.failListsSetup = true
        let retryListsTransport = NeonListsCloudService(database: transport)
        do {
            _ = try await retryListsTransport.pullLists(householdId: "new-home", rawConnectionString: syncing.neonConnectionString)
            preconditionFailure("A setup failure must be surfaced")
        } catch NeonError.serverError {}
        SQLProtocol.failListsSetup = false
        _ = try await retryListsTransport.pullLists(householdId: "new-home", rawConnectionString: syncing.neonConnectionString)
        check(SQLProtocol.listsSchemaExists, "a failed setup can be retried")
        var privateArchive = HouseholdListsDefaults.archive(householdID: "new-home", connectionFingerprint: "postgres://test:private@example/db")
        privateArchive.localRevision = 9
        privateArchive.uploadedRevision = 7
        _ = try await retryListsTransport.pushLists(privateArchive, householdId: "new-home", expectedRevision: nil, rawConnectionString: syncing.neonConnectionString)
        let sentLists = (SQLProtocol.requests.last!["params"] as! [Any])[1] as! String
        check(!sentLists.contains("postgres://") && !sentLists.contains("private@example"), "shared list documents never carry a connection URI")
        let decodedLists = try JSONDecoder().decode(HouseholdListsArchive.self, from: Data(sentLists.utf8))
        check(decodedLists.localRevision == 0 && decodedLists.uploadedRevision == 0, "a peer cannot inherit another device's sync counters")
        SQLProtocol.requireListsSchema = false

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

        // 5b. An edit made here, that never reached Google, must survive the
        // next import. Google repeating itself is not a change, and taking its
        // fields anyway silently reverted the household's own work overnight.
        var editedHere = gcalStore.records().first(where: { $0.calendarId == reimportedTimed.calendarId })!
        editedHere.time = "18:00"
        editedHere.endTime = "19:00"
        editedHere.title = "Piano — moved in HeliPad"
        editedHere.location = "Studio B"
        gcalStore.replaceRecords([editedHere])
        gcalStore.mergeGoogleCalendarEvents(
            [reimportedTimed],
            calendarIDs: ["primary"],
            from: "2026-09-14",
            through: "2026-09-20"
        )
        let afterIdleImport = gcalStore.records().first(where: { $0.calendarId == reimportedTimed.calendarId })!
        check(afterIdleImport.time == "18:00", "local time edit survives an unchanged re-import")
        check(afterIdleImport.title == "Piano — moved in HeliPad", "local title edit survives an unchanged re-import")
        check(afterIdleImport.location == "Studio B", "local location edit survives an unchanged re-import")

        // ...and a real upstream move still wins over that local edit.
        var movedOnGoogle = updatedGoogleEvent
        movedOnGoogle.start = GoogleEventDateTime(dateTime: "2026-09-14T20:00:00-04:00")
        movedOnGoogle.end = GoogleEventDateTime(dateTime: "2026-09-14T21:00:00-04:00")
        let movedParsed = GoogleCalendarService.parseGoogleEvent(
            movedOnGoogle, calendarId: "primary", timeZone: nyTz, homeName: "Home"
        )!
        gcalStore.mergeGoogleCalendarEvents(
            [movedParsed],
            calendarIDs: ["primary"],
            from: "2026-09-14",
            through: "2026-09-20"
        )
        let afterUpstreamMove = gcalStore.records().first(where: { $0.calendarId == movedParsed.calendarId })!
        check(afterUpstreamMove.time == "20:00", "a genuine upstream move is still applied")
        check(afterUpstreamMove.owner == "Mom", "app overlay survives the upstream move")

        // 5c. Cancelling a stop while its export is still in flight must stick.
        // The export finishes holding a copy of a record that no longer exists,
        // and re-adding it put a cancelled stop back on the week minutes later.
        let cancelStore = store(TestCloud())
        cancelStore.restore(from: UserDefaults(suiteName: "helipad.cancel.\(UUID().uuidString)")!)
        cancelStore.hasCompletedOnboarding = true
        let doomed = TaskRecord(
            id: "ev-doomed", date: "2026-09-18", time: "09:00", endTime: "10:00",
            title: "Dentist", owner: "Mom", location: "Home", mode: "Home"
        )
        cancelStore.replaceRecords([doomed])
        cancelStore.deleteEvent(id: "ev-doomed")
        check(!cancelStore.records().contains { $0.id == "ev-doomed" }, "the stop is gone once cancelled")
        check(cancelStore.tombstones.contains { $0.kind == .event && $0.id == "ev-doomed" },
              "cancelling leaves a tombstone")
        // The in-flight export lands afterwards, carrying the pre-delete copy.
        var exportedLate = doomed
        exportedLate.gcal = true
        exportedLate.calendarId = "google|primary|late-write"
        cancelStore.applyExportedRecordsForTesting([exportedLate])
        check(!cancelStore.records().contains { $0.id == "ev-doomed" },
              "a late export does not resurrect a cancelled stop")
        check(cancelStore.plan.calendar.exports["ev-doomed"] == nil,
              "and its stale export bookkeeping is dropped")

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

        // 7b. Exporting a series writes the household once, not once per stop.
        // Saving per occurrence ran reconcile, persist, a notification
        // reschedule and a cloud sync for every occurrence, which locked the
        // app up after adding a twenty-week recurrence.
        let seriesStops = (0..<3).map { index in
            TaskRecord(
                id: "series-stop-\(index)",
                date: PlanCore.dateAdd("2026-09-22", index * 7),
                time: "15:00",
                endTime: "15:20",
                title: "Pickup",
                owner: "Dad",
                kids: ["Leo"],
                location: "Town Library",
                mode: "Drive",
                seriesId: "series-batch-1"
            )
        }
        gcalStore.replaceRecords(gcalStore.records() + seriesStops)
        let createsBefore = mockGoogleService.createCount
        let revisionBefore = gcalStore.contentRevision

        let exportedSeries = await gcalStore.exportEventsToGoogleCalendar(seriesStops)
        check(exportedSeries.count == 3, "every occurrence in the series is exported")
        check(
            mockGoogleService.createCount - createsBefore == 3,
            "one remote write per occurrence"
        )
        check(
            gcalStore.contentRevision - revisionBefore == 1,
            "the whole series costs exactly one household save"
        )
        check(
            exportedSeries.allSatisfy { $0.gcal && ($0.calendarId?.hasPrefix("google|") ?? false) },
            "every exported occurrence is marked and carries its provider key"
        )
        check(
            gcalStore.records().filter { $0.seriesId == "series-batch-1" }.allSatisfy(\.gcal),
            "exported series is persisted back into the household"
        )

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

        // MARK: - Event provenance and legacy decoding
        //
        // Shortcut suggestions depend on knowing how an event was created.
        // These guard the migration path: old households must decode intact,
        // and every creation path must record what made it.

        let provenance = store()

        // A record written before provenance existed: no `origin` key at all.
        // It must decode intact rather than being dropped or rewritten.
        let legacyJSON = #"""
        [{"id":"legacy-1","date":"2026-09-07","time":"08:00","endTime":"08:30",
          "title":"School drop-off","owner":"Kellie","lead":"Kellie","kids":["Soni"],"kid":"Soni",
          "location":"Goddard School","mode":"Drive","kind":"dropoff","done":false,
          "tentative":false,"locked":false,"gcal":false,"notes":"","allDay":false}]
        """#
        let legacyEvents = try JSONDecoder().decode([TaskRecord].self, from: Data(legacyJSON.utf8))
        check(legacyEvents.count == 1, "legacy event JSON decodes without losing events")
        check(legacyEvents.first?.origin == nil, "legacy events keep nil provenance rather than being rewritten")
        check(legacyEvents.first?.title == "School drop-off", "legacy event content is preserved verbatim")
        check(legacyEvents.first?.countsAsManualEffort == true,
              "a legacy standalone event still counts as manual effort")

        var seriesLegacy = legacyEvents[0]
        seriesLegacy.seriesId = "series-x"
        check(seriesLegacy.countsAsManualEffort == false, "legacy series occurrence is not manual effort")
        var importedLegacy = legacyEvents[0]
        importedLegacy.calendarId = "google|cal|evt"
        check(importedLegacy.countsAsManualEffort == false, "legacy imported event is not manual effort")

        // And a whole household round-trips through the real persistence path
        // with the new field present.
        let roundTripSuite = "helipad.provenance.\(UUID().uuidString)"
        let roundTripDefaults = UserDefaults(suiteName: roundTripSuite)!
        defer { roundTripDefaults.removePersistentDomain(forName: roundTripSuite) }
        provenance.restore(from: roundTripDefaults)
        let beforeCount = provenance.records().count
        provenance.save(syncToCloud: false)
        let reloaded = store()
        reloaded.restore(from: roundTripDefaults)
        check(reloaded.records().count == beforeCount,
              "persist/restore keeps every event after adding provenance")

        // Manual save path.
        let manualDraft = TaskRecord(
            id: "prov-manual", date: "2026-09-14", time: "08:00", endTime: "08:30",
            title: "Drop off", owner: "Kellie", kids: ["Soni"], location: "Goddard School", kind: .dropoff
        )
        let savedManual = try provenance.saveEvent(
            draft: manualDraft,
            recurrence: RecurrencePattern(mode: .none, startDate: "2026-09-14", timeZone: "UTC")
        )
        check(savedManual.first?.origin == .manual, "editor save records manual provenance")

        // Recurrence path.
        let seriesDraft = TaskRecord(
            id: "prov-series", date: "2026-09-14", time: "16:00", endTime: "17:00",
            title: "Swim", owner: "Kellie", kids: ["Soni"], location: "Pool", kind: .practice
        )
        let savedSeries = try provenance.saveEvent(
            draft: seriesDraft,
            recurrence: RecurrencePattern(
                mode: .weekly, startDate: "2026-09-14", timeZone: "UTC",
                weekdays: [0], end: .weekCount(3)
            )
        )
        check(savedSeries.count == 3, "weekly series materialises its occurrences")
        check(savedSeries.allSatisfy { if case .recurrence = $0.origin { return true }; return false },
              "series occurrences record recurrence provenance")
        check(savedSeries.allSatisfy { $0.countsAsManualEffort == false },
              "series occurrences are not manual effort")

        // Shortcut path.
        let shortcutTemplate = TemplateItem(
            id: "tmpl-1", title: "Drop Off", time: "08:00", endTime: "08:30",
            kids: ["Soni"], owner: "Kellie", location: "Goddard School", duration: 30
        )
        let fromShortcut = FamilyCore.eventDraft(template: shortcutTemplate, date: "2026-09-15")
        check(fromShortcut.origin == .shortcut(templateID: "tmpl-1"),
              "shortcut-created event records the template it came from")
        check(fromShortcut.countsAsManualEffort == false, "shortcut-created events are not manual effort")
        let savedFromShortcut = try provenance.saveEvent(
            draft: fromShortcut,
            recurrence: RecurrencePattern(mode: .none, startDate: "2026-09-15", timeZone: "UTC")
        )
        check(savedFromShortcut.first?.origin == .shortcut(templateID: "tmpl-1"),
              "saveEvent does not overwrite provenance the caller already set")

        // MARK: - Lists: identity, storage and commands
        //
        // Two things a household can lose here: the lists themselves through a
        // bad save, and the schedule through a list edit. The checks below are
        // about both.

        let listsSuite = "helipad.lists.\(UUID().uuidString)"
        let listsDefaults = UserDefaults(suiteName: listsSuite)!
        defer { listsDefaults.removePersistentDomain(forName: listsSuite) }

        func listsHost(_ household: String, _ device: String, into defaults: UserDefaults) -> MockListsHost {
            MockListsHost(householdID: household, defaults: defaults, deviceID: device)
        }

        // 1. A household that has never used Lists.
        let listsHostA = listsHost("household-a", "phone-a", into: listsDefaults)
        let cloudA = MockListsCloud()
        let lists = HouseholdListsStore(cloud: cloudA)
        lists.attach(to: listsHostA)

        check(lists.lists(.todos).count == 1 && lists.lists(.groceries).count == 1,
              "a household that has never used Lists gets exactly two lists")
        check(lists.remainingCount(of: lists.defaultList(.todos)!.id) == 0,
              "the lists arrive empty, never carrying sample data")
        check(lists.archive.lists.count == 2, "a household's archive describes exactly two lists")
        check(lists.defaultList(.todos)!.kind == .todos && lists.defaultList(.groceries)!.kind == .groceries,
              "each derived list knows which kind it is")
        check(lists.groups(of: lists.defaultList(.todos)!.id).map(\.name) == ["General"],
              "every list starts with one General section")
        check(lists.syncState == .upToDate, "empty lists with a configured connection have no pending local edits")

        // Legacy cloud documents contain the two defaults plus optional lists.
        // They must migrate before strict validation, never be pruned as noise.
        var legacyLists = HouseholdListsDefaults.archive(householdID: "migration-home", now: Date(timeIntervalSince1970: 100))
        legacyLists.version = 1
        legacyLists.lists.append(HouseholdList(id: "old-project", kind: .todos, name: "Garage project"))
        legacyLists.groups.append(HouseholdListGroup(id: "old-general", listID: "old-project", name: "General"))
        legacyLists.items.append(HouseholdListItem(id: "old-task", listID: "old-project", groupID: "old-general",
                                                  text: "Sort tools", note: "Keep the blue box", completedAt: Date(timeIntervalSince1970: 200)))
        legacyLists.subtasks.append(ListSubtask(id: "old-step", itemID: "old-task", text: "Label drawers", rank: 0))
        let migratedLists = try legacyLists.migrated()
        check(migratedLists.lists.count == 2 && migratedLists.version == HouseholdListsArchive.currentVersion,
              "legacy extra lists migrate to the two-primary-list format")
        check(migratedLists.items.first?.id == "old-task" && migratedLists.items.first?.isCompleted == true &&
              migratedLists.items.first?.note == "Keep the blue box" && migratedLists.subtasks.first?.id == "old-step",
              "migration preserves item identity, completion, notes and steps")
        check(migratedLists.groups.first(where: { $0.id == "old-general" })?.name == "Garage project",
              "legacy list name becomes a section instead of losing its contents")
        check(try migratedLists.migrated() == migratedLists, "migration is idempotent")
        let migrationSuite = "helipad.lists.migration.\(UUID().uuidString)"
        let migrationDefaults = UserDefaults(suiteName: migrationSuite)!
        defer { migrationDefaults.removePersistentDomain(forName: migrationSuite) }
        let legacyBytes = try JSONEncoder().encode(legacyLists)
        migrationDefaults.set(legacyBytes, forKey: HouseholdListsPersistence.quarantineKey(householdID: "migration-home"))
        guard case .loaded(let recoveredLists) = HouseholdListsPersistence.load(householdID: "migration-home", from: migrationDefaults) else {
            preconditionFailure("expected recovery of readable legacy lists")
        }
        check(recoveredLists.items.count == 1 && HouseholdListsPersistence.quarantined(householdID: "migration-home", from: migrationDefaults) == legacyBytes,
              "a quarantined legacy archive recovers without replacing its original backup")
        let migrationCloud = MockListsCloud()
        migrationCloud.document = legacyLists
        migrationCloud.revision = "legacy-r1"
        let migrationHost = listsHost("migration-home", "migration-phone", into: migrationDefaults)
        let migrationStore = HouseholdListsStore(cloud: migrationCloud)
        migrationStore.attach(to: migrationHost)
        await migrationStore.sync()
        check(migrationStore.syncState == .upToDate && migrationCloud.document?.version == HouseholdListsArchive.currentVersion,
              "legacy cloud lists finish migration and sync instead of showing not syncing")
        check(migrationCloud.document?.items.first?.text == "Sort tools", "migration upload preserves the old remote item")
        let migratedTodo = migrationStore.defaultList(.todos)!.id
        let migratedGeneral = migrationStore.generalGroup(of: migratedTodo)!.id
        let batchDrafts = [ListItemDraft(id: "assistant-task", listID: migratedTodo, groupID: migratedGeneral, text: "Clean garage")]
        _ = try migrationStore.addItems(batchDrafts)
        _ = try migrationStore.addItems(batchDrafts)
        check(migrationStore.archive.items.filter { $0.id == "assistant-task" }.count == 1, "confirmed list batch retries are idempotent")
        check(migrationStore.archive.localRevision > migrationStore.archive.uploadedRevision, "an edit after migration is still pending")
        let beforeBadBatch = migrationStore.archive
        do {
            _ = try migrationStore.addItems([
                ListItemDraft(id: "valid-first", listID: migratedTodo, groupID: migratedGeneral, text: "First"),
                ListItemDraft(id: "invalid-second", listID: migratedTodo, groupID: migratedGeneral, text: " ")
            ])
            preconditionFailure("invalid batch must fail")
        } catch {}
        check(migrationStore.archive == beforeBadBatch, "an invalid assistant batch saves no partial items")
        await migrationStore.sync()
        check(migrationCloud.document?.items.contains(where: { $0.id == "assistant-task" }) == true,
              "assistant additions go through the shared sync pipeline")

        // 2. Identity is derived, not synced: a second phone agrees untold.
        let peerSuite = "helipad.lists.peer.\(UUID().uuidString)"
        let peerDefaults = UserDefaults(suiteName: peerSuite)!
        defer { peerDefaults.removePersistentDomain(forName: peerSuite) }
        let listsHostB = listsHost("household-a", "phone-b", into: peerDefaults)
        let peer = HouseholdListsStore(cloud: MockListsCloud())
        peer.attach(to: listsHostB)
        check(peer.defaultList(.groceries)!.id == lists.defaultList(.groceries)!.id,
              "both phones derive the same default list identity from the household")
        check(peer.groups(of: peer.defaultList(.todos)!.id) == lists.groups(of: lists.defaultList(.todos)!.id),
              "both phones derive the same General section")

        // 3. Commands.
        let groceriesID = lists.defaultList(.groceries)!.id
        let generalID = lists.generalGroup(of: groceriesID)!.id
        let milk = lists.addItem(listID: groceriesID, groupID: generalID, text: "  Oat milk  ", quantity: "2 cartons")
        check(milk != nil, "an item can be added")
        check(lists.item(milk!)?.text == "Oat milk", "item text is trimmed on the way in")
        check(lists.item(milk!)?.quantity == "2 cartons", "a grocery quantity is kept")
        check(lists.addItem(listID: groceriesID, groupID: generalID, text: "   ") == nil,
              "a blank item is rejected rather than stored")

        let bread = lists.addItem(listID: groceriesID, groupID: generalID, text: "Bread", quantity: "1 loaf")!
        check(lists.items(of: groceriesID, inGroup: generalID).map(\.text) == ["Oat milk", "Bread"],
              "new items keep their order")
        lists.moveItem(id: bread, by: -1)
        check(lists.items(of: groceriesID, inGroup: generalID).map(\.text) == ["Bread", "Oat milk"],
              "an item can be reordered inside its section")
        check(lists.items(of: groceriesID, inGroup: generalID).map(\.rank) == [0, 1],
              "reordering leaves dense ranks")

        lists.setCompleted(id: milk!, to: true)
        check(lists.item(milk!)?.isCompleted == true, "an item can be checked off")
        lists.setCompleted(id: milk!, to: true)
        check(lists.item(milk!)?.isCompleted == true, "replaying a completion keeps the requested state")
        check(lists.duplicate(of: groceriesID, matching: "Oat milk") == nil,
              "a checked-off row is not offered as a duplicate")
        check(lists.duplicate(of: groceriesID, matching: "  oat   MILK ") == nil, "normalization ignores case and spacing")
        lists.setCompleted(id: milk!, to: false)
        check(lists.item(milk!)?.isCompleted == false, "an item can be reopened")
        check(lists.duplicate(of: groceriesID, matching: "  oat   MILK ")?.id == milk,
              "a duplicate is recognized across case and whitespace")
        // Captured after the reopen: reopening is a real change, so the clock is
        // allowed to move for it. Only the tidying below must leave it alone.
        let activityBeforeMove = lists.item(milk!)!.activityAt
        lists.moveItem(id: milk!, by: -1)
        check(lists.item(milk!)!.activityAt == activityBeforeMove,
              "reordering is not activity: the cleanup clock does not move")
        check(lists.item(milk!)!.stamps.placement != nil, "a move is still stamped so it can merge")
        let stampsBeforeNote = lists.item(milk!)!.stamps
        lists.updateItem(id: milk!, text: "Oat milk", quantity: "2 cartons", note: "Barista blend", groupID: generalID)
        check(lists.item(milk!)!.stamps.placement == stampsBeforeNote.placement,
              "a note edit leaves placement unstamped, so it cannot undo a move from the other phone")
        check(lists.item(milk!)!.stamps.content != stampsBeforeNote.content, "a note edit stamps content")
        let stampsBeforeNoOp = lists.item(milk!)!.stamps
        lists.updateItem(id: milk!, text: "Oat milk", quantity: "2 cartons", note: "Barista blend", groupID: generalID)
        check(lists.item(milk!)!.stamps.content == stampsBeforeNoOp.content,
              "closing the editor without changes stamps nothing")

        // 4. Relaunch.
        let relaunched = HouseholdListsStore(cloud: MockListsCloud())
        relaunched.attach(to: listsHostA)
        check(relaunched.items(of: groceriesID, inGroup: generalID).map(\.text) == ["Oat milk", "Bread"],
              "every command survives an offline relaunch")
        check(relaunched.archive.localRevision == lists.archive.localRevision,
              "the list revision is restored rather than reset")

        // 5. Sections.
        let produce = lists.addGroup(listID: groceriesID, name: "Fruit & vegetables")!
        check(lists.groups(of: groceriesID).map(\.name) == ["General", "Fruit & vegetables"],
              "a section can be added and keeps its position")
        let avocados = lists.addItem(listID: groceriesID, groupID: produce, text: "Avocados")!
        lists.deleteGroup(id: produce)
        check(lists.groups(of: groceriesID).map(\.name) == ["General"], "a section can be removed")
        check(lists.item(avocados)?.groupID == generalID,
              "removing a section moves its rows into General instead of deleting them")
        check(lists.item(avocados)?.text == "Avocados", "the moved row keeps its wording")
        lists.deleteGroup(id: generalID)
        check(lists.groups(of: groceriesID).map(\.name) == ["General"], "General cannot be removed")
        lists.dismissUndo()

        // Exactly one General section per list, and it is the section new items land
        // in. A duplicate would leave the same name twice, with the capture bar
        // pointing at the empty one.
        check(lists.groups(of: groceriesID).filter { $0.name == "General" }.count == 1,
              "the list has exactly one General section")

        // Reordering by index, which is where dragging a section lands.
        let vegSection = lists.addGroup(listID: groceriesID, name: "Fruit & vegetables")!
        let bakerySection = lists.addGroup(listID: groceriesID, name: "Bakery")!
        check(lists.groups(of: groceriesID).map(\.name) == ["General", "Fruit & vegetables", "Bakery"],
              "added sections keep their order")
        lists.moveGroup(id: bakerySection, toIndex: 0)
        check(lists.groups(of: groceriesID).map(\.name) == ["Bakery", "General", "Fruit & vegetables"],
              "a section can be dragged to the front")
        check(lists.groups(of: groceriesID).map(\.rank) == [0, 1, 2], "reordering leaves dense ranks")
        lists.moveGroup(id: bakerySection, toIndex: 9)
        check(lists.groups(of: groceriesID).map(\.name) == ["General", "Fruit & vegetables", "Bakery"],
              "a section dragged past the end lands at the end")
        lists.moveGroup(id: vegSection, by: -1)
        check(lists.groups(of: groceriesID).map(\.name) == ["Fruit & vegetables", "General", "Bakery"],
              "moving a section by one place still works")
        check(lists.groups(of: groceriesID).filter { $0.name == "General" }.count == 1,
              "reordering never duplicates a section")
        lists.deleteGroup(id: vegSection)
        lists.deleteGroup(id: bakerySection)
        check(lists.groups(of: groceriesID).map(\.name) == ["General"], "the extra sections can be removed")
        lists.dismissUndo()

        // 6. To-dos and steps.
        let todosID = lists.defaultList(.todos)!.id
        let todosGeneral = lists.generalGroup(of: todosID)!.id
        let furnace = lists.addItem(listID: todosID, groupID: todosGeneral, text: "Replace the furnace filter")!
        let stepOne = lists.addSubtask(itemID: furnace, text: "Buy a filter")!
        _ = lists.addSubtask(itemID: furnace, text: "Fit it")
        check(lists.subtasks(of: furnace).map(\.text) == ["Buy a filter", "Fit it"], "a to-do carries ordered steps")
        lists.setSubtaskCompleted(id: stepOne, to: true)
        check(lists.subtasks(of: furnace).first?.isCompleted == true, "a step can be ticked")
        check(lists.item(furnace)?.isCompleted == false, "ticking a step does not complete the parent")
        let cheese = lists.addItem(listID: groceriesID, groupID: generalID, text: "Cheese")!
        check(lists.addSubtask(itemID: cheese, text: "Not for groceries") == nil,
              "steps stay a to-do feature; a grocery row does not take them")

        // 7. Clearing checked-off rows, and Undo.
        lists.setCompleted(id: milk!, to: true)
        check(lists.completedItems(of: groceriesID).count == 1, "one row is checked off")
        lists.clearCompleted(listID: groceriesID)
        check(lists.completedItems(of: groceriesID).isEmpty, "clearing removes the checked rows")
        check(lists.activeItems(of: groceriesID).map(\.text).contains("Bread"),
              "clearing leaves unchecked rows exactly where they were")
        check(lists.pendingUndo != nil, "clearing offers an undo")
        lists.undo()
        check(lists.completedItems(of: groceriesID).map(\.text) == ["Oat milk"],
              "undo brings the cleared row back, still checked off")
        check(lists.items(of: groceriesID, inGroup: generalID).allSatisfy { $0.id != milk },
              "the restored row carries a fresh identity")
        check(lists.pendingUndo == nil, "the undo batch is consumed by the undo")

        let listsDoomed = lists.addItem(listID: groceriesID, groupID: generalID, text: "Sesame oil")!
        lists.deleteItem(id: listsDoomed)
        check(lists.item(listsDoomed) == nil, "a removed row is gone")
        let afterRelaunch = HouseholdListsStore(cloud: MockListsCloud())
        afterRelaunch.attach(to: listsHostA)
        check(afterRelaunch.pendingUndo != nil, "the undo batch survives a relaunch")
        afterRelaunch.undo()
        check(afterRelaunch.activeItems(of: groceriesID).map(\.text).contains("Sesame oil"),
              "undo after a relaunch restores the row")
        afterRelaunch.dismissUndo()

        // 8. Advisory cleanup, and the snooze.
        let aged = Date(timeIntervalSince1970: 1_700_000_000)
        func stamp(_ counter: Int, _ device: String) -> RecordStamp { RecordStamp(counter: counter, deviceID: device) }

        var cleanup = HouseholdListsDefaults.archive(householdID: "household-c", now: aged)
        let cleanupTodos = cleanup.defaultList(of: .todos)!.id
        let cleanupTodoGroup = cleanup.generalGroup(of: cleanupTodos)!.id
        let cleanupGroceries = cleanup.defaultList(of: .groceries)!.id
        let cleanupGroceryGroup = cleanup.generalGroup(of: cleanupGroceries)!.id
        cleanup.items.append(HouseholdListItem(id: "old-todo", listID: cleanupTodos, groupID: cleanupTodoGroup,
                                               text: "Pottery class", createdAt: aged, updatedAt: aged, activityAt: aged))
        cleanup.items.append(HouseholdListItem(id: "old-grocery", listID: cleanupGroceries, groupID: cleanupGroceryGroup,
                                               text: "Sesame oil", createdAt: aged, updatedAt: aged, activityAt: aged))
        check(cleanup.reviewCandidates(of: cleanupTodos, kind: .todos, now: aged.addingTimeInterval(44 * 86_400)).isEmpty,
              "a to-do is not suggested before 45 days")
        check(cleanup.reviewCandidates(of: cleanupTodos, kind: .todos, now: aged.addingTimeInterval(46 * 86_400)).count == 1,
              "a to-do is suggested after 45 days")
        check(cleanup.reviewCandidates(of: cleanupGroceries, kind: .groceries, now: aged.addingTimeInterval(13 * 86_400)).isEmpty,
              "a grocery item is not suggested before 14 days")
        check(cleanup.reviewCandidates(of: cleanupGroceries, kind: .groceries, now: aged.addingTimeInterval(15 * 86_400)).count == 1,
              "a grocery item is suggested after 14 days")
        if let index = cleanup.items.firstIndex(where: { $0.id == "old-grocery" }) {
            cleanup.items[index].completedAt = aged
        }
        check(cleanup.reviewCandidates(of: cleanupGroceries, kind: .groceries, now: aged.addingTimeInterval(30 * 86_400)).isEmpty,
              "checked-off rows are never suggested")

        let keptUntil = aged.addingTimeInterval(46 * 86_400 + 30 * 86_400)
        if let index = cleanup.items.firstIndex(where: { $0.id == "old-todo" }) {
            cleanup.items[index].reviewAfter = keptUntil
        }
        check(cleanup.reviewCandidates(of: cleanupTodos, kind: .todos, now: keptUntil.addingTimeInterval(-86_400)).isEmpty,
              "a kept row is not suggested while its snooze holds")
        check(cleanup.reviewCandidates(of: cleanupTodos, kind: .todos, now: keptUntil.addingTimeInterval(86_400)).count == 1,
              "a kept row becomes eligible again once the snooze expires")

        let snoozable = lists.addItem(listID: todosID, groupID: todosGeneral, text: "Find a book")!
        let keptAt = Date()
        lists.keep(id: snoozable)
        let snoozeUntil = lists.item(snoozable)!.reviewAfter
        check(snoozeUntil != nil, "Keep for now records a snooze")
        check(snoozeUntil!.timeIntervalSince(keptAt) > 29 * 86_400 && snoozeUntil!.timeIntervalSince(keptAt) < 31 * 86_400,
              "Keep for now defers the suggestion by about thirty days")

        // 9. Convergence, as pure document merges.
        func mergeArchive(_ household: String) -> HouseholdListsArchive {
            HouseholdListsDefaults.archive(householdID: household, now: aged)
        }
        var left = mergeArchive("household-merge")
        let mergeList = left.defaultList(of: .groceries)!.id
        let mergeGroup = left.generalGroup(of: mergeList)!.id
        let sharedRow = HouseholdListItem(
            id: "shared", listID: mergeList, groupID: mergeGroup, text: "Milk",
            stamps: ListStamps(content: stamp(1, "a"), completion: stamp(1, "a"), placement: stamp(1, "a")),
            createdAt: aged, updatedAt: aged, activityAt: aged
        )
        left.items = [sharedRow]
        var right = left

        left.items[0].text = "Oat milk"; left.items[0].stamps.content = stamp(2, "a")
        right.items[0].completedAt = aged; right.items[0].stamps.completion = stamp(2, "b")
        check(left.merged(with: right) == right.merged(with: left),
              "two phones converge whichever one merges first")
        check(left.merged(with: right).items[0].text == "Oat milk"
              && left.merged(with: right).items[0].isCompleted,
              "edits to different fields of one row survive together")

        var editA = left, editB = left
        editA.items[0].text = "Almond milk"; editA.items[0].stamps.content = stamp(5, "a")
        editB.items[0].text = "Soy milk"; editB.items[0].stamps.content = stamp(6, "b")
        check(editA.merged(with: editB) == editB.merged(with: editA),
              "a same-field conflict resolves identically on both sides")
        check(editA.merged(with: editB).items[0].text == "Soy milk", "the later stamp wins the field")

        var placeA = left, placeB = left
        placeA.items[0].rank = 3; placeA.items[0].stamps.placement = stamp(7, "a")
        placeB.items[0].rank = 9; placeB.items[0].stamps.placement = stamp(8, "b")
        check(placeA.merged(with: placeB) == placeB.merged(with: placeA), "simultaneous reorders converge")

        var addA = left, addB = left
        addA.items.append(HouseholdListItem(id: "added-a", listID: mergeList, groupID: mergeGroup, text: "Bread",
                                            createdAt: aged, updatedAt: aged, activityAt: aged))
        addB.items.append(HouseholdListItem(id: "added-b", listID: mergeList, groupID: mergeGroup, text: "Cheese",
                                            createdAt: aged, updatedAt: aged, activityAt: aged))
        check(Set(addA.merged(with: addB).items.map(\.id)) == ["shared", "added-a", "added-b"],
              "rows added while both phones were offline all survive")

        var removed = left, edited = left
        removed.deletions.append(ListDeletion(id: "shared", kind: .item, stamp: stamp(10, "a")))
        edited.items[0].text = "Milk (2)"; edited.items[0].stamps.content = stamp(99, "b")
        check(removed.merged(with: edited).items.isEmpty, "a deletion beats a much later edit to the same row")
        check(edited.merged(with: removed).items.isEmpty, "the same holds merging the other way")
        check(removed.merged(with: edited).isDeleted(id: "shared", kind: .item),
              "the deletion record is kept rather than swept")

        let once = left.merged(with: right)
        check(once.merged(with: right) == once, "replaying the same merge changes nothing")

        // A removed section stays removed, and rows left behind by it do not come
        // back either. The store moves a section's rows to General before it goes;
        // this is the merge being defensive about an archive that did not.
        var withSection = left
        withSection.groups.append(HouseholdListGroup(id: "produce", listID: mergeList, name: "Fruit & vegetables", rank: 5))
        withSection.items.append(HouseholdListItem(id: "produce-row", listID: mergeList, groupID: "produce", text: "Avocados"))
        var withoutSection = withSection
        withoutSection.deletions.append(ListDeletion(id: "produce", kind: .group, stamp: stamp(10, "b")))
        withoutSection.groups.removeAll { $0.id == "produce" }
        let suppressed = withSection.merged(with: withoutSection)
        check(suppressed.groups.allSatisfy { $0.id != "produce" },
              "a removed section does not come back on merge")
        check(suppressed.isDeleted(id: "produce", kind: .group),
              "its deletion record is kept rather than swept")
        check(suppressed.items.allSatisfy { $0.groupID != "produce" },
              "a row stranded by a removed section does not come back either")

        // 10. Two stores through the lists cloud.
        let serverCloud = MockListsCloud()
        let listsSyncSuiteA = "helipad.lists.sync.a.\(UUID().uuidString)"
        let listsSyncSuiteB = "helipad.lists.sync.b.\(UUID().uuidString)"
        let syncDefaultsA = UserDefaults(suiteName: listsSyncSuiteA)!
        let syncDefaultsB = UserDefaults(suiteName: listsSyncSuiteB)!
        defer {
            syncDefaultsA.removePersistentDomain(forName: listsSyncSuiteA)
            syncDefaultsB.removePersistentDomain(forName: listsSyncSuiteB)
        }
        let syncHostA = listsHost("household-sync", "phone-a", into: syncDefaultsA)
        let syncHostB = listsHost("household-sync", "phone-b", into: syncDefaultsB)
        let deviceA = HouseholdListsStore(cloud: serverCloud)
        let deviceB = HouseholdListsStore(cloud: serverCloud)
        deviceA.attach(to: syncHostA)
        deviceB.attach(to: syncHostB)

        let syncList = deviceA.defaultList(.groceries)!.id
        let syncGroup = deviceA.generalGroup(of: syncList)!.id
        deviceA.addItem(listID: syncList, groupID: syncGroup, text: "Milk", quantity: "2 cartons")
        await deviceA.sync()
        check(serverCloud.pushCount == 1, "a local change is published")
        check(deviceA.syncState == .upToDate, "the publisher reports up to date")
        await deviceB.sync()
        check(deviceB.activeItems(of: syncList).map(\.text) == ["Milk"], "the other phone receives the row")
        check(deviceB.syncState == .upToDate, "the receiver reports up to date")

        let quietRevisions = serverCloud.revisionCount
        let quietPulls = serverCloud.pullCount
        await deviceA.sync()
        check(serverCloud.revisionCount == quietRevisions + 1 && serverCloud.pullCount == quietPulls,
              "a quiet poll asks for the revision without pulling the document")

        serverCloud.failPushes = true
        deviceB.addItem(listID: syncList, groupID: syncGroup, text: "Bread")
        await deviceB.sync()
        check(deviceB.archive.localRevision > deviceB.archive.uploadedRevision,
              "a failed upload leaves the change pending locally")
        check(deviceB.syncState != .upToDate, "a failed upload is not reported as up to date")
        check(deviceB.activeItems(of: syncList).map(\.text).sorted() == ["Bread", "Milk"],
              "the unsent row is still usable while it waits")
        serverCloud.failPushes = false
        await deviceB.sync()
        check(deviceB.syncState == .upToDate, "the pending change goes up once the connection returns")
        await deviceA.sync()
        check(deviceA.activeItems(of: syncList).map(\.text).sorted() == ["Bread", "Milk"],
              "both phones end up with both rows")

        // An edit made while the upload is suspended must survive its response.
        deviceA.addItem(listID: syncList, groupID: syncGroup, text: "Apples")
        serverCloud.onPush = {
            await Task.yield()
            deviceA.addItem(listID: syncList, groupID: syncGroup, text: "Pears during upload")
        }
        await deviceA.sync()
        check(deviceA.activeItems(of: syncList).contains { $0.text == "Pears during upload" }, "upload acknowledgement preserves newer local edits")
        check(serverCloud.document?.items.contains { $0.text == "Pears during upload" } == true, "newer edits are published in a following upload")
        check(deviceA.archive.localRevision == deviceA.archive.uploadedRevision, "only acknowledged changes become clean")
        check(!deviceA.archive.connectionFingerprint.contains("://"), "the local connection fingerprint is a digest")
        check(serverCloud.document?.connectionFingerprint == "", "the store boundary strips connection metadata too")

        serverCloud.onRevision = {
            await Task.yield()
            deviceA.addItem(listID: syncList, groupID: syncGroup, text: "Added during revision check")
        }
        await deviceA.sync()
        check(serverCloud.document?.items.contains { $0.text == "Added during revision check" } == true, "a quiet-poll reply cannot hide a newly pending edit")

        serverCloud.failPushes = true
        deviceA.addItem(listID: syncList, groupID: syncGroup, text: "Offline addition")
        await deviceA.sync()
        deviceA.addItem(listID: syncList, groupID: syncGroup, text: "Another offline addition")
        if case .failed = deviceA.syncState {} else { preconditionFailure("Editing must not hide the sync failure") }
        serverCloud.failPushes = false
        await deviceA.sync()

        deviceA.addItem(listID: syncList, groupID: syncGroup, text: "Old connection upload")
        serverCloud.onPush = { syncHostA.connection = "postgres://changed" }
        await deviceA.sync()
        check(deviceA.archive.localRevision > deviceA.archive.uploadedRevision, "a response from an old connection cannot mark the new session clean")
        syncHostA.connection = "postgres://test"
        await deviceA.sync()

        // A missing remote row must clear its stale CAS revision before create.
        serverCloud.document = nil
        serverCloud.revision = nil
        deviceA.addItem(listID: syncList, groupID: syncGroup, text: "After remote restore")
        await deviceA.sync()
        check(deviceA.syncState == .upToDate && serverCloud.document != nil, "a missing row is recreated without a stale expected revision")

        // 11. Recovery, and switching household.
        let recoverySuite = "helipad.lists.recover.\(UUID().uuidString)"
        let recoveryDefaults = UserDefaults(suiteName: recoverySuite)!
        defer { recoveryDefaults.removePersistentDomain(forName: recoverySuite) }
        let corrupt = Data("not a lists document".utf8)
        recoveryDefaults.set(corrupt, forKey: HouseholdListsPersistence.storageKey(householdID: "household-r"))
        let recoveryHost = listsHost("household-r", "phone-r", into: recoveryDefaults)
        let recovery = HouseholdListsStore(cloud: MockListsCloud())
        recovery.attach(to: recoveryHost)
        check(recovery.recoveryNeeded, "an unreadable document asks for an answer instead of being replaced")
        check(HouseholdListsPersistence.quarantined(householdID: "household-r", from: recoveryDefaults) == corrupt,
              "the unreadable bytes are kept")
        check(recovery.lists(.todos).count == 1, "the household can still use Lists while it decides")
        recovery.resolveRecovery(keepingCopy: true)
        check(!recovery.recoveryNeeded, "answering the recovery prompt returns Lists to normal")
        check(HouseholdListsPersistence.quarantined(householdID: "household-r", from: recoveryDefaults) == corrupt,
              "keeping the copy leaves the old bytes recoverable")

        let switchDefaults = UserDefaults(suiteName: "helipad.lists.switch.\(UUID().uuidString)")!
        let switchHost = listsHost("household-one", "phone-s", into: switchDefaults)
        let switching = HouseholdListsStore(cloud: MockListsCloud())
        switching.attach(to: switchHost)
        let oneList = switching.defaultList(.todos)!.id
        let oneGroup = switching.generalGroup(of: oneList)!.id
        switching.addItem(listID: oneList, groupID: oneGroup, text: "First household only")
        switchHost.householdID = "household-two"
        switching.reload()
        check(switching.activeItems(of: oneList).isEmpty, "a new household does not inherit the last one's lists")
        check(switching.archive.householdID == "household-two", "the document follows the household")
        switchHost.householdID = "household-one"
        switching.reload()
        check(switching.activeItems(of: oneList).map(\.text) == ["First household only"],
              "switching back finds the first household's lists untouched")

        // 12. A list edit must not touch the schedule.
        let appSuite = "helipad.lists.app.\(UUID().uuidString)"
        let appDefaults = UserDefaults(suiteName: appSuite)!
        defer { appDefaults.removePersistentDomain(forName: appSuite) }
        let app = AppStore(timeZone: "UTC", cloudService: TestCloud(), secretStore: secrets,
                           schedulesNotifications: false, now: { now })
        app.restore(from: appDefaults)
        // `restore` derives the household identity from the stored metadata, so
        // read it back rather than assuming one.
        let appHousehold = app.cloudHouseholdID
        check(!appHousehold.isEmpty, "a restored household has an identity for its lists")

        let appList = app.lists.defaultList(.groceries)!.id
        let appGroup = app.lists.generalGroup(of: appList)!.id
        let snapshotBefore = appDefaults.data(forKey: HeliPersistence.storageKey)
        let listsRevisionBefore = app.contentRevision
        let pendingBefore = app.syncPending
        let householdRevisionBefore = app.plan.seriesDefinitions?.count ?? 0

        let appItem = app.lists.addItem(listID: appList, groupID: appGroup, text: "Oat milk", quantity: "2 cartons")!
        app.lists.setCompleted(id: appItem, to: true)
        app.lists.moveItem(id: appItem, by: 0)
        _ = app.lists.addGroup(listID: appList, name: "Fruit & vegetables")

        check(app.contentRevision == listsRevisionBefore, "a list edit does not bump the schedule revision")
        check(app.syncPending == pendingBefore, "a list edit does not mark the household as pending")
        check(appDefaults.data(forKey: HeliPersistence.storageKey) == snapshotBefore,
              "a list edit does not rewrite the household snapshot")
        check(app.tombstones.isEmpty, "a list edit leaves schedule tombstones alone")
        check((app.plan.seriesDefinitions?.count ?? 0) == householdRevisionBefore,
              "a list edit does not touch recurrence definitions")
        check(appDefaults.data(forKey: HouseholdListsPersistence.storageKey(householdID: appHousehold)) != nil,
              "lists are written to their own document instead")
        check(app.lists.archive.householdID == appHousehold, "the lists document is keyed to the household")

        print("Production regression checks passed: credentials, sync races/conflicts/retry, two-phone merge and convergence, live sync quiescence, rollover, clock, analysis caching, solo events, Google Calendar read/write/reconciliation/conflicts, stats tracking, event provenance/legacy decoding, and Lists identity/storage/commands/convergence/sync/recovery/isolation.")
    }
}

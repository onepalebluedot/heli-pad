import Foundation
import Combine
import CoreLocation
import CryptoKit

public class AppStore: ObservableObject {
    public static let shared: AppStore = {
        let store = AppStore()
        store.restore()
        return store
    }()

    public static var BASE_WEEK: String {
        return PlanCore.currentMonday()
    }
    public static let SETTINGS_KEYS = [
        "buffer", "synced", "trafficMode", "dinnerProtection", "currentUser",
        "mockTime", "parentLocations", "people", "homeAddress", "homePlaceName",
        "timeZone", "notifyLeaveBy", "notifyDriverNeeded", "notifyCrew", "connections"
    ]
    private static let RESERVED_NAMES: Set<String> = ["all", "family", "tbd", "unassigned", "undetermined"]

    /// Names that mean "a group" rather than a person, and so cannot be worn by one.
    public static func isReservedName(_ name: String) -> Bool {
        return RESERVED_NAMES.contains(name.trimmingCharacters(in: .whitespaces).lowercased())
    }

    // MARK: - Published State
    @Published public var people: [Person]
    @Published public var locations: [LocationItem]
    @Published public var eventsByDay: [Int: [TaskRecord]]
    @Published public var plan: PlanMetadata
    @Published public var templates: [TemplateItem]
    @Published public var parentLocations: [String: String]
    @Published public var homeAddress: String
    @Published public var homePlaceName: String
    @Published public var buffer: Int
    @Published public var synced: Bool
    @Published public var trafficMode: Bool
    @Published public var dinnerProtection: Bool
    @Published public var currentUser: String
    public var activeUser: String {
        get { currentUser }
        set { currentUser = newValue }
    }
    @Published public var mockTime: String
    @Published public var timeZone: String
    @Published public var notifyLeaveBy: Bool
    @Published public var notifyDriverNeeded: Bool
    @Published public var notifyCrew: Bool
    @Published public var connections: [String: Bool]

    // MARK: - Cloud & Integrations
    @Published public var googleMapsApiKey: String = ""
    @Published public var neonConnectionString: String = ""
    @Published public var googleClientId: String = ""
    @Published public var googleAccountEmail: String = ""
    @Published public var googleCalendars: [GoogleCalendarChoice] = []
    @Published public var isGoogleAuthenticated: Bool = false
    private let googleCalendarService: GoogleCalendarProtocol
    @Published public var cloudHouseholdID: String = UUID().uuidString
    @Published public private(set) var syncError: String?
    @Published public private(set) var notificationScheduleError: String?
    @Published public private(set) var syncPending: Bool = false
    private var syncMetadata = HouseholdSyncMetadata()
    /// Stamp covering the household-wide settings block. Records carry their
    /// own; the loose settings need one shared stamp to be mergeable at all.
    private var settingsStamp: RecordStamp?
    private var syncTask: Task<Void, Error>?
    private let cloudService: HouseholdCloudService
    private let secretStore: IntegrationSecretStore
    private let schedulesNotifications: Bool
    private let nowProvider: () -> Date
    private var persistenceDefaults: UserDefaults = .standard
    @Published public private(set) var weekStart: String = PlanCore.currentMonday()
    @Published public var neonSyncEnabled: Bool = false
    @Published public var lastNeonSyncDate: Date? = nil
    @Published public var liveWeather: LiveWeather = LiveWeather(temperature: 78, tempLow: 58, tempHigh: 78, condition: "Sunny", icon: "sun", label: "Sunny · 58°–78°")
    @Published public var realTimeDeviceEta: Int? = nil

    // MARK: - Setup
    @Published public var hasCompletedOnboarding: Bool = false
    /// Drives the full-screen setup flow. Set from first launch and from Settings.
    @Published public var showOnboarding: Bool = false
    /// The answers the household last gave, so a re-run starts from them.
    public var savedOnboardingDraft: OnboardingDraft?
    /// Off until `restore()` has run, so loading a family does not write it back
    /// a dozen times on the way in.
    private var persistenceEnabled: Bool = false

    public var settings: [String: Any] {
        get {
            return [
                "buffer": buffer,
                "bufferMinutes": buffer,
                "synced": synced,
                "trafficMode": trafficMode,
                "peakTraffic": trafficMode,
                "dinnerProtection": dinnerProtection,
                "dinnerProtected": dinnerProtection,
                "currentUser": currentUser,
                "mockTime": mockTime,
                "timeZone": timeZone,
                "notifyLeaveBy": notifyLeaveBy,
                "notifyDriverNeeded": notifyDriverNeeded,
                "notifyCrew": notifyCrew,
                "homeAddress": homeAddress,
                "homePlaceName": homePlaceName,
                "parentLocations": parentLocations,
                "connections": connections
            ]
        }
        set {
            if let b = newValue["buffer"] as? Int ?? newValue["bufferMinutes"] as? Int {
                buffer = b
            }
            if let t = newValue["trafficMode"] as? Bool ?? newValue["peakTraffic"] as? Bool {
                trafficMode = t
            }
            if let d = newValue["dinnerProtection"] as? Bool ?? newValue["dinnerProtected"] as? Bool {
                dinnerProtection = d
            }
            if let u = newValue["currentUser"] as? String {
                currentUser = u
            }
            if let tz = newValue["timeZone"] as? String {
                timeZone = tz
            }
            if let h = newValue["homeAddress"] as? String {
                homeAddress = h
            }
        }
    }

    // View Scopes
    @Published public var activeDay: Int
    @Published public var todayIndex: Int
    @Published public var goKidFilter: String
    @Published public var goCrewFilter: String?
    @Published public var goScopeOpen: String?
    @Published public var goPanel: String // "rail" | "load"
    @Published public var goDraft: TaskRecord?
    @Published public var familyActivePanel: String // "events" | "locations" | "kids" | "roster"
    @Published public var familyKidStatsFilter: String
    @Published public var dismissedEventIds: Set<String> = []

    public var routes: [String: [String: Int]]
    private var draftProviders: [() -> TaskRecord?] = []

    public init(
        people: [Person] = SeedData.defaultPeople,
        locations: [LocationItem] = SeedData.defaultLocations,
        eventsByDay: [Int: [TaskRecord]] = SeedData.defaultEventsByDay(),
        plan: PlanMetadata = PlanMetadata(),
        templates: [TemplateItem] = SeedData.defaultTemplates,
        parentLocations: [String: String] = ["Mom": "Product Office", "Dad": "Warren Plant"],
        homeAddress: String = "18 Redwood Lane",
        homePlaceName: String = "Home",
        buffer: Int = 12,
        synced: Bool = true,
        trafficMode: Bool = true,
        dinnerProtection: Bool = true,
        currentUser: String = "All",
        mockTime: String = "",
        timeZone: String = "device",
        notifyLeaveBy: Bool = true,
        notifyDriverNeeded: Bool = true,
        notifyCrew: Bool = false,
        connections: [String: Bool] = ["google": false, "apple": false],
        routes: [String: [String: Int]] = SeedData.routeMatrix,
        defaultLocations: [LocationItem]? = nil,
        cloudService: HouseholdCloudService = NeonDatabaseService.shared,
        secretStore: IntegrationSecretStore = KeychainIntegrationSecrets(),
        googleCalendarService: GoogleCalendarProtocol = GoogleCalendarService.shared,
        schedulesNotifications: Bool = true,
        now: @escaping () -> Date = Date.init
    ) {
        self.schedulesNotifications = schedulesNotifications
        self.cloudService = cloudService
        self.secretStore = secretStore
        self.googleCalendarService = googleCalendarService
        self.isGoogleAuthenticated = googleCalendarService.isAuthenticated()
        self.googleAccountEmail = googleCalendarService.currentEmail() ?? ""
        self.nowProvider = now
        self.weekStart = PlanCore.currentMonday(date: now(), timeZone: TimeZone(identifier: timeZone) ?? .current)
        self.people = people
        self.locations = locations
        self.eventsByDay = eventsByDay
        self.plan = plan
        self.templates = templates
        self.parentLocations = parentLocations
        self.homeAddress = homeAddress
        self.homePlaceName = homePlaceName
        self.buffer = buffer
        self.synced = synced
        self.trafficMode = trafficMode
        self.dinnerProtection = dinnerProtection
        self.currentUser = currentUser
        self.mockTime = mockTime
        self.timeZone = timeZone
        self.notifyLeaveBy = notifyLeaveBy
        self.notifyDriverNeeded = notifyDriverNeeded
        self.notifyCrew = notifyCrew
        self.connections = connections
        self.routes = routes

        let currentDay = PlanCore.currentWeekdayIndex(date: now(), timeZone: TimeZone(identifier: timeZone) ?? .current)
        self.activeDay = currentDay
        self.todayIndex = currentDay
        self.goKidFilter = "all"
        self.goCrewFilter = nil
        self.goScopeOpen = nil
        self.goPanel = "rail"
        self.goDraft = nil
        self.familyActivePanel = "kids"
        self.familyKidStatsFilter = "All"

        // Initialize route keys if not set
        let seeds = defaultLocations ?? SeedData.defaultLocations
        for i in self.locations.indices {
            if self.locations[i].routeKey == nil {
                let name = self.locations[i].name
                let addr = self.locations[i].address
                if let seed = seeds.first(where: { $0.name == name && $0.address == addr }) {
                    self.locations[i].routeKey = seed.name
                }
            }
        }

        reconcile()
    }

    // MARK: - Computed Properties

    public func people(kind: String? = nil) -> [Person] {
        if let kind = kind {
            return people.filter { $0.kind == kind }
        }
        return people
    }

    public func caregivers() -> [String] {
        return people.filter { $0.kind == "caregiver" }.map { $0.name }
    }

    public func caregiverPeople() -> [Person] {
        return people.filter { $0.kind == "caregiver" }
    }

    public func children() -> [String] {
        return people.filter { $0.kind == "child" }.map { $0.name }
    }

    public func childPeople() -> [Person] {
        return people.filter { $0.kind == "child" }
    }

    public func home() -> String {
        return homePlaceName.isEmpty ? "Home" : homePlaceName
    }

    public func hasPlace(_ name: String) -> Bool {
        return locations.contains { $0.name == name }
    }

    public func color(_ name: String) -> String {
        if let p = people.first(where: { $0.name == name }) {
            return p.color
        }
        switch name {
        case "Family": return "#b08313"
        case "TBD", "Unassigned": return "#bf6c2c"
        default: return "#687469"
        }
    }

    public func dateForDay(_ day: Int) -> String {
        PlanCore.dateAdd(weekStart, day)
    }

    public func records() -> [TaskRecord] {
        (eventsByDay.keys.sorted().flatMap { eventsByDay[$0] ?? [] } + plan.future).sorted {
            if $0.date != $1.date { return $0.date < $1.date }
            if $0.time != $1.time { return $0.time < $1.time }
            return $0.id < $1.id
        }
    }

    /// Buckets are a projection of absolute dates. Off-week records, including
    /// history, stay in the legacy `future` collection without changing dates.
    private func partitionRecords(_ records: [TaskRecord]) {
        var days: [Int: [TaskRecord]] = [:]
        var outside: [TaskRecord] = []
        for record in records {
            // A record whose date will not parse has no place in the week. Keeping
            // it aside preserves it without inventing a day for it — filing it on
            // Monday would look deliberate and be wrong.
            if let day = PlanCore.dayOffset(from: weekStart, to: record.date), (0...6).contains(day) {
                days[day, default: []].append(record)
            } else {
                outside.append(record)
            }
        }
        if eventsByDay != days { eventsByDay = days }
        if plan.future != outside { plan.future = outside }
    }

    // MARK: - Reconcile & Normalization

    public func registerDraft(_ provider: @escaping () -> TaskRecord?) {
        draftProviders.append(provider)
    }

    private func normalizeRecord(_ e: inout TaskRecord) {
        let crew = caregivers()
        if !["Family", "TBD"].contains(e.owner) && !crew.contains(e.owner) {
            e.owner = "TBD"
            e.tentative = false
            e.locked = false
        }
        e.lead = e.owner

        let kids = e.kids
        if kids.contains("All") {
            e.kids = ["All"]
        } else {
            let validKids = children()
            e.kids = Array(Set(kids.filter { validKids.contains($0) }))
        }
        e.kid = e.kids.joined(separator: ", ")
        e.color = color(e.owner)

        let hasAttachedCoordinate = e.latitude != nil && e.longitude != nil
        if !e.location.isEmpty && !hasPlace(e.location) && !hasAttachedCoordinate {
            e.locationMissing = true
        } else {
            e.locationMissing = nil
        }
    }

    public func reconcile() {
        let crew = caregivers()
        let kids = children()

        PersonInks.register(people)

        weekStart = PlanCore.currentMonday(date: nowProvider(), timeZone: TimeZone(identifier: timeZone) ?? .current)
        partitionRecords(records())

        // Recurrence metadata is authoritative only for deletion/exclusion.
        // Reconcile never generates future rows; it merely prevents a stale
        // payload from reviving slots a household explicitly removed.
        let definitions = plan.seriesDefinitions ?? []
        let deletedSeries = Set(definitions.filter(\.deleted).map(\.seriesId))
        var validSlots: [String: Set<String>] = [:]
        for definition in definitions where !definition.deleted {
            if let dates = try? PlanCore.occurrenceDates(for: definition.pattern) {
                validSlots[definition.seriesId] = Set(dates)
            }
        }
        let excludedSlots = Set((plan.seriesExceptions ?? []).filter { $0.kind == .excluded }.map(\.id))
        if !deletedSeries.isEmpty || !excludedSlots.isEmpty || !validSlots.isEmpty {
            partitionRecords(records().filter { record in
                guard let seriesId = record.seriesId else { return true }
                guard !deletedSeries.contains(seriesId) else { return false }
                let original = record.originalOccurrenceDate ?? record.date
                if let allowed = validSlots[seriesId], !allowed.contains(original) { return false }
                return !excludedSlots.contains("\(seriesId)|\(original)")
            })
        }

        // Normalize eventsByDay
        for d in eventsByDay.keys {
            if var list = eventsByDay[d] {
                for i in list.indices {
                    normalizeRecord(&list[i])
                }
                eventsByDay[d] = list
            }
        }

        // Normalize plan.future
        for i in plan.future.indices {
            normalizeRecord(&plan.future[i])
        }

        // Normalize templates
        for i in templates.indices {
            if !["Family", "TBD"].contains(templates[i].owner) && !crew.contains(templates[i].owner) {
                templates[i].owner = "TBD"
            }
            let validKids = templates[i].kids.filter { kids.contains($0) }
            templates[i].kids = validKids
            templates[i].kid = validKids.joined(separator: ", ")
        }

        // Check draft
        if var draft = goDraft {
            normalizeRecord(&draft)
            goDraft = draft
        }

        // Home place
        if !hasPlace(home()) {
            homePlaceName = locations.first?.name ?? "Home"
        }
        homeAddress = locations.first(where: { $0.name == home() })?.address ?? ""
        if let coord = homeCoordinate {
            LocationService.shared.homeCoordinateFallback = coord
        }

        // Parent locations
        for key in Array(parentLocations.keys) {
            if !crew.contains(key) {
                parentLocations.removeValue(forKey: key)
            }
        }
        for name in crew {
            if let base = parentLocations[name], !hasPlace(base) {
                parentLocations[name] = home()
            }
        }

        // Scopes & current user
        if currentUser != "All" && !crew.contains(currentUser) {
            currentUser = "All"
        }
        if let goCrew = goCrewFilter, !["all", "All", "Family", "TBD"].contains(goCrew) && !crew.contains(goCrew) {
            goCrewFilter = nil
        }
        if goKidFilter != "all" && goKidFilter != "All" && !kids.contains(goKidFilter) {
            goKidFilter = "all"
        }

        // Clean orphaned calendar exports
        let allIds = Set(records().map { $0.id })
        for id in Array(plan.calendar.exports.keys) {
            if !allIds.contains(id) {
                plan.calendar.exports.removeValue(forKey: id)
            }
        }
    }

    // MARK: - Edit stamping
    //
    // Two phones cannot agree on which edit is newer by comparing wall clocks.
    // Instead every locally changed record takes a logical stamp, and every
    // record that disappears leaves a tombstone. Both are derived centrally by
    // diffing against the last saved content, so existing edit and delete call
    // sites did not need to change — and none can forget to stamp.

    /// Last saved content per record, so a save can tell what actually changed.
    /// Rebuilt whenever state is loaded or replaced wholesale.
    private var contentBaseline: [String: String] = [:]

    /// Tombstones are swept once they are older than this. A delete that takes
    /// longer than this to reach the other phone would be resurrected, which is
    /// far longer than any realistic gap between two phones in one household.
    private static let tombstoneHorizon: TimeInterval = 30 * 24 * 60 * 60

    private static let fingerprintEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    /// The household-wide settings, as one comparable blob. Anything a second
    /// phone should see when the first one changes it belongs here; anything
    /// that describes *this* phone (who is holding it, which reminders it
    /// shows) deliberately does not.
    private struct SettingsBlock: Encodable {
        var parentLocations: [String: String]
        var routes: [String: [String: Int]]
        var homeAddress: String
        var homePlaceName: String
        var buffer: Int
        var trafficMode: Bool
        var dinnerProtection: Bool
        var timeZone: String
        var connections: [String: Bool]
        var priorities: [String: WeekPriority]
        var weeklyNotes: [String: String]
        var calendar: CalendarMetadata
    }

    private func settingsBlock() -> SettingsBlock {
        SettingsBlock(
            parentLocations: parentLocations,
            routes: routes,
            homeAddress: homeAddress,
            homePlaceName: homePlaceName,
            buffer: buffer,
            trafficMode: trafficMode,
            dinnerProtection: dinnerProtection,
            timeZone: timeZone,
            connections: connections,
            priorities: plan.priorities,
            weeklyNotes: plan.weeklyNotes ?? [:],
            calendar: plan.calendar
        )
    }

    private static let settingsBaselineKey = "settings:household"

    /// Hash of only the parts of a household that both phones share.
    ///
    /// The payload also carries fields that belong to one handset — who is
    /// using it, which reminders it shows, what it has dismissed. Those must
    /// not count towards "has anything changed?", or each phone would see the
    /// other's copy as different, push it back, and the two would trade
    /// revisions for as long as both apps were open.
    private func sharedFingerprint(_ state: PersistedState) -> String {
        struct Shared: Encodable {
            var people: [Person]
            var locations: [LocationItem]
            var templates: [TemplateItem]
            var events: [TaskRecord]
            var tombstones: [Tombstone]
            var seriesDefinitions: [SeriesDefinition]
            var seriesExceptions: [SeriesException]
            var priorities: [String: WeekPriority]
            var weeklyNotes: [String: String]
            var reviewed: [String: String]
            var calendar: CalendarMetadata
            var parentLocations: [String: String]
            var routes: [String: [String: Int]]
            var homeAddress: String
            var homePlaceName: String
            var buffer: Int
            var trafficMode: Bool
            var dinnerProtection: Bool
            var timeZone: String
            var connections: [String: Bool]
            var settingsStamp: RecordStamp?
            var hasCompletedOnboarding: Bool
        }
        let shared = Shared(
            people: state.people.sorted { $0.stampKey < $1.stampKey },
            locations: state.locations.sorted { $0.stampKey < $1.stampKey },
            templates: state.templates.sorted { $0.stampKey < $1.stampKey },
            events: (state.eventsByDay.values.flatMap { $0 } + state.plan.future)
                .sorted { $0.stampKey < $1.stampKey },
            tombstones: (state.plan.tombstones ?? []).sorted { $0.key < $1.key },
            seriesDefinitions: (state.plan.seriesDefinitions ?? []).sorted { $0.seriesId < $1.seriesId },
            seriesExceptions: (state.plan.seriesExceptions ?? []).sorted { $0.id < $1.id },
            priorities: state.plan.priorities,
            weeklyNotes: state.plan.weeklyNotes ?? [:],
            reviewed: state.plan.reviewed,
            calendar: state.plan.calendar,
            parentLocations: state.parentLocations,
            routes: state.routes,
            homeAddress: state.homeAddress,
            homePlaceName: state.homePlaceName,
            buffer: state.buffer,
            trafficMode: state.trafficMode,
            dinnerProtection: state.dinnerProtection,
            timeZone: state.timeZone,
            connections: state.connections,
            settingsStamp: state.settingsStamp,
            hasCompletedOnboarding: state.hasCompletedOnboarding
        )
        return fingerprint(shared)
    }

    /// Content hash that is stable across launches. `Hashable` is seeded per
    /// process, so it would report every record as changed after a relaunch.
    private func fingerprint<T: Encodable>(_ value: T) -> String {
        guard let data = try? Self.fingerprintEncoder.encode(value) else { return UUID().uuidString }
        var hash: UInt64 = 0xcbf29ce484222325            // FNV-1a
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(hash, radix: 16)
    }

    private func fingerprint<T: StampedRecord>(_ record: T) -> String {
        var bare = record
        bare.stamp = nil
        guard let data = try? Self.fingerprintEncoder.encode(bare) else { return UUID().uuidString }
        var hash: UInt64 = 0xcbf29ce484222325            // FNV-1a
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(hash, radix: 16)
    }

    private func nextStamp() -> RecordStamp {
        syncMetadata.lamport += 1
        return RecordStamp(counter: syncMetadata.lamport, deviceID: syncMetadata.deviceID)
    }

    public var tombstones: [Tombstone] { plan.tombstones ?? [] }

    /// Raises the logical clock above everything the payload carries, so the
    /// next local edit sorts after anything the other phone has already done.
    private func observeStamps(in state: PersistedState) {
        var highest = syncMetadata.lamport
        func note(_ stamp: RecordStamp?) {
            if let stamp, stamp.counter > highest { highest = stamp.counter }
        }
        state.eventsByDay.values.flatMap { $0 }.forEach { note($0.stamp) }
        state.plan.future.forEach { note($0.stamp) }
        state.plan.tombstones?.forEach { note($0.stamp) }
        state.plan.seriesDefinitions?.forEach { note($0.stamp) }
        state.plan.seriesExceptions?.forEach { note($0.stamp) }
        state.people.forEach { note($0.stamp) }
        state.templates.forEach { note($0.stamp) }
        state.locations.forEach { note($0.stamp) }
        note(state.settingsStamp)
        syncMetadata.lamport = highest
    }

    /// Records current content as the baseline without stamping anything. Used
    /// after a load or a download, where nothing was edited locally.
    private func rebaselineContent() {
        var baseline: [String: String] = [:]
        func note<T: StampedRecord>(_ items: [T], _ kind: Tombstone.Kind) {
            for item in items { baseline["\(kind.rawValue):\(item.stampKey)"] = fingerprint(item) }
        }
        note(records(), .event)
        note(people, .person)
        note(templates, .template)
        note(locations, .location)
        baseline[Self.settingsBaselineKey] = fingerprint(settingsBlock())
        contentBaseline = baseline
    }

    private func stampChanged<T: StampedRecord>(
        _ items: inout [T],
        kind: Tombstone.Kind,
        seen: inout [String: String]
    ) -> Bool {
        var changed = false
        for index in items.indices {
            let key = "\(kind.rawValue):\(items[index].stampKey)"
            let print = fingerprint(items[index])
            seen[key] = print
            if contentBaseline[key] != print || items[index].stamp == nil {
                items[index].stamp = nextStamp()
                changed = true
            }
        }
        return changed
    }

    /// Stamps what changed since the last save and tombstones what vanished.
    private func stampLocalChanges() {
        var seen: [String: String] = [:]

        var events = records()
        let eventsChanged = stampChanged(&events, kind: .event, seen: &seen)
        if eventsChanged { partitionRecords(events) }

        _ = stampChanged(&people, kind: .person, seen: &seen)
        _ = stampChanged(&templates, kind: .template, seen: &seen)
        _ = stampChanged(&locations, kind: .location, seen: &seen)

        // Settings move as one block, under one stamp.
        let settingsPrint = fingerprint(settingsBlock())
        seen[Self.settingsBaselineKey] = settingsPrint
        if contentBaseline[Self.settingsBaselineKey] != settingsPrint || settingsStamp == nil {
            settingsStamp = nextStamp()
        }

        // Anything the baseline knew about that is no longer here was deleted.
        var graves = plan.tombstones ?? []
        let now = nowProvider()
        for key in contentBaseline.keys where seen[key] == nil {
            let parts = key.split(separator: ":", maxSplits: 1)
            guard parts.count == 2, let kind = Tombstone.Kind(rawValue: String(parts[0])) else { continue }
            let id = String(parts[1])
            graves.removeAll { $0.kind == kind && $0.id == id }
            graves.append(Tombstone(id: id, kind: kind, stamp: nextStamp(), deletedAt: now))
        }

        // A record that came back (re-added under the same id) outlives its grave.
        graves.removeAll { seen["\($0.kind.rawValue):\($0.id)"] != nil }
        graves.removeAll { now.timeIntervalSince($0.deletedAt) > Self.tombstoneHorizon }

        let settled: [Tombstone]? = graves.isEmpty ? nil : graves
        if plan.tombstones != settled { plan.tombstones = settled }
        contentBaseline = seen
    }

    public func save(syncToCloud: Bool = true) {
        reconcile()
        prepareSyncIdentity()
        stampLocalChanges()
        syncMetadata.localRevision += 1
        syncPending = true
        persist()
        refreshDepartureReminders()
        if syncToCloud && neonSyncEnabled && !neonConnectionString.isEmpty {
            Task { @MainActor in
                do { try await self.syncWithNeon() } catch { self.syncError = error.localizedDescription }
            }
        }
    }

    /// Re-queues the leave-in-10 reminders from the current schedule. Drive
    /// reminders use the device's GPS origin and Apple Maps traffic estimate;
    /// the service debounces, so saves and location updates can both call this.
    public func refreshDepartureReminders() {
        guard schedulesNotifications else { return }
        NotificationService.shared.scheduleReminders(
            records: records(),
            timeZoneId: timeZone,
            enabled: notifyLeaveBy,
            driverNeededEnabled: notifyDriverNeeded,
            bufferMinutes: buffer,
            travelTimeProvider: { [weak self] event, appointmentDate in
                guard let self else { return nil }
                return await self.appleMapsDriveTime(for: event, arrivingAt: appointmentDate)
            },
            onError: { [weak self] message in
                self?.notificationScheduleError = message
            }
        )
    }

    // MARK: - Persistence

    private func snapshot() -> PersistedState {
        return PersistedState(
            version: HeliPersistence.version(),
            people: people,
            locations: locations,
            eventsByDay: eventsByDay,
            plan: plan,
            templates: templates,
            parentLocations: parentLocations,
            routes: routes,
            homeAddress: homeAddress,
            homePlaceName: homePlaceName,
            buffer: buffer,
            trafficMode: trafficMode,
            dinnerProtection: dinnerProtection,
            currentUser: currentUser,
            timeZone: timeZone,
            notifyLeaveBy: notifyLeaveBy,
            notifyDriverNeeded: notifyDriverNeeded,
            notifyCrew: notifyCrew,
            connections: connections,
            hasCompletedOnboarding: hasCompletedOnboarding,
            onboardingDraft: savedOnboardingDraft,
            googleMapsApiKey: nil,
            neonConnectionString: nil,
            neonSyncEnabled: neonSyncEnabled,
            lastNeonSyncDate: lastNeonSyncDate,
            dismissedEventIds: Array(dismissedEventIds),
            weekStart: weekStart,
            syncMetadata: syncMetadata,
            settingsStamp: settingsStamp
        )
    }

    private func persist() {
        guard persistenceEnabled else { return }
        do {
            try secretStore.set(googleMapsApiKey, for: "googleMapsApiKey")
            try secretStore.set(neonConnectionString, for: "neonConnectionString")
            try secretStore.set(googleClientId, for: "googleClientId")
        } catch {
            syncError = "Could not save integration credentials securely. Please try again."
        }
        HeliPersistence.save(snapshot(), to: persistenceDefaults)
    }

    /// Loads the stored household, or opens setup if this phone has never had one.
    public func restore(from defaults: UserDefaults = .standard) {
        persistenceDefaults = defaults
        var legacyGoogleKey: String?
        if let state = HeliPersistence.load(from: defaults) {
            apply(state)
            legacyGoogleKey = state.googleMapsApiKey
            if !(state.neonConnectionString ?? "").isEmpty {
                syncError = "Re-enter your personal Neon connection. Previous plaintext credentials were removed."
            }
            syncMetadata = state.syncMetadata ?? HouseholdSyncMetadata()
            cloudHouseholdID = syncMetadata.householdID
            neonSyncEnabled = state.syncMetadata != nil && (state.neonSyncEnabled ?? false)
            lastNeonSyncDate = state.lastNeonSyncDate
        }
        cloudHouseholdID = syncMetadata.householdID
        do {
            googleMapsApiKey = try secretStore.get("googleMapsApiKey") ?? legacyGoogleKey ?? ""
            if !googleMapsApiKey.isEmpty { try secretStore.set(googleMapsApiKey, for: "googleMapsApiKey") }
            neonConnectionString = try secretStore.get("neonConnectionString") ?? ""
            googleClientId = try secretStore.get("googleClientId") ?? AppConfig.defaultGoogleClientId
            isGoogleAuthenticated = googleCalendarService.isAuthenticated()
            googleAccountEmail = googleCalendarService.currentEmail() ?? ""
            if isGoogleAuthenticated {
                connections["google"] = true
            }
        } catch {
            syncError = "Integration credentials are unavailable. Unlock your device and try again."
            neonSyncEnabled = false
        }
        showOnboarding = !hasCompletedOnboarding
        syncPending = syncMetadata.localRevision != syncMetadata.uploadedRevision
        persistenceEnabled = true
        // Re-encode immediately to remove legacy plaintext credentials. Never
        // import the previously bundled database password into Keychain.
        HeliPersistence.save(snapshot(), to: defaults)
        refreshDepartureReminders()
        Task { @MainActor in
            await self.resolveMissingPlaceCoordinates()
        }
        // Foreground lifecycle handles pending work. Restoring never uploads seed data.
    }

    private func apply(_ state: PersistedState) {
        people = state.people
        locations = state.locations
        eventsByDay = state.eventsByDay
        plan = state.plan
        templates = state.templates
        parentLocations = state.parentLocations
        routes = state.routes
        homeAddress = state.homeAddress
        homePlaceName = state.homePlaceName
        buffer = state.buffer
        trafficMode = state.trafficMode
        dinnerProtection = state.dinnerProtection
        currentUser = state.currentUser
        timeZone = state.timeZone
        notifyLeaveBy = state.notifyLeaveBy
        notifyDriverNeeded = state.notifyDriverNeeded
        // Older builds exposed this switch without any APNs delivery path.
        // Keep it off until authenticated household/device membership exists.
        notifyCrew = false
        connections = state.connections
        hasCompletedOnboarding = state.hasCompletedOnboarding
        savedOnboardingDraft = state.onboardingDraft
        settingsStamp = state.settingsStamp
        if let dismissed = state.dismissedEventIds {
            dismissedEventIds = Set(dismissed)
        }
        reconcile()
        // Nothing here was edited on this phone: adopt the incoming stamps as
        // the baseline, and move the clock past them so the next local edit
        // sorts after everything the other phone has already done.
        observeStamps(in: state)
        rebaselineContent()
    }

    // MARK: - Merge

    /// Folds the cloud household into this one, record by record.
    ///
    /// Both phones run this and reach the same answer, because "newer" is the
    /// Lamport stamp on each record rather than either phone's wall clock. A
    /// record that exists on both sides keeps the higher stamp; a tombstone
    /// removes a record only when the delete is newer than the record itself,
    /// so re-adding a stop after someone else deleted it keeps the stop.
    ///
    /// Unlike `apply`, nothing local is discarded: this is what lets both
    /// phones edit the same week without one of them losing its work.
    func merge(_ remote: PersistedState) {
        // Newest delete wins, per record.
        var graves: [String: Tombstone] = [:]
        for stone in (plan.tombstones ?? []) + (remote.plan.tombstones ?? []) {
            if let seen = graves[stone.key], stone.stamp < seen.stamp { continue }
            graves[stone.key] = stone
        }

        func combine<T: StampedRecord>(_ mine: [T], _ theirs: [T], _ kind: Tombstone.Kind) -> [T] {
            var byKey: [String: T] = [:]
            var order: [String] = []
            for item in mine + theirs {
                guard let existing = byKey[item.stampKey] else {
                    byKey[item.stampKey] = item
                    order.append(item.stampKey)
                    continue
                }
                // Ties keep the local copy; the stamp's device id makes that
                // choice the same on both phones.
                if (existing.stamp ?? RecordStamp()) < (item.stamp ?? RecordStamp()) {
                    byKey[item.stampKey] = item
                }
            }
            return order.compactMap { key in
                guard let item = byKey[key] else { return nil }
                guard let grave = graves["\(kind.rawValue):\(key)"] else { return item }
                // The delete only sticks while it is newer than the record.
                return grave.stamp < (item.stamp ?? RecordStamp()) ? item : nil
            }
        }

        let mergedEvents = combine(records(), remote.eventsByDay.values.flatMap { $0 } + remote.plan.future, .event)
        let mergedPeople = combine(people, remote.people, .person)
        let mergedTemplates = combine(templates, remote.templates, .template)
        let mergedLocations = combine(locations, remote.locations, .location)

        func mergeIndependent<T: StampedRecord>(_ mine: [T], _ theirs: [T]) -> [T] {
            var result: [String: T] = [:]
            for item in mine + theirs {
                if let existing = result[item.stampKey],
                   (item.stamp ?? RecordStamp()) <= (existing.stamp ?? RecordStamp()) { continue }
                result[item.stampKey] = item
            }
            return result.keys.sorted().compactMap { result[$0] }
        }
        let mergedSeries = mergeIndependent(plan.seriesDefinitions ?? [], remote.plan.seriesDefinitions ?? [])
        let mergedExceptions = mergeIndependent(plan.seriesExceptions ?? [], remote.plan.seriesExceptions ?? [])

        // Settings are one block: the newer stamp takes the whole thing, so the
        // two phones never end up with half of each other's planning rules.
        if (settingsStamp ?? RecordStamp()) < (remote.settingsStamp ?? RecordStamp()) {
            parentLocations = remote.parentLocations
            routes = remote.routes
            homeAddress = remote.homeAddress
            homePlaceName = remote.homePlaceName
            buffer = remote.buffer
            trafficMode = remote.trafficMode
            dinnerProtection = remote.dinnerProtection
            timeZone = remote.timeZone
            connections = remote.connections
            plan.priorities = remote.plan.priorities
            plan.weeklyNotes = remote.plan.weeklyNotes
            plan.calendar = remote.plan.calendar
            settingsStamp = remote.settingsStamp
        }

        people = mergedPeople
        templates = mergedTemplates
        locations = mergedLocations
        partitionRecords(mergedEvents)
        plan.seriesDefinitions = mergedSeries.isEmpty ? nil : mergedSeries
        plan.seriesExceptions = mergedExceptions.isEmpty ? nil : mergedExceptions

        let deletedSeries = Set(mergedSeries.filter(\.deleted).map(\.seriesId))
        let excludedSlots = Set(mergedExceptions.filter { $0.kind == .excluded }.map(\.id))
        let recurrenceFiltered = records().filter { record in
            guard let seriesId = record.seriesId else { return true }
            if deletedSeries.contains(seriesId) { return false }
            let original = record.originalOccurrenceDate ?? record.date
            return !excludedSlots.contains("\(seriesId)|\(original)")
        }
        partitionRecords(recurrenceFiltered)

        // Weeks either phone has reviewed stay reviewed.
        plan.reviewed.merge(remote.plan.reviewed) { mine, _ in mine }

        // A record that outlived its own delete no longer needs the grave.
        let surviving = Set(
            records().map { "event:\($0.stampKey)" }
                + people.map { "person:\($0.stampKey)" }
                + templates.map { "template:\($0.stampKey)" }
                + locations.map { "location:\($0.stampKey)" }
        )
        let now = nowProvider()
        var settled = graves.values.filter { !surviving.contains($0.key) }
        settled.removeAll { now.timeIntervalSince($0.deletedAt) > Self.tombstoneHorizon }
        plan.tombstones = settled.isEmpty ? nil : settled.sorted { $0.key < $1.key }

        // Setup done anywhere in the household is done here.
        hasCompletedOnboarding = hasCompletedOnboarding || remote.hasCompletedOnboarding
        if savedOnboardingDraft == nil { savedOnboardingDraft = remote.onboardingDraft }

        // Deliberately not merged: currentUser and the notification switches
        // describe this handset, not the household.

        reconcile()
        observeStamps(in: remote)
        // The merged content is the new baseline. Re-stamping it here would
        // mark records this phone never touched as its own fresh edits.
        rebaselineContent()
    }

    // MARK: - Cloud & Services Operations

    @MainActor
    public func updateLiveWeather(forceRefresh: Bool = false) async {
        let coord = LocationService.shared.currentLocation?.coordinate
        let w = await WeatherService.shared.fetchWeather(coordinate: coord, forceRefresh: forceRefresh)
        self.liveWeather = w
    }

    /// A household id or connection edited mid-flight must never have another
    /// household's response attached to it.
    private func assertIdentity(connection: String, household: String) throws {
        guard neonConnectionString == connection, cloudHouseholdID == household else {
            throw NeonError.invalidConfig("Cloud connection changed during sync. Sync the selected household again.")
        }
    }

    /// How many times a push may lose the compare-and-swap race before we stop
    /// and report it. Two phones saving at once resolve on the first retry.
    private static let syncConflictRetries = 4

    private func prepareSyncIdentity() {
        let fingerprint = SHA256.hash(data: Data(neonConnectionString.utf8)).map { String(format: "%02x", $0) }.joined()
        if syncMetadata.connectionFingerprint != fingerprint || syncMetadata.householdID != cloudHouseholdID {
            // Point at the new household, but keep this device's identity and
            // logical clock: rewinding either would make its next edit look
            // older than edits the other phone has already seen.
            syncMetadata = HouseholdSyncMetadata(
                householdID: cloudHouseholdID,
                deviceID: syncMetadata.deviceID,
                lamport: syncMetadata.lamport,
                connectionFingerprint: fingerprint
            )
            syncMetadata.localRevision = 1
            syncPending = true
        }
    }

    @MainActor
    public func syncWithNeon() async throws {
        if let task = syncTask { return try await task.value }
        guard hasCompletedOnboarding else { throw NeonError.invalidConfig("Complete setup before uploading a household.") }
        guard !neonConnectionString.isEmpty, !cloudHouseholdID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NeonError.invalidConfig("Enter your personal connection and household ID first.")
        }
        prepareSyncIdentity()
        let connection = neonConnectionString
        let householdID = cloudHouseholdID
        let task = Task { @MainActor in
            var attempt = 0
            repeat {
                let revision = self.syncMetadata.localRevision

                // 1. Take what the other phone has published and fold it in.
                //    Doing this before every push is what makes two phones
                //    converge instead of one of them being refused forever.
                let incoming = try await self.cloudService.pullHousehold(
                    householdId: householdID, rawConnectionString: connection
                )
                try self.assertIdentity(connection: connection, household: householdID)
                if let incoming {
                    self.merge(incoming.state)
                    self.syncMetadata.remoteRevision = incoming.revision
                } else {
                    self.syncMetadata.remoteRevision = nil
                }

                // 2. Publish the union — unless the cloud already holds every
                //    shared record we have. Re-publishing an identical
                //    household would only bump the revision, which the other
                //    phone would read as news and answer with a write of its
                //    own, forever.
                if let incoming,
                   self.sharedFingerprint(self.snapshot()) == self.sharedFingerprint(incoming.state) {
                    self.syncMetadata.uploadedRevision = revision
                    self.syncPending = self.syncMetadata.localRevision != revision
                    if !self.syncPending { self.lastNeonSyncDate = self.nowProvider() }
                    self.persist()
                    continue
                }

                do {
                    let remoteRevision = try await self.cloudService.pushHousehold(
                        state: self.snapshot().cloudPayload(), householdId: householdID,
                        expectedRevision: self.syncMetadata.remoteRevision, rawConnectionString: connection
                    )
                    // A settings edit while awaiting the server must not attach
                    // the old response to a different household or database.
                    try self.assertIdentity(connection: connection, household: householdID)
                    self.syncMetadata.remoteRevision = remoteRevision
                    self.syncMetadata.uploadedRevision = revision
                    self.syncPending = self.syncMetadata.localRevision != revision
                    attempt = 0
                } catch NeonError.conflict {
                    // The other phone wrote between our pull and our push. Its
                    // work is now the baseline, so go round again rather than
                    // stranding this device the way a bare push did.
                    try self.assertIdentity(connection: connection, household: householdID)
                    attempt += 1
                    guard attempt <= Self.syncConflictRetries else { throw NeonError.conflict }
                    self.syncPending = true
                    continue
                }
                if !self.syncPending { self.lastNeonSyncDate = self.nowProvider() }
                self.persist()
            } while self.syncPending
        }
        syncTask = task
        defer { syncTask = nil }
        do {
            try await task.value
            syncError = nil
        } catch {
            syncPending = true
            syncError = error.localizedDescription
            persist()
            throw error
        }
    }

    /// Explicit replacement from Settings. An in-flight local edit aborts the
    /// download rather than discarding a change made while it was fetching.
    @MainActor
    public func pullFromNeon() async throws -> Bool {
        guard syncTask == nil else { throw NeonError.invalidConfig("Wait for the current sync before downloading.") }
        prepareSyncIdentity()
        let revision = syncMetadata.localRevision
        let connection = neonConnectionString
        let householdID = cloudHouseholdID
        guard let remote = try await cloudService.pullHousehold(householdId: householdID, rawConnectionString: connection) else { return false }
        guard syncTask == nil, syncMetadata.localRevision == revision,
              neonConnectionString == connection, cloudHouseholdID == householdID else {
            throw NeonError.conflict
        }
        apply(remote.state)
        showOnboarding = !hasCompletedOnboarding
        syncMetadata.remoteRevision = remote.revision
        syncMetadata.uploadedRevision = syncMetadata.localRevision
        syncPending = false
        syncError = nil
        lastNeonSyncDate = nowProvider()
        persist()
        refreshDepartureReminders()
        return true
    }

    @MainActor
    public func resumePendingSync() async {
        guard hasCompletedOnboarding, neonSyncEnabled, syncPending, !neonConnectionString.isEmpty else { return }
        do { try await syncWithNeon() } catch { syncError = error.localizedDescription }
    }

    // MARK: - Live sync

    /// How often an open app asks whether the household has moved on. Neon is
    /// reached over plain HTTP with no push channel, so the other phone's edit
    /// lands within one of these rather than instantly.
    public static let liveSyncInterval: TimeInterval = 4

    private var liveSyncTask: Task<Void, Never>?

    /// Starts watching the cloud household while the app is on screen. Each tick
    /// asks only for the revision, and pulls the household itself when that
    /// revision has actually moved — a full pull every few seconds would be a
    /// lot of traffic to learn that nothing happened.
    @MainActor
    public func startLiveSync() {
        guard liveSyncTask == nil else { return }
        liveSyncTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(Self.liveSyncInterval * 1_000_000_000))
                if Task.isCancelled { return }
                guard let self else { return }
                await self.liveSyncTick()
            }
        }
    }

    @MainActor
    public func stopLiveSync() {
        liveSyncTask?.cancel()
        liveSyncTask = nil
    }

    @MainActor
    func liveSyncTick() async {
        guard hasCompletedOnboarding, neonSyncEnabled, !neonConnectionString.isEmpty else { return }
        // Never race the sync already running; it will publish what we have.
        guard syncTask == nil else { return }
        do {
            if !syncPending {
                let revision = try await cloudService.fetchRevision(
                    householdId: cloudHouseholdID, rawConnectionString: neonConnectionString
                )
                // Nothing new upstream and nothing waiting here: stay quiet.
                guard revision != syncMetadata.remoteRevision else { return }
            }
            try await syncWithNeon()
        } catch is CancellationError {
            return
        } catch {
            // A dropped tick is normal on the school run. Keep the message for
            // Settings, and let the next tick try again.
            syncError = error.localizedDescription
        }
    }

    /// Fills in coordinates for saved places that only have a street address.
    /// Without this a household whose home was never geocoded has no position at
    /// all, so `homeCoordinate` is nil and both drive times and weather quietly
    /// fall back to the sample coordinate baked into `LocationService`.
    @MainActor
    public func resolveMissingPlaceCoordinates() async {
        let pending = locations.filter {
            $0.latitude == nil && $0.longitude == nil
                && !$0.address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !pending.isEmpty else { return }

        var resolved = false
        for place in pending {
            guard let coord = await LocationService.shared.geocode(address: place.address) else { continue }
            // Re-find by name: the list may have moved while we were away.
            guard let idx = locations.firstIndex(where: { $0.name == place.name }),
                  locations[idx].latitude == nil else { continue }
            locations[idx].latitude = coord.latitude
            locations[idx].longitude = coord.longitude
            resolved = true
        }

        guard resolved else { return }
        if let coord = homeCoordinate {
            LocationService.shared.homeCoordinateFallback = coord
        }
        save()
    }

    public func destinationCoordinate(for event: TaskRecord) -> CLLocationCoordinate2D? {
        // 1. If explicit latitude & longitude are attached to the stop
        if let lat = event.latitude, let lng = event.longitude {
            return CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }

        let locName = event.location.trimmingCharacters(in: .whitespaces)

        // 2. If destination is explicitly named and exists in household locations
        if !locName.isEmpty,
           let dest = locations.first(where: { $0.name.lowercased() == locName.lowercased() }),
           let lat = dest.latitude, let lng = dest.longitude {
            return CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }

        // 3. Only an explicitly home-bound stop should use the home coordinate.
        if event.mode == "Home" || locName.lowercased() == "home" || locName.lowercased() == homePlaceName.lowercased() {
            return homeCoordinate
        }

        // An unknown destination is not Home. Callers can fall back to the
        // event's formatted address, while drive-time calculation correctly
        // reports that it still needs a route.
        return nil
    }

    @MainActor
    public func calculateDeviceDriveTime(for event: TaskRecord) async -> Int? {
        guard let destCoord = destinationCoordinate(for: event) else {
            self.realTimeDeviceEta = nil
            return nil
        }
        let deviceCoord = LocationService.shared.effectiveCoordinate

        // If the device is already within 150 meters of the destination, ETA is 0 min
        let meters = LocationService.distanceInMeters(from: deviceCoord, to: destCoord)
        if meters < 150 {
            self.realTimeDeviceEta = 0
            return 0
        }

        if let result = await GoogleMapsService.shared.calculateDriveTime(from: deviceCoord, to: destCoord, apiKey: googleMapsApiKey) {
            self.realTimeDeviceEta = result.durationMinutes
            return result.durationMinutes
        }
        return nil
    }

    /// Resolves the leave-by route used by notifications. This intentionally
    /// uses Apple Maps even when a Google API key is configured, keeping the
    /// notification in sync with the app's Apple Maps navigation experience.
    @MainActor
    public func appleMapsDriveTime(for event: TaskRecord, arrivingAt appointmentDate: Date) async -> Int? {
        guard let destination = destinationCoordinate(for: event) else { return nil }
        let origin = LocationService.shared.effectiveCoordinate
        if LocationService.distanceInMeters(from: origin, to: destination) < 150 { return 0 }
        return await GoogleMapsService.shared.calculateAppleDriveTime(
            from: origin,
            to: destination,
            arrivingAt: appointmentDate
        )?.durationMinutes
    }

    @MainActor
    public func calculateDeviceDriveTime(to destinationName: String) async -> Int? {
        let dummy = TaskRecord(id: "query", date: "", owner: "", location: destinationName)
        return await calculateDeviceDriveTime(for: dummy)
    }

    // MARK: - Onboarding

    /// Replaces the household with the answers from setup. Everything the sample
    /// week held is dropped — after setup the app shows this family, not a demo.
    public func applyOnboarding(_ draft: OnboardingDraft) {
        let result = draft.build(
            baseWeek: PlanCore.currentMonday(date: nowProvider(), timeZone: TimeZone(identifier: timeZone) ?? .current),
            timeZone: timeZone
        )

        people = result.people
        locations = result.locations
        routes = result.routes
        parentLocations = result.parentLocations
        templates = result.templates
        plan = PlanMetadata(seriesDefinitions: result.seriesDefinitions.map { definition in
            var stamped = definition
            stamped.stamp = nextStamp()
            return stamped
        })
        partitionRecords(result.records)
        homePlaceName = result.homePlaceName
        homeAddress = result.homeAddress
        currentUser = result.currentUser

        goKidFilter = "all"
        goCrewFilter = nil
        goDraft = nil
        familyKidStatsFilter = "All"

        savedOnboardingDraft = draft
        hasCompletedOnboarding = true
        showOnboarding = false
        save()
    }

    /// Opens setup again, starting from what the household answered last time.
    public func restartOnboarding() {
        showOnboarding = true
    }

    /// A rerun always reflects the household as it exists now. Historical setup
    /// answers must not overwrite later renames, places, or shortcuts.
    public func onboardingStartingPoint() -> OnboardingDraft {
        if hasCompletedOnboarding { return OnboardingDraft.from(store: self) }
        if let saved = savedOnboardingDraft { return saved }
        return OnboardingDraft()
    }

    // MARK: - Mutations & Operations

    public func allReferences(_ name: String) -> Int {
        var count = 0
        for e in records() {
            if e.owner == name || e.kids.contains(name) { count += 1 }
        }
        for t in templates {
            if t.owner == name || t.kids.contains(name) { count += 1 }
        }
        return count
    }

    public func renamePerson(id: String, value: String) throws {
        guard let idx = people.firstIndex(where: { $0.id == id }) else {
            throw NSError(domain: "AppStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "This person is no longer in the family."])
        }
        let name = value.trimmingCharacters(in: .whitespaces)
        if name.isEmpty || AppStore.RESERVED_NAMES.contains(name.lowercased()) {
            throw NSError(domain: "AppStore", code: 2, userInfo: [NSLocalizedDescriptionKey: "Choose a personal name, rather than a shared assignment label."])
        }
        if people.contains(where: { $0.id != id && $0.name.lowercased() == name.lowercased() }) {
            throw NSError(domain: "AppStore", code: 3, userInfo: [NSLocalizedDescriptionKey: "Someone in the family already uses that name."])
        }

        let from = people[idx].name
        if from == name { return }

        // Cascade rename through records
        for d in eventsByDay.keys {
            if var list = eventsByDay[d] {
                for i in list.indices {
                    if list[i].owner == from { list[i].owner = name }
                    if list[i].lead == from { list[i].lead = name }
                    list[i].kids = list[i].kids.map { $0 == from ? name : $0 }
                    list[i].kid = list[i].kids.joined(separator: ", ")
                }
                eventsByDay[d] = list
            }
        }
        for i in plan.future.indices {
            if plan.future[i].owner == from { plan.future[i].owner = name }
            if plan.future[i].lead == from { plan.future[i].lead = name }
            plan.future[i].kids = plan.future[i].kids.map { $0 == from ? name : $0 }
            plan.future[i].kid = plan.future[i].kids.joined(separator: ", ")
        }
        for i in templates.indices {
            if templates[i].owner == from { templates[i].owner = name }
            templates[i].kids = templates[i].kids.map { $0 == from ? name : $0 }
            templates[i].kid = templates[i].kids.joined(separator: ", ")
        }
        if var draft = goDraft {
            if draft.owner == from { draft.owner = name }
            if draft.lead == from { draft.lead = name }
            draft.kids = draft.kids.map { $0 == from ? name : $0 }
            draft.kid = draft.kids.joined(separator: ", ")
            goDraft = draft
        }

        if currentUser == from { currentUser = name }
        if goCrewFilter == from { goCrewFilter = name }
        if goKidFilter == from { goKidFilter = name }
        if let base = parentLocations[from] {
            parentLocations[name] = base
            parentLocations.removeValue(forKey: from)
        }

        people[idx].name = name
        save()
    }

    public func removePerson(id: String) {
        if let idx = people.firstIndex(where: { $0.id == id }) {
            let removedName = people[idx].name
            people.remove(at: idx)

            // Explicitly clean draft providers if any
            for provider in draftProviders {
                if var draft = provider() {
                    if draft.owner == removedName {
                        draft.owner = "TBD"
                        draft.lead = "TBD"
                        draft.locked = false
                        draft.tentative = false
                    }
                    draft.kids.removeAll { $0 == removedName }
                    draft.kid = draft.kids.joined(separator: ", ")
                }
            }

            save()
        }
    }

    public func setPersonRole(id: String, relationship: String) {
        if let idx = people.firstIndex(where: { $0.id == id }) {
            people[idx].relationship = relationship
            people[idx].kind = (relationship == "Child") ? "child" : "caregiver"
            let name = people[idx].name
            if people[idx].kind == "caregiver" && parentLocations[name] == nil {
                parentLocations[name] = home()
            }
            save()
        }
    }

    public func addPerson(kind: String) -> Person {
        var n = 1
        var name = ""
        repeat {
            name = (kind == "child") ? "Child \(n)" : "Caregiver \(n)"
            n += 1
        } while people.contains(where: { $0.name == name })

        let palette = (kind == "child") ? OnboardingDraft.childInks : OnboardingDraft.caregiverInks
        let taken = people.filter { $0.kind == kind }.count
        let color = palette[taken % palette.count]
        let p = Person(
            id: "person-\(Date().timeIntervalSince1970)-\(Int.random(in: 1000...9999))",
            name: name,
            relationship: kind == "child" ? "Child" : "Other",
            kind: kind,
            color: color
        )
        people.append(p)
        if kind == "caregiver" {
            parentLocations[name] = home()
        }
        save()
        return p
    }

    public func setSetting(key: String, value: Any) throws {
        guard AppStore.SETTINGS_KEYS.contains(key) else {
            throw NSError(domain: "AppStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unknown setting."])
        }
        if key == "buffer" {
            guard let v = value as? Int, v >= 0, v <= 45 else {
                throw NSError(domain: "AppStore", code: 2, userInfo: [NSLocalizedDescriptionKey: "Choose a buffer from 0 to 45 minutes."])
            }
            buffer = v
        } else if key == "trafficMode" {
            trafficMode = (value as? Bool) ?? false
        } else if key == "dinnerProtection" {
            dinnerProtection = (value as? Bool) ?? false
        } else if key == "timeZone" {
            let tz = String(describing: value)
            if tz != "device" {
                guard TimeZone(identifier: tz) != nil else {
                    throw NSError(domain: "AppStore", code: 3, userInfo: [NSLocalizedDescriptionKey: "Choose a valid time zone."])
                }
            }
            timeZone = tz
        }
        save()
    }

    public func planningRules(for week: String) -> WeekPriority {
        let monday = PlanCore.monday(week)
        return plan.priorities[monday]
            ?? WeekPriority(
                enabled: dinnerProtection,
                days: [0, 1, 2, 3, 4, 5, 6],
                time: "18:30"
            )
    }

    public func weeklyPlanningNotes(for week: String) -> String {
        plan.weeklyNotes?[PlanCore.monday(week)] ?? ""
    }

    /// One canonical save path for the Planning Rules sheet. The global travel
    /// settings and the selected week's dinner contract are committed together.
    public func updatePlanningRules(
        for week: String,
        dinnerProtected: Bool,
        dinnerTime: String,
        bufferMinutes: Int,
        peakTraffic: Bool,
        notes: String
    ) throws {
        guard (0...45).contains(bufferMinutes) else {
            throw NSError(domain: "AppStore", code: 20, userInfo: [NSLocalizedDescriptionKey: "Choose a buffer from 0 to 45 minutes."])
        }
        let timeParts = dinnerTime.split(separator: ":").compactMap { Int($0) }
        guard timeParts.count == 2,
              (0...23).contains(timeParts[0]),
              (0...59).contains(timeParts[1]) else {
            throw NSError(domain: "AppStore", code: 21, userInfo: [NSLocalizedDescriptionKey: "Enter dinner time as HH:mm."])
        }

        let monday = PlanCore.monday(week)
        buffer = bufferMinutes
        trafficMode = peakTraffic
        dinnerProtection = dinnerProtected
        plan.priorities[monday] = WeekPriority(
            enabled: dinnerProtected,
            days: [0, 1, 2, 3, 4, 5, 6],
            time: String(format: "%02d:%02d", timeParts[0], timeParts[1])
        )
        var allNotes = plan.weeklyNotes ?? [:]
        let cleanNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanNotes.isEmpty { allNotes.removeValue(forKey: monday) }
        else { allNotes[monday] = cleanNotes }
        plan.weeklyNotes = allNotes.isEmpty ? nil : allNotes
        save()
    }

    public func setAlertPreference(_ key: String, enabled: Bool) throws {
        switch key {
        case "notifyLeaveBy": notifyLeaveBy = enabled
        case "notifyDriverNeeded": notifyDriverNeeded = enabled
        case "notifyCrew":
            guard !enabled else {
                throw NSError(domain: "AppStore", code: 25, userInfo: [NSLocalizedDescriptionKey: "Crew reassignment alerts require the authenticated household notification service."])
            }
            notifyCrew = false
        default:
            throw NSError(domain: "AppStore", code: 22, userInfo: [NSLocalizedDescriptionKey: "Unknown alert preference."])
        }
        save()
    }

    public func setConnection(_ key: String, enabled: Bool) throws {
        guard key == "google" || key == "apple" else {
            throw NSError(domain: "AppStore", code: 23, userInfo: [NSLocalizedDescriptionKey: "Unknown calendar connection."])
        }
        if key == "google" {
            if enabled {
                guard isGoogleAuthenticated || googleCalendarService.isAuthenticated() else {
                    throw NSError(domain: "AppStore", code: 26, userInfo: [NSLocalizedDescriptionKey: "Sign in with Google before enabling Google Calendar sync."])
                }
                connections["google"] = true
                isGoogleAuthenticated = true
            } else {
                connections["google"] = false
                isGoogleAuthenticated = false
                googleAccountEmail = ""
                googleCalendars = []
                Task {
                    try? await self.googleCalendarService.disconnect()
                }
            }
        } else {
            connections[key] = enabled
        }
        save()
    }

    public func setActiveUser(_ name: String) throws {
        guard name == "All" || caregivers().contains(name) else {
            throw NSError(domain: "AppStore", code: 24, userInfo: [NSLocalizedDescriptionKey: "Choose a current caregiver profile."])
        }
        currentUser = name
        save()
    }

    public func upsertTemplate(_ template: TemplateItem) {
        if let index = templates.firstIndex(where: { $0.id == template.id }) {
            templates[index] = template
        } else {
            templates.append(template)
        }
        save()
    }

    public func removeTemplate(id: String) {
        templates.removeAll { $0.id == id }
        save()
    }

    /// Reconciles a bounded EventKit import without replacing app-owned
    /// overlays such as caregiver assignment, completion, children, and notes.
    public func mergeAppleCalendarEvents(
        _ imported: [TaskRecord],
        calendarIDs: Set<String>,
        from startDate: String,
        through endDate: String
    ) {
        let incomingKeys = Set(imported.compactMap(\.calendarId))
        var all = records().filter { existing in
            guard let key = existing.calendarId, key.hasPrefix("apple|") else { return true }
            let fields = key.split(separator: "|", omittingEmptySubsequences: false)
            guard fields.count >= 2, calendarIDs.contains(String(fields[1])) else { return true }
            guard existing.date >= startDate && existing.date <= endDate else { return true }
            return incomingKeys.contains(key)
        }

        for providerEvent in imported {
            if let index = all.firstIndex(where: { $0.calendarId == providerEvent.calendarId }) {
                all[index].date = providerEvent.date
                all[index].time = providerEvent.time
                all[index].endTime = providerEvent.endTime
                all[index].title = providerEvent.title
                all[index].location = providerEvent.location
                all[index].mode = providerEvent.mode
                all[index].kind = providerEvent.kind
                all[index].allDay = providerEvent.allDay
                all[index].seriesId = providerEvent.seriesId
                all[index].originalOccurrenceDate = providerEvent.originalOccurrenceDate
            } else {
                all.append(providerEvent)
            }
        }

        plan.calendar.appleCalendarIDs = calendarIDs.sorted()
        plan.calendar.pulled = imported.compactMap(\.calendarId).sorted()
        plan.calendar.lastAppleImport = nowProvider()
        partitionRecords(all)
        save()
    }

    // MARK: - Google Calendar Operations

    @MainActor
    public func connectGoogleAccount() async throws {
        let clientId = googleClientId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? AppConfig.defaultGoogleClientId
            : googleClientId
        guard !clientId.isEmpty else {
            throw GoogleCalendarError.missingClientId
        }
        let result = try await googleCalendarService.authenticate(clientId: clientId)
        googleAccountEmail = result.userEmail
        isGoogleAuthenticated = true
        connections["google"] = true
        try? secretStore.set(googleClientId, for: "googleClientId")
        try? await refreshGoogleCalendars()
        save()
    }

    @MainActor
    public func disconnectGoogleAccount() async {
        try? await googleCalendarService.disconnect()
        isGoogleAuthenticated = false
        connections["google"] = false
        googleAccountEmail = ""
        googleCalendars = []
        save()
    }

    @MainActor
    public func refreshGoogleCalendars() async throws {
        guard isGoogleAuthenticated else { return }
        let cals = try await googleCalendarService.listCalendars()
        googleCalendars = cals
        if plan.calendar.googleCalendarIDs == nil || plan.calendar.googleCalendarIDs?.isEmpty == true {
            if let primary = cals.first(where: { $0.isPrimary }) ?? cals.first {
                plan.calendar.googleCalendarIDs = [primary.id]
                plan.calendar.googleExportCalendarID = primary.id
                save()
            }
        }
    }

    /// Reconciles a bounded Google Calendar import without replacing app-owned
    /// overlays such as caregiver assignment, completion, children, and notes.
    public func mergeGoogleCalendarEvents(
        _ imported: [TaskRecord],
        calendarIDs: Set<String>,
        from startDate: String,
        through endDate: String
    ) {
        func googleKey(_ key: String?) -> String? {
            guard let key, key.hasPrefix("google|") else { return nil }
            let fields = key.split(separator: "|", omittingEmptySubsequences: false)
            guard fields.count >= 3 else { return key }
            return "google|\(fields[1])|\(fields[2])"
        }

        let incomingKeys = Set(imported.compactMap(\.calendarId))
        let incomingIdentities = Set(imported.compactMap { googleKey($0.calendarId) })

        var all = records().filter { existing in
            guard let key = existing.calendarId, key.hasPrefix("google|") else { return true }
            let fields = key.split(separator: "|", omittingEmptySubsequences: false)
            guard fields.count >= 2, calendarIDs.contains(String(fields[1])) else { return true }
            guard existing.date >= startDate && existing.date <= endDate else { return true }
            guard let ident = googleKey(key) else { return incomingKeys.contains(key) }
            return incomingIdentities.contains(ident)
        }

        for providerEvent in imported {
            let providerIdent = googleKey(providerEvent.calendarId)
            if let index = all.firstIndex(where: {
                $0.calendarId == providerEvent.calendarId ||
                (providerIdent != nil && googleKey($0.calendarId) == providerIdent)
            }) {
                all[index].date = providerEvent.date
                all[index].time = providerEvent.time
                all[index].endTime = providerEvent.endTime
                all[index].title = providerEvent.title
                all[index].location = providerEvent.location
                all[index].mode = providerEvent.mode
                all[index].kind = providerEvent.kind
                all[index].allDay = providerEvent.allDay
                all[index].seriesId = providerEvent.seriesId
                all[index].originalOccurrenceDate = providerEvent.originalOccurrenceDate
                all[index].calendarId = providerEvent.calendarId
                all[index].gcal = true
            } else {
                var newRecord = providerEvent
                newRecord.gcal = true
                all.append(newRecord)
            }
        }

        plan.calendar.googleCalendarIDs = calendarIDs.sorted()
        var updatedPulled = Set(plan.calendar.pulled)
        for key in incomingKeys { updatedPulled.insert(key) }
        plan.calendar.pulled = updatedPulled.sorted()
        plan.calendar.lastGoogleImport = nowProvider()
        partitionRecords(all)
        save()
    }

    /// Writes an event to Google Calendar (create or update).
    /// Enforces conflict detection with ETag and only sets task.gcal = true
    /// once the external write has succeeded.
    @discardableResult
    public func exportEventToGoogleCalendar(_ task: TaskRecord) async throws -> TaskRecord {
        guard isGoogleAuthenticated else {
            throw GoogleCalendarError.unauthenticated
        }

        let targetCalendarId = plan.calendar.googleExportCalendarID
            ?? plan.calendar.googleCalendarIDs?.first
            ?? "primary"

        var tz = TimeZone(identifier: timeZone) ?? .current
        if timeZone == "device" { tz = .current }

        var updatedTask = task
        let currentEtag = plan.calendar.exports[task.id]

        if let calId = task.calendarId, calId.hasPrefix("google|") {
            let fields = calId.split(separator: "|", omittingEmptySubsequences: false)
            if fields.count >= 3 {
                let remoteCalId = String(fields[1])
                let remoteEvId = String(fields[2])
                let newEtag = try await googleCalendarService.updateEvent(
                    calendarId: remoteCalId,
                    eventId: remoteEvId,
                    task: task,
                    expectedEtag: currentEtag,
                    timeZone: tz
                )
                plan.calendar.exports[task.id] = newEtag
                updatedTask.gcal = true
            } else {
                let (newEvId, newEtag) = try await googleCalendarService.createEvent(
                    calendarId: targetCalendarId,
                    task: task,
                    timeZone: tz
                )
                let providerKey = "google|\(targetCalendarId)|\(newEvId)"
                updatedTask.calendarId = providerKey
                updatedTask.gcal = true
                plan.calendar.exports[task.id] = newEtag
            }
        } else {
            let (newEvId, newEtag) = try await googleCalendarService.createEvent(
                calendarId: targetCalendarId,
                task: task,
                timeZone: tz
            )
            let providerKey = "google|\(targetCalendarId)|\(newEvId)"
            updatedTask.calendarId = providerKey
            updatedTask.gcal = true
            plan.calendar.exports[task.id] = newEtag
        }

        var all = records()
        if let idx = all.firstIndex(where: { $0.id == updatedTask.id }) {
            all[idx] = updatedTask
        } else {
            all.append(updatedTask)
        }
        partitionRecords(all)
        save()
        return updatedTask
    }

    public func deleteEventFromGoogleCalendar(_ task: TaskRecord) async throws {
        guard isGoogleAuthenticated else { return }
        if let calId = task.calendarId, calId.hasPrefix("google|") {
            let fields = calId.split(separator: "|", omittingEmptySubsequences: false)
            if fields.count >= 3 {
                let remoteCalId = String(fields[1])
                let remoteEvId = String(fields[2])
                try? await googleCalendarService.deleteEvent(calendarId: remoteCalId, eventId: remoteEvId)
            }
        }
        plan.calendar.exports.removeValue(forKey: task.id)
        save()
    }

    public func setHomeAddress(
        _ address: String,
        latitude: Double? = nil,
        longitude: Double? = nil,
        placeId: String? = nil
    ) throws {
        guard let idx = locations.firstIndex(where: { $0.name == home() }) else {
            throw NSError(domain: "AppStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Choose a home location first."])
        }
        var updated = locations[idx]
        let cleanAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanAddress.isEmpty else {
            throw NSError(domain: "AppStore", code: 4, userInfo: [NSLocalizedDescriptionKey: "Enter a home street address."])
        }
        let addressChanged = updated.address.caseInsensitiveCompare(cleanAddress) != .orderedSame
        updated.address = cleanAddress
        if addressChanged {
            updated.latitude = nil
            updated.longitude = nil
            updated.placeId = nil
            updated.routeKey = nil
            updated.source = "manual"
        }
        if let lat = latitude, let lng = longitude {
            updated.latitude = lat
            updated.longitude = lng
            updated.source = "resolved"
            LocationService.shared.homeCoordinateFallback = CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }
        updated.placeId = placeId
        try updateLocation(index: idx, data: updated)
    }

    public var homeCoordinate: CLLocationCoordinate2D? {
        if let homeLoc = locations.first(where: { $0.name == home() }),
           let lat = homeLoc.latitude, let lng = homeLoc.longitude {
            return CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }
        return nil
    }

    public func setBases(_ bases: [String: String]) throws {
        let crew = caregivers()
        for (name, place) in bases {
            guard crew.contains(name), hasPlace(place) else {
                throw NSError(domain: "AppStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Choose a saved place for each caregiver."])
            }
        }
        parentLocations = bases
        save()
    }

    public func updateLocation(index: Int, data: LocationItem) throws {
        let name = data.name.trimmingCharacters(in: .whitespaces)
        let addr = data.address.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !addr.isEmpty else {
            throw NSError(domain: "AppStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Enter a place name and address."])
        }
        if locations.indices.contains(index) {
            if locations.enumerated().contains(where: { $0.offset != index && $0.element.name.lowercased() == name.lowercased() }) {
                throw NSError(domain: "AppStore", code: 2, userInfo: [NSLocalizedDescriptionKey: "A place already uses this name."])
            }
            let old = locations[index]
            var next = data
            next.name = name
            next.address = addr
            let addressChanged = old.address.caseInsensitiveCompare(addr) != .orderedSame
            next.routeKey = addressChanged ? nil : old.routeKey
            if addressChanged && (next.latitude == old.latitude && next.longitude == old.longitude) {
                // A manually changed address cannot retain coordinates that were
                // resolved for the old text.
                next.latitude = nil
                next.longitude = nil
                next.placeId = nil
                next.source = "manual"
            }
            locations[index] = next

            func updateSharedDestination(_ event: inout TaskRecord) {
                guard event.location == old.name else { return }
                let usedSharedDestination = event.formattedAddress == nil
                    || event.formattedAddress?.caseInsensitiveCompare(old.address) == .orderedSame
                    || (event.latitude == old.latitude && event.longitude == old.longitude)
                guard usedSharedDestination else { return }
                event.formattedAddress = next.address
                event.latitude = next.latitude
                event.longitude = next.longitude
            }
            for day in eventsByDay.keys {
                guard var rows = eventsByDay[day] else { continue }
                for row in rows.indices { updateSharedDestination(&rows[row]) }
                eventsByDay[day] = rows
            }
            for row in plan.future.indices { updateSharedDestination(&plan.future[row]) }

            if old.name != name {
                // Cascade place rename
                for d in eventsByDay.keys {
                    if var list = eventsByDay[d] {
                        for i in list.indices where list[i].location == old.name {
                            list[i].location = name
                        }
                        eventsByDay[d] = list
                    }
                }
                for i in plan.future.indices where plan.future[i].location == old.name {
                    plan.future[i].location = name
                }
                for i in templates.indices where templates[i].location == old.name {
                    templates[i].location = name
                }
                for (k, v) in parentLocations where v == old.name {
                    parentLocations[k] = name
                }
                if homePlaceName == old.name {
                    homePlaceName = name
                }
            }
        } else {
            if locations.contains(where: { $0.name.lowercased() == name.lowercased() }) {
                throw NSError(domain: "AppStore", code: 2, userInfo: [NSLocalizedDescriptionKey: "A place already uses this name."])
            }
            var newLoc = data
            newLoc.name = name
            newLoc.address = addr
            if newLoc.latitude != nil && newLoc.longitude != nil {
                newLoc.source = "resolved"
            } else if newLoc.source == nil {
                newLoc.source = "manual"
            }
            locations.append(newLoc)
        }
        save()
    }

    public func removeLocation(index: Int) throws {
        guard locations.indices.contains(index) else { return }
        let l = locations[index]
        if l.name == home() || parentLocations.values.contains(l.name) {
            throw NSError(domain: "AppStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Change home and starting bases before removing this place."])
        }
        if records().contains(where: { $0.location == l.name }) || templates.contains(where: { $0.location == l.name }) {
            throw NSError(domain: "AppStore", code: 2, userInfo: [NSLocalizedDescriptionKey: "This place is used by an event or template. Change those references first."])
        }
        locations.remove(at: index)
        save()
    }

    // MARK: - Event and recurrence commands

    public func seriesDefinition(id: String) -> SeriesDefinition? {
        plan.seriesDefinitions?.first { $0.seriesId == id && !$0.deleted }
    }

    public func events(inSeries seriesId: String) -> [TaskRecord] {
        records().filter { $0.seriesId == seriesId }.sorted {
            let lhs = $0.originalOccurrenceDate ?? $0.date
            let rhs = $1.originalOccurrenceDate ?? $1.date
            return lhs == rhs ? $0.id < $1.id : lhs < rhs
        }
    }

    private func putSeriesDefinition(_ definition: SeriesDefinition) {
        var definitions = plan.seriesDefinitions ?? []
        definitions.removeAll { $0.seriesId == definition.seriesId }
        definitions.append(definition)
        plan.seriesDefinitions = definitions.sorted { $0.seriesId < $1.seriesId }
    }

    private func putSeriesException(_ exception: SeriesException) {
        var exceptions = plan.seriesExceptions ?? []
        exceptions.removeAll { $0.id == exception.id }
        exceptions.append(exception)
        plan.seriesExceptions = exceptions.sorted { $0.id < $1.id }
    }

    private func clearSeriesException(seriesId: String, originalDate: String) {
        var exceptions = plan.seriesExceptions ?? []
        exceptions.removeAll { $0.seriesId == seriesId && $0.originalDate == originalDate }
        plan.seriesExceptions = exceptions.isEmpty ? nil : exceptions
    }

    /// One mutation path for new stops, single-occurrence edits, and complete
    /// finite-series edits. Existing per-occurrence overlays survive unless the
    /// field was explicitly changed on the occurrence used to open the editor.
    @discardableResult
    public func saveEvent(
        draft: TaskRecord,
        recurrence: RecurrencePattern,
        scope: RecurrenceEditScope = .occurrence,
        sourceOccurrenceID: String? = nil
    ) throws -> [TaskRecord] {
        var all = records()
        let source = sourceOccurrenceID.flatMap { id in all.first { $0.id == id } }

        if scope == .occurrence, let source, source.seriesId != nil {
            _ = try PlanCore.occurrences(
                draft,
                recurrence: RecurrencePattern(mode: .none, startDate: draft.date, timeZone: timeZone)
            )
            var updated = draft
            updated.id = source.id
            updated.seriesId = source.seriesId
            updated.originalOccurrenceDate = source.originalOccurrenceDate ?? source.date
            updated.recurrenceOverride = OccurrenceOverride(
                modified: true,
                moved: updated.date != (source.originalOccurrenceDate ?? source.date)
            )
            updated.done = source.done
            updated.locked = source.locked
            updated.tentative = source.tentative
            updated.notes = source.notes
            updated.calendarId = source.calendarId
            updated.bufferMinutes = source.bufferMinutes
            guard let index = all.firstIndex(where: { $0.id == source.id }) else { return [] }
            all[index] = updated
            let original = updated.originalOccurrenceDate ?? updated.date
            putSeriesException(SeriesException(
                seriesId: updated.seriesId!,
                originalDate: original,
                kind: .modified,
                occurrenceId: updated.id,
                stamp: nextStamp()
            ))
            partitionRecords(all)
            save()
            return [updated]
        }

        if recurrence.mode == .none {
            var singleDraft = draft
            singleDraft.id = source?.id ?? draft.id
            singleDraft.seriesId = nil
            singleDraft.originalOccurrenceDate = nil
            singleDraft.recurrenceOverride = nil
            let generated = try PlanCore.occurrences(singleDraft, recurrence: recurrence)
            if scope == .series, let source, let oldSeriesId = source.seriesId {
                let priorPattern = seriesDefinition(id: oldSeriesId)?.pattern
                    ?? RecurrencePattern(
                        mode: .weekly,
                        startDate: events(inSeries: oldSeriesId).map { $0.originalOccurrenceDate ?? $0.date }.min() ?? source.date,
                        timeZone: timeZone,
                        weekdays: Array(Set(events(inSeries: oldSeriesId).map { PlanCore.weekdayIndex($0.originalOccurrenceDate ?? $0.date) })).sorted(),
                        end: .throughDate(events(inSeries: oldSeriesId).map { $0.originalOccurrenceDate ?? $0.date }.max() ?? source.date)
                    )
                putSeriesDefinition(SeriesDefinition(seriesId: oldSeriesId, pattern: priorPattern, deleted: true, stamp: nextStamp()))
                all.removeAll { $0.seriesId == oldSeriesId }
                var replacement = generated[0]
                replacement.done = source.done
                replacement.locked = source.locked
                replacement.tentative = source.tentative
                replacement.notes = source.notes
                replacement.calendarId = source.calendarId
                replacement.bufferMinutes = source.bufferMinutes
                all.append(replacement)
            } else if let source, let index = all.firstIndex(where: { $0.id == source.id }) {
                var replacement = generated[0]
                replacement.done = source.done
                replacement.locked = source.locked
                replacement.tentative = source.tentative
                replacement.notes = source.notes
                replacement.calendarId = source.calendarId
                replacement.bufferMinutes = source.bufferMinutes
                all[index] = replacement
            } else {
                all.append(generated[0])
            }
            partitionRecords(all)
            save()
            return generated
        }

        let seriesId = source?.seriesId ?? draft.seriesId ?? "series-\(UUID().uuidString)"
        var normalizedPattern = recurrence
        normalizedPattern.mode = .weekly
        let generated = try PlanCore.occurrences(draft, recurrence: normalizedPattern, seriesId: seriesId)
        let existing = all.filter { $0.seriesId == seriesId }
        var existingBySlot: [String: TaskRecord] = [:]
        for item in existing {
            let slot = item.originalOccurrenceDate ?? item.date
            if let prior = existingBySlot[slot],
               (item.stamp ?? RecordStamp()) <= (prior.stamp ?? RecordStamp()) { continue }
            existingBySlot[slot] = item
        }
        let excluded = Set((plan.seriesExceptions ?? [])
            .filter { $0.seriesId == seriesId && $0.kind == .excluded }
            .map(\.originalDate))

        func applyingExplicitChanges(to prior: TaskRecord, generated fresh: TaskRecord) -> TaskRecord {
            guard let source else { return fresh }
            var result = prior
            if draft.title != source.title { result.title = draft.title }
            if draft.time != source.time { result.time = draft.time }
            if draft.endTime != source.endTime { result.endTime = draft.endTime }
            if draft.owner != source.owner { result.owner = draft.owner; result.lead = draft.owner }
            if draft.kids != source.kids { result.kids = draft.kids; result.kid = draft.kid }
            if draft.location != source.location || draft.formattedAddress != source.formattedAddress
                || draft.latitude != source.latitude || draft.longitude != source.longitude {
                result.location = draft.location
                result.formattedAddress = draft.formattedAddress
                result.latitude = draft.latitude
                result.longitude = draft.longitude
            }
            if draft.mode != source.mode { result.mode = draft.mode }
            if draft.kind != source.kind { result.kind = draft.kind }
            if draft.gcal != source.gcal { result.gcal = draft.gcal }
            result.seriesId = seriesId
            result.originalOccurrenceDate = prior.originalOccurrenceDate ?? prior.date
            return result
        }

        var rebuilt: [TaskRecord] = []
        for fresh in generated {
            let slot = fresh.originalOccurrenceDate ?? fresh.date
            guard !excluded.contains(slot) else { continue }
            if let prior = existingBySlot[slot] {
                rebuilt.append(applyingExplicitChanges(to: prior, generated: fresh))
            } else {
                rebuilt.append(fresh)
                clearSeriesException(seriesId: seriesId, originalDate: slot)
            }
        }

        all.removeAll { $0.seriesId == seriesId }
        all.append(contentsOf: rebuilt)
        putSeriesDefinition(SeriesDefinition(
            seriesId: seriesId,
            pattern: normalizedPattern,
            deleted: false,
            stamp: nextStamp()
        ))
        partitionRecords(all)
        save()
        return rebuilt
    }

    public func deleteEvent(id: String, scope: RecurrenceEditScope = .occurrence) {
        var all = records()
        guard let event = all.first(where: { $0.id == id }) else { return }
        if scope == .series, let seriesId = event.seriesId {
            deleteSeries(id: seriesId)
            return
        }
        if let seriesId = event.seriesId {
            let original = event.originalOccurrenceDate ?? event.date
            putSeriesException(SeriesException(
                seriesId: seriesId,
                originalDate: original,
                kind: .excluded,
                stamp: nextStamp()
            ))
        }
        if event.calendarId?.hasPrefix("google|") == true || plan.calendar.exports[event.id] != nil {
            Task {
                try? await self.deleteEventFromGoogleCalendar(event)
            }
        }
        all.removeAll { $0.id == id }
        partitionRecords(all)
        save()
    }

    public func deleteSeries(id seriesId: String) {
        let existing = events(inSeries: seriesId)
        let fallbackStart = existing.map { $0.originalOccurrenceDate ?? $0.date }.min() ?? weekStart
        let fallbackEnd = existing.map { $0.originalOccurrenceDate ?? $0.date }.max() ?? fallbackStart
        let fallback = RecurrencePattern(
            mode: .weekly,
            startDate: fallbackStart,
            timeZone: timeZone,
            weekdays: Array(Set(existing.map { PlanCore.weekdayIndex($0.originalOccurrenceDate ?? $0.date) })).sorted(),
            end: .throughDate(fallbackEnd)
        )
        let pattern = seriesDefinition(id: seriesId)?.pattern ?? fallback
        putSeriesDefinition(SeriesDefinition(seriesId: seriesId, pattern: pattern, deleted: true, stamp: nextStamp()))
        partitionRecords(records().filter { $0.seriesId != seriesId })
        save()
    }

    public func assignEvent(id: String, caregiver: String, scope: RecurrenceEditScope = .occurrence) throws {
        let all = records()
        guard let source = all.first(where: { $0.id == id }) else { return }
        let targets: Set<String>
        if scope == .series, let seriesId = source.seriesId {
            targets = Set(all.filter { $0.seriesId == seriesId }.map(\.id))
        } else {
            targets = [id]
        }
        try assignEvents(
            Dictionary(uniqueKeysWithValues: targets.map { ($0, caregiver) }),
            recordsOccurrenceOverrides: scope == .occurrence
        )
    }

    /// Applies a reviewed set of per-occurrence assignments in one save. This
    /// is used by weekly rebalance as well as single assignment, so a recurring
    /// row never loses the override metadata that protects it during a later
    /// series edit or merge.
    public func assignEvents(
        _ assignments: [String: String],
        recordsOccurrenceOverrides: Bool = true
    ) throws {
        let allowed = Set(caregivers() + ["TBD", "Family"])
        guard assignments.values.allSatisfy(allowed.contains) else {
            throw NSError(domain: "AppStore", code: 30, userInfo: [NSLocalizedDescriptionKey: "Choose a current caregiver."])
        }
        var all = records()
        let knownIds = Set(all.map(\.id))
        guard assignments.keys.allSatisfy(knownIds.contains) else {
            throw NSError(domain: "AppStore", code: 31, userInfo: [NSLocalizedDescriptionKey: "The schedule changed. Review the assignments again."])
        }
        for index in all.indices {
            guard let caregiver = assignments[all[index].id] else { continue }
            all[index].owner = caregiver
            all[index].lead = caregiver
            all[index].tentative = false
            if recordsOccurrenceOverrides, let seriesId = all[index].seriesId {
                all[index].recurrenceOverride = OccurrenceOverride(modified: true, moved: all[index].date != (all[index].originalOccurrenceDate ?? all[index].date))
                putSeriesException(SeriesException(
                    seriesId: seriesId,
                    originalDate: all[index].originalOccurrenceDate ?? all[index].date,
                    kind: .modified,
                    occurrenceId: all[index].id,
                    stamp: nextStamp()
                ))
            }
        }
        partitionRecords(all)
        save()
    }

    public func toggleEventDone(id: String) {
        var all = records()
        guard let index = all.firstIndex(where: { $0.id == id }) else { return }
        all[index].done.toggle()
        if let seriesId = all[index].seriesId {
            all[index].recurrenceOverride = OccurrenceOverride(
                modified: true,
                moved: all[index].date != (all[index].originalOccurrenceDate ?? all[index].date)
            )
            putSeriesException(SeriesException(
                seriesId: seriesId,
                originalDate: all[index].originalOccurrenceDate ?? all[index].date,
                kind: .modified,
                occurrenceId: all[index].id,
                stamp: nextStamp()
            ))
        }
        partitionRecords(all)
        save()
    }

    public func replaceRecords(_ list: [TaskRecord]) {
        partitionRecords(list)
        save()
    }

    public func travel(origin: String, destination: String, at: Int?) -> Int? {
        if origin.isEmpty || destination.isEmpty { return nil }
        if origin == destination { return 0 }
        guard let a = locations.first(where: { $0.name == origin })?.routeKey,
              let b = locations.first(where: { $0.name == destination })?.routeKey,
              let base = routes[a]?[b] else {
            return nil
        }
        let peak = at != nil && ((at! >= 420 && at! < 540) || (at! >= 960 && at! < 1080))
        let mult = (trafficMode && peak) ? 1.15 : 1.0
        return Int(round(Double(base) * mult))
    }

    /// Saved places we can actually pin down: a geocoded pick, a Google place,
    /// or a seed location with a known route key.
    public func verifiedPlaceNames() -> Set<String> {
        var names: Set<String> = []
        for loc in locations {
            let hasCoordinate = loc.latitude != nil && loc.longitude != nil
            let hasPlaceId = !(loc.placeId ?? "").isEmpty
            let hasRouteKey = !(loc.routeKey ?? "").isEmpty
            if hasCoordinate || hasPlaceId || hasRouteKey {
                names.insert(loc.name)
            }
        }
        return names
    }

    public func planningOptions() -> PlanningOptions {
        return PlanningOptions(
            crew: caregivers(),
            home: home(),
            origins: parentLocations,
            buffer: buffer,
            priorities: plan.priorities,
            dinnerProtection: dinnerProtection,
            travel: { [weak self] origin, dest, at in
                return self?.travel(origin: origin, destination: dest, at: at)
            },
            routes: routes,
            verifiedPlaces: verifiedPlaceNames()
        )
    }

    public func clock(now: Date = Date()) -> (minutes: Int, day: Int) {
        var cal = Calendar(identifier: .gregorian)
        if timeZone != "device", let tz = TimeZone(identifier: timeZone) {
            cal.timeZone = tz
        } else {
            cal.timeZone = .current
        }
        let hour = cal.component(.hour, from: now)
        let minute = cal.component(.minute, from: now)
        let weekday = cal.component(.weekday, from: now) // 1=Sun, 2=Mon...
        let dayIdx = (weekday + 5) % 7 // 0=Mon... 6=Sun
        return (minutes: hour * 60 + minute, day: dayIdx)
    }

    public func syncWithDeviceDate() {
        let now = nowProvider()
        let currentDay = clock(now: now).day
        let monday = PlanCore.currentMonday(date: now, timeZone: TimeZone(identifier: timeZone) ?? .current)
        if weekStart != monday {
            let all = records()
            weekStart = monday
            partitionRecords(all)
            persist()
            refreshDepartureReminders()
        }
        if todayIndex != currentDay {
            if activeDay == todayIndex { activeDay = currentDay }
            todayIndex = currentDay
        }
    }

    public var currentDate: Date { nowProvider() }

    public func resetSchedule(seed: [Int: [TaskRecord]] = SeedData.defaultEventsByDay()) {
        eventsByDay = seed
        plan.future = []
        plan.reviewed = [:]
        plan.calendar = CalendarMetadata()
        dismissedEventIds = []
        save()
    }

    public func clearData() {
        eventsByDay = [:]
        plan = PlanMetadata()
        templates = []
        dismissedEventIds = []
        save()
    }

    // MARK: - Plan Review Dismissals

    public func dismissReview(for eventId: String) {
        dismissedEventIds.insert(eventId)
        save()
    }

    public func dismissAllReviews(for eventIds: [String]) {
        for id in eventIds {
            dismissedEventIds.insert(id)
        }
        save()
    }

    public func restoreReview(for eventId: String) {
        dismissedEventIds.remove(eventId)
        save()
    }

    public func isReviewDismissed(eventId: String) -> Bool {
        return dismissedEventIds.contains(eventId)
    }
}

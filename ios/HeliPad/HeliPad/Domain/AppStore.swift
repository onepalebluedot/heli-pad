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
    @Published public var cloudHouseholdID: String = UUID().uuidString
    @Published public private(set) var syncError: String?
    @Published public private(set) var syncPending: Bool = false
    private var syncMetadata = HouseholdSyncMetadata()
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
        notifyCrew: Bool = true,
        connections: [String: Bool] = ["google": false, "apple": false],
        routes: [String: [String: Int]] = SeedData.routeMatrix,
        defaultLocations: [LocationItem]? = nil,
        cloudService: HouseholdCloudService = NeonDatabaseService.shared,
        secretStore: IntegrationSecretStore = KeychainIntegrationSecrets(),
        schedulesNotifications: Bool = true,
        now: @escaping () -> Date = Date.init
    ) {
        self.schedulesNotifications = schedulesNotifications
        self.cloudService = cloudService
        self.secretStore = secretStore
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

    public static func dayDate(_ d: Int) -> String {
        return PlanCore.dateAdd(BASE_WEEK, d)
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
            let day = PlanCore.daysBetween(weekStart, record.date)
            if (0...6).contains(day) {
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

        if !e.location.isEmpty && !hasPlace(e.location) {
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

    public func save(syncToCloud: Bool = true) {
        reconcile()
        prepareSyncIdentity()
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

    /// Re-queues the leave-in-10 reminders from the current schedule. The
    /// service debounces, so calling this on every save is cheap.
    public func refreshDepartureReminders() {
        guard schedulesNotifications else { return }
        NotificationService.shared.scheduleReminders(
            records: records(),
            timeZoneId: timeZone,
            enabled: notifyLeaveBy
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
            syncMetadata: syncMetadata
        )
    }

    private func persist() {
        guard persistenceEnabled else { return }
        do {
            try secretStore.set(googleMapsApiKey, for: "googleMapsApiKey")
            try secretStore.set(neonConnectionString, for: "neonConnectionString")
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
        notifyCrew = state.notifyCrew
        connections = state.connections
        hasCompletedOnboarding = state.hasCompletedOnboarding
        savedOnboardingDraft = state.onboardingDraft
        if let dismissed = state.dismissedEventIds {
            dismissedEventIds = Set(dismissed)
        }
        reconcile()
    }

    // MARK: - Cloud & Services Operations

    @MainActor
    public func updateLiveWeather(forceRefresh: Bool = false) async {
        let coord = LocationService.shared.currentLocation?.coordinate
        let w = await WeatherService.shared.fetchWeather(coordinate: coord, forceRefresh: forceRefresh)
        self.liveWeather = w
    }

    private func prepareSyncIdentity() {
        let fingerprint = SHA256.hash(data: Data(neonConnectionString.utf8)).map { String(format: "%02x", $0) }.joined()
        if syncMetadata.connectionFingerprint != fingerprint || syncMetadata.householdID != cloudHouseholdID {
            syncMetadata = HouseholdSyncMetadata(householdID: cloudHouseholdID, connectionFingerprint: fingerprint)
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
            repeat {
                let revision = self.syncMetadata.localRevision
                let remoteRevision = try await self.cloudService.pushHousehold(
                    state: self.snapshot().cloudPayload(), householdId: householdID,
                    expectedRevision: self.syncMetadata.remoteRevision, rawConnectionString: connection
                )
                // A settings edit while awaiting the server must not attach the
                // old response to a different household or database.
                guard self.neonConnectionString == connection, self.cloudHouseholdID == householdID else {
                    throw NeonError.invalidConfig("Cloud connection changed during sync. Sync the selected household again.")
                }
                self.syncMetadata.remoteRevision = remoteRevision
                self.syncMetadata.uploadedRevision = revision
                self.syncPending = self.syncMetadata.localRevision != revision
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

    @MainActor
    public func calculateDeviceDriveTime(to destinationName: String) async -> Int? {
        guard let dest = locations.first(where: { $0.name.lowercased() == destinationName.lowercased() }) else {
            return nil
        }
        let deviceCoord = LocationService.shared.effectiveCoordinate
        let destCoord: CLLocationCoordinate2D
        if let lat = dest.latitude, let lng = dest.longitude {
            destCoord = CLLocationCoordinate2D(latitude: lat, longitude: lng)
        } else {
            // Standing in for an unplaceable destination with a sample coordinate
            // produces a confident, wrong ETA. Better to have none.
            self.realTimeDeviceEta = nil
            return nil
        }

        if let result = await GoogleMapsService.shared.calculateDriveTime(from: deviceCoord, to: destCoord, apiKey: googleMapsApiKey) {
            self.realTimeDeviceEta = result.durationMinutes
            return result.durationMinutes
        }
        return nil
    }

    // MARK: - Onboarding

    /// Replaces the household with the answers from setup. Everything the sample
    /// week held is dropped — after setup the app shows this family, not a demo.
    public func applyOnboarding(_ draft: OnboardingDraft) {
        let result = draft.build(baseWeek: PlanCore.currentMonday(date: nowProvider(), timeZone: TimeZone(identifier: timeZone) ?? .current))

        people = result.people
        locations = result.locations
        routes = result.routes
        parentLocations = result.parentLocations
        templates = result.templates
        eventsByDay = result.eventsByDay
        plan = PlanMetadata()
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

    /// The draft setup should open with: the saved answers, then the live
    /// household, and a blank form only on a phone that has neither.
    public func onboardingStartingPoint() -> OnboardingDraft {
        if let saved = savedOnboardingDraft { return saved }
        if hasCompletedOnboarding { return OnboardingDraft.from(store: self) }
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
        updated.address = address.trimmingCharacters(in: .whitespaces)
        if let lat = latitude, let lng = longitude {
            updated.latitude = lat
            updated.longitude = lng
            LocationService.shared.homeCoordinateFallback = CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }
        if let pid = placeId {
            updated.placeId = pid
        }
        updated.source = "manual"
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
            next.routeKey = (old.address == addr) ? old.routeKey : nil
            locations[index] = next

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

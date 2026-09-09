import Foundation
import Security

// MARK: - Persisted state
//
// Everything a household can change from inside the app. Written on every
// `AppStore.save()`, so a phone that is closed mid-week reopens on the same
// week rather than on the sample data.

public struct PersistedState: Codable {
    public var version: Int
    public var people: [Person]
    public var locations: [LocationItem]
    public var eventsByDay: [Int: [TaskRecord]]
    public var plan: PlanMetadata
    public var templates: [TemplateItem]
    public var parentLocations: [String: String]
    public var routes: [String: [String: Int]]
    public var homeAddress: String
    public var homePlaceName: String
    public var buffer: Int
    public var trafficMode: Bool
    public var dinnerProtection: Bool
    public var currentUser: String
    public var timeZone: String
    public var notifyLeaveBy: Bool
    public var notifyDriverNeeded: Bool
    public var notifyCrew: Bool
    public var connections: [String: Bool]
    public var hasCompletedOnboarding: Bool
    public var onboardingDraft: OnboardingDraft?
    public var googleMapsApiKey: String? = nil
    public var neonConnectionString: String? = nil
    public var neonSyncEnabled: Bool? = false
    public var lastNeonSyncDate: Date? = nil
    public var dismissedEventIds: [String]? = []
    public var weekStart: String? = nil
    public var syncMetadata: HouseholdSyncMetadata? = nil

    public func cloudPayload() -> PersistedState {
        var state = self
        state.googleMapsApiKey = nil
        state.neonConnectionString = nil
        state.syncMetadata = nil
        state.neonSyncEnabled = nil
        state.lastNeonSyncDate = nil
        return state
    }
    enum CodingKeys: String, CodingKey {
        case version, people, locations, eventsByDay, plan, templates, parentLocations, routes, homeAddress, homePlaceName, buffer, trafficMode, dinnerProtection, currentUser, timeZone, notifyLeaveBy, notifyDriverNeeded, notifyCrew, connections, hasCompletedOnboarding, onboardingDraft, googleMapsApiKey, neonConnectionString, neonSyncEnabled, lastNeonSyncDate, dismissedEventIds, weekStart, syncMetadata
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(version, forKey: .version)
        try container.encodeIfPresent(people, forKey: .people)
        try container.encodeIfPresent(locations, forKey: .locations)
        try container.encodeIfPresent(eventsByDay, forKey: .eventsByDay)
        try container.encodeIfPresent(plan, forKey: .plan)
        try container.encodeIfPresent(templates, forKey: .templates)
        try container.encodeIfPresent(parentLocations, forKey: .parentLocations)
        try container.encodeIfPresent(routes, forKey: .routes)
        try container.encodeIfPresent(homeAddress, forKey: .homeAddress)
        try container.encodeIfPresent(homePlaceName, forKey: .homePlaceName)
        try container.encodeIfPresent(buffer, forKey: .buffer)
        try container.encodeIfPresent(trafficMode, forKey: .trafficMode)
        try container.encodeIfPresent(dinnerProtection, forKey: .dinnerProtection)
        try container.encodeIfPresent(currentUser, forKey: .currentUser)
        try container.encodeIfPresent(timeZone, forKey: .timeZone)
        try container.encodeIfPresent(notifyLeaveBy, forKey: .notifyLeaveBy)
        try container.encodeIfPresent(notifyDriverNeeded, forKey: .notifyDriverNeeded)
        try container.encodeIfPresent(notifyCrew, forKey: .notifyCrew)
        try container.encodeIfPresent(connections, forKey: .connections)
        try container.encodeIfPresent(hasCompletedOnboarding, forKey: .hasCompletedOnboarding)
        try container.encodeIfPresent(onboardingDraft, forKey: .onboardingDraft)
        try container.encodeIfPresent(neonSyncEnabled, forKey: .neonSyncEnabled)
        try container.encodeIfPresent(lastNeonSyncDate, forKey: .lastNeonSyncDate)
        try container.encodeIfPresent(dismissedEventIds, forKey: .dismissedEventIds)
        try container.encodeIfPresent(weekStart, forKey: .weekStart)
        try container.encodeIfPresent(syncMetadata, forKey: .syncMetadata)
    }

}

public enum HeliPersistence {
    public static let storageKey = "helipad.state.v1"
    /// Where a household that failed to decode is parked, rather than deleted.
    public static let quarantineKey = "helipad.state.v1.unreadable"

    /// The last household that could not be read, if there is one.
    public static func quarantined(from defaults: UserDefaults = .standard) -> Data? {
        defaults.data(forKey: quarantineKey)
    }
    private static let currentVersion = 1

    public static func load(from defaults: UserDefaults = .standard) -> PersistedState? {
        guard let data = defaults.data(forKey: storageKey) else { return nil }
        do {
            let state = try JSONDecoder().decode(PersistedState.self, from: data)
            guard state.version == currentVersion else { return nil }
            return state
        } catch {
            // A shape we can no longer read is worse than none: fall back to the
            // seed household rather than launching into a half-decoded family.
            // Keep the bytes, though — deleting them turns a decoding slip into
            // permanent data loss, and a later build may well read them fine.
            defaults.set(data, forKey: quarantineKey)
            defaults.removeObject(forKey: storageKey)
            return nil
        }
    }

    public static func save(_ state: PersistedState, to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: storageKey)
    }

    public static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: storageKey)
    }

    public static func version() -> Int { currentVersion }
}


/// Local sync bookkeeping is stripped from every cloud payload.
public struct HouseholdSyncMetadata: Codable {
    public var householdID: String = UUID().uuidString
    /// Identifies this install when two phones stamp an edit at the same
    /// logical moment. Never reused, so ties resolve identically on both sides.
    public var deviceID: String = UUID().uuidString
    /// Logical clock. Raised past anything seen from the other phone.
    public var lamport: Int = 0
    public var connectionFingerprint: String = ""
    public var remoteRevision: String? = nil
    public var localRevision: Int = 0
    public var uploadedRevision: Int = 0

    public init(
        householdID: String = UUID().uuidString,
        deviceID: String = UUID().uuidString,
        lamport: Int = 0,
        connectionFingerprint: String = "",
        remoteRevision: String? = nil,
        localRevision: Int = 0,
        uploadedRevision: Int = 0
    ) {
        self.householdID = householdID
        self.deviceID = deviceID
        self.lamport = lamport
        self.connectionFingerprint = connectionFingerprint
        self.remoteRevision = remoteRevision
        self.localRevision = localRevision
        self.uploadedRevision = uploadedRevision
    }

    /// Decoded field by field, with a default for anything absent. A synthesized
    /// decoder demands every non-optional key, so adding one field here would
    /// otherwise make every household saved by an earlier build unreadable —
    /// and an unreadable household is a lost household.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        householdID = try c.decodeIfPresent(String.self, forKey: .householdID) ?? UUID().uuidString
        deviceID = try c.decodeIfPresent(String.self, forKey: .deviceID) ?? UUID().uuidString
        lamport = try c.decodeIfPresent(Int.self, forKey: .lamport) ?? 0
        connectionFingerprint = try c.decodeIfPresent(String.self, forKey: .connectionFingerprint) ?? ""
        remoteRevision = try c.decodeIfPresent(String.self, forKey: .remoteRevision)
        localRevision = try c.decodeIfPresent(Int.self, forKey: .localRevision) ?? 0
        uploadedRevision = try c.decodeIfPresent(Int.self, forKey: .uploadedRevision) ?? 0
    }
}

public protocol IntegrationSecretStore {
    func get(_ key: String) throws -> String?
    func set(_ value: String, for key: String) throws
}

public struct KeychainIntegrationSecrets: IntegrationSecretStore {
    private let service = "app.helipad.personal-integrations"

    public init() {}

    public func get(_ key: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw KeychainError(status: status) }
        return String(data: data, encoding: .utf8)
    }

    public func set(_ value: String, for key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        if value.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
            return
        }
        let attributes: [String: Any] = [
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let added = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
            guard added == errSecSuccess else { throw KeychainError(status: added) }
        } else if status != errSecSuccess {
            throw KeychainError(status: status)
        }
    }

    private struct KeychainError: Error { let status: OSStatus }
}

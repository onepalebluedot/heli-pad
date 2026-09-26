import Foundation

public struct FamilyAccount: Codable {
    public var id: String
    public var displayName: String
    public var email: String?

    enum CodingKeys: String, CodingKey {
        case id, email
        case displayName = "display_name"
    }
}

public struct FamilySummary: Codable, Identifiable {
    public var id: String
    public var name: String
    public var role: String
}

public struct FamilyProfile: Codable {
    public var account: FamilyAccount
    public var families: [FamilySummary]
}

public struct FamilyMember: Codable, Identifiable {
    public var id: String
    public var displayName: String
    public var role: String

    enum CodingKeys: String, CodingKey {
        case id, role
        case displayName = "display_name"
    }
}

public struct FamilyInvite: Codable {
    public var code: String
    public var expiresAt: String
}

public struct FamilyInvitePreview: Codable {
    public var name: String
    public var expiresAt: String
}

public enum FamilyAccountError: LocalizedError {
    case unavailable
    case invalidResponse
    case notSignedIn
    case rejected(String)

    public var errorDescription: String? {
        switch self {
        case .unavailable: return "Family accounts are not configured in this build."
        case .invalidResponse: return "The family service returned an unreadable response."
        case .notSignedIn: return "Sign in with Apple to continue."
        case .rejected(let message): return message
        }
    }
}

public enum FamilyAccountAccess {
    public static func requiresSignIn(
        apiConfigured: Bool, hasCompletedOnboarding: Bool,
        isManagedFamily: Bool, hasSession: Bool
    ) -> Bool {
        guard apiConfigured else { return false }
        if isManagedFamily { return !hasSession }
        return !hasCompletedOnboarding
    }
}

/// The family API is the only client of the account token. The database URL
/// stays on the service, while the session remains in this device's Keychain.
public final class FamilyAccountAPI {
    public static let shared = FamilyAccountAPI()
    public static let managedConnection = "managed-family"

    private let session: URLSession
    private let secrets: IntegrationSecretStore
    private let tokenKey = "familySessionToken"

    public init(session: URLSession = .shared, secrets: IntegrationSecretStore = KeychainIntegrationSecrets()) {
        self.session = session
        self.secrets = secrets
    }

    public var hasSession: Bool { (try? secrets.get(tokenKey))?.isEmpty == false }

    public func clearSession() throws { try secrets.set("", for: tokenKey) }

    private struct Challenge: Decodable { var nonce: String }
    private struct SignInResponse: Decodable { var token: String; var account: FamilyAccount }
    private struct CreateResponse: Decodable { var family: FamilySummary }
    private struct JoinResponse: Decodable { var familyId: String }
    private struct MembersResponse: Decodable { var members: [FamilyMember] }
    private struct DocumentResponse<T: Decodable>: Decodable { var data: T?; var revision: String? }
    private struct RevisionResponse: Decodable { var revision: String }
    private struct DocumentBody<Content: Encodable>: Encodable {
        var data: Content
        var expectedRevision: String?
    }
    private struct ErrorResponse: Decodable { var error: String }

    public func challenge() async throws -> String {
        let response: Challenge = try await request("v1/auth/challenge", method: "POST", authenticated: false)
        return response.nonce
    }

    public func signIn(identityToken: String, nonce: String, displayName: String) async throws -> FamilyProfile {
        let response: SignInResponse = try await request(
            "v1/auth/apple", method: "POST", authenticated: false,
            body: ["identityToken": identityToken, "nonce": nonce, "displayName": displayName]
        )
        try secrets.set(response.token, for: tokenKey)
        return try await profile()
    }

    public func profile() async throws -> FamilyProfile {
        try await request("v1/me")
    }

    public func createFamily(name: String, state: PersistedState?) async throws -> FamilySummary {
        struct Body: Encodable {
            var name: String
            var state: PersistedState?
        }
        let response: CreateResponse = try await request(
            "v1/families", method: "POST",
            body: Body(name: name, state: state?.cloudPayload())
        )
        return response.family
    }

    public func createInvite(familyID: String) async throws -> FamilyInvite {
        try await request("v1/families/\(familyID)/invites", method: "POST")
    }

    public func members(familyID: String) async throws -> [FamilyMember] {
        let response: MembersResponse = try await request("v1/families/\(familyID)/members")
        return response.members
    }

    public func previewInvite(code: String) async throws -> FamilyInvitePreview {
        try await request("v1/invites/\(code)")
    }

    public func acceptInvite(code: String) async throws -> String {
        let response: JoinResponse = try await request("v1/invites/\(code)/accept", method: "POST")
        return response.familyId
    }

    public func logout() async throws {
        let token = try secrets.get(tokenKey)
        try clearSession()
        guard let token, !token.isEmpty, let base = AppConfig.familyAPIURL,
              let url = URL(string: "v1/auth/logout", relativeTo: base)?.absoluteURL else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 5
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        _ = try? await session.data(for: request)
    }

    public func pullDocument<T: Decodable>(familyID: String, kind: String, revisionOnly: Bool = false) async throws -> (T?, String?) {
        let suffix = revisionOnly ? "?revisionOnly=1" : ""
        let response: DocumentResponse<T> = try await request("v1/families/\(familyID)/documents/\(kind)\(suffix)")
        return (response.data, response.revision)
    }

    public func pushDocument<T: Encodable>(_ document: T, familyID: String, kind: String, expectedRevision: String?) async throws -> String {
        let response: RevisionResponse = try await request(
            "v1/families/\(familyID)/documents/\(kind)", method: "PUT",
            body: DocumentBody(data: document, expectedRevision: expectedRevision)
        )
        return response.revision
    }

    private func request<Result: Decodable, Body: Encodable>(
        _ path: String,
        method: String = "GET",
        authenticated: Bool = true,
        body: Body?
    ) async throws -> Result {
        guard let base = AppConfig.familyAPIURL else { throw FamilyAccountError.unavailable }
        guard let url = URL(string: path, relativeTo: base)?.absoluteURL else { throw FamilyAccountError.unavailable }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if authenticated {
            guard let token = try secrets.get(tokenKey), !token.isEmpty else { throw FamilyAccountError.notSignedIn }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw FamilyAccountError.invalidResponse }
        if response.statusCode == 409 { throw NeonError.conflict }
        if authenticated && response.statusCode == 401 { throw FamilyAccountError.notSignedIn }
        guard (200..<300).contains(response.statusCode) else {
            let message = (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.error ?? "Family service error (\(response.statusCode))."
            throw FamilyAccountError.rejected(message)
        }
        return try JSONDecoder().decode(Result.self, from: data)
    }

    private func request<Result: Decodable>(_ path: String, method: String = "GET", authenticated: Bool = true) async throws -> Result {
        try await request(path, method: method, authenticated: authenticated, body: Optional<String>.none)
    }
}

public struct FamilyHouseholdCloudService: HouseholdCloudService {
    private let legacy: HouseholdCloudService
    private let account: FamilyAccountAPI

    public init(legacy: HouseholdCloudService = NeonDatabaseService.shared, account: FamilyAccountAPI = .shared) {
        self.legacy = legacy
        self.account = account
    }

    public func pushHousehold(state: PersistedState, householdId: String, expectedRevision: String?, rawConnectionString: String) async throws -> String {
        if rawConnectionString == FamilyAccountAPI.managedConnection {
            return try await account.pushDocument(state.cloudPayload(), familyID: householdId, kind: "household", expectedRevision: expectedRevision)
        }
        return try await legacy.pushHousehold(state: state, householdId: householdId, expectedRevision: expectedRevision, rawConnectionString: rawConnectionString)
    }

    public func pullHousehold(householdId: String, rawConnectionString: String) async throws -> RemoteHousehold? {
        if rawConnectionString == FamilyAccountAPI.managedConnection {
            let (state, revision): (PersistedState?, String?) = try await account.pullDocument(familyID: householdId, kind: "household")
            guard let state, let revision else { return nil }
            return RemoteHousehold(state: state.cloudPayload(), revision: revision)
        }
        return try await legacy.pullHousehold(householdId: householdId, rawConnectionString: rawConnectionString)
    }

    public func fetchRevision(householdId: String, rawConnectionString: String) async throws -> String? {
        if rawConnectionString == FamilyAccountAPI.managedConnection {
            let (_, revision): (PersistedState?, String?) = try await account.pullDocument(familyID: householdId, kind: "household", revisionOnly: true)
            return revision
        }
        return try await legacy.fetchRevision(householdId: householdId, rawConnectionString: rawConnectionString)
    }
}

public struct FamilyListsCloudService: HouseholdListsCloudService {
    private let legacy: HouseholdListsCloudService
    private let account: FamilyAccountAPI

    public init(legacy: HouseholdListsCloudService = NeonListsCloudService(), account: FamilyAccountAPI = .shared) {
        self.legacy = legacy
        self.account = account
    }

    public func fetchListsRevision(householdId: String, rawConnectionString: String) async throws -> String? {
        if rawConnectionString == FamilyAccountAPI.managedConnection {
            let (_, revision): (HouseholdListsArchive?, String?) = try await account.pullDocument(familyID: householdId, kind: "lists", revisionOnly: true)
            return revision
        }
        return try await legacy.fetchListsRevision(householdId: householdId, rawConnectionString: rawConnectionString)
    }

    public func pullLists(householdId: String, rawConnectionString: String) async throws -> RemoteHouseholdLists? {
        if rawConnectionString == FamilyAccountAPI.managedConnection {
            let (archive, revision): (HouseholdListsArchive?, String?) = try await account.pullDocument(familyID: householdId, kind: "lists")
            guard let archive, let revision else { return nil }
            guard archive.householdID == householdId else { throw ListError.invalidArchive("household mismatch") }
            return RemoteHouseholdLists(archive: try archive.migrated().cloudPayload(), revision: revision)
        }
        return try await legacy.pullLists(householdId: householdId, rawConnectionString: rawConnectionString)
    }

    public func pushLists(_ archive: HouseholdListsArchive, householdId: String, expectedRevision: String?, rawConnectionString: String) async throws -> String {
        if rawConnectionString == FamilyAccountAPI.managedConnection {
            return try await account.pushDocument(archive.validated().cloudPayload(), familyID: householdId, kind: "lists", expectedRevision: expectedRevision)
        }
        return try await legacy.pushLists(archive, householdId: householdId, expectedRevision: expectedRevision, rawConnectionString: rawConnectionString)
    }
}

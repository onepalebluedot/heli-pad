import Foundation

public struct NeonConfig {
    public var host: String
    public var passwordOrToken: String
    public var database: String
    public var rawConnectionString: String
    public var endpointUrl: URL? {
        URL(string: "https://\(host)/sql")
    }

    public init(
        host: String,
        passwordOrToken: String,
        database: String,
        rawConnectionString: String = ""
    ) {
        self.host = host
        self.passwordOrToken = passwordOrToken
        self.database = database
        self.rawConnectionString = rawConnectionString
    }

    public static func parse(from raw: String) -> NeonConfig? {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Remove parameters incompatible with Neon Serverless HTTP proxy
        trimmed = trimmed.replacingOccurrences(of: "&channel_binding=require", with: "")
        trimmed = trimmed.replacingOccurrences(of: "channel_binding=require&", with: "")
        trimmed = trimmed.replacingOccurrences(of: "?channel_binding=require", with: "")

        // Format 1: Full PostgreSQL URI (e.g. postgresql://user:pass@ep-xyz.us-east-2.aws.neon.tech/neondb)
        if trimmed.starts(with: "postgres://") || trimmed.starts(with: "postgresql://") {
            let components = URLComponents(string: trimmed)
            let host = components?.host ?? URL(string: trimmed)?.host
            guard let validHost = host, !validHost.isEmpty else { return nil }
            let password = components?.password ?? URL(string: trimmed)?.password ?? ""
            let path = components?.path ?? URL(string: trimmed)?.path ?? ""
            let database = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let cleanHost = validHost.replacingOccurrences(of: "-pooler.", with: ".")
            return NeonConfig(
                host: cleanHost,
                passwordOrToken: password,
                database: database.isEmpty ? "neondb" : database,
                rawConnectionString: trimmed
            )
        }

        // Format 2: Direct Neon host (e.g. ep-xyz.us-east-2.aws.neon.tech)
        if trimmed.contains(".neon.tech") {
            let parts = trimmed.split(separator: "/")
            let hostPart = String(parts.first ?? "").replacingOccurrences(of: "-pooler.", with: ".")
            return NeonConfig(
                host: hostPart,
                passwordOrToken: "",
                database: "neondb",
                rawConnectionString: trimmed
            )
        }

        return nil
    }
}

public enum NeonError: LocalizedError {
    case invalidConfig(String)
    case networkError(String)
    case serverError(Int, String)
    case decodingError(String)
    case conflict

    public var errorDescription: String? {
        switch self {
        case .invalidConfig(let msg): return "Neon Configuration Error: \(msg)"
        case .networkError(let msg): return "Neon Network Error: \(msg)"
        case .serverError(let code, let msg): return "Neon Server Error (HTTP \(code)): \(msg)"
        case .decodingError(let msg): return "Neon Data Error: \(msg)"
        case .conflict: return "The cloud household has changed, or already exists on another device. Download it before uploading. Your local changes have been kept."
        }
    }
}

public struct RemoteHousehold {
    public var state: PersistedState
    public var revision: String
}

public protocol HouseholdCloudService {
    func pushHousehold(state: PersistedState, householdId: String, expectedRevision: String?, rawConnectionString: String) async throws -> String
    func pullHousehold(householdId: String, rawConnectionString: String) async throws -> RemoteHousehold?
    /// Just the revision, so a phone can ask "has anything changed?" without
    /// pulling the whole household every few seconds.
    func fetchRevision(householdId: String, rawConnectionString: String) async throws -> String?
}

public class NeonDatabaseService: HouseholdCloudService {
    public static let shared = NeonDatabaseService()

    private let session: URLSession

    public init(session: URLSession = .shared) { self.session = session }

    // MARK: - Execute SQL via Neon Serverless HTTP API

    public func executeSQL(query: String, params: [Any] = [], config: NeonConfig) async throws -> [[String: Any]] {
        guard let url = config.endpointUrl else {
            throw NeonError.invalidConfig("Invalid Neon endpoint URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Pass Neon-Connection-String header required by Neon Serverless HTTP API
        if !config.rawConnectionString.isEmpty {
            request.setValue(config.rawConnectionString, forHTTPHeaderField: "Neon-Connection-String")
        } else if !config.passwordOrToken.isEmpty {
            request.setValue("Bearer \(config.passwordOrToken)", forHTTPHeaderField: "Authorization")
        }

        var bodyDict: [String: Any] = ["query": query]
        if !params.isEmpty {
            bodyDict["params"] = params
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: bodyDict)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw NeonError.networkError(error.localizedDescription)
        }

        guard let httpRes = response as? HTTPURLResponse else {
            throw NeonError.networkError("Invalid HTTP response")
        }

        if httpRes.statusCode != 200 {
            // Server error bodies can include SQL or connection details.
            throw NeonError.serverError(httpRes.statusCode, "Request failed. Check your personal connection and database permissions.")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NeonError.decodingError("Invalid response document")
        }

        // Neon returns {"rows": [[...]]} or {"rows": [{...}]}
        if let rows = json["rows"] as? [[String: Any]] {
            return rows
        }

        return []
    }

    // MARK: - Operations

    public func testConnection(rawConnectionString: String) async throws -> Bool {
        guard let config = NeonConfig.parse(from: rawConnectionString) else {
            throw NeonError.invalidConfig("Could not parse Neon connection string. Please enter a valid postgresql:// connection URL.")
        }

        let rows = try await executeSQL(query: "SELECT 1 AS connected, NOW() AS server_time;", config: config)
        return !rows.isEmpty
    }

    public func bootstrapSchema(rawConnectionString: String) async throws {
        guard let config = NeonConfig.parse(from: rawConnectionString) else {
            throw NeonError.invalidConfig("Invalid connection string")
        }

        let ddl = """
        CREATE TABLE IF NOT EXISTS helipad_household (
            id TEXT PRIMARY KEY,
            state_data JSONB NOT NULL,
            updated_at TIMESTAMPTZ DEFAULT NOW()
        );
        """
        _ = try await executeSQL(query: ddl, config: config)
    }

    public func pushHousehold(
        state: PersistedState,
        householdId: String,
        expectedRevision: String?,
        rawConnectionString: String
    ) async throws -> String {
        guard let config = NeonConfig.parse(from: rawConnectionString), !householdId.isEmpty else {
            throw NeonError.invalidConfig("Enter a personal connection and household ID.")
        }
        try await bootstrapSchema(rawConnectionString: rawConnectionString)
        let data = try JSONEncoder().encode(state.cloudPayload())
        guard let json = String(data: data, encoding: .utf8) else {
            throw NeonError.decodingError("Could not encode household state")
        }

        let rows: [[String: Any]]
        if let expectedRevision {
            // Compare-and-swap occurs in the same statement as the write. Reading
            // first and then doing an unconditional upsert would still race.
            rows = try await executeSQL(query: """
                UPDATE helipad_household
                SET state_data = $2::jsonb, updated_at = GREATEST(clock_timestamp(), updated_at + interval '1 microsecond')
                WHERE id = $1 AND updated_at = $3::timestamptz
                RETURNING updated_at::text AS revision;
                """, params: [householdId, json, expectedRevision], config: config)
        } else {
            rows = try await executeSQL(query: """
                INSERT INTO helipad_household (id, state_data)
                VALUES ($1, $2::jsonb)
                ON CONFLICT (id) DO NOTHING
                RETURNING updated_at::text AS revision;
                """, params: [householdId, json], config: config)
        }
        guard let revision = rows.first?["revision"] as? String else { throw NeonError.conflict }
        return revision
    }

    public func fetchRevision(
        householdId: String,
        rawConnectionString: String
    ) async throws -> String? {
        guard let config = NeonConfig.parse(from: rawConnectionString), !householdId.isEmpty else {
            throw NeonError.invalidConfig("Enter a personal connection and household ID.")
        }
        let rows = try await executeSQL(query: "SELECT updated_at::text AS revision FROM helipad_household WHERE id = $1;",
                                        params: [householdId], config: config)
        return rows.first?["revision"] as? String
    }

    public func pullHousehold(
        householdId: String,
        rawConnectionString: String
    ) async throws -> RemoteHousehold? {
        guard let config = NeonConfig.parse(from: rawConnectionString), !householdId.isEmpty else {
            throw NeonError.invalidConfig("Enter a personal connection and household ID.")
        }
        let rows = try await executeSQL(query: "SELECT state_data, updated_at::text AS revision FROM helipad_household WHERE id = $1;",
                                        params: [householdId], config: config)
        guard let first = rows.first else { return nil }
        guard let state = first["state_data"], let revision = first["revision"] as? String else {
            throw NeonError.decodingError("Household response is missing its state or revision")
        }
        let data = try JSONSerialization.data(withJSONObject: state)
        return RemoteHousehold(state: try JSONDecoder().decode(PersistedState.self, from: data).cloudPayload(), revision: revision)
    }
}

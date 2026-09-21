import Foundation
import CryptoKit

// MARK: - Lists cloud seam
//
// Lists travel in their own record, `helipad_household_lists`, keyed by
// household id. Same transport and the same compare-and-swap discipline as the
// household document, but a separate row and a separate revision, so an older
// build that only knows `helipad_household` can keep writing the schedule
// without ever erasing lists, and a failure in household sync cannot stop lists
// from synchronising.

public struct RemoteHouseholdLists {
    public var archive: HouseholdListsArchive
    public var revision: String
    public var needsMigrationUpload: Bool

    public init(archive: HouseholdListsArchive, revision: String, needsMigrationUpload: Bool = false) {
        self.archive = archive
        self.revision = revision
        self.needsMigrationUpload = needsMigrationUpload
    }
}

public protocol HouseholdListsCloudService {
    /// Just the revision, so a foreground poll can ask "has anything changed?"
    /// without pulling the whole document every couple of seconds.
    func fetchListsRevision(householdId: String, rawConnectionString: String) async throws -> String?
    func pullLists(householdId: String, rawConnectionString: String) async throws -> RemoteHouseholdLists?
    /// `expectedRevision` makes the write a compare-and-swap: two phones saving
    /// at once cannot silently overwrite each other. `nil` means "create", and
    /// conflicts if the record already exists.
    func pushLists(
        _ archive: HouseholdListsArchive,
        householdId: String,
        expectedRevision: String?,
        rawConnectionString: String
    ) async throws -> String
}

/// The Neon-backed implementation, using the existing HTTP SQL transport.
public struct NeonListsCloudService: HouseholdListsCloudService {
    private let database: NeonDatabaseService
    private let schema = ListsSchemaPreparation()

    public init(database: NeonDatabaseService = .shared) {
        self.database = database
    }

    public func bootstrapSchema(rawConnectionString: String) async throws {
        try await schema.prepare(database: database, connection: rawConnectionString)
    }

    public func fetchListsRevision(householdId: String, rawConnectionString: String) async throws -> String? {
        guard let config = NeonConfig.parse(from: rawConnectionString), !householdId.isEmpty else {
            throw NeonError.invalidConfig("Enter a personal connection and household ID.")
        }
        try await bootstrapSchema(rawConnectionString: rawConnectionString)
        let rows = try await database.executeSQL(
            query: "SELECT updated_at::text AS revision FROM helipad_household_lists WHERE id = $1;",
            params: [householdId],
            config: config
        )
        return rows.first?["revision"] as? String
    }

    public func pullLists(householdId: String, rawConnectionString: String) async throws -> RemoteHouseholdLists? {
        guard let config = NeonConfig.parse(from: rawConnectionString), !householdId.isEmpty else {
            throw NeonError.invalidConfig("Enter a personal connection and household ID.")
        }
        try await bootstrapSchema(rawConnectionString: rawConnectionString)
        let rows = try await database.executeSQL(
            query: "SELECT state_data, updated_at::text AS revision FROM helipad_household_lists WHERE id = $1;",
            params: [householdId],
            config: config
        )
        guard let first = rows.first else { return nil }
        guard let state = first["state_data"], let revision = first["revision"] as? String else {
            throw NeonError.decodingError("The household lists response is missing its document or revision")
        }
        let data = try JSONSerialization.data(withJSONObject: state)
        let original = try JSONDecoder().decode(HouseholdListsArchive.self, from: data)
        guard original.householdID == householdId else { throw ListError.invalidArchive("household mismatch") }
        let archive = try original.migrated().cloudPayload()
        return RemoteHouseholdLists(archive: archive, revision: revision, needsMigrationUpload: original.version != archive.version)
    }

    public func pushLists(
        _ archive: HouseholdListsArchive,
        householdId: String,
        expectedRevision: String?,
        rawConnectionString: String
    ) async throws -> String {
        guard let config = NeonConfig.parse(from: rawConnectionString), !householdId.isEmpty else {
            throw NeonError.invalidConfig("Enter a personal connection and household ID.")
        }
        try await bootstrapSchema(rawConnectionString: rawConnectionString)
        let payload = try JSONEncoder().encode(archive.validated().cloudPayload())
        guard let json = String(data: payload, encoding: .utf8) else {
            throw NeonError.decodingError("Could not encode household lists")
        }

        let rows: [[String: Any]]
        if let expectedRevision {
            // The compare-and-swap is the write. Reading first and then doing an
            // unconditional upsert would still race.
            rows = try await database.executeSQL(query: """
                UPDATE helipad_household_lists
                SET state_data = $2::jsonb, updated_at = GREATEST(clock_timestamp(), updated_at + interval '1 microsecond')
                WHERE id = $1 AND updated_at = $3::timestamptz
                RETURNING updated_at::text AS revision;
                """, params: [householdId, json, expectedRevision], config: config)
        } else {
            rows = try await database.executeSQL(query: """
                INSERT INTO helipad_household_lists (id, state_data)
                VALUES ($1, $2::jsonb)
                ON CONFLICT (id) DO NOTHING
                RETURNING updated_at::text AS revision;
                """, params: [householdId, json], config: config)
        }
        guard let revision = rows.first?["revision"] as? String else { throw NeonError.conflict }
        return revision
    }
}

/// Prepare before the first read as well as the first write. Share in-flight
/// setup and cache successful setup so a quiet poll remains one small SELECT.
private actor ListsSchemaPreparation {
    private var ready: Set<String> = []
    private var pending: [String: Task<Void, Error>] = [:]

    func prepare(database: NeonDatabaseService, connection: String) async throws {
        let key = SHA256.hash(data: Data(connection.utf8)).map { String(format: "%02x", $0) }.joined()
        if ready.contains(key) { return }
        if let task = pending[key] { return try await task.value }
        guard let config = NeonConfig.parse(from: connection) else {
            throw NeonError.invalidConfig("Invalid connection string")
        }
        let task = Task {
            // Existing installations only need read/write access. Do not run
            // DDL on every launch: a collaborator may not have CREATE rights.
            let rows = try await database.executeSQL(
                query: "SELECT to_regclass('helipad_household_lists') IS NOT NULL AS lists_ready;",
                config: config
            )
            if rows.first?["lists_ready"] as? Bool == true { return }
            _ = try await database.executeSQL(query: """
                CREATE TABLE IF NOT EXISTS helipad_household_lists (
                    id TEXT PRIMARY KEY,
                    state_data JSONB NOT NULL,
                    updated_at TIMESTAMPTZ DEFAULT NOW()
                );
                """, config: config)
        }
        pending[key] = task
        do {
            try await task.value
            ready.insert(key)
            pending[key] = nil
        } catch {
            pending[key] = nil
            throw error
        }
    }
}

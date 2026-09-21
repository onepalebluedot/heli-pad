import Foundation

// MARK: - Lists storage
//
// One versioned document per household, in its own key.
//
// Separate from `helipad.state.v1` on purpose. That snapshot is written by
// whichever build is installed, so a build that has never heard of a list field
// would drop it the next time it saved the household. This document is either
// read whole or left alone, and a document that cannot be read has its bytes
// kept instead of being overwritten.
//
// Keyed by household so that changing household preserves the lists of the one
// being left: switching back finds them, and a document belonging to another
// household can never be uploaded as this one's.

public enum HouseholdListsPersistence {
    static let storagePrefix = "helipad.lists.v1"
    static let quarantinePrefix = "helipad.lists.v1.unreadable"

    public static func storageKey(householdID: String) -> String {
        "\(storagePrefix).\(householdID)"
    }

    public static func quarantineKey(householdID: String) -> String {
        "\(quarantinePrefix).\(householdID)"
    }

    public enum LoadOutcome: Equatable {
        /// This household has never stored lists: it gets its two defaults.
        case empty
        case loaded(HouseholdListsArchive)
        /// Bytes that cannot be read. They are kept for recovery, and must not
        /// be replaced by a fresh document.
        case unreadable
    }

    /// The bytes of the last lists document this household could not read.
    public static func quarantined(householdID: String, from defaults: UserDefaults = .standard) -> Data? {
        defaults.data(forKey: quarantineKey(householdID: householdID))
    }

    public static func load(householdID: String, from defaults: UserDefaults = .standard) -> LoadOutcome {
        // A previous build may have quarantined a valid version-1 document.
        // Try that copy again before declaring this household empty.
        guard let data = defaults.data(forKey: storageKey(householdID: householdID))
            ?? defaults.data(forKey: quarantineKey(householdID: householdID)) else { return .empty }
        do {
            let archive = try JSONDecoder().decode(HouseholdListsArchive.self, from: data)
            guard archive.householdID == householdID else { throw ListError.invalidArchive("household mismatch") }
            let migrated = try archive.migrated()
            if migrated != archive {
                // Retain the original bytes as a recovery copy before rewriting.
                if defaults.data(forKey: quarantineKey(householdID: householdID)) == nil {
                    defaults.set(data, forKey: quarantineKey(householdID: householdID))
                }
                try save(migrated, to: defaults)
            }
            return .loaded(migrated)
        } catch {
            // Keep the bytes: a decoding slip is not permission to lose a
            // household's lists, and a later build may read them perfectly well.
            defaults.set(data, forKey: quarantineKey(householdID: householdID))
            defaults.removeObject(forKey: storageKey(householdID: householdID))
            return .unreadable
        }
    }

    /// Throws rather than swallowing the error: a save that did not happen must
    /// never be reported as one that did.
    public static func save(_ archive: HouseholdListsArchive, to defaults: UserDefaults = .standard) throws {
        let validated = try archive.validated()
        let data = try JSONEncoder().encode(validated)
        defaults.set(data, forKey: storageKey(householdID: archive.householdID))
    }

    /// Discards a document the household has accepted losing.
    public static func discard(householdID: String, from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: storageKey(householdID: householdID))
        defaults.removeObject(forKey: quarantineKey(householdID: householdID))
    }

    /// The most recent removed set, kept locally and never uploaded.
    public static func undoKey(householdID: String) -> String {
        "helipad.lists.undo.v1.\(householdID)"
    }

    public static func saveUndo(_ batch: ListUndoBatch?, householdID: String, to defaults: UserDefaults = .standard) {
        guard let batch, let data = try? JSONEncoder().encode(batch) else {
            defaults.removeObject(forKey: undoKey(householdID: householdID))
            return
        }
        defaults.set(data, forKey: undoKey(householdID: householdID))
    }

    public static func loadUndo(householdID: String, from defaults: UserDefaults = .standard) -> ListUndoBatch? {
        guard let data = defaults.data(forKey: undoKey(householdID: householdID)) else { return nil }
        return try? JSONDecoder().decode(ListUndoBatch.self, from: data)
    }
}

// MARK: - Undo

/// One batch for the latest destructive action, whatever it removed.
///
/// Uniform on purpose: an item, a section, a set of checked-off rows, or a whole
/// list all reduce to "these records went away", so undo has one shape and one
/// place to be restored from. Kept locally, never uploaded, and restored under
/// fresh identities — an undo must not resurrect an identity the household
/// deleted, nor overwrite a record someone else has since edited.
public struct ListUndoBatch: Codable, Equatable {
    public var label: String
    public var groups: [HouseholdListGroup]
    public var items: [HouseholdListItem]
    public var subtasks: [ListSubtask]
    public var createdAt: Date

    public init(
        label: String,
        groups: [HouseholdListGroup] = [],
        items: [HouseholdListItem] = [],
        subtasks: [ListSubtask] = [],
        createdAt: Date = Date()
    ) {
        self.label = label
        self.groups = groups
        self.items = items
        self.subtasks = subtasks
        self.createdAt = createdAt
    }

    public var isEmpty: Bool {
        groups.isEmpty && items.isEmpty && subtasks.isEmpty
    }
}

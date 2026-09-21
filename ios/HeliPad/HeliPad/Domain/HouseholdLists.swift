import Foundation

// MARK: - Kinds and roles
//
// Lists are undated and have no child, owner, place, or recurrence. They are
// deliberately not `TaskRecord`: a scheduled event needs a date and time, and
// teaching that type to be undated would put list rows into every schedule,
// statistics, reminder and calendar path.

public enum ListKind: String, Codable, CaseIterable, Hashable {
    case todos, groceries

    public var title: String { self == .todos ? "To-dos" : "Groceries" }
    /// Advisory-cleanup inactivity threshold.
    public var reviewDays: Int { self == .todos ? 45 : 14 }
    public var completedTitle: String { self == .todos ? "Completed" : "Purchased" }
    public var remainingTitle: String { self == .todos ? "still to do" : "to pick up" }
    public var capturePrompt: String { self == .todos ? "Add a to-do…" : "Add a grocery item…" }
    public var emptyTitle: String { self == .todos ? "Nothing to do here" : "Nothing to pick up" }
    public var emptyDetail: String { self == .todos ? "Add something below whenever it comes to mind." : "Add what you need below." }
    public var supportsSubtasks: Bool { self == .todos }
}

/// Lists keeps two lists and two only: To-dos and Groceries. They are derived
/// from the household id rather than created, so both phones agree on them
/// without syncing anything, and neither can be deleted or retyped. Sections
/// inside a list are where the household organises actual work.

// MARK: - Ordering

/// Stable ordering ranks. A rank says where a record sits among its siblings;
/// array position never does, and never identifies anything, so two phones that
/// built their arrays differently still agree on order.
public protocol RankedRecord: Identifiable where ID == String {
    var rank: Int { get set }
}

public extension Sequence where Element: RankedRecord {
    /// Sibling order: integer rank, then record id to break ties.
    func inListOrder() -> [Element] {
        sorted { ($0.rank, $0.id) < ($1.rank, $1.id) }
    }
}

// MARK: - Field stamps
//
// A row is not one editable thing. Its wording, its checked state, where it
// sits, and whether its cleanup suggestion was deferred all change
// independently, and two phones must be able to do two of those at once without
// one overwriting the other. Hence a stamp per facet rather than per record.

public struct ListStamps: Codable, Hashable, Equatable {
    /// Text, quantity, note. Also subtask wording.
    public var content: RecordStamp?
    /// Checked / reopened.
    public var completion: RecordStamp?
    /// Which group it belongs to and where it sits in it.
    public var placement: RecordStamp?
    /// Advisory-cleanup snooze.
    public var review: RecordStamp?

    public init(
        content: RecordStamp? = nil,
        completion: RecordStamp? = nil,
        placement: RecordStamp? = nil,
        review: RecordStamp? = nil
    ) {
        self.content = content
        self.completion = completion
        self.placement = placement
        self.review = review
    }

    /// Decoded field by field. A synthesized decoder demands every non-optional
    /// key, so a field added later would make older archives unreadable.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        content = try c.decodeIfPresent(RecordStamp.self, forKey: .content)
        completion = try c.decodeIfPresent(RecordStamp.self, forKey: .completion)
        placement = try c.decodeIfPresent(RecordStamp.self, forKey: .placement)
        review = try c.decodeIfPresent(RecordStamp.self, forKey: .review)
    }

    /// The newest of the four. Used to raise the local Lamport counter so a
    /// future edit always outranks everything this device has seen.
    public var highest: RecordStamp? {
        [content, completion, placement, review].compactMap { $0 }.max()
    }

    public func stamp(for facet: ListFacet) -> RecordStamp? {
        switch facet {
        case .content: return content
        case .completion: return completion
        case .placement: return placement
        case .review: return review
        }
    }

    public mutating func set(_ stamp: RecordStamp, for facet: ListFacet) {
        switch facet {
        case .content: content = stamp
        case .completion: completion = stamp
        case .placement: placement = stamp
        case .review: review = stamp
        }
    }
}

public enum ListFacet: String, Codable, Hashable {
    case content, completion, placement, review
}

// MARK: - Records

public struct HouseholdList: Codable, Equatable, Identifiable, RankedRecord {
    public var id: String
    /// Never changes. It is what decides whether this is the To-dos list or the
    /// Groceries list.
    public var kind: ListKind
    public var name: String
    public var rank: Int
    public var stamps: ListStamps
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        kind: ListKind,
        name: String,
        rank: Int = 0,
        stamps: ListStamps = ListStamps(),
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.rank = rank
        self.stamps = stamps
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        kind = try c.decode(ListKind.self, forKey: .kind)
        name = try c.decode(String.self, forKey: .name)
        rank = try c.decodeIfPresent(Int.self, forKey: .rank) ?? 0
        stamps = try c.decodeIfPresent(ListStamps.self, forKey: .stamps) ?? ListStamps()
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }
}

public struct HouseholdListGroup: Codable, Equatable, Identifiable, RankedRecord {
    public var id: String
    public var listID: String
    public var name: String
    public var rank: Int
    public var stamps: ListStamps

    public init(
        id: String,
        listID: String,
        name: String,
        rank: Int = 0,
        stamps: ListStamps = ListStamps()
    ) {
        self.id = id
        self.listID = listID
        self.name = name
        self.rank = rank
        self.stamps = stamps
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        listID = try c.decode(String.self, forKey: .listID)
        name = try c.decode(String.self, forKey: .name)
        rank = try c.decodeIfPresent(Int.self, forKey: .rank) ?? 0
        stamps = try c.decodeIfPresent(ListStamps.self, forKey: .stamps) ?? ListStamps()
    }
}

/// A step inside a to-do. Flat rather than nested inside its item so two people
/// ticking different steps — or one editing a step while the other edits the
/// item's wording — merge instead of colliding on the whole item.
public struct ListSubtask: Codable, Equatable, Identifiable, RankedRecord {
    public var id: String
    public var itemID: String
    public var text: String
    public var completedAt: Date?
    public var rank: Int
    public var stamps: ListStamps

    public var isCompleted: Bool { completedAt != nil }

    public init(
        id: String,
        itemID: String,
        text: String,
        completedAt: Date? = nil,
        rank: Int = 0,
        stamps: ListStamps = ListStamps()
    ) {
        self.id = id
        self.itemID = itemID
        self.text = text
        self.completedAt = completedAt
        self.rank = rank
        self.stamps = stamps
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        itemID = try c.decode(String.self, forKey: .itemID)
        text = try c.decode(String.self, forKey: .text)
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
        rank = try c.decodeIfPresent(Int.self, forKey: .rank) ?? 0
        stamps = try c.decodeIfPresent(ListStamps.self, forKey: .stamps) ?? ListStamps()
    }
}

public struct HouseholdListItem: Codable, Equatable, Identifiable, RankedRecord {
    public var id: String
    public var listID: String
    public var groupID: String
    public var text: String
    /// Groceries only: "2 cartons". Never parsed, never summed.
    public var quantity: String
    public var note: String
    public var completedAt: Date?
    /// Order within its group.
    public var rank: Int
    public var stamps: ListStamps
    public var createdAt: Date
    public var updatedAt: Date
    /// Last *meaningful* change — wording, quantity, note, steps, or checking.
    /// Placement and review snoozing deliberately do not move it, so tidying a
    /// list cannot make an untouched item look freshly handled.
    public var activityAt: Date
    /// Set by "Keep for now"; suppresses the suggestion household-wide.
    public var reviewAfter: Date?

    public var isCompleted: Bool { completedAt != nil }

    public init(
        id: String,
        listID: String,
        groupID: String,
        text: String,
        quantity: String = "",
        note: String = "",
        completedAt: Date? = nil,
        rank: Int = 0,
        stamps: ListStamps = ListStamps(),
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        activityAt: Date? = nil,
        reviewAfter: Date? = nil
    ) {
        self.id = id
        self.listID = listID
        self.groupID = groupID
        self.text = text
        self.quantity = quantity
        self.note = note
        self.completedAt = completedAt
        self.rank = rank
        self.stamps = stamps
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.activityAt = activityAt ?? createdAt
        self.reviewAfter = reviewAfter
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        listID = try c.decode(String.self, forKey: .listID)
        groupID = try c.decode(String.self, forKey: .groupID)
        text = try c.decode(String.self, forKey: .text)
        quantity = try c.decodeIfPresent(String.self, forKey: .quantity) ?? ""
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
        rank = try c.decodeIfPresent(Int.self, forKey: .rank) ?? 0
        stamps = try c.decodeIfPresent(ListStamps.self, forKey: .stamps) ?? ListStamps()
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        activityAt = try c.decodeIfPresent(Date.self, forKey: .activityAt) ?? createdAt
        reviewAfter = try c.decodeIfPresent(Date.self, forKey: .reviewAfter)
    }
}

// MARK: - Deletion records
//
// These carry no `deletedAt` on purpose. An ordinary household tombstone is
// swept after 30 days, which is fine for an event that can be re-created but
// not for a list row: a device that has been offline longer than the sweep
// would resurrect something the household deliberately cleared. Deletion wins
// for the deleted identity, however long it has been.

public struct ListDeletion: Codable, Equatable, Hashable, Identifiable {
    public enum Kind: String, Codable, Hashable {
        case list, group, item, subtask
    }

    public var id: String
    public var kind: Kind
    public var stamp: RecordStamp

    public init(id: String, kind: Kind, stamp: RecordStamp) {
        self.id = id
        self.kind = kind
        self.stamp = stamp
    }

    /// Keeps ids from different collections apart.
    public var key: String { "\(kind.rawValue):\(id)" }
}

// MARK: - Archive

/// Everything the household keeps in Lists, in one versioned document.
///
/// Separate from `PersistedState` on purpose: that snapshot is decoded by
/// whichever build is installed, and an older build that has never heard of a
/// list field would drop it on its next save. A separate file is either read
/// whole or left alone.
public struct HouseholdListsArchive: Codable, Equatable {
    public static let currentVersion = 2

    public var version: Int
    /// Which household these lists belong to. A mismatch means they are not
    /// this household's lists and must never be uploaded into it.
    public var householdID: String
    /// Which cloud connection they were last reconciled with.
    public var connectionFingerprint: String
    public var lists: [HouseholdList]
    public var groups: [HouseholdListGroup]
    public var items: [HouseholdListItem]
    public var subtasks: [ListSubtask]
    public var deletions: [ListDeletion]
    /// Remote revision this archive was last reconciled against.
    public var remoteRevision: String?
    /// Increments on every local list change. Never touches the household's
    /// schedule revision.
    public var localRevision: Int
    public var uploadedRevision: Int

    /// Credentials and per-device bookkeeping never travel with shared content.
    public func cloudPayload() -> HouseholdListsArchive {
        var copy = self
        copy.connectionFingerprint = ""
        copy.remoteRevision = nil
        copy.localRevision = 0
        copy.uploadedRevision = 0
        return copy
    }

    public init(
        version: Int = HouseholdListsArchive.currentVersion,
        householdID: String,
        connectionFingerprint: String = "",
        lists: [HouseholdList] = [],
        groups: [HouseholdListGroup] = [],
        items: [HouseholdListItem] = [],
        subtasks: [ListSubtask] = [],
        deletions: [ListDeletion] = [],
        remoteRevision: String? = nil,
        localRevision: Int = 0,
        uploadedRevision: Int = 0
    ) {
        self.version = version
        self.householdID = householdID
        self.connectionFingerprint = connectionFingerprint
        self.lists = lists
        self.groups = groups
        self.items = items
        self.subtasks = subtasks
        self.deletions = deletions
        self.remoteRevision = remoteRevision
        self.localRevision = localRevision
        self.uploadedRevision = uploadedRevision
    }

    /// Field by field, so a document written by an earlier build stays readable.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        householdID = try c.decodeIfPresent(String.self, forKey: .householdID) ?? ""
        connectionFingerprint = try c.decodeIfPresent(String.self, forKey: .connectionFingerprint) ?? ""
        lists = try c.decodeIfPresent([HouseholdList].self, forKey: .lists) ?? []
        groups = try c.decodeIfPresent([HouseholdListGroup].self, forKey: .groups) ?? []
        items = try c.decodeIfPresent([HouseholdListItem].self, forKey: .items) ?? []
        subtasks = try c.decodeIfPresent([ListSubtask].self, forKey: .subtasks) ?? []
        deletions = try c.decodeIfPresent([ListDeletion].self, forKey: .deletions) ?? []
        remoteRevision = try c.decodeIfPresent(String.self, forKey: .remoteRevision)
        localRevision = try c.decodeIfPresent(Int.self, forKey: .localRevision) ?? 0
        uploadedRevision = try c.decodeIfPresent(Int.self, forKey: .uploadedRevision) ?? 0
    }
}

// MARK: - Limits

public struct ListItemDraft {
    public var id: String
    public var listID: String
    public var groupID: String
    public var text: String
    public var quantity: String
    public init(id: String, listID: String, groupID: String, text: String, quantity: String = "") {
        self.id = id; self.listID = listID; self.groupID = groupID; self.text = text; self.quantity = quantity
    }
}

public enum ListLimits {
    public static let listName = 100
    public static let groupName = 60
    public static let itemText = 200
    public static let quantity = 80
    public static let note = 2000
    public static let subtaskText = 200
    public static let groupsPerList = 30
    public static let itemsPerList = 2000
    public static let subtasksPerItem = 20
}

public enum ListError: LocalizedError, Equatable {
    case invalidArchive(String)
    case unsupportedVersion(Int)
    case notFound(String)
    case rejected(String)

    public var errorDescription: String? {
        switch self {
        case .invalidArchive(let detail): return "This household's lists are not readable: \(detail)"
        case .unsupportedVersion(let version): return "These lists were written by a newer version (format \(version)). Update HeliPad to read them."
        case .notFound(let what): return "That \(what) is no longer on this list."
        case .rejected(let reason): return reason
        }
    }
}

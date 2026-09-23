import Foundation
import Combine
import CryptoKit

// MARK: - Sync state

/// What the household should be told about these lists, in words.
public enum ListsSyncState: Equatable {
    /// No cloud connection, sync switched off, or setup incomplete.
    case onDevice
    /// Local changes exist that the household has not received yet.
    case waiting
    case upToDate
    case failed(String)

    public var label: String {
        switch self {
        case .onDevice: return "On this device"
        case .waiting: return "Waiting to sync"
        case .upToDate: return "Up to date"
        case .failed: return "Not syncing"
        }
    }

    public var detail: String? {
        switch self {
        case .onDevice: return "Not shared with the household"
        case .waiting: return "Saved here; sending when there is a connection"
        case .upToDate: return nil
        case .failed(let message): return message
        }
    }
}

// MARK: - Host

/// What the lists store needs from the app that owns it: identity, the logical
/// clock, and where lists are written. Kept narrow — and internal — so the store
/// can be built in a test without an `AppStore`, and so the bridge does not
/// become public API.
protocol HouseholdListsHost: AnyObject {
    /// Next value of the shared Lamport clock. Using the same clock as the
    /// household means a list edit can never look older than a schedule edit
    /// this phone already made.
    func listsNextStamp() -> RecordStamp
    /// Raises the clock above a stamp seen from the other phone.
    func listsObserve(_ stamp: RecordStamp)
    var listsHouseholdID: String { get }
    var listsPersistenceDefaults: UserDefaults { get }
    var listsPersistenceEnabled: Bool { get }
    /// Non-nil only when a connection is configured and sync is switched on.
    func listsCloudContext() -> ListsCloudContext?
}

struct ListsCloudContext: Equatable {
    var householdID: String
    var connection: String
    var fingerprint: String {
        SHA256.hash(data: Data(connection.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    init(householdID: String, connection: String) {
        self.householdID = householdID
        self.connection = connection
    }
}

// MARK: - Store

/// Everything the household can do to a list, in one place.
///
/// Owned by `AppStore`, but with its own document, its own revision and its own
/// sync channel. Checking off a grocery item bumps a list revision and writes
/// one small file: it does not reconcile the schedule, re-stamp the household,
/// rebuild reminders, rehash events, or talk to a calendar.
public final class HouseholdListsStore: ObservableObject {

    @Published public private(set) var archive: HouseholdListsArchive
    /// A save that did not happen is visible here rather than reported as done.
    @Published public private(set) var saveError: String?
    /// A document that could not be read is waiting for the household's answer.
    @Published public private(set) var recoveryNeeded = false
    @Published public private(set) var syncState: ListsSyncState = .onDevice
    @Published public private(set) var isSyncing = false
    @Published public private(set) var pendingUndo: ListUndoBatch?
    @Published public private(set) var lastSyncedAt: Date?

    weak var host: HouseholdListsHost?
    private let cloud: HouseholdListsCloudService
    private var syncTask: Task<Void, Never>?
    private var syncDelay: TimeInterval = AppStore.liveSyncInterval
    /// Guards against a response that belongs to a household we have left.
    private var sessionToken = UUID()

    public init(
        archive: HouseholdListsArchive = HouseholdListsArchive(householdID: ""),
        cloud: HouseholdListsCloudService = NeonListsCloudService()
    ) {
        self.archive = archive
        self.cloud = cloud
        self.syncState = .onDevice
    }

    // MARK: - Lifecycle

    /// Points the store at the app that owns it and loads this household's
    /// document. Called from `AppStore.restore` and whenever the household
    /// changes, so a phone that switches household never shows, or uploads, the
    /// lists of the one it left.
    func attach(to host: HouseholdListsHost) {
        self.host = host
        reload()
    }

    /// Loads the current household's document, or starts it with its two
    /// defaults. Never creates a document for a household we cannot identify.
    public func reload() {
        guard let host else { return }
        let householdID = host.listsHouseholdID
        sessionToken = UUID()
        pendingUndo = nil
        saveError = nil
        lastSyncedAt = nil
        guard !householdID.isEmpty else {
            archive = HouseholdListsArchive(householdID: "")
            syncState = .onDevice
            return
        }

        switch HouseholdListsPersistence.load(householdID: householdID, from: host.listsPersistenceDefaults) {
        case .empty:
            recoveryNeeded = false
            archive = HouseholdListsDefaults.archive(
                householdID: householdID,
                connectionFingerprint: cloudContext()?.fingerprint ?? ""
            )
            persist()
            refreshSyncState()
        case .loaded(let loaded):
            recoveryNeeded = false
            // A document from the other phone carries stamps; raise our clock
            // above them so this phone's next edit still sorts newest.
            observe(loaded)
            archive = loaded
            // Earlier builds accidentally stored the connection URI here.
            // Migrate it locally and republish a payload without credentials.
            if loaded.connectionFingerprint.contains("://") {
                archive.connectionFingerprint = ListsCloudContext(householdID: householdID, connection: loaded.connectionFingerprint).fingerprint
                archive.localRevision += 1
                persist()
            }
            pendingUndo = HouseholdListsPersistence.loadUndo(
                householdID: householdID, from: host.listsPersistenceDefaults
            )
            refreshSyncState()
        case .unreadable:
            // Keep the bytes, keep working, and let the household decide.
            recoveryNeeded = true
            archive = HouseholdListsDefaults.archive(
                householdID: householdID,
                connectionFingerprint: cloudContext()?.fingerprint ?? ""
            )
            syncState = .onDevice
        }
    }

    /// The household has answered about an unreadable document. Either way the
    /// store starts writing again; the difference is whether the old bytes are
    /// kept for a later build to read.
    public func resolveRecovery(keepingCopy: Bool) {
        guard let host else { return }
        if !keepingCopy {
            HouseholdListsPersistence.discard(householdID: host.listsHouseholdID, from: host.listsPersistenceDefaults)
        }
        recoveryNeeded = false
        persist()
    }

    public var hasRecoverableCopy: Bool {
        guard let host else { return false }
        return HouseholdListsPersistence.quarantined(
            householdID: host.listsHouseholdID, from: host.listsPersistenceDefaults
        ) != nil
    }

    // MARK: - Persistence

    private func persist() {
        guard !recoveryNeeded, let host, host.listsPersistenceEnabled, !archive.householdID.isEmpty else { return }
        do {
            try HouseholdListsPersistence.save(archive, to: host.listsPersistenceDefaults)
            saveError = nil
        } catch {
            saveError = "These list changes were not saved on this device. \(error.localizedDescription)"
        }
    }

    private func persistUndo() {
        guard let host else { return }
        HouseholdListsPersistence.saveUndo(pendingUndo, householdID: host.listsHouseholdID, to: host.listsPersistenceDefaults)
    }

    // MARK: - Stamps

    private func stamp() -> RecordStamp {
        host?.listsNextStamp() ?? RecordStamp(counter: archive.localRevision, deviceID: "local")
    }

    /// A new record is stamped on every facet, so a later edit by either phone
    /// always has something to be compared against.
    private func birthStamps() -> ListStamps {
        let now = stamp()
        return ListStamps(content: now, completion: now, placement: now, review: now)
    }

    private func observe(_ archive: HouseholdListsArchive) {
        var highest: RecordStamp?
        func note(_ candidate: RecordStamp?) {
            guard let candidate else { return }
            if let current = highest { highest = max(current, candidate) } else { highest = candidate }
        }
        archive.lists.forEach { note($0.stamps.highest) }
        archive.groups.forEach { note($0.stamps.highest) }
        archive.items.forEach { note($0.stamps.highest) }
        archive.subtasks.forEach { note($0.stamps.highest) }
        archive.deletions.forEach { note($0.stamp) }
        if let highest { host?.listsObserve(highest) }
    }

    // MARK: - Mutation funnel

    /// One place where a change is validated, revised, saved and published.
    @discardableResult
    private func mutate(_ body: (inout HouseholdListsArchive) throws -> Void) -> Bool {
        var next = archive
        do {
            try body(&next)
            next.ensureDefaults()
            next.ensureGeneralGroups()
            next.normalizeRanks()
            _ = try next.validated()
        } catch {
            saveError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
        guard next != archive else { return true }
        next.localRevision += 1
        archive = next
        persist()
        refreshSyncState()
        // An edit here usually starts an exchange: come back to the short gap so
        // the other phone's answer is not sitting upstream for half a minute.
        quicken()
        return true
    }

    private func refreshSyncState() {
        guard cloudContext() != nil else { syncState = .onDevice; return }
        // An edit must not hide the underlying failure before a retry succeeds.
        if case .failed = syncState { return }
        syncState = archive.localRevision > archive.uploadedRevision ? .waiting : .upToDate
    }

    private func cloudContext() -> ListsCloudContext? {
        guard let host, host.listsPersistenceEnabled else { return nil }
        return host.listsCloudContext()
    }

    // MARK: - Reading

    public func lists(_ kind: ListKind) -> [HouseholdList] { archive.lists(of: kind) }
    public func defaultList(_ kind: ListKind) -> HouseholdList? { archive.defaultList(of: kind) }
    public func list(_ id: String) -> HouseholdList? { archive.list(id) }
    public func groups(of listID: String) -> [HouseholdListGroup] { archive.groups(of: listID) }
    public func generalGroup(of listID: String) -> HouseholdListGroup? { archive.generalGroup(of: listID) }
    /// The one section that cannot be renamed away or removed.
    public func isGeneral(_ group: HouseholdListGroup) -> Bool { archive.isGeneral(group) }
    public func items(of listID: String, inGroup groupID: String) -> [HouseholdListItem] {
        archive.items(of: listID, inGroup: groupID)
    }
    public func activeItems(of listID: String) -> [HouseholdListItem] { archive.activeItems(of: listID) }
    public func completedItems(of listID: String) -> [HouseholdListItem] { archive.completedItems(of: listID) }
    public func subtasks(of itemID: String) -> [ListSubtask] { archive.subtasks(of: itemID) }
    public func item(_ id: String) -> HouseholdListItem? { archive.items.first { $0.id == id } }
    public func remainingCount(of listID: String) -> Int { archive.remainingCount(of: listID) }
    public func duplicate(of listID: String, matching text: String) -> HouseholdListItem? {
        archive.duplicate(of: listID, matching: text)
    }
    public func reviewCandidates(of listID: String, kind: ListKind, now: Date = Date()) -> [HouseholdListItem] {
        archive.reviewCandidates(of: listID, kind: kind, now: now)
    }
    // MARK: - Sections

    @discardableResult
    public func addGroup(listID: String, name: String) -> String? {
        let trimmed = ListText.trimmed(name)
        guard !trimmed.isEmpty, trimmed.count <= ListLimits.groupName else {
            saveError = "Give the section a name of \(ListLimits.groupName) characters or fewer."
            return nil
        }
        guard archive.list(listID) != nil,
              archive.groups(of: listID).count < ListLimits.groupsPerList else {
            saveError = "This list has as many sections as it can hold."
            return nil
        }
        let id = UUID().uuidString
        let rank = archive.groups(of: listID).count
        let stamps = birthStamps()
        let created = mutate { archive in
            archive.groups.append(HouseholdListGroup(id: id, listID: listID, name: trimmed, rank: rank, stamps: stamps))
        }
        return created ? id : nil
    }

    @discardableResult
    public func renameGroup(id: String, to name: String) -> Bool {
        let trimmed = ListText.trimmed(name)
        guard !trimmed.isEmpty, trimmed.count <= ListLimits.groupName else { return false }
        let now = stamp()
        return mutate { archive in
            guard let index = archive.groups.firstIndex(where: { $0.id == id }) else { throw ListError.notFound("section") }
            archive.groups[index].name = trimmed
            archive.groups[index].stamps.content = now
        }
    }

    /// Moves a section one place up or down.
    public func moveGroup(id: String, by offset: Int) {
        guard let group = archive.groups.first(where: { $0.id == id }),
              let position = archive.groups(of: group.listID).firstIndex(where: { $0.id == id }) else { return }
        moveGroup(id: id, toIndex: position + offset)
    }

    /// Moves a section to a position in its list. The reorder arrows land here,
    /// and one command for both directions means the ranks are assigned the same
    /// way however the section moved.
    public func moveGroup(id: String, toIndex: Int) {
        guard let group = archive.groups.first(where: { $0.id == id }) else { return }
        var rows = archive.groups(of: group.listID)
        guard let position = rows.firstIndex(where: { $0.id == id }) else { return }
        let target = min(max(0, toIndex), rows.count - 1)
        guard target != position else { return }
        let now = stamp()
        rows.remove(at: position)
        rows.insert(group, at: target)
        mutate { archive in
            for (index, row) in rows.enumerated() {
                guard let slot = archive.groups.firstIndex(where: { $0.id == row.id }) else { continue }
                archive.groups[slot].rank = index
                archive.groups[slot].stamps.placement = now
            }
        }
    }

    /// General cannot be removed, and no other section takes its rows with it:
    /// they move into General, wording and order intact.
    public func deleteGroup(id: String) {
        guard let group = archive.groups.first(where: { $0.id == id }),
              archive.groups(of: group.listID).count > 1,
              !archive.isGeneral(group),
              let general = archive.generalGroup(of: group.listID) else { return }
        let moving = archive.items(of: group.listID, inGroup: id)
        let now = stamp()
        let removed = mutate { archive in
            archive.recordDeletion(id: id, kind: .group, stamp: now)
            for index in archive.items.indices where archive.items[index].groupID == id {
                archive.items[index].groupID = general.id
                archive.items[index].stamps.placement = now
            }
            archive.applyDeletions()
        }
        guard removed else { return }
        pendingUndo = ListUndoBatch(label: "Removed \(group.name)", groups: [group], items: moving)
        persistUndo()
    }

    // MARK: - Items

    @discardableResult
    public func addItem(
        listID: String,
        groupID: String,
        text: String,
        quantity: String = "",
        note: String = ""
    ) -> String? {
        let trimmed = ListText.trimmed(text)
        guard !trimmed.isEmpty, trimmed.count <= ListLimits.itemText else {
            saveError = "Give the item some text of \(ListLimits.itemText) characters or fewer."
            return nil
        }
        guard let list = archive.list(listID) else { return nil }
        let target = archive.groups(of: listID).first { $0.id == groupID } ?? archive.generalGroup(of: listID)
        guard let group = target else { return nil }
        let id = UUID().uuidString
        let rank = archive.items(of: listID, inGroup: group.id).count
        let stamps = birthStamps()
        let now = Date()
        let created = mutate { archive in
            archive.items.append(HouseholdListItem(
                id: id, listID: listID, groupID: group.id, text: trimmed,
                quantity: list.kind == .groceries ? ListText.trimmed(quantity) : "",
                note: ListText.trimmed(note),
                rank: rank, stamps: stamps, createdAt: now, updatedAt: now, activityAt: now
            ))
        }
        return created ? id : nil
    }

    /// One durable, retry-safe batch for assistant-confirmed additions. Uses the
    /// same validation, stamps, persistence and pending-sync path as manual edits.
    public func addItems(_ drafts: [ListItemDraft]) throws -> [String] {
        guard !recoveryNeeded, host?.listsPersistenceEnabled == true,
              !drafts.isEmpty, drafts.count <= 20,
              Set(drafts.map(\.id)).count == drafts.count else {
            throw ListError.rejected("Lists are unavailable or the batch is invalid.")
        }
        for draft in drafts {
            guard list(draft.listID) != nil,
                  groups(of: draft.listID).contains(where: { $0.id == draft.groupID }),
                  !archive.deletions.contains(where: { $0.kind == .item && $0.id == draft.id }) else {
                throw ListError.notFound("destination section or item")
            }
            if let existing = item(draft.id), existing.listID != draft.listID {
                throw ListError.rejected("This item belongs to another list.")
            }
        }
        let previous = archive
        let additions = drafts.filter { item($0.id) == nil }
        let births = Dictionary(uniqueKeysWithValues: additions.map { ($0.id, birthStamps()) })
        let now = Date()
        let saved = mutate { next in
            for draft in additions {
                next.items.append(HouseholdListItem(
                    id: draft.id, listID: draft.listID, groupID: draft.groupID,
                    text: ListText.trimmed(draft.text), quantity: ListText.trimmed(draft.quantity),
                    rank: next.items(of: draft.listID, inGroup: draft.groupID).count,
                    stamps: births[draft.id]!, createdAt: now, updatedAt: now, activityAt: now
                ))
            }
        }
        guard saved else { throw ListError.rejected(saveError ?? "Could not add these items.") }
        persist()
        if let saveError {
            archive = previous
            refreshSyncState()
            throw ListError.rejected(saveError)
        }
        return drafts.map(\.id)
    }

    /// Content and placement in one call, as the detail editor commits them.
    @discardableResult
    public func updateItem(
        id: String,
        text: String,
        quantity: String,
        note: String,
        groupID: String,
        subtaskTexts: [String: String]? = nil
    ) -> Bool {
        let trimmed = ListText.trimmed(text)
        guard let existing = item(id), !trimmed.isEmpty, trimmed.count <= ListLimits.itemText,
              quantity.count <= ListLimits.quantity, note.count <= ListLimits.note else { return false }
        let content = stamp()
        let placement = stamp()
        let movedContent = trimmed != existing.text
            || ListText.trimmed(quantity) != existing.quantity
            || ListText.trimmed(note) != existing.note
        let movedPlacement = groupID != existing.groupID
        return mutate { archive in
            guard let index = archive.items.firstIndex(where: { $0.id == id }) else { throw ListError.notFound("item") }
            archive.items[index].text = trimmed
            archive.items[index].quantity = ListText.trimmed(quantity)
            archive.items[index].note = ListText.trimmed(note)
            // Each stamp is taken only for the part that actually changed. The
            // editor saves every field on close, so stamping both regardless
            // let a note edit on one phone undo a section move made on the
            // other — the untouched placement carried the newer stamp.
            if movedPlacement, archive.groups(of: existing.listID).contains(where: { $0.id == groupID }) {
                archive.items[index].groupID = groupID
                archive.items[index].rank = archive.items(of: existing.listID, inGroup: groupID).count
                archive.items[index].stamps.placement = placement
            }
            if movedContent {
                archive.items[index].stamps.content = content
            }
            archive.items[index].updatedAt = Date()
            // Only wording, quantity, note or steps count as activity. Moving a
            // row between sections is tidying, not handling it, so it must not
            // restart the cleanup clock or clear a snooze.
            if movedContent {
                archive.items[index].activityAt = Date()
            }
            if let subtaskTexts {
                for slot in archive.subtasks.indices where archive.subtasks[slot].itemID == id {
                    guard let next = subtaskTexts[archive.subtasks[slot].id] else { continue }
                    let value = ListText.trimmed(next)
                    guard !value.isEmpty, value.count <= ListLimits.subtaskText else { continue }
                    if value != archive.subtasks[slot].text {
                        archive.subtasks[slot].text = value
                        archive.subtasks[slot].stamps.content = content
                        archive.items[index].activityAt = Date()
                    }
                }
            }
        }
    }

    /// Explicit state, never a toggle, so a replayed command cannot flip it back.
    public func setCompleted(id: String, to completed: Bool) {
        guard let existing = item(id), existing.isCompleted != completed else { return }
        let now = stamp()
        mutate { archive in
            guard let index = archive.items.firstIndex(where: { $0.id == id }) else { throw ListError.notFound("item") }
            archive.items[index].completedAt = completed ? Date() : nil
            archive.items[index].stamps.completion = now
            archive.items[index].updatedAt = Date()
            // Checking and reopening are both meaningful: reopening restarts the
            // cleanup clock, checking stops it.
            archive.items[index].activityAt = Date()
            archive.items[index].reviewAfter = nil
        }
    }

    public func moveItem(id: String, toGroup groupID: String) {
        guard let existing = item(id), existing.groupID != groupID,
              archive.groups(of: existing.listID).contains(where: { $0.id == groupID }) else { return }
        let now = stamp()
        mutate { archive in
            guard let index = archive.items.firstIndex(where: { $0.id == id }) else { throw ListError.notFound("item") }
            archive.items[index].groupID = groupID
            archive.items[index].rank = archive.items(of: existing.listID, inGroup: groupID).count
            archive.items[index].stamps.placement = now
            archive.items[index].updatedAt = Date()
        }
    }

    public func moveItem(id: String, by offset: Int) {
        guard let existing = item(id) else { return }
        let ordered = archive.items(of: existing.listID, inGroup: existing.groupID)
        guard let position = ordered.firstIndex(where: { $0.id == id }) else { return }
        let destination = position + offset
        guard ordered.indices.contains(destination) else { return }
        let now = stamp()
        mutate { archive in
            var rows = archive.items(of: existing.listID, inGroup: existing.groupID)
            rows.swapAt(position, destination)
            for (index, row) in rows.enumerated() {
                guard let slot = archive.items.firstIndex(where: { $0.id == row.id }) else { continue }
                archive.items[slot].rank = index
                archive.items[slot].stamps.placement = now
            }
        }
    }

    public func deleteItem(id: String) {
        guard let existing = item(id) else { return }
        let steps = archive.subtasks(of: id)
        let now = stamp()
        let removed = mutate { archive in
            archive.recordDeletion(id: id, kind: .item, stamp: now)
            archive.applyDeletions()
        }
        guard removed else { return }
        pendingUndo = ListUndoBatch(label: "Removed \(existing.text)", items: [existing], subtasks: steps)
        persistUndo()
    }

    /// Clears exactly the rows that are checked off now. A row another phone
    /// reopens, or adds, while this is in flight is left alone.
    public func clearCompleted(listID: String) {
        let targeted = archive.completedItems(of: listID)
        guard !targeted.isEmpty else { return }
        let ids = Set(targeted.map(\.id))
        let steps = archive.subtasks.filter { ids.contains($0.itemID) }
        let now = stamp()
        let cleared = mutate { archive in
            for id in ids {
                // Only if it is still checked off: a reopen is somebody's work.
                guard archive.items.first(where: { $0.id == id })?.isCompleted == true else { continue }
                archive.recordDeletion(id: id, kind: .item, stamp: now)
            }
            archive.applyDeletions()
        }
        guard cleared else { return }
        let label = targeted.count == 1 ? "Removed \(targeted[0].text)" : "Removed \(targeted.count) items"
        pendingUndo = ListUndoBatch(label: label, items: targeted, subtasks: steps)
        persistUndo()
    }

    /// Suppresses this item's cleanup suggestion for the whole household.
    public func keep(id: String) {
        guard item(id) != nil else { return }
        let now = stamp()
        mutate { archive in
            guard let index = archive.items.firstIndex(where: { $0.id == id }) else { throw ListError.notFound("item") }
            archive.items[index].reviewAfter = Date().addingTimeInterval(30 * 86_400)
            archive.items[index].stamps.review = now
        }
    }

    // MARK: - Subtasks

    @discardableResult
    public func addSubtask(itemID: String, text: String) -> String? {
        let trimmed = ListText.trimmed(text)
        guard let parent = item(itemID), !trimmed.isEmpty, trimmed.count <= ListLimits.subtaskText else { return nil }
        guard archive.list(parent.listID)?.kind.supportsSubtasks == true else { return nil }
        guard archive.subtasks(of: itemID).count < ListLimits.subtasksPerItem else {
            saveError = "This item has as many steps as it can hold."
            return nil
        }
        let id = UUID().uuidString
        let rank = archive.subtasks(of: itemID).count
        let stamps = birthStamps()
        let content = stamp()
        let created = mutate { archive in
            archive.subtasks.append(ListSubtask(id: id, itemID: itemID, text: trimmed, rank: rank, stamps: stamps))
            if let index = archive.items.firstIndex(where: { $0.id == itemID }) {
                archive.items[index].activityAt = Date()
                archive.items[index].stamps.content = content
            }
        }
        return created ? id : nil
    }

    public func setSubtaskCompleted(id: String, to completed: Bool) {
        guard let step = archive.subtasks.first(where: { $0.id == id }), step.isCompleted != completed else { return }
        let now = stamp()
        mutate { archive in
            guard let index = archive.subtasks.firstIndex(where: { $0.id == id }) else { throw ListError.notFound("step") }
            archive.subtasks[index].completedAt = completed ? Date() : nil
            archive.subtasks[index].stamps.completion = now
            // A step is not the item: ticking every step never checks the parent.
        }
    }

    public func deleteSubtask(id: String) {
        guard let step = archive.subtasks.first(where: { $0.id == id }) else { return }
        let now = stamp()
        mutate { archive in
            archive.recordDeletion(id: id, kind: .subtask, stamp: now)
            archive.applyDeletions()
        }
    }

    public func moveSubtask(id: String, by offset: Int) {
        guard let step = archive.subtasks.first(where: { $0.id == id }) else { return }
        let ordered = archive.subtasks(of: step.itemID)
        guard let position = ordered.firstIndex(where: { $0.id == id }) else { return }
        let destination = position + offset
        guard ordered.indices.contains(destination) else { return }
        let now = stamp()
        mutate { archive in
            var rows = archive.subtasks(of: step.itemID)
            rows.swapAt(position, destination)
            for (index, row) in rows.enumerated() {
                guard let slot = archive.subtasks.firstIndex(where: { $0.id == row.id }) else { continue }
                archive.subtasks[slot].rank = index
                archive.subtasks[slot].stamps.placement = now
            }
        }
    }

    // MARK: - Undo

    public func dismissUndo() {
        pendingUndo = nil
        persistUndo()
    }

    /// Puts back what the last destructive action removed, under fresh
    /// identities. The deletion records stay, so undoing a removal can never
    /// resurrect an identity the household deleted, and a record the other phone
    /// has edited since is left as the household has it.
    public func undo() {
        guard let batch = pendingUndo, !batch.isEmpty else { return }
        let content = stamp()
        let placement = stamp()
        let now = Date()

        let restored = mutate { archive in
            // Lists are fixed, so a restored section or row only has to find its
            // list, never a replacement one.
            var groupMap: [String: String] = [:]
            for group in batch.groups {
                guard archive.list(group.listID) != nil else { continue }
                let id = UUID().uuidString
                groupMap[group.id] = id
                var copy = group
                copy.id = id
                copy.stamps = ListStamps(content: content, placement: placement)
                archive.groups.append(copy)
            }

            var itemMap: [String: String] = [:]
            for item in batch.items {
                let listID = item.listID
                guard archive.list(listID) != nil else { continue }
                let groupID = groupMap[item.groupID]
                    ?? (archive.groups(of: listID).contains { $0.id == item.groupID } ? item.groupID : nil)
                    ?? archive.generalGroup(of: listID)?.id
                guard let groupID else { continue }
                let id = UUID().uuidString
                itemMap[item.id] = id
                var copy = item
                copy.id = id
                copy.listID = listID
                copy.groupID = groupID
                copy.stamps = ListStamps(
                    content: content,
                    completion: content,
                    placement: placement,
                    review: content
                )
                copy.createdAt = now
                copy.updatedAt = now
                copy.activityAt = now
                copy.reviewAfter = nil
                copy.rank = archive.items(of: listID, inGroup: groupID).count
                archive.items.append(copy)
            }

            for step in batch.subtasks {
                guard let itemID = itemMap[step.itemID] else { continue }
                var copy = step
                copy.id = UUID().uuidString
                copy.itemID = itemID
                copy.stamps = ListStamps(content: content, completion: content, placement: placement)
                copy.rank = archive.subtasks(of: itemID).count
                archive.subtasks.append(copy)
            }
        }

        if restored {
            pendingUndo = nil
            persistUndo()
        }
    }

    // MARK: - Sync

    /// One pull/merge/push cycle. Safe to call from a poll: it asks only for the
    /// revision unless something actually moved.
    @MainActor
    public func sync(localChanges: Bool = false) async {
        guard !isSyncing, !recoveryNeeded else { return }
        guard let context = cloudContext() else { syncState = .onDevice; return }
        guard let host else { return }
        let token = sessionToken
        func isCurrent() -> Bool {
            token == sessionToken && host.listsHouseholdID == context.householdID && cloudContext() == context
        }
        isSyncing = true
        defer { isSyncing = false }

        do {
            var pending = localChanges || archive.localRevision > archive.uploadedRevision
            if !pending {
                let revision = try await cloud.fetchListsRevision(
                    householdId: context.householdID, rawConnectionString: context.connection
                )
                guard isCurrent() else { return }
                // Recheck pending state after the await: a checkbox may have
                // changed while the revision request was in flight.
                if revision == archive.remoteRevision && archive.localRevision == archive.uploadedRevision {
                    syncState = .upToDate
                    lastSyncedAt = Date()
                    noteQuietTick()
                    return
                }
            }

            // Pull, merge, then push if anything here is still unpublished.
            // Bounded: two phones saving at once resolve on the first retry.
            var attempts = 0
            while attempts < Self.conflictAttempts {
                attempts += 1
                let remote = try await cloud.pullLists(
                    householdId: context.householdID, rawConnectionString: context.connection
                )
                guard isCurrent() else { return }

                var merged = archive
                var revision: String? = nil
                if let remote {
                    var incoming = remote.archive
                    // A document belonging to another household is not ours to merge.
                    guard incoming.householdID.isEmpty || incoming.householdID == context.householdID else {
                        throw ListError.rejected("The stored list document belongs to a different household.")
                    }
                    incoming.householdID = context.householdID
                    observe(incoming)
                    if remote.needsMigrationUpload { archive.localRevision += 1 }
                    merged = archive.merged(with: incoming)
                    revision = remote.revision
                }
                merged.remoteRevision = revision
                merged.connectionFingerprint = context.fingerprint

                pending = merged.localRevision > merged.uploadedRevision
                if !pending {
                    archive = merged
                    persist()
                    syncState = .upToDate
                    lastSyncedAt = Date()
                    syncDelay = AppStore.liveSyncInterval
                    return
                }

                do {
                    let sentRevision = merged.localRevision
                    let newRevision = try await cloud.pushLists(
                        merged.cloudPayload(),
                        householdId: context.householdID,
                        expectedRevision: revision,
                        rawConnectionString: context.connection
                    )
                    guard isCurrent() else { return }
                    // Merge the acknowledged snapshot into today's local state,
                    // never assign the pre-await snapshot over newer edits.
                    var settled = archive.merged(with: merged)
                    settled.connectionFingerprint = context.fingerprint
                    settled.remoteRevision = newRevision
                    settled.uploadedRevision = sentRevision
                    archive = settled
                    persist()
                    syncState = archive.localRevision > sentRevision ? .waiting : .upToDate
                    lastSyncedAt = Date()
                    syncDelay = AppStore.liveSyncInterval
                    if archive.localRevision > sentRevision { continue }
                    return
                } catch NeonError.conflict {
                    // Someone wrote between our pull and our push. Pull again.
                    continue
                }
            }
            syncState = .waiting
        } catch is CancellationError {
            return
        } catch {
            guard isCurrent(), !Task.isCancelled else { return }
            syncState = .failed(error.localizedDescription)
            noteQuietTick()
        }
    }

    /// Watches the cloud **while Lists is on screen**. Its own loop, its own
    /// pacing, its own pending flag: a schedule-sync failure cannot hold these
    /// lists back, and closing Lists stops the polling entirely.
    @MainActor
    public func startVisibleSync() {
        guard syncTask == nil, cloudContext() != nil else { return }
        syncDelay = AppStore.liveSyncInterval
        syncTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.sync()
                let gap = self.syncDelay
                try? await Task.sleep(nanoseconds: UInt64(max(AppStore.liveSyncInterval, gap) * 1_000_000_000))
            }
        }
    }

    @MainActor
    public func stopVisibleSync() {
        syncTask?.cancel()
        syncTask = nil
        syncDelay = AppStore.liveSyncInterval
    }

    /// Brings the poll back to its fastest gap, because something just happened.
    func quicken() {
        syncDelay = AppStore.liveSyncInterval
    }

    /// Slows the poll after a quiet or failed tick, so a phone with no signal is
    /// not asking every two seconds for the length of the drive.
    func noteQuietTick() {
        syncDelay = min(syncDelay * Self.backoff, AppStore.liveSyncIdleInterval)
    }
}

// MARK: - Pacing
//
// Shared with the household poll on purpose: two phones should feel the same
// however quickly the change they are waiting for arrives.

extension HouseholdListsStore {
    static let backoff: Double = 1.5
    /// How many times a push may lose the compare-and-swap race before lists
    /// stop and report it rather than spinning.
    static let conflictAttempts = 4
}

import Foundation

// MARK: - Text

public enum ListText {
    /// How a duplicate is recognised: whitespace runs collapse, case is ignored.
    /// Wording is never rewritten from this — the user's own text is what is
    /// stored and shown; this is only ever a comparison key.
    public static func normalized(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").lowercased()
    }

    public static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Deterministic defaults

public enum HouseholdListsDefaults {
    public static let generalName = "General"

    /// Derived from the household id, so both phones create the same two lists
    /// with the same identities without having to sync the act of creating them.
    public static func listID(householdID: String, kind: ListKind) -> String {
        "list-default-\(kind.rawValue)-\(householdID)"
    }

    public static func groupID(listID: String) -> String {
        "group-\(generalName.lowercased())-\(listID)"
    }

    /// The two fixed lists, empty, each with its General group. Never sample
    /// data: a household that has never used Lists opens an empty tab.
    public static func archive(
        householdID: String,
        connectionFingerprint: String = "",
        now: Date = Date()
    ) -> HouseholdListsArchive {
        var lists: [HouseholdList] = []
        var groups: [HouseholdListGroup] = []
        for kind in ListKind.allCases {
            let id = listID(householdID: householdID, kind: kind)
            lists.append(HouseholdList(
                id: id, kind: kind, name: kind.title, rank: 0,
                stamps: ListStamps(), createdAt: now, updatedAt: now
            ))
            groups.append(HouseholdListGroup(
                id: groupID(listID: id), listID: id, name: generalName, rank: 0,
                stamps: ListStamps()
            ))
        }
        return HouseholdListsArchive(
            householdID: householdID,
            connectionFingerprint: connectionFingerprint,
            lists: lists,
            groups: groups
        )
    }
}

// MARK: - Queries

public extension HouseholdListsArchive {
    func list(_ id: String) -> HouseholdList? {
        lists.first { $0.id == id }
    }

    /// Lists of one kind in display order.
    func lists(of kind: ListKind) -> [HouseholdList] {
        lists.filter { $0.kind == kind }.inListOrder()
    }

    /// The household's list for a kind. There is always exactly one.
    func defaultList(of kind: ListKind) -> HouseholdList? {
        lists(of: kind).first
    }

    func groups(of listID: String) -> [HouseholdListGroup] {
        groups.filter { $0.listID == listID }.inListOrder()
    }

    func generalGroup(of listID: String) -> HouseholdListGroup? {
        let ordered = groups(of: listID)
        if let canonical = ordered.first(where: { $0.id == HouseholdListsDefaults.groupID(listID: listID) }) {
            return canonical
        }
        if let named = ordered.first(where: { isGeneral($0) }) { return named }
        return ordered.first
    }

    /// Whether a section is the one that cannot be removed. Matched by identity
    /// *or* by name, because a list created before the General identity was
    /// derived already has a General under a generated id, and adding a second
    /// one would leave two sections with the same name — and the wrong one as
    /// the capture target.
    func isGeneral(_ group: HouseholdListGroup) -> Bool {
        group.id == HouseholdListsDefaults.groupID(listID: group.listID)
            || ListText.normalized(group.name) == ListText.normalized(HouseholdListsDefaults.generalName)
    }

    func items(of listID: String, inGroup groupID: String) -> [HouseholdListItem] {
        items.filter { $0.listID == listID && $0.groupID == groupID }.inListOrder()
    }

    /// Items in group order, then in each group's own order.
    func orderedItems(of listID: String) -> [HouseholdListItem] {
        groups(of: listID).flatMap { items(of: listID, inGroup: $0.id) }
    }

    func activeItems(of listID: String) -> [HouseholdListItem] {
        orderedItems(of: listID).filter { !$0.isCompleted }
    }

    func completedItems(of listID: String) -> [HouseholdListItem] {
        orderedItems(of: listID).filter(\.isCompleted)
    }

    func subtasks(of itemID: String) -> [ListSubtask] {
        subtasks.filter { $0.itemID == itemID }.inListOrder()
    }

    func remainingCount(of listID: String) -> Int {
        items.reduce(into: 0) { total, item in
            if item.listID == listID && !item.isCompleted { total += 1 }
        }
    }

    /// An unfinished item in this list whose wording matches, for the grocery
    /// "you already have this" prompt.
    func duplicate(of listID: String, matching text: String) -> HouseholdListItem? {
        let key = ListText.normalized(text)
        guard !key.isEmpty else { return nil }
        return activeItems(of: listID).first { ListText.normalized($0.text) == key }
    }

    /// Advisory-cleanup candidates for one list.
    func reviewCandidates(of listID: String, kind: ListKind, now: Date, calendar: Calendar = .current) -> [HouseholdListItem] {
        let threshold = calendar.date(byAdding: .day, value: -kind.reviewDays, to: now) ?? now
        return activeItems(of: listID)
            .filter { $0.activityAt <= threshold && ($0.reviewAfter.map { $0 <= now } ?? true) }
            .sorted { $0.activityAt < $1.activityAt }
    }
}

// MARK: - Maintenance

public extension HouseholdListsArchive {
    mutating func recordDeletion(id: String, kind: ListDeletion.Kind, stamp: RecordStamp) {
        let deletion = ListDeletion(id: id, kind: kind, stamp: stamp)
        deletions.removeAll { $0.key == deletion.key }
        deletions.append(deletion)
    }

    func isDeleted(id: String, kind: ListDeletion.Kind) -> Bool {
        deletions.contains { $0.kind == kind && $0.id == id }
    }

    /// Deletion wins for its identity: the row goes, and so does everything
    /// that only existed because of it.
    mutating func applyDeletions() {
        let deletedLists = Set(deletions.filter { $0.kind == .list }.map(\.id))
        let deletedGroups = Set(deletions.filter { $0.kind == .group }.map(\.id))
        let deletedItems = Set(deletions.filter { $0.kind == .item }.map(\.id))
        let deletedSubtasks = Set(deletions.filter { $0.kind == .subtask }.map(\.id))

        lists.removeAll { deletedLists.contains($0.id) }
        let survivingLists = Set(lists.map(\.id))
        groups.removeAll { deletedGroups.contains($0.id) || !survivingLists.contains($0.listID) }
        let survivingGroups = Set(groups.map(\.id))
        items.removeAll {
            deletedItems.contains($0.id) || !survivingLists.contains($0.listID) || !survivingGroups.contains($0.groupID)
        }
        let survivingItems = Set(items.map(\.id))
        subtasks.removeAll { deletedSubtasks.contains($0.id) || !survivingItems.contains($0.itemID) }

        // A default list is never deleted, however it was recorded: otherwise a
        // stray deletion record would leave the household with no Groceries tab.
        ensureDefaults()
        // An empty group list would strand items with nowhere to live.
        ensureGeneralGroups()
        normalizeRanks()
    }

    /// Add missing defaults. Legacy lists must be migrated before this point;
    /// never silently discard their rows while normalising a document.
    mutating func ensureDefaults(now: Date = Date()) {
        for kind in ListKind.allCases {
            let id = HouseholdListsDefaults.listID(householdID: householdID, kind: kind)
            if let index = lists.firstIndex(where: { $0.id == id }) {
                if ListText.trimmed(lists[index].name).isEmpty { lists[index].name = kind.title }
            } else {
                lists.append(HouseholdList(
                    id: id, kind: kind, name: kind.title, rank: 0,
                    stamps: ListStamps(), createdAt: now, updatedAt: now
                ))
            }
        }
        pruneDescendants()
    }

    /// Drops sections and rows left behind by a list that is no longer here.
    mutating func pruneDescendants() {
        let listIDs = Set(lists.map(\.id))
        groups.removeAll { !listIDs.contains($0.listID) }
        let groupIDs = Set(groups.map(\.id))
        items.removeAll { !listIDs.contains($0.listID) || !groupIDs.contains($0.groupID) }
        let itemIDs = Set(items.map(\.id))
        subtasks.removeAll { !itemIDs.contains($0.itemID) }
    }

    /// Every list keeps a General group, so items always have a home.
    mutating func ensureGeneralGroups() {
        for list in lists {
            // Already has one, under whatever identity it was created with.
            if groups.contains(where: { $0.listID == list.id && isGeneral($0) }) { continue }
            let id = HouseholdListsDefaults.groupID(listID: list.id)
            if let index = groups.firstIndex(where: { $0.id == id }) {
                if ListText.trimmed(groups[index].name).isEmpty { groups[index].name = HouseholdListsDefaults.generalName }
                continue
            }
            groups.append(HouseholdListGroup(
                id: id, listID: list.id, name: HouseholdListsDefaults.generalName, rank: 0
            ))
        }
    }

    /// Dense ranks per sibling scope, ordered by (rank, id). Both phones compute
    /// the same numbers from the same records, so tidying converges.
    ///
    /// Also puts every collection in a canonical order — by identity, never by
    /// how a merge happened to walk a dictionary. Display order comes from
    /// `rank`; array order only has to be *the same on both phones*, so that two
    /// documents that agree about their contents compare equal.
    mutating func normalizeRanks() {
        lists.sort { $0.id < $1.id }
        groups.sort { $0.id < $1.id }
        items.sort { $0.id < $1.id }
        subtasks.sort { $0.id < $1.id }
        deletions.sort { $0.key < $1.key }

        for kind in ListKind.allCases {
            let ordered = lists.filter { $0.kind == kind }.inListOrder()
            for (index, record) in ordered.enumerated() {
                if let position = lists.firstIndex(where: { $0.id == record.id }) { lists[position].rank = index }
            }
        }
        for list in lists {
            let ordered = groups.filter { $0.listID == list.id }.inListOrder()
            for (index, record) in ordered.enumerated() {
                if let position = groups.firstIndex(where: { $0.id == record.id }) { groups[position].rank = index }
            }
            for group in groups(of: list.id) {
                let rows = items.filter { $0.listID == list.id && $0.groupID == group.id }.inListOrder()
                for (index, record) in rows.enumerated() {
                    if let position = items.firstIndex(where: { $0.id == record.id }) { items[position].rank = index }
                }
            }
        }
        for item in items {
            let rows = subtasks.filter { $0.itemID == item.id }.inListOrder()
            for (index, record) in rows.enumerated() {
                if let position = subtasks.firstIndex(where: { $0.id == record.id }) { subtasks[position].rank = index }
            }
        }
    }
}

// MARK: - Validation

public extension HouseholdListsArchive {
    /// Version 1 allowed additional lists. Version 2 keeps their sections and
    /// items under the matching primary list, with stable item/group identities.
    /// Both devices compute the same migration. Unknown future data is refused.
    func migrated() throws -> HouseholdListsArchive {
        if version == Self.currentVersion { return try validated() }
        guard version == 1 else { throw ListError.unsupportedVersion(version) }
        _ = try validated(allowLegacyLists: true)
        var result = self
        let deletedLists = Set(deletions.filter { $0.kind == .list }.map(\.id))
        let deletedGroups = Set(deletions.filter { $0.kind == .group }.map(\.id))
        let deletedItems = Set(deletions.filter { $0.kind == .item }.map(\.id))
        let deletedSteps = Set(deletions.filter { $0.kind == .subtask }.map(\.id))
        let originals = Dictionary(uniqueKeysWithValues: lists.map { ($0.id, $0) })
        let canonicalIDs = Set(ListKind.allCases.map { HouseholdListsDefaults.listID(householdID: householdID, kind: $0) })
        result.groups.removeAll { deletedGroups.contains($0.id) || (deletedLists.contains($0.listID) && !canonicalIDs.contains($0.listID)) }
        let survivingGroups = Set(result.groups.map(\.id))
        result.items.removeAll { deletedItems.contains($0.id) || !survivingGroups.contains($0.groupID) }
        let survivingItems = Set(result.items.map(\.id))
        result.subtasks.removeAll { deletedSteps.contains($0.id) || !survivingItems.contains($0.itemID) }
        for index in result.groups.indices {
            let oldID = result.groups[index].listID
            guard let old = originals[oldID] else { continue }
            let target = HouseholdListsDefaults.listID(householdID: householdID, kind: old.kind)
            result.groups[index].listID = target
            if oldID != target, isGeneral(result.groups[index]) || result.groups[index].name == HouseholdListsDefaults.generalName {
                result.groups[index].name = String(old.name.prefix(ListLimits.groupName))
            }
        }
        for index in result.items.indices {
            if let old = originals[result.items[index].listID] {
                result.items[index].listID = HouseholdListsDefaults.listID(householdID: householdID, kind: old.kind)
            }
        }
        result.lists.removeAll { !canonicalIDs.contains($0.id) }
        result.ensureDefaults(now: lists.map(\.createdAt).min() ?? .distantPast)
        result.ensureGeneralGroups()
        result.normalizeRanks()
        result.version = Self.currentVersion
        result.localRevision += 1
        return try result.validated()
    }

    /// Throws rather than repairing. A caller that finds this archive unreadable
    /// must keep the bytes and offer recovery, never overwrite them.
    func validated(allowLegacyLists: Bool = false) throws -> HouseholdListsArchive {
        guard version == Self.currentVersion || (allowLegacyLists && version == 1) else { throw ListError.unsupportedVersion(version) }
        guard !householdID.isEmpty else { throw ListError.invalidArchive("no household identity") }
        guard Set(lists.map(\.id)).count == lists.count else { throw ListError.invalidArchive("duplicate list identity") }
        guard Set(groups.map(\.id)).count == groups.count else { throw ListError.invalidArchive("duplicate group identity") }
        guard Set(items.map(\.id)).count == items.count else { throw ListError.invalidArchive("duplicate item identity") }
        guard Set(subtasks.map(\.id)).count == subtasks.count else { throw ListError.invalidArchive("duplicate step identity") }
        guard Set(deletions.map(\.key)).count == deletions.count else { throw ListError.invalidArchive("duplicate deletion record") }

        for list in lists {
            guard !ListText.trimmed(list.name).isEmpty,
                  list.name.count <= ListLimits.listName,
                  list.rank >= 0 else { throw ListError.invalidArchive("bad list name or rank") }
            guard groups(of: list.id).count <= ListLimits.groupsPerList else { throw ListError.invalidArchive("too many sections") }
            guard items.filter({ $0.listID == list.id }).count <= ListLimits.itemsPerList else { throw ListError.invalidArchive("too many items") }
            guard generalGroup(of: list.id) != nil else { throw ListError.invalidArchive("list without a General section") }
        }

        let listIDs = Set(lists.map(\.id))
        let groupIDs = Set(groups.map(\.id))
        let itemIDs = Set(items.map(\.id))
        let listKinds = Dictionary(uniqueKeysWithValues: lists.map { ($0.id, $0.kind) })

        let expected = Set(ListKind.allCases.map { HouseholdListsDefaults.listID(householdID: householdID, kind: $0) })
        guard allowLegacyLists || listIDs == expected else {
            throw ListError.invalidArchive("expected exactly the To-dos and Groceries lists")
        }

        for group in groups {
            guard listIDs.contains(group.listID),
                  !ListText.trimmed(group.name).isEmpty,
                  group.name.count <= ListLimits.groupName,
                  group.rank >= 0 else { throw ListError.invalidArchive("bad group") }
        }

        for item in items {
            guard listIDs.contains(item.listID),
                  groupIDs.contains(item.groupID),
                  groups.first(where: { $0.id == item.groupID })?.listID == item.listID,
                  !ListText.trimmed(item.text).isEmpty,
                  item.text.count <= ListLimits.itemText,
                  item.quantity.count <= ListLimits.quantity,
                  item.note.count <= ListLimits.note,
                  item.rank >= 0 else { throw ListError.invalidArchive("bad item") }
        }

        for step in subtasks {
            guard itemIDs.contains(step.itemID),
                  listKinds[items.first { $0.id == step.itemID }?.listID ?? ""]?.supportsSubtasks == true,
                  !ListText.trimmed(step.text).isEmpty,
                  step.text.count <= ListLimits.subtaskText,
                  step.rank >= 0 else { throw ListError.invalidArchive("bad step") }
            guard subtasks(of: step.itemID).count <= ListLimits.subtasksPerItem else {
                throw ListError.invalidArchive("too many steps on one item")
            }
        }

        return self
    }
}

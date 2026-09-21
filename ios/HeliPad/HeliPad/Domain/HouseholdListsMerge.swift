import Foundation

// MARK: - Convergence
//
// Two phones must reach the same document from the same two inputs, in either
// order, whichever one each calls "local". Every rule below is therefore
// symmetric: a stamp decides when the two sides disagree about who edited last,
// and when stamps do not disagree the *values* decide, never which archive is
// the one being held.

/// Wording, quantity and note move together: they are one edit in the editor,
/// so they are one comparison here.
private struct ListContent: Comparable {
    var text: String
    var quantity: String
    var note: String

    static func < (lhs: ListContent, rhs: ListContent) -> Bool {
        (lhs.text, lhs.quantity, lhs.note) < (rhs.text, rhs.quantity, rhs.note)
    }
}

/// Which group a row sits in, and where in it.
private struct ListPlacement: Comparable {
    var groupID: String
    var rank: Int

    static func < (lhs: ListPlacement, rhs: ListPlacement) -> Bool {
        (lhs.groupID, lhs.rank) < (rhs.groupID, rhs.rank)
    }
}

private func resolve<T: Comparable>(
    local: T,
    remote: T,
    localStamp: RecordStamp?,
    remoteStamp: RecordStamp?
) -> (value: T, stamp: RecordStamp?) {
    switch (localStamp, remoteStamp) {
    case let (l?, r?) where l != r:
        return r > l ? (remote, r) : (local, l)
    case (nil, let r?):
        return (remote, r)
    case (let l?, nil):
        return (local, l)
    default:
        // Both absent, or the same stamp: pick by value. Both phones compute the
        // same answer, so a tie can never leave the two archives disagreeing.
        return (max(local, remote), localStamp)
    }
}

private func newest(_ a: RecordStamp?, _ b: RecordStamp?) -> RecordStamp? {
    switch (a, b) {
    case let (a?, b?): return max(a, b)
    case (let a?, nil): return a
    case (nil, let b?): return b
    default: return nil
    }
}

/// An unchecked row stores no date, which cannot take part in a comparison, so
/// "not completed" sorts as the distant past.
private extension Date {
    static func fromOptional(_ value: Date?) -> Date { value ?? .distantPast }
    static func toOptional(_ value: Date) -> Date? { value == .distantPast ? nil : value }
}

private func mergedStamps(_ a: ListStamps, _ b: ListStamps) -> ListStamps {
    ListStamps(
        content: newest(a.content, b.content),
        completion: newest(a.completion, b.completion),
        placement: newest(a.placement, b.placement),
        review: newest(a.review, b.review)
    )
}

public extension HouseholdListsArchive {

    /// Union by identity, then per-facet resolution for records both sides have.
    ///
    /// Records are never matched on wording or array position. A deletion record
    /// beats an edit to the same identity however old it is, which is what keeps
    /// a long-offline phone from resurrecting something the household cleared.
    func merged(with other: HouseholdListsArchive, now: Date = Date()) -> HouseholdListsArchive {
        var result = self
        result.ensureDefaults()

        // 1. Deletions: the union, newest stamp per identity.
        var deletionsByKey = Dictionary(uniqueKeysWithValues: deletions.map { ($0.key, $0) })
        for deletion in other.deletions {
            if let existing = deletionsByKey[deletion.key] {
                if deletion.stamp > existing.stamp { deletionsByKey[deletion.key] = deletion }
            } else {
                deletionsByKey[deletion.key] = deletion
            }
        }
        result.deletions = Array(deletionsByKey.values)

        // 2. Records: union by identity, facet-resolved where both exist.
        result.lists = mergedLists(result.lists, other.lists)
        result.groups = mergedGroups(result.groups, other.groups)
        result.items = mergedItems(result.items, other.items)
        result.subtasks = mergedSubtasks(result.subtasks, other.subtasks)

        // 3. Deletion wins for its identity, and takes descendants with it.
        result.applyDeletions()

        // Revision bookkeeping belongs to the store that owns the document, not
        // to the merge: `remoteRevision` comes from the pull that produced
        // `other`, and pending state stays whatever this phone already had.
        result.householdID = householdID
        if !connectionFingerprint.isEmpty { result.connectionFingerprint = connectionFingerprint }
        result.localRevision = localRevision
        result.uploadedRevision = uploadedRevision
        return result
    }
}

// MARK: - Per-collection merges

extension HouseholdListsArchive {

    func mergedLists(_ local: [HouseholdList], _ remote: [HouseholdList]) -> [HouseholdList] {
        var byID = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
        for incoming in remote {
            guard let existing = byID[incoming.id] else { byID[incoming.id] = incoming; continue }
            var result = existing
            result.name = resolve(
                local: existing.name, remote: incoming.name,
                localStamp: existing.stamps.content, remoteStamp: incoming.stamps.content
            ).value
            result.rank = resolve(
                local: existing.rank, remote: incoming.rank,
                localStamp: existing.stamps.placement, remoteStamp: incoming.stamps.placement
            ).value
            result.stamps = mergedStamps(existing.stamps, incoming.stamps)
            // Kind is fixed at creation, so a disagreement here is damage rather
            // than an edit. Resolve it the same way on both phones.
            if existing.kind != incoming.kind {
                result.kind = existing.kind.rawValue <= incoming.kind.rawValue ? existing.kind : incoming.kind
            }
            result.createdAt = min(existing.createdAt, incoming.createdAt)
            result.updatedAt = max(existing.updatedAt, incoming.updatedAt)
            byID[incoming.id] = result
        }
        return Array(byID.values)
    }

    func mergedGroups(_ local: [HouseholdListGroup], _ remote: [HouseholdListGroup]) -> [HouseholdListGroup] {
        var byID = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
        for incoming in remote {
            guard let existing = byID[incoming.id] else { byID[incoming.id] = incoming; continue }
            var result = existing
            result.name = resolve(
                local: existing.name, remote: incoming.name,
                localStamp: existing.stamps.content, remoteStamp: incoming.stamps.content
            ).value
            result.rank = resolve(
                local: existing.rank, remote: incoming.rank,
                localStamp: existing.stamps.placement, remoteStamp: incoming.stamps.placement
            ).value
            result.stamps = mergedStamps(existing.stamps, incoming.stamps)
            // A section belongs to the list it was made in.
            if existing.listID != incoming.listID { result.listID = min(existing.listID, incoming.listID) }
            byID[incoming.id] = result
        }
        return Array(byID.values)
    }

    func mergedItems(_ local: [HouseholdListItem], _ remote: [HouseholdListItem]) -> [HouseholdListItem] {
        var byID = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
        for incoming in remote {
            guard let existing = byID[incoming.id] else { byID[incoming.id] = incoming; continue }
            var result = existing

            let content = resolve(
                local: ListContent(text: existing.text, quantity: existing.quantity, note: existing.note),
                remote: ListContent(text: incoming.text, quantity: incoming.quantity, note: incoming.note),
                localStamp: existing.stamps.content, remoteStamp: incoming.stamps.content
            )
            result.text = content.value.text
            result.quantity = content.value.quantity
            result.note = content.value.note

            let completion = resolve(
                local: Date.fromOptional(existing.completedAt), remote: Date.fromOptional(incoming.completedAt),
                localStamp: existing.stamps.completion, remoteStamp: incoming.stamps.completion
            )
            result.completedAt = Date.toOptional(completion.value)

            let placement = resolve(
                local: ListPlacement(groupID: existing.groupID, rank: existing.rank),
                remote: ListPlacement(groupID: incoming.groupID, rank: incoming.rank),
                localStamp: existing.stamps.placement, remoteStamp: incoming.stamps.placement
            )
            result.groupID = placement.value.groupID
            result.rank = placement.value.rank

            let review = resolve(
                local: Date.fromOptional(existing.reviewAfter), remote: Date.fromOptional(incoming.reviewAfter),
                localStamp: existing.stamps.review, remoteStamp: incoming.stamps.review
            )
            result.reviewAfter = Date.toOptional(review.value)

            result.stamps = mergedStamps(existing.stamps, incoming.stamps)
            if existing.listID != incoming.listID { result.listID = min(existing.listID, incoming.listID) }
            result.createdAt = min(existing.createdAt, incoming.createdAt)
            result.updatedAt = max(existing.updatedAt, incoming.updatedAt)
            // Activity only ever advances on a meaningful change, so the later of
            // the two is the household's real last touch of this row.
            result.activityAt = max(existing.activityAt, incoming.activityAt)
            byID[incoming.id] = result
        }
        return Array(byID.values)
    }

    func mergedSubtasks(_ local: [ListSubtask], _ remote: [ListSubtask]) -> [ListSubtask] {
        var byID = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
        for incoming in remote {
            guard let existing = byID[incoming.id] else { byID[incoming.id] = incoming; continue }
            var result = existing
            result.text = resolve(
                local: existing.text, remote: incoming.text,
                localStamp: existing.stamps.content, remoteStamp: incoming.stamps.content
            ).value
            result.rank = resolve(
                local: existing.rank, remote: incoming.rank,
                localStamp: existing.stamps.placement, remoteStamp: incoming.stamps.placement
            ).value
            let completion = resolve(
                local: Date.fromOptional(existing.completedAt), remote: Date.fromOptional(incoming.completedAt),
                localStamp: existing.stamps.completion, remoteStamp: incoming.stamps.completion
            )
            result.completedAt = Date.toOptional(completion.value)
            result.stamps = mergedStamps(existing.stamps, incoming.stamps)
            if existing.itemID != incoming.itemID { result.itemID = min(existing.itemID, incoming.itemID) }
            byID[incoming.id] = result
        }
        return Array(byID.values)
    }
}
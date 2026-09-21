import Foundation

public enum ListKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case todos, groceries
    public var id: String { rawValue }
    public var title: String { self == .todos ? "To-dos" : "Groceries" }
    public var reviewDays: Int { self == .todos ? 45 : 14 }
}

public struct ListGroup: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    /// Position within the list. Order is never taken from array position.
    public var sortIndex: Int
    public init(id: UUID = UUID(), title: String, sortIndex: Int = 0) {
        self.id = id; self.title = title; self.sortIndex = sortIndex
    }

    private enum CodingKeys: String, CodingKey { case id, title, sortIndex }

    /// Additive: files written before ordering existed decode with sortIndex 0.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        sortIndex = try container.decodeIfPresent(Int.self, forKey: .sortIndex) ?? 0
    }
}

public struct ListStep: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var text: String
    public var isCompleted: Bool
    public init(id: UUID = UUID(), text: String, isCompleted: Bool = false) {
        self.id = id; self.text = text; self.isCompleted = isCompleted
    }
}

public struct ListItem: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var groupID: UUID
    public var text: String
    public var quantity: String
    public var note: String
    public var steps: [ListStep]
    public var createdAt: Date
    public var updatedAt: Date
    public var completedAt: Date?
    public var reviewAfter: Date?
    /// Position within the item's group. Order is never taken from array position.
    public var sortIndex: Int
    public var isCompleted: Bool { completedAt != nil }

    public init(id: UUID = UUID(), groupID: UUID, text: String, quantity: String = "", note: String = "",
                steps: [ListStep] = [], now: Date = Date(), sortIndex: Int = 0) {
        self.id = id; self.groupID = groupID; self.text = text; self.quantity = quantity
        self.note = note; self.steps = steps; createdAt = now; updatedAt = now; self.sortIndex = sortIndex
    }

    private enum CodingKeys: String, CodingKey {
        case id, groupID, text, quantity, note, steps, createdAt, updatedAt, completedAt, reviewAfter, sortIndex
    }

    /// Additive: files written before ordering existed decode with sortIndex 0.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        groupID = try container.decode(UUID.self, forKey: .groupID)
        text = try container.decode(String.self, forKey: .text)
        quantity = try container.decode(String.self, forKey: .quantity)
        note = try container.decode(String.self, forKey: .note)
        steps = try container.decode([ListStep].self, forKey: .steps)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        reviewAfter = try container.decodeIfPresent(Date.self, forKey: .reviewAfter)
        sortIndex = try container.decodeIfPresent(Int.self, forKey: .sortIndex) ?? 0
    }
}

public struct ListBoard: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var kind: ListKind
    public var name: String
    public var groups: [ListGroup]
    public var items: [ListItem]
    /// Position within the board's kind. Order is never taken from array position.
    public var sortIndex: Int
    public init(id: UUID = UUID(), kind: ListKind, name: String, groups: [ListGroup], items: [ListItem] = [], sortIndex: Int = 0) {
        self.id = id; self.kind = kind; self.name = name; self.groups = groups; self.items = items; self.sortIndex = sortIndex
    }

    private enum CodingKeys: String, CodingKey { case id, kind, name, groups, items, sortIndex }

    /// Additive: files written before ordering existed decode with sortIndex 0.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = try container.decode(ListKind.self, forKey: .kind)
        name = try container.decode(String.self, forKey: .name)
        groups = try container.decode([ListGroup].self, forKey: .groups)
        items = try container.decode([ListItem].self, forKey: .items)
        sortIndex = try container.decodeIfPresent(Int.self, forKey: .sortIndex) ?? 0
    }

    public func reviewCandidates(now: Date, calendar: Calendar = .current) -> [ListItem] {
        let threshold = calendar.date(byAdding: .day, value: -kind.reviewDays, to: now) ?? now
        return items.filter { !$0.isCompleted && $0.updatedAt <= threshold && ($0.reviewAfter.map { $0 <= now } ?? true) }
            .sorted { $0.updatedAt < $1.updatedAt }
    }

    public mutating func upsert(_ input: ListItem, now: Date) throws {
        var item = input
        item.text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
        item.quantity = item.quantity.trimmingCharacters(in: .whitespacesAndNewlines)
        item.note = item.note.trimmingCharacters(in: .whitespacesAndNewlines)
        if let current = items.first(where: { $0.id == item.id }),
           current.text == item.text, current.quantity == item.quantity, current.note == item.note,
           current.steps == item.steps, current.groupID == item.groupID {
            // Moving a row is not an edit: it must not restart the inactivity
            // clock or clear a "keep for now" snooze.
            item.updatedAt = current.updatedAt
            item.reviewAfter = current.reviewAfter
        } else {
            item.updatedAt = now
            item.reviewAfter = nil
        }
        var candidate = self
        if let index = candidate.items.firstIndex(where: { $0.id == item.id }) { candidate.items[index] = item }
        else {
            item.sortIndex = candidate.items(in: item.groupID).count
            candidate.items.append(item)
        }
        try candidate.validate()
        self = candidate
    }

    public mutating func setCompleted(_ id: UUID, to completed: Bool, now: Date) {
        guard let index = items.firstIndex(where: { $0.id == id }), items[index].isCompleted != completed else { return }
        items[index].completedAt = completed ? now : nil
        items[index].updatedAt = now
        items[index].reviewAfter = nil
    }

    public mutating func keep(_ id: UUID, now: Date, calendar: Calendar = .current) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].reviewAfter = calendar.date(byAdding: .day, value: 30, to: now)
    }

    // MARK: - Ordering

    /// Groups and items in display order. Array position is only a tiebreaker for
    /// data written before ordering existed, never the ordering contract.
    public var orderedGroups: [ListGroup] {
        groups.enumerated().sorted { ($0.element.sortIndex, $0.offset) < ($1.element.sortIndex, $1.offset) }.map(\.element)
    }

    public func items(in groupID: UUID) -> [ListItem] {
        items.enumerated().filter { $0.element.groupID == groupID }
            .sorted { ($0.element.sortIndex, $0.offset) < ($1.element.sortIndex, $1.offset) }.map(\.element)
    }

    /// Assigns a dense total order to every group and to the items inside it.
    public mutating func normalizeOrder() {
        var orderedGroups = self.orderedGroups
        for index in orderedGroups.indices { orderedGroups[index].sortIndex = index }
        let known = Set(orderedGroups.map(\.id))
        var orderedItems: [ListItem] = []
        for group in orderedGroups {
            var members = items(in: group.id)
            for index in members.indices { members[index].sortIndex = index }
            orderedItems += members
        }
        orderedItems += items.filter { !known.contains($0.groupID) }
        groups = orderedGroups
        items = orderedItems
    }

    // MARK: - Groups

    public mutating func upsertGroup(_ group: ListGroup) throws {
        var group = group
        group.title = group.title.trimmingCharacters(in: .whitespacesAndNewlines)
        var candidate = self
        if let index = candidate.groups.firstIndex(where: { $0.id == group.id }) { candidate.groups[index] = group }
        else { candidate.groups.append(group) }
        candidate.normalizeOrder()
        try candidate.validate()
        self = candidate
    }

    /// Refuses to remove the last group; otherwise that group's items move to the
    /// first remaining group so nothing is silently discarded.
    public mutating func removeGroup(_ id: UUID) throws {
        guard groups.count > 1, let index = groups.firstIndex(where: { $0.id == id }) else { throw ListError.invalidData }
        var candidate = self
        candidate.groups.remove(at: index)
        guard let fallback = candidate.orderedGroups.first?.id else { throw ListError.invalidData }
        for position in candidate.items.indices where candidate.items[position].groupID == id {
            candidate.items[position].groupID = fallback
        }
        candidate.normalizeOrder()
        try candidate.validate()
        self = candidate
    }

    public mutating func moveGroups(fromOffsets: IndexSet, toOffset: Int) {
        var ordered = orderedGroups
        guard !ordered.isEmpty else { return }
        let moving = fromOffsets.map { ordered[$0] }
        for index in fromOffsets.sorted(by: >) { ordered.remove(at: index) }
        ordered.insert(contentsOf: moving, at: toOffset - fromOffsets.filter { $0 < toOffset }.count)
        for index in ordered.indices { ordered[index].sortIndex = index }
        groups = ordered
    }

    // MARK: - Items

    public mutating func reorderItems(groupID: UUID, fromOffsets: IndexSet, toOffset: Int) {
        var ordered = items(in: groupID)
        guard !ordered.isEmpty else { return }
        let moving = fromOffsets.map { ordered[$0] }
        for index in fromOffsets.sorted(by: >) { ordered.remove(at: index) }
        ordered.insert(contentsOf: moving, at: toOffset - fromOffsets.filter { $0 < toOffset }.count)
        for index in ordered.indices { ordered[index].sortIndex = index }
        let updated = Dictionary(uniqueKeysWithValues: ordered.map { ($0.id, $0) })
        for index in items.indices where items[index].groupID == groupID {
            if let replacement = updated[items[index].id] { items[index] = replacement }
        }
        normalizeOrder()
    }

    /// Moves an item one position inside its group.
    public mutating func moveItem(_ id: UUID, by offset: Int) {
        guard let target = items.first(where: { $0.id == id }) else { return }
        var ordered = items(in: target.groupID)
        guard let position = ordered.firstIndex(where: { $0.id == id }) else { return }
        let destination = position + offset
        guard ordered.indices.contains(destination) else { return }
        ordered.swapAt(position, destination)
        for index in ordered.indices { ordered[index].sortIndex = index }
        let updated = Dictionary(uniqueKeysWithValues: ordered.map { ($0.id, $0) })
        for index in items.indices where items[index].groupID == target.groupID {
            if let replacement = updated[items[index].id] { items[index] = replacement }
        }
        normalizeOrder()
    }

    /// Moves an item to the end of another group.
    public mutating func moveItem(_ id: UUID, toGroup groupID: UUID) throws {
        guard let index = items.firstIndex(where: { $0.id == id }), groups.contains(where: { $0.id == groupID }) else {
            throw ListError.invalidData
        }
        var candidate = self
        candidate.items[index].groupID = groupID
        candidate.items[index].sortIndex = candidate.items(in: groupID).filter { $0.id != id }.count
        candidate.normalizeOrder()
        try candidate.validate()
        self = candidate
    }

    /// Removes every completed item and returns exactly what was removed, for Undo.
    @discardableResult public mutating func clearCompleted() -> [ListItem] {
        let removed = items.filter(\.isCompleted)
        guard !removed.isEmpty else { return [] }
        items.removeAll { $0.isCompleted }
        normalizeOrder()
        return removed
    }

    public mutating func rename(_ name: String) throws {
        var candidate = self
        candidate.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        try candidate.validate()
        self = candidate
    }

    public func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 100,
              !groups.isEmpty, groups.count <= 30, items.count <= 1000,
              Set(groups.map(\.id)).count == groups.count,
              Set(items.map(\.id)).count == items.count else { throw ListError.invalidData }
        let groupIDs = Set(groups.map(\.id))
        guard groups.allSatisfy({ !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.title.count <= 60 }),
              items.allSatisfy({ item in
                  groupIDs.contains(item.groupID) && !item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                  item.text.count <= 200 && item.quantity.count <= 80 && item.note.count <= 2000 &&
                  item.steps.count <= 20 && Set(item.steps.map(\.id)).count == item.steps.count &&
                  item.steps.allSatisfy { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.text.count <= 200 }
              }) else { throw ListError.invalidData }
    }

    /// Receiving a copy never overwrites the sender's identity or another local list.
    public func independentCopy() -> ListBoard {
        var copy = self
        copy.id = UUID()
        let mapping = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, UUID()) })
        copy.groups = groups.map { ListGroup(id: mapping[$0.id]!, title: $0.title, sortIndex: $0.sortIndex) }
        copy.items = items.map { original in
            var item = original
            item.id = UUID(); item.groupID = mapping[original.groupID]!
            item.steps = original.steps.map { ListStep(text: $0.text, isCompleted: $0.isCompleted) }
            return item
        }
        return copy
    }

    public var plainText: String {
        var lines = [name, ""]
        for group in orderedGroups {
            let rows = items(in: group.id).filter { !$0.isCompleted }
            guard !rows.isEmpty else { continue }
            lines.append(group.title)
            for item in rows {
                lines.append("☐ \(item.text)\(item.quantity.isEmpty ? "" : " · \(item.quantity)")")
                if !item.note.isEmpty { lines.append("  \(item.note)") }
                lines += item.steps.map { "  \($0.isCompleted ? "☑" : "☐") \($0.text)" }
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}

public enum ListError: LocalizedError {
    case invalidData, unsupportedVersion, tooLarge
    public var errorDescription: String? {
        switch self {
        case .invalidData: "This list has empty, oversized, or invalid items. Check the details and try again."
        case .unsupportedVersion: "This list was made with a different version. Keep the file and update Lists Preview."
        case .tooLarge: "This file is too large. Lists Preview accepts files up to 2 MB."
        }
    }
}

public struct ListTransfer: Codable, Sendable {
    public var version: Int = 1
    public var board: ListBoard
    public init(board: ListBoard) { self.board = board }
    public func data() throws -> Data { try board.validate(); return try JSONEncoder().encode(self) }
    public static func read(_ data: Data) throws -> ListTransfer {
        guard data.count <= 2_000_000 else { throw ListError.tooLarge }
        let transfer = try JSONDecoder().decode(Self.self, from: data)
        guard transfer.version == 1 else { throw ListError.unsupportedVersion }
        try transfer.board.validate()
        return transfer
    }
}

public struct ListArchive: Codable, Equatable, Sendable {
    public var version: Int = 1
    public var boards: [ListBoard]
    public init(boards: [ListBoard]) { self.boards = boards }

    public func validate() throws {
        guard version == 1 else { throw ListError.unsupportedVersion }
        guard boards.count <= 50, Set(boards.map(\.id)).count == boards.count else { throw ListError.invalidData }
        try boards.forEach { try $0.validate() }
    }

    /// Lists of one kind in display order.
    public func boards(of kind: ListKind) -> [ListBoard] {
        boards.enumerated().filter { $0.element.kind == kind }
            .sorted { ($0.element.sortIndex, $0.offset) < ($1.element.sortIndex, $1.offset) }.map(\.element)
    }

    /// Dense ordering across kinds, then inside each list.
    public mutating func normalizeOrder() {
        for index in boards.indices { boards[index].normalizeOrder() }
        var ordered: [ListBoard] = []
        for kind in ListKind.allCases {
            var matching = boards(of: kind)
            for index in matching.indices { matching[index].sortIndex = index }
            ordered += matching
        }
        boards = ordered
    }

    @discardableResult
    public mutating func addBoard(kind: ListKind, name: String, groupTitle: String) throws -> ListBoard {
        let board = ListBoard(kind: kind, name: name, groups: [ListGroup(title: groupTitle)],
                              items: [], sortIndex: boards(of: kind).count)
        try board.validate()
        var candidate = self
        candidate.boards.append(board)
        candidate.normalizeOrder()
        try candidate.validate()
        self = candidate
        return board
    }

    /// Restores a removed list at its previous position. Used by Undo.
    public mutating func insertBoard(_ board: ListBoard) throws {
        var candidate = self
        var matching = candidate.boards(of: board.kind).filter { $0.id != board.id }
        matching.insert(board, at: min(max(0, board.sortIndex), matching.count))
        candidate.boards = candidate.boards.filter { $0.kind != board.kind } + matching
        candidate.normalizeOrder()
        try candidate.validate()
        self = candidate
    }

    @discardableResult
    public mutating func removeBoard(_ id: UUID) throws -> ListBoard {
        guard let index = boards.firstIndex(where: { $0.id == id }) else { throw ListError.invalidData }
        var candidate = self
        let removed = candidate.boards.remove(at: index)
        candidate.normalizeOrder()
        try candidate.validate()
        self = candidate
        return removed
    }

    public mutating func renameBoard(_ id: UUID, to name: String) throws {
        guard let index = boards.firstIndex(where: { $0.id == id }) else { throw ListError.invalidData }
        var candidate = self
        try candidate.boards[index].rename(name)
        try candidate.validate()
        self = candidate
    }

    public mutating func moveBoards(kind: ListKind, fromOffsets: IndexSet, toOffset: Int) {
        var ordered = boards(of: kind)
        guard !ordered.isEmpty else { return }
        let moving = fromOffsets.map { ordered[$0] }
        for index in fromOffsets.sorted(by: >) { ordered.remove(at: index) }
        ordered.insert(contentsOf: moving, at: toOffset - fromOffsets.filter { $0 < toOffset }.count)
        let positions = Dictionary(uniqueKeysWithValues: ordered.enumerated().map { ($0.element.id, $0.offset) })
        for index in boards.indices where boards[index].kind == kind {
            if let position = positions[boards[index].id] { boards[index].sortIndex = position }
        }
        normalizeOrder()
    }

    public static func sample(now: Date = Date()) -> ListArchive {
        let home = ListGroup(title: "Around the house")
        let personal = ListGroup(title: "For yourself")
        let later = ListGroup(title: "Someday")
        let produce = ListGroup(title: "Fruit & vegetables")
        let dairy = ListGroup(title: "Fridge & dairy")
        let pantry = ListGroup(title: "Pantry")
        func old(_ days: Int) -> Date { Calendar.current.date(byAdding: .day, value: -days, to: now)! }
        var todos = ListBoard(kind: .todos, name: "Everyday things", groups: [home, personal, later], items: [
            ListItem(groupID: home.id, text: "Refresh the entryway", note: "A little space to land when we get home.", steps: [ListStep(text: "Sort the shoe basket", isCompleted: true), ListStep(text: "Hang the spare hooks"), ListStep(text: "Donate coats we no longer wear")], now: now),
            ListItem(groupID: home.id, text: "Replace the furnace filter", now: now),
            ListItem(groupID: personal.id, text: "Find a book for the weekend", now: now),
            ListItem(groupID: later.id, text: "Look into a pottery class", now: old(52))
        ])
        var done = ListItem(groupID: home.id, text: "Drop off the donations", now: now)
        done.completedAt = now; todos.items.append(done)
        let groceries = ListBoard(kind: .groceries, name: "The next shop", groups: [produce, dairy, pantry], items: [
            ListItem(groupID: produce.id, text: "Avocados", quantity: "3 ripe", now: now),
            ListItem(groupID: produce.id, text: "Blueberries", quantity: "1 punnet", now: now),
            ListItem(groupID: produce.id, text: "Baby spinach", quantity: "1 bag", now: now),
            ListItem(groupID: dairy.id, text: "Oat milk", quantity: "2 cartons", now: now),
            ListItem(groupID: dairy.id, text: "Greek yogurt", quantity: "Plain", now: now),
            ListItem(groupID: pantry.id, text: "Sesame oil", quantity: "Small bottle", now: old(19))
        ])
        return ListArchive(boards: [todos, groceries]).normalized()
    }

    /// Ordering assigned by array position. Only for data built in code, such as
    /// the sample archive; stored data is normalized on load instead.
    public func normalized() -> ListArchive {
        var copy = self
        copy.normalizeOrder()
        return copy
    }
}

/// Small, idempotent operations let different rows be changed concurrently.
/// Content edits carry their base so conflicts can be reviewed instead of overwritten.
public struct ListOperation: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID = UUID()
    public var kind: String
    public var item: ListItem?
    public var base: ListItem?
    public var itemID: UUID?
    public var completed: Bool?
    public var name: String?
    public var group: ListGroup?
    public var groupID: UUID?
    public var now: Date
    public init(kind: String, item: ListItem? = nil, base: ListItem? = nil, itemID: UUID? = nil, completed: Bool? = nil,
                name: String? = nil, group: ListGroup? = nil, groupID: UUID? = nil, now: Date = Date()) {
        self.kind = kind; self.item = item; self.base = base; self.itemID = itemID; self.completed = completed
        self.name = name; self.group = group; self.groupID = groupID; self.now = now
    }
    public func apply(to board: inout ListBoard) throws {
        switch kind {
        case "save":
            guard var item else { throw ListError.invalidData }
            if let current = board.items.first(where: { $0.id == item.id }) { item.completedAt = current.completedAt }
            try board.upsert(item, now: now)
        case "complete":
            guard let itemID, let completed else { throw ListError.invalidData }
            board.setCompleted(itemID, to: completed, now: now)
        case "keep":
            guard let itemID else { throw ListError.invalidData }
            board.keep(itemID, now: now)
        case "delete":
            guard let itemID else { throw ListError.invalidData }
            board.items.removeAll { $0.id == itemID }
            board.normalizeOrder()
        case "rename":
            guard let name else { throw ListError.invalidData }
            try board.rename(name)
        case "groupSave":
            guard let group else { throw ListError.invalidData }
            try board.upsertGroup(group)
        case "groupDelete":
            guard let groupID else { throw ListError.invalidData }
            try board.removeGroup(groupID)
        default: throw ListError.invalidData
        }
    }
}

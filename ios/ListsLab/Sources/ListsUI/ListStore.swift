import SwiftUI
import ListsKit

public struct SharedList: Codable, Equatable, Sendable {
    var link: URL
    var pending: [ListOperation] = []
    var revision: Int = 0
}

private struct SavedPreview: Codable {
    var archive: ListArchive
    var connections: [String: SharedList]
}

private struct RemoteList: Codable {
    var board: ListBoard
    var revision: Int
}

/// What the last destructive action can put back. Restored items take fresh
/// identities so Undo cannot resurrect an item another device deleted.
public enum ListUndo: Equatable, Sendable {
    case item(boardID: UUID, item: ListItem)
    case items(boardID: UUID, items: [ListItem])
    case group(boardID: UUID, group: ListGroup, items: [ListItem])
    case board(board: ListBoard, connection: SharedList?)

    public var summary: String {
        switch self {
        case .item(_, let item): "Removed \(item.text)"
        case .items(_, let items): "Removed \(items.count) item\(items.count == 1 ? "" : "s")"
        case .group(_, let group, _): "Removed \(group.title)"
        case .board(let board, _): "Removed \(board.name)"
        }
    }
}

@MainActor public final class ListStore: ObservableObject {
    @Published public private(set) var boards: [ListBoard] = []
    @Published public private(set) var connections: [String: SharedList] = [:]
    @Published public var error: String?
    @Published public private(set) var status = ""
    @Published public private(set) var pendingUndo: ListUndo?
    @Published public private(set) var isSyncing = false
    @Published public private(set) var blockedIDs: Set<UUID> = []
    private let fileURL: URL?
    private var readable = true

    public init(fileURL: URL? = nil, inMemory: Bool = false) {
        self.fileURL = inMemory ? nil : fileURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ListsPreview/lists.json")
        do {
            if let url = self.fileURL, FileManager.default.fileExists(atPath: url.path) {
                let saved = try JSONDecoder().decode(SavedPreview.self, from: Data(contentsOf: url))
                var archive = saved.archive
                archive.normalizeOrder()
                try archive.validate()
                boards = archive.boards; connections = saved.connections
            } else {
                boards = ListArchive.sample().boards
                try persist()
            }
        } catch {
            readable = false
            self.error = "Your saved preview could not be opened. The original file is preserved. \(error.localizedDescription)"
        }
    }

    public func board(_ id: UUID?) -> ListBoard? { boards.first { $0.id == id } }
    public func isShared(_ id: UUID) -> Bool { connections[id.uuidString] != nil }
    public func pendingCount(_ id: UUID) -> Int { connections[id.uuidString]?.pending.count ?? 0 }
    public func lists(of kind: ListKind) -> [ListBoard] { ListArchive(boards: boards).boards(of: kind) }
    public var undoSummary: String? { pendingUndo?.summary }

    private func persist() throws {
        guard readable else { throw ListError.invalidData }
        let archive = ListArchive(boards: boards)
        try archive.validate()
        guard let fileURL else { return }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(SavedPreview(archive: archive, connections: connections)).write(to: fileURL, options: .atomic)
    }

    /// Applies every operation as one atomic change and one persisted write.
    /// Operations are queued for publication only when the list is shared.
    @discardableResult private func mutate(boardID: UUID, _ operations: [ListOperation]) -> Bool {
        guard !operations.isEmpty, let index = boards.firstIndex(where: { $0.id == boardID }),
              !blockedIDs.contains(boardID) else { return false }
        let oldBoards = boards; let oldConnections = connections
        do {
            var next = boards[index]
            for operation in operations { try operation.apply(to: &next) }
            boards[index] = next
            if connections[boardID.uuidString] != nil { connections[boardID.uuidString]?.pending.append(contentsOf: operations) }
            try persist()
            return true
        } catch {
            boards = oldBoards; connections = oldConnections
            self.error = "Could not save this change. \(error.localizedDescription)"
            return false
        }
    }

    // MARK: - Items

    @discardableResult public func save(_ item: ListItem, boardID: UUID) -> Bool {
        let base = board(boardID)?.items.first { $0.id == item.id }
        return mutate(boardID: boardID, [ListOperation(kind: "save", item: item, base: base)])
    }
    public func saveDraft(_ item: ListItem, original: ListItem, boardID: UUID) -> Bool {
        let current = board(boardID)?.items.first { $0.id == item.id }
        if !original.text.isEmpty {
            guard let current, current.text == original.text, current.quantity == original.quantity,
                  current.note == original.note, current.steps == original.steps, current.groupID == original.groupID else {
                error = "This item changed on another device. Your draft is still open; copy anything you need before reopening the latest item."
                return false
            }
        }
        return save(item, boardID: boardID)
    }
    public func complete(_ item: ListItem, boardID: UUID) {
        mutate(boardID: boardID, [ListOperation(kind: "complete", itemID: item.id, completed: !item.isCompleted)])
    }
    public func keep(_ item: ListItem, boardID: UUID) {
        mutate(boardID: boardID, [ListOperation(kind: "keep", itemID: item.id)])
    }
    public func remove(_ item: ListItem, boardID: UUID) {
        if mutate(boardID: boardID, [ListOperation(kind: "delete", itemID: item.id)]) {
            pendingUndo = .item(boardID: boardID, item: item)
        }
    }

    /// Moves an item one position inside its group.
    public func moveItem(_ item: ListItem, boardID: UUID, by offset: Int) {
        guard let current = board(boardID) else { return }
        var next = current
        next.moveItem(item.id, by: offset)
        guard next != current else { return }
        mutate(boardID: boardID, reorderOperations(from: current, to: next, groupID: item.groupID))
    }

    /// Moves an item to the end of another group.
    public func moveItem(_ item: ListItem, boardID: UUID, toGroup groupID: UUID) {
        guard let current = board(boardID) else { return }
        var next = current
        do { try next.moveItem(item.id, toGroup: groupID) } catch { self.error = error.localizedDescription; return }
        let moved = next.items.first { $0.id == item.id }
        var operations = reorderOperations(from: current, to: next, groupID: item.groupID)
        if let moved, let before = current.items.first(where: { $0.id == item.id }) {
            operations.append(ListOperation(kind: "save", item: moved, base: before))
        }
        mutate(boardID: boardID, operations)
    }

    public func reorderItems(boardID: UUID, groupID: UUID, fromOffsets: IndexSet, toOffset: Int) {
        guard let current = board(boardID) else { return }
        var next = current
        next.reorderItems(groupID: groupID, fromOffsets: fromOffsets, toOffset: toOffset)
        guard next != current else { return }
        mutate(boardID: boardID, reorderOperations(from: current, to: next, groupID: groupID))
    }

    /// Sends only the rows whose position actually changed.
    private func reorderOperations(from current: ListBoard, to next: ListBoard, groupID: UUID) -> [ListOperation] {
        let previous = Dictionary(uniqueKeysWithValues: current.items(in: groupID).map { ($0.id, $0) })
        return next.items(in: groupID).compactMap { updated in
            guard let before = previous[updated.id], before != updated else { return nil }
            return ListOperation(kind: "save", item: updated, base: before)
        }
    }

    /// Removes every completed item. Undo restores exactly those items.
    public func clearCompleted(boardID: UUID) {
        guard let current = board(boardID) else { return }
        let removed = current.items.filter(\.isCompleted)
        guard !removed.isEmpty else { return }
        if mutate(boardID: boardID, removed.map { ListOperation(kind: "delete", itemID: $0.id) }) {
            pendingUndo = .items(boardID: boardID, items: removed)
        }
    }

    // MARK: - Groups

    @discardableResult public func addGroup(boardID: UUID, title: String) -> UUID? {
        let group = ListGroup(title: title, sortIndex: board(boardID)?.groups.count ?? 0)
        return mutate(boardID: boardID, [ListOperation(kind: "groupSave", group: group)]) ? group.id : nil
    }
    @discardableResult public func renameGroup(boardID: UUID, groupID: UUID, title: String) -> Bool {
        guard var group = board(boardID)?.groups.first(where: { $0.id == groupID }) else { return false }
        group.title = title
        return mutate(boardID: boardID, [ListOperation(kind: "groupSave", group: group)])
    }
    /// Items in a removed group move to the first remaining group, so Undo can
    /// put both the group and its items back where they were.
    public func deleteGroup(boardID: UUID, groupID: UUID) {
        guard let current = board(boardID), let group = current.groups.first(where: { $0.id == groupID }) else { return }
        let items = current.items(in: groupID)
        if mutate(boardID: boardID, [ListOperation(kind: "groupDelete", groupID: groupID)]) {
            pendingUndo = .group(boardID: boardID, group: group, items: items)
        }
    }
    public func moveGroups(boardID: UUID, fromOffsets: IndexSet, toOffset: Int) {
        guard let current = board(boardID) else { return }
        var next = current
        next.moveGroups(fromOffsets: fromOffsets, toOffset: toOffset)
        guard next != current else { return }
        let previous = Dictionary(uniqueKeysWithValues: current.groups.map { ($0.id, $0) })
        let operations = next.orderedGroups.compactMap { group -> ListOperation? in
            guard previous[group.id] != group else { return nil }
            return ListOperation(kind: "groupSave", group: group)
        }
        mutate(boardID: boardID, operations)
    }

    /// Moves a section one position in the list.
    public func moveGroup(_ group: ListGroup, boardID: UUID, by offset: Int) {
        guard let current = board(boardID) else { return }
        let ordered = current.orderedGroups
        guard let position = ordered.firstIndex(where: { $0.id == group.id }) else { return }
        let destination = position + offset
        guard ordered.indices.contains(destination) else { return }
        moveGroups(boardID: boardID, fromOffsets: IndexSet(integer: position), toOffset: offset > 0 ? destination + 1 : destination)
    }

    // MARK: - Lists

    @discardableResult public func createBoard(kind: ListKind, name: String, groupTitle: String) -> UUID? {
        do {
            var archive = ListArchive(boards: boards)
            let board = try archive.addBoard(kind: kind, name: name, groupTitle: groupTitle)
            let previous = boards
            boards = archive.boards
            do { try persist(); return board.id }
            catch { boards = previous; throw error }
        } catch {
            self.error = "Could not create the list. \(error.localizedDescription)"
            return nil
        }
    }

    @discardableResult public func renameBoard(_ id: UUID, to name: String) -> Bool {
        mutate(boardID: id, [ListOperation(kind: "rename", name: name)])
    }

    /// Removes the list from this device. A shared link stays valid for everyone
    /// else; Undo restores the list and its connection here.
    public func deleteBoard(_ id: UUID) {
        guard let index = boards.firstIndex(where: { $0.id == id }) else { return }
        let removed = boards[index]
        let connection = connections[id.uuidString]
        do {
            var archive = ListArchive(boards: boards)
            try archive.removeBoard(id)
            let previous = boards; let previousConnections = connections
            boards = archive.boards
            connections.removeValue(forKey: id.uuidString)
            do { try persist() }
            catch { boards = previous; connections = previousConnections; throw error }
            pendingUndo = .board(board: removed, connection: connection)
        } catch {
            self.error = "Could not remove the list. \(error.localizedDescription)"
        }
    }

    /// List order is a device preference; it is not published to a shared list.
    public func moveBoards(kind: ListKind, fromOffsets: IndexSet, toOffset: Int) {
        var archive = ListArchive(boards: boards)
        archive.moveBoards(kind: kind, fromOffsets: fromOffsets, toOffset: toOffset)
        let previous = boards
        boards = archive.boards
        do { try persist() } catch { boards = previous; self.error = error.localizedDescription }
    }

    public func undo() {
        guard let pending = pendingUndo else { return }
        switch pending {
        case .item(let boardID, let item):
            var copy = item; copy.id = UUID()
            if save(copy, boardID: boardID) { pendingUndo = nil }
        case .items(let boardID, let items):
            var operations: [ListOperation] = []
            for item in items {
                var copy = item; copy.id = UUID()
                operations.append(ListOperation(kind: "save", item: copy, base: nil))
            }
            if mutate(boardID: boardID, operations) { pendingUndo = nil }
        case .group(let boardID, let group, let items):
            let current = board(boardID)?.items ?? []
            var operations = [ListOperation(kind: "groupSave", group: group)]
            for item in items {
                operations.append(ListOperation(kind: "save", item: item, base: current.first { $0.id == item.id }))
            }
            if mutate(boardID: boardID, operations) { pendingUndo = nil }
        case .board(let board, let connection):
            do {
                var archive = ListArchive(boards: boards)
                try archive.insertBoard(board)
                let previous = boards; let previousConnections = connections
                boards = archive.boards
                if let connection { connections[board.id.uuidString] = connection }
                do { try persist() }
                catch { boards = previous; connections = previousConnections; throw error }
                pendingUndo = nil
            } catch {
                self.error = "Could not restore the list. \(error.localizedDescription)"
            }
        }
    }

    public func duplicate(_ id: UUID) -> UUID? {
        guard let source = board(id) else { return nil }
        var copy = source.independentCopy(); copy.name += " (copy)"
        let prior = boards
        boards.append(copy)
        do { try persist(); return copy.id }
        catch { boards = prior; self.error = error.localizedDescription; return nil }
    }

    public func share(boardID: UUID, server: String) async -> URL? {
        if let existing = connections[boardID.uuidString] { return existing.link }
        guard let board = board(boardID), let base = URL(string: server.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["https", "http"].contains(base.scheme), base.host != nil, base.user == nil, base.password == nil else {
            error = "Enter the preview service address, including http:// or https://."; return nil
        }
        do {
            var request = URLRequest(url: base.appendingPathComponent("v1/lists"))
            request.httpMethod = "POST"; request.timeoutInterval = 15
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try ListTransfer(board: board).data()
            let (data, response) = try await URLSession.shared.data(for: request)
            try check(response, data: data)
            struct Created: Decodable { var token: String; var revision: Int }
            let result = try JSONDecoder().decode(Created.self, from: data)
            guard self.board(boardID) == board else {
                error = "The list changed while sharing. Try again to share the latest version."
                return nil
            }
            let link = base.appendingPathComponent("join").appendingPathComponent(result.token)
            connections[boardID.uuidString] = SharedList(link: link, revision: result.revision)
            do { try persist() }
            catch { connections.removeValue(forKey: boardID.uuidString); throw error }
            status = "Shared list ready"
            return link
        } catch { self.error = "Could not share the list. \(error.localizedDescription)"; return nil }
    }

    public func join(_ input: String) async -> UUID? {
        guard let link = URL(string: input.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(link.scheme), link.host != nil,
              link.pathComponents.count == 3, link.pathComponents[1] == "join", link.lastPathComponent.count >= 32 else {
            error = "Paste the complete private list link from the sender."; return nil
        }
        if let match = connections.first(where: { $0.value.link == link }), let id = UUID(uuidString: match.key) { return id }
        do {
            let remote = try await fetch(link)
            try remote.board.validate()
            guard !boards.contains(where: { $0.id == remote.board.id }) else {
                error = "This list is already on this device."; return nil
            }
            let previous = boards; let priorConnections = connections
            boards.append(remote.board)
            connections[remote.board.id.uuidString] = SharedList(link: link, revision: remote.revision)
            do { try persist() }
            catch { boards = previous; connections = priorConnections; throw error }
            return remote.board.id
        } catch { self.error = "Could not open the shared list. \(error.localizedDescription)"; return nil }
    }

    private func endpoint(_ link: URL) -> URL {
        link.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("v1/lists").appendingPathComponent(link.lastPathComponent)
    }
    private func check(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if http.statusCode == 409 { throw SyncError.conflict }
        guard (200..<300).contains(http.statusCode) else { throw SyncError.server(http.statusCode) }
    }
    private func fetch(_ link: URL) async throws -> RemoteList {
        var request = URLRequest(url: endpoint(link)); request.timeoutInterval = 12
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(response, data: data)
        guard data.count < 2_000_000 else { throw ListError.tooLarge }
        return try JSONDecoder().decode(RemoteList.self, from: data)
    }
    public func sync(boardID: UUID) async {
        guard !isSyncing, !blockedIDs.contains(boardID), var connection = connections[boardID.uuidString] else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            // Snapshot the queue. New edits made during requests remain in the persisted queue.
            for operation in connection.pending {
                try Task.checkCancellation()
                var request = URLRequest(url: endpoint(connection.link))
                request.httpMethod = "PATCH"; request.timeoutInterval = 12
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONEncoder().encode(operation)
                let (data, response) = try await URLSession.shared.data(for: request)
                try check(response, data: data)
                let remote = try JSONDecoder().decode(RemoteList.self, from: data)
                try integrate(remote, boardID: boardID, acknowledged: operation.id)
            }
            connection = connections[boardID.uuidString] ?? connection
            let remote = try await fetch(connection.link)
            try Task.checkCancellation()
            try integrate(remote, boardID: boardID, acknowledged: nil)
            status = "Up to date"
        } catch is CancellationError {
            // The durable queue resumes on the next foreground refresh.
        } catch SyncError.conflict {
            blockedIDs.insert(boardID)
            status = "Changes need review"
        } catch {
            status = "Offline · changes saved here"
        }
    }

    private func integrate(_ remote: RemoteList, boardID: UUID, acknowledged: UUID?) throws {
        guard remote.board.id == boardID, let index = boards.firstIndex(where: { $0.id == boardID }),
              var connection = connections[boardID.uuidString] else { throw ListError.invalidData }
        try remote.board.validate()
        let previous = boards; let previousConnections = connections
        if let acknowledged { connection.pending.removeAll { $0.id == acknowledged } }
        var projected = remote.board
        for pending in connection.pending { try pending.apply(to: &projected) }
        connection.revision = remote.revision
        // Quiet polls should not publish changes or rewrite the archive every three seconds.
        guard boards[index] != projected || connections[boardID.uuidString] != connection else { return }
        boards[index] = projected
        connections[boardID.uuidString] = connection
        do { try persist() }
        catch { boards = previous; connections = previousConnections; throw error }
    }

    /// Preserve unsent work as a separate local copy before accepting the shared version.
    public func resolveConflict(_ boardID: UUID) async {
        guard let connection = connections[boardID.uuidString], let index = boards.firstIndex(where: { $0.id == boardID }) else { return }
        do {
            let remote = try await fetch(connection.link)
            try remote.board.validate()
            guard remote.board.id == boardID else { throw ListError.invalidData }
            let previous = boards; let priorConnections = connections
            var backup = boards[index].independentCopy(); backup.name = String((backup.name + " (my edits)").prefix(100))
            boards.append(backup); boards[index] = remote.board
            connections[boardID.uuidString]?.pending = []
            do { try persist() }
            catch { boards = previous; connections = priorConnections; throw error }
            blockedIDs.remove(boardID); status = "Your edits are kept in a local copy"
        } catch { self.error = error.localizedDescription }
    }
}

private enum SyncError: LocalizedError {
    case conflict, server(Int)
    var errorDescription: String? {
        switch self {
        case .conflict: "This list needs review before more changes."
        case .server(let code): "The preview service replied with status \(code)."
        }
    }
}

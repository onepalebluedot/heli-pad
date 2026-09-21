import XCTest
@testable import ListsKit
@testable import ListsUI

final class ListsTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_789_300_000)
    func testReviewUsesInactivityAndNeverCompletedItems() throws {
        var board = ListArchive.sample(now: now).boards[0]
        let old = try XCTUnwrap(board.reviewCandidates(now: now).first)
        XCTAssertEqual(old.text, "Look into a pottery class")
        board.setCompleted(old.id, to: true, now: now)
        XCTAssertTrue(board.reviewCandidates(now: now).isEmpty)
        board.setCompleted(old.id, to: false, now: now)
        XCTAssertTrue(board.reviewCandidates(now: now).isEmpty, "Reopening restarts inactivity")
    }
    func testKeepSuppressesForThirtyDaysWithoutDeleting() throws {
        var board = ListArchive.sample(now: now).boards[1]
        let old = try XCTUnwrap(board.reviewCandidates(now: now).first)
        board.keep(old.id, now: now)
        XCTAssertFalse(board.reviewCandidates(now: now.addingTimeInterval(29 * 86400)).contains { $0.id == old.id })
        XCTAssertEqual(board.reviewCandidates(now: now.addingTimeInterval(31 * 86400)).filter { $0.id == old.id }.count, 1)
        XCTAssertTrue(board.items.contains { $0.id == old.id })
    }
    func testCompletionReplayIsIdempotent() {
        var board = ListArchive.sample(now: now).boards[1]
        let id = board.items[0].id
        board.setCompleted(id, to: true, now: now)
        let first = board
        board.setCompleted(id, to: true, now: now.addingTimeInterval(10))
        XCTAssertEqual(first, board)
    }
    func testInvalidUpsertLeavesBoardUnchanged() {
        var board = ListArchive.sample(now: now).boards[0]
        let original = board
        XCTAssertThrowsError(try board.upsert(ListItem(groupID: board.groups[0].id, text: "   "), now: now))
        XCTAssertEqual(original, board)
    }
    func testCopyHasIndependentIDsAndPreservesSteps() throws {
        let original = ListArchive.sample(now: now).boards[0]
        let copy = original.independentCopy()
        try copy.validate()
        XCTAssertNotEqual(copy.id, original.id)
        XCTAssertTrue(Set(copy.items.map(\.id)).isDisjoint(with: original.items.map(\.id)))
        XCTAssertEqual(copy.items[0].steps.map(\.text), original.items[0].steps.map(\.text))
        XCTAssertNotEqual(copy.items[0].steps[0].id, original.items[0].steps[0].id)
    }
    func testTransferRejectsUnsupportedOrInvalidData() throws {
        let board = ListArchive.sample(now: now).boards[0]
        XCTAssertEqual(try ListTransfer.read(ListTransfer(board: board).data()).board, board)
        var transfer = ListTransfer(board: board); transfer.version = 2
        XCTAssertThrowsError(try ListTransfer.read(JSONEncoder().encode(transfer)))
        var invalid = board; invalid.items[0].groupID = UUID()
        XCTAssertThrowsError(try invalid.validate())
        XCTAssertThrowsError(try ListTransfer.read(Data(repeating: 0, count: 2_000_001)))
    }
    @MainActor func testStorePersistsCompletionRemovalAndUndo() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("lists.json")
        let store = ListStore(fileURL: file)
        let board = store.boards[1]; let item = board.items[0]
        store.complete(item, boardID: board.id)
        XCTAssertTrue(ListStore(fileURL: file).board(board.id)!.items[0].isCompleted)
        store.remove(item, boardID: board.id)
        store.undo()
        let restored = ListStore(fileURL: file).board(board.id)!
        XCTAssertTrue(restored.items.contains { $0.text == item.text })
        XCTAssertFalse(restored.items.contains { $0.id == item.id }, "Undo uses a fresh identity")
    }
    @MainActor func testCorruptStorageIsPreserved() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("lists.json")
        let corrupt = Data("broken".utf8); try corrupt.write(to: file)
        let store = ListStore(fileURL: file)
        XCTAssertNotNil(store.error); XCTAssertTrue(store.boards.isEmpty)
        XCTAssertEqual(try Data(contentsOf: file), corrupt)
    }
    @MainActor func testStaleEditorCannotOverwriteNewerContents() {
        let store = ListStore(inMemory: true)
        let board = store.boards[0], original = board.items[0]
        var newer = original; newer.text = "A newer title"
        store.save(newer, boardID: board.id)
        var draft = original; draft.note = "Unsent draft"
        XCTAssertFalse(store.saveDraft(draft, original: original, boardID: board.id))
        XCTAssertEqual(store.board(board.id)?.items[0].text, newer.text)
        XCTAssertNotNil(store.error)
    }
    @MainActor func testSharedQueueSurvivesRestart() async throws {
        guard let address = ProcessInfo.processInfo.environment["LISTS_TEST_SERVER"] else { throw XCTSkip("Needs preview service") }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("lists.json")
        let first = ListStore(fileURL: file), other = ListStore(inMemory: true)
        let board = first.boards[0]
        let sharedLink = await first.share(boardID: board.id, server: address)
        let link = try XCTUnwrap(sharedLink)
        _ = await other.join(link.absoluteString)
        first.complete(board.items[0], boardID: board.id)
        let restarted = ListStore(fileURL: file)
        XCTAssertEqual(restarted.pendingCount(board.id), 1)
        await restarted.sync(boardID: board.id)
        await other.sync(boardID: board.id)
        XCTAssertEqual(restarted.pendingCount(board.id), 0)
        XCTAssertTrue(other.board(board.id)!.items[0].isCompleted)
    }
    @MainActor func testTwoNativeStoresCollaborateThroughService() async throws {
        guard let address = ProcessInfo.processInfo.environment["LISTS_TEST_SERVER"] else {
            throw XCTSkip("Set LISTS_TEST_SERVER to exercise native clients against the isolated service")
        }
        let a = ListStore(inMemory: true), b = ListStore(inMemory: true)
        let board = a.boards[1]
        let sharedLink = await a.share(boardID: board.id, server: address)
        let link = try XCTUnwrap(sharedLink)
        let joined = await b.join(link.absoluteString)
        XCTAssertEqual(joined, board.id)
        a.complete(board.items[0], boardID: board.id)
        b.complete(board.items[1], boardID: board.id)
        await a.sync(boardID: board.id); await b.sync(boardID: board.id); await a.sync(boardID: board.id)
        XCTAssertEqual(a.board(board.id), b.board(board.id))
        XCTAssertTrue(a.board(board.id)!.items.prefix(2).allSatisfy(\.isCompleted))
        XCTAssertEqual(a.pendingCount(board.id), 0)
        // Same-field conflicting edits are retained until explicit review.
        var left = a.board(board.id)!.items[2]; var right = left
        left.text = "One edit"; right.text = "Another edit"
        a.save(left, boardID: board.id); b.save(right, boardID: board.id)
        await a.sync(boardID: board.id); await b.sync(boardID: board.id)
        XCTAssertTrue(b.blockedIDs.contains(board.id))
        await b.resolveConflict(board.id)
        XCTAssertTrue(b.boards.contains { $0.name.hasSuffix("(my edits)") && $0.items.contains { $0.text == "Another edit" } })
        XCTAssertEqual(b.board(board.id), a.board(board.id))
    }

    @MainActor func testStructuralEditsConvergeAcrossClients() async throws {
        guard let address = ProcessInfo.processInfo.environment["LISTS_TEST_SERVER"] else { throw XCTSkip("Needs preview service") }
        let a = ListStore(inMemory: true), b = ListStore(inMemory: true)
        let board = a.boards[0]
        guard let link = await a.share(boardID: board.id, server: address) else { return XCTFail("share failed: \(a.error ?? "")") }
        let joined = await b.join(link.absoluteString)
        XCTAssertEqual(joined, board.id)
        XCTAssertTrue(a.renameBoard(board.id, to: "House and garden"))
        let group = a.board(board.id)!.orderedGroups[0]
        let items = a.board(board.id)!.items(in: group.id)
        XCTAssertGreaterThanOrEqual(items.count, 2)
        a.moveItem(items[1], boardID: board.id, by: -1)
        a.addGroup(boardID: board.id, title: "Someday soon")
        await a.sync(boardID: board.id); await b.sync(boardID: board.id)
        XCTAssertEqual(b.board(board.id)?.name, "House and garden")
        XCTAssertEqual(b.board(board.id)!.items(in: group.id).map(\.text).prefix(2),
                       a.board(board.id)!.items(in: group.id).map(\.text).prefix(2))
        XCTAssertEqual(b.board(board.id)!.orderedGroups.map(\.title), a.board(board.id)!.orderedGroups.map(\.title))
        XCTAssertEqual(a.board(board.id), b.board(board.id))
    }

    // MARK: - Ordering and list lifecycle

    func testRemovingASectionKeepsItsItems() throws {
        let sample = ListArchive.sample(now: now).boards[1]
        var board = sample
        let removed = board.orderedGroups[1]
        let moved = board.items(in: removed.id).map(\.text)
        XCTAssertFalse(moved.isEmpty)
        try board.removeGroup(removed.id)
        XCTAssertFalse(board.groups.contains { $0.id == removed.id })
        let fallback = board.orderedGroups[0]
        XCTAssertTrue(moved.allSatisfy { text in board.items(in: fallback.id).contains { $0.text == text } })
        XCTAssertEqual(board.items.count, sample.items.count)
        var single = ListBoard(kind: .todos, name: "One", groups: [ListGroup(title: "Only")])
        XCTAssertThrowsError(try single.removeGroup(single.groups[0].id))
    }

    func testStructuralOperationsAreIdempotent() throws {
        var board = ListArchive.sample(now: now).boards[0]
        let rename = ListOperation(kind: "rename", name: "  Weekend  ")
        try rename.apply(to: &board)
        XCTAssertEqual(board.name, "Weekend")
        let once = board
        try rename.apply(to: &board)
        XCTAssertEqual(once, board)
        let group = ListGroup(title: "Later")
        try ListOperation(kind: "groupSave", group: group).apply(to: &board)
        try ListOperation(kind: "groupSave", group: group).apply(to: &board)
        XCTAssertEqual(board.groups.filter { $0.id == group.id }.count, 1)
        try ListOperation(kind: "groupDelete", groupID: group.id).apply(to: &board)
        XCTAssertFalse(board.groups.contains { $0.id == group.id })
    }

    func testDecodingAListWrittenBeforeOrderingExisted() throws {
        let board = ListArchive.sample(now: now).boards[0]
        let legacy = try strippingOrdering(from: board)
        let decoded = try JSONDecoder().decode(ListBoard.self, from: legacy)
        XCTAssertTrue(decoded.groups.allSatisfy { $0.sortIndex == 0 })
        XCTAssertTrue(decoded.items.allSatisfy { $0.sortIndex == 0 })
        XCTAssertEqual(decoded.orderedGroups.map(\.title), board.orderedGroups.map(\.title))
        for group in board.orderedGroups {
            XCTAssertEqual(decoded.items(in: group.id).map(\.text), board.items(in: group.id).map(\.text))
        }
    }

    @MainActor func testStoreOpensAFileWrittenBeforeOrderingExisted() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("lists.json")
        let board = ListArchive.sample(now: now).boards[1]
        let saved: [String: Any] = ["archive": ["version": 1, "boards": [try JSONSerialization.jsonObject(with: strippingOrdering(from: board))]],
                                    "connections": [String: Any]()]
        try JSONSerialization.data(withJSONObject: saved).write(to: file)
        let store = ListStore(fileURL: file)
        XCTAssertNil(store.error, "An older file must still open")
        let loaded = try XCTUnwrap(store.boards.first)
        XCTAssertEqual(loaded.name, board.name)
        XCTAssertEqual(loaded.orderedGroups.map(\.title), board.orderedGroups.map(\.title))
        XCTAssertEqual(loaded.items(in: board.orderedGroups[0].id).map(\.text), board.items(in: board.orderedGroups[0].id).map(\.text))
    }

    @MainActor func testCreatingRenamingReorderingAndDeletingLists() throws {
        let store = ListStore(inMemory: true)
        let created = try XCTUnwrap(store.createBoard(kind: .todos, name: "House projects", groupTitle: "This week"))
        XCTAssertEqual(store.lists(of: .todos).last?.name, "House projects")
        XCTAssertEqual(store.board(created)?.orderedGroups.map(\.title), ["This week"])
        XCTAssertTrue(store.renameBoard(created, to: "House and garden"))
        XCTAssertEqual(store.board(created)?.name, "House and garden")
        store.moveBoards(kind: .todos, fromOffsets: IndexSet(integer: store.lists(of: .todos).count - 1), toOffset: 0)
        XCTAssertEqual(store.lists(of: .todos).first?.id, created)
        store.deleteBoard(created)
        XCTAssertNil(store.board(created))
        XCTAssertEqual(store.pendingUndo?.summary, "Removed House and garden")
        store.undo()
        XCTAssertEqual(store.board(created)?.name, "House and garden")
        XCTAssertEqual(store.lists(of: .todos).first?.id, created, "Undo restores the previous position")
    }

    @MainActor func testAddingAndRenamingASectionPersists() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("lists.json")
        let store = ListStore(fileURL: file)
        let board = store.boards[0]
        let group = try XCTUnwrap(store.addGroup(boardID: board.id, title: "Someday"))
        XCTAssertEqual(store.board(board.id)?.orderedGroups.last?.title, "Someday")
        XCTAssertTrue(store.renameGroup(boardID: board.id, groupID: group, title: "Someday soon"))
        let reopened = ListStore(fileURL: file)
        XCTAssertEqual(reopened.board(board.id)?.orderedGroups.last?.title, "Someday soon")
        store.deleteGroup(boardID: board.id, groupID: group)
        let afterDelete = ListStore(fileURL: file)
        XCTAssertNil(afterDelete.board(board.id)?.groups.first { $0.id == group })
    }

    @MainActor func testReorderingThroughTheStoreIsNotAnEdit() throws {
        let store = ListStore(inMemory: true)
        let board = store.boards[0]
        let group = board.orderedGroups[0]
        let before = board.items(in: group.id)
        try XCTSkipUnless(before.count >= 2, "Needs two items in one section")
        store.moveItem(before[1], boardID: board.id, by: -1)
        let after = try XCTUnwrap(store.board(board.id)).items(in: group.id)
        XCTAssertEqual(after.map(\.text), [before[1].text, before[0].text] + before.dropFirst(2).map(\.text))
        XCTAssertEqual(after.map(\.sortIndex), Array(0..<after.count))
        XCTAssertEqual(after[0].updatedAt, before[1].updatedAt, "A move must not restart the inactivity clock")
    }

    @MainActor func testClearingCompletedRestoresExactlyThoseItems() throws {
        let store = ListStore(inMemory: true)
        let board = store.boards[0]
        let completed = board.items.filter(\.isCompleted)
        XCTAssertFalse(completed.isEmpty)
        store.clearCompleted(boardID: board.id)
        XCTAssertTrue(try XCTUnwrap(store.board(board.id)).items.allSatisfy { !$0.isCompleted })
        XCTAssertEqual(store.pendingUndo?.summary, "Removed \(completed.count) item\(completed.count == 1 ? "" : "s")")
        store.undo()
        let restored = try XCTUnwrap(store.board(board.id)).items.filter(\.isCompleted)
        XCTAssertEqual(restored.map(\.text).sorted(), completed.map(\.text).sorted())
        XCTAssertTrue(restored.allSatisfy { item in !completed.contains { $0.id == item.id } }, "Undo uses fresh identities")
    }

    /// The stored shape from before ordering keys existed.
    private func strippingOrdering(from board: ListBoard) throws -> Data {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(board)) as? [String: Any])
        json.removeValue(forKey: "sortIndex")
        json["groups"] = (json["groups"] as? [[String: Any]])?.map { group in
            var group = group; group.removeValue(forKey: "sortIndex"); return group
        }
        json["items"] = (json["items"] as? [[String: Any]])?.map { item in
            var item = item; item.removeValue(forKey: "sortIndex"); return item
        }
        return try JSONSerialization.data(withJSONObject: json)
    }
}

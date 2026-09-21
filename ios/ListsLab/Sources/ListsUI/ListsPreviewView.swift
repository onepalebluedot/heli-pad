import SwiftUI
import ListsKit

#if os(iOS)

@MainActor public struct ListsPreviewView: View {
    @StateObject private var store: ListStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var kind: ListKind = .todos
    @State private var selected: [ListKind: UUID] = [:]
    @State private var openGroups: Set<UUID> = []
    @State private var openSteps: Set<UUID> = []
    @State private var showCompleted = false
    @State private var drafts: [UUID: String] = [:]
    @State private var addTarget: [UUID: UUID] = [:]
    @State private var editing: ListItem?
    @State private var showShare = false
    @State private var showJoin = false
    @State private var showReview = false
    @State private var showIndex = false
    @State private var creating: ListKind?
    @State private var renamingGroup: ListGroup?
    @State private var isAddingGroup = false
    @State private var groupDraft = ""
    @State private var duplicate: (text: String, existing: ListItem)?
    @FocusState private var adding: Bool

    public init(store: ListStore = ListStore()) { _store = StateObject(wrappedValue: store) }

    private var lists: [ListBoard] { store.lists(of: kind) }
    private var board: ListBoard? { store.board(selected[kind]) ?? lists.first }
    private var boardID: UUID? { board?.id }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    Picker("List type", selection: $kind) {
                        ForEach(ListKind.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("list-kind")

                    if lists.count > 1 { listStrip }

                    if let board {
                        listHeading(board)
                        if store.blockedIDs.contains(board.id) { conflictNotice(board) }
                        if !board.reviewCandidates(now: Date()).isEmpty { reviewNotice(board) }
                        if board.items.allSatisfy(\.isCompleted) { emptyState }
                        LazyVStack(spacing: 12) {
                            ForEach(board.orderedGroups) { group in
                                let items = activeItems(board, in: group)
                                if !items.isEmpty { groupCard(group, items: items, board: board) }
                            }
                            addGroupRow(board)
                            completedSection(board)
                        }
                        Text("A place for everyday things. No dates needed.")
                            .font(.footnote).foregroundStyle(Palette.muted)
                            .frame(maxWidth: .infinity).padding(.top, 6)
                    } else {
                        emptyArchiveState
                    }
                }
                .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 28)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
            }
            .background(Palette.canvas)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) { captureBar }
            .toolbar(.hidden, for: .navigationBar)
            .tint(Palette.forest)
            .sheet(item: $editing) { item in
                if let board {
                    ItemEditor(item: item, board: board, onSave: { store.saveDraft($0, original: item, boardID: board.id) }, onDelete: {
                        store.remove(item, boardID: board.id)
                    })
                }
            }
            .sheet(isPresented: $showShare) {
                if let board { ShareListSheet(store: store, boardID: board.id) }
            }
            .sheet(isPresented: $showJoin) {
                JoinListSheet(store: store) { id in
                    if let joined = store.board(id) { kind = joined.kind; selected[joined.kind] = id; expandFirst(joined) }
                }
            }
            .sheet(isPresented: $showReview) {
                if let board { ReviewSheet(store: store, boardID: board.id) }
            }
            .sheet(isPresented: $showIndex) {
                ListsIndexView(store: store, kind: $kind, selected: $selected)
            }
            .sheet(item: $creating) { target in
                NewListSheet(kind: target) { name, groupTitle in
                    if let id = store.createBoard(kind: target, name: name, groupTitle: groupTitle) {
                        kind = target; selected[target] = id
                    }
                }
            }
            .alert("Lists Preview", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(store.error ?? "") }
            .alert("Rename section", isPresented: Binding(get: { renamingGroup != nil }, set: { if !$0 { renamingGroup = nil } })) {
                TextField("Section name", text: $groupDraft)
                Button("Save") {
                    if let board, let group = renamingGroup { store.renameGroup(boardID: board.id, groupID: group.id, title: groupDraft) }
                    renamingGroup = nil
                }
                Button("Cancel", role: .cancel) { renamingGroup = nil }
            }
            .alert("New section", isPresented: $isAddingGroup) {
                TextField("Fruit & vegetables", text: $groupDraft)
                Button("Add") {
                    if let board { store.addGroup(boardID: board.id, title: groupDraft) }
                    isAddingGroup = false
                }
                Button("Cancel", role: .cancel) { isAddingGroup = false }
            } message: {
                Text("Sections group items inside this list.")
            }
            .confirmationDialog(duplicate.map { "\($0.text) is already on this list" } ?? "",
                                isPresented: Binding(get: { duplicate != nil }, set: { if !$0 { duplicate = nil } }),
                                titleVisibility: .visible) {
                Button("Update quantity") {
                    let existing = duplicate?.existing
                    duplicate = nil
                    editing = existing
                }
                Button("Add another") {
                    let text = duplicate?.text ?? ""
                    duplicate = nil
                    addItem(text, force: true)
                }
                Button("Cancel", role: .cancel) { duplicate = nil }
            } message: {
                Text("Nothing is combined automatically.")
            }
            .onAppear { if let board { expandFirst(board) } }
            .onChange(of: kind) { _, _ in
                if let board { expandFirst(board) }
                showCompleted = false
            }
            .onChange(of: boardID) { _, _ in showCompleted = false }
            .task(id: "\(boardID?.uuidString ?? "")|\(scenePhase == .active)") {
                guard scenePhase == .active, let id = boardID else { return }
                while !Task.isCancelled {
                    await store.sync(boardID: id)
                    do { try await Task.sleep(for: .seconds(store.status.hasPrefix("Offline") ? 12 : 3)) }
                    catch { return }
                }
            }
            .onOpenURL { url in
                let raw = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "url" }?.value
                guard let raw else { return }
                Task {
                    if let id = await store.join(raw), let joined = store.board(id) {
                        kind = joined.kind; selected[joined.kind] = id; expandFirst(joined)
                    }
                }
            }
        }
        .preferredColorScheme(.light)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 7) {
                    Image(systemName: "leaf").foregroundStyle(Palette.forest)
                    Text("HELIPAD").tracking(2).font(.caption.weight(.bold))
                }
                Spacer()
                Text("Lists preview").font(.caption.weight(.medium))
                    .padding(.horizontal, 11).padding(.vertical, 6)
                    .background(Palette.sage, in: Capsule())
            }.foregroundStyle(Palette.muted)
            HStack(alignment: .center) {
                Text("Your lists").font(.largeTitle.weight(.regular).width(.standard)).fontDesign(.serif)
                    .foregroundStyle(Palette.ink)
                Spacer()
                Button { creating = kind } label: {
                    Image(systemName: "plus").font(.title3)
                        .frame(width: 46, height: 46).background(Palette.card, in: Circle())
                        .overlay(Circle().stroke(Palette.rule, lineWidth: 1))
                }.accessibilityLabel("New \(kind.title.lowercased()) list").accessibilityIdentifier("new-list")
                Button { showShare = true } label: {
                    Image(systemName: "square.and.arrow.up").font(.title3)
                        .frame(width: 46, height: 46).background(Palette.card, in: Circle())
                        .overlay(Circle().stroke(Palette.rule, lineWidth: 1))
                }.accessibilityLabel("Share this list").accessibilityIdentifier("share-list")
                Menu {
                    Button("All lists", systemImage: "list.bullet") { showIndex = true }
                    Button("New list", systemImage: "plus") { creating = kind }
                    Button("Join a shared list", systemImage: "link") { showJoin = true }
                    if let board {
                        Button("Make a private copy", systemImage: "doc.on.doc") {
                            if let id = store.duplicate(board.id) { selected[kind] = id }
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis").font(.title3).frame(width: 44, height: 46)
                }.accessibilityLabel("List options")
            }
        }
    }

    /// One-tap switching when a category holds more than one list.
    private var listStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(lists) { choice in
                    let current = choice.id == boardID
                    Button {
                        selected[kind] = choice.id
                        expandFirst(choice)
                    } label: {
                        HStack(spacing: 7) {
                            Text(choice.name).font(.subheadline.weight(current ? .semibold : .regular))
                            Text("\(choice.items.filter { !$0.isCompleted }.count)")
                                .font(.caption.monospacedDigit()).opacity(0.75)
                        }
                        .padding(.horizontal, 14).frame(minHeight: 44)
                        .foregroundStyle(current ? Color.white : Palette.ink)
                        .background(current ? Palette.forest : Palette.card, in: Capsule())
                        .overlay(Capsule().stroke(current ? Color.clear : Palette.rule, lineWidth: 1))
                    }
                    .accessibilityLabel("\(choice.name), \(choice.items.filter { !$0.isCompleted }.count) remaining\(current ? ", open" : "")")
                }
            }
            .padding(.horizontal, 1).padding(.vertical, 2)
        }
    }

    private func listHeading(_ board: ListBoard) -> some View {
        let remaining = board.items.filter { !$0.isCompleted }.count
        return HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Button { showIndex = true } label: {
                    HStack(spacing: 6) {
                        Text(board.name).font(.title2.weight(.semibold)).fontDesign(.serif)
                        Image(systemName: "chevron.down").font(.caption.weight(.bold))
                    }.foregroundStyle(Palette.ink)
                }
                .accessibilityLabel("Switch list. \(board.name) is open")
                .accessibilityIdentifier("open-lists-index")
                Text("\(remaining) \(kind == .groceries ? "to pick up" : "still to do")")
                    .font(.subheadline).foregroundStyle(Palette.muted)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                Label(store.isShared(board.id) ? "Shared" : "Personal", systemImage: store.isShared(board.id) ? "person.2" : "lock")
                    .font(.caption.weight(.medium)).foregroundStyle(Palette.forest)
                    .padding(.horizontal, 10).padding(.vertical, 7).background(Palette.sage, in: Capsule())
                if store.isShared(board.id) {
                    Text(store.pendingCount(board.id) > 0 ? "\(store.pendingCount(board.id)) waiting to sync" : store.status)
                        .font(.caption2).foregroundStyle(Palette.muted)
                }
            }
        }
    }

    // MARK: - Notices

    private func reviewNotice(_ board: ListBoard) -> some View {
        Button { showReview = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "leaf.circle").font(.title2)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Still need these?").font(.subheadline.weight(.semibold))
                    let count = board.reviewCandidates(now: Date()).count
                    Text("\(count) \(count == 1 ? "item has" : "items have") been here a while.").font(.subheadline)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold))
            }.foregroundStyle(Palette.ink).padding(16)
                .background(Palette.butter, in: RoundedRectangle(cornerRadius: 18))
        }.buttonStyle(.plain).accessibilityIdentifier("review-old-items")
    }

    private func conflictNotice(_ board: ListBoard) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Someone changed an item you edited.").font(.subheadline.weight(.semibold))
            Text("Keep your edits in a private copy, then load the latest shared list.").font(.subheadline)
            Button("Keep my copy & refresh") { Task { await store.resolveConflict(board.id) } }
                .buttonStyle(.bordered)
        }.padding(16).background(Palette.butter, in: RoundedRectangle(cornerRadius: 18))
    }

    // MARK: - Groups

    private func groupCard(_ group: ListGroup, items: [ListItem], board: ListBoard) -> some View {
        let expanded = openGroups.contains(group.id)
        return VStack(spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                    if expanded { openGroups.remove(group.id) } else { openGroups.insert(group.id) }
                }
            } label: {
                HStack(spacing: 10) {
                    Circle().fill(groupColor(group, board: board)).frame(width: 7, height: 7)
                    Text(group.title).font(.headline).foregroundStyle(Palette.ink)
                    Spacer()
                    Text("\(items.count)").font(.subheadline.monospacedDigit()).foregroundStyle(Palette.muted)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.caption.weight(.bold)).foregroundStyle(Palette.muted)
                }.padding(17).frame(minHeight: 58)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(group.title), \(items.count) items, \(expanded ? "expanded" : "collapsed")")
            .contextMenu {
                Button("Rename section", systemImage: "pencil") { groupDraft = group.title; renamingGroup = group }
                Button("Move up", systemImage: "arrow.up") { store.moveGroup(group, boardID: board.id, by: -1) }
                Button("Move down", systemImage: "arrow.down") { store.moveGroup(group, boardID: board.id, by: 1) }
                if board.orderedGroups.count > 1 {
                    Button("Delete section", systemImage: "trash", role: .destructive) {
                        store.deleteGroup(boardID: board.id, groupID: group.id)
                    }
                }
            }
            if expanded {
                ForEach(items) { item in
                    Divider().overlay(Palette.rule).padding(.horizontal, 17)
                    itemRow(item, board: board)
                }
                Button {
                    editing = ListItem(groupID: group.id, text: "")
                } label: {
                    Label("Add to \(group.title.lowercased())", systemImage: "plus")
                        .font(.subheadline).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).frame(minHeight: 48)
                }.disabled(store.blockedIDs.contains(board.id))
            }
        }
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Palette.rule, lineWidth: 1))
    }

    private func addGroupRow(_ board: ListBoard) -> some View {
        Button {
            groupDraft = ""
            isAddingGroup = true
        } label: {
            Label("Add a section", systemImage: "plus.circle")
                .font(.subheadline).foregroundStyle(Palette.forest)
                .frame(maxWidth: .infinity, alignment: .leading).frame(minHeight: 48)
                .padding(.horizontal, 6)
        }
        .disabled(store.blockedIDs.contains(board.id) || board.groups.count >= 30)
    }

    // MARK: - Rows

    private func itemRow(_ item: ListItem, board: ListBoard) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 2) {
                Button { store.complete(item, boardID: board.id) } label: {
                    Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.title2.weight(.light)).foregroundStyle(item.isCompleted ? Palette.forest : Palette.muted.opacity(0.7))
                        .frame(width: 48, height: 52)
                }.accessibilityLabel("\(item.isCompleted ? "Reopen" : "Complete") \(item.text)")
                    .accessibilityValue(item.isCompleted ? "Checked" : "Unchecked")
                    .accessibilityIdentifier("check-\(item.text)")
                Button { editing = item } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.text).font(.body).strikethrough(item.isCompleted).foregroundStyle(item.isCompleted ? Palette.muted : Palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        if !item.quantity.isEmpty { Text(item.quantity).font(.subheadline).foregroundStyle(Palette.muted) }
                        if !item.steps.isEmpty {
                            Text("\(item.steps.filter(\.isCompleted).count) of \(item.steps.count) steps")
                                .font(.subheadline).foregroundStyle(Palette.muted)
                        } else if !item.note.isEmpty {
                            Text(item.note).font(.subheadline).foregroundStyle(Palette.muted).lineLimit(1)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 16)
                }.buttonStyle(.plain).accessibilityLabel("Edit \(item.text)")
                if !item.steps.isEmpty && !item.isCompleted {
                    Button {
                        if openSteps.contains(item.id) { openSteps.remove(item.id) } else { openSteps.insert(item.id) }
                    } label: { Image(systemName: openSteps.contains(item.id) ? "chevron.up" : "chevron.down").font(.caption).frame(width: 44, height: 48) }
                        .accessibilityLabel("\(openSteps.contains(item.id) ? "Collapse" : "Expand") steps for \(item.text)")
                } else { Spacer().frame(width: 14) }
            }.padding(.leading, 7)
            .contextMenu { itemMenu(item, board: board) }
            if openSteps.contains(item.id) && !item.isCompleted {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(item.steps) { step in
                        Button {
                            var edited = item
                            if let i = edited.steps.firstIndex(where: { $0.id == step.id }) { edited.steps[i].isCompleted.toggle() }
                            store.save(edited, boardID: board.id)
                        } label: {
                            HStack(alignment: .center, spacing: 10) {
                                Image(systemName: step.isCompleted ? "checkmark.circle.fill" : "circle").font(.body)
                                Text(step.text).font(.subheadline).strikethrough(step.isCompleted).multilineTextAlignment(.leading)
                            }.foregroundStyle(step.isCompleted ? Palette.muted : Palette.ink).frame(minHeight: 44)
                        }.accessibilityLabel("\(step.isCompleted ? "Reopen" : "Complete") step: \(step.text)")
                    }
                }.padding(.leading, 57).padding(.trailing, 16).padding(.bottom, 12)
            }
        }.disabled(store.blockedIDs.contains(board.id))
    }

    @ViewBuilder
    private func itemMenu(_ item: ListItem, board: ListBoard) -> some View {
        Button("Edit", systemImage: "square.and.pencil") { editing = item }
        Button("Move up", systemImage: "arrow.up") { store.moveItem(item, boardID: board.id, by: -1) }
        Button("Move down", systemImage: "arrow.down") { store.moveItem(item, boardID: board.id, by: 1) }
        if board.orderedGroups.count > 1 {
            Menu("Move to section") {
                ForEach(board.orderedGroups) { group in
                    Button(group.title) { store.moveItem(item, boardID: board.id, toGroup: group.id) }
                        .disabled(group.id == item.groupID)
                }
            }
        }
        Button("Remove", systemImage: "trash", role: .destructive) { store.remove(item, boardID: board.id) }
    }

    private func completedSection(_ board: ListBoard) -> some View {
        let completed = board.orderedGroups.flatMap { board.items(in: $0.id) }.filter(\.isCompleted)
        return VStack(spacing: 0) {
            if !completed.isEmpty {
                DisclosureGroup(isExpanded: $showCompleted) {
                    ForEach(completed) { item in itemRow(item, board: board) }
                    Button("Clear \(kind == .groceries ? "purchased" : "completed")", systemImage: "trash", role: .destructive) {
                        store.clearCompleted(boardID: board.id)
                    }
                    .font(.subheadline).frame(minHeight: 44)
                } label: {
                    Label("\(kind == .groceries ? "Purchased" : "Completed") · \(completed.count)", systemImage: "checkmark.circle")
                        .font(.subheadline.weight(.medium)).foregroundStyle(Palette.muted).padding(.vertical, 12)
                }.padding(.horizontal, 8)
            }
        }
    }

    // MARK: - Empty states

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: kind == .groceries ? "basket" : "checkmark.seal").font(.largeTitle.weight(.light))
            Text(kind == .groceries ? "Nothing to pick up" : "A little breathing room")
                .font(.title2).fontDesign(.serif)
            Text("Add something below whenever it comes to mind.").font(.body).multilineTextAlignment(.center)
        }.foregroundStyle(Palette.muted).frame(maxWidth: .infinity).padding(.vertical, 36)
    }

    private var emptyArchiveState: some View {
        VStack(spacing: 14) {
            Image(systemName: "list.bullet.rectangle").font(.largeTitle.weight(.light)).foregroundStyle(Palette.forest)
            Text(store.error == nil ? "No lists yet" : "Your lists are unavailable").font(.title2).fontDesign(.serif)
            Text(store.error == nil
                 ? "Create a to-do list or a grocery list to get started."
                 : "Your saved file has been preserved. Reopen the preview to try again.")
                .font(.body).multilineTextAlignment(.center).foregroundStyle(Palette.muted)
            if store.error == nil {
                Button { creating = kind } label: { Label("New list", systemImage: "plus") }
                    .buttonStyle(.borderedProminent).frame(minHeight: 44)
            }
        }.frame(maxWidth: .infinity).padding(.vertical, 36)
    }

    // MARK: - Capture

    private var captureBar: some View {
        VStack(spacing: 8) {
            if let summary = store.undoSummary {
                HStack {
                    Text(summary).font(.subheadline).lineLimit(1)
                    Spacer()
                    Button("Undo") { store.undo() }.font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                }.padding(.horizontal, 18)
            }
            if let board, board.orderedGroups.count > 1 {
                Menu {
                    ForEach(board.orderedGroups) { group in
                        Button(group.title) {
                            addTarget[board.id] = group.id
                            openGroups.insert(group.id)
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.turn.down.right").font(.caption2)
                        Text(targetGroup(board)?.title ?? "Section").font(.caption.weight(.medium))
                        Image(systemName: "chevron.up.chevron.down").font(.caption2)
                    }
                    .foregroundStyle(Palette.forest)
                    .padding(.horizontal, 11).frame(minHeight: 34)
                    .background(Palette.sage, in: Capsule())
                }
                .accessibilityLabel("New items go to \(targetGroup(board)?.title ?? "the first section")")
                .accessibilityIdentifier("add-target")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
            }
            HStack(spacing: 8) {
                TextField(kind == .groceries ? "Add a grocery item…" : "Add a to-do…", text: draftBinding(board))
                    .font(.body).focused($adding).submitLabel(.done).onSubmit { quickAdd() }
                    .accessibilityIdentifier("quick-add")
                Button(action: quickAdd) {
                    Image(systemName: "plus").font(.title3.weight(.medium)).foregroundStyle(.white)
                        .frame(width: 46, height: 46).background(Palette.forest, in: Circle())
                }.accessibilityLabel("Add item").disabled(currentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || board == nil)
            }
            .padding(.leading, 20).padding(.trailing, 7).padding(.vertical, 7)
            .background(Palette.card, in: Capsule()).overlay(Capsule().stroke(Palette.rule, lineWidth: 1))
            .padding(.horizontal, 18)
        }.padding(.top, 10).padding(.bottom, 8).frame(maxWidth: 680).frame(maxWidth: .infinity)
            .background(Palette.canvas)
    }

    // MARK: - Actions

    private func activeItems(_ board: ListBoard, in group: ListGroup) -> [ListItem] {
        board.items(in: group.id).filter { !$0.isCompleted }
    }

    private func draftBinding(_ board: ListBoard?) -> Binding<String> {
        guard let board else { return .constant("") }
        return Binding(get: { drafts[board.id] ?? "" }, set: { drafts[board.id] = $0 })
    }

    private var currentDraft: String { board.map { drafts[$0.id] ?? "" } ?? "" }

    private func targetGroup(_ board: ListBoard) -> ListGroup? {
        if let chosen = addTarget[board.id], let match = board.orderedGroups.first(where: { $0.id == chosen }) { return match }
        return board.orderedGroups.first
    }

    private func quickAdd() {
        guard let board else { return }
        addItem(drafts[board.id] ?? "")
    }

    private func addItem(_ raw: String, force: Bool = false) {
        guard let board, let group = targetGroup(board), !store.blockedIDs.contains(board.id) else { return }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if !force, board.kind == .groceries,
           let existing = board.items.first(where: { !$0.isCompleted && normalized($0.text) == normalized(text) }) {
            duplicate = (text, existing)
            return
        }
        let item = ListItem(groupID: group.id, text: text)
        store.save(item, boardID: board.id)
        if store.board(board.id)?.items.contains(where: { $0.id == item.id }) == true {
            drafts[board.id] = ""
            openGroups.insert(group.id)
        }
    }

    private func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func expandFirst(_ board: ListBoard) {
        if let first = board.orderedGroups.first { openGroups.insert(first.id) }
    }

    private func groupColor(_ group: ListGroup, board: ListBoard) -> Color {
        let colors = [Color(red: 0.5, green: 0.64, blue: 0.46), Color(red: 0.5, green: 0.62, blue: 0.68), Color(red: 0.72, green: 0.61, blue: 0.43)]
        return colors[(board.orderedGroups.firstIndex(where: { $0.id == group.id }) ?? 0) % colors.count]
    }
}

@MainActor private struct ItemEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var item: ListItem
    let board: ListBoard
    let onSave: (ListItem) -> Bool
    let onDelete: () -> Void
    @State private var newStep = ""
    @State private var saveFailed = false
    private var existing: Bool { board.items.contains { $0.id == item.id } }
    var body: some View {
        NavigationStack {
            Form {
                if saveFailed {
                    Text("Could not save. This item may have changed on another device, or a field is too long. Your draft is still here. Copy anything you need before reopening the latest item.")
                        .foregroundStyle(.red)
                }
                Section {
                    TextField("What needs doing?", text: $item.text, axis: .vertical).font(.title3)
                    if board.kind == .groceries { TextField("Quantity (optional)", text: $item.quantity) }
                    Picker("Section", selection: $item.groupID) { ForEach(board.orderedGroups) { Text($0.title).tag($0.id) } }
                    TextField("A note, if you need one", text: $item.note, axis: .vertical).lineLimit(2...5)
                }
                if board.kind == .todos {
                    Section {
                        ForEach($item.steps) { $step in
                            HStack {
                                Button { step.isCompleted.toggle() } label: {
                                    Image(systemName: step.isCompleted ? "checkmark.circle.fill" : "circle").frame(width: 44, height: 44)
                                }.buttonStyle(.plain).accessibilityLabel("Toggle \(step.text)")
                                TextField("Step", text: $step.text)
                            }
                        }.onDelete { item.steps.remove(atOffsets: $0) }
                        if item.steps.count < 20 {
                            HStack {
                                TextField("Add a small step", text: $newStep).onSubmit(addStep)
                                Button(action: addStep) { Image(systemName: "plus.circle.fill").frame(width: 44, height: 44) }
                                    .accessibilityLabel("Add step").disabled(newStep.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }
                    } header: { Text("Break it down") } footer: { Text("Steps tuck inside this to-do. Swipe a step to remove it.") }
                }
                if existing {
                    Section {
                        Button("Remove item", role: .destructive) { onDelete(); dismiss() }
                    }
                }
            }.scrollContentBackground(.hidden).background(Palette.canvas)
                .navigationTitle(existing ? "Item details" : "New item").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { addStep(); if onSave(item) { dismiss() } else { saveFailed = true } }.fontWeight(.semibold)
                            .disabled(item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || item.text.count > 200 || item.steps.contains { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
                    }
                }.tint(Palette.forest)
        }
    }
    private func addStep() {
        let text = newStep.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, item.steps.count < 20 else { return }
        item.steps.append(ListStep(text: text)); newStep = ""
    }
}

@MainActor private struct ReviewSheet: View {
    @ObservedObject var store: ListStore
    let boardID: UUID
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Image(systemName: "leaf.circle").font(.system(size: 42, weight: .light)).foregroundStyle(Palette.forest)
                    Text("Make a little space").font(.largeTitle).fontDesign(.serif)
                    if let board = store.board(boardID) {
                        Text("These haven't changed in at least \(board.kind.reviewDays) days. Keep what matters, let go of the rest.")
                            .font(.body).foregroundStyle(Palette.muted)
                        let candidates = board.reviewCandidates(now: Date())
                        if candidates.isEmpty { Label("All caught up", systemImage: "checkmark.circle").padding(.vertical, 24) }
                        ForEach(candidates.prefix(10)) { item in
                            VStack(alignment: .leading, spacing: 14) {
                                Text(item.text).font(.headline)
                                Text("Unchanged for \(max(0, Calendar.current.dateComponents([.day], from: item.updatedAt, to: Date()).day ?? 0)) days")
                                    .font(.subheadline).foregroundStyle(Palette.muted)
                                HStack(spacing: 12) {
                                    Button("Keep for now") { store.keep(item, boardID: boardID) }.buttonStyle(.borderedProminent)
                                    Button("Remove", role: .destructive) { store.remove(item, boardID: boardID) }.buttonStyle(.bordered)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
                                .background(Palette.card, in: RoundedRectangle(cornerRadius: 18))
                        }
                        if candidates.count > 10 { Text("Review these first; more will appear as you go.").font(.footnote) }
                    }
                    if store.pendingUndo != nil { Button("Undo last removal") { store.undo() }.buttonStyle(.bordered) }
                    Text("Keeping an item pauses its suggestion for 30 days. Nothing is removed automatically.")
                        .font(.footnote).foregroundStyle(Palette.muted)
                }.padding(24)
            }.background(Palette.canvas).tint(Palette.forest)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

@MainActor private struct ShareListSheet: View {
    @ObservedObject var store: ListStore
    let boardID: UUID
    @Environment(\.dismiss) private var dismiss
    @AppStorage("lists-preview-service") private var service = "http://localhost:8788"
    @State private var working = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("A list you can both use").font(.title2).fontDesign(.serif)
                    Text("Check things off together. Changes appear while the list is open, and offline edits wait safely on this device.").font(.body)
                }
                if let link = store.connections[boardID.uuidString]?.link {
                    Section {
                        ShareLink(item: link) { Label("Share private link", systemImage: "square.and.arrow.up") }
                            .frame(minHeight: 44)
                        Text(link.absoluteString).font(.footnote).textSelection(.enabled)
                    } footer: {
                        Text("Anyone with this link can read and edit this list. Only send it to people you trust. The preview service must be reachable from both devices.")
                    }
                } else {
                    Section {
                        TextField("http://your-mac.local:8788", text: $service)
                            .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                        Button {
                            working = true
                            Task { _ = await store.share(boardID: boardID, server: service); working = false }
                        } label: {
                            HStack { Text("Create shared list"); Spacer(); if working { ProgressView() } }
                        }.disabled(working).frame(minHeight: 44)
                    } header: { Text("Preview service") } footer: { Text("For this standalone test, run the included preview service on your Mac. On a phone, use your Mac's network address. This does not connect to HeliPad.") }
                }
                if let board = store.board(boardID) {
                    Section {
                        ShareLink(item: board.plainText) { Label("Send a text copy instead", systemImage: "text.alignleft") }.frame(minHeight: 44)
                    } footer: { Text("Text copies include active items and notes. They do not update together.") }
                }
                if let error = store.error { Text(error).foregroundStyle(.red).font(.subheadline) }
            }.scrollContentBackground(.hidden).background(Palette.canvas).tint(Palette.forest)
                .navigationTitle("Share list").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

@MainActor private struct JoinListSheet: View {
    @ObservedObject var store: ListStore
    let onJoined: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var link = ""
    @State private var working = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Keep the same list").font(.title2).fontDesign(.serif)
                    Text("Paste a private link to add the shared list alongside your own.")
                    TextField("Private list link", text: $link).textInputAutocapitalization(.never)
                        .autocorrectionDisabled().keyboardType(.URL)
                    Button {
                        working = true
                        Task { if let id = await store.join(link) { onJoined(id); dismiss() }; working = false }
                    } label: { HStack { Text("Join list"); Spacer(); if working { ProgressView() } } }
                        .disabled(link.isEmpty || working).frame(minHeight: 44)
                }
                if let error = store.error { Text(error).font(.subheadline).foregroundStyle(.red) }
            }.scrollContentBackground(.hidden).background(Palette.canvas).tint(Palette.forest)
                .navigationTitle("Join a list").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

#Preview { ListsPreviewView(store: ListStore(inMemory: true)) }
#endif

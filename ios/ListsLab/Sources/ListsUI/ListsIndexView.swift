import SwiftUI
import ListsKit

#if os(iOS)

/// Every list the household keeps, grouped by To-dos and Groceries. This is the
/// navigation answer to many lists: one screen with counts, shared state, and
/// create, rename, reorder, and delete in one place.
@MainActor public struct ListsIndexView: View {
    @ObservedObject var store: ListStore
    @Binding var kind: ListKind
    @Binding var selected: [ListKind: UUID]
    @Environment(\.dismiss) private var dismiss
    @State private var creating: ListKind?
    @State private var renaming: ListBoard?
    @State private var draftName = ""

    public init(store: ListStore, kind: Binding<ListKind>, selected: Binding<[ListKind: UUID]>) {
        self.store = store
        _kind = kind
        _selected = selected
    }

    public var body: some View {
        NavigationStack {
            List {
                ForEach(ListKind.allCases, id: \.self) { section in
                    sectionView(section)
                }
                if let summary = store.undoSummary {
                    Section {
                        Button("Undo · \(summary)", systemImage: "arrow.uturn.backward") { store.undo() }
                            .frame(minHeight: 44)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Palette.canvas)
            .navigationTitle("Your lists")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton().tint(Palette.forest) }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .tint(Palette.forest)
            .sheet(item: $creating) { target in
                NewListSheet(kind: target) { name, groupTitle in
                    if let id = store.createBoard(kind: target, name: name, groupTitle: groupTitle) {
                        kind = target; selected[target] = id
                    }
                }
            }
            .alert("Rename list", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("List name", text: $draftName)
                Button("Save") {
                    if let board = renaming { store.renameBoard(board.id, to: draftName) }
                    renaming = nil
                }
                Button("Cancel", role: .cancel) { renaming = nil }
            } message: {
                Text("Items stay in this list.")
            }
        }
        .preferredColorScheme(.light)
    }

    @ViewBuilder
    private func sectionView(_ section: ListKind) -> some View {
        let lists = store.lists(of: section)
        Section {
            if lists.isEmpty {
                Text(section == .todos ? "No to-do lists yet." : "No grocery lists yet.")
                    .font(.subheadline).foregroundStyle(Palette.muted)
            }
            ForEach(lists) { board in
                row(board, in: section)
            }
            .onMove { store.moveBoards(kind: section, fromOffsets: $0, toOffset: $1) }
            .onDelete { offsets in
                for index in offsets { store.deleteBoard(lists[index].id) }
            }
        } header: {
            HStack {
                Text(section.title)
                Spacer()
                Button {
                    creating = section
                } label: {
                    Label("New \(section.title.lowercased()) list", systemImage: "plus")
                        .labelStyle(.iconOnly)
                        .frame(width: 44, height: 44)
                }
            }
        } footer: {
            Text(section == .todos
                 ? "Lists of things to do. No dates needed."
                 : "Lists of things to pick up.")
        }
    }

    private func row(_ board: ListBoard, in section: ListKind) -> some View {
        let remaining = board.items.filter { !$0.isCompleted }.count
        let done = board.items.count - remaining
        let shared = store.isShared(board.id)
        return Button {
            kind = section
            selected[section] = board.id
            dismiss()
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(board.name).font(.body.weight(.medium)).foregroundStyle(Palette.ink)
                    Text("\(remaining) remaining · \(done) done")
                        .font(.caption).foregroundStyle(Palette.muted)
                }
                Spacer(minLength: 0)
                if shared {
                    Image(systemName: "person.2").font(.caption).foregroundStyle(Palette.forest)
                }
                if selected[section] == board.id {
                    Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(Palette.forest)
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(board.name), \(remaining) remaining, \(shared ? "shared" : "personal")\(selected[section] == board.id ? ", open" : "")")
        .contextMenu {
            Button("Rename", systemImage: "pencil") { draftName = board.name; renaming = board }
            Button("Delete", systemImage: "trash", role: .destructive) { store.deleteBoard(board.id) }
        }
    }
}

@MainActor struct NewListSheet: View {
    let kind: ListKind
    let onCreate: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var groupTitle = ""

    private var defaultGroup: String { kind == .groceries ? "To buy" : "To do" }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(kind == .groceries ? "Weekend shop" : "House projects", text: $name)
                        .font(.title3)
                } header: { Text("List name") }
                Section {
                    TextField(defaultGroup, text: $groupTitle)
                } header: { Text("First section") } footer: {
                    Text("Sections keep a long list tidy. You can add more later, and rename or remove them any time.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.canvas)
            .navigationTitle(kind == .groceries ? "New grocery list" : "New to-do list")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        onCreate(name.trimmingCharacters(in: .whitespacesAndNewlines),
                                 groupTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? defaultGroup : groupTitle)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .tint(Palette.forest)
        }
    }
}

#endif

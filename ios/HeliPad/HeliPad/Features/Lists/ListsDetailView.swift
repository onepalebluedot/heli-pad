import SwiftUI

#if os(iOS)

/// One list, open.
///
/// The same screen serves both lists. Nothing about it is kind-specific except
/// what an item carries: a grocery may have a quantity, a to-do may have steps.
/// Sections, the capture bar and the completed section behave identically.
///
/// Nothing here is held in `@StateObject`: `ListsPresentation` owns the draft,
/// the target section, what is expanded and where the list was scrolled to, so
/// leaving the tab and coming back does not lose any of it.
struct ListDetailView: View {
    @ObservedObject private var store: HouseholdListsStore
    @ObservedObject private var presentation: ListsPresentation
    private let appStore: AppStore
    private let listID: String

    /// Which item the editor sheet is open on. Deliberately an id rather than a
    /// `HouseholdListItem`: a sync can rewrite the row underneath the sheet,
    /// and the sheet must keep pointing at the same item.
    private struct EditTarget: Identifiable, Equatable {
        let id: String
    }

    @State private var editingItem: EditTarget?
    @State private var showingReview = false
    @State private var duplicateCandidate: HouseholdListItem?
    @State private var isAddingSection = false
    @State private var newSectionName = ""
    @State private var confirmingClear = false
    /// Sections are managed in place from the two icon buttons under the list:
    /// nothing about the list changes until a name is typed or a section is
    /// moved with an arrow.
    @State private var sectionMode: SectionMode = .none
    @State private var sectionNames: [String: String] = [:]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Steps opened inline, per item. Presentation state, so a tab switch
    /// collapses them — which is the same thing a re-entry should do anyway.
    @State private var expandedSteps: Set<String> = []
    @FocusState private var captureFocused: Bool

    /// What the Sections row's icon buttons switch on.
    private enum SectionMode: Equatable {
        case none
        /// Rename a section in place, and remove one that is not General.
        case editing
        /// Move sections one position at a time with arrow buttons.
        case rearranging
    }

    init(appStore: AppStore, presentation: ListsPresentation, listID: String) {
        self.appStore = appStore
        self._store = ObservedObject(wrappedValue: appStore.lists)
        self._presentation = ObservedObject(wrappedValue: presentation)
        self.listID = listID
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let list = store.list(listID) {
                    header(list)
                    undoBar
                    saveErrorBanner
                    advisoryEntry
                    sections
                    sectionsFooter
                    completedSection
                } else {
                    missingList
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 16)
            .scrollTargetLayout()
            // Sections settle into their new order rather than jumping.
            .animation(.easeInOut(duration: 0.25), value: groups.map(\.id))
        }
        .scrollPosition(id: presentation.scrollAnchor(listID))
        .scrollDismissesKeyboard(.interactively)
        .background(HeliColors.canvasIvory.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if store.list(listID) != nil { captureBar }
        }
        .onAppear { openSectionsOnFirstVisit() }
        .onDisappear { commitSectionNames() }
        .sheet(item: $editingItem) { target in
            ListsItemEditorView(appStore: appStore, listID: listID, itemID: target.id)
        }
        .sheet(isPresented: $showingReview) {
            ReviewSheet(store: store, listID: listID, kind: kind)
        }
        .alert("New section", isPresented: $isAddingSection) {
            TextField("Section name", text: $newSectionName)
            Button("Add") { addSection() }
            Button("Cancel", role: .cancel) { newSectionName = "" }
        } message: {
            Text("Sections group the items on this list.")
        }
        .confirmationDialog(
            "Clear \(kind.completedTitle.lowercased())?",
            isPresented: $confirmingClear,
            titleVisibility: .visible
        ) {
            Button(
                completedCount == 1 ? "Remove 1 item" : "Remove \(completedCount) items",
                role: .destructive
            ) {
                store.clearCompleted(listID: listID)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes everything currently checked off. You can undo it straight afterwards.")
        }
        .confirmationDialog(
            "Already on your list",
            isPresented: duplicateBinding,
            titleVisibility: .visible,
            presenting: duplicateCandidate
        ) { existing in
            Button("Edit existing") {
                editingItem = EditTarget(id: existing.id)
                duplicateCandidate = nil
            }
            Button("Add another") { addDraft() }
            Button("Cancel", role: .cancel) { duplicateCandidate = nil }
        } message: { existing in
            Text("\(existing.text) is already on this list. Nothing has been combined — choose what you meant.")
        }
    }

    // MARK: - Derived

    private var kind: ListKind { store.list(listID)?.kind ?? .todos }

    private var groups: [HouseholdListGroup] { store.groups(of: listID) }

    private var completedCount: Int { store.completedItems(of: listID).count }

    private var reviewCandidates: [HouseholdListItem] {
        store.reviewCandidates(of: listID, kind: kind)
    }

    /// Whether a section is the one that cannot be removed.
    private func isGeneral(_ group: HouseholdListGroup) -> Bool {
        store.isGeneral(group)
    }

    /// There is nowhere else to go: Lists has two lists, and this is one of them.
    private var backLabel: String { "Lists" }

    private func sectionNameBinding(_ group: HouseholdListGroup) -> Binding<String> {
        Binding(
            get: { sectionNames[group.id] ?? group.name },
            set: { sectionNames[group.id] = $0 }
        )
    }

    /// Writes back every section name that was actually changed. Blank names are
    /// left alone: an accidental clear should not rename a section to nothing.
    private func commitSectionNames() {
        for group in groups {
            guard let draft = sectionNames[group.id] else { continue }
            let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, trimmed != group.name {
                store.renameGroup(id: group.id, to: trimmed)
            }
        }
        sectionNames = [:]
    }

    private func setSectionMode(_ mode: SectionMode) {
        if sectionMode == .editing, mode != .editing { commitSectionNames() }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) { sectionMode = mode }
    }

    private func moveSection(_ id: String, offset: Int) {
        guard let current = groups.firstIndex(where: { $0.id == id }),
              groups.indices.contains(current + offset) else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
            store.moveGroup(id: id, toIndex: current + offset)
        }
    }

    private func moveSectionButton(_ group: HouseholdListGroup, offset: Int) -> some View {
        let index = groups.firstIndex(where: { $0.id == group.id }) ?? 0
        let allowed = groups.indices.contains(index + offset)
        return Button { moveSection(group.id, offset: offset) } label: {
            Image(systemName: offset < 0 ? "arrow.up" : "arrow.down")
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(allowed ? HeliColors.forestGreen : HeliColors.mutedGray.opacity(0.35))
        .disabled(!allowed)
        .accessibilityLabel("Move \(group.name) \(offset < 0 ? "up" : "down")")
        .accessibilityHint("Moves this section one position")
    }

    private var duplicateBinding: Binding<Bool> {
        Binding(
            get: { duplicateCandidate != nil },
            set: { if !$0 { duplicateCandidate = nil } }
        )
    }

    private var draftBinding: Binding<String> {
        Binding(
            get: { presentation.draft(listID) },
            set: { presentation.setDraft(listID, $0) }
        )
    }

    // MARK: - Header

    private func header(_ list: HouseholdList) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { back() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                    Text(backLabel)
                        .font(.body)
                }
                .foregroundColor(HeliColors.forestGreen)
                .frame(minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to Lists")

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(list.name)
                    .font(.title2)
                    .fontDesign(.serif)
                    .foregroundColor(HeliColors.greenInk)
                    .lineLimit(2)
                Spacer(minLength: 8)
                syncCapsule
            }

            Text("\(store.remainingCount(of: listID)) \(kind.remainingTitle)")
                .font(.subheadline)
                .foregroundColor(HeliColors.mutedGray)

            if let detail = store.syncState.detail {
                Text(detail)
                    .font(.caption)
                    .foregroundColor(HeliColors.mutedGray)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if case .failed = store.syncState {
                Button {
                    Task { await store.sync() }
                } label: {
                    Label(store.isSyncing ? "Retrying…" : "Retry sync", systemImage: "arrow.clockwise")
                        .font(.subheadline.weight(.medium))
                        .frame(minHeight: 44)
                }
                .disabled(store.isSyncing)
                .tint(HeliColors.forestGreen)
            }
        }
        .id("header")
    }

    private var syncCapsule: some View {
        Text(store.syncState.label)
            .font(.caption)
            .lineLimit(1)
            .foregroundColor(HeliColors.forestGreen)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(HeliColors.forestTint)
            .clipShape(Capsule())
            .accessibilityLabel("Sync status: \(store.syncState.label)")
    }

    private var missingList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("This list is no longer available")
                .font(.title3)
                .fontDesign(.serif)
                .foregroundColor(HeliColors.greenInk)
            Text("It was removed on another device.")
                .font(.subheadline)
                .foregroundColor(HeliColors.mutedGray)
            Button("Back to Lists") { presentation.screen = .home }
                .font(.body)
                .foregroundColor(HeliColors.forestGreen)
                .frame(minHeight: 44)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .modifier(CardChrome())
    }

    /// The home screen owns the usual undo bar, but a "Clear purchased" or a
    /// removed section done from here must be undoable from here too.
    @ViewBuilder
    private var undoBar: some View {
        if let undo = store.pendingUndo {
            HStack(spacing: 8) {
                Text(undo.label)
                    .font(.subheadline)
                    .foregroundColor(HeliColors.greenInk)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button("Undo") { store.undo() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(HeliColors.forestGreen)
                    .frame(minHeight: 44)
                Button { store.dismissUndo() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(HeliColors.mutedGray)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss undo")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 2)
            .modifier(CardChrome())
            .id("undo")
        }
    }

    /// A save that did not happen is said out loud here rather than the row
    /// quietly staying as it was. The store clears it on the next good save.
    @ViewBuilder
    private var saveErrorBanner: some View {
        if let message = store.saveError {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 13))
                    .foregroundColor(HeliColors.warningText)
                Text(message)
                    .font(.caption)
                    .foregroundColor(HeliColors.greenInk)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(HeliColors.butterYellow)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(HeliColors.sageRule, lineWidth: 0.8))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Not saved. \(message)")
        }
    }

    // MARK: - Advisory cleanup

    @ViewBuilder
    private var advisoryEntry: some View {
        if !reviewCandidates.isEmpty {
            Button { showingReview = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(HeliColors.ochreDark)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Still need these?")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(HeliColors.greenInk)
                        Text(reviewCandidates.count == 1
                             ? "1 item has been here a while"
                             : "\(reviewCandidates.count) items have been here a while")
                            .font(.caption)
                            .foregroundColor(HeliColors.mutedGray)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(HeliColors.mutedGray)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(minHeight: 44)
                .background(HeliColors.butterYellow)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(HeliColors.sageRule, lineWidth: 0.8))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Still need these? \(reviewCandidates.count) items to review")
            .id("advisory")
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var sections: some View {
        // A list with nothing in it shows its empty state — except while the
        // sections are being managed, when the sections are the thing on screen.
        if store.activeItems(of: listID).isEmpty, sectionMode == .none {
            emptyState
        } else {
            ForEach(groups) { group in
                groupCard(group)
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(kind.emptyTitle)
                .font(.title2)
                .fontDesign(.serif)
                .foregroundColor(HeliColors.greenInk)
            Text(kind.emptyDetail)
                .font(.subheadline)
                .foregroundColor(HeliColors.mutedGray)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .modifier(CardChrome())
        .id("empty")
    }

    private func groupCard(_ group: HouseholdListGroup) -> some View {
        let rows = store.items(of: listID, inGroup: group.id).filter { !$0.isCompleted }
        let expanded = presentation.isExpanded(group.id)
        return VStack(alignment: .leading, spacing: 0) {
            // The header carries the theme tint edge to edge, so a section reads
            // as a labelled band rather than one more line of text above rows
            // that look exactly like it.
            sectionHeader(group, rows: rows, expanded: expanded)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(HeliColors.forestTint)
            // Rearranging is about the sections themselves, so the rows step out
            // of the way while it is on.
            if expanded, sectionMode != .rearranging {
                hairline
                VStack(alignment: .leading, spacing: 0) {
                    if rows.isEmpty {
                        Text("Nothing here yet.")
                            .font(.subheadline)
                            .foregroundColor(HeliColors.mutedGray)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(rows) { item in
                            itemRow(item)
                            if item.id != rows.last?.id { hairline }
                        }
                    }
                    addToSectionButton(group)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
                .scrollTargetLayout()
            }
        }
        .modifier(CardChrome())
        .id("group-\(group.id)")
    }

    @ViewBuilder
    private func sectionHeader(_ group: HouseholdListGroup, rows: [HouseholdListItem], expanded: Bool) -> some View {
        switch sectionMode {
        case .editing:
            HStack(spacing: 8) {
                TextField("Section name", text: sectionNameBinding(group))
                    .font(.headline)
                    .foregroundColor(HeliColors.forestGreen)
                    .submitLabel(.done)
                    .onSubmit { commitSectionNames() }
                    .padding(.horizontal, 10)
                    .frame(minHeight: 44)
                    // Warm white, not ivory: the field has to stay legible as a
                    // field now that it sits on the tinted header band.
                    .background(HeliColors.cardWarmWhite)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(HeliColors.sageRule, lineWidth: 1))
                    .accessibilityLabel("Name of the \(group.name) section")
                countBadge(rows.count)
                Spacer(minLength: 0)
                if !isGeneral(group) {
                    Button { store.deleteGroup(id: group.id) } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 16))
                            .foregroundColor(HeliColors.warningText)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove the \(group.name) section")
                    .accessibilityHint("Its items move to General")
                }
            }
        case .rearranging:
            HStack(spacing: 8) {
                Text(group.name)
                    .font(.headline)
                    .foregroundColor(HeliColors.forestGreen)
                countBadge(rows.count)
                Spacer(minLength: 0)
                moveSectionButton(group, offset: -1)
                moveSectionButton(group, offset: 1)
            }
            .frame(minHeight: 44)
        case .none:
            Button { presentation.setExpanded(group.id, !expanded) } label: {
                HStack(spacing: 8) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(HeliColors.forestGreen)
                        .frame(width: 14)
                    Text(group.name)
                        .font(.headline)
                        .foregroundColor(HeliColors.forestGreen)
                    countBadge(rows.count)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(group.name) section")
            .accessibilityValue(rows.count == 1 ? "1 item" : "\(rows.count) items")
            .accessibilityHint(expanded ? "Hides this section" : "Shows this section")
        }
    }

    /// How many items a section holds. A pill rather than a loose numeral,
    /// because a caption-sized number floating beside a headline disappeared
    /// against the header band.
    private func countBadge(_ count: Int) -> some View {
        Text("\(count)")
            .font(.caption.weight(.semibold))
            .foregroundColor(HeliColors.forestGreen)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(HeliColors.cardWarmWhite)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(HeliColors.sageRule, lineWidth: 0.8))
            .accessibilityHidden(true)
    }

    /// Adding from a section header never creates a blank row: it points the
    /// capture bar at this section and puts the keyboard there.
    private func addToSectionButton(_ group: HouseholdListGroup) -> some View {
        Button {
            presentation.setTargetGroup(listID, group.id)
            presentation.setExpanded(group.id, true)
            captureFocused = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 14, weight: .semibold))
                Text("Add to \(group.name)")
                    .font(.subheadline)
                Spacer(minLength: 0)
            }
            .foregroundColor(HeliColors.forestGreen)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add an item to \(group.name)")
        .accessibilityHint("Points the add field at this section")
    }

    // MARK: - Rows

    private func itemRow(_ item: HouseholdListItem) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                completeButton(item)
                    // The circle's centre, nudged down, is treated as its
                    // baseline, so it lines up with the item's name instead of
                    // sitting below it.
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 3 }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(item.text)
                            .font(.body)
                            .strikethrough(item.isCompleted)
                            .foregroundColor(item.isCompleted ? HeliColors.mutedGray : HeliColors.greenInk)
                            .fixedSize(horizontal: false, vertical: true)
                        if let quantity = inlineQuantity(item) {
                            Text(quantity)
                                .font(.subheadline)
                                .foregroundColor(HeliColors.mutedGray)
                        }
                    }
                    if let caption = caption(item) {
                        Text(caption)
                            .font(.caption)
                            .foregroundColor(HeliColors.mutedGray)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                if showsSteps(item) { stepsDisclosure(item) }
            }
            if showsSteps(item), expandedSteps.contains(item.id) {
                stepRows(item)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .contextMenu { itemMenu(item) }
        .id("item-\(item.id)")
    }

    private func completeButton(_ item: HouseholdListItem) -> some View {
        Button { store.setCompleted(id: item.id, to: !item.isCompleted) } label: {
            Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 20, weight: item.isCompleted ? .semibold : .regular))
                .foregroundColor(item.isCompleted ? HeliColors.forestGreen : HeliColors.mutedGray)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Complete \(item.text)")
        .accessibilityValue(item.isCompleted ? "Checked" : "Unchecked")
        .accessibilityAddTraits(item.isCompleted ? [.isButton, .isSelected] : .isButton)
    }

    /// Groceries carry a quantity, and it reads as part of the row's own line.
    private func inlineQuantity(_ item: HouseholdListItem) -> String? {
        guard kind == .groceries, !item.quantity.isEmpty else { return nil }
        return item.quantity
    }

    /// One secondary line: a to-do with steps counts them, anything else says
    /// its note, and a grocery item with no quantity still says its note.
    private func caption(_ item: HouseholdListItem) -> String? {
        if kind.supportsSubtasks {
            let steps = store.subtasks(of: item.id)
            if !steps.isEmpty {
                return "\(steps.filter(\.isCompleted).count) of \(steps.count) steps"
            }
        }
        if kind == .groceries, !item.quantity.isEmpty { return nil }
        return item.note.isEmpty ? nil : item.note
    }

    private func showsSteps(_ item: HouseholdListItem) -> Bool {
        kind.supportsSubtasks && !item.isCompleted && !store.subtasks(of: item.id).isEmpty
    }

    private func stepsDisclosure(_ item: HouseholdListItem) -> some View {
        let expanded = expandedSteps.contains(item.id)
        return Button {
            if expanded { expandedSteps.remove(item.id) } else { expandedSteps.insert(item.id) }
        } label: {
            Image(systemName: expanded ? "chevron.down" : "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(HeliColors.mutedGray)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Steps for \(item.text)")
        .accessibilityValue(expanded ? "Shown" : "Hidden")
        .accessibilityHint(expanded ? "Hides the steps" : "Shows the steps")
    }

    /// Ticking a step never touches the parent: finishing every step is a
    /// person's decision about the item, not an arithmetic one.
    private func stepRows(_ item: HouseholdListItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(store.subtasks(of: item.id)) { step in
                Button { store.setSubtaskCompleted(id: step.id, to: !step.isCompleted) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: step.isCompleted ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 16))
                            .foregroundColor(step.isCompleted ? HeliColors.forestGreen : HeliColors.mutedGray)
                            .frame(width: 20)
                        Text(step.text)
                            .font(.subheadline)
                            .strikethrough(step.isCompleted)
                            .foregroundColor(step.isCompleted ? HeliColors.mutedGray : HeliColors.greenInk)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Complete \(step.text)")
                .accessibilityValue(step.isCompleted ? "Checked" : "Unchecked")
            }
        }
        .padding(.leading, 44)
    }

    @ViewBuilder
    private func itemMenu(_ item: HouseholdListItem) -> some View {
        Button { editingItem = EditTarget(id: item.id) } label: {
            Label("Edit", systemImage: "pencil")
        }
        Button { store.moveItem(id: item.id, by: -1) } label: {
            Label("Move up", systemImage: "arrow.up")
        }
        Button { store.moveItem(id: item.id, by: 1) } label: {
            Label("Move down", systemImage: "arrow.down")
        }
        Menu {
            ForEach(groups.filter { $0.id != item.groupID }) { group in
                Button { store.moveItem(id: item.id, toGroup: group.id) } label: {
                    Text(group.name)
                }
            }
        } label: {
            Label("Move to section", systemImage: "arrow.turn.down.right")
        }
        Button(role: .destructive) { store.deleteItem(id: item.id) } label: {
            Label("Remove", systemImage: "trash")
        }
    }

    // MARK: - Completed / Purchased

    @ViewBuilder
    private var completedSection: some View {
        let completed = store.completedItems(of: listID)
        if !completed.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Button { presentation.setShowsCompleted(listID, !presentation.showsCompleted(listID)) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: presentation.showsCompleted(listID) ? "chevron.down" : "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(HeliColors.forestGreen)
                            .frame(width: 14)
                        Text(kind.completedTitle)
                            .font(.headline)
                            .foregroundColor(HeliColors.forestGreen)
                        countBadge(completed.count)
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: 44)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(HeliColors.forestTint)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(kind.completedTitle)
                .accessibilityValue(completed.count == 1 ? "1 item" : "\(completed.count) items")
                .accessibilityHint(presentation.showsCompleted(listID) ? "Hides these" : "Shows these")

                if presentation.showsCompleted(listID) {
                    hairline
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(completed) { item in
                            itemRow(item)
                            if item.id != completed.last?.id { hairline }
                        }
                        Button(role: .destructive) { confirmingClear = true } label: {
                            Text("Clear \(kind.completedTitle.lowercased())")
                                .font(.subheadline)
                                .foregroundColor(HeliColors.warningClay)
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear \(kind.completedTitle.lowercased())")
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
                    .scrollTargetLayout()
                }
            }
            .modifier(CardChrome())
            .id("completed")
        }
    }

    // MARK: - Section management
    //
    // One row under the sections: a button to add one, and two icon buttons that
    // put the sections into a mode where they can be renamed, removed or moved
    // into a new order. Nothing here is on the home screen, where a tile is for
    // opening a list rather than restructuring it.

    private var sectionsFooter: some View {
        HStack(spacing: 4) {
            Button {
                newSectionName = ""
                isAddingSection = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Add section")
                        .font(.subheadline.weight(.medium))
                }
                .foregroundColor(HeliColors.forestGreen)
                .frame(minHeight: 44)
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add a section")

            Spacer(minLength: 0)

            // Also shown while a mode is on, whatever the count is now. Deleting
            // the second-to-last section used to drop this row to a bare "Add
            // section" and strand the list in editing mode, with the only way
            // out being to leave the screen.
            if groups.count > 1 || sectionMode != .none {
                sectionModeButton(
                    "pencil",
                    mode: .editing,
                    label: "Edit section names",
                    hint: "Rename a section, or remove one that is not General"
                )
                sectionModeButton(
                    "arrow.up.arrow.down",
                    mode: .rearranging,
                    label: "Rearrange sections",
                    hint: "Use the up and down arrows to change the order"
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
        .modifier(CardChrome())
        .id("sections-footer")
    }

    /// Icon only, and it says which mode is on rather than only what tapping
    /// would do.
    private func sectionModeButton(_ symbol: String, mode: SectionMode, label: String, hint: String) -> some View {
        let active = sectionMode == mode
        return Button {
            setSectionMode(active ? .none : mode)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(active ? .white : HeliColors.forestGreen)
                .frame(width: 44, height: 44)
                .background(active ? HeliColors.forestGreen : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityHint(active ? "Returns the sections to normal" : hint)
        .accessibilityAddTraits(active ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - Capture

    private var captureBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            targetLabel
            HStack(spacing: 8) {
                TextField(kind.capturePrompt, text: draftBinding)
                    .font(.body)
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.done)
                    .onSubmit { submitCapture() }
                    .focused($captureFocused)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .background(HeliColors.cardWarmWhite)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(HeliColors.sageRule, lineWidth: 0.8))
                    .accessibilityLabel(kind.capturePrompt)
                Button { submitCapture() } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(HeliColors.forestGreen)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add item")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, ContentView.bottomBarInset)
        .background(HeliColors.canvasIvory)
    }

    /// The target section is never implied: it is always on screen, and with
    /// more than one section it can be changed from here.
    @ViewBuilder
    private var targetLabel: some View {
        if groups.count > 1 {
            Menu {
                ForEach(groups) { group in
                    Button { presentation.setTargetGroup(listID, group.id) } label: {
                        if group.id == presentation.targetGroup(listID, in: groups) {
                            Label(group.name, systemImage: "checkmark")
                        } else {
                            Text(group.name)
                        }
                    }
                }
            } label: {
                targetLabelContent(changeable: true)
            }
            .accessibilityLabel("Section new items are added to")
            .accessibilityValue(targetName)
        } else {
            targetLabelContent(changeable: false)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("New items are added to \(targetName)")
        }
    }

    private var targetName: String {
        let target = presentation.targetGroup(listID, in: groups)
        return groups.first { $0.id == target }?.name ?? HouseholdListsDefaults.generalName
    }

    private func targetLabelContent(changeable: Bool) -> some View {
        HStack(spacing: 5) {
            Text("Adding to")
                .font(.caption)
                .foregroundColor(HeliColors.mutedGray)
            Text(targetName)
                .font(.caption.weight(.semibold))
                .foregroundColor(HeliColors.forestGreen)
            if changeable {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(HeliColors.mutedGray)
            }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    // MARK: - Actions

    private func back() {
        presentation.screen = .home
    }

    /// A section whose items are hidden behind a collapsed header reads as an
    /// empty list, so a list nobody has touched opens with every section open.
    /// `expandedGroups` holds ids for every list, so the question is asked of
    /// this list's sections only: if none of them is open, none of them has
    /// been decided.
    private func openSectionsOnFirstVisit() {
        let rows = groups
        guard !rows.isEmpty, !rows.contains(where: { presentation.isExpanded($0.id) }) else { return }
        for group in rows {
            presentation.setExpanded(group.id, true)
        }
    }

    private func addSection() {
        let name = ListText.trimmed(newSectionName)
        newSectionName = ""
        guard !name.isEmpty else { return }
        if let id = store.addGroup(listID: listID, name: name) {
            presentation.setExpanded(id, true)
        }
    }

    /// Groceries are never silently combined: a second "Milk" is a question.
    private func submitCapture() {
        let text = ListText.trimmed(presentation.draft(listID))
        guard !text.isEmpty else { return }
        if kind == .groceries, let existing = store.duplicate(of: listID, matching: text) {
            duplicateCandidate = existing
            return
        }
        addDraft()
    }

    private func addDraft() {
        let text = ListText.trimmed(presentation.draft(listID))
        guard !text.isEmpty else { return }
        guard let groupID = presentation.targetGroup(listID, in: groups) else { return }
        if store.addItem(listID: listID, groupID: groupID, text: text) != nil {
            // The draft is cleared only once the row exists, and the section it
            // went into is open so the new row can be seen.
            presentation.clearDraft(listID)
            presentation.setExpanded(groupID, true)
        }
    }

    // MARK: - Chrome

    private var hairline: some View {
        Rectangle()
            .fill(HeliColors.sageRule)
            .frame(height: 0.8)
    }

    private struct CardChrome: ViewModifier {
        func body(content: Content) -> some View {
            content
                .background(HeliColors.cardWarmWhite)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(HeliColors.sageRule, lineWidth: 0.8))
        }
    }

    // MARK: - Advisory sheet

    /// Advice, never an action taken on the household's behalf: every row here
    /// waits for a person to keep it or take it off.
    private struct ReviewSheet: View {
        @ObservedObject var store: HouseholdListsStore
        let listID: String
        let kind: ListKind
        @Environment(\.dismiss) private var dismiss

        private var total: Int { store.reviewCandidates(of: listID, kind: kind).count }

        private var shown: [HouseholdListItem] {
            Array(store.reviewCandidates(of: listID, kind: kind).prefix(10))
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Still need these?")
                        .font(.title3)
                        .fontDesign(.serif)
                        .foregroundColor(HeliColors.greenInk)
                    Spacer(minLength: 8)
                    Button("Done") { dismiss() }
                        .font(.body)
                        .foregroundColor(HeliColors.forestGreen)
                        .frame(minHeight: 44)
                }

                Text("Nothing is removed on its own. Keep an item to leave it alone for a month, or take it off the list.")
                    .font(.caption)
                    .foregroundColor(HeliColors.mutedGray)
                    .fixedSize(horizontal: false, vertical: true)

                if shown.isEmpty {
                    Text("Nothing needs a decision right now.")
                        .font(.subheadline)
                        .foregroundColor(HeliColors.mutedGray)
                    Spacer(minLength: 0)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(shown) { item in
                                row(item)
                            }
                            if total > shown.count {
                                Text("Showing the \(shown.count) longest-standing of \(total).")
                                    .font(.caption)
                                    .foregroundColor(HeliColors.mutedGray)
                            }
                        }
                        .scrollTargetLayout()
                    }
                }

                if let undo = store.pendingUndo {
                    Button { store.undo() } label: {
                        Text("Undo \(undo.label)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(HeliColors.forestGreen)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(HeliColors.canvasIvory.ignoresSafeArea())
            .presentationDetents([.medium, .large])
        }

        private func row(_ item: HouseholdListItem) -> some View {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(item.text)
                        .font(.body)
                        .foregroundColor(HeliColors.greenInk)
                        .fixedSize(horizontal: false, vertical: true)
                    if kind == .groceries, !item.quantity.isEmpty {
                        Text(item.quantity)
                            .font(.subheadline)
                            .foregroundColor(HeliColors.mutedGray)
                    }
                    Spacer(minLength: 0)
                }
                HStack(spacing: 12) {
                    Button { store.keep(id: item.id) } label: {
                        Text("Keep for now")
                            .font(.subheadline)
                            .foregroundColor(HeliColors.forestGreen)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Keep \(item.text) for now")
                    .accessibilityHint("Leaves it on the list and stops asking for a month")

                    Spacer(minLength: 8)

                    Button(role: .destructive) { store.deleteItem(id: item.id) } label: {
                        Text("Remove")
                            .font(.subheadline)
                            .foregroundColor(HeliColors.warningClay)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(item.text)")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(HeliColors.cardWarmWhite)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(HeliColors.sageRule, lineWidth: 0.8))
        }
    }
}

#endif

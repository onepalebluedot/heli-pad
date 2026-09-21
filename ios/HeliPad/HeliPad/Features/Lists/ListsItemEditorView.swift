import SwiftUI

#if os(iOS)

/// Editing one item on a list, and — for a to-do — the steps inside it.
///
/// A sheet, not a screen: the app has no navigation stack, and this is a short,
/// cancellable edit of something that is already on the list. Nothing at all is
/// written until Save, including step wording, so Cancel can never leave a
/// half-typed change behind.
struct ListsItemEditorView: View {
    @ObservedObject private var store: HouseholdListsStore
    private let listID: String
    private let itemID: String
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var quantity = ""
    @State private var note = ""
    @State private var groupID = ""
    /// Step wording typed here, held until Save.
    @State private var stepEdits: [String: String] = [:]
    @State private var newStep = ""
    @State private var failure: String?
    @State private var hasLoaded = false
    @FocusState private var focused: Field?

    private enum Field: Hashable { case item, quantity, note, newStep }

    init(appStore: AppStore, listID: String, itemID: String) {
        self._store = ObservedObject(wrappedValue: appStore.lists)
        self.listID = listID
        self.itemID = itemID
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            titleRow
            if itemExists {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        failureBanner
                        fieldsCard
                        if kind.supportsSubtasks { stepsCard }
                        removeButton
                    }
                }
            } else {
                missingItem
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(HeliColors.canvasIvory.ignoresSafeArea())
        .onAppear { load() }
    }

    // MARK: - Derived

    private var itemExists: Bool { store.item(itemID) != nil }

    private var kind: ListKind { store.list(listID)?.kind ?? .todos }

    private var sections: [HouseholdListGroup] { store.groups(of: listID) }

    private var steps: [ListSubtask] { store.subtasks(of: itemID) }

    private var canSave: Bool { itemExists && !ListText.trimmed(text).isEmpty }

    // MARK: - Title

    private var titleRow: some View {
        HStack(spacing: 12) {
            Button("Cancel") { dismiss() }
                .font(.body)
                .foregroundColor(HeliColors.mutedGray)
                .frame(minHeight: 44)
                .accessibilityHint("Closes without saving anything")
            Spacer(minLength: 8)
            Text("Edit item")
                .font(.headline)
                .foregroundColor(HeliColors.greenInk)
            Spacer(minLength: 8)
            Button("Save") { save() }
                .font(.body.weight(.semibold))
                .foregroundColor(canSave ? HeliColors.forestGreen : HeliColors.mutedGray)
                .frame(minHeight: 44)
                .disabled(!canSave)
        }
    }

    @ViewBuilder
    private var failureBanner: some View {
        if let message = failure {
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

    // MARK: - Fields

    private var fieldsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            labelled("Item") {
                TextField("Item", text: $text)
                    .font(.body)
                    .foregroundColor(HeliColors.greenInk)
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.done)
                    .focused($focused, equals: .item)
                    .onChange(of: text) { _, value in
                        // The store enforces this too; trimming here keeps the
                        // counter honest rather than silently refusing Save.
                        if value.count > ListLimits.itemText {
                            text = String(value.prefix(ListLimits.itemText))
                        }
                    }
                    .modifier(FieldChrome())
            }

            if kind == .groceries {
                labelled("Quantity") {
                    TextField("e.g. 2 cartons", text: $quantity)
                        .font(.body)
                        .foregroundColor(HeliColors.greenInk)
                        .submitLabel(.done)
                        .focused($focused, equals: .quantity)
                        .modifier(FieldChrome())
                }
            }

            labelled("Note") {
                TextField("Anything worth remembering", text: $note, axis: .vertical)
                    .font(.body)
                    .foregroundColor(HeliColors.greenInk)
                    .lineLimit(2...6)
                    .focused($focused, equals: .note)
                    .modifier(FieldChrome())
            }

            HStack(spacing: 10) {
                Text("Section")
                    .font(.body)
                    .foregroundColor(HeliColors.greenInk)
                Spacer(minLength: 8)
                Picker("Section", selection: $groupID) {
                    ForEach(sections) { group in
                        Text(group.name).tag(group.id)
                    }
                }
                .pickerStyle(.menu)
                .tint(HeliColors.forestGreen)
                .disabled(sections.count < 2)
                .accessibilityLabel("Section")
            }
            .frame(minHeight: 44)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .modifier(CardChrome())
    }

    // MARK: - Steps

    private var stepsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Steps")
                    .font(.headline)
                    .foregroundColor(HeliColors.greenInk)
                Spacer(minLength: 8)
                Text("\(steps.filter(\.isCompleted).count) of \(steps.count)")
                    .font(.caption)
                    .foregroundColor(HeliColors.mutedGray)
            }

            if steps.isEmpty {
                Text("No steps yet. A to-do can hold up to \(ListLimits.subtasksPerItem).")
                    .font(.subheadline)
                    .foregroundColor(HeliColors.mutedGray)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(steps) { step in
                    stepRow(step)
                }
            }

            if steps.count >= ListLimits.subtasksPerItem {
                Text("This item already holds \(ListLimits.subtasksPerItem) steps. Remove one to add another.")
                    .font(.caption)
                    .foregroundColor(HeliColors.mutedGray)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                addStepRow
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .modifier(CardChrome())
    }

    private func stepRow(_ step: ListSubtask) -> some View {
        HStack(spacing: 6) {
            Button { store.setSubtaskCompleted(id: step.id, to: !step.isCompleted) } label: {
                Image(systemName: step.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: step.isCompleted ? .semibold : .regular))
                    .foregroundColor(step.isCompleted ? HeliColors.forestGreen : HeliColors.mutedGray)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Complete \(step.text)")
            .accessibilityValue(step.isCompleted ? "Checked" : "Unchecked")

            TextField("Step", text: stepBinding(step))
                .font(.subheadline)
                .foregroundColor(HeliColors.greenInk)
                .submitLabel(.done)
                .frame(minHeight: 44)
                .accessibilityLabel("Step \(step.text)")

            Button {
                stepEdits.removeValue(forKey: step.id)
                store.deleteSubtask(id: step.id)
            } label: {
                Image(systemName: "minus.circle")
                    .font(.system(size: 16))
                    .foregroundColor(HeliColors.warningClay)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove step \(step.text)")
        }
    }

    private var addStepRow: some View {
        HStack(spacing: 6) {
            TextField("Add a step", text: $newStep)
                .font(.subheadline)
                .foregroundColor(HeliColors.greenInk)
                .textInputAutocapitalization(.sentences)
                .submitLabel(.done)
                .onSubmit { addStep() }
                .focused($focused, equals: .newStep)
                .accessibilityLabel("Add a step")
                .modifier(FieldChrome())

            Button { addStep() } label: {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(HeliColors.forestGreen)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add step")
            .disabled(ListText.trimmed(newStep).isEmpty)
        }
    }

    private var removeButton: some View {
        Button {
            store.deleteItem(id: itemID)
            dismiss()
        } label: {
            Text("Remove item")
                .font(.body)
                .foregroundColor(HeliColors.warningClay)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove item")
        .accessibilityHint("Takes this item off the list")
    }

    private var missingItem: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("This item is no longer on the list")
                .font(.title3)
                .fontDesign(.serif)
                .foregroundColor(HeliColors.greenInk)
            Text("It was removed on another device.")
                .font(.subheadline)
                .foregroundColor(HeliColors.mutedGray)
            Button("Close") { dismiss() }
                .font(.body)
                .foregroundColor(HeliColors.forestGreen)
                .frame(minHeight: 44)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .modifier(CardChrome())
    }

    // MARK: - Helpers

    private func labelled<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption)
                .foregroundColor(HeliColors.mutedGray)
            content()
        }
    }

    private func stepBinding(_ step: ListSubtask) -> Binding<String> {
        Binding(
            get: { stepEdits[step.id] ?? step.text },
            set: { stepEdits[step.id] = $0 }
        )
    }

    private func load() {
        guard !hasLoaded, let item = store.item(itemID) else { return }
        hasLoaded = true
        text = item.text
        quantity = item.quantity
        note = item.note
        let rows = store.groups(of: listID)
        groupID = rows.contains { $0.id == item.groupID } ? item.groupID : (rows.first?.id ?? "")
    }

    private func addStep() {
        let value = ListText.trimmed(newStep)
        guard !value.isEmpty else { return }
        guard store.addSubtask(itemID: itemID, text: value) != nil else {
            failure = store.saveError ?? "That step could not be added."
            return
        }
        newStep = ""
        failure = nil
        focused = .newStep
    }

    private func save() {
        let trimmed = ListText.trimmed(text)
        guard !trimmed.isEmpty else { return }

        var stepTexts: [String: String] = [:]
        for step in steps {
            guard let edited = stepEdits[step.id] else { continue }
            let value = ListText.trimmed(edited)
            guard !value.isEmpty, value != step.text else { continue }
            stepTexts[step.id] = value
        }

        let saved = store.updateItem(
            id: itemID,
            text: trimmed,
            quantity: quantity,
            note: note,
            groupID: groupID,
            subtaskTexts: stepTexts.isEmpty ? nil : stepTexts
        )
        guard saved else {
            failure = store.saveError ?? "That change was not saved."
            return
        }
        dismiss()
    }

    // MARK: - Chrome

    private struct CardChrome: ViewModifier {
        func body(content: Content) -> some View {
            content
                .background(HeliColors.cardWarmWhite)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(HeliColors.sageRule, lineWidth: 0.8))
        }
    }

    private struct FieldChrome: ViewModifier {
        func body(content: Content) -> some View {
            content
                .padding(.horizontal, 12)
                // 11 + a body line + 11 clears the 44pt tap target.
                .padding(.vertical, 11)
                .background(HeliColors.cardWarmWhite)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(HeliColors.sageRule, lineWidth: 0.8))
        }
    }
}

#endif

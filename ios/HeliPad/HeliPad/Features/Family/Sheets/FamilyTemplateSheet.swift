import SwiftUI

public struct FamilyTemplateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject public var store: AppStore
    public var template: TemplateItem?
    public var isNew: Bool

    @State private var title: String = ""
    @State private var category: String = "Sports"
    @State private var startMinutes: Int = 16 * 60
    @State private var duration: Int = 60
    @State private var location: String = "Home"
    @State private var selectedKids: [String] = []
    @State private var owner: String = "TBD"
    @State private var notes: String = ""
    @State private var repeatDays: Set<Int> = []
    @State private var recurrenceWeekCount: Int = 20

    private struct WeekdayOption: Identifiable {
        let id: Int
        let letter: String
        let name: String
    }

    private let weekdays: [WeekdayOption] = [
        WeekdayOption(id: 0, letter: "M", name: "Mon"),
        WeekdayOption(id: 1, letter: "T", name: "Tue"),
        WeekdayOption(id: 2, letter: "W", name: "Wed"),
        WeekdayOption(id: 3, letter: "Th", name: "Thu"),
        WeekdayOption(id: 4, letter: "F", name: "Fri"),
        WeekdayOption(id: 5, letter: "Sa", name: "Sat"),
        WeekdayOption(id: 6, letter: "Su", name: "Sun")
    ]

    public init(store: AppStore, template: TemplateItem?, isNew: Bool) {
        self.store = store
        self.template = template
        self.isNew = isNew
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    previewCard

                    VStack(spacing: 8) {
                        titleField
                        categoryRow
                        locationRow
                        driverRow
                    }

                    timingCard
                    kidsCard

                    saveButton

                    if !isNew {
                        Button(action: {
                            deleteTemplate()
                            dismiss()
                        }) {
                            Text("Remove this shortcut")
                                .font(HeliTypography.actionButton(13))
                                .foregroundColor(HeliColors.warningText)
                                .underline()
                        }
                        .padding(.top, 2)
                    }

                    Spacer().frame(height: 24)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
            .background(HeliColors.canvasIvory)
            .navigationTitle(isNew ? "New Shortcut" : "Edit Shortcut")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(HeliTypography.buttonLabel(14))
                        .foregroundColor(HeliColors.mutedGray)
                }
            }
            .onAppear { setupInitialValues() }
        }
    }

    // MARK: - Preview

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(displayTitle)
                    .font(HeliTypography.destTitle(18))
                    .foregroundColor(.white)
                Spacer()
                Text(TimeFormat.formatDuration(duration))
                    .font(HeliTypography.railMeta(12))
                    .foregroundColor(Color.white.opacity(0.85))
            }

            HStack(spacing: 8) {
                Text(category.uppercased())
                    .font(HeliTypography.eyebrow(9))
                    .foregroundColor(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.18))
                    .clipShape(Capsule())

                Text(repeatSummary)
                    .font(HeliTypography.railMeta(12))
                    .foregroundColor(Color.white.opacity(0.9))

                Spacer()

                Text(TimeFormat.formatTime(startMinutes))
                    .font(HeliTypography.monoTime(14))
                    .foregroundColor(.white)
            }

            HStack(spacing: 6) {
                HeliIcon("car", size: 12)
                    .foregroundColor(Color.white.opacity(0.85))
                Text(location)
                    .font(HeliTypography.railMeta(12))
                    .foregroundColor(Color.white.opacity(0.85))
                if !selectedKids.isEmpty {
                    Text("·")
                        .foregroundColor(Color.white.opacity(0.5))
                    Text(selectedKids.joined(separator: ", "))
                        .font(HeliTypography.railMeta(12))
                        .foregroundColor(Color.white.opacity(0.85))
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HeliColors.forestGreen)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Fields

    private var titleField: some View {
        HStack(spacing: 12) {
            HeliIcon("pencil", size: 14)
                .foregroundColor(HeliColors.forestGreen)
                .frame(width: 20)
            Text("What")
                .font(HeliTypography.railTitle(13.5))
                .foregroundColor(HeliColors.mutedGray)
                .frame(width: 56, alignment: .leading)
            TextField("Soccer practice", text: $title)
                .font(HeliTypography.body(13.5))
                .foregroundColor(HeliColors.greenInk)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 52)
        .background(HeliColors.cardWarmWhite)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(HeliColors.sageRule, lineWidth: 0.8)
        )
    }

    private var categoryRow: some View {
        menuRow(icon: "list", label: "Type", value: category) {
            Picker("", selection: $category) {
                ForEach(TaskKind.categories, id: \.self) { cat in
                    Text(cat).tag(cat)
                }
            }
        }
    }

    private var locationRow: some View {
        menuRow(icon: "map-pin", label: "Where", value: location) {
            Picker("", selection: $location) {
                ForEach(store.locations) { loc in
                    Text(loc.name).tag(loc.name)
                }
            }
        }
    }

    private var driverRow: some View {
        menuRow(icon: "user", label: "Driver", value: owner == "TBD" ? "Needs driver" : owner) {
            Picker("", selection: $owner) {
                Text("Needs driver").tag("TBD")
                ForEach(store.caregiverPeople()) { person in
                    Text(person.name).tag(person.name)
                }
            }
        }
    }

    private func menuRow<Content: View>(
        icon: String,
        label: String,
        value: String,
        @ViewBuilder picker: () -> Content
    ) -> some View {
        HStack(spacing: 12) {
            HeliIcon(icon, size: 14)
                .foregroundColor(HeliColors.forestGreen)
                .frame(width: 20)
            Text(label)
                .font(HeliTypography.railTitle(13.5))
                .foregroundColor(HeliColors.mutedGray)
                .frame(width: 56, alignment: .leading)
            Spacer()
            Menu {
                picker()
            } label: {
                HStack(spacing: 6) {
                    Text(value)
                        .font(HeliTypography.body(13.5))
                        .foregroundColor(HeliColors.greenInk)
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(HeliColors.mutedGray)
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 52)
        .background(HeliColors.cardWarmWhite)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(HeliColors.sageRule, lineWidth: 0.8)
        )
    }

    // MARK: - Timing

    private var timingCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Which days this shortcut normally runs, so a week can be loaded
            // in one tap rather than rebuilt each time.
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("USUAL DAYS")
                        .font(HeliTypography.eyebrow(10))
                        .foregroundColor(HeliColors.mutedGray)
                        .tracking(1.2)
                    Spacer()
                    if !repeatDays.isEmpty {
                        Text("\(repeatDays.count) selected")
                            .font(HeliTypography.caption(10.5))
                            .foregroundColor(HeliColors.forestGreen)
                    }
                }

                HStack(spacing: 5) {
                    ForEach(weekdays) { day in
                        let isSelected = repeatDays.contains(day.id)
                        Button(action: {
                            if isSelected {
                                repeatDays.remove(day.id)
                            } else {
                                repeatDays.insert(day.id)
                            }
                        }) {
                            VStack(spacing: 2) {
                                Text(day.letter)
                                    .font(HeliTypography.actionButton(12))
                                Text(day.name)
                                    .font(.system(size: 8.5, weight: .regular))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .foregroundColor(isSelected ? HeliColors.cardWarmWhite : HeliColors.greenInk)
                            .background(isSelected ? HeliColors.forestGreen : HeliColors.cardWarmWhite)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(isSelected ? HeliColors.forestGreen : HeliColors.sageRule, lineWidth: 0.8)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }

                Text(repeatDays.isEmpty
                     ? "No set days — you'll pick the day when you use it."
                     : "Loads onto \(repeatSummary) for \(recurrenceWeekCount) calendar weeks when used.")
                    .font(HeliTypography.caption(11))
                    .foregroundColor(HeliColors.mutedGray)

                if !repeatDays.isEmpty {
                    HStack {
                        Button("20 weeks") { recurrenceWeekCount = 20 }
                        Button("30 weeks") { recurrenceWeekCount = 30 }
                        Spacer()
                        Stepper("\(recurrenceWeekCount)", value: $recurrenceWeekCount, in: 1...52)
                            .fixedSize()
                    }
                }
            }

            Divider().background(HeliColors.sageRule)

            // The system picker follows the phone's own 12/24-hour setting.
            HStack {
                Text("Starts at")
                    .font(HeliTypography.body(13.5))
                    .foregroundColor(HeliColors.greenInk)
                Spacer()
                DatePicker(
                    "",
                    selection: startTimeBinding,
                    displayedComponents: [.hourAndMinute]
                )
                .datePickerStyle(.compact)
                .labelsHidden()
                .tint(HeliColors.forestGreen)
            }

            HStack {
                Text("Runs for")
                    .font(HeliTypography.body(13.5))
                    .foregroundColor(HeliColors.greenInk)
                Spacer()
                Text(TimeFormat.formatDuration(duration))
                    .font(HeliTypography.monoTime(13))
                    .foregroundColor(HeliColors.greenInk)
                Stepper("", value: $duration, in: 15...240, step: 15)
                    .labelsHidden()
                    .tint(HeliColors.forestGreen)
            }
        }
        .padding(14)
        .background(HeliColors.cardWarmWhite)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(HeliColors.sageRule, lineWidth: 0.8)
        )
    }

    // MARK: - Kids

    private var kidsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("WHO IT'S FOR")
                .font(HeliTypography.eyebrow(10))
                .foregroundColor(HeliColors.mutedGray)
                .tracking(1.2)

            let children = store.childPeople()
            if children.isEmpty {
                Text("Add a child in Roster first.")
                    .font(HeliTypography.caption(11))
                    .foregroundColor(HeliColors.mutedGray)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(children) { child in
                            let isSelected = selectedKids.contains(child.name)
                            Button(action: {
                                if isSelected {
                                    selectedKids.removeAll { $0 == child.name }
                                } else {
                                    selectedKids.append(child.name)
                                }
                            }) {
                                HStack(spacing: 6) {
                                    AvatarDisc(name: child.name, size: 20)
                                    Text(child.name)
                                        .font(HeliTypography.chipLabel(12))
                                        .foregroundColor(isSelected ? HeliColors.forestGreen : HeliColors.greenInk)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(isSelected ? HeliColors.forestTint : HeliColors.cardWarmWhite)
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule().stroke(
                                        isSelected ? HeliColors.forestGreen : HeliColors.sageRule,
                                        lineWidth: isSelected ? 1.5 : 0.8
                                    )
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HeliColors.cardWarmWhite)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(HeliColors.sageRule, lineWidth: 0.8)
        )
    }

    private var saveButton: some View {
        Button(action: {
            saveTemplate()
            dismiss()
        }) {
            Text(isNew ? "Add shortcut" : "Save changes")
                .font(HeliTypography.buttonLabel(15))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(canSave ? HeliColors.forestGreen : HeliColors.mutedGray.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .disabled(!canSave)
    }

    // MARK: - Derived

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "New shortcut" : trimmed
    }

    private var repeatSummary: String {
        if repeatDays.isEmpty { return "Any day" }
        return repeatDays.sorted()
            .compactMap { idx in weekdays.first(where: { $0.id == idx })?.name }
            .joined(separator: ", ")
    }

    /// Bridges the stored "HH:mm" to the system picker. Only the clock matters,
    /// so the date part is pinned and the picker renders in the phone's own
    /// 12- or 24-hour format.
    private var startTimeBinding: Binding<Date> {
        Binding(
            get: {
                var parts = DateComponents()
                parts.year = 2000
                parts.month = 1
                parts.day = 1
                parts.hour = startMinutes / 60
                parts.minute = startMinutes % 60
                return Calendar.current.date(from: parts) ?? Date()
            },
            set: { picked in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: picked)
                startMinutes = (parts.hour ?? 16) * 60 + (parts.minute ?? 0)
            }
        )
    }

    private var timeString: String {
        String(format: "%02d:%02d", startMinutes / 60, startMinutes % 60)
    }

    // MARK: - Load & Save

    private func setupInitialValues() {
        if let t = template {
            title = t.title
            category = t.category ?? "Sports"
            startMinutes = PlanCore.mins(t.time)
            duration = t.duration
            location = t.location
            selectedKids = t.kids
            owner = t.owner
            notes = t.notes ?? ""
            repeatDays = t.repeatDays
            recurrenceWeekCount = t.recurrenceWeekCount ?? 1
        } else {
            location = store.locations.first?.name ?? "Home"
        }
    }

    private func saveTemplate() {
        let item = TemplateItem(
            id: template?.id ?? "tmpl-\(UUID().uuidString.prefix(8))",
            title: title.trimmingCharacters(in: .whitespaces),
            time: timeString,
            endTime: PlanCore.addMinutes(time: timeString, mins: duration),
            kids: selectedKids,
            kid: selectedKids.joined(separator: ", "),
            owner: owner,
            location: location,
            mode: "Drive",
            duration: duration,
            notes: notes.isEmpty ? nil : notes,
            category: category,
            weekdays: repeatDays.isEmpty ? nil : repeatDays.sorted(),
            recurrenceWeekCount: repeatDays.isEmpty ? nil : recurrenceWeekCount
        )

        store.upsertTemplate(item)
    }

    private func deleteTemplate() {
        if let t = template {
            store.removeTemplate(id: t.id)
        }
    }
}

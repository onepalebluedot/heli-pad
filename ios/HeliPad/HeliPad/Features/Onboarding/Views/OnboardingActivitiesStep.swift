import SwiftUI

struct OnboardingActivitiesStep: View {
    @Binding var draft: OnboardingDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            OnboardingHeader(
                eyebrow: "Step 6 · Routines · optional",
                title: "What happens every week?",
                subtitle: "Practices, lessons, the school run. Each one becomes a routine you can assign, and lands on the days you pick."
            )

            if draft.kidNames.isEmpty {
                OnboardingNotice(text: "Add a child first — a routine needs someone to be for.")
            }

            if let error = draft.activitiesValidationError {
                OnboardingNotice(text: error)
            }

            ForEach($draft.activities) { $activity in
                OnboardingActivityRow(
                    activity: $activity,
                    kidNames: draft.kidNames,
                    crewNames: draft.caregiverNames,
                    placeNames: [draft.homeName] + draft.placeNames,
                    onDelete: { remove(activity.id) }
                )
            }

            OnboardingAddButton(label: "Add a routine") {
                draft.activities.append(
                    OnboardingDraft.DraftActivity(
                        kidNames: Array(draft.kidNames.prefix(1)),
                        placeName: draft.placeNames.first ?? draft.homeName
                    )
                )
            }
        }
    }

    private func remove(_ id: String) {
        draft.activities.removeAll { $0.id == id }
    }
}

struct OnboardingActivityRow: View {
    @Binding var activity: OnboardingDraft.DraftActivity
    var kidNames: [String]
    var crewNames: [String]
    var placeNames: [String]
    var onDelete: () -> Void

    private var ownerOptions: [String] { ["TBD", "Family"] + crewNames }

    var body: some View {
        OnboardingCardRow(onDelete: onDelete) {
            OnboardingField(label: "What is it", placeholder: "e.g. Soccer practice", text: $activity.title)

            labelled("Who it's for") {
                OnboardingChipWrap(items: kidNames, perRow: 3) { name in
                    OnboardingChip(
                        label: name,
                        isSelected: activity.kidNames.contains(name),
                        action: { toggleKid(name) }
                    )
                }
            }

            labelled("Where") {
                OnboardingChipWrap(items: placeNames, perRow: 2) { name in
                    OnboardingChip(
                        label: name,
                        isSelected: activity.placeName == name,
                        action: { activity.placeName = name }
                    )
                }
            }

            labelled("Starts") {
                DatePicker("Start date", selection: startDateBinding, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .labelsHidden()
            }

            labelled("Repeat") {
                Picker("Repeat", selection: recurrenceModeBinding) {
                    Text("Does not repeat").tag(RecurrenceMode.none)
                    Text("Weekly").tag(RecurrenceMode.weekly)
                }
                .pickerStyle(.segmented)
            }

            if recurrenceModeBinding.wrappedValue == .weekly {
                OnboardingWeekdayPicker(weekdays: $activity.weekdays)

                labelled("Ends") {
                    Picker("Ends", selection: endModeBinding) {
                        Text("For weeks").tag("weeks")
                        Text("Until date").tag("date")
                    }
                    .pickerStyle(.segmented)
                }

                if endModeBinding.wrappedValue == "weeks" {
                    HStack {
                        Button("20 weeks") { activity.recurrenceWeekCount = 20 }
                        Button("30 weeks") { activity.recurrenceWeekCount = 30 }
                        Spacer()
                        Stepper(
                            "\(activity.recurrenceWeekCount ?? 20)",
                            value: Binding(
                                get: { activity.recurrenceWeekCount ?? 20 },
                                set: { activity.recurrenceWeekCount = $0 }
                            ),
                            in: 1...52
                        )
                        .fixedSize()
                    }
                    Text("Calendar weeks include the partial starting week.")
                        .font(HeliTypography.caption(11))
                        .foregroundColor(HeliColors.mutedGray)
                } else {
                    DatePicker("Repeat through", selection: throughDateBinding, displayedComponents: .date)
                        .datePickerStyle(.compact)
                }

                Text(recurrenceSummary)
                    .font(HeliTypography.caption(11))
                    .foregroundColor(HeliColors.mutedGray)
            }

            HStack(alignment: .bottom, spacing: 14) {
                OnboardingTimeField(label: "Starts", time: $activity.time)
                Stepper(
                    "\(activity.durationMinutes) min",
                    value: $activity.durationMinutes,
                    in: 15...240,
                    step: 15
                )
                .font(HeliTypography.body(13))
                .foregroundColor(HeliColors.greenInk)
            }

            labelled("Usually driven by") {
                OnboardingChipWrap(items: ownerOptions, perRow: 3) { name in
                    OnboardingChip(
                        label: name,
                        isSelected: activity.ownerName == name,
                        action: { activity.ownerName = name }
                    )
                }
            }

            labelled("Kind") {
                OnboardingChipWrap(items: OnboardingDraft.activityCategories, perRow: 3) { category in
                    OnboardingChip(
                        label: category,
                        isSelected: activity.category == category,
                        action: { activity.category = category }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func labelled<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(HeliTypography.railTitle(11.5))
                .foregroundColor(HeliColors.mutedGray)
            content()
        }
    }

    private func toggleKid(_ name: String) {
        if let index = activity.kidNames.firstIndex(of: name) {
            activity.kidNames.remove(at: index)
        } else {
            activity.kidNames.append(name)
        }
    }

    private var recurrenceModeBinding: Binding<RecurrenceMode> {
        Binding(
            get: { activity.recurrenceMode ?? (activity.weekdays.isEmpty ? .none : .weekly) },
            set: { mode in
                activity.recurrenceMode = mode
                if mode == .weekly && activity.weekdays.isEmpty {
                    activity.weekdays = [PlanCore.weekdayIndex(activity.startDate ?? PlanCore.currentDeviceDate())]
                }
            }
        )
    }

    private var endModeBinding: Binding<String> {
        Binding(
            get: { activity.recurrenceThroughDate == nil ? "weeks" : "date" },
            set: { mode in
                if mode == "weeks" {
                    activity.recurrenceThroughDate = nil
                    if activity.recurrenceWeekCount == nil { activity.recurrenceWeekCount = 20 }
                } else {
                    activity.recurrenceThroughDate = activity.startDate ?? PlanCore.currentDeviceDate()
                }
            }
        )
    }

    private var startDateBinding: Binding<Date> {
        dateBinding(
            get: { activity.startDate ?? PlanCore.currentDeviceDate() },
            set: { activity.startDate = $0 }
        )
    }

    private var throughDateBinding: Binding<Date> {
        dateBinding(
            get: { activity.recurrenceThroughDate ?? activity.startDate ?? PlanCore.currentDeviceDate() },
            set: { activity.recurrenceThroughDate = $0 }
        )
    }

    private func dateBinding(get: @escaping () -> String, set: @escaping (String) -> Void) -> Binding<Date> {
        Binding(
            get: {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                formatter.timeZone = .current
                return formatter.date(from: get()) ?? Date()
            },
            set: { date in
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                formatter.timeZone = .current
                set(formatter.string(from: date))
            }
        )
    }

    private var recurrenceSummary: String {
        let start = activity.startDate ?? PlanCore.currentDeviceDate()
        let end: RecurrenceEnd = activity.recurrenceThroughDate.map(RecurrenceEnd.throughDate)
            ?? .weekCount(activity.recurrenceWeekCount ?? 20)
        let pattern = RecurrencePattern(mode: .weekly, startDate: start, weekdays: activity.weekdays, end: end)
        let draft = TaskRecord(
            id: "preview",
            date: start,
            time: activity.time,
            endTime: PlanCore.addMinutes(time: activity.time, mins: activity.durationMinutes),
            title: activity.title.isEmpty ? "Preview" : activity.title
        )
        guard let rows = try? PlanCore.occurrences(draft, recurrence: pattern, seriesId: "preview"),
              let first = rows.first, let last = rows.last else {
            return "Choose a weekday that occurs in the selected range."
        }
        return "\(rows.count) occurrence\(rows.count == 1 ? "" : "s") · \(first.date) through \(last.date)"
    }
}

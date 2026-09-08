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

            OnboardingWeekdayPicker(weekdays: $activity.weekdays)

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
}

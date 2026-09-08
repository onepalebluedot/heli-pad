import SwiftUI

struct OnboardingReviewStep: View {
    var draft: OnboardingDraft

    private var driveCount: Int {
        draft.activities.reduce(0) { total, activity in
            let named = !activity.title.trimmingCharacters(in: .whitespaces).isEmpty
            return total + (named ? activity.weekdays.count : 0)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            OnboardingHeader(
                eyebrow: "Step 7 · Review",
                title: "Here's your household.",
                subtitle: "Finishing saves this to the phone and replaces whatever the app is showing now."
            )

            summaryCard(icon: "house", title: draft.homeName) {
                Text(draft.homeAddress.trimmingCharacters(in: .whitespaces))
                    .font(HeliTypography.body(13))
                    .foregroundColor(HeliColors.mutedGray)
            }

            summaryCard(icon: "users-round", title: "Crew · \(draft.caregiverNames.count)") {
                rosterRow(names: draft.caregiverNames, isKid: false)
            }

            summaryCard(icon: "user-round", title: "Children · \(draft.kidNames.count)") {
                rosterRow(names: draft.kidNames, isKid: true)
            }

            summaryCard(icon: "map-pin", title: "Places · \(draft.placeNames.count + 1)") {
                Text(([draft.homeName] + draft.placeNames).joined(separator: " · "))
                    .font(HeliTypography.body(13))
                    .foregroundColor(HeliColors.mutedGray)
                    .fixedSize(horizontal: false, vertical: true)
            }

            summaryCard(icon: "clock", title: "Routines · \(draft.activities.count)") {
                if driveCount == 0 {
                    Text("No routines yet. The week starts empty and you can add events from Go.")
                        .font(HeliTypography.body(13))
                        .foregroundColor(HeliColors.mutedGray)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("\(driveCount) event\(driveCount == 1 ? "" : "s") across the week, unassigned until you or the crew take them.")
                        .font(HeliTypography.body(13))
                        .foregroundColor(HeliColors.mutedGray)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func rosterRow(names: [String], isKid: Bool) -> some View {
        let roster = draft.previewPeople()
        return HStack(spacing: 10) {
            ForEach(names, id: \.self) { name in
                AvatarDisc(
                    name: name,
                    size: 30,
                    showNameBelow: true,
                    isKid: isKid,
                    colorHex: roster.first { $0.name == name }?.color
                )
            }
            Spacer(minLength: 0)
        }
    }

    private func summaryCard<Content: View>(
        icon: String,
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                HeliIcon(icon, size: 14)
                    .foregroundColor(HeliColors.forestGreen)
                Text(title)
                    .font(HeliTypography.railTitle(13.5))
                    .foregroundColor(HeliColors.greenInk)
                Spacer()
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(HeliColors.cardWarmWhite)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(HeliColors.sageRule, lineWidth: 0.9)
        )
    }
}

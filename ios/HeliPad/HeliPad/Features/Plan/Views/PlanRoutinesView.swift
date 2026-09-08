import SwiftUI

public struct PlanRoutinesView: View {
    public var routines: [RoutineGroup]
    public var onSetCaregiver: (RoutineGroup) -> Void
    public var onEditSeries: (RoutineGroup) -> Void

    public init(
        routines: [RoutineGroup],
        onSetCaregiver: @escaping (RoutineGroup) -> Void,
        onEditSeries: @escaping (RoutineGroup) -> Void
    ) {
        self.routines = routines
        self.onSetCaregiver = onSetCaregiver
        self.onEditSeries = onEditSeries
    }

    public var body: some View {
        if !routines.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                // Section Header
                HStack(spacing: 8) {
                    Text("RECURRING STOPS")
                        .font(HeliTypography.eyebrow(11))
                        .foregroundColor(HeliColors.mutedGray)
                        .tracking(1.4)

                    Text("\(routines.count)")
                        .font(HeliTypography.eyebrow(10))
                        .foregroundColor(HeliColors.greenInk)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(HeliColors.forestTint)
                        .clipShape(Capsule())

                    Spacer()
                }
                .padding(.horizontal, 20)

                // Routine Cards
                VStack(spacing: 10) {
                    ForEach(routines) { group in
                        routineCard(group: group)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func routineCard(group: RoutineGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: Title + Days — tapping edits every occurrence at once
            Button(action: { onEditSeries(group) }) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.title)
                        .font(HeliTypography.cardTitle(15))
                        .foregroundColor(HeliColors.greenInk)

                    HStack(spacing: 6) {
                        Text(group.location)
                            .font(HeliTypography.caption(12))
                            .foregroundColor(HeliColors.mutedGray)

                        if !group.kids.isEmpty {
                            Text("•")
                                .font(.system(size: 10))
                                .foregroundColor(HeliColors.sageRule)
                            ForEach(group.kids, id: \.self) { kid in
                                Text(kid)
                                    .font(HeliTypography.chipLabel(11))
                                    .foregroundColor(HeliColors.greenInk)
                            }
                        }
                    }
                }

                Spacer()

                // Day badges
                HStack(spacing: 4) {
                    ForEach(group.events.map { formatDayShort($0.date) }, id: \.self) { day in
                        Text(day)
                            .font(HeliTypography.eyebrow(9))
                            .foregroundColor(HeliColors.forestGreen)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(HeliColors.forestTint)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }

                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(HeliColors.mutedGray)
                }
            }
            }
            .buttonStyle(.plain)

            Divider()
                .background(HeliColors.sageRule)

            // Footer: Current owner + Assign action
            HStack {
                HStack(spacing: 6) {
                    AvatarDisc(name: group.owner, size: 22)
                    Text(group.owner == "TBD" ? "Unassigned" : group.owner)
                        .font(HeliTypography.caption(12))
                        .foregroundColor(group.owner == "TBD" ? HeliColors.clayText : HeliColors.greenInk)
                }

                Spacer()

                HStack(spacing: 8) {
                    Button(action: { onEditSeries(group) }) {
                        HStack(spacing: 4) {
                            Image(systemName: "square.and.pencil")
                                .font(.system(size: 10, weight: .bold))
                            Text("Edit all (\(group.events.count))")
                                .font(HeliTypography.actionButton(11))
                        }
                        .foregroundColor(HeliColors.forestGreen)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(HeliColors.cardWarmWhite)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(HeliColors.sageRule, lineWidth: 0.8))
                    }
                    .buttonStyle(.plain)

                    Button(action: { onSetCaregiver(group) }) {
                        HStack(spacing: 4) {
                            Text("Set driver")
                                .font(HeliTypography.actionButton(11))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundColor(HeliColors.forestGreen)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(HeliColors.cardWarmWhite)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(HeliColors.sageRule, lineWidth: 0.8))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(HeliColors.cardWarmWhite)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(HeliColors.sageRule, lineWidth: 0.8)
        )
    }

    private func formatDayShort(_ dStr: String) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone = TimeZone(secondsFromGMT: 0)
        guard let d = df.date(from: dStr) else { return dStr }
        let out = DateFormatter()
        out.dateFormat = "EEE"
        out.timeZone = TimeZone(secondsFromGMT: 0)
        return out.string(from: d)
    }
}

import SwiftUI

public struct PlanRoutinesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject public var store: AppStore
    public var routines: [RoutineGroup]
    public var onAssignRoutine: (RoutineGroup) -> Void
    public var onSelectEvent: ((TaskRecord) -> Void)?

    public init(
        store: AppStore,
        routines: [RoutineGroup],
        onAssignRoutine: @escaping (RoutineGroup) -> Void,
        onSelectEvent: ((TaskRecord) -> Void)? = nil
    ) {
        self.store = store
        self.routines = routines
        self.onAssignRoutine = onAssignRoutine
        self.onSelectEvent = onSelectEvent
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Header Status Summary
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Recurring Shortcuts")
                            .font(HeliTypography.mastheadDate(22))
                            .foregroundColor(HeliColors.greenInk)

                        let totalStops = routines.reduce(0) { $0 + $1.weekEvents.count }
                        Text("\(routines.count) recurring series · \(totalStops) stops this week")
                            .font(HeliTypography.caption(12))
                            .foregroundColor(HeliColors.mutedGray)

                        Text("Assign a caregiver once to set all weekly occurrences in the series.")
                            .font(HeliTypography.caption(11))
                            .foregroundColor(HeliColors.greenInk.opacity(0.8))
                            .padding(.top, 2)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(HeliColors.cardWarmWhite)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(HeliColors.sageRule, lineWidth: 0.8))

                    // Routines List
                    if routines.isEmpty {
                        emptyState
                    } else {
                        VStack(spacing: 14) {
                            ForEach(routines) { group in
                                routineCard(group: group)
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(HeliColors.canvasIvory)
            .navigationTitle("Recurring Shortcuts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(HeliColors.greenInk)
                }
            }
        }
    }

    private func routineCard(group: RoutineGroup) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: Title + Days
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.title)
                        .font(HeliTypography.cardTitle(16))
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
                    ForEach(group.weekdays, id: \.self) { day in
                        Text(weekdayLabel(day))
                            .font(HeliTypography.eyebrow(9))
                            .foregroundColor(HeliColors.forestGreen)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(HeliColors.forestTint)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }

            // Scheduled occurrences breakdown
            VStack(spacing: 6) {
                ForEach(group.weekEvents) { ev in
                    Button(action: {
                        dismiss()
                        onSelectEvent?(ev)
                    }) {
                        HStack {
                            Text("\(formatDayDate(ev.date)) · \(TimeFormat.formatTime(ev.time))")
                                .font(HeliTypography.monoTime(11))
                                .foregroundColor(HeliColors.mutedGray)

                            Spacer()

                            HStack(spacing: 4) {
                                AvatarDisc(name: ev.owner, size: 18)
                                Text(ev.owner == "TBD" ? "Unassigned" : ev.owner)
                                    .font(HeliTypography.caption(11))
                                    .foregroundColor(ev.owner == "TBD" ? HeliColors.clayText : HeliColors.greenInk)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10))
                                    .foregroundColor(HeliColors.mutedGray)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(HeliColors.canvasIvory.opacity(0.7))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }

            Divider()
                .background(HeliColors.sageRule)

            // Footer: Current status + Bulk Assign Button
            HStack {
                HStack(spacing: 6) {
                    AvatarDisc(name: group.owner, size: 24)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(group.owner == "TBD" ? "Unassigned Series" : "\(group.owner)")
                            .font(HeliTypography.cardTitle(12))
                            .foregroundColor(group.owner == "TBD" ? HeliColors.clayText : HeliColors.greenInk)
                        Text("\(group.events.count) total · \(group.firstDate)–\(group.lastDate)")
                            .font(HeliTypography.caption(10))
                            .foregroundColor(HeliColors.mutedGray)
                    }
                }

                Spacer()

                Button(action: {
                    dismiss()
                    onAssignRoutine(group)
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 11))
                        Text("Set Caregiver for All")
                            .font(HeliTypography.actionButton(11))
                    }
                    .foregroundColor(HeliColors.cardWarmWhite)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(HeliColors.forestGreen)
                    .clipShape(Capsule())
                }
                .buttonStyle(PlainButtonStyle())
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

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 32))
                .foregroundColor(HeliColors.forestGreen)
            Text("No recurring shortcuts found for this week.")
                .font(HeliTypography.caption(13))
                .foregroundColor(HeliColors.greenInk)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(HeliColors.cardWarmWhite)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(HeliColors.sageRule, lineWidth: 0.8))
    }

    private func weekdayLabel(_ day: Int) -> String {
        let names = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        return names.indices.contains(day) ? names[day] : "?"
    }

    private func formatDayDate(_ dStr: String) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone = TimeZone(secondsFromGMT: 0)
        guard let d = df.date(from: dStr) else { return dStr }
        let out = DateFormatter()
        out.dateFormat = "EEE, MMM d"
        out.timeZone = TimeZone(secondsFromGMT: 0)
        return out.string(from: d)
    }
}

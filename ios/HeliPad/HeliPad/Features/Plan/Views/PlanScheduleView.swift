import SwiftUI

public struct PlanScheduleView: View {
    @ObservedObject public var viewModel: PlanViewModel
    @ObservedObject public var store: AppStore
    public var onSelectEvent: (TaskRecord) -> Void
    public var onAddEvent: (String) -> Void

    public init(
        viewModel: PlanViewModel,
        store: AppStore,
        onSelectEvent: @escaping (TaskRecord) -> Void,
        onAddEvent: @escaping (String) -> Void
    ) {
        self.viewModel = viewModel
        self.store = store
        self.onSelectEvent = onSelectEvent
        self.onAddEvent = onAddEvent
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Section Header
            HStack(spacing: 8) {
                Text("WEEKLY SCHEDULE")
                    .font(HeliTypography.eyebrow(11))
                    .foregroundColor(HeliColors.mutedGray)
                    .tracking(1.4)
                Spacer()
            }
            .padding(.horizontal, 20)

            // 7-day strip selector
            let loads = viewModel.dayLoads(store: store)
            HStack(spacing: 6) {
                ForEach(viewModel.daysOfWeek(), id: \.self) { dateStr in
                    dayPill(dateStr: dateStr, load: loads[dateStr] ?? PlanViewModel.DayLoad())
                }
            }
            .padding(.horizontal, 16)

            // Selected Day Panel
            VStack(alignment: .leading, spacing: 12) {
                // Day Title row
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(viewModel.formatFullDayHeader(viewModel.selectedDay))
                            .font(HeliTypography.headline(16))
                            .foregroundColor(HeliColors.greenInk)

                        let dayEvs = selectedDayEvents
                        Text("\(dayEvs.count) stop\(dayEvs.count == 1 ? "" : "s")")
                            .font(HeliTypography.caption(11))
                            .foregroundColor(HeliColors.mutedGray)
                    }

                    Spacer()

                    Button(action: { onAddEvent(viewModel.selectedDay) }) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .bold))
                            Text("Add stop")
                                .font(HeliTypography.actionButton(11))
                        }
                        .foregroundColor(HeliColors.forestGreen)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(HeliColors.forestTint)
                        .clipShape(Capsule())
                    }
                }

                // Day Timeline Events
                let evs = selectedDayEvents
                if evs.isEmpty {
                    VStack(spacing: 6) {
                        Text("No stops scheduled for this day.")
                            .font(HeliTypography.body(13))
                            .foregroundColor(HeliColors.mutedGray)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                } else {
                    let morning = evs.filter { $0.time < "12:00" }
                    let afternoon = evs.filter { $0.time >= "12:00" }

                    if !morning.isEmpty {
                        timelineSection(title: "MORNING", events: morning)
                    }

                    if !afternoon.isEmpty {
                        timelineSection(title: "AFTERNOON & EVENING", events: afternoon)
                    }
                }
            }
            .padding(16)
            .background(HeliColors.cardWarmWhite)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(HeliColors.sageRule, lineWidth: 0.8)
            )
            .padding(.horizontal, 16)
        }
    }

    private var selectedDayEvents: [TaskRecord] {
        store.records()
            .filter { $0.date == viewModel.selectedDay }
            .sorted { $0.time < $1.time }
    }

    private func dayPill(dateStr: String, load: PlanViewModel.DayLoad) -> some View {
        let isSelected = viewModel.selectedDay == dateStr

        return Button(action: {
            viewModel.selectedDay = dateStr
        }) {
            VStack(spacing: 4) {
                Text(viewModel.formatDayName(dateStr))
                    .font(HeliTypography.eyebrow(10))
                    .foregroundColor(isSelected ? HeliColors.forestGreen : HeliColors.mutedGray)

                Text(viewModel.formatDayNum(dateStr))
                    .font(HeliTypography.headline(14))
                    .foregroundColor(isSelected ? HeliColors.forestGreen : HeliColors.greenInk)

                // Load dot: deeper with more stops, ochre when the day may clash
                Circle()
                    .fill(dotColor(load))
                    .frame(width: 6, height: 6)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(isSelected ? HeliColors.forestTint : HeliColors.cardWarmWhite)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? HeliColors.forestGreen : HeliColors.sageRule, lineWidth: isSelected ? 1.5 : 0.8)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func timelineSection(title: String, events: [TaskRecord]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(HeliTypography.eyebrow(10))
                .foregroundColor(HeliColors.mutedGray)
                .tracking(1.2)
                .padding(.top, 4)

            VStack(spacing: 8) {
                ForEach(events) { ev in
                    timelineRow(ev: ev)
                }
            }
        }
    }

    private func timelineRow(ev: TaskRecord) -> some View {
        Button(action: { onSelectEvent(ev) }) {
            HStack(alignment: .center, spacing: 10) {
                // Time
                VStack(alignment: .trailing, spacing: 2) {
                    Text(TimeFormat.formatTime(ev.time))
                        .font(HeliTypography.monoTime(12))
                        .foregroundColor(HeliColors.greenInk)
                    Text(TimeFormat.formatTime(ev.endTime))
                        .font(HeliTypography.caption(10))
                        .foregroundColor(HeliColors.mutedGray)
                }
                .frame(width: 60, alignment: .trailing)

                // Status pill line
                Rectangle()
                    .fill(ev.owner == "TBD" ? HeliColors.clayText : HeliColors.forestGreen)
                    .frame(width: 3, height: 36)
                    .clipShape(Capsule())

                // Event details
                VStack(alignment: .leading, spacing: 2) {
                    Text(ev.title)
                        .font(HeliTypography.cardTitle(14))
                        .foregroundColor(HeliColors.greenInk)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text(ev.location)
                            .font(HeliTypography.caption(11))
                            .foregroundColor(HeliColors.mutedGray)
                            .lineLimit(1)

                        if !ev.kids.isEmpty {
                            Text("•")
                                .font(.system(size: 9))
                                .foregroundColor(HeliColors.sageRule)
                            ForEach(ev.kids, id: \.self) { kid in
                                Text(kid)
                                    .font(HeliTypography.chipLabel(10))
                                    .foregroundColor(HeliColors.greenInk)
                            }
                        }
                    }
                }

                Spacer()

                // Driver badge
                if ev.owner.lowercased() == "tbd" {
                    Text("TBD")
                        .font(HeliTypography.eyebrow(9))
                        .foregroundColor(HeliColors.clayText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(HeliColors.clayWash)
                        .clipShape(Capsule())
                } else {
                    AvatarDisc(name: ev.owner, size: 24)
                }
            }
            .padding(10)
            .background(HeliColors.canvasIvory.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func dotColor(_ load: PlanViewModel.DayLoad) -> Color {
        guard load.count > 0 else { return HeliColors.sageRule }
        let base: Color
        if load.hasMissing {
            base = HeliColors.clayText
        } else if load.hasConflict {
            base = HeliColors.sunOchre
        } else {
            base = HeliColors.forestGreen
        }
        return base.opacity(dotOpacity(load.count))
    }

    /// One stop reads clearly, and the dot deepens to solid by a five-stop day.
    private func dotOpacity(_ count: Int) -> Double {
        min(1.0, 0.45 + 0.14 * Double(count - 1))
    }
}

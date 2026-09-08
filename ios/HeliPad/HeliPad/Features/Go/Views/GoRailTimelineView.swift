import SwiftUI

public struct GoRailTimelineView: View {
    public var events: [AnalyzedEvent]
    public var heroId: String?
    public var onSelect: (TaskRecord) -> Void
    public var onToggleDone: (TaskRecord) -> Void
    public var onAddStop: () -> Void

    public init(
        events: [AnalyzedEvent],
        heroId: String? = nil,
        onSelect: @escaping (TaskRecord) -> Void,
        onToggleDone: @escaping (TaskRecord) -> Void,
        onAddStop: @escaping () -> Void
    ) {
        self.events = events
        self.heroId = heroId
        self.onSelect = onSelect
        self.onToggleDone = onToggleDone
        self.onAddStop = onAddStop
    }

    public var body: some View {
        VStack(spacing: 16) {
            let morning = events.filter { PlanCore.mins($0.event.time) < 720 }
            let afternoon = events.filter { PlanCore.mins($0.event.time) >= 720 }

            if !morning.isEmpty {
                periodSection(title: "Morning", items: morning)
            }

            if !afternoon.isEmpty {
                periodSection(title: "Afternoon", items: afternoon)
            }

            if events.isEmpty {
                VStack(spacing: 8) {
                    Text("Nothing on the schedule")
                        .font(HeliTypography.body(14))
                        .foregroundColor(HeliColors.mutedGray)
                }
                .padding(.vertical, 24)
            }

            // Add a stop button
            Button(action: onAddStop) {
                HStack(spacing: 8) {
                    HeliIcon("plus", size: 14)
                        .foregroundColor(HeliColors.forestGreen)
                    Text("Add a stop")
                        .font(HeliTypography.buttonLabel(14))
                        .foregroundColor(HeliColors.greenInk)
                }
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(HeliColors.activeNavTab)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(HeliColors.sageRule, lineWidth: 1)
                )
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 20)
    }

    private func periodSection(title: String, items: [AnalyzedEvent]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(HeliTypography.eyebrow(10))
                .foregroundColor(HeliColors.mutedGray)
                .tracking(1.2)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                ForEach(items) { analyzed in
                    timelineRow(analyzed: analyzed)
                        .padding(.vertical, 10)

                    if analyzed.id != items.last?.id {
                        Divider()
                            .background(HeliColors.sageRule)
                            .padding(.leading, 54)
                    }
                }
            }
            .padding(.horizontal, 14)
            .background(HeliColors.cardWarmWhite)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(HeliColors.sageRule.opacity(0.8), lineWidth: 0.8)
            )
        }
    }

    private func timelineRow(analyzed: AnalyzedEvent) -> some View {
        let e = analyzed.event
        let isTBD = PlanCore.unassigned(e)
        let isNow = (e.id == heroId)

        return Button(action: { onSelect(e) }) {
            HStack(alignment: .top, spacing: 10) {
                // Time Column
                VStack(alignment: .leading, spacing: 2) {
                    Text(formatTime(e.time))
                        .font(HeliTypography.railTime(13))
                        .foregroundColor(e.done ? HeliColors.mutedGray : HeliColors.greenInk)
                }
                .frame(width: 66, alignment: .leading)

                // Checkbox Marker
                Button(action: { onToggleDone(e) }) {
                    ZStack {
                        Circle()
                            .stroke(e.done ? HeliColors.forestGreen : HeliColors.sageRule, lineWidth: 1.8)
                            .frame(width: 20, height: 20)
                        if e.done {
                            Circle()
                                .fill(HeliColors.forestGreen)
                                .frame(width: 14, height: 14)
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                }
                .buttonStyle(.plain)
                .frame(width: 22)

                // Body Column
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        // Status Dot
                        statusDot(done: e.done, isTBD: isTBD, isNow: isNow, status: analyzed.status)

                        Text(e.title)
                            .font(HeliTypography.railTitle(13.5))
                            .foregroundColor(e.done ? HeliColors.mutedGray : HeliColors.greenInk)
                            .strikethrough(e.done, color: HeliColors.mutedGray)
                            .lineLimit(1)

                        if isTBD {
                            Text("Unassigned")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(HeliColors.warningClay)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(HeliColors.tbd.bg)
                                .clipShape(Capsule())
                        }
                    }

                    HStack(spacing: 6) {
                        HeliIcon(PlanCore.needsTravel(e) ? e.mode : "house", size: 11)
                            .foregroundColor(HeliColors.mutedGray)
                        Text(e.location)
                            .font(HeliTypography.railMeta(11.5))
                            .foregroundColor(HeliColors.mutedGray)
                            .lineLimit(1)
                        if !e.kids.isEmpty {
                            Text("(\(e.kids.joined(separator: ", ")))")
                                .font(HeliTypography.railMeta(11))
                                .foregroundColor(HeliColors.mutedGray)
                        }
                    }

                    if let addr = e.formattedAddress, !addr.isEmpty, addr != e.location {
                        Text(addr)
                            .font(HeliTypography.caption(10.5))
                            .foregroundColor(HeliColors.mutedGray.opacity(0.85))
                            .lineLimit(1)
                            .padding(.leading, 17)
                    }

                    if analyzed.detail.eta != nil, PlanCore.needsTravel(e) {
                        Text("Leave \(TimeFormat.formatTime(analyzed.detail.leave))")
                            .font(HeliTypography.railLeave(11))
                            .foregroundColor(HeliColors.forestGreen)
                    }
                }

                Spacer()

                // Driver Disc
                AvatarDisc(name: e.owner, size: 28, showNameBelow: true)
                    .frame(width: 42)
            }
        }
        .buttonStyle(.plain)
        .opacity(e.done ? 0.6 : 1.0)
    }

    private func statusDot(done: Bool, isTBD: Bool, isNow: Bool, status: String) -> some View {
        if isNow && !done {
            return AnyView(PulsingStatusDot(color: HeliColors.forestGreen))
        }

        let dotColor: Color = {
            if done { return Color(hex: "#cbd3bd") }
            if isTBD { return HeliColors.sunOchre }
            if status == "review" { return HeliColors.warningClay }
            return Color(hex: "#c2cbb6") // Standard subtle sage dot for future scheduled stops
        }()

        return AnyView(
            Circle()
                .fill(dotColor)
                .frame(width: 7, height: 7)
        )
    }

    private func formatTime(_ t: String) -> String {
        return TimeFormat.formatTime(t)
    }
}

public struct PulsingStatusDot: View {
    public var color: Color
    @State private var isDimmed: Bool = false

    public init(color: Color) {
        self.color = color
    }

    public var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .scaleEffect(isDimmed ? 0.82 : 1.0)
            .opacity(isDimmed ? 0.35 : 1.0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    isDimmed = true
                }
            }
    }
}

import SwiftUI

public struct GoDialCardView: View {
    public var event: TaskRecord?
    public var now: Int
    public var options: PlanningOptions
    public var liveDriveTime: Int?
    public var isDeviceLocationLive: Bool
    public var onEdit: () -> Void
    public var onToggleDone: () -> Void
    public var onDirections: () -> Void

    public init(
        event: TaskRecord?,
        now: Int,
        options: PlanningOptions,
        liveDriveTime: Int? = nil,
        isDeviceLocationLive: Bool = false,
        onEdit: @escaping () -> Void,
        onToggleDone: @escaping () -> Void,
        onDirections: @escaping () -> Void
    ) {
        self.event = event
        self.now = now
        self.options = options
        self.liveDriveTime = liveDriveTime
        self.isDeviceLocationLive = isDeviceLocationLive
        self.onEdit = onEdit
        self.onToggleDone = onToggleDone
        self.onDirections = onDirections
    }

    public var body: some View {
        guard let e = event else {
            // Resting state: All clear
            return AnyView(allClearCard)
        }

        let cand = PlanCore.candidate(e, e.owner, [], options)
        let effectiveEta: Int? = liveDriveTime ?? (isDeviceLocationLive ? nil : cand.eta)
        let hasTravelRequired: Bool = {
            if let live = liveDriveTime {
                return live > 0
            }
            return PlanCore.needsTravel(e)
        }()
        let noTravel = !hasTravelRequired
        let start = PlanCore.mins(e.time)
        let depart: Int
        if effectiveEta == nil || e.allDay || noTravel {
            depart = start
        } else {
            depart = start - (effectiveEta! + options.buffer)
        }
        let target = noTravel ? start : depart
        let minsUntil = target - now

        let tone: UrgencyTone
        if now >= start {
            tone = .started
        } else if minsUntil <= 0 {
            tone = .now
        } else if minsUntil <= 15 {
            tone = .soon
        } else {
            tone = .ontrack
        }

        let cardBg: Color = {
            switch tone {
            case .now, .started: return HeliColors.toneClay
            case .soon: return HeliColors.toneOlive
            default: return Color(hex: "#234d3d")
            }
        }()

        let fraction = TimeFormat.countdownFraction(minutesUntil: minsUntil)

        let hasRoute = effectiveEta != nil || noTravel
        let (title, unit, isWord, isHours) = computeCenterText(minsUntil: minsUntil, start: start, noTravel: noTravel, cand: cand, tone: tone, hasRoute: hasRoute)

        return AnyView(
            VStack(alignment: .center, spacing: 16) {
                // Top row: Dial Instrument + Route Spine
                HStack(alignment: .center, spacing: 18) {
                    GoDialInstrument(
                        fraction: fraction,
                        tone: tone,
                        centerTitle: title,
                        centerUnit: unit,
                        isWord: isWord,
                        isHours: isHours
                    )

                    // Route beside dial
                    routeColumn(
                        e: e,
                        depart: depart,
                        start: start,
                        noTravel: noTravel,
                        eta: effectiveEta,
                        isLiveGPS: isDeviceLocationLive && liveDriveTime != nil
                    )
                }
                .padding(.top, 4)

                // Centered Event Info (Serif editorial title + location link)
                Button(action: onEdit) {
                    VStack(spacing: 6) {
                        Text(e.title)
                            .font(.system(size: 25, weight: .bold, design: .serif))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)

                        VStack(spacing: 3) {
                            HStack(spacing: 6) {
                                HeliIcon(noTravel ? "house" : e.mode, size: 13)
                                    .foregroundColor(Color.white.opacity(0.9))
                                Text(e.location)
                                    .font(HeliTypography.caption(13.5))
                                    .foregroundColor(Color.white.opacity(0.95))
                                    .lineLimit(1)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10.5, weight: .bold))
                                    .foregroundColor(Color.white.opacity(0.7))
                            }
                            if let addr = e.formattedAddress, !addr.isEmpty, addr != e.location {
                                Text(addr)
                                    .font(HeliTypography.caption(11.5))
                                    .foregroundColor(Color.white.opacity(0.75))
                                    .lineLimit(1)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .buttonStyle(.plain)

                // Centered Child / Solo Badge (Dark translucent pill)
                let childNames = e.kids.isEmpty ? (e.kid?.isEmpty == false ? [e.kid!] : []) : e.kids
                let isSolo = childNames.isEmpty
                let badgeLabel: String = {
                    if isSolo {
                        let who = (e.owner.isEmpty || e.owner == "TBD") ? "Adult" : e.owner
                        return "Solo · \(who)"
                    } else if childNames.contains("All") {
                        return "All kids"
                    } else {
                        return childNames.joined(separator: ", ")
                    }
                }()
                HStack(spacing: 6) {
                    Image(systemName: "person")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.85))
                    Text(badgeLabel)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(Color(hex: "#1b4435"))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 0.8))

                // Actions Row: Directions (cream/butter) + Checkmark
                actionsRow(e: e, noTravel: noTravel)
            }
            .padding(20)
            .frame(maxWidth: .infinity)
            .background(
                ZStack {
                    cardBg

                    // Orbit / Radar Concentric Bands on right
                    GeometryReader { geo in
                        let cx = geo.size.width * 1.02
                        let cy = geo.size.height * 0.28
                        ZStack {
                            Circle()
                                .stroke(Color.white.opacity(0.045), lineWidth: 22)
                                .frame(width: 220, height: 220)
                            Circle()
                                .stroke(Color.white.opacity(0.035), lineWidth: 32)
                                .frame(width: 360, height: 360)
                        }
                        .position(x: cx, y: cy)
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .shadow(color: cardBg.opacity(0.25), radius: 10, x: 0, y: 5)
        )
    }

    private var allClearCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 16) {
                GoDialInstrument(
                    fraction: 1.0,
                    tone: .clear,
                    centerTitle: "✓",
                    centerUnit: "ALL CLEAR",
                    isWord: true,
                    isHours: false
                )
                VStack(alignment: .leading, spacing: 4) {
                    Text("All clear")
                        .font(.system(size: 24, weight: .bold, design: .serif))
                        .foregroundColor(.white)
                    Text("Every handoff done for today.")
                        .font(HeliTypography.body(13))
                        .foregroundColor(Color.white.opacity(0.8))
                }
                Spacer()
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HeliColors.toneForest)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private func routeColumn(e: TaskRecord, depart: Int, start: Int, noTravel: Bool, eta: Int?, isLiveGPS: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if noTravel {
                HStack(spacing: 8) {
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(TimeFormat.formatTime(e.time))
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                        Text("TOGETHER")
                            .font(HeliTypography.eyebrow(9))
                            .foregroundColor(Color.white.opacity(0.72))
                            .tracking(1.4)
                    }
                }
            } else {
                // Depart node
                HStack(spacing: 8) {
                    Circle()
                        .stroke(Color.white, lineWidth: 2)
                        .frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(TimeFormat.formatTime(depart))
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                        Text("LEAVE")
                            .font(HeliTypography.eyebrow(9))
                            .foregroundColor(Color.white.opacity(0.72))
                            .tracking(1.4)
                    }
                }

                // Vertical dashed line with bead
                let legHeight: CGFloat = 40
                let progress: CGFloat = {
                    if start <= depart { return 0 }
                    let p = CGFloat(now - depart) / CGFloat(start - depart)
                    return max(0, min(1, p))
                }()

                HStack(spacing: 12) {
                    ZStack(alignment: .top) {
                        Rectangle()
                            .fill(Color.clear)
                            .frame(width: 2, height: legHeight)
                            .overlay(
                                Path { path in
                                    path.move(to: CGPoint(x: 1, y: 0))
                                    path.addLine(to: CGPoint(x: 1, y: legHeight))
                                }
                                .stroke(Color.white.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                            )

                        if progress > 0 && progress < 1 {
                            TransitBeadView()
                                .offset(y: legHeight * progress - 4)
                        }
                    }
                    .frame(width: 8)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(eta != nil ? TimeFormat.formatDuration(eta!) : "Route needed")
                            .font(.system(size: 11.5, weight: .semibold))
                            .italic()
                            .foregroundColor(Color.white.opacity(0.85))

                        if isLiveGPS && eta != nil {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color(hex: "#6ee7b7"))
                                    .frame(width: 5, height: 5)
                                Text("LIVE GPS")
                                    .font(.system(size: 8.5, weight: .bold))
                                    .foregroundColor(Color(hex: "#6ee7b7"))
                                    .tracking(0.8)
                            }
                        }
                    }
                }
                .padding(.vertical, 2)

                // Arrive node
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color(hex: "#e8e4c9"))
                        .frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(TimeFormat.formatTime(start))
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                        Text((e.mode == "Home" || e.location.lowercased() == "home") ? "HOME" : "ARRIVE")
                            .font(HeliTypography.eyebrow(9))
                            .foregroundColor(Color.white.opacity(0.72))
                            .tracking(1.4)
                    }
                }
            }
        }
    }

    private func actionsRow(e: TaskRecord, noTravel: Bool) -> some View {
        HStack(spacing: 10) {
            if e.done {
                Button(action: onToggleDone) {
                    Text("Reopen")
                        .font(HeliTypography.buttonLabel(15))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Color.white.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            } else if e.owner == "TBD" {
                Button(action: onEdit) {
                    Text("Assign a driver")
                        .font(HeliTypography.buttonLabel(15))
                        .foregroundColor(HeliColors.greenInk)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Color(hex: "#e8e4c9"))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            } else if noTravel {
                Button(action: onToggleDone) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                        Text("Done")
                    }
                    .font(HeliTypography.buttonLabel(15))
                    .foregroundColor(HeliColors.greenInk)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Color(hex: "#e8e4c9"))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            } else {
                Button(action: onDirections) {
                    HStack(spacing: 8) {
                        Image(systemName: "location.north.fill")
                            .font(.system(size: 13, weight: .bold))
                            .rotationEffect(.degrees(45))
                        Text("Directions")
                            .font(HeliTypography.buttonLabel(15))
                    }
                    .foregroundColor(HeliColors.greenInk)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Color(hex: "#e8e4c9"))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                Button(action: onToggleDone) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 56, height: 50)
                        .background(Color(hex: "#345f4e"))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        }
    }

    private func computeCenterText(minsUntil: Int, start: Int, noTravel: Bool, cand: CandidateDetail, tone: UrgencyTone, hasRoute: Bool) -> (String, String, Bool, Bool) {
        if !hasRoute && cand.unknown {
            return ("CHECK", "route needed", true, false)
        }
        if tone == .now {
            return ("NOW", noTravel ? "be there" : "leave", true, false)
        }
        if tone == .started {
            let late = max(0, now - start)
            let lateStr = TimeFormat.formatDurationShort(late)
            return ("LATE", "\(lateStr) ago", true, false)
        }
        if minsUntil <= 60 {
            return ("\(max(0, minsUntil))", noTravel ? "MIN · BE THERE" : "MIN · TO LEAVE", false, false)
        } else {
            let str = TimeFormat.formatDurationShort(minsUntil)
            return (str, noTravel ? "TO ARRIVAL" : "TO LEAVE", false, true)
        }
    }
}

public struct TransitBeadView: View {
    @State private var breathe: Bool = false

    public init() {}

    public var body: some View {
        ZStack {
            Circle()
                .fill(HeliColors.highlightGold.opacity(breathe ? 0.35 : 0.8))
                .frame(width: breathe ? 10 : 8, height: breathe ? 10 : 8)
            Circle()
                .fill(HeliColors.highlightGold)
                .frame(width: 6, height: 6)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                breathe = true
            }
        }
    }
}

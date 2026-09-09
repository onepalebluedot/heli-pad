import SwiftUI

public struct PlanDecisionListView: View {
    public var decisions: [AnalyzedEvent]
    public var onAssign: (TaskRecord) -> Void
    public var onReview: (AnalyzedEvent) -> Void
    public var onDismiss: ((String) -> Void)?

    public init(
        decisions: [AnalyzedEvent],
        onAssign: @escaping (TaskRecord) -> Void,
        onReview: @escaping (AnalyzedEvent) -> Void,
        onDismiss: ((String) -> Void)? = nil
    ) {
        self.decisions = decisions
        self.onAssign = onAssign
        self.onReview = onReview
        self.onDismiss = onDismiss
    }

    public var body: some View {
        if !decisions.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                // Section Header
                HStack(spacing: 8) {
                    Text("ACT FIRST")
                        .font(HeliTypography.eyebrow(11))
                        .foregroundColor(HeliColors.mutedGray)
                        .tracking(1.4)

                    Text("\(decisions.count)")
                        .font(HeliTypography.eyebrow(10))
                        .foregroundColor(HeliColors.clayText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(HeliColors.clayWash)
                        .clipShape(Capsule())

                    Spacer()
                }
                .padding(.horizontal, 20)

                // Decision Cards
                VStack(spacing: 10) {
                    ForEach(decisions) { item in
                        decisionCard(item: item)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func decisionCard(item: AnalyzedEvent) -> some View {
        let ev = item.event
        return VStack(alignment: .leading, spacing: 10) {
            // Keep the date/time independent from the variable-width risk badges.
            // When several risks are present, one shared row can compress this
            // capsule until its text wraps a character at a time.
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: "calendar")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(HeliColors.forestGreen)
                    Text(formatDayDate(ev.date))
                        .font(HeliTypography.cardTitle(13))
                        .foregroundColor(HeliColors.greenInk)
                    Text("·")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(HeliColors.sageRule)
                    Text(TimeFormat.formatTime(ev.time))
                        .font(HeliTypography.monoTime(12))
                        .foregroundColor(HeliColors.greenInk.opacity(0.85))
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4.5)
                .background(HeliColors.canvasIvory)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(HeliColors.sageRule, lineWidth: 0.8)
                )
                .fixedSize(horizontal: true, vertical: false)

                if !item.risks.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(item.risks, id: \.self) { r in
                            Text(r.label)
                                .font(HeliTypography.eyebrow(10))
                                .foregroundColor(riskColor(r.type))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3.5)
                                .background(riskBg(r.type))
                                .clipShape(Capsule())
                        }
                    }
                }
            }

            // Middle row: Title, Location, Kids
            VStack(alignment: .leading, spacing: 5) {
                Text(ev.title)
                    .font(HeliTypography.cardTitle(17))
                    .foregroundColor(HeliColors.greenInk)

                HStack(spacing: 6) {
                    HeliIcons.icon(name: ev.mode.lowercased(), size: 13, color: HeliColors.mutedGray)
                    Text(ev.location)
                        .font(HeliTypography.caption(13.5))
                        .foregroundColor(HeliColors.mutedGray)

                    if !ev.kids.isEmpty {
                        Text("•")
                            .font(.system(size: 11))
                            .foregroundColor(HeliColors.sageRule)
                        ForEach(ev.kids, id: \.self) { kid in
                            Text(kid)
                                .font(HeliTypography.chipLabel(11.5))
                                .foregroundColor(HeliColors.greenInk)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(HeliColors.canvasIvory)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(HeliColors.sageRule.opacity(0.6), lineWidth: 0.6))
                        }
                    }
                }
            }

            // Bottom action row
            HStack {
                if ev.owner.lowercased() == "tbd" {
                    Text("No driver assigned")
                        .font(HeliTypography.caption(13.5))
                        .foregroundColor(HeliColors.clayText)
                } else {
                    HStack(spacing: 5) {
                        AvatarDisc(name: ev.owner, size: 22)
                        Text(ev.owner)
                            .font(HeliTypography.caption(13.5))
                            .foregroundColor(HeliColors.greenInk)
                    }
                }

                Spacer()

                if ev.owner.lowercased() == "tbd" {
                    Button(action: {
                        onAssign(ev)
                    }) {
                        Text("Assign")
                            .font(HeliTypography.actionButton(13))
                            .foregroundColor(HeliColors.forestGreen)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(HeliColors.forestTint)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(HeliColors.forestGreen.opacity(0.3), lineWidth: 0.8))
                    }
                } else {
                    HStack(spacing: 8) {
                        Button(action: {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            onDismiss?(item.id)
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .semibold))
                                Text("Dismiss")
                                    .font(HeliTypography.actionButton(12.5))
                            }
                            .foregroundColor(HeliColors.mutedGray)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 7)
                            .background(HeliColors.canvasIvory)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(HeliColors.sageRule, lineWidth: 0.8))
                        }

                        Button(action: {
                            onReview(item)
                        }) {
                            Text("Review")
                                .font(HeliTypography.actionButton(13))
                                .foregroundColor(HeliColors.forestGreen)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(HeliColors.forestTint)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(HeliColors.forestGreen.opacity(0.3), lineWidth: 0.8))
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(HeliColors.cardWarmWhite)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(item.status == "missing" ? HeliColors.clayText.opacity(0.3) : HeliColors.sageRule, lineWidth: 1)
        )
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

    private func riskColor(_ type: String) -> Color {
        switch type {
        case "driver": return HeliColors.clayText
        case "overlap": return HeliColors.clayText
        case "tight": return HeliColors.ochreDark
        default: return HeliColors.mutedGray
        }
    }

    private func riskBg(_ type: String) -> Color {
        switch type {
        case "driver": return HeliColors.clayWash
        case "overlap": return HeliColors.clayWash
        case "tight": return HeliColors.butterLight
        default: return HeliColors.canvasIvory
        }
    }
}

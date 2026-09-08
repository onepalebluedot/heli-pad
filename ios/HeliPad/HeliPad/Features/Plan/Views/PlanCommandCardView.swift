import SwiftUI

public struct PlanCommandCardView: View {
    public var unassignedCount: Int
    public var reviewCount: Int
    public var routinesCount: Int
    public var onReview: () -> Void
    public var onRebalance: () -> Void
    public var onPriorities: () -> Void
    public var onTapUnassigned: (() -> Void)?
    public var onTapReview: (() -> Void)?
    public var onTapRoutines: (() -> Void)?

    public init(
        unassignedCount: Int,
        reviewCount: Int,
        routinesCount: Int,
        onReview: @escaping () -> Void,
        onRebalance: @escaping () -> Void,
        onPriorities: @escaping () -> Void,
        onTapUnassigned: (() -> Void)? = nil,
        onTapReview: (() -> Void)? = nil,
        onTapRoutines: (() -> Void)? = nil
    ) {
        self.unassignedCount = unassignedCount
        self.reviewCount = reviewCount
        self.routinesCount = routinesCount
        self.onReview = onReview
        self.onRebalance = onRebalance
        self.onPriorities = onPriorities
        self.onTapUnassigned = onTapUnassigned
        self.onTapReview = onTapReview
        self.onTapRoutines = onTapRoutines
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header: readiness badge & status text
            HStack(alignment: .center) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    Text(statusTitle)
                        .font(HeliTypography.eyebrow(10))
                        .foregroundColor(HeliColors.greenInk)
                        .tracking(1.2)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(HeliColors.cardWarmWhite)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(HeliColors.sageRule, lineWidth: 0.6))

                Spacer()

                Button(action: onPriorities) {
                    HStack(spacing: 4) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 11))
                        Text("Rules")
                            .font(HeliTypography.chipLabel(11))
                    }
                    .foregroundColor(HeliColors.forestGreen)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(HeliColors.cardWarmWhite)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(HeliColors.sageRule, lineWidth: 0.6))
                }
            }

            // Headline
            Text(statusHeadline)
                .font(HeliTypography.headline(20))
                .foregroundColor(HeliColors.greenInk)
                .lineLimit(2)

            // 3 Stat metrics
            HStack(spacing: 8) {
                Button(action: {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onTapUnassigned?()
                }) {
                    statBoxContent(count: unassignedCount, label: "Unassigned", highlight: unassignedCount > 0)
                }
                .buttonStyle(StatBoxButtonStyle(highlight: unassignedCount > 0, tone: .clay))

                Button(action: {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onTapReview?()
                }) {
                    statBoxContent(count: reviewCount, label: "To review", highlight: reviewCount > 0)
                }
                .buttonStyle(StatBoxButtonStyle(highlight: reviewCount > 0, tone: .butter))

                Button(action: {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onTapRoutines?()
                }) {
                    statBoxContent(count: routinesCount, label: "Shortcuts", highlight: false)
                }
                .buttonStyle(StatBoxButtonStyle(highlight: false, tone: .sage))
            }

            // Action row
            HStack(spacing: 10) {
                Button(action: onReview) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Review assignments")
                            .font(HeliTypography.actionButton(13))
                    }
                    .foregroundColor(HeliColors.cardWarmWhite)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(HeliColors.forestGreen)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Button(action: onRebalance) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 12))
                        Text("Rebalance")
                            .font(HeliTypography.actionButton(12))
                    }
                    .foregroundColor(HeliColors.greenInk)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(HeliColors.cardWarmWhite)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(HeliColors.sageRule, lineWidth: 0.8))
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(cardBorder, lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }

    private var isReady: Bool {
        unassignedCount == 0 && reviewCount == 0
    }

    private var statusColor: Color {
        if unassignedCount > 0 { return HeliColors.ochreDark }
        if reviewCount > 0 { return HeliColors.ochreLight }
        return HeliColors.forestGreen
    }

    private var statusTitle: String {
        if unassignedCount > 0 { return "ATTENTION NEEDED" }
        if reviewCount > 0 { return "NEEDS REVIEW" }
        return "WEEK READY"
    }

    private var statusHeadline: String {
        if unassignedCount > 0 {
            return "\(unassignedCount) handoff\(unassignedCount == 1 ? "" : "s") still need a driver."
        }
        if reviewCount > 0 {
            return "\(reviewCount) stop\(reviewCount == 1 ? "" : "s") have tight slack or conflicts."
        }
        return "All weekly shortcuts and stops are assigned."
    }

    private var cardBackground: Color {
        if unassignedCount > 0 {
            return HeliColors.clayWash
        }
        if reviewCount > 0 {
            return HeliColors.butterLight.opacity(0.4)
        }
        return HeliColors.forestTint
    }

    private var cardBorder: Color {
        if unassignedCount > 0 {
            return HeliColors.clayText.opacity(0.3)
        }
        return HeliColors.sageRule
    }

    private func statBoxContent(count: Int, label: String, highlight: Bool) -> some View {
        VStack(spacing: 2) {
            Text("\(count)")
                .font(HeliTypography.headline(19))
                .foregroundColor(highlight ? HeliColors.clayText : HeliColors.greenInk)
            Text(label)
                .font(HeliTypography.caption(10.5))
                .foregroundColor(HeliColors.mutedGray)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
    }
}

public enum StatTone {
    case clay, butter, sage
}

public struct StatBoxButtonStyle: ButtonStyle {
    public var highlight: Bool
    public var tone: StatTone

    public init(highlight: Bool = false, tone: StatTone = .sage) {
        self.highlight = highlight
        self.tone = tone
    }

    public func makeBody(configuration: Configuration) -> some View {
        let isPressed = configuration.isPressed
        let normalBg = HeliColors.cardWarmWhite
        let pressedBg: Color = {
            switch tone {
            case .clay: return Color(hex: "#f9ebe7")
            case .butter: return Color(hex: "#faeed0")
            case .sage: return Color(hex: "#e8ede1")
            }
        }()

        let normalBorder = highlight ? HeliColors.clayText.opacity(0.35) : HeliColors.sageRule
        let pressedBorder: Color = {
            switch tone {
            case .clay: return HeliColors.warningText
            case .butter: return HeliColors.sunOchre
            case .sage: return HeliColors.forestGreen
            }
        }()

        return configuration.label
            .background(isPressed ? pressedBg : normalBg)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(isPressed ? pressedBorder : normalBorder, lineWidth: isPressed ? 1.6 : (highlight ? 1.0 : 0.7))
            )
            .shadow(
                color: isPressed ? Color.black.opacity(0.12) : Color.black.opacity(0.04),
                radius: isPressed ? 1 : 3,
                x: 0,
                y: isPressed ? 1 : 2
            )
            .scaleEffect(isPressed ? 0.93 : 1.0)
            .offset(y: isPressed ? 1.5 : 0)
            .animation(.spring(response: 0.22, dampingFraction: 0.6), value: isPressed)
    }
}


import SwiftUI
import AssistantKit

/// Renders one typed card in the app's visual language.
///
/// There is no branch here that draws model text: every string comes from
/// `AssistantCopy` or from household data the app fetched itself, and
/// household data is drawn quoted, in a text view, never as markup.
public struct AssistantCardView: View {
    public let card: AssistantCard
    public var onOpenEvent: ((String, String) -> Void)?
    public var onConfirmProposal: (() -> Void)?
    public var onCancelProposal: (() -> Void)?
    public var onQuickReply: ((String) -> Void)?

    public init(
        card: AssistantCard,
        onOpenEvent: ((String, String) -> Void)? = nil,
        onConfirmProposal: (() -> Void)? = nil,
        onCancelProposal: (() -> Void)? = nil,
        onQuickReply: ((String) -> Void)? = nil
    ) {
        self.card = card
        self.onOpenEvent = onOpenEvent
        self.onConfirmProposal = onConfirmProposal
        self.onCancelProposal = onCancelProposal
        self.onQuickReply = onQuickReply
    }

    public var body: some View {
        switch card {
        case .summary(let c):
            Text(c.text)
                .font(HeliTypography.body(14.5))
                .foregroundStyle(HeliColors.greenInk)
                .fixedSize(horizontal: false, vertical: true)

        case .eventList(let c):
            HeliCard {
                VStack(alignment: .leading, spacing: 0) {
                    sectionHead(c.periodLabel, icon: "calendar-days")
                    if c.rows.isEmpty {
                        Text("Nothing scheduled.")
                            .font(HeliTypography.railMeta())
                            .foregroundStyle(HeliColors.mutedGray)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                    }
                    ForEach(Array(c.rows.enumerated()), id: \.offset) { index, row in
                        if index > 0 { rule }
                        EventRowView(row: row, onOpen: onOpenEvent)
                    }
                    if c.omittedCount > 0 {
                        rule
                        Text("\(c.omittedCount) more not shown")
                            .font(HeliTypography.caption())
                            .foregroundStyle(HeliColors.mutedGray)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                    }
                }
            }

        case .people(let c):
            HeliCard {
                VStack(alignment: .leading, spacing: 0) {
                    sectionHead("Household", icon: "users-round")
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(c.caregivers) { person in
                            personRow(person.name, person.relationship)
                        }
                        if !c.children.isEmpty {
                            Eyebrow(text: "Children").padding(.top, 4)
                            ForEach(c.children) { person in
                                personRow(person.name, "Child")
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
            }

        case .places(let c):
            HeliCard {
                VStack(alignment: .leading, spacing: 0) {
                    sectionHead("Saved places", icon: "map-pin")
                    VStack(alignment: .leading, spacing: 9) {
                        ForEach(c.places) { place in
                            HStack(spacing: 8) {
                                Text(place.name)
                                    .font(HeliTypography.cardTitle())
                                    .foregroundStyle(HeliColors.greenInk)
                                Spacer(minLength: 8)
                                if !place.isVerified {
                                    Text("no location saved")
                                        .font(HeliTypography.caption(10))
                                        .foregroundStyle(HeliColors.mutedGray)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
            }

        case .proposal(let c):
            ProposalCardView(
                card: c,
                onOpenEvent: onOpenEvent,
                onConfirm: onConfirmProposal,
                onCancel: onCancelProposal
            )

        case .trends(let c):
            TrendCardView(card: c)

        case .help(let c):
            HeliCard {
                VStack(alignment: .leading, spacing: 0) {
                    sectionHead(c.title, icon: "info")
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(c.body.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(HeliTypography.body(13.5))
                                .foregroundStyle(HeliColors.greenInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
            }

        case .clarification(let c):
            HeliCard(backgroundColor: HeliColors.butterLight) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(c.question)
                        .font(HeliTypography.cardTitle(15))
                        .foregroundStyle(HeliColors.greenInk)
                        .fixedSize(horizontal: false, vertical: true)
                    FlowRow(spacing: 8) {
                        ForEach(c.options) { option in
                            Button { onQuickReply?(option.reply) } label: {
                                Text(option.label).font(HeliTypography.actionButton())
                            }
                            .buttonStyle(HeliChipButton())
                        }
                    }
                }
                .padding(16)
            }

        case .refusal(let c):
            HeliCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text(c.text)
                        .font(HeliTypography.body(13.5))
                        .foregroundStyle(HeliColors.greenInk)
                        .fixedSize(horizontal: false, vertical: true)
                    if !c.suggestions.isEmpty {
                        Eyebrow(text: "I can")
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(c.suggestions, id: \.self) { suggestion in
                                Button { onQuickReply?(suggestion) } label: {
                                    HStack(spacing: 6) {
                                        HeliIcon(name: "chevron-right", size: 10)
                                        Text(suggestion).font(HeliTypography.actionButton())
                                        Spacer(minLength: 0)
                                    }
                                    .foregroundStyle(HeliColors.forestGreen)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(16)
            }

        case .receipt(let c):
            HeliCard {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        HeliIcon(name: "circle-check", size: 16)
                            .foregroundStyle(HeliColors.forestGreen)
                        Text(c.headline)
                            .font(HeliTypography.serifTitle(19, weight: .medium))
                            .foregroundStyle(HeliColors.forestGreen)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 10)

                    VStack(alignment: .leading, spacing: 6) {
                        if !c.detail.isEmpty {
                            Text(c.detail)
                                .font(HeliTypography.railMeta())
                                .foregroundStyle(HeliColors.greenInk)
                        }
                        statusLine(c.syncLabel)
                        if let external = c.externalCalendarLabel {
                            statusLine(external)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)

                    ForEach(Array(c.rows.prefix(4).enumerated()), id: \.offset) { index, row in
                        if index == 0 { rule }
                        EventRowView(row: row, onOpen: onOpenEvent)
                        if index < min(3, c.rows.count - 1) { rule }
                    }
                    if c.rows.count > 4 {
                        rule
                        Text("\(c.rows.count - 4) more")
                            .font(HeliTypography.caption())
                            .foregroundStyle(HeliColors.mutedGray)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                    }
                }
            }

        case .failure(let c):
            HeliCard(backgroundColor: HeliColors.clayWash) {
                HStack(alignment: .top, spacing: 10) {
                    HeliIcon(name: "triangle-alert", size: 14)
                        .foregroundStyle(HeliColors.warningText)
                    Text(c.text)
                        .font(HeliTypography.body(13.5))
                        .foregroundStyle(HeliColors.warningClay)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(16)
            }
        }
    }

    // MARK: - Shared pieces

    @ViewBuilder
    private func sectionHead(_ title: String, icon: String) -> some View {
        HStack(spacing: 7) {
            HeliIcon(name: icon, size: 11)
                .foregroundStyle(HeliColors.forestGreen.opacity(0.75))
            Eyebrow(text: title, color: HeliColors.forestGreen.opacity(0.9))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 15)
        .padding(.bottom, 11)
    }

    private var rule: some View {
        Rectangle()
            .fill(HeliColors.sageRule.opacity(0.55))
            .frame(height: 0.8)
            .padding(.leading, 16)
    }

    private func statusLine(_ text: String) -> some View {
        Text(text)
            .font(HeliTypography.caption(10.5))
            .foregroundStyle(HeliColors.mutedGray)
    }

    private func personRow(_ name: String, _ relationship: String) -> some View {
        let tone = HeliColors.personColor(for: name)
        return HStack(spacing: 10) {
            Circle()
                .fill(tone.bg)
                .frame(width: 26, height: 26)
                .overlay(
                    Text(String(name.prefix(1)))
                        .font(HeliTypography.eyebrow(11))
                        .foregroundStyle(tone.text)
                )
            Text(name)
                .font(HeliTypography.cardTitle())
                .foregroundStyle(HeliColors.greenInk)
            Text(relationship)
                .font(HeliTypography.caption())
                .foregroundStyle(HeliColors.mutedGray)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Event row

struct EventRowView: View {
    let row: EventRow
    var onOpen: ((String, String) -> Void)?

    var body: some View {
        Button {
            onOpen?(row.eventID, row.date)
        } label: {
            HStack(alignment: .top, spacing: 11) {
                // Category spine, the same cue the planner's rows use.
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(HeliColors.categoryColor(for: row.category))
                    .frame(width: 3)
                    .frame(maxHeight: .infinity)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Text("\(row.time)\u{2013}\(row.endTime)")
                            .font(HeliTypography.monoTime(11.5))
                            .foregroundStyle(HeliColors.mutedGray)
                        Text(CalendarMath.shortLabel(row.date))
                            .font(HeliTypography.railTime(11.5))
                            .foregroundStyle(HeliColors.mutedGray)
                        if row.isPast {
                            Text("past")
                                .font(HeliTypography.caption(9.5))
                                .foregroundStyle(HeliColors.mutedGray.opacity(0.8))
                        }
                    }
                    // Household-authored text: quoted, inert, never markup.
                    Text("\u{201C}\(row.title)\u{201D}")
                        .font(HeliTypography.railTitle())
                        .foregroundStyle(HeliColors.greenInk)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(row.locationName)
                        .font(HeliTypography.railMeta(11.5))
                        .foregroundStyle(HeliColors.mutedGray)
                }

                Spacer(minLength: 6)
                OwnerChip(label: row.ownerLabel, isUnassigned: row.isUnassigned)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.title), \(CalendarMath.shortLabel(row.date)) at \(row.time), \(row.ownerLabel)")
        .accessibilityHint("Opens this event")
    }
}

struct OwnerChip: View {
    let label: String
    let isUnassigned: Bool

    var body: some View {
        let tone = HeliColors.personColor(for: label)
        Text(label)
            .font(HeliTypography.chipLabel(10.5))
            .foregroundStyle(tone.text)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(tone.bg.opacity(isUnassigned ? 0.9 : 0.75))
            )
            .fixedSize()
    }
}

// MARK: - Review

struct ProposalCardView: View {
    let card: ProposalCard
    var onOpenEvent: ((String, String) -> Void)?
    var onConfirm: (() -> Void)?
    var onCancel: (() -> Void)?
    @State private var showsAllRows = false

    private var visibleRows: [EventRow] {
        showsAllRows ? card.rows : Array(card.rows.prefix(4))
    }

    var body: some View {
        HeliCard {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 7) {
                    Eyebrow(text: "Review \u{00B7} nothing saved yet", color: HeliColors.sunOchre)
                    Text(card.headline)
                        .font(HeliTypography.serifTitle(20, weight: .medium))
                        .foregroundStyle(HeliColors.forestGreen)
                        .fixedSize(horizontal: false, vertical: true)
                    if let rule = card.ruleDescription {
                        HStack(spacing: 6) {
                            HeliIcon(name: "repeat-2", size: 11)
                                .foregroundStyle(HeliColors.mutedGray)
                            Text(rule)
                                .font(HeliTypography.railMeta())
                                .foregroundStyle(HeliColors.greenInk)
                        }
                    }
                    Text("\(card.affectedCount) event\(card.affectedCount == 1 ? "" : "s") \u{00B7} \(card.periodLabel)")
                        .font(HeliTypography.caption(10.5))
                        .foregroundStyle(HeliColors.mutedGray)
                    Text(card.destinationNote)
                        .font(HeliTypography.caption(10.5))
                        .foregroundStyle(HeliColors.mutedGray)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)

                // What the app filled in because the request did not say.
                if !card.assumptions.isEmpty {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(card.assumptions, id: \.self) { assumption in
                            HStack(alignment: .top, spacing: 7) {
                                HeliIcon(name: "info", size: 11)
                                    .foregroundStyle(HeliColors.sunOchre)
                                Text(assumption)
                                    .font(HeliTypography.caption(11))
                                    .foregroundStyle(HeliColors.greenInk)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(HeliColors.ochreLight.opacity(0.55))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }

                if !card.conflicts.isEmpty {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: 6) {
                            HeliIcon(name: "triangle-alert", size: 11)
                                .foregroundStyle(HeliColors.warningText)
                            Eyebrow(
                                text: "\(card.conflicts.count) conflict\(card.conflicts.count == 1 ? "" : "s")",
                                color: HeliColors.warningText
                            )
                        }
                        ForEach(card.conflicts.prefix(4)) { conflict in
                            Text("\(CalendarMath.shortLabel(conflict.date)) \u{00B7} \(conflict.detail)")
                                .font(HeliTypography.caption(11))
                                .foregroundStyle(HeliColors.warningClay)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if card.conflicts.count > 4 {
                            Text("\(card.conflicts.count - 4) more")
                                .font(HeliTypography.caption(10))
                                .foregroundStyle(HeliColors.warningClay.opacity(0.8))
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(HeliColors.clayWash)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }

                Rectangle()
                    .fill(HeliColors.sageRule.opacity(0.55))
                    .frame(height: 0.8)

                ForEach(Array(visibleRows.enumerated()), id: \.offset) { index, row in
                    if index > 0 {
                        Rectangle()
                            .fill(HeliColors.sageRule.opacity(0.55))
                            .frame(height: 0.8)
                            .padding(.leading, 16)
                    }
                    EventRowView(row: row, onOpen: onOpenEvent)
                }

                if card.rows.count > 4 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { showsAllRows.toggle() }
                    } label: {
                        Text(showsAllRows
                             ? "Show fewer"
                             : "Show all \(card.rows.count) occurrences")
                            .font(HeliTypography.actionButton(12))
                            .foregroundStyle(HeliColors.forestGreen)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 11)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                Rectangle()
                    .fill(HeliColors.sageRule.opacity(0.55))
                    .frame(height: 0.8)

                HStack(spacing: 10) {
                    Button("Confirm") { onConfirm?() }
                        .buttonStyle(HeliPrimaryButton())
                    Button("Cancel") { onCancel?() }
                        .buttonStyle(HeliSecondaryButton())
                }
                .padding(16)
            }
        }
    }
}

// MARK: - Trends

struct TrendCardView: View {
    let card: TrendCard

    var body: some View {
        HeliCard {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 5) {
                    Eyebrow(text: "Recorded", color: HeliColors.forestGreen.opacity(0.9))
                    Text(card.periodLabel)
                        .font(HeliTypography.serifTitle(20, weight: .medium))
                        .foregroundStyle(HeliColors.forestGreen)
                    Text(card.comparisonLabel)
                        .font(HeliTypography.caption(10.5))
                        .foregroundStyle(HeliColors.mutedGray)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)

                if let note = card.partialPeriodNote {
                    HStack(alignment: .top, spacing: 7) {
                        HeliIcon(name: "info", size: 11)
                            .foregroundStyle(HeliColors.sunOchre)
                        Text(note)
                            .font(HeliTypography.caption(11))
                            .foregroundStyle(HeliColors.greenInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(HeliColors.ochreLight.opacity(0.55))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }

                VStack(spacing: 10) {
                    ForEach(card.metrics) { metric in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(metric.title)
                                .font(HeliTypography.railMeta(12.5))
                                .foregroundStyle(HeliColors.greenInk)
                            Spacer(minLength: 8)
                            Text("\(metric.currentValue)")
                                .font(.system(size: 19, weight: .bold, design: .default).monospacedDigit())
                                .foregroundStyle(HeliColors.forestGreen)
                            ChangeBadge(change: metric.change)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 14)

                if !card.workload.isEmpty {
                    barSection("Who is driving", rows: card.workload.map { ($0.name, $0.count, HeliColors.personColor(for: $0.name).ink) })
                }
                if !card.categoryMix.isEmpty {
                    barSection("Activity mix", rows: card.categoryMix.map { ($0.category, $0.count, HeliColors.categoryColor(for: $0.category)) })
                }

                if !card.notes.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(card.notes.enumerated()), id: \.offset) { _, note in
                            Text(note)
                                .font(HeliTypography.caption(10))
                                .foregroundStyle(HeliColors.mutedGray)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
            }
        }
    }

    @ViewBuilder
    private func barSection(_ title: String, rows: [(String, Int, Color)]) -> some View {
        let maximum = max(rows.map(\.1).max() ?? 1, 1)
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: title)
            ForEach(rows, id: \.0) { name, count, tint in
                HStack(spacing: 9) {
                    Text(name)
                        .font(HeliTypography.railMeta(12))
                        .foregroundStyle(HeliColors.greenInk)
                        .frame(width: 92, alignment: .leading)
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(HeliColors.sageRule.opacity(0.5))
                            Capsule()
                                .fill(tint.opacity(0.85))
                                .frame(width: max(4, geometry.size.width * CGFloat(count) / CGFloat(maximum)))
                        }
                    }
                    .frame(height: 7)
                    Text("\(count)")
                        .font(HeliTypography.monoTime(11.5))
                        .foregroundStyle(HeliColors.mutedGray)
                        .frame(width: 22, alignment: .trailing)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(name), \(count)")
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
    }
}

struct ChangeBadge: View {
    let change: TrendMetric.Change

    var body: some View {
        Text(label)
            .font(HeliTypography.caption(10))
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule(style: .continuous).fill(tint.opacity(0.13)))
            .fixedSize()
    }

    /// Absolute change is always shown; a percentage only when there is a real
    /// baseline to divide by.
    private var label: String {
        switch change {
        case .percent(let pct, let absolute):
            return "\(pct >= 0 ? "+" : "")\(pct)% (\(absolute >= 0 ? "+" : "")\(absolute))"
        case .fromZero(let absolute):
            return "+\(absolute) \u{00B7} no baseline"
        case .noBaseline:
            return "no baseline"
        case .insufficientData:
            return "not enough data"
        }
    }

    private var tint: Color {
        switch change {
        case .percent(let pct, _):
            return pct == 0 ? HeliColors.mutedGray : (pct > 0 ? HeliColors.sunOchre : HeliColors.forestGreen)
        case .fromZero:
            return HeliColors.sunOchre
        case .noBaseline, .insufficientData:
            return HeliColors.mutedGray
        }
    }
}

// MARK: - Buttons

struct HeliPrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(HeliTypography.buttonLabel())
            .foregroundStyle(HeliColors.cardWarmWhite)
            .padding(.horizontal, 20)
            .padding(.vertical, 11)
            .background(
                Capsule(style: .continuous)
                    .fill(HeliColors.forestGreen.opacity(configuration.isPressed ? 0.82 : 1))
            )
    }
}

struct HeliSecondaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(HeliTypography.buttonLabel())
            .foregroundStyle(HeliColors.forestGreen)
            .padding(.horizontal, 20)
            .padding(.vertical, 11)
            .background(
                Capsule(style: .continuous)
                    .fill(configuration.isPressed ? HeliColors.forestTint : Color.clear)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(HeliColors.sageRule, lineWidth: 1)
            )
    }
}

struct HeliChipButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(HeliColors.forestGreen)
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(configuration.isPressed ? HeliColors.forestTint : HeliColors.cardWarmWhite)
            )
            .overlay(Capsule(style: .continuous).stroke(HeliColors.sageRule, lineWidth: 1))
    }
}

// MARK: - Layout

/// Wraps children onto as many lines as they need.
///
/// Clarification options are user-supplied lengths ("A different number of
/// weeks"), so a fixed HStack would push them off a small phone.
struct FlowRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

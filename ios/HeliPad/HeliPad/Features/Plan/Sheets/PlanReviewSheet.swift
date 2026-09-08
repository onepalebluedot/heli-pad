import SwiftUI

public struct PlanReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject public var store: AppStore
    public var currentWeek: String
    public var initialFilter: ReviewFilterMode
    public var onSelectEvent: (TaskRecord) -> Void
    public var onAssignEvent: ((TaskRecord) -> Void)?

    @State private var selectedFilter: ReviewFilterMode

    public init(
        store: AppStore,
        currentWeek: String,
        initialFilter: ReviewFilterMode = .all,
        onSelectEvent: @escaping (TaskRecord) -> Void,
        onAssignEvent: ((TaskRecord) -> Void)? = nil
    ) {
        self.store = store
        self.currentWeek = currentWeek
        self.initialFilter = initialFilter
        self._selectedFilter = State(initialValue: initialFilter)
        self.onSelectEvent = onSelectEvent
        self.onAssignEvent = onAssignEvent
    }

    public var body: some View {
        NavigationStack {
            let summary = PlanCore.summary(
                weekEvents,
                store.planningOptions()
            )
            let unassigned = summary.list.filter { $0.status == "missing" }
            let reviewItems = summary.list.filter { $0.status == "review" && !store.isReviewDismissed(eventId: $0.id) }
            let dismissedReviews = summary.list.filter { $0.status == "review" && store.isReviewDismissed(eventId: $0.id) }
            let readyItems = summary.list.filter { $0.status == "ready" }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Header Status Summary
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Weekly Readiness Review")
                            .font(HeliTypography.mastheadDate(22))
                            .foregroundColor(HeliColors.greenInk)

                        Text("\(summary.total) total stops · \(unassigned.count) unassigned · \(reviewItems.count) need review")
                            .font(HeliTypography.caption(12))
                            .foregroundColor(HeliColors.mutedGray)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(HeliColors.cardWarmWhite)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(HeliColors.sageRule, lineWidth: 0.8))

                    // Segmented Filter Tabs
                    HStack(spacing: 6) {
                        filterButton(title: "All", count: summary.total, mode: .all, countColor: HeliColors.forestGreen)
                        filterButton(title: "Unassigned", count: unassigned.count, mode: .unassigned, countColor: unassigned.count > 0 ? HeliColors.clayText : HeliColors.mutedGray)
                        filterButton(title: "To Review", count: reviewItems.count, mode: .review, countColor: reviewItems.count > 0 ? HeliColors.ochreDark : HeliColors.mutedGray)
                    }

                    // Content based on selected filter
                    if selectedFilter == .all {
                        if !unassigned.isEmpty {
                            riskGroup(title: "UNASSIGNED DRIVERS", count: unassigned.count, items: unassigned, badgeColor: HeliColors.clayText, badgeBg: HeliColors.clayWash)
                        }

                        if !reviewItems.isEmpty {
                            riskGroup(title: "CONFLICTS & TIGHT SLACK", count: reviewItems.count, items: reviewItems, badgeColor: HeliColors.ochreDark, badgeBg: HeliColors.butterLight)
                        }

                        if !readyItems.isEmpty {
                            readyGroup(items: readyItems)
                        }

                        if !dismissedReviews.isEmpty {
                            dismissedGroup(items: dismissedReviews)
                        }

                        if unassigned.isEmpty && reviewItems.isEmpty && readyItems.isEmpty && dismissedReviews.isEmpty {
                            emptyState(message: "No stops scheduled for this week.")
                        }
                    } else if selectedFilter == .unassigned {
                        if !unassigned.isEmpty {
                            riskGroup(title: "UNASSIGNED DRIVERS", count: unassigned.count, items: unassigned, badgeColor: HeliColors.clayText, badgeBg: HeliColors.clayWash)
                        } else {
                            emptyState(message: "No unassigned drivers! All stops have assigned caregivers.")
                        }
                    } else if selectedFilter == .review {
                        if !reviewItems.isEmpty {
                            riskGroup(title: "CONFLICTS & TIGHT SLACK", count: reviewItems.count, items: reviewItems, badgeColor: HeliColors.ochreDark, badgeBg: HeliColors.butterLight)
                        }

                        if !dismissedReviews.isEmpty {
                            dismissedGroup(items: dismissedReviews)
                        }

                        if reviewItems.isEmpty && dismissedReviews.isEmpty {
                            emptyState(message: "No conflicts or tight buffers found for this week.")
                        }
                    }
                }
                .padding(20)
            }
            .background(HeliColors.canvasIvory)
            .navigationTitle("Assignments Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(HeliColors.greenInk)
                }
            }
        }
    }

    private var weekEvents: [TaskRecord] {
        let endWeek = PlanCore.dateAdd(currentWeek, 6)
        return store.records().filter { $0.date >= currentWeek && $0.date <= endWeek }
    }

    private func filterButton(title: String, count: Int, mode: ReviewFilterMode, countColor: Color) -> some View {
        Button(action: {
            selectedFilter = mode
        }) {
            HStack(spacing: 5) {
                Text(title)
                    .font(HeliTypography.chipLabel(12))
                Text("\(count)")
                    .font(HeliTypography.eyebrow(10))
                    .foregroundColor(selectedFilter == mode ? HeliColors.cardWarmWhite : countColor)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(selectedFilter == mode ? HeliColors.greenInk.opacity(0.3) : HeliColors.canvasIvory)
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(selectedFilter == mode ? HeliColors.forestGreen : HeliColors.cardWarmWhite)
            .foregroundColor(selectedFilter == mode ? HeliColors.cardWarmWhite : HeliColors.greenInk)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(selectedFilter == mode ? HeliColors.forestGreen : HeliColors.sageRule, lineWidth: 0.8)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func riskGroup(title: String, count: Int, items: [AnalyzedEvent], badgeColor: Color, badgeBg: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(title)
                    .font(HeliTypography.eyebrow(11))
                    .foregroundColor(HeliColors.mutedGray)
                    .tracking(1.4)

                Text("\(count)")
                    .font(HeliTypography.eyebrow(10))
                    .foregroundColor(badgeColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(badgeBg)
                    .clipShape(Capsule())

                Spacer()

                if title.contains("CONFLICTS") && count > 0 {
                    Button(action: {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        withAnimation {
                            store.dismissAllReviews(for: items.map { $0.id })
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle")
                                .font(.system(size: 11))
                            Text("Dismiss All")
                                .font(HeliTypography.actionButton(11.5))
                        }
                        .foregroundColor(HeliColors.forestGreen)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(HeliColors.forestTint)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(HeliColors.forestGreen.opacity(0.3), lineWidth: 0.7))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }

            ForEach(items) { item in
                HStack(alignment: .center, spacing: 8) {
                    Button(action: {
                        onSelectEvent(item.event)
                        dismiss()
                    }) {
                        HStack {
                            VStack(alignment: .leading, spacing: 6) {
                                // Prominent Date Badge
                                HStack(spacing: 5) {
                                    Image(systemName: "calendar")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(HeliColors.forestGreen)
                                    Text(formatDayDate(item.event.date))
                                        .font(HeliTypography.cardTitle(12.5))
                                        .foregroundColor(HeliColors.greenInk)
                                    Text("·")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(HeliColors.sageRule)
                                    Text(TimeFormat.formatTime(item.event.time))
                                        .font(HeliTypography.monoTime(11.5))
                                        .foregroundColor(HeliColors.greenInk.opacity(0.85))
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3.5)
                                .background(HeliColors.canvasIvory)
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule().stroke(HeliColors.sageRule, lineWidth: 0.7)
                                )

                                Text(item.event.title)
                                    .font(HeliTypography.cardTitle(16))
                                    .foregroundColor(HeliColors.greenInk)

                                HStack(spacing: 6) {
                                    HeliIcons.icon(name: item.event.mode.lowercased(), size: 12, color: HeliColors.mutedGray)
                                    Text(item.event.location)
                                        .font(HeliTypography.caption(13))
                                        .foregroundColor(HeliColors.mutedGray)

                                    if !item.event.kids.isEmpty {
                                        Text("•")
                                            .font(.system(size: 10))
                                            .foregroundColor(HeliColors.sageRule)
                                        ForEach(item.event.kids, id: \.self) { kid in
                                            Text(kid)
                                                .font(HeliTypography.chipLabel(11))
                                                .foregroundColor(HeliColors.greenInk)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 1.5)
                                                .background(HeliColors.canvasIvory)
                                                .clipShape(Capsule())
                                        }
                                    }
                                }

                                if !item.risks.isEmpty {
                                    HStack(spacing: 4) {
                                        ForEach(item.risks, id: \.self) { r in
                                            Text(r.label)
                                                .font(HeliTypography.eyebrow(9.5))
                                                .foregroundColor(badgeColor)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2.5)
                                                .background(badgeBg)
                                                .clipShape(Capsule())
                                        }
                                    }
                                }
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(PlainButtonStyle())

                    if item.status == "missing", let onAssign = onAssignEvent {
                        Button(action: {
                            onAssign(item.event)
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "person.badge.plus")
                                    .font(.system(size: 11, weight: .semibold))
                                Text("Assign")
                                    .font(HeliTypography.actionButton(12))
                            }
                            .foregroundColor(HeliColors.cardWarmWhite)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(HeliColors.forestGreen)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(PlainButtonStyle())
                    } else if item.status == "review" {
                        HStack(spacing: 6) {
                            Button(action: {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                withAnimation {
                                    store.dismissReview(for: item.id)
                                }
                            }) {
                                HStack(spacing: 3) {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .semibold))
                                    Text("Dismiss")
                                        .font(HeliTypography.actionButton(11))
                                }
                                .foregroundColor(HeliColors.mutedGray)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 6)
                                .background(HeliColors.canvasIvory)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(HeliColors.sageRule, lineWidth: 0.8))
                            }
                            .buttonStyle(PlainButtonStyle())

                            Button(action: {
                                onSelectEvent(item.event)
                                dismiss()
                            }) {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(HeliColors.mutedGray)
                                    .padding(6)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    } else {
                        Button(action: {
                            onSelectEvent(item.event)
                            dismiss()
                        }) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(HeliColors.mutedGray)
                                .padding(6)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(13)
                .background(HeliColors.cardWarmWhite)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(HeliColors.sageRule, lineWidth: 0.8))
            }
        }
    }

    private func dismissedGroup(items: [AnalyzedEvent]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("DISMISSED CONCERNS")
                    .font(HeliTypography.eyebrow(11))
                    .foregroundColor(HeliColors.mutedGray)
                    .tracking(1.4)
                Text("\(items.count)")
                    .font(HeliTypography.eyebrow(10))
                    .foregroundColor(HeliColors.mutedGray)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(HeliColors.canvasIvory)
                    .clipShape(Capsule())
                Spacer()
            }

            ForEach(items) { item in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 5) {
                            Text(formatDayDate(item.event.date))
                                .font(HeliTypography.chipLabel(11))
                                .foregroundColor(HeliColors.forestGreen)
                            Text("·")
                                .foregroundColor(HeliColors.sageRule)
                            Text(TimeFormat.formatTime(item.event.time))
                                .font(HeliTypography.monoTime(11))
                                .foregroundColor(HeliColors.mutedGray)
                        }
                        Text(item.event.title)
                            .font(HeliTypography.cardTitle(14.5))
                            .foregroundColor(HeliColors.greenInk)
                        Text(item.event.location)
                            .font(HeliTypography.caption(12.5))
                            .foregroundColor(HeliColors.mutedGray)
                    }
                    Spacer()

                    Button(action: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation {
                            store.restoreReview(for: item.id)
                        }
                    }) {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.system(size: 10))
                            Text("Undo")
                                .font(HeliTypography.actionButton(11.5))
                        }
                        .foregroundColor(HeliColors.forestGreen)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(HeliColors.forestTint)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(HeliColors.forestGreen.opacity(0.3), lineWidth: 0.7))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(11)
                .background(HeliColors.cardWarmWhite.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(HeliColors.sageRule.opacity(0.6), lineWidth: 0.6))
            }
        }
    }

    private func readyGroup(items: [AnalyzedEvent]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("READY & ON TRACK")
                    .font(HeliTypography.eyebrow(11))
                    .foregroundColor(HeliColors.mutedGray)
                    .tracking(1.4)
                Text("\(items.count)")
                    .font(HeliTypography.eyebrow(10))
                    .foregroundColor(HeliColors.forestGreen)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(HeliColors.forestTint)
                    .clipShape(Capsule())
                Spacer()
            }

            ForEach(items) { item in
                readyRow(ev: item.event)
            }
        }
    }

    private func readyRow(ev: TaskRecord) -> some View {
        Button(action: {
            onSelectEvent(ev)
            dismiss()
        }) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text(formatDayDate(ev.date))
                            .font(HeliTypography.chipLabel(11))
                            .foregroundColor(HeliColors.forestGreen)
                        Text("·")
                            .foregroundColor(HeliColors.sageRule)
                        Text(TimeFormat.formatTime(ev.time))
                            .font(HeliTypography.monoTime(11))
                            .foregroundColor(HeliColors.mutedGray)
                    }
                    Text(ev.title)
                        .font(HeliTypography.cardTitle(14.5))
                        .foregroundColor(HeliColors.greenInk)
                    Text(ev.location)
                        .font(HeliTypography.caption(12.5))
                        .foregroundColor(HeliColors.mutedGray)
                }
                Spacer()
                AvatarDisc(name: ev.owner, size: 24)
            }
            .padding(11)
            .background(HeliColors.cardWarmWhite.opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(HeliColors.sageRule.opacity(0.6), lineWidth: 0.6))
        }
        .buttonStyle(PlainButtonStyle())
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

    private func emptyState(message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 28))
                .foregroundColor(HeliColors.forestGreen)
            Text(message)
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
}

import SwiftUI

/// One cadence group, or everything needing a driver, as a list of series.
/// A row opens the series detail inside the same sheet; acting on a series
/// hands back to the Plan page, which owns the assign and edit sheets.
public struct PlanRoutinesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject public var store: AppStore
    public var focus: RecurringSheetFocus
    public var load: () -> [RecurringGroup]
    public var onEditSeries: (RecurringSeries) -> Void
    public var onSetDriver: (RecurringSeries) -> Void
    public var onSelectEvent: (TaskRecord) -> Void

    @State private var searchText = ""
    private let today = PlanCore.currentDeviceDate()

    public init(
        store: AppStore,
        focus: RecurringSheetFocus,
        load: @escaping () -> [RecurringGroup],
        onEditSeries: @escaping (RecurringSeries) -> Void,
        onSetDriver: @escaping (RecurringSeries) -> Void,
        onSelectEvent: @escaping (TaskRecord) -> Void
    ) {
        self.store = store
        self.focus = focus
        self.load = load
        self.onEditSeries = onEditSeries
        self.onSetDriver = onSetDriver
        self.onSelectEvent = onSelectEvent
    }

    public var body: some View {
        // Read from the store on every render, so a driver set from the
        // detail is reflected the moment the sheet comes back.
        let groups = load()
        let inFocus = series(in: groups)
        let shown = filtered(inFocus)

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(summary(inFocus))
                        .font(HeliTypography.caption(12))
                        .foregroundColor(HeliColors.mutedGray)

                    if inFocus.isEmpty {
                        emptyState
                    } else if shown.isEmpty {
                        Text("No series match your search.")
                            .font(HeliTypography.body(13))
                            .foregroundColor(HeliColors.mutedGray)
                            .frame(maxWidth: .infinity)
                            .padding(24)
                    } else {
                        ForEach(sections(shown), id: \.title) { section in
                            sectionView(section)
                        }
                    }
                }
                .padding(20)
            }
            .background(HeliColors.canvasIvory)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Find a series")
            .navigationDestination(for: String.self) { id in
                PlanRecurringSeriesView(
                    store: store,
                    series: groups.flatMap(\.series).first { $0.id == id },
                    onEditSeries: { series in dismiss(); onEditSeries(series) },
                    onSetDriver: { series in dismiss(); onSetDriver(series) },
                    onSelectEvent: { event in dismiss(); onSelectEvent(event) }
                )
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(HeliColors.greenInk)
                }
            }
        }
    }

    // MARK: - Content

    private var title: String {
        switch focus {
        case .group(let cadence): return cadence.title
        case .needsDriver: return "Needs a driver"
        }
    }

    private func series(in groups: [RecurringGroup]) -> [RecurringSeries] {
        switch focus {
        case .group(let cadence):
            return groups.first { $0.cadence == cadence }?.series ?? []
        case .needsDriver:
            return groups.flatMap(\.series).filter(\.needsDriver).sorted { $0.next < $1.next }
        }
    }

    private func filtered(_ series: [RecurringSeries]) -> [RecurringSeries] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return series }
        return series.filter { item in
            [item.title, item.location, item.driver ?? ""].contains { $0.localizedCaseInsensitiveContains(query) }
                || item.kids.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    private func summary(_ series: [RecurringSeries]) -> String {
        let count = series.count == 1 ? "1 series" : "\(series.count) series"
        let waiting = series.filter(\.needsDriver).count
        guard waiting > 0, focus != .needsDriver else { return count }
        return "\(count) · \(waiting) need\(waiting == 1 ? "s" : "") a driver"
    }

    private struct Section {
        var title: String
        var series: [RecurringSeries]
    }

    /// Birthdays read by date; everything else by whether it is covered.
    private func sections(_ series: [RecurringSeries]) -> [Section] {
        if case .group(.yearly) = focus {
            let soon = series.filter { RecurringFormat.days(from: today, to: $0.next) <= 31 }.sorted { $0.next < $1.next }
            let later = series.filter { RecurringFormat.days(from: today, to: $0.next) > 31 }.sorted { $0.next < $1.next }
            var result = soon.isEmpty ? [] : [Section(title: "Coming up", series: soon)]
            var byMonth: [(String, [RecurringSeries])] = []
            for item in later {
                let month = RecurringFormat.month(item.next, today: today)
                if byMonth.last?.0 == month { byMonth[byMonth.count - 1].1.append(item) } else { byMonth.append((month, [item])) }
            }
            result += byMonth.map { Section(title: $0.0, series: $0.1) }
            return result
        }
        if focus == .needsDriver { return [Section(title: "", series: series)] }
        let waiting = series.filter(\.needsDriver)
        let covered = series.filter { !$0.needsDriver }
        return [Section(title: "Needs a driver", series: waiting), Section(title: "Covered", series: covered)]
            .filter { !$0.series.isEmpty }
    }

    private func sectionView(_ section: Section) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !section.title.isEmpty {
                Text(section.title.uppercased())
                    .font(HeliTypography.eyebrow(11))
                    .foregroundColor(HeliColors.mutedGray)
                    .tracking(1.4)
            }
            VStack(spacing: 0) {
                ForEach(Array(section.series.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Divider().background(HeliColors.sageRule) }
                    row(item)
                }
            }
            .padding(.horizontal, 14)
            .background(HeliColors.cardWarmWhite)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(HeliColors.sageRule, lineWidth: 0.8))
        }
    }

    private func row(_ item: RecurringSeries) -> some View {
        NavigationLink(value: item.id) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(HeliTypography.cardTitle(15))
                        .foregroundColor(HeliColors.greenInk)
                        .lineLimit(1)
                    Text(subtitle(item))
                        .font(HeliTypography.caption(12))
                        .foregroundColor(HeliColors.mutedGray)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                trailing(item)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(HeliColors.mutedGray)
            }
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Shows dates and actions for this series")
    }

    private func subtitle(_ item: RecurringSeries) -> String {
        if item.cadence == .yearly { return RecurringFormat.day(item.next) }
        var parts = [item.schedule, item.allDay ? "All day" : TimeFormat.formatTime(item.time)]
        if !item.kids.isEmpty { parts.append(item.kids.joined(separator: ", ")) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func trailing(_ item: RecurringSeries) -> some View {
        if item.needsDriver {
            RecurringChip(text: "No driver", warning: true)
        } else if item.cadence == .yearly {
            let away = RecurringFormat.days(from: today, to: item.next)
            if away <= 7 {
                RecurringChip(text: away == 0 ? "Today" : away == 1 ? "Tomorrow" : "In \(away) days", warning: false)
            }
        } else if let driver = item.driver {
            HStack(spacing: 5) {
                if driver != "Mixed" { AvatarDisc(name: driver, size: 22) }
                Text(driver == "Mixed" ? "Mixed" : driver)
                    .font(HeliTypography.caption(12))
                    .foregroundColor(HeliColors.greenInk)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: focus == .needsDriver ? "checkmark.circle" : "calendar.badge.clock")
                .font(.system(size: 30))
                .foregroundColor(HeliColors.forestGreen)
            Text(focus == .needsDriver ? "Every recurring stop has a driver." : "Nothing here has dates still to come.")
                .font(HeliTypography.caption(13))
                .foregroundColor(HeliColors.greenInk)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(HeliColors.cardWarmWhite)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(HeliColors.sageRule, lineWidth: 0.8))
    }
}

/// A small status pill: clay when something needs doing, sage otherwise.
struct RecurringChip: View {
    var text: String
    var warning: Bool

    var body: some View {
        Text(text)
            .font(HeliTypography.chipLabel(11))
            .foregroundColor(warning ? HeliColors.clayText : HeliColors.forestGreen)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(warning ? HeliColors.clayWash : HeliColors.forestTint)
            .clipShape(Capsule())
    }
}

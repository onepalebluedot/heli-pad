import SwiftUI

/// One recurring series: how it repeats, where, who drives, and its next
/// dates. Pushed inside the Recurring sheet, so the list behind it stays a
/// row per series however many dates each one has.
struct PlanRecurringSeriesView: View {
    @ObservedObject var store: AppStore
    var series: RecurringSeries?
    var onEditSeries: (RecurringSeries) -> Void
    var onSetDriver: (RecurringSeries) -> Void
    var onSelectEvent: (TaskRecord) -> Void

    @State private var showAllDates = false
    private static let datesShown = 4

    var body: some View {
        ScrollView {
            if let series {
                VStack(alignment: .leading, spacing: 16) {
                    header(series)
                    details(series)
                    // A birthday is a reminder, not a handoff: no driver to set.
                    if !(series.allDay && series.cadence == .yearly) {
                        driver(series)
                    }
                    upcoming(series)
                    actions(series)
                }
                .padding(20)
            } else {
                Text("This series has no dates still to come.")
                    .font(HeliTypography.body(14))
                    .foregroundColor(HeliColors.mutedGray)
                    .frame(maxWidth: .infinity)
                    .padding(32)
            }
        }
        .background(HeliColors.canvasIvory)
        // The serif header already names the series; repeating it in the bar
        // read as a stutter.
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Sections

    private func header(_ series: RecurringSeries) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(series.title)
                .font(HeliTypography.mastheadDate(22))
                .foregroundColor(HeliColors.greenInk)
            Text("\(series.schedule) · \(RecurringFormat.span(series))")
                .font(HeliTypography.body(14))
                .foregroundColor(HeliColors.mutedGray)
        }
        .accessibilityElement(children: .combine)
    }

    private func details(_ series: RecurringSeries) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if series.location != store.home() && !series.location.isEmpty {
                detailRow(symbol: "mappin.and.ellipse", title: series.location, note: routeNote(series))
            }
            if !series.kids.isEmpty {
                detailRow(symbol: "person.2", title: series.kids.joined(separator: ", "), note: nil)
            }
            detailRow(symbol: "calendar", title: series.source == .household ? extent(series) : "From \(calendarName(series))", note: nil)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .background(HeliColors.cardWarmWhite)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(HeliColors.sageRule, lineWidth: 0.8))
    }

    private func detailRow(symbol: String, title: String, note: String?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .foregroundColor(HeliColors.mutedGray)
                .frame(width: 20)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(HeliTypography.body(14))
                    .foregroundColor(HeliColors.greenInk)
                if let note {
                    Text(note)
                        .font(HeliTypography.caption(12))
                        .foregroundColor(HeliColors.mutedGray)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func driver(_ series: RecurringSeries) -> some View {
        if series.needsDriver {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(series.driver == nil ? "No driver yet" : "Some dates need a driver")
                        .font(HeliTypography.cardTitle(14))
                    Text("Set one for every date in the series.")
                        .font(HeliTypography.caption(12))
                }
                .foregroundColor(HeliColors.clayText)
                Spacer()
                Button("Set driver") { onSetDriver(series) }
                    .font(HeliTypography.actionButton(13))
                    .foregroundColor(HeliColors.clayText)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
                    .background(HeliColors.cardWarmWhite)
                    .clipShape(Capsule())
                    .contentShape(Rectangle())
                    .accessibilityHint("Chooses a driver for every date in this series")
            }
            .padding(12)
            .background(HeliColors.clayWash)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        } else if let name = series.driver {
            HStack(spacing: 10) {
                if name != "Mixed" { AvatarDisc(name: name, size: 28) }
                Text(name == "Mixed" ? "Drivers vary by date" : "\(name) drives")
                    .font(HeliTypography.cardTitle(14))
                    .foregroundColor(HeliColors.greenInk)
                Spacer()
                Button("Change") { onSetDriver(series) }
                    .font(HeliTypography.actionButton(13))
                    .foregroundColor(HeliColors.forestGreen)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                    .accessibilityLabel("Change driver")
                    .accessibilityHint("Chooses a driver for every date in this series")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .background(HeliColors.cardWarmWhite)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(HeliColors.sageRule, lineWidth: 0.8))
        }
    }

    private func upcoming(_ series: RecurringSeries) -> some View {
        let dates = showAllDates ? series.upcoming : Array(series.upcoming.prefix(Self.datesShown))
        return VStack(alignment: .leading, spacing: 8) {
            Text("UPCOMING")
                .font(HeliTypography.eyebrow(11))
                .foregroundColor(HeliColors.mutedGray)
                .tracking(1.4)

            if dates.isEmpty {
                // A yearly series past this year's date: its next one is
                // projected, and imports when it comes within a month.
                Text("Next on \(RecurringFormat.day(series.next)).")
                    .font(HeliTypography.body(14))
                    .foregroundColor(HeliColors.greenInk)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(dates.enumerated()), id: \.element.id) { index, event in
                        if index > 0 { Divider().background(HeliColors.sageRule) }
                        dateRow(event, series: series)
                    }
                }
                .padding(.horizontal, 14)
                .background(HeliColors.cardWarmWhite)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(HeliColors.sageRule, lineWidth: 0.8))
            }

            if series.upcoming.count > Self.datesShown {
                Button(showAllDates ? "Show fewer" : "Show all \(series.upcoming.count) dates") {
                    showAllDates.toggle()
                }
                .font(HeliTypography.actionButton(13))
                .foregroundColor(HeliColors.forestGreen)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
        }
    }

    private func dateRow(_ event: TaskRecord, series: RecurringSeries) -> some View {
        let changed = event.recurrenceOverride?.modified == true
        let lacksDriver = PlanCore.lacksCaregiver(event, store.planningOptions())
        let time = event.allDay ? "All day" : TimeFormat.formatTime(event.time)
        return Button(action: { onSelectEvent(event) }) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(RecurringFormat.day(event.date))
                        .font(HeliTypography.cardTitle(14))
                        .foregroundColor(HeliColors.greenInk)
                    Text(changed ? "Changed · \(time)" : time)
                        .font(HeliTypography.caption(12))
                        .foregroundColor(HeliColors.mutedGray)
                }
                Spacer(minLength: 8)
                if lacksDriver {
                    RecurringChip(text: "No driver", warning: true)
                } else if !(series.allDay && series.cadence == .yearly) {
                    HStack(spacing: 5) {
                        AvatarDisc(name: event.owner, size: 22)
                        Text(event.owner)
                            .font(HeliTypography.caption(12))
                            .foregroundColor(HeliColors.greenInk)
                    }
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(HeliColors.mutedGray)
            }
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens this date on its own")
    }

    @ViewBuilder
    private func actions(_ series: RecurringSeries) -> some View {
        switch series.source {
        case .household:
            Button(action: { onEditSeries(series) }) {
                Label("Edit series", systemImage: "square.and.pencil")
                    .font(HeliTypography.actionButton(14))
                    .foregroundColor(HeliColors.forestGreen)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(HeliColors.forestTint)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Changes every date in this series")
        case .google, .apple:
            // An edit made here would be undone by the next import, so the
            // screen says where the series can actually be changed.
            Text(series.allDay && series.cadence == .yearly
                 ? "This repeats in \(calendarName(series)). Change it there."
                 : "This series repeats in \(calendarName(series)). Change its dates or time there; drivers stay set here.")
                .font(HeliTypography.caption(12))
                .foregroundColor(HeliColors.mutedGray)
        }
    }

    // MARK: - Wording

    private func routeNote(_ series: RecurringSeries) -> String? {
        guard let next = series.upcoming.first else { return nil }
        let options = store.planningOptions()
        guard PlanCore.placeIsVerified(next, options) else { return "Route needs checking" }
        if let minutes = store.travel(origin: store.home(), destination: series.location, at: PlanCore.mins(next.time)) {
            return "\(minutes) min from home · route verified"
        }
        return "Route verified"
    }

    private func extent(_ series: RecurringSeries) -> String {
        let left = series.upcoming.count
        let last: String? = {
            if case .throughDate(let date)? = store.seriesDefinition(id: series.id)?.pattern.end { return date }
            return store.events(inSeries: series.id).map(\.date).max()
        }()
        guard let last else { return "\(left) left" }
        return "Through \(RecurringFormat.day(last)) · \(left) left"
    }

    private func calendarName(_ series: RecurringSeries) -> String {
        series.source == .apple ? "Apple Calendar" : "Google Calendar"
    }
}

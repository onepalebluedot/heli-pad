import SwiftUI

/// The Plan page's one compact card for recurring stops: a row per cadence and
/// what needs a driver. It used to list a full card per series in the week on
/// screen, which grew with every routine and changed every week.
public struct PlanRoutinesView: View {
    public var groups: [RecurringGroup]
    public var today: String
    public var onOpen: (RecurringSheetFocus) -> Void

    public init(groups: [RecurringGroup], today: String = PlanCore.currentDeviceDate(), onOpen: @escaping (RecurringSheetFocus) -> Void) {
        self.groups = groups
        self.today = today
        self.onOpen = onOpen
    }

    private var seriesCount: Int { groups.reduce(0) { $0 + $1.series.count } }
    private var needsDriverCount: Int { groups.reduce(0) { $0 + $1.needsDriverCount } }

    public var body: some View {
        if !groups.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text("RECURRING")
                        .font(HeliTypography.eyebrow(11))
                        .foregroundColor(HeliColors.mutedGray)
                        .tracking(1.4)
                    Spacer()
                    Text(seriesCount == 1 ? "1 series" : "\(seriesCount) series")
                        .font(HeliTypography.caption(12))
                        .foregroundColor(HeliColors.mutedGray)
                }
                .padding(.horizontal, 20)

                VStack(spacing: 0) {
                    if needsDriverCount > 0 {
                        needsDriverBanner
                            .padding(.bottom, 6)
                    }
                    ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                        if index > 0 {
                            Divider().background(HeliColors.sageRule)
                        }
                        groupRow(group)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(HeliColors.cardWarmWhite)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(HeliColors.sageRule, lineWidth: 0.8))
                .padding(.horizontal, 16)
            }
        }
    }

    private var needsDriverBanner: some View {
        Button(action: { onOpen(.needsDriver) }) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 13, weight: .semibold))
                Text(needsDriverCount == 1 ? "1 series needs a driver" : "\(needsDriverCount) series need a driver")
                    .font(HeliTypography.actionButton(13))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundColor(HeliColors.clayText)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(HeliColors.clayWash)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows every recurring series without a driver")
    }

    private func groupRow(_ group: RecurringGroup) -> some View {
        Button(action: { onOpen(.group(group.cadence)) }) {
            HStack(spacing: 12) {
                Image(systemName: group.cadence.symbol)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(HeliColors.forestGreen)
                    .frame(width: 32, height: 32)
                    .background(HeliColors.forestTint)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(group.cadence.title)
                        .font(HeliTypography.cardTitle(15))
                        .foregroundColor(HeliColors.greenInk)
                    if let first = soonest(group) {
                        Text("Next: \(first.title) · \(RecurringFormat.when(first, today: today))")
                            .font(HeliTypography.caption(12))
                            .foregroundColor(HeliColors.mutedGray)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 8)

                if group.needsDriverCount > 0 {
                    Circle()
                        .fill(HeliColors.clayText)
                        .frame(width: 7, height: 7)
                }
                Text("\(group.series.count)")
                    .font(HeliTypography.caption(13))
                    .foregroundColor(HeliColors.mutedGray)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(HeliColors.mutedGray)
            }
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(group.cadence.title), \(group.series.count) series")
        .accessibilityValue(accessibilityValue(group))
        .accessibilityHint("Opens the list")
    }

    /// Soonest by date, not the group's own order, which puts what needs a
    /// driver first.
    private func soonest(_ group: RecurringGroup) -> RecurringSeries? {
        group.series.min { ($0.next, $0.time) < ($1.next, $1.time) }
    }

    private func accessibilityValue(_ group: RecurringGroup) -> String {
        var parts: [String] = []
        if group.needsDriverCount > 0 { parts.append("\(group.needsDriverCount) need a driver") }
        if let first = soonest(group) { parts.append("next, \(first.title), \(RecurringFormat.when(first, today: today))") }
        return parts.joined(separator: ", ")
    }
}

/// Dates and times for recurring stops, worded relative to today the way the
/// rest of the Plan page speaks.
enum RecurringFormat {
    private static func date(_ string: String) -> Date? {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone = TimeZone(secondsFromGMT: 0)
        return df.date(from: string)
    }

    private static func format(_ string: String, _ pattern: String) -> String {
        guard let d = date(string) else { return string }
        let out = DateFormatter()
        out.locale = Locale(identifier: "en_US")
        out.dateFormat = pattern
        out.timeZone = TimeZone(secondsFromGMT: 0)
        return out.string(from: d)
    }

    static func days(from today: String, to day: String) -> Int {
        guard let a = date(today), let b = date(day) else { return 0 }
        return Int((b.timeIntervalSince(a) / 86_400).rounded())
    }

    /// "today 4:30 PM", "Tue 4:30 PM", "Oct 14", "Feb 3, 2027".
    static func when(_ series: RecurringSeries, today: String) -> String {
        let away = days(from: today, to: series.next)
        let time = series.allDay ? "" : " " + TimeFormat.formatTime(series.time)
        switch away {
        case 0: return "today" + time
        case 1: return "tomorrow" + time
        case 2..<7: return format(series.next, "EEE") + time
        default:
            let sameYear = series.next.prefix(4) == today.prefix(4)
            return format(series.next, sameYear ? "MMM d" : "MMM d, yyyy")
        }
    }

    /// "Mon, Oct 6".
    static func day(_ string: String) -> String { format(string, "EEE, MMM d") }

    /// "October", or "February 2027" outside this year.
    static func month(_ string: String, today: String) -> String {
        format(string, string.prefix(4) == today.prefix(4) ? "MMMM" : "MMMM yyyy")
    }

    /// "5:00–6:30 PM", or "All day".
    static func span(_ series: RecurringSeries) -> String {
        series.allDay ? "All day" : "\(TimeFormat.formatTime(series.time))–\(TimeFormat.formatTime(series.endTime))"
    }
}

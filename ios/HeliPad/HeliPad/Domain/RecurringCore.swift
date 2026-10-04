import Foundation

/// How often a recurring stop comes round. The Plan page groups by this
/// because the groups need different amounts of attention: a weekly series
/// needs a driver every week, a birthday never does.
public enum RecurringCadence: String, CaseIterable, Hashable {
    case weekly, monthly, yearly, other
}

/// Where a series is defined, which decides who can change it: a series made
/// here is edited here; one from a calendar is changed in that calendar, and
/// the next import would undo an edit made here.
public enum RecurringSource: Hashable {
    case household, google, apple
}

/// One series as the Plan page shows it: its rule and next date rather than
/// every occurrence, which is what made the old section grow without bound.
public struct RecurringSeries: Identifiable {
    public var id: String
    public var title: String
    public var location: String
    public var kids: [String]
    public var cadence: RecurringCadence
    /// "Every Mon and Wed", "Monthly on the 14th". No time; the screen adds it.
    public var schedule: String
    public var source: RecurringSource
    public var allDay: Bool
    public var time: String
    public var endTime: String
    public var upcoming: [TaskRecord]
    /// The next date. For a yearly series whose next date is beyond the import
    /// window this is projected from the last one seen, so a birthday does not
    /// vanish from the list for eleven months of the year.
    public var next: String
    public var needsDriver: Bool
    /// The one driver on the assigned upcoming dates, "Mixed" when they differ,
    /// nil when none is assigned.
    public var driver: String?
}

public struct RecurringGroup: Identifiable {
    public var cadence: RecurringCadence
    public var series: [RecurringSeries]

    public var id: RecurringCadence { cadence }
    public var needsDriverCount: Int { series.filter(\.needsDriver).count }
}

public enum RecurringCore {
    /// Every series in the household with something still to come.
    public static func series(
        _ records: [TaskRecord],
        definitions: [SeriesDefinition],
        options: PlanningOptions,
        today: String
    ) -> [RecurringSeries] {
        let patterns = Dictionary(definitions.map { ($0.seriesId, $0.pattern) }, uniquingKeysWith: { first, _ in first })
        let bySeries = Dictionary(grouping: records.filter { $0.seriesId != nil }, by: { $0.seriesId! })

        return bySeries.compactMap { seriesId, rows -> RecurringSeries? in
            let sorted = rows.sorted { ($0.date, $0.time) < ($1.date, $1.time) }
            guard let latest = sorted.last else { return nil }
            let upcoming = sorted.filter { $0.date >= today && !$0.done }

            // A series made here can only repeat weekly. One from a calendar
            // says how it repeats on its own rows, when its rule could be
            // read; without one it is not assumed weekly.
            let source: RecurringSource = seriesId.hasPrefix("google-series|") ? .google
                : seriesId.hasPrefix("apple-series|") ? .apple
                : .household
            let rule: SeriesRule? = source == .household
                ? SeriesRule(frequency: .weekly, rrule: "")
                : sorted.last(where: { $0.seriesRule != nil })?.seriesRule
            let cadence = cadence(of: rule)

            var next = upcoming.first?.date
            if next == nil, cadence == .yearly, let rule {
                next = projectYearly(from: latest.date, every: rule.interval, onOrAfter: today)
            }
            guard let next else { return nil }

            let shown = upcoming.first ?? latest
            let ownWeekdays = patterns[seriesId]?.weekdays ?? []
            let weekdays = ownWeekdays.isEmpty
                ? Array(Set(sorted.map { PlanCore.weekdayIndex($0.originalOccurrenceDate ?? $0.date) })).sorted()
                : ownWeekdays
            let assigned = Set(upcoming.filter { !PlanCore.lacksCaregiver($0, options) }.map(\.owner))

            return RecurringSeries(
                id: seriesId,
                title: shown.title,
                location: shown.location,
                kids: shown.kids,
                cadence: cadence,
                schedule: schedule(rule, weekdays: source == .household ? weekdays : [], date: shown.date),
                source: source,
                allDay: shown.allDay,
                time: shown.time,
                endTime: shown.endTime,
                upcoming: upcoming,
                next: next,
                needsDriver: upcoming.contains { PlanCore.lacksCaregiver($0, options) },
                driver: assigned.count > 1 ? "Mixed" : assigned.first
            )
        }
    }

    /// Most frequent first; within a group, what needs a driver, then soonest.
    public static func groups(_ series: [RecurringSeries]) -> [RecurringGroup] {
        RecurringCadence.allCases.compactMap { cadence in
            let members = series.filter { $0.cadence == cadence }.sorted {
                if $0.needsDriver != $1.needsDriver { return $0.needsDriver }
                if $0.next != $1.next { return $0.next < $1.next }
                return $0.title.localizedCompare($1.title) == .orderedAscending
            }
            return members.isEmpty ? nil : RecurringGroup(cadence: cadence, series: members)
        }
    }

    static func cadence(of rule: SeriesRule?) -> RecurringCadence {
        switch rule?.frequency {
        case .daily?, .weekly?: return .weekly
        case .monthly?: return .monthly
        case .yearly?: return .yearly
        case nil: return .other
        }
    }

    // MARK: - Schedule phrase

    private static let shortDays = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    private static let longDays = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
    private static let rruleDays = ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]
    private static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    /// How the series repeats, in words. `weekdays` (0 = Monday) stands in for
    /// a rule with no BYDAY; `date` is any occurrence, for rules that leave the
    /// day to the first event.
    public static func schedule(_ rule: SeriesRule?, weekdays: [Int], date: String) -> String {
        guard let rule else { return "Repeats" }
        let parts = ruleParts(rule.rrule)
        let n = rule.interval

        switch rule.frequency {
        case .daily:
            return n == 1 ? "Every day" : "Every \(n) days"

        case .weekly:
            var days = (parts["BYDAY"] ?? "").split(separator: ",").compactMap { rruleDays.firstIndex(of: String($0)) }
            if days.isEmpty { days = weekdays.isEmpty ? [PlanCore.weekdayIndex(date)] : weekdays }
            days = Array(Set(days)).sorted()
            if n == 1 && days == [0, 1, 2, 3, 4] { return "Every weekday" }
            if n == 1 && days.count == 7 { return "Every day" }
            let list = joined(days.map { shortDays[$0] })
            switch n {
            case 1: return "Every \(list)"
            case 2: return "Every other \(list)"
            default: return "Every \(n) weeks on \(list)"
            }

        case .monthly:
            let lead = n == 1 ? "Monthly on the" : "Every \(n) months on the"
            if let byDay = parts["BYDAY"], let (position, day) = positionedDay(byDay) {
                return "\(lead) \(position) \(longDays[day])"
            }
            let dayOfMonth = parts["BYMONTHDAY"].flatMap(Int.init) ?? dayParts(date)?.day ?? 1
            return "\(lead) \(ordinal(dayOfMonth))"

        case .yearly:
            let when = dayParts(date).map { "\(months[$0.month - 1]) \($0.day)" } ?? ""
            return n == 1 ? "Every year on \(when)" : "Every \(n) years on \(when)"
        }
    }

    private static func ruleParts(_ rrule: String) -> [String: String] {
        var parts: [String: String] = [:]
        for pair in rrule.split(separator: ";") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            if kv.count == 2 { parts[kv[0].uppercased()] = String(kv[1]).uppercased() }
        }
        return parts
    }

    /// "2TU" -> ("second", 1); "-1FR" -> ("last", 4). Only the first of a
    /// comma list is described; a rule naming several is rare for a family.
    private static func positionedDay(_ byDay: String) -> (String, Int)? {
        let first = String(byDay.split(separator: ",").first ?? "")
        guard first.count >= 3, let day = rruleDays.firstIndex(of: String(first.suffix(2))),
              let position = Int(first.dropLast(2)) else { return nil }
        let words = [1: "first", 2: "second", 3: "third", 4: "fourth", 5: "fifth", -1: "last", -2: "second to last"]
        guard let word = words[position] else { return nil }
        return (word, day)
    }

    private static func ordinal(_ n: Int) -> String {
        let suffix: String
        switch (n % 10, n % 100) {
        case (_, 11...13): suffix = "th"
        case (1, _): suffix = "st"
        case (2, _): suffix = "nd"
        case (3, _): suffix = "rd"
        default: suffix = "th"
        }
        return "\(n)\(suffix)"
    }

    private static func joined(_ items: [String]) -> String {
        guard items.count > 1 else { return items.first ?? "" }
        return items.dropLast().joined(separator: ", ") + " and " + items.last!
    }

    private static func dayParts(_ date: String) -> (year: Int, month: Int, day: Int)? {
        let p = date.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3, (1...12).contains(p[1]) else { return nil }
        return (p[0], p[1], p[2])
    }

    // MARK: - Yearly projection

    /// The first anniversary of `date`, every `years`, on or after `today`. A
    /// Feb 29 date only lands in leap years, as RFC 5545 has it.
    static func projectYearly(from date: String, every years: Int, onOrAfter today: String) -> String? {
        guard let start = dayParts(date) else { return nil }
        var year = start.year
        for _ in 0..<400 {
            let isLeap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
            if !(start.month == 2 && start.day == 29) || isLeap {
                let candidate = String(format: "%04d-%02d-%02d", year, start.month, start.day)
                if candidate >= today { return candidate }
            }
            year += max(1, years)
        }
        return nil
    }
}

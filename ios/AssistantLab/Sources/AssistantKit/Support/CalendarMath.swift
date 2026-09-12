import Foundation

/// Date and time arithmetic on the app's stored string formats ("YYYY-MM-DD",
/// "HH:mm"). Mirrors the equivalent helpers in the app's `PlanCore` so the two
/// agree exactly at integration; behaviour here is verified against the same
/// fixtures.
public enum CalendarMath {
    /// Fixed UTC calendar. Stored dates are calendar days, not instants, so
    /// doing the arithmetic in a fixed zone keeps "+7 days" from shifting
    /// across a DST boundary.
    public static let utc: TimeZone = TimeZone(secondsFromGMT: 0)!

    private static var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = utc
        c.firstWeekday = 2 // Monday
        return c
    }()

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = utc
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    public static func date(from iso: String) -> Date? {
        guard iso.count == 10 else { return nil }
        return dateFormatter.date(from: iso)
    }

    public static func iso(from date: Date) -> String {
        dateFormatter.string(from: date)
    }

    public static func isValidDate(_ iso: String) -> Bool { date(from: iso) != nil }

    /// "HH:mm" -> minutes past midnight. Returns nil on anything else, so
    /// callers cannot silently accept "7pm" or "25:00".
    public static func minutes(_ time: String) -> Int? {
        let parts = time.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].count == 2, parts[1].count == 2,
              let h = Int(parts[0]), let m = Int(parts[1]),
              (0...23).contains(h), (0...59).contains(m) else { return nil }
        return h * 60 + m
    }

    public static func time(fromMinutes total: Int) -> String {
        let clamped = max(0, min(23 * 60 + 59, total))
        return String(format: "%02d:%02d", clamped / 60, clamped % 60)
    }

    public static func addDays(_ iso: String, _ days: Int) -> String {
        guard let d = date(from: iso), let next = calendar.date(byAdding: .day, value: days, to: d) else { return iso }
        return self.iso(from: next)
    }

    /// Whole days from `a` to `b`; negative when `b` precedes `a`.
    public static func daysBetween(_ a: String, _ b: String) -> Int? {
        guard let x = date(from: a), let y = date(from: b) else { return nil }
        return calendar.dateComponents([.day], from: x, to: y).day
    }

    /// Monday of the week containing `iso`.
    public static func monday(_ iso: String) -> String {
        guard let d = date(from: iso) else { return iso }
        // weekday: 1 = Sunday ... 7 = Saturday
        let weekday = calendar.component(.weekday, from: d)
        let backwards = (weekday + 5) % 7 // Mon -> 0, Sun -> 6
        return addDays(iso, -backwards)
    }

    /// 0 = Monday ... 6 = Sunday.
    public static func weekdayIndex(_ iso: String) -> Int? {
        guard let d = date(from: iso) else { return nil }
        return (calendar.component(.weekday, from: d) + 5) % 7
    }

    public static func today(in timeZone: TimeZone, now: Date = Date()) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: now)
    }

    public static let weekdayNames = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

    /// "Sep 14" style, for card copy the app owns.
    public static func shortLabel(_ iso: String) -> String {
        guard let d = date(from: iso) else { return iso }
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = utc
        f.dateFormat = "MMM d"
        return f.string(from: d)
    }
}

/// An inclusive closed range of calendar days. Every query and every trend
/// names the period it covers; nothing is computed over an open-ended span.
public struct DateRange: Codable, Hashable, Sendable {
    public var start: String
    public var end: String

    public init?(start: String, end: String) {
        guard CalendarMath.isValidDate(start), CalendarMath.isValidDate(end), start <= end else { return nil }
        self.start = start
        self.end = end
    }

    public var dayCount: Int { (CalendarMath.daysBetween(start, end) ?? 0) + 1 }

    public func contains(_ iso: String) -> Bool { iso >= start && iso <= end }

    /// The equal-length window immediately before this one, for current-vs-previous
    /// comparison.
    public var previousEqualLength: DateRange {
        let previousEnd = CalendarMath.addDays(start, -1)
        let previousStart = CalendarMath.addDays(previousEnd, -(dayCount - 1))
        return DateRange(start: previousStart, end: previousEnd)!
    }

    public var label: String {
        "\(CalendarMath.shortLabel(start))–\(CalendarMath.shortLabel(end))"
    }
}

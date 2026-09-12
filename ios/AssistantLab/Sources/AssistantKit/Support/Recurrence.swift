import Foundation

/// Finite weekly recurrence, stored as a rule rather than inferred from the
/// surviving occurrences — so deleting the last event cannot change the
/// apparent intended end date (product decision 2).
public struct RecurrenceRule: Codable, Hashable, Sendable {
    public enum Mode: String, Codable, Sendable {
        case none
        case weekly
    }

    /// How the series is bounded. Exactly one of these, never both.
    public enum Bound: Codable, Hashable, Sendable {
        /// Inclusive number of calendar weeks starting with the week of `startDate`.
        case weeks(Int)
        /// Inclusive last day the series may land on.
        case until(String)
    }

    public var mode: Mode
    /// 0 = Monday ... 6 = Sunday.
    public var weekdays: [Int]
    public var bound: Bound
    public var startDate: String

    public init(mode: Mode, weekdays: [Int], bound: Bound, startDate: String) {
        self.mode = mode
        self.weekdays = Array(Set(weekdays)).sorted()
        self.bound = bound
        self.startDate = startDate
    }

    public static func single(on date: String) -> RecurrenceRule {
        RecurrenceRule(mode: .none, weekdays: [CalendarMath.weekdayIndex(date) ?? 0], bound: .weeks(1), startDate: date)
    }
}

public enum RecurrenceError: Error, Equatable, Sendable {
    case invalidStartDate(String)
    case invalidWeekday(Int)
    case noWeekdays
    case weekCountOutOfRange(Int)
    case invalidEndDate(String)
    case endBeforeStart(start: String, end: String)
    case producesNoOccurrences
    case tooManyOccurrences(Int, limit: Int)
}

public enum RecurrenceCore {
    /// The app's editor caps a series at 52 weeks; the assistant uses the same
    /// ceiling so chat cannot create something the manual editor would refuse.
    public static let maxWeeks = 52
    /// Hard ceiling on materialised records from one proposal. 7 days x 52
    /// weeks, so it never fires before the week cap does, but a malformed rule
    /// still cannot fan out unbounded.
    public static let maxOccurrences = 364

    /// Expands a rule into the calendar days it covers.
    ///
    /// Weeks are counted from the Monday of the start week, matching the app's
    /// existing expansion, and days before `startDate` in that first week are
    /// dropped.
    public static func dates(for rule: RecurrenceRule) throws -> [String] {
        guard CalendarMath.isValidDate(rule.startDate) else {
            throw RecurrenceError.invalidStartDate(rule.startDate)
        }
        guard !rule.weekdays.isEmpty else { throw RecurrenceError.noWeekdays }
        if let bad = rule.weekdays.first(where: { $0 < 0 || $0 > 6 }) {
            throw RecurrenceError.invalidWeekday(bad)
        }

        guard rule.mode == .weekly else { return [rule.startDate] }

        let startMonday = CalendarMath.monday(rule.startDate)
        let weekCount: Int
        var lastAllowedDate: String?

        switch rule.bound {
        case .weeks(let count):
            guard count >= 1, count <= maxWeeks else { throw RecurrenceError.weekCountOutOfRange(count) }
            weekCount = count
        case .until(let end):
            guard CalendarMath.isValidDate(end) else { throw RecurrenceError.invalidEndDate(end) }
            guard end >= rule.startDate else {
                throw RecurrenceError.endBeforeStart(start: rule.startDate, end: end)
            }
            let span = (CalendarMath.daysBetween(startMonday, end) ?? 0)
            weekCount = min(maxWeeks, span / 7 + 1)
            lastAllowedDate = end
        }

        var out: [String] = []
        for week in 0..<weekCount {
            for day in rule.weekdays {
                let date = CalendarMath.addDays(startMonday, week * 7 + day)
                if date < rule.startDate { continue }
                if let last = lastAllowedDate, date > last { continue }
                out.append(date)
            }
        }
        out.sort()
        guard !out.isEmpty else { throw RecurrenceError.producesNoOccurrences }
        guard out.count <= maxOccurrences else {
            throw RecurrenceError.tooManyOccurrences(out.count, limit: maxOccurrences)
        }
        return out
    }

    /// Plain-language description of the rule, built by app code. Used on the
    /// review card so the user confirms the rule, not a model paraphrase of it.
    public static func describe(_ rule: RecurrenceRule) -> String {
        guard rule.mode == .weekly else {
            return "Once on \(CalendarMath.shortLabel(rule.startDate))"
        }
        let days = rule.weekdays.map { CalendarMath.weekdayNames[$0] }.joined(separator: " and ")
        switch rule.bound {
        case .weeks(let n):
            return "Every \(days) for \(n) week\(n == 1 ? "" : "s")"
        case .until(let end):
            return "Every \(days) through \(CalendarMath.shortLabel(end))"
        }
    }
}

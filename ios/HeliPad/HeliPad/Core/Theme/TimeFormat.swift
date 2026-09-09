import Foundation

public enum TimeFormat {
    /// The departure ring drains only during the final 60 minutes.
    public static func countdownFraction(minutesUntil: Int) -> Double {
        min(1, max(0, Double(minutesUntil) / 60))
    }

    private static var timeFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .none
        df.timeStyle = .short
        return df
    }()

    public static func dateFrom(minutes: Int) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let startOfDay = cal.startOfDay(for: Date())
        return cal.date(byAdding: .minute, value: minutes, to: startOfDay) ?? Date()
    }

    /// Formats minutes into device-setting time (e.g. "1:16 PM" for 12h or "13:16" for 24h)
    public static func formatTime(_ minutes: Int) -> String {
        let date = dateFrom(minutes: minutes)
        return timeFormatter.string(from: date)
    }

    /// Formats "HH:mm" time string into device-setting time
    public static func formatTime(_ timeStr: String) -> String {
        let parts = timeStr.split(separator: ":")
        guard parts.count == 2,
              let h = Int(parts[0]),
              let m = Int(parts[1]) else {
            return timeStr
        }
        return formatTime(h * 60 + m)
    }

    /// Formats durations: things over 60 mins display as hours and mins (e.g. "1 hr 15 min", "2 hr", "45 min")
    public static func formatDuration(_ mins: Int) -> String {
        if mins < 60 {
            return "\(max(0, mins)) min"
        }
        let h = mins / 60
        let m = mins % 60
        if m == 0 {
            return "\(h) hr\(h == 1 ? "" : "s")"
        }
        return "\(h) hr \(m) min"
    }

    /// Compact format for pills and countdown dials (e.g. "1h 15m", "2h", "45m")
    public static func formatDurationShort(_ mins: Int) -> String {
        if mins < 60 {
            return "\(max(0, mins))m"
        }
        let h = mins / 60
        let m = mins % 60
        if m == 0 {
            return "\(h)h"
        }
        return "\(h)h \(m)m"
    }
}

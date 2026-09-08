import Foundation
import UserNotifications

/// Departure reminders.
///
/// These are *local* notifications: the phone schedules them itself and fires
/// them even with no network and no server behind the app. That matters here —
/// the household's schedule lives on the device, so there is nothing for a push
/// server to send from. Remote push would need APNs and a backend that knows
/// the schedule; when the data moves to Neon that becomes possible, but a leave
/// reminder is better as a local notification either way, because it still
/// fires in a car park with no signal.
public final class NotificationService {
    public static let shared = NotificationService()

    /// How far ahead of the stop we nudge.
    public static let leadMinutes = 10

    /// iOS keeps at most 64 pending local notifications per app; stay well under
    /// so we never silently lose the near-term ones to a far-future stop.
    private static let maxScheduled = 48

    private static let identifierPrefix = "helipad.leave."

    private let center = UNUserNotificationCenter.current()
    private var pendingWork: Task<Void, Never>?

    private init() {}

    // MARK: - Permission

    /// Asks once; afterwards the system remembers the answer and this is a no-op
    /// that simply reports what the user already chose.
    @discardableResult
    public func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    public func isAuthorized() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        default: return false
        }
    }

    // MARK: - Scheduling

    /// Coalesces bursts of saves into one reschedule. Typing in a settings field
    /// should not rewrite the whole notification queue on every keystroke.
    public func scheduleReminders(
        records: [TaskRecord],
        timeZoneId: String,
        enabled: Bool,
        debounce: Bool = true
    ) {
        pendingWork?.cancel()
        pendingWork = Task { [weak self] in
            if debounce {
                try? await Task.sleep(nanoseconds: 400_000_000)
                if Task.isCancelled { return }
            }
            await self?.applySchedule(records: records, timeZoneId: timeZoneId, enabled: enabled)
        }
    }

    /// Replaces every reminder this app owns with a fresh set. Other pending
    /// notifications are left alone — we only ever remove our own prefix.
    private func applySchedule(records: [TaskRecord], timeZoneId: String, enabled: Bool) async {
        let existing = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(Self.identifierPrefix) }
        if !existing.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: existing)
        }

        guard enabled, await isAuthorized() else { return }

        var calendar = Calendar(identifier: .gregorian)
        if timeZoneId != "device", let tz = TimeZone(identifier: timeZoneId) {
            calendar.timeZone = tz
        }

        let now = Date()
        let upcoming = records
            .filter { !$0.done && !$0.allDay }
            .compactMap { record -> (Date, TaskRecord)? in
                guard let fire = Self.reminderDate(for: record, calendar: calendar),
                      fire > now else { return nil }
                return (fire, record)
            }
            .sorted { $0.0 < $1.0 }
            .prefix(Self.maxScheduled)

        for (fireDate, record) in upcoming {
            let content = UNMutableNotificationContent()
            content.title = "Leave in \(Self.leadMinutes) minutes"
            content.body = Self.body(for: record, calendar: calendar)
            content.sound = .default

            let parts = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: fireDate
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            let request = UNNotificationRequest(
                identifier: Self.identifierPrefix + record.id,
                content: content,
                trigger: trigger
            )
            try? await center.add(request)
        }
    }

    public func cancelAll() async {
        let mine = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(Self.identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: mine)
    }

    // MARK: - Helpers

    /// The stop's start time, less the lead. The stored date is a plain calendar
    /// day and the time a plain wall clock, so both are resolved in the
    /// household's own calendar rather than parsed as an instant.
    static func reminderDate(for record: TaskRecord, calendar: Calendar) -> Date? {
        let day = record.date.split(separator: "-").compactMap { Int($0) }
        let clock = record.time.split(separator: ":").compactMap { Int($0) }
        guard day.count == 3, clock.count >= 2 else { return nil }

        var parts = DateComponents()
        parts.year = day[0]
        parts.month = day[1]
        parts.day = day[2]
        parts.hour = clock[0]
        parts.minute = clock[1]

        guard let start = calendar.date(from: parts) else { return nil }
        return start.addingTimeInterval(-Double(leadMinutes) * 60)
    }

    static func body(for record: TaskRecord, calendar: Calendar) -> String {
        var line = record.title.isEmpty ? "Your next stop" : record.title
        line += " at \(TimeFormat.formatTime(record.time))"
        if !record.location.isEmpty {
            line += " · \(record.location)"
        }
        return line
    }
}

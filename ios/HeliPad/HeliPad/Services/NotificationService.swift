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

    /// How far ahead of the calculated leave-by time we nudge.
    public static let leadMinutes = 10

    /// iOS keeps at most 64 pending local notifications per app; stay well under
    /// so we never silently lose the near-term ones to a far-future stop.
    private static let maxScheduled = 48

    private static let identifierPrefix = "helipad."

    private enum ReminderKind: Equatable {
        case leave
        case driverNeeded
    }

    private struct ReminderCandidate {
        var fireDate: Date
        var record: TaskRecord
        var kind: ReminderKind
    }

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
        driverNeededEnabled: Bool = false,
        bufferMinutes: Int = 0,
        travelTimeProvider: ((TaskRecord, Date) async -> Int?)? = nil,
        onError: ((String?) -> Void)? = nil,
        debounce: Bool = true
    ) {
        pendingWork?.cancel()
        pendingWork = Task { [weak self] in
            if debounce {
                try? await Task.sleep(nanoseconds: 400_000_000)
                if Task.isCancelled { return }
            }
            await self?.applySchedule(
                records: records,
                timeZoneId: timeZoneId,
                enabled: enabled,
                driverNeededEnabled: driverNeededEnabled,
                bufferMinutes: bufferMinutes,
                travelTimeProvider: travelTimeProvider,
                onError: onError
            )
        }
    }

    /// Replaces every reminder this app owns with a fresh set. Other pending
    /// notifications are left alone — we only ever remove our own prefix.
    private func applySchedule(
        records: [TaskRecord],
        timeZoneId: String,
        enabled: Bool,
        driverNeededEnabled: Bool,
        bufferMinutes: Int,
        travelTimeProvider: ((TaskRecord, Date) async -> Int?)?,
        onError: ((String?) -> Void)?
    ) async {
        let existing = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(Self.identifierPrefix) }
        if !existing.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: existing)
        }

        guard enabled || driverNeededEnabled else {
            await MainActor.run { onError?(nil) }
            return
        }
        guard await isAuthorized() else {
            await MainActor.run { onError?("Notifications are not authorized for HeliPad. Enable them in iOS Settings.") }
            return
        }

        var calendar = Calendar(identifier: .gregorian)
        if timeZoneId != "device", let tz = TimeZone(identifier: timeZoneId) {
            calendar.timeZone = tz
        }

        let now = Date()
        let upcoming = records
            .filter { !$0.done && !$0.allDay }
            .compactMap { record -> (Date, TaskRecord)? in
                guard let start = Self.startDate(for: record, calendar: calendar),
                      start > now else { return nil }
                return (start, record)
            }
            .sorted { $0.0 < $1.0 }

        var candidates: [ReminderCandidate] = []
        for (startDate, record) in upcoming {
            guard !Task.isCancelled else { return }

            if enabled {
                let needsTravel = PlanCore.needsTravel(record)
                let travelMinutes: Int
                if needsTravel, let travelTimeProvider {
                    travelMinutes = max(0, await travelTimeProvider(record, startDate) ?? 0)
                } else {
                    travelMinutes = 0
                }

                if let fireDate = Self.reminderDate(
                    for: record,
                    calendar: calendar,
                    travelMinutes: travelMinutes,
                    bufferMinutes: needsTravel && travelMinutes > 0 ? bufferMinutes : 0
                ), fireDate > now {
                    candidates.append(ReminderCandidate(fireDate: fireDate, record: record, kind: .leave))
                }
            }

            if driverNeededEnabled,
               PlanCore.unassigned(record),
               let fireDate = Self.driverNeededDate(for: record, calendar: calendar),
               fireDate > now {
                candidates.append(ReminderCandidate(fireDate: fireDate, record: record, kind: .driverNeeded))
            }
        }

        var schedulingErrors: [String] = []
        for candidate in candidates.sorted(by: { $0.fireDate < $1.fireDate }).prefix(Self.maxScheduled) {
            guard !Task.isCancelled else { return }

            let content = UNMutableNotificationContent()
            switch candidate.kind {
            case .leave:
                content.title = "Leave in \(Self.leadMinutes) minutes"
                content.body = Self.body(for: candidate.record, calendar: calendar)
            case .driverNeeded:
                content.title = "Driver needed in 12 hours"
                content.body = Self.driverNeededBody(for: candidate.record)
            }
            content.sound = .default

            var parts = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: candidate.fireDate
            )
            parts.timeZone = calendar.timeZone
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            let kindId = candidate.kind == .leave ? "leave." : "driver-needed."
            let request = UNNotificationRequest(
                identifier: Self.identifierPrefix + kindId + candidate.record.id,
                content: content,
                trigger: trigger
            )
            do {
                try await center.add(request)
            } catch {
                schedulingErrors.append("\(candidate.record.title.isEmpty ? "Untitled stop" : candidate.record.title): \(error.localizedDescription)")
            }
        }

        let errorMessage = schedulingErrors.isEmpty
            ? nil
            : "Some reminders could not be scheduled. \(schedulingErrors[0])"
        await MainActor.run { onError?(errorMessage) }
    }

    public func cancelAll() async {
        let mine = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(Self.identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: mine)
    }

    // MARK: - Helpers

    /// The stored date is a plain calendar day and the time a plain wall clock,
    /// so both are resolved in the household's own calendar rather than parsed
    /// as an instant.
    static func startDate(for record: TaskRecord, calendar: Calendar) -> Date? {
        let day = record.date.split(separator: "-").compactMap { Int($0) }
        let clock = record.time.split(separator: ":").compactMap { Int($0) }
        guard day.count == 3, clock.count >= 2 else { return nil }

        var parts = DateComponents()
        parts.year = day[0]
        parts.month = day[1]
        parts.day = day[2]
        parts.hour = clock[0]
        parts.minute = clock[1]

        return calendar.date(from: parts)
    }

    /// Fires before the actual leave-by time: appointment start minus the live
    /// Apple Maps drive time, household arrival buffer, and reminder lead.
    static func reminderDate(
        for record: TaskRecord,
        calendar: Calendar,
        travelMinutes: Int = 0,
        bufferMinutes: Int = 0
    ) -> Date? {
        guard let start = startDate(for: record, calendar: calendar) else { return nil }
        let minutesBeforeStart = max(0, travelMinutes) + max(0, bufferMinutes) + leadMinutes
        return start.addingTimeInterval(-Double(minutesBeforeStart) * 60)
    }

    static func driverNeededDate(for record: TaskRecord, calendar: Calendar) -> Date? {
        guard let start = startDate(for: record, calendar: calendar) else { return nil }
        return calendar.date(byAdding: .hour, value: -12, to: start)
    }

    static func body(for record: TaskRecord, calendar: Calendar) -> String {
        var line = record.title.isEmpty ? "Your next stop" : record.title
        line += " at \(TimeFormat.formatTime(record.time))"
        if !record.location.isEmpty {
            line += " · \(record.location)"
        }
        return line
    }

    static func driverNeededBody(for record: TaskRecord) -> String {
        let title = record.title.isEmpty ? "An upcoming stop" : record.title
        return "\(title) at \(TimeFormat.formatTime(record.time)) still needs a caregiver."
    }
}

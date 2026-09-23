import Foundation
import UserNotifications

/// Departure reminders, and the check-in for a stop left unfinished.
///
/// These are *local* notifications: the phone schedules them itself and fires
/// them even with no network and no server behind the app. That matters here —
/// the household's schedule lives on the device, so there is nothing for a push
/// server to send from. Remote push would need APNs and a backend that knows
/// the schedule; when the data moves to Neon that becomes possible, but a leave
/// reminder is better as a local notification either way, because it still
/// fires in a car park with no signal.
///
/// Every notification is a calendar trigger handed to the system when the
/// schedule changes. Nothing runs in the background to watch the clock, so a
/// check-in for a stop left undone costs no battery while it waits. A
/// background refresh task was the rejected alternative: iOS runs those when
/// it chooses, often hours late, and each wake costs more than the trigger.
public final class NotificationService {
    public static let shared = NotificationService()

    /// How far ahead of the calculated leave-by time we nudge.
    public static let leadMinutes = 10

    /// How long after a stop's end time an unfinished one earns a check-in.
    /// Long enough that someone who marks things done on the drive home is
    /// never nagged; short enough that the day is still fresh.
    public static let overdueGraceMinutes = 120

    /// What the check-in's snooze buys.
    public static let overdueSnoozeMinutes = 60

    public static let overdueCategory = "helipad.overdue"
    public static let doneAction = "helipad.action.done"
    public static let snoozeAction = "helipad.action.snooze"
    public static let eventIdKey = "eventId"

    /// iOS keeps at most 64 pending local notifications per app; stay well under
    /// so we never silently lose the near-term ones to a far-future stop.
    private static let maxScheduled = 48

    private static let identifierPrefix = "helipad."

    /// Live drive times are only worth asking Apple Maps for again when the trip
    /// is close enough that where the phone is now says something about where
    /// it starts. A trip days away keeps one answer for hours.
    private static let liveTravelHorizon: TimeInterval = 12 * 3600
    private static let nearTravelTTL: TimeInterval = 20 * 60
    private static let farTravelTTL: TimeInterval = 6 * 3600

    private enum ReminderKind: String, Equatable {
        case leave = "leave."
        case driverNeeded = "driver-needed."
        case overdue = "overdue."
    }

    private struct ReminderCandidate {
        var fireDate: Date
        var record: TaskRecord
        var kind: ReminderKind
    }

    private struct TravelEntry {
        var minutes: Int
        var expires: Date
    }

    private let center = UNUserNotificationCenter.current()
    private var pendingWork: Task<Void, Never>?
    /// Every save reschedules, and each reschedule used to ask Apple Maps about
    /// every upcoming stop in the household — dozens of requests per edit, and
    /// again on each 50 m location fix while driving.
    private var travelCache: [String: TravelEntry] = [:]

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

    /// The check-in's two buttons. Neither opens the app: finishing a stop from
    /// the lock screen is the point, so both are handled in the background.
    public func registerCategories() {
        let done = UNNotificationAction(identifier: Self.doneAction, title: "Mark done", options: [])
        let snooze = UNNotificationAction(identifier: Self.snoozeAction, title: "Remind me in an hour", options: [])
        let overdue = UNNotificationCategory(
            identifier: Self.overdueCategory,
            actions: [done, snooze],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([overdue])
    }

    // MARK: - Scheduling

    /// Coalesces bursts of saves into one reschedule. Typing in a settings field
    /// should not rewrite the whole notification queue on every keystroke.
    @discardableResult
    public func scheduleReminders(
        records: [TaskRecord],
        timeZoneId: String,
        enabled: Bool,
        driverNeededEnabled: Bool = false,
        overdueEnabled: Bool = false,
        owners: Set<String>? = nil,
        overdueSnoozes: [String: Date] = [:],
        bufferMinutes: Int = 0,
        travelTimeProvider: ((TaskRecord, Date) async -> Int?)? = nil,
        onError: ((String?) -> Void)? = nil,
        debounce: Bool = true
    ) -> Task<Void, Never> {
        pendingWork?.cancel()
        let work = Task { @MainActor [weak self] in
            if debounce {
                try? await Task.sleep(nanoseconds: 400_000_000)
                if Task.isCancelled { return }
            }
            await self?.applySchedule(
                records: records,
                timeZoneId: timeZoneId,
                enabled: enabled,
                driverNeededEnabled: driverNeededEnabled,
                overdueEnabled: overdueEnabled,
                owners: owners,
                overdueSnoozes: overdueSnoozes,
                bufferMinutes: bufferMinutes,
                travelTimeProvider: travelTimeProvider,
                onError: onError
            )
        }
        pendingWork = work
        return work
    }

    /// Resolves once the reschedule in flight, if any, has reached the system.
    /// A notification action handled in the background waits for this before
    /// telling iOS it is finished, or the app can be suspended with the old
    /// check-in still queued.
    public func waitForPendingWork() async {
        await pendingWork?.value
    }

    /// Replaces every reminder this app owns with a fresh set. Other pending
    /// notifications are left alone — we only ever remove our own prefix.
    ///
    /// The new set is worked out before the old one is removed. Removing first
    /// meant a reschedule cancelled part-way — by a newer save, or a location
    /// fix — left the phone with no reminders until the next one finished, and
    /// a leave reminder due in that gap never fired.
    @MainActor
    private func applySchedule(
        records: [TaskRecord],
        timeZoneId: String,
        enabled: Bool,
        driverNeededEnabled: Bool,
        overdueEnabled: Bool,
        owners: Set<String>?,
        overdueSnoozes: [String: Date],
        bufferMinutes: Int,
        travelTimeProvider: ((TaskRecord, Date) async -> Int?)?,
        onError: ((String?) -> Void)?
    ) async {
        let anyEnabled = enabled || driverNeededEnabled || overdueEnabled
        let authorized = anyEnabled ? await isAuthorized() : false

        var calendar = Calendar(identifier: .gregorian)
        if timeZoneId != "device", let tz = TimeZone(identifier: timeZoneId) {
            calendar.timeZone = tz
        }

        let now = Date()
        var candidates: [ReminderCandidate] = []
        if anyEnabled && authorized {
            let open = records
                .filter { !$0.done && !$0.allDay }
                .compactMap { record -> (Date, TaskRecord)? in
                    guard let start = Self.startDate(for: record, calendar: calendar) else { return nil }
                    return (start, record)
                }
                .sorted { $0.0 < $1.0 }

            var leaveLookups = 0
            for (startDate, record) in open {
                guard !Task.isCancelled else { return }
                // Leave reminders and check-ins are for the person doing the
                // stop. Every phone used to buzz for every caregiver's stops,
                // so Dad was told to leave for Mom's pickup.
                let ownedHere = owners.map { $0.contains(record.owner) } ?? true

                // Stops past the notification cap are never shown, so they are
                // not worth a Maps lookup either.
                if enabled, ownedHere, startDate > now, leaveLookups < Self.maxScheduled {
                    let needsTravel = PlanCore.needsTravel(record)
                    var travelMinutes = 0
                    if needsTravel, let travelTimeProvider {
                        travelMinutes = await travel(for: record, startDate: startDate, now: now, provider: travelTimeProvider)
                        leaveLookups += 1
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

                // Not scoped by owner: an unassigned stop belongs to nobody
                // yet, and every caregiver is a candidate to take it.
                if driverNeededEnabled,
                   startDate > now,
                   PlanCore.unassigned(record),
                   let fireDate = Self.driverNeededDate(for: record, calendar: calendar),
                   fireDate > now {
                    candidates.append(ReminderCandidate(fireDate: fireDate, record: record, kind: .driverNeeded))
                }

                if overdueEnabled,
                   ownedHere,
                   let fireDate = Self.overdueDate(for: record, calendar: calendar, snoozedUntil: overdueSnoozes[record.id]),
                   fireDate > now {
                    candidates.append(ReminderCandidate(fireDate: fireDate, record: record, kind: .overdue))
                }
            }
        }
        guard !Task.isCancelled else { return }

        let existing = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(Self.identifierPrefix) }
        guard !Task.isCancelled else { return }
        if !existing.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: existing)
        }
        // A check-in still on the lock screen for a stop someone has since
        // finished is noise, and its Mark done would do nothing.
        let finished = records.filter(\.done).map { Self.identifier(.overdue, $0.id) }
        if !finished.isEmpty {
            center.removeDeliveredNotifications(withIdentifiers: finished)
        }

        guard anyEnabled else {
            onError?(nil)
            return
        }
        guard authorized else {
            onError?("Notifications are not authorized for HeliPad. Enable them in iOS Settings.")
            return
        }

        var schedulingErrors: [String] = []
        for candidate in candidates.sorted(by: { $0.fireDate < $1.fireDate }).prefix(Self.maxScheduled) {
            let content = UNMutableNotificationContent()
            switch candidate.kind {
            case .leave:
                content.title = "Leave in \(Self.leadMinutes) minutes"
                content.body = Self.body(for: candidate.record, calendar: calendar)
            case .driverNeeded:
                content.title = "Driver needed in 12 hours"
                content.body = Self.driverNeededBody(for: candidate.record)
            case .overdue:
                content.title = Self.overdueTitle(for: candidate.record)
                content.body = Self.overdueBody(for: candidate.record)
                content.categoryIdentifier = Self.overdueCategory
                content.threadIdentifier = Self.overdueCategory
            }
            content.userInfo = [Self.eventIdKey: candidate.record.id]
            content.sound = .default

            var parts = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: candidate.fireDate
            )
            parts.timeZone = calendar.timeZone
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            let request = UNNotificationRequest(
                identifier: Self.identifier(candidate.kind, candidate.record.id),
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
        onError?(errorMessage)
    }

    /// Drive minutes for one stop, reusing a recent answer for the same stop.
    @MainActor
    private func travel(
        for record: TaskRecord,
        startDate: Date,
        now: Date,
        provider: (TaskRecord, Date) async -> Int?
    ) async -> Int {
        let near = startDate.timeIntervalSince(now) <= Self.liveTravelHorizon
        // Anything that changes the trip changes the key, so an edited stop
        // never reuses the old answer.
        let key = [
            record.id, record.date, record.time, record.location,
            record.latitude.map { String($0) } ?? "", record.longitude.map { String($0) } ?? "",
            near ? "near" : "far"
        ].joined(separator: "|")
        if let hit = travelCache[key], hit.expires > now { return hit.minutes }
        let minutes = max(0, await provider(record, startDate) ?? 0)
        travelCache = travelCache.filter { $0.value.expires > now }
        travelCache[key] = TravelEntry(
            minutes: minutes,
            expires: now.addingTimeInterval(near ? Self.nearTravelTTL : Self.farTravelTTL)
        )
        return minutes
    }

    public func cancelAll() async {
        let mine = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(Self.identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: mine)
    }

    // MARK: - Helpers

    private static func identifier(_ kind: ReminderKind, _ recordId: String) -> String {
        identifierPrefix + kind.rawValue + recordId
    }

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

    /// When the stop is expected to be over. An end at or before the start
    /// wraps past midnight, matching `PlanCore.end`.
    static func endDate(for record: TaskRecord, calendar: Calendar) -> Date? {
        guard let start = startDate(for: record, calendar: calendar) else { return nil }
        let duration = PlanCore.end(record) - PlanCore.mins(record.time)
        return calendar.date(byAdding: .minute, value: duration, to: start)
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

    /// The grace period after the stop's end, or the snooze if that is later.
    /// A snooze that ran out before the grace did is simply ignored.
    static func overdueDate(for record: TaskRecord, calendar: Calendar, snoozedUntil: Date? = nil) -> Date? {
        guard let end = endDate(for: record, calendar: calendar) else { return nil }
        let due = end.addingTimeInterval(Double(overdueGraceMinutes) * 60)
        guard let snoozedUntil else { return due }
        return max(due, snoozedUntil)
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

    static func overdueTitle(for record: TaskRecord) -> String {
        "Still open: \(record.title.isEmpty ? "a stop" : record.title)"
    }

    static func overdueBody(for record: TaskRecord) -> String {
        "It was due to wrap up at \(TimeFormat.formatTime(record.endTime)). Mark it done, or hold the question for an hour."
    }
}

/// Answers what the user did with a notification.
///
/// Set as the notification center's delegate at launch, before any response
/// can arrive: iOS delivers an action taken from the lock screen to whichever
/// delegate is in place when the app wakes, and drops it if there is none.
public final class NotificationResponder: NSObject, UNUserNotificationCenterDelegate {
    public static let shared = NotificationResponder()

    public enum Action: Equatable {
        case markDone(eventId: String)
        case snooze(eventId: String)
        case open(eventId: String?)
    }

    /// Does the work for an action and returns once it has been saved. Set by
    /// the app once the store exists.
    public var handler: ((Action) async -> Void)?

    /// Without this, a reminder that comes due while HeliPad is open is
    /// swallowed — the moment someone is looking at the app is exactly when
    /// a leave reminder must not be lost.
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let eventId = response.notification.request.content.userInfo[NotificationService.eventIdKey] as? String
        let action: Action
        switch (response.actionIdentifier, eventId) {
        case (NotificationService.doneAction, let id?): action = .markDone(eventId: id)
        case (NotificationService.snoozeAction, let id?): action = .snooze(eventId: id)
        default: action = .open(eventId: eventId)
        }
        guard let handler else {
            completionHandler()
            return
        }
        Task { @MainActor in
            await handler(action)
            completionHandler()
        }
    }
}

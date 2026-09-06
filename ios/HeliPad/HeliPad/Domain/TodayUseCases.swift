import Foundation

enum TodayUseCases {
    /// Hottest Task for the active viewer (any kind present in chrome).
    static func hottestTask(in agenda: DayAgenda, now: Date = .now) -> TaskItem? {
        let open = agenda.tasks.filter { !$0.isDone }
        return open.min { a, b in
            urgencyScore(a, now: now) < urgencyScore(b, now: now)
        }
    }

    static func tripPlan(for task: TaskItem, now: Date = .now) -> TripPlan? {
        guard task.travel != nil else { return nil }
        let travelMinutes = 18 // stub TravelEstimator
        let arriveBy = task.start
        let departBy = arriveBy.addingTimeInterval(TimeInterval(-travelMinutes * 60 - task.bufferMinutes * 60))
        let leaveIn = Int(departBy.timeIntervalSince(now) / 60)
        let tone: UrgencyTone
        switch leaveIn {
        case ...0: tone = .late
        case 1...8: tone = .now
        case 9...20: tone = .soon
        default: tone = .later
        }
        return TripPlan(
            departBy: departBy,
            travelMinutes: travelMinutes,
            arriveBy: arriveBy,
            tone: tone,
            leaveInMinutes: max(leaveIn, 0)
        )
    }

    /// Persist a chosen leave-by by shifting Task.start so derived TripPlan matches.
    static func applying(leaveBy: Date, to task: TaskItem) -> TaskItem {
        var updated = task
        let travelMinutes = task.travel == nil ? 0 : 18
        updated.start = leaveBy.addingTimeInterval(TimeInterval((travelMinutes + task.bufferMinutes) * 60))
        return updated
    }

    /// Rest-of-day groups preserve dual-kid separation (no merge).
    static func restGroups(in agenda: DayAgenda, excluding heroId: String?) -> [(String, [TaskItem])] {
        let order = ["go", "dinner", "home"]
        let rest = agenda.tasks.filter { $0.id != heroId && !$0.isDone }
        return order.compactMap { g in
            let rows = rest.filter { $0.group == g }.sorted { $0.start < $1.start }
            return rows.isEmpty ? nil : (g, rows)
        }
    }

    /// Tell-the-crew when driver swap or leave-by Δ ≥ 10.
    static func requiresTellTheCrew(driverChanged: Bool, leaveByDeltaMinutes: Int) -> Bool {
        driverChanged || abs(leaveByDeltaMinutes) >= 10
    }

    /// Dual-kid overlap ±45 min — different children, cards stay separate.
    static func dualKidOverlap(for task: TaskItem, in agenda: DayAgenda, windowMinutes: Int = 45) -> TaskItem? {
        let kids = Set(task.children)
        guard !kids.isEmpty else { return nil }
        let window = TimeInterval(windowMinutes * 60)
        return agenda.tasks.first { other in
            guard other.id != task.id, !other.isDone else { return false }
            let otherKids = Set(other.children)
            guard !otherKids.isEmpty, kids.isDisjoint(with: otherKids) else { return false }
            return abs(other.start.timeIntervalSince(task.start)) <= window
        }
    }

    private static func urgencyScore(_ task: TaskItem, now: Date) -> TimeInterval {
        if let plan = tripPlan(for: task, now: now) {
            return plan.departBy.timeIntervalSince(now)
        }
        return task.start.timeIntervalSince(now)
    }
}

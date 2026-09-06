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
        guard let travel = task.travel else { return nil }
        _ = travel
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

    private static func urgencyScore(_ task: TaskItem, now: Date) -> TimeInterval {
        if let plan = tripPlan(for: task, now: now) {
            return plan.departBy.timeIntervalSince(now)
        }
        return task.start.timeIntervalSince(now)
    }
}

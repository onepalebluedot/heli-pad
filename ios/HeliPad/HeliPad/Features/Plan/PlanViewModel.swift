import SwiftUI
import Combine

public struct RoutineGroup: Identifiable {
    public var key: String
    public var title: String
    public var location: String
    public var kids: [String]
    public var events: [TaskRecord]

    public var id: String { key }

    public var owner: String {
        let owners = Array(Set(events.map { $0.owner }))
        return owners.count == 1 ? (owners.first ?? "Mixed") : "Mixed"
    }
}

public enum ReviewFilterMode: String, CaseIterable, Identifiable {
    case all = "All"
    case unassigned = "Unassigned"
    case review = "To Review"

    public var id: String { rawValue }
}

public class PlanViewModel: ObservableObject {
    @Published public var currentWeek: String = PlanCore.currentMonday()
    @Published public var selectedDay: String = PlanCore.currentDeviceDate()
    @Published public var scheduleOpen: Bool = false
    @Published public var caregiverFilter: String = "all"

    // Active sheets
    @Published public var showReviewSheet: Bool = false
    @Published public var reviewFilter: ReviewFilterMode = .all
    @Published public var showRoutinesSheet: Bool = false
    @Published public var showAssignSheet: Bool = false
    @Published public var showRebalanceSheet: Bool = false
    @Published public var showPrioritiesSheet: Bool = false
    @Published public var showCalendarSheet: Bool = false
    @Published public var showEventSheet: Bool = false

    @Published public var activeEventForAssign: TaskRecord? = nil
    @Published public var activeRoutineForAssign: RoutineGroup? = nil

    public init() {
        self.currentWeek = PlanCore.currentMonday()
        self.selectedDay = PlanCore.currentDeviceDate()
    }

    public func weekRecords(store: AppStore) -> [TaskRecord] {
        let endWeek = PlanCore.dateAdd(currentWeek, 6)
        return store.records().filter { $0.date >= currentWeek && $0.date <= endWeek }
    }

    public func routineGroups(store: AppStore) -> [RoutineGroup] {
        var groups: [String: RoutineGroup] = [:]
        for e in weekRecords(store: store) {
            let key = e.seriesId ?? "\(e.title.lowercased())|\(e.location.lowercased())|\(e.kids.sorted().joined(separator: ",").lowercased())"
            if groups[key] == nil {
                groups[key] = RoutineGroup(key: key, title: e.title, location: e.location, kids: e.kids, events: [e])
            } else {
                groups[key]?.events.append(e)
            }
        }
        return groups.values.filter { $0.events.count > 1 }.sorted {
            if $0.events.count != $1.events.count {
                return $0.events.count > $1.events.count
            }
            return $0.title.localizedCompare($1.title) == .orderedAscending
        }
    }

    public func changeWeek(delta: Int) {
        currentWeek = PlanCore.dateAdd(currentWeek, delta * 7)
        selectedDay = currentWeek
        scheduleOpen = false
    }

    public func setCaregiverForRoutine(routine: RoutineGroup, caregiver: String, store: AppStore) {
        let eventIds = Set(routine.events.map { $0.id })
        var all = store.records()
        for i in all.indices where eventIds.contains(all[i].id) {
            all[i].owner = caregiver
            all[i].lead = caregiver
            all[i].tentative = false
        }
        store.replaceRecords(all)
    }

    public func summary(store: AppStore) -> SummaryResult {
        let evs = weekRecords(store: store)
        let baseSummary = PlanCore.summary(evs, store.planningOptions())

        let adjustedList = baseSummary.list.map { analyzed -> AnalyzedEvent in
            if analyzed.status == "review" && store.isReviewDismissed(eventId: analyzed.id) {
                return AnalyzedEvent(
                    event: analyzed.event,
                    detail: analyzed.detail,
                    risks: analyzed.risks,
                    status: "ready"
                )
            }
            return analyzed
        }

        let missingCount = adjustedList.filter { $0.status == "missing" }.count
        let reviewCount = adjustedList.filter { $0.status == "review" }.count
        let readyCount = adjustedList.filter { $0.status == "ready" }.count

        return SummaryResult(
            list: adjustedList,
            total: baseSummary.total,
            ready: readyCount,
            missing: missingCount,
            review: reviewCount
        )
    }

    public func decisionQueue(store: AppStore) -> [AnalyzedEvent] {
        let summ = summary(store: store)
        return summ.list.filter { $0.status != "ready" }
    }

    /// How busy a day is, and whether anything on it needs attention.
    public struct DayLoad {
        public var count: Int
        public var hasConflict: Bool
        public var hasMissing: Bool

        public init(count: Int = 0, hasConflict: Bool = false, hasMissing: Bool = false) {
            self.count = count
            self.hasConflict = hasConflict
            self.hasMissing = hasMissing
        }
    }

    /// One `records()` and one `analyze` pass for the whole week, keyed by date,
    /// so the seven day pills read from this instead of each rebuilding the week.
    public func dayLoads(store: AppStore) -> [String: DayLoad] {
        let analyzed = PlanCore.analyze(weekRecords(store: store), store.planningOptions())
        var loads: [String: DayLoad] = [:]
        for item in analyzed {
            var load = loads[item.event.date] ?? DayLoad()
            load.count += 1
            if item.status == "missing" {
                load.hasMissing = true
            } else if !store.isReviewDismissed(eventId: item.id) {
                let clashes = item.risks.contains { $0.type == "overlap" || $0.type == "tight" }
                if clashes { load.hasConflict = true }
            }
            loads[item.event.date] = load
        }
        return loads
    }

    public func daysOfWeek() -> [String] {
        (0..<7).map { PlanCore.dateAdd(currentWeek, $0) }
    }

    public func dayStatus(date: String, store: AppStore) -> String {
        let dayEvs = store.records().filter { $0.date == date }
        let summ = PlanCore.summary(dayEvs, store.planningOptions())
        if summ.missing > 0 { return "missing" }
        let activeReviews = summ.list.filter { $0.status == "review" && !store.isReviewDismissed(eventId: $0.id) }
        if !activeReviews.isEmpty { return "review" }
        return "ready"
    }

    public func formatDayName(_ dStr: String) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone = TimeZone(secondsFromGMT: 0)
        guard let d = df.date(from: dStr) else { return "" }
        let out = DateFormatter()
        out.dateFormat = "EEE"
        out.timeZone = TimeZone(secondsFromGMT: 0)
        return out.string(from: d).uppercased()
    }

    public func formatDayNum(_ dStr: String) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone = TimeZone(secondsFromGMT: 0)
        guard let d = df.date(from: dStr) else { return "" }
        let out = DateFormatter()
        out.dateFormat = "d"
        out.timeZone = TimeZone(secondsFromGMT: 0)
        return out.string(from: d)
    }

    public func formatFullDayHeader(_ dStr: String) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone = TimeZone(secondsFromGMT: 0)
        guard let d = df.date(from: dStr) else { return dStr }
        let out = DateFormatter()
        out.dateFormat = "EEEE, MMM d"
        out.timeZone = TimeZone(secondsFromGMT: 0)
        return out.string(from: d)
    }

    public func formatWeekRange() -> String {
        let end = PlanCore.dateAdd(currentWeek, 6)
        return "\(formatShortDate(currentWeek)) – \(formatShortDate(end))"
    }

    private func formatShortDate(_ dStr: String) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone = TimeZone(secondsFromGMT: 0)
        guard let d = df.date(from: dStr) else { return dStr }
        let out = DateFormatter()
        out.dateFormat = "MMM d"
        out.timeZone = TimeZone(secondsFromGMT: 0)
        return out.string(from: d)
    }
}


import SwiftUI
import Combine

public struct GoViewData {
    public var todayIdx: Int
    public var listIdx: Int
    public var listIsToday: Bool
    public var now: Int
    public var plan: [AnalyzedEvent]
    public var drivers: [String: DriverLoad]
    public var mine: [AnalyzedEvent]
    public var listed: [AnalyzedEvent]
    public var hidden: Int
    public var live: Int
    public var looseEnds: Int
    public var restingState: GoRestingState
}

public struct DriverLoad: Hashable {
    public var assignedStops: Int = 0
    public var knownRoutes: Int = 0
    public var unknownRoutes: Int = 0
    public var minutes: Int = 0
}

public enum GoRestingState: Hashable {
    case empty
    case complete
    case outstanding(Int)
}

public class GoViewModel: ObservableObject {
    /// Seeded from the device clock in `init`; `mockTime` overrides it only when
    /// something deliberately sets one for a demo or a test.
    @Published public var nowMinutes: Int = 0
    @Published public var selectedStopForEdit: TaskRecord? = nil
    @Published public var showAddEditSheet: Bool = false

    private let store: AppStore
    private var clockTask: Task<Void, Never>?

    private struct AnalysisKey: Equatable {
        var events: [TaskRecord]
        var crew: [String]
        var home: String
        var origins: [String: String]
        var buffer: Int
        var priorities: [String: WeekPriority]
        var dinnerProtection: Bool
        var trafficMode: Bool
        var routes: [String: [String: Int]]
        var locations: [LocationItem]
    }
    private var analysisCache: [Int: (key: AnalysisKey, events: [AnalyzedEvent], loads: [String: DriverLoad])] = [:]
    // Internal diagnostic used by regression tests to detect unwanted recomputation.
    private(set) var analysisPassCount = 0

    public init(store: AppStore) {
        self.store = store
        self.nowMinutes = store.mockTime.isEmpty ? store.clock(now: store.currentDate).minutes : PlanCore.mins(store.mockTime)
    }

    deinit { clockTask?.cancel() }

    public func updateClock() {
        store.syncWithDeviceDate()
        let minute = store.mockTime.isEmpty ? store.clock(now: store.currentDate).minutes : PlanCore.mins(store.mockTime)
        if nowMinutes != minute { nowMinutes = minute }
    }

    @MainActor
    public func startClock() {
        stopClock()
        updateClock()
        clockTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                // Wake at the next wall-clock minute, not twelve times per minute.
                let delay = 60 - Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 60)
                do { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
                catch { return }
                guard !Task.isCancelled else { return }
                self?.updateClock()
            }
        }
    }

    public func stopClock() {
        clockTask?.cancel()
        clockTask = nil
    }

    private func analysis(day: Int, store: AppStore, options: PlanningOptions) -> (events: [AnalyzedEvent], loads: [String: DriverLoad]) {
        let events = store.eventsByDay[day] ?? []
        let key = AnalysisKey(events: events, crew: options.crew, home: options.home,
                              origins: options.origins, buffer: options.buffer, priorities: options.priorities,
                              dinnerProtection: options.dinnerProtection, trafficMode: store.trafficMode,
                              routes: store.routes, locations: store.locations)
        if let cached = analysisCache[day], cached.key == key { return (cached.events, cached.loads) }
        let analyzed = PlanCore.analyze(events, options)
        var loads = Dictionary(uniqueKeysWithValues: options.crew.map { ($0, DriverLoad()) })
        for item in analyzed where loads[item.event.owner] != nil && PlanCore.needsTravel(item.event) {
            loads[item.event.owner]!.assignedStops += 1
            if let eta = item.detail.eta {
                loads[item.event.owner]!.knownRoutes += 1
                loads[item.event.owner]!.minutes += eta
            } else {
                loads[item.event.owner]!.unknownRoutes += 1
            }
        }
        analysisPassCount += 1
        analysisCache[day] = (key, analyzed, loads)
        return (analyzed, loads)
    }

    public func computeView(store: AppStore) -> GoViewData {
        let todayIdx = store.todayIndex
        let listIdx = store.activeDay
        let listIsToday = (listIdx == todayIdx)
        let now = nowMinutes

        let options = store.planningOptions()

        let todayAnalysis = analysis(day: todayIdx, store: store, options: options)
        let listAnalysis = listIsToday ? todayAnalysis : analysis(day: listIdx, store: store, options: options)
        let todayAnalyzed = todayAnalysis.events
        let listAnalyzed = listAnalysis.events

        // Scope filter for hero dial and resting-state truthfulness.
        let currentUser = store.currentUser
        let scopedToday = todayAnalyzed.filter { analyzed in
            if currentUser == "All" { return true }
            return analyzed.event.owner == currentUser || analyzed.event.owner == "Family" || analyzed.event.owner == "TBD"
        }
        let mine = scopedToday.filter { !$0.event.allDay }

        // Scope filter for timeline rail: chosen day, chosen crew, chosen kid
        let who = store.goCrewFilter ?? currentUser
        let kidFilter = store.goKidFilter
        let listed = listAnalyzed.filter { analyzed in
            let e = analyzed.event
            // Caregiver filter
            if who != "All" && who != "all" {
                if e.owner != who && e.owner != "Family" { return false }
            }
            // Kid filter
            if kidFilter != "all" && kidFilter != "All" {
                if !e.kids.contains(kidFilter) && !e.kids.contains("All") { return false }
            }
            return true
        }
        let hidden = listAnalyzed.count - listed.count

        // Unfinished work remains actionable even after its start or end time.
        let liveIndex = mine.firstIndex { analyzed in
            !analyzed.event.done
        } ?? -1

        let looseEnds = mine.filter { analyzed in
            !analyzed.event.done && now >= PlanCore.end(analyzed.event)
        }.count

        let unfinishedCount = scopedToday.filter { !$0.event.done }.count
        let restingState: GoRestingState
        if scopedToday.isEmpty { restingState = .empty }
        else if unfinishedCount == 0 { restingState = .complete }
        else { restingState = .outstanding(unfinishedCount) }

        let drivers = listAnalysis.loads

        return GoViewData(
            todayIdx: todayIdx,
            listIdx: listIdx,
            listIsToday: listIsToday,
            now: now,
            plan: listAnalyzed,
            drivers: drivers,
            mine: mine,
            listed: listed,
            hidden: hidden,
            live: liveIndex,
            looseEnds: looseEnds,
            restingState: restingState
        )
    }

    public func dialState(event: TaskRecord?, now: Int, options: PlanningOptions, liveDriveTime: Int? = nil, isDeviceLocationLive: Bool = false) -> (tone: UrgencyTone, fraction: Double, centerTitle: String, centerUnit: String, isWord: Bool, isHours: Bool) {
        guard let e = event else {
            return (.clear, 1.0, "DONE", "all clear", true, false)
        }

        if e.done {
            return (.clear, 1.0, "DONE", "done", true, false)
        }

        let start = PlanCore.mins(e.time)
        let cand = PlanCore.candidate(e, e.owner, [], options)
        let effectiveEta: Int? = liveDriveTime ?? (isDeviceLocationLive ? nil : cand.eta)
        let hasTravelRequired: Bool = {
            if let live = liveDriveTime {
                return live > 0
            }
            return PlanCore.needsTravel(e)
        }()
        let noTravel = !hasTravelRequired
        let depart: Int
        if effectiveEta == nil || e.allDay || noTravel {
            depart = start
        } else {
            depart = start - (effectiveEta! + options.buffer)
        }

        let target = noTravel ? start : depart
        let minsUntil = target - now

        let tone: UrgencyTone
        if now >= start {
            tone = .started
        } else if minsUntil <= 0 {
            tone = .now
        } else if minsUntil <= 15 {
            tone = .soon
        } else {
            tone = .ontrack
        }

        let fraction = TimeFormat.countdownFraction(minutesUntil: minsUntil)

        if cand.unknown {
            return (tone, fraction, "CHECK", "route needed", true, false)
        }
        if tone == .now {
            return (tone, fraction, "NOW", noTravel ? "be there" : "leave", true, false)
        }
        if tone == .started {
            let late = max(0, now - start)
            let lateStr = late >= 60 ? "\(late / 60)h \(late % 60)m" : "\(late)m"
            return (tone, fraction, "LATE", "\(lateStr) ago", true, false)
        }

        if minsUntil <= 60 {
            return (tone, fraction, "\(max(0, minsUntil))", noTravel ? "min · be there" : "min · to leave", false, false)
        } else {
            let h = minsUntil / 60
            let m = minsUntil % 60
            let str = m > 0 ? "\(h)h \(m)m" : "\(h)h"
            return (tone, fraction, str, noTravel ? "be there" : "to leave", false, true)
        }
    }
}

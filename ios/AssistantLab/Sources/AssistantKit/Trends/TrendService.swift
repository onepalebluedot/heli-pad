import Foundation

/// Deterministic schedule aggregates over an explicit period and the
/// equal-length period before it.
///
/// Three rules the plan calls out, enforced here rather than in a prompt:
/// future-dated rows never contribute to a historical claim; a metric with no
/// usable baseline says so instead of producing a percentage; and recorded
/// completion is described as recorded state, never as attendance or
/// punctuality — the records carry no timestamps that could support that.
public enum TrendService {
    public static func report(
        events: [AssistantEvent],
        range: DateRange,
        people: [AssistantPerson],
        today: String
    ) -> TrendCard {
        let previous = range.previousEqualLength

        // Historical metrics stop at today. If the requested window runs past
        // it, the elapsed part is what gets compared, and the card says so.
        let elapsedEnd = min(range.end, today)
        let elapsed = DateRange(start: range.start, end: elapsedEnd)
        let partialNote: String? = {
            guard range.end > today else { return nil }
            guard let elapsed else {
                return "This period has not started yet, so there is nothing recorded to compare. Counts below are scheduled, not history."
            }
            return "\(range.label) is still running. Recorded comparisons cover \(elapsed.label); anything after today is scheduled, not history."
        }()

        let currentAll = events.filter { range.contains($0.date) }
        let currentElapsed = elapsed.map { r in events.filter { r.contains($0.date) } } ?? []
        let previousEvents = events.filter { previous.contains($0.date) }

        var metrics: [TrendMetric] = []
        var notes: [String] = []

        // Scheduled volume is a forward-looking count, so it uses the whole
        // requested window on both sides.
        metrics.append(TrendMetric(
            id: "scheduled_events",
            title: "Scheduled events",
            currentValue: currentAll.count,
            previousValue: previousEvents.count,
            unit: currentAll.count == 1 ? "event" : "events",
            change: change(current: currentAll.count, previous: previousEvents.count, hasBaseline: !previousEvents.isEmpty || previous.end <= today)
        ))

        let currentUnassigned = currentAll.filter(\.isUnassigned).count
        let previousUnassigned = previousEvents.filter(\.isUnassigned).count
        metrics.append(TrendMetric(
            id: "unassigned_events",
            title: "Still needs a driver",
            currentValue: currentUnassigned,
            previousValue: previousUnassigned,
            unit: currentUnassigned == 1 ? "event" : "events",
            change: change(current: currentUnassigned, previous: previousUnassigned, hasBaseline: !previousEvents.isEmpty)
        ))

        // Completion is only meaningful over days that have happened.
        let completionChange: TrendMetric.Change
        let currentDone = currentElapsed.filter(\.done).count
        let previousDone = previousEvents.filter(\.done).count
        if elapsed == nil {
            completionChange = .insufficientData("the period has not started")
        } else if currentElapsed.isEmpty {
            completionChange = .insufficientData("no events recorded in the elapsed period")
        } else if previousEvents.isEmpty {
            completionChange = .noBaseline
            notes.append("No events in \(previous.label), so there is nothing to compare the earlier period against.")
        } else {
            completionChange = change(current: currentDone, previous: previousDone, hasBaseline: true)
        }
        metrics.append(TrendMetric(
            id: "recorded_complete",
            title: "Marked complete in the app",
            currentValue: currentDone,
            previousValue: previousDone,
            unit: currentDone == 1 ? "event" : "events",
            change: completionChange
        ))
        notes.append("\u{201C}Marked complete\u{201D} is what someone ticked off in HeliPad. It is not a record of who attended or whether anyone was on time.")

        // Workload counts assignments by caregiver name, matching how the roster
        // and planner label ownership.
        let caregiverNames = Set(people.filter { $0.role == .caregiver }.map(\.name))
        var workloadCounts: [String: Int] = [:]
        for event in currentAll where !event.isUnassigned {
            guard caregiverNames.contains(event.owner) else { continue }
            workloadCounts[event.owner, default: 0] += 1
        }
        let workload = workloadCounts
            .map { TrendCard.WorkloadRow(name: $0.key, count: $0.value) }
            .sorted { $0.count == $1.count ? $0.name < $1.name : $0.count > $1.count }

        var categoryCounts: [String: Int] = [:]
        for event in currentAll { categoryCounts[event.kind.category, default: 0] += 1 }
        let mix = categoryCounts
            .map { TrendCard.CategoryRow(category: $0.key, count: $0.value) }
            .sorted { $0.count == $1.count ? $0.category < $1.category : $0.count > $1.count }

        if currentAll.isEmpty {
            notes.append("Nothing is scheduled in \(range.label).")
        }

        return TrendCard(
            periodLabel: range.label,
            comparisonLabel: "compared with \(previous.label)",
            partialPeriodNote: partialNote,
            metrics: metrics,
            workload: workload,
            categoryMix: mix,
            supportingEventIDs: currentAll.map(\.id).sorted(),
            notes: notes
        )
    }

    private static func change(current: Int, previous: Int, hasBaseline: Bool) -> TrendMetric.Change {
        guard hasBaseline else { return .noBaseline }
        let absolute = current - previous
        guard previous > 0 else { return .fromZero(absolute: absolute) }
        // Rounded to a whole percent: the inputs are counts, so more precision
        // would suggest an accuracy the data does not have.
        let percent = Int((Double(absolute) / Double(previous) * 100).rounded())
        return .percent(percent, absolute: absolute)
    }
}

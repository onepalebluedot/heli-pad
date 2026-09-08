import SwiftUI
import Combine

public enum FamilyTab: String, CaseIterable, Identifiable {
    case templates = "Templates"
    case places = "Places"
    case kids = "Kids Stats"
    case roster = "Roster"

    public var id: String { rawValue }
}

public class FamilyViewModel: ObservableObject {
    @Published public var selectedTab: FamilyTab = .templates
    @Published public var selectedKid: String = ""

    @Published public var showTemplateSheet: Bool = false
    @Published public var editingTemplate: TemplateItem? = nil

    @Published public var showLocationSheet: Bool = false
    @Published public var editingLocation: LocationItem? = nil

    public init() {}

    // Workload calculation across caregivers
    public func caregiverLoads(store: AppStore) -> [(name: String, minutes: Int, color: Color)] {
        let events = store.records()
        let loads = PlanCore.loads(events, store.planningOptions())

        return store.caregivers().map { name in
            let mins = loads[name] ?? 0
            return (name: name, minutes: mins, color: HeliColors.caregiverInk(name))
        }.sorted { $0.minutes > $1.minutes }
    }

    public func totalWorkloadMinutes(store: AppStore) -> Int {
        caregiverLoads(store: store).reduce(0) { $0 + $1.minutes }
    }

    // Template suggestions
    public func suggestions(store: AppStore) -> [TemplateItem] {
        FamilyCore.suggestions(events: store.records(), templates: store.templates).map { $0.draft }
    }

    // Kid stats
    public func statsForKid(kid: String, store: AppStore) -> KidStatsData {
        let kidEvents = store.records().filter { $0.kids.contains(kid) }
        let totalMinutes = kidEvents.reduce(0) { acc, ev in
            let dur = PlanCore.timeDiff(start: ev.time, end: ev.endTime)
            return acc + max(0, dur)
        }

        // Busiest day. Counting into a dictionary and asking for `max` leaves the
        // winner of a tie down to hash order, which is seeded per process — the
        // reason this box could not settle on a day. Walk the week in order and
        // keep the first day that beats the running best, so ties resolve to the
        // earliest day and the answer is the same every time.
        var dayCounts: [Int: Int] = [:]
        for ev in kidEvents {
            dayCounts[PlanCore.weekdayIndex(ev.date), default: 0] += 1
        }
        var busiestIndex: Int? = nil
        for day in 0...6 where (dayCounts[day] ?? 0) > 0 {
            if busiestIndex == nil || (dayCounts[day] ?? 0) > (dayCounts[busiestIndex!] ?? 0) {
                busiestIndex = day
            }
        }
        let busiestDay = busiestIndex.map { Self.weekdayNames[$0] } ?? "None"

        // Category breakdown, grouped into the household's big buckets rather
        // than the raw stop kind.
        var catCounts: [String: Int] = [:]
        for ev in kidEvents {
            catCounts[ev.kind.category, default: 0] += 1
        }
        // "Other" is a catch-all, so it makes a poor headline. Lead with a named
        // category when the child has one, and only fall back to Other.
        func leader(among pool: [String]) -> String? {
            var best: String? = nil
            for cat in pool where (catCounts[cat] ?? 0) > 0 {
                if best == nil || (catCounts[cat] ?? 0) > (catCounts[best!] ?? 0) {
                    best = cat
                }
            }
            return best
        }
        let named = TaskKind.categories.filter { $0 != "Other" }
        let topCategory = leader(among: named) ?? leader(among: ["Other"]) ?? "Activities"

        // Caregiver split
        var driverCounts: [String: Int] = [:]
        for ev in kidEvents {
            driverCounts[ev.owner, default: 0] += 1
        }

        return KidStatsData(
            totalHours: Double(totalMinutes) / 60.0,
            journeyCount: kidEvents.count,
            busiestDay: busiestDay,
            topCategory: topCategory,
            categoryMix: catCounts,
            driverSplit: driverCounts
        )
    }

    private static let weekdayNames = [
        "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"
    ]
}

public struct KidStatsData {
    public var totalHours: Double
    public var journeyCount: Int
    public var busiestDay: String
    public var topCategory: String
    public var categoryMix: [String: Int]
    public var driverSplit: [String: Int]
}

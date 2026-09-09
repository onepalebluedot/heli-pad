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

    /// Every Family panel reads the week buckets rather than `records()`, which
    /// also carries off-week history. The panels all say "weekly", so they must
    /// count a week.
    public func weekEvents(store: AppStore) -> [TaskRecord] {
        store.eventsByDay.keys.sorted().flatMap { store.eventsByDay[$0] ?? [] }
    }

    /// Driving load is counted in stops, not minutes. Minutes came from route
    /// ETAs, and `route` returns nil for any place pair the route table has not
    /// learned yet — so a household whose places are unmapped saw every
    /// caregiver sitting at zero. A count of driving stops is always available.
    public func driveCounts(store: AppStore) -> [String: Int] {
        var counts: [String: Int] = [:]
        for name in store.caregivers() { counts[name] = 0 }
        for event in weekEvents(store: store)
        where counts[event.owner] != nil && PlanCore.needsTravel(event) {
            counts[event.owner, default: 0] += 1
        }
        return counts
    }

    // Workload distribution across caregivers
    public func caregiverLoads(store: AppStore) -> [(name: String, drives: Int, color: Color)] {
        let counts = driveCounts(store: store)
        return store.caregivers()
            .map { (name: $0, drives: counts[$0] ?? 0, color: HeliColors.caregiverInk($0)) }
            // Swift's sort is not stable, so a bare comparison on the count lets
            // tied caregivers swap places between renders. Break ties on name.
            .sorted { $0.drives != $1.drives ? $0.drives > $1.drives : $0.name < $1.name }
    }

    public func totalDrives(store: AppStore) -> Int {
        caregiverLoads(store: store).reduce(0) { $0 + $1.drives }
    }

    // Template suggestions
    public func suggestions(store: AppStore) -> [TemplateItem] {
        FamilyCore.suggestions(events: store.records(), templates: store.templates).map { $0.draft }
    }

    // Kid stats
    public func statsForKid(kid: String, store: AppStore) -> KidStatsData {
        let kidEvents = weekEvents(store: store).filter { $0.kids.contains(kid) || $0.kids.contains("All") }
        // The one number in this panel that asks for a decision: stops nobody has
        // picked up yet. Counting stops that need driving instead only restated
        // the total, since almost every stop is away from home.
        let needsDriverCount = kidEvents.filter { PlanCore.unassigned($0) }.count

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
        let shortcuts = shortcutCategories(store: store)
        for ev in kidEvents {
            catCounts[category(of: ev, shortcuts: shortcuts), default: 0] += 1
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
            eventCount: kidEvents.count,
            needsDriverCount: needsDriverCount,
            busiestDay: busiestDay,
            topCategory: topCategory,
            categoryMix: catCounts,
            driverSplit: driverCounts
        )
    }

    /// Shortcut title (folded) to the category the household filed it under.
    private func shortcutCategories(store: AppStore) -> [String: String] {
        var map: [String: String] = [:]
        for template in store.templates {
            guard let cat = template.category, TaskKind.categories.contains(cat) else { continue }
            map[template.title.trimmingCharacters(in: .whitespaces).lowercased()] = cat
        }
        return map
    }

    /// A stop built from a shortcut carries the shortcut's title but not its
    /// category — `kind` only records whether someone has to drive, so every
    /// such stop reports the "Other" catch-all and the mix reads as one bar.
    /// Fall back to the shortcut it came from before settling for Other.
    private func category(of event: TaskRecord, shortcuts: [String: String]) -> String {
        let own = event.kind.category
        guard own == "Other" else { return own }
        let key = event.title.trimmingCharacters(in: .whitespaces).lowercased()
        return shortcuts[key] ?? own
    }

    private static let weekdayNames = [
        "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"
    ]
}

public struct KidStatsData {
    public var eventCount: Int
    public var needsDriverCount: Int
    public var busiestDay: String
    public var topCategory: String
    public var categoryMix: [String: Int]
    public var driverSplit: [String: Int]
}

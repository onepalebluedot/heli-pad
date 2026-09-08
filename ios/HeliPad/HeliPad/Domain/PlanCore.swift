import Foundation

public struct PlanningOptions {
    public var crew: [String]
    public var home: String
    public var origins: [String: String]
    public var buffer: Int
    public var priorities: [String: WeekPriority]
    public var dinnerProtection: Bool
    public var travel: ((String, String, Int?) -> Int?)?
    public var routes: [String: [String: Int]]
    /// Names of saved places we can actually locate (coordinates, place id, or a
    /// known route key). Used to decide whether an unknown ETA is worth a prompt.
    public var verifiedPlaces: Set<String>

    public init(
        crew: [String] = PlanCore.CREW,
        home: String = "Home",
        origins: [String: String] = [:],
        buffer: Int = 12,
        priorities: [String: WeekPriority] = [:],
        dinnerProtection: Bool = true,
        travel: ((String, String, Int?) -> Int?)? = nil,
        routes: [String: [String: Int]] = [:],
        verifiedPlaces: Set<String> = []
    ) {
        self.crew = crew
        self.home = home
        self.origins = origins
        self.buffer = buffer
        self.priorities = priorities
        self.dinnerProtection = dinnerProtection
        self.travel = travel
        self.routes = routes
        self.verifiedPlaces = verifiedPlaces
    }
}

public enum PlanCore {
    public static var BASE_WEEK: String {
        return currentMonday()
    }
    public static let CREW = ["Mom", "Dad", "Nani", "Grandma"]

    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone = TimeZone(secondsFromGMT: 0)
        return df
    }()

    public static func mins(_ t: String) -> Int {
        let parts = t.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2 else { return 0 }
        return parts[0] * 60 + parts[1]
    }

    public static func formatTime(_ m: Int) -> String {
        let normalized = ((m % 1440) + 1440) % 1440
        let h = normalized / 60
        let min = normalized % 60
        return String(format: "%02d:%02d", h, min)
    }

    public static func addMinutes(time: String, mins added: Int) -> String {
        let current = mins(time)
        return formatTime(current + added)
    }

    public static func timeDiff(start: String, end: String) -> Int {
        let s = mins(start)
        let e = mins(end)
        return e >= s ? e - s : (e + 1440) - s
    }

    public static func dateAdd(_ date: String, _ days: Int) -> String {
        guard let d = dateFormatter.date(from: date) else { return date }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        var comps = DateComponents()
        comps.day = days
        let target = cal.date(byAdding: comps, to: d) ?? d
        return dateFormatter.string(from: target)
    }

    public static func daysBetween(_ a: String, _ b: String) -> Int {
        guard let da = dateFormatter.date(from: a), let db = dateFormatter.date(from: b) else { return 0 }
        let diff = db.timeIntervalSince(da)
        return Int(round(diff / 86400.0))
    }

    public static func monday(_ date: String) -> String {
        guard let d = dateFormatter.date(from: date) else { return date }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let weekday = cal.component(.weekday, from: d) // 1=Sun, 2=Mon... 7=Sat
        let offset = -((weekday + 5) % 7) // Mon -> 0, Tue -> -1... Sun -> -6
        return dateAdd(date, offset)
    }

    public static func weekdayIndex(_ date: String) -> Int {
        guard let d = dateFormatter.date(from: date) else { return 0 }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let weekday = cal.component(.weekday, from: d) // 1=Sun, 2=Mon... 7=Sat
        return (weekday + 5) % 7 // 0=Mon, 1=Tue... 6=Sun
    }

    public static func currentDeviceDate(date: Date = Date(), timeZone: TimeZone = .current) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone = timeZone
        return df.string(from: date)
    }

    public static func currentMonday(date: Date = Date(), timeZone: TimeZone = .current) -> String {
        let dateStr = currentDeviceDate(date: date, timeZone: timeZone)
        return monday(dateStr)
    }

    public static func currentWeekdayIndex(date: Date = Date(), timeZone: TimeZone = .current) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let weekday = cal.component(.weekday, from: date)
        return (weekday + 5) % 7 // 0=Mon, 1=Tue... 6=Sun
    }

    public static func needsTravel(_ e: TaskRecord) -> Bool {
        return !e.allDay && e.mode != "Home" && e.kind != .cook && e.kind != .placeholder
    }

    public static func unassigned(_ e: TaskRecord) -> Bool {
        return e.owner.isEmpty || e.owner == "TBD" || e.owner == "Unassigned"
    }

    public static func end(_ e: TaskRecord) -> Int {
        let t = mins(e.endTime)
        return t <= mins(e.time) ? t + 1440 : t
    }

    public static func intersects(_ a: Int, _ b: Int, _ c: Int, _ d: Int) -> Bool {
        return a < d && c < b
    }

    public static func route(_ a: String, _ b: String, _ options: PlanningOptions, _ at: Int) -> Int? {
        if let travel = options.travel {
            return travel(a, b, at)
        }
        if a == b { return 0 }
        return options.routes[a]?[b]
    }

    private static func crew(_ options: PlanningOptions) -> [String] {
        return options.crew.isEmpty ? CREW : options.crew
    }

    public static func owned(_ e: TaskRecord, _ name: String) -> Bool {
        return e.owner == name || e.owner == "Family"
    }

    public static func candidate(
        _ event: TaskRecord,
        _ name: String,
        _ events: [TaskRecord],
        _ options: PlanningOptions
    ) -> CandidateDetail {
        let start = mins(event.time)
        let finish = end(event)
        let buffer = options.buffer

        let others = events.filter { $0.date == event.date && $0.id != event.id && owned($0, name) }
        var prior: TaskRecord?
        for other in others where end(other) <= start {
            if prior == nil || end(other) > end(prior!) { prior = other }
        }
        let recent = prior != nil && (start - end(prior!)) <= 180

        let origin: String
        if start < 540 {
            origin = options.home.isEmpty ? "Home" : options.home
        } else if recent {
            origin = prior!.location
        } else {
            origin = options.origins[name] ?? (options.home.isEmpty ? "Home" : options.home)
        }

        let eta: Int?
        if needsTravel(event) {
            eta = route(origin, event.location, options, start)
        } else {
            eta = 0
        }

        let leave: Int
        if let eta = eta {
            leave = start - eta - (needsTravel(event) ? buffer : 0)
        } else {
            leave = start
        }

        let overlap = others.first { intersects(leave, finish, mins($0.time), end($0)) }
        let slack: Int?
        if let prior = prior, eta != nil {
            slack = leave - end(prior)
        } else {
            slack = nil
        }

        // Check onward journey too
        var next: TaskRecord?
        for other in others where mins(other.time) >= finish {
            if next == nil || mins(other.time) < mins(next!.time) { next = other }
        }
        let nextEta: Int?
        if let next = next, needsTravel(next) {
            nextEta = route(event.location, next.location, options, mins(next.time))
        } else {
            nextEta = 0
        }

        let onwardSlack: Int?
        if let next = next, let nextEta = nextEta {
            onwardSlack = mins(next.time) - nextEta - (needsTravel(next) ? buffer : 0) - finish
        } else {
            onwardSlack = nil
        }

        let unknown = eta == nil || (next != nil && nextEta == nil)
        let conflict = overlap != nil || (slack != nil && slack! < 0) || (onwardSlack != nil && onwardSlack! < 0)

        let reason: String
        if let overlap = overlap {
            reason = "Overlaps \(overlap.title)"
        } else if let onwardSlack = onwardSlack, onwardSlack < 0 {
            reason = "\(abs(onwardSlack)) min short before \(next!.title)"
        } else if let slack = slack, slack < 0 {
            reason = "\(abs(slack)) min short after \(prior!.title)"
        } else if unknown {
            reason = "Route needs checking"
        } else if let eta = eta {
            reason = "\(eta) min \(needsTravel(event) ? "travel" : "travel needed")\(needsTravel(event) ? " from " + origin : "")"
        } else {
            reason = "Route needs checking"
        }

        return CandidateDetail(
            name: name,
            origin: origin,
            eta: eta,
            leave: leave,
            slack: slack,
            onwardSlack: onwardSlack,
            unknown: unknown,
            conflict: conflict,
            reason: reason
        )
    }

    /// A destination counts as verified when it carries its own coordinates or
    /// matches a saved household place we can locate.
    public static func placeIsVerified(_ event: TaskRecord, _ options: PlanningOptions) -> Bool {
        if event.latitude != nil && event.longitude != nil { return true }
        if event.locationMissing ?? false { return false }
        let name = event.location.trimmingCharacters(in: .whitespaces)
        if name.isEmpty { return false }
        return options.verifiedPlaces.contains(name)
    }

    public static func analyze(_ events: [TaskRecord], _ options: PlanningOptions) -> [AnalyzedEvent] {
        let days = Dictionary(grouping: events, by: \.date)
        return events.map { event in
            let missing = unassigned(event) || (event.owner != "Family" && !crew(options).contains(event.owner))
            let detail = candidate(event, missing ? (crew(options).first ?? "") : event.owner, days[event.date] ?? [], options)
            var risks: [Risk] = []

            if missing {
                risks.append(Risk(type: "driver", label: needsTravel(event) ? "Needs driver" : "Needs caregiver"))
            }
            if !missing && detail.conflict {
                risks.append(Risk(type: "overlap", label: detail.reason))
            }
            if !missing && !detail.conflict, let slack = detail.slack, slack < 10 {
                risks.append(Risk(type: "tight", label: "\(slack) min spare after travel + buffer"))
            }
            if (event.locationMissing ?? false) || event.location.trimmingCharacters(in: .whitespaces).isEmpty {
                risks.append(Risk(type: "place", label: "Choose a saved location"))
            }
            // An unknown ETA on its own is not worth a prompt: most households
            // never build a routes table, so every stop would flag. Ask only when
            // the timing is genuinely broken, or when we cannot place the
            // destination well enough to work the travel out at all.
            if detail.unknown && (detail.conflict || !placeIsVerified(event, options)) {
                risks.append(Risk(type: "route", label: "Check the route"))
            }
            if !missing, let eta = detail.eta, eta >= 25 {
                risks.append(Risk(type: "long", label: "\(eta) min drive"))
            }

            let mon = monday(event.date)
            let priority = options.priorities[mon] ?? (options.dinnerProtection ? WeekPriority(enabled: true, days: [0, 1, 2, 3, 4, 5, 6], time: "18:30") : nil)
            if options.dinnerProtection,
               let priority = priority,
               priority.enabled,
               priority.days.contains(weekdayIndex(event.date)),
               !event.allDay,
               !event.title.localizedCaseInsensitiveContains("dinner"),
               !event.title.localizedCaseInsensitiveContains("supper") {
                let dTime = mins(priority.time)
                if intersects(detail.leave, end(event), dTime, dTime + 45) {
                    risks.append(Risk(type: "dinner", label: "Crosses family dinner"))
                }
            }

            let tentative = event.tentative && !missing
            if tentative {
                risks.append(Risk(type: "tentative", label: "Driver is tentative"))
            }

            let status = missing ? "missing" : (risks.isEmpty ? "ready" : "review")
            return AnalyzedEvent(event: event, detail: detail, risks: risks, status: status)
        }
    }

    public static func summary(_ events: [TaskRecord], _ options: PlanningOptions) -> SummaryResult {
        let list = analyze(events, options)
        return SummaryResult(
            list: list,
            total: list.count,
            ready: list.filter { $0.status == "ready" }.count,
            missing: list.filter { $0.status == "missing" }.count,
            review: list.filter { $0.status == "review" }.count
        )
    }

    public static func loads(_ events: [TaskRecord], _ options: PlanningOptions) -> [String: Int] {
        var result: [String: Int] = [:]
        for n in crew(options) {
            result[n] = 0
        }
        for e in events where result[e.owner] != nil && needsTravel(e) {
            let detail = candidate(e, e.owner, events, options)
            result[e.owner, default: 0] += detail.eta ?? 0
        }
        return result
    }

    public static func proposals(_ events: [TaskRecord], _ options: PlanningOptions) -> ProposalsResult {
        var draft = events
        var changes: [RebalanceProposal] = []
        let sorted = draft.sorted {
            if $0.date != $1.date { return $0.date < $1.date }
            return $0.time < $1.time
        }

        for e in sorted {
            if e.done || e.owner == "Family" || e.tentative || e.locked || !needsTravel(e) {
                continue
            }
            let oldDetail = candidate(e, e.owner.isEmpty ? (crew(options).first ?? "") : e.owner, draft, options)
            let currentLoad = loads(draft, options)
            let pool = crew(options)
                .map { candidate(e, $0, draft, options) }
                .filter { !$0.conflict && !$0.unknown }
                .sorted {
                    let costA = Double($0.eta ?? 0) + Double(currentLoad[$0.name] ?? 0) * 0.12
                    let costB = Double($1.eta ?? 0) + Double(currentLoad[$1.name] ?? 0) * 0.12
                    return costA < costB
                }

            guard let best = pool.first, best.name != e.owner else { continue }
            let saving = (oldDetail.eta ?? 0) - (best.eta ?? 0)
            let loadDiff = (currentLoad[e.owner] ?? 0) - (currentLoad[best.name] ?? 0)
            let balancing = loadDiff >= 35 && (best.eta ?? 0) <= (oldDetail.eta ?? 0) + 3

            if !unassigned(e) && !oldDetail.conflict && saving < 5 && !balancing {
                continue
            }

            let beforeScore = summary(draft, options).list.filter { item in
                item.risks.contains { $0.type == "overlap" }
            }.count

            let trial = draft.map { item -> TaskRecord in
                if item.id == e.id {
                    var updated = item
                    updated.owner = best.name
                    updated.tentative = false
                    return updated
                }
                return item
            }

            if summary(trial, options).list.filter({ item in
                item.risks.contains { $0.type == "overlap" }
            }).count > beforeScore {
                continue
            }

            let reason: String
            if unassigned(e) {
                reason = "Covers an open handoff"
            } else if oldDetail.conflict {
                reason = "Clears a schedule overlap"
            } else if saving >= 5 {
                reason = "\(saving) min less driving"
            } else {
                reason = "Shares the driving more evenly"
            }

            changes.append(RebalanceProposal(
                id: e.id,
                date: e.date,
                title: e.title,
                time: e.time,
                from: e.owner.isEmpty ? "TBD" : e.owner,
                to: best.name,
                eta: best.eta,
                saving: saving,
                reason: reason
            ))
            draft = trial
        }

        return ProposalsResult(
            changes: changes,
            before: loads(events, options),
            after: loads(draft, options),
            events: draft
        )
    }

    public static func occurrences(
        _ draft: TaskRecord,
        repeatMode: String = "none",
        count: Int = 1,
        weekdays: [Int]? = nil
    ) throws -> [TaskRecord] {
        guard dateFormatter.date(from: draft.date) != nil else {
            throw NSError(domain: "PlanCore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Choose a date."])
        }
        guard !draft.title.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw NSError(domain: "PlanCore", code: 2, userInfo: [NSLocalizedDescriptionKey: "Give this event a name."])
        }
        let timeRegex = try! NSRegularExpression(pattern: "^([01]\\d|2[0-3]):[0-5]\\d$")
        let fullRangeT = NSRange(draft.time.startIndex..<draft.time.endIndex, in: draft.time)
        let fullRangeE = NSRange(draft.endTime.startIndex..<draft.endTime.endIndex, in: draft.endTime)
        guard timeRegex.firstMatch(in: draft.time, range: fullRangeT) != nil,
              timeRegex.firstMatch(in: draft.endTime, range: fullRangeE) != nil,
              mins(draft.endTime) > mins(draft.time) else {
            throw NSError(domain: "PlanCore", code: 3, userInfo: [NSLocalizedDescriptionKey: "End time must be after start time on the same day."])
        }

        let realCount = (repeatMode == "weekly") ? count : 1
        guard realCount >= 1 && realCount <= 52 else {
            throw NSError(domain: "PlanCore", code: 4, userInfo: [NSLocalizedDescriptionKey: "Choose 1 to 52 weeks."])
        }

        let actualWeekdays: [Int]
        if let weekdays = weekdays {
            actualWeekdays = weekdays
        } else {
            actualWeekdays = [daysBetween(monday(draft.date), draft.date)]
        }

        guard !actualWeekdays.isEmpty, actualWeekdays.allSatisfy({ $0 >= 0 && $0 <= 6 }) else {
            throw NSError(domain: "PlanCore", code: 5, userInfo: [NSLocalizedDescriptionKey: "Choose at least one weekday."])
        }

        let selectedDays = Array(Set(actualWeekdays)).sorted()
        let startMonday = monday(draft.date)
        var dates: [TaskRecord] = []

        for week in 0..<realCount {
            for day in selectedDays {
                let date = dateAdd(startMonday, week * 7 + day)
                if repeatMode != "weekly" || date >= draft.date {
                    var copy = draft
                    copy.date = date
                    dates.append(copy)
                }
            }
        }

        guard !dates.isEmpty else {
            throw NSError(domain: "PlanCore", code: 6, userInfo: [NSLocalizedDescriptionKey: "Choose a day on or after the start date, or add another week."])
        }

        return dates
    }

    public static func schedule(_ e: TaskRecord) -> [String: String] {
        return [
            "date": e.date,
            "title": e.title,
            "time": e.time,
            "endTime": e.endTime,
            "location": e.location
        ]
    }

    public static func signature(_ e: TaskRecord) -> String {
        let s = schedule(e)
        let json = try? JSONSerialization.data(withJSONObject: [s["date"], s["title"], s["time"], s["endTime"], s["location"]], options: [])
        return json.flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    public static func pull(_ records: [TaskRecord], _ incoming: [TaskRecord]) -> [TaskRecord] {
        var merged = records
        for item in incoming {
            if let idx = merged.firstIndex(where: { $0.calendarId != nil && $0.calendarId == item.calendarId }) {
                merged[idx].date = item.date
                merged[idx].title = item.title
                merged[idx].time = item.time
                merged[idx].endTime = item.endTime
                merged[idx].location = item.location
            } else {
                var brandNew = item
                brandNew.owner = "TBD"
                brandNew.done = false
                brandNew.tentative = false
                merged.append(brandNew)
            }
        }
        return merged
    }
}

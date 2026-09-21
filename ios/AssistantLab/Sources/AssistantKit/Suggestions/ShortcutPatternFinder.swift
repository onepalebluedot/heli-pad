import Foundation

/// Finds repeated hand-made events that a shortcut would save work on.
///
/// All of this is deterministic app code. The model never sees raw events and
/// never counts anything; it only ranks and names what this produces.
public enum ShortcutPatternFinder {
    /// Rolling window. Not the household's whole history: a routine that ended
    /// in spring is not worth automating today, and scanning everything gets
    /// slower forever.
    public static let lookBackDays = 120
    public static let lookAheadDays = 30

    public static let minimumOccurrences = 3
    /// Across distinct calendar weeks, so three in one busy week is not a habit.
    public static let minimumDistinctWeeks = 3
    /// The pattern has to still be live.
    public static let recencyDays = 30

    /// Start times inside this span belong to the same habit. A tolerance, not
    /// a bucket: 8:29 and 8:30 must never land in different patterns.
    public static let startToleranceMinutes = 45
    /// Durations inside this span are "about the same length".
    public static let durationToleranceMinutes = 20

    /// Most the model is ever asked to consider.
    public static let maxCandidates = 8

    public static func candidates(
        events: [AssistantEvent],
        shortcuts: [ExistingShortcut],
        today: String
    ) -> [ShortcutCandidate] {
        let windowStart = CalendarMath.addDays(today, -lookBackDays)
        let windowEnd = CalendarMath.addDays(today, lookAheadDays)
        let recencyFloor = CalendarMath.addDays(today, -recencyDays)

        let eligible = events.filter { event in
            guard event.date >= windowStart, event.date <= windowEnd else { return false }
            guard event.countsAsManualEffort else { return false }
            guard CalendarMath.minutes(event.time) != nil,
                  let duration = duration(of: event), duration > 0 else { return false }
            return true
        }

        // Identity first: what the activity is, where, and for whom. Caregiver
        // is deliberately absent - the same school run shared between two
        // parents is one habit, and the spec is explicit that a varying
        // caregiver must not split a pattern.
        var buckets: [String: [AssistantEvent]] = [:]
        for event in eligible {
            buckets[identityKey(for: event), default: []].append(event)
        }

        var found: [ShortcutCandidate] = []
        for (identity, bucket) in buckets {
            for cluster in clusters(in: bucket) {
                guard cluster.count >= minimumOccurrences else { continue }
                let weeks = Set(cluster.map { CalendarMath.monday($0.date) })
                guard weeks.count >= minimumDistinctWeeks else { continue }
                let sorted = cluster.sorted { $0.date < $1.date }
                guard let last = sorted.last?.date, last >= recencyFloor else { continue }

                let candidate = summarise(sorted, identity: identity, weeks: weeks.count)
                // Already automated? Checked per child set, so one child having
                // a shortcut at a school does not silence another child's.
                if shortcuts.contains(where: { covers($0, candidate) }) { continue }
                found.append(candidate)
            }
        }

        found.sort { a, b in
            if a.occurrences != b.occurrences { return a.occurrences > b.occurrences }
            if a.distinctWeeks != b.distinctWeeks { return a.distinctWeeks > b.distinctWeeks }
            if a.lastDate != b.lastDate { return a.lastDate > b.lastDate }
            return a.id < b.id
        }
        return Array(found.prefix(maxCandidates))
    }

    /// A fingerprint of what the detector currently sees. When this is
    /// unchanged there is nothing new to rank, so no model request is made.
    public static func fingerprint(_ candidates: [ShortcutCandidate]) -> String {
        candidates
            .map { "\($0.id):\($0.occurrences):\($0.lastDate)" }
            .sorted()
            .joined(separator: ";")
    }

    // MARK: - Identity

    /// What makes two events the same activity: the words in the title, the
    /// place, the children, and the broad category.
    static func identityKey(for event: AssistantEvent) -> String {
        [
            normalizedTitle(event.title, knownNames: event.kids),
            placeKey(event),
            childKey(event.kids),
            event.kind.category
        ].joined(separator: "|")
    }

    /// Stable place identity when the location was resolved, falling back to
    /// the normalised name when it was not.
    static func placeKey(_ event: AssistantEvent) -> String {
        if let placeID = event.placeID, !placeID.isEmpty { return "id:\(placeID)" }
        return "name:" + event.location.lowercased().trimmingCharacters(in: .whitespaces)
    }

    static func childKey(_ kids: [String]) -> String {
        Set(kids.map { $0.lowercased().trimmingCharacters(in: .whitespaces) })
            .sorted()
            .joined(separator: "+")
    }

    /// Strips what varies between otherwise identical entries: case,
    /// punctuation, filler, and the child's name, which people include
    /// inconsistently ("Soni Drop Off" and "Drop Off" are one habit).
    static func normalizedTitle(_ title: String, knownNames: [String] = []) -> String {
        var text = title.lowercased()
        for name in knownNames where !name.isEmpty {
            text = text.replacingOccurrences(of: name.lowercased(), with: " ")
        }
        let stripped = String(text.unicodeScalars.map {
            CharacterSet.alphanumerics.contains($0) ? Character($0) : " "
        })
        return stripped
            .split(separator: " ")
            .map(String.init)
            .filter { !["the", "a", "to", "for", "at", "and", "of"].contains($0) }
            .sorted()
            .joined(separator: " ")
    }

    // MARK: - Clustering

    /// Groups a bucket by start time then duration, using spans rather than
    /// fixed boundaries.
    ///
    /// Greedy over sorted values: a new cluster begins only when a value is
    /// more than the tolerance from the *first* value in the current cluster.
    /// That bounds each cluster's spread, so it cannot chain indefinitely.
    static func clusters(in events: [AssistantEvent]) -> [[AssistantEvent]] {
        let byStart = split(events, tolerance: startToleranceMinutes) {
            CalendarMath.minutes($0.time) ?? 0
        }
        return byStart.flatMap { group in
            split(group, tolerance: durationToleranceMinutes) { duration(of: $0) ?? 0 }
        }
    }

    private static func split(
        _ events: [AssistantEvent],
        tolerance: Int,
        value: (AssistantEvent) -> Int
    ) -> [[AssistantEvent]] {
        guard !events.isEmpty else { return [] }
        let sorted = events.sorted { value($0) < value($1) }
        var result: [[AssistantEvent]] = []
        var current: [AssistantEvent] = [sorted[0]]
        var anchor = value(sorted[0])
        for event in sorted.dropFirst() {
            if value(event) - anchor <= tolerance {
                current.append(event)
            } else {
                result.append(current)
                current = [event]
                anchor = value(event)
            }
        }
        result.append(current)
        return result
    }

    // MARK: - Summarising

    static func summarise(_ sorted: [AssistantEvent], identity: String, weeks: Int) -> ShortcutCandidate {
        let titles = frequency(sorted.map(\.title).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
        let starts = sorted.compactMap { CalendarMath.minutes($0.time) }
        let durations = sorted.compactMap(duration(of:))
        let owners = Set(sorted.map(\.owner).filter { $0 != "TBD" && !$0.isEmpty })

        return ShortcutCandidate(
            // Identity, not contents: new occurrences must not change the id,
            // or a dismissal would stop applying.
            id: stableID(identity),
            representativeTitle: titles.first?.0 ?? sorted[0].title,
            location: sorted[0].location,
            placeID: sorted.compactMap(\.placeID).first,
            startTime: CalendarMath.time(fromMinutes: roundToFive(median(starts))),
            durationMinutes: roundToFive(median(durations)),
            kids: sorted[0].kids,
            // Only when it is unambiguous; otherwise the editor opens with the
            // caregiver unset rather than guessing.
            owner: owners.count == 1 ? owners.first : nil,
            category: sorted[0].kind.category,
            weekdays: usualWeekdays(sorted, distinctWeeks: weeks),
            occurrences: sorted.count,
            distinctWeeks: weeks,
            firstDate: sorted.first!.date,
            lastDate: sorted.last!.date,
            titleVariants: Array(titles.prefix(4).map(\.0)),
            sourceEventIDs: sorted.map(\.id).sorted()
        )
    }

    /// Weekdays the pattern reliably lands on.
    ///
    /// A day qualifies when it shows up in at least 60% of the weeks observed.
    /// Anything less is not a weekly shape and the draft is left without days
    /// rather than inventing one.
    static func usualWeekdays(_ events: [AssistantEvent], distinctWeeks: Int) -> [Int] {
        guard distinctWeeks > 0 else { return [] }
        var weeksByWeekday: [Int: Set<String>] = [:]
        for event in events {
            guard let day = CalendarMath.weekdayIndex(event.date) else { continue }
            weeksByWeekday[day, default: []].insert(CalendarMath.monday(event.date))
        }
        let threshold = Double(distinctWeeks) * 0.6
        return weeksByWeekday
            .filter { Double($0.value.count) >= threshold }
            .keys
            .sorted()
    }

    // MARK: - Coverage

    /// Whether a saved shortcut already automates this pattern.
    ///
    /// Compared on activity, place, children, duration and time - not on exact
    /// titles, so "Drop Off" covers "Soni Drop Off". The child check is
    /// containment rather than overlap, so a shortcut for one child never
    /// suppresses a sibling's.
    static func covers(_ shortcut: ExistingShortcut, _ candidate: ShortcutCandidate) -> Bool {
        guard samePlace(shortcut, candidate) else { return false }

        let shortcutKids = Set(shortcut.kids.map { $0.lowercased() })
        let candidateKids = Set(candidate.kids.map { $0.lowercased() })
        if !candidateKids.isEmpty {
            guard candidateKids.isSubset(of: shortcutKids) else { return false }
        } else if !shortcutKids.isEmpty {
            return false
        }

        let a = Set(normalizedTitle(shortcut.title, knownNames: shortcut.kids).split(separator: " "))
        let b = Set(normalizedTitle(candidate.representativeTitle, knownNames: candidate.kids).split(separator: " "))
        guard !a.isDisjoint(with: b) || (a.isEmpty && b.isEmpty) else { return false }

        guard abs(shortcut.durationMinutes - candidate.durationMinutes) <= durationToleranceMinutes else {
            return false
        }
        // A shortcut with no time set still covers: it is the same activity at
        // the same place for the same children.
        if let shortcutStart = CalendarMath.minutes(shortcut.startTime),
           let candidateStart = CalendarMath.minutes(candidate.startTime) {
            guard abs(shortcutStart - candidateStart) <= startToleranceMinutes else { return false }
        }
        return true
    }

    private static func samePlace(_ shortcut: ExistingShortcut, _ candidate: ShortcutCandidate) -> Bool {
        if let a = shortcut.placeID, let b = candidate.placeID, !a.isEmpty, !b.isEmpty {
            return a == b
        }
        return shortcut.location.caseInsensitiveCompare(candidate.location) == .orderedSame
    }

    // MARK: - Helpers

    static func duration(of event: AssistantEvent) -> Int? {
        guard let start = CalendarMath.minutes(event.time),
              let end = CalendarMath.minutes(event.endTime) else { return nil }
        return end - start
    }

    static func median(_ values: [Int]) -> Int {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }

    static func roundToFive(_ value: Int) -> Int {
        Int((Double(value) / 5).rounded()) * 5
    }

    static func frequency(_ values: [String]) -> [(String, Int)] {
        var counts: [String: Int] = [:]
        for value in values { counts[value, default: 0] += 1 }
        return counts
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .map { ($0.key, $0.value) }
    }

    /// Short, stable, filesystem- and dictionary-safe id for an identity key.
    static func stableID(_ identity: String) -> String {
        var hash: UInt64 = 5381
        for byte in Array(identity.utf8) { hash = hash &* 33 &+ UInt64(byte) }
        return "cand-" + String(hash, radix: 36)
    }
}

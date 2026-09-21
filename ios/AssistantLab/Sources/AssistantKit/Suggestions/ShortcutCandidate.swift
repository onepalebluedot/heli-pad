import Foundation

/// An existing one-tap shortcut, so a pattern already covered by one is not
/// offered again.
public struct ExistingShortcut: Hashable, Sendable, Codable {
    public var id: String
    public var title: String
    public var location: String
    public var placeID: String?
    public var kids: [String]
    public var startTime: String
    public var durationMinutes: Int

    public init(
        id: String = "",
        title: String,
        location: String,
        placeID: String? = nil,
        kids: [String] = [],
        startTime: String = "",
        durationMinutes: Int
    ) {
        self.id = id
        self.title = title
        self.location = location
        self.placeID = placeID
        self.kids = kids
        self.startTime = startTime
        self.durationMinutes = durationMinutes
    }
}

/// A repeated pattern the app found in events the household created by hand.
///
/// Every field is computed from real records. The model's only job is to rank
/// these and name them; it cannot invent one, because the app renders only ids
/// that appear in this list.
public struct ShortcutCandidate: Hashable, Sendable, Identifiable, Codable {
    /// Stable across runs for the same behavioural pattern, so a cached
    /// suggestion and a dismissal still refer to the same thing after new
    /// occurrences arrive.
    public var id: String
    /// The most common valid title in the group.
    public var representativeTitle: String
    public var location: String
    public var placeID: String?
    /// Median start, rounded to five minutes.
    public var startTime: String
    /// Median duration, rounded to five minutes.
    public var durationMinutes: Int
    /// The child set shared by every occurrence.
    public var kids: [String]
    /// Only set when the same caregiver did all of them.
    public var owner: String?
    public var category: String
    /// Weekdays the pattern consistently lands on, 0 = Monday. Empty when the
    /// occurrences show no consistent weekly shape.
    public var weekdays: [Int]
    public var occurrences: Int
    public var distinctWeeks: Int
    public var firstDate: String
    public var lastDate: String
    /// Titles actually used, so the model can name it in the household's words.
    public var titleVariants: [String]
    /// Ids of the events behind this, so a cached suggestion can be revalidated
    /// when events are edited or deleted.
    public var sourceEventIDs: [String]
    /// True when the household already has a saved shortcut for this place.
    public var hasSimilarShortcut: Bool

    public init(
        id: String, representativeTitle: String, location: String, placeID: String? = nil,
        startTime: String, durationMinutes: Int, kids: [String] = [], owner: String? = nil,
        category: String = "", weekdays: [Int] = [], occurrences: Int, distinctWeeks: Int,
        firstDate: String, lastDate: String, titleVariants: [String] = [], sourceEventIDs: [String] = [],
        hasSimilarShortcut: Bool = false
    ) {
        self.id = id
        self.representativeTitle = representativeTitle
        self.location = location
        self.placeID = placeID
        self.startTime = startTime
        self.durationMinutes = durationMinutes
        self.kids = kids
        self.owner = owner
        self.category = category
        self.weekdays = weekdays
        self.occurrences = occurrences
        self.distinctWeeks = distinctWeeks
        self.firstDate = firstDate
        self.lastDate = lastDate
        self.titleVariants = titleVariants
        self.sourceEventIDs = sourceEventIDs
        self.hasSimilarShortcut = hasSimilarShortcut
    }

    public var endTime: String {
        CalendarMath.time(fromMinutes: (CalendarMath.minutes(startTime) ?? 0) + durationMinutes)
    }
}

/// A suggestion the app is willing to show: a candidate that survived ranking,
/// with a label that survived validation.
public struct ShortcutSuggestion: Hashable, Sendable, Identifiable, Codable {
    public var id: String { candidate.id }
    public var candidate: ShortcutCandidate
    /// The model's words when they hold up, the household's own title when
    /// they do not.
    public var label: String
    /// App-authored evidence, always shown, so a suggestion is visibly earned.
    public var evidence: String
    /// True when no model ranked this - shown from local detection alone.
    public var isLocalOnly: Bool

    public init(candidate: ShortcutCandidate, label: String, evidence: String, isLocalOnly: Bool = false) {
        self.candidate = candidate
        self.label = label
        self.evidence = evidence
        self.isLocalOnly = isLocalOnly
    }
}

import Foundation

// MARK: - Boundary value types
//
// These mirror the shapes the app already stores (`TaskRecord`, `Person`,
// `LocationItem` in `Domain/Models.swift`) but stay independent of the app
// target so this work stream compiles and is testable on its own. Integration
// is a field-for-field adapter, not a second domain: see `Integration.md`.

/// One scheduled item. Field names follow `TaskRecord` so the adapter is a
/// rename-free copy.
public struct AssistantEvent: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    /// "YYYY-MM-DD", absolute, as the app stores it.
    public var date: String
    /// "HH:mm", 24-hour.
    public var time: String
    public var endTime: String
    /// Untrusted household text. Never interpolated into model instructions.
    public var title: String
    /// Caregiver display name, or "TBD" when unassigned.
    public var owner: String
    public var kids: [String]
    public var location: String
    public var kind: EventKind
    public var done: Bool
    public var tentative: Bool
    /// Untrusted household text.
    public var notes: String
    public var seriesId: String?
    /// Optimistic-concurrency token. The app's `RecordStamp` maps onto this.
    public var revision: Int

    public init(
        id: String,
        date: String,
        time: String = "16:00",
        endTime: String = "17:00",
        title: String,
        owner: String = "TBD",
        kids: [String] = [],
        location: String = "Home",
        kind: EventKind = .other,
        done: Bool = false,
        tentative: Bool = false,
        notes: String = "",
        seriesId: String? = nil,
        revision: Int = 1
    ) {
        self.id = id
        self.date = date
        self.time = time
        self.endTime = endTime
        self.title = title
        self.owner = owner
        self.kids = kids
        self.location = location
        self.kind = kind
        self.done = done
        self.tentative = tentative
        self.notes = notes
        self.seriesId = seriesId
        self.revision = revision
    }

    public var isUnassigned: Bool {
        let trimmed = owner.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty || trimmed == "TBD"
    }
}

/// Mirrors `TaskKind` including its `category` grouping, which A05 reuses so
/// Family and the assistant report the same activity mix.
public enum EventKind: String, Codable, CaseIterable, Sendable {
    case drive, cook, lead, placeholder, dropoff, pickup
    case practice, lesson, clinic, play, dinner, home, other

    public var category: String {
        switch self {
        case .dropoff, .pickup: return "School"
        case .practice: return "Sports"
        case .lesson: return "Arts"
        case .play: return "Social"
        case .clinic: return "Health"
        case .dinner, .cook, .home: return "Family"
        case .drive, .lead, .placeholder, .other: return "Other"
        }
    }

    public static var categories: [String] {
        ["School", "Sports", "Arts", "Social", "Family", "Health", "Other"]
    }

    /// How long this kind of thing usually takes, used when the request did not
    /// say.
    ///
    /// These are app-owned defaults, not a model guess: "swimming at 4pm" has
    /// no end time, and the assistant must not invent one. The value is stated
    /// on the review card so the user can see what was assumed and change it.
    /// The numbers match durations already present in household data - a school
    /// run is half an hour, a practice an hour and a half, a music lesson
    /// forty-five minutes.
    public var defaultDurationMinutes: Int {
        switch self {
        case .dropoff, .pickup, .drive: return 30
        case .practice: return 90
        case .lesson, .cook: return 45
        case .play: return 120
        case .clinic, .dinner, .home, .lead, .placeholder, .other: return 60
        }
    }
}

public struct AssistantPerson: Identifiable, Codable, Hashable, Sendable {
    public enum Role: String, Codable, Sendable { case caregiver, child }

    public var id: String
    public var name: String
    public var role: Role
    public var relationship: String

    public init(id: String, name: String, role: Role, relationship: String) {
        self.id = id
        self.name = name
        self.role = role
        self.relationship = relationship
    }
}

/// A saved place. Street address and coordinates are deliberately not part of
/// this type: A06 requires minimised context, and no allowlisted operation
/// needs them.
public struct AssistantPlace: Identifiable, Codable, Hashable, Sendable {
    public var id: String { name }
    public var name: String
    public var isVerified: Bool

    public init(name: String, isVerified: Bool) {
        self.name = name
        self.isVerified = isVerified
    }
}

// MARK: - Session

/// Server-derived identity. Everything the tools can reach is scoped by this,
/// never by an id the model supplies. The local caregiver picker in the app is
/// not authentication and must not produce one of these on its own.
public struct AssistantSession: Codable, Hashable, Sendable {
    public var householdID: String
    public var userID: String
    /// IANA identifier, e.g. "America/New_York".
    public var timeZoneIdentifier: String
    /// "YYYY-MM-DD" in the household timezone. Passed to the model explicitly
    /// so it never guesses "today".
    public var today: String
    /// The date range currently on screen, so "this week" resolves the way the
    /// user sees it.
    public var displayedWeekStart: String

    public init(
        householdID: String,
        userID: String,
        timeZoneIdentifier: String,
        today: String,
        displayedWeekStart: String
    ) {
        self.householdID = householdID
        self.userID = userID
        self.timeZoneIdentifier = timeZoneIdentifier
        self.today = today
        self.displayedWeekStart = displayedWeekStart
    }

    public var timeZone: TimeZone {
        TimeZone(identifier: timeZoneIdentifier) ?? TimeZone(secondsFromGMT: 0)!
    }
}

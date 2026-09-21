import Foundation

/// How an event came to exist.
///
/// Added so shortcut suggestions can tell work someone typed out by hand from
/// work the app already automated. Without it the detector cannot distinguish
/// "you have created this five times" from "a shortcut created this five
/// times", and would keep offering to automate something already automated.
///
/// **Optional on `TaskRecord` on purpose.** Households saved before this
/// existed decode with `origin == nil` and are left exactly as they are; see
/// `isLegacy`. Nothing rewrites or discards them, and `seriesId` /
/// `calendarId` remain the authoritative signals for those records.
public enum EventOrigin: Codable, Hashable, Sendable {
    /// Typed into the event editor by a person.
    case manual
    /// Created by tapping a saved shortcut.
    case shortcut(templateID: String)
    /// Materialised as part of a finite series.
    case recurrence(seriesID: String?)
    /// Pulled in from an external calendar.
    case calendarImport(provider: String?)
    /// One event created from a confirmed assistant proposal. Still counts as
    /// hand-made work: the household decided on it one occurrence at a time.
    case assistantSingle
    /// Seeded during onboarding.
    case onboarding
    /// Written by a build that predates provenance, or otherwise unknown.
    case legacy

    /// Whether an event with this origin is work a shortcut could have saved.
    ///
    /// Recurrence, shortcuts and imports are all already automated. Onboarding
    /// seeds are not evidence of a habit.
    public var countsAsManualEffort: Bool {
        switch self {
        case .manual, .assistantSingle: return true
        case .shortcut, .recurrence, .calendarImport, .onboarding, .legacy: return false
        }
    }

    public var templateID: String? {
        if case .shortcut(let id) = self { return id }
        return nil
    }
}

public extension TaskRecord {
    /// True when this record predates provenance. Such records are judged on
    /// `seriesId` and `calendarId` alone rather than being excluded outright,
    /// so an established household still gets suggestions.
    var isLegacyOrigin: Bool { origin == nil }

    /// Whether this record is evidence of repeated manual work.
    ///
    /// A legacy record qualifies when nothing about it says otherwise: not
    /// part of a series, not imported. Coverage by an existing shortcut is
    /// checked separately, against the shortcut list.
    var countsAsManualEffort: Bool {
        if let origin { return origin.countsAsManualEffort }
        return seriesId == nil && calendarId == nil
    }
}

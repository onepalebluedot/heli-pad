import Foundation

/// A reviewed, not-yet-applied change (A04).
///
/// Holds resolved app ids, the recurrence rule, the timezone it was computed
/// in, the conflicts found, the affected count, and the record revisions it was
/// built against. Confirmation revalidates all of that; it is never a replay of
/// whatever the model said.
public struct Proposal: Hashable, Sendable, Identifiable {
    public enum Kind: String, Hashable, Sendable {
        case createEvents
        case assignTasks
    }

    public var id: String
    public var kind: Kind
    public var householdID: String
    public var createdAt: Date
    /// After this instant the proposal must be rebuilt. Stops a review from
    /// being applied hours later against a schedule that moved on.
    public var expiresAt: Date
    public var timeZoneIdentifier: String
    /// The exact work to perform, already resolved to ids.
    public var batch: MutationBatch
    /// Revisions the batch was computed against, by event id. Empty for pure
    /// creates.
    public var sourceRevisions: [String: Int]
    public var conflicts: [ScheduleConflict]
    /// Number of records this would create or change.
    public var affectedCount: Int
    /// App-authored description of the recurrence, shown verbatim on the card.
    public var ruleDescription: String?

    public init(
        id: String = UUID().uuidString,
        kind: Kind,
        householdID: String,
        createdAt: Date,
        expiresAt: Date,
        timeZoneIdentifier: String,
        batch: MutationBatch,
        sourceRevisions: [String: Int] = [:],
        conflicts: [ScheduleConflict] = [],
        affectedCount: Int,
        ruleDescription: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.householdID = householdID
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.timeZoneIdentifier = timeZoneIdentifier
        self.batch = batch
        self.sourceRevisions = sourceRevisions
        self.conflicts = conflicts
        self.affectedCount = affectedCount
        self.ruleDescription = ruleDescription
    }

    public func isExpired(at now: Date) -> Bool { now >= expiresAt }
}

/// A clash the app found. Conflicts stay visible on the review; nothing here
/// silently reschedules or overrides them.
public struct ScheduleConflict: Hashable, Sendable, Identifiable, Codable {
    public enum Cause: String, Hashable, Sendable, Codable {
        /// Two events for the same caregiver overlap once the travel buffer is
        /// applied.
        case caregiverDoubleBooked
        /// The same child is expected in two places at once.
        case childDoubleBooked
        /// Lands inside the household's protected dinner window.
        case dinnerWindow
    }

    public var id: String
    public var cause: Cause
    public var date: String
    /// The existing event involved, when there is one.
    public var existingEventID: String?
    /// App-authored explanation. Household text inside it is quoted.
    public var detail: String

    public init(id: String = UUID().uuidString, cause: Cause, date: String, existingEventID: String?, detail: String) {
        self.id = id
        self.cause = cause
        self.date = date
        self.existingEventID = existingEventID
        self.detail = detail
    }
}

/// The reviewable form of a `Proposal`.
public struct ProposalCard: Hashable, Sendable, Codable {
    public var proposalID: String
    public var headline: String
    /// e.g. "Every Tuesday for 30 weeks"
    public var ruleDescription: String?
    public var affectedCount: Int
    public var periodLabel: String
    /// Every occurrence, so the user confirms the real list rather than a count.
    public var rows: [EventRow]
    public var conflicts: [ScheduleConflict]
    public var destinationNote: String
    /// Anything the app filled in because the request did not say - a default
    /// duration, a fallback location. Shown so the user confirms what will
    /// actually be saved, not an abbreviation of it.
    public var assumptions: [String]
    public var expiresAt: Date

    public init(
        proposalID: String,
        headline: String,
        ruleDescription: String?,
        affectedCount: Int,
        periodLabel: String,
        rows: [EventRow],
        conflicts: [ScheduleConflict],
        destinationNote: String,
        assumptions: [String] = [],
        expiresAt: Date
    ) {
        self.proposalID = proposalID
        self.headline = headline
        self.ruleDescription = ruleDescription
        self.affectedCount = affectedCount
        self.periodLabel = periodLabel
        self.rows = rows
        self.conflicts = conflicts
        self.destinationNote = destinationNote
        self.assumptions = assumptions
        self.expiresAt = expiresAt
    }
}

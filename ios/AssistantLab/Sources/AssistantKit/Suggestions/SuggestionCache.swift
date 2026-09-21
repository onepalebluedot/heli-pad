import Foundation

/// Everything remembered about suggestions for one household + caregiver.
///
/// Deliberately a value type keyed by session: nothing here is global, so one
/// household's cache, refresh clock and dismissals cannot surface in another.
public struct SuggestionCacheEntry: Codable, Hashable, Sendable {
    public var suggestions: [ShortcutSuggestion]
    /// What the detector saw when these were ranked. A change means there is
    /// something new to rank.
    public var fingerprint: String
    /// Last time a model ranking actually succeeded.
    public var lastRankedAt: Date?
    /// Last failed attempt, for bounded retry.
    public var lastFailureAt: Date?
    public var consecutiveFailures: Int
    /// Candidate id -> when it was dismissed.
    public var dismissals: [String: Date]
    /// Candidate id -> occurrences at the time it was dismissed, so
    /// substantial new evidence can bring it back early.
    public var dismissedAtOccurrences: [String: Int]

    public init(
        suggestions: [ShortcutSuggestion] = [],
        fingerprint: String = "",
        lastRankedAt: Date? = nil,
        lastFailureAt: Date? = nil,
        consecutiveFailures: Int = 0,
        dismissals: [String: Date] = [:],
        dismissedAtOccurrences: [String: Int] = [:]
    ) {
        self.suggestions = suggestions
        self.fingerprint = fingerprint
        self.lastRankedAt = lastRankedAt
        self.lastFailureAt = lastFailureAt
        self.consecutiveFailures = consecutiveFailures
        self.dismissals = dismissals
        self.dismissedAtOccurrences = dismissedAtOccurrences
    }
}

/// When to spend a model request, what to show meanwhile, and when a dismissed
/// suggestion may come back.
///
/// Pure policy, no storage and no clock of its own, so every rule below is
/// directly testable.
public enum SuggestionPolicy {
    /// A dismissal is a snooze, not a permanent block.
    public static let snoozeDays = 90
    /// Or sooner, if this many further manual occurrences pile up.
    public static let newEvidenceOccurrences = 2

    /// Bounded retry after a failure, so a broken service is not hit on every
    /// visit to Family.
    public static let retryBackoff: [TimeInterval] = [
        30 * 60,        // half an hour
        6 * 60 * 60,    // six hours
        24 * 60 * 60    // then daily
    ]

    /// Whether a dismissed candidate is allowed to reappear.
    public static func isSnoozed(
        _ candidate: ShortcutCandidate,
        entry: SuggestionCacheEntry,
        now: Date
    ) -> Bool {
        guard let dismissedAt = entry.dismissals[candidate.id] else { return false }

        let elapsed = now.timeIntervalSince(dismissedAt)
        if elapsed >= Double(snoozeDays) * 24 * 60 * 60 { return false }

        // Substantial new evidence outranks the snooze: if they kept doing it
        // by hand, the suggestion has earned another look.
        if let then = entry.dismissedAtOccurrences[candidate.id],
           candidate.occurrences - then >= newEvidenceOccurrences {
            return false
        }
        return true
    }

    /// Whether it is worth calling the model.
    ///
    /// Only when there is something new to rank, or the last ranking has aged
    /// out - and never while a failure backoff is still running.
    public static func shouldRequestRanking(
        candidates: [ShortcutCandidate],
        entry: SuggestionCacheEntry,
        now: Date
    ) -> Bool {
        guard !candidates.isEmpty else { return false }

        if let lastFailureAt = entry.lastFailureAt {
            let step = min(entry.consecutiveFailures, retryBackoff.count) - 1
            let wait = retryBackoff[max(0, step)]
            if now.timeIntervalSince(lastFailureAt) < wait { return false }
        }

        let fingerprint = ShortcutPatternFinder.fingerprint(candidates)
        if fingerprint != entry.fingerprint { return true }

        guard let lastRankedAt = entry.lastRankedAt else { return true }
        return now.timeIntervalSince(lastRankedAt) >= SuggestionService.refreshInterval
    }

    /// Filters a cached list against what the detector currently sees.
    ///
    /// Run before display, every time. A suggestion whose pattern has gone -
    /// the events were deleted, or a shortcut now covers it - disappears at
    /// once rather than waiting for the next ranking, and its counts are
    /// refreshed from the live candidate so evidence never goes stale.
    public static func revalidate(
        _ cached: [ShortcutSuggestion],
        against candidates: [ShortcutCandidate],
        entry: SuggestionCacheEntry,
        now: Date
    ) -> [ShortcutSuggestion] {
        let live = Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0) })
        return cached.compactMap { suggestion in
            guard let candidate = live[suggestion.id] else { return nil }
            guard !isSnoozed(candidate, entry: entry, now: now) else { return nil }
            var refreshed = suggestion
            refreshed.candidate = candidate
            refreshed.evidence = SuggestionService.evidence(for: candidate)
            return refreshed
        }
    }
}

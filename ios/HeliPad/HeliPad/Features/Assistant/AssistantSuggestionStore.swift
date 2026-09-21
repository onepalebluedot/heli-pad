import Foundation
import SwiftUI
import AssistantKit

/// Owns the shortcut suggestions shown on Family: local detection, when to
/// spend a model request, caching, dismissal and household isolation.
///
/// Everything is keyed by household + caregiver. There is no global cache, so
/// switching household cannot surface another family's suggestions, refresh
/// clock or dismissals.
@MainActor
public final class AssistantSuggestionStore: ObservableObject {
    /// Empty hides the whole Smart Suggestions section.
    @Published public private(set) var suggestions: [ShortcutSuggestion] = []

    private let store: AppStore
    private let now: () -> Date
    private var refreshing = false
    /// The session the published list currently belongs to.
    private var loadedKey: String?

    public init(store: AppStore, now: @escaping () -> Date = { Date() }) {
        self.store = store
        self.now = now
    }

    // MARK: - Per-household storage

    private func key(for session: AssistantSession) -> String {
        "assistant.suggestions.\(session.userID)|\(session.householdID)"
    }

    private func entry(for session: AssistantSession) -> SuggestionCacheEntry {
        guard let data = UserDefaults.standard.data(forKey: key(for: session)),
              let entry = try? JSONDecoder().decode(SuggestionCacheEntry.self, from: data) else {
            return SuggestionCacheEntry()
        }
        return entry
    }

    private func save(_ entry: SuggestionCacheEntry, for session: AssistantSession) {
        guard let data = try? JSONEncoder().encode(entry) else { return }
        UserDefaults.standard.set(data, forKey: key(for: session))
    }

    // MARK: - Detection

    /// The candidates the detector currently sees. Cheap, local, no network.
    public func currentCandidates() -> [ShortcutCandidate] {
        let placeIDs = AssistantHouseholdAdapter.placeIDLookup(store.locations)
        return ShortcutPatternFinder.candidates(
            events: store.records().map { AssistantHouseholdAdapter.toAssistant($0, placeIDs: placeIDs) },
            shortcuts: store.templates.map { Self.shortcut(from: $0, placeIDs: placeIDs) },
            today: PlanCore.currentDeviceDate()
        )
    }

    static func shortcut(from template: TemplateItem, placeIDs: [String: String] = [:]) -> ExistingShortcut {
        ExistingShortcut(
            id: template.id,
            title: template.title,
            location: template.location,
            placeID: placeIDs[template.location.lowercased()],
            kids: template.kids,
            startTime: template.time,
            durationMinutes: template.duration
        )
    }

    // MARK: - Refresh

    /// Local-only pass. Cheap enough to run whenever something changed: on
    /// Family appearing, on foreground, and after any event or shortcut edit.
    /// Never touches the network.
    public func refreshLocally(session: AssistantSession) {
        let candidates = currentCandidates()
        let entry = entry(for: session)
        loadedKey = key(for: session)
        suggestions = SuggestionPolicy.revalidate(
            entry.suggestions, against: candidates, entry: entry, now: now()
        )
    }

    /// Local pass, then a model ranking only if the policy says it is worth it.
    public func refresh(client: LunaClient?, session: AssistantSession) async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }

        let candidates = currentCandidates()
        var entry = entry(for: session)
        loadedKey = key(for: session)

        // Show what is already known, revalidated, before anything slow.
        suggestions = SuggestionPolicy.revalidate(
            entry.suggestions, against: candidates, entry: entry, now: now()
        )

        guard SuggestionPolicy.shouldRequestRanking(candidates: candidates, entry: entry, now: now()) else {
            return
        }

        let visible = candidates.filter { !SuggestionPolicy.isSnoozed($0, entry: entry, now: now()) }
        guard !visible.isEmpty else {
            // Nothing to ask about. Record the fingerprint so this does not
            // re-evaluate on every visit.
            entry.fingerprint = ShortcutPatternFinder.fingerprint(candidates)
            entry.suggestions = []
            save(entry, for: session)
            suggestions = []
            return
        }

        let ranked = await SuggestionService(client: client).rank(visible)

        if client != nil && ranked.allSatisfy(\.isLocalOnly) && !ranked.isEmpty {
            // The service fell back, so this was not a successful ranking.
            // Show the local result but keep the retry clock running.
            entry.lastFailureAt = now()
            entry.consecutiveFailures += 1
            entry.suggestions = ranked
            save(entry, for: session)
            suggestions = ranked
            return
        }

        entry.suggestions = ranked
        entry.fingerprint = ShortcutPatternFinder.fingerprint(candidates)
        entry.lastRankedAt = now()
        entry.lastFailureAt = nil
        entry.consecutiveFailures = 0
        save(entry, for: session)
        suggestions = ranked
    }

    // MARK: - User actions

    /// The user saved this as a shortcut, so stop offering it. The shortcut
    /// itself will also cover the pattern from the next local pass.
    public func accept(_ suggestion: ShortcutSuggestion, session: AssistantSession) {
        dismiss(suggestion, session: session)
    }

    /// A snooze, not a permanent block. `SuggestionPolicy` decides when it may
    /// come back.
    public func dismiss(_ suggestion: ShortcutSuggestion, session: AssistantSession) {
        var entry = entry(for: session)
        entry.dismissals[suggestion.id] = now()
        entry.dismissedAtOccurrences[suggestion.id] = suggestion.candidate.occurrences
        entry.suggestions.removeAll { $0.id == suggestion.id }
        save(entry, for: session)
        suggestions.removeAll { $0.id == suggestion.id }
    }

    /// Household or caregiver changed: drop what is on screen so the previous
    /// household's suggestions cannot linger while the new ones load.
    public func resetForSessionChange() {
        suggestions = []
        loadedKey = nil
    }
}

import Foundation

/// Decides which detected patterns are worth offering as shortcuts.
///
/// The division of labour is the point. **Code** finds the patterns and owns
/// every number: counts, weeks, places, children, times, evidence text. **The
/// model** does only what code is bad at - judging whether a pattern is worth
/// interrupting someone about, and naming it in the household's own words.
///
/// It can decline everything, and that is a normal outcome. When it is
/// unavailable the app falls back to its own ranking rather than showing an
/// error: a suggestion is never worth an error card.
public struct SuggestionService: Sendable {
    /// How long a successful ranking stands before it is worth asking again.
    public static let refreshInterval: TimeInterval = 14 * 24 * 60 * 60
    public static let maxSuggestions = 3

    private let client: LunaClient?
    public init(client: LunaClient?) {
        self.client = client
    }

    /// - Returns: what to show. Empty means show nothing, which hides the
    ///   whole section.
    public func rank(_ candidates: [ShortcutCandidate]) async -> [ShortcutSuggestion] {
        guard !candidates.isEmpty else { return [] }
        guard let client else { return Self.localRanking(candidates) }

        let request = LunaRequest(
            kind: .structured(name: "helipad_shortcut_suggestions", schemaJSON: Self.schemaJSON),
            instructions: Self.instructions,
            items: [.userMessage(Self.payload(candidates))],
            maxOutputTokens: 400
        )

        do {
            let reply = try await client.send(request)
            guard case .structured(let json) = reply else { return Self.localRanking(candidates) }
            return Self.validate(json, against: candidates)
        } catch {
            // Offline, quota, anything. The local ranking is still honest
            // work, so it is shown rather than an error.
            return Self.localRanking(candidates)
        }
    }

    public func suggestions(from candidates: [ShortcutCandidate]) async throws -> [ShortcutSuggestion] {
        await rank(candidates)
    }

    /// Ranking without a model: the detector's own order, capped, labelled
    /// with the household's own titles.
    public static func localRanking(_ candidates: [ShortcutCandidate]) -> [ShortcutSuggestion] {
        candidates.prefix(maxSuggestions).map {
            ShortcutSuggestion(
                candidate: $0,
                label: $0.representativeTitle,
                evidence: evidence(for: $0),
                isLocalOnly: true
            )
        }
    }

    /// Keeps only selections naming a real candidate, with a label that holds
    /// up. Invented ids, duplicates and malformed output are dropped.
    public static func validate(_ json: String, against candidates: [ShortcutCandidate]) -> [ShortcutSuggestion] {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let picks = root["suggestions"] as? [[String: Any]] else {
            return []
        }
        let byID = Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0) })

        var out: [ShortcutSuggestion] = []
        var seen: Set<String> = []
        for pick in picks {
            guard let id = pick["candidate_id"] as? String,
                  let candidate = byID[id],
                  !seen.contains(id) else { continue }
            seen.insert(id)

            // A label may only restate facts the candidate already carries, so
            // it cannot assert a count or a place that is not real.
            let label = ProseValidator
                .validate(pick["label"] as? String, evidence: [groundingText(candidate)])
                .text ?? candidate.representativeTitle

            out.append(ShortcutSuggestion(
                candidate: candidate,
                label: String(label.prefix(48)),
                evidence: evidence(for: candidate)
            ))
            if out.count == maxSuggestions { break }
        }
        return out
    }

    /// App-authored, always shown. This is what makes a suggestion visibly
    /// earned rather than asserted.
    public static func evidence(for candidate: ShortcutCandidate) -> String {
        let times = candidate.occurrences == 1 ? "once" : "\(candidate.occurrences) times"
        let weeks = candidate.distinctWeeks == 1 ? "one week" : "\(candidate.distinctWeeks) weeks"
        return "Added manually \(times) across \(weeks)."
    }

    /// A time to show beside the place, in the household's locale.
    public static func timeLabel(for candidate: ShortcutCandidate) -> String {
        TimeLabel.clock(candidate.startTime)
    }

    static func groundingText(_ candidate: ShortcutCandidate) -> String {
        ([
            candidate.representativeTitle,
            candidate.titleVariants.joined(separator: " "),
            candidate.location,
            candidate.kids.joined(separator: " "),
            String(candidate.durationMinutes),
            candidate.startTime,
            String(candidate.occurrences),
            String(candidate.distinctWeeks),
            candidate.firstDate,
            candidate.lastDate
        ]).joined(separator: " ")
    }

    /// Only the facts needed to choose between candidates. No notes, no
    /// addresses, no unrelated household data, no raw events.
    static func payload(_ candidates: [ShortcutCandidate]) -> String {
        let rows = candidates.map { candidate -> [String: Any] in
            [
                "candidate_id": candidate.id,
                "titles_used": candidate.titleVariants.map { UntrustedText($0).forModel(limit: 60) },
                "place": UntrustedText(candidate.location).forModel(limit: 60),
                "children": candidate.kids.map { UntrustedText($0).forModel(limit: 40) },
                "minutes": candidate.durationMinutes,
                "usual_start": candidate.startTime,
                "category": candidate.category,
                "times_added_by_hand": candidate.occurrences,
                "distinct_weeks": candidate.distinctWeeks,
                "first": candidate.firstDate,
                "last": candidate.lastDate
            ]
        }
        let data = (try? JSONSerialization.data(withJSONObject: ["candidates": rows], options: [.sortedKeys])) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    static let instructions = """
    A family scheduling app found activities its household has been creating one \
    at a time, by hand. Each could be saved as a one-tap shortcut. Decide which \
    are worth offering.

    Offer one only when a shortcut would clearly save real work: the same \
    activity, same place, same children, happening regularly and still current.

    Decline freely. An empty list is the right answer when nothing stands out, \
    and is better than a weak suggestion - the app hides the whole section when \
    you return nothing.

    For each one you offer, write a short label from the titles the household \
    already used. Two to four words. Invent nothing: no numbers, places, names \
    or claims that are not in the candidate. The app prints the counts, dates \
    and places itself.

    At most three, strongest first.
    """

    static let schemaJSON = """
    {
      "type": "object",
      "additionalProperties": false,
      "required": ["suggestions"],
      "properties": {
        "suggestions": {
          "type": "array",
          "maxItems": 3,
          "items": {
            "type": "object",
            "additionalProperties": false,
            "required": ["candidate_id", "label"],
            "properties": {
              "candidate_id": {
                "type": "string",
                "description": "Must be one of the candidate_id values supplied. Do not invent one."
              },
              "label": {
                "type": "string",
                "description": "Two to four words, in the household's own wording."
              }
            }
          }
        }
      }
    }
    """
}

/// Minimal 12-hour clock formatting for evidence lines.
enum TimeLabel {
    static func clock(_ time: String) -> String {
        guard let minutes = CalendarMath.minutes(time) else { return time }
        let hour24 = minutes / 60
        let minute = minutes % 60
        let hour = hour24 % 12 == 0 ? 12 : hour24 % 12
        let suffix = hour24 < 12 ? "AM" : "PM"
        return String(format: "%d:%02d %@", hour, minute, suffix)
    }
}

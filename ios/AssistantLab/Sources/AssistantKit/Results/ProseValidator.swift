import Foundation

/// Decides whether the model's own wording is safe to show.
///
/// The original design forbade model prose entirely and rendered only
/// app-owned templates. That made the assistant unpleasant to talk to, so
/// prose is now allowed - but the property that mattered is kept by a
/// different mechanism.
///
/// The property: **the assistant must not assert a fact about this household
/// that the app did not compute.** The mechanism: every number in the message
/// has to appear in the output of an operation that actually ran this turn. A
/// model that says "you have 14 events" when `find_events` returned 12 is
/// rejected, and the app's own sentence is shown instead.
///
/// Honest about the limits. This catches fabricated *figures*, which is the
/// failure mode with real consequences for a schedule. It does not catch a
/// fabricated qualitative claim ("your week looks quiet"), and a number
/// written as a word slips through. It is a strong mitigation, not a proof -
/// which is why the typed cards still carry the authoritative version of
/// every fact, right underneath the prose.
public enum ProseValidator {
    /// Two sentences of warmth is the point; a paragraph is the model taking
    /// over the screen from the cards.
    public static let maxLength = 400

    public enum Outcome: Equatable, Sendable {
        case accepted(String)
        case rejected(Rejection)

        public var text: String? {
            if case .accepted(let value) = self { return value }
            return nil
        }
    }

    public enum Rejection: Equatable, Sendable {
        case empty
        case tooLong(Int)
        /// A figure that no operation produced.
        case ungroundedNumber(String)
        /// Numbers in a turn where nothing was looked up.
        case numericWithoutEvidence(String)
    }

    /// - Parameters:
    ///   - message: the model's text.
    ///   - evidence: raw tool payloads from this turn. Empty when no
    ///     operation ran, which switches on the stricter rule.
    public static func validate(_ message: String?, evidence: [String]) -> Outcome {
        // Control characters become spaces rather than vanishing. A newline is
        // a control character, so deleting it would weld the words either side
        // of it together.
        let despaced = (message ?? "").map { character -> Character in
            character.unicodeScalars.allSatisfy { CharacterSet.controlCharacters.contains($0) } ? " " : character
        }
        let collapsed = String(despaced)
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        guard !collapsed.isEmpty else { return .rejected(.empty) }
        guard collapsed.count <= maxLength else { return .rejected(.tooLong(collapsed.count)) }

        let written = numbers(in: collapsed)
        guard !written.isEmpty else { return .accepted(collapsed) }

        // Nothing was looked up, so there is no evidence any figure could have
        // come from. A greeting has no business quoting a count.
        guard !evidence.isEmpty else {
            return .rejected(.numericWithoutEvidence(written.first!))
        }

        let grounded = evidence.flatMap { numbers(in: $0) }
        let groundedSet = Set(grounded)
        for value in written where !groundedSet.contains(value) {
            return .rejected(.ungroundedNumber(value))
        }
        return .accepted(collapsed)
    }

    /// Pulls out every run of digits, normalised so "05" and "5" compare equal
    /// and a date in prose matches the same date in a payload.
    ///
    /// Deliberately crude: it compares digit runs rather than parsing
    /// quantities, so "Sep 15" grounds against `"2026-09-15"` and `16:00`
    /// grounds against `"16:00"`. Being loose here costs some strictness and
    /// buys far fewer false rejections of correct sentences.
    static func numbers(in text: String) -> [String] {
        var found: [String] = []
        var current = ""
        for character in text {
            if character.isNumber {
                current.append(character)
            } else if !current.isEmpty {
                found.append(normalise(current))
                current = ""
            }
        }
        if !current.isEmpty { found.append(normalise(current)) }
        return found
    }

    private static func normalise(_ digits: String) -> String {
        let trimmed = digits.drop(while: { $0 == "0" })
        return trimmed.isEmpty ? "0" : String(trimmed)
    }
}

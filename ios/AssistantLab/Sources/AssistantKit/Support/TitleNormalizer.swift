import Foundation

/// Tidies a title the way the manual editor would.
///
/// The tool schema asks the model for the user's own words, which is right —
/// it should not paraphrase what someone called their kid's activity. But
/// "swimming" typed into a sentence arrives lowercase, and the manual editor
/// would have produced "Swimming". Fixing that here rather than in the prompt
/// keeps it deterministic and keeps the model out of a decision it does not
/// need to make.
public enum TitleNormalizer {
    public static func normalize(_ raw: String) -> String {
        let collapsed = raw
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard let first = collapsed.first else { return collapsed }

        // Only capitalise when the opening word is entirely lowercase. That
        // leaves deliberate casing alone: "iPad setup" and "LEGO club" keep
        // their shape instead of becoming "IPad" and "LEGO" respectively
        // mangled by a blanket capitalisation.
        let firstWord = collapsed.prefix { !$0.isWhitespace }
        guard firstWord.allSatisfy({ !$0.isUppercase }) else { return collapsed }

        return first.uppercased() + collapsed.dropFirst()
    }
}

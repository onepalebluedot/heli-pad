import Foundation

/// Reads a `.env` file for local development.
///
/// This exists so a real key can be kept out of your shell history and out of
/// the repository. It is read by the command-line harness only. No app target
/// depends on this module, and nothing here is compiled into HeliPad.
public enum DotEnv {
    /// Values already in the process environment win, so
    /// `OPENAI_API_KEY=... swift run ...` overrides the file without editing it.
    @discardableResult
    public static func load(from url: URL? = nil) -> [String: String] {
        let location = url ?? defaultLocation()
        var values: [String: String] = [:]

        guard let contents = try? String(contentsOf: location, encoding: .utf8) else {
            return values
        }

        for rawLine in contents.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }

            // `export FOO=bar` is common in files people paste from docs.
            let body = line.hasPrefix("export ") ? String(line.dropFirst(7)) : line
            guard let separator = body.firstIndex(of: "=") else { continue }

            let key = String(body[body.startIndex..<separator]).trimmingCharacters(in: .whitespaces)
            var value = String(body[body.index(after: separator)...]).trimmingCharacters(in: .whitespaces)

            // Strip one matching pair of surrounding quotes, so a key pasted
            // with quotes does not arrive with them attached.
            if value.count >= 2, let first = value.first, let last = value.last,
               first == last, first == "\"" || first == "'" {
                value = String(value.dropFirst().dropLast())
            }
            guard !key.isEmpty, !value.isEmpty else { continue }
            values[key] = value
        }
        return values
    }

    /// Merges file values under the real environment and returns the lookup the
    /// harness uses.
    public static func environment(from url: URL? = nil) -> [String: String] {
        var merged = load(from: url)
        for (key, value) in ProcessInfo.processInfo.environment {
            merged[key] = value
        }
        return merged
    }

    /// `AssistantLab/.env`, found relative to this source file so it works
    /// whatever directory `swift run` was invoked from.
    public static func defaultLocation(file: StaticString = #filePath) -> URL {
        URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent()   // AssistantDevRelay
            .deletingLastPathComponent()   // Sources
            .deletingLastPathComponent()   // AssistantLab
            .appendingPathComponent(".env")
    }
}

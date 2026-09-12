import Foundation
import AssistantKit

/// Calls the OpenAI Responses API directly with a key from the environment.
///
/// **Development only. This must never ship in the app.**
///
/// A01 requires that the provider key lives on a server and that the device
/// holds only a session token. This client does the opposite: it puts the key
/// in the process that makes the request. That is acceptable on your Mac,
/// where the key is already in a file you control, and unacceptable on a phone,
/// where the bundle is readable by anyone who has the device.
///
/// The isolation that makes this safe is structural: `AssistantDevRelay` is its
/// own target, and neither `AssistantKit` nor `AssistantUI` depends on it. Only
/// `AssistantHarness` links it, and the harness is a command-line tool.
///
/// Everything else is identical to the production path. The request body, the
/// tool schemas, the structured-output contract and the reply parsing all come
/// from `ResponsesWire`, so what you exercise here is the request the relay
/// will forward once it exists.
public struct DirectOpenAIClient: LunaClient {
    public struct Configuration: Sendable {
        public var apiKey: String
        public var model: String
        public var baseURL: URL
        public var timeout: TimeInterval
        /// Prints the provider's own error text. Useful on your machine, and
        /// the reason this client is not allowed near the app: those messages
        /// can name your project and organisation.
        public var verboseErrors: Bool

        public init(
            apiKey: String,
            model: String,
            baseURL: URL = URL(string: "https://api.openai.com/v1")!,
            timeout: TimeInterval = 60,
            verboseErrors: Bool = true
        ) {
            self.apiKey = apiKey
            self.model = model
            self.baseURL = baseURL
            self.timeout = timeout
            self.verboseErrors = verboseErrors
        }
    }

    public enum SetupError: Error, CustomStringConvertible {
        case missingKey(checkedPath: String)

        public var description: String {
            switch self {
            case .missingKey(let path):
                return """
                No OPENAI_API_KEY found.

                Put it in \(path):

                    OPENAI_API_KEY=sk-...
                    HELIPAD_ASSISTANT_MODEL=gpt-5.6-luna

                or pass it for one run:

                    OPENAI_API_KEY=sk-... swift run AssistantHarness --live

                The file is already covered by the repository's .gitignore.
                """
            }
        }
    }

    private let configuration: Configuration
    private let session: URLSession

    public init(configuration: Configuration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    /// Builds a client from `.env` plus the process environment, or explains
    /// what is missing.
    ///
    /// The model id is not defaulted to something that is known to work: the
    /// plan is explicit that no other model may be silently substituted, so an
    /// account without access should see the provider's rejection rather than
    /// a quiet downgrade.
    public static func fromEnvironment(defaultModel: String = "gpt-5.6-luna") throws -> DirectOpenAIClient {
        let environment = DotEnv.environment()
        guard let key = environment["OPENAI_API_KEY"], !key.isEmpty else {
            throw SetupError.missingKey(checkedPath: DotEnv.defaultLocation().path)
        }
        var configuration = Configuration(
            apiKey: key,
            model: environment["HELIPAD_ASSISTANT_MODEL"] ?? defaultModel
        )
        if let base = environment["OPENAI_BASE_URL"], let url = URL(string: base) {
            configuration.baseURL = url
        }
        return DirectOpenAIClient(configuration: configuration)
    }

    public var model: String { configuration.model }

    public func send(_ request: LunaRequest) async throws -> LunaReply {
        var urlRequest = URLRequest(url: configuration.baseURL.appendingPathComponent("responses"))
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = configuration.timeout
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try JSONSerialization.data(
            withJSONObject: try ResponsesWire.body(model: configuration.model, request: request),
            options: []
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch let error as URLError {
            throw ResponsesWire.lunaError(from: error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw LunaError.invalidResponse("no HTTP response")
        }
        switch http.statusCode {
        case 200:
            return try ResponsesWire.parse(data)
        case 429:
            throw LunaError.quotaExceeded
        default:
            throw LunaError.service(status: http.statusCode, detail: detail(from: data, status: http.statusCode))
        }
    }

    /// The provider's message, so a rejected model id or a missing scope is
    /// legible rather than a bare status code. Only reachable when
    /// `verboseErrors` is on, which no shipped configuration sets.
    private func detail(from data: Data, status: Int) -> String {
        guard configuration.verboseErrors,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = root["error"] as? [String: Any] else {
            return "HTTP \(status)"
        }
        let message = error["message"] as? String ?? "no message"
        let code = error["code"] as? String ?? error["type"] as? String ?? "\(status)"
        return "\(code): \(message)"
    }
}

import Foundation

/// Talks to the household's own authenticated service, which forwards to the
/// OpenAI Responses API with a server-held project key (A01, A02).
///
/// The device never sees a provider credential, so a jailbroken phone, a
/// sysdiagnose or a screenshot of settings cannot leak one. The relay is also
/// where per-household rate limiting and the model-id check belong, since a
/// client-side limit is advisory at best.
public struct RelayLunaClient: LunaClient {
    private let configuration: AssistantConfiguration
    private let tokens: SessionTokenProvider
    private let session: URLSession

    public init(
        configuration: AssistantConfiguration,
        tokens: SessionTokenProvider,
        session: URLSession = .shared
    ) {
        self.configuration = configuration
        self.tokens = tokens
        self.session = session
    }

    public func send(_ request: LunaRequest) async throws -> LunaReply {
        var urlRequest = URLRequest(url: configuration.relayBaseURL.appendingPathComponent("assistant/respond"))
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = configuration.requestTimeout
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(try await tokens.bearerToken())", forHTTPHeaderField: "Authorization")

        let body = try ResponsesWire.body(model: configuration.model, request: request)
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

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
            break
        case 401, 403:
            throw LunaError.service(status: http.statusCode, detail: "session rejected")
        case 429:
            throw LunaError.quotaExceeded
        default:
            // Never surfaced verbatim: a provider error body can contain
            // configuration detail that does not belong on a family's screen.
            throw LunaError.service(status: http.statusCode, detail: "relay returned \(http.statusCode)")
        }

        return try ResponsesWire.parse(data)
    }
}

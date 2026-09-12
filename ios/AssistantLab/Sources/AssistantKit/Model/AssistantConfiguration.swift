import Foundation

/// Client-side configuration.
///
/// The provider key is deliberately absent: it lives on the relay. Nothing here
/// is a secret, so it is safe in the bundle and in a snapshot (A01).
public struct AssistantConfiguration: Sendable {
    /// The household's own authenticated service, never `api.openai.com`. The
    /// device has no provider credential to call the provider directly with.
    public var relayBaseURL: URL
    /// Model id, configured by the deployment. `gpt-5.6-luna` per the plan's
    /// reference; the relay is the authority and rejects a mismatch rather than
    /// quietly substituting another model.
    public var model: String
    /// Ceiling on model turns per user message. Each round is at most one batch
    /// of tool calls, so this also bounds tool executions.
    public var maxToolRounds: Int
    public var maxOutputTokens: Int
    public var requestTimeout: TimeInterval

    public init(
        relayBaseURL: URL,
        model: String = "gpt-5.6-luna",
        maxToolRounds: Int = 4,
        maxOutputTokens: Int = 700,
        requestTimeout: TimeInterval = 30
    ) {
        self.relayBaseURL = relayBaseURL
        self.model = model
        self.maxToolRounds = maxToolRounds
        self.maxOutputTokens = maxOutputTokens
        self.requestTimeout = requestTimeout
    }
}

/// Supplies the short-lived session token proving who is asking. The production
/// implementation reads it from Keychain; it is never a household id typed into
/// settings, and never the local caregiver picker's selection.
public protocol SessionTokenProvider: Sendable {
    func bearerToken() async throws -> String
}

public struct StaticTokenProvider: SessionTokenProvider {
    private let token: String
    public init(_ token: String) { self.token = token }
    public func bearerToken() async throws -> String { token }
}

import Foundation

/// Device-local assistant settings.
///
/// Deliberately kept out of the synced household document. A session token
/// identifies *this device*, so syncing it to the other phone would be wrong
/// as well as unsafe, and the disclosure acknowledgement is a per-device
/// preference. Keeping them here also means the household fingerprint and the
/// two-phone merge are untouched by this feature.
public extension AppStore {
    private enum AssistantKeys {
        static let relayURL = "assistant.relayURL"
        static let sessionToken = "assistant.sessionToken"
        static let disclosure = "assistant.disclosureAcknowledged"
    }

    /// Base URL of the household's assistant service. Empty until A01 is
    /// deployed; a developer can point it at a relay on their own machine.
    var assistantRelayURL: String {
        get { UserDefaults.standard.string(forKey: AssistantKeys.relayURL) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: AssistantKeys.relayURL) }
    }

    /// Short-lived token proving who is asking.
    ///
    /// In UserDefaults rather than Keychain only because there is nothing real
    /// to store yet - A01 has no session issuance. **Move this to Keychain as
    /// part of A01**, alongside the rest of the session handling; the plan
    /// calls for exactly that and this is a placeholder until then.
    var assistantSessionToken: String {
        get { UserDefaults.standard.string(forKey: AssistantKeys.sessionToken) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: AssistantKeys.sessionToken) }
    }

    var assistantDisclosureAcknowledged: Bool {
        get { UserDefaults.standard.bool(forKey: AssistantKeys.disclosure) }
        set { UserDefaults.standard.set(newValue, forKey: AssistantKeys.disclosure) }
    }

    /// True when there is somewhere to send a request.
    var isAssistantConfigured: Bool {
        !assistantRelayURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !assistantSessionToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

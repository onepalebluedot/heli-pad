import Foundation
import SwiftUI
import AssistantKit
import AssistantUI

/// Assembles the assistant for the running app and owns its configuration.
///
/// Built lazily the first time the sheet is opened, and torn down when the
/// household or signed-in caregiver changes, so no part of one family's
/// conversation can survive into another's.
@MainActor
public final class AssistantHost: ObservableObject {
    /// Nil until the relay is configured. A06 requires the failure to be
    /// truthful rather than a chat box that silently does nothing.
    @Published public private(set) var chat: AssistantChatModel?
    @Published public private(set) var unavailableReason: String?

    private let store: AppStore
    /// Chat history on disk, in Application Support so it is backed up with
    /// the app's own data and excluded from the user's Documents.
    private let transcript = ChatTranscript(storageDirectory: AssistantHost.transcriptDirectory)

    private static var transcriptDirectory: URL? {
        try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("Assistant", isDirectory: true)
    }
    private var builtFor: String?

    public init(store: AppStore) {
        self.store = store
    }

    /// The household's own service. Empty in this build: A01 is not deployed,
    /// so there is nothing to point at except a relay a developer runs
    /// locally. It is read from settings rather than hard-coded so a staging
    /// deployment needs no code change.
    private var relayURL: URL? {
        let raw = store.assistantRelayURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        return URL(string: raw)
    }

    private var sessionKey: String {
        "\(store.currentUser)|\(store.cloudHouseholdID)"
    }

    public func prepare() {
        // A changed caregiver or household invalidates everything: the
        // transcript, the engine's context and any pending review.
        if builtFor != sessionKey {
            // The engine's model-facing context is dropped, but the stored
            // transcript is not: it is already partitioned by user and
            // household, so switching back should show that conversation
            // again rather than an empty one. `reset()` is what wipes it.
            chat?.cancel()
            chat = nil
            builtFor = nil
        }
        guard chat == nil else { return }

        guard let relayURL else {
            unavailableReason = """
            The assistant needs HeliPad's assistant service, which is not set up yet. \
            Everything else in the app works without it, including offline.
            """
            return
        }
        guard let token = store.assistantSessionToken.nonEmpty else {
            unavailableReason = "This device is not signed in to the assistant service."
            return
        }

        let adapter = AssistantHouseholdAdapter(store: store)
        let configuration = AssistantConfiguration(relayBaseURL: relayURL)
        let engine = AssistantEngine(
            client: RelayLunaClient(configuration: configuration, tokens: StaticTokenProvider(token)),
            router: ToolRouter(query: adapter),
            proposals: ProposalStore(query: adapter, command: adapter),
            query: adapter,
            configuration: configuration
        )

        unavailableReason = nil
        builtFor = sessionKey
        chat = AssistantChatModel(
            engine: engine,
            transcript: transcript,
            session: session(),
            hasSeenDataDisclosure: store.assistantDisclosureAcknowledged,
            // Device-local, so no household save is involved.
            onDisclosureAcknowledged: { [weak store] seen in
                store?.assistantDisclosureAcknowledged = seen
            }
        )
    }

    /// Server-derived identity is what this should be once A01 exists. Until
    /// then it is assembled locally, which is why the relay must not trust it:
    /// the caregiver picker is a preference, not authentication.
    private func session() -> AssistantSession {
        AssistantSession(
            householdID: store.cloudHouseholdID,
            userID: store.currentUser,
            timeZoneIdentifier: store.timeZone == "device" ? TimeZone.current.identifier : store.timeZone,
            today: PlanCore.currentDeviceDate(),
            displayedWeekStart: store.weekStart
        )
    }

    /// Called on sign-out and household change.
    public func reset() {
        chat?.cancel()
        transcript.clearAll()
        chat = nil
        builtFor = nil
        unavailableReason = nil
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

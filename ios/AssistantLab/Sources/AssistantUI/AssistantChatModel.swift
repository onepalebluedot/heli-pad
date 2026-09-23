import Foundation
import SwiftUI
import AssistantKit

/// View state for the assistant sheet (A06).
///
/// Holds the device-local transcript, the in-flight request, and the pending
/// review. Everything it displays came from `AssistantKit` as typed cards; this
/// layer chooses how they look, not what they say.
@MainActor
public final class AssistantChatModel: ObservableObject {
    @Published public private(set) var messages: [ChatMessage] = []
    @Published public private(set) var isWorking = false
    /// Set while a review is on screen, so the confirm button knows its target.
    @Published public private(set) var pendingProposalID: String?
    /// The one-time explanation of what leaves the device.
    @Published public var showsDataDisclosure: Bool

    private let engine: AssistantEngine
    private let transcript: ChatTranscript
    private var session: AssistantSession
    private var task: Task<Void, Never>?
    private let disclosureSeen: (Bool) -> Void
    private let prompts: [String]

    public init(
        engine: AssistantEngine,
        transcript: ChatTranscript,
        session: AssistantSession,
        hasSeenDataDisclosure: Bool,
        suggestedPrompts: [String] = AssistantCopy.suggestedPrompts,
        onDisclosureAcknowledged: @escaping (Bool) -> Void = { _ in }
    ) {
        self.engine = engine
        self.transcript = transcript
        self.session = session
        self.showsDataDisclosure = !hasSeenDataDisclosure
        self.disclosureSeen = onDisclosureAcknowledged
        self.prompts = suggestedPrompts
        self.messages = transcript.messages(for: session)
    }

    public var suggestedPrompts: [String] { prompts }

    /// Whether a message can be sent right now. The draft itself lives in the
    /// view, not here: publishing it from this object meant every keystroke
    /// invalidated the whole transcript and re-laid-out every card, which on a
    /// long conversation reads as the app freezing.
    public var isIdle: Bool { !isWorking }

    public func acknowledgeDisclosure() {
        showsDataDisclosure = false
        disclosureSeen(true)
    }

    /// Called when the app switches household or signs out. Dropping the
    /// visible transcript is not enough on its own \u{2014} the engine's model-facing
    /// context and any pending review go too.
    public func switchSession(to newSession: AssistantSession, signedOut: Bool) {
        cancel()
        if signedOut { transcript.clearAll() }
        session = newSession
        pendingProposalID = nil
        messages = transcript.messages(for: newSession)
        Task { await engine.reset() }
    }

    public func send(_ text: String) {
        let outgoing = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !outgoing.isEmpty, !isWorking else { return }
        // A chat can stay open across midnight. "Today" must not remain the
        // day the assistant was first constructed, or use the phone's zone.
        let date = DateFormatter()
        date.locale = Locale(identifier: "en_US_POSIX")
        date.timeZone = session.timeZone
        date.dateFormat = "yyyy-MM-dd"
        session.today = date.string(from: Date())
        append(ChatMessage(author: .user, date: Date(), text: outgoing))

        // A new question supersedes any review still on screen: confirming it
        // afterwards would apply a decision the user has moved past.
        pendingProposalID = nil
        isWorking = true

        task = Task { [engine, session] in
            let turn = await engine.send(outgoing, in: session)
            // A cancelled task must not post its result: an interrupted
            // response is never shown as a finished answer.
            guard !Task.isCancelled else { return }
            self.finish(turn)
        }
    }

    public func confirmPendingProposal() {
        guard let id = pendingProposalID, !isWorking else { return }
        isWorking = true
        pendingProposalID = nil
        task = Task { [engine, session] in
            let turn = await engine.confirm(proposalID: id, in: session)
            guard !Task.isCancelled else { return }
            self.finish(turn)
        }
    }

    public func cancelPendingProposal() {
        guard let id = pendingProposalID else { return }
        pendingProposalID = nil
        Task { [engine] in await engine.cancelProposal(id) }
        append(ChatMessage(author: .assistant, date: Date(), cards: [
            .summary(SummaryCard(text: "Cancelled. Nothing was saved."))
        ]))
    }

    public func proposedEvent(proposalID: String, eventID: String) async -> AssistantEvent? {
        guard pendingProposalID == proposalID else { return nil }
        return await engine.proposedEvent(proposalID: proposalID, eventID: eventID)
    }

    public func updatePendingProposalEvent(
        proposalID: String,
        event: AssistantEvent
    ) async throws {
        guard pendingProposalID == proposalID,
              let currentCard = proposalCard(id: proposalID) else {
            throw ProposalEditError.unavailable
        }

        let updatedCard = try await engine.updateProposedEvent(
            proposalID: proposalID,
            event: event,
            card: currentCard,
            in: session
        )

        guard pendingProposalID == proposalID else { throw ProposalEditError.unavailable }
        for messageIndex in messages.indices {
            guard let cardIndex = messages[messageIndex].cards.firstIndex(where: {
                guard case .proposal(let card) = $0 else { return false }
                return card.proposalID == proposalID
            }) else { continue }

            messages[messageIndex].cards[cardIndex] = .proposal(updatedCard)
            transcript.replace(messages[messageIndex], for: session)
            return
        }
        throw ProposalEditError.unavailable
    }

    public func cancel() {
        task?.cancel()
        task = nil
        if isWorking {
            isWorking = false
            append(ChatMessage(author: .assistant, date: Date(), cards: [
                .failure(AssistantCopy.failure(.cancelled))
            ]))
        }
    }

    public func clearConversation() {
        cancel()
        transcript.clear(for: session)
        messages = []
        pendingProposalID = nil
        Task { await engine.reset() }
    }

    private func finish(_ turn: AssistantTurn) {
        isWorking = false
        task = nil
        pendingProposalID = turn.pendingProposalID
        append(ChatMessage(author: .assistant, date: Date(), cards: turn.cards))
    }

    private func proposalCard(id: String) -> ProposalCard? {
        for message in messages {
            for card in message.cards {
                if case .proposal(let proposal) = card, proposal.proposalID == id {
                    return proposal
                }
            }
        }
        return nil
    }

    private func append(_ message: ChatMessage) {
        transcript.append(message, for: session)
        messages.append(message)
    }
}

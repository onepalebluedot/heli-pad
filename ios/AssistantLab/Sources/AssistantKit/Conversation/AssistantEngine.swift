import Foundation

/// One completed assistant turn: what to show, and what it left pending.
public struct AssistantTurn: Sendable {
    public var cards: [AssistantCard]
    /// Set when this turn produced a review awaiting confirmation.
    public var pendingProposalID: String?
    /// Operations that actually ran, for the debug view and the tests.
    public var executedTools: [ToolName]
    /// Calls refused before execution, with the developer-facing reason.
    public var rejections: [String]

    public init(cards: [AssistantCard], pendingProposalID: String? = nil, executedTools: [ToolName] = [], rejections: [String] = []) {
        self.cards = cards
        self.pendingProposalID = pendingProposalID
        self.executedTools = executedTools
        self.rejections = rejections
    }
}

/// Runs a user message through the model and the allowlisted operations, and
/// turns the outcome into cards.
///
/// The engine owns the budget: how many model rounds, how many refused calls
/// before giving up, and what happens when the model answers without having
/// looked anything up.
public actor AssistantEngine {
    /// How many refused calls are tolerated before the turn is abandoned. One
    /// correction is reasonable; a third is a loop.
    private static let rejectionBudget = 2
    /// Model-facing history kept per turn sequence. Older turns are dropped so
    /// context stays bounded (A02).
    private static let itemBudget = 40
    /// Longest message accepted from the composer.
    public static let maxUserMessageLength = 500

    private let client: LunaClient
    private let router: ToolRouter
    private let proposals: ProposalStore
    private let query: HouseholdQueryPort
    private let configuration: AssistantConfiguration
    private let now: @Sendable () -> Date

    private var items: [ConversationItem] = []
    private var itemsKey: String?

    public init(
        client: LunaClient,
        router: ToolRouter,
        proposals: ProposalStore,
        query: HouseholdQueryPort,
        configuration: AssistantConfiguration,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.client = client
        self.router = router
        self.proposals = proposals
        self.query = query
        self.configuration = configuration
        self.now = now
    }

    /// Drops model-facing history. Called on sign-out and household change so
    /// no part of another family's schedule can travel into the next request.
    public func reset() {
        items.removeAll()
        itemsKey = nil
    }

    public func send(_ rawMessage: String, in session: AssistantSession) async -> AssistantTurn {
        // Household change invalidates the running context, whatever the UI did.
        let key = ChatTranscript.key(for: session)
        if itemsKey != key {
            items.removeAll()
            itemsKey = key
            await proposals.clear()
        }

        let message = String(rawMessage.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxUserMessageLength))
        guard !message.isEmpty else {
            return AssistantTurn(cards: [.refusal(AssistantCopy.refusal(.outOfScope))])
        }

        let planning: PlanningContext
        do {
            planning = try await query.planningContext(in: session)
        } catch {
            return AssistantTurn(cards: [.failure(AssistantCopy.failure(.serviceError))])
        }

        items.append(.userMessage(message))
        trimItems()

        var executed: [ToolName] = []
        var rejections: [String] = []
        var collectedCards: [AssistantCard] = []
        var evidence: [String] = []
        var latestSlots = AssistantCopy.ResultSlots()
        var pendingProposalID: String?

        for _ in 0..<configuration.maxToolRounds {
            if Task.isCancelled {
                return AssistantTurn(cards: [.failure(AssistantCopy.failure(.cancelled))], executedTools: executed, rejections: rejections)
            }

            let request = LunaRequest(
                instructions: Instructions.text(for: session, planning: planning),
                items: items,
                maxOutputTokens: configuration.maxOutputTokens
            )

            let reply: LunaReply
            do {
                reply = try await client.send(request)
            } catch let error as LunaError {
                return AssistantTurn(
                    cards: [.failure(AssistantCopy.failure(error.failureReason))],
                    executedTools: executed,
                    rejections: rejections
                )
            } catch is CancellationError {
                return AssistantTurn(cards: [.failure(AssistantCopy.failure(.cancelled))], executedTools: executed, rejections: rejections)
            } catch {
                return AssistantTurn(cards: [.failure(AssistantCopy.failure(.serviceError))], executedTools: executed, rejections: rejections)
            }

            switch reply {
            case .toolCalls(let calls):
                for call in calls {
                    items.append(.toolCall(call))
                    do {
                        let validated = try ToolArgumentParser.validate(call)
                        let outcome = try await router.run(validated, in: session)
                        executed.append(validated.name)
                        collectedCards.append(contentsOf: outcome.cards)
                        latestSlots = outcome.slots
                        if let proposal = outcome.proposal {
                            await proposals.store(proposal)
                            pendingProposalID = proposal.id
                        }
                        evidence.append(outcome.modelPayload)
                        items.append(.toolResult(callID: call.callID, payload: outcome.modelPayload))
                    } catch let rejection as ToolRejection {
                        rejections.append(rejection.developerDescription)
                        // The model is told it was refused and why, in app words,
                        // so it can pick a legitimate call instead of repeating.
                        items.append(.toolRejected(callID: call.callID, reason: rejection.developerDescription))
                    } catch {
                        rejections.append("operation failed")
                        items.append(.toolRejected(callID: call.callID, reason: "operation failed"))
                    }
                }
                trimItems()

                if rejections.count > Self.rejectionBudget {
                    return AssistantTurn(
                        cards: [.failure(AssistantCopy.failure(.toolRejected))],
                        executedTools: executed,
                        rejections: rejections
                    )
                }

            case .final(let decision):
                items.append(.assistantDecision(encode(decision)))
                trimItems()
                let cards = await render(
                    decision,
                    collected: collectedCards,
                    slots: latestSlots,
                    executed: executed,
                    evidence: evidence,
                    session: session
                )
                return AssistantTurn(
                    cards: cards,
                    pendingProposalID: cards.contains(where: isProposalCard) ? pendingProposalID : nil,
                    executedTools: executed,
                    rejections: rejections
                )
            }
        }

        return AssistantTurn(
            cards: [.failure(AssistantCopy.failure(.roundLimit))],
            executedTools: executed,
            rejections: rejections
        )
    }

    // MARK: - Confirmation

    /// Applies a review. This is reached from a button, never from a tool: the
    /// model has no way to call it (A04).
    public func confirm(proposalID: String, in session: AssistantSession) async -> AssistantTurn {
        guard let proposal = await proposals.proposal(proposalID) else {
            // Either already applied, cancelled, or expired and swept.
            return AssistantTurn(cards: [.failure(AssistantCopy.failure(.proposalExpired))])
        }

        do {
            let receipt = try await proposals.confirm(proposalID, in: session)
            let rows = try await receiptRows(for: proposal, receipt: receipt, session: session)
            let headline: String
            switch proposal.kind {
            case .createEvents:
                let n = receipt.createdEventIDs.count
                headline = "Added \(n) event\(n == 1 ? "" : "s")"
            case .assignTasks:
                let n = receipt.updatedEventIDs.count
                headline = "Assigned \(n) event\(n == 1 ? "" : "s")"
            }
            let card = ReceiptCard(
                headline: headline,
                detail: proposal.ruleDescription ?? "",
                syncLabel: AssistantCopy.syncLabel(receipt.syncState),
                externalCalendarLabel: AssistantCopy.externalCalendarLabel(exported: receipt.exportedToExternalCalendar),
                rows: rows
            )
            return AssistantTurn(cards: [.receipt(card)])
        } catch let error as ConfirmationError {
            switch error {
            case .expired, .unknownProposal:
                return AssistantTurn(cards: [.failure(AssistantCopy.failure(.proposalExpired))])
            case .stale, .deleted:
                return AssistantTurn(cards: [.failure(AssistantCopy.failure(.proposalStale))])
            case .wrongHousehold:
                return AssistantTurn(cards: [.failure(AssistantCopy.failure(.proposalExpired))])
            case .saveFailed:
                return AssistantTurn(cards: [.failure(AssistantCopy.failure(.saveFailed))])
            }
        } catch {
            return AssistantTurn(cards: [.failure(AssistantCopy.failure(.saveFailed))])
        }
    }

    public func cancelProposal(_ id: String) async {
        await proposals.cancel(id)
    }

    // MARK: - Rendering

    /// Turns the model's decision into cards, refusing anything it cannot back
    /// with app data.
    private func render(
        _ decision: FinalDecision,
        collected: [AssistantCard],
        slots: AssistantCopy.ResultSlots,
        executed: [ToolName],
        evidence: [String],
        session: AssistantSession
    ) async -> [AssistantCard] {
        switch decision.outcome {
        case .converse:
            // No operation ran, so the message may not carry a figure. That
            // keeps small talk from turning into an unchecked claim about the
            // schedule.
            guard case .accepted(let text) = ProseValidator.validate(decision.message, evidence: []) else {
                return [.refusal(AssistantCopy.refusal(.outOfScope))]
            }
            return [.summary(SummaryCard(text: text))]

        case .result:
            // A result with no operation behind it would be the model answering
            // from its own knowledge. There is nothing to render, so it is
            // refused rather than paraphrased.
            guard !executed.isEmpty, !collected.isEmpty, let template = decision.resultTemplate else {
                return [.refusal(AssistantCopy.refusal(.generalKnowledge))]
            }
            // The template has to match what actually happened. A model that
            // claims "found events" after only reading help does not get to.
            // The model's own wording when it holds up, the app's sentence
            // when it does not. Either way the cards below are unchanged, so
            // the authoritative numbers are always on screen.
            let narration = ProseValidator.validate(decision.message, evidence: evidence).text
                ?? (templateMatches(template, cards: collected)
                    ? AssistantCopy.text(for: template, slots: slots)
                    : nil)

            guard let narration else { return collected }
            return [.summary(SummaryCard(text: narration))] + collected

        case .clarify:
            guard let kind = decision.clarificationKind else {
                return [.failure(AssistantCopy.failure(.invalidModelResponse))]
            }
            var card = await clarification(kind, decision: decision, session: session)
            // A question in the model's own words reads far better than the
            // stock one, so long as it invents no figures.
            if case .accepted(let text) = ProseValidator.validate(decision.message, evidence: evidence) {
                card.question = text
            }
            return collected + [.clarification(card)]

        case .refuse:
            var card = AssistantCopy.refusal(decision.refusalReason ?? .outOfScope)
            // A refusal that sounds like a person still refuses. The list of
            // what it can do stays app-owned.
            if case .accepted(let text) = ProseValidator.validate(decision.message, evidence: []) {
                card.text = text
            }
            return [.refusal(card)]
        }
    }

    private func clarification(
        _ kind: AssistantCopy.ClarificationKind,
        decision: FinalDecision,
        session: AssistantSession
    ) async -> ClarificationCard {
        var options: [ClarificationCard.Option] = []

        switch kind {
        case .missingSeriesBound:
            options = AssistantCopy.seriesBoundOptions

        case .ambiguousPerson:
            // Only ids this household actually contains become buttons, so a
            // borrowed or invented id produces no option rather than a name.
            let people = (try? await query.people(in: session)) ?? []
            for id in decision.candidatePersonIDs {
                guard let person = people.first(where: { $0.id == id }) else { continue }
                options.append(.init(id: person.id, label: person.name, reply: "I mean \(person.name)."))
            }

        case .ambiguousDate:
            for date in decision.candidateDates where CalendarMath.isValidDate(date) {
                options.append(.init(id: date, label: CalendarMath.shortLabel(date), reply: "I mean \(date)."))
            }

        case .missingTime, .ambiguousPlace, .ambiguousEvent:
            options = []
        }

        return ClarificationCard(question: AssistantCopy.clarificationQuestion(kind), options: options)
    }

    private func templateMatches(_ template: AssistantCopy.ResultTemplate, cards: [AssistantCard]) -> Bool {
        switch template {
        case .foundEvents, .foundNoEvents:
            return cards.contains { if case .eventList = $0 { return true }; return false }
        case .reviewReady, .reviewReadyWithConflicts:
            return cards.contains(where: isProposalCard)
        case .trendsReady:
            return cards.contains { if case .trends = $0 { return true }; return false }
        case .peopleListed:
            return cards.contains { if case .people = $0 { return true }; return false }
        case .placesListed:
            return cards.contains { if case .places = $0 { return true }; return false }
        case .helpShown:
            return cards.contains { if case .help = $0 { return true }; return false }
        }
    }

    private func isProposalCard(_ card: AssistantCard) -> Bool {
        if case .proposal = card { return true }
        return false
    }

    private func receiptRows(
        for proposal: Proposal,
        receipt: MutationReceipt,
        session: AssistantSession
    ) async throws -> [EventRow] {
        let touched = Set(receipt.createdEventIDs + receipt.updatedEventIDs)
        let live = (try? await query.events(in: session)) ?? []
        return live
            .filter { touched.contains($0.id) }
            .sorted { $0.date == $1.date ? $0.time < $1.time : $0.date < $1.date }
            .prefix(ToolRouter.displayRowCap)
            .map {
                EventRow(
                    eventID: $0.id,
                    date: $0.date,
                    time: $0.time,
                    endTime: $0.endTime,
                    title: $0.title,
                    ownerLabel: $0.isUnassigned ? "Needs a driver" : $0.owner,
                    isUnassigned: $0.isUnassigned,
                    locationName: $0.location,
                    category: $0.kind.category,
                    isPast: $0.date < session.today
                )
            }
    }

    private func trimItems() {
        if items.count > Self.itemBudget {
            items.removeFirst(items.count - Self.itemBudget)
        }
    }

    private func encode(_ decision: FinalDecision) -> String {
        let object: [String: Any] = [
            "outcome": decision.outcome.rawValue,
            "result_template": decision.resultTemplate?.rawValue as Any,
            "clarification_kind": decision.clarificationKind?.rawValue as Any,
            "candidate_person_ids": decision.candidatePersonIDs,
            "candidate_dates": decision.candidateDates,
            "refusal_reason": decision.refusalReason?.rawValue as Any
        ]
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

import Foundation

public enum ConfirmationError: Error, Equatable, Sendable {
    case unknownProposal(String)
    case expired(String)
    case wrongHousehold
    /// Records moved since the review was built; rebuild it rather than
    /// overwriting newer work.
    case stale(eventIDs: [String])
    case deleted(eventIDs: [String])
    case saveFailed(reason: String)
}

/// Holds reviews awaiting a decision, and makes confirming one idempotent.
///
/// An actor because confirmation can be triggered twice — an impatient second
/// tap, or a retry after a network error the user never saw. Both must land on
/// one set of records (A04).
public actor ProposalStore {
    /// How long a review stays applicable. Long enough to read a 30-week list,
    /// short enough that the schedule underneath is unlikely to have moved.
    public static let lifetime: TimeInterval = 10 * 60

    private let query: HouseholdQueryPort
    private let command: HouseholdCommandPort
    private let now: @Sendable () -> Date

    private var pending: [String: Proposal] = [:]
    /// Receipts for proposals already applied, so a repeat confirmation returns
    /// the first outcome instead of creating a second set of events.
    private var applied: [String: MutationReceipt] = [:]
    /// Applied proposals are kept alongside their receipt. Without this a
    /// second confirmation would find nothing pending and be reported as
    /// expired - telling the user their change did not happen when it did.
    private var archive: [String: Proposal] = [:]
    /// Proposals with a confirmation in flight, so two taps cannot both reach
    /// the command port.
    private var inFlight: Set<String> = []

    public init(
        query: HouseholdQueryPort,
        command: HouseholdCommandPort,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.query = query
        self.command = command
        self.now = now
    }

    public func store(_ proposal: Proposal) {
        pending[proposal.id] = proposal
    }

    public func proposal(_ id: String) -> Proposal? {
        pending[id] ?? archive[id]
    }

    /// Cancel is a no-op on household data by construction: the proposal is
    /// dropped and nothing was ever written.
    public func cancel(_ id: String) {
        pending.removeValue(forKey: id)
    }

    /// Invalidates every pending review. Called on sign-out and household
    /// switch so a review cannot be applied to the wrong family.
    public func clear() {
        pending.removeAll()
        applied.removeAll()
        archive.removeAll()
        inFlight.removeAll()
    }

    public func confirm(_ id: String, in session: AssistantSession) async throws -> MutationReceipt {
        if let receipt = applied[id] { return receipt }

        guard let proposal = pending[id] else {
            throw ConfirmationError.unknownProposal(id)
        }
        guard proposal.householdID == session.householdID else {
            throw ConfirmationError.wrongHousehold
        }
        guard !proposal.isExpired(at: now()) else {
            pending.removeValue(forKey: id)
            throw ConfirmationError.expired(id)
        }
        guard !inFlight.contains(id) else {
            // A second tap while the first is still working. Returning the
            // stale-free path would be a lie, so this is refused explicitly.
            throw ConfirmationError.saveFailed(reason: "already saving")
        }

        // Revalidate against live data. The review may have been built minutes
        // ago against records another device has since changed.
        let live = try await query.events(in: session)
        let byID = Dictionary(uniqueKeysWithValues: live.map { ($0.id, $0) })

        var missing: [String] = []
        var moved: [String] = []
        for (eventID, expected) in proposal.sourceRevisions {
            guard let current = byID[eventID] else { missing.append(eventID); continue }
            if current.revision != expected { moved.append(eventID) }
        }
        if !missing.isEmpty {
            pending.removeValue(forKey: id)
            throw ConfirmationError.deleted(eventIDs: missing.sorted())
        }
        if !moved.isEmpty {
            pending.removeValue(forKey: id)
            throw ConfirmationError.stale(eventIDs: moved.sorted())
        }

        inFlight.insert(id)
        defer { inFlight.remove(id) }

        do {
            let receipt = try await command.apply(proposal.batch, in: session)
            applied[id] = receipt
            archive[id] = proposal
            pending.removeValue(forKey: id)
            return receipt
        } catch let error as MutationError {
            switch error {
            case .staleRevision(let ids):
                pending.removeValue(forKey: id)
                throw ConfirmationError.stale(eventIDs: ids)
            case .recordDeleted(let ids):
                pending.removeValue(forKey: id)
                throw ConfirmationError.deleted(eventIDs: ids)
            case .notPermitted(let reason):
                throw ConfirmationError.saveFailed(reason: reason)
            case .transportFailed(let reason):
                // The proposal stays pending: the user can retry, and the
                // receipt cache still prevents a double write if the first
                // attempt actually landed.
                throw ConfirmationError.saveFailed(reason: reason)
            }
        }
    }
}

import Foundation
import AssistantKit

/// In-memory stand-in for the app, so section C can be exercised end to end
/// before any of it is wired into HeliPad.
///
/// It deliberately reproduces the behaviours the real adapter must have and
/// that the assistant has to cope with: household scoping, revision bumps on
/// write, and a distinction between a local save and a synced one. It is not a
/// simulation of the app's storage \u{2014} at integration time this class is
/// replaced by an adapter over `AppStore`, and the ports stay the same.
public final class MockHousehold: HouseholdQueryPort, HouseholdCommandPort, @unchecked Sendable {
    private let lock = NSLock()

    /// Keyed by household id, so a test can prove that one family's session
    /// cannot read another's rows.
    private var events: [String: [AssistantEvent]]
    private var people: [String: [AssistantPerson]]
    private var places: [String: [AssistantPlace]]
    private var planning: [String: PlanningContext]

    /// Set to make the next write fail, for the offline and retry cases.
    public var nextWriteError: MutationError?
    /// When false, writes report "saved on this device, sync pending".
    public var cloudReachable: Bool = true
    /// Counts applied batches so a test can prove a duplicate confirmation did
    /// not reach the store twice.
    public private(set) var applyCount = 0

    public init(
        events: [String: [AssistantEvent]],
        people: [String: [AssistantPerson]],
        places: [String: [AssistantPlace]],
        planning: [String: PlanningContext]
    ) {
        self.events = events
        self.people = people
        self.places = places
        self.planning = planning
    }

    // MARK: - Queries

    public func events(in session: AssistantSession) async throws -> [AssistantEvent] {
        lock.withLock { events[session.householdID] ?? [] }
    }

    public func people(in session: AssistantSession) async throws -> [AssistantPerson] {
        lock.withLock { people[session.householdID] ?? [] }
    }

    public func places(in session: AssistantSession) async throws -> [AssistantPlace] {
        lock.withLock { places[session.householdID] ?? [] }
    }

    public func planningContext(in session: AssistantSession) async throws -> PlanningContext {
        lock.withLock { planning[session.householdID] ?? PlanningContext() }
    }

    // MARK: - Commands

    public func apply(_ batch: MutationBatch, in session: AssistantSession) async throws -> MutationReceipt {
        try lock.withLock {
        if let error = nextWriteError {
            nextWriteError = nil
            throw error
        }

        var current = events[session.householdID] ?? []

        // Revisions are rechecked here as well as in the proposal store: the
        // real save pipeline is the last place that can see a concurrent edit,
        // and it must refuse rather than clobber.
        var stale: [String] = []
        var missing: [String] = []
        for change in batch.reassignments {
            guard let index = current.firstIndex(where: { $0.id == change.eventID }) else {
                missing.append(change.eventID)
                continue
            }
            if current[index].revision != change.expectedRevision { stale.append(change.eventID) }
        }
        if !missing.isEmpty { throw MutationError.recordDeleted(eventIDs: missing.sorted()) }
        if !stale.isEmpty { throw MutationError.staleRevision(eventIDs: stale.sorted()) }

        var created: [String] = []
        for event in batch.creates {
            // Ids come from the proposal, so replaying the same batch overwrites
            // rather than duplicating.
            if let index = current.firstIndex(where: { $0.id == event.id }) {
                current[index] = event
            } else {
                current.append(event)
                created.append(event.id)
            }
        }

        var updated: [String] = []
        for change in batch.reassignments {
            guard let index = current.firstIndex(where: { $0.id == change.eventID }) else { continue }
            current[index].owner = change.newOwner
            current[index].revision += 1
            updated.append(change.eventID)
        }

        events[session.householdID] = current.sorted {
            $0.date == $1.date ? ($0.time == $1.time ? $0.id < $1.id : $0.time < $1.time) : $0.date < $1.date
        }
        applyCount += 1

        return MutationReceipt(
            createdEventIDs: created,
            updatedEventIDs: updated,
            syncState: cloudReachable ? .syncedToHousehold : .savedLocallySyncPending,
            // Nothing here talks to Google or Apple Calendar, and saying
            // otherwise is exactly the failure A04 warns about.
            exportedToExternalCalendar: false
        )
        }
    }

    // MARK: - Test affordances

    /// Simulates the other phone editing a record between review and confirm.
    public func bumpRevision(eventID: String, household: String) {
        lock.lock(); defer { lock.unlock() }
        guard var rows = events[household], let index = rows.firstIndex(where: { $0.id == eventID }) else { return }
        rows[index].revision += 1
        events[household] = rows
    }

    public func delete(eventID: String, household: String) {
        lock.lock(); defer { lock.unlock() }
        events[household]?.removeAll { $0.id == eventID }
    }

    public func snapshot(household: String) -> [AssistantEvent] {
        lock.lock(); defer { lock.unlock() }
        return events[household] ?? []
    }
}

import Foundation

/// Read side of the app. The production adapter wraps the same `AppStore`
/// queries the manual UI uses; it must apply household scoping itself rather
/// than trusting any identifier that reached it through the model.
public protocol HouseholdQueryPort: AnyObject, Sendable {
    /// Every stored event, past and future, for the authenticated household.
    /// Implementations return app-local state; they do not fan out to external
    /// calendars.
    func events(in session: AssistantSession) async throws -> [AssistantEvent]
    func people(in session: AssistantSession) async throws -> [AssistantPerson]
    func places(in session: AssistantSession) async throws -> [AssistantPlace]
    /// Planning constants the assistant must not re-derive: travel buffer and
    /// the protected dinner window.
    func planningContext(in session: AssistantSession) async throws -> PlanningContext
}

public struct PlanningContext: Codable, Hashable, Sendable {
    public var bufferMinutes: Int
    public var dinnerProtection: Bool
    public var dinnerTime: String
    public var homeName: String

    public init(bufferMinutes: Int = 12, dinnerProtection: Bool = true, dinnerTime: String = "18:30", homeName: String = "Home") {
        self.bufferMinutes = bufferMinutes
        self.dinnerProtection = dinnerProtection
        self.dinnerTime = dinnerTime
        self.homeName = homeName
    }
}

/// Write side. A04 requires that chat and manual edits land through one path,
/// so the production adapter must call the app's existing save/merge pipeline
/// rather than writing storage directly.
public protocol HouseholdCommandPort: AnyObject, Sendable {
    /// Applies an already-confirmed, already-validated batch.
    ///
    /// - Throws: `MutationError.staleRevision` when any touched record moved on
    ///   since the proposal was built. The caller turns that into a refreshed
    ///   review rather than overwriting newer work.
    func apply(_ batch: MutationBatch, in session: AssistantSession) async throws -> MutationReceipt
}

/// A confirmed unit of work. Built by app code from a `Proposal`; the model
/// never constructs one.
public struct MutationBatch: Codable, Hashable, Sendable {
    public var creates: [AssistantEvent]
    /// Event id -> new owner display name, paired with the revision the
    /// proposal was computed against.
    public var reassignments: [Reassignment]

    public struct Reassignment: Codable, Hashable, Sendable {
        public var eventID: String
        public var newOwner: String
        public var expectedRevision: Int

        public init(eventID: String, newOwner: String, expectedRevision: Int) {
            self.eventID = eventID
            self.newOwner = newOwner
            self.expectedRevision = expectedRevision
        }
    }

    public init(creates: [AssistantEvent] = [], reassignments: [Reassignment] = []) {
        self.creates = creates
        self.reassignments = reassignments
    }

    public var isEmpty: Bool { creates.isEmpty && reassignments.isEmpty }
}

/// What actually happened, so the UI can tell "saved on this device / sync
/// pending" from "synced" instead of announcing success optimistically.
public struct MutationReceipt: Codable, Hashable, Sendable {
    public enum SyncState: String, Codable, Sendable {
        case syncedToHousehold
        case savedLocallySyncPending
    }

    public var createdEventIDs: [String]
    public var updatedEventIDs: [String]
    public var syncState: SyncState
    /// True only when an authorised external calendar export succeeded. App-local
    /// creation leaves this false; `gcal == true` on a record is not evidence.
    public var exportedToExternalCalendar: Bool

    public init(
        createdEventIDs: [String],
        updatedEventIDs: [String],
        syncState: SyncState,
        exportedToExternalCalendar: Bool = false
    ) {
        self.createdEventIDs = createdEventIDs
        self.updatedEventIDs = updatedEventIDs
        self.syncState = syncState
        self.exportedToExternalCalendar = exportedToExternalCalendar
    }
}

public enum MutationError: Error, Equatable, Sendable {
    /// A record changed underneath the proposal. Carries the ids that moved.
    case staleRevision(eventIDs: [String])
    /// The record is gone. The review has to be rebuilt, not replayed.
    case recordDeleted(eventIDs: [String])
    case notPermitted(reason: String)
    case transportFailed(reason: String)
}

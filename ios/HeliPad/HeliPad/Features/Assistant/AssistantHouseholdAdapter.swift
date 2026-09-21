import Foundation
import AssistantKit
import MapKit

/// Bridges `AssistantKit`'s ports onto `AppStore`.
///
/// This is the whole integration surface. The assistant has no other way to
/// reach the app: household queries, Apple Maps search, and confirmed writes
/// all pass through this adapter.
///
/// A04 requires that chat and manual edits travel the same path, so the writes
/// here call `AppStore.saveEvent(draft:recurrence:)` and
/// `AppStore.assignEvents(_:)` - the same entry points the Go editor and the
/// Plan assign sheet use. Nothing here touches `partitionRecords`, `persist`
/// or the sync pipeline directly.
@MainActor
public final class AssistantHouseholdAdapter: HouseholdQueryPort, HouseholdCommandPort {
    private let store: AppStore

    public init(store: AppStore) {
        self.store = store
    }

    // MARK: - Queries

    public nonisolated func events(in session: AssistantSession) async throws -> [AssistantEvent] {
        await MainActor.run {
            let placeIDs = Self.placeIDLookup(store.locations)
            return store.records().map { Self.toAssistant($0, placeIDs: placeIDs) }
        }
    }

    public nonisolated func people(in session: AssistantSession) async throws -> [AssistantPerson] {
        await MainActor.run {
            store.people.map { person in
                AssistantPerson(
                    id: person.id,
                    name: person.name,
                    role: person.kind == "caregiver" ? .caregiver : .child,
                    relationship: person.relationship
                )
            }
        }
    }

    public nonisolated func places(in session: AssistantSession) async throws -> [AssistantPlace] {
        await MainActor.run {
            let options = store.planningOptions()
            var out = store.locations.map {
                AssistantPlace(name: $0.name, isVerified: options.verifiedPlaces.contains($0.name))
            }
            // Home is a place the assistant can schedule at even when it is not
            // in the saved list.
            let home = store.home()
            if !out.contains(where: { $0.name == home }) {
                out.insert(AssistantPlace(name: home, isVerified: true), at: 0)
            }
            return out
        }
    }

    public nonisolated func planningContext(in session: AssistantSession) async throws -> PlanningContext {
        await MainActor.run {
            let options = store.planningOptions()
            // The dinner window the planner is actually using this week, so a
            // conflict the assistant reports matches one the planner reports.
            let monday = PlanCore.monday(session.today)
            let dinner = options.priorities[monday]?.time ?? "18:30"
            return PlanningContext(
                bufferMinutes: options.buffer,
                dinnerProtection: options.dinnerProtection,
                dinnerTime: dinner,
                homeName: store.home()
            )
        }
    }

    // MARK: - Commands

    public nonisolated func householdLists(in session: AssistantSession) async throws -> [AssistantHouseholdList] {
        try await MainActor.run { try validateListSession(session) }
        // Refresh when possible, but retain an honestly labelled local snapshot
        // if offline. List reading must never erase pending changes.
        await store.lists.sync()
        return try await MainActor.run {
            try validateListSession(session)
            return ListKind.allCases.compactMap { kind in
                guard let list = store.lists.defaultList(kind),
                      let assistantKind = AssistantListKind(rawValue: kind.rawValue) else { return nil }
                let groups = store.lists.groups(of: list.id)
                return AssistantHouseholdList(kind: assistantKind, sections: groups.map(\.name), items: groups.flatMap { group in
                    store.lists.items(of: list.id, inGroup: group.id).map {
                        AssistantListItem(id: $0.id, text: $0.text, quantity: $0.quantity, section: group.name, isCompleted: $0.isCompleted)
                    }
                }, syncLabel: store.lists.syncState.label)
            }
        }
    }

    private func validateListSession(_ session: AssistantSession) throws {
        guard session.householdID == store.cloudHouseholdID,
              session.householdID == store.lists.archive.householdID,
              !store.lists.recoveryNeeded else {
            throw MutationError.notPermitted(reason: "This household's lists are unavailable. Reopen the assistant for the current household.")
        }
    }

    public func searchLocations(query: String, in session: AssistantSession) async throws -> [AssistantLocation] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = [.address, .pointOfInterest]
        let response = try await MKLocalSearch(request: request).start()
        return response.mapItems.prefix(5).map { item in
            AssistantLocation(
                name: item.name ?? query,
                address: item.placemark.title ?? query,
                latitude: item.placemark.coordinate.latitude,
                longitude: item.placemark.coordinate.longitude
            )
        }
    }

    public nonisolated func apply(_ batch: MutationBatch, in session: AssistantSession) async throws -> MutationReceipt {
        try await MainActor.run {
            guard session.householdID == store.cloudHouseholdID else {
                throw MutationError.notPermitted(reason: "The household changed. Prepare a new review.")
            }
            if let additions = batch.listAdditions, !additions.isEmpty {
                try validateListSession(session)
                guard batch.creates.isEmpty, batch.reassignments.isEmpty else {
                    throw MutationError.notPermitted(reason: "List and calendar changes need separate reviews.")
                }
                let drafts = try additions.map { addition -> ListItemDraft in
                    guard let kind = ListKind(rawValue: addition.kind.rawValue), let list = store.lists.defaultList(kind) else {
                        throw MutationError.notPermitted(reason: "List unavailable.")
                    }
                    let matches = store.lists.groups(of: list.id).filter { $0.name.caseInsensitiveCompare(addition.section) == .orderedSame }
                    guard matches.count == 1, let group = matches.first else {
                        throw MutationError.notPermitted(reason: "The section changed. Prepare a new review.")
                    }
                    return ListItemDraft(id: addition.id, listID: list.id, groupID: group.id, text: addition.text, quantity: addition.quantity)
                }
                let ids: [String]
                do { ids = try store.lists.addItems(drafts) }
                catch { throw MutationError.transportFailed(reason: error.localizedDescription) }
                Task { await store.lists.sync() }
                return MutationReceipt(createdEventIDs: [], updatedEventIDs: [],
                                       syncState: store.lists.syncState == .onDevice ? .savedOnDeviceOnly : .savedLocallySyncPending,
                                       createdListItemIDs: ids)
            }
            var created: [String] = []

            // Creates go through the editor's own entry point, which owns
            // series identity, exceptions, partitioning and save().
            for group in Self.groupedBySeries(batch.creates) {
                guard let first = group.first else { continue }
                let draft = Self.toRecord(first)
                let pattern = Self.pattern(for: group, timeZone: store.timeZone)
                do {
                    let saved = try store.saveEvent(draft: draft, recurrence: pattern)
                    created.append(contentsOf: saved.map(\.id))
                } catch {
                    throw MutationError.transportFailed(reason: error.localizedDescription)
                }
            }

            var updated: [String] = []
            if !batch.reassignments.isEmpty {
                // Revisions are checked before handing over, so a record another
                // device moved is refused here rather than overwritten.
                let live = Dictionary(uniqueKeysWithValues: store.records().map { ($0.id, $0) })
                var missing: [String] = []
                var moved: [String] = []
                for change in batch.reassignments {
                    guard let current = live[change.eventID] else { missing.append(change.eventID); continue }
                    if Self.revision(of: current) != change.expectedRevision { moved.append(change.eventID) }
                }
                if !missing.isEmpty { throw MutationError.recordDeleted(eventIDs: missing.sorted()) }
                if !moved.isEmpty { throw MutationError.staleRevision(eventIDs: moved.sorted()) }

                let assignments = Dictionary(
                    uniqueKeysWithValues: batch.reassignments.map { ($0.eventID, $0.newOwner) }
                )
                do {
                    try store.assignEvents(assignments)
                    updated = assignments.keys.sorted()
                } catch {
                    throw MutationError.notPermitted(reason: error.localizedDescription)
                }
            }

            return MutationReceipt(
                createdEventIDs: created,
                updatedEventIDs: updated,
                // `save()` has run, so it is on this device for certain. Whether
                // the household has it depends on the cloud round trip.
                syncState: store.syncPending ? .savedLocallySyncPending : .syncedToHousehold,
                // Nothing above exports anywhere. `gcal` on a record is not
                // evidence that an export happened.
                exportedToExternalCalendar: false
            )
        }
    }

    // MARK: - Mapping

    /// `RecordStamp.counter` is the app's ordering token, so it is what the
    /// assistant's optimistic-concurrency check compares. A record that has
    /// never been stamped reads as revision 0.
    static func revision(of record: TaskRecord) -> Int {
        record.stamp?.counter ?? 0
    }

    /// Saved-place ids by lowercased place name, so two events at the same
    /// saved place match even when the name was typed differently. Events
    /// themselves carry no place id - only `LocationItem` does - so identity
    /// is resolved through the household's places here.
    static func placeIDLookup(_ locations: [LocationItem]) -> [String: String] {
        var map: [String: String] = [:]
        for location in locations {
            guard let placeID = location.placeId, !placeID.isEmpty else { continue }
            map[location.name.lowercased()] = placeID
        }
        return map
    }

    static func toAssistant(_ record: TaskRecord, placeIDs: [String: String] = [:]) -> AssistantEvent {
        let resolvedLocation: AssistantLocation?
        if let latitude = record.latitude, let longitude = record.longitude {
            resolvedLocation = AssistantLocation(
                name: record.location,
                address: record.formattedAddress ?? record.location,
                latitude: latitude,
                longitude: longitude
            )
        } else {
            resolvedLocation = nil
        }
        return AssistantEvent(
            id: record.id,
            date: record.date,
            time: record.time,
            endTime: record.endTime,
            title: record.title,
            owner: record.owner,
            kids: record.kids,
            location: record.location,
            kind: EventKind(rawValue: record.kind.rawValue) ?? .other,
            done: record.done,
            tentative: record.tentative,
            // Notes are carried so conflict copy can quote an existing event,
            // but `ToolRouter` never puts them in a model payload.
            notes: record.notes,
            seriesId: record.seriesId,
            placeID: placeIDs[record.location.lowercased()],
            calendarID: record.calendarId,
            origin: originFor(record),
            revision: revision(of: record),
            resolvedLocation: resolvedLocation
        )
    }

    /// Flattens the app's provenance for the detector. Legacy records stay nil
    /// rather than being guessed at; the detector judges those on `seriesId`
    /// and `calendarID` instead.
    static func originFor(_ record: TaskRecord) -> AssistantEventOrigin? {
        switch record.origin {
        case .none: return nil
        case .manual: return .manual
        case .shortcut: return .shortcut
        case .recurrence: return .recurrence
        case .calendarImport: return .calendarImport
        case .assistantSingle: return .assistantSingle
        case .onboarding: return .onboarding
        case .legacy: return .legacy
        }
    }

    static func toRecord(_ event: AssistantEvent) -> TaskRecord {
        TaskRecord(
            id: event.id,
            date: event.date,
            time: event.time,
            endTime: event.endTime,
            title: event.title,
            owner: event.owner,
            kids: event.kids,
            location: event.location,
            mode: "Drive",
            kind: TaskKind(rawValue: event.kind.rawValue) ?? .other,
            notes: event.notes,
            seriesId: event.seriesId,
            latitude: event.resolvedLocation?.latitude,
            longitude: event.resolvedLocation?.longitude,
            formattedAddress: event.resolvedLocation?.address,
            // A single confirmed proposal is still the household deciding one
            // occurrence at a time, so it counts as manual effort. A weekly
            // series is re-tagged by `AppStore.saveEvent`.
            origin: event.seriesId == nil ? .assistantSingle : .recurrence(seriesID: event.seriesId)
        )
    }

    /// A proposal carries one series' worth of occurrences, already expanded.
    /// The editor wants the rule instead, so the rule is recovered from the
    /// dates rather than re-expanded here - there must be exactly one
    /// expansion, and it belongs to `PlanCore`.
    static func pattern(for group: [AssistantEvent], timeZone: String) -> RecurrencePattern {
        let dates = group.map(\.date).sorted()
        guard let start = dates.first, dates.count > 1 else {
            return RecurrencePattern(
                mode: .none,
                startDate: dates.first ?? PlanCore.currentDeviceDate(),
                timeZone: timeZone
            )
        }
        let weekdays = Array(Set(dates.map { PlanCore.weekdayIndex($0) })).sorted()
        return RecurrencePattern(
            mode: .weekly,
            startDate: start,
            timeZone: timeZone,
            weekdays: weekdays,
            // Through-date rather than a week count: the proposal's last
            // occurrence is the truth the user just confirmed, and deriving a
            // count could round the series longer than what they reviewed.
            end: .throughDate(dates.last!)
        )
    }

    static func groupedBySeries(_ events: [AssistantEvent]) -> [[AssistantEvent]] {
        var bySeries: [String: [AssistantEvent]] = [:]
        var singles: [[AssistantEvent]] = []
        for event in events {
            if let series = event.seriesId {
                bySeries[series, default: []].append(event)
            } else {
                singles.append([event])
            }
        }
        return singles + bySeries.keys.sorted().map { bySeries[$0]!.sorted { $0.date < $1.date } }
    }
}

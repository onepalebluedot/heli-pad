import Foundation

/// What running one allowlisted operation produced.
public struct ToolOutcome: Sendable {
    /// Compact JSON handed back to the model as the tool result. Bounded in
    /// size and stripped of anything the operation does not need.
    public var modelPayload: String
    /// What the user sees. Built from app data, in parallel with the payload,
    /// so the screen never depends on the model relaying results correctly.
    public var cards: [AssistantCard]
    /// Present for `preview_*` operations. Stored for confirmation.
    public var proposal: Proposal?
    /// Slots for the closing sentence, filled from this result.
    public var slots: AssistantCopy.ResultSlots

    public init(modelPayload: String, cards: [AssistantCard], proposal: Proposal? = nil, slots: AssistantCopy.ResultSlots = .init()) {
        self.modelPayload = modelPayload
        self.cards = cards
        self.proposal = proposal
        self.slots = slots
    }
}

/// Executes validated calls against the household.
///
/// Two things happen here that shape-level validation cannot do: identifiers
/// are checked against the authenticated household's actual data, and every
/// result is capped before it goes anywhere near the model.
public struct ToolRouter: Sendable {
    /// Rows returned to the model. Enough to answer "what's on this week"
    /// without letting one call pull a year of history into context.
    public static let modelRowCap = 40
    /// Rows shown on a card before the count takes over.
    public static let displayRowCap = 60

    private let query: HouseholdQueryPort
    private let now: @Sendable () -> Date

    public init(query: HouseholdQueryPort, now: @escaping @Sendable () -> Date = { Date() }) {
        self.query = query
        self.now = now
    }

    public func run(_ call: ValidatedToolCall, in session: AssistantSession) async throws -> ToolOutcome {
        switch call {
        case .findEvents(let args):
            return try await findEvents(args, session)
        case .getEvent(let eventID):
            return try await getEvent(eventID, session)
        case .listHouseholdPeople(let includeChildren):
            return try await listPeople(includeChildren, session)
        case .listSavedPlaces(let verifiedOnly):
            return try await listPlaces(verifiedOnly, session)
        case .previewCreateEvents(let args):
            return try await previewCreate(args, session)
        case .previewAssignTasks(let eventIDs, let ownerID):
            return try await previewAssign(eventIDs, ownerID, session)
        case .getScheduleTrends(let range, let personIDs):
            return try await trends(range, personIDs, session)
        case .getAppHelp(let topic):
            return help(topic)
        }
    }

    // MARK: - Reads

    private func findEvents(_ args: FindEventsArgs, _ session: AssistantSession) async throws -> ToolOutcome {
        let people = try await query.people(in: session)
        let names = try resolveNames(args.personIDs, in: people)
        let all = try await query.events(in: session)

        let matches = all.filter { event in
            guard args.range.contains(event.date) else { return false }
            if !names.isEmpty {
                let involved = Set(event.kids + [event.owner])
                if involved.isDisjoint(with: names) { return false }
            }
            if !args.categories.isEmpty, !args.categories.contains(event.kind.category) { return false }
            if args.onlyUnassigned, !event.isUnassigned { return false }
            if let needle = args.textContains,
               event.title.range(of: needle, options: .caseInsensitive) == nil { return false }
            return true
        }.sorted(by: chronological)

        let rows = matches.prefix(Self.displayRowCap).map { row(for: $0, today: session.today) }
        let card = EventListCard(
            periodLabel: args.range.label,
            rows: Array(rows),
            omittedCount: max(0, matches.count - rows.count)
        )

        let payload = try json([
            "period": ["start": args.range.start, "end": args.range.end],
            "total_matches": matches.count,
            "returned": min(matches.count, Self.modelRowCap),
            "events": matches.prefix(Self.modelRowCap).map(modelRow)
        ])

        return ToolOutcome(
            modelPayload: payload,
            cards: [.eventList(card)],
            slots: .init(count: matches.count, periodLabel: args.range.label)
        )
    }

    private func getEvent(_ eventID: String, _ session: AssistantSession) async throws -> ToolOutcome {
        let all = try await query.events(in: session)
        guard let event = all.first(where: { $0.id == eventID }) else {
            // An id that is not in this household is refused outright rather
            // than answered with "not found", which would confirm nothing
            // either way but still invite probing.
            throw ToolRejection.unknownEventID(eventID)
        }
        let card = EventListCard(
            periodLabel: CalendarMath.shortLabel(event.date),
            rows: [row(for: event, today: session.today)]
        )
        return ToolOutcome(
            modelPayload: try json(modelRow(event)),
            cards: [.eventList(card)],
            slots: .init(count: 1, periodLabel: CalendarMath.shortLabel(event.date))
        )
    }

    private func listPeople(_ includeChildren: Bool, _ session: AssistantSession) async throws -> ToolOutcome {
        let people = try await query.people(in: session)
        let caregivers = people.filter { $0.role == .caregiver }
        let children = includeChildren ? people.filter { $0.role == .child } : []
        let visible = caregivers + children

        let payload = try json([
            "people": visible.map { [
                "id": $0.id,
                "name": UntrustedText($0.name).forModel(limit: 40),
                "role": $0.role.rawValue,
                "relationship": UntrustedText($0.relationship).forModel(limit: 40)
            ] }
        ])
        return ToolOutcome(
            modelPayload: payload,
            cards: [.people(PeopleCard(caregivers: caregivers, children: children))],
            slots: .init(count: visible.count)
        )
    }

    private func listPlaces(_ verifiedOnly: Bool, _ session: AssistantSession) async throws -> ToolOutcome {
        let places = try await query.places(in: session)
        let visible = verifiedOnly ? places.filter(\.isVerified) : places
        let payload = try json([
            "places": visible.map { [
                "name": UntrustedText($0.name).forModel(limit: 60),
                "locatable": $0.isVerified
            ] as [String: Any] }
        ])
        return ToolOutcome(
            modelPayload: payload,
            cards: [.places(PlacesCard(places: visible))],
            slots: .init(count: visible.count)
        )
    }

    private func trends(_ range: DateRange, _ personIDs: [String], _ session: AssistantSession) async throws -> ToolOutcome {
        let people = try await query.people(in: session)
        let names = try resolveNames(personIDs, in: people)
        let all = try await query.events(in: session)
        let scoped = names.isEmpty ? all : all.filter { !Set($0.kids + [$0.owner]).isDisjoint(with: names) }

        let card = TrendService.report(events: scoped, range: range, people: people, today: session.today)

        // The model gets the same numbers the card shows, so it cannot narrate
        // a different figure than the one on screen.
        let payload = try json([
            "period": card.periodLabel,
            "comparison": card.comparisonLabel,
            "partial_period": card.partialPeriodNote as Any,
            "metrics": card.metrics.map { [
                "id": $0.id,
                "current": $0.currentValue,
                "previous": $0.previousValue,
                "change": describe($0.change)
            ] as [String: Any] },
            "workload": card.workload.map { ["name": $0.name, "events": $0.count] as [String: Any] },
            "category_mix": card.categoryMix.map { ["category": $0.category, "events": $0.count] as [String: Any] }
        ])

        return ToolOutcome(
            modelPayload: payload,
            cards: [.trends(card)],
            slots: .init(count: card.metrics.first?.currentValue ?? 0, periodLabel: card.periodLabel)
        )
    }

    private func help(_ topic: HelpTopic) -> ToolOutcome {
        let card = AssistantCopy.help(topic)
        // The model is told only that the topic was shown. The body is already
        // on screen; echoing it into context would invite paraphrase.
        let payload = (try? json(["topic": topic.rawValue, "shown": true])) ?? "{}"
        return ToolOutcome(modelPayload: payload, cards: [.help(card)], slots: .init(count: 1))
    }

    // MARK: - Previews

    private func previewCreate(_ args: CreateEventsArgs, _ session: AssistantSession) async throws -> ToolOutcome {
        let people = try await query.people(in: session)
        let places = try await query.places(in: session)
        let planning = try await query.planningContext(in: session)

        let childNames = try resolveNames(args.childIDs, in: people, requiring: .child)
        var ownerName = "TBD"
        if let ownerID = args.ownerID {
            guard let person = people.first(where: { $0.id == ownerID }) else {
                throw ToolRejection.unknownPersonID(ownerID)
            }
            guard person.role == .caregiver else { throw ToolRejection.personIsNotCaregiver(ownerID) }
            ownerName = person.name
        }

        var locationName = planning.homeName
        if let requested = args.locationName {
            guard let place = places.first(where: { $0.name.caseInsensitiveCompare(requested) == .orderedSame }) else {
                throw ToolRejection.unknownPlace(requested)
            }
            locationName = place.name
        }

        // Assumptions are collected rather than applied quietly. Each one is a
        // thing the user did not say, so each one has to be readable on the
        // review before they confirm it.
        var assumptions: [String] = []
        if args.durationWasAssumed {
            assumptions.append("No end time was given, so this runs for HeliPad's default \(args.kind.defaultDurationMinutes) minutes, ending \(args.endTime).")
        }
        if args.locationWasAssumed {
            let alternatives = places.filter { $0.name != planning.homeName }
            let suffix = alternatives.isEmpty
                ? ""
                : " Your saved places are \(alternatives.map(\.name).joined(separator: ", "))."
            assumptions.append("No place was named, so this is at \(planning.homeName).\(suffix)")
        }

        let dates: [String]
        do {
            dates = try RecurrenceCore.dates(for: args.rule)
        } catch let error as RecurrenceError {
            throw ToolRejection.recurrence(error)
        }

        // Ids are minted here, once, and carried through confirmation. A retry
        // reuses this proposal and therefore these ids, which is what stops a
        // duplicate confirmation from creating a second series.
        let seriesID = args.rule.mode == .weekly ? "series-\(UUID().uuidString)" : nil
        let proposed = dates.map { date in
            AssistantEvent(
                id: "evt-\(UUID().uuidString)",
                date: date,
                time: args.startTime,
                endTime: args.endTime,
                title: args.title,
                owner: ownerName,
                kids: childNames.sorted(),
                location: locationName,
                kind: args.kind,
                notes: "",
                seriesId: seriesID,
                revision: 1
            )
        }

        let existing = try await query.events(in: session)
        let conflicts = ConflictFinder.conflicts(proposed: proposed, existing: existing, planning: planning)
        let period = DateRange(start: dates.first!, end: dates.last!)!

        let proposal = Proposal(
            kind: .createEvents,
            householdID: session.householdID,
            createdAt: now(),
            expiresAt: now().addingTimeInterval(ProposalStore.lifetime),
            timeZoneIdentifier: session.timeZoneIdentifier,
            batch: MutationBatch(creates: proposed),
            // Pure creates touch no existing record, so there is nothing whose
            // revision could go stale.
            sourceRevisions: [:],
            conflicts: conflicts,
            affectedCount: proposed.count,
            ruleDescription: RecurrenceCore.describe(args.rule)
        )

        let card = ProposalCard(
            proposalID: proposal.id,
            headline: "Create \u{201C}\(args.title)\u{201D}",
            ruleDescription: proposal.ruleDescription,
            affectedCount: proposed.count,
            periodLabel: period.label,
            rows: proposed.prefix(Self.displayRowCap).map { row(for: $0, today: session.today) },
            conflicts: conflicts,
            destinationNote: AssistantCopy.externalCalendarLabel(exported: false),
            assumptions: assumptions,
            expiresAt: proposal.expiresAt
        )

        let payload = try json([
            "proposal_id": proposal.id,
            "kind": "create_events",
            // Reported back so the model does not restate the event as though
            // the user had specified these.
            "app_supplied_defaults": assumptions,
            "end_time": args.endTime,
            "place": locationName,
            "rule": proposal.ruleDescription as Any,
            "occurrence_count": proposed.count,
            "first_date": dates.first!,
            "last_date": dates.last!,
            "assigned_to": ownerName,
            "conflict_count": conflicts.count,
            "saved": false,
            "awaiting": "user_confirmation"
        ])

        return ToolOutcome(
            modelPayload: payload,
            cards: [.proposal(card)],
            proposal: proposal,
            slots: .init(count: proposed.count, periodLabel: period.label, conflictCount: conflicts.count)
        )
    }

    private func previewAssign(_ eventIDs: [String], _ ownerID: String, _ session: AssistantSession) async throws -> ToolOutcome {
        let people = try await query.people(in: session)
        guard let owner = people.first(where: { $0.id == ownerID }) else {
            throw ToolRejection.unknownPersonID(ownerID)
        }
        guard owner.role == .caregiver else { throw ToolRejection.personIsNotCaregiver(ownerID) }

        let all = try await query.events(in: session)
        let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

        var targets: [AssistantEvent] = []
        for id in eventIDs {
            guard let event = byID[id] else { throw ToolRejection.unknownEventID(id) }
            targets.append(event)
        }
        targets.sort(by: chronological)

        let planning = try await query.planningContext(in: session)
        // Conflicts are evaluated for the schedule as it would be, so the
        // review shows what this person is being asked to be in two places for.
        let reassigned = targets.map { event -> AssistantEvent in
            var copy = event
            copy.owner = owner.name
            return copy
        }
        let untouched = all.filter { event in !eventIDs.contains(event.id) }
        let conflicts = ConflictFinder.conflicts(proposed: reassigned, existing: untouched, planning: planning)

        let batch = MutationBatch(reassignments: targets.map {
            .init(eventID: $0.id, newOwner: owner.name, expectedRevision: $0.revision)
        })
        let revisions = Dictionary(uniqueKeysWithValues: targets.map { ($0.id, $0.revision) })
        let period = DateRange(start: targets.first!.date, end: targets.last!.date)!

        let proposal = Proposal(
            kind: .assignTasks,
            householdID: session.householdID,
            createdAt: now(),
            expiresAt: now().addingTimeInterval(ProposalStore.lifetime),
            timeZoneIdentifier: session.timeZoneIdentifier,
            batch: batch,
            sourceRevisions: revisions,
            conflicts: conflicts,
            affectedCount: targets.count
        )

        let card = ProposalCard(
            proposalID: proposal.id,
            headline: "Assign \(targets.count) event\(targets.count == 1 ? "" : "s") to \(owner.name)",
            ruleDescription: nil,
            affectedCount: targets.count,
            periodLabel: period.label,
            rows: reassigned.prefix(Self.displayRowCap).map { row(for: $0, today: session.today) },
            conflicts: conflicts,
            destinationNote: AssistantCopy.externalCalendarLabel(exported: false),
            expiresAt: proposal.expiresAt
        )

        let payload = try json([
            "proposal_id": proposal.id,
            "kind": "assign_tasks",
            "event_count": targets.count,
            "assigned_to": owner.name,
            "first_date": period.start,
            "last_date": period.end,
            "conflict_count": conflicts.count,
            "saved": false,
            "awaiting": "user_confirmation"
        ])

        return ToolOutcome(
            modelPayload: payload,
            cards: [.proposal(card)],
            proposal: proposal,
            slots: .init(count: targets.count, periodLabel: period.label, conflictCount: conflicts.count)
        )
    }

    // MARK: - Helpers

    /// Turns model-supplied person ids into household names, refusing anything
    /// this household does not contain. This is where an invented or borrowed
    /// id from another family stops.
    private func resolveNames(
        _ ids: [String],
        in people: [AssistantPerson],
        requiring role: AssistantPerson.Role? = nil
    ) throws -> Set<String> {
        var names: Set<String> = []
        for id in ids {
            guard let person = people.first(where: { $0.id == id }) else {
                throw ToolRejection.unknownPersonID(id)
            }
            if let role, person.role != role {
                throw role == .child
                    ? ToolRejection.invalidValue(tool: "preview_create_events", field: "child_ids", detail: "'\(id)' is not a child in this household")
                    : ToolRejection.personIsNotCaregiver(id)
            }
            names.insert(person.name)
        }
        return names
    }

    private func chronological(_ a: AssistantEvent, _ b: AssistantEvent) -> Bool {
        if a.date != b.date { return a.date < b.date }
        if a.time != b.time { return a.time < b.time }
        return a.id < b.id
    }

    private func row(for event: AssistantEvent, today: String) -> EventRow {
        EventRow(
            eventID: event.id,
            date: event.date,
            time: event.time,
            endTime: event.endTime,
            title: event.title,
            ownerLabel: event.isUnassigned ? "Needs a driver" : event.owner,
            isUnassigned: event.isUnassigned,
            locationName: event.location,
            category: event.kind.category,
            isPast: event.date < today
        )
    }

    /// The projection sent to the model. Notes, addresses and coordinates are
    /// absent by design (A06 minimisation), and the title goes through
    /// `UntrustedText` so it cannot forge structure in the payload.
    private func modelRow(_ event: AssistantEvent) -> [String: Any] {
        [
            "id": event.id,
            "date": event.date,
            "start": event.time,
            "end": event.endTime,
            "title": UntrustedText(event.title).forModel(),
            "owner": event.isUnassigned ? "unassigned" : UntrustedText(event.owner).forModel(limit: 40),
            "children": event.kids.map { UntrustedText($0).forModel(limit: 40) },
            "place": UntrustedText(event.location).forModel(limit: 60),
            "category": event.kind.category,
            "marked_complete": event.done
        ]
    }

    private func describe(_ change: TrendMetric.Change) -> String {
        switch change {
        case .percent(let pct, let absolute):
            return "\(pct >= 0 ? "+" : "")\(pct)% (\(absolute >= 0 ? "+" : "")\(absolute))"
        case .fromZero(let absolute):
            return "+\(absolute) from a baseline of zero; no percentage"
        case .noBaseline:
            return "no comparable baseline"
        case .insufficientData(let why):
            return "insufficient data: \(why)"
        }
    }

    private func json(_ object: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

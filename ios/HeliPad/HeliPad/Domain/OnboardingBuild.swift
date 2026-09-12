import Foundation

// MARK: - Turning setup answers into a family

public struct OnboardingResult {
    public var people: [Person]
    public var locations: [LocationItem]
    public var routes: [String: [String: Int]]
    public var parentLocations: [String: String]
    public var templates: [TemplateItem]
    public var eventsByDay: [Int: [TaskRecord]]
    public var records: [TaskRecord]
    public var seriesDefinitions: [SeriesDefinition]
    public var homePlaceName: String
    public var homeAddress: String
    public var currentUser: String
}

public extension OnboardingDraft {

    /// Builds the whole household from the answers. Pure — it reads nothing and
    /// writes nothing, so it can be exercised without a store.
    func build(baseWeek: String = AppStore.BASE_WEEK, timeZone: String = "device") -> OnboardingResult {
        let crewNames = caregiverNames
        let kidRoster = kidNames

        let people = buildPeople(crewNames: crewNames, kidRoster: kidRoster)
        let locations = buildLocations()
        let routes = buildRoutes()

        var bases: [String: String] = [:]
        for name in crewNames { bases[name] = homeName }

        let usableActivities = activities.filter { activity in
            !activity.title.trimmingCharacters(in: .whitespaces).isEmpty
        }

        let templates = usableActivities.map { activity in
            template(from: activity, crewNames: crewNames, kidRoster: kidRoster)
        }

        var allRecords: [TaskRecord] = []
        var seriesDefinitions: [SeriesDefinition] = []
        for activity in usableActivities {
            let start = activity.startDate ?? baseWeek
            let seriesId = "onb-\(activity.id)"
            let pattern = recurrencePattern(for: activity, startDate: start, timeZone: timeZone)
            let draft = event(from: activity, date: start, seriesId: seriesId, crewNames: crewNames, kidRoster: kidRoster)
            if let generated = try? PlanCore.occurrences(draft, recurrence: pattern, seriesId: seriesId) {
                allRecords.append(contentsOf: generated)
                if pattern.mode == .weekly {
                    seriesDefinitions.append(SeriesDefinition(seriesId: seriesId, pattern: pattern))
                }
            }
        }
        var eventsByDay: [Int: [TaskRecord]] = [:]
        for event in allRecords {
            if let day = PlanCore.dayOffset(from: baseWeek, to: event.date), (0...6).contains(day) {
                eventsByDay[day, default: []].append(event)
            }
        }
        for day in eventsByDay.keys {
            eventsByDay[day]?.sort { $0.time < $1.time }
        }

        return OnboardingResult(
            people: people,
            locations: locations,
            routes: routes,
            parentLocations: bases,
            templates: templates,
            eventsByDay: eventsByDay,
            records: allRecords,
            seriesDefinitions: seriesDefinitions,
            homePlaceName: homeName,
            homeAddress: homeAddress.trimmingCharacters(in: .whitespaces),
            currentUser: crewNames.first ?? "All"
        )
    }

    // MARK: Roster

    /// The roster alone, without the week. Setup uses it to colour avatars
    /// while the answers are still a draft.
    func previewPeople() -> [Person] {
        return buildPeople(crewNames: caregiverNames, kidRoster: kidNames)
    }

    private func buildPeople(crewNames: [String], kidRoster: [String]) -> [Person] {
        var people: [Person] = []

        // Relationship for each caregiver, keyed by the name they typed.
        var relationships: [String: String] = [trimmedYourName: yourRelationship]
        for member in crew {
            let name = member.name.trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { relationships[name] = member.relationship }
        }

        for (index, name) in crewNames.enumerated() {
            people.append(Person(
                id: "onb-crew-\(index)",
                name: name,
                relationship: relationships[name] ?? "Other",
                kind: "caregiver",
                color: OnboardingDraft.caregiverInks[index % OnboardingDraft.caregiverInks.count],
                baseLocation: homeName
            ))
        }

        for (index, name) in kidRoster.enumerated() {
            people.append(Person(
                id: "onb-kid-\(index)",
                name: name,
                relationship: "Child",
                kind: "child",
                color: OnboardingDraft.childInks[index % OnboardingDraft.childInks.count],
                baseLocation: homeName
            ))
        }

        return people
    }

    // MARK: Places

    private func buildLocations() -> [LocationItem] {
        var locations: [LocationItem] = [
            LocationItem(
                name: homeName,
                address: homeAddress.trimmingCharacters(in: .whitespaces),
                icon: "house",
                routeKey: homeRouteKey ?? homeName,
                source: homeSource ?? "manual",
                latitude: homeLatitude,
                longitude: homeLongitude,
                placeId: homePlaceId
            )
        ]

        let names = placeNames
        for name in names {
            guard let place = places.first(where: {
                $0.name.trimmingCharacters(in: .whitespaces) == name
            }) else { continue }
            locations.append(LocationItem(
                name: name,
                address: place.address.trimmingCharacters(in: .whitespaces),
                icon: place.icon,
                routeKey: place.routeKey ?? name,
                source: place.source ?? "manual",
                latitude: place.latitude,
                longitude: place.longitude,
                placeId: place.placeId
            ))
        }

        return locations
    }

    /// A travel matrix from the one number the household actually knows: how
    /// long it takes to drive there from home. Trips that do not touch home are
    /// estimated from both legs — a placeholder until the routing port lands,
    /// which is why every entry is derived rather than invented per-pair.
    private func buildRoutes() -> [String: [String: Int]] {
        var minutesFromHome: [String: Int] = [homeName: 0]
        for name in placeNames {
            guard let place = places.first(where: {
                $0.name.trimmingCharacters(in: .whitespaces) == name
            }) else { continue }
            minutesFromHome[name] = max(1, place.minutesFromHome)
        }

        var matrix: [String: [String: Int]] = [:]
        for (from, fromMins) in minutesFromHome {
            var row: [String: Int] = [:]
            for (to, toMins) in minutesFromHome {
                if from == to {
                    row[to] = 0
                } else if from == homeName || to == homeName {
                    row[to] = max(fromMins, toMins)
                } else {
                    row[to] = max(1, Int(round(Double(fromMins + toMins) * 0.7)))
                }
            }
            matrix[from] = row
        }
        return matrix
    }

    // MARK: Activities

    private func resolvedOwner(_ owner: String, crewNames: [String]) -> String {
        if owner == "Family" || crewNames.contains(owner) { return owner }
        return "TBD"
    }

    private func resolvedKids(_ names: [String], kidRoster: [String]) -> [String] {
        let picked = names.filter { kidRoster.contains($0) }
        return picked.isEmpty ? kidRoster : picked
    }

    private func resolvedPlace(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return homeName }
        if trimmed == homeName || placeNames.contains(trimmed) { return trimmed }
        return homeName
    }

    private func template(from activity: DraftActivity, crewNames: [String], kidRoster: [String]) -> TemplateItem {
        let kids = resolvedKids(activity.kidNames, kidRoster: kidRoster)
        let place = resolvedPlace(activity.placeName)
        return TemplateItem(
            id: "onb-tpl-\(activity.id)",
            title: activity.title.trimmingCharacters(in: .whitespaces),
            time: activity.time,
            endTime: PlanCore.addMinutes(time: activity.time, mins: activity.durationMinutes),
            kids: kids,
            kid: kids.joined(separator: ", "),
            owner: resolvedOwner(activity.ownerName, crewNames: crewNames),
            location: place,
            mode: place == homeName ? "Home" : "Drive",
            duration: activity.durationMinutes,
            category: activity.category,
            weekdays: activity.weekdays.isEmpty ? nil : Array(Set(activity.weekdays)).sorted(),
            recurrenceWeekCount: activity.recurrenceMode == .weekly ? (activity.recurrenceWeekCount ?? 1) : nil
        )
    }

    private func recurrencePattern(for activity: DraftActivity, startDate: String, timeZone: String) -> RecurrencePattern {
        let mode = activity.recurrenceMode ?? (activity.weekdays.isEmpty ? .none : .weekly)
        let end: RecurrenceEnd
        if let through = activity.recurrenceThroughDate, !through.isEmpty {
            end = .throughDate(through)
        } else {
            end = .weekCount(activity.recurrenceWeekCount ?? 1)
        }
        return RecurrencePattern(
            mode: mode,
            startDate: startDate,
            timeZone: timeZone,
            weekdays: Array(Set(activity.weekdays)).sorted(),
            end: end
        )
    }

    private func event(
        from activity: DraftActivity,
        date: String,
        seriesId: String,
        crewNames: [String],
        kidRoster: [String]
    ) -> TaskRecord {
        let kids = resolvedKids(activity.kidNames, kidRoster: kidRoster)
        let place = resolvedPlace(activity.placeName)
        let atHome = place == homeName
        return TaskRecord(
            id: "onb-\(activity.id)-\(date)",
            date: date,
            time: activity.time,
            endTime: PlanCore.addMinutes(time: activity.time, mins: activity.durationMinutes),
            title: activity.title.trimmingCharacters(in: .whitespaces),
            owner: resolvedOwner(activity.ownerName, crewNames: crewNames),
            kids: kids,
            kid: kids.joined(separator: ", "),
            location: place,
            mode: atHome ? "Home" : "Drive",
            kind: atHome ? .home : .drive,
            seriesId: seriesId,
            originalOccurrenceDate: date
        )
    }

    // MARK: Re-run

    /// Rebuilds a draft from a household that is already set up, so a second run
    /// of setup starts from the real answers instead of a blank form.
    static func from(store: AppStore) -> OnboardingDraft {
        var draft = OnboardingDraft()
        let crew = store.caregiverPeople()
        let active = crew.first(where: { $0.name == store.currentUser }) ?? crew.first

        draft.yourName = active?.name ?? ""
        draft.yourRelationship = active?.relationship ?? "Mother"
        draft.homePlaceName = store.home()
        draft.homeAddress = store.homeAddress
        if let home = store.locations.first(where: { $0.name == store.home() }) {
            draft.homeLatitude = home.latitude
            draft.homeLongitude = home.longitude
            draft.homePlaceId = home.placeId
            draft.homeSource = home.source
            draft.homeRouteKey = home.routeKey
        }
        draft.crew = crew
            .filter { $0.name != active?.name }
            .map { DraftPerson(name: $0.name, relationship: $0.relationship) }
        draft.kids = store.childPeople().map { DraftPerson(name: $0.name, relationship: "Child") }

        draft.places = store.locations
            .filter { $0.name != store.home() }
            .map { location in
                DraftPlace(
                    name: location.name,
                    address: location.address,
                    icon: location.icon ?? "map-pin",
                    minutesFromHome: store.travel(origin: store.home(), destination: location.name, at: nil) ?? 15,
                    latitude: location.latitude,
                    longitude: location.longitude,
                    placeId: location.placeId,
                    source: location.source,
                    routeKey: location.routeKey
                )
            }

        draft.activities = store.templates.map { template in
            DraftActivity(
                title: template.title,
                kidNames: template.kids,
                placeName: template.location,
                weekdays: OnboardingDraft.weekdays(for: template, in: store),
                time: template.time,
                durationMinutes: template.duration,
                ownerName: template.owner,
                category: template.category ?? "Sports",
                recurrenceMode: template.repeatDays.isEmpty ? RecurrenceMode.none : .weekly,
                recurrenceWeekCount: template.recurrenceWeekCount ?? 1
            )
        }

        return draft
    }

    /// Which days this routine already sits on, read back off the week so a
    /// re-run does not silently forget the schedule the family built.
    private static func weekdays(for template: TemplateItem, in store: AppStore) -> [Int] {
        var days: [Int] = []
        for day in 0...6 {
            let matches = store.eventsByDay[day]?.contains {
                $0.title == template.title && $0.time == template.time
            } ?? false
            if matches { days.append(day) }
        }
        return template.repeatDays.isEmpty ? days : template.repeatDays.sorted()
    }
}

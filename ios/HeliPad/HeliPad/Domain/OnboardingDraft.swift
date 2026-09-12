import Foundation

// MARK: - Onboarding Draft
//
// Everything the setup flow collects, in one Codable value. It is captured
// before it touches the store, so the flow can be abandoned without damaging
// a family that is already set up, and so a re-run can start from what the
// household answered last time.

public struct OnboardingDraft: Codable, Hashable {

    // MARK: Nested drafts

    public struct DraftPerson: Identifiable, Codable, Hashable {
        public var id: String
        public var name: String
        public var relationship: String

        public init(id: String = UUID().uuidString, name: String = "", relationship: String = "Other") {
            self.id = id
            self.name = name
            self.relationship = relationship
        }
    }

    public struct DraftPlace: Identifiable, Codable, Hashable {
        public var id: String
        public var name: String
        public var address: String
        public var icon: String
        public var minutesFromHome: Int
        public var latitude: Double?
        public var longitude: Double?
        public var placeId: String?
        public var source: String?
        public var routeKey: String?

        public init(
            id: String = UUID().uuidString,
            name: String = "",
            address: String = "",
            icon: String = "map-pin",
            minutesFromHome: Int = 15,
            latitude: Double? = nil,
            longitude: Double? = nil,
            placeId: String? = nil,
            source: String? = nil,
            routeKey: String? = nil
        ) {
            self.id = id
            self.name = name
            self.address = address
            self.icon = icon
            self.minutesFromHome = minutesFromHome
            self.latitude = latitude
            self.longitude = longitude
            self.placeId = placeId
            self.source = source
            self.routeKey = routeKey
        }
    }

    public struct DraftActivity: Identifiable, Codable, Hashable {
        public var id: String
        public var title: String
        public var kidNames: [String]
        public var placeName: String
        public var weekdays: [Int]        // 0 = Monday … 6 = Sunday
        public var time: String           // "HH:mm"
        public var durationMinutes: Int
        public var ownerName: String      // a caregiver name, or "TBD" / "Family"
        public var category: String
        public var startDate: String?
        public var recurrenceMode: RecurrenceMode?
        public var recurrenceWeekCount: Int?
        public var recurrenceThroughDate: String?

        public init(
            id: String = UUID().uuidString,
            title: String = "",
            kidNames: [String] = [],
            placeName: String = "",
            weekdays: [Int] = [],
            time: String = "16:00",
            durationMinutes: Int = 60,
            ownerName: String = "TBD",
            category: String = "Sports",
            startDate: String? = PlanCore.currentDeviceDate(),
            recurrenceMode: RecurrenceMode? = .weekly,
            recurrenceWeekCount: Int? = 20,
            recurrenceThroughDate: String? = nil
        ) {
            self.id = id
            self.title = title
            self.kidNames = kidNames
            self.placeName = placeName
            self.weekdays = weekdays
            self.time = time
            self.durationMinutes = durationMinutes
            self.ownerName = ownerName
            self.category = category
            self.startDate = startDate
            self.recurrenceMode = recurrenceMode
            self.recurrenceWeekCount = recurrenceWeekCount
            self.recurrenceThroughDate = recurrenceThroughDate
        }
    }

    // MARK: Answers

    public var yourName: String
    public var yourRelationship: String
    public var homePlaceName: String
    public var homeAddress: String
    public var homeLatitude: Double?
    public var homeLongitude: Double?
    public var homePlaceId: String?
    public var homeSource: String?
    public var homeRouteKey: String?
    public var crew: [DraftPerson]        // caregivers besides you
    public var kids: [DraftPerson]
    public var places: [DraftPlace]
    public var activities: [DraftActivity]

    public init(
        yourName: String = "",
        yourRelationship: String = "Mother",
        homePlaceName: String = "Home",
        homeAddress: String = "",
        homeLatitude: Double? = nil,
        homeLongitude: Double? = nil,
        homePlaceId: String? = nil,
        homeSource: String? = nil,
        homeRouteKey: String? = nil,
        crew: [DraftPerson] = [],
        kids: [DraftPerson] = [],
        places: [DraftPlace] = [],
        activities: [DraftActivity] = []
    ) {
        self.yourName = yourName
        self.yourRelationship = yourRelationship
        self.homePlaceName = homePlaceName
        self.homeAddress = homeAddress
        self.homeLatitude = homeLatitude
        self.homeLongitude = homeLongitude
        self.homePlaceId = homePlaceId
        self.homeSource = homeSource
        self.homeRouteKey = homeRouteKey
        self.crew = crew
        self.kids = kids
        self.places = places
        self.activities = activities
    }

    // MARK: Vocabulary

    public static let caregiverRelationships = [
        "Mother", "Father", "Grandmother", "Grandfather",
        "Aunt", "Uncle", "Nanny", "Other"
    ]

    public static let activityCategories = ["Sports", "Arts", "School", "Health", "Family"]

    public static let weekdayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    /// The four caregiver inks the design language already defines. Real names
    /// cycle through them so every person on the roster reads as distinct.
    public static let caregiverInks = ["#c75f45", "#397cad", "#8f55a0", "#3f806e"]
    public static let childInks = ["#a8672b", "#5a6ea8", "#8a6d3b", "#55532e"]

    // MARK: Normalized answers

    public var trimmedYourName: String {
        yourName.trimmingCharacters(in: .whitespaces)
    }

    public var homeName: String {
        let n = homePlaceName.trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? "Home" : n
    }

    /// You first, then everyone else you named. Blank, duplicate and reserved
    /// names are dropped rather than carried into the roster.
    public var caregiverNames: [String] {
        var seen = Set<String>()
        var out: [String] = []
        for candidate in [trimmedYourName] + crew.map({ $0.name.trimmingCharacters(in: .whitespaces) }) {
            guard OnboardingDraft.isUsableName(candidate) else { continue }
            let key = candidate.lowercased()
            if seen.contains(key) { continue }
            seen.insert(key)
            out.append(candidate)
        }
        return out
    }

    public var kidNames: [String] {
        var seen = Set(caregiverNames.map { $0.lowercased() })
        var out: [String] = []
        for kid in kids {
            let name = kid.name.trimmingCharacters(in: .whitespaces)
            guard OnboardingDraft.isUsableName(name) else { continue }
            let key = name.lowercased()
            if seen.contains(key) { continue }
            seen.insert(key)
            out.append(name)
        }
        return out
    }

    public var placeNames: [String] {
        var seen = Set([homeName.lowercased()])
        var out: [String] = []
        for place in places {
            let name = place.name.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }
            let key = name.lowercased()
            if seen.contains(key) { continue }
            seen.insert(key)
            out.append(name)
        }
        return out
    }

    public static func isUsableName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && !AppStore.isReservedName(trimmed)
    }

    // MARK: Step validation

    public var youStepIsComplete: Bool { OnboardingDraft.isUsableName(yourName) }
    public var homeStepIsComplete: Bool { !homeAddress.trimmingCharacters(in: .whitespaces).isEmpty }
    public var kidsStepIsComplete: Bool { !kidNames.isEmpty }

    public var activitiesValidationError: String? {
        for activity in activities {
            let title = activity.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if title.isEmpty { continue }
            let start = activity.startDate ?? PlanCore.currentDeviceDate()
            let mode = activity.recurrenceMode ?? (activity.weekdays.isEmpty ? .none : .weekly)
            let end: RecurrenceEnd = activity.recurrenceThroughDate.map(RecurrenceEnd.throughDate)
                ?? .weekCount(activity.recurrenceWeekCount ?? 1)
            let pattern = RecurrencePattern(
                mode: mode,
                startDate: start,
                weekdays: activity.weekdays,
                end: end
            )
            let draft = TaskRecord(
                id: "validation",
                date: start,
                time: activity.time,
                endTime: PlanCore.addMinutes(time: activity.time, mins: activity.durationMinutes),
                title: title
            )
            do { _ = try PlanCore.occurrences(draft, recurrence: pattern, seriesId: "validation") }
            catch { return "\(title): \(error.localizedDescription)" }
        }
        return nil
    }
}

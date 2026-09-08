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

        public init(
            id: String = UUID().uuidString,
            name: String = "",
            address: String = "",
            icon: String = "map-pin",
            minutesFromHome: Int = 15
        ) {
            self.id = id
            self.name = name
            self.address = address
            self.icon = icon
            self.minutesFromHome = minutesFromHome
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

        public init(
            id: String = UUID().uuidString,
            title: String = "",
            kidNames: [String] = [],
            placeName: String = "",
            weekdays: [Int] = [],
            time: String = "16:00",
            durationMinutes: Int = 60,
            ownerName: String = "TBD",
            category: String = "Sports"
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
        }
    }

    // MARK: Answers

    public var yourName: String
    public var yourRelationship: String
    public var homePlaceName: String
    public var homeAddress: String
    public var crew: [DraftPerson]        // caregivers besides you
    public var kids: [DraftPerson]
    public var places: [DraftPlace]
    public var activities: [DraftActivity]

    public init(
        yourName: String = "",
        yourRelationship: String = "Mother",
        homePlaceName: String = "Home",
        homeAddress: String = "",
        crew: [DraftPerson] = [],
        kids: [DraftPerson] = [],
        places: [DraftPlace] = [],
        activities: [DraftActivity] = []
    ) {
        self.yourName = yourName
        self.yourRelationship = yourRelationship
        self.homePlaceName = homePlaceName
        self.homeAddress = homeAddress
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
}

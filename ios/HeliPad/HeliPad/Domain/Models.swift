import Foundation

enum TaskKind: String, Codable, CaseIterable, Hashable {
    case drive
    case cook
    case lead
    case placeholder
    case dinner
    case home
}

enum UrgencyTone: String, Hashable {
    case later, ontrack, soon, now, started, late, driverNeeded
}

struct Person: Identifiable, Hashable {
    let id: String
    var name: String
    var role: String // caregiver | child
    var monogram: String
}

struct Place: Identifiable, Hashable {
    let id: String
    var name: String
    var kind: String
}

/// Root coordination unit (SYSTEM.md). Travel is an optional facet.
struct TaskItem: Identifiable, Hashable {
    let id: String
    var kind: TaskKind
    var title: String
    var start: Date
    var end: Date?
    var children: [String]
    var assigneeId: String?
    var backupId: String?
    var isDone: Bool
    var bufferMinutes: Int
    var group: String // go | dinner | home
    var stamp: String?
    var travel: TravelFacet?
}

struct TravelFacet: Hashable {
    var originId: String
    var destinationId: String
    var mode: String
}

struct TripPlan: Hashable {
    var departBy: Date
    var travelMinutes: Int
    var arriveBy: Date
    var tone: UrgencyTone
    var leaveInMinutes: Int
}

/// First-class facet: sticky in prod, switchable in lab.
struct ActiveViewer: Hashable {
    var caregiverId: String
    var isLabSwitchable: Bool
}

struct DayAgenda {
    var viewer: ActiveViewer
    var tasks: [TaskItem]
    var people: [Person]
    var places: [Place]
}

import Foundation

protocol CalendarProvider {
    func events(for day: Date) async throws -> [TaskItem]
}

protocol TravelEstimator {
    func travelMinutes(from origin: Place, to destination: Place, departingAt: Date) async throws -> Int
}

protocol Notifier {
    /// Shared-backend push owned by platform later — local toast stub only for now.
    func notifyCrew(message: String) async
}

protocol TaskStore {
    func loadAgenda(viewer: ActiveViewer) async throws -> DayAgenda
    func saveOverlay(_ task: TaskItem) async throws
}

struct StubNotifier: Notifier {
    func notifyCrew(message: String) async {
        // Intentionally no fake multi-device sync.
        print("[heli-notify] \(message)")
    }
}

struct SampleDayStore: TaskStore {
    func loadAgenda(viewer: ActiveViewer) async throws -> DayAgenda {
        SampleDay.agenda(for: viewer)
    }

    func saveOverlay(_ task: TaskItem) async throws {
        _ = task
    }
}

enum SampleDay {
    static let mom = Person(id: "mom", name: "Mom", role: "caregiver", monogram: "M")
    static let dad = Person(id: "dad", name: "Dad", role: "caregiver", monogram: "D")
    static let maya = Person(id: "maya", name: "Maya", role: "child", monogram: "M")
    static let leo = Person(id: "leo", name: "Leo", role: "child", monogram: "L")

    static let home = Place(id: "home", name: "Home", kind: "home")
    static let school = Place(id: "school", name: "Riverside School", kind: "school")
    static let pitch = Place(id: "pitch", name: "North Field", kind: "activity")
    static let clinic = Place(id: "clinic", name: "Pediatric Clinic", kind: "other")

    static func agenda(for viewer: ActiveViewer) -> DayAgenda {
        let cal = Calendar.current
        let now = Date()
        func at(_ h: Int, _ m: Int) -> Date {
            cal.date(bySettingHour: h, minute: m, second: 0, of: now) ?? now
        }
        let tasks: [TaskItem] = [
            TaskItem(
                id: "maya-pickup",
                kind: .drive,
                title: "Pick up Maya",
                start: at(15, 45),
                end: at(16, 0),
                children: ["maya"],
                assigneeId: viewer.caregiverId,
                backupId: viewer.caregiverId == "mom" ? "dad" : "mom",
                isDone: false,
                bufferMinutes: 8,
                group: "go",
                stamp: "M",
                travel: TravelFacet(originId: "home", destinationId: "school", mode: "drive")
            ),
            TaskItem(
                id: "maya-soccer",
                kind: .drive,
                title: "Maya soccer",
                start: at(17, 15),
                end: at(18, 15),
                children: ["maya"],
                assigneeId: "dad",
                backupId: "mom",
                isDone: false,
                bufferMinutes: 10,
                group: "go",
                stamp: "M",
                travel: TravelFacet(originId: "school", destinationId: "pitch", mode: "drive")
            ),
            TaskItem(
                id: "leo-clinic",
                kind: .drive,
                title: "Leo clinic",
                start: at(16, 30),
                end: at(17, 0),
                children: ["leo"],
                assigneeId: "mom",
                backupId: "dad",
                isDone: false,
                bufferMinutes: 12,
                group: "go",
                stamp: "L",
                travel: TravelFacet(originId: "home", destinationId: "clinic", mode: "drive")
            ),
            TaskItem(
                id: "dinner-pasta",
                kind: .dinner,
                title: "Pasta + salad",
                start: at(18, 45),
                end: at(19, 30),
                children: ["maya", "leo"],
                assigneeId: "mom",
                backupId: "dad",
                isDone: false,
                bufferMinutes: 0,
                group: "dinner",
                stamp: nil,
                travel: nil
            ),
            TaskItem(
                id: "bedtime-books",
                kind: .home,
                title: "Bedtime books",
                start: at(20, 0),
                end: at(20, 30),
                children: ["maya", "leo"],
                assigneeId: viewer.caregiverId,
                backupId: nil,
                isDone: false,
                bufferMinutes: 0,
                group: "home",
                stamp: nil,
                travel: nil
            )
        ]
        return DayAgenda(
            viewer: viewer,
            tasks: tasks,
            people: [mom, dad, maya, leo],
            places: [home, school, pitch, clinic]
        )
    }
}

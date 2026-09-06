import Foundation
import SwiftUI

@MainActor
final class TodayViewModel: ObservableObject {
    @Published var agenda: DayAgenda
    @Published var hero: TaskItem?
    @Published var plan: TripPlan?
    @Published var showEdit = false
    @Published var showTellTheCrew = false
    @Published var toast: String?
    @Published var draftAssigneeId: String?
    @Published var draftLeaveBy: Date?
    @Published var isLabMode: Bool

    private let store: TaskStore
    private let notifier: Notifier
    private var baselineAssigneeId: String?
    private var baselineLeaveBy: Date?

    init(store: TaskStore = SampleDayStore(), notifier: Notifier = StubNotifier(), labMode: Bool = true) {
        self.store = store
        self.notifier = notifier
        self.isLabMode = labMode
        let viewer = ActiveViewer(caregiverId: "mom", isLabSwitchable: labMode)
        self.agenda = SampleDay.agenda(for: viewer)
        refreshHero()
    }

    var viewerName: String {
        agenda.people.first(where: { $0.id == agenda.viewer.caregiverId })?.name ?? "Caregiver"
    }

    var restGroups: [(String, [TaskItem])] {
        TodayUseCases.restGroups(in: agenda, excluding: hero?.id)
    }

    func refreshHero() {
        hero = TodayUseCases.hottestTask(in: agenda)
        plan = hero.flatMap { TodayUseCases.tripPlan(for: $0) }
        draftAssigneeId = hero?.assigneeId
        draftLeaveBy = plan?.departBy
        baselineAssigneeId = draftAssigneeId
        baselineLeaveBy = draftLeaveBy
    }

    func switchViewer() {
        guard agenda.viewer.isLabSwitchable else { return }
        let next = agenda.viewer.caregiverId == "mom" ? "dad" : "mom"
        agenda.viewer.caregiverId = next
        // Recompute per viewer — never label-swap a merged household view.
        Task {
            if let loaded = try? await store.loadAgenda(viewer: agenda.viewer) {
                agenda = loaded
                refreshHero()
            }
        }
    }

    func openEdit() {
        showEdit = true
        showTellTheCrew = false
    }

    func applyLeaveNudge(_ minutes: Int) {
        guard let current = draftLeaveBy else { return }
        draftLeaveBy = current.addingTimeInterval(TimeInterval(minutes * 60))
    }

    func setDriver(_ id: String) {
        draftAssigneeId = id
    }

    /// Done: either commit quietly or morph to Tell-the-crew.
    func tapDone() {
        let driverChanged = draftAssigneeId != baselineAssigneeId
        let delta: Int = {
            guard let a = draftLeaveBy, let b = baselineLeaveBy else { return 0 }
            return Int(a.timeIntervalSince(b) / 60)
        }()
        if TodayUseCases.requiresTellTheCrew(driverChanged: driverChanged, leaveByDeltaMinutes: delta) {
            showTellTheCrew = true
        } else {
            commitEdits(notify: false)
        }
    }

    func sendToCrew() {
        Task {
            await notifier.notifyCrew(message: "Updated \(hero?.title ?? "task")")
            commitEdits(notify: true)
        }
    }

    func dontNotify() {
        commitEdits(notify: false)
    }

    /// Swipe-down / Escape from Tell-the-crew → Edit only (never skip Send / silent discard).
    func backFromTellTheCrewToEdit() {
        showTellTheCrew = false
        showEdit = true
    }

    func completeHero() {
        guard var h = hero, let idx = agenda.tasks.firstIndex(where: { $0.id == h.id }) else { return }
        h.isDone = true
        agenda.tasks[idx] = h
        toast = "Completed — undo in 5s"
        refreshHero()
    }

    func snoozeHero(by minutes: Int = 10) {
        guard var h = hero, let idx = agenda.tasks.firstIndex(where: { $0.id == h.id }) else { return }
        h.start = h.start.addingTimeInterval(TimeInterval(minutes * 60))
        agenda.tasks[idx] = h
        // ≥10 still triggers Tell-the-crew rules
        if minutes >= 10 {
            showEdit = true
            showTellTheCrew = true
            toast = "Snoozed +\(minutes) — tell the crew"
        } else {
            toast = "Snoozed +\(minutes) min"
        }
        refreshHero()
    }

    private func commitEdits(notify: Bool) {
        guard var h = hero, let idx = agenda.tasks.firstIndex(where: { $0.id == h.id }) else { return }
        h.assigneeId = draftAssigneeId
        agenda.tasks[idx] = h
        showTellTheCrew = false
        showEdit = false
        toast = notify ? "Crew notified" : "Saved"
        refreshHero()
    }

    func personName(_ id: String?) -> String {
        guard let id else { return "—" }
        return agenda.people.first(where: { $0.id == id })?.name ?? id
    }

    func childNames(_ ids: [String]) -> String {
        ids.compactMap { id in agenda.people.first(where: { $0.id == id })?.name }.joined(separator: " · ")
    }
}

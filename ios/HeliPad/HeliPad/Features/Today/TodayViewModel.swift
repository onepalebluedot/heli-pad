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
    @Published var overlapTask: TaskItem?
    @Published var askConfirmSent = false

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
        refreshHero(resetBaselines: true)
    }

    var viewerName: String {
        agenda.people.first(where: { $0.id == agenda.viewer.caregiverId })?.name ?? "Caregiver"
    }

    var restGroups: [(String, [TaskItem])] {
        TodayUseCases.restGroups(in: agenda, excluding: hero?.id)
    }

    var wasSummary: String? {
        guard let leave = baselineLeaveBy else { return nil }
        let driver = personName(baselineAssigneeId)
        return "Was: \(driver) · leave \(leave.formatted(date: .omitted, time: .shortened))"
    }

    var askConfirmName: String {
        // Ask the other caregiver (backup / non-assignee) to confirm.
        let other = draftAssigneeId == "mom" ? "dad" : "mom"
        return personName(other)
    }

    func refreshHero(resetBaselines: Bool = true) {
        hero = TodayUseCases.hottestTask(in: agenda)
        plan = hero.flatMap { TodayUseCases.tripPlan(for: $0) }
        draftAssigneeId = hero?.assigneeId
        draftLeaveBy = plan?.departBy
        if resetBaselines {
            baselineAssigneeId = draftAssigneeId
            baselineLeaveBy = draftLeaveBy
        }
        recalculateOverlap()
    }

    func switchViewer() {
        guard agenda.viewer.isLabSwitchable else { return }
        let next = agenda.viewer.caregiverId == "mom" ? "dad" : "mom"
        agenda.viewer.caregiverId = next
        // Recompute per viewer — never label-swap a merged household view.
        Task {
            if let loaded = try? await store.loadAgenda(viewer: agenda.viewer) {
                agenda = loaded
                refreshHero(resetBaselines: true)
            }
        }
    }

    func openEdit() {
        showEdit = true
        showTellTheCrew = false
        askConfirmSent = false
        recalculateOverlap()
    }

    func applyLeaveNudge(_ minutes: Int) {
        guard let current = draftLeaveBy else { return }
        draftLeaveBy = current.addingTimeInterval(TimeInterval(minutes * 60))
        recalculateOverlap()
    }

    func setDriver(_ id: String) {
        draftAssigneeId = id
    }

    /// Done: either commit quietly or morph to Tell-the-crew.
    func tapDone() {
        let driverChanged = draftAssigneeId != baselineAssigneeId
        let delta = leaveByDeltaMinutes()
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

    /// Tap-only Ask X to confirm (SWIPE-TAP-MAP).
    func askToConfirm() {
        askConfirmSent = true
        toast = "Asked \(askConfirmName) to confirm"
        Task {
            await notifier.notifyCrew(message: "Please confirm overlap around \(hero?.title ?? "task")")
        }
    }

    func completeHero() {
        completeTask(id: hero?.id)
    }

    func snoozeHero(by minutes: Int = 10) {
        snoozeTask(id: hero?.id, by: minutes, presentTellTheCrew: true)
    }

    func completeTask(id: String?) {
        guard let id, var task = agenda.tasks.first(where: { $0.id == id }),
              let idx = agenda.tasks.firstIndex(where: { $0.id == id }) else { return }
        task.isDone = true
        agenda.tasks[idx] = task
        toast = "Completed — undo in 5s"
        refreshHero(resetBaselines: true)
    }

    func snoozeTask(id: String?, by minutes: Int = 10, presentTellTheCrew: Bool = false) {
        guard let id, var task = agenda.tasks.first(where: { $0.id == id }),
              let idx = agenda.tasks.firstIndex(where: { $0.id == id }) else { return }

        // Capture baselines BEFORE mutating so ≥10 still trips Tell-the-crew.
        let preAssignee = task.assigneeId
        let preLeave = TodayUseCases.tripPlan(for: task)?.departBy

        task.start = task.start.addingTimeInterval(TimeInterval(minutes * 60))
        agenda.tasks[idx] = task

        if id == hero?.id {
            hero = task
            plan = TodayUseCases.tripPlan(for: task)
            draftAssigneeId = task.assigneeId
            draftLeaveBy = plan?.departBy
            baselineAssigneeId = preAssignee
            baselineLeaveBy = preLeave
        }

        if presentTellTheCrew && minutes >= 10 && id == hero?.id {
            showEdit = true
            showTellTheCrew = true
            toast = "Snoozed +\(minutes) — tell the crew"
            // Do not refreshHero (would wipe baselines).
            recalculateOverlap()
        } else {
            toast = "Snoozed +\(minutes) min"
            refreshHero(resetBaselines: true)
        }
    }

    private func commitEdits(notify: Bool) {
        guard var h = hero, let idx = agenda.tasks.firstIndex(where: { $0.id == h.id }) else { return }
        h.assigneeId = draftAssigneeId
        // Gate fix: persist leave-by nudges onto the Task.
        if let leaveBy = draftLeaveBy {
            h = TodayUseCases.applying(leaveBy: leaveBy, to: h)
        }
        agenda.tasks[idx] = h
        showTellTheCrew = false
        showEdit = false
        askConfirmSent = false
        toast = notify ? "Crew notified" : "Saved"
        refreshHero(resetBaselines: true)
    }

    private func leaveByDeltaMinutes() -> Int {
        guard let a = draftLeaveBy, let b = baselineLeaveBy else { return 0 }
        return Int(a.timeIntervalSince(b) / 60)
    }

    private func recalculateOverlap() {
        guard let hero else {
            overlapTask = nil
            return
        }
        var probe = hero
        if let leaveBy = draftLeaveBy {
            probe = TodayUseCases.applying(leaveBy: leaveBy, to: probe)
        }
        overlapTask = TodayUseCases.dualKidOverlap(for: probe, in: agenda)
    }

    func personName(_ id: String?) -> String {
        guard let id else { return "—" }
        return agenda.people.first(where: { $0.id == id })?.name ?? id
    }

    func childNames(_ ids: [String]) -> String {
        ids.compactMap { id in agenda.people.first(where: { $0.id == id })?.name }.joined(separator: " · ")
    }
}

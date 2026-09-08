import SwiftUI

public struct PlanView: View {
    @ObservedObject public var store: AppStore
    @StateObject private var viewModel = PlanViewModel()
    @State private var eventToEdit: TaskRecord? = nil
    /// Set when the sheet was opened to edit a whole recurring series.
    @State private var seriesToEdit: RoutineGroup? = nil
    /// Usual days carried in from a shortcut, so it opens ready to repeat.
    @State private var templateDays: Set<Int> = []

    public init(store: AppStore) {
        self.store = store
    }

    public var body: some View {
        let summary = viewModel.summary(store: store)
        let decisions = viewModel.decisionQueue(store: store)
        let routines = viewModel.routineGroups(store: store)

        ScrollView {
            VStack(spacing: 20) {
                // 1. Week Masthead with prev/next week arrows
                PlanMastheadView(
                    weekRange: viewModel.formatWeekRange(),
                    onPrev: { viewModel.changeWeek(delta: -1) },
                    onNext: { viewModel.changeWeek(delta: 1) }
                )

                // 2. Command Card with readiness counts
                PlanCommandCardView(
                    unassignedCount: summary.missing,
                    reviewCount: summary.review,
                    routinesCount: store.templates.count,
                    onReview: {
                        viewModel.reviewFilter = .all
                        viewModel.showReviewSheet = true
                    },
                    onRebalance: { viewModel.showRebalanceSheet = true },
                    onPriorities: { viewModel.showPrioritiesSheet = true },
                    onTapUnassigned: {
                        viewModel.reviewFilter = .unassigned
                        viewModel.showReviewSheet = true
                    },
                    onTapReview: {
                        viewModel.reviewFilter = .review
                        viewModel.showReviewSheet = true
                    },
                    onTapRoutines: {
                        // Focus on shortcuts
                    }
                )

                // 3. Decision Queue ("Act First")
                PlanDecisionListView(
                    decisions: decisions,
                    onAssign: { ev in
                        viewModel.activeEventForAssign = ev
                        viewModel.activeRoutineForAssign = nil
                        viewModel.showAssignSheet = true
                    },
                    onReview: { item in
                        eventToEdit = item.event
                        viewModel.showEventSheet = true
                    },
                    onDismiss: { eventId in
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                            store.dismissReview(for: eventId)
                        }
                    }
                )

                // 4. Template Shortcuts Strip
                PlanTemplateStripView(
                    templates: store.templates,
                    onSelectTemplate: { tmpl in
                        // A shortcut with usual days lands on the first of them
                        // in the week on screen; otherwise on the day in view.
                        let usual = tmpl.repeatDays
                        let date = usual.sorted().first
                            .map { PlanCore.dateAdd(viewModel.currentWeek, $0) }
                            ?? viewModel.selectedDay
                        templateDays = usual
                        eventToEdit = FamilyCore.eventDraft(template: tmpl, date: date)
                        viewModel.showEventSheet = true
                    }

                )

                // 5. Recurring stops — one card per series, edited as a set
                PlanRoutinesView(
                    routines: routines,
                    onSetCaregiver: { group in
                        viewModel.activeRoutineForAssign = group
                        viewModel.activeEventForAssign = nil
                        viewModel.showAssignSheet = true
                    },
                    onEditSeries: { group in
                        guard let first = group.events.min(by: { $0.date < $1.date }) else { return }
                        seriesToEdit = group
                        eventToEdit = first
                        viewModel.showEventSheet = true
                    }
                )

                // 6. Expandable 7-day schedule with day selection
                PlanScheduleView(
                    viewModel: viewModel,
                    store: store,
                    onSelectEvent: { ev in
                        eventToEdit = ev
                        viewModel.showEventSheet = true
                    },
                    onAddEvent: { dateStr in
                        let newEv = TaskRecord(
                            id: "ev-\(UUID().uuidString.prefix(8))",
                            date: dateStr,
                            time: "15:00",
                            endTime: "16:00",
                            title: "",
                            owner: "TBD",
                            kids: [],
                            location: "Home",
                            mode: "Drive"
                        )
                        eventToEdit = newEv
                        viewModel.showEventSheet = true
                    }
                )

                Spacer().frame(height: 80)
            }
            .padding(.top, 8)
        }
        .background(HeliColors.canvasIvory.ignoresSafeArea())
        // MARK: - Sheets
        .sheet(isPresented: $viewModel.showReviewSheet) {
            PlanReviewSheet(
                store: store,
                currentWeek: viewModel.currentWeek,
                initialFilter: viewModel.reviewFilter,
                onSelectEvent: { ev in
                    eventToEdit = ev
                    viewModel.showEventSheet = true
                },
                onAssignEvent: { ev in
                    viewModel.showReviewSheet = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        viewModel.activeEventForAssign = ev
                        viewModel.activeRoutineForAssign = nil
                        viewModel.showAssignSheet = true
                    }
                }
            )
        }
        .sheet(isPresented: $viewModel.showRoutinesSheet) {
            PlanRoutinesSheet(
                store: store,
                routines: routines,
                onAssignRoutine: { group in
                    viewModel.showRoutinesSheet = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        viewModel.activeRoutineForAssign = group
                        viewModel.activeEventForAssign = nil
                        viewModel.showAssignSheet = true
                    }
                },
                onSelectEvent: { ev in
                    viewModel.showRoutinesSheet = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        eventToEdit = ev
                        viewModel.showEventSheet = true
                    }
                }
            )
        }
        .sheet(isPresented: $viewModel.showAssignSheet) {
            PlanAssignSheet(
                store: store,
                event: viewModel.activeEventForAssign,
                routine: viewModel.activeRoutineForAssign,
                onAssignEvent: { ev, newOwner in
                    var all = store.records()
                    if let idx = all.firstIndex(where: { $0.id == ev.id }) {
                        all[idx].owner = newOwner
                        all[idx].lead = newOwner
                        all[idx].tentative = false
                        store.replaceRecords(all)
                    }
                },
                onAssignRoutine: { routine, newOwner in
                    viewModel.setCaregiverForRoutine(routine: routine, caregiver: newOwner, store: store)
                }
            )
        }
        .sheet(isPresented: $viewModel.showRebalanceSheet) {
            PlanRebalanceSheet(store: store, currentWeek: viewModel.currentWeek)
        }
        .sheet(isPresented: $viewModel.showPrioritiesSheet) {
            PlanPrioritiesSheet(store: store)
        }
        .sheet(isPresented: $viewModel.showCalendarSheet) {
            PlanCalendarReviewSheet(store: store)
        }
        .sheet(isPresented: $viewModel.showEventSheet, onDismiss: { seriesToEdit = nil; templateDays = [] }) {
            if let ev = eventToEdit {
                // A stop the week already holds is an edit; anything else is a new
                // stop that should open on the day (or template) it came from.
                let isExisting = store.records().contains(where: { $0.id == ev.id })
                let series = seriesToEdit
                GoAddEditStopSheet(
                    store: store,
                    existingStop: isExisting ? ev : nil,
                    prefill: isExisting ? nil : ev,
                    seriesEvents: series?.events ?? [],
                    preselectedDays: isExisting || templateDays.isEmpty ? nil : templateDays,
                    onSave: { updatedStops in
                        var all = store.records()
                        if let series = series {
                            // Days switched off in the editor leave the series.
                            let kept = Set(updatedStops.map { $0.id })
                            let original = Set(series.events.map { $0.id })
                            all.removeAll { original.contains($0.id) && !kept.contains($0.id) }
                        }
                        for updated in updatedStops {
                            if let idx = all.firstIndex(where: { $0.id == updated.id }) {
                                all[idx] = updated
                            } else {
                                all.append(updated)
                            }
                        }
                        store.replaceRecords(all)
                    },
                    onDelete: { id in
                        var all = store.records()
                        if let series = series {
                            let original = Set(series.events.map { $0.id })
                            all.removeAll { original.contains($0.id) }
                        } else {
                            all.removeAll { $0.id == id }
                        }
                        store.replaceRecords(all)
                    }
                )
            }
        }

    }
}

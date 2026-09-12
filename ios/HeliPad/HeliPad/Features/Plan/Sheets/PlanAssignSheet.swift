import SwiftUI

public struct PlanAssignSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject public var store: AppStore
    public var event: TaskRecord?
    public var routine: RoutineGroup?
    @State private var assignScope: RecurrenceEditScope = .occurrence
    @State private var pendingOwner: String? = nil
    @State private var showSeriesConfirmation = false
    @State private var errorMessage: String? = nil

    public init(
        store: AppStore,
        event: TaskRecord? = nil,
        routine: RoutineGroup? = nil
    ) {
        self.store = store
        self.event = event
        self.routine = routine
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let ev = event {
                        eventHeader(ev: ev)
                        candidateList(ev: ev)
                    } else if let rt = routine {
                        routineHeader(rt: rt)
                        routineCaregiverList(rt: rt)
                    }
                }
                .padding(20)
            }
            .background(HeliColors.canvasIvory)
            .navigationTitle(event != nil ? "Assign Driver" : "Assign Routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundColor(HeliColors.greenInk)
                }
            }
            .confirmationDialog("Assign the entire series?", isPresented: $showSeriesConfirmation, titleVisibility: .visible) {
                Button("Assign all \(seriesCount) occurrences") { commitPendingSeriesAssignment() }
                Button("Cancel", role: .cancel) { pendingOwner = nil }
            } message: {
                Text("This changes \(seriesCount) total occurrences, including \(historicalCount) in the past.")
            }
            .alert("Couldn’t Assign", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Please try again.")
            }
        }
    }

    // MARK: - Event Header & Candidates

    private func eventHeader(ev: TaskRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(ev.title)
                .font(HeliTypography.mastheadDate(22))
                .foregroundColor(HeliColors.greenInk)

            HStack(spacing: 8) {
                Text("\(ev.date) · \(ev.time)")
                    .font(HeliTypography.monoTime(12))
                    .foregroundColor(HeliColors.mutedGray)

                Text("•")
                    .foregroundColor(HeliColors.sageRule)

                Text(ev.location)
                    .font(HeliTypography.caption(12))
                    .foregroundColor(HeliColors.mutedGray)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HeliColors.cardWarmWhite)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(HeliColors.sageRule, lineWidth: 0.8))
    }

    private func candidateList(ev: TaskRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if ev.seriesId != nil {
                Picker("Assignment scope", selection: $assignScope) {
                    Text("This occurrence").tag(RecurrenceEditScope.occurrence)
                    Text("Entire series").tag(RecurrenceEditScope.series)
                }
                .pickerStyle(.segmented)
            }

            Text("CAREGIVER CANDIDATES")
                .font(HeliTypography.eyebrow(11))
                .foregroundColor(HeliColors.mutedGray)
                .tracking(1.4)

            ForEach(store.caregiverPeople()) { person in
                let detail = PlanCore.candidate(
                    ev,
                    person.name,
                    store.records(),
                    store.planningOptions()
                )
                candidateRow(person: person, detail: detail, isCurrent: ev.owner == person.name) {
                    requestAssignment(event: ev, owner: person.name)
                }
            }

            // Family (All Caregivers) Option
            let isFamily = (ev.owner == "Family")
            Button(action: {
                requestAssignment(event: ev, owner: "Family")
            }) {
                HStack {
                    AvatarDisc(name: "Family", size: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Family")
                            .font(HeliTypography.headline(15))
                            .foregroundColor(HeliColors.greenInk)
                        Text("All caretakers shared")
                            .font(HeliTypography.caption(11))
                            .foregroundColor(HeliColors.mutedGray)
                    }

                    if isFamily {
                        Text("Current")
                            .font(HeliTypography.eyebrow(9))
                            .foregroundColor(HeliColors.forestGreen)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(HeliColors.forestTint)
                            .clipShape(Capsule())
                    }

                    Spacer()

                    Text("Shared")
                        .font(HeliTypography.eyebrow(9))
                        .foregroundColor(HeliColors.forestGreen)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(HeliColors.forestTint)
                        .clipShape(Capsule())
                }
                .padding(14)
                .background(HeliColors.cardWarmWhite)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(isFamily ? HeliColors.forestGreen : HeliColors.sageRule, lineWidth: isFamily ? 1.5 : 0.8)
                )
            }
            .buttonStyle(PlainButtonStyle())

            // TBD / Unassign Option
            Button(action: {
                requestAssignment(event: ev, owner: "TBD")
            }) {
                HStack {
                    Text("Leave unassigned (TBD)")
                        .font(HeliTypography.body(14))
                        .foregroundColor(HeliColors.clayText)
                    Spacer()
                    if ev.owner.lowercased() == "tbd" {
                        Image(systemName: "checkmark")
                            .foregroundColor(HeliColors.clayText)
                    }
                }
                .padding(14)
                .background(HeliColors.cardWarmWhite)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(HeliColors.sageRule, lineWidth: 0.8))
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    private func candidateRow(person: Person, detail: CandidateDetail, isCurrent: Bool, onSelect: @escaping () -> Void) -> some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    AvatarDisc(name: person.name, size: 28)
                    Text(person.name)
                        .font(HeliTypography.headline(15))
                        .foregroundColor(HeliColors.greenInk)

                    if isCurrent {
                        Text("Current")
                            .font(HeliTypography.eyebrow(9))
                            .foregroundColor(HeliColors.forestGreen)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(HeliColors.forestTint)
                            .clipShape(Capsule())
                    }

                    Spacer()

                    if detail.conflict {
                        Text("Conflict")
                            .font(HeliTypography.eyebrow(9))
                            .foregroundColor(HeliColors.clayText)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(HeliColors.clayWash)
                            .clipShape(Capsule())
                    } else if let s = detail.slack, s < 10 {
                        Text("Tight (\(s)m)")
                            .font(HeliTypography.eyebrow(9))
                            .foregroundColor(HeliColors.ochreDark)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(HeliColors.butterLight)
                            .clipShape(Capsule())
                    } else {
                        Text("Optimal")
                            .font(HeliTypography.eyebrow(9))
                            .foregroundColor(HeliColors.forestGreen)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(HeliColors.forestTint)
                            .clipShape(Capsule())
                    }
                }

                // Subtitle details: Origin, Travel time, Slack
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Image(systemName: "location")
                            .font(.system(size: 10))
                        Text(detail.origin)
                            .font(HeliTypography.caption(11))
                    }
                    .foregroundColor(HeliColors.mutedGray)

                    if let eta = detail.eta {
                        HStack(spacing: 4) {
                            Image(systemName: "car")
                                .font(.system(size: 10))
                            Text("\(eta) min drive")
                                .font(HeliTypography.caption(11))
                        }
                        .foregroundColor(HeliColors.mutedGray)
                    }

                    if let slack = detail.slack {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.system(size: 10))
                            Text("\(slack)m slack before")
                                .font(HeliTypography.caption(11))
                        }
                        .foregroundColor(HeliColors.mutedGray)
                    }
                }
            }
            .padding(14)
            .background(HeliColors.cardWarmWhite)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isCurrent ? HeliColors.forestGreen : HeliColors.sageRule, lineWidth: isCurrent ? 1.5 : 0.8)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Routine Flow

    private func routineHeader(rt: RoutineGroup) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(rt.title)
                .font(HeliTypography.mastheadDate(22))
                .foregroundColor(HeliColors.greenInk)

            Text("\(rt.events.count) occurrences · \(rt.location)")
                .font(HeliTypography.caption(12))
                .foregroundColor(HeliColors.mutedGray)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HeliColors.cardWarmWhite)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(HeliColors.sageRule, lineWidth: 0.8))
    }

    private func routineCaregiverList(rt: RoutineGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ASSIGN TO ALL OCCURRENCES")
                .font(HeliTypography.eyebrow(11))
                .foregroundColor(HeliColors.mutedGray)
                .tracking(1.4)

            ForEach(store.caregiverPeople()) { person in
                Button(action: {
                    pendingOwner = person.name
                    showSeriesConfirmation = true
                }) {
                    HStack {
                        AvatarDisc(name: person.name, size: 28)
                        Text(person.name)
                            .font(HeliTypography.headline(15))
                            .foregroundColor(HeliColors.greenInk)

                        Spacer()

                        if rt.owner == person.name {
                            Text("Assigned to all")
                                .font(HeliTypography.eyebrow(9))
                                .foregroundColor(HeliColors.forestGreen)
                        } else {
                            Text("Set for all (\(rt.events.count))")
                                .font(HeliTypography.actionButton(12))
                                .foregroundColor(HeliColors.forestGreen)
                        }
                    }
                    .padding(14)
                    .background(HeliColors.cardWarmWhite)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(HeliColors.sageRule, lineWidth: 0.8))
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }

    private var seriesCount: Int {
        if let routine { return routine.events.count }
        guard let seriesId = event?.seriesId else { return 1 }
        return store.events(inSeries: seriesId).count
    }

    private var historicalCount: Int {
        let rows: [TaskRecord]
        if let routine { rows = routine.events }
        else if let seriesId = event?.seriesId { rows = store.events(inSeries: seriesId) }
        else { rows = event.map { [$0] } ?? [] }
        return rows.filter { $0.date < PlanCore.currentDeviceDate() }.count
    }

    private func requestAssignment(event: TaskRecord, owner: String) {
        if assignScope == .series, event.seriesId != nil {
            pendingOwner = owner
            showSeriesConfirmation = true
        } else {
            do {
                try store.assignEvent(id: event.id, caregiver: owner, scope: .occurrence)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func commitPendingSeriesAssignment() {
        guard let owner = pendingOwner else { return }
        let first = routine?.events.first ?? event
        guard let first else { return }
        do {
            try store.assignEvent(id: first.id, caregiver: owner, scope: .series)
            pendingOwner = nil
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

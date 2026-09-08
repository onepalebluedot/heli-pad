import SwiftUI

public struct PlanAssignSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject public var store: AppStore
    public var event: TaskRecord?
    public var routine: RoutineGroup?
    public var onAssignEvent: ((TaskRecord, String) -> Void)?
    public var onAssignRoutine: ((RoutineGroup, String) -> Void)?

    public init(
        store: AppStore,
        event: TaskRecord? = nil,
        routine: RoutineGroup? = nil,
        onAssignEvent: ((TaskRecord, String) -> Void)? = nil,
        onAssignRoutine: ((RoutineGroup, String) -> Void)? = nil
    ) {
        self.store = store
        self.event = event
        self.routine = routine
        self.onAssignEvent = onAssignEvent
        self.onAssignRoutine = onAssignRoutine
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
                    onAssignEvent?(ev, person.name)
                    dismiss()
                }
            }

            // Family (All Caregivers) Option
            let isFamily = (ev.owner == "Family")
            Button(action: {
                onAssignEvent?(ev, "Family")
                dismiss()
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
                onAssignEvent?(ev, "TBD")
                dismiss()
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
                    onAssignRoutine?(rt, person.name)
                    dismiss()
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
}

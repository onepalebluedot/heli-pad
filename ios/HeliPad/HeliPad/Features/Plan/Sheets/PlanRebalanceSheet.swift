import SwiftUI

public struct PlanRebalanceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject public var store: AppStore
    public var currentWeek: String

    public init(store: AppStore, currentWeek: String) {
        self.store = store
        self.currentWeek = currentWeek
    }

    public var body: some View {
        NavigationStack {
            let proposals = calculateProposals()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header card
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Schedule Rebalance")
                            .font(HeliTypography.mastheadDate(22))
                            .foregroundColor(HeliColors.greenInk)

                        Text("Deterministic assignment optimizations based on location proximity and travel slack.")
                            .font(HeliTypography.caption(12))
                            .foregroundColor(HeliColors.mutedGray)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(HeliColors.cardWarmWhite)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(HeliColors.sageRule, lineWidth: 0.8))

                    // Before vs After Drive Time Comparison
                    VStack(alignment: .leading, spacing: 10) {
                        Text("DRIVING TIME IMPACT")
                            .font(HeliTypography.eyebrow(11))
                            .foregroundColor(HeliColors.mutedGray)
                            .tracking(1.4)

                        VStack(spacing: 8) {
                            ForEach(store.caregiverPeople()) { person in
                                let beforeM = proposals.before[person.name] ?? 0
                                let afterM = proposals.after[person.name] ?? beforeM
                                caregiverLoadRow(name: person.name, before: beforeM, after: afterM)
                            }
                        }
                        .padding(14)
                        .background(HeliColors.cardWarmWhite)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(HeliColors.sageRule, lineWidth: 0.8))
                    }

                    // Proposed Changes
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Text("PROPOSED REASSIGNMENTS")
                                .font(HeliTypography.eyebrow(11))
                                .foregroundColor(HeliColors.mutedGray)
                                .tracking(1.4)

                            Text("\(proposals.changes.count)")
                                .font(HeliTypography.eyebrow(10))
                                .foregroundColor(HeliColors.forestGreen)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(HeliColors.forestTint)
                                .clipShape(Capsule())

                            Spacer()
                        }

                        if proposals.changes.isEmpty {
                            Text("Schedule is already optimal. No reassignments needed.")
                                .font(HeliTypography.body(13))
                                .foregroundColor(HeliColors.mutedGray)
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(HeliColors.cardWarmWhite)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        } else {
                            ForEach(proposals.changes) { prop in
                                proposalRow(prop: prop)
                            }
                        }
                    }

                    // Apply Button
                    if !proposals.changes.isEmpty {
                        Button(action: {
                            applyProposals(proposals: proposals)
                            dismiss()
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 13, weight: .bold))
                                Text("Apply \(proposals.changes.count) Reassignments")
                                    .font(HeliTypography.actionButton(14))
                            }
                            .foregroundColor(HeliColors.cardWarmWhite)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(HeliColors.forestGreen)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .padding(.top, 6)
                    }
                }
                .padding(20)
            }
            .background(HeliColors.canvasIvory)
            .navigationTitle("Rebalance Week")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundColor(HeliColors.greenInk)
                }
            }
        }
    }

    private func calculateProposals() -> ProposalsResult {
        let endWeek = PlanCore.dateAdd(currentWeek, 6)
        let evs = store.records().filter { $0.date >= currentWeek && $0.date <= endWeek }
        return PlanCore.proposals(evs, store.planningOptions())
    }

    private func caregiverLoadRow(name: String, before: Int, after: Int) -> some View {
        HStack {
            AvatarDisc(name: name, size: 24)
            Text(name)
                .font(HeliTypography.headline(13))
                .foregroundColor(HeliColors.greenInk)
            Spacer()
            HStack(spacing: 8) {
                Text("\(before)m")
                    .font(HeliTypography.monoTime(12))
                    .foregroundColor(HeliColors.mutedGray)
                Image(systemName: "arrow.right")
                    .font(.system(size: 10))
                    .foregroundColor(HeliColors.sageRule)
                Text("\(after)m")
                    .font(HeliTypography.monoTime(12))
                    .foregroundColor(after < before ? HeliColors.forestGreen : HeliColors.greenInk)
            }
        }
    }

    private func proposalRow(prop: RebalanceProposal) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(prop.title)
                    .font(HeliTypography.cardTitle(14))
                    .foregroundColor(HeliColors.greenInk)
                Spacer()
                Text("\(prop.date) · \(prop.time)")
                    .font(HeliTypography.monoTime(11))
                    .foregroundColor(HeliColors.mutedGray)
            }

            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    AvatarDisc(name: prop.from, size: 18)
                    Text(prop.from)
                        .font(HeliTypography.caption(11))
                        .foregroundColor(HeliColors.clayText)
                }

                Image(systemName: "arrow.right")
                    .font(.system(size: 10))
                    .foregroundColor(HeliColors.mutedGray)

                HStack(spacing: 4) {
                    AvatarDisc(name: prop.to, size: 18)
                    Text(prop.to)
                        .font(HeliTypography.caption(11))
                        .foregroundColor(HeliColors.forestGreen)
                }

                Spacer()

                if prop.saving > 0 {
                    Text("Saves \(prop.saving)m")
                        .font(HeliTypography.eyebrow(9))
                        .foregroundColor(HeliColors.forestGreen)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(HeliColors.forestTint)
                        .clipShape(Capsule())
                }
            }

            if !prop.reason.isEmpty {
                Text(prop.reason)
                    .font(HeliTypography.caption(11))
                    .foregroundColor(HeliColors.mutedGray)
            }
        }
        .padding(12)
        .background(HeliColors.cardWarmWhite)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(HeliColors.sageRule, lineWidth: 0.8))
    }

    private func applyProposals(proposals: ProposalsResult) {
        var all = store.records()
        let changesById = Dictionary(uniqueKeysWithValues: proposals.changes.map { ($0.id, $0.to) })
        for i in all.indices {
            if let newOwner = changesById[all[i].id] {
                all[i].owner = newOwner
                all[i].lead = newOwner
                all[i].tentative = false
            }
        }
        store.replaceRecords(all)
    }
}

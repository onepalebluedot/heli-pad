import SwiftUI

public struct FamilyView: View {
    @ObservedObject public var store: AppStore
    @StateObject private var viewModel = FamilyViewModel()
    @State private var showRulesSheet: Bool = false

    public init(store: AppStore) {
        self.store = store
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Masthead
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("HOUSEHOLD LOGISTICS")
                            .font(HeliTypography.eyebrow(10))
                            .foregroundColor(HeliColors.mutedGray)
                            .tracking(1.4)
                        Text("Family Setup")
                            .font(HeliTypography.mastheadDate(26))
                            .foregroundColor(HeliColors.greenInk)
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                // 1. Persistent Workload Distribution Card
                let loads = viewModel.caregiverLoads(store: store)
                FamilyWorkloadCardView(loads: loads, totalDrives: viewModel.totalDrives(store: store))

                // 2. Segmented Panel Switcher
                HStack(spacing: 6) {
                    ForEach(FamilyTab.allCases) { tab in
                        let isSelected = viewModel.selectedTab == tab
                        Button(action: { viewModel.selectedTab = tab }) {
                            Text(tab.rawValue)
                                .font(HeliTypography.chipLabel(12))
                                .foregroundColor(isSelected ? HeliColors.forestGreen : HeliColors.mutedGray)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(isSelected ? HeliColors.forestTint : HeliColors.cardWarmWhite)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(isSelected ? HeliColors.forestGreen : HeliColors.sageRule, lineWidth: isSelected ? 1.2 : 0.8)
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, 16)

                // 3. Active Panel Content
                switch viewModel.selectedTab {
                case .templates:
                    FamilyTemplatesView(
                        templates: store.templates,
                        suggestions: viewModel.suggestions(store: store),
                        onSelectTemplate: { tmpl in
                            viewModel.editingTemplate = tmpl
                            viewModel.showTemplateSheet = true
                        },
                        onAddTemplate: {
                            viewModel.editingTemplate = nil
                            viewModel.showTemplateSheet = true
                        },
                        onAdoptSuggestion: { sugg in
                            store.upsertTemplate(sugg)
                        }
                    )

                case .places:
                    FamilyPlacesView(
                        locations: store.locations,
                        caregivers: store.caregiverPeople(),
                        onSelectLocation: { loc in
                            viewModel.editingLocation = loc
                            viewModel.showLocationSheet = true
                        },
                        onAddLocation: {
                            viewModel.editingLocation = nil
                            viewModel.showLocationSheet = true
                        }
                    )

                case .kids:
                    let children = store.childPeople()
                    let kidName = viewModel.selectedKid.isEmpty ? (children.first?.name ?? "") : viewModel.selectedKid
                    let stats = viewModel.statsForKid(kid: kidName, store: store)

                    FamilyKidsStatsView(
                        children: children,
                        selectedKid: Binding(
                            get: { kidName },
                            set: { viewModel.selectedKid = $0 }
                        ),
                        stats: stats
                    )

                case .roster:
                    FamilyRosterView(
                        caregivers: store.caregiverPeople(),
                        loads: viewModel.driveCounts(store: store),
                        bufferMinutes: store.buffer,
                        peakTraffic: store.trafficMode,
                        dinnerRule: store.planningRules(for: PlanCore.currentMonday()),
                        onEditRules: {
                            showRulesSheet = true
                        }
                    )
                }

                Spacer().frame(height: 80)
            }
            .padding(.top, 8)
        }
        .background(HeliColors.canvasIvory.ignoresSafeArea())
        .sheet(isPresented: $viewModel.showTemplateSheet) {
            FamilyTemplateSheet(
                store: store,
                template: viewModel.editingTemplate,
                isNew: viewModel.editingTemplate == nil
            )
        }
        .sheet(isPresented: $viewModel.showLocationSheet) {
            FamilyLocationSheet(
                store: store,
                location: viewModel.editingLocation,
                isNew: viewModel.editingLocation == nil
            )
        }
        .sheet(isPresented: $showRulesSheet) {
            PlanPrioritiesSheet(store: store, week: PlanCore.currentMonday())
        }
    }
}

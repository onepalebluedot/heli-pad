import SwiftUI
import AssistantKit

public struct FamilyView: View {
    @ObservedObject public var store: AppStore
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel = FamilyViewModel()
    @StateObject private var suggestionStore: AssistantSuggestionStore
    /// Supplied by the app shell so suggestions use the same relay as the chat.
    public var assistant: AssistantHost?

    /// Changes when the signed-in caregiver or household changes, which is the
    /// signal to throw away another household's suggestions.
    private var sessionFingerprint: String {
        "\(store.currentUser)|\(store.cloudHouseholdID)"
    }
    @State private var showRulesSheet: Bool = false

    public init(store: AppStore, assistant: AssistantHost? = nil) {
        self.assistant = assistant
        _suggestionStore = StateObject(wrappedValue: AssistantSuggestionStore(store: store))
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
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
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
                        suggestions: suggestionStore.suggestions,
                        onSelectTemplate: { tmpl in
                            viewModel.editingTemplate = tmpl
                            viewModel.editingTemplateIsNew = false
                            viewModel.showTemplateSheet = true
                        },
                        onAddTemplate: {
                            viewModel.editingTemplate = nil
                            viewModel.editingTemplateIsNew = true
                            viewModel.showTemplateSheet = true
                        },
                        onReviewSuggestion: { suggestion in
                            // Opens the existing editor with an unsaved draft.
                            // Nothing is written until the user confirms there.
                            viewModel.editingTemplate = Self.draft(from: suggestion)
                            viewModel.editingTemplateIsNew = true
                            viewModel.showTemplateSheet = true
                        },
                        onDismissSuggestion: { suggestion in
                            guard let assistant else { return }
                            suggestionStore.dismiss(suggestion, session: assistant.currentSession)
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
        .modifier(SuggestionRefresh(
            store: suggestionStore,
            assistant: assistant,
            sessionFingerprint: sessionFingerprint,
            revision: store.contentRevision,
            shortcutCount: store.templates.count
        ))

    }

    /// Builds the unsaved draft the editor opens with. Every field comes from
    /// the detected pattern, so what the user reviews is what they have
    /// actually been doing.
    static func draft(from suggestion: ShortcutSuggestion) -> TemplateItem {
        let candidate = suggestion.candidate
        return TemplateItem(
            id: UUID().uuidString,
            title: suggestion.label,
            time: candidate.startTime,
            endTime: candidate.endTime,
            kids: candidate.kids,
            kid: candidate.kids.joined(separator: ", "),
            owner: candidate.owner ?? "TBD",
            location: candidate.location,
            mode: "Drive",
            duration: candidate.durationMinutes,
            category: candidate.category,
            weekdays: candidate.weekdays.isEmpty ? nil : candidate.weekdays
        )
    }
}

/// Drives shortcut-suggestion refreshes.
///
/// Local detection is cheap and runs whenever the household data could have
/// changed - a save bumps `localRevision`, a shortcut changes the count, the
/// app returns to the foreground. The model is only called from `.task`, and
/// only when `SuggestionPolicy` says it is worth it.
///
/// Extracted from `FamilyView.body` because chaining this many modifiers onto
/// an already large body defeats the SwiftUI type checker.
private struct SuggestionRefresh: ViewModifier {
    @ObservedObject var store: AssistantSuggestionStore
    @Environment(\.scenePhase) private var scenePhase
    let assistant: AssistantHost?
    let sessionFingerprint: String
    /// Bumped by every `AppStore.save()`, so this covers events created,
    /// edited or deleted, and recurrence changes, without rebuilding the
    /// record list on each render.
    let revision: Int
    let shortcutCount: Int

    func body(content: Content) -> some View {
        content
            .task(id: sessionFingerprint) {
                guard let assistant else { return }
                await store.refresh(
                    client: assistant.makeClient(),
                    session: assistant.currentSession
                )
            }
            .onChange(of: sessionFingerprint) { _, _ in
                // Household or caregiver changed: drop the previous
                // household's cards immediately.
                store.resetForSessionChange()
            }
            .onChange(of: revision) { _, _ in refreshLocally() }
            .onChange(of: shortcutCount) { _, _ in refreshLocally() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { refreshLocally() }
            }
    }

    private func refreshLocally() {
        guard let assistant else { return }
        store.refreshLocally(session: assistant.currentSession)
    }
}

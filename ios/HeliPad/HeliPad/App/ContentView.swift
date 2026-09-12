import SwiftUI
import AssistantUI

public enum MainTab: String, CaseIterable, Identifiable {
    case go = "Go"
    case plan = "Plan"
    case assistant = "Assistant"
    case family = "Family"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .go: return "bolt.fill"
        case .plan: return "calendar"
        // The speech bubble reads at tab size where the bubble-plus-calendar
        // composition used on a 56pt button would turn to mush.
        case .assistant: return "bubble.left.fill"
        case .family: return "person.2.fill"
        }
    }
}

public struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = AppStore.shared
    @State private var selectedTab: MainTab = .go
    /// One route, so two sheets can never race each other (N01). The previous
    /// pair of booleans could both be true at once.
    @State private var route: PresentedRoute?
    @StateObject private var assistant = AssistantHost(store: AppStore.shared)

    /// Presentation actions, as distinct from the three destinations. These do
    /// not change `selectedTab`, so dismissing one returns to the same screen,
    /// week, filter and scroll position.
    enum PresentedRoute: String, Identifiable, Equatable {
        case settings
        case profilePicker

        var id: String { rawValue }
    }

    public init() {}

    public var body: some View {
        ZStack(alignment: .bottom) {
            // Main surface switch
            VStack(spacing: 0) {
                topBar
                Group {
                    switch selectedTab {
                    case .go:
                        GoView(store: store)
                    case .plan:
                        PlanView(store: store)
                    case .assistant:
                        assistantDestination
                    case .family:
                        FamilyView(store: store)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(HeliColors.canvasIvory.ignoresSafeArea())

            // Custom Floating Bottom Navigation Bar
            bottomNavBar
        }
        .onChange(of: route) { previous, current in
            // Settings can change the service URL or token, so the engine is
            // rebuilt when that sheet closes rather than staying stale until
            // the next tab switch.
            if previous == .settings, current == nil, selectedTab == .assistant {
                assistant.reset()
                assistant.prepare()
            }
        }
        .sheet(item: $route) { presented in
            switch presented {
            case .settings:
                SettingsView(store: store)
            case .profilePicker:
                profilePickerSheet
            }
        }
        .onChange(of: selectedTab) { _, tab in
            // Built on first visit, and rebuilt if the caregiver or household
            // changed since last time.
            if tab == .assistant { assistant.prepare() }
        }
        .onChange(of: store.currentUser) { _, _ in
            // Switching caregiver drops the conversation, the engine's context
            // and any pending review with it.
            assistant.reset()
        }
        .task(id: scenePhase) {
            if scenePhase == .active {
                LocationService.shared.startUpdating()
                store.syncWithDeviceDate()
                await store.resumePendingSync()
                // Pick up whatever the other phone did while this one was away,
                // then keep watching for as long as we are on screen.
                await store.liveSyncTick()
                store.startLiveSync()
            } else {
                LocationService.shared.stopUpdating()
                store.stopLiveSync()
            }
        }
        .onReceive(LocationService.shared.$currentLocation) { location in
            guard location != nil else { return }
            store.refreshDepartureReminders()
        }
        .task {
            // Ask once, on the launch after the reminder is switched on, then
            // queue the upcoming departures.
            if store.notifyLeaveBy || store.notifyDriverNeeded {
                await NotificationService.shared.requestAuthorization()
                store.refreshDepartureReminders()
            }
            // Fetch live weather once on app load to conserve battery & network
            await store.updateLiveWeather()
        }
        .fullScreenCover(isPresented: $store.showOnboarding) {
            OnboardingView(store: store)
        }
    }

    // MARK: - Top Bar
    private var topBar: some View {
        HStack(alignment: .center) {
            // Active Caregiver Profile Switcher
            Button(action: { route = .profilePicker }) {
                HStack(spacing: 6) {
                    AvatarDisc(name: store.activeUser, size: 26)
                    Text(store.activeUser)
                        .font(HeliTypography.actionButton(13))
                        .foregroundColor(HeliColors.greenInk)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(HeliColors.mutedGray)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(HeliColors.cardWarmWhite)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(HeliColors.sageRule, lineWidth: 0.8))
            }

            Spacer()

            // App Brand
            Text("VINCENT - PAD")
                .font(HeliTypography.eyebrow(11))
                .foregroundColor(HeliColors.forestGreen)
                .tracking(2.0)

            Spacer()

            // Settings Gear
            Button(action: { route = .settings }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(HeliColors.greenInk)
                    .frame(width: 36, height: 36)
                    .background(HeliColors.cardWarmWhite)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(HeliColors.sageRule, lineWidth: 0.8))
            }
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 6)
        .background(HeliColors.canvasIvory)
    }

    // MARK: - Bottom Navigation
    //
    // Four equal destinations. The assistant is an ordinary tab rather than a
    // raised launcher, so it keeps its scroll position and draft when you
    // switch away and back, and there is no floating ornament to clip.
    private var bottomNavBar: some View {
        HStack(spacing: 0) {
            ForEach(MainTab.allCases) { tab in
                navDestination(tab)
            }
        }
        .frame(height: 60)
        .padding(.horizontal, 8)
        .background(HeliColors.cardWarmWhite)
        .clipShape(RoundedRectangle(cornerRadius: 26))
        .overlay(
            RoundedRectangle(cornerRadius: 26)
                .stroke(HeliColors.sageRule, lineWidth: 0.8)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 4)
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    /// Height the floating bar occupies, so a destination can inset its own
    /// content out from under it.
    static let bottomBarInset: CGFloat = 80

    @ViewBuilder
    private func navDestination(_ tab: MainTab) -> some View {
        let isSelected = selectedTab == tab
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { selectedTab = tab }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: tab.iconName)
                    .font(.system(size: 15, weight: isSelected ? .bold : .medium))
                    .foregroundColor(isSelected ? HeliColors.forestGreen : HeliColors.mutedGray)
                if isSelected {
                    Text(tab.rawValue)
                        .font(HeliTypography.actionButton(12.5))
                        .foregroundColor(HeliColors.forestGreen)
                        .fixedSize()
                }
            }
            .padding(.horizontal, isSelected ? 12 : 10)
            .padding(.vertical, 9)
            .background(isSelected ? HeliColors.forestTint : Color.clear)
            .clipShape(Capsule())
            // Keeps the tap target at 44 points even though the pill is
            // shorter than that.
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel(tab.rawValue)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - Assistant

    @ViewBuilder
    private var assistantDestination: some View {
        if let chat = assistant.chat {
            AssistantChatView(
                model: chat,
                presentation: .embedded(bottomInset: Self.bottomBarInset),
                onOpenEvent: { _, date in
                    // Only the displayed week can be navigated to: `weekStart`
                    // is private(set) on AppStore and follows the device date,
                    // so there is no API to jump to another week yet. Rather
                    // than switch tabs and land the user on the wrong week, an
                    // out-of-week link does nothing and leaves the list up.
                    guard let day = PlanCore.dayOffset(from: store.weekStart, to: date),
                          (0...6).contains(day) else { return }
                    store.activeDay = day
                    selectedTab = .plan
                }
            )
        } else {
            assistantUnavailable
        }
    }

    private var assistantUnavailable: some View {
        VStack(spacing: 14) {
            Image(systemName: "bubble.left")
                .font(.system(size: 30, weight: .light))
                .foregroundColor(HeliColors.mutedGray)
            Text("Assistant unavailable")
                .font(HeliTypography.serifTitle(22, weight: .medium))
                .foregroundColor(HeliColors.forestGreen)
            Text(assistant.unavailableReason ?? "The assistant is not set up on this device.")
                .font(HeliTypography.body(13.5))
                .foregroundColor(HeliColors.mutedGray)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            // A dead end with no way out is worse than the error itself.
            Button(action: { route = .settings }) {
                HStack(spacing: 6) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12))
                    Text("Open Settings \u{203A} Assistant")
                        .font(HeliTypography.buttonLabel(13))
                }
                .foregroundColor(HeliColors.forestGreen)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(HeliColors.forestTint)
                .clipShape(Capsule())
            }
            .padding(.top, 2)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(HeliColors.canvasIvory)
    }

    // MARK: - Profile Picker Sheet
    private var profilePickerSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Switch Active Profile")
                    .font(HeliTypography.headline(18))
                    .foregroundColor(HeliColors.greenInk)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                Text("Controls whose schedule and countdown dial are prioritized on Go.")
                    .font(HeliTypography.caption(12))
                    .foregroundColor(HeliColors.mutedGray)
                    .padding(.horizontal, 20)

                VStack(spacing: 8) {
                    ForEach(store.caregiverPeople()) { (p: Person) in
                        Button(action: {
                            if (try? store.setActiveUser(p.name)) != nil {
                                route = nil
                            }
                        }) {
                            HStack {
                                AvatarDisc(name: p.name, size: 32)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.name)
                                        .font(HeliTypography.headline(14))
                                        .foregroundColor(HeliColors.greenInk)
                                    Text(p.role.capitalized)
                                        .font(HeliTypography.caption(11))
                                        .foregroundColor(HeliColors.mutedGray)
                                }
                                Spacer()
                                if store.currentUser == p.name {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(HeliColors.forestGreen)
                                }
                            }
                            .padding(14)
                            .background(HeliColors.cardWarmWhite)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(store.currentUser == p.name ? HeliColors.forestGreen : HeliColors.sageRule, lineWidth: store.currentUser == p.name ? 1.5 : 0.8))
                        }
                    }
                }
                .padding(.horizontal, 16)

                Spacer()
            }
            .background(HeliColors.canvasIvory)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { route = nil }
                        .foregroundColor(HeliColors.greenInk)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

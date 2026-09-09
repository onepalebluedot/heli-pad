import SwiftUI

public enum MainTab: String, CaseIterable, Identifiable {
    case go = "Go"
    case plan = "Plan"
    case family = "Family"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .go: return "bolt.fill"
        case .plan: return "calendar"
        case .family: return "person.2.fill"
        }
    }
}

public struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = AppStore.shared
    @State private var selectedTab: MainTab = .go
    @State private var showSettings: Bool = false
    @State private var showProfilePicker: Bool = false

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
        .sheet(isPresented: $showSettings) {
            SettingsView(store: store)
        }
        .sheet(isPresented: $showProfilePicker) {
            profilePickerSheet
        }
        .task(id: scenePhase) {
            if scenePhase == .active {
                store.syncWithDeviceDate()
                await store.resumePendingSync()
                // Pick up whatever the other phone did while this one was away,
                // then keep watching for as long as we are on screen.
                await store.liveSyncTick()
                store.startLiveSync()
            } else {
                store.stopLiveSync()
            }
        }
        .task {
            // Ask once, on the launch after the reminder is switched on, then
            // queue the upcoming departures.
            if store.notifyLeaveBy {
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
            Button(action: { showProfilePicker = true }) {
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
            Button(action: { showSettings = true }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(HeliColors.greenInk)
                    .frame(width: 36, height: 36)
                    .background(HeliColors.cardWarmWhite)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(HeliColors.sageRule, lineWidth: 0.8))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 6)
        .background(HeliColors.canvasIvory)
    }

    // MARK: - Custom Warm White Bottom Nav Bar
    private var bottomNavBar: some View {
        HStack(spacing: 0) {
            ForEach(MainTab.allCases, id: \.self) { tab in
                let isSelected = selectedTab == tab
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = tab
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: tab.iconName)
                            .font(.system(size: 16, weight: isSelected ? .bold : .medium))
                            .foregroundColor(isSelected ? HeliColors.forestGreen : HeliColors.mutedGray)

                        if isSelected {
                            Text(tab.rawValue)
                                .font(HeliTypography.actionButton(13))
                                .foregroundColor(HeliColors.forestGreen)
                        }
                    }
                    .padding(.horizontal, isSelected ? 16 : 12)
                    .padding(.vertical, 10)
                    .background(isSelected ? HeliColors.forestTint : Color.clear)
                    .clipShape(Capsule())
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 60)
        .padding(.horizontal, 14)
        .background(HeliColors.cardWarmWhite)
        .clipShape(RoundedRectangle(cornerRadius: 26))
        .overlay(
            RoundedRectangle(cornerRadius: 26)
                .stroke(HeliColors.sageRule, lineWidth: 0.8)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 4)
        .padding(.horizontal, 24)
        .padding(.bottom, 10)
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
                            store.currentUser = p.name
                            showProfilePicker = false
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
                    Button("Done") { showProfilePicker = false }
                        .foregroundColor(HeliColors.greenInk)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

import SwiftUI

public struct GoView: View {
    @ObservedObject var store: AppStore
    @StateObject private var viewModel: GoViewModel
    @Environment(\.scenePhase) private var scenePhase

    public init(store: AppStore) {
        self.store = store
        _viewModel = StateObject(wrappedValue: GoViewModel(store: store))
    }

    public var body: some View {
        let viewData = viewModel.computeView(store: store)
        let heroEvent = viewData.live >= 0 ? viewData.mine[viewData.live].event : nil
        let options = store.planningOptions()

        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 14) {
                // Masthead (Date + Weather)
                GoMastheadView(todayIdx: viewData.todayIdx, store: store)

                // Dial Hero Card
                GoDialCardView(
                    event: heroEvent,
                    now: viewData.now,
                    options: options,
                    liveDriveTime: store.realTimeDeviceEta,
                    isDeviceLocationLive: LocationService.shared.isUsingDeviceFix,
                    restingState: viewData.restingState,
                    onEdit: {
                        if let hero = heroEvent {
                            viewModel.selectedStopForEdit = hero
                            viewModel.showAddEditSheet = true
                        }
                    },
                    onToggleDone: {
                        if let hero = heroEvent {
                            toggleStopDone(hero)
                        }
                    },
                    onDirections: {
                        // Launch Apple Maps turn-by-turn navigation
                        if let hero = heroEvent {
                            launchMaps(for: hero)
                        }
                    }
                )
                .padding(.horizontal, 20)

                // Scope Row (Caregiver & Kid Segments + Swappable Drawer)
                GoScopeRowView(store: store)

                // Panel Header (Dynamic Title + Completion Pips + Swap Toggle)
                GoPanelHeadView(store: store, viewData: viewData)

                // Panel Body (Rail Timeline or Wheel-Time Load Distribution)
                if store.goPanel == "rail" {
                    GoRailTimelineView(
                        events: viewData.listed,
                        heroId: heroEvent?.id,
                        onSelect: { stop in
                            viewModel.selectedStopForEdit = stop
                            viewModel.showAddEditSheet = true
                        },
                        onToggleDone: { stop in
                            toggleStopDone(stop)
                        },
                        onAddStop: {
                            viewModel.selectedStopForEdit = nil
                            viewModel.showAddEditSheet = true
                        }
                    )
                } else {
                    GoWheelTimeView(
                        drivers: viewData.drivers,
                        currentUser: store.currentUser
                    )
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 90) // Clear custom bottom navigation
        }
        .background(HeliColors.canvasIvory)
        .onAppear {
            if scenePhase == .active { viewModel.startClock() }
            if let hero = heroEvent {
                Task {
                    _ = await store.calculateDeviceDriveTime(for: hero)
                }
            }
        }
        .onDisappear {
            viewModel.stopClock()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { viewModel.startClock() } else { viewModel.stopClock() }
        }
        .onChange(of: store.timeZone) { _, _ in viewModel.updateClock() }
        .onChange(of: store.mockTime) { _, _ in viewModel.updateClock() }
        .onChange(of: heroEvent?.id) { _, _ in
            if let hero = heroEvent {
                Task {
                    _ = await store.calculateDeviceDriveTime(for: hero)
                }
            }
        }
        .onReceive(LocationService.shared.$currentLocation) { newLoc in
            guard newLoc != nil, let hero = heroEvent else { return }
            Task {
                _ = await store.calculateDeviceDriveTime(for: hero)
            }
        }
        .sheet(isPresented: $viewModel.showAddEditSheet) {
            GoAddEditStopSheet(
                store: store,
                existingStop: viewModel.selectedStopForEdit
            )
        }
    }

    private func toggleStopDone(_ stop: TaskRecord) {
        store.toggleEventDone(id: stop.id)
    }

    private func launchMaps(for stop: TaskRecord) {
        if let lat = stop.latitude, let lon = stop.longitude {
            if let url = URL(string: "http://maps.apple.com/?daddr=\(lat),\(lon)&dirflg=d") {
                UIApplication.shared.open(url)
                return
            }
        }
        if let coord = store.destinationCoordinate(for: stop) {
            if let url = URL(string: "http://maps.apple.com/?daddr=\(coord.latitude),\(coord.longitude)&dirflg=d") {
                UIApplication.shared.open(url)
                return
            }
        }
        let dest = (stop.formattedAddress?.isEmpty == false ? stop.formattedAddress! : stop.location)
        let query = (dest.isEmpty ? store.homeAddress : dest).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "http://maps.apple.com/?daddr=\(query)&dirflg=d") {
            UIApplication.shared.open(url)
        }
    }
}

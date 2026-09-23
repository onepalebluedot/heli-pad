import SwiftUI

public struct GoView: View {
    @ObservedObject var store: AppStore
    @StateObject private var viewModel: GoViewModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The hero stop playing its done sequence. Held until the hand-off has
    /// finished, so the outgoing card keeps its sealed look and stays on top
    /// of the incoming one while it leaves.
    @State private var completingId: String?

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

                // Dial Hero Card. Keyed by the stop it shows, so a change of
                // hero is a hand-off between two cards rather than one card
                // rewriting itself in place.
                ZStack {
                    GoDialCardView(
                        event: heroEvent,
                        now: viewData.now,
                        options: options,
                        liveDriveTime: store.realTimeDeviceEta,
                        isDeviceLocationLive: LocationService.shared.isUsingDeviceFix,
                        restingState: viewData.restingState,
                        isCompleting: heroEvent != nil && heroEvent?.id == completingId,
                        onEdit: {
                            if let hero = heroEvent {
                                viewModel.selectedStopForEdit = hero
                                viewModel.showAddEditSheet = true
                            }
                        },
                        onToggleDone: {
                            if let hero = heroEvent {
                                toggleStopDone(hero, isHero: true)
                            }
                        },
                        onDirections: {
                            // Launch Apple Maps turn-by-turn navigation
                            if let hero = heroEvent {
                                launchMaps(for: hero)
                            }
                        }
                    )
                    .id(heroEvent?.id ?? "resting")
                    .zIndex(heroEvent?.id == completingId ? 1 : 0)
                    .transition(reduceMotion ? .opacity : .goHeroHandoff)
                }
                .padding(.horizontal, 20)

                if !viewData.looseEndEvents.isEmpty {
                    GoLooseEndsView(
                        events: viewData.looseEndEvents,
                        onDone: { stop in
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                                store.setEventDone(id: stop.id, done: true)
                            }
                        },
                        onOpen: { stop in
                            viewModel.selectedStopForEdit = stop
                            viewModel.showAddEditSheet = true
                        }
                    )
                    .padding(.horizontal, 20)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

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
                            toggleStopDone(stop, isHero: stop.id == heroEvent?.id)
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
                await store.refreshDeviceDriveTime(forMovedEvent: hero)
            }
        }
        .sheet(isPresented: $viewModel.showAddEditSheet) {
            GoAddEditStopSheet(
                store: store,
                existingStop: viewModel.selectedStopForEdit
            )
        }
    }

    /// Finishing the hero plays out in two beats: the card seals itself —
    /// green floods from the button, the dial closes, a check is drawn and the
    /// name struck through — then it is filed away as the next stop rises into
    /// its place. Anything else, including reopening, just changes.
    private func toggleStopDone(_ stop: TaskRecord, isHero: Bool = false) {
        guard isHero, !stop.done, completingId == nil else {
            if completingId == nil { store.toggleEventDone(id: stop.id) }
            return
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        guard !reduceMotion else {
            withAnimation(.easeInOut(duration: 0.25)) {
                store.setEventDone(id: stop.id, done: true)
            }
            return
        }
        completingId = stop.id
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 750_000_000)
            withAnimation(.spring(response: 0.55, dampingFraction: 0.8)) {
                store.setEventDone(id: stop.id, done: true)
            }
            // Released once the outgoing card is gone; until then it keeps the
            // sealed look and sits above the card arriving under it.
            try? await Task.sleep(nanoseconds: 650_000_000)
            completingId = nil
        }
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

/// Stops that ended without being ticked off. They used to hold the hero until
/// someone dealt with them; now they wait here, one tap from done, while the
/// hero gets on with what is next.
struct GoLooseEndsView: View {
    var events: [TaskRecord]
    var onDone: (TaskRecord) -> Void
    var onOpen: (TaskRecord) -> Void

    private static let shownLimit = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text("STILL OPEN")
                    .font(HeliTypography.eyebrow(10))
                    .foregroundColor(HeliColors.clayText)
                    .tracking(1.4)
                Text("\(events.count)")
                    .font(HeliTypography.eyebrow(10))
                    .foregroundColor(HeliColors.clayText)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(HeliColors.clayWash)
                    .clipShape(Capsule())
                Spacer(minLength: 0)
            }
            .padding(.top, 10)
            .padding(.bottom, 2)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(events.count) earlier \(events.count == 1 ? "stop is" : "stops are") still open")

            ForEach(Array(events.prefix(Self.shownLimit))) { stop in
                row(stop)
                    .transition(.opacity.combined(with: .move(edge: .leading)))
                if stop.id != events.prefix(Self.shownLimit).last?.id {
                    Rectangle().fill(HeliColors.sageRule).frame(height: 0.8)
                }
            }

            if events.count > Self.shownLimit {
                Text("\(events.count - Self.shownLimit) more in the timeline below")
                    .font(HeliTypography.caption(11.5))
                    .foregroundColor(HeliColors.mutedGray)
                    .padding(.vertical, 8)
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 4)
        .background(HeliColors.cardWarmWhite)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(HeliColors.sageRule, lineWidth: 0.8)
        )
    }

    private func row(_ stop: TaskRecord) -> some View {
        HStack(spacing: 8) {
            Button { onOpen(stop) } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(stop.title)
                        .font(HeliTypography.railTitle(14))
                        .foregroundColor(HeliColors.greenInk)
                        .lineLimit(1)
                    Text("Ended \(TimeFormat.formatTime(stop.endTime)) · \(stop.owner)")
                        .font(HeliTypography.railMeta(11.5))
                        .foregroundColor(HeliColors.mutedGray)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(stop.title), ended \(TimeFormat.formatTime(stop.endTime))")
            .accessibilityHint("Opens the stop")

            Button { onDone(stop) } label: {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                    Text("Done")
                        .font(HeliTypography.buttonLabel(13))
                }
                .foregroundColor(HeliColors.forestGreen)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(HeliColors.forestTint)
                .clipShape(Capsule())
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Mark \(stop.title) done")
        }
    }
}

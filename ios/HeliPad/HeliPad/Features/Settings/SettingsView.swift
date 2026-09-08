import SwiftUI
import CoreLocation

public struct SettingsView: View {
    @ObservedObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var expandedSection: String? = nil
    @State private var editingName: [String: String] = [:]
    @State private var homeAddressInput: String = ""
    @State private var errorMessage: String? = nil
    @State private var showResetConfirm: Bool = false
    @State private var toastMessage: String? = nil
    @State private var showIntegrationsGuide: Bool = false
    @State private var showGoogleApiKey: Bool = false
    @State private var showNeonConnString: Bool = false
    @State private var isTestingGoogle: Bool = false
    @State private var isTestingNeon: Bool = false
    @State private var showCloudDownloadConfirm = false
    @State private var isSyncingNeon: Bool = false
    @State private var googleStatusText: String? = nil
    @State private var neonStatusText: String? = nil

    // Home address autocomplete state
    @State private var homePredictions: [PlacePrediction] = []
    @State private var isSearchingHome: Bool = false
    @State private var isSelectingHome: Bool = false
    @State private var homeSearchTask: Task<Void, Never>? = nil
    @State private var homeLatitude: Double? = nil
    @State private var homeLongitude: Double? = nil
    @State private var homePlaceId: String? = nil

    public init(store: AppStore) {
        self.store = store
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    accordionSection(id: "home", title: "Home address", icon: "house") {
                        homeSectionContent
                    }

                    accordionSection(id: "caregivers", title: "Caregivers", icon: "users-round") {
                        caregiversSectionContent
                    }

                    accordionSection(id: "children", title: "Children", icon: "user-round") {
                        childrenSectionContent
                    }

                    accordionSection(id: "connections", title: "Connections", icon: "calendar-days") {
                        connectionsSectionContent
                    }

                    accordionSection(id: "alerts", title: "Alerts & device", icon: "moon") {
                        alertsSectionContent
                    }

                    accordionSection(id: "travel", title: "Travel & timing", icon: "car-front") {
                        travelSectionContent
                    }

                    accordionSection(id: "account", title: "Account", icon: "users") {
                        accountSectionContent
                    }

                    accordionSection(id: "integrations", title: "Integrations & Cloud", icon: "sparkles") {
                        integrationsSectionContent
                    }

                    accordionSection(id: "data", title: "Your data", icon: "list") {
                        dataSectionContent
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
            }
            .background(HeliColors.canvasIvory)
            .sheet(isPresented: $showIntegrationsGuide) {
                IntegrationsGuideSheet()
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .font(HeliTypography.buttonLabel(15))
                        .foregroundColor(HeliColors.forestGreen)
                    }
                }
            }
            .alert("Schedule Reset", isPresented: $showResetConfirm) {
                Button("Reset to Defaults", role: .destructive) {
                    store.resetSchedule()
                    toastMessage = "Schedule reset to default sample week."
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will restore the default August sample week and clear custom event edits.")
            }
            .confirmationDialog("Replace this device's household with the cloud copy?", isPresented: $showCloudDownloadConfirm, titleVisibility: .visible) {
                Button("Download and replace local household", role: .destructive) { downloadNeonHousehold() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Local edits will be replaced. Copy any changes you want to keep before continuing.")
            }
            .overlay(alignment: .bottom) {
                if let msg = toastMessage {
                    Text(msg)
                        .font(HeliTypography.body(13))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(HeliColors.greenInk)
                        .clipShape(Capsule())
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                toastMessage = nil
                            }
                        }
                }
            }
        }
    }

    // MARK: - Accordion Header Component

    private func accordionSection<Content: View>(
        id: String,
        title: String,
        icon: String,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        let isOpen = expandedSection == id

        return VStack(spacing: 0) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.22)) {
                    expandedSection = isOpen ? nil : id
                }
            }) {
                HStack(spacing: 12) {
                    HeliIcon(icon, size: 16)
                        .foregroundColor(HeliColors.forestGreen)
                    Text(title)
                        .font(HeliTypography.railTitle(15))
                        .foregroundColor(HeliColors.greenInk)
                    Spacer()
                    Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(HeliColors.mutedGray)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(HeliColors.cardWarmWhite)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(HeliColors.sageRule.opacity(0.7), lineWidth: 0.8)
                )
            }

            if isOpen {
                VStack(alignment: .leading, spacing: 14) {
                    content()
                }
                .padding(16)
                .background(HeliColors.cardWarmWhite.opacity(0.85))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Section 1: Home Address

    private var homeSectionContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Home location name: \(store.home())")
                .font(HeliTypography.body(13))
                .foregroundColor(HeliColors.mutedGray)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    TextField("Home address (e.g. 25622 Coach Ln)", text: $homeAddressInput)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: homeAddressInput) { _, val in
                            if isSelectingHome {
                                isSelectingHome = false
                                return
                            }
                            homeSearchTask?.cancel()
                            let query = val.trimmingCharacters(in: .whitespaces)
                            guard query.count >= 2 else {
                                homePredictions = []
                                isSearchingHome = false
                                return
                            }
                            isSearchingHome = true
                            homeSearchTask = Task {
                                try? await Task.sleep(nanoseconds: 180_000_000)
                                if Task.isCancelled { return }
                                // Search unconstrained nationwide so addresses outside local area resolve immediately
                                let results = await GoogleMapsService.shared.autocompletePlaces(
                                    query: query,
                                    apiKey: store.googleMapsApiKey,
                                    locationBias: nil,
                                    savedLocations: []
                                )
                                if !Task.isCancelled {
                                    await MainActor.run {
                                        self.homePredictions = results
                                        self.isSearchingHome = false
                                    }
                                }
                            }
                        }

                    if isSearchingHome {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                }

                // Autocomplete Suggestions Dropdown
                if !homePredictions.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(homePredictions) { pred in
                            Button(action: {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                isSelectingHome = true
                                let fullAddr = pred.secondaryText.isEmpty ? pred.primaryText : "\(pred.primaryText), \(pred.secondaryText)"
                                homeAddressInput = fullAddr
                                homeLatitude = pred.latitude
                                homeLongitude = pred.longitude
                                homePlaceId = pred.placeId
                                homePredictions = []

                                Task {
                                    if let details = try? await GoogleMapsService.shared.fetchPlaceDetails(
                                        placeId: pred.placeId,
                                        apiKey: store.googleMapsApiKey,
                                        fallbackName: pred.primaryText,
                                        fallbackAddress: fullAddr
                                    ) {
                                        await MainActor.run {
                                            if !details.formattedAddress.isEmpty && details.formattedAddress != "Address unavailable" {
                                                self.homeAddressInput = details.formattedAddress
                                            }
                                            self.homeLatitude = details.latitude
                                            self.homeLongitude = details.longitude
                                        }
                                    }
                                }
                            }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "mappin.circle.fill")
                                        .foregroundColor(HeliColors.forestGreen)
                                        .font(.system(size: 15))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(pred.primaryText)
                                            .font(HeliTypography.cardTitle(13))
                                            .foregroundColor(HeliColors.greenInk)
                                            .lineLimit(1)
                                        if !pred.secondaryText.isEmpty {
                                            Text(pred.secondaryText)
                                                .font(HeliTypography.caption(11))
                                                .foregroundColor(HeliColors.mutedGray)
                                                .lineLimit(1)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.up.left")
                                        .font(.system(size: 11))
                                        .foregroundColor(HeliColors.mutedGray)
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 10)
                                .background(Color.white)
                            }
                            .buttonStyle(.plain)

                            if pred.id != homePredictions.last?.id {
                                Divider()
                            }
                        }
                    }
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(HeliColors.sageRule, lineWidth: 0.8)
                    )
                    .shadow(color: Color.black.opacity(0.06), radius: 6, y: 3)
                    .padding(.top, 2)
                }
            }

            if let lat = homeLatitude, let lng = homeLongitude {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(HeliColors.forestGreen)
                        .font(.system(size: 12))
                    Text("GPS Coordinates Verified: \(String(format: "%.4f", lat)), \(String(format: "%.4f", lng))")
                        .font(HeliTypography.caption(11))
                        .foregroundColor(HeliColors.forestGreen)
                }
            }

            Button("Save Address") {
                do {
                    try store.setHomeAddress(
                        homeAddressInput,
                        latitude: homeLatitude,
                        longitude: homeLongitude,
                        placeId: homePlaceId
                    )
                    toastMessage = "Home address and GPS updated."
                    Task {
                        await store.updateLiveWeather(forceRefresh: true)
                    }
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(HeliColors.forestGreen)
        }
        .onAppear {
            homeAddressInput = store.homeAddress
            if let homeLoc = store.locations.first(where: { $0.name == store.home() }) {
                homeLatitude = homeLoc.latitude
                homeLongitude = homeLoc.longitude
                homePlaceId = homeLoc.placeId
            }
        }
    }

    // MARK: - Section 2: Caregivers

    private var caregiversSectionContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(store.people(kind: "caregiver")) { p in
                HStack(spacing: 10) {
                    AvatarDisc(name: p.name, size: 30)
                    TextField("Name", text: Binding(
                        get: { editingName[p.id] ?? p.name },
                        set: { editingName[p.id] = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        if let newName = editingName[p.id], newName != p.name {
                            do {
                                try store.renamePerson(id: p.id, value: newName)
                                toastMessage = "Renamed to \(newName)."
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                        }
                    }

                    Button(role: .destructive, action: {
                        store.removePerson(id: p.id)
                    }) {
                        Image(systemName: "trash")
                            .foregroundColor(HeliColors.warningClay)
                    }
                }
            }

            Button("+ Add Caregiver") {
                _ = store.addPerson(kind: "caregiver")
            }
            .font(HeliTypography.buttonLabel(14))
            .foregroundColor(HeliColors.forestGreen)
        }
    }

    // MARK: - Section 3: Children

    private var childrenSectionContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(store.people(kind: "child")) { c in
                HStack(spacing: 10) {
                    AvatarDisc(name: c.name, size: 30, isKid: true)
                    TextField("Name", text: Binding(
                        get: { editingName[c.id] ?? c.name },
                        set: { editingName[c.id] = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        if let newName = editingName[c.id], newName != c.name {
                            do {
                                try store.renamePerson(id: c.id, value: newName)
                                toastMessage = "Renamed child to \(newName)."
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                        }
                    }

                    Button(role: .destructive, action: {
                        store.removePerson(id: c.id)
                    }) {
                        Image(systemName: "trash")
                            .foregroundColor(HeliColors.warningClay)
                    }
                }
            }

            Button("+ Add Child") {
                _ = store.addPerson(kind: "child")
            }
            .font(HeliTypography.buttonLabel(14))
            .foregroundColor(HeliColors.forestGreen)
        }
    }

    // MARK: - Section 4: Connections

    private var connectionsSectionContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Calendar integration is currently read-only in v1 per SYSTEM.md.")
                .font(HeliTypography.body(12.5))
                .foregroundColor(HeliColors.mutedGray)

            Toggle("Google Calendar (Preview)", isOn: Binding(
                get: { store.connections["google"] ?? false },
                set: { store.connections["google"] = $0 }
            ))
            Toggle("Apple Calendar (EventKit)", isOn: Binding(
                get: { store.connections["apple"] ?? false },
                set: { store.connections["apple"] = $0 }
            ))
        }
    }

    // MARK: - Section 5: Alerts & Device

    private var alertsSectionContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(
                "Leave-by departure reminder",
                isOn: Binding(
                    get: { store.notifyLeaveBy },
                    set: { wantsReminders in
                        store.notifyLeaveBy = wantsReminders
                        store.save()
                        Task {
                            if wantsReminders {
                                await NotificationService.shared.requestAuthorization()
                                store.refreshDepartureReminders()
                            } else {
                                await NotificationService.shared.cancelAll()
                            }
                        }
                    }
                )
            )
            Text("Nudges you \(NotificationService.leadMinutes) minutes before each stop starts.")
                .font(HeliTypography.caption(11))
                .foregroundColor(HeliColors.mutedGray)
            Toggle("Driver needed alert (12h prior)", isOn: $store.notifyDriverNeeded)
            Toggle("Crew informed on reassignments", isOn: $store.notifyCrew)

            HStack {
                Text("Time Zone")
                Spacer()
                Text(store.timeZone == "device" ? "Device Local" : store.timeZone)
                    .foregroundColor(HeliColors.mutedGray)
            }
        }
    }

    // MARK: - Section 6: Travel & Timing

    private var travelSectionContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Stepper("Arrival buffer: \(store.buffer) min", value: $store.buffer, in: 0...45)
            Toggle("Traffic-aware peak adjustment (1.15x)", isOn: $store.trafficMode)
            Toggle("Dinner protection window (6:30 PM)", isOn: $store.dinnerProtection)
        }
    }

    // MARK: - Section 7: Account

    private var accountSectionContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Switch active caregiver profile:")
                .font(HeliTypography.body(13))
                .foregroundColor(HeliColors.mutedGray)

            Picker("Active Caregiver", selection: $store.currentUser) {
                Text("All (Family)").tag("All")
                ForEach(store.caregivers(), id: \.self) { name in
                    Text(name).tag(name)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - Section: Integrations & Cloud

    private var integrationsSectionContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Setup Guide Action Banner
            Button(action: { showIntegrationsGuide = true }) {
                HStack(spacing: 12) {
                    Image(systemName: "book.pages.fill")
                        .font(.system(size: 16))
                        .foregroundColor(HeliColors.forestGreen)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("3rd-Party Setup & API Key Guide")
                            .font(HeliTypography.railTitle(14))
                            .foregroundColor(HeliColors.greenInk)
                        Text("Step-by-step instructions for Google Cloud & Neon")
                            .font(HeliTypography.caption(12))
                            .foregroundColor(HeliColors.mutedGray)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(HeliColors.mutedGray)
                }
                .padding(12)
                .background(HeliColors.forestTint)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)

            // 1. Google Maps Platform
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Google Maps Platform")
                        .font(HeliTypography.railTitle(14))
                        .foregroundColor(HeliColors.greenInk)
                    Spacer()
                    let hasKey = !store.googleMapsApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    Text(hasKey ? "Key Configured" : "MapKit Fallback")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(hasKey ? HeliColors.forestGreen : HeliColors.mutedGray)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background((hasKey ? HeliColors.forestTint : Color.black.opacity(0.05)))
                        .clipShape(Capsule())
                }

                Text("Enables Places autocomplete, venue search, and real-time traffic route analysis. If left empty, Apple MapKit is used.")
                    .font(HeliTypography.caption(12))
                    .foregroundColor(HeliColors.mutedGray)

                HStack(spacing: 8) {
                    if showGoogleApiKey {
                        TextField("AIzaSy...", text: Binding(
                            get: { store.googleMapsApiKey },
                            set: {
                                store.googleMapsApiKey = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                                store.save()
                            }
                        ))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(size: 13, design: .monospaced))
                    } else {
                        SecureField("AIzaSy...", text: Binding(
                            get: { store.googleMapsApiKey },
                            set: {
                                store.googleMapsApiKey = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                                store.save()
                            }
                        ))
                        .font(.system(size: 13, design: .monospaced))
                    }

                    Button(action: { showGoogleApiKey.toggle() }) {
                        Image(systemName: showGoogleApiKey ? "eye.slash" : "eye")
                            .font(.system(size: 13))
                            .foregroundColor(HeliColors.mutedGray)
                    }
                    .buttonStyle(.plain)
                }
                .padding(10)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(HeliColors.sageRule, lineWidth: 0.8)
                )

                HStack(spacing: 10) {
                    Button(action: testGoogleMaps) {
                        HStack(spacing: 6) {
                            if isTestingGoogle {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 12))
                            }
                            Text(isTestingGoogle ? "Testing..." : "Test Places & Route")
                                .font(HeliTypography.buttonLabel(13))
                        }
                        .foregroundColor(HeliColors.forestGreen)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(HeliColors.forestTint)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(isTestingGoogle)

                    if let status = googleStatusText {
                        Text(status)
                            .font(HeliTypography.caption(12))
                            .foregroundColor(status.contains("✓") ? HeliColors.forestGreen : HeliColors.warningClay)
                            .lineLimit(2)
                    }
                }
            }

            Divider().overlay(HeliColors.sageRule)

            // 2. Device Location / GPS
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Device GPS & Real-Time Location")
                        .font(HeliTypography.railTitle(14))
                        .foregroundColor(HeliColors.greenInk)
                    Spacer()
                    let authorized = LocationService.shared.isAuthorized
                    Text(authorized ? "GPS Active" : "Not Authorized")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(authorized ? HeliColors.forestGreen : HeliColors.warningClay)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background((authorized ? HeliColors.forestTint : HeliColors.warningClay.opacity(0.12)))
                        .clipShape(Capsule())
                }

                Text("Enables dynamic live countdowns and drive times to your next stop calculated directly from where you are standing.")
                    .font(HeliTypography.caption(12))
                    .foregroundColor(HeliColors.mutedGray)

                if LocationService.shared.isSimulatorDefaultSF {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 6) {
                            Image(systemName: "laptopcomputer")
                                .foregroundColor(HeliColors.warningClay)
                                .font(.system(size: 13))
                            Text("iOS Simulator Location (San Francisco)")
                                .font(HeliTypography.cardTitle(12))
                                .foregroundColor(HeliColors.greenInk)
                        }
                        Text("Apple Simulator defaults GPS to San Francisco, CA. HeliPad automatically anchors device location to your Home Address (\(store.homeAddress.isEmpty ? "not configured" : store.homeAddress)) for accurate weather and drive times.")
                            .font(HeliTypography.caption(11))
                            .foregroundColor(HeliColors.mutedGray)
                        Text("💡 Tip: In the Mac Simulator menu, choose Features > Location > Custom Location... to set custom coordinates.")
                            .font(HeliTypography.caption(10.5))
                            .foregroundColor(HeliColors.forestGreen)
                    }
                    .padding(10)
                    .background(HeliColors.sunOchre.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                Button(action: {
                    LocationService.shared.requestWhenInUsePermission()
                    LocationService.shared.startUpdating()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 12))
                        Text("Request / Verify GPS Access")
                            .font(HeliTypography.buttonLabel(13))
                    }
                    .foregroundColor(HeliColors.forestGreen)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(HeliColors.forestTint)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            Divider().overlay(HeliColors.sageRule)

            // 3. Open-Meteo Weather
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Open-Meteo Weather")
                        .font(HeliTypography.railTitle(14))
                        .foregroundColor(HeliColors.greenInk)
                    Spacer()
                    Text("Free · Zero API Key")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(HeliColors.forestGreen)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(HeliColors.forestTint)
                        .clipShape(Capsule())
                }

                Text("Today's Forecast: \(store.liveWeather.label)")
                    .font(HeliTypography.body(13))
                    .foregroundColor(HeliColors.greenInk)

                Button(action: {
                    Task {
                        await store.updateLiveWeather(forceRefresh: true)
                        toastMessage = "Weather refreshed."
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12))
                        Text("Refresh Weather Now")
                            .font(HeliTypography.buttonLabel(13))
                    }
                    .foregroundColor(HeliColors.forestGreen)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(HeliColors.forestTint)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            Divider().overlay(HeliColors.sageRule)

            // 4. Neon Serverless Postgres Database
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Neon Serverless Database")
                        .font(HeliTypography.railTitle(14))
                        .foregroundColor(HeliColors.greenInk)
                    Spacer()
                    Toggle("", isOn: $store.neonSyncEnabled)
                        .labelsHidden()
                        .onChange(of: store.neonSyncEnabled) { _, _ in
                            store.save()
                        }
                }

                Text("Use your own Neon database. Your connection is stored in this device’s Keychain. On another device, enter the same household ID and download before editing.")
                    .font(HeliTypography.caption(12))
                    .foregroundColor(HeliColors.mutedGray)

                HStack(spacing: 8) {
                    if showNeonConnString {
                        TextField("postgresql://user:pass@ep-...neon.tech/neondb", text: Binding(
                            get: { store.neonConnectionString },
                            set: {
                                store.neonConnectionString = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                                store.save(syncToCloud: false)
                            }
                        ))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(size: 12, design: .monospaced))
                    } else {
                        SecureField("postgresql://user:pass@ep-...neon.tech/neondb", text: Binding(
                            get: { store.neonConnectionString },
                            set: {
                                store.neonConnectionString = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                                store.save(syncToCloud: false)
                            }
                        ))
                        .font(.system(size: 12, design: .monospaced))
                    }

                    Button(action: { showNeonConnString.toggle() }) {
                        Image(systemName: showNeonConnString ? "eye.slash" : "eye")
                            .font(.system(size: 13))
                            .foregroundColor(HeliColors.mutedGray)
                    }
                    .buttonStyle(.plain)
                }
                .padding(10)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(HeliColors.sageRule, lineWidth: 0.8)
                )

                TextField("Household ID", text: Binding(
                    get: { store.cloudHouseholdID },
                    set: {
                        store.cloudHouseholdID = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                        store.save(syncToCloud: false)
                    }
                ))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Cloud household ID")

                HStack(spacing: 10) {
                    Button(action: testNeonConnection) {
                        HStack(spacing: 6) {
                            if isTestingNeon {
                                ProgressView().scaleEffect(0.8)
                            } else {
                                Image(systemName: "network")
                                    .font(.system(size: 12))
                            }
                            Text(isTestingNeon ? "Testing..." : "Test Connection")
                                .font(HeliTypography.buttonLabel(13))
                        }
                        .foregroundColor(HeliColors.forestGreen)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(HeliColors.forestTint)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(isTestingNeon)

                    Button(action: syncNeonNow) {
                        HStack(spacing: 6) {
                            if isSyncingNeon {
                                ProgressView().scaleEffect(0.8)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 12))
                            }
                            Text(isSyncingNeon ? "Syncing..." : "Sync Now")
                                .font(HeliTypography.buttonLabel(13))
                        }
                        .foregroundColor(HeliColors.greenInk)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color(hex: "#e8e4c9"))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(isSyncingNeon)
                }

                Button("Download cloud household") { showCloudDownloadConfirm = true }
                    .disabled(isSyncingNeon || store.neonConnectionString.isEmpty)

                if store.syncPending {
                    Text("Local changes are waiting to upload.")
                        .font(HeliTypography.caption(12))
                }
                if let error = store.syncError {
                    Text(error).font(HeliTypography.caption(12)).foregroundColor(HeliColors.warningClay)
                }
                if let status = neonStatusText {
                    Text(status)
                        .font(HeliTypography.caption(12))
                        .foregroundColor(status.contains("✓") ? HeliColors.forestGreen : HeliColors.warningClay)
                        .lineLimit(2)
                }

                if let lastSync = store.lastNeonSyncDate {
                    Text("Last synchronized: \(lastSync.formatted(date: .abbreviated, time: .shortened))")
                        .font(HeliTypography.caption(11))
                        .foregroundColor(HeliColors.mutedGray)
                }
            }
        }
    }

    private func testGoogleMaps() {
        guard !isTestingGoogle else { return }
        isTestingGoogle = true
        googleStatusText = nil
        Task {
            let key = store.googleMapsApiKey.isEmpty ? nil : store.googleMapsApiKey
            let places = await GoogleMapsService.shared.autocompletePlaces(query: "School", apiKey: key)
            let eta = await GoogleMapsService.shared.calculateDriveTime(
                from: LocationService.defaultCoordinate,
                to: CLLocationCoordinate2D(latitude: 42.2780, longitude: -83.7400),
                apiKey: key
            )
            await MainActor.run {
                isTestingGoogle = false
                if !places.isEmpty || eta != nil {
                    googleStatusText = "✓ Active: \(places.count) places, \(eta?.durationMinutes ?? 15)m drive"
                } else {
                    googleStatusText = "Route returned nil. Check API key."
                }
            }
        }
    }

    private func testNeonConnection() {
        guard !isTestingNeon else { return }
        let conn = store.neonConnectionString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !conn.isEmpty else {
            neonStatusText = "Please enter a Neon connection string first."
            return
        }
        isTestingNeon = true
        neonStatusText = nil
        Task {
            do {
                let success = try await NeonDatabaseService.shared.testConnection(rawConnectionString: conn)
                if success {
                    try await NeonDatabaseService.shared.bootstrapSchema(rawConnectionString: conn)
                }
                await MainActor.run {
                    isTestingNeon = false
                    neonStatusText = success ? "✓ Connected & schema ready" : "Connection failed."
                }
            } catch {
                await MainActor.run {
                    isTestingNeon = false
                    neonStatusText = "Connection error: \(error.localizedDescription)"
                }
            }
        }
    }

    private func syncNeonNow() {
        guard !isSyncingNeon else { return }
        isSyncingNeon = true
        neonStatusText = nil
        Task {
            do {
                try await store.syncWithNeon()
                await MainActor.run {
                    isSyncingNeon = false
                    neonStatusText = store.syncPending ? "Some changes are still waiting to upload." : "✓ Successfully synced with Neon"
                }
            } catch {
                await MainActor.run {
                    isSyncingNeon = false
                    neonStatusText = "Sync error: \(error.localizedDescription)"
                }
            }
        }
    }

    private func downloadNeonHousehold() {
        guard !isSyncingNeon else { return }
        isSyncingNeon = true
        Task { @MainActor in
            defer { isSyncingNeon = false }
            do {
                let found = try await store.pullFromNeon()
                neonStatusText = found ? "✓ Cloud household downloaded" : "No cloud household with this ID."
            } catch { neonStatusText = error.localizedDescription }
        }
    }

    // MARK: - Section 8: Your Data

    private var dataSectionContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Button(action: rerunSetup) {
                    HStack(spacing: 8) {
                        HeliIcon("rotate-ccw", size: 14)
                        Text("Run Setup Again")
                    }
                    .font(HeliTypography.buttonLabel(14))
                    .foregroundColor(HeliColors.forestGreen)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .background(HeliColors.forestTint)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Text("Reopens the setup questions with your current answers filled in. Finishing replaces the household; backing out changes nothing.")
                    .font(HeliTypography.caption(11.5))
                    .foregroundColor(HeliColors.mutedGray)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider().overlay(HeliColors.sageRule)

            Button("Reset Sample Schedule") {
                showResetConfirm = true
            }
            .font(HeliTypography.buttonLabel(14))
            .foregroundColor(HeliColors.warningClay)
        }
    }

    /// Settings is a sheet and setup is a full-screen cover; letting the sheet
    /// finish dismissing first keeps the cover from being swallowed.
    private func rerunSetup() {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            store.restartOnboarding()
        }
    }
}

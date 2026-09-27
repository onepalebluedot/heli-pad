import SwiftUI
import CoreLocation

public struct SettingsView: View {
    @ObservedObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    private let onFamilySignedOut: () -> Void

    @State private var expandedSection: String? = nil
    @State private var assistantProbing = false
    @State private var assistantProbe: (ok: Bool, message: String)? = nil
    // Mirrors of the two device-local assistant settings. They live in
    // UserDefaults, which SwiftUI does not observe, so the status badge would
    // otherwise not update until some other state changed.
    @State private var assistantRelayURL = ""
    @State private var assistantSessionToken = ""
    @State private var assistantFieldsLoaded = false
    @State private var editingName: [String: String] = [:]
    @State private var homeAddressInput: String = ""
    @State private var familyNameInput: String? = nil
    @State private var errorMessage: String? = nil
    @State private var showResetConfirm: Bool = false
    @State private var toastMessage: String? = nil
    @State private var showIntegrationsGuide: Bool = false
    @State private var showCalendarReview: Bool = false
    @State private var showGoogleApiKey: Bool = false
    @State private var showGoogleClientId: Bool = false
    @State private var showNeonConnString: Bool = false
    @State private var isTestingGoogle: Bool = false
    @State private var isTestingNeon: Bool = false
    @State private var showCloudDownloadConfirm = false
    @State private var showFamilyAccount = false
    @State private var showFamilyInvite = false
    @State private var showSignOutConfirm = false
    @State private var isSigningOut = false
    @State private var familyProfile: FamilyProfile?
    @State private var familyMembers: [FamilyMember] = []
    @State private var familySessionExpired = false
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
    @State private var homeResolutionToken = UUID()

    public init(store: AppStore, onFamilySignedOut: @escaping () -> Void = {}) {
        self.store = store
        self.onFamilySignedOut = onFamilySignedOut
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    accordionSection(id: "home", title: "Household", icon: "house") {
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

                    accordionSection(id: "assistant", title: "Assistant", icon: "sparkles") {
                        assistantSectionContent
                    }

                    accordionSection(id: "data", title: "Your data", icon: "list") {
                        dataSectionContent
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
            }
            .background(HeliColors.canvasIvory)
            .onAppear {
                reconcileCalendarConnections()
            }
            .sheet(isPresented: $showIntegrationsGuide) {
                IntegrationsGuideSheet()
            }
            .sheet(isPresented: $showCalendarReview) {
                PlanCalendarReviewSheet(store: store)
            }
            .sheet(isPresented: $showFamilyAccount) {
                FamilyAccountView(store: store, isFirstRun: false, onFinished: { showFamilyAccount = false })
            }
            .sheet(isPresented: $showFamilyInvite) {
                FamilyInviteView(store: store)
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
            .alert("Couldn’t Save", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Please check the value and try again.")
            }
            .confirmationDialog("Replace this device's household with the cloud copy?", isPresented: $showCloudDownloadConfirm, titleVisibility: .visible) {
                Button("Download and replace local household", role: .destructive) { downloadNeonHousehold() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Local edits will be replaced. Copy any changes you want to keep before continuing.")
            }
            .confirmationDialog("Sign out of your family account?", isPresented: $showSignOutConfirm, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) { signOutOfFamily() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This phone will return to the sign-in screen. Your family's shared data stays in the family, and you can sign back in with the same account.")
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
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(HeliColors.sageRule.opacity(0.7), lineWidth: 0.8)
                )
            }

            if isOpen {
                VStack(alignment: .leading, spacing: 14) {
                    content()
                }
                .padding(16)
                .background(HeliColors.cardWarmWhite.opacity(0.85))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Section 1: Household

    private var familyNameField: some View {
        let editing = familyNameInput != nil && familyNameInput != store.familyName
        let preview = AppStore.padTitle(familyName: familyNameInput ?? store.familyName)
        return VStack(alignment: .leading, spacing: 6) {
            Text("Family name")
                .font(HeliTypography.body(13))
                .foregroundColor(HeliColors.greenInk)
            HStack(spacing: 8) {
                TextField("e.g. Vincent", text: Binding(
                    get: { familyNameInput ?? store.familyName },
                    set: { familyNameInput = String($0.prefix(AppStore.familyNameLimit)) }
                ))
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .onSubmit(saveFamilyName)
                .accessibilityHint("Shown at the top of the app")
                if editing {
                    Button("Save", action: saveFamilyName)
                        .font(HeliTypography.actionButton(13))
                        .foregroundColor(HeliColors.forestGreen)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
            }
            Text("Shown at the top of the app as \(preview), on every phone in the family.")
                .font(HeliTypography.caption(11))
                .foregroundColor(HeliColors.mutedGray)
        }
    }

    private func saveFamilyName() {
        guard let input = familyNameInput else { return }
        store.setFamilyName(input)
        familyNameInput = nil
    }

    private var homeSectionContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            familyNameField
            Rectangle().fill(HeliColors.sageRule).frame(height: 1).padding(.vertical, 4)
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
                            if val.caseInsensitiveCompare(store.homeAddress) != .orderedSame {
                                homeResolutionToken = UUID()
                                homeLatitude = nil
                                homeLongitude = nil
                                homePlaceId = nil
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
                                let token = UUID()
                                homeResolutionToken = token
                                let selectedAddress = fullAddr

                                Task {
                                    if let details = try? await GoogleMapsService.shared.fetchPlaceDetails(
                                        placeId: pred.placeId,
                                        apiKey: store.googleMapsApiKey,
                                        fallbackName: pred.primaryText,
                                        fallbackAddress: fullAddr
                                    ) {
                                        await MainActor.run {
                                            guard homeResolutionToken == token,
                                                  homeAddressInput.caseInsensitiveCompare(selectedAddress) == .orderedSame else { return }
                                            if !details.formattedAddress.isEmpty && details.formattedAddress != "Address unavailable" {
                                                self.isSelectingHome = true
                                                self.homeAddressInput = details.formattedAddress
                                            }
                                            self.homeLatitude = details.latitude
                                            self.homeLongitude = details.longitude
                                            self.homePlaceId = details.placeId
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
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
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
            .buttonBorderShape(.roundedRectangle(radius: 8))
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
                        saveName(p)
                    }

                    if editingName[p.id] != nil {
                        Button("Cancel") { editingName[p.id] = nil }
                            .font(HeliTypography.caption(11))
                        Button("Save") { saveName(p) }
                            .font(HeliTypography.actionButton(11))
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

            VStack(alignment: .leading, spacing: 6) {
                Text("This phone belongs to")
                    .font(HeliTypography.body(13))
                    .foregroundColor(HeliColors.greenInk)
                Picker("This phone belongs to", selection: Binding(
                    get: { store.currentUser },
                    set: { newValue in
                        do { try store.setActiveUser(newValue) }
                        catch { errorMessage = error.localizedDescription }
                    }
                )) {
                    Text("All").tag("All")
                    ForEach(store.caregivers(), id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .pickerStyle(.segmented)
                Text("Whose stops come first on Go and which reminders this phone sends.")
                    .font(HeliTypography.caption(11))
                    .foregroundColor(HeliColors.mutedGray)
            }
            .padding(.top, 6)
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
                        saveName(c)
                    }

                    if editingName[c.id] != nil {
                        Button("Cancel") { editingName[c.id] = nil }
                            .font(HeliTypography.caption(11))
                        Button("Save") { saveName(c) }
                            .font(HeliTypography.actionButton(11))
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
        VStack(alignment: .leading, spacing: 12) {
            Text("Apple Calendar supports reviewed, selected-calendar import. Google Calendar connects your Google Account to import family events and export stops.")
                .font(HeliTypography.body(12.5))
                .foregroundColor(HeliColors.mutedGray)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Google Calendar")
                            .font(HeliTypography.headline(14))
                            .foregroundColor(HeliColors.greenInk)
                        if store.isGoogleAuthenticated {
                            Text("Connected as \(store.googleAccountEmail.isEmpty ? "Google Account" : store.googleAccountEmail)")
                                .font(HeliTypography.caption(11))
                                .foregroundColor(HeliColors.forestGreen)
                        } else {
                            Text("Not connected")
                                .font(HeliTypography.caption(11))
                                .foregroundColor(HeliColors.mutedGray)
                        }
                    }
                    Spacer()
                    if store.isGoogleAuthenticated {
                        Button("Disconnect") {
                            Task { @MainActor in
                                await store.disconnectGoogleAccount()
                            }
                        }
                        .font(HeliTypography.caption(11))
                        .foregroundColor(HeliColors.warningClay)
                    } else {
                        Button("Connect") {
                            showCalendarReview = true
                        }
                        .font(HeliTypography.actionButton(12))
                        .foregroundColor(HeliColors.forestGreen)
                    }
                }
            }
            .padding(10)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(HeliColors.sageRule, lineWidth: 0.8)
            )

            Toggle("Apple Calendar (EventKit)", isOn: Binding(
                get: { store.connections["apple"] ?? false },
                set: { setConnection("apple", enabled: $0) }
            ))

            Button("Manage Calendars & Sync") {
                showCalendarReview = true
            }
            .font(HeliTypography.actionButton(13))
            .foregroundColor(HeliColors.forestGreen)
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
                        do { try store.setAlertPreference("notifyLeaveBy", enabled: wantsReminders) }
                        catch { errorMessage = error.localizedDescription; return }
                        Task {
                            if wantsReminders {
                                await NotificationService.shared.requestAuthorization()
                            }
                            store.refreshDepartureReminders()
                        }
                    }
                )
            )
            Text("Nudges you \(NotificationService.leadMinutes) minutes before it is time to leave, based on Apple Maps travel time and your arrival buffer. Only for stops that belong to the profile selected on this phone, or to the whole family; choose All to hear about every stop.")
                .font(HeliTypography.caption(11))
                .foregroundColor(HeliColors.mutedGray)
            Toggle("Driver needed alert (12h prior)", isOn: Binding(
                get: { store.notifyDriverNeeded },
                set: { setAlert("notifyDriverNeeded", enabled: $0) }
            ))
            Toggle("Check in on unfinished stops", isOn: Binding(
                get: { store.notifyOverdue },
                set: { wantsCheckIns in
                    Task {
                        if wantsCheckIns {
                            await NotificationService.shared.requestAuthorization()
                        }
                        store.setNotifyOverdue(wantsCheckIns)
                    }
                }
            ))
            Text("If one of your stops is still open \(NotificationService.overdueGraceMinutes / 60) hours after it should have ended, asks whether it happened. Mark it done from the notification, or snooze it for an hour. This phone only.")
                .font(HeliTypography.caption(11))
                .foregroundColor(HeliColors.mutedGray)
            Toggle("Crew informed on reassignments", isOn: Binding(
                get: { store.notifyCrew },
                set: { setAlert("notifyCrew", enabled: $0) }
            ))
            .disabled(true)
            Text("Cross-device reassignment alerts require authenticated household membership and APNs registration; they are unavailable in this build.")
                .font(HeliTypography.caption(11))
                .foregroundColor(HeliColors.mutedGray)

            if let notificationError = store.notificationScheduleError {
                Label(notificationError, systemImage: "exclamationmark.triangle")
                    .font(HeliTypography.caption(11))
                    .foregroundColor(HeliColors.warningClay)
            }

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
            Stepper("Arrival buffer: \(store.buffer) min", value: Binding(
                get: { store.buffer },
                set: { setSetting("buffer", value: $0) }
            ), in: 0...45)
            Toggle("Traffic-aware peak adjustment (1.15x)", isOn: Binding(
                get: { store.trafficMode },
                set: { setSetting("trafficMode", value: $0) }
            ))
            let currentDinnerRule = store.planningRules(for: PlanCore.currentMonday())
            Toggle("Dinner protection (\(TimeFormat.formatTime(currentDinnerRule.time)))", isOn: Binding(
                get: { currentDinnerRule.enabled },
                set: { enabled in
                    do {
                        try store.updatePlanningRules(
                            for: PlanCore.currentMonday(),
                            dinnerProtected: enabled,
                            dinnerTime: currentDinnerRule.time,
                            bufferMinutes: store.buffer,
                            peakTraffic: store.trafficMode,
                            notes: store.weeklyPlanningNotes(for: PlanCore.currentMonday())
                        )
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            ))
        }
    }

    // MARK: - Section 7: Account

    private var accountSectionContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            if AppConfig.familyAPIURL == nil {
                Text("Family accounts are not available in this build. This household stays on this phone.")
                    .font(HeliTypography.body(13))
                    .foregroundColor(HeliColors.mutedGray)
            } else if store.isManagedFamily {
                FamilyAccountSummary(
                    account: familyProfile?.account,
                    family: familyProfile?.families.first { $0.id == store.cloudHouseholdID },
                    members: familyMembers,
                    sessionExpired: familySessionExpired,
                    sync: familySyncState,
                    isSigningOut: isSigningOut,
                    onInvite: { showFamilyInvite = true },
                    onSignIn: { showFamilyAccount = true },
                    onSignOut: { showSignOutConfirm = true }
                )
            } else {
                FamilyAccountSignedOut(
                    hasSession: FamilyAccountAPI.shared.hasSession,
                    onContinue: { showFamilyAccount = true }
                )
            }
        }
        .task(id: "\(store.isManagedFamily ? store.cloudHouseholdID : "")|\(showFamilyAccount)") {
            // Keyed on the sheet too, so signing in again from it refreshes
            // this section when it closes instead of still reading as expired.
            guard store.isManagedFamily, !showFamilyAccount else { return }
            do {
                let api = FamilyAccountAPI.shared
                familyProfile = try await api.profile()
                familyMembers = try await api.members(familyID: store.cloudHouseholdID)
                familySessionExpired = false
            } catch FamilyAccountError.notSignedIn {
                familySessionExpired = true
            } catch { familyMembers = [] }
        }
    }

    private var familySyncState: FamilyAccountSummary.SyncState {
        if store.syncError != nil { return .failing }
        if store.syncPending { return .pending }
        if let last = store.lastNeonSyncDate { return .synced(last) }
        return .unknown
    }

    private func signOutOfFamily() {
        isSigningOut = true
        Task { @MainActor in
            do {
                try await FamilyAccountAPI.shared.logout()
                isSigningOut = false
                dismiss()
                onFamilySignedOut()
            } catch {
                isSigningOut = false
                errorMessage = "Could not sign out on this phone: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Section: Integrations & Cloud

    private var integrationsSectionContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            if store.isManagedFamily {
                Text("Cloud sync is managed by your family account. Database credentials stay on the family service.")
                    .font(HeliTypography.body(13))
                    .foregroundColor(HeliColors.greenInk)
            } else {
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
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            }

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
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
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

            // 2. Google Calendar OAuth 2.0 Client ID
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Google Calendar OAuth Client ID")
                        .font(HeliTypography.railTitle(14))
                        .foregroundColor(HeliColors.greenInk)
                    Spacer()
                    let hasClientId = !store.googleClientId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    Text(hasClientId ? "Configured" : (store.isGoogleAuthenticated ? "Active Session" : "Optional Custom ID"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor((hasClientId || store.isGoogleAuthenticated) ? HeliColors.forestGreen : HeliColors.mutedGray)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(((hasClientId || store.isGoogleAuthenticated) ? HeliColors.forestTint : Color.black.opacity(0.05)))
                        .clipShape(Capsule())
                }

                Text("Enter your Google Cloud iOS OAuth 2.0 Client ID to authenticate your Google Account and sync Google Calendar events.")
                    .font(HeliTypography.caption(12))
                    .foregroundColor(HeliColors.mutedGray)

                HStack(spacing: 8) {
                    if showGoogleClientId {
                        TextField("...apps.googleusercontent.com", text: Binding(
                            get: { store.googleClientId },
                            set: {
                                store.googleClientId = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                                store.save()
                            }
                        ))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(size: 13, design: .monospaced))
                    } else {
                        SecureField("...apps.googleusercontent.com", text: Binding(
                            get: { store.googleClientId },
                            set: {
                                store.googleClientId = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                                store.save()
                            }
                        ))
                        .font(.system(size: 13, design: .monospaced))
                    }

                    Button(action: { showGoogleClientId.toggle() }) {
                        Image(systemName: showGoogleClientId ? "eye.slash" : "eye")
                            .font(.system(size: 13))
                            .foregroundColor(HeliColors.mutedGray)
                    }
                    .buttonStyle(.plain)
                }
                .padding(10)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(HeliColors.sageRule, lineWidth: 0.8)
                )

                if store.isGoogleAuthenticated {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(HeliColors.forestGreen)
                            .font(.system(size: 12))
                        Text("Connected: \(store.googleAccountEmail)")
                            .font(HeliTypography.caption(11))
                            .foregroundColor(HeliColors.forestGreen)
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
                    .clipShape(RoundedRectangle(cornerRadius: 6))
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
            if !store.isManagedFamily {
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
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
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

    private func saveName(_ person: Person) {
        guard let draft = editingName[person.id] else { return }
        do {
            try store.renamePerson(id: person.id, value: draft)
            editingName[person.id] = nil
            toastMessage = "Saved \(draft.trimmingCharacters(in: .whitespaces))."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func setConnection(_ key: String, enabled: Bool) {
        if key == "google" && enabled {
            errorMessage = "Google Calendar cannot connect until an OAuth client ID and callback URL are configured."
            return
        }
        if key == "apple" && enabled {
            Task { @MainActor in
                let granted = await AppleCalendarService.shared.requestAccess()
                do { try store.setConnection("apple", enabled: granted) }
                catch { errorMessage = error.localizedDescription; return }
                if granted { showCalendarReview = true }
                else { errorMessage = "Apple Calendar access was denied or restricted. You can change it in iOS Settings." }
            }
            return
        }
        do { try store.setConnection(key, enabled: enabled) }
        catch { errorMessage = error.localizedDescription }
    }

    private func reconcileCalendarConnections() {
        if store.connections["google"] == true && !store.isGoogleAuthenticated {
            store.connections["google"] = false
        }
        if store.connections["apple"] == true && !AppleCalendarService.shared.hasReadAccess {
            do { try store.setConnection("apple", enabled: false) }
            catch { errorMessage = error.localizedDescription }
        }
    }

    private func setAlert(_ key: String, enabled: Bool) {
        do {
            try store.setAlertPreference(key, enabled: enabled)
            if key == "notifyDriverNeeded" && enabled {
                Task {
                    await NotificationService.shared.requestAuthorization()
                    store.refreshDepartureReminders()
                }
            }
        }
        catch { errorMessage = error.localizedDescription }
    }

    private func setSetting(_ key: String, value: Any) {
        do { try store.setSetting(key: key, value: value) }
        catch { errorMessage = error.localizedDescription }
    }

    // MARK: - Section: Assistant

    private var assistantSectionContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Color.clear.frame(height: 0).onAppear {
                guard !assistantFieldsLoaded else { return }
                assistantRelayURL = store.assistantRelayURL
                assistantSessionToken = store.assistantSessionToken
                assistantFieldsLoaded = true
            }

            HStack {
                Text("Assistant service")
                    .font(HeliTypography.railTitle(14))
                    .foregroundColor(HeliColors.greenInk)
                Spacer()
                let ready = !assistantRelayURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && !assistantSessionToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                Text(ready ? "Configured" : "Not configured")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(ready ? HeliColors.forestGreen : HeliColors.warningClay)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(ready ? HeliColors.forestTint : HeliColors.warningClay.opacity(0.12))
                    .clipShape(Capsule())
            }

            Text("The assistant answers through HeliPad's own service, which holds the model credentials. Without it the Assistant tab reports itself unavailable; nothing else in the app is affected.")
                .font(HeliTypography.caption(12))
                .foregroundColor(HeliColors.mutedGray)

            VStack(alignment: .leading, spacing: 6) {
                Text("Service URL")
                    .font(HeliTypography.caption(11))
                    .foregroundColor(HeliColors.mutedGray)
                TextField("https://…", text: Binding(
                    get: { assistantRelayURL },
                    set: {
                        assistantRelayURL = $0
                        store.assistantRelayURL = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                        assistantProbe = nil
                    }
                ))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .font(.system(size: 13, design: .monospaced))
                .padding(10)
                .background(HeliColors.canvasIvory)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(HeliColors.sageRule, lineWidth: 0.8))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Session token")
                    .font(HeliTypography.caption(11))
                    .foregroundColor(HeliColors.mutedGray)
                SecureField("token", text: Binding(
                    get: { assistantSessionToken },
                    set: {
                        assistantSessionToken = $0
                        store.assistantSessionToken = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                        assistantProbe = nil
                    }
                ))
                .font(.system(size: 13, design: .monospaced))
                .padding(10)
                .background(HeliColors.canvasIvory)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(HeliColors.sageRule, lineWidth: 0.8))
            }

            // Says whether the service is actually reachable, rather than
            // leaving "Configured" to imply it.
            HStack(spacing: 10) {
                Button(action: { Task { await probeAssistant() } }) {
                    HStack(spacing: 6) {
                        if assistantProbing {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .font(.system(size: 12))
                        }
                        Text("Test connection")
                            .font(HeliTypography.buttonLabel(13))
                    }
                    .foregroundColor(HeliColors.forestGreen)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(HeliColors.forestTint)
                    .clipShape(Capsule())
                }
                .disabled(assistantProbing || assistantRelayURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if let assistantProbe {
                    Text(assistantProbe.message)
                        .font(HeliTypography.caption(11))
                        .foregroundColor(assistantProbe.ok ? HeliColors.forestGreen : HeliColors.warningClay)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("Running a service locally")
                    .font(HeliTypography.cardTitle(12))
                    .foregroundColor(HeliColors.greenInk)
                Text("For development, start ios/AssistantLab/tools/dev-relay/relay.py on your Mac and use http://localhost:8787 with the token from that package's .env. Plain HTTP is permitted for local addresses only; anything else must be HTTPS.")
                    .font(HeliTypography.caption(11))
                    .foregroundColor(HeliColors.mutedGray)
            }
            .padding(10)
            .background(HeliColors.sunOchre.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            Text("What gets sent: event titles, dates, times, saved place names and household first names — only for the question asked. Street addresses, coordinates and event notes are not sent. Chat history stays on this device.")
                .font(HeliTypography.caption(11))
                .foregroundColor(HeliColors.mutedGray)
        }
    }

    /// Hits the service's health endpoint. Deliberately not a model request:
    /// this should cost nothing and answer one question — is it reachable.
    private func probeAssistant() async {
        let raw = assistantRelayURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let base = URL(string: raw), base.scheme != nil else {
            assistantProbe = (false, "That is not a valid URL.")
            return
        }
        assistantProbing = true
        defer { assistantProbing = false }

        var request = URLRequest(url: base.appendingPathComponent("health"))
        request.timeoutInterval = 8
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            assistantProbe = code == 200
                ? (true, "Reachable.")
                : (false, "Reached it, but it answered \\(code).")
        } catch let error as URLError where error.code == .appTransportSecurityRequiresSecureConnection {
            assistantProbe = (false, "Plain HTTP is only allowed for local addresses. Use HTTPS.")
        } catch {
            assistantProbe = (false, "Could not reach it. Check the URL and that the service is running.")
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

// MARK: - Account section

/// The Account section's buttons. Every action here is a real button with a
/// shape, because plain tinted text read as labels and people missed them.
struct AccountButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, destructive }
    var kind: Kind

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(HeliTypography.actionButton(14))
            .foregroundColor(foreground)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(background)
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(border, lineWidth: kind == .primary ? 0 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.75 : 1)
    }

    private var foreground: Color {
        switch kind {
        case .primary: return HeliColors.cardWarmWhite
        case .secondary: return HeliColors.forestGreen
        case .destructive: return HeliColors.clayText
        }
    }

    private var background: Color {
        switch kind {
        case .primary: return HeliColors.forestGreen
        case .secondary: return HeliColors.forestTint
        case .destructive: return HeliColors.cardWarmWhite
        }
    }

    private var border: Color {
        switch kind {
        case .primary: return .clear
        case .secondary: return HeliColors.forestGreen.opacity(0.18)
        case .destructive: return HeliColors.clayText.opacity(0.35)
        }
    }
}

/// Signed out, or signed in without having shared this household yet.
struct FamilyAccountSignedOut: View {
    var hasSession: Bool
    var onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "person.2.circle")
                    .font(.system(size: 26))
                    .foregroundColor(HeliColors.forestGreen)
                VStack(alignment: .leading, spacing: 4) {
                    Text(hasSession ? "Share this household" : "Share with your family")
                        .font(HeliTypography.cardTitle(15))
                        .foregroundColor(HeliColors.greenInk)
                    Text(hasSession
                         ? "You're signed in. Create your family to sync this household and invite others."
                         : "Create an account or sign in with Apple. Until then, everything stays on this phone.")
                        .font(HeliTypography.body(13))
                        .foregroundColor(HeliColors.mutedGray)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Button(action: onContinue) {
                Label(hasSession ? "Share this household" : "Create account or sign in",
                      systemImage: hasSession ? "person.2.badge.plus" : "person.crop.circle.badge.plus")
            }
            .buttonStyle(AccountButtonStyle(kind: .primary))
        }
    }
}

/// A shared family: who you are, who is in it, whether it is syncing, and the
/// two things you can do about it. Takes plain values rather than reaching
/// into the family service, so the layout does not depend on a live account.
struct FamilyAccountSummary: View {
    enum SyncState { case synced(Date), pending, failing, unknown }

    var account: FamilyAccount?
    var family: FamilySummary?
    var members: [FamilyMember]
    var sessionExpired: Bool
    var sync: SyncState
    var isSigningOut: Bool
    var onInvite: () -> Void
    var onSignIn: () -> Void
    var onSignOut: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // An expired session can show neither the account nor the members,
            // so it gets the way back in and the way out, and nothing else.
            if sessionExpired {
                expiredNotice
                signOutButton
            } else {
                signedInContent
            }
        }
    }

    private var signedInContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            group(title: "Signed in as") {
                if let account {
                    HStack(spacing: 12) {
                        AvatarDisc(name: account.shownName, size: 38)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(account.shownName)
                                .font(HeliTypography.cardTitle(15))
                                .foregroundColor(HeliColors.greenInk)
                            Text(account.signInMethod)
                                .font(HeliTypography.caption(12))
                                .foregroundColor(HeliColors.mutedGray)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .accessibilityElement(children: .combine)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 62)
                }
            }

            group(title: family.map { "Family · \($0.name)" } ?? "Family", trailing: AnyView(syncBadge)) {
                if members.isEmpty {
                    Text("Loading members…")
                        .font(HeliTypography.body(13))
                        .foregroundColor(HeliColors.mutedGray)
                        .padding(12)
                } else {
                    ForEach(Array(members.enumerated()), id: \.element.id) { index, member in
                        if index > 0 {
                            Rectangle().fill(HeliColors.sageRule).frame(height: 1).padding(.leading, 52)
                        }
                        memberRow(member)
                    }
                }
            }

            VStack(spacing: 10) {
                if family?.role == "owner" {
                    Button(action: onInvite) {
                        Label("Invite family member", systemImage: "person.badge.plus")
                    }
                    .buttonStyle(AccountButtonStyle(kind: .primary))
                    .accessibilityHint("Creates a one-time invitation code to share")
                } else if family != nil {
                    Text("Only the family owner can invite people.")
                        .font(HeliTypography.caption(12))
                        .foregroundColor(HeliColors.mutedGray)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                signOutButton
            }
        }
    }

    private var signOutButton: some View {
        Button(action: onSignOut) {
            Label(isSigningOut ? "Signing out…" : "Sign out", systemImage: "rectangle.portrait.and.arrow.right")
        }
        .buttonStyle(AccountButtonStyle(kind: .destructive))
        .disabled(isSigningOut)
        .accessibilityHint("Signs this phone out of the family account")
    }

    private var expiredNotice: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Your sign-in expired on this phone, so family changes are not syncing.", systemImage: "exclamationmark.triangle.fill")
                .font(HeliTypography.body(13))
                .foregroundColor(HeliColors.warningClay)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onSignIn) {
                Label("Sign in again", systemImage: "arrow.clockwise")
            }
            .buttonStyle(AccountButtonStyle(kind: .primary))
        }
        .padding(14)
        .background(HeliColors.clayWash)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func group<Content: View>(title: String, trailing: AnyView? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title.uppercased())
                    .font(HeliTypography.eyebrow(11))
                    .foregroundColor(HeliColors.mutedGray)
                    .lineLimit(1)
                Spacer(minLength: 8)
                trailing
            }
            VStack(alignment: .leading, spacing: 0) { content() }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(HeliColors.canvasIvory)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(HeliColors.sageRule, lineWidth: 1)
                )
        }
    }

    private func memberRow(_ member: FamilyMember) -> some View {
        let name = member.displayName.isEmpty ? "Family member" : member.displayName
        let isYou = member.id == account?.id
        return HStack(spacing: 12) {
            AvatarDisc(name: name, size: 30)
            Text(name)
                .font(HeliTypography.body(14))
                .foregroundColor(HeliColors.greenInk)
                .lineLimit(1)
            if isYou {
                Text("You")
                    .font(HeliTypography.caption(11))
                    .foregroundColor(HeliColors.mutedGray)
            }
            Spacer(minLength: 8)
            Text(member.role.capitalized)
                .font(HeliTypography.caption(11))
                .foregroundColor(member.role == "owner" ? HeliColors.forestGreen : HeliColors.mutedGray)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(member.role == "owner" ? HeliColors.forestTint : HeliColors.sageRule.opacity(0.5))
                .clipShape(Capsule())
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 50)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var syncBadge: some View {
        switch sync {
        case .synced(let date):
            badge("Synced \(date.formatted(.relative(presentation: .named)))", icon: "checkmark.icloud", color: HeliColors.forestGreen)
        case .pending:
            badge("Waiting to sync", icon: "arrow.triangle.2.circlepath", color: HeliColors.mutedGray)
        case .failing:
            badge("Not syncing", icon: "exclamationmark.icloud", color: HeliColors.warningClay)
        case .unknown:
            EmptyView()
        }
    }

    private func badge(_ text: String, icon: String, color: Color) -> some View {
        Label(text, systemImage: icon)
            .font(HeliTypography.caption(11))
            .foregroundColor(color)
            .lineLimit(1)
    }
}

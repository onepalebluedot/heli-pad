import SwiftUI
import EventKit

public struct AppleCalendarChoice: Identifiable, Hashable {
    public var id: String
    public var title: String
    public var source: String
}

@MainActor
public final class AppleCalendarService: ObservableObject {
    public static let shared = AppleCalendarService()

    @Published public private(set) var calendars: [AppleCalendarChoice] = []
    private let eventStore = EKEventStore()

    private init() {}

    public var hasReadAccess: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    public func requestAccess() async -> Bool {
        do {
            let granted = try await eventStore.requestFullAccessToEvents()
            if granted { loadCalendars() }
            return granted
        } catch {
            return false
        }
    }

    public func loadCalendars() {
        guard hasReadAccess else {
            calendars = []
            return
        }
        calendars = eventStore.calendars(for: .event)
            .map { AppleCalendarChoice(id: $0.calendarIdentifier, title: $0.title, source: $0.source.title) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    public func events(
        calendarIDs: Set<String>,
        start: Date,
        end: Date,
        timeZone: TimeZone,
        homeName: String
    ) throws -> [TaskRecord] {
        let selected = eventStore.calendars(for: .event).filter { calendarIDs.contains($0.calendarIdentifier) }
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: selected)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        func dateString(_ date: Date) -> String {
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        }
        func timeString(_ date: Date) -> String {
            let parts = calendar.dateComponents([.hour, .minute], from: date)
            return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
        }

        return eventStore.events(matching: predicate).compactMap { event -> TaskRecord? in
            guard let eventStart = event.startDate, let eventEnd = event.endDate else { return nil }
            let day = dateString(eventStart)
            let calendarIdentifier = event.calendar.calendarIdentifier
            let externalIdentifier = event.calendarItemExternalIdentifier?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let providerItemIdentifier = (externalIdentifier?.isEmpty == false)
                ? externalIdentifier!
                : event.calendarItemIdentifier
            let originalDate = event.occurrenceDate ?? eventStart
            let originalDay = dateString(originalDate)
            let providerKey = "apple|\(calendarIdentifier)|\(providerItemIdentifier)|\(originalDay)|\(timeString(originalDate))"
            // EventKit tells us whether the item belongs to a recurrence. Keep
            // that provider identity instead of grouping lookalike local rows by
            // title, destination, or children. No local rule is invented: the
            // imported window remains bounded to the provider rows we fetched.
            let providerSeriesId = (event.occurrenceDate != nil || event.hasRecurrenceRules)
                ? "apple-series|\(calendarIdentifier)|\(providerItemIdentifier)"
                : nil
            let destination = (event.location ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return TaskRecord(
                id: providerKey,
                date: day,
                time: event.isAllDay ? "00:00" : timeString(eventStart),
                endTime: event.isAllDay ? "23:59" : timeString(eventEnd),
                title: event.title ?? "Calendar event",
                owner: "TBD",
                location: destination.isEmpty ? homeName : destination,
                mode: destination.isEmpty ? "Home" : "Drive",
                kind: destination.isEmpty ? .home : .other,
                allDay: event.isAllDay,
                seriesId: providerSeriesId,
                originalOccurrenceDate: providerSeriesId == nil ? nil : originalDay,
                calendarId: providerKey
            )
        }
    }
}

public struct PlanCalendarReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject public var store: AppStore
    @ObservedObject private var calendarService = AppleCalendarService.shared
    @State private var selectedCalendarIDs: Set<String> = []
    @State private var statusMessage: String? = nil
    @State private var isWorking = false

    @State private var selectedGoogleCalendarIDs: Set<String> = []
    @State private var isConnectingGoogle = false
    @State private var isWorkingGoogle = false

    public init(store: AppStore) {
        self.store = store
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("GOOGLE CALENDAR") {
                    Text("Connect your Google Account to import family calendar events into HeliPad and export stops to Google Calendar. HeliPad reconciles event changes while preserving family caregiver assignments and notes.")
                        .font(HeliTypography.body(13))
                        .foregroundColor(HeliColors.mutedGray)

                    if store.isGoogleAuthenticated {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(HeliColors.forestGreen)
                                        .frame(width: 8, height: 8)
                                    Text("Connected")
                                        .font(HeliTypography.headline(13))
                                        .foregroundColor(HeliColors.forestGreen)
                                }
                                Text(store.googleAccountEmail.isEmpty ? "Google Account" : store.googleAccountEmail)
                                    .font(HeliTypography.caption(12))
                                    .foregroundColor(HeliColors.mutedGray)
                            }
                            Spacer()
                            Button("Disconnect", role: .destructive) {
                                Task { @MainActor in
                                    await store.disconnectGoogleAccount()
                                    statusMessage = "Google Account disconnected."
                                }
                            }
                            .font(HeliTypography.caption(12))
                            .buttonStyle(.bordered)
                        }
                        .padding(.vertical, 4)

                        if !store.googleCalendars.isEmpty {
                            Text("CHOOSE CALENDARS TO IMPORT")
                                .font(HeliTypography.eyebrow(11))
                                .foregroundColor(HeliColors.mutedGray)
                                .padding(.top, 4)

                            ForEach(store.googleCalendars) { cal in
                                Toggle(isOn: Binding(
                                    get: { selectedGoogleCalendarIDs.contains(cal.id) },
                                    set: { selected in
                                        if selected { selectedGoogleCalendarIDs.insert(cal.id) }
                                        else { selectedGoogleCalendarIDs.remove(cal.id) }
                                        store.plan.calendar.googleCalendarIDs = selectedGoogleCalendarIDs.sorted()
                                        store.save()
                                    }
                                )) {
                                    HStack {
                                        Text(cal.title)
                                        if cal.isPrimary {
                                            Text("Primary")
                                                .font(.system(size: 10, weight: .semibold))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(HeliColors.forestTint)
                                                .foregroundColor(HeliColors.forestGreen)
                                                .clipShape(Capsule())
                                        }
                                    }
                                }
                            }

                            Picker("Export Stops To", selection: Binding(
                                get: { store.plan.calendar.googleExportCalendarID ?? "primary" },
                                set: {
                                    store.plan.calendar.googleExportCalendarID = $0
                                    store.save()
                                }
                            )) {
                                ForEach(store.googleCalendars) { cal in
                                    Text(cal.isPrimary ? "\(cal.title) (Primary)" : cal.title)
                                        .tag(cal.id)
                                }
                            }

                            Button(isWorkingGoogle ? "Importing from Google…" : "Import Selected Google Calendars") {
                                importSelectedGoogleCalendars()
                            }
                            .font(HeliTypography.actionButton(14))
                            .foregroundColor(HeliColors.forestGreen)
                            .disabled(isWorkingGoogle || selectedGoogleCalendarIDs.isEmpty)

                            if let lastImport = store.plan.calendar.lastGoogleImport {
                                Text("Last imported: \(lastImport.formatted(date: .abbreviated, time: .shortened))")
                                    .font(HeliTypography.caption(11))
                                    .foregroundColor(HeliColors.mutedGray)
                            }
                        } else {
                            Button("Load Google Calendars") {
                                Task { @MainActor in
                                    do {
                                        try await store.refreshGoogleCalendars()
                                        selectedGoogleCalendarIDs = Set(store.plan.calendar.googleCalendarIDs ?? [])
                                    } catch {
                                        statusMessage = "Could not load calendars: \(error.localizedDescription)"
                                    }
                                }
                            }
                            .font(HeliTypography.actionButton(13))
                            .foregroundColor(HeliColors.forestGreen)
                        }
                    } else {
                        Button(isConnectingGoogle ? "Connecting…" : "Sign In with Google") {
                            connectGoogle()
                        }
                        .font(HeliTypography.actionButton(14))
                        .foregroundColor(HeliColors.forestGreen)
                        .disabled(isConnectingGoogle)
                    }
                }

                Section("APPLE CALENDAR IMPORT") {
                    Text("Choose the calendars HeliPad may read. Import updates event details while preserving HeliPad assignments, completion, children, and notes.")
                        .font(HeliTypography.body(13))
                        .foregroundColor(HeliColors.mutedGray)

                    if calendarService.hasReadAccess {
                        ForEach(calendarService.calendars) { calendar in
                            Toggle(isOn: Binding(
                                get: { selectedCalendarIDs.contains(calendar.id) },
                                set: { selected in
                                    if selected { selectedCalendarIDs.insert(calendar.id) }
                                    else { selectedCalendarIDs.remove(calendar.id) }
                                }
                            )) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(calendar.title)
                                    Text(calendar.source)
                                        .font(HeliTypography.caption(11))
                                        .foregroundColor(HeliColors.mutedGray)
                                }
                            }
                        }
                    } else {
                        Button("Allow Apple Calendar Access") { requestAccess() }
                    }

                    if calendarService.hasReadAccess {
                        Button(isWorking ? "Importing…" : "Import Apple Calendars") { importSelectedCalendars() }
                            .font(HeliTypography.actionButton(14))
                            .foregroundColor(HeliColors.forestGreen)
                            .disabled(isWorking || selectedCalendarIDs.isEmpty)
                    }
                }

                if let statusMessage {
                    Section("STATUS") {
                        Text(statusMessage)
                            .font(HeliTypography.body(13))
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(HeliColors.canvasIvory)
            .navigationTitle("Calendar Sync")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear {
                selectedCalendarIDs = Set(store.plan.calendar.appleCalendarIDs ?? [])
                selectedGoogleCalendarIDs = Set(store.plan.calendar.googleCalendarIDs ?? [])
                calendarService.loadCalendars()
                if store.isGoogleAuthenticated && store.googleCalendars.isEmpty {
                    Task { @MainActor in
                        try? await store.refreshGoogleCalendars()
                        selectedGoogleCalendarIDs = Set(store.plan.calendar.googleCalendarIDs ?? [])
                    }
                }
            }
        }
    }

    private func connectGoogle() {
        isConnectingGoogle = true
        Task { @MainActor in
            defer { isConnectingGoogle = false }
            do {
                try await store.connectGoogleAccount()
                selectedGoogleCalendarIDs = Set(store.plan.calendar.googleCalendarIDs ?? [])
                statusMessage = "Connected to Google as \(store.googleAccountEmail). Select calendars to import."
            } catch {
                statusMessage = "Google connection failed: \(error.localizedDescription)"
            }
        }
    }

    private func importSelectedGoogleCalendars() {
        isWorkingGoogle = true
        Task { @MainActor in
            defer { isWorkingGoogle = false }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = store.timeZone == "device"
                ? .current
                : (TimeZone(identifier: store.timeZone) ?? .current)
            let start = calendar.startOfDay(for: store.currentDate)
            let end = calendar.date(byAdding: .day, value: 31, to: start)!
            do {
                let service = GoogleCalendarService.shared
                let imported = try await service.fetchEvents(
                    calendarIDs: selectedGoogleCalendarIDs,
                    start: start,
                    end: end,
                    timeZone: calendar.timeZone,
                    homeName: store.home()
                )
                let startString = PlanCore.currentDeviceDate(date: start, timeZone: calendar.timeZone)
                let finalDay = calendar.date(byAdding: .day, value: -1, to: end)!
                let endString = PlanCore.currentDeviceDate(date: finalDay, timeZone: calendar.timeZone)
                store.mergeGoogleCalendarEvents(
                    imported,
                    calendarIDs: selectedGoogleCalendarIDs,
                    from: startString,
                    through: endString
                )
                statusMessage = "Imported \(imported.count) event\(imported.count == 1 ? "" : "s") from Google Calendar."
            } catch {
                statusMessage = "Google Calendar import failed: \(error.localizedDescription)"
            }
        }
    }

    private func requestAccess() {
        Task { @MainActor in
            let granted = await calendarService.requestAccess()
            statusMessage = granted
                ? "Apple Calendar access granted. Choose at least one calendar to import."
                : "Apple Calendar access was denied or restricted. Change access in iOS Settings to import events."
            do {
                try store.setConnection("apple", enabled: granted)
            } catch {
                statusMessage = "Calendar access changed, but HeliPad could not save the connection: \(error.localizedDescription)"
            }
        }
    }

    private func importSelectedCalendars() {
        isWorking = true
        Task { @MainActor in
            defer { isWorking = false }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = store.timeZone == "device"
                ? .current
                : (TimeZone(identifier: store.timeZone) ?? .current)
            let start = calendar.startOfDay(for: store.currentDate)
            let end = calendar.date(byAdding: .day, value: 31, to: start)!
            do {
                let imported = try calendarService.events(
                    calendarIDs: selectedCalendarIDs,
                    start: start,
                    end: end,
                    timeZone: calendar.timeZone,
                    homeName: store.home()
                )
                let startString = PlanCore.currentDeviceDate(date: start, timeZone: calendar.timeZone)
                let finalDay = calendar.date(byAdding: .day, value: -1, to: end)!
                let endString = PlanCore.currentDeviceDate(date: finalDay, timeZone: calendar.timeZone)
                store.mergeAppleCalendarEvents(
                    imported,
                    calendarIDs: selectedCalendarIDs,
                    from: startString,
                    through: endString
                )
                statusMessage = "Imported \(imported.count) event\(imported.count == 1 ? "" : "s") from Apple Calendar."
            } catch {
                statusMessage = "Import failed: \(error.localizedDescription)"
            }
        }
    }
}

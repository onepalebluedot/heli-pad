import SwiftUI
import CoreLocation

public struct GoAddEditStopSheet: View {
    @ObservedObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    public var existingStop: TaskRecord?
    /// Values to open a brand new stop with (the day the caller was looking at,
    /// or a shortcut's template). Ignored when editing an existing stop.
    public var prefill: TaskRecord?
    /// Weekdays to open with already ticked — a shortcut carrying its usual days.
    public var preselectedDays: Set<Int>?
    public var preselectedWeekCount: Int?
    public var initialEditScope: RecurrenceEditScope
    public var onSaved: (() -> Void)?

    @FocusState private var isWhatFocused: Bool
    @FocusState private var isWhereFocused: Bool
    @State private var isRepeating: Bool = false
    @State private var title: String = ""
    @State private var kind: TaskKind = .other
    @State private var selectedKids: Set<String> = []
    @State private var location: String = ""
    @State private var customLocation: String = ""
    @State private var startMinutes: Int = 15 * 60
    @State private var durationMinutes: Int = 30
    @State private var driver: String = "Dad"
    @State private var mode: String = "Drive"
    @State private var gcal: Bool = false
    @State private var customTitle: String = ""

    // Google Places & Autocomplete State
    @State private var placePredictions: [PlacePrediction] = []
    @State private var isSearchingPlaces: Bool = false
    @State private var isSelectingPrediction: Bool = false
    @State private var selectedAddress: String = ""
    @State private var selectedCoordinate: CLLocationCoordinate2D? = nil
    @State private var saveToHouseholdPlaces: Bool = false
    @State private var searchTask: Task<Void, Never>? = nil

    // Date & Recurrence State
    @State private var stopDate: Date = Date()
    @State private var dateString: String = ""
    @State private var repeatDays: Set<Int> = [] // 0=Mon ... 6=Sun
    @State private var repeatMode: RecurrenceMode = .none
    @State private var recurrenceEndMode: String = "weeks"
    @State private var recurrenceWeekCount: Int = 20
    @State private var recurrenceThroughDate: Date = Date()
    @State private var editScope: RecurrenceEditScope = .occurrence
    @State private var showDeleteConfirmation = false
    @State private var showSaveSeriesConfirmation = false

    // Shortcut / Template State
    @State private var saveAsTemplate: Bool = false
    @State private var templateCategory: String = "Sports"
    @State private var saveError: String? = nil

    private struct WeekdayOption: Identifiable {
        let id: Int
        let letter: String
        let name: String
    }

    private let weekdays: [WeekdayOption] = [
        WeekdayOption(id: 0, letter: "M", name: "Mon"),
        WeekdayOption(id: 1, letter: "T", name: "Tue"),
        WeekdayOption(id: 2, letter: "W", name: "Wed"),
        WeekdayOption(id: 3, letter: "Th", name: "Thu"),
        WeekdayOption(id: 4, letter: "F", name: "Fri"),
        WeekdayOption(id: 5, letter: "Sa", name: "Sat"),
        WeekdayOption(id: 6, letter: "Su", name: "Sun")
    ]

    public init(
        store: AppStore,
        existingStop: TaskRecord? = nil,
        prefill: TaskRecord? = nil,
        preselectedDays: Set<Int>? = nil,
        preselectedWeekCount: Int? = nil,
        initialEditScope: RecurrenceEditScope = .occurrence,
        onSaved: (() -> Void)? = nil
    ) {
        self.store = store
        self.existingStop = existingStop
        self.prefill = prefill
        self.preselectedDays = preselectedDays
        self.preselectedWeekCount = preselectedWeekCount
        self.initialEditScope = initialEditScope
        self.onSaved = onSaved
    }

    private let presets: [(id: TaskKind, label: String, icon: String, defaultMins: Int, place: String)] = [
        (.dropoff, "Drop-off", "car", 20, ""),
        (.pickup, "Pickup", "car", 20, ""),
        (.practice, "Practice", "ball", 90, "Lakeside Sports Complex"),
        (.lesson, "Lesson", "music", 60, "Community Center"),
        (.clinic, "Health", "care", 60, "Pediatric Clinic"),
        (.play, "Playdate", "play", 120, "Downtown Square"),
        (.dinner, "Dinner", "meal", 60, "Home"),
        (.other, "Other", "pencil", 60, "Home")
    ]

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Preview Tone Card
                    previewCard

                    // 5 Form Sections
                    VStack(spacing: 12) {
                        whatSection
                        whoSection
                        whereSection
                        whenSection
                        driverSection
                    }

                    // Shortcut / Template Toggle
                    VStack(spacing: 8) {
                        Toggle(isOn: $saveAsTemplate) {
                            HStack(spacing: 8) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 15))
                                    .foregroundColor(HeliColors.forestGreen)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Save as Activity Shortcut")
                                        .font(HeliTypography.cardTitle(13.5))
                                        .foregroundColor(HeliColors.greenInk)
                                    Text("Add to quick templates for 1-tap re-use")
                                        .font(HeliTypography.caption(11))
                                        .foregroundColor(HeliColors.mutedGray)
                                }
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(HeliColors.cardWarmWhite)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(saveAsTemplate ? HeliColors.forestGreen.opacity(0.5) : HeliColors.sageRule, lineWidth: 0.8)
                        )

                        if saveAsTemplate {
                            HStack {
                                Text("Shortcut Category:")
                                    .font(HeliTypography.caption(12))
                                    .foregroundColor(HeliColors.mutedGray)
                                Spacer()
                                Picker("Category", selection: $templateCategory) {
                                    ForEach(TaskKind.categories, id: \.self) { cat in
                                        Text(cat).tag(cat)
                                    }
                                }
                                .pickerStyle(.menu)
                                .tint(HeliColors.forestGreen)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(HeliColors.canvasIvory)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }

                    // Calendar intent toggle
                    Toggle("Request Google Calendar export", isOn: $gcal)
                        .font(HeliTypography.body(13))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(HeliColors.cardWarmWhite)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .disabled(!store.isGoogleAuthenticated)

                    if !store.isGoogleAuthenticated {
                        Text("Connect Google Calendar in Settings or Plan before requesting export. Local saves are never labeled as exported.")
                            .font(HeliTypography.caption(11))
                            .foregroundColor(HeliColors.mutedGray)
                    }

                    // Primary Action Button
                    Button(action: requestSave) {
                        HStack(spacing: 6) {
                            if isRepeating {
                                Image(systemName: "repeat")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            Text(actionButtonTitle)
                                .font(HeliTypography.buttonLabel(15))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(HeliColors.forestGreen)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .padding(.top, 6)

                    // Destructive Remove Button
                    if existingStop != nil {
                        Button(action: {
                            if existingStop?.seriesId != nil && editScope == .series {
                                showDeleteConfirmation = true
                            } else {
                                deleteStop()
                            }
                        }) {
                            Text(editScope == .series ? "Remove entire series" : "Remove this occurrence")
                                .font(HeliTypography.body(14))
                                .foregroundColor(HeliColors.warningClay)
                                .underline()
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(18)
            }
            .background(HeliColors.canvasIvory)
            .navigationTitle(existingStop != nil ? "Edit stop" : "New stop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(HeliTypography.buttonLabel(14))
                        .foregroundColor(HeliColors.forestGreen)
                }
            }
            .onAppear {
                seedInitialValues()
            }
            .onChange(of: editScope) { _, scope in
                guard let existing = existingStop, let seriesId = existing.seriesId else { return }
                if scope == .occurrence {
                    dateString = existing.date
                    stopDate = dateFromString(existing.date)
                } else {
                    let start = store.seriesDefinition(id: seriesId)?.pattern.startDate
                        ?? store.events(inSeries: seriesId).map { $0.originalOccurrenceDate ?? $0.date }.min()
                        ?? existing.date
                    dateString = start
                    stopDate = dateFromString(start)
                }
            }
            .alert("Couldn’t Save Stop", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveError ?? "Please check the stop and try again.")
            }
            .confirmationDialog(
                "Remove the entire recurring series?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Remove all \(seriesDeleteCount) occurrences", role: .destructive) { deleteStop() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes \(seriesDeleteCount) total occurrences, including \(seriesHistoricalCount) in the past. This cannot be undone.")
            }
            .confirmationDialog(
                "Save changes to the entire series?",
                isPresented: $showSaveSeriesConfirmation,
                titleVisibility: .visible
            ) {
                Button("Update \(previewOccurrenceCount) occurrences") { saveStop() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This updates the finite series and may affect \(seriesHistoricalCount) historical occurrences. Per-occurrence completion, notes, locks, and unchanged mixed assignments are preserved.")
            }
        }
    }

    private var actionButtonTitle: String {
        if existingStop != nil { return editScope == .series ? "Save entire series" : "Save this occurrence" }
        if isRepeating { return "Add \(previewOccurrenceCount) repeating stops" }
        if previewOccurrenceCount > 1 { return "Add \(previewOccurrenceCount) stops this week" }
        return "Add stop"
    }

    private var whenSummaryValue: String {
        let timeStr = "\(TimeFormat.formatTime(startMinutes)) (\(TimeFormat.formatDurationShort(durationMinutes)))"
        if isRepeating {
            return "\(repeatDaysSummary) · \(previewOccurrenceCount) stops · \(timeStr)"
        } else if repeatDays.count > 1 {
            return "\(repeatDaysSummary) (this week) · \(previewOccurrenceCount) stops · \(timeStr)"
        }
        return "\(formatDayShort(dateString)) · \(timeStr)"
    }

    private var driverSummaryValue: String {
        if driver == "TBD" { return "Needs driver" }
        if driver == "Family" { return "Family (All caretakers)" }
        return driver
    }

    private var computedTitle: String {
        let trimmed = customTitle.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { return trimmed }
        return title
    }

    private func seedInitialValues() {
        editScope = initialEditScope
        if let e = existingStop {
            title = e.title
            customTitle = e.title
            kind = e.kind
            selectedKids = Set(e.kids)
            location = e.location
            customLocation = e.location
            selectedAddress = e.formattedAddress ?? (store.locations.first(where: { $0.name == e.location })?.address ?? "")
            if let lat = e.latitude, let lng = e.longitude {
                selectedCoordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
            } else if let loc = store.locations.first(where: { $0.name == e.location }), let lat = loc.latitude, let lng = loc.longitude {
                selectedCoordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
            }
            startMinutes = PlanCore.mins(e.time)
            durationMinutes = max(10, PlanCore.mins(e.endTime) - startMinutes)
            driver = e.owner
            mode = e.mode
            gcal = e.gcal
            dateString = e.date
            stopDate = dateFromString(e.date)
            let w = weekdayIndex(for: stopDate)
            repeatDays = [w]
            if let seriesId = e.seriesId {
                isRepeating = true
                repeatMode = .weekly
                let allSeries = store.events(inSeries: seriesId)
                if let definition = store.seriesDefinition(id: seriesId) {
                    if initialEditScope == .series {
                        dateString = definition.pattern.startDate
                        stopDate = dateFromString(definition.pattern.startDate)
                    }
                    repeatDays = Set(definition.pattern.weekdays)
                    switch definition.pattern.end {
                    case .weekCount(let count):
                        recurrenceEndMode = "weeks"
                        recurrenceWeekCount = count
                    case .throughDate(let date):
                        recurrenceEndMode = "date"
                        recurrenceThroughDate = dateFromString(date)
                    }
                } else {
                    let originalDates = allSeries.map { $0.originalOccurrenceDate ?? $0.date }
                    if initialEditScope == .series {
                        dateString = originalDates.min() ?? e.date
                        stopDate = dateFromString(dateString)
                    }
                    repeatDays = Set(originalDates.map(PlanCore.weekdayIndex))
                    recurrenceEndMode = "date"
                    recurrenceThroughDate = dateFromString(originalDates.max() ?? e.date)
                }
            } else {
                isRepeating = false
                repeatMode = .none
            }
        } else {
            // Start from whatever the caller handed us — the day they were looking
            // at, or a shortcut's template — and fill the gaps with the defaults.
            let seed = prefill
            kind = seed?.kind ?? .other

            let seedLocation = (seed?.location ?? "").trimmingCharacters(in: .whitespaces)
            location = seedLocation
            customLocation = seedLocation
            selectedAddress = seed?.formattedAddress
                ?? store.locations.first(where: { $0.name == location })?.address
                ?? ""
            if let lat = seed?.latitude, let lng = seed?.longitude {
                selectedCoordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
            } else if let loc = store.locations.first(where: { $0.name == location }),
                      let lat = loc.latitude, let lng = loc.longitude {
                selectedCoordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
            }

            if let seedKids = seed?.kids, !seedKids.isEmpty {
                selectedKids = Set(seedKids)
            } else if let firstKid = store.children().first {
                selectedKids = [firstKid]
            }

            let seedTitle = (seed?.title ?? "").trimmingCharacters(in: .whitespaces)
            if !seedTitle.isEmpty {
                title = seedTitle
                customTitle = seedTitle
            } else {
                title = ""
                customTitle = ""
            }

            let seedOwner = seed?.owner ?? ""
            if !seedOwner.isEmpty && seedOwner != "TBD" {
                driver = seedOwner
            } else {
                driver = store.currentUser == "All" ? (store.caregivers().first ?? "Dad") : store.currentUser
            }
            if let seedMode = seed?.mode, !seedMode.isEmpty {
                mode = seedMode
            }

            if let seedTime = seed?.time, !seedTime.isEmpty {
                startMinutes = PlanCore.mins(seedTime)
                let seedEnd = PlanCore.mins(seed?.endTime ?? "")
                durationMinutes = seedEnd > startMinutes ? (seedEnd - startMinutes) : 30
            } else {
                startMinutes = 15 * 60 // 3:00 PM default
                durationMinutes = 30
            }

            let seedDate = (seed?.date ?? "").trimmingCharacters(in: .whitespaces)
            dateString = seedDate.isEmpty ? store.dateForDay(store.activeDay) : seedDate
            stopDate = dateFromString(dateString)
            repeatDays = [weekdayIndex(for: stopDate)]
            isRepeating = false
            repeatMode = .none
        }

        // A shortcut arrives with the days it usually runs on.
        if let usual = preselectedDays, !usual.isEmpty {
            repeatDays = usual
            let count = preselectedWeekCount ?? 1
            isRepeating = count > 1
            repeatMode = isRepeating ? .weekly : (usual.count > 1 ? .weekly : .none)
            recurrenceWeekCount = count > 1 ? count : 20
        }

        let defaultThrough = PlanCore.dateAdd(PlanCore.monday(dateString), recurrenceWeekCount * 7 - 1)
        if recurrenceEndMode == "weeks" { recurrenceThroughDate = dateFromString(defaultThrough) }

        templateCategory = categoryForKind(kind)
    }

    // MARK: - Preview Card

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(computedTitle.isEmpty ? "New stop" : computedTitle)
                    .font(HeliTypography.destTitle(18))
                    .foregroundColor(.white)
                Spacer()
                Text(TimeFormat.formatDuration(durationMinutes))
                    .font(HeliTypography.railMeta(12))
                    .foregroundColor(Color.white.opacity(0.85))
            }

            // Date & Recurrence Row
            HStack(spacing: 8) {
                HeliIcon("calendar", size: 12)
                    .foregroundColor(.white)
                Text(formatDisplayDate(dateString))
                    .font(HeliTypography.railMeta(12))
                    .foregroundColor(Color.white.opacity(0.95))

                if isRepeating {
                    HStack(spacing: 4) {
                        Image(systemName: "repeat")
                            .font(.system(size: 10, weight: .bold))
                        Text(repeatDaysSummary)
                            .font(HeliTypography.eyebrow(9.5))
                    }
                    .foregroundColor(HeliColors.greenInk)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(HeliColors.butterYellow)
                    .clipShape(Capsule())
                } else if repeatDays.count > 1 {
                    HStack(spacing: 4) {
                        Text(repeatDaysSummary)
                            .font(HeliTypography.eyebrow(9.5))
                    }
                    .foregroundColor(HeliColors.greenInk)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(HeliColors.butterYellow)
                    .clipShape(Capsule())
                }

                Spacer()

                Text("\(TimeFormat.formatTime(startMinutes)) → \(TimeFormat.formatTime(startMinutes + durationMinutes))")
                    .font(HeliTypography.railTime(12))
                    .foregroundColor(.white)
            }

            HStack(spacing: 8) {
                HeliIcon(mode == "Home" ? "house" : "car", size: 12)
                    .foregroundColor(.white)
                Text(location.isEmpty ? "No location set" : location)
                    .font(HeliTypography.railMeta(12))
                    .foregroundColor(Color.white.opacity(0.85))
            }

            HStack(spacing: 6) {
                AvatarDisc(name: driver, size: 20)
                Text(driverSummaryValue)
                    .font(HeliTypography.railMeta(11.5))
                    .foregroundColor(.white)

                Spacer()

                if selectedKids.isEmpty {
                    Text("Solo · No child")
                        .font(HeliTypography.railMeta(10.5))
                        .foregroundColor(HeliColors.greenInk)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(HeliColors.butterYellow)
                        .clipShape(Capsule())
                } else {
                    ForEach(Array(selectedKids), id: \.self) { kid in
                        Text(kid)
                            .font(HeliTypography.railMeta(10.5))
                            .foregroundColor(HeliColors.greenInk)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(HeliColors.butterYellow)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(14)
        .background(HeliColors.toneForest)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - Section Card Template

    private func sectionCard<Content: View>(
        icon: String,
        label: String,
        badge: String? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                HeliIcon(icon, size: 14)
                    .foregroundColor(HeliColors.forestGreen)
                    .frame(width: 20)
                Text(label)
                    .font(HeliTypography.railTitle(13.5))
                    .foregroundColor(HeliColors.mutedGray)
                Spacer()
                if let badge = badge, !badge.isEmpty {
                    Text(badge)
                        .font(HeliTypography.caption(11.5))
                        .foregroundColor(HeliColors.greenInk)
                        .lineLimit(1)
                }
            }

            content()
        }
        .padding(14)
        .background(HeliColors.cardWarmWhite)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(HeliColors.sageRule, lineWidth: 0.8)
        )
    }

    // MARK: - What Section (Typing First, Presets Below)

    private var whatSection: some View {
        sectionCard(icon: "pencil", label: "What") {
            VStack(alignment: .leading, spacing: 10) {
                // Primary typing field
                HStack(spacing: 8) {
                    TextField("What is this stop? (e.g. Pickup, Soccer...)", text: $customTitle)
                        .font(HeliTypography.body(14))
                        .foregroundColor(HeliColors.greenInk)
                        .tint(HeliColors.forestGreen)
                        .focused($isWhatFocused)
                        .onChange(of: customTitle) { _, val in
                            title = val
                            if let matching = presets.first(where: { $0.label.caseInsensitiveCompare(val.trimmingCharacters(in: .whitespaces)) == .orderedSame }) {
                                kind = matching.id
                                templateCategory = categoryForKind(matching.id)
                            }
                        }

                    if !customTitle.isEmpty {
                        Button(action: {
                            customTitle = ""
                            title = ""
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(HeliColors.mutedGray)
                                .font(.system(size: 14))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(HeliColors.canvasIvory)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isWhatFocused ? HeliColors.forestGreen : HeliColors.sageRule, lineWidth: isWhatFocused ? 1.2 : 0.8)
                )

                // Presets available if the user wants to select one
                VStack(alignment: .leading, spacing: 6) {
                    Text("PRESETS")
                        .font(HeliTypography.eyebrow(9.5))
                        .foregroundColor(HeliColors.mutedGray)
                        .tracking(1.0)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(presets, id: \.id) { preset in
                                let isSelected = !customTitle.isEmpty && (customTitle.caseInsensitiveCompare(preset.label) == .orderedSame)
                                Button(action: {
                                    kind = preset.id
                                    durationMinutes = preset.defaultMins
                                    if !preset.place.isEmpty {
                                        location = preset.place
                                        customLocation = preset.place
                                    }
                                    mode = (preset.id == .dinner) ? "Home" : "Drive"
                                    customTitle = preset.label
                                    title = preset.label
                                    templateCategory = categoryForKind(preset.id)
                                    isWhatFocused = false
                                }) {
                                    HStack(spacing: 5) {
                                        HeliIcon(preset.icon, size: 12)
                                        Text(preset.label)
                                            .font(HeliTypography.railMeta(11.5))
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .foregroundColor(isSelected ? HeliColors.forestGreen : HeliColors.greenInk)
                                    .background(isSelected ? HeliColors.activeNavTab : HeliColors.cardWarmWhite)
                                    .clipShape(Capsule())
                                    .overlay(
                                        Capsule().stroke(isSelected ? HeliColors.forestGreen : HeliColors.sageRule, lineWidth: isSelected ? 1.2 : 0.8)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Who Section (Always Shown Directly)

    private var whoSection: some View {
        sectionCard(
            icon: "user-round",
            label: "Who",
            badge: selectedKids.isEmpty ? "Solo" : selectedKids.sorted().joined(separator: ", ")
        ) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    let isSolo = selectedKids.isEmpty
                    Button(action: {
                        selectedKids.removeAll()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "person.slash")
                                .font(.system(size: 11, weight: .semibold))
                            Text("No child")
                                .font(HeliTypography.railMeta(12))
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 38)
                        .foregroundColor(isSolo ? HeliColors.forestGreen : HeliColors.greenInk)
                        .background(isSolo ? HeliColors.activeNavTab : HeliColors.cardWarmWhite)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().stroke(isSolo ? HeliColors.forestGreen : HeliColors.sageRule, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)

                    ForEach(store.children(), id: \.self) { child in
                        let selected = selectedKids.contains(child)
                        Button(action: {
                            if selectedKids.contains(child) {
                                selectedKids.remove(child)
                            } else {
                                selectedKids.insert(child)
                            }
                        }) {
                            HStack(spacing: 6) {
                                AvatarDisc(name: child, size: 20, isKid: true)
                                Text(child)
                                    .font(HeliTypography.railMeta(12))
                            }
                            .padding(.horizontal, 10)
                            .frame(height: 38)
                            .foregroundColor(selected ? HeliColors.forestGreen : HeliColors.greenInk)
                            .background(selected ? HeliColors.activeNavTab : HeliColors.cardWarmWhite)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().stroke(selected ? HeliColors.forestGreen : HeliColors.sageRule, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Where Section (Typing First, Saved Places Presets Below)

    private var whereSection: some View {
        sectionCard(icon: location.isEmpty ? "map-pin" : (location == store.home() ? "house" : "map-pin"), label: "Where") {
            VStack(alignment: .leading, spacing: 10) {
                // Primary search / address typing field
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(HeliColors.forestGreen)
                        .font(.system(size: 13))

                    TextField("Type school, business, or address...", text: $customLocation)
                        .font(HeliTypography.body(13.5))
                        .foregroundColor(HeliColors.greenInk)
                        .tint(HeliColors.forestGreen)
                        .focused($isWhereFocused)
                        .onChange(of: customLocation) { _, val in
                            if isSelectingPrediction {
                                isSelectingPrediction = false
                                return
                            }
                            searchTask?.cancel()
                            let query = val.trimmingCharacters(in: .whitespaces)
                            location = query
                            selectedAddress = query
                            selectedCoordinate = nil
                            mode = (query.caseInsensitiveCompare(store.home()) == .orderedSame) ? "Home" : "Drive"
                            guard query.count >= 1 else {
                                placePredictions = []
                                isSearchingPlaces = false
                                return
                            }
                            isSearchingPlaces = true
                            searchTask = Task {
                                try? await Task.sleep(nanoseconds: 200_000_000)
                                if Task.isCancelled { return }
                                let results = await GoogleMapsService.shared.autocompletePlaces(
                                    query: query,
                                    apiKey: store.googleMapsApiKey,
                                    locationBias: LocationService.shared.currentLocation?.coordinate,
                                    savedLocations: store.locations
                                )
                                if !Task.isCancelled {
                                    await MainActor.run {
                                        self.placePredictions = results
                                        self.isSearchingPlaces = false
                                    }
                                }
                            }
                        }

                    if isSearchingPlaces {
                        ProgressView()
                            .scaleEffect(0.7)
                    }

                    if !customLocation.isEmpty {
                        Button(action: {
                            customLocation = ""
                            location = ""
                            selectedAddress = ""
                            selectedCoordinate = nil
                            placePredictions = []
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(HeliColors.mutedGray)
                                .font(.system(size: 14))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(HeliColors.canvasIvory)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isWhereFocused ? HeliColors.forestGreen : HeliColors.sageRule, lineWidth: isWhereFocused ? 1.2 : 0.8)
                )

                // Autocomplete Suggestions List
                if !placePredictions.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(placePredictions) { pred in
                            Button(action: {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                isSelectingPrediction = customLocation != pred.primaryText
                                location = pred.primaryText
                                mode = "Drive"
                                customLocation = pred.primaryText
                                let immediateAddress = pred.secondaryText.isEmpty ? pred.fullText : pred.secondaryText
                                selectedAddress = immediateAddress
                                if let lat = pred.latitude, let lng = pred.longitude {
                                    selectedCoordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
                                }
                                placePredictions = []
                                isWhereFocused = false

                                Task {
                                    if let details = try? await GoogleMapsService.shared.fetchPlaceDetails(
                                        placeId: pred.placeId,
                                        apiKey: store.googleMapsApiKey,
                                        fallbackName: pred.primaryText,
                                        fallbackAddress: immediateAddress
                                    ) {
                                        await MainActor.run {
                                            if !details.formattedAddress.isEmpty && details.formattedAddress != "Address unavailable" {
                                                self.selectedAddress = details.formattedAddress
                                            }
                                            self.selectedCoordinate = CLLocationCoordinate2D(latitude: details.latitude, longitude: details.longitude)
                                        }
                                    }
                                }
                            }) {
                                HStack(spacing: 10) {
                                    Image(systemName: pred.placeId.starts(with: "saved-") ? "bookmark.fill" : "mappin.circle.fill")
                                        .font(.system(size: 16))
                                        .foregroundColor(HeliColors.forestGreen)

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
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(PlainButtonStyle())

                            if pred.id != placePredictions.last?.id {
                                Divider().background(HeliColors.sageRule.opacity(0.5))
                            }
                        }
                    }
                    .background(HeliColors.cardWarmWhite)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(HeliColors.forestGreen.opacity(0.4), lineWidth: 1))
                }

                // Selected Address Details Badge
                if !selectedAddress.isEmpty && selectedAddress != location {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 6) {
                            Image(systemName: "mappin.and.ellipse")
                                .foregroundColor(HeliColors.forestGreen)
                                .font(.system(size: 13, weight: .semibold))
                            Text(location.isEmpty ? "Selected Place" : location)
                                .font(HeliTypography.railTitle(13))
                                .foregroundColor(HeliColors.greenInk)
                                .lineLimit(1)
                            Spacer()
                            HStack(spacing: 3) {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 10))
                                Text(selectedCoordinate != nil ? "Verified GPS" : "Address Set")
                                    .font(HeliTypography.eyebrow(9.5))
                            }
                            .foregroundColor(HeliColors.forestGreen)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(HeliColors.cardWarmWhite)
                            .clipShape(Capsule())
                        }

                        Text(selectedAddress)
                            .font(HeliTypography.caption(12))
                            .foregroundColor(HeliColors.mutedGray)
                            .lineLimit(2)
                    }
                    .padding(10)
                    .background(HeliColors.forestTint)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(HeliColors.forestGreen.opacity(0.35), lineWidth: 1)
                    )

                    // Optional toggle to save to household places
                    if !store.locations.contains(where: { $0.name.lowercased() == location.lowercased() }) {
                        Toggle("Save to household saved places", isOn: $saveToHouseholdPlaces)
                            .font(HeliTypography.caption(11.5))
                            .tint(HeliColors.forestGreen)
                            .padding(.top, 2)
                    }
                }

                // Presets: Saved Places
                if !store.locations.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("SAVED PLACES")
                            .font(HeliTypography.eyebrow(9.5))
                            .foregroundColor(HeliColors.mutedGray)
                            .tracking(1.0)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(store.locations) { loc in
                                    let isSelected = (location.caseInsensitiveCompare(loc.name) == .orderedSame)
                                    Button(action: {
                                        isSelectingPrediction = true
                                        location = loc.name
                                        customLocation = loc.name
                                        mode = (loc.name == store.home()) ? "Home" : "Drive"
                                        selectedAddress = loc.address
                                        if let lat = loc.latitude, let lng = loc.longitude {
                                            selectedCoordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
                                        } else {
                                            selectedCoordinate = nil
                                        }
                                        placePredictions = []
                                        isWhereFocused = false
                                    }) {
                                        HStack(spacing: 5) {
                                            HeliIcon(loc.icon ?? "map-pin", size: 12)
                                            Text(loc.name)
                                                .font(HeliTypography.railMeta(11.5))
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 7)
                                        .foregroundColor(isSelected ? HeliColors.forestGreen : HeliColors.greenInk)
                                        .background(isSelected ? HeliColors.activeNavTab : HeliColors.cardWarmWhite)
                                        .clipShape(Capsule())
                                        .overlay(
                                            Capsule().stroke(isSelected ? HeliColors.forestGreen : HeliColors.sageRule, lineWidth: isSelected ? 1.2 : 0.8)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - When Section (Date, Weekdays on as default, Repeat toggle reveals weekly, Time)

    private var whenSection: some View {
        sectionCard(icon: "calendar", label: "When", badge: whenSummaryValue) {
            VStack(alignment: .leading, spacing: 14) {
                if existingStop?.seriesId != nil {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("EDIT SCOPE")
                            .font(HeliTypography.eyebrow(10))
                            .foregroundColor(HeliColors.mutedGray)
                        Picker("Edit scope", selection: $editScope) {
                            Text("This occurrence").tag(RecurrenceEditScope.occurrence)
                            Text("Entire series").tag(RecurrenceEditScope.series)
                        }
                        .pickerStyle(.segmented)
                    }
                }

                // 1. Date Selection Row
                VStack(alignment: .leading, spacing: 6) {
                    Text("DATE")
                        .font(HeliTypography.eyebrow(10))
                        .foregroundColor(HeliColors.mutedGray)
                        .tracking(1.2)

                    HStack {
                        Image(systemName: "calendar")
                            .foregroundColor(HeliColors.forestGreen)
                            .font(.system(size: 14))

                        DatePicker(
                            "",
                            selection: $stopDate,
                            displayedComponents: [.date]
                        )
                        .datePickerStyle(.compact)
                        .labelsHidden()
                        .tint(HeliColors.forestGreen)
                        .onChange(of: stopDate) { _, newD in
                            dateString = stringFromDate(newD)
                            let w = weekdayIndex(for: newD)
                            if !isRepeating && repeatDays.count <= 1 {
                                repeatDays = [w]
                            }
                        }

                        Spacer()

                        Text(formatDisplayDate(dateString))
                            .font(HeliTypography.cardTitle(13))
                            .foregroundColor(HeliColors.greenInk)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(HeliColors.canvasIvory)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(HeliColors.sageRule, lineWidth: 0.8))
                }

                // 2. Weekday Selector (On as default)
                VStack(alignment: .leading, spacing: 6) {
                    Text("DAYS OF WEEK")
                        .font(HeliTypography.eyebrow(10))
                        .foregroundColor(HeliColors.mutedGray)
                        .tracking(1.2)

                    HStack(spacing: 5) {
                        ForEach(weekdays) { day in
                            let isSelected = repeatDays.contains(day.id)
                            Button(action: {
                                if isSelected {
                                    if repeatDays.count > 1 {
                                        repeatDays.remove(day.id)
                                    }
                                } else {
                                    repeatDays.insert(day.id)
                                }
                                if repeatDays.count == 1, let singleDay = repeatDays.first {
                                    let mon = PlanCore.monday(dateString)
                                    dateString = PlanCore.dateAdd(mon, singleDay)
                                    stopDate = dateFromString(dateString)
                                }
                            }) {
                                VStack(spacing: 2) {
                                    Text(day.letter).font(HeliTypography.actionButton(12))
                                    Text(day.name).font(.system(size: 8.5))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .foregroundColor(isSelected ? HeliColors.cardWarmWhite : HeliColors.greenInk)
                                .background(isSelected ? HeliColors.forestGreen : HeliColors.cardWarmWhite)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(isSelected ? HeliColors.forestGreen : HeliColors.sageRule, lineWidth: 0.8)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // 3. Repeat Toggle to reveal weekly recurrence
                if existingStop?.seriesId == nil || editScope == .series {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle(isOn: $isRepeating.animation(.easeInOut(duration: 0.2))) {
                            HStack(spacing: 8) {
                                Image(systemName: "repeat")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(HeliColors.forestGreen)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Repeat")
                                        .font(HeliTypography.cardTitle(13))
                                        .foregroundColor(HeliColors.greenInk)
                                    Text("Repeat this pattern beyond the current week")
                                        .font(HeliTypography.caption(11))
                                        .foregroundColor(HeliColors.mutedGray)
                                }
                            }
                        }
                        .tint(HeliColors.forestGreen)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(HeliColors.canvasIvory)
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                        if isRepeating {
                            VStack(alignment: .leading, spacing: 10) {
                                Picker("Ends", selection: $recurrenceEndMode) {
                                    Text("For weeks").tag("weeks")
                                    Text("Until date").tag("date")
                                }
                                .pickerStyle(.segmented)

                                if recurrenceEndMode == "weeks" {
                                    HStack {
                                        Button("20 weeks") { recurrenceWeekCount = 20 }
                                        Button("30 weeks") { recurrenceWeekCount = 30 }
                                        Spacer()
                                        Stepper("\(recurrenceWeekCount)", value: $recurrenceWeekCount, in: 2...52)
                                            .fixedSize()
                                    }
                                    Text("For \(recurrenceWeekCount) calendar weeks, including the starting week.")
                                        .font(HeliTypography.caption(11))
                                        .foregroundColor(HeliColors.mutedGray)
                                } else {
                                    DatePicker("Repeat through", selection: $recurrenceThroughDate, displayedComponents: .date)
                                        .datePickerStyle(.compact)
                                }

                                Text(recurrencePreviewSummary)
                                    .font(HeliTypography.caption(11))
                                    .foregroundColor(previewOccurrenceCount > 0 ? HeliColors.greenInk : HeliColors.warningText)
                            }
                            .padding(.top, 4)
                        }
                    }
                } else {
                    Text("Only this occurrence will change. Its series schedule and other assignments stay intact.")
                        .font(HeliTypography.caption(11))
                        .foregroundColor(HeliColors.mutedGray)
                }

                Divider().background(HeliColors.sageRule)

                // 4. Start Hour & Duration Stepper
                VStack(alignment: .leading, spacing: 6) {
                    Text("TIME & DURATION")
                        .font(HeliTypography.eyebrow(10))
                        .foregroundColor(HeliColors.mutedGray)
                        .tracking(1.2)

                    VStack(spacing: 8) {
                        Stepper(onIncrement: {
                            startMinutes = min(23 * 60, startMinutes + 15)
                        }, onDecrement: {
                            startMinutes = max(6 * 60, startMinutes - 15)
                        }) {
                            stepperLabel("Start", TimeFormat.formatTime(startMinutes))
                        }

                        Stepper(onIncrement: {
                            durationMinutes = min(240, durationMinutes + 15)
                        }, onDecrement: {
                            durationMinutes = max(10, durationMinutes - 15)
                        }) {
                            stepperLabel("Length", TimeFormat.formatDurationShort(durationMinutes))
                        }
                    }
                }

                // 5. Hour Presets (7 AM to 8 PM)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(7...20, id: \.self) { hour in
                            let m = hour * 60
                            let selected = (startMinutes == m)
                            Button(action: { startMinutes = m }) {
                                Text("\(hour > 12 ? hour - 12 : hour)\(hour >= 12 ? "p" : "a")")
                                    .font(HeliTypography.railMeta(11))
                                    .padding(.horizontal, 8)
                                    .frame(height: 32)
                                    .foregroundColor(selected ? HeliColors.forestGreen : HeliColors.greenInk)
                                    .background(selected ? HeliColors.activeNavTab : HeliColors.cardWarmWhite)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    /// Stepper takes its label from a view builder, so the value has to carry
    /// its own colour — a plain string label inherits the system label colour.
    private func stepperLabel(_ title: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(HeliTypography.body(13))
                .foregroundColor(HeliColors.mutedGray)
            Text(value)
                .font(HeliTypography.body(13))
                .foregroundColor(HeliColors.greenInk)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    // MARK: - Driver Section (Always Shown Directly)

    private var driverSection: some View {
        sectionCard(icon: "users", label: "Driver", badge: driverSummaryValue) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(store.caregivers(), id: \.self) { name in
                    let selected = (driver == name)
                    Button(action: { driver = name }) {
                        HStack(spacing: 6) {
                            AvatarDisc(name: name, size: 20)
                            Text(name)
                                .font(HeliTypography.railMeta(12))
                        }
                        .padding(.horizontal, 8)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .foregroundColor(selected ? HeliColors.forestGreen : HeliColors.greenInk)
                        .background(selected ? HeliColors.activeNavTab : HeliColors.cardWarmWhite)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(selected ? HeliColors.forestGreen : HeliColors.sageRule, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }

                // Family button (All caretakers)
                let isFamily = (driver == "Family")
                Button(action: { driver = "Family" }) {
                    HStack(spacing: 5) {
                        AvatarDisc(name: "Family", size: 20)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Family")
                                .font(HeliTypography.railMeta(12))
                            Text("All caretakers")
                                .font(.system(size: 8))
                                .foregroundColor(isFamily ? HeliColors.forestGreen : HeliColors.mutedGray)
                        }
                    }
                    .padding(.horizontal, 6)
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .foregroundColor(isFamily ? HeliColors.forestGreen : HeliColors.greenInk)
                    .background(isFamily ? HeliColors.activeNavTab : HeliColors.cardWarmWhite)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(isFamily ? HeliColors.forestGreen : HeliColors.sageRule, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)

                // TBD button
                let isTBD = (driver == "TBD")
                Button(action: { driver = "TBD" }) {
                    HStack(spacing: 6) {
                        AvatarDisc(name: "TBD", size: 20)
                        Text("Needs driver")
                            .font(HeliTypography.railMeta(11.5))
                    }
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .foregroundColor(isTBD ? HeliColors.tbd.text : HeliColors.greenInk)
                    .background(isTBD ? HeliColors.tbd.bg : HeliColors.cardWarmWhite)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(isTBD ? HeliColors.tbd.ink : HeliColors.sageRule, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Save Action

    private func requestSave() {
        if existingStop?.seriesId != nil && editScope == .series {
            showSaveSeriesConfirmation = true
        } else {
            saveStop()
        }
    }

    private func saveStop() {
        let finalTitle = computedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !finalTitle.isEmpty else {
            saveError = "Give this event a name."
            return
        }
        let startStr = String(format: "%02d:%02d", startMinutes / 60, startMinutes % 60)
        let endMinutes = startMinutes + durationMinutes
        let endStr = String(format: "%02d:%02d", endMinutes / 60, endMinutes % 60)
        let recurrence = recurrencePattern
        let isSeries = isRepeating || repeatDays.count > 1
        let draft = TaskRecord(
            id: existingStop?.id ?? "ev-\(UUID().uuidString)",
            date: recurrence.startDate,
            time: startStr,
            endTime: endStr,
            title: finalTitle,
            owner: driver,
            lead: driver,
            kids: Array(selectedKids).sorted(),
            kid: selectedKids.sorted().joined(separator: ", "),
            location: location,
            mode: mode,
            kind: kind,
            gcal: gcal,
            allDay: false,
            seriesId: existingStop?.seriesId,
            latitude: selectedCoordinate?.latitude ?? existingStop?.latitude,
            longitude: selectedCoordinate?.longitude ?? existingStop?.longitude,
            formattedAddress: selectedAddress.isEmpty ? existingStop?.formattedAddress : selectedAddress
        )

        do {
            // Validate before any secondary durable mutation such as adding a
            // saved place or shortcut.
            _ = try PlanCore.occurrences(
                draft,
                recurrence: (existingStop?.seriesId != nil && editScope == .occurrence)
                    ? RecurrencePattern(mode: .none, startDate: draft.date, timeZone: store.timeZone)
                    : recurrence,
                seriesId: existingStop?.seriesId
            )

            if saveToHouseholdPlaces && !location.isEmpty,
               !store.locations.contains(where: { $0.name.caseInsensitiveCompare(location) == .orderedSame }) {
                try store.updateLocation(
                    index: store.locations.endIndex,
                    data: LocationItem(
                        name: location,
                        address: selectedAddress.isEmpty ? location : selectedAddress,
                        icon: "map-pin",
                        latitude: selectedCoordinate?.latitude,
                        longitude: selectedCoordinate?.longitude
                    )
                )
            }

            let savedRecords = try store.saveEvent(
                draft: draft,
                recurrence: recurrence,
                scope: existingStop == nil ? (isSeries ? .series : .occurrence) : editScope,
                sourceOccurrenceID: existingStop?.id
            )

            if (gcal || existingStop?.gcal == true || existingStop?.calendarId?.hasPrefix("google|") == true) && store.isGoogleAuthenticated {
                Task {
                    for rec in savedRecords {
                        try? await store.exportEventToGoogleCalendar(rec)
                    }
                }
            }

            if saveAsTemplate {
                let tmpl = TemplateItem(
                    id: "tmpl-\(UUID().uuidString.prefix(8))",
                    title: finalTitle,
                    time: startStr,
                    endTime: endStr,
                    kids: Array(selectedKids).sorted(),
                    kid: selectedKids.sorted().joined(separator: ", "),
                    owner: driver,
                    location: location.isEmpty ? store.home() : location,
                    mode: mode,
                    duration: durationMinutes,
                    category: templateCategory,
                    weekdays: isSeries ? repeatDays.sorted() : nil,
                    recurrenceWeekCount: isRepeating && recurrenceEndMode == "weeks" ? recurrenceWeekCount : nil
                )
                if !store.templates.contains(where: { $0.title.caseInsensitiveCompare(tmpl.title) == .orderedSame }) {
                    store.upsertTemplate(tmpl)
                }
            }
            onSaved?()
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func deleteStop() {
        guard let existingStop else { return }
        store.deleteEvent(id: existingStop.id, scope: editScope)
        onSaved?()
        dismiss()
    }

    private var recurrencePattern: RecurrencePattern {
        let isWeekly = isRepeating || repeatDays.count > 1
        let weekCount = isRepeating ? recurrenceWeekCount : 1
        let mon = PlanCore.monday(dateString.isEmpty ? store.dateForDay(store.activeDay) : dateString)
        let minDay = repeatDays.min() ?? PlanCore.weekdayIndex(dateString)
        let patternStartDate = isWeekly ? PlanCore.dateAdd(mon, minDay) : (dateString.isEmpty ? store.dateForDay(store.activeDay) : dateString)

        return RecurrencePattern(
            mode: isWeekly ? .weekly : .none,
            startDate: patternStartDate,
            timeZone: store.timeZone,
            weekdays: repeatDays.sorted(),
            end: (isRepeating && recurrenceEndMode == "date")
                ? .throughDate(stringFromDate(recurrenceThroughDate))
                : .weekCount(weekCount)
        )
    }

    private var previewOccurrences: [TaskRecord] {
        var preview = existingStop ?? TaskRecord(id: "preview")
        preview.date = recurrencePattern.startDate
        preview.time = String(format: "%02d:%02d", startMinutes / 60, startMinutes % 60)
        preview.endTime = String(format: "%02d:%02d", (startMinutes + durationMinutes) / 60, (startMinutes + durationMinutes) % 60)
        preview.title = computedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Preview" : computedTitle
        return (try? PlanCore.occurrences(preview, recurrence: recurrencePattern, seriesId: existingStop?.seriesId ?? "preview")) ?? []
    }

    private var previewOccurrenceCount: Int {
        if isRepeating || repeatDays.count > 1 {
            return previewOccurrences.count
        }
        return 1
    }

    private var recurrencePreviewSummary: String {
        let rows = previewOccurrences
        guard let first = rows.first, let last = rows.last else {
            return "No occurrences in this range. Choose a later end or another weekday."
        }
        return "\(rows.count) occurrence\(rows.count == 1 ? "" : "s") · \(first.date) through \(last.date)"
    }

    private var seriesDeleteCount: Int {
        guard let id = existingStop?.seriesId else { return existingStop == nil ? 0 : 1 }
        return store.events(inSeries: id).count
    }

    private var seriesHistoricalCount: Int {
        guard let id = existingStop?.seriesId else { return 0 }
        return store.events(inSeries: id).filter { $0.date < PlanCore.currentDeviceDate() }.count
    }

    // MARK: - Date & Formatting Helpers

    private var repeatDaysSummary: String {
        let sorted = repeatDays.sorted()
        return sorted.compactMap { idx in
            weekdays.first(where: { $0.id == idx })?.name
        }.joined(separator: ", ")
    }

    private func weekdayIndex(for date: Date) -> Int {
        var cal = Calendar(identifier: .gregorian)
        // `DatePicker` presents dates in the device's calendar time zone. Keep
        // the weekday calculation on that same calendar day; using UTC here can
        // turn a locally selected Sunday into Monday before it reaches the
        // Monday-through-Sunday recurrence row.
        cal.timeZone = .current
        let w = cal.component(.weekday, from: date) // 1=Sun, 2=Mon...
        return (w + 5) % 7 // 0=Mon ... 6=Sun
    }

    private func dateFromString(_ str: String) -> Date {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd"
        // This Date exists only to back the UI picker. Parsing at local midnight
        // prevents a date-only Monday from rendering as Sunday west of UTC.
        df.timeZone = .current
        return df.date(from: str) ?? Date()
    }

    private func stringFromDate(_ d: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone = .current
        return df.string(from: d)
    }

    private func formatDisplayDate(_ str: String) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone = .current
        guard let d = df.date(from: str) else { return str }
        let out = DateFormatter()
        out.locale = Locale.current
        out.dateFormat = "EEE, MMM d, yyyy"
        out.timeZone = .current
        return out.string(from: d)
    }

    private func formatDayShort(_ dStr: String) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone = .current
        guard let d = df.date(from: dStr) else { return dStr }
        let out = DateFormatter()
        out.locale = Locale.current
        out.dateFormat = "EEE, MMM d"
        out.timeZone = .current
        return out.string(from: d)
    }

    private func formatMinutes(_ mins: Int) -> String {
        return TimeFormat.formatTime(mins)
    }

    private func categoryForKind(_ k: TaskKind) -> String { k.category }
}

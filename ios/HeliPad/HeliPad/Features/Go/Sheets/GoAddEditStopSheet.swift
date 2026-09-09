import SwiftUI
import CoreLocation

public struct GoAddEditStopSheet: View {
    @ObservedObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    public var existingStop: TaskRecord?
    /// Values to open a brand new stop with (the day the caller was looking at,
    /// or a shortcut's template). Ignored when editing an existing stop.
    public var prefill: TaskRecord?
    /// Every occurrence of the series being edited, so saving keeps each day's
    /// id and its done/notes state instead of minting fresh rows.
    public var seriesEvents: [TaskRecord]
    /// Weekdays to open with already ticked — a shortcut carrying its usual days.
    public var preselectedDays: Set<Int>?
    public var onSave: ([TaskRecord]) -> Void
    public var onDelete: ((String) -> Void)?

    @State private var activeField: String? = nil // "what", "who", "where", "when", "driver"
    @State private var title: String = ""
    @State private var kind: TaskKind = .pickup
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

    // Shortcut / Template State
    @State private var saveAsTemplate: Bool = false
    @State private var templateCategory: String = "Sports"

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
        seriesEvents: [TaskRecord] = [],
        preselectedDays: Set<Int>? = nil,
        onSave: @escaping ([TaskRecord]) -> Void,
        onDelete: ((String) -> Void)? = nil
    ) {
        self.store = store
        self.existingStop = existingStop
        self.prefill = prefill
        self.seriesEvents = seriesEvents
        self.preselectedDays = preselectedDays
        self.onSave = onSave
        self.onDelete = onDelete
    }

    // Single-stop convenience initializer
    public init(
        store: AppStore,
        existingStop: TaskRecord? = nil,
        prefill: TaskRecord? = nil,
        seriesEvents: [TaskRecord] = [],
        preselectedDays: Set<Int>? = nil,
        onSaveSingle: @escaping (TaskRecord) -> Void,
        onDelete: ((String) -> Void)? = nil
    ) {
        self.store = store
        self.existingStop = existingStop
        self.prefill = prefill
        self.seriesEvents = seriesEvents
        self.preselectedDays = preselectedDays
        self.onSave = { stops in
            for s in stops { onSaveSingle(s) }
        }
        self.onDelete = onDelete
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

                    // 5 Field Rows with Accordion Pickers
                    VStack(spacing: 8) {
                        fieldRow(
                            id: "what",
                            label: "What",
                            value: computedTitle,
                            icon: "pencil"
                        ) {
                            whatPicker
                        }

                        fieldRow(
                            id: "who",
                            label: "Who",
                            value: selectedKids.isEmpty ? "No child (Solo)" : selectedKids.sorted().joined(separator: ", "),
                            icon: "user-round"
                        ) {
                            whoPicker
                        }

                        fieldRow(
                            id: "where",
                            label: "Where",
                            value: location,
                            subtitle: location.isEmpty ? "" : selectedAddress,
                            icon: location.isEmpty ? "map-pin" : (location == store.home() ? "house" : "map-pin")
                        ) {
                            wherePicker
                        }

                        fieldRow(
                            id: "when",
                            label: "When",
                            value: whenSummaryValue,
                            icon: "calendar"
                        ) {
                            whenPicker
                        }

                        fieldRow(
                            id: "driver",
                            label: "Driver",
                            value: driverSummaryValue,
                            icon: "users"
                        ) {
                            driverPicker
                        }
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
                    Toggle("Add to Google Calendar", isOn: $gcal)
                        .font(HeliTypography.body(13))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(HeliColors.cardWarmWhite)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    // Primary Action Button
                    Button(action: saveStop) {
                        HStack(spacing: 6) {
                            if repeatDays.count > 1 {
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
                    if let existing = existingStop, let onDelete = onDelete {
                        Button(action: {
                            onDelete(existing.id)
                            dismiss()
                        }) {
                            Text("Remove this stop")
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
        }
    }

    private var actionButtonTitle: String {
        if existingStop != nil {
            return repeatDays.count > 1 ? "Save across \(repeatDays.count) days" : "Save changes"
        }
        return repeatDays.count > 1 ? "Add \(repeatDays.count) repeating stops" : "Add stop"
    }

    private var whenSummaryValue: String {
        let timeStr = "\(TimeFormat.formatTime(startMinutes)) (\(TimeFormat.formatDurationShort(durationMinutes)))"
        if repeatDays.count > 1 {
            return "\(repeatDaysSummary) · \(timeStr)"
        }
        return "\(formatDayShort(dateString)) · \(timeStr)"
    }

    private var driverSummaryValue: String {
        if driver == "TBD" { return "Needs driver" }
        if driver == "Family" { return "Family (All caretakers)" }
        return driver
    }

    private var computedTitle: String {
        if !customTitle.isEmpty { return customTitle }
        if !title.isEmpty { return title }
        if selectedKids.count == 1, let single = selectedKids.first {
            return "\(single) \(kind.rawValue.capitalized)"
        }
        return kind.rawValue.capitalized
    }

    private func seedInitialValues() {
        if let e = existingStop {
            title = e.title
            customTitle = e.title
            kind = e.kind
            selectedKids = Set(e.kids)
            location = e.location
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
        } else {
            // Start from whatever the caller handed us — the day they were looking
            // at, or a shortcut's template — and fill the gaps with the defaults.
            let seed = prefill
            kind = seed?.kind ?? .pickup

            let seedLocation = (seed?.location ?? "").trimmingCharacters(in: .whitespaces)
            location = seedLocation
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
        }

        // A shortcut arrives with the days it usually runs on.
        if let usual = preselectedDays, !usual.isEmpty {
            repeatDays = usual
        }

        // Editing a whole series: light up every weekday it already runs on.
        if !seriesEvents.isEmpty {
            let days = Set(seriesEvents.map { PlanCore.weekdayIndex($0.date) })
            if !days.isEmpty {
                repeatDays = days
            }
        }

        templateCategory = categoryForKind(kind)
    }

    // MARK: - Preview Card

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(computedTitle)
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

                if repeatDays.count > 1 {
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

    // MARK: - Field Row Template

    private func fieldRow<PickerContent: View>(
        id: String,
        label: String,
        value: String,
        subtitle: String? = nil,
        icon: String,
        @ViewBuilder picker: @escaping () -> PickerContent
    ) -> some View {
        let isOpen = (activeField == id)

        return VStack(spacing: 0) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    activeField = isOpen ? nil : id
                }
            }) {
                HStack(spacing: 12) {
                    HeliIcon(icon, size: 14)
                        .foregroundColor(HeliColors.forestGreen)
                        .frame(width: 20)
                    Text(label)
                        .font(HeliTypography.railTitle(13.5))
                        .foregroundColor(HeliColors.mutedGray)
                        .frame(width: 50, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(value)
                            .font(HeliTypography.body(13.5))
                            .foregroundColor(HeliColors.greenInk)
                            .lineLimit(1)
                        if let sub = subtitle, !sub.isEmpty, sub != value {
                            Text(sub)
                                .font(HeliTypography.caption(11))
                                .foregroundColor(HeliColors.mutedGray)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(HeliColors.mutedGray)
                }
                .padding(.horizontal, 14)
                .frame(minHeight: (subtitle != nil && !subtitle!.isEmpty) ? 58 : 52)
                .background(HeliColors.cardWarmWhite)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(isOpen ? HeliColors.forestGreen : HeliColors.sageRule, lineWidth: 0.8)
                )
            }

            if isOpen {
                VStack(alignment: .leading, spacing: 12) {
                    picker()
                }
                .padding(14)
                .background(HeliColors.cardWarmWhite.opacity(0.85))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.top, 4)
            }
        }
    }

    // MARK: - What Picker

    private var whatPicker: some View {
        VStack(spacing: 10) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(presets, id: \.id) { preset in
                    let selected = (kind == preset.id && customTitle.isEmpty)
                    Button(action: {
                        kind = preset.id
                        durationMinutes = preset.defaultMins
                        location = preset.place
                        mode = (preset.id == .dinner) ? "Home" : "Drive"
                        customTitle = ""
                        templateCategory = categoryForKind(preset.id)
                    }) {
                        VStack(spacing: 4) {
                            HeliIcon(preset.icon, size: 16)
                            Text(preset.label)
                                .font(HeliTypography.railMeta(11))
                        }
                        .foregroundColor(selected ? HeliColors.forestGreen : HeliColors.greenInk)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(selected ? HeliColors.activeNavTab : HeliColors.cardWarmWhite)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(selected ? HeliColors.forestGreen : HeliColors.sageRule, lineWidth: 1)
                        )
                    }
                }
            }

            // Custom Title escape hatch
            HStack(spacing: 8) {
                Text("✎")
                    .foregroundColor(HeliColors.mutedGray)
                TextField("Custom activity name", text: $customTitle)
                    .font(HeliTypography.body(13.5))
                    .foregroundColor(HeliColors.greenInk)
                    .tint(HeliColors.forestGreen)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(HeliColors.cardWarmWhite)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(HeliColors.sageRule, lineWidth: 0.8))
        }
    }

    // MARK: - Who Picker

    private var whoPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // No child / Solo option
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
                }
            }
        }
    }

    // MARK: - Where Picker

    private var wherePicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 1. Saved Household Locations Grid
            Text("SAVED PLACES")
                .font(HeliTypography.eyebrow(10))
                .foregroundColor(HeliColors.mutedGray)
                .tracking(1.2)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(store.locations) { loc in
                    let selected = (location == loc.name)
                    Button(action: {
                        // `onChange` only fires when the search text actually
                        // changes. Do not leave its suppression flag armed when
                        // the field is already empty.
                        isSelectingPrediction = !customLocation.isEmpty
                        location = loc.name
                        mode = (loc.name == store.home()) ? "Home" : "Drive"
                        customLocation = ""
                        selectedAddress = loc.address
                        if let lat = loc.latitude, let lng = loc.longitude {
                            selectedCoordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
                        } else {
                            selectedCoordinate = nil
                        }
                        placePredictions = []
                    }) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                HeliIcon(loc.icon ?? "map-pin", size: 12)
                                    .foregroundColor(selected ? HeliColors.forestGreen : HeliColors.greenInk)
                                Text(loc.name)
                                    .font(HeliTypography.railTitle(12))
                                    .foregroundColor(selected ? HeliColors.forestGreen : HeliColors.greenInk)
                                    .lineLimit(1)
                            }
                            if !loc.address.isEmpty {
                                Text(loc.address)
                                    .font(HeliTypography.caption(10.5))
                                    .foregroundColor(selected ? HeliColors.forestGreen.opacity(0.85) : HeliColors.mutedGray)
                                    .lineLimit(1)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                        .background(selected ? HeliColors.activeNavTab : HeliColors.cardWarmWhite)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(selected ? HeliColors.forestGreen : HeliColors.sageRule, lineWidth: selected ? 1.2 : 0.8)
                        )
                    }
                }
            }

            Divider().background(HeliColors.sageRule)

            // 2. Search Venue / School / Address with Autocomplete
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("SEARCH OR ENTER ADDRESS")
                        .font(HeliTypography.eyebrow(10))
                        .foregroundColor(HeliColors.mutedGray)
                        .tracking(1.2)
                    Spacer()
                    if isSearchingPlaces {
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                }

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(HeliColors.forestGreen)
                        .font(.system(size: 13))

                    TextField("Type school, business, or address...", text: $customLocation)
                        .font(HeliTypography.body(13.5))
                        .foregroundColor(HeliColors.greenInk)
                        .tint(HeliColors.forestGreen)
                        .onChange(of: customLocation) { _, val in
                            if isSelectingPrediction {
                                isSelectingPrediction = false
                                return
                            }
                            searchTask?.cancel()
                            let query = val.trimmingCharacters(in: .whitespaces)
                            // The text field is also a valid free-form address
                            // entry. Keep the value that will be saved in sync
                            // instead of silently retaining a prefilled place.
                            location = query
                            selectedAddress = query
                            selectedCoordinate = nil
                            mode = "Drive"
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

                    if !customLocation.isEmpty {
                        Button(action: {
                            customLocation = ""
                            placePredictions = []
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(HeliColors.mutedGray)
                                .font(.system(size: 14))
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(HeliColors.cardWarmWhite)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(HeliColors.sageRule, lineWidth: 0.8))

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
                if !selectedAddress.isEmpty {
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
            }
        }
    }

    // MARK: - When Picker (Date, Recurrence, Time)

    private var whenPicker: some View {
        VStack(alignment: .leading, spacing: 14) {
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
                        if repeatDays.count <= 1 {
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
                .background(HeliColors.cardWarmWhite)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(HeliColors.sageRule, lineWidth: 0.8))
            }

            // 2. Multi-Day Recurrence
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("REPEAT ON DAYS")
                        .font(HeliTypography.eyebrow(10))
                        .foregroundColor(HeliColors.mutedGray)
                        .tracking(1.2)
                    Spacer()
                    if repeatDays.count > 1 {
                        Text("\(repeatDays.count) days selected")
                            .font(HeliTypography.caption(10.5))
                            .foregroundColor(HeliColors.forestGreen)
                    }
                }

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
                        }) {
                            VStack(spacing: 2) {
                                Text(day.letter)
                                    .font(HeliTypography.actionButton(12))
                                Text(day.name)
                                    .font(.system(size: 8.5, weight: .regular))
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
                        .buttonStyle(PlainButtonStyle())
                    }
                }

                if repeatDays.count > 1 {
                    HStack(spacing: 5) {
                        Image(systemName: "repeat")
                            .font(.system(size: 11))
                            .foregroundColor(HeliColors.forestGreen)
                        Text("Repeats across \(repeatDays.count) days: \(repeatDaysSummary)")
                            .font(HeliTypography.caption(11))
                            .foregroundColor(HeliColors.greenInk)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(HeliColors.forestTint)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }

            Divider().background(HeliColors.sageRule)

            // 3. Start Hour & Duration Stepper
            VStack(alignment: .leading, spacing: 6) {
                Text("TIME & DURATION")
                    .font(HeliTypography.eyebrow(10))
                    .foregroundColor(HeliColors.mutedGray)
                    .tracking(1.2)

                // One per row: side by side, the stepper controls take a fixed
                // width and the times get truncated to "3:0..." and "Len...".
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

            // 4. Hour Presets (7 AM to 8 PM)
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

    // MARK: - Driver Picker

    private var driverPicker: some View {
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
        }
    }

    // MARK: - Save Action

    private func saveStop() {
        let finalTitle = computedTitle
        let startStr = String(format: "%02d:%02d", startMinutes / 60, startMinutes % 60)
        let endMinutes = startMinutes + durationMinutes
        let endStr = String(format: "%02d:%02d", endMinutes / 60, endMinutes % 60)

        // 1. Save as Shortcut / Template if enabled
        if saveAsTemplate {
            let tmpl = TemplateItem(
                id: "tmpl-\(UUID().uuidString.prefix(8))",
                title: finalTitle,
                time: startStr,
                endTime: endStr,
                kids: Array(selectedKids),
                kid: selectedKids.sorted().joined(separator: ", "),
                owner: driver,
                location: location.isEmpty ? store.home() : location,
                mode: mode,
                duration: durationMinutes,
                notes: nil,
                category: templateCategory
            )
            var allTemplates = store.templates
            if !allTemplates.contains(where: { $0.title.lowercased() == tmpl.title.lowercased() }) {
                allTemplates.append(tmpl)
                store.templates = allTemplates
            }
        }

        // 1.5 Save to household places if selected
        if saveToHouseholdPlaces && !location.isEmpty {
            if !store.locations.contains(where: { $0.name.lowercased() == location.lowercased() }) {
                let newLoc = LocationItem(
                    name: location,
                    address: selectedAddress.isEmpty ? location : selectedAddress,
                    icon: "map-pin",
                    latitude: selectedCoordinate?.latitude,
                    longitude: selectedCoordinate?.longitude
                )
                var allLocs = store.locations
                allLocs.append(newLoc)
                store.locations = allLocs
                store.save()
            }
        }

        // 2. Build Stops (Single or Multi-Day Recurring)
        if repeatDays.count <= 1 {
            // Narrowing a series down to one weekday should land on the weekday
            // that is still selected, not on whichever day the sheet opened at.
            var resolvedDate = dateString.isEmpty ? store.dateForDay(store.activeDay) : dateString
            if let onlyDay = repeatDays.first {
                let openedOn = PlanCore.weekdayIndex(resolvedDate)
                if onlyDay != openedOn {
                    let mondayStr = PlanCore.dateAdd(resolvedDate, -openedOn)
                    resolvedDate = PlanCore.dateAdd(mondayStr, onlyDay)
                }
            }
            let stop = TaskRecord(
                id: existingStop?.id ?? UUID().uuidString,
                date: resolvedDate,
                time: startStr,
                endTime: endStr,
                title: finalTitle,
                owner: driver,
                lead: driver,
                kids: Array(selectedKids),
                kid: selectedKids.sorted().joined(separator: ", "),
                location: location,
                mode: mode,
                kind: kind,
                done: existingStop?.done ?? false,
                tentative: existingStop?.tentative ?? false,
                locked: existingStop?.locked ?? false,
                gcal: gcal,
                notes: existingStop?.notes ?? "",
                allDay: false,
                latitude: selectedCoordinate?.latitude ?? existingStop?.latitude,
                longitude: selectedCoordinate?.longitude ?? existingStop?.longitude,
                formattedAddress: selectedAddress.isEmpty ? existingStop?.formattedAddress : selectedAddress
            )
            onSave([stop])
        } else {
            // Synchronized series across selected weekdays
            let seriesId = existingStop?.seriesId
                ?? seriesEvents.first?.seriesId
                ?? "series-\(UUID().uuidString.prefix(8))"
            let currentWeekday = weekdayIndex(for: stopDate)
            let mondayStr = PlanCore.dateAdd(dateString, -currentWeekday)

            // Occurrences we already have, by day, so a re-save edits them in
            // place rather than replacing them with fresh ids.
            var priorByDate: [String: TaskRecord] = [:]
            for e in seriesEvents { priorByDate[e.date] = e }
            if let existing = existingStop { priorByDate[existing.date] = existing }

            var stopsToSave: [TaskRecord] = []
            for dayIdx in repeatDays.sorted() {
                let occurrenceDate = PlanCore.dateAdd(mondayStr, dayIdx)
                let prior = priorByDate[occurrenceDate]
                let stopId = prior?.id ?? "ev-\(UUID().uuidString.prefix(8))"

                let stop = TaskRecord(
                    id: stopId,
                    date: occurrenceDate,
                    time: startStr,
                    endTime: endStr,
                    title: finalTitle,
                    owner: driver,
                    lead: driver,
                    kids: Array(selectedKids),
                    kid: selectedKids.sorted().joined(separator: ", "),
                    location: location,
                    mode: mode,
                    kind: kind,
                    done: prior?.done ?? false,
                    tentative: prior?.tentative ?? false,
                    locked: prior?.locked ?? false,
                    gcal: gcal,
                    notes: prior?.notes ?? existingStop?.notes ?? "",
                    allDay: false,
                    seriesId: seriesId,
                    latitude: selectedCoordinate?.latitude ?? prior?.latitude ?? existingStop?.latitude,
                    longitude: selectedCoordinate?.longitude ?? prior?.longitude ?? existingStop?.longitude,
                    formattedAddress: selectedAddress.isEmpty ? (prior?.formattedAddress ?? existingStop?.formattedAddress) : selectedAddress
                )
                stopsToSave.append(stop)
            }
            onSave(stopsToSave)
        }

        dismiss()
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

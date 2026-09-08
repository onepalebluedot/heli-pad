import SwiftUI

public struct FamilyLocationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject public var store: AppStore
    public var location: LocationItem?
    public var isNew: Bool

    @State private var name: String = ""
    @State private var address: String = ""
    @State private var latitude: Double? = nil
    @State private var longitude: Double? = nil
    @State private var placePredictions: [PlacePrediction] = []
    @State private var isSearching: Bool = false
    @State private var isSelecting: Bool = false
    @State private var searchTask: Task<Void, Never>? = nil

    public init(store: AppStore, location: LocationItem?, isNew: Bool) {
        self.store = store
        self.location = location
        self.isNew = isNew
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("LOCATION DETAILS").font(HeliTypography.eyebrow(11))) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            TextField("Location Name (e.g. Lincoln High)", text: $name)
                                .font(HeliTypography.body(14))
                                .onChange(of: name) { _, val in
                                    if isSelecting {
                                        isSelecting = false
                                        return
                                    }
                                    searchTask?.cancel()
                                    let query = val.trimmingCharacters(in: .whitespaces)
                                    guard query.count >= 1 else {
                                        placePredictions = []
                                        isSearching = false
                                        return
                                    }
                                    isSearching = true
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
                                                self.isSearching = false
                                            }
                                        }
                                    }
                                }

                            if isSearching {
                                ProgressView()
                                    .scaleEffect(0.7)
                            }
                        }

                        // Autocomplete Suggestions
                        if !placePredictions.isEmpty {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(placePredictions) { pred in
                                    Button(action: {
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        isSelecting = true
                                        name = pred.primaryText
                                        let addr = pred.secondaryText.isEmpty ? pred.fullText : pred.secondaryText
                                        address = addr
                                        if let lat = pred.latitude, let lng = pred.longitude {
                                            latitude = lat
                                            longitude = lng
                                        }
                                        placePredictions = []

                                        Task {
                                            if let details = try? await GoogleMapsService.shared.fetchPlaceDetails(
                                                placeId: pred.placeId,
                                                apiKey: store.googleMapsApiKey,
                                                fallbackName: pred.primaryText,
                                                fallbackAddress: addr
                                            ) {
                                                await MainActor.run {
                                                    if !details.formattedAddress.isEmpty && details.formattedAddress != "Address unavailable" {
                                                        self.address = details.formattedAddress
                                                    }
                                                    self.latitude = details.latitude
                                                    self.longitude = details.longitude
                                                }
                                            }
                                        }
                                    }) {
                                        HStack(spacing: 8) {
                                            Image(systemName: "mappin.circle.fill")
                                                .font(.system(size: 15))
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
                                        .padding(.vertical, 8)
                                        .padding(.horizontal, 4)
                                    }
                                    .buttonStyle(PlainButtonStyle())

                                    if pred.id != placePredictions.last?.id {
                                        Divider()
                                    }
                                }
                            }
                            .padding(.top, 4)
                        }
                    }

                    TextField("Street Address", text: $address)
                        .font(HeliTypography.body(14))

                    if latitude != nil && longitude != nil {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundColor(HeliColors.forestGreen)
                                .font(.system(size: 11))
                            Text("GPS Coordinates Verified")
                                .font(HeliTypography.caption(11))
                                .foregroundColor(HeliColors.forestGreen)
                        }
                    }
                }

                if !isNew {
                    Section {
                        Button("Delete Location", role: .destructive) {
                            deleteLocation()
                            dismiss()
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(HeliColors.canvasIvory)
            .navigationTitle(isNew ? "Add Place" : "Edit Place")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(HeliColors.mutedGray)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveLocation()
                        dismiss()
                    }
                    .font(HeliTypography.actionButton(14))
                    .foregroundColor(HeliColors.forestGreen)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if let loc = location {
                    name = loc.name
                    address = loc.address
                    latitude = loc.latitude
                    longitude = loc.longitude
                }
            }
        }
    }

    private func saveLocation() {
        let cleanName = name.trimmingCharacters(in: .whitespaces)
        let cleanAddr = address.trimmingCharacters(in: .whitespaces)

        if let loc = location {
            // Updating existing location
            var all = store.locations
            if let idx = all.firstIndex(where: { $0.id == loc.id }) {
                let addressChanged = (loc.address.lowercased() != cleanAddr.lowercased())
                let oldName = loc.name

                all[idx].name = cleanName
                all[idx].address = cleanAddr
                all[idx].latitude = latitude
                all[idx].longitude = longitude
                if addressChanged {
                    all[idx].routeKey = nil
                }
                store.locations = all

                // Cascade rename across events and templates if name changed
                if oldName != cleanName {
                    var recs = store.records()
                    for i in recs.indices where recs[i].location == oldName {
                        recs[i].location = cleanName
                    }
                    store.replaceRecords(recs)

                    var tmpls = store.templates
                    for i in tmpls.indices where tmpls[i].location == oldName {
                        tmpls[i].location = cleanName
                    }
                    store.templates = tmpls
                }
            }
        } else {
            // New location
            let newLoc = LocationItem(
                name: cleanName,
                address: cleanAddr,
                latitude: latitude,
                longitude: longitude
            )
            store.locations.append(newLoc)
        }
    }

    private func deleteLocation() {
        if let loc = location {
            store.locations.removeAll { $0.id == loc.id }
        }
    }
}

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
    @State private var placeId: String? = nil
    @State private var source: String? = nil
    @State private var placePredictions: [PlacePrediction] = []
    @State private var isSearching: Bool = false
    @State private var isSelecting: Bool = false
    @State private var searchTask: Task<Void, Never>? = nil
    @State private var resolutionToken = UUID()
    @State private var isApplyingResolvedAddress = false
    @State private var errorMessage: String? = nil

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
                                                guard name.trimmingCharacters(in: .whitespaces) == query else { return }
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
                                        isApplyingResolvedAddress = true
                                        address = addr
                                        if let lat = pred.latitude, let lng = pred.longitude {
                                            latitude = lat
                                            longitude = lng
                                            source = "resolved"
                                        }
                                        placeId = pred.placeId
                                        placePredictions = []
                                        let token = UUID()
                                        resolutionToken = token

                                        Task {
                                            if let details = try? await GoogleMapsService.shared.fetchPlaceDetails(
                                                placeId: pred.placeId,
                                                apiKey: store.googleMapsApiKey,
                                                fallbackName: pred.primaryText,
                                                fallbackAddress: addr
                                            ) {
                                                await MainActor.run {
                                                    guard resolutionToken == token,
                                                          address.caseInsensitiveCompare(addr) == .orderedSame else { return }
                                                    if !details.formattedAddress.isEmpty && details.formattedAddress != "Address unavailable" {
                                                        self.isApplyingResolvedAddress = true
                                                        self.address = details.formattedAddress
                                                    }
                                                    self.latitude = details.latitude
                                                    self.longitude = details.longitude
                                                    self.placeId = details.placeId
                                                    self.source = "resolved"
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
                        .onChange(of: address) { _, _ in
                            if isApplyingResolvedAddress {
                                isApplyingResolvedAddress = false
                                return
                            }
                            resolutionToken = UUID()
                            latitude = nil
                            longitude = nil
                            placeId = nil
                            source = "manual"
                        }

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
                            if deleteLocation() { dismiss() }
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
                        if saveLocation() { dismiss() }
                    }
                    .font(HeliTypography.actionButton(14))
                    .foregroundColor(HeliColors.forestGreen)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if let loc = location {
                    name = loc.name
                    isApplyingResolvedAddress = true
                    address = loc.address
                    latitude = loc.latitude
                    longitude = loc.longitude
                    placeId = loc.placeId
                    source = loc.source
                }
            }
            .alert("Couldn’t Save Place", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Please check the place and try again.")
            }
        }
    }

    private func saveLocation() -> Bool {
        let cleanName = name.trimmingCharacters(in: .whitespaces)
        let cleanAddr = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let item = LocationItem(
                name: cleanName,
                address: cleanAddr,
                icon: location?.icon,
                routeKey: location?.routeKey,
                source: source,
                latitude: latitude,
                longitude: longitude,
                placeId: placeId
        )
        do {
            let index = location.flatMap { original in
                store.locations.firstIndex(where: { $0.name == original.name })
            } ?? store.locations.endIndex
            try store.updateLocation(index: index, data: item)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func deleteLocation() -> Bool {
        guard let loc = location,
              let index = store.locations.firstIndex(where: { $0.name == loc.name }) else { return true }
        do {
            try store.removeLocation(index: index)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}

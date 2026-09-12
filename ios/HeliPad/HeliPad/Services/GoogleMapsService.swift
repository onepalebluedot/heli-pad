import Foundation
import CoreLocation
import MapKit

public struct RouteCacheKey: Hashable {
    let fromLat: Double
    let fromLng: Double
    let toLat: Double
    let toLng: Double

    init(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) {
        // Round to 3 decimal places (~110 meters) to coalesce nearby queries
        self.fromLat = (from.latitude * 1000).rounded() / 1000
        self.fromLng = (from.longitude * 1000).rounded() / 1000
        self.toLat = (to.latitude * 1000).rounded() / 1000
        self.toLng = (to.longitude * 1000).rounded() / 1000
    }
}

// MARK: - Apple MapKit Autocomplete Engine

@MainActor
public class MapKitCompleterService: NSObject, MKLocalSearchCompleterDelegate {
    public static let shared = MapKitCompleterService()

    private let completer = MKLocalSearchCompleter()
    private var pendingContinuation: CheckedContinuation<[PlacePrediction], Never>?
    private var timeoutTask: Task<Void, Never>?

    public override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.pointOfInterest, .address]
    }

    public func search(query: String, bias: CLLocationCoordinate2D? = nil) async -> [PlacePrediction] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        // Cancel previous continuation safely
        if let prev = pendingContinuation {
            pendingContinuation = nil
            prev.resume(returning: [])
        }
        timeoutTask?.cancel()

        if let b = bias {
            completer.region = MKCoordinateRegion(center: b, latitudinalMeters: 100_000, longitudinalMeters: 100_000)
        } else {
            completer.region = MKCoordinateRegion(MKMapRect.world)
        }

        return await withCheckedContinuation { continuation in
            self.pendingContinuation = continuation
            self.completer.queryFragment = trimmed

            self.timeoutTask = Task {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                if !Task.isCancelled, let pending = self.pendingContinuation {
                    self.pendingContinuation = nil
                    pending.resume(returning: [])
                }
            }
        }
    }

    public func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        timeoutTask?.cancel()
        guard let cont = pendingContinuation else { return }
        pendingContinuation = nil

        let preds = completer.results.prefix(8).map { comp in
            let title = comp.title
            let subtitle = comp.subtitle
            return PlacePrediction(
                placeId: "mkcomp-\(title)|\(subtitle)",
                primaryText: title,
                secondaryText: subtitle,
                fullText: subtitle.isEmpty ? title : "\(title), \(subtitle)"
            )
        }
        cont.resume(returning: Array(preds))
    }

    public func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        timeoutTask?.cancel()
        guard let cont = pendingContinuation else { return }
        pendingContinuation = nil
        cont.resume(returning: [])
    }
}

// MARK: - Google Maps & Navigation Service

public class GoogleMapsService {
    public static let shared = GoogleMapsService()

    private var routeCache: [RouteCacheKey: (duration: Int, miles: Double, timestamp: Date)] = [:]
    private struct AppleRouteCacheKey: Hashable {
        let route: RouteCacheKey
        let arrivalBucket: Int
    }
    private var appleRouteCache: [AppleRouteCacheKey: (duration: Int, miles: Double, timestamp: Date)] = [:]
    private let cacheTTL: TimeInterval = 15 * 60 // 15 minutes

    // Known seed places for intelligent fallback when offline or no API key
    private let seedPlaces: [(name: String, address: String, lat: Double, lng: Double)] = [
        ("Oak Ridge Elementary", "2140 Schoolhouse Road, Ann Arbor, MI", 42.2780, -83.7400),
        ("Lakeside Sports Complex", "803 Lakeview Drive, Ann Arbor, MI", 42.2650, -83.7150),
        ("Community Center", "1440 Maple Avenue, Ann Arbor, MI", 42.2850, -83.7380),
        ("Pediatric Clinic", "590 Health Parkway, Ann Arbor, MI", 42.2920, -83.7210),
        ("Downtown Square", "1 Market Plaza, Ann Arbor, MI", 42.2810, -83.7480),
        ("Kroger Pickup", "420 Grocery Way, Ann Arbor, MI", 42.2630, -83.7390),
        ("North Athletic Field", "880 Northfield Road, Ann Arbor, MI", 42.2950, -83.7320),
        ("Product Office", "300 Innovation Drive, Ann Arbor, MI", 42.2980, -83.7120),
        ("Grandma's House", "42 Elm Court, Ypsilanti, MI", 42.2410, -83.6120),
        ("Westside Aquatic Center", "770 West Stadium Boulevard, Ann Arbor, MI", 42.2700, -83.7650),
        ("Ann Arbor District Library", "343 South 5th Avenue, Ann Arbor, MI", 42.2785, -83.7450),
        ("Huron High School", "2727 Fuller Road, Ann Arbor, MI", 42.2880, -83.7020),
        ("Pioneer High School", "601 West Stadium Boulevard, Ann Arbor, MI", 42.2610, -83.7530),
        ("Skyline High School", "2552 North Maple Road, Ann Arbor, MI", 42.3120, -83.7740),
        ("Gallup Park", "3000 Fuller Road, Ann Arbor, MI", 42.2740, -83.6980),
        ("Ann Arbor YMCA", "400 West Washington Street, Ann Arbor, MI", 42.2805, -83.7530),
        ("Trader Joe's", "2398 East Stadium Boulevard, Ann Arbor, MI", 42.2590, -83.7120),
        ("Whole Foods Market", "990 West Eisenhower Parkway, Ann Arbor, MI", 42.2450, -83.7580),
        ("Target", "3749 Carpenter Road, Ypsilanti, MI", 42.2150, -83.6820),
        ("Starbucks - Main St", "300 South Main Street, Ann Arbor, MI", 42.2801, -83.7485),
        ("Starbucks - Stadium", "2220 West Stadium Boulevard, Ann Arbor, MI", 42.2620, -83.7690),
        ("CVS Pharmacy", "209 South State Street, Ann Arbor, MI", 42.2790, -83.7405),
        ("Walgreens", "317 South State Street, Ann Arbor, MI", 42.2780, -83.7408)
    ]

    public init() {}

    // MARK: - Places Autocomplete

    public func autocompletePlaces(
        query: String,
        apiKey: String? = nil,
        locationBias: CLLocationCoordinate2D? = nil,
        savedLocations: [LocationItem] = []
    ) async -> [PlacePrediction] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var results: [PlacePrediction] = []

        // 1. Saved household locations matching query (zero network latency)
        let matchedSaved = savedLocations.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed) || $0.address.localizedCaseInsensitiveContains(trimmed)
        }.map { loc in
            PlacePrediction(
                placeId: "saved-\(loc.name)",
                primaryText: loc.name,
                secondaryText: loc.address,
                fullText: "\(loc.name), \(loc.address)",
                latitude: loc.latitude,
                longitude: loc.longitude
            )
        }
        results.append(contentsOf: matchedSaved)

        // Detect if query contains numbers (indicating a specific street address like 25622 Coach Ln)
        let hasDigits = trimmed.contains(where: { $0.isNumber })
        let effectiveBias = hasDigits ? nil : locationBias

        // 2. Google Places Autocomplete API if key provided
        if let key = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
            if let googleResults = await fetchGooglePlacesAutocomplete(query: trimmed, apiKey: key, bias: effectiveBias), !googleResults.isEmpty {
                results.append(contentsOf: googleResults)
                return deduplicate(results)
            }
        }

        // 3. Apple MapKit LocalSearch Completer (instant search-as-you-type)
        let mkCompleterResults = await MapKitCompleterService.shared.search(query: trimmed, bias: effectiveBias)
        if !mkCompleterResults.isEmpty {
            results.append(contentsOf: mkCompleterResults)
            return deduplicate(results)
        }

        // 4. Apple MapKit Direct Search
        let mkDirectResults = await searchMapKitDirect(query: trimmed, bias: effectiveBias)
        if !mkDirectResults.isEmpty {
            results.append(contentsOf: mkDirectResults)
            return deduplicate(results)
        }

        // 5. Fallback: Seed venues (popular family destinations, schools, and businesses)
        let matchedSeeds = seedPlaces.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed) || $0.address.localizedCaseInsensitiveContains(trimmed)
        }.map {
            PlacePrediction(
                placeId: "seed-\($0.name.lowercased().replacingOccurrences(of: " ", with: "-"))",
                primaryText: $0.name,
                secondaryText: $0.address,
                fullText: "\($0.name), \($0.address)",
                latitude: $0.lat,
                longitude: $0.lng
            )
        }
        results.append(contentsOf: matchedSeeds)

        return deduplicate(results)
    }

    private func deduplicate(_ predictions: [PlacePrediction]) -> [PlacePrediction] {
        var seenNames = Set<String>()
        var unique: [PlacePrediction] = []
        for p in predictions {
            let key = p.primaryText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !seenNames.contains(key) {
                seenNames.insert(key)
                unique.append(p)
            }
        }
        return unique
    }

    private func fetchGooglePlacesAutocomplete(
        query: String,
        apiKey: String,
        bias: CLLocationCoordinate2D?
    ) async -> [PlacePrediction]? {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }

        // Omit types to permit both establishments (businesses, schools) and geocoded street addresses
        var urlString = "https://maps.googleapis.com/maps/api/place/autocomplete/json?input=\(encoded)&key=\(apiKey)"
        if let b = bias {
            urlString += "&location=\(b.latitude),\(b.longitude)&radius=50000"
        }

        guard let url = URL(string: urlString) else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200 else { return nil }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let status = json["status"] as? String,
                  status == "OK" || status == "ZERO_RESULTS",
                  let predictions = json["predictions"] as? [[String: Any]] else {
                return nil
            }

            return predictions.compactMap { dict -> PlacePrediction? in
                guard let placeId = dict["place_id"] as? String,
                      let desc = dict["description"] as? String else { return nil }

                let formatting = dict["structured_formatting"] as? [String: Any]
                let primary = (formatting?["main_text"] as? String) ?? desc
                let secondary = (formatting?["secondary_text"] as? String) ?? ""

                return PlacePrediction(
                    placeId: placeId,
                    primaryText: primary,
                    secondaryText: secondary,
                    fullText: desc
                )
            }
        } catch {
            return nil
        }
    }

    private func searchMapKitDirect(
        query: String,
        bias: CLLocationCoordinate2D?
    ) async -> [PlacePrediction] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = [.pointOfInterest, .address]
        if let b = bias {
            request.region = MKCoordinateRegion(center: b, latitudinalMeters: 100_000, longitudinalMeters: 100_000)
        }

        let search = MKLocalSearch(request: request)
        do {
            let response = try await search.start()
            let list = response.mapItems.prefix(8).map { item in
                let name = item.name ?? query
                let address = item.placemark.title ?? ""
                let cleanAddr = address.replacingOccurrences(of: name + ", ", with: "")
                return PlacePrediction(
                    placeId: "mk-\(item.placemark.coordinate.latitude),\(item.placemark.coordinate.longitude)|\(name)|\(cleanAddr.isEmpty ? address : cleanAddr)",
                    primaryText: name,
                    secondaryText: cleanAddr.isEmpty ? address : cleanAddr,
                    fullText: address.isEmpty ? name : address,
                    latitude: item.placemark.coordinate.latitude,
                    longitude: item.placemark.coordinate.longitude
                )
            }
            if !list.isEmpty {
                return Array(list)
            }
        } catch {
            // Regional search failed or timed out, attempt nationwide fallback
        }

        // If regional search returned empty and bias was set, retry nationwide without region constraint
        if bias != nil {
            let fallbackReq = MKLocalSearch.Request()
            fallbackReq.naturalLanguageQuery = query
            fallbackReq.resultTypes = [.pointOfInterest, .address]
            let fallbackSearch = MKLocalSearch(request: fallbackReq)
            if let fallbackRes = try? await fallbackSearch.start() {
                return fallbackRes.mapItems.prefix(8).map { item in
                    let name = item.name ?? query
                    let address = item.placemark.title ?? ""
                    let cleanAddr = address.replacingOccurrences(of: name + ", ", with: "")
                    return PlacePrediction(
                        placeId: "mk-\(item.placemark.coordinate.latitude),\(item.placemark.coordinate.longitude)|\(name)|\(cleanAddr.isEmpty ? address : cleanAddr)",
                        primaryText: name,
                        secondaryText: cleanAddr.isEmpty ? address : cleanAddr,
                        fullText: address.isEmpty ? name : address,
                        latitude: item.placemark.coordinate.latitude,
                        longitude: item.placemark.coordinate.longitude
                    )
                }
            }
        }

        return []
    }

    // MARK: - Place Details

    public func fetchPlaceDetails(
        placeId: String,
        apiKey: String? = nil,
        fallbackName: String = "Selected Place",
        fallbackAddress: String = ""
    ) async throws -> PlaceDetail {
        // 1. Saved household place
        if placeId.starts(with: "saved-") {
            let name = placeId.replacingOccurrences(of: "saved-", with: "")
            return PlaceDetail(
                name: fallbackName.isEmpty ? name : fallbackName,
                formattedAddress: fallbackAddress.isEmpty ? name : fallbackAddress,
                latitude: LocationService.defaultCoordinate.latitude,
                longitude: LocationService.defaultCoordinate.longitude,
                placeId: placeId
            )
        }

        // 2. Check if it's a seed place
        if placeId.starts(with: "seed-") {
            let clean = placeId.replacingOccurrences(of: "seed-", with: "")
            if let match = seedPlaces.first(where: { $0.name.lowercased().replacingOccurrences(of: " ", with: "-") == clean }) {
                return PlaceDetail(
                    name: match.name,
                    formattedAddress: match.address,
                    latitude: match.lat,
                    longitude: match.lng,
                    placeId: placeId
                )
            }
        }

        // 3. Apple MapKit Completer place ("mkcomp-Title|Subtitle")
        if placeId.starts(with: "mkcomp-") {
            let clean = placeId.replacingOccurrences(of: "mkcomp-", with: "")
            let parts = clean.split(separator: "|", maxSplits: 1)
            let title = parts.count > 0 ? String(parts[0]) : fallbackName
            let address = parts.count > 1 ? String(parts[1]) : fallbackAddress

            // Resolve exact coordinates via MKLocalSearch
            let searchQuery = address.isEmpty ? title : "\(title), \(address)"
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = searchQuery
            let search = MKLocalSearch(request: request)
            if let response = try? await search.start(), let item = response.mapItems.first {
                let resolvedAddr = item.placemark.title ?? address
                return PlaceDetail(
                    name: title,
                    formattedAddress: resolvedAddr.isEmpty ? address : resolvedAddr,
                    latitude: item.placemark.coordinate.latitude,
                    longitude: item.placemark.coordinate.longitude,
                    placeId: placeId
                )
            }

            return PlaceDetail(
                name: title,
                formattedAddress: address.isEmpty ? title : address,
                latitude: LocationService.defaultCoordinate.latitude,
                longitude: LocationService.defaultCoordinate.longitude,
                placeId: placeId
            )
        }

        // 4. Check if it's an MK coordinate place ("mk-lat,lng|name|address")
        if placeId.starts(with: "mk-") {
            let raw = placeId.replacingOccurrences(of: "mk-", with: "")
            let pipeParts = raw.split(separator: "|", maxSplits: 2)
            let coordsPart = String(pipeParts[0])
            let coords = coordsPart.split(separator: ",")
            let name = pipeParts.count > 1 ? String(pipeParts[1]) : fallbackName
            let address = pipeParts.count > 2 ? String(pipeParts[2]) : fallbackAddress

            if coords.count == 2, let lat = Double(coords[0]), let lng = Double(coords[1]) {
                return PlaceDetail(
                    name: name,
                    formattedAddress: address.isEmpty ? "\(lat), \(lng)" : address,
                    latitude: lat,
                    longitude: lng,
                    placeId: placeId
                )
            }
        }

        // 5. Fetch from Google Places Details API if key provided
        if let key = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
            let urlString = "https://maps.googleapis.com/maps/api/place/details/json?place_id=\(placeId)&fields=name,formatted_address,geometry&key=\(key)"
            if let url = URL(string: urlString) {
                let (data, response) = try await URLSession.shared.data(from: url)
                if let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200,
                   let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let result = json["result"] as? [String: Any] {
                    let name = (result["name"] as? String) ?? fallbackName
                    let address = (result["formatted_address"] as? String) ?? (fallbackAddress.isEmpty ? name : fallbackAddress)
                    let geom = result["geometry"] as? [String: Any]
                    let loc = geom?["location"] as? [String: Any]
                    let lat = (loc?["lat"] as? Double) ?? LocationService.defaultCoordinate.latitude
                    let lng = (loc?["lng"] as? Double) ?? LocationService.defaultCoordinate.longitude

                    return PlaceDetail(
                        name: name,
                        formattedAddress: address,
                        latitude: lat,
                        longitude: lng,
                        placeId: placeId
                    )
                }
            }
        }

        // 6. Resilient Fallback using provided name and address
        return PlaceDetail(
            name: fallbackName,
            formattedAddress: fallbackAddress.isEmpty ? fallbackName : fallbackAddress,
            latitude: LocationService.defaultCoordinate.latitude,
            longitude: LocationService.defaultCoordinate.longitude,
            placeId: placeId
        )
    }

    // MARK: - Real-time Drive Time Calculation

    public func calculateDriveTime(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D,
        apiKey: String? = nil
    ) async -> (durationMinutes: Int, distanceMiles: Double)? {
        let key = RouteCacheKey(from: from, to: to)

        // Check cache
        if let cached = routeCache[key], Date().timeIntervalSince(cached.timestamp) < cacheTTL {
            return (cached.duration, cached.miles)
        }

        // 1. Google Distance Matrix API if key provided
        if let keyStr = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines), !keyStr.isEmpty {
            if let result = await fetchGoogleDistanceMatrix(from: from, to: to, apiKey: keyStr) {
                routeCache[key] = (result.durationMinutes, result.distanceMiles, Date())
                return result
            }
        }

        // 2. Apple MapKit Directions API fallback (free, real-time traffic)
        if let result = await fetchMapKitDriveTime(from: from, to: to) {
            routeCache[key] = (result.durationMinutes, result.distanceMiles, Date())
            return result
        }

        // 3. Fallback: Haversine distance with 30 mph city speed assumption
        let miles = LocationService.distanceInMiles(from: from, to: to)
        let mins = max(2, Int(ceil(miles / 30.0 * 60.0)) + 2) // +2 min traffic slack
        let result = (durationMinutes: mins, distanceMiles: (miles * 10).rounded() / 10)
        routeCache[key] = (result.durationMinutes, result.distanceMiles, Date())
        return result
    }

    /// Apple Maps route estimate from the device's current GPS position. The
    /// appointment time is supplied as the desired arrival so MapKit can account
    /// for the traffic expected when this trip will actually happen.
    public func calculateAppleDriveTime(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D,
        arrivingAt arrivalDate: Date
    ) async -> (durationMinutes: Int, distanceMiles: Double)? {
        let route = RouteCacheKey(from: from, to: to)
        let key = AppleRouteCacheKey(
            route: route,
            arrivalBucket: Int(arrivalDate.timeIntervalSince1970 / (15 * 60))
        )
        if let cached = appleRouteCache[key], Date().timeIntervalSince(cached.timestamp) < cacheTTL {
            return (cached.duration, cached.miles)
        }

        guard let result = await fetchMapKitDriveTime(from: from, to: to, arrivingAt: arrivalDate) else {
            return nil
        }
        appleRouteCache[key] = (result.durationMinutes, result.distanceMiles, Date())
        return result
    }

    private func fetchGoogleDistanceMatrix(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D,
        apiKey: String
    ) async -> (durationMinutes: Int, distanceMiles: Double)? {
        let urlString = "https://maps.googleapis.com/maps/api/distancematrix/json?origins=\(from.latitude),\(from.longitude)&destinations=\(to.latitude),\(to.longitude)&departure_time=now&traffic_model=best_guess&key=\(apiKey)"
        guard let url = URL(string: urlString) else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let status = json["status"] as? String, status == "OK",
                  let rows = json["rows"] as? [[String: Any]], let firstRow = rows.first,
                  let elements = firstRow["elements"] as? [[String: Any]], let elem = elements.first,
                  let elemStatus = elem["status"] as? String, elemStatus == "OK" else {
                return nil
            }

            // Prefer duration_in_traffic if available
            let durationDict = (elem["duration_in_traffic"] as? [String: Any]) ?? (elem["duration"] as? [String: Any])
            let seconds = (durationDict?["value"] as? Double) ?? 0
            let durationMins = max(1, Int(ceil(seconds / 60.0)))

            let distanceDict = elem["distance"] as? [String: Any]
            let meters = (distanceDict?["value"] as? Double) ?? 0
            let miles = (meters / 1609.344 * 10).rounded() / 10

            return (durationMinutes: durationMins, distanceMiles: miles)
        } catch {
            return nil
        }
    }

    private func fetchMapKitDriveTime(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D,
        arrivingAt arrivalDate: Date? = nil
    ) async -> (durationMinutes: Int, distanceMiles: Double)? {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: from))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: to))
        request.transportType = .automobile
        if let arrivalDate {
            request.arrivalDate = arrivalDate
        } else {
            request.departureDate = Date()
        }

        let directions = MKDirections(request: request)
        do {
            let response = try await directions.calculate()
            guard let route = response.routes.first else { return nil }
            let mins = max(1, Int(ceil(route.expectedTravelTime / 60.0)))
            let miles = (route.distance / 1609.344 * 10).rounded() / 10
            return (durationMinutes: mins, distanceMiles: miles)
        } catch {
            return nil
        }
    }
}

import Foundation
import CoreLocation
import Combine

public class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    public static let shared = LocationService()

    @Published public var currentLocation: CLLocation? = nil
    @Published public var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published public var isUpdating: Bool = false

    private let manager = CLLocationManager()

    // Default sample coordinate (Ann Arbor / Detroit Metro, matching seed data)
    public static let defaultCoordinate = CLLocationCoordinate2D(latitude: 42.2808, longitude: -83.7430)

    public override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 50 // meters
        self.authorizationStatus = manager.authorizationStatus
    }

    public func requestWhenInUsePermission() {
        #if os(iOS)
        manager.requestWhenInUseAuthorization()
        #else
        manager.requestAlwaysAuthorization()
        #endif
    }

    public func startUpdating() {
        guard !isUpdating else { return }
        let status = manager.authorizationStatus
        #if os(iOS)
        let isAuth = (status == .authorizedWhenInUse || status == .authorizedAlways)
        #else
        let isAuth = (status == .authorizedAlways || status == .authorized)
        #endif
        if isAuth {
            manager.startUpdatingLocation()
            isUpdating = true
        } else if status == .notDetermined {
            #if os(iOS)
            manager.requestWhenInUseAuthorization()
            #else
            manager.requestAlwaysAuthorization()
            #endif
            manager.startUpdatingLocation()
            isUpdating = true
        }
    }

    public func stopUpdating() {
        guard isUpdating else { return }
        manager.stopUpdatingLocation()
        isUpdating = false
    }

    /// Home coordinate fallback supplied by the household
    public var homeCoordinateFallback: CLLocationCoordinate2D? = nil

    /// Manual override for simulated device testing
    public var simulatedLocationOverride: CLLocationCoordinate2D? = nil

    /// Detects whether the current device is running on the simulator and reporting Apple's default SF GPS
    public var isSimulatorDefaultSF: Bool {
        #if targetEnvironment(simulator)
        if let loc = currentLocation {
            return abs(loc.coordinate.latitude - 37.785834) < 0.25 && abs(loc.coordinate.longitude - (-122.406417)) < 0.25
        }
        return false
        #else
        return false
        #endif
    }

    public var effectiveCoordinate: CLLocationCoordinate2D {
        if let override = simulatedLocationOverride {
            return override
        }
        if let loc = currentLocation {
            #if targetEnvironment(simulator)
            // If running on iOS Simulator and GPS is Apple's default SF simulated location,
            // automatically prefer the household's actual home coordinates so weather and drive times match home.
            if isSimulatorDefaultSF, let home = homeCoordinateFallback {
                return home
            }
            #endif
            return loc.coordinate
        }
        return homeCoordinateFallback ?? Self.defaultCoordinate
    }

    public var isAuthorized: Bool {
        #if os(iOS)
        return authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
        #else
        return authorizationStatus == .authorizedAlways || authorizationStatus == .authorized
        #endif
    }

    // MARK: - CLLocationManagerDelegate

    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async {
            self.authorizationStatus = manager.authorizationStatus
            if self.isAuthorized && self.isUpdating {
                manager.startUpdatingLocation()
            }
        }
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        DispatchQueue.main.async {
            self.currentLocation = latest
        }
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Location failed gracefully; existing location or fallback coordinate will be used
    }

    /// True only when `effectiveCoordinate` is an actual device fix. Mirrors the
    /// branches below, so callers can avoid claiming "live GPS" over a fallback.
    public var isUsingDeviceFix: Bool {
        if simulatedLocationOverride != nil { return false }
        guard currentLocation != nil else { return false }
        #if targetEnvironment(simulator)
        if isSimulatorDefaultSF && homeCoordinateFallback != nil { return false }
        #endif
        return true
    }

    // MARK: - Geocoding

    /// Turns a saved place's street address into coordinates. Uses Apple's
    /// geocoder, so it needs no API key — which matters because a household
    /// without one would otherwise have places that can never be located, and
    /// every drive time would silently fall back to a sample coordinate.
    public func geocode(address: String) async -> CLLocationCoordinate2D? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        do {
            let places = try await CLGeocoder().geocodeAddressString(trimmed)
            return places.first?.location?.coordinate
        } catch {
            return nil
        }
    }

    // MARK: - Distance Calculations

    public static func distanceInMeters(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> CLLocationDistance {
        let locA = CLLocation(latitude: from.latitude, longitude: from.longitude)
        let locB = CLLocation(latitude: to.latitude, longitude: to.longitude)
        return locA.distance(from: locB)
    }

    public static func distanceInMiles(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        return distanceInMeters(from: from, to: to) / 1609.344
    }
}

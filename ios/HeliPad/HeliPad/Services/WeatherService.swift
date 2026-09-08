import Foundation
import CoreLocation

public struct LiveWeather: Hashable, Sendable {
    public var temperature: Int
    public var tempLow: Int?
    public var tempHigh: Int?
    public var condition: String
    public var icon: String // "sun", "partly", "cloud", "rain", "storm"
    public var label: String // "Sunny · 58°–78°"

    public init(
        temperature: Int,
        tempLow: Int? = nil,
        tempHigh: Int? = nil,
        condition: String,
        icon: String,
        label: String
    ) {
        self.temperature = temperature
        self.tempLow = tempLow
        self.tempHigh = tempHigh
        self.condition = condition
        self.icon = icon
        self.label = label
    }

    /// Formatted daily temperature range display (e.g., "58°–78°"), falling back to single temp if range unavailable
    public var tempRangeDisplay: String {
        if let low = tempLow, let high = tempHigh {
            return "\(low)°–\(high)°"
        }
        return "\(temperature)°"
    }
}

public class WeatherService {
    public static let shared = WeatherService()

    private var cachedWeather: (weather: LiveWeather, timestamp: Date)? = nil
    private let cacheTTL: TimeInterval = 60 * 60 // 1 hour cache to reduce network usage & save battery

    private struct OpenMeteoResponse: Codable {
        struct Current: Codable {
            let temperature_2m: Double
            let weather_code: Int
            let is_day: Int
        }
        struct Daily: Codable {
            let temperature_2m_max: [Double]?
            let temperature_2m_min: [Double]?
        }
        let current: Current
        let daily: Daily?
    }

    public init() {}

    public func fetchWeather(
        coordinate: CLLocationCoordinate2D? = nil,
        forceRefresh: Bool = false
    ) async -> LiveWeather {
        // Return valid cache if available and not expired
        if !forceRefresh, let cached = cachedWeather, Date().timeIntervalSince(cached.timestamp) < cacheTTL {
            return cached.weather
        }

        let coord = coordinate ?? LocationService.shared.effectiveCoordinate
        let urlString = "https://api.open-meteo.com/v1/forecast?latitude=\(coord.latitude)&longitude=\(coord.longitude)&current=temperature_2m,weather_code,is_day&daily=temperature_2m_max,temperature_2m_min&temperature_unit=fahrenheit&timezone=auto"

        guard let url = URL(string: urlString) else {
            return fallbackWeather()
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200 else {
                return fallbackWeather()
            }

            let decoded = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
            let temp = Int(decoded.current.temperature_2m.rounded())
            let high = decoded.daily?.temperature_2m_max?.first.map { Int($0.rounded()) }
            let low = decoded.daily?.temperature_2m_min?.first.map { Int($0.rounded()) }
            let (condition, icon) = Self.mapWMOCode(decoded.current.weather_code, isDay: decoded.current.is_day == 1)

            let label: String
            if let low = low, let high = high {
                label = "\(condition) · \(low)°–\(high)°"
            } else {
                label = "\(condition) · \(temp)°"
            }

            let live = LiveWeather(
                temperature: temp,
                tempLow: low,
                tempHigh: high,
                condition: condition,
                icon: icon,
                label: label
            )
            cachedWeather = (live, Date())
            return live
        } catch {
            return fallbackWeather()
        }
    }

    public static func mapWMOCode(_ code: Int, isDay: Bool = true) -> (condition: String, icon: String) {
        switch code {
        case 0:
            return (isDay ? "Sunny" : "Clear", isDay ? "sun" : "sun")
        case 1, 2:
            return ("Partly cloudy", "partly")
        case 3:
            return ("Overcast", "cloud")
        case 45, 48:
            return ("Foggy", "cloud")
        case 51, 53, 55, 56, 57:
            return ("Light drizzle", "rain")
        case 61, 63:
            return ("Rain", "rain")
        case 65, 66, 67:
            return ("Heavy rain", "rain")
        case 71, 73, 75, 77:
            return ("Snow", "cloud")
        case 80, 81, 82:
            return ("Rain showers", "rain")
        case 85, 86:
            return ("Snow showers", "cloud")
        case 95:
            return ("Thunderstorms", "storm")
        case 96, 99:
            return ("Severe storms", "storm")
        default:
            return ("Clear", "sun")
        }
    }

    private func fallbackWeather() -> LiveWeather {
        return LiveWeather(
            temperature: 78,
            tempLow: 58,
            tempHigh: 78,
            condition: "Sunny",
            icon: "sun",
            label: "Sunny · 58°–78°"
        )
    }
}

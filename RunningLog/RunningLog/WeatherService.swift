import CoreLocation
import Foundation
import os

// MARK: - WorkoutWeather

struct WorkoutWeather: Codable {
    let temperatureFahrenheit: Double
    let condition: WeatherCondition
    let humidity: Int?
    let windSpeedMph: Double?
    let dewPointFahrenheit: Double?

    var formattedTemperature: String {
        "\(Int(temperatureFahrenheit))°F"
    }

    var formattedDewPoint: String? {
        guard let dp = dewPointFahrenheit else { return nil }
        return "\(Int(dp))°F"
    }

    var icon: String {
        condition.icon
    }

    var description: String {
        condition.description
    }
}

// MARK: - WeatherCondition

enum WeatherCondition: String, Codable {
    case clear
    case partlyCloudy = "partly_cloudy"
    case cloudy
    case fog
    case drizzle
    case rain
    case snow
    case thunderstorm
    case unknown

    var icon: String {
        switch self {
        case .clear: "sun.max.fill"
        case .partlyCloudy: "cloud.sun.fill"
        case .cloudy: "cloud.fill"
        case .fog: "cloud.fog.fill"
        case .drizzle: "cloud.drizzle.fill"
        case .rain: "cloud.rain.fill"
        case .snow: "cloud.snow.fill"
        case .thunderstorm: "cloud.bolt.rain.fill"
        case .unknown: "questionmark.circle"
        }
    }

    var description: String {
        switch self {
        case .clear: "Clear"
        case .partlyCloudy: "Partly Cloudy"
        case .cloudy: "Cloudy"
        case .fog: "Foggy"
        case .drizzle: "Drizzle"
        case .rain: "Rain"
        case .snow: "Snow"
        case .thunderstorm: "Thunderstorm"
        case .unknown: "Unknown"
        }
    }

    /// Maps WMO weather codes to our conditions
    /// https://open-meteo.com/en/docs
    static func fromWMOCode(_ code: Int) -> WeatherCondition {
        switch code {
        case 0: .clear
        case 1,
             2: .partlyCloudy
        case 3: .cloudy
        case 45,
             48: .fog
        case 51,
             53,
             55,
             56,
             57: .drizzle
        case 61,
             63,
             65,
             66,
             67,
             80,
             81,
             82: .rain
        case 71,
             73,
             75,
             77,
             85,
             86: .snow
        case 95,
             96,
             99: .thunderstorm
        default: .unknown
        }
    }
}

// MARK: - OpenMeteoHistoricalResponse

struct OpenMeteoHistoricalResponse: Codable {
    let hourly: HourlyData?

    struct HourlyData: Codable {
        let time: [String]
        let temperature_2m: [Double?]
        let weather_code: [Int?]
        let relative_humidity_2m: [Int?]?
        let wind_speed_10m: [Double?]?
        let dew_point_2m: [Double?]?
    }
}

// MARK: - OpenMeteoForecastResponse

struct OpenMeteoForecastResponse: Codable {
    let current: CurrentData?
    let hourly: HourlyData?

    struct CurrentData: Codable {
        let temperature_2m: Double
        let weather_code: Int
        let relative_humidity_2m: Int?
        let wind_speed_10m: Double?
        let dew_point_2m: Double?
    }

    struct HourlyData: Codable {
        let time: [String]
        let temperature_2m: [Double?]
        let weather_code: [Int?]
        let relative_humidity_2m: [Int?]?
        let wind_speed_10m: [Double?]?
        let dew_point_2m: [Double?]?
    }
}

// MARK: - WeatherService

class WeatherService {
    static let shared = WeatherService()

    private let session: URLSession
    private var cache: [String: WorkoutWeather] = [:]

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        self.session = URLSession(configuration: config)
    }

    /// Fetches weather for a workout at a specific time and location
    func fetchWeather(for date: Date, location: CLLocation) async -> WorkoutWeather? {
        // Check cache first
        let lat = Int(location.coordinate.latitude * 100)
        let lon = Int(location.coordinate.longitude * 100)
        let hour = Int(date.timeIntervalSince1970 / 3600)
        let cacheKey = "\(lat)_\(lon)_\(hour)"
        if let cached = cache[cacheKey] {
            return cached
        }

        let daysSinceDate = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0

        // Use forecast API for recent data (within 5 days), archive for older
        if daysSinceDate <= 5 {
            return await fetchRecentWeather(for: date, location: location, cacheKey: cacheKey)
        } else {
            return await fetchHistoricalWeather(for: date, location: location, cacheKey: cacheKey)
        }
    }

    /// Fetches weather using the forecast API (for recent dates)
    private func fetchRecentWeather(for date: Date, location: CLLocation, cacheKey: String) async -> WorkoutWeather? {
        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude

        let urlString = "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)&current=temperature_2m,weather_code,relative_humidity_2m,wind_speed_10m,dew_point_2m&temperature_unit=fahrenheit&windspeed_unit=mph&timezone=auto"

        guard let url = URL(string: urlString) else { return nil }

        do {
            let (data, _) = try await session.data(from: url)

            // Debug: Log raw JSON response
            if let jsonString = String(data: data, encoding: .utf8) {
                Log.weather.debug("Weather API response: \(jsonString.prefix(500))")
            }

            let response = try JSONDecoder().decode(OpenMeteoForecastResponse.self, from: data)

            guard let current = response.current else {
                Log.weather.warning("No 'current' data in response")
                return nil
            }

            let dewPt = current.dew_point_2m ?? -999
            let humidity = current.relative_humidity_2m ?? -1
            Log.weather.info("Weather - Temp: \(current.temperature_2m)°F, DewPoint: \(dewPt)°F, Humidity: \(humidity)%")

            let weather = WorkoutWeather(
                temperatureFahrenheit: current.temperature_2m,
                condition: WeatherCondition.fromWMOCode(current.weather_code),
                humidity: current.relative_humidity_2m,
                windSpeedMph: current.wind_speed_10m,
                dewPointFahrenheit: current.dew_point_2m
            )

            cache[cacheKey] = weather
            return weather
        } catch {
            Log.weather.error("Weather fetch error: \(error)")
            return nil
        }
    }

    /// Fetches weather using the archive API (for historical dates)
    private func fetchHistoricalWeather(for date: Date, location: CLLocation, cacheKey: String) async -> WorkoutWeather? {
        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: date)

        let urlString = "https://archive-api.open-meteo.com/v1/archive?latitude=\(lat)&longitude=\(lon)&start_date=\(dateString)&end_date=\(dateString)&hourly=temperature_2m,weather_code,relative_humidity_2m,wind_speed_10m,dew_point_2m&temperature_unit=fahrenheit&windspeed_unit=mph&timezone=auto"

        guard let url = URL(string: urlString) else { return nil }

        do {
            let (data, _) = try await session.data(from: url)
            let response = try JSONDecoder().decode(OpenMeteoHistoricalResponse.self, from: data)

            guard let hourly = response.hourly else { return nil }

            // Find the hour closest to workout time
            let calendar = Calendar.current
            let hour = calendar.component(.hour, from: date)
            let index = min(hour, hourly.time.count - 1)

            guard index >= 0,
                  let temp = hourly.temperature_2m[safe: index] ?? hourly.temperature_2m.compactMap({ $0 }).first,
                  let code = hourly.weather_code[safe: index] ?? hourly.weather_code.compactMap({ $0 }).first
            else { return nil }

            let humidity = hourly.relative_humidity_2m?[safe: index].flatMap { $0 }
            let wind = hourly.wind_speed_10m?[safe: index].flatMap { $0 }
            let dewPoint = hourly.dew_point_2m?[safe: index].flatMap { $0 }

            let weather = WorkoutWeather(
                temperatureFahrenheit: temp,
                condition: WeatherCondition.fromWMOCode(code),
                humidity: humidity,
                windSpeedMph: wind,
                dewPointFahrenheit: dewPoint
            )

            cache[cacheKey] = weather
            return weather
        } catch {
            Log.weather.error("Historical weather fetch error: \(error)")
            return nil
        }
    }

    /// Fetches weather forecast for a future date/time
    func fetchForecast(for date: Date, location: CLLocation) async -> WorkoutWeather? {
        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: date)

        // Forecast API supports up to 16 days ahead
        let urlString = "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)&hourly=temperature_2m,weather_code,relative_humidity_2m,wind_speed_10m,dew_point_2m&start_date=\(dateString)&end_date=\(dateString)&temperature_unit=fahrenheit&windspeed_unit=mph&timezone=auto"

        guard let url = URL(string: urlString) else { return nil }

        do {
            let (data, _) = try await session.data(from: url)

            // Debug: Log raw JSON response
            if let jsonString = String(data: data, encoding: .utf8) {
                Log.weather.debug("Forecast API response: \(jsonString.prefix(500))")
            }

            let response = try JSONDecoder().decode(OpenMeteoForecastResponse.self, from: data)

            guard let hourly = response.hourly, !hourly.time.isEmpty else {
                Log.weather.error("Forecast: No hourly data in response")
                return nil
            }

            // Find the hour closest to requested time
            let calendar = Calendar.current
            let hour = calendar.component(.hour, from: date)
            let index = min(hour, hourly.time.count - 1)

            Log.weather.debug("Forecast: hour=\(hour), index=\(index), times=\(hourly.time.count)")

            guard index >= 0,
                  let temp = hourly.temperature_2m[safe: index] ?? hourly.temperature_2m.compactMap({ $0 }).first,
                  let code = hourly.weather_code[safe: index] ?? hourly.weather_code.compactMap({ $0 }).first
            else {
                Log.weather.error("Forecast: Could not get temp or weather code at index \(index)")
                return nil
            }

            let humidity = hourly.relative_humidity_2m?[safe: index].flatMap { $0 }
            let wind = hourly.wind_speed_10m?[safe: index].flatMap { $0 }
            let dewPoint = hourly.dew_point_2m?[safe: index].flatMap { $0 }

            Log.weather.info("Forecast: Temp=\(temp)°F, DewPoint=\(dewPoint ?? -999)°F, Humidity=\(humidity ?? -1)%")

            return WorkoutWeather(
                temperatureFahrenheit: temp,
                condition: WeatherCondition.fromWMOCode(code),
                humidity: humidity,
                windSpeedMph: wind,
                dewPointFahrenheit: dewPoint
            )
        } catch {
            Log.weather.error("Forecast fetch error: \(error)")
            return nil
        }
    }

    /// Fetches current weather at a location
    func fetchCurrentWeather(location: CLLocation) async -> WorkoutWeather? {
        await fetchRecentWeather(
            for: Date(),
            location: location,
            cacheKey: "current_\(Int(location.coordinate.latitude * 100))_\(Int(location.coordinate.longitude * 100))"
        )
    }
}

// MARK: - Safe Array Access

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard index >= 0, index < count else { return nil }
        return self[index]
    }
}

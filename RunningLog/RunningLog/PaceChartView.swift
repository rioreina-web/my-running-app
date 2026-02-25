import Combine
import CoreLocation
import os
import Supabase
import SwiftUI

// MARK: - PaceCalculator

enum PaceCalculator {
    /// Race distances in miles
    static let distances: [String: Double] = [
        "1500m": 0.932,
        "mile": 1.0,
        "3K": 1.864,
        "5K": 3.107,
        "10K": 6.214,
        "10mi": 10.0,
        "half": 13.109,
        "marathon": 26.219
    ]

    // MARK: - Performance Ratios (VDOT-based)

    // Baseline: 10K = 1.0
    // Formula: TargetTime = KnownTime * (TargetRatio / KnownRatio)
    // Or equivalently: Base10K = KnownTime / KnownRatio, then TargetTime = Base10K * TargetRatio
    static let performanceRatios: [String: Double] = [
        "1500m": 0.129167,
        "mile": 0.139583,
        "3K": 0.277083,
        "5K": 0.481250,
        "10K": 1.000000,
        "10mi": 1.661000, // Interpolated between 10K and half
        "half": 2.204167,
        "marathon": 4.615625
    ]

    /// Calculate all equivalent paces using ratio-based VDOT
    /// This approach uses fixed ratios relative to 10K to predict equivalent times
    static func calculateEquivalentPaces(
        fromDistance: String,
        totalSeconds: Int
    ) -> [String: Double] {
        let inputSeconds = Double(totalSeconds)

        // Get the ratio for the input distance
        guard let inputRatio = performanceRatios[fromDistance] else { return [:] }

        // Calculate the theoretical base 10K time
        // Base10K = KnownTime / KnownRatio
        let base10KSeconds = inputSeconds / inputRatio

        var paces: [String: Double] = [:]

        // Calculate predicted times and paces for all distances
        for (distanceName, distanceMiles) in distances {
            guard let targetRatio = performanceRatios[distanceName] else { continue }

            // PredictedTime = Base10K * TargetRatio
            let predictedSeconds = base10KSeconds * targetRatio
            paces[distanceName] = predictedSeconds / distanceMiles
        }

        return paces
    }

    /// Get equivalent race time for a distance given another race performance
    static func getEquivalentTime(
        fromDistance: String,
        fromSeconds: Int,
        toDistance: String
    ) -> Int {
        guard let fromRatio = performanceRatios[fromDistance],
              let toRatio = performanceRatios[toDistance] else { return 0 }

        // TargetTime = KnownTime * (TargetRatio / KnownRatio)
        let predictedSeconds = Double(fromSeconds) * (toRatio / fromRatio)
        return Int(predictedSeconds)
    }

    /// Calculate training paces from MP
    static func calculateTrainingPaces(mpPaceSeconds: Double) -> [String: Double] {
        [
            "Easy": mpPaceSeconds / 0.75, // 75% of MP effort = slower pace
            "Moderate Low": mpPaceSeconds / 0.75, // 75% effort
            "Moderate High": mpPaceSeconds / 0.85, // 85% effort
            "Steady Low": mpPaceSeconds / 0.85, // 85% effort
            "Steady High": mpPaceSeconds / 0.95 // 95% effort
        ]
    }

    /// Calculate 1-hour pace (LT/Threshold pace)
    /// Finds the pace at which you could race for exactly 1 hour (3600 seconds)
    /// by interpolating between 10K and Half Marathon performance
    static func calculateOneHourPace(
        fromDistance: String,
        totalSeconds: Int
    ) -> Double? {
        guard let inputRatio = performanceRatios[fromDistance],
              let ratio10K = performanceRatios["10K"],
              let ratioHalf = performanceRatios["half"] else { return nil }

        // Calculate base 10K time
        let base10KSeconds = Double(totalSeconds) / inputRatio

        // Get 10K and Half times
        let time10K = base10KSeconds * ratio10K // Time to run 10K (6.214 mi)
        let timeHalf = base10KSeconds * ratioHalf // Time to run Half (13.109 mi)

        // Target: exactly 1 hour = 3600 seconds
        let targetTime = 3600.0

        // Find what distance can be covered in exactly 3600 seconds
        // by interpolating between 10K and Half Marathon
        let distance10K = 6.214
        let distanceHalf = 13.109

        // Edge cases
        if time10K >= targetTime {
            // 10K takes >= 1 hour, use 10K pace
            return time10K / distance10K
        }
        if timeHalf <= targetTime {
            // Half takes <= 1 hour, use Half pace
            return timeHalf / distanceHalf
        }

        // Interpolate: fraction = (targetTime - time10K) / (timeHalf - time10K)
        let fraction = (targetTime - time10K) / (timeHalf - time10K)

        // Distance covered in 1 hour = 10K distance + fraction * (Half distance - 10K distance)
        let distanceInOneHour = distance10K + fraction * (distanceHalf - distance10K)

        // 1-hour pace = 3600 seconds / distance in miles
        return targetTime / distanceInOneHour
    }

    /// Format seconds per mile to MM:SS
    static func formatPace(_ seconds: Double) -> String {
        let totalSecs = Int(seconds.rounded())
        let mins = totalSecs / 60
        let secs = totalSecs % 60
        return String(format: "%d:%02d", mins, secs)
    }

    /// Format pace in km (converts seconds/mile to seconds/km)
    static func formatPaceKm(_ secondsPerMile: Double) -> String {
        let totalSecs = Int((secondsPerMile / 1.60934).rounded())
        let mins = totalSecs / 60
        let secs = totalSecs % 60
        return String(format: "%d:%02d", mins, secs)
    }

    /// Calculate splits for a given pace (400m, 1K, mile)
    static func calculateSplits(paceSecondsPerMile: Double) -> (fourHundred: Double, oneK: Double, mile: Double) {
        let secondsPerKm = paceSecondsPerMile / 1.60934
        let fourHundred = secondsPerKm * 0.4 // 400m = 0.4km
        let oneK = secondsPerKm
        let mile = paceSecondsPerMile
        return (fourHundred, oneK, mile)
    }

    /// Format split time (handles sub-minute times)
    static func formatSplit(_ seconds: Double) -> String {
        let totalSeconds = Int(seconds.rounded())
        let mins = totalSeconds / 60
        let secs = totalSeconds % 60
        if mins == 0 {
            return String(format: "0:%02d", secs)
        }
        return String(format: "%d:%02d", mins, secs)
    }

    /// Format total time to H:MM:SS or MM:SS
    static func formatTime(_ totalSeconds: Int) -> String {
        let hours = totalSeconds / 3600
        let mins = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, mins, secs)
        } else {
            return String(format: "%d:%02d", mins, secs)
        }
    }

    /// Parse time string to seconds
    /// Uses smart detection based on the first number:
    /// - If first part > 9 (like 45:00, 30:56), it's MM:SS format
    /// - If first part <= 9 (like 3:30, 1:40) and it's a long distance, it's H:MM format
    static func parseTime(_ timeString: String, forDistance distance: String? = nil) -> Int? {
        let parts = timeString.split(separator: ":").compactMap { Int($0) }

        switch parts.count {
        case 2:
            // Smart detection: if first part > 9, it's almost certainly minutes (MM:SS)
            // E.g., "45:00" = 45 min, "30:56" = 30:56
            // If first part <= 9, check if it's a long distance that expects H:MM
            // E.g., "3:30" for marathon = 3 hours 30 min
            let longDistances = ["10mi", "half", "marathon"]
            let isLongDistance = distance.map { longDistances.contains($0) } ?? false

            if parts[0] > 9 {
                // First part is large (10+), so this must be MM:SS
                // Examples: 45:00 = 45 min, 30:56 = 30:56, 75:00 = 75 min
                return parts[0] * 60 + parts[1]
            } else if isLongDistance {
                // First part is small (1-9) and it's a long distance, so H:MM
                // Examples: 3:30 marathon = 3h30m, 1:40 half = 1h40m
                return parts[0] * 3600 + parts[1] * 60
            } else {
                // First part is small (1-9) and short distance, so MM:SS
                // Examples: 5:30 mile = 5:30, 4:19 mile = 4:19
                return parts[0] * 60 + parts[1]
            }
        case 3: // H:MM:SS
            return parts[0] * 3600 + parts[1] * 60 + parts[2]
        default:
            return nil
        }
    }

    /// Validate if the time is reasonable for the distance
    /// Returns nil if valid, or an error message if unrealistic
    static func validateTime(_ seconds: Int, forDistance distance: String) -> String? {
        guard let distanceMiles = distances[distance] else { return nil }

        let paceSecondsPerMile = Double(seconds) / distanceMiles

        // World record paces (roughly):
        // - Marathon: ~4:38/mi (278 sec)
        // - Half: ~4:28/mi (268 sec)
        // - 10K: ~4:15/mi (255 sec)
        // - 5K: ~4:00/mi (240 sec)
        // - Mile: ~3:43/mi (223 sec)
        // - 1500m: ~3:26/mi (206 sec)

        // Minimum reasonable pace (slightly faster than world records)
        let minPace: Double = switch distance {
        case "marathon": 250 // ~4:10/mi
        case "half": 240 // ~4:00/mi
        case "10K",
             "10mi": 230 // ~3:50/mi
        case "5K",
             "3K": 210 // ~3:30/mi
        case "mile",
             "1500m": 180 // ~3:00/mi
        default: 180
        }

        if paceSecondsPerMile < minPace {
            return "Time seems too fast - check format (H:MM:SS for long races)"
        }

        // No "too slow" warning - let users enter whatever time they want
        return nil
    }

    // MARK: - Dew Point Adjustment (Emy's Calculator)

    /// Calculate heat-adjusted pace based on temperature and dew point
    /// Returns adjustment details including the adjusted pace in seconds per mile
    static func calculateDewPointAdjustment(
        paceSeconds: Double,
        temperatureF: Double,
        dewPointF: Double
    ) -> DewPointAdjustment {
        // 1. Calculate Dew Point Multiplier
        // Logic: 1.12 at 74DP. Assumes 1.0 baseline at 50DP.
        // Formula: 1 + (DewPoint - 50) * 0.005
        let dpMultiplier = 1.0 + max(0, (dewPointF - 50) * 0.005)

        // 2. Calculate Composite Score
        // Formula: Temp + (Dew Point * Multiplier)
        let compositeScore = temperatureF + (dewPointF * dpMultiplier)

        // 3. Calculate Adjustment Percentage
        // Logic: 0.071767 adjustment at 170.88 score. Assumes 0 adjustment at 100 score.
        // Slope: ~0.0010125 per point above 100.
        var adjustmentPct = 0.0
        if compositeScore > 100 {
            adjustmentPct = (compositeScore - 100) * 0.0010125
        }

        // 4. Calculate Adjusted Pace
        let adjustedSeconds = paceSeconds * (1 + adjustmentPct)

        return DewPointAdjustment(
            originalPaceSeconds: paceSeconds,
            adjustedPaceSeconds: adjustedSeconds,
            temperatureF: temperatureF,
            dewPointF: dewPointF,
            multiplier: dpMultiplier,
            compositeScore: compositeScore,
            adjustmentPercent: adjustmentPct
        )
    }

    /// Apply weather adjustment to all paces
    static func applyWeatherAdjustment(
        paces: [String: Double],
        temperatureF: Double,
        dewPointF: Double
    ) -> [String: Double] {
        var adjusted: [String: Double] = [:]
        for (key, pace) in paces {
            let adjustment = calculateDewPointAdjustment(
                paceSeconds: pace,
                temperatureF: temperatureF,
                dewPointF: dewPointF
            )
            adjusted[key] = adjustment.adjustedPaceSeconds
        }
        return adjusted
    }
}

// MARK: - DewPointAdjustment

struct DewPointAdjustment {
    let originalPaceSeconds: Double
    let adjustedPaceSeconds: Double
    let temperatureF: Double
    let dewPointF: Double
    let multiplier: Double
    let compositeScore: Double
    let adjustmentPercent: Double

    var adjustmentSecondsPerMile: Double {
        adjustedPaceSeconds - originalPaceSeconds
    }

    var formattedAdjustment: String {
        let secs = Int(adjustmentSecondsPerMile)
        if secs == 0 {
            return "No adjustment"
        }
        return "+\(secs) sec/mi"
    }

    var formattedPercent: String {
        String(format: "%.1f%%", adjustmentPercent * 100)
    }

    var heatCategory: HeatCategory {
        if compositeScore < 100 {
            .ideal
        } else if compositeScore < 130 {
            .warm
        } else if compositeScore < 150 {
            .hot
        } else if compositeScore < 170 {
            .veryHot
        } else {
            .dangerous
        }
    }
}

// MARK: - HeatCategory

enum HeatCategory: String {
    case ideal = "Ideal"
    case warm = "Warm"
    case hot = "Hot"
    case veryHot = "Very Hot"
    case dangerous = "Dangerous"

    var color: Color {
        switch self {
        case .ideal: Color.drip.positive
        case .warm: Color.drip.energized
        case .hot: Color.drip.coralLight
        case .veryHot: Color.drip.coral
        case .dangerous: Color.drip.tired
        }
    }

    var icon: String {
        switch self {
        case .ideal: "checkmark.circle.fill"
        case .warm: "sun.max.fill"
        case .hot: "thermometer.sun.fill"
        case .veryHot: "flame.fill"
        case .dangerous: "exclamationmark.triangle.fill"
        }
    }
}

// MARK: - PaceChartDistance

enum PaceChartDistance: String, CaseIterable, Identifiable {
    case marathon
    case half
    case tenMile = "10mi"
    case tenK = "10K"
    case fiveK = "5K"
    case threeK = "3K"
    case mile
    case fifteenHundred = "1500m"

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .marathon: "Marathon"
        case .half: "Half Marathon"
        case .tenMile: "10 Mile"
        case .tenK: "10K"
        case .fiveK: "5K"
        case .threeK: "3K"
        case .mile: "Mile"
        case .fifteenHundred: "1500m"
        }
    }

    var shortName: String {
        rawValue
    }

    var distanceMiles: Double {
        PaceCalculator.distances[rawValue] ?? 0
    }

    /// Default example time for each distance
    var exampleTime: String {
        switch self {
        case .marathon: "3:30:00"
        case .half: "1:40:00"
        case .tenMile: "1:10:00"
        case .tenK: "45:00"
        case .fiveK: "22:00"
        case .threeK: "12:30"
        case .mile: "5:30"
        case .fifteenHundred: "5:00"
        }
    }

    /// Detect distance from goal title
    static func fromGoalTitle(_ title: String) -> PaceChartDistance? {
        let lower = title.lowercased()
        if lower.contains("marathon") && !lower.contains("half") {
            return .marathon
        } else if lower.contains("half") || lower.contains("hm") {
            return .half
        } else if lower.contains("10 mile") || lower.contains("10mi") || lower.contains("ten mile") {
            return .tenMile
        } else if lower.contains("10k") || lower.contains("10 k") {
            return .tenK
        } else if lower.contains("5k") || lower.contains("5 k") {
            return .fiveK
        } else if lower.contains("3k") || lower.contains("3 k") {
            return .threeK
        } else if lower.contains("mile"), !lower.contains("half"), !lower.contains("10") {
            return .mile
        } else if lower.contains("1500") {
            return .fifteenHundred
        }
        return nil
    }
}

// MARK: - PaceChartViewModel

@Observable
class PaceChartViewModel {
    var selectedDistance: PaceChartDistance = .half
    var goalTimeString: String = "1:40:00"
    var goalTimeSeconds: Int = 6000
    var isEditing = false
    var isLoading = false
    var validationError: String? // Shows warning if time seems unrealistic

    var racePaces: [String: Double] = [:]
    var trainingPaces: [String: Double] = [:]

    // LT (1-hour) pace
    var ltPace: Double?
    var adjustedLtPace: Double?

    /// Unit preference
    var useKilometers = false

    // Weather adjustment
    var weatherEnabled = false
    var isLoadingWeather = false
    var currentWeather: WorkoutWeather?
    var forecastWeather: WorkoutWeather?
    var selectedForecastDate: Date = .init()
    var useForecast = false
    var locationManager = LocationManager()
    var weatherError: String?

    // Adjusted paces
    var adjustedRacePaces: [String: Double] = [:]
    var adjustedTrainingPaces: [String: Double] = [:]
    var currentAdjustment: DewPointAdjustment?

    init() {
        calculatePaces()
    }

    func loadFromGoal() async {
        isLoading = true
        defer { isLoading = false }

        do {
            // Fetch most recent active goal
            let goals: [GoalEntry] = try await supabase
                .from("user_goals")
                .select()
                .eq("status", value: "active")
                .order("target_date", ascending: true)
                .limit(1)
                .execute()
                .value

            if let goal = goals.first {
                await MainActor.run {
                    // Try to detect distance from goal title
                    if let distance = PaceChartDistance.fromGoalTitle(goal.goalTitle) {
                        self.selectedDistance = distance
                        self.goalTimeString = distance.exampleTime
                        if let seconds = PaceCalculator.parseTime(distance.exampleTime, forDistance: distance.rawValue) {
                            self.goalTimeSeconds = seconds
                        }
                    }
                    calculatePaces()
                }
            }
        } catch {
            Log.goals.error("Failed to load goal: \(error)")
        }
    }

    func updateGoalTime(_ timeString: String) {
        goalTimeString = timeString
        if let seconds = PaceCalculator.parseTime(timeString, forDistance: selectedDistance.rawValue) {
            // Validate the parsed time
            validationError = PaceCalculator.validateTime(seconds, forDistance: selectedDistance.rawValue)

            goalTimeSeconds = seconds
            calculatePaces()
        }
    }

    func selectDistance(_ distance: PaceChartDistance) {
        selectedDistance = distance
        // Update to example time for this distance
        goalTimeString = distance.exampleTime
        validationError = nil // Clear any validation error
        if let seconds = PaceCalculator.parseTime(distance.exampleTime, forDistance: distance.rawValue) {
            goalTimeSeconds = seconds
        }
        calculatePaces()
    }

    func calculatePaces() {
        racePaces = PaceCalculator.calculateEquivalentPaces(
            fromDistance: selectedDistance.rawValue,
            totalSeconds: goalTimeSeconds
        )

        // Get MP pace for training pace calculations
        if let mpPace = racePaces["marathon"] {
            trainingPaces = PaceCalculator.calculateTrainingPaces(mpPaceSeconds: mpPace)
        }

        // Calculate LT (1-hour) pace
        ltPace = PaceCalculator.calculateOneHourPace(
            fromDistance: selectedDistance.rawValue,
            totalSeconds: goalTimeSeconds
        )

        // Recalculate weather adjustments if enabled
        if weatherEnabled {
            calculateWeatherAdjustments()
        }
    }

    // MARK: - Weather Functions

    func fetchCurrentWeather() async {
        isLoadingWeather = true

        // Request location permission if needed
        locationManager.requestPermission()

        // Wait for location
        for _ in 0 ..< 20 { // Wait up to 2 seconds
            if locationManager.currentLocation != nil {
                break
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        guard let location = locationManager.currentLocation else {
            await MainActor.run {
                isLoadingWeather = false
            }
            Log.weather.warning("Could not get location")
            return
        }

        let weather = await WeatherService.shared.fetchCurrentWeather(location: location)

        await MainActor.run {
            self.currentWeather = weather
            self.isLoadingWeather = false
            if weatherEnabled {
                calculateWeatherAdjustments()
            }
        }
    }

    func fetchForecastWeather() async {
        var location = locationManager.currentLocation

        // Try to get location first if we don't have one
        if location == nil {
            await fetchCurrentWeather()
            location = locationManager.currentLocation
        }

        guard let location else {
            Log.weather.error("Cannot fetch forecast - no location available")
            return
        }

        isLoadingWeather = true
        Log.weather.debug("Fetching forecast for \(self.selectedForecastDate) at \(location.coordinate.latitude), \(location.coordinate.longitude)")

        let weather = await WeatherService.shared.fetchForecast(for: selectedForecastDate, location: location)

        await MainActor.run {
            self.forecastWeather = weather
            self.isLoadingWeather = false

            if let weather {
                Log.weather.info("Forecast loaded - Temp: \(weather.temperatureFahrenheit)°F, DewPoint: \(weather.dewPointFahrenheit ?? -999)°F")
            } else {
                Log.weather.error("Forecast fetch returned nil")
            }

            if weatherEnabled, useForecast {
                calculateWeatherAdjustments()
            }
        }
    }

    func calculateWeatherAdjustments() {
        // Get the active weather (forecast or current)
        let activeWeather = useForecast ? forecastWeather : currentWeather

        Log.weather.debug("calculateWeatherAdjustments called")
        Log.weather.debug("   - useForecast: \(self.useForecast)")
        Log.weather.debug("   - currentWeather: \(self.currentWeather != nil ? "loaded" : "nil")")
        Log.weather.debug("   - forecastWeather: \(self.forecastWeather != nil ? "loaded" : "nil")")
        Log.weather.debug("   - activeWeather: \(activeWeather != nil ? "loaded" : "nil")")

        let dewPointValue = activeWeather?.dewPointFahrenheit
        guard let weather = activeWeather,
              let dewPoint = weather.dewPointFahrenheit else {
            Log.weather
                .debug("No weather data or dew point - activeWeather: \(activeWeather != nil), dewPoint: \(dewPointValue ?? -999)")
            adjustedRacePaces = [:]
            adjustedTrainingPaces = [:]
            adjustedLtPace = nil
            currentAdjustment = nil
            if activeWeather != nil, dewPointValue == nil {
                weatherError = "Dew point unavailable - cannot calculate adjustment"
            } else {
                weatherError = nil
            }
            return
        }
        weatherError = nil

        Log.weather.info("Weather data available - Temp: \(weather.temperatureFahrenheit)°F, DewPoint: \(dewPoint)°F")

        // Calculate adjustments
        adjustedRacePaces = PaceCalculator.applyWeatherAdjustment(
            paces: racePaces,
            temperatureF: weather.temperatureFahrenheit,
            dewPointF: dewPoint
        )

        adjustedTrainingPaces = PaceCalculator.applyWeatherAdjustment(
            paces: trainingPaces,
            temperatureF: weather.temperatureFahrenheit,
            dewPointF: dewPoint
        )

        // Calculate adjusted LT pace
        if let lt = ltPace {
            let ltAdjustment = PaceCalculator.calculateDewPointAdjustment(
                paceSeconds: lt,
                temperatureF: weather.temperatureFahrenheit,
                dewPointF: dewPoint
            )
            adjustedLtPace = ltAdjustment.adjustedPaceSeconds
        }

        // Get representative adjustment (using MP or reference 8:00/mile pace)
        let referencePace = racePaces["marathon"] ?? 480.0 // 8:00/mile default
        currentAdjustment = PaceCalculator.calculateDewPointAdjustment(
            paceSeconds: referencePace,
            temperatureF: weather.temperatureFahrenheit,
            dewPointF: dewPoint
        )
        let score = currentAdjustment?.compositeScore ?? 0
        let pct = currentAdjustment?.adjustmentPercent ?? 0
        Log.weather.info("Weather adjustment: \(Int(weather.temperatureFahrenheit))°F, DP \(Int(dewPoint))°F → Score: \(Int(score)), +\(String(format: "%.1f", pct * 100))%")
    }

    func toggleWeather() {
        weatherEnabled.toggle()
        if weatherEnabled, currentWeather == nil {
            Task {
                await fetchCurrentWeather()
            }
        } else if weatherEnabled {
            calculateWeatherAdjustments()
        }
    }

    func toggleForecast() {
        useForecast.toggle()
        if useForecast, forecastWeather == nil {
            Task {
                await fetchForecastWeather()
            }
        } else {
            calculateWeatherAdjustments()
        }
    }

    func updateForecastDate(_ date: Date) {
        selectedForecastDate = date
        Task {
            await fetchForecastWeather()
        }
    }
}

// MARK: - LocationManager

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    @Published var currentLocation: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        authorizationStatus = manager.authorizationStatus
        Log.weather.debug("LocationManager init - status: \(self.authorizationStatus.rawValue)")
    }

    func requestPermission() {
        Log.weather.debug("Requesting location permission - current status: \(self.authorizationStatus.rawValue)")
        manager.requestWhenInUseAuthorization()
        if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        currentLocation = locations.last
        if let loc = currentLocation {
            Log.weather.info("Location received: \(loc.coordinate.latitude), \(loc.coordinate.longitude)")
        }
        manager.stopUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        Log.weather.debug("Location authorization changed: \(status.rawValue)")
        authorizationStatus = status
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Log.weather.error("Location error: \(error.localizedDescription)")
    }
}

// MARK: - GoalEntry

struct GoalEntry: Codable {
    let id: UUID
    let goalTitle: String
    let targetDate: Date
    let status: String

    enum CodingKeys: String, CodingKey {
        case id
        case goalTitle = "goal_title"
        case targetDate = "target_date"
        case status
    }
}

// MARK: - PaceChartView

struct PaceChartView: View {
    @State private var viewModel = PaceChartViewModel()
    @Environment(\.dismiss) private var dismiss

    // Splits sheet state
    @State private var showSplitsSheet = false
    @State private var selectedSplitsPace: Double?
    @State private var selectedSplitsName: String = ""

    var body: some View {
        ZStack {
            Color.drip.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    // Goal Race Section
                    goalRaceSection

                    // Weather Adjustment Section
                    weatherAdjustmentSection

                    // Race Paces Section
                    racePacesSection

                    // Training Paces Section
                    trainingPacesSection

                    // Info Section
                    infoSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("Pace Chart")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadFromGoal()
        }
        .sheet(isPresented: $showSplitsSheet) {
            if let pace = selectedSplitsPace {
                PaceSplitsSheet(
                    paceName: selectedSplitsName,
                    paceSecondsPerMile: pace,
                    useKilometers: viewModel.useKilometers
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - Goal Race Section

    private var goalRaceSection: some View {
        VStack(spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "target")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.drip.coral)
                Text("GOAL RACE")
                    .font(.dripCaption(11))
                    .foregroundStyle(Color.drip.textSecondary)
                    .tracking(1.2)
                Spacer()

                if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }

            VStack(spacing: 16) {
                // Distance Picker (Dropdown)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Distance")
                        .font(.dripCaption(11))
                        .foregroundStyle(Color.drip.textSecondary)

                    Menu {
                        ForEach(PaceChartDistance.allCases) { distance in
                            Button {
                                viewModel.selectDistance(distance)
                            } label: {
                                HStack {
                                    Text(distance.displayName)
                                    if viewModel.selectedDistance == distance {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Text(viewModel.selectedDistance.displayName)
                                .font(.dripLabel(16))
                                .foregroundStyle(Color.drip.textPrimary)

                            Spacer()

                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.drip.coral)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(Color.drip.cardBackgroundElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }

                // Time Input
                VStack(alignment: .leading, spacing: 8) {
                    Text("Goal Time")
                        .font(.dripCaption(11))
                        .foregroundStyle(Color.drip.textSecondary)

                    HStack {
                        TextField("1:40:00", text: $viewModel.goalTimeString)
                            .font(.dripStat(32))
                            .foregroundStyle(Color.drip.textPrimary)
                            .keyboardType(.numbersAndPunctuation)
                            .multilineTextAlignment(.center)
                            .onChange(of: viewModel.goalTimeString) { _, newValue in
                                viewModel.updateGoalTime(newValue)
                            }

                        Button {
                            viewModel.calculatePaces()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color.drip.coral)
                                .padding(10)
                                .background(Color.drip.coral.opacity(0.15))
                                .clipShape(Circle())
                        }
                    }
                    .padding(16)
                    .background(Color.drip.cardBackgroundElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    // Validation error/warning
                    if let error = viewModel.validationError {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 12))
                            Text(error)
                                .font(.dripCaption(11))
                        }
                        .foregroundStyle(Color.drip.tired)
                        .padding(.top, 4)
                    }
                }

                // Calculated pace for goal
                if let goalPace = viewModel.racePaces[viewModel.selectedDistance.rawValue] {
                    HStack {
                        Text("Goal Pace:")
                            .font(.dripBody(14))
                            .foregroundStyle(Color.drip.textSecondary)
                        Spacer()
                        Text(formatPaceWithUnit(goalPace))
                            .font(.dripLabel(16))
                            .foregroundStyle(Color.drip.coral)
                    }
                }

                // KM / Miles toggle
                HStack(spacing: 0) {
                    Button {
                        viewModel.useKilometers = false
                    } label: {
                        Text("Miles")
                            .font(.dripLabel(13))
                            .foregroundStyle(!viewModel.useKilometers ? .white : Color.drip.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(!viewModel.useKilometers ? Color.drip.coral : Color.clear)
                    }

                    Button {
                        viewModel.useKilometers = true
                    } label: {
                        Text("Kilometers")
                            .font(.dripLabel(13))
                            .foregroundStyle(viewModel.useKilometers ? .white : Color.drip.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(viewModel.useKilometers ? Color.drip.coral : Color.clear)
                    }
                }
                .background(Color.drip.cardBackgroundElevated)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .padding(16)
            .background(Color.drip.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    // MARK: - Pace Formatting Helpers

    private func formatPaceWithUnit(_ secondsPerMile: Double) -> String {
        if viewModel.useKilometers {
            "\(PaceCalculator.formatPaceKm(secondsPerMile)) /km"
        } else {
            "\(PaceCalculator.formatPace(secondsPerMile)) /mi"
        }
    }

    private func formatPaceRangeWithUnit(low: Double?, high: Double?) -> String? {
        guard let low else { return nil }

        if let high {
            if viewModel.useKilometers {
                return "\(PaceCalculator.formatPaceKm(high)) - \(PaceCalculator.formatPaceKm(low))"
            } else {
                return "\(PaceCalculator.formatPace(high)) - \(PaceCalculator.formatPace(low))"
            }
        } else {
            if viewModel.useKilometers {
                return "\(PaceCalculator.formatPaceKm(low))+"
            } else {
                return "\(PaceCalculator.formatPace(low))+"
            }
        }
    }

    // MARK: - Weather Adjustment Section

    private var weatherAdjustmentSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "thermometer.sun.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.drip.coralLight)
                Text("WEATHER ADJUSTMENT")
                    .font(.dripCaption(11))
                    .foregroundStyle(Color.drip.textSecondary)
                    .tracking(1.2)
                Spacer()

                Toggle("", isOn: Binding(
                    get: { viewModel.weatherEnabled },
                    set: { _ in viewModel.toggleWeather() }
                ))
                .labelsHidden()
                .tint(Color.drip.coral)
            }

            if viewModel.weatherEnabled {
                VStack(spacing: 16) {
                    // Current vs Forecast Toggle
                    HStack(spacing: 0) {
                        Button {
                            viewModel.useForecast = false
                            viewModel.calculateWeatherAdjustments()
                        } label: {
                            Text("Current")
                                .font(.dripLabel(13))
                                .foregroundStyle(!viewModel.useForecast ? .white : Color.drip.textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(!viewModel.useForecast ? Color.drip.coral : Color.clear)
                        }

                        Button {
                            viewModel.toggleForecast()
                        } label: {
                            Text("Forecast")
                                .font(.dripLabel(13))
                                .foregroundStyle(viewModel.useForecast ? .white : Color.drip.textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(viewModel.useForecast ? Color.drip.coral : Color.clear)
                        }
                    }
                    .background(Color.drip.cardBackgroundElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    // Forecast Date/Time Picker
                    if viewModel.useForecast {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Run Time")
                                .font(.dripCaption(11))
                                .foregroundStyle(Color.drip.textSecondary)

                            DatePicker(
                                "",
                                selection: Binding(
                                    get: { viewModel.selectedForecastDate },
                                    set: { viewModel.updateForecastDate($0) }
                                ),
                                in: Date() ... (Calendar.current.date(byAdding: .day, value: 14, to: Date()) ?? Date()),
                                displayedComponents: [.date, .hourAndMinute]
                            )
                            .labelsHidden()
                            .datePickerStyle(.compact)
                            .tint(Color.drip.coral)
                        }
                    }

                    // Weather Display
                    if viewModel.isLoadingWeather {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Fetching weather...")
                                .font(.dripCaption(12))
                                .foregroundStyle(Color.drip.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    } else if let weather = viewModel.useForecast ? viewModel.forecastWeather : viewModel.currentWeather {
                        weatherDisplayCard(weather: weather)
                    } else {
                        // No weather data
                        Button {
                            Task {
                                if viewModel.useForecast {
                                    await viewModel.fetchForecastWeather()
                                } else {
                                    await viewModel.fetchCurrentWeather()
                                }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "location.fill")
                                Text("Get Weather")
                            }
                            .font(.dripLabel(14))
                            .foregroundStyle(Color.drip.coral)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.drip.coral.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }

                    // Adjustment Summary or Error
                    if let adjustment = viewModel.currentAdjustment {
                        adjustmentSummaryCard(adjustment: adjustment)
                    } else if let error = viewModel.weatherError {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(Color.drip.energized)
                            Text(error)
                                .font(.dripCaption(12))
                                .foregroundStyle(Color.drip.textSecondary)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity)
                        .background(Color.drip.energized.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding(16)
                .background(Color.drip.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private func weatherDisplayCard(weather: WorkoutWeather) -> some View {
        HStack(spacing: 16) {
            // Weather Icon & Condition
            VStack(spacing: 4) {
                Image(systemName: weather.icon)
                    .font(.system(size: 28))
                    .foregroundStyle(Color.drip.energized)
                Text(weather.description)
                    .font(.dripCaption(10))
                    .foregroundStyle(Color.drip.textTertiary)
            }
            .frame(width: 70)

            // Temperature & Dew Point
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("TEMP")
                            .font(.dripCaption(9))
                            .foregroundStyle(Color.drip.textTertiary)
                        Text(weather.formattedTemperature)
                            .font(.dripStat(22))
                            .foregroundStyle(Color.drip.textPrimary)
                    }

                    if let dewPoint = weather.formattedDewPoint {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("DEW POINT")
                                .font(.dripCaption(9))
                                .foregroundStyle(Color.drip.textTertiary)
                            Text(dewPoint)
                                .font(.dripStat(22))
                                .foregroundStyle(Color.drip.textPrimary)
                        }
                    }
                }

                if let humidity = weather.humidity {
                    Text("Humidity: \(humidity)%")
                        .font(.dripCaption(11))
                        .foregroundStyle(Color.drip.textSecondary)
                }
            }

            Spacer()

            // Refresh button
            Button {
                Task {
                    if viewModel.useForecast {
                        await viewModel.fetchForecastWeather()
                    } else {
                        await viewModel.fetchCurrentWeather()
                    }
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.drip.textSecondary)
            }
        }
        .padding(12)
        .background(Color.drip.cardBackgroundElevated)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func adjustmentSummaryCard(adjustment: DewPointAdjustment) -> some View {
        VStack(spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: adjustment.heatCategory.icon)
                        .font(.system(size: 14))
                        .foregroundStyle(adjustment.heatCategory.color)
                    Text(adjustment.heatCategory.rawValue)
                        .font(.dripLabel(14))
                        .foregroundStyle(adjustment.heatCategory.color)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(adjustment.formattedAdjustment)
                        .font(.dripStat(18))
                        .foregroundStyle(adjustment.heatCategory.color)
                    Text("(\(adjustment.formattedPercent) slower)")
                        .font(.dripCaption(10))
                        .foregroundStyle(Color.drip.textTertiary)
                }
            }

            // Composite score indicator
            VStack(spacing: 4) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        // Background
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.drip.cardBackgroundElevated)
                            .frame(height: 6)

                        // Gradient scale
                        LinearGradient(
                            colors: [Color.drip.positive, Color.drip.energized, Color.drip.coralLight, Color.drip.coral, Color.drip.tired],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .frame(height: 6)

                        // Indicator
                        let position = min(max((adjustment.compositeScore - 80) / 120, 0), 1) // Scale 80-200
                        Circle()
                            .fill(.white)
                            .frame(width: 12, height: 12)
                            .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
                            .offset(x: geo.size.width * position - 6)
                    }
                }
                .frame(height: 12)

                HStack {
                    Text("Ideal")
                        .font(.dripCaption(9))
                        .foregroundStyle(Color.drip.textTertiary)
                    Spacer()
                    Text("Score: \(Int(adjustment.compositeScore))")
                        .font(.dripCaption(9))
                        .foregroundStyle(Color.drip.textSecondary)
                    Spacer()
                    Text("Dangerous")
                        .font(.dripCaption(9))
                        .foregroundStyle(Color.drip.textTertiary)
                }
            }
        }
        .padding(12)
        .background(adjustment.heatCategory.color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(adjustment.heatCategory.color.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Race Paces Section

    private var racePacesSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "speedometer")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.drip.energized)
                Text("RACE PACES")
                    .font(.dripCaption(11))
                    .foregroundStyle(Color.drip.textSecondary)
                    .tracking(1.2)
                Spacer()
            }

            VStack(spacing: 0) {
                ForEach(PaceChartDistance.allCases) { distance in
                    if let pace = viewModel.racePaces[distance.rawValue] {
                        racePaceRow(
                            distance: distance,
                            pace: pace,
                            isGoal: distance == viewModel.selectedDistance
                        )

                        if distance != PaceChartDistance.allCases.last {
                            Divider()
                                .background(Color.drip.divider)
                        }
                    }
                }
            }
            .background(Color.drip.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    private func racePaceRow(distance: PaceChartDistance, pace: Double, isGoal: Bool) -> some View {
        let adjustedPace = viewModel.weatherEnabled ? viewModel.adjustedRacePaces[distance.rawValue] : nil
        let displayPace = adjustedPace ?? pace

        return Button {
            selectedSplitsPace = displayPace
            selectedSplitsName = distance.displayName
            showSplitsSheet = true
        } label: {
            HStack {
                HStack(spacing: 8) {
                    if isGoal {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.drip.coral)
                    }
                    Text(distance.displayName)
                        .font(.dripLabel(14))
                        .foregroundStyle(isGoal ? Color.drip.coral : Color.drip.textPrimary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    if let adjusted = adjustedPace, viewModel.weatherEnabled {
                        // Show adjusted pace
                        HStack(spacing: 6) {
                            Text(viewModel.useKilometers ? PaceCalculator.formatPaceKm(pace) : PaceCalculator.formatPace(pace))
                                .font(.dripCaption(12))
                                .foregroundStyle(Color.drip.textTertiary)
                                .strikethrough()
                            Image(systemName: "arrow.right")
                                .font(.system(size: 8))
                                .foregroundStyle(Color.drip.textTertiary)
                            Text(formatPaceWithUnit(adjusted))
                                .font(.dripStat(18))
                                .foregroundStyle(viewModel.currentAdjustment?.heatCategory.color ?? Color.drip.coralLight)
                        }
                    } else {
                        Text(formatPaceWithUnit(pace))
                            .font(.dripStat(18))
                            .foregroundStyle(isGoal ? Color.drip.coral : Color.drip.textPrimary)
                    }

                    // Show estimated finish time (use adjusted if available)
                    let finishTime = Int(displayPace * distance.distanceMiles)
                    Text(PaceCalculator.formatTime(finishTime))
                        .font(.dripCaption(11))
                        .foregroundStyle(Color.drip.textTertiary)
                }

                // Chevron indicator
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.drip.textTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(isGoal ? Color.drip.coral.opacity(0.08) : Color.clear)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Training Paces Section

    private var trainingPacesSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.drip.positive)
                Text("TRAINING PACES")
                    .font(.dripCaption(11))
                    .foregroundStyle(Color.drip.textSecondary)
                    .tracking(1.2)
                Spacer()

                Text("Based on MP")
                    .font(.dripCaption(10))
                    .foregroundStyle(Color.drip.textTertiary)
            }

            VStack(spacing: 0) {
                // Easy (not clickable)
                trainingPaceRow(
                    name: "Easy",
                    description: "75% effort or less",
                    paceRange: formatPaceRangeWithUnit(low: viewModel.trainingPaces["Easy"], high: nil) ?? "--",
                    adjustedPaceRange: formatPaceRangeWithUnit(low: viewModel.adjustedTrainingPaces["Easy"], high: nil),
                    color: Color.drip.positive,
                    icon: "leaf.fill",
                    isClickable: false,
                    pace: nil
                )

                Divider().background(Color.drip.divider)

                // Moderate (not clickable)
                trainingPaceRow(
                    name: "Moderate",
                    description: "75-85% effort",
                    paceRange: formatPaceRangeWithUnit(
                        low: viewModel.trainingPaces["Moderate Low"],
                        high: viewModel.trainingPaces["Moderate High"]
                    ) ?? "--",
                    adjustedPaceRange: formatPaceRangeWithUnit(
                        low: viewModel.adjustedTrainingPaces["Moderate Low"],
                        high: viewModel.adjustedTrainingPaces["Moderate High"]
                    ),
                    color: Color.drip.energized,
                    icon: "figure.walk",
                    isClickable: false,
                    pace: nil
                )

                Divider().background(Color.drip.divider)

                // Steady (not clickable)
                trainingPaceRow(
                    name: "Steady",
                    description: "85-95% effort",
                    paceRange: formatPaceRangeWithUnit(
                        low: viewModel.trainingPaces["Steady Low"],
                        high: viewModel.trainingPaces["Steady High"]
                    ) ?? "--",
                    adjustedPaceRange: formatPaceRangeWithUnit(
                        low: viewModel.adjustedTrainingPaces["Steady Low"],
                        high: viewModel.adjustedTrainingPaces["Steady High"]
                    ),
                    color: Color.drip.coralLight,
                    icon: "flame",
                    isClickable: false,
                    pace: nil
                )

                Divider().background(Color.drip.divider)

                // MP - Marathon Pace (clickable)
                if let mpPace = viewModel.racePaces["marathon"] {
                    let adjustedMp = viewModel.adjustedRacePaces["marathon"]
                    let displayPace = viewModel.weatherEnabled ? (adjustedMp ?? mpPace) : mpPace
                    trainingPaceRow(
                        name: "MP",
                        description: "Marathon Pace",
                        paceRange: viewModel.useKilometers ? PaceCalculator.formatPaceKm(mpPace) : PaceCalculator.formatPace(mpPace),
                        adjustedPaceRange: adjustedMp
                            .map { viewModel.useKilometers ? PaceCalculator.formatPaceKm($0) : PaceCalculator.formatPace($0) },
                        color: Color.drip.coral,
                        icon: "bolt.fill",
                        isClickable: true,
                        pace: displayPace
                    )
                }

                Divider().background(Color.drip.divider)

                // HMP - Half Marathon Pace (clickable)
                if let hmpPace = viewModel.racePaces["half"] {
                    let adjustedHmp = viewModel.adjustedRacePaces["half"]
                    let displayPace = viewModel.weatherEnabled ? (adjustedHmp ?? hmpPace) : hmpPace
                    trainingPaceRow(
                        name: "HMP",
                        description: "Half Marathon Pace",
                        paceRange: viewModel.useKilometers ? PaceCalculator.formatPaceKm(hmpPace) : PaceCalculator.formatPace(hmpPace),
                        adjustedPaceRange: adjustedHmp
                            .map { viewModel.useKilometers ? PaceCalculator.formatPaceKm($0) : PaceCalculator.formatPace($0) },
                        color: Color.drip.tired,
                        icon: "bolt.horizontal.fill",
                        isClickable: true,
                        pace: displayPace
                    )
                }

            }
            .background(Color.drip.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    @ViewBuilder
    private func trainingPaceRow(
        name: String,
        description: String,
        paceRange: String,
        adjustedPaceRange: String?,
        color: Color,
        icon: String,
        isClickable: Bool,
        pace: Double?
    ) -> some View {
        let unit = viewModel.useKilometers ? "/km" : "/mi"

        let content = HStack {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(color)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.dripLabel(14))
                        .foregroundStyle(Color.drip.textPrimary)
                    Text(description)
                        .font(.dripCaption(11))
                        .foregroundStyle(Color.drip.textTertiary)
                }
            }

            Spacer()

            if let adjusted = adjustedPaceRange, viewModel.weatherEnabled {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(adjusted) \(unit)")
                        .font(.dripStat(16))
                        .foregroundStyle(viewModel.currentAdjustment?.heatCategory.color ?? color)
                    Text(paceRange)
                        .font(.dripCaption(10))
                        .foregroundStyle(Color.drip.textTertiary)
                        .strikethrough()
                }
            } else {
                Text("\(paceRange) \(unit)")
                    .font(.dripStat(16))
                    .foregroundStyle(color)
            }

            if isClickable {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.drip.textTertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)

        if isClickable, let pace {
            Button {
                selectedSplitsPace = pace
                selectedSplitsName = name
                showSplitsSheet = true
            } label: {
                content
            }
            .buttonStyle(.plain)
        } else {
            content
        }
    }

    private func formatTrainingPaceRange(low: Double?, high: Double?) -> String? {
        if let low, let high {
            return "\(PaceCalculator.formatPace(high)) - \(PaceCalculator.formatPace(low))"
        } else if let low {
            return "\(PaceCalculator.formatPace(low))+"
        }
        return nil
    }

    // MARK: - Info Section

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.drip.textTertiary)
                Text("ABOUT THESE PACES")
                    .font(.dripCaption(11))
                    .foregroundStyle(Color.drip.textSecondary)
                    .tracking(1.2)
            }

            VStack(alignment: .leading, spacing: 8) {
                // swiftlint:disable:next line_length
                Text("Race paces are calculated using standard equivalency formulas. Training paces are based on percentage of marathon pace (MP) effort.")
                    .font(.dripCaption(12))
                    .foregroundStyle(Color.drip.textTertiary)

                Text("MP = Marathon Pace")
                    .font(.dripCaption(12))
                    .foregroundStyle(Color.drip.textTertiary)

                Text("HMP = Half Marathon Pace")
                    .font(.dripCaption(12))
                    .foregroundStyle(Color.drip.textTertiary)

                if viewModel.weatherEnabled {
                    Divider().background(Color.drip.divider)

                    // swiftlint:disable:next line_length
                    Text("Weather adjustments use the Dew Point Heat Index formula: higher temperature and humidity require slower paces to maintain the same effort level.")
                        .font(.dripCaption(12))
                        .foregroundStyle(Color.drip.textTertiary)
                }
            }
            .padding(16)
            .background(Color.drip.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

// MARK: - PaceSplitsSheet

struct PaceSplitsSheet: View {
    let paceName: String
    let paceSecondsPerMile: Double
    let useKilometers: Bool

    @Environment(\.dismiss) private var dismiss

    private var splits: (fourHundred: Double, oneK: Double, mile: Double) {
        PaceCalculator.calculateSplits(paceSecondsPerMile: paceSecondsPerMile)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.drip.background.ignoresSafeArea()

                VStack(spacing: 24) {
                    // Pace header
                    VStack(spacing: 8) {
                        Text(paceName)
                            .font(.dripLabel(14))
                            .foregroundStyle(Color.drip.textSecondary)
                            .tracking(1.2)

                        Text(useKilometers ? PaceCalculator.formatPaceKm(paceSecondsPerMile) : PaceCalculator.formatPace(paceSecondsPerMile))
                            .font(.dripStat(48))
                            .foregroundStyle(Color.drip.coral)

                        Text(useKilometers ? "per kilometer" : "per mile")
                            .font(.dripCaption(12))
                            .foregroundStyle(Color.drip.textTertiary)
                    }
                    .padding(.top, 16)

                    // Splits grid
                    VStack(spacing: 0) {
                        HStack(spacing: 8) {
                            Image(systemName: "timer")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.drip.energized)
                            Text("SPLITS")
                                .font(.dripCaption(11))
                                .foregroundStyle(Color.drip.textSecondary)
                                .tracking(1.2)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)

                        VStack(spacing: 0) {
                            splitRow(distance: "400m", time: splits.fourHundred, icon: "figure.run")

                            Divider().background(Color.drip.divider)

                            splitRow(distance: "1K", time: splits.oneK, icon: "flame")

                            Divider().background(Color.drip.divider)

                            splitRow(distance: "Mile", time: splits.mile, icon: "flag.fill")
                        }
                        .background(Color.drip.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .padding(.horizontal, 20)

                    Spacer()
                }
            }
            .navigationTitle("Pace Splits")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(Color.drip.textTertiary)
                    }
                }
            }
        }
    }

    private func splitRow(distance: String, time: Double, icon: String) -> some View {
        HStack {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(Color.drip.coral)
                    .frame(width: 24)

                Text(distance)
                    .font(.dripLabel(16))
                    .foregroundStyle(Color.drip.textPrimary)
            }

            Spacer()

            Text(PaceCalculator.formatSplit(time))
                .font(.dripStat(24))
                .foregroundStyle(Color.drip.textPrimary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
    }
}

#Preview {
    NavigationStack {
        PaceChartView()
    }
}

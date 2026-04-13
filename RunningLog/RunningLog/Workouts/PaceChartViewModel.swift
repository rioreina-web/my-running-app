import Combine
import CoreLocation
import Foundation
import os
import Supabase
import SwiftUI

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
    var selectedDistance: PaceChartDistance = .half {
        didSet { if !isLoadingDefaults { saveGoalToDefaults() } }
    }
    var goalTimeString: String = "1:40:00" {
        didSet { if !isLoadingDefaults { saveGoalToDefaults() } }
    }
    var goalTimeSeconds: Int = 6000 {
        didSet { if !isLoadingDefaults { saveGoalToDefaults() } }
    }
    private var isLoadingDefaults = false
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

    private static let distanceKey = "paceChart_selectedDistance"
    private static let timeStringKey = "paceChart_goalTimeString"
    private static let timeSecondsKey = "paceChart_goalTimeSeconds"

    /// Version key for one-time cache invalidation
    private static let cacheVersionKey = "paceChart_cacheVersion"
    private static let currentCacheVersion = 2  // Bump to invalidate stale defaults

    init() {
        // One-time: clear stale cached pace data from before the fix
        if UserDefaults.standard.integer(forKey: Self.cacheVersionKey) < Self.currentCacheVersion {
            UserDefaults.standard.removeObject(forKey: Self.distanceKey)
            UserDefaults.standard.removeObject(forKey: Self.timeStringKey)
            UserDefaults.standard.removeObject(forKey: Self.timeSecondsKey)
            UserDefaults.standard.set(Self.currentCacheVersion, forKey: Self.cacheVersionKey)
            Log.goals.info("Cleared stale pace chart cache (version migration)")
        }
        loadGoalFromDefaults()
        calculatePaces()
    }

    func loadFromGoal() async {
        isLoading = true
        defer { isLoading = false }

        // Priority 1: Always try active training plan first (has exact goal time)
        if await loadFromActivePlan() { return }

        // Priority 2: Load from user goals table (parse time from title)
        if await loadFromUserGoal() { return }

        // Priority 3: Load from fitness predictor snapshot (most recent prediction)
        if await loadFromFitnessSnapshot() { return }
    }

    /// Load from user_goals table — only if we can parse an actual time from the title
    private func loadFromUserGoal() async -> Bool {
        do {
            let goals: [GoalEntry] = try await supabase
                .from("user_goals")
                .select()
                .eq("status", value: "active")
                .order("target_date", ascending: true)
                .limit(1)
                .execute()
                .value

            if let goal = goals.first,
               let distance = PaceChartDistance.fromGoalTitle(goal.goalTitle),
               let parsedTime = Self.parseTimeFromTitle(goal.goalTitle, distance: distance),
               let seconds = PaceCalculator.parseTime(parsedTime, forDistance: distance.rawValue) {
                await MainActor.run {
                    self.selectedDistance = distance
                    self.goalTimeString = parsedTime
                    self.goalTimeSeconds = seconds
                    calculatePaces()
                    Log.goals.info("Loaded pace chart from goal title: \(distance.displayName) \(parsedTime)")
                }
                return true
            }
        } catch {
            Log.goals.error("Failed to load goal: \(error)")
        }
        return false
    }

    /// Load from the most recent fitness snapshot — uses predicted race times as the pace basis
    private func loadFromFitnessSnapshot() async -> Bool {
        do {
            struct SnapshotGoal: Codable {
                let predictedMarathonSeconds: Int
                let predicted10kSeconds: Int
                let confidence: String
                enum CodingKeys: String, CodingKey {
                    case predictedMarathonSeconds = "predicted_marathon_seconds"
                    case predicted10kSeconds = "predicted_10k_seconds"
                    case confidence
                }
            }

            let snapshots: [SnapshotGoal] = try await supabase
                .from("fitness_snapshots")
                .select("predicted_marathon_seconds, predicted_10k_seconds, confidence")
                .order("created_at", ascending: false)
                .limit(1)
                .execute()
                .value

            if let snap = snapshots.first, snap.predictedMarathonSeconds > 0 {
                await MainActor.run {
                    // Use marathon prediction as the pace chart basis
                    self.selectedDistance = .marathon
                    self.goalTimeSeconds = snap.predictedMarathonSeconds
                    self.goalTimeString = PaceCalculator.formatSeconds(snap.predictedMarathonSeconds)
                    calculatePaces()
                    Log.goals.info("Loaded pace chart from fitness snapshot: marathon \(self.goalTimeString) (confidence: \(snap.confidence))")
                }
                return true
            }
        } catch {
            Log.goals.error("Failed to load fitness snapshot for pace chart: \(error)")
        }
        return false
    }

    /// Parse a race time from a goal title string like "2:35 Marathon", "Sub-3:00 Marathon", "1:15 Half Marathon"
    static func parseTimeFromTitle(_ title: String, distance: PaceChartDistance) -> String? {
        // Match time patterns: H:MM:SS, H:MM, M:SS (with optional "sub-" prefix)
        let pattern = #"(?:sub[- ]?)?(\d{1,2}:\d{2}(?::\d{2})?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)),
              let timeRange = Range(match.range(at: 1), in: title) else {
            return nil
        }
        return String(title[timeRange])
    }

    /// Load goal race from the active training plan
    private func loadFromActivePlan() async -> Bool {
        do {
            struct PlanGoal: Codable {
                let targetRaceDistance: String?
                let targetTimeSeconds: Int?
                enum CodingKeys: String, CodingKey {
                    case targetRaceDistance = "target_race_distance"
                    case targetTimeSeconds = "target_time_seconds"
                }
            }

            let plans: [PlanGoal] = try await supabase
                .from("training_plans")
                .select("target_race_distance, target_time_seconds")
                .eq("status", value: "active")
                .order("created_at", ascending: false)
                .limit(1)
                .execute()
                .value

            if let plan = plans.first,
               let distStr = plan.targetRaceDistance,
               let seconds = plan.targetTimeSeconds,
               seconds > 0 {
                await MainActor.run {
                    // Map plan distance to PaceChartDistance
                    let distMap: [String: PaceChartDistance] = [
                        "marathon": .marathon, "half_marathon": .half,
                        "10k": .tenK, "5k": .fiveK, "mile": .mile,
                    ]
                    if let distance = distMap[distStr] {
                        self.selectedDistance = distance
                        self.goalTimeSeconds = seconds
                        self.goalTimeString = PaceCalculator.formatSeconds(seconds)
                        calculatePaces()
                        Log.goals.info("Loaded pace chart goal from training plan: \(distance.displayName) \(self.goalTimeString)")
                    }
                }
                return true
            }
        } catch {
            Log.goals.error("Failed to load training plan goal: \(error)")
        }
        return false
    }

    // MARK: - Persistence

    private func saveGoalToDefaults() {
        UserDefaults.standard.set(selectedDistance.rawValue, forKey: Self.distanceKey)
        UserDefaults.standard.set(goalTimeString, forKey: Self.timeStringKey)
        UserDefaults.standard.set(goalTimeSeconds, forKey: Self.timeSecondsKey)
    }

    private func loadGoalFromDefaults() {
        guard let distRaw = UserDefaults.standard.string(forKey: Self.distanceKey),
              let distance = PaceChartDistance(rawValue: distRaw) else { return }
        let savedSeconds = UserDefaults.standard.integer(forKey: Self.timeSecondsKey)
        guard savedSeconds > 0 else { return }
        let savedTimeString = UserDefaults.standard.string(forKey: Self.timeStringKey) ?? PaceCalculator.formatSeconds(savedSeconds)

        isLoadingDefaults = true
        selectedDistance = distance
        goalTimeString = savedTimeString
        goalTimeSeconds = savedSeconds
        isLoadingDefaults = false
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
        let previousDistance = selectedDistance
        let previousSeconds = goalTimeSeconds
        selectedDistance = distance
        validationError = nil

        // Convert current goal time to equivalent time at the new distance
        let equivalentSeconds = PaceCalculator.getEquivalentTime(
            fromDistance: previousDistance.rawValue,
            fromSeconds: previousSeconds,
            toDistance: distance.rawValue
        )
        if equivalentSeconds > 0 {
            goalTimeSeconds = equivalentSeconds
            goalTimeString = PaceCalculator.formatSeconds(equivalentSeconds)
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

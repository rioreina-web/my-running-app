//
//  VitalManager.swift
//  RunningLog
//
//  Service for fetching workout data from the Vital (Junction) API.
//

import CoreLocation
import Foundation
import os

// MARK: - VitalManager

@Observable
final class VitalManager {
    static let shared = VitalManager()

    private let baseURL = "https://api.sandbox.tryvital.io/v2"
    private let apiKey: String = Bundle.main.infoDictionary?["VITAL_API_KEY"] as? String ?? ""
    private let userId: String = Bundle.main.infoDictionary?["VITAL_USER_ID"] as? String ?? ""

    var recentWorkouts: [RunningWorkout] = []
    var isAuthorized = true // Vital is always authorized once connected

    /// Cache of Vital summaries keyed by workout ID
    @ObservationIgnored private var summaryCache: [String: VitalWorkoutSummary] = [:]

    // MARK: - Fetch Workouts

    /// Fetch running workouts from Vital within a date range
    func fetchVitalSummaries(startDate: Date, endDate: Date) async -> [VitalWorkoutSummary] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        let url = "\(baseURL)/summary/workouts/\(userId)?start_date=\(formatter.string(from: startDate))&end_date=\(formatter.string(from: endDate))"

        guard let data = await vitalRequest(url: url) else { return [] }

        do {
            let response = try JSONDecoder().decode(VitalWorkoutsResponse.self, from: data)
            return response.workouts.filter { $0.sport?.slug == "running" }
        } catch {
            Log.health.error("Failed to decode Vital workouts: \(error)")
            return []
        }
    }

    /// Fetch recent running workouts (last 90 days)
    func fetchRecentRunningWorkouts(limit: Int = 30) async -> [RunningWorkout] {
        let endDate = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -90, to: endDate) ?? endDate

        let vitalWorkouts = await fetchVitalSummaries(startDate: startDate, endDate: endDate)

        // Cache summaries
        for vw in vitalWorkouts {
            summaryCache[vw.id] = vw
        }

        let workouts = vitalWorkouts.prefix(limit).map { $0.toRunningWorkout() }
        return Array(workouts)
    }

    /// Fetch running miles per day for a date range (replaces HealthKit version)
    func fetchRunningMilesByDate(from startDate: Date, to endDate: Date) async -> [String: Double] {
        let vitalWorkouts = await fetchVitalSummaries(startDate: startDate, endDate: endDate)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        var milesByDate: [String: Double] = [:]
        for workout in vitalWorkouts {
            let miles = (workout.distance ?? 0) / 1609.34
            if miles > 0 {
                milesByDate[workout.calendarDate, default: 0] += miles
            }
        }
        return milesByDate
    }

    /// Fetch workouts for a specific day
    func fetchRunningWorkouts(for date: Date) async -> [RunningWorkout] {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return [] }

        let vitalWorkouts = await fetchVitalSummaries(startDate: dayStart, endDate: dayEnd)
        for vw in vitalWorkouts {
            summaryCache[vw.id] = vw
        }
        return vitalWorkouts.map { $0.toRunningWorkout() }
    }

    /// Get cached summary for a workout ID
    func getSummary(for workoutId: String) -> VitalWorkoutSummary? {
        summaryCache[workoutId]
    }

    // MARK: - Fetch Workout Stream (GPS, HR, Elevation, etc.)

    /// Fetch the full per-second stream data for a workout (retries once on failure)
    func fetchWorkoutStream(workoutId: String) async -> VitalWorkoutStream? {
        let url = "\(baseURL)/timeseries/workouts/\(workoutId)/stream"

        for attempt in 1...2 {
            // Check cancellation before each attempt
            guard !Task.isCancelled else {
                Log.health.info("Stream fetch cancelled for \(workoutId)")
                return nil
            }

            guard let data = await vitalRequest(url: url, timeout: 60) else {
                Log.health.error("Stream fetch attempt \(attempt) returned nil for workout: \(workoutId)")
                if attempt < 2 {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                }
                continue
            }

            do {
                let stream = try JSONDecoder().decode(VitalWorkoutStream.self, from: data)
                Log.health.info("Stream decoded OK: \(stream.time?.count ?? 0) points for \(workoutId)")
                return stream
            } catch {
                Log.health.error("Stream decode failed (attempt \(attempt)): \(error)")
                if attempt < 2 {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                }
            }
        }
        return nil
    }

    /// Fetch heart rate samples from workout stream
    func fetchHeartRateSamples(workoutId: String) async -> [HeartRateSample] {
        guard let stream = await fetchWorkoutStream(workoutId: workoutId) else { return [] }
        guard let heartrates = stream.heartrate, let times = stream.time,
              heartrates.count == times.count, !heartrates.isEmpty
        else { return [] }

        let startTime = times[0]
        return zip(times, heartrates).map { time, bpm in
            HeartRateSample(
                timestamp: Double(time - startTime),
                bpm: Double(bpm)
            )
        }
    }

    /// Calculate mile splits from stream distance/time data.
    /// Excludes stopped time (velocity < 0.5 m/s) so splits reflect moving time only.
    func calculateSplits(from stream: VitalWorkoutStream) -> [MileSplit] {
        guard let distances = stream.distance, let times = stream.time,
              distances.count == times.count, distances.count >= 2
        else { return [] }

        let velocities = stream.velocitySmooth
        let mileInMeters = 1609.34
        // Match Garmin auto-pause: ~17:00/mile pace = 1.58 m/s
        let stoppedThreshold = 1.6 // m/s — below this, runner is stopped/walking

        // Pre-compute cumulative moving time at each data point
        var movingTimeAt: [Double] = [0]
        for i in 1..<times.count {
            let dt = Double(times[i] - times[i - 1])
            let isMoving = velocities?[i] ?? 1.0 >= stoppedThreshold
            movingTimeAt.append(movingTimeAt[i - 1] + (isMoving ? dt : 0))
        }

        var splits: [MileSplit] = []
        var currentMile = 1
        var mileStartMovingTime = 0.0

        for mile in 1...100 {
            let targetDistance = Double(mile) * mileInMeters
            guard let totalDistance = distances.last, targetDistance <= totalDistance else { break }

            for i in 1..<distances.count {
                if distances[i] >= targetDistance && distances[i - 1] < targetDistance {
                    // Interpolate moving time at exact mile crossing
                    let distRange = distances[i] - distances[i - 1]
                    let fraction = distRange > 0 ? (targetDistance - distances[i - 1]) / distRange : 0
                    let movingTimeRange = movingTimeAt[i] - movingTimeAt[i - 1]
                    let mileEndMovingTime = movingTimeAt[i - 1] + (fraction * movingTimeRange)

                    let mileMovingTime = mileEndMovingTime - mileStartMovingTime
                    let paceMinutes = mileMovingTime / 60.0

                    splits.append(MileSplit(
                        mile: currentMile,
                        paceMinutes: paceMinutes,
                        elapsedTime: mileEndMovingTime
                    ))

                    mileStartMovingTime = mileEndMovingTime
                    currentMile += 1
                    break
                }
            }
        }

        // Handle partial final mile
        if let lastDistance = distances.last {
            let completedDistance = Double(splits.count) * mileInMeters
            let remaining = lastDistance - completedDistance
            if remaining > 80 {
                let partialMiles = remaining / mileInMeters
                let totalMovingTime = movingTimeAt.last ?? 0
                let partialMovingTime = totalMovingTime - mileStartMovingTime
                let paceMinutes = partialMiles > 0 ? (partialMovingTime / 60.0) / partialMiles : 0

                splits.append(MileSplit(
                    mile: currentMile,
                    paceMinutes: paceMinutes,
                    elapsedTime: totalMovingTime,
                    isPartial: true,
                    partialDistance: partialMiles
                ))
            }
        }

        return splits
    }

    /// Detect interval segments from per-second velocity data.
    /// Classifies each second as "hard" or "easy" based on pace relative to the run's
    /// median pace, then groups consecutive seconds into segments.
    /// For steady runs this returns very few segments; for intervals it catches each rep + rest.
    func calculatePaceSplits(from stream: VitalWorkoutStream) -> [PaceSplit] {
        guard let distances = stream.distance, let times = stream.time,
              let velocities = stream.velocitySmooth,
              distances.count == times.count, velocities.count == times.count,
              distances.count >= 30
        else { return [] }

        let heartrates = stream.heartrate
        let startTime = times[0]
        let mileInMeters = 1609.34

        // 1. Smooth velocity over a 30-second window
        let windowSize = 30
        var smoothedVel: [Double] = Array(repeating: 0, count: velocities.count)
        for i in 0..<velocities.count {
            let lo = max(0, i - windowSize / 2)
            let hi = min(velocities.count - 1, i + windowSize / 2)
            let window = velocities[lo...hi]
            smoothedVel[i] = window.reduce(0, +) / Double(window.count)
        }

        // 2. Calculate median velocity (ignoring first/last 30s for warmup/cooldown)
        let trimStart = min(30, velocities.count / 4)
        let trimEnd = max(velocities.count - 30, velocities.count * 3 / 4)
        let trimmed = Array(smoothedVel[trimStart..<trimEnd]).sorted()
        let medianVel = trimmed[trimmed.count / 2]

        // 3. Classify each second: pace faster than median-10% = "hard", else "easy"
        //    A meaningful interval has at least 1 min/mile difference from easy pace
        let hardThresholdVel = medianVel * 1.08  // ~8% faster velocity = ~0.5 min/mi faster pace
        var isHard: [Bool] = smoothedVel.map { $0 >= hardThresholdVel }

        // 4. Debounce: remove flickers shorter than 15 seconds
        let debounce = 15
        var i = 0
        while i < isHard.count {
            let state = isHard[i]
            var j = i + 1
            while j < isHard.count && isHard[j] == state { j += 1 }
            let segLen = j - i
            if segLen < debounce && i > 0 && j < isHard.count {
                // Flip short segment to match surroundings
                for k in i..<j { isHard[k] = !state }
            }
            i = j
        }

        // 5. Build segments from consecutive same-state seconds
        struct Segment {
            var startIndex: Int
            var endIndex: Int
            var hard: Bool
        }

        var segments: [Segment] = []
        var segStart = 0
        for idx in 1..<isHard.count {
            if isHard[idx] != isHard[segStart] {
                segments.append(Segment(startIndex: segStart, endIndex: idx - 1, hard: isHard[segStart]))
                segStart = idx
            }
        }
        segments.append(Segment(startIndex: segStart, endIndex: isHard.count - 1, hard: isHard[segStart]))

        // 6. Merge segments shorter than 30 seconds into neighbors
        var merged: [Segment] = []
        for seg in segments {
            let dur = Double(times[seg.endIndex] - times[seg.startIndex])
            if dur < 30 && !merged.isEmpty {
                merged[merged.count - 1].endIndex = seg.endIndex
            } else {
                merged.append(seg)
            }
        }

        // If only 1-2 segments, this is a steady run — return empty (mile splits are better)
        if merged.count <= 2 { return [] }

        // 7. Convert to PaceSplit
        var paceSplits: [PaceSplit] = []
        for (index, seg) in merged.enumerated() {
            let segDuration = Double(times[seg.endIndex] - times[seg.startIndex])
            let segDistance = (distances[seg.endIndex] - distances[seg.startIndex]) / mileInMeters
            let elapsed = Double(times[seg.endIndex] - startTime)

            var avgHR: Int? = nil
            if let hrs = heartrates {
                let hrSlice = hrs[seg.startIndex...seg.endIndex]
                avgHR = hrSlice.reduce(0, +) / hrSlice.count
            }

            let pace = segDistance > 0.01 ? (segDuration / 60.0) / segDistance : 0

            paceSplits.append(PaceSplit(
                segment: index + 1,
                durationSeconds: segDuration,
                distanceMiles: segDistance,
                paceMinutes: pace,
                elapsedTime: elapsed,
                avgHeartRate: avgHR
            ))
        }

        return paceSplits
    }

    /// Extract GPS route from stream
    func extractRoute(from stream: VitalWorkoutStream) -> [CLLocation] {
        guard let lats = stream.lat, let lngs = stream.lng, let times = stream.time,
              lats.count == lngs.count, lats.count == times.count
        else { return [] }

        let altitudes = stream.altitude

        // Sample every 5th point to avoid overwhelming MapKit
        return stride(from: 0, to: lats.count, by: 5).compactMap { i in
            let lat = lats[i]
            let lng = lngs[i]
            guard lat != 0 && lng != 0 else { return nil }
            let coord = CLLocationCoordinate2D(latitude: lat, longitude: lng)
            let alt = altitudes?[safe: i] ?? 0
            let date = Date(timeIntervalSince1970: Double(times[i]))
            return CLLocation(
                coordinate: coord,
                altitude: alt,
                horizontalAccuracy: 5,
                verticalAccuracy: 5,
                timestamp: date
            )
        }
    }

    // MARK: - Network

    // NOTE: Vital integration stubbed out — trial ended 2026-04-14.
    // All network calls short-circuit to nil so upstream callers get empty results
    // without triggering 401s. HealthKit is the wearable source for V1.
    // Replacement (Terra) planned for V1.1 — restore this function to re-enable.
    private func vitalRequest(url _: String, timeout _: TimeInterval = 30) async -> Data? {
        return nil
    }

    private func vitalRequest_DISABLED(url urlString: String, timeout: TimeInterval = 30) async -> Data? {
        guard let url = URL(string: urlString) else {
            Log.health.error("Vital: invalid URL: \(urlString)")
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.setValue(apiKey, forHTTPHeaderField: "x-vital-api-key")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode != 200 {
                    Log.health.error("Vital API \(httpResponse.statusCode) for \(url.lastPathComponent): \(String(data: data.prefix(200), encoding: .utf8) ?? "")")
                    return nil
                }
                Log.health.info("Vital API OK: \(url.lastPathComponent) — \(data.count) bytes")
            }
            return data
        } catch is CancellationError {
            Log.health.info("Vital request cancelled: \(url.lastPathComponent)")
            return nil
        } catch {
            Log.health.error("Vital request failed: \(url.lastPathComponent) — \(error.localizedDescription)")
            return nil
        }
    }
}

// MARK: - Safe Array Subscript

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Vital API Response Models

struct VitalWorkoutsResponse: Decodable {
    let workouts: [VitalWorkoutSummary]
}

struct VitalWorkoutSummary: Decodable, Identifiable {
    let id: String
    let userId: String
    let title: String?
    let timezoneOffset: Int?
    let averageHr: Int?
    let maxHr: Int?
    let distance: Double?
    let calendarDate: String
    let timeStart: String
    let timeEnd: String
    let calories: Double?
    let sport: VitalSport?
    let hrZones: [Int]?
    let movingTime: Int?
    let totalElevationGain: Double?
    let elevHigh: Double?
    let elevLow: Double?
    let averageSpeed: Double?
    let maxSpeed: Double?
    let averageWatts: Double?
    let maxWatts: Double?
    let steps: Int?
    let providerId: String?
    let source: VitalSource?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case title
        case timezoneOffset = "timezone_offset"
        case averageHr = "average_hr"
        case maxHr = "max_hr"
        case distance
        case calendarDate = "calendar_date"
        case timeStart = "time_start"
        case timeEnd = "time_end"
        case calories
        case sport
        case hrZones = "hr_zones"
        case movingTime = "moving_time"
        case totalElevationGain = "total_elevation_gain"
        case elevHigh = "elev_high"
        case elevLow = "elev_low"
        case averageSpeed = "average_speed"
        case maxSpeed = "max_speed"
        case averageWatts = "average_watts"
        case maxWatts = "max_watts"
        case steps
        case providerId = "provider_id"
        case source
    }

    /// Convert to the existing RunningWorkout model for compatibility
    func toRunningWorkout() -> RunningWorkout {
        // Parse dates — try with fractional seconds first, then without
        let start = Self.parseISO8601(timeStart) ?? Date()
        let end = Self.parseISO8601(timeEnd) ?? Date()

        let distanceMeters = distance ?? 0
        let distanceMiles = distanceMeters / 1609.34

        // Use movingTime from API directly (seconds) — more reliable than computing from dates
        let durationSeconds = Double(movingTime ?? Int(end.timeIntervalSince(start)))
        let durationMinutes = durationSeconds / 60.0
        let pace = distanceMiles > 0 ? durationMinutes / distanceMiles : 0

        return RunningWorkout(
            id: UUID(uuidString: id) ?? UUID(),
            startDate: start,
            endDate: end,
            distanceMiles: distanceMiles,
            durationMinutes: durationMinutes,
            pacePerMile: pace,
            calories: calories ?? 0,
            sourceApp: source?.name ?? "Garmin",
            vitalWorkoutId: id
        )
    }

    private static func parseISO8601(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}

struct VitalSport: Decodable {
    let id: Int
    let name: String
    let slug: String
}

struct VitalSource: Decodable {
    let provider: String?
    let type: String?
    let appId: String?
    let name: String
    let slug: String

    enum CodingKeys: String, CodingKey {
        case provider, type
        case appId = "app_id"
        case name, slug
    }
}

// MARK: - Workout Stream

struct VitalWorkoutStream: Decodable {
    let time: [Int]?
    let heartrate: [Int]?
    let lat: [Double]?
    let lng: [Double]?
    let altitude: [Double]?
    let distance: [Double]?
    let velocitySmooth: [Double]?
    let cadence: [Double]?
    /// Ambient temperature in °C (Strava `temp` stream). No HealthKit equivalent.
    let temp: [Double]?
    /// Raw power may contain nulls from Garmin
    private let rawPower: [Double?]?

    /// Power with nulls stripped out (replaced with 0)
    var power: [Double]? {
        rawPower?.map { $0 ?? 0 }
    }

    enum CodingKeys: String, CodingKey {
        case time, heartrate, lat, lng, altitude, distance
        case velocitySmooth = "velocity_smooth"
        case cadence
        case temp
        case rawPower = "power"
    }

    /// Memberwise init so non-Vital sources (Strava via ExternalStreamAdapter, etc.)
    /// can construct this struct directly instead of going through JSON decode.
    /// `temp` defaults to nil so existing callers that predate temperature
    /// support keep compiling.
    init(
        time: [Int]?,
        heartrate: [Int]?,
        lat: [Double]?,
        lng: [Double]?,
        altitude: [Double]?,
        distance: [Double]?,
        velocitySmooth: [Double]?,
        cadence: [Double]?,
        temp: [Double]? = nil,
        rawPower: [Double?]?
    ) {
        self.time = time
        self.heartrate = heartrate
        self.lat = lat
        self.lng = lng
        self.altitude = altitude
        self.distance = distance
        self.velocitySmooth = velocitySmooth
        self.cadence = cadence
        self.temp = temp
        self.rawPower = rawPower
    }
}

// MARK: - WorkoutDataSource Conformance

extension VitalManager: WorkoutDataSource {
    func fetchRunningWorkouts(startDate: Date, endDate: Date) async -> [RunningWorkout] {
        let summaries = await fetchVitalSummaries(startDate: startDate, endDate: endDate)
        return summaries.map { $0.toRunningWorkout() }
    }

    func fetchRunningMilesByDate(startDate: Date, endDate: Date) async -> [String: Double] {
        await fetchRunningMilesByDate(from: startDate, to: endDate)
    }
}

import Combine
import CoreLocation
import Foundation
import HealthKit
import os
import SwiftUI

// MARK: - HealthKitManager

class HealthKitManager: ObservableObject {
    static let shared = HealthKitManager()

    let healthStore = HKHealthStore()

    @Published var isAuthorized = false
    @Published var recentWorkouts: [RunningWorkout] = []

    /// How much we can actually SEE — honestly. HealthKit hides read-denial
    /// by design: `requestAuthorization` returns success on "Don't Allow"
    /// too, and queries for read-denied types return EMPTY results with NO
    /// error. So the app can never know "denied" for certain. What it CAN
    /// know is (a) whether the permission sheet has ever been handled
    /// (`statusForAuthorizationRequest` — reliable) and (b) whether any
    /// probe data is visible afterwards. UI copy must stay honest to that:
    /// "no data visible" + how to fix — never a false "CONNECTED ✓".
    /// (Beta-audit item #7: denying Health used to show CONNECTED and an
    /// empty app forever, with no explanation.)
    enum HealthReadState: Equatable {
        case unknown        // not evaluated yet this launch
        case unavailable    // device has no Health data (e.g. iPad)
        case notDetermined  // permission sheet never handled
        case visibleData    // probe found data — reads definitely work
        case noVisibleData  // sheet handled but nothing visible: denied OR truly empty
    }

    @Published var readState: HealthReadState = .unknown

    /// Types we want to read from HealthKit
    private var typesToRead: Set<HKObjectType> {
        var types: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute()
        ]
        if let heartRate = HKQuantityType.quantityType(forIdentifier: .heartRate) {
            types.insert(heartRate)
        }
        if let distance = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning) {
            types.insert(distance)
        }
        if let energy = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
            types.insert(energy)
        }
        // Steps: the denial probe. Virtually every iPhone records steps by
        // itself, so a runner with zero workouts still probes `visibleData`
        // after granting — which is what lets us tell "granted but no runs
        // yet" apart from "denied everything" in the common case.
        if let steps = HKQuantityType.quantityType(forIdentifier: .stepCount) {
            types.insert(steps)
        }
        // Overnight recovery trio, read by `HealthBiometricsSync` and pushed to
        // `daily_biometrics` (source 'healthkit'). Watch-only in practice — a
        // phone-only athlete grants these and simply has no samples, which the
        // sync reports honestly rather than fabricating.
        //
        // NOTE: `.heartRateVariabilitySDNN` is Apple's ONLY HRV type, and SDNN
        // is not the RMSSD that Garmin-via-Junction reports. They must never be
        // pooled — see the header of `ingest-biometrics/index.ts`.
        if let hrv = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) {
            types.insert(hrv)
        }
        if let restingHR = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) {
            types.insert(restingHR)
        }
        if let sleep = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleep)
        }
        return types
    }

    /// Re-evaluate what we can see. Sets `readState` (the honest probe) and
    /// `isAuthorized` (= the permission sheet has been handled and queries
    /// are safe to run — NOT a guarantee that data is visible).
    func checkAuthorizationStatus() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            await MainActor.run {
                isAuthorized = false
                readState = .unavailable
            }
            return
        }

        // "Never asked" vs "asked" — this API is reliable, unlike read
        // authorization status (which HealthKit deliberately hides).
        // NOTE: it reports .shouldRequest whenever ANY type in the set was
        // never requested — including for EXISTING users after we add a new
        // type (like stepCount). So probe first: if data is already visible,
        // the user granted the core types long ago and must stay authorized;
        // only an empty probe + .shouldRequest means a genuinely fresh user.
        let visible = await probeAnyVisibleData()
        if visible {
            await MainActor.run {
                isAuthorized = true
                readState = .visibleData
            }
            return
        }

        let requestStatus = (try? await healthStore.statusForAuthorizationRequest(
            toShare: [], read: typesToRead
        )) ?? .unknown

        if requestStatus == .shouldRequest {
            await MainActor.run {
                isAuthorized = false
                readState = .notDetermined
            }
            return
        }

        await MainActor.run {
            isAuthorized = true
            readState = .noVisibleData
        }
    }

    /// True if ANY probe data is visible: any workout (any activity type),
    /// otherwise any step sample in the last 30 days.
    private func probeAnyVisibleData() async -> Bool {
        if await sampleExists(HKObjectType.workoutType(), predicate: nil) {
            return true
        }
        if let steps = HKQuantityType.quantityType(forIdentifier: .stepCount) {
            let from = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
            let predicate = HKQuery.predicateForSamples(withStart: from, end: nil)
            return await sampleExists(steps, predicate: predicate)
        }
        return false
    }

    private func sampleExists(_ type: HKSampleType, predicate: NSPredicate?) async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: 1,
                sortDescriptors: nil
            ) { _, samples, _ in
                continuation.resume(returning: (samples?.isEmpty == false))
            }
            healthStore.execute(query)
        }
    }

    /// Bump whenever `typesToRead` GAINS a type.
    /// v2 (2026-08-06): added sleepAnalysis + restingHeartRate + HRV SDNN.
    private static let readTypesVersion = 2
    private static let readTypesVersionKey = "healthKitReadTypesVersion"

    /// Re-present the permission sheet once after `typesToRead` grows.
    ///
    /// Necessary because `checkAuthorizationStatus()` probes for visible data
    /// FIRST and returns `.visibleData` early — deliberately, so that adding a
    /// type doesn't demote an existing user to "not authorized". The side
    /// effect is that an existing user is never re-asked, so a newly added
    /// type stays permanently unrequested and its queries return empty with no
    /// error. That is indistinguishable from "this athlete has no watch", and
    /// it is exactly how a recovery feature ships to zero users and looks fine.
    ///
    /// HealthKit only lists types the user hasn't handled yet, so an existing
    /// athlete sees a short sheet (Sleep, Resting HR, HRV) and someone who has
    /// already handled them sees nothing at all.
    ///
    /// Deliberately does nothing when the FIRST sheet was never handled —
    /// onboarding owns that moment and shouldn't be pre-empted on launch.
    func ensureAuthorizationCoversCurrentTypes() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let defaults = UserDefaults.standard
        guard defaults.integer(forKey: Self.readTypesVersionKey) < Self.readTypesVersion else { return }
        if readState == .unknown { await checkAuthorizationStatus() }
        guard readState != .notDetermined, readState != .unavailable else { return }

        do {
            try await healthStore.requestAuthorization(toShare: [], read: typesToRead)
            defaults.set(Self.readTypesVersion, forKey: Self.readTypesVersionKey)
            await checkAuthorizationStatus()
        } catch {
            // Leave the version unset so the next launch retries.
            Log.health.error("HealthKit re-authorization failed: \(error.localizedDescription)")
        }
    }

    func requestAuthorization() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else {
            Log.health.warning("HealthKit not available on this device")
            await MainActor.run {
                readState = .unavailable
                ErrorReporter.shared.report(.healthKit("HealthKit is not available on this device."))
            }
            return false
        }

        do {
            try await healthStore.requestAuthorization(toShare: [], read: typesToRead)
            // The sheet has now covered the current type set — record it so
            // `ensureAuthorizationCoversCurrentTypes` doesn't ask again.
            UserDefaults.standard.set(Self.readTypesVersion, forKey: Self.readTypesVersionKey)
            // A non-throwing return does NOT mean granted — HealthKit
            // reports success on "Don't Allow" too. Probe what's actually
            // visible instead of assuming.
            await checkAuthorizationStatus()
            return await MainActor.run { isAuthorized }
        } catch {
            Log.health.error("HealthKit authorization failed: \(error)")
            await MainActor.run { ErrorReporter.shared.report(.healthKit("HealthKit access was denied. Enable it in Settings > Privacy > Health.")) }
            return false
        }
    }

    func fetchRecentRunningWorkouts(limit: Int = 10) async -> [RunningWorkout] {
        // Re-check authorization before fetching — catches revocation in Settings
        await checkAuthorizationStatus()
        guard isAuthorized else {
            Log.health.warning("HealthKit not authorized — skipping workout fetch")
            await MainActor.run { ErrorReporter.shared.report(.healthKit("Cannot read workouts. HealthKit access is not authorized.")) }
            return []
        }

        let workoutType = HKObjectType.workoutType()

        // Only fetch running workouts
        let runningPredicate = HKQuery.predicateForWorkouts(with: .running)

        // Sort by start date, most recent first
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: workoutType,
                predicate: runningPredicate,
                limit: limit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                guard let workouts = samples as? [HKWorkout], error == nil else {
                    Log.health.error("Failed to fetch workouts: \(error?.localizedDescription ?? "Unknown error")")
                    continuation.resume(returning: [])
                    return
                }

                let runningWorkouts = workouts.map { workout -> RunningWorkout in
                    // Get distance in miles
                    let distanceInMeters = workout.totalDistance?.doubleValue(for: .meter()) ?? 0
                    let distanceInMiles = distanceInMeters / 1609.34

                    // Get duration in minutes
                    let durationInMinutes = workout.duration / 60

                    // Calculate pace (minutes per mile)
                    let pacePerMile = distanceInMiles > 0 ? durationInMinutes / distanceInMiles : 0

                    // Get calories using statistics API (iOS 18+)
                    let caloriesType = HKQuantityType(.activeEnergyBurned)
                    let calories = workout.statistics(for: caloriesType)?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0

                    return RunningWorkout(
                        id: workout.uuid,
                        startDate: workout.startDate,
                        endDate: workout.endDate,
                        distanceMiles: distanceInMiles,
                        durationMinutes: durationInMinutes,
                        pacePerMile: pacePerMile,
                        calories: calories,
                        sourceApp: workout.sourceRevision.source.name
                    )
                }

                continuation.resume(returning: runningWorkouts)
            }

            healthStore.execute(query)
        }
    }

    /// Fetch running workouts within a date range, returning per-day total miles
    func fetchRunningMilesByDate(from startDate: Date, to endDate: Date) async -> [String: Double] {
        await checkAuthorizationStatus()
        guard isAuthorized else {
            Log.health.warning("HealthKit not authorized — skipping miles fetch")
            return [:]
        }

        let workoutType = HKObjectType.workoutType()
        let runningPredicate = HKQuery.predicateForWorkouts(with: .running)
        let datePredicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        let compound = NSCompoundPredicate(andPredicateWithSubpredicates: [runningPredicate, datePredicate])
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: workoutType,
                predicate: compound,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                guard let workouts = samples as? [HKWorkout], error == nil else {
                    continuation.resume(returning: [:])
                    return
                }

                var milesByDate: [String: Double] = [:]
                for workout in workouts {
                    let miles = (workout.totalDistance?.doubleValue(for: .meter()) ?? 0) / 1609.34
                    if miles > 0 {
                        let key = formatter.string(from: workout.startDate)
                        milesByDate[key, default: 0] += miles
                    }
                }
                continuation.resume(returning: milesByDate)
            }

            healthStore.execute(query)
        }
    }

    /// Fetch individual running workouts for a specific day
    func fetchRunningWorkouts(for date: Date) async -> [RunningWorkout] {
        await checkAuthorizationStatus()
        guard isAuthorized else { return [] }

        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return [] }

        let workoutType = HKObjectType.workoutType()
        let runningPredicate = HKQuery.predicateForWorkouts(with: .running)
        let datePredicate = HKQuery.predicateForSamples(withStart: dayStart, end: dayEnd, options: .strictStartDate)
        let compound = NSCompoundPredicate(andPredicateWithSubpredicates: [runningPredicate, datePredicate])
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: workoutType,
                predicate: compound,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                guard let workouts = samples as? [HKWorkout], error == nil else {
                    continuation.resume(returning: [])
                    return
                }

                let results = workouts.map { workout -> RunningWorkout in
                    let distanceInMeters = workout.totalDistance?.doubleValue(for: .meter()) ?? 0
                    let distanceInMiles = distanceInMeters / 1609.34
                    let durationInMinutes = workout.duration / 60
                    let pacePerMile = distanceInMiles > 0 ? durationInMinutes / distanceInMiles : 0
                    let caloriesType = HKQuantityType(.activeEnergyBurned)
                    let calories = workout.statistics(for: caloriesType)?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0

                    return RunningWorkout(
                        id: workout.uuid,
                        startDate: workout.startDate,
                        endDate: workout.endDate,
                        distanceMiles: distanceInMiles,
                        durationMinutes: durationInMinutes,
                        pacePerMile: pacePerMile,
                        calories: calories,
                        sourceApp: workout.sourceRevision.source.name
                    )
                }
                continuation.resume(returning: results)
            }

            healthStore.execute(query)
        }
    }

    func fetchWorkoutHeartRate(for workout: HKWorkout) async -> (average: Double, max: Double)? {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return nil }

        let predicate = HKQuery.predicateForSamples(
            withStart: workout.startDate,
            end: workout.endDate,
            options: .strictStartDate
        )

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: heartRateType,
                quantitySamplePredicate: predicate,
                options: [.discreteAverage, .discreteMax]
            ) { _, statistics, error in
                guard let stats = statistics, error == nil else {
                    continuation.resume(returning: nil)
                    return
                }

                let avgHR = stats.averageQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute())) ?? 0
                let maxHR = stats.maximumQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute())) ?? 0

                continuation.resume(returning: (average: avgHR, max: maxHR))
            }

            healthStore.execute(query)
        }
    }

    func fetchHeartRateSamples(for workout: HKWorkout) async -> [HeartRateSample] {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return [] }

        let predicate = HKQuery.predicateForSamples(
            withStart: workout.startDate,
            end: workout.endDate,
            options: .strictStartDate
        )

        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: heartRateType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                guard let samples = samples as? [HKQuantitySample], error == nil else {
                    continuation.resume(returning: [])
                    return
                }

                let hrSamples = samples.map { sample -> HeartRateSample in
                    let bpm = sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                    let elapsed = sample.startDate.timeIntervalSince(workout.startDate)
                    return HeartRateSample(timestamp: elapsed, bpm: bpm)
                }

                continuation.resume(returning: hrSamples)
            }

            healthStore.execute(query)
        }
    }

    /// Assembles an `ExternalStreamsPayload` for a HealthKit workout from its
    /// heart-rate samples and GPS route, in the same shape the workout-detail
    /// charts read (`ExternalStreamAdapter`). WorkoutSyncService calls this so
    /// newly-synced runs persist their telemetry. Returns nil when neither HR
    /// nor route data exists (e.g. a manually-entered HealthKit workout).
    func buildExternalStreams(for workout: HKWorkout, calories: Double) async -> ExternalStreamsPayload? {
        async let hrTask = fetchHeartRateSamples(for: workout)
        async let routeTask = fetchWorkoutRoute(for: workout)
        let hrSamples = await hrTask
        let route = await routeTask

        let start = workout.startDate
        let deviceName = workout.sourceRevision.source.name

        // HR meta from the raw samples, independent of which spine we use.
        let hrValues = hrSamples.map(\.bpm)
        let avgHr = hrValues.isEmpty ? nil : Int((hrValues.reduce(0, +) / Double(hrValues.count)).rounded())
        let maxHr = hrValues.max().map { Int($0.rounded()) }

        // Preferred spine: the GPS route (≈1 Hz), which gives time, lat/lng,
        // altitude and cumulative distance; HR is aligned onto it by timestamp.
        if !route.isEmpty {
            var time: [Int] = []
            var lat: [Double] = []
            var lng: [Double] = []
            var altitude: [Double] = []
            var distance: [Double] = []
            var velocity: [Double] = []
            var elevationGain = 0.0
            var cumulativeDistance = 0.0
            var previous: CLLocation?

            for loc in route {
                let elapsed = max(0, loc.timestamp.timeIntervalSince(start))
                if let prev = previous {
                    let step = loc.distance(from: prev)
                    cumulativeDistance += step
                    let dt = loc.timestamp.timeIntervalSince(prev.timestamp)
                    velocity.append(dt > 0 ? step / dt : 0)
                    let climb = loc.altitude - prev.altitude
                    if climb > 0 { elevationGain += climb }
                } else {
                    velocity.append(0)
                }
                time.append(Int(elapsed.rounded()))
                lat.append(loc.coordinate.latitude)
                lng.append(loc.coordinate.longitude)
                altitude.append(loc.altitude)
                distance.append(cumulativeDistance)
                previous = loc
            }

            let alignedHr = Self.alignHeartRate(toTimes: time, samples: hrSamples)
            let streams = ExternalStreamsPayload.Streams(
                time: time,
                heartrate: alignedHr.isEmpty ? nil : alignedHr,
                altitude: altitude,
                distance: distance,
                velocitySmooth: velocity,
                cadence: nil,
                latlng: zip(lat, lng).map { [$0, $1] }
            )
            let meta = ExternalStreamsPayload.Meta(
                averageHeartrate: avgHr,
                maxHeartrate: maxHr,
                totalElevationGain: elevationGain,
                calories: calories,
                deviceName: deviceName
            )
            let payload = ExternalStreamsPayload(streams: streams, meta: meta)
            return payload.hasUsableData ? payload : nil
        }

        // No route (treadmill / indoor): an HR-only spine still powers the
        // heart-rate chart and the time-in-zone histogram.
        if !hrSamples.isEmpty {
            let streams = ExternalStreamsPayload.Streams(
                time: hrSamples.map { Int($0.timestamp.rounded()) },
                heartrate: hrSamples.map { Int($0.bpm.rounded()) },
                altitude: nil,
                distance: nil,
                velocitySmooth: nil,
                cadence: nil,
                latlng: nil
            )
            let meta = ExternalStreamsPayload.Meta(
                averageHeartrate: avgHr,
                maxHeartrate: maxHr,
                totalElevationGain: nil,
                calories: calories,
                deviceName: deviceName
            )
            return ExternalStreamsPayload(streams: streams, meta: meta)
        }

        return nil
    }

    /// Nearest-timestamp alignment of HR samples onto a target time spine.
    /// Both inputs are ascending (route is time-sorted; HR samples are
    /// fetched sorted ascending), so a single forward walk is O(n + m).
    private static func alignHeartRate(toTimes times: [Int], samples: [HeartRateSample]) -> [Int] {
        guard !samples.isEmpty else { return [] }
        var result: [Int] = []
        result.reserveCapacity(times.count)
        var j = 0
        for t in times {
            let target = Double(t)
            while j + 1 < samples.count,
                  abs(samples[j + 1].timestamp - target) <= abs(samples[j].timestamp - target) {
                j += 1
            }
            result.append(Int(samples[j].bpm.rounded()))
        }
        return result
    }

    func fetchWorkoutWithUUID(_ uuid: UUID) async -> HKWorkout? {
        let workoutType = HKObjectType.workoutType()
        let predicate = HKQuery.predicateForObject(with: uuid)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: workoutType,
                predicate: predicate,
                limit: 1,
                sortDescriptors: nil
            ) { _, samples, _ in
                continuation.resume(returning: samples?.first as? HKWorkout)
            }

            healthStore.execute(query)
        }
    }

    /// Fetches workout route (GPS coordinates) if available
    func fetchWorkoutRoute(for workout: HKWorkout) async -> [CLLocation] {
        // First, get the route samples associated with this workout
        let routeType = HKSeriesType.workoutRoute()
        let predicate = HKQuery.predicateForObjects(from: workout)

        return await withCheckedContinuation { continuation in
            let routeQuery = HKAnchoredObjectQuery(
                type: routeType,
                predicate: predicate,
                anchor: nil,
                limit: HKObjectQueryNoLimit
            ) { _, samples, _, _, error in
                guard let routes = samples as? [HKWorkoutRoute], let route = routes.first, error == nil else {
                    Log.health.debug("No route data available: \(error?.localizedDescription ?? "Unknown error")")
                    continuation.resume(returning: [])
                    return
                }

                // Now extract the CLLocation points from the route
                var locations: [CLLocation] = []

                let locationQuery = HKWorkoutRouteQuery(route: route) { _, locationResults, done, error in
                    if let error {
                        Log.health.error("Route location query error: \(error.localizedDescription)")
                        if done {
                            continuation.resume(returning: RouteSanitizer.clean(locations))
                        }
                        return
                    }

                    if let locationResults {
                        locations.append(contentsOf: locationResults)
                    }

                    if done {
                        let cleaned = RouteSanitizer.clean(locations)
                        Log.health.info("Fetched \(locations.count) GPS points from workout route (\(cleaned.count) after cleaning)")
                        continuation.resume(returning: cleaned)
                    }
                }

                self.healthStore.execute(locationQuery)
            }

            healthStore.execute(routeQuery)
        }
    }

    /// Calculate mile splits from GPS coordinates (more accurate than distance samples)
    func calculateSplitsFromGPS(_ locations: [CLLocation], workoutStart: Date) -> [MileSplit] {
        guard locations.count >= 2 else { return [] }

        var splits: [MileSplit] = []
        let mileInMeters = 1609.34

        var accumulatedDistance: Double = 0
        var mileStartIndex = 0
        var currentMile = 1

        for i in 1 ..< locations.count {
            let prevLocation = locations[i - 1]
            let currLocation = locations[i]

            // Calculate distance between consecutive GPS points
            let segmentDistance = currLocation.distance(from: prevLocation)
            accumulatedDistance += segmentDistance

            // Check if we've completed a mile
            while accumulatedDistance >= mileInMeters {
                // Interpolate the exact time when the mile was completed
                let overshoot = accumulatedDistance - mileInMeters
                let segmentFraction = 1.0 - (overshoot / segmentDistance)

                // Interpolate timestamp
                let timeDiff = currLocation.timestamp.timeIntervalSince(prevLocation.timestamp)
                let mileEndTime = prevLocation.timestamp.addingTimeInterval(timeDiff * segmentFraction)

                // Calculate pace for this mile
                let mileStartTime = locations[mileStartIndex].timestamp
                let mileTime = mileEndTime.timeIntervalSince(mileStartTime)
                let paceMinutesPerMile = mileTime / 60.0

                splits.append(MileSplit(
                    mile: currentMile,
                    paceMinutes: paceMinutesPerMile,
                    elapsedTime: mileEndTime.timeIntervalSince(workoutStart)
                ))

                // Prepare for next mile
                accumulatedDistance -= mileInMeters
                mileStartIndex = i
                currentMile += 1
            }
        }

        // Handle partial final mile
        if accumulatedDistance > 80, let lastLocation = locations.last { // Only show if > 80 meters remaining
            let partialDistanceMiles = accumulatedDistance / mileInMeters
            let mileStartTime = locations[mileStartIndex].timestamp
            let partialTime = lastLocation.timestamp.timeIntervalSince(mileStartTime)
            let paceMinutesPerMile = (partialTime / 60.0) / partialDistanceMiles

            splits.append(MileSplit(
                mile: currentMile,
                paceMinutes: paceMinutesPerMile,
                elapsedTime: lastLocation.timestamp.timeIntervalSince(workoutStart),
                isPartial: true,
                partialDistance: partialDistanceMiles
            ))
        }

        return splits
    }

    /// Fetches real mile splits - tries GPS route first, falls back to distance samples
    func fetchWorkoutSplits(for workout: HKWorkout) async -> [MileSplit] {
        // Try GPS-based splits first (more accurate)
        let routeLocations = await fetchWorkoutRoute(for: workout)
        if !routeLocations.isEmpty {
            let gpsSplits = calculateSplitsFromGPS(routeLocations, workoutStart: workout.startDate)
            if !gpsSplits.isEmpty {
                Log.health.info("Using GPS-based splits (\(gpsSplits.count) splits from \(routeLocations.count) GPS points)")
                return gpsSplits
            }
        }

        // Fallback to distance sample interpolation
        Log.health.debug("Falling back to distance sample interpolation")
        guard let distanceType = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning) else { return [] }

        let predicate = HKQuery.predicateForSamples(
            withStart: workout.startDate,
            end: workout.endDate,
            options: .strictStartDate
        )

        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: distanceType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                guard let samples = samples as? [HKQuantitySample], error == nil, !samples.isEmpty else {
                    Log.health.warning("No distance samples found")
                    continuation.resume(returning: [])
                    return
                }

                // DEBUG: Log sample details
                Log.health.debug("Found \(samples.count) distance samples from source: \(samples.first?.sourceRevision.source.name ?? "unknown")")
                for (index, sample) in samples.prefix(5).enumerated() {
                    let distance = sample.quantity.doubleValue(for: .meter())
                    let duration = sample.endDate.timeIntervalSince(sample.startDate)
                    Log.health.debug("  Sample \(index + 1): \(String(format: "%.1f", distance))m over \(String(format: "%.1f", duration))s")
                }
                if samples.count > 5 {
                    Log.health.debug("  ... and \(samples.count - 5) more samples")
                }

                // Build cumulative distance/time arrays for interpolation
                var cumulativePoints: [(distance: Double, time: TimeInterval)] = [(0, 0)]

                for sample in samples {
                    let sampleDistance = sample.quantity.doubleValue(for: .meter())
                    let sampleTime = sample.endDate.timeIntervalSince(workout.startDate)
                    let lastDistance = cumulativePoints.last?.distance ?? 0
                    cumulativePoints.append((lastDistance + sampleDistance, sampleTime))
                }

                Log.health.debug("Total cumulative distance: \(String(format: "%.1f", cumulativePoints.last?.distance ?? 0))m")

                // Calculate splits by interpolating mile completion times
                var splits: [MileSplit] = []
                let mileInMeters = 1609.34
                let totalDistance = cumulativePoints.last?.distance ?? 0
                let totalMiles = Int(totalDistance / mileInMeters)

                for mile in 1 ... max(totalMiles, 1) {
                    let targetDistance = Double(mile) * mileInMeters
                    let prevTargetDistance = Double(mile - 1) * mileInMeters

                    // Skip if we haven't reached this mile
                    if targetDistance > totalDistance {
                        break
                    }

                    // Find the time when this mile was completed (interpolate)
                    let mileEndTime = Self.interpolateTime(
                        forDistance: targetDistance,
                        in: cumulativePoints
                    )
                    let mileStartTime = Self.interpolateTime(
                        forDistance: prevTargetDistance,
                        in: cumulativePoints
                    )

                    let mileTime = mileEndTime - mileStartTime
                    let paceMinutesPerMile = mileTime / 60.0

                    splits.append(MileSplit(
                        mile: mile,
                        paceMinutes: paceMinutesPerMile,
                        elapsedTime: mileEndTime
                    ))
                }

                // Handle partial final mile
                let completedDistance = Double(totalMiles) * mileInMeters
                let remainingDistance = totalDistance - completedDistance

                if remainingDistance > 80 { // Only show if > 80 meters (0.05 mi) remaining
                    let partialDistanceMiles = remainingDistance / mileInMeters
                    let totalTime = cumulativePoints.last?.time ?? 0
                    let partialStartTime = splits.last?.elapsedTime ?? 0
                    let partialTime = totalTime - partialStartTime
                    let paceMinutesPerMile = (partialTime / 60.0) / partialDistanceMiles

                    splits.append(MileSplit(
                        mile: totalMiles + 1,
                        paceMinutes: paceMinutesPerMile,
                        elapsedTime: totalTime,
                        isPartial: true,
                        partialDistance: partialDistanceMiles
                    ))
                }

                continuation.resume(returning: splits)
            }

            healthStore.execute(query)
        }
    }

    /// Interpolate the time at which a specific distance was reached
    private static func interpolateTime(
        forDistance targetDistance: Double,
        in points: [(distance: Double, time: TimeInterval)]
    ) -> TimeInterval {
        // Find the two points that bracket the target distance
        for i in 1 ..< points.count {
            let prev = points[i - 1]
            let curr = points[i]

            if curr.distance >= targetDistance {
                // Linear interpolation
                let distanceRange = curr.distance - prev.distance
                if distanceRange <= 0 {
                    return curr.time
                }

                let fraction = (targetDistance - prev.distance) / distanceRange
                let timeRange = curr.time - prev.time
                return prev.time + (fraction * timeRange)
            }
        }

        // If we get here, return the last time
        return points.last?.time ?? 0
    }
}

// MARK: - MileSplit

struct MileSplit: Identifiable {
    let id = UUID()
    let mile: Int
    let paceMinutes: Double // minutes per mile
    let elapsedTime: TimeInterval // seconds from workout start
    var isPartial: Bool = false
    var partialDistance: Double = 1.0 // fraction of a mile (1.0 = full mile)
    var avgHeartRate: Int? = nil
    var avgCadence: Int? = nil

    var formattedPace: String {
        let totalSeconds = Int((paceMinutes * 60).rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var formattedElapsedTime: String {
        let totalMinutes = Int(elapsedTime) / 60
        let seconds = Int(elapsedTime) % 60
        if totalMinutes >= 60 {
            let hours = totalMinutes / 60
            let mins = totalMinutes % 60
            return String(format: "%d:%02d:%02d", hours, mins, seconds)
        }
        return String(format: "%d:%02d", totalMinutes, seconds)
    }

    /// Time it took to run this split (for a full mile = pace; for partial it's scaled)
    var formattedSplitTime: String {
        let splitSeconds = Int((paceMinutes * 60 * (isPartial ? partialDistance : 1.0)).rounded())
        let minutes = splitSeconds / 60
        let seconds = splitSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - PaceSplit (Garmin-style interval split)

struct PaceSplit: Identifiable {
    let id = UUID()
    let segment: Int
    let durationSeconds: Double
    let distanceMiles: Double
    let paceMinutes: Double // minutes per mile
    let elapsedTime: TimeInterval // seconds from workout start
    let avgHeartRate: Int?

    var formattedPace: String {
        let totalSeconds = Int((paceMinutes * 60).rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var formattedDuration: String {
        let totalSecs = Int(durationSeconds)
        let mins = totalSecs / 60
        let secs = totalSecs % 60
        if mins >= 60 {
            let hours = mins / 60
            let remMins = mins % 60
            return String(format: "%d:%02d:%02d", hours, remMins, secs)
        }
        return String(format: "%d:%02d", mins, secs)
    }

    var formattedDistance: String {
        String(format: "%.2f mi", distanceMiles)
    }

    var formattedElapsedTime: String {
        let totalMinutes = Int(elapsedTime) / 60
        let seconds = Int(elapsedTime) % 60
        if totalMinutes >= 60 {
            let hours = totalMinutes / 60
            let mins = totalMinutes % 60
            return String(format: "%d:%02d:%02d", hours, mins, seconds)
        }
        return String(format: "%d:%02d", totalMinutes, seconds)
    }
}

// MARK: - HeartRateSample

struct HeartRateSample: Identifiable {
    let id = UUID()
    let timestamp: TimeInterval // seconds from start
    let bpm: Double
}

// MARK: - RunningWorkout

struct RunningWorkout: Identifiable, Codable {
    let id: UUID
    let startDate: Date
    let endDate: Date
    let distanceMiles: Double
    let durationMinutes: Double
    let pacePerMile: Double
    let calories: Double
    let sourceApp: String
    var vitalWorkoutId: String?

    var formattedDistance: String {
        String(format: "%.2f mi", distanceMiles)
    }

    var formattedDuration: String {
        let totalSeconds = Int((durationMinutes * 60).rounded())
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }

    var formattedPace: String {
        let totalSeconds = Int((pacePerMile * 60).rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d /mi", minutes, seconds)
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: startDate)
    }
}

// MARK: - HealthKit Auth Banner

struct HealthKitAuthBanner: View {
    @ObservedObject var healthKitManager: HealthKitManager

    var body: some View {
        if !healthKitManager.isAuthorized {
            HStack(spacing: 8) {
                Image(systemName: "heart.slash")
                    .foregroundStyle(.red)
                Text("HealthKit access revoked. Tap to re-enable in Settings.")
                    .font(.caption)
                Spacer()
            }
            .padding(12)
            .background(.red.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .onTapGesture {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        }
    }
}

// MARK: - WorkoutDataSource Conformance

extension HealthKitManager: WorkoutDataSource {
    func fetchRunningWorkouts(startDate: Date, endDate: Date) async -> [RunningWorkout] {
        await checkAuthorizationStatus()
        guard isAuthorized else { return [] }

        let workoutType = HKObjectType.workoutType()
        let runningPredicate = HKQuery.predicateForWorkouts(with: .running)
        let datePredicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        let compound = NSCompoundPredicate(andPredicateWithSubpredicates: [runningPredicate, datePredicate])
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: workoutType,
                predicate: compound,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                guard let workouts = samples as? [HKWorkout], error == nil else {
                    continuation.resume(returning: [])
                    return
                }

                let result = workouts.map { workout -> RunningWorkout in
                    let distanceInMiles = (workout.totalDistance?.doubleValue(for: .meter()) ?? 0) / 1609.34
                    let durationInMinutes = workout.duration / 60
                    let pacePerMile = distanceInMiles > 0 ? durationInMinutes / distanceInMiles : 0
                    let caloriesType = HKQuantityType(.activeEnergyBurned)
                    let calories = workout.statistics(for: caloriesType)?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0

                    return RunningWorkout(
                        id: workout.uuid,
                        startDate: workout.startDate,
                        endDate: workout.endDate,
                        distanceMiles: distanceInMiles,
                        durationMinutes: durationInMinutes,
                        pacePerMile: pacePerMile,
                        calories: calories,
                        sourceApp: workout.sourceRevision.source.name
                    )
                }
                continuation.resume(returning: result)
            }
            healthStore.execute(query)
        }
    }

    func fetchRunningMilesByDate(startDate: Date, endDate: Date) async -> [String: Double] {
        await fetchRunningMilesByDate(from: startDate, to: endDate)
    }
}

// MARK: - Display formatting (moved from WorkoutDetailSheet.swift, 2026-07-03)

extension RunningWorkout {
    var dayOfWeek: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: startDate)
    }

    var shortDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter.string(from: startDate)
    }
}

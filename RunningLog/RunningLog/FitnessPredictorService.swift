//
//  FitnessPredictorService.swift
//  RunningLog
//
//  Service for AI-powered race predictions.
//

import Foundation
import HealthKit
import os
import Supabase

// MARK: - Models

struct FitnessPrediction {
    let races: [RacePredictionItem]
    let fitnessSummary: String?
    let dataSources: DataSources
}

struct RacePredictionItem: Identifiable {
    let id = UUID()
    let distance: String   // "5K", "10K", "HALF", "MARATHON"
    let time: String       // "19:45", "1:32:10"
    let pace: String       // "6:22/mi"
}

struct DataSources {
    let workoutCount: Int
    let voiceLogCount: Int
    let hardEffortCount: Int
    let confidence: String  // "High", "Medium", "Low"
}

// MARK: - FitnessPredictorService

@Observable
final class FitnessPredictorService {
    var isAnalyzing = false
    var predictions: FitnessPrediction?
    var lastUpdated: Date?
    var errorMessage: String?

    private let healthStore = HKHealthStore()

    // MARK: - Predict Fitness

    @MainActor
    func predictFitness(
        plan: TrainingPlan?,
        healthKitManager: HealthKitManager
    ) async {
        Log.coach.info("Starting fitness prediction...")
        isAnalyzing = true
        errorMessage = nil

        // Fetch HealthKit workouts (30 days)
        Log.coach.info("Fetching HealthKit workouts...")
        let healthKitWorkouts = await fetchWorkouts(healthKitManager: healthKitManager, days: 30)
        Log.coach.info("Found \(healthKitWorkouts.count) HealthKit workouts")

        // Fetch voice logs from Supabase (includes linked workout data)
        Log.coach.info("Fetching training logs...")
        let voiceLogs = await fetchTrainingLogs(days: 30)
        Log.coach.info("Found \(voiceLogs.count) training logs")

        // Extract linked workouts from training logs (this is where race data often lives!)
        let linkedWorkouts = extractLinkedWorkouts(from: voiceLogs)
        Log.coach.info("Found \(linkedWorkouts.count) linked workouts in training logs")

        // Merge all workouts (linked workouts + HealthKit, avoiding duplicates by date+distance)
        var allWorkouts = linkedWorkouts
        for hkWorkout in healthKitWorkouts {
            // Check if this workout is already in linked workouts (same date and similar distance)
            let isDuplicate = linkedWorkouts.contains { linked in
                linked.date == hkWorkout.date &&
                abs(linked.distanceMiles - hkWorkout.distanceMiles) < 0.2
            }
            if !isDuplicate {
                allWorkouts.append(hkWorkout)
            }
        }
        Log.coach.info("Total workouts after merge: \(allWorkouts.count)")

        // Generate prediction (always use local for now - fast and free)
        let prediction = generateLocalPrediction(
            workouts: allWorkouts,
            voiceLogs: voiceLogs,
            plan: plan
        )

        predictions = prediction
        lastUpdated = Date()
        isAnalyzing = false

        Log.coach.info("Fitness prediction completed with \(prediction.races.count) races")
    }

    // MARK: - Fetch Workouts

    private func fetchWorkouts(
        healthKitManager: HealthKitManager,
        days: Int
    ) async -> [WorkoutData] {
        let endDate = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -days, to: endDate) ?? endDate

        let hkWorkouts = await withCheckedContinuation { continuation in
            healthKitManager.fetchWorkouts(from: startDate, to: endDate) { result in
                switch result {
                case let .success(workouts):
                    continuation.resume(returning: workouts)
                case .failure:
                    continuation.resume(returning: [])
                }
            }
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        return hkWorkouts.compactMap { workout -> WorkoutData? in
            guard workout.workoutActivityType == .running else { return nil }

            let distanceMiles = workout.totalDistance?.doubleValue(for: .mile()) ?? 0
            guard distanceMiles > 0.5 else { return nil }

            let durationSeconds = workout.duration
            let paceSecondsPerMile = distanceMiles > 0 ? durationSeconds / distanceMiles : 0

            var heartRateAvg: Int?
            if let hrStats = workout.statistics(for: HKQuantityType(.heartRate)) {
                heartRateAvg = Int(hrStats.averageQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute())) ?? 0)
            }

            return WorkoutData(
                date: dateFormatter.string(from: workout.startDate),
                distanceMiles: distanceMiles,
                durationMinutes: durationSeconds / 60,
                paceSecondsPerMile: paceSecondsPerMile,
                heartRateAvg: heartRateAvg,
                type: classifyWorkout(distance: distanceMiles, pace: paceSecondsPerMile)
            )
        }
    }

    private func classifyWorkout(distance: Double, pace: Double) -> String {
        if distance >= 10 { return "Long Run" }
        if pace > 0 && pace < 420 { return "Speed Work" }
        if pace > 0 && pace < 480 { return "Tempo" }
        if distance < 4 { return "Recovery" }
        return "Easy Run"
    }

    // MARK: - Fetch Training Logs (Voice Logs + Linked Workouts)

    private func fetchTrainingLogs(days: Int) async -> [VoiceLogData] {
        let startDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()

        do {
            let logs: [TrainingLog] = try await supabase
                .from("training_logs")
                .select()
                .gte("created_at", value: ISO8601DateFormatter().string(from: startDate))
                .order("created_at", ascending: false)
                .execute()
                .value

            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"

            return logs.compactMap { log -> VoiceLogData? in
                let notes = log.cleanedNotes ?? log.notes ?? ""

                // Extract pace mentions from notes
                let paces = extractPaces(from: notes)

                // Parse structured workout data from notes (intervals, tempo, etc.)
                let extractedWorkout = WorkoutTextParser.shared.parse(notes)
                if extractedWorkout.hasStructuredData {
                    Log.coach.info("Extracted structured workout: \(extractedWorkout.summary)")
                }

                return VoiceLogData(
                    date: log.workoutDate.map { dateFormatter.string(from: $0) } ?? dateFormatter.string(from: Date()),
                    notes: notes,
                    mood: log.mood,
                    pacesMentioned: paces,
                    linkedWorkoutDistanceMiles: log.workoutDistanceMiles,
                    linkedWorkoutDurationMinutes: log.workoutDurationMinutes,
                    extractedWorkout: extractedWorkout
                )
            }
        } catch {
            Log.coach.error("Failed to fetch training logs: \(error.localizedDescription)")
            return []
        }
    }

    /// Extract workouts from training logs that have linked workout data
    private func extractLinkedWorkouts(from voiceLogs: [VoiceLogData]) -> [WorkoutData] {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        return voiceLogs.compactMap { log -> WorkoutData? in
            guard let distance = log.linkedWorkoutDistanceMiles,
                  let duration = log.linkedWorkoutDurationMinutes,
                  distance > 0.5 else { return nil }

            let paceSecondsPerMile = (duration * 60) / distance

            return WorkoutData(
                date: log.date,
                distanceMiles: distance,
                durationMinutes: duration,
                paceSecondsPerMile: paceSecondsPerMile,
                heartRateAvg: nil,
                type: classifyWorkout(distance: distance, pace: paceSecondsPerMile)
            )
        }
    }

    private func extractPaces(from text: String) -> [String] {
        var paces: [String] = []

        // Pattern: "X:XX" or "XX:XX" format (1-2 digit minutes, 2 digit seconds)
        let pattern = #"(\d{1,2}):(\d{2})"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(text.startIndex..., in: text)
            let matches = regex.matches(in: text, range: range)

            for match in matches {
                if let minuteRange = Range(match.range(at: 1), in: text),
                   let secondRange = Range(match.range(at: 2), in: text),
                   let minutes = Int(text[minuteRange]),
                   let seconds = Int(text[secondRange]) {
                    let totalSeconds = minutes * 60 + seconds
                    // Only include reasonable running paces (4:00-15:00/mi)
                    if totalSeconds >= 240 && totalSeconds <= 900 {
                        paces.append("\(minutes):\(String(format: "%02d", seconds))/mi")
                    }
                }
            }
        }

        return paces
    }

    // MARK: - Local Prediction

    private func generateLocalPrediction(
        workouts: [WorkoutData],
        voiceLogs: [VoiceLogData],
        plan: TrainingPlan?
    ) -> FitnessPrediction {
        // PRIORITY 1: Detect recent RACE efforts (most accurate data)
        // Race = standard distance + faster than typical training
        let detectedRaces = detectRaces(workouts: workouts, voiceLogs: voiceLogs)

        // Find hard efforts using RELATIVE thresholds (not absolute pace numbers)
        // A "hard effort" is a workout significantly faster than the runner's average
        let hardEfforts: [WorkoutData]
        if workouts.count >= 2 {
            let avgPace = workouts.map { $0.paceSecondsPerMile }.reduce(0, +) / Double(workouts.count)
            // Hard effort = 8%+ faster than average (accounts for individual fitness)
            hardEfforts = workouts.filter { $0.paceSecondsPerMile < avgPace * 0.92 }
        } else {
            hardEfforts = []
        }

        // Extract paces from voice logs
        var voicePaces: [Double] = []
        for log in voiceLogs {
            for paceStr in log.pacesMentioned {
                if let pace = parsePaceString(paceStr) {
                    voicePaces.append(pace)
                }
            }
        }

        // Extract structured interval data from voice logs
        var intervalPaces: [(pace: Double, type: String)] = []
        for log in voiceLogs {
            guard let extracted = log.extractedWorkout, extracted.hasStructuredData else { continue }

            // Calculate paces from interval sets
            for interval in extracted.intervalSets {
                if let targetTime = interval.targetTime {
                    // Convert rep time to pace per mile
                    // e.g., 67s for 400m → (67 / 400m) * 1609m = 269s/mi = 4:29/mi
                    let pacePerMile = (targetTime.seconds / interval.distance.meters) * 1609.34
                    // Only include reasonable paces (3:30-15:00/mi)
                    if pacePerMile >= 210 && pacePerMile <= 900 {
                        intervalPaces.append((pacePerMile, "interval"))
                        Log.coach.info("Extracted interval pace: \(self.formatPaceLocal(pacePerMile)) from \(interval.description)")
                    }
                }
                if let targetPace = interval.targetPace {
                    intervalPaces.append((targetPace.secondsPerMile, "interval"))
                }
            }

            // Extract tempo/threshold paces
            for effort in extracted.continuousEfforts {
                if let pace = effort.targetPace {
                    intervalPaces.append((pace.secondsPerMile, effort.effortType.rawValue))
                    Log.coach.info("Extracted \(effort.effortType.rawValue) pace: \(self.formatPaceLocal(pace.secondsPerMile))")
                }
            }
        }

        // Estimate 10K pace from best available data
        var estimated10KPace: Double = 0
        var dataSource = "default"

        // Priority 1: Use actual race result if we have one
        if let race = detectedRaces.first {
            estimated10KPace = convert(racePace: race.paceSecondsPerMile, from: race.raceType, to: .tenK)
            dataSource = "race (\(race.raceType.rawValue))"
            Log.coach.info("Using \(race.raceType.rawValue) race result: \(self.formatPaceLocal(race.paceSecondsPerMile))")
        }
        // Priority 2: Structured interval data (very precise - "12x400m at 67s")
        // Interval paces are typically at VO2max (close to 5K race pace)
        else if !intervalPaces.isEmpty {
            // Separate interval paces from tempo paces for more accurate estimation
            let intervals = intervalPaces.filter { $0.type == "interval" }
            let tempos = intervalPaces.filter { $0.type == "tempo" || $0.type == "threshold" }

            if !intervals.isEmpty {
                // Interval pace is ~5K pace, which is ~4% faster than 10K
                let avgIntervalPace = intervals.map { $0.pace }.reduce(0, +) / Double(intervals.count)
                estimated10KPace = avgIntervalPace * 1.04  // 10K is ~4% slower than 5K/interval pace
                dataSource = "structured intervals (\(intervals.count) sets)"
                Log.coach.info("Using structured interval data: avg \(self.formatPaceLocal(avgIntervalPace)) → 10K \(self.formatPaceLocal(estimated10KPace))")
            } else if !tempos.isEmpty {
                // Tempo pace is threshold (~3% slower than 10K)
                let avgTempoPace = tempos.map { $0.pace }.reduce(0, +) / Double(tempos.count)
                estimated10KPace = avgTempoPace * 0.97
                dataSource = "structured tempo (\(tempos.count) efforts)"
                Log.coach.info("Using structured tempo data: avg \(self.formatPaceLocal(avgTempoPace)) → 10K \(self.formatPaceLocal(estimated10KPace))")
            }
        }
        // Priority 3: Voice log paces (user-reported threshold/tempo)
        else if !voicePaces.isEmpty {
            let avgVoicePace = voicePaces.reduce(0, +) / Double(voicePaces.count)
            // Assume voice log paces are threshold (~3% slower than 10K race pace)
            // To get 10K pace: divide by 1.03 (or multiply by ~0.97)
            estimated10KPace = avgVoicePace * 0.97
            dataSource = "voice logs"
        }
        // Priority 4: Hard effort workouts (faster than average)
        else if !hardEfforts.isEmpty {
            let fastestHardEffort = hardEfforts.min(by: { $0.paceSecondsPerMile < $1.paceSecondsPerMile })!
            // Assume hard effort is threshold (~3% slower than 10K race pace)
            estimated10KPace = fastestHardEffort.paceSecondsPerMile * 0.97
            dataSource = "hard efforts"
        }
        // Priority 5: Use fastest workout (assume it's a moderate effort)
        else if !workouts.isEmpty {
            let fastestWorkout = workouts.min(by: { $0.paceSecondsPerMile < $1.paceSecondsPerMile })!
            // With no hard efforts detected, assume fastest workout is ~5% slower than 10K race pace
            // (Could be a tempo-ish effort or fast easy run)
            estimated10KPace = fastestWorkout.paceSecondsPerMile * 0.95
            dataSource = "fastest workout"
        }
        // Fallback
        else {
            estimated10KPace = 480 // 8:00/mi default
            dataSource = "default"
        }

        Log.coach.info("Estimated 10K pace: \(self.formatPaceLocal(estimated10KPace)) (source: \(dataSource))")

        // Use VDOT methodology to calculate race paces (Jack Daniels)
        // These multipliers are derived from VDOT tables
        let milePace = estimated10KPace * 0.88       // Mile is ~12% faster than 10K pace
        let fiveKPace = estimated10KPace * 0.96      // 5K is ~4% faster
        let halfPace = estimated10KPace * 1.055      // Half is ~5.5% slower
        let marathonPace = estimated10KPace * 1.105  // Marathon is ~10.5% slower

        // Race distances in miles
        let mileDistance = 1.0
        let fiveKDistance = 3.10686
        let tenKDistance = 6.21371
        let halfDistance = 13.1094
        let marathonDistance = 26.2188

        let races = [
            RacePredictionItem(
                distance: "MILE",
                time: formatTime(seconds: Int(milePace * mileDistance)),
                pace: formatPaceLocal(milePace)
            ),
            RacePredictionItem(
                distance: "5K",
                time: formatTime(seconds: Int(fiveKPace * fiveKDistance)),
                pace: formatPaceLocal(fiveKPace)
            ),
            RacePredictionItem(
                distance: "10K",
                time: formatTime(seconds: Int(estimated10KPace * tenKDistance)),
                pace: formatPaceLocal(estimated10KPace)
            ),
            RacePredictionItem(
                distance: "HALF",
                time: formatTime(seconds: Int(halfPace * halfDistance)),
                pace: formatPaceLocal(halfPace)
            ),
            RacePredictionItem(
                distance: "MARATHON",
                time: formatTime(seconds: Int(marathonPace * marathonDistance)),
                pace: formatPaceLocal(marathonPace)
            )
        ]

        // Build summary based on data source
        let confidence: String
        let summary: String

        // Count structured interval sets for summary
        let structuredIntervalCount = intervalPaces.filter { $0.type == "interval" }.count
        let structuredTempoCount = intervalPaces.filter { $0.type == "tempo" || $0.type == "threshold" }.count

        if let race = detectedRaces.first {
            // High confidence when we have a recent race result
            confidence = "High"
            let raceTime = formatTime(seconds: race.totalTimeSeconds)
            summary = "Based on your recent \(race.raceType.rawValue) race (\(raceTime)). This is the most accurate predictor of fitness."
        } else if !intervalPaces.isEmpty {
            // High confidence with structured interval data
            confidence = "High"
            if structuredIntervalCount > 0 {
                summary = "Based on \(structuredIntervalCount) interval workout(s) extracted from your training notes. This gives precise VO2max estimates."
            } else {
                summary = "Based on \(structuredTempoCount) tempo/threshold workout(s) extracted from your training notes."
            }
        } else if workouts.isEmpty && voiceLogs.isEmpty {
            confidence = "Low"
            summary = "Sample predictions shown. Log runs via HealthKit or voice notes to get personalized race times."
        } else {
            confidence = hardEfforts.count >= 3 || voicePaces.count >= 2 ? "High" :
                        (hardEfforts.count >= 1 || voicePaces.count >= 1 ? "Medium" : "Low")
            summary = "Based on \(hardEfforts.count) hard efforts and \(voiceLogs.count) training logs from the last 30 days."
        }

        return FitnessPrediction(
            races: races,
            fitnessSummary: summary,
            dataSources: DataSources(
                workoutCount: workouts.count,
                voiceLogCount: voiceLogs.count,
                hardEffortCount: hardEfforts.count,
                confidence: confidence
            )
        )
    }

    private func parsePaceString(_ pace: String) -> Double? {
        // Parse "M:SS/mi" format
        let cleaned = pace.replacingOccurrences(of: "/mi", with: "")
        let parts = cleaned.split(separator: ":")
        guard parts.count == 2,
              let mins = Int(parts[0]),
              let secs = Int(parts[1]) else { return nil }
        return Double(mins * 60 + secs)
    }

    private func formatTime(seconds: Int) -> String {
        let hours = seconds / 3600
        let mins = (seconds % 3600) / 60
        let secs = seconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, mins, secs)
        } else {
            return String(format: "%d:%02d", mins, secs)
        }
    }

    private func formatPaceLocal(_ secondsPerMile: Double) -> String {
        let totalSecs = Int(secondsPerMile.rounded())
        let mins = totalSecs / 60
        let secs = totalSecs % 60
        return "\(mins):\(String(format: "%02d", secs))/mi"
    }

    // MARK: - Race Detection

    private enum RaceType: String {
        case mile = "Mile"
        case fiveK = "5K"
        case tenK = "10K"
        case half = "Half Marathon"
        case marathon = "Marathon"

        var distanceMiles: Double {
            switch self {
            case .mile: return 1.0
            case .fiveK: return 3.107
            case .tenK: return 6.214
            case .half: return 13.109
            case .marathon: return 26.219
            }
        }

        var tolerance: Double {
            // Allow for GPS drift - races often read short due to tangent running
            // 10K might show as 6.15mi instead of 6.21mi
            switch self {
            case .mile: return 0.08      // ±0.08mi (~8%)
            case .fiveK: return 0.20     // ±0.20mi (~6%)
            case .tenK: return 0.25      // ±0.25mi (~4%) - 5.96 to 6.46
            case .half: return 0.50      // ±0.50mi (~4%)
            case .marathon: return 1.0   // ±1.0mi (~4%)
            }
        }
    }

    private struct DetectedRace {
        let raceType: RaceType
        let paceSecondsPerMile: Double
        let date: String
        let totalTimeSeconds: Int
    }

    /// Detect race efforts from workouts
    /// A race is: standard distance + faster than typical training pace (relative to the runner)
    private func detectRaces(workouts: [WorkoutData], voiceLogs: [VoiceLogData]) -> [DetectedRace] {
        var races: [DetectedRace] = []

        // Check voice logs for race mentions
        let raceDates = Set(voiceLogs.filter { log in
            let notes = log.notes.lowercased()
            return notes.contains("race") || notes.contains("raced") || notes.contains("pr") ||
                   notes.contains("pb") || notes.contains("personal best") || notes.contains("finish time")
        }.map { $0.date })

        for workout in workouts {
            // Check if this workout is a standard race distance
            for raceType in [RaceType.mile, .fiveK, .tenK, .half, .marathon] {
                let minDist = raceType.distanceMiles - raceType.tolerance
                let maxDist = raceType.distanceMiles + raceType.tolerance

                if workout.distanceMiles >= minDist && workout.distanceMiles <= maxDist {
                    // This is a race distance - check if it was a hard effort

                    // Get all OTHER workouts (leave-one-out to avoid comparing to self)
                    let otherWorkouts = workouts.filter {
                        $0.date != workout.date || abs($0.distanceMiles - workout.distanceMiles) > 0.1
                    }

                    var isRaceEffort = false

                    if otherWorkouts.isEmpty {
                        // If this is the ONLY workout, treat it as a race
                        // (Why else would someone log exactly a race distance?)
                        isRaceEffort = true
                        Log.coach.info("Only workout at \(raceType.rawValue) distance - treating as race")
                    } else {
                        // Compare to other workouts - race should be faster than average
                        let avgPace = otherWorkouts.map { $0.paceSecondsPerMile }.reduce(0, +) / Double(otherWorkouts.count)
                        isRaceEffort = workout.paceSecondsPerMile < avgPace * 0.92 // 8% faster than average
                    }

                    // Also check if it's the fastest workout we have (likely a race)
                    let fastestPace = workouts.map { $0.paceSecondsPerMile }.min() ?? workout.paceSecondsPerMile
                    let isFastestWorkout = workout.paceSecondsPerMile <= fastestPace * 1.02 // Within 2% of fastest

                    // Voice logs mention it was a race
                    let mentionedAsRace = raceDates.contains(workout.date)

                    if isRaceEffort || isFastestWorkout || mentionedAsRace {
                        // Keep the GPS pace (that's what you actually ran)
                        // But calculate time for OFFICIAL race distance
                        let adjustedTimeSeconds = workout.paceSecondsPerMile * raceType.distanceMiles

                        races.append(DetectedRace(
                            raceType: raceType,
                            paceSecondsPerMile: workout.paceSecondsPerMile,
                            date: workout.date,
                            totalTimeSeconds: Int(adjustedTimeSeconds)
                        ))
                        Log.coach.info("Detected \(raceType.rawValue) race on \(workout.date): \(self.formatPaceLocal(workout.paceSecondsPerMile)) → \(self.formatTime(seconds: Int(adjustedTimeSeconds))) (official distance)")
                        break // Don't double-count
                    }
                }
            }
        }

        // Sort by date (most recent first)
        return races.sorted { $0.date > $1.date }
    }

    /// Convert pace from one race distance to another using VDOT equivalents
    private func convert(racePace: Double, from source: RaceType, to target: RaceType) -> Double {
        // VDOT conversion factors (relative to 10K pace)
        // Based on Jack Daniels' tables
        let factors: [RaceType: Double] = [
            .mile: 0.88,      // Mile is ~12% faster than 10K
            .fiveK: 0.96,     // 5K is ~4% faster than 10K
            .tenK: 1.0,       // 10K is the baseline
            .half: 1.055,     // Half is ~5.5% slower than 10K
            .marathon: 1.105  // Marathon is ~10.5% slower than 10K
        ]

        guard let sourceFactor = factors[source], let targetFactor = factors[target] else {
            return racePace
        }

        // Convert source pace to 10K equivalent, then to target
        let tenKPace = racePace / sourceFactor
        return tenKPace * targetFactor
    }
}

// MARK: - Internal Data Structures

private struct WorkoutData {
    let date: String
    let distanceMiles: Double
    let durationMinutes: Double
    let paceSecondsPerMile: Double
    let heartRateAvg: Int?
    let type: String
}

private struct VoiceLogData {
    let date: String
    let notes: String
    let mood: String?
    let pacesMentioned: [String]
    // Linked workout data from training_logs
    let linkedWorkoutDistanceMiles: Double?
    let linkedWorkoutDurationMinutes: Double?
    // Structured workout data extracted from notes
    let extractedWorkout: ExtractedWorkoutData?
}

// MARK: - HealthKitManager Extension

extension HealthKitManager {
    func fetchWorkouts(from startDate: Date, to endDate: Date, completion: @escaping (Result<[HKWorkout], Error>) -> Void) {
        let workoutType = HKObjectType.workoutType()

        // Filter for running workouts only
        let runningPredicate = HKQuery.predicateForWorkouts(with: .running)
        let datePredicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [runningPredicate, datePredicate])

        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        let query = HKSampleQuery(
            sampleType: workoutType,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [sortDescriptor]
        ) { _, samples, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            let workouts = samples as? [HKWorkout] ?? []
            completion(.success(workouts))
        }

        // Use the instance's healthStore, not a new one
        healthStore.execute(query)
    }
}

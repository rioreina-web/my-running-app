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

// MARK: - FitnessPredictorService

@Observable
final class FitnessPredictorService {
    var isAnalyzing = false
    var predictions: FitnessPrediction?
    var lastUpdated: Date?
    var errorMessage: String?
    var snapshotHistory: [FitnessSnapshot] = []
    var isLoadingHistory = false

    private let healthStore = HKHealthStore()
    private let workoutSources: [WorkoutDataSource]
    private let auth: AuthProvider

    init(
        workoutSources: [WorkoutDataSource]? = nil,
        auth: AuthProvider? = nil
    ) {
        self.workoutSources = workoutSources ?? [HealthKitManager.shared, VitalManager.shared]
        self.auth = auth ?? AuthManager.shared
    }

    // MARK: - Predict Fitness

    @MainActor
    func predictFitness(
        plan: TrainingPlan?
    ) async {
        Log.coach.info("Starting fitness prediction...")
        isAnalyzing = true
        errorMessage = nil

        let userId = AuthManager.shared.userId
        Log.coach.info("Using userId: \(userId)")

        // Fetch workouts from all sources (30 days)
        Log.coach.info("Fetching workouts from \(self.workoutSources.count) sources...")
        let sourceWorkouts = await fetchFromAllSources(days: 30)
        Log.coach.info("Found \(sourceWorkouts.count) workouts from all sources")

        // Fetch voice logs from Supabase (includes linked workout data)
        Log.coach.info("Fetching training logs...")
        let voiceLogs = await fetchTrainingLogs(days: 30)
        Log.coach.info("Found \(voiceLogs.count) training logs")

        // Surface data issues to the user
        if sourceWorkouts.isEmpty && voiceLogs.isEmpty {
            errorMessage = "No workout data found. Make sure HealthKit is authorized and you have recent runs."
            Log.coach.warning("No data from any source — userId=\(userId)")
        }

        // Extract linked workouts from training logs (this is where race data often lives!)
        let linkedWorkouts = extractLinkedWorkouts(from: voiceLogs)
        Log.coach.info("Found \(linkedWorkouts.count) linked workouts in training logs")

        // Merge all workouts (linked + sources, avoiding duplicates by date+distance)
        let allWorkouts = mergeWorkouts(linkedWorkouts, sourceWorkouts)
        Log.coach.info("Total workouts after merge: \(allWorkouts.count)")

        // Load snapshot history early so the predictor can use it as a baseline
        if snapshotHistory.isEmpty {
            await fetchHistory()
        }

        // Fetch extended history (180 days) for race detection — races happen infrequently
        Log.coach.info("Fetching extended history for race detection...")
        let extendedSourceWorkouts = await fetchFromAllSources(days: 180)
        let extendedVoiceLogs = await fetchTrainingLogs(days: 180)

        let extendedLinkedWorkouts = extractLinkedWorkouts(from: extendedVoiceLogs)
        let extendedWorkouts = mergeWorkouts(extendedLinkedWorkouts, extendedSourceWorkouts)
        Log.coach.info("Extended history: \(extendedWorkouts.count) workouts, \(extendedVoiceLogs.count) voice logs")

        // Generate prediction (always use local for now - fast and free)
        let prediction = generateLocalPrediction(
            workouts: allWorkouts,
            voiceLogs: voiceLogs,
            plan: plan,
            extendedWorkouts: extendedWorkouts,
            extendedVoiceLogs: extendedVoiceLogs
        )

        predictions = prediction
        lastUpdated = Date()
        isAnalyzing = false

        Log.coach.info("Fitness prediction completed with \(prediction.races.count) races")

        await saveSnapshot(prediction: prediction)
    }

    // MARK: - Fetch Workouts (Protocol-based)

    private func fetchFromAllSources(days: Int) async -> [WorkoutData] {
        let endDate = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -days, to: endDate) ?? endDate
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        var all: [WorkoutData] = []
        for source in workoutSources {
            let workouts = await source.fetchRunningWorkouts(startDate: startDate, endDate: endDate)
            let mapped = workouts.compactMap { rw -> WorkoutData? in
                guard rw.distanceMiles > 0.5 else { return nil }
                let durationSeconds = rw.durationMinutes * 60
                let paceSecondsPerMile = rw.distanceMiles > 0 ? durationSeconds / rw.distanceMiles : 0
                return WorkoutData(
                    date: dateFormatter.string(from: rw.startDate),
                    distanceMiles: rw.distanceMiles,
                    durationMinutes: rw.durationMinutes,
                    paceSecondsPerMile: paceSecondsPerMile,
                    heartRateAvg: nil,
                    type: classifyWorkout(distance: rw.distanceMiles, pace: paceSecondsPerMile)
                )
            }
            all.append(contentsOf: mapped)
        }
        return all
    }

    /// Merge workouts, deduplicating by date + distance proximity
    func mergeWorkouts(_ base: [WorkoutData], _ additions: [WorkoutData]) -> [WorkoutData] {
        var merged = base
        for workout in additions {
            let isDuplicate = merged.contains { existing in
                existing.date == workout.date &&
                abs(existing.distanceMiles - workout.distanceMiles) < 0.2
            }
            if !isDuplicate {
                merged.append(workout)
            }
        }
        return merged
    }

    func classifyWorkout(distance: Double, pace: Double) -> String {
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
            // Select only columns in the TrainingLog model to avoid decoding issues
            // with extra DB columns (extracted_data, last_processing_attempt, etc.)
            let columns = "id, created_at, audio_url, notes, cleaned_notes, mood, workout_date, workout_distance_miles, workout_duration_minutes, processing_status, processing_error, processing_attempts, transcript_url, coach_insight, workout_notes, workout_pace_per_mile, workout_type, source, vital_workout_id, pace_segments"
            let logs: [TrainingLog] = try await supabase
                .from("training_logs")
                .select(columns)
                .gte("created_at", value: ISO8601DateFormatter().string(from: startDate))
                .order("created_at", ascending: false)
                .limit(1000)
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
                    extractedWorkout: extractedWorkout,
                    paceSegments: log.paceSegments
                )
            }
        } catch {
            Log.coach.error("Failed to fetch training logs: \(error)")
            // Surface decoding errors — these are the #1 silent killer
            if let decodingError = error as? DecodingError {
                Log.coach.error("Decoding error detail: \(decodingError)")
            }
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

    func extractPaces(from text: String) -> [String] {
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
        plan: TrainingPlan?,
        extendedWorkouts: [WorkoutData] = [],
        extendedVoiceLogs: [VoiceLogData] = []
    ) -> FitnessPrediction {
        // PRIORITY 1: Detect RACE efforts from extended history (180 days)
        // Race = standard distance + faster than typical training
        // Use extended data so races from months ago are still found
        let raceWorkouts = extendedWorkouts.isEmpty ? workouts : extendedWorkouts
        let raceVoiceLogs = extendedVoiceLogs.isEmpty ? voiceLogs : extendedVoiceLogs
        let detectedRaces = detectRaces(workouts: raceWorkouts, voiceLogs: raceVoiceLogs)

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

        // --- Fitness baseline from previous snapshot history ---
        // Fitness doesn't vanish — use the best previous snapshot as a floor/ceiling.
        // Apply slight decay if no new data confirms fitness (~0.3%/week detraining).
        var baselinePace: Double? = nil
        if let bestSnapshot = snapshotHistory.first(where: { $0.confidence == "High" || $0.confidence == "Medium" }) {
            let weeksAgo = Calendar.current.dateComponents([.day], from: bestSnapshot.createdAt, to: Date()).day.map { Double($0) / 7.0 } ?? 0
            let decayFactor = 1.0 + (weeksAgo * 0.003)  // pace gets 0.3% slower per week without new data
            baselinePace = bestSnapshot.estimated10kPaceSeconds * decayFactor
            Log.coach.info("Fitness baseline from \(Int(weeksAgo))w ago: \(self.formatPaceLocal(bestSnapshot.estimated10kPaceSeconds)) → decayed \(self.formatPaceLocal(baselinePace!))")
        }

        // --- Estimate 10K pace: anchor + training adjustment ---
        // Step 1: Find the best anchor (race, plan goal, or snapshot baseline)
        // Step 2: Find the best current training signal (intervals, tempo, hard efforts)
        // Step 3: Blend — training signal nudges the anchor up or down
        var estimated10KPace: Double = 0
        var dataSource = "default"

        // ── Step 1: Anchor — the foundation of our fitness estimate ──
        var anchorPace: Double? = nil
        var anchorSource = ""
        var anchorWeeksAgo: Double = 0

        // Best anchor: detected race result
        if let race = detectedRaces.first {
            anchorPace = convert(racePace: race.paceSecondsPerMile, from: race.raceType, to: .tenK)
            anchorSource = "race (\(race.raceType.rawValue))"
            // Calculate how old the race is
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            if let raceDate = dateFormatter.date(from: race.date) {
                anchorWeeksAgo = Calendar.current.dateComponents([.day], from: raceDate, to: Date()).day.map { Double($0) / 7.0 } ?? 0
            }
            Log.coach.info("Anchor: \(race.raceType.rawValue) race \(self.formatPaceLocal(anchorPace!)) (\(Int(anchorWeeksAgo))w ago)")
        }
        // Next: training plan goal
        else if let plan = plan, plan.status == .active, plan.targetTimeSeconds > 0 {
            let goalPace = Double(plan.targetTimeSeconds) / plan.raceDistance.distanceInMiles
            anchorPace = convert(racePace: goalPace, from: planRaceType(plan.raceDistance), to: .tenK)
            anchorSource = "training plan (\(plan.raceDistance.displayName) goal)"
            Log.coach.info("Anchor: training plan goal → 10K \(self.formatPaceLocal(anchorPace!))")
        }
        // Fallback: previous snapshot baseline
        else if let baseline = baselinePace {
            anchorPace = baseline
            anchorSource = "fitness profile"
            let bestSnapshot = snapshotHistory.first(where: { $0.confidence == "High" || $0.confidence == "Medium" })
            if let snap = bestSnapshot {
                anchorWeeksAgo = Calendar.current.dateComponents([.day], from: snap.createdAt, to: Date()).day.map { Double($0) / 7.0 } ?? 0
            }
            Log.coach.info("Anchor: fitness profile \(self.formatPaceLocal(baseline)) (\(Int(anchorWeeksAgo))w ago)")
        }

        // ── Step 2: Measure actual training stimulus ──
        //
        // Grounded in what a competitive runner actually does:
        //   - 31:21 10K runner (~5:03/mi) typically runs 40-60 mi/week, 5-7 days
        //   - Quality: 2-3 sessions/week → 40-70 min of hard work
        //     e.g. Tue: 6x1K @ 3:40 (~22min), Thu: 5mi tempo @ 5:20 (~27min)
        //   - One quality session/week (~25 min) = enough to maintain fitness
        //   - Two sessions/week (~50 min) = standard training, fitness holds or improves
        //   - Zero quality + dropping volume = detraining
        //
        // We measure:
        //   1. Time at hard paces (from GPS pace segments in training_logs)
        //   2. Structured sessions (workouts with intervals/tempo from voice logs)
        //   3. Volume and quality trends (recent 2 weeks vs prior 2 weeks)
        //
        // Only count training AFTER the race anchor — pre-race training is
        // already reflected in the race result.

        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM-dd"
        let now = Date()
        let twoWeeksAgo = Calendar.current.date(byAdding: .day, value: -14, to: now)!
        let fourWeeksAgo = Calendar.current.date(byAdding: .day, value: -28, to: now)!

        // Determine the anchor date — only count stimulus after this point
        var anchorDate: Date = fourWeeksAgo  // default: 4 weeks back
        if let race = detectedRaces.first, let d = dateFmt.date(from: race.date) {
            anchorDate = d
        }

        // ── Count miles and runs from ALL workout sources (not just voice logs) ──
        var recentMiles: Double = 0
        var priorMiles: Double = 0
        var recentRuns = 0
        var priorRuns = 0

        // Use the 30-day workouts from HealthKit/Vital (already merged, deduplicated)
        for workout in workouts {
            guard let workoutDate = dateFmt.date(from: workout.date),
                  workoutDate > anchorDate else { continue }
            let isRecent = workoutDate >= twoWeeksAgo
            let isPrior = workoutDate >= fourWeeksAgo && workoutDate < twoWeeksAgo
            if isRecent { recentMiles += workout.distanceMiles; recentRuns += 1 }
            else if isPrior { priorMiles += workout.distanceMiles; priorRuns += 1 }
        }

        // ── Count hard stimulus from ALL sources ──
        // Priority: pace segments (most accurate) > voice log structured data > workout classification
        var postRaceStimulusSeconds: Double = 0
        var recentStimulusSeconds: Double = 0
        var priorStimulusSeconds: Double = 0
        var structuredSessionCount = 0
        var datesWithDetailedStimulus: Set<String> = []  // Don't double-count

        let allVoiceLogs = extendedVoiceLogs.isEmpty ? voiceLogs : extendedVoiceLogs
        let hardEffortTypes: Set<String> = ["tempo", "threshold", "interval", "race_pace"]

        // Pass 1: Pace segments from training_logs (most accurate — actual GPS-derived effort)
        for log in allVoiceLogs {
            let logDate = dateFmt.date(from: log.date) ?? now
            guard logDate > anchorDate else { continue }

            let isRecent = logDate >= twoWeeksAgo
            let isPrior = logDate >= fourWeeksAgo && logDate < twoWeeksAgo

            if let segments = log.paceSegments, !segments.isEmpty {
                var sessionHasStimulus = false
                for segment in segments {
                    if hardEffortTypes.contains(segment.effort) {
                        postRaceStimulusSeconds += segment.durationSeconds
                        if isRecent { recentStimulusSeconds += segment.durationSeconds }
                        else if isPrior { priorStimulusSeconds += segment.durationSeconds }
                        sessionHasStimulus = true
                    }
                }
                if sessionHasStimulus {
                    structuredSessionCount += 1
                    datesWithDetailedStimulus.insert(log.date)
                }
                continue
            }

            // Pass 2: Voice log structured data (intervals/tempo from notes)
            guard let extracted = log.extractedWorkout, extracted.hasStructuredData else { continue }
            var sessionHasStimulus = false

            for interval in extracted.intervalSets {
                if let targetTime = interval.targetTime {
                    let repSeconds = targetTime.seconds * Double(interval.repetitions)
                    postRaceStimulusSeconds += repSeconds
                    if isRecent { recentStimulusSeconds += repSeconds }
                    else if isPrior { priorStimulusSeconds += repSeconds }
                    sessionHasStimulus = true
                }
            }
            for effort in extracted.continuousEfforts {
                if let duration = effort.duration {
                    postRaceStimulusSeconds += duration.seconds
                    if isRecent { recentStimulusSeconds += duration.seconds }
                    else if isPrior { priorStimulusSeconds += duration.seconds }
                    sessionHasStimulus = true
                }
            }
            if sessionHasStimulus {
                structuredSessionCount += 1
                datesWithDetailedStimulus.insert(log.date)
            }
        }

        // No Pass 3: workouts without pace segments or structured voice log data
        // get no stimulus credit. We never guess from average pace classification
        // because average pace includes warmup/cooldown/recovery and is misleading.
        // Ensure pace segments are extracted at sync time (WorkoutsView.extractAndSavePaceSegments)
        // so they're available here via training_logs.

        // ── Compute weekly averages ──
        // Use the actual weeks since the race for weekly stimulus (not a fixed 4-week window)
        let weeksSinceAnchor = max(anchorWeeksAgo, 1.0)
        let weeklyStimulusMinutes = (postRaceStimulusSeconds / 60.0) / weeksSinceAnchor
        let stimulusMinutes = postRaceStimulusSeconds / 60.0
        let weeklyMiles = (recentMiles + priorMiles) / min(weeksSinceAnchor, 4.0)
        let runsPerWeek = Double(recentRuns + priorRuns) / min(weeksSinceAnchor, 4.0)

        // Trends: >1 = increasing, <1 = decreasing (recent 2wk vs prior 2wk)
        let volumeTrend = priorMiles > 0 ? recentMiles / priorMiles : (recentMiles > 0 ? 2.0 : 0.0)
        let stimulusTrend = priorStimulusSeconds > 0 ? recentStimulusSeconds / priorStimulusSeconds : (recentStimulusSeconds > 0 ? 2.0 : 0.0)

        Log.coach.info("Training stimulus: \(String(format: "%.0f", weeklyStimulusMinutes))min/wk hard (\(String(format: "%.0f", stimulusMinutes))min total), \(structuredSessionCount) quality sessions, \(String(format: "%.0f", weeklyMiles))mi/wk, vol trend \(String(format: "%.2f", volumeTrend)), stim trend \(String(format: "%.2f", stimulusTrend))")

        if let anchor = anchorPace {
            // ── Decay model ──
            //
            // Real-world calibration for a ~31:20 10K runner:
            //   Scenario A: Training well (2 quality sessions/wk, 50+ mi/wk)
            //     → weeklyStimulusMin ~50, volumeTrend ~1.0
            //     → effectiveDecay ≈ 0 → predicted 10K stays ~31:20  ✓
            //   Scenario B: Maintaining (1 quality session/wk, 35 mi/wk)
            //     → weeklyStimulusMin ~25, volumeTrend ~0.9
            //     → effectiveDecay ≈ 0.05%/wk → 5 weeks = +5 sec → 31:26  ✓
            //   Scenario C: Easy running only (0 quality, 30 mi/wk)
            //     → weeklyStimulusMin 0, volumeTrend ~1.0
            //     → effectiveDecay ≈ 0.15%/wk → 5 weeks = +14 sec → 31:35  ✓
            //   Scenario D: Not running at all
            //     → weeklyStimulusMin 0, volumeTrend 0
            //     → effectiveDecay ≈ 0.35%/wk → 5 weeks = +33 sec → 31:54  ✓
            //   Scenario E: Increasing quality + volume (peaking)
            //     → weeklyStimulusMin ~60, volumeTrend 1.3, stimulusTrend 1.4
            //     → slight improvement → 5 weeks = -5 to -10 sec → 31:11–31:16  ✓

            // Base detraining: 0.3%/week with zero running (VO2max literature)
            let baseDecayPerWeek = 0.003

            // Quality work offsets decay. One session/week (~25 min) = half maintenance.
            // Two sessions/week (~50 min) = full maintenance. Scale linearly up to 50 min.
            let stimulusOffset = min(weeklyStimulusMinutes / 50.0, 1.0) // 0..1

            // Volume also matters — you can't maintain with quality alone on 15 mi/week.
            // Running volume preserves the aerobic base that supports the hard stuff.
            // At 40+ mi/wk: full volume credit. Below that: partial. Below 10: minimal.
            let volumeCredit = min(weeklyMiles / 40.0, 1.0) // 0..1

            // Combined: stimulus and volume both contribute. Stimulus matters more
            // (you can maintain on 30 mi/wk with 2 quality sessions, but not on
            // 60 mi/wk of easy running with no quality for months).
            let maintenanceFactor = stimulusOffset * 0.65 + volumeCredit * 0.35
            // 0 = no training at all, 1 = full training

            // Effective decay: full training = ~0.03%/wk (residual). No training = 0.3%/wk.
            var effectiveDecayPerWeek = baseDecayPerWeek * (1.0 - maintenanceFactor * 0.9)

            // Progressive overload: if both volume and quality are trending up,
            // the runner is getting fitter, not just maintaining.
            if volumeTrend > 1.15 && stimulusTrend > 1.0 && weeklyStimulusMinutes >= 30 {
                // Building phase — slight improvement possible
                let buildRate = min((volumeTrend - 1.0) * 0.003, 0.002) // cap at 0.2%/wk improvement
                effectiveDecayPerWeek -= buildRate
            }

            // Sharp volume drop = faster decay (injury, life, etc.)
            if volumeTrend < 0.5 && volumeTrend > 0 {
                effectiveDecayPerWeek += 0.001
            }

            // Cap: can't improve faster than 0.2%/week, can't decay faster than 0.4%/week
            effectiveDecayPerWeek = max(min(effectiveDecayPerWeek, 0.004), -0.002)

            let decayFactor = 1.0 + (anchorWeeksAgo * effectiveDecayPerWeek)
            estimated10KPace = anchor * decayFactor

            // ── Step 2b: Validate anchor with actual workout paces ──
            // If we have recent interval/tempo paces from GPS pace segments,
            // use them to validate and adjust the anchor-based estimate.
            // Interval pace ≈ 5K-10K fitness. Tempo pace ≈ half marathon fitness.
            var paceSegmentSignal: Double?

            // Collect hard segment paces + distances from recent workouts (last 14 days)
            // We need VOLUME at hard paces, not just a few 200m reps
            struct HardEffort {
                let paceSeconds: Double
                let distanceMiles: Double
            }
            var recentHardEfforts: [HardEffort] = []

            for log in allVoiceLogs {
                let logDate = dateFmt.date(from: log.date) ?? now
                guard logDate >= twoWeeksAgo else { continue }
                guard let segments = log.paceSegments else { continue }
                for seg in segments {
                    guard hardEffortTypes.contains(seg.effort) else { continue }
                    guard seg.distanceMiles > 0.1 else { continue } // skip tiny segments
                    let parts = seg.pacePerMile.split(separator: ":").compactMap { Double($0) }
                    if parts.count == 2 {
                        let paceSeconds = parts[0] * 60 + parts[1]
                        if paceSeconds >= 210 && paceSeconds <= 540 {
                            recentHardEfforts.append(HardEffort(paceSeconds: paceSeconds, distanceMiles: seg.distanceMiles))
                        }
                    }
                }
            }

            // Also include voice-log extracted interval paces with estimated distance
            for ip in intervalPaces {
                if ip.pace >= 210 && ip.pace <= 540 {
                    // Estimate distance from pace type — intervals ~0.5mi each, tempo ~2mi
                    let estDist = ip.type == "interval" ? 0.5 : 2.0
                    recentHardEfforts.append(HardEffort(paceSeconds: ip.pace, distanceMiles: estDist))
                }
            }

            // Only use pace signal if there's meaningful volume at hard paces
            // Minimum: 4 miles of hard running in the last 14 days
            // This prevents 2x200m strides from skewing the prediction
            let totalHardMiles = recentHardEfforts.reduce(0.0) { $0 + $1.distanceMiles }

            if totalHardMiles >= 4.0 && recentHardEfforts.count >= 3 {
                // Distance-weighted average pace (longer efforts count more)
                let weightedPaceSum = recentHardEfforts.reduce(0.0) { $0 + $1.paceSeconds * $1.distanceMiles }
                let weightedAvgPace = weightedPaceSum / totalHardMiles

                // Convert interval pace to 10K equivalent:
                // Hard training pace ≈ 3K-5K effort → multiply by ~1.06 for 10K
                paceSegmentSignal = weightedAvgPace * 1.06

                let diff = paceSegmentSignal! - estimated10KPace
                if abs(diff) > 5 { // More than 5 sec/mi discrepancy
                    // Blend weight scales with volume: 4mi = 30% signal, 8mi+ = 50% signal
                    let signalWeight = min(0.3 + (totalHardMiles - 4.0) * 0.05, 0.5)
                    let anchorWeight = 1.0 - signalWeight
                    let blended = estimated10KPace * anchorWeight + paceSegmentSignal! * signalWeight
                    Log.coach.info("Pace segment signal: \(self.formatPaceLocal(paceSegmentSignal!)) vs anchor \(self.formatPaceLocal(estimated10KPace)) → blended \(self.formatPaceLocal(blended)) (weight: \(String(format: "%.0f", signalWeight * 100))%, \(String(format: "%.1f", totalHardMiles))mi hard)")
                    estimated10KPace = blended
                }
            } else if totalHardMiles > 0 {
                Log.coach.info("Pace segments found (\(String(format: "%.1f", totalHardMiles))mi) but below 4mi threshold — not enough volume to adjust")
            }

            if effectiveDecayPerWeek < 0 {
                dataSource = anchorSource + " (improving)"
            } else if effectiveDecayPerWeek < 0.001 {
                dataSource = anchorSource + " (maintaining)"
            } else {
                dataSource = anchorSource
            }

            if paceSegmentSignal != nil {
                dataSource += " + pace segments"
            }

            Log.coach.info("Anchor \(self.formatPaceLocal(anchor)) → \(self.formatPaceLocal(estimated10KPace)) (\(Int(anchorWeeksAgo))w, decay \(String(format: "%.3f", effectiveDecayPerWeek * 100))%/wk, stim \(String(format: "%.0f", weeklyStimulusMinutes))min/wk, vol \(String(format: "%.0f", weeklyMiles))mi/wk, maint \(String(format: "%.0f", maintenanceFactor * 100))%, hard vol: \(String(format: "%.1f", totalHardMiles))mi)")
        }

        // ── Fallback: structured workout data from voice logs (only when no anchor) ──
        // Only use explicitly logged interval/tempo paces from voice logs — these are
        // the actual work portions, not contaminated by warmup/cooldown.
        if estimated10KPace == 0 {
            let intervals = intervalPaces.filter { $0.type == "interval" }
            let tempos = intervalPaces.filter { $0.type == "tempo" || $0.type == "threshold" }
            var trainingSignal: Double? = nil
            var trainingSource = ""

            if !intervals.isEmpty {
                let avgIntervalPace = intervals.map { $0.pace }.reduce(0, +) / Double(intervals.count)
                trainingSignal = avgIntervalPace * 1.04
                trainingSource = "intervals (\(intervals.count) sets)"
            } else if !tempos.isEmpty {
                let avgTempoPace = tempos.map { $0.pace }.reduce(0, +) / Double(tempos.count)
                trainingSignal = avgTempoPace * 0.97
                trainingSource = "tempo (\(tempos.count) efforts)"
            } else if !voicePaces.isEmpty {
                let avgVoicePace = voicePaces.reduce(0, +) / Double(voicePaces.count)
                trainingSignal = avgVoicePace * 0.97
                trainingSource = "voice log paces"
            }

            if let signal = trainingSignal {
                estimated10KPace = signal
                dataSource = trainingSource
                Log.coach.info("Training signal only: \(self.formatPaceLocal(signal))")
            } else if !workouts.isEmpty {
                // No structured data — last resort, use fastest workout as rough estimate
                let fastestWorkout = workouts.min(by: { $0.paceSecondsPerMile < $1.paceSecondsPerMile })!
                estimated10KPace = fastestWorkout.paceSecondsPerMile * 0.95
                dataSource = "fastest workout"
            } else {
                estimated10KPace = 480
                dataSource = "default"
            }
        }

        Log.coach.info("Estimated 10K pace: \(self.formatPaceLocal(estimated10KPace)) (source: \(dataSource))")

        // Use PaceCalculator equivalence tables (same system as the pace chart)
        // to derive all race predictions from the estimated 10K pace.
        let tenKSeconds = Int(estimated10KPace * 6.21371)

        func raceTime(_ toDistance: String) -> Int {
            PaceCalculator.getEquivalentTime(fromDistance: "10K", fromSeconds: tenKSeconds, toDistance: toDistance)
        }
        func racePace(_ toDistance: String) -> Double {
            let time = raceTime(toDistance)
            let miles = PaceCalculator.distances[toDistance] ?? 1.0
            return Double(time) / miles
        }

        let races = [
            RacePredictionItem(
                distance: "MILE",
                time: formatTime(seconds: raceTime("mile")),
                pace: formatPaceLocal(racePace("mile"))
            ),
            RacePredictionItem(
                distance: "5K",
                time: formatTime(seconds: raceTime("5K")),
                pace: formatPaceLocal(racePace("5K"))
            ),
            RacePredictionItem(
                distance: "10K",
                time: formatTime(seconds: tenKSeconds),
                pace: formatPaceLocal(estimated10KPace)
            ),
            RacePredictionItem(
                distance: "HALF",
                time: formatTime(seconds: raceTime("half")),
                pace: formatPaceLocal(racePace("half"))
            ),
            RacePredictionItem(
                distance: "MARATHON",
                time: formatTime(seconds: raceTime("marathon")),
                pace: formatPaceLocal(racePace("marathon"))
            )
        ]

        // Build summary based on data source
        let confidence: String
        let summary: String

        // Count structured interval sets for summary
        let structuredIntervalCount = intervalPaces.filter { $0.type == "interval" }.count
        let structuredTempoCount = intervalPaces.filter { $0.type == "tempo" || $0.type == "threshold" }.count

        if let race = detectedRaces.first {
            confidence = "High"
            let raceTime = formatTime(seconds: race.totalTimeSeconds)
            summary = "Based on your \(race.raceType.rawValue) race (\(raceTime))."
        } else if anchorPace != nil {
            confidence = "Medium"
            summary = "Based on your \(anchorSource)."
        } else if structuredIntervalCount > 0 || structuredTempoCount > 0 {
            confidence = "Medium"
            summary = "Based on structured workout data from your training logs."
        } else if dataSource.contains("training plan") {
            confidence = "Medium"
            let goalTime = plan.map { formatTime(seconds: $0.targetTimeSeconds) } ?? ""
            let raceName = plan?.raceDistance.displayName ?? ""
            summary = "Based on your \(raceName) goal of \(goalTime). Log workouts and voice notes for more precise predictions."
        } else if dataSource.contains("fitness profile") {
            confidence = "Medium"
            summary = "Based on your previous fitness profile. Log a hard workout or race for a fresh assessment."
        } else if workouts.isEmpty && voiceLogs.isEmpty {
            confidence = "Low"
            summary = "Sample predictions shown. Log runs via HealthKit or voice notes to get personalized race times."
        } else {
            confidence = "Low"
            summary = "Based on \(workouts.count) workouts from the last 30 days. Log a hard effort or race for better accuracy."
        }

        // Build training paces from the estimated 10K pace
        let eqPaces = EquivalentPaces(raceDistance: .tenK, goalTimeSeconds: tenKSeconds)
        let trainingPaces = TrainingPacesSummary(
            easyPace: "\(formatPaceLocal(eqPaces.easyPace)) – \(formatPaceLocal(eqPaces.moderatePace))",
            marathonPace: formatPaceLocal(eqPaces.mpPace),
            thresholdPace: formatPaceLocal(eqPaces.thresholdPace),
            intervalPace: formatPaceLocal(racePace("5K")),
            longRunPace: formatPaceLocal(eqPaces.longRunPace)
        )

        // Build race anchor info
        var raceAnchor: RaceAnchorInfo? = nil
        if let race = detectedRaces.first {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            var weeksAgo = 0
            if let raceDate = dateFormatter.date(from: race.date) {
                weeksAgo = (Calendar.current.dateComponents([.day], from: raceDate, to: Date()).day ?? 0) / 7
            }
            let displayFmt = DateFormatter()
            displayFmt.dateFormat = "MMM d, yyyy"
            let displayDate = dateFormatter.date(from: race.date).map { displayFmt.string(from: $0) } ?? race.date
            raceAnchor = RaceAnchorInfo(
                raceType: race.raceType.rawValue.uppercased(),
                time: formatTime(seconds: race.totalTimeSeconds),
                date: displayDate,
                weeksAgo: weeksAgo
            )
        }

        return FitnessPrediction(
            races: races,
            fitnessSummary: summary,
            dataSources: DataSources(
                workoutCount: workouts.count,
                voiceLogCount: voiceLogs.count,
                hardEffortCount: hardEfforts.count,
                confidence: confidence
            ),
            estimated10kPaceSeconds: estimated10KPace,
            dataSource: dataSource,
            trainingPaces: trainingPaces,
            raceAnchor: raceAnchor,
            trainingStimulus: TrainingStimulusInfo(
                weeklyMiles: weeklyMiles,
                runsPerWeek: runsPerWeek,
                stimulusMinutes: stimulusMinutes,
                structuredSessions: structuredSessionCount,
                volumeTrend: volumeTrend,
                stimulusTrend: stimulusTrend
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
        PaceCalculator.formatPaceWithUnit(secondsPerMile)
    }

    // MARK: - Snapshot Persistence

    @MainActor
    private func saveSnapshot(prediction: FitnessPrediction) async {
        let userId = AuthManager.shared.userId

        // Rate limit: max 1 snapshot per day
        let today = Calendar.current.startOfDay(for: Date())
        if let latest = snapshotHistory.first,
           Calendar.current.isDate(latest.createdAt, inSameDayAs: today) {
            Log.coach.info("Fitness snapshot already exists for today, skipping save")
            return
        }

        // Calculate race times from the 10K pace baseline using PaceCalculator
        let pace10k = prediction.estimated10kPaceSeconds
        let tenKSeconds = Int(pace10k * 6.21371)

        let insert = FitnessSnapshotInsert(
            userId: userId,
            predictedMileSeconds: PaceCalculator.getEquivalentTime(fromDistance: "10K", fromSeconds: tenKSeconds, toDistance: "mile"),
            predicted5kSeconds: PaceCalculator.getEquivalentTime(fromDistance: "10K", fromSeconds: tenKSeconds, toDistance: "5K"),
            predicted10kSeconds: tenKSeconds,
            predictedHalfSeconds: PaceCalculator.getEquivalentTime(fromDistance: "10K", fromSeconds: tenKSeconds, toDistance: "half"),
            predictedMarathonSeconds: PaceCalculator.getEquivalentTime(fromDistance: "10K", fromSeconds: tenKSeconds, toDistance: "marathon"),
            estimated10kPaceSeconds: pace10k,
            confidence: prediction.dataSources.confidence,
            dataSource: prediction.dataSource,
            workoutCount: prediction.dataSources.workoutCount
        )

        do {
            try await supabase
                .from("fitness_snapshots")
                .insert(insert)
                .execute()

            Log.coach.info("Saved fitness snapshot (10K pace: \(self.formatPaceLocal(pace10k)))")

            // Refresh history to include the new snapshot
            await fetchHistory()
        } catch {
            Log.coach.error("Failed to save fitness snapshot: \(error.localizedDescription)")
        }
    }

    @MainActor
    func fetchHistory() async {
        isLoadingHistory = true

        let ninetyDaysAgo = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date()

        let userId = AuthManager.shared.userId

        do {
            let snapshots: [FitnessSnapshot] = try await supabase
                .from("fitness_snapshots")
                .select()
                .eq("user_id", value: userId)
                .gte("created_at", value: ISO8601DateFormatter().string(from: ninetyDaysAgo))
                .order("created_at", ascending: false)
                .limit(100)
                .execute()
                .value

            snapshotHistory = snapshots
            Log.coach.info("Fetched \(snapshots.count) fitness snapshots")
        } catch {
            Log.coach.error("Failed to fetch fitness history: \(error.localizedDescription)")
        }

        isLoadingHistory = false
    }

    // MARK: - Trend Helpers

    /// Change in predicted 10K time (seconds) vs previous snapshot. Negative = improvement.
    var tenKChangeFromPrevious: Int? {
        guard snapshotHistory.count >= 2 else { return nil }
        return snapshotHistory[0].predicted10kSeconds - snapshotHistory[1].predicted10kSeconds
    }

    /// Date of the previous snapshot for comparison labeling
    var previousSnapshotDate: Date? {
        guard snapshotHistory.count >= 2 else { return nil }
        return snapshotHistory[1].createdAt
    }

    // MARK: - Race Detection

    enum RaceType: String {
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
            case .tenK: return 0.40      // ±0.40mi (~6%) - 5.81 to 6.61
            case .half: return 0.50      // ±0.50mi (~4%)
            case .marathon: return 1.0   // ±1.0mi (~4%)
            }
        }
    }

    struct DetectedRace {
        let raceType: RaceType
        let paceSecondsPerMile: Double
        let date: String
        let totalTimeSeconds: Int
    }

    /// Detect race efforts from workouts and voice logs.
    /// Voice log text parsing runs FIRST — "10k race: 31:24" is the strongest signal.
    func detectRaces(workouts: [WorkoutData], voiceLogs: [VoiceLogData]) -> [DetectedRace] {
        var races: [DetectedRace] = []

        // ── PHASE 1: Parse explicit race results from training log notes ──
        // This is the most reliable source — the user explicitly wrote "10k race: 31:24"
        let raceKeywords = ["race", "raced", "pr ", "pr:", "pb ", "pb:", "personal best", "personal record", "finish time"]
        let distancePatterns: [(String, RaceType)] = [
            ("marathon", .marathon), ("half marathon", .half), ("half", .half),
            ("10k", .tenK), ("10K", .tenK),
            ("5k", .fiveK), ("5K", .fiveK),
            ("mile", .mile),
        ]

        for log in voiceLogs {
            let notes = log.notes.lowercased()
            guard raceKeywords.contains(where: { notes.contains($0) }) else { continue }

            for (pattern, raceType) in distancePatterns {
                guard notes.contains(pattern) else { continue }
                // Already have this race type? Skip.
                if races.contains(where: { $0.raceType == raceType }) { break }

                // Parse time: H:MM:SS or MM:SS patterns
                let originalNotes = log.notes
                let timePattern = #"(\d{1,2}):(\d{2}):(\d{2})|(\d{1,2}):(\d{2})"#
                guard let regex = try? NSRegularExpression(pattern: timePattern) else { break }
                let range = NSRange(originalNotes.startIndex..., in: originalNotes)
                let matches = regex.matches(in: originalNotes, range: range)

                for match in matches {
                    var totalSeconds: Int?

                    // H:MM:SS format
                    if let hRange = Range(match.range(at: 1), in: originalNotes),
                       let mRange = Range(match.range(at: 2), in: originalNotes),
                       let sRange = Range(match.range(at: 3), in: originalNotes),
                       let h = Int(originalNotes[hRange]),
                       let m = Int(originalNotes[mRange]),
                       let s = Int(originalNotes[sRange]) {
                        totalSeconds = h * 3600 + m * 60 + s
                    }
                    // MM:SS format
                    else if let mRange = Range(match.range(at: 4), in: originalNotes),
                            let sRange = Range(match.range(at: 5), in: originalNotes),
                            let m = Int(originalNotes[mRange]),
                            let s = Int(originalNotes[sRange]) {
                        totalSeconds = m * 60 + s
                    }

                    if let seconds = totalSeconds, seconds > 60, seconds < 36000 {
                        let pace = Double(seconds) / raceType.distanceMiles
                        if pace >= 180 && pace <= 900 {
                            races.append(DetectedRace(
                                raceType: raceType,
                                paceSecondsPerMile: pace,
                                date: log.date,
                                totalTimeSeconds: seconds
                            ))
                            Log.coach.info("Parsed \(raceType.rawValue) race from notes on \(log.date): \(self.formatTime(seconds: seconds)) (\(self.formatPaceLocal(pace)))")
                            break
                        }
                    }
                }
                break // Only match the first distance pattern per log
            }
        }

        // ── PHASE 2: Detect race efforts from workout data ──
        // Race = standard distance + faster than typical training pace
        let raceDates = Set(voiceLogs.filter { log in
            let notes = log.notes.lowercased()
            return raceKeywords.contains(where: { notes.contains($0) })
        }.map { $0.date })

        for workout in workouts {
            for raceType in [RaceType.mile, .fiveK, .tenK, .half, .marathon] {
                // Already found this race type from voice logs? Skip.
                if races.contains(where: { $0.raceType == raceType }) { continue }

                let minDist = raceType.distanceMiles - raceType.tolerance
                let maxDist = raceType.distanceMiles + raceType.tolerance

                if workout.distanceMiles >= minDist && workout.distanceMiles <= maxDist {
                    let minComparisonDist = min(4.0, raceType.distanceMiles * 0.8)
                    let otherWorkouts = workouts.filter {
                        ($0.date != workout.date || abs($0.distanceMiles - workout.distanceMiles) > 0.1) &&
                        $0.distanceMiles >= minComparisonDist
                    }

                    var isRaceEffort = false

                    if otherWorkouts.isEmpty {
                        isRaceEffort = true
                        Log.coach.info("Only workout at \(raceType.rawValue) distance - treating as race")
                    } else {
                        let avgPace = otherWorkouts.map { $0.paceSecondsPerMile }.reduce(0, +) / Double(otherWorkouts.count)
                        isRaceEffort = workout.paceSecondsPerMile < avgPace * 0.92
                    }

                    let sameDistWorkouts = workouts.filter {
                        $0.distanceMiles >= minDist && $0.distanceMiles <= maxDist
                    }
                    let fastestAtDist = sameDistWorkouts.map { $0.paceSecondsPerMile }.min() ?? workout.paceSecondsPerMile
                    let isFastestWorkout = sameDistWorkouts.count >= 2 &&
                        workout.paceSecondsPerMile <= fastestAtDist * 1.01 &&
                        !otherWorkouts.isEmpty &&
                        workout.paceSecondsPerMile < (otherWorkouts.map { $0.paceSecondsPerMile }.reduce(0, +) / Double(otherWorkouts.count))

                    let mentionedAsRace = raceDates.contains(workout.date)

                    if isRaceEffort || isFastestWorkout || mentionedAsRace {
                        // Adjust race time from GPS-measured distance to the standard race distance.
                        // GPS commonly reads short (tangent running, tunnel signal loss) — a 10K
                        // race showing 5.9mi on the watch is still a 10K. Use the actual finish
                        // time as the race time when GPS is short. Only scale up when GPS is
                        // long (extra warm-up distance, wrong start/stop).
                        let actualTimeSeconds = workout.durationMinutes * 60
                        let actualDistanceMiles = workout.distanceMiles
                        let targetKey = raceTypeToPCKey(raceType)
                        let targetDistanceMiles = PaceCalculator.distances[targetKey] ?? raceType.distanceMiles

                        let adjustedTimeSeconds: Int
                        let distanceRatio = actualDistanceMiles / targetDistanceMiles

                        if distanceRatio >= 0.92 && distanceRatio <= 1.02 {
                            // GPS shows the race distance (or slightly short due to GPS error).
                            // Trust the actual finish time as the true race time.
                            adjustedTimeSeconds = Int(actualTimeSeconds)
                        } else if distanceRatio > 1.02 && distanceRatio < 1.08 {
                            // GPS reads longer (extra distance from warm-up, wrong cut-off).
                            // Scale down proportionally.
                            adjustedTimeSeconds = Int(actualTimeSeconds / distanceRatio)
                        } else {
                            // Significantly different distance — use PaceCalculator equivalence
                            let pcKey = closestPaceCalculatorKey(distanceMiles: actualDistanceMiles)
                            let converted = PaceCalculator.getEquivalentTime(
                                fromDistance: pcKey, fromSeconds: Int(actualTimeSeconds), toDistance: targetKey
                            )
                            adjustedTimeSeconds = converted > 0 ? converted : Int(actualTimeSeconds)
                        }
                        let adjustedPace = Double(adjustedTimeSeconds) / raceType.distanceMiles

                        races.append(DetectedRace(
                            raceType: raceType,
                            paceSecondsPerMile: adjustedPace,
                            date: workout.date,
                            totalTimeSeconds: adjustedTimeSeconds
                        ))
                        Log.coach.info("Detected \(raceType.rawValue) race on \(workout.date): \(self.formatPaceLocal(workout.paceSecondsPerMile)) (\(String(format: "%.2f", actualDistanceMiles))mi) → \(self.formatTime(seconds: adjustedTimeSeconds))")
                        break
                    }
                }
            }
        }

        // Sort by date (most recent first)
        return races.sorted { $0.date > $1.date }
    }

    /// Map the public RaceDistance enum to the internal RaceType
    private func planRaceType(_ distance: RaceDistance) -> RaceType {
        switch distance {
        case .mile1500: return .mile
        case .fiveK: return .fiveK
        case .tenK: return .tenK
        case .halfMarathon: return .half
        case .marathon: return .marathon
        }
    }

    /// Convert pace from one race distance to another using PaceCalculator equivalence tables.
    /// This matches the pace chart system exactly.
    func convert(racePace: Double, from source: RaceType, to target: RaceType) -> Double {
        let sourceKey = raceTypeToPCKey(source)
        let targetKey = raceTypeToPCKey(target)
        let sourceMiles = PaceCalculator.distances[sourceKey] ?? source.distanceMiles
        let targetMiles = PaceCalculator.distances[targetKey] ?? target.distanceMiles

        guard let fromRatio = PaceCalculator.performanceRatios[sourceKey],
              let toRatio = PaceCalculator.performanceRatios[targetKey] else { return racePace }

        // Use doubles throughout to avoid Int truncation errors
        let sourceTimeSeconds = racePace * sourceMiles
        let targetTimeSeconds = sourceTimeSeconds * (toRatio / fromRatio)
        guard targetTimeSeconds > 0 else { return racePace }
        return targetTimeSeconds / targetMiles
    }

    /// Map RaceType to PaceCalculator distance key
    private func raceTypeToPCKey(_ type: RaceType) -> String {
        switch type {
        case .mile: return "mile"
        case .fiveK: return "5K"
        case .tenK: return "10K"
        case .half: return "half"
        case .marathon: return "marathon"
        }
    }

    /// Find the closest PaceCalculator distance key for a given distance in miles
    private func closestPaceCalculatorKey(distanceMiles: Double) -> String {
        let keys: [(String, Double)] = [
            ("mile", 1.0),
            ("5K", 3.10686),
            ("10K", 6.21371),
            ("half", 13.1094),
            ("marathon", 26.2188),
        ]
        return keys.min(by: { abs($0.1 - distanceMiles) < abs($1.1 - distanceMiles) })?.0 ?? "10K"
    }
}



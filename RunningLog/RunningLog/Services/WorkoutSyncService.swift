import Foundation
import os
import Supabase

/// Automatically syncs Vital/HealthKit workouts to training_logs so all runs
/// are visible to coaching analysis, weekly reports, and ACWR calculations.
@Observable
final class WorkoutSyncService {
    private(set) var isSyncing = false
    private(set) var lastSyncCount = 0
    private(set) var isBackfilling = false
    private(set) var backfillProgress: (done: Int, total: Int) = (0, 0)
    private(set) var lastBackfillCount = 0

    @MainActor
    func syncUnloggedWorkouts(workouts: [RunningWorkout]) async {
        guard !isSyncing else { return }

        let userId = AuthManager.shared.userId

        isSyncing = true
        defer { isSyncing = false }

        do {
            // Fetch existing training_logs for the last 90 days
            let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date()
            let existingLogs: [TrainingLog] = try await supabase
                .from("training_logs")
                .select()
                .gte("workout_date", value: ISO8601DateFormatter().string(from: cutoff))
                .execute()
                .value

            // Find workouts that don't have a matching training_log
            var inserts: [TrainingLogInsert] = []

            for workout in workouts {
                guard workout.distanceMiles > 0 else { continue }

                let alreadyLogged = existingLogs.contains { log in
                    guard let logDate = log.workoutDate else { return false }
                    return abs(logDate.timeIntervalSince(workout.startDate)) < 300
                        && abs((log.workoutDistanceMiles ?? 0) - workout.distanceMiles) < 0.2
                }

                if !alreadyLogged {
                    let paceMinutes = workout.pacePerMile
                    let paceSeconds = Int((paceMinutes * 60).rounded())
                    let paceStr = String(format: "%d:%02d", paceSeconds / 60, paceSeconds % 60)

                    let vitalId = workout.vitalWorkoutId ?? "sync-\(ISO8601DateFormatter().string(from: workout.startDate))"

                    // Fetch Vital stream and compute pace segments
                    var segments: [PaceSegment]?
                    var workoutType: String
                    if let streamId = workout.vitalWorkoutId {
                        let stream = await VitalManager.shared.fetchWorkoutStream(workoutId: streamId)
                        if let stream {
                            let paceSplits = VitalManager.shared.calculatePaceSplits(from: stream)
                            if !paceSplits.isEmpty {
                                segments = classifyPaceSplits(paceSplits, overallPace: paceMinutes)
                                workoutType = deriveWorkoutType(from: segments!, distance: workout.distanceMiles)
                            } else {
                                workoutType = classifyWorkout(distance: workout.distanceMiles, pace: paceMinutes * 60)
                            }
                        } else {
                            workoutType = classifyWorkout(distance: workout.distanceMiles, pace: paceMinutes * 60)
                        }
                    } else {
                        workoutType = classifyWorkout(distance: workout.distanceMiles, pace: paceMinutes * 60)
                    }

                    var insert = TrainingLogInsert()
                    insert.userId = userId
                    insert.workoutDate = workout.startDate
                    insert.workoutDistanceMiles = workout.distanceMiles
                    insert.workoutDurationMinutes = workout.durationMinutes
                    insert.workoutPacePerMile = paceStr
                    insert.workoutType = workoutType
                    insert.processingStatus = "completed"
                    insert.source = "auto_sync"
                    insert.vitalWorkoutId = vitalId
                    insert.paceSegments = segments

                    inserts.append(insert)
                }
            }

            if !inserts.isEmpty {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601

                struct InsertedId: Codable { let id: UUID }
                let inserted: [InsertedId] = try await supabase
                    .from("training_logs")
                    .insert(inserts, returning: .representation)
                    .select("id")
                    .execute()
                    .value

                lastSyncCount = inserts.count
                Log.coach.info("Auto-synced \(inserts.count) workouts to training_logs")

                // Trigger workout feature computation + post-run analysis for synced workouts
                let syncedIds = inserted.map { $0.id.uuidString }
                Task.detached {
                    await Self.triggerFeatureComputation(userId: userId)
                    for logId in syncedIds {
                        await Self.triggerPostRunAnalysis(userId: userId, trainingLogId: logId)
                    }
                }
            } else {
                lastSyncCount = 0
                Log.coach.debug("No new workouts to sync")
            }
        } catch {
            Log.coach.error("Workout sync failed: \(error.localizedDescription)")
            ErrorReporter.shared.report(error, context: "workout auto-sync")
        }
    }

    /// Remove auto_sync entry when a voice log is created for the same workout.
    @MainActor
    func removeAutoSyncEntry(forWorkoutDate date: Date, distance: Double) async {
        do {
            let windowStart = date.addingTimeInterval(-300)
            let windowEnd = date.addingTimeInterval(300)
            let fmt = ISO8601DateFormatter()

            try await supabase
                .from("training_logs")
                .delete()
                .eq("source", value: "auto_sync")
                .gte("workout_date", value: fmt.string(from: windowStart))
                .lte("workout_date", value: fmt.string(from: windowEnd))
                .execute()

            Log.coach.debug("Removed auto_sync entry for workout at \(date)")
        } catch {
            Log.coach.error("Failed to remove auto_sync entry: \(error.localizedDescription)")
        }
    }

    // MARK: - Backfill Pace Segments

    /// Find existing training_logs with a vital_workout_id but no pace_segments
    /// and re-fetch the Vital stream to compute them. Useful for logs created
    /// before the stream URL fix (was only fetching HR, missing distance/velocity).
    @MainActor
    func backfillPaceSegments() async {
        guard !isBackfilling else { return }
        isBackfilling = true
        backfillProgress = (0, 0)
        lastBackfillCount = 0
        defer { isBackfilling = false }

        struct LogRow: Codable {
            let id: UUID
            let vitalWorkoutId: String?
            let workoutDistanceMiles: Double?
            let workoutPacePerMile: String?
            let paceSegments: [PaceSegment]?

            enum CodingKeys: String, CodingKey {
                case id
                case vitalWorkoutId = "vital_workout_id"
                case workoutDistanceMiles = "workout_distance_miles"
                case workoutPacePerMile = "workout_pace_per_mile"
                case paceSegments = "pace_segments"
            }
        }

        struct UpdatePayload: Codable {
            let paceSegments: [PaceSegment]
            let workoutType: String

            enum CodingKeys: String, CodingKey {
                case paceSegments = "pace_segments"
                case workoutType = "workout_type"
            }
        }

        do {
            // Find candidates: auto_sync logs with a vital_workout_id but pace_segments is null/empty
            let cutoff = Calendar.current.date(byAdding: .day, value: -180, to: Date()) ?? Date()
            let logs: [LogRow] = try await supabase
                .from("training_logs")
                .select("id, vital_workout_id, workout_distance_miles, workout_pace_per_mile, pace_segments")
                .eq("source", value: "auto_sync")
                .gte("workout_date", value: ISO8601DateFormatter().string(from: cutoff))
                .execute()
                .value

            // Filter to ones missing segments and with a real vital ID (not "sync-..." fallback)
            let candidates = logs.filter { row in
                guard let vitalId = row.vitalWorkoutId, !vitalId.hasPrefix("sync-") else { return false }
                return (row.paceSegments?.isEmpty ?? true)
            }

            backfillProgress = (0, candidates.count)
            Log.coach.info("Backfill: found \(candidates.count) workouts to re-process")

            var successCount = 0

            for (index, row) in candidates.enumerated() {
                guard let vitalId = row.vitalWorkoutId else { continue }

                // Fetch the Vital stream
                guard let stream = await VitalManager.shared.fetchWorkoutStream(workoutId: vitalId) else {
                    backfillProgress = (index + 1, candidates.count)
                    continue
                }

                // Compute splits
                let paceSplits = VitalManager.shared.calculatePaceSplits(from: stream)
                guard !paceSplits.isEmpty else {
                    backfillProgress = (index + 1, candidates.count)
                    continue
                }

                // Parse overall pace from "M:SS" string
                let overallPace = parsePaceString(row.workoutPacePerMile ?? "0:00")

                let segments = classifyPaceSplits(paceSplits, overallPace: overallPace)
                let workoutType = deriveWorkoutType(from: segments, distance: row.workoutDistanceMiles ?? 0)

                let payload = UpdatePayload(paceSegments: segments, workoutType: workoutType)

                do {
                    try await supabase
                        .from("training_logs")
                        .update(payload)
                        .eq("id", value: row.id.uuidString)
                        .execute()
                    successCount += 1
                } catch {
                    Log.coach.error("Backfill update failed for \(row.id): \(error.localizedDescription)")
                }

                backfillProgress = (index + 1, candidates.count)
            }

            lastBackfillCount = successCount
            Log.coach.info("Backfill complete: \(successCount)/\(candidates.count) workouts updated")
        } catch {
            Log.coach.error("Backfill failed: \(error.localizedDescription)")
            await MainActor.run { ErrorReporter.shared.report(error, context: "pace segment backfill") }
        }
    }

    /// Parse "M:SS" pace string into total minutes (Double).
    private func parsePaceString(_ s: String) -> Double {
        let parts = s.split(separator: ":")
        guard parts.count == 2,
              let mins = Double(parts[0]),
              let secs = Double(parts[1])
        else { return 0 }
        return mins + secs / 60.0
    }

    // MARK: - Feature Computation Trigger

    private static func triggerFeatureComputation(userId: String) async {
        do {
            try await supabase.functions.invoke(
                "compute-workout-features",
                options: .init(body: ["user_id": userId])
            )
            Log.coach.info("Triggered workout feature computation for \(userId)")
        } catch {
            Log.coach.error("Feature computation trigger failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Post-Run Analysis Trigger

    private static func triggerPostRunAnalysis(userId: String, trainingLogId: String) async {
        do {
            let _: Void = try await supabase.functions.invoke(
                "post-run-analysis",
                options: .init(body: ["user_id": userId, "training_log_id": trainingLogId])
            )
            Log.coach.info("Triggered post-run analysis for \(trainingLogId)")
        } catch {
            Log.coach.error("Post-run analysis trigger failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Pace Segment Classification

    /// Public accessor for voice log enrichment pipeline.
    func classifyPaceSplitsPublic(_ splits: [PaceSplit], overallPace: Double) -> [PaceSegment] {
        classifyPaceSplits(splits, overallPace: overallPace)
    }

    /// Convert raw PaceSplits (hard/easy binary) into labeled PaceSegments with effort zones.
    /// Effort labels are derived from pace relative to the run's own data, not hardcoded thresholds.
    private func classifyPaceSplits(_ splits: [PaceSplit], overallPace: Double) -> [PaceSegment] {
        guard !splits.isEmpty else { return [] }

        // Compute median pace for easy vs hard segments
        let easyPaces = splits.enumerated()
            .filter { !isHardSegment(index: $0.offset, splits: splits) }
            .map(\.element.paceMinutes)
            .sorted()
        let hardPaces = splits.enumerated()
            .filter { isHardSegment(index: $0.offset, splits: splits) }
            .map(\.element.paceMinutes)
            .sorted()

        let medianEasyPace = easyPaces.isEmpty ? overallPace : easyPaces[easyPaces.count / 2]
        let medianHardPace = hardPaces.isEmpty ? overallPace : hardPaces[hardPaces.count / 2]

        // Pace gap between easy and hard determines intensity classification
        let paceGap = medianEasyPace - medianHardPace  // positive = hard is faster

        return splits.enumerated().map { index, split in
            let effort: String
            let isHard = isHardSegment(index: index, splits: splits)

            if isHard {
                // Classify hard segments by pace gap from easy pace
                if paceGap > 2.0 {
                    // Very large gap (>2 min/mi faster): interval work
                    effort = split.durationSeconds < 180 ? "interval" : "race_pace"
                } else if paceGap > 1.0 {
                    // Moderate gap (1-2 min/mi faster): threshold/tempo
                    effort = split.durationSeconds < 300 ? "threshold" : "tempo"
                } else {
                    // Small gap: moderate effort
                    effort = "moderate"
                }
            } else {
                // Easy segments: recovery if sandwiched between hard segments
                let hasHardBefore = splits[0..<index].contains { _ in true } &&
                    splits[0..<index].reversed().first.map { isHardSplit($0, medianHardPace: medianHardPace, medianEasyPace: medianEasyPace) } ?? false
                let hasHardAfter = index + 1 < splits.count &&
                    splits[(index + 1)...].first.map { isHardSplit($0, medianHardPace: medianHardPace, medianEasyPace: medianEasyPace) } ?? false

                effort = (hasHardBefore && hasHardAfter) ? "recovery" : "easy"
            }

            let totalSec = Int((split.paceMinutes * 60).rounded())
            let paceStr = String(format: "%d:%02d", totalSec / 60, totalSec % 60)

            return PaceSegment(
                effort: effort,
                distanceMiles: split.distanceMiles,
                durationSeconds: split.durationSeconds,
                pacePerMile: paceStr,
                avgHeartRate: split.avgHeartRate
            )
        }
    }

    /// Check if a split's pace is in the "hard" range relative to the run's pace distribution.
    /// Uses the fact that calculatePaceSplits alternates hard/easy: odd-numbered segments
    /// (1-indexed) in an interval workout are typically the work portions.
    private func isHardSegment(index: Int, splits: [PaceSplit]) -> Bool {
        guard splits.count > 2 else { return false }
        // calculatePaceSplits already groups by hard/easy — hard segments have faster pace
        // We identify them by comparing to the overall median
        let allPaces = splits.map(\.paceMinutes).sorted()
        let median = allPaces[allPaces.count / 2]
        return splits[index].paceMinutes < median * 0.95
    }

    private func isHardSplit(_ split: PaceSplit, medianHardPace: Double, medianEasyPace: Double) -> Bool {
        let midpoint = (medianHardPace + medianEasyPace) / 2.0
        return split.paceMinutes < midpoint
    }

    /// Derive overall workout type from pace segments rather than a single flat pace.
    private func deriveWorkoutType(from segments: [PaceSegment], distance: Double) -> String {
        if distance >= 10 { return "long_run" }

        let hardSegments = segments.filter { ["interval", "race_pace", "threshold", "tempo", "moderate"].contains($0.effort) }
        let hardMiles = hardSegments.reduce(0.0) { $0 + $1.distanceMiles }
        let totalMiles = segments.reduce(0.0) { $0 + $1.distanceMiles }

        guard totalMiles > 0 else { return "easy" }
        let hardRatio = hardMiles / totalMiles

        if hardRatio < 0.15 { return "easy" }

        // Use the dominant hard effort type
        let effortCounts = Dictionary(grouping: hardSegments, by: \.effort)
            .mapValues { $0.reduce(0.0) { $0 + $1.distanceMiles } }
        let dominant = effortCounts.max(by: { $0.value < $1.value })?.key ?? "easy"

        switch dominant {
        case "interval": return "interval"
        case "race_pace": return "race"
        case "threshold": return "threshold"
        case "tempo", "moderate": return "tempo"
        default: return "easy"
        }
    }

    // MARK: - Fallback Classification

    /// Fallback classification when stream data is unavailable.
    /// Uses distance and pace relative to the run's own data.
    private func classifyWorkout(distance: Double, pace: Double) -> String {
        if distance >= 10 { return "long_run" }
        if pace > 0, pace < 420 { return "interval" }
        if pace > 0, pace < 480 { return "tempo" }
        if distance < 4 { return "recovery" }
        return "easy"
    }
}

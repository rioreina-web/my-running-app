//
//  FitnessPredictorModels.swift
//  RunningLog
//
//  Data models for the fitness prediction feature.
//

import Foundation

// MARK: - FitnessPrediction

struct FitnessPrediction {
    let races: [RacePredictionItem]
    let fitnessSummary: String?
    let dataSources: DataSources
    let estimated10kPaceSeconds: Double
    let dataSource: String
    let trainingPaces: TrainingPacesSummary?
    let raceAnchor: RaceAnchorInfo?
    let trainingStimulus: TrainingStimulusInfo?
}

struct TrainingStimulusInfo {
    let weeklyMiles: Double
    let runsPerWeek: Double
    let stimulusMinutes: Double     // actual minutes at tempo/threshold/interval/race pace
    let structuredSessions: Int     // workouts with pace segments showing hard efforts
    let volumeTrend: Double         // recent 2wk vs prior 2wk volume ratio (>1 = increasing)
    let stimulusTrend: Double       // recent 2wk vs prior 2wk quality ratio (>1 = sharpening)
}

struct TrainingPacesSummary {
    // Canonical zones shown on the paces list (aerobic → race-pace).
    let easyPace: String       // "7:38/mi"
    let moderatePace: String   // "7:05/mi"
    let steadyPace: String     // "6:30/mi"
    let marathonPace: String   // "5:44/mi"  (MP)
    let hmpPace: String        // "5:30/mi"  (half-marathon pace)
    let tenKPace: String       // "5:15/mi"
    let fiveKPace: String      // "5:02/mi"

    // Legacy fields — retained so the alternate (currently unused) rebrand view
    // and any other callers still compile. Not shown on the redesigned list.
    let thresholdPace: String  // "5:22/mi"
    let intervalPace: String   // "5:02/mi"
    let longRunPace: String    // "6:50/mi"
}

struct RaceAnchorInfo {
    let raceType: String       // "10K"
    let time: String           // "31:21"
    let date: String           // "Feb 7, 2026"
    let weeksAgo: Int
}

// MARK: - RaceCandidate
//
// 2026-07-17 race gathering. A race-like run the nightly server job tagged on
// its training_logs row (`extracted_data.race_candidate`, status "pending").
// Surfaced for the athlete to confirm or dismiss — detection, not decision.

struct RaceCandidate: Identifiable {
    let id: UUID               // training_logs id
    let date: Date             // workout_date
    let raceLabel: String      // "10K" — server's display label
    let raceType: String       // server race_type key, e.g. "tenK"
    let finishTimeSeconds: Int
}

// MARK: - RacePredictionItem

struct RacePredictionItem: Identifiable {
    let id = UUID()
    let distance: String   // "5K", "10K", "HALF", "MARATHON"
    let time: String       // "19:45", "1:32:10" — unrounded raw point estimate
    let pace: String       // "6:22/mi"
    /// Half-window in seconds around the point estimate. Renderer shows
    /// `point ± rangeSeconds` rounded to whole minutes per CLAUDE.md hard rule #7.
    let pointSeconds: Int
    let rangeSeconds: Int
}

// MARK: - ConfidenceTier

/// Deterministic prediction confidence per CLAUDE.md hard rule #7. Lower-case
/// canonical — `DataSources.confidence` retains the legacy mixed-case string.
enum ConfidenceTier: String {
    case high, medium, low

    var displayLabel: String {
        switch self {
        case .high:   return "HIGH CONFIDENCE"
        case .medium: return "MEDIUM CONFIDENCE"
        case .low:    return "LOW CONFIDENCE"
        }
    }

    /// Half-window as a fraction of the point estimate. Calibrated so the
    /// high→medium gap on a 3:11 marathon is ~6 minutes (matches the tune-up
    /// race example in outputs/marathon-prediction-honesty.md).
    var rangeFraction: Double {
        switch self {
        case .high:   return 0.015
        case .medium: return 0.030
        case .low:    return 0.050
        }
    }
}

// MARK: - DataSources

struct DataSources {
    let workoutCount: Int
    let voiceLogCount: Int
    let hardEffortCount: Int
    let confidence: String        // legacy mixed-case
    let confidenceTier: ConfidenceTier
}

// MARK: - FitnessSnapshot

/// Row returned when reading from fitness_snapshots
struct FitnessSnapshot: Codable, Identifiable {
    let id: UUID
    let userId: String
    let predictedMileSeconds: Int
    let predicted5kSeconds: Int
    let predicted10kSeconds: Int
    let predictedHalfSeconds: Int
    let predictedMarathonSeconds: Int
    let estimated10kPaceSeconds: Double
    let confidence: String
    let dataSource: String
    let workoutCount: Int
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case predictedMileSeconds = "predicted_mile_seconds"
        case predicted5kSeconds = "predicted_5k_seconds"
        case predicted10kSeconds = "predicted_10k_seconds"
        case predictedHalfSeconds = "predicted_half_seconds"
        case predictedMarathonSeconds = "predicted_marathon_seconds"
        case estimated10kPaceSeconds = "estimated_10k_pace_seconds"
        case confidence
        case dataSource = "data_source"
        case workoutCount = "workout_count"
        case createdAt = "created_at"
    }
}

// MARK: - CanonicalFitnessRow

/// The server's canonical fitness answer, read from `fitness_snapshots`.
///
/// ONE SOURCE OF TRUTH (2026-08-17). The device used to compute its own
/// prediction from HealthKit + logs and render that. It sees none of what the
/// server sees — per-lap heat/grade normalization, conditions-normalized race
/// anchors, HR efficiency, the damped curve — so it produced a materially
/// different answer: on 2026-08-17 this screen showed a 33:44 10K / 2:36
/// marathon while the server held 32:00 / 2:29:13, off a race it had picked
/// by a different rule (Apr 14 33:04 vs the confirmed Feb 7 31:20).
/// The device stopped WRITING this table on 2026-08-17; this is the other
/// half — it stops computing a rival answer and renders the canonical one.
///
/// `anchorDate` is deliberately `String`, not `Date`: the column is a Postgres
/// DATE and the Supabase Swift SDK's `.value` decoder only parses full
/// ISO-8601 timestamps — decoding it as `Date` throws and takes the whole row
/// with it.
struct CanonicalFitnessRow: Codable {
    let predictedMileSeconds: Int?
    let predicted5kSeconds: Int?
    let predicted10kSeconds: Int?
    let predictedHalfSeconds: Int?
    let predictedMarathonSeconds: Int?
    let estimated10kPaceSeconds: Double?
    let confidence: String?
    let confidenceTier: String?
    let dataSource: String?
    let workoutCount: Int?
    let rangeMileSeconds: Int?
    let range5kSeconds: Int?
    let range10kSeconds: Int?
    let rangeHalfSeconds: Int?
    let rangeMarathonSeconds: Int?
    // Anchor — what the estimate rests on (migration 20260817210000).
    let anchorDistanceKey: String?
    let anchorRawSeconds: Int?
    let anchorNeutralSeconds: Int?
    let anchorDate: String?
    let anchorWeeksAgo: Double?
    // Context the device used to compute for itself (migration 20260817220000).
    let summary: String?
    let supportingTraining: SupportingTraining?

    /// The workings behind the estimate — which sessions it rests on, and
    /// which were read and set aside. Mirrors
    /// `FitnessPredictionResult.supportingTraining` on the server.
    struct SupportingTraining: Codable {
        let workMinutes: Int?
        let used: [Session]?
        let readButNotUsed: [Skipped]?

        struct Session: Codable {
            let date: String?
            let workMiles: Double?
            let repCount: Int?
            let meanHr: Int?
            let why: String?
        }
        struct Skipped: Codable {
            let date: String?
            let reason: String?
        }
    }

    enum CodingKeys: String, CodingKey {
        case predictedMileSeconds = "predicted_mile_seconds"
        case predicted5kSeconds = "predicted_5k_seconds"
        case predicted10kSeconds = "predicted_10k_seconds"
        case predictedHalfSeconds = "predicted_half_seconds"
        case predictedMarathonSeconds = "predicted_marathon_seconds"
        case estimated10kPaceSeconds = "estimated_10k_pace_seconds"
        case confidence
        case confidenceTier = "confidence_tier"
        case dataSource = "data_source"
        case workoutCount = "workout_count"
        case rangeMileSeconds = "range_mile_seconds"
        case range5kSeconds = "range_5k_seconds"
        case range10kSeconds = "range_10k_seconds"
        case rangeHalfSeconds = "range_half_seconds"
        case rangeMarathonSeconds = "range_marathon_seconds"
        case anchorDistanceKey = "anchor_distance_key"
        case anchorRawSeconds = "anchor_raw_seconds"
        case anchorNeutralSeconds = "anchor_neutral_seconds"
        case anchorDate = "anchor_date"
        case anchorWeeksAgo = "anchor_weeks_ago"
        case summary
        case supportingTraining = "supporting_training"
    }
}

// MARK: - FitnessSnapshotInsert

/// Insert payload (no id or created_at — server generates those)
struct FitnessSnapshotInsert: Codable {
    let userId: String
    let predictedMileSeconds: Int
    let predicted5kSeconds: Int
    let predicted10kSeconds: Int
    let predictedHalfSeconds: Int
    let predictedMarathonSeconds: Int
    let estimated10kPaceSeconds: Double
    let confidence: String
    let dataSource: String
    let workoutCount: Int
    // 2026-07-16: iOS previously omitted these — tier arrived NULL in the DB
    // and per-distance ranges were lost. Keep in sync with the edge function's
    // upsert (compute-fitness-snapshot/index.ts).
    let confidenceTier: String
    let rangeMileSeconds: Int?
    let range5kSeconds: Int?
    let range10kSeconds: Int?
    let rangeHalfSeconds: Int?
    let rangeMarathonSeconds: Int?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case predictedMileSeconds = "predicted_mile_seconds"
        case predicted5kSeconds = "predicted_5k_seconds"
        case predicted10kSeconds = "predicted_10k_seconds"
        case predictedHalfSeconds = "predicted_half_seconds"
        case predictedMarathonSeconds = "predicted_marathon_seconds"
        case estimated10kPaceSeconds = "estimated_10k_pace_seconds"
        case confidence
        case dataSource = "data_source"
        case workoutCount = "workout_count"
        case confidenceTier = "confidence_tier"
        case rangeMileSeconds = "range_mile_seconds"
        case range5kSeconds = "range_5k_seconds"
        case range10kSeconds = "range_10k_seconds"
        case rangeHalfSeconds = "range_half_seconds"
        case rangeMarathonSeconds = "range_marathon_seconds"
    }
}

// MARK: - WorkoutData

struct WorkoutData {
    let date: String
    let distanceMiles: Double
    let durationMinutes: Double
    let paceSecondsPerMile: Double
    let heartRateAvg: Int?
    let type: String
}

// MARK: - VoiceLogData

struct VoiceLogData {
    let date: String
    let notes: String
    let mood: String?
    let pacesMentioned: [String]
    // Linked workout data from training_logs
    let linkedWorkoutDistanceMiles: Double?
    let linkedWorkoutDurationMinutes: Double?
    // Structured workout data extracted from notes
    let extractedWorkout: ExtractedWorkoutData?
    // Pace segments from GPS stream analysis (stored in training_logs)
    let paceSegments: [PaceSegment]?
    // Observer-layer AI parse: type, pattern, equivalent race pace, etc.
    // When present, this is the highest-quality signal — used as fitness anchor.
    let parsedStructure: ParsedStructure?
}

// MARK: - ParsedStructure

/// Output of parse-workout-structure edge function. Matches the JSON schema
/// that function emits (see supabase/functions/parse-workout-structure/index.ts).
struct ParsedStructure: Codable {
    let type: String
    let pattern: String?
    let confidence: Double
    let workSummary: WorkSummary?
    let equivalentRacePace: EquivalentRacePace?

    enum CodingKeys: String, CodingKey {
        case type, pattern, confidence
        case workSummary = "work_summary"
        case equivalentRacePace = "equivalent_race_pace"
    }

    // The Observer can emit a partially-parsed structure where `confidence`
    // (or `type`) is null — e.g. a memo it couldn't score. A single null here
    // must not fail the decode of the entire history list, so we default
    // rather than throw. A null confidence decodes to 0.0, which correctly
    // fails the `>= 0.6` anchor guard downstream (we don't anchor on a parse
    // the model wasn't confident about). `pattern`, `workSummary`, and
    // `equivalentRacePace` are already optional and decode to nil as before.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decodeIfPresent(String.self, forKey: .type) ?? "unknown"
        pattern = try c.decodeIfPresent(String.self, forKey: .pattern)
        confidence = try c.decodeIfPresent(Double.self, forKey: .confidence) ?? 0.0
        workSummary = try c.decodeIfPresent(WorkSummary.self, forKey: .workSummary)
        equivalentRacePace = try c.decodeIfPresent(EquivalentRacePace.self, forKey: .equivalentRacePace)
    }

    struct WorkSummary: Codable {
        let totalDistanceMi: Double?
        let totalDurationS: Double?
        let avgWorkPacePerMile: String?
        let peakSustainedPacePerMile: String?

        enum CodingKeys: String, CodingKey {
            case totalDistanceMi = "total_distance_mi"
            case totalDurationS = "total_duration_s"
            case avgWorkPacePerMile = "avg_work_pace_per_mile"
            case peakSustainedPacePerMile = "peak_sustained_pace_per_mile"
        }
    }

    struct EquivalentRacePace: Codable {
        let distanceKey: String          // "mile" | "fiveK" | "tenK" | "halfMarathon" | "marathon"
        let pacePerMile: String          // "M:SS"
        let reasoning: String?

        enum CodingKeys: String, CodingKey {
            case distanceKey = "distance_key"
            case pacePerMile = "pace_per_mile"
            case reasoning
        }
    }
}

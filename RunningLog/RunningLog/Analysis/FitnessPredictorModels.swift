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
    let easyPace: String       // "7:10 – 7:38/mi"
    let marathonPace: String   // "5:44/mi"
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

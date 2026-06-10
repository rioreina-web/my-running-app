import Foundation

// MARK: - Pace Segment

/// A single effort segment within a run (e.g., warmup, threshold portion, cooldown).
/// Derived from GPS/watch stream data at sync time.
struct PaceSegment: Codable, Identifiable {
    var id: UUID { UUID() }
    let effort: String          // "easy", "moderate", "threshold", "tempo", "interval", "race_pace", "recovery"
    let distanceMiles: Double
    let durationSeconds: Double
    let pacePerMile: String     // formatted "M:SS"
    let avgHeartRate: Int?

    enum CodingKeys: String, CodingKey {
        case effort
        case distanceMiles = "distance_miles"
        case durationSeconds = "duration_seconds"
        case pacePerMile = "pace_per_mile"
        case avgHeartRate = "avg_heart_rate"
    }
}

// MARK: - TrainingLog

struct TrainingLog: Codable, Identifiable {
    let id: UUID
    let createdAt: Date
    let audioUrl: String?
    let notes: String?
    let cleanedNotes: String?
    let mood: String?
    let workoutDate: Date?
    let workoutDistanceMiles: Double?
    let workoutDurationMinutes: Double?
    let processingStatus: String?
    let processingError: String?
    let processingAttempts: Int?
    let transcriptUrl: String?
    let coachInsight: String?
    let workoutNotes: String?
    let workoutPacePerMile: String?
    let workoutType: String?
    let source: String?
    let vitalWorkoutId: String?
    let paceSegments: [PaceSegment]?
    let parsedStructure: ParsedStructure?

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case audioUrl = "audio_url"
        case notes
        case cleanedNotes = "cleaned_notes"
        case mood
        case workoutDate = "workout_date"
        case workoutDistanceMiles = "workout_distance_miles"
        case workoutDurationMinutes = "workout_duration_minutes"
        case processingStatus = "processing_status"
        case processingError = "processing_error"
        case processingAttempts = "processing_attempts"
        case transcriptUrl = "transcript_url"
        case coachInsight = "coach_insight"
        case workoutNotes = "workout_notes"
        case workoutPacePerMile = "workout_pace_per_mile"
        case workoutType = "workout_type"
        case source
        case vitalWorkoutId = "vital_workout_id"
        case paceSegments = "pace_segments"
        case parsedStructure = "parsed_structure"
    }

    // MARK: - Source

    var isAutoSynced: Bool {
        source == "auto_sync"
    }

    // MARK: - Processing Status

    var isPending: Bool {
        processingStatus == "pending" || processingStatus == "processing"
    }

    var isFailed: Bool {
        processingStatus == "failed"
    }

    var isCompleted: Bool {
        processingStatus == "completed"
    }

    // MARK: - Workout Info

    var hasLinkedWorkout: Bool {
        workoutDate != nil && workoutDistanceMiles != nil
    }

    var displayDate: Date {
        workoutDate ?? createdAt
    }

    var formattedWorkoutDistance: String? {
        guard let miles = workoutDistanceMiles else { return nil }
        if miles == miles.rounded() {
            return String(format: "%.0f", miles)
        } else if (miles * 10).rounded() == miles * 10 {
            return String(format: "%.1f", miles)
        }
        return String(format: "%.2f", miles)
    }

    var formattedWorkoutDuration: String? {
        guard let minutes = workoutDurationMinutes else { return nil }
        let totalSeconds = Int((minutes * 60).rounded())
        let hours = totalSeconds / 3600
        let mins = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, mins, secs)
        }
        return String(format: "%d:%02d", mins, secs)
    }

    var formattedWorkoutPace: String? {
        guard let miles = workoutDistanceMiles, let minutes = workoutDurationMinutes, miles > 0 else { return nil }
        let totalSeconds = Int(((minutes / miles) * 60).rounded())
        let paceMinutes = totalSeconds / 60
        let paceSeconds = totalSeconds % 60
        return String(format: "%d:%02d", paceMinutes, paceSeconds)
    }

    var workoutTypeLabel: String? {
        guard let type = workoutType else { return nil }
        switch type {
        case "easy": return "Easy"
        case "tempo": return "Tempo"
        case "interval": return "Intervals"
        case "long_run": return "Long Run"
        case "recovery": return "Recovery"
        case "race": return "Race"
        case "other": return "Workout"
        default: return nil
        }
    }
}

// MARK: - TrainingLogInsert

struct TrainingLogInsert: Codable {
    var userId: String?
    var audioUrl: String?
    var notes: String?
    var workoutDate: Date?
    var workoutDistanceMiles: Double?
    var workoutDurationMinutes: Double?
    var workoutPacePerMile: String?
    var workoutType: String?
    var processingStatus: String?
    var source: String?
    var vitalWorkoutId: String?
    var paceSegments: [PaceSegment]?
    var externalStreams: ExternalStreamsPayload?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case audioUrl = "audio_url"
        case notes
        case workoutDate = "workout_date"
        case workoutDistanceMiles = "workout_distance_miles"
        case workoutDurationMinutes = "workout_duration_minutes"
        case workoutPacePerMile = "workout_pace_per_mile"
        case workoutType = "workout_type"
        case processingStatus = "processing_status"
        case source
        case vitalWorkoutId = "vital_workout_id"
        case paceSegments = "pace_segments"
        case externalStreams = "external_streams"
    }
}

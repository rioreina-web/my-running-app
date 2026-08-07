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

    init(effort: String, distanceMiles: Double, durationSeconds: Double,
         pacePerMile: String, avgHeartRate: Int?) {
        self.effort = effort
        self.distanceMiles = distanceMiles
        self.durationSeconds = durationSeconds
        self.pacePerMile = pacePerMile
        self.avgHeartRate = avgHeartRate
    }

    /// Decodes leniently. Rep-shaped segments written by the structure parser
    /// carry only `{effort, pace_per_mile, distance_miles}` — no duration. A
    /// strict decode there throws, and because the journal decodes all 50 rows
    /// as one array, a single such segment empties the entire feed. Duration is
    /// recoverable from pace × distance, so recover it instead of failing.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        effort = (try? c.decode(String.self, forKey: .effort)) ?? "easy"
        distanceMiles = (try? c.decode(Double.self, forKey: .distanceMiles)) ?? 0
        pacePerMile = (try? c.decode(String.self, forKey: .pacePerMile)) ?? ""
        avgHeartRate = try? c.decodeIfPresent(Int.self, forKey: .avgHeartRate)

        if let seconds = try? c.decode(Double.self, forKey: .durationSeconds) {
            durationSeconds = seconds
        } else if let paceSec = PaceSegment.paceSeconds(from: pacePerMile), distanceMiles > 0 {
            durationSeconds = paceSec * distanceMiles
        } else {
            durationSeconds = 0
        }
    }

    /// "M:SS" (or "H:MM:SS") per-mile pace → seconds. nil if unparseable.
    static func paceSeconds(from pace: String) -> Double? {
        let parts = pace.split(separator: ":").compactMap { Double($0) }
        guard parts.count >= 2 else { return nil }
        return parts.count == 3
            ? parts[0] * 3600 + parts[1] * 60 + parts[2]
            : parts[0] * 60 + parts[1]
    }
}

// MARK: - Lossy row decoding

/// Wraps a row so a decode failure yields `nil` instead of throwing. Decoding a
/// list as `[TrainingLog]` is all-or-nothing: one malformed row anywhere in the
/// page throws and the caller sees an empty feed plus an error. Decode as
/// `[Failable<TrainingLog>]` and `compactMap` so a bad row costs one row.
struct Failable<T: Decodable>: Decodable {
    let value: T?

    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
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
    /// Optional athlete-authored entry title. Shown as the journal entry
    /// header when set; the entry falls back to the day-of-week/date when
    /// this is nil or empty. Defaulted so existing memberwise-init call
    /// sites (and tests) keep compiling without passing it.
    var title: String? = nil

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
        case title
    }

    /// Trimmed title if the athlete set a non-empty one, else nil. Views use
    /// this to decide whether to show a custom header or fall back to the date.
    var displayTitle: String? {
        guard let t = title?.trimmingCharacters(in: .whitespacesAndNewlines),
              !t.isEmpty else { return nil }
        return t
    }

    /// The workout itself, as a concise journal title, when the athlete hasn't
    /// set their own. Uses the workout-type label ("Intervals", "Easy", "Long
    /// Run") — clean and reliable, and editable if they want something sharper
    /// ("8×200m"). nil for a row with no workout type (a pure voice memo / rest
    /// day), where the header falls back to the day-of-week.
    var workoutTitle: String? { workoutTypeLabel }

    /// The header shown for this entry: the athlete's own title, else the
    /// workout, else the day-of-week (resolved by the view).
    var resolvedTitle: String? { displayTitle ?? workoutTitle }

    // MARK: - Source

    var isAutoSynced: Bool {
        source == "auto_sync"
    }

    // MARK: - Processing Status

    var isPending: Bool {
        processingStatus == "pending" || processingStatus == "processing"
    }

    /// Two-stage reveal: the transcript is on the row (`cleanedNotes` holds the
    /// athlete's raw words) but the AI analysis (mood, niggles, structure) is
    /// still running. The journal renders these as normal entries — the words
    /// appear ~6-9s in; the analysis fills in when the status flips to
    /// `completed`.
    var isTranscribed: Bool {
        processingStatus == "transcribed"
    }

    /// Still somewhere in the pipeline (queued, processing, or transcribed-but-
    /// unanalyzed). Used by stale-retry sweeps — NOT by row rendering, which
    /// deliberately treats `transcribed` as displayable.
    var isInFlight: Bool {
        isPending || isTranscribed
    }

    var isFailed: Bool {
        processingStatus == "failed"
    }

    var isCompleted: Bool {
        processingStatus == "completed"
    }

    // MARK: - Failure Classification

    /// Why a voice memo failed to process. Derived from `processingError`
    /// text so we can show the user the right recovery copy without a
    /// schema change. Network failures mean "we couldn't reach the
    /// server" (recording is safe, retry when back online); transcription
    /// failures mean the audio uploaded but the AI couldn't process it.
    enum FailureKind {
        case network
        case transcription
        case unknown
    }

    var failureKind: FailureKind {
        guard isFailed else { return .unknown }
        let error = (processingError ?? "").lowercased()

        let networkSignals = [
            "network", "timeout", "timed out", "connection", "offline",
            "unreachable", "could not connect", "failed to fetch",
            "download", "dns", "socket", "econn", "502", "503", "504",
            "gateway"
        ]
        if networkSignals.contains(where: { error.contains($0) }) {
            return .network
        }

        let transcriptionSignals = [
            "transcri", "audio", "gemini", "parse", "json", "mood",
            "missing", "empty", "analysis", "response", "no speech",
            "inaudible", "format"
        ]
        if transcriptionSignals.contains(where: { error.contains($0) }) {
            return .transcription
        }

        return .unknown
    }

    /// Short, human headline for the failed card. No jargon, no error codes.
    var failureHeadline: String {
        switch failureKind {
        case .network:
            return "Couldn't reach the server"
        case .transcription:
            return "Couldn't process this memo"
        case .unknown:
            return "Processing failed"
        }
    }

    /// One reassuring line: the recording is safe, here's what to do.
    var failureDetail: String {
        switch failureKind {
        case .network:
            return "Your recording is saved. Check your connection, then tap to retry."
        case .transcription:
            return "The audio uploaded but we couldn't transcribe it. Tap to try again."
        case .unknown:
            return "Your recording is saved. Tap to retry."
        }
    }

    /// Verb on the retry control, matched to what actually failed.
    var retryActionLabel: String {
        switch failureKind {
        case .network:
            return "Retry upload"
        case .transcription, .unknown:
            return "Retry transcription"
        }
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

    /// Delegates to `WorkoutLabel` (2026-08-07). This was the fourth switch
    /// over `workout_type` in the app — `WorkoutLabel.swift` was written to be
    /// the last one and this copy survived it, missing the whole race-pace half
    /// of the taxonomy (MP / HMP / LT / 10K / 5K / 3K / Mile all fell through
    /// to `nil`, so a run typed with any of them showed no title at all).
    ///
    /// The `nil` for a `nil`/blank type is preserved deliberately —
    /// `resolvedTitle` falls back to the weekday on nil, and
    /// `WorkoutLabel.display` returns "Run" rather than nil, which would title
    /// every untyped entry "Run".
    var workoutTypeLabel: String? {
        guard let type = workoutType?.trimmingCharacters(in: .whitespacesAndNewlines),
              !type.isEmpty
        else { return nil }
        return WorkoutLabel.display(type)
    }

    // MARK: - Manual entry

    /// True for workouts the athlete typed in by hand (vs. HealthKit/Strava/
    /// voice). Only manual rows are editable in ManualWorkoutView.
    var isManual: Bool {
        source == "manual"
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

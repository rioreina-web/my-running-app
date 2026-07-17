//
//  ModelOfYouState.swift
//  RunningLog
//
//  WS6 — "model of you" surface. A fuller projection of `athlete_state`
//  than TrendsAthleteState, for the redesigned Coach screen (the cards in
//  outputs/model-of-you-mock.html). Reads athlete_state directly — the table
//  has a "Users read own athlete state" RLS SELECT policy, so the auth'd
//  client is scoped to the signed-in user automatically.
//
//  Property names are snake_case to match the JSON columns 1:1 (the SDK's
//  decoder is NOT convertFromSnakeCase — see TrendsAthleteState). All fields
//  optional so a thin/partial state never fails to decode.
//

import Foundation
import Supabase
import os

struct ModelOfYouState: Decodable {
    var experience_level: String?
    var current_phase: String?
    var fitness_trend: String?
    var last_mood: String?
    var last_readiness_score: Int?
    var rolling_7d_miles: Double?
    var rolling_28d_miles: Double?
    var weekly_avg_miles: Double?

    var load_distribution: LoadDistribution?
    var fitness_prediction: FitnessPrediction?
    var execution: [ExecutionItem]?
    var patterns: [Pattern]?
    var niggle_recurrence: [Niggle]?
    var active_injuries: [ActiveInjury]?
    var possible_injuries: [PossibleInjury]?
    var data_gaps: [DataGap]?

    // MARK: Nested shapes

    struct LoadDistribution: Decodable {
        var volume_x_intensity_7d: Double?
        var volume_x_intensity_28d: Double?
        var zone_pct_7d: ZonePct?
        var monotony_7d: Double?
        var strain_7d: Double?
        var effort_distribution: String?
        // WS3 additions (may be absent on older rows)
        var load_trend: String?
        var load_vs_chronic_pct: Double?
        var recovery_read: RecoveryRead?
    }

    struct RecoveryRead: Decodable {
        var down_week: Bool?
        var hard_sessions_28d: Int?
        var avg_days_between_hard: Int?
    }

    struct ZonePct: Decodable {
        var easy: Double?
        var moderate: Double?
        var threshold: Double?
        var hard: Double?
    }

    struct FitnessPrediction: Decodable {
        var ranges: [String: RaceRange]?
        var confidence_tier: String?
        var workout_count: Int?
    }

    struct RaceRange: Decodable {
        var low: Double?
        var high: Double?
        var point: Double?
    }

    struct ExecutionItem: Decodable {
        var date: String?
        var type: String?
        var structure: String?
        var shape: String?
        var rep_count: Int?
        var rep_paces: [String]?
        var fade_pct: Double?
        var hr_drift_pct: Double?
    }

    struct Pattern: Decodable {
        var statement: String?
        var confidence: String?
        var evidence: String?
    }

    struct Niggle: Decodable {
        var body_area: String?
        var occurrences: Int?
        var first_seen: String?
        var last_seen: String?
        var worst_severity: String?
    }

    struct ActiveInjury: Decodable {
        var body_area: String?
        var status: String?
        var severity: Int?
    }

    struct PossibleInjury: Decodable {
        var date: String?
        var body_area: String?
        var severity_hint: String?
        var excerpt: String?
    }

    struct DataGap: Decodable {
        var gap: String?
        var detail: String?
    }

    // MARK: Fetch

    static func fetch() async -> ModelOfYouState? {
        do {
            let rows: [ModelOfYouState] = try await supabase
                .from("athlete_state")
                .select("""
                    experience_level, current_phase, fitness_trend, last_mood, \
                    last_readiness_score, rolling_7d_miles, rolling_28d_miles, \
                    weekly_avg_miles, load_distribution, fitness_prediction, \
                    execution, patterns, niggle_recurrence, active_injuries, \
                    possible_injuries, data_gaps
                """)
                .limit(1)
                .execute()
                .value
            return rows.first
        } catch {
            Log.coach.error("ModelOfYouState fetch failed: \(error)")
            return nil
        }
    }
}

// MARK: - Display helpers

extension ModelOfYouState.RaceRange {
    /// "32:10–32:48" or "32:29" when collapsed. nil when no data.
    var formattedRange: String? {
        guard let lo = low, lo > 0 else { return nil }
        let hi = high ?? lo
        if abs(hi - lo) < 1 { return Self.hms(lo) }
        return "\(Self.hms(lo))–\(Self.hms(hi))"
    }
    static func hms(_ seconds: Double) -> String {
        let t = Int(seconds.rounded())
        let h = t / 3600, m = (t % 3600) / 60, s = t % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }
}

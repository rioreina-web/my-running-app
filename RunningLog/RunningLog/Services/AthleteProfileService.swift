//
//  AthleteProfileService.swift
//  RunningLog
//
//  Builds and caches a comprehensive athlete profile from up to 5 years
//  of training history. The profile is recency-weighted and used as
//  context for all AI coaching features.
//

import Foundation
import os

// MARK: - Athlete Profile Response

struct AthleteProfileResponse: Codable {
    let profile: AthleteProfileData
    let cached: Bool
    let processingTime: Int?

    enum CodingKeys: String, CodingKey {
        case profile
        case cached
        case processingTime = "processing_time"
    }
}

struct AthleteProfileData: Codable {
    let builtAt: String
    let dataSpanMonths: Int
    let totalLogs: Int
    let volume: [VolumeTier]
    let volumeSummary: VolumeSummary
    let pace: [PaceTier]
    let performanceTrajectory: [PerformanceSnapshot]
    let injuryHistory: [InjuryRecord]
    let recovery: RecoveryProfile
    let preferences: TrainingPreferences
    let biomechanics: BiomechanicsSummary?
    let goalHistory: GoalHistorySummary

    enum CodingKeys: String, CodingKey {
        case builtAt = "built_at"
        case dataSpanMonths = "data_span_months"
        case totalLogs = "total_logs"
        case volume
        case volumeSummary = "volume_summary"
        case pace
        case performanceTrajectory = "performance_trajectory"
        case injuryHistory = "injury_history"
        case recovery
        case preferences
        case biomechanics
        case goalHistory = "goal_history"
    }
}

struct VolumeTier: Codable {
    let tier: String
    let weight: Double
    let totalRuns: Int
    let totalMiles: Double
    let avgWeeklyMiles: Double
    let peakWeeklyMiles: Double
    let avgRunsPerWeek: Double
    let avgRunDistance: Double

    enum CodingKeys: String, CodingKey {
        case tier, weight
        case totalRuns = "total_runs"
        case totalMiles = "total_miles"
        case avgWeeklyMiles = "avg_weekly_miles"
        case peakWeeklyMiles = "peak_weekly_miles"
        case avgRunsPerWeek = "avg_runs_per_week"
        case avgRunDistance = "avg_run_distance"
    }
}

struct VolumeSummary: Codable {
    let currentWeeklyAvg: Double
    let peakWeeklyEver: Double
    let longestRunEver: Double
    let totalLifetimeMiles: Double
    let consistencyScore: Double

    enum CodingKeys: String, CodingKey {
        case currentWeeklyAvg = "current_weekly_avg"
        case peakWeeklyEver = "peak_weekly_ever"
        case longestRunEver = "longest_run_ever"
        case totalLifetimeMiles = "total_lifetime_miles"
        case consistencyScore = "consistency_score"
    }
}

struct PaceTier: Codable {
    let tier: String
    let avgPaceSecondsPerMile: Int
    let easyPace: Int
    let fastestPace: Int

    enum CodingKeys: String, CodingKey {
        case tier
        case avgPaceSecondsPerMile = "avg_pace_seconds_per_mile"
        case easyPace = "easy_pace"
        case fastestPace = "fastest_pace"
    }
}

struct PerformanceSnapshot: Codable {
    let date: String
    let predicted5k: String
    let predicted10k: String
    let predictedHalf: String
    let predictedMarathon: String

    enum CodingKeys: String, CodingKey {
        case date
        case predicted5k = "predicted_5k"
        case predicted10k = "predicted_10k"
        case predictedHalf = "predicted_half"
        case predictedMarathon = "predicted_marathon"
    }
}

struct InjuryRecord: Codable {
    let bodyArea: String
    let side: String
    let occurrences: Int
    let mostRecent: String
    let avgSeverity: Double
    let isRecurring: Bool

    enum CodingKeys: String, CodingKey {
        case bodyArea = "body_area"
        case side
        case occurrences
        case mostRecent = "most_recent"
        case avgSeverity = "avg_severity"
        case isRecurring = "is_recurring"
    }
}

struct RecoveryProfile: Codable {
    let avgMoodPositivePct: Double
    let fatigueAfterHighVolumeWeeks: Bool
    let typicalEasyDayFrequency: Double

    enum CodingKeys: String, CodingKey {
        case avgMoodPositivePct = "avg_mood_positive_pct"
        case fatigueAfterHighVolumeWeeks = "fatigue_after_high_volume_weeks"
        case typicalEasyDayFrequency = "typical_easy_day_frequency"
    }
}

struct TrainingPreferences: Codable {
    let mostCommonWorkoutTypes: [String]
    let avgLongRunDistance: Double
    let preferredRunDays: [String]
    let trainsConsecutively: Bool

    enum CodingKeys: String, CodingKey {
        case mostCommonWorkoutTypes = "most_common_workout_types"
        case avgLongRunDistance = "avg_long_run_distance"
        case preferredRunDays = "preferred_run_days"
        case trainsConsecutively = "trains_consecutively"
    }
}

struct BiomechanicsSummary: Codable {
    let latestScore: Double
    let trend: String
    let keyFindings: [String]

    enum CodingKeys: String, CodingKey {
        case latestScore = "latest_score"
        case trend
        case keyFindings = "key_findings"
    }
}

struct GoalHistorySummary: Codable {
    let completed: Int
    let active: Int
    let raceDistancesTargeted: [String]

    enum CodingKeys: String, CodingKey {
        case completed, active
        case raceDistancesTargeted = "race_distances_targeted"
    }
}

// MARK: - AthleteProfileService

@Observable
final class AthleteProfileService {
    var profile: AthleteProfileData?
    var isLoading = false
    var error: String?

    /// Cached profile data, persisted in UserDefaults
    private static let cacheKey = "athlete_profile_cache"
    private static let cacheTimestampKey = "athlete_profile_cache_timestamp"

    init() {
        loadFromLocalCache()
    }

    /// Build or fetch the athlete profile. Uses 24-hour server-side cache.
    @MainActor
    func fetchProfile(forceRebuild: Bool = false) async {
        isLoading = true
        error = nil

        do {
            let body: [String: Any] = ["force_rebuild": forceRebuild]
            let data = try await callEdgeFunction(name: "build-athlete-profile", body: body)
            let response = try JSONDecoder().decode(AthleteProfileResponse.self, from: data)
            profile = response.profile
            saveToLocalCache(data: data)
            Log.app.info("Athlete profile \(response.cached ? "loaded from cache" : "rebuilt") in \(response.processingTime ?? 0)ms")
        } catch {
            Log.app.error("Failed to fetch athlete profile: \(error)")
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    /// Returns a concise text summary of the profile for injecting into AI prompts.
    /// Returns nil if no profile is available.
    var profileContextForAI: String? {
        guard let profile else { return nil }

        var parts: [String] = []
        parts.append("ATHLETE PROFILE (\(profile.dataSpanMonths)mo data, \(profile.totalLogs) runs)")

        // Volume
        let vs = profile.volumeSummary
        parts.append("Volume: \(vs.currentWeeklyAvg) mi/wk avg, peak \(vs.peakWeeklyEver) mi/wk, longest \(vs.longestRunEver) mi, \(Int(vs.consistencyScore * 100))% consistent")

        // Pace evolution
        if let recent = profile.pace.first(where: { $0.tier == "last_6_months" }) {
            parts.append("Recent pace: avg \(formatPace(recent.avgPaceSecondsPerMile)), easy \(formatPace(recent.easyPace)), fast \(formatPace(recent.fastestPace))")
        }

        // Injuries
        let recurring = profile.injuryHistory.filter(\.isRecurring)
        if !recurring.isEmpty {
            let injuryStr = recurring.map { "\($0.bodyArea) (\($0.occurrences)x)" }.joined(separator: ", ")
            parts.append("Recurring injuries: \(injuryStr)")
        }

        // Preferences
        if !profile.preferences.mostCommonWorkoutTypes.isEmpty {
            parts.append("Prefers: \(profile.preferences.mostCommonWorkoutTypes.joined(separator: ", "))")
        }

        return parts.joined(separator: " | ")
    }

    // MARK: - Local Cache

    private func loadFromLocalCache() {
        guard let data = UserDefaults.standard.data(forKey: Self.cacheKey) else { return }
        do {
            let response = try JSONDecoder().decode(AthleteProfileResponse.self, from: data)
            profile = response.profile
        } catch {
            Log.app.warning("Failed to load cached athlete profile: \(error)")
        }
    }

    private func saveToLocalCache(data: Data) {
        UserDefaults.standard.set(data, forKey: Self.cacheKey)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.cacheTimestampKey)
    }

    private func formatPace(_ seconds: Int) -> String {
        PaceCalculator.formatPaceWithUnit(Double(seconds))
    }
}

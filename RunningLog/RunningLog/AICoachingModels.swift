//
//  AICoachingModels.swift
//  RunningLog
//
//  Models for AI-powered coaching analysis and recommendations.
//

import Foundation
import SwiftUI

// MARK: - Training Analysis Request

/// Data sent to AI for analysis
struct TrainingAnalysisRequest: Codable {
    let planSummary: PlanSummary
    let recentWorkouts: [WorkoutSummary]
    let scheduledWorkouts: [ScheduledWorkoutSummary]
    let athleteProfile: AthleteProfile

    enum CodingKeys: String, CodingKey {
        case planSummary = "plan_summary"
        case recentWorkouts = "recent_workouts"
        case scheduledWorkouts = "scheduled_workouts"
        case athleteProfile = "athlete_profile"
    }
}

struct PlanSummary: Codable {
    let name: String
    let goalRace: String
    let goalTime: String
    let goalPace: String
    let totalWeeks: Int
    let currentWeek: Int
    let currentPhase: String
    let daysUntilRace: Int

    enum CodingKeys: String, CodingKey {
        case name
        case goalRace = "goal_race"
        case goalTime = "goal_time"
        case goalPace = "goal_pace"
        case totalWeeks = "total_weeks"
        case currentWeek = "current_week"
        case currentPhase = "current_phase"
        case daysUntilRace = "days_until_race"
    }
}

struct WorkoutSummary: Codable {
    let date: String
    let type: String
    let plannedDistance: Double?
    let actualDistance: Double
    let plannedPace: String?
    let actualPace: String
    let duration: Int // seconds
    let heartRateAvg: Int?
    let wasPlanned: Bool
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case date
        case type
        case plannedDistance = "planned_distance"
        case actualDistance = "actual_distance"
        case plannedPace = "planned_pace"
        case actualPace = "actual_pace"
        case duration
        case heartRateAvg = "heart_rate_avg"
        case wasPlanned = "was_planned"
        case notes
    }
}

struct ScheduledWorkoutSummary: Codable {
    let date: String
    let type: String
    let distance: Double
    let description: String
    let status: String
}

struct AthleteProfile: Codable {
    let baseWeeklyMileage: Double
    let currentWeeklyMileage: Double
    let recentTrend: String // "increasing", "stable", "decreasing"
    let missedWorkoutsLast2Weeks: Int
    let completionRate: Double // 0.0 - 1.0

    enum CodingKeys: String, CodingKey {
        case baseWeeklyMileage = "base_weekly_mileage"
        case currentWeeklyMileage = "current_weekly_mileage"
        case recentTrend = "recent_trend"
        case missedWorkoutsLast2Weeks = "missed_workouts_last_2_weeks"
        case completionRate = "completion_rate"
    }
}

// MARK: - AI Analysis Response

struct TrainingAnalysisResponse: Codable {
    let summary: String
    let insights: [CoachingInsight]
    let recommendations: [CoachingRecommendation]
    let weeklyFocus: String
    let alertLevel: AlertLevel
    let encouragement: String

    enum CodingKeys: String, CodingKey {
        case summary
        case insights
        case recommendations
        case weeklyFocus = "weekly_focus"
        case alertLevel = "alert_level"
        case encouragement
    }
}

struct CoachingInsight: Codable, Identifiable {
    let id: UUID
    let category: InsightCategory
    let title: String
    let detail: String
    let metric: String?
    let trend: TrendDirection?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = UUID()
        self.category = try container.decode(InsightCategory.self, forKey: .category)
        self.title = try container.decode(String.self, forKey: .title)
        self.detail = try container.decode(String.self, forKey: .detail)
        self.metric = try container.decodeIfPresent(String.self, forKey: .metric)
        self.trend = try container.decodeIfPresent(TrendDirection.self, forKey: .trend)
    }

    init(category: InsightCategory, title: String, detail: String, metric: String? = nil, trend: TrendDirection? = nil) {
        self.id = UUID()
        self.category = category
        self.title = title
        self.detail = detail
        self.metric = metric
        self.trend = trend
    }

    enum CodingKeys: String, CodingKey {
        case category, title, detail, metric, trend
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(category, forKey: .category)
        try container.encode(title, forKey: .title)
        try container.encode(detail, forKey: .detail)
        try container.encodeIfPresent(metric, forKey: .metric)
        try container.encodeIfPresent(trend, forKey: .trend)
    }
}

enum InsightCategory: String, Codable {
    case volume
    case intensity
    case consistency
    case recovery
    case pacing
    case fitness

    var icon: String {
        switch self {
        case .volume: return "chart.bar.fill"
        case .intensity: return "flame.fill"
        case .consistency: return "checkmark.circle.fill"
        case .recovery: return "bed.double.fill"
        case .pacing: return "speedometer"
        case .fitness: return "heart.fill"
        }
    }

    var color: Color {
        switch self {
        case .volume: return Color.drip.energized
        case .intensity: return Color.drip.coral
        case .consistency: return Color.drip.positive
        case .recovery: return Color.drip.textSecondary
        case .pacing: return Color.drip.coralLight
        case .fitness: return Color.red
        }
    }
}

enum TrendDirection: String, Codable {
    case up
    case down
    case stable

    var icon: String {
        switch self {
        case .up: return "arrow.up.right"
        case .down: return "arrow.down.right"
        case .stable: return "arrow.right"
        }
    }

    var color: Color {
        switch self {
        case .up: return Color.drip.positive
        case .down: return Color.drip.coral
        case .stable: return Color.drip.textSecondary
        }
    }
}

struct CoachingRecommendation: Codable, Identifiable {
    let id: UUID
    let priority: RecommendationPriority
    let title: String
    let action: String
    let rationale: String

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = UUID()
        self.priority = try container.decode(RecommendationPriority.self, forKey: .priority)
        self.title = try container.decode(String.self, forKey: .title)
        self.action = try container.decode(String.self, forKey: .action)
        self.rationale = try container.decode(String.self, forKey: .rationale)
    }

    init(priority: RecommendationPriority, title: String, action: String, rationale: String) {
        self.id = UUID()
        self.priority = priority
        self.title = title
        self.action = action
        self.rationale = rationale
    }

    enum CodingKeys: String, CodingKey {
        case priority, title, action, rationale
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(priority, forKey: .priority)
        try container.encode(title, forKey: .title)
        try container.encode(action, forKey: .action)
        try container.encode(rationale, forKey: .rationale)
    }
}

enum RecommendationPriority: String, Codable {
    case high
    case medium
    case low

    var color: Color {
        switch self {
        case .high: return Color.drip.coral
        case .medium: return Color.drip.energized
        case .low: return Color.drip.positive
        }
    }

    var label: String {
        switch self {
        case .high: return "Priority"
        case .medium: return "Suggested"
        case .low: return "Optional"
        }
    }
}

enum AlertLevel: String, Codable {
    case green   // All good, on track
    case yellow  // Minor concerns, adjustments suggested
    case orange  // Significant concerns, action needed
    case red     // Critical - injury risk, major issues

    var color: Color {
        switch self {
        case .green: return Color.drip.positive
        case .yellow: return Color.drip.energized
        case .orange: return Color.orange
        case .red: return Color.drip.coral
        }
    }

    var icon: String {
        switch self {
        case .green: return "checkmark.shield.fill"
        case .yellow: return "exclamationmark.shield.fill"
        case .orange: return "exclamationmark.triangle.fill"
        case .red: return "xmark.shield.fill"
        }
    }

    var label: String {
        switch self {
        case .green: return "On Track"
        case .yellow: return "Minor Adjustments"
        case .orange: return "Attention Needed"
        case .red: return "Action Required"
        }
    }
}

// MARK: - Stored Analysis

struct StoredAnalysis: Codable, Identifiable {
    let id: UUID
    let createdAt: Date
    let weekNumber: Int
    let analysis: TrainingAnalysisResponse

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case weekNumber = "week_number"
        case analysis
    }
}

// MARK: - Workout Variation Models

/// Represents a creative workout variation that maintains the original training stimulus
struct WorkoutVariation: Codable, Identifiable {
    let id: UUID
    let originalWorkoutType: String
    let variationName: String
    let description: String
    let structure: WorkoutStructure
    let trainingStimulus: String
    let whyItWorks: String
    let difficultyAdjustment: DifficultyAdjustment

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = UUID()
        self.originalWorkoutType = try container.decode(String.self, forKey: .originalWorkoutType)
        self.variationName = try container.decode(String.self, forKey: .variationName)
        self.description = try container.decode(String.self, forKey: .description)
        self.structure = try container.decode(WorkoutStructure.self, forKey: .structure)
        self.trainingStimulus = try container.decode(String.self, forKey: .trainingStimulus)
        self.whyItWorks = try container.decode(String.self, forKey: .whyItWorks)
        self.difficultyAdjustment = try container.decode(DifficultyAdjustment.self, forKey: .difficultyAdjustment)
    }

    init(
        originalWorkoutType: String,
        variationName: String,
        description: String,
        structure: WorkoutStructure,
        trainingStimulus: String,
        whyItWorks: String,
        difficultyAdjustment: DifficultyAdjustment = .same
    ) {
        self.id = UUID()
        self.originalWorkoutType = originalWorkoutType
        self.variationName = variationName
        self.description = description
        self.structure = structure
        self.trainingStimulus = trainingStimulus
        self.whyItWorks = whyItWorks
        self.difficultyAdjustment = difficultyAdjustment
    }

    enum CodingKeys: String, CodingKey {
        case originalWorkoutType = "original_workout_type"
        case variationName = "variation_name"
        case description
        case structure
        case trainingStimulus = "training_stimulus"
        case whyItWorks = "why_it_works"
        case difficultyAdjustment = "difficulty_adjustment"
    }
}

/// Describes the structure of a workout for analysis
struct WorkoutStructure: Codable {
    let warmupMiles: Double
    let mainSetDescription: String
    let mainSetVolumeMiles: Double
    let intensityRange: String // e.g., "85-95% MP"
    let recoveryDescription: String
    let cooldownMiles: Double
    let totalMiles: Double

    enum CodingKeys: String, CodingKey {
        case warmupMiles = "warmup_miles"
        case mainSetDescription = "main_set_description"
        case mainSetVolumeMiles = "main_set_volume_miles"
        case intensityRange = "intensity_range"
        case recoveryDescription = "recovery_description"
        case cooldownMiles = "cooldown_miles"
        case totalMiles = "total_miles"
    }
}

enum DifficultyAdjustment: String, Codable {
    case easier = "easier"
    case same = "same"
    case harder = "harder"

    var displayName: String {
        switch self {
        case .easier: return "Slightly Easier"
        case .same: return "Same Difficulty"
        case .harder: return "Slightly Harder"
        }
    }

    var color: Color {
        switch self {
        case .easier: return Color.drip.positive
        case .same: return Color.drip.textSecondary
        case .harder: return Color.drip.coral
        }
    }
}

/// Analysis of a workout's training purpose and structure
struct WorkoutAnalysis: Codable, Identifiable {
    let id: UUID
    let workoutType: String
    let primaryStimulus: TrainingStimulus
    let secondaryStimulus: TrainingStimulus?
    let volumeCategory: VolumeCategory
    let intensityCategory: IntensityCategory
    let recoveryDemand: RecoveryDemand
    let bestFor: [String]
    let variations: [WorkoutVariation]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = UUID()
        self.workoutType = try container.decode(String.self, forKey: .workoutType)
        self.primaryStimulus = try container.decode(TrainingStimulus.self, forKey: .primaryStimulus)
        self.secondaryStimulus = try container.decodeIfPresent(TrainingStimulus.self, forKey: .secondaryStimulus)
        self.volumeCategory = try container.decode(VolumeCategory.self, forKey: .volumeCategory)
        self.intensityCategory = try container.decode(IntensityCategory.self, forKey: .intensityCategory)
        self.recoveryDemand = try container.decode(RecoveryDemand.self, forKey: .recoveryDemand)
        self.bestFor = try container.decode([String].self, forKey: .bestFor)
        self.variations = try container.decode([WorkoutVariation].self, forKey: .variations)
    }

    init(
        workoutType: String,
        primaryStimulus: TrainingStimulus,
        secondaryStimulus: TrainingStimulus? = nil,
        volumeCategory: VolumeCategory,
        intensityCategory: IntensityCategory,
        recoveryDemand: RecoveryDemand,
        bestFor: [String],
        variations: [WorkoutVariation]
    ) {
        self.id = UUID()
        self.workoutType = workoutType
        self.primaryStimulus = primaryStimulus
        self.secondaryStimulus = secondaryStimulus
        self.volumeCategory = volumeCategory
        self.intensityCategory = intensityCategory
        self.recoveryDemand = recoveryDemand
        self.bestFor = bestFor
        self.variations = variations
    }

    enum CodingKeys: String, CodingKey {
        case workoutType = "workout_type"
        case primaryStimulus = "primary_stimulus"
        case secondaryStimulus = "secondary_stimulus"
        case volumeCategory = "volume_category"
        case intensityCategory = "intensity_category"
        case recoveryDemand = "recovery_demand"
        case bestFor = "best_for"
        case variations
    }
}

enum TrainingStimulus: String, Codable {
    case aerobicBase = "aerobic_base"
    case lactateThreshold = "lactate_threshold"
    case vo2max = "vo2max"
    case neuromuscular = "neuromuscular"
    case marathonSpecific = "marathon_specific"
    case endurance = "endurance"
    case recovery = "recovery"

    var displayName: String {
        switch self {
        case .aerobicBase: return "Aerobic Base"
        case .lactateThreshold: return "Lactate Threshold"
        case .vo2max: return "VO2max"
        case .neuromuscular: return "Neuromuscular"
        case .marathonSpecific: return "Marathon Specific"
        case .endurance: return "Endurance"
        case .recovery: return "Recovery"
        }
    }

    var icon: String {
        switch self {
        case .aerobicBase: return "heart.fill"
        case .lactateThreshold: return "gauge.with.needle.fill"
        case .vo2max: return "bolt.fill"
        case .neuromuscular: return "figure.run"
        case .marathonSpecific: return "flag.checkered"
        case .endurance: return "clock.fill"
        case .recovery: return "leaf.fill"
        }
    }

    var color: Color {
        switch self {
        case .aerobicBase: return Color.drip.positive
        case .lactateThreshold: return Color.drip.energized
        case .vo2max: return Color.drip.coral
        case .neuromuscular: return Color.drip.coralLight
        case .marathonSpecific: return Color.drip.coral
        case .endurance: return Color.drip.textSecondary
        case .recovery: return Color.drip.positive
        }
    }
}

enum VolumeCategory: String, Codable {
    case low = "low"       // < 6 miles
    case moderate = "moderate" // 6-10 miles
    case high = "high"     // 10-16 miles
    case veryHigh = "very_high" // 16+ miles

    var displayName: String {
        switch self {
        case .low: return "Low Volume"
        case .moderate: return "Moderate Volume"
        case .high: return "High Volume"
        case .veryHigh: return "Very High Volume"
        }
    }
}

enum IntensityCategory: String, Codable {
    case easy = "easy"         // < 75% MP
    case moderate = "moderate" // 75-85% MP
    case hard = "hard"         // 85-95% MP
    case veryHard = "very_hard" // 95-105% MP

    var displayName: String {
        switch self {
        case .easy: return "Easy"
        case .moderate: return "Moderate"
        case .hard: return "Hard"
        case .veryHard: return "Very Hard"
        }
    }

    var color: Color {
        switch self {
        case .easy: return Color.drip.positive
        case .moderate: return Color.drip.energized
        case .hard: return Color.drip.coralLight
        case .veryHard: return Color.drip.coral
        }
    }
}

enum RecoveryDemand: String, Codable {
    case minimal = "minimal"   // Can run quality next day
    case low = "low"           // Easy run OK next day
    case moderate = "moderate" // Need easy day before quality
    case high = "high"         // Need 1-2 easy days
    case veryHigh = "very_high" // Need 2+ easy days

    var displayName: String {
        switch self {
        case .minimal: return "Minimal"
        case .low: return "Low"
        case .moderate: return "Moderate"
        case .high: return "High"
        case .veryHigh: return "Very High"
        }
    }

    var recommendedEasyDays: Int {
        switch self {
        case .minimal: return 0
        case .low: return 0
        case .moderate: return 1
        case .high: return 2
        case .veryHigh: return 2
        }
    }
}

/// Request for analyzing a specific workout and generating variations
struct WorkoutVariationRequest: Codable {
    let workout: CanovaWorkout
    let athleteProfile: AthleteProfile
    let trainingPhase: String
    let weeksUntilRace: Int
    let goalPaceSecondsPerMile: Double

    enum CodingKeys: String, CodingKey {
        case workout
        case athleteProfile = "athlete_profile"
        case trainingPhase = "training_phase"
        case weeksUntilRace = "weeks_until_race"
        case goalPaceSecondsPerMile = "goal_pace_seconds_per_mile"
    }
}

/// Response with workout analysis and creative variations
struct WorkoutVariationResponse: Codable {
    let analysis: WorkoutAnalysis
    let suggestedVariation: WorkoutVariation?
    let alternativeVariations: [WorkoutVariation]
    let coachingNotes: String

    enum CodingKeys: String, CodingKey {
        case analysis
        case suggestedVariation = "suggested_variation"
        case alternativeVariations = "alternative_variations"
        case coachingNotes = "coaching_notes"
    }
}

// MARK: - Sample Data

extension TrainingAnalysisResponse {
    static var sample: TrainingAnalysisResponse {
        TrainingAnalysisResponse(
            summary: "You're making solid progress in week 8 of your Boston Marathon prep. Your consistency has been excellent with 6 of 7 workouts completed last week. Volume is on target at 72 miles.",
            insights: [
                CoachingInsight(
                    category: .volume,
                    title: "Weekly Volume",
                    detail: "You hit 72 miles last week, right in the target range for the fundamental phase.",
                    metric: "72 mi",
                    trend: .stable
                ),
                CoachingInsight(
                    category: .pacing,
                    title: "Long Run Pacing",
                    detail: "Your last long run averaged 7:45/mi - slightly faster than the prescribed 8:00/mi easy pace.",
                    metric: "7:45/mi",
                    trend: .up
                ),
                CoachingInsight(
                    category: .consistency,
                    title: "Workout Completion",
                    detail: "86% completion rate over the last 4 weeks. Great consistency!",
                    metric: "86%",
                    trend: .stable
                )
            ],
            recommendations: [
                CoachingRecommendation(
                    priority: .medium,
                    title: "Slow Down Long Runs",
                    action: "Keep long runs at 8:00-8:15/mi pace",
                    rationale: "Running long runs too fast can compromise recovery and limit the aerobic benefit. Save the speed for quality days."
                ),
                CoachingRecommendation(
                    priority: .low,
                    title: "Add Strides",
                    action: "Include 4-6 strides after 2 easy runs this week",
                    rationale: "Strides maintain neuromuscular efficiency and leg turnover without adding fatigue."
                )
            ],
            weeklyFocus: "This is a key volume week in the fundamental phase. Focus on completing the 20-mile long run with the last 4 miles at marathon pace. The mid-week tempo is 6 miles at 6:50/mi.",
            alertLevel: .green,
            encouragement: "You're building a strong aerobic foundation. Trust the process - the fitness gains from these high-volume weeks will pay dividends on race day!"
        )
    }
}

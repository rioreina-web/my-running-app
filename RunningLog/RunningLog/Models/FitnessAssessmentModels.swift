//
//  FitnessAssessmentModels.swift
//  RunningLog
//
//  Models for fitness assessment and AI-powered training plan calibration.
//

import Foundation
import SwiftUI

// MARK: - Fitness Assessment

/// Complete fitness assessment combining questionnaire and workout analysis
struct FitnessAssessment: Codable {
    let id: UUID
    let createdAt: Date
    let questionnaire: FitnessQuestionnaire
    let workoutAnalysis: WorkoutHistoryAnalysis?
    let aiAssessment: AIFitnessAssessment?

    /// Overall fitness level determined by AI
    var fitnessLevel: FitnessLevel {
        aiAssessment?.fitnessLevel ?? .intermediate
    }

    /// Recommended starting weekly mileage
    var recommendedWeeklyMileage: Double {
        aiAssessment?.recommendedStartingMileage ?? questionnaire.currentWeeklyMileage
    }

    /// Recommended peak mileage
    var recommendedPeakMileage: Double {
        aiAssessment?.recommendedPeakMileage ?? (questionnaire.currentWeeklyMileage * 1.5)
    }
}

// MARK: - Fitness Questionnaire

/// User-provided answers about their current fitness
struct FitnessQuestionnaire: Codable {
    // Running history
    let yearsRunning: YearsRunning
    let currentWeeklyMileage: Double
    let peakWeeklyMileage: Double
    let runsPerWeek: Int

    // Recent training
    let consistencyLevel: ConsistencyLevel
    let recentInjury: Bool
    let injuryDetails: String?

    // Race history
    let hasRacedMarathon: Bool
    let marathonPR: Int? // seconds
    let hasRacedHalfMarathon: Bool
    let halfMarathonPR: Int? // seconds
    let has5kOr10kRecent: Bool
    let recent5kTime: Int? // seconds
    let recent10kTime: Int? // seconds

    // Training preferences
    let preferredLongRunDay: DayOfWeek
    let canRunDoubles: Bool
    let hasAccessToTrack: Bool
    let preferredWorkoutTypes: [PreferredWorkoutType]

    // Goals and constraints
    let goalTimeRealistic: GoalTimeAssessment
    let timeAvailablePerDay: TimeAvailability
    let crossTrainingActivities: [CrossTrainingActivity]
}

// MARK: - Questionnaire Enums

enum YearsRunning: String, Codable, CaseIterable {
    case lessThanOne = "less_than_1"
    case oneToTwo = "1_to_2"
    case twoToFive = "2_to_5"
    case fiveToTen = "5_to_10"
    case moreThanTen = "10_plus"

    var displayName: String {
        switch self {
        case .lessThanOne: return "Less than 1 year"
        case .oneToTwo: return "1-2 years"
        case .twoToFive: return "2-5 years"
        case .fiveToTen: return "5-10 years"
        case .moreThanTen: return "10+ years"
        }
    }
}

enum ConsistencyLevel: String, Codable, CaseIterable {
    case veryConsistent = "very_consistent"
    case mostlyConsistent = "mostly_consistent"
    case inconsistent = "inconsistent"
    case returning = "returning"

    var displayName: String {
        switch self {
        case .veryConsistent: return "Very consistent (rarely miss runs)"
        case .mostlyConsistent: return "Mostly consistent (occasional missed run)"
        case .inconsistent: return "Inconsistent (frequently miss runs)"
        case .returning: return "Returning from break/injury"
        }
    }
}

enum DayOfWeek: String, Codable, CaseIterable {
    case sunday, monday, tuesday, wednesday, thursday, friday, saturday

    var displayName: String {
        rawValue.capitalized
    }
}

enum PreferredWorkoutType: String, Codable, CaseIterable {
    case tempo = "tempo"
    case intervals = "intervals"
    case longRun = "long_run"
    case hillRepeats = "hill_repeats"
    case fartlek = "fartlek"
    case progressiveRun = "progressive"

    var displayName: String {
        switch self {
        case .tempo: return "Tempo runs"
        case .intervals: return "Track intervals"
        case .longRun: return "Long runs"
        case .hillRepeats: return "Hill repeats"
        case .fartlek: return "Fartlek"
        case .progressiveRun: return "Progressive runs"
        }
    }
}

enum GoalTimeAssessment: String, Codable, CaseIterable {
    case ambitious = "ambitious"
    case challenging = "challenging"
    case achievable = "achievable"
    case conservative = "conservative"
    case unsure = "unsure"

    var displayName: String {
        switch self {
        case .ambitious: return "Very ambitious (stretch goal)"
        case .challenging: return "Challenging but possible"
        case .achievable: return "Should be achievable"
        case .conservative: return "Conservative / safe"
        case .unsure: return "I'm not sure"
        }
    }
}

enum TimeAvailability: String, Codable, CaseIterable {
    case limited = "limited"      // < 45 min
    case moderate = "moderate"    // 45-75 min
    case flexible = "flexible"    // 75-90 min
    case abundant = "abundant"    // 90+ min

    var displayName: String {
        switch self {
        case .limited: return "Limited (< 45 min/day)"
        case .moderate: return "Moderate (45-75 min/day)"
        case .flexible: return "Flexible (75-90 min/day)"
        case .abundant: return "Abundant (90+ min/day)"
        }
    }
}

enum CrossTrainingActivity: String, Codable, CaseIterable {
    case cycling, swimming, yoga, strength, elliptical, walking, none

    var displayName: String {
        switch self {
        case .cycling: return "Cycling"
        case .swimming: return "Swimming"
        case .yoga: return "Yoga/Stretching"
        case .strength: return "Strength training"
        case .elliptical: return "Elliptical"
        case .walking: return "Walking"
        case .none: return "None"
        }
    }
}

// MARK: - Workout History Analysis

/// Analysis of HealthKit workout data
struct WorkoutHistoryAnalysis: Codable {
    let analyzedWorkouts: Int
    let dateRange: DateRange
    let weeklyMileageStats: WeeklyMileageStats
    let paceProgression: PaceProgression
    let workoutTypeBreakdown: [WorkoutTypeCount]
    let consistencyScore: Double // 0-100
    let longestRun: LongestRunInfo?
    let recentTrend: TrendDirection

    struct DateRange: Codable {
        let start: Date
        let end: Date
    }

    struct WeeklyMileageStats: Codable {
        let average: Double
        let peak: Double
        let recent4WeekAverage: Double
        let trend: TrendDirection
    }

    struct PaceProgression: Codable {
        let averageEasyPace: Double // seconds per mile
        let averageWorkoutPace: Double // seconds per mile
        let estimatedMarathonPace: Double // seconds per mile
        let fitnessIndex: Double
    }

    struct WorkoutTypeCount: Codable {
        let type: String
        let count: Int
        let totalMiles: Double
    }

    struct LongestRunInfo: Codable {
        let distanceMiles: Double
        let date: Date
        let pace: Double // seconds per mile
    }
}

// MARK: - AI Fitness Assessment

/// AI-generated fitness assessment and recommendations
struct AIFitnessAssessment: Codable {
    let fitnessLevel: FitnessLevel
    let summary: String
    let strengths: [String]
    let areasToImprove: [String]
    let recommendedStartingMileage: Double
    let recommendedPeakMileage: Double
    let riskFactors: [RiskFactor]
    let goalAssessment: GoalAssessmentResult
    let trainingRecommendations: [TrainingRecommendation]

    enum CodingKeys: String, CodingKey {
        case fitnessLevel = "fitness_level"
        case summary
        case strengths
        case areasToImprove = "areas_to_improve"
        case recommendedStartingMileage = "recommended_starting_mileage"
        case recommendedPeakMileage = "recommended_peak_mileage"
        case riskFactors = "risk_factors"
        case goalAssessment = "goal_assessment"
        case trainingRecommendations = "training_recommendations"
    }
}

enum FitnessLevel: String, Codable, CaseIterable {
    case beginner = "beginner"
    case novice = "novice"
    case intermediate = "intermediate"
    case advanced = "advanced"
    case elite = "elite"

    var displayName: String {
        switch self {
        case .beginner: return "Beginner"
        case .novice: return "Novice"
        case .intermediate: return "Intermediate"
        case .advanced: return "Advanced"
        case .elite: return "Elite"
        }
    }

    var description: String {
        switch self {
        case .beginner: return "New to running or marathon training"
        case .novice: return "Some running experience, first marathon"
        case .intermediate: return "Multiple marathons, solid base"
        case .advanced: return "Experienced marathoner with PRs"
        case .elite: return "Sub-elite competitive runner"
        }
    }

    var color: Color {
        switch self {
        case .beginner: return Color.drip.positive
        case .novice: return Color.drip.energized
        case .intermediate: return Color.drip.coralLight
        case .advanced: return Color.drip.coral
        case .elite: return Color.purple
        }
    }

    var icon: String {
        switch self {
        case .beginner: return "figure.walk"
        case .novice: return "figure.run"
        case .intermediate: return "figure.run.circle"
        case .advanced: return "bolt.fill"
        case .elite: return "star.fill"
        }
    }
}

struct RiskFactor: Codable, Identifiable {
    var id: String { factor }
    let factor: String
    let severity: RiskSeverity
    let mitigation: String
}

enum RiskSeverity: String, Codable {
    case low, moderate, high

    var color: Color {
        switch self {
        case .low: return Color.drip.positive
        case .moderate: return Color.drip.energized
        case .high: return Color.drip.coral
        }
    }
}

struct GoalAssessmentResult: Codable {
    let isRealistic: Bool
    let confidenceLevel: Double // 0-100
    let suggestedGoalTime: Int? // seconds
    let reasoning: String

    enum CodingKeys: String, CodingKey {
        case isRealistic = "is_realistic"
        case confidenceLevel = "confidence_level"
        case suggestedGoalTime = "suggested_goal_time"
        case reasoning
    }
}

struct TrainingRecommendation: Codable, Identifiable {
    var id: String { title }
    let title: String
    let description: String
    let priority: RecommendationPriority
}

// MARK: - Assessment Request (for AI)

struct FitnessAssessmentRequest: Codable {
    let questionnaire: FitnessQuestionnaire
    let workoutHistory: WorkoutHistoryAnalysis?
    let goalRaceDistance: String
    let goalTimeSeconds: Int
    let weeksUntilRace: Int

    enum CodingKeys: String, CodingKey {
        case questionnaire
        case workoutHistory = "workout_history"
        case goalRaceDistance = "goal_race_distance"
        case goalTimeSeconds = "goal_time_seconds"
        case weeksUntilRace = "weeks_until_race"
    }
}

// MARK: - Serialization for Edge Function

extension FitnessAssessment {
    /// Flattens all assessment data into a dictionary for the generate-training-plan edge function
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [:]
        let q = questionnaire

        // Questionnaire
        dict["yearsRunning"] = q.yearsRunning.rawValue
        dict["currentWeeklyMileage"] = q.currentWeeklyMileage
        dict["peakWeeklyMileage"] = q.peakWeeklyMileage
        dict["runsPerWeek"] = q.runsPerWeek
        dict["consistencyLevel"] = q.consistencyLevel.rawValue
        dict["recentInjury"] = q.recentInjury
        if let details = q.injuryDetails { dict["injuryDetails"] = details }
        dict["preferredLongRunDay"] = q.preferredLongRunDay.rawValue
        dict["canRunDoubles"] = q.canRunDoubles
        dict["hasAccessToTrack"] = q.hasAccessToTrack
        dict["preferredWorkoutTypes"] = q.preferredWorkoutTypes.map(\.rawValue)
        dict["goalTimeRealistic"] = q.goalTimeRealistic.rawValue
        dict["timeAvailablePerDay"] = q.timeAvailablePerDay.rawValue
        dict["crossTrainingActivities"] = q.crossTrainingActivities.map(\.rawValue)

        // Race PRs (seconds)
        if q.hasRacedMarathon, let pr = q.marathonPR { dict["marathonPR"] = pr }
        if q.hasRacedHalfMarathon, let pr = q.halfMarathonPR { dict["halfMarathonPR"] = pr }
        if let t = q.recent5kTime { dict["recent5kTime"] = t }
        if let t = q.recent10kTime { dict["recent10kTime"] = t }

        // Workout analysis from HealthKit
        if let wa = workoutAnalysis {
            var waDict: [String: Any] = [
                "weeklyMileageAvg": wa.weeklyMileageStats.average,
                "weeklyMileagePeak": wa.weeklyMileageStats.peak,
                "recent4WeekAvg": wa.weeklyMileageStats.recent4WeekAverage,
                "mileageTrend": wa.weeklyMileageStats.trend.rawValue,
                "consistencyScore": wa.consistencyScore,
                "fitnessIndex": wa.paceProgression.fitnessIndex,
                "averageEasyPace": wa.paceProgression.averageEasyPace,
                "averageWorkoutPace": wa.paceProgression.averageWorkoutPace,
                "estimatedMarathonPace": wa.paceProgression.estimatedMarathonPace,
            ]
            if let lr = wa.longestRun { waDict["longestRunMiles"] = lr.distanceMiles }
            dict["workoutAnalysis"] = waDict
        }

        // AI assessment
        if let ai = aiAssessment {
            var aiDict: [String: Any] = [
                "fitnessLevel": ai.fitnessLevel.rawValue,
                "recommendedStartingMileage": ai.recommendedStartingMileage,
                "recommendedPeakMileage": ai.recommendedPeakMileage,
                "goalIsRealistic": ai.goalAssessment.isRealistic,
                "goalConfidence": ai.goalAssessment.confidenceLevel,
            ]
            if let suggested = ai.goalAssessment.suggestedGoalTime {
                aiDict["suggestedGoalTime"] = suggested
            }
            aiDict["riskFactors"] = ai.riskFactors.map {
                ["factor": $0.factor, "severity": $0.severity.rawValue, "mitigation": $0.mitigation]
            }
            dict["aiAssessment"] = aiDict
        }

        return dict
    }
}

// MARK: - Sample Data

extension FitnessQuestionnaire {
    static var sample: FitnessQuestionnaire {
        FitnessQuestionnaire(
            yearsRunning: .twoToFive,
            currentWeeklyMileage: 35,
            peakWeeklyMileage: 50,
            runsPerWeek: 5,
            consistencyLevel: .mostlyConsistent,
            recentInjury: false,
            injuryDetails: nil,
            hasRacedMarathon: true,
            marathonPR: 14400, // 4:00:00
            hasRacedHalfMarathon: true,
            halfMarathonPR: 6300, // 1:45:00
            has5kOr10kRecent: true,
            recent5kTime: 1380, // 23:00
            recent10kTime: 2880, // 48:00
            preferredLongRunDay: .sunday,
            canRunDoubles: false,
            hasAccessToTrack: true,
            preferredWorkoutTypes: [.tempo, .longRun, .progressiveRun],
            goalTimeRealistic: .challenging,
            timeAvailablePerDay: .moderate,
            crossTrainingActivities: [.strength, .yoga]
        )
    }
}

extension AIFitnessAssessment {
    static var sample: AIFitnessAssessment {
        AIFitnessAssessment(
            fitnessLevel: .intermediate,
            summary: "You have a solid running foundation with consistent training history. Your race times suggest you're ready for a challenging marathon goal.",
            strengths: [
                "Consistent training with 5 runs per week",
                "Good long run experience up to 16 miles",
                "Recent half marathon PR shows fitness is building"
            ],
            areasToImprove: [
                "Increase weekly mileage gradually",
                "Add more marathon-pace work",
                "Consider adding a second quality day"
            ],
            recommendedStartingMileage: 40,
            recommendedPeakMileage: 65,
            riskFactors: [
                RiskFactor(
                    factor: "Aggressive mileage increase planned",
                    severity: .moderate,
                    mitigation: "Include recovery weeks every 3 weeks"
                )
            ],
            goalAssessment: GoalAssessmentResult(
                isRealistic: true,
                confidenceLevel: 75,
                suggestedGoalTime: nil,
                reasoning: "Based on your half marathon PR and training history, your goal is achievable with proper preparation."
            ),
            trainingRecommendations: [
                TrainingRecommendation(
                    title: "Build Base First",
                    description: "Spend the first 3 weeks building to 45 mpw before adding quality work",
                    priority: .high
                ),
                TrainingRecommendation(
                    title: "Long Run Progression",
                    description: "Progress long runs by 1-2 miles every 2 weeks up to 22 miles",
                    priority: .medium
                )
            ]
        )
    }
}

//
//  CoachModels.swift
//  RunningLog
//
//  Data models for the coach training plan feature.
//  Coaches build workout templates and plan templates of any duration.
//  Athletes subscribe via join code or coach assignment.
//

import Foundation

// MARK: - Coach Profile

struct CoachProfile: Identifiable, Codable {
    let id: UUID
    var userId: String
    var displayName: String
    var bio: String?
    var specializations: [String]
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case displayName = "display_name"
        case bio
        case specializations
        case createdAt = "created_at"
    }
}

struct CoachProfileInsert: Codable {
    var userId: String
    var displayName: String
    var bio: String?
    var specializations: [String]

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case displayName = "display_name"
        case bio
        case specializations
    }
}

// MARK: - Workout Template

/// A reusable workout blueprint saved to the coach's library.
/// workout_data stores a full PlannedWorkout JSON blob.
struct WorkoutTemplate: Identifiable, Codable {
    let id: UUID
    var coachId: UUID
    var name: String
    var workoutType: ScheduledWorkoutType
    var description: String?
    var tags: [String]
    var workoutData: PlannedWorkout
    var estimatedDistanceMiles: Double?
    var estimatedDurationMinutes: Int?
    var isPublic: Bool
    var useCount: Int
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case coachId = "coach_id"
        case name
        case workoutType = "workout_type"
        case description
        case tags
        case workoutData = "workout_data"
        case estimatedDistanceMiles = "estimated_distance_miles"
        case estimatedDurationMinutes = "estimated_duration_minutes"
        case isPublic = "is_public"
        case useCount = "use_count"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    /// Display string for distance and/or duration
    var summaryText: String {
        var parts: [String] = []
        if let dist = estimatedDistanceMiles {
            parts.append(String(format: "%.1f mi", dist))
        }
        if let mins = estimatedDurationMinutes {
            if mins >= 60 {
                let h = mins / 60
                let m = mins % 60
                parts.append(m > 0 ? "\(h)h \(m)m" : "\(h)h")
            } else {
                parts.append("\(mins) min")
            }
        }
        return parts.joined(separator: " · ")
    }
}

struct WorkoutTemplateInsert: Codable {
    var coachId: UUID
    var name: String
    var workoutType: String
    var description: String?
    var tags: [String]
    var workoutData: PlannedWorkout
    var estimatedDistanceMiles: Double?
    var estimatedDurationMinutes: Int?
    var isPublic: Bool = false

    enum CodingKeys: String, CodingKey {
        case coachId = "coach_id"
        case name
        case workoutType = "workout_type"
        case description
        case tags
        case workoutData = "workout_data"
        case estimatedDistanceMiles = "estimated_distance_miles"
        case estimatedDurationMinutes = "estimated_duration_minutes"
        case isPublic = "is_public"
    }
}

// MARK: - Plan Template

/// A training plan blueprint of any duration. The `weeks` array is the full schedule.
struct PlanTemplate: Identifiable, Codable {
    let id: UUID
    var coachId: UUID
    var name: String
    var description: String?
    var targetDistance: String
    var durationWeeks: Int
    var planType: String               // "fixed" | "adaptive"
    var weeks: [PlanTemplateWeek]
    var dayStructure: [DayStructureEntry]?
    var phaseConfig: PhaseConfigData?
    var weeklyMileageTargets: [WeeklyMileageTarget]?
    var raceDate: String?
    var joinCode: String?
    var isPublished: Bool
    var subscriberCount: Int
    var createdAt: Date
    var updatedAt: Date

    var isAdaptive: Bool { planType == "adaptive" }

    var targetDistanceDisplay: String {
        switch targetDistance {
        case "marathon": return "Marathon"
        case "half_marathon": return "Half Marathon"
        case "10k": return "10K"
        case "5k": return "5K"
        default: return targetDistance.capitalized
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case coachId = "coach_id"
        case name, description
        case targetDistance = "target_distance"
        case durationWeeks = "duration_weeks"
        case planType = "plan_type"
        case weeks
        case dayStructure = "day_structure"
        case phaseConfig = "phase_config"
        case weeklyMileageTargets = "weekly_mileage_targets"
        case raceDate = "race_date"
        case joinCode = "join_code"
        case isPublished = "is_published"
        case subscriberCount = "subscriber_count"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct DayStructureEntry: Codable {
    var dayOfWeek: Int
    var role: String  // "speed" | "moderate" | "long_run" | "easy" | "recovery" | "rest" | "strides"
}

struct PhaseConfigData: Codable {
    // Phases can be missing — the web plan builder now stores the pace anchor
    // in this same JSONB without necessarily writing phases. Keeping phases
    // required caused `join_code` lookup to fail with "data couldn't be read
    // because it is missing" whenever a template was saved from the web.
    var phases: [PhaseEntry]?

    struct PhaseEntry: Codable {
        var name: String     // "base" | "build" | "specific" | "taper"
        var startWeek: Int
        var endWeek: Int

        enum CodingKeys: String, CodingKey {
            case name
            case startWeek = "startWeek"
            case endWeek = "endWeek"
        }
    }
}

struct WeeklyMileageTarget: Codable {
    var weekNumber: Int
    var targetMiles: Int
    var phase: String

    enum CodingKeys: String, CodingKey {
        case weekNumber = "weekNumber"
        case targetMiles = "targetMiles"
        case phase
    }

}

struct PlanTemplateInsert: Codable {
    var coachId: UUID
    var name: String
    var description: String?
    var targetDistance: String
    var durationWeeks: Int
    var planType: String = "fixed"
    var weeks: [PlanTemplateWeek]

    enum CodingKeys: String, CodingKey {
        case coachId = "coach_id"
        case name, description
        case targetDistance = "target_distance"
        case durationWeeks = "duration_weeks"
        case planType = "plan_type"
        case weeks
    }
}

// MARK: - Plan Template Week

struct PlanTemplateWeek: Codable, Identifiable {
    var id: UUID { UUID() }
    var weekNumber: Int
    var theme: String
    var notes: String
    var workouts: [PlanTemplateWorkout]
    /// Coach's prescribed weekly volume range (the "RANGE 60 - 70 mpw"
    /// inputs in the web plan-builder). Saved per-week so each week's
    /// mileage target can step up over the plan. The subscribe-to-plan
    /// edge function reads these directly; the iOS sheet uses them to
    /// show "Coach prescribes X–Y mi/week" on the join flow.
    var targetMilesMin: Double?
    var targetMilesMax: Double?

    enum CodingKeys: String, CodingKey {
        case weekNumber = "weekNumber"
        case theme
        case notes
        case workouts
        case targetMilesMin = "targetMilesMin"
        case targetMilesMax = "targetMilesMax"
    }

    /// Total planned distance across all workouts in the week (uses step data when explicit distance not set)
    var totalPlannedMiles: Double {
        workouts
            .filter { $0.workoutType?.isRunning ?? true }
            .compactMap { $0.workoutData?.effectiveDistanceMiles }
            .reduce(0, +)
    }

    /// Number of rest days in the week
    var restDays: Int {
        workouts.filter { $0.workoutType == .rest || $0.workoutType == nil }.count
    }
}

// MARK: - Plan Template Workout

/// One day's workout assignment within a plan template week.
struct PlanTemplateWorkout: Codable, Identifiable {
    var id: UUID
    /// 0 = Monday, 6 = Sunday
    var dayOfWeek: Int
    /// Optional reference to a saved WorkoutTemplate
    var workoutTemplateId: UUID?
    /// The actual workout type (from ScheduledWorkoutType)
    var workoutType: ScheduledWorkoutType?
    /// Inline workout data (may duplicate template data for portability)
    var workoutData: PlannedWorkout?
    var notes: String

    enum CodingKeys: String, CodingKey {
        case id
        case dayOfWeek = "dayOfWeek"
        case workoutTemplateId = "workoutTemplateId"
        case workoutType = "workoutType"
        case workoutData = "workoutData"
        case notes
    }

    init(
        id: UUID = UUID(),
        dayOfWeek: Int,
        workoutTemplateId: UUID? = nil,
        workoutType: ScheduledWorkoutType? = .rest,
        workoutData: PlannedWorkout? = nil,
        notes: String = ""
    ) {
        self.id = id
        self.dayOfWeek = dayOfWeek
        self.workoutTemplateId = workoutTemplateId
        self.workoutType = workoutType
        self.workoutData = workoutData
        self.notes = notes
    }

    var dayName: String {
        let days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        guard dayOfWeek >= 0, dayOfWeek < 7 else { return "" }
        return days[dayOfWeek]
    }

    var isRest: Bool {
        workoutType == .rest || workoutType == nil
    }

    // Custom decoder: web plan-builder omits `id` from workout entries in the
    // `weeks` JSONB. Generate one when missing so decoding doesn't fail.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        self.dayOfWeek = try c.decode(Int.self, forKey: .dayOfWeek)
        self.workoutTemplateId = try? c.decode(UUID.self, forKey: .workoutTemplateId)
        self.workoutType = try? c.decode(ScheduledWorkoutType.self, forKey: .workoutType)
        self.workoutData = try? c.decode(PlannedWorkout.self, forKey: .workoutData)
        self.notes = (try? c.decode(String.self, forKey: .notes)) ?? ""
    }
}

// MARK: - Coach-Athlete Relationship

struct CoachAthleteRelationship: Identifiable, Codable {
    let id: UUID
    var coachId: UUID
    var athleteUserId: String
    var status: RelationshipStatus
    var invitedAt: Date
    var acceptedAt: Date?

    enum RelationshipStatus: String, Codable {
        case pending
        case active
        case inactive

        var displayName: String {
            switch self {
            case .pending: return "Pending"
            case .active: return "Active"
            case .inactive: return "Inactive"
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case coachId = "coach_id"
        case athleteUserId = "athlete_user_id"
        case status
        case invitedAt = "invited_at"
        case acceptedAt = "accepted_at"
    }
}

struct CoachAthleteRelationshipInsert: Codable {
    var coachId: UUID
    var athleteUserId: String
    var status: String = "pending"

    enum CodingKeys: String, CodingKey {
        case coachId = "coach_id"
        case athleteUserId = "athlete_user_id"
        case status
    }
}

// MARK: - Athlete Plan Subscription

struct AthletePlanSubscription: Identifiable, Codable {
    let id: UUID
    var planTemplateId: UUID
    var athleteUserId: String
    var trainingPlanId: UUID?
    var startDate: Date
    var status: SubscriptionStatus
    var createdAt: Date
    // AO-2 columns. Optional on decode so older rows (or partial selects)
    // don't break loading. The edit-preferences flow re-uses these to
    // seed the JoinCoachPlanSheet in edit mode (AO-5).
    var restDows: [Int]?
    var preferredQualityDows: [Int]?
    var longRunDow: Int?
    var volumeRamp: VolumeRamp?
    var shapePrefs: ShapePrefs?
    var currentWeeklyMileage: Double?

    enum SubscriptionStatus: String, Codable {
        case active
        case paused
        case completed
        case dropped

        var displayName: String {
            switch self {
            case .active: return "Active"
            case .paused: return "Paused"
            case .completed: return "Completed"
            case .dropped: return "Dropped"
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case planTemplateId = "plan_template_id"
        case athleteUserId = "athlete_user_id"
        case trainingPlanId = "training_plan_id"
        case startDate = "start_date"
        case status
        case createdAt = "created_at"
        case restDows = "rest_dows"
        case preferredQualityDows = "preferred_quality_dows"
        case longRunDow = "long_run_dow"
        case volumeRamp = "volume_ramp"
        case shapePrefs = "shape_prefs"
        case currentWeeklyMileage = "current_weekly_mileage"
    }
}

struct AthletePlanSubscriptionInsert: Codable {
    var planTemplateId: UUID
    var athleteUserId: String
    var startDate: Date
    var status: String = "active"

    enum CodingKeys: String, CodingKey {
        case planTemplateId = "plan_template_id"
        case athleteUserId = "athlete_user_id"
        case startDate = "start_date"
        case status
    }
}

// MARK: - Helper: Empty PlanTemplate

extension PlanTemplate {
    /// Creates a blank plan template with empty weeks for the given duration
    static func blank(coachId: UUID, durationWeeks: Int = 16) -> PlanTemplate {
        let weeks = (1...durationWeeks).map { weekNum in
            PlanTemplateWeek(
                weekNumber: weekNum,
                theme: weekNum == durationWeeks ? "Race Week" : "Week \(weekNum)",
                notes: "",
                workouts: (0..<7).map { day in
                    PlanTemplateWorkout(dayOfWeek: day, workoutType: .rest)
                }
            )
        }
        return PlanTemplate(
            id: UUID(),
            coachId: coachId,
            name: "",
            description: nil,
            targetDistance: "marathon",
            durationWeeks: durationWeeks,
            planType: "fixed",
            weeks: weeks,
            dayStructure: nil,
            phaseConfig: nil,
            weeklyMileageTargets: nil,
            raceDate: nil,
            joinCode: nil,
            isPublished: false,
            subscriberCount: 0,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}

// MARK: - Subscribe to Plan Request/Response

struct SubscribeToPlanRequest: Codable {
    var planTemplateId: UUID
    var athleteUserId: String
    var startDate: String  // ISO date string "yyyy-MM-dd"
    var goalTimeSeconds: Int?
    var targetRaceDistance: String?
}

struct SubscribeToPlanResponse: Codable {
    var trainingPlanId: UUID?
    var subscriptionId: UUID?
    var error: String?
}

// MARK: - Subscription Preferences (athlete onboarding §AO-1)
//
// Athlete-side overrides layered on top of the coach's plan template at
// subscribe time. The shape mirrors the new columns on
// `athlete_plan_subscriptions` (migration 20260425200000) and the JSON body
// the iOS sheet posts to `subscribe-to-plan`. Coding keys are snake_case to
// match the edge function's expected payload.

struct VolumeRamp: Codable, Equatable {
    var startMileage: Double
    var rampToCoachTarget: Bool
    var rampWeeks: Int

    enum CodingKeys: String, CodingKey {
        case startMileage = "start_mileage"
        case rampToCoachTarget = "ramp_to_coach_target"
        case rampWeeks = "ramp_weeks"
    }
}

struct ShapePrefs: Codable, Equatable {
    var stridesPreQuality: Bool
    var recoveryAfterLong: Bool
    var doublesOnEasyDays: Bool

    enum CodingKeys: String, CodingKey {
        case stridesPreQuality = "strides_pre_quality"
        case recoveryAfterLong = "recovery_after_long"
        case doublesOnEasyDays = "doubles_on_easy_days"
    }
}

struct SubscriptionPreferences: Codable, Equatable {
    var restDows: [Int]
    var preferredQualityDows: [Int]
    var longRunDow: Int?
    var volumeRamp: VolumeRamp?
    var shapePrefs: ShapePrefs?
    var currentWeeklyMileage: Double?

    enum CodingKeys: String, CodingKey {
        case restDows = "rest_dows"
        case preferredQualityDows = "preferred_quality_dows"
        case longRunDow = "long_run_dow"
        case volumeRamp = "volume_ramp"
        case shapePrefs = "shape_prefs"
        case currentWeeklyMileage = "current_weekly_mileage"
    }
}

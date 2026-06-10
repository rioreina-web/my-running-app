//
//  TrainingPlanModels.swift
//  RunningLog
//
//  Core training plan types: TrainingPlan, TrainingPlanInsert, ScheduledWorkout,
//  ScheduledWorkoutType, WorkoutStatus, ScheduledWorkoutInsert, and
//  ScheduledWorkoutUpdate.
//

import Foundation
import SwiftUI

private let postgresTimestampFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(secondsFromGMT: 0)
    f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXXXX"
    return f
}()

private let iso8601NoFraction: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(secondsFromGMT: 0)
    f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"
    return f
}()

private let dateOnlyFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    // Parse YYYY-MM-DD as LOCAL midnight, not UTC. Using UTC would shift every
    // workout one day earlier in any negative-offset timezone (so a workout
    // dated 2026-04-27 lands on Sun Apr 26 in PDT). Bare date columns from
    // Postgres are calendar-day values with no timezone meaning — local
    // midnight is the right interpretation everywhere they're displayed.
    f.timeZone = TimeZone.current
    f.dateFormat = "yyyy-MM-dd"
    return f
}()

// MARK: - Training Plan

/// A complete training plan spanning multiple months
struct TrainingPlan: Identifiable, Codable {
    let id: UUID
    var userId: String
    var goalId: UUID?
    var name: String
    var startDate: Date
    var endDate: Date
    var targetRaceDistance: String
    var targetTimeSeconds: Int
    var status: PlanStatus
    var createdAt: Date
    var updatedAt: Date
    /// Set when this plan was generated from a coach's plan template
    var coachId: UUID?
    var planTemplateId: UUID?
    /// "self" (default, athlete-generated) or "coach" (from a coach template)
    var sourceType: String?
    /// "fixed" | "adaptive" (only meaningful when sourceType == "coach")
    var planType: String?

    var isCoachPlan: Bool { sourceType == "coach" || coachId != nil || planTemplateId != nil }
    var isAdaptive: Bool { planType == "adaptive" }

    /// Parsed race distance enum (defaults to marathon for legacy data)
    var raceDistance: RaceDistance {
        RaceDistance.from(legacyString: targetRaceDistance) ?? .marathon
    }

    enum PlanStatus: String, Codable, CaseIterable {
        case active
        case completed
        case archived

        var displayName: String {
            switch self {
            case .active: return "Active"
            case .completed: return "Completed"
            case .archived: return "Archived"
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case goalId = "goal_id"
        case name
        case startDate = "start_date"
        case endDate = "end_date"
        case targetRaceDistance = "target_race_distance"
        case targetTimeSeconds = "target_time_seconds"
        case status
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case coachId = "coach_id"
        case planTemplateId = "plan_template_id"
        case sourceType = "source_type"
        case planType = "plan_type"
    }

    // Explicit memberwise init (the implicit one is removed when we add init(from:) below)
    init(
        id: UUID,
        userId: String,
        goalId: UUID? = nil,
        name: String,
        startDate: Date,
        endDate: Date,
        targetRaceDistance: String,
        targetTimeSeconds: Int,
        status: PlanStatus,
        createdAt: Date,
        updatedAt: Date,
        coachId: UUID? = nil,
        planTemplateId: UUID? = nil,
        sourceType: String? = nil,
        planType: String? = nil
    ) {
        self.id = id
        self.userId = userId
        self.goalId = goalId
        self.name = name
        self.startDate = startDate
        self.endDate = endDate
        self.targetRaceDistance = targetRaceDistance
        self.targetTimeSeconds = targetTimeSeconds
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.coachId = coachId
        self.planTemplateId = planTemplateId
        self.sourceType = sourceType
        self.planType = planType
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.userId = try c.decode(String.self, forKey: .userId)
        self.goalId = try? c.decode(UUID.self, forKey: .goalId)
        self.name = try c.decode(String.self, forKey: .name)
        self.startDate = try TrainingPlan.decodeFlexibleDate(c, key: .startDate)
        self.endDate = try TrainingPlan.decodeFlexibleDate(c, key: .endDate)
        self.targetRaceDistance = try c.decode(String.self, forKey: .targetRaceDistance)
        self.targetTimeSeconds = try c.decode(Int.self, forKey: .targetTimeSeconds)
        self.status = try c.decode(PlanStatus.self, forKey: .status)
        self.createdAt = try TrainingPlan.decodeFlexibleDate(c, key: .createdAt)
        self.updatedAt = try TrainingPlan.decodeFlexibleDate(c, key: .updatedAt)
        self.coachId = try? c.decode(UUID.self, forKey: .coachId)
        self.planTemplateId = try? c.decode(UUID.self, forKey: .planTemplateId)
        self.sourceType = try? c.decode(String.self, forKey: .sourceType)
        self.planType = try? c.decode(String.self, forKey: .planType)
    }

    /// Handles Postgres timestamps with microsecond precision, plain `yyyy-MM-dd`
    /// date-only values, and ISO8601 w/o fractions. Falls back to epoch 0 on parse
    /// failure so a bad date doesn't blow up the whole plan load.
    private static func decodeFlexibleDate(_ c: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) throws -> Date {
        let s = try c.decode(String.self, forKey: key)
        if let d = postgresTimestampFormatter.date(from: s) { return d }
        if let d = iso8601NoFraction.date(from: s) { return d }
        if let d = dateOnlyFormatter.date(from: s) { return d }
        // Truncate sub-second to millis and retry ISO8601.
        let millisString = s.replacingOccurrences(of: #"\.(\d{3})\d+"#, with: ".$1", options: .regularExpression)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: millisString) { return d }
        let iso2 = ISO8601DateFormatter()
        iso2.formatOptions = [.withInternetDateTime]
        if let d = iso2.date(from: millisString) { return d }
        throw DecodingError.dataCorruptedError(forKey: key, in: c, debugDescription: "Unparseable date: \(s)")
    }

    /// Total weeks in the plan
    var totalWeeks: Int {
        let calendar = Calendar.current
        let weeks = calendar.dateComponents([.weekOfYear], from: startDate, to: endDate).weekOfYear ?? 0
        return max(1, weeks + 1)
    }

    /// Current week number (1-based)
    var currentWeek: Int {
        let calendar = Calendar.current
        let today = Date()
        guard today >= startDate else { return 1 }
        guard today <= endDate else { return totalWeeks }
        let weeks = calendar.dateComponents([.weekOfYear], from: startDate, to: today).weekOfYear ?? 0
        return min(weeks + 1, totalWeeks)
    }

    /// Days remaining until race
    var daysRemaining: Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let target = calendar.startOfDay(for: endDate)
        return calendar.dateComponents([.day], from: today, to: target).day ?? 0
    }

    /// Formatted goal time string
    var formattedGoalTime: String {
        let hours = targetTimeSeconds / 3600
        let mins = (targetTimeSeconds % 3600) / 60
        let secs = targetTimeSeconds % 60
        if secs > 0 {
            return String(format: "%d:%02d:%02d", hours, mins, secs)
        }
        return String(format: "%d:%02d", hours, mins)
    }

    /// Race pace in seconds per mile
    var racePaceSecondsPerMile: Double {
        raceDistance.racePaceSecondsPerMile(goalTimeSeconds: targetTimeSeconds)
    }

    /// Pre-computed equivalent race paces for this plan's goal
    var equivalentPaces: EquivalentPaces {
        EquivalentPaces(raceDistance: raceDistance, goalTimeSeconds: targetTimeSeconds)
    }

    /// Formatted race pace string
    var formattedRacePace: String {
        let totalSecs = Int(racePaceSecondsPerMile.rounded())
        let mins = totalSecs / 60
        let secs = totalSecs % 60
        return "\(mins):\(String(format: "%02d", secs))/mi"
    }
}

// MARK: - Training Plan Insert

/// Insert model for creating new training plans
struct TrainingPlanInsert: Codable {
    var id: UUID
    var userId: String
    var goalId: UUID?
    var name: String
    var startDate: Date
    var endDate: Date
    var targetRaceDistance: String = "marathon"
    var targetTimeSeconds: Int
    var status: String = "active"
    var sourceType: String = "self"
    var planType: String = "fixed"

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case goalId = "goal_id"
        case name
        case startDate = "start_date"
        case endDate = "end_date"
        case targetRaceDistance = "target_race_distance"
        case targetTimeSeconds = "target_time_seconds"
        case status
        case sourceType = "source_type"
        case planType = "plan_type"
    }
}

// MARK: - Scheduled Workout

/// A workout scheduled on a specific date within a training plan
struct ScheduledWorkout: Identifiable, Codable {
    let id: UUID
    var planId: UUID
    var date: Date
    var dayOfWeek: Int
    var weekNumber: Int
    var session: Int
    var workout: PlannedWorkout?
    var workoutType: ScheduledWorkoutType
    var status: WorkoutStatus
    var completedWorkoutId: UUID?
    var workoutCode: String?
    var isAutoSelected: Bool?
    var notes: String?
    var createdAt: Date
    var updatedAt: Date
    /// Two-lane model: who placed this workout on this date
    var source: String?
    /// Two-lane model: can the athlete drag this to another day?
    var isMovable: Bool?
    /// Two-lane model: links back to quality session pool template
    var poolTemplateId: UUID?
    /// Open-Meteo forecast for the planned workout day, populated by
    /// fetch-workout-weather. Nil when no forecast has been fetched
    /// (e.g., the daily cron hasn't run since the workout was scheduled).
    var weatherForecast: WorkoutForecast?
    /// Per-workout scheduled local hour (0-23). When set, the heat
    /// forecast is pulled for THIS hour rather than the athlete's
    /// profile-level preferred_run_time. Stored as a plain integer
    /// (not a timestamptz) so we can match Open-Meteo's local-time
    /// hourly array without needing the athlete's timezone. Nullable —
    /// most workouts inherit the profile preference until the athlete
    /// taps the time pill on the workout detail and picks something
    /// custom.
    var scheduledHour: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case planId = "plan_id"
        case date
        case dayOfWeek = "day_of_week"
        case weekNumber = "week_number"
        case session
        case workout = "workout_data"
        case workoutType = "workout_type"
        case status
        case completedWorkoutId = "completed_workout_id"
        case workoutCode = "workout_code"
        case isAutoSelected = "is_auto_selected"
        case notes
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case source
        case isMovable = "is_movable"
        case poolTemplateId = "pool_template_id"
        case weatherForecast = "weather_forecast"
        case scheduledHour = "scheduled_hour"
    }

    init(
        id: UUID, planId: UUID, date: Date, dayOfWeek: Int, weekNumber: Int, session: Int,
        workout: PlannedWorkout?, workoutType: ScheduledWorkoutType, status: WorkoutStatus,
        completedWorkoutId: UUID? = nil, notes: String? = nil,
        createdAt: Date, updatedAt: Date
    ) {
        self.id = id
        self.planId = planId
        self.date = date
        self.dayOfWeek = dayOfWeek
        self.weekNumber = weekNumber
        self.session = session
        self.workout = workout
        self.workoutType = workoutType
        self.status = status
        self.completedWorkoutId = completedWorkoutId
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.planId = try c.decode(UUID.self, forKey: .planId)
        self.date = try ScheduledWorkout.decodeFlexibleDate(c, key: .date)
        self.dayOfWeek = try c.decode(Int.self, forKey: .dayOfWeek)
        self.weekNumber = try c.decode(Int.self, forKey: .weekNumber)
        self.session = (try? c.decode(Int.self, forKey: .session)) ?? 1
        self.workout = try? c.decode(PlannedWorkout.self, forKey: .workout)
        self.workoutType = try c.decode(ScheduledWorkoutType.self, forKey: .workoutType)
        self.status = try c.decode(WorkoutStatus.self, forKey: .status)
        self.completedWorkoutId = try? c.decode(UUID.self, forKey: .completedWorkoutId)
        self.workoutCode = try? c.decode(String.self, forKey: .workoutCode)
        self.isAutoSelected = try? c.decode(Bool.self, forKey: .isAutoSelected)
        self.notes = try? c.decode(String.self, forKey: .notes)
        self.createdAt = (try? ScheduledWorkout.decodeFlexibleDate(c, key: .createdAt)) ?? Date()
        self.updatedAt = (try? ScheduledWorkout.decodeFlexibleDate(c, key: .updatedAt)) ?? Date()
        self.source = try? c.decode(String.self, forKey: .source)
        self.isMovable = try? c.decode(Bool.self, forKey: .isMovable)
        self.poolTemplateId = try? c.decode(UUID.self, forKey: .poolTemplateId)
        self.weatherForecast = try? c.decode(WorkoutForecast.self, forKey: .weatherForecast)
        // smallint 0-23 from the DB; nil = inherit profile preference.
        self.scheduledHour = try? c.decode(Int.self, forKey: .scheduledHour)
    }

    /// Handles yyyy-MM-dd date-only strings (for `date` field) AND full
    /// Postgres timestamps (for `created_at`/`updated_at`).
    private static func decodeFlexibleDate(_ c: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) throws -> Date {
        let s = try c.decode(String.self, forKey: key)
        let dateOnly = DateFormatter()
        dateOnly.locale = Locale(identifier: "en_US_POSIX")
        // Local midnight, not UTC — see comment on dateOnlyFormatter above.
        dateOnly.timeZone = TimeZone.current
        dateOnly.dateFormat = "yyyy-MM-dd"
        if let d = dateOnly.date(from: s) { return d }

        let pgTs = DateFormatter()
        pgTs.locale = Locale(identifier: "en_US_POSIX")
        pgTs.timeZone = TimeZone(secondsFromGMT: 0)
        pgTs.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXXXX"
        if let d = pgTs.date(from: s) { return d }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }

        let iso2 = ISO8601DateFormatter()
        iso2.formatOptions = [.withInternetDateTime]
        if let d = iso2.date(from: s) { return d }

        // Postgres micro-second precision — truncate to millis and retry
        let millisString = s.replacingOccurrences(of: #"\.(\d{3})\d+"#, with: ".$1", options: .regularExpression)
        if let d = iso.date(from: millisString) { return d }
        if let d = iso2.date(from: millisString) { return d }

        throw DecodingError.dataCorruptedError(forKey: key, in: c, debugDescription: "Unparseable date: \(s)")
    }

    var isRestDay: Bool {
        workoutType == .rest
    }

    /// Whether this is a quality session (coach-prescribed hard workout)
    var isQualitySession: Bool {
        source == "coach_locked" || source == "athlete_drag"
    }

    /// Whether the athlete can drag this workout to another day
    var canMove: Bool {
        isMovable ?? false
    }

    var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }

    var isPast: Bool {
        date < Calendar.current.startOfDay(for: Date())
    }

    var isFuture: Bool {
        date > Calendar.current.startOfDay(for: Date())
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter.string(from: date)
    }

    var dayName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }

    var shortDayName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }

    var dayNumber: Int {
        Calendar.current.component(.day, from: date)
    }

    var formattedFullDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: date)
    }

    var formattedShortDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}

// MARK: - Scheduled Workout Type

enum ScheduledWorkoutType: String, Codable, CaseIterable {
    case rest
    case easy
    case tempo
    case intervals
    case longRun = "long_run"
    case recovery
    case race
    case progression
    case strides
    case strength
    case crossTraining = "cross_training"

    var displayName: String {
        switch self {
        case .rest: return "Rest Day"
        case .easy: return "Easy Run"
        case .tempo: return "Tempo Run"
        case .intervals: return "Intervals"
        case .longRun: return "Long Run"
        case .recovery: return "Recovery"
        case .race: return "Race Day"
        case .progression: return "Progression Run"
        case .strides: return "Easy + Strides"
        case .strength: return "Strength"
        case .crossTraining: return "Cross Training"
        }
    }

    var shortName: String {
        switch self {
        case .rest: return "Rest"
        case .easy: return "Easy"
        case .tempo: return "Tempo"
        case .intervals: return "Intervals"
        case .longRun: return "Long"
        case .recovery: return "Recovery"
        case .race: return "Race"
        case .progression: return "Progression"
        case .strides: return "Strides"
        case .strength: return "Strength"
        case .crossTraining: return "XT"
        }
    }

    var icon: String {
        switch self {
        case .rest: return "bed.double.fill"
        case .easy: return "figure.walk"
        case .tempo: return "gauge.with.needle.fill"
        case .intervals: return "repeat"
        case .longRun: return "road.lanes"
        case .recovery: return "leaf.fill"
        case .race: return "flag.checkered"
        case .progression: return "arrow.up.right"
        case .strides: return "bolt.fill"
        case .strength: return "dumbbell.fill"
        case .crossTraining: return "figure.pool.swim"
        }
    }

    var color: Color {
        switch self {
        case .rest: return Color.drip.textTertiary
        case .easy: return Color.drip.positive
        case .tempo: return Color.drip.coralLight
        case .intervals: return Color.drip.coral
        case .longRun: return Color.drip.energized
        case .recovery: return Color.drip.positive
        case .race: return Color.drip.coral
        case .progression: return Color.drip.coralLight
        case .strides: return Color.drip.energized
        case .strength: return .purple
        case .crossTraining: return .cyan
        }
    }

    /// Whether this workout type is a running workout (affects volume calculations)
    var isRunning: Bool {
        switch self {
        case .strength, .crossTraining, .rest: return false
        default: return true
        }
    }
}

// MARK: - Workout Status

enum WorkoutStatus: String, Codable, CaseIterable {
    case scheduled
    case completed
    case skipped
    case modified

    var displayName: String {
        switch self {
        case .scheduled: return "Scheduled"
        case .completed: return "Completed"
        case .skipped: return "Skipped"
        case .modified: return "Modified"
        }
    }

    var icon: String {
        switch self {
        case .scheduled: return "calendar"
        case .completed: return "checkmark.circle.fill"
        case .skipped: return "xmark.circle"
        case .modified: return "pencil.circle"
        }
    }
}

// MARK: - Scheduled Workout Insert

/// Insert model for creating scheduled workouts
struct ScheduledWorkoutInsert: Codable {
    var planId: UUID
    var date: Date
    var dayOfWeek: Int
    var weekNumber: Int
    var session: Int = 1
    var workoutData: PlannedWorkout?
    var workoutType: ScheduledWorkoutType
    var status: String = "scheduled"
    var notes: String?
    var source: String = "legacy"
    var isMovable: Bool = false

    enum CodingKeys: String, CodingKey {
        case planId = "plan_id"
        case date
        case dayOfWeek = "day_of_week"
        case weekNumber = "week_number"
        case session
        case workoutData = "workout_data"
        case workoutType = "workout_type"
        case status
        case notes
        case source
        case isMovable = "is_movable"
    }
}

// MARK: - Quality Session Template

/// A quality session in the weekly pool — not tied to a specific date until the athlete places it.
struct QualitySessionTemplate: Identifiable, Codable {
    let id: UUID
    var planId: UUID
    var weekNumber: Int
    var purpose: String
    var workoutType: ScheduledWorkoutType
    var workoutData: PlannedWorkout?
    var targetPacePercentage: Double?
    var targetDistanceMiles: Double?
    var targetDurationMinutes: Double?
    var priorityRank: Int
    var suggestedDayOfWeek: Int?
    var isPlaced: Bool
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case planId = "plan_id"
        case weekNumber = "week_number"
        case purpose
        case workoutType = "workout_type"
        case workoutData = "workout_data"
        case targetPacePercentage = "target_pace_percentage"
        case targetDistanceMiles = "target_distance_miles"
        case targetDurationMinutes = "target_duration_minutes"
        case priorityRank = "priority_rank"
        case suggestedDayOfWeek = "suggested_day_of_week"
        case isPlaced = "is_placed"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - Scheduled Workout Update

/// Update model for modifying scheduled workouts
struct ScheduledWorkoutUpdate: Codable {
    var workoutData: PlannedWorkout?
    var workoutType: ScheduledWorkoutType
    var status: WorkoutStatus
    var notes: String?

    enum CodingKeys: String, CodingKey {
        case workoutData = "workout_data"
        case workoutType = "workout_type"
        case status
        case notes
    }
}

// MARK: - Sample Data

extension TrainingPlan {
    static var sample: TrainingPlan {
        TrainingPlan(
            id: UUID(),
            userId: "sample-user",
            goalId: UUID(),
            name: "Boston Marathon 2026",
            startDate: Date(),
            endDate: Date().addingTimeInterval(86400 * 112), // 16 weeks
            targetRaceDistance: "marathon",
            targetTimeSeconds: 3 * 3600 + 30 * 60, // 3:30
            status: .active,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}

extension ScheduledWorkout {
    static var sample: ScheduledWorkout {
        ScheduledWorkout(
            id: UUID(),
            planId: UUID(),
            date: Date(),
            dayOfWeek: 2,
            weekNumber: 5,
            session: 1,
            workout: PlannedWorkout.sample,
            workoutType: .tempo,
            status: .scheduled,
            completedWorkoutId: nil,
            notes: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    static var restDaySample: ScheduledWorkout {
        ScheduledWorkout(
            id: UUID(),
            planId: UUID(),
            date: Date(),
            dayOfWeek: 1,
            weekNumber: 5,
            session: 1,
            workout: nil,
            workoutType: .rest,
            status: .scheduled,
            completedWorkoutId: nil,
            notes: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}

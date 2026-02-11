//
//  TrainingPlanModels.swift
//  RunningLog
//
//  Data models for training plan calendar system.
//

import Foundation
import SwiftUI

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

    /// Formatted race pace string
    var formattedRacePace: String {
        let pace = racePaceSecondsPerMile
        let mins = Int(pace) / 60
        let secs = Int(pace) % 60
        return "\(mins):\(String(format: "%02d", secs))/mi"
    }
}

// MARK: - Training Plan Insert

/// Insert model for creating new training plans
struct TrainingPlanInsert: Codable {
    var userId: String
    var goalId: UUID?
    var name: String
    var startDate: Date
    var endDate: Date
    var targetRaceDistance: String = "marathon"
    var targetTimeSeconds: Int
    var status: String = "active"

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case goalId = "goal_id"
        case name
        case startDate = "start_date"
        case endDate = "end_date"
        case targetRaceDistance = "target_race_distance"
        case targetTimeSeconds = "target_time_seconds"
        case status
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
    var workout: CanovaWorkout?
    var workoutType: ScheduledWorkoutType
    var status: WorkoutStatus
    var completedWorkoutId: UUID?
    var notes: String?
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case planId = "plan_id"
        case date
        case dayOfWeek = "day_of_week"
        case weekNumber = "week_number"
        case workout = "workout_data"
        case workoutType = "workout_type"
        case status
        case completedWorkoutId = "completed_workout_id"
        case notes
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var isRestDay: Bool {
        workoutType == .rest
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
    var workoutData: CanovaWorkout?
    var workoutType: ScheduledWorkoutType
    var status: String = "scheduled"
    var notes: String?

    enum CodingKeys: String, CodingKey {
        case planId = "plan_id"
        case date
        case dayOfWeek = "day_of_week"
        case weekNumber = "week_number"
        case workoutData = "workout_data"
        case workoutType = "workout_type"
        case status
        case notes
    }
}

// MARK: - Scheduled Workout Update

/// Update model for modifying scheduled workouts
struct ScheduledWorkoutUpdate: Codable {
    var workoutData: CanovaWorkout?
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

// MARK: - Training Week Summary

/// Aggregated data for a training week
struct TrainingWeekSummary: Identifiable {
    let id = UUID()
    let weekNumber: Int
    let phase: CanovaTrainingPhase
    let startDate: Date
    let endDate: Date
    let scheduledWorkouts: [ScheduledWorkout]

    /// Total planned distance in miles
    var totalPlannedMiles: Double {
        let kmTotal = scheduledWorkouts.compactMap { $0.workout?.totalDistanceKm }.reduce(0, +)
        return kmTotal / 1.60934
    }

    /// Total planned duration in minutes
    var totalPlannedMinutes: Double {
        scheduledWorkouts.compactMap { $0.workout?.estimatedDurationMinutes }.reduce(0, +)
    }

    /// Number of completed workouts
    var completedCount: Int {
        scheduledWorkouts.filter { $0.status == .completed }.count
    }

    /// Number of workout days (non-rest)
    var workoutDays: Int {
        scheduledWorkouts.filter { !$0.isRestDay }.count
    }

    /// Number of rest days
    var restDays: Int {
        scheduledWorkouts.filter { $0.isRestDay }.count
    }

    /// Formatted date range string
    var dateRangeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return "\(formatter.string(from: startDate)) - \(formatter.string(from: endDate))"
    }

    /// Completion percentage
    var completionPercentage: Double {
        let total = workoutDays
        guard total > 0 else { return 0 }
        return Double(completedCount) / Double(total) * 100
    }
}

// MARK: - Calendar View Mode

enum CalendarViewMode: String, CaseIterable {
    case week = "Week"
    case month = "Month"
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
            workout: CanovaWorkout.sample,
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

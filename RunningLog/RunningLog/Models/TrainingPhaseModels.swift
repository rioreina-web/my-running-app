//
//  TrainingPhaseModels.swift
//  RunningLog
//
//  Phase and periodization aggregate types: TrainingWeekSummary and
//  CalendarViewMode.
//

import Foundation

// MARK: - Training Week Summary

/// Aggregated data for a training week
struct TrainingWeekSummary: Identifiable {
    let id = UUID()
    let weekNumber: Int
    let phase: TrainingPhase
    let startDate: Date
    let endDate: Date
    let scheduledWorkouts: [ScheduledWorkout]

    /// Total planned distance in miles
    var totalPlannedMiles: Double {
        let kmTotal = scheduledWorkouts
            .filter { $0.workoutType.isRunning }
            .compactMap { $0.workout?.totalDistanceKm }
            .reduce(0, +)
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

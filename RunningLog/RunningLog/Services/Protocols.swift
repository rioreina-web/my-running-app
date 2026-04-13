import Foundation

// MARK: - WorkoutRecord

/// Unified protocol for any workout-like entity (logged, scheduled, or planned).
/// Enables generic views and utilities to work across RunningWorkout, ScheduledWorkout, and TrainingLog.
protocol WorkoutRecord: Identifiable where ID == UUID {
    var workoutDate: Date? { get }
    var workoutDistanceMiles: Double? { get }
    var workoutDurationMinutes: Double? { get }
    var workoutDisplayName: String { get }
}

// MARK: - WorkoutRecord Conformances

extension RunningWorkout: WorkoutRecord {
    var workoutDate: Date? { startDate }
    var workoutDistanceMiles: Double? { distanceMiles }
    var workoutDurationMinutes: Double? { durationMinutes }
    var workoutDisplayName: String { "\(formattedDistance) run" }
}

extension ScheduledWorkout: WorkoutRecord {
    var workoutDate: Date? { date }
    var workoutDistanceMiles: Double? { workout?.totalDistanceMiles }
    var workoutDurationMinutes: Double? { workout?.estimatedDurationMinutes.map { Double($0) } }
    var workoutDisplayName: String { workout?.name ?? workoutType.displayName }
}

extension TrainingLog: WorkoutRecord {
    // workoutDate, workoutDistanceMiles, workoutDurationMinutes are already
    // stored properties on TrainingLog with matching types (all optional).
    var workoutDisplayName: String { cleanedNotes ?? notes ?? "Training log" }
}

// MARK: - AuthProvider

/// Abstracts authentication state so services don't depend on AuthManager directly.
protocol AuthProvider {
    var currentUserId: String? { get }
    var userEmail: String? { get }
    var isAuthenticated: Bool { get }
}

// MARK: - WorkoutDataSource

/// Unified interface for fetching workout data from HealthKit, Vital, or test mocks.
protocol WorkoutDataSource {
    func fetchRunningWorkouts(startDate: Date, endDate: Date) async -> [RunningWorkout]
    func fetchRunningMilesByDate(startDate: Date, endDate: Date) async -> [String: Double]
}

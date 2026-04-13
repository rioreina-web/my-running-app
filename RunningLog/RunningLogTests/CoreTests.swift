import Foundation
import Testing
@testable import RunningLog

// MARK: - AuthManager Tests

@Suite("AuthManager")
struct AuthManagerTests {
    @Test("userId returns empty string when not authenticated")
    func userIdNotAuthenticated() {
        // When not signed in, userId should return empty (no dev fallback)
        let auth = AuthManager.shared
        if auth.currentUserId == nil {
            #expect(auth.userId.isEmpty)
        }
    }
}

// MARK: - Workout Type Tests

@Suite("ScheduledWorkoutType")
struct WorkoutTypeTests {
    @Test("All workout types have display names")
    func displayNames() {
        for type in ScheduledWorkoutType.allCases {
            #expect(!type.displayName.isEmpty, "Missing display name for \(type)")
        }
    }

    @Test("All workout types have icons")
    func icons() {
        for type in ScheduledWorkoutType.allCases {
            #expect(!type.icon.isEmpty, "Missing icon for \(type)")
        }
    }

    @Test("Raw values match expected strings")
    func rawValues() {
        #expect(ScheduledWorkoutType.longRun.rawValue == "long_run")
        #expect(ScheduledWorkoutType.easy.rawValue == "easy")
        #expect(ScheduledWorkoutType.rest.rawValue == "rest")
    }
}

// MARK: - WorkoutStatus Tests

@Suite("WorkoutStatus")
struct WorkoutStatusTests {
    @Test("All statuses have display names")
    func displayNames() {
        for status in WorkoutStatus.allCases {
            #expect(!status.displayName.isEmpty)
        }
    }
}

// MARK: - TrainingLog Tests

@Suite("TrainingLog")
struct TrainingLogTests {
    @Test("displayDate prefers workoutDate over createdAt")
    func displayDatePriority() {
        let workoutDate = Date(timeIntervalSince1970: 1000000)
        let createdDate = Date(timeIntervalSince1970: 2000000)

        let log = TrainingLog(
            id: UUID(), createdAt: createdDate, audioUrl: nil,
            notes: nil, cleanedNotes: nil, mood: nil,
            workoutDate: workoutDate, workoutDistanceMiles: nil,
            workoutDurationMinutes: nil, processingStatus: "completed",
            processingError: nil, processingAttempts: 0,
            transcriptUrl: nil, coachInsight: nil, workoutNotes: nil,
            workoutPacePerMile: nil, workoutType: nil, source: "voice_log",
            vitalWorkoutId: nil, paceSegments: nil
        )

        #expect(log.displayDate == workoutDate)
    }

    @Test("displayDate falls back to createdAt when no workoutDate")
    func displayDateFallback() {
        let createdDate = Date(timeIntervalSince1970: 2000000)

        let log = TrainingLog(
            id: UUID(), createdAt: createdDate, audioUrl: nil,
            notes: nil, cleanedNotes: nil, mood: nil,
            workoutDate: nil, workoutDistanceMiles: nil,
            workoutDurationMinutes: nil, processingStatus: "completed",
            processingError: nil, processingAttempts: 0,
            transcriptUrl: nil, coachInsight: nil, workoutNotes: nil,
            workoutPacePerMile: nil, workoutType: nil, source: "voice_log",
            vitalWorkoutId: nil, paceSegments: nil
        )

        #expect(log.displayDate == createdDate)
    }

    @Test("isCompleted checks processing status")
    func isCompleted() {
        let log = TrainingLog(
            id: UUID(), createdAt: Date(), audioUrl: nil,
            notes: nil, cleanedNotes: nil, mood: nil,
            workoutDate: nil, workoutDistanceMiles: nil,
            workoutDurationMinutes: nil, processingStatus: "completed",
            processingError: nil, processingAttempts: 0,
            transcriptUrl: nil, coachInsight: nil, workoutNotes: nil,
            workoutPacePerMile: nil, workoutType: nil, source: nil,
            vitalWorkoutId: nil, paceSegments: nil
        )

        #expect(log.isCompleted == true)
        #expect(log.isPending == false)
        #expect(log.isFailed == false)
    }

    @Test("hasLinkedWorkout requires both date and distance")
    func hasLinkedWorkout() {
        let withBoth = TrainingLog(
            id: UUID(), createdAt: Date(), audioUrl: nil,
            notes: nil, cleanedNotes: nil, mood: nil,
            workoutDate: Date(), workoutDistanceMiles: 5.0,
            workoutDurationMinutes: nil, processingStatus: "completed",
            processingError: nil, processingAttempts: 0,
            transcriptUrl: nil, coachInsight: nil, workoutNotes: nil,
            workoutPacePerMile: nil, workoutType: nil, source: nil,
            vitalWorkoutId: nil, paceSegments: nil
        )

        let withoutDistance = TrainingLog(
            id: UUID(), createdAt: Date(), audioUrl: nil,
            notes: nil, cleanedNotes: nil, mood: nil,
            workoutDate: Date(), workoutDistanceMiles: nil,
            workoutDurationMinutes: nil, processingStatus: "completed",
            processingError: nil, processingAttempts: 0,
            transcriptUrl: nil, coachInsight: nil, workoutNotes: nil,
            workoutPacePerMile: nil, workoutType: nil, source: nil,
            vitalWorkoutId: nil, paceSegments: nil
        )

        #expect(withBoth.hasLinkedWorkout == true)
        #expect(withoutDistance.hasLinkedWorkout == false)
    }
}

// MARK: - RescheduleScope Tests

@Suite("RescheduleScope")
struct RescheduleScopeTests {
    @Test("All scopes have display names and icons")
    func properties() {
        for scope in RescheduleScope.allCases {
            #expect(!scope.displayName.isEmpty)
            #expect(!scope.icon.isEmpty)
        }
    }

    @Test("Raw values for API")
    func rawValues() {
        #expect(RescheduleScope.day.rawValue == "day")
        #expect(RescheduleScope.week.rawValue == "week")
        #expect(RescheduleScope.remainingPlan.rawValue == "remaining_plan")
    }
}

// MARK: - RescheduleReason Tests

@Suite("RescheduleReason")
struct RescheduleReasonTests {
    @Test("All reasons have display names and icons")
    func properties() {
        for reason in RescheduleReason.allCases {
            #expect(!reason.displayName.isEmpty)
            #expect(!reason.icon.isEmpty)
        }
    }
}

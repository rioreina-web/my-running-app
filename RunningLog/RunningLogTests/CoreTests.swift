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

// MARK: - PlannedWorkout Distance Tests

@Suite("PlannedWorkout distance")
struct PlannedWorkoutDistanceTests {
    private func makeWorkout(steps: [PlannedWorkoutStep]) -> PlannedWorkout {
        PlannedWorkout(
            id: UUID(),
            name: "Test",
            category: .fundamental,
            trainingPhase: .base,
            description: "",
            steps: steps,
            totalDistanceMiles: nil,
            estimatedDurationMinutes: nil,
            signatureType: nil,
            createdAt: Date()
        )
    }

    private func step(
        type: PlannedWorkoutStep.StepType,
        durationType: PlannedWorkoutStep.DurationType,
        durationValue: Double,
        repeats: Int? = nil,
        recovery: PlannedWorkoutRecovery? = nil,
        targetPaceIntensity: PaceIntensity? = nil,
        order: Int = 0
    ) -> PlannedWorkoutStep {
        PlannedWorkoutStep(
            id: UUID(),
            stepType: type,
            durationType: durationType,
            durationValue: durationValue,
            targetPaceIntensity: targetPaceIntensity,
            targetHR: nil,
            notes: nil,
            order: order,
            paceZone: nil,
            paceAdjustment: nil,
            repeats: repeats,
            recovery: recovery
        )
    }

    @Test("6×800m + 400m recovery totals 4.225 mi — matches web")
    func intervalSetWithRecovery() {
        let recovery = PlannedWorkoutRecovery(
            durationType: .distanceMeters,
            durationValue: 400,
            paceZone: nil,
            paceAdjustment: nil
        )
        let workout = makeWorkout(steps: [
            step(type: .active, durationType: .distanceMeters, durationValue: 800, repeats: 6, recovery: recovery)
        ])
        #expect(abs(workout.totalActiveDistanceMiles - 4.225) < 0.001)
        #expect(abs(workout.totalAllStepsDistanceMiles - 4.225) < 0.001)
    }

    @Test("Single step with no repeats behaves like a single rep")
    func singleStepNoRepeats() {
        let workout = makeWorkout(steps: [
            step(type: .active, durationType: .distanceMiles, durationValue: 3.0)
        ])
        #expect(workout.totalActiveDistanceMiles == 3.0)
        #expect(workout.totalAllStepsDistanceMiles == 3.0)
    }

    @Test("reps of 1 does not add recovery distance")
    func repsOfOneSkipsRecovery() {
        let recovery = PlannedWorkoutRecovery(
            durationType: .distanceMeters,
            durationValue: 400,
            paceZone: nil,
            paceAdjustment: nil
        )
        let workout = makeWorkout(steps: [
            step(type: .active, durationType: .distanceMeters, durationValue: 1600, repeats: 1, recovery: recovery)
        ])
        let expected = 1600.0 / 1609.344
        #expect(abs(workout.totalActiveDistanceMiles - expected) < 0.0001)
    }

    @Test("Warmup + interval set + cooldown sums correctly")
    func fullWorkoutComposition() {
        let recovery = PlannedWorkoutRecovery(
            durationType: .distanceMeters,
            durationValue: 400,
            paceZone: nil,
            paceAdjustment: nil
        )
        let workout = makeWorkout(steps: [
            step(type: .warmup, durationType: .distanceMiles, durationValue: 2.0, order: 0),
            step(type: .active, durationType: .distanceMeters, durationValue: 800, repeats: 6, recovery: recovery, order: 1),
            step(type: .cooldown, durationType: .distanceMiles, durationValue: 1.0, order: 2)
        ])
        // Active only: 4.225 mi
        #expect(abs(workout.totalActiveDistanceMiles - 4.225) < 0.001)
        // All steps: warmup (2) + active+recovery (4.225) + cooldown (1) = 7.225
        #expect(abs(workout.totalAllStepsDistanceMiles - 7.225) < 0.001)
    }

    @Test("Kilometer and mile recoveries convert correctly")
    func mixedUnitRecoveries() {
        let kmRecovery = PlannedWorkoutRecovery(
            durationType: .distanceKm,
            durationValue: 0.4,
            paceZone: nil,
            paceAdjustment: nil
        )
        let workout = makeWorkout(steps: [
            step(type: .active, durationType: .distanceKm, durationValue: 1.0, repeats: 4, recovery: kmRecovery)
        ])
        // Active: 4km / 1.60934 ; Recovery: (0.4 × 3) / 1.60934
        let expected = (4.0 + 1.2) / 1.60934
        #expect(abs(workout.totalAllStepsDistanceMiles - expected) < 0.001)
    }

    @Test("Time-based interval with recovery uses heuristic paces")
    func timeBasedHeuristic() {
        let recovery = PlannedWorkoutRecovery(
            durationType: .timeSeconds,
            durationValue: 90,
            paceZone: nil,
            paceAdjustment: nil
        )
        let workout = makeWorkout(steps: [
            step(
                type: .active,
                durationType: .timeSeconds,
                durationValue: 180,
                repeats: 4,
                recovery: recovery,
                targetPaceIntensity: PaceIntensity(percentage: 95)
            )
        ])
        // Active: 180s / 420 s/mi × 4 reps
        // Recovery: 90s / 570 s/mi × 3 inter-rep gaps
        let expected = (180.0 / 420.0) * 4 + (90.0 / 570.0) * 3
        #expect(abs(workout.totalAllStepsDistanceMiles - expected) < 0.0001)
        // totalActiveDistanceMiles ignores time-based steps (distance-only).
        #expect(workout.totalActiveDistanceMiles == 0)
    }

    @Test("Open step contributes zero distance")
    func openStepZero() {
        let workout = makeWorkout(steps: [
            step(type: .active, durationType: .open, durationValue: 0)
        ])
        #expect(workout.totalActiveDistanceMiles == 0)
        #expect(workout.totalAllStepsDistanceMiles == 0)
    }

    /// A 6×800m @ 5K pace with 400m jog recovery should have a total duration
    /// that scales linearly with the athlete's 5K pace. Regression guard
    /// against the old hardcoded reference runner.
    @Test("Duration scales linearly with athlete 5K pace")
    func durationScalesWith5KPace() {
        let recovery = PlannedWorkoutRecovery(
            durationType: .distanceMeters,
            durationValue: 400,
            paceZone: .recovery,
            paceAdjustment: nil
        )
        let fiveKRep = PlannedWorkoutStep(
            id: UUID(),
            stepType: .active,
            durationType: .distanceMeters,
            durationValue: 800,
            targetPaceIntensity: nil,
            targetHR: nil,
            notes: nil,
            order: 0,
            paceZone: .fiveK,
            paceAdjustment: nil,
            repeats: 6,
            recovery: recovery
        )
        let workout = makeWorkout(steps: [fiveKRep])

        // Two athletes at different 5K fitness — recovery pace held constant
        // so only the 5K contribution drives the difference.
        let fastPaces = EquivalentPaces(
            raceDistance: .marathon,
            goalTimeSeconds: 3 * 3600,
            paceOverrides: [.fiveK: 330, .recovery: 600]  // 5:30/mi 5K, 10:00/mi recovery
        )
        let slowPaces = EquivalentPaces(
            raceDistance: .marathon,
            goalTimeSeconds: 4 * 3600,
            paceOverrides: [.fiveK: 420, .recovery: 600]  // 7:00/mi 5K, 10:00/mi recovery
        )

        let fastMinutes = workout.computedDurationMinutes(paces: fastPaces)
        let slowMinutes = workout.computedDurationMinutes(paces: slowPaces)

        // Expected analytically: activeMiles = 4800m/1609.344 ≈ 2.9826 mi
        // recoveryMiles (reps-1 = 5) = 2000m/1609.344 ≈ 1.2427 mi
        let activeMiles = 4800.0 / 1609.344
        let recoveryMiles = 2000.0 / 1609.344
        let fastExpected = (activeMiles * 330 + recoveryMiles * 600) / 60
        let slowExpected = (activeMiles * 420 + recoveryMiles * 600) / 60

        #expect(abs(fastMinutes - fastExpected) < 0.01)
        #expect(abs(slowMinutes - slowExpected) < 0.01)

        // Linear-scaling check: the delta between the two durations must equal
        // activeMiles × (420 - 330) / 60. Recovery contribution cancels out.
        let delta = slowMinutes - fastMinutes
        let expectedDelta = activeMiles * (420 - 330) / 60
        #expect(abs(delta - expectedDelta) < 0.01)
    }

    /// Reference-runner fallback path: omitting paces produces a number but
    /// callers should label it with `PlannedWorkout.referenceRunnerLabel`.
    @Test("Duration without paces falls back to reference runner")
    func durationFallsBackToReference() {
        let rep = PlannedWorkoutStep(
            id: UUID(),
            stepType: .active,
            durationType: .distanceMiles,
            durationValue: 1.0,
            targetPaceIntensity: nil,
            targetHR: nil,
            notes: nil,
            order: 0,
            paceZone: .fiveK,
            paceAdjustment: nil,
            repeats: nil,
            recovery: nil
        )
        let workout = makeWorkout(steps: [rep])
        // Reference 5K pace is 6:00/mi → 1 mile → 6 minutes.
        #expect(abs(workout.computedDurationMinutes(paces: nil) - 6.0) < 0.001)
        #expect(!PlannedWorkout.referenceRunnerLabel.isEmpty)
    }
}

// MARK: - EquivalentPaces Tests

@Suite("EquivalentPaces")
struct EquivalentPacesTests {
    /// Both initializers must produce the same zone table when fed equivalent
    /// inputs. Anchor: a 3:30 marathon goal. Feed init #1 as goal time; feed
    /// init #2 with the race anchors that PaceCalculator derives from that goal.
    @Test("Race-goal and raw-paces inits agree on zone table")
    func bothInitsAgreeFor3h30Marathon() {
        let marathonSeconds = 3 * 3600 + 30 * 60  // 12600 s
        let goalBased = EquivalentPaces(raceDistance: .marathon, goalTimeSeconds: marathonSeconds)

        let rawBased = EquivalentPaces(
            mpPace: goalBased.mpPace,
            hmPace: goalBased.hmPace,
            tenKPace: goalBased.tenKPace,
            fiveKPace: goalBased.fiveKPace,
            threeKPace: goalBased.threeKPace,
            milePace: goalBased.milePace
        )

        let tol = 0.01  // sec/mi — both paths share the same math
        #expect(abs(goalBased.recoveryPace - rawBased.recoveryPace) < tol)
        #expect(abs(goalBased.easyPace - rawBased.easyPace) < tol)
        #expect(abs(goalBased.longRunPace - rawBased.longRunPace) < tol)
        #expect(abs(goalBased.moderatePace - rawBased.moderatePace) < tol)
        #expect(abs(goalBased.steadyPace - rawBased.steadyPace) < tol)
        #expect(abs(goalBased.thresholdPace - rawBased.thresholdPace) < tol)
    }

    /// Regression guard: the old `mp / 0.75` easy-pace formula returned 12:13/mi
    /// for a 4:00 marathoner. The new coefficient should be materially faster.
    @Test("Easy pace for 4:00 marathoner is under 11:00/mi")
    func easyPaceNotOverSlowed() {
        let paces = EquivalentPaces(raceDistance: .marathon, goalTimeSeconds: 4 * 3600)
        #expect(paces.easyPace < 660.0, "easyPace \(paces.easyPace) s/mi is over-slowed")
        #expect(paces.easyPace > paces.mpPace, "easyPace must be slower than MP")
    }

    /// Threshold pace should sit between 10K and half-marathon pace for a
    /// typical sub-elite runner — confirms the 1-hour-pace interpolation is wired.
    @Test("Threshold interpolates between 10K and HM pace")
    func thresholdBetween10KAndHM() {
        let paces = EquivalentPaces(raceDistance: .marathon, goalTimeSeconds: 3 * 3600 + 30 * 60)
        #expect(paces.thresholdPace > paces.tenKPace)
        #expect(paces.thresholdPace < paces.hmPace)
    }
}

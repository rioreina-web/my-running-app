import Foundation
import Testing
@testable import RunningLog

// MARK: - Shared Helpers

@MainActor
private func makeWorkout(_ type: SignatureType, goalTime: Int) -> PlannedWorkout {
    let vm = WorkoutGeneratorViewModel()
    vm.marathonGoalTime = goalTime
    return vm.createLocalWorkout(type: type, goalTime: goalTime)
}

private func stepDistanceMiles(_ step: PlannedWorkoutStep) -> Double {
    switch step.durationType {
    case .distanceMiles: return step.durationValue
    case .distanceKm: return step.durationValue / RaceDistanceConstants.kmPerMile
    case .distanceMeters: return step.durationValue / RaceDistanceConstants.meterPerMile
    case .timeSeconds, .open: return 0
    }
}

private func sumOfStepDistances(_ workout: PlannedWorkout) -> Double {
    workout.steps.reduce(0) { $0 + stepDistanceMiles($1) }
}

/// Distance of active + recovery steps only (excludes warmup/cooldown) —
/// this is what the text description typically enumerates.
private func activeAndRecoveryMiles(_ workout: PlannedWorkout) -> Double {
    workout.steps
        .filter { $0.stepType == .active || $0.stepType == .recovery }
        .reduce(0) { $0 + stepDistanceMiles($1) }
}

/// Compute workout duration (minutes) by resolving each step's pace from
/// race pace × its percentage-of-MP intensity.
private func computedDurationMinutes(_ workout: PlannedWorkout, racePaceSecPerMile: Double) -> Double {
    var totalSeconds: Double = 0
    for step in workout.steps {
        let miles = stepDistanceMiles(step)
        guard miles > 0, let intensity = step.targetPaceIntensity else { continue }
        let paceSecPerMile = racePaceSecPerMile / (intensity.percentage / 100.0)
        totalSeconds += miles * paceSecPerMile
    }
    return totalSeconds / 60.0
}

private let signatureTypes: [SignatureType] = [
    .progressiveTempo,
    .descendingLadder,
    .racePaceRepeats,
    .specialBlock,
    .longRunWithTempo,
]

/// Marathon goal times spanning the fitness spectrum — 2:45 elite through 5:00
/// first-timer. Used to verify estimatedDurationMinutes scales with fitness.
private let marathonGoalTimes: [Int] = [
    2 * 3600 + 45 * 60,  // 2:45 — 9,900 s
    3 * 3600 + 30 * 60,  // 3:30 — 12,600 s
    4 * 3600 + 15 * 60,  // 4:15 — 15,300 s
    5 * 3600,            // 5:00 — 18,000 s
]

private func racePaceSeconds(forGoalTime goalTime: Int) -> Double {
    Double(goalTime) / RaceDistanceConstants.marathonMiles
}

/// Expected distance implied by the text description's arithmetic, restricted
/// to active + between-rep recovery (what the description enumerates). `nil`
/// means the description doesn't contain explicit mile math — skip assertion.
private func expectedDescriptionActiveAndRecoveryMiles(_ type: SignatureType) -> Double? {
    switch type {
    case .descendingLadder:
        // "4+3+2.5+2+1.5+1 miles with 0.5mi float recovery between each"
        let active = 4.0 + 3 + 2.5 + 2 + 1.5 + 1
        let recoveryCount = 5.0  // between 6 reps
        return active + recoveryCount * 0.5
    case .racePaceRepeats:
        // "6x1mi @ MP with 0.5mi float recovery between reps"
        return 6 * 1.0 + 5 * 0.5
    case .progressiveTempo, .specialBlock, .longRunWithTempo:
        return nil
    }
}

// MARK: - Distance Consistency

@Suite("WorkoutGenerator signature workouts — distance consistency")
@MainActor
struct WorkoutGeneratorDistanceTests {
    @Test(
        "totalDistanceMiles equals sum of step distances",
        arguments: signatureTypes
    )
    func totalMatchesStepSum(type: SignatureType) {
        // Distance is fitness-independent, so one goal time is enough here.
        let workout = makeWorkout(type, goalTime: marathonGoalTimes[1])
        let stepSum = sumOfStepDistances(workout)
        let stated = workout.totalDistanceMiles ?? -1
        #expect(
            abs(stepSum - stated) < 0.01,
            "\(type): totalDistanceMiles=\(stated) but steps sum to \(stepSum)"
        )
    }

    @Test(
        "description arithmetic matches active+recovery step sum",
        arguments: signatureTypes
    )
    func descriptionArithmeticMatchesSteps(type: SignatureType) {
        guard let expected = expectedDescriptionActiveAndRecoveryMiles(type) else {
            // Description has no mile arithmetic to validate.
            return
        }
        let workout = makeWorkout(type, goalTime: marathonGoalTimes[1])
        let actual = activeAndRecoveryMiles(workout)
        #expect(
            abs(actual - expected) < 0.01,
            "\(type): description implies \(expected) mi of active+recovery, steps give \(actual). Description was: \"\(workout.description)\""
        )
    }
}

// MARK: - Duration Scales With Fitness

@Suite("WorkoutGenerator signature workouts — duration scaling")
@MainActor
struct WorkoutGeneratorDurationTests {
    /// estimatedDurationMinutes must fall within ±20% of the duration computed
    /// from the athlete's race-pace-derived step paces. Tested across the full
    /// fitness spectrum — a 2:45 marathoner should finish a 12mi workout in
    /// materially less time than a 5:00 marathoner, and estimatedDurationMinutes
    /// should reflect that.
    ///
    /// NOTE: the current implementation hard-codes estimatedDurationMinutes
    /// (e.g. 90 for Progressive Tempo regardless of fitness), so this test is
    /// expected to fail at the extremes until the generator scales duration
    /// with goalTime — see Prompt 7.
    @Test(
        "estimatedDurationMinutes is within ±20% of computed duration",
        arguments: signatureTypes, marathonGoalTimes
    )
    func durationWithinTolerance(type: SignatureType, goalTime: Int) {
        let workout = makeWorkout(type, goalTime: goalTime)
        let racePace = racePaceSeconds(forGoalTime: goalTime)
        let computed = computedDurationMinutes(workout, racePaceSecPerMile: racePace)
        guard let stated = workout.estimatedDurationMinutes else {
            Issue.record("\(type) goal=\(goalTime)s: estimatedDurationMinutes is nil")
            return
        }
        let lowerBound = computed * 0.8
        let upperBound = computed * 1.2
        #expect(
            stated >= lowerBound && stated <= upperBound,
            "\(type) goal=\(goalTime)s: stated=\(stated)min, computed=\(String(format: "%.1f", computed))min, expected range [\(String(format: "%.1f", lowerBound)), \(String(format: "%.1f", upperBound))]"
        )
    }

    /// Sanity: faster athlete → shorter computed duration for the same workout.
    /// If this fails, the percentage-of-MP → pace math is broken, not the
    /// generator's estimate.
    @Test("computed duration increases monotonically as goal time increases",
          arguments: signatureTypes)
    func computedDurationMonotonic(type: SignatureType) {
        // marathonGoalTimes is sorted ascending (fast→slow). A slower athlete
        // runs a fixed workout more slowly, so computed duration must be
        // non-decreasing across the sequence.
        let durations = marathonGoalTimes.map { goalTime -> Double in
            let workout = makeWorkout(type, goalTime: goalTime)
            let racePace = racePaceSeconds(forGoalTime: goalTime)
            return computedDurationMinutes(workout, racePaceSecPerMile: racePace)
        }
        for (prev, next) in zip(durations, durations.dropFirst()) {
            #expect(
                next >= prev - 0.01,
                "\(type): duration must be non-decreasing as goal time grows. prev=\(prev), next=\(next)"
            )
        }
    }
}

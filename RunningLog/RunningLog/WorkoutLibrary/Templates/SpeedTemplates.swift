//
//  SpeedTemplates.swift
//  RunningLog
//
//  Speed and VO2max workout templates primarily for shorter events.
//

import Foundation

// MARK: - Speed Templates

/// Collection of speed and VO2max workout templates
struct SpeedTemplates {

    // MARK: - 200m Speed Repeats

    /// Very short, fast 200m repeats for speed development
    static let speed200m = WorkoutTemplate(
        id: "speed_200m",
        name: "200m Speed Repeats",
        category: .specific,
        workoutType: .intervals,
        raceDistances: [.mile1500, .fiveK],
        phases: [.specific],
        description: "Pure speed work with full recovery",
        progressionType: .volume,
        minTotalMiles: 4.0,
        maxTotalMiles: 7.0,
        intensityProgression: .gradual,
        builder: { ctx in
            let repCount: Int
            switch ctx.raceDistance {
            case .mile1500:
                repCount = 10 + Int(ctx.progression * 6)  // 10-16 reps
            case .fiveK:
                repCount = 8 + Int(ctx.progression * 6)  // 8-14 reps
            default:
                repCount = 10
            }

            // Faster than race pace (108-112%)
            let speedPace = ctx.intensity(110)

            var steps: [CanovaWorkoutStep] = [
                StepBuilder.warmup(miles: 1.5)
            ]

            for i in 0..<repCount {
                steps.append(StepBuilder.activeMeters(
                    200,
                    intensity: speedPace,
                    notes: "Rep \(i + 1) - fast but controlled"
                ))
                if i < repCount - 1 {
                    // 200m walk/jog recovery (full recovery for speed)
                    steps.append(StepBuilder.recoveryMeters(200, intensity: 55))
                }
            }

            steps.append(StepBuilder.cooldown(miles: 1.5))

            return WorkoutFactory.create(
                name: "200m Speed Repeats",
                category: .specific,
                phase: ctx.phase,
                description: "\(repCount)x200m @ 110%",
                steps: steps
            )
        }
    )

    // MARK: - 300m Repeats

    /// Speed endurance 300m repeats
    static let speed300m = WorkoutTemplate(
        id: "speed_300m",
        name: "300m Repeats",
        category: .specific,
        workoutType: .intervals,
        raceDistances: [.mile1500, .fiveK],
        phases: [.specific],
        description: "Speed endurance development",
        progressionType: .volume,
        minTotalMiles: 5.0,
        maxTotalMiles: 8.0,
        intensityProgression: .gradual,
        builder: { ctx in
            let repCount: Int
            switch ctx.raceDistance {
            case .mile1500:
                repCount = 8 + Int(ctx.progression * 4)  // 8-12 reps
            case .fiveK:
                repCount = 6 + Int(ctx.progression * 4)  // 6-10 reps
            default:
                repCount = 8
            }

            // ~3K race pace effort
            let speedPace = ctx.intensity(107)

            var steps: [CanovaWorkoutStep] = [
                StepBuilder.warmup(miles: 1.5)
            ]

            for i in 0..<repCount {
                steps.append(StepBuilder.activeMeters(
                    300,
                    intensity: speedPace,
                    notes: "Rep \(i + 1)"
                ))
                if i < repCount - 1 {
                    // 100m jog recovery
                    steps.append(StepBuilder.recoveryMeters(100, intensity: 55))
                }
            }

            steps.append(StepBuilder.cooldown(miles: 1.5))

            return WorkoutFactory.create(
                name: "300m Repeats",
                category: .specific,
                phase: ctx.phase,
                description: "\(repCount)x300m @ 107%",
                steps: steps
            )
        }
    )

    // MARK: - Hill Repeats (Short)

    /// Short hill repeats for power and speed
    static let shortHillRepeats = WorkoutTemplate(
        id: "speed_hills_short",
        name: "Short Hill Repeats",
        category: .special,
        workoutType: .intervals,
        raceDistances: RaceDistance.allCases,
        phases: [.base, .support, .specific],
        description: "Short explosive hill repeats for power",
        progressionType: .volume,
        minTotalMiles: 5.0,
        maxTotalMiles: 8.0,
        intensityProgression: .none,
        builder: { ctx in
            let repCount: Int
            switch ctx.raceDistance {
            case .mile1500:
                repCount = 10 + Int(ctx.progression * 6)  // 10-16 reps
            case .fiveK:
                repCount = 8 + Int(ctx.progression * 6)  // 8-14 reps
            case .tenK:
                repCount = 8 + Int(ctx.progression * 4)  // 8-12 reps
            case .halfMarathon, .marathon:
                repCount = 6 + Int(ctx.progression * 4)  // 6-10 reps
            }

            // Hard effort (perceived) - hills use higher RPE at same "pace"
            let hillPace = ctx.intensity(105)

            var steps: [CanovaWorkoutStep] = [
                StepBuilder.warmup(miles: 1.5)
            ]

            for i in 0..<repCount {
                // ~60-90 seconds uphill
                steps.append(StepBuilder.activeTime(
                    seconds: 75,
                    intensity: hillPace,
                    notes: "Hill \(i + 1) - strong, controlled effort"
                ))
                if i < repCount - 1 {
                    // Jog down recovery
                    steps.append(StepBuilder.recoveryTime(seconds: 120, intensity: 60))
                }
            }

            steps.append(StepBuilder.cooldown(miles: 1.5))

            return WorkoutFactory.create(
                name: "Short Hill Repeats",
                category: .special,
                phase: ctx.phase,
                description: "\(repCount)x75\" uphill",
                steps: steps
            )
        }
    )

    // MARK: - Hill Repeats (Long)

    /// Longer hill repeats for strength endurance
    static let longHillRepeats = WorkoutTemplate(
        id: "speed_hills_long",
        name: "Long Hill Repeats",
        category: .special,
        workoutType: .intervals,
        raceDistances: [.tenK, .halfMarathon, .marathon],
        phases: [.base, .support, .specific],
        description: "Longer hill repeats for strength endurance",
        progressionType: .volume,
        minTotalMiles: 6.0,
        maxTotalMiles: 10.0,
        intensityProgression: .none,
        builder: { ctx in
            let repCount: Int
            switch ctx.raceDistance {
            case .tenK:
                repCount = 5 + Int(ctx.progression * 3)  // 5-8 reps
            case .halfMarathon:
                repCount = 5 + Int(ctx.progression * 3)  // 5-8 reps
            case .marathon:
                repCount = 4 + Int(ctx.progression * 3)  // 4-7 reps
            default:
                repCount = 5
            }

            // Threshold effort on hills
            let hillPace = ctx.thresholdPace

            var steps: [CanovaWorkoutStep] = [
                StepBuilder.warmup(miles: 2.0)
            ]

            for i in 0..<repCount {
                // 2-3 minutes uphill
                steps.append(StepBuilder.activeTime(
                    seconds: 150,
                    intensity: hillPace,
                    notes: "Hill \(i + 1) - strong but sustainable"
                ))
                if i < repCount - 1 {
                    // Jog down recovery
                    steps.append(StepBuilder.recoveryTime(seconds: 180, intensity: 60))
                }
            }

            steps.append(StepBuilder.cooldown(miles: 1.5))

            return WorkoutFactory.create(
                name: "Long Hill Repeats",
                category: .special,
                phase: ctx.phase,
                description: "\(repCount)x2.5' uphill @ threshold",
                steps: steps
            )
        }
    )

    // MARK: - VO2max Workout

    /// Classic VO2max intervals (3-5 min repeats)
    static let vo2maxIntervals = WorkoutTemplate(
        id: "speed_vo2max",
        name: "VO2max Intervals",
        category: .specific,
        workoutType: .intervals,
        raceDistances: RaceDistance.allCases,
        phases: [.specific],
        description: "Intervals at maximum oxygen uptake intensity",
        progressionType: .volume,
        minTotalMiles: 7.0,
        maxTotalMiles: 11.0,
        intensityProgression: .gradual,
        builder: { ctx in
            let repCount: Int
            let repDuration: Double  // seconds

            switch ctx.raceDistance {
            case .mile1500:
                repCount = 5 + Int(ctx.progression * 2)  // 5-7 reps
                repDuration = 180  // 3 min
            case .fiveK:
                repCount = 4 + Int(ctx.progression * 2)  // 4-6 reps
                repDuration = 210  // 3:30
            case .tenK:
                repCount = 4 + Int(ctx.progression * 2)  // 4-6 reps
                repDuration = 240  // 4 min
            case .halfMarathon, .marathon:
                repCount = 4 + Int(ctx.progression * 2)  // 4-6 reps
                repDuration = 300  // 5 min
            }

            let vo2pace = ctx.vo2maxPace

            var steps: [CanovaWorkoutStep] = [
                StepBuilder.warmup(miles: 2.0)
            ]

            for i in 0..<repCount {
                steps.append(StepBuilder.activeTime(
                    seconds: repDuration,
                    intensity: vo2pace,
                    notes: "VO2max rep \(i + 1)"
                ))
                if i < repCount - 1 {
                    // 50-75% of work duration for recovery
                    steps.append(StepBuilder.recoveryTime(
                        seconds: repDuration * 0.6,
                        intensity: 65
                    ))
                }
            }

            steps.append(StepBuilder.cooldown(miles: 1.5))

            let repMin = Int(repDuration / 60)
            return WorkoutFactory.create(
                name: "VO2max Intervals",
                category: .specific,
                phase: ctx.phase,
                description: String(format: "%dx%d' @ VO2max", repCount, repMin),
                steps: steps
            )
        }
    )

    // MARK: - Speed Endurance

    /// Longer speed intervals (600-800m) with short rest
    static let speedEndurance = WorkoutTemplate(
        id: "speed_endurance",
        name: "Speed Endurance",
        category: .specific,
        workoutType: .intervals,
        raceDistances: [.mile1500, .fiveK, .tenK],
        phases: [.specific],
        description: "Speed endurance with short recovery",
        progressionType: .volume,
        minTotalMiles: 6.0,
        maxTotalMiles: 10.0,
        intensityProgression: .gradual,
        builder: { ctx in
            let repCount: Int
            let repMeters: Double

            switch ctx.raceDistance {
            case .mile1500:
                repCount = 5 + Int(ctx.progression * 3)  // 5-8 reps
                repMeters = 600
            case .fiveK:
                repCount = 5 + Int(ctx.progression * 3)  // 5-8 reps
                repMeters = 800
            case .tenK:
                repCount = 4 + Int(ctx.progression * 3)  // 4-7 reps
                repMeters = 800
            default:
                repCount = 5
                repMeters = 800
            }

            // Race pace or slightly faster
            let speedPace = ctx.intensity(ctx.racePace.percentage + 2)

            var steps: [CanovaWorkoutStep] = [
                StepBuilder.warmup(miles: 2.0)
            ]

            for i in 0..<repCount {
                steps.append(StepBuilder.activeMeters(
                    repMeters,
                    intensity: speedPace,
                    notes: "Rep \(i + 1)"
                ))
                if i < repCount - 1 {
                    // Short recovery (200m jog or ~60 seconds)
                    steps.append(StepBuilder.recoveryTime(seconds: 60, intensity: 60))
                }
            }

            steps.append(StepBuilder.cooldown(miles: 1.5))

            return WorkoutFactory.create(
                name: "Speed Endurance",
                category: .specific,
                phase: ctx.phase,
                description: "\(repCount)x\(Int(repMeters))m w/ short rest",
                steps: steps
            )
        }
    )

    // MARK: - All Speed Templates

    static var all: [WorkoutTemplate] {
        [
            speed200m,
            speed300m,
            shortHillRepeats,
            longHillRepeats,
            vo2maxIntervals,
            speedEndurance
        ]
    }
}

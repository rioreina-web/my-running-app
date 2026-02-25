//
//  IntervalTemplates.swift
//  RunningLog
//
//  Interval workout templates for all race distances.
//

import Foundation

// MARK: - Interval Templates

/// Collection of interval workout templates
struct IntervalTemplates {

    // MARK: - 400m Repeats

    /// Classic 400m repeats at VO2max pace
    static let repeats400m = WorkoutTemplate(
        id: "interval_400m",
        name: "400m Repeats",
        category: .specific,
        workoutType: .intervals,
        raceDistances: [.mile1500, .fiveK, .tenK],
        phases: [.specific],
        description: "Short, fast repeats to develop speed",
        progressionType: .volume,
        minTotalMiles: 5.0,
        maxTotalMiles: 9.0,
        intensityProgression: .gradual,
        builder: { ctx in
            let repCount: Int
            switch ctx.raceDistance {
            case .mile1500:
                repCount = 8 + Int(ctx.progression * 8)  // 8-16 reps
            case .fiveK:
                repCount = 6 + Int(ctx.progression * 6)  // 6-12 reps
            case .tenK:
                repCount = 5 + Int(ctx.progression * 5)  // 5-10 reps
            default:
                repCount = 6
            }

            // Intensity based on event
            let intervalPace: PaceIntensity
            switch ctx.raceDistance {
            case .mile1500:
                intervalPace = ctx.intensity(108)  // Faster than race pace
            case .fiveK:
                intervalPace = ctx.intensity(105)  // 5K pace or slightly faster
            default:
                intervalPace = ctx.vo2maxPace
            }

            var steps: [CanovaWorkoutStep] = [StepBuilder.warmup(miles: 2.0)]

            for i in 0..<repCount {
                steps.append(StepBuilder.activeMeters(
                    400,
                    intensity: intervalPace,
                    notes: "Rep \(i + 1) of \(repCount)"
                ))
                if i < repCount - 1 {
                    // 200m jog recovery (or ~60-90 seconds)
                    steps.append(StepBuilder.recoveryMeters(200, intensity: 65))
                }
            }

            steps.append(StepBuilder.cooldown(miles: 1.5))

            return WorkoutFactory.create(
                name: "400m Repeats",
                category: .specific,
                phase: ctx.phase,
                description: "\(repCount)x400m @ \(Int(intervalPace.percentage))%",
                steps: steps
            )
        }
    )

    // MARK: - 800m Repeats

    /// Classic 800m repeats at VO2max pace
    static let repeats800m = WorkoutTemplate(
        id: "interval_800m",
        name: "800m Repeats",
        category: .specific,
        workoutType: .intervals,
        raceDistances: [.mile1500, .fiveK, .tenK, .halfMarathon],
        phases: [.base, .support, .specific],
        description: "Half-mile repeats for VO2max development",
        progressionType: .volume,
        minTotalMiles: 6.0,
        maxTotalMiles: 10.0,
        intensityProgression: .gradual,
        builder: { ctx in
            let repCount: Int
            switch ctx.raceDistance {
            case .mile1500:
                repCount = 6 + Int(ctx.progression * 4)  // 6-10 reps
            case .fiveK:
                repCount = 5 + Int(ctx.progression * 4)  // 5-9 reps
            case .tenK:
                repCount = 4 + Int(ctx.progression * 4)  // 4-8 reps
            case .halfMarathon:
                repCount = 4 + Int(ctx.progression * 3)  // 4-7 reps
            default:
                repCount = 5
            }

            let intervalPace = ctx.vo2maxPace

            var steps: [CanovaWorkoutStep] = [StepBuilder.warmup(miles: 2.0)]

            for i in 0..<repCount {
                steps.append(StepBuilder.activeMeters(
                    800,
                    intensity: intervalPace,
                    notes: "Rep \(i + 1) of \(repCount)"
                ))
                if i < repCount - 1 {
                    // 400m jog recovery
                    steps.append(StepBuilder.recoveryMeters(400, intensity: 65))
                }
            }

            steps.append(StepBuilder.cooldown(miles: 1.5))

            return WorkoutFactory.create(
                name: "800m Repeats",
                category: .specific,
                phase: ctx.phase,
                description: "\(repCount)x800m @ VO2max",
                steps: steps
            )
        }
    )

    // MARK: - 1K Repeats

    /// 1000m repeats at 5K to 10K pace
    static let repeats1K = WorkoutTemplate(
        id: "interval_1k",
        name: "1K Repeats",
        category: .specific,
        workoutType: .intervals,
        raceDistances: [.fiveK, .tenK, .halfMarathon],
        phases: [.base, .support, .specific],
        description: "Kilometer repeats for specific endurance",
        progressionType: .volume,
        minTotalMiles: 7.0,
        maxTotalMiles: 12.0,
        intensityProgression: .gradual,
        builder: { ctx in
            let repCount: Int
            let intervalPace: PaceIntensity

            switch ctx.raceDistance {
            case .fiveK:
                repCount = 5 + Int(ctx.progression * 3)  // 5-8 reps
                intervalPace = ctx.racePace  // 5K pace
            case .tenK:
                repCount = 5 + Int(ctx.progression * 4)  // 5-9 reps
                intervalPace = ctx.intensity(105)  // 5K pace
            case .halfMarathon:
                repCount = 4 + Int(ctx.progression * 4)  // 4-8 reps
                intervalPace = ctx.intensity(110)  // ~5K-10K pace
            default:
                repCount = 5
                intervalPace = ctx.vo2maxPace
            }

            var steps: [CanovaWorkoutStep] = [StepBuilder.warmup(miles: 2.0)]

            for i in 0..<repCount {
                steps.append(StepBuilder.activeMeters(
                    1000,
                    intensity: intervalPace,
                    notes: "Rep \(i + 1) of \(repCount)"
                ))
                if i < repCount - 1 {
                    // 400m jog recovery
                    steps.append(StepBuilder.recoveryMeters(400, intensity: 65))
                }
            }

            steps.append(StepBuilder.cooldown(miles: 1.5))

            return WorkoutFactory.create(
                name: "1K Repeats",
                category: .specific,
                phase: ctx.phase,
                description: "\(repCount)x1000m @ \(Int(intervalPace.percentage))%",
                steps: steps
            )
        }
    )

    // MARK: - Mile Repeats

    /// Mile repeats at threshold to VO2max pace
    static let repeatsMile = WorkoutTemplate(
        id: "interval_mile",
        name: "Mile Repeats",
        category: .specific,
        workoutType: .intervals,
        raceDistances: [.tenK, .halfMarathon, .marathon],
        phases: [.specific],
        description: "Mile repeats for lactate clearance and pace judgment",
        progressionType: .volume,
        minTotalMiles: 8.0,
        maxTotalMiles: 14.0,
        intensityProgression: .gradual,
        builder: { ctx in
            let repCount: Int
            let intervalPace: PaceIntensity

            switch ctx.raceDistance {
            case .tenK:
                repCount = 3 + Int(ctx.progression * 2)  // 3-5 reps
                intervalPace = ctx.racePace  // 10K pace
            case .halfMarathon:
                repCount = 3 + Int(ctx.progression * 3)  // 3-6 reps
                intervalPace = ctx.intensity(105)  // ~10K pace
            case .marathon:
                repCount = 4 + Int(ctx.progression * 3)  // 4-7 reps
                intervalPace = ctx.intensity(108)  // ~10K pace
            default:
                repCount = 4
                intervalPace = ctx.thresholdPace
            }

            var steps: [CanovaWorkoutStep] = [StepBuilder.warmup(miles: 2.0)]

            for i in 0..<repCount {
                steps.append(StepBuilder.active(
                    miles: 1.0,
                    intensity: intervalPace,
                    notes: "Mile \(i + 1) of \(repCount)"
                ))
                if i < repCount - 1 {
                    // 0.25 mile jog recovery
                    steps.append(StepBuilder.recovery(miles: 0.25, intensity: 70))
                }
            }

            steps.append(StepBuilder.cooldown(miles: 1.5))

            return WorkoutFactory.create(
                name: "Mile Repeats",
                category: .specific,
                phase: ctx.phase,
                description: "\(repCount)x1mi @ \(Int(intervalPace.percentage))%",
                steps: steps
            )
        }
    )

    // MARK: - 2K/2-Mile Repeats

    /// Longer repeats for specific endurance
    static let repeats2K = WorkoutTemplate(
        id: "interval_2k",
        name: "2K Repeats",
        category: .specific,
        workoutType: .intervals,
        raceDistances: [.tenK, .halfMarathon, .marathon],
        phases: [.specific],
        description: "Extended repeats at race-specific pace",
        progressionType: .volume,
        minTotalMiles: 9.0,
        maxTotalMiles: 15.0,
        intensityProgression: .gradual,
        builder: { ctx in
            let repCount: Int
            let intervalPace: PaceIntensity
            let repDistance = 1.25  // ~2K in miles

            switch ctx.raceDistance {
            case .tenK:
                repCount = 3 + Int(ctx.progression * 2)  // 3-5 reps
                intervalPace = ctx.racePace  // 10K pace
            case .halfMarathon:
                repCount = 3 + Int(ctx.progression * 3)  // 3-6 reps
                intervalPace = ctx.racePace  // HM pace
            case .marathon:
                repCount = 3 + Int(ctx.progression * 3)  // 3-6 reps
                intervalPace = ctx.intensity(105)  // ~HM pace
            default:
                repCount = 4
                intervalPace = ctx.thresholdPace
            }

            var steps: [CanovaWorkoutStep] = [StepBuilder.warmup(miles: 2.0)]

            for i in 0..<repCount {
                steps.append(StepBuilder.active(
                    miles: repDistance,
                    intensity: intervalPace,
                    notes: "Rep \(i + 1) of \(repCount)"
                ))
                if i < repCount - 1 {
                    // 0.5 mile float recovery
                    steps.append(StepBuilder.recovery(miles: 0.5, intensity: 75))
                }
            }

            steps.append(StepBuilder.cooldown(miles: 1.5))

            return WorkoutFactory.create(
                name: "2K Repeats",
                category: .specific,
                phase: ctx.phase,
                description: "\(repCount)x2K @ \(Int(intervalPace.percentage))%",
                steps: steps
            )
        }
    )

    // MARK: - Cutdown Intervals

    /// Descending distance with increasing pace
    static let cutdownIntervals = WorkoutTemplate(
        id: "interval_cutdown",
        name: "Cutdown Intervals",
        category: .specific,
        workoutType: .intervals,
        raceDistances: RaceDistance.allCases,
        phases: [.specific],
        description: "Decreasing distance, increasing pace",
        progressionType: .complexity,
        minTotalMiles: 7.0,
        maxTotalMiles: 12.0,
        intensityProgression: .none,
        builder: { ctx in
            // Structure: longer to shorter with faster paces
            let structure: [(meters: Double, intensityBonus: Double)]

            switch ctx.raceDistance {
            case .mile1500, .fiveK:
                // 1200, 1000, 800, 600, 400
                structure = [(1200, 0), (1000, 2), (800, 4), (600, 6), (400, 8)]
            case .tenK:
                // 1600, 1200, 1000, 800, 400
                structure = [(1609, 0), (1200, 2), (1000, 4), (800, 6), (400, 8)]
            case .halfMarathon, .marathon:
                // 2000, 1600, 1200, 800, 400
                structure = [(2000, 0), (1609, 2), (1200, 4), (800, 6), (400, 8)]
            }

            let basePace = ctx.vo2maxPace.percentage

            var steps: [CanovaWorkoutStep] = [StepBuilder.warmup(miles: 2.0)]

            for (i, (meters, bonus)) in structure.enumerated() {
                steps.append(StepBuilder.activeMeters(
                    meters,
                    intensity: ctx.intensity(basePace + bonus),
                    notes: "Rep \(i + 1) - \(Int(meters))m"
                ))
                if i < structure.count - 1 {
                    // Equal jog recovery
                    steps.append(StepBuilder.recoveryTime(
                        seconds: Double(Int(meters / 1609.34 * 60 * 8)),  // ~time to run at 8:00 pace
                        intensity: 65
                    ))
                }
            }

            steps.append(StepBuilder.cooldown(miles: 1.5))

            return WorkoutFactory.create(
                name: "Cutdown Intervals",
                category: .specific,
                phase: ctx.phase,
                description: "Descending ladder with increasing pace",
                steps: steps
            )
        }
    )

    // MARK: - Pyramid/Ladder

    /// Classic pyramid workout
    static let pyramidLadder = WorkoutTemplate(
        id: "interval_pyramid",
        name: "Pyramid Ladder",
        category: .specific,
        workoutType: .intervals,
        raceDistances: [.mile1500, .fiveK, .tenK],
        phases: [.specific],
        description: "Up and down ladder workout",
        progressionType: .complexity,
        minTotalMiles: 7.0,
        maxTotalMiles: 11.0,
        intensityProgression: .none,
        builder: { ctx in
            // Classic: 400-800-1200-1600-1200-800-400
            let ladder: [Double]
            switch ctx.raceDistance {
            case .mile1500:
                ladder = [200, 400, 600, 800, 600, 400, 200]
            case .fiveK:
                ladder = [400, 800, 1200, 1600, 1200, 800, 400]
            default:
                ladder = [400, 800, 1200, 1600, 1200, 800, 400]
            }

            var steps: [CanovaWorkoutStep] = [StepBuilder.warmup(miles: 2.0)]

            for (i, meters) in ladder.enumerated() {
                steps.append(StepBuilder.activeMeters(
                    meters,
                    intensity: ctx.vo2maxPace,
                    notes: "\(Int(meters))m"
                ))
                if i < ladder.count - 1 {
                    // 200m jog between
                    steps.append(StepBuilder.recoveryMeters(200, intensity: 65))
                }
            }

            steps.append(StepBuilder.cooldown(miles: 1.5))

            return WorkoutFactory.create(
                name: "Pyramid Ladder",
                category: .specific,
                phase: ctx.phase,
                description: "Ladder: \(ladder.map { "\(Int($0))m" }.joined(separator: "-"))",
                steps: steps,
                signatureType: .descendingLadder
            )
        }
    )

    // MARK: - Canova Descending Ladder

    /// Canova-style 6+5+4+3+2+1 km ladder
    static let canovaLadder = WorkoutTemplate(
        id: "interval_canova_ladder",
        name: "Canova Ladder",
        category: .specific,
        workoutType: .intervals,
        raceDistances: [.halfMarathon, .marathon],
        phases: [.specific],
        description: "Classic 6+5+4+3+2+1 km descending ladder",
        progressionType: .intensity,
        minTotalMiles: 15.0,
        maxTotalMiles: 18.0,
        intensityProgression: .gradual,
        builder: { ctx in
            // 6km, 5km, 4km, 3km, 2km, 1km
            let kmDistances = [6.0, 5.0, 4.0, 3.0, 2.0, 1.0]

            // Pace gets progressively faster
            let paces: [Double]
            if ctx.raceDistance == .marathon {
                // Start at MP, end at 10K pace
                paces = [100, 102, 104, 106, 108, 110]
            } else {
                // Start at HMP, end at 5K pace
                paces = [100, 103, 106, 109, 112, 115]
            }

            var steps: [CanovaWorkoutStep] = [StepBuilder.warmup(miles: 2.0)]

            for (i, km) in kmDistances.enumerated() {
                let miles = km / 1.60934
                steps.append(StepBuilder.active(
                    miles: miles,
                    intensity: ctx.intensity(paces[i]),
                    notes: "\(Int(km))K"
                ))
                if i < kmDistances.count - 1 {
                    // 1K float recovery
                    steps.append(StepBuilder.recovery(miles: 0.62, intensity: 75))
                }
            }

            steps.append(StepBuilder.cooldown(miles: 1.5))

            return WorkoutFactory.create(
                name: "Canova Ladder",
                category: .specific,
                phase: ctx.phase,
                description: "6+5+4+3+2+1 km with float recoveries",
                steps: steps,
                signatureType: .descendingLadder
            )
        }
    )

    // MARK: - Half Marathon Pace Repeats

    /// HM pace repeats for marathon runners
    static let hmPaceRepeats = WorkoutTemplate(
        id: "interval_hm_pace",
        name: "HM Pace Repeats",
        category: .specific,
        workoutType: .intervals,
        raceDistances: [.halfMarathon, .marathon],
        phases: [.specific],
        description: "Extended repeats at half marathon pace",
        progressionType: .volume,
        minTotalMiles: 10.0,
        maxTotalMiles: 16.0,
        intensityProgression: .gradual,
        builder: { ctx in
            let repCount: Int
            let repDistance: Double
            let pace: PaceIntensity

            switch ctx.raceDistance {
            case .halfMarathon:
                repCount = 3 + Int(ctx.progression * 3)  // 3-6 reps
                repDistance = 1.25  // ~2K
                pace = ctx.racePace
            case .marathon:
                repCount = 3 + Int(ctx.progression * 4)  // 3-7 reps
                repDistance = 1.5   // ~2.5K
                pace = ctx.intensity(105)  // HM pace
            default:
                repCount = 4
                repDistance = 1.5
                pace = ctx.thresholdPace
            }

            var steps: [CanovaWorkoutStep] = [StepBuilder.warmup(miles: 2.0)]

            for i in 0..<repCount {
                steps.append(StepBuilder.active(
                    miles: repDistance,
                    intensity: pace,
                    notes: "Rep \(i + 1) of \(repCount)"
                ))
                if i < repCount - 1 {
                    // Float recovery
                    steps.append(StepBuilder.recovery(miles: 0.5, intensity: 75))
                }
            }

            steps.append(StepBuilder.cooldown(miles: 1.5))

            return WorkoutFactory.create(
                name: "HM Pace Repeats",
                category: .specific,
                phase: ctx.phase,
                description: "\(repCount)x\(String(format: "%.1f", repDistance))mi @ HM pace",
                steps: steps
            )
        }
    )

    // MARK: - Race Pace Repeats

    /// Event-specific race pace repeats
    static let racePaceRepeats = WorkoutTemplate(
        id: "interval_race_pace",
        name: "Race Pace Repeats",
        category: .specific,
        workoutType: .intervals,
        raceDistances: RaceDistance.allCases,
        phases: [.specific],
        description: "Repeats at goal race pace",
        progressionType: .volume,
        minTotalMiles: 7.0,
        maxTotalMiles: 14.0,
        intensityProgression: .none,
        builder: { ctx in
            let repCount: Int
            let repDistance: Double

            switch ctx.raceDistance {
            case .mile1500:
                repCount = 4 + Int(ctx.progression * 4)  // 4-8 reps
                repDistance = 0.25  // 400m
            case .fiveK:
                repCount = 4 + Int(ctx.progression * 4)  // 4-8 reps
                repDistance = 0.62  // 1K
            case .tenK:
                repCount = 4 + Int(ctx.progression * 3)  // 4-7 reps
                repDistance = 0.62  // 1K
            case .halfMarathon:
                repCount = 3 + Int(ctx.progression * 4)  // 3-7 reps
                repDistance = 1.0   // Mile
            case .marathon:
                repCount = 3 + Int(ctx.progression * 5)  // 3-8 reps
                repDistance = 1.5   // ~2.5K
            }

            var steps: [CanovaWorkoutStep] = [StepBuilder.warmup(miles: 2.0)]

            for i in 0..<repCount {
                steps.append(StepBuilder.active(
                    miles: repDistance,
                    intensity: ctx.racePace,
                    notes: "Rep \(i + 1) - Goal race pace"
                ))
                if i < repCount - 1 {
                    // Float recovery (shorter for shorter events)
                    let recoveryMiles = ctx.raceDistance == .mile1500 || ctx.raceDistance == .fiveK ? 0.25 : 0.5
                    steps.append(StepBuilder.recovery(miles: recoveryMiles, intensity: 75))
                }
            }

            steps.append(StepBuilder.cooldown(miles: 1.5))

            return WorkoutFactory.create(
                name: "Race Pace Repeats",
                category: .specific,
                phase: ctx.phase,
                description: "\(repCount)x\(String(format: "%.2f", repDistance))mi @ race pace",
                steps: steps,
                signatureType: .racePaceRepeats
            )
        }
    )

    // MARK: - Mixed Intervals

    /// Combination workout with different distances
    static let mixedIntervals = WorkoutTemplate(
        id: "interval_mixed",
        name: "Mixed Intervals",
        category: .specific,
        workoutType: .intervals,
        raceDistances: [.fiveK, .tenK, .halfMarathon],
        phases: [.specific],
        description: "Varied distances in one session",
        progressionType: .complexity,
        minTotalMiles: 8.0,
        maxTotalMiles: 12.0,
        intensityProgression: .none,
        builder: { ctx in
            // Structure varies by event
            let sets: [(meters: Double, reps: Int, intensity: Double)]

            switch ctx.raceDistance {
            case .fiveK:
                sets = [
                    (1000, 2, ctx.racePace.percentage),
                    (600, 3, ctx.racePace.percentage + 3),
                    (400, 4, ctx.racePace.percentage + 5)
                ]
            case .tenK:
                sets = [
                    (1609, 2, ctx.racePace.percentage),
                    (1000, 3, ctx.racePace.percentage + 3),
                    (600, 4, ctx.racePace.percentage + 5)
                ]
            default:
                sets = [
                    (2000, 2, ctx.thresholdPace.percentage),
                    (1000, 3, ctx.thresholdPace.percentage + 3),
                    (600, 4, ctx.thresholdPace.percentage + 5)
                ]
            }

            var steps: [CanovaWorkoutStep] = [StepBuilder.warmup(miles: 2.0)]

            for (setIndex, set) in sets.enumerated() {
                for rep in 0..<set.reps {
                    steps.append(StepBuilder.activeMeters(
                        set.meters,
                        intensity: ctx.intensity(set.intensity),
                        notes: "Set \(setIndex + 1), rep \(rep + 1)"
                    ))
                    if rep < set.reps - 1 {
                        steps.append(StepBuilder.recoveryMeters(200, intensity: 65))
                    }
                }
                if setIndex < sets.count - 1 {
                    // Longer recovery between sets
                    steps.append(StepBuilder.recoveryTime(seconds: 180, intensity: 65))
                }
            }

            steps.append(StepBuilder.cooldown(miles: 1.5))

            return WorkoutFactory.create(
                name: "Mixed Intervals",
                category: .specific,
                phase: ctx.phase,
                description: "Multiple distances at varied paces",
                steps: steps
            )
        }
    )

    // MARK: - Taper Intervals

    /// Short, sharp intervals for race preparation
    static let taperIntervals = WorkoutTemplate(
        id: "interval_taper",
        name: "Taper Intervals",
        category: .specific,
        workoutType: .intervals,
        raceDistances: RaceDistance.allCases,
        phases: [.taper],
        description: "Short repeats to maintain sharpness during taper",
        progressionType: .static_,
        minTotalMiles: 5.0,
        maxTotalMiles: 7.0,
        intensityProgression: .none,
        builder: { ctx in
            let repCount: Int
            let distance: Double

            switch ctx.raceDistance {
            case .mile1500, .fiveK:
                repCount = 4
                distance = 400
            case .tenK:
                repCount = 4
                distance = 600
            case .halfMarathon, .marathon:
                repCount = 4
                distance = 800
            }

            // Slightly faster than race pace for sharpness
            let pace = ctx.intensity(ctx.racePace.percentage + 3)

            var steps: [CanovaWorkoutStep] = [StepBuilder.warmup(miles: 1.5)]

            for i in 0..<repCount {
                steps.append(StepBuilder.activeMeters(
                    distance,
                    intensity: pace,
                    notes: "Rep \(i + 1) - crisp!"
                ))
                if i < repCount - 1 {
                    steps.append(StepBuilder.recoveryMeters(400, intensity: 65))
                }
            }

            steps.append(StepBuilder.cooldown(miles: 1.5))

            return WorkoutFactory.create(
                name: "Taper Intervals",
                category: .specific,
                phase: ctx.phase,
                description: "\(repCount)x\(Int(distance))m - tune-up",
                steps: steps
            )
        }
    )

    // MARK: - All Interval Templates

    static var all: [WorkoutTemplate] {
        [
            repeats400m,
            repeats800m,
            repeats1K,
            repeatsMile,
            repeats2K,
            cutdownIntervals,
            pyramidLadder,
            canovaLadder,
            hmPaceRepeats,
            racePaceRepeats,
            mixedIntervals,
            taperIntervals
        ]
    }
}

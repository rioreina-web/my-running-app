//
//  EasyRecoveryTemplates.swift
//  RunningLog
//
//  Easy and recovery workout templates for all race distances.
//

import Foundation

// MARK: - Easy/Recovery Templates

/// Collection of easy and recovery workout templates
struct EasyRecoveryTemplates {

    // MARK: - Easy Run

    /// Standard easy run for aerobic development
    static let easyRun = WorkoutTemplate(
        id: "easy_run",
        name: "Easy Run",
        category: .regeneration,
        workoutType: .easy,
        raceDistances: RaceDistance.allCases,
        phases: [.base, .specific, .taper],
        description: "Relaxed aerobic run at conversational pace",
        progressionType: .volume,
        minTotalMiles: 4.0,
        maxTotalMiles: 10.0,
        intensityProgression: .none,
        builder: { ctx in
            let distance: Double
            switch ctx.raceDistance {
            case .mile1500:
                distance = 4.0 + (ctx.progression * 3.0)  // 4-7 mi
            case .fiveK:
                distance = 4.0 + (ctx.progression * 4.0)  // 4-8 mi
            case .tenK:
                distance = 5.0 + (ctx.progression * 4.0)  // 5-9 mi
            case .halfMarathon:
                distance = 5.0 + (ctx.progression * 5.0)  // 5-10 mi
            case .marathon:
                distance = 6.0 + (ctx.progression * 4.0)  // 6-10 mi
            }

            let run = StepBuilder.active(
                miles: distance,
                intensity: ctx.easyPace,
                notes: "Relaxed, conversational pace"
            )

            return WorkoutFactory.create(
                name: "Easy Run",
                category: .regeneration,
                phase: ctx.phase,
                description: String(format: "%.0f miles easy", distance),
                steps: [run]
            )
        }
    )

    // MARK: - Aerobic Run

    /// Slightly brisker aerobic run
    static let aerobicRun = WorkoutTemplate(
        id: "easy_aerobic",
        name: "Aerobic Run",
        category: .fundamental,
        workoutType: .easy,
        raceDistances: RaceDistance.allCases,
        phases: [.base, .specific],
        description: "Moderate aerobic effort, slightly faster than easy",
        progressionType: .volume,
        minTotalMiles: 5.0,
        maxTotalMiles: 10.0,
        intensityProgression: .none,
        builder: { ctx in
            let distance: Double
            switch ctx.raceDistance {
            case .mile1500, .fiveK:
                distance = 5.0 + (ctx.progression * 3.0)  // 5-8 mi
            case .tenK:
                distance = 5.0 + (ctx.progression * 4.0)  // 5-9 mi
            case .halfMarathon, .marathon:
                distance = 6.0 + (ctx.progression * 4.0)  // 6-10 mi
            }

            // Aerobic = easy pace + 5%
            let aerobicPace = ctx.intensity(ctx.easyPace.percentage + 5)

            let run = StepBuilder.active(
                miles: distance,
                intensity: aerobicPace,
                notes: "Moderate aerobic effort, controlled breathing"
            )

            return WorkoutFactory.create(
                name: "Aerobic Run",
                category: .fundamental,
                phase: ctx.phase,
                description: String(format: "%.0f miles moderate aerobic", distance),
                steps: [run]
            )
        }
    )

    // MARK: - Recovery Run

    /// Very easy recovery run
    static let recoveryRun = WorkoutTemplate(
        id: "easy_recovery",
        name: "Recovery Run",
        category: .regeneration,
        workoutType: .recovery,
        raceDistances: RaceDistance.allCases,
        phases: [.base, .specific, .taper],
        description: "Very easy run for active recovery",
        progressionType: .static_,
        minTotalMiles: 3.0,
        maxTotalMiles: 6.0,
        intensityProgression: .none,
        builder: { ctx in
            let distance: Double
            switch ctx.raceDistance {
            case .mile1500, .fiveK:
                distance = 3.0 + (ctx.progression * 2.0)  // 3-5 mi
            case .tenK:
                distance = 4.0 + (ctx.progression * 2.0)  // 4-6 mi
            case .halfMarathon, .marathon:
                distance = 4.0 + (ctx.progression * 2.0)  // 4-6 mi
            }

            // Recovery = very easy, lower than normal easy pace
            let recoveryPace = ctx.intensity(ctx.easyPace.percentage - 5)

            let run = StepBuilder.active(
                miles: distance,
                intensity: recoveryPace,
                notes: "Very easy, promote recovery"
            )

            return WorkoutFactory.create(
                name: "Recovery Run",
                category: .regeneration,
                phase: ctx.phase,
                description: String(format: "%.0f miles very easy", distance),
                steps: [run]
            )
        }
    )

    // MARK: - Recovery + Strides

    /// Easy run followed by strides
    static let recoveryWithStrides = WorkoutTemplate(
        id: "easy_recovery_strides",
        name: "Recovery + Strides",
        category: .regeneration,
        workoutType: .strides,
        raceDistances: RaceDistance.allCases,
        phases: [.base, .specific, .taper],
        description: "Easy run with fast strides for neuromuscular activation",
        progressionType: .static_,
        minTotalMiles: 4.0,
        maxTotalMiles: 7.0,
        intensityProgression: .none,
        builder: { ctx in
            let baseMiles: Double
            switch ctx.raceDistance {
            case .mile1500, .fiveK:
                baseMiles = 4.0
            case .tenK:
                baseMiles = 5.0
            case .halfMarathon, .marathon:
                baseMiles = 5.0
            }

            var steps: [CanovaWorkoutStep] = [
                StepBuilder.active(miles: baseMiles, intensity: ctx.easyPace, notes: "Easy running")
            ]

            // 4-6 strides
            let strideCount = 4 + Int(ctx.progression * 2)
            for i in 0..<strideCount {
                steps.append(StepBuilder.activeMeters(
                    100,
                    intensity: ctx.intensity(110),
                    notes: "Stride \(i + 1) - smooth acceleration"
                ))
                if i < strideCount - 1 {
                    steps.append(StepBuilder.recoveryMeters(100, intensity: 60))
                }
            }

            return WorkoutFactory.create(
                name: "Recovery + Strides",
                category: .regeneration,
                phase: ctx.phase,
                description: String(format: "%.0f mi easy + %d strides", baseMiles, strideCount),
                steps: steps
            )
        }
    )

    // MARK: - Easy + Strides

    /// Standard easy run with strides
    static let easyWithStrides = WorkoutTemplate(
        id: "easy_strides",
        name: "Easy + Strides",
        category: .fundamental,
        workoutType: .strides,
        raceDistances: RaceDistance.allCases,
        phases: [.base, .specific, .taper],
        description: "Easy run with strides for leg turnover",
        progressionType: .volume,
        minTotalMiles: 5.0,
        maxTotalMiles: 9.0,
        intensityProgression: .none,
        builder: { ctx in
            let baseMiles: Double
            switch ctx.raceDistance {
            case .mile1500, .fiveK:
                baseMiles = 5.0 + (ctx.progression * 2.0)  // 5-7 mi
            case .tenK:
                baseMiles = 5.0 + (ctx.progression * 3.0)  // 5-8 mi
            case .halfMarathon, .marathon:
                baseMiles = 6.0 + (ctx.progression * 3.0)  // 6-9 mi
            }

            var steps: [CanovaWorkoutStep] = [
                StepBuilder.active(miles: baseMiles, intensity: ctx.easyPace, notes: "Easy aerobic running")
            ]

            // 6-8 strides
            let strideCount = 6 + Int(ctx.progression * 2)
            for i in 0..<strideCount {
                steps.append(StepBuilder.activeMeters(
                    100,
                    intensity: ctx.intensity(115),
                    notes: "Stride \(i + 1)"
                ))
                if i < strideCount - 1 {
                    steps.append(StepBuilder.recoveryMeters(100, intensity: 60))
                }
            }

            return WorkoutFactory.create(
                name: "Easy + Strides",
                category: .fundamental,
                phase: ctx.phase,
                description: String(format: "%.0f mi easy + %d strides", baseMiles, strideCount),
                steps: steps
            )
        }
    )

    // MARK: - Shakeout Run

    /// Short, easy shakeout run (pre-race or pre-workout)
    static let shakeoutRun = WorkoutTemplate(
        id: "easy_shakeout",
        name: "Shakeout Run",
        category: .regeneration,
        workoutType: .easy,
        raceDistances: RaceDistance.allCases,
        phases: [.base, .specific, .taper],
        description: "Short easy run to loosen up",
        progressionType: .static_,
        minTotalMiles: 2.0,
        maxTotalMiles: 4.0,
        intensityProgression: .none,
        builder: { ctx in
            let distance: Double
            switch ctx.raceDistance {
            case .mile1500, .fiveK:
                distance = 2.0 + (ctx.progression * 1.0)  // 2-3 mi
            case .tenK:
                distance = 2.5 + (ctx.progression * 1.0)  // 2.5-3.5 mi
            case .halfMarathon, .marathon:
                distance = 3.0 + (ctx.progression * 1.0)  // 3-4 mi
            }

            let run = StepBuilder.active(
                miles: distance,
                intensity: ctx.intensity(ctx.easyPace.percentage - 3),
                notes: "Easy shakeout - loosen the legs"
            )

            return WorkoutFactory.create(
                name: "Shakeout Run",
                category: .regeneration,
                phase: ctx.phase,
                description: String(format: "%.0f miles easy shakeout", distance),
                steps: [run]
            )
        }
    )

    // MARK: - AM Easy (Double Day)

    /// Morning easy run for double days
    static let amEasyRun = WorkoutTemplate(
        id: "easy_am_double",
        name: "AM Easy Run",
        category: .regeneration,
        workoutType: .easy,
        raceDistances: RaceDistance.allCases,
        phases: [.base, .specific],
        description: "Morning easy run for double day",
        progressionType: .volume,
        minTotalMiles: 3.0,
        maxTotalMiles: 6.0,
        intensityProgression: .none,
        builder: { ctx in
            let distance: Double
            switch ctx.raceDistance {
            case .mile1500, .fiveK:
                distance = 3.0 + (ctx.progression * 2.0)  // 3-5 mi
            case .tenK:
                distance = 4.0 + (ctx.progression * 2.0)  // 4-6 mi
            case .halfMarathon, .marathon:
                distance = 4.0 + (ctx.progression * 2.0)  // 4-6 mi
            }

            let run = StepBuilder.active(
                miles: distance,
                intensity: ctx.easyPace,
                notes: "AM run - easy effort"
            )

            return WorkoutFactory.create(
                name: "AM Easy Run",
                category: .regeneration,
                phase: ctx.phase,
                description: String(format: "%.0f miles AM easy", distance),
                steps: [run]
            )
        }
    )

    // MARK: - PM Easy (Double Day)

    /// Afternoon/evening easy run for double days
    static let pmEasyRun = WorkoutTemplate(
        id: "easy_pm_double",
        name: "PM Easy Run",
        category: .regeneration,
        workoutType: .easy,
        raceDistances: RaceDistance.allCases,
        phases: [.base, .specific],
        description: "Afternoon/evening easy run for double day",
        progressionType: .volume,
        minTotalMiles: 3.0,
        maxTotalMiles: 6.0,
        intensityProgression: .none,
        builder: { ctx in
            let distance: Double
            switch ctx.raceDistance {
            case .mile1500, .fiveK:
                distance = 3.0 + (ctx.progression * 2.0)  // 3-5 mi
            case .tenK:
                distance = 4.0 + (ctx.progression * 2.0)  // 4-6 mi
            case .halfMarathon, .marathon:
                distance = 4.0 + (ctx.progression * 2.0)  // 4-6 mi
            }

            let run = StepBuilder.active(
                miles: distance,
                intensity: ctx.intensity(ctx.easyPace.percentage - 2),  // Slightly easier for PM
                notes: "PM run - relaxed effort"
            )

            return WorkoutFactory.create(
                name: "PM Easy Run",
                category: .regeneration,
                phase: ctx.phase,
                description: String(format: "%.0f miles PM easy", distance),
                steps: [run]
            )
        }
    )

    // MARK: - All Easy/Recovery Templates

    static var all: [WorkoutTemplate] {
        [
            easyRun,
            aerobicRun,
            recoveryRun,
            recoveryWithStrides,
            easyWithStrides,
            shakeoutRun,
            amEasyRun,
            pmEasyRun
        ]
    }
}

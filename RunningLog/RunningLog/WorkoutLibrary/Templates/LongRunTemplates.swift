//
//  LongRunTemplates.swift
//  RunningLog
//
//  Long run workout templates for all race distances.
//

import Foundation

// MARK: - Long Run Templates

/// Collection of long run workout templates
struct LongRunTemplates {

    // MARK: - Easy Long Run

    /// Pure aerobic long run at easy pace
    static let easyLongRun = WorkoutTemplate(
        id: "long_easy",
        name: "Easy Long Run",
        category: .fundamental,
        workoutType: .longRun,
        raceDistances: RaceDistance.allCases,
        phases: [.base, .support, .specific, .taper],
        description: "Aerobic endurance builder at comfortable pace",
        progressionType: .volume,
        minTotalMiles: 8.0,
        maxTotalMiles: 22.0,
        intensityProgression: .none,
        builder: { ctx in
            // Scale distance based on event
            let maxDistance: Double
            switch ctx.raceDistance {
            case .mile1500:
                maxDistance = 10.0 + (ctx.progression * 4.0)  // 10-14 mi
            case .fiveK:
                maxDistance = 10.0 + (ctx.progression * 5.0)  // 10-15 mi
            case .tenK:
                maxDistance = 11.0 + (ctx.progression * 6.0)  // 11-17 mi
            case .halfMarathon:
                maxDistance = 12.0 + (ctx.progression * 8.0)  // 12-20 mi
            case .marathon:
                maxDistance = 14.0 + (ctx.progression * 8.0)  // 14-22 mi
            }

            let longRun = StepBuilder.active(
                miles: maxDistance,
                intensity: ctx.longRunPace,
                notes: "Comfortable, conversational pace"
            )

            return WorkoutFactory.create(
                name: "Easy Long Run",
                category: .fundamental,
                phase: ctx.phase,
                description: String(format: "%.0f miles at easy pace", maxDistance),
                steps: [longRun]
            )
        }
    )

    // MARK: - Steady Long Run

    /// Long run at moderate/steady effort
    static let steadyLongRun = WorkoutTemplate(
        id: "long_steady",
        name: "Steady Long Run",
        category: .special,
        workoutType: .longRun,
        raceDistances: [.tenK, .halfMarathon, .marathon],
        phases: [.base, .support, .specific],
        description: "Long run at moderate steady effort",
        progressionType: .hybrid,
        minTotalMiles: 10.0,
        maxTotalMiles: 18.0,
        intensityProgression: .gradual,
        builder: { ctx in
            let distance: Double
            switch ctx.raceDistance {
            case .tenK:
                distance = 10.0 + (ctx.progression * 5.0)  // 10-15 mi
            case .halfMarathon:
                distance = 11.0 + (ctx.progression * 6.0)  // 11-17 mi
            case .marathon:
                distance = 12.0 + (ctx.progression * 6.0)  // 12-18 mi
            default:
                distance = 10.0
            }

            // Steady = ~85% of race effort
            let steadyPace = ctx.intensity(ctx.raceDistance.easyPaceIntensity + 8)

            let warmup = StepBuilder.active(
                miles: 2.0,
                intensity: ctx.easyPace,
                notes: "Easy start"
            )
            let steady = StepBuilder.active(
                miles: distance - 3.0,
                intensity: steadyPace,
                notes: "Steady, controlled effort"
            )
            let cooldown = StepBuilder.active(
                miles: 1.0,
                intensity: ctx.easyPace,
                notes: "Easy finish"
            )

            return WorkoutFactory.create(
                name: "Steady Long Run",
                category: .special,
                phase: ctx.phase,
                description: String(format: "%.0f mi with %.0f mi steady", distance, distance - 3.0),
                steps: [warmup, steady, cooldown]
            )
        }
    )

    // MARK: - Progression Long Run

    /// Long run with progressively faster final miles
    static let progressionLongRun = WorkoutTemplate(
        id: "long_progression",
        name: "Progression Long Run",
        category: .special,
        workoutType: .longRun,
        raceDistances: [.tenK, .halfMarathon, .marathon],
        phases: [.base, .support, .specific],
        description: "Negative split long run building to tempo finish",
        progressionType: .hybrid,
        minTotalMiles: 10.0,
        maxTotalMiles: 20.0,
        intensityProgression: .backLoaded,
        builder: { ctx in
            let totalDistance: Double
            let progressionMiles: Double

            switch ctx.raceDistance {
            case .tenK:
                totalDistance = 10.0 + (ctx.progression * 5.0)  // 10-15 mi
                progressionMiles = 3.0 + (ctx.progression * 2.0)  // 3-5 mi
            case .halfMarathon:
                totalDistance = 12.0 + (ctx.progression * 6.0)  // 12-18 mi
                progressionMiles = 4.0 + (ctx.progression * 2.0)  // 4-6 mi
            case .marathon:
                totalDistance = 14.0 + (ctx.progression * 6.0)  // 14-20 mi
                progressionMiles = 5.0 + (ctx.progression * 3.0)  // 5-8 mi
            default:
                totalDistance = 12.0
                progressionMiles = 4.0
            }

            let easyMiles = totalDistance - progressionMiles

            let easySection = StepBuilder.active(
                miles: easyMiles,
                intensity: ctx.longRunPace,
                notes: "Easy, relaxed pace"
            )

            // Build through 3 segments
            let segmentMiles = progressionMiles / 3.0
            let intensities: [Double] = [85, 90, ctx.tempoPace.percentage]

            var steps: [CanovaWorkoutStep] = [easySection]
            for (i, intensity) in intensities.enumerated() {
                steps.append(StepBuilder.active(
                    miles: segmentMiles,
                    intensity: ctx.intensity(intensity),
                    notes: "Build \(i + 1) of 3"
                ))
            }

            return WorkoutFactory.create(
                name: "Progression Long Run",
                category: .special,
                phase: ctx.phase,
                description: String(format: "%.0f mi easy + %.0f mi progression", easyMiles, progressionMiles),
                steps: steps
            )
        }
    )

    // MARK: - MP Finish Long Run

    /// Long run with marathon pace finish
    static let mpFinishLongRun = WorkoutTemplate(
        id: "long_mp_finish",
        name: "MP Finish Long Run",
        category: .specific,
        workoutType: .longRun,
        raceDistances: [.halfMarathon, .marathon],
        phases: [.specific],
        description: "Long run finishing at race pace",
        progressionType: .hybrid,
        minTotalMiles: 14.0,
        maxTotalMiles: 22.0,
        intensityProgression: .gradual,
        builder: { ctx in
            let totalDistance: Double
            let mpMiles: Double
            let racePace: PaceIntensity

            switch ctx.raceDistance {
            case .halfMarathon:
                totalDistance = 14.0 + (ctx.progression * 4.0)  // 14-18 mi
                mpMiles = 4.0 + (ctx.progression * 3.0)  // 4-7 mi @ HM pace
                racePace = ctx.racePace
            case .marathon:
                totalDistance = 16.0 + (ctx.progression * 6.0)  // 16-22 mi
                mpMiles = 5.0 + (ctx.progression * 5.0)  // 5-10 mi @ MP
                racePace = ctx.racePace
            default:
                totalDistance = 16.0
                mpMiles = 6.0
                racePace = ctx.tempoPace
            }

            let easyMiles = totalDistance - mpMiles

            let easy = StepBuilder.active(
                miles: easyMiles,
                intensity: ctx.longRunPace,
                notes: "Easy aerobic pace"
            )
            let mpFinish = StepBuilder.active(
                miles: mpMiles,
                intensity: racePace,
                notes: "Strong finish at race pace"
            )

            return WorkoutFactory.create(
                name: "MP Finish Long Run",
                category: .specific,
                phase: ctx.phase,
                description: String(format: "%.0f mi easy + %.0f mi @ race pace", easyMiles, mpMiles),
                steps: [easy, mpFinish],
                signatureType: .longRunWithTempo
            )
        }
    )

    // MARK: - MP Sandwich Long Run

    /// Long run with MP segments sandwiched between easy running
    static let mpSandwichLongRun = WorkoutTemplate(
        id: "long_mp_sandwich",
        name: "MP Sandwich Long Run",
        category: .specific,
        workoutType: .longRun,
        raceDistances: [.halfMarathon, .marathon],
        phases: [.specific],
        description: "Race pace segments surrounded by easy running",
        progressionType: .complexity,
        minTotalMiles: 16.0,
        maxTotalMiles: 22.0,
        intensityProgression: .none,
        builder: { ctx in
            let totalDistance: Double
            let mpSegmentMiles: Double
            let segments: Int

            switch ctx.raceDistance {
            case .halfMarathon:
                totalDistance = 16.0 + (ctx.progression * 2.0)  // 16-18 mi
                mpSegmentMiles = 2.0
                segments = 2 + Int(ctx.progression * 2)  // 2-4 segments
            case .marathon:
                totalDistance = 18.0 + (ctx.progression * 4.0)  // 18-22 mi
                mpSegmentMiles = 3.0
                segments = 2 + Int(ctx.progression * 2)  // 2-4 segments
            default:
                totalDistance = 18.0
                mpSegmentMiles = 3.0
                segments = 3
            }

            let totalMpMiles = Double(segments) * mpSegmentMiles
            let totalEasyMiles = totalDistance - totalMpMiles
            let easyBetween = totalEasyMiles / Double(segments + 1)

            var steps: [CanovaWorkoutStep] = []

            // Easy start
            steps.append(StepBuilder.active(
                miles: easyBetween,
                intensity: ctx.longRunPace,
                notes: "Easy warm-up"
            ))

            for i in 0..<segments {
                steps.append(StepBuilder.active(
                    miles: mpSegmentMiles,
                    intensity: ctx.racePace,
                    notes: "MP segment \(i + 1)"
                ))
                steps.append(StepBuilder.active(
                    miles: easyBetween,
                    intensity: ctx.longRunPace,
                    notes: i < segments - 1 ? "Float recovery" : "Easy finish"
                ))
            }

            return WorkoutFactory.create(
                name: "MP Sandwich",
                category: .specific,
                phase: ctx.phase,
                description: String(format: "%.0f mi with %dx%.0f mi @ race pace", totalDistance, segments, mpSegmentMiles),
                steps: steps
            )
        }
    )

    // MARK: - MP Repeats Long Run

    /// Long run with race pace repeats and float recovery
    static let mpRepeatsLongRun = WorkoutTemplate(
        id: "long_mp_repeats",
        name: "MP Repeats Long Run",
        category: .specific,
        workoutType: .longRun,
        raceDistances: [.halfMarathon, .marathon],
        phases: [.specific],
        description: "Race pace repeats with float recovery in long run",
        progressionType: .hybrid,
        minTotalMiles: 16.0,
        maxTotalMiles: 22.0,
        intensityProgression: .gradual,
        builder: { ctx in
            let warmupMiles = 3.0
            let cooldownMiles = 2.0
            let repMiles: Double
            let reps: Int

            switch ctx.raceDistance {
            case .halfMarathon:
                repMiles = 2.0 + (ctx.progression * 1.0)  // 2-3 mi reps
                reps = 3 + Int(ctx.progression * 2)  // 3-5 reps
            case .marathon:
                repMiles = 2.5 + (ctx.progression * 1.5)  // 2.5-4 mi reps
                reps = 3 + Int(ctx.progression * 2)  // 3-5 reps
            default:
                repMiles = 2.0
                reps = 4
            }

            var steps: [CanovaWorkoutStep] = [
                StepBuilder.active(miles: warmupMiles, intensity: ctx.longRunPace, notes: "Easy warm-up")
            ]

            for i in 0..<reps {
                steps.append(StepBuilder.active(
                    miles: repMiles,
                    intensity: ctx.racePace,
                    notes: "MP rep \(i + 1) of \(reps)"
                ))
                if i < reps - 1 {
                    // Float recovery between reps
                    steps.append(StepBuilder.recovery(
                        miles: 0.5,
                        intensity: ctx.longRunPace.percentage - 3
                    ))
                }
            }

            steps.append(StepBuilder.active(miles: cooldownMiles, intensity: ctx.easyPace, notes: "Easy cool-down"))

            let totalMpMiles = Double(reps) * repMiles
            return WorkoutFactory.create(
                name: "MP Repeats Long Run",
                category: .specific,
                phase: ctx.phase,
                description: String(format: "%dx%.1f mi @ race pace", reps, repMiles),
                steps: steps,
                signatureType: .racePaceRepeats
            )
        }
    )

    // MARK: - Race Simulation Long Run

    /// Full race simulation at goal pace
    static let raceSimulationLongRun = WorkoutTemplate(
        id: "long_race_simulation",
        name: "Race Simulation",
        category: .specific,
        workoutType: .longRun,
        raceDistances: [.halfMarathon, .marathon],
        phases: [.specific],
        description: "Extended race pace run simulating race conditions",
        progressionType: .intensity,
        minTotalMiles: 18.0,
        maxTotalMiles: 22.0,
        intensityProgression: .backLoaded,
        builder: { ctx in
            let warmupMiles = 2.0
            let cooldownMiles = 1.0
            let simulationMiles: Double
            let simulationPace: PaceIntensity

            switch ctx.raceDistance {
            case .halfMarathon:
                simulationMiles = 10.0 + (ctx.progression * 3.0)  // 10-13 mi
                simulationPace = ctx.intensity(98)  // Slightly conservative
            case .marathon:
                simulationMiles = 14.0 + (ctx.progression * 4.0)  // 14-18 mi
                simulationPace = ctx.intensity(95)  // ~95% MP for safety
            default:
                simulationMiles = 14.0
                simulationPace = ctx.intensity(95)
            }

            let warmup = StepBuilder.active(
                miles: warmupMiles,
                intensity: ctx.longRunPace,
                notes: "Easy start"
            )
            let simulation = StepBuilder.active(
                miles: simulationMiles,
                intensity: simulationPace,
                notes: "Race simulation - stay focused"
            )
            let cooldown = StepBuilder.active(
                miles: cooldownMiles,
                intensity: ctx.easyPace,
                notes: "Easy cool-down"
            )

            return WorkoutFactory.create(
                name: "Race Simulation",
                category: .specific,
                phase: ctx.phase,
                description: String(format: "%.0f mi @ 95-98%% race pace", simulationMiles),
                steps: [warmup, simulation, cooldown]
            )
        }
    )

    // MARK: - Fast Finish Long Run

    /// Long run with fast (HM pace) final miles
    static let fastFinishLongRun = WorkoutTemplate(
        id: "long_fast_finish",
        name: "Fast Finish Long Run",
        category: .specific,
        workoutType: .longRun,
        raceDistances: [.tenK, .halfMarathon, .marathon],
        phases: [.specific],
        description: "Long run finishing faster than race pace",
        progressionType: .hybrid,
        minTotalMiles: 12.0,
        maxTotalMiles: 20.0,
        intensityProgression: .gradual,
        builder: { ctx in
            let totalMiles: Double
            let fastMiles: Double
            let fastPace: PaceIntensity

            switch ctx.raceDistance {
            case .tenK:
                totalMiles = 12.0 + (ctx.progression * 3.0)  // 12-15 mi
                fastMiles = 2.0 + (ctx.progression * 1.0)  // 2-3 mi @ 10K pace
                fastPace = ctx.racePace
            case .halfMarathon:
                totalMiles = 14.0 + (ctx.progression * 4.0)  // 14-18 mi
                fastMiles = 3.0 + (ctx.progression * 2.0)  // 3-5 mi @ HM pace
                fastPace = ctx.racePace
            case .marathon:
                totalMiles = 16.0 + (ctx.progression * 4.0)  // 16-20 mi
                fastMiles = 4.0 + (ctx.progression * 2.0)  // 4-6 mi @ HM pace
                fastPace = ctx.intensity(105)  // HM pace
            default:
                totalMiles = 14.0
                fastMiles = 4.0
                fastPace = ctx.thresholdPace
            }

            let easyMiles = totalMiles - fastMiles

            let easy = StepBuilder.active(
                miles: easyMiles,
                intensity: ctx.longRunPace,
                notes: "Relaxed, aerobic effort"
            )
            let fast = StepBuilder.active(
                miles: fastMiles,
                intensity: fastPace,
                notes: "Fast finish - strong!"
            )

            return WorkoutFactory.create(
                name: "Fast Finish Long Run",
                category: .specific,
                phase: ctx.phase,
                description: String(format: "%.0f mi easy + %.0f mi fast", easyMiles, fastMiles),
                steps: [easy, fast]
            )
        }
    )

    // MARK: - Cutback Long Run

    /// Shorter long run for recovery weeks
    static let cutbackLongRun = WorkoutTemplate(
        id: "long_cutback",
        name: "Cutback Long Run",
        category: .fundamental,
        workoutType: .longRun,
        raceDistances: RaceDistance.allCases,
        phases: [.base, .support, .specific, .taper],
        description: "Reduced volume long run for recovery",
        progressionType: .static_,
        minTotalMiles: 8.0,
        maxTotalMiles: 14.0,
        intensityProgression: .none,
        builder: { ctx in
            let distance: Double
            switch ctx.raceDistance {
            case .mile1500, .fiveK:
                distance = 8.0
            case .tenK:
                distance = 10.0
            case .halfMarathon:
                distance = 12.0
            case .marathon:
                distance = 14.0
            }

            let run = StepBuilder.active(
                miles: distance,
                intensity: ctx.easyPace,
                notes: "Recovery week - keep it easy"
            )

            return WorkoutFactory.create(
                name: "Cutback Long Run",
                category: .fundamental,
                phase: ctx.phase,
                description: String(format: "%.0f mi easy (recovery week)", distance),
                steps: [run]
            )
        }
    )

    // MARK: - Taper Long Run

    /// Shorter long run for taper phase
    static let taperLongRun = WorkoutTemplate(
        id: "long_taper",
        name: "Taper Long Run",
        category: .fundamental,
        workoutType: .longRun,
        raceDistances: RaceDistance.allCases,
        phases: [.taper],
        description: "Reduced long run maintaining fitness during taper",
        progressionType: .static_,
        minTotalMiles: 6.0,
        maxTotalMiles: 12.0,
        intensityProgression: .none,
        builder: { ctx in
            // Taper long run is shorter with some race pace
            let distance: Double
            let racePaceMiles: Double

            switch ctx.raceDistance {
            case .mile1500, .fiveK:
                distance = 6.0
                racePaceMiles = 1.0
            case .tenK:
                distance = 8.0
                racePaceMiles = 2.0
            case .halfMarathon:
                distance = 10.0
                racePaceMiles = 2.0
            case .marathon:
                distance = 12.0
                racePaceMiles = 3.0
            }

            let easyMiles = distance - racePaceMiles

            let easy = StepBuilder.active(
                miles: easyMiles - 1,
                intensity: ctx.longRunPace,
                notes: "Easy and relaxed"
            )
            let racePaceSection = StepBuilder.active(
                miles: racePaceMiles,
                intensity: ctx.racePace,
                notes: "Race pace check-in"
            )
            let cooldown = StepBuilder.active(
                miles: 1.0,
                intensity: ctx.easyPace,
                notes: "Easy finish"
            )

            return WorkoutFactory.create(
                name: "Taper Long Run",
                category: .fundamental,
                phase: ctx.phase,
                description: String(format: "%.0f mi with %.0f mi @ race pace", distance, racePaceMiles),
                steps: [easy, racePaceSection, cooldown]
            )
        }
    )

    // MARK: - All Long Run Templates

    static var all: [WorkoutTemplate] {
        [
            easyLongRun,
            steadyLongRun,
            progressionLongRun,
            mpFinishLongRun,
            mpSandwichLongRun,
            mpRepeatsLongRun,
            raceSimulationLongRun,
            fastFinishLongRun,
            cutbackLongRun,
            taperLongRun
        ]
    }
}

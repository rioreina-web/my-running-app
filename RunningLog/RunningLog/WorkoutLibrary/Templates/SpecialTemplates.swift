//
//  SpecialTemplates.swift
//  RunningLog
//
//  Fartlek and special workout templates for all race distances.
//

import Foundation

// MARK: - Special/Fartlek Templates

/// Collection of fartlek and special workout templates
struct SpecialTemplates {

    // MARK: - Short Fartlek

    /// Short on/off fartlek (30-60 seconds)
    static let shortFartlek = WorkoutTemplate(
        id: "special_fartlek_short",
        name: "Short Fartlek",
        category: .special,
        workoutType: .tempo,
        raceDistances: RaceDistance.allCases,
        phases: [.base, .support, .specific],
        description: "Short surges with equal recovery",
        progressionType: .volume,
        minTotalMiles: 6.0,
        maxTotalMiles: 10.0,
        intensityProgression: .gradual,
        builder: { ctx in
            let warmupMiles = 1.5
            let cooldownMiles = 1.5

            // Number of surges increases with progression
            let surgeCount: Int
            let surgeDuration: Double  // seconds
            let surgePace: PaceIntensity

            switch ctx.raceDistance {
            case .mile1500:
                surgeCount = 10 + Int(ctx.progression * 6)  // 10-16 surges
                surgeDuration = 30
                surgePace = ctx.intensity(105)  // Race pace
            case .fiveK:
                surgeCount = 10 + Int(ctx.progression * 6)  // 10-16 surges
                surgeDuration = 45
                surgePace = ctx.racePace
            case .tenK:
                surgeCount = 8 + Int(ctx.progression * 6)  // 8-14 surges
                surgeDuration = 60
                surgePace = ctx.racePace
            case .halfMarathon, .marathon:
                surgeCount = 8 + Int(ctx.progression * 6)  // 8-14 surges
                surgeDuration = 60
                surgePace = ctx.intensity(105)  // HM pace
            }

            var steps: [CanovaWorkoutStep] = [
                StepBuilder.warmup(miles: warmupMiles)
            ]

            for i in 0..<surgeCount {
                steps.append(StepBuilder.activeTime(
                    seconds: surgeDuration,
                    intensity: surgePace,
                    notes: "Surge \(i + 1)"
                ))
                if i < surgeCount - 1 {
                    // Equal recovery
                    steps.append(StepBuilder.recoveryTime(seconds: surgeDuration, intensity: 70))
                }
            }

            steps.append(StepBuilder.cooldown(miles: cooldownMiles))

            return WorkoutFactory.create(
                name: "Short Fartlek",
                category: .special,
                phase: ctx.phase,
                description: String(format: "%dx%d\" on/%d\" off", surgeCount, Int(surgeDuration), Int(surgeDuration)),
                steps: steps
            )
        }
    )

    // MARK: - Medium Fartlek

    /// Medium duration fartlek (2-3 minutes)
    static let mediumFartlek = WorkoutTemplate(
        id: "special_fartlek_medium",
        name: "Medium Fartlek",
        category: .special,
        workoutType: .tempo,
        raceDistances: RaceDistance.allCases,
        phases: [.base, .support, .specific],
        description: "Medium-length surges at tempo effort",
        progressionType: .volume,
        minTotalMiles: 7.0,
        maxTotalMiles: 12.0,
        intensityProgression: .gradual,
        builder: { ctx in
            let warmupMiles = 2.0
            let cooldownMiles = 1.5

            let surgeCount: Int
            let surgeDuration: Double  // seconds (2-3 min)
            let recoveryDuration: Double
            let surgePace: PaceIntensity

            switch ctx.raceDistance {
            case .mile1500:
                surgeCount = 6 + Int(ctx.progression * 4)  // 6-10 surges
                surgeDuration = 120
                recoveryDuration = 60
                surgePace = ctx.intensity(105)
            case .fiveK:
                surgeCount = 6 + Int(ctx.progression * 4)  // 6-10 surges
                surgeDuration = 150
                recoveryDuration = 90
                surgePace = ctx.racePace
            case .tenK:
                surgeCount = 5 + Int(ctx.progression * 4)  // 5-9 surges
                surgeDuration = 180
                recoveryDuration = 90
                surgePace = ctx.racePace
            case .halfMarathon, .marathon:
                surgeCount = 5 + Int(ctx.progression * 4)  // 5-9 surges
                surgeDuration = 180
                recoveryDuration = 90
                surgePace = ctx.thresholdPace
            }

            var steps: [CanovaWorkoutStep] = [
                StepBuilder.warmup(miles: warmupMiles)
            ]

            for i in 0..<surgeCount {
                steps.append(StepBuilder.activeTime(
                    seconds: surgeDuration,
                    intensity: surgePace,
                    notes: "Surge \(i + 1) of \(surgeCount)"
                ))
                if i < surgeCount - 1 {
                    steps.append(StepBuilder.recoveryTime(seconds: recoveryDuration, intensity: 72))
                }
            }

            steps.append(StepBuilder.cooldown(miles: cooldownMiles))

            let surgeMin = Int(surgeDuration / 60)
            return WorkoutFactory.create(
                name: "Medium Fartlek",
                category: .special,
                phase: ctx.phase,
                description: String(format: "%dx%d' at tempo effort", surgeCount, surgeMin),
                steps: steps
            )
        }
    )

    // MARK: - Long Fartlek

    /// Long duration fartlek (5+ minutes)
    static let longFartlek = WorkoutTemplate(
        id: "special_fartlek_long",
        name: "Long Fartlek",
        category: .special,
        workoutType: .tempo,
        raceDistances: [.tenK, .halfMarathon, .marathon],
        phases: [.specific],
        description: "Extended tempo segments with float recovery",
        progressionType: .hybrid,
        minTotalMiles: 9.0,
        maxTotalMiles: 14.0,
        intensityProgression: .gradual,
        builder: { ctx in
            let warmupMiles = 2.0
            let cooldownMiles = 1.5

            let surgeCount: Int
            let surgeDuration: Double  // seconds (5-8 min)
            let recoveryDuration: Double
            let surgePace: PaceIntensity

            switch ctx.raceDistance {
            case .tenK:
                surgeCount = 4 + Int(ctx.progression * 2)  // 4-6 surges
                surgeDuration = 300  // 5 min
                recoveryDuration = 150
                surgePace = ctx.racePace
            case .halfMarathon:
                surgeCount = 4 + Int(ctx.progression * 2)  // 4-6 surges
                surgeDuration = 360  // 6 min
                recoveryDuration = 180
                surgePace = ctx.racePace
            case .marathon:
                surgeCount = 4 + Int(ctx.progression * 2)  // 4-6 surges
                surgeDuration = 480  // 8 min
                recoveryDuration = 240
                surgePace = ctx.racePace
            default:
                surgeCount = 4
                surgeDuration = 300
                recoveryDuration = 150
                surgePace = ctx.tempoPace
            }

            var steps: [CanovaWorkoutStep] = [
                StepBuilder.warmup(miles: warmupMiles)
            ]

            for i in 0..<surgeCount {
                steps.append(StepBuilder.activeTime(
                    seconds: surgeDuration,
                    intensity: surgePace,
                    notes: "Tempo segment \(i + 1)"
                ))
                if i < surgeCount - 1 {
                    steps.append(StepBuilder.recoveryTime(seconds: recoveryDuration, intensity: 75))
                }
            }

            steps.append(StepBuilder.cooldown(miles: cooldownMiles))

            let surgeMin = Int(surgeDuration / 60)
            return WorkoutFactory.create(
                name: "Long Fartlek",
                category: .special,
                phase: ctx.phase,
                description: String(format: "%dx%d' at race pace effort", surgeCount, surgeMin),
                steps: steps
            )
        }
    )

    // MARK: - Kenyan Fartlek

    /// Unstructured feel-based fartlek
    static let kenyanFartlek = WorkoutTemplate(
        id: "special_fartlek_kenyan",
        name: "Kenyan Fartlek",
        category: .special,
        workoutType: .tempo,
        raceDistances: RaceDistance.allCases,
        phases: [.base, .support, .specific],
        description: "Unstructured surges based on feel",
        progressionType: .volume,
        minTotalMiles: 6.0,
        maxTotalMiles: 10.0,
        intensityProgression: .none,
        builder: { ctx in
            let totalMiles: Double
            switch ctx.raceDistance {
            case .mile1500, .fiveK:
                totalMiles = 6.0 + (ctx.progression * 2.0)  // 6-8 mi
            case .tenK:
                totalMiles = 7.0 + (ctx.progression * 2.0)  // 7-9 mi
            case .halfMarathon, .marathon:
                totalMiles = 8.0 + (ctx.progression * 2.0)  // 8-10 mi
            }

            let warmupMiles = 1.5
            let cooldownMiles = 1.0
            let fartlekMiles = totalMiles - warmupMiles - cooldownMiles

            let warmup = StepBuilder.warmup(miles: warmupMiles)
            let fartlek = StepBuilder.active(
                miles: fartlekMiles,
                intensity: ctx.intensity(82),  // Average effort
                notes: "Surges by feel - vary effort naturally"
            )
            let cooldown = StepBuilder.cooldown(miles: cooldownMiles)

            return WorkoutFactory.create(
                name: "Kenyan Fartlek",
                category: .special,
                phase: ctx.phase,
                description: String(format: "%.0f mi with surges by feel", fartlekMiles),
                steps: [warmup, fartlek, cooldown]
            )
        }
    )

    // MARK: - Special Block AM

    /// Morning session of a special block double day
    static let specialBlockAM = WorkoutTemplate(
        id: "special_block_am",
        name: "Special Block AM",
        category: .specific,
        workoutType: .intervals,
        raceDistances: [.halfMarathon, .marathon],
        phases: [.specific],
        description: "Morning workout of a special block day",
        progressionType: .volume,
        minTotalMiles: 8.0,
        maxTotalMiles: 12.0,
        intensityProgression: .gradual,
        builder: { ctx in
            // AM session: Shorter, more intense intervals
            let warmupMiles = 2.0
            let cooldownMiles = 1.5

            let repCount: Int
            let repDistance: Double
            let repPace: PaceIntensity

            switch ctx.raceDistance {
            case .halfMarathon:
                repCount = 4 + Int(ctx.progression * 2)  // 4-6 reps
                repDistance = 1.0  // Mile reps
                repPace = ctx.racePace
            case .marathon:
                repCount = 4 + Int(ctx.progression * 3)  // 4-7 reps
                repDistance = 1.0  // Mile reps
                repPace = ctx.intensity(105)  // HM pace
            default:
                repCount = 5
                repDistance = 1.0
                repPace = ctx.thresholdPace
            }

            var steps: [CanovaWorkoutStep] = [
                StepBuilder.warmup(miles: warmupMiles)
            ]

            for i in 0..<repCount {
                steps.append(StepBuilder.active(
                    miles: repDistance,
                    intensity: repPace,
                    notes: "AM rep \(i + 1) of \(repCount)"
                ))
                if i < repCount - 1 {
                    steps.append(StepBuilder.recovery(miles: 0.25, intensity: 70))
                }
            }

            steps.append(StepBuilder.cooldown(miles: cooldownMiles))

            return WorkoutFactory.create(
                name: "Special Block AM",
                category: .specific,
                phase: ctx.phase,
                description: String(format: "AM: %dx1mi @ %d%%", repCount, Int(repPace.percentage)),
                steps: steps,
                signatureType: .specialBlock
            )
        }
    )

    // MARK: - Special Block PM

    /// Afternoon/evening session of a special block double day
    static let specialBlockPM = WorkoutTemplate(
        id: "special_block_pm",
        name: "Special Block PM",
        category: .specific,
        workoutType: .tempo,
        raceDistances: [.halfMarathon, .marathon],
        phases: [.specific],
        description: "Afternoon workout of a special block day",
        progressionType: .volume,
        minTotalMiles: 8.0,
        maxTotalMiles: 14.0,
        intensityProgression: .gradual,
        builder: { ctx in
            // PM session: Longer, steadier effort (tempo or long intervals)
            let warmupMiles = 2.0
            let cooldownMiles = 1.5

            let tempoMiles: Double
            let tempoPace: PaceIntensity

            switch ctx.raceDistance {
            case .halfMarathon:
                tempoMiles = 4.0 + (ctx.progression * 3.0)  // 4-7 mi
                tempoPace = ctx.intensity(95)  // Slightly slower than race pace
            case .marathon:
                tempoMiles = 5.0 + (ctx.progression * 4.0)  // 5-9 mi
                tempoPace = ctx.intensity(95)  // ~MP
            default:
                tempoMiles = 5.0
                tempoPace = ctx.tempoPace
            }

            let warmup = StepBuilder.warmup(miles: warmupMiles)
            let tempo = StepBuilder.active(
                miles: tempoMiles,
                intensity: tempoPace,
                notes: "PM tempo - steady and controlled"
            )
            let cooldown = StepBuilder.cooldown(miles: cooldownMiles)

            return WorkoutFactory.create(
                name: "Special Block PM",
                category: .specific,
                phase: ctx.phase,
                description: String(format: "PM: %.0f mi @ %d%%", tempoMiles, Int(tempoPace.percentage)),
                steps: [warmup, tempo, cooldown],
                signatureType: .specialBlock
            )
        }
    )

    // MARK: - Alternations Workout

    /// Canova-style alternations between two paces
    static let alternationsWorkout = WorkoutTemplate(
        id: "special_alternations",
        name: "Alternations",
        category: .specific,
        workoutType: .tempo,
        raceDistances: [.halfMarathon, .marathon],
        phases: [.specific],
        description: "Alternating between race pace and slightly faster",
        progressionType: .volume,
        minTotalMiles: 8.0,
        maxTotalMiles: 14.0,
        intensityProgression: .backLoaded,
        builder: { ctx in
            let warmupMiles = 2.0
            let cooldownMiles = 1.5

            let totalWorkMiles: Double
            let segmentMiles = 0.5

            // Two paces: race pace and slightly faster (102-103%)
            let racePace = ctx.racePace
            let fastPace = ctx.intensity(racePace.percentage + 3)

            switch ctx.raceDistance {
            case .halfMarathon:
                totalWorkMiles = 4.0 + (ctx.progression * 4.0)  // 4-8 mi
            case .marathon:
                totalWorkMiles = 5.0 + (ctx.progression * 5.0)  // 5-10 mi
            default:
                totalWorkMiles = 6.0
            }

            let segments = Int(totalWorkMiles / segmentMiles)

            var steps: [CanovaWorkoutStep] = [
                StepBuilder.warmup(miles: warmupMiles)
            ]

            for i in 0..<segments {
                let isRacePace = i % 2 == 0
                steps.append(StepBuilder.active(
                    miles: segmentMiles,
                    intensity: isRacePace ? racePace : fastPace,
                    notes: isRacePace ? "Race pace" : "Surge"
                ))
            }

            steps.append(StepBuilder.cooldown(miles: cooldownMiles))

            return WorkoutFactory.create(
                name: "Alternations",
                category: .specific,
                phase: ctx.phase,
                description: String(format: "%dx0.5mi alternating race pace/surge", segments),
                steps: steps
            )
        }
    )

    // MARK: - Threshold Cruise Intervals

    /// Longer cruise intervals at threshold
    static let thresholdCruise = WorkoutTemplate(
        id: "special_threshold_cruise",
        name: "Threshold Cruise",
        category: .special,
        workoutType: .tempo,
        raceDistances: [.fiveK, .tenK, .halfMarathon, .marathon],
        phases: [.base, .support, .specific],
        description: "Extended cruise intervals at threshold pace",
        progressionType: .volume,
        minTotalMiles: 8.0,
        maxTotalMiles: 14.0,
        intensityProgression: .gradual,
        builder: { ctx in
            let warmupMiles = 2.0
            let cooldownMiles = 1.5

            let repCount: Int
            let repMiles: Double

            switch ctx.raceDistance {
            case .fiveK:
                repCount = 3 + Int(ctx.progression * 2)  // 3-5 reps
                repMiles = 1.0  // Mile reps
            case .tenK:
                repCount = 3 + Int(ctx.progression * 2)  // 3-5 reps
                repMiles = 1.25  // 2K reps
            case .halfMarathon:
                repCount = 3 + Int(ctx.progression * 2)  // 3-5 reps
                repMiles = 1.5
            case .marathon:
                repCount = 4 + Int(ctx.progression * 2)  // 4-6 reps
                repMiles = 2.0
            default:
                repCount = 4
                repMiles = 1.5
            }

            var steps: [CanovaWorkoutStep] = [
                StepBuilder.warmup(miles: warmupMiles)
            ]

            for i in 0..<repCount {
                steps.append(StepBuilder.active(
                    miles: repMiles,
                    intensity: ctx.thresholdPace,
                    notes: "Cruise \(i + 1) of \(repCount)"
                ))
                if i < repCount - 1 {
                    // 90 seconds jog recovery
                    steps.append(StepBuilder.recoveryTime(seconds: 90, intensity: 70))
                }
            }

            steps.append(StepBuilder.cooldown(miles: cooldownMiles))

            return WorkoutFactory.create(
                name: "Threshold Cruise",
                category: .special,
                phase: ctx.phase,
                description: String(format: "%dx%.1f mi @ threshold", repCount, repMiles),
                steps: steps
            )
        }
    )

    // MARK: - All Special Templates

    static var all: [WorkoutTemplate] {
        [
            shortFartlek,
            mediumFartlek,
            longFartlek,
            kenyanFartlek,
            specialBlockAM,
            specialBlockPM,
            alternationsWorkout,
            thresholdCruise
        ]
    }
}

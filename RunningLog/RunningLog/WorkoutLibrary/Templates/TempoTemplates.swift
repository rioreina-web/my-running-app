//
//  TempoTemplates.swift
//  RunningLog
//
//  Tempo workout templates for all race distances.
//

import Foundation

// MARK: - Tempo Templates

/// Collection of tempo workout templates
struct TempoTemplates {

    // MARK: - Continuous Tempo

    /// Classic continuous tempo run at threshold pace
    static let continuousTempo = WorkoutTemplate(
        id: "tempo_continuous",
        name: "Continuous Tempo",
        category: .special,
        workoutType: .tempo,
        raceDistances: RaceDistance.allCases,
        phases: [.base, .specific],
        description: "Sustained run at lactate threshold pace",
        progressionType: .volume,
        minTotalMiles: 6.0,
        maxTotalMiles: 12.0,
        intensityProgression: .gradual,
        builder: { ctx in
            // Scale tempo distance based on event and progression
            let tempoMiles: Double
            switch ctx.raceDistance {
            case .mile1500, .fiveK:
                tempoMiles = 2.0 + (ctx.progression * 3.0)  // 2-5 miles
            case .tenK:
                tempoMiles = 3.0 + (ctx.progression * 4.0)  // 3-7 miles
            case .halfMarathon:
                tempoMiles = 4.0 + (ctx.progression * 5.0)  // 4-9 miles
            case .marathon:
                tempoMiles = 5.0 + (ctx.progression * 7.0)  // 5-12 miles
            }

            let warmup = StepBuilder.warmup(miles: 2.0)
            let tempo = StepBuilder.active(
                miles: tempoMiles,
                intensity: ctx.thresholdPace,
                notes: "Comfortably hard, controlled breathing"
            )
            let cooldown = StepBuilder.cooldown(miles: 1.5)

            return WorkoutFactory.create(
                name: "Continuous Tempo",
                category: .special,
                phase: ctx.phase,
                description: String(format: "%.1f miles at threshold pace", tempoMiles),
                steps: [warmup, tempo, cooldown]
            )
        }
    )

    // MARK: - Alternating Tempo (Canova Style)

    /// Marathon-specific alternating tempo with MP and float segments
    static let alternatingTempo = WorkoutTemplate(
        id: "tempo_alternating",
        name: "Alternating Tempo",
        category: .specific,
        workoutType: .tempo,
        raceDistances: [.halfMarathon, .marathon],
        phases: [.specific],
        description: "Alternating segments at race pace and slightly slower",
        progressionType: .hybrid,
        minTotalMiles: 8.0,
        maxTotalMiles: 16.0,
        intensityProgression: .backLoaded,
        builder: { ctx in
            // Marathon: MP (100%) / Float (92%)
            // Half Marathon: HMP (100%) / Float (90%)
            let onPace = ctx.racePace
            let floatPace = ctx.raceDistance == .marathon ?
                ctx.intensity(92) : ctx.intensity(90)

            // Number of alternations increases with progression
            let repCount = Int(6 + ctx.progression * 6)  // 6-12 reps
            let repDistance = 0.5  // Half-mile segments

            var steps: [CanovaWorkoutStep] = [StepBuilder.warmup(miles: 2.0)]

            for i in 0..<repCount {
                let isOn = i % 2 == 0
                steps.append(StepBuilder.active(
                    miles: repDistance,
                    intensity: isOn ? onPace : floatPace,
                    notes: isOn ? "Race pace" : "Float"
                ))
            }

            steps.append(StepBuilder.cooldown(miles: 1.5))

            let totalTempo = Double(repCount) * repDistance
            return WorkoutFactory.create(
                name: "Alternating Tempo",
                category: .specific,
                phase: ctx.phase,
                description: String(format: "%dx0.5mi alternations (%d mi total)", repCount, Int(totalTempo)),
                steps: steps,
                signatureType: .progressiveTempo
            )
        }
    )

    // MARK: - Progressive Tempo

    /// Tempo run with increasing pace through segments
    static let progressiveTempo = WorkoutTemplate(
        id: "tempo_progressive",
        name: "Progressive Tempo",
        category: .special,
        workoutType: .tempo,
        raceDistances: RaceDistance.allCases,
        phases: [.base, .specific],
        description: "Three segments with progressively faster pace",
        progressionType: .intensity,
        minTotalMiles: 7.0,
        maxTotalMiles: 13.0,
        intensityProgression: .gradual,
        builder: { ctx in
            let segmentMiles: Double
            switch ctx.raceDistance {
            case .mile1500, .fiveK:
                segmentMiles = 1.0 + (ctx.progression * 0.5)  // 1-1.5 mi each
            case .tenK:
                segmentMiles = 1.5 + (ctx.progression * 1.0)  // 1.5-2.5 mi each
            case .halfMarathon:
                segmentMiles = 2.0 + (ctx.progression * 1.0)  // 2-3 mi each
            case .marathon:
                segmentMiles = 2.5 + (ctx.progression * 1.5)  // 2.5-4 mi each
            }

            // Three segments: 85%, 90%, 95% of threshold
            let intensities: [Double] = [
                ctx.raceDistance.thresholdPaceIntensity * 0.92,
                ctx.raceDistance.thresholdPaceIntensity * 0.97,
                ctx.raceDistance.thresholdPaceIntensity * 1.02
            ]

            var steps: [CanovaWorkoutStep] = [StepBuilder.warmup(miles: 2.0)]

            for (i, intensity) in intensities.enumerated() {
                steps.append(StepBuilder.active(
                    miles: segmentMiles,
                    intensity: ctx.intensity(intensity),
                    notes: "Segment \(i + 1) of 3"
                ))
            }

            steps.append(StepBuilder.cooldown(miles: 1.5))

            return WorkoutFactory.create(
                name: "Progressive Tempo",
                category: .special,
                phase: ctx.phase,
                description: String(format: "3x%.1f mi building from moderate to race effort", segmentMiles),
                steps: steps,
                signatureType: .progressiveTempo
            )
        }
    )

    // MARK: - Cruise Intervals

    /// Threshold intervals with short recovery
    static let cruiseIntervals = WorkoutTemplate(
        id: "tempo_cruise_intervals",
        name: "Cruise Intervals",
        category: .special,
        workoutType: .tempo,
        raceDistances: RaceDistance.allCases,
        phases: [.base, .specific],
        description: "Threshold-pace repeats with short jog recovery",
        progressionType: .volume,
        minTotalMiles: 7.0,
        maxTotalMiles: 12.0,
        intensityProgression: .none,
        builder: { ctx in
            let repDistance: Double
            let repCount: Int

            switch ctx.raceDistance {
            case .mile1500, .fiveK:
                repDistance = 0.75  // 1200m
                repCount = 3 + Int(ctx.progression * 3)  // 3-6 reps
            case .tenK:
                repDistance = 1.0  // Mile
                repCount = 3 + Int(ctx.progression * 3)  // 3-6 reps
            case .halfMarathon, .marathon:
                repDistance = 1.25  // 2K
                repCount = 3 + Int(ctx.progression * 3)  // 3-6 reps
            }

            var steps: [CanovaWorkoutStep] = [StepBuilder.warmup(miles: 2.0)]

            for i in 0..<repCount {
                steps.append(StepBuilder.active(
                    miles: repDistance,
                    intensity: ctx.thresholdPace,
                    notes: "Rep \(i + 1) of \(repCount)"
                ))
                if i < repCount - 1 {
                    // 1 min jog recovery between reps
                    steps.append(StepBuilder.recoveryTime(seconds: 60))
                }
            }

            steps.append(StepBuilder.cooldown(miles: 1.5))

            return WorkoutFactory.create(
                name: "Cruise Intervals",
                category: .special,
                phase: ctx.phase,
                description: String(format: "%dx%.2f mi @ threshold w/ 1' recovery", repCount, repDistance),
                steps: steps
            )
        }
    )

    // MARK: - Threshold Run

    /// Straight threshold effort (slightly faster than tempo)
    static let thresholdRun = WorkoutTemplate(
        id: "tempo_threshold",
        name: "Threshold Run",
        category: .special,
        workoutType: .tempo,
        raceDistances: RaceDistance.allCases,
        phases: [.specific],
        description: "Sustained effort at lactate threshold",
        progressionType: .volume,
        minTotalMiles: 6.0,
        maxTotalMiles: 11.0,
        intensityProgression: .gradual,
        builder: { ctx in
            let thresholdMiles: Double
            switch ctx.raceDistance {
            case .mile1500:
                thresholdMiles = 1.5 + (ctx.progression * 1.5)  // 1.5-3 miles
            case .fiveK:
                thresholdMiles = 2.0 + (ctx.progression * 2.0)  // 2-4 miles
            case .tenK:
                thresholdMiles = 3.0 + (ctx.progression * 3.0)  // 3-6 miles
            case .halfMarathon:
                thresholdMiles = 4.0 + (ctx.progression * 3.0)  // 4-7 miles
            case .marathon:
                thresholdMiles = 4.0 + (ctx.progression * 4.0)  // 4-8 miles
            }

            let warmup = StepBuilder.warmup(miles: 2.0)
            let threshold = StepBuilder.active(
                miles: thresholdMiles,
                intensity: ctx.thresholdPace,
                notes: "Hard but controlled, at the edge"
            )
            let cooldown = StepBuilder.cooldown(miles: 1.5)

            return WorkoutFactory.create(
                name: "Threshold Run",
                category: .special,
                phase: ctx.phase,
                description: String(format: "%.1f miles at threshold", thresholdMiles),
                steps: [warmup, threshold, cooldown]
            )
        }
    )

    // MARK: - Broken Tempo

    /// Tempo with short float breaks
    static let brokenTempo = WorkoutTemplate(
        id: "tempo_broken",
        name: "Broken Tempo",
        category: .special,
        workoutType: .tempo,
        raceDistances: [.tenK, .halfMarathon, .marathon],
        phases: [.base, .specific],
        description: "Tempo segments with brief float recoveries",
        progressionType: .hybrid,
        minTotalMiles: 8.0,
        maxTotalMiles: 14.0,
        intensityProgression: .none,
        builder: { ctx in
            let segmentMiles: Double
            let segments: Int

            switch ctx.raceDistance {
            case .tenK:
                segmentMiles = 1.5 + (ctx.progression * 0.5)  // 1.5-2 mi
                segments = 3 + Int(ctx.progression * 1)  // 3-4 segments
            case .halfMarathon:
                segmentMiles = 2.0 + (ctx.progression * 0.5)  // 2-2.5 mi
                segments = 3 + Int(ctx.progression * 2)  // 3-5 segments
            case .marathon:
                segmentMiles = 2.5 + (ctx.progression * 0.5)  // 2.5-3 mi
                segments = 3 + Int(ctx.progression * 2)  // 3-5 segments
            default:
                segmentMiles = 2.0
                segments = 3
            }

            var steps: [CanovaWorkoutStep] = [StepBuilder.warmup(miles: 2.0)]

            for i in 0..<segments {
                steps.append(StepBuilder.active(
                    miles: segmentMiles,
                    intensity: ctx.tempoPace,
                    notes: "Tempo segment \(i + 1)"
                ))
                if i < segments - 1 {
                    // 0.25 mi float recovery
                    steps.append(StepBuilder.recovery(miles: 0.25, intensity: 75))
                }
            }

            steps.append(StepBuilder.cooldown(miles: 1.5))

            let totalTempo = Double(segments) * segmentMiles
            return WorkoutFactory.create(
                name: "Broken Tempo",
                category: .special,
                phase: ctx.phase,
                description: String(format: "%dx%.1f mi tempo w/ 0.25mi floats", segments, segmentMiles),
                steps: steps
            )
        }
    )

    // MARK: - Taper Tempo

    /// Shorter, sharper tempo for taper phase
    static let taperTempo = WorkoutTemplate(
        id: "tempo_taper",
        name: "Taper Tempo",
        category: .special,
        workoutType: .tempo,
        raceDistances: RaceDistance.allCases,
        phases: [.taper],
        description: "Short tempo to maintain sharpness during taper",
        progressionType: .static_,
        minTotalMiles: 5.0,
        maxTotalMiles: 7.0,
        intensityProgression: .none,
        builder: { ctx in
            let tempoMiles: Double
            switch ctx.raceDistance {
            case .mile1500, .fiveK:
                tempoMiles = 1.5
            case .tenK:
                tempoMiles = 2.0
            case .halfMarathon:
                tempoMiles = 2.5
            case .marathon:
                tempoMiles = 3.0
            }

            // Slightly faster than normal tempo for sharpness
            let taperedIntensity = ctx.thresholdPace.percentage + 2

            let warmup = StepBuilder.warmup(miles: 2.0)
            let tempo = StepBuilder.active(
                miles: tempoMiles,
                intensity: ctx.intensity(taperedIntensity),
                notes: "Crisp and controlled"
            )
            let cooldown = StepBuilder.cooldown(miles: 1.0)

            return WorkoutFactory.create(
                name: "Taper Tempo",
                category: .special,
                phase: ctx.phase,
                description: String(format: "%.1f mi at tempo+ pace", tempoMiles),
                steps: [warmup, tempo, cooldown]
            )
        }
    )

    // MARK: - Tempo with Strides

    /// Tempo run followed by fast strides
    static let tempoWithStrides = WorkoutTemplate(
        id: "tempo_with_strides",
        name: "Tempo + Strides",
        category: .special,
        workoutType: .tempo,
        raceDistances: RaceDistance.allCases,
        phases: [.base, .specific, .taper],
        description: "Tempo run with fast finish strides",
        progressionType: .volume,
        minTotalMiles: 6.0,
        maxTotalMiles: 10.0,
        intensityProgression: .none,
        builder: { ctx in
            let tempoMiles: Double
            switch ctx.raceDistance {
            case .mile1500, .fiveK:
                tempoMiles = 2.0 + (ctx.progression * 1.5)
            case .tenK:
                tempoMiles = 2.5 + (ctx.progression * 2.0)
            case .halfMarathon, .marathon:
                tempoMiles = 3.0 + (ctx.progression * 2.5)
            }

            var steps: [CanovaWorkoutStep] = [
                StepBuilder.warmup(miles: 1.5),
                StepBuilder.active(
                    miles: tempoMiles,
                    intensity: ctx.tempoPace,
                    notes: "Steady tempo effort"
                ),
                StepBuilder.recovery(miles: 0.5, intensity: 70)
            ]

            // 4-6 strides
            let strideCount = 4 + Int(ctx.progression * 2)
            for i in 0..<strideCount {
                steps.append(StepBuilder.activeMeters(
                    100,
                    intensity: ctx.intensity(110),
                    notes: "Stride \(i + 1)"
                ))
                if i < strideCount - 1 {
                    steps.append(StepBuilder.recoveryMeters(100, intensity: 60))
                }
            }

            steps.append(StepBuilder.cooldown(miles: 1.0))

            return WorkoutFactory.create(
                name: "Tempo + Strides",
                category: .special,
                phase: ctx.phase,
                description: String(format: "%.1f mi tempo + %d strides", tempoMiles, strideCount),
                steps: steps
            )
        }
    )

    // MARK: - All Tempo Templates

    static var all: [WorkoutTemplate] {
        [
            continuousTempo,
            alternatingTempo,
            progressiveTempo,
            cruiseIntervals,
            thresholdRun,
            brokenTempo,
            taperTempo,
            tempoWithStrides
        ]
    }
}

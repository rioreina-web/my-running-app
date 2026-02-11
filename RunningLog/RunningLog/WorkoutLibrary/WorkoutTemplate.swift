//
//  WorkoutTemplate.swift
//  RunningLog
//
//  Core template model for the workout library system.
//

import Foundation
import SwiftUI

// MARK: - Workout Template

/// A workout template that can be scaled and adjusted based on progression
struct WorkoutTemplate: Identifiable {
    let id: String
    let name: String
    let category: CanovaWorkoutCategory
    let workoutType: ScheduledWorkoutType
    let raceDistances: [RaceDistance]
    let phases: [CanovaTrainingPhase]
    let description: String
    let progressionType: ProgressionType

    /// Volume bounds (scaled by progression level 0.0-1.0)
    let minTotalMiles: Double
    let maxTotalMiles: Double

    /// Intensity progression (some workouts get faster, others maintain)
    let intensityProgression: IntensityProgression

    /// The builder closure that creates the actual workout
    let builder: WorkoutBuilder

    /// Build a concrete workout from this template
    func buildWorkout(
        progression: Double,
        goalTimeSeconds: Int,
        weeklyMileage: Double,
        raceDistance: RaceDistance,
        phase: CanovaTrainingPhase
    ) -> CanovaWorkout {
        builder(
            WorkoutBuildContext(
                progression: progression,
                goalTimeSeconds: goalTimeSeconds,
                weeklyMileage: weeklyMileage,
                raceDistance: raceDistance,
                phase: phase,
                template: self
            )
        )
    }

    /// Check if template is valid for given context
    func isValid(for raceDistance: RaceDistance, phase: CanovaTrainingPhase) -> Bool {
        raceDistances.contains(raceDistance) && phases.contains(phase)
    }

    /// Calculate the total miles for a given progression level
    func totalMiles(at progression: Double) -> Double {
        minTotalMiles + (maxTotalMiles - minTotalMiles) * progression
    }
}

// MARK: - Workout Builder

/// Context passed to workout builders
struct WorkoutBuildContext {
    let progression: Double          // 0.0 (start of phase) to 1.0 (end of phase)
    let goalTimeSeconds: Int         // Goal race time in seconds
    let weeklyMileage: Double        // Current weekly mileage
    let raceDistance: RaceDistance   // Target race distance
    let phase: CanovaTrainingPhase   // Current training phase
    let template: WorkoutTemplate    // The template being built

    /// Race pace in seconds per mile
    var racePaceSeconds: Double {
        raceDistance.racePaceSecondsPerMile(goalTimeSeconds: goalTimeSeconds)
    }

    /// Calculate pace for a given intensity percentage
    func paceSeconds(at intensity: Double) -> Double {
        racePaceSeconds / (intensity / 100.0)
    }

    /// Get the total workout miles based on progression
    var targetMiles: Double {
        template.totalMiles(at: progression)
    }

    /// Create a pace intensity struct
    func intensity(_ percentage: Double) -> PaceIntensity {
        PaceIntensity(percentage: percentage)
    }

    /// Get event-appropriate easy pace
    var easyPace: PaceIntensity {
        intensity(raceDistance.easyPaceIntensity)
    }

    /// Get event-appropriate tempo pace
    var tempoPace: PaceIntensity {
        intensity(raceDistance.tempoPaceIntensity)
    }

    /// Get event-appropriate threshold pace
    var thresholdPace: PaceIntensity {
        intensity(raceDistance.thresholdPaceIntensity)
    }

    /// Get event-appropriate VO2max pace
    var vo2maxPace: PaceIntensity {
        intensity(raceDistance.vo2maxPaceIntensity)
    }

    /// Race pace intensity (100%)
    var racePace: PaceIntensity {
        intensity(100)
    }

    /// Get event-appropriate long run pace
    var longRunPace: PaceIntensity {
        intensity(raceDistance.longRunPaceIntensity)
    }
}

/// Type alias for workout builder closures
typealias WorkoutBuilder = (WorkoutBuildContext) -> CanovaWorkout

// MARK: - Progression Type

/// How the workout progresses over the phase
enum ProgressionType: String, Codable {
    case volume       // Primarily increases distance
    case intensity    // Primarily increases pace/effort
    case complexity   // Adds more challenging structure
    case hybrid       // Combination of volume and intensity
    case static_      // Stays relatively constant (recovery workouts)

    var displayName: String {
        switch self {
        case .volume: return "Volume Progression"
        case .intensity: return "Intensity Progression"
        case .complexity: return "Complexity Progression"
        case .hybrid: return "Hybrid Progression"
        case .static_: return "Static"
        }
    }
}

// MARK: - Intensity Progression

/// How intensity changes over the phase
enum IntensityProgression: String, Codable {
    case none           // Intensity stays constant
    case gradual        // Small increases throughout
    case backLoaded     // Intensity increases later in phase
    case frontLoaded    // Higher intensity early, maintain later
    case cyclic         // Alternates between harder/easier weeks

    /// Calculate intensity modifier based on progression (0-1)
    func modifier(at progression: Double) -> Double {
        switch self {
        case .none:
            return 1.0
        case .gradual:
            return 1.0 + (progression * 0.03)  // Up to 3% faster
        case .backLoaded:
            // Stays flat until 60%, then increases
            return progression > 0.6 ? 1.0 + ((progression - 0.6) / 0.4 * 0.04) : 1.0
        case .frontLoaded:
            // Starts 2% harder, gradually normalizes
            return 1.02 - (progression * 0.02)
        case .cyclic:
            // Alternate every 2 weeks (assuming ~0.125 progression per week in 8-week phase)
            let cyclePosition = (progression * 8).truncatingRemainder(dividingBy: 2)
            return cyclePosition < 1 ? 1.02 : 0.98
        }
    }
}

// MARK: - Template Type

/// Categories of workout templates for organization
enum WorkoutTemplateType: String, Codable, CaseIterable {
    case tempo
    case interval
    case longRun
    case easy
    case recovery
    case fartlek
    case speed
    case special

    var displayName: String {
        switch self {
        case .tempo: return "Tempo"
        case .interval: return "Intervals"
        case .longRun: return "Long Run"
        case .easy: return "Easy"
        case .recovery: return "Recovery"
        case .fartlek: return "Fartlek"
        case .speed: return "Speed"
        case .special: return "Special"
        }
    }

    var scheduledType: ScheduledWorkoutType {
        switch self {
        case .tempo: return .tempo
        case .interval: return .intervals
        case .longRun: return .longRun
        case .easy: return .easy
        case .recovery: return .recovery
        case .fartlek: return .tempo
        case .speed: return .intervals
        case .special: return .intervals
        }
    }
}

// MARK: - Step Builder Helpers

/// Helper functions for building workout steps
struct StepBuilder {
    /// Create a warmup step
    static func warmup(miles: Double, intensity: Double = 70) -> CanovaWorkoutStep {
        CanovaWorkoutStep(
            id: UUID(),
            stepType: .warmup,
            durationType: .distanceMiles,
            durationValue: miles,
            targetPaceIntensity: PaceIntensity(percentage: intensity),
            notes: "Easy warm-up",
            order: 0
        )
    }

    /// Create a cooldown step
    static func cooldown(miles: Double, intensity: Double = 65) -> CanovaWorkoutStep {
        CanovaWorkoutStep(
            id: UUID(),
            stepType: .cooldown,
            durationType: .distanceMiles,
            durationValue: miles,
            targetPaceIntensity: PaceIntensity(percentage: intensity),
            notes: "Easy cool-down",
            order: 0
        )
    }

    /// Create an active step with distance in miles
    static func active(miles: Double, intensity: PaceIntensity, notes: String? = nil) -> CanovaWorkoutStep {
        CanovaWorkoutStep(
            id: UUID(),
            stepType: .active,
            durationType: .distanceMiles,
            durationValue: miles,
            targetPaceIntensity: intensity,
            notes: notes,
            order: 0
        )
    }

    /// Create an active step with distance in meters
    static func activeMeters(_ meters: Double, intensity: PaceIntensity, notes: String? = nil) -> CanovaWorkoutStep {
        CanovaWorkoutStep(
            id: UUID(),
            stepType: .active,
            durationType: .distanceMeters,
            durationValue: meters,
            targetPaceIntensity: intensity,
            notes: notes,
            order: 0
        )
    }

    /// Create an active step with time duration
    static func activeTime(seconds: Double, intensity: PaceIntensity, notes: String? = nil) -> CanovaWorkoutStep {
        CanovaWorkoutStep(
            id: UUID(),
            stepType: .active,
            durationType: .timeSeconds,
            durationValue: seconds,
            targetPaceIntensity: intensity,
            notes: notes,
            order: 0
        )
    }

    /// Create a recovery step (float recovery between intervals)
    static func recovery(miles: Double, intensity: Double = 75) -> CanovaWorkoutStep {
        CanovaWorkoutStep(
            id: UUID(),
            stepType: .recovery,
            durationType: .distanceMiles,
            durationValue: miles,
            targetPaceIntensity: PaceIntensity(percentage: intensity),
            notes: "Float recovery",
            order: 0
        )
    }

    /// Create a recovery step with meters
    static func recoveryMeters(_ meters: Double, intensity: Double = 75) -> CanovaWorkoutStep {
        CanovaWorkoutStep(
            id: UUID(),
            stepType: .recovery,
            durationType: .distanceMeters,
            durationValue: meters,
            targetPaceIntensity: PaceIntensity(percentage: intensity),
            notes: "Jog recovery",
            order: 0
        )
    }

    /// Create a recovery step with time
    static func recoveryTime(seconds: Double, intensity: Double = 70) -> CanovaWorkoutStep {
        CanovaWorkoutStep(
            id: UUID(),
            stepType: .recovery,
            durationType: .timeSeconds,
            durationValue: seconds,
            targetPaceIntensity: PaceIntensity(percentage: intensity),
            notes: "Recovery jog",
            order: 0
        )
    }

    /// Create a rest step (standing/walking)
    static func rest(seconds: Double) -> CanovaWorkoutStep {
        CanovaWorkoutStep(
            id: UUID(),
            stepType: .rest,
            durationType: .timeSeconds,
            durationValue: seconds,
            targetPaceIntensity: nil,
            notes: "Rest",
            order: 0
        )
    }

    /// Assign order numbers to an array of steps
    static func ordered(_ steps: [CanovaWorkoutStep]) -> [CanovaWorkoutStep] {
        steps.enumerated().map { index, step in
            CanovaWorkoutStep(
                id: step.id,
                stepType: step.stepType,
                durationType: step.durationType,
                durationValue: step.durationValue,
                targetPaceIntensity: step.targetPaceIntensity,
                notes: step.notes,
                order: index
            )
        }
    }
}

// MARK: - Workout Factory

/// Helper for creating CanovaWorkout from template context
struct WorkoutFactory {
    static func create(
        name: String,
        category: CanovaWorkoutCategory,
        phase: CanovaTrainingPhase,
        description: String,
        steps: [CanovaWorkoutStep],
        signatureType: CanovaSignatureType? = nil
    ) -> CanovaWorkout {
        let orderedSteps = StepBuilder.ordered(steps)
        let totalMiles = calculateTotalMiles(steps: orderedSteps)
        let estimatedMinutes = estimateDuration(steps: orderedSteps, totalMiles: totalMiles)

        return CanovaWorkout(
            id: UUID(),
            name: name,
            category: category,
            trainingPhase: phase,
            description: description,
            steps: orderedSteps,
            totalDistanceMiles: totalMiles,
            estimatedDurationMinutes: estimatedMinutes,
            signatureType: signatureType,
            createdAt: Date()
        )
    }

    private static func calculateTotalMiles(steps: [CanovaWorkoutStep]) -> Double {
        steps.reduce(0) { total, step in
            switch step.durationType {
            case .distanceMiles:
                return total + step.durationValue
            case .distanceKm:
                return total + (step.durationValue / 1.60934)
            case .distanceMeters:
                return total + (step.durationValue / 1609.34)
            case .timeSeconds:
                // Estimate ~0.1 miles per minute for recovery/easy
                return total + (step.durationValue / 60 * 0.1)
            case .open:
                return total
            }
        }
    }

    private static func estimateDuration(steps: [CanovaWorkoutStep], totalMiles: Double) -> Double {
        // Rough estimate: 8 min/mile average for mixed workout
        return totalMiles * 8
    }
}

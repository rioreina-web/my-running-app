//
//  CanovaModels.swift
//  RunningLog
//
//  Data models for Renato Canova-inspired AI workout generation.
//

import Foundation
import SwiftUI

// MARK: - Training Phase

/// Four-phase periodization: Base (10%), Support (40%), Specific (40%), Taper (10%)
enum CanovaTrainingPhase: String, Codable, CaseIterable {
    case base = "base"
    case support = "support"
    case specific = "specific"
    case taper = "taper"

    var displayName: String {
        switch self {
        case .base: return "Base Phase"
        case .support: return "Support Phase"
        case .specific: return "Specific Phase"
        case .taper: return "Taper Phase"
        }
    }

    var description: String {
        switch self {
        case .base:
            return "Building aerobic foundation with easy volume and progression runs"
        case .support:
            return "Race-supportive work at 90% and 110% of race pace, building the ladder of support"
        case .specific:
            return "Race-specific workouts at 95-105% of race pace including tempo, intervals, and MP long runs"
        case .taper:
            return "Reducing volume while maintaining intensity for race readiness"
        }
    }

    var icon: String {
        switch self {
        case .base: return "figure.run"
        case .support: return "arrow.up.right"
        case .specific: return "chart.line.uptrend.xyaxis"
        case .taper: return "target"
        }
    }

    var color: Color {
        switch self {
        case .base: return Color.drip.positive
        case .support: return Color.drip.tired
        case .specific: return Color.drip.coral
        case .taper: return Color.drip.energized
        }
    }

    /// Determine phase based on week number and total weeks
    /// Distribution: Base 10%, Support 40%, Specific 40%, Taper 10%
    static func fromWeeksOut(_ weeksOut: Int, totalWeeks: Int) -> CanovaTrainingPhase {
        let taperWeeks = max(1, Int(Double(totalWeeks) * 0.10))
        let baseWeeks = max(1, Int(Double(totalWeeks) * 0.10))
        let supportWeeks = max(2, Int(Double(totalWeeks) * 0.40))

        if weeksOut < taperWeeks {
            return .taper
        } else if weeksOut >= totalWeeks - baseWeeks {
            return .base
        } else if weeksOut >= totalWeeks - baseWeeks - supportWeeks {
            return .support
        } else {
            return .specific
        }
    }

    /// Legacy method for compatibility - assumes 16 week plan
    static func fromWeeksOut(_ weeks: Int) -> CanovaTrainingPhase {
        return fromWeeksOut(weeks, totalWeeks: 16)
    }
}

// MARK: - Workout Category

/// Canova workout categories
enum CanovaWorkoutCategory: String, Codable, CaseIterable {
    case regeneration = "regeneration"
    case fundamental = "fundamental"
    case special = "special"
    case specific = "specific"

    var displayName: String {
        switch self {
        case .regeneration: return "Regeneration"
        case .fundamental: return "Fundamental"
        case .special: return "Special"
        case .specific: return "Specific"
        }
    }

    var description: String {
        switch self {
        case .regeneration: return "Easy recovery running"
        case .fundamental: return "Aerobic building blocks"
        case .special: return "Extending endurance at moderate-fast paces"
        case .specific: return "Race-pace training"
        }
    }

    var color: Color {
        switch self {
        case .regeneration: return Color.drip.positive
        case .fundamental: return Color.drip.energized
        case .special: return Color.drip.coralLight
        case .specific: return Color.drip.coral
        }
    }

    var icon: String {
        switch self {
        case .regeneration: return "leaf.fill"
        case .fundamental: return "heart.fill"
        case .special: return "flame"
        case .specific: return "bolt.fill"
        }
    }
}

// MARK: - Signature Workout Types

/// Canova signature workout types
enum CanovaSignatureType: String, Codable {
    case progressiveTempo = "progressive_tempo"
    case descendingLadder = "descending_ladder"
    case racePaceRepeats = "race_pace_repeats"
    case specialBlock = "special_block"
    case longRunWithTempo = "long_run_with_tempo"

    var displayName: String {
        switch self {
        case .progressiveTempo: return "Progressive Tempo"
        case .descendingLadder: return "Descending Ladder"
        case .racePaceRepeats: return "Race-Pace Repeats"
        case .specialBlock: return "Special Block"
        case .longRunWithTempo: return "Long Run with Tempo"
        }
    }

    var description: String {
        switch self {
        case .progressiveTempo:
            return "Continuous run with progressive speed increase through fractions"
        case .descendingLadder:
            return "6+5+4+3+2+1 km with float recovery between each"
        case .racePaceRepeats:
            return "Repeats at 100-102% of goal race pace"
        case .specialBlock:
            return "Two quality sessions on the same day (AM + PM)"
        case .longRunWithTempo:
            return "Long run finishing with tempo section"
        }
    }
}

// MARK: - Pace Intensity

/// Intensity as percentage of goal race pace
struct PaceIntensity: Codable, Equatable {
    let percentage: Double

    var displayPercentage: String {
        String(format: "%.0f%%", percentage)
    }

    /// Calculate actual pace in seconds per mile given race pace
    func paceSeconds(forRacePace racePaceSeconds: Double) -> Double {
        racePaceSeconds / (percentage / 100.0)
    }

    /// Format pace string given race pace
    func formattedPace(forRacePace racePaceSeconds: Double) -> String {
        let totalSecs = Int(paceSeconds(forRacePace: racePaceSeconds).rounded())
        let mins = totalSecs / 60
        let secs = totalSecs % 60
        return "\(mins):\(String(format: "%02d", secs))/mi"
    }


    /// Get a display label using named pace references when available
    func displayLabel(
        forRacePace racePaceSeconds: Double,
        equivalentPaces: EquivalentPaces?
    ) -> String {
        let actualPace = paceSeconds(forRacePace: racePaceSeconds)

        if let equiv = equivalentPaces,
           let namedPace = equiv.closestNamedPace(forPaceSeconds: actualPace) {
            return namedPace.shortName
        }

        return "\(displayPercentage) MP"
    }
}

// MARK: - Named Pace Reference

/// Named reference paces derived from a goal race performance
enum NamedPace: String, CaseIterable {
    case easy
    case longRun
    case mp
    case hm
    case tenK
    case fiveK

    var displayName: String {
        switch self {
        case .easy: return "Easy"
        case .longRun: return "Long Run"
        case .mp: return "Marathon Pace"
        case .hm: return "Half Marathon Pace"
        case .tenK: return "10K Pace"
        case .fiveK: return "5K Pace"
        }
    }

    var shortName: String {
        switch self {
        case .easy: return "Easy"
        case .longRun: return "Long Run"
        case .mp: return "MP"
        case .hm: return "HM"
        case .tenK: return "10K"
        case .fiveK: return "5K"
        }
    }

    var color: Color {
        switch self {
        case .easy: return Color.drip.positive
        case .longRun: return Color.drip.energized
        case .mp: return Color.drip.coral
        case .hm: return Color.drip.coralLight
        case .tenK: return Color.drip.tired
        case .fiveK: return Color.drip.struggling
        }
    }
}

// MARK: - Equivalent Paces

/// Pre-computed equivalent pace values (in seconds per mile) for a given goal
struct EquivalentPaces {
    let goalRaceDistance: RaceDistance
    let goalTimeSeconds: Int

    /// All paces in seconds per mile
    let mpPace: Double
    let hmPace: Double
    let tenKPace: Double
    let fiveKPace: Double
    let easyPace: Double
    let longRunPace: Double

    /// Named paces that are hidden from display and selection
    var disabledPaces: Set<NamedPace>

    init(raceDistance: RaceDistance, goalTimeSeconds: Int, disabledPaces: Set<NamedPace> = []) {
        self.goalRaceDistance = raceDistance
        self.goalTimeSeconds = goalTimeSeconds
        self.disabledPaces = disabledPaces

        let goalRacePace = raceDistance.racePaceSecondsPerMile(goalTimeSeconds: goalTimeSeconds)

        // Compute equivalent race times using Riegel, then derive paces
        let marathonTime = RaceDistance.marathon.equivalentTime(from: raceDistance, time: goalTimeSeconds)
        self.mpPace = Double(marathonTime) / RaceDistance.marathon.distanceInMiles

        let hmTime = RaceDistance.halfMarathon.equivalentTime(from: raceDistance, time: goalTimeSeconds)
        self.hmPace = Double(hmTime) / RaceDistance.halfMarathon.distanceInMiles

        let tenKTime = RaceDistance.tenK.equivalentTime(from: raceDistance, time: goalTimeSeconds)
        self.tenKPace = Double(tenKTime) / RaceDistance.tenK.distanceInMiles

        let fiveKTime = RaceDistance.fiveK.equivalentTime(from: raceDistance, time: goalTimeSeconds)
        self.fiveKPace = Double(fiveKTime) / RaceDistance.fiveK.distanceInMiles

        // Easy and long run derived from goal race pace + distance-specific intensity
        self.easyPace = goalRacePace / (raceDistance.easyPaceIntensity / 100.0)
        self.longRunPace = goalRacePace / (raceDistance.longRunPaceIntensity / 100.0)
    }

    /// All named paces ordered from slowest to fastest (excluding disabled paces)
    var allPaces: [(NamedPace, Double)] {
        let all: [(NamedPace, Double)] = [
            (.easy, easyPace),
            (.longRun, longRunPace),
            (.mp, mpPace),
            (.hm, hmPace),
            (.tenK, tenKPace),
            (.fiveK, fiveKPace),
        ]
        return all.filter { !disabledPaces.contains($0.0) }
    }

    /// Find the closest named pace for a given actual pace (sec/mi)
    func closestNamedPace(forPaceSeconds paceSeconds: Double, tolerance: Double = 10.0) -> NamedPace? {
        var closest: (NamedPace, Double)?
        for (name, refPace) in allPaces {
            let diff = abs(paceSeconds - refPace)
            if diff <= tolerance {
                if closest == nil || diff < closest!.1 {
                    closest = (name, diff)
                }
            }
        }
        return closest?.0
    }

    /// Get pace seconds for a named pace
    func paceSeconds(for namedPace: NamedPace) -> Double {
        switch namedPace {
        case .easy: return easyPace
        case .longRun: return longRunPace
        case .mp: return mpPace
        case .hm: return hmPace
        case .tenK: return tenKPace
        case .fiveK: return fiveKPace
        }
    }

    /// Format a pace in seconds as a min:sec/mi string
    static func formatPace(_ seconds: Double) -> String {
        let totalSecs = Int(seconds.rounded())
        let mins = totalSecs / 60
        let secs = totalSecs % 60
        return "\(mins):\(String(format: "%02d", secs))/mi"
    }
}

// MARK: - Workout Step

/// A single step within a Canova workout
struct CanovaWorkoutStep: Identifiable, Codable, Equatable {
    let id: UUID
    let stepType: StepType
    let durationType: DurationType
    let durationValue: Double
    let targetPaceIntensity: PaceIntensity?
    let notes: String?
    let order: Int

    enum StepType: String, Codable, CaseIterable {
        case warmup = "warmup"
        case active = "active"
        case rest = "rest"
        case recovery = "recovery"
        case cooldown = "cooldown"

        var displayName: String {
            switch self {
            case .warmup: return "Warm-up"
            case .active: return "Active"
            case .rest: return "Rest"
            case .recovery: return "Float Recovery"
            case .cooldown: return "Cool-down"
            }
        }

        var color: Color {
            switch self {
            case .warmup: return Color.drip.positive
            case .active: return Color.drip.coral
            case .rest: return Color.drip.textSecondary
            case .recovery: return Color.drip.energized
            case .cooldown: return Color.drip.positive
            }
        }
    }

    enum DurationType: String, Codable, CaseIterable {
        case distanceKm = "distance_km"
        case distanceMiles = "distance_miles"
        case distanceMeters = "distance_meters"
        case timeSeconds = "time_seconds"
        case open = "open"

        var unit: String {
            switch self {
            case .distanceKm: return "km"
            case .distanceMiles: return "mi"
            case .distanceMeters: return "m"
            case .timeSeconds: return ""
            case .open: return ""
            }
        }

        var displayLabel: String {
            switch self {
            case .distanceKm: return "km"
            case .distanceMiles: return "miles"
            case .distanceMeters: return "meters"
            case .timeSeconds: return "seconds"
            case .open: return "open"
            }
        }
    }

    /// Format duration for display
    var formattedDuration: String {
        switch durationType {
        case .distanceKm:
            return String(format: "%.1f km", durationValue)
        case .distanceMiles:
            return String(format: "%.1f mi", durationValue)
        case .distanceMeters:
            return String(format: "%.0fm", durationValue)
        case .timeSeconds:
            let mins = Int(durationValue) / 60
            let secs = Int(durationValue) % 60
            if secs > 0 {
                return "\(mins):\(String(format: "%02d", secs))"
            }
            return "\(mins) min"
        case .open:
            return "Open"
        }
    }

    /// Full description including pace target
    func fullDescription(racePaceSeconds: Double) -> String {
        var desc = formattedDuration
        if let intensity = targetPaceIntensity {
            desc += " @ \(intensity.formattedPace(forRacePace: racePaceSeconds))"
            desc += " (\(intensity.displayPercentage))"
        }
        return desc
    }

    /// Full description with named pace labels when available
    func fullDescription(racePaceSeconds: Double, equivalentPaces: EquivalentPaces?) -> String {
        var desc = formattedDuration
        if let intensity = targetPaceIntensity {
            desc += " @ \(intensity.formattedPace(forRacePace: racePaceSeconds))"
            let label = intensity.displayLabel(forRacePace: racePaceSeconds, equivalentPaces: equivalentPaces)
            desc += " (\(label))"
        }
        return desc
    }
}

// MARK: - Editable Workout Step

/// Mutable version of CanovaWorkoutStep for editing
struct EditableWorkoutStep: Identifiable {
    let id: UUID
    var stepType: CanovaWorkoutStep.StepType
    var durationType: CanovaWorkoutStep.DurationType
    var durationValue: Double
    var paceSelection: PaceSelection
    var notes: String
    var order: Int

    /// How the pace target is specified
    enum PaceSelection: Equatable {
        case namedPace(NamedPace)
        case custom(Double)
        case none

        /// Convert to PaceIntensity given equivalent paces and race pace
        func toPaceIntensity(
            racePaceSeconds: Double,
            equivalentPaces: EquivalentPaces
        ) -> PaceIntensity? {
            switch self {
            case .namedPace(let named):
                let targetPaceSeconds = equivalentPaces.paceSeconds(for: named)
                let percentage = racePaceSeconds / targetPaceSeconds * 100.0
                return PaceIntensity(percentage: percentage)
            case .custom(let pct):
                return PaceIntensity(percentage: pct)
            case .none:
                return nil
            }
        }
    }

    /// Initialize from an existing CanovaWorkoutStep
    init(from step: CanovaWorkoutStep, equivalentPaces: EquivalentPaces?, racePaceSeconds: Double) {
        self.id = step.id
        self.stepType = step.stepType
        self.durationType = step.durationType
        self.durationValue = step.durationValue
        self.order = step.order
        self.notes = step.notes ?? ""

        if let intensity = step.targetPaceIntensity, let equiv = equivalentPaces {
            let actualPace = intensity.paceSeconds(forRacePace: racePaceSeconds)
            if let named = equiv.closestNamedPace(forPaceSeconds: actualPace) {
                self.paceSelection = .namedPace(named)
            } else {
                self.paceSelection = .custom(intensity.percentage)
            }
        } else if let intensity = step.targetPaceIntensity {
            self.paceSelection = .custom(intensity.percentage)
        } else {
            self.paceSelection = .none
        }
    }

    /// Initialize a new empty step
    init(order: Int) {
        self.id = UUID()
        self.stepType = .active
        self.durationType = .distanceMiles
        self.durationValue = 1.0
        self.paceSelection = .namedPace(.mp)
        self.notes = ""
        self.order = order
    }

    /// Convert back to CanovaWorkoutStep
    func toCanovaStep(racePaceSeconds: Double, equivalentPaces: EquivalentPaces) -> CanovaWorkoutStep {
        CanovaWorkoutStep(
            id: id,
            stepType: stepType,
            durationType: durationType,
            durationValue: durationValue,
            targetPaceIntensity: paceSelection.toPaceIntensity(
                racePaceSeconds: racePaceSeconds,
                equivalentPaces: equivalentPaces
            ),
            notes: notes.isEmpty ? nil : notes,
            order: order
        )
    }
}

// MARK: - Canova Workout

/// Complete Canova workout with all steps
struct CanovaWorkout: Identifiable, Codable {
    let id: UUID
    let name: String
    let category: CanovaWorkoutCategory
    let trainingPhase: CanovaTrainingPhase
    let description: String
    let steps: [CanovaWorkoutStep]
    let totalDistanceMiles: Double?
    let estimatedDurationMinutes: Double?
    let signatureType: CanovaSignatureType?
    let createdAt: Date

    // Legacy support for Supabase data stored in km
    private enum CodingKeys: String, CodingKey {
        case id, name, category, trainingPhase, description, steps
        case totalDistanceMiles = "total_distance_km" // Keep same DB column, convert on read
        case estimatedDurationMinutes = "estimated_duration_minutes"
        case signatureType = "signature_type"
        case createdAt = "created_at"
    }

    var formattedTotalDistance: String? {
        guard let miles = totalDistanceMiles else { return nil }
        return String(format: "%.1f mi", miles)
    }

    var formattedDuration: String? {
        guard let mins = estimatedDurationMinutes else { return nil }
        if mins >= 60 {
            let hours = Int(mins) / 60
            let remaining = Int(mins) % 60
            if remaining > 0 {
                return "\(hours)h \(remaining)m"
            }
            return "\(hours)h"
        }
        return "\(Int(mins)) min"
    }

    var activeSteps: [CanovaWorkoutStep] {
        steps.filter { $0.stepType == .active }
    }

    /// Calculate total active distance in miles
    var totalActiveDistanceMiles: Double {
        steps.filter { $0.stepType == .active }.reduce(0) { total, step in
            switch step.durationType {
            case .distanceKm:
                return total + step.durationValue / 1.60934
            case .distanceMiles:
                return total + step.durationValue
            case .distanceMeters:
                return total + step.durationValue / 1609.34
            default:
                return total
            }
        }
    }

    /// Backward compatibility: total distance in km
    var totalDistanceKm: Double? {
        guard let miles = totalDistanceMiles else { return nil }
        return miles * 1.60934
    }
}

// MARK: - Workout Generation Request

/// Request payload for generating a Canova workout
struct WorkoutGenerationRequest: Codable {
    let userId: String
    let goalRaceDistance: String
    let goalTimeSeconds: Int
    let targetDate: Date
    let weeksUntilRace: Int
    let currentPhase: String
    let currentWeeklyMileage: Double?
    let preferredWorkoutType: String?
    let fitnessLevel: String?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case goalRaceDistance = "goal_race_distance"
        case goalTimeSeconds = "goal_time_seconds"
        case targetDate = "target_date"
        case weeksUntilRace = "weeks_until_race"
        case currentPhase = "current_phase"
        case currentWeeklyMileage = "current_weekly_mileage"
        case preferredWorkoutType = "preferred_workout_type"
        case fitnessLevel = "fitness_level"
    }
}

// MARK: - Workout Generation Response

/// Response from workout generator edge function
struct WorkoutGenerationResponse: Codable {
    let workout: CanovaWorkout?
    let error: String?
}

// MARK: - Generated Workout Record

/// Database record for stored workouts
struct GeneratedWorkoutRecord: Codable, Identifiable {
    let id: UUID
    let workoutData: CanovaWorkout
    let goalRaceDistance: String?
    let goalTimeSeconds: Int?
    let trainingPhase: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case workoutData = "workout_data"
        case goalRaceDistance = "goal_race_distance"
        case goalTimeSeconds = "goal_time_seconds"
        case trainingPhase = "training_phase"
        case createdAt = "created_at"
    }
}

// MARK: - Helper Extensions

extension CanovaWorkout {
    /// Create a sample workout for previews
    static var sample: CanovaWorkout {
        CanovaWorkout(
            id: UUID(),
            name: "Progressive Tempo Run",
            category: .special,
            trainingPhase: .specific,
            description: "Build aerobic capacity with progressive intensity",
            steps: [
                CanovaWorkoutStep(
                    id: UUID(),
                    stepType: .warmup,
                    durationType: .distanceMiles,
                    durationValue: 2.0,
                    targetPaceIntensity: PaceIntensity(percentage: 70),
                    notes: "Easy warm-up",
                    order: 0
                ),
                CanovaWorkoutStep(
                    id: UUID(),
                    stepType: .active,
                    durationType: .distanceMiles,
                    durationValue: 4.0,
                    targetPaceIntensity: PaceIntensity(percentage: 87),
                    notes: "First fraction - comfortable",
                    order: 1
                ),
                CanovaWorkoutStep(
                    id: UUID(),
                    stepType: .active,
                    durationType: .distanceMiles,
                    durationValue: 4.0,
                    targetPaceIntensity: PaceIntensity(percentage: 95),
                    notes: "Second fraction - push",
                    order: 2
                ),
                CanovaWorkoutStep(
                    id: UUID(),
                    stepType: .cooldown,
                    durationType: .distanceMiles,
                    durationValue: 2.0,
                    targetPaceIntensity: PaceIntensity(percentage: 65),
                    notes: "Easy cool-down",
                    order: 3
                )
            ],
            totalDistanceMiles: 12.0,
            estimatedDurationMinutes: 90,
            signatureType: .progressiveTempo,
            createdAt: Date()
        )
    }
}

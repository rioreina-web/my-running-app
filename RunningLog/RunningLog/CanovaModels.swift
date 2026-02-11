//
//  CanovaModels.swift
//  RunningLog
//
//  Data models for Renato Canova-inspired AI workout generation.
//

import Foundation
import SwiftUI

// MARK: - Training Phase

/// Three-phase marathon periodization: Base (20%), Specific (70%), Taper (10%)
enum CanovaTrainingPhase: String, Codable, CaseIterable {
    case base = "base"
    case specific = "specific"
    case taper = "taper"

    var displayName: String {
        switch self {
        case .base: return "Base Phase"
        case .specific: return "Specific Phase"
        case .taper: return "Taper Phase"
        }
    }

    var description: String {
        switch self {
        case .base:
            return "Building aerobic foundation with easy volume and progression runs"
        case .specific:
            return "Race-specific workouts including tempo, intervals, and long runs with MP work"
        case .taper:
            return "Reducing volume while maintaining intensity for race readiness"
        }
    }

    var icon: String {
        switch self {
        case .base: return "figure.run"
        case .specific: return "chart.line.uptrend.xyaxis"
        case .taper: return "target"
        }
    }

    var color: Color {
        switch self {
        case .base: return Color.drip.positive
        case .specific: return Color.drip.coral
        case .taper: return Color.drip.energized
        }
    }

    /// Determine phase based on week number and total weeks
    /// Distribution: Base 20%, Specific 70%, Taper 10%
    static func fromWeeksOut(_ weeksOut: Int, totalWeeks: Int) -> CanovaTrainingPhase {
        let taperWeeks = max(1, Int(Double(totalWeeks) * 0.10))
        let baseWeeks = max(2, Int(Double(totalWeeks) * 0.20))

        if weeksOut < taperWeeks {
            return .taper
        } else if weeksOut >= totalWeeks - baseWeeks {
            return .base
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
        let pace = paceSeconds(forRacePace: racePaceSeconds)
        let mins = Int(pace) / 60
        let secs = Int(pace) % 60
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

    enum StepType: String, Codable {
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

    enum DurationType: String, Codable {
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

//
//  PlannedWorkoutModels.swift
//  RunningLog
//
//  Workout definition and import types: ImportedDayWorkout, ImportedPlanResponse,
//  ImportedWeek, and ScheduledWorkoutType import helpers.
//

import Foundation
import os
import SwiftUI

// MARK: - Import Week Models

/// A single day's workout parsed from user text by AI
struct ImportedDayWorkout: Identifiable, Codable {
    var id: UUID { UUID() }
    let dayOfWeek: Int
    let dayName: String
    /// Session number for doubles: 1 = first run, 2 = second run, etc.
    let session: Int?
    let workoutType: String
    let name: String
    let description: String
    let totalDistanceMiles: Double?
    let estimatedDurationMinutes: Double?
    let steps: [ImportedStep]

    // TODO(adaptive-plan-1.5): REWORK this struct.
    //   Add target_pace_seconds_per_mile + pace_reference ('5K', '10K', 'half', 'marathon', 'mile', 'easy').
    //   Keep pacePercentage only as a transitional field — will be dropped in a follow-up migration.
    //   Backend plan-generation (Prompt 1.6) resolves references to concrete seconds before write.
    //   See: adaptive-plan-loop-prompts.md § Prompts 1.5, 1.6
    struct ImportedStep: Codable {
        let stepType: String
        let durationType: String
        let durationValue: Double
        let pacePercentage: Double?
        /// Fast end of a pace range (lower seconds per km = faster pace).
        let paceSecondsPerKm: Double?
        /// Slow end of a pace range (higher seconds per km = slower pace).
        /// `nil` when no range was given. Name refers to higher seconds/km, not higher % of race pace.
        let paceSecondsPerKmHigh: Double?
        /// Phase 1 canonical pace (seconds per mile). When present, wins over
        /// pacePercentage + paceSecondsPerKm. Written by the plan-generation
        /// edge functions and resolved against AthletePaceProfile server-side.
        let targetPaceSecondsPerMile: Double?
        let targetPaceSecondsHigh: Double?
        /// Named reference ("easy" | "marathon" | "half" | "10K" | "5K" | "mile")
        /// — a display label when target_pace_seconds_per_mile is present.
        let paceReference: String?
        /// Interval set count. When >1, this step is rendered as "N × {duration}"
        /// with `recovery` nested underneath. Authored by coaches in the web
        /// editor and by the LLM when generating interval workouts. Required
        /// for any "Nx Mmi" workout — without it the structure is lost.
        let repeats: Int?
        /// Between-rep recovery. Only meaningful when `repeats > 1`.
        let recovery: ImportedStepRecovery?
        let notes: String?
        let order: Int?

        init(stepType: String, durationType: String, durationValue: Double,
             pacePercentage: Double? = nil, paceSecondsPerKm: Double? = nil,
             paceSecondsPerKmHigh: Double? = nil,
             targetPaceSecondsPerMile: Double? = nil,
             targetPaceSecondsHigh: Double? = nil,
             paceReference: String? = nil,
             repeats: Int? = nil,
             recovery: ImportedStepRecovery? = nil,
             notes: String? = nil, order: Int? = nil) {
            self.stepType = stepType
            self.durationType = durationType
            self.durationValue = durationValue
            self.pacePercentage = pacePercentage
            self.paceSecondsPerKm = paceSecondsPerKm
            self.paceSecondsPerKmHigh = paceSecondsPerKmHigh
            self.targetPaceSecondsPerMile = targetPaceSecondsPerMile
            self.targetPaceSecondsHigh = targetPaceSecondsHigh
            self.paceReference = paceReference
            self.repeats = repeats
            self.recovery = recovery
            self.notes = notes
            self.order = order
        }

        private enum CodingKeys: String, CodingKey {
            case stepType, durationType, durationValue
            case pacePercentage, paceSecondsPerKm, paceSecondsPerKmHigh
            case repeats, recovery, notes, order
            case targetPaceSecondsPerMile = "target_pace_seconds_per_mile"
            case targetPaceSecondsHigh = "target_pace_seconds_high"
            case paceReference = "pace_reference"
        }
    }

    /// Between-rep recovery for an interval set. Mirrors
    /// `PlannedWorkoutRecovery` but uses string-typed fields for compatibility
    /// with the import + AI edge function payloads.
    struct ImportedStepRecovery: Codable {
        let durationType: String
        let durationValue: Double
        let paceSecondsPerKm: Double?
        let pacePercentage: Double?

        init(durationType: String, durationValue: Double,
             paceSecondsPerKm: Double? = nil,
             pacePercentage: Double? = nil) {
            self.durationType = durationType
            self.durationValue = durationValue
            self.paceSecondsPerKm = paceSecondsPerKm
            self.pacePercentage = pacePercentage
        }
    }

    private enum CodingKeys: String, CodingKey {
        case dayOfWeek, dayName, session, workoutType, name, description
        case totalDistanceMiles, estimatedDurationMinutes, steps
    }

    /// Whether this is a double (session 2+)
    var isSecondarySession: Bool {
        (session ?? 1) > 1
    }

    /// Convert to PlannedWorkout for the training plan
    func toPlannedWorkout(phase: TrainingPhase, racePaceSecondsPerMile: Double? = nil) -> PlannedWorkout {
        let category: PlannedWorkoutCategory = switch workoutType {
        case "easy", "recovery": .regeneration
        case "tempo", "progression", "strides": .special
        case "intervals": .specific
        case "long_run": .fundamental
        default: .regeneration
        }

        let canovaSteps = steps.enumerated().map { index, step in
            let stepType: PlannedWorkoutStep.StepType = switch step.stepType {
            case "warmup": .warmup
            case "rest": .rest
            case "recovery": .recovery
            case "cooldown": .cooldown
            default: .active
            }

            let durationType: PlannedWorkoutStep.DurationType = switch step.durationType {
            case "distance_km": .distanceKm
            case "distance_meters": .distanceMeters
            case "time_seconds": .timeSeconds
            default: .distanceMiles
            }

            // Build PaceIntensity from concrete pace data only. Percentage
            // fallbacks have been removed — if a step has no paceSecondsPerKm
            // (and no race pace to derive one from), surface nil so the
            // caller can show "pace not set" instead of inventing a number.
            //
            // Phase 1 canonical field wins: if target_pace_seconds_per_mile
            // is populated we convert → seconds/km and use it directly.
            let intensity: PaceIntensity? = {
                if let secPerMile = step.targetPaceSecondsPerMile, secPerMile > 0 {
                    let secPerKm = secPerMile / 1.609344
                    let secPerKmHigh = step.targetPaceSecondsHigh.map { $0 / 1.609344 }
                    return PaceIntensity(
                        percentage: 0,
                        paceSecondsPerKm: secPerKm,
                        paceSecondsPerKmHigh: secPerKmHigh
                    )
                }
                guard let paceKm = step.paceSecondsPerKm else {
                    if step.pacePercentage != nil {
                        Log.paceProfile.error(
                            "PlannedWorkoutStep has pacePercentage but no paceSecondsPerKm — data bug, resolver should have populated it (step order: \(step.order ?? -1))"
                        )
                    }
                    return nil
                }

                // Derive percentage from actual pace when we have a race-pace anchor.
                // If we don't, leave percentage at zero — callers should prefer
                // paceSecondsPerKm for display, and displayLabel falls back to "—".
                let pct: Double = {
                    guard let racePace = racePaceSecondsPerMile, racePace > 0 else { return 0 }
                    let racePacePerKm = racePace / 1.609344
                    return (racePacePerKm / paceKm) * 100
                }()
                let pctHigh: Double? = step.paceSecondsPerKmHigh.flatMap { highKm in
                    guard let racePace = racePaceSecondsPerMile, racePace > 0 else { return nil }
                    return (racePace / 1.609344 / highKm) * 100
                }
                return PaceIntensity(
                    percentage: pct,
                    percentageHigh: pctHigh,
                    paceSecondsPerKm: paceKm,
                    paceSecondsPerKmHigh: step.paceSecondsPerKmHigh
                )
            }()

            // Convert nested recovery (if any) to PlannedWorkoutRecovery.
            // Same priority order as the main step: targetPaceSecondsPerMile
            // would win if present, but recovery typically only has
            // pacePercentage / paceSecondsPerKm.
            let recovery: PlannedWorkoutRecovery? = {
                guard let r = step.recovery else { return nil }
                let recDurationType: PlannedWorkoutStep.DurationType = switch r.durationType {
                case "distance_km": .distanceKm
                case "distance_meters": .distanceMeters
                case "time_seconds": .timeSeconds
                default: .distanceMiles
                }
                return PlannedWorkoutRecovery(
                    durationType: recDurationType,
                    durationValue: r.durationValue,
                    paceZone: nil,
                    paceAdjustment: nil
                )
            }()

            return PlannedWorkoutStep(
                id: UUID(),
                stepType: stepType,
                durationType: durationType,
                durationValue: step.durationValue,
                targetPaceIntensity: intensity,
                notes: step.notes,
                order: step.order ?? index,
                paceZone: nil,
                paceAdjustment: nil,
                repeats: (step.repeats ?? 1) > 1 ? step.repeats : nil,
                recovery: recovery
            )
        }

        return PlannedWorkout(
            id: UUID(),
            name: name,
            category: category,
            trainingPhase: phase,
            description: description,
            steps: canovaSteps,
            totalDistanceMiles: totalDistanceMiles,
            estimatedDurationMinutes: estimatedDurationMinutes,
            signatureType: nil,
            createdAt: Date()
        )
    }
}

// MARK: - Full Plan Import Models

/// Response from the parse-training-plan edge function
struct ImportedPlanResponse: Codable {
    let totalWeeks: Int
    let clarifications: [Clarification]?
    let weeks: [ImportedWeek]
    let planName: String?
    let detectedMeta: DetectedMeta?
    let missingFields: [String]?

    struct Clarification: Identifiable, Codable {
        let id: String
        let question: String
        let options: [String]?
    }

    struct DetectedMeta: Codable {
        let raceDistance: String?
        let goalTime: String?
        let startDate: String?
    }
}

/// A single week within an imported multi-week plan
struct ImportedWeek: Identifiable, Codable {
    var id: UUID { UUID() }
    let weekNumber: Int
    let label: String?
    let totalDistanceMiles: Double?
    let days: [ImportedDayWorkout]

    private enum CodingKeys: String, CodingKey {
        case weekNumber, label, totalDistanceMiles, days
    }
}

// MARK: - ScheduledWorkoutType Import Helper

extension ScheduledWorkoutType {
    static func fromImportString(_ str: String) -> ScheduledWorkoutType {
        switch str.lowercased() {
        case "easy": return .easy
        case "tempo": return .tempo
        case "intervals": return .intervals
        case "long_run", "longrun": return .longRun
        case "recovery": return .recovery
        case "race": return .race
        case "progression": return .progression
        case "strides": return .strides
        case "rest": return .rest
        default: return .easy
        }
    }
}

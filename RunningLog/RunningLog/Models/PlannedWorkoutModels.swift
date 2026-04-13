//
//  PlannedWorkoutModels.swift
//  RunningLog
//
//  Workout definition and import types: ImportedDayWorkout, ImportedPlanResponse,
//  ImportedWeek, and ScheduledWorkoutType import helpers.
//

import Foundation
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

    struct ImportedStep: Codable {
        let stepType: String
        let durationType: String
        let durationValue: Double
        let pacePercentage: Double?
        let paceSecondsPerKm: Double?
        let paceSecondsPerKmHigh: Double?
        let notes: String?
        let order: Int?

        init(stepType: String, durationType: String, durationValue: Double,
             pacePercentage: Double? = nil, paceSecondsPerKm: Double? = nil,
             paceSecondsPerKmHigh: Double? = nil, notes: String? = nil, order: Int? = nil) {
            self.stepType = stepType
            self.durationType = durationType
            self.durationValue = durationValue
            self.pacePercentage = pacePercentage
            self.paceSecondsPerKm = paceSecondsPerKm
            self.paceSecondsPerKmHigh = paceSecondsPerKmHigh
            self.notes = notes
            self.order = order
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

            // Build PaceIntensity: prefer actual pace data, fall back to percentage
            let intensity: PaceIntensity? = {
                if let paceKm = step.paceSecondsPerKm {
                    // Compute percentage from actual pace if we have race pace
                    let pct: Double
                    if let racePace = racePaceSecondsPerMile {
                        let racePacePerKm = racePace / 1.60934
                        pct = (racePacePerKm / paceKm) * 100
                    } else {
                        pct = step.pacePercentage ?? 80
                    }
                    let pctHigh: Double? = step.paceSecondsPerKmHigh.map { highKm in
                        if let racePace = racePaceSecondsPerMile {
                            return (racePace / 1.60934 / highKm) * 100
                        }
                        return pct
                    }
                    return PaceIntensity(
                        percentage: pct,
                        percentageHigh: pctHigh,
                        paceSecondsPerKm: paceKm,
                        paceSecondsPerKmHigh: step.paceSecondsPerKmHigh
                    )
                } else if let pct = step.pacePercentage {
                    return PaceIntensity(percentage: pct)
                }
                return nil
            }()

            return PlannedWorkoutStep(
                id: UUID(),
                stepType: stepType,
                durationType: durationType,
                durationValue: step.durationValue,
                targetPaceIntensity: intensity,
                notes: step.notes,
                order: step.order ?? index
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

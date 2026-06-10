//
//  AITrainingPlanService.swift
//  RunningLog
//
//  Service for AI-powered marathon training plan generation via conversation.
//

import Foundation
import os

// MARK: - AI Plan Chat Response

struct AIPlanChatResponse: Codable {
    let type: String // "question" or "plan"
    let message: String
    let conversationId: String?
    let planData: AIPlanData?
}

struct AIPlanData: Codable {
    let plan: AIPlanMeta
    let workouts: [AIPlanWorkout]
}

struct AIPlanMeta: Codable {
    let name: String
    let startDate: String
    let endDate: String
    let targetRaceDistance: String?
    let targetTimeSeconds: Int?
}

struct AIPlanWorkout: Codable {
    let date: String
    let dayOfWeek: Int
    let dayName: String?
    let weekNumber: Int
    let workoutType: String
    let name: String
    let description: String
    let totalDistanceMiles: Double?
    let estimatedDurationMinutes: Double?
    let steps: [AIPlanStep]
}

struct AIPlanStep: Codable {
    let stepType: String
    let durationType: String
    let durationValue: Double
    let pacePercentage: Double?
    // Named zone preferred over raw percentage. The model emits one of:
    //   easy, longRun, moderate, steady, mp, hm, threshold, tenK, fiveK,
    //   threeK, mile, recovery
    // Falls back to pacePercentage only when the model cannot map the
    // requested effort to a zone (rare).
    let paceZone: String?
    // Off-baseline adjustment authored by the coach or LLM (e.g. "+3% for
    // heat", "-10s/mi"). Layers on top of paceZone.
    let paceAdjustment: AIPlanPaceAdjustment?
    // Interval set count. When >1, this step is rendered as "N × {duration}"
    // with the recovery nested underneath. The schema MUST be used to
    // express interval workouts; flat repetition lists or freeform
    // descriptions are not acceptable substitutes.
    let repeats: Int?
    // Between-rep recovery for interval sets. Only meaningful when
    // repeats > 1. Same fields as a step but no nested repeats/recovery.
    let recovery: AIPlanStepRecovery?
    let notes: String?
    let order: Int?
}

struct AIPlanPaceAdjustment: Codable {
    let type: String   // "percent" | "seconds_per_mile" | "seconds_per_km"
    let value: Double
}

struct AIPlanStepRecovery: Codable {
    let durationType: String
    let durationValue: Double
    let paceZone: String?
    let pacePercentage: Double?
}

// MARK: - AITrainingPlanService

@Observable
final class AITrainingPlanService {
    var isLoading = false
    var error: String?

    @MainActor
    func sendMessage(
        _ message: String,
        conversationId: String?,
        startDate: Date? = nil,
        raceDate: Date? = nil,
        goalTimeSeconds: Int? = nil,
        currentWeeklyMileage: Double? = nil,
        assessment: [String: Any]? = nil
    ) async throws -> AIPlanChatResponse {
        isLoading = true
        error = nil
        defer { isLoading = false }

        var body: [String: Any] = [
            "message": message,
        ]

        if let conversationId {
            body["conversationId"] = conversationId
        }

        // Pre-filled context (only on first message)
        if conversationId == nil {
            if let startDate {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                body["startDate"] = formatter.string(from: startDate)
            }
            if let raceDate {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                body["raceDate"] = formatter.string(from: raceDate)
            }
            if let goalTimeSeconds {
                body["goalTimeSeconds"] = goalTimeSeconds
            }
            if let currentWeeklyMileage {
                body["currentWeeklyMileage"] = currentWeeklyMileage
            }
            if let assessment {
                body["assessment"] = assessment
            }
        }

        let data = try await callEdgeFunction(name: "generate-training-plan", body: body)

        // Check for error response
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let errorMsg = json["error"] as? String {
            self.error = errorMsg
            throw AITrainingPlanError.serverError(errorMsg)
        }

        let decoder = JSONDecoder()
        let response = try decoder.decode(AIPlanChatResponse.self, from: data)
        return response
    }

    /// Convert AI plan data into the ImportedPlanResponse format for the existing import pipeline
    func toImportedPlanResponse(_ planData: AIPlanData) -> ImportedPlanResponse {
        // Group workouts by weekNumber
        let grouped = Dictionary(grouping: planData.workouts, by: \.weekNumber)
        let sortedWeeks = grouped.keys.sorted()

        let weeks: [ImportedWeek] = sortedWeeks.map { weekNum in
            let weekWorkouts = grouped[weekNum] ?? []

            let days: [ImportedDayWorkout] = weekWorkouts.map { w in
                let steps: [ImportedDayWorkout.ImportedStep] = w.steps.map { s -> ImportedDayWorkout.ImportedStep in
                    let recovery: ImportedDayWorkout.ImportedStepRecovery? = s.recovery.map { r in
                        ImportedDayWorkout.ImportedStepRecovery(
                            durationType: r.durationType,
                            durationValue: r.durationValue,
                            paceSecondsPerKm: nil,
                            pacePercentage: r.pacePercentage
                        )
                    }
                    return ImportedDayWorkout.ImportedStep(
                        stepType: s.stepType,
                        durationType: s.durationType,
                        durationValue: s.durationValue,
                        pacePercentage: s.pacePercentage,
                        paceReference: s.paceZone,
                        repeats: s.repeats,
                        recovery: recovery,
                        notes: s.notes,
                        order: s.order
                    )
                }

                return ImportedDayWorkout(
                    dayOfWeek: w.dayOfWeek,
                    dayName: w.dayName ?? dayNameForWeekday(w.dayOfWeek),
                    session: 1,
                    workoutType: w.workoutType,
                    name: w.name,
                    description: w.description,
                    totalDistanceMiles: w.totalDistanceMiles,
                    estimatedDurationMinutes: w.estimatedDurationMinutes,
                    steps: steps
                )
            }

            let totalMiles = weekWorkouts.compactMap(\.totalDistanceMiles).reduce(0, +)

            return ImportedWeek(
                weekNumber: weekNum,
                label: "Week \(weekNum)",
                totalDistanceMiles: totalMiles > 0 ? totalMiles : nil,
                days: days
            )
        }

        return ImportedPlanResponse(
            totalWeeks: sortedWeeks.count,
            clarifications: nil,
            weeks: weeks,
            planName: planData.plan.name,
            detectedMeta: nil,
            missingFields: nil
        )
    }

    private func dayNameForWeekday(_ dow: Int) -> String {
        let names = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        guard dow >= 1, dow <= 7 else { return "Monday" }
        return names[dow - 1]
    }
}

// MARK: - Error

enum AITrainingPlanError: LocalizedError {
    case serverError(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .serverError(let msg): return msg
        case .invalidResponse: return "Invalid response from AI coach"
        }
    }
}

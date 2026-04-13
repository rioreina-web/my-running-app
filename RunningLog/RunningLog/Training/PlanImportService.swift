//
//  PlanImportService.swift
//  RunningLog
//
//  Handles training plan import parsing and application.
//

import Foundation
import os
import Supabase
import SwiftUI

// MARK: - PlanImportService

@Observable
final class PlanImportService {
    // MARK: - Dependencies

    private unowned let vm: TrainingPlanViewModel

    // MARK: - Import Week State

    var importedWorkouts: [ImportedDayWorkout]?
    var isParsingImport = false
    var importError: String?

    // MARK: - Import Full Plan State

    var importedPlanResponse: ImportedPlanResponse?
    var isParsingPlanImport = false
    var planImportError: String?

    // MARK: - Init

    init(viewModel: TrainingPlanViewModel) {
        self.vm = viewModel
    }

    // MARK: - Parse Week from Text

    @MainActor
    func parseWeekFromText(_ text: String) async {
        isParsingImport = true
        importError = nil
        importedWorkouts = nil

        let goalTime = vm.activePlan?.targetTimeSeconds ?? vm.marathonGoalTime ?? 14400
        let raceDistance = vm.activePlan?.targetRaceDistance ?? "marathon"

        let body: [String: Any] = [
            "text": text,
            "goalTimeSeconds": goalTime,
            "raceDistance": raceDistance,
            "currentPhase": vm.currentPhase.rawValue,
        ]

        do {
            let data = try await callEdgeFunction(name: "parse-training-week", body: body)

            struct ParseResponse: Codable {
                let days: [ImportedDayWorkout]?
                let error: String?
            }

            let response = try JSONDecoder().decode(ParseResponse.self, from: data)

            if let error = response.error {
                importError = error
            } else if let days = response.days {
                importedWorkouts = days
            } else {
                importError = "No workouts returned"
            }
        } catch {
            importError = error.localizedDescription
        }

        isParsingImport = false
    }

    @MainActor
    func applyImportedWorkouts() async {
        guard let imported = importedWorkouts, let plan = vm.activePlan else { return }
        vm.isSaving = true

        let weekWorkouts = vm.currentWeekWorkouts

        // Group imported workouts by dayOfWeek to handle doubles
        let dayGroups = Dictionary(grouping: imported, by: \.dayOfWeek)

        for (dayOfWeek, sessions) in dayGroups {
            let sortedSessions = sessions.sorted { ($0.session ?? 1) < ($1.session ?? 1) }
            let existingForDay = weekWorkouts
                .filter { $0.dayOfWeek == dayOfWeek }
                .sorted { $0.session < $1.session }

            for (idx, importedDay) in sortedSessions.enumerated() {
                let sessionNum = importedDay.session ?? (idx + 1)

                if importedDay.workoutType == "rest" {
                    if let existing = existingForDay.first {
                        await vm.convertToRestDay(existing)
                    }
                    continue
                }

                let workout = importedDay.toPlannedWorkout(phase: vm.currentPhase, racePaceSecondsPerMile: vm.racePaceSecondsPerMile)
                let workoutType = ScheduledWorkoutType.fromImportString(importedDay.workoutType)

                if idx < existingForDay.count {
                    var updated = existingForDay[idx]
                    updated.workout = workout
                    updated.workoutType = workoutType
                    updated.status = .modified
                    await vm.updateWorkout(updated)
                } else {
                    guard let existing = existingForDay.first else { continue }
                    let insert = ScheduledWorkoutInsert(
                        planId: plan.id,
                        date: existing.date,
                        dayOfWeek: dayOfWeek,
                        weekNumber: vm.selectedWeek,
                        session: sessionNum,
                        workoutData: workout,
                        workoutType: workoutType
                    )
                    _ = await vm.insertScheduledWorkout(insert)
                }
            }
        }

        importedWorkouts = nil
        vm.isSaving = false
    }

    // MARK: - Parse Full Training Plan

    @MainActor
    func parseFullPlan(text: String? = nil, imageBase64: String? = nil, imageMimeType: String? = nil, fileBase64: String? = nil, fileType: String? = nil, clarificationAnswers: [[String: String]]? = nil) async {
        isParsingPlanImport = true
        planImportError = nil
        if clarificationAnswers == nil {
            importedPlanResponse = nil
        }

        var body: [String: Any] = [:]
        if let text { body["text"] = text }
        if let imageBase64 { body["imageBase64"] = imageBase64 }
        if let imageMimeType { body["imageMimeType"] = imageMimeType }
        if let fileBase64 { body["fileBase64"] = fileBase64 }
        if let fileType { body["fileType"] = fileType }

        if let goalTime = vm.activePlan?.targetTimeSeconds ?? vm.marathonGoalTime {
            body["goalTimeSeconds"] = goalTime
        }
        if let distance = vm.activePlan?.targetRaceDistance {
            body["raceDistance"] = distance
        }

        if let answers = clarificationAnswers {
            body["clarificationAnswers"] = answers
        }

        do {
            let data = try await callEdgeFunction(name: "parse-training-plan", body: body)

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorMsg = json["error"] as? String {
                planImportError = errorMsg
                isParsingPlanImport = false
                return
            }

            let response = try JSONDecoder().decode(ImportedPlanResponse.self, from: data)

            if response.weeks.isEmpty {
                planImportError = "No weeks found in the training plan"
            } else {
                importedPlanResponse = response
            }
        } catch let decodingError as DecodingError {
            switch decodingError {
            case .keyNotFound(let key, _):
                planImportError = "Parsing error: missing field '\(key.stringValue)'"
            case .typeMismatch(_, let context):
                planImportError = "Parsing error at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
            default:
                planImportError = "Could not parse response: \(decodingError.localizedDescription)"
            }
            Log.coach.error("Plan import decoding error: \(decodingError)")
        } catch {
            planImportError = error.localizedDescription
        }

        isParsingPlanImport = false
    }

    // MARK: - Apply Imported Plan (New Plan)

    @MainActor
    func applyImportedPlan(
        name: String,
        startDate: Date,
        raceDistance: String,
        goalTimeSeconds: Int
    ) async -> Bool {
        guard let response = importedPlanResponse else { return false }

        let calendar = Calendar.current
        _ = response.totalWeeks
        let raceDistEnum = RaceDistance.from(legacyString: raceDistance) ?? .marathon
        _ = raceDistEnum.racePaceSecondsPerMile(goalTimeSeconds: goalTimeSeconds)
        var allWorkouts: [ImportedDayWorkout] = []
        var allDates: [Date] = []

        for week in response.weeks {
            let weekOffset = week.weekNumber - 1
            let weekStart = calendar.date(byAdding: .weekOfYear, value: weekOffset, to: startDate) ?? startDate
            let weekday = calendar.component(.weekday, from: weekStart)
            let daysToMonday = (weekday == 1) ? -6 : 2 - weekday
            let monday = calendar.date(byAdding: .day, value: daysToMonday, to: weekStart) ?? weekStart

            let dayGroups = Dictionary(grouping: week.days, by: \.dayOfWeek)

            for dayOfWeek in 1...7 {
                let sessions = (dayGroups[dayOfWeek] ?? [])
                    .sorted { ($0.session ?? 1) < ($1.session ?? 1) }
                let dayOffset = dayOfWeek - 1
                let workoutDate = calendar.date(byAdding: .day, value: dayOffset, to: monday) ?? monday

                if sessions.isEmpty {
                    let dayNames = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
                    allWorkouts.append(ImportedDayWorkout(
                        dayOfWeek: dayOfWeek,
                        dayName: dayNames[dayOfWeek - 1],
                        session: 1,
                        workoutType: "rest",
                        name: "Rest Day",
                        description: "Recovery day",
                        totalDistanceMiles: nil,
                        estimatedDurationMinutes: nil,
                        steps: []
                    ))
                    allDates.append(workoutDate)
                } else {
                    // Keep each session as a separate workout (supports doubles)
                    for session in sessions {
                        allWorkouts.append(session)
                        allDates.append(workoutDate)
                    }
                }
            }
        }

        let endDate = allDates.max() ?? calendar.date(byAdding: .weekOfYear, value: response.totalWeeks, to: startDate) ?? startDate

        let success = await importCustomPlan(
            name: name,
            startDate: startDate,
            endDate: endDate,
            targetRaceDistance: raceDistance,
            targetTimeSeconds: goalTimeSeconds,
            importedWorkouts: allWorkouts,
            workoutDates: allDates
        )

        if success {
            importedPlanResponse = nil
        }

        return success
    }

    // MARK: - Apply Imported Workouts to Active Plan

    @MainActor
    func applyImportedWorkoutsToActivePlan() async -> Bool {
        guard let response = importedPlanResponse, let plan = vm.activePlan else { return false }
        vm.isGeneratingPlan = true

        for importedWeek in response.weeks {
            let weekWorkouts = vm.allScheduledWorkouts.filter { $0.weekNumber == importedWeek.weekNumber }

            let dayGroups = Dictionary(grouping: importedWeek.days, by: \.dayOfWeek)

            for (dayOfWeek, sessions) in dayGroups {
                let sortedSessions = sessions.sorted { ($0.session ?? 1) < ($1.session ?? 1) }
                let existingForDay = weekWorkouts
                    .filter { $0.dayOfWeek == dayOfWeek }
                    .sorted { $0.session < $1.session }

                let allRest = sortedSessions.allSatisfy { $0.workoutType == "rest" }
                if allRest {
                    if let first = existingForDay.first {
                        await vm.convertToRestDay(first)
                    }
                    continue
                }

                let weeksOut = plan.totalWeeks - importedWeek.weekNumber
                let phase = TrainingPhase.fromWeeksOut(weeksOut, totalWeeks: plan.totalWeeks)
                let racePace = vm.racePaceSecondsPerMile

                for (idx, imported) in sortedSessions.enumerated() {
                    let sessionNum = imported.session ?? (idx + 1)
                    let workoutType = ScheduledWorkoutType.fromImportString(imported.workoutType)

                    if idx < existingForDay.count {
                        // Update existing row
                        var updated = existingForDay[idx]
                        updated.workout = imported.toPlannedWorkout(phase: phase, racePaceSecondsPerMile: racePace)
                        updated.workoutType = workoutType
                        updated.status = .modified
                        await vm.updateWorkout(updated)
                    } else {
                        // Insert new row for additional session
                        guard let scheduled = existingForDay.first else { continue }
                        let insert = ScheduledWorkoutInsert(
                            planId: plan.id,
                            date: scheduled.date,
                            dayOfWeek: dayOfWeek,
                            weekNumber: importedWeek.weekNumber,
                            session: sessionNum,
                            workoutData: imported.toPlannedWorkout(phase: phase, racePaceSecondsPerMile: racePace),
                            workoutType: workoutType
                        )
                        _ = await vm.insertScheduledWorkout(insert)
                    }
                }
            }
        }

        vm.isGeneratingPlan = false
        importedPlanResponse = nil
        return true
    }

    // MARK: - Import Custom Plan (Supabase Persistence)

    @MainActor
    func importCustomPlan(
        name: String,
        startDate: Date,
        endDate: Date,
        targetRaceDistance: String,
        targetTimeSeconds: Int,
        importedWorkouts: [ImportedDayWorkout],
        workoutDates: [Date]
    ) async -> Bool {
        vm.isGeneratingPlan = true
        vm.errorMessage = nil

        let userId = AuthManager.shared.currentUserId ?? ""
        let planId = UUID()
        let now = Date()
        let totalWeeks = max(1, (Calendar.current.dateComponents([.weekOfYear], from: startDate, to: endDate).weekOfYear ?? 0) + 1)

        let createdPlan = TrainingPlan(
            id: planId,
            userId: userId,
            goalId: vm.activeGoal?.id,
            name: name,
            startDate: startDate,
            endDate: endDate,
            targetRaceDistance: targetRaceDistance,
            targetTimeSeconds: targetTimeSeconds,
            status: .active,
            createdAt: now,
            updatedAt: now
        )

        let calendar = Calendar.current
        let startWeekday = calendar.component(.weekday, from: startDate)
        let daysToMonday = (startWeekday == 1) ? 6 : startWeekday - 2
        let planMonday = calendar.date(byAdding: .day, value: -daysToMonday, to: startDate) ?? startDate

        let raceDistanceEnum = RaceDistance.from(legacyString: targetRaceDistance) ?? .marathon
        let racePace = raceDistanceEnum.racePaceSecondsPerMile(goalTimeSeconds: targetTimeSeconds)

        let workoutInserts: [ScheduledWorkoutInsert] = importedWorkouts.enumerated().map { index, imported in
            let workoutDate = index < workoutDates.count ? workoutDates[index] : startDate
            let daysSinceStart = calendar.dateComponents([.day], from: planMonday, to: workoutDate).day ?? 0
            let weekNumber = max(1, (daysSinceStart / 7) + 1)
            let weeksOut = max(0, totalWeeks - weekNumber)
            let phase = TrainingPhase.fromWeeksOut(weeksOut, totalWeeks: totalWeeks)
            let workoutType = ScheduledWorkoutType.fromImportString(imported.workoutType)

            return ScheduledWorkoutInsert(
                planId: planId,
                date: workoutDate,
                dayOfWeek: imported.dayOfWeek,
                weekNumber: weekNumber,
                session: imported.session ?? 1,
                workoutData: workoutType == .rest ? nil : imported.toPlannedWorkout(phase: phase, racePaceSecondsPerMile: racePace),
                workoutType: workoutType,
                notes: nil
            )
        }

        let workouts = workoutInserts.map { insert in
            ScheduledWorkout(
                id: UUID(),
                planId: insert.planId,
                date: insert.date,
                dayOfWeek: insert.dayOfWeek,
                weekNumber: insert.weekNumber,
                session: insert.session,
                workout: insert.workoutData,
                workoutType: insert.workoutType,
                status: .scheduled,
                completedWorkoutId: nil,
                notes: insert.notes,
                createdAt: now,
                updatedAt: now
            )
        }

        if !TrainingPlanViewModel.useLocalMode {
            do {
                try await vm.archiveExistingPlans()

                let planInsert = TrainingPlanInsert(
                    id: planId,
                    userId: userId,
                    goalId: vm.activeGoal?.id,
                    name: name,
                    startDate: startDate,
                    endDate: endDate,
                    targetRaceDistance: targetRaceDistance,
                    targetTimeSeconds: targetTimeSeconds
                )

                Log.coach.info("Importing custom plan to Supabase...")
                try await supabase
                    .from("training_plans")
                    .insert(planInsert)
                    .execute()

                Log.coach.info("Inserting \(workoutInserts.count) imported workouts to Supabase...")
                try await supabase
                    .from("scheduled_workouts")
                    .insert(workoutInserts)
                    .execute()

                Log.coach.info("Successfully imported custom plan")
            } catch {
                Log.coach.error("Supabase error importing custom plan: \(error.localizedDescription)")
                Log.coach.error("Full error: \(String(describing: error))")
                vm.errorMessage = "Failed to save plan: \(error.localizedDescription)"
                vm.isGeneratingPlan = false
                return false
            }
        }

        vm.activePlan = createdPlan
        vm.allScheduledWorkouts = workouts
        vm.marathonGoalTime = targetTimeSeconds
        vm.initializeSelectedWeek()
        vm.initializeSelectedMonth()

        vm.isGeneratingPlan = false
        Log.coach.info("Imported custom plan '\(name)' with \(workouts.count) workouts")
        return true
    }

    // MARK: - Merge Double Sessions

    func mergeDoubleSessions(_ sessions: [ImportedDayWorkout], phase: TrainingPhase, racePaceSecondsPerMile: Double? = nil) -> PlannedWorkout {
        let sorted = sessions.sorted { ($0.session ?? 1) < ($1.session ?? 1) }

        let mergedName = sorted.map(\.name).joined(separator: " + ")
        let mergedDescription = sorted.map(\.description).filter { !$0.isEmpty }.joined(separator: " | ")

        var allSteps: [PlannedWorkoutStep] = []
        for (sessionIndex, session) in sorted.enumerated() {
            let sessionWorkout = session.toPlannedWorkout(phase: phase, racePaceSecondsPerMile: racePaceSecondsPerMile)
            if sessionIndex > 0 {
                allSteps.append(PlannedWorkoutStep(
                    id: UUID(),
                    stepType: .recovery,
                    durationType: .timeSeconds,
                    durationValue: 0,
                    targetPaceIntensity: nil,
                    notes: "--- Session \(sessionIndex + 1) ---",
                    order: allSteps.count
                ))
            }
            for step in sessionWorkout.steps {
                allSteps.append(PlannedWorkoutStep(
                    id: step.id,
                    stepType: step.stepType,
                    durationType: step.durationType,
                    durationValue: step.durationValue,
                    targetPaceIntensity: step.targetPaceIntensity,
                    notes: step.notes,
                    order: allSteps.count
                ))
            }
        }

        let totalMiles = sorted.compactMap(\.totalDistanceMiles).reduce(0, +)
        let totalMinutes = sorted.compactMap(\.estimatedDurationMinutes).reduce(0, +)

        let categoryPriority: [PlannedWorkoutCategory] = [.specific, .special, .fundamental, .regeneration]
        let sessionWorkouts = sorted.map { $0.toPlannedWorkout(phase: phase, racePaceSecondsPerMile: racePaceSecondsPerMile) }
        let category = categoryPriority.first { cat in
            sessionWorkouts.contains { $0.category == cat }
        } ?? .regeneration

        return PlannedWorkout(
            id: UUID(),
            name: mergedName,
            category: category,
            trainingPhase: phase,
            description: mergedDescription,
            steps: allSteps,
            totalDistanceMiles: totalMiles > 0 ? totalMiles : nil,
            estimatedDurationMinutes: totalMinutes > 0 ? totalMinutes : nil,
            signatureType: nil,
            createdAt: Date()
        )
    }
}

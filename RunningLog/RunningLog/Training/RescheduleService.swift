//
//  RescheduleService.swift
//  RunningLog
//
//  AI-powered training plan rescheduling service.
//

import Foundation
import os

// MARK: - Models

enum RescheduleScope: String, CaseIterable {
    case day
    case week
    case remainingPlan = "remaining_plan"

    var displayName: String {
        switch self {
        case .day: return "This Day"
        case .week: return "This Week"
        case .remainingPlan: return "Remaining Plan"
        }
    }

    var icon: String {
        switch self {
        case .day: return "calendar.day.timeline.left"
        case .week: return "calendar.badge.clock"
        case .remainingPlan: return "calendar"
        }
    }
}

enum RescheduleReason: String, CaseIterable {
    case missedDays = "missed_days"
    case injury
    case scheduleConflict = "schedule_conflict"
    case fatigue
    case lifeEvent = "life_event"

    var displayName: String {
        switch self {
        case .missedDays: return "Missed Days"
        case .injury: return "Injury"
        case .scheduleConflict: return "Schedule Conflict"
        case .fatigue: return "Fatigue"
        case .lifeEvent: return "Life Event"
        }
    }

    var icon: String {
        switch self {
        case .missedDays: return "calendar.badge.exclamationmark"
        case .injury: return "bandage.fill"
        case .scheduleConflict: return "clock.badge.xmark"
        case .fatigue: return "zzz"
        case .lifeEvent: return "figure.wave"
        }
    }
}

struct ReschedulePreview {
    var changes: [WorkoutChange]
    let summary: String
    let coachMessage: String

    var approvedCount: Int {
        changes.filter(\.isApproved).count
    }

    struct WorkoutChange: Identifiable {
        let id: UUID
        let date: Date
        let dateString: String
        let dayOfWeek: Int
        let weekNumber: Int
        let before: WorkoutSnapshot
        var after: WorkoutSnapshot
        let notes: String?
        var isApproved: Bool = true
    }

    struct WorkoutSnapshot {
        var workoutType: ScheduledWorkoutType
        var name: String?
        var totalDistanceMiles: Double?
    }
}

// MARK: - RescheduleService

@Observable
final class RescheduleService {
    var isLoading = false
    var preview: ReschedulePreview?
    var errorMessage: String?
    var isApplying = false
    var applyProgress: Int = 0
    var applyTotal: Int = 0

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    // MARK: - Request Reschedule

    @MainActor
    func requestReschedule(
        scope: RescheduleScope,
        reason: String,
        reasonCategory: RescheduleReason,
        plan: TrainingPlan,
        allWorkouts: [ScheduledWorkout],
        targetDate: Date? = nil
    ) async {
        isLoading = true
        errorMessage = nil
        preview = nil

        do {
            let body = buildPayload(
                scope: scope,
                reason: reason,
                reasonCategory: reasonCategory,
                plan: plan,
                allWorkouts: allWorkouts,
                targetDate: targetDate
            )

            let data = try await callEdgeFunction(name: "reschedule-plan", body: body)

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw RescheduleError.invalidResponse
            }

            if let error = json["error"] as? String {
                throw RescheduleError.serverError(error)
            }

            guard let success = json["success"] as? Bool, success,
                  let changes = json["changes"] as? [[String: Any]]
            else {
                errorMessage = json["message"] as? String ?? "No changes suggested."
                isLoading = false
                return
            }

            let summary = json["summary"] as? String ?? ""
            let coachMessage = json["message"] as? String ?? ""

            preview = buildPreview(
                from: changes,
                allWorkouts: allWorkouts,
                summary: summary,
                coachMessage: coachMessage
            )

            isLoading = false
        } catch {
            Log.coach.error("Reschedule failed: \(error)")
            errorMessage = "Failed to generate reschedule. Please try again."
            isLoading = false
        }
    }

    // MARK: - Apply Changes

    @MainActor
    func applyChanges(
        preview: ReschedulePreview,
        allWorkouts: [ScheduledWorkout],
        planService: TrainingPlanService
    ) async -> Bool {
        let approvedChanges = preview.changes.filter(\.isApproved)
        guard !approvedChanges.isEmpty else { return true }

        isApplying = true
        applyProgress = 0
        applyTotal = approvedChanges.count

        for change in approvedChanges {
            guard var workout = allWorkouts.first(where: { $0.id == change.id }) else { continue }

            // Update the workout
            workout.workoutType = change.after.workoutType
            workout.status = .modified

            if change.after.workoutType == .rest {
                workout.workout = nil
            } else if let name = change.after.name {
                // Create minimal PlannedWorkout — the full steps will be built
                // if needed when the user views the workout detail
                workout.workout = PlannedWorkout(
                    id: UUID(),
                    name: name,
                    category: .fundamental,
                    trainingPhase: .support,
                    description: change.notes ?? name,
                    steps: [],
                    totalDistanceMiles: change.after.totalDistanceMiles,
                    estimatedDurationMinutes: nil,
                    signatureType: nil,
                    createdAt: Date()
                )
            }

            // Add reschedule note
            let existingNotes = workout.notes ?? ""
            let rescheduleNote = "[AI Rescheduled] \(change.notes ?? "")"
            workout.notes = existingNotes.isEmpty ? rescheduleNote : "\(existingNotes)\n\(rescheduleNote)"

            await planService.updateWorkout(workout)
            applyProgress += 1
        }

        isApplying = false
        return true
    }

    // MARK: - Build Payload

    private func buildPayload(
        scope: RescheduleScope,
        reason: String,
        reasonCategory: RescheduleReason,
        plan: TrainingPlan,
        allWorkouts: [ScheduledWorkout],
        targetDate: Date?
    ) -> [String: Any] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Filter workouts by scope
        let scopeWorkouts: [ScheduledWorkout]
        switch scope {
        case .day:
            let target = targetDate ?? today
            let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: target))!
            let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart)!
            scopeWorkouts = allWorkouts.filter { $0.date >= weekStart && $0.date < weekEnd }

        case .week:
            let target = targetDate ?? today
            let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: target))!
            let prevWeekStart = calendar.date(byAdding: .day, value: -7, to: weekStart)!
            let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart)!
            scopeWorkouts = allWorkouts.filter { $0.date >= prevWeekStart && $0.date < weekEnd }

        case .remainingPlan:
            scopeWorkouts = allWorkouts.filter { $0.date >= today }
        }

        // Recent history (last 14 days of completed/skipped)
        let twoWeeksAgo = calendar.date(byAdding: .day, value: -14, to: today)!
        let recentHistory = allWorkouts
            .filter { $0.date >= twoWeeksAgo && $0.date < today && ($0.status == .completed || $0.status == .skipped) }
            .map { workout -> [String: Any] in
                [
                    "date": dateFormatter.string(from: workout.date),
                    "workoutType": workout.workoutType.rawValue,
                    "status": workout.status.rawValue,
                    "distanceMiles": workout.workout?.totalDistanceMiles as Any,
                ]
            }

        // Current week number
        let daysSinceStart = calendar.dateComponents([.day], from: plan.startDate, to: today).day ?? 0
        let currentWeek = max(1, (daysSinceStart / 7) + 1)

        let totalWeeks = calendar.dateComponents([.weekOfYear], from: plan.startDate, to: plan.endDate).weekOfYear ?? 16

        let planPayload: [String: Any] = [
            "name": plan.name,
            "targetRaceDistance": plan.targetRaceDistance,
            "targetTimeSeconds": plan.targetTimeSeconds,
            "startDate": dateFormatter.string(from: plan.startDate),
            "endDate": dateFormatter.string(from: plan.endDate),
            "totalWeeks": totalWeeks,
            "currentWeek": currentWeek,
        ]

        let workoutsPayload = scopeWorkouts.map { workout -> [String: Any] in
            [
                "id": workout.id.uuidString,
                "date": dateFormatter.string(from: workout.date),
                "dayOfWeek": workout.dayOfWeek,
                "weekNumber": workout.weekNumber,
                "workoutType": workout.workoutType.rawValue,
                "workoutName": workout.workout?.name as Any,
                "workoutDescription": workout.workout?.description as Any,
                "totalDistanceMiles": workout.workout?.totalDistanceMiles as Any,
                "status": workout.status.rawValue,
            ]
        }

        return [
            "scope": scope.rawValue,
            "reason": reason,
            "reasonCategory": reasonCategory.rawValue,
            "plan": planPayload,
            "workouts": workoutsPayload,
            "recentHistory": recentHistory,
        ]
    }

    // MARK: - Build Preview

    private func buildPreview(
        from changes: [[String: Any]],
        allWorkouts: [ScheduledWorkout],
        summary: String,
        coachMessage: String
    ) -> ReschedulePreview {
        var workoutChanges: [ReschedulePreview.WorkoutChange] = []

        for change in changes {
            guard let dateStr = change["date"] as? String,
                  let date = dateFormatter.date(from: dateStr),
                  let workoutTypeStr = change["workoutType"] as? String
            else { continue }

            let dayOfWeek = change["dayOfWeek"] as? Int ?? 0
            let weekNumber = change["weekNumber"] as? Int ?? 0
            let workoutCode = change["workoutCode"] as? String
            let totalMiles = change["totalDistanceMiles"] as? Double
            let notes = change["notes"] as? String
            let newType = ScheduledWorkoutType(rawValue: workoutTypeStr) ?? .easy

            // Find the existing workout for this date
            let calendar = Calendar.current
            let existingWorkout = allWorkouts.first { calendar.isDate($0.date, inSameDayAs: date) }

            let before = ReschedulePreview.WorkoutSnapshot(
                workoutType: existingWorkout?.workoutType ?? .rest,
                name: existingWorkout?.workout?.name,
                totalDistanceMiles: existingWorkout?.workout?.totalDistanceMiles
            )

            // Determine workout name from code or type
            let afterName: String?
            if let code = workoutCode, code != "REST", code != "EASY" {
                afterName = code
            } else {
                afterName = newType.displayName
            }

            let after = ReschedulePreview.WorkoutSnapshot(
                workoutType: newType,
                name: afterName,
                totalDistanceMiles: totalMiles
            )

            let changeId = existingWorkout?.id ?? UUID()

            workoutChanges.append(ReschedulePreview.WorkoutChange(
                id: changeId,
                date: date,
                dateString: dateStr,
                dayOfWeek: dayOfWeek,
                weekNumber: weekNumber,
                before: before,
                after: after,
                notes: notes
            ))
        }

        // Sort by date
        workoutChanges.sort { $0.date < $1.date }

        return ReschedulePreview(
            changes: workoutChanges,
            summary: summary,
            coachMessage: coachMessage
        )
    }
}

// MARK: - Errors

enum RescheduleError: LocalizedError {
    case invalidResponse
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid response from server"
        case .serverError(let msg): return msg
        }
    }
}

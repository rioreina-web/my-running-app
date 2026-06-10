//
//  PlanAdaptationService.swift
//  RunningLog
//
//  Mutates scheduled_workouts based on coaching decisions. This is where the
//  plan stops being a static prescription and actually reacts to what's
//  happening — when the athlete accepts a "soften next week" note, the
//  easy days literally shrink; when they accept "swap Tuesday's tempo to
//  Thursday", the workout moves.
//

import Foundation
import PostgREST
import Supabase

@Observable
final class PlanAdaptationService {
    var isApplying = false
    var lastAppliedSummary: String?
    var lastError: String?

    // MARK: - Soften Week

    /// Drop easy-day volume by a percentage across the next upcoming week that
    /// hasn't started yet. Quality sessions are left alone — that's the point
    /// of the week. Returns a human-readable summary of what changed.
    @MainActor
    @discardableResult
    func softenUpcomingWeek(
        planId: UUID,
        reductionPct: Double = 0.2
    ) async -> String? {
        isApplying = true
        lastError = nil
        defer { isApplying = false }

        // 1. Find the next upcoming week (Monday-based, starts today or later)
        let (weekStart, weekEnd) = nextWeekBounds()
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM-dd"

        do {
            let workouts: [ScheduledWorkout] = try await supabase
                .from("scheduled_workouts")
                .select()
                .eq("plan_id", value: planId.uuidString)
                .gte("date", value: dateFmt.string(from: weekStart))
                .lte("date", value: dateFmt.string(from: weekEnd))
                .execute()
                .value

            let easyTypes: Set<ScheduledWorkoutType> = [.easy, .recovery, .strides]
            let easyDays = workouts.filter { easyTypes.contains($0.workoutType) }

            guard !easyDays.isEmpty else {
                let summary = "Nothing to soften this week — all quality/rest days."
                lastAppliedSummary = summary
                return summary
            }

            var totalBefore: Double = 0
            var totalAfter: Double = 0

            for workout in easyDays {
                guard let planned = workout.workout else { continue }
                let beforeMi = planned.totalDistanceMiles ?? 0
                guard beforeMi > 0.5 else { continue }

                let afterMi = (beforeMi * (1 - reductionPct)).rounded(to: 1)
                totalBefore += beforeMi
                totalAfter += afterMi

                // PlannedWorkout properties are mostly `let`, so rebuild it
                let newDescription = planned.description.isEmpty
                    ? "Adapted: reduced for recovery"
                    : "\(planned.description) (adapted: reduced for recovery)"
                let updated = PlannedWorkout(
                    id: planned.id,
                    name: planned.name,
                    category: planned.category,
                    trainingPhase: planned.trainingPhase,
                    description: newDescription,
                    steps: planned.steps,
                    totalDistanceMiles: afterMi,
                    estimatedDurationMinutes: planned.estimatedDurationMinutes,
                    signatureType: planned.signatureType,
                    createdAt: planned.createdAt
                )

                var newWorkout = workout
                newWorkout.workout = updated
                newWorkout.status = .modified

                await TrainingPlanService().updateWorkout(newWorkout)
            }

            let summary = String(format: "Reduced next week's easy volume from %.1f mi to %.1f mi (−%.0f%%).",
                                 totalBefore, totalAfter, reductionPct * 100)
            lastAppliedSummary = summary
            return summary
        } catch {
            print("[PlanAdaptation] softenUpcomingWeek failed: \(error)")
            lastError = "Couldn't adjust next week's plan. \(error.localizedDescription)"
            return nil
        }
    }

    // MARK: - Swap Quality Session

    /// Move a quality session from its current date to a target date. Typically
    /// used for heat warnings ("move Thursday's tempo to Wednesday, cooler").
    @MainActor
    @discardableResult
    func swapWorkoutToDay(
        workoutId: UUID,
        toDate: Date
    ) async -> String? {
        isApplying = true
        lastError = nil
        defer { isApplying = false }

        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM-dd"

        do {
            struct DateUpdate: Encodable {
                let date: String
                let status: String
            }
            let update = DateUpdate(
                date: dateFmt.string(from: toDate),
                status: "modified"
            )

            try await supabase
                .from("scheduled_workouts")
                .update(update)
                .eq("id", value: workoutId.uuidString)
                .execute()

            let out = DateFormatter()
            out.dateFormat = "EEEE, MMM d"
            let summary = "Moved to \(out.string(from: toDate))."
            lastAppliedSummary = summary
            return summary
        } catch {
            print("[PlanAdaptation] swapWorkoutToDay failed: \(error)")
            lastError = "Couldn't move the workout. \(error.localizedDescription)"
            return nil
        }
    }

    // MARK: - Mark Adjustment Applied

    /// After successfully applying an adjustment, mark it as followed=true
    /// so it doesn't surface again in the Coach's Read.
    @MainActor
    func markAdjustmentApplied(_ adjustmentId: UUID) async {
        do {
            struct FollowedUpdate: Encodable {
                let followed: Bool
                let resolved_at: String
            }
            let update = FollowedUpdate(
                followed: true,
                resolved_at: ISO8601DateFormatter().string(from: Date())
            )
            try await supabase
                .from("coaching_adjustments")
                .update(update)
                .eq("id", value: adjustmentId.uuidString)
                .execute()
        } catch {
            print("[PlanAdaptation] markAdjustmentApplied failed: \(error)")
        }
    }

    /// Inverse: mark as dismissed (followed=false). Keeps a record that the
    /// athlete declined so future coaching can avoid repeating the same
    /// suggestion.
    @MainActor
    func markAdjustmentDismissed(_ adjustmentId: UUID) async {
        do {
            struct DismissUpdate: Encodable {
                let followed: Bool
                let resolved_at: String
            }
            let update = DismissUpdate(
                followed: false,
                resolved_at: ISO8601DateFormatter().string(from: Date())
            )
            try await supabase
                .from("coaching_adjustments")
                .update(update)
                .eq("id", value: adjustmentId.uuidString)
                .execute()
        } catch {
            print("[PlanAdaptation] markAdjustmentDismissed failed: \(error)")
        }
    }

    // MARK: - Missed Workout Detection

    struct MissedWorkout: Identifiable {
        let id: UUID
        let date: Date
        let name: String
        let workoutType: ScheduledWorkoutType
        let daysLate: Int
    }

    /// Fetch workouts whose date has passed but status is still 'scheduled'
    /// (never completed, never explicitly skipped). Limited to the last 7 days
    /// so we don't surface ancient misses.
    @MainActor
    func fetchMissedWorkouts(planId: UUID) async -> [MissedWorkout] {
        let today = Calendar.current.startOfDay(for: Date())
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: today) ?? today
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM-dd"

        do {
            let workouts: [ScheduledWorkout] = try await supabase
                .from("scheduled_workouts")
                .select()
                .eq("plan_id", value: planId.uuidString)
                .eq("status", value: "scheduled")
                .gte("date", value: dateFmt.string(from: sevenDaysAgo))
                .lt("date", value: dateFmt.string(from: today))
                .neq("workout_type", value: "rest")
                .order("date", ascending: false)
                .execute()
                .value

            return workouts.map { w in
                let days = Calendar.current.dateComponents([.day], from: w.date, to: today).day ?? 0
                return MissedWorkout(
                    id: w.id,
                    date: w.date,
                    name: w.workout?.name ?? w.workoutType.displayName,
                    workoutType: w.workoutType,
                    daysLate: days
                )
            }
        } catch {
            print("[PlanAdaptation] fetchMissedWorkouts failed: \(error)")
            return []
        }
    }

    // MARK: - Helpers

    /// The Monday 00:00 through Sunday 23:59 of the upcoming week (or this
    /// week if today is Monday).
    private func nextWeekBounds() -> (start: Date, end: Date) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let weekday = cal.component(.weekday, from: today)   // 1=Sun..7=Sat
        // Days until next Monday: 1→1 (Sun), 2→7 (Mon: start today's week next week)
        // Actually we want the next upcoming Monday OR today if today is Monday
        let daysUntilMonday: Int = {
            if weekday == 2 { return 0 }           // Monday — use today
            if weekday == 1 { return 1 }           // Sunday — tomorrow
            return 9 - weekday                      // Tue..Sat → next Monday
        }()
        let start = cal.date(byAdding: .day, value: daysUntilMonday, to: today) ?? today
        let end = cal.date(byAdding: .day, value: 6, to: start) ?? start
        return (start, end)
    }
}

private extension Double {
    func rounded(to places: Int) -> Double {
        let mult = pow(10.0, Double(places))
        return (self * mult).rounded() / mult
    }
}

//
//  TrainingPlanService.swift
//  RunningLog
//
//  Data service for training plan CRUD and fetching.
//

import CoreLocation
import Foundation
import os
import Supabase

// MARK: - TrainingPlanService

@Observable
final class TrainingPlanService {
    // MARK: - Data State

    var activePlan: TrainingPlan?
    var allScheduledWorkouts: [ScheduledWorkout] = []
    var moodByDate: [String: String] = [:]
    var logDistanceByDate: [String: Double] = [:]

    // Goal data
    var activeGoal: UserGoal?
    var marathonGoalTime: Int?
    var weeksUntilRace: Int = 0

    // Pace / phase configuration (UserDefaults-backed, per plan)
    private(set) var paceConfig = PaceConfigManager()

    // Loading states
    var isLoadingPlan = false
    var isGeneratingPlan = false
    var isSaving = false
    var errorMessage: String?
    var showError = false
    /// Last error from `refreshForecastForWorkout`. The HeatCalculatorCard
    /// reads this to render specific failure states ("Location needed",
    /// "Forecast service unavailable") rather than a vague placeholder.
    var lastForecastFetchError: String?

    /// Set to true to use local-only mode (no Supabase)
    static var useLocalMode = false

    @ObservationIgnored private let moodDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    // MARK: - Computed Properties

    var racePaceSecondsPerMile: Double? {
        if let plan = activePlan {
            return plan.racePaceSecondsPerMile
        }
        if let goalTime = marathonGoalTime, goalTime > 0 {
            return Double(goalTime) / 26.2188
        }
        if let snapMarathon = fitnessSnapshotMarathonSeconds, snapMarathon > 0 {
            return Double(snapMarathon) / 26.2188
        }
        return nil
    }

    /// Fitness snapshot fallback: predicted marathon seconds from most recent snapshot
    var fitnessSnapshotMarathonSeconds: Int?

    var equivalentPaces: EquivalentPaces? {
        if let plan = activePlan {
            return EquivalentPaces(
                raceDistance: plan.raceDistance,
                goalTimeSeconds: plan.targetTimeSeconds,
                disabledPaces: paceConfig.disabledPaces,
                paceOverrides: paceConfig.paceOverrides
            )
        }
        // Fallback: use marathon goal time from user_goals or fitness snapshot
        if let goalTime = marathonGoalTime, goalTime > 0 {
            return EquivalentPaces(
                raceDistance: .marathon,
                goalTimeSeconds: goalTime,
                disabledPaces: paceConfig.disabledPaces,
                paceOverrides: paceConfig.paceOverrides
            )
        }
        if let snapMarathon = fitnessSnapshotMarathonSeconds, snapMarathon > 0 {
            return EquivalentPaces(
                raceDistance: .marathon,
                goalTimeSeconds: snapMarathon,
                disabledPaces: paceConfig.disabledPaces,
                paceOverrides: paceConfig.paceOverrides
            )
        }
        return nil
    }

    // MARK: - Load Plan

    @MainActor
    func loadActivePlan(then initializeUI: @MainActor () -> Void) async {
        guard !isLoadingPlan else { return }
        isLoadingPlan = true
        errorMessage = nil

        await loadActiveGoal()

        guard !Self.useLocalMode else {
            isLoadingPlan = false
            return
        }

        let debugUid = AuthManager.shared.userId
        Log.coach.info("loadActivePlan: auth uid=\(debugUid)")

        // 1. Raw fetch (debug): how many rows does RLS expose for this user?
        do {
            struct Row: Codable { let id: UUID; let user_id: String; let status: String; let name: String }
            let rows: [Row] = try await supabase
                .from("training_plans")
                .select("id,user_id,status,name")
                .execute()
                .value
            Log.coach.info("loadActivePlan: RLS sees \(rows.count) rows; active=\(rows.filter{$0.status=="active"}.count); user_ids=\(rows.map{$0.user_id}.joined(separator: ","))")
        } catch {
            Log.coach.info("loadActivePlan: debug fetch failed: \(error.localizedDescription)")
            errorMessage = "Debug fetch failed: \(error.localizedDescription)"
        }

        do {
            let plans: [TrainingPlan] = try await supabase
                .from("training_plans")
                .select()
                .eq("status", value: "active")
                .order("created_at", ascending: false)
                .limit(1)
                .execute()
                .value

            Log.coach.info("loadActivePlan: decoded \(plans.count) plans")

            if let plan = plans.first {
                activePlan = plan
                paceConfig.configure(for: plan)
                await loadScheduledWorkouts(for: plan.id)
                await loadMoodData(startDate: plan.startDate, endDate: plan.endDate)
                initializeUI()
            } else {
                errorMessage = "No active training_plans row for uid \(debugUid)"
                await loadFitnessSnapshotFallback()
                isLoadingPlan = false
            }

            isLoadingPlan = false
        } catch {
            Log.coach.error("loadActivePlan: decode/query failed: \(error)")
            errorMessage = "Plan load failed: \(error.localizedDescription)"
            await loadFitnessSnapshotFallback()
            isLoadingPlan = false
        }
    }

    /// Load the most recent fitness snapshot to provide pace zone data when no training plan exists
    @MainActor
    private func loadFitnessSnapshotFallback() async {
        guard fitnessSnapshotMarathonSeconds == nil else { return }
        do {
            struct SnapRow: Codable {
                let predictedMarathonSeconds: Int
                enum CodingKeys: String, CodingKey {
                    case predictedMarathonSeconds = "predicted_marathon_seconds"
                }
            }
            let rows: [SnapRow] = try await supabase
                .from("fitness_snapshots")
                .select("predicted_marathon_seconds")
                .order("created_at", ascending: false)
                .limit(1)
                .execute()
                .value
            if let snap = rows.first, snap.predictedMarathonSeconds > 0 {
                fitnessSnapshotMarathonSeconds = snap.predictedMarathonSeconds
                Log.coach.info("Loaded fitness snapshot fallback: marathon \(snap.predictedMarathonSeconds)s")
            }
        } catch {
            Log.coach.info("Could not load fitness snapshot fallback: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func loadActiveGoal() async {
        guard !Self.useLocalMode else { return }

        do {
            let response: [UserGoal] = try await supabase
                .from("user_goals")
                .select()
                .eq("status", value: "active")
                .order("target_date", ascending: true)
                .limit(1)
                .execute()
                .value

            if let goal = response.first {
                activeGoal = goal
                parseGoalTime(from: goal.goalTitle)
                calculateWeeksUntilRace(for: goal)
            }
        } catch {
            Log.coach.info("Could not load goal from Supabase: \(error.localizedDescription)")
            ErrorReporter.shared.report(error, context: "load active goal")
        }
    }

    /// Reload scheduled workouts for the active plan.
    @MainActor
    func loadScheduledWorkouts() async {
        guard let planId = activePlan?.id else { return }
        await loadScheduledWorkouts(for: planId)
    }

    private func loadScheduledWorkouts(for planId: UUID) async {
        do {
            let workouts: [ScheduledWorkout] = try await supabase
                .from("scheduled_workouts")
                .select()
                .eq("plan_id", value: planId.uuidString)
                .order("date", ascending: true)
                .limit(200)
                .execute()
                .value

            allScheduledWorkouts = workouts
            print("[ScheduledWorkouts] Loaded \(workouts.count) workouts for plan \(planId.uuidString.prefix(8))")
        } catch {
            print("[ScheduledWorkouts] ERROR: \(error)")
            Log.coach.error("Failed to load workouts: \(error)")
            ErrorReporter.shared.report(error, context: "load scheduled workouts")
        }
    }

    @MainActor
    func loadMoodData(startDate: Date, endDate: Date) async {
        guard !Self.useLocalMode else { return }

        let calendar = Calendar.current
        let bufferStart = calendar.date(byAdding: .day, value: -7, to: startDate) ?? startDate
        let bufferEnd = calendar.date(byAdding: .day, value: 7, to: endDate) ?? endDate

        let logUserId = AuthManager.shared.userId
        async let logsFetch: [TrainingLog] = {
            let iso = ISO8601DateFormatter()
            return (try? await supabase
                .from("training_logs")
                .select()
                .eq("user_id", value: logUserId)
                .not("workout_date", operator: .is, value: "null")
                .gte("workout_date", value: iso.string(from: bufferStart))
                .lte("workout_date", value: iso.string(from: bufferEnd))
                .order("workout_date", ascending: false, nullsFirst: false)
                .limit(500)
                .execute()
                .value) ?? []
        }()

        async let hkMilesFetch = VitalManager.shared.fetchRunningMilesByDate(
            from: bufferStart, to: bufferEnd
        )

        let logs = await logsFetch
        let hkMilesByDate = await hkMilesFetch

        var moodLookup: [String: String] = [:]
        var moodDistLookup: [String: Double] = [:]
        var logDistLookup: [String: Double] = [:]
        for log in logs {
            guard let date = log.workoutDate else { continue }
            let key = moodDateFormatter.string(from: date)
            if let mood = log.mood {
                let logDist = log.workoutDistanceMiles ?? 0
                if moodLookup[key] == nil || logDist > (moodDistLookup[key] ?? 0) {
                    moodLookup[key] = mood
                    moodDistLookup[key] = logDist
                }
            }
            if let miles = log.workoutDistanceMiles, miles > 0 {
                logDistLookup[key, default: 0] += miles
            }
        }

        var mergedDist: [String: Double] = [:]
        let allKeys = Set(logDistLookup.keys).union(hkMilesByDate.keys)
        for key in allKeys {
            mergedDist[key] = max(logDistLookup[key] ?? 0, hkMilesByDate[key] ?? 0)
        }

        moodByDate = moodLookup
        logDistanceByDate = mergedDist
    }

    @MainActor
    func loadMoodDataForMonth(year: Int, month: Int) async {
        let cal = Calendar.current
        guard let start = cal.date(from: DateComponents(year: year, month: month, day: 1)),
              let end = cal.date(byAdding: .month, value: 1, to: start)
        else { return }
        await loadMoodData(startDate: start, endDate: end)
    }

    @MainActor
    func loadLogEntries(for date: Date) async -> [TrainingLog] {
        guard !Self.useLocalMode else { return [] }
        let iso = ISO8601DateFormatter()
        let dayStart = Calendar.current.startOfDay(for: date)
        guard let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) else { return [] }
        do {
            let userId = AuthManager.shared.userId
            let entries: [TrainingLog] = try await supabase
                .from("training_logs")
                .select()
                .eq("user_id", value: userId)
                .gte("workout_date", value: iso.string(from: dayStart))
                .lt("workout_date", value: iso.string(from: dayEnd))
                .order("workout_date", ascending: false, nullsFirst: false)
                .limit(20)
                .execute()
                .value
            return entries
        } catch {
            Log.coach.info("Could not load log entries: \(error.localizedDescription)")
            ErrorReporter.shared.report(error, context: "load log entries for date")
            return []
        }
    }

    // MARK: - Mood / Distance Lookups

    func moodForDate(_ date: Date) -> String? {
        moodByDate[moodDateFormatter.string(from: date)]
    }

    func moodForDay(_ day: Int, year: Int, month: Int) -> String? {
        guard let date = Calendar.current.date(from: DateComponents(
            year: year, month: month, day: day
        )) else { return nil }
        return moodByDate[moodDateFormatter.string(from: date)]
    }

    func logDistanceForDay(_ day: Int, year: Int, month: Int) -> Double? {
        guard let date = Calendar.current.date(from: DateComponents(
            year: year, month: month, day: day
        )) else { return nil }
        return logDistanceByDate[moodDateFormatter.string(from: date)]
    }

    func workoutForDay(_ day: Int, year: Int, month: Int) -> ScheduledWorkout? {
        let calendar = Calendar.current
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else {
            return nil
        }
        return allScheduledWorkouts.first { calendar.isDate($0.date, inSameDayAs: date) }
    }

    // MARK: - Shared Helpers

    func archiveExistingPlans() async throws {
        try await supabase
            .from("training_plans")
            .update(["status": "archived"])
            .eq("status", value: "active")
            .execute()
    }

    // MARK: - CRUD Operations

    @MainActor
    func updateWorkout(_ workout: ScheduledWorkout) async {
        isSaving = true
        do {
            let updateData = ScheduledWorkoutUpdate(
                workoutData: workout.workout,
                workoutType: workout.workoutType,
                status: workout.status,
                notes: workout.notes
            )

            try await supabase
                .from("scheduled_workouts")
                .update(updateData)
                .eq("id", value: workout.id.uuidString)
                .execute()

            if let index = allScheduledWorkouts.firstIndex(where: { $0.id == workout.id }) {
                allScheduledWorkouts[index] = workout
            }
            isSaving = false
        } catch {
            Log.coach.error("Failed to update workout: \(error)")
            ErrorReporter.shared.report(error, context: "update scheduled workout")
            isSaving = false
            errorMessage = "Failed to save changes"
            showError = true
        }
    }

    /// Update a single workout's `scheduled_hour` (0-23) and re-fetch
    /// its weather forecast for the new hour. Two writes:
    ///   1. UPDATE scheduled_workouts SET scheduled_hour = ?
    ///   2. POST fetch-workout-weather { kind: "refresh_one", workout_id }
    /// On success, the local `allScheduledWorkouts` cache gets the new
    /// scheduled_hour AND the refreshed weather_forecast.
    @MainActor
    func updateScheduledTime(workoutId: UUID, scheduledHour: Int?) async {
        do {
            // Custom encoder — Optional<Int> with the default Encodable
            // conformance OMITS the key when nil, which produces an empty
            // PATCH body and silently no-ops the clear path. Encoding
            // explicitly lets us write SQL NULL when clearing.
            struct TimeUpdate: Encodable {
                let scheduledHour: Int?
                enum CodingKeys: String, CodingKey { case scheduledHour = "scheduled_hour" }
                func encode(to encoder: Encoder) throws {
                    var c = encoder.container(keyedBy: CodingKeys.self)
                    if let h = scheduledHour {
                        try c.encode(h, forKey: .scheduledHour)
                    } else {
                        try c.encodeNil(forKey: .scheduledHour)
                    }
                }
            }
            let payload = TimeUpdate(scheduledHour: scheduledHour)

            // `.select()` flips the request from `Prefer: return=minimal`
            // to `return=representation`, so the UPDATE returns the row(s)
            // it actually touched. RLS denials produce a zero-row response
            // (not an HTTP error), so we surface that case ourselves.
            let updated: [ScheduledWorkout] = try await supabase
                .from("scheduled_workouts")
                .update(payload)
                .eq("id", value: workoutId.uuidString)
                .select()
                .execute()
                .value

            guard !updated.isEmpty else {
                Log.coach.error("updateScheduledTime: 0 rows affected — RLS or wrong workout id")
                errorMessage = "Couldn't save the run time"
                showError = true
                return
            }
            Log.coach.info("scheduled_hour set to \(scheduledHour ?? -1) on \(workoutId)")

            // Step 2: refresh the weather forecast for the new hour.
            // Pulled out into a separate helper so the calculator card can
            // also call it directly (manual "Refresh forecast" button +
            // auto-retry when the card appears with no forecast).
            await refreshForecastForWorkout(workoutId: workoutId)

            // Update local cache so the UI reflects scheduled_hour even
            // if the weather fetch failed. (The forecast field is updated
            // inside refreshForecastForWorkout.)
            if let index = allScheduledWorkouts.firstIndex(where: { $0.id == workoutId }) {
                allScheduledWorkouts[index].scheduledHour = scheduledHour
            }
        } catch {
            Log.coach.error("Failed to update scheduled_hour: \(error)")
            ErrorReporter.shared.report(error, context: "update scheduled time")
            errorMessage = "Couldn't save the run time"
            showError = true
        }
    }

    /// Re-fetch the weather forecast for one workout by calling
    /// fetch-workout-weather { kind: "refresh_one" }. Updates the local
    /// `allScheduledWorkouts` cache in place. Surfaces specific failure
    /// modes via `lastForecastFetchError` so the calculator card can show
    /// "Location needed" instead of silently failing.
    @MainActor
    func refreshForecastForWorkout(workoutId: UUID) async {
        lastForecastFetchError = nil
        let coord = await LocationProvider.shared.currentCoordinate()

        // Short-circuit when CoreLocation didn't return a fix: either the
        // athlete hasn't granted permission yet (first tap kicks off the
        // prompt asynchronously), or it's denied/restricted at the system
        // level. Either way, calling the edge fn without lat/lon would
        // return a 400 that supabase-swift surfaces as a confusing
        // "couldn't reach forecast service" — say what's actually wrong.
        guard let coord else {
            let status = LocationProvider.shared.authorizationStatus()
            switch status {
            case .denied, .restricted:
                lastForecastFetchError = "Location access is off. Enable it in Settings → Privacy → Location."
            case .notDetermined:
                lastForecastFetchError = "Tap Allow on the location prompt, then try again."
            default:
                lastForecastFetchError = "Couldn't get your location yet — try again in a moment."
            }
            Log.coach.error("Weather refresh skipped: no location fix (status=\(status.rawValue))")
            return
        }

        struct RefreshArgs: Encodable {
            let workout_id: String
            let kind: String
            let lat: Double?
            let lon: Double?
        }
        struct RefreshResponse: Decodable {
            let weather: WorkoutForecast?
            let error: String?
        }

        do {
            let response: RefreshResponse = try await supabase.functions.invoke(
                "fetch-workout-weather",
                options: FunctionInvokeOptions(
                    body: RefreshArgs(
                        workout_id: workoutId.uuidString,
                        kind: "refresh_one",
                        lat: coord.latitude,
                        lon: coord.longitude
                    )
                )
            )

            if let serverError = response.error {
                lastForecastFetchError = serverError
                Log.coach.error("Weather refresh server error: \(serverError)")
                return
            }

            if let fresh = response.weather,
               let index = allScheduledWorkouts.firstIndex(where: { $0.id == workoutId }) {
                allScheduledWorkouts[index].weatherForecast = fresh
                Log.coach.info("Forecast refreshed for \(workoutId): \(Int(fresh.temperatureF))°F")
            } else {
                lastForecastFetchError = "Forecast not available for this date."
            }
        } catch {
            lastForecastFetchError = "Couldn't reach forecast service: \(error.localizedDescription)"
            Log.coach.error("Weather refresh failed: \(error)")
        }
    }

    @MainActor
    func insertScheduledWorkout(_ insert: ScheduledWorkoutInsert) async -> ScheduledWorkout? {
        let now = Date()
        let workout = ScheduledWorkout(
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

        if !Self.useLocalMode {
            do {
                try await supabase
                    .from("scheduled_workouts")
                    .insert(insert)
                    .execute()
            } catch {
                Log.coach.error("Failed to insert workout: \(error)")
                ErrorReporter.shared.report(error, context: "insert scheduled workout")
                return nil
            }
        }

        allScheduledWorkouts.append(workout)
        return workout
    }

    @MainActor
    func markWorkoutComplete(_ workout: ScheduledWorkout, linkedWorkoutId: UUID? = nil) async {
        var updated = workout
        updated.status = .completed
        updated.completedWorkoutId = linkedWorkoutId
        await updateWorkout(updated)
    }

    @MainActor
    func markWorkoutSkipped(_ workout: ScheduledWorkout) async {
        var updated = workout
        updated.status = .skipped
        await updateWorkout(updated)
    }

    @MainActor
    func swapWorkouts(_ workout1: ScheduledWorkout, with workout2: ScheduledWorkout) async {
        isSaving = true

        var updated1 = workout1
        var updated2 = workout2

        let tempWorkout = updated1.workout
        let tempType = updated1.workoutType

        updated1.workout = updated2.workout
        updated1.workoutType = updated2.workoutType
        updated1.status = .modified

        updated2.workout = tempWorkout
        updated2.workoutType = tempType
        updated2.status = .modified

        await updateWorkout(updated1)
        await updateWorkout(updated2)

        isSaving = false
    }

    @MainActor
    func convertToRestDay(_ workout: ScheduledWorkout) async {
        var updated = workout
        updated.workout = nil
        updated.workoutType = .rest
        updated.status = .modified
        await updateWorkout(updated)
    }

    @MainActor
    func addWorkoutToRestDay(_ restDay: ScheduledWorkout, workoutType: ScheduledWorkoutType, phase: TrainingPhase) async {
        guard restDay.isRestDay else { return }

        var updated = restDay
        updated.workoutType = workoutType
        updated.workout = PlannedWorkout(
            id: UUID(),
            name: workoutType.displayName,
            category: .fundamental,
            trainingPhase: phase,
            description: workoutType.displayName,
            steps: [],
            totalDistanceMiles: nil,
            estimatedDurationMinutes: nil,
            signatureType: nil,
            createdAt: Date()
        )
        updated.status = .modified
        await updateWorkout(updated)
    }

    @MainActor
    func deletePlan() async {
        guard let plan = activePlan else { return }

        do {
            try await supabase
                .from("training_plans")
                .delete()
                .eq("id", value: plan.id.uuidString)
                .execute()

            activePlan = nil
            allScheduledWorkouts = []
        } catch {
            Log.coach.error("Failed to delete plan: \(error)")
            ErrorReporter.shared.report(error, context: "delete training plan")
            errorMessage = "Failed to delete plan"
            showError = true
        }
    }

    // MARK: - Private Helpers

    private func parseGoalTime(from title: String) {
        let patterns = [
            #"(\d{1,2}):(\d{2}):(\d{2})"#,
            #"(\d{1,2}):(\d{2})"#,
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title))
            {
                if match.numberOfRanges == 4 {
                    if let hoursRange = Range(match.range(at: 1), in: title),
                       let minsRange = Range(match.range(at: 2), in: title),
                       let secsRange = Range(match.range(at: 3), in: title),
                       let hours = Int(title[hoursRange]),
                       let mins = Int(title[minsRange]),
                       let secs = Int(title[secsRange])
                    {
                        marathonGoalTime = hours * 3600 + mins * 60 + secs
                        return
                    }
                } else {
                    if let hoursRange = Range(match.range(at: 1), in: title),
                       let minsRange = Range(match.range(at: 2), in: title),
                       let hours = Int(title[hoursRange]),
                       let mins = Int(title[minsRange])
                    {
                        marathonGoalTime = hours * 3600 + mins * 60
                        return
                    }
                }
            }
        }
    }

    private func calculateWeeksUntilRace(for goal: UserGoal) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let targetDate = calendar.startOfDay(for: goal.targetDate)
        let weeks = calendar.dateComponents([.weekOfYear], from: today, to: targetDate).weekOfYear ?? 0
        weeksUntilRace = max(0, weeks)
    }
}

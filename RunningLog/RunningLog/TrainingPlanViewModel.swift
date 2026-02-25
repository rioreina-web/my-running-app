//
//  TrainingPlanViewModel.swift
//  RunningLog
//
//  View model for training plan calendar management.
//

import Foundation
import os
import Supabase
import SwiftUI

// MARK: - TrainingPlanViewModel

@Observable
final class TrainingPlanViewModel {
    // MARK: - State

    var activePlan: TrainingPlan?
    var allScheduledWorkouts: [ScheduledWorkout] = []

    // Navigation state
    var selectedWeek: Int = 1
    var selectedMonth: Int = Calendar.current.component(.month, from: Date())
    var selectedYear: Int = Calendar.current.component(.year, from: Date())
    var selectedDate: Date?

    // Goal data
    var activeGoal: UserGoal?
    var marathonGoalTime: Int?
    var weeksUntilRace: Int = 0

    // Loading states
    var isLoadingPlan = false
    var isGeneratingPlan = false
    var isSaving = false
    var errorMessage: String?
    var showError = false

    // Import week state
    var importedWorkouts: [ImportedDayWorkout]?
    var isParsingImport = false
    var importError: String?

    // MARK: - Computed Properties

    var racePaceSecondsPerMile: Double? {
        guard let plan = activePlan else {
            guard let goalTime = marathonGoalTime else { return nil }
            return Double(goalTime) / 26.2188
        }
        return plan.racePaceSecondsPerMile
    }

    var equivalentPaces: EquivalentPaces? {
        guard let plan = activePlan else { return nil }
        return EquivalentPaces(
            raceDistance: plan.raceDistance,
            goalTimeSeconds: plan.targetTimeSeconds,
            disabledPaces: disabledPaces
        )
    }

    /// Named paces disabled for the active plan (persisted per plan ID)
    var disabledPaces: Set<NamedPace> {
        get {
            guard let plan = activePlan else { return [] }
            let key = "disabledPaces_\(plan.id.uuidString)"
            guard let raw = UserDefaults.standard.stringArray(forKey: key) else { return [] }
            return Set(raw.compactMap { NamedPace(rawValue: $0) })
        }
        set {
            guard let plan = activePlan else { return }
            let key = "disabledPaces_\(plan.id.uuidString)"
            UserDefaults.standard.set(newValue.map(\.rawValue), forKey: key)
        }
    }

    var currentPhase: CanovaTrainingPhase {
        guard let plan = activePlan else {
            return CanovaTrainingPhase.fromWeeksOut(weeksUntilRace)
        }
        let weeksOut = plan.totalWeeks - selectedWeek
        return CanovaTrainingPhase.fromWeeksOut(weeksOut)
    }

    var currentWeekWorkouts: [ScheduledWorkout] {
        allScheduledWorkouts
            .filter { $0.weekNumber == selectedWeek }
            .sorted { $0.date < $1.date }
    }

    var currentMonthWorkouts: [ScheduledWorkout] {
        let calendar = Calendar.current
        return allScheduledWorkouts.filter { workout in
            let components = calendar.dateComponents([.month, .year], from: workout.date)
            return components.month == selectedMonth && components.year == selectedYear
        }.sorted { $0.date < $1.date }
    }

    var currentWeekSummary: TrainingWeekSummary? {
        guard activePlan != nil else { return nil }
        let weekWorkouts = currentWeekWorkouts
        guard let firstDay = weekWorkouts.first?.date,
              let lastDay = weekWorkouts.last?.date
        else { return nil }

        let weeksOut = (activePlan?.totalWeeks ?? 16) - selectedWeek
        return TrainingWeekSummary(
            weekNumber: selectedWeek,
            phase: CanovaTrainingPhase.fromWeeksOut(weeksOut),
            startDate: firstDay,
            endDate: lastDay,
            scheduledWorkouts: weekWorkouts
        )
    }

    /// Number of empty cells before the first day of the month (for Monday-start week)
    var monthLeadingEmptyCells: Int {
        let calendar = Calendar.current
        guard let firstOfMonth = calendar.date(from: DateComponents(year: selectedYear, month: selectedMonth, day: 1)) else {
            return 0
        }
        let weekday = calendar.component(.weekday, from: firstOfMonth)
        // Convert to Monday-start (weekday 1 = Sunday, so Monday = 2)
        // Monday=0, Tuesday=1, ..., Sunday=6
        return (weekday + 5) % 7
    }

    /// Days in the selected month
    var daysInMonth: Int {
        let calendar = Calendar.current
        guard let date = calendar.date(from: DateComponents(year: selectedYear, month: selectedMonth, day: 1)),
              let range = calendar.range(of: .day, in: .month, for: date)
        else { return 30 }
        return range.count
    }

    // MARK: - Load Plan

    @MainActor
    func loadActivePlan() async {
        isLoadingPlan = true
        errorMessage = nil

        // First load the active goal (non-critical)
        await loadActiveGoal()

        // Skip Supabase if using local mode
        guard !Self.useLocalMode else {
            isLoadingPlan = false
            return
        }

        do {
            // Then load the active training plan
            let plans: [TrainingPlan] = try await supabase
                .from("training_plans")
                .select()
                .eq("status", value: "active")
                .order("created_at", ascending: false)
                .limit(1)
                .execute()
                .value

            if let plan = plans.first {
                activePlan = plan
                await loadScheduledWorkouts(for: plan.id)
                initializeSelectedWeek()
                initializeSelectedMonth()
            }
            // No plan found is not an error - user just hasn't created one yet

            isLoadingPlan = false
        } catch {
            // Log error but don't show to user - treat as "no plan yet"
            // This handles cases where Supabase isn't configured or network is unavailable
            Log.coach.info("Could not load plan from Supabase (may not be configured): \(error.localizedDescription)")
            isLoadingPlan = false
            // Don't set errorMessage or showError - empty state is fine
        }
    }

    @MainActor
    private func loadActiveGoal() async {
        // Skip if using local mode
        guard !Self.useLocalMode else { return }

        do {
            let response: [UserGoal] = try await supabase
                .from("user_goals")
                .select()
                .eq("status", value: "active")
                .order("target_date", ascending: true)
                .execute()
                .value

            if let goal = response.first {
                activeGoal = goal
                parseGoalTime(from: goal.goalTitle)
                calculateWeeksUntilRace(for: goal)
            }
        } catch {
            // Non-critical - just log and continue
            Log.coach.info("Could not load goal from Supabase: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func loadScheduledWorkouts(for planId: UUID) async {
        do {
            let workouts: [ScheduledWorkout] = try await supabase
                .from("scheduled_workouts")
                .select()
                .eq("plan_id", value: planId.uuidString)
                .order("date", ascending: true)
                .execute()
                .value

            allScheduledWorkouts = workouts
        } catch {
            Log.coach.error("Failed to load workouts: \(error)")
        }
    }

    // MARK: - Generate Plan

    /// Set to true to use local-only mode (no Supabase)
    static var useLocalMode = false

    /// Stored fitness assessment for the current plan
    var fitnessAssessment: FitnessAssessment?

    @MainActor
    func generatePlan(
        name: String,
        startDate: Date,
        targetDate: Date,
        targetTimeSeconds: Int,
        raceDistance: RaceDistance = .marathon,
        baseWeeklyMileage: Double = 40.0,
        peakWeeklyMileage: Double? = nil,
        canRunDoubles: Bool? = nil,
        preferredLongRunDay: String? = nil,
        fitnessAssessment: FitnessAssessment? = nil
    ) async {
        // Store the fitness assessment
        self.fitnessAssessment = fitnessAssessment
        isGeneratingPlan = true
        errorMessage = nil

        let userId = AuthManager.shared.currentUserId ?? ""

        // Create the plan object
        let planId = UUID()
        let now = Date()

        let createdPlan = TrainingPlan(
            id: planId,
            userId: userId,
            goalId: activeGoal?.id,
            name: name,
            startDate: startDate,
            endDate: targetDate,
            targetRaceDistance: raceDistance.legacyString,
            targetTimeSeconds: targetTimeSeconds,
            status: .active,
            createdAt: now,
            updatedAt: now
        )

        // Generate workouts for each week
        let workoutInserts = generateWorkoutSchedule(
            for: createdPlan,
            raceDistance: raceDistance,
            baseWeeklyMileage: baseWeeklyMileage,
            peakWeeklyMileage: peakWeeklyMileage,
            canRunDoubles: canRunDoubles,
            preferredLongRunDay: preferredLongRunDay
        )

        // Convert inserts to full ScheduledWorkout objects for local use
        let workouts = workoutInserts.map { insert in
            ScheduledWorkout(
                id: UUID(),
                planId: insert.planId,
                date: insert.date,
                dayOfWeek: insert.dayOfWeek,
                weekNumber: insert.weekNumber,
                workout: insert.workoutData,
                workoutType: insert.workoutType,
                status: .scheduled,
                completedWorkoutId: nil,
                notes: insert.notes,
                createdAt: now,
                updatedAt: now
            )
        }

        if Self.useLocalMode {
            // Local-only mode - just use in-memory data
            Log.coach.info("Using local mode - skipping Supabase")
        } else {
            // Try to save to Supabase
            do {
                // Archive any existing active plans
                try await archiveExistingPlans()

                // Create the plan insert
                let planInsert = TrainingPlanInsert(
                    userId: userId,
                    goalId: activeGoal?.id,
                    name: name,
                    startDate: startDate,
                    endDate: targetDate,
                    targetRaceDistance: raceDistance.legacyString,
                    targetTimeSeconds: targetTimeSeconds
                )

                Log.coach.info("Inserting plan to Supabase...")
                let _: [TrainingPlan] = try await supabase
                    .from("training_plans")
                    .insert(planInsert)
                    .select()
                    .execute()
                    .value

                Log.coach.info("Inserting \(workoutInserts.count) workouts to Supabase...")
                try await supabase
                    .from("scheduled_workouts")
                    .insert(workoutInserts)
                    .execute()

                Log.coach.info("Successfully saved to Supabase")
            } catch {
                // Log the detailed error but continue with local data
                Log.coach.error("Supabase error (using local data): \(error.localizedDescription)")
                Log.coach.error("Full error: \(String(describing: error))")
            }
        }

        // Update local state regardless of Supabase success
        activePlan = createdPlan
        allScheduledWorkouts = workouts
        marathonGoalTime = targetTimeSeconds
        initializeSelectedWeek()
        initializeSelectedMonth()

        isGeneratingPlan = false
        Log.coach.info("Generated plan '\(name)' with \(workouts.count) workouts")
    }

    private func archiveExistingPlans() async throws {
        try await supabase
            .from("training_plans")
            .update(["status": "archived"])
            .eq("status", value: "active")
            .execute()
    }

    // MARK: - Import Custom Plan

    /// Import a custom plan built by the Plan Builder chat.
    /// Takes pre-built plan data from the edge function and saves it as a real TrainingPlan.
    /// - Parameter workoutDates: Parallel array of dates matching `importedWorkouts`, parsed from the edge function's ISO date strings.
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
        isGeneratingPlan = true
        errorMessage = nil

        let userId = AuthManager.shared.currentUserId ?? ""
        let planId = UUID()
        let now = Date()
        let totalWeeks = max(1, (Calendar.current.dateComponents([.weekOfYear], from: startDate, to: endDate).weekOfYear ?? 0) + 1)

        let createdPlan = TrainingPlan(
            id: planId,
            userId: userId,
            goalId: activeGoal?.id,
            name: name,
            startDate: startDate,
            endDate: endDate,
            targetRaceDistance: targetRaceDistance,
            targetTimeSeconds: targetTimeSeconds,
            status: .active,
            createdAt: now,
            updatedAt: now
        )

        // Convert imported workouts to ScheduledWorkoutInserts
        let calendar = Calendar.current
        // Find the Monday of the week containing the start date
        let startWeekday = calendar.component(.weekday, from: startDate)
        let daysToMonday = (startWeekday == 1) ? 6 : startWeekday - 2
        let planMonday = calendar.date(byAdding: .day, value: -daysToMonday, to: startDate) ?? startDate

        let workoutInserts: [ScheduledWorkoutInsert] = importedWorkouts.enumerated().map { index, imported in
            let workoutDate = index < workoutDates.count ? workoutDates[index] : startDate
            let daysSinceStart = calendar.dateComponents([.day], from: planMonday, to: workoutDate).day ?? 0
            let weekNumber = max(1, (daysSinceStart / 7) + 1)
            let weeksOut = max(0, totalWeeks - weekNumber)
            let phase = CanovaTrainingPhase.fromWeeksOut(weeksOut, totalWeeks: totalWeeks)
            let workoutType = ScheduledWorkoutType.fromImportString(imported.workoutType)

            return ScheduledWorkoutInsert(
                planId: planId,
                date: workoutDate,
                dayOfWeek: imported.dayOfWeek,
                weekNumber: weekNumber,
                workoutData: workoutType == .rest ? nil : imported.toCanovaWorkout(phase: phase),
                workoutType: workoutType,
                notes: nil
            )
        }

        // Convert inserts to full ScheduledWorkout objects for local use
        let workouts = workoutInserts.map { insert in
            ScheduledWorkout(
                id: UUID(),
                planId: insert.planId,
                date: insert.date,
                dayOfWeek: insert.dayOfWeek,
                weekNumber: insert.weekNumber,
                workout: insert.workoutData,
                workoutType: insert.workoutType,
                status: .scheduled,
                completedWorkoutId: nil,
                notes: insert.notes,
                createdAt: now,
                updatedAt: now
            )
        }

        if !Self.useLocalMode {
            do {
                try await archiveExistingPlans()

                let planInsert = TrainingPlanInsert(
                    userId: userId,
                    goalId: activeGoal?.id,
                    name: name,
                    startDate: startDate,
                    endDate: endDate,
                    targetRaceDistance: targetRaceDistance,
                    targetTimeSeconds: targetTimeSeconds
                )

                Log.coach.info("Importing custom plan to Supabase...")
                let _: [TrainingPlan] = try await supabase
                    .from("training_plans")
                    .insert(planInsert)
                    .select()
                    .execute()
                    .value

                Log.coach.info("Inserting \(workoutInserts.count) imported workouts to Supabase...")
                try await supabase
                    .from("scheduled_workouts")
                    .insert(workoutInserts)
                    .execute()

                Log.coach.info("Successfully imported custom plan")
            } catch {
                Log.coach.error("Supabase error importing custom plan: \(error.localizedDescription)")
                errorMessage = "Could not save plan: \(error.localizedDescription)"
                isGeneratingPlan = false
                return false
            }
        }

        activePlan = createdPlan
        allScheduledWorkouts = workouts
        marathonGoalTime = targetTimeSeconds
        initializeSelectedWeek()
        initializeSelectedMonth()

        isGeneratingPlan = false
        Log.coach.info("Imported custom plan '\(name)' with \(workouts.count) workouts")
        return true
    }

    // MARK: - Plan Generation Algorithm

    private func generateWorkoutSchedule(
        for plan: TrainingPlan,
        raceDistance: RaceDistance = .marathon,
        baseWeeklyMileage: Double,
        peakWeeklyMileage: Double? = nil,
        canRunDoubles: Bool? = nil,
        preferredLongRunDay: String? = nil
    ) -> [ScheduledWorkoutInsert] {
        var workouts: [ScheduledWorkoutInsert] = []
        let calendar = Calendar.current

        // Find the Monday of the week containing the start date
        var startOfWeek = plan.startDate
        let weekday = calendar.component(.weekday, from: startOfWeek)
        // Adjust to Monday (weekday 2 in Calendar, where Sunday = 1)
        let daysToSubtract = (weekday == 1) ? 6 : weekday - 2
        startOfWeek = calendar.date(byAdding: .day, value: -daysToSubtract, to: startOfWeek) ?? plan.startDate

        // Calculate total weeks
        let totalWeeks = plan.totalWeeks

        // Use provided peak mileage or calculate from base
        let targetPeakMileage = peakWeeklyMileage ?? (baseWeeklyMileage * 1.5)

        for weekNum in 1 ... totalWeeks {
            let weekStartDate = calendar.date(byAdding: .weekOfYear, value: weekNum - 1, to: startOfWeek)!
            let weeksOut = totalWeeks - weekNum
            let phase = CanovaTrainingPhase.fromWeeksOut(weeksOut, totalWeeks: totalWeeks)

            // Calculate weekly mileage with proper periodization
            let weeklyMileage = calculateWeeklyMileage(
                weekNumber: weekNum,
                totalWeeks: totalWeeks,
                baseMileage: baseWeeklyMileage,
                peakMileage: targetPeakMileage,
                phase: phase
            )

            // Determine if doubles are needed (70+ mpw and user can run doubles)
            let needsDoubles = weeklyMileage >= 70.0 && (canRunDoubles ?? true)

            // Generate 7 days for each week (Monday = 1, Sunday = 7)
            for dayOffset in 0 ..< 7 {
                let date = calendar.date(byAdding: .day, value: dayOffset, to: weekStartDate)!
                let dayOfWeek = dayOffset + 1

                // Skip if date is before plan start or after plan end
                if date < plan.startDate || date > plan.endDate {
                    continue
                }

                let workoutType = determineWorkoutType(
                    dayOfWeek: dayOfWeek,
                    weekNumber: weekNum,
                    totalWeeks: totalWeeks,
                    phase: phase,
                    weeklyMileage: weeklyMileage
                )

                // Check if this day needs a double (AM + PM)
                let isDoubleDay = needsDoubles && shouldAddDouble(dayOfWeek: dayOfWeek, workoutType: workoutType)

                // For double days, add AM easy run first
                if isDoubleDay {
                    let amWorkout = createAMEasyRun(phase: phase, raceDistance: raceDistance, goalTime: plan.targetTimeSeconds)
                    workouts.append(ScheduledWorkoutInsert(
                        planId: plan.id,
                        date: date,
                        dayOfWeek: dayOfWeek,
                        weekNumber: weekNum,
                        workoutData: amWorkout,
                        workoutType: .easy,
                        notes: "AM"
                    ))
                }

                // Main workout (PM if double day)
                var workout: CanovaWorkout?
                if workoutType != .rest {
                    workout = generateWorkoutForDay(
                        dayOfWeek: dayOfWeek,
                        type: workoutType,
                        phase: phase,
                        raceDistance: raceDistance,
                        goalTime: plan.targetTimeSeconds,
                        weeklyMileage: weeklyMileage,
                        weekNumber: weekNum,
                        totalWeeks: totalWeeks,
                        includeDouble: false // No longer combining - separate workouts
                    )
                }

                workouts.append(ScheduledWorkoutInsert(
                    planId: plan.id,
                    date: date,
                    dayOfWeek: dayOfWeek,
                    weekNumber: weekNum,
                    workoutData: workout,
                    workoutType: workoutType,
                    notes: isDoubleDay ? "PM" : nil
                ))
            }
        }

        return workouts
    }

    /// Determine if a double (AM easy run) should be added for high volume weeks
    private func shouldAddDouble(dayOfWeek: Int, workoutType: ScheduledWorkoutType) -> Bool {
        // Add doubles on easy days, not on quality days or long runs
        // Typically Mon, Wed, Fri for high volume weeks
        switch workoutType {
        case .easy, .strides:
            return dayOfWeek == 1 || dayOfWeek == 3 || dayOfWeek == 5
        default:
            return false
        }
    }

    /// Calculate weekly mileage with proper build-up, peak, and taper
    private func calculateWeeklyMileage(
        weekNumber: Int,
        totalWeeks: Int,
        baseMileage: Double,
        peakMileage: Double? = nil,
        phase: CanovaTrainingPhase
    ) -> Double {
        let weeksOut = totalWeeks - weekNumber

        // Peak mileage from assessment or default 22% above base
        let targetPeak = peakMileage ?? (baseMileage * 1.22)

        // Recovery week pattern (every 4th week drops 15%)
        let isRecoveryWeek = weekNumber % 4 == 0 && weeksOut > 3

        // 3-week taper: 90% → 70% → 40%
        if weeksOut == 0 {
            // Race week
            return baseMileage * 0.40
        }
        if weeksOut == 1 {
            // Week before race
            return baseMileage * 0.70
        }
        if weeksOut == 2 {
            // Two weeks out - start of taper
            return baseMileage * 0.90
        }

        // Build-up progression based on phase
        var targetMileage: Double
        switch phase {
        case .base:
            // Base phase - building volume
            targetMileage = baseMileage * 1.05
        case .support:
            // Support phase - progressive build toward peak
            targetMileage = baseMileage + (targetPeak - baseMileage) * 0.7
        case .specific:
            // Peak volume in specific phase
            targetMileage = targetPeak
        case .taper:
            // Taper already handled above, but fallback
            targetMileage = baseMileage * 0.80
        }

        // Apply recovery week reduction
        if isRecoveryWeek {
            targetMileage *= 0.85
        }

        return targetMileage
    }

    /// Marathon-specific weekly structure
    /// Base phase (weeks 1-3): Fartlek + Progression long run + Strides
    /// Specific phase: Alternating threshold/intervals + Long run variations
    /// Taper phase: Reduced volume maintaining intensity
    /// No mandatory rest days - rest is optional based on athlete needs
    private func determineWorkoutType(
        dayOfWeek: Int,
        weekNumber: Int,
        totalWeeks: Int,
        phase: CanovaTrainingPhase,
        weeklyMileage: Double = 50.0
    ) -> ScheduledWorkoutType {
        let weeksOut = totalWeeks - weekNumber
        let isRecoveryWeek = weekNumber % 4 == 0 && weeksOut > 3
        let baseWeeks = max(1, Int(Double(totalWeeks) * 0.10))
        let supportWeeks = max(2, Int(Double(totalWeeks) * 0.40))

        // Race week (last week)
        if weeksOut == 0 {
            switch dayOfWeek {
            case 1: return .easy        // Monday: Shakeout
            case 2: return .easy        // Tuesday: Easy
            case 3: return .strides     // Wednesday: Easy + Strides
            case 4: return .easy        // Thursday: Short shakeout
            case 5: return .rest        // Friday: Rest
            case 6: return .rest        // Saturday: Rest
            case 7: return .race        // Sunday: Race!
            default: return .rest
            }
        }

        // Taper phase (except race week)
        if phase == .taper {
            switch dayOfWeek {
            case 1: return .easy        // Monday: Easy
            case 2: return .tempo       // Tuesday: Short tempo tune-up
            case 3: return .easy        // Wednesday: Easy
            case 4: return .strides     // Thursday: Easy + Strides
            case 5: return .easy        // Friday: Easy
            case 6: return .longRun     // Saturday: Reduced long run
            case 7: return .recovery    // Sunday: Recovery
            default: return .easy
            }
        }

        // Recovery weeks - reduced intensity
        if isRecoveryWeek {
            switch dayOfWeek {
            case 1: return .easy        // Monday: Easy
            case 2: return .easy        // Tuesday: Easy
            case 3: return .strides     // Wednesday: Easy + Strides
            case 4: return .easy        // Thursday: Easy
            case 5: return .easy        // Friday: Easy
            case 6: return .longRun     // Saturday: Long Run (reduced)
            case 7: return .recovery    // Sunday: Recovery
            default: return .easy
            }
        }

        // Base phase - Fartlek + Progression Long Run + Strides
        if phase == .base {
            switch dayOfWeek {
            case 1: return .easy            // Monday: Easy
            case 2: return .tempo           // Tuesday: Fartlek (handled in generation)
            case 3: return .easy            // Wednesday: Easy
            case 4: return .strides         // Thursday: Easy + Strides
            case 5: return .easy            // Friday: Easy
            case 6: return .longRun         // Saturday: Progression Long Run
            case 7: return .recovery        // Sunday: Recovery
            default: return .easy
            }
        }

        // Support phase - Race-supportive work at 90% and 110% of race pace
        if phase == .support {
            let supportWeekNumber = weekNumber - baseWeeks
            let isTempoWeek = supportWeekNumber % 2 == 1 // Alternate tempo/intervals

            switch dayOfWeek {
            case 1: return .easy            // Monday: Easy
            case 2:                         // Tuesday: Quality session
                return isTempoWeek ? .tempo : .intervals
            case 3: return .easy            // Wednesday: Easy
            case 4: return .strides         // Thursday: Easy + Strides
            case 5: return .easy            // Friday: Easy
            case 6: return .longRun         // Saturday: Long Run (progressive)
            case 7: return .recovery        // Sunday: Recovery
            default: return .easy
            }
        }

        // Specific phase - Alternating workout types
        let specificWeekNumber = weekNumber - baseWeeks - supportWeeks
        let isThresholdWeek = specificWeekNumber % 2 == 1 // Odd weeks: threshold/alternations

        switch dayOfWeek {
        case 1: return .easy            // Monday: Easy
        case 2:                         // Tuesday: Quality
            return isThresholdWeek ? .tempo : .intervals
        case 3: return .easy            // Wednesday: Easy
        case 4: return .strides         // Thursday: Easy + Strides
        case 5: return .easy            // Friday: Easy
        case 6: return .longRun         // Saturday: Long Run (varied)
        case 7: return .recovery        // Sunday: Recovery
        default: return .easy
        }
    }

    // Track recently used templates for variety
    private var recentTemplateIDs: Set<String> = []

    /// Generate workout using the WorkoutSelector from the workout library
    private func generateWorkoutForDay(
        dayOfWeek: Int,
        type: ScheduledWorkoutType,
        phase: CanovaTrainingPhase,
        raceDistance: RaceDistance,
        goalTime: Int,
        weeklyMileage: Double,
        weekNumber: Int,
        totalWeeks: Int,
        includeDouble: Bool = false
    ) -> CanovaWorkout {
        let weeksOut = totalWeeks - weekNumber
        let isRecoveryWeek = weekNumber % 4 == 0 && weeksOut > 3
        let baseWeeks = max(1, Int(Double(totalWeeks) * 0.10))
        let supportWeeks = max(2, Int(Double(totalWeeks) * 0.40))
        let taperWeeks = max(1, Int(Double(totalWeeks) * 0.10))
        let specificWeeks = totalWeeks - baseWeeks - supportWeeks - taperWeeks

        // Week within current phase (1-indexed)
        let weekInPhase: Int
        let totalWeeksInPhase: Int
        if phase == .base {
            weekInPhase = weekNumber
            totalWeeksInPhase = baseWeeks
        } else if phase == .support {
            weekInPhase = weekNumber - baseWeeks
            totalWeeksInPhase = supportWeeks
        } else if phase == .specific {
            weekInPhase = weekNumber - baseWeeks - supportWeeks
            totalWeeksInPhase = specificWeeks
        } else {
            weekInPhase = weekNumber - baseWeeks - supportWeeks - specificWeeks
            totalWeeksInPhase = taperWeeks
        }

        let selector = WorkoutSelector.shared

        // Try to select from the workout library
        let result: WorkoutSelector.SelectionResult?

        switch type {
        case .longRun:
            result = selector.selectLongRun(
                raceDistance: raceDistance,
                phase: phase,
                weekInPhase: weekInPhase,
                totalWeeksInPhase: totalWeeksInPhase,
                recentTemplateIDs: recentTemplateIDs,
                isRecoveryWeek: isRecoveryWeek,
                goalTimeSeconds: goalTime,
                weeklyMileage: weeklyMileage
            )
        case .easy:
            result = selector.selectEasyRun(
                raceDistance: raceDistance,
                phase: phase,
                weekInPhase: weekInPhase,
                totalWeeksInPhase: totalWeeksInPhase,
                includeStrides: false,
                isDoubleDay: false,
                isAM: false,
                goalTimeSeconds: goalTime,
                weeklyMileage: weeklyMileage
            )
        case .recovery:
            result = selector.selectRecoveryRun(
                raceDistance: raceDistance,
                phase: phase,
                weekInPhase: weekInPhase,
                totalWeeksInPhase: totalWeeksInPhase,
                goalTimeSeconds: goalTime,
                weeklyMileage: weeklyMileage
            )
        case .strides:
            result = selector.selectEasyRun(
                raceDistance: raceDistance,
                phase: phase,
                weekInPhase: weekInPhase,
                totalWeeksInPhase: totalWeeksInPhase,
                includeStrides: true,
                isDoubleDay: false,
                isAM: false,
                goalTimeSeconds: goalTime,
                weeklyMileage: weeklyMileage
            )
        default:
            result = selector.selectWorkout(
                raceDistance: raceDistance,
                phase: phase,
                weekInPhase: weekInPhase,
                totalWeeksInPhase: totalWeeksInPhase,
                dayOfWeek: dayOfWeek,
                scheduledType: type,
                recentTemplateIDs: recentTemplateIDs,
                isRecoveryWeek: isRecoveryWeek,
                goalTimeSeconds: goalTime,
                weeklyMileage: weeklyMileage
            )
        }

        // Track the template for variety
        if let result = result {
            recentTemplateIDs.insert(result.template.id)
            // Keep only last 14 templates (~2 weeks)
            if recentTemplateIDs.count > 14 {
                recentTemplateIDs.removeFirst()
            }
            return result.workout
        }

        // Fallback to legacy workout creation if selector returns nil
        return createFallbackWorkout(
            type: type,
            phase: phase,
            goalTime: goalTime,
            weeklyMileage: weeklyMileage
        )
    }

    /// Fallback workout when the selector can't find a suitable template
    private func createFallbackWorkout(
        type: ScheduledWorkoutType,
        phase: CanovaTrainingPhase,
        goalTime: Int,
        weeklyMileage: Double
    ) -> CanovaWorkout {
        switch type {
        case .tempo:
            return createTempoWorkout(phase: phase, goalTime: goalTime, totalMiles: 8.0)
        case .intervals:
            return createIntervalsWorkout(phase: phase, goalTime: goalTime, totalMiles: 8.0)
        case .longRun:
            return createLongRunWorkout(phase: phase, goalTime: goalTime, totalMiles: weeklyMileage * 0.35)
        case .easy:
            return createEasyRunWorkout(phase: phase, goalTime: goalTime, totalMiles: max(4, weeklyMileage * 0.10), includeDouble: false)
        case .recovery:
            return createRecoveryWorkout(phase: phase, goalTime: goalTime, totalMiles: max(3, weeklyMileage * 0.07))
        case .strides:
            return createStridesWorkout(phase: phase, goalTime: goalTime, totalMiles: max(5, weeklyMileage * 0.10), includeDouble: false)
        default:
            return createEasyRunWorkout(phase: phase, goalTime: goalTime, totalMiles: weeklyMileage * 0.10, includeDouble: false)
        }
    }

    private func createTempoWorkout(phase: CanovaTrainingPhase, goalTime: Int, totalMiles: Double) -> CanovaWorkout {
        // Distribute: 2mi warmup + tempo portion + 2mi cooldown
        let warmupCooldown = 4.0
        let tempoMiles = max(4.0, totalMiles - warmupCooldown)
        let actualTotal = tempoMiles + warmupCooldown

        return CanovaWorkout(
            id: UUID(),
            name: "Tempo Run",
            category: .special,
            trainingPhase: phase,
            description: "Sustained effort at comfortably hard pace",
            steps: [
                CanovaWorkoutStep(id: UUID(), stepType: .warmup, durationType: .distanceMiles, durationValue: 2.0, targetPaceIntensity: PaceIntensity(percentage: 70), notes: "Easy warm-up", order: 0),
                CanovaWorkoutStep(id: UUID(), stepType: .active, durationType: .distanceMiles, durationValue: tempoMiles, targetPaceIntensity: PaceIntensity(percentage: 88), notes: "Tempo @ marathon effort", order: 1),
                CanovaWorkoutStep(id: UUID(), stepType: .cooldown, durationType: .distanceMiles, durationValue: 2.0, targetPaceIntensity: PaceIntensity(percentage: 65), notes: "Easy cool-down", order: 2),
            ],
            totalDistanceMiles: actualTotal ,
            estimatedDurationMinutes: actualTotal * 8.0,
            signatureType: .progressiveTempo,
            createdAt: Date()
        )
    }

    private func createIntervalsWorkout(phase: CanovaTrainingPhase, goalTime: Int, totalMiles: Double) -> CanovaWorkout {
        // Distribute: 2mi warmup + intervals + 2mi cooldown
        let warmupCooldown = 4.0
        let intervalMiles = max(4.0, totalMiles - warmupCooldown)

        // Calculate number of mile repeats (accounting for recovery jog ~0.25mi each)
        let repeats = max(3, Int(intervalMiles / 1.25))
        let actualIntervalMiles = Double(repeats) * 1.0
        let actualTotal = actualIntervalMiles + warmupCooldown

        var steps: [CanovaWorkoutStep] = []
        var order = 0

        // Warmup
        steps.append(CanovaWorkoutStep(id: UUID(), stepType: .warmup, durationType: .distanceMiles, durationValue: 2.0, targetPaceIntensity: PaceIntensity(percentage: 70), notes: "Easy warm-up", order: order))
        order += 1

        // Intervals
        for i in 0 ..< repeats {
            let isLast = i == repeats - 1
            let intensity = isLast ? 102.0 : 100.0
            let note = isLast ? "1 mile - fast finish!" : "1 mile @ race pace"

            steps.append(CanovaWorkoutStep(id: UUID(), stepType: .active, durationType: .distanceMiles, durationValue: 1.0, targetPaceIntensity: PaceIntensity(percentage: intensity), notes: note, order: order))
            order += 1

            if !isLast {
                steps.append(CanovaWorkoutStep(id: UUID(), stepType: .recovery, durationType: .timeSeconds, durationValue: 90, targetPaceIntensity: nil, notes: "90s recovery jog", order: order))
                order += 1
            }
        }

        // Cooldown
        steps.append(CanovaWorkoutStep(id: UUID(), stepType: .cooldown, durationType: .distanceMiles, durationValue: 2.0, targetPaceIntensity: PaceIntensity(percentage: 65), notes: "Easy cool-down", order: order))

        return CanovaWorkout(
            id: UUID(),
            name: "\(repeats) x 1 Mile Repeats",
            category: .specific,
            trainingPhase: phase,
            description: "Race-pace mile repeats with recovery",
            steps: steps,
            totalDistanceMiles: actualTotal ,
            estimatedDurationMinutes: actualTotal * 7.5,
            signatureType: .racePaceRepeats,
            createdAt: Date()
        )
    }

    private func createLongRunWorkout(phase: CanovaTrainingPhase, goalTime: Int, totalMiles: Double) -> CanovaWorkout {
        let distanceMiles = max(10.0, round(totalMiles))

        // In specific phase, add marathon pace finish for long runs >= 14 miles
        let includesMPWork = phase == .specific && distanceMiles >= 14

        if includesMPWork {
            let mpMiles = min(6.0, distanceMiles * 0.3) // Last 30% at MP, max 6 miles
            let easyMiles = distanceMiles - mpMiles

            return CanovaWorkout(
                id: UUID(),
                name: "Long Run w/ MP Finish",
                category: .fundamental,
                trainingPhase: phase,
                description: "Long run finishing at marathon pace",
                steps: [
                    CanovaWorkoutStep(id: UUID(), stepType: .active, durationType: .distanceMiles, durationValue: easyMiles, targetPaceIntensity: PaceIntensity(percentage: 75), notes: "Easy long run pace", order: 0),
                    CanovaWorkoutStep(id: UUID(), stepType: .active, durationType: .distanceMiles, durationValue: mpMiles, targetPaceIntensity: PaceIntensity(percentage: 100), notes: "Marathon pace finish", order: 1),
                ],
                totalDistanceMiles: distanceMiles ,
                estimatedDurationMinutes: distanceMiles * 8.5,
                signatureType: .longRunWithTempo,
                createdAt: Date()
            )
        }

        return CanovaWorkout(
            id: UUID(),
            name: "Long Run",
            category: .fundamental,
            trainingPhase: phase,
            description: "Endurance builder at easy pace",
            steps: [
                CanovaWorkoutStep(id: UUID(), stepType: .active, durationType: .distanceMiles, durationValue: distanceMiles, targetPaceIntensity: PaceIntensity(percentage: 75), notes: "Easy conversational pace", order: 0),
            ],
            totalDistanceMiles: distanceMiles ,
            estimatedDurationMinutes: distanceMiles * 9.0,
            signatureType: nil,
            createdAt: Date()
        )
    }

    private func createEasyRunWorkout(phase: CanovaTrainingPhase, goalTime: Int, totalMiles: Double, includeDouble: Bool = false) -> CanovaWorkout {
        let distanceMiles = max(4.0, round(totalMiles))

        return CanovaWorkout(
            id: UUID(),
            name: "Easy Run",
            category: .regeneration,
            trainingPhase: phase,
            description: "Aerobic maintenance run",
            steps: [
                CanovaWorkoutStep(id: UUID(), stepType: .active, durationType: .distanceMiles, durationValue: distanceMiles, targetPaceIntensity: PaceIntensity(percentage: 70), notes: "Easy conversational pace", order: 0),
            ],
            totalDistanceMiles: distanceMiles,
            estimatedDurationMinutes: distanceMiles * 9.5,
            signatureType: nil,
            createdAt: Date()
        )
    }

    private func createRecoveryWorkout(phase: CanovaTrainingPhase, goalTime: Int, totalMiles: Double) -> CanovaWorkout {
        let distanceMiles = max(3.0, round(totalMiles))

        return CanovaWorkout(
            id: UUID(),
            name: "Recovery Run",
            category: .regeneration,
            trainingPhase: phase,
            description: "Very easy recovery jog",
            steps: [
                CanovaWorkoutStep(id: UUID(), stepType: .active, durationType: .distanceMiles, durationValue: distanceMiles, targetPaceIntensity: PaceIntensity(percentage: 65), notes: "Super easy - conversational", order: 0),
            ],
            totalDistanceMiles: distanceMiles,
            estimatedDurationMinutes: distanceMiles * 10.0,
            signatureType: nil,
            createdAt: Date()
        )
    }

    /// AM easy run for double days - short, easy effort
    private func createAMEasyRun(phase: CanovaTrainingPhase, raceDistance: RaceDistance, goalTime: Int) -> CanovaWorkout {
        // Try to use the workout library
        if let result = WorkoutSelector.shared.selectEasyRun(
            raceDistance: raceDistance,
            phase: phase,
            weekInPhase: 1,
            totalWeeksInPhase: 8,
            includeStrides: false,
            isDoubleDay: true,
            isAM: true,
            goalTimeSeconds: goalTime,
            weeklyMileage: 50.0
        ) {
            return result.workout
        }

        // Fallback
        let distanceMiles = 4.0 // Fixed 4mi AM run
        let easyPace = raceDistance.easyPaceIntensity

        return CanovaWorkout(
            id: UUID(),
            name: "AM Easy Run",
            category: .regeneration,
            trainingPhase: phase,
            description: "Morning easy run - part of double day",
            steps: [
                CanovaWorkoutStep(id: UUID(), stepType: .active, durationType: .distanceMiles, durationValue: distanceMiles, targetPaceIntensity: PaceIntensity(percentage: easyPace), notes: "AM easy - conversational pace", order: 0),
            ],
            totalDistanceMiles: distanceMiles,
            estimatedDurationMinutes: distanceMiles * 10.0,
            signatureType: nil,
            createdAt: Date()
        )
    }

    private func createProgressionWorkout(phase: CanovaTrainingPhase, goalTime: Int, totalMiles: Double) -> CanovaWorkout {
        // Progression run: start easy, finish faster
        // 2mi warmup + progression segments + no cooldown (end fast)
        let warmup = 2.0
        let progressionMiles = max(4.0, totalMiles - warmup)
        let actualTotal = progressionMiles + warmup

        // Split progression into 3 segments: easy -> moderate -> tempo
        let segmentMiles = progressionMiles / 3.0

        return CanovaWorkout(
            id: UUID(),
            name: "Progression Run",
            category: .special,
            trainingPhase: phase,
            description: "Start easy, finish fast - great for building fitness",
            steps: [
                CanovaWorkoutStep(id: UUID(), stepType: .warmup, durationType: .distanceMiles, durationValue: warmup, targetPaceIntensity: PaceIntensity(percentage: 70), notes: "Easy warm-up", order: 0),
                CanovaWorkoutStep(id: UUID(), stepType: .active, durationType: .distanceMiles, durationValue: segmentMiles, targetPaceIntensity: PaceIntensity(percentage: 75), notes: "Easy pace", order: 1),
                CanovaWorkoutStep(id: UUID(), stepType: .active, durationType: .distanceMiles, durationValue: segmentMiles, targetPaceIntensity: PaceIntensity(percentage: 82), notes: "Moderate - pick it up", order: 2),
                CanovaWorkoutStep(id: UUID(), stepType: .active, durationType: .distanceMiles, durationValue: segmentMiles, targetPaceIntensity: PaceIntensity(percentage: 90), notes: "Tempo finish - strong!", order: 3),
            ],
            totalDistanceMiles: actualTotal ,
            estimatedDurationMinutes: actualTotal * 8.0,
            signatureType: .progressiveTempo,
            createdAt: Date()
        )
    }

    private func createStridesWorkout(phase: CanovaTrainingPhase, goalTime: Int, totalMiles: Double, includeDouble: Bool = false) -> CanovaWorkout {
        // Easy run with 6x100m strides
        let easyMiles = max(4.0, round(totalMiles) - 0.5) // Account for strides distance

        var steps: [CanovaWorkoutStep] = []
        var order = 0

        // Main easy run
        steps.append(CanovaWorkoutStep(id: UUID(), stepType: .active, durationType: .distanceMiles, durationValue: easyMiles, targetPaceIntensity: PaceIntensity(percentage: 70), notes: "Easy conversational pace", order: order))
        order += 1

        // 6x100m strides with walk-back recovery
        for i in 0 ..< 6 {
            steps.append(CanovaWorkoutStep(id: UUID(), stepType: .active, durationType: .distanceMeters, durationValue: 100, targetPaceIntensity: PaceIntensity(percentage: 115), notes: "Stride \(i + 1) - smooth & fast", order: order))
            order += 1

            if i < 5 { // No recovery after last stride
                steps.append(CanovaWorkoutStep(id: UUID(), stepType: .recovery, durationType: .distanceMeters, durationValue: 100, targetPaceIntensity: nil, notes: "Walk back", order: order))
                order += 1
            }
        }

        let stridesMiles = 0.75 // ~1.2km of strides total
        let totalDistance = easyMiles + stridesMiles

        return CanovaWorkout(
            id: UUID(),
            name: "Easy + 6x100m Strides",
            category: .fundamental,
            trainingPhase: phase,
            description: "Easy run with strides to maintain leg speed",
            steps: steps,
            totalDistanceMiles: totalDistance,
            estimatedDurationMinutes: totalDistance * 9.0 + 10, // Extra time for strides
            signatureType: nil,
            createdAt: Date()
        )
    }

    // MARK: - Base Phase Workouts

    /// Fartlek progression: 10x1'/2' → 8x3'/3' → 6x5'/2'
    private func createFartlekWorkout(weekInPhase: Int, baseWeeks: Int, goalTime: Int) -> CanovaWorkout {
        var steps: [CanovaWorkoutStep] = []
        var order = 0

        // Warmup
        steps.append(CanovaWorkoutStep(id: UUID(), stepType: .warmup, durationType: .distanceMiles, durationValue: 2.0, targetPaceIntensity: PaceIntensity(percentage: 70), notes: "Easy warm-up", order: order))
        order += 1

        // Progress fartlek structure based on week
        let progression = min(weekInPhase, 3) // Cap at week 3 structure
        let (reps, fastSeconds, easySeconds, name): (Int, Double, Double, String)

        switch progression {
        case 1:
            // Week 1: 10 x 1' fast / 2' easy (~30 min of intervals)
            (reps, fastSeconds, easySeconds, name) = (10, 60, 120, "10 x 1min Fast / 2min Easy")
        case 2:
            // Week 2: 8 x 3' steady / 3' easy (~48 min of intervals)
            (reps, fastSeconds, easySeconds, name) = (8, 180, 180, "8 x 3min Steady / 3min Easy")
        default:
            // Week 3+: 6 x 5' steady / 2' easy (~42 min of intervals)
            (reps, fastSeconds, easySeconds, name) = (6, 300, 120, "6 x 5min Steady / 2min Easy")
        }

        // Add fartlek intervals
        for i in 0 ..< reps {
            let intensity = progression == 1 ? 105.0 : 95.0 // Fast vs Steady
            let note = progression == 1 ? "Fast effort \(i + 1)" : "Steady effort \(i + 1)"

            steps.append(CanovaWorkoutStep(id: UUID(), stepType: .active, durationType: .timeSeconds, durationValue: fastSeconds, targetPaceIntensity: PaceIntensity(percentage: intensity), notes: note, order: order))
            order += 1

            if i < reps - 1 {
                steps.append(CanovaWorkoutStep(id: UUID(), stepType: .recovery, durationType: .timeSeconds, durationValue: easySeconds, targetPaceIntensity: PaceIntensity(percentage: 70), notes: "Easy recovery", order: order))
                order += 1
            }
        }

        // Cooldown
        steps.append(CanovaWorkoutStep(id: UUID(), stepType: .cooldown, durationType: .distanceMiles, durationValue: 2.0, targetPaceIntensity: PaceIntensity(percentage: 65), notes: "Easy cool-down", order: order))

        let totalMinutes = 4 * 9.0 + Double(reps) * (fastSeconds + easySeconds) / 60.0
        let estimatedMiles = totalMinutes / 8.5

        return CanovaWorkout(
            id: UUID(),
            name: "Fartlek: \(name)",
            category: .special,
            trainingPhase: .base,
            description: "Build aerobic capacity with varied pace running",
            steps: steps,
            totalDistanceMiles: estimatedMiles ,
            estimatedDurationMinutes: totalMinutes,
            signatureType: nil,
            createdAt: Date()
        )
    }

    /// Base phase progression long run: 8mi → 12-14mi
    private func createBasePhaseProgLongRun(weekInPhase: Int, baseWeeks: Int, goalTime: Int) -> CanovaWorkout {
        // Progress from 8mi to 14mi over base phase
        let startMiles = 8.0
        let endMiles = 14.0
        let progressPerWeek = (endMiles - startMiles) / Double(max(1, baseWeeks - 1))
        let distanceMiles = min(endMiles, startMiles + progressPerWeek * Double(weekInPhase - 1))

        return CanovaWorkout(
            id: UUID(),
            name: "Progression Long Run",
            category: .fundamental,
            trainingPhase: .base,
            description: "Start easy, progress to moderate/steady by feel",
            steps: [
                CanovaWorkoutStep(id: UUID(), stepType: .active, durationType: .distanceMiles, durationValue: distanceMiles * 0.6, targetPaceIntensity: PaceIntensity(percentage: 72), notes: "Easy - conversational", order: 0),
                CanovaWorkoutStep(id: UUID(), stepType: .active, durationType: .distanceMiles, durationValue: distanceMiles * 0.4, targetPaceIntensity: PaceIntensity(percentage: 80), notes: "Moderate/steady by feel", order: 1),
            ],
            totalDistanceMiles: distanceMiles ,
            estimatedDurationMinutes: distanceMiles * 9.0,
            signatureType: nil,
            createdAt: Date()
        )
    }

    // MARK: - Specific Phase Workouts

    /// Threshold/Alternations workout for specific phase
    private func createThresholdWorkout(weekInPhase: Int, specificWeeks: Int, goalTime: Int) -> CanovaWorkout {
        var steps: [CanovaWorkoutStep] = []
        var order = 0

        // Warmup
        steps.append(CanovaWorkoutStep(id: UUID(), stepType: .warmup, durationType: .distanceMiles, durationValue: 2.0, targetPaceIntensity: PaceIntensity(percentage: 70), notes: "Easy warm-up", order: order))
        order += 1

        // Progress workout volume: 6mi → 12mi of alternations
        let thresholdWeek = (weekInPhase + 1) / 2 // Which threshold week (1, 2, 3...)
        let workoutMiles = min(12.0, 6.0 + Double(thresholdWeek - 1) * 2.0)

        // Alternations: MP-10 / MP+20 (faster/slower than MP)
        let segmentMiles = 0.5 // Half-mile alternations
        let segments = Int(workoutMiles / segmentMiles)

        for i in 0 ..< segments {
            let isFast = i % 2 == 0
            let intensity = isFast ? 110.0 : 80.0 // MP-10 vs MP+20
            let note = isFast ? "MP-10 (faster)" : "MP+20 (float)"

            steps.append(CanovaWorkoutStep(id: UUID(), stepType: .active, durationType: .distanceMiles, durationValue: segmentMiles, targetPaceIntensity: PaceIntensity(percentage: intensity), notes: note, order: order))
            order += 1
        }

        // Cooldown
        steps.append(CanovaWorkoutStep(id: UUID(), stepType: .cooldown, durationType: .distanceMiles, durationValue: 2.0, targetPaceIntensity: PaceIntensity(percentage: 65), notes: "Easy cool-down", order: order))

        let totalMiles = 4.0 + workoutMiles

        return CanovaWorkout(
            id: UUID(),
            name: "\(Int(workoutMiles))mi Alternations",
            category: .specific,
            trainingPhase: .specific,
            description: "MP-10/MP+20 alternations to build marathon-specific endurance",
            steps: steps,
            totalDistanceMiles: totalMiles ,
            estimatedDurationMinutes: totalMiles * 7.5,
            signatureType: nil,
            createdAt: Date()
        )
    }

    /// Interval workout for specific phase
    /// Early: 8 x 1mi @ HMP with 0.5mi recovery
    /// Later: 6 x 1mi cutdown MP → HMP-10 with 0.5mi recovery
    private func createSpecificIntervalsWorkout(weekInPhase: Int, specificWeeks: Int, goalTime: Int) -> CanovaWorkout {
        var steps: [CanovaWorkoutStep] = []
        var order = 0

        // Warmup
        steps.append(CanovaWorkoutStep(id: UUID(), stepType: .warmup, durationType: .distanceMiles, durationValue: 2.0, targetPaceIntensity: PaceIntensity(percentage: 70), notes: "Easy warm-up", order: order))
        order += 1

        let intervalWeek = weekInPhase / 2 // Which interval week (0, 1, 2...)
        let midPoint = specificWeeks / 4
        let isLaterPhase = intervalWeek >= midPoint

        if isLaterPhase {
            // Later specific phase: 6 x 1mi cutdown MP → HMP-10 with 0.5mi recovery
            // Intensity progresses: 100% → 102% → 104% → 106% → 108% → 110%
            let intensities = [100.0, 102.0, 104.0, 106.0, 108.0, 110.0]

            for i in 0 ..< 6 {
                let note = i == 0 ? "Mile 1 @ MP" : i == 5 ? "Mile 6 @ HMP-10 - SEND IT!" : "Mile \(i + 1) - pick it up"
                steps.append(CanovaWorkoutStep(id: UUID(), stepType: .active, durationType: .distanceMiles, durationValue: 1.0, targetPaceIntensity: PaceIntensity(percentage: intensities[i]), notes: note, order: order))
                order += 1

                if i < 5 {
                    steps.append(CanovaWorkoutStep(id: UUID(), stepType: .recovery, durationType: .distanceMiles, durationValue: 0.5, targetPaceIntensity: PaceIntensity(percentage: 70), notes: "0.5mi jog recovery", order: order))
                    order += 1
                }
            }

            steps.append(CanovaWorkoutStep(id: UUID(), stepType: .cooldown, durationType: .distanceMiles, durationValue: 2.0, targetPaceIntensity: PaceIntensity(percentage: 65), notes: "Easy cool-down", order: order))

            // 2mi warmup + 6mi reps + 2.5mi recovery + 2mi cooldown = 12.5mi
            return CanovaWorkout(
                id: UUID(),
                name: "6 x 1mi Cutdown (MP → HMP-10)",
                category: .specific,
                trainingPhase: .specific,
                description: "Progressive mile repeats from marathon to faster than half-marathon pace",
                steps: steps,
                totalDistanceMiles: 12.5,
                estimatedDurationMinutes: 85,
                signatureType: .racePaceRepeats,
                createdAt: Date()
            )
        } else {
            // Early specific phase: 8 x 1mi @ HMP with 0.5mi recovery
            for i in 0 ..< 8 {
                let isLast = i == 7
                let intensity = isLast ? 105.0 : 103.0
                let note = isLast ? "Mile 8 @ HMP - strong finish!" : "Mile \(i + 1) @ HMP"

                steps.append(CanovaWorkoutStep(id: UUID(), stepType: .active, durationType: .distanceMiles, durationValue: 1.0, targetPaceIntensity: PaceIntensity(percentage: intensity), notes: note, order: order))
                order += 1

                if i < 7 {
                    steps.append(CanovaWorkoutStep(id: UUID(), stepType: .recovery, durationType: .distanceMiles, durationValue: 0.5, targetPaceIntensity: PaceIntensity(percentage: 70), notes: "0.5mi jog recovery", order: order))
                    order += 1
                }
            }

            steps.append(CanovaWorkoutStep(id: UUID(), stepType: .cooldown, durationType: .distanceMiles, durationValue: 2.0, targetPaceIntensity: PaceIntensity(percentage: 65), notes: "Easy cool-down", order: order))

            // 2mi warmup + 8mi reps + 3.5mi recovery + 2mi cooldown = 15.5mi
            return CanovaWorkout(
                id: UUID(),
                name: "8 x 1mi @ HMP",
                category: .specific,
                trainingPhase: .specific,
                description: "Mile repeats at half-marathon pace with 0.5mi jog recovery",
                steps: steps,
                totalDistanceMiles: 15.5,
                estimatedDurationMinutes: 105,
                signatureType: .racePaceRepeats,
                createdAt: Date()
            )
        }
    }

    /// Specific phase long runs: Rotate between easy, steady, MP repeats, and continuous MP runs
    private func createSpecificPhaseLongRun(weekInPhase: Int, specificWeeks: Int, goalTime: Int, isRecoveryWeek: Bool) -> CanovaWorkout {
        if isRecoveryWeek {
            return createLongRunWorkout(phase: .specific, goalTime: goalTime, totalMiles: 14.0)
        }

        // Rotate: Easy Long → Steady → MP Repeats → Continuous MP → repeat
        let longRunType = weekInPhase % 4

        switch longRunType {
        case 0:
            // Easy long run: 13mi → 22mi
            let miles = min(22.0, 13.0 + Double(weekInPhase / 4) * 3.0)
            return createLongRunWorkout(phase: .specific, goalTime: goalTime, totalMiles: miles)
        case 1:
            // Steady run: 2mi easy + 10mi steady → 18mi steady
            return createSteadyLongRun(weekInPhase: weekInPhase, goalTime: goalTime)
        case 2:
            // MP workout with repeats and float recovery
            return createMPWorkoutLongRun(weekInPhase: weekInPhase, goalTime: goalTime)
        default:
            // Continuous MP long run at varied intensity
            return createContinuousMPLongRun(weekInPhase: weekInPhase, goalTime: goalTime)
        }
    }

    /// Steady long run: 2mi easy + steady miles
    private func createSteadyLongRun(weekInPhase: Int, goalTime: Int) -> CanovaWorkout {
        // Progress: 10mi steady → 18mi steady
        let steadyMiles = min(18.0, 10.0 + Double(weekInPhase / 4) * 2.0)
        let totalMiles = 2.0 + steadyMiles

        return CanovaWorkout(
            id: UUID(),
            name: "Steady Long Run",
            category: .specific,
            trainingPhase: .specific,
            description: "Extended steady-state running for marathon endurance",
            steps: [
                CanovaWorkoutStep(id: UUID(), stepType: .warmup, durationType: .distanceMiles, durationValue: 2.0, targetPaceIntensity: PaceIntensity(percentage: 72), notes: "Easy warm-up", order: 0),
                CanovaWorkoutStep(id: UUID(), stepType: .active, durationType: .distanceMiles, durationValue: steadyMiles, targetPaceIntensity: PaceIntensity(percentage: 85), notes: "Steady effort - controlled", order: 1),
            ],
            totalDistanceMiles: totalMiles,
            estimatedDurationMinutes: totalMiles * 8.0,
            signatureType: nil,
            createdAt: Date()
        )
    }

    /// Continuous MP long run at varied intensity based on progression
    /// 1mi warmup + continuous run at controlled effort
    private func createContinuousMPLongRun(weekInPhase: Int, goalTime: Int) -> CanovaWorkout {
        // Progress through continuous MP runs at decreasing intensity but increasing distance
        let mpWeek = weekInPhase / 4
        let progression = min(mpWeek, 2)

        let (mainMiles, intensity, name, description): (Double, Double, String, String)

        switch progression {
        case 0:
            // 15mi @ 95% MP
            (mainMiles, intensity, name, description) = (15.0, 95.0, "15mi @ 95% MP", "Continuous run at controlled marathon effort")
        case 1:
            // 18mi @ 92% MP
            (mainMiles, intensity, name, description) = (18.0, 92.0, "18mi @ 92% MP", "Extended run building marathon endurance")
        default:
            // 21mi @ 90% MP
            (mainMiles, intensity, name, description) = (21.0, 90.0, "21mi @ 90% MP", "Long aerobic run at steady marathon effort")
        }

        let totalMiles = 1.0 + mainMiles // 1mi warmup + main run

        return CanovaWorkout(
            id: UUID(),
            name: name,
            category: .specific,
            trainingPhase: .specific,
            description: description,
            steps: [
                CanovaWorkoutStep(id: UUID(), stepType: .warmup, durationType: .distanceMiles, durationValue: 1.0, targetPaceIntensity: PaceIntensity(percentage: 70), notes: "Easy warm-up", order: 0),
                CanovaWorkoutStep(id: UUID(), stepType: .active, durationType: .distanceMiles, durationValue: mainMiles, targetPaceIntensity: PaceIntensity(percentage: intensity), notes: "Continuous @ \(Int(intensity))% MP", order: 1),
            ],
            totalDistanceMiles: totalMiles,
            estimatedDurationMinutes: totalMiles * 8.0,
            signatureType: nil,
            createdAt: Date()
        )
    }

    /// MP workout long run: Repeats at MP with 0.5mi float recovery
    /// Progression: 5x2mi → 4x3mi → 3x4mi @ MP
    private func createMPWorkoutLongRun(weekInPhase: Int, goalTime: Int) -> CanovaWorkout {
        var steps: [CanovaWorkoutStep] = []
        var order = 0

        // Warmup
        steps.append(CanovaWorkoutStep(id: UUID(), stepType: .warmup, durationType: .distanceMiles, durationValue: 2.0, targetPaceIntensity: PaceIntensity(percentage: 70), notes: "Easy warm-up", order: order))
        order += 1

        // Progress: 5x2mi → 4x3mi → 3x4mi @ MP with 0.5mi float
        let mpWeek = weekInPhase / 4
        let progression = min(mpWeek, 2)

        let (reps, repMiles, name): (Int, Double, String)
        let floatMiles = 0.5 // Always 0.5mi float recovery

        switch progression {
        case 0:
            // 5 x 2mi @ MP w/.5mi float (~14.5mi total)
            (reps, repMiles, name) = (5, 2.0, "5 x 2mi @ MP")
        case 1:
            // 4 x 3mi @ MP w/.5mi float (~17.5mi total)
            (reps, repMiles, name) = (4, 3.0, "4 x 3mi @ MP")
        default:
            // 3 x 4mi @ MP w/.5mi float (~17mi total)
            (reps, repMiles, name) = (3, 4.0, "3 x 4mi @ MP")
        }

        for i in 0 ..< reps {
            steps.append(CanovaWorkoutStep(id: UUID(), stepType: .active, durationType: .distanceMiles, durationValue: repMiles, targetPaceIntensity: PaceIntensity(percentage: 100), notes: "\(Int(repMiles))mi @ MP - rep \(i + 1)", order: order))
            order += 1

            if i < reps - 1 {
                steps.append(CanovaWorkoutStep(id: UUID(), stepType: .recovery, durationType: .distanceMiles, durationValue: floatMiles, targetPaceIntensity: PaceIntensity(percentage: 80), notes: "Float recovery", order: order))
                order += 1
            }
        }

        // Cooldown
        steps.append(CanovaWorkoutStep(id: UUID(), stepType: .cooldown, durationType: .distanceMiles, durationValue: 2.0, targetPaceIntensity: PaceIntensity(percentage: 65), notes: "Easy cool-down", order: order))

        let workoutMiles = Double(reps) * repMiles + Double(reps - 1) * floatMiles
        let totalMiles = 4.0 + workoutMiles

        return CanovaWorkout(
            id: UUID(),
            name: "MP Long Run: \(name)",
            category: .specific,
            trainingPhase: .specific,
            description: "Marathon pace repeats with 0.5mi float recovery",
            steps: steps,
            totalDistanceMiles: totalMiles,
            estimatedDurationMinutes: totalMiles * 7.5,
            signatureType: .longRunWithTempo,
            createdAt: Date()
        )
    }

    /// Helper for adding workouts to rest days with default distances
    private func generateWorkoutForType(
        type: ScheduledWorkoutType,
        phase: CanovaTrainingPhase,
        goalTime: Int
    ) -> CanovaWorkout {
        switch type {
        case .tempo:
            return createTempoWorkout(phase: phase, goalTime: goalTime, totalMiles: 10.0)
        case .intervals:
            return createIntervalsWorkout(phase: phase, goalTime: goalTime, totalMiles: 10.0)
        case .progression:
            return createProgressionWorkout(phase: phase, goalTime: goalTime, totalMiles: 8.0)
        case .strides:
            return createStridesWorkout(phase: phase, goalTime: goalTime, totalMiles: 6.0)
        case .longRun:
            return createLongRunWorkout(phase: phase, goalTime: goalTime, totalMiles: 16.0)
        case .easy:
            return createEasyRunWorkout(phase: phase, goalTime: goalTime, totalMiles: 6.0)
        case .recovery:
            return createRecoveryWorkout(phase: phase, goalTime: goalTime, totalMiles: 4.0)
        default:
            return createEasyRunWorkout(phase: phase, goalTime: goalTime, totalMiles: 5.0)
        }
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
            isSaving = false
            errorMessage = "Failed to save changes"
            showError = true
        }
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

        // Swap workout data but keep dates
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
    func addWorkoutToRestDay(_ restDay: ScheduledWorkout, workoutType: ScheduledWorkoutType) async {
        guard restDay.isRestDay else { return }

        var updated = restDay
        updated.workoutType = workoutType
        updated.workout = generateWorkoutForType(
            type: workoutType,
            phase: currentPhase,
            goalTime: activePlan?.targetTimeSeconds ?? marathonGoalTime ?? 14400
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
            errorMessage = "Failed to delete plan"
            showError = true
        }
    }

    // MARK: - Navigation

    func goToPreviousWeek() {
        if selectedWeek > 1 {
            selectedWeek -= 1
        }
    }

    func goToNextWeek() {
        if let plan = activePlan, selectedWeek < plan.totalWeeks {
            selectedWeek += 1
        }
    }

    func goToPreviousMonth() {
        if selectedMonth > 1 {
            selectedMonth -= 1
        } else {
            selectedMonth = 12
            selectedYear -= 1
        }
    }

    func goToNextMonth() {
        if selectedMonth < 12 {
            selectedMonth += 1
        } else {
            selectedMonth = 1
            selectedYear += 1
        }
    }

    func goToCurrentWeek() {
        guard let plan = activePlan else { return }
        selectedWeek = plan.currentWeek
    }

    func goToCurrentMonth() {
        let calendar = Calendar.current
        let today = Date()
        selectedMonth = calendar.component(.month, from: today)
        selectedYear = calendar.component(.year, from: today)
    }

    private func initializeSelectedWeek() {
        guard let plan = activePlan else { return }
        selectedWeek = min(plan.currentWeek, plan.totalWeeks)
    }

    private func initializeSelectedMonth() {
        let calendar = Calendar.current
        if let plan = activePlan {
            // Set to the month of the plan's current position
            let today = Date()
            if today >= plan.startDate, today <= plan.endDate {
                selectedMonth = calendar.component(.month, from: today)
                selectedYear = calendar.component(.year, from: today)
            } else {
                selectedMonth = calendar.component(.month, from: plan.startDate)
                selectedYear = calendar.component(.year, from: plan.startDate)
            }
        }
    }

    func isSelectedDate(_ date: Date) -> Bool {
        guard let selected = selectedDate else { return false }
        return Calendar.current.isDate(date, inSameDayAs: selected)
    }

    // MARK: - Helper Methods

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

        marathonGoalTime = 4 * 3600
    }

    private func calculateWeeksUntilRace(for goal: UserGoal) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let targetDate = calendar.startOfDay(for: goal.targetDate)
        let weeks = calendar.dateComponents([.weekOfYear], from: today, to: targetDate).weekOfYear ?? 0
        weeksUntilRace = max(0, weeks)
    }

    /// Get workout for a specific date in the month view
    func workout(for day: Int) -> ScheduledWorkout? {
        let calendar = Calendar.current
        guard let date = calendar.date(from: DateComponents(year: selectedYear, month: selectedMonth, day: day)) else {
            return nil
        }
        return allScheduledWorkouts.first { calendar.isDate($0.date, inSameDayAs: date) }
    }

    // MARK: - Import Week from Text

    @MainActor
    func parseWeekFromText(_ text: String) async {
        isParsingImport = true
        importError = nil
        importedWorkouts = nil

        let goalTime = activePlan?.targetTimeSeconds ?? marathonGoalTime ?? 14400
        let raceDistance = activePlan?.targetRaceDistance ?? "marathon"

        let body: [String: Any] = [
            "text": text,
            "goalTimeSeconds": goalTime,
            "raceDistance": raceDistance,
            "currentPhase": currentPhase.rawValue,
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
        guard let imported = importedWorkouts else { return }
        isSaving = true

        let weekWorkouts = currentWeekWorkouts

        for importedDay in imported {
            guard let scheduled = weekWorkouts.first(where: { $0.dayOfWeek == importedDay.dayOfWeek }) else {
                continue
            }

            if importedDay.workoutType == "rest" {
                await convertToRestDay(scheduled)
            } else {
                let workout = importedDay.toCanovaWorkout(phase: currentPhase)
                let workoutType = ScheduledWorkoutType.fromImportString(importedDay.workoutType)

                var updated = scheduled
                updated.workout = workout
                updated.workoutType = workoutType
                updated.status = .modified
                await updateWorkout(updated)
            }
        }

        importedWorkouts = nil
        isSaving = false
    }
}

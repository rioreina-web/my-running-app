//
//  TrainingPlanViewModel.swift
//  RunningLog
//
//  Thin view model holding UI/navigation state. Data operations are
//  delegated to TrainingPlanService.
//

import Foundation
import SwiftUI

// MARK: - TrainingPlanViewModel

@Observable
final class TrainingPlanViewModel {
    // MARK: - Service

    let service = TrainingPlanService()

    // MARK: - Navigation State

    var selectedWeek: Int = 1
    var selectedMonth: Int = Calendar.current.component(.month, from: Date())
    var selectedYear: Int = Calendar.current.component(.year, from: Date())
    var selectedDate: Date?

    // MARK: - Services

    @ObservationIgnored private(set) lazy var importService = PlanImportService(viewModel: self)

    // MARK: - Forwarded Data State

    var activePlan: TrainingPlan? {
        get { service.activePlan }
        set { service.activePlan = newValue }
    }

    var allScheduledWorkouts: [ScheduledWorkout] {
        get { service.allScheduledWorkouts }
        set { service.allScheduledWorkouts = newValue }
    }

    var moodByDate: [String: String] {
        get { service.moodByDate }
        set { service.moodByDate = newValue }
    }

    var logDistanceByDate: [String: Double] {
        get { service.logDistanceByDate }
        set { service.logDistanceByDate = newValue }
    }

    var activeGoal: UserGoal? {
        get { service.activeGoal }
        set { service.activeGoal = newValue }
    }

    var marathonGoalTime: Int? {
        get { service.marathonGoalTime }
        set { service.marathonGoalTime = newValue }
    }

    var weeksUntilRace: Int {
        get { service.weeksUntilRace }
        set { service.weeksUntilRace = newValue }
    }

    var paceConfig: PaceConfigManager { service.paceConfig }

    var isLoadingPlan: Bool {
        get { service.isLoadingPlan }
        set { service.isLoadingPlan = newValue }
    }

    var isGeneratingPlan: Bool {
        get { service.isGeneratingPlan }
        set { service.isGeneratingPlan = newValue }
    }

    var isSaving: Bool {
        get { service.isSaving }
        set { service.isSaving = newValue }
    }

    var errorMessage: String? {
        get { service.errorMessage }
        set { service.errorMessage = newValue }
    }

    var showError: Bool {
        get { service.showError }
        set { service.showError = newValue }
    }

    static var useLocalMode: Bool {
        get { TrainingPlanService.useLocalMode }
        set { TrainingPlanService.useLocalMode = newValue }
    }

    // MARK: - Computed Properties

    var racePaceSecondsPerMile: Double? {
        service.racePaceSecondsPerMile
    }

    var equivalentPaces: EquivalentPaces? {
        service.equivalentPaces
    }

    var currentPhase: TrainingPhase {
        _ = paceConfig.phaseOverrideVersion
        if let override = paceConfig.phaseOverride(for: selectedWeek) {
            return override
        }
        guard let plan = activePlan else {
            return TrainingPhase.fromWeeksOut(weeksUntilRace)
        }
        let weeksOut = plan.totalWeeks - selectedWeek
        return TrainingPhase.fromWeeksOut(weeksOut)
    }

    var currentWeekWorkouts: [ScheduledWorkout] {
        allScheduledWorkouts
            .filter { $0.weekNumber == selectedWeek }
            .sorted { $0.date == $1.date ? $0.session < $1.session : $0.date < $1.date }
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
            phase: TrainingPhase.fromWeeksOut(weeksOut),
            startDate: firstDay,
            endDate: lastDay,
            scheduledWorkouts: weekWorkouts
        )
    }

    var monthLeadingEmptyCells: Int {
        let calendar = Calendar.current
        guard let firstOfMonth = calendar.date(from: DateComponents(year: selectedYear, month: selectedMonth, day: 1)) else {
            return 0
        }
        let weekday = calendar.component(.weekday, from: firstOfMonth)
        return (weekday + 5) % 7
    }

    var daysInMonth: Int {
        let calendar = Calendar.current
        guard let date = calendar.date(from: DateComponents(year: selectedYear, month: selectedMonth, day: 1)),
              let range = calendar.range(of: .day, in: .month, for: date)
        else { return 30 }
        return range.count
    }

    // MARK: - Delegated Data Methods

    @MainActor
    func loadActivePlan() async {
        await service.loadActivePlan { [self] in
            initializeSelectedWeek()
            initializeSelectedMonth()
        }
        // If no plan was loaded, load mood data for current month
        if activePlan == nil && !isLoadingPlan {
            await loadMoodDataForCurrentMonth()
        }
    }

    @MainActor
    func loadMoodDataForCurrentMonth() async {
        await service.loadMoodDataForMonth(year: selectedYear, month: selectedMonth)
    }

    @MainActor
    func loadLogEntries(for date: Date) async -> [TrainingLog] {
        await service.loadLogEntries(for: date)
    }

    func archiveExistingPlans() async throws {
        try await service.archiveExistingPlans()
    }

    @MainActor
    func updateWorkout(_ workout: ScheduledWorkout) async {
        await service.updateWorkout(workout)
    }

    @MainActor
    func insertScheduledWorkout(_ insert: ScheduledWorkoutInsert) async -> ScheduledWorkout? {
        await service.insertScheduledWorkout(insert)
    }

    @MainActor
    func markWorkoutComplete(_ workout: ScheduledWorkout, linkedWorkoutId: UUID? = nil) async {
        await service.markWorkoutComplete(workout, linkedWorkoutId: linkedWorkoutId)
    }

    @MainActor
    func markWorkoutSkipped(_ workout: ScheduledWorkout) async {
        await service.markWorkoutSkipped(workout)
    }

    @MainActor
    func swapWorkouts(_ workout1: ScheduledWorkout, with workout2: ScheduledWorkout) async {
        await service.swapWorkouts(workout1, with: workout2)
    }

    @MainActor
    func convertToRestDay(_ workout: ScheduledWorkout) async {
        await service.convertToRestDay(workout)
    }

    @MainActor
    func addWorkoutToRestDay(_ restDay: ScheduledWorkout, workoutType: ScheduledWorkoutType) async {
        await service.addWorkoutToRestDay(restDay, workoutType: workoutType, phase: currentPhase)
    }

    @MainActor
    func deletePlan() async {
        await service.deletePlan()
    }

    // MARK: - View-Only Lookups

    func mood(for day: Int) -> String? {
        service.moodForDay(day, year: selectedYear, month: selectedMonth)
    }

    func mood(for date: Date) -> String? {
        service.moodForDate(date)
    }

    func logDistance(for day: Int) -> Double? {
        service.logDistanceForDay(day, year: selectedYear, month: selectedMonth)
    }

    func workout(for day: Int) -> ScheduledWorkout? {
        service.workoutForDay(day, year: selectedYear, month: selectedMonth)
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
        if activePlan == nil {
            Task { await loadMoodDataForCurrentMonth() }
        }
    }

    func goToNextMonth() {
        if selectedMonth < 12 {
            selectedMonth += 1
        } else {
            selectedMonth = 1
            selectedYear += 1
        }
        if activePlan == nil {
            Task { await loadMoodDataForCurrentMonth() }
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

    func initializeSelectedWeek() {
        guard let plan = activePlan else { return }
        selectedWeek = min(plan.currentWeek, plan.totalWeeks)
    }

    func initializeSelectedMonth() {
        let calendar = Calendar.current
        if let plan = activePlan {
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
}

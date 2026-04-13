//
//  TrainingPlanView.swift
//  RunningLog
//
//  Main view for the training plan calendar system.
//

import SwiftUI

// MARK: - TrainingPlanView

struct TrainingPlanView: View {
    @EnvironmentObject private var healthKitManager: HealthKitManager
    @State private var viewModel = TrainingPlanViewModel()
    @State private var viewMode: CalendarViewMode = .week
    @State private var showPlanGenerator = false
    @State private var selectedWorkout: ScheduledWorkout?
    @State private var showPlanSettings = false
    @State private var showImportWeek = false
    @State private var showImportPlan = false
    @State private var selectedLogEntry: TrainingLog?
    @State private var dayLogEntries: [TrainingLog] = []
    @State private var showDayLogPicker = false
    @State private var showWeeklyReport = false
    @State private var showReschedule = false

    var body: some View {
        ZStack {
            DripBackground()

            if viewModel.isLoadingPlan {
                LoadingPlanView()
            } else {
                ScrollView {
                    VStack(spacing: 20) {
                        // Plan header (only when plan exists)
                        if let plan = viewModel.activePlan {
                            PlanHeaderBanner(plan: plan)
                                .padding(.horizontal, 20)
                                .padding(.top, 8)
                        }

                        // View mode toggle (only when plan exists — week view needs a plan)
                        if viewModel.activePlan != nil {
                            CalendarViewModeToggle(selectedMode: $viewMode)
                                .padding(.horizontal, 20)
                        }

                        // Calendar content
                        if viewModel.activePlan != nil, viewMode == .week {
                            WeekCalendarView(
                                viewModel: viewModel,
                                onDayTap: { workout in
                                    selectedWorkout = workout
                                }
                            )
                        } else {
                            MonthCalendarView(
                                viewModel: viewModel,
                                onDayTap: { workout in
                                    selectedWorkout = workout
                                },
                                onLogDayTap: { day in
                                    Task {
                                        guard let date = Calendar.current.date(from: DateComponents(
                                            year: viewModel.selectedYear,
                                            month: viewModel.selectedMonth,
                                            day: day
                                        )) else { return }
                                        var entries = await viewModel.loadLogEntries(for: date)

                                        // Fallback: if no training logs, check HealthKit
                                        if entries.isEmpty {
                                            let hkWorkouts = await healthKitManager.fetchRunningWorkouts(for: date)
                                            entries = hkWorkouts.map { w in
                                                TrainingLog(
                                                    id: w.id,
                                                    createdAt: w.startDate,
                                                    audioUrl: nil,
                                                    notes: nil,
                                                    cleanedNotes: nil,
                                                    mood: nil,
                                                    workoutDate: w.startDate,
                                                    workoutDistanceMiles: w.distanceMiles,
                                                    workoutDurationMinutes: w.durationMinutes,
                                                    processingStatus: nil,
                                                    processingError: nil,
                                                    processingAttempts: nil,
                                                    transcriptUrl: nil,
                                                    coachInsight: nil,
                                                    workoutNotes: nil,
                                                    workoutPacePerMile: w.formattedPace,
                                                    workoutType: "run",
                                                    source: nil,
                                                    vitalWorkoutId: nil,
                                                    paceSegments: nil
                                                )
                                            }
                                        }

                                        if entries.count == 1 {
                                            selectedLogEntry = entries.first
                                        } else if entries.count > 1 {
                                            dayLogEntries = entries
                                            showDayLogPicker = true
                                        }
                                    }
                                }
                            )
                        }

                        // Inline prompt when no plan
                        if viewModel.activePlan == nil {
                            VStack(spacing: 12) {
                                Text("No training plan active")
                                    .font(.dripCaption(12))
                                    .foregroundStyle(Color.drip.textSecondary)

                                DripButton("New Plan", icon: "plus.circle", style: .primary) {
                                    showPlanGenerator = true
                                }

                                DripButton("Import Plan", icon: "square.and.arrow.down", style: .secondary) {
                                    showImportPlan = true
                                }
                            }
                            .padding(.horizontal, 20)
                        }

                        Spacer()
                            .frame(height: 100)
                    }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                SidebarMenuButton()
            }
            ToolbarItem(placement: .principal) {
                Text("TRAINING PLAN")
                    .font(.dripCaption(12))
                    .foregroundStyle(Color.drip.textSecondary)
                    .tracking(2)
            }
            ToolbarItem(placement: .topBarTrailing) {
                if viewModel.activePlan != nil {
                    Menu {
                        Button {
                            showPlanGenerator = true
                        } label: {
                            Label("New Plan", systemImage: "plus.circle")
                        }

                        Button {
                            showImportPlan = true
                        } label: {
                            Label("Import Plan", systemImage: "square.and.arrow.down")
                        }

                        Button {
                            showImportWeek = true
                        } label: {
                            Label("Import Week", systemImage: "doc.text")
                        }

                        Divider()

                        Button {
                            showReschedule = true
                        } label: {
                            Label("AI Reschedule", systemImage: "sparkles")
                        }

                        Button {
                            showWeeklyReport = true
                        } label: {
                            Label("Weekly Analysis", systemImage: "waveform.path.ecg")
                        }

                        Button(role: .destructive) {
                            showPlanSettings = true
                        } label: {
                            Label("Delete Plan", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.drip.textSecondary)
                    }
                }
            }
        }
        .toolbarBackground(Color.drip.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .onAppear {
            Task {
                await viewModel.loadActivePlan()
            }
        }
        .sheet(isPresented: $showPlanGenerator) {
            PlanGeneratorSheet(viewModel: viewModel) {
                showPlanGenerator = false
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showImportWeek) {
            ImportWeekSheet(
                viewModel: viewModel,
                importService: viewModel.importService,
                initialWeekNumber: viewModel.selectedWeek
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showImportPlan) {
            ImportTrainingPlanSheet(viewModel: viewModel, importService: viewModel.importService)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedWorkout) { workout in
            DayDetailSheet(
                viewModel: viewModel,
                scheduledWorkout: workout,
                racePaceSeconds: viewModel.racePaceSecondsPerMile ?? 480
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedLogEntry) { entry in
            HistoryDetailSheet(entry: entry) {
                Task { await viewModel.loadMoodDataForCurrentMonth() }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showDayLogPicker) {
            DayLogPickerSheet(entries: dayLogEntries) { entry in
                showDayLogPicker = false
                selectedLogEntry = entry
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showWeeklyReport) {
            WeeklyCoachingReportSheet()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showReschedule) {
            RescheduleSheet(viewModel: viewModel, initialScope: .remainingPlan)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .alert("Delete Training Plan", isPresented: $showPlanSettings) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task {
                    await viewModel.deletePlan()
                }
            }
        } message: {
            Text("Are you sure you want to delete this training plan? This action cannot be undone.")
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "An error occurred")
        }
    }
}

// MARK: - Loading Plan View

struct LoadingPlanView: View {
    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(Color.drip.coral)

            Text("Loading your training plan...")
                .font(.dripBody(14))
                .foregroundStyle(Color.drip.textSecondary)
        }
    }
}

// MARK: - Day Log Picker Sheet

struct DayLogPickerSheet: View {
    let entries: [TrainingLog]
    let onSelect: (TrainingLog) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(entries) { entry in
                Button {
                    onSelect(entry)
                } label: {
                    HStack(spacing: 12) {
                        if let mood = entry.mood {
                            MoodBadge(mood: mood)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            if let type = entry.workoutType {
                                Text(type.capitalized)
                                    .font(.dripLabel(14))
                                    .foregroundStyle(Color.drip.textPrimary)
                            }

                            HStack(spacing: 8) {
                                if let miles = entry.workoutDistanceMiles, miles > 0 {
                                    Text(String(format: "%.1f mi", miles))
                                        .font(.dripCaption(12))
                                        .foregroundStyle(Color.drip.textSecondary)
                                }
                                if let mins = entry.workoutDurationMinutes, mins > 0 {
                                    Text(String(format: "%.0f min", mins))
                                        .font(.dripCaption(12))
                                        .foregroundStyle(Color.drip.textSecondary)
                                }
                            }
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.drip.textTertiary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .listStyle(.plain)
            .navigationTitle("Workouts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.drip.coral)
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        TrainingPlanView()
    }
}

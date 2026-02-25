//
//  TrainingDashboardView.swift
//  RunningLog
//
//  Training dashboard — weekly stats, plan overview, recent activity,
//  training logs, race predictions, and AI analysis link.
//

import Supabase
import SwiftUI

// MARK: - TrainingDashboardView

struct TrainingDashboardView: View {
    @ObservedObject private var healthKitManager = HealthKitManager.shared
    @State private var trainingPlanVM = TrainingPlanViewModel()
    @State private var fitnessService = FitnessPredictorService()

    // Data
    @State private var healthKitWorkouts: [RunningWorkout] = []
    @State private var trainingLogs: [TrainingLog] = []
    @State private var isLoadingWorkouts = false
    @State private var isLoadingLogs = false

    // Navigation
    @State private var selectedWorkout: RunningWorkout?
    @State private var selectedLogEntry: HistoryLogEntry?
    @State private var showAnalysis = false

    var body: some View {
        ZStack {
            DripBackground()

            ScrollView {
                VStack(spacing: 24) {

                    // MARK: Weekly Stats
                    if !healthKitWorkouts.isEmpty {
                        WeeklyStatsHeader(workouts: healthKitWorkouts)
                            .padding(.horizontal, 20)
                            .padding(.top, 8)
                    }

                    // MARK: This Week's Plan
                    if let plan = trainingPlanVM.activePlan {
                        thisWeekPlanSection(plan: plan)
                    }

                    // MARK: Recent Activity (HealthKit)
                    recentActivitySection

                    // MARK: Training Logs
                    trainingLogsSection

                    // MARK: Race Predictions
                    racePredictionsSection

                    // MARK: AI Analysis Link
                    analysisLinkCard

                    Spacer()
                        .frame(height: 40)
                }
            }
            .refreshable {
                await loadAll()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                SidebarMenuButton()
            }
            ToolbarItem(placement: .principal) {
                Text("TRAINING")
                    .font(.dripCaption(12))
                    .foregroundStyle(Color.drip.textSecondary)
                    .tracking(2)
            }
        }
        .toolbarBackground(Color.drip.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .task {
            await loadAll()
        }
        .sheet(item: $selectedWorkout) { workout in
            WorkoutDetailSheet(workout: workout)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedLogEntry) { entry in
            HistoryDetailSheet(entry: entry) {
                Task { await loadTrainingLogs() }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: $showAnalysis) {
            NavigationStack {
                AnalysisView()
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                showAnalysis = false
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(Color.drip.textSecondary)
                            }
                        }
                    }
            }
        }
    }

    // MARK: - This Week's Plan Section

    @ViewBuilder
    private func thisWeekPlanSection(plan: TrainingPlan) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(plan.name)
                        .font(.dripLabel(15))
                        .foregroundStyle(Color.drip.textPrimary)
                        .lineLimit(1)

                    Text("Week \(plan.currentWeek) of \(plan.totalWeeks)")
                        .font(.dripCaption(11))
                        .foregroundStyle(Color.drip.textSecondary)
                }

                Spacer()

                Text("\(plan.daysRemaining)d left")
                    .font(.dripCaption(11))
                    .foregroundStyle(Color.drip.coral)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.drip.coral.opacity(0.15))
                    .clipShape(Capsule())
            }

            // Horizontal scroll of this week's workouts
            let weekWorkouts = trainingPlanVM.currentWeekWorkouts
            if !weekWorkouts.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(weekWorkouts) { workout in
                            ScheduledWorkoutMiniCard(workout: workout)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.drip.divider, lineWidth: 1)
        )
        .padding(.horizontal, 20)
    }

    // MARK: - Recent Activity Section

    @ViewBuilder
    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Recent Activity")
                .padding(.horizontal, 20)

            if !healthKitManager.isAuthorized {
                ConnectHealthCard {
                    Task {
                        _ = await healthKitManager.requestAuthorization()
                        await loadHealthKitWorkouts()
                    }
                }
                .padding(.horizontal, 20)
            } else if isLoadingWorkouts && healthKitWorkouts.isEmpty {
                HStack {
                    Spacer()
                    ProgressView().tint(Color.drip.coral)
                    Spacer()
                }
                .padding(.vertical, 20)
            } else if healthKitWorkouts.isEmpty {
                emptyCard(icon: "figure.run", message: "No recent runs")
                    .padding(.horizontal, 20)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(healthKitWorkouts.prefix(5)) { workout in
                        WorkoutCard(workout: workout)
                            .onTapGesture {
                                selectedWorkout = workout
                            }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    // MARK: - Training Logs Section

    @ViewBuilder
    private var trainingLogsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Training Logs")
                .padding(.horizontal, 20)

            if isLoadingLogs && trainingLogs.isEmpty {
                HStack {
                    Spacer()
                    ProgressView().tint(Color.drip.coral)
                    Spacer()
                }
                .padding(.vertical, 20)
            } else if trainingLogs.isEmpty {
                emptyCard(icon: "text.bubble", message: "No training logs yet")
                    .padding(.horizontal, 20)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(trainingLogs.filter(\.isCompleted).prefix(5), id: \.id) { log in
                        HistoryEntryCard(entry: log.asHistoryEntry)
                            .onTapGesture {
                                selectedLogEntry = log.asHistoryEntry
                            }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    // MARK: - Race Predictions Section

    @ViewBuilder
    private var racePredictionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Race Predictions")
                .padding(.horizontal, 20)

            if let predictions = fitnessService.predictions {
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        Image(systemName: "trophy.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.drip.coral)

                        Text("Predicted Race Times")
                            .font(.dripLabel(14))
                            .foregroundStyle(Color.drip.textPrimary)

                        Spacer()

                        Text(predictions.dataSources.confidence)
                            .font(.dripCaption(10))
                            .foregroundStyle(confidenceColor(predictions.dataSources.confidence))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(confidenceColor(predictions.dataSources.confidence).opacity(0.15))
                            .clipShape(Capsule())
                    }
                    .padding(16)

                    Divider().background(Color.drip.divider)

                    // Race times
                    HStack(spacing: 0) {
                        ForEach(predictions.races.prefix(3)) { race in
                            VStack(spacing: 6) {
                                Text(race.distance)
                                    .font(.dripCaption(10))
                                    .foregroundStyle(Color.drip.textSecondary)
                                    .tracking(1)

                                Text(race.time)
                                    .font(.dripStat(16))
                                    .foregroundStyle(Color.drip.textPrimary)

                                Text(race.pace)
                                    .font(.dripCaption(10))
                                    .foregroundStyle(Color.drip.textTertiary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(16)
                }
                .background(Color.drip.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.drip.divider, lineWidth: 1)
                )
                .padding(.horizontal, 20)
            } else if fitnessService.isAnalyzing {
                HStack(spacing: 10) {
                    ProgressView().tint(Color.drip.coral).scaleEffect(0.8)
                    Text("Analyzing your fitness...")
                        .font(.dripCaption(12))
                        .foregroundStyle(Color.drip.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(Color.drip.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 20)
            } else {
                emptyCard(icon: "trophy", message: "Not enough data for predictions")
                    .padding(.horizontal, 20)
            }
        }
    }

    // MARK: - Analysis Link Card

    @ViewBuilder
    private var analysisLinkCard: some View {
        Button {
            showAnalysis = true
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.drip.coral.opacity(0.15))
                        .frame(width: 40, height: 40)

                    Image(systemName: "chart.xyaxis.line")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.drip.coral)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Training Analysis")
                        .font(.dripLabel(15))
                        .foregroundStyle(Color.drip.textPrimary)

                    Text("View detailed trends & insights")
                        .font(.dripCaption(11))
                        .foregroundStyle(Color.drip.textTertiary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.drip.textTertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(Color.drip.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
    }

    // MARK: - Empty Card

    @ViewBuilder
    private func emptyCard(icon: String, message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(Color.drip.textTertiary)
            Text(message)
                .font(.dripCaption(12))
                .foregroundStyle(Color.drip.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Data Loading

    private func loadAll() async {
        // Load workouts, logs, and plan concurrently
        async let workouts: () = loadHealthKitWorkouts()
        async let logs: () = loadTrainingLogs()
        async let plan: () = loadActivePlan()
        _ = await (workouts, logs, plan)
        // Predictions depend on plan being loaded
        await loadPredictions()
    }

    private func loadHealthKitWorkouts() async {
        await MainActor.run { isLoadingWorkouts = true }
        let workouts = await healthKitManager.fetchRecentRunningWorkouts(limit: 30)
        await MainActor.run {
            healthKitWorkouts = workouts
            healthKitManager.recentWorkouts = workouts
            isLoadingWorkouts = false
        }
    }

    private func loadTrainingLogs() async {
        await MainActor.run { isLoadingLogs = true }
        do {
            let logs: [TrainingLog] = try await supabase
                .from("training_logs")
                .select()
                .order("created_at", ascending: false)
                .limit(20)
                .execute()
                .value

            await MainActor.run {
                trainingLogs = logs
                isLoadingLogs = false
            }
        } catch {
            await MainActor.run { isLoadingLogs = false }
        }
    }

    private func loadActivePlan() async {
        await trainingPlanVM.loadActivePlan()
    }

    private func loadPredictions() async {
        await fitnessService.predictFitness(
            plan: trainingPlanVM.activePlan,
            healthKitManager: healthKitManager
        )
    }

    private func confidenceColor(_ confidence: String) -> Color {
        switch confidence.lowercased() {
        case "high": Color.drip.energized
        case "medium": Color.drip.tired
        default: Color.drip.textSecondary
        }
    }
}

// MARK: - ScheduledWorkoutMiniCard

struct ScheduledWorkoutMiniCard: View {
    let workout: ScheduledWorkout

    var body: some View {
        VStack(spacing: 8) {
            // Day name
            Text(workout.shortDayName.uppercased())
                .font(.dripCaption(10))
                .foregroundStyle(workout.isToday ? Color.drip.coral : Color.drip.textSecondary)
                .tracking(0.8)

            // Type icon
            ZStack {
                Circle()
                    .fill(workout.workoutType.color.opacity(0.15))
                    .frame(width: 36, height: 36)

                Image(systemName: workout.workoutType.icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(workout.workoutType.color)
            }

            // Workout name
            Text(workout.workoutType.shortName)
                .font(.dripCaption(10))
                .foregroundStyle(Color.drip.textPrimary)
                .lineLimit(1)

            // Distance (if workout data available)
            if let w = workout.workout, let dist = w.totalDistanceMiles {
                Text(String(format: "%.0fmi", dist))
                    .font(.dripCaption(9))
                    .foregroundStyle(Color.drip.textTertiary)
            }

            // Completion indicator
            if workout.status == .completed {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.drip.energized)
            }
        }
        .frame(width: 72)
        .padding(.vertical, 10)
        .background(
            workout.isToday
                ? Color.drip.coral.opacity(0.1)
                : Color.drip.cardBackgroundElevated
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    workout.isToday ? Color.drip.coral.opacity(0.4) : Color.clear,
                    lineWidth: 1
                )
        )
    }
}

#Preview {
    NavigationStack {
        TrainingDashboardView()
    }
}

//
//  TrainingPlanView.swift
//  RunningLog
//
//  Main view for the training plan calendar system.
//

import SwiftUI

// MARK: - TrainingPlanView

struct TrainingPlanView: View {
    @State private var viewModel = TrainingPlanViewModel()
    @State private var viewMode: CalendarViewMode = .week
    @State private var showPlanGenerator = false
    @State private var selectedWorkout: ScheduledWorkout?
    @State private var showPlanSettings = false
    @State private var showImportWeek = false

    var body: some View {
        ZStack {
            DripBackground()

            if viewModel.isLoadingPlan {
                LoadingPlanView()
            } else if viewModel.activePlan == nil {
                // No active plan - show empty state
                EmptyPlanState {
                    showPlanGenerator = true
                }
            } else {
                // Active plan exists
                ScrollView {
                    VStack(spacing: 20) {
                        // Plan header
                        if let plan = viewModel.activePlan {
                            PlanHeaderBanner(plan: plan)
                                .padding(.horizontal, 20)
                                .padding(.top, 8)
                        }

                        // View mode toggle
                        CalendarViewModeToggle(selectedMode: $viewMode)
                            .padding(.horizontal, 20)

                        // Calendar content
                        switch viewMode {
                        case .week:
                            WeekCalendarView(
                                viewModel: viewModel,
                                onDayTap: { workout in
                                    selectedWorkout = workout
                                }
                            )
                        case .month:
                            MonthCalendarView(
                                viewModel: viewModel,
                                onDayTap: { workout in
                                    selectedWorkout = workout
                                }
                            )
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
                            showImportWeek = true
                        } label: {
                            Label("Import Week", systemImage: "doc.text")
                        }

                        Button {
                            showPlanGenerator = true
                        } label: {
                            Label("New Plan", systemImage: "plus.circle")
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
            PlanGeneratorSheet(
                viewModel: viewModel,
                onGenerate: {
                    showPlanGenerator = false
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showImportWeek) {
            ImportWeekSheet(
                viewModel: viewModel,
                weekNumber: viewModel.selectedWeek
            )
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

// MARK: - Preview

#Preview {
    NavigationStack {
        TrainingPlanView()
    }
}

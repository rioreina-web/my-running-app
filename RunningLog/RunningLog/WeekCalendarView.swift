//
//  WeekCalendarView.swift
//  RunningLog
//
//  Week overview calendar showing 7 days of scheduled workouts.
//

import SwiftUI

// MARK: - WeekCalendarView

struct WeekCalendarView: View {
    @Bindable var viewModel: TrainingPlanViewModel
    let onDayTap: (ScheduledWorkout) -> Void

    var body: some View {
        VStack(spacing: 16) {
            // Week Navigation
            if let plan = viewModel.activePlan,
               let summary = viewModel.currentWeekSummary
            {
                WeekNavigationHeader(
                    weekNumber: viewModel.selectedWeek,
                    totalWeeks: plan.totalWeeks,
                    phase: viewModel.currentPhase,
                    dateRange: summary.dateRangeString,
                    onPrevious: { viewModel.goToPreviousWeek() },
                    onNext: { viewModel.goToNextWeek() }
                )
                .padding(.horizontal, 20)

                // Week Stats Summary
                WeekStatsSummary(summary: summary)
                    .padding(.horizontal, 20)
            }

            // Days List
            VStack(spacing: 8) {
                ForEach(viewModel.currentWeekWorkouts) { workout in
                    WeekDayCard(
                        workout: workout,
                        racePaceSeconds: viewModel.racePaceSecondsPerMile ?? 480
                    )
                    .onTapGesture { onDayTap(workout) }
                }
            }
            .padding(.horizontal, 20)

            // Today button if not viewing current week
            if let plan = viewModel.activePlan,
               viewModel.selectedWeek != plan.currentWeek
            {
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        viewModel.goToCurrentWeek()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 14))

                        Text("Go to Current Week")
                            .font(.dripLabel(13))
                    }
                    .foregroundStyle(Color.drip.coral)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.drip.coral.opacity(0.1))
                    .clipShape(Capsule())
                }
                .padding(.top, 8)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        DripBackground()

        WeekCalendarView(
            viewModel: TrainingPlanViewModel(),
            onDayTap: { _ in }
        )
    }
}

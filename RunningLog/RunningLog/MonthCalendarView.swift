//
//  MonthCalendarView.swift
//  RunningLog
//
//  Month grid calendar view showing scheduled workouts.
//

import SwiftUI

// MARK: - MonthCalendarView

struct MonthCalendarView: View {
    @Bindable var viewModel: TrainingPlanViewModel
    let onDayTap: (ScheduledWorkout) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    private let weekdaySymbols = ["M", "T", "W", "T", "F", "S", "S"]

    var body: some View {
        VStack(spacing: 16) {
            // Month Navigation
            MonthNavigationHeader(
                month: viewModel.selectedMonth,
                year: viewModel.selectedYear,
                onPrevious: { viewModel.goToPreviousMonth() },
                onNext: { viewModel.goToNextMonth() }
            )
            .padding(.horizontal, 20)

            // Weekday Headers
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.dripCaption(11))
                        .foregroundStyle(Color.drip.textTertiary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 20)

            // Calendar Grid
            LazyVGrid(columns: columns, spacing: 4) {
                // Leading empty cells for first week offset
                ForEach(0 ..< viewModel.monthLeadingEmptyCells, id: \.self) { _ in
                    Color.clear.frame(height: 60)
                }

                // Day cells
                ForEach(1 ... viewModel.daysInMonth, id: \.self) { day in
                    let workout = viewModel.workout(for: day)
                    let isInPlanRange = isDateInPlanRange(day: day)

                    MonthDayCell(
                        day: day,
                        workout: workout,
                        isSelected: isSelectedDay(day),
                        isInPlanRange: isInPlanRange
                    )
                    .onTapGesture {
                        if let workout = workout {
                            onDayTap(workout)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)

            // Month summary
            if let plan = viewModel.activePlan {
                MonthSummaryBar(
                    workouts: viewModel.currentMonthWorkouts,
                    plan: plan
                )
                .padding(.horizontal, 20)
            }

            // Today button if not viewing current month
            if !isCurrentMonth {
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        viewModel.goToCurrentMonth()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 14))

                        Text("Go to Today")
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

    private func isSelectedDay(_ day: Int) -> Bool {
        guard let selectedDate = viewModel.selectedDate else { return false }
        let calendar = Calendar.current
        guard let date = calendar.date(from: DateComponents(
            year: viewModel.selectedYear,
            month: viewModel.selectedMonth,
            day: day
        )) else { return false }
        return calendar.isDate(date, inSameDayAs: selectedDate)
    }

    private func isDateInPlanRange(day: Int) -> Bool {
        guard let plan = viewModel.activePlan else { return false }
        let calendar = Calendar.current
        guard let date = calendar.date(from: DateComponents(
            year: viewModel.selectedYear,
            month: viewModel.selectedMonth,
            day: day
        )) else { return false }
        return date >= plan.startDate && date <= plan.endDate
    }

    private var isCurrentMonth: Bool {
        let calendar = Calendar.current
        let today = Date()
        return viewModel.selectedMonth == calendar.component(.month, from: today) &&
            viewModel.selectedYear == calendar.component(.year, from: today)
    }
}

// MARK: - Month Summary Bar

struct MonthSummaryBar: View {
    let workouts: [ScheduledWorkout]
    let plan: TrainingPlan

    private var totalMiles: Double {
        workouts.compactMap { $0.workout?.totalDistanceKm }.reduce(0, +) / 1.60934
    }

    private var workoutCount: Int {
        workouts.filter { !$0.isRestDay }.count
    }

    private var completedCount: Int {
        workouts.filter { $0.status == .completed }.count
    }

    var body: some View {
        HStack(spacing: 0) {
            MonthSummaryItem(
                icon: "figure.run",
                value: String(format: "%.0f mi", totalMiles),
                label: "Planned"
            )

            Divider()
                .frame(height: 24)
                .background(Color.drip.divider)

            MonthSummaryItem(
                icon: "calendar",
                value: "\(workoutCount)",
                label: "Workouts"
            )

            Divider()
                .frame(height: 24)
                .background(Color.drip.divider)

            MonthSummaryItem(
                icon: "checkmark",
                value: "\(completedCount)",
                label: "Done"
            )
        }
        .padding(.vertical, 10)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Month Summary Item

struct MonthSummaryItem: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(Color.drip.coral)

            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.dripLabel(13))
                    .foregroundStyle(Color.drip.textPrimary)

                Text(label)
                    .font(.dripCaption(9))
                    .foregroundStyle(Color.drip.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        DripBackground()

        MonthCalendarView(
            viewModel: TrainingPlanViewModel(),
            onDayTap: { _ in }
        )
    }
}

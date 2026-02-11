//
//  CalendarComponents.swift
//  RunningLog
//
//  Shared UI components for training plan calendar views.
//

import SwiftUI

// MARK: - Plan Header Banner

struct PlanHeaderBanner: View {
    let plan: TrainingPlan

    var body: some View {
        VStack(spacing: 16) {
            // Plan name and status
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(plan.name)
                        .font(.dripLabel(18))
                        .foregroundStyle(Color.drip.textPrimary)

                    Text("\(plan.daysRemaining) days to race")
                        .font(.dripCaption(13))
                        .foregroundStyle(Color.drip.textSecondary)
                }

                Spacer()

                // Progress indicator
                ZStack {
                    Circle()
                        .stroke(Color.drip.divider, lineWidth: 4)
                        .frame(width: 50, height: 50)

                    Circle()
                        .trim(from: 0, to: CGFloat(plan.currentWeek) / CGFloat(plan.totalWeeks))
                        .stroke(Color.drip.coral, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .frame(width: 50, height: 50)
                        .rotationEffect(.degrees(-90))

                    VStack(spacing: 0) {
                        Text("\(plan.currentWeek)")
                            .font(.dripStat(14))
                            .foregroundStyle(Color.drip.coral)
                        Text("/\(plan.totalWeeks)")
                            .font(.dripCaption(9))
                            .foregroundStyle(Color.drip.textTertiary)
                    }
                }
            }

            // Goal stats
            HStack(spacing: 0) {
                PlanStatColumn(
                    label: "GOAL TIME",
                    value: plan.formattedGoalTime,
                    color: Color.drip.coral
                )

                Divider()
                    .frame(height: 30)
                    .background(Color.drip.divider)

                PlanStatColumn(
                    label: "RACE PACE",
                    value: plan.formattedRacePace,
                    color: Color.drip.energized
                )

                Divider()
                    .frame(height: 30)
                    .background(Color.drip.divider)

                PlanStatColumn(
                    label: "WEEKS",
                    value: "\(plan.totalWeeks)",
                    color: Color.drip.textPrimary
                )
            }
        }
        .padding(16)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.drip.coral.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Plan Stat Column

struct PlanStatColumn: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.dripCaption(9))
                .foregroundStyle(Color.drip.textTertiary)
                .tracking(0.5)

            Text(value)
                .font(.dripLabel(14))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Calendar View Mode Toggle

struct CalendarViewModeToggle: View {
    @Binding var selectedMode: CalendarViewMode

    var body: some View {
        HStack(spacing: 0) {
            ForEach(CalendarViewMode.allCases, id: \.self) { mode in
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        selectedMode = mode
                    }
                } label: {
                    Text(mode.rawValue)
                        .font(.dripLabel(14))
                        .foregroundStyle(selectedMode == mode ? Color.drip.textPrimary : Color.drip.textTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            selectedMode == mode
                                ? Color.drip.cardBackgroundElevated
                                : Color.clear
                        )
                }
            }
        }
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.drip.divider, lineWidth: 1)
        )
    }
}

// MARK: - Week Navigation Header

struct WeekNavigationHeader: View {
    let weekNumber: Int
    let totalWeeks: Int
    let phase: CanovaTrainingPhase
    let dateRange: String
    let onPrevious: () -> Void
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            // Navigation row
            HStack {
                Button(action: onPrevious) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(weekNumber > 1 ? Color.drip.coral : Color.drip.textTertiary)
                }
                .disabled(weekNumber <= 1)

                Spacer()

                VStack(spacing: 2) {
                    Text("WEEK \(weekNumber) OF \(totalWeeks)")
                        .font(.dripCaption(11))
                        .foregroundStyle(Color.drip.textSecondary)
                        .tracking(1.5)

                    Text(dateRange)
                        .font(.dripLabel(14))
                        .foregroundStyle(Color.drip.textPrimary)
                }

                Spacer()

                Button(action: onNext) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(weekNumber < totalWeeks ? Color.drip.coral : Color.drip.textTertiary)
                }
                .disabled(weekNumber >= totalWeeks)
            }

            // Phase badge
            HStack(spacing: 6) {
                Image(systemName: phase.icon)
                    .font(.system(size: 12))

                Text(phase.displayName)
                    .font(.dripCaption(11))
            }
            .foregroundStyle(phase.color)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(phase.color.opacity(0.15))
            .clipShape(Capsule())
        }
        .padding(16)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Month Navigation Header

struct MonthNavigationHeader: View {
    let month: Int
    let year: Int
    let onPrevious: () -> Void
    let onNext: () -> Void

    private var monthName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        let components = DateComponents(year: year, month: month, day: 1)
        if let date = Calendar.current.date(from: components) {
            return formatter.string(from: date)
        }
        return ""
    }

    var body: some View {
        HStack {
            Button(action: onPrevious) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.drip.coral)
            }

            Spacer()

            Text(monthName.uppercased())
                .font(.dripCaption(12))
                .foregroundStyle(Color.drip.textSecondary)
                .tracking(2)

            Spacer()

            Button(action: onNext) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.drip.coral)
            }
        }
        .padding(.horizontal, 8)
    }
}

// MARK: - Week Stats Summary

struct WeekStatsSummary: View {
    let summary: TrainingWeekSummary

    var body: some View {
        HStack(spacing: 0) {
            WeekStatItem(
                icon: "figure.run",
                value: String(format: "%.1f mi", summary.totalPlannedMiles),
                label: "Planned"
            )

            Divider()
                .frame(height: 30)
                .background(Color.drip.divider)

            WeekStatItem(
                icon: "calendar",
                value: "\(summary.workoutDays)",
                label: "Workouts"
            )

            Divider()
                .frame(height: 30)
                .background(Color.drip.divider)

            WeekStatItem(
                icon: "checkmark.circle",
                value: "\(summary.completedCount)/\(summary.workoutDays)",
                label: "Done"
            )
        }
        .padding(.vertical, 12)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Week Stat Item

struct WeekStatItem: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.drip.coral)

                Text(value)
                    .font(.dripLabel(14))
                    .foregroundStyle(Color.drip.textPrimary)
            }

            Text(label)
                .font(.dripCaption(10))
                .foregroundStyle(Color.drip.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Week Day Card

struct WeekDayCard: View {
    let workout: ScheduledWorkout
    let racePaceSeconds: Double

    var body: some View {
        HStack(spacing: 14) {
            // Day indicator
            VStack(spacing: 2) {
                Text(workout.shortDayName.uppercased())
                    .font(.dripCaption(10))
                    .foregroundStyle(Color.drip.textTertiary)

                Text("\(workout.dayNumber)")
                    .font(.dripStat(18))
                    .foregroundStyle(workout.isToday ? Color.drip.coral : Color.drip.textPrimary)
            }
            .frame(width: 44)

            // Workout info
            if workout.isRestDay {
                RestDayContent()
            } else {
                WorkoutDayContent(
                    workout: workout,
                    racePaceSeconds: racePaceSeconds
                )
            }

            Spacer()

            // Status indicator
            StatusBadge(status: workout.status)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.drip.textTertiary)
        }
        .padding(14)
        .background(
            workout.isToday
                ? Color.drip.coral.opacity(0.08)
                : Color.drip.cardBackground
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    workout.isToday ? Color.drip.coral.opacity(0.3) : Color.drip.divider,
                    lineWidth: 1
                )
        )
    }
}

// MARK: - Rest Day Content

struct RestDayContent: View {
    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.drip.textTertiary.opacity(0.15))
                    .frame(width: 36, height: 36)

                Image(systemName: "bed.double.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.drip.textTertiary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Rest Day")
                    .font(.dripLabel(14))
                    .foregroundStyle(Color.drip.textSecondary)

                Text("Recovery & adaptation")
                    .font(.dripCaption(11))
                    .foregroundStyle(Color.drip.textTertiary)
            }
        }
    }
}

// MARK: - Workout Day Content

struct WorkoutDayContent: View {
    let workout: ScheduledWorkout
    let racePaceSeconds: Double

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(workout.workoutType.color.opacity(0.15))
                    .frame(width: 36, height: 36)

                Image(systemName: workout.workoutType.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(workout.workoutType.color)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(workout.workout?.name ?? workout.workoutType.displayName)
                    .font(.dripLabel(14))
                    .foregroundStyle(Color.drip.textPrimary)

                if let w = workout.workout {
                    HStack(spacing: 8) {
                        if let distance = w.formattedTotalDistance {
                            Text(distance)
                                .font(.dripCaption(11))
                        }
                        if let duration = w.formattedDuration {
                            Text("•")
                                .font(.dripCaption(11))
                            Text(duration)
                                .font(.dripCaption(11))
                        }
                    }
                    .foregroundStyle(Color.drip.textSecondary)
                }
            }
        }
    }
}

// MARK: - Status Badge

struct StatusBadge: View {
    let status: WorkoutStatus

    var body: some View {
        Group {
            switch status {
            case .scheduled:
                EmptyView()
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.drip.positive)
            case .skipped:
                Image(systemName: "xmark.circle")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.drip.textTertiary)
            case .modified:
                Image(systemName: "pencil.circle")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.drip.coralLight)
            }
        }
    }
}

// MARK: - Month Day Cell

struct MonthDayCell: View {
    let day: Int
    let workout: ScheduledWorkout?
    let isSelected: Bool
    let isInPlanRange: Bool

    var body: some View {
        VStack(spacing: 4) {
            // Day number
            Text("\(day)")
                .font(.dripCaption(12))
                .foregroundStyle(dayNumberColor)

            // Workout indicator
            if let workout = workout {
                ZStack {
                    Circle()
                        .fill(workout.workoutType.color.opacity(0.2))
                        .frame(width: 28, height: 28)

                    Image(systemName: workout.workoutType.icon)
                        .font(.system(size: 12))
                        .foregroundStyle(workout.workoutType.color)

                    // Completion overlay
                    if workout.status == .completed {
                        Circle()
                            .stroke(Color.drip.positive, lineWidth: 2)
                            .frame(width: 28, height: 28)
                    }
                }
            } else {
                Circle()
                    .fill(Color.clear)
                    .frame(width: 28, height: 28)
            }
        }
        .frame(height: 60)
        .frame(maxWidth: .infinity)
        .background(
            isSelected
                ? Color.drip.coral.opacity(0.1)
                : Color.clear
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.drip.coral : Color.clear, lineWidth: 1)
        )
        .opacity(isInPlanRange ? 1 : 0.4)
    }

    private var dayNumberColor: Color {
        if let workout = workout, workout.isToday {
            return Color.drip.coral
        }
        if !isInPlanRange {
            return Color.drip.textTertiary
        }
        return Color.drip.textSecondary
    }
}

// MARK: - Empty Plan State

struct EmptyPlanState: View {
    let onGenerate: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(Color.drip.coral.opacity(0.1))
                    .frame(width: 100, height: 100)

                Image(systemName: "calendar.badge.plus")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(Color.drip.coral)
            }

            VStack(spacing: 8) {
                Text("No Training Plan")
                    .font(.dripLabel(18))
                    .foregroundStyle(Color.drip.textPrimary)

                Text("Generate a personalized training plan based on your goal race date and target time.")
                    .font(.dripBody(14))
                    .foregroundStyle(Color.drip.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }

            DripButton("Generate Plan", icon: "sparkles", style: .primary) {
                onGenerate()
            }
            .frame(width: 180)
        }
        .padding(.vertical, 40)
    }
}

// MARK: - Workout Type Picker

struct WorkoutTypePicker: View {
    @Binding var selectedType: ScheduledWorkoutType
    let availableTypes: [ScheduledWorkoutType]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(availableTypes, id: \.self) { type in
                    Button {
                        selectedType = type
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: type.icon)
                                .font(.system(size: 12))

                            Text(type.shortName)
                                .font(.dripCaption(12))
                        }
                        .foregroundStyle(selectedType == type ? .white : type.color)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            selectedType == type
                                ? type.color
                                : type.color.opacity(0.15)
                        )
                        .clipShape(Capsule())
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        DripBackground()

        VStack(spacing: 20) {
            PlanHeaderBanner(plan: TrainingPlan.sample)
                .padding(.horizontal, 20)

            CalendarViewModeToggle(selectedMode: .constant(.week))
                .padding(.horizontal, 20)

            WeekDayCard(
                workout: ScheduledWorkout.sample,
                racePaceSeconds: 480
            )
            .padding(.horizontal, 20)

            WeekDayCard(
                workout: ScheduledWorkout.restDaySample,
                racePaceSeconds: 480
            )
            .padding(.horizontal, 20)
        }
    }
}

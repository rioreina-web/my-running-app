//
//  PlanWeekListView.swift
//  RunningLog
//
//  Negative Splits — daily prescription list for the Plan tab's WEEK view.
//  Matches Plate 12. Each day in the current week renders as a row showing
//  the workout name, distance, pace target, and structure breakdown.
//
//  Replaces the previous `WeekCalendarView` (a horizontal mini-card row).
//  Vertical list matches how a coach writes a week's training.
//

import SwiftUI

struct PlanWeekListView: View {
    let viewModel: TrainingPlanViewModel
    var onDayTap: (ScheduledWorkout) -> Void

    private var workouts: [ScheduledWorkout] {
        viewModel.currentWeekWorkouts.sorted { lhs, rhs in
            lhs.date < rhs.date
        }
    }

    private var weekTotalMiles: Double {
        workouts
            .compactMap { $0.workout?.totalDistanceMiles }
            .reduce(0, +)
    }

    private var weekLabel: String {
        guard let plan = viewModel.activePlan else { return "" }
        let week = plan.currentWeek
        let total = plan.totalWeeks
        return "WEEK \(String(format: "%02d", week)) OF \(total)"
    }

    private var weekDateLabel: String {
        guard let first = workouts.first?.date,
              let last = workouts.last?.date else { return "" }
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return "\(f.string(from: first).uppercased())  —  \(f.string(from: last).uppercased())"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Section eyebrow
            HStack {
                Text("\(weekLabel)  ·  \(weekDateLabel)")
                    .font(.dripCaption(11))
                    .tracking(1.2)
                    .foregroundStyle(Color.drip.textSecondary)
                Spacer()
                Text("\(Int(weekTotalMiles.rounded())) MI  PLANNED")
                    .font(.dripCaption(11))
                    .foregroundStyle(Color.drip.textSecondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Rectangle().fill(Color.drip.divider).frame(height: 1)

            if workouts.isEmpty {
                Text("No workouts scheduled this week.")
                    .font(.system(size: 14, design: .serif).italic())
                    .foregroundStyle(Color.drip.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 24)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(workouts.enumerated()), id: \.element.id) { idx, w in
                        Button {
                            onDayTap(w)
                        } label: {
                            PlanWeekDayRow(
                                workout: w,
                                equivalentPaces: viewModel.equivalentPaces
                            )
                            .padding(.horizontal, 20)
                        }
                        .buttonStyle(.plain)
                        if idx < workouts.count - 1 {
                            Rectangle()
                                .fill(Color.drip.divider)
                                .frame(height: 1)
                                .padding(.horizontal, 20)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - PlanWeekDayRow

private struct PlanWeekDayRow: View {
    let workout: ScheduledWorkout
    let equivalentPaces: EquivalentPaces?

    private var dayLabel: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        return f.string(from: workout.date).uppercased()
    }

    private var dateLabel: String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: workout.date).uppercased()
    }

    private var isToday: Bool {
        Calendar.current.isDateInToday(workout.date)
    }

    private var isPast: Bool {
        Calendar.current.startOfDay(for: workout.date)
            < Calendar.current.startOfDay(for: Date())
    }

    private var isRest: Bool {
        workout.workoutType == .rest
    }

    private var isLongRun: Bool {
        workout.workoutType == .longRun
    }

    private var statusTag: String {
        if isToday { return "TODAY" }
        if workout.status == .completed { return "DONE" }
        if workout.status == .skipped { return "MISSED" }
        if isPast { return "PAST" }
        if isLongRun { return "MARQUEE" }
        return "AHEAD"
    }

    private var statusColor: Color {
        if isToday || isLongRun { return Color.drip.coral }
        if workout.status == .completed { return Color.drip.energized }
        if workout.status == .skipped { return Color.drip.textTertiary }
        return Color.drip.textTertiary
    }

    private var workoutName: String {
        workout.workoutType.displayName
    }

    private var distanceLabel: String {
        if isRest { return "—" }
        if let m = workout.workout?.totalDistanceMiles, m > 0 {
            return "\(Int(m.rounded())) MI"
        }
        return "—"
    }

    /// Best-effort pace target line. Uses the workout type's natural pace
    /// from `equivalentPaces` if available; otherwise generic phrasing.
    private var paceTarget: String? {
        guard let p = equivalentPaces else { return nil }
        switch workout.workoutType {
        case .easy, .recovery:
            return "\(formatPace(p.easyPace + 30)) – \(formatPace(p.easyPace - 30)) / mi  ·  conversational"
        case .tempo:
            return "\(formatPace(p.thresholdPace)) / mi  ·  threshold pace"
        case .longRun:
            return "\(formatPace(p.longRunPace)) / mi  ·  long-run pace"
        case .intervals:
            return "\(formatPace(p.fiveKPace)) / mi  ·  5K pace"
        case .progression:
            return "\(formatPace(p.easyPace)) → \(formatPace(p.mpPace)) / mi  ·  build through"
        case .race:
            return "race effort"
        case .rest:
            return nil
        case .strides, .strength, .crossTraining:
            return nil
        }
    }

    /// Optional structure summary. Falls back to `nil` if we can't infer one.
    private var structureLine: String? {
        if isRest { return "Recovery day. Walk, stretch, or cross-train." }
        if let notes = workout.notes, !notes.isEmpty { return notes }
        switch workout.workoutType {
        case .tempo:
            return "Warm-up · main set at threshold · cool-down."
        case .longRun:
            return "Steady, conversational. Fuel and hydrate."
        case .intervals:
            return "Warm-up · interval set · cool-down."
        case .progression:
            return "Easy → moderate → MP. Build through."
        case .easy:
            return "Whole run conversational. Recovery focus."
        case .recovery:
            return "Easy shakeout between hard days."
        default:
            return nil
        }
    }

    private func formatPace(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Eyebrow row — DAY · DATE  ·  STATUS
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 0) {
                    Text(dayLabel)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .tracking(1.0)
                        .foregroundStyle(Color.drip.textSecondary)
                    Text("  ·  ")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color.drip.textTertiary)
                    Text(dateLabel)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(Color.drip.textTertiary)
                }
                Spacer()
                Text(statusTag)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .tracking(1.0)
                    .foregroundStyle(statusColor)
            }

            // Workout name + distance
            HStack(alignment: .firstTextBaseline) {
                Text(workoutName)
                    .font(.dripDisplay(22))
                    .foregroundStyle(isToday || isLongRun ? Color.drip.coral : Color.drip.textPrimary)
                Spacer()
                Text(distanceLabel)
                    .font(.dripDisplay(22))
                    .foregroundStyle(isToday || isLongRun ? Color.drip.coral : Color.drip.textPrimary)
            }
            .padding(.top, 4)

            // Pace target
            if let pace = paceTarget {
                Text(pace)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.drip.textSecondary)
                    .padding(.top, 2)
            }

            // Structure / note
            if let s = structureLine {
                Text(s)
                    .font(.system(size: 13, design: .serif).italic())
                    .foregroundStyle(Color.drip.textSecondary)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 18)
        .contentShape(Rectangle())
    }
}

//
//  PlanMonthSummaryView.swift
//  RunningLog
//
//  Negative Splits — weekly summary list for the Plan tab's MONTH view.
//  Matches Plate 13. Each week renders as one row with total mileage, key
//  sessions called out, and a 7-bar daily intensity strip on the right.
//
//  Replaces the previous `MonthCalendarView` (a 7-column grid of small
//  cells) for athletes who want the *block shape* at a glance: which week
//  is peak, which is cutback, where the long-run distance ramps and falls.
//
//  Tap any week to jump to that week in the WEEK view.
//

import SwiftUI

struct PlanMonthSummaryView: View {
    let viewModel: TrainingPlanViewModel
    var onWeekTap: (Int) -> Void

    /// Group all scheduled workouts by ISO week-of-year.
    private var weeklyGroups: [(weekOfYear: Int, weekStart: Date, workouts: [ScheduledWorkout])] {
        let calendar = Calendar.iso8601Monday
        var byKey: [Int: [ScheduledWorkout]] = [:]
        for w in viewModel.allScheduledWorkouts {
            let key = calendar.component(.weekOfYear, from: w.date)
            byKey[key, default: []].append(w)
        }
        return byKey
            .sorted { $0.key < $1.key }
            .compactMap { (key, workouts) in
                guard let firstDate = workouts.map(\.date).min() else { return nil }
                let weekStart = calendar.date(from: calendar.dateComponents(
                    [.yearForWeekOfYear, .weekOfYear], from: firstDate
                )) ?? firstDate
                return (key, weekStart, workouts)
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Section eyebrow
            HStack {
                Text("ALL WEEKS  ·  \(viewModel.activePlan.map { "\($0.totalWeeks)-WEEK PLAN" } ?? "")")
                    .font(.dripCaption(11))
                    .tracking(1.2)
                    .foregroundStyle(Color.drip.textSecondary)
                Spacer()
                if let plan = viewModel.activePlan {
                    Text("WEEK \(String(format: "%02d", plan.currentWeek)) OF \(plan.totalWeeks)")
                        .font(.dripCaption(11))
                        .foregroundStyle(Color.drip.textSecondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Rectangle().fill(Color.drip.divider).frame(height: 1)

            if weeklyGroups.isEmpty {
                Text("No weeks in this plan yet.")
                    .font(.system(size: 14, design: .serif).italic())
                    .foregroundStyle(Color.drip.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 24)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(weeklyGroups.enumerated()), id: \.element.weekOfYear) { idx, group in
                        Button {
                            onWeekTap(group.weekOfYear)
                        } label: {
                            PlanMonthWeekRow(
                                weekStart: group.weekStart,
                                workouts: group.workouts,
                                planWeekNumber: group.workouts.first?.weekNumber ?? 0,
                                isCurrent: isCurrentWeek(group.weekStart)
                            )
                            .padding(.horizontal, 20)
                        }
                        .buttonStyle(.plain)
                        if idx < weeklyGroups.count - 1 {
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

    private func isCurrentWeek(_ weekStart: Date) -> Bool {
        let cal = Calendar.iso8601Monday
        let today = Date()
        return cal.component(.weekOfYear, from: weekStart) == cal.component(.weekOfYear, from: today)
            && cal.component(.yearForWeekOfYear, from: weekStart) == cal.component(.yearForWeekOfYear, from: today)
    }
}

// MARK: - PlanMonthWeekRow

private struct PlanMonthWeekRow: View {
    let weekStart: Date
    let workouts: [ScheduledWorkout]
    let planWeekNumber: Int
    let isCurrent: Bool

    private var weekLabel: String {
        "WEEK \(String(format: "%02d", planWeekNumber))"
    }

    private var dateRangeLabel: String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        let start = weekStart
        let end = Calendar.current.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        return "\(f.string(from: start).uppercased())  —  \(f.string(from: end).uppercased())"
    }

    private var totalMiles: Int {
        let total = workouts
            .compactMap { $0.workout?.totalDistanceMiles }
            .reduce(0, +)
        return Int(total.rounded())
    }

    /// Headline sessions: long, race, intervals, tempo, MP/progression.
    private var keySessions: String {
        let priority: [ScheduledWorkoutType] = [.race, .longRun, .intervals, .tempo, .progression]
        var picks: [String] = []
        for type in priority {
            for w in workouts where w.workoutType == type {
                let miles = Int((w.workout?.totalDistanceMiles ?? 0).rounded())
                let label = type.displayName.replacingOccurrences(of: " Run", with: "")
                if miles > 0 {
                    picks.append("\(label) \(miles)")
                } else {
                    picks.append(label)
                }
            }
        }
        if picks.isEmpty {
            // Fall back to a count of easy/recovery
            let easyCount = workouts.filter { $0.workoutType == .easy || $0.workoutType == .recovery }.count
            if easyCount > 0 { picks.append("Easy × \(easyCount)") }
            let restCount = workouts.filter { $0.workoutType == .rest }.count
            if restCount > 0 { picks.append("\(restCount) rest") }
        }
        return picks.joined(separator: "  ·  ")
    }

    /// 7-bar intensity strip. Each bar = one day's mileage, ordered Mon-Sun.
    private var dailyIntensity: [Double] {
        var byDow: [Int: Double] = [:]
        for w in workouts {
            let dow = Calendar.iso8601Monday.component(.weekday, from: w.date)
            // ISO week: Mon=2, Tue=3, ... Sun=1 in Calendar default; with iso8601Monday firstWeekday=2
            // Normalize to Mon=0 ... Sun=6
            let idx = (dow + 5) % 7
            byDow[idx, default: 0] += w.workout?.totalDistanceMiles ?? 0
        }
        return (0..<7).map { byDow[$0] ?? 0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Eyebrow row
            HStack(alignment: .firstTextBaseline) {
                Text(weekLabel)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(isCurrent ? Color.drip.coral : Color.drip.textSecondary)
                Text("  ·  \(dateRangeLabel)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.drip.textTertiary)
                Spacer()
                if isCurrent {
                    Text("THIS WEEK")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .tracking(1.0)
                        .foregroundStyle(Color.drip.coral)
                }
            }
            .padding(.top, 14)

            // Mid row — big mileage on left, key sessions in italic, intensity strip right
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(totalMiles)")
                            .font(.dripDisplay(34))
                            .foregroundStyle(isCurrent ? Color.drip.coral : Color.drip.textPrimary)
                        Text("MI")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.drip.textSecondary)
                            .padding(.bottom, 4)
                    }
                    if !keySessions.isEmpty {
                        Text(keySessions)
                            .font(.system(size: 13, design: .serif).italic())
                            .foregroundStyle(Color.drip.textSecondary)
                            .lineLimit(2)
                    }
                }
                .padding(.top, 4)

                Spacer(minLength: 8)

                IntensityStrip(values: dailyIntensity, isCurrent: isCurrent)
                    .frame(width: 130, height: 36)
                    .padding(.top, 12)
            }
            .padding(.top, 6)
            .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

// MARK: - IntensityStrip

private struct IntensityStrip: View {
    let values: [Double]
    let isCurrent: Bool

    var body: some View {
        GeometryReader { geo in
            let max = (values.max() ?? 1).clamped(min: 1, max: .infinity)
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(values.indices, id: \.self) { i in
                    if values[i] == 0 {
                        Rectangle()
                            .fill(Color.drip.textTertiary)
                            .frame(height: 1)
                            .frame(maxHeight: .infinity, alignment: .center)
                    } else {
                        Rectangle()
                            .fill(barColor(for: i))
                            .frame(height: max == 0 ? 1 : geo.size.height * CGFloat(values[i] / max))
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }

    private func barColor(for index: Int) -> Color {
        // Today's bar (Mon=0...) — highlight if this is the current week and
        // the day matches today.
        if isCurrent {
            let cal = Calendar.iso8601Monday
            let todayDow = cal.component(.weekday, from: Date())
            let todayIdx = (todayDow + 5) % 7
            if index == todayIdx { return Color.drip.coral }
            return Color.drip.textSecondary
        }
        return Color.drip.textTertiary
    }
}

// MARK: - Helpers

private extension Calendar {
    /// ISO 8601 week (Monday-first). The app stores plan workouts on Mon-Sun
    /// weeks, so use this consistently for grouping/sorting.
    static var iso8601Monday: Calendar {
        var cal = Calendar(identifier: .iso8601)
        cal.firstWeekday = 2
        return cal
    }
}

private extension Comparable {
    func clamped(min: Self, max: Self) -> Self {
        Swift.min(Swift.max(self, min), max)
    }
}

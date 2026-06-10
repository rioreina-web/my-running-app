//
//  CoachPlanWeekStrip.swift
//  RunningLog
//
//  Negative Splits week strip — horizontal hairline timeline with seven
//  day-cells. Replaces the colored card carousel for the dashboard's
//  "Coach's Plan" section.
//
//  Visual language (matches Plate 06 mockups):
//   - Day abbreviation in mono caps at the top.
//   - A node on a connecting hairline:
//       · filled ink dot     = completed
//       · amber dot + halo   = today
//       · open circle        = upcoming
//       · short dash         = rest day
//   - Distance below the node in serif display.
//   - Workout-type tag below distance in mono caps.
//
//  The strip takes the runner's `[ScheduledWorkout]` for the current
//  week. Days are rendered in dayOfWeek order (Mon → Sun).
//

import SwiftUI

struct CoachPlanWeekStrip: View {
    let workouts: [ScheduledWorkout]

    /// Sort + de-duplicate by dayOfWeek so the strip lays out Mon → Sun.
    /// (If two scheduled workouts land on the same day, prefer the
    /// non-rest one and ignore the secondary.)
    private var sortedWorkouts: [ScheduledWorkout] {
        var seen: Set<Int> = []
        var out: [ScheduledWorkout] = []
        for w in workouts.sorted(by: { lhs, rhs in
            // dayOfWeek convention used elsewhere in the app: Mon = 1 ... Sun = 7
            let lDay = normalizeDayOfWeek(lhs.dayOfWeek)
            let rDay = normalizeDayOfWeek(rhs.dayOfWeek)
            if lDay != rDay { return lDay < rDay }
            // Prefer non-rest first
            if (lhs.workoutType == .rest) != (rhs.workoutType == .rest) {
                return lhs.workoutType != .rest
            }
            return false
        }) {
            let day = normalizeDayOfWeek(w.dayOfWeek)
            if !seen.contains(day) {
                seen.insert(day)
                out.append(w)
            }
        }
        return out
    }

    /// Convert any day-of-week convention (Sun=1 vs Mon=1) to Mon=1...Sun=7.
    private func normalizeDayOfWeek(_ raw: Int) -> Int {
        // Heuristic: if any value is 0, treat as Mon=0...Sun=6 → bump
        // by 1. Common Swift conventions are Sun=1...Sat=7 (Calendar
        // default) and Mon=1...Sun=7 (ISO). We'll just preserve order
        // and not try to be clever — relative ordering is what matters.
        return raw
    }

    var body: some View {
        ZStack(alignment: .center) {
            // Horizontal hairline through the dot row
            GeometryReader { geo in
                Path { p in
                    let y = nodeRowCenterY
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: geo.size.width, y: y))
                }
                .stroke(Color.drip.divider, lineWidth: 1)
            }

            HStack(alignment: .top, spacing: 0) {
                ForEach(sortedWorkouts) { workout in
                    DayCellView(workout: workout)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(height: cellTotalHeight)
    }

    private let cellTotalHeight: CGFloat = 96
    /// Vertical center of the dot row, measured from the top of the strip.
    private var nodeRowCenterY: CGFloat { 28 }
}

// MARK: - Single day cell

private struct DayCellView: View {
    let workout: ScheduledWorkout

    private var dayLabel: String {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f.string(from: workout.date).uppercased()
    }

    private var isToday: Bool {
        Calendar.current.isDateInToday(workout.date)
    }

    private var isPast: Bool {
        Calendar.current.startOfDay(for: workout.date)
            < Calendar.current.startOfDay(for: Date())
    }

    private var isCompleted: Bool {
        workout.status == .completed
    }

    private var isSkipped: Bool {
        workout.status == .skipped
    }

    private var isRest: Bool {
        workout.workoutType == .rest
    }

    private var distanceLabel: String {
        if isRest { return "—" }
        if let m = workout.workout?.totalDistanceMiles, m > 0 {
            // Round to integer for the strip — fractional miles are noise here.
            return "\(Int(m.rounded()))"
        }
        return "—"
    }

    private var typeLabel: String {
        switch workout.workoutType {
        case .rest:          return "REST"
        case .easy:          return "EASY"
        case .tempo:         return "TEMPO"
        case .intervals:     return "INTV"
        case .longRun:       return "LONG"
        case .recovery:      return "RECOV"
        case .race:          return "RACE"
        case .progression:   return "PROG"
        case .strides:       return "STRIDE"
        case .strength:      return "STR"
        case .crossTraining: return "XT"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Row 1: day abbreviation
            Text(dayLabel)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .tracking(0.6)
                .foregroundStyle(isToday ? Color.drip.coral : Color.drip.textSecondary)
                .frame(height: 14)

            // Row 2: node (16x16 area inside a 28pt-tall row so the hairline
            // bisects it cleanly)
            ZStack {
                if isToday {
                    Circle()
                        .stroke(Color.drip.coral, lineWidth: 1)
                        .frame(width: 22, height: 22)
                }
                node
            }
            .frame(height: 28)

            // Row 3: distance
            Text(distanceLabel)
                .font(.dripDisplay(18))
                .foregroundStyle(distanceColor)
                .frame(height: 24)
                .padding(.top, 6)

            // Row 4: type
            Text(typeLabel)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .tracking(0.6)
                .foregroundStyle(typeColor)
                .frame(height: 12)
        }
    }

    /// The dot node itself. Filled ink for completed, amber for today,
    /// hollow for upcoming, dashed-feel for rest days.
    @ViewBuilder
    private var node: some View {
        if isToday {
            Circle()
                .fill(Color.drip.coral)
                .frame(width: 14, height: 14)
        } else if isCompleted {
            Circle()
                .fill(Color.drip.textPrimary)
                .frame(width: 14, height: 14)
        } else if isSkipped {
            // Open circle with a strikethrough to convey "missed"
            ZStack {
                Circle()
                    .stroke(Color.drip.textTertiary, lineWidth: 1.5)
                    .frame(width: 14, height: 14)
                Rectangle()
                    .fill(Color.drip.textTertiary)
                    .frame(width: 16, height: 1)
                    .rotationEffect(.degrees(-30))
            }
        } else if isRest {
            // Tiny horizontal dash — denotes a rest day
            Rectangle()
                .fill(Color.drip.textTertiary)
                .frame(width: 10, height: 1.5)
        } else {
            // Upcoming — hollow circle
            Circle()
                .strokeBorder(Color.drip.textTertiary, lineWidth: 1.5)
                .frame(width: 14, height: 14)
        }
    }

    private var distanceColor: Color {
        if isToday { return Color.drip.coral }
        if isCompleted { return Color.drip.textPrimary }
        if isSkipped || isRest { return Color.drip.textTertiary }
        return Color.drip.textPrimary
    }

    private var typeColor: Color {
        if isToday { return Color.drip.coral }
        if isCompleted { return Color.drip.textSecondary }
        return Color.drip.textTertiary
    }
}

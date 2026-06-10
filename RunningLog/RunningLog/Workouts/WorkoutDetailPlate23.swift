//
//  WorkoutDetailPlate23.swift
//  RunningLog
//
//  Plate 23 (Pace, narrated · sharpened) editorial chrome for the
//  Vital/Strava workout-detail screen.
//
//  This file is INTENTIONALLY conservative: it only provides the
//  editorial chrome (header, stat strip, section eyebrow, divider,
//  weekly-context line). The existing chart components — PaceChartCard,
//  RouteMapCard, HeartRateGraphCard, mile splits — stay where they
//  are; we just dress the framing around them down to match the rest
//  of the trend-mockup voice.
//
//  To revert: delete this file and revert the body changes in
//  VitalWorkoutDetailView.swift. No data shapes change.
//

import SwiftUI

// MARK: - Editorial rule
//
// `WD23EditorialRule` was deleted — use the shared `EditorialRule` from
// DesignSystem.swift instead. Callsites in VitalWorkoutDetailView were
// renamed in the same pass.

// MARK: - Header

/// Editorial header for a completed workout.
///
/// Replaces the previous centered weekday + date + source-badge stack
/// with a left-aligned editorial set: mono eyebrow, Crimson Pro display
/// date, italic-serif tagline carrying distance + duration + source.
struct WD23Header: View {
    let workout: RunningWorkout

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(eyebrow)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .tracking(1.5)  // 0.14em label tracking at 11pt (was 1.4 — slight drift vs WorkoutDetailScreen.jsx)
                .foregroundStyle(Color.drip.coral)
            Text(dateLine)
                .font(.dripDisplay(40))
                .foregroundStyle(Color.drip.textPrimary)
            Text(taglineText)
                .font(.system(size: 14, design: .serif).italic())
                .foregroundStyle(Color.drip.textSecondary)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "THURSDAY  ·  LOG"
    private var eyebrow: String {
        "\(workout.dayOfWeek.uppercased())  ·  LOG"
    }

    /// "May 7" — month + day, no year. Year goes into the tagline if it's
    /// in a different year than today (rare for a freshly-imported workout).
    private var dateLine: String {
        let f = DateFormatter()
        f.dateFormat = "MMMM d"
        return f.string(from: workout.startDate)
    }

    /// "5.01 mi  ·  35:59  ·  Strava"
    private var taglineText: String {
        var parts: [String] = []
        parts.append(workout.formattedDistance)
        parts.append(workout.formattedDuration)
        parts.append(sourceLabel(workout.sourceApp))
        return parts.joined(separator: "  ·  ")
    }

    private func sourceLabel(_ source: String) -> String {
        let trimmed = source.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return "Imported" }
        return trimmed.capitalized
    }
}

// MARK: - Two-stat strip

/// Editorial 4-stat top strip — DISTANCE / DURATION / AVG PACE / AVG HR.
/// Per WorkoutDetailScreen.jsx's 4-cell grid (the JSX shows GAP / LOAD
/// in slots 3-4, which aren't in the data model yet — AVG PACE and AVG
/// HR are the realistic fill while keeping the editorial 4-up pattern).
///
/// Name kept (`WD23TwoStatStrip`) for callsite stability; rename in a
/// follow-up sweep.
struct WD23TwoStatStrip: View {
    let workout: RunningWorkout
    let avgHr: Int?
    var elevationFeet: Int? = nil

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color.drip.divider).frame(height: 1)
            HStack(alignment: .top, spacing: 0) {
                statCell(label: "DISTANCE",
                         value: workout.formattedDistance.replacingOccurrences(of: " mi", with: ""),
                         unit: "mi",
                         sub: distanceSub)
                verticalRule
                statCell(label: "DURATION",
                         value: workout.formattedDuration,
                         unit: "")
                verticalRule
                statCell(label: "AVG PACE",
                         value: workout.formattedPace,
                         unit: "/mi")
                verticalRule
                statCell(label: "AVG HR",
                         value: avgHr.map(String.init) ?? "—",
                         unit: avgHr != nil ? "bpm" : "",
                         sub: hrZoneSub)
            }
            .padding(.vertical, 16)
            Rectangle().fill(Color.drip.divider).frame(height: 1)
        }
    }

    /// Sub-line under DISTANCE — elevation gained, per the
    /// WorkoutDetailScreen.jsx "+141 ft elev" treatment. Hidden when the
    /// stream carries no elevation.
    private var distanceSub: String? {
        elevationFeet.map { "+\($0) ft elev" }
    }

    /// Sub-line under AVG HR — the dominant HR zone for the average, e.g.
    /// "Z3". Mirrors the JSX secondary strip's "143 · Z3" pairing without a
    /// separate cell. Uses the shared zone table (default max HR 185).
    private var hrZoneSub: String? {
        guard let hr = avgHr else { return nil }
        return DripHRZone.defaultZones(maxHR: 185)
            .first(where: { hr >= $0.low && hr < $0.high })?.id
    }

    private var verticalRule: some View {
        Rectangle().fill(Color.drip.divider).frame(width: 1, height: 64)
    }

    /// `sub` is the small grade-/context caption beneath the value
    /// (`.05em` mono, tertiary). A blank line is reserved when `sub` is nil
    /// so every cell keeps the same height and the values stay aligned.
    private func statCell(label: String, value: String, unit: String, sub: String? = nil) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.dripEyebrow(9))
                .tracking(0.9)  // 0.10em caption tracking at 9pt
                .foregroundStyle(Color.drip.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.dripStat(22))  // mono per WorkoutDetailScreen.jsx stat cells (was .dripDisplay/serif — drift)
                    .foregroundStyle(Color.drip.textPrimary)
                    .monospacedDigit()
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Color.drip.textSecondary)
                }
            }
            Text(sub ?? " ")
                .font(.dripEyebrow(9))
                .tracking(0.45)  // 0.05em sub tracking at 9pt (WorkoutDetailScreen.jsx)
                .foregroundStyle(Color.drip.textTertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Secondary stats row

/// Slim row of supplementary stats below the main 4-stat strip. AVG
/// PACE and HR AVG moved up to the editorial top strip; this row now
/// carries the leftovers — ELEV + CALORIES. Renders 2-up.
struct WD23SecondaryStats: View {
    let workout: RunningWorkout
    let elevationFeet: Int?

    var body: some View {
        HStack(spacing: 0) {
            cell(label: "ELEV",
                 value: elevationFeet.map { "\($0)" } ?? "—",
                 sub: elevationFeet != nil ? "ft gained" : "no data")
            cell(label: "CALORIES",
                 value: "\(Int(workout.calories))",
                 sub: "kcal")
        }
    }

    private func cell(label: String, value: String, sub: String) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.dripEyebrow(9))
                .tracking(0.9)  // 0.10em caption tracking at 9pt
                .foregroundStyle(Color.drip.textSecondary)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.drip.textPrimary)
            Text(sub)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(Color.drip.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Section eyebrow

/// Small mono caption above each chart section. Replaces the "icon +
/// label + toggle pill" pattern used previously. When `trailing` is
/// supplied it renders at the right edge in SLATE_LIGHT — useful for
/// "AVG 7:11" or "MAX 162" annotations that used to sit inside cards.
struct WD23SectionEyebrow: View {
    let label: String
    var trailing: String? = nil

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .tracking(1.0)
                .foregroundStyle(Color.drip.textSecondary)
            Spacer()
            if let trailing = trailing {
                Text(trailing)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Color.drip.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Weekly context

/// Italic-serif quote section that ties this single workout to the
/// week's narrative. Renders only when caller supplies the context
/// numbers — when fields are nil, the whole component hides itself
/// rather than showing dashes.
struct WD23WeeklyContext: View {
    let runIndexInWeek: Int?     // e.g. 4 (this is the 4th run of the week)
    let runsInWeek: Int?         // e.g. 5 (planned)
    let milesBankedThisWeek: Double?
    let loadDeltaPct: Int?       // e.g. +9 = "+9% to chronic load"
    let acwrAfterRun: Double?    // e.g. 1.18

    var body: some View {
        if shouldRender {
            VStack(alignment: .leading, spacing: 6) {
                Text("WEEKLY CONTEXT")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .tracking(1.0)
                    .foregroundStyle(Color.drip.textSecondary)
                Text(line1)
                    .font(.system(size: 14, design: .serif).italic())
                    .foregroundStyle(Color.drip.textPrimary)
                if let line2 = line2 {
                    Text(line2)
                        .font(.system(size: 14, design: .serif).italic())
                        .foregroundStyle(Color.drip.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var shouldRender: Bool {
        runIndexInWeek != nil || milesBankedThisWeek != nil || loadDeltaPct != nil
    }

    private var line1: String {
        var parts: [String] = []
        if let i = runIndexInWeek, let n = runsInWeek {
            parts.append("Run \(i) of \(n) this week.")
        } else if let i = runIndexInWeek {
            parts.append("Run \(i) this week.")
        }
        if let banked = milesBankedThisWeek {
            let str = banked == banked.rounded()
                ? String(format: "%.0f", banked)
                : String(format: "%.1f", banked)
            parts.append("\(str) mi banked.")
        }
        return parts.joined(separator: " ")
    }

    private var line2: String? {
        guard let delta = loadDeltaPct else { return nil }
        let sign = delta >= 0 ? "+" : ""
        var s = "This run added \(sign)\(delta)% to your chronic load"
        if let acwr = acwrAfterRun {
            s += " — bringing ACWR to \(String(format: "%.2f", acwr))."
        } else {
            s += "."
        }
        return s
    }
}

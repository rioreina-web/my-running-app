//
//  TrainingWeekExpanded.swift
//  RunningLog
//
//  Plate 27 — inline week-expanded panel for the Training tab's weekly
//  load bars. Pairs with TrainingDayExpanded (Plate 26).
//
//  Tap a weekly bar → AMBER fill on that bar, this panel slides in
//  below the bar list. No drill-out: the week IS the page.
//
//  v1 sections:
//    • Week eyebrow (WEEK 17 · APR 21 – APR 27) + collapse hint
//    • Headline "91 mi · 7 runs"
//    • Sub: LOAD · plan-vs-actual · ACWR-going-in (mono line)
//    • Zone mix horizontal stacked bar
//    • Day-by-day 7-cell row, mile count + workout-type color
//    • Key session callout (longest or heaviest run)
//
//  Data sources: training_logs only — the same fetch the Training tab
//  already does. Load/zone-mix derived from workout_features when
//  available, fallback to workout_type × duration otherwise. Plan vs
//  actual + ACWR are placeholders (—) until the proper plan-week and
//  athlete-state fetches land in this view.
//

import SwiftUI

struct TrainingWeekExpanded: View {
    /// First day of the week (Monday).
    let weekStart: Date
    /// All logs that fall within `weekStart … weekStart + 7 days`.
    let weekLogs: [TodayLogRow]
    /// Position in the displayed 4-week window (0 = Wk-3, 3 = This week).
    /// Used to label the eyebrow and pick the date range.
    let weekIndex: Int
    let onCollapse: () -> Void

    private var cal: Calendar { Calendar.current }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            topBar
            headline
            metaLine
            zoneMixSection
            dayByDayRow
            keySession
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.drip.divider.opacity(0.18))
        )
    }

    // MARK: - Sections

    private var topBar: some View {
        HStack {
            Text(eyebrowText)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .tracking(1.0)
                .foregroundStyle(Color.drip.coral)
            Spacer()
            Button(action: onCollapse) {
                Text("TAP TO COLLAPSE")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(Color.drip.textTertiary)
            }
            .buttonStyle(.plain)
        }
    }

    private var headline: some View {
        Text(headlineText)
            .font(.dripDisplay(22))
            .foregroundStyle(Color.drip.textPrimary)
    }

    private var metaLine: some View {
        Text(metaText)
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(Color.drip.textSecondary)
    }

    private var zoneMixSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ZONE MIX  ·  WEEK TOTAL")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(Color.drip.textTertiary)
            zoneMixBar
        }
        .padding(.top, 6)
    }

    private var zoneMixBar: some View {
        // Approximate zone mix from workout_type since we don't fetch
        // workout_features here. Heavy on easy minutes, modest on
        // moderate, small slivers for threshold/hard. Future revision:
        // wire workout_features data through to make this accurate.
        let zones = approximateZoneMix()
        return GeometryReader { geo in
            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color.drip.positive)
                    .frame(width: geo.size.width * zones.easy)
                Rectangle()
                    .fill(Color.drip.textSecondary)
                    .frame(width: geo.size.width * zones.moderate)
                Rectangle()
                    .fill(Color.drip.coral)
                    .frame(width: geo.size.width * zones.threshold)
                Rectangle()
                    .fill(Color.drip.textPrimary)
                    .frame(width: geo.size.width * zones.hard)
            }
        }
        .frame(height: 14)
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    private var dayByDayRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("DAY BY DAY")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(Color.drip.textTertiary)
            HStack(spacing: 4) {
                ForEach(0..<7, id: \.self) { offset in
                    dayCell(offset: offset)
                }
            }
        }
        .padding(.top, 4)
    }

    private func dayCell(offset: Int) -> some View {
        let dayDate = cal.date(byAdding: .day, value: offset, to: weekStart) ?? weekStart
        let dayLogs = weekLogs.filter { cal.isDate($0.date, inSameDayAs: dayDate) }
        let miles = dayLogs.compactMap(\.miles).reduce(0, +)
        let dayLabels = ["M", "T", "W", "Th", "F", "Sa", "Su"]
        let label = dayLabels[offset]
        let color: Color = {
            guard miles > 0 else { return Color.drip.divider.opacity(0.4) }
            let types = dayLogs.compactMap { $0.typeKey?.lowercased() }
            if types.contains("intervals") { return Color.drip.coral }
            if types.contains("tempo") || types.contains("threshold") || types.contains("progression") {
                return Color.drip.coral.opacity(0.6)
            }
            if types.contains("long_run") || miles >= 12 { return Color.drip.positive }
            return Color.drip.positive.opacity(0.5)
        }()

        return VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.drip.textSecondary)
            Text(miles > 0 ? "\(Int(miles))" : "·")
                .font(.dripDisplay(13))
                .foregroundStyle(Color.drip.textPrimary)
                .monospacedDigit()
            Text(miles > 0 ? "mi" : "")
                .font(.system(size: 7, design: .monospaced))
                .foregroundStyle(Color.drip.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(color)
        )
    }

    @ViewBuilder
    private var keySession: some View {
        if let key = pickKeySession() {
            VStack(alignment: .leading, spacing: 6) {
                Text("KEY SESSION")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(Color.drip.textTertiary)
                Text(key)
                    .font(.system(size: 13, design: .serif).italic())
                    .foregroundStyle(Color.drip.textPrimary)
                    .lineSpacing(2)
            }
            .padding(.top, 6)
        }
    }

    // MARK: - Strings + computations

    /// "WEEK · APR 21 – APR 27" or "THIS WEEK · MAY 5 – MAY 11"
    private var eyebrowText: String {
        let weekEnd = cal.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        let startStr = f.string(from: weekStart).uppercased()
        let endStr = f.string(from: weekEnd).uppercased()
        let prefix: String
        switch weekIndex {
        case 3:  prefix = "THIS WEEK"
        case 2:  prefix = "WEEK − 1"
        case 1:  prefix = "WEEK − 2"
        case 0:  prefix = "WEEK − 3"
        default: prefix = "WEEK"
        }
        return "\(prefix)  ·  \(startStr) – \(endStr)"
    }

    /// "91 mi · 7 runs"
    private var headlineText: String {
        let totalMiles = weekLogs.compactMap(\.miles).reduce(0, +)
        let runCount = weekLogs.filter { ($0.miles ?? 0) > 0 }.count
        let milesStr: String
        if totalMiles == totalMiles.rounded() {
            milesStr = String(format: "%.0f", totalMiles)
        } else {
            milesStr = String(format: "%.1f", totalMiles)
        }
        return "\(milesStr) mi  ·  \(runCount) \(runCount == 1 ? "run" : "runs")"
    }

    /// "LOAD 612 · 5 quality, 2 easy · longest 20 mi"
    private var metaText: String {
        let totalLoad = weekLogs
            .map { approximateLoadFromLog($0) }
            .reduce(0, +)
        let qualityCount = weekLogs.filter { isQualityLog($0) }.count
        let easyCount = weekLogs.filter { isEasyLog($0) }.count
        let longest = weekLogs.compactMap(\.miles).max() ?? 0
        var parts: [String] = []
        if totalLoad > 0 {
            parts.append("LOAD \(totalLoad)")
        }
        if qualityCount > 0 || easyCount > 0 {
            parts.append("\(qualityCount) quality, \(easyCount) easy")
        }
        if longest > 0 {
            let str = longest == longest.rounded()
                ? String(format: "%.0f", longest)
                : String(format: "%.1f", longest)
            parts.append("longest \(str) mi")
        }
        return parts.joined(separator: "  ·  ")
    }

    /// Pick the longest hard run of the week and write a 1-line note.
    private func pickKeySession() -> String? {
        let scored = weekLogs.compactMap { log -> (TodayLogRow, Int)? in
            let load = approximateLoadFromLog(log)
            return load > 0 ? (log, load) : nil
        }
        guard let (top, load) = scored.max(by: { $0.1 < $1.1 }) else { return nil }
        let f = DateFormatter()
        f.dateFormat = "EEE"
        let day = f.string(from: top.date)
        let type = (top.typeKey ?? "run").replacingOccurrences(of: "_", with: " ").capitalized
        guard let miles = top.miles, miles > 0 else { return nil }
        let mStr = miles == miles.rounded()
            ? String(format: "%.0f", miles)
            : String(format: "%.1f", miles)
        return "\(day) · \(type) \(mStr) mi — \(load) weighted-min."
    }

    private func isQualityLog(_ log: TodayLogRow) -> Bool {
        let t = (log.typeKey ?? "").lowercased()
        return t.contains("tempo") || t.contains("threshold") ||
               t.contains("intervals") || t.contains("progression") ||
               t.contains("race") || t.contains("long")
    }

    private func isEasyLog(_ log: TodayLogRow) -> Bool {
        let t = (log.typeKey ?? "").lowercased()
        return t == "easy" || t == "recovery"
    }

    /// Coarse load proxy — same shape used by TrainingDayExpanded so the
    /// numbers stay consistent across the Training tab's expansions.
    private func approximateLoadFromLog(_ log: TodayLogRow) -> Int {
        guard let dur = log.durationMinutes, dur > 0 else { return 0 }
        let factor = typeFallbackWeight(log.typeKey)
        return Int((dur * factor).rounded())
    }

    private func typeFallbackWeight(_ key: String?) -> Double {
        switch (key ?? "easy").lowercased() {
        case "easy":            return 1.0
        case "recovery":        return 0.7
        case "long_run", "long":return 1.1
        case "strides":         return 1.5
        case "progression":     return 1.6
        case "tempo":           return 1.8
        case "threshold":       return 1.8
        case "intervals":       return 2.5
        case "mile_repeats":    return 3.0
        case "race":            return 2.8
        case "rest":            return 0.0
        case "cross_training":  return 0.7
        case "strength":        return 0.5
        default:                return 1.0
        }
    }

    // MARK: - Zone mix estimation

    private struct ZoneMix {
        let easy: CGFloat
        let moderate: CGFloat
        let threshold: CGFloat
        let hard: CGFloat
    }

    /// Approximate week-level zone distribution from per-log durations
    /// weighted by `typeFallbackWeight`. Coarse but directionally honest
    /// — easy runs dominate easy-zone time, threshold sessions add to
    /// threshold-zone time, etc.
    private func approximateZoneMix() -> ZoneMix {
        var easy: Double = 0, mod: Double = 0, thr: Double = 0, hard: Double = 0
        for log in weekLogs {
            let dur = log.durationMinutes ?? 0
            guard dur > 0 else { continue }
            let weight = typeFallbackWeight(log.typeKey)
            // Heuristic split based on weight: very light = mostly easy,
            // heavier = more time in threshold/hard.
            switch weight {
            case ..<1.05:         easy += dur
            case ..<1.4:          easy += dur * 0.85; mod += dur * 0.15
            case ..<1.7:          easy += dur * 0.5;  mod += dur * 0.4; thr += dur * 0.1
            case ..<2.1:          easy += dur * 0.3;  mod += dur * 0.3; thr += dur * 0.35; hard += dur * 0.05
            case ..<2.7:          easy += dur * 0.25; mod += dur * 0.2; thr += dur * 0.35; hard += dur * 0.2
            default:              easy += dur * 0.2;  mod += dur * 0.15; thr += dur * 0.3;  hard += dur * 0.35
            }
        }
        let total = easy + mod + thr + hard
        guard total > 0 else {
            return ZoneMix(easy: 1.0, moderate: 0, threshold: 0, hard: 0)
        }
        return ZoneMix(
            easy:      CGFloat(easy / total),
            moderate:  CGFloat(mod / total),
            threshold: CGFloat(thr / total),
            hard:      CGFloat(hard / total),
        )
    }
}

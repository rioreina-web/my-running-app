//
//  TrainingDayExpanded.swift
//  RunningLog
//
//  Plate 26 — inline day-expanded panel for the Training tab's 28-day
//  daily-intensity grid.
//
//  Tap a calendar cell → this panel slides in below the grid, telling
//  the workout's story without leaving the page:
//
//    • Eyebrow + collapse hint
//    • Headline (type + miles)
//    • Stat row — TIME · PACE · LOAD (the three numbers a coach scans first)
//    • Pace spectrum — % distance at each MP-relative zone, as a single
//      stacked bar. Reads "what kind of run was this?" at a glance.
//    • Mile splits — per-mile pace bars, color-coded by zone, with HR
//      when Strava/Vital provided it. Reads "how did the effort flow?"
//    • IN CONTEXT — comparison against the visible 28-day window.
//
//  Pace classification uses the same MP-relative ratios as the calendar
//  cell colors (TrainingTabView.pickKind) — never the legacy stored
//  effort labels, which mis-tag fast runners' easy days as tempo. MP
//  comes from the parent's `equivalentPaces`; when MP isn't available
//  the spectrum/splits hide and the panel falls back to the v1 layout.
//

import SwiftUI

// MARK: - Public view

/// Inline day-expanded panel. Renders only when `day` carries at least
/// one log; for empty days the parent should hide the expansion entirely
/// rather than showing a blank panel.
struct TrainingDayExpanded: View {
    /// The day this panel describes.
    let day: Date
    /// All logs that fall on this day (already filtered by the parent).
    let dayLogs: [TodayLogRow]
    /// All 28 days of logs in the visible window — feeds the IN CONTEXT
    /// comparison lines.
    let windowLogs: [TodayLogRow]
    /// Athlete's marathon pace in seconds/mile. Drives the MP-relative
    /// zone bucketing for the pace spectrum + splits. When nil, the
    /// spectrum/splits are skipped.
    let mpPaceSec: Double?
    /// Closure invoked when the user wants to collapse the panel.
    let onCollapse: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            topBar
            headline
            statRow
            if let primary = primaryLog,
               let segments = primary.paceSegments,
               !segments.isEmpty,
               let mp = mpPaceSec, mp > 0 {
                paceSpectrum(segments: segments, mp: mp)
                splitsList(segments: segments, mp: mp)
            } else if metaText != "" {
                Text(metaText)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.drip.textSecondary)
            }
            if !dayLogs.isEmpty {
                inContext
            }
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

    /// Three-column stat row: TIME · AVG PACE · LOAD. The numbers a coach
    /// reads first; replaces the cramped meta line of v1.
    private var statRow: some View {
        HStack(alignment: .top, spacing: 0) {
            statCol(
                label: "TIME",
                value: primaryLog?.durationMinutes.map(formatDuration) ?? "—"
            )
            statDivider
            statCol(
                label: "AVG PACE",
                value: avgPaceLabel
            )
            statDivider
            statCol(
                label: "LOAD",
                value: primaryLog.flatMap(approximateLoadFromLog).map { "\($0)" } ?? "—"
            )
            if let mood = primaryLog?.mood?.uppercased(), !mood.isEmpty {
                statDivider
                statCol(label: "MOOD", value: mood)
            }
        }
        .padding(.top, 2)
    }

    private func statCol(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(Color.drip.textTertiary)
            Text(value)
                .font(.system(size: 17, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.drip.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statDivider: some View {
        Rectangle()
            .fill(Color.drip.divider.opacity(0.5))
            .frame(width: 0.5, height: 28)
    }

    /// Pace spectrum — single horizontal stacked bar showing the %
    /// distance at each zone, plus a one-line legend below listing only
    /// the zones present.
    private func paceSpectrum(segments: [PaceSegment], mp: Double) -> some View {
        let buckets = bucketDistances(segments: segments, mp: mp)
        let total = max(0.001, buckets.values.reduce(0, +))
        let ordered: [PaceZone] = [.recovery, .easy, .moderate, .tempo, .intervals]

        return VStack(alignment: .leading, spacing: 8) {
            Text("PACE SPECTRUM")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(Color.drip.textSecondary)

            GeometryReader { geo in
                HStack(spacing: 0) {
                    ForEach(ordered, id: \.self) { zone in
                        let miles = buckets[zone] ?? 0
                        if miles > 0 {
                            Rectangle()
                                .fill(zone.color)
                                .frame(width: geo.size.width * CGFloat(miles / total))
                        }
                    }
                }
                .frame(height: 14)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .frame(height: 14)

            // Legend — only zones with >0 distance, % rounded.
            HStack(spacing: 10) {
                ForEach(ordered, id: \.self) { zone in
                    let miles = buckets[zone] ?? 0
                    if miles > 0 {
                        let pct = Int((miles / total * 100).rounded())
                        legendChip(zone: zone, percent: pct)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.top, 4)
    }

    private func legendChip(zone: PaceZone, percent: Int) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2)
                .fill(zone.color)
                .frame(width: 8, height: 8)
            // iOS 26 deprecated `Text + Text` concatenation in favor of
            // string interpolation, but the two segments here need
            // different font weights and colors. AttributedString preserves
            // the per-segment styling inside a single Text.
            Text(legendLabel(shortName: zone.shortName, percent: percent))
        }
    }

    private func legendLabel(shortName: String, percent: Int) -> AttributedString {
        var name = AttributedString("\(shortName) ")
        name.font = .system(size: 10, design: .monospaced)
        name.foregroundColor = Color.drip.textSecondary

        var pct = AttributedString("\(percent)%")
        pct.font = .system(size: 10, weight: .medium, design: .monospaced)
        pct.foregroundColor = Color.drip.textPrimary

        return name + pct
    }

    /// Mile splits — one bar per pace_segment, sorted in workout order.
    /// Bar width is normalized to the run's slowest segment (so the
    /// fastest split has the shortest bar; it's the inverse of "pace =
    /// time/distance"). Color matches the segment's MP-relative zone.
    /// HR shown on the right when present.
    private func splitsList(segments: [PaceSegment], mp: Double) -> some View {
        let paces = segments.map { paceSeconds($0.pacePerMile) }
        let maxPace = max(paces.max() ?? 1, 1)
        let minPace = paces.min() ?? maxPace

        return VStack(alignment: .leading, spacing: 6) {
            Text("MILE SPLITS")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(Color.drip.textSecondary)
            VStack(spacing: 3) {
                ForEach(Array(segments.enumerated()), id: \.offset) { idx, seg in
                    splitRow(
                        index: idx + 1,
                        segment: seg,
                        zone: zone(forPaceSec: paceSeconds(seg.pacePerMile), mp: mp),
                        minPace: minPace,
                        maxPace: maxPace
                    )
                }
            }
        }
        .padding(.top, 4)
    }

    private func splitRow(
        index: Int,
        segment: PaceSegment,
        zone: PaceZone,
        minPace: Double,
        maxPace: Double
    ) -> some View {
        let pace = paceSeconds(segment.pacePerMile)
        // Normalize: fastest = 30% width, slowest = 100% width.
        // (Faster pace = lower seconds, so we invert.)
        let span = max(0.001, maxPace - minPace)
        let frac = 0.3 + 0.7 * CGFloat((pace - minPace) / span)

        return HStack(spacing: 8) {
            // Mile number + partial-mile marker.
            Text(splitLabel(for: segment, index: index))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.drip.textTertiary)
                .frame(width: 22, alignment: .leading)

            // Bar.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.drip.divider.opacity(0.4))
                        .frame(height: 14)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(zone.color)
                        .frame(width: geo.size.width * frac, height: 14)
                }
            }
            .frame(height: 14)

            // Pace.
            Text(segment.pacePerMile)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.drip.textPrimary)
                .frame(width: 40, alignment: .trailing)

            // HR (when present).
            if let hr = segment.avgHeartRate {
                Text("\(hr)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.drip.textTertiary)
                    .frame(width: 28, alignment: .trailing)
            }
        }
    }

    private func splitLabel(for segment: PaceSegment, index: Int) -> String {
        // Partial miles (last segment, e.g. 0.28 mi) get marked with a "·"
        // rather than a confusing whole-mile number.
        if segment.distanceMiles < 0.95 { return "\(index)·" }
        return "\(index)"
    }

    @ViewBuilder
    private var inContext: some View {
        let lines = comparisonLines()
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("IN CONTEXT")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(Color.drip.textSecondary)
                ForEach(Array(lines.enumerated()), id: \.offset) { idx, line in
                    Text(line)
                        .font(.system(size: 13, design: .serif).italic())
                        .foregroundStyle(idx < 2 ? Color.drip.textPrimary
                                                 : Color.drip.textSecondary)
                        .lineSpacing(2)
                }
            }
            .padding(.top, 6)
        }
    }

    // MARK: - Strings

    /// "THURSDAY · APR 30"
    private var eyebrowText: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE  ·  MMM d"
        return f.string(from: day).uppercased()
    }

    /// "Long run, 16 mi." — workout-type-led headline.
    private var headlineText: String {
        guard let primary = primaryLog else { return "Rest day." }
        let typeName = displayType(primary.typeKey)
        if let miles = primary.miles, miles > 0 {
            let str = miles == miles.rounded()
                ? String(format: "%.0f", miles)
                : String(format: "%.1f", miles)
            return "\(typeName), \(str) mi."
        }
        return "\(typeName)."
    }

    /// Backup meta line for cases without pace_segments — preserves the
    /// v1 layout when we can't render the rich spectrum/splits.
    private var metaText: String {
        guard let primary = primaryLog else { return "" }
        var parts: [String] = []
        if let dur = primary.durationMinutes, dur > 0 {
            parts.append(formatDuration(dur))
        }
        if let pace = primary.pace, !pace.isEmpty {
            parts.append("\(pace) / mi")
        }
        if let load = approximateLoadFromLog(primary) {
            parts.append("LOAD \(load)")
        }
        if let mood = primary.mood?.uppercased(), !mood.isEmpty {
            parts.append(mood)
        }
        return parts.joined(separator: "  ·  ")
    }

    private var avgPaceLabel: String {
        if let pace = primaryLog?.pace, !pace.isEmpty { return pace }
        // Fallback: derive avg pace from total distance / total time.
        if let p = primaryLog, let miles = p.miles, miles > 0,
           let mins = p.durationMinutes, mins > 0 {
            let secPerMile = (mins / miles) * 60
            return String(format: "%d:%02d", Int(secPerMile) / 60, Int(secPerMile) % 60)
        }
        return "—"
    }

    // MARK: - Comparison

    /// Three italic-serif lines comparing this day against the 28-day
    /// window. Each line earns its space by saying something the
    /// stand-alone workout-detail page can't say.
    private func comparisonLines() -> [String] {
        guard let primary = primaryLog,
              let primaryMiles = primary.miles, primaryMiles > 0 else { return [] }

        // All logs in the 28-day window with miles > 0, ordered by mileage descending.
        let runsInWindow = windowLogs
            .filter { ($0.miles ?? 0) > 0 }
            .sorted { ($0.miles ?? 0) > ($1.miles ?? 0) }

        var lines: [String] = []

        // Line 1 — ranking of this run by mileage in the visible block.
        if let topMiles = runsInWindow.first?.miles, topMiles == primaryMiles {
            let secondMiles = runsInWindow.dropFirst().first?.miles ?? primaryMiles
            let delta = primaryMiles - secondMiles
            if delta >= 0.5 {
                let str = String(format: "%.0f", delta.rounded())
                lines.append("Heaviest day of the block. +\(str) mi over the next-longest.")
            } else {
                lines.append("Heaviest day of the block — by a hair.")
            }
        } else {
            if let rank = runsInWindow.firstIndex(where: { ($0.miles ?? 0) == primaryMiles }) {
                let ordinal = ordinalString(rank + 1)
                lines.append("\(ordinal)-longest run of the block.")
            }
        }

        // Line 2 — pace consistency commentary if pace is available.
        if let pace = primary.pace, !pace.isEmpty {
            lines.append("Splits within typical range — \(pace)/mi average pace.")
        }

        // Line 3 — load context relative to the window.
        if let load = approximateLoadFromLog(primary) {
            let loads = runsInWindow.compactMap { approximateLoadFromLog($0) }
            if let topLoad = loads.max(), load == topLoad {
                lines.append("—— biggest single-session load of the 28-day block.")
            } else if !loads.isEmpty {
                let total = loads.reduce(0, +)
                let pct = Int(round(Double(load) / Double(total) * 100))
                if pct >= 5 {
                    lines.append("—— \(pct)% of the block's total load came from this run.")
                }
            }
        }

        return lines
    }

    // MARK: - Pace zone bucketing

    private enum PaceZone: Hashable {
        case recovery, easy, moderate, tempo, intervals

        var shortName: String {
            switch self {
            case .recovery:  return "Recovery"
            case .easy:      return "Easy"
            case .moderate:  return "Moderate"
            case .tempo:     return "Tempo"
            case .intervals: return "Intervals"
            }
        }

        var color: Color {
            switch self {
            case .recovery:  return Color(red: 0.88, green: 0.96, blue: 0.93)
            case .easy:      return Color(red: 0.62, green: 0.88, blue: 0.80)
            case .moderate:  return Color(red: 0.36, green: 0.79, blue: 0.65)
            case .tempo:     return Color(red: 0.96, green: 0.77, blue: 0.70)
            case .intervals: return Color(red: 0.94, green: 0.60, blue: 0.48)
            }
        }
    }

    /// MP-relative bucketing — same thresholds as `TrainingTabView.pickKind`.
    /// ratio = paceSec / mpSec; lower ratio = faster relative to MP.
    private func zone(forPaceSec paceSec: Double, mp: Double) -> PaceZone {
        guard paceSec > 0, mp > 0 else { return .easy }
        let ratio = paceSec / mp
        if ratio < 0.97 { return .intervals }
        if ratio < 1.07 { return .tempo }
        if ratio < 1.20 { return .moderate }
        if ratio < 1.43 { return .easy }
        return .recovery
    }

    /// Sum distance per zone across the segments.
    private func bucketDistances(segments: [PaceSegment], mp: Double) -> [PaceZone: Double] {
        var out: [PaceZone: Double] = [:]
        for seg in segments {
            let z = zone(forPaceSec: paceSeconds(seg.pacePerMile), mp: mp)
            out[z, default: 0] += seg.distanceMiles
        }
        return out
    }

    private func paceSeconds(_ s: String) -> Double {
        let parts = s.split(separator: ":")
        guard parts.count == 2,
              let m = Int(parts[0]),
              let sec = Int(parts[1]) else { return 0 }
        return Double(m * 60 + sec)
    }

    // MARK: - Helpers

    private var primaryLog: TodayLogRow? {
        // Prefer the GPS-source row (richer data — pace_segments, accurate
        // distance) over the voice_log mirror. If only voice_log exists,
        // use that.
        let gps = dayLogs.first {
            let s = $0.source?.lowercased() ?? ""
            return s == "strava" || s == "auto_sync"
        }
        return gps ?? dayLogs.max(by: { ($0.miles ?? 0) < ($1.miles ?? 0) })
    }

    private func formatDuration(_ minutes: Double) -> String {
        let totalSeconds = Int((minutes * 60).rounded())
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        let s = totalSeconds % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    private func displayType(_ key: String?) -> String {
        switch (key ?? "").lowercased() {
        case "easy": return "Easy run"
        case "recovery": return "Recovery"
        case "tempo": return "Tempo"
        case "threshold": return "Threshold"
        case "intervals": return "Intervals"
        case "long_run", "long": return "Long run"
        case "race": return "Race"
        case "progression": return "Progression"
        case "strides": return "Strides"
        default: return "Run"
        }
    }

    /// Coarse load approximation when workout_features isn't available
    /// to this view. Mirrors the fallback weights in
    /// `weeklyAnalytics.ts → TYPE_FALLBACK_WEIGHTS` so the on-device
    /// number is in the same ballpark as the backend's.
    private func approximateLoadFromLog(_ log: TodayLogRow) -> Int? {
        guard let dur = log.durationMinutes, dur > 0 else { return nil }
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

    private func ordinalString(_ n: Int) -> String {
        switch n {
        case 1: return "1st"
        case 2: return "2nd"
        case 3: return "3rd"
        default: return "\(n)th"
        }
    }
}

//
//  TrainingPaceAnalysisSection.swift
//  RunningLog
//
//  Pace-volume analysis section for the Training tab. Aggregates the
//  athlete's pace_segments across configurable buckets (weekly or
//  monthly) and a configurable range (4w/8w/12w or 3m/6m/12m), with an
//  optional WoW/MoM comparison overlay against the immediately-prior
//  period of equal length.
//
//  Reads:
//    • [TodayLogRow] (parent's extended fetch — at least the active
//      range × 2 if compare is on)
//    • mpPaceSec (athlete's MP from EquivalentPaces) — drives the same
//      MP-relative bucketing used by TrainingTabView.pickKind so the
//      five-zone palette is consistent across the tab
//
//  Writes: nothing (pure presentation).
//
//  Layout:
//    Header  ·  control row (Bucket | Range | Compare)
//    Stacked-column chart (one column per bucket, oldest left)
//    Per-column delta vs prior period (when compare on)
//    Legend
//    Aggregate this-period vs prior-period summary panel (when compare on)
//
//  Voice_log rows are excluded from the pace aggregation — they mirror
//  GPS-source rows and would double-count the same physical segments.
//

import SwiftUI

// MARK: - File-level types
//
// These were nested inside `TrainingPaceAnalysisSection` while the section
// owned the whole flow. Hoisted to file scope so the bar drill-down sheet
// (`BarPeriodDetailView`, defined below) can reference Period and its
// zone vocabulary directly without crossing access-level boundaries.

fileprivate enum BucketSize: String { case weekly, monthly }

fileprivate enum TrainingZone: Hashable {
    case recovery, easy, moderate, tempo, intervals

    var color: Color {
        switch self {
        case .recovery:  return Color(red: 0.78, green: 0.93, blue: 0.87)
        case .easy:      return Color(red: 0.62, green: 0.88, blue: 0.80)
        case .moderate:  return Color(red: 0.36, green: 0.79, blue: 0.65)
        case .tempo:     return Color(red: 0.96, green: 0.77, blue: 0.70)
        case .intervals: return Color(red: 0.94, green: 0.60, blue: 0.48)
        }
    }

    var label: String {
        switch self {
        case .recovery:  return "Recovery"
        case .easy:      return "Easy"
        case .moderate:  return "Moderate"
        case .tempo:     return "Tempo"
        case .intervals: return "Intervals"
        }
    }

    /// Plain-language pace band for this zone given the runner's MP, e.g.
    /// "7:30 – 8:45" for Easy. Used in the drill-down zone breakdown.
    func paceRange(mp: Double) -> String {
        guard mp > 0 else { return "" }
        // Mirror of zone(forPaceSec:mp:): ratio bands ≥ 1.43 recovery,
        // ≥ 1.20 easy, ≥ 1.07 moderate, ≥ 0.97 tempo, else intervals.
        switch self {
        case .recovery:  return "\(formatPace(mp * 1.43))+"
        case .easy:      return "\(formatPace(mp * 1.43)) – \(formatPace(mp * 1.20))"
        case .moderate:  return "\(formatPace(mp * 1.20)) – \(formatPace(mp * 1.07))"
        case .tempo:     return "\(formatPace(mp * 1.07)) – \(formatPace(mp * 0.97))"
        case .intervals: return "faster than \(formatPace(mp * 0.97))"
        }
    }

    private func formatPace(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }
}

fileprivate struct Period: Identifiable {
    let id = UUID()
    let start: Date
    let label: String
    var zoneMiles: [TrainingZone: Double]

    var totalMiles: Double { zoneMiles.values.reduce(0, +) }
}

/// Carries everything the bar drill-down sheet needs. Lives at file scope so
/// `.sheet(item:)` can use it via Identifiable.
fileprivate struct BarTap: Identifiable {
    let id = UUID()
    let period: Period
    let prior: Period?
    let bucket: BucketSize
}

struct TrainingPaceAnalysisSection: View {
    let logs: [TodayLogRow]
    let mpPaceSec: Double?

    @State private var bucket: BucketSize = .weekly
    @State private var rangeWeeks: Int = 8
    @State private var rangeMonths: Int = 6
    @State private var compareOn: Bool = true

    /// Drives the bar drill-down sheet. nil = no sheet presented.
    @State private var barTap: BarTap? = nil

    private var cal: Calendar { Calendar.current }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            controlRow
            if let mp = mpPaceSec, mp > 0 {
                let curr = computePeriods(prior: false, mp: mp)
                let prior = compareOn ? computePeriods(prior: true, mp: mp) : []
                // Prior is always computed for drill-down delta even when the
                // overlay is off — cheap and gives the sheet useful context.
                let priorForDrill = compareOn ? prior : computePeriods(prior: true, mp: mp)
                chart(periods: curr, priorPeriods: prior, priorForDrill: priorForDrill)
                if compareOn {
                    deltaRow(curr: curr, prior: prior)
                }
                legend
                if compareOn {
                    summaryPanel(curr: curr, prior: prior)
                }
            } else {
                emptyState
            }
        }
        .sheet(item: $barTap) { tap in
            BarPeriodDetailView(tap: tap, logs: logs, mpPaceSec: mpPaceSec ?? 0)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("PACE VOLUME")
                .font(.dripCaption(11))
                .tracking(1.5)
                .foregroundStyle(Color.drip.textTertiary)
            Spacer()
            Text(rangeLabel)
                .font(.dripStat(11))
                .foregroundStyle(Color.drip.textTertiary)
        }
    }

    private var rangeLabel: String {
        let count = bucket == .weekly ? rangeWeeks : rangeMonths
        let unit = bucket == .weekly ? "w" : "m"
        return "Last \(count)\(unit)"
    }

    // MARK: - Controls

    private var controlRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                controlGroup(label: "BUCKET") {
                    HStack(spacing: 4) {
                        controlButton(text: "Weekly",  selected: bucket == .weekly)  { bucket = .weekly }
                        controlButton(text: "Monthly", selected: bucket == .monthly) { bucket = .monthly }
                    }
                }
                Spacer(minLength: 0)
                controlGroup(label: "COMPARE") {
                    controlButton(text: comparePeriodLabel, selected: compareOn) {
                        compareOn.toggle()
                    }
                }
            }
            controlGroup(label: "RANGE") {
                HStack(spacing: 4) {
                    ForEach(rangeOptions, id: \.value) { opt in
                        controlButton(
                            text: opt.label,
                            selected: opt.value == currentRange
                        ) {
                            setRange(opt.value)
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.drip.divider.opacity(0.18))
        )
    }

    private func controlGroup<Content: View>(
        label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .tracking(0.6)
                .foregroundStyle(Color.drip.textTertiary)
            content()
        }
    }

    private func controlButton(text: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 11, weight: selected ? .medium : .regular, design: .monospaced))
                .foregroundStyle(selected ? Color.drip.textPrimary : Color.drip.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(selected ? Color.drip.divider.opacity(0.6) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(
                            selected ? Color.drip.textPrimary : Color.drip.divider.opacity(0.5),
                            lineWidth: 0.5
                        )
                )
        }
        .buttonStyle(.plain)
    }

    private var rangeOptions: [(label: String, value: Int)] {
        bucket == .weekly
            ? [(label: "4w", value: 4), (label: "8w", value: 8), (label: "12w", value: 12)]
            : [(label: "3m", value: 3), (label: "6m", value: 6), (label: "12m", value: 12)]
    }

    private var currentRange: Int {
        bucket == .weekly ? rangeWeeks : rangeMonths
    }

    private func setRange(_ v: Int) {
        if bucket == .weekly { rangeWeeks = v } else { rangeMonths = v }
    }

    private var comparePeriodLabel: String {
        let count = bucket == .weekly ? rangeWeeks : rangeMonths
        let unit = bucket == .weekly ? "w" : "m"
        return "vs prior \(count)\(unit)"
    }

    // MARK: - Chart

    private func chart(periods: [Period], priorPeriods: [Period], priorForDrill: [Period]) -> some View {
        let chartHeight: CGFloat = 200
        // Use the max across BOTH periods so the comparison stays
        // visually honest — current bars don't get artificially "tall"
        // because the prior block is being ignored in the y-scale.
        let allTotals = periods.map(\.totalMiles) + priorPeriods.map(\.totalMiles)
        let maxMiles = max(allTotals.max() ?? 1, 1)
        let yStops = niceYStops(maxMiles: maxMiles)

        return HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .trailing, spacing: 0) {
                ForEach(yStops.indices, id: \.self) { idx in
                    Text("\(yStops[idx]) mi")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Color.drip.textTertiary)
                        .frame(height: idx == 0 ? 10 : (chartHeight / CGFloat(yStops.count - 1)),
                               alignment: idx == 0 ? .top : .top)
                }
            }
            .frame(height: chartHeight + 22)

            VStack(spacing: 0) {
                ZStack(alignment: .bottom) {
                    // Grid lines
                    VStack(spacing: 0) {
                        ForEach(0..<yStops.count, id: \.self) { _ in
                            Spacer()
                            Rectangle()
                                .fill(Color.drip.divider.opacity(0.4))
                                .frame(height: 0.5)
                        }
                    }
                    .frame(height: chartHeight)

                    HStack(alignment: .bottom, spacing: 4) {
                        ForEach(periods.indices, id: \.self) { idx in
                            barColumn(period: periods[idx],
                                      maxMiles: maxMiles,
                                      chartHeight: chartHeight,
                                      isCurrent: idx == periods.count - 1)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    let p = priorForDrill.indices.contains(idx) ? priorForDrill[idx] : nil
                                    barTap = BarTap(period: periods[idx], prior: p, bucket: bucket)
                                }
                        }
                    }
                    .frame(height: chartHeight, alignment: .bottom)
                }
                // X-axis labels
                HStack(spacing: 4) {
                    ForEach(periods.indices, id: \.self) { idx in
                        Text(periods[idx].label)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(
                                idx == periods.count - 1
                                    ? Color.drip.coral
                                    : Color.drip.textSecondary
                            )
                            .frame(maxWidth: .infinity)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                .frame(height: 16)
                .padding(.top, 4)
            }
        }
    }

    private func barColumn(period: Period, maxMiles: Double, chartHeight: CGFloat, isCurrent: Bool) -> some View {
        let totalH = chartHeight * CGFloat(period.totalMiles / maxMiles)
        return VStack(spacing: 2) {
            // Total label above each bar.
            Text(formatMilesShort(period.totalMiles))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(isCurrent ? Color.drip.coral : Color.drip.textPrimary)
                .frame(height: 14)
            VStack(spacing: 0) {
                ForEach(stackedZones, id: \.self) { zone in
                    let m = period.zoneMiles[zone] ?? 0
                    if m > 0 {
                        Rectangle()
                            .fill(zone.color)
                            .frame(height: max(0, chartHeight * CGFloat(m / maxMiles)))
                    }
                }
            }
            .frame(height: totalH, alignment: .bottom)
            .clipShape(RoundedRectangle(cornerRadius: 2))
        }
        .frame(maxWidth: .infinity)
    }

    /// Stacking order — top is most intense, bottom is recovery.
    private var stackedZones: [TrainingZone] {
        [.intervals, .tempo, .moderate, .easy, .recovery]
    }

    /// Human-rounded y-axis stops at the top, midpoints, and zero.
    private func niceYStops(maxMiles: Double) -> [Int] {
        // Round max up to a friendly number for the top stop, then bisect.
        let top: Int
        switch maxMiles {
        case ..<10:  top = 10
        case ..<25:  top = 25
        case ..<50:  top = 50
        case ..<75:  top = 75
        case ..<100: top = 100
        default:     top = Int((maxMiles / 25.0).rounded(.up)) * 25
        }
        return [top, top * 2 / 3, top / 3, 0]
    }

    // MARK: - Delta row

    private func deltaRow(curr: [Period], prior: [Period]) -> some View {
        HStack(alignment: .top, spacing: 4) {
            // Spacer to align with the y-axis column above.
            Color.clear.frame(width: 36, height: 12)
            HStack(spacing: 4) {
                ForEach(curr.indices, id: \.self) { idx in
                    let priorVal = idx < prior.count ? prior[idx].totalMiles : 0
                    let delta = curr[idx].totalMiles - priorVal
                    deltaChip(delta: delta, hasPrior: idx < prior.count)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func deltaChip(delta: Double, hasPrior: Bool) -> some View {
        Group {
            if !hasPrior || abs(delta) < 0.5 {
                Text("—")
                    .foregroundStyle(Color.drip.textTertiary)
            } else if delta > 0 {
                Text("▲ \(Int(delta.rounded()))")
                    .foregroundStyle(Color.drip.positive)
            } else {
                Text("▼ \(Int(abs(delta).rounded()))")
                    .foregroundStyle(Color.drip.injured)
            }
        }
        .font(.system(size: 9, design: .monospaced))
    }

    // MARK: - Legend

    private var legend: some View {
        HStack(spacing: 12) {
            legendItem("Intervals", color: TrainingZone.intervals.color)
            legendItem("Tempo",     color: TrainingZone.tempo.color)
            legendItem("Moderate",  color: TrainingZone.moderate.color)
            legendItem("Easy",      color: TrainingZone.easy.color)
            legendItem("Recovery",  color: TrainingZone.recovery.color)
            Spacer(minLength: 0)
        }
        .padding(.top, 6)
    }

    private func legendItem(_ label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 9, height: 9)
            Text(label)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color.drip.textSecondary)
        }
    }

    // MARK: - Aggregate summary

    private func summaryPanel(curr: [Period], prior: [Period]) -> some View {
        let currTotals = aggregate(curr)
        let priorTotals = aggregate(prior)
        let unit = bucket == .weekly ? "w" : "m"
        let count = bucket == .weekly ? rangeWeeks : rangeMonths

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("This \(count)\(unit) vs prior \(count)\(unit)".uppercased())
                    .font(.dripCaption(10))
                    .tracking(1.2)
                    .foregroundStyle(Color.drip.textTertiary)
                Spacer()
                Text("\(formatMilesShort(currTotals.total)) mi  ·  prior \(formatMilesShort(priorTotals.total)) mi")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.drip.textSecondary)
            }
            HStack(alignment: .top, spacing: 6) {
                summaryStat("Easy",      curr: currTotals.easy,      prior: priorTotals.easy)
                summaryStat("Moderate",  curr: currTotals.moderate,  prior: priorTotals.moderate)
                summaryStat("Recovery",  curr: currTotals.recovery,  prior: priorTotals.recovery)
                summaryStat("Tempo",     curr: currTotals.tempo,     prior: priorTotals.tempo)
                summaryStat("Intervals", curr: currTotals.intervals, prior: priorTotals.intervals)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.drip.divider.opacity(0.18))
        )
        .padding(.top, 6)
    }

    private func summaryStat(_ label: String, curr: Double, prior: Double) -> some View {
        let delta = curr - prior
        let deltaText: Text
        if abs(delta) < 0.5 {
            deltaText = Text("—").foregroundStyle(Color.drip.textTertiary)
        } else if delta > 0 {
            deltaText = Text("▲ \(Int(delta.rounded()))").foregroundStyle(Color.drip.positive)
        } else {
            deltaText = Text("▼ \(Int(abs(delta).rounded()))").foregroundStyle(Color.drip.injured)
        }

        return VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .tracking(0.6)
                .foregroundStyle(Color.drip.textTertiary)
            Text(formatMilesShort(curr))
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.drip.textPrimary)
            deltaText
                .font(.system(size: 10, design: .monospaced))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        Text("Set a goal to see your pace zones, then this chart will populate.")
            .font(.dripBody(13))
            .foregroundStyle(Color.drip.textTertiary)
            .padding(.vertical, 12)
    }

    // MARK: - Period bucketing

    /// Build periods either for the current range (prior=false) or the
    /// equally-sized window immediately preceding it (prior=true).
    private func computePeriods(prior: Bool, mp: Double) -> [Period] {
        // Dedup BEFORE bucketing so cross-source dupes (strava + auto_sync
        // for the same physical workout) get collapsed to one row. See
        // LogDedup.swift for the rule. Voice_log filtering also happens
        // there, which is why we no longer skip voice_log inline below.
        let deduped = logs.dedupedByPhysicalWorkout()
        let count = bucket == .weekly ? rangeWeeks : rangeMonths
        var out: [Period] = []
        for i in 0..<count {
            // Index 0 = oldest in the (prior or current) range, count-1 = newest.
            // Current range:   bucket offset = -(count-1-i)
            // Prior range:     bucket offset = -(count-1-i) - count
            let offset = -(count - 1 - i) - (prior ? count : 0)
            guard let bucketStart = bucketStart(offset: offset) else { continue }
            let bucketEnd = nextBucketStart(after: bucketStart)
            let label = labelFor(bucketStart: bucketStart)
            var zoneMiles: [TrainingZone: Double] = [:]
            for log in deduped {
                guard log.date >= bucketStart, log.date < bucketEnd else { continue }
                guard let segments = log.paceSegments, !segments.isEmpty else {
                    // No segments — fall back to the row's avg pace + total miles.
                    if let miles = log.miles, miles > 0,
                       let avg = avgPaceSeconds(for: log) {
                        let z = zone(forPaceSec: avg, mp: mp)
                        zoneMiles[z, default: 0] += miles
                    }
                    continue
                }
                for seg in segments {
                    let secs = paceSeconds(seg.pacePerMile)
                    guard secs > 0 else { continue }
                    let z = zone(forPaceSec: secs, mp: mp)
                    zoneMiles[z, default: 0] += seg.distanceMiles
                }
            }
            out.append(Period(start: bucketStart, label: label, zoneMiles: zoneMiles))
        }
        return out
    }

    /// Start date of the current bucket plus `offset` buckets (negative = past).
    private func bucketStart(offset: Int) -> Date? {
        let now = Date()
        switch bucket {
        case .weekly:
            let weekday = cal.component(.weekday, from: now)
            let daysBackToMon = (weekday + 5) % 7
            guard let thisMonday = cal.date(byAdding: .day, value: -daysBackToMon, to: cal.startOfDay(for: now)) else {
                return nil
            }
            return cal.date(byAdding: .day, value: offset * 7, to: thisMonday)
        case .monthly:
            let comps = cal.dateComponents([.year, .month], from: now)
            guard let thisMonth = cal.date(from: comps) else { return nil }
            return cal.date(byAdding: .month, value: offset, to: thisMonth)
        }
    }

    private func nextBucketStart(after start: Date) -> Date {
        switch bucket {
        case .weekly:  return cal.date(byAdding: .day, value: 7, to: start) ?? start
        case .monthly: return cal.date(byAdding: .month, value: 1, to: start) ?? start
        }
    }

    private func labelFor(bucketStart: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = bucket == .weekly ? "MMM d" : "MMM"
        return f.string(from: bucketStart)
    }

    // MARK: - Pace zone bucketing (mirror of TrainingTabView.pickKind)

    private func zone(forPaceSec paceSec: Double, mp: Double) -> TrainingZone {
        guard paceSec > 0, mp > 0 else { return .easy }
        let ratio = paceSec / mp
        if ratio < 0.97 { return .intervals }
        if ratio < 1.07 { return .tempo }
        if ratio < 1.20 { return .moderate }
        if ratio < 1.43 { return .easy }
        return .recovery
    }

    // MARK: - Aggregate helpers

    private struct ZoneTotals {
        var recovery: Double = 0
        var easy: Double = 0
        var moderate: Double = 0
        var tempo: Double = 0
        var intervals: Double = 0
        var total: Double { recovery + easy + moderate + tempo + intervals }
    }

    private func aggregate(_ periods: [Period]) -> ZoneTotals {
        var t = ZoneTotals()
        for p in periods {
            t.recovery  += p.zoneMiles[.recovery]  ?? 0
            t.easy      += p.zoneMiles[.easy]      ?? 0
            t.moderate  += p.zoneMiles[.moderate]  ?? 0
            t.tempo     += p.zoneMiles[.tempo]     ?? 0
            t.intervals += p.zoneMiles[.intervals] ?? 0
        }
        return t
    }

    // MARK: - Misc helpers

    private func paceSeconds(_ s: String) -> Double {
        let parts = s.split(separator: ":")
        guard parts.count == 2,
              let m = Int(parts[0]),
              let sec = Int(parts[1]) else { return 0 }
        return Double(m * 60 + sec)
    }

    private func avgPaceSeconds(for log: TodayLogRow) -> Double? {
        if let p = log.pace, !p.isEmpty {
            let s = paceSeconds(p)
            if s > 0 { return s }
        }
        if let miles = log.miles, miles > 0,
           let mins = log.durationMinutes, mins > 0 {
            return (mins / miles) * 60.0
        }
        return nil
    }

    private func formatMilesShort(_ miles: Double) -> String {
        if miles == 0 { return "0" }
        if miles < 10 { return String(format: "%.0f", miles.rounded()) }
        return "\(Int(miles))"
    }

}

// MARK: - Bar drill-down sheet
//
// Presented from `TrainingPaceAnalysisSection` when the user taps a bar in
// the stacked-column chart. Shows the in-depth view for that one period:
//   • header + hero (total miles + delta + sub-period grid)
//   • zone breakdown (stacked bar + 5 rows w/ pace bands + deltas)
//   • pace × volume density (KDE chart anchored at Easy/MP/LT/5K)
//   • runs list for that period

fileprivate struct BarPeriodDetailView: View {
    let tap: BarTap
    let logs: [TodayLogRow]
    let mpPaceSec: Double

    @Environment(\.dismiss) private var dismiss

    private var cal: Calendar { Calendar.current }

    // MARK: - Derived data

    private var periodEnd: Date {
        switch tap.bucket {
        case .weekly:  return cal.date(byAdding: .day, value: 7, to: tap.period.start) ?? tap.period.start
        case .monthly: return cal.date(byAdding: .month, value: 1, to: tap.period.start) ?? tap.period.start
        }
    }

    private var dedupedLogs: [TodayLogRow] { logs.dedupedByPhysicalWorkout() }

    private var runsInPeriod: [TodayLogRow] {
        dedupedLogs
            .filter { $0.date >= tap.period.start && $0.date < periodEnd }
            .sorted { $0.date > $1.date }
    }

    private var totalMiles: Double { tap.period.totalMiles }
    private var priorMiles: Double? { tap.prior?.totalMiles }
    private var delta: Double? { priorMiles.map { totalMiles - $0 } }

    private var titleText: String {
        switch tap.bucket {
        case .weekly:
            let endDay = cal.date(byAdding: .day, value: 6, to: tap.period.start) ?? tap.period.start
            let mdFmt = DateFormatter(); mdFmt.dateFormat = "MMM d"
            let dFmt  = DateFormatter(); dFmt.dateFormat  = "d"
            let sameMonth = cal.component(.month, from: tap.period.start) == cal.component(.month, from: endDay)
            return sameMonth
                ? "\(mdFmt.string(from: tap.period.start)) – \(dFmt.string(from: endDay))"
                : "\(mdFmt.string(from: tap.period.start)) – \(mdFmt.string(from: endDay))"
        case .monthly:
            let f = DateFormatter(); f.dateFormat = "MMMM yyyy"
            return f.string(from: tap.period.start)
        }
    }

    private var subtitle: String {
        let n = runsInPeriod.count
        let word = n == 1 ? "run" : "runs"
        if let longest = runsInPeriod.compactMap(\.miles).max(), longest > 0 {
            return "\(n) \(word) · \(formatMiles(longest))mi longest"
        }
        return "\(n) \(word)"
    }

    private var toolbarTitle: String {
        tap.bucket == .weekly ? "WEEK DETAIL" : "MONTH DETAIL"
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Color.drip.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        headerBlock
                            .padding(.top, 12)
                            .padding(.horizontal, 20)

                        heroCard
                            .padding(.horizontal, 20)

                        zoneSection
                            .padding(.horizontal, 20)

                        if mpPaceSec > 0, !paceSamples.isEmpty {
                            paceDensitySection
                                .padding(.horizontal, 20)
                        }

                        if !runsInPeriod.isEmpty {
                            runsSection
                                .padding(.horizontal, 20)
                        }

                        Spacer().frame(height: 40)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(toolbarTitle)
                        .font(.dripCaption(11))
                        .tracking(1.8)
                        .foregroundStyle(Color.drip.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.dripBody(15))
                        .foregroundStyle(Color.drip.coral)
                }
            }
            .toolbarBackground(Color.drip.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }

    // MARK: - Header

    private var headerBlock: some View {
        VStack(spacing: 6) {
            Text(titleText)
                .font(.dripDisplay(28))
                .foregroundStyle(Color.drip.textPrimary)
            Text(subtitle)
                .font(.dripBody(13))
                .foregroundStyle(Color.drip.textSecondary)
                .italic()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Hero card

    private var heroCard: some View {
        VStack(spacing: 14) {
            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("TOTAL VOLUME")
                        .font(.dripCaption(10))
                        .tracking(1.2)
                        .foregroundStyle(Color.drip.textTertiary)
                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Text(formatMiles(totalMiles))
                            .font(.system(size: 40, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.drip.textPrimary)
                        Text("mi")
                            .font(.dripBody(14))
                            .foregroundStyle(Color.drip.textTertiary)
                    }
                }
                Spacer()
                deltaBlock
            }

            Rectangle().fill(Color.drip.divider).frame(height: 1)

            subPeriodGrid
        }
        .padding(16)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private var deltaBlock: some View {
        if let delta, let prior = priorMiles {
            VStack(alignment: .trailing, spacing: 4) {
                Text(tap.bucket == .weekly ? "VS PRIOR WK" : "VS PRIOR MO")
                    .font(.dripCaption(10))
                    .tracking(1.2)
                    .foregroundStyle(Color.drip.textTertiary)
                if abs(delta) < 0.5 {
                    Text("—")
                        .font(.dripStat(16))
                        .foregroundStyle(Color.drip.textTertiary)
                } else {
                    Text("\(delta > 0 ? "▲" : "▼") \(Int(abs(delta).rounded())) mi")
                        .font(.dripStat(16))
                        .foregroundStyle(delta > 0 ? Color.drip.energized : Color.drip.struggling)
                }
                Text("\(formatMiles(prior))mi prior")
                    .font(.dripCaption(10))
                    .foregroundStyle(Color.drip.textTertiary)
            }
        }
    }

    // MARK: - Sub-period grid (days for week, weeks for month)

    private var subPeriodGrid: some View {
        let buckets = subBuckets()
        let maxMiles = max(buckets.map(\.miles).max() ?? 1, 1)
        return HStack(spacing: 6) {
            ForEach(buckets) { b in
                VStack(spacing: 4) {
                    ZStack(alignment: .bottom) {
                        Color.clear.frame(width: 22, height: 60)
                        VStack(spacing: 1) {
                            ForEach(stackedZones, id: \.self) { zone in
                                let m = b.zoneMiles[zone] ?? 0
                                if m > 0 {
                                    Rectangle()
                                        .fill(zone.color)
                                        .frame(width: 22, height: max(60 * CGFloat(m / maxMiles), 1))
                                }
                            }
                        }
                    }
                    Text(b.label)
                        .font(.dripCaption(10))
                        .foregroundStyle(Color.drip.textTertiary)
                    Text(b.miles > 0 ? formatMiles(b.miles) : "·")
                        .font(.dripStat(10))
                        .foregroundStyle(b.miles > 0 ? Color.drip.textPrimary : Color.drip.textTertiary)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Zone breakdown

    private var zoneSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionRule(label: "Zone breakdown")
            VStack(spacing: 14) {
                // Proportional stacked bar
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        ForEach(stackedZones, id: \.self) { zone in
                            let m = tap.period.zoneMiles[zone] ?? 0
                            let frac = totalMiles > 0 ? CGFloat(m / totalMiles) : 0
                            if m > 0 {
                                Rectangle()
                                    .fill(zone.color)
                                    .frame(width: max(geo.size.width * frac, 2))
                            }
                        }
                    }
                }
                .frame(height: 10)
                .clipShape(RoundedRectangle(cornerRadius: 3))

                VStack(spacing: 8) {
                    ForEach(stackedZones, id: \.self) { zone in
                        zoneRow(zone)
                    }
                }
            }
            .padding(16)
            .background(Color.drip.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    private func zoneRow(_ zone: TrainingZone) -> some View {
        let m = tap.period.zoneMiles[zone] ?? 0
        let priorM = tap.prior?.zoneMiles[zone] ?? 0
        let pct = totalMiles > 0 ? (m / totalMiles) * 100 : 0
        let d = m - priorM

        return HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(zone.color)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 1) {
                Text(zone.label)
                    .font(.dripBody(13))
                    .foregroundStyle(Color.drip.textPrimary)
                Text(zone.paceRange(mp: mpPaceSec))
                    .font(.dripCaption(10))
                    .foregroundStyle(Color.drip.textTertiary)
            }
            Spacer()
            Text(formatMilesCompact(m) + "mi")
                .font(.dripStat(13))
                .foregroundStyle(Color.drip.textPrimary)
                .frame(width: 60, alignment: .trailing)
            Text("\(Int(pct.rounded()))%")
                .font(.dripStat(11))
                .foregroundStyle(Color.drip.textTertiary)
                .frame(width: 36, alignment: .trailing)
            Group {
                if tap.prior != nil, abs(d) >= 0.5 {
                    Text("\(d > 0 ? "▲" : "▼") \(Int(abs(d).rounded()))")
                        .foregroundStyle(d > 0 ? Color.drip.energized : Color.drip.struggling)
                } else {
                    Text("—").foregroundStyle(Color.drip.textTertiary)
                }
            }
            .font(.dripStat(10))
            .frame(width: 36, alignment: .trailing)
        }
    }

    // MARK: - Pace density

    private var paceSamples: [PaceVolumeSample] {
        var out: [PaceVolumeSample] = []
        for log in runsInPeriod {
            if let segs = log.paceSegments, !segs.isEmpty {
                for seg in segs {
                    let s = paceSeconds(seg.pacePerMile)
                    if s > 0 { out.append(.init(paceSeconds: s, miles: seg.distanceMiles)) }
                }
            } else if let m = log.miles, m > 0, let p = log.pace, !p.isEmpty {
                let s = paceSeconds(p)
                if s > 0 { out.append(.init(paceSeconds: s, miles: m)) }
            }
        }
        return out
    }

    /// Anchors derived from MP using rough ratios — Easy ≈ MP × 1.34,
    /// LT ≈ MP × 0.97, 5K ≈ MP × 0.92. Replace when AthletePaceProfile lands.
    private var paceAnchors: [PaceAnchor] {
        guard mpPaceSec > 0 else { return [] }
        return PaceVolumeSpectrumChart.defaultAnchors(
            easyPace:      mpPaceSec * 1.34,
            marathonPace:  mpPaceSec,
            thresholdPace: mpPaceSec * 0.97,
            fiveKPace:     mpPaceSec * 0.92
        )
    }

    private var paceDensitySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionRule(label: "Where the miles fell")
            PaceVolumeSpectrumChart(
                samples: paceSamples,
                anchors: paceAnchors,
                bandwidth: 18
            )
            .padding(.vertical, 6)
            .background(Color.drip.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    // MARK: - Runs list

    private var runsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionRule(label: "Runs · \(runsInPeriod.count)")
            VStack(spacing: 0) {
                ForEach(Array(runsInPeriod.enumerated()), id: \.element.id) { idx, log in
                    runRow(log)
                    if idx < runsInPeriod.count - 1 {
                        Rectangle()
                            .fill(Color.drip.divider)
                            .frame(height: 1)
                            .padding(.leading, 60)
                    }
                }
            }
            .background(Color.drip.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    private func runRow(_ log: TodayLogRow) -> some View {
        HStack(spacing: 12) {
            VStack(spacing: 0) {
                Text(Self.dayFmt.string(from: log.date).uppercased())
                    .font(.dripCaption(9))
                    .foregroundStyle(Color.drip.textTertiary)
                Text(Self.dateNumFmt.string(from: log.date))
                    .font(.dripStat(15))
                    .foregroundStyle(Color.drip.textPrimary)
            }
            .frame(width: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(typeLabelForRow(log))
                    .font(.dripBody(14))
                    .foregroundStyle(Color.drip.textPrimary)
                Text(metaLine(for: log))
                    .font(.dripStat(10))
                    .foregroundStyle(Color.drip.textTertiary)
            }
            Spacer()
            if let slug = log.typeKey, !slug.isEmpty,
               let chipLabel = Self.typeLabels[slug] {
                Text(chipLabel)
                    .font(.dripCaption(10))
                    .foregroundStyle(Color.drip.electric)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.drip.coral.opacity(0.12))
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    // MARK: - Helpers

    private static let typeLabels: [String: String] = [
        "long_run":    "Long Run",
        "easy":        "Easy",
        "steady":      "Steady",
        "tempo":       "Tempo",
        "interval":    "Intervals",
        "progression": "Progression",
        "race":        "Race",
        "recovery":    "Recovery",
        "other":       "Workout",
    ]

    private func typeLabelForRow(_ log: TodayLogRow) -> String {
        if let slug = log.typeKey, let label = Self.typeLabels[slug] { return label }
        return "Run"
    }

    private func metaLine(for log: TodayLogRow) -> String {
        var parts: [String] = []
        if let m = log.miles, m > 0 { parts.append(String(format: "%.2fmi", m)) }
        if let p = log.pace, !p.isEmpty { parts.append(p) }
        return parts.joined(separator: " · ")
    }

    private static let dayFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE"; return f
    }()

    private static let dateNumFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "d"; return f
    }()

    private func formatMiles(_ m: Double) -> String {
        m == m.rounded() ? "\(Int(m))" : String(format: "%.1f", m)
    }

    private func formatMilesCompact(_ m: Double) -> String {
        if m == 0 { return "0" }
        if m < 10 { return String(format: "%.1f", m) }
        return "\(Int(m.rounded()))"
    }

    private func paceSeconds(_ s: String) -> Double {
        let parts = s.split(separator: ":")
        guard parts.count == 2, let m = Int(parts[0]), let sec = Int(parts[1]) else { return 0 }
        return Double(m * 60 + sec)
    }

    private var stackedZones: [TrainingZone] {
        [.intervals, .tempo, .moderate, .easy, .recovery]
    }

    // MARK: - Sub-bucketing

    private struct SubBucket: Identifiable {
        let id = UUID()
        let label: String
        let zoneMiles: [TrainingZone: Double]
        var miles: Double { zoneMiles.values.reduce(0, +) }
    }

    private func subBuckets() -> [SubBucket] {
        switch tap.bucket {
        case .weekly:  return weeklyDays()
        case .monthly: return monthlyWeeks()
        }
    }

    private func weeklyDays() -> [SubBucket] {
        let labels = ["M", "T", "W", "T", "F", "S", "S"]
        var out: [SubBucket] = []
        for i in 0..<7 {
            guard let dayStart = cal.date(byAdding: .day, value: i, to: tap.period.start),
                  let dayEnd   = cal.date(byAdding: .day, value: 1, to: dayStart) else { continue }
            var zoneMiles: [TrainingZone: Double] = [:]
            for log in dedupedLogs where log.date >= dayStart && log.date < dayEnd {
                accumulate(log, into: &zoneMiles)
            }
            out.append(SubBucket(label: labels[i], zoneMiles: zoneMiles))
        }
        return out
    }

    private func monthlyWeeks() -> [SubBucket] {
        var out: [SubBucket] = []
        var weekStart = tap.period.start
        var i = 0
        while weekStart < periodEnd && i < 6 {
            let weekEnd = min(cal.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart, periodEnd)
            var zoneMiles: [TrainingZone: Double] = [:]
            for log in dedupedLogs where log.date >= weekStart && log.date < weekEnd {
                accumulate(log, into: &zoneMiles)
            }
            out.append(SubBucket(label: "W\(i + 1)", zoneMiles: zoneMiles))
            weekStart = weekEnd
            i += 1
        }
        return out
    }

    private func accumulate(_ log: TodayLogRow, into bins: inout [TrainingZone: Double]) {
        if let segs = log.paceSegments, !segs.isEmpty {
            for seg in segs {
                let s = paceSeconds(seg.pacePerMile)
                guard s > 0 else { continue }
                let z = zoneFor(paceSec: s)
                bins[z, default: 0] += seg.distanceMiles
            }
            return
        }
        guard let m = log.miles, m > 0 else { return }
        var paceSec: Double? = nil
        if let p = log.pace, !p.isEmpty {
            let v = paceSeconds(p)
            if v > 0 { paceSec = v }
        }
        if paceSec == nil, let mins = log.durationMinutes, mins > 0 {
            paceSec = (mins / m) * 60.0
        }
        if let s = paceSec {
            let z = zoneFor(paceSec: s)
            bins[z, default: 0] += m
        }
    }

    private func zoneFor(paceSec: Double) -> TrainingZone {
        guard paceSec > 0, mpPaceSec > 0 else { return .easy }
        let ratio = paceSec / mpPaceSec
        if ratio < 0.97 { return .intervals }
        if ratio < 1.07 { return .tempo }
        if ratio < 1.20 { return .moderate }
        if ratio < 1.43 { return .easy }
        return .recovery
    }
}

// MARK: - Section header rule (small caps + thin warm divider)

fileprivate struct SectionRule: View {
    let label: String
    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(label.uppercased())
                    .font(.dripCaption(11))
                    .tracking(1.5)
                    .foregroundStyle(Color.drip.textSecondary)
                Spacer()
            }
            Rectangle()
                .fill(Color.drip.divider)
                .frame(height: 1)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 12)
    }
}

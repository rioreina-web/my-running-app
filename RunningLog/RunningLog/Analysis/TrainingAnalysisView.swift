//
//  TrainingAnalysisView.swift
//  RunningLog
//
//  The deep load-and-intensity audit. Reached from the Trends tab via
//  the "VIEW DETAIL ↗" link on the FITNESS · 12-WEEK PROGRESSION
//  section. Lives under Analysis/ rather than Training/ so future
//  Train-tab redesigns can't accidentally retire it again.
//
//  This view is reconstructed from the original `TrainingTabView.swift`
//  that lived on disk before the May 2026 Train redesign (Plate 6/7
//  hybrid · WEEK/BLOCK segmenter). That redesign moved today's session
//  + week strip + weekly mileage to the front of Train, and pushed
//  this analytical layer to a destination one tab over — per the
//  redesign handoff: *"move to a dedicated Analysis screen, behind
//  Trends → ACWR ↗ or similar."*
//
//  Section order:
//    1. Header           — eyebrow + title + fitness-snapshot source
//    2. Pace zones       — all 10 zones with tolerance bands
//                          (positive aerobic / coral race-pace /
//                          injured short-fast)
//    3. Training load    — ACWR number + verdict + linear gauge
//    4. Daily intensity  — 28-day calendar heatmap, tap to expand
//    5. Weekly load      — past three weeks vs. this week as bars,
//                          tap to expand
//    6. Pace analysis    — the TrainingPaceAnalysisSection chart
//                          (existing component, unchanged)
//    7. Load split       — Quality / Easy / Rest counts + ratio bar
//
//  Data sources:
//    - EquivalentPaces (computed from active goal time + race distance)
//    - athlete_state (acwr, rolling miles, weekly avg)
//    - training_logs (last 400 days for pace analysis; 28-day window
//      for the heatmap + weekly load + split)
//

import os
import Supabase
import SwiftUI

struct TrainingAnalysisView: View {
    @State private var equivalentPaces: EquivalentPaces?
    @State private var athleteState: TrainingAnalysisState?
    @State private var logs: [TodayLogRow] = []
    @State private var loaded = false
    @State private var trainingPlanVM = TrainingPlanViewModel()
    @State private var paceZonesExpanded = false

    /// Plate 26 — currently-expanded calendar cell. When non-nil, the
    /// daily-intensity grid renders an AMBER ring around the cell with
    /// this date and shows a `TrainingDayExpanded` panel below the grid.
    /// Nil means "nothing expanded; legend follows directly."
    @State private var selectedCalendarDate: Date?

    /// Plate 27 — currently-expanded weekly load bar. The four bars map
    /// to indices 0…3 (oldest → newest). When non-nil, that bar fills
    /// AMBER and `TrainingWeekExpanded` slides in below the bar list.
    @State private var selectedWeekIndex: Int?

    private let cal = Calendar.current

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PlateStrip(surface: "ANALYSIS  ·  LOAD & INTENSITY", fig: "FIG. 7")
                header
                EditorialRule()
                paceZonesSection
                EditorialRule()
                trainingLoadSection
                EditorialRule()
                dailyIntensitySection
                EditorialRule()
                weeklyLoadSection
                EditorialRule()
                TrainingPaceAnalysisSection(
                    logs: logs,
                    mpPaceSec: equivalentPaces?.mpPace
                )
                EditorialRule()
                loadSplitSection
                EditorialRule()
                PlateFooter("Pace zones MP-anchored. ACWR is the safety rail, not the goal.")
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
        .background(Color.drip.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadAll() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("TRAINING")
                .font(.dripEyebrow(11))
                .tracking(1.3)  // 0.12em label tracking at 11pt
                .foregroundStyle(Color.drip.textTertiary)
            Text("Where you actually run.")
                .font(.dripDisplay(26))
                .foregroundStyle(Color.drip.textPrimary)
            Text(headerSub)
                .font(.dripBody(13))
                .foregroundStyle(Color.drip.textSecondary)
                .padding(.top, 2)
        }
    }

    private var headerSub: String {
        guard let p = equivalentPaces else {
            return "From your most recent fitness snapshot."
        }
        let timeStr = formatHms(p.goalTimeSeconds)
        return "From your most recent fitness snapshot · \(timeStr) \(p.goalRaceDistance.displayName.lowercased())"
    }

    // MARK: - Pace zones

    private var paceZonesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    paceZonesExpanded.toggle()
                }
            } label: {
                HStack {
                    sectionLabel("PACE ZONES")
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.drip.textTertiary)
                        .rotationEffect(.degrees(paceZonesExpanded ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if paceZonesExpanded {
                if let p = equivalentPaces {
                    // Canonical 10-zone spectrum, MP-anchored:
                    //   Range zones (% of MP speed): recovery, easy, moderate, steady
                    //   Exact paces:                 MP, HMP, 10K, 5K, 3K, mile
                    // Bands derived directly from MP via the same multipliers
                    // as the backend engine (pace-engine.ts). Source of truth.
                    let mp = p.mpPace
                    let recoveryBand: (low: Double, high: Double) = (low: mp * 1.4286, high: mp * 1.6667)
                    let easyBand:     (low: Double, high: Double) = (low: mp * 1.25,   high: mp * 1.4286)
                    let moderateBand: (low: Double, high: Double) = (low: mp * 1.1111, high: mp * 1.25)
                    let steadyBand:   (low: Double, high: Double) = (low: mp * 1.0,    high: mp * 1.1111)

                    let allPaces: [Double] = [
                        recoveryBand.high, recoveryBand.low,
                        easyBand.high,     easyBand.low,
                        moderateBand.high, moderateBand.low,
                        steadyBand.high,   steadyBand.low,
                        p.mpPace, p.hmPace, p.tenKPace, p.fiveKPace, p.threeKPace, p.milePace,
                    ]
                    let scale = paceScale(values: allPaces)

                    VStack(spacing: 0) {
                        zoneRow(name: "Recovery", band: recoveryBand,                       family: .aerobic, scale: scale)
                        zoneRow(name: "Easy",     band: easyBand,                           family: .aerobic, scale: scale)
                        zoneRow(name: "Moderate", band: moderateBand,                       family: .aerobic, scale: scale)
                        zoneRow(name: "Steady",   band: steadyBand,                         family: .aerobic, scale: scale)
                        zoneRow(name: "MP",       band: (p.mpPace,    p.mpPace),    family: .tempo, scale: scale, marker: p.mpPace)
                        zoneRow(name: "HMP",      band: (p.hmPace,    p.hmPace),    family: .tempo, scale: scale, marker: p.hmPace)
                        zoneRow(name: "10K",      band: (p.tenKPace,  p.tenKPace),  family: .fast,  scale: scale, marker: p.tenKPace)
                        zoneRow(name: "5K",       band: (p.fiveKPace, p.fiveKPace), family: .fast,  scale: scale, marker: p.fiveKPace)
                        zoneRow(name: "3K",       band: (p.threeKPace, p.threeKPace), family: .fast, scale: scale, marker: p.threeKPace)
                        zoneRow(name: "Mile",     band: (p.milePace,  p.milePace),  family: .fast,  scale: scale, marker: p.milePace)
                    }
                    .padding(.top, 4)
                } else {
                    Text("Set a goal to see your pace zones.")
                        .font(.dripBody(13))
                        .foregroundStyle(Color.drip.textTertiary)
                        .padding(.top, 8)
                }
            }
        }
    }

    private enum ZoneFamily {
        case aerobic, tempo, fast

        var nameColor: Color {
            switch self {
            case .aerobic: return Color.drip.positive
            case .tempo:   return Color.drip.coral
            case .fast:    return Color.drip.injured
            }
        }
        var fillColor: Color {
            switch self {
            case .aerobic: return Color.drip.positive.opacity(0.35)
            case .tempo:   return Color.drip.coral.opacity(0.35)
            case .fast:    return Color.drip.injured.opacity(0.30)
            }
        }
    }

    private func zoneRow(
        name: String,
        band: (low: Double, high: Double),
        family: ZoneFamily,
        scale: (min: Double, max: Double),
        marker: Double? = nil
    ) -> some View {
        HStack(spacing: 12) {
            Text(name)
                .font(.dripBody(14))
                .foregroundStyle(family.nameColor)
                .frame(width: 92, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.drip.divider.opacity(0.5))
                        .frame(height: 8)
                        .frame(maxWidth: .infinity)
                    let (lowFrac, highFrac) = bandFractions(band: band, scale: scale)
                    let width = geo.size.width
                    RoundedRectangle(cornerRadius: 4)
                        .fill(family.fillColor)
                        .frame(
                            width: max(8, width * (highFrac - lowFrac)),
                            height: 8
                        )
                        .offset(x: width * lowFrac, y: 0)
                    if let marker {
                        let frac = paceFraction(pace: marker, scale: scale)
                        Rectangle()
                            .fill(Color.drip.textPrimary)
                            .frame(width: 2, height: 12)
                            .offset(x: width * frac - 1, y: -2)
                    }
                }
                .frame(height: 12)
            }
            .frame(height: 12)

            Text(bandLabel(band))
                .font(.dripStat(13))
                .foregroundStyle(Color.drip.textPrimary)
                .frame(width: 88, alignment: .trailing)
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.drip.divider.opacity(0.4))
                .frame(height: 0.5)
        }
    }

    private func paceScale(values: [Double]) -> (min: Double, max: Double) {
        guard let lo = values.min(), let hi = values.max() else { return (0, 1) }
        // Pad a touch so endpoints don't sit at the very edge.
        let pad = (hi - lo) * 0.05
        return (lo - pad, hi + pad)
    }

    private func bandFractions(
        band: (low: Double, high: Double),
        scale: (min: Double, max: Double)
    ) -> (Double, Double) {
        let span = max(0.01, scale.max - scale.min)
        // Faster pace (lower seconds) sits to the RIGHT in the mockup —
        // mirror the values onto a "speed" axis so race-paces appear right.
        let lowFrac = 1 - (band.high - scale.min) / span
        let highFrac = 1 - (band.low - scale.min) / span
        return (max(0, lowFrac), min(1, highFrac))
    }

    private func paceFraction(pace: Double, scale: (min: Double, max: Double)) -> Double {
        let span = max(0.01, scale.max - scale.min)
        return min(1, max(0, 1 - (pace - scale.min) / span))
    }

    private func bandLabel(_ band: (low: Double, high: Double)) -> String {
        if abs(band.high - band.low) < 0.5 {
            return "\(formatPace(band.low))/mi"
        }
        return "\(formatPace(band.low))–\(formatPace(band.high))/mi"
    }

    // MARK: - Training load (ACWR)

    private var trainingLoadSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("TRAINING LOAD")
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(athleteState?.acwr.map { String(format: "%.2f", $0) } ?? "—")
                    .font(.dripDisplay(36))
                    .foregroundStyle(Color.drip.coral)
                    .monospacedDigit()
                VStack(alignment: .leading, spacing: 2) {
                    Text("ACWR")
                        .font(.dripCaption(10))
                        .tracking(1.2)
                        .foregroundStyle(Color.drip.textTertiary)
                    Text(acwrVerdict)
                        .font(.dripCaption(11))
                        .tracking(1.2)
                        .foregroundStyle(acwrVerdictColor)
                        .textCase(.uppercase)
                }
                Spacer()
            }
            acwrGauge
            HStack {
                Text("0.7").frame(maxWidth: .infinity, alignment: .leading)
                Text("1.0").frame(maxWidth: .infinity, alignment: .center)
                Text("1.3").frame(maxWidth: .infinity, alignment: .center)
                Text("1.5").frame(maxWidth: .infinity, alignment: .center)
                Text("2.0").frame(maxWidth: .infinity, alignment: .trailing)
            }
            .font(.dripStat(11))
            .foregroundStyle(Color.drip.textSecondary)
            .padding(.top, 2)
        }
    }

    private var acwrGauge: some View {
        // Linear gauge with four colored segments and a marker.
        // Segments scale 0.7 - 1.0 - 1.3 - 1.5 - 2.0.
        let acwr = athleteState?.acwr ?? 1.0
        let frac = max(0, min(1, (acwr - 0.7) / (2.0 - 0.7)))
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Segments span 0.7→1.0, 1.0→1.3, 1.3→1.5, 1.5→2.0
                // Total span 1.3 → fractions: 0.231, 0.231, 0.154, 0.384
                HStack(spacing: 0) {
                    Rectangle().fill(Color(red: 0.98, green: 0.93, blue: 0.85)).frame(width: geo.size.width * 0.231)
                    Rectangle().fill(Color(red: 0.75, green: 0.87, blue: 0.59)).frame(width: geo.size.width * 0.231)
                    Rectangle().fill(Color(red: 0.98, green: 0.78, blue: 0.46)).frame(width: geo.size.width * 0.154)
                    Rectangle().fill(Color(red: 0.94, green: 0.58, blue: 0.58)).frame(width: geo.size.width * 0.384)
                }
                .frame(height: 14)
                .clipShape(RoundedRectangle(cornerRadius: 7))

                Rectangle()
                    .fill(Color.drip.textPrimary)
                    .frame(width: 2, height: 20)
                    .offset(x: geo.size.width * frac - 1, y: -3)
            }
        }
        .frame(height: 14)
    }

    private var acwrVerdict: String {
        guard let a = athleteState?.acwr else { return "No data" }
        if a < 0.8 { return "Undertraining" }
        if a <= 1.3 { return "Safe" }
        if a <= 1.5 { return "High but safe" }
        return "Spike risk"
    }

    private var acwrVerdictColor: Color {
        guard let a = athleteState?.acwr else { return Color.drip.textTertiary }
        if a < 0.8 { return Color.drip.tired }
        if a <= 1.3 { return Color.drip.positive }
        if a <= 1.5 { return Color(red: 0.73, green: 0.46, blue: 0.09) }
        return Color.drip.injured
    }

    // MARK: - Daily intensity (28-day calendar)

    private var dailyIntensitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                sectionLabel("DAILY INTENSITY")
                Spacer()
                Text(windowLabel)
                    .font(.dripStat(11))
                    .foregroundStyle(Color.drip.textTertiary)
            }
            calendarGrid

            // Plate 26 — inline expansion. Slides in below the grid when
            // a day is selected. For empty days (no run logged) we hide
            // the panel entirely; tapping the same day a second time also
            // hides it (toggle behavior in `calendarCell`).
            if let date = selectedCalendarDate {
                let dayLogs = logs.filter { cal.isDate($0.date, inSameDayAs: date) }
                if !dayLogs.isEmpty {
                    TrainingDayExpanded(
                        day: date,
                        dayLogs: dayLogs,
                        windowLogs: logs,
                        mpPaceSec: equivalentPaces?.mpPace,
                        onCollapse: {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                                selectedCalendarDate = nil
                            }
                        }
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            calendarLegend
                .padding(.top, 4)
        }
    }

    private var calendarGrid: some View {
        let cells = computeCalendarCells()
        let weeks = cells.chunked(into: 7)
        let labelColWidth: CGFloat = 52

        return VStack(spacing: 4) {
            HStack(spacing: 4) {
                Text("").frame(width: labelColWidth)
                ForEach(["M", "T", "W", "Th", "F", "Sa", "Su"], id: \.self) { d in
                    Text(d)
                        .font(.dripCaption(9))
                        .tracking(0.8)
                        .foregroundStyle(Color.drip.textTertiary)
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(Array(weeks.enumerated()), id: \.offset) { idx, weekRow in
                HStack(spacing: 4) {
                    Text(weekLabel(forIndex: idx))
                        .font(.dripStat(11))
                        .foregroundStyle(idx == 3 ? Color.drip.coral : Color.drip.textSecondary)
                        .frame(width: labelColWidth, alignment: .trailing)
                        .padding(.trailing, 4)
                    ForEach(Array(weekRow.enumerated()), id: \.offset) { _, cell in
                        calendarCell(cell)
                    }
                }
            }
        }
    }

    private func calendarCell(_ cell: CalendarCell) -> some View {
        let bg: Color = cell.kind.color
        let fg: Color = cell.kind == .rest ? Color.drip.textTertiary : Color.drip.textPrimary
        let isSelected = selectedCalendarDate.map {
            cal.isDate($0, inSameDayAs: cell.date)
        } ?? false
        // Empty cells (no run) shouldn't be tappable — there's nothing to
        // show in the expansion. They render as static rest cells.
        let canExpand = cell.miles > 0
        let dayNum = cal.component(.day, from: cell.date)
        let isFuture = cal.startOfDay(for: cell.date) > cal.startOfDay(for: Date())
        let cornerColor: Color = cell.kind == .rest
            ? Color.drip.textTertiary.opacity(0.55)
            : Color.drip.textPrimary.opacity(0.45)
        return Button {
            guard canExpand else { return }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                if isSelected {
                    selectedCalendarDate = nil   // tap again to collapse
                } else {
                    selectedCalendarDate = cell.date
                }
            }
        } label: {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(bg)
                    .overlay(
                        cell.isToday
                            ? RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.drip.textPrimary, lineWidth: 1.5)
                            : nil
                    )
                    // CORAL ring on the selected cell — sits above any
                    // "today" outline so the selection is unambiguous.
                    .overlay(
                        isSelected
                            ? RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.drip.coral, lineWidth: 2.5)
                                .padding(-1)
                            : nil
                    )

                if cell.isToday && cell.miles <= 0 {
                    // Today, no run yet: anchor the cell with a prominent
                    // centered day number. The outline + centered date is
                    // the today indicator; the corner number is skipped to
                    // avoid duplicating the same digits.
                    Text("\(dayNum)")
                        .font(.dripStat(15))
                        .foregroundStyle(Color.drip.textPrimary)
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // Corner day-of-month — always shown so every cell is
                    // self-identifying without tapping.
                    Text("\(dayNum)")
                        .font(.dripStat(9))
                        .foregroundStyle(cornerColor)
                        .monospacedDigit()
                        .padding(.leading, 5)
                        .padding(.top, 4)

                    if cell.miles > 0 {
                        Text(String(format: "%.1f", cell.miles))
                            .font(.dripStat(13))
                            .foregroundStyle(fg)
                            .monospacedDigit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if !isFuture {
                        Text("·")
                            .font(.dripCaption(12))
                            .foregroundStyle(Color.drip.textTertiary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    // Future cells: corner date only, no center glyph.
                }
            }
            .frame(height: 48)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(!canExpand)
    }

    private var calendarLegend: some View {
        HStack(spacing: 12) {
            legendItem(label: "Easy",      color: Color(red: 0.62, green: 0.88, blue: 0.80))
            legendItem(label: "Long",      color: Color(red: 0.36, green: 0.79, blue: 0.65))
            legendItem(label: "Tempo",     color: Color(red: 0.96, green: 0.77, blue: 0.70))
            legendItem(label: "Intervals", color: Color(red: 0.94, green: 0.60, blue: 0.48))
            legendItem(label: "Rest",      color: .clear, bordered: true)
            Spacer(minLength: 0)
        }
    }

    private func legendItem(label: String, color: Color, bordered: Bool = false) -> some View {
        HStack(spacing: 4) {
            Group {
                if bordered {
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(Color.drip.divider, lineWidth: 0.5)
                } else {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                }
            }
            .frame(width: 10, height: 10)
            Text(label)
                .font(.dripCaption(10))
                .foregroundStyle(Color.drip.textSecondary)
        }
    }

    // MARK: - Weekly load

    private var weeklyLoadSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionLabel("WEEKLY LOAD")
                Spacer()
                Text("TAP A WEEK")
                    .font(.dripCaption(9))
                    .tracking(0.8)
                    .foregroundStyle(Color.drip.textTertiary)
            }

            let weeks = computeWeeklyTotals()
            let max = weeks.map(\.miles).max() ?? 1
            let labels = ["Wk-3", "Wk-2", "Wk-1", "This"]
            VStack(spacing: 6) {
                ForEach(Array(weeks.enumerated()), id: \.offset) { idx, week in
                    Button {
                        // Only weeks with logged miles open the expansion;
                        // empty weeks are tap-noops to avoid blank panels.
                        guard week.miles > 0 else { return }
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                            if selectedWeekIndex == idx {
                                selectedWeekIndex = nil
                            } else {
                                selectedWeekIndex = idx
                            }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Text(labels[safe: idx] ?? "")
                                .font(.dripCaption(9))
                                .tracking(0.8)
                                .foregroundStyle(
                                    selectedWeekIndex == idx
                                        ? Color.drip.coral
                                        : Color.drip.textTertiary
                                )
                                .frame(width: 36, alignment: .leading)
                            weekBar(
                                miles: week.miles,
                                max: max,
                                isCurrent: idx == weeks.count - 1,
                                isSelected: selectedWeekIndex == idx
                            )
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(week.miles <= 0)
                }
            }

            // Plate 27 — inline expansion below the bars when a week is
            // selected. Pulls logs for that week from `logs` (already
            // loaded for the 28-day grid).
            if let idx = selectedWeekIndex,
               let weekStart = startOfWeek(forIndex: idx) {
                let weekEnd = cal.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
                let weekLogs = logs.filter { $0.date >= weekStart && $0.date < weekEnd }
                TrainingWeekExpanded(
                    weekStart: weekStart,
                    weekLogs: weekLogs,
                    weekIndex: idx,
                    onCollapse: {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                            selectedWeekIndex = nil
                        }
                    }
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func weekBar(miles: Double, max: Double,
                         isCurrent: Bool, isSelected: Bool) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.drip.divider.opacity(0.5))
                let frac = max > 0 ? CGFloat(miles / max) : 0
                RoundedRectangle(cornerRadius: 4)
                    .fill(
                        isSelected
                            ? Color.drip.coral
                            : (isCurrent
                               ? Color.drip.coral.opacity(0.9)
                               : Color.drip.coral.opacity(0.45))
                    )
                    .frame(width: geo.size.width * frac)
                Text("\(Int(miles)) mi")
                    .font(.dripStat(11))
                    .foregroundStyle(Color.drip.textPrimary)
                    .padding(.leading, 8)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 8)
            }
        }
        .frame(height: 18)
    }

    /// Maps a weekly-bar index (0…3, oldest → newest) back to the
    /// Monday-anchored start date of that week. Mirrors the math used by
    /// `computeCalendarCells()` so the dates line up exactly.
    private func startOfWeek(forIndex idx: Int) -> Date? {
        let today = Date()
        let weekday = cal.component(.weekday, from: today)
        let daysBackToMonday = (weekday + 5) % 7
        guard let thisMonday = cal.date(byAdding: .day, value: -daysBackToMonday, to: today)
        else { return nil }
        // idx 0 = oldest (3 weeks back), idx 3 = this week.
        let weeksBack = 3 - idx
        return cal.date(byAdding: .day, value: -weeksBack * 7,
                        to: cal.startOfDay(for: thisMonday))
    }

    // MARK: - Load split

    private var loadSplitSection: some View {
        let split = computeSplit()
        let total = max(1, split.quality + split.easy + split.rest)
        let qPct = Double(split.quality) / Double(total)
        let ePct = Double(split.easy)    / Double(total)
        let rPct = Double(split.rest)    / Double(total)

        return VStack(alignment: .leading, spacing: 10) {
            sectionLabel("LOAD SPLIT · 28 DAYS")
            HStack(alignment: .top, spacing: 16) {
                splitCol(num: "\(split.quality)", label: "Quality", detail: "tempo, intervals, long", accent: true)
                splitCol(num: "\(split.easy)",    label: "Easy",    detail: "aerobic + recovery",   accent: false)
                splitCol(num: "\(split.rest)",    label: "Rest",    detail: "no run logged",        accent: false)
                Spacer(minLength: 0)
            }
            GeometryReader { geo in
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.drip.coral)
                        .frame(width: geo.size.width * CGFloat(qPct))
                    Rectangle()
                        .fill(Color.drip.positive)
                        .frame(width: geo.size.width * CGFloat(ePct))
                    Rectangle()
                        .fill(Color.drip.divider)
                        .frame(width: geo.size.width * CGFloat(rPct))
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .frame(height: 8)
            HStack {
                Text("\(Int((qPct * 100).rounded()))% quality")
                    .foregroundStyle(Color.drip.coral)
                Spacer()
                Text("\(Int((ePct * 100).rounded()))% easy")
                    .foregroundStyle(Color.drip.positive)
                Spacer()
                Text("\(Int((rPct * 100).rounded()))% rest")
                    .foregroundStyle(Color.drip.textSecondary)
            }
            .font(.dripCaption(11))
        }
    }

    private func splitCol(num: String, label: String, detail: String, accent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(num)
                .font(.dripDisplay(22))
                .foregroundStyle(accent ? Color.drip.coral : Color.drip.textPrimary)
                .monospacedDigit()
            Text(label.uppercased())
                .font(.dripCaption(10))
                .tracking(0.5)
                .foregroundStyle(Color.drip.textTertiary)
            Text(detail)
                .font(.dripCaption(11))
                .foregroundStyle(Color.drip.textSecondary)
                .lineLimit(1)
        }
    }

    // MARK: - Reusable

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.dripCaption(11))
            .tracking(1.5)
            .foregroundStyle(Color.drip.textTertiary)
    }

    // MARK: - Calendar / weekly / split data

    private struct CalendarCell {
        enum Kind {
            case rest, recovery, easy, long, tempo, intervals
            var color: Color {
                switch self {
                case .rest:      return Color.clear
                case .recovery:  return Color(red: 0.88, green: 0.96, blue: 0.93)
                case .easy:      return Color(red: 0.62, green: 0.88, blue: 0.80)
                case .long:      return Color(red: 0.36, green: 0.79, blue: 0.65)
                case .tempo:     return Color(red: 0.96, green: 0.77, blue: 0.70)
                case .intervals: return Color(red: 0.94, green: 0.60, blue: 0.48)
                }
            }
        }
        let date: Date
        let kind: Kind
        let miles: Double
        let isToday: Bool
    }

    private func computeCalendarCells() -> [CalendarCell] {
        let today = Date()
        let weekday = cal.component(.weekday, from: today)
        let daysBackToMonday = (weekday + 5) % 7
        guard let thisMonday = cal.date(byAdding: .day, value: -daysBackToMonday, to: today) else {
            return []
        }
        let start = cal.date(byAdding: .day, value: -21, to: cal.startOfDay(for: thisMonday)) ?? today
        var out: [CalendarCell] = []
        for i in 0..<28 {
            guard let day = cal.date(byAdding: .day, value: i, to: start) else { continue }
            let dayLogs = logs.filter { cal.isDate($0.date, inSameDayAs: day) }
            let miles = summedMiles(for: dayLogs)
            let kind = pickKind(logs: dayLogs, miles: miles)
            out.append(CalendarCell(
                date: day,
                kind: kind,
                miles: miles,
                isToday: cal.isDate(day, inSameDayAs: today)
            ))
        }
        return out
    }

    /// Cell-mile sum delegated to the shared physical-workout dedup
    /// (LogDedup.swift). Catches the full set of overlap shapes:
    /// voice_log mirroring a GPS row, strava + auto_sync writing the
    /// same workout from different importers, while still preserving
    /// genuine same-source doubles (May 5: WU + main + CD all from
    /// Strava as three distinct activities). Notes/mood from skipped
    /// voice_log rows still surface in TrainingDayExpanded.
    private func summedMiles(for dayLogs: [TodayLogRow]) -> Double {
        return dayLogs.dedupedByPhysicalWorkout()
            .compactMap { $0.miles }
            .reduce(0, +)
    }

    private func pickKind(logs: [TodayLogRow], miles: Double) -> CalendarCell.Kind {
        if logs.isEmpty || miles <= 0 { return .rest }
        let types = logs.compactMap { $0.typeKey?.lowercased() }

        // Long-run trumps other signals by volume. Plan-side classifier
        // flags long_run explicitly; distance threshold catches unplanned
        // long days that weren't tagged.
        if types.contains("long_run") || miles >= 12 { return .long }

        // Trust explicit interval workouts. Average pace masks the hard
        // intervals in a workout like 3mi easy + 4×800m + 1mi cool, so
        // we can't catch intervals reliably via avg-pace ratio. The
        // segment-based classifier handles these at write time.
        if types.contains("interval") || types.contains("intervals") {
            return .intervals
        }

        // Pace-relative classification. The historic absolute-pace
        // thresholds in WorkoutSyncService.classifyWorkout (sub-7:00 →
        // interval, sub-8:00 → tempo) miscall fast athletes' easy days
        // as hard days — e.g. a 6:30/mi easy run for a 5:30 MP runner
        // gets stored as "tempo". Reclassifying at read time using the
        // same MP multipliers as the pace-zone engine restores the
        // calibration without needing to backfill the DB.
        if let mp = equivalentPaces?.mpPace, mp > 0,
           let avgPaceSec = avgPaceSeconds(for: logs) {
            let ratio = avgPaceSec / mp
            if ratio < 0.97 { return .intervals }   // faster than HMP
            if ratio < 1.07 { return .tempo }       // steady → MP → HMP
            if ratio < 1.43 { return .easy }        // easy / moderate
            return .recovery
        }

        // Last-resort fallback to stored type — only fires when MP
        // hasn't loaded yet or the row has no pace/duration data.
        if types.contains("tempo") || types.contains("threshold") || types.contains("progression") {
            return .tempo
        }
        if types.contains("recovery") { return .recovery }
        return .easy
    }

    private func avgPaceSeconds(for logs: [TodayLogRow]) -> Double? {
        let totalMiles = logs.compactMap { $0.miles }.reduce(0, +)
        let totalMinutes = logs.compactMap { $0.durationMinutes }.reduce(0, +)
        if totalMiles > 0, totalMinutes > 0 {
            return (totalMinutes / totalMiles) * 60.0
        }
        for log in logs {
            if let p = log.pace, let secs = parsePaceSeconds(p) { return secs }
        }
        return nil
    }

    private func parsePaceSeconds(_ s: String) -> Double? {
        let parts = s.split(separator: ":")
        guard parts.count == 2,
              let mins = Int(parts[0]),
              let secs = Int(parts[1]) else { return nil }
        return Double(mins * 60 + secs)
    }

    private struct WeekTotal { let miles: Double }

    private func computeWeeklyTotals() -> [WeekTotal] {
        let cells = computeCalendarCells()
        let weeks = cells.chunked(into: 7)
        return weeks.map { WeekTotal(miles: $0.reduce(0) { $0 + $1.miles }) }
    }

    private struct LoadSplit {
        let quality: Int
        let easy: Int
        let rest: Int
    }

    private func computeSplit() -> LoadSplit {
        let cells = computeCalendarCells()
        var q = 0, e = 0, r = 0
        for c in cells {
            switch c.kind {
            case .tempo, .intervals, .long: q += 1
            case .easy, .recovery:           e += 1
            case .rest:                      r += 1
            }
        }
        return LoadSplit(quality: q, easy: e, rest: r)
    }

    // MARK: - Loading

    private func loadAll() async {
        // 400-day window so TrainingPaceAnalysisSection has the
        // history it needs (12-month range with comparison = ~24 months).
        // Calendar grid still filters to the visible 28-day window.
        async let logsTask = TodayLogRow.fetchRecent(days: 400)
        async let stateTask = TrainingAnalysisState.fetch()

        // The plan service owns equivalentPaces — same source the rest of
        // the Training surface uses (DayDetailSheet, GoalAndPacesCard).
        await trainingPlanVM.loadActivePlan()
        let paces = await MainActor.run { trainingPlanVM.service.equivalentPaces }

        let (fetchedLogs, state) = await (logsTask, stateTask)

        await MainActor.run {
            self.logs = fetchedLogs
            self.athleteState = state
            self.equivalentPaces = paces
            self.loaded = true
        }
    }

    // MARK: - Formatters

    private func formatPace(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func formatHms(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    // Daily-intensity date labels. `weekLabel` anchors each row by its
    // Monday ("Apr 20"); the full 28-day window appears in the section
    // header right ("Apr 20 — May 17"). Together with the day-of-month
    // corner in each cell, every date is identifiable without a tap.
    private func weekLabel(forIndex idx: Int) -> String {
        guard let start = startOfWeek(forIndex: idx) else { return "" }
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: start)
    }

    private var windowLabel: String {
        guard let firstStart = startOfWeek(forIndex: 0),
              let lastStart = startOfWeek(forIndex: 3),
              let lastEnd = cal.date(byAdding: .day, value: 6, to: lastStart)
        else { return "" }
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return "\(f.string(from: firstStart)) — \(f.string(from: lastEnd))"
    }
}

// MARK: - athlete_state slim row

/// Slim projection of `athlete_state` for the ACWR gauge. Renamed from
/// the original `TrainingTabState` to avoid colliding with any future
/// re-introduction of the same name elsewhere; `TrendsAthleteState`
/// (in `TrendsTabView.swift`) is a sibling that pulls the same row for
/// a different surface.
struct TrainingAnalysisState: Decodable {
    let acwr: Double?
    let rolling_7d_miles: Double?
    let rolling_28d_miles: Double?

    static func fetch() async -> TrainingAnalysisState? {
        do {
            let rows: [TrainingAnalysisState] = try await supabase
                .from("athlete_state")
                .select("acwr, rolling_7d_miles, rolling_28d_miles")
                .limit(1)
                .execute()
                .value
            return rows.first
        } catch {
            Log.coach.error("TrainingAnalysisState fetch failed: \(error)")
            return nil
        }
    }
}

// MARK: - Helpers

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}

//
//  GoalPaceGridCard.swift
//  RunningLog · Trends
//
//  "Is my training converging on the pace I intend to race?"
//
//  A GRID, NOT A SCATTER OR A SET OF LANES. Three earlier attempts at this
//  surface failed for related reasons: pace-only dots couldn't place a
//  multi-pace workout, lanes lost the calendar dimension, and both collapsed
//  under six months of density. This is calendar across (Monday-anchored
//  DAYS across, pace-relative-to-goal down (server-computed rows — see
//  GoalPaceGridDTO's file header for why bucketing never happens on this
//  side). TWO ENCODINGS, TWO CHANNELS, never merged:
//    • WHICH PACE — the row, keyed by its `PaceSpectrum` swatch in the
//      gutter. That ramp means fast→slow here exactly as it does everywhere
//      else in the product; it is never repurposed.
//    • HOW MANY MILES — the cell fill, neutral ink, light to dark.
//
//  Three retired encodings, all 2026-09-01, all for failing to show a
//  distribution or for lying about what colour means:
//    • AREA (a small square floating in an empty cell) read as scattered
//      specks; the eye compares small areas poorly and the whitespace hid
//      the shape of the training.
//    • HUE=pace + OPACITY=miles fought each other: a pale Easy row holding
//      20 miles looked identical to a navy Mile row holding 2.
//    • PaceSpectrum driven by MILES — read well, but hijacked the product's
//      "colour == pace" ramp to mean volume, which would have taught navy =
//      "lots of miles" here and navy = "mile pace" everywhere else.
//
//  The actual grid drawing lives in GoalPaceGridPlot.swift, shared with
//  GoalPaceGridDetailView at a larger size — one renderer, so the glance and
//  the expanded view can never disagree about the same sessions.
//
//  Opens scrolled to today, not the race — the empty weeks between today and
//  race day are real information (the runway), not something to default into.
//

import SwiftUI

struct GoalPaceGridCard: View {
    let data: GoalPaceGridData

    @State private var filter: GoalPaceGridFilter = .all
    @State private var heatAdjusted = false
    @State private var selected: GoalPaceGridDeposit?
    @State private var showDetail = false

    init(data: GoalPaceGridData) {
        self.data = data
    }

    private var hasHeatData: Bool {
        data.deposits.contains { $0.paceSecHeatAdj != $0.paceSec }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            filterChips
            GoalPaceGridPlot(data: data, filter: filter, heatAdjusted: heatAdjusted, selected: $selected)
            readout
            legend
            footnote
        }
        .padding(.vertical, 4)
        .fullScreenCover(isPresented: $showDetail) {
            // Reverted from GoalPaceConvergenceView (2026-09-01): that scatter
            // renderer was a real design detour, but a calendar × pace-band
            // grid with area = miles already IS the density heatmap the
            // athlete asked for, once the server stops excluding non-quality
            // sessions (goalPaceGrid.ts, same date) — no third renderer
            // needed. Card and detail share GoalPaceGridPlot again, so they
            // can never disagree about the same sessions.
            GoalPaceGridDetailView(data: data, filter: $filter, heatAdjusted: $heatAdjusted)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(paceString(Int(data.goal.paceSecPerMile.rounded())))
                    .font(.dripDisplay(28))
                    .foregroundStyle(Color.drip.textPrimary)
                Text("/MI IS GOAL PACE")
                    .font(.dripEyebrow(10))
                    .tracking(0.9)
                    .foregroundStyle(Color.drip.textTertiary)
                Spacer()
                if hasHeatData { heatToggle }
                expandButton
            }
            Text(summaryLine)
                .font(.dripBody(12.5))
                .foregroundStyle(Color.drip.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var heatToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) { heatAdjusted.toggle() }
        } label: {
            Text("HEAT-ADJUSTED")
                .font(.dripEyebrow(9))
                .tracking(1.0)
                .foregroundStyle(heatAdjusted ? Color.drip.background : Color.drip.textTertiary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(heatAdjusted ? Color.drip.textPrimary : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(heatAdjusted ? Color.clear : Color.drip.divider, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Heat-adjusted paces")
        .accessibilityValue(heatAdjusted ? "On" : "Off")
    }

    private var expandButton: some View {
        Button { showDetail = true } label: {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.drip.textSecondary)
                .padding(6)
                .background(Circle().fill(Color.drip.paperDeep))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Expand goal pace grid")
    }

    private var summaryLine: String {
        let miles = data.miles(filter: filter)
        guard miles > 0 else { return "Nothing logged for this filter yet." }
        let near = data.deposits(for: filter)
            .filter { (heatAdjusted ? $0.pctOfGoalHeatAdj : $0.pctOfGoal) >= 95 &&
                      (heatAdjusted ? $0.pctOfGoalHeatAdj : $0.pctOfGoal) <= 105 }
            .reduce(0.0) { $0 + $1.miles }
        let pct = Int((near / miles * 100).rounded())
        return "\(Int(miles.rounded())) mi in view · \(pct)% within 5% of goal pace"
    }

    // MARK: - Filter chips

    private var filterChips: some View {
        HStack(spacing: 6) {
            ForEach(GoalPaceGridFilter.allCases) { f in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { filter = f }
                } label: {
                    Text(f.label.uppercased())
                        .font(.dripEyebrow(9))
                        .tracking(0.8)
                        .foregroundStyle(filter == f ? Color.drip.background : Color.drip.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(filter == f ? Color.drip.textPrimary : Color.drip.paperDeep)
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    // MARK: - Readout, legend, footnote

    private var readout: some View {
        Group {
            if let s = selected {
                let pct = heatAdjusted ? s.pctOfGoalHeatAdj : s.pctOfGoal
                let pace = heatAdjusted ? s.paceSecHeatAdj : s.paceSec
                let siblings = data.sessionDeposits(matching: s)
                let dayMiles = siblings.reduce(0.0) { $0 + $1.miles }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(s.date.formatted(.dateTime.day().month(.abbreviated)))
                            .font(.dripEyebrow(10))
                            .foregroundStyle(Color.drip.textSecondary)
                        Text("\(fmt(pct))%")
                            .font(.dripStat(13))
                            .foregroundStyle(Color.drip.textPrimary)
                        Text("\(paceString(pace))/mi · \(fmt(s.miles)) mi")
                            .font(.dripBody(11.5))
                            .foregroundStyle(Color.drip.textSecondary)
                        Spacer()
                    }
                    // A tapped mark is one PIECE of a day, not the whole
                    // run — a 21-mile day with a warm-up and four 3-mile reps
                    // at different paces shows as several marks. Without this
                    // line, tapping one and seeing "3 mi" reads as the chart
                    // thinking the run WAS 3 miles. No "blocks" language —
                    // that's internal segmentation, not something the athlete
                    // needs to count.
                    if siblings.count > 1 {
                        Text("part of a \(fmt(dayMiles)) mi day")
                            .font(.dripEyebrow(9))
                            .foregroundStyle(Color.drip.textTertiary)
                    }
                }
            } else if let h = data.headlineSession() {
                headlineReadout(h)
            } else {
                Text("Tap a mark")
                    .font(.dripBody(11.5))
                    .foregroundStyle(Color.drip.textTertiary)
            }
        }
        .frame(minHeight: 17, alignment: .leading)
    }

    /// The default state, before any tap: the most recent day's FULL volume,
    /// summed across every block logged for it — not the single largest or
    /// single most-recent block. A 21-mile day with a warm-up and four 3-mile
    /// reps at different paces shows as "12 mi across 4 blocks", the true
    /// captured total, never a fragment of it presented as the whole.
    // No "blocks" language, no counts — just what the day was and how it
    // sat against goal pace. Internal segmentation is implementation detail;
    // the athlete cares about the day, not how many pieces it parsed into.
    private func headlineReadout(_ h: SessionHeadline) -> some View {
        let pct = heatAdjusted ? h.dominant.pctOfGoalHeatAdj : h.dominant.pctOfGoal
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(h.date.formatted(.dateTime.day().month(.abbreviated)))
                .font(.dripEyebrow(10))
                .foregroundStyle(Color.drip.textSecondary)
            Text("\(fmt(h.totalMiles)) mi")
                .font(.dripStat(13))
                .foregroundStyle(Color.drip.textPrimary)
            Text(h.blockCount > 1 ? "mostly \(fmt(pct))% of goal pace" : "\(fmt(pct))% of goal pace")
                .font(.dripBody(11.5))
                .foregroundStyle(Color.drip.textSecondary)
            Spacer()
        }
    }

    /// TWO ramps, because there are two encodings and conflating them is what
    /// broke this chart twice. The PaceSpectrum ramp means what it means
    /// everywhere else in the product — fast to slow — and keys the ROWS. The
    /// ink ramp is density: how many miles landed in a cell.
    private var legend: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                ForEach(Array(PaceSpectrum.stops.reversed().enumerated()), id: \.offset) { _, c in
                    Rectangle().fill(c).frame(width: 10, height: 5)
                }
                Text("ROWS: FAST → SLOW")
                    .font(.dripEyebrow(8))
                    .tracking(0.6)
                    .foregroundStyle(Color.drip.textTertiary)
                    .padding(.leading, 4)
                Spacer()
            }
            HStack(spacing: 4) {
                ForEach(0..<10, id: \.self) { i in
                    Rectangle()
                        .fill(Color.drip.textPrimary.opacity(0.14 + 0.86 * Double(i) / 9))
                        .frame(width: 10, height: 5)
                }
                Text("CELLS: FEWER → MORE MILES")
                    .font(.dripEyebrow(8))
                    .tracking(0.6)
                    .foregroundStyle(Color.drip.textTertiary)
                    .padding(.leading, 4)
                Spacer()
            }
        }
    }

    private var footnote: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("TOTAL MILES · \(filter.label.uppercased())")
                .font(.dripEyebrow(9))
                .tracking(1.1)
                .foregroundStyle(Color.drip.textTertiary)
            Text("\(fmt(data.miles(filter: filter))) mi")
                .font(.dripDisplay(17))
                .foregroundStyle(Color.drip.textPrimary)
        }
    }

    // MARK: - Formatting

    private func fmt(_ d: Double) -> String {
        d == d.rounded() ? String(Int(d)) : String(format: "%.1f", d)
    }
    private func paceString(_ sec: Int) -> String {
        var m = sec / 60, s = sec % 60
        if s == 60 { m += 1; s = 0 }
        return "\(m):\(String(format: "%02d", s))"
    }
}

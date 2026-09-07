//
//  GoalPaceGridDetailView.swift
//  RunningLog · Trends
//
//  The expanded goal-pace surface — same GoalPaceGridPlot renderer as the
//  card, at a bigger cell size, plus every deposit as a list underneath.
//  `filter`/`heatAdjusted` are BINDINGS shared with the card, not local
//  state, so toggling the lens here and dismissing back to the card can never
//  leave the two surfaces disagreeing about which lens is active — the same
//  reasoning that made the old lane-based GoalPaceDetailView share its heat
//  binding with its card.
//

import SwiftUI

struct GoalPaceGridDetailView: View {
    let data: GoalPaceGridData
    @Binding var filter: GoalPaceGridFilter
    @Binding var heatAdjusted: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var selected: GoalPaceGridDeposit?

    init(data: GoalPaceGridData, filter: Binding<GoalPaceGridFilter>, heatAdjusted: Binding<Bool>) {
        self.data = data
        _filter = filter
        _heatAdjusted = heatAdjusted
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    goalHeader
                    filterChips
                    GoalPaceGridPlot(
                        data: data, filter: filter, heatAdjusted: heatAdjusted,
                        selected: $selected,
                        // 11pt per DAY, not 42pt per week (2026-09-01) — a
                        // week-wide cell at 42 became ~300 day columns of the
                        // same width and a mile-wide scroll.
                        cellWidth: 11, rowHeight: 32, leftGutter: 58
                    )
                    readout
                    legend
                    sessionList
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .background(Color.drip.background)
            .navigationTitle("Closing on goal pace")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if data.deposits.contains(where: { $0.paceSecHeatAdj != $0.paceSec }) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) { heatAdjusted.toggle() }
                        } label: {
                            Label("Heat-adjusted",
                                  systemImage: heatAdjusted ? "checkmark.circle.fill" : "circle")
                                .labelStyle(.titleAndIcon)
                        }
                        .accessibilityValue(heatAdjusted ? "On" : "Off")
                    }
                }
            }
        }
    }

    // MARK: - Header

    private var goalHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(paceString(Int(data.goal.paceSecPerMile.rounded())))
                    .font(.dripDisplay(34))
                    .foregroundStyle(Color.drip.textPrimary)
                Text("/MI IS GOAL PACE")
                    .font(.dripEyebrow(10))
                    .tracking(0.9)
                    .foregroundStyle(Color.drip.textTertiary)
            }
            Text("\(fmt(data.miles(filter: filter))) mi · \(filter.label)")
                .font(.dripBody(13))
                .foregroundStyle(Color.drip.textSecondary)
        }
        .padding(.top, 8)
    }

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
                    // Same reasoning as the card's readout, same wording —
                    // no "blocks" language, just what day this piece belongs to.
                    if siblings.count > 1 {
                        Text("part of a \(fmt(dayMiles)) mi day")
                            .font(.dripEyebrow(9))
                            .foregroundStyle(Color.drip.textTertiary)
                    }
                }
            } else if let h = data.headlineSession() {
                headlineReadout(h)
            } else {
                Text("Tap a mark, or scroll the list below")
                    .font(.dripBody(11.5))
                    .foregroundStyle(Color.drip.textTertiary)
            }
        }
        .frame(minHeight: 17, alignment: .leading)
    }

    /// The default state, before any tap — see GoalPaceGridCard's twin of
    /// this for the full reasoning: the most recent day's FULL volume, summed
    /// across every block, never a single fragment of it.
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

    /// Two ramps, two encodings — see GoalPaceGridPlot.densityColor for why
    /// they must not be collapsed into one.
    private var legend: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                ForEach(Array(PaceSpectrum.stops.reversed().enumerated()), id: \.offset) { _, c in
                    Rectangle().fill(c).frame(width: 14, height: 7)
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
                        .frame(width: 14, height: 7)
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

    // MARK: - Session list

    // ONE ROW PER SESSION, NOT PER BLOCK. This used to list every raw block —
    // an 8-rep interval workout was 8 nearly-identical rows for what the
    // athlete thinks of as one session. `sessionSummaries` does the same
    // day-level aggregation the default headline uses, applied consistently
    // to the whole list. Tapping a row selects that session's dominant block
    // (the pace row carrying the most of its miles), which populates the
    // block-level readout above — full detail is a tap away, not the default.
    private var sessionList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("SESSIONS · \(filter.label.uppercased())")
                .font(.dripEyebrow(9))
                .tracking(1.2)
                .foregroundStyle(Color.drip.textTertiary)
                .padding(.top, 8)
                .padding(.bottom, 8)

            ForEach(data.sessionSummaries(for: filter), id: \.date) { h in
                let pct = heatAdjusted ? h.dominant.pctOfGoalHeatAdj : h.dominant.pctOfGoal
                let pace = heatAdjusted ? h.dominant.paceSecHeatAdj : h.dominant.paceSec
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(h.date.formatted(.dateTime.day().month(.abbreviated)))
                        .font(.dripEyebrow(10))
                        .foregroundStyle(Color.drip.textTertiary)
                        .frame(width: 52, alignment: .leading)
                    Text("\(fmt(h.totalMiles)) mi")
                        .font(.dripStat(13))
                        .foregroundStyle(Color.drip.textPrimary)
                        .frame(width: 54, alignment: .leading)
                    Text("mostly \(paceString(pace))/mi")
                        .font(.dripStat(12))
                        .foregroundStyle(Color.drip.textSecondary)
                        .frame(width: 88, alignment: .leading)
                    Text("\(fmt(pct))% of goal")
                        .font(.dripBody(12))
                        .foregroundStyle(Color.drip.textSecondary)
                    Spacer()
                }
                .padding(.vertical, 7)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.drip.divider).frame(height: 1)
                }
                .onTapGesture { selected = (selected == h.dominant) ? nil : h.dominant }
            }
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

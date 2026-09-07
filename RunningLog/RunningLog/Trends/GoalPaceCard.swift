//
//  GoalPaceCard.swift
//  RunningLog · Trends
//
//  "Is my training converging on the pace I intend to race?"
//
//  THREE LANES, NOT AN AXIS. Goal pace is the only reference that matters, so
//  every key session is one of three things: faster than it, on it, or slower.
//  A lane is a verdict you read without measuring anything against a gridline —
//  which is the whole reason this reads at phone width where two earlier
//  scatter builds didn't.
//
//  MARKS ARE SIZED BY VOLUME AND MUST NEVER OVERLAP. Size carries the miles, so
//  two marks stacked on top of each other destroy the one thing size is for.
//  Each mark drops to the first slot in its lane where it clears its
//  neighbours; if a lane genuinely runs out of room the mark is CLAMPED into
//  the lane rather than left wherever the search gave up — an earlier build let
//  them escape and land on the copy above the chart.
//
//  Per-lane volume totals are the actual answer. "78% of your key-session
//  volume is slower than goal pace" is the specificity read, stated rather than
//  implied by a cloud of dots.
//
//  THREE WEEKS AT A TIME, SCROLLED. Six months compressed into 350pt is the
//  density problem that made two earlier builds unreadable — the marks were
//  never the issue, the time axis was. The viewport holds ~3 weeks at legible
//  spacing and the canvas scrolls across the whole block, opening on the most
//  recent weeks because that is the end you are training from. Tap to expand
//  for the full block and the session list.
//
//  HEAT IS A TOGGLE, NOT A DEFAULT. The server carries every pace twice, raw
//  and credited for conditions, and the goal is never adjusted — only sessions
//  move. Raw leads because this athlete's own validation found the model
//  over-credits hot laps; the correction is offered, not applied behind her
//  back. The toggle only appears when there is a correction to show.
//

import SwiftUI

struct GoalPaceCard: View {
    let data: GoalPaceData

    @State private var heatAdjusted = false
    @State private var selected: GoalPaceSession?
    @State private var showDetail = false

    private let laneHeight: CGFloat = 74
    private let chartTop: CGFloat = 8

    private var pct: (GoalPaceSession) -> Double {
        { heatAdjusted ? $0.pctOfGoalHeatAdj : $0.pctOfGoal }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            GeometryReader { geo in
                lanesScroller(laneH: laneHeight, viewportWidth: geo.size.width)
                    .overlay(alignment: .topLeading) { laneChrome(laneH: laneHeight) }
            }
            .frame(height: laneHeight * 3)
            timeline
            readout
            legend
            footnote
        }
        .padding(.vertical, 4)
        .fullScreenCover(isPresented: $showDetail) {
            GoalPaceDetailView(data: data, heatAdjusted: $heatAdjusted)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(paceString(Int(data.goal.paceSecPerMile.rounded())))
                    .font(.dripDisplay(28))
                    .foregroundStyle(Color.drip.textPrimary)
                Text("/MI IS 100%")
                    .font(.dripEyebrow(10))
                    .tracking(0.9)
                    .foregroundStyle(Color.drip.textTertiary)
                Spacer()
                if data.hasHeatData { heatToggle }
            }
            Text(summaryLine)
                .font(.dripBody(12.5))
                .foregroundStyle(Color.drip.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// One label, two states — the chip names the thing being ADDED rather than
    /// naming the untouched state. "Heat-adjusted" off means "tap to apply it";
    /// on means it is applied. Naming the default was both charmless and, as a
    /// word on its own, unfortunate.
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
        .accessibilityAddTraits(.isButton)
    }

    private var summaryLine: String {
        let total = data.totalMiles
        guard total > 0 else { return "" }
        let on = data.miles(in: .onPace, heatAdjusted: heatAdjusted) / total * 100
        let slow = data.miles(in: .slower, heatAdjusted: heatAdjusted) / total * 100
        return "\(Int(on.rounded()))% of your key-session volume sits on goal pace. "
             + "\(Int(slow.rounded()))% is slower — the aerobic base a marathon is built on."
    }

    // MARK: - Lanes

    /// Days visible in the viewport. Three weeks is about where marks stop
    /// colliding at phone width; the rest of the block is a scroll away.
    private let visibleDays: CGFloat = 21

    private var allDates: [Date] { data.sessions.map(\.date) }
    private var firstDate: Date { allDates.min() ?? Date() }
    private var lastDate: Date { max(allDates.max() ?? Date(), Date()) }
    private var spanDays: CGFloat {
        max(CGFloat(lastDate.timeIntervalSince(firstDate) / 86400), visibleDays)
    }

    private func lanesScroller(laneH: CGFloat, viewportWidth: CGFloat) -> some View {
        let ptsPerDay = max((viewportWidth - 16) / visibleDays, 1)
        let contentWidth = spanDays * ptsPerDay + 24

        return ScrollView(.horizontal, showsIndicators: false) {
            ZStack(alignment: .topLeading) {
                // Lane grounds run the full canvas so the tint and rules scroll
                // with the marks rather than floating over them.
                VStack(spacing: 0) {
                    ForEach(GoalPaceLane.allCases) { lane in
                        ZStack(alignment: .top) {
                            if lane == .onPace {
                                Rectangle().fill(Color(hex: "4E86B4").opacity(0.10))
                            }
                            if lane != .faster {
                                Rectangle().fill(Color.drip.divider).frame(height: 1)
                            }
                        }
                        .frame(height: laneH)
                    }
                }
                ForEach(GoalPaceLane.allCases) { lane in
                    ForEach(placed(lane, ptsPerDay: ptsPerDay, laneH: laneH), id: \.session.id) { m in
                        markView(m, laneIndex: laneIndex(lane), laneH: laneH)
                    }
                }
                weekTicks(ptsPerDay: ptsPerDay, laneH: laneH)
            }
            .frame(width: contentWidth, height: laneH * 3, alignment: .topLeading)
        }
        .defaultScrollAnchor(.trailing)   // open on the most recent weeks
    }

    private func laneIndex(_ lane: GoalPaceLane) -> Int {
        GoalPaceLane.allCases.firstIndex(of: lane) ?? 0
    }

    /// Week rules, so a scrolled canvas still has a sense of time.
    @ViewBuilder
    private func weekTicks(ptsPerDay: CGFloat, laneH: CGFloat) -> some View {
        let weeks = Int(spanDays / 7)
        ForEach(0...max(weeks, 0), id: \.self) { w in
            Rectangle()
                .fill(Color.drip.divider.opacity(0.5))
                .frame(width: 1, height: laneH * 3)
                .position(x: 8 + CGFloat(w) * 7 * ptsPerDay, y: laneH * 1.5)
        }
    }

    /// Lane names and volume totals, pinned so they never scroll away.
    private func laneChrome(laneH: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(GoalPaceLane.allCases) { lane in
                let miles = data.miles(in: lane, heatAdjusted: heatAdjusted)
                let share = data.totalMiles > 0 ? miles / data.totalMiles * 100 : 0
                HStack {
                    Text(lane.label)
                        .font(.dripEyebrow(8.5))
                        .tracking(1.1)
                        .foregroundStyle(lane == .onPace ? Color.drip.textSecondary
                                                         : Color.drip.textTertiary)
                    Spacer()
                    Text("\(Int(miles.rounded())) MI · \(Int(share.rounded()))%")
                        .font(.dripEyebrow(8.5))
                        .foregroundStyle(Color.drip.textSecondary)
                }
                .padding(.horizontal, 4)
                .padding(.top, 3)
                .frame(height: laneH, alignment: .top)
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Placement

    private struct Placed {
        let session: GoalPaceSession
        let x: CGFloat
        let y: CGFloat
        let r: CGFloat
    }

    private func radius(_ miles: Double) -> CGFloat {
        min(max(2.6 + sqrt(max(miles, 0.3)) * 1.5, 3.4), 11)
    }

    private func placed(_ lane: GoalPaceLane, ptsPerDay: CGFloat, laneH: CGFloat) -> [Placed] {
        let mid = laneH / 2 + 4
        let items = data.sessions(in: lane, heatAdjusted: heatAdjusted)
            .sorted { $0.date < $1.date }
        var out: [Placed] = []
        for s in items {
            let r = radius(s.continuousMiles)
            let days = CGFloat(s.date.timeIntervalSince(firstDate) / 86400)
            let x = 8 + days * ptsPerDay
            let top = 16 + r
            let bottom = laneH - 4 - r
            var y = mid
            var ok = false
            var slot = 0
            while !ok, slot < 60 {
                let dir: CGFloat = slot % 2 == 0 ? 1 : -1
                let step = CGFloat((slot + 1) / 2)
                let cand = mid + dir * step * (r * 1.7)
                slot += 1
                guard cand >= top, cand <= bottom else { continue }
                y = cand
                ok = out.allSatisfy { hypot($0.x - x, $0.y - y) >= ($0.r + r + 1.4) }
            }
            // Clamp rather than let a mark escape its lane.
            if !ok { y = min(max(y, top), bottom) }
            out.append(Placed(session: s, x: x, y: y, r: r))
        }
        return out
    }

    @ViewBuilder
    private func markView(_ m: Placed, laneIndex: Int, laneH: CGFloat) -> some View {
        let isSel = selected == m.session
        let isLong = (m.session.workoutType ?? "").contains("long")
        Circle()
            .fill(isLong ? Color(hex: "93B9D6") : Color(hex: "0E2E5C"))
            .overlay(Circle().stroke(Color.drip.background, lineWidth: 1.1))
            .overlay(Circle().stroke(Color.drip.textPrimary, lineWidth: isSel ? 1.5 : 0))
            .frame(width: m.r * 2, height: m.r * 2)
            .position(x: m.x, y: CGFloat(laneIndex) * laneH + m.y)
            .contentShape(Circle())
            .onTapGesture { selected = isSel ? nil : m.session }
    }

    // MARK: - Timeline, readout, legend

    private var timeline: some View {
        HStack(spacing: 8) {
            Text("SCROLL FOR EARLIER")
                .font(.dripEyebrow(8.5))
                .tracking(1.0)
                .foregroundStyle(Color.drip.textTertiary)
            Spacer()
            Button { showDetail = true } label: {
                HStack(spacing: 3) {
                    Text("EXPAND").font(.dripEyebrow(8.5)).tracking(1.0)
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 8, weight: .semibold))
                }
                .foregroundStyle(Color.drip.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 2)
    }

    private var readout: some View {
        Group {
            if let s = selected {
                let p = heatAdjusted ? s.paceSecHeatAdj : s.paceSec
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(s.date.formatted(.dateTime.day().month(.abbreviated)))
                        .font(.dripEyebrow(10))
                        .foregroundStyle(Color.drip.textSecondary)
                    Text("\(fmt(pct(s)))%")
                        .font(.dripStat(13))
                        .foregroundStyle(Color.drip.textPrimary)
                    Text("\(paceString(p))/mi · \(fmt(s.continuousMiles)) mi"
                         + (s.isFloatSession ? " incl. floats" : "")
                         + (heatAdjusted && s.heatGainSec > 0 ? " · −\(s.heatGainSec)s heat" : ""))
                        .font(.dripBody(11.5))
                        .foregroundStyle(Color.drip.textSecondary)
                    Spacer()
                }
            } else {
                Text("Tap a session")
                    .font(.dripBody(11.5))
                    .foregroundStyle(Color.drip.textTertiary)
            }
        }
        .frame(height: 17, alignment: .leading)
    }

    private var legend: some View {
        HStack(spacing: 15) {
            HStack(spacing: 5) {
                Circle().fill(Color(hex: "0E2E5C")).frame(width: 7, height: 7)
                Text("Reps").font(.dripEyebrow(9)).foregroundStyle(Color.drip.textTertiary)
            }
            HStack(spacing: 5) {
                Circle().fill(Color(hex: "93B9D6")).frame(width: 7, height: 7)
                Text("Long workouts").font(.dripEyebrow(9)).foregroundStyle(Color.drip.textTertiary)
            }
            HStack(spacing: 4) {
                Circle().stroke(Color.drip.textTertiary, lineWidth: 1).frame(width: 6, height: 6)
                Circle().stroke(Color.drip.textTertiary, lineWidth: 1).frame(width: 13, height: 13)
                Text("volume").font(.dripEyebrow(9)).foregroundStyle(Color.drip.textTertiary)
            }
            Spacer()
        }
    }

    private var footnote: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("LONGEST CONTINUOUS AT GOAL PACE")
                .font(.dripEyebrow(9))
                .tracking(1.1)
                .foregroundStyle(Color.drip.textTertiary)
            Text("\(fmt(data.summary.longestSpecificMiles)) mi")
                .font(.dripDisplay(17))
                .foregroundStyle(Color.drip.textPrimary)
        }
    }

    // MARK: - Formatting

    private func fmt(_ d: Double) -> String {
        d == d.rounded() ? String(Int(d)) : String(format: "%.1f", d)
    }

    private func paceString(_ sec: Int) -> String {
        var m = sec / 60
        var s = sec % 60
        if s == 60 { m += 1; s = 0 }
        return "\(m):\(String(format: "%02d", s))"
    }
}

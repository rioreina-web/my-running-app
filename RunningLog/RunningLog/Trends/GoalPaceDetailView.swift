//
//  GoalPaceDetailView.swift
//  RunningLog · Trends
//
//  The expanded goal-pace surface. Same three lanes as the card, given the room
//  the card can't spare, plus the sessions as a list — because a mark you can
//  only identify by tapping it is a poor way to read twenty of them.
//
//  Follows `KeyPaceDetailView`'s shape: a `fullScreenCover` off the card, and
//  the heat toggle is a BINDING rather than its own state, so the card and the
//  detail can never disagree about whether the correction is applied.
//

import SwiftUI

struct GoalPaceDetailView: View {
    let data: GoalPaceData
    @Binding var heatAdjusted: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var selected: GoalPaceSession?

    private let laneHeight: CGFloat = 118
    private let visibleDays: CGFloat = 42   // twice the card — room to compare blocks

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    goalHeader
                    lanes
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
                    if data.hasHeatData {
                        // Names what is added, not the untouched state.
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
                Text("/MI IS 100%")
                    .font(.dripEyebrow(10))
                    .tracking(0.9)
                    .foregroundStyle(Color.drip.textTertiary)
            }
            Text("\(data.summary.sessions) key sessions · longest continuous at goal pace "
                 + "\(fmt(data.summary.longestSpecificMiles)) mi")
                .font(.dripBody(13))
                .foregroundStyle(Color.drip.textSecondary)
        }
        .padding(.top, 8)
    }

    // MARK: - Lanes

    private var allDates: [Date] { data.sessions.map(\.date) }
    private var firstDate: Date { allDates.min() ?? Date() }
    private var lastDate: Date { max(allDates.max() ?? Date(), Date()) }
    private var spanDays: CGFloat {
        max(CGFloat(lastDate.timeIntervalSince(firstDate) / 86400), visibleDays)
    }

    private var lanes: some View {
        GeometryReader { geo in
            let ptsPerDay = max((geo.size.width - 16) / visibleDays, 1)
            let contentWidth = spanDays * ptsPerDay + 24
            ScrollView(.horizontal, showsIndicators: true) {
                ZStack(alignment: .topLeading) {
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
                            .frame(height: laneHeight)
                        }
                    }
                    ForEach(GoalPaceLane.allCases) { lane in
                        ForEach(placed(lane, ptsPerDay: ptsPerDay), id: \.session.id) { m in
                            let idx = GoalPaceLane.allCases.firstIndex(of: lane) ?? 0
                            Circle()
                                .fill(isLong(m.session) ? Color(hex: "93B9D6") : Color(hex: "0E2E5C"))
                                .overlay(Circle().stroke(Color.drip.background, lineWidth: 1.2))
                                .overlay(Circle().stroke(Color.drip.textPrimary,
                                                         lineWidth: selected == m.session ? 2 : 0))
                                .frame(width: m.r * 2, height: m.r * 2)
                                .position(x: m.x, y: CGFloat(idx) * laneHeight + m.y)
                                .onTapGesture { selected = selected == m.session ? nil : m.session }
                        }
                    }
                }
                .frame(width: contentWidth, height: laneHeight * 3, alignment: .topLeading)
            }
            .defaultScrollAnchor(.trailing)
            .overlay(alignment: .topLeading) { chrome }
        }
        .frame(height: laneHeight * 3)
    }

    private var chrome: some View {
        VStack(spacing: 0) {
            ForEach(GoalPaceLane.allCases) { lane in
                let miles = data.miles(in: lane, heatAdjusted: heatAdjusted)
                let share = data.totalMiles > 0 ? miles / data.totalMiles * 100 : 0
                HStack {
                    Text(lane.label)
                        .font(.dripEyebrow(9))
                        .tracking(1.1)
                        .foregroundStyle(lane == .onPace ? Color.drip.textSecondary
                                                         : Color.drip.textTertiary)
                    Spacer()
                    Text("\(Int(miles.rounded())) MI · \(Int(share.rounded()))%")
                        .font(.dripEyebrow(9))
                        .foregroundStyle(Color.drip.textSecondary)
                }
                .padding(.horizontal, 4)
                .padding(.top, 4)
                .frame(height: laneHeight, alignment: .top)
            }
        }
        .allowsHitTesting(false)
    }

    private struct Placed {
        let session: GoalPaceSession
        let x: CGFloat
        let y: CGFloat
        let r: CGFloat
    }

    private func radius(_ miles: Double) -> CGFloat {
        min(max(3 + sqrt(max(miles, 0.3)) * 2.0, 4), 15)
    }

    private func placed(_ lane: GoalPaceLane, ptsPerDay: CGFloat) -> [Placed] {
        let mid = laneHeight / 2 + 6
        let items = data.sessions(in: lane, heatAdjusted: heatAdjusted).sorted { $0.date < $1.date }
        var out: [Placed] = []
        for s in items {
            let r = radius(s.continuousMiles)
            let x = 8 + CGFloat(s.date.timeIntervalSince(firstDate) / 86400) * ptsPerDay
            let top = 20 + r, bottom = laneHeight - 5 - r
            var y = mid, ok = false, slot = 0
            while !ok, slot < 60 {
                let dir: CGFloat = slot % 2 == 0 ? 1 : -1
                let cand = mid + dir * CGFloat((slot + 1) / 2) * (r * 1.7)
                slot += 1
                guard cand >= top, cand <= bottom else { continue }
                y = cand
                ok = out.allSatisfy { hypot($0.x - x, $0.y - y) >= ($0.r + r + 1.5) }
            }
            if !ok { y = min(max(y, top), bottom) }
            out.append(Placed(session: s, x: x, y: y, r: r))
        }
        return out
    }

    // MARK: - Session list

    private var sessionList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("EVERY KEY SESSION")
                .font(.dripEyebrow(9))
                .tracking(1.2)
                .foregroundStyle(Color.drip.textTertiary)
                .padding(.bottom, 8)

            ForEach(data.sessions.sorted { $0.date > $1.date }) { s in
                let p = heatAdjusted ? s.pctOfGoalHeatAdj : s.pctOfGoal
                let pace = heatAdjusted ? s.paceSecHeatAdj : s.paceSec
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(s.date.formatted(.dateTime.day().month(.abbreviated)))
                        .font(.dripEyebrow(10))
                        .foregroundStyle(Color.drip.textTertiary)
                        .frame(width: 52, alignment: .leading)
                    Text("\(fmt(p))%")
                        .font(.dripStat(13))
                        .foregroundStyle(Color.drip.textPrimary)
                        .frame(width: 46, alignment: .leading)
                    Text("\(paceString(pace))/mi")
                        .font(.dripStat(12))
                        .foregroundStyle(Color.drip.textSecondary)
                        .frame(width: 62, alignment: .leading)
                    Text("\(fmt(s.continuousMiles)) mi"
                         + (s.isFloatSession ? " · floats" : ""))
                        .font(.dripBody(12))
                        .foregroundStyle(Color.drip.textSecondary)
                    Spacer()
                    if heatAdjusted, s.heatGainSec > 0 {
                        Text("−\(s.heatGainSec)s")
                            .font(.dripEyebrow(9))
                            .foregroundStyle(Color.drip.textTertiary)
                    }
                }
                .padding(.vertical, 7)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.drip.divider).frame(height: 1)
                }
            }
        }
    }

    // MARK: - Helpers

    private func isLong(_ s: GoalPaceSession) -> Bool {
        (s.workoutType ?? "").contains("long")
    }
    private func fmt(_ d: Double) -> String {
        d == d.rounded() ? String(Int(d)) : String(format: "%.1f", d)
    }
    private func paceString(_ sec: Int) -> String {
        var m = sec / 60, s = sec % 60
        if s == 60 { m += 1; s = 0 }
        return "\(m):\(String(format: "%02d", s))"
    }
}

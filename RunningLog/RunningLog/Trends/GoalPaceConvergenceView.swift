//
//  GoalPaceConvergenceView.swift
//  RunningLog · Trends
//
//  Full-screen goal-pace visualization: every block plotted continuously
//  by date (x) and percent of goal pace (y) — not bucketed into the
//  calendar-week × pace-band grid GoalPaceGridPlot draws. Same underlying
//  data (`GoalPaceGridData` — real, block-level, server-computed in
//  `trends-timeline/goalPaceGrid.ts`); this is a different renderer over
//  the same real numbers, not a new backend. Ported from an HTML
//  prototype validated against this athlete's real training_logs first.
//
//  Domain (pctDomain) is pinned to the FULL, unfiltered deposit set, same
//  principle as GoalPaceGridPlot's globalMaxCell — switching Key/Long
//  filters must only ever remove marks, never rescale the axes under them.
//
//  Known gap: no "planned" future sessions. That needs a
//  scheduled_workouts fetch this view doesn't do yet. When an athlete has
//  no active plan (true for the athlete this was built against), the
//  runway between today and race day is honestly empty, not faked.
//

import SwiftUI

struct GoalPaceConvergenceView: View {
    let data: GoalPaceGridData
    @Binding var filter: GoalPaceGridFilter
    @Binding var heatAdjusted: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var selected: GoalPaceGridDeposit?

    private let dayWidth: CGFloat = 8.3
    private let marginLeft: CGFloat = 46
    private let marginRight: CGFloat = 24
    private let marginTop: CGFloat = 18
    private let axisPad: CGFloat = 34

    // MARK: - Domain

    /// Pinned to every deposit regardless of `filter`, so switching lenses
    /// can only remove marks, never rescale the chart under them.
    private var pctDomain: ClosedRange<Double> {
        let pcts = data.deposits.map { heatAdjusted ? $0.pctOfGoalHeatAdj : $0.pctOfGoal }
        let lo = min((pcts.min() ?? 80) - 6, 90)
        let hi = max((pcts.max() ?? 120) + 6, 110)
        return lo...hi
    }
    private var rangeStart: Date {
        data.deposits.map(\.date).min() ?? Date()
    }
    /// Through race day when known, else through today — an empty runway
    /// ahead is information (no plan on file), not something to hide.
    private var rangeEnd: Date {
        max(data.goal.raceDate ?? Date(), Date())
    }
    private var totalDays: CGFloat {
        CGFloat(max(Calendar.current.dateComponents([.day], from: rangeStart, to: rangeEnd).day ?? 1, 1))
    }
    private var plotWidth: CGFloat { totalDays * dayWidth }

    private func x(for date: Date) -> CGFloat {
        let days = Calendar.current.dateComponents([.day], from: rangeStart, to: date).day ?? 0
        return marginLeft + CGFloat(days) * dayWidth
    }
    private func y(for pct: Double, plotHeight: CGFloat) -> CGFloat {
        let d = pctDomain
        let t = (pct - d.lowerBound) / (d.upperBound - d.lowerBound)
        return marginTop + plotHeight - CGFloat(t) * plotHeight
    }
    private func paceColor(_ pct: Double) -> Color {
        let d = pctDomain
        let t = (pct - d.lowerBound) / (d.upperBound - d.lowerBound)
        return PaceSpectrum.color(at: t)
    }
    private func radius(for miles: Double) -> CGFloat {
        max(4, min(20, 3 + CGFloat(miles.squareRoot()) * 3))
    }

    private struct MarkGeom {
        let deposit: GoalPaceGridDeposit
        let point: CGPoint
        let radius: CGFloat
        let visible: Bool
    }

    private func marks(plotHeight: CGFloat) -> [MarkGeom] {
        let visibleIds = Set(data.deposits(for: filter).map(\.id))
        let byWorkout = Dictionary(grouping: data.deposits, by: \.workoutId)
        var out: [MarkGeom] = []
        for (_, deps) in byWorkout {
            for (i, dep) in deps.enumerated() {
                let pct = heatAdjusted ? dep.pctOfGoalHeatAdj : dep.pctOfGoal
                let jitter = CGFloat(i) - CGFloat(deps.count - 1) / 2
                let point = CGPoint(x: x(for: dep.date) + jitter * 5, y: y(for: pct, plotHeight: plotHeight))
                out.append(MarkGeom(deposit: dep, point: point, radius: radius(for: dep.miles),
                                     visible: visibleIds.contains(dep.id)))
            }
        }
        return out
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                header
                controls
                legend
                GeometryReader { geo in
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            ZStack(alignment: .topLeading) {
                                chart(height: geo.size.height)
                                // A dedicated, uniquely-keyed anchor at
                                // today's actual x — tagging the whole
                                // Canvas with `.id()` and a fractional
                                // UnitPoint anchor targets a fixed FRACTION
                                // of total width, which drifts as more
                                // training accumulates and the content
                                // widens. That's the exact bug that made
                                // the calendar-grid version open on the
                                // race week; this is the fix for it, ported.
                                Color.clear
                                    .frame(width: 1, height: 1)
                                    .id("today")
                                    .position(x: x(for: Date()), y: geo.size.height / 2)
                            }
                        }
                        .onAppear {
                            DispatchQueue.main.async {
                                proxy.scrollTo("today", anchor: .trailing)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)
            .background(Color.drip.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
            .overlay(alignment: .bottom) {
                if let selected { detailPanel(selected) }
            }
        }
    }

    // MARK: - Header

    private var stats: (days: Int, sessions: Int, miles: Double, nearPct: Int) {
        let now = Date()
        let days = data.goal.raceDate.map {
            Calendar.current.dateComponents([.day], from: now, to: $0).day ?? 0
        } ?? 0
        let key = data.deposits.filter(\.isKey)
        let sessions = Set(key.map(\.workoutId)).count
        let miles = key.reduce(0) { $0 + $1.miles }
        let near = key.filter {
            let p = heatAdjusted ? $0.pctOfGoalHeatAdj : $0.pctOfGoal
            return p >= 95 && p <= 105
        }.reduce(0) { $0 + $1.miles }
        let nearPct = miles > 0 ? Int((near / miles * 100).rounded()) : 0
        return (days, sessions, miles, nearPct)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("GOAL PACE CONVERGENCE")
                    .font(.dripEyebrow(10)).tracking(1.2)
                    .foregroundStyle(Color.drip.textSecondary)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(paceString(Int(data.goal.paceSecPerMile.rounded())))
                        .font(.dripDisplay(28))
                        .foregroundStyle(Color.drip.textPrimary)
                    Text("/MI IS 100%")
                        .font(.dripEyebrow(10)).tracking(0.8)
                        .foregroundStyle(Color.drip.textTertiary)
                }
                if let raceDate = data.goal.raceDate {
                    Text(raceDate.formatted(date: .long, time: .omitted))
                        .font(.dripBody(13))
                        .foregroundStyle(Color.drip.textSecondary)
                }
            }
            Spacer()
            HStack(spacing: 18) {
                statFigure("\(stats.days)", "Days to race")
                statFigure("\(stats.sessions)", "Key sessions")
                statFigure(fmt(stats.miles) + " mi", "Key miles")
                statFigure("\(stats.nearPct)%", "Within 5%")
            }
        }
    }

    private func statFigure(_ value: String, _ label: String) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(value)
                .font(.dripStat(16))
                .foregroundStyle(Color.drip.textPrimary)
            Text(label.uppercased())
                .font(.dripEyebrow(8.5)).tracking(0.6)
                .foregroundStyle(Color.drip.textTertiary)
        }
    }

    // MARK: - Controls

    private var controls: some View {
        HStack {
            HStack(spacing: 6) {
                ForEach(GoalPaceGridFilter.allCases) { f in
                    Button(f.label) { filter = f }
                        .font(.dripEyebrow(11))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(
                            Capsule().fill(filter == f ? Color.drip.textPrimary : Color.clear)
                        )
                        .overlay(
                            Capsule().stroke(filter == f ? Color.clear : Color.drip.divider, lineWidth: 1)
                        )
                        .foregroundStyle(filter == f ? Color.drip.background : Color.drip.textSecondary)
                }
            }
            Spacer()
            if data.deposits.contains(where: { $0.pctOfGoalHeatAdj != $0.pctOfGoal }) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { heatAdjusted.toggle() }
                } label: {
                    Label("Heat-adjusted", systemImage: heatAdjusted ? "checkmark.circle.fill" : "circle")
                        .font(.dripEyebrow(11))
                        .foregroundStyle(Color.drip.textSecondary)
                }
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 16) {
            HStack(spacing: 6) {
                Circle().fill(Color.drip.textPrimary).frame(width: 8, height: 8)
                Text("Logged · colour = pace, size = miles")
            }
            Text("Every mark is one block, never a whole session averaged into one number")
        }
        .font(.dripEyebrow(9.5))
        .foregroundStyle(Color.drip.textTertiary)
    }

    // MARK: - Chart

    private func chart(height: CGFloat) -> some View {
        let plotH = max(height - axisPad, 220)
        let markList = marks(plotHeight: plotH)
        let width = marginLeft + plotWidth + marginRight

        return Canvas { context, size in
            drawBackground(&context, plotH: plotH, width: size.width)
            drawGridlines(&context, plotH: plotH, width: size.width)
            drawGoalLine(&context, plotH: plotH, width: size.width)
            drawMonthTicks(&context, plotH: plotH)
            drawTodayAndRace(&context, plotH: plotH)
            drawMarks(&context, marks: markList)
        }
        .frame(width: width, height: height)
        .contentShape(Rectangle())
        .gesture(
            SpatialTapGesture().onEnded { value in
                hitTest(at: value.location, in: markList)
            }
        )
    }

    private func drawBackground(_ context: inout GraphicsContext, plotH: CGFloat, width: CGFloat) {
        let rect = CGRect(x: marginLeft, y: marginTop, width: plotWidth, height: plotH)
        let gradient = Gradient(colors: [
            PaceSpectrum.color(at: 1).opacity(0.09),
            PaceSpectrum.color(at: 0).opacity(0.09),
        ])
        context.fill(Path(rect), with: .linearGradient(
            gradient, startPoint: CGPoint(x: 0, y: marginTop), endPoint: CGPoint(x: 0, y: marginTop + plotH)
        ))
    }

    private func drawGridlines(_ context: inout GraphicsContext, plotH: CGFloat, width: CGFloat) {
        let d = pctDomain
        var p = (Int(d.lowerBound / 10) + 1) * 10
        while Double(p) < d.upperBound {
            let yy = y(for: Double(p), plotHeight: plotH)
            var path = Path()
            path.move(to: CGPoint(x: marginLeft, y: yy))
            path.addLine(to: CGPoint(x: marginLeft + plotWidth, y: yy))
            context.stroke(path, with: .color(Color.drip.divider.opacity(0.5)), lineWidth: 1)
            context.draw(
                Text("\(p)%").font(.dripEyebrow(8)).foregroundStyle(Color.drip.textTertiary),
                at: CGPoint(x: 10, y: yy), anchor: .leading
            )
            p += 10
        }
    }

    private func drawGoalLine(_ context: inout GraphicsContext, plotH: CGFloat, width: CGFloat) {
        let gy = y(for: 100, plotHeight: plotH)
        var path = Path()
        path.move(to: CGPoint(x: marginLeft, y: gy))
        path.addLine(to: CGPoint(x: marginLeft + plotWidth, y: gy))
        context.stroke(path, with: .color(Color.drip.textPrimary.opacity(0.6)), lineWidth: 1.6)
        context.draw(
            Text("GOAL PACE").font(.dripEyebrow(9)).bold().foregroundStyle(Color.drip.textPrimary),
            at: CGPoint(x: marginLeft + 4, y: gy - 9), anchor: .leading
        )
    }

    private func drawMonthTicks(_ context: inout GraphicsContext, plotH: CGFloat) {
        let cal = Calendar.current
        var lastMonth = -1
        var d = rangeStart
        let axisBottom = marginTop + plotH + axisPad - 14
        while d <= rangeEnd {
            let m = cal.component(.month, from: d)
            if m != lastMonth {
                lastMonth = m
                let xx = x(for: d)
                var path = Path()
                path.move(to: CGPoint(x: xx, y: marginTop))
                path.addLine(to: CGPoint(x: xx, y: axisBottom))
                context.stroke(path, with: .color(Color.drip.divider.opacity(0.5)), lineWidth: 1)
                context.draw(
                    Text(d.formatted(.dateTime.month(.abbreviated)).uppercased())
                        .font(.dripEyebrow(8)).foregroundStyle(Color.drip.textTertiary),
                    at: CGPoint(x: xx + 4, y: axisBottom + 14), anchor: .leading
                )
            }
            d = cal.date(byAdding: .day, value: 1, to: d) ?? rangeEnd.addingTimeInterval(1)
        }
    }

    private func drawTodayAndRace(_ context: inout GraphicsContext, plotH: CGFloat) {
        let axisBottom = marginTop + plotH + axisPad - 14
        let todayX = x(for: Date())
        var todayPath = Path()
        todayPath.move(to: CGPoint(x: todayX, y: marginTop - 2))
        todayPath.addLine(to: CGPoint(x: todayX, y: axisBottom))
        context.stroke(todayPath, with: .color(Color.drip.textPrimary), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
        context.draw(
            Text("TODAY").font(.dripEyebrow(9)).bold().foregroundStyle(Color.drip.textPrimary),
            at: CGPoint(x: todayX + 5, y: marginTop + 9), anchor: .leading
        )

        if let raceDate = data.goal.raceDate {
            let raceX = x(for: raceDate)
            let label = raceX - todayX > 60 ? "RACE DAY" : "RACE DAY — NO PLAN YET"
            context.draw(
                Text(label).font(.dripEyebrow(9)).bold().foregroundStyle(PaceSpectrum.mile),
                at: CGPoint(x: raceX - 4, y: marginTop + 9), anchor: .trailing
            )
        }
    }

    private func drawMarks(_ context: inout GraphicsContext, marks: [MarkGeom]) {
        for m in marks {
            let pct = heatAdjusted ? m.deposit.pctOfGoalHeatAdj : m.deposit.pctOfGoal
            let color = paceColor(pct)
            let rect = CGRect(x: m.point.x - m.radius, y: m.point.y - m.radius,
                               width: m.radius * 2, height: m.radius * 2)
            var circle = context
            circle.opacity = m.visible ? 1 : 0.12
            circle.fill(Path(ellipseIn: rect), with: .color(color.opacity(0.88)))
            circle.stroke(Path(ellipseIn: rect), with: .color(Color.drip.background), lineWidth: 1.2)
            if selected?.id == m.deposit.id {
                let ring = rect.insetBy(dx: -4, dy: -4)
                circle.stroke(Path(ellipseIn: ring), with: .color(Color.drip.textPrimary), lineWidth: 1.4)
            }
        }
    }

    private func hitTest(at point: CGPoint, in marks: [MarkGeom]) {
        let hit = marks
            .filter { $0.visible }
            .min { a, b in
                hypot(a.point.x - point.x, a.point.y - point.y) < hypot(b.point.x - point.x, b.point.y - point.y)
            }
        guard let hit, hypot(hit.point.x - point.x, hit.point.y - point.y) <= max(hit.radius, 14) else { return }
        withAnimation(.easeOut(duration: 0.15)) { selected = hit.deposit }
    }

    // MARK: - Detail panel

    private func detailPanel(_ dep: GoalPaceGridDeposit) -> some View {
        let siblings = data.sessionDeposits(matching: dep).sorted { $0.miles > $1.miles }
        let pct = heatAdjusted ? dep.pctOfGoalHeatAdj : dep.pctOfGoal
        let paceSec = heatAdjusted ? dep.paceSecHeatAdj : dep.paceSec
        let totalMiles = siblings.reduce(0) { $0 + $1.miles }

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(dep.date.formatted(date: .abbreviated, time: .omitted).uppercased())
                        .font(.dripEyebrow(9)).foregroundStyle(Color.drip.textTertiary)
                    Text(dep.workoutType?.capitalized ?? "Session")
                        .font(.dripDisplay(18)).foregroundStyle(Color.drip.textPrimary)
                }
                Spacer()
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { selected = nil }
                } label: {
                    Text("CLOSE ✕").font(.dripEyebrow(10)).foregroundStyle(Color.drip.textSecondary)
                }
            }
            HStack(spacing: 22) {
                statFigure(fmt(dep.miles) + " mi", "This block")
                statFigure("\(Int((pct * 10).rounded()) / 10)%", "Of goal pace")
                statFigure(paceString(paceSec) + "/mi", "Actual pace")
                if siblings.count > 1 {
                    statFigure(fmt(totalMiles) + " mi", "Full session")
                }
            }
            if siblings.count > 1 {
                VStack(alignment: .leading, spacing: 4) {
                    Text("THIS SESSION — \(siblings.count) BLOCKS")
                        .font(.dripEyebrow(9)).foregroundStyle(Color.drip.textTertiary)
                    ForEach(siblings) { s in
                        let sPct = heatAdjusted ? s.pctOfGoalHeatAdj : s.pctOfGoal
                        let sPace = heatAdjusted ? s.paceSecHeatAdj : s.paceSec
                        HStack(spacing: 8) {
                            Circle().fill(paceColor(sPct)).frame(width: 8, height: 8)
                            Text("\(fmt(s.miles)) mi").font(.dripBody(13))
                            Text("·").foregroundStyle(Color.drip.textTertiary)
                            Text("\(Int((sPct * 10).rounded()) / 10)%").font(.dripBody(13))
                            Text("·").foregroundStyle(Color.drip.textTertiary)
                            Text("\(paceString(sPace))/mi").font(.dripBody(13)).foregroundStyle(Color.drip.textSecondary)
                        }
                        .fontWeight(s.id == dep.id ? .semibold : .regular)
                    }
                }
            }
        }
        .padding(18)
        .background(Color.drip.background)
        .overlay(alignment: .top) { Rectangle().fill(Color.drip.divider).frame(height: 1) }
        .transition(.move(edge: .bottom))
    }

    // MARK: - Helpers

    private func fmt(_ d: Double) -> String {
        d == d.rounded() ? String(Int(d)) : String(format: "%.1f", d)
    }
    private func paceString(_ sec: Int) -> String {
        var m = sec / 60, s = sec % 60
        if s == 60 { m += 1; s = 0 }
        return "\(m):\(String(format: "%02d", s))"
    }
}

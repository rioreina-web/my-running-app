//
//  TrendsThresholdView.swift
//  RunningLog · Trends
//
//  Section 04 — threshold work against the athlete's own half-marathon band.
//
//  One chart, one rule. Pace runs up the y axis with faster at the top and the
//  band drawn as a shaded region, so a session's height *is* the claim: inside
//  the shading, it happened at threshold pace. Dot area is minutes, so a
//  six-minute clip and a thirty-five-minute block cannot read alike.
//
//  The grading rule from `ThresholdBuilder` is drawn rather than footnoted.
//  Minutes that cleared the heart-rate floor are solid; minutes that did not
//  are hollow, and the legend names the floor. That is the whole argument of
//  the 2026-08-02 band audit, rendered instead of written.
//
//  Chrome-free by design: no card, no title, no range control. The parent
//  `section(eyebrow:number:sub:)` supplies those, and the window comes from the
//  tab's one time control.
//

import SwiftUI

struct TrendsThresholdView: View {
    let read: ThresholdRead
    /// Tapping a session opens its workout.
    var onSelect: ((String) -> Void)?

    /// 168 in the inline card; the full-screen detail passes 250.
    ///
    /// A parameter rather than a second view: two threshold charts is how the
    /// card and the detail start disagreeing about the same miles. Everything
    /// downstream — the `Layout`, the domain, the mark radius — already reads
    /// this, so the taller frame is genuinely the same picture with more room.
    var chartHeight: CGFloat = 168

    @State private var scrubIndex: Int?

    // Geometry, in points.
    private let gutter: CGFloat = 34
    private let axisHeight: CGFloat = 16

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            statRow
                .padding(.top, 16)

            readoutLine
                .padding(.top, 14)

            chart
                .padding(.top, 6)

            legend
                .padding(.top, 10)
        }
    }

    // MARK: Stats

    private var statRow: some View {
        DripStatStrip(stats: [
            DripStat("IN BAND", minuteLabel(read.workMinutes), unit: "min"),
            DripStat("SESSIONS", "\(read.workPoints.count)"),
            DripStat("BEST", TrendsFormat.pace(read.best?.adjSec)),
            DripStat("AVG HR", read.workHrAvg.map { "\($0)" } ?? "—", unit: read.workHrAvg == nil ? nil : "bpm"),
        ])
    }

    // MARK: Readout

    /// One line above the chart. Idle it states the window; scrubbed it states
    /// the session. Same slot either way, so the chart never jumps.
    private var readoutLine: some View {
        Text(readoutText)
            .font(.dripEyebrow(9.5))
            .tracking(0.7)
            .foregroundStyle(Color.drip.textTertiary)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.easeInOut(duration: 0.12), value: readoutText)
    }

    private var readoutText: String {
        if let i = scrubIndex, read.points.indices.contains(i) {
            let p = read.points[i]
            var bits: [String] = [
                p.dateLabel.uppercased(),
                "\(minuteLabel(p.minutes)) MIN IN BAND",
                TrendsFormat.pace(p.adjSec),
            ]
            if p.hasCorrection {
                bits.append("RAW \(TrendsFormat.pace(p.rawSec))")
            }
            // Only worth saying when the time came in pieces — on a single
            // unbroken block the two numbers are the same number.
            if p.isFragmented {
                bits.append("LONGEST BLOCK \(minuteLabel(p.blockMinutes))")
            }
            if let hr = p.hrAvg { bits.append("\(hr) BPM") }
            switch p.grade {
            case .work: break
            case .cruise: bits.append("UNDER THE \(read.hrFloor) FLOOR")
            case .unclassed: bits.append("NO HR — NOT GRADED")
            }
            return bits.joined(separator: " · ")
        }

        var bits = ["\(read.points.count) SESSIONS IN THE BAND"]
        // What the minimums held out, said out loud. A gate that quietly
        // deletes running reads as "there was none".
        if read.excludedSessions > 0 {
            bits.append(
                "\(read.excludedSessions) BELOW THE MINIMUM"
                    + (read.excludedMinutes >= 1
                        ? " (\(minuteLabel(read.excludedMinutes)) MIN)" : "")
            )
        }
        if read.cruiseMinutes >= 1 {
            bits.append("\(minuteLabel(read.cruiseMinutes)) MIN UNDER THE FLOOR")
        }
        if let t = read.trendSecPerMonth {
            let sign = t > 0 ? "+" : ""
            bits.append("TREND \(sign)\(String(format: "%.1f", t)) S/MI PER MONTH")
        }
        return bits.joined(separator: " · ")
    }

    // MARK: Chart

    private var chart: some View {
        GeometryReader { geo in
            let layout = Layout(
                width: geo.size.width,
                height: chartHeight - axisHeight,
                gutter: gutter,
                read: read
            )
            Canvas { ctx, _ in draw(ctx, layout: layout) }
                .accessibilityLabel(accessibilitySummary)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 12)
                        .onChanged { value in
                            // Horizontal-dominant only, so a vertical pan still
                            // scrolls the tab rather than scrubbing the chart.
                            guard abs(value.translation.width) >= abs(value.translation.height)
                            else { return }
                            scrubIndex = layout.index(atX: value.location.x)
                        }
                )
                .simultaneousGesture(
                    SpatialTapGesture()
                        .onEnded { value in
                            let i = layout.index(atX: value.location.x)
                            if scrubIndex == i, let i, read.points.indices.contains(i) {
                                // Second tap on the same session opens it.
                                onSelect?(read.points[i].id)
                            } else {
                                scrubIndex = i
                            }
                        }
                )
        }
        .frame(height: chartHeight)
    }

    private var accessibilitySummary: String {
        "Threshold sessions against the \(read.anchor.proseLabel) pace band. "
            + "\(read.workPoints.count) graded sessions, \(minuteLabel(read.workMinutes)) minutes in band."
    }

    private func draw(_ ctx: GraphicsContext, layout: Layout) {
        guard !read.points.isEmpty else { return }

        let bandColor = read.anchorColor

        // ---- the band, as one shaded region
        let bandRect = CGRect(
            x: layout.gutter,
            y: layout.y(read.fastSec),
            width: max(0, layout.width - layout.gutter),
            height: max(0, layout.y(read.slowSec) - layout.y(read.fastSec))
        )
        ctx.fill(Path(bandRect), with: .color(bandColor.opacity(0.12)))
        for edge in [read.fastSec, read.slowSec] {
            var p = Path()
            p.move(to: CGPoint(x: layout.gutter, y: layout.y(edge)))
            p.addLine(to: CGPoint(x: layout.width, y: layout.y(edge)))
            ctx.stroke(
                p,
                with: .color(bandColor.opacity(0.45)),
                style: StrokeStyle(lineWidth: 1, dash: read.lowConfidence ? [3, 3] : [])
            )
        }

        // ---- y labels: the two edges and the anchor
        for sec in [read.fastSec, read.anchorSec, read.slowSec] {
            ctx.draw(
                Text(TrendsFormat.pace(sec))
                    .font(.dripEyebrow(8.5))
                    .foregroundStyle(Color.drip.textTertiary),
                at: CGPoint(x: layout.gutter - 6, y: layout.y(sec)),
                anchor: .trailing
            )
        }

        // ---- scrub rule, under the marks
        if let i = scrubIndex, read.points.indices.contains(i) {
            var line = Path()
            line.move(to: CGPoint(x: layout.x(i), y: 0))
            line.addLine(to: CGPoint(x: layout.x(i), y: layout.height))
            ctx.stroke(
                line,
                with: .color(Color.drip.textPrimary.opacity(0.35)),
                style: StrokeStyle(lineWidth: 1, dash: [2, 2])
            )
        }

        // ---- one mark per session
        for (i, p) in read.points.enumerated() {
            let x = layout.x(i)
            let yAdj = layout.y(p.adjSec)
            let r = layout.radius(minutes: p.minutes)

            // Heat correction: a coral stem from what the watch said to what the
            // run was worth, with a hollow ring at the raw pace. Coral is the
            // alert palette and appears once per mark, never as a pace fill.
            if p.hasCorrection {
                let yRaw = layout.y(p.rawSec)
                var stem = Path()
                stem.move(to: CGPoint(x: x, y: yRaw))
                stem.addLine(to: CGPoint(x: x, y: yAdj))
                ctx.stroke(stem, with: .color(Color.drip.coral.opacity(0.55)), lineWidth: 1.6)

                let ring = CGRect(x: x - 3.5, y: yRaw - 3.5, width: 7, height: 7)
                ctx.fill(Path(ellipseIn: ring), with: .color(Color.drip.cardBackground))
                ctx.stroke(Path(ellipseIn: ring), with: .color(Color.drip.coral), lineWidth: 1.4)
            }

            let dot = CGRect(x: x - r, y: yAdj - r, width: r * 2, height: r * 2)
            switch p.grade {
            case .work:
                ctx.fill(Path(ellipseIn: dot), with: .color(bandColor))
            case .cruise:
                // Pale and solid — it happened, it just wasn't threshold.
                ctx.fill(Path(ellipseIn: dot), with: .color(bandColor.opacity(0.28)))
            case .unclassed:
                // Hollow — we have no effort reading, so we make no claim.
                ctx.fill(Path(ellipseIn: dot), with: .color(Color.drip.cardBackground))
                ctx.stroke(Path(ellipseIn: dot), with: .color(bandColor.opacity(0.55)), lineWidth: 1.2)
            }
            ctx.stroke(
                Path(ellipseIn: dot),
                with: .color(Color.drip.cardBackground),
                lineWidth: scrubIndex == i ? 2 : 0.8
            )
        }

        // ---- axis: first and last session only, so labels never collide
        if let first = read.points.first, let last = read.points.last {
            ctx.draw(
                Text(first.dateLabel.uppercased())
                    .font(.dripEyebrow(8.5))
                    .foregroundStyle(Color.drip.textTertiary),
                at: CGPoint(x: layout.gutter, y: layout.height + 8),
                anchor: .leading
            )
            if read.points.count > 1 {
                ctx.draw(
                    Text(last.dateLabel.uppercased())
                        .font(.dripEyebrow(8.5))
                        .foregroundStyle(Color.drip.textTertiary),
                    at: CGPoint(x: layout.width, y: layout.height + 8),
                    anchor: .trailing
                )
            }
        }
    }

    // MARK: Legend

    private var legend: some View {
        HStack(spacing: 14) {
            legendItem(fill: read.anchorColor, label: "Threshold work")
            if !read.cruisePoints.isEmpty {
                legendItem(fill: read.anchorColor.opacity(0.28), label: "Under \(read.hrFloor) bpm")
            }
            if !read.unclassedPoints.isEmpty {
                legendItem(fill: nil, label: "No HR")
            }
            Spacer(minLength: 0)
            Text("SIZE = MINUTES")
                .font(.dripEyebrow(8.5))
                .tracking(0.8)
                .foregroundStyle(Color.drip.textTertiary)
        }
    }

    private func legendItem(fill: Color?, label: String) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(fill ?? Color.drip.cardBackground)
                .overlay(
                    Circle().stroke(
                        fill == nil ? read.anchorColor.opacity(0.55) : Color.clear,
                        lineWidth: 1
                    )
                )
                .frame(width: 7, height: 7)
            Text(label.uppercased())
                .font(.dripEyebrow(8.5))
                .tracking(0.8)
                .foregroundStyle(Color.drip.textSecondary)
        }
    }

    // MARK: Formatting

    private func minuteLabel(_ minutes: Double) -> String {
        String(Int(minutes.rounded()))
    }

    // MARK: Geometry

    /// Pure geometry, mirroring the `Layout` idiom in `TrendsSignalLanes`.
    private struct Layout {
        let width: CGFloat
        let height: CGFloat
        let gutter: CGFloat
        let read: ThresholdRead

        /// Computed once. `radius` used to walk every point to find this, and
        /// `x` calls `radius` for its inset — so a single drag allocated one
        /// array per point per event. Scrubbing a six-month window is not the
        /// place to be doing O(n²) work.
        private let maxMinutes: Double
        /// Horizontal breathing room at each end, so the largest mark can't
        /// clip. Does not vary with the point, so it is not recomputed per point.
        private let inset: CGFloat

        init(width: CGFloat, height: CGFloat, gutter: CGFloat, read: ThresholdRead) {
            self.width = width
            self.height = height
            self.gutter = gutter
            self.read = read
            self.maxMinutes = read.points.map(\.minutes).max() ?? 1
            let scale = CGFloat(max(1, height / 152).squareRoot())
            self.inset = max(12, (3.5 + 6) * scale + 2)
        }

        /// The pace domain, padded a little past the band so a session outside
        /// it still lands on screen.
        private var domain: (fast: Double, slow: Double) {
            let paces = read.points.map { Double($0.adjSec) } + read.points.map { Double($0.rawSec) }
            let lo = min(Double(read.fastSec), paces.min() ?? Double(read.fastSec))
            let hi = max(Double(read.slowSec), paces.max() ?? Double(read.slowSec))
            let pad = max(6, (hi - lo) * 0.10)
            return (lo - pad, hi + pad)
        }

        /// Faster pace draws higher. Never flip the axis — the house rule is
        /// that pace is plotted as pace.
        func y(_ sec: Int) -> CGFloat {
            let d = domain
            let span = max(1, d.slow - d.fast)
            let t = (Double(sec) - d.fast) / span
            return CGFloat(min(1, max(0, t))) * height
        }

        private var plotWidth: CGFloat { max(1, width - gutter) }

        func x(_ i: Int) -> CGFloat {
            let n = read.points.count
            guard n > 1 else { return gutter + plotWidth / 2 }
            let usable = max(1, plotWidth - inset * 2)
            return gutter + inset + usable * CGFloat(i) / CGFloat(n - 1)
        }

        /// Area, not diameter, tracks minutes — so a 30-minute block reads
        /// twice the 15-minute one rather than four times it.
        ///
        /// The `3.5 + 6` pair was tuned against the inline card's 152pt plot.
        /// On the detail's taller frame the same dots read as pinpricks, so the
        /// whole ramp scales with the frame — by its square root, so a 54%
        /// taller chart grows marks 24% rather than 54% and the picture stays
        /// a scatter rather than becoming a bubble chart.
        func radius(minutes: Double) -> CGFloat {
            guard maxMinutes > 0 else { return 4 * frameScale }
            let t = min(1, minutes / maxMinutes)
            return (3.5 + 6 * CGFloat(t.squareRoot())) * frameScale
        }

        /// 1 at the inline card's plot height, growing by its square root.
        private var frameScale: CGFloat {
            CGFloat(max(1, height / 152).squareRoot())
        }

        func index(atX px: CGFloat) -> Int? {
            guard !read.points.isEmpty else { return nil }
            var best: Int?
            var bestDx = CGFloat.greatestFiniteMagnitude
            for i in read.points.indices {
                let dx = abs(x(i) - px)
                if dx < bestDx { bestDx = dx; best = i }
            }
            return best
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Threshold · HM ±5%") {
    ScrollView {
        VStack(alignment: .leading) {
            TrendsThresholdView(
                read: ThresholdBuilder.build(lab: .preview, settings: .default)
            )
        }
        .padding(24)
    }
    .background(Color.drip.background)
}

/// The same window re-anchored on 10K with the slow edge clamped — the case
/// the controls exist for. A different set of sessions should draw.
#Preview("Threshold · 10K, slow edge tight") {
    ScrollView {
        VStack(alignment: .leading) {
            TrendsThresholdView(
                read: ThresholdBuilder.build(
                    lab: .preview,
                    settings: BandSettings(
                        anchor: .k10,
                        fastPct: 5,
                        slowPct: 2,
                        minTotalMinutes: 6,
                        minBlockMinutes: 4,
                        hrFloor: 160
                    )
                )
            )
        }
        .padding(24)
    }
    .background(Color.drip.background)
}
#endif

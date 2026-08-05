//
//  SignalLabCharts.swift
//  RunningLog · Analysis
//
//  The four charts the Signal Lab draws. Built from `SignalLabPrimitives`.
//
//  All four are `Canvas`, matching the house pattern set by
//  `TrendsSignalLanes` rather than reaching for the Charts framework — the
//  editorial marks (hairline rules, hollow rings, coral stems) are cheaper to
//  draw directly than to talk a chart library out of its defaults.
//
//  Every one takes its data pre-computed from `SignalLabModels` and owns no
//  state beyond its own scrub index. None of them fetches, filters, or carries
//  a time control: the Lab has one window, set once at the top.
//

import SwiftUI

// MARK: - 01 · drift scatter

/// Decoupling readings against a steady band.
struct LabDriftChart: View {
    let read: AerobicDriftRead
    @State private var scrubIndex: Int?

    private let height: CGFloat = 170
    private let gutter: CGFloat = 34

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LabReadout(text: readout)
            GeometryReader { geo in
                Canvas { ctx, size in draw(ctx, size: size) }
                    .contentShape(Rectangle())
                    .gesture(scrubGesture(width: geo.size.width))
            }
            .frame(height: height)
            .padding(.top, 10)

            HStack(spacing: 14) {
                LabLegendChip(color: Color.drip.textPrimary, label: "In the band")
                LabLegendChip(color: Color.drip.coral, label: "Over \(Int(read.bandHi))%")
                Spacer(minLength: 0)
                Text("SHADED = AEROBICALLY STEADY")
                    .font(.dripEyebrow(8.5))
                    .tracking(0.8)
                    .foregroundStyle(Color.drip.textTertiary)
            }
            .padding(.top, 10)
        }
    }

    private var readout: String {
        if let i = scrubIndex, read.points.indices.contains(i) {
            let p = read.points[i]
            let sign = p.pct > 0 ? "+" : ""
            var bits: [String] = []
            if let l = p.label { bits.append(l.uppercased()) }
            bits.append("DRIFT \(sign)\(String(format: "%.1f", p.pct))%")
            if p.pct > read.bandHi { bits.append("OVER THE BAND") }
            return bits.joined(separator: " · ")
        }
        var bits = ["\(read.points.count) READINGS"]
        if let m = read.mean {
            bits.append("MEAN \(m > 0 ? "+" : "")\(String(format: "%.1f", m))%")
        }
        if !read.overBand.isEmpty {
            bits.append("\(read.overBand.count) OVER \(Int(read.bandHi))%")
        }
        return bits.joined(separator: " · ")
    }

    private func scrubGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard abs(value.translation.width) >= abs(value.translation.height) else { return }
                scrubIndex = index(atX: value.location.x, width: width)
            }
            .simultaneously(
                with: SpatialTapGesture().onEnded { value in
                    let i = index(atX: value.location.x, width: width)
                    scrubIndex = (scrubIndex == i) ? nil : i
                }
            )
    }

    private func index(atX px: CGFloat, width: CGFloat) -> Int? {
        let n = read.points.count
        guard n > 0 else { return nil }
        let plot = max(1, width - gutter)
        let t = (px - gutter) / plot
        return min(n - 1, max(0, Int((t * CGFloat(n - 1)).rounded())))
    }

    private func draw(_ ctx: GraphicsContext, size: CGSize) {
        guard !read.points.isEmpty else { return }
        let w = size.width, h = size.height

        let values = read.points.map(\.pct)
        let lo = min(read.bandLo, values.min() ?? 0) - 1
        let hi = max(read.bandHi + 1, values.max() ?? 5) + 1
        let y: (Double) -> CGFloat = { v in
            CGFloat(1 - (v - lo) / max(0.001, hi - lo)) * h
        }
        let x: (Int) -> CGFloat = { i in
            let n = read.points.count
            guard n > 1 else { return gutter + (w - gutter) / 2 }
            return gutter + (w - gutter - 10) * CGFloat(i) / CGFloat(n - 1)
        }

        // Steady band
        let bandRect = CGRect(
            x: gutter, y: y(read.bandHi),
            width: max(0, w - gutter), height: max(0, y(read.bandLo) - y(read.bandHi))
        )
        ctx.fill(Path(bandRect), with: .color(Color.drip.paperDeep.opacity(0.7)))

        for v in [lo + 1, read.bandHi, hi - 1] {
            LabDraw.label(ctx, "\(Int(v.rounded()))%", at: CGPoint(x: gutter - 6, y: y(v)), anchor: .trailing)
        }
        LabDraw.gridline(ctx, y: y(0), from: gutter, to: w)

        if let slope = SignalLabMath.slope(xs: read.points.map { Double($0.index) }, ys: values),
           let first = read.points.first, let last = read.points.last {
            let meanX = Double(read.points.map(\.index).reduce(0, +)) / Double(read.points.count)
            let meanY = values.reduce(0, +) / Double(values.count)
            let at: (Int) -> Double = { i in meanY + slope * (Double(i) - meanX) }
            LabDraw.trend(
                ctx,
                from: CGPoint(x: x(first.index), y: y(at(first.index))),
                to: CGPoint(x: x(last.index), y: y(at(last.index))),
                color: Color.drip.textPrimary
            )
        }

        for (i, p) in read.points.enumerated() {
            LabDraw.dot(
                ctx,
                at: CGPoint(x: x(i), y: y(p.pct)),
                radius: scrubIndex == i ? 6 : 4.5,
                fill: p.pct > read.bandHi ? Color.drip.coral : Color.drip.textPrimary,
                emphasised: scrubIndex == i
            )
        }
    }
}

// MARK: - 03 · two-series efficiency

/// Metres per heartbeat, reps and long efforts as separate series on one axis.
struct LabEfficiencyChart: View {
    let read: BeatEfficiencyRead
    @State private var scrubID: String?

    private let height: CGFloat = 180
    private let gutter: CGFloat = 38
    private let rightPad: CGFloat = 46

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LabReadout(text: readout)
            GeometryReader { geo in
                Canvas { ctx, size in draw(ctx, size: size) }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 12)
                            .onChanged { value in
                                guard abs(value.translation.width) >= abs(value.translation.height)
                                else { return }
                                scrubID = nearest(x: value.location.x, width: geo.size.width)?.id
                            }
                            .onEnded { _ in }
                    )
            }
            .frame(height: height)
            .padding(.top, 10)

            HStack(spacing: 14) {
                LabLegendChip(color: PaceSpectrum.fiveK, label: "Rep sessions")
                LabLegendChip(color: PaceSpectrum.moderate, label: "Long & tempo")
                Spacer(minLength: 0)
                Text("DASHED = FITTED TREND")
                    .font(.dripEyebrow(8.5))
                    .tracking(0.8)
                    .foregroundStyle(Color.drip.textTertiary)
            }
            .padding(.top, 10)
        }
    }

    private var readout: String {
        if let id = scrubID, let p = read.all.first(where: { $0.id == id }) {
            return [
                p.dateLabel.uppercased(),
                String(format: "%.2f M/BEAT", p.metresPerBeat),
                "\(p.hr) BPM",
                TrendsFormat.pace(p.paceSec),
            ].joined(separator: " · ")
        }
        var bits: [String] = []
        if let r = read.repsMean { bits.append("REPS \(String(format: "%.2f", r))") }
        if let l = read.longsMean { bits.append("LONG \(String(format: "%.2f", l))") }
        bits.append("\(read.all.count) SESSIONS")
        return bits.joined(separator: " · ")
    }

    private func nearest(x px: CGFloat, width: CGFloat) -> BeatEfficiencyPoint? {
        let pts = read.all
        guard !pts.isEmpty else { return nil }
        let xs = pts.map { xFor($0, width: width) }
        var best = 0
        var bestDx = CGFloat.greatestFiniteMagnitude
        for (i, v) in xs.enumerated() where abs(v - px) < bestDx {
            bestDx = abs(v - px); best = i
        }
        return pts[best]
    }

    private var domain: (lo: Double, hi: Double) {
        let days = read.all.map { SignalLabMath.dayNumber($0.date) }
        return (days.min() ?? 0, days.max() ?? 1)
    }

    private func xFor(_ p: BeatEfficiencyPoint, width: CGFloat) -> CGFloat {
        let d = domain
        let span = max(0.001, d.hi - d.lo)
        let t = (SignalLabMath.dayNumber(p.date) - d.lo) / span
        return gutter + (width - gutter - rightPad) * CGFloat(t)
    }

    private func draw(_ ctx: GraphicsContext, size: CGSize) {
        let pts = read.all
        guard !pts.isEmpty else { return }
        let w = size.width, h = size.height

        let values = pts.map(\.metresPerBeat)
        let lo = (values.min() ?? 1.4) - 0.06
        let hi = (values.max() ?? 1.9) + 0.06
        let y: (Double) -> CGFloat = { v in CGFloat(1 - (v - lo) / max(0.001, hi - lo)) * h }

        for v in stride(from: (lo * 20).rounded() / 20, through: hi, by: 0.10) {
            guard v >= lo else { continue }
            LabDraw.gridline(ctx, y: y(v), from: gutter, to: w - rightPad)
            LabDraw.label(ctx, String(format: "%.2f", v), at: CGPoint(x: gutter - 6, y: y(v)), anchor: .trailing)
        }

        let series: [(pts: [BeatEfficiencyPoint], color: Color, name: String)] = [
            (read.reps, PaceSpectrum.fiveK, "REPS"),
            (read.longs, PaceSpectrum.moderate, "LONG"),
        ]

        for s in series where !s.pts.isEmpty {
            let xs = s.pts.map { SignalLabMath.dayNumber($0.date) }
            let ys = s.pts.map(\.metresPerBeat)
            if let slope = SignalLabMath.slope(xs: xs, ys: ys) {
                let mx = xs.reduce(0, +) / Double(xs.count)
                let my = ys.reduce(0, +) / Double(ys.count)
                let d = domain
                LabDraw.trend(
                    ctx,
                    from: CGPoint(x: gutter, y: y(my + slope * (d.lo - mx))),
                    to: CGPoint(x: w - rightPad, y: y(my + slope * (d.hi - mx))),
                    color: s.color
                )
            }
            for p in s.pts {
                LabDraw.dot(
                    ctx,
                    at: CGPoint(x: xFor(p, width: w), y: y(p.metresPerBeat)),
                    radius: scrubID == p.id ? 6 : 4.5,
                    fill: s.color,
                    emphasised: scrubID == p.id
                )
            }
            // Direct label at the series end — identity never rests on the
            // legend alone.
            if let last = s.pts.last {
                ctx.draw(
                    Text("\(s.name) \(String(format: "%.2f", last.metresPerBeat))")
                        .font(.dripEyebrow(8.5))
                        .foregroundStyle(s.color),
                    at: CGPoint(x: xFor(last, width: w) + 8, y: y(last.metresPerBeat)),
                    anchor: .leading
                )
            }
        }

        if let first = pts.first, let last = pts.last {
            LabDraw.label(ctx, first.dateLabel.uppercased(), at: CGPoint(x: gutter, y: h - 2), anchor: .bottomLeading)
            if pts.count > 1 {
                LabDraw.label(ctx, last.dateLabel.uppercased(), at: CGPoint(x: w - rightPad, y: h - 2), anchor: .bottomTrailing)
            }
        }
    }
}

// MARK: - 04 · mood against load

/// One row per mood label: mean load as a bar, with volume and day count
/// beside it. A bar chart rather than a scatter on purpose — mood is a label,
/// not a magnitude, so it gets categories and never an axis.
struct LabMoodLoadChart: View {
    let read: MoodLoadRead

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(read.groups) { group in
                row(group)
                if group.id != read.groups.last?.id { Hairline() }
            }
        }
    }

    private var maxLoad: Double {
        max(0.001, read.groups.map(\.meanLoad).max() ?? 1)
    }

    private func row(_ group: MoodLoadGroup) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(group.id.uppercased())
                .font(.dripEyebrow(9))
                .tracking(1.0)
                .foregroundStyle(Color.drip.textSecondary)
                .frame(width: 76, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.drip.paperDeep)
                        .frame(height: 10)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(TrendsMoodColor.color(group.id))
                        .frame(
                            width: max(4, geo.size.width * CGFloat(group.meanLoad / maxLoad)),
                            height: 10
                        )
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 20)

            Text(String(format: "%.0f", group.meanLoad))
                .font(.dripStat(12))
                .monospacedDigit()
                .foregroundStyle(Color.drip.textPrimary)
                .frame(width: 34, alignment: .trailing)

            Text("\(group.dayCount)d")
                .font(.dripEyebrow(9))
                .foregroundStyle(Color.drip.textTertiary)
                .frame(width: 28, alignment: .trailing)
        }
        .padding(.vertical, 9)
    }
}

// MARK: - 05 · heat dumbbells

/// Raw pace and the same run heat-neutral, paired. The gap is the charge.
struct LabHeatChart: View {
    let read: HeatImpactRead
    @State private var scrubIndex: Int?

    private let height: CGFloat = 180
    private let gutter: CGFloat = 38

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LabReadout(text: readout)
            GeometryReader { geo in
                Canvas { ctx, size in draw(ctx, size: size) }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 12)
                            .onChanged { value in
                                guard abs(value.translation.width) >= abs(value.translation.height)
                                else { return }
                                scrubIndex = index(atX: value.location.x, width: geo.size.width)
                            }
                    )
            }
            .frame(height: height)
            .padding(.top, 10)

            HStack(spacing: 14) {
                LabLegendChip(color: Color.drip.coral, label: "Raw · what the watch said")
                LabLegendChip(color: PaceSpectrum.lt, label: "Heat-neutral · same run")
            }
            .padding(.top, 10)
        }
    }

    private var readout: String {
        if let i = scrubIndex, read.points.indices.contains(i) {
            let p = read.points[i]
            var bits = [
                p.dateLabel.uppercased(),
                "RAW \(TrendsFormat.pace(p.rawSec))",
                "NEUTRAL \(TrendsFormat.pace(p.adjSec))",
                "\(p.penaltySec) S/MI",
            ]
            if let dew = p.dewPointF { bits.append("DEW \(dew)°") }
            return bits.joined(separator: " · ")
        }
        var bits = ["\(read.points.count) SESSIONS CORRECTED"]
        if let m = read.meanPenalty { bits.append("MEAN \(m) S/MI") }
        if let w = read.worst { bits.append("WORST \(w.penaltySec) ON \(w.dateLabel.uppercased())") }
        return bits.joined(separator: " · ")
    }

    private func index(atX px: CGFloat, width: CGFloat) -> Int? {
        let n = read.points.count
        guard n > 0 else { return nil }
        let plot = max(1, width - gutter - 10)
        let t = (px - gutter) / plot
        return min(n - 1, max(0, Int((t * CGFloat(n - 1)).rounded())))
    }

    private func draw(_ ctx: GraphicsContext, size: CGSize) {
        guard !read.points.isEmpty else { return }
        let w = size.width, h = size.height

        let paces = read.points.flatMap { [Double($0.rawSec), Double($0.adjSec)] }
        let fast = (paces.min() ?? 280) - 12
        let slow = (paces.max() ?? 420) + 12
        let y: (Int) -> CGFloat = { sec in
            CGFloat((Double(sec) - fast) / max(1, slow - fast)) * (h - 16)
        }
        let x: (Int) -> CGFloat = { i in
            let n = read.points.count
            guard n > 1 else { return gutter + (w - gutter) / 2 }
            return gutter + (w - gutter - 10) * CGFloat(i) / CGFloat(n - 1)
        }

        for sec in stride(from: Int(fast / 30) * 30 + 30, to: Int(slow), by: 30) {
            LabDraw.gridline(ctx, y: y(sec), from: gutter, to: w)
            LabDraw.label(ctx, TrendsFormat.pace(sec), at: CGPoint(x: gutter - 6, y: y(sec)), anchor: .trailing)
        }

        for (i, p) in read.points.enumerated() {
            let px = x(i)
            let on = scrubIndex == i
            var stem = Path()
            stem.move(to: CGPoint(x: px, y: y(p.rawSec)))
            stem.addLine(to: CGPoint(x: px, y: y(p.adjSec)))
            ctx.stroke(
                stem,
                with: .color(on ? Color.drip.textSecondary : Color.drip.divider),
                lineWidth: on ? 1.8 : 1.3
            )
            LabDraw.dot(ctx, at: CGPoint(x: px, y: y(p.rawSec)), radius: on ? 5 : 3.6,
                        fill: Color.drip.coral, emphasised: on)
            LabDraw.dot(ctx, at: CGPoint(x: px, y: y(p.adjSec)), radius: on ? 5 : 3.6,
                        fill: PaceSpectrum.lt, emphasised: on)
        }

        if let first = read.points.first, let last = read.points.last {
            LabDraw.label(ctx, first.dateLabel.uppercased(), at: CGPoint(x: gutter, y: h - 2), anchor: .bottomLeading)
            if read.points.count > 1 {
                LabDraw.label(ctx, last.dateLabel.uppercased(), at: CGPoint(x: w, y: h - 2), anchor: .bottomTrailing)
            }
        }
    }
}

//
//  UnifiedTelemetryCard.swift
//  RunningLog
//
//  Plate 23 · "Pace, narrated" — the unified telemetry chart.
//
//  Replaces the five stacked panels (HR / pace / cadence / elevation /
//  HR-recovery) with ONE shared-axis chart. Per the May-2026 redesign:
//
//    1. One chart — all metrics share a single distance axis.
//    2. Toggleable layers — design-system chips turn each metric on/off.
//       Default: Heart rate + Pace. Cadence + Elevation start off.
//    3. Reps + splits on the chart — per-mile split ticks along the base
//       always; coral rep bands when `repRangesMiles` is supplied (lap
//       data isn't in the stream model yet — see note below).
//    4. Expandable — tap EXPAND for a fullscreen landscape view; drag
//       anywhere to scrub a crosshair + floating value tooltip.
//
//  Colors follow Post Run Drip exactly: HR = coral, Pace = navy
//  (Color.drip.paceFast), Cadence = warm gray, Elevation = sage
//  (Color.drip.positive). No SF Symbols, no emoji (hard rule #8 / the
//  design-system no-icon posture). The "lead" metric (first active in
//  priority order HR → Pace → Cadence → Elevation) owns the left y-axis
//  labels; other layers are read via the scrub tooltip.
//
//  Data inputs mirror the old PaceChartCard so the call site swap is a
//  one-for-one. Smoothing / GAP-free point computation is adapted from
//  PaceChartCard.computeChartPoints.
//
//  REPS NOTE: `external_streams` carries no lap/interval boundaries, so
//  `repRangesMiles` is empty in the current wiring. When lap data lands,
//  pass mile ranges (e.g. [1.05...1.55, ...]) and the bands + R# labels
//  render automatically.
//

import SwiftUI

// MARK: - Metric

enum TelemetryMetric: String, CaseIterable, Identifiable {
    case heartRate, pace, cadence, elevation
    var id: String { rawValue }

    /// Priority for which metric owns the y-axis when several are active.
    static let priority: [TelemetryMetric] = [.heartRate, .pace, .cadence, .elevation]

    var label: String {
        switch self {
        case .heartRate: return "Heart rate"
        case .pace:      return "Pace"
        case .cadence:   return "Cadence"
        case .elevation: return "Elevation"
        }
    }

    /// Short key for the tooltip rows.
    var shortLabel: String {
        switch self {
        case .heartRate: return "HR"
        case .pace:      return "Pace"
        case .cadence:   return "Cad"
        case .elevation: return "Elev"
        }
    }

    var unit: String {
        switch self {
        case .heartRate: return "bpm"
        case .pace:      return "/mi"
        case .cadence:   return "spm"
        case .elevation: return "ft"
        }
    }

    var color: Color {
        switch self {
        case .heartRate: return Color.drip.coral
        case .pace:      return Color.drip.paceFast    // navy (fast end of pace ramp)
        case .cadence:   return Color.drip.textSecondary
        case .elevation: return Color.drip.positive    // sage
        }
    }

    /// Pace reads "faster is up", so its axis is inverted (low minutes at top).
    var inverted: Bool { self == .pace }
}

// MARK: - Point

struct TelemetryPoint {
    let distanceMiles: Double
    let timeSec: Double
    let pace: Double        // min/mi
    let heartrate: Double?  // bpm
    let cadence: Double?    // spm (raw stream value)
    let elevationFt: Double? // feet
}

// MARK: - Unified card

struct UnifiedTelemetryCard: View {
    let velocities: [Double]
    let distances: [Double]
    let times: [Int]
    let heartrates: [Int]?
    var altitudes: [Double]? = nil
    var cadences: [Double]? = nil
    /// Mile ranges for interval reps. Empty until lap data exists.
    var repRangesMiles: [ClosedRange<Double>] = []

    private let points: [TelemetryPoint]

    @State private var active: Set<TelemetryMetric> = [.heartRate, .pace]
    @State private var scrub: Double? = nil           // fraction 0…1
    @State private var showFull = false

    init(velocities: [Double], distances: [Double], times: [Int],
         heartrates: [Int]? = nil, altitudes: [Double]? = nil,
         cadences: [Double]? = nil, repRangesMiles: [ClosedRange<Double>] = []) {
        self.velocities = velocities
        self.distances = distances
        self.times = times
        self.heartrates = heartrates
        self.altitudes = altitudes
        self.cadences = cadences
        self.repRangesMiles = repRangesMiles
        self.points = TelemetryMath.computePoints(
            velocities: velocities, distances: distances, times: times,
            heartrates: heartrates, altitudes: altitudes, cadences: cadences)
    }

    /// Which metrics actually have data — chips for the rest render disabled.
    private var availability: [TelemetryMetric: Bool] {
        [
            .heartRate: points.contains { $0.heartrate != nil },
            .pace: true,
            .cadence: points.contains { $0.cadence != nil },
            .elevation: points.contains { $0.elevationFt != nil },
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            TelemetryChips(active: $active, availability: availability)
            TelemetryChartCanvas(points: points, active: active,
                                 repRangesMiles: repRangesMiles,
                                 scrub: $scrub, height: 220)
            TelemetryReadout(points: points, active: active, scrub: scrub)
            Text(scrub == nil
                 ? "SESSION AVERAGES · PRESS & DRAG FOR LIVE VALUES"
                 : "LIVE · DRAG TO MOVE")
                .font(.dripEyebrow(9))
                .tracking(0.5)
                .foregroundStyle(Color.drip.textTertiary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(16)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.drip.divider, lineWidth: 1))
        .fullScreenCover(isPresented: $showFull) {
            TelemetryFullScreen(points: points, active: $active,
                                repRangesMiles: repRangesMiles)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("THE EFFORT")
                .font(.dripEyebrow(10))
                .tracking(1.0)
                .foregroundStyle(Color.drip.textSecondary)
            Spacer()
            Button {
                showFull = true
            } label: {
                Text("EXPAND")
                    .font(.dripEyebrow(9))
                    .tracking(1.0)
                    .foregroundStyle(Color.drip.coral)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .overlay(Capsule().stroke(Color.drip.coral.opacity(0.5), lineWidth: 1))
            }
        }
    }
}

// MARK: - Chips

struct TelemetryChips: View {
    @Binding var active: Set<TelemetryMetric>
    let availability: [TelemetryMetric: Bool]

    var body: some View {
        HStack(spacing: 7) {
            ForEach(TelemetryMetric.allCases) { metric in
                let on = active.contains(metric)
                let avail = availability[metric] ?? true
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        if on { active.remove(metric) } else { active.insert(metric) }
                    }
                } label: {
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(metric.color)
                            .frame(width: 9, height: 9)
                            .opacity(on ? 1 : 0.35)
                        Text(metric.label.uppercased())
                            .font(.dripEyebrow(10))
                            .tracking(0.6)
                            .foregroundStyle(on ? Color.drip.textPrimary : Color.drip.textTertiary)
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(on ? Color.drip.cardBackgroundElevated : Color.drip.cardBackground)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(on ? metric.color : Color.drip.divider, lineWidth: 1))
                    .opacity(avail ? 1 : 0.35)
                }
                .disabled(!avail)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Chart canvas

struct TelemetryChartCanvas: View {
    let points: [TelemetryPoint]
    let active: Set<TelemetryMetric>
    let repRangesMiles: [ClosedRange<Double>]
    @Binding var scrub: Double?
    var height: CGFloat = 220

    private let pad = EdgeInsets(top: 16, leading: 38, bottom: 26, trailing: 12)

    var body: some View {
        GeometryReader { geo in
            let rect = plotRect(in: geo.size)
            ZStack(alignment: .topLeading) {
                Canvas { ctx, _ in
                    draw(ctx: ctx, rect: rect)
                }
                if let s = scrub, let idx = indexFor(fraction: s) {
                    tooltip(at: s, point: points[idx], rect: rect, canvasWidth: geo.size.width)
                }
            }
            .contentShape(Rectangle())
            // Long-press-then-drag so a plain vertical swipe still scrolls
            // the page (matches the old PaceChartCard touch pattern); a
            // press-and-hold begins scrubbing.
            .gesture(
                LongPressGesture(minimumDuration: 0.12)
                    .sequenced(before: DragGesture(minimumDistance: 0))
                    .onChanged { value in
                        switch value {
                        case .second(true, let drag):
                            if let drag = drag {
                                let f = (drag.location.x - rect.minX) / max(rect.width, 1)
                                scrub = min(max(Double(f), 0), 1)
                            }
                        default:
                            break
                        }
                    }
                    .onEnded { _ in scrub = nil }
            )
        }
        .frame(height: height)
    }

    // MARK: layout

    private func plotRect(in size: CGSize) -> CGRect {
        CGRect(x: pad.leading, y: pad.top,
               width: max(size.width - pad.leading - pad.trailing, 1),
               height: max(size.height - pad.top - pad.bottom, 1))
    }

    private var maxDist: Double { points.last?.distanceMiles ?? 1 }

    private func xFor(_ miles: Double, _ rect: CGRect) -> CGFloat {
        rect.minX + CGFloat(maxDist > 0 ? miles / maxDist : 0) * rect.width
    }

    private func yFor(_ value: Double, _ metric: TelemetryMetric, _ rect: CGRect) -> CGFloat {
        let r = TelemetryMath.range(for: metric, points: points)
        var t = (value - r.lo) / max(r.hi - r.lo, 0.0001)
        if metric.inverted { t = 1 - t }
        return rect.maxY - CGFloat(t) * rect.height
    }

    private func indexFor(fraction: Double) -> Int? {
        guard !points.isEmpty else { return nil }
        return min(max(Int((fraction * Double(points.count - 1)).rounded()), 0), points.count - 1)
    }

    private var leadMetric: TelemetryMetric? {
        TelemetryMetric.priority.first { active.contains($0) }
    }

    // MARK: drawing

    private func draw(ctx: GraphicsContext, rect: CGRect) {
        let lead = leadMetric

        // gridlines + lead-metric y labels
        let ticks: [Double] = [0, 0.25, 0.5, 0.75, 1]
        for t in ticks {
            let y = rect.maxY - CGFloat(t) * rect.height
            var line = Path()
            line.move(to: CGPoint(x: rect.minX, y: y))
            line.addLine(to: CGPoint(x: rect.maxX, y: y))
            ctx.stroke(line, with: .color(Color.drip.divider.opacity(t == 0 ? 1 : 0.55)), lineWidth: 1)

            if let lead {
                let r = TelemetryMath.range(for: lead, points: points)
                let value = lead.inverted ? r.hi - t * (r.hi - r.lo) : r.lo + t * (r.hi - r.lo)
                let text = Text(TelemetryMath.format(value, lead))
                    .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                    .foregroundColor(lead.color.opacity(0.85))
                ctx.draw(ctx.resolve(text), at: CGPoint(x: rect.minX - 6, y: y), anchor: .trailing)
            }
        }
        // lead unit caption (top-left, horizontal — no rotation)
        if let lead {
            let cap = Text("\(lead.shortLabel.uppercased()) · \(lead.unit)")
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundColor(lead.color.opacity(0.7))
            ctx.draw(ctx.resolve(cap), at: CGPoint(x: rect.minX, y: rect.minY - 8), anchor: .leading)
        }

        // rep bands
        for (i, range) in repRangesMiles.enumerated() {
            let x0 = xFor(range.lowerBound, rect)
            let x1 = xFor(range.upperBound, rect)
            let band = Path(CGRect(x: x0, y: rect.minY, width: max(x1 - x0, 0), height: rect.height))
            ctx.fill(band, with: .color(Color.drip.coral.opacity(0.09)))
            if x1 - x0 > 14 {
                let lab = Text("R\(i + 1)")
                    .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                    .foregroundColor(Color.drip.coral.opacity(0.8))
                ctx.draw(ctx.resolve(lab), at: CGPoint(x: (x0 + x1) / 2, y: rect.minY + 6), anchor: .center)
            }
        }

        // mile split ticks + labels along base
        let miles = Int(maxDist)
        if miles >= 1 {
            for m in 1...miles {
                let x = xFor(Double(m), rect)
                var tick = Path()
                tick.move(to: CGPoint(x: x, y: rect.maxY))
                tick.addLine(to: CGPoint(x: x, y: rect.maxY + 4))
                ctx.stroke(tick, with: .color(Color.drip.textTertiary), lineWidth: 1)
                let lab = Text("\(m)mi")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundColor(Color.drip.textTertiary)
                ctx.draw(ctx.resolve(lab), at: CGPoint(x: x, y: rect.maxY + 13), anchor: .center)
            }
        }

        // metric layers — draw non-lead first, lead last (on top)
        let order: [TelemetryMetric] = [.elevation, .cadence, .pace, .heartRate]
        for metric in order where active.contains(metric) {
            guard let pts = linePoints(for: metric, rect: rect), pts.count > 1 else { continue }
            // elevation fill
            if metric == .elevation {
                var fill = TelemetryMath.smoothPath(pts)
                fill.addLine(to: CGPoint(x: pts.last!.x, y: rect.maxY))
                fill.addLine(to: CGPoint(x: pts.first!.x, y: rect.maxY))
                fill.closeSubpath()
                ctx.fill(fill, with: .color(Color.drip.positive.opacity(0.12)))
            }
            let path = TelemetryMath.smoothPath(pts)
            let isLead = metric == leadMetric
            ctx.stroke(path, with: .color(metric.color.opacity(isLead || metric == .heartRate || metric == .pace ? 1 : 0.78)),
                       style: StrokeStyle(lineWidth: isLead ? 2.4 : 1.6, lineCap: .round, lineJoin: .round))
        }

        // scrub crosshair + dots
        if let s = scrub, let idx = indexFor(fraction: s) {
            let x = xFor(points[idx].distanceMiles, rect)
            var v = Path()
            v.move(to: CGPoint(x: x, y: rect.minY))
            v.addLine(to: CGPoint(x: x, y: rect.maxY))
            ctx.stroke(v, with: .color(Color.drip.textPrimary.opacity(0.3)),
                       style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            for metric in order where active.contains(metric) {
                guard let value = value(points[idx], metric) else { continue }
                let y = yFor(value, metric, rect)
                let dot = Path(ellipseIn: CGRect(x: x - 3.8, y: y - 3.8, width: 7.6, height: 7.6))
                ctx.fill(dot, with: .color(metric.color))
                ctx.stroke(dot, with: .color(Color.drip.cardBackground), lineWidth: 1.8)
            }
        }
    }

    private func linePoints(for metric: TelemetryMetric, rect: CGRect) -> [CGPoint]? {
        var out: [CGPoint] = []
        for p in points {
            guard let value = value(p, metric) else { continue }
            out.append(CGPoint(x: xFor(p.distanceMiles, rect), y: yFor(value, metric, rect)))
        }
        return out.isEmpty ? nil : out
    }

    private func value(_ p: TelemetryPoint, _ metric: TelemetryMetric) -> Double? {
        switch metric {
        case .heartRate: return p.heartrate
        case .pace:      return p.pace
        case .cadence:   return p.cadence
        case .elevation: return p.elevationFt
        }
    }

    // MARK: tooltip

    private func tooltip(at fraction: Double, point: TelemetryPoint, rect: CGRect, canvasWidth: CGFloat) -> some View {
        let x = xFor(point.distanceMiles, rect)
        return VStack(alignment: .leading, spacing: 4) {
            Text("\(String(format: "%.2f", point.distanceMiles)) mi · \(TelemetryMath.clock(point.timeSec))")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.8))
            ForEach(TelemetryMetric.priority.filter { active.contains($0) }) { metric in
                if let value = value(point, metric) {
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 2).fill(metric.color).frame(width: 7, height: 7)
                        Text(metric.shortLabel.uppercased())
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.6))
                        Spacer(minLength: 8)
                        Text(TelemetryMath.format(value, metric))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white)
                    }
                }
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(minWidth: 104, alignment: .leading)
        .background(Color(red: 26/255, green: 24/255, blue: 21/255).opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .position(x: min(max(x + 60, rect.minX + 56), canvasWidth - 56), y: rect.minY + 34)
        .allowsHitTesting(false)
    }
}

// MARK: - Readout (session averages)

struct TelemetryReadout: View {
    let points: [TelemetryPoint]
    let active: Set<TelemetryMetric>
    let scrub: Double?

    var body: some View {
        HStack(spacing: 0) {
            cell(.heartRate, value: TelemetryMath.avgHR(points), unit: "bpm avg")
            divider
            cell(.pace, value: TelemetryMath.avgPace(points), unit: "/mi avg")
            divider
            cell(.cadence, value: TelemetryMath.avgCadence(points), unit: "spm avg")
            divider
            cell(.elevation, value: TelemetryMath.elevGain(points), unit: "ft gain")
        }
    }

    private var divider: some View {
        Rectangle().fill(Color.drip.divider).frame(width: 1, height: 30)
    }

    private func cell(_ metric: TelemetryMetric, value: String, unit: String) -> some View {
        let on = active.contains(metric)
        return VStack(spacing: 2) {
            Text(metric.shortLabel.uppercased())
                .font(.dripEyebrow(8.5)).tracking(0.8)
                .foregroundStyle(Color.drip.textTertiary)
            Text(value)
                .font(.dripStat(16))
                .foregroundStyle(on ? metric.color : Color.drip.textTertiary)
                .monospacedDigit()
            Text(unit)
                .font(.system(size: 8.5, design: .monospaced))
                .foregroundStyle(Color.drip.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .opacity(on ? 1 : 0.4)
    }
}

// MARK: - Fullscreen

struct TelemetryFullScreen: View {
    let points: [TelemetryPoint]
    @Binding var active: Set<TelemetryMetric>
    let repRangesMiles: [ClosedRange<Double>]
    @Environment(\.dismiss) private var dismiss
    @State private var scrub: Double? = nil

    private var availability: [TelemetryMetric: Bool] {
        [
            .heartRate: points.contains { $0.heartrate != nil },
            .pace: true,
            .cadence: points.contains { $0.cadence != nil },
            .elevation: points.contains { $0.elevationFt != nil },
        ]
    }

    var body: some View {
        ZStack {
            Color.drip.background.ignoresSafeArea()
            GeometryReader { geo in
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("The Effort")
                            .font(.dripDisplay(24))
                            .foregroundStyle(Color.drip.textPrimary)
                        Spacer()
                        Button { dismiss() } label: {
                            Text("CLOSE")
                                .font(.dripEyebrow(11)).tracking(1.0)
                                .foregroundStyle(Color.drip.coral)
                                .padding(.horizontal, 14).padding(.vertical, 7)
                                .overlay(Capsule().stroke(Color.drip.coral, lineWidth: 1))
                        }
                    }
                    TelemetryChips(active: $active, availability: availability)
                    // Fill the screen: the chart takes all vertical space left
                    // after the header, chips, readout and hint — far taller and
                    // easier to read than the old fixed 320pt (which left half the
                    // screen empty). Floored so it never collapses.
                    TelemetryChartCanvas(points: points, active: active,
                                         repRangesMiles: repRangesMiles,
                                         scrub: $scrub,
                                         height: max(geo.size.height - 210, 340))
                    TelemetryReadout(points: points, active: active, scrub: scrub)
                    Text("PRESS & DRAG TO SCRUB · TAP CLOSE TO RETURN")
                        .font(.dripEyebrow(9)).tracking(0.6)
                        .foregroundStyle(Color.drip.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding(20)
            }
        }
    }
}

// MARK: - Math helpers

enum TelemetryMath {
    private static let mileInMeters = 1609.34

    /// Smoothed, sampled points adapted from PaceChartCard.computeChartPoints.
    static func computePoints(velocities: [Double], distances: [Double], times: [Int],
                              heartrates: [Int]?, altitudes: [Double]?, cadences: [Double]?) -> [TelemetryPoint] {
        guard velocities.count >= 10, distances.count == velocities.count else { return [] }
        let window = 30
        let step = max(1, velocities.count / 400)
        let hasHR = heartrates != nil && heartrates!.count == velocities.count
        let hasAlt = altitudes != nil && altitudes!.count == velocities.count
        let hasCad = cadences != nil && cadences!.count == velocities.count
        let t0 = times.first ?? 0

        var out: [TelemetryPoint] = []
        for i in stride(from: 0, to: velocities.count, by: step) {
            let lo = max(0, i - window / 2)
            let hi = min(velocities.count - 1, i + window / 2)
            let velSlice = velocities[lo...hi]
            let avgVel = velSlice.reduce(0, +) / Double(velSlice.count)
            let pace = avgVel > 0.5 ? (mileInMeters / avgVel) / 60.0 : 0
            guard pace > 0, pace < 20 else { continue }
            let dist = distances[i] / mileInMeters
            let timeSec = i < times.count ? Double(times[i] - t0) : 0

            var hr: Double? = nil
            if hasHR {
                let slice = heartrates![lo...hi]
                hr = Double(slice.reduce(0, +)) / Double(slice.count)
            }
            var cad: Double? = nil
            if hasCad {
                let slice = cadences![lo...hi]
                cad = slice.reduce(0, +) / Double(slice.count)
            }
            var elevFt: Double? = nil
            if hasAlt { elevFt = altitudes![i] * 3.28084 }

            out.append(TelemetryPoint(distanceMiles: dist, timeSec: timeSec, pace: pace,
                                      heartrate: hr, cadence: cad, elevationFt: elevFt))
        }
        return out
    }

    /// Per-metric value range with editorial padding.
    static func range(for metric: TelemetryMetric, points: [TelemetryPoint]) -> (lo: Double, hi: Double) {
        let vals: [Double]
        switch metric {
        case .heartRate: vals = points.compactMap { $0.heartrate }
        case .pace:      vals = points.map { $0.pace }
        case .cadence:   vals = points.compactMap { $0.cadence }
        case .elevation: vals = points.compactMap { $0.elevationFt }
        }
        guard let mn = vals.min(), let mx = vals.max() else { return (0, 1) }
        switch metric {
        case .heartRate: return (mn - 4, mx + 4)
        case .pace:      return (max(mn - 0.3, 2), mx + 0.3)
        case .cadence:   return (mn - 6, mx + 6)
        case .elevation: return (mn - 10, mx + 20)
        }
    }

    static func smoothPath(_ pts: [CGPoint]) -> Path {
        var path = Path()
        guard pts.count > 1 else { return path }
        path.move(to: pts[0])
        for i in 1..<(pts.count - 1) {
            let mid = CGPoint(x: (pts[i].x + pts[i + 1].x) / 2, y: (pts[i].y + pts[i + 1].y) / 2)
            path.addQuadCurve(to: mid, control: pts[i])
        }
        path.addLine(to: pts[pts.count - 1])
        return path
    }

    // formatting
    static func format(_ value: Double, _ metric: TelemetryMetric) -> String {
        switch metric {
        case .heartRate: return "\(Int(value.rounded()))"
        case .pace:      return PaceCalculator.formatPaceFromMinutes(value)
        case .cadence:   return "\(Int(value.rounded()))"
        case .elevation: return "\(Int(value.rounded()))"
        }
    }

    static func clock(_ sec: Double) -> String {
        let s = Int(sec.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    static func avgHR(_ p: [TelemetryPoint]) -> String {
        let v = p.compactMap { $0.heartrate }
        guard !v.isEmpty else { return "—" }
        return "\(Int((v.reduce(0, +) / Double(v.count)).rounded()))"
    }
    static func avgPace(_ p: [TelemetryPoint]) -> String {
        let v = p.map { $0.pace }
        guard !v.isEmpty else { return "—" }
        return PaceCalculator.formatPaceFromMinutes(v.reduce(0, +) / Double(v.count))
    }
    static func avgCadence(_ p: [TelemetryPoint]) -> String {
        let v = p.compactMap { $0.cadence }
        guard !v.isEmpty else { return "—" }
        return "\(Int((v.reduce(0, +) / Double(v.count)).rounded()))"
    }
    static func elevGain(_ p: [TelemetryPoint]) -> String {
        let v = p.compactMap { $0.elevationFt }
        guard let mn = v.min(), let mx = v.max() else { return "—" }
        return "+\(Int((mx - mn).rounded()))"
    }
}

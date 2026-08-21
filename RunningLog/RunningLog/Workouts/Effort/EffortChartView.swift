//
//  EffortChartView.swift
//  RunningLog
//
//  "The Effort" — portrait 3a. One tall pace chart where each rep's pace + HR
//  are set vertically inside its band, so the chart IS the session structure and
//  no separate rep list is needed (design handoff §3a).
//
//  House style: GeometryReader + Path, no Canvas, no chart dependency — matches
//  RRTelemetryPanel. The scale/series math lives in the SwiftUI-free engine
//  (EffortSeries / EffortChartScale); this file only maps engine output to
//  points and draws. The derived render data (resampled points, resolved scale,
//  ticks, mile marks, rep stats) is computed ONCE per (width, window, metric,
//  smoothing) in `.task(id:)`, never inside `body` — the same lesson
//  RRTelemetryPanel records about scanning the full stream on every redraw.
//

import SwiftUI

// MARK: - Portrait 3a chart

struct EffortPortraitChart: View {
    let samples: [EffortSample]
    let segments: [EffortSegment]
    let targetPaceSecPerMile: Double
    let distanceLabel: String     // "14.4 MI"
    let durationLabel: String     // "98:50"
    var figure: String = "FIG. 31"
    var metric: EffortMetric = .pace
    var plotHeight: CGFloat = 250
    /// The athlete's real pace zones, so the fill's blues are anchored to the
    /// same pace spectrum used everywhere else in the app (a given pace → the
    /// same blue). Nil falls back to a chart-relative ramp.
    var paceZones: PaceZonesEngine? = nil
    /// The athlete's real HR zones (`rr_zones`), drawn as bands behind the HR
    /// trace only. Empty = no bands.
    var hrZones: [RRZone] = []
    /// Recorded lap boundary times (seconds from start). Drawn as vertical
    /// markers when `showLaps` is on.
    var lapMarks: [TimeInterval] = []
    var showLaps: Bool = false
    /// Authoritative elevation GAIN (ft) from the workout — the number that
    /// matters for a run, not average altitude above sea level.
    var elevationGainFt: Int? = nil
    /// When false, the plate strip and footer are suppressed so several of these
    /// can stack under one header/footer (see EffortDetailCharts).
    var showChrome: Bool = true
    /// A shared scrub time. When bound (landscape comparison), dragging any panel
    /// moves the crosshair on ALL of them; nil keeps scrub local to this chart.
    var sharedScrubT: Binding<TimeInterval?>? = nil
    /// Compact panel: trims the top gutter and hides the scale note so several
    /// panels stack in a landscape height.
    var compact: Bool = false
    /// Draw the mile x-axis. In a stack, only the bottom panel shows it.
    var showXAxis: Bool = true
    var onExpand: (() -> Void)? = nil

    /// The active scrub time — shared when bound, else this chart's own.
    private var activeScrubT: TimeInterval? { sharedScrubT?.wrappedValue ?? scrubT }

    // Plot gutters (3a; trimmed in compact / axis-less panels).
    private var padL: CGFloat { 46 }
    private var padR: CGFloat { 24 }
    private var padT: CGFloat { compact ? 10 : 24 }
    private var padB: CGFloat { showXAxis ? (compact ? 22 : 28) : 8 }

    @State private var plotWidth: CGFloat = 0
    @State private var render: EffortRender?
    @State private var selectedRep: String?
    @State private var scrubT: TimeInterval?

    private var window: ClosedRange<TimeInterval> {
        let lo = samples.first?.t ?? 0
        let hi = samples.last?.t ?? max(lo + 1, 1)
        return lo...max(hi, lo + 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showChrome { plateStrip }
            statsRow
            if metric == .pace && !compact { scaleNote }   // honesty line, pace only
            plotBlock
            if showChrome { footer }
        }
    }

    // MARK: Plate strip

    private var plateStrip: some View {
        HStack {
            Text("THE EFFORT · \(distanceLabel) · \(durationLabel)")
            Spacer()
            Text(figure)
        }
        .font(.system(size: 8.5, weight: .medium, design: .monospaced))
        .tracking(1.4)
        .foregroundStyle(Color.drip.textSecondary)
        .padding(.bottom, 10)
        .overlay(Rectangle().fill(Color.drip.divider).frame(height: 1), alignment: .bottom)
    }

    // MARK: Stats row

    private var statsRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(metric.axisCaption)
                .font(.system(size: compact ? 9 : 10, weight: .medium, design: .monospaced))
                .tracking(1.1)
                .foregroundStyle(metric.color)
            Spacer()
            if metric == .elev {
                // Elevation's meaningful stat is GAIN, not average altitude.
                statPair(caption: "GAIN", value: "+\(elevGain)")
                statPair(caption: "MAX", value: peakLabel)
            } else {
                statPair(caption: "AVG", value: avgLabel)
                statPair(caption: metric.peakLabel, value: peakLabel)
            }
        }
        .padding(.top, compact ? 3 : 14)
        .padding(.bottom, compact ? 2 : 10)
    }

    /// Elevation gain (ft) — the passed-in authoritative value, else a
    /// noise-tolerant sum of positive deltas over the samples.
    private var elevGain: Int {
        if let g = elevationGainFt { return g }
        let e = samples.map(\.elevationFt)
        guard e.count > 1 else { return 0 }
        var gain = 0.0
        for i in 1..<e.count {
            let d = e[i] - e[i - 1]
            if d > 0.5 { gain += d }   // ignore sub-foot GPS jitter
        }
        return Int(gain.rounded())
    }

    // The honesty line — WORK/SPLIT readout + any compression/pin note. Keeping
    // it on-screen is the design's scale-honesty contract (handoff §2).
    @ViewBuilder
    private var scaleNote: some View {
        if let r = render {
            HStack(spacing: 8) {
                Text(r.scale.readout)
                    .foregroundStyle(Color.drip.textTertiary)
                if let note = r.scale.note {
                    Text("·").foregroundStyle(Color.drip.textTertiary)
                    Text(note).foregroundStyle(Color.drip.coral)
                }
                Spacer(minLength: 0)
            }
            .font(.system(size: 8.5, weight: .medium, design: .monospaced))
            .tracking(0.6)
            .padding(.bottom, 8)
        }
    }

    private func statPair(caption: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(value)
                .font(.custom("CrimsonPro-Regular", size: compact ? 15 : 22).weight(.bold))
                .monospacedDigit()
                .foregroundStyle(Color.drip.textPrimary)
            Text(caption)
                .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(Color.drip.textTertiary)
        }
    }

    private var avgLabel: String {
        let vals = samples.map { metric.value(of: $0) }.filter { $0.isFinite && $0 > 0 }
        guard !vals.isEmpty else { return "—" }
        return metric.format(vals.reduce(0, +) / Double(vals.count))
    }

    private var peakLabel: String {
        let vals = samples.map { metric.value(of: $0) }.filter { $0.isFinite && $0 > 0 }
        guard let p = metric.peak(of: vals) else { return "—" }
        return metric.format(p)
    }

    // MARK: Plot

    private var plotBlock: some View {
        ZStack(alignment: .topLeading) {
            // Width probe.
            GeometryReader { geo in
                Color.clear.preference(key: EffortWidthKey.self, value: geo.size.width)
            }
            if let r = render, plotWidth > 0 {
                plotContent(r)
            } else {
                // Loading: hold geometry, omit the trace (no spinner).
                Rectangle().fill(Color.clear)
            }
        }
        .frame(height: plotHeight + padT + padB)
        .contentShape(Rectangle())
        .gesture(scrubGesture)
        .onPreferenceChange(EffortWidthKey.self) { w in
            let rounded = (w - padL - padR).rounded()
            if rounded != plotWidth { plotWidth = rounded }
        }
        .task(id: renderToken) { rebuild() }
    }

    private var plotRect: CGRect {
        CGRect(x: padL, y: padT, width: plotWidth, height: plotHeight)
    }

    private func plotContent(_ r: EffortRender) -> some View {
        let plot = plotRect
        return ZStack(alignment: .topLeading) {
            // 0 · HR zone bands (HR metric only, behind everything)
            if metric == .hr, !hrZones.isEmpty {
                EffortHRZoneBands(zones: hrZones, scale: r.scale, plot: plot)
            }
            // 1 · split compression bands (behind everything)
            if let split = r.scale.split {
                EffortSplitBands(scale: r.scale, split: split, plot: plot)
            }
            // 2 · segment bands
            ForEach(Array(r.segments.enumerated()), id: \.offset) { _, seg in
                segmentBand(seg, plot: plot)
            }
            // 3 · gridlines
            EffortGrid(scale: r.scale, plot: plot)
            // 4 · trace + area (pace: spectrum fill; HR: zone-colored line)
            EffortTrace(points: r.points, scale: r.scale, window: window, plot: plot,
                        color: metric.color, spectrum: spectrumColor(for: r.scale),
                        dipFloor: 0,
                        strokeGradient: zoneLineGradient(for: r.scale))
            // 4b · clamped (below-axis) spans — a walk/stop marked so a floored
            // value never reads as a measured one (pace only).
            if metric == .pace {
                EffortClampMarks(points: r.points, scale: r.scale,
                                 window: window, plot: plot)
            }
            // 4c · lap boundary markers
            if showLaps, !lapMarks.isEmpty {
                EffortLapLines(marks: lapMarks, window: window, plot: plot)
            }
            // 5 · y-axis labels + caption
            yAxisLabels(r, plot: plot)
            // 6 · x-axis mile ticks (bottom panel only in a stack)
            if showXAxis { xAxisMiles(r, plot: plot) }
            // 7 · in-band rep numbers (vertical)
            ForEach(r.repStats, id: \.label) { stat in
                inBandNumbers(stat, plot: plot)
            }
            // 8 · scrub crosshair + readout
            if let t = activeScrubT, let idx = nearestIndex(to: t, in: r.points) {
                EffortScrub(point: r.points[idx], window: window, plot: plot,
                            metric: metric, segments: r.segments,
                            distanceMiles: distance(at: r.points[idx].t))
            }
        }
    }

    // MARK: Segment bands

    @ViewBuilder
    private func segmentBand(_ seg: EffortSegment, plot: CGRect) -> some View {
        let x0 = xFor(seg.t0, plot: plot)
        let x1 = xFor(seg.t1, plot: plot)
        let w = max(0, x1 - x0)
        if seg.kind == .rep {
            let isSel = selectedRep == seg.label
            let anySel = selectedRep != nil
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(Color.drip.coral.opacity(isSel ? 0.14 : anySel ? 0.03 : 0.09))
                    .frame(width: w, height: plot.height)
                // leading edge
                Rectangle()
                    .fill(Color.drip.coral.opacity(isSel ? 1 : anySel ? 0.15 : 0.45))
                    .frame(width: isSel ? 1.5 : 0.6, height: plot.height)
                // trailing edge when selected
                if isSel {
                    Rectangle().fill(Color.drip.coral)
                        .frame(width: 1.5, height: plot.height)
                        .offset(x: max(0, w - 1.5))
                }
                if w > 26 {
                    Text(seg.label)
                        .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                        .tracking(1.0)
                        .foregroundStyle(Color.drip.coral)
                        .offset(x: 5, y: 4)
                }
            }
            .frame(width: w, height: plot.height, alignment: .topLeading)
            .position(x: x0 + w / 2, y: plot.midY)
            // tap the bottom 20 pt selects/deselects this rep
            .overlay(alignment: .bottom) {
                Color.clear
                    .frame(width: w, height: 20)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedRep = (selectedRep == seg.label) ? nil : seg.label
                    }
            }
        } else if seg.kind == .float {
            Rectangle()
                .fill(Color.drip.textSecondary.opacity(0.045))
                .frame(width: w, height: plot.height)
                .position(x: x0 + w / 2, y: plot.midY)
        }
        // WU / CD: no fill.
    }

    // MARK: y-axis

    private func yAxisLabels(_ r: EffortRender, plot: CGRect) -> some View {
        ZStack(alignment: .topLeading) {
            // unit caption above top-left gridline
            Text(metric.axisCaption)
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(Color.drip.textTertiary)
                .position(x: padL, y: plot.minY - 8)
                .fixedSize()
            // HR labels its zone boundaries (in EffortHRZoneBands), not raw bpm.
            if metric != .hr {
                ForEach(r.ticks, id: \.self) { tick in
                    let y = yFor(tick, scale: r.scale, plot: plot)
                    Text(metric.format(tick))
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                        .foregroundStyle(Color.drip.textTertiary)
                        .frame(width: padL - 7, alignment: .trailing)
                        .position(x: (padL - 7) / 2, y: y)
                        .fixedSize()
                }
            }
        }
    }

    // MARK: x-axis miles

    private func xAxisMiles(_ r: EffortRender, plot: CGRect) -> some View {
        let everySecond = r.mileMarks.count > 8
        return ZStack(alignment: .topLeading) {
            ForEach(r.mileMarks, id: \.mile) { mark in
                let x = xFor(mark.t, plot: plot)
                if x >= plot.minX && x <= plot.maxX {
                    // tick
                    Rectangle().fill(Color.drip.textTertiary)
                        .frame(width: 0.8, height: 4)
                        .position(x: x, y: plot.maxY + 2)
                    if !everySecond || mark.mile % 2 == 0 {
                        Text("\(mark.mile) MI")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .tracking(0.6)
                            .foregroundStyle(Color.drip.textTertiary)
                            .fixedSize()
                            .position(x: x, y: plot.maxY + 14)
                    }
                }
            }
        }
    }

    // MARK: in-band rep numbers (vertical)

    @ViewBuilder
    private func inBandNumbers(_ stat: EffortRepStat, plot: CGRect) -> some View {
        if let seg = segments.first(where: { $0.label == stat.label }) {
            let x0 = xFor(seg.t0, plot: plot)
            let x1 = xFor(seg.t1, plot: plot)
            let w = x1 - x0
            if w > 14 {
                // Set vertically inside the band, reading upward, anchored clear
                // of the x-axis mile labels below the baseline.
                Text("\(EffortFormat.pace(stat.meanPace)) · \(Int(stat.meanHR.rounded())) BPM")
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color.drip.textSecondary)
                    .fixedSize()
                    .rotationEffect(.degrees(-90))
                    .position(x: x0 + w / 2, y: plot.maxY - 74)
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Text("DRAG TO SCRUB · TAP A REP TO SELECT")
            Spacer()
            if onExpand != nil {
                Button { onExpand?() } label: {
                    Text("ROTATE FOR FULL SCREEN ↗")
                }
                .buttonStyle(.plain)
            }
        }
        .font(.system(size: 8, weight: .medium, design: .monospaced))
        .tracking(1.0)
        .foregroundStyle(Color.drip.textTertiary)
        .padding(.top, 12)
        .overlay(Rectangle().fill(Color.drip.divider).frame(height: 1), alignment: .top)
    }

    // MARK: Gestures

    private var scrubGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                let plot = plotRect
                guard plot.width > 0 else { return }
                let frac = min(max((g.location.x - plot.minX) / plot.width, 0), 1)
                let t = window.lowerBound + Double(frac) * (window.upperBound - window.lowerBound)
                if let b = sharedScrubT { b.wrappedValue = t } else { scrubT = t }
            }
            .onEnded { _ in
                if let b = sharedScrubT { b.wrappedValue = nil } else { scrubT = nil }
            }
    }

    // MARK: HR zone-colored line

    /// A vertical gradient that colors the HR line by the zone at each height,
    /// so the line reads directly against the zone bands. Nil for other metrics.
    private func zoneLineGradient(for scale: EffortScale) -> LinearGradient? {
        guard metric == .hr, !hrZones.isEmpty else { return nil }
        let n = 24
        let stops: [Gradient.Stop] = (0...n).map { i in
            let f = Double(i) / Double(n)                 // 0 = top (high HR)
            let hr = scale.lo + (1 - f) * (scale.hi - scale.lo)
            return .init(color: EffortHRRamp.color(forHR: hr, zones: hrZones), location: f)
        }
        return LinearGradient(stops: stops, startPoint: .top, endPoint: .bottom)
    }

    // MARK: Pace-spectrum fill

    /// Maps a pace (sec/mi) to its pace-spectrum color. Anchored to the athlete's
    /// real zones when available (so a pace reads the same color as everywhere
    /// else), else scaled to this chart's domain. Nil for non-pace metrics.
    private func spectrumColor(for scale: EffortScale) -> ((Double) -> Color)? {
        guard metric == .pace else { return nil }
        return { pace in
            if let z = paceZones, let c = PaceSpectrum.anchoredColor(paceSec: pace, zones: z) {
                return c
            }
            return PaceSpectrum.color(forPaceSec: pace, slowSec: scale.hi, fastSec: scale.lo)
        }
    }

    // MARK: Mapping helpers

    private func xFor(_ t: TimeInterval, plot: CGRect) -> CGFloat {
        let span = window.upperBound - window.lowerBound
        guard span > 0 else { return plot.minX }
        return plot.minX + CGFloat((t - window.lowerBound) / span) * plot.width
    }

    private func yFor(_ value: Double, scale: EffortScale, plot: CGRect) -> CGFloat {
        plot.maxY - CGFloat(scale.normalized(value)) * plot.height
    }

    private func nearestIndex(to t: TimeInterval, in points: [EffortPoint]) -> Int? {
        guard !points.isEmpty else { return nil }
        var best = 0
        var bestD = Double.greatestFiniteMagnitude
        for (i, p) in points.enumerated() {
            let d = abs(p.t - t)
            if d < bestD { bestD = d; best = i }
        }
        return best
    }

    private func distance(at t: TimeInterval) -> Double {
        // nearest sample's cumulative miles
        guard !samples.isEmpty else { return 0 }
        var best = samples[0]
        var bestD = Double.greatestFiniteMagnitude
        for s in samples {
            let d = abs(s.t - t)
            if d < bestD { bestD = d; best = s }
        }
        return best.distanceMiles
    }

    // MARK: Derived render pipeline

    private var renderToken: EffortRenderToken {
        EffortRenderToken(width: Int(plotWidth), lo: window.lowerBound, hi: window.upperBound,
                          metric: metric, count: samples.count)
    }

    /// Stable, zone-anchored pace bounds: fastest race anchor (with headroom) to
    /// easy pace + a jog buffer. Same axis every run — so a session reads the
    /// same against itself and against last month — and it's wide enough that a
    /// recovery JOG shows its real depth (only a walk/stop falls off the bottom
    /// and gets marked). Nil (→ moving-band fallback) when zones are unavailable.
    private var paceAnchoredDomain: ClosedRange<Double>? {
        guard let z = paceZones else { return nil }
        let fast = (z.mile?.pace ?? z.fiveK?.pace ?? z.thresholdPace ?? 330) - 12
        let easySlow = z.easy?.paceSlow ?? z.easy?.paceFast ?? 570
        let slow = easySlow + 90
        guard slow > fast + 30 else { return nil }
        return fast...slow
    }

    private func fixedDomain(for pts: [EffortPoint]) -> ClosedRange<Double>? {
        switch metric {
        case .pace:
            return paceAnchoredDomain
        case .hr:
            // Include the actual max so the work portion isn't above the top
            // gridline (was: p98 fit stopped at 160 while max was 175).
            let v = pts.map(\.value).filter { $0 > 0 }
            guard let lo = v.min(), let hi = v.max(), hi > lo else { return nil }
            return (lo - 4)...(hi + 4)
        default:
            return nil
        }
    }

    private func rebuild() {
        guard plotWidth > 0, !samples.isEmpty else { render = nil; return }
        let interval = EffortStreamAdapter.sampleInterval(times: samples.map(\.t))
        let points = EffortSeries.resample(samples, window: window, plotWidth: plotWidth,
                                           sampleInterval: interval) { metric.value(of: $0) }
        let smoothedVals = EffortSeries.smooth(points.map(\.value))
        let smoothed = zip(points, smoothedVals).map { EffortPoint(t: $0.0.t, value: $0.1) }
        let scale = EffortChartScale.resolve(points: smoothed, segments: segments,
                                             metric: metric, request: .work,
                                             fixedDomain: fixedDomain(for: smoothed))
        let ticks = scale.ticks()
        let marks = EffortSeries.mileMarks(samples)
        let repStats = EffortSeries.repStats(samples, segments: segments,
                                             targetPaceSecPerMile: targetPaceSecPerMile)
        render = EffortRender(points: smoothed, scale: scale, ticks: ticks,
                              mileMarks: marks, repStats: repStats, segments: segments)
    }
}

// MARK: - Detail section: Pace + HR + Elevation stacked

/// The workout-detail telemetry section — the pace chart (spectrum fill) plus
/// HR and elevation stacked beneath it, under one plate strip and footer. This
/// is what mounts in `WorkoutRepReceiptView` in place of the old panel, so the
/// "PACE · HR · ELEVATION" section carries all three again.
struct EffortDetailCharts: View {
    let samples: [EffortSample]
    let segments: [EffortSegment]
    let targetPaceSecPerMile: Double
    let distanceLabel: String
    let durationLabel: String
    var figure: String = "FIG. 31"
    var paceZones: PaceZonesEngine? = nil
    var hrZones: [RRZone] = []
    var lapMarks: [TimeInterval] = []
    var elevationGainFt: Int? = nil

    @State private var showLaps = false
    @State private var showLandscape = false

    private var hasHR: Bool { samples.contains { $0.hr > 0 } }
    private var hasElev: Bool {
        let e = samples.map(\.elevationFt)
        return (e.max() ?? 0) - (e.min() ?? 0) > 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            plateStrip
            controlRow
            plot(.pace, height: 240)
            if hasHR {
                sep
                plot(.hr, height: 150)
            }
            if hasElev {
                sep
                plot(.elev, height: 130)
            }
            footer
        }
        .fullScreenCover(isPresented: $showLandscape) {
            EffortLandscapeView(
                samples: samples, segments: segments,
                targetPaceSecPerMile: targetPaceSecPerMile,
                distanceLabel: distanceLabel, durationLabel: durationLabel,
                paceZones: paceZones, hrZones: hrZones, lapMarks: lapMarks,
                elevationGainFt: elevationGainFt)
        }
    }

    private var controlRow: some View {
        HStack(spacing: 8) {
            Spacer()
            if !lapMarks.isEmpty { chip("LAPS", on: showLaps) { showLaps.toggle() } }
            chip("EXPAND ↗", on: false) { showLandscape = true }
        }
        .padding(.top, 10)
    }

    private func chip(_ title: String, on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .tracking(1.1)
                .foregroundStyle(on ? Color.drip.coral : Color.drip.textSecondary)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .overlay(Capsule().stroke(on ? Color.drip.coral : Color.drip.divider,
                                          lineWidth: on ? 1.3 : 1))
        }
        .buttonStyle(.plain)
    }

    private func plot(_ metric: EffortMetric, height: CGFloat) -> some View {
        EffortPortraitChart(
            samples: samples, segments: segments,
            targetPaceSecPerMile: targetPaceSecPerMile,
            distanceLabel: distanceLabel, durationLabel: durationLabel,
            metric: metric, plotHeight: height, paceZones: paceZones,
            hrZones: hrZones, lapMarks: lapMarks, showLaps: showLaps,
            elevationGainFt: elevationGainFt, showChrome: false)
    }

    private var sep: some View {
        Rectangle().fill(Color.drip.divider).frame(height: 1).padding(.vertical, 18)
    }

    private var plateStrip: some View {
        HStack {
            Text("THE EFFORT · \(distanceLabel) · \(durationLabel)")
            Spacer()
            Text(figure)
        }
        .font(.system(size: 8.5, weight: .medium, design: .monospaced))
        .tracking(1.4)
        .foregroundStyle(Color.drip.textSecondary)
        .padding(.bottom, 14)
        .overlay(Rectangle().fill(Color.drip.divider).frame(height: 1), alignment: .bottom)
    }

    private var footer: some View {
        Text("DRAG TO SCRUB · TAP A REP TO SELECT")
            .font(.system(size: 8, weight: .medium, design: .monospaced))
            .tracking(1.0)
            .foregroundStyle(Color.drip.textTertiary)
            .padding(.top, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(Rectangle().fill(Color.drip.divider).frame(height: 1), alignment: .top)
    }
}

// MARK: - Derived render data

private struct EffortRender {
    let points: [EffortPoint]
    let scale: EffortScale
    let ticks: [Double]
    let mileMarks: [EffortMileMark]
    let repStats: [EffortRepStat]
    let segments: [EffortSegment]
}

private struct EffortRenderToken: Equatable {
    let width: Int
    let lo: TimeInterval
    let hi: TimeInterval
    let metric: EffortMetric
    let count: Int
}

private struct EffortWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - Drawing subviews (Path, house style)

/// The metric trace plus its filled area, closed to the baseline. When
/// `spectrum` is supplied (pace), the area is shaded by the pace spectrum blues
/// — deep brick under fast running, pale sky under slow stretches — the way
/// Strava colors its pace fill, done with one horizontal gradient masked by the
/// area shape (no per-strip fills, no Canvas).
private struct EffortTrace: View {
    let points: [EffortPoint]
    let scale: EffortScale
    let window: ClosedRange<TimeInterval>
    let plot: CGRect
    let color: Color
    var spectrum: ((Double) -> Color)? = nil
    /// Minimum fill height as a fraction of plot height. Keeps a walk/stop from
    /// collapsing the fill to nothing — the recovery reads as a shallow dip in a
    /// continuous ribbon instead of a white gap.
    var dipFloor: CGFloat = 0
    /// When set, the trace is drawn as a LINE stroked with this vertical
    /// gradient (used for HR: a zone-colored line reading against the zone
    /// bands) instead of a competing filled area.
    var strokeGradient: LinearGradient? = nil

    var body: some View {
        if let spectrum, points.count > 1 {
            area.fill(paceGradient(spectrum))              // pace: spectrum fill
        } else if let strokeGradient {
            ZStack {
                area.fill(color.opacity(0.04))             // whisper, just to ground the line
                line.stroke(strokeGradient,
                            style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
            }
        } else {
            area.fill(color.opacity(0.16))                 // elevation etc.
        }
    }

    /// A vertical gradient keyed to the pace axis: the fill's color at each
    /// height is the pace-spectrum color for the pace at that height (fast/navy
    /// up top, easy/pale toward the bottom). One smooth ramp — no per-x seams.
    private func paceGradient(_ spectrum: (Double) -> Color) -> LinearGradient {
        let n = 12
        let lo = scale.lo, hi = scale.hi
        let stops: [Gradient.Stop] = (0...n).map { i in
            let f = Double(i) / Double(n)            // 0 = top (fast), 1 = bottom (slow)
            return .init(color: spectrum(lo + (hi - lo) * f), location: f)
        }
        return LinearGradient(stops: stops, startPoint: .top, endPoint: .bottom)
    }

    private func x(_ t: TimeInterval) -> CGFloat {
        let span = window.upperBound - window.lowerBound
        guard span > 0 else { return plot.minX }
        return plot.minX + CGFloat((t - window.lowerBound) / span) * plot.width
    }
    private func y(_ v: Double) -> CGFloat {
        let n = max(CGFloat(scale.normalized(v)), dipFloor)
        return plot.maxY - n * plot.height
    }

    private var line: Path {
        Path { p in
            guard let first = points.first else { return }
            p.move(to: CGPoint(x: x(first.t), y: y(first.value)))
            for pt in points.dropFirst() { p.addLine(to: CGPoint(x: x(pt.t), y: y(pt.value))) }
        }
    }
    private var area: Path {
        Path { p in
            guard let first = points.first, let last = points.last else { return }
            p.move(to: CGPoint(x: x(first.t), y: plot.maxY))
            p.addLine(to: CGPoint(x: x(first.t), y: y(first.value)))
            for pt in points.dropFirst() { p.addLine(to: CGPoint(x: x(pt.t), y: y(pt.value))) }
            p.addLine(to: CGPoint(x: x(last.t), y: plot.maxY))
            p.closeSubpath()
        }
    }
}

/// Horizontal gridlines at each tick value.
private struct EffortGrid: View {
    let scale: EffortScale
    let plot: CGRect
    var body: some View {
        Path { p in
            for tick in scale.ticks() {
                let y = plot.maxY - CGFloat(scale.normalized(tick)) * plot.height
                p.move(to: CGPoint(x: plot.minX, y: y))
                p.addLine(to: CGPoint(x: plot.maxX, y: y))
            }
        }
        .stroke(Color.drip.divider, lineWidth: 0.6)
        .overlay(
            Path { p in   // baseline
                p.move(to: CGPoint(x: plot.minX, y: plot.maxY))
                p.addLine(to: CGPoint(x: plot.maxX, y: plot.maxY))
            }.stroke(Color.drip.divider, lineWidth: 1)
        )
    }
}

/// The compressed outer bands of a SPLIT axis: a faint fill + a dashed boundary
/// at the inner edge, so the compression is visible, never silent.
private struct EffortSplitBands: View {
    let scale: EffortScale
    let split: EffortScale.SplitGeometry
    let plot: CGRect

    var body: some View {
        ZStack(alignment: .topLeading) {
            band(from: split.gl, to: split.repLo, present: split.fLo > 0)
            band(from: split.repHi, to: split.gh, present: split.fHi > 0)
        }
    }

    @ViewBuilder
    private func band(from a: Double, to b: Double, present: Bool) -> some View {
        if present {
            let ya = plot.maxY - CGFloat(scale.normalized(a)) * plot.height
            let yb = plot.maxY - CGFloat(scale.normalized(b)) * plot.height
            let top = min(ya, yb), bottom = max(ya, yb)
            ZStack(alignment: .topLeading) {
                Rectangle().fill(Color.drip.textSecondary.opacity(0.05))
                    .frame(width: plot.width, height: bottom - top)
                    .position(x: plot.midX, y: (top + bottom) / 2)
                // dashed boundary at the inner edge (nearest the work band)
                Path { p in
                    let yInner = (a == split.gl) ? bottom : top
                    p.move(to: CGPoint(x: plot.minX, y: yInner))
                    p.addLine(to: CGPoint(x: plot.maxX, y: yInner))
                }
                .stroke(Color.drip.textTertiary,
                        style: StrokeStyle(lineWidth: 0.7, dash: [4, 3]))
            }
        }
    }
}

/// A monotonic HR intensity ramp — one warm hue, increasing saturation Z1→Z5 —
/// so a threshold session's hard zones read as an escalating scale instead of
/// three near-identical pinks. Independent of the app's semantic zone colors on
/// purpose; here the job is legibility of ordinal intensity.
enum EffortHRRamp {
    static let stops: [Color] = [
        Color(hex: "E7CDBB"),  // Z1 pale
        Color(hex: "E0A87F"),  // Z2
        Color(hex: "D17A48"),  // Z3
        Color(hex: "BC5228"),  // Z4
        Color(hex: "922F12"),  // Z5 deep
    ]
    static func color(index: Int) -> Color { stops[min(max(index, 0), stops.count - 1)] }
    static func color(forHR hr: Double, zones: [RRZone]) -> Color {
        if let i = zones.firstIndex(where: { hr >= Double($0.lo) && hr < Double($0.hi) }) {
            return color(index: i)
        }
        if let last = zones.last, hr >= Double(last.lo) { return color(index: zones.count - 1) }
        return color(index: 0)
    }
}

/// Marks pace spans that fell below the axis floor (a walk / stop) so a clamped
/// value never passes for a measured one: a dashed baseline segment plus a
/// "↓ m:ss" callout of the real pace there.
private struct EffortClampMarks: View {
    let points: [EffortPoint]
    let scale: EffortScale
    let window: ClosedRange<TimeInterval>
    let plot: CGRect

    private func x(_ t: TimeInterval) -> CGFloat {
        let span = window.upperBound - window.lowerBound
        guard span > 0 else { return plot.minX }
        return plot.minX + CGFloat((t - window.lowerBound) / span) * plot.width
    }

    private var spans: [(range: ClosedRange<Int>, pace: Double)] {
        EffortChartScale.pinnedRuns(points: points, scale: scale).compactMap { run in
            guard run.count >= 2 else { return nil }
            let vals = points[run].map(\.value).sorted()
            let median = vals[vals.count / 2]
            guard median > scale.hi else { return nil }   // slower than the floor = a walk
            return (run, median)
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(spans.enumerated()), id: \.offset) { _, s in
                let x0 = x(points[s.range.lowerBound].t)
                let x1 = x(points[s.range.upperBound].t)
                let mid = (x0 + x1) / 2
                Path { p in
                    p.move(to: CGPoint(x: x0, y: plot.maxY))
                    p.addLine(to: CGPoint(x: x1, y: plot.maxY))
                }
                .stroke(Color.drip.textSecondary.opacity(0.7),
                        style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                Text("↓ \(EffortFormat.pace(s.pace))")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .tracking(0.4)
                    .foregroundStyle(Color.drip.textSecondary)
                    .fixedSize()
                    .position(x: mid, y: plot.maxY - 10)
            }
        }
    }
}

/// Vertical lap-boundary markers, drawn over the fill as thin dashed lines.
private struct EffortLapLines: View {
    let marks: [TimeInterval]
    let window: ClosedRange<TimeInterval>
    let plot: CGRect

    var body: some View {
        Path { p in
            let span = window.upperBound - window.lowerBound
            guard span > 0 else { return }
            for t in marks {
                let x = plot.minX + CGFloat((t - window.lowerBound) / span) * plot.width
                guard x > plot.minX + 0.5, x < plot.maxX - 0.5 else { continue }
                p.move(to: CGPoint(x: x, y: plot.minY))
                p.addLine(to: CGPoint(x: x, y: plot.maxY))
            }
        }
        .stroke(Color.drip.textPrimary.opacity(0.28),
                style: StrokeStyle(lineWidth: 0.8, dash: [3, 3]))
    }
}

/// HR zone bands: full-width color washes for each `rr_zones` band, with the
/// zone id set right-aligned inside. Bands are clamped to the visible axis and
/// skipped when thinner than a point.
private struct EffortHRZoneBands: View {
    let zones: [RRZone]
    let scale: EffortScale
    let plot: CGRect
    var padL: CGFloat = 46

    private func y(_ bpm: Int) -> CGFloat {
        plot.maxY - CGFloat(scale.normalized(Double(bpm))) * plot.height
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Fills — escalating opacity so higher zones read as visibly stronger.
            ForEach(Array(zones.enumerated()), id: \.element.id) { idx, z in
                let ramp = EffortHRRamp.color(index: idx)
                let top = min(y(z.hi), y(z.lo)), bottom = max(y(z.hi), y(z.lo))
                let h = bottom - top
                if h > 1 {
                    Rectangle().fill(ramp.opacity(0.05 + Double(idx) * 0.055))
                        .frame(width: plot.width, height: h)
                        .position(x: plot.midX, y: (top + bottom) / 2)
                    Text(z.id)
                        .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(ramp)
                        .fixedSize()
                        .position(x: plot.maxX - 13,
                                  y: min(max((top + bottom) / 2, plot.minY + 7), plot.maxY - 7))
                }
            }
            // Boundary line + threshold bpm at each interior zone edge, so you can
            // see (and read) exactly where one zone ends and the next begins.
            ForEach(Array(zones.enumerated()), id: \.element.id) { idx, z in
                let yb = y(z.lo)
                if idx > 0, yb > plot.minY + 2, yb < plot.maxY - 2 {
                    let ramp = EffortHRRamp.color(index: idx)
                    Path { p in
                        p.move(to: CGPoint(x: plot.minX, y: yb))
                        p.addLine(to: CGPoint(x: plot.maxX, y: yb))
                    }
                    .stroke(ramp.opacity(0.55), lineWidth: 1)
                    Text("\(z.lo)")
                        .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.drip.textTertiary)
                        .frame(width: padL - 7, alignment: .trailing)
                        .position(x: (padL - 7) / 2, y: yb)
                        .fixedSize()
                }
            }
        }
    }
}

/// Crosshair + readout card snapped to the nearest resampled point.
private struct EffortScrub: View {
    let point: EffortPoint
    let window: ClosedRange<TimeInterval>
    let plot: CGRect
    let metric: EffortMetric
    let segments: [EffortSegment]
    let distanceMiles: Double

    private var x: CGFloat {
        let span = window.upperBound - window.lowerBound
        guard span > 0 else { return plot.minX }
        return plot.minX + CGFloat((point.t - window.lowerBound) / span) * plot.width
    }
    private var y: CGFloat { plot.maxY /* dot rides the value */ }

    private var segLabel: String {
        segments.first { $0.contains(point.t) }?.label ?? "RUN"
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Path { p in
                p.move(to: CGPoint(x: x, y: plot.minY))
                p.addLine(to: CGPoint(x: x, y: plot.maxY))
            }
            .stroke(Color.drip.textPrimary.opacity(0.55),
                    style: StrokeStyle(lineWidth: 0.8, dash: [2, 3]))
            readout
                .position(x: clampX(x + 16 + 62), y: plot.minY + 40)
        }
    }

    private var readout: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(segLabel) · \(EffortFormat.clock(point.t))")
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.drip.textTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(metric.format(point.value))
                    .font(.custom("CrimsonPro-Regular", size: 22).weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(Color.drip.textPrimary)
                Text(metric.unit)
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.drip.textSecondary)
            }
            Text(String(format: "MI %.2f", distanceMiles))
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.drip.textTertiary)
        }
        .padding(EdgeInsets(top: 8, leading: 10, bottom: 9, trailing: 10))
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.drip.cardBackground)
                .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
        )
        .allowsHitTesting(false)
    }

    private func clampX(_ cx: CGFloat) -> CGFloat {
        min(max(cx, plot.minX + 62), plot.maxX - 62)
    }
}

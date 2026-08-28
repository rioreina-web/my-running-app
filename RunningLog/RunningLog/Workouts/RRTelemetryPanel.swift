//
//  RRTelemetryPanel.swift
//  RunningLog
//
//  The unified telemetry chart for the "Rep Receipt" workout detail
//  (WorkoutRepReceiptView). Replaces the four stacked time-series panels
//  — RRZoneTimeline (HR), RRPaceTrace (pace), RRCadenceStrip (cadence),
//  RRElevationGrade (elevation) — with ONE shared time-axis chart, per the
//  May-2026 redesign:
//
//    1. One chart — HR / pace / cadence / elevation on a single time axis.
//    2. Toggleable layers — chips turn each metric on/off (HR + Pace on by
//       default). The "lead" metric (first active in priority order) owns
//       the left y-axis labels.
//    3. Reps on the chart — real work-rep windows shaded coral with R#
//       labels (from the lap-derived `RRWindow`s).
//    4. Expandable — EXPAND opens a fullscreen view; press-and-drag scrubs
//       a crosshair + floating value tooltip.
//
//  House style: GeometryReader + Path (matches the other RR* charts; no
//  Canvas, no chart dependency). Colors reuse TelemetryMetric (HR coral,
//  Pace navy, Cadence gray, Elevation sage) so both detail screens read
//  the same. Pace formatting respects the km toggle via rr_pace.
//
//  The HR-recovery small-multiples row and the SPLITS table stay as their
//  own sections in WorkoutRepReceiptView — they aren't continuous traces.
//

import SwiftUI

/// How the scrubber is activated, so the same chart can live both inside a
/// vertically-scrolling page and on a dedicated full-screen view.
///
/// BOTH modes are now gated behind a DOUBLE-TAP that arms the scrubber
/// (`scrubArmed`). Merely swiping across a chart — scrolling the page past it,
/// panning the time axis, brushing it on the way somewhere else — must never
/// drop a crosshair; a press-and-hold was too easy to trigger by accident and
/// full-screen's bare drag fired on the very first touch. Once armed, the
/// crosshair STAYS put when you lift your finger, and a second double-tap puts
/// it away.
/// - `.hold`: armed drags scrub; unarmed, the chart passes touches straight
///   through, so a plain swipe still scrolls the page (the inline card).
/// - `.drag`: armed drags scrub and auto-pan the zoomed axis to follow the
///   point. Used full-screen, where there's no page scroll to protect.
enum RRScrubMode { case hold, drag }

// MARK: - Panel (chips + chart + readout + expand)

struct RRTelemetryPanel: View {
    let times: [Double]
    let hr: [Double]
    let paceSec: [Double]   // sec/mi
    let cadence: [Double]   // spm
    let altFt: [Double]     // feet
    let windows: [RRWindow]
    let km: Bool
    /// HR zone bands (Z1–Z5). Empty disables the zone overlay + its chip.
    var zones: [RRZone] = []

    // Multi-select: HR + Pace stack as synced lanes by default, so they read
    // against each other on one shared, scrollable time axis. Add/remove lanes
    // (Cadence, Elevation) via the chips.
    @State private var active: Set<TelemetryMetric> = [.heartRate, .pace]
    @State private var scrub: Double? = nil
    /// Double-tap arms the scrubber; until then drags over the chart are inert.
    /// Shared across every lane, like `scrub`, so arming one arms the stack.
    @State private var scrubArmed = false
    @State private var showFull = false
    @State private var showRepPace = false
    /// Apply the HR-zone overlay (bands behind the trace + zone axis tags).
    @State private var zonesOn = true

    private var series: [TelemetryMetric: [Double]] {
        [.heartRate: hr, .pace: paceSec, .cadence: cadence, .elevation: altFt]
    }
    private var availability: [TelemetryMetric: Bool] {
        [
            .heartRate: hr.count > 1,
            .pace: paceSec.count > 1,
            .cadence: cadence.count > 1,
            .elevation: altFt.count > 1,
        ]
    }

    /// Seed the horizontal zoom. Interval workouts (~4+ reps) start zoomed so
    /// each rep gets real width (~4 per screen) and you scroll through the
    /// session. Continuous runs show the WHOLE run at once by default
    /// (Garmin-style) rather than ~10 min/screen — pinch-to-zoom and sideways
    /// scroll still work. Capped at the max interactive zoom.
    private var defaultZoom: CGFloat {
        let byReps = windows.count >= 4 ? CGFloat(windows.count) / 4 : 1
        return min(8, max(1, byReps))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("THE EFFORT")
                    .font(.dripStat(12)).tracking(1.2)
                    .foregroundStyle(Color.drip.textSecondary)
                Spacer()
                Button { showFull = true } label: {
                    Text("EXPAND")
                        .font(.dripStat(11)).tracking(1.0)
                        .foregroundStyle(Color.drip.coral)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .overlay(Capsule().stroke(Color.drip.coral.opacity(0.5), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            RRTelemetryChips(active: $active, availability: availability,
                             showRepPace: $showRepPace, repsAvailable: !windows.isEmpty,
                             zonesOn: $zonesOn, zonesAvailable: !zones.isEmpty)
            // Synced stacked lanes on a wider-than-screen canvas: each rep gets
            // real width and you scroll through the workout instead of squishing
            // it. Roughly ~4 reps per screen (min zoom 1 for easy runs w/o reps).
            RRStackedTelemetry(times: times, series: series, active: active,
                               windows: windows, km: km, scrub: $scrub,
                               scrubArmed: $scrubArmed,
                               zones: zones, zonesOn: zonesOn, showRepPace: showRepPace,
                               scrubMode: .hold, panelHeight: 172,
                               initialZoom: defaultZoom)
            Text(scrubArmed
                 ? "SCRUB ON · DRAG TO MOVE · DOUBLE-TAP TO PUT IT AWAY"
                 : "DOUBLE-TAP A PANEL FOR LIVE VALUES · EXPAND FOR FULL SCREEN")
                .font(.dripStat(11)).tracking(0.4)
                .foregroundStyle(Color.drip.textTertiary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .fullScreenCover(isPresented: $showFull) {
            RRTelemetryFullScreen(times: times, series: series, active: $active,
                                  availability: availability, windows: windows, km: km,
                                  zones: zones, showRepPace: $showRepPace, zonesOn: $zonesOn)
        }
    }
}

// MARK: - Chips

struct RRTelemetryChips: View {
    @Binding var active: Set<TelemetryMetric>
    let availability: [TelemetryMetric: Bool]
    /// Toggle for the per-rep average-pace bar overlay. Only shown when the run
    /// actually has work reps to summarize.
    @Binding var showRepPace: Bool
    var repsAvailable: Bool = false
    /// Toggle for the HR-zone overlay. Only shown when zone data exists.
    @Binding var zonesOn: Bool
    var zonesAvailable: Bool = false

    var body: some View {
        // Horizontal scroll so the extra REP PACE chip never clips on a narrow
        // phone — the metric chips alone already nearly fill the width.
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(TelemetryMetric.allCases) { metric in
                    let on = active.contains(metric)
                    let avail = availability[metric] ?? true
                    Button {
                        // Single-select: tapping a metric shows ONLY that chart.
                        withAnimation(.easeInOut(duration: 0.15)) { active = [metric] }
                    } label: {
                        chipLabel(metric.label, color: metric.color, on: on)
                            .opacity(avail ? 1 : 0.35)
                    }
                    .buttonStyle(.plain)
                    .disabled(!avail)
                }
                // Overlay toggles only apply to the metric on screen: rep-pace
                // over the pace chart, zones over the HR chart.
                if repsAvailable && active.contains(.pace) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { showRepPace.toggle() }
                    } label: {
                        chipLabel("Rep pace", color: TelemetryMetric.pace.color, on: showRepPace)
                    }
                    .buttonStyle(.plain)
                }
                if zonesAvailable && active.contains(.heartRate) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { zonesOn.toggle() }
                    } label: {
                        chipLabel("HR zones", color: TelemetryMetric.heartRate.color, on: zonesOn)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 1)
        }
    }

    /// One pill — shared by the metric chips and the rep-pace toggle.
    private func chipLabel(_ title: String, color: Color, on: Bool) -> some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 3).fill(color)
                .frame(width: 11, height: 11).opacity(on ? 1 : 0.35)
            Text(title.uppercased())
                .font(.dripStat(12)).tracking(0.6)
                .foregroundStyle(on ? Color.drip.textPrimary : Color.drip.textTertiary)
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(on ? Color.drip.cardBackgroundElevated : Color.drip.cardBackground)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(on ? color : Color.drip.divider, lineWidth: on ? 1.5 : 1))
    }
}

// MARK: - Chart

struct RRTelemetryChart: View {
    let times: [Double]
    let series: [TelemetryMetric: [Double]]
    let active: Set<TelemetryMetric>
    let windows: [RRWindow]
    let km: Bool
    @Binding var scrub: Double?
    /// Armed by a double-tap on any lane. While false this chart claims no
    /// drag at all, so swiping across it scrolls/pans exactly as if the
    /// scrubber weren't there.
    @Binding var scrubArmed: Bool
    /// Fixed chart height. Pass `nil` to let the chart fill the space it's
    /// given (used full-screen so the layout fits any device without clipping).
    var height: CGFloat? = 220
    var scrubMode: RRScrubMode = .hold
    /// Per-rep average-pace bar overlay (toggled by the REP PACE chip).
    var showRepPace: Bool = false
    /// HR zone bands (Z1–Z5) + master toggle for the zone overlay.
    var zones: [RRZone] = []
    var zonesOn: Bool = false
    /// Stacked-panel mode suppresses the floating tooltip (the panel header
    /// shows the live value instead) and the per-panel x-axis (only the
    /// bottom panel in a stack draws the shared time labels).
    var showTooltip: Bool = true
    var showXAxisLabels: Bool = true

    // padB leaves room below the plot for the time (x-axis) labels.
    // padL fits a 9pt "12:10" pace label with breathing room.
    private let padL: CGFloat = 50, padR: CGFloat = 12, padT: CGFloat = 20, padB: CGFloat = 28

    // Pinch-zoom + horizontal pan, SHARED across all lanes in the stack so they
    // scroll together (synced time axis). Owned by RRStackedTelemetry.
    @Binding var zoom: CGFloat
    @Binding var lastZoom: CGFloat
    @Binding var panOffset: CGFloat
    @Binding var lastPan: CGFloat

    private var total: Double { max(times.last ?? 1, 1) }
    private var lead: TelemetryMetric? { TelemetryMetric.priority.first { active.contains($0) } }
    /// Zone overlay is live only when toggled on, zone data exists, and HR is
    /// actually being shown (zones map onto the HR y-axis).
    private var showZones: Bool { zonesOn && !zones.isEmpty && active.contains(.heartRate) }

    /// Zoomed content width for a given plot rect.
    private func contentW(_ rect: CGRect) -> CGFloat { rect.width * zoom }
    /// Pan clamped so the zoomed content always covers the plot rect.
    private func clampedPan(_ rect: CGRect) -> CGFloat {
        min(max(panOffset, rect.width - contentW(rect)), 0)
    }

    var body: some View {
        GeometryReader { geo in
            let rect = CGRect(x: padL, y: padT,
                              width: max(geo.size.width - padL - padR, 1),
                              height: max(geo.size.height - padT - padB, 1))
            let plot = ZStack(alignment: .topLeading) {
                if showZones { zoneBands(rect) }             // fixed, furthest back
                gridLines(rect)                              // fixed, behind
                ZStack(alignment: .topLeading) {             // scrollable, clipped
                    repBands(rect)
                    if showRepPace { repPaceBars(rect) }
                    lines(rect)
                    scrubLayer(rect)
                }
                .mask(
                    Path(CGRect(x: rect.minX, y: 0, width: rect.width, height: geo.size.height))
                        .fill(Color.black)
                )
                axisLabels(rect)                             // fixed, on top
                if showXAxisLabels { xAxisTimeLabels(rect) }  // fixed, below plot
                if showTooltip, let s = scrub, let idx = index(s) {
                    tooltip(idx: idx, frac: s, rect: rect, canvasWidth: geo.size.width)
                }
                // Armed affordance: the plot picks up a coral hairline so it's
                // obvious the next drag will scrub rather than scroll.
                if scrubArmed {
                    Path(roundedRect: rect, cornerRadius: 3)
                        .stroke(Color.drip.coral.opacity(0.45), lineWidth: 1)
                }
            }
            .contentShape(Rectangle())

            // Gestures, in one shape for both modes: a double-tap ARMS the
            // scrubber (and drops the crosshair where you tapped), and only
            // then does a drag scrub. Unarmed, the scrub drag is masked to
            // `.subviews` — i.e. off — so the chart claims nothing and a swipe
            // across it scrolls the page exactly as if it weren't there.
            // `.subviews` and not `.none`: `.none` also disables the SIBLING
            // gestures, which is what silently killed the scrubber before.
            if scrubMode == .drag {
                // Full screen: no page scroll to protect, and the armed drag
                // auto-pans so the scrubbed point stays centered while zoomed.
                plot
                    .simultaneousGesture(zoomGesture(rect))
                    .simultaneousGesture(scrubDragGesture(rect, autoPan: true),
                                         including: scrubArmed ? .all : .subviews)
                    .simultaneousGesture(armGesture(rect))
            } else {
                // Inline card (inside a ScrollView): pinch zoom + (when zoomed,
                // and NOT armed) horizontal pan. Arming hands the horizontal
                // drag to the scrubber so the two can't fight over it.
                plot
                    .simultaneousGesture(zoomGesture(rect))
                    .simultaneousGesture(panGesture(rect),
                                         including: (zoom > 1 && !scrubArmed) ? .all : .subviews)
                    .simultaneousGesture(scrubDragGesture(rect),
                                         including: scrubArmed ? .all : .subviews)
                    .simultaneousGesture(armGesture(rect))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: height == nil ? .infinity : nil)
        .frame(height: height)
    }

    // MARK: gestures

    private func zoomGesture(_ rect: CGRect) -> some Gesture {
        MagnificationGesture()
            .onChanged { v in
                zoom = min(max(lastZoom * v, 1), 8)
                panOffset = clampedPan(rect)
            }
            .onEnded { _ in
                lastZoom = zoom
                if zoom <= 1 { panOffset = 0; lastPan = 0 }
                lastPan = panOffset
            }
    }

    private func panGesture(_ rect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { v in
                panOffset = min(max(lastPan + v.translation.width,
                                    rect.width - contentW(rect)), 0)
            }
            .onEnded { _ in lastPan = panOffset }
    }

    /// Double-tap arms (and places) the scrubber; double-tap again puts it
    /// away. `SpatialTapGesture` so the crosshair lands where you tapped
    /// instead of at some arbitrary default — the tap IS the first placement,
    /// and the drag that follows is only fine-tuning.
    private func armGesture(_ rect: CGRect) -> some Gesture {
        SpatialTapGesture(count: 2)
            .onEnded { e in
                if scrubArmed {
                    scrubArmed = false
                    scrub = nil
                } else {
                    scrubArmed = true
                    setScrub(e.location.x, rect)
                }
            }
    }

    /// The armed scrubber. `minimumDistance: 4` so the two taps that arm it
    /// aren't swallowed as a zero-distance drag, and the crosshair is LEFT in
    /// place on lift — the athlete reads the values after the finger is gone.
    ///
    /// Inline (`.hold`, inside a ScrollView) a decidedly VERTICAL drag is left
    /// alone: armed or not, scrolling the page past the chart must not drag the
    /// crosshair sideways with it. Full-screen there's no page to scroll, so
    /// every direction scrubs.
    private func scrubDragGesture(_ rect: CGRect, autoPan: Bool = false) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { v in
                if scrubMode == .hold {
                    let dx = abs(v.translation.width), dy = abs(v.translation.height)
                    if dy > 24 && dy > dx { return }
                }
                setScrub(v.location.x, rect, autoPan: autoPan)
            }
    }

    /// Maps a touch x-position to a 0–1 scrub fraction (accounting for zoom +
    /// pan) and, in drag mode, keeps the scrubbed point centered while zoomed.
    private func setScrub(_ locX: CGFloat, _ rect: CGRect, autoPan: Bool = false) {
        let cw = contentW(rect)
        let f = (locX - rect.minX - clampedPan(rect)) / max(cw, 1)
        let frac = min(max(Double(f), 0), 1)
        scrub = frac
        if autoPan && zoom > 1 {
            panOffset = min(max(rect.width / 2 - CGFloat(frac) * cw, rect.width - cw), 0)
            lastPan = panOffset
        }
    }

    // MARK: math

    private func range(_ m: TelemetryMetric) -> (lo: Double, hi: Double) {
        guard let vals = series[m], !vals.isEmpty else { return (0, 1) }
        switch m {
        case .pace:
            // Scale to MOVING pace, Strava-style. Standing/walking samples hit
            // the 720 s/mi clamp; letting them set the axis crushed the work
            // reps into a thin band at the top on interval days. Samples slower
            // than the slow bound pin to the bottom edge (see the clamped
            // fraction in yFor/plottedPoints). Downsample before sorting so
            // this stays cheap on per-second streams during scrub renders.
            let n = vals.count
            let k = max(1, n / 800)
            var moving: [Double] = []
            moving.reserveCapacity(n / k + 1)
            var i = 0
            while i < n {
                let v = vals[i]
                if v < 715 { moving.append(max(v, 200)) }
                i += k
            }
            guard moving.count > 5 else {
                // All-walking / no moving samples: fall back to the raw range.
                let c = vals.map { min(max($0, 200), 720) }
                return ((c.min() ?? 300) - 10, (c.max() ?? 360) + 10)
            }
            moving.sort()
            let fastest = moving[0]
            let slow = moving[min(Int(Double(moving.count - 1) * 0.90), moving.count - 1)]
            return (fastest - 15, max(slow, fastest + 45) + 15)
        case .heartRate:
            let dataLo = (vals.min() ?? 100) - 5
            let dataHi = (vals.max() ?? 180) + 5
            // When the zone overlay is on, span the FULL zone ladder so Z4/Z5
            // always render even on an easy run that never reached them. Floor
            // dips into Z1 for context; ceiling is maxHR (≈ Z5.lo / 0.95, since
            // rr_zones sets Z5's lower bound at 0.95·maxHR) — never the 240
            // sentinel that Z5.hi carries.
            if showZones, let z1 = zones.first, let z5 = zones.last {
                let maxHR = (Double(z5.lo) / 0.95).rounded()
                let floor = min(dataLo, Double(z1.hi) - 4)
                return (floor, max(dataHi, maxHR))
            }
            return (dataLo, dataHi)
        case .cadence:
            // Ignore dropout zeros (stops) when picking the floor — they made
            // the axis read "-6" and crushed the running band. Dropouts still
            // draw, pinned to the bottom edge.
            let nz = vals.filter { $0 > 40 }
            let lo = (nz.min() ?? vals.min() ?? 150) - 6
            return (max(lo, 0), (nz.max() ?? vals.max() ?? 190) + 6)
        case .elevation: return ((vals.min() ?? 0) - 10, (vals.max() ?? 100) + 20)
        }
    }

    private func xFor(_ t: Double, _ rect: CGRect) -> CGFloat {
        rect.minX + clampedPan(rect) + CGFloat(t / total) * contentW(rect)
    }
    /// Vertical position. Pace inverts so faster (smaller sec) sits higher.
    /// The fraction is clamped so samples outside the axis range (walking
    /// recoveries, cadence dropouts) pin to the panel edge instead of drawing
    /// off-plot — the axis now scales to the meaningful band, not the extremes.
    private func yFor(_ value: Double, _ m: TelemetryMetric, _ rect: CGRect) -> CGFloat {
        let r = range(m)
        let v = (m == .pace) ? min(max(value, 200), 720) : value
        let t = (m == .pace) ? (r.hi - v) / max(r.hi - r.lo, 0.0001)
                             : (v - r.lo) / max(r.hi - r.lo, 0.0001)
        return rect.maxY - CGFloat(min(max(t, 0), 1)) * rect.height
    }

    private func index(_ frac: Double) -> Int? {
        guard times.count > 1 else { return nil }
        return min(max(Int((frac * Double(times.count - 1)).rounded()), 0), times.count - 1)
    }

    private func plottedPoints(_ m: TelemetryMetric, _ rect: CGRect) -> [CGPoint] {
        guard var vals = series[m], !vals.isEmpty, times.count > 1 else { return [] }
        // Heavier smoothing (was win:3) so the pace line reads calmer / more
        // Garmin-like without flattening interval reps.
        if m == .pace { vals = rr_smooth(vals, win: 5) }
        let n = min(vals.count, times.count)
        guard n > 1 else { return [] }

        // Compute the metric's range ONCE here, not once per point. `yFor`
        // recomputed it for every sample, making this O(n²) and freezing the
        // main thread for seconds on long runs. The transform is now O(n).
        let r = range(m)
        let span = max(r.hi - r.lo, 0.0001)
        let cw = contentW(rect)
        let panX = rect.minX + clampedPan(rect)
        let isPace = (m == .pace)

        // Downsample to ~the chart's pixel width (capped). Drawing thousands of
        // per-second samples into a few-hundred-pixel chart is invisible work;
        // capping keeps every pan/zoom/scrub frame cheap even when zoomed in.
        let cap = min(max(Int(cw), 120), 800)
        let step = max(1, n / cap)

        func point(_ i: Int) -> CGPoint {
            let raw = vals[i]
            let v = isPace ? min(max(raw, 200), 720) : raw
            let frac = isPace ? (r.hi - v) / span : (v - r.lo) / span
            // Clamp so out-of-range samples pin to the panel edge (see yFor).
            return CGPoint(x: panX + CGFloat(times[i] / total) * cw,
                           y: rect.maxY - CGFloat(min(max(frac, 0), 1)) * rect.height)
        }

        var out: [CGPoint] = []
        out.reserveCapacity(n / step + 2)
        var i = 0
        while i < n { out.append(point(i)); i += step }
        if (n - 1) % step != 0 { out.append(point(n - 1)) }  // always reach the end
        return out
    }

    // MARK: drawing

    /// Round-number y-axis tick VALUES for a metric (Strava-style: 100/120/140
    /// bpm, 6:00/6:30/7:00 pace — never "4:11" or "-6 spm"). Picks the smallest
    /// metric-appropriate step that yields at most ~5 gridlines, then walks
    /// multiples of it across the axis range.
    private func tickValues(_ m: TelemetryMetric) -> [Double] {
        let r = range(m)
        let span = max(r.hi - r.lo, 0.0001)
        let steps: [Double]
        switch m {
        case .heartRate: steps = [5, 10, 20, 25, 50]
        case .pace:      steps = [15, 30, 60, 120, 300]     // sec/mi
        case .cadence:   steps = [5, 10, 20, 25, 50]
        case .elevation: steps = [10, 25, 50, 100, 250, 500]
        }
        let step = steps.first { span / $0 <= 5.5 } ?? steps.last!
        var t = (r.lo / step).rounded(.up) * step
        var out: [Double] = []
        while t <= r.hi + span * 0.001 { out.append(t); t += step }
        return out
    }

    /// Horizontal gridlines at round tick values, plus the baseline — fixed
    /// behind the scrollable content.
    private func gridLines(_ rect: CGRect) -> some View {
        ZStack {
            Path { p in p.move(to: .init(x: rect.minX, y: rect.maxY)); p.addLine(to: .init(x: rect.maxX, y: rect.maxY)) }
                .stroke(Color.drip.divider, lineWidth: 1)
            if let lead {
                ForEach(tickValues(lead), id: \.self) { v in
                    let y = yFor(v, lead, rect)
                    if y < rect.maxY - 2 {
                        Path { p in p.move(to: .init(x: rect.minX, y: y)); p.addLine(to: .init(x: rect.maxX, y: y)) }
                            .stroke(Color.drip.divider.opacity(0.55), lineWidth: 0.5)
                    }
                }
            }
        }
    }

    /// Horizontal HR-zone bands across the full plot width, mapped onto the HR
    /// y-axis. Fixed (don't pan with the trace) and clamped to the plot rect so
    /// only the in-range slice of each zone paints.
    private func zoneBands(_ rect: CGRect) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(zones) { z in
                let yHi = yFor(Double(z.hi), .heartRate, rect)
                let yLo = yFor(Double(z.lo), .heartRate, rect)
                let top = max(min(yHi, yLo), rect.minY)
                let bot = min(max(yHi, yLo), rect.maxY)
                if bot - top > 0.5 {
                    // Kept light — at 0.16 the stacked bands tinted the whole
                    // panel and muddied the trace.
                    Rectangle().fill(z.color.opacity(0.10))
                        .frame(width: rect.width, height: bot - top)
                        .position(x: rect.midX, y: (top + bot) / 2)
                }
            }
        }
    }

    /// Lead-metric y-axis value labels + unit caption — fixed on top so they
    /// stay readable while the trace pans underneath.
    private func axisLabels(_ rect: CGRect) -> some View {
        ZStack(alignment: .topLeading) {
            if let lead {
                if showZones && lead == .heartRate {
                    // Zone tags replace the bpm ladder — the bands carry the
                    // numbers' job, so the gutter just names Z1–Z5.
                    ForEach(zones) { z in
                        let yHi = yFor(Double(z.hi), .heartRate, rect)
                        let yLo = yFor(Double(z.lo), .heartRate, rect)
                        let top = max(min(yHi, yLo), rect.minY)
                        let bot = min(max(yHi, yLo), rect.maxY)
                        if bot - top > 10 {
                            Text(z.id)
                                .font(.dripStat(12)).foregroundStyle(z.color)
                                .position(x: rect.minX - 17, y: (top + bot) / 2)
                        }
                    }
                    Text("HR · ZONES")
                        .font(.dripStat(11)).tracking(0.5).foregroundStyle(Color.drip.textSecondary)
                        .position(x: rect.minX + 34, y: rect.minY - 10)
                } else {
                    ForEach(tickValues(lead), id: \.self) { v in
                        let y = yFor(v, lead, rect)
                        if y > rect.minY - 2 && y < rect.maxY + 2 {
                            Text(axisLabel(v, lead))
                                .font(.dripStat(12)).foregroundStyle(lead.color.opacity(0.85))
                                .position(x: rect.minX - 22, y: y)
                        }
                    }
                    Text("\(lead.shortLabel.uppercased()) · \(unit(lead))")
                        .font(.dripStat(11)).tracking(0.5).foregroundStyle(lead.color.opacity(0.7))
                        .position(x: rect.minX + 32, y: rect.minY - 10)
                }
            }
        }
    }

    private func repBands(_ rect: CGRect) -> some View {
        ForEach(windows) { win in
            let x0 = xFor(win.start, rect), x1 = xFor(win.end, rect)
            // Highlight the rep the readout is currently parked on.
            let selected: Bool = {
                guard let s = scrub, total > 0 else { return false }
                let t = s * total
                return t >= win.start && t <= win.end
            }()
            ZStack(alignment: .top) {
                Rectangle().fill(Color.drip.coral.opacity(selected ? 0.18 : 0.08))
                    .frame(width: max(x1 - x0, 1), height: rect.height)
                    .position(x: (x0 + x1) / 2, y: rect.minY + rect.height / 2)
                    // Tap a rep to jump the readout (and highlight) to it.
                    .contentShape(Rectangle())
                    .onTapGesture {
                        let center = (win.start + win.end) / 2
                        scrub = total > 0 ? min(max(center / total, 0), 1) : nil
                    }
                if x1 - x0 > 16 {
                    Text("R\(win.id)")
                        .font(.dripStat(13))
                        .foregroundStyle(Color.drip.coral.opacity(selected ? 1 : 0.75))
                        .position(x: (x0 + x1) / 2, y: rect.minY + 8)
                }
            }
        }
    }

    /// Average pace within a rep window, clamped to the chart's pace bounds.
    private func repAvgPace(_ win: RRWindow) -> Double? {
        guard let pace = series[.pace], !pace.isEmpty else { return nil }
        let n = min(pace.count, times.count)
        var sum = 0.0, count = 0
        for i in 0..<n where times[i] >= win.start && times[i] <= win.end {
            sum += min(max(pace[i], 200), 720); count += 1
        }
        return count > 0 ? sum / Double(count) : nil
    }

    /// One bar per rep, height = that rep's average pace on the pace axis
    /// (faster = taller). Toggled by the REP PACE chip; sits behind the traces.
    private func repPaceBars(_ rect: CGRect) -> some View {
        ForEach(windows) { win in
            if let p = repAvgPace(win) {
                let x0 = xFor(win.start, rect), x1 = xFor(win.end, rect)
                let y = yFor(p, .pace, rect)
                let w = max(x1 - x0, 2)
                let barColor = TelemetryMetric.pace.color
                ZStack(alignment: .top) {
                    Rectangle().fill(barColor.opacity(0.20))
                        .frame(width: w, height: max(rect.maxY - y, 1))
                        .position(x: (x0 + x1) / 2, y: (y + rect.maxY) / 2)
                    Rectangle().fill(barColor.opacity(0.85))
                        .frame(width: w, height: 2)
                        .position(x: (x0 + x1) / 2, y: y)
                    if w > 22 {
                        Text(rr_pace(p, km: km))
                            .font(.dripStat(8)).foregroundStyle(barColor)
                            .position(x: (x0 + x1) / 2, y: y - 8)
                    }
                }
            }
        }
    }

    /// Elapsed-time labels along the bottom (x) axis. Computes the time under
    /// each screen tick so labels stay correct while zoomed / panned.
    private func xAxisTimeLabels(_ rect: CGRect) -> some View {
        ForEach([0.0, 0.25, 0.5, 0.75, 1.0], id: \.self) { f in
            let x = rect.minX + CGFloat(f) * rect.width
            let dataFrac = (x - rect.minX - clampedPan(rect)) / max(contentW(rect), 1)
            let t = min(max(Double(dataFrac), 0), 1) * total
            Text(rr_clock(t))
                .font(.dripStat(12)).foregroundStyle(Color.drip.textTertiary)
                .position(x: min(max(x, rect.minX + 12), rect.maxX - 12), y: rect.maxY + 15)
        }
    }

    private func lines(_ rect: CGRect) -> some View {
        // non-lead first, lead last (on top)
        let order: [TelemetryMetric] = [.elevation, .cadence, .pace, .heartRate]
        return ZStack {
            ForEach(order.filter { active.contains($0) }) { m in
                let pts = plottedPoints(m, rect)
                let strokeColor = (showZones && m == .heartRate) ? Color.drip.textPrimary : m.color
                if pts.count > 1 {
                    if m == .elevation {
                        Path { p in
                            p.move(to: CGPoint(x: pts.first!.x, y: rect.maxY))
                            for pt in pts { p.addLine(to: pt) }
                            p.addLine(to: CGPoint(x: pts.last!.x, y: rect.maxY))
                            p.closeSubpath()
                        }
                        .fill(Color.drip.positive.opacity(0.12))
                    }
                    Path { p in
                        p.move(to: pts[0])
                        for pt in pts.dropFirst() { p.addLine(to: pt) }
                    }
                    .stroke(strokeColor.opacity(m == lead || m == .heartRate || m == .pace ? 1 : 0.78),
                            style: StrokeStyle(lineWidth: m == lead ? 2.0 : 1.3, lineCap: .round, lineJoin: .round))
                }
            }
        }
    }

    @ViewBuilder private func scrubLayer(_ rect: CGRect) -> some View {
        if let s = scrub, let idx = index(s) {
            let x = xFor(times[idx], rect)
            ZStack(alignment: .topLeading) {
                Path { p in p.move(to: .init(x: x, y: rect.minY)); p.addLine(to: .init(x: x, y: rect.maxY)) }
                    .stroke(Color.drip.textPrimary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                ForEach(Array(active).sorted { TelemetryMetric.priority.firstIndex(of: $0)! < TelemetryMetric.priority.firstIndex(of: $1)! }) { m in
                    if let vals = series[m], idx < vals.count {
                        let y = yFor(vals[idx], m, rect)
                        Circle().fill(m.color).frame(width: 7, height: 7)
                            .overlay(Circle().stroke(Color.drip.cardBackground, lineWidth: 1.6))
                            .position(x: x, y: y)
                    }
                }
            }
        }
    }

    private func tooltip(idx: Int, frac: Double, rect: CGRect, canvasWidth: CGFloat) -> some View {
        let x = xFor(times[idx], rect)
        return VStack(alignment: .leading, spacing: 4) {
            Text(rr_clock(times[idx]) + " elapsed")
                .font(.dripStat(9)).foregroundStyle(Color.white.opacity(0.8))
            ForEach(TelemetryMetric.priority.filter { active.contains($0) }) { m in
                if let vals = series[m], idx < vals.count {
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 2).fill(m.color).frame(width: 7, height: 7)
                        Text(m.shortLabel.uppercased())
                            .font(.dripStat(9)).foregroundStyle(Color.white.opacity(0.6))
                        Spacer(minLength: 8)
                        Text(axisLabel(vals[idx], m))
                            .font(.dripStat(11)).foregroundStyle(.white)
                    }
                }
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 7)
        // FIXED width — the rows contain a Spacer, so with only a `minWidth`
        // the box grew to fill the whole chart (the "black box" bug).
        .frame(width: 132, alignment: .leading)
        .background(Color(red: 26/255, green: 24/255, blue: 21/255).opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .position(x: min(max(x + 70, rect.minX + 70), canvasWidth - 70), y: rect.minY + 40)
        .allowsHitTesting(false)
    }

    // MARK: formatting

    private func axisLabel(_ v: Double, _ m: TelemetryMetric) -> String {
        switch m {
        case .heartRate: return "\(Int(v.rounded()))"
        case .pace:      return rr_pace(v, km: km)
        case .cadence:   return "\(Int(v.rounded()))"
        case .elevation: return "\(Int((km ? v * 0.3048 : v).rounded()))"
        }
    }
    private func unit(_ m: TelemetryMetric) -> String {
        switch m {
        case .heartRate: return "bpm"
        case .pace:      return km ? "/km" : "/mi"
        case .cadence:   return "spm"
        case .elevation: return km ? "m" : "ft"
        }
    }
}

// MARK: - Readout (session averages)

struct RRTelemetryReadout: View {
    let series: [TelemetryMetric: [Double]]
    let active: Set<TelemetryMetric>
    let km: Bool
    /// Time axis + current scrub fraction. When `scrub` is set, each cell shows
    /// the instantaneous value at that point instead of the session average.
    var times: [Double] = []
    var scrub: Double? = nil

    /// Sample index under the scrubber, or nil when at rest (show averages).
    private var scrubIdx: Int? {
        guard let s = scrub, times.count > 1 else { return nil }
        return min(max(Int((s * Double(times.count - 1)).rounded()), 0), times.count - 1)
    }
    private var scrubbing: Bool { scrubIdx != nil }

    var body: some View {
        VStack(spacing: 6) {
            caption
            HStack(spacing: 0) {
                cell(.heartRate, value: hrValue(),
                     unit: scrubbing ? "bpm" : "bpm avg")
                divider
                cell(.pace, value: paceValue(),
                     unit: scrubbing ? (km ? "/km" : "/mi") : (km ? "/km avg" : "/mi avg"))
                divider
                cell(.cadence, value: cadValue(),
                     unit: scrubbing ? "spm" : "spm avg")
                divider
                cell(.elevation, value: elevValue(),
                     unit: scrubbing ? (km ? "m" : "ft") : (km ? "m gain" : "ft gain"))
            }
        }
    }

    /// Tells the reader whether the strip is showing a live point or averages.
    @ViewBuilder private var caption: some View {
        if let idx = scrubIdx, idx < times.count {
            Text("AT \(rr_clock(times[idx])) ELAPSED")
                .font(.dripStat(8)).tracking(1.0)
                .foregroundStyle(Color.drip.coral)
        } else {
            Text("SESSION AVERAGE")
                .font(.dripStat(8)).tracking(1.0)
                .foregroundStyle(Color.drip.textTertiary)
        }
    }

    private var divider: some View {
        Rectangle().fill(Color.drip.divider).frame(width: 1, height: 30)
    }

    // Live value at the scrubbed point, falling back to the session average.
    private func hrValue() -> String {
        if let i = scrubIdx, let v = series[.heartRate], i < v.count { return "\(Int(v[i].rounded()))" }
        return avgInt(.heartRate)
    }
    private func cadValue() -> String {
        if let i = scrubIdx, let v = series[.cadence], i < v.count { return "\(Int(v[i].rounded()))" }
        return avgInt(.cadence)
    }
    private func paceValue() -> String {
        if let i = scrubIdx, let v = series[.pace], i < v.count {
            return rr_pace(min(max(v[i], 200), 720), km: km)
        }
        return avgPace()
    }
    private func elevValue() -> String {
        if let i = scrubIdx, let v = series[.elevation], i < v.count {
            return "\(Int((km ? v[i] * 0.3048 : v[i]).rounded()))"
        }
        return elevGain()
    }

    private func cell(_ metric: TelemetryMetric, value: String, unit: String) -> some View {
        let on = active.contains(metric)
        return VStack(spacing: 2) {
            Text(metric.shortLabel.uppercased())
                .font(.dripStat(8.5)).tracking(0.8).foregroundStyle(Color.drip.textTertiary)
            Text(value).font(.dripStat(16))
                .foregroundStyle(on ? metric.color : Color.drip.textTertiary)
                .monospacedDigit()
            Text(unit).font(.dripStat(8.5)).foregroundStyle(Color.drip.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .opacity(on ? 1 : 0.4)
    }

    private func avgInt(_ m: TelemetryMetric) -> String {
        guard let v = series[m], !v.isEmpty else { return "—" }
        return "\(Int((v.reduce(0, +) / Double(v.count)).rounded()))"
    }
    private func avgPace() -> String {
        guard let v = series[.pace], !v.isEmpty else { return "—" }
        let c = v.map { min(max($0, 200), 720) }
        return rr_pace(c.reduce(0, +) / Double(c.count), km: km)
    }
    private func elevGain() -> String {
        guard let v = series[.elevation], v.count > 1 else { return "—" }
        var gain = 0.0
        for i in 1..<v.count { let d = v[i] - v[i - 1]; if d > 0 { gain += d } }
        return "+\(Int((km ? gain * 0.3048 : gain).rounded()))"
    }
}

// MARK: - Fullscreen

struct RRTelemetryFullScreen: View {
    let times: [Double]
    let series: [TelemetryMetric: [Double]]
    @Binding var active: Set<TelemetryMetric>
    let availability: [TelemetryMetric: Bool]
    let windows: [RRWindow]
    let km: Bool
    var zones: [RRZone] = []
    @Binding var showRepPace: Bool
    @Binding var zonesOn: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var scrub: Double? = nil
    @State private var scrubArmed = false

    /// Panels that will actually render (mirrors RRStackedTelemetry.panels).
    private var panelCount: Int {
        TelemetryMetric.priority.filter { active.contains($0) && (series[$0]?.count ?? 0) > 1 }.count
    }
    /// With 1–2 charts everything fits the screen at a generous size, so we
    /// keep the fit-to-screen layout and the auto-panning scrubber. With 3+
    /// charts, squeezing them all on screen made each one unreadably short —
    /// instead every chart keeps a Strava-like ~240pt height and the page
    /// scrolls (scrubbing is armed by a double-tap either way, so an unarmed
    /// drag always scrolls).
    private var scrolls: Bool { panelCount > 2 }

    var body: some View {
        ZStack {
            Color.drip.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("The Effort").font(.dripDisplay(24)).foregroundStyle(Color.drip.textPrimary)
                    Spacer()
                    Button { dismiss() } label: {
                        Text("CLOSE").font(.dripStat(11)).tracking(1.0)
                            .foregroundStyle(Color.drip.coral)
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .overlay(Capsule().stroke(Color.drip.coral, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                RRTelemetryChips(active: $active, availability: availability,
                                 showRepPace: $showRepPace, repsAvailable: !windows.isEmpty,
                                 zonesOn: $zonesOn, zonesAvailable: !zones.isEmpty)
                if scrolls {
                    ScrollView(showsIndicators: false) {
                        RRStackedTelemetry(times: times, series: series, active: active,
                                           windows: windows, km: km, scrub: $scrub,
                                           scrubArmed: $scrubArmed,
                                           zones: zones, zonesOn: zonesOn, showRepPace: showRepPace,
                                           scrubMode: .hold, panelHeight: 240)
                            .padding(.bottom, 8)
                    }
                } else {
                    // Flexible height (`height: nil`) fills the screen. `.drag`
                    // scrub means an ARMED touch-and-drag moves the point and
                    // pans the zoomed axis to keep it centered.
                    RRStackedTelemetry(times: times, series: series, active: active,
                                       windows: windows, km: km, scrub: $scrub,
                                       scrubArmed: $scrubArmed,
                                       zones: zones, zonesOn: zonesOn, showRepPace: showRepPace,
                                       scrubMode: .drag, panelHeight: nil)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                Text(scrubArmed
                     ? "SCRUB ON · DRAG TO MOVE THE POINT · DOUBLE-TAP TO PUT IT AWAY"
                     : (scrolls ? "SCROLL FOR MORE · DOUBLE-TAP A PANEL TO SCRUB"
                                : "DOUBLE-TAP A PANEL TO SCRUB · TAP CLOSE TO RETURN"))
                    .font(.dripStat(9)).tracking(0.6).foregroundStyle(Color.drip.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(20)
        }
    }
}

// MARK: - Stacked panels (one metric per row, each owning its own axis)

/// The stacked-panel layout: one `RRStackPanel` per active metric, in priority
/// order, sharing a single scrub fraction so the crosshair lines up across
/// panels. Replaces the former single shared-axis chart — pace no longer rides
/// the HR axis, so every metric reads against the correct scale. The zone
/// overlay rides the HR panel; the rep-pace bars ride the pace panel.
struct RRStackedTelemetry: View {
    let times: [Double]
    let series: [TelemetryMetric: [Double]]
    let active: Set<TelemetryMetric>
    let windows: [RRWindow]
    let km: Bool
    @Binding var scrub: Double?
    /// Shared across every lane so a double-tap on one arms the whole stack —
    /// the lanes already share one crosshair, so they must share its switch.
    @Binding var scrubArmed: Bool
    var zones: [RRZone] = []
    var zonesOn: Bool = false
    var showRepPace: Bool = false
    var scrubMode: RRScrubMode = .hold
    /// Fixed per-panel height (inline). Pass `nil` to divide the available
    /// height across the visible panels (fullscreen, no page scroll).
    var panelHeight: CGFloat? = 148

    // Horizontal scroll shared by every lane, so they pan together on one time
    // axis. Seeded to `initialZoom` (>1 = wider-than-screen canvas, scrollable).
    @State private var zoom: CGFloat
    @State private var lastZoom: CGFloat
    @State private var panOffset: CGFloat = 0
    @State private var lastPan: CGFloat = 0

    init(times: [Double], series: [TelemetryMetric: [Double]], active: Set<TelemetryMetric>,
         windows: [RRWindow], km: Bool, scrub: Binding<Double?>,
         scrubArmed: Binding<Bool>,
         zones: [RRZone] = [], zonesOn: Bool = false, showRepPace: Bool = false,
         scrubMode: RRScrubMode = .hold, panelHeight: CGFloat? = 148, initialZoom: CGFloat = 1) {
        self.times = times
        self.series = series
        self.active = active
        self.windows = windows
        self.km = km
        self._scrub = scrub
        self._scrubArmed = scrubArmed
        self.zones = zones
        self.zonesOn = zonesOn
        self.showRepPace = showRepPace
        self.scrubMode = scrubMode
        self.panelHeight = panelHeight
        self._zoom = State(initialValue: initialZoom)
        self._lastZoom = State(initialValue: initialZoom)
    }

    /// Visible panels: active metrics that actually have a series, in the same
    /// priority order the single chart used (HR, pace, cadence, elevation).
    private var panels: [TelemetryMetric] {
        TelemetryMetric.priority.filter { active.contains($0) && (series[$0]?.count ?? 0) > 1 }
    }

    var body: some View {
        if let h = panelHeight {
            VStack(alignment: .leading, spacing: 18) { stack(h) }
        } else {
            GeometryReader { geo in
                let n = max(panels.count, 1)
                // Reserve ~40pt per header + 18pt inter-panel spacing, divide
                // the rest evenly so 2–4 panels always fit without clipping.
                let perPanel = max((geo.size.height - CGFloat(n) * 40 - CGFloat(n - 1) * 18) / CGFloat(n), 90)
                VStack(alignment: .leading, spacing: 18) { stack(perPanel) }
            }
        }
    }

    @ViewBuilder private func stack(_ h: CGFloat) -> some View {
        ForEach(Array(panels.enumerated()), id: \.element) { idx, m in
            RRStackPanel(metric: m, times: times, series: series, windows: windows,
                         km: km, scrub: $scrub, scrubArmed: $scrubArmed,
                         zones: m == .heartRate ? zones : [],
                         zonesOn: m == .heartRate ? zonesOn : false,
                         showRepPace: m == .pace ? showRepPace : false,
                         scrubMode: scrubMode,
                         showXAxisLabels: idx == panels.count - 1,
                         height: h,
                         zoom: $zoom, lastZoom: $lastZoom,
                         panOffset: $panOffset, lastPan: $lastPan)
        }
    }
}

/// One panel: metric eyebrow + avg/best (or live, while scrubbing) readout in
/// the header, then a single-metric chart locked to that metric so it owns its
/// own y-axis. Reuses the tuned `RRTelemetryChart` engine (rep bands, scrub,
/// zone overlay) rather than re-implementing it.
struct RRStackPanel: View {
    let metric: TelemetryMetric
    let times: [Double]
    let series: [TelemetryMetric: [Double]]
    let windows: [RRWindow]
    let km: Bool
    @Binding var scrub: Double?
    @Binding var scrubArmed: Bool
    var zones: [RRZone] = []
    var zonesOn: Bool = false
    var showRepPace: Bool = false
    var scrubMode: RRScrubMode = .hold
    var showXAxisLabels: Bool = true
    var height: CGFloat = 148
    // Shared scroll state (all lanes move together).
    @Binding var zoom: CGFloat
    @Binding var lastZoom: CGFloat
    @Binding var panOffset: CGFloat
    @Binding var lastPan: CGFloat

    private var values: [Double] { series[metric] ?? [] }

    /// Sample index under the shared scrubber, or nil at rest (show summary).
    private var scrubIdx: Int? {
        guard let s = scrub, times.count > 1 else { return nil }
        return min(max(Int((s * Double(times.count - 1)).rounded()), 0), times.count - 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            header
            RRTelemetryChart(times: times, series: series, active: [metric],
                             windows: windows, km: km, scrub: $scrub,
                             scrubArmed: $scrubArmed,
                             height: height, scrubMode: scrubMode,
                             showRepPace: showRepPace,
                             zones: zones, zonesOn: zonesOn,
                             showTooltip: false, showXAxisLabels: showXAxisLabels,
                             zoom: $zoom, lastZoom: $lastZoom,
                             panOffset: $panOffset, lastPan: $lastPan)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(metric.label.uppercased())
                .font(.dripStat(13)).tracking(1.2)
                .foregroundStyle(metric.color)
            Spacer()
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                readoutPair(primaryValue, primaryCaption)
                if let s = secondaryValue, let c = secondaryCaption {
                    readoutPair(s, c)
                }
            }
        }
    }

    private func readoutPair(_ value: String, _ caption: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(value).font(.dripDisplay(28)).foregroundStyle(Color.drip.textPrimary)
                .monospacedDigit()
            Text(caption).font(.dripStat(10)).tracking(0.5)
                .foregroundStyle(Color.drip.textTertiary)
        }
    }

    // MARK: readout values

    private var primaryValue: String {
        if let i = scrubIdx, i < values.count { return liveString(values[i]) }
        switch metric {
        case .heartRate, .cadence: return avgInt()
        case .pace:                return avgPace()
        case .elevation:           return elevGain()
        }
    }
    private var primaryCaption: String {
        if let i = scrubIdx, i < times.count { return "AT \(rr_clock(times[i]))" }
        switch metric {
        case .elevation: return km ? "M GAIN" : "FT GAIN"
        default:         return "AVG"
        }
    }
    private var secondaryValue: String? {
        guard scrubIdx == nil else { return nil }
        switch metric {
        case .heartRate: return maxInt()
        case .pace:      return bestPace()
        default:         return nil
        }
    }
    private var secondaryCaption: String? {
        guard scrubIdx == nil else { return nil }
        switch metric {
        case .heartRate: return "MAX"
        case .pace:      return "BEST"
        default:         return nil
        }
    }

    // MARK: formatting (mirrors RRTelemetryReadout / RRTelemetryChart)

    private func liveString(_ v: Double) -> String {
        switch metric {
        case .heartRate, .cadence: return "\(Int(v.rounded()))"
        case .pace:                return rr_pace(min(max(v, 200), 720), km: km)
        case .elevation:           return "\(Int((km ? v * 0.3048 : v).rounded()))"
        }
    }
    private func avgInt() -> String {
        guard !values.isEmpty else { return "0" }
        return "\(Int((values.reduce(0, +) / Double(values.count)).rounded()))"
    }
    private func maxInt() -> String {
        guard let m = values.max() else { return "0" }
        return "\(Int(m.rounded()))"
    }
    private func avgPace() -> String {
        guard !values.isEmpty else { return "0:00" }
        let c = values.map { min(max($0, 200), 720) }
        return rr_pace(c.reduce(0, +) / Double(c.count), km: km)
    }
    private func bestPace() -> String {
        let c = values.map { min(max($0, 200), 720) }
        guard let best = c.min() else { return "0:00" }
        return rr_pace(best, km: km)
    }
    private func elevGain() -> String {
        guard values.count > 1 else { return "0" }
        var gain = 0.0
        for i in 1..<values.count { let d = values[i] - values[i - 1]; if d > 0 { gain += d } }
        return "+\(Int((km ? gain * 0.3048 : gain).rounded()))"
    }
}

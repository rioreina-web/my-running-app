//
//  WorkoutReceiptCharts.swift
//  RunningLog
//
//  Hand-drawn (GeometryReader / Path) chart kit for the dense "Rep Receipt"
//  workout detail (Direction A of the Workout Detail Redesign). No chart
//  dependency. All charts read the Post Run Drip tokens (Color.drip / Font.drip)
//  and the per-second Strava streams already loaded via ExternalStreamAdapter.
//
//  Charts here:
//    • RRRepBars         — hero rep chart: width ∝ distance, height ∝ speed,
//                          avg-HR line riding the tops, target dashed refs,
//                          rest gaps to scale.
//    • RRZoneTimeline    — HR over the full session, zone bands, rep windows.
//    • RRPaceTrace       — smoothed pace/velocity trace, rep windows shaded.
//    • RRCadenceStrip    — cadence over time + avg line.
//    • RRElevationGrade  — elevation area, grade-tinted columns.
//    • RRRecoveryRow     — small-multiples HR drop in each post-rep rest.
//    • RRZoneBar         — stacked time-in-HR-zone bar + legend grid.
//    • RRRouteShape      — route line colored by work/easy (or HR zone) + rep pins.
//
//  Shared models + helpers (rr_*) at the bottom are used by both this file
//  and WorkoutRepReceiptView.swift.
//

import SwiftUI
import CoreLocation

// MARK: - Shared models

/// One work rep distilled for the receipt charts.
struct RRRep: Identifiable {
    let id: Int          // rep number (1-based)
    let label: String    // "2K" / "1K" / "1mi"
    let distMi: Double
    let paceSec: Double   // sec/mi
    let hr: Int?
    let cad: Int?
    let restSec: Int?     // rest that FOLLOWS this rep (nil for last)
    let adjPaceSec: Double? // heat-adjusted pace, sec/mi (nil if none)
    var durSec: Int? = nil  // actual split time for this rep, seconds
    var elevFt: Int? = nil  // net elevation gain over the split, feet
    // The recovery that FOLLOWS this rep, so the splits table can render it as
    // its own interval row. `restSec` is its duration; these carry its pace and
    // HR when the rest lap actually moved (a jog) — nil for a standing rest.
    var restPaceSec: Double? = nil  // recovery jog pace, sec/mi
    var restHR: Int? = nil          // avg HR during the recovery
}

/// A work-rep time window inside the stream, for shading the timelines.
struct RRWindow: Identifiable { let id: Int; let start: Double; let end: Double }

/// HR drop in the rest after one rep.
struct RRRecovery: Identifiable { let id: Int; let drop: Int; let endHR: Int; let pts: [Int] }

/// An HR zone band.
struct RRZone: Identifiable { let id: String; let lo: Int; let hi: Int; let color: Color }

// MARK: - 1 · Hero rep bars

/// Absolute pace → colour anchors. Colour encodes the *pace zone*, not the
/// rank within a single workout, so the same pace reads the same colour in
/// every chart. Matches the Volume × Pace chart axis (8:00 easy/pale end →
/// 4:30 fastest/navy end) and shares the universal blue depth ramp with
/// `PaceSpectrum` / `IntensityRamp`. A later pass can swap these fixed
/// bounds for the athlete's `EquivalentPaces` zone paces.
/// Pace → colour scale for the rep charts. Colour encodes the pace zone
/// (absolute, not within-run rank). The pace axis is *warped*: the broad
/// easy/moderate range (8:00–6:00) fills the left half, and the fast zones
/// (6:00–4:30) spread across the right. That (a) gives the pale base more
/// room, (b) lands MP mid-blue, LT deeper, mile on navy, and (c) lets the
/// legend ruler sit on round, evenly-spaced ticks (8:00·7:00·6:00·5:00·4:30).
enum PaceZoneScale {
    /// Warp anchors (pace sec/mi → position 0…1). Piecewise-linear between.
    private static let warp: [(pace: Double, pos: Double)] = [
        (480, 0.00),   // 8:00
        (360, 0.50),   // 6:00
        (300, 0.75),   // 5:00
        (270, 1.00),   // 4:30
    ]

    /// Colour stops by position (0 = slow/pale … 1 = fast/navy).
    /// Single-hue blue depth ramp — mirrors `PaceSpectrum.stops`.
    private static let stops: [(pos: Double, r: Double, g: Double, b: Double)] = [
        (0.00, 147, 185, 214),  // pale sky — easy
        (0.30, 147, 185, 214),  // pale held — "farther over"
        (0.42,  87, 143, 192),  // steady
        (0.50,  63, 124, 181),  // MP (6:00)
        (0.5625, 47, 102, 168), // HMP
        (0.625,  39,  84, 155), // LT (5:30)
        (0.75,  14,  29,  78),  // navy — mile (5:00)
        (1.00,  10,  21,  56),  // deepest navy — fastest (4:30)
    ]

    /// Warped position 0…1 for an absolute pace.
    static func pos(forPaceSec pace: Double) -> Double {
        let p = min(max(pace, warp.last!.pace), warp.first!.pace)
        for i in 0..<(warp.count - 1) {
            let a = warp[i], b = warp[i + 1]
            if p <= a.pace && p >= b.pace {
                let t = (a.pace - p) / (a.pace - b.pace)
                return a.pos + (b.pos - a.pos) * t
            }
        }
        return p >= warp.first!.pace ? 0 : 1
    }

    private static func color(atPos x: Double) -> Color {
        let pos = min(max(x, 0), 1)
        for i in 0..<(stops.count - 1) {
            let a = stops[i], b = stops[i + 1]
            if pos >= a.pos && pos <= b.pos {
                let t = b.pos == a.pos ? 0 : (pos - a.pos) / (b.pos - a.pos)
                return Color(red: (a.r + (b.r - a.r) * t) / 255,
                             green: (a.g + (b.g - a.g) * t) / 255,
                             blue: (a.b + (b.b - a.b) * t) / 255)
            }
        }
        let l = stops.last!
        return Color(red: l.r / 255, green: l.g / 255, blue: l.b / 255)
    }

    /// Colour for an absolute pace (sec/mi).
    static func color(forPaceSec pace: Double) -> Color { color(atPos: pos(forPaceSec: pace)) }

    /// Warm grey for recovery / very-easy segments — anything run slower than
    /// `recoveryGreyFracOfMP` of marathon-pace SPEED. These shouldn't sit on the
    /// work-pace spectrum; greying them lets the actual reps pop.
    static let recoveryGrey = Color(red: 0.64, green: 0.62, blue: 0.59)
    static let recoveryGreyFracOfMP = 0.5  // 50% of MP speed

    /// Colour for a pace, greying out anything slower than 50% of MP speed
    /// (i.e. pace slower than mpSec / frac = 2× MP pace). `mpSec == nil` disables
    /// the grey rule and falls back to the normal spectrum.
    static func color(forPaceSec pace: Double, mpSec: Double?) -> Color {
        if let mp = mpSec, mp > 0, pace > mp / recoveryGreyFracOfMP { return recoveryGrey }
        return color(forPaceSec: pace)
    }

    /// Warped legend gradient — pale blue broad on the left, navy at the right.
    static var gradient: LinearGradient {
        LinearGradient(gradient: Gradient(stops: stops.map { s in
            .init(color: Color(red: s.r / 255, green: s.g / 255, blue: s.b / 255), location: s.pos)
        }), startPoint: .leading, endPoint: .trailing)
    }

    /// Ruler ticks (sec/mi) — round and evenly spaced thanks to the warp.
    static let rulerTicks: [Double] = [480, 420, 360, 300, 270]  // 8:00·7:00·6:00·5:00·4:30
}

struct RRRepBars: View {
    let reps: [RRRep]
    let targetSec: Double
    let colorByZone: Bool
    /// When true, each bar is colored by its pace along the blue depth
    /// ramp. When `colorByZone` is on it wins instead; otherwise a single
    /// coral accent. Defaults true.
    var colorByPace: Bool = true
    let heatOn: Bool
    let km: Bool
    let zones: [RRZone]
    /// HR recovery after each rep (interval reps only) — keyed by rep id.
    var recoveries: [RRRecovery] = []
    /// Elevation profile overlay toggle. (HR lives in its own HR & DRIFT
    /// section now, not on these bars.)
    var showElev = true
    /// Compress the whole strip to fit the plot width instead of holding a
    /// readable floor and scrolling. Width stays proportional to distance, so
    /// short reps read as slivers next to a long warmup — the honest, whole-
    /// workout picture on one screen.
    var fitToWidth = false

    /// Elevation-profile honesty floors, in feet.
    ///
    /// A barometric altimeter drifts a foot or two per lap even on a flat
    /// track. Scaling the profile to the data range alone stretched that
    /// noise across half the plot, so a track session rendered as a mountain
    /// range. `elevDrawFloorFt` is the spread below which a run counts as
    /// flat and the profile is not drawn at all; `elevMinRangeFt` is the
    /// tightest the scale may ever zoom once it does draw, so a 20 ft roller
    /// can't be shown the way a 400 ft climb is.
    private static let elevDrawFloorFt: Double = 15
    private static let elevMinRangeFt: Double = 60

    /// Tap-selected rep id; drives the readout + bar highlight.
    @State private var selected: Int?

    private func pace(_ r: RRRep) -> Double { heatOn ? (r.adjPaceSec ?? r.paceSec) : r.paceSec }

    /// The heat-adjusted (neutral-air equivalent) pace for a rep — what the
    /// tap readout shows BESIDE the raw split pace, never instead of it. The
    /// bars move to the adjusted scale when HEAT-ADJ is on, so the readout
    /// used to show a number that silently wasn't the pace on the watch.
    /// Nil when the toggle is off, when the rep carries no adjustment, or
    /// when the adjustment rounds to the same displayed pace — an ADJ cell
    /// identical to PACE is noise, not information.
    private func adjPace(_ r: RRRep) -> Double? {
        guard heatOn, let a = r.adjPaceSec, a > 0 else { return nil }
        return abs(a - r.paceSec) >= 1 ? a : nil
    }

    /// The dashed reference line. With HEAT-ADJ on, use the adjusted mean so the
    /// line tracks the (faster) bars instead of sitting at the raw average —
    /// otherwise the raw avg falls outside the adjusted axis and vanishes.
    private var avgLineSec: Double {
        guard heatOn else { return targetSec }
        let ps = reps.map(pace)
        return ps.isEmpty ? targetSec : ps.reduce(0, +) / Double(ps.count)
    }

    private func clockMS(_ s: Int) -> String {
        s < 60 ? String(format: "0:%02d", s) : String(format: "%d:%02d", s / 60, s % 60)
    }
    private func splitSec(_ r: RRRep) -> Int { r.durSec ?? Int((r.paceSec * r.distMi).rounded()) }

    /// Aerobic decoupling at rep `i` vs the first rep with HR: how far the
    /// HR-to-speed ratio has drifted (positive = HR rising for the same pace).
    private func decoupling(_ i: Int) -> Int? {
        guard i < reps.count, let hr = reps[i].hr, hr > 0 else { return nil }
        guard let base = reps.first(where: { ($0.hr ?? 0) > 0 }), let bhr = base.hr, bhr > 0 else { return nil }
        let effBase = (1.0 / max(base.paceSec, 1)) / Double(bhr)
        let eff = (1.0 / max(reps[i].paceSec, 1)) / Double(hr)
        guard effBase > 0 else { return nil }
        return Int(((effBase - eff) / effBase * 100).rounded())
    }

    private func repIndex(at x: CGFloat, layout: [(x: CGFloat, w: CGFloat)]) -> Int? {
        var idx: Int?
        for (i, l) in layout.enumerated() { if x >= l.x { idx = i } else { break } }
        return idx
    }

    var body: some View {
        VStack(spacing: 8) {
            if let sel = selected, sel < reps.count {
                readout(reps[sel], index: sel)
            } else {
                legendBar
            }
            GeometryReader { geo in
                let yAxisW: CGFloat = 34
                let labelH: CGFloat = 15
                let plotH = geo.size.height - labelH
                let plotW = geo.size.width - yAxisW

                // Pace axis (faster sits higher), rounded to clean gridlines.
                // Bracket the range to the WORK reps: recovery/warmup jogs run
                // minutes/mile slower and would otherwise stretch the axis into
                // a cluttered 30-min ladder. Slow laps still draw (clamped to a
                // nub at the base) — they just don't drive the scale. Frames the
                // fast cluster the way Strava does, with ~4 clean gridlines.
                //
                // The axis spans BOTH the raw and the heat-adjusted pace of
                // every rep, so it is the SAME axis whether HEAT-ADJ is on or
                // off. Deriving it from the toggled pace is what made the
                // toggle look inert: on a continuous run every split earns the
                // same percentage credit, so the axis rescaled by exactly as
                // much as the bars moved and the chart came out pixel-identical
                // — only the tick labels changed. Held still, the bars visibly
                // rise when the toggle goes on.
                let allPaces = reps.flatMap { r -> [Double] in
                    guard let adj = r.adjPaceSec, adj > 0 else { return [r.paceSec] }
                    return [r.paceSec, adj]
                }
                let fastest = allPaces.min() ?? 240
                let work = allPaces.filter { $0 <= fastest * 1.6 }
                let paces = work.count >= 2 ? work : allPaces
                let dataMin = paces.min() ?? 240
                let dataMax = paces.max() ?? 300
                let spread = max(dataMax - dataMin, 1)
                let rawStep = (spread + 12) / 4
                let step: Double = [10.0, 15, 20, 30, 45, 60, 90, 120].first { $0 >= rawStep } ?? 120
                let axisMin = (max(dataMin - 4, 1) / step).rounded(.down) * step
                let axisMax = ((dataMax + 6) / step).rounded(.up) * step
                let axisSpan = max(axisMax - axisMin, 1)
                let ticks = stride(from: axisMin, through: axisMax + 0.5, by: step).map { $0 }

                // Bar WIDTH encodes rep distance; the GAP after each bar
                // encodes its rest, scaled to that rep's own length. Bars fit
                // the plot when they can, otherwise the smallest holds a
                // readable floor and the strip scrolls (axis stays pinned).
                let info = barLayout(plotW: plotW)

                HStack(spacing: 0) {
                    paceAxis(ticks: ticks, axisMin: axisMin, axisSpan: axisSpan, plotH: plotH)
                        .frame(width: yAxisW)
                    let plot = plotCanvas(width: info.scrolling ? info.contentW : plotW,
                                          layout: info.layout, selected: selected, plotH: plotH, labelH: labelH,
                                          axisMin: axisMin, axisSpan: axisSpan, ticks: ticks)
                        .contentShape(Rectangle())
                        .gesture(SpatialTapGesture().onEnded { e in
                            let i = repIndex(at: e.location.x, layout: info.layout)
                            selected = (i == selected) ? nil : i
                        })
                    if info.scrolling {
                        ScrollView(.horizontal, showsIndicators: false) { plot }
                    } else {
                        plot
                    }
                }
            }
            .frame(height: 172)
        }
    }

    /// Pinned pace axis — labels at each gridline, aligned to the plot's scale.
    private func paceAxis(ticks: [Double], axisMin: Double, axisSpan: Double, plotH: CGFloat) -> some View {
        GeometryReader { g in
            ForEach(ticks, id: \.self) { tv in
                let y = CGFloat((tv - axisMin) / axisSpan) * plotH
                Text(rr_pace(tv, km: km)).font(.dripStat(8))
                    .foregroundStyle(Color.drip.textTertiary)
                    .position(x: g.size.width - 15, y: y)
            }
        }
    }

    /// Distance-proportional bar layout. Each bar's width tracks its rep
    /// distance (a 1200m reads ~6× a 200m). If the smallest bar would fall
    /// below a readable floor, the whole strip scales up and scrolls instead
    /// of cramming everything into the viewport.
    private func barLayout(plotW: CGFloat) -> (layout: [(x: CGFloat, w: CGFloat)], contentW: CGFloat, scrolling: Bool) {
        let n = max(reps.count, 1)
        let dist = reps.map { max($0.distMi, 0.0001) }
        // Rest after each rep, expressed relative to that rep's own duration,
        // so the gap reads as long as the rest felt next to the effort. A
        // continuous run (no rest) collapses to flush bars.
        let restRatio = reps.map { r -> Double in
            let dur = Double(r.durSec ?? Int(max(r.paceSec * r.distMi, 1)))
            return Double(r.restSec ?? 0) / max(dur, 1)
        }
        // A small constant gap separates every bar (even flush continuous
        // splits) so each split reads as its own; rest adds to it on intervals.
        let baseGap: CGFloat = 2
        let totalBase = baseGap * CGFloat(max(n - 1, 0))
        let restUnits = (0..<n).reduce(0.0) { $0 + ($1 < n - 1 ? dist[$1] * restRatio[$1] : 0) }
        let sumUnits = max(dist.reduce(0, +) + restUnits, 0.0001)
        let minDist = max(dist.min() ?? 0.0001, 0.0001)
        let fitScale = max(plotW - totalBase, 1) / CGFloat(sumUnits)
        let floor: CGFloat = 16
        // fitToWidth forces the whole strip onto the screen — never scroll,
        // even when that pushes short reps below the readable floor.
        let scrolling = fitToWidth ? false : (fitScale * CGFloat(minDist) < floor)
        let scale = scrolling ? floor / CGFloat(minDist) : fitScale
        var layout: [(x: CGFloat, w: CGFloat)] = []
        var x: CGFloat = 0
        for i in 0..<n {
            let bw = max(CGFloat(dist[i]) * scale, 2)
            layout.append((x: x, w: bw))
            x += bw
            if i < n - 1 { x += baseGap + CGFloat(dist[i] * restRatio[i]) * scale }
        }
        let lastEnd = layout.last.map { $0.x + $0.w } ?? plotW
        let contentW = scrolling ? lastEnd : plotW
        return (layout, contentW, scrolling)
    }

    /// The scrollable plot: faint gridlines, a translucent elevation profile
    /// behind, the AVG line, the pace-coloured bars (translucent so the
    /// elevation shows through), and a number under each bar.
    private func plotCanvas(width: CGFloat, layout: [(x: CGFloat, w: CGFloat)], selected: Int?, plotH: CGFloat,
                            labelH: CGFloat, axisMin: Double, axisSpan: Double, ticks: [Double]) -> some View {
        Canvas { ctx, _ in
            let baseY = plotH
            let axisMax = axisMin + axisSpan
            func yFor(_ p: Double) -> CGFloat { CGFloat((p - axisMin) / axisSpan) * plotH }
            func cx(_ i: Int) -> CGFloat { i < layout.count ? layout[i].x + layout[i].w / 2 : 0 }

            for tv in ticks {
                let y = yFor(tv)
                var gl = Path(); gl.move(to: CGPoint(x: 0, y: y)); gl.addLine(to: CGPoint(x: width, y: y))
                ctx.stroke(gl, with: .color(Color.drip.divider.opacity(0.6)), lineWidth: 0.5)
            }

            // Elevation profile behind — cumulative net elevation gives the
            // shape; a ridge line on top keeps it legible over the bars.
            let elevs = reps.map { $0.elevFt }
            if showElev, elevs.contains(where: { $0 != nil }) {
                var cum: [Double] = []; var acc = 0.0
                for e in elevs { acc += Double(e ?? 0); cum.append(acc) }
                let lo = cum.min() ?? 0, hi = cum.max() ?? 1
                // Flat ground draws nothing. Absence of a line means absence
                // of terrain, which is the honest read on a track.
                if hi - lo >= Self.elevDrawFloorFt {
                    let range = max(hi - lo, Self.elevMinRangeFt)
                    let band = plotH * 0.5
                    func ey(_ v: Double) -> CGFloat { baseY - CGFloat((v - lo) / range) * band }
                    var area = Path()
                    area.move(to: CGPoint(x: 0, y: baseY))
                    for i in cum.indices { area.addLine(to: CGPoint(x: cx(i), y: ey(cum[i]))) }
                    area.addLine(to: CGPoint(x: width, y: baseY))
                    area.closeSubpath()
                    ctx.fill(area, with: .color(Color.drip.textSecondary.opacity(0.20)))
                    var ridge = Path()
                    for (k, i) in cum.indices.enumerated() {
                        let pt = CGPoint(x: cx(i), y: ey(cum[i]))
                        if k == 0 { ridge.move(to: pt) } else { ridge.addLine(to: pt) }
                    }
                    ctx.stroke(ridge, with: .color(Color.drip.textSecondary.opacity(0.55)), lineWidth: 1)
                }
            }

            if avgLineSec >= axisMin && avgLineSec <= axisMax {
                let ty = yFor(avgLineSec)
                var avg = Path(); avg.move(to: CGPoint(x: 0, y: ty)); avg.addLine(to: CGPoint(x: width, y: ty))
                ctx.stroke(avg, with: .color(Color.drip.textSecondary.opacity(0.45)),
                           style: StrokeStyle(lineWidth: 0.8, dash: [3, 3]))
            }

            var base = Path(); base.move(to: CGPoint(x: 0, y: baseY)); base.addLine(to: CGPoint(x: width, y: baseY))
            ctx.stroke(base, with: .color(Color.drip.textSecondary.opacity(0.5)), lineWidth: 1)

            // Faint separator centred in each between-bar gap.
            for i in 0..<max(layout.count - 1, 0) {
                let xMid = (layout[i].x + layout[i].w + layout[i + 1].x) / 2
                var sep = Path(); sep.move(to: CGPoint(x: xMid, y: 0)); sep.addLine(to: CGPoint(x: xMid, y: baseY))
                ctx.stroke(sep, with: .color(Color.drip.divider.opacity(0.7)), lineWidth: 0.5)
            }

            for (i, r) in reps.enumerated() where i < layout.count {
                let lay = layout[i]
                let p = pace(r)
                let top = yFor(p)
                let bh = max(baseY - top, 3)
                let rect = CGRect(x: lay.x, y: top, width: lay.w, height: bh)
                let col: Color = colorByZone ? rr_zoneColor(r.hr, zones)
                    : (colorByPace ? PaceZoneScale.color(forPaceSec: p) : Color.drip.coral)
                let isSel = (i == selected)
                let bar = Path(roundedRect: rect, cornerRadius: 3)
                ctx.fill(bar, with: .color(col.opacity(isSel ? 1.0 : 0.72)))
                if isSel { ctx.stroke(bar, with: .color(Color.drip.textPrimary), lineWidth: 1.5) }
                ctx.draw(Text("\(r.id)").font(.dripStat(8))
                            .foregroundColor(isSel ? Color.drip.textPrimary : Color.drip.textTertiary),
                         at: CGPoint(x: lay.x + lay.w / 2, y: plotH + labelH / 2))
            }
        }
        .frame(width: width, height: plotH + labelH)
    }

    /// Readout shown above the chart when a bar is tapped — the split's pace,
    /// HR, elevation, recovery and aerobic decoupling.
    private func readout(_ r: RRRep, index: Int) -> some View {
        let recov = recoveries.first { $0.id == r.id }?.drop
        let dec = decoupling(index)
        let adj = adjPace(r)
        // Six cells (SPLIT PACE ADJ HR ELEV REC/DRIFT) is the widest this row
        // ever gets. Each cell must size to its own NUMBER, so the strip is
        // measured at its ideal width and scrolls only if it still overflows.
        //
        // Without the fixedSize the outer HStack split the row evenly between
        // the strip and the trailing Spacer, proposed the strip far less than
        // its ideal, and every cell collapsed to its LABEL width — which
        // truncated the values ("2:31" → "2…", "4:54" → "…"). The numbers were
        // the whole point of the readout, so they take width first now.
        let cells = HStack(spacing: adj == nil ? 11 : 8) {
            readoutCell("SPLIT", clockMS(splitSec(r)))
            // PACE is always the pace that was actually run. ADJ is the
            // heat credit alongside it, tinted to match the HEAT-ADJ chip.
            readoutCell("PACE", rr_pace(r.paceSec, km: km))
            if let adj {
                readoutCell("ADJ", rr_pace(adj, km: km), tone: Color.drip.tired)
            }
            readoutCell("HR", r.hr.map(String.init) ?? "—")
            readoutCell("ELEV", r.elevFt.map { "\($0 > 0 ? "+" : "")\($0)" } ?? "—")
            if let recov { readoutCell("REC", "−\(recov)") }
            if let dec { readoutCell("DRIFT", "\(dec > 0 ? "+" : "")\(dec)%") }
        }
        .fixedSize(horizontal: true, vertical: false)

        return HStack(spacing: adj == nil ? 12 : 9) {
            Text("REP \(r.id)").font(.dripStat(11)).tracking(1)
                .foregroundStyle(Color.drip.coral)
                .fixedSize()
            // Scrolls only when the cells genuinely don't fit (seven cells on
            // a small phone); at every normal width it sits flush left and
            // stays put, so this is a safety net, not a scrolling stat row.
            ScrollView(.horizontal, showsIndicators: false) { cells }
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.drip.textTertiary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
                .onTapGesture { selected = nil }
        }
        .padding(.vertical, 2)
    }

    /// `tone` marks a derived number (currently the heat-adjusted pace) so it
    /// never reads as a measured one.
    private func readoutCell(_ label: String, _ value: String, tone: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.dripStat(8)).tracking(0.6)
                .foregroundStyle(tone ?? Color.drip.textTertiary)
                .lineLimit(1).fixedSize()
            // fixedSize, not minimumScaleFactor: a split time that shrinks
            // to 85% and then truncates anyway is worse than one that simply
            // asks for the width it needs.
            Text(value).font(.dripStat(13))
                .foregroundStyle(tone ?? Color.drip.textPrimary)
                .lineLimit(1).fixedSize()
        }
    }

    /// Option C legend — a full-width gradient bar with a pace ruler on the
    /// fixed colour scale (8:00 easy/green → 4:30 faster-than-mile/blue), so
    /// every colour reads off to a pace. The HR-zone and single-coral modes
    /// keep a plain text label.
    @ViewBuilder private var legendBar: some View {
        if colorByZone {
            Text("COLOR · HR ZONE").font(.dripStat(9)).tracking(0.8)
                .foregroundStyle(Color.drip.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if colorByPace {
            VStack(spacing: 3) {
                RoundedRectangle(cornerRadius: 2).fill(PaceZoneScale.gradient).frame(height: 14)
                GeometryReader { g in
                    ForEach(PaceZoneScale.rulerTicks, id: \.self) { sec in
                        let frac = PaceZoneScale.pos(forPaceSec: sec)
                        Text(rr_pace(sec, km: km)).font(.dripStat(9)).fixedSize()
                            .foregroundStyle(Color.drip.textTertiary)
                            .position(x: min(max(CGFloat(frac) * g.size.width, 14), g.size.width - 14), y: 7)
                    }
                }
                .frame(height: 14)
            }
        } else {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 1).fill(Color.drip.coral).frame(width: 9, height: 9)
                Text("REP PACE · TALLER = FASTER").font(.dripStat(9)).tracking(0.8)
                    .foregroundStyle(Color.drip.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

}

/// Clean splits list under the rep bars — one row per work rep: a pace-colored
/// swatch, the rep distance, its actual split time, and the rest that followed.
struct RepSplitsList: View {
    let reps: [RRRep]
    var km: Bool = false

    private func clock(_ s: Int) -> String {
        s < 60 ? String(format: "0:%02d", s) : String(format: "%d:%02d", s / 60, s % 60)
    }
    private func splitSec(_ r: RRRep) -> Int { r.durSec ?? Int((r.paceSec * r.distMi).rounded()) }

    /// Lap distance in the active unit (e.g. "0.62 mi") — rendered next to the
    /// lap number, since a lap isn't always a whole mile/km.
    private func repDist(_ r: RRRep) -> String {
        let d = km ? r.distMi * 1.60934 : r.distMi
        return String(format: "%.2f %@", d, km ? "km" : "mi")
    }

    var body: some View {
        // Interval reps carry rest; continuous splits carry elevation + HR.
        let hasRest = reps.contains { $0.restSec != nil }
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Text("REP").font(.dripStat(9)).tracking(1).foregroundStyle(Color.drip.textTertiary)
                Spacer()
                Text("SPLIT").font(.dripStat(9)).tracking(1).foregroundStyle(Color.drip.textTertiary)
                    .frame(width: 50, alignment: .trailing)
                Text("PACE").font(.dripStat(9)).tracking(1).foregroundStyle(Color.drip.textTertiary)
                    .frame(width: 46, alignment: .trailing)
                if hasRest {
                    Text("REST").font(.dripStat(9)).tracking(1).foregroundStyle(Color.drip.textTertiary)
                        .frame(width: 44, alignment: .trailing)
                } else {
                    Text("ELEV").font(.dripStat(9)).tracking(1).foregroundStyle(Color.drip.textTertiary)
                        .frame(width: 40, alignment: .trailing)
                    Text("HR").font(.dripStat(9)).tracking(1).foregroundStyle(Color.drip.textTertiary)
                        .frame(width: 32, alignment: .trailing)
                }
            }
            .padding(.leading, 19)
            .padding(.bottom, 8)
            .overlay(Rectangle().fill(Color.drip.divider).frame(height: 1), alignment: .bottom)

            ForEach(reps) { r in
                HStack(spacing: 7) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(PaceZoneScale.color(forPaceSec: r.paceSec))
                        .frame(width: 9, height: 9)
                    if hasRest {
                        Text(r.label).font(.dripBody(14)).foregroundStyle(Color.drip.textPrimary)
                    } else {
                        Text("\(r.id)").font(.dripBody(14)).foregroundStyle(Color.drip.textPrimary)
                            .frame(minWidth: 20, alignment: .leading)
                        Text(repDist(r)).font(.dripStat(12)).foregroundStyle(Color.drip.textSecondary)
                    }
                    Spacer()
                    Text(clock(splitSec(r))).font(.dripStat(14)).foregroundStyle(Color.drip.textPrimary)
                        .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                        .frame(width: 50, alignment: .trailing)
                    Text(rr_pace(r.paceSec, km: km)).font(.dripStat(13)).foregroundStyle(Color.drip.textSecondary)
                        .frame(width: 46, alignment: .trailing)
                    if hasRest {
                        Text(r.restSec.map(clock) ?? "").font(.dripStat(12)).foregroundStyle(Color.drip.textSecondary)
                            .frame(width: 44, alignment: .trailing)
                    } else {
                        Text(r.elevFt.map { "\($0 > 0 ? "+" : "")\($0)" } ?? "")
                            .font(.dripStat(12))
                            .foregroundStyle(Color.drip.textPrimary)
                            .frame(width: 40, alignment: .trailing)
                        Text(r.hr.map(String.init) ?? "")
                            .font(.dripStat(13)).foregroundStyle(Color.drip.textSecondary)
                            .frame(width: 32, alignment: .trailing)
                    }
                }
                .padding(.vertical, 11)
                .overlay(Rectangle().fill(Color.drip.divider.opacity(0.5)).frame(height: 1), alignment: .bottom)
            }
        }
    }
}

/// Every lap on its own line — work reps AND the recoveries between them, each
/// with its own distance, split time, pace and HR (a jog recovery is real easy
/// running, not dead time). Paces slower than 50% of MP speed render grey so the
/// work reps stand out. Driven directly by the per-lap rows (incl. recovery laps
/// with their measured pace) rather than the work-only RRRep model.
struct LapSplitsList: View {
    let laps: [WorkoutLapRow]
    var km: Bool = false
    var mpSec: Double? = nil
    /// Mirrors the receipt's HEAT-ADJ toggle. On, WORK laps render their
    /// stored neutral-air equivalent pace (tinted, so a credited number never
    /// passes for a measured one) and the whole screen — chart, readout,
    /// table — agrees. Recovery laps stay raw: the adjustment table is
    /// calibrated on quality work, so an adjusted jog pace isn't a number
    /// anyone should read off.
    var heatOn: Bool = false

    private func clock(_ s: Int) -> String {
        s < 60 ? String(format: "0:%02d", s) : String(format: "%d:%02d", s / 60, s % 60)
    }
    private func distLabel(_ m: Double) -> String {
        let d = km ? m / 1000 : m / 1609.344
        return String(format: "%.2f %@", d, km ? "km" : "mi")
    }

    var body: some View {
        let ordered = laps.sorted { ($0.lap_index ?? 0) < ($1.lap_index ?? 0) }
        // 1-based work-rep number per row (recoveries get no number).
        var workNo = 0
        let rows: [(lap: WorkoutLapRow, num: Int?)] = ordered.map { lap in
            if lap.is_rest == true { return (lap, nil) }
            workNo += 1
            return (lap, workNo)
        }
        return VStack(spacing: 0) {
            HStack(spacing: 7) {
                Text("LAP").font(.dripStat(9)).tracking(1).foregroundStyle(Color.drip.textTertiary)
                Spacer()
                Text("SPLIT").font(.dripStat(9)).tracking(1).foregroundStyle(Color.drip.textTertiary)
                    .frame(width: 50, alignment: .trailing)
                Text("PACE").font(.dripStat(9)).tracking(1).foregroundStyle(Color.drip.textTertiary)
                    .frame(width: 50, alignment: .trailing)
                Text("HR").font(.dripStat(9)).tracking(1).foregroundStyle(Color.drip.textTertiary)
                    .frame(width: 34, alignment: .trailing)
            }
            .padding(.leading, 19).padding(.bottom, 8)
            .overlay(Rectangle().fill(Color.drip.divider).frame(height: 1), alignment: .bottom)

            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                let lap = row.lap
                let isRest = lap.is_rest == true
                let rawPace = lap.avg_pace_sec_per_mile ?? 0
                // Adjusted only when the toggle is on, the lap is work, the
                // row actually stores an adjustment, and it moves the
                // displayed pace by at least a second.
                let storedAdj = lap.heat_adjusted_pace_sec_per_mile ?? 0
                let adjPace: Double? = (heatOn && !isRest && rawPace > 0 && storedAdj > 0
                                        && abs(storedAdj - rawPace) >= 1) ? storedAdj : nil
                let paceSec = adjPace ?? rawPace
                let dot = paceSec > 0
                    ? PaceZoneScale.color(forPaceSec: paceSec, mpSec: mpSec)
                    : PaceZoneScale.recoveryGrey
                HStack(spacing: 7) {
                    RoundedRectangle(cornerRadius: 2).fill(dot).frame(width: 9, height: 9)
                    Text(row.num.map { "\($0)" } ?? "rec")
                        .font(.dripBody(14))
                        .foregroundStyle(isRest ? Color.drip.textSecondary : Color.drip.textPrimary)
                        .frame(minWidth: 26, alignment: .leading)
                    if let m = lap.distance_meters, m > 0 {
                        Text(distLabel(m)).font(.dripStat(12)).foregroundStyle(Color.drip.textSecondary)
                    }
                    Spacer()
                    Text(lap.moving_time_seconds.map(clock) ?? "—")
                        .font(.dripStat(14)).foregroundStyle(Color.drip.textPrimary)
                        .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                        .frame(width: 50, alignment: .trailing)
                    Text(paceSec > 0 ? rr_pace(paceSec, km: km) : "—")
                        .font(.dripStat(13))
                        .foregroundStyle(adjPace != nil
                                         ? Color.drip.tired
                                         : (isRest ? Color.drip.textTertiary : Color.drip.textSecondary))
                        .lineLimit(1)
                        .frame(width: 50, alignment: .trailing)
                    Text(lap.avg_heart_rate.map(String.init) ?? "")
                        .font(.dripStat(13)).foregroundStyle(Color.drip.textSecondary)
                        .frame(width: 34, alignment: .trailing)
                }
                .padding(.vertical, 9)
                .overlay(Rectangle().fill(Color.drip.divider.opacity(0.5)).frame(height: 1), alignment: .bottom)
            }
        }
    }
}

// MARK: - HR & aerobic decoupling

/// Dedicated HR + drift visual: per-split pace (as speed) and HR, each
/// normalised to their first-half average so both start near 1.0. The amber
/// gap that opens as HR climbs above the effort line is aerobic decoupling.
struct RRHRDrift: View {
    let reps: [RRRep]
    var km: Bool = false
    @State private var showFull = false

    private struct Model { let pace: [Double]; let hr: [Double]; let dec: Int }
    private var model: Model? {
        let valid = reps.filter { ($0.hr ?? 0) > 0 && $0.paceSec > 0 }
        guard valid.count >= 4 else { return nil }
        let half = max(valid.count / 2, 1)
        let mP = valid.prefix(half).map { $0.paceSec }.reduce(0, +) / Double(half)
        let mH = valid.prefix(half).map { Double($0.hr ?? 0) }.reduce(0, +) / Double(half)
        guard mP > 0, mH > 0 else { return nil }
        let pace = valid.map { mP / $0.paceSec }          // speed ratio — up = faster
        let hr = valid.map { Double($0.hr ?? 0) / mH }     // HR ratio — up = higher
        func eff(_ r: RRRep) -> Double { (1.0 / r.paceSec) / Double(r.hr ?? 1) }
        let e1 = valid.prefix(half).map(eff).reduce(0, +) / Double(half)
        let rest = max(valid.count - half, 1)
        let e2 = valid.suffix(rest).map(eff).reduce(0, +) / Double(rest)
        let dec = e1 > 0 ? Int(((e1 - e2) / e1 * 100).rounded()) : 0
        return Model(pace: pace, hr: hr, dec: dec)
    }

    var body: some View {
        if let m = model {
            VStack(alignment: .leading, spacing: 8) {
                header(m, expandable: true)
                chartScroller(m).frame(height: 96)
                legend
            }
            .fullScreenCover(isPresented: $showFull) { fullScreen(m) }
        }
    }

    private func header(_ m: Model, expandable: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("HR & DRIFT").font(.dripStat(11)).tracking(1.3).foregroundStyle(Color.drip.textSecondary)
            Spacer()
            Text("\(m.dec > 0 ? "+" : "")\(m.dec)%")
                .font(.dripStat(15)).foregroundStyle(m.dec > 6 ? Color.drip.tired : Color.drip.textPrimary)
            Text("2ND-HALF DRIFT").font(.dripStat(9)).tracking(0.6).foregroundStyle(Color.drip.textTertiary)
            if expandable {
                Button { showFull = true } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.drip.textTertiary)
                }.buttonStyle(.plain).padding(.leading, 4)
            }
        }
    }

    /// Horizontally scrollable line chart — points hold a readable minimum
    /// spacing, so a long run scrolls instead of cramming.
    private func chartScroller(_ m: Model) -> some View {
        GeometryReader { geo in
            let n = m.pace.count
            let minPt: CGFloat = 16
            let needed = CGFloat(max(n - 1, 1)) * minPt + 12
            let scrolling = needed > geo.size.width
            let w = scrolling ? needed : geo.size.width
            let chart = driftCanvas(m, width: w, height: geo.size.height)
            if scrolling {
                ScrollView(.horizontal, showsIndicators: false) { chart }
            } else {
                chart
            }
        }
    }

    private func driftCanvas(_ m: Model, width: CGFloat, height: CGFloat) -> some View {
        Canvas { ctx, _ in
            let n = m.pace.count
            guard n > 1 else { return }
            let pad: CGFloat = 6
            let all = m.pace + m.hr
            let lo = (all.min() ?? 0.9) - 0.02, hi = (all.max() ?? 1.1) + 0.02
            let range = max(hi - lo, 0.01)
            func X(_ i: Int) -> CGFloat { pad + CGFloat(i) / CGFloat(n - 1) * (width - 2 * pad) }
            func Y(_ v: Double) -> CGFloat { pad + (1 - CGFloat((v - lo) / range)) * (height - 2 * pad) }
            let y1 = Y(1.0)
            var bl = Path(); bl.move(to: CGPoint(x: pad, y: y1)); bl.addLine(to: CGPoint(x: width - pad, y: y1))
            ctx.stroke(bl, with: .color(Color.drip.divider), style: StrokeStyle(lineWidth: 0.8, dash: [3, 3]))
            var area = Path()
            area.move(to: CGPoint(x: X(0), y: Y(m.pace[0])))
            for i in 0..<n { area.addLine(to: CGPoint(x: X(i), y: Y(m.pace[i]))) }
            for i in stride(from: n - 1, through: 0, by: -1) { area.addLine(to: CGPoint(x: X(i), y: Y(m.hr[i]))) }
            area.closeSubpath()
            ctx.fill(area, with: .color(Color.drip.tired.opacity(0.30)))
            var pl = Path()
            for i in 0..<n { let p = CGPoint(x: X(i), y: Y(m.pace[i])); if i == 0 { pl.move(to: p) } else { pl.addLine(to: p) } }
            ctx.stroke(pl, with: .color(Color.drip.textPrimary), lineWidth: 2)
            var hl = Path()
            for i in 0..<n { let p = CGPoint(x: X(i), y: Y(m.hr[i])); if i == 0 { hl.move(to: p) } else { hl.addLine(to: p) } }
            ctx.stroke(hl, with: .color(Color.drip.injured), lineWidth: 2)
        }
        .frame(width: width, height: height)
    }

    private var legend: some View {
        HStack(spacing: 16) {
            driftKey(Color.drip.textPrimary, "PACE", line: true)
            driftKey(Color.drip.injured, "HR", line: true)
            driftKey(Color.drip.tired.opacity(0.4), "DRIFT", line: false)
            Spacer()
        }
    }

    private func fullScreen(_ m: Model) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top bar — title + close.
            HStack(alignment: .firstTextBaseline) {
                Text("HR & DRIFT").font(.dripStat(12)).tracking(1.3)
                    .foregroundStyle(Color.drip.textSecondary)
                Spacer()
                Button { showFull = false } label: {
                    Image(systemName: "xmark").font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.drip.textSecondary)
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 18)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    // Headline drift figure + plain-language explanation.
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("\(m.dec > 0 ? "+" : "")\(m.dec)%")
                                .font(.dripStat(42))
                                .foregroundStyle(m.dec > 6 ? Color.drip.tired : Color.drip.textPrimary)
                            Text("2ND-HALF DRIFT").font(.dripStat(10)).tracking(0.8)
                                .foregroundStyle(Color.drip.textTertiary)
                        }
                        Text("How much your heart rate rose over the second half of the run at the same pace. The shaded gap is that drift opening up.")
                            .font(.dripStat(12))
                            .foregroundStyle(Color.drip.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 20)

                    // The chart, held at a readable fixed height so the lines
                    // aren't stretched into zigzags.
                    fullChart(m)
                        .frame(height: 300)
                        .padding(.horizontal, 20)

                    legend.padding(.horizontal, 20)

                    Text("Each point is one split, left to right. Values are shown relative to your first-half average, so both lines start near 0%.")
                        .font(.dripStat(11))
                        .foregroundStyle(Color.drip.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 20)
                }
                .padding(.top, 4)
                .padding(.bottom, 40)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Color.drip.background.ignoresSafeArea())
    }

    // Full-screen chart geometry.
    private var fullPadT: CGFloat { 12 }
    private var fullPadB: CGFloat { 26 }
    private var fullAxisW: CGFloat { 44 }

    /// Percent-scaled axis bounds + gridline ticks. The model's pace/HR values
    /// are ratios vs the first-half average, so `(ratio − 1) × 100` reads as a
    /// percentage above/below baseline. Always brackets 0%.
    private func driftTicks(_ m: Model) -> (lo: Double, hi: Double, ticks: [Double]) {
        let pct = (m.pace + m.hr).map { ($0 - 1) * 100 }
        let dataLo = min(pct.min() ?? -4, 0)
        let dataHi = max(pct.max() ?? 4, 0)
        let span = max(dataHi - dataLo, 2)
        let rawStep = span / 4
        let step = [1.0, 2, 2.5, 5, 10, 20].first { $0 >= rawStep } ?? 20
        let lo = (dataLo / step).rounded(.down) * step
        let hi = (dataHi / step).rounded(.up) * step
        var ticks: [Double] = []
        var v = lo
        while v <= hi + 0.0001 { ticks.append(v); v += step }
        return (lo, hi, ticks)
    }

    /// Pinned percent y-axis on the left; pace/HR/drift plot on the right,
    /// horizontally scrollable when there are many splits.
    private func fullChart(_ m: Model) -> some View {
        let t = driftTicks(m)
        let span = max(t.hi - t.lo, 1)
        let n = m.pace.count
        return HStack(spacing: 0) {
            GeometryReader { g in
                let plotH = g.size.height - fullPadT - fullPadB
                ForEach(t.ticks, id: \.self) { tv in
                    let y = fullPadT + (1 - CGFloat((tv - t.lo) / span)) * plotH
                    Text("\(tv > 0 ? "+" : "")\(Int(tv))%")
                        .font(.dripStat(9))
                        .foregroundStyle(tv == 0 ? Color.drip.textSecondary : Color.drip.textTertiary)
                        .position(x: fullAxisW - 20, y: y)
                }
            }
            .frame(width: fullAxisW)

            GeometryReader { geo in
                let minPt: CGFloat = 26
                let needed = CGFloat(max(n - 1, 1)) * minPt + 24
                let scrolling = needed > geo.size.width
                let w = scrolling ? needed : geo.size.width
                let plot = fullPlot(m, ticks: t, span: span, width: w, height: geo.size.height)
                if scrolling {
                    ScrollView(.horizontal, showsIndicators: false) { plot }
                } else {
                    plot
                }
            }
        }
    }

    private func fullPlot(_ m: Model, ticks t: (lo: Double, hi: Double, ticks: [Double]),
                          span: Double, width: CGFloat, height: CGFloat) -> some View {
        Canvas { ctx, _ in
            let n = m.pace.count
            guard n > 1 else { return }
            let padL: CGFloat = 4, padR: CGFloat = 8
            let plotH = height - fullPadT - fullPadB
            let plotBottom = fullPadT + plotH
            func X(_ i: Int) -> CGFloat { padL + CGFloat(i) / CGFloat(n - 1) * (width - padL - padR) }
            func Y(_ ratio: Double) -> CGFloat {
                let pct = (ratio - 1) * 100
                return fullPadT + (1 - CGFloat((pct - t.lo) / span)) * plotH
            }

            // Gridlines; the 0% baseline is drawn solid and darker.
            for tv in t.ticks {
                let y = fullPadT + (1 - CGFloat((tv - t.lo) / span)) * plotH
                let isBase = abs(tv) < 0.0001
                var gl = Path(); gl.move(to: CGPoint(x: padL, y: y)); gl.addLine(to: CGPoint(x: width - padR, y: y))
                ctx.stroke(gl,
                           with: .color(isBase ? Color.drip.textSecondary.opacity(0.45)
                                               : Color.drip.divider.opacity(0.6)),
                           style: StrokeStyle(lineWidth: isBase ? 0.9 : 0.5, dash: isBase ? [] : [3, 3]))
            }

            // First-half / second-half divider.
            let half = max(n / 2, 1)
            if half < n {
                let hx = (X(half - 1) + X(half)) / 2
                var vp = Path(); vp.move(to: CGPoint(x: hx, y: fullPadT)); vp.addLine(to: CGPoint(x: hx, y: plotBottom))
                ctx.stroke(vp, with: .color(Color.drip.divider), style: StrokeStyle(lineWidth: 0.6, dash: [2, 3]))
            }

            // Drift fill between the pace and HR lines.
            var area = Path()
            area.move(to: CGPoint(x: X(0), y: Y(m.pace[0])))
            for i in 0..<n { area.addLine(to: CGPoint(x: X(i), y: Y(m.pace[i]))) }
            for i in stride(from: n - 1, through: 0, by: -1) { area.addLine(to: CGPoint(x: X(i), y: Y(m.hr[i]))) }
            area.closeSubpath()
            ctx.fill(area, with: .color(Color.drip.tired.opacity(0.28)))

            // Pace (speed) line.
            var pl = Path()
            for i in 0..<n { let p = CGPoint(x: X(i), y: Y(m.pace[i])); if i == 0 { pl.move(to: p) } else { pl.addLine(to: p) } }
            ctx.stroke(pl, with: .color(Color.drip.textPrimary), lineWidth: 2)

            // HR line.
            var hl = Path()
            for i in 0..<n { let p = CGPoint(x: X(i), y: Y(m.hr[i])); if i == 0 { hl.move(to: p) } else { hl.addLine(to: p) } }
            ctx.stroke(hl, with: .color(Color.drip.injured), lineWidth: 2)

            // Split numbers along the bottom.
            for i in 0..<n {
                ctx.draw(Text("\(i + 1)").font(.dripStat(8)).foregroundColor(Color.drip.textTertiary),
                         at: CGPoint(x: X(i), y: plotBottom + 12))
            }
        }
        .frame(width: width, height: height)
    }

    private func driftKey(_ c: Color, _ t: String, line: Bool) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: line ? 1 : 2).fill(c)
                .frame(width: line ? 14 : 10, height: line ? 2 : 10)
            Text(t).font(.dripStat(9)).foregroundStyle(Color.drip.textSecondary)
        }
    }
}

// MARK: - 2 · HR zone timeline

struct RRZoneTimeline: View {
    let times: [Double]
    let hr: [Double]
    let windows: [RRWindow]
    let zones: [RRZone]
    var height: CGFloat = 150

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let padL: CGFloat = 26, padR: CGFloat = 6, padT: CGFloat = 8, padB: CGFloat = 14
            let plotW = w - padL - padR, plotH = h - padT - padB
            let total = max(times.last ?? 1, 1)
            let yMin = 90.0, yMax = 185.0
            let x: (Double) -> CGFloat = { padL + CGFloat($0 / total) * plotW }
            let y: (Double) -> CGFloat = { padT + plotH - CGFloat(($0 - yMin) / (yMax - yMin)) * plotH }

            ZStack(alignment: .topLeading) {
                ForEach(zones) { z in
                    let top = y(min(Double(z.hi), yMax)), bot = y(max(Double(z.lo), yMin))
                    if bot > top {
                        Rectangle().fill(z.color.opacity(0.09))
                            .frame(width: plotW, height: bot - top).position(x: padL + plotW / 2, y: (top + bot) / 2)
                    }
                }
                ForEach(windows) { win in
                    let x0 = x(win.start), x1 = x(win.end)
                    Rectangle().fill(Color.drip.coral.opacity(0.07))
                        .frame(width: max(x1 - x0, 1), height: plotH).position(x: (x0 + x1) / 2, y: padT + plotH / 2)
                }
                ForEach([120, 150, 175], id: \.self) { v in
                    Text("\(v)").font(.dripStat(7.5)).foregroundStyle(Color.drip.textTertiary)
                        .position(x: padL - 11, y: y(Double(v)))
                }
                Path { p in
                    for (i, t) in times.enumerated() where i < hr.count {
                        let pt = CGPoint(x: x(t), y: y(hr[i]))
                        if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                    }
                }
                .stroke(Color.drip.textPrimary.opacity(0.85), lineWidth: 1.1)
            }
        }
        .frame(height: height)
    }
}

// MARK: - 3 · Pace trace

struct RRPaceTrace: View {
    let times: [Double]
    let paceSec: [Double]   // sec/mi
    let windows: [RRWindow]
    let km: Bool
    /// When true, the trace is drawn as colored segments along the pace
    /// ramp (recoveries pale, surges navy). When false it's a single
    /// coral line. Defaults true.
    var colorByPace: Bool = true
    var height: CGFloat = 120

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let padL: CGFloat = 30, padR: CGFloat = 6, padT: CGFloat = 8, padB: CGFloat = 14
            let plotW = w - padL - padR, plotH = h - padT - padB
            let total = max(times.last ?? 1, 1)
            let pmin = 280.0, pmax = 640.0
            let x: (Double) -> CGFloat = { padL + CGFloat($0 / total) * plotW }
            let y: (Double) -> CGFloat = { padT + CGFloat(($0 - pmin) / (pmax - pmin)) * plotH }
            // light smoothing
            let sm = rr_smooth(paceSec, win: 3)

            ZStack(alignment: .topLeading) {
                ForEach([330.0, 420.0, 540.0], id: \.self) { v in
                    Path { p in p.move(to: .init(x: padL, y: y(v))); p.addLine(to: .init(x: padL + plotW, y: y(v))) }
                        .stroke(Color.drip.divider, lineWidth: 0.4)
                    Text(rr_pace(v, km: km)).font(.dripStat(7.5)).foregroundStyle(Color.drip.textTertiary)
                        .position(x: padL - 12, y: y(v))
                }
                ForEach(windows) { win in
                    let x0 = x(win.start), x1 = x(win.end)
                    Rectangle().fill(Color.drip.coral.opacity(0.07))
                        .frame(width: max(x1 - x0, 1), height: plotH).position(x: (x0 + x1) / 2, y: padT + plotH / 2)
                }
                if colorByPace {
                    // Colored segments: each step tinted by its pace along the
                    // ramp. pmin/pmax (280–640) map fast→slow, so the
                    // pale→navy ramp spans the visible pace window.
                    ForEach(1..<max(times.count, 1), id: \.self) { i in
                        if i < sm.count {
                            let p0 = CGPoint(x: x(times[i - 1]), y: y(sm[i - 1]))
                            let p1 = CGPoint(x: x(times[i]), y: y(sm[i]))
                            let segPace = (sm[i - 1] + sm[i]) / 2
                            Path { p in p.move(to: p0); p.addLine(to: p1) }
                                .stroke(PaceZoneScale.color(forPaceSec: segPace),
                                        style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                        }
                    }
                } else {
                    Path { p in
                        for (i, t) in times.enumerated() where i < sm.count {
                            let pt = CGPoint(x: x(t), y: y(sm[i]))
                            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                        }
                    }
                    .stroke(Color.drip.coral, lineWidth: 1.2)
                }
            }
        }
        .frame(height: height)
    }
}

// MARK: - 4 · Cadence strip

struct RRCadenceStrip: View {
    let times: [Double]
    let cadence: [Double]   // spm
    var height: CGFloat = 70

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let padL: CGFloat = 26, padR: CGFloat = 6, pad: CGFloat = 8
            let plotW = w - padL - padR, plotH = h - pad * 2
            let total = max(times.last ?? 1, 1)
            let lo = 150.0, hi = 200.0
            let x: (Double) -> CGFloat = { padL + CGFloat($0 / total) * plotW }
            let y: (Double) -> CGFloat = { pad + plotH - CGFloat(($0 - lo) / (hi - lo)) * plotH }
            let avg = cadence.isEmpty ? 0 : cadence.reduce(0, +) / Double(cadence.count)
            ZStack(alignment: .topLeading) {
                Path { p in p.move(to: .init(x: padL, y: y(avg))); p.addLine(to: .init(x: padL + plotW, y: y(avg))) }
                    .stroke(Color.drip.textSecondary.opacity(0.5), style: StrokeStyle(lineWidth: 0.6, dash: [3, 3]))
                Path { p in
                    for (i, t) in times.enumerated() where i < cadence.count {
                        let pt = CGPoint(x: x(t), y: y(cadence[i]))
                        if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                    }
                }
                .stroke(Color.drip.textSecondary.opacity(0.8), lineWidth: 1)
                Text("AVG \(Int(avg)) SPM").font(.dripStat(7.5)).foregroundStyle(Color.drip.textSecondary)
                    .position(x: padL + plotW - 34, y: pad + 6)
            }
        }
        .frame(height: height)
    }
}

// MARK: - 5 · Elevation + grade

struct RRElevationGrade: View {
    let times: [Double]
    let altFt: [Double]
    let grade: [Double]   // %
    var height: CGFloat = 88

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let padL: CGFloat = 26, padR: CGFloat = 6, padT: CGFloat = 8, padB: CGFloat = 8
            let plotW = w - padL - padR, plotH = h - padT - padB
            let total = max(times.last ?? 1, 1)
            let lo = altFt.min() ?? 0, hi = altFt.max() ?? 1
            let x: (Double) -> CGFloat = { padL + CGFloat($0 / total) * plotW }
            let y: (Double) -> CGFloat = { padT + plotH - CGFloat(($0 - lo) / max(hi - lo, 1)) * plotH }
            ZStack(alignment: .topLeading) {
                // grade-tinted columns
                ForEach(Array(times.enumerated()), id: \.offset) { i, t in
                    if i > 0, i < grade.count {
                        let g = grade[i]
                        let col: Color = g > 1.5 ? Color.drip.coral : (g < -1.5 ? Color.drip.positive : Color.drip.textTertiary)
                        let op = min(0.5, abs(g) / 8 + 0.06)
                        let x0 = x(times[i - 1]), x1 = x(t)
                        Rectangle().fill(col.opacity(op))
                            .frame(width: max(x1 - x0 + 0.5, 0.5), height: plotH).position(x: (x0 + x1) / 2, y: padT + plotH / 2)
                    }
                }
                // area + line
                Path { p in
                    p.move(to: .init(x: x(times.first ?? 0), y: padT + plotH))
                    for (i, t) in times.enumerated() where i < altFt.count { p.addLine(to: .init(x: x(t), y: y(altFt[i]))) }
                    p.addLine(to: .init(x: x(times.last ?? 0), y: padT + plotH))
                    p.closeSubpath()
                }
                .fill(Color.drip.textPrimary.opacity(0.06))
                Path { p in
                    for (i, t) in times.enumerated() where i < altFt.count {
                        let pt = CGPoint(x: x(t), y: y(altFt[i]))
                        if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                    }
                }
                .stroke(Color.drip.textPrimary.opacity(0.55), lineWidth: 0.9)
            }
        }
        .frame(height: height)
    }
}

// MARK: - 6 · Rep recovery small-multiples

struct RRRecoveryRow: View {
    let recoveries: [RRRecovery]
    var body: some View {
        HStack(spacing: 6) {
            ForEach(recoveries) { r in
                VStack(spacing: 3) {
                    Text("R\(r.id)").font(.dripStat(8)).foregroundStyle(Color.drip.textTertiary)
                    GeometryReader { geo in
                        let w = geo.size.width, h = geo.size.height
                        let lo = 130.0, hi = 185.0
                        Path { p in
                            for (i, v) in r.pts.enumerated() {
                                let x = CGFloat(i) / CGFloat(max(r.pts.count - 1, 1)) * w
                                let y = h - CGFloat((Double(v) - lo) / (hi - lo)) * h
                                if i == 0 { p.move(to: .init(x: x, y: y)) } else { p.addLine(to: .init(x: x, y: y)) }
                            }
                        }
                        .stroke(r.drop >= 36 ? Color.drip.coral : Color.drip.textSecondary, style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                    }
                    .frame(height: 26)
                    Text("−\(r.drop)").font(.dripStat(11)).foregroundStyle(r.drop >= 36 ? Color.drip.coral : Color.drip.textPrimary)
                    Text("bpm/60s").font(.dripStat(7)).foregroundStyle(Color.drip.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .overlay(Rectangle().fill(Color.drip.divider).frame(height: 1), alignment: .bottom)
            }
        }
    }
}

// MARK: - 7 · Time in zone bar

struct RRZoneBar: View {
    let seconds: [String: Double]   // zone id → seconds
    let zones: [RRZone]
    let mainZone: String

    var body: some View {
        let total = max(seconds.values.reduce(0, +), 1)
        return VStack(alignment: .leading, spacing: 10) {
            // Proportional stacked bar. Widths are computed explicitly from the
            // container width — `layoutPriority` in an HStack does NOT split
            // width proportionally (it hands the highest-priority segment its
            // full flexible size first), which collapsed the whole bar to the
            // single dominant zone. GeometryReader gives each zone `width × pct`.
            GeometryReader { geo in
                HStack(spacing: 0) {
                    ForEach(zones) { z in
                        let pct = (seconds[z.id] ?? 0) / total
                        if pct > 0.004 {
                            Rectangle().fill(z.color).opacity(z.id == mainZone ? 1 : 0.5)
                                .frame(width: max(1, geo.size.width * pct))
                                .overlay(Rectangle().fill(Color.drip.background).frame(width: 1), alignment: .trailing)
                        }
                    }
                }
            }
            .frame(height: 20)
            .overlay(Rectangle().stroke(Color.drip.divider, lineWidth: 1))
            HStack(alignment: .top, spacing: 6) {
                ForEach(zones) { z in
                    let sec = seconds[z.id] ?? 0
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Rectangle().fill(z.color).opacity(z.id == mainZone ? 1 : 0.5).frame(width: 6, height: 6)
                            Text(z.id).font(.dripStat(8)).foregroundStyle(z.id == mainZone ? Color.drip.textPrimary : Color.drip.textTertiary)
                        }
                        Text(rr_clock(sec)).font(.dripStat(12)).foregroundStyle(z.id == mainZone ? Color.drip.coral : Color.drip.textSecondary)
                        Text("\(Int((sec / total * 100).rounded()))%").font(.dripStat(8)).foregroundStyle(Color.drip.textTertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

// MARK: - 8 · Route shape

struct RRRouteShape: View {
    let coords: [CLLocationCoordinate2D]
    let hr: [Int]            // parallel to coords (may be empty)
    let colorByZone: Bool
    let zones: [RRZone]
    let repStartIdx: [(idx: Int, rep: Int)]
    var height: CGFloat = 150

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let pad: CGFloat = 16
            guard coords.count > 1 else { return AnyView(EmptyView()) }
            let lats = coords.map(\.latitude), lngs = coords.map(\.longitude)
            let minLat = lats.min()!, maxLat = lats.max()!, minLng = lngs.min()!, maxLng = lngs.max()!
            let spanLat = max(maxLat - minLat, 1e-5), spanLng = max(maxLng - minLng, 1e-5)
            let scale = min((w - pad * 2) / spanLng, (h - pad * 2) / spanLat)
            let ox = (w - spanLng * scale) / 2, oy = (h - spanLat * scale) / 2
            let pt: (Int) -> CGPoint = { i in
                CGPoint(x: ox + (coords[i].longitude - minLng) * scale,
                        y: h - (oy + (coords[i].latitude - minLat) * scale))
            }
            return AnyView(
                ZStack {
                    ForEach(1..<coords.count, id: \.self) { i in
                        let col: Color = {
                            if colorByZone, i < hr.count { return rr_zoneColor(hr[i], zones) }
                            // coral when fast (proxy: inside a rep window via hr high), else gray
                            if i < hr.count, hr[i] >= 160 { return Color.drip.coral }
                            return Color.drip.textTertiary
                        }()
                        Path { p in p.move(to: pt(i - 1)); p.addLine(to: pt(i)) }
                            .stroke(col.opacity(0.9), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                    }
                    ForEach(Array(repStartIdx.enumerated()), id: \.offset) { _, rs in
                        let p = pt(rs.idx)
                        Circle().fill(Color.drip.background).overlay(Circle().stroke(Color.drip.textPrimary, lineWidth: 1.2))
                            .frame(width: 13, height: 13).position(p)
                        Text("\(rs.rep)").font(.dripStat(8)).foregroundStyle(Color.drip.textPrimary).position(p)
                    }
                    Circle().fill(Color.drip.textPrimary).frame(width: 7, height: 7).position(pt(0))
                    Circle().fill(Color.drip.coral).frame(width: 7, height: 7).position(pt(coords.count - 1))
                }
            )
        }
        .frame(height: height)
        .background(Color.drip.cardBackgroundElevated)
        .overlay(Rectangle().stroke(Color.drip.divider, lineWidth: 1))
    }
}

// MARK: - Shared helpers (rr_*)

private struct RRItem { let isRest: Bool; let rep: Int; let dur: Double; let x0: Double }

private func rr_layItems(reps: [RRRep]) -> [RRItem] {
    var out: [RRItem] = []
    var cursor = 0.0
    for r in reps {
        let dur = r.distMi * r.paceSec
        out.append(RRItem(isRest: false, rep: r.id, dur: dur, x0: cursor)); cursor += dur
        if let rest = r.restSec { out.append(RRItem(isRest: true, rep: r.id, dur: Double(rest), x0: cursor)); cursor += Double(rest) }
    }
    return out
}

// MARK: - Comparison vs recent same-type sessions

/// Average work pace for the current session vs recent same-type sessions.
/// Faster paces plot higher. Prior sessions are gray dots; today is the coral
/// dot on the right. A dashed line marks the recent average.
struct RRComparison: View {
    let series: [RecentSimilarWorkout]   // oldest → newest; last element = current session
    let km: Bool
    var height: CGFloat = 132

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let padL: CGFloat = 34, padR: CGFloat = 10, padT: CGFloat = 10, padB: CGFloat = 20
            let plotW = w - padL - padR, plotH = h - padT - padB
            let paces = series.map(\.avgPaceSec)
            let lo = (paces.min() ?? 300) - 6
            let hi = (paces.max() ?? 360) + 6
            let span = max(hi - lo, 1)
            let n = max(series.count - 1, 1)
            let x: (Int) -> CGFloat = { padL + CGFloat(Double($0) / Double(n)) * plotW }
            // faster (lower sec/mi) sits higher → invert against `lo`
            let y: (Double) -> CGFloat = { padT + CGFloat(($0 - lo) / span) * plotH }
            let prior = series.dropLast().map(\.avgPaceSec)
            let priorAvg = prior.isEmpty ? (paces.first ?? 0) : prior.reduce(0, +) / Double(prior.count)

            ZStack(alignment: .topLeading) {
                ForEach([hi, (hi + lo) / 2, lo], id: \.self) { v in
                    Path { p in p.move(to: .init(x: padL, y: y(v))); p.addLine(to: .init(x: padL + plotW, y: y(v))) }
                        .stroke(Color.drip.divider, lineWidth: 0.4)
                    Text(rr_pace(v, km: km)).font(.dripStat(7.5)).foregroundStyle(Color.drip.textTertiary)
                        .position(x: padL - 14, y: y(v))
                }
                // recent-average reference
                Path { p in p.move(to: .init(x: padL, y: y(priorAvg))); p.addLine(to: .init(x: padL + plotW, y: y(priorAvg))) }
                    .stroke(Color.drip.textTertiary, style: StrokeStyle(lineWidth: 0.8, dash: [3, 3]))
                // connecting line
                Path { p in
                    for (i, s) in series.enumerated() {
                        let pt = CGPoint(x: x(i), y: y(s.avgPaceSec))
                        if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                    }
                }
                .stroke(Color.drip.textSecondary.opacity(0.5), lineWidth: 1)
                // dots + date labels
                ForEach(Array(series.enumerated()), id: \.offset) { i, s in
                    let isCur = i == series.count - 1
                    Circle().fill(isCur ? Color.drip.coral : Color.drip.textSecondary)
                        .frame(width: isCur ? 9 : 6, height: isCur ? 9 : 6)
                        .position(x: x(i), y: y(s.avgPaceSec))
                    Text(s.dateLabel).font(.dripStat(7.5))
                        .foregroundStyle(isCur ? Color.drip.coral : Color.drip.textTertiary)
                        .position(x: x(i), y: padT + plotH + 12)
                }
            }
        }
        .frame(height: height)
    }
}

func rr_smooth(_ a: [Double], win: Int) -> [Double] {
    guard !a.isEmpty else { return a }
    return a.indices.map { i in
        let lo = max(0, i - win), hi = min(a.count - 1, i + win)
        return a[lo...hi].reduce(0, +) / Double(hi - lo + 1)
    }
}

func rr_zoneColor(_ hr: Int?, _ zones: [RRZone]) -> Color {
    guard let hr else { return Color.drip.textSecondary }
    return zones.first { hr >= $0.lo && hr < $0.hi }?.color ?? zones.last?.color ?? Color.drip.coral
}

/// Format sec/mi as m:ss, optionally per-km.
func rr_pace(_ secPerMile: Double, km: Bool) -> String {
    let v = km ? secPerMile / 1.60934 : secPerMile
    let t = Int(v.rounded()); return "\(t / 60):\(String(format: "%02d", t % 60))"
}
func rr_clock(_ sec: Double) -> String {
    let t = Int(sec.rounded()); return "\(t / 60):\(String(format: "%02d", t % 60))"
}
func rr_dist(_ mi: Double, km: Bool) -> String {
    String(format: "%.2f%@", km ? mi * 1.60934 : mi, km ? "km" : "mi")
}

/// Standard 5-band HR zones from a max HR.
func rr_zones(maxHR: Int) -> [RRZone] {
    let m = Double(max(maxHR, 150))
    func b(_ f: Double) -> Int { Int((m * f).rounded()) }
    return [
        RRZone(id: "Z1", lo: 0,       hi: b(0.70), color: Color.drip.neutral),
        RRZone(id: "Z2", lo: b(0.70), hi: b(0.80), color: Color.drip.positive),
        RRZone(id: "Z3", lo: b(0.80), hi: b(0.88), color: Color.drip.tired),
        // Z4/Z5 were coral (#D4592A) + struggling (#C45A3A) — nearly the same
        // hue, so the top two zones were indistinguishable. Split them into a
        // bright orange → deep red step (distinct as faint bands AND as the
        // full-strength axis labels).
        RRZone(id: "Z4", lo: b(0.88), hi: b(0.95), color: Color(hex: "E0742E")),
        RRZone(id: "Z5", lo: b(0.95), hi: 240,     color: Color(hex: "8F2A1E")),
    ]
}

//
//  PaceVolumeSpectrumChart.swift
//  RunningLog
//
//  Continuous-spectrum visualization of training volume distributed across
//  the pace axis. Anchored by four reference paces — Easy / MP / LT / 5K.
//
//  Where the existing `TrainingEffortChart` shows volume as discrete zone
//  buckets (easy / steady / threshold / vo2 / race), this chart treats pace
//  as the continuous variable it actually is. Volume becomes a density area
//  along the pace axis, anchored visually by the runner's own reference
//  paces. The athlete's pace ladder calibrates the chart; the data tells the
//  story of where this week's miles actually landed.
//
//  The chart is purely a visualization — it accepts pre-computed
//  `[PaceVolumeSample]` and a set of `PaceAnchor`s. Parent views
//  (e.g. TrainingTabView's BLOCK view) own the data assembly. See `PaceVolumeSample`
//  for the schema and `samples(from:)` helpers.
//

import SwiftUI

// MARK: - Data types

/// One training-pace anchor — typically Easy, MP, LT, 5K. Drawn as a
/// vertical reference line plus a two-line label above the chart.
public struct PaceAnchor: Identifiable, Hashable {
    public let id: String
    public let label: String          // short caps label, e.g. "EASY"
    public let paceSeconds: Double    // pace in seconds per mile
    public let color: Color

    public init(label: String, paceSeconds: Double, color: Color) {
        self.id = label
        self.label = label
        self.paceSeconds = paceSeconds
        self.color = color
    }
}

/// One contribution to the volume distribution: `miles` run at `paceSeconds`.
/// Multiple samples may share the same pace; the chart sums them via KDE.
public struct PaceVolumeSample: Hashable {
    public let paceSeconds: Double
    public let miles: Double

    public init(paceSeconds: Double, miles: Double) {
        self.paceSeconds = paceSeconds
        self.miles = miles
    }
}

// MARK: - Chart

/// A continuous density area showing where this period's miles fell along
/// the pace axis. Color regions correspond to anchor zones; reference
/// paces appear as vertical hairlines with two-line labels above.
///
/// Sizing: the chart fills the parent's width and renders at a fixed
/// internal height (label row + density area + axis row). Drop it into a
/// section without additional sizing constraints.
public struct PaceVolumeSpectrumChart: View {

    public let samples: [PaceVolumeSample]
    public let anchors: [PaceAnchor]   // sorted by paceSeconds (slowest first) in init
    public let paceSlow: Double         // axis left bound (seconds/mi; e.g. 540 = 9:00)
    public let paceFast: Double         // axis right bound (e.g. 330 = 5:30)
    public let bandwidth: Double        // KDE smoothing kernel σ (seconds; default 18)

    // 90pt accommodates up to 3 rows of staggered anchor labels for
    // the worst realistic case (4 close race anchors crowding the
    // right side of the axis). Each row is 26pt; the label block
    // itself is ~24pt; 90pt gives breathing room.
    private let topLabelHeight: CGFloat = 90
    private let chartHeight:    CGFloat = 110
    private let axisHeight:     CGFloat = 22
    // Approximate rendered width of one anchor label block. Used by
    // the row-assignment algorithm to detect collisions.
    private let anchorLabelWidth: CGFloat = 44

    public init(
        samples: [PaceVolumeSample],
        anchors: [PaceAnchor],
        paceSlow: Double = 540,
        paceFast: Double = 330,
        bandwidth: Double = 18
    ) {
        self.samples   = samples
        self.anchors   = anchors.sorted { $0.paceSeconds > $1.paceSeconds }
        self.paceSlow  = paceSlow
        self.paceFast  = paceFast
        self.bandwidth = bandwidth
    }

    /// Auto-fit constructor — derives the pace axis from the union of the
    /// runner's actual workout paces and the anchor reference paces, with
    /// 45 seconds of padding on each side. Use this when the runner's
    /// reference paces and actual training paces don't overlap (common
    /// when goal-derived paces are aspirational).
    ///
    /// The slow side is capped at ~75 seconds slower than the slowest
    /// anchor (typically EASY). Without the cap, a single recovery walk
    /// or GPS glitch at 15:00 pace stretches the axis so far left that
    /// the EASY zone visually owns most of the chart and drowns out the
    /// actual training distribution. Outliers beyond the cap clip to
    /// the left edge of the chart.
    public init(
        samples: [PaceVolumeSample],
        anchors: [PaceAnchor],
        bandwidth: Double = 18
    ) {
        let pad: Double = 45
        let allPaces = samples.map(\.paceSeconds) + anchors.map(\.paceSeconds)
        let slowestAnchor = anchors.map(\.paceSeconds).max() ?? 540
        let dataSlow = (allPaces.max() ?? 540) + pad
        let slow = min(dataSlow, slowestAnchor + 75)
        let fast = max((allPaces.min() ?? 330) - pad, 180)
        self.init(
            samples: samples,
            anchors: anchors,
            paceSlow: slow,
            paceFast: fast,
            bandwidth: bandwidth
        )
    }

    public var body: some View {
        VStack(spacing: 6) {
            anchorLabelRow
                .frame(height: topLabelHeight)
                .padding(.horizontal, 14)
            densityCanvas
                .frame(height: chartHeight)
                .padding(.horizontal, 14)
            axisLabelRow
                .frame(height: axisHeight)
                .padding(.horizontal, 14)
        }
    }

    // MARK: Density canvas

    private var densityCanvas: some View {
        Canvas { ctx, size in
            drawDensityArea(in: ctx, size: size)
            drawAnchorLines(in: ctx, size: size)
        }
    }

    private func drawDensityArea(in ctx: GraphicsContext, size: CGSize) {
        let n = max(2, Int(size.width))
        var ys: [Double] = Array(repeating: 0, count: n)
        var ps: [Double] = Array(repeating: 0, count: n)
        for x in 0..<n {
            let pace = paceFromX(Double(x), width: size.width)
            ps[x] = pace
            ys[x] = densityAt(pace: pace)
        }
        let maxDens = ys.max() ?? 1
        guard maxDens > 0 else { return }

        let plotHeight = size.height
        let plotMaxFill = plotHeight * 0.85

        // Vertical 1px slices, colored by zone.
        for i in 0..<n {
            let h = (ys[i] / maxDens) * plotMaxFill
            guard h > 0 else { continue }
            let pace = ps[i]
            let color = zoneColor(forPace: pace)
            let rect = CGRect(
                x: Double(i),
                y: plotHeight - h,
                width: 1.5,
                height: h
            )
            ctx.fill(Path(rect), with: .color(color))
        }

        // Top edge — thin ink trace.
        var top = Path()
        top.move(to: CGPoint(x: 0, y: plotHeight - (ys[0] / maxDens) * plotMaxFill))
        for i in 1..<n {
            let h = (ys[i] / maxDens) * plotMaxFill
            top.addLine(to: CGPoint(x: Double(i), y: plotHeight - h))
        }
        ctx.stroke(top, with: .color(Color.drip.textPrimary), lineWidth: 1)

        // Baseline hairline.
        var baseline = Path()
        baseline.move(to: CGPoint(x: 0, y: plotHeight))
        baseline.addLine(to: CGPoint(x: size.width, y: plotHeight))
        ctx.stroke(baseline, with: .color(Color.drip.divider), lineWidth: 1)
    }

    private func drawAnchorLines(in ctx: GraphicsContext, size: CGSize) {
        for anchor in anchors {
            let x = xFromPace(anchor.paceSeconds, width: size.width)
            var line = Path()
            line.move(to: CGPoint(x: x, y: 0))
            line.addLine(to: CGPoint(x: x, y: size.height))
            ctx.stroke(line,
                       with: .color(Color.drip.textTertiary.opacity(0.35)),
                       lineWidth: 1)
        }
    }

    // MARK: Label rows

    /// Anchor labels — assigned to one of up to three vertically-stacked
    /// rows via greedy first-fit so tight pace clusters (e.g. MP 5:21 /
    /// 5K 4:42 only ~40s apart) don't collide. The previous `idx % 2`
    /// stagger broke down whenever two same-parity anchors happened to
    /// be close in pace — MP and 5K both land on the odd row and merged
    /// into a "MP5K" smush.
    ///
    /// `topLabelHeight: 90` accommodates 3 rows of ~26pt each.
    private var anchorLabelRow: some View {
        GeometryReader { geo in
            let rows = assignAnchorRows(width: geo.size.width)
            ZStack(alignment: .topLeading) {
                ForEach(Array(anchors.enumerated()), id: \.element.id) { idx, anchor in
                    let x = xFromPace(anchor.paceSeconds, width: geo.size.width)
                    let row = rows[idx]
                    let y = (topLabelHeight / 2 - 8) + CGFloat(row) * 26
                    VStack(spacing: 1) {
                        Text(anchor.label)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .tracking(0.6)
                            .foregroundStyle(anchor.color)
                        Text(formatPace(anchor.paceSeconds))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(Color.drip.textSecondary)
                        Rectangle()
                            .fill(anchor.color)
                            .frame(width: 2, height: 5)
                    }
                    .frame(width: 44)            // narrower so neighboring labels can tuck closer
                    .position(x: x, y: y)
                }
            }
        }
    }

    /// Greedy first-fit row assignment for anchor labels. For each
    /// anchor in axis order, picks the lowest-numbered row whose last
    /// placed label is at least `anchorLabelWidth` away on the x axis.
    /// Falls back to the row with the most horizontal distance from
    /// its last placement when no row is fully clear (rare — only
    /// happens with 4+ anchors clustered within one label width).
    private func assignAnchorRows(width: CGFloat) -> [Int] {
        var lastX: [CGFloat?] = [nil, nil, nil]   // up to 3 rows
        var out: [Int] = []
        out.reserveCapacity(anchors.count)
        for anchor in anchors {
            let x = xFromPace(anchor.paceSeconds, width: width)
            var assigned: Int = -1
            for row in 0..<lastX.count {
                if let lx = lastX[row] {
                    if abs(x - lx) >= anchorLabelWidth {
                        assigned = row
                        break
                    }
                } else {
                    assigned = row
                    break
                }
            }
            if assigned < 0 {
                var best = 0
                var bestDist: CGFloat = -1
                for row in 0..<lastX.count {
                    let d = abs(x - (lastX[row] ?? -1000))
                    if d > bestDist { bestDist = d; best = row }
                }
                assigned = best
            }
            lastX[assigned] = x
            out.append(assigned)
        }
        return out
    }

    private var axisLabelRow: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                ForEach(axisTickPaces, id: \.self) { p in
                    let x = xFromPace(p, width: geo.size.width)
                    Text(formatPace(p))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Color.drip.textTertiary)
                        .position(x: x, y: 10)
                }
            }
        }
    }

    // MARK: Math helpers

    private func paceFromX(_ x: Double, width: Double) -> Double {
        let t = x / max(width, 1)
        return paceSlow - t * (paceSlow - paceFast)
    }

    private func xFromPace(_ pace: Double, width: Double) -> Double {
        let t = (paceSlow - pace) / (paceSlow - paceFast)
        return min(max(t, 0), 1) * width
    }

    /// Kernel density estimate: sum of gaussian contributions from each
    /// sample, weighted by the sample's miles.
    private func densityAt(pace: Double) -> Double {
        let twoSigSq = 2.0 * bandwidth * bandwidth
        var sum = 0.0
        for s in samples {
            let dx = pace - s.paceSeconds
            sum += s.miles * exp(-(dx * dx) / twoSigSq)
        }
        return sum
    }

    /// Decide which anchor's color owns a given pace. Boundary between
    /// adjacent anchors is the midpoint pace.
    private func zoneColor(forPace pace: Double) -> Color {
        guard !anchors.isEmpty else { return Color.drip.textTertiary }
        for (i, a) in anchors.enumerated() {
            if i == anchors.count - 1 {
                // Fastest anchor — owns everything beyond it
                return a.color
            }
            let next = anchors[i + 1]
            let midpoint = (a.paceSeconds + next.paceSeconds) / 2.0
            if pace >= midpoint {
                return a.color
            }
        }
        return anchors.last?.color ?? Color.drip.textTertiary
    }

    /// Adaptive pace-tick interval — picks 1 / 2 / 3 / 5 / 10-minute steps
    /// based on the axis span so labels never crowd into an unreadable
    /// strip. With the previous fixed 60-second step a wide auto-fit axis
    /// (e.g. 4:00–20:00) produced ~17 overlapping labels.
    private var axisTickPaces: [Double] {
        let span = paceSlow - paceFast
        let step: Double = {
            switch span {
            case ..<360:  return 60     // ≤6 min span → 1-min ticks
            case ..<720:  return 120    // ≤12 min span → 2-min ticks
            case ..<1200: return 180    // ≤20 min span → 3-min ticks
            case ..<2400: return 300    // ≤40 min span → 5-min ticks
            default:      return 600    // 10-min ticks
            }
        }()
        let lo = floor(paceFast / step) * step
        let hi = ceil(paceSlow / step) * step
        var ticks: [Double] = []
        var p = lo
        while p <= hi {
            if p >= paceFast && p <= paceSlow { ticks.append(p) }
            p += step
        }
        return ticks
    }

    private func formatPace(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Convenience

public extension PaceVolumeSpectrumChart {

    /// Build the four standard anchors from an athlete's pace profile.
    /// All paces are seconds per mile.
    static func defaultAnchors(
        easyPace: Double,
        marathonPace: Double,
        thresholdPace: Double,
        fiveKPace: Double
    ) -> [PaceAnchor] {
        [
            PaceAnchor(label: "EASY", paceSeconds: easyPace,
                       color: Color.drip.energized),
            PaceAnchor(label: "MP",   paceSeconds: marathonPace,
                       color: Color.drip.textSecondary),
            PaceAnchor(label: "LT",   paceSeconds: thresholdPace,
                       color: Color.drip.coral),
            PaceAnchor(label: "5K",   paceSeconds: fiveKPace,
                       color: Color.drip.textPrimary),
        ]
    }

    /// Convenience builder pulling anchors from an `AthletePaceProfile`-shaped
    /// data object. Pass any object exposing the four pace values.
    /// (Inline so no protocol dependency on the model layer.)
    static func anchors(
        from profile: (easyPace: Double,
                       marathonPace: Double,
                       thresholdPace: Double,
                       fiveKPace: Double)
    ) -> [PaceAnchor] {
        defaultAnchors(
            easyPace: profile.easyPace,
            marathonPace: profile.marathonPace,
            thresholdPace: profile.thresholdPace,
            fiveKPace: profile.fiveKPace
        )
    }
}

// MARK: - Sample assembly helpers
//
// These convert workout-feature time-in-zone data into the chart's
// `[PaceVolumeSample]` input. Use whichever helper matches the data shape
// your dashboard already has.

public extension PaceVolumeSample {

    /// Build samples from per-workout time-in-zone seconds.
    /// `easyPace`, `mpPace` etc. are the athlete's reference paces in
    /// seconds-per-mile. Each non-zero zone time contributes one sample
    /// at that zone's representative pace.
    ///
    /// Use this when you have `workout_features` rows with the standard
    /// easy/moderate/threshold/hard time fields.
    static func fromZoneSeconds(
        easySeconds: Double,
        moderateSeconds: Double,
        thresholdSeconds: Double,
        hardSeconds: Double,
        easyPace: Double,
        mpPace: Double,
        thresholdPace: Double,
        fiveKPace: Double
    ) -> [PaceVolumeSample] {
        func toMiles(_ secs: Double, at pace: Double) -> Double {
            guard pace > 0 else { return 0 }
            return secs / pace
        }
        var out: [PaceVolumeSample] = []
        if easySeconds      > 0 { out.append(.init(paceSeconds: easyPace,
                                                   miles: toMiles(easySeconds, at: easyPace))) }
        if moderateSeconds  > 0 { out.append(.init(paceSeconds: mpPace,
                                                   miles: toMiles(moderateSeconds, at: mpPace))) }
        if thresholdSeconds > 0 { out.append(.init(paceSeconds: thresholdPace,
                                                   miles: toMiles(thresholdSeconds, at: thresholdPace))) }
        if hardSeconds      > 0 { out.append(.init(paceSeconds: fiveKPace,
                                                   miles: toMiles(hardSeconds, at: fiveKPace))) }
        return out
    }
}

// MARK: - Preview

#if DEBUG
struct PaceVolumeSpectrumChart_Previews: PreviewProvider {

    /// ~47 mile training week for a sub-3:10 marathoner mid-block. Multiple
    /// samples per zone so the KDE gives a believable shape rather than four
    /// sharp spikes.
    static let mockSamples: [PaceVolumeSample] = [
        // Easy block — broad spread (recovery + steady aerobic)
        .init(paceSeconds: 540, miles: 4),    // 9:00
        .init(paceSeconds: 525, miles: 4),    // 8:45
        .init(paceSeconds: 510, miles: 8),    // 8:30
        .init(paceSeconds: 495, miles: 6),    // 8:15
        .init(paceSeconds: 480, miles: 4),    // 8:00
        .init(paceSeconds: 465, miles: 2),    // 7:45
        // MP work — clustered around 7:15 (the 11-mi MP run)
        .init(paceSeconds: 440, miles: 2),    // 7:20
        .init(paceSeconds: 435, miles: 5),    // 7:15
        .init(paceSeconds: 432, miles: 2),    // 7:12
        // LT work — tempo session at ~6:35
        .init(paceSeconds: 400, miles: 1),    // 6:40
        .init(paceSeconds: 395, miles: 3),    // 6:35
        // 5K-pace work — strides + intervals at 6:00
        .init(paceSeconds: 365, miles: 0.5),  // 6:05
        .init(paceSeconds: 360, miles: 1.5),  // 6:00
    ]

    static var previews: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("PACE & VOLUME")
                    .font(.dripCaption(11))
                    .tracking(1.2)
                    .foregroundStyle(Color.drip.textSecondary)
                Spacer()
                Text("47.2 MI · WEEK 09")
                    .font(.dripCaption(11))
                    .foregroundStyle(Color.drip.textSecondary)
            }

            PaceVolumeSpectrumChart(
                samples: mockSamples,
                anchors: PaceVolumeSpectrumChart.defaultAnchors(
                    easyPace:      510,    // 8:30
                    marathonPace:  435,    // 7:15
                    thresholdPace: 395,    // 6:35
                    fiveKPace:     360     // 6:00
                ),
                paceSlow: 540,
                paceFast: 330,
                bandwidth: 18
            )
        }
        .padding(20)
        .background(Color.drip.background)
        .previewLayout(.sizeThatFits)
        .previewDisplayName("Pace × Volume Spectrum")
    }
}
#endif

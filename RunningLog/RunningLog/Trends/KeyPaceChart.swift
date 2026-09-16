//
//  KeyPaceChart.swift
//  RunningLog · Trends
//
//  The one renderer for key pace. The card passes 140pt, the detail passes
//  250pt; there is no second implementation, and adding one would let the
//  glance and the detail disagree about the same sessions.
//
//  Draw order, back to front: band → stepped anchor → gridlines → trend →
//  heat ticks → dots → field marks → crosshair → hit layer.
//
//  **Encodings.** Hue is zone, and only zone — the `PaceSpectrum` ramp,
//  per the three-palette rule. Grade is carried by *fill* (solid / hollow /
//  dotted ring) so it survives greyscale and colour-blind rendering. Long runs
//  are diamonds, not dots, because their pace is a whole-run mean rather than
//  a work-bout pace. Coral appears exactly once, on the latest session.
//
//  **Interaction.** A drag anywhere over the plot moves a crosshair to the
//  nearest session and updates the binding; `KeyPaceReadout` below the chart
//  shows what the crosshair is on and is itself the tap target that opens the
//  workout. The readout is the primary affordance rather than a floating
//  tooltip: a tooltip vanishes on touch-up, which is useless on a phone and
//  invisible to VoiceOver.
//

import SwiftUI

// MARK: - Density

/// How many layers the chart is allowed to draw.
///
/// The card and the detail render the same view, but 140pt of height cannot
/// carry six overlapping layers legibly — band fill, band edges, a weekly
/// staircase, heat ticks, a trend and 28 dots turn into noise. The glance
/// keeps the three layers that answer "how am I tracking" and drops the rest;
/// the detail, at 250pt with controls beside it, draws everything.
enum KeyPaceDensity {
    /// Card. Band wash, dots, trend, crosshair.
    case glance
    /// Detail. Adds band edges, the weekly target staircase, and ghost ticks.
    case full

    var drawsAnchorSteps: Bool { self == .full }
    var drawsGhostTicks: Bool { self == .full }
    var drawsBandEdges: Bool { self == .full }
    var bandOpacity: Double { self == .full ? 0.10 : 0.07 }
}

// MARK: - Chart

struct KeyPaceChart: View {

    let points: [KeyPacePoint]
    /// Weekly band anchor, already clipped to the window. Empty when there is
    /// no ladder — the chart then draws no target and says nothing about one.
    let anchorSteps: [KeyPaceAnchorStep]
    /// The band edges at the end of the window, sec/mi. `nil` draws no band.
    let band: (fast: Int, slow: Int)?
    let anchorSec: Int?
    let anchorColor: Color
    let lowConfidence: Bool
    let mode: KeyPaceMode
    /// Which pace the dots are. The other one becomes the ghost tick.
    let basis: KeyPaceBasis
    let showHeatTicks: Bool
    let trend: KeyPaceTrend?
    /// Min/max measured volume across the visible set, for the dot-size scale.
    /// `nil` draws every dot at the base radius.
    let volumeDomain: (lo: Double, hi: Double)?
    /// Which second track to draw under the plot.
    var lane: KeyPaceLane = .off
    /// HR range, used when `lane == .heartRate`. `nil` hides the lane.
    let hrDomain: (lo: Int, hi: Int)?
    /// Efficiency range, used when `lane == .efficiency`.
    let efficiencyDomain: (lo: Double, hi: Double)?
    /// Median efficiency — the lane's reference line, drawn instead of the HR
    /// floor because there is no floor to draw on this scale.
    var medianEfficiency: Double?
    /// The floor the grade rule used **for the selected zone**, drawn as a
    /// line in the HR lane. `nil` across all zones — there is no one floor to
    /// draw when six zones are on screen, which was the whole problem with the
    /// single 160.
    var hrFloor: Int?
    var density: KeyPaceDensity = .full
    let height: CGFloat
    /// Dot radius — the card draws smaller marks than the detail.
    var dotRadius: CGFloat = 4
    /// Footer hint between the two date ticks.
    var hint: String = "DRAG TO SCRUB · TAP TO OPEN"

    @Binding var selected: KeyPacePoint?
    let onOpen: (KeyPacePoint) -> Void

    // Left gutter for the y labels, right gutter so the last dot isn't clipped.
    private let gutterLeading: CGFloat = 36
    private let gutterTrailing: CGFloat = 10
    private let axisHeight: CGFloat = 16

    /// Points that can be plotted in the current mode. In `.vsTarget` a point
    /// with no zone target is omitted rather than drawn at a fabricated zero.
    private var plotted: [KeyPacePoint] {
        points.filter { $0.value(mode: mode, basis: basis) != nil }
    }

    private var ghostsVisible: Bool { showHeatTicks && density.drawsGhostTicks }

    private var laneVisible: Bool {
        guard lane.isVisible, !plotted.isEmpty else { return false }
        switch lane {
        case .heartRate: return hrDomain != nil
        case .efficiency: return efficiencyDomain != nil
        case .off: return false
        }
    }
    private var laneHeight: CGFloat { laneVisible ? 34 : 0 }

    /// Dot radius from volume, **area-proportional** — the eye reads a mark's
    /// area, not its radius, so mapping volume straight onto radius would
    /// exaggerate a long session by its square. Hence `sqrt`.
    ///
    /// A point with no measured volume draws at the base radius rather than at
    /// the minimum: absent volume is not the same fact as a short session.
    private func radius(for point: KeyPacePoint) -> CGFloat {
        guard let domain = volumeDomain, let value = point.volumeValue else { return dotRadius }
        let span = max(domain.hi - domain.lo, 0.000_1)
        let t = min(max((value - domain.lo) / span, 0), 1)
        let rMin = dotRadius * 0.60
        let rMax = dotRadius * 1.85
        return rMin + (rMax - rMin) * CGFloat(t.squareRoot())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(mode.axisLabel)
                .instrumentTick()
                .padding(.bottom, 4)

            if plotted.isEmpty {
                emptyPlot
            } else {
                plot
                if laneVisible { secondLane }
                axis
            }
        }
    }

    // MARK: Empty

    private var emptyPlot: some View {
        // Not an em-dash and not a blank box (hard rule #8): the axis frame is
        // drawn so the surface still reads as a chart, with words inside it.
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.drip.divider, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            Text(mode == .vsTarget
                 ? "NO TARGETS FOR THESE SESSIONS YET"
                 : "NO SESSIONS IN THIS ZONE AND WINDOW")
                .instrumentTick()
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
        }
        .frame(height: height)
    }

    // MARK: Plot

    private var plot: some View {
        GeometryReader { geo in
            let layout = Layout(
                size: geo.size,
                gutterLeading: gutterLeading,
                gutterTrailing: gutterTrailing,
                points: plotted,
                mode: mode,
                basis: basis,
                band: mode == .absolute ? band : nil,
                showGhosts: ghostsVisible
            )

            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    drawBand(in: context, layout: layout)
                    drawAnchorSteps(in: context, layout: layout)
                    drawGrid(in: context, layout: layout)
                    drawTrend(in: context, layout: layout)
                    drawHeatTicks(in: context, layout: layout)
                }

                gridLabels(layout: layout)
                crosshair(layout: layout)
                dots(layout: layout)
                hitLayer(layout: layout)
            }
        }
        .frame(height: height)
    }

    // MARK: The second lane

    /// Efficiency or heart rate, on the same x-axis as the plot.
    ///
    /// It is a lane rather than a fifth channel on the dot. The mark already
    /// carries zone (hue), grade (fill), volume (area) and long-run (shape);
    /// folding effort in as well would make all five unreadable, and this
    /// file's rule is that no channel encodes two things.
    ///
    /// The reference line differs by reading, and that difference is the point:
    ///   • **Heart rate** draws the grade *floor*, because the fill of every
    ///     dot above is defined by it — a session under the line is exactly a
    ///     hollow dot, which makes the rule visible instead of documented.
    ///   • **Efficiency** has no floor to draw, so it draws the window's
    ///     median. Above the line is a better-than-usual day for this athlete;
    ///     there is no external standard for metres per beat and the chart
    ///     should not imply one.
    private var secondLane: some View {
        GeometryReader { geo in
            let layout = Layout(
                size: geo.size,
                gutterLeading: gutterLeading,
                gutterTrailing: gutterTrailing,
                points: plotted,
                mode: mode,
                basis: basis,
                band: nil,
                showGhosts: false
            )

            // One mapping for both readings: value → y, higher is better on
            // each scale (a bigger m/beat, a higher bpm).
            let bounds: (lo: Double, hi: Double) = {
                switch lane {
                case .efficiency: efficiencyDomain ?? (0, 1)
                case .heartRate:
                    hrDomain.map { (Double($0.lo), Double($0.hi)) } ?? (100, 200)
                case .off: (0, 1)
                }
            }()
            let span = max(bounds.hi - bounds.lo, 0.000_1)
            let yFor: (Double) -> CGFloat = { value in
                geo.size.height - CGFloat((value - bounds.lo) / span) * geo.size.height
            }
            let reference: Double? = {
                switch lane {
                case .efficiency: medianEfficiency
                case .heartRate: hrFloor.flatMap { $0 > 0 ? Double($0) : nil }
                case .off: nil
                }
            }()
            let valueFor: (KeyPacePoint) -> Double? = { point in
                switch lane {
                case .efficiency: point.metresPerBeat(basis)
                case .heartRate: point.hrAvg.map(Double.init)
                case .off: nil
                }
            }

            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    if let reference, reference >= bounds.lo, reference <= bounds.hi {
                        var line = Path()
                        line.move(to: CGPoint(x: layout.plotMinX, y: yFor(reference)))
                        line.addLine(to: CGPoint(x: layout.plotMaxX, y: yFor(reference)))
                        context.stroke(
                            line,
                            with: .color(Color.drip.textTertiary.opacity(0.8)),
                            style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                        )
                    }
                    for point in plotted {
                        guard let value = valueFor(point) else { continue }
                        let x = layout.x(Double(point.dayNumber))
                        let y = yFor(value)
                        var tick = Path()
                        tick.move(to: CGPoint(x: x, y: size.height))
                        tick.addLine(to: CGPoint(x: x, y: y))
                        context.stroke(
                            tick,
                            with: .color(KeyZone.color(point.zone).opacity(0.28)),
                            lineWidth: 1
                        )
                        context.fill(
                            Path(ellipseIn: CGRect(x: x - 1.8, y: y - 1.8, width: 3.6, height: 3.6)),
                            with: .color(
                                point.id == plotted.last?.id
                                    ? Color.drip.coral
                                    : KeyZone.color(point.zone)
                            )
                        )
                    }
                }

                Text(lane.axisLabel)
                    .instrumentTick()
                    .frame(width: gutterLeading - 6, alignment: .trailing)
                    .position(x: (gutterLeading - 6) / 2, y: 6)

                if let reference, reference >= bounds.lo, reference <= bounds.hi {
                    Text(referenceLabel(reference))
                        .instrumentTick()
                        .frame(width: gutterLeading - 6, alignment: .trailing)
                        .position(x: (gutterLeading - 6) / 2, y: yFor(reference))
                }
            }
        }
        .frame(height: laneHeight)
        .padding(.top, 8)
        .accessibilityHidden(true)
    }

    private func referenceLabel(_ value: Double) -> String {
        switch lane {
        case .efficiency: String(format: "MED %.2f", value)
        case .heartRate: "FLOOR \(Int(value))"
        case .off: ""
        }
    }

    // MARK: Band

    private func drawBand(in context: GraphicsContext, layout: Layout) {
        guard mode == .absolute, let band else { return }
        let top = layout.y(Double(band.fast))
        let bottom = layout.y(Double(band.slow))
        let rect = CGRect(
            x: layout.plotMinX,
            y: min(top, bottom),
            width: layout.plotWidth,
            height: max(abs(bottom - top), 1)
        )
        context.fill(Path(rect), with: .color(anchorColor.opacity(density.bandOpacity)))

        guard density.drawsBandEdges else { return }
        let dash: [CGFloat] = lowConfidence ? [2, 4] : [4, 3]
        for value in [band.fast, band.slow] {
            var line = Path()
            line.move(to: CGPoint(x: layout.plotMinX, y: layout.y(Double(value))))
            line.addLine(to: CGPoint(x: layout.plotMaxX, y: layout.y(Double(value))))
            context.stroke(
                line,
                with: .color(anchorColor.opacity(0.55)),
                style: StrokeStyle(lineWidth: 1, dash: dash)
            )
        }
    }

    /// The anchor as it actually behaves: a weekly step, never a smooth curve.
    ///
    /// **One connected staircase, not a row of floating bars.** Drawn as
    /// disconnected segments this read as scattered ramp-colored dashes at random
    /// heights — indistinguishable from data, and the first thing anyone
    /// pointed at when asked what was confusing. Each tread now runs to the
    /// next one's start and a riser joins them, so the line is continuous and
    /// obviously a reference rather than a series.
    ///
    /// It is also deliberately subordinate: thinner than a data stroke and
    /// well under full opacity, so it sits behind the dots instead of
    /// competing with them for the same color.
    private func drawAnchorSteps(in context: GraphicsContext, layout: Layout) {
        guard mode == .absolute, density.drawsAnchorSteps else { return }
        let steps = anchorSteps.sorted { $0.startDay < $1.startDay }
        guard !steps.isEmpty else { return }

        var path = Path()
        var started = false
        var lastY: CGFloat?

        for step in steps {
            let y = layout.y(Double(step.sec))
            let x0 = max(layout.x(Double(step.startDay)), layout.plotMinX)
            let x1 = min(layout.x(Double(step.endDay)), layout.plotMaxX)
            guard x1 >= layout.plotMinX, x0 <= layout.plotMaxX, x1 >= x0 else { continue }

            if !started {
                path.move(to: CGPoint(x: x0, y: y))
                started = true
            } else if let lastY, lastY != y {
                // The riser. Without it the treads read as unrelated bars.
                path.addLine(to: CGPoint(x: x0, y: lastY))
                path.addLine(to: CGPoint(x: x0, y: y))
            } else {
                path.addLine(to: CGPoint(x: x0, y: y))
            }
            path.addLine(to: CGPoint(x: x1, y: y))
            lastY = y
        }
        guard started else { return }

        context.stroke(
            path,
            with: .color(anchorColor.opacity(0.45)),
            style: StrokeStyle(lineWidth: 1.1, lineCap: .butt, lineJoin: .miter)
        )
    }

    // MARK: Grid

    private func drawGrid(in context: GraphicsContext, layout: Layout) {
        for tick in layout.ticks {
            var line = Path()
            line.move(to: CGPoint(x: layout.plotMinX, y: layout.y(tick.value)))
            line.addLine(to: CGPoint(x: layout.plotMaxX, y: layout.y(tick.value)))
            context.stroke(line, with: .color(Color.drip.divider), lineWidth: 1)
        }
    }

    private func gridLabels(layout: Layout) -> some View {
        ForEach(layout.ticks) { tick in
            Text(tick.label)
                .instrumentTick()
                .frame(width: gutterLeading - 6, alignment: .trailing)
                .position(x: (gutterLeading - 6) / 2, y: layout.y(tick.value))
        }
    }

    // MARK: Trend

    private func drawTrend(in context: GraphicsContext, layout: Layout) {
        guard mode == .absolute, let trend else { return }
        var path = Path()
        path.move(to: CGPoint(
            x: layout.plotMinX,
            y: layout.y(trend.sec(atDay: layout.dayLo))
        ))
        path.addLine(to: CGPoint(
            x: layout.plotMaxX,
            y: layout.y(trend.sec(atDay: layout.dayHi))
        ))
        context.stroke(
            path,
            with: .color(Color.drip.textPrimary.opacity(0.5)),
            style: StrokeStyle(lineWidth: 1.4, dash: [1, 3])
        )
    }

    // MARK: Heat

    /// A hairline from the dot to where the OTHER basis would put it, so the
    /// heat correction is visible being applied rather than applied silently.
    ///
    /// No end cap any more: capped, these read as error bars, which is a
    /// different and much stronger claim than "the weather moved this by four
    /// seconds". A plain hairline with a small open marker says it is the same
    /// session measured another way.
    private func drawHeatTicks(in context: GraphicsContext, layout: Layout) {
        guard ghostsVisible else { return }
        for point in plotted {
            guard let value = point.value(mode: mode, basis: basis),
                  let ghost = point.ghostValue(mode: mode, basis: basis)
            else { continue }
            let x = layout.x(Double(point.dayNumber))
            let y0 = layout.y(Double(value))
            let y1 = layout.y(Double(ghost))
            var path = Path()
            path.move(to: CGPoint(x: x, y: y0))
            path.addLine(to: CGPoint(x: x, y: y1))
            context.stroke(path, with: .color(Color.drip.textTertiary.opacity(0.45)), lineWidth: 1)
            context.stroke(
                Path(ellipseIn: CGRect(x: x - 1.6, y: y1 - 1.6, width: 3.2, height: 3.2)),
                with: .color(Color.drip.textTertiary.opacity(0.7)),
                lineWidth: 1
            )
        }
    }

    // MARK: Dots

    private func dots(layout: Layout) -> some View {
        ForEach(plotted) { point in
            let value = point.value(mode: mode, basis: basis) ?? 0
            let isLatest = point.id == plotted.last?.id
            let colour = isLatest ? Color.drip.coral : KeyZone.color(point.zone)

            let r = radius(for: point)

            KeyPaceMark(
                grade: point.grade,
                isLongRun: point.isLongRun,
                colour: colour,
                radius: r
            )
            .frame(width: r * 2 + 4, height: r * 2 + 4)
            .overlay {
                if isLatest {
                    Circle()
                        .stroke(Color.drip.coral.opacity(0.45), lineWidth: 1)
                        .frame(width: r * 2 + 7, height: r * 2 + 7)
                }
            }
            .position(x: layout.x(Double(point.dayNumber)), y: layout.y(Double(value)))
            .accessibilityElement()
            .accessibilityLabel(point.accessibilityLabel)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onOpen(point) }
        }
    }

    // MARK: Crosshair

    @ViewBuilder
    private func crosshair(layout: Layout) -> some View {
        if let selected, let value = selected.value(mode: mode, basis: basis),
           plotted.contains(where: { $0.id == selected.id }) {
            let x = layout.x(Double(selected.dayNumber))
            Rectangle()
                .fill(Color.drip.textSecondary.opacity(0.55))
                .frame(width: 1, height: layout.plotHeight)
                .position(x: x, y: layout.plotHeight / 2)
                .allowsHitTesting(false)

            let r = radius(for: selected)
            Circle()
                .stroke(Color.drip.textPrimary, lineWidth: 1.2)
                .frame(width: r * 2 + 10, height: r * 2 + 10)
                .position(x: x, y: layout.y(Double(value)))
                .allowsHitTesting(false)
        }
    }

    // MARK: Hit layer

    private func hitLayer(layout: Layout) -> some View {
        Rectangle()
            .fill(.clear)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if let nearest = layout.nearest(toX: value.location.x) {
                            if nearest.id != selected?.id {
                                selected = nearest
                            }
                        }
                    }
                    .onEnded { value in
                        // A tap is a drag with no travel. Only that opens the
                        // workout; a scrub selects and stops there.
                        guard abs(value.translation.width) < 6,
                              abs(value.translation.height) < 6,
                              let nearest = layout.nearest(toX: value.location.x)
                        else { return }
                        selected = nearest
                        onOpen(nearest)
                    }
            )
            // The dots above carry the per-point accessibility elements; this
            // layer must not swallow them.
            .accessibilityHidden(true)
    }

    // MARK: Axis

    private var axis: some View {
        HStack(alignment: .firstTextBaseline) {
            Text((plotted.first?.dateLabel ?? "").uppercased()).instrumentTick()
            Spacer(minLength: 6)
            Text(hint).instrumentTick()
            Spacer(minLength: 6)
            Text((plotted.last?.dateLabel ?? "").uppercased()).instrumentTick()
        }
        .padding(.top, 4)
        .frame(height: axisHeight)
        .accessibilityHidden(true)
    }
}

// MARK: - Layout

/// One gridline. A struct rather than a tuple because `ForEach(_:id:)` needs a
/// key path, and Swift has no key paths into tuple elements.
struct KeyPaceTick: Identifiable, Equatable {
    let value: Double
    let label: String
    var id: Double { value }
}

private extension KeyPaceChart {

    /// Domain → view mapping, computed once per render.
    struct Layout {
        let size: CGSize
        let gutterLeading: CGFloat
        let gutterTrailing: CGFloat
        let points: [KeyPacePoint]
        let dayLo: Double
        let dayHi: Double
        let valueLo: Double
        let valueHi: Double
        let ticks: [KeyPaceTick]

        var plotMinX: CGFloat { gutterLeading }
        var plotMaxX: CGFloat { max(size.width - gutterTrailing, gutterLeading + 1) }
        var plotWidth: CGFloat { plotMaxX - plotMinX }
        var plotHeight: CGFloat { size.height }

        init(
            size: CGSize,
            gutterLeading: CGFloat,
            gutterTrailing: CGFloat,
            points: [KeyPacePoint],
            mode: KeyPaceMode,
            basis: KeyPaceBasis,
            band: (fast: Int, slow: Int)?,
            showGhosts: Bool
        ) {
            self.size = size
            self.gutterLeading = gutterLeading
            self.gutterTrailing = gutterTrailing
            self.points = points

            let days = points.map { Double($0.dayNumber) }
            let lo = days.min() ?? 0
            let hi = days.max() ?? 1
            // A single session would give a zero-width domain; give it a day of
            // room so it lands mid-plot rather than on the axis.
            self.dayLo = lo == hi ? lo - 0.5 : lo
            self.dayHi = lo == hi ? hi + 0.5 : hi

            var values = points.compactMap { $0.value(mode: mode, basis: basis).map(Double.init) }
            if showGhosts {
                values += points.compactMap { $0.ghostValue(mode: mode, basis: basis).map(Double.init) }
            }
            if let band {
                values.append(Double(band.fast))
                values.append(Double(band.slow))
            }
            let vLo = values.min() ?? 0
            let vHi = values.max() ?? 1
            let pad = max((vHi - vLo) * 0.14, 5)
            self.valueLo = vLo - pad
            self.valueHi = vHi + pad

            self.ticks = Layout.makeTicks(lo: self.valueLo, hi: self.valueHi, mode: mode)
        }

        /// Faster (fewer seconds, or a more negative delta) plots higher.
        func y(_ value: Double) -> CGFloat {
            let span = max(valueHi - valueLo, 1)
            return CGFloat((value - valueLo) / span) * plotHeight
        }

        func x(_ day: Double) -> CGFloat {
            let span = max(dayHi - dayLo, 1)
            return plotMinX + CGFloat((day - dayLo) / span) * plotWidth
        }

        func nearest(toX px: CGFloat) -> KeyPacePoint? {
            points.min { a, b in
                abs(x(Double(a.dayNumber)) - px) < abs(x(Double(b.dayNumber)) - px)
            }
        }

        /// Round gridlines. Pace ticks land on 5/10/20-second marks so the
        /// labels read as paces rather than as arbitrary samples.
        static func makeTicks(lo: Double, hi: Double, mode: KeyPaceMode) -> [KeyPaceTick] {
            let span = hi - lo
            let step: Double = span > 70 ? 20 : span > 34 ? 10 : 5
            var out: [KeyPaceTick] = []
            var value = (lo / step).rounded(.up) * step
            while value <= hi, out.count < 8 {
                let label = switch mode {
                case .absolute: TrendsFormat.pace(Int(value.rounded()))
                case .vsTarget: KeyPaceProse.signedSec(value)
                }
                out.append(KeyPaceTick(value: value, label: label))
                value += step
            }
            return out
        }
    }
}

// MARK: - One mark

/// Zone by hue, grade by fill, long run by shape. No mark ever encodes two
/// facts in one channel.
struct KeyPaceMark: View {
    let grade: ThresholdGrade
    let isLongRun: Bool
    let colour: Color
    let radius: CGFloat

    var body: some View {
        Group {
            if isLongRun {
                // A whole-run mean, not a work-bout pace. Different quantity,
                // different shape.
                Diamond()
                    .fill(Color.drip.cardBackground)
                    .overlay(Diamond().stroke(colour, lineWidth: 1.4))
                    .frame(width: radius * 2.3, height: radius * 2.3)
            } else {
                switch grade {
                case .work:
                    Circle()
                        .fill(colour)
                        .overlay(Circle().stroke(Color.drip.cardBackground, lineWidth: 1.2))
                        .frame(width: radius * 2, height: radius * 2)
                case .cruise:
                    Circle()
                        .fill(Color.drip.cardBackground)
                        .overlay(Circle().stroke(colour, lineWidth: 1.6))
                        .frame(width: radius * 2, height: radius * 2)
                case .unclassed:
                    Circle()
                        .fill(Color.drip.cardBackground)
                        .overlay(
                            Circle().stroke(
                                colour,
                                style: StrokeStyle(lineWidth: 1.4, dash: [1.6, 1.6])
                            )
                        )
                        .frame(width: radius * 2, height: radius * 2)
                }
            }
        }
    }
}

struct Diamond: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Readout

/// What the crosshair is on, and the way out to the workout. Persistent by
/// design: it survives touch-up, reads aloud, and gives the chart a 44pt tap
/// target that a 9pt dot never could.
struct KeyPaceReadout: View {
    let point: KeyPacePoint
    var basis: KeyPaceBasis = .watch
    let onOpen: (KeyPacePoint) -> Void

    var body: some View {
        Button {
            onOpen(point)
        } label: {
            HStack(spacing: 9) {
                KeyPaceMark(
                    grade: point.grade,
                    isLongRun: point.isLongRun,
                    colour: KeyZone.color(point.zone),
                    radius: 4
                )
                .frame(width: 10, height: 10)

                VStack(alignment: .leading, spacing: 2) {
                    Text(caption)
                        .font(.dripEyebrow(8.5))
                        .tracking(0.85)
                        .foregroundStyle(Color.drip.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                    Text(point.structure ?? "\(KeyZone.label(point.zone)) session")
                        .font(.dripDisplay(14))
                        .foregroundStyle(Color.drip.textPrimary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(TrendsFormat.pace(point.sec(basis)))
                        .font(.dripStat(14))
                        .foregroundStyle(Color.drip.textPrimary)
                    Text(trailing)
                        .font(.dripEyebrow(8))
                        .tracking(0.64)
                        .foregroundStyle(Color.drip.textTertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .background(Color.drip.background)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8).stroke(Color.drip.divider, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open \(point.accessibilityLabel)")
        .accessibilityAddTraits(.isButton)
    }

    /// Date · zone · volume · heart rate. Volume and HR sit here rather than
    /// on the mark because the mark already carries four facts.
    private var caption: String {
        var bits = [point.dateLabel.uppercased(), KeyZone.label(point.zone).uppercased()]
        if let volume = point.volumeShortLabel { bits.append(volume) }
        if let efficiency = point.efficiencyLabel(basis) { bits.append(efficiency) }
        // The swatch to the left already shows the grade. Naming it as well is
        // only worth the width when it is the exception — a session under the
        // floor, or one with no heart rate at all.
        switch point.grade {
        case .work:
            if let hr = point.hrAvg { bits.append("\(hr) BPM") }
        case .cruise:
            bits.append(point.hrAvg.map { "\($0) BPM · UNDER FLOOR" } ?? "UNDER FLOOR")
        case .unclassed:
            bits.append("NO HR")
        }
        if point.isLongRun { bits.append("LONG") }
        return bits.joined(separator: " · ")
    }

    /// The correction, named, then the target delta. Watch pace leads; the
    /// adjusted number is offered, never substituted.
    private var trailing: String {
        var bits: [String] = []
        if point.hasCorrection {
            bits.append("+\(point.correctionSec)s HEAT → \(TrendsFormat.pace(point.sec(basis.other)))")
        }
        if let delta = point.delta(basis) {
            bits.append("\(KeyPaceProse.signedSec(delta)) VS \(KeyZone.label(point.zone).uppercased())")
        }
        return bits.isEmpty ? "OPEN" : bits.joined(separator: " · ")
    }
}

// MARK: - Zone chips

/// The filter row. Every zone the classifier can emit gets a chip, including
/// the ones with nothing in them — a missing chip reads as "this zone does not
/// exist", which is a different and wrong claim.
struct KeyPaceZoneChips: View {
    let read: KeyPaceRead
    let includeLongRuns: Bool
    @Binding var zone: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chip(
                    label: "ALL",
                    colour: nil,
                    count: read.count(zone: nil, includeLongRuns: includeLongRuns),
                    isOn: zone == nil
                ) { zone = nil }

                ForEach(KeyZone.chipOrder, id: \.self) { token in
                    chip(
                        label: KeyZone.label(token).uppercased(),
                        colour: KeyZone.color(token),
                        count: read.count(zone: token, includeLongRuns: includeLongRuns),
                        isOn: zone == token
                    ) { zone = token }
                }
            }
            .padding(.vertical, 1)
        }
        .scrollClipDisabled()
    }

    private func chip(
        label: String,
        colour: Color?,
        count: Int,
        isOn: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let colour {
                    Circle().fill(colour).frame(width: 7, height: 7)
                }
                Text(label)
                    .font(.dripEyebrow(9).weight(.semibold))
                    .tracking(0.72)
                Text("\(count)")
                    .font(.dripEyebrow(9))
                    .tracking(0.72)
                    .foregroundStyle(isOn ? Color.drip.background.opacity(0.65) : Color.drip.textTertiary)
            }
            .foregroundStyle(isOn ? Color.drip.background : Color.drip.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(minHeight: 32)
            .background(isOn ? Color.drip.textPrimary : Color.drip.cardBackground)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(isOn ? Color.clear : Color.drip.divider, lineWidth: 1))
            .opacity(count == 0 && !isOn ? 0.34 : 1)
        }
        .buttonStyle(.plain)
        .disabled(count == 0 && !isOn)
        .accessibilityLabel("\(label), \(count) \(count == 1 ? "session" : "sessions")")
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Legend

struct KeyPaceLegend: View {
    let read: KeyPaceRead
    let includeLongRuns: Bool
    let showHeatTicks: Bool
    let mode: KeyPaceMode
    let basis: KeyPaceBasis
    var hasVolume: Bool = false
    var lane: KeyPaceLane = .off
    var hrFloor: Int?
    var density: KeyPaceDensity = .full

    var body: some View {
        InstrumentLegendRow(items: items)
    }

    /// Short labels, and only for layers actually drawn.
    ///
    /// The glance collapses the three grade swatches into one statement.
    /// Spelling out WORK / CRUISE / NO HR costs three entries and a second
    /// line to explain an encoding the reader picks up from one: filled means
    /// the heart rate cleared the floor, and everything else is visibly not
    /// filled. The detail, which has the HR lane and the floor line beside it,
    /// spells all three out.
    private var items: [(InstrumentLegendItem.Swatch, String)] {
        var out: [(InstrumentLegendItem.Swatch, String)] = []

        switch density {
        case .glance:
            out.append((.dot(Color.drip.textPrimary), "FILLED · OVER HR FLOOR"))
        case .full:
            out.append((.dot(Color.drip.textPrimary), "WORK"))
            out.append((.dot(Color.drip.textTertiary), "CRUISE"))
            out.append((.dot(Color.drip.divider), "NO HR"))
        }

        if hasVolume {
            out.append((.dot(Color.drip.textSecondary), "SIZE · MILES OF WORK"))
        }
        if includeLongRuns {
            out.append((.fill(PaceSpectrum.mp), "LONG RUN"))
        }
        if mode == .absolute, read.hasBand {
            out.append((
                .fill(read.anchor.color(in: read.ladder).opacity(0.25)),
                "\(read.anchor.label) BAND \(read.settings.widthLabel)"
            ))
        }

        // Everything below is detail-only: the glance does not draw these
        // layers, and naming a layer that is not on screen is worse than
        // saying nothing.
        guard density == .full else { return out }

        if showHeatTicks, density.drawsGhostTicks {
            out.append((.line(Color.drip.textTertiary), basis.other.short))
        }
        switch lane {
        case .efficiency:
            out.append((.line(Color.drip.textTertiary), "M/BEAT LANE · MEDIAN DASHED"))
        case .heartRate:
            out.append((
                .line(Color.drip.textTertiary),
                hrFloor == nil ? "HR LANE · FLOOR IS PER ZONE" : "HR LANE · ZONE FLOOR DASHED"
            ))
        case .off:
            break
        }
        if density.drawsAnchorSteps, mode == .absolute, read.hasBand {
            out.append((.line(read.anchor.color(in: read.ladder).opacity(0.45)), "WEEKLY TARGET"))
        }
        out.append((.dot(Color.drip.coral), "LATEST"))
        return out
    }
}

// MARK: - Stat row

/// Three derived figures. The middle one is the honest-trend rule made visible:
/// with ALL selected it reports how many zones are in play, because a slope
/// across zones would be a number that means nothing.
struct KeyPaceStatRow: View {
    let read: KeyPaceRead
    let zone: String?
    let includeLongRuns: Bool
    var basis: KeyPaceBasis = .watch

    var body: some View {
        InstrumentStatRow(items: items)
    }

    private var items: [InstrumentStatRow.Item] {
        let pts = read.points(zone: zone, includeLongRuns: includeLongRuns)
        let graded = pts.filter(\.isWork).count

        // When the trend is fitted on a subset, the count stat says so itself.
        //
        // It used to read "12 SESSIONS / LT ONLY" beside a slope computed from
        // nine of them, which invites exactly the wrong inference. And the
        // phrase that used to carry this — "GRADED WORK ONLY", under the slope
        // — was jargon: nothing on screen said what grading was. "9 OVER HR
        // FLOOR" is the same fact in words that match the legend the reader
        // just looked at.
        var out: [InstrumentStatRow.Item] = [
            .init(
                value: "\(pts.count)",
                unit: "SESSIONS",
                detail: graded < pts.count
                    ? "\(graded) OVER HR FLOOR"
                    : (zone.map { "\(KeyZone.label($0).uppercased()) ONLY" } ?? "ALL ZONES")
            )
        ]

        if zone == nil {
            let zones = read.zonesPresent(includeLongRuns: includeLongRuns).count
            out.append(.init(value: "\(zones)", unit: "ZONES", detail: "TRENDS ARE PER ZONE"))
        } else if let slope = read.trendSecPerMonth(
            zone: zone, includeLongRuns: includeLongRuns, basis: basis
        ) {
            // A slope under half a second per 30 days rounds to "0s", which
            // reads as a missing value rather than as the finding it is. Flat
            // is a real answer — say it as a word, the way the note does.
            let isFlat = Int(abs(slope).rounded()) == 0
            out.append(.init(
                value: isFlat ? "FLAT" : KeyPaceProse.signedSec(slope),
                unit: isFlat ? "TREND" : "PER 30 D",
                detail: basis == .watch ? "NOT HEAT-ADJUSTED" : "HEAT-ADJUSTED"
            ))
        } else {
            out.append(.init(value: "NOT YET", unit: "PER 30 D", detail: "NEEDS 3 GRADED"))
        }

        // Volume displaces the in-band count when it exists: "how much work at
        // this pace" is the question the dot sizes are already answering, and
        // three stats is the row's width.
        if let miles = read.totalBandMiles(zone: zone, includeLongRuns: includeLongRuns) {
            // The detail line used to repeat the session count, which the
            // first stat in this very row already gives.
            out.append(.init(
                value: String(format: "%.0f", miles),
                unit: "MI OF WORK",
                detail: "AT PACE OR QUICKER"
            ))
            return out
        }

        // Omitted rather than placeheld when there is no band to be inside of.
        if let inBand = read.inBandCount(
            zone: zone, includeLongRuns: includeLongRuns, basis: basis
        ), !pts.isEmpty {
            out.append(.init(
                value: "\(inBand)/\(pts.count)",
                unit: "IN BAND",
                detail: "\(read.anchor.label) \(read.settings.widthLabel)"
            ))
        }
        return out
    }
}

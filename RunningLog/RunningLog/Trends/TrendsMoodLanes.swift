import SwiftUI

//  Thirty days, one date axis, one lane per signal.
//
//  Reading a day means reading straight down: the Tuesday that felt bad sits
//  directly above the Tuesday's mileage, its niggle and its session. Overlaying
//  these on one plot reads fine with two series on and falls apart with six,
//  which is why they are lanes and not lines.
//
//  Modelled on `TrendsSignalLanes` — same Canvas-in-a-GeometryReader shape, the
//  same `Layout` maths and, load-bearingly, the same gesture thresholds. The
//  differences are that lanes here are switchable (so `Layout` is built per
//  render from whatever is on) and that a left gutter carries lane names, since
//  six lanes is past the point where a reader can hold the order in their head.
//
//  PALETTE. Mood owns the warm/green ramp. Coral is the niggle alert and the
//  scrub marker, never a fill. The miles and TLS bars stack by pace zone on
//  the blue ramp (`PaceSpectrum`) — the ramp belongs to pace, and these bars ARE
//  pace signals now, so the rule is earned rather than dodged. (They were
//  graphite until 2026-08-18 precisely because a ramp-colored bar would have read as
//  a pace signal it wasn't.) A day with distance but no lap breakdown still
//  draws flat graphite: we cannot say how it was distributed, and must not
//  guess.

// MARK: - Lanes

enum TrendsMoodLane: String, CaseIterable, Identifiable {
    case mood, miles, niggles, key, load, weekly
    case sleep, restingHR, hrv

    var id: String { rawValue }

    /// The toggle chip.
    var chipLabel: String {
        switch self {
        case .mood: "Mood"
        case .miles: "Mileage"
        case .niggles: "Niggles"
        case .key: "Key sessions"
        case .load: "TLS"
        case .weekly: "Weekly volume"
        case .sleep: "Sleep"
        case .restingHR: "Resting HR"
        case .hrv: "HRV"
        }
    }

    /// The nightly lanes. They share a drawing routine, a scale and a palette,
    /// and they are the ones offered conditionally — see `TrendsMoodSection
    /// .offeredLanes`.
    var isNightly: Bool {
        switch self {
        case .sleep, .restingHR, .hrv: true
        default: false
        }
    }

    /// The gutter label. Short enough to survive 34pt at accessibility sizes.
    var laneLabel: String {
        switch self {
        case .mood: "MOOD"
        case .miles: "MILES"
        case .niggles: "NIGGLE"
        case .key: "KEY"
        case .load: "TLS"
        case .weekly: "WK VOL"
        case .sleep: "SLEEP"
        case .restingHR: "RHR"
        case .hrv: "HRV"
        }
    }

    /// The stacked lanes (miles, TLS) run taller than the flat bars did —
    /// a 46pt bar divided into three or four zone segments left the thin
    /// ones a couple of points high, unreadable at arm's length. Height is
    /// what makes a stack legible, so those two get the room. (Rio, 2026-08-18.)
    var height: CGFloat {
        switch self {
        case .mood: 30
        case .miles: 68
        case .niggles: 20
        case .key: 20
        case .load: 54
        case .weekly: 44
        // Deviation lanes spend half their height above the centre rule and
        // half below, so they need roughly double a one-sided bar to give
        // either direction the same room.
        case .sleep, .restingHR, .hrv: 46
        }
    }

    /// The chip dot. These sit on an ink pill when the lane is on, so every one
    /// of them has to read light against near-black. Miles and TLS carry pace
    /// stops from the pale half of the ramp — a hint of what the lane is
    /// coloured by, light enough to survive the ink pill.
    var chipColour: Color {
        switch self {
        case .mood: Color.drip.positive
        case .miles: PaceSpectrum.easy
        case .niggles: Color.drip.coral
        case .key: Color.drip.divider
        case .load: PaceSpectrum.steady
        case .weekly: Color.drip.textTertiary
        // Graphite, all three, on purpose. The warm/green ramp belongs to
        // mood, coral is the niggle alert, and the blue ramp belongs to pace —
        // a nightly lane borrowing any of them would read as a signal it
        // isn't. It would also imply a valence these lanes must not carry: a
        // resting HR above your usual is not "bad", it is above your usual.
        case .sleep, .restingHR, .hrv: Color.drip.textSecondary
        }
    }

    /// Mood and niggles open; load is context you ask for, not context you are
    /// handed. Key sessions ride along because they are what a bad patch is
    /// usually explained by.
    static let defaultOn: Set<TrendsMoodLane> = [.mood, .miles, .niggles, .key]

    /// Draw order is fixed regardless of toggle order, so the chart does not
    /// reshuffle itself under the reader.
    /// Words, then runs, then nights — "the athlete's words lead; the watch
    /// corroborates." The nightly lanes sit at the foot for that reason.
    static let drawOrder: [TrendsMoodLane] = [
        .mood, .miles, .niggles, .key, .load, .weekly, .sleep, .restingHR, .hrv,
    ]

    /// The band a nightly lane calls "your usual range", in SD.
    static let bandSD: Double = 0.5

    /// Half a nightly lane's vertical span, in SD. FIXED, never fitted to the
    /// window: a fortnight whose worst night was 1 sd out must not draw that
    /// night as tall as a 3-sd night draws in another fortnight.
    static let deviationSpan: Double = 2.5
}

// MARK: - The chart

struct TrendsMoodLanes: View {

    let block: TrendsMoodBlock
    let lanes: [TrendsMoodLane]
    @Binding var scrubIndex: Int?
    /// A mood label from the counted list below, or `"nolog"`. Cells that don't
    /// match dim, so "which four days were struggling" is answered by pointing
    /// rather than by scrubbing fourteen columns.
    var highlight: String? = nil

    @ScaledMetric(relativeTo: .caption2)
    private var microType: CGFloat = DripTypeFloor.eyebrowMicro

    private var gutter: CGFloat { 34 }
    private var laneGap: CGFloat { max(14, microType + 5) }
    private var axisHeight: CGFloat { max(14, microType + 5) }

    private var totalHeight: CGFloat {
        lanes.reduce(0) { $0 + $1.height }
            + laneGap * CGFloat(max(0, lanes.count - 1))
            + axisHeight
    }

    var body: some View {
        GeometryReader { geo in
            let layout = Layout(
                width: geo.size.width,
                gutter: gutter,
                count: block.buckets.count,
                heights: lanes.map(\.height),
                laneGap: laneGap,
                axisHeight: axisHeight
            )

            Canvas { ctx, _ in draw(ctx, layout: layout) }
                // A Canvas is one opaque element to VoiceOver. Republish it as
                // one child per column so the chart walks along the time axis,
                // each child reading down every lane that is on.
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Thirty days of mood, with \(lanes.count) lanes")
                .accessibilityChildren {
                    HStack(spacing: 0) {
                        ForEach(Array(block.buckets.enumerated()), id: \.element.id) { i, bucket in
                            Color.clear
                                .accessibilityElement()
                                .accessibilityLabel(
                                    Self.spoken(bucket,
                                                day: block.days.indices.contains(i) ? block.days[i] : nil)
                                )
                        }
                    }
                }
                .contentShape(Rectangle())
                // Scrubbing READS; it never navigates. 12pt of movement that is
                // more horizontal than vertical before it engages, so a vertical
                // pan falls through to the enclosing ScrollView instead of being
                // swallowed here.
                .gesture(
                    DragGesture(minimumDistance: 12)
                        .onChanged { value in
                            guard abs(value.translation.width) >= abs(value.translation.height)
                            else { return }
                            scrubIndex = layout.index(atX: value.location.x, count: block.buckets.count)
                        }
                )
                .simultaneousGesture(
                    SpatialTapGesture()
                        .onEnded { value in
                            let i = layout.index(atX: value.location.x, count: block.buckets.count)
                            scrubIndex = (scrubIndex == i) ? nil : i
                        }
                )
        }
        .frame(height: totalHeight)
        .sensoryFeedback(.selection, trigger: scrubIndex)
    }

    // MARK: Layout maths

    private struct Layout {
        let width: CGFloat
        let gutter: CGFloat
        let count: Int
        let tops: [CGFloat]
        let heights: [CGFloat]
        let slot: CGFloat
        let barWidth: CGFloat
        let axisY: CGFloat

        init(
            width: CGFloat,
            gutter: CGFloat,
            count: Int,
            heights: [CGFloat],
            laneGap: CGFloat,
            axisHeight: CGFloat
        ) {
            self.width = width
            self.gutter = gutter
            self.count = max(1, count)
            self.heights = heights

            var tops: [CGFloat] = []
            var y: CGFloat = 0
            for (i, h) in heights.enumerated() {
                tops.append(y)
                y += h
                if i < heights.count - 1 { y += laneGap }
            }
            self.tops = tops
            self.axisY = y + axisHeight / 2
            self.slot = max(1, (width - gutter) / CGFloat(max(1, count)))
            self.barWidth = max(2, self.slot * 0.62)
        }

        func x(_ i: Int) -> CGFloat { gutter + CGFloat(i) * slot }
        func centreX(_ i: Int) -> CGFloat { x(i) + slot / 2 }
        func bottom(_ lane: Int) -> CGFloat { tops[lane] + heights[lane] }

        func index(atX px: CGFloat, count: Int) -> Int? {
            guard count > 0, slot > 0 else { return nil }
            return min(count - 1, max(0, Int((px - gutter) / slot)))
        }
    }

    // MARK: Drawing

    private func draw(_ ctx: GraphicsContext, layout: Layout) {
        drawWeekRules(ctx, layout: layout)

        for (i, lane) in lanes.enumerated() {
            drawLaneLabel(ctx, layout: layout, lane: i, text: lane.laneLabel)
            switch lane {
            case .mood:
                drawMood(ctx, layout: layout, lane: i)
            case .miles:
                drawStackedBars(ctx, layout: layout, lane: i,
                                totals: block.buckets.map(\.miles),
                                zones: block.zoneMilesPerDay,
                                flatColour: Color.drip.textTertiary)
            case .niggles:
                drawNiggles(ctx, layout: layout, lane: i)
            case .key:
                drawKey(ctx, layout: layout, lane: i)
            case .load:
                drawStackedBars(ctx, layout: layout, lane: i,
                                totals: block.load,
                                zones: block.zoneLoadPerDay,
                                flatColour: Color.drip.textSecondary)
            case .weekly:
                drawWeekly(ctx, layout: layout, lane: i)
            case .sleep, .restingHR, .hrv:
                drawDeviation(ctx, layout: layout, lane: i,
                              series: block.series(for: lane),
                              colour: lane.chipColour)
            }
        }

        drawAxis(ctx, layout: layout)
        if let i = scrubIndex, block.buckets.indices.contains(i) {
            drawSpine(ctx, layout: layout, index: i)
        }
    }

    /// Faint verticals on the Mondays, so a week is legible without a lane
    /// spent drawing one.
    private func drawWeekRules(_ ctx: GraphicsContext, layout: Layout) {
        guard let lastTop = layout.tops.last, let lastHeight = layout.heights.last else { return }
        let bottom = lastTop + lastHeight
        for (i, bucket) in block.buckets.enumerated() where bucket.isWeekStart && i > 0 {
            var path = Path()
            path.move(to: CGPoint(x: layout.x(i), y: 0))
            path.addLine(to: CGPoint(x: layout.x(i), y: bottom))
            ctx.stroke(path, with: .color(Color.drip.divider.opacity(0.55)), lineWidth: 1)
        }
    }

    private func drawLaneLabel(_ ctx: GraphicsContext, layout: Layout, lane: Int, text: String) {
        ctx.draw(
            Text(text)
                .font(.dripEyebrow(microType - 1))
                .foregroundStyle(Color.drip.textTertiary),
            at: CGPoint(x: layout.gutter - 6, y: layout.tops[lane] + layout.heights[lane] / 2),
            anchor: .trailing
        )
    }

    /// Big square day cells — the whole lane.
    ///
    /// The rolling line that used to sit above them was a mean by another name,
    /// and on a fourteen-column chart it had eight meaningful points. Dropping
    /// it bought the height back for cells you can actually hit with a thumb,
    /// and the trend now lives where it belongs: this fortnight's count against
    /// the last one, in the header. (Rio, 2026-08-15.)
    private func drawMood(_ ctx: GraphicsContext, layout: Layout, lane: Int) {
        let top = layout.tops[lane]
        let height = layout.heights[lane]
        let side = min(min(layout.slot - 3, height - 2), 26)

        for (i, bucket) in block.buckets.enumerated() {
            let logged = TrendsMoodRead.isLogged(bucket.mood)
            let colour = logged
                ? TrendsMoodColor.color(bucket.mood ?? "")
                : Color.drip.paperDeep

            // Dim anything the counted list isn't pointing at.
            let matches: Bool
            if let highlight {
                matches = highlight == "nolog" ? !logged : (bucket.mood?.lowercased() == highlight)
            } else {
                matches = true
            }

            let rect = CGRect(
                x: layout.centreX(i) - side / 2,
                y: top + (height - side) / 2,
                width: side,
                height: side
            )
            ctx.fill(
                Path(roundedRect: rect, cornerRadius: 3),
                with: .color(colour.opacity(matches ? 1 : 0.18))
            )

            // The selected day gets a ring rather than a colour change, so the
            // mood it is reporting stays readable while it is selected.
            if scrubIndex == i {
                ctx.stroke(
                    Path(roundedRect: rect.insetBy(dx: -2.5, dy: -2.5), cornerRadius: 5),
                    with: .color(Color.drip.textPrimary),
                    lineWidth: 1.6
                )
            }
        }
    }

    /// The ten-zone taxonomy in stacking order (slow → fast), each with its
    /// `PaceSpectrum` stop. `recovery` folds to the easy stop and the backend
    /// classifier folds LT into `hmp` (the `lt` row is belt-and-braces against
    /// an older payload). Owned here rather than shared with
    /// `TrendsReadView.zoneColor`, which maps *work* zones only and defaults
    /// everything else to steady — wrong for a lane that is mostly easy miles.
    private static let zoneStack: [(token: String, colour: Color)] = [
        ("recovery", PaceSpectrum.easy),
        ("easy", PaceSpectrum.easy),
        ("moderate", PaceSpectrum.moderate),
        ("steady", PaceSpectrum.steady),
        ("mp", PaceSpectrum.mp),
        ("hmp", PaceSpectrum.hmp),
        ("lt", PaceSpectrum.lt),
        ("10k", PaceSpectrum.tenK),
        ("5k", PaceSpectrum.fiveK),
        ("3k", PaceSpectrum.threeK),
        ("mile", PaceSpectrum.mile),
    ]

    /// The stacked variant of the old flat `drawBars`. One scale across the
    /// whole lane, never per-column relative fill — that would make the same
    /// 8-mile day look different in a light month than in a heavy one. The
    /// bar's HEIGHT still comes from `totals` (the same numbers the flat bars
    /// drew), so stacking changes what a bar is made of, never how tall it is;
    /// `zones` only divides it, slow at the base, the sharp end on top.
    ///
    /// Three states, three looks (the `TrendsDay.hasZoneBreakdown` contract):
    ///   • total == 0                → rest day, nothing drawn.
    ///   • total > 0, zones[i] nil   → ran without laps. Flat graphite at
    ///     reduced opacity with a dashed cap — visibly "we don't know", never
    ///     a guessed distribution.
    ///   • total > 0, zones present  → the real thing, on the pace ramp.
    private func drawStackedBars(
        _ ctx: GraphicsContext,
        layout: Layout,
        lane: Int,
        totals: [Double],
        zones: [[String: Double]?],
        flatColour: Color
    ) {
        let base = layout.bottom(lane)
        let height = layout.heights[lane]

        var rule = Path()
        rule.move(to: CGPoint(x: layout.gutter, y: base))
        rule.addLine(to: CGPoint(x: layout.width, y: base))
        ctx.stroke(rule, with: .color(Color.drip.divider.opacity(0.8)), lineWidth: 1)

        let peak = totals.max() ?? 0
        guard peak > 0 else { return }
        for (i, total) in totals.enumerated() where total > 0 {
            guard i < layout.count else { break }
            let barHeight = max(1.5, CGFloat(total / peak) * height)
            let rect = CGRect(
                x: layout.centreX(i) - layout.barWidth / 2,
                y: base - barHeight,
                width: layout.barWidth,
                height: barHeight
            )
            let outline = Path(roundedRect: rect, cornerRadius: 1.5)

            // Ran, but the run arrived with no laps — the fallback bar.
            let dayZones = i < zones.count ? zones[i] : nil
            let zoneSum = dayZones?.values.reduce(0, +) ?? 0
            guard let dayZones, zoneSum > 0 else {
                ctx.fill(outline, with: .color(flatColour.opacity(0.55)))
                var cap = Path()
                cap.move(to: CGPoint(x: rect.minX, y: rect.minY - 2.5))
                cap.addLine(to: CGPoint(x: rect.maxX, y: rect.minY - 2.5))
                ctx.stroke(cap, with: .color(flatColour),
                           style: StrokeStyle(lineWidth: 1.2, dash: [2, 2]))
                continue
            }

            // Segment heights are shares of the day's own zone sum, so the
            // stack always fills the bar even when lap miles don't add up to
            // the day's deduped total exactly. A token the table doesn't know
            // is left as a graphite remainder on top rather than silently
            // vanishing — a new backend zone must show as *something*.
            var inner = ctx
            inner.clip(to: outline)
            var y = rect.maxY
            for entry in Self.zoneStack {
                guard let value = dayZones[entry.token], value > 0 else { continue }
                let segment = CGFloat(value / zoneSum) * barHeight
                y -= segment
                inner.fill(
                    Path(CGRect(x: rect.minX, y: y,
                                width: rect.width, height: segment + 0.5)),
                    with: .color(entry.colour)
                )
            }
            if y - rect.minY > 0.5 {
                inner.fill(
                    Path(CGRect(x: rect.minX, y: rect.minY,
                                width: rect.width, height: y - rect.minY)),
                    with: .color(flatColour.opacity(0.8))
                )
            }
        }
    }

    /// A dot is a mention, not an injury. Size grows with how many areas were
    /// named that day; severity drives the alpha, reusing the tab's ranking so
    /// a "sharp" here looks like a "sharp" everywhere else.
    private func drawNiggles(_ ctx: GraphicsContext, layout: Layout, lane: Int) {
        let centre = layout.tops[lane] + layout.heights[lane] / 2
        for (i, bucket) in block.buckets.enumerated() {
            let point = CGPoint(x: layout.centreX(i), y: centre)
            guard bucket.hasNiggle else {
                let dot = CGRect(x: point.x - 1.1, y: point.y - 1.1, width: 2.2, height: 2.2)
                ctx.fill(Path(ellipseIn: dot), with: .color(Color.drip.divider))
                continue
            }
            let radius = min(4.6, 3 + CGFloat(bucket.niggles.count) * 0.9)
            let rect = CGRect(x: point.x - radius, y: point.y - radius,
                              width: radius * 2, height: radius * 2)
            ctx.fill(
                Path(ellipseIn: rect),
                with: .color(Color.drip.coral.opacity(TrendsSeverity.opacity(bucket.loudestSeverity)))
            )
        }
    }

    /// Ink diamonds, not coral: coral is the alert palette and a key session is
    /// not an alert. Long runs draw a shade lighter and a touch larger.
    private func drawKey(_ ctx: GraphicsContext, layout: Layout, lane: Int) {
        let centre = layout.tops[lane] + layout.heights[lane] / 2

        var rule = Path()
        rule.move(to: CGPoint(x: layout.gutter, y: centre))
        rule.addLine(to: CGPoint(x: layout.width, y: centre))
        ctx.stroke(rule, with: .color(Color.drip.divider.opacity(0.8)), lineWidth: 1)

        for (i, bucket) in block.buckets.enumerated() {
            let channel = bucket.channel
            guard channel.isKey || channel.isLong else { continue }
            let size: CGFloat = channel.isLong ? 5.0 : 4.2
            let x = layout.centreX(i)
            var diamond = Path()
            diamond.move(to: CGPoint(x: x, y: centre - size))
            diamond.addLine(to: CGPoint(x: x + size, y: centre))
            diamond.addLine(to: CGPoint(x: x, y: centre + size))
            diamond.addLine(to: CGPoint(x: x - size, y: centre))
            diamond.closeSubpath()
            ctx.fill(diamond, with: .color(channel.isKey ? Color.drip.textPrimary : Color.drip.textSecondary))
        }
    }

    /// Weekly totals as blocks spanning the days of their week, so a heavy week
    /// sits visibly above the days that made it heavy.
    ///
    /// A clipped week is not a light week. The two at the window edges draw
    /// hollow with a dashed cap, or the eye reads the edge of the window as a
    /// down week.
    private func drawWeekly(_ ctx: GraphicsContext, layout: Layout, lane: Int) {
        let base = layout.bottom(lane)
        let height = layout.heights[lane]
        let runs = block.weekRuns

        var rule = Path()
        rule.move(to: CGPoint(x: layout.gutter, y: base))
        rule.addLine(to: CGPoint(x: layout.width, y: base))
        ctx.stroke(rule, with: .color(Color.drip.divider.opacity(0.8)), lineWidth: 1)

        let peak = runs.map(\.miles).max() ?? 0
        guard peak > 0 else { return }

        for run in runs {
            let left = layout.x(run.first) + 1
            let right = layout.x(run.last) + layout.slot - 1
            guard right > left else { continue }
            let barHeight = max(2, CGFloat(run.miles / peak) * height)
            let rect = CGRect(x: left, y: base - barHeight, width: right - left, height: barHeight)
            ctx.fill(
                Path(rect),
                with: .color(Color.drip.textTertiary.opacity(run.partial ? 0.10 : 0.26))
            )
            var cap = Path()
            cap.move(to: CGPoint(x: left, y: base - barHeight))
            cap.addLine(to: CGPoint(x: right, y: base - barHeight))
            ctx.stroke(
                cap,
                with: .color(Color.drip.textTertiary),
                style: StrokeStyle(lineWidth: 1.4, dash: run.partial ? [3, 3] : [])
            )
            if right - left > 26 {
                ctx.draw(
                    Text("\(Int(run.miles.rounded()))" + (run.partial ? "*" : ""))
                        .font(.dripEyebrow(microType - 1))
                        .foregroundStyle(run.partial ? Color.drip.textTertiary : Color.drip.textSecondary),
                    at: CGPoint(x: (left + right) / 2, y: base - barHeight - 6),
                    anchor: .bottom
                )
            }
        }
    }

    /// Every seventh column. Labelling all thirty is unreadable at this width,
    /// and the header already carries the exact span.
    private func drawAxis(_ ctx: GraphicsContext, layout: Layout) {
        // Every seventh column is two labels on a fortnight. Step by three so
        // the axis stays readable without the labels touching.
        let step = block.buckets.count <= 16 ? 3 : 7
        for (i, bucket) in block.buckets.enumerated() where i % step == 0 {
            ctx.draw(
                Text(bucket.label)
                    .font(.dripEyebrow(microType - 1))
                    .foregroundStyle(Color.drip.textTertiary),
                at: CGPoint(x: layout.centreX(i), y: layout.axisY),
                anchor: .center
            )
        }
    }

    private func drawSpine(_ ctx: GraphicsContext, layout: Layout, index: Int) {
        guard let lastTop = layout.tops.last, let lastHeight = layout.heights.last else { return }
        var path = Path()
        let x = layout.centreX(index)
        path.move(to: CGPoint(x: x, y: 0))
        path.addLine(to: CGPoint(x: x, y: lastTop + lastHeight))
        ctx.stroke(path, with: .color(Color.drip.coral.opacity(0.45)), lineWidth: 1)
    }

    // MARK: Spoken

    /// The nightly lanes — sleep, resting HR, HRV.
    ///
    /// A centre rule is the athlete's own baseline and the pale well around it
    /// is ±`TrendsMoodLane.bandSD`, the same "inside your usual range" threshold `overnight`
    /// thresholds direction at. A mark runs from the rule to the night's
    /// deviation, so DIRECTION is which side of the rule it sits on and
    /// MAGNITUDE is how far it reaches. Nights inside the band are drawn quiet;
    /// nights outside it darken.
    ///
    /// Colour never says good or bad, and the two directions are drawn
    /// identically. A resting HR above your usual is not "bad" — it is above
    /// your usual, and one night cannot tell you which of a dozen reasons put
    /// it there. Reading meaning into a column is the athlete's call; this lane
    /// only supplies the column and the band it usually sits in.
    ///
    /// Nights with no reading draw NOTHING — not a zero, not a bridged line
    /// between the nights either side. A missing night and an average night are
    /// different facts, the same contract `TrendsDay` holds everywhere else.
    private func drawDeviation(
        _ ctx: GraphicsContext,
        layout: Layout,
        lane: Int,
        series: TrendsBiometricSeries?,
        colour: Color
    ) {
        let top = layout.tops[lane]
        let height = layout.heights[lane]
        let mid = top + height / 2
        let half = height / 2

        // The usual-range well, then the baseline rule over it.
        let bandHalf = half * CGFloat(TrendsMoodLane.bandSD / TrendsMoodLane.deviationSpan)
        ctx.fill(
            Path(CGRect(x: layout.gutter,
                        y: mid - bandHalf,
                        width: max(0, layout.width - layout.gutter),
                        height: bandHalf * 2)),
            with: .color(Color.drip.paperDeep)
        )
        var rule = Path()
        rule.move(to: CGPoint(x: layout.gutter, y: mid))
        rule.addLine(to: CGPoint(x: layout.width, y: mid))
        ctx.stroke(rule, with: .color(Color.drip.divider.opacity(0.8)), lineWidth: 1)

        // No baseline behind this fortnight, or nothing measured inside it.
        // Say so in place — an empty lane that looks like a flat lane would be
        // read as "nothing happened", which is a claim we have not earned.
        guard let series else {
            ctx.draw(
                Text("no readings we can place against your usual")
                    .font(.dripEyebrow(microType - 1))
                    .foregroundStyle(Color.drip.textTertiary),
                at: CGPoint(x: layout.gutter + max(0, layout.width - layout.gutter) / 2, y: mid),
                anchor: .center
            )
            return
        }

        for (i, deviation) in series.deviations.enumerated() {
            guard i < layout.count, let deviation else { continue }

            let clipped = abs(deviation) > TrendsMoodLane.deviationSpan
            let reach = min(abs(deviation), TrendsMoodLane.deviationSpan) / TrendsMoodLane.deviationSpan
            let length = max(1.5, CGFloat(reach) * half)
            let above = deviation > 0
            let rect = CGRect(
                x: layout.centreX(i) - layout.barWidth / 2,
                y: above ? mid - length : mid,
                width: layout.barWidth,
                height: length
            )
            let inBand = abs(deviation) < TrendsMoodLane.bandSD
            ctx.fill(
                Path(roundedRect: rect, cornerRadius: 1.5),
                with: .color(colour.opacity(inBand ? 0.28 : 0.95))
            )

            // Past the fixed span. The dashed cap is the same idiom the flat
            // fallback bar uses: the mark is bounded, the night was not.
            if clipped {
                var cap = Path()
                let y = above ? rect.minY - 2.5 : rect.maxY + 2.5
                cap.move(to: CGPoint(x: rect.minX, y: y))
                cap.addLine(to: CGPoint(x: rect.maxX, y: y))
                ctx.stroke(cap, with: .color(colour),
                           style: StrokeStyle(lineWidth: 1.2, dash: [2, 2]))
            }
        }
    }

    /// `day` carries the nightly readings, which live on `TrendsDay` rather
    /// than on the bucket. Optional so the callers that have no day handy keep
    /// reading exactly as they did.
    static func spoken(_ bucket: TrendsBucket, day: TrendsDay? = nil) -> String {
        var parts: [String] = [bucket.label]
        parts.append(bucket.mood.map { "felt \($0)" } ?? "no log")
        parts.append(bucket.miles > 0 ? String(format: "%.1f miles", bucket.miles) : "rest day")
        if bucket.keyCount > 0 { parts.append("key session") }
        if bucket.hasNiggle {
            parts.append("niggle: " + bucket.niggles.map(\.area).joined(separator: ", "))
        }
        if let day {
            if let sleep = day.sleepTotalMin {
                parts.append("slept \(sleep / 60)h \(sleep % 60)m")
            }
            if let rhr = day.restingHr {
                parts.append(String(format: "resting HR %.0f", rhr))
            }
            if let hrv = day.hrvRmssd {
                parts.append(String(format: "HRV %.0f", hrv))
            }
        }
        return parts.joined(separator: ", ")
    }
}

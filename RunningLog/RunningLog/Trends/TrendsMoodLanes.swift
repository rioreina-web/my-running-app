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
//  scrub marker, never a fill. Load bars are deliberately achromatic graphite:
//  blue belongs to pace, and a blue bar here would read as a pace signal.

// MARK: - Lanes

enum TrendsMoodLane: String, CaseIterable, Identifiable {
    case mood, miles, niggles, key, load, weekly

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
        }
    }

    var height: CGFloat {
        switch self {
        case .mood: 30
        case .miles: 46
        case .niggles: 20
        case .key: 20
        case .load: 42
        case .weekly: 44
        }
    }

    /// The chip dot. These sit on an ink pill when the lane is on, so every one
    /// of them has to read light against near-black.
    var chipColour: Color {
        switch self {
        case .mood: Color.drip.positive
        case .miles: Color.drip.textTertiary
        case .niggles: Color.drip.coral
        case .key: Color.drip.divider
        case .load: Color.drip.textTertiary
        case .weekly: Color.drip.textTertiary
        }
    }

    /// Mood and niggles open; load is context you ask for, not context you are
    /// handed. Key sessions ride along because they are what a bad patch is
    /// usually explained by.
    static let defaultOn: Set<TrendsMoodLane> = [.mood, .miles, .niggles, .key]

    /// Draw order is fixed regardless of toggle order, so the chart does not
    /// reshuffle itself under the reader.
    static let drawOrder: [TrendsMoodLane] = [.mood, .miles, .niggles, .key, .load, .weekly]
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
                        ForEach(block.buckets) { bucket in
                            Color.clear
                                .accessibilityElement()
                                .accessibilityLabel(Self.spoken(bucket))
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
                drawBars(ctx, layout: layout, lane: i,
                         values: block.buckets.map(\.miles),
                         colour: Color.drip.textTertiary)
            case .niggles:
                drawNiggles(ctx, layout: layout, lane: i)
            case .key:
                drawKey(ctx, layout: layout, lane: i)
            case .load:
                drawBars(ctx, layout: layout, lane: i,
                         values: block.load,
                         colour: Color.drip.textSecondary)
            case .weekly:
                drawWeekly(ctx, layout: layout, lane: i)
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

    /// One scale across the whole lane, never per-column relative fill — that
    /// would make the same 8-mile day look different in a light month than in
    /// a heavy one.
    private func drawBars(
        _ ctx: GraphicsContext,
        layout: Layout,
        lane: Int,
        values: [Double],
        colour: Color
    ) {
        let base = layout.bottom(lane)
        let height = layout.heights[lane]

        var rule = Path()
        rule.move(to: CGPoint(x: layout.gutter, y: base))
        rule.addLine(to: CGPoint(x: layout.width, y: base))
        ctx.stroke(rule, with: .color(Color.drip.divider.opacity(0.8)), lineWidth: 1)

        let peak = values.max() ?? 0
        guard peak > 0 else { return }
        for (i, value) in values.enumerated() where value > 0 {
            guard i < layout.count else { break }
            let barHeight = max(1.5, CGFloat(value / peak) * height)
            let rect = CGRect(
                x: layout.centreX(i) - layout.barWidth / 2,
                y: base - barHeight,
                width: layout.barWidth,
                height: barHeight
            )
            ctx.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(colour))
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

    static func spoken(_ bucket: TrendsBucket) -> String {
        var parts: [String] = [bucket.label]
        parts.append(bucket.mood.map { "felt \($0)" } ?? "no log")
        parts.append(bucket.miles > 0 ? String(format: "%.1f miles", bucket.miles) : "rest day")
        if bucket.keyCount > 0 { parts.append("key session") }
        if bucket.hasNiggle {
            parts.append("niggle: " + bucket.niggles.map(\.area).joined(separator: ", "))
        }
        return parts.joined(separator: ", ")
    }
}

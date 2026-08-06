//
//  TrendsSignalLanes.swift
//  RunningLog · Trends
//
//  The five-signal chart: mileage, key work, recovery, mood and niggles on one
//  shared time axis. Drag across it to read a single day down all five lanes.
//
//  **Why lanes and not the calendar.** `trends-v2-spec-2026-07-30` chose a
//  calendar grid, and its argument was good — a calendar shows *which day of
//  the week*, and weekday rhythm is where a self-coached runner's habits live.
//  But a calendar cell needs ~45pt to carry four channels, and at the 1-year
//  window the cells fall to ~5pt; the spec itself concedes the Season scale has
//  to announce that bar height and mood no longer fit. That is the calendar
//  saying it works at two of the five ranges.
//
//  Lanes degrade instead of collapsing: the same five rows read identically at
//  30 daily columns and at 53 weekly ones, and `degradationNote` says what the
//  wider windows dropped. One structure that survives every range is worth more
//  than the best structure for one.
//
//  Two encodings are deliberate and load-bearing:
//   • **Mood is colour only** (2026-08-06). Every logged day is one swatch of
//     the same height, so the lane reads as a ribbon rather than as a bar
//     chart of feelings. It was tried the other way — a rank-derived height as
//     a redundant channel for readers who cannot separate the adjacent warm
//     hues (tired amber, struggling terracotta, injured rose) — and the ramp
//     cost more legibility for every reader than it bought for those it
//     helped. The redundancy moved off the drawing rather than disappearing:
//     the scrub readout names the mood in words, each column's VoiceOver
//     label speaks it down all five lanes, and the audio graph still places
//     mood on the `TrendsRecoveryFactors.moodPoints` ordering via
//     `TrendsMoodColor.rank`. Colour carries the glance; words carry the
//     certainty.
//   • **Bar height is miles against the window maximum, one scale for the whole
//     lane.** Never per-column relative fill — that makes the same 8-mile day
//     look different in a light month than in a heavy one.
//
//  **Accessibility.** The chart is a Canvas, which is one opaque element to
//  VoiceOver by default. `accessibilityChildren` republishes it as one element
//  per column, read down all five lanes, so the swipe order follows the time
//  axis; `AXChartDescriptorRepresentable` publishes the same five series as an
//  audio graph. Micro type on this page is `@ScaledMetric`-driven with a 9pt
//  floor — the drip fonts are fixed-size by construction, so Dynamic Type has
//  to be opted into per surface.
//

import SwiftUI
import Accessibility

struct TrendsSignalLanes: View {
    let set: TrendsBucketSet
    /// Called when the athlete taps a column, for the day drill-down.
    var onSelect: ((TrendsBucket) -> Void)?

    @State private var scrubIndex: Int?

    /// Every label the Canvas draws is sized from these. They start at the
    /// floor rather than the old 7.5–8pt literals and grow with the reader's
    /// Dynamic Type setting — see `DripTypeFloor`.
    @ScaledMetric(relativeTo: .caption2)
    private var microType: CGFloat = DripTypeFloor.eyebrowMicro
    @ScaledMetric(relativeTo: .caption2)
    private var smallType: CGFloat = DripTypeFloor.eyebrowSmall

    // Lane geometry. Heights are the design's, in points. The gaps around
    // text grow with `microType` so a label never lands on the lane above it
    // at the accessibility sizes.
    private let laneHeights: [CGFloat] = [82, 26, 54, 16, 13]
    private var headerHeight: CGFloat { max(12, microType + 3) }
    private var laneGap: CGFloat { max(15, microType + 6) }
    /// Extra room under the mileage lane for its legend.
    private var legendGap: CGFloat { max(12, microType + 3) }
    /// Extra room under the mood lane for its ramp legend.
    private var moodLegendGap: CGFloat { max(12, microType + 3) }
    private var axisHeight: CGFloat { max(14, microType + 5) }

    private var totalHeight: CGFloat {
        laneHeights.reduce(0) { $0 + $1 }
            + headerHeight * CGFloat(laneHeights.count)
            + laneGap * CGFloat(laneHeights.count - 1)
            + legendGap + moodLegendGap + axisHeight
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            chart
            if let bucket = selectedBucket { selectionRow(bucket) }
            Text(set.degradationNote)
                .font(.dripEyebrow(microType))
                .tracking(0.5)
                .textCase(.uppercase)
                .foregroundStyle(Color.drip.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        // The scrub snaps column to column, and until now it did so silently —
        // the finger crossed a boundary and only the readout said so. A
        // selection tick per column makes the snapping felt as well as seen.
        .sensoryFeedback(.selection, trigger: scrubIndex)
    }

    private var chart: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let layout = Layout(
                width: width,
                count: max(1, set.buckets.count),
                laneHeights: laneHeights,
                headerHeight: headerHeight,
                laneGap: laneGap,
                legendGap: legendGap,
                moodLegendGap: moodLegendGap
            )

            ZStack(alignment: .topLeading) {
                Canvas { ctx, _ in draw(ctx, layout: layout) }
                    // A Canvas is one opaque element to VoiceOver. Republish
                    // it as one child per column so the chart is walkable
                    // left-to-right along the time axis, each child reading
                    // down all five lanes for that bucket.
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Five signal lanes: mileage, key work, recovery, mood and niggles")
                    .accessibilityChildren {
                        HStack(spacing: 0) {
                            ForEach(set.buckets) { bucket in
                                Color.clear
                                    .accessibilityElement()
                                    .accessibilityLabel(axLabel(bucket))
                            }
                        }
                    }
                    .accessibilityChartDescriptor(self)

                if let i = scrubIndex, set.buckets.indices.contains(i) {
                    readout(for: set.buckets[i], layout: layout, width: width)
                }
            }
            .contentShape(Rectangle())
            // Scrubbing READS. It never navigates.
            //
            // This gesture used to be `DragGesture(minimumDistance: 0)` whose
            // `onEnded` called `onSelect`, which meant every touch anywhere on
            // the chart opened a workout — including the start of a scroll, so
            // the page could barely be scrolled without a sheet appearing.
            //
            // Two changes: the drag no longer navigates at all, and it needs
            // 12pt of movement that is more horizontal than vertical before it
            // engages. That lets a vertical pan fall through to the enclosing
            // ScrollView instead of being swallowed here. Opening a day is now
            // a deliberate, separate tap on the row below the chart.
            .gesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { value in
                        guard abs(value.translation.width) >= abs(value.translation.height)
                        else { return }
                        scrubIndex = layout.index(atX: value.location.x, count: set.buckets.count)
                    }
            )
            // A tap selects the column under the finger; tapping the same
            // column again clears it. Still no navigation.
            .simultaneousGesture(
                SpatialTapGesture()
                    .onEnded { value in
                        let i = layout.index(atX: value.location.x, count: set.buckets.count)
                        scrubIndex = (scrubIndex == i) ? nil : i
                    }
            )
        }
        .frame(height: totalHeight)
    }

    // MARK: - Selection row

    private var selectedBucket: TrendsBucket? {
        guard let i = scrubIndex, set.buckets.indices.contains(i) else { return nil }
        return set.buckets[i]
    }

    /// The only route out of the chart. A day-grain column with a run opens
    /// that day's logs; a weekly column opens the week, which lists its days
    /// and pages into any of them. A day with no run is the one case left with
    /// nothing to open — it renders the summary without the control rather
    /// than offering a dead tap. A rest *week* is still worth opening: the
    /// sheet says so.
    @ViewBuilder
    private func selectionRow(_ bucket: TrendsBucket) -> some View {
        let openable = onSelect != nil && (set.grain == .week || bucket.miles > 0)

        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text((set.grain == .day ? bucket.label : "Week of \(bucket.label)").uppercased())
                    .font(.dripEyebrow(smallType))
                    .tracking(1.1)
                    .foregroundStyle(Color.drip.textSecondary)
                Text(summaryLine(bucket))
                    .font(.dripBody(12.5))
                    .foregroundStyle(Color.drip.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 6)
            if openable {
                Text("Open ›")
                    .font(.dripLabel(13))
                    .foregroundStyle(Color.drip.coral)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10).fill(Color.drip.cardBackgroundElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10).stroke(Color.drip.divider, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture { if openable { onSelect?(bucket) } }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(openable ? .isButton : [])
        .accessibilityHint(
            openable
                ? (set.grain == .day ? "Opens this day's workouts" : "Opens this week's days")
                : ""
        )
    }

    private func summaryLine(_ b: TrendsBucket) -> String {
        var parts: [String] = [runSummary(b)]
        if let mood = b.mood { parts.append(mood) }
        parts.append("recovery \(b.recovery)")
        if let area = b.niggles.first?.area { parts.append(area) }
        return parts.joined(separator: " · ")
    }

    // MARK: - Layout maths

    private struct Layout {
        let width: CGFloat
        let count: Int
        /// Lane plot-area tops, indexed 0…4.
        let tops: [CGFloat]
        let heights: [CGFloat]
        let slot: CGFloat
        let barWidth: CGFloat
        let axisY: CGFloat

        init(
            width: CGFloat,
            count: Int,
            laneHeights: [CGFloat],
            headerHeight: CGFloat,
            laneGap: CGFloat,
            legendGap: CGFloat,
            moodLegendGap: CGFloat
        ) {
            self.width = width
            self.count = count
            self.heights = laneHeights
            var tops: [CGFloat] = []
            var y: CGFloat = 0
            for (i, h) in laneHeights.enumerated() {
                y += headerHeight
                tops.append(y)
                y += h
                if i < laneHeights.count - 1 {
                    // Lane 0 (mileage) and lane 3 (mood) each carry a legend
                    // below them; the others just take the gap.
                    y += laneGap + (i == 0 ? legendGap : 0) + (i == 3 ? moodLegendGap : 0)
                }
            }
            self.tops = tops
            self.axisY = y + 10
            self.slot = width / CGFloat(max(1, count))
            self.barWidth = max(1.4, slot * 0.62)
        }

        func x(_ i: Int) -> CGFloat { CGFloat(i) * slot }
        func centreX(_ i: Int) -> CGFloat { CGFloat(i) * slot + slot / 2 }
        func bottom(_ lane: Int) -> CGFloat { tops[lane] + heights[lane] }

        func index(atX px: CGFloat, count: Int) -> Int? {
            guard count > 0, slot > 0 else { return nil }
            return min(count - 1, max(0, Int(px / slot)))
        }
    }

    // MARK: - Drawing

    private func draw(_ ctx: GraphicsContext, layout: Layout) {
        let buckets = set.buckets
        guard !buckets.isEmpty else { return }

        let rule = Color.drip.divider
        let ink = Color.drip.textPrimary

        // Gridlines through every lane — Mondays at day grain, month starts at
        // week grain.
        for (i, b) in buckets.enumerated() {
            let show: Bool
            if set.grain == .day {
                show = b.isWeekStart
            } else {
                // A week marks a month start when its month differs from the
                // previous week's. The old day-01–09 string test double-marked
                // months with two early Mondays and skipped any month whose
                // first Monday fell on the 10th or later.
                show = i > 0 && b.startISO.prefix(7) != buckets[i - 1].startISO.prefix(7)
            }
            guard show else { continue }
            var p = Path()
            p.move(to: CGPoint(x: layout.x(i), y: layout.tops[0]))
            p.addLine(to: CGPoint(x: layout.x(i), y: layout.bottom(4)))
            ctx.stroke(p, with: .color(rule), lineWidth: 1)
        }

        drawMileage(ctx, layout: layout)
        drawKeyWork(ctx, layout: layout)
        drawRecovery(ctx, layout: layout)
        drawMood(ctx, layout: layout)
        drawNiggles(ctx, layout: layout)
        drawAxis(ctx, layout: layout)

        // Scrub crosshair, spanning every lane — this is what makes the shared
        // axis worth having: one gesture reads all five signals for one day.
        if let i = scrubIndex, buckets.indices.contains(i) {
            var line = Path()
            line.move(to: CGPoint(x: layout.centreX(i), y: layout.tops[0]))
            line.addLine(to: CGPoint(x: layout.centreX(i), y: layout.bottom(4)))
            ctx.stroke(line, with: .color(ink.opacity(0.45)), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
        }
    }

    private func laneHeader(_ ctx: GraphicsContext, layout: Layout, lane: Int, left: String, right: String) {
        let y = layout.tops[lane] - 4
        ctx.draw(
            Text(left.uppercased())
                .font(.dripEyebrow(microType))
                .tracking(1.1)
                .foregroundStyle(Color.drip.textSecondary),
            at: CGPoint(x: 0, y: y),
            anchor: .bottomLeading
        )
        ctx.draw(
            Text(right.uppercased())
                .font(.dripEyebrow(microType).weight(.semibold))
                .foregroundStyle(Color.drip.textSecondary),
            at: CGPoint(x: layout.width, y: y),
            anchor: .bottomTrailing
        )
    }

    // 1 · Mileage — bars, fill by session type.
    private func drawMileage(_ ctx: GraphicsContext, layout: Layout) {
        let lane = 0
        let top = layout.tops[lane], h = layout.heights[lane]
        let maxMiles = max(6, (set.buckets.map(\.miles).max() ?? 6) * 1.06)

        laneHeader(ctx, layout: layout, lane: lane,
                   left: "Mileage",
                   right: "\(Int(set.totalMiles.rounded())) mi")

        var baseline = Path()
        baseline.move(to: CGPoint(x: 0, y: top + h))
        baseline.addLine(to: CGPoint(x: layout.width, y: top + h))
        ctx.stroke(baseline, with: .color(Color.drip.divider), lineWidth: 1)

        for (i, b) in set.buckets.enumerated() where b.miles > 0 {
            let barH = max(1.5, CGFloat(b.miles / maxMiles) * h)
            let x = layout.x(i) + (layout.slot - layout.barWidth) / 2
            let rect = CGRect(x: x, y: top + h - barH, width: layout.barWidth, height: barH)

            if set.grain == .week {
                // A week almost always contains a key session, so colouring by
                // type would wash the whole lane. Weeks render neutral and the
                // KEY WORK lane carries the count.
                ctx.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(Self.longInk))
            } else if b.channel == .keyLong {
                // Both. The bar is coral because quality happened, with a grey
                // foot so the long run isn't erased — this is the case the wire
                // format collapses and the whole reason `keyLong` exists.
                ctx.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(Color.drip.coral))
                let footH = min(barH, max(3, barH * 0.34))
                let foot = CGRect(x: rect.minX, y: rect.maxY - footH, width: rect.width, height: footH)
                ctx.fill(Path(foot), with: .color(Self.longInk))
            } else {
                ctx.fill(Path(roundedRect: rect, cornerRadius: layout.barWidth > 3 ? 1 : 0),
                         with: .color(fill(for: b.channel)))
            }
        }

        // Legend. The grey foot rides on the entry itself rather than a
        // positional index — the old `idx == 2` check silently broke if the
        // entries were ever reordered.
        let entries: [(label: String, colour: Color, foot: Bool)] = set.grain == .week
            ? [("Weekly total", Self.longInk, false)]
            : [("Key", Color.drip.coral, false), ("Long", Self.longInk, false),
               ("Both", Color.drip.coral, true), ("Easy", Self.easyInk, false)]
        var lx: CGFloat = 0
        let ly = top + h + 7
        for entry in entries {
            let swatch = CGRect(x: lx, y: ly, width: 6, height: 6)
            ctx.fill(Path(roundedRect: swatch, cornerRadius: 1), with: .color(entry.colour))
            // "Both" gets the grey foot in its swatch, same as the bar.
            if entry.foot {
                ctx.fill(Path(CGRect(x: lx, y: ly + 4, width: 6, height: 2)), with: .color(Self.longInk))
            }
            ctx.draw(
                Text(entry.label.uppercased())
                    .font(.dripEyebrow(microType))
                    .tracking(0.7)
                    .foregroundStyle(Color.drip.textTertiary),
                at: CGPoint(x: lx + 9, y: ly + 3),
                anchor: .leading
            )
            // Advance by the label's drawn width, which now tracks the type
            // size rather than assuming the retired 7.5pt face.
            lx += 9 + CGFloat(entry.label.count) * microType * 0.62 + 11
        }
    }

    // 2 · Key work — one mark per key session.
    private func drawKeyWork(_ ctx: GraphicsContext, layout: Layout) {
        let lane = 1
        let top = layout.tops[lane], h = layout.heights[lane]
        let count = set.keySessionCount

        laneHeader(ctx, layout: layout, lane: lane,
                   left: "Key work",
                   right: count == 1 ? "1 session" : "\(count) sessions")

        var baseline = Path()
        baseline.move(to: CGPoint(x: 0, y: top + h))
        baseline.addLine(to: CGPoint(x: layout.width, y: top + h))
        ctx.stroke(baseline, with: .color(Color.drip.divider), lineWidth: 1)

        let maxKey = max(1, set.buckets.map(\.keyCount).max() ?? 1)

        for (i, b) in set.buckets.enumerated() {
            let x = layout.x(i) + (layout.slot - layout.barWidth) / 2

            // A long run draws its own low grey mark, so a `keyLong` day shows
            // both facts: the grey foot and the coral mark above it.
            if b.longCount > 0 {
                let foot = CGRect(x: x, y: top + h - 4, width: layout.barWidth, height: 4)
                ctx.fill(Path(roundedRect: foot, cornerRadius: 1),
                         with: .color(Self.longInk.opacity(0.55)))
            }
            guard b.keyCount > 0 else { continue }

            let fraction = set.grain == .day ? 1.0 : Double(b.keyCount) / Double(maxKey)
            let markH = max(6, CGFloat(fraction) * h)
            let rect = CGRect(x: x, y: top + h - markH, width: layout.barWidth, height: markH)
            ctx.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(Color.drip.coral))
        }
    }

    // 3 · Recovery — line over banded ground.
    private func drawRecovery(_ ctx: GraphicsContext, layout: Layout) {
        let lane = 2
        let top = layout.tops[lane], h = layout.heights[lane]
        let buckets = set.buckets
        guard let first = buckets.first, let last = buckets.last else { return }

        let delta = last.recovery - first.recovery
        laneHeader(ctx, layout: layout, lane: lane,
                   left: "Recovery",
                   right: "\(last.recovery) · \(delta >= 0 ? "+" : "−")\(abs(delta)) over window")

        // The lane's floor matches the score's actual clamp (8…96) — a scale
        // starting above the clamp plotted floor scores below the lane.
        func y(_ v: Int) -> CGFloat {
            top + h - CGFloat((Double(v) - 8) / (96 - 8)) * h
        }

        // Band grounds, at low alpha so the line stays the figure.
        let bands: [(Int, Int, Color)] = [
            (75, 96, Color.drip.positive),
            (60, 75, Color.drip.neutral),
            (45, 60, Color.drip.tired),
            (8, 45, Color.drip.struggling),
        ]
        for (lo, hi, colour) in bands {
            let rect = CGRect(x: 0, y: y(hi), width: layout.width, height: y(lo) - y(hi))
            ctx.fill(Path(rect), with: .color(colour.opacity(0.07)))
        }

        var mid = Path()
        mid.move(to: CGPoint(x: 0, y: y(60)))
        mid.addLine(to: CGPoint(x: layout.width, y: y(60)))
        ctx.stroke(mid, with: .color(Color.drip.textTertiary.opacity(0.55)),
                   style: StrokeStyle(lineWidth: 1, dash: [2, 3]))

        let points = buckets.enumerated().map { CGPoint(x: layout.centreX($0.offset), y: y($0.element.recovery)) }
        guard points.count > 1 else { return }

        var area = Path()
        area.move(to: CGPoint(x: points[0].x, y: top + h))
        for p in points { area.addLine(to: p) }
        area.addLine(to: CGPoint(x: points[points.count - 1].x, y: top + h))
        area.closeSubpath()
        ctx.fill(area, with: .color(Color.drip.textPrimary.opacity(0.05)))

        var line = Path()
        line.move(to: points[0])
        for p in points.dropFirst() { line.addLine(to: p) }
        ctx.stroke(line, with: .color(Color.drip.textPrimary),
                   style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))

        let end = points[points.count - 1]
        let dot = CGRect(x: end.x - 3, y: end.y - 3, width: 6, height: 6)
        ctx.fill(Path(ellipseIn: dot.insetBy(dx: -1.5, dy: -1.5)), with: .color(Color.drip.background))
        ctx.fill(Path(ellipseIn: dot), with: .color(Self.bandColour(last.recovery)))
    }

    // 4 · Mood — colour only, one equal-height swatch per logged day.
    // Unlogged renders as empty ground: a day with no feeling logged is a
    // fact about the week, not a zero.
    private func drawMood(_ ctx: GraphicsContext, layout: Layout) {
        let lane = 3
        let top = layout.tops[lane], h = layout.heights[lane]

        laneHeader(ctx, layout: layout, lane: lane,
                   left: "Mood",
                   right: "\(set.moodLoggedDays)/\(set.days.count) days logged")

        let ground = CGRect(x: 0, y: top, width: layout.width, height: h)
        ctx.fill(Path(roundedRect: ground, cornerRadius: 2),
                 with: .color(Color.drip.paperDeep.opacity(0.55)))

        for (i, b) in set.buckets.enumerated() {
            guard let mood = b.mood else { continue }
            // One height for every mood — the lane fills, and only the hue
            // changes. Rank lives in the readout and the audio graph now,
            // never in the drawing.
            let rect = CGRect(x: layout.x(i), y: top,
                              width: max(1, layout.slot - 0.4), height: h)
            ctx.fill(Path(rect), with: .color(TrendsMoodColor.color(mood).opacity(0.92)))
        }

        drawMoodLegend(ctx, layout: layout, lane: lane)
    }

    /// The six mood colours in order, worst to best, with the two ends named.
    /// Equal-height swatches: the legend teaches the hues and nothing else.
    /// The words are what the readout speaks, so legend and readout use one
    /// vocabulary.
    private func drawMoodLegend(_ ctx: GraphicsContext, layout: Layout, lane: Int) {
        let ly = layout.bottom(lane) + 6
        let swatchMax: CGFloat = 7
        let swatchW: CGFloat = 5
        let gap: CGFloat = 3

        func label(_ text: String, at x: CGFloat, anchor: UnitPoint) -> CGFloat {
            ctx.draw(
                Text(text.uppercased())
                    .font(.dripEyebrow(microType))
                    .tracking(0.7)
                    .foregroundStyle(Color.drip.textTertiary),
                at: CGPoint(x: x, y: ly + swatchMax / 2),
                anchor: anchor
            )
            return CGFloat(text.count) * microType * 0.62
        }

        // Worst → best, left to right. Equal heights — see `drawMood`.
        let ramp = TrendsMoodColor.ordered.reversed()
        var x = label("Injured", at: 0, anchor: .leading) + 8
        for mood in ramp {
            let rect = CGRect(x: x, y: ly, width: swatchW, height: swatchMax)
            ctx.fill(Path(roundedRect: rect, cornerRadius: 0.5),
                     with: .color(TrendsMoodColor.color(mood).opacity(0.92)))
            x += swatchW + gap
        }
        _ = label("Energized", at: x + 5, anchor: .leading)
    }

    // 5 · Niggles — ticks, opacity from the athlete's own severity word.
    private func drawNiggles(_ ctx: GraphicsContext, layout: Layout) {
        let lane = 4
        let top = layout.tops[lane], h = layout.heights[lane]
        let mentions = set.niggleMentionCount

        laneHeader(ctx, layout: layout, lane: lane,
                   left: "Niggles",
                   right: mentions == 0 ? "none" : (mentions == 1 ? "1 mention" : "\(mentions) mentions"))

        var baseline = Path()
        baseline.move(to: CGPoint(x: 0, y: top + h))
        baseline.addLine(to: CGPoint(x: layout.width, y: top + h))
        ctx.stroke(baseline, with: .color(Color.drip.divider), lineWidth: 1)

        let w = max(2, layout.barWidth * 0.7)
        for (i, b) in set.buckets.enumerated() where b.hasNiggle {
            let rect = CGRect(x: layout.x(i) + (layout.slot - w) / 2, y: top, width: w, height: h)
            ctx.fill(Path(roundedRect: rect, cornerRadius: 1),
                     with: .color(Color.drip.injured.opacity(TrendsSeverity.opacity(b.loudestSeverity))))
        }
    }

    private func drawAxis(_ ctx: GraphicsContext, layout: Layout) {
        let buckets = set.buckets
        guard buckets.count > 1 else { return }
        // Five reference labels once the window is wide enough — three left
        // ~4-month gaps unlabeled at a year. Ends pin to the chart edges;
        // interior labels centre on their column.
        let n = buckets.count

        // Label width is estimated from the widest mark's own text, so the
        // count backs off when the labels would touch — at a narrow custom
        // window five of them ran together, and at the accessibility type
        // sizes three can too. Ends always survive: the window's first and
        // last dates are the two the axis exists to state.
        let candidates: [[Int]] = n >= 8
            ? [[0, n / 4, n / 2, (3 * n) / 4, n - 1], [0, n / 2, n - 1], [0, n - 1]]
            : [[0, n / 2, n - 1], [0, n - 1]]
        let marks = candidates.first { set in
            let widest = set.map { buckets[$0].label.count }.max() ?? 6
            let need = CGFloat(widest) * microType * 0.62 + 10
            return need * CGFloat(set.count) <= layout.width
        } ?? [0, n - 1]

        for (k, i) in marks.enumerated() {
            let isFirst = k == 0
            let isLast = k == marks.count - 1
            let x: CGFloat = isFirst ? 0 : (isLast ? layout.width : layout.centreX(i))
            let anchor: UnitPoint = isFirst ? .leading : (isLast ? .trailing : .center)
            // textSecondary, not textTertiary: #9B9590 on the #F5F3F0 paper
            // is 2.7:1, well under the 4.5:1 these labels need at this size.
            // #6B6560 measures 5.2:1 on the same ground.
            ctx.draw(
                Text(buckets[i].label.uppercased())
                    .font(.dripEyebrow(microType))
                    .tracking(0.8)
                    .foregroundStyle(Color.drip.textSecondary),
                at: CGPoint(x: x, y: layout.axisY),
                anchor: anchor
            )
        }
    }

    // MARK: - Readout

    @ViewBuilder
    private func readout(for bucket: TrendsBucket, layout: Layout, width: CGFloat) -> some View {
        let cardWidth: CGFloat = 190
        let index = set.buckets.firstIndex { $0.id == bucket.id } ?? 0
        let centre = layout.centreX(index)
        let left = min(max(0, centre - cardWidth / 2), max(0, width - cardWidth))

        VStack(alignment: .leading, spacing: 5) {
            Text((set.grain == .day ? bucket.label : "Week of \(bucket.label)").uppercased())
                .font(.dripEyebrow(microType))
                .tracking(1.2)
                .foregroundStyle(Color.drip.background.opacity(0.65))
                .padding(.bottom, 1)

            readoutRow("Run", runSummary(bucket))
            readoutRow("Recovery", "\(bucket.recovery) · \(TrendsRecoveryLedger.Band.of(bucket.recovery).rawValue.uppercased())")
            readoutRow("Mood", bucket.mood?.uppercased() ?? "not logged")
            readoutRow("Niggle", bucket.niggles.isEmpty
                       ? "none"
                       : bucket.niggles.map { $0.area.uppercased() }.joined(separator: ", "))

            // Verbatim, always. The athlete's own words are never summarised.
            if let quote = bucket.niggles.first?.quote, !quote.isEmpty {
                Divider().overlay(Color.drip.background.opacity(0.22))
                Text("“\(quote)”")
                    .font(.dripBody(10.5))
                    .italic()
                    .foregroundStyle(Color.drip.background.opacity(0.88))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .frame(width: cardWidth, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8).fill(Color.drip.textPrimary)
        )
        .offset(x: left, y: 0)
        .allowsHitTesting(false)
        .transition(.opacity)
    }

    private func readoutRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label.uppercased())
                .font(.dripEyebrow(microType))
                .tracking(0.6)
                .foregroundStyle(Color.drip.background.opacity(0.65))
            Spacer(minLength: 4)
            Text(value)
                .font(.dripStat(10))
                .foregroundStyle(Color.drip.background)
                .multilineTextAlignment(.trailing)
        }
    }

    private func runSummary(_ b: TrendsBucket) -> String {
        guard b.miles > 0 else { return "day off" }
        let miles = String(format: "%.1f mi", b.miles)
        if set.grain == .week {
            return "\(miles) · \(b.keyCount) key"
        }
        return "\(miles) \(b.channel.readoutLabel)"
    }

    // MARK: - Spoken forms

    /// One column, spoken. Channels with nothing to say are omitted rather
    /// than read out as "none" — a VoiceOver reader shouldn't have to sit
    /// through four negatives per day to reach the one fact that moved.
    /// A rest day is not an absence, though: zero miles is a fact, and it
    /// says so.
    func axLabel(_ b: TrendsBucket) -> String {
        let date = set.grain == .day
            ? Self.spokenDate(b.startISO)
            : "Week of \(Self.spokenDate(b.startISO))"

        var parts: [String] = []

        if b.miles > 0 {
            var run = String(format: "%.1f miles", b.miles)
            if set.grain == .week {
                if b.keyCount > 0 {
                    run += ", \(b.keyCount) key session\(b.keyCount == 1 ? "" : "s")"
                }
            } else {
                run += ", \(Self.spokenChannel(b.channel))"
            }
            parts.append(run)
        } else {
            parts.append(set.grain == .day ? "rest day" : "no miles")
        }

        parts.append("recovery \(b.recovery), \(TrendsRecoveryLedger.Band.of(b.recovery).rawValue)")

        if let mood = b.mood, !mood.isEmpty { parts.append("mood \(mood)") }

        if !b.niggles.isEmpty {
            let said = b.niggles.map { n in
                [n.area, n.severity].compactMap { $0 }.joined(separator: ", ")
            }
            parts.append("niggle: \(said.joined(separator: "; "))")
        }

        return "\(date) — \(parts.joined(separator: "; "))"
    }

    private static let spokenMonths = [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December",
    ]

    /// "2026-07-14" → "July 14". The axis abbreviates; speech should not.
    static func spokenDate(_ iso: String) -> String {
        let p = iso.prefix(10).split(separator: "-")
        guard p.count == 3, let m = Int(p[1]), (1...12).contains(m), let d = Int(p[2])
        else { return iso }
        return "\(spokenMonths[m - 1]) \(d)"
    }

    /// The readout's channel words, written out for speech.
    static func spokenChannel(_ c: TrendsSessionChannel) -> String {
        switch c {
        case .rest: "rest day"
        case .easy: "easy run"
        case .long: "long run"
        case .key: "key session"
        case .keyLong: "long run with key work"
        }
    }

    // MARK: - Palette

    /// Dark warm grey — the long-run channel. Not a mood, not a pace.
    private static let longInk = Color(red: 0x7A / 255, green: 0x73 / 255, blue: 0x6C / 255)
    /// Light warm grey — easy volume.
    private static let easyInk = Color(red: 0xD8 / 255, green: 0xD3 / 255, blue: 0xCD / 255)

    private func fill(for channel: TrendsSessionChannel) -> Color {
        switch channel {
        case .key, .keyLong: Color.drip.coral
        case .long: Self.longInk
        case .easy: Self.easyInk
        case .rest: Color.clear
        }
    }

    static func bandColour(_ score: Int) -> Color {
        switch TrendsRecoveryLedger.Band.of(score) {
        case .flat: Color.drip.struggling
        case .worn: Color.drip.tired
        case .steady: Color.drip.neutral
        case .clear: Color.drip.positive
        }
    }
}

// MARK: - Audio graph

/// The five lanes as an audio graph.
///
/// **Why every series is normalised to its own lane.** The five signals have
/// nothing like a shared scale — miles run 0…20, recovery 8…96, key work 0…3.
/// Plotting them against one numeric axis would flatten mileage into a
/// straight line and make the graph a worse description of the data than the
/// picture it describes. Each series is therefore mapped to 0…100 *of its own
/// lane*, exactly as the Canvas draws it, so the pitch contour the reader
/// hears is the shape the sighted reader sees. Nothing is lost to that
/// normalisation, because every point also carries a `label` holding the real
/// value in words — the graph sounds like the chart and speaks like the data.
///
/// Mood and niggles are discrete, not continuous, and days with neither
/// contribute no point at all: an unlogged mood is not a low mood.
extension TrendsSignalLanes: AXChartDescriptorRepresentable {

    func makeChartDescriptor() -> AXChartDescriptor {
        let buckets = set.buckets
        let grainWord = set.grain == .day ? "day" : "week"

        let xAxis = AXNumericDataAxisDescriptor(
            title: "Date",
            range: 0...Double(max(1, buckets.count - 1)),
            gridlinePositions: [],
            valueDescriptionProvider: { value in
                guard !buckets.isEmpty else { return "" }
                let i = min(buckets.count - 1, max(0, Int(value.rounded())))
                let iso = buckets[i].startISO
                return set.grain == .day
                    ? Self.spokenDate(iso)
                    : "week of \(Self.spokenDate(iso))"
            }
        )

        let yAxis = AXNumericDataAxisDescriptor(
            title: "Level within its own lane",
            range: 0...100,
            gridlinePositions: [],
            valueDescriptionProvider: { "\(Int($0.rounded())) percent of lane" }
        )

        func makeSeries(
            _ name: String,
            continuous: Bool,
            _ point: (TrendsBucket) -> (normalised: Double, spoken: String)?
        ) -> AXDataSeriesDescriptor {
            AXDataSeriesDescriptor(
                name: name,
                isContinuous: continuous,
                dataPoints: buckets.enumerated().compactMap { i, b in
                    guard let p = point(b) else { return nil }
                    return AXDataPoint(
                        x: Double(i),
                        y: min(100, max(0, p.normalised)),
                        additionalValues: [],
                        label: p.spoken
                    )
                }
            )
        }

        let maxMiles = buckets.map(\.miles).max() ?? 0
        let maxKey = Double(buckets.map(\.keyCount).max() ?? 0)

        let series = [
            makeSeries("Mileage", continuous: true) { b in
                guard maxMiles > 0 else { return (0, "no miles") }
                return (b.miles / maxMiles * 100, String(format: "%.1f miles", b.miles))
            },
            makeSeries("Key work", continuous: true) { b in
                guard maxKey > 0 else { return (0, "no key sessions") }
                let word = b.keyCount == 1 ? "1 key session" : "\(b.keyCount) key sessions"
                return (Double(b.keyCount) / maxKey * 100, word)
            },
            makeSeries("Recovery", continuous: true) { b in
                // The score's real clamp, matching the lane's own floor.
                let n = (Double(b.recovery) - 8) / (96 - 8) * 100
                return (n, "\(b.recovery), \(TrendsRecoveryLedger.Band.of(b.recovery).rawValue)")
            },
            makeSeries("Mood", continuous: false) { b in
                guard let mood = b.mood, !mood.isEmpty else { return nil }
                return (TrendsMoodColor.rank(mood) * 100, mood)
            },
            makeSeries("Niggles", continuous: false) { b in
                guard b.hasNiggle else { return nil }
                let said = b.niggles.map { n in
                    [n.area, n.severity].compactMap { $0 }.joined(separator: ", ")
                }
                return (Double(TrendsSeverity.rank(b.loudestSeverity)) / 4 * 100,
                        said.joined(separator: "; "))
            },
        ]

        return AXChartDescriptor(
            title: "Five signals",
            summary: "Mileage, key work, recovery, mood and niggles over "
                + "\(buckets.count) \(grainWord)\(buckets.count == 1 ? "" : "s"), "
                + "each series scaled to its own lane.",
            xAxis: xAxis,
            yAxis: yAxis,
            additionalAxes: [],
            series: series
        )
    }

    /// The window picker rebuilds the whole bucket set, so the cached
    /// descriptor has to be refreshed rather than left describing the range
    /// the athlete just navigated away from.
    func updateChartDescriptor(_ descriptor: AXChartDescriptor) {
        let fresh = makeChartDescriptor()
        descriptor.title = fresh.title
        descriptor.summary = fresh.summary
        descriptor.xAxis = fresh.xAxis
        descriptor.yAxis = fresh.yAxis
        descriptor.series = fresh.series
    }
}

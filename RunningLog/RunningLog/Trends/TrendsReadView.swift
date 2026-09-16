//
//  TrendsReadView.swift
//  RunningLog · Trends
//
//  The Read — the story-and-month surface explored in
//  `design-system/explorations/trends-story-calendar-2026-08-06.html`
//  (Fig. 09). A templated headline, a templated story, one volume figure,
//  one month grid. Nothing on this screen is narrated by a model; every
//  string comes from `TrendsReadBuilder`.
//
//  **One month at a time.** The service fetches six months; this surface
//  reads one of them and steps back a month at a time. That is not a
//  display preference — a read over 180 days puts 180 bars inside each
//  other, turns the grid into an endless scroll, and produces a headline
//  ("1302 miles") that no athlete has a feel for. A month is the unit she
//  already thinks in and the unit the grid draws.
//
//  Encoding, one channel per property so no two readings compete:
//  • bar height  → miles that day
//  • bar colour  → the work zone, **key sessions only**. An easy day has no
//    classified pace in the payload, so its bar stays neutral rather than
//    borrowing a colour it did not earn. Blue is pace and nothing else
//    (the three-palette rule).
//  • star        → a key session landed here
//  • cell tint   → that day's mood, at wash strength — colour alone, never
//    a height (`TrendsMoodColor`, 2026-08-06).
//  • coral date  → a body mention landed here. Coral is the alert palette
//    and appears at most once per cluster.
//
//  Scope: volume, mood, niggles and the month. Load and recovery do not
//  belong to a single day and already have renderers on the Trends tab —
//  they join as lanes under the figure rather than being drawn twice.
//

import SwiftUI

struct TrendsReadView: View {
    let windows: [TrendsReadWindow]
    let keySessions: [KeySession]
    /// The full payload. Recovery and the load baseline read backwards past
    /// the start of the month on screen, so the builder needs the history
    /// even though only one month is drawn.
    let history: [TrendsDay]

    /// 0 is the newest month; stepping up walks backwards through the year.
    @State private var index = 0
    /// The day whose detail sheet is open, if any.
    @State private var selected: String?
    /// Index of the day under the finger while scrubbing a chart. All three
    /// charts share it, so one drag moves one crosshair across all of them.
    @State private var scrub: Int?

    private let cellHeight: CGFloat = 46

    init(days: [TrendsDay], keySessions: [KeySession] = []) {
        self.windows = TrendsReadBuilder.windows(days)
        self.keySessions = keySessions
        self.history = days
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                plate
                monthBar

                if let read {
                    headline(read)

                    if read.isThin {
                        thinState(read)
                    } else {
                        story(read)
                        DripEditorialRule().padding(.vertical, 18)
                        figure(read)
                        lanes(read)
                        DripEditorialRule().padding(.vertical, 18)
                        grid(read)
                        moodKey(read)
                        footnote
                        askBar
                    }
                } else {
                    emptyPayload
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .background(Color.drip.background)
        .sheet(item: Binding(
            get: { selected.map(SelectedDay.init(date:)) },
            set: { selected = $0?.date }
        )) { pick in
            TrendsReadDaySheet(
                date: pick.date,
                day: history.first { $0.date == pick.date },
                session: keySessions.first { $0.date == pick.date }
            )
        }
    }

    private struct SelectedDay: Identifiable {
        let date: String
        var id: String { date }
    }

    // MARK: Derived

    private var window: TrendsReadWindow? {
        windows.indices.contains(index) ? windows[index] : nil
    }

    private var read: TrendsRead? {
        window.map {
            TrendsReadBuilder.build(
                month: $0.days, history: history, keySessions: keySessions
            )
        }
    }

    private var days: [TrendsRead.MonthDay] {
        read?.weeks.flatMap { $0.days.compactMap { $0 } } ?? []
    }

    /// Older months sit at higher indices, so "back" increments.
    private var canGoBack: Bool { index + 1 < windows.count }
    private var canGoForward: Bool { index > 0 }

    // MARK: Chrome

    private var plate: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("RUNNING LOG — THE READ")
            Spacer()
            Text(rangeLabel)
        }
        .font(.dripEyebrow(10))
        .tracking(1.4)
        .foregroundStyle(Color.drip.textSecondary)
        .padding(.top, 18)
        .padding(.bottom, 14)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.drip.divider).frame(height: 1)
        }
    }

    private var rangeLabel: String {
        guard let first = days.first?.date, let last = days.last?.date else { return "" }
        return "\(TrendsReadBuilder.label(first)) – \(TrendsReadBuilder.label(last))".uppercased()
    }

    /// `‹  AUGUST 2026  ›`. The only control on the surface.
    private var monthBar: some View {
        HStack(spacing: 0) {
            step(icon: "chevron.left", enabled: canGoBack) { index += 1 }

            Text((window?.title ?? "").uppercased())
                .font(.dripEyebrow(11))
                .tracking(1.5)
                .foregroundStyle(Color.drip.textPrimary)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(window?.title ?? "No window")

            step(icon: "chevron.right", enabled: canGoForward) { index -= 1 }
        }
        .padding(.top, 16)
    }

    private func step(icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.drip.textSecondary)
                .frame(width: 44, height: 30)
                .contentShape(Rectangle())
        }
        .opacity(enabled ? 1 : 0.32)
        .allowsHitTesting(enabled)
        .accessibilityLabel(icon == "chevron.left" ? "Previous month" : "Next month")
    }

    // MARK: Headline

    private func headline(_ read: TrendsRead) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(read.headline)
                .font(.dripDisplay(33))
                .foregroundStyle(Color.drip.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if !read.subline.isEmpty {
                Text(read.subline.uppercased())
                    .font(.dripEyebrow(10.5))
                    .tracking(1.05)
                    .foregroundStyle(Color.drip.textSecondary)
            }
        }
        .padding(.top, 14)
    }

    // MARK: Story

    private func story(_ read: TrendsRead) -> some View {
        storyText(read)
            .font(.dripBody(14.5))
            .foregroundStyle(Color.drip.textPrimary)
            .lineSpacing(5)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 12)
            .accessibilityLabel(read.beats.map(\.text).joined(separator: " "))
    }

    /// Concatenated so the callout numerals sit as superscripts inside the
    /// paragraph rather than breaking it into separate blocks.
    private func storyText(_ read: TrendsRead) -> Text {
        // Built by interpolating `Text` into `Text` rather than with `+`, which
        // is deprecated from iOS 26. Interpolation keeps what `+` was here for:
        // each fragment carries its OWN styling into the same paragraph, which
        // is what puts the callout numeral inline as a superscript instead of
        // breaking the story into separate blocks.
        read.beats.reduce(Text(verbatim: "")) { acc, beat in
            let body = Text(beat.text)
            guard let callout = beat.callout else {
                return Text("\(acc)\(body) ")
            }
            let mark = Text(verbatim: "\(callout)")
                .font(.dripCaption(9))
                .baselineOffset(6)
                .foregroundStyle(Color.drip.textSecondary)
            return Text("\(acc)\(body)\(mark) ")
        }
    }

    private func thinState(_ read: TrendsRead) -> some View {
        Text(read.beats.first?.text ?? "")
            .font(.dripBody(14))
            .italic()
            .foregroundStyle(Color.drip.textSecondary)
            .padding(.top, 14)
    }

    private var emptyPayload: some View {
        Text("No runs logged yet. When you do, the month lands here.")
            .font(.dripBody(14))
            .italic()
            .foregroundStyle(Color.drip.textSecondary)
            .padding(.top, 24)
    }

    // MARK: The figure

    private func figure(_ read: TrendsRead) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHead("Volume × pace", trailing: scrubSummary(read) ?? workSummary)

            // 88pt of bars + 15pt of star gutter — the geometry in
            // `trends-story-calendar-2026-08-06.html`, matched exactly.
            Canvas { context, size in
                draw(in: &context, size: size)
            }
            .frame(height: 103)
            .padding(.top, 2)
            .overlay { scrubLayer() }
            .accessibilityLabel("Daily miles across the month, key sessions marked")

            // Five stops, evenly spaced — the mock's axis. Two stops left
            // the middle of a 30-day row unlabelled.
            HStack(spacing: 0) {
                ForEach(Array(axisStops.enumerated()), id: \.offset) { i, stop in
                    Text(stop.uppercased())
                        .frame(
                            maxWidth: .infinity,
                            alignment: i == 0 ? .leading
                                : (i == axisStops.count - 1 ? .trailing : .center)
                        )
                }
            }
            .font(.dripCaption(10))
            .tracking(1)
            .foregroundStyle(Color.drip.textTertiary)

            paceLegend.padding(.top, 6)
        }
    }

    // MARK: Scrubbing

    /// The day under the finger, if any.
    private var scrubDay: TrendsRead.MonthDay? {
        guard let scrub, days.indices.contains(scrub) else { return nil }
        return days[scrub]
    }

    /// Replaces a section's trailing stat while a finger is down, so the
    /// readout lands where the eye already is instead of in a floating chip.
    private func scrubSummary(_ read: TrendsRead) -> String? {
        guard let day = scrubDay else { return nil }
        var parts = [TrendsReadBuilder.label(day.date)]
        parts.append(day.miles > 0 ? "\(Int(day.miles.rounded())) mi" : "rest")
        if let load = read.load.first(where: { $0.date == day.date }) {
            parts.append("7-day \(Int(load.value.rounded()))")
        }
        return parts.joined(separator: " · ")
    }

    /// Same x mapping the bars use, inverted.
    private func scrubIndex(x: CGFloat, width: CGFloat) -> Int? {
        let n = days.count
        guard n > 1, width > 0 else { return nil }
        let barWidth = min(7, width / CGFloat(n) * 0.62)
        let step = (width - barWidth) / CGFloat(n - 1)
        guard step > 0 else { return nil }
        let raw = Int(((x - barWidth / 2) / step).rounded())
        return min(max(raw, 0), n - 1)
    }

    /// One transparent layer per chart. A drag scrubs; a tap — a drag that
    /// never travelled — opens that day.
    private func scrubLayer() -> some View {
        GeometryReader { geo in
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            scrub = scrubIndex(x: value.location.x, width: geo.size.width)
                        }
                        .onEnded { value in
                            let travelled = abs(value.translation.width)
                                + abs(value.translation.height)
                            if travelled < 8,
                               let i = scrub, days.indices.contains(i) {
                                selected = days[i].date
                            }
                            scrub = nil
                        }
                )
        }
    }

    /// Five evenly-spaced day labels across the window.
    private var axisStops: [String] {
        let all = days
        guard all.count > 1 else { return all.map { TrendsReadBuilder.label($0.date) } }
        return (0 ..< 5).map { i in
            let idx = Int((Double(i) / 4 * Double(all.count - 1)).rounded())
            return TrendsReadBuilder.label(all[min(idx, all.count - 1)].date)
        }
    }

    private var workSummary: String {
        let miles = Int(days.reduce(0) { $0 + $1.miles }.rounded())
        let key = days.filter(\.isKey).count
        return "\(miles) mi · \(key) key"
    }

    /// The ten-stop ramp, Easy → Fast. Without it the ramp-colored bars are a
    /// colour with no key.
    private var paceLegend: some View {
        HStack(spacing: 8) {
            Text("EASY")
            HStack(spacing: 0) {
                ForEach(Array(PaceSpectrum.stops.enumerated()), id: \.offset) { _, stop in
                    Rectangle().fill(stop)
                }
            }
            .frame(height: 7)
            .clipShape(RoundedRectangle(cornerRadius: 2))
            Text("FAST")
        }
        .font(.dripCaption(10))
        .tracking(1)
        .foregroundStyle(Color.drip.textTertiary)
        .accessibilityHidden(true)
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let all = days
        guard all.count > 1 else { return }

        // Geometry lifted from the HTML, one for one:
        //   BARS = 88, BW = 7, PAD = BW/2
        //   X(i) = PAD + (i / (n-1)) · (W - BW)
        // Point positioning, not band: the first bar's centre sits half a
        // bar in from the left edge and the last one half a bar in from the
        // right, so the row spans the full width instead of floating inside
        // it. A month is 28–31 bars, which at 345pt leaves a ~4.3pt gap —
        // the spacing the mock was drawn at.
        let barsHeight: CGFloat = 88
        let barWidth: CGFloat = min(7, size.width / CGFloat(all.count) * 0.62)
        let pad = barWidth / 2
        let step = (size.width - barWidth) / CGFloat(all.count - 1)
        let peak = all.map(\.miles).max() ?? 0
        guard peak > 0 else { return }

        var base = Path()
        base.move(to: CGPoint(x: 0, y: barsHeight))
        base.addLine(to: CGPoint(x: size.width, y: barsHeight))
        context.stroke(base, with: .color(Color.drip.divider), lineWidth: 1)

        for (i, day) in all.enumerated() {
            let centre = pad + CGFloat(i) * step

            if day.miles > 0 {
                let height = max(3, CGFloat(day.miles / peak) * (barsHeight - 6))
                context.fill(
                    Path(
                        roundedRect: CGRect(
                            x: centre - barWidth / 2,
                            y: barsHeight - height,
                            width: barWidth,
                            height: height
                        ),
                        cornerRadius: 1.5
                    ),
                    with: .color(barColor(day))
                )
            }

            if day.isKey {
                context.fill(
                    star(centre: CGPoint(x: centre, y: barsHeight + 7.5), radius: 4.5),
                    with: .color(Color.drip.textPrimary)
                )
            }
        }

        // Crosshair last, so it rides over the bars.
        if let scrub, all.indices.contains(scrub) {
            let x = pad + CGFloat(scrub) * step
            var line = Path()
            line.move(to: CGPoint(x: x, y: 0))
            line.addLine(to: CGPoint(x: x, y: barsHeight))
            context.stroke(line, with: .color(Color.drip.coral), lineWidth: 1)
        }
    }

    /// Pace blue when the day carries a classified work zone, neutral ink
    /// otherwise. Never a guess.
    private func barColor(_ day: TrendsRead.MonthDay) -> Color {
        guard let token = day.zoneToken else {
            return Color.drip.textTertiary.opacity(0.5)
        }
        return Self.zoneColor(token)
    }

    /// Work-zone token → the shared pace ramp. The backend classifier folds
    /// LT into `hmp`, so there is no `lt` case to map here.
    static func zoneColor(_ token: String) -> Color {
        switch token.lowercased() {
        case "mile": PaceSpectrum.mile
        case "3k":   PaceSpectrum.threeK
        case "5k":   PaceSpectrum.fiveK
        case "10k":  PaceSpectrum.tenK
        case "hmp":  PaceSpectrum.hmp
        case "mp":   PaceSpectrum.mp
        default:     PaceSpectrum.steady
        }
    }

    /// A drawn five-point star. Not the ★ glyph: the system admits only
    /// `·`, `↗` and `→` as unicode marks, so this is a path.
    private func star(centre: CGPoint, radius: CGFloat) -> Path {
        var path = Path()
        for i in 0 ..< 10 {
            // CGFloat throughout: `cos` overloads on Float/Double/CGFloat, and
            // mixing a Double angle with a CGFloat radius makes the call
            // ambiguous rather than merely promoting.
            let angle: CGFloat = (CGFloat(i) * 36 - 90) * .pi / 180
            let r: CGFloat = i.isMultiple(of: 2) ? radius : radius * 0.42
            let point = CGPoint(x: centre.x + r * cos(angle), y: centre.y + r * sin(angle))
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }

    // MARK: The lanes — recovery and load

    /// The two signals that don't belong to a single day, so they sit under
    /// the figure on the same month axis rather than inside the grid.
    /// Both lanes always render their header. An empty series states why it
    /// is empty rather than vanishing — a lane that silently disappears is
    /// indistinguishable from a lane that was never built, which is exactly
    /// the failure this surface hit.
    @ViewBuilder
    private func lanes(_ read: TrendsRead) -> some View {
        lane(
            title: "Load",
            trailing: scrubSummary(read) ?? "",
            points: read.load,
            reference: read.loadBaseline,
            referenceLabel: "8-WK MEAN",
            height: 62,
            floor: 0,
            ceiling: 100,
            emptyNote: "No recovery score for this month yet."
        )
        .padding(.top, 16)

        lane(
            title: "Load",
            trailing: scrubSummary(read)
                ?? read.loadBaseline.map { "7-day mi · 8-wk avg \(Int($0.rounded()))" }
                ?? "7-day mi",
            points: read.load,
            reference: read.loadBaseline,
            referenceLabel: "8-WK AVG",
            height: 54,
            floor: nil,
            ceiling: nil,
            emptyNote: "Needs 7 days of history before a trailing week exists."
        )
        .padding(.top, 14)
    }

    private func lane(
        title: String,
        trailing: String,
        points: [TrendsRead.LanePoint],
        reference: Double?,
        referenceLabel: String,
        height: CGFloat,
        floor: Double?,
        ceiling: Double?,
        emptyNote: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionHead(title, trailing: trailing)

            if points.count > 1 {
                Canvas { context, size in
                    drawLane(
                        in: &context, size: size, points: points,
                        reference: reference, referenceLabel: referenceLabel,
                        floor: floor, ceiling: ceiling
                    )
                }
                .frame(height: height)
                .overlay { scrubLayer() }
                .accessibilityLabel("\(title) across the month")
            } else {
                // State the absence, then say what will fill it — the house
                // empty-state pattern.
                Text(emptyNote)
                    .font(.dripBody(12.5))
                    .italic()
                    .foregroundStyle(Color.drip.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            }
        }
    }

    private func drawLane(
        in context: inout GraphicsContext,
        size: CGSize,
        points: [TrendsRead.LanePoint],
        reference: Double?,
        referenceLabel: String,
        floor: Double?,
        ceiling: Double?
    ) {
        guard points.count > 1 else { return }

        let values = points.map(\.value) + [reference].compactMap { $0 }
        let low = floor ?? ((values.min() ?? 0) * 0.9)
        let high = ceiling ?? max((values.max() ?? 1) * 1.08, low + 1)
        guard high > low else { return }

        let pad: CGFloat = 5
        func y(_ v: Double) -> CGFloat {
            size.height - pad - CGFloat((v - low) / (high - low)) * (size.height - pad * 2)
        }
        // Identical mapping to the bars, so a day sits at the same x in every
        // chart and one crosshair lines up across all three.
        let barWidth = min(7, size.width / CGFloat(points.count) * 0.62)
        let originX = barWidth / 2
        let step = (size.width - barWidth) / CGFloat(max(points.count - 1, 1))

        if let reference {
            var line = Path()
            line.move(to: CGPoint(x: 0, y: y(reference)))
            line.addLine(to: CGPoint(x: size.width, y: y(reference)))
            context.stroke(
                line,
                with: .color(Color.drip.textTertiary),
                style: StrokeStyle(lineWidth: 1, dash: [3, 4])
            )
            // Sits clear ABOVE its own line — anchoring the top at y-7 put
            // the text across the dashes and read as a strikethrough.
            context.draw(
                Text(referenceLabel)
                    .font(.dripCaption(7.5))
                    .foregroundStyle(Color.drip.textTertiary),
                at: CGPoint(x: 2, y: y(reference) - 4),
                anchor: .bottomLeading
            )
        }

        var path = Path()
        for (i, point) in points.enumerated() {
            let p = CGPoint(x: originX + CGFloat(i) * step, y: y(point.value))
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        context.stroke(
            path,
            with: .color(Color.drip.textPrimary),
            style: StrokeStyle(lineWidth: 1.5, lineJoin: .round)
        )

        if let last = points.last {
            context.fill(
                Path(ellipseIn: CGRect(
                    x: originX + CGFloat(points.count - 1) * step - 2.6,
                    y: y(last.value) - 2.6, width: 5.2, height: 5.2
                )),
                with: .color(Color.drip.textPrimary)
            )
        }

        if let scrub, points.indices.contains(scrub) {
            let x = originX + CGFloat(scrub) * step
            var line = Path()
            line.move(to: CGPoint(x: x, y: 0))
            line.addLine(to: CGPoint(x: x, y: size.height))
            context.stroke(line, with: .color(Color.drip.coral), lineWidth: 1)
            context.fill(
                Path(ellipseIn: CGRect(
                    x: x - 3, y: y(points[scrub].value) - 3, width: 6, height: 6
                )),
                with: .color(Color.drip.coral)
            )
        }
    }

    // MARK: The grid

    private func grid(_ read: TrendsRead) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHead("The month", trailing: "Mood tints the day")

            VStack(spacing: 3) {
                HStack(spacing: 3) {
                    ForEach(Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()),
                            id: \.offset) { _, symbol in
                        Text(symbol)
                            .font(.dripCaption(8.5))
                            .tracking(0.85)
                            .foregroundStyle(Color.drip.textTertiary)
                            .frame(maxWidth: .infinity)
                    }
                    Text("WK")
                        .font(.dripCaption(8.5))
                        .tracking(0.85)
                        .foregroundStyle(Color.drip.textTertiary)
                        .frame(width: 40, alignment: .trailing)
                }

                ForEach(read.weeks) { week in
                    HStack(spacing: 3) {
                        ForEach(Array(week.days.enumerated()), id: \.offset) { _, day in
                            cell(day)
                        }
                        margin(week.miles)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cell(_ day: TrendsRead.MonthDay?) -> some View {
        if let day {
            ZStack {
                RoundedRectangle(cornerRadius: 4).fill(cellFill(day))

                // Date, top-leading. Coral when a body mention landed here.
                Text(verbatim: "\(day.dayOfMonth)")
                    .font(.dripCaption(8.5))
                    .foregroundStyle(day.hasNiggle ? Color.drip.coral : Color.drip.textTertiary)
                    .fontWeight(day.hasNiggle ? .semibold : .regular)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.leading, 5)
                    .padding(.top, 4)

                if let mood = day.mood {
                    Circle()
                        .fill(TrendsMoodColor.color(mood))
                        .frame(width: 5, height: 5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(.trailing, 5)
                        .padding(.top, 5)
                }

                // Miles, centred low. The star rides under it so the two
                // never share a baseline.
                VStack(spacing: 2) {
                    if day.miles > 0 {
                        Text(verbatim: "\(Int(day.miles.rounded()))")
                            .font(.dripStat(13))
                            .foregroundStyle(Color.drip.textPrimary)
                    }
                    if day.isKey {
                        Circle().fill(Color.drip.textPrimary).frame(width: 3, height: 3)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 5)

                // Story callout, bottom-leading — the one corner the date,
                // the mood dot and the mileage all leave free.
                if let callout = day.callout {
                    Text(verbatim: "\(callout)")
                        .font(.dripCaption(8))
                        .foregroundStyle(Color.drip.textPrimary)
                        .frame(width: 12, height: 12)
                        .background(
                            Circle()
                                .fill(Color.drip.cardBackground)
                                .overlay(Circle().stroke(Color.drip.textTertiary, lineWidth: 1))
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .padding(.leading, 3)
                        .padding(.bottom, 3)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: cellHeight)
            .contentShape(RoundedRectangle(cornerRadius: 4))
            .onTapGesture { selected = day.date }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(cellLabel(day))
            .accessibilityHint("Opens the day")
            .accessibilityAddTraits(.isButton)
        } else {
            Color.clear.frame(maxWidth: .infinity).frame(height: cellHeight)
        }
    }

    private func cellFill(_ day: TrendsRead.MonthDay) -> Color {
        if let mood = day.mood {
            return TrendsMoodColor.color(mood).opacity(0.20)
        }
        return day.miles > 0 ? Color.drip.cardBackground : Color.drip.paperDeep
    }

    private func cellLabel(_ day: TrendsRead.MonthDay) -> String {
        var parts = [TrendsReadBuilder.label(day.date)]
        parts.append(day.miles > 0 ? "\(Int(day.miles.rounded())) miles" : "rest")
        if let mood = day.mood { parts.append(mood) }
        if day.isKey { parts.append("key session") }
        if day.hasNiggle { parts.append("body mention") }
        return parts.joined(separator: ", ")
    }

    private func margin(_ miles: Double) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(verbatim: "\(Int(miles.rounded()))")
                .font(.dripStat(13))
                .foregroundStyle(Color.drip.textPrimary)
            Text("MI")
                .font(.dripCaption(7.5))
                .tracking(0.75)
                .foregroundStyle(Color.drip.textTertiary)
        }
        .frame(width: 40, height: cellHeight, alignment: .trailing)
        .overlay(alignment: .leading) {
            Rectangle().fill(Color.drip.divider).frame(width: 1)
        }
        .accessibilityLabel("Week total \(Int(miles.rounded())) miles")
    }

    // MARK: Mood key

    private func moodKey(_ read: TrendsRead) -> some View {
        HStack(spacing: 12) {
            ForEach(read.moodCounts, id: \.mood) { entry in
                HStack(spacing: 5) {
                    Circle()
                        .fill(TrendsMoodColor.color(entry.mood))
                        .frame(width: 6, height: 6)
                    Text("\(entry.mood.uppercased()) \(entry.count)")
                        .font(.dripCaption(10))
                        .tracking(1)
                        .foregroundStyle(Color.drip.textTertiary)
                }
            }
        }
        .padding(.top, 12)
    }

    /// The plate footer — the register the whole system is set in.
    private var footnote: some View {
        Text("— numerals in the read point into the month —")
            .font(.dripBody(11.5))
            .italic()
            .foregroundStyle(Color.drip.textTertiary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 18)
    }

    /// Hands the window to the coach composer. Inert here until the Read
    /// graduates past comparison — `CoachAskContext` is the wire.
    private var askBar: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Ask about this block…")
                .font(.dripBody(14))
                .italic()
                .foregroundStyle(Color.drip.textTertiary)
            Spacer()
            Text("↗")
                .font(.dripLabel(12))
                .foregroundStyle(Color.drip.textSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(
            RoundedRectangle(cornerRadius: 12).fill(Color.drip.cardBackground)
        )
        .padding(.top, 16)
    }

    // MARK: Section chrome

    private func sectionHead(_ title: String, trailing: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title.uppercased())
                .font(.dripEyebrow(11))
                .tracking(1.32)
                .foregroundStyle(Color.drip.textSecondary)
            Spacer()
            Text(trailing.uppercased())
                .font(.dripCaption(10))
                .tracking(1)
                .foregroundStyle(Color.drip.textTertiary)
        }
    }
}

// MARK: - Day sheet

/// What one day was. Opened by tapping a cell in the month.
///
/// This reads the payload the Read already holds rather than routing into
/// the workout detail — the Read is a comparison surface, and a sheet that
/// can always be swiped away can never trap the athlete. When this graduates
/// past comparison, the row for a key session is the natural place to push
/// `WorkoutDetail` instead.
struct TrendsReadDaySheet: View {
    let date: String
    let day: TrendsDay?
    let session: KeySession?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(TrendsReadBuilder.label(date).uppercased())
                        .font(.dripEyebrow(11))
                        .tracking(1.32)
                        .foregroundStyle(Color.drip.textSecondary)

                    Text(headline)
                        .font(.dripDisplay(30))
                        .foregroundStyle(Color.drip.textPrimary)
                        .padding(.top, 8)
                        .fixedSize(horizontal: false, vertical: true)

                    if let mood = day?.mood {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(TrendsMoodColor.color(mood))
                                .frame(width: 6, height: 6)
                            Text(mood.uppercased())
                                .font(.dripCaption(10))
                                .tracking(1)
                                .foregroundStyle(Color.drip.textSecondary)
                        }
                        .padding(.top, 12)
                    }

                    if let session {
                        DripEditorialRule().padding(.vertical, 18)
                        row("Zone", KeyZone.label(session.zone))
                        row("Work pace", pace(session.workPaceSec))
                        if let structure = session.structure {
                            row("Structure", structure)
                        }
                        if session.isHeatAdjusted, let adjusted = session.workPaceAdjSec {
                            row("Heat-adjusted", pace(adjusted))
                        }
                    }

                    if let niggles = day?.niggles, !niggles.isEmpty {
                        DripEditorialRule().padding(.vertical, 18)
                        Text("BODY MENTIONS")
                            .font(.dripEyebrow(11))
                            .tracking(1.32)
                            .foregroundStyle(Color.drip.textSecondary)

                        ForEach(niggles) { niggle in
                            VStack(alignment: .leading, spacing: 4) {
                                Text([niggle.side, niggle.area]
                                    .compactMap { $0 }
                                    .joined(separator: " ")
                                    .uppercased())
                                    .font(.dripCaption(10))
                                    .tracking(1)
                                    .foregroundStyle(Color.drip.coral)
                                // The athlete's own words, verbatim.
                                Text("“\(niggle.quote)”")
                                    .font(.dripBody(14))
                                    .italic()
                                    .foregroundStyle(Color.drip.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.top, 12)
                        }

                        Text("Not medical advice. If anything gets sharper, see a clinician.")
                            .font(.dripBody(11.5))
                            .italic()
                            .foregroundStyle(Color.drip.textTertiary)
                            .padding(.top, 16)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
            .background(Color.drip.background)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .toolbarBackground(Color.drip.background, for: .navigationBar)
        }
        .presentationDetents([.medium, .large])
    }

    private var headline: String {
        guard let day, day.miles > 0 else { return "Rest." }
        return "\(String(format: "%.1f", day.miles)) mi."
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label.uppercased())
                .font(.dripCaption(10))
                .tracking(1)
                .foregroundStyle(Color.drip.textSecondary)
            Spacer()
            Text(value)
                .font(.dripStat(14))
                .foregroundStyle(Color.drip.textPrimary)
        }
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.drip.divider).frame(height: 1)
        }
    }

    /// Lowercase units, per the house rules — `5:42 / mi`.
    private func pace(_ seconds: Int) -> String {
        "\(seconds / 60):\(String(format: "%02d", seconds % 60)) / mi"
    }
}

// MARK: - Editorial rule

/// `line · dot · line` — the canonical section break. A typesetting mark,
/// not an `hr`.
struct DripEditorialRule: View {
    var body: some View {
        HStack(spacing: 8) {
            Rectangle().fill(Color.drip.divider).frame(height: 1)
            Circle().fill(Color.drip.textTertiary).frame(width: 3, height: 3)
            Rectangle().fill(Color.drip.divider).frame(height: 1)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Previews

#Preview("The Read") {
    TrendsReadView(
        days: TrendsDay.previewMonthRich,
        keySessions: KeySession.previewLadder
    )
}

#Preview("Thin month") {
    TrendsReadView(days: Array(TrendsDay.previewMonthRich.prefix(3)))
}

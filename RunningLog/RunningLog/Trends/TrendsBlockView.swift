//
//  TrendsBlockView.swift
//  RunningLog · Trends
//
//  THE BLOCK SURFACE — Trends v2, built 2026-08-18 from the approved
//  prototype `trends-simplified-prototype.html`. Reachable from the `v2 ›`
//  door on the legacy header; `TrendsTabView` owns the swap. The old
//  five-signal `TrendsV2View` is untouched and still unlinked.
//
//  WHAT THIS SURFACE IS FOR. The legacy tab answers "how am I trending" with
//  six sections and three stat cards. This one answers a different question —
//  "what did this block amount to" — in five, each with one claim and one
//  chart:
//
//    plate → the block, in position           (weeks in, miles, race countdown)
//    01 · The shape of it                     (weekly load, one 12-week axis)
//    02 · What's actually changed             (threshold minutes + band pace)
//    03 · Where the miles go                  (easy / grey / quality)
//    04 · Best of the block                   (three superlatives, rule-picked)
//    05 · One thing                           (a focus, or nothing)
//
//  THREE RULES THIS SURFACE KEEPS.
//
//    ONE TIME CONTROL. The segmenter owns the window. Every section reads
//    `window`, never `service.weeks`. Same rule the legacy tab learned on
//    2026-08-03, and section 02 obeys it by passing `range.days` into the
//    threshold builder rather than carrying a range of its own.
//
//    ONE AXIS. Sections 01 and 02 draw the same twelve columns at the same
//    geometry, so scrolling from one to the other is the same block through a
//    second lens. `BlockThresholdPoint.weekIndex` is what keeps them aligned;
//    if the load chart's padding changes, change it in `Geometry` and both
//    charts move together.
//
//    NO PROSE THE DATA DOESN'T HOLD. The section captions are fixed templates
//    with computed numbers slotted in — no model, no adjective chosen by data,
//    every clause arithmetic the athlete could do off the chart beneath it.
//    The reasoning, and the guards that omit a sentence rather than hedge it,
//    are in `TrendsBlockModels.swift`. Every caption is optional at this layer:
//    delete the `read` properties and the sections still stand.
//
//  DATA. Everything is a function of what `TrendsService` already loaded, so
//  this surface adds no timeline request. Two small extra awaits, both gated
//  on the surface actually appearing and both cached for the visit:
//  `TrendsAthleteState.fetch()` for the canonical intensity-weighted ACWR (so
//  the chip cannot disagree with the number the legacy tab prints), and
//  `TodayGoal.fetchActive()` for the race countdown. Both degrade to nil —
//  the ratio falls back to the miles-based one, the plate drops the countdown.
//

import SwiftUI

struct TrendsBlockView: View {

    @Environment(\.selectedTab) private var selectedTab

    @State private var service: TrendsService
    @State private var range: TrendsRange = .twelveWeek
    /// Shared store, not view state — section 02 here and section 02 in the
    /// Signal Lab must not disagree about what "in band" means.
    @State private var bandSettings = BandSettingsStore.shared
    @State private var athleteState: TrendsAthleteState?
    @State private var goal: TrendsBlockGoal?
    @State private var didLoadGoal = false
    /// Scrubbed column in section 01. Cleared when the window changes — an
    /// index into a twelve-week array means something else in a twenty-six.
    @State private var selectedWeek: Int?
    /// The week sheet, reusing `TrendsWeekDrill` / `TrendsWeekSheet` rather
    /// than inventing a second week detail. One definition of "a week, opened".
    @State private var weekDrill: TrendsWeekDrill?

    private let autoLoad: Bool
    private let onOpenLegacy: (() -> Void)?
    private let onOpenLab: (() -> Void)?

    /// Chart furniture starts at the `DripTypeFloor` and grows with the
    /// reader's Dynamic Type setting — the drip fonts are fixed-size by
    /// construction, so this has to be opted into per surface.
    @ScaledMetric(relativeTo: .caption2)
    private var microType: CGFloat = DripTypeFloor.eyebrowMicro

    init(
        service: TrendsService = .shared,
        autoLoad: Bool = true,
        onOpenLegacy: (() -> Void)? = nil,
        onOpenLab: (() -> Void)? = nil
    ) {
        _service = State(initialValue: service)
        self.autoLoad = autoLoad
        self.onOpenLegacy = onOpenLegacy
        self.onOpenLab = onOpenLab
    }

    // MARK: Derived

    private var window: [TrendsWeek] {
        Array(service.weeks.suffix(range.rawValue))
    }

    /// Built once per render in `body` and threaded down. The threshold
    /// builder walks every lap in the window and is not free.
    private var thresholdRead: ThresholdRead? {
        if let lab = service.bandLaps {
            return ThresholdBuilder.build(
                lab: lab,
                settings: bandSettings.settings,
                windowDays: range.days
            )
        }
        return service.paceBands.map {
            ThresholdBuilder.build(bands: $0, band: .hm, windowDays: range.days)
        }
    }

    // MARK: Body

    var body: some View {
        let read = TrendsBlockBuilder.build(
            weeks: window,
            days: service.days,
            keySessions: service.keySessions,
            threshold: thresholdRead,
            goal: goal,
            canonicalAcwr: athleteState?.acwr
        )

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                plate(read)
                    .padding(.horizontal, 24)
                    .padding(.top, 16)   // breathing room under the status bar

                if service.failedWithNothingToShow {
                    failure.padding(.horizontal, 24).padding(.top, 40)
                } else if read.isEmpty {
                    empty.padding(.horizontal, 24).padding(.top, 40)
                } else {
                    sections(read).padding(.horizontal, 24)
                }
            }
            .padding(.bottom, 40)
        }
        .background(Color.drip.background)
        // The SAME fetch gate `TrendsLegacyTabView` carries, and for the same
        // reason: every tab in `RunningLogApp` is constructed at launch and
        // merely hidden with `.opacity`, so a plain `.task` here would fire a
        // timeline request for a tab the athlete never opened. Tag 4 is
        // Trends. `refresh()` is a no-op once loaded, so whichever surface the
        // athlete lands on pays for the fetch and the other one rides free.
        .task(id: selectedTab.wrappedValue) { await loadIfNeeded() }
        // An index into a 12-week array points at a different week in a
        // 26-week one, so the scrub cannot survive a window change.
        .onChange(of: range) { _, _ in selectedWeek = nil }
        .sheet(item: $weekDrill) { drill in
            TrendsWeekSheet(drill: drill, service: service)
        }
    }

    /// Opens the tapped column in the week sheet the rest of the tab uses.
    private func openWeek(_ point: BlockWeekPoint) {
        guard !point.weekStartISO.isEmpty else { return }
        weekDrill = TrendsWeekDrill.make(
            weekStartISO: point.weekStartISO,
            label: point.dateLabel,
            days: service.days,
            keySessions: service.keySessions
        )
    }

    // MARK: Loading

    private func loadIfNeeded() async {
        guard autoLoad, selectedTab.wrappedValue == 4 else { return }
        await service.refresh()

        // Two small extras, both optional, both cached for the visit, neither
        // allowed to block the surface: the sections render the moment the
        // timeline lands and simply gain a countdown / swap a ratio after.
        if athleteState == nil {
            athleteState = await TrendsAthleteState.fetch()
        }
        if !didLoadGoal {
            didLoadGoal = true
            if let active = await TodayGoal.fetchActive(), let date = active.raceDate {
                goal = TrendsBlockGoal(raceDate: date, distanceLabel: active.distanceLabel)
            }
        }
    }

    // MARK: Plate

    private func plate(_ read: TrendsBlockRead) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Text(plateKicker(read).uppercased())
                    .font(.dripEyebrow(11))
                    .tracking(1.3)
                    .foregroundStyle(Color.drip.coral)
                Spacer(minLength: 8)
                if let onOpenLab { doorChip("lab ›", action: onOpenLab) }
                if let onOpenLegacy { doorChip("v1 ›", action: onOpenLegacy) }
            }
            .padding(.bottom, 14)

            Text(plateTitle(read))
                .font(.dripDisplay(36))
                .foregroundStyle(Color.drip.textPrimary)
                .lineSpacing(0)
                .fixedSize(horizontal: false, vertical: true)

            if let sub = plateSub(read) {
                Text(sub)
                    .font(.dripBody(15))
                    .foregroundStyle(Color.drip.textSecondary)
                    .lineSpacing(3)
                    .padding(.top, 10)
                    .fixedSize(horizontal: false, vertical: true)
            }

            segmenter.padding(.top, 20)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func plateKicker(_ read: TrendsBlockRead) -> String {
        guard let goal = read.goal else { return "Trends · the block" }
        return "Trends · \(goal.distanceLabel) block"
    }

    private func plateTitle(_ read: TrendsBlockRead) -> String {
        let n = read.weekCount
        guard n > 0 else { return "Nothing\nlogged yet." }
        return "\(TrendsBlockFormat.spelled(n).capitalized)\nweeks in."
    }

    /// Miles and key sessions always; the countdown only when a race is set.
    private func plateSub(_ read: TrendsBlockRead) -> String? {
        guard !read.isEmpty else { return nil }
        let miles = Int(read.load.totalMiles.rounded())
        guard miles > 0 else { return nil }
        var line = "\(miles) miles behind you."
        let keys = read.load.keySessionCount
        if keys > 0 { line += " \(keys) key session\(keys == 1 ? "" : "s")." }
        if let goal = read.goal {
            let out = goal.weeksOut()
            if out > 0 {
                line += "\n\(TrendsBlockFormat.spelled(out).capitalized) week\(out == 1 ? "" : "s") until the line."
            } else {
                line += "\nRace week."
            }
        }
        return line
    }

    private var segmenter: some View {
        HStack(spacing: 2) {
            ForEach(TrendsRange.allCases) { r in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { range = r }
                } label: {
                    Text(r.label.uppercased())
                        .font(.dripEyebrow(10))
                        .tracking(0.8)
                        .foregroundStyle(range == r ? Color.drip.textPrimary : Color.drip.textSecondary)
                        .fontWeight(range == r ? .semibold : .regular)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(range == r ? Color.drip.cardBackground : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color.drip.paperDeep)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: Sections

    @ViewBuilder
    private func sections(_ read: TrendsBlockRead) -> some View {
        VStack(alignment: .leading, spacing: 0) {

            // 01 · load
            rule
            section(number: "01", title: "The shape of it", read: read.load.read) {
                VStack(alignment: .leading, spacing: 0) {
                    card {
                        VStack(alignment: .leading, spacing: 0) {
                            BlockLoadChart(load: read.load,
                                           microType: microType,
                                           selection: $selectedWeek)
                            weekReadout(read.load)
                        }
                    }
                    footStats([
                        ("This week",
                         read.load.isWeekComplete
                            ? "\(Int(read.load.currentMiles.rounded()))"
                            : "\(Int(read.load.currentMiles.rounded())) → \(Int(read.load.projectedMiles.rounded()))",
                         true),
                        ("4-wk avg", "\(Int(read.load.fourWeekAvg.rounded()))", false),
                        ("Peak", "\(Int(read.load.peakMiles.rounded()))", false)
                    ])
                    balanceChip(read.load)
                }
            }

            // 02 · threshold
            if !read.threshold.isEmpty {
                rule
                section(number: "02", title: "What's actually changed", read: read.threshold.read) {
                    VStack(alignment: .leading, spacing: 0) {
                        card { BlockThresholdChart(band: read.threshold, microType: microType) }
                        footStats([
                            ("Minutes in band",
                             read.threshold.minutesChangePct.map { "\($0 > 0 ? "+" : "")\($0)%" } ?? "—",
                             false),
                            ("Band pace",
                             read.threshold.paceDeltaSec.map { "\($0 > 0 ? "+" : "")\($0) s/mi" } ?? "—",
                             false),
                            ("Anchor", read.threshold.anchorLabel, false)
                        ])
                    }
                }
            }

            // 03 · mix
            if !read.mix.isEmpty {
                rule
                section(number: "03", title: "Where the miles go", read: read.mix.read) {
                    card { BlockMixBar(mix: read.mix, microType: microType) }
                }
            }

            // 04 · moments
            if !read.moments.isEmpty {
                rule
                section(number: "04", title: "Best of the block", read: nil) {
                    VStack(spacing: 0) {
                        ForEach(Array(read.moments.enumerated()), id: \.element.id) { i, m in
                            momentRow(m, isLast: i == read.moments.count - 1)
                        }
                    }
                }
            }

            // 05 · one thing
            if let focus = read.focus {
                rule
                VStack(alignment: .leading, spacing: 0) {
                    focusCard(focus)
                }
                .padding(.vertical, 24)
            }
        }
    }

    private var rule: some View {
        HStack(spacing: 8) {
            Rectangle().fill(Color.drip.divider).frame(height: 1)
            Circle().fill(Color.drip.divider).frame(width: 3, height: 3)
            Rectangle().fill(Color.drip.divider).frame(height: 1)
        }
    }

    @ViewBuilder
    private func section<Content: View>(
        number: String,
        title: String,
        read: String?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(number)
                    .font(.dripEyebrow(11))
                    .tracking(0.9)
                    .foregroundStyle(Color.drip.coral)
                Text(title)
                    .font(.dripDisplay(21))
                    .foregroundStyle(Color.drip.textPrimary)
            }
            if let read {
                Text(read)
                    .font(.dripBody(15))
                    .foregroundStyle(Color.drip.textPrimary)
                    .lineSpacing(3)
                    .padding(.top, 8)
                    .fixedSize(horizontal: false, vertical: true)
            }
            content().padding(.top, 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 24)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
            .background(Color.drip.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.drip.divider, lineWidth: 1)
            )
    }

    private func footStats(_ items: [(String, String, Bool)]) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.0.uppercased())
                        .font(.dripEyebrow(max(9, microType - 1)))
                        .tracking(0.8)
                        .foregroundStyle(Color.drip.textTertiary)
                    Text(item.1)
                        .font(.dripStat(15))
                        .foregroundStyle(item.2 ? Color.drip.coral : Color.drip.textPrimary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.top, 12)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.drip.divider).frame(height: 1)
        }
        .padding(.top, 12)
    }

    /// The scrub readout, inside the chart card and under a hairline.
    ///
    /// Always occupies its row — an empty state that collapses would make the
    /// whole section jump every time a finger lands on the chart. Before a
    /// column is picked it says how to pick one.
    @ViewBuilder
    private func weekReadout(_ load: BlockLoad) -> some View {
        let point: BlockWeekPoint? = selectedWeek.flatMap {
            load.points.indices.contains($0) ? load.points[$0] : nil
        }
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.drip.divider)
                .frame(height: 1)
                .padding(.top, 12)

            if let p = point {
                Button { openWeek(p) } label: {
                    HStack(alignment: .center, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text((p.isCurrent ? "\(p.dateLabel) · this week" : "Week of \(p.dateLabel)").uppercased())
                                .font(.dripEyebrow(max(9, microType - 1)))
                                .tracking(1.0)
                                .foregroundStyle(p.isCurrent ? Color.drip.coral : Color.drip.textTertiary)
                            HStack(spacing: 14) {
                                readoutStat("\(Int(p.miles.rounded()))", "mi")
                                readoutStat("\(Int(p.drawableQuality.rounded()))", "quality")
                                readoutStat("\(p.keyCount)", p.keyCount == 1 ? "key session" : "key sessions")
                            }
                        }
                        Spacer(minLength: 4)
                        if !p.weekStartISO.isEmpty {
                            Text("open ›")
                                .font(.dripCaption(11))
                                .foregroundStyle(Color.drip.textTertiary)
                        }
                    }
                    .padding(.top, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(p.weekStartISO.isEmpty)
            } else {
                HStack {
                    Text("Tap a week to read it.")
                        .font(.dripBody(12.5))
                        .italic()
                        .foregroundStyle(Color.drip.textTertiary)
                    Spacer(minLength: 0)
                }
                .padding(.top, 11)
                .frame(minHeight: 34, alignment: .leading)
            }
        }
    }

    private func readoutStat(_ value: String, _ unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(value)
                .font(.dripStat(15))
                .foregroundStyle(Color.drip.textPrimary)
            Text(unit)
                .font(.dripEyebrow(max(9, microType - 1)))
                .foregroundStyle(Color.drip.textTertiary)
        }
    }

    private func balanceChip(_ load: BlockLoad) -> some View {
        HStack(spacing: 7) {
            Text(load.balance.label.uppercased())
                .font(.dripEyebrow(max(9, microType - 1)))
                .tracking(1.0)
                .fontWeight(.semibold)
                .foregroundStyle(Color.drip.coralDeep)
            Text(String(format: "acute : chronic %.2f", load.acwr))
                .font(.dripEyebrow(max(9, microType - 1)))
                .tracking(0.4)
                .foregroundStyle(Color.drip.textSecondary)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 5)
        .background(Color.drip.coralWash)
        .clipShape(Capsule())
        .padding(.top, 14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Load balance \(load.balance.label), acute to chronic ratio \(String(format: "%.2f", load.acwr))")
    }

    private func momentRow(_ m: BlockMoment, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(m.kicker.uppercased())
                    .font(.dripEyebrow(max(9, microType - 1)))
                    .tracking(1.0)
                    .foregroundStyle(Color.drip.textTertiary)
                Text(m.value)
                    .font(.dripDisplay(17))
                    .foregroundStyle(Color.drip.textPrimary)
                if let note = m.note {
                    Text(note)
                        .font(.dripBody(12.5))
                        .italic()
                        .foregroundStyle(Color.drip.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            Text(m.dateLabel.uppercased())
                .font(.dripEyebrow(max(9, microType - 1)))
                .tracking(0.8)
                .foregroundStyle(Color.drip.textTertiary)
        }
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle().fill(Color.drip.divider).frame(height: 1)
            }
        }
    }

    private func focusCard(_ focus: BlockFocus) -> some View {
        HStack(spacing: 0) {
            Rectangle().fill(Color.drip.coral).frame(width: 2)
            VStack(alignment: .leading, spacing: 8) {
                Text("One thing".uppercased())
                    .font(.dripEyebrow(max(9, microType - 1)))
                    .tracking(1.4)
                    .foregroundStyle(Color.drip.coral)
                Text(focus.title)
                    .font(.dripDisplay(19))
                    .foregroundStyle(Color.drip.textPrimary)
                Text(focus.body)
                    .font(.dripBody(15))
                    .foregroundStyle(Color.drip.textPrimary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
            Spacer(minLength: 0)
        }
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.drip.divider, lineWidth: 1)
        )
    }

    // MARK: States

    private var empty: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No weeks in this window.")
                .font(.dripDisplay(20))
                .foregroundStyle(Color.drip.textPrimary)
            Text("Log a run and the block starts building here.")
                .font(.dripBody(14))
                .foregroundStyle(Color.drip.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var failure: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Couldn't load your timeline.")
                .font(.dripDisplay(20))
                .foregroundStyle(Color.drip.textPrimary)
            Text("Pull to try again.")
                .font(.dripBody(14))
                .foregroundStyle(Color.drip.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func doorChip(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.dripCaption(9))
                .foregroundStyle(Color.drip.textTertiary)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .overlay(Capsule().stroke(Color.drip.divider, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Shared chart geometry

/// Sections 01 and 02 draw the same columns at the same x positions. Both read
/// their geometry from here so the two charts stay readable straight down; a
/// change to padding or bar inset moves both at once.
enum BlockChartGeometry {
    static let padLeading: CGFloat = 30
    static let padTrailing: CGFloat = 10

    static func columnWidth(_ width: CGFloat, count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        return (width - padLeading - padTrailing) / CGFloat(count)
    }

    /// The gap is a FRACTION of the column, not a constant (2026-08-18).
    ///
    /// A fixed 9pt gutter is a third of the column at twelve weeks and most of
    /// it at twenty-six, which is how 6 MO came out as hairlines. A third of
    /// the column keeps the bar the dominant mark at every range, and the 9pt
    /// ceiling keeps 4 WK from drawing four slabs with no air between them.
    static func gap(forColumn cw: CGFloat) -> CGFloat {
        Swift.min(9, Swift.max(1.5, cw * 0.32))
    }

    /// Bars are capped at `maxBarWidth` and centred in their column. Without
    /// the cap, 4 WK draws four 60pt slabs and the current week's projection
    /// ghost becomes a large empty box — a bar chart of four weeks should
    /// still look like a bar chart.
    static let maxBarWidth: CGFloat = 44

    static func barRect(_ width: CGFloat, count: Int, index: Int) -> (x: CGFloat, w: CGFloat) {
        let cw = columnWidth(width, count: count)
        let g = gap(forColumn: cw)
        let bw = Swift.min(Swift.max(2, cw - g), maxBarWidth)
        return (padLeading + CGFloat(index) * cw + (cw - bw) / 2, bw)
    }

    /// Which column a touch at `x` lands in, clamped to the chart.
    static func index(at x: CGFloat, width: CGFloat, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let cw = columnWidth(width, count: count)
        guard cw > 0 else { return 0 }
        let raw = Int(((x - padLeading) / cw).rounded(.down))
        return Swift.min(Swift.max(0, raw), count - 1)
    }
}

// MARK: - 01 · load chart

/// Twelve to twenty-six weeks of miles, with the three numbers the old stat
/// cards carried read straight off the bars: the current week in coral with its
/// projection ghosted above it, the four-week average as a dashed rule, the
/// peak labelled where it happened.
///
/// KEY WORK IS IN THE BAR, not under it. A row of key-session dots was the
/// first build; at 6 MO it became a grey smear along the axis, because every
/// week has one or two and twenty-six columns of "one or two" is a texture, not
/// a signal. Quality miles stack on TOP of each bar instead — the sharp end up,
/// the same convention `TrendsMoodLanes.zoneStack` uses — so the mark scales
/// with the column, says how MUCH rather than how many, and reads at any range.
///
/// The chart is scrubbable and every column is a door: drag to read a week,
/// tap the readout to open it. Selection is owned by the parent so the readout
/// row and the sheet can both see it.
private struct BlockLoadChart: View {
    let load: BlockLoad
    let microType: CGFloat
    @Binding var selection: Int?

    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in draw(ctx, size) }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let i = BlockChartGeometry.index(
                                at: value.location.x,
                                width: geo.size.width,
                                count: load.points.count
                            )
                            if selection != i { selection = i }
                        }
                )
        }
        .frame(height: 164)
        .sensoryFeedback(.selection, trigger: selection)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Weekly miles across \(load.points.count) weeks")
        .accessibilityValue(load.read ?? "")
        // One VoiceOver child per column, so the chart is walkable along the
        // time axis instead of being one opaque element.
        .accessibilityChildren {
            HStack(spacing: 0) {
                ForEach(load.points) { p in
                    Color.clear.accessibilityLabel(
                        "\(p.dateLabel): \(Int(p.miles.rounded())) miles, "
                        + "\(Int(p.drawableQuality.rounded())) quality, "
                        + "\(p.keyCount) key session\(p.keyCount == 1 ? "" : "s")"
                    )
                }
            }
        }
    }

    private func draw(_ ctx: GraphicsContext, _ size: CGSize) {
        let pts = load.points
        guard !pts.isEmpty else { return }
        let w = size.width, h = size.height
        let top: CGFloat = 16
        // Room for two stacked rows under the plot: month ticks, then the
        // legend. At 30 they touched at the left edge, where the first month
        // tick and the quality swatch both start.
        let axisH: CGFloat = 36
        let plotH = h - top - axisH
        let maxMiles = max(load.peakMiles, load.projectedMiles, 1) * 1.14
        func y(_ v: Double) -> CGFloat { top + plotH - CGFloat(v / maxMiles) * plotH }
        let baseline = top + plotH

        // gridlines
        for v in gridSteps(max: maxMiles) {
            var line = Path()
            line.move(to: CGPoint(x: BlockChartGeometry.padLeading, y: y(v)))
            line.addLine(to: CGPoint(x: w - BlockChartGeometry.padTrailing, y: y(v)))
            ctx.stroke(line, with: .color(Color.drip.divider.opacity(0.7)), lineWidth: 1)
            ctx.draw(
                label("\(Int(v))", size: microType - 1, color: Color.drip.textTertiary.opacity(0.7)),
                at: CGPoint(x: BlockChartGeometry.padLeading - 6, y: y(v)),
                anchor: .trailing
            )
        }

        // selection column, drawn UNDER the bars so it never dims the mark
        if let sel = selection, pts.indices.contains(sel) {
            let cw = BlockChartGeometry.columnWidth(w, count: pts.count)
            let x = BlockChartGeometry.padLeading + CGFloat(sel) * cw
            ctx.fill(
                Path(roundedRect: CGRect(x: x, y: top - 6, width: cw, height: plotH + 12),
                     cornerRadius: 3),
                with: .color(Color.drip.paperDeep.opacity(0.9))
            )
        }

        // bars — total, then quality stacked on top
        for (i, p) in pts.enumerated() {
            let (x, bw) = BlockChartGeometry.barRect(w, count: pts.count, index: i)
            guard p.miles > 0 || p.isCurrent else { continue }

            let bodyFill = p.isCurrent
                ? Color.drip.coral
                : Color.drip.textTertiary.opacity(0.42)
            let sharpFill = p.isCurrent
                ? Color.drip.coralDeep
                : Color.drip.textSecondary.opacity(0.9)

            if p.isCurrent, load.projectedMiles > p.miles {
                let ghost = CGRect(x: x, y: y(load.projectedMiles),
                                   width: bw, height: y(p.miles) - y(load.projectedMiles))
                let path = Path(roundedRect: ghost, cornerRadius: 2)
                ctx.fill(path, with: .color(Color.drip.coralWash))
                ctx.stroke(path, with: .color(Color.drip.coral),
                           style: StrokeStyle(lineWidth: 1, dash: [2.5, 2]))
            }

            if p.miles > 0 {
                let bar = CGRect(x: x, y: y(p.miles), width: bw, height: baseline - y(p.miles))
                ctx.fill(Path(roundedRect: bar, cornerRadius: 2), with: .color(bodyFill))

                // The sharp end. Never taller than the bar it sits in, and
                // floored at 2pt so a real quality week is visible even when
                // it is a small share of a big one.
                let q = p.drawableQuality
                if q > 0 {
                    let qh = max(2, baseline - y(q))
                    let qRect = CGRect(x: x, y: y(p.miles), width: bw,
                                       height: min(qh, baseline - y(p.miles)))
                    ctx.fill(Path(roundedRect: qRect, cornerRadius: 2), with: .color(sharpFill))
                }
            }
        }

        // four-week average. Labelled BELOW the line at the right edge: above
        // it collides with the peak marker whenever the peak is recent, which
        // for a block in its taper is most of the time.
        if load.fourWeekAvg > 0 {
            var avg = Path()
            avg.move(to: CGPoint(x: BlockChartGeometry.padLeading, y: y(load.fourWeekAvg)))
            avg.addLine(to: CGPoint(x: w - BlockChartGeometry.padTrailing, y: y(load.fourWeekAvg)))
            ctx.stroke(avg, with: .color(Color.drip.textSecondary),
                       style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            // Labelled at the LEFT end, below the line. The right end is where
            // the current week and its projection ghost live, and the space
            // above the line belongs to the peak marker — so neither end of
            // the top edge is free. Early weeks in a block sit below the
            // four-week average often enough that below-left is the one
            // reliably empty corner.
            ctx.draw(
                label("4-WK AVG \(Int(load.fourWeekAvg.rounded()))",
                      size: microType - 1, color: Color.drip.textSecondary),
                at: CGPoint(x: BlockChartGeometry.padLeading + 2,
                            y: y(load.fourWeekAvg) + 3),
                anchor: .topLeading
            )
        }

        // peak marker
        if let pi = load.peakIndex, load.peakMiles > 0, pts.indices.contains(pi) {
            let (x, bw) = BlockChartGeometry.barRect(w, count: pts.count, index: pi)
            ctx.draw(
                label("PEAK \(Int(load.peakMiles.rounded()))",
                      size: microType - 0.5, color: Color.drip.textPrimary, weight: .semibold),
                at: CGPoint(x: min(max(x + bw / 2, 34), w - 30), y: y(load.peakMiles) - 6),
                anchor: .bottom
            )
        }

        // month ticks, with collision avoidance — at 6 MO the naive version
        // printed FEB over MAR.
        var lastTickX: CGFloat = -.greatestFiniteMagnitude
        let tickPitch = (microType + 1) * 3.4
        for (i, p) in pts.enumerated() {
            guard let tick = p.monthTick else { continue }
            let (x, _) = BlockChartGeometry.barRect(w, count: pts.count, index: i)
            guard x - lastTickX >= tickPitch, x < w - 24 else { continue }
            lastTickX = x
            ctx.draw(label(tick, size: microType - 0.5, color: Color.drip.textTertiary),
                     at: CGPoint(x: x, y: baseline + 8), anchor: .topLeading)
        }

        // legend
        if load.totalQualityMiles > 0 {
            let sw = CGRect(x: BlockChartGeometry.padLeading, y: h - microType - 3,
                            width: 7, height: 7)
            ctx.fill(Path(roundedRect: sw, cornerRadius: 1),
                     with: .color(Color.drip.textSecondary.opacity(0.9)))
            ctx.draw(label("QUALITY MILES", size: microType - 1.5,
                           color: Color.drip.textTertiary),
                     at: CGPoint(x: sw.maxX + 5, y: sw.midY), anchor: .leading)
        }
        ctx.draw(label("MILES / WEEK", size: microType - 1.5,
                       color: Color.drip.textTertiary),
                 at: CGPoint(x: w - BlockChartGeometry.padTrailing, y: h - 3),
                 anchor: .bottomTrailing)
    }

    /// Two or three round gridlines under the max, never more.
    private func gridSteps(max: Double) -> [Double] {
        let candidates: [Double] = [10, 20, 25, 50, 75, 100, 125]
        return candidates.filter { $0 < max * 0.95 }.suffix(3).map { $0 }
    }
}

// MARK: - 02 · threshold chart

/// Two lanes on one axis: band pace on top (faster is higher), minutes in band
/// beneath. Two lanes rather than two scales in one plot — overlaid, the line
/// reads as part of the bars and neither series is legible.
private struct BlockThresholdChart: View {
    let band: BlockThreshold
    let microType: CGFloat

    var body: some View {
        Canvas { ctx, size in draw(ctx, size) }
            .frame(height: 196)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Threshold minutes and band pace across the window")
            .accessibilityValue(band.read ?? "")
    }

    private func draw(_ ctx: GraphicsContext, _ size: CGSize) {
        let pts = band.points
        guard pts.count >= 2, band.weekCount > 0 else { return }
        let w = size.width
        let count = band.weekCount

        func x(_ p: BlockThresholdPoint) -> CGFloat {
            let idx = p.weekIndex >= 0 ? p.weekIndex : 0
            let (bx, bw) = BlockChartGeometry.barRect(w, count: count, index: min(idx, count - 1))
            return bx + bw / 2
        }

        // ── lane A · band pace ──────────────────────────────────────────
        let aTop: CGFloat = 16, aH: CGFloat = 52
        let paces = pts.map { Double($0.adjSec) }
        let lo = (paces.min() ?? 0) - 3, hi = (paces.max() ?? 1) + 3
        let spread = Swift.max(hi - lo, 1)
        func yp(_ sec: Int) -> CGFloat {
            aTop + CGFloat((Double(sec) - lo) / spread) * aH
        }

        for edge in [aTop - 4, aTop + aH + 4] {
            var l = Path()
            l.move(to: CGPoint(x: BlockChartGeometry.padLeading, y: edge))
            l.addLine(to: CGPoint(x: w - BlockChartGeometry.padTrailing, y: edge))
            ctx.stroke(l, with: .color(Color.drip.divider.opacity(0.7)), lineWidth: 1)
        }
        ctx.draw(label("FAST", size: microType - 1.5, color: Color.drip.textTertiary.opacity(0.8)),
                 at: CGPoint(x: BlockChartGeometry.padLeading - 7, y: aTop), anchor: .trailing)
        ctx.draw(label("SLOW", size: microType - 1.5, color: Color.drip.textTertiary.opacity(0.8)),
                 at: CGPoint(x: BlockChartGeometry.padLeading - 7, y: aTop + aH), anchor: .trailing)
        ctx.draw(label("BAND PACE, HEAT-ADJUSTED", size: microType - 1.5,
                       color: Color.drip.textTertiary),
                 at: CGPoint(x: BlockChartGeometry.padLeading, y: aTop - 9), anchor: .bottomLeading)

        var line = Path()
        for (i, p) in pts.enumerated() {
            let pt = CGPoint(x: x(p), y: yp(p.adjSec))
            if i == 0 { line.move(to: pt) } else { line.addLine(to: pt) }
        }
        ctx.stroke(line, with: .color(Color.drip.coral),
                   style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
        for p in pts {
            let c = CGPoint(x: x(p), y: yp(p.adjSec))
            let r: CGFloat = 2.6
            let dot = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            ctx.fill(dot, with: .color(Color.drip.cardBackground))
            ctx.stroke(dot, with: .color(Color.drip.coral), lineWidth: 1.6)
        }
        // Endpoint paces, the two numbers the caption quotes.
        if let a = pts.first {
            ctx.draw(label(TrendsBlockFormat.pace(a.adjSec), size: microType,
                           color: Color.drip.coral, weight: .semibold),
                     at: CGPoint(x: x(a) + 7, y: yp(a.adjSec) + 10), anchor: .leading)
        }
        if let b = pts.last {
            ctx.draw(label(TrendsBlockFormat.pace(b.adjSec), size: microType,
                           color: Color.drip.coral, weight: .semibold),
                     at: CGPoint(x: x(b), y: yp(b.adjSec) - 7), anchor: .bottom)
        }

        // ── lane B · minutes in band ────────────────────────────────────
        let bTop = aTop + aH + 27, bH: CGFloat = 62
        let maxMin = Swift.max(pts.map(\.minutes).max() ?? 1, 1) * 1.15
        func ym(_ v: Double) -> CGFloat { bTop + bH - CGFloat(v / maxMin) * bH }

        for v in [maxMin / 2, maxMin * 0.9].map({ (($0 / 10).rounded() * 10) }) where v > 0 {
            var l = Path()
            l.move(to: CGPoint(x: BlockChartGeometry.padLeading, y: ym(v)))
            l.addLine(to: CGPoint(x: w - BlockChartGeometry.padTrailing, y: ym(v)))
            ctx.stroke(l, with: .color(Color.drip.divider.opacity(0.7)), lineWidth: 1)
            ctx.draw(label("\(Int(v))", size: microType - 1,
                           color: Color.drip.textTertiary.opacity(0.7)),
                     at: CGPoint(x: BlockChartGeometry.padLeading - 7, y: ym(v)), anchor: .trailing)
        }

        for p in pts {
            let idx = p.weekIndex >= 0 ? Swift.min(p.weekIndex, count - 1) : 0
            let (bx, bw) = BlockChartGeometry.barRect(w, count: count, index: idx)
            let bar = CGRect(x: bx, y: ym(p.minutes), width: bw, height: bTop + bH - ym(p.minutes))
            ctx.fill(Path(roundedRect: bar, cornerRadius: 2),
                     with: .color(Color.drip.textTertiary.opacity(0.45)))
        }

        ctx.draw(label("MINUTES IN BAND", size: microType - 1.5, color: Color.drip.textTertiary),
                 at: CGPoint(x: BlockChartGeometry.padLeading, y: bTop - 6), anchor: .bottomLeading)
    }
}

// MARK: - 03 · mix bar

/// One bar, three bands. The ten-zone histogram is a shape you study; this is
/// a shape you read, and it puts the grey zone next to the number that makes
/// it a finding.
private struct BlockMixBar: View {
    let mix: BlockMix
    let microType: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    segment(width: geo.size.width * frac(mix.easyMiles),
                            title: "EASY", pct: mix.easyPct,
                            fill: Color.drip.textTertiary.opacity(0.45), dark: false)
                    segment(width: geo.size.width * frac(mix.greyMiles),
                            title: "STEADY", pct: mix.greyPct,
                            fill: Color.drip.textSecondary.opacity(0.75), dark: true)
                    segment(width: geo.size.width * frac(mix.qualityMiles),
                            title: "QUALITY", pct: mix.qualityPct,
                            fill: Color.drip.coral, dark: true)
                }
            }
            .frame(height: 38)

            HStack(spacing: 14) {
                legendDot(Color.drip.textTertiary.opacity(0.45), "Easy \(mix.easyPct)%")
                legendDot(Color.drip.textSecondary.opacity(0.75), "Steady \(mix.greyPct)%")
                legendDot(Color.drip.coral, "Quality \(mix.qualityPct)%")
            }

            Text(footnote)
                .font(.dripEyebrow(max(9, microType - 1)))
                .tracking(0.5)
                .foregroundStyle(Color.drip.textTertiary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Mile mix: \(mix.easyPct) percent easy, \(mix.greyPct) percent steady, \(mix.qualityPct) percent quality")
    }

    private var footnote: String {
        let classified = Int(mix.classifiedMiles.rounded())
        let unknown = Int(mix.unclassifiedMiles.rounded())
        guard unknown > 0 else { return "\(classified) classified miles" }
        return "\(classified) classified · \(unknown) mi without lap data"
    }

    private func frac(_ miles: Double) -> CGFloat {
        guard mix.classifiedMiles > 0 else { return 0 }
        return CGFloat(miles / mix.classifiedMiles)
    }

    @ViewBuilder
    private func segment(width: CGFloat, title: String, pct: Int,
                         fill: Color, dark: Bool) -> some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2).fill(fill)
            if width > 58 {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.dripEyebrow(max(9, microType - 1)))
                        .tracking(1.0)
                        .fontWeight(.semibold)
                        .foregroundStyle(dark ? Color.white : Color.drip.textSecondary)
                    Text("\(pct)%")
                        .font(.dripStat(11))
                        .foregroundStyle(dark ? Color.white.opacity(0.8) : Color.drip.textTertiary)
                }
                .padding(.leading, 9)
            }
        }
        .frame(width: max(0, width))
    }

    private func legendDot(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 1).fill(color).frame(width: 8, height: 8)
            Text(text)
                .font(.dripEyebrow(max(9, microType - 1)))
                .tracking(0.4)
                .foregroundStyle(Color.drip.textSecondary)
        }
    }
}

// MARK: - Canvas text helper

/// Canvas draws resolved `Text`. One helper so every label on this surface
/// shares a face and the Dynamic Type size threaded down from the view.
private func label(_ s: String, size: CGFloat, color: Color,
                   weight: Font.Weight = .regular) -> Text {
    Text(s)
        .font(.dripEyebrow(Swift.max(8, size)).weight(weight))
        .foregroundColor(color)
}

// MARK: - Previews

#Preview("Trends · block") {
    NavigationStack {
        TrendsBlockView(
            service: TrendsService(
                preview: TrendsSampleData.weeks,
                days: TrendsDay.previewMonthRich,
                keySessions: KeySession.previewLadder
            ),
            autoLoad: false,
            onOpenLegacy: {},
            onOpenLab: {}
        )
    }
}

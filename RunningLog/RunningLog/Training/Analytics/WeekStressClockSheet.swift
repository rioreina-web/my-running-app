//
//  WeekStressClockSheet.swift
//  RunningLog
//
//  The week's training stress, full screen and LANDSCAPE. Days stay ACROSS —
//  the same picture as `WeekStressStripSection`, given the whole phone turned
//  sideways. The rotation is requested, not suggested: seven days across a
//  portrait phone is the compressed strip the athlete just tapped away from,
//  so opening this in portrait would make the expand button a lie.
//
//  THE ENCODING. X is the seven days, each one a FULL 24 HOURS; a bar sits at
//  the hour its run started, so a 7am session and a 6pm easy run land at
//  opposite ends of the same band and can never be mistaken for one effort. Y
//  is the training stress score, on a real axis with a real scale — which is
//  the thing the collapsed strip cannot give you, because seven days across a
//  phone leaves no room for gridlines or labels. Height is therefore readable
//  here rather than merely comparable.
//
//  WHAT COUNTS AS ONE BAR is not "one upload". It is `TrendsDay.sessions(from:)`,
//  the same fold the strip uses: uploads inside the session gap become one run,
//  so warm-up + reps + cool-down is a single bar labelled "3 uploads, one run",
//  while two runs hours apart stay two. The two surfaces must never disagree
//  about what a run is.
//
//  KEEPING IT FROM READING AS A JUMBLE was the hard part, and three things do
//  the work: alternating day bands, so seven 24-hour windows are visibly seven
//  and a bar is unambiguously inside one of them; horizontal gridlines, which
//  give the eye a rule to follow across the whole week instead of comparing
//  free-floating heights; and a fixed bar width, so nothing changes size as the
//  athlete pages between weeks. Hour ticks INSIDE a band are still refused —
//  they invite measuring a position the encoding does not support. The hairline
//  states the clock time in the panel instead, where it is read, not estimated.
//
//  WHAT THE EXTRA WIDTH BUYS, AND WHAT IT DOESN'T. A day slot goes from ~48pt
//  to ~114pt and the plot roughly doubles in height, so bars separate, doubles
//  stop touching, and small differences in load become visible. What it does
//  NOT buy is proportional width: at 114pt a 76-minute run is 6pt, so width
//  still cannot be duration and height still carries the magnitude. The strip's
//  encoding survives the resize intact, which is the point — this is the same
//  chart, not a second one that has to be learned.
//
//  WHY THERE ARE STILL NO HOUR GRIDLINES. The strip refuses them because
//  ticks at 6/12/18 invite measuring off a slot the encoding cannot support,
//  and that is as true at 114pt as at 48. Precision arrives a different way
//  here: the hairline. Point at a run and it states the clock time, in words,
//  in the panel — read rather than estimated. That is the same contract the
//  strip's run panel makes, so nothing about how position works changes.
//
//  SCRUB IS ONE-DIMENSIONAL, ON PURPOSE. X alone decides everything: which
//  seventh of the week the finger is in, and where inside that day. So a
//  single left-to-right drag walks the week in chronological order, Monday
//  midnight to Sunday midnight, and Y is free — the athlete does not have to
//  keep their finger on a 12pt bar to hold a reading. The panel stays put when
//  the finger lifts, because a run someone stopped on is a run they want to
//  keep reading.
//
//  Data comes in already built. `WeekStressStripSection.model()` is the one
//  place a week is assembled from `TrendsService.days` and the view model's
//  scaffolding, and it stays that way — this sheet renders a `StripWeek`, it
//  never derives one. Two builders would be two definitions of a week and they
//  would drift inside a month.
//

import os
import SwiftUI
import UIKit

struct WeekStressClockSheet: View {

    typealias Run    = WeekStressStripSection.StressRun
    typealias Week   = WeekStressStripSection.StripWeek
    typealias Day    = WeekStressStripSection.StripDay
    typealias Metric = WeekStressStripSection.StripMetric

    /// The week the athlete expanded FROM. Held so the first frame draws
    /// without rebuilding a week the strip has already built.
    let initialWeek: Week
    /// That week's `weeksAgo` offset — the origin the sheet's own nav pages
    /// away from.
    let weekOffset: Int
    /// ANY week, built on demand by the strip's own `model(weeksAgo:)`. A
    /// closure rather than a second `Week` value so the athlete can page the
    /// comparison anywhere without the sheet ever assembling a week itself —
    /// one builder, one definition of a week.
    let weekAt: (Int) -> Week
    /// That week's range label, from the same formatter the strip's head uses.
    let labelAt: (Int) -> String
    let metric: Metric
    var onOpenDay: (Date) -> Void

    @Environment(\.dismiss) private var dismiss

    /// How far the sheet's own week nav has moved from where it opened. Held
    /// as a DELTA rather than an absolute so the origin stays whatever the
    /// strip was showing, and so no `init` is needed to seed `@State`.
    @State private var offsetDelta = 0

    /// Overlay each run's heart-rate trace. Off by default — it is a second
    /// reading of the same runs and earns its ink only when asked for.
    @State private var showingHR = false
    @State private var hrTraces = RunHRTraceService.shared

    /// Weeks the nav has paged to, and the compare week — both CACHED.
    ///
    /// `weekAt` is not a lookup, it is `model(weeksAgo:)`: it re-scaffolds the
    /// days, rebuilds a dictionary over every `TrendsDay`, runs a shared
    /// `DateFormatter` seven times and re-folds every day's sessions. Calling
    /// it from a computed property meant every `week.days` and every
    /// `height()` — dozens per body pass, on every frame of the week-nav
    /// animation — paid for a full rebuild. Built once when the offset
    /// changes instead.
    @State private var pagedWeek: Week?
    @State private var comparisonWeek: Week?

    /// The week actually on screen. Offset zero is the week the strip already
    /// built, so the common case costs nothing at all.
    private var viewOffset: Int { weekOffset + offsetDelta }
    private var week: Week { offsetDelta == 0 ? initialWeek : (pagedWeek ?? initialWeek) }

    /// The tapped run, or nil. Nil on open: the sheet shows the whole week
    /// first, not a run nobody chose.
    @State private var selected: UUID?

    /// The `weeksAgo` offset of the week drawn behind, or nil for none. Off by
    /// default — the athlete opened THIS week, and a second week of ink before
    /// they asked for one is the jumble this surface is trying not to be.
    @State private var compareOffset: Int?

    private var selectedRun: Run? {
        selected.flatMap { id in week.allRuns.first { $0.id == id } }
    }

    /// The week drawn behind. Read from the cache, filled by `.onChange`.
    private var comparison: Week? { comparisonWeek }

    // MARK: Geometry

    /// Bar width is a FRACTION OF THE DAY, not a constant.
    ///
    /// A fixed 13pt looked right in the 114pt band landscape gives it and was
    /// indefensible in the 47pt band portrait gives it: the bar ate 28% of its
    /// own day, so two runs seven hours apart — 29% of a day — could not draw
    /// clear of each other no matter how the placement maths worked. Width has
    /// to shrink with the window or "where in the day" stops being a claim the
    /// chart can make. Floored at 4pt so a bar is still a mark, capped at 12pt
    /// so a wide iPad band doesn't grow slabs.
    private func barWidth(slot: CGFloat) -> CGFloat {
        min(12, max(4, slot * 0.10))
    }
    private let minBarHeight: CGFloat = 3
    private let stubHeight: CGFloat = 14
    /// Keeps the tallest bar off the top edge and leaves the niggle caret
    /// somewhere to sit without clipping.
    private let railHeight: CGFloat = 54
    /// Room above the tallest bar for its niggle caret and the top gridline
    /// label, so neither collides with the plot's ceiling.
    private let axisTop: CGFloat = 16
    // NOTE: `headRoom` and `clock(_:)` were removed with the scrub hairline —
    // the panel reads the clock time off `run.clockLabel` now.
    /// Width of the y-axis label gutter.
    private let axisGutter: CGFloat = 32
    /// Share of the width the readout takes in landscape. The chart is the
    /// thing; the panel supports it.
    private let panelFraction: CGFloat = 0.32

    // MARK: Body

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height

            Group {
                if landscape {
                    HStack(alignment: .top, spacing: 24) {
                        chartColumn
                            .frame(width: geo.size.width * (1 - panelFraction) - 24)
                        readout
                            .frame(width: geo.size.width * panelFraction)
                    }
                } else {
                    // Fallback only — the rotation request above normally
                    // means this never renders. It exists for the cases the
                    // system can refuse: an iPad in Split View, Guided Access,
                    // a scene that is not foreground-active. A working portrait
                    // layout beats a sideways-locked blank screen.
                    VStack(alignment: .leading, spacing: 0) {
                        chartColumn
                        readout
                        Text("Turn your phone — this one is built sideways.")
                            .font(.dripEyebrow(9)).tracking(1.1)
                            .foregroundStyle(Color.drip.textTertiary)
                            .padding(.top, 16)
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .background(Color.drip.background.ignoresSafeArea())
        .onChange(of: offsetDelta) { _, new in
            pagedWeek = new == 0 ? nil : weekAt(weekOffset + new)
            // C · the RHR control hides itself on a week with no readings, so
            // leaving it ON while paging would strand the athlete with an
            // overlay and no way to switch it off.
            selected = nil
        }
        .onChange(of: compareOffset) { _, new in
            comparisonWeek = new.map(weekAt)
        }
        // Only the runs on screen, and only once each — the service caches by
        // log id, so paging back over a block costs nothing after the first
        // visit. Deliberately not gated on `showingHR`: fetching while the
        // toggle is off means the overlay appears the instant it is tapped
        // rather than a second later.
        .task(id: viewOffset) { await hrTraces.load(week.allRuns.map(\.id)) }
        .onAppear { SheetOrientation.set(.landscape) }
        // Restored on the way out, not left where it was: every other surface
        // in the app is a portrait reading column, and dropping the athlete
        // back into one of them sideways reads as a bug in the app rather than
        // as the timeline having had an opinion.
        .onDisappear { SheetOrientation.set(.portrait) }
    }

    private var chartColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            plot
            caption
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        offsetDelta += 1
                        selected = nil
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.drip.textSecondary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Previous week")

                Text(labelAt(viewOffset))
                    .font(.dripEyebrow(12)).tracking(1.3)
                    .foregroundStyle(Color.drip.textPrimary)
                    .lineLimit(1)
                    .fixedSize()

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        offsetDelta -= 1
                        selected = nil
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(viewOffset <= 0
                                         ? Color.drip.textTertiary.opacity(0.35)
                                         : Color.drip.textSecondary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(viewOffset <= 0)
                .accessibilityLabel("Next week")

                Spacer()
                Button { dismiss() } label: {
                    Text("CLOSE")
                        .font(.dripEyebrow(10)).tracking(1.1)
                        .foregroundStyle(Color.drip.coral)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close the full-screen timeline")
            }

            // NOTHING IN THIS ROW MAY WRAP. Every item here is a single token
            // — a score, a unit, a control — and SwiftUI's default is to wrap
            // Text at any width, which broke "283" across two lines and turned
            // "RESTING HR" into three. `fixedSize` on each says "you get your
            // natural width"; the summary on the right is the only thing
            // allowed to give, and it gives by truncating rather than by
            // making the headline illegible. `layoutPriority(-1)` is what
            // makes the squeeze land there and nowhere else.
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(metric == .load ? "\(Int(week.load.rounded()))"
                                     : String(format: "%.1f", week.miles))
                    .font(.dripStat(28))
                    .foregroundStyle(Color.drip.textPrimary)
                    .lineLimit(1)
                    .fixedSize()
                Text(metric.unit)
                    .font(.dripStat(13))
                    .foregroundStyle(Color.drip.textSecondary)
                    .lineLimit(1)
                    .fixedSize()
                Spacer(minLength: 12)

                rhrToggle

                comparePicker

                Text("\(week.runDays) DAYS · \(week.allRuns.count) RUNS · "
                     + WeekStressStripSection.fmtDuration(week.timeSec))
                    .font(.dripEyebrow(9)).tracking(1.1)
                    .foregroundStyle(Color.drip.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(-1)
                    .padding(.leading, 12)
            }
            .padding(.top, 10)
        }
    }

    @ViewBuilder
    private var rhrToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { showingHR.toggle() }
        } label: {
            Text("HEART RATE")
                .font(.dripEyebrow(9)).tracking(1.1)
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(showingHR ? Color.drip.background
                                           : Color.drip.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background {
                    if showingHR { Capsule().fill(Color.drip.textPrimary) }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Overlay each run's heart rate")
        .accessibilityAddTraits(showingHR ? [.isSelected] : [])
        .padding(.trailing, 8)
    }

    /// Off, it is one word. On, it becomes a week nav — because "compare with
    /// last week" is the common case but not the only one: an athlete looks
    /// back at the same week of a previous build, or at the week before a race.
    /// Paging is bounded at 0 (this week) and cannot run into the future.
    @ViewBuilder
    private var comparePicker: some View {
        if let off = compareOffset {
            HStack(spacing: 6) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { compareOffset = off + 1 }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.drip.textSecondary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Compare with an earlier week")

                Text("VS \(labelAt(off))")
                    .font(.dripEyebrow(9)).tracking(1.1)
                    .foregroundStyle(Color.drip.textSecondary)
                    .fixedSize()

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        compareOffset = max(0, off - 1)
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(off <= 0 ? Color.drip.textTertiary.opacity(0.35)
                                                  : Color.drip.textSecondary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(off <= 0)
                .accessibilityLabel("Compare with a later week")

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { compareOffset = nil }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.drip.textTertiary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Stop comparing")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background { Capsule().fill(Color.drip.paperDeep.opacity(0.7)) }
        } else {
            Button {
                // Opens on the week before, which is what "compare" means most
                // of the time; the chevrons take it anywhere from there.
                withAnimation(.easeInOut(duration: 0.18)) {
                    compareOffset = viewOffset + 1
                }
            } label: {
                Text("COMPARE")
                    .font(.dripEyebrow(9)).tracking(1.1)
                    .lineLimit(1)
                    .fixedSize()
                    .foregroundStyle(Color.drip.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Overlay another week")
        }
    }

    // MARK: The plot

    private var plot: some View {
        GeometryReader { geo in
            let laneW = max(1, geo.size.width - axisGutter)
            let slot  = laneW / 7
            let fullH = max(60, geo.size.height - railHeight - axisTop)
            // SMALL MULTIPLES, not an overlay. Two weeks stacked get EQUAL
            // height, which is the whole point: identical scale means a bar
            // the same height is the same score, and the comparison is read
            // rather than decoded. Every overlay attempt failed on the same
            // thing — two sets of the same kind of mark in one frame — and
            // separating them vertically lets BOTH keep their pace colours
            // instead of demoting one week to grey.
            let panelGap: CGFloat = comparison == nil ? 0 : 14
            let plotH = comparison == nil ? fullH : (fullH - panelGap) / 2
            let lowerTop = axisTop + plotH + panelGap
            let ceiling = self.ceiling
            let bw = barWidth(slot: slot)
            let xs = layout(slot: slot, laneW: laneW, bw: bw, in: week.allRuns)
            let cmpXs = comparison.map { layout(slot: slot, laneW: laneW, bw: bw, in: $0.allRuns) }

            ZStack(alignment: .topLeading) {
                // 1 · Alternating day bands. The single strongest thing keeping
                //     this from reading as one undifferentiated field of bars:
                //     seven 24-hour windows become visibly seven, and every bar
                //     is unambiguously inside one of them.
                ForEach(Array(week.days.indices), id: \.self) { i in
                    if i % 2 == 1 {
                        Rectangle()
                            .fill(Color.drip.paperDeep.opacity(0.55))
                            .frame(width: slot, height: fullH)
                            .offset(x: axisGutter + slot * CGFloat(i), y: axisTop)
                    }
                }

                // A RULE AT EVERY DAY BOUNDARY. The tint alone was not enough:
                // with nothing but a shade change to mark the edge, two runs
                // seven hours apart inside one day read as the same loose
                // cluster as two runs either side of midnight. The eye needs a
                // hard edge to parcel bars into days before it can judge
                // anything about where they sit inside one. Dashed on a day
                // that has not happened yet, so "not yet" stays visibly
                // different from "empty".
                ForEach(Array(week.days.indices.dropFirst()), id: \.self) { i in
                    Path { p in
                        p.move(to: .zero)
                        // fullH, not plotH: the boundary has to run past BOTH
                        // panels, or the days stop being divided halfway down
                        // exactly when a second week makes that division most
                        // necessary.
                        p.addLine(to: CGPoint(x: 0, y: fullH))
                    }
                    .stroke(Color.drip.textTertiary.opacity(0.45),
                            style: week.days[i].isFuture
                                ? StrokeStyle(lineWidth: 1, dash: [3, 3])
                                : StrokeStyle(lineWidth: 1))
                    .frame(width: 1, height: fullH)
                    .offset(x: axisGutter + slot * CGFloat(i), y: axisTop)
                }

                // 2 · The y axis. Gridlines give the eye a rule to carry across
                //     the whole week; without them height is only comparable,
                //     never readable.
                ForEach(0...4, id: \.self) { i in
                    let v = ceiling * Double(i) / 4
                    let y = axisTop + plotH - CGFloat(v / ceiling) * plotH
                    Rectangle()
                        .fill(i == 0 ? Color.drip.textTertiary : Color.drip.divider)
                        .frame(width: laneW, height: 1)
                        .offset(x: axisGutter, y: y)
                    Text(gridLabel(v))
                        .font(.dripStat(9))
                        .foregroundStyle(Color.drip.textTertiary)
                        .frame(width: axisGutter - 8, alignment: .trailing)
                        .offset(y: y - 6)
                }

                // 3 · The week's average day. One dashed rule, so "was Saturday
                //     big" has an answer instead of a feeling.
                let avgY = axisTop + plotH - CGFloat(average / ceiling) * plotH
                Rectangle()
                    .fill(Color.drip.textSecondary.opacity(0.5))
                    .frame(width: laneW, height: 1)
                    .offset(x: axisGutter, y: avgY)
                // Its own child, not an `.overlay` on the rule: an overlay
                // inherits the 1pt-tall rule's coordinate space, so the label
                // would be positioned against a hairline instead of the plot.
                Text("AVG \(Int(average.rounded()))")
                    .font(.dripEyebrow(8)).tracking(0.9)
                    .foregroundStyle(Color.drip.textSecondary)
                    .frame(width: laneW, alignment: .trailing)
                    .offset(x: axisGutter, y: avgY - 13)

                // 4 · Last week, as its own panel below. See `comparisonPanel`.
                comparisonPanel(laneW: laneW, plotH: plotH,
                                lowerTop: lowerTop, bw: bw, cmpXs: cmpXs)

                // 5 · This week.
                ForEach(week.allRuns) { run in
                    let h = height(run, plotH: plotH)
                    bar(run, height: h, bw: bw)
                        .offset(x: axisGutter + (xs[run.id] ?? 0),
                                y: axisTop + plotH - h)
                }

                ForEach(week.days.filter { $0.niggle != nil && !$0.runs.isEmpty }) { day in
                    let anchor = day.runs[0]
                    let h = height(anchor, plotH: plotH)
                    NiggleCaret()
                        .fill(Color.drip.coral)
                        .frame(width: 9, height: 6)
                        .offset(x: axisGutter + (xs[anchor.id] ?? 0) + (bw - 9) / 2,
                                y: axisTop + plotH - h - 11)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }

                if showingHR {
                    ForEach(week.allRuns) { run in
                        if let trace = hrTraces.traces[run.id] {
                            hrTrace(run, trace: trace, slot: slot,
                                    plotH: plotH, x: xs[run.id] ?? 0)
                        }
                    }
                }

                rail(slot: slot)
                    .frame(width: laneW, height: railHeight)
                    .offset(x: axisGutter, y: axisTop + fullH + 1)
            }
            // Tapping the background clears the selection, so there is a way
            // out that is not "find the same small bar again".
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeInOut(duration: 0.16)) { selected = nil } }
        }
        .padding(.top, 14)
    }

    /// Section 4 — the compared week, as its own panel below this week's.
    ///
    /// Extracted from `plot` because that one `ZStack` grew past what the
    /// type-checker would solve in reasonable time. Behaviour is unchanged;
    /// it is the same children with the same offsets.
    ///
    /// NOTE ON THE STALE COMMENTARY this replaced: the block carried three
    /// layered rationales from abandoned attempts — "grey, never a faded
    /// blue", then "one silhouette per day", then "a skyline, drawn as a line
    /// rather than as more bars" — all of which argue against drawing the
    /// compared week as bars at all. The code drew bars regardless. The
    /// small-multiples note at the top of `plot` is the one that matches what
    /// is here: two panels, equal scale, both keeping their pace colours. If
    /// the skyline is what you actually want, this is the function to rewrite.
    @ViewBuilder
    private func comparisonPanel(laneW: CGFloat, plotH: CGFloat,
                                 lowerTop: CGFloat, bw: CGFloat,
                                 cmpXs: [Run.ID: CGFloat]?) -> some View {
        if let comparison, let cmpXs, let off = compareOffset {
            // Its own baseline, its own bars, the SAME scale.
            Rectangle()
                .fill(Color.drip.textTertiary)
                .frame(width: laneW, height: 1)
                .offset(x: axisGutter, y: lowerTop + plotH)

            ForEach(comparison.allRuns) { run in
                let h = height(run, plotH: plotH)
                referenceBar(run, height: h, bw: bw)
                    .offset(x: axisGutter + (cmpXs[run.id] ?? 0),
                            y: lowerTop + plotH - h)
            }

            // The compared week's OWN total, and the difference. Without it
            // the lower panel showed a shape that had plainly changed and no
            // way to say by how much — and the difference is the entire
            // reason to put a second week on screen. Neutral ink and a signed
            // number: warm is mood and coral is alert in this app, and a
            // heavier week than last week is neither.
            HStack(spacing: 6) {
                Text(labelAt(off))
                    .foregroundStyle(Color.drip.textTertiary)
                Text(fmtValue(weekTotal(comparison)) + " " + metric.unit.uppercased())
                    .foregroundStyle(Color.drip.textSecondary)
                Text(deltaLabel(comparison))
                    .foregroundStyle(Color.drip.textSecondary)
            }
            .font(.dripEyebrow(8))
            .tracking(1.0)
            .lineLimit(1)
            .fixedSize()
            .frame(width: laneW, alignment: .leading)
            .offset(x: axisGutter + 2, y: lowerTop - 11)
            .accessibilityLabel(
                "Compared with \(labelAt(off)), "
                + "\(fmtValue(weekTotal(comparison))) \(metric.unit), "
                + "\(deltaLabel(comparison))")
        }
    }

    /// One run of the COMPARED week, in the lower panel.
    ///
    /// Keeps its pace colours rather than going grey. That follows the
    /// small-multiples decision at the top of `plot`: two panels at equal
    /// scale, so neither week has to be demoted to a tint to stay legible.
    /// (The "GREY, never a faded ramp color" note further up is left over from the
    /// abandoned single-panel overlay — see the note in `plot`.)
    ///
    /// Not a `Button`: selection belongs to the week being read, and a tap
    /// target in the reference panel would offer a detail panel for a run
    /// from another week.
    @ViewBuilder
    private func referenceBar(_ run: Run, height h: CGFloat, bw: CGFloat) -> some View {
        barFill(run, height: h, bw: bw)
            .frame(width: bw, height: h)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// The visual of a bar, with no interaction and no selection state — the
    /// part `bar` and `referenceBar` genuinely share.
    @ViewBuilder
    private func barFill(_ run: Run, height h: CGFloat, bw: CGFloat) -> some View {
        if run.hasZones {
            VStack(spacing: 0) {
                ForEach(Array(run.zones.reversed())) { z in
                    Rectangle()
                        .fill(ZoneTaxonomy.color(z.token))
                        .frame(height: h * CGFloat(z.value(metric)
                                                   / max(run.value(metric), 0.0001)))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 2))
        } else {
            // Ran, no breakdown. An OUTLINE, not a fill: a solid block
            // would be a height, and a height here is a claim about load
            // there is no data to make.
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.drip.paperDeep.opacity(0.6))
                .overlay {
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(Color.drip.textTertiary,
                                      style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                }
        }
    }

    /// One run. Height is the metric, fill is the pace split with easy at the
    /// base — the same reading order as the strip, so a run never inverts
    /// between the two views of it.
    @ViewBuilder
    private func bar(_ run: Run, height h: CGFloat, bw: CGFloat) -> some View {
        let isHot = selected == run.id
        Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                selected = selected == run.id ? nil : run.id
            }
        } label: {
        barFill(run, height: h, bw: bw)
        .frame(width: bw, height: h)
        .overlay {
            if isHot {
                // Selection is INK, never coral — coral is the alert palette
                // and must not sit on a pace fill.
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(Color.drip.textPrimary, lineWidth: 1.5)
            }
        }
        // Grown for the thumb, then pulled back on the two edges the caller
        // positions from — otherwise the padding would shift the bar off the
        // hour it was actually run at. A 15pt bar is not a 15pt target.
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .padding(.leading, -9)
        .padding(.top, -8)
        .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(run.voiceLabel)
        .accessibilityHint("Opens the pace breakdown")
    }

    /// One run's heart rate, drawn ACROSS THE MINUTES IT WAS RUNNING.
    ///
    /// This is the shape the athlete already knows from their watch: the ramp
    /// at the start, the steps through a rep session, the drop on the jog
    /// home. The day band is already twenty-four hours wide, so a trace that
    /// starts where the run started and is as wide as the run was long lands
    /// exactly where the effort happened — a thing the bar, which is a fixed
    /// width at a single point in the day, cannot show.
    ///
    /// ITS OWN SCALE, SHARED ACROSS THE WEEK. Heart rate is not training load
    /// and must not be read off the load axis, so the trace has its own range:
    /// the week's own min-to-max, padded, computed once so that every run is
    /// drawn against the same ruler and Tuesday's session visibly sits above
    /// Monday's easy hour. A per-run scale would make every run look identical.
    ///
    /// NEUTRAL INK. Blue is pace, warm is mood, coral is alert (CLAUDE.md).
    /// Heart rate is none of those, and drawing it in a pace color over a
    /// pace-coloured bar would be claiming the two mean the same thing.
    ///
    /// A DROPOUT BREAKS THE LINE — `Trace.segments` is what makes that happen.
    @ViewBuilder
    private func hrTrace(_ run: Run, trace: RunHRTraceService.Trace,
                         slot: CGFloat, plotH: CGFloat, x: CGFloat) -> some View {
        let range = hrRange
        let span = CGFloat(max(range.hi - range.lo, 1))
        // The run's true footprint on the time axis — NOT the bar's position,
        // which is nudged by the de-collision pass. A trace is wide enough to
        // show where it really sat, so it should.
        let startFrac = CGFloat(run.minuteOfDay ?? 0) / 1440
        let widthFrac = CGFloat(run.timeSec / 60) / 1440
        let x0 = axisGutter + slot * (CGFloat(run.dayIndex) + startFrac)
        let w = max(slot * widthFrac, 2)
        let minutes = max(CGFloat(trace.bpm.count - 1), 1)

        let point: (Int, Int) -> CGPoint = { minute, bpm in
            CGPoint(
                x: x0 + w * (CGFloat(minute) / minutes),
                y: axisTop + plotH
                   - plotH * (CGFloat(bpm - range.lo) / span) * 0.92 - plotH * 0.04
            )
        }

        ZStack(alignment: .topLeading) {
            ForEach(Array(trace.segments.enumerated()), id: \.offset) { _, seg in
                if seg.count > 1 {
                    Path { p in
                        p.move(to: point(seg[0].minute, seg[0].bpm))
                        for s in seg.dropFirst() {
                            p.addLine(to: point(s.minute, s.bpm))
                        }
                    }
                    .stroke(Color.drip.textPrimary.opacity(0.62),
                            style: StrokeStyle(lineWidth: 1.2, lineCap: .round,
                                               lineJoin: .round))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The week's heart-rate range, padded — one ruler for every trace.
    private var hrRange: (lo: Int, hi: Int) {
        let all = week.allRuns.compactMap { hrTraces.traces[$0.id]?.range }
        guard let lo = all.map(\.lo).min(), let hi = all.map(\.hi).max() else {
            return (100, 180)
        }
        return (max(0, lo - 4), hi + 4)
    }

    /// Seven equal cells under the axis: the day, its whole-day total, mood.
    private func rail(slot: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(week.days.enumerated()), id: \.element.id) { i, d in
                VStack(spacing: 0) {
                    Text(d.label)
                        .font(.dripEyebrow(11)).tracking(1.2)
                        .foregroundStyle(selectedRun?.dayIndex == i ? Color.drip.coral
                                         : d.isFuture ? Color.drip.textTertiary.opacity(0.5)
                                         : d.ran ? Color.drip.textSecondary
                                                 : Color.drip.textTertiary)
                        .padding(.top, 10)

                    // Mood sits with the DAY, immediately under its name —
                    // it is how the day felt, not what the number was. Below
                    // the total it read as a footnote to the score, which is
                    // the wrong thing for it to be attached to.
                    Capsule()
                        .fill(d.mood.flatMap { Self.moodColor($0) } ?? Color.clear)
                        .frame(width: 15, height: 2.5)
                        .padding(.top, 5)

                    // A future day shows NOTHING, not "0" — it has not had the
                    // chance to be zero yet. A rest day shows a real 0, because
                    // a zero is a fact and not a placeholder.
                    Text(d.isFuture ? " "
                         : metric == .load ? "\(Int(d.load.rounded()))"
                                           : String(format: "%.1f", d.miles))
                        .font(.dripStat(13))
                        .foregroundStyle(d.value(metric) > 0 ? Color.drip.textPrimary
                                                              : Color.drip.textTertiary)
                        .padding(.top, 5)
                }
                .frame(width: slot)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(rowVoiceLabel(d))
            }
        }
    }

    private var caption: some View {
        Text("Each band is one day, midnight to midnight. A bar sits where in "
             + "that day the run happened — left is early, right is late. "
             + "Warm-up, session and cool-down count as one run.")
            .font(.system(size: 12.5, design: .serif).italic())
            .foregroundStyle(Color.drip.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 12)
    }


    // MARK: The readout

    @ViewBuilder
    private var readout: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let run = selectedRun {
                let day: Day? = week.days.indices.contains(run.dayIndex)
                    ? week.days[run.dayIndex] : nil
                HStack(alignment: .firstTextBaseline) {
                    Text(run.whenLabel.uppercased())
                        .font(.dripEyebrow(10)).tracking(1.2)
                        .foregroundStyle(Color.drip.textSecondary)
                    Spacer()
                    if let d = day {
                        Button { onOpenDay(d.date) } label: {
                            Text("OPEN DAY ↗")
                                .font(.dripEyebrow(9)).tracking(1.1)
                                .foregroundStyle(Color.drip.coral)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Rectangle().fill(Color.drip.divider).frame(height: 1)
                    .padding(.top, 10)

                runReadout(run)

                dayFooter(run.dayIndex)
            } else {
                Text("TAP A RUN")
                    .font(.dripEyebrow(10)).tracking(1.2)
                    .foregroundStyle(Color.drip.textSecondary)
                Rectangle().fill(Color.drip.divider).frame(height: 1)
                    .padding(.top, 10)
                Text("Its pace breakdown opens here — what each zone cost, and "
                     + "what the day came to.")
                    .font(.dripBody(14))
                    .foregroundStyle(Color.drip.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 12)
    }

    /// The whole day under the run, and the same day in the compared week when
    /// one is on. The delta is the reason to overlay at all — reading it off
    /// two bar heights is exactly the estimating this surface avoids elsewhere.
    @ViewBuilder
    private func dayFooter(_ i: Int) -> some View {
        if week.days.indices.contains(i) {
        let d = week.days[i]
        Rectangle().fill(Color.drip.divider).frame(height: 1)
            .padding(.top, 14)

        Text("\(d.label.uppercased()) · \(d.runs.count) RUN"
             + (d.runs.count == 1 ? "" : "S"))
            .font(.dripEyebrow(9)).tracking(1.1)
            .foregroundStyle(Color.drip.textTertiary)
            .padding(.top, 10)

        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(metric == .load ? "\(Int(d.load.rounded()))"
                                 : String(format: "%.1f", d.miles))
                .font(.dripStat(18))
                .foregroundStyle(Color.drip.textPrimary)
            Text(metric.unit)
                .font(.dripStat(10))
                .foregroundStyle(Color.drip.textSecondary)
        }
        .padding(.top, 4)

        if let comparison, let off = compareOffset,
           comparison.days.indices.contains(i) {
            let was = comparison.days[i].value(metric)
            let delta = d.value(metric) - was
            // NEUTRAL INK, not green-up / red-down. Warm is mood and coral is
            // alert in this app (CLAUDE.md, three-palette rule), and a heavier
            // Tuesday than last Tuesday is neither. The sign carries it.
            Text("\(labelAt(off)) · \(fmtValue(was)) · "
                 + (delta >= 0 ? "+" : "−") + fmtValue(abs(delta)))
                .font(.dripEyebrow(9)).tracking(1.1)
                .foregroundStyle(Color.drip.textSecondary)
                .padding(.top, 6)
        }
        }
    }

    /// A week's total in the metric on screen.
    private func weekTotal(_ w: Week) -> Double {
        metric == .load ? w.load : w.miles
    }

    /// This week against that one, signed. Written as a MINUS SIGN rather than
    /// a hyphen so it lines up in the mono face and reads as arithmetic.
    private func deltaLabel(_ other: Week) -> String {
        let d = weekTotal(week) - weekTotal(other)
        guard abs(d) >= (metric == .load ? 0.5 : 0.05) else { return "LEVEL" }
        return (d > 0 ? "+" : "−") + fmtValue(abs(d))
    }

    private func fmtValue(_ v: Double) -> String {
        metric == .load ? "\(Int(v.rounded()))" : String(format: "%.1f", v)
    }

    @ViewBuilder
    private func runReadout(_ run: Run) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                stat(String(format: "%.1f", run.miles), "mi")
                stat(WeekStressStripSection.fmtDuration(run.timeSec), "")
                stat("\(Int(run.load.rounded()))", "TLS")
            }
            .padding(.top, 12)

            if let c = run.clockLabel {
                Text("STARTED \(c.uppercased())"
                     + (run.pieceCount > 1 ? " · \(run.pieceCount) UPLOADS" : ""))
                    .font(.dripEyebrow(9)).tracking(1.1)
                    .foregroundStyle(Color.drip.textTertiary)
                    .padding(.top, 6)
            }

            ForEach(run.zones) { z in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(ZoneTaxonomy.color(z.token))
                        .frame(width: 9, height: 9)
                    Text(ZoneTaxonomy.label(z.token).uppercased())
                        .font(.dripEyebrow(9)).tracking(1.0)
                        .foregroundStyle(Color.drip.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(WeekStressStripSection.fmtDuration(z.minutes * 60))
                        .font(.dripStat(11))
                        .foregroundStyle(Color.drip.textPrimary)
                    Text("×\(mult(z.effectiveWeight))")
                        .font(.dripStat(10))
                        .foregroundStyle(Color.drip.textTertiary)
                        .frame(width: 32, alignment: .trailing)
                    Text("\(Int(z.load.rounded()))")
                        .font(.dripStat(11))
                        .foregroundStyle(Color.drip.textPrimary)
                        .frame(width: 32, alignment: .trailing)
                }
                .padding(.top, 8)
            }

            if run.hasUnclassified {
                Text(String(format: "%.1f mi came in without a pace zone — "
                            + "counted in the distance, not in the load score.",
                            run.unclassifiedMiles))
                    .font(.system(size: 12.5, design: .serif).italic())
                    .foregroundStyle(Color.drip.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(run.voiceLabel)
    }

    private func stat(_ v: String, _ unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(v).font(.dripStat(19)).foregroundStyle(Color.drip.textPrimary)
            if !unit.isEmpty {
                Text(unit).font(.dripStat(11)).foregroundStyle(Color.drip.textSecondary)
            }
        }
    }

    // MARK: Scales

    /// Where a run WANTS to be: its start time inside its own 24-hour band.
    /// The `slot - barWidth` inset stops an 11pm run overhanging into the next
    /// day; an unplaceable run is centered rather than defaulted to midnight.
    private func idealX(_ run: Run, slot: CGFloat, bw: CGFloat) -> CGFloat {
        let base = CGFloat(run.dayIndex) * slot
        let usable = max(0, slot - bw)
        guard let minute = run.minuteOfDay else { return base + usable / 2 }
        return base + CGFloat(minute) / 1440 * usable
    }

    /// Chronological order across the whole week, so the de-collision pass
    /// below can walk the runs the way the athlete reads them.
    private func orderKey(_ run: Run) -> Int {
        run.dayIndex * 1440 + (run.minuteOfDay ?? 720)
    }

    /// Every bar's x, with overlaps resolved.
    ///
    /// TIME ALONE IS NOT ENOUGH TO PLACE A BAR. Two runs forty minutes apart
    /// want positions four points apart, and a 13pt bar cannot sit four points
    /// from its neighbour — they overlap and read as one wide smear with
    /// nonsense banding, which is exactly the "jumbled" this chart cannot
    /// afford. The same happens across a day boundary: a 10pm Monday and a 5am
    /// Tuesday are eleven hours apart in life and a few points apart here.
    ///
    /// So: place every bar at its true time, then walk left to right and push
    /// any bar that would touch its neighbour just far enough to clear it. A
    /// second pass walks back from the right in case the forward pass ran the
    /// last bar off the end. Bars never reorder and never move further than
    /// they must, so a nudged bar is still honest about WHEN — it just also
    /// stays legible, and the panel carries the exact clock time anyway.
    private func layout(slot: CGFloat, laneW: CGFloat, bw: CGFloat,
                        in runs: [Run]) -> [UUID: CGFloat] {
        // Scales with the bar: a 2pt gutter beside a 4pt bar reads as clearly
        // as a 4pt gutter beside a 12pt one.
        let minGap = max(2, bw * 0.35)
        let ordered = runs.sorted { orderKey($0) < orderKey($1) }
        var xs: [CGFloat] = ordered.map { idealX($0, slot: slot, bw: bw) }

        // Forward: nothing may start before the previous bar has finished.
        for i in 1 ..< max(xs.count, 1) {
            xs[i] = max(xs[i], xs[i - 1] + bw + minGap)
        }
        // Backward: if that pushed the last one past the edge, walk the excess
        // back down the line rather than letting it fall off.
        if let last = xs.last, last + bw > laneW {
            xs[xs.count - 1] = laneW - bw
            for i in stride(from: xs.count - 2, through: 0, by: -1) {
                xs[i] = min(xs[i], xs[i + 1] - bw - minGap)
            }
        }
        // `uniquingKeysWith`, NOT `uniqueKeysWithValues`: the latter TRAPS on a
        // duplicate key, and run ids come from `training_logs.id` in the
        // payload with nothing upstream guaranteeing a week can't carry the
        // same log twice. A chart is never worth a crash. Same defensive shape
        // `model()` already uses for its by-date dictionary.
        return Dictionary(zip(ordered.map(\.id), xs), uniquingKeysWith: { a, _ in a })
    }

    /// A bar's height, against the AXIS — not against the week's biggest run.
    ///
    /// This is the difference the y axis buys. The strip scales every week to
    /// its own peak, which is right when there are no gridlines to read: a
    /// recovery week would otherwise be a row of stubs. Here there IS a scale,
    /// printed, and rescaling it per week would make the printed numbers a lie
    /// — two weeks would draw the same bar at two different heights. So the
    /// ceiling is a round number above the peak, and it covers last week too
    /// when the overlay is on, or the comparison would be measured against a
    /// axis that does not contain it.
    private func height(_ run: Run, plotH: CGFloat) -> CGFloat {
        let v = run.value(metric)
        guard v > 0 else { return stubHeight }
        return max(minBarHeight, plotH * CGFloat(v / ceiling))
    }

    /// The top of the y axis: a round step above the biggest single run in
    /// view, so the labels read 0 / 50 / 100 / 150 rather than 0 / 42 / 84.
    private var ceiling: Double {
        var peak = week.allRuns.map { $0.value(metric) }.max() ?? 0
        if let comparison {
            // DAY totals, because the overlay draws days — not runs. Scaling
            // to a run the overlay never draws would leave dead headroom.
            peak = max(peak, comparison.days.map { $0.value(metric) }.max() ?? 0)
        }
        guard peak > 0 else { return metric == .load ? 100 : 10 }
        let steps: [Double] = metric == .load
            ? [10, 20, 25, 50, 100, 200, 250, 500]
            : [1, 2, 2.5, 5, 10, 20, 25]
        for s in steps where peak / s <= 4 { return (peak / s).rounded(.up) * s }
        return (peak / 500).rounded(.up) * 500
    }

    /// The week's average DAY — the reference the dashed rule draws. Divided by
    /// seven, not by the number of days run: a rest day is part of the week and
    /// dropping it would flatter every average.
    private var average: Double {
        let total = metric == .load ? week.load : week.miles
        return total / 7
    }

    private func gridLabel(_ v: Double) -> String {
        metric == .load ? "\(Int(v.rounded()))"
                        : (v == v.rounded() ? "\(Int(v))" : String(format: "%.1f", v))
    }

    // MARK: Formatting


    private func mult(_ w: Double) -> String {
        let r = (w * 10).rounded() / 10
        return r == r.rounded() ? "\(Int(r))" : String(format: "%.1f", r)
    }

    private func rowVoiceLabel(_ d: Day) -> String {
        if d.isFuture { return "\(d.label), upcoming." }
        if !d.ran { return "\(d.label), rest day." }
        return "\(d.label). " + d.runs.map(\.voiceLabel).joined(separator: " ")
    }

    /// Called through an explicit closure, never as a bare function value:
    /// `Color.drip` is main-actor isolated and passing the method as a value
    /// drops the call out of the body's MainActor context.
    private static func moodColor(_ mood: String) -> Color? {
        switch mood.lowercased() {
        case "energized":  return Color.drip.energized
        case "positive":   return Color.drip.positive
        case "neutral":    return Color.drip.neutral
        case "tired":      return Color.drip.tired
        case "struggling": return Color.drip.struggling
        case "injured":    return Color.drip.injured
        default:           return nil
        }
    }
}

/// Turns the phone for the athlete.
///
/// `requestGeometryUpdate` is the supported way to ask, and it rotates even
/// when the athlete has rotation lock switched on — which matters, because a
/// chart you have to go into Control Centre to see is a chart most people
/// never see.
///
/// `Info.plist` already lists both landscape orientations, so this is a request
/// the system will honour rather than one it will refuse. If that list is ever
/// narrowed to portrait, this silently stops working and the fallback layout
/// above is what the athlete gets — which is why that layout is kept.
private enum SheetOrientation {
    /// `@MainActor` because every symbol in the body is — `UIApplication.shared`,
    /// the scene's key window, and both UIKit calls. A bare `static func` gets
    /// no isolation inference and is a hard error under Swift 6.
    ///
    /// RETRIED, because the first attempt lands too early. `.onAppear` fires
    /// while `fullScreenCover` is still presenting, and at that moment the
    /// cover's own hosting controller is not yet the one the scene asks about
    /// its supported orientations — so the request is accepted and then
    /// immediately re-evaluated against the presenting (portrait) controller.
    /// The symptom is a sheet that silently stays portrait, which is what
    /// shipped: the fallback layout appeared with its "turn your phone" line
    /// on a phone that was never going to turn itself.
    ///
    /// `setNeedsUpdateOfSupportedInterfaceOrientations` on the TOPMOST
    /// presented controller is the other half — without it UIKit keeps the
    /// answer it cached before the cover existed.
    @MainActor
    static func set(_ mask: UIInterfaceOrientationMask, retries: Int = 3) {
        // Foreground-active first, but fall back to any window scene: during
        // presentation the state is briefly `.foregroundInactive`, and
        // returning early there is precisely how the request gets skipped.
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive })
                       ?? scenes.first
        else { return }

        var top = scene.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        top?.setNeedsUpdateOfSupportedInterfaceOrientations()

        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { error in
            Log.coach.warning(
                "Sheet orientation request refused: \(error.localizedDescription)")
        }

        // Did it take? If the scene is still the wrong way round a beat later,
        // ask again — the presentation has finished by then.
        guard retries > 0 else { return }
        let wanted = mask == .landscape
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 220_000_000)
            let isLandscape = scene.effectiveGeometry.interfaceOrientation.isLandscape
            if isLandscape != wanted { set(mask, retries: retries - 1) }
        }
    }
}

/// The niggle caret, pointing DOWN at the run it belongs to. Coral is the
/// alert palette and must never sit on a pace fill, so it hangs above the bar.
private struct NiggleCaret: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

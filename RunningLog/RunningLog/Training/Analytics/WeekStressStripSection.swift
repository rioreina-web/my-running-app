//
//  WeekStressStripSection.swift
//  RunningLog
//
//  One week of training stress as a single horizontal strip.
//
//    • EACH DAY   = an equal 1/7 of the width, representing a full 24 hours
//    • X POSITION = when the run started inside that day (early left, late right)
//    • BAR HEIGHT = that run's training load score
//    • BAR FILL   = the pace zones it was run in, easy at the base
//    • TAP A BAR  = its pace breakdown, opened in place
//
//  Replaced `WeekTrainingLoadSection` (seven circles) 2026-08-11. That section
//  answered "how far each day" with circle area and "how hard" with one color
//  per day. It could not answer "when", and it could not show a double at all:
//  a morning session and an evening easy four were one circle with one color.
//
//  WHY HEIGHT IS LOAD AND WIDTH IS NOTHING. The first pass drew each run at
//  true scale on the time axis — width proportional to duration, so area was
//  load. That is the better chart and it is not available here: seven days
//  across a 390pt phone leaves a day slot of ~48pt, so a 76-minute run is
//  2.5pt wide. A hairline. So width is fixed, height carries the whole
//  magnitude, and duration is a number in the panel. The version that keeps
//  proportional width is one day per row, not seven — see
//  `week-stress-clock-prototype.html` in the repo root if that surface is ever
//  wanted. Do not try to retrofit it into this one.
//
//  WHY THERE IS NO HOUR AXIS. Position is deliberately imprecise: it claims a
//  part of the day, not an hour. Gridlines at 6/12/18 and tick labels would
//  invite measuring off a 48pt slot, which the encoding does not support. The
//  single italic line under the strip is the entire contract, and every place
//  the app states *when* in words it says "Morning", not "6:05am" — the clock
//  time appears in the panel, where it is read rather than estimated.
//
//  WHY A RUN WITH NO START TIME IS CENTERED. A bar has to go somewhere, and the
//  far left of the slot is not "unknown", it is a claim that the athlete ran at
//  midnight. Centered, hatched and heightless is the only honest rendering, and
//  it is also what the whole week looks like before `days[].runs` is deployed —
//  which reads as "we don't know yet" rather than as a broken chart.
//
//  Data: `TrainingAnalyticsViewModel.dayVolumes(forWeekStart:)` for the Mon→Sun
//  scaffolding, `TrendsService.days[].runs` for per-run start times + zones, and
//  `QualityLoad` / `TrendsZoneWeight` for the load maths. `ZoneTaxonomy` (color
//  + order + the ramp/backend vocabulary reconciliation) is reused from
//  `WeekTrainingLoadSection.swift`, which stays in the repo unmounted — it also
//  still owns `LoadDay`, which `TrainingLoadExplainer` takes.
//

import Foundation
import SwiftUI

struct WeekStressStripSection: View {

    let vm: TrainingAnalyticsViewModel
    /// Deep link into the full day sheet, from the panel's "Open day".
    var onOpenDay: (Date) -> Void

    /// 0 = current week, 1 = last week. SHARED with the This-Week list above via
    /// a binding so the two week navs move together.
    @Binding var weekOffset: Int

    /// The open run, or nil. Not defaulted to today's run — opening with a panel
    /// already down buries the strip, and on a past week there is no today.
    @State private var selected: UUID?

    /// The TLS explainer sheet, from the panel's load number.
    @State private var explainingLoad = false

    /// The full-screen landscape timeline. Not a navigation push: the sheet
    /// wants the whole screen including where the tab bar sits, and it is a
    /// LOOK at this week rather than a place in the app to be somewhere.
    @State private var expanded = false

    /// What bar height means. Persisted, not `@State`: an athlete who thinks in
    /// miles thinks in miles every week, and making them re-pick on every launch
    /// would be a setting that pretends to be a filter.
    @AppStorage("weekStrip.metric") private var metricRaw: String = StripMetric.load.rawValue

    /// What the athlete PICKED. Read `metric`, not this: a standing preference
    /// for TLS is not a promise that TLS exists on the week being drawn.
    private var chosenMetric: StripMetric { StripMetric(rawValue: metricRaw) ?? .load }

    /// Whether load can be computed at all. It is derived from the zone minutes
    /// that only `TrendsService.days` carries, so with that array empty every
    /// bar scores zero — and a headline reading "0 TLS" over a week with 23
    /// miles in it is not a measurement, it is a wrong answer stated confidently.
    /// That is what the section did on 2026-08-11 while the backend was down.
    private var loadAvailable: Bool { !trends.days.isEmpty }

    /// What the section ACTUALLY draws in. Falls back to miles whenever load is
    /// unavailable, so the surface degrades to the number it does have instead
    /// of to a zero it cannot stand behind. Miles come from the local view
    /// model and survive the network being gone.
    private var metric: StripMetric { loadAvailable ? chosenMetric : .volume }

    /// `TrendsService` is only otherwise loaded by the Trends tabs, and this
    /// section is on TRAIN. Held as `@State` (not read through `.shared` inline)
    /// so `@Observable` tracks it and the strip redraws when the fetch lands.
    @State private var trends = TrendsService.shared

    @ScaledMetric(relativeTo: .caption2)
    private var eyebrowMicro: CGFloat = DripTypeFloor.eyebrowMicro
    @ScaledMetric(relativeTo: .caption)
    private var eyebrowSmall: CGFloat = DripTypeFloor.eyebrowSmall

    @Environment(\.dynamicTypeSize) private var typeSize

    // MARK: Geometry
    //
    // Every vertical gap on this surface comes off the 8pt scale — 8 / 12 / 16 /
    // 20 / 24 / 32. Untokenized spacing is a standing drift in this codebase and
    // a brand-new surface has no excuse for adding to it.

    /// Plot height. NOT scaled with Dynamic Type: it is a chart, and growing it
    /// with the type ramp would push the day rail off a small screen while
    /// making the bars no more legible.
    private let plotHeight: CGFloat = 128
    private let barWidth: CGFloat = 11
    /// Keeps the tallest bar off the top edge AND leaves the niggle caret
    /// somewhere to sit above a bar without clipping.
    private let headRoom: CGFloat = 16
    /// A 12-minute shakeout still has to be visible and tappable.
    private let minBarHeight: CGFloat = 3
    /// The "ran, but we cannot say how" stub. A height, but not a load height —
    /// it is flat and hatched so it reads as an outline, not a measurement.
    private let stubHeight: CGFloat = 12
    /// Diameter the week's biggest RUN gets in MILES mode. Every other run is
    /// smaller, by area. Capped just under the ~48pt day slot so a late-evening
    /// run cannot spill into the next day, which is the whole reason the marks
    /// are inset from the slot edge.
    private let maxPieDiameter: CGFloat = 44

    init(vm: TrainingAnalyticsViewModel,
         weekOffset: Binding<Int>,
         onOpenDay: @escaping (Date) -> Void) {
        self.vm = vm
        self.onOpenDay = onOpenDay
        _weekOffset = weekOffset
    }

    // MARK: Body

    var body: some View {
        let week = model()

        VStack(alignment: .leading, spacing: 0) {
            head(week)

            if trends.isLoading && trends.days.isEmpty {
                EmptyStateView(
                    variant: .dataPending,
                    eyebrow: "Loading",
                    title: "Pulling this week's runs and their pace breakdown."
                )
                .padding(.top, 8)
            } else if trends.failedWithNothingToShow && week.miles <= 0 {
                // Nothing locally AND nothing from the server. There is no week
                // to draw, and the two states below would both misattribute it:
                // "no miles yet" and "a week off" are claims about the athlete,
                // and this is a claim about the backend.
                EmptyStateView(
                    variant: .error,
                    eyebrow: "Couldn't load",
                    title: "This week's runs didn't come through. Check your "
                         + "connection and try again.",
                    cta: .init(label: "RETRY") { retry() }
                )
            } else if week.miles > 0 {
                // Gated on MILES, not load. A week whose runs all arrived
                // without laps scores zero load and is still a week that was
                // run; gating on load hides it behind "nothing logged".
                if trends.failedWithNothingToShow { loadFailedNote }
                strip(week)
                axisNote

                // Looked up in what this mode DREW, not in allRuns — a MILES
                // selection is a day mark, whose id is the day and is not in
                // allRuns at all, so tapping a circle opened nothing.
                if let id = selected, let run = marks(week).first(where: { $0.id == id }) {
                    runPanel(run, week: week)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                legend
            } else {
                let isCurrent = vm.isCurrentWeek(vm.weekStart(weeksAgo: weekOffset))
                EmptyStateView(
                    variant: isCurrent ? .dataPending : .optionalEmpty,
                    eyebrow: isCurrent ? "No miles yet" : "A week off",
                    title: isCurrent
                        ? "Nothing logged this week so far. Once a run lands, it shows "
                          + "up here at the hour you ran it."
                        : "Nothing was logged that week. Page forward to a week with "
                          + "runs in it."
                )
            }
        }
        .padding(.top, 32)
        // `refresh()` no-ops when already loaded, so arriving here after a visit
        // to Trends costs nothing; arriving here first does the fetch.
        .task { await trends.refresh() }
        // The SAME `week` this section just drew, handed over rather than
        // rebuilt. `model()` stays the one place a week is assembled; a second
        // builder would be a second definition of a week.
        .fullScreenCover(isPresented: $expanded) {
            WeekStressClockSheet(
                initialWeek: week,
                weekOffset: weekOffset,
                // The BUILDER, not a second week: the sheet's compare picker
                // pages anywhere, and every week it draws has to come off this
                // one function or two weeks could be assembled two ways.
                weekAt: { model(weeksAgo: $0) },
                labelAt: { weeksAgo in
                    let start = vm.weekStart(weeksAgo: weeksAgo)
                    return vm.isCurrentWeek(start)
                        ? "THIS WEEK"
                        : TrainingAnalyticsViewModel.weekRangeLabel(start)
                },
                metric: metric,
                onOpenDay: { date in
                    expanded = false
                    onOpenDay(date)
                }
            )
        }
    }

    // MARK: Head

    private func head(_ week: StripWeek) -> some View {
        let start = vm.weekStart(weeksAgo: weekOffset)
        let isCurrent = vm.isCurrentWeek(start)

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        weekOffset += 1
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

                Text(isCurrent ? "THIS WEEK"
                               : TrainingAnalyticsViewModel.weekRangeLabel(start))
                    .font(.dripEyebrow(eyebrowSmall + 1)).tracking(1.3)
                    .foregroundStyle(Color.drip.textPrimary)

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        weekOffset = max(0, weekOffset - 1)
                        selected = nil
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isCurrent ? Color.drip.textTertiary.opacity(0.35)
                                                   : Color.drip.textSecondary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isCurrent)
                .accessibilityLabel("Next week")

                Spacer()

                metricToggle

                Button { expanded = true } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.drip.textSecondary)
                        .padding(.leading, 10)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open the full-screen timeline")
                .accessibilityHint("Turn your phone sideways for the full width")
            }
            .padding(.bottom, 16)

            // The headline names whatever the bars are drawn in, so the number
            // and the picture are never in different units.
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(metric == .load ? "\(Int(week.load.rounded()))"
                                     : fmtMiles(week.miles))
                    .font(.dripStat(30))
                    .foregroundStyle(Color.drip.textPrimary)
                Text(metric.unit)
                    .font(.dripStat(14))
                    .foregroundStyle(Color.drip.textSecondary)
            }

            Text(contextLine(week))
                .font(.dripEyebrow(eyebrowMicro)).tracking(1.1)
                .foregroundStyle(Color.drip.textTertiary)
                .padding(.top, 8)
        }
        // NOT `.accessibilityElement(children: .combine)` — combining silently
        // removes the two week-nav buttons from the VoiceOver rotor.
    }

    /// The OTHER metric, as a footnote, so switching the headline never hides a
    /// number — it only moves it between headline and footnote.
    ///
    /// When load has not arrived there is no other metric to carry, and the
    /// old string invented two of them: it printed "0 TLS · 0:00" beside a real
    /// mileage, which reads as "you did 23 miles and they were worth nothing"
    /// rather than as "we haven't got the pace breakdown".
    private func contextLine(_ week: StripWeek) -> String {
        guard loadAvailable else {
            // No second metric and no duration: both come from the timeline,
            // and the headline is already carrying the mileage.
            return "\(week.runDays) DAYS · TRAINING LOAD NOT IN YET"
        }
        let other = metric == .load ? "\(fmtMiles(week.miles)) MI"
                                    : "\(Int(week.load.rounded())) TLS"
        return "\(week.runDays) DAYS · \(other) · \(Self.fmtDuration(week.timeSec))"
    }

    /// Sits over a week we can draw in miles but not in load. One line, and the
    /// way back — without it, a row of dashed stubs is indistinguishable from a
    /// week of runs the segmenter genuinely could not classify, and there is
    /// nothing on screen the athlete can act on.
    private var loadFailedNote: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("PACE BREAKDOWN DIDN'T LOAD")
                .font(.dripEyebrow(eyebrowMicro)).tracking(1.1)
                .foregroundStyle(Color.drip.coral)
            Spacer()
            Button { retry() } label: {
                Text("RETRY")
                    .font(.dripEyebrow(eyebrowMicro)).tracking(1.1)
                    .foregroundStyle(Color.drip.coral)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Retry loading the pace breakdown")
        }
        .padding(.top, 24)
        // NOT `.accessibilityElement(children: .combine)`: combining would fold
        // the button into the sentence and drop it out of the VoiceOver rotor,
        // leaving a screen-reader user told about a failure with no way to act
        // on it. Same trap as the one flagged in `head`.
    }

    /// `force` because a failed load leaves `loaded` false but a SECOND failure
    /// would otherwise be indistinguishable from a no-op to the athlete — and
    /// because the same button has to work once the fetch has succeeded and the
    /// athlete simply wants fresher data.
    private func retry() {
        Task { await trends.refresh(force: true) }
    }

    /// Two words, not a segmented control. `.segmented` is a form control and
    /// this is an editorial surface — the pill matches the week nav beside it
    /// and costs less ink than a filled iOS segment would.
    private var metricToggle: some View {
        HStack(spacing: 2) {
            ForEach([StripMetric.load, .volume], id: \.rawValue) { m in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { metricRaw = m.rawValue }
                } label: {
                    Text(m.short)
                        .font(.dripEyebrow(eyebrowMicro)).tracking(1.1)
                        .foregroundStyle(metric == m ? Color.drip.background
                                                     : Color.drip.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background {
                            if metric == m {
                                Capsule().fill(Color.drip.textPrimary)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                // Not hidden — the athlete's own preference is still stored and
                // comes back the moment the breakdown lands. Dimmed and inert,
                // so tapping it cannot produce a screen full of zeroes.
                .disabled(m == .load && !loadAvailable)
                .opacity(m == .load && !loadAvailable ? 0.35 : 1)
                .accessibilityLabel(m == .load ? "Show training load" : "Show distance")
                .accessibilityValue(m == .load && !loadAvailable
                                    ? "Unavailable, pace breakdown not loaded" : "")
                .accessibilityAddTraits(metric == m ? [.isSelected] : [])
            }
        }
    }

    // MARK: The strip

    private func strip(_ week: StripWeek) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            GeometryReader { geo in
                let slot = geo.size.width / 7

                // `.bottomLeading` so every child hangs off the axis line and
                // `offset` is measured from there. `layoutPriority` cannot
                // divide width proportionally in an HStack (see the RRZoneBar
                // note in WorkoutReceiptCharts.swift), so positions are
                // computed from the geometry rather than delegated to a stack.
                ZStack(alignment: .bottomLeading) {
                    // Interior boundaries only — no box around the strip. A day
                    // that has not happened yet gets a DASHED boundary, so
                    // "not yet" is visibly not the same as "empty".
                    ForEach(Array(week.days.indices.dropFirst()), id: \.self) { i in
                        Path { p in
                            p.move(to: .zero)
                            p.addLine(to: CGPoint(x: 0, y: plotHeight))
                        }
                        .stroke(Color.drip.divider,
                                style: week.days[i].isFuture
                                    ? StrokeStyle(lineWidth: 1, dash: [3, 3])
                                    : StrokeStyle(lineWidth: 1))
                        .frame(width: 1, height: plotHeight)
                        .offset(x: slot * CGFloat(i))
                    }

                    ForEach(marks(week)) { run in
                        runMark(run, week: week)
                            .offset(x: xOffset(run, slot: slot,
                                               width: markWidth(run, week: week)))
                    }

                    ForEach(week.days.filter { $0.niggle != nil && !$0.runs.isEmpty }) { day in
                        // Hangs above whatever this mode actually drew, or the
                        // caret floats over empty axis in MILES.
                        let anchor = (metric == .load ? day.runs[0] : day.dayMark) ?? day.runs[0]
                        let w = markWidth(anchor, week: week)
                        NiggleMark()
                            .fill(Color.drip.coral)
                            .frame(width: 8, height: 5)
                            .offset(x: xOffset(anchor, slot: slot, width: w) + (w - 8) / 2,
                                    y: -(markHeight(anchor, week: week) + 4))
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
            }
            .frame(height: plotHeight)

            // The axis. One hairline, in secondary ink so it reads as a
            // baseline rather than as a border around a box.
            Rectangle()
                .fill(Color.drip.textTertiary)
                .frame(height: 1)

            dayRail(week)
        }
        .padding(.top, 40)
    }

    /// Bottom-left x for a run's bar. The `slot - barWidth` inset is what stops
    /// an 11pm run overhanging into the next day; an unplaceable run is centered
    /// rather than defaulted to midnight.
    private func xOffset(_ run: StressRun, slot: CGFloat, width: CGFloat) -> CGFloat {
        let base = CGFloat(run.dayIndex) * slot
        let usable = max(0, slot - width)
        guard let minute = run.minuteOfDay else { return base + usable / 2 }
        return base + CGFloat(minute) / 1440 * usable
    }

    /// A run's pie diameter. MIRRORS `ZoneVolumePie.diameter` — radius scales
    /// as √(miles ÷ biggest), so AREA carries the number and an 18-miler reads
    /// as three times a 6, not nine. The pie sizes itself from the same inputs;
    /// this copy exists because the strip has to know the width BEFORE it can
    /// place the mark on the time axis. If that formula ever changes, both move.
    private func pieDiameter(_ run: StressRun, week: StripWeek) -> CGFloat {
        let m = run.miles
        guard m > 0, week.maxRunMiles > 0 else { return 0 }
        return maxPieDiameter * CGFloat((m / week.maxRunMiles).squareRoot())
    }

    /// What the axis draws, per mode. TLS keeps one bar per SESSION — its
    /// encoding is when the effort landed, and a double has to read as two
    /// efforts. MILES draws one circle per DAY, area = the day's whole
    /// distance. See `StripDay.dayMark`.
    private func marks(_ week: StripWeek) -> [StressRun] {
        metric == .load ? week.allRuns : week.days.compactMap(\.dayMark)
    }

    /// The mark's footprint on the time axis. A bar is a fixed 11pt; a pie is
    /// as wide as it is big, so the inset that keeps an 11pm run inside its own
    /// day has to be computed per run rather than taken from a constant.
    private func markWidth(_ run: StressRun, week: StripWeek) -> CGFloat {
        metric == .load ? barWidth : max(pieDiameter(run, week: week), stubHeight)
    }

    /// How far the mark rises off the axis — what the niggle caret hangs above.
    private func markHeight(_ run: StressRun, week: StripWeek) -> CGFloat {
        metric == .load ? barHeight(run, week: week) : markWidth(run, week: week)
    }

    private func barHeight(_ run: StressRun, week: StripWeek) -> CGFloat {
        let v = run.value(metric)
        guard v > 0 else { return stubHeight }
        let usable = plotHeight - headRoom
        return max(minBarHeight, usable * CGFloat(v / week.maxRun(metric)))
    }

    /// One run on the axis. Both modes share the tap target, the selection
    /// ring and the voice label — only the mark itself changes, so switching
    /// TLS↔MILES never moves what is tappable or what VoiceOver reads.
    @ViewBuilder
    private func runMark(_ run: StressRun, week: StripWeek) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                selected = selected == run.id ? nil : run.id
            }
        } label: {
            Group {
                if metric == .load { loadBar(run, week: week) }
                else { volumePie(run, week: week) }
            }
            // Padded before the shape is taken, so a 10pt mark is not a 10pt
            // tap target. NEGATIVE leading inset cancels it for LAYOUT: the
            // caller offsets this button by the run's time position, and 6pt of
            // padding inside it would push every mark 6pt later in the day
            // while defeating the `slot - width` inset that keeps an 11pm run
            // out of the next day. The touch area still grows; only the drawn
            // position stays honest.
            .padding(.horizontal, 6)
            .padding(.leading, -6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(run.voiceLabel)
        .accessibilityHint("Opens the pace breakdown")
    }

    /// MILES mode. AREA — not radius — is the miles, so an 18-miler reads as
    /// three times a 6 rather than nine; `ZoneVolumePie` has owned that maths
    /// since the circles row and owns it still. The wedges are the pace split,
    /// so a long easy day and a short session of the same distance are the
    /// same size and visibly different colours.
    ///
    /// A run whose miles are only partly classified draws its FULL size with
    /// wedges for the part we know: the disc is the distance, which is not in
    /// doubt, and composition is only ever claimed for what was classified.
    @ViewBuilder
    private func volumePie(_ run: StressRun, week: StripWeek) -> some View {
        let d = max(pieDiameter(run, week: week), stubHeight)
        Group {
            if run.hasZones {
                ZoneVolumePie(
                    slices: run.zones.map {
                        .init(token: $0.token, miles: $0.miles,
                              color: ZoneTaxonomy.color($0.token))
                    },
                    miles: run.miles,
                    maxMiles: week.maxRunMiles,
                    maxDiameter: maxPieDiameter
                )
            } else {
                // Ran, no breakdown. The same dashed outline the bar uses, so
                // both modes say "we don't know how" in the same language.
                Circle()
                    .fill(Color.drip.paperDeep.opacity(0.6))
                    .overlay {
                        Circle().strokeBorder(Color.drip.textTertiary,
                                              style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                    }
                    .frame(width: d, height: d)
            }
        }
        .overlay {
            if selected == run.id {
                // INK, never coral — coral is the alert palette and must not
                // sit on a pace mark.
                Circle().strokeBorder(Color.drip.textPrimary, lineWidth: 1.5)
            }
        }
    }

    /// TLS mode. Unchanged from the original strip: height is the load, the
    /// fill is the pace zones with easy at the base.
    @ViewBuilder
    private func loadBar(_ run: StressRun, week: StripWeek) -> some View {
        let h = barHeight(run, week: week)
        Group {
            if run.hasZones {
                // First child is TOP in a VStack, so iterate fastest →
                // slowest to land easy at the base.
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
                // would be a height, and a height on this chart is a claim
                // about load that there is no data to make.
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.drip.paperDeep.opacity(0.6))
                    .overlay {
                        RoundedRectangle(cornerRadius: 2)
                            .strokeBorder(Color.drip.textTertiary,
                                          style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                    }
            }
        }
        .frame(width: barWidth, height: h)
        .overlay {
            if selected == run.id {
                RoundedRectangle(cornerRadius: 2)
                    // Selection is INK, never coral — coral is the alert
                    // palette and must not sit on a pace fill.
                    .strokeBorder(Color.drip.textPrimary, lineWidth: 1.5)
            }
        }
    }

    /// Seven equal cells sharing the plot's baseline: day, its total load, mood.
    private func dayRail(_ week: StripWeek) -> some View {
        HStack(spacing: 0) {
            ForEach(week.days) { d in
                VStack(spacing: 0) {
                    Text(dayLabel(d))
                        .font(.dripEyebrow(eyebrowSmall)).tracking(1.2)
                        .foregroundStyle(d.isFuture ? Color.drip.textTertiary.opacity(0.5)
                                         : d.ran ? Color.drip.textSecondary
                                                 : Color.drip.textTertiary)
                        .padding(.top, 16)

                    // A future day shows NOTHING, not "0" — it has not had the
                    // chance to be zero yet. A rest day shows a real 0, because
                    // a zero is a fact and not a placeholder (hard rule #8: no
                    // em-dashes standing in for absent values).
                    Text(d.isFuture ? " "
                         : metric == .load ? "\(Int(d.load.rounded()))"
                                           : fmtMiles(d.miles))
                        .font(.dripStat(eyebrowSmall + 2))
                        .foregroundStyle(d.value(metric) > 0 ? Color.drip.textPrimary
                                                              : Color.drip.textTertiary)
                        .padding(.top, 8)

                    // The share of the week, in MILES mode. ALWAYS emitted —
                    // a blank where it does not apply, never a dropped row —
                    // so the mood capsules below stay on one line across all
                    // seven columns instead of stepping up under the rest days.
                    Text(shareLabel(d, week: week))
                        .font(.dripEyebrow(eyebrowMicro)).tracking(0.9)
                        .foregroundStyle(Color.drip.textTertiary)
                        .padding(.top, 4)

                    Capsule()
                        .fill(d.mood.flatMap { Self.moodColor($0) } ?? Color.clear)
                        .frame(width: 13, height: 2.5)
                        .padding(.top, 8)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(d.railVoiceLabel)
            }
        }
    }

    /// A day's share of the week's miles. MILES mode only: the pies are sized
    /// against the biggest RUN, which answers "which was the big one" but not
    /// "how much of my week was that" — and the second question is the one a
    /// volume athlete actually asks.
    ///
    /// A space, not "0%" and not an em-dash, where it does not apply: a future
    /// day has not had the chance to be a share of anything yet, and hard rule
    /// #8 forbids a dash standing in for an absent value.
    private func shareLabel(_ d: StripDay, week: StripWeek) -> String {
        guard metric == .volume, !d.isFuture, week.miles > 0, d.miles > 0
        else { return " " }
        return "\(Int((d.miles / week.miles * 100).rounded()))%"
    }

    /// Three letters normally, one initial at the largest accessibility sizes.
    /// Seven three-letter labels do not fit across a phone at AX3+, and the
    /// alternatives — shrinking under the 9pt floor, or truncating "WED" to
    /// "WE…" — are both worse than the conventional calendar initial.
    private func dayLabel(_ d: StripDay) -> String {
        typeSize >= .accessibility1
            ? String(d.label.prefix(1))
            : d.label
    }

    /// Says what the marks on screen actually encode. MILES no longer places
    /// anything in time — one circle per day, centered — so the sentence about
    /// early and late would be describing a chart that is not there.
    private var axisNote: some View {
        Text(metric == .load
             ? "Each slot is one day, midnight to midnight. A bar sits where the run "
               + "happened in it — left is early, right is late."
             : "One circle per day. Its area is everything you ran that day, "
               + "split into the paces you ran it at.")
            .font(.system(size: 12.5, design: .serif).italic())
            .foregroundStyle(Color.drip.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 24)
    }

    // MARK: The run panel

    @ViewBuilder
    private func runPanel(_ run: StressRun, week: StripWeek) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Hairline()
                .padding(.top, 8)

            HStack(alignment: .firstTextBaseline) {
                // The part of day is what the POSITION claimed; the clock time
                // is the fact, and it lives here rather than on the axis.
                Text(run.whenLabel.uppercased())
                    .font(.dripEyebrow(eyebrowSmall)).tracking(1.2)
                    .foregroundStyle(Color.drip.textSecondary)
                Spacer()
                Button { onOpenDay(run.date) } label: {
                    Text("OPEN DAY ↗")
                        .font(.dripEyebrow(eyebrowMicro)).tracking(1.1)
                        .foregroundStyle(Color.drip.coral)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 20)
            .padding(.bottom, 12)

            statLine(run)

            if run.hasZones {
                VStack(spacing: 0) {
                    ForEach(run.zones) { z in
                        zoneRow(z)
                    }
                }
                .padding(.top, 16)

                // The athlete stopped their watch mid-session; the bar did
                // not. Worth one line, because the duration above is the sum of
                // the pieces and will not match any single upload in the Log.
                if run.pieceCount > 1 {
                    Text("\(run.pieceCount) uploads folded into one run — "
                         + "warm-up, session and cool-down are the same run.")
                        .font(.system(size: 12, design: .serif).italic())
                        .foregroundStyle(Color.drip.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 12)
                }

                // Said plainly rather than left to be inferred from a bar that
                // is centered for no visible reason.
                if run.isDayRollup {
                    Text("This is the whole day, not one run — start times "
                         + "aren't available for it yet, so the bar sits in the "
                         + "middle of the slot instead of at an hour.")
                        .font(.system(size: 12, design: .serif).italic())
                        .foregroundStyle(Color.drip.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 12)
                }

                if run.hasUnclassified {
                    Text("\(fmtMiles(run.unclassifiedMiles)) mi came in without a pace "
                         + "zone — counted in the distance, not in the load score.")
                        .font(.system(size: 12, design: .serif).italic())
                        .foregroundStyle(Color.drip.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 12)
                }
            } else {
                Text(run.minuteOfDay == nil
                     ? "This run arrived without a start time or splits, so it cannot be "
                       + "placed in the day and has no load score. Its "
                       + "\(fmtMiles(run.miles)) miles still count toward the week."
                     : "This run arrived without splits, so there is no pace breakdown "
                       + "and no load score for it. The \(fmtMiles(run.miles)) miles "
                       + "still count toward the week.")
                    .font(.system(size: 13, design: .serif).italic())
                    .foregroundStyle(Color.drip.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
            }

            if let n = week.days[run.dayIndex].niggle {
                HStack(alignment: .top, spacing: 8) {
                    NiggleCaretUp()
                        .fill(Color.drip.coral)
                        .frame(width: 9, height: 7)
                        .padding(.top, 5)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(Self.bodyPart(n).uppercased())
                            .font(.dripEyebrow(eyebrowMicro)).tracking(1.0)
                            .foregroundStyle(Color.drip.coralDeep)
                        // Verbatim, always. Surface, never diagnose.
                        Text("“\(n.quote)”")
                            .font(.system(size: 13.5, design: .serif).italic())
                            .foregroundStyle(Color.drip.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, 16)
            }
        }
    }

    /// `10.7mi · 1:16 · 187TLS`. The load number is the one tappable thing —
    /// coral on "TLS" is the whole affordance, the same color that means "this
    /// opens something" on "OPEN DAY ↗" one row up.
    private func statLine(_ run: StressRun) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(fmtMiles(run.miles)).font(.dripStat(17))
            Text("mi").font(.dripStat(11)).foregroundStyle(Color.drip.textSecondary)
            sep()
            Text(Self.fmtDuration(run.timeSec)).font(.dripStat(17))
            if run.load > 0 {
                sep()
                Button { explainingLoad = true } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text("\(Int(run.load.rounded()))")
                            .font(.dripStat(17))
                            .foregroundStyle(Color.drip.textPrimary)
                        Text("TLS")
                            .font(.dripStat(11))
                            .foregroundStyle(Color.drip.coral)
                    }
                    .padding(.vertical, 6)
                    .padding(.trailing, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(Int(run.load.rounded())) training load score")
                .accessibilityHint("Explains how the score is calculated")
            }
            Spacer()
        }
        .foregroundStyle(Color.drip.textPrimary)
        .sheet(isPresented: $explainingLoad) {
            // The explainer still speaks `LoadDay`, which `WeekTrainingLoadSection`
            // owns. Handing it a run-shaped one keeps a single explainer for the
            // whole app rather than forking a near-identical screen.
            TrainingLoadExplainer(day: run.asLoadDay)
        }
    }

    private func sep() -> some View {
        Text(" · ")
            .font(.dripStat(13))
            .foregroundStyle(Color.drip.textTertiary)
    }

    /// Swatch, zone, minutes, pace. MINUTES rather than miles, because on this
    /// surface minutes are what the bar is made of — height is minutes × weight,
    /// and a table in miles would not visibly add up to the picture above it.
    private func zoneRow(_ z: StripZone) -> some View {
        VStack(spacing: 0) {
            Hairline()
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(ZoneTaxonomy.color(z.token))
                    .frame(width: 8, height: 15)
                Text(ZoneTaxonomy.label(z.token))
                    .font(.dripEyebrow(eyebrowSmall)).tracking(0.9)
                    .foregroundStyle(Color.drip.textSecondary)
                    .padding(.leading, 8)
                Spacer()
                Text(Self.fmtDuration(z.minutes * 60))
                    .font(.dripStat(eyebrowSmall + 2))
                    .foregroundStyle(Color.drip.textPrimary)
                // The multiplier this zone's minutes ACTUALLY earned, not the
                // table's anchor for it. A `mile` bucket holding a 200 at 4:20
                // reads x8.6 here, which is the honest number and the only
                // place the athlete can see the curve at work.
                Text("×\(fmtMultiplier(z.effectiveWeight))")
                    .font(.dripStat(eyebrowSmall + 1))
                    .foregroundStyle(Color.drip.textTertiary)
                    .frame(width: 44, alignment: .trailing)
                Text(z.avgPaceSec.map { "\(fmtPace($0))/mi" } ?? "")
                    .font(.dripStat(eyebrowSmall + 2))
                    .foregroundStyle(Color.drip.textPrimary)
                    .frame(width: 82, alignment: .trailing)
            }
            .padding(.vertical, 9)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(ZoneTaxonomy.label(z.token)), \(Self.fmtDuration(z.minutes * 60))"
            + (z.avgPaceSec.map { ", averaging \(fmtPace($0)) per mile" } ?? "")
        )
    }

    // MARK: The legend

    /// The ramp drawn as a LADDER: bar height is what a minute in that zone
    /// costs. Flat equal-height swatches named the colors and said nothing
    /// about intensity, which is the whole thing the chart above encodes — so
    /// the legend now teaches color and scale in one graphic.
    ///
    /// The dashed cap over `mile` is not decoration. Mile is the top ANCHOR at
    /// x8, not a ceiling: the backend weights each bout on a continuous curve
    /// that keeps climbing past it, so a 200 at 4:20/mi outscores a mile rep at
    /// 4:50 instead of both flattening to 8. A ladder that simply stopped at
    /// mile would say the opposite.
    private var legend: some View {
        let anchorHeight: CGFloat = 44          // x8 — the mile anchor
        let ladderHeight: CGFloat = 62          // room above it for ">8"

        return VStack(alignment: .leading, spacing: 0) {
            Hairline().padding(.top, 32)

            Text("THE PACE SPECTRUM · WHAT A MINUTE COSTS")
                .font(.dripEyebrow(eyebrowMicro)).tracking(1.1)
                .foregroundStyle(Color.drip.textTertiary)
                .padding(.top, 20)

            HStack(alignment: .bottom, spacing: 2) {
                ForEach(ZoneTaxonomy.ordered, id: \.self) { token in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(ZoneTaxonomy.color(token))
                        .frame(height: max(4, anchorHeight
                                           * TrendsZoneWeight.weight(token) / maxAnchorWeight))
                }
            }
            .frame(height: ladderHeight, alignment: .bottom)
            .overlay(alignment: .topTrailing) { pastMile(anchorHeight: anchorHeight) }
            .padding(.top, 12)

            HStack {
                Text("EASY ×1")
                Spacer()
                Text("MILE ×\(fmtMultiplier(maxAnchorWeight))")
            }
            .font(.dripEyebrow(eyebrowMicro)).tracking(1.1)
            .foregroundStyle(Color.drip.textTertiary)
            .padding(.top, 8)

            Text("Color is the pace. " + metric.heightSentence
                 + "\(fmtWeightRatio())× "
                 + (metric == .load ? "taller than ten minutes easy."
                                    : "what ten minutes easy costs.")
                 + " Mile is the top anchor at ×\(fmtMultiplier(maxAnchorWeight)); "
                 + "anything faster keeps climbing above it.")
                .font(.system(size: 12.5, design: .serif))
                .foregroundStyle(Color.drip.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "The pace spectrum. Bar height is what a minute at that pace costs, "
            + "from easy at 1 times to mile at \(fmtMultiplier(maxAnchorWeight)) "
            + "times. Faster than mile scores above that."
        )
    }

    /// The ">8" cap: a dashed stem rising off the mile bar. Sized to one
    /// column so it sits over `mile` rather than floating at the plot edge.
    private func pastMile(anchorHeight: CGFloat) -> some View {
        VStack(spacing: 2) {
            Text(">\(fmtMultiplier(maxAnchorWeight))")
                .font(.dripEyebrow(eyebrowMicro))
                .foregroundStyle(Color.drip.textSecondary)
                .fixedSize()
            Path { p in
                p.move(to: .zero)
                p.addLine(to: CGPoint(x: 0, y: 7))
            }
            .stroke(Color.drip.textTertiary,
                    style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
            .frame(width: 1, height: 7)
        }
        .allowsHitTesting(false)
    }

    /// The heaviest anchor in the table, read rather than hardcoded — it moved
    /// once already (2026-08-11) and the legend must not be the thing that
    /// disagrees with the maths.
    private var maxAnchorWeight: Double {
        ZoneTaxonomy.ordered.map { TrendsZoneWeight.weight($0) }.max() ?? 8
    }

    /// Read off the table rather than written into the copy, so the sentence
    /// cannot outlive a reweight. (It changed on 2026-08-11.)
    private func fmtWeightRatio() -> String {
        let r = TrendsZoneWeight.weight("5k") / TrendsZoneWeight.weight("easy")
        return r == r.rounded() ? "\(Int(r))" : String(format: "%.1f", r)
    }

    // MARK: - Model

    /// The two questions this chart can answer. They are genuinely different
    /// weeks: a 20-mile easy Saturday is the biggest bar by volume and a
    /// mid-sized one by load, and a 6-mile session is the reverse. Color stays
    /// the pace spectrum in both — only the height changes meaning.
    enum StripMetric: String {
        case load, volume

        var short: String { self == .load ? "TLS" : "MILES" }
        var unit: String { self == .load ? "TLS" : "mi" }
        /// What the legend says height means.
        var heightSentence: String {
            self == .load
                ? "Height is the load — minutes weighted by what a minute at "
                  + "that pace costs, so ten minutes at 5K stands "
                : "Height is the distance. Switch to TLS to weight it by how "
                  + "hard those miles were — ten minutes at 5K costs "
        }
    }

    struct StripZone: Identifiable {
        var id: String { token }
        let token: String
        let minutes: Double
        let miles: Double
        let load: Double
        func value(_ m: StripMetric) -> Double { m == .load ? load : miles }
        /// Load ÷ minutes — what a minute in this zone cost on THIS run. Equal
        /// to the table anchor when every bout sat on it, and above it when the
        /// work was faster than the anchor (past mile, above 8).
        var effectiveWeight: Double { minutes > 0 ? load / minutes : 0 }
        /// Σ time ÷ Σ distance — a real average, not a mean of means.
        var avgPaceSec: Double? { miles > 0 ? minutes * 60 / miles : nil }
    }

    struct StressRun: Identifiable {
        let id: UUID
        let dayIndex: Int
        let date: Date
        let dayLabel: String
        /// Minutes past local midnight, or nil when the run cannot be placed —
        /// no start time in the payload. Nil renders centered and hatched.
        let minuteOfDay: Int?
        let partOfDay: String?
        let clockLabel: String?
        let miles: Double
        /// Wall-clock seconds — see `fmtDuration`.
        let timeSec: Double
        let zones: [StripZone]
        let load: Double
        /// Uploads folded into this bar — 3 for the usual warm-up / reps /
        /// cool-down trio. `var` with a default so the two tiers that cannot
        /// know it keep the memberwise init they already had.
        var pieceCount: Int = 1
        /// True when this bar is a WHOLE DAY standing in for its runs, because
        /// `days[].runs` was not in the payload. It carries a real load and a
        /// real zone stack — just no time, so it sits centered. A day with two
        /// runs shows one bar in this mode.
        let isDayRollup: Bool

        var hasZones: Bool { !zones.isEmpty }
        /// What this bar is TALL by. Volume is knowable for a run with no lap
        /// data — the miles are on the row — which is why the volume view has
        /// one fewer unknown than the load view.
        func value(_ m: StripMetric) -> Double { m == .load ? load : miles }
        var zonedMiles: Double { zones.reduce(0) { $0 + $1.miles } }
        var unclassifiedMiles: Double { max(0, miles - zonedMiles) }
        /// A tenth of a mile of rounding slop is not worth a sentence.
        var hasUnclassified: Bool { unclassifiedMiles > 0.1 }

        /// "Tue Aug 4 · Morning, 6:05am", degrading gracefully when there is no
        /// time to report.
        var whenLabel: String {
            guard let part = partOfDay, let clock = clockLabel else {
                return isDayRollup ? "\(dayLabel) · whole day"
                                   : "\(dayLabel) · time not recorded"
            }
            return "\(dayLabel) · \(part), \(clock)"
        }

        /// Says "morning", not "6:05am" — matching what the bar's position
        /// actually encodes. The exact time is read in the panel.
        var voiceLabel: String {
            var s = "\(dayLabel)"
            if let part = partOfDay { s += " \(part.lowercased())" }
            else if isDayRollup { s += ", whole day" }
            s += ". \(String(format: "%.1f", miles)) miles. "
            if zones.isEmpty {
                s += "No pace breakdown available."
                return s
            }
            s += "Training load \(Int(load.rounded())). "
            s += zones.map {
                "\(WeekStressStripSection.fmtDuration($0.minutes * 60)) \(ZoneTaxonomy.label($0.token))"
            }.joined(separator: ", ") + "."
            return s
        }

        /// A `LoadDay` shaped from this run, for `TrainingLoadExplainer`. The
        /// label is the run's own so the explainer's worked example is headed
        /// with what was tapped.
        var asLoadDay: WeekTrainingLoadSection.LoadDay {
            WeekTrainingLoadSection.LoadDay(
                date: date,
                label: partOfDay.map { "\(dayLabel) \($0.lowercased())" } ?? dayLabel,
                miles: miles,
                minutes: zones.reduce(0) { $0 + $1.minutes },
                zones: zones.map {
                    WeekTrainingLoadSection.ZoneTotal(
                        token: $0.token, miles: $0.miles,
                        minutes: $0.minutes, load: $0.load
                    )
                },
                load: load,
                timeMin: timeSec / 60,
                zonedMiles: zonedMiles,
                mood: nil,
                niggle: nil,
                isRest: false,
                isFuture: false
            )
        }
    }

    struct StripDay: Identifiable {
        /// The DAY, not a fresh UUID. `model()` runs on every body pass, so a
        /// minted id gave all seven columns a new identity each time — SwiftUI
        /// tore down and rebuilt the rail on every state change, which fought
        /// the week-nav transitions it is supposed to animate.
        var id: Date { date }
        let date: Date
        let label: String
        let miles: Double
        let load: Double
        func value(_ m: StripMetric) -> Double { m == .load ? load : miles }
        let runs: [StressRun]
        let mood: String?
        let niggle: TrendsDay.DayNiggle?
        /// Overnight resting heart rate, from `daily_biometrics` via the
        /// timeline payload. Nil on a day with no reading — a gap in the line,
        /// never an interpolated point: a resting HR the athlete did not
        /// record is not a number this app gets to invent.
        let restingHr: Double?
        let isRest: Bool
        let isFuture: Bool
        var ran: Bool { miles > 0 }

        /// The day folded to ONE mark — what MILES mode draws.
        ///
        /// Volume is the one quantity here that genuinely adds up: two runs on
        /// a Thursday are 15 miles of Thursday, and two overlapping discs read
        /// as neither run's distance nor as the day's. Load does not fold the
        /// same way — its whole encoding is *when* the effort landed — so TLS
        /// keeps one bar per session and a double still reads as two efforts.
        ///
        /// Centered, because a day total has no time of day. Placing the fold
        /// at the first run's hour would claim a position the number no longer
        /// carries.
        var dayMark: StressRun? {
            guard !runs.isEmpty else { return nil }
            var byToken: [String: (min: Double, mi: Double, load: Double)] = [:]
            for r in runs {
                for z in r.zones {
                    let cur = byToken[z.token] ?? (0, 0, 0)
                    byToken[z.token] = (cur.min + z.minutes, cur.mi + z.miles, cur.load + z.load)
                }
            }
            // The per-run zones are already normalised and load-resolved by
            // `zones(minutes:miles:load:)`; summing them needs neither again.
            // Same ordering as everywhere else — easy at the base.
            let folded = byToken
                .map { StripZone(token: $0.key, minutes: $0.value.min,
                                 miles: $0.value.mi, load: $0.value.load) }
                .filter { $0.minutes > 0 }
                .sorted { ZoneTaxonomy.rank($0.token) < ZoneTaxonomy.rank($1.token) }
            return StressRun(
                id: WeekStressStripSection.stableID(date),
                dayIndex: runs[0].dayIndex,
                date: date,
                dayLabel: label,
                minuteOfDay: nil,          // centered — see above
                partOfDay: nil,
                clockLabel: nil,
                miles: miles,
                timeSec: runs.reduce(0) { $0 + $1.timeSec },
                zones: folded,
                load: runs.reduce(0) { $0 + $1.load },
                pieceCount: runs.reduce(0) { $0 + $1.pieceCount },
                isDayRollup: true
            )
        }

        var railVoiceLabel: String {
            if isFuture { return "\(label), upcoming." }
            if !ran { return "\(label), rest day." }
            if load <= 0 { return "\(label), ran, no load score available." }
            return "\(label), total training load \(Int(load.rounded()))."
        }
    }

    struct StripWeek {
        let days: [StripDay]
        let allRuns: [StressRun]
        let miles: Double
        let load: Double
        let timeSec: Double
        let runDays: Int
        /// The tallest bar's load. Bars scale to THIS WEEK's peak, so a heavy
        /// week and a recovery week both use the full plot. The absolute
        /// comparison is the day rail's numbers; a fixed ceiling across all
        /// weeks would render a down week as a row of stubs.
        let maxRunLoad: Double
        /// The biggest DAY's miles — MILES mode draws one circle per day, so
        /// the scale ceiling has to be a day too. Scaling day circles against
        /// the biggest single RUN is how the fold overflowed: a 15-mile
        /// Thursday built from an 11 and a 4 divided by an 11-mile ceiling
        /// asks for √1.36 of the maximum diameter and blows the slot.
        let maxRunMiles: Double
        func maxRun(_ m: StripMetric) -> Double {
            max(m == .load ? maxRunLoad : maxRunMiles, 0.0001)
        }
    }

    /// The week on screen. Kept as the no-argument call every existing caller
    /// already makes.
    private func model() -> StripWeek { model(weeksAgo: weekOffset) }

    /// ANY week, so the expanded sheet can also ask for the one before it and
    /// draw the comparison. Still the single place a week is assembled — the
    /// sheet renders what this returns and never derives a week itself.
    private func model(weeksAgo: Int) -> StripWeek {
        let start = vm.weekStart(weeksAgo: weeksAgo)
        let scaffold = vm.dayVolumes(forWeekStart: start)

        // `TrendsDay` is keyed by a "yyyy-MM-dd" UTC day string; we match on the
        // athlete's own calendar date, which is what the slot is labeled with.
        // Day-level METADATA (mood, niggle, resting HR, the zone rollup) still
        // comes from that key — it is a property of the payload's day, and no
        // better answer exists for it here.
        let byDate = Dictionary(
            trends.days.map { ($0.date, $0) },
            uniquingKeysWith: { a, _ in a }
        )

        // RUNS, though, are filed by the athlete's OWN day (`Run.localDay`),
        // not by the key they arrived under. This was the section's documented
        // known edge and it is a real one: a run at 7:26pm Chicago is 00:26Z
        // the next day, so it drew late on THURSDAY while the list directly
        // above the chart — which buckets locally — had it on Wednesday. Two
        // surfaces on one screen, 4 miles apart, both claiming to be the week.
        //
        // Sessions are folded per payload-day first (`sessions(from:)` joins a
        // warm-up / reps / cool-down trio) and only then re-filed, so folding
        // still sees the pieces the backend grouped together.
        let runsByLocalDay = Dictionary(
            grouping: trends.days.flatMap { TrendsDay.sessions(from: $0.runs) },
            by: { Self.isoKey($0.localDay) }
        )

        var days: [StripDay] = []
        var allRuns: [StressRun] = []

        for (i, dv) in scaffold.enumerated() {
            let td = byDate[Self.isoKey(dv.date)]
            let localRuns = runsByLocalDay[Self.isoKey(dv.date)] ?? []
            // When we have the runs, the day's mileage is THEIR sum — the
            // payload's `day.miles` is a UTC-day total, and after re-filing it
            // would describe a different set of runs than the marks drawn.
            let dayMiles = localRuns.isEmpty
                ? (td?.miles ?? dv.split.total)
                : localRuns.reduce(0) { $0 + $1.miles }
            var runs: [StressRun] = []

            // Three tiers, best first. The point of the ladder is that the
            // section degrades in ONE dimension at a time instead of collapsing
            // to nothing: lose the start times and you still have the load;
            // lose the laps too and you still have a mark saying a run happened.
            if !localRuns.isEmpty {
                // 1 · Per-session. Already folded above — a track Tuesday is
                // one bar and not three stacked on top of each other, and a
                // genuine double still splits (see `sessions(from:)`).
                for r in localRuns {
                    runs.append(Self.stressRun(
                        from: r, dayIndex: i, date: dv.date, dayLabel: dv.label
                    ))
                }
            } else if let payload = td, payload.hasZoneBreakdown {
                // 2 · The DAY, standing in for its runs. `days[].runs` is not in
                // this payload — an older deploy — but `zone_minutes` is, and it
                // has been shipping since 2026-08-10. Dropping it on the floor
                // was the bug that made this section render a fully-populated
                // week as "0 TLS": the load was right there and unused.
                //
                // The bar is real in height and color and carries no time, so
                // it sits centered. A double collapses to one bar here, which is
                // exactly the limitation the `runs` field exists to remove.
                runs.append(Self.dayRollupRun(
                    zoneMinutes: payload.zoneMinutes ?? [:],
                    zoneMiles: payload.zoneMiles ?? [:],
                    zoneLoad: payload.zoneLoad,
                    dayIndex: i, date: dv.date, dayLabel: dv.label,
                    miles: dayMiles, durationMin: Double(payload.durationMin ?? 0)
                ))
            } else if dayMiles > 0 {
                // 3 · Ran, and we cannot say a thing about how. One unplaceable
                // stub rather than nothing, because rendering a run day as a
                // rest day is the one outcome that is actually wrong.
                runs.append(StressRun(
                    id: Self.stableID(dv.date), dayIndex: i, date: dv.date, dayLabel: dv.label,
                    minuteOfDay: nil, partOfDay: nil, clockLabel: nil,
                    miles: dayMiles, timeSec: Double(td?.durationMin ?? 0) * 60,
                    zones: [], load: 0, isDayRollup: false
                ))
            }

            allRuns.append(contentsOf: runs)
            days.append(StripDay(
                date: dv.date,
                label: dv.label,
                miles: dayMiles,
                load: runs.reduce(0) { $0 + $1.load },
                runs: runs,
                mood: td?.mood,
                niggle: td?.niggles.first,
                restingHr: td?.restingHr,
                isRest: dv.isRest || (!dv.isFuture && dayMiles <= 0),
                isFuture: dv.isFuture
            ))
        }

        return StripWeek(
            days: days,
            allRuns: allRuns,
            miles: days.reduce(0) { $0 + $1.miles },
            load: days.reduce(0) { $0 + $1.load },
            timeSec: allRuns.reduce(0) { $0 + $1.timeSec },
            runDays: days.filter { $0.ran }.count,
            maxRunLoad: max(allRuns.map(\.load).max() ?? 0, 0.0001),
            maxRunMiles: max(days.map(\.miles).max() ?? 0, 0.0001)
        )
    }

    /// One payload run → one bar's worth of model. Zones are folded through
    /// `ZoneTaxonomy.normalise` (recovery → easy) before totalling, so the
    /// display vocabulary matches the ramp, and the load comes from
    /// `QualityLoad` rather than a local multiplication — that table is already
    /// mirrored once from `workoutSegmentation.ts` and a second copy here would
    /// be a third place to drift.
    private static func stressRun(from r: TrendsDay.Run,
                                  dayIndex: Int,
                                  date: Date,
                                  dayLabel: String) -> StressRun {
        let zones = Self.zones(minutes: r.zoneMinutes ?? [:],
                               miles: r.zoneMiles ?? [:], load: r.zoneLoad)
        let zonedMin = zones.reduce(0.0) { $0 + $1.minutes }
        return StressRun(
            id: r.id,
            dayIndex: dayIndex,
            date: date,
            dayLabel: dayLabel,
            minuteOfDay: r.minuteOfDay,
            partOfDay: r.partOfDay,
            clockLabel: r.clockLabel,
            miles: r.miles,
            // WALL CLOCK WINS, same as the circles row: when the segmenter
            // classifies only part of a run, the zoned figure understates the
            // run badly enough that the athlete cannot reconcile it. `zones`
            // keeps the zoned minutes for the pace maths, where it is the
            // correct denominator.
            timeSec: r.durationSec > 0 ? r.durationSec : zonedMin * 60,
            zones: zones,
            load: zones.reduce(0) { $0 + $1.load },
            pieceCount: r.pieceCount,
            isDayRollup: false
        )
    }

    /// Tier 2 of the ladder: the day's own zone breakdown as a single centered
    /// bar. Same maths, same taxonomy folding — only the placement is missing.
    private static func dayRollupRun(zoneMinutes: [String: Double],
                                     zoneMiles: [String: Double],
                                     zoneLoad: [String: Double]?,
                                     dayIndex: Int,
                                     date: Date,
                                     dayLabel: String,
                                     miles: Double,
                                     durationMin: Double) -> StressRun {
        let zones = Self.zones(minutes: zoneMinutes, miles: zoneMiles, load: zoneLoad)
        let zonedMin = zones.reduce(0.0) { $0 + $1.minutes }
        return StressRun(
            id: stableID(date),
            dayIndex: dayIndex,
            date: date,
            dayLabel: dayLabel,
            minuteOfDay: nil,
            partOfDay: nil,
            clockLabel: nil,
            miles: miles,
            timeSec: durationMin > 0 ? durationMin * 60 : zonedMin * 60,
            zones: zones,
            load: zones.reduce(0) { $0 + $1.load },
            isDayRollup: true
        )
    }

    /// Raw zone map → display rows. `recovery` is folded into `easy` before
    /// totalling so the vocabulary matches the ramp, and the load comes from
    /// `QualityLoad` rather than a local multiplication — that weight table is
    /// already mirrored once from `workoutSegmentation.ts` and a second copy
    /// here would be a third place to drift.
    private static func zones(minutes: [String: Double],
                              miles: [String: Double],
                              load: [String: Double]?) -> [StripZone] {
        var mins: [String: Double] = [:]
        var mis: [String: Double] = [:]
        var lds: [String: Double] = [:]
        for (raw, m) in minutes {
            let t = ZoneTaxonomy.normalise(raw)
            mins[t, default: 0] += m
            mis[t, default: 0] += (miles[raw] ?? 0)
            lds[t, default: 0] += (load?[raw] ?? 0)
        }
        return mins.map { token, m in
            // The server's per-bout figure when it sent one. `QualityLoad` is
            // the fallback for payloads predating `zone_load`, and it is a
            // FLOOR, not an equal: it evaluates the discrete table, so a
            // sub-mile rep caps at x8 where the curve carries it past.
            let served = lds[token] ?? 0
            return StripZone(
                token: token, minutes: m, miles: mis[token] ?? 0,
                load: served > 0 ? served
                                 : QualityLoad.score(workSeconds: m * 60, zone: token)
            )
        }
        .filter { $0.minutes > 0 }
        .sorted { ZoneTaxonomy.rank($0.token) < ZoneTaxonomy.rank($1.token) }
    }

    // MARK: - Formatting

    /// A run id that is THE SAME on every `model()` call for a given day.
    ///
    /// Tiers 2 and 3 have no payload id to borrow — the day is standing in for
    /// its runs — and minting a `UUID()` made selection impossible on exactly
    /// those tiers: the tap set `selected` to an id that the very next body
    /// pass had already replaced, so the panel never opened and the ring never
    /// lit. Both tiers produce at most one run per day, so the day is a
    /// sufficient key. Tier 1 keeps the payload's real id and does not come
    /// through here.
    private static func stableID(_ date: Date) -> UUID {
        let secs = UInt64(max(0, date.timeIntervalSince1970))
        return UUID(uuidString: String(format: "00000000-0000-4000-8000-%012llx", secs))
            ?? UUID()
    }

    private static let isoFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func isoKey(_ d: Date) -> String { isoFormatter.string(from: d) }

    private func fmtMiles(_ m: Double) -> String { String(format: "%.1f", m) }

    /// `42:13` under an hour, `1:24:12` over it — the exact time, always.
    ///
    /// The circles row printed `0:42`, hours-always, seconds-never. That is the
    /// right call for a WEEK total, where seconds are noise, and the wrong one
    /// for a run: an athlete reads their run as 42:13 and checks it against
    /// their watch, and a leading `0:` for a 42-minute run is a field of digits
    /// that carries no information. Hours appear only when there are hours.
    /// `static` because the nested `StressRun` needs it too, and a nested type
    /// has no path to an outer *instance*. Pure formatting, no state to capture.
    static func fmtDuration(_ seconds: Double) -> String {
        let t = max(0, Int(seconds.rounded()))
        let h = t / 3600, m = (t % 3600) / 60, sec = t % 60
        return h > 0
            ? "\(h):" + String(format: "%02d:%02d", m, sec)
            : "\(m):" + String(format: "%02d", sec)
    }

    /// `×8` not `×8.0`, `×8.6` when the curve carried it past the anchor.
    private func fmtMultiplier(_ w: Double) -> String {
        let r = (w * 10).rounded() / 10
        return r == r.rounded() ? "\(Int(r))" : String(format: "%.1f", r)
    }

    private func fmtPace(_ sec: Double) -> String {
        let s = Int(sec.rounded())
        return "\(s / 60):" + String(format: "%02d", s % 60)
    }

    /// Side + body part, without saying the side twice. Some logs arrive with
    /// the side split out, others with it folded into the area — both are the
    /// athlete's own words and neither is normalized on the way in.
    private static func bodyPart(_ n: TrendsDay.DayNiggle) -> String {
        let area = n.area.trimmingCharacters(in: .whitespaces)
        guard let side = n.side?.trimmingCharacters(in: .whitespaces), !side.isEmpty,
              !area.lowercased().contains(side.lowercased())
        else { return area }
        return "\(side) \(area)"
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

// MARK: - Marks

/// The niggle mark on the strip: a caret pointing DOWN at the run it belongs
/// to, hung above the bar. Coral is the alert palette and must never sit on a
/// pace fill, or it reads as coral commenting on pace.
private struct NiggleMark: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// The same mark pointing up, for the panel's quote — where it is a bullet
/// beside text rather than a pointer at a bar.
private struct NiggleCaretUp: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

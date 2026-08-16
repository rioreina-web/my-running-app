//
//  WeekTrainingLoadSection.swift
//  RunningLog
//
//  One week of training. Seven circles, one number, one sentence.
//
//    • CIRCLE AREA  = that day's miles
//    • CIRCLE COLOUR = the pace that carried most of that day's load
//    • TAP A DAY    = its pace breakdown and load score, opened in place
//
//  Replaced Section 8 (Effort · Felt vs Planned) 2026-08-10. Simplified down
//  to this on 2026-08-11: the section had been drawing every day three times
//  — a percentage above a pie above a coloured band — then repeating the
//  header totals in a footer, with mood and niggles as two further lanes
//  beneath and a labelled pace spectrum under those. Nine stacked elements
//  for one week.
//
//  WHY ONE MARK PER DAY. The old chart encoded load in the column width and
//  volume in the pie area *at the same time*, on the theory that the
//  disagreement between them was the insight. It is an insight, but it is a
//  second-order one, and it was being paid for with the first-order question
//  — how far did I run each day — which no single mark answered cleanly.
//
//  Intensity came back on 2026-08-11 as COLOUR rather than as a second
//  object. A vertical load bar beside each circle was tried first and cut: it
//  was accurate, but it made every day two things to parse and cost the
//  circle 12pt of diameter. Colour is free — it occupies no space, the blue
//  ramp is already the app's word for pace, and it answers the question the
//  bar was really being asked ("which days were sessions?") in one look.
//
//  What colour does NOT carry is magnitude: a day's exact TLS is a number in
//  the panel, not something to be estimated off a swatch. That split is
//  deliberate — the row is for scanning, the panel is for reading.
//
//  WHY AREA, NOT DIAMETER. A circle scaled by diameter overstates its biggest
//  value by squaring it: a 20-mile day drawn at 4x the diameter of a 5-mile
//  day reads as sixteen times the running. `dotDiameter` takes the square
//  root so the AREA is proportional and the row does not flatter long runs.
//
//  WHY MOOD AND NIGGLES ARE NO LONGER LANES. Two lanes and two lane headers
//  existed to give one tick and one caret a place to live. Both now sit
//  inside the day they belong to — the mood tick under the circle, the niggle
//  caret above it — and the niggle's actual sentence moved into the day
//  panel, so it is finally reachable in one tap instead of being abbreviated
//  to "CALF · SORE" with no way back to the words.
//
//  WHY THE SPECTRUM IS A SENTENCE. The weekly bar plus its labels was a chart
//  that had to be decoded to yield two facts: how much of the week was easy,
//  and the average pace. Both are now written out. The per-zone detail is a
//  tap away on any day that ran.
//
//  Data: `TrainingAnalyticsViewModel.dayVolumes(forWeekStart:)` for the Mon→Sun
//  scaffolding, `TrendsService.days` for the per-zone breakdown + mood +
//  niggles, and `QualityLoad` / `TrendsZoneWeight` for the load maths. The
//  weights are NOT re-declared here — that table is already mirrored once from
//  `_shared/workoutSegmentation.ts` and a second copy is a third place to
//  drift.
//

import Foundation
import SwiftUI

// MARK: - Zone taxonomy

/// Display order and colour for the ten canonical zones.
///
/// The backend vocabulary (`workoutSegmentation.ts`) and the colour ramp
/// (`PaceSpectrum`) are not quite the same list: the backend has `recovery`
/// and folds the threshold band into `hmp`, while the ramp carries a separate
/// `LT` stop. This is the one place the two are reconciled, so no view has to
/// know about it.
enum ZoneTaxonomy {

    /// Slowest → fastest. `recovery` is deliberately absent: it folds into
    /// `easy`, exactly as `ZONE_WEIGHTS` folds it (both weigh 1.0), so a
    /// recovery jog does not get its own near-identical row.
    static let ordered: [String] = [
        "easy", "moderate", "steady", "mp", "hmp", "10k", "5k", "3k", "mile",
    ]

    /// Raw token → the token we display it under.
    static func normalise(_ token: String) -> String {
        let t = token.lowercased()
        if t == "recovery" { return "easy" }
        return ordered.contains(t) ? t : "easy"
    }

    /// Sort position. Unknown tokens sort to the slow end rather than being
    /// dropped — a zone we do not recognise is still volume that was run.
    static func rank(_ token: String) -> Int {
        ordered.firstIndex(of: normalise(token)) ?? 0
    }

    /// Index into `PaceSpectrum.stops`. The ramp's `LT` stop (index 5) is
    /// skipped because the backend has no separate LT zone — `hmp` IS the
    /// threshold band there.
    private static let stopIndex: [String: Int] = [
        "easy": 0, "moderate": 1, "steady": 2, "mp": 3,
        "hmp": 4, "10k": 6, "5k": 7, "3k": 8, "mile": 9,
    ]

    static func color(_ token: String) -> Color {
        let i = stopIndex[normalise(token)] ?? 0
        return PaceSpectrum.stops[min(i, PaceSpectrum.stops.count - 1)]
    }

    /// Uppercase display label. `mp`/`hmp`/`10k` read as initialisms, not
    /// as capitalised words.
    static func label(_ token: String) -> String {
        normalise(token).uppercased()
    }
}

// MARK: - Section

struct WeekTrainingLoadSection: View {

    let vm: TrainingAnalyticsViewModel
    /// Deep link into the full day sheet, from the panel's "Open day".
    var onOpenDay: (Date) -> Void

    /// 0 = current week, 1 = last week, and so on. SHARED with the This-Week
    /// list above via a binding, so the two week navs move together — paging
    /// this row back also pages the day list, and vice versa. Two nav rows
    /// showing different weeks on one screen was the confusing version.
    @Binding var weekOffset: Int

    /// The open day, or nil. Deliberately not defaulted to "today" — opening
    /// with a panel already down buries the row, and on a past week "today"
    /// is not even in range. Tapping the open day closes it.
    @State private var selected: Date?

    /// The TLS explainer sheet. Opened from the day panel's load number,
    /// which is the only piece of jargon left on this surface.
    @State private var explainingLoad = false

    /// The per-zone breakdown lives on `TrendsService`, which until now was
    /// only ever loaded by the Trends tabs. This section is on TRAIN, so on a
    /// launch where the athlete never opened Trends, `days` was empty, every
    /// day scored zero load, and the whole section collapsed to its "no load
    /// yet" empty state — which looked like the feature was missing.
    ///
    /// Held as `@State` (not read through `.shared` inline) so `@Observable`
    /// tracks it and the section redraws when the fetch lands.
    @State private var trends = TrendsService.shared

    @ScaledMetric(relativeTo: .caption2)
    private var eyebrowMicro: CGFloat = DripTypeFloor.eyebrowMicro
    @ScaledMetric(relativeTo: .caption)
    private var eyebrowSmall: CGFloat = DripTypeFloor.eyebrowSmall

    // Geometry. The dot slot is fixed so the row does not resize when a
    // week's biggest day changes; only the circle inside it does.
    private let gutter: CGFloat = 2
    private let dotSlot: CGFloat = 52
    private let maxDot: CGFloat = 46
    private let minDot: CGFloat = 11
    private let caretSlot: CGFloat = 11

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
                    title: "Pulling this week's pace breakdown."
                )
                .padding(.top, 8)
            } else if week.miles > 0 {
                // Gated on MILES, not load. A week of runs that all arrived
                // without lap data scores zero load and is still a week that
                // was run; gating on load hid it behind "nothing logged".
                weekRow(week)

                if let sel = selected,
                   let day = week.days.first(where: {
                       Calendar.current.isDate($0.date, inSameDayAs: sel)
                   }) {
                    dayPanel(day)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                mixLine(week)
            } else {
                EmptyStateView(
                    variant: vm.isCurrentWeek(vm.weekStart(weeksAgo: weekOffset))
                             ? .dataPending : .optionalEmpty,
                    eyebrow: vm.isCurrentWeek(vm.weekStart(weeksAgo: weekOffset))
                             ? "No miles yet" : "A week off",
                    title: vm.isCurrentWeek(vm.weekStart(weeksAgo: weekOffset))
                        ? "Nothing logged this week so far. Once a run lands, it "
                          + "shows up here."
                        : "Nothing was logged that week. Page forward to a week with "
                          + "runs in it."
                )
            }
        }
        .padding(.top, 30)
        // `refresh()` no-ops when already loaded, so arriving here after a
        // visit to Trends costs nothing; arriving here first does the fetch.
        .task { await trends.refresh() }
    }

    // MARK: Head

    /// Week nav, then one headline and one quiet line. Volume was previously
    /// one of three stat columns separated by dividers — three headlines
    /// competing for the same slot. It is the number you came for; days run
    /// and time are context and read as context.
    private func head(_ week: WeekLoad) -> some View {
        let start = vm.weekStart(weeksAgo: weekOffset)
        let isCurrent = vm.isCurrentWeek(start)

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 11) {
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

                Text(isCurrent ? "THIS WEEK" : TrainingAnalyticsViewModel.weekRangeLabel(start))
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
            }
            .padding(.bottom, 14)

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(fmtMiles(week.miles))
                    .font(.dripStat(30))
                    .foregroundStyle(Color.drip.textPrimary)
                Text("mi")
                    .font(.dripStat(14))
                    .foregroundStyle(Color.drip.textSecondary)
            }

            Text("\(week.runDays) DAYS · \(fmtHM(week.timeMin))"
                 + (week.load > 0 ? " · \(Int(week.load.rounded())) TLS" : ""))
                .font(.dripEyebrow(eyebrowMicro)).tracking(1.1)
                .foregroundStyle(Color.drip.textTertiary)
                .padding(.top, 8)
        }
        // NOT `.accessibilityElement(children: .combine)`. Combining reads
        // the whole header as one label, which sounds tidier and silently
        // removes the two week-nav buttons from the VoiceOver rotor — you
        // could no longer page weeks at all.
    }

    // MARK: The row

    private func weekRow(_ week: WeekLoad) -> some View {
        HStack(alignment: .top, spacing: gutter) {
            ForEach(week.days) { d in
                dayButton(d, week: week)
            }
        }
        .padding(.top, 26)
    }

    /// One day: label, niggle caret, circle, miles, mood tick. Every mark
    /// belongs to this day and sits in this day's column, so nothing has to
    /// be aligned across a separate lane.
    private func dayButton(_ d: LoadDay, week: WeekLoad) -> some View {
        let isOpen = selected.map {
            Calendar.current.isDate($0, inSameDayAs: d.date)
        } ?? false

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selected = isOpen ? nil : d.date
            }
        } label: {
            VStack(spacing: 0) {
                Text(d.label)
                    .font(.dripEyebrow(eyebrowMicro)).tracking(1.2)
                    .foregroundStyle(isOpen ? Color.drip.textPrimary : Color.drip.textTertiary)

                // Reserved whether or not there is a caret, so a niggle on
                // Thursday does not shunt Thursday's circle down relative to
                // the rest of the row.
                ZStack {
                    if d.niggle != nil {
                        NiggleCaret()
                            .fill(Color.drip.coral)
                            .frame(width: 9, height: 7)
                    }
                }
                .frame(height: caretSlot)
                .padding(.top, 4)

                // SIZE IS MILES, COLOUR IS THE DAY'S MAIN STRESS. One mark
                // carrying two facts, where a bar beside it was a second
                // object to parse. Colour costs no space and the ramp is
                // already the app's word for pace, so the row gains a reading
                // — which day was the session — without gaining an element.
                ZStack {
                    Color.clear
                    if d.miles > 0 {
                        let dia = Self.dotDiameter(miles: d.miles, maxMiles: week.maxMiles,
                                                   maxDiameter: maxDot, minDiameter: minDot)
                        Circle()
                            // A day that ran without laps is drawn at its real
                            // size in paper-deep: the miles happened, the pace
                            // did not arrive, and a blue circle would be a
                            // claim about pace we cannot make.
                            .fill(d.markColor)
                            .frame(width: dia, height: dia)
                    } else {
                        Rectangle()
                            .fill(Color.drip.divider)
                            .frame(width: 13, height: 1)
                    }
                }
                .frame(height: dotSlot)

                Text(d.miles > 0 ? fmtMiles(d.miles) : "—")
                    .font(.dripStat(eyebrowSmall + 1))
                    .foregroundStyle(d.miles > 0 ? Color.drip.textPrimary : Color.drip.textTertiary)
                    .padding(.top, 5)

                // 15x3, and nothing when the day was not logged. A mood is
                // the only thing on this row that came from the athlete
                // rather than the watch, which is why it survived the cut.
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(d.mood.flatMap { Self.moodColor($0) } ?? Color.clear)
                    .frame(width: 15, height: 3)
                    .padding(.top, 6)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isOpen ? Color.drip.paperDeep.opacity(0.55) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(d.voiceLabel(of: week.load))
        .accessibilityHint(d.miles > 0 ? "Opens the day's pace breakdown" : "")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: The day panel

    /// What the picture used to encode, written out: one line of numbers,
    /// the zones the miles were run in, and — if there was one — the sentence
    /// the athlete wrote about their body.
    @ViewBuilder
    private func dayPanel(_ d: LoadDay) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Hairline()

            HStack(alignment: .firstTextBaseline) {
                Text("\(d.label) · \(TrainingAnalyticsViewModel.monthDayLabel(d.date))")
                    .font(.dripEyebrow(eyebrowSmall)).tracking(1.2)
                    .foregroundStyle(Color.drip.textSecondary)
                Spacer()
                Button { onOpenDay(d.date) } label: {
                    Text("OPEN DAY ↗")
                        .font(.dripEyebrow(eyebrowMicro)).tracking(1.1)
                        .foregroundStyle(Color.drip.coral)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 16)
            .padding(.bottom, 10)

            if d.miles <= 0 {
                Text("Nothing logged, and nothing missing. The week's load is carried "
                     + "by the other days.")
                    .font(.system(size: 13, design: .serif).italic())
                    .foregroundStyle(Color.drip.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                statLine(d)

                if d.hasZones {
                    VStack(spacing: 0) {
                        ForEach(d.zones) { z in
                            zoneRow(z)
                        }
                    }
                    .padding(.top, 14)

                    // The rows above will not sum to the headline mileage when
                    // part of the run went unclassified, and an unexplained
                    // gap between two numbers on the same card reads as a bug.
                    // It is also the honest caveat on the load score: those
                    // miles are not in it.
                    if d.hasUnclassified {
                        Text("\(fmtMiles(d.unclassifiedMiles)) mi came in without a pace "
                             + "zone — counted in the distance, not in the load score.")
                            .font(.system(size: 12, design: .serif).italic())
                            .foregroundStyle(Color.drip.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 12)
                    }
                } else {
                    Text("This run arrived without splits, so there is no pace breakdown "
                         + "and no load score for it. The \(fmtMiles(d.miles)) miles still "
                         + "count toward the week.")
                        .font(.system(size: 13, design: .serif).italic())
                        .foregroundStyle(Color.drip.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 12)
                }
            }

            if let n = d.niggle {
                HStack(alignment: .top, spacing: 9) {
                    NiggleCaret()
                        .fill(Color.drip.coral)
                        .frame(width: 9, height: 7)
                        .padding(.top, 5)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(Self.bodyPart(n).uppercased())
                            .font(.dripEyebrow(eyebrowMicro)).tracking(1.0)
                            .foregroundStyle(Color.drip.coralDeep)
                        // Verbatim. The lane used to show "CALF · SORE" —
                        // the filing label, not the report — with no route
                        // back to the words.
                        Text("“\(n.quote)”")
                            .font(.system(size: 13.5, design: .serif).italic())
                            .foregroundStyle(Color.drip.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, 14)
            }
        }
        .padding(.top, 16)
    }

    /// `11.0mi · 1:20:14 · 128TLS`. One line where three stat columns with
    /// dividers used to be — inside a panel, they were a second header
    /// competing with the week's.
    private func statLine(_ d: LoadDay) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(fmtMiles(d.miles)).font(.dripStat(17))
            Text("mi").font(.dripStat(11)).foregroundStyle(Color.drip.textSecondary)
            sep()
            Text(fmtHM(d.timeMin)).font(.dripStat(17))
            if d.load > 0 {
                sep()
                // The one tappable number in the line. Coral on "TLS" is the
                // whole affordance — the same colour that means "this opens
                // something" on "OPEN DAY ↗" two rows up. A superscript "?"
                // was doing the same job twice and put a piece of help-desk
                // punctuation in the middle of a stat line.
                Button { explainingLoad = true } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text("\(Int(d.load.rounded()))")
                            .font(.dripStat(17))
                            .foregroundStyle(Color.drip.textPrimary)
                        Text("TLS")
                            .font(.dripStat(11))
                            .foregroundStyle(Color.drip.coral)
                    }
                    // Padded before the shape is taken, so the tap target is
                    // bigger than the three small glyphs that trigger it.
                    .padding(.vertical, 6)
                    .padding(.trailing, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(Int(d.load.rounded())) training load score")
                .accessibilityHint("Explains how the score is calculated")
            }
            Spacer()
        }
        .foregroundStyle(Color.drip.textPrimary)
        .sheet(isPresented: $explainingLoad) {
            TrainingLoadExplainer(day: d)
        }
    }

    private func sep() -> some View {
        Text(" · ")
            .font(.dripStat(13))
            .foregroundStyle(Color.drip.textTertiary)
    }

    /// Swatch, zone, miles, pace. No TIME column and no header row: with
    /// miles and pace both present, time is arithmetic the table does not
    /// need to spend a column on.
    private func zoneRow(_ z: ZoneTotal) -> some View {
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
                Text("\(fmtMiles(z.miles)) mi")
                    .font(.dripStat(eyebrowSmall + 2))
                    .foregroundStyle(Color.drip.textPrimary)
                Text(z.avgPaceSec.map { "\(fmtPace($0))/mi" } ?? "—")
                    .font(.dripStat(eyebrowSmall + 2))
                    .foregroundStyle(Color.drip.textPrimary)
                    .frame(width: 82, alignment: .trailing)
            }
            .padding(.vertical, 9)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(ZoneTaxonomy.label(z.token)), \(fmtMiles(z.miles)) miles"
            + (z.avgPaceSec.map { ", averaging \(fmtPace($0)) per mile" } ?? "")
        )
    }

    // MARK: The week's pace mix

    /// The weekly spectrum bar and its per-zone labels, said out loud. The
    /// bar was a chart that had to be decoded to yield exactly these two
    /// facts, and its narrow segments could not carry a legible label anyway.
    @ViewBuilder
    private func mixLine(_ week: WeekLoad) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Hairline()

            Group {
                if week.zoneTotals.isEmpty {
                    Text("This week's runs came in without splits, so there is no pace "
                         + "breakdown. The miles still count.")
                        .foregroundStyle(Color.drip.textSecondary)
                } else if let avg = week.averagePaceSec {
                    // Two Texts interpolated into one, not an HStack: this has
                    // to wrap as one paragraph, and an HStack would break it
                    // into two rigid blocks at narrow widths. No `verbatim:`
                    // here — every part is app copy over app-formatted numbers,
                    // so it stays localizable.
                    let volume = Text("\(Int(week.easyMiles.rounded())) of "
                                      + "\(Int(week.miles.rounded())) miles easy.")
                        .foregroundStyle(Color.drip.textPrimary)
                    let pace = Text(" \(fmtPace(avg))/mi average across the week.")
                        .foregroundStyle(Color.drip.textSecondary)
                    Text("\(volume)\(pace)")
                }
            }
            .font(.system(size: 13, design: .serif))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 14)
        }
        .padding(.top, 26)
    }

    // MARK: - Model

    struct ZoneTotal: Identifiable {
        var id: String { token }
        let token: String
        let miles: Double
        let minutes: Double
        let load: Double
        /// Σ time ÷ Σ distance — a real average, not a mean of per-run means.
        var avgPaceSec: Double? { miles > 0 ? minutes * 60 / miles : nil }
    }

    struct LoadDay: Identifiable {
        let id = UUID()
        let date: Date
        let label: String
        let miles: Double
        let minutes: Double
        let zones: [ZoneTotal]
        let load: Double
        /// Wall-clock running minutes for the day, from `TrendsDay.durationMin`
        /// (paused-watch artifacts already re-imputed server-side). Distinct
        /// from `minutes`, which only counts time we could place in a zone — a
        /// lapless run has time but no zones, and the week's "time run" must
        /// still include it.
        let timeMin: Double
        /// Miles the segmenter could place in a pace zone. Less than `miles`
        /// whenever part of the run was not classified — the warmup and
        /// cooldown around a rep session are the everyday case.
        let zonedMiles: Double
        let mood: String?
        let niggle: TrendsDay.DayNiggle?
        let isRest: Bool
        let isFuture: Bool
        /// False when the day ran but arrived without laps.
        var hasZones: Bool { !zones.isEmpty }

        /// The zone that contributed the most LOAD, not the most miles.
        ///
        /// Miles would answer "where did the distance go", which on almost
        /// every day is easy — the row would be one colour and say nothing.
        /// Load answers "what made this day cost what it cost", so a rep
        /// session reads as its reps even though the warmup was longer, and a
        /// genuinely easy day still reads easy. That is the reading the
        /// colour is for: which days were sessions.
        ///
        /// A long run with a hard finish is the honest edge case: 12 easy
        /// miles outweigh 5 at marathon pace on load, so it colours easy. It
        /// was, in load terms, mostly an easy run — the panel has the split.
        var dominantZone: ZoneTotal? {
            zones.max { $0.load < $1.load }
        }

        /// Circle fill. Paper-deep when the run arrived without laps: there
        /// is no pace to report and a blue circle would invent one.
        @MainActor var markColor: Color {
            guard let z = dominantZone else { return Color.drip.paperDeep }
            return ZoneTaxonomy.color(z.token)
        }

        /// Mileage with no pace zone attached. It counts toward the day's
        /// distance and toward the week, but NOT toward the load score —
        /// which is why the panel says so rather than letting the zone rows
        /// quietly fail to add up to the headline.
        var unclassifiedMiles: Double { max(0, miles - zonedMiles) }
        /// A tenth of a mile of rounding slop is not worth a sentence.
        var hasUnclassified: Bool { unclassifiedMiles > 0.1 }

        func voiceLabel(of weekLoad: Double) -> String {
            if isFuture { return "\(label), upcoming." }
            if isRest { return "\(label), rest day." }
            var s = "\(label). \(String(format: "%.1f", miles)) miles. "
            if zones.isEmpty {
                s += "No pace breakdown available. "
            } else {
                s += "Training load score \(Int(load.rounded())). "
                s += zones.map {
                    "\(String(format: "%.1f", $0.miles)) miles \(ZoneTaxonomy.label($0.token))"
                }.joined(separator: ", ") + ". "
            }
            if let m = mood { s += "Felt \(m). " }
            if let n = niggle {
                s += "\(n.area)\(n.severity.map { ", \($0)" } ?? "")."
            }
            return s
        }
    }

    struct WeekLoad {
        let days: [LoadDay]
        let miles: Double
        let minutes: Double
        let load: Double
        let maxMiles: Double
        let runDays: Int
        let timeMin: Double
        let zoneTotals: [ZoneTotal]
        var averagePaceSec: Double? { miles > 0 ? minutes * 60 / miles : nil }
        /// Easy already has `recovery` folded into it by `normalise`, so this
        /// is "miles run at conversational pace", not "miles tagged easy".
        var easyMiles: Double {
            zoneTotals.first { $0.token == "easy" }?.miles ?? 0
        }
    }

    private func model() -> WeekLoad {
        let start = vm.weekStart(weeksAgo: weekOffset)
        let scaffold = vm.dayVolumes(forWeekStart: start)

        // TrendsDay is keyed by a "yyyy-MM-dd" UTC day string. We match on the
        // athlete's own calendar date, which is what the column is labelled
        // with. KNOWN EDGE: a run logged late enough in the evening to fall on
        // the next UTC day lands on the next column. The same simplification
        // the weekly rollup already makes (see timeline.ts's header note); a
        // profile-timezone cutoff fixes both at once, not just this view.
        let byDate = Dictionary(
            trends.days.map { ($0.date, $0) },
            uniquingKeysWith: { a, _ in a }
        )

        let days: [LoadDay] = scaffold.map { dv in
            let td = byDate[Self.isoKey(dv.date)]

            var zones: [ZoneTotal] = []
            if let minutes = td?.zoneMinutes, !minutes.isEmpty {
                let miles = td?.zoneMiles ?? [:]
                // Fold recovery into easy before totalling, so the display
                // vocabulary matches the ramp.
                var mins: [String: Double] = [:]
                var mis: [String: Double] = [:]
                for (raw, m) in minutes {
                    let t = ZoneTaxonomy.normalise(raw)
                    mins[t, default: 0] += m
                    mis[t, default: 0] += miles[raw] ?? 0
                }
                zones = mins.map { token, m in
                    ZoneTotal(token: token, miles: mis[token] ?? 0, minutes: m,
                              load: QualityLoad.score(workSeconds: m * 60, zone: token))
                }
                .filter { $0.minutes > 0 }
                .sorted { ZoneTaxonomy.rank($0.token) < ZoneTaxonomy.rank($1.token) }
            }

            let miles = td?.miles ?? dv.split.total
            // No breakdown → no load. A duration-times-easy estimate would be
            // a fabricated number sitting in the same row as measured ones.
            let zonedMin = zones.reduce(0.0) { $0 + $1.minutes }
            let dayMin = Double(td?.durationMin ?? 0)
            return LoadDay(
                date: dv.date,
                label: dv.label,
                miles: miles,
                minutes: zonedMin,
                zones: zones,
                load: zones.reduce(0) { $0 + $1.load },
                // WALL CLOCK WINS. This used to prefer `zonedMin` for its
                // sub-minute precision, falling back to `duration_min` only
                // when there were no zones at all. That is wrong whenever the
                // segmenter classifies *part* of a run: an interval Tuesday
                // placed 6.2 of its 10.2 miles, so the day reported "0:32:57"
                // for what was nearly an hour of running — a number the
                // athlete could not reconcile with anything.
                //
                // `duration_min` is rounded to whole minutes server-side,
                // which is why precision was preferred here in the first
                // place; `fmtHM` no longer prints seconds, so the rounding
                // is no longer on show. `minutes` keeps the zoned figure for
                // the pace maths, where it is the correct denominator.
                timeMin: dayMin > 0 ? dayMin : zonedMin,
                zonedMiles: zones.reduce(0) { $0 + $1.miles },
                mood: td?.mood,
                niggle: td?.niggles.first,
                isRest: dv.isRest || (!dv.isFuture && miles <= 0),
                isFuture: dv.isFuture
            )
        }

        // Week rollup, from the day rollups — one home for the math.
        var mins: [String: Double] = [:]
        var mis: [String: Double] = [:]
        var lds: [String: Double] = [:]
        for d in days {
            for z in d.zones {
                mins[z.token, default: 0] += z.minutes
                mis[z.token, default: 0] += z.miles
                lds[z.token, default: 0] += z.load
            }
        }
        let totals = mins.map { token, m in
            ZoneTotal(token: token, miles: mis[token] ?? 0, minutes: m, load: lds[token] ?? 0)
        }
        .sorted { ZoneTaxonomy.rank($0.token) < ZoneTaxonomy.rank($1.token) }

        return WeekLoad(
            days: days,
            miles: days.reduce(0) { $0 + $1.miles },
            minutes: days.reduce(0) { $0 + $1.minutes },
            load: days.reduce(0) { $0 + $1.load },
            maxMiles: max(days.map(\.miles).max() ?? 0, 0.0001),
            runDays: days.filter { $0.miles > 0 }.count,
            timeMin: days.reduce(0) { $0 + $1.timeMin },
            zoneTotals: totals
        )
    }

    // MARK: - Layout maths

    /// Diameter for a day's circle so that its AREA is proportional to miles.
    ///
    /// Area ∝ miles means diameter ∝ √miles. Scaling the diameter directly is
    /// the classic circle-chart lie: the week's 20-mile day would be drawn at
    /// four times the diameter of a 5-mile day and therefore SIXTEEN times the
    /// ink, which is what the eye actually reads.
    ///
    /// `minDiameter` keeps a 1-mile shakeout visible and tappable rather than
    /// rendering it as a speck; a day that did not run returns 0 and gets the
    /// rest dash instead.
    static func dotDiameter(miles: Double, maxMiles: Double,
                            maxDiameter: CGFloat, minDiameter: CGFloat) -> CGFloat {
        guard miles > 0 else { return 0 }
        guard maxMiles > 0, maxDiameter > 0 else { return minDiameter }
        let scaled = maxDiameter * CGFloat((miles / maxMiles).squareRoot())
        return min(maxDiameter, max(minDiameter, scaled))
    }

    // MARK: - Formatting

    private static let isoFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func isoKey(_ d: Date) -> String { isoFormatter.string(from: d) }

    private func fmtMiles(_ m: Double) -> String { String(format: "%.1f", m) }

    /// "2:07" and "0:55" — hours:minutes. One formatter for every duration on
    /// this surface. A 96-minute long run reading "96" is ambiguous (96 hours?
    /// 96 minutes?); "1:36" never is. Hours are always shown, even when zero,
    /// so the field is the same shape everywhere and the colon means the same
    /// thing in every row.
    ///
    /// Seconds were dropped 2026-08-11 along with the switch to wall-clock
    /// time: `duration_min` is whole minutes server-side, so a seconds field
    /// would print ":00" on every row and read as precision that is not there.
    private func fmtHM(_ minutes: Double) -> String {
        let total = Int(minutes.rounded())
        return "\(total / 60):" + String(format: "%02d", total % 60)
    }

    private func fmtPace(_ sec: Double) -> String {
        let s = Int(sec.rounded())
        return "\(s / 60):" + String(format: "%02d", s % 60)
    }

    /// Side + body part, without saying the side twice. Some logs arrive with
    /// the side split out (`side: "right"`, `area: "achilles"`), others with it
    /// folded into the area (`area: "left calf"`, `side: nil`) — both are the
    /// athlete's own words and neither is normalised on the way in.
    private static func bodyPart(_ n: TrendsDay.DayNiggle) -> String {
        let area = n.area.trimmingCharacters(in: .whitespaces)
        guard let side = n.side?.trimmingCharacters(in: .whitespaces), !side.isEmpty,
              !area.lowercased().contains(side.lowercased())
        else { return area }
        return "\(side) \(area)"
    }

    /// Call through an explicit closure, never as a bare function value
    /// (`flatMap(Self.moodColor)`): `Color.drip` is main-actor isolated, and
    /// passing the method as a value drops the call out of the body's
    /// MainActor context — a Swift 6 concurrency warning.
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

// MARK: - Niggle mark

/// The one coral element on this surface. A caret above the day rather than a
/// ring around its circle: coral is the alert palette and must never sit on a
/// pace mark, or it reads as coral commenting on pace.
private struct NiggleCaret: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

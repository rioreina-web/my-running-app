//
//  TrendsLegacyTabView.swift
//  RunningLog
//
//  THE PREVIOUS TRENDS TAB (v1). Superseded 2026-08-03 by `TrendsV2View`,
//  which is now what `TrendsTabView` renders. Kept whole and reachable —
//  behind the DEBUG `v1 ›` door in the v2 header — so the two can be read
//  side by side while v2 settles, and so the pace spectrum, threshold
//  miles and race prediction sections aren't lost while they wait for a
//  screen of their own. See `outputs/trends-audit-2026-08-03.md`.
//
//  The **Trends** tab — revived as the chart-centric "show me what I can't
//  see" surface (the tab was previously a tombstone; see git history in
//  this folder). Built from the approved prototype `trends-tab-prototype.html`.
//
//  ONE tab, one scroll, five sections ordered by the question being asked:
//
//    header → range segmenter (the tab's ONLY time control)
//    1 · Load            (VolumeDetailView — week totals + acute:chronic band)
//    2 · Pace            (PaceSignalView + the threshold-band row)
//    3 · Key sessions    (TrendsSessionGrid + week readout + head-to-head)
//    4 · Recovery        (RecoveryReadView + MoodDetailView + NigglesDetailView)
//    5 · Race prediction (RacePredictionTrack)
//
//  Two standing rules for this surface, both learned the hard way on 2026-08-03:
//
//    ONE TIME CONTROL. The segmenter owns the window and every section reads
//    `window`, not `service.weeks`. The tab used to stack three independent
//    ranges in a single viewport and hand three sections the full timeline
//    regardless, so "6 MO" sat above a one-week histogram and "PEAK 72" (all
//    time) sat under a read that said 67 (twelve weeks).
//
//    NO GENERATED PROSE. Trends shows; it doesn't narrate. There were five
//    paragraph generators here — a top-of-tab "read", an ACWR narrative, a
//    recovery read, a mood read — and they restated the charts beneath them
//    while claiming more than the data held (a two-point first-vs-last pace
//    comparison was rendered as "the engine is growing under the fatigue").
//    Numbers, charts and the athlete's own voice quotes carry the surface.
//    A written read may return, but only behind a real model.
//
//  Dropped 2026-07-27: the `UnifiedTrainingChart` multi-track hero — each of
//  its tracks now has a section that reads it better, and it was the heaviest
//  thing on the tab. Kept in the repo if the vertical week-read is wanted back.
//  Still unlinked, not deleted: the Sharp End fitness read, the pace×effort
//  map, the workload scatter, the Compare trend grid, Threshold work, and the
//  Trends 2 tab (`TrendsInsightsTabView`).
//
//  Voice + brand rules honored: coral as punctuation (key-session dots +
//  scrub marker only), mood via the muted mood palette, niggles
//  surfaced-never-diagnosed, no cheerleading, no em-dash empty states.
//
//  Data comes from `TrendsService` (the `trends-timeline` edge function);
//  `TrendsSampleData` now backs previews only. Charts can be refined.
//

import SwiftUI
import Supabase

struct TrendsLegacyTabView: View {
    @Environment(\.selectedTab) private var selectedTab

    @State private var range: TrendsRange = .twelveWeek
    @State private var scrubIndex: Int?
    @State private var service: TrendsService
    // Canonical athlete_state projection: the intensity-weighted ACWR passed to
    // the volume section (so it stops recomputing its own miles-based ratio, §1)
    // and the recovery read (readiness, hard-session balance, body signals).
    @State private var athleteState: TrendsAthleteState?
    // Head-to-head pair (the one Compare surface that survived the fitness
    // cull). Seeded to the two most recent sessions on first load.
    @State private var compareA: String = ""
    @State private var compareB: String = ""
    @State private var compareZones = PaceZonesService.shared
    @State private var openWorkoutLog: TrainingLog?
    /// Set when the athlete opens the Pace Bands drill-down from section 02.
    @State private var showPaceBands = false

    init(service: TrendsService = .shared) {
        _service = State(initialValue: service)
    }

    /// The selected window, sliced from the loaded timeline.
    private var window: [TrendsWeek] {
        Array(service.weeks.suffix(range.rawValue))
    }

    /// The chart window. One granularity now — weekly.
    /// The week the readout describes: the scrubbed one if the athlete is
    /// scrubbing, else the most recent week with actual training. The
    /// current week is often a partial, run-less week (early-week), so
    /// defaulting to `window.last` would show a misleading "0 mi" — we
    /// fall back to the latest week with miles instead. Scrubbing still
    /// surfaces empty weeks honestly.
    private var readoutWeek: TrendsWeek? {
        if let s = scrubIndex, s >= 0, s < window.count { return window[s] }
        return window.last(where: { $0.miles > 0 }) ?? window.last
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                content
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            // Clear the custom DripTabBar (~47pt bar + home-indicator
            // gutter). Without enough bottom inset the ask bar — the last
            // item in the scroll — sits trapped behind the tab bar and
            // can't be tapped. Matches the bottom-clearance convention
            // used by AnalysisView / FitnessAssessmentView.
            .padding(.bottom, 100)
        }
        .background(Color.drip.background)
        // NOTE: do not hide the navigation bar here. This view is no longer
        // mounted as a tab — its only route is the DEBUG `v1 ›` door in
        // `TrendsTabView`, which presents it inside a NavigationStack whose
        // toolbar carries the Close button. Hiding the bar took that button
        // with it and left the screen with no exit (2026-08-06).
        // Reset the scrub when the window changes so the readout falls back
        // to the latest week of the new range.
        .onChange(of: range) { _, _ in scrubIndex = nil }
        // Load when the Trends tab (tag 4) becomes active. `refresh()` is a
        // no-op once loaded, so re-entry is cheap and no fetch fires for a
        // tab the user never opens.
        .task(id: selectedTab.wrappedValue) {
            if selectedTab.wrappedValue == 4 {
                await service.refresh()
                athleteState = await TrendsAthleteState.fetch()
            }
        }
        // Head-to-head "Open workout" — presented from the tab, not from the
        // card, so the sheet survives the card re-rendering on scrub.
        .sheet(item: $openWorkoutLog) { log in
            HistoryDetailSheet(entry: log, onUpdate: {})
        }
        // Section 02's drill-down. "Open session ↗" inside it hands the log id
        // back to the same `openWorkout` the head-to-head card uses, so a
        // workout opens the same way from everywhere on this tab.
        .sheet(isPresented: $showPaceBands) {
            if let bands = service.paceBands {
                // Inherits the tab's range — Trends ships ONE time control,
                // and every number inside recomputes for that window.
                TrendsPaceBandsView(
                    data: bands,
                    windowDays: range.days,
                    rangeLabel: range.label
                ) { logId in
                    showPaceBands = false
                    openWorkout(logId)
                }
            }
        }
    }

    // MARK: state-aware content

    @ViewBuilder
    private var content: some View {
        if !service.weeks.isEmpty {
            loadedContent
        } else if service.isLoading {
            loadingState
        } else if service.lastError != nil {
            EmptyStateView(
                variant: .error,
                eyebrow: "Couldn't load",
                title: "Your timeline didn't load. Try again in a moment.",
                cta: .init(label: "Retry") {
                    Task { await service.refresh(force: true) }
                }
            )
            .padding(.top, 40)
        } else {
            EmptyStateView(
                variant: .dataPending,
                eyebrow: "Nothing to chart yet",
                title: "Your training shapes this view. Log a few runs and the timeline fills in."
            )
            .padding(.top, 40)
        }
    }

    /// One tab, one scroll, five sections, one rhythm. Every section is built
    /// the same way — eyebrow + one line of what it answers, then its content —
    /// so once you've read 01 you know how to read 05.
    ///
    ///   THE READ           the conclusion, before any chart
    ///   01 LOAD            how much, and whether the ramp is safe
    ///   02 PACE            where those miles fell, and how many were threshold
    ///   03 KEY SESSIONS    the grid, the week it lands on, two side by side
    ///   04 RECOVERY        how well you're resting, then mood and niggles
    ///   05 RACE PREDICTION where this points
    ///
    /// Reordered 2026-08-03 (Rio, "this is messy" pass). Four structural calls:
    ///
    ///   • **The read moved to the top.** It was the last thing on a six-screen
    ///     scroll, titled "what the chart shows" — the conclusion filed behind
    ///     the evidence. Trends is the 5-second view; the house pattern (see
    ///     `TrendsCalendarLede` on the v2 surface) is conclusion first.
    ///   • **Load leads, pace follows.** "How much am I running and is the ramp
    ///     safe" is the orienting question; "how is that volume spread across
    ///     paces" is its follow-up. Load is also three tiles and a band, so the
    ///     first chart now lands above the fold instead of a 208pt histogram
    ///     sitting behind two toggles.
    ///   • **"ACWR" is not a section name.** It's one number inside the load
    ///     question, in a tab that speaks plain English everywhere else.
    ///   • **Pace bands folded into 02.** Added earlier today as its own
    ///     numbered section on the rationale that it "finishes 01's sentence" —
    ///     which is the argument for making it a sub-block of that section, not
    ///     a peer of it. Still hides itself with no usable anchor.
    ///
    /// The `UnifiedTrainingChart` multi-track hero was dropped in the 2026-07-27
    /// pass. It stacked volume/sessions/mood/niggles on one shared x-axis — a
    /// genuinely good overlap — but each of those now has a section that reads
    /// it better, and the hero was the single heaviest thing on the tab. Kept in
    /// the repo (`UnifiedTrainingChart.swift`) if the vertical read is wanted.
    private var loadedContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            segmenter
                .padding(.top, 16)

            EditorialRule().padding(.vertical, 22)

            // 01 · LOAD — the three week totals and the acute:chronic band.
            sectionHead("Load", "Weekly miles, and the ramp")
            // `window`, not `service.weeks`. These three views were each handed
            // the entire timeline while the segmenter above claimed to scope the
            // tab — so "PEAK 72 mpw" (all time) sat directly under a read that
            // said "peaking at 67" (12 weeks), and the mood ribbon counted weeks
            // the header had excluded. One control means every section obeys it.
            // (Rio, 2026-08-03.)
            VolumeDetailView(
                weeks: window,
                flagged: service.flagged,
                trimmed: service.trimmed,
                onSetExcluded: { id, excluded in
                    Task { await service.setExcluded(id, excluded: excluded) }
                },
                canonicalAcwr: athleteState?.acwr,
                embedded: true
            )
            .padding(.top, 14)

            EditorialRule().padding(.vertical, 22)

            // 02 · PACE — where those miles fell, then how many landed at
            // threshold. The spectrum takes its window from `range` above: it
            // no longer carries a range bar of its own, and its VOLUME /
            // WORKLOAD / MOOD tiles are gone because section 01, the band right
            // here, and section 04 each already own one of those numbers.
            sectionHead("Pace", "Every mile, sorted by pace")
            PaceSignalView(
                embedded: true,
                fixedWindowDays: range.days,
                fixedWindowLabel: range.label
            )
            .padding(.top, 10)

            // Absent for an athlete with no usable fitness anchor: the surface
            // returns nothing rather than drawing a band it had to guess at.
            // Gated on the WINDOWED payload: a 4 wk range on a quiet stretch
            // has nothing to show, and a row of zeros reads as "you did no
            // threshold work" rather than "nothing in this window".
            if service.paceBands?.windowed(days: range.days).sessions.isEmpty == false {
                subHead("Threshold miles")
                    .padding(.top, 24)
                paceBandsRow
                    .padding(.top, 8)
            }

            EditorialRule().padding(.vertical, 22)

            // 03 · KEY SESSIONS — grid, the week it lands on, then two side by
            // side. Head-to-head lives here rather than as its own section: it
            // is what you get when you want two of these sessions compared, not
            // a separate destination.
            sectionHead("Key sessions", "One mark per session")
            TrendsSessionGrid(
                weeks: window,
                sessions: service.keySessions,
                scrubIndex: $scrubIndex
            )
            .padding(.top, 10)
            // The week readout sits under the grid because the grid is what
            // scrubs it. It used to live at the top of the tab, four screens
            // up: you dragged a chart down here and a number changed off-screen.
            readout
                .padding(.top, 12)
            KeySessionsDetailView(
                sessions: service.keySessions,
                volume: service.keyVolume,
                embedded: true
            )
            .padding(.top, 16)
            subHead("Two side by side")
                .padding(.top, 22)
            headToHead
                .padding(.top, 8)

            EditorialRule().padding(.vertical, 22)

            // 04 · RECOVERY — how well you're resting leads (readiness + the
            // load/rest balance off athlete_state), then how it felt and what
            // the body said (mood + niggles from the voice logs).
            sectionHead("Recovery", "Rest, mood, niggles")
            RecoveryReadView(
                readiness: athleteState?.last_readiness_score,
                hardSessions28d: athleteState?.load_distribution?.recovery_read?.hard_sessions_28d,
                avgDaysBetweenHard: athleteState?.load_distribution?.recovery_read?.avg_days_between_hard,
                downWeek: athleteState?.load_distribution?.recovery_read?.down_week,
                bodySignalCount: athleteState?.bodySignalCount ?? 0,
                embedded: true
            )
            .padding(.top, 6)
            subHead("How it's felt")
                .padding(.top, 26)
            MoodDetailView(weeks: window, embedded: true)
                .padding(.top, 10)
            subHead("Niggles · surfaced, not diagnosed")
                .padding(.top, 26)
            NigglesDetailView(weeks: window, embedded: true)
                .padding(.top, 10)

            EditorialRule().padding(.vertical, 22)

            // 05 · RACE PREDICTION — where the block points
            sectionHead("Race prediction", "Where this points")
            RacePredictionTrack()
                .padding(.top, 8)
        }
    }

    /// Section 02's body: the current threshold band and how much work has
    /// landed inside it, as one tappable line. Enough to know whether it's
    /// worth opening; the drill-down carries the toggle, the three lanes and
    /// the per-session table.
    ///
    /// Reports, never grades — no "on track", no target, no colour-coded
    /// verdict on the number.
    @ViewBuilder
    private var paceBandsRow: some View {
        // Windowed to the tab's range so the row can never disagree with the
        // drill-down it opens.
        if let bands = service.paceBands?.windowed(days: range.days) {
            Button { showPaceBands = true } label: {
                HStack(alignment: .center, spacing: 14) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(PaceBandKey.hm.color)
                        .frame(width: 10, height: 34)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(TrendsFormat.pace(bands.hm.anchorSec)) /mi")
                            .font(.dripStat(19)).monospacedDigit()
                            .foregroundStyle(Color.drip.textPrimary)
                        // "Threshold" is the plain-English question the section
                        // head asks; the DATA label stays in the canonical zone
                        // vocabulary, because LT and HMP are separate zones and
                        // this band is HMP. (The backend classifier folds
                        // LT/threshold into hmp, which is why the question and
                        // the label point at the same miles.)
                        Text("Half marathon band · \(TrendsFormat.pace(bands.hm.fastSec)) – \(TrendsFormat.pace(bands.hm.slowSec))")
                            .font(.dripCaption(10))
                            .foregroundStyle(Color.drip.textTertiary)
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("\(Int(bands.hm.miles.rounded())) mi")
                            .font(.dripStat(15)).monospacedDigit()
                            .foregroundStyle(Color.drip.textPrimary)
                        Text("\(Int(bands.hm.minutes.rounded())) min in band")
                            .font(.dripCaption(10))
                            .foregroundStyle(Color.drip.textTertiary)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.drip.textTertiary)
                }
                .padding(16)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.drip.cardBackground)
                        .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
                )
            }
            .buttonStyle(.plain)
        }
    }

    /// Section eyebrow + one line of what the section answers.
    private func sectionHead(_ title: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(.dripEyebrow(11)).tracking(1.3)
                .foregroundStyle(Color.drip.textSecondary)
            Text(sub)
                .font(.dripBody(13))
                .foregroundStyle(Color.drip.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A second thing inside a section — head-to-head under Key sessions,
    /// niggles under Mood. Deliberately quieter than `sectionHead` so the
    /// numbered sections stay countable and a sub-block never reads as
    /// another one.
    private func subHead(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.dripEyebrow(10)).tracking(1.2)
            .foregroundStyle(Color.drip.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The head-to-head pair. Everything else on the old Fitness group — the
    /// Sharp End read, the pace×effort map, the workload scatter, the trend
    /// grid, Threshold work — is unlinked; those files stay in the repo.
    @ViewBuilder
    private var headToHead: some View {
        let ordered = service.fastSegments.sessions.sorted { $0.date < $1.date }
        if ordered.count < 2 {
            EmptyStateView(
                variant: .dataPending,
                eyebrow: "Not enough to compare yet",
                title: "Two key sessions with lap data and this puts them side by side."
            )
        } else {
            HeadToHeadCard(
                sessions: ordered,
                aID: $compareA,
                bID: $compareB,
                heat: true,
                hills: true,
                zones: compareZones.zones,
                onOpenWorkout: openWorkout
            )
            .onAppear { seedComparePair(ordered) }
        }
    }

    /// Default to the two most recent sessions, newest as B.
    private func seedComparePair(_ ordered: [FastSession]) {
        guard compareA.isEmpty || compareB.isEmpty, ordered.count >= 2 else { return }
        compareB = ordered[ordered.count - 1].id
        compareA = ordered[ordered.count - 2].id
    }

    /// Tapped "Open workout" on the head-to-head card.
    private func openWorkout(_ id: String) {
        Task {
            let rows: [TrainingLog] = (try? await supabase
                .from("training_logs")
                .select()
                .eq("id", value: id)
                .limit(1)
                .execute()
                .value) ?? []
            if let log = rows.first {
                await MainActor.run { openWorkoutLog = log }
            }
        }
    }

    private var loadingState: some View {
        VStack(spacing: 14) {
            ProgressView()
                .tint(Color.drip.coral)
            Text("Reading your training…")
                .font(.dripBody(13))
                .foregroundStyle(Color.drip.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    // MARK: header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Text("TRENDS · \(Self.todayLabel)")
                    .font(.dripEyebrow(11))
                    .tracking(1.3)
                    .foregroundStyle(Color.drip.coral)
            }

            Text("The shape of\nyour block.")
                .font(.dripDisplay(32))
                .foregroundStyle(Color.drip.textPrimary)
                .lineSpacing(1)

            // No subtitle. This slot used to read "Advanced · base phase ·
            // everything on one timeline" — a hardcoded string, not derived
            // from anything, sitting where the athlete reads facts about their
            // own training. The Read below states the block in real numbers.
            // (Rio, 2026-08-03.)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    // MARK: readout

    /// How the readout's week relates to now — appended to the date so a week
    /// picked by the `readoutWeek` fallback can't sit there in coral looking
    /// like this week. On Aug 3 the tab was heading a Jul 20 week with a bare
    /// "WEEK OF JUL 20" and no hint it was looking two weeks back.
    private var readoutQualifier: String? {
        guard let week = readoutWeek else { return nil }
        if scrubIndex != nil { return nil }          // she picked it; she knows
        guard let latest = window.last else { return nil }
        if week.weekStart == latest.weekStart { return "THIS WEEK" }
        return "LATEST WEEK WITH MILES"
    }

    @ViewBuilder
    private var readout: some View {
        if let week = readoutWeek {
            VStack(alignment: .leading, spacing: 5) {
                Text("WEEK OF \(week.dateLabel.uppercased())"
                     + (readoutQualifier.map { " · \($0)" } ?? ""))
                    .font(.dripEyebrow(10))
                    .tracking(1.0)
                    .foregroundStyle(Color.drip.coral)

                HStack(spacing: 6) {
                    readStat("\(Int(week.miles))", "mi")
                    dotSep
                    readStat("\(Int(week.qualityMiles))", "quality")
                    if let pace = week.keyPaceSec {
                        dotSep
                        readStat(TrendsFormat.pace(pace), "/mi")
                    }
                }

                HStack(spacing: 8) {
                    if !week.mood.isEmpty {
                        MoodBadge(mood: week.mood)
                    }
                    if !week.niggles.isEmpty {
                        Text("WATCHING: \(week.niggles.joined(separator: ", ").uppercased())")
                            .font(.dripEyebrow(9))
                            .tracking(0.8)
                            .foregroundStyle(Color.drip.injured)
                    }
                }
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.easeInOut(duration: 0.12), value: week.dateLabel)
        }
    }

    private func readStat(_ value: String, _ unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(value)
                .font(.dripStat(16))
                .foregroundStyle(Color.drip.textPrimary)
            Text(unit)
                .font(.dripBody(12))
                .foregroundStyle(Color.drip.textSecondary)
        }
    }

    private var dotSep: some View {
        Text("·")
            .font(.dripBody(13))
            .foregroundStyle(Color.drip.textTertiary)
    }

    // MARK: no generated prose
    //
    // A block of derived sentences used to live here — "the read" at the top of
    // the tab, plus `volumeInsight` / `paceInsight` / `niggleInsight` feeding it.
    // Cut wholesale 2026-08-03 (Rio: "way too much text, a lot of it is
    // inaccurate"). Two problems, and the second is why none of it was salvaged
    // by rewording:
    //
    //   • Four paragraphs of prose stood between the athlete and the first
    //     chart, restating numbers the tiles underneath already carried.
    //   • The sentences claimed more than the data could support. `paceInsight`
    //     compared the FIRST and LAST key-session pace in the window — two
    //     points — and from that pair asserted "quality pace keeps dropping",
    //     "at the same effort", "even as volume climbs" and "the engine is
    //     growing under the fatigue". Not one of those four was tested: no
    //     trend fit, no effort term, no volume term. `niggleInsight` said
    //     "most of them land in the highest-mileage weeks" off a sample of 2.
    //
    // Trends shows; it doesn't narrate. Numbers and charts carry the surface,
    // and the athlete's own voice quotes stay because they are hers, not ours.
    // If a written read comes back it needs a real model behind it, not string
    // interpolation over a first-and-last comparison.

    // MARK: today label

    private static var todayLabel: String {
        let f = DateFormatter()
        f.dateFormat = "EEE · MMM d"
        return f.string(from: Date()).uppercased()
    }

}

// MARK: - Insight block (coral left bar + prose)

// MARK: - Preview

#if DEBUG
#Preview("Trends tab") {
    NavigationStack {
        TrendsLegacyTabView(service: TrendsService(preview: TrendsSampleData.weeks))
    }
}
#endif

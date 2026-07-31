//
//  TrendsTabView.swift
//  RunningLog
//
//  The **Trends** tab — revived as the chart-centric "show me what I can't
//  see" surface (the tab was previously a tombstone; see git history in
//  this folder). Built from the approved prototype `trends-tab-prototype.html`.
//
//  Simplified 2026-07-27 (Rio) into ONE tab, one scroll, four sections
//  ordered by the question being asked:
//
//    header → range segmenter → live readout
//    1 · Pace spectrum   (PaceSignalView — where the miles live)
//    2 · ACWR            (VolumeDetailView — acute:chronic band + week totals)
//    3 · Key sessions    (TrendsSessionGrid + KeySessionsDetailView + head-to-head)
//    4 · Recovery        (RecoveryReadView + MoodDetailView + NigglesDetailView)
//        Race prediction (RacePredictionTrack) → auto-surfaced insights.
//
//  Dropped in this pass: the `UnifiedTrainingChart` multi-track hero — each of
//  its tracks now has a section that reads it better, and it was the heaviest
//  thing on the tab. Kept in the repo if the vertical week-read is wanted back.
//  Still unlinked, not deleted: the Sharp End fitness read, the pace×effort
//  map, the workload scatter, the Compare trend grid, Threshold work, and the
//  Trends 2 tab (`TrendsInsightsTabView`).
//
//  Voice + brand rules honored: coral as punctuation (key-session dots +
//  scrub marker only), mood via the muted mood palette, niggles labeled
//  "Watching · in your own words" and surfaced-never-diagnosed, no
//  cheerleading, no em-dash empty states.
//
//  Data comes from `TrendsService` (the `trends-timeline` edge function);
//  `TrendsSampleData` now backs previews only. Charts can be refined.
//

import SwiftUI
import Supabase

struct TrendsTabView: View {
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
    #if DEBUG
    @State private var showV2 = false
    #endif

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
        .toolbar(.hidden, for: .navigationBar)
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
        #if DEBUG
        .fullScreenCover(isPresented: $showV2) {
            NavigationStack {
                // Seed with preview days so the calendar renders in-sim without
                // depending on a signed-in user or a synced backend — this
                // entry exists to iterate on the v2 visuals, not the data path.
                // Live surface: the same service the tab already loaded with
                // your real timeline. No preview seed, no demo biometrics — the
                // demo-only sections show their honest empty states.
                TrendsV2View(service: service)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Close") { showV2 = false }
                        }
                        ToolbarItem(placement: .principal) {
                            Text("TRENDS · V2")
                                .font(.dripEyebrow(11)).tracking(1.3)
                                .foregroundStyle(Color.drip.textSecondary)
                        }
                    }
                    .toolbarBackground(Color.drip.background, for: .navigationBar)
            }
        }
        #endif
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

    /// One tab, one scroll, four sections, one rhythm. Every section is built
    /// the same way — eyebrow + one line of what it answers, then its content —
    /// so once you've read 01 you know how to read 04.
    ///
    ///   01 PACE SPECTRUM   where the miles live
    ///   02 ACWR            acute vs. chronic load, with the week's totals
    ///   03 KEY SESSIONS    the grid, the detail, then two side by side
    ///   04 RECOVERY        how well you're resting, then mood and niggles
    ///      RACE PREDICTION where this points
    ///
    /// Restructured 2026-07-27 (Rio, simplification pass). Pace spectrum leads;
    /// ACWR is promoted to its own section carrying just the three totals + the
    /// acute:chronic band; Recovery leads with a readiness/rest read off
    /// athlete_state and folds mood + niggles beneath it.
    ///
    /// The `UnifiedTrainingChart` multi-track hero was dropped in this pass. It
    /// stacked volume/sessions/mood/niggles on one shared x-axis — a genuinely
    /// good overlap — but each of those now has a section that reads it better,
    /// and the hero was the single heaviest thing on the tab. Kept in the repo
    /// (`UnifiedTrainingChart.swift`) if the vertical read is wanted back.
    private var loadedContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            segmenter
                .padding(.top, 16)

            readout
                .padding(.top, 14)

            // 01 · PACE SPECTRUM — where the miles live
            sectionHead("Pace spectrum", "Every mile, sorted by pace")
                .padding(.top, 22)
            PaceSignalView(embedded: true)
                .padding(.top, 6)

            EditorialRule().padding(.vertical, 22)

            // 02 · ACWR — the three week totals and the acute:chronic band.
            // The multi-track Load hero was dropped in the simplification pass;
            // ACWR stands on its own with just enough volume context to read it.
            sectionHead("ACWR", "Acute vs. chronic load, with the week's totals")
            VolumeDetailView(
                weeks: service.weeks,
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

            // 03 · KEY SESSIONS — grid, detail, then two side by side.
            // Head-to-head lives here rather than as its own section: it is
            // what you get when you want two of these sessions compared, not
            // a separate destination.
            sectionHead("Key sessions", "Every session, on the day you ran it")
            TrendsSessionGrid(
                weeks: window,
                sessions: service.keySessions,
                scrubIndex: $scrubIndex
            )
            .padding(.top, 10)
            KeySessionsDetailView(
                sessions: service.keySessions,
                volume: service.keyVolume,
                embedded: true
            )
            .padding(.top, 12)
            subHead("Two side by side")
                .padding(.top, 22)
            headToHead
                .padding(.top, 8)

            EditorialRule().padding(.vertical, 22)

            // 04 · RECOVERY — how well you're resting leads (readiness + the
            // load/rest balance off athlete_state), then how it felt and what
            // the body said (mood + niggles from the voice logs). Mood and
            // Niggles self-head, so they need no sub-eyebrow of their own.
            sectionHead("Recovery", "How well you're resting, and what the body's saying")
            RecoveryReadView(
                readiness: athleteState?.last_readiness_score,
                hardSessions28d: athleteState?.load_distribution?.recovery_read?.hard_sessions_28d,
                avgDaysBetweenHard: athleteState?.load_distribution?.recovery_read?.avg_days_between_hard,
                downWeek: athleteState?.load_distribution?.recovery_read?.down_week,
                bodySignalCount: athleteState?.bodySignalCount ?? 0,
                embedded: true
            )
            .padding(.top, 6)
            MoodDetailView(weeks: service.weeks, embedded: true)
                .padding(.top, 24)
            NigglesDetailView(weeks: service.weeks, embedded: true)
                .padding(.top, 24)

            EditorialRule().padding(.vertical, 22)

            // RACE PREDICTION — where the block points
            sectionHead("Race prediction", "What this block projects to")
            RacePredictionTrack()
                .padding(.top, 8)

            EditorialRule().padding(.vertical, 22)

            insights
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
    /// five sections stay countable and a sub-block never reads as a sixth.
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
                #if DEBUG
                Spacer()
                // TEMP dev entry to the parallel Trends-v2 surface so the
                // calendar can be seen in-sim while it's wired. Remove when v2
                // takes over the tab (or is gated behind a real flag).
                Button {
                    showV2 = true
                } label: {
                    Text("v2 ›")
                        .font(.dripCaption(9))
                        .foregroundStyle(Color.drip.textTertiary)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .overlay(Capsule().stroke(Color.drip.divider, lineWidth: 1))
                }
                .buttonStyle(.plain)
                #endif
            }

            Text("The shape of\nyour block.")
                .font(.dripDisplay(32))
                .foregroundStyle(Color.drip.textPrimary)
                .lineSpacing(1)

            Text("Advanced · base phase · everything on one timeline")
                .font(.dripBody(13))
                .foregroundStyle(Color.drip.textSecondary)
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

    @ViewBuilder
    private var readout: some View {
        if let week = readoutWeek {
            VStack(alignment: .leading, spacing: 5) {
                Text("WEEK OF \(week.dateLabel.uppercased())")
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

    // MARK: insights

    private var insights: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("WHAT THE CHART SHOWS")
                .font(.dripEyebrow(11))
                .tracking(1.3)
                .foregroundStyle(Color.drip.textSecondary)

            if let n = niggleInsight { InsightBlock(text: n) }
            if let p = paceInsight { InsightBlock(text: p) }

            if let q = quoteWeek, let quote = q.voiceQuote {
                VStack(alignment: .leading, spacing: 8) {
                    InsightBlock(text: "Mood dips a day after the long run, then recovers. Predictable, not a warning.")
                    CoachQuote(text: quote)
                    Text(q.dateLabel)
                        .font(.dripBody(12))
                        .foregroundStyle(Color.drip.textTertiary)
                        .padding(.leading, 12)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: derived insights

    private var paceInsight: String? {
        let paced = window.compactMap(\.keyPaceSec)
        guard let first = paced.first, let last = paced.last, last < first else { return nil }
        return "Quality pace keeps dropping — \(TrendsFormat.pace(first)) to \(TrendsFormat.pace(last)) /mi at the same effort — even as volume climbs. The engine is growing under the fatigue."
    }

    private var niggleInsight: String? {
        let nigWeeks = window.filter { !$0.niggles.isEmpty }
        guard !nigWeeks.isEmpty else { return nil }
        let sortedMiles = window.map(\.miles).sorted(by: >)
        let topThirdCount = max(1, window.count / 3)
        let threshold = sortedMiles[topThirdCount - 1]
        let inTop = nigWeeks.filter { $0.miles >= threshold }.count
        if inTop * 2 >= nigWeeks.count {
            return "Your body's mentions land in the highest-mileage weeks of the window — the load is talking back. Surfaced from your own words, never diagnosed."
        }
        return "Body-part mentions are surfaced here from what you said, never interpreted. If anything gets sharper, see a clinician."
    }

    private var quoteWeek: TrendsWeek? {
        window.last { $0.voiceQuote != nil }
    }

    // MARK: today label

    private static var todayLabel: String {
        let f = DateFormatter()
        f.dateFormat = "EEE · MMM d"
        return f.string(from: Date()).uppercased()
    }

}

// MARK: - Insight block (coral left bar + prose)

private struct InsightBlock: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.dripBody(15))
            .foregroundStyle(Color.drip.textPrimary)
            .lineSpacing(3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 13)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Color.drip.coral.opacity(0.5))
                    .frame(width: 2)
            }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Trends tab") {
    NavigationStack {
        TrendsTabView(service: TrendsService(preview: TrendsSampleData.weeks))
    }
}
#endif

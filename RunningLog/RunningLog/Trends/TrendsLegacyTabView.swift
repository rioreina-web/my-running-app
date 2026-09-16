//
//  TrendsLegacyTabView.swift
//  RunningLog
//
//  THE TRENDS TAB. Superseded 2026-08-03 by `TrendsV2View`; restored as the
//  tab 2026-08-11 (Rio). `TrendsTabView` renders this file again, and
//  `TrendsV2View` is unlinked — no door leads to it from the tab in either
//  build configuration. See `outputs/trends-audit-2026-08-03.md` for the swap
//  this reverses.
//
//  Exactly two things came back from v2, and nothing else:
//
//    • THE RECOVERY SCORE — the ledger card, closing section 04. It is the one
//      number on this tab the segmenter does NOT own; see `recoverySection`.
//    • ASK — `AskBar`, at the foot of the scroll.
//
//  The name stays `TrendsLegacyTabView` on purpose: renaming the type would
//  churn every call site, preview and test that points at it for no gain, and
//  "legacy" is now only true of the filename. The v2 surface is the one in
//  cold storage.
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
//    3 · Key sessions    (week readout + receipt ledger + head-to-head)
//    4 · Signals         (TrendsMoodSection — 30-day block, own stepper)
//    6 · Race prediction (RacePredictionTrack)
//    foot · Ask          (AskBar)
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

    /// Section 03's head-to-head, folded away by default (2026-08-11).
    ///
    /// It is the one thing on this tab that isn't a read — it's a tool, with
    /// its own two pickers and its own toggles, and rendering it inline put a
    /// two-column comparison card between the key-session grid and section 04
    /// for every athlete whether or not they'd asked to compare anything. Two
    /// sessions side by side is something you go looking for.
    ///
    /// Not persisted. The next visit opens folded, the same rule the recovery
    /// receipt and the section explainers follow: the athlete asked to see the
    /// working once, not forever.
    @State private var showHeadToHead = false

    /// Opens the Signal Lab. Owned by the host (`TrendsTabView`) so the sheet
    /// survives this view re-rendering on scrub — the same reason the
    /// head-to-head workout sheet is hoisted. The door was v2's; it moved here
    /// when v2 was unlinked, because the Lab had no other entrance.
    private let onOpenLab: (() -> Void)?

    /// Opens the block surface (`TrendsBlockView`) — Trends v2, added
    /// 2026-08-18. Same door shape as `onOpenLab`: somewhere you go, not
    /// somewhere you land. The host owns which surface is showing and
    /// persists it, so this is a one-line handoff and no state lives here.
    private let onOpenBlock: (() -> Void)?

    init(
        service: TrendsService = .shared,
        onOpenLab: (() -> Void)? = nil,
        onOpenBlock: (() -> Void)? = nil
    ) {
        _service = State(initialValue: service)
        self.onOpenLab = onOpenLab
        self.onOpenBlock = onOpenBlock
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
            .padding(.top, 16)   // breathing room under the status bar
            // Clear the custom DripTabBar (~47pt bar + home-indicator
            // gutter). Without enough bottom inset the ask bar — the last
            // item in the scroll — sits trapped behind the tab bar and
            // can't be tapped. Matches the bottom-clearance convention
            // used by AnalysisView / FitnessAssessmentView.
            .padding(.bottom, 100)
        }
        .background(Color.drip.background)
        // NOTE: the navigation bar is hidden by `TrendsTabView`, the host,
        // and NOT here. When this view briefly lived behind a sheet door it
        // was presented inside a NavigationStack whose toolbar carried the
        // only Close button, and hiding the bar from in here took that button
        // with it — leaving the screen with no exit (2026-08-06). Mounted as
        // a tab the exit is the tab bar, but the rule stands: the surface
        // that presents this view owns its chrome.
        // Reset the scrub when the window changes so the readout falls back
        // to the latest week of the new range.
        .onChange(of: range) { _, _ in scrubIndex = nil }
        // Load when the Trends tab (tag 4) becomes active. `refresh()` is a
        // no-op once loaded, so re-entry is cheap and no fetch fires for a
        // tab the user never opens.
        .task(id: selectedTab.wrappedValue) {
            if selectedTab.wrappedValue == 4 {
                // `KeySessionStore.hydrateLoadsIfNeeded()` used to run here,
                // concurrently with the timeline fetch: the session grid's
                // filled-vs-open mark read `KeySessionStore`, and opening
                // Trends before Train left `loadByDay` empty, so every mark
                // drew as an open "below floor" ring. The grid is gone
                // (2026-08-17) and nothing else on this tab reads that store,
                // so the hydration went with it — one fewer round trip on tab
                // open. Restore both together if the grid ever comes back.
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
    ///   01 LOAD            how much, and whether the ramp is safe
    ///   02 PACE            where those miles fell, and how many were threshold
    ///   03 KEY SESSIONS    the grid, the week it lands on, and two side by
    ///                      side behind a fold
    ///   04 RECOVERY        how well you're resting, then today's score with
    ///                      its arithmetic
    ///   05 MOOD            thirty days of mood against miles, niggles and
    ///                      key sessions, on one date axis
    ///   06 RACE PREDICTION where this points
    ///   ASK                why, and compared to what
    ///
    /// The score closes 04 rather than leading it (Rio, 2026-08-11). It is the
    /// densest thing in the section — a number, a band, a delta and a foldable
    /// receipt — and putting it first made the read below it look like
    /// supporting evidence for a figure the athlete hadn't asked about yet.
    /// Rest, then how it felt, then what the body said, then the number that
    /// adds them up.
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
            sectionHead("Load", "Weekly miles and how fast they climbed")
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
            sectionHead("Pace", "How many miles at each pace")
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

            // 03 · KEY SESSIONS — the ledger, the week it sits in, then two
            // side by side. Head-to-head lives here rather than as its own
            // section: it is what you get when you want two of these sessions
            // compared, not a separate destination.
            //
            // THE DOT GRID CAME OUT, 2026-08-17 (Rio). `TrendsSessionGrid`
            // opened this section and is now unlinked — the file moved to
            // `_to_delete/` rather than being deleted outright, so this is one
            // `git mv` from reversible.
            //
            // Two things killed it, and both were the reader's problem rather
            // than the chart's:
            //
            //   • It asked for three encodings at once — dot SIZE is effort,
            //     COLOUR is pace zone, FILLED vs OPEN is whether the session
            //     cleared the floor — with a legend that had to be redrawn
            //     inside the Canvas because there was nowhere else to put it.
            //   • On real data it was about 10% full. `SESSION-GRID-APPLY.md`
            //     already recorded this as "legible at 12 weeks, mostly
            //     whitespace at 26" and recommended shortening the range. The
            //     honest fix turned out to be a different form, not a shorter
            //     window: seven day-rows spend most of their height proving a
            //     negative.
            //
            // What replaces it is the receipt ledger that was already sitting
            // two rows below it — promoted from a four-row card inside
            // `KeySessionsDetailView` to the section itself. Same sessions,
            // named and dated, with the measured rep pace and the density
            // strip per row: nothing to decode, and it reads the same at two
            // sessions or two hundred.
            //
            // Cost, stated plainly: the weekly rhythm — "Tuesday is threshold
            // day, and here are the weeks that broke it" — is no longer shown
            // anywhere on Trends. That read belongs to the Train calendar; if
            // it is wanted back it should go there, not here.
            sectionHead("Key sessions", "One line per session")
            // The readout no longer has a scrubber above it — the grid was the
            // only thing on this tab that set `scrubIndex` — so it states the
            // latest week with miles and labels itself as such. It moved above
            // the ledger: it is the "where you are" line, and the ledger under
            // it is the record.
            readout
                .padding(.top, 10)
            WorkoutsAndRepsSection(style: .editorial, initialCount: 8)
                .padding(.top, 8)
            expandableSubHead("Two side by side", isOpen: $showHeadToHead)
                .padding(.top, 22)
            if showHeadToHead {
                headToHead
                    .padding(.top, 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            EditorialRule().padding(.vertical, 22)

            // 04 · RECOVERY WAS HERE, AND IS GONE (2026-08-24).
            //
            // The section shed three different single numbers in five days,
            // each for the same reason. First "Readiness N/100" off
            // `athlete_state.last_readiness_score` (a stale server score next
            // to a live one). Then the ledger total, which summed DEMAND and
            // SUPPLY into one scalar — a 39 could mean "big block, feeling
            // fine" or "barely running, feeling awful". Then the BODY
            // percentile that replaced it, which still summed four supply
            // channels before ranking them, so opposing signals still
            // cancelled.
            //
            // The 214-day replay (`outputs/recovery-score-validation-2026-08-18.md`)
            // settled it: over seven months the number never left a 37-point
            // strip, had no relationship with `felt_rpe`, did not separate rest
            // days from run days, and did not move ahead of the one injury in
            // the window. The receipt under it was the good part, and the
            // receipt does not need a score to exist.
            //
            // What replaced it: the nightly signals are lanes in section 04
            // below, each against the athlete's own ±0.5 sd band, co-presented
            // so the athlete reads across them. Co-present, never compose.
            //
            // Mood and niggles used to live here too, as a week-by-week ribbon
            // and a by-body-part row. Section 05 below now reads both by day,
            // against the miles that produced them, and two mood surfaces one
            // screen apart is the contradiction this tab keeps having to fix.
            // (Rio, 2026-08-15.) `MoodDetailView` and `NigglesDetailView` are
            // still in `TrendsDetailViews.swift`, now unreferenced — the voice
            // quote was the one thing only they showed.

            EditorialRule().padding(.vertical, 22)

            // 05 · MOOD — thirty days of how it felt, laid against what she
            // actually ran.
            //
            // Section 04 above reads mood by WEEK, as one input to the recovery
            // picture. This reads it by DAY, and is the surface you come to when
            // mood is the question rather than a symptom. It owns its own thirty
            // day stepper rather than the segmenter's window — a mood block is
            // thirty days by definition, and the whole read is one thirty
            // against the thirty before it. See `TrendsMoodSection`.
            sectionHead("Mood", "Mood, miles and niggles by day")
            TrendsMoodSection(
                service: service,
                days: service.days,
                keySessions: service.keySessions
            )
                .padding(.top, 10)

            EditorialRule().padding(.vertical, 22)

            // 06 · RACE PREDICTION — where the block points
            sectionHead("Race prediction", "Estimated times at your current fitness")
            RacePredictionTrack()
                .padding(.top, 8)

            // The Ask door used to live here — `AskBar`, the analyzer chip
            // rail, answering in `AskAnswerCard`s. Removed 2026-08-19: Ask is
            // its own tab now (free-text chat, tag 10), and the cards the rail
            // produced were under-developed. `AskBar` stays in the repo,
            // unlinked. The scroll keeps its 100pt bottom inset — it was sized
            // for this bar, and without it the last section sits trapped
            // behind the tab bar either way.
        }
    }

    // MARK: 04 · recovery

    /// Today's recovery read — the two axes and the state.
    ///
    /// Deliberately NOT windowed, and the only thing on this tab that isn't.
    /// The segmenter owns every other number here (see the ONE TIME CONTROL
    /// rule at the top of the file), but this is a *today* read built over the
    /// full history: its load axis runs 7-day and 42-day EWMAs and its body
    /// axis ranks against 180 days, all of which sit behind a 4 wk window's
    /// first day. Handing it `window` would quietly change the arithmetic
    /// every time the segmenter moved while the label still said today — so it
    /// reads `service.days` end to end.
    ///
    /// `service.days` is one entry per day through today, rest days included,
    /// so the last index is today.


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

    /// The header's one outbound door. Kept quiet — a hairline capsule in
    /// tertiary text — because the Lab is a place you go on purpose, not a
    /// control competing with the segmenter beneath it.
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

    /// A `subHead` that opens something.
    ///
    /// Same size, tracking and colour as the plain one on purpose: a sub-block
    /// you can open must not read as a louder kind of heading than one you
    /// can't. The chevron is the whole difference, and the tap target is the
    /// full row width rather than the text — a 10pt eyebrow is not a button.
    private func expandableSubHead(_ title: String, isOpen: Binding<Bool>) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) { isOpen.wrappedValue.toggle() }
        } label: {
            HStack(spacing: 8) {
                Text(title.uppercased())
                    .font(.dripEyebrow(10)).tracking(1.2)
                    .foregroundStyle(Color.drip.textTertiary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.drip.textTertiary)
                    .rotationEffect(.degrees(isOpen.wrappedValue ? 0 : -90))
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(isOpen.wrappedValue ? "Collapse" : "Expand")
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
                .select(TrainingLog.columns)
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
                Spacer(minLength: 8)
                if let onOpenLab {
                    doorChip("lab ›", action: onOpenLab)
                }
                if let onOpenBlock {
                    doorChip("v2 ›", action: onOpenBlock)
                }
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

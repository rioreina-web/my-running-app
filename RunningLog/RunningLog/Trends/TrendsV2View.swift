//
//  TrendsV2View.swift
//  RunningLog · Trends
//
//  The Trends-v2 surface, rebuilt 2026-08-03 against
//  `outputs/trends-audit-2026-08-03.md`.
//
//  Four sections, one scroll, one time control:
//
//    00  THE READ         computed headline + noise guard + verdict chips
//    01  FIVE SIGNALS     mileage · key work · recovery · mood · niggles,
//                         on one shared time axis
//    02  RECOVERY SCORE   the number, showing its arithmetic
//    03  WHAT LINES UP    computed findings, small-n honest
//    04  THRESHOLD PACE   band work against the athlete's own band, adjustable
//
//  **What this replaces.** The previous v2 shipped seven sections — a
//  calendar, an efficiency curve, three stacked recovery cards, a pace
//  spectrum, a pace ladder, a pace-bands row and a key-session list. Of those,
//  the efficiency curve only ever rendered in preview mode, the recovery cards
//  and the v1 tab told contradictory load stories (convergence vs. ACWR), and
//  the pace surfaces answer a different question than "how am I trending".
//  They are not deleted — the pace surfaces still exist and belong on their own
//  screen — they are simply no longer what Trends opens on.
//
//  **The default window is 30 days.** It was 12 weeks, and there was no 30-day
//  option at all. `TrendsWindow` now offers 30d / 3mo / 6mo / 1yr / custom, and
//  every section on the screen reads its slice from that one control — including
//  the recovery ledger's "today", which is the last day in the window rather
//  than an unconditional today.
//
//  **Section 04 was promoted out of the Signal Lab.** Threshold pace is the one
//  "how fast am I" surface that earned a place next to the trend signals: it is
//  the only chart on either screen that reads the athlete's OWN band rather than
//  a shipped constant, and the band is a setting she moves. It renders through
//  the same `TrendsThresholdView` the Lab's section 02 uses and reads the same
//  `BandSettingsStore.shared` — one renderer and one band, so the two surfaces
//  cannot start disagreeing about the same miles. Nothing is duplicated and
//  nothing was removed from the Lab.
//
//  THIS IS THE TRENDS TAB. The v1 → v2 IA swap was made 2026-08-03: this view
//  is what `TrendsTabView` renders. The previous surface is kept whole in
//  `TrendsLegacyTabView` and is one DEBUG tap away via `onOpenLegacy`, so the
//  two can be read side by side while this one settles.
//

import SwiftUI

struct TrendsV2View: View {
    @State private var service: TrendsService
    @State private var window: TrendsWindow = .thirtyDays
    @State private var customFrom: Date = Date().addingTimeInterval(-59 * 86_400)
    @State private var customTo: Date = Date()
    @State private var dayWorkouts: DayWorkouts?
    @State private var weekDrill: TrendsWeekDrill?
    /// Explainers the athlete has asked back for, this visit only.
    @State private var revealedExplainers: Set<String> = []
    /// True once the scroll has moved off the top, so the time control can take
    /// its compact treatment. The picker never reads a scroll offset itself.
    @State private var pickerIsPinned = false
    /// Section 04, full screen. Carries which control segment to open on, so
    /// the section head lands on the anchor and `Adjust ›` lands on the band.
    @State private var thresholdDetail: ThresholdDetailRequest?
    /// The athlete's threshold band. The shared store rather than view state,
    /// so section 04 here and section 02 in the Signal Lab cannot disagree about
    /// what "in band" means for the same athlete.
    @State private var bandSettings = BandSettingsStore.shared
    /// Written by `TrendsTabView` when the tab becomes active.
    @AppStorage("trendsV2Visits") private var visitCount: Int = 0

    /// When false the host owns loading. The tab gates its fetch on becoming
    /// active, so no request fires for a tab the athlete never opens — every
    /// tab is constructed up front and merely hidden with `.opacity`.
    private let autoLoad: Bool
    /// Set by the tab host in DEBUG builds to offer the `v1 ›` door.
    private let onOpenLegacy: (() -> Void)?
    /// Set by the tab host to offer the `lab ›` door — the Signal Lab, where a
    /// signal gets looked at hard rather than glanced at. Same shape as
    /// `onOpenLegacy` because it is the same kind of door: a place you go, not
    /// somewhere you land.
    private let onOpenLab: (() -> Void)?

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

    // MARK: Derived — one build per render, shared by every section

    private var bucketSet: TrendsBucketSet {
        TrendsSignalBuilder.build(
            days: service.days,
            keySessions: service.keySessions,
            window: window
        )
    }

    /// Threshold work in the window, read off the raw laps against the band the
    /// athlete set. Falls back to the server's fixed HM ±5% bucketing when the
    /// backend predates `band_laps` — the section keeps working, the controls
    /// just have nothing to move.
    ///
    /// Both substrates arrive on the `trends-timeline` payload the tab already
    /// loads, so this section adds no request.
    ///
    /// Built once per render in `body` and threaded down to the section, the
    /// detail and the empty-state copy — never read twice. The builder walks
    /// every lap in the window and is not free.
    private var thresholdRead: ThresholdRead? {
        if let lab = service.bandLaps {
            return ThresholdBuilder.build(
                lab: lab,
                settings: bandSettings.settings,
                windowDays: window.days
            )
        }
        return service.paceBands.map {
            ThresholdBuilder.build(bands: $0, band: .hm, windowDays: window.days)
        }
    }

    /// True once the raw laps are on hand — the controls are inert without them,
    /// so they don't render.
    private var bandIsAdjustable: Bool { service.bandLaps != nil }

    var body: some View {
        // The two expensive reads, built ONCE per render and threaded down.
        //
        // Both builders walk the whole window — `TrendsSignalBuilder` over every
        // day, `ThresholdBuilder` over every lap — and both are now needed by
        // three places each (the sections, the pinned time control's meta line,
        // and the full-screen detail). Reading the computed vars from each of
        // those would restore exactly the three-passes-per-render shape the
        // section-02 comment below was written to kill.
        let set = bucketSet
        let threshold = thresholdRead

        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    content(proxy, set, threshold)
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 100)
            }
            // Attached to the ScrollView directly, before any wrapping
            // modifier, so the observation binds to this scroll view rather
            // than hunting for one through a `safeAreaInset` wrapper.
            //
            // Two thresholds, not one: a single boundary flickers the hairline
            // for anyone resting a thumb at exactly that offset. Pin past 12,
            // release under 4.
            .onScrollGeometryChange(for: CGFloat.self) { geo in
                geo.contentOffset.y
            } action: { _, y in
                let pinned = pickerIsPinned ? y > 4 : y > 12
                if pinned != pickerIsPinned { pickerIsPinned = pinned }
            }
            // The one time control, hoisted out of the scroll (2026-08-07).
            //
            // It always offered five ranges and always drove every section; it
            // just sat above four long sections, so by the time you were reading
            // section 04 the range was a scroll-to-top away. Pinned, it is one
            // tap from anywhere on the page — same control, same binding, and
            // still the only range on the surface.
            //
            // The header scrolls away with the content. A pinned title is
            // chrome; a pinned control is a control.
            .safeAreaInset(edge: .top, spacing: 0) {
                TrendsWindowPicker(
                    window: $window,
                    customFrom: $customFrom,
                    customTo: $customTo,
                    isPinned: pickerIsPinned,
                    meta: windowMeta(set)
                )
            }
            .background(Color.drip.background)
            .task { if autoLoad { await service.refresh() } }
            .sheet(item: $dayWorkouts) { dw in
                HistoryDetailPager(entries: dw.entries, initial: dw.initial, onUpdate: {})
            }
            .sheet(item: $weekDrill) { drill in
                TrendsWeekSheet(drill: drill, service: service)
            }
            .fullScreenCover(item: $thresholdDetail) { request in
                TrendsThresholdDetailView(
                    read: threshold,
                    settings: $bandSettings.settings,
                    // The SAME window the page reads. Change the range in there
                    // and this page is already changed — there is no second
                    // window that can disagree with the first.
                    window: $window,
                    customFrom: $customFrom,
                    customTo: $customTo,
                    ladder: service.bandLaps?.latestLadder,
                    meta: windowMeta(set),
                    initialBlock: request.block,
                    resolveDay: { iso, focus in
                        await service.resolveDay(dayISO: iso, focusLogId: focus)
                    }
                )
            }
        }
    }

    /// The days the window actually resolved to, and how much running is in
    /// them.
    ///
    /// Both figures come off the already-built slice rather than the preset's
    /// nominal span: a preset takes the last n rows that EXIST, so an athlete
    /// twelve days into her timeline is looking at twelve days and the control
    /// must not tell her otherwise. And "run days" rather than "runs" because
    /// that is what `runDays` counts — a double day is one day.
    private func windowMeta(_ set: TrendsBucketSet) -> (range: String, count: String)? {
        guard !set.days.isEmpty else { return nil }
        let runs = set.runDays
        return (
            range: set.dateRangeLabel,
            count: "\(runs) run day\(runs == 1 ? "" : "s")"
        )
    }

    /// The read's chips and the recovery gauge are the page's own table of
    /// contents: they name a section, so they travel to it. Anchors are the
    /// section ids below — `signals`, `recovery`, `findings`, `threshold`.
    private func jump(_ proxy: ScrollViewProxy, to anchor: String) {
        withAnimation(.easeInOut(duration: 0.32)) {
            proxy.scrollTo(anchor, anchor: .top)
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .top) {
                DripEyebrow(text: "Trends", coral: true)
                Spacer()
                if let onOpenLab {
                    doorChip("lab ›", action: onOpenLab)
                }
                if let onOpenLegacy {
                    // The reverse of the door v1 used to carry. Dev-only, and
                    // it goes away with the legacy surface.
                    doorChip("v1 ›", action: onOpenLegacy)
                }
            }
            Text("Running Log — \(window.plateTitle)".uppercased())
                .font(.dripEyebrow(10))
                .tracking(1.4)
                .foregroundStyle(Color.drip.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The header's outbound doors. One shape, so a second door can't quietly
    /// become a different kind of control from the first.
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

    // MARK: State-aware content

    @ViewBuilder
    private func content(
        _ proxy: ScrollViewProxy,
        _ set: TrendsBucketSet,
        _ threshold: ThresholdRead?
    ) -> some View {
        if !set.isEmpty {
            let read = TrendsSignalRead.compute(set)

            TrendsReadHeader(read: read, set: set) { anchor in
                jump(proxy, to: anchor)
            }
            .padding(.top, 22)

            EditorialRule().padding(.vertical, 24)

            section(eyebrow: "Five signals", number: "01",
                    sub: "Mileage, key work, recovery, mood, niggles — one time axis. Drag across to read a day down all five.",
                    anchor: "signals") {
                TrendsSignalLanes(set: set) { bucket in
                    // A day-grain column maps to one day's workouts; a weekly
                    // column maps to seven, so it opens the week instead of
                    // guessing which day was meant.
                    if set.grain == .day {
                        openDay(bucket.startISO)
                    } else {
                        openWeek(bucket)
                    }
                }
                .padding(.top, 14)
            }

            EditorialRule().padding(.vertical, 24)

            section(eyebrow: "Recovery score · \(recoveryDayLabel(set))", number: "02",
                    sub: "Every score shows its own arithmetic. Starts at 50, and each line carries the evidence it moved on.",
                    anchor: "recovery") {
                if let ledger = ledger(for: set) {
                    TrendsRecoveryLedgerView(
                        ledger: ledger,
                        previous: previousScore(for: set),
                        onSeeTrend: { jump(proxy, to: "signals") }
                    )
                } else {
                    EmptyStateView(
                        variant: .dataPending,
                        eyebrow: "No score yet",
                        title: "The score reads your mood logs, your niggles and your last few weeks of running. A few more days and it fills in."
                    )
                }
            }

            EditorialRule().padding(.vertical, 24)

            section(eyebrow: "What lines up", number: "03",
                    sub: "Computed from the window in view. When there isn't enough to say, it says that.",
                    anchor: "findings") {
                TrendsFindingsView(findings: read.findings).padding(.top, 6)
            }

            thresholdSection(threshold)

            // The door to Ask. Trends shows the shape; Ask explains it. Kept
            // at the foot rather than in the header because it is the next
            // thing to read, not a control competing with the signals.
            EditorialRule().padding(.vertical, 24)
            AskBar()

        } else if service.isLoading {
            loadingState
        } else if service.lastError != nil {
            EmptyStateView(
                variant: .error,
                eyebrow: "Couldn't load",
                title: "Your timeline didn't load. Try again in a moment.",
                cta: .init(label: "Retry") { Task { await service.refresh(force: true) } }
            )
            .padding(.top, 40)
        } else if !service.days.isEmpty {
            // Data exists, but not inside the chosen custom range.
            EmptyStateView(
                variant: .optionalEmpty,
                eyebrow: "Nothing in this range",
                title: "There's no logged training between those two dates. Try a wider window.",
                cta: .init(label: "Back to 1 month") { window = .thirtyDays }
            )
            .padding(.top, 40)
        } else {
            EmptyStateView(
                variant: .dataPending,
                eyebrow: "Nothing to chart yet",
                title: "Your training shapes this view. Log a few runs and the signals fill in."
            )
            .padding(.top, 40)
        }
    }

    // MARK: 04 · threshold

    /// The section, rule included.
    ///
    /// The rule lives in here rather than beside the call, alongside the other
    /// sections': `content(_:)`'s populated branch was already at ten views, and
    /// a `ViewBuilder` block takes no more than ten. Carrying its own separator
    /// keeps this section one child instead of two.
    @ViewBuilder
    private func thresholdSection(_ read: ThresholdRead?) -> some View {
        EditorialRule().padding(.vertical, 24)

        section(eyebrow: "Threshold pace", number: "04",
                sub: "Every session that held time inside your own pace band, heat-neutral. Height is pace, dot size is minutes. The band is a setting — move it and the chart recounts.",
                anchor: "threshold",
                // The door only appears when there is something behind it to
                // move. On a backend without `band_laps` the fallback card IS
                // the whole story, and a full screen of it is chrome.
                onExpand: bandIsAdjustable ? { thresholdDetail = .init(block: nil) } : nil) {
            thresholdBody(read).padding(.top, 14)
        }
    }

    /// The chart, its empty states, and the band controls beneath them.
    ///
    /// Takes the already-built read rather than reading `thresholdRead` again —
    /// the empty-state copy needs the same numbers the chart drew from, and
    /// rebuilding it per accessor is how a section starts costing three passes
    /// over every lap in the window.
    private func thresholdBody(_ read: ThresholdRead?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let read, !read.isEmpty {
                LabCard {
                    TrendsThresholdView(read: read, onSelect: { openThresholdSession($0, in: read) })
                }
            } else if bandIsAdjustable {
                // A band the athlete set can be set to catch nothing. Say which
                // band found nothing and how to open it back up — the controls
                // sit directly below.
                EmptyStateView(
                    variant: .dataPending,
                    eyebrow: "Nothing clears this band",
                    title: emptyBandTitle(read)
                )
            } else {
                EmptyStateView(
                    variant: .dataPending,
                    eyebrow: "No band work yet",
                    title: "This reads every session that spent time inside your half-marathon pace band. Once a few land, the trend draws itself."
                )
            }

            if bandIsAdjustable {
                adjustRow(bandSettings.settings).padding(.top, 14)
            }
        }
    }

    /// The band's current setting, and the door to changing it.
    ///
    /// This replaces the inline expanded controls (2026-08-07). The line itself
    /// is unchanged — it is still the complete settings read, from
    /// `TrendsThresholdControls.summaryLine`, so the athlete can see which band
    /// she is looking at without opening anything. What changed is where the
    /// controls open: full screen, next to a chart tall enough to watch, rather
    /// than as ~700pt of stacked blocks pushing the rest of the page down.
    private func adjustRow(_ settings: BandSettings) -> some View {
        Button {
            thresholdDetail = .init(block: "band")
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(TrendsThresholdControls.summaryLine(
                    settings, ladder: service.bandLaps?.latestLadder
                ))
                .font(.dripEyebrow(11))
                .tracking(0.8)
                .foregroundStyle(Color.drip.textSecondary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                Text("ADJUST ›")
                    .font(.dripEyebrow(10).weight(.semibold))
                    .tracking(1.0)
                    .foregroundStyle(Color.drip.textPrimary)
                    .fixedSize()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Band settings")
        .accessibilityValue(TrendsThresholdControls.summaryLine(
            settings, ladder: service.bandLaps?.latestLadder
        ))
        .accessibilityHint("Opens the full threshold screen, where the band and the date range can be adjusted")
    }

    /// What the current band asked for, so an empty chart is a readable result
    /// rather than a dead end.
    private func emptyBandTitle(_ read: ThresholdRead?) -> String {
        let s = bandSettings.settings
        var t = "No session in this window held "
        t += s.minTotalMinutes > 0 ? "\(Int(s.minTotalMinutes.rounded())) minutes" : "time"
        if s.minBlockMinutes > 0 {
            t += " (\(Int(s.minBlockMinutes.rounded())) unbroken)"
        }
        t += " inside \(s.anchor.proseLabel) \(s.widthLabel)."
        if let read, read.excludedSessions > 0 {
            t += " \(read.excludedSessions) came close and fell under the minimum."
        }
        t += " Widen an edge or lower a minimum and it fills in."
        return t
    }

    /// Open the workout behind a threshold dot.
    ///
    /// Routed through the tab's own day drill-down rather than a second fetch,
    /// so a session opens the same pager here as it does from the signal lanes.
    /// The point carries its own ISO date, which is what `openDay` needs; the
    /// log id focuses the pager on the right session for a day with two runs.
    private func openThresholdSession(_ logId: String, in read: ThresholdRead) {
        guard let point = read.points.first(where: { $0.id == logId }) else { return }
        openDay(point.date, focusLogId: point.id)
    }

    // MARK: Section chrome

    /// The explainer paragraphs introduce the page. Charming on visit one,
    /// wallpaper by visit ten — and they push the actual signal down the
    /// screen every single time. They ship for the first three visits and
    /// then retire behind a chevron, which recalls them for as long as the
    /// page is on screen and forgets by the next visit. Nothing about the
    /// toggle is persisted: the athlete asked once, not forever.
    private var explainersAreAutomatic: Bool { visitCount <= 3 }

    @ViewBuilder
    private func section<Content: View>(
        eyebrow: String,
        number: String,
        sub: String,
        anchor: String,
        /// When non-nil the head grows a door to this section's full screen.
        /// Built generic so 01-03 *can* have one later; only 04 passes it
        /// today, because only 04 has controls and a list that don't fit
        /// inline. A door onto the same content at a different size is chrome.
        onExpand: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let showsSub = explainersAreAutomatic || revealedExplainers.contains(anchor)

        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                DripEyebrow(text: eyebrow)
                Spacer(minLength: 8)
                if !explainersAreAutomatic {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if revealedExplainers.contains(anchor) {
                                revealedExplainers.remove(anchor)
                            } else {
                                revealedExplainers.insert(anchor)
                            }
                        }
                    } label: {
                        Text("⌄")
                            .font(.dripEyebrow(11))
                            .foregroundStyle(Color.drip.textTertiary)
                            .rotationEffect(.degrees(showsSub ? 180 : 0))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        showsSub ? "Hide what this section counts"
                                 : "What this section counts"
                    )
                }
                if let onExpand {
                    Button(action: onExpand) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down.left.and.arrow.up.right")
                                .font(.system(size: 8, weight: .semibold))
                            Text("EXPAND")
                                .font(.dripEyebrow(9).weight(.semibold))
                                .tracking(1.1)
                        }
                        .foregroundStyle(Color.drip.textPrimary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .overlay(Capsule().stroke(Color.drip.divider, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Expand \(eyebrow.lowercased())")
                    .accessibilityHint("Opens the full screen, where the band and the date range can be adjusted")
                }
                Text(number)
                    .font(.dripEyebrow(9))
                    .tracking(1.3)
                    .foregroundStyle(Color.drip.textTertiary)
            }
            if showsSub {
                Text(sub)
                    .font(.dripBody(12.5))
                    .foregroundStyle(Color.drip.textSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
            content()
        }
        .id(anchor)
    }

    // MARK: Ledger for the window's last day

    /// The ledger is built over the FULL history — the 8-week load baseline and
    /// the 14-day niggle lookback both need days that sit before the window's
    /// first column — then read at the window's last day.
    ///
    /// These take the already-built `set` rather than reading `bucketSet`
    /// again: the old computed-var shape evaluated the full builder (including
    /// the whole-history recovery series) three times per render.
    private func ledgerIndex(for set: TrendsBucketSet) -> Int? {
        guard let lastISO = set.days.last?.date else { return nil }
        return service.days.lastIndex(where: { $0.date == lastISO })
    }

    private func ledger(for set: TrendsBucketSet) -> TrendsRecoveryLedger? {
        guard let idx = ledgerIndex(for: set) else { return nil }
        return TrendsRecoveryLedger.ledger(days: service.days, at: idx)
    }

    private func previousScore(for set: TrendsBucketSet) -> Int? {
        guard let idx = ledgerIndex(for: set), idx > 0 else { return nil }
        return TrendsRecoveryLedger.ledger(days: service.days, at: idx - 1).total
    }

    /// "Today" only when the window actually ends today — otherwise name the
    /// day, so a custom range never labels a July score as today's.
    private func recoveryDayLabel(_ set: TrendsBucketSet) -> String {
        guard let lastISO = set.days.last?.date else { return "today" }
        let isLatest = lastISO == service.days.last?.date
        return isLatest ? "today" : TrendsSignalBuilder.shortLabel(lastISO)
    }

    // MARK: Drill-down

    /// Open a day's logs, landing on the hardest session.
    ///
    /// The ranking and the fetch both live in `TrendsService.resolveDay`, which
    /// the week sheet's day rows call too — the same day must not open on one
    /// session from the chart and a different one from the week list.
    private func openDay(_ dayISO: String, focusLogId: String? = nil) {
        Task {
            if let dw = await service.resolveDay(dayISO: dayISO, focusLogId: focusLogId) {
                dayWorkouts = dw
            }
        }
    }

    /// Open a weekly column's seven days. Built from the timeline already in
    /// memory — no fetch happens until a day inside it is tapped.
    private func openWeek(_ bucket: TrendsBucket) {
        weekDrill = TrendsWeekDrill.make(
            weekStartISO: bucket.startISO,
            label: bucket.label,
            days: service.days,
            keySessions: service.keySessions
        )
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Reading your signals…")
                .font(.dripCaption(10))
                .foregroundStyle(Color.drip.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}

// MARK: - Shared drill-down payload

/// A request to open section 04 full screen, carrying which control segment to
/// land on. `Identifiable` so it drives `fullScreenCover(item:)` — presenting on
/// a payload rather than a bool is what lets the section head and the `ADJUST ›`
/// row open the same screen on different tabs.
struct ThresholdDetailRequest: Identifiable {
    let id = UUID()
    /// `"anchor" | "band" | "minimum" | "floor"`, or nil for the default.
    let block: String?
}

/// A day's workouts to open in the detail pager.
struct DayWorkouts: Identifiable {
    let id = UUID()
    let entries: [TrainingLog]
    let initial: TrainingLog
}

// MARK: - Preview

#Preview("Trends v2 · five signals") {
    TrendsV2View(
        service: TrendsService(
            preview: [],
            days: TrendsDay.previewMonthRich,
            keySessions: KeySession.previewLadder,
            paceBands: .preview,
            bandLaps: .preview
        )
    )
}

/// The same page against a backend with no `band_laps` — section 04 falls back
/// to the fixed HM ±5% read and draws no controls. Worth its own preview: the
/// fallback is the shape most athletes' first launch after an old deploy hits.
#Preview("Trends v2 · threshold fallback") {
    TrendsV2View(
        service: TrendsService(
            preview: [],
            days: TrendsDay.previewMonthRich,
            keySessions: KeySession.previewLadder,
            paceBands: .preview
        )
    )
}

//
//  TrendsV2View.swift
//  RunningLog · Trends
//
//  The Trends-v2 surface, rebuilt 2026-08-03 against
//  `outputs/trends-audit-2026-08-03.md`.
//
//  Three sections, one scroll, one time control:
//
//    00  THE READ         computed headline + noise guard + verdict chips
//    01  FIVE SIGNALS     mileage · key work · recovery · mood · niggles,
//                         on one shared time axis
//    02  RECOVERY SCORE   the number, showing its arithmetic
//    03  WHAT LINES UP    computed findings, small-n honest
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

    /// When false the host owns loading. The tab gates its fetch on becoming
    /// active, so no request fires for a tab the athlete never opens — every
    /// tab is constructed up front and merely hidden with `.opacity`.
    private let autoLoad: Bool
    /// Set by the tab host in DEBUG builds to offer the `v1 ›` door.
    private let onOpenLegacy: (() -> Void)?

    init(
        service: TrendsService = .shared,
        autoLoad: Bool = true,
        onOpenLegacy: (() -> Void)? = nil
    ) {
        _service = State(initialValue: service)
        self.autoLoad = autoLoad
        self.onOpenLegacy = onOpenLegacy
    }

    // MARK: Derived — one build per render, shared by every section

    private var bucketSet: TrendsBucketSet {
        TrendsSignalBuilder.build(
            days: service.days,
            keySessions: service.keySessions,
            window: window
        )
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    TrendsWindowPicker(window: $window, customFrom: $customFrom, customTo: $customTo)
                        .padding(.top, 14)
                    content(proxy)
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 100)
            }
            .background(Color.drip.background)
            .task { if autoLoad { await service.refresh() } }
            .sheet(item: $dayWorkouts) { dw in
                HistoryDetailPager(entries: dw.entries, initial: dw.initial, onUpdate: {})
            }
            .sheet(item: $weekDrill) { drill in
                TrendsWeekSheet(drill: drill, service: service)
            }
        }
    }

    /// The read's chips and the recovery gauge are the page's own table of
    /// contents: they name a section, so they travel to it. Anchors are the
    /// section ids below — `signals`, `recovery`, `findings`.
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
                if let onOpenLegacy {
                    Spacer()
                    // The reverse of the door v1 used to carry. Dev-only, and
                    // it goes away with the legacy surface.
                    Button(action: onOpenLegacy) {
                        Text("v1 ›")
                            .font(.dripCaption(9))
                            .foregroundStyle(Color.drip.textTertiary)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .overlay(Capsule().stroke(Color.drip.divider, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            Text("Running Log — \(window.plateTitle)".uppercased())
                .font(.dripEyebrow(10))
                .tracking(1.4)
                .foregroundStyle(Color.drip.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: State-aware content

    @ViewBuilder
    private func content(_ proxy: ScrollViewProxy) -> some View {
        let set = bucketSet

        if !set.isEmpty {
            let read = TrendsRead.compute(set)

            TrendsReadHeader(read: read, set: set) { anchor in
                jump(proxy, to: anchor)
            }
            .padding(.top, 22)

            EditorialRule().padding(.vertical, 24)

            section(eyebrow: "Five signals", number: "01",
                    sub: "Mileage, key work, recovery, mood, niggles — one time axis. Drag across to read a day down all five.") {
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
            .id("signals")

            EditorialRule().padding(.vertical, 24)

            section(eyebrow: "Recovery score · \(recoveryDayLabel(set))", number: "02",
                    sub: "Every score shows its own arithmetic. Starts at 50, and each line carries the evidence it moved on.") {
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
            .id("recovery")

            EditorialRule().padding(.vertical, 24)

            section(eyebrow: "What lines up", number: "03",
                    sub: "Computed from the window in view. When there isn't enough to say, it says that.") {
                TrendsFindingsView(findings: read.findings).padding(.top, 6)
            }
            .id("findings")

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
                cta: .init(label: "Back to 30 days") { window = .thirtyDays }
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

    // MARK: Section chrome

    @ViewBuilder
    private func section<Content: View>(
        eyebrow: String,
        number: String,
        sub: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                DripEyebrow(text: eyebrow)
                Spacer(minLength: 8)
                Text(number)
                    .font(.dripEyebrow(9))
                    .tracking(1.3)
                    .foregroundStyle(Color.drip.textTertiary)
            }
            Text(sub)
                .font(.dripBody(12.5))
                .foregroundStyle(Color.drip.textSecondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
            content()
        }
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
            keySessions: KeySession.previewLadder
        )
    )
}

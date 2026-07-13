//
//  TrendsTabView.swift
//  RunningLog
//
//  The **Trends** tab — revived as the chart-centric "show me what I can't
//  see" surface (the tab was previously a tombstone; see git history in
//  this folder). Built from the approved prototype `trends-tab-prototype.html`.
//
//  Structure: editorial header → range segmenter → live readout → the
//  unified multi-track chart (`UnifiedTrainingChart`) → auto-surfaced
//  pattern insights → an ask bar that hands off to The Read.
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

struct TrendsTabView: View {
    @Environment(\.selectedTab) private var selectedTab
    @Environment(\.coachAsk) private var coachAsk

    @State private var range: TrendsRange = .twelveWeek
    @State private var scrubIndex: Int?
    @State private var service: TrendsService
    /// D · deep-dive group (Effort · Fitness · Signal) — swaps the rows below.
    @State private var deepGroup: DeepGroup = .fitness
    /// Which deep-dive row is expanded in place (by title); nil = all collapsed.
    @State private var expandedRow: String?
    private enum DeepGroup: String, CaseIterable {
        case effort = "Effort", fitness = "Fitness", signal = "Signal"
    }

    init(service: TrendsService = .shared) {
        _service = State(initialValue: service)
    }

    /// The selected window, sliced from the loaded timeline.
    private var window: [TrendsWeek] {
        Array(service.weeks.suffix(range.rawValue))
    }

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
            if selectedTab.wrappedValue == 4 { await service.refresh() }
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

    private var loadedContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // A · the 5-second view — what moved this week, one card per group.
            Text("THIS WEEK")
                .font(.dripEyebrow(11)).tracking(1.3)
                .foregroundStyle(Color.drip.textSecondary)
                .padding(.top, 14)
            thisWeekStrip
                .padding(.top, 8)

            segmenter
                .padding(.top, 20)

            readout
                .padding(.top, 14)

            UnifiedTrainingChart(weeks: window, scrubIndex: $scrubIndex)
                .padding(.top, 6)

            RacePredictionTrack()
                .padding(.top, 14)

            goDeeper
                .padding(.top, 16)

            EditorialRule()
                .padding(.vertical, 20)

            insights

            askBar
                .padding(.top, 18)
        }
    }

    // MARK: drill-down entries

    /// Each track on the timeline opens a full detail screen. Destinations
    /// are driven by the full loaded window (not the range slice) so the
    /// detail is rich regardless of the overview's selected range.
    private var goDeeper: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("GO DEEPER")
                .font(.dripEyebrow(11)).tracking(1.3)
                .foregroundStyle(Color.drip.textSecondary)
                .padding(.bottom, 10)

            // Group sub-nav — one group's rows show at a time (swap, not scroll).
            deepGroupNav
                .padding(.bottom, 4)

            switch deepGroup {
            case .effort:
                expandableRow("Training volume", "Load, intensity & the safe band") {
                    VolumeDetailView(
                        weeks: service.weeks,
                        flagged: service.flagged,
                        trimmed: service.trimmed,
                        onSetExcluded: { id, excluded in
                            Task { await service.setExcluded(id, excluded: excluded) }
                        },
                        embedded: true
                    )
                }
            case .fitness:
                expandableRow("Key sessions", "Same-effort pace + rep splits") {
                    KeySessionsDetailView(sessions: service.keySessions, volume: service.keyVolume, embedded: true)
                }
            case .signal:
                expandableRow("Mood", "How the block has felt") {
                    MoodDetailView(weeks: service.weeks, embedded: true)
                }
                expandableRow("Niggles", "Recurrence, in your words") {
                    NigglesDetailView(weeks: service.weeks, embedded: true)
                }
            }
        }
    }

    /// Segmented Effort · Fitness · Signal switcher. Active segment reads coral
    /// (the one coral accent in this cluster, per the three-palette rule).
    private var deepGroupNav: some View {
        HStack(spacing: 0) {
            ForEach(DeepGroup.allCases, id: \.self) { g in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { deepGroup = g }
                } label: {
                    Text(g.rawValue.uppercased())
                        .font(.dripEyebrow(10)).tracking(1.0)
                        .foregroundStyle(deepGroup == g ? Color.drip.coral : Color.drip.textTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(deepGroup == g ? Color.drip.cardBackgroundElevated : Color.clear)
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.drip.divider, lineWidth: 1))
    }

    /// A summary row that expands its chart IN PLACE (no push-navigation). The
    /// content is the detail view rendered `embedded: true` (bare, no scroll/nav).
    private func expandableRow<Content: View>(
        _ title: String,
        _ subtitle: String,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        let isOpen = expandedRow == title
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) {
                    expandedRow = isOpen ? nil : title
                }
            } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title.uppercased())
                            .font(.dripEyebrow(10)).tracking(1.0)
                            .foregroundStyle(Color.drip.textSecondary)
                        Text(subtitle)
                            .font(.dripBody(14))
                            .foregroundStyle(Color.drip.textPrimary)
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isOpen ? Color.drip.coral : Color.drip.textTertiary)
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                }
                .padding(.vertical, 12)
                .contentShape(Rectangle())
                .overlay(Rectangle().fill(Color.drip.divider).frame(height: 1), alignment: .bottom)
            }
            .buttonStyle(.plain)

            if isOpen {
                content()
                    .padding(.top, 10)
                    .padding(.bottom, 14)
            }
        }
    }

    // MARK: this-week strip (the 5-second "what changed" answer)

    /// Most recent week with real training; the strip describes it.
    private var latestWeek: TrendsWeek? { window.last(where: { $0.miles > 0 }) ?? window.last }
    private var priorWeek: TrendsWeek? {
        guard let cur = latestWeek, let idx = window.firstIndex(where: { $0.id == cur.id }) else { return nil }
        return window[..<idx].last(where: { $0.miles > 0 })
    }
    private var latestKeyWeek: TrendsWeek? { window.last(where: { $0.keyPaceSec != nil }) }
    private var priorKeyWeek: TrendsWeek? {
        guard let cur = latestKeyWeek, let idx = window.firstIndex(where: { $0.id == cur.id }) else { return nil }
        return window[..<idx].last(where: { $0.keyPaceSec != nil })
    }
    private func paceStr(_ sec: Int) -> String { "\(sec / 60):\(String(format: "%02d", sec % 60))" }
    /// Neutral delta with a direction arrow (no green/coral — three-palette rule).
    private func deltaStr(_ d: Double, unit: String) -> String? {
        let r = Int(d.rounded())
        guard r != 0 else { return nil }
        return "\(r > 0 ? "↑" : "↓") \(abs(r))\(unit)"
    }
    private var signalValue: String {
        guard let cur = latestWeek else { return "—" }
        if let n = cur.niggles.first(where: { !$0.isEmpty }) { return n.lowercased() }
        return cur.mood.isEmpty ? "clear" : cur.mood.lowercased()
    }

    /// A · the horizontal what-changed strip: one card per deep-dive group
    /// (Effort · Fitness · Signal), each tappable into its detail view.
    private var thisWeekStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                if let cur = latestWeek {
                    stripCard(eyebrow: "EFFORT",
                              value: "\(Int(cur.miles.rounded())) mi",
                              delta: priorWeek.flatMap { deltaStr(cur.miles - $0.miles, unit: "") }) {
                        VolumeDetailView(
                            weeks: service.weeks, flagged: service.flagged, trimmed: service.trimmed,
                            onSetExcluded: { id, ex in Task { await service.setExcluded(id, excluded: ex) } }
                        )
                    }
                }
                if let kw = latestKeyWeek, let kp = kw.keyPaceSec {
                    stripCard(eyebrow: "FITNESS",
                              value: "\(paceStr(kp))/mi",
                              delta: priorKeyWeek?.keyPaceSec.flatMap { deltaStr(Double(kp - $0), unit: "s") }) {
                        KeySessionsDetailView(sessions: service.keySessions, volume: service.keyVolume)
                    }
                }
                stripCard(eyebrow: "SIGNAL", value: signalValue, delta: nil) {
                    NigglesDetailView(weeks: service.weeks)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func stripCard<Destination: View>(
        eyebrow: String, value: String, delta: String?,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(eyebrow)
                    .font(.dripEyebrow(9)).tracking(1.0)
                    .foregroundStyle(Color.drip.textTertiary)
                Text(value)
                    .font(.dripDisplay(20))
                    .foregroundStyle(Color.drip.textPrimary)
                    .lineLimit(1)
                Text(delta ?? " ")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.drip.textSecondary)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(minWidth: 118, alignment: .leading)
            .background(Color.drip.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.drip.divider, lineWidth: 1))
        }
        .buttonStyle(.plain)
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
            Text("TRENDS · \(Self.todayLabel)")
                .font(.dripEyebrow(11))
                .tracking(1.3)
                .foregroundStyle(Color.drip.coral)

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

    // MARK: range segmenter

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
            .animation(.easeInOut(duration: 0.12), value: week.id)
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

    // MARK: ask bar

    private var askBar: some View {
        Button {
            // Stage a question about the scrubbed (or latest) week, then
            // hand off to The Read (tab tag 2), which presents the composer.
            if let week = readoutWeek {
                coachAsk.stage(
                    question: Self.askPrompt(for: week),
                    focus: "week of \(week.dateLabel)"
                )
            }
            selectedTab.wrappedValue = 2
        } label: {
            HStack(spacing: 10) {
                Text("Ask about a week, a pattern, a pace…")
                    .font(.dripBody(14))
                    .foregroundStyle(Color.drip.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ZStack {
                    Circle()
                        .fill(Color.drip.coral)
                        .frame(width: 30, height: 30)
                    Image(systemName: "mic.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(Color.drip.cardBackground)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.drip.divider, lineWidth: 1))
        }
        .buttonStyle(.plain)
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

    /// Build the contextual question the ask bar stages for a given week.
    /// Kept light — the coach has the full picture; this just points it at
    /// the week the athlete was looking at.
    private static func askPrompt(for w: TrendsWeek) -> String {
        "Walk me through the week of \(w.dateLabel) — \(Int(w.miles)) mi. What stands out?"
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

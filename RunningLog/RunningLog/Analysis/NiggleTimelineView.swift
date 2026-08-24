//
//  NiggleTimelineView.swift
//  RunningLog
//
//  The niggle mention-timeline, as a collapsed summary card that expands in
//  place. Port of the web prototype `/design/niggles` (PR #11) onto the
//  Analysis tab, reading real `body_mentions` via `InjuryService`.
//
//  Palette discipline, carried over from the rebrand commit — the three
//  palettes never share hues (DesignSystem.swift):
//
//   • The training overlay is INTENSITY data, so it draws on the blue pace
//     ramp (`PaceSpectrum.easy`), never on the warm paper greys it borrowed
//     in the first prototype.
//   • Coral is ALERT only: an active mention, the active tile, section
//     eyebrows. Not selection state, not a link colour, not a bar fill.
//   • Green is MOOD only. A resolved niggle is not a mood, so status is
//     encoded by ink weight and *form* — a resolved dot is hollow, a quiet
//     thread trails off dashed. That also beats colour-only encoding for
//     VoiceOver and for anyone who cannot separate the two hues.
//

import SwiftUI

// MARK: - Card

/// Collapsed: one 44pt row with a sparkline. Expanded: the full timeline,
/// its threads and the co-occurrence tallies, in place. Per `trends.md` this
/// must never become a card inside a card, so the expanded body sheds chrome.
struct NiggleTimelineCard: View {
    let timeline: NiggleTimeline

    @State private var isExpanded = false
    @State private var selectedThread: String?

    private var scopedThreads: [NiggleThread] {
        guard let key = selectedThread else { return timeline.threads }
        return timeline.threads.filter { $0.id == key }
    }

    private var scopedMentions: [NiggleMention] {
        scopedThreads.flatMap(\.mentions)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            summaryRow

            if isExpanded {
                VStack(alignment: .leading, spacing: 20) {
                    NiggleTimelineChart(
                        timeline: timeline,
                        selectedThread: $selectedThread
                    )

                    if selectedThread != nil {
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) { selectedThread = nil }
                        } label: {
                            Text("Clear filter")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .tracking(1.2)
                                .foregroundStyle(Color.drip.textSecondary)
                                .underline()
                        }
                        .buttonStyle(.plain)
                    }

                    ForEach(scopedThreads) { thread in
                        NiggleThreadRow(thread: thread)
                    }

                    tallies
                }
                .padding(.top, 18)
                .transition(.opacity)
            }
        }
    }

    // MARK: Collapsed row
    //
    // 44pt is the brief's minimum touch target, and it is the whole point of
    // the summary-card pattern: eight scannable rows instead of eight
    // full-bleed charts. The facts here are counts, never a reading.

    private var summaryRow: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("NIGGLE TIMELINE")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .tracking(1.4)
                        .foregroundStyle(Color.drip.textPrimary)

                    Text(summaryLine)
                        .font(.system(size: 11, design: .monospaced))
                        .tracking(0.6)
                        .foregroundStyle(Color.drip.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                Spacer(minLength: 8)

                NiggleSparkline(counts: timeline.mentionsPerWeek)
                    .frame(width: 72, height: 20)

                Text(isExpanded ? "▾" : "▸")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Color.drip.textTertiary)
                    .frame(width: 14)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Niggle timeline. \(summaryLine)")
        .accessibilityHint(isExpanded ? "Collapses the timeline" : "Expands the timeline")
        .accessibilityAddTraits(.isButton)
    }

    private var summaryLine: String {
        var parts = [
            "\(timeline.threads.count) body area\(timeline.threads.count == 1 ? "" : "s")",
            "\(timeline.totalMentions) mention\(timeline.totalMentions == 1 ? "" : "s")",
            "\(timeline.weeks.count) weeks",
        ]
        if timeline.activeCount > 0 { parts.append("\(timeline.activeCount) ACTIVE") }
        return parts.joined(separator: "  ·  ")
    }

    // MARK: Co-occurrence
    //
    // Counting, not causation. Handoff §5.2: these are phrased as tallies and
    // withheld entirely below `minTallyMentions`, so one data point can never
    // read as a pattern. The dashboard does not finish the sentence.

    @ViewBuilder
    private var tallies: some View {
        let bands = NiggleTimelineBuilder.volumeBands(
            mentions: scopedMentions, weeks: timeline.weeks
        )
        if !bands.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("MENTIONS BY WEEKLY VOLUME")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(Color.drip.coral)

                ForEach(bands) { tally in
                    HStack(spacing: 10) {
                        Text(tally.label)
                            .font(.system(size: 12, design: .serif))
                            .foregroundStyle(Color.drip.textSecondary)
                        Spacer(minLength: 8)
                        Text("\(tally.count)")
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.drip.textPrimary)
                    }
                }

                Text("Counts of what the log already says. Not a cause.")
                    .font(.system(size: 11, design: .serif).italic())
                    .foregroundStyle(Color.drip.textTertiary)
                    .padding(.top, 2)
            }
        }
    }
}

// MARK: - Sparkline

/// Mentions per week. Deliberately unlabelled and unscaled against anything
/// but itself — it is a shape cue for the collapsed row, not a reading.
struct NiggleSparkline: View {
    let counts: [Int]

    var body: some View {
        GeometryReader { geo in
            let peak = max(counts.max() ?? 0, 1)
            let slot = counts.isEmpty ? 0 : geo.size.width / CGFloat(counts.count)
            let barW = max(slot - 1.5, 1)

            ZStack(alignment: .bottomLeading) {
                ForEach(Array(counts.enumerated()), id: \.offset) { idx, count in
                    let h = count == 0 ? 1 : geo.size.height * CGFloat(count) / CGFloat(peak)
                    Rectangle()
                        .fill(count == 0
                              ? Color.drip.divider
                              : Color.drip.textPrimary.opacity(0.55))
                        .frame(width: barW, height: max(h, 1))
                        .offset(x: CGFloat(idx) * slot, y: 0)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Timeline chart

/// 16 weeks across. Weekly volume draws behind as a blue wash; each thread
/// gets a lane, each mention a dot. Row-tap scopes to a thread — the handoff's
/// open decision #3, settled toward row-tap as primary because precise
/// dot-tapping is a poor primary gesture at this density; dots stay tappable
/// as a convenience.
struct NiggleTimelineChart: View {
    let timeline: NiggleTimeline
    @Binding var selectedThread: String?

    private let laneHeight: CGFloat = 30

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("16 WEEKS  ·  WEEKLY VOLUME BEHIND")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(Color.drip.coral)

            GeometryReader { geo in
                let slot = timeline.weeks.isEmpty
                    ? 0 : geo.size.width / CGFloat(timeline.weeks.count)

                ZStack(alignment: .topLeading) {
                    overlay(slot: slot, height: geo.size.height)
                    lanes(slot: slot)
                }
            }
            .frame(height: laneHeight * CGFloat(max(timeline.threads.count, 1)))

            axis
        }
    }

    // The training overlay. Blue pace ramp, washed — it is context behind the
    // mentions, not the subject. The in-progress week is drawn LIGHTER so an
    // incomplete week never reads as more solid than a finished one.
    private func overlay(slot: CGFloat, height: CGFloat) -> some View {
        let peak = max(timeline.weeks.map(\.miles).max() ?? 0, 1)
        return ZStack(alignment: .bottomLeading) {
            ForEach(Array(timeline.weeks.enumerated()), id: \.element.start) { idx, week in
                let h = height * CGFloat(week.miles / peak)
                Rectangle()
                    .fill(PaceSpectrum.easy.opacity(week.partial ? 0.16 : 0.34))
                    .frame(width: max(slot - 2, 1), height: max(h, 0))
                    .offset(x: CGFloat(idx) * slot)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .accessibilityHidden(true)
    }

    private func lanes(slot: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(timeline.threads) { thread in
                NiggleLane(
                    thread: thread,
                    weeks: timeline.weeks,
                    slot: slot,
                    isDimmed: selectedThread != nil && selectedThread != thread.id
                )
                .frame(height: laneHeight)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selectedThread = selectedThread == thread.id ? nil : thread.id
                    }
                }
            }
        }
    }

    private var axis: some View {
        HStack {
            Text(Self.monthDay.string(from: timeline.spanStart).uppercased())
            Spacer()
            Text("TODAY")
                .foregroundStyle(Color.drip.coral)
        }
        .font(.system(size: 9, weight: .medium, design: .monospaced))
        .tracking(1.2)
        .foregroundStyle(Color.drip.textTertiary)
    }

    static let monthDay: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "MMM d"
        df.timeZone = TimeZone(identifier: "UTC")
        df.locale = Locale(identifier: "en_US_POSIX")
        return df
    }()
}

// MARK: - One thread lane

struct NiggleLane: View {
    let thread: NiggleThread
    let weeks: [NiggleWeek]
    let slot: CGFloat
    let isDimmed: Bool

    var body: some View {
        ZStack(alignment: .leading) {
            baseline
            dots
            label
        }
        .opacity(isDimmed ? 0.3 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(thread.label), \(thread.status.label.lowercased()), "
            + "\(thread.mentionCount) mention\(thread.mentionCount == 1 ? "" : "s"), "
            + "last \(thread.daysSinceLast) days ago"
        )
    }

    // Form carries status, not just colour: a quiet thread trails off dashed.
    private var baseline: some View {
        HairlineAcross()
            .stroke(
                Color.drip.divider,
                style: StrokeStyle(lineWidth: 1, dash: thread.status == .quiet ? [2, 3] : [])
            )
            .frame(height: 1)
    }

    private var dots: some View {
        ForEach(thread.mentions) { mention in
            let idx = weeks.firstIndex {
                $0.start == NiggleTimelineBuilder.weekStart(of: mention.mentionedAt)
            }
            if let idx {
                dot
                    // Centre the dot in its week slot. Half of the 30pt hit
                    // area, not half the 8pt circle — the hit area is what
                    // the layout is actually sized to.
                    .offset(x: CGFloat(idx) * slot + slot / 2 - 15)
            }
        }
    }

    // Coral is alert, so only an ACTIVE thread's mentions earn it. A resolved
    // dot is hollow — status readable without relying on hue.
    @ViewBuilder
    private var dot: some View {
        Group {
            switch thread.status {
            case .active:
                Circle().fill(Color.drip.coral)
            case .quiet:
                Circle().fill(Color.drip.textTertiary)
            case .resolved:
                Circle().strokeBorder(Color.drip.textTertiary, lineWidth: 1)
            }
        }
        .frame(width: 8, height: 8)
        // 30pt hit area around an 8pt dot, per the handoff's touch audit.
        .frame(width: 30, height: 30)
        .contentShape(Rectangle())
    }

    private var label: some View {
        Text(thread.label.uppercased())
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .tracking(1.1)
            .foregroundStyle(
                thread.status == .active ? Color.drip.coral : Color.drip.textTertiary
            )
            .offset(y: -11)
    }
}

/// A 1pt rule that spans whatever width it is given. A fixed-width `Path`
/// would draw outside the lane and break the no-horizontal-overflow rule the
/// prototype was measured against.
private struct HairlineAcross: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return p
    }
}

// MARK: - Thread detail

struct NiggleThreadRow: View {
    let thread: NiggleThread

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(thread.label)
                    .font(.dripDisplay(20))
                    .foregroundStyle(Color.drip.textPrimary)
                Text(thread.status.label)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .tracking(1.3)
                    .foregroundStyle(
                        thread.status == .active ? Color.drip.coral : Color.drip.textTertiary
                    )
                Spacer(minLength: 4)
            }

            Text(eyebrow)
                .font(.system(size: 11, design: .monospaced))
                .tracking(0.6)
                .foregroundStyle(Color.drip.textSecondary)

            if let quote = thread.lastQuote, !quote.isEmpty {
                // The coach-quote primitive: a 2px coral left bar. This is one
                // of the few places coral still earns its keep.
                HStack(alignment: .top, spacing: 10) {
                    Rectangle()
                        .fill(Color.drip.coral)
                        .frame(width: 2)
                    Text("\u{201C}\(quote)\u{201D}")
                        .font(.system(size: 13, design: .serif).italic())
                        .foregroundStyle(Color.drip.textPrimary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var eyebrow: String {
        var parts = [
            "\(thread.mentionCount) mention\(thread.mentionCount == 1 ? "" : "s")",
            "\(thread.daysSinceLast)d since last",
        ]
        if thread.spanDays > 0 { parts.append("over \(thread.spanDays)d") }
        // A return is the one derived fact worth calling out — the athlete
        // said it came back after a gap. Still a count, not a diagnosis.
        if let last = thread.returns.last {
            parts.append("returned after \(last.afterDays)d")
        }
        return parts.joined(separator: "  ·  ")
    }
}

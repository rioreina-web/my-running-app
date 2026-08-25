//
//  NiggleTimelineView.swift
//  RunningLog
//
//  REBUILT 2026-08-24. The first render was a four-lane shared chart with the
//  body-area labels drawn inside the plot and weekly volume as full-height
//  bars behind them. On mock data (15 mentions spread evenly over 16 weeks)
//  that read fine. On real data — 9 mentions, most of them in the last two
//  weeks, against near-constant 65 mi weeks — it collapsed: the labels
//  overprinted the bars, the bars carried no information because they barely
//  varied, and every mark crushed into the right-hand edge.
//
//  So the structure inverts. Each body area gets its own block with its own
//  strip, all sharing one time axis so they stay comparable. Labels live
//  outside the plot. Volume drops to a single hairline of context at the
//  bottom instead of competing with every thread.
//
//  Palette discipline is unchanged: coral is ALERT only (an ache mentioned
//  recently), the blue pace ramp carries training data, green is mood-only and
//  therefore never appears here. Status is carried by ink weight and form as
//  well as hue — a settled mark is hollow, a quiet thread's rule is dashed —
//  so it survives without colour.
//

import SwiftUI

// MARK: - Card (collapsed entry point, used on the injuries screen)

struct NiggleTimelineCard: View {
    let timeline: NiggleTimeline
    /// Marks a thread resolved. Omitted where no service is in reach, in which
    /// case the action simply does not render.
    let onResolve: ((NiggleThread) -> Void)?

    @State private var isExpanded: Bool

    init(timeline: NiggleTimeline,
         startExpanded: Bool = false,
         onResolve: ((NiggleThread) -> Void)? = nil) {
        self.timeline = timeline
        self.onResolve = onResolve
        _isExpanded = State(initialValue: startExpanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !isExpanded { summaryRow }
            if isExpanded { NiggleTimelineBody(timeline: timeline, onResolve: onResolve) }
        }
    }

    private var summaryRow: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { isExpanded = true }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("NIGGLE TIMELINE")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .tracking(1.4)
                        .foregroundStyle(Color.drip.textPrimary)
                    Text(summaryLine)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.drip.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Spacer(minLength: 8)
                Text("▸")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Color.drip.textTertiary)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Niggle timeline. \(summaryLine)")
    }

    private var summaryLine: String {
        let areas = timeline.threads.count
        return "\(areas) area\(areas == 1 ? "" : "s")  ·  \(timeline.totalMentions) mentions"
    }
}

// MARK: - The body

struct NiggleTimelineBody: View {
    let timeline: NiggleTimeline
    var onResolve: ((NiggleThread) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(timeline.threads.enumerated()), id: \.element.id) { idx, thread in
                NiggleThreadBlock(thread: thread, timeline: timeline, onResolve: onResolve)
                if idx < timeline.threads.count - 1 {
                    EditorialRule().padding(.vertical, 20)
                }
            }

            axis.padding(.top, 22)
            NiggleVolumeStrip(timeline: timeline).padding(.top, 10)
        }
    }

    /// The span is open-ended — it runs from the first ache ever recorded to
    /// today — so the axis has to stay readable whether that is six weeks or
    /// six years. Ticks spread evenly and switch to month-year past a year.
    ///
    /// Laid out with spacers rather than absolute positioning: `.position`
    /// centres a label on its coordinate, which ran the end labels off the
    /// edge and collided them ("TODAYM"). Even spacing is what an axis row
    /// actually needs, and it cannot overlap.
    private var axis: some View {
        HStack(spacing: 4) {
            ForEach(Array(axisTicks.enumerated()), id: \.offset) { idx, label in
                if idx > 0 { Spacer(minLength: 2) }
                Text(label)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .tracking(1.1)
                    .foregroundStyle(Color.drip.textTertiary)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }

    private var axisTicks: [String] {
        let totalDays = NiggleTimelineBuilder.days(
            from: timeline.spanStart, to: timeline.spanEnd
        )
        let fmt = totalDays > 365 ? Self.axisMonthYear : Self.axisDate

        // One interior tick per ~120 days, capped at 2 so nothing crowds.
        let interior = max(0, min(2, totalDays / 120 - 1))
        var out = [fmt.string(from: timeline.spanStart).uppercased()]
        if interior > 0 {
            for i in 1...interior {
                let f = Double(i) / Double(interior + 1)
                let d = timeline.spanStart.addingTimeInterval(
                    timeline.spanEnd.timeIntervalSince(timeline.spanStart) * f
                )
                out.append(fmt.string(from: d).uppercased())
            }
        }
        out.append("TODAY")
        return out
    }

    static let axisDate: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "MMM d"
        df.timeZone = TimeZone(identifier: "UTC")
        df.locale = Locale(identifier: "en_US_POSIX")
        return df
    }()

    static let axisMonthYear: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "MMM ''yy"
        df.timeZone = TimeZone(identifier: "UTC")
        df.locale = Locale(identifier: "en_US_POSIX")
        return df
    }()
}

// MARK: - One body area

struct NiggleThreadBlock: View {
    let thread: NiggleThread
    let timeline: NiggleTimeline
    var onResolve: ((NiggleThread) -> Void)? = nil

    private var accent: Color {
        thread.status == .active ? Color.drip.coral : Color.drip.textTertiary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header — name left, recency right. Both outside the plot.
            HStack(alignment: .firstTextBaseline) {
                Text(thread.label)
                    .font(.dripDisplay(22))
                    .foregroundStyle(Color.drip.textPrimary)
                Spacer(minLength: 8)
                Text(thread.recencyLine.uppercased())
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .tracking(1.1)
                    .foregroundStyle(accent)
                    .lineLimit(1)
            }

            Text(factLine)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.drip.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            NiggleStrip(thread: thread, timeline: timeline)
                .frame(height: 22)

            if let quote = cleanedQuote {
                HStack(alignment: .top, spacing: 10) {
                    Rectangle().fill(accent).frame(width: 2)
                    Text("\u{201C}\(quote)\u{201D}")
                        .font(.system(size: 13, design: .serif).italic())
                        .foregroundStyle(Color.drip.textPrimary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let note = positiveNoteLine {
                Text(note)
                    .font(.system(size: 11, design: .serif).italic())
                    .foregroundStyle(Color.drip.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // The athlete's own all-clear. This is the trustworthy path —
            // `niggle_resolutions` rows written by the extractor demonstrably
            // include complaints, but a tap here is a declaration.
            if thread.status != .settled, let onResolve {
                Button { onResolve(thread) } label: {
                    Text("MARK RESOLVED")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .tracking(1.3)
                        .foregroundStyle(Color.drip.textSecondary)
                        .underline()
                        .frame(minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Mark \(thread.label) resolved")
            } else if thread.status == .settled {
                Text("MARKED RESOLVED")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .tracking(1.3)
                    .foregroundStyle(Color.drip.textTertiary)
                    .padding(.top, 4)
            }
        }
    }

    private var factLine: String {
        var parts = ["\(thread.mentionCount) mention\(thread.mentionCount == 1 ? "" : "s")"]
        if let side = thread.sideNote { parts.append(side) }
        parts.append("since \(NiggleTimelineBody.axisDate.string(from: thread.firstSeen))")
        if let last = thread.returns.last { parts.append("back after \(last.afterDays)d") }
        return parts.joined(separator: "  ·  ")
    }

    /// The extractor stores quotes already clipped, often with a leading
    /// ellipsis mid-sentence. Strip it rather than render "…​…".
    private var cleanedQuote: String? {
        guard var q = thread.lastQuote?.trimmingCharacters(in: .whitespacesAndNewlines),
              !q.isEmpty else { return nil }
        while q.hasPrefix(".") || q.hasPrefix("…") { q.removeFirst() }
        return q.trimmingCharacters(in: .whitespaces)
    }

    /// `niggle_resolutions` holds both all-clears and complaints, so this is
    /// phrased as "you also said" — a count of what was said, not a verdict
    /// that the ache is over.
    private var positiveNoteLine: String? {
        let n = thread.positiveNotes.count
        guard n > 0 else { return nil }
        guard let latest = thread.positiveNotes.last else { return nil }
        let when = NiggleTimelineBody.axisDate.string(from: latest.on)
        return n == 1
            ? "One other note on this, \(when)."
            : "\(n) other notes on this, most recently \(when)."
    }
}

// MARK: - The strip

/// One thread's mentions across the shared span. A dot per mention, placed by
/// date. Because every strip uses the same span, a new ache visibly clusters
/// at the right while a long-running one spreads.
struct NiggleStrip: View {
    let thread: NiggleThread
    let timeline: NiggleTimeline

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let midY = geo.size.height / 2

            ZStack(alignment: .topLeading) {
                // Baseline — dashed when the thread has gone quiet.
                Path { p in
                    p.move(to: CGPoint(x: 0, y: midY))
                    p.addLine(to: CGPoint(x: w, y: midY))
                }
                .stroke(
                    Color.drip.divider,
                    style: StrokeStyle(
                        lineWidth: 1,
                        dash: thread.status == .quiet ? [2, 3] : []
                    )
                )

                ForEach(weekBuckets, id: \.day) { bucket in
                    mark(heavy: bucket.count > 1)
                        .position(
                            x: inset(CGFloat(timeline.position(of: bucket.day)) * w, in: w),
                            y: midY
                        )
                }
            }
        }
    }

    /// Keep a mark on the very first or last day fully inside the strip.
    private func inset(_ x: CGFloat, in w: CGFloat) -> CGFloat {
        min(max(x, 5), w - 5)
    }

    /// One mark per week. Mentions a day or two apart sit within a few points
    /// of each other at this scale and would fuse into a blob; bucketing keeps
    /// each mark legible and lets a busy week read heavier instead.
    private var weekBuckets: [(day: Date, count: Int)] {
        var counts: [Date: Int] = [:]
        for m in thread.mentions {
            counts[NiggleTimelineBuilder.weekStart(of: m.mentionedAt), default: 0] += 1
        }
        return counts.keys.sorted().map { (day: $0, count: counts[$0] ?? 1) }
    }

    @ViewBuilder
    private func mark(heavy: Bool) -> some View {
        let d: CGFloat = heavy ? 12 : 9
        switch thread.status {
        case .active:
            Circle().fill(Color.drip.coral).frame(width: d, height: d)
        case .quiet:
            Circle().fill(Color.drip.textTertiary).frame(width: d - 1, height: d - 1)
        case .settled:
            Circle()
                .strokeBorder(Color.drip.textTertiary, lineWidth: 1)
                .frame(width: d, height: d)
        }
    }
}

// MARK: - Training context

/// Weekly mileage across the same span — one hairline area, drawn once, so the
/// training behind the mentions is available without competing with them.
struct NiggleVolumeStrip: View {
    let timeline: NiggleTimeline

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("WEEKLY VOLUME BEHIND IT")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(Color.drip.textTertiary)

            GeometryReader { geo in
                let weeks = timeline.weeks
                let peak = max(weeks.map(\.miles).max() ?? 0, 1)
                let slot = weeks.isEmpty ? 0 : geo.size.width / CGFloat(weeks.count)

                ZStack(alignment: .bottomLeading) {
                    ForEach(Array(weeks.enumerated()), id: \.element.start) { idx, week in
                        Rectangle()
                            .fill(PaceSpectrum.easy.opacity(week.partial ? 0.28 : 0.55))
                            .frame(
                                // Years of weeks means sub-point slots — drop
                                // the gap before the bar itself disappears.
                                width: max(slot - (slot > 4 ? 1.5 : 0), 0.75),
                                height: max(geo.size.height * CGFloat(week.miles / peak), 1)
                            )
                            .offset(x: CGFloat(idx) * slot)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                    }
                }
            }
            .frame(height: 26)

            if let peak = timeline.weeks.map(\.miles).max(), peak > 0 {
                Text("peak \(Int(peak.rounded())) mi/wk")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Color.drip.textTertiary)
            }
        }
        .accessibilityHidden(true)
    }
}

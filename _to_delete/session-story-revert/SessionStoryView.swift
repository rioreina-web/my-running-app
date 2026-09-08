//
//  SessionStoryView.swift
//  RunningLog
//
//  One key session, told whole — the Session Story sheet. Opens from the
//  session strip under Trends ▸ Key sessions. Prototype:
//  `session-story-prototype.html` (repo root), approved 2026-07-27.
//
//  Layout, top to bottom (each block degrades honestly when its data is
//  missing — no faked numbers, no em-dash empty states):
//
//    header      name · date · distance/duration
//    pills       kind/zone · mood (from the memo) · niggle
//    hero        raw pace, with heat-neutral + conditions pace ALONGSIDE
//    segments    per-rep (or halves) pace bars, the previous comparable
//                session as a dashed ghost line behind them
//    heart rate  the same segments' HR, its own track and its own scale
//                (never a dual axis)
//    drift       the cost of holding pace — durable-zone gauge
//    then → now  like-for-like deltas against the ghost
//    the day     feels-like · heat cost · hill cost tiles
//    in your words   the voice memo, verbatim, with the niggle quotes
//    the read    observation + soft question (SessionStoryRead — pure,
//                tested; no LLM call on this surface)
//
//  Palette rules (CLAUDE.md): bars wear the blue pace ramp; the ghost and HR
//  wear ink; the drift gauge's safe band is neutral gray (never green);
//  coral appears once, on the section eyebrow.
//

import SwiftUI

struct SessionStoryView: View {
    let keySession: KeySession
    let allSessions: [KeySession]

    @State private var service = SessionStoryService.shared
    @State private var payload: SessionStoryPayload?
    @Environment(\.dismiss) private var dismiss

    private var ghostPick: KeySession? {
        SessionStoryLogic.previousComparable(to: keySession, in: allSessions)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let payload {
                    content(payload)
                } else if service.isLoading {
                    loading
                } else if service.lastError != nil {
                    EmptyStateView(
                        variant: .error,
                        eyebrow: "Couldn't load",
                        title: "This session's story didn't load. Try again in a moment.",
                        cta: .init(label: "Retry") { Task { await reload() } }
                    )
                    .padding(.top, 60)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 40)
        }
        .background(Color.drip.background)
        .task { await reload() }
    }

    @MainActor
    private func reload() async {
        payload = await service.load(logId: keySession.id, compareLogId: ghostPick?.id)
    }

    private var loading: some View {
        VStack(spacing: 14) {
            ProgressView().tint(Color.drip.coral)
            Text("Reading the session…")
                .font(.dripBody(13))
                .foregroundStyle(Color.drip.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    // MARK: - Loaded content

    @ViewBuilder
    private func content(_ p: SessionStoryPayload) -> some View {
        let s = p.session
        header(s)
        pills(s)
            .padding(.top, 10)
        hero(s)
            .padding(.top, 18)

        if !s.segments.isEmpty {
            sectionLabel(s.isReps ? "THE FAST SEGMENTS · PACE PER REP" : "THE EFFORT · PACE BY SEGMENT")
                .padding(.top, 24)
            SessionStoryPaceChart(
                segments: s.segments,
                ghost: p.compare?.segments ?? [],
                zoneColor: zoneColor
            )
            .frame(height: 150)
            .padding(.top, 8)
            legend(p)
                .padding(.top, 8)

            if s.segments.contains(where: { $0.hr != nil }) {
                sectionLabel("HEART RATE · SAME SEGMENTS")
                    .padding(.top, 20)
                SessionStoryHRChart(segments: s.segments)
                    .frame(height: 74)
                    .padding(.top, 8)
                Text(s.isReps
                    ? "Beats per minute across the reps. Climbing HR at level pace is the effort the clock doesn't show."
                    : "Average heart rate by segment. A flat line with a held pace is the durable version of fast.")
                    .font(.dripBody(12))
                    .foregroundStyle(Color.drip.textTertiary)
                    .padding(.top, 6)
            }
        }

        if let drift = s.drift {
            sectionLabel("DRIFT · THE COST OF HOLDING PACE")
                .padding(.top, 22)
            driftCard(drift)
                .padding(.top, 8)
        }

        if let g = p.compare {
            sectionLabel("VS LAST \(s.isReps ? "INTERVALS" : "SUSTAINED") · THEN → NOW")
                .padding(.top, 22)
            thenNowCard(now: s, then: g)
                .padding(.top, 8)
        }

        sectionLabel("THE DAY ITSELF")
            .padding(.top, 22)
        conditionsTiles(s)
            .padding(.top, 8)

        sectionLabel("IN YOUR WORDS")
            .padding(.top, 22)
        memoBlock(s)
            .padding(.top, 8)

        readBlock(s, compare: p.compare)
            .padding(.top, 18)
    }

    // MARK: - Header, pills, hero

    private func header(_ s: SessionStory) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SESSION STORY · \(SessionStoryRead.dateLabel(s.date).uppercased())")
                .font(.dripEyebrow(11)).tracking(1.3)
                .foregroundStyle(Color.drip.coral)
            Text(s.name)
                .font(.dripDisplay(28))
                .foregroundStyle(Color.drip.textPrimary)
            Text(meta(s))
                .font(.dripBody(13))
                .foregroundStyle(Color.drip.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func meta(_ s: SessionStory) -> String {
        var parts: [String] = []
        if let mi = s.totalMiles { parts.append(DistanceFormat.string(miles: mi)) }
        if let min = s.durationMin { parts.append("\(min) min") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func pills(_ s: SessionStory) -> some View {
        HStack(spacing: 8) {
            pill(keySession.isLongRun ? "LONG RUN" : keySession.zone.uppercased(),
                 color: Color.drip.textSecondary)
            if let mood = s.memo?.mood, !mood.isEmpty {
                MoodBadge(mood: mood)
            }
            if let n = s.niggles.first {
                pill("NIGGLE · \([n.side, n.bodyArea].compactMap { $0 }.joined(separator: " ").uppercased())",
                     color: Color.drip.injured)
            }
            Spacer()
        }
    }

    private func pill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.dripEyebrow(9)).tracking(0.8)
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Color.drip.cardBackgroundElevated)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.drip.divider, lineWidth: 1))
    }

    private func hero(_ s: SessionStory) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text("KEY PACE")
                    .font(.dripEyebrow(10)).tracking(1.0)
                    .foregroundStyle(Color.drip.textSecondary)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(TrendsFormat.pace(s.avgPaceSec))
                        .font(.dripStat(32))
                        .foregroundStyle(Color.drip.textPrimary)
                    Text("/mi")
                        .font(.dripBody(12))
                        .foregroundStyle(Color.drip.textTertiary)
                }
                if let adjusted = s.conditionsPaceSec ?? s.neutralPaceSec {
                    Text(adjustedLine(s, adjusted: adjusted))
                        .font(.dripCaption(10))
                        .foregroundStyle(Color.drip.textSecondary)
                }
            }
            Spacer()
            if let hr = s.hr {
                VStack(alignment: .trailing, spacing: 5) {
                    Text("EFFORT HR")
                        .font(.dripEyebrow(10)).tracking(1.0)
                        .foregroundStyle(Color.drip.textSecondary)
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text("\(hr.avg)")
                            .font(.dripStat(24))
                            .foregroundStyle(Color.drip.textPrimary)
                        Text("bpm")
                            .font(.dripBody(12))
                            .foregroundStyle(Color.drip.textTertiary)
                    }
                    Text(hrSub(hr))
                        .font(.dripCaption(10))
                        .foregroundStyle(Color.drip.textTertiary)
                }
            }
        }
    }

    private func adjustedLine(_ s: SessionStory, adjusted: Int) -> String {
        var costs: [String] = []
        if let h = s.heat, h.costSecPerMi > 0 { costs.append("heat \(h.costSecPerMi)s") }
        if let g = s.grade, let c = g.costSecPerMi, c > 0 { costs.append("hills \(c)s") }
        let label = costs.isEmpty ? "" : " · \(costs.joined(separator: " · ")) /mi"
        return "flat + cool \(TrendsFormat.pace(adjusted))\(label)"
    }

    private func hrSub(_ hr: StoryHR) -> String {
        var parts: [String] = []
        if let max = hr.max { parts.append("max \(max)") }
        if let mpb = hr.metersPerBeat { parts.append(String(format: "%.2f m/beat", mpb)) }
        return parts.joined(separator: " · ")
    }

    // MARK: - Legend, drift, then→now, conditions, memo, read

    @ViewBuilder
    private func legend(_ p: SessionStoryPayload) -> some View {
        HStack(spacing: 14) {
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(zoneColor)
                    .frame(width: 10, height: 10)
                Text("THIS SESSION")
                    .font(.dripEyebrow(9)).tracking(0.6)
                    .foregroundStyle(Color.drip.textSecondary)
            }
            if let ghost = ghostPick, !(p.compare?.segments.isEmpty ?? true) {
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(Color.drip.textTertiary, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                        .frame(width: 10, height: 10)
                    Text("LAST · \((ghost.structure ?? ghost.zone).uppercased()) (\(ghost.dateLabel.uppercased()))")
                        .font(.dripEyebrow(9)).tracking(0.6)
                        .foregroundStyle(Color.drip.textSecondary)
                }
            }
        }
    }

    private func driftCard(_ drift: StoryDrift) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            if drift.meaningful {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(driftValueLabel(drift))
                        .font(.dripStat(22))
                        .foregroundStyle(Color.drip.textPrimary)
                    Text(DriftTier.tier(for: drift).rawValue)
                        .font(.dripEyebrow(9)).tracking(0.8)
                        .foregroundStyle(tierColor(DriftTier.tier(for: drift)))
                }
                if drift.kind == "decoupling" {
                    DriftGauge(valuePct: drift.value)
                        .frame(height: 22)
                }
                Text(driftSentence(drift))
                    .font(.dripBody(12))
                    .foregroundStyle(Color.drip.textSecondary)
            } else {
                Text(drift.note)
                    .font(.dripBody(12))
                    .foregroundStyle(Color.drip.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.drip.divider, lineWidth: 1))
    }

    private func driftValueLabel(_ d: StoryDrift) -> String {
        d.kind == "decoupling"
            ? String(format: "%.1f%%", d.value)
            : String(format: "%+.0f bpm", d.value)
    }

    private func driftSentence(_ d: StoryDrift) -> String {
        if d.kind == "decoupling" {
            switch DriftTier.tier(for: d) {
            case .durable: return "Second-half heart rate held with pace — inside the durable zone; the engine paid for this one comfortably."
            case .creeping: return "Second-half heart rate ran ahead of pace — just past the durable zone; the last stretch cost more than the clock admits."
            case .high: return "Second-half heart rate ran well ahead of pace — the finish was bought on credit."
            }
        }
        return d.value >= 0
            ? "Heart rate rose \(Int(d.value.rounded())) bpm from the first reps to the last at similar pace — the effort the clock doesn't show."
            : "Heart rate came down across the set even as the reps held — the recovery was doing its job."
    }

    private func tierColor(_ t: DriftTier) -> Color {
        switch t {
        case .durable: return Color.drip.textSecondary // safe band stays neutral, never green
        case .creeping: return Color.drip.tired
        case .high: return Color.drip.coralDeep
        }
    }

    private func thenNowCard(now s: SessionStory, then g: SessionStory) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("\(g.name) → \(s.name)")
                    .font(.dripLabel(13))
                    .foregroundStyle(Color.drip.textPrimary)
                    .lineLimit(1)
                Spacer()
                Text("\(SessionStoryRead.dateLabel(g.date).uppercased()) → \(SessionStoryRead.dateLabel(s.date).uppercased())")
                    .font(.dripEyebrow(8)).tracking(0.6)
                    .foregroundStyle(Color.drip.textTertiary)
            }
            .padding(.bottom, 6)

            deltaRow("KEY PACE /MI", now: s.avgPaceSec, then: g.avgPaceSec, pace: true, lowerIsBetter: true)
            deltaRow("FLAT + COOL /MI",
                     now: s.conditionsPaceSec ?? s.neutralPaceSec,
                     then: g.conditionsPaceSec ?? g.neutralPaceSec,
                     pace: true, lowerIsBetter: true)
            deltaRow("EFFORT HR BPM", now: s.hr?.avg, then: g.hr?.avg, pace: false, lowerIsBetter: true)
            deltaRow("FEELS-LIKE °F", now: s.heat?.tempF, then: g.heat?.tempF, pace: false, lowerIsBetter: true)
            deltaRow("CLIMB M", now: s.grade?.elevGainM, then: g.grade?.elevGainM, pace: false, lowerIsBetter: true)
        }
        .padding(13)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.drip.divider, lineWidth: 1))
    }

    @ViewBuilder
    private func deltaRow(_ label: String, now: Int?, then: Int?, pace: Bool, lowerIsBetter: Bool) -> some View {
        if let now, let then {
            let d = now - then
            let improved = lowerIsBetter ? d < 0 : d > 0
            HStack {
                Text(label)
                    .font(.dripEyebrow(8)).tracking(0.6)
                    .foregroundStyle(Color.drip.textSecondary)
                Spacer()
                Text(pace ? TrendsFormat.pace(then) : "\(then)")
                    .font(.dripStat(11))
                    .foregroundStyle(Color.drip.textTertiary)
                Text("→")
                    .font(.dripBody(11))
                    .foregroundStyle(Color.drip.textTertiary)
                Text(pace ? TrendsFormat.pace(now) : "\(now)")
                    .font(.dripStat(11))
                    .foregroundStyle(Color.drip.textPrimary)
                Text(deltaLabel(d, pace: pace))
                    .font(.dripStat(11))
                    .foregroundStyle(d == 0 ? Color.drip.textTertiary
                        : improved ? Color.drip.textSecondary : Color.drip.coralDeep)
                    .frame(minWidth: 46, alignment: .trailing)
            }
            .padding(.vertical, 5)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.drip.divider).frame(height: 0.5)
            }
        }
    }

    private func deltaLabel(_ d: Int, pace: Bool) -> String {
        if d == 0 { return "±0" }
        let sign = d > 0 ? "+" : "−"
        let v = abs(d)
        if pace, v >= 60 { return "\(sign)\(v / 60):\(String(format: "%02d", v % 60))" }
        return "\(sign)\(v)"
    }

    private func conditionsTiles(_ s: SessionStory) -> some View {
        HStack(spacing: 8) {
            tile("FEELS LIKE",
                 value: s.heat.map { "\($0.tempF)°" } ?? nil,
                 sub: s.heat.map { "dew \($0.dewF)°" },
                 emptyNudge: "No weather on this one yet.")
            tile("HEAT COST",
                 value: s.heat.map { "\($0.costSecPerMi)s/mi" },
                 sub: "removed in flat + cool",
                 emptyNudge: "Needs weather.")
            tile("HILLS",
                 value: s.grade.flatMap { g in g.costSecPerMi.map { "\($0)s/mi" } } ?? s.grade.map { "\($0.elevGainM) m" },
                 sub: s.grade.flatMap { g in g.costSecPerMi != nil ? "\(g.elevGainM) m climb" : "climb" },
                 emptyNudge: "No elevation data.")
        }
    }

    private func tile(_ label: String, value: String?, sub: String?, emptyNudge: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.dripEyebrow(8)).tracking(0.7)
                .foregroundStyle(Color.drip.textSecondary)
            if let value {
                Text(value)
                    .font(.dripStat(16))
                    .foregroundStyle(Color.drip.textPrimary)
                if let sub {
                    Text(sub)
                        .font(.dripBody(10))
                        .foregroundStyle(Color.drip.textTertiary)
                }
            } else {
                Text(emptyNudge)
                    .font(.dripBody(10))
                    .foregroundStyle(Color.drip.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.drip.divider, lineWidth: 1))
    }

    @ViewBuilder
    private func memoBlock(_ s: SessionStory) -> some View {
        if let memo = s.memo {
            VStack(alignment: .leading, spacing: 8) {
                Text("“\(memo.text)”")
                    .font(.dripBody(14))
                    .italic()
                    .foregroundStyle(Color.drip.textPrimary)
                    .lineSpacing(3)
                Text("VOICE MEMO · \(SessionStoryRead.dateLabel(s.date).uppercased())\(memo.mood.map { " · \($0.uppercased())" } ?? "")")
                    .font(.dripEyebrow(8)).tracking(0.7)
                    .foregroundStyle(Color.drip.textTertiary)
                ForEach(s.niggles) { n in
                    if let quote = n.quote {
                        Text("“\(quote)”")
                            .font(.dripBody(12))
                            .italic()
                            .foregroundStyle(Color.drip.injured)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(13)
            .background(Color.drip.cardBackgroundElevated)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(alignment: .leading) {
                UnevenRoundedRectangle(topLeadingRadius: 10, bottomLeadingRadius: 10)
                    .fill(Color.drip.moodBorderColor(for: memo.mood) ?? Color.drip.textTertiary)
                    .frame(width: 2)
            }
        } else {
            EmptyStateView(
                variant: .dataPending,
                eyebrow: "Nothing logged",
                title: "No voice memo for this one. Thirty seconds after the next hard day is all the story needs."
            )
        }
    }

    private func readBlock(_ s: SessionStory, compare: SessionStory?) -> some View {
        let read = SessionStoryRead.build(session: s, compare: compare)
        return VStack(alignment: .leading, spacing: 8) {
            Text("THE READ")
                .font(.dripEyebrow(10)).tracking(1.2)
                .foregroundStyle(Color.drip.coral)
            Text(read.body)
                .font(.dripBody(14))
                .foregroundStyle(Color.drip.textPrimary)
                .lineSpacing(3)
            Text(read.question)
                .font(.dripBody(13))
                .italic()
                .foregroundStyle(Color.drip.textSecondary)
                .lineSpacing(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(Color.drip.cardBackgroundElevated)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: 10, bottomLeadingRadius: 10)
                .fill(Color.drip.coral)
                .frame(width: 2)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.dripEyebrow(10)).tracking(1.2)
            .foregroundStyle(Color.drip.textSecondary)
    }

    /// Bar colour from the session's zone, on the canonical blue pace ramp.
    private var zoneColor: Color {
        switch keySession.zone {
        case "mile": return PaceSpectrum.mile
        case "3k": return PaceSpectrum.threeK
        case "5k": return PaceSpectrum.fiveK
        case "10k": return PaceSpectrum.tenK
        case "hmp": return PaceSpectrum.hmp
        case "mp": return PaceSpectrum.mp
        case "steady": return PaceSpectrum.steady
        case "moderate": return PaceSpectrum.moderate
        default: return PaceSpectrum.easy
        }
    }
}

// MARK: - Pace chart (bars + ghost dashed line)

/// Segment pace bars with the previous comparable session as a dashed ghost
/// polyline behind them. One axis (pace, inverted so faster = taller); the
/// ghost spans the same width on its own step so differing segment counts
/// never overflow. Canvas, matching the Trends charts.
struct SessionStoryPaceChart: View {
    let segments: [StorySegment]
    let ghost: [StorySegment]
    let zoneColor: Color

    var body: some View {
        Canvas { ctx, size in
            let padL: CGFloat = 34, padR: CGFloat = 4, padT: CGFloat = 12, padB: CGFloat = 18
            let iw = size.width - padL - padR
            let ih = size.height - padT - padB
            guard iw > 0, ih > 0, !segments.isEmpty else { return }

            let all = (segments.map(\.paceSec) + ghost.map(\.paceSec)).map(Double.init)
            guard var lo = all.min(), var hi = all.max() else { return }
            let pad = Swift.max(8, (hi - lo) * 0.25)
            lo -= pad; hi += pad
            // Faster (smaller sec) = higher on the chart.
            func y(_ pace: Double) -> CGFloat { padT + CGFloat((pace - lo) / (hi - lo)) * ih }

            // Gridline + axis labels at the quartiles.
            for v in [lo + (hi - lo) * 0.25, lo + (hi - lo) * 0.75] {
                var line = Path()
                line.move(to: CGPoint(x: padL, y: y(v)))
                line.addLine(to: CGPoint(x: size.width - padR, y: y(v)))
                ctx.stroke(line, with: .color(Color.drip.divider), lineWidth: 1)
                ctx.draw(
                    Text(TrendsFormat.pace(Int(v)))
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(Color.drip.textTertiary),
                    at: CGPoint(x: padL - 4, y: y(v)),
                    anchor: .trailing
                )
            }

            // Ghost polyline on its own step across the same width.
            if ghost.count > 1 {
                let gstep = iw / CGFloat(ghost.count)
                var path = Path()
                for (i, seg) in ghost.enumerated() {
                    let pt = CGPoint(x: padL + gstep * (CGFloat(i) + 0.5), y: y(Double(seg.paceSec)))
                    if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                }
                ctx.stroke(path, with: .color(Color.drip.textTertiary),
                           style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
            }

            // Bars, bottom-anchored, rounded data end.
            let step = iw / CGFloat(segments.count)
            let bw = Swift.min(30, step * 0.62)
            let base = padT + ih
            for (i, seg) in segments.enumerated() {
                let x = padL + step * CGFloat(i) + (step - bw) / 2
                let top = y(Double(seg.paceSec))
                let rect = CGRect(x: x, y: top, width: bw, height: Swift.max(4, base - top))
                ctx.fill(
                    Path(roundedRect: rect, cornerRadii: RectangleCornerRadii(topLeading: 4, topTrailing: 4)),
                    with: .color(zoneColor)
                )
                ctx.draw(
                    Text(seg.label)
                        .font(.system(size: 7.5, design: .monospaced))
                        .foregroundColor(Color.drip.textTertiary),
                    at: CGPoint(x: x + bw / 2, y: base + 9),
                    anchor: .center
                )
                // Direct labels: first, last, and the fastest bar only.
                let fastest = segments.map(\.paceSec).min()
                if i == 0 || i == segments.count - 1 || seg.paceSec == fastest {
                    ctx.draw(
                        Text(TrendsFormat.pace(seg.paceSec))
                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                            .foregroundColor(Color.drip.textPrimary),
                        at: CGPoint(x: x + bw / 2, y: top - 7),
                        anchor: .center
                    )
                }
            }
        }
    }
}

// MARK: - HR chart (same segments, own track, own scale)

struct SessionStoryHRChart: View {
    let segments: [StorySegment]

    var body: some View {
        Canvas { ctx, size in
            let padL: CGFloat = 34, padR: CGFloat = 4, padT: CGFloat = 10, padB: CGFloat = 6
            let iw = size.width - padL - padR
            let ih = size.height - padT - padB
            let hrs = segments.compactMap { $0.hr.map(Double.init) }
            guard iw > 0, ih > 0, hrs.count > 1, var lo = hrs.min(), var hi = hrs.max() else { return }
            let pad = Swift.max(4, (hi - lo) * 0.3)
            lo -= pad; hi += pad
            func y(_ v: Double) -> CGFloat { padT + CGFloat(1 - (v - lo) / (hi - lo)) * ih }

            let mid = lo + (hi - lo) * 0.5
            var grid = Path()
            grid.move(to: CGPoint(x: padL, y: y(mid)))
            grid.addLine(to: CGPoint(x: size.width - padR, y: y(mid)))
            ctx.stroke(grid, with: .color(Color.drip.divider), lineWidth: 1)
            ctx.draw(
                Text("\(Int(mid))")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(Color.drip.textTertiary),
                at: CGPoint(x: padL - 4, y: y(mid)),
                anchor: .trailing
            )

            let step = iw / CGFloat(segments.count)
            var path = Path()
            var points: [(Int, CGPoint)] = []
            for (i, seg) in segments.enumerated() {
                guard let hr = seg.hr else { continue }
                let pt = CGPoint(x: padL + step * (CGFloat(i) + 0.5), y: y(Double(hr)))
                if path.isEmpty { path.move(to: pt) } else { path.addLine(to: pt) }
                points.append((hr, pt))
            }
            ctx.stroke(path, with: .color(Color.drip.textSecondary),
                       style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            for (hr, pt) in points {
                let dot = CGRect(x: pt.x - 3, y: pt.y - 3, width: 6, height: 6)
                ctx.fill(Path(ellipseIn: dot), with: .color(Color.drip.textSecondary))
                _ = hr
            }
            if let first = points.first, let last = points.last {
                for (hr, pt) in [first, last] {
                    ctx.draw(
                        Text("\(hr)")
                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                            .foregroundColor(Color.drip.textPrimary),
                        at: CGPoint(x: pt.x, y: pt.y - 9),
                        anchor: .center
                    )
                }
            }
        }
    }
}

// MARK: - Drift gauge (0–12%, durable band 0–5 in neutral gray — never green)

struct DriftGauge: View {
    let valuePct: Double

    var body: some View {
        Canvas { ctx, size in
            let maxPct = 12.0
            let trackY = size.height / 2 - 3
            let track = CGRect(x: 0, y: trackY, width: size.width, height: 6)
            ctx.fill(Path(roundedRect: track, cornerRadius: 3), with: .color(Color.drip.paperDeep))
            let bandW = size.width * CGFloat(5.0 / maxPct)
            let band = CGRect(x: 0, y: trackY, width: bandW, height: 6)
            ctx.fill(Path(roundedRect: band, cornerRadius: 3),
                     with: .color(Color.drip.textTertiary.opacity(0.35)))
            var tick = Path()
            tick.move(to: CGPoint(x: bandW, y: trackY - 3))
            tick.addLine(to: CGPoint(x: bandW, y: trackY + 9))
            ctx.stroke(tick, with: .color(Color.drip.textTertiary), lineWidth: 1)
            let x = size.width * CGFloat(Swift.min(Swift.max(valuePct, 0), maxPct) / maxPct)
            let marker = CGRect(x: x - 5, y: trackY - 2, width: 10, height: 10)
            ctx.fill(Path(ellipseIn: marker), with: .color(Color.drip.textPrimary))
            ctx.stroke(Path(ellipseIn: marker), with: .color(Color.drip.background), lineWidth: 2)
        }
    }
}

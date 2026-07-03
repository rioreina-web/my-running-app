//
//  TrendsDetailViews.swift
//  RunningLog
//
//  The four Trends drill-down screens, pushed from the overview tracks in
//  TrendsTabView. Each is a full detail screen with a chart built for that
//  dimension (design: trends-drilldowns-prototype.html):
//
//    • VolumeDetailView      bars + 4-wk average + acute:chronic band
//    • KeySessionsDetailView pace progression + reuses WorkoutsAndRepsSection
//                            (session list → WorkoutRepChart rep splits)
//    • MoodDetailView        per-week mood ribbon + distribution
//    • NigglesDetailView     recurrence swimlanes + verbatim quotes
//
//  All four are driven by the already-loaded `[TrendsWeek]` (no new fetches),
//  except KeySessions, which reuses the self-contained WorkoutsAndRepsSection
//  for the real rep-level data. Charts hand-drawn with Canvas to match
//  UnifiedTrainingChart. Post Run Drip.
//
//  Follow-ups noted inline: intensity-weighted ACWR from athlete_state, a
//  daily mood ribbon, and severity-encoded niggle markers all want richer
//  data than the weekly timeline carries today.
//

import SwiftUI

// MARK: - Shared bits

/// Editorial detail header (eyebrow + display title).
private struct DetailHead: View {
    let eyebrow: String
    let title: String
    var tag: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(eyebrow.uppercased())
                    .font(.dripEyebrow(11)).tracking(1.3)
                    .foregroundStyle(Color.drip.coral)
                if let tag {
                    Text(tag.uppercased())
                        .font(.dripEyebrow(9)).tracking(0.8)
                        .foregroundStyle(Color.drip.tired)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Color.drip.tired.opacity(0.14))
                        .clipShape(Capsule())
                }
            }
            Text(title)
                .font(.dripDisplay(26))
                .foregroundStyle(Color.drip.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TrackEyebrow: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.dripEyebrow(10)).tracking(1.0)
            .foregroundStyle(Color.drip.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct InsightBlock: View {
    let text: String
    var quote: String? = nil
    var quoteAttribution: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text)
                .font(.dripBody(15)).lineSpacing(3)
                .foregroundStyle(Color.drip.textPrimary)
            if let quote {
                Text("\u{201C}\(quote)\u{201D}\(quoteAttribution.map { "  — \($0)" } ?? "")")
                    .font(.dripBody(14).italic())
                    .foregroundStyle(Color.drip.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 13)
        .overlay(alignment: .leading) {
            Rectangle().fill(Color.drip.coral.opacity(0.5)).frame(width: 2)
        }
    }
}

/// Draw a small mono label into a Canvas context.
private func canvasLabel(
    _ ctx: GraphicsContext, _ s: String, at p: CGPoint,
    anchor: UnitPoint = .center, size: CGFloat = 8.5,
    color: Color = Color.drip.textTertiary
) {
    ctx.draw(
        Text(s).font(.system(size: size, weight: .medium, design: .monospaced)).foregroundColor(color),
        at: p, anchor: anchor
    )
}

private func paceString(_ sec: Int) -> String { "\(sec / 60):\(String(format: "%02d", sec % 60))" }

private var detailBackground: some View { Color.drip.background.ignoresSafeArea() }

// MARK: - Volume

struct VolumeDetailView: View {
    let weeks: [TrendsWeek]
    var flagged: [TrendsFlaggedRun] = []
    var trimmed: [TrendsFlaggedRun] = []
    var onSetExcluded: (String, Bool) -> Void = { _, _ in }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                DetailHead(eyebrow: "Training volume · \(weeks.count) weeks", title: "The build.")

                if !flagged.isEmpty || !trimmed.isEmpty {
                    flagBanner.padding(.top, 14)
                }

                HStack(spacing: 8) {
                    DripStatTile(label: "This wk", value: thisWeekMiles, unit: "mpw")
                    DripStatTile(label: "4-wk avg", value: fourWeekAvg, unit: "mpw")
                    DripStatTile(label: "Peak", value: peakMiles, unit: "mpw")
                }
                .padding(.top, 14)

                TrackEyebrow(text: "Weekly volume + 4-wk average").padding(.top, 18).padding(.bottom, 6)
                VolumeChart(weeks: weeks).frame(height: 168)

                HStack(spacing: 14) {
                    legendSwatch(Color.drip.paperDeep, "Easy miles")
                    legendSwatch(Color.drip.textSecondary, "Quality miles")
                    legendSwatch(Color.drip.textPrimary, "4-wk avg")
                }
                .padding(.top, 8)

                TrackEyebrow(text: "Load balance · acute : chronic").padding(.top, 18).padding(.bottom, 6)
                ACWRBar(value: acwr).frame(height: 48)

                InsightBlock(text: acwrNarrative).padding(.top, 16)
            }
            .padding(20)
        }
        .background(detailBackground)
        .navigationTitle("Trends")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var flagBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("DATA CHECK · LOOKS OFF")
                .font(.dripEyebrow(10)).tracking(1.0)
                .foregroundStyle(Color.drip.tired)

            if !flagged.isEmpty {
                Text("\(flagged.count) \(flagged.count == 1 ? "run" : "runs") didn't add up — kept out of your totals. Trim to drop it, Keep to count it.")
                    .font(.dripBody(13)).foregroundStyle(Color.drip.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(flagged) { f in flagRow(f, isTrimmed: false) }
            }

            if !trimmed.isEmpty {
                Text("TRIMMED")
                    .font(.dripEyebrow(9)).tracking(0.8)
                    .foregroundStyle(Color.drip.textTertiary)
                    .padding(.top, 2)
                ForEach(trimmed) { f in flagRow(f, isTrimmed: true) }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.drip.tired.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func flagRow(_ f: TrendsFlaggedRun, isTrimmed: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(f.date) · \(Int(f.miles)) mi\(f.pace.map { " · \($0)/mi" } ?? "")")
                    .font(.dripBody(13)).foregroundStyle(Color.drip.textPrimary)
                Text(f.reason)
                    .font(.dripBody(11)).foregroundStyle(Color.drip.textTertiary)
            }
            Spacer(minLength: 8)
            if isTrimmed {
                actionChip("Restore") { onSetExcluded(f.id, false) }
            } else {
                actionChip("Keep") { onSetExcluded(f.id, false) }
                actionChip("Trim") { onSetExcluded(f.id, true) }
            }
        }
        .padding(.vertical, 7)
        .overlay(Rectangle().fill(Color.drip.divider).frame(height: 1), alignment: .bottom)
    }

    private func actionChip(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.dripEyebrow(10)).tracking(0.6)
                .foregroundStyle(Color.drip.coral)
                .padding(.horizontal, 11).padding(.vertical, 6)
                .overlay(Capsule().stroke(Color.drip.coral.opacity(0.5), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func legendSwatch(_ c: Color, _ label: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(c).frame(width: 10, height: 10)
            Text(label).font(.dripEyebrow(9)).foregroundStyle(Color.drip.textSecondary)
        }
    }

    // Derived stats (miles-based; intensity-weighted ACWR from athlete_state
    // is the follow-up — see trends-tab-data-wiring.md §10).
    private var nonEmpty: [TrendsWeek] { weeks.filter { $0.miles > 0 } }
    private var thisWeekMiles: String { String(Int(nonEmpty.last?.miles ?? 0)) }
    private var fourWeekAvg: String {
        let last4 = nonEmpty.suffix(4)
        guard !last4.isEmpty else { return "0" }
        return String(Int(last4.map(\.miles).reduce(0, +) / Double(last4.count)))
    }
    private var peakMiles: String { String(Int(weeks.map(\.miles).max() ?? 0)) }

    private var acwr: Double {
        let ne = nonEmpty
        guard ne.count >= 2 else { return 1.0 }
        let acute = ne[ne.count - 1].miles
        let chronicSlice = ne.suffix(5).dropLast() // up to 4 prior weeks
        let chronic = chronicSlice.map(\.miles).reduce(0, +) / Double(max(chronicSlice.count, 1))
        return chronic > 0 ? acute / chronic : 1.0
    }

    private var acwrNarrative: String {
        let r = acwr
        if r > 1.5 { return String(format: "Acute:chronic is %.2f — a spike. Worth an easier few days before the next quality block.", r) }
        if r > 1.3 { return String(format: "Acute:chronic is %.2f, just past the sweet spot. Climbing, but keep an eye on it.", r) }
        if r < 0.8 { return String(format: "Acute:chronic is %.2f — below the sweet spot, a lighter stretch.", r) }
        return String(format: "Acute:chronic is %.2f — inside the 0.8–1.3 band. A steady, controlled ramp.", r)
    }
}

private struct VolumeChart: View {
    let weeks: [TrendsWeek]
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            guard !weeks.isEmpty else { return }
            let n = weeks.count
            let padL: CGFloat = 4, padR: CGFloat = 4
            let base = h - 18, top: CGFloat = 14
            let maxMiles = max(weeks.map(\.miles).max() ?? 1, 1)
            let slot = (w - padL - padR) / CGFloat(n)
            let bw = min(slot * 0.6, 16)
            func x(_ i: Int) -> CGFloat { padL + slot * (CGFloat(i) + 0.5) }
            func yFor(_ m: Double) -> CGFloat { base - CGFloat(m / maxMiles) * (base - top) }

            // baseline
            var bl = Path(); bl.move(to: CGPoint(x: padL, y: base)); bl.addLine(to: CGPoint(x: w - padR, y: base))
            ctx.stroke(bl, with: .color(Color.drip.divider), lineWidth: 1)
            canvasLabel(ctx, "\(Int(maxMiles)) mpw", at: CGPoint(x: w - padR, y: top - 4), anchor: .trailing)

            // bars
            for (i, wk) in weeks.enumerated() {
                let cx = x(i)
                let totH = CGFloat(wk.miles / maxMiles) * (base - top)
                let qH = CGFloat(wk.qualityMiles / maxMiles) * (base - top)
                ctx.fill(Path(CGRect(x: cx - bw / 2, y: base - totH, width: bw, height: max(totH - qH, 0))), with: .color(Color.drip.paperDeep))
                ctx.fill(Path(CGRect(x: cx - bw / 2, y: base - totH, width: bw, height: max(qH, 0))), with: .color(Color.drip.textSecondary))
            }

            // 4-wk rolling average
            var line = Path(); var started = false
            for i in 0..<n {
                let s = max(0, i - 3)
                let seg = weeks[s...i].map(\.miles)
                let avg = seg.reduce(0, +) / Double(seg.count)
                let pt = CGPoint(x: x(i), y: yFor(avg))
                if started { line.addLine(to: pt) } else { line.move(to: pt); started = true }
            }
            ctx.stroke(line, with: .color(Color.drip.textPrimary.opacity(0.6)), lineWidth: 1.6)

            // first/last month ticks
            if let f = weeks.first { canvasLabel(ctx, f.month.uppercased(), at: CGPoint(x: x(0), y: h - 4), anchor: .leading) }
            if let l = weeks.last { canvasLabel(ctx, l.month.uppercased(), at: CGPoint(x: x(n - 1), y: h - 4), anchor: .trailing) }
        }
    }
}

/// Acute:chronic marker on a 0.6–1.6 scale with the 0.8–1.3 sweet-spot band.
private struct ACWRBar: View {
    let value: Double
    private let lo = 0.6, hi = 1.6, sweetLo = 0.8, sweetHi = 1.3
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let trackY = h * 0.4, trackH: CGFloat = 10
            func fx(_ v: Double) -> CGFloat { CGFloat((min(max(v, lo), hi) - lo) / (hi - lo)) * w }
            ctx.fill(Path(roundedRect: CGRect(x: 0, y: trackY, width: w, height: trackH), cornerRadius: 3), with: .color(Color.drip.paperDeep))
            ctx.fill(Path(CGRect(x: fx(sweetLo), y: trackY, width: fx(sweetHi) - fx(sweetLo), height: trackH)), with: .color(Color.drip.energized.opacity(0.18)))
            let mx = fx(value)
            var m = Path(); m.move(to: CGPoint(x: mx, y: trackY - 6)); m.addLine(to: CGPoint(x: mx, y: trackY + trackH + 6))
            ctx.stroke(m, with: .color(Color.drip.coral), lineWidth: 2)
            canvasLabel(ctx, String(format: "%.2f", value), at: CGPoint(x: mx, y: trackY - 10), anchor: .center, size: 9, color: Color.drip.coral)
            canvasLabel(ctx, "0.8", at: CGPoint(x: fx(sweetLo), y: h - 3), anchor: .center)
            canvasLabel(ctx, "1.3 SWEET SPOT", at: CGPoint(x: fx(sweetHi), y: h - 3), anchor: .leading)
        }
    }
}

// MARK: - Key sessions

struct KeySessionsDetailView: View {
    let weeks: [TrendsWeek]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                DetailHead(eyebrow: "Key sessions · pace progression", title: "The engine is growing.")

                TrackEyebrow(text: "Quality pace at the same effort").padding(.top, 16).padding(.bottom, 6)
                PaceProgressionChart(weeks: weeks).frame(height: 150)

                if let delta = paceDeltaNarrative {
                    InsightBlock(text: delta).padding(.top, 14)
                }

                // Real rep-level data: the existing self-contained section
                // (session list → WorkoutRepChart split-by-split).
                WorkoutsAndRepsSection().padding(.top, 18)
            }
            .padding(20)
        }
        .background(detailBackground)
        .navigationTitle("Trends")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var paced: [TrendsWeek] { weeks.filter { $0.keyPaceSec != nil } }
    private var paceDeltaNarrative: String? {
        guard let first = paced.first?.keyPaceSec, let last = paced.last?.keyPaceSec, last < first else { return nil }
        return "Your key-session pace has dropped from \(paceString(first)) to \(paceString(last)) /mi at the same effort across the block. The work is landing."
    }
}

private struct PaceProgressionChart: View {
    let weeks: [TrendsWeek]
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let paced = weeks.enumerated().filter { $0.element.keyPaceSec != nil }
            guard paced.count >= 1 else {
                canvasLabel(ctx, "No quality sessions in range", at: CGPoint(x: w / 2, y: h / 2), anchor: .center, size: 11, color: Color.drip.textTertiary)
                return
            }
            let padL: CGFloat = 6, padR: CGFloat = 6
            let top: CGFloat = 22, bot = h - 22
            let n = weeks.count
            let slot = (w - padL - padR) / CGFloat(n)
            func x(_ i: Int) -> CGFloat { padL + slot * (CGFloat(i) + 0.5) }
            let paces = paced.map { $0.element.keyPaceSec! }
            let pMin = CGFloat(paces.min()!), pMax = CGFloat(paces.max()!)
            let span = max(pMax - pMin, 1)
            func y(_ p: Int) -> CGFloat { top + (CGFloat(p) - pMin) / span * (bot - top) } // faster→top

            var bl = Path(); bl.move(to: CGPoint(x: padL, y: bot)); bl.addLine(to: CGPoint(x: w - padR, y: bot))
            ctx.stroke(bl, with: .color(Color.drip.divider), lineWidth: 1)

            var line = Path(); var started = false
            for (i, wk) in paced { let pt = CGPoint(x: x(i), y: y(wk.keyPaceSec!)); if started { line.addLine(to: pt) } else { line.move(to: pt); started = true } }
            ctx.stroke(line, with: .color(Color.drip.coral.opacity(0.4)), lineWidth: 1.4)

            let labelEvery = paced.count <= 8
            for (idx, item) in paced.enumerated() {
                let (i, wk) = item
                let p = wk.keyPaceSec!
                let r: CGFloat = 4
                ctx.fill(Path(ellipseIn: CGRect(x: x(i) - r, y: y(p) - r, width: r * 2, height: r * 2)), with: .color(Color.drip.coral))
                if labelEvery || idx == 0 || idx == paced.count - 1 {
                    canvasLabel(ctx, paceString(p), at: CGPoint(x: x(i), y: y(p) - 10), anchor: .center, color: Color.drip.textSecondary)
                }
            }
            if let f = paced.first { canvasLabel(ctx, weeks[f.offset].dateLabel.uppercased(), at: CGPoint(x: x(f.offset), y: h - 4), anchor: .leading) }
            if let l = paced.last, paced.count > 1 { canvasLabel(ctx, weeks[l.offset].dateLabel.uppercased(), at: CGPoint(x: x(l.offset), y: h - 4), anchor: .trailing) }
        }
    }
}

// MARK: - Mood

struct MoodDetailView: View {
    let weeks: [TrendsWeek]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                DetailHead(eyebrow: "Mood · from your voice logs", title: "How the block has felt.")

                TrackEyebrow(text: "Week by week").padding(.top, 16).padding(.bottom, 8)
                ribbon

                TrackEyebrow(text: "Distribution").padding(.top, 20).padding(.bottom, 8)
                distribution

                InsightBlock(
                    text: "Energy reads strongest mid-week and dips after the long run. A daily ribbon lands in a later build — this is the weekly read.",
                    quote: latestQuote?.0, quoteAttribution: latestQuote?.1
                ).padding(.top, 18)
            }
            .padding(20)
        }
        .background(detailBackground)
        .navigationTitle("Trends")
        .navigationBarTitleDisplayMode(.inline)
    }

    // One swatch per week, wrapped. Empty weeks render as a paper-deep cell.
    private var ribbon: some View {
        let cols = Array(repeating: GridItem(.flexible(), spacing: 6), count: 8)
        return LazyVGrid(columns: cols, spacing: 6) {
            ForEach(Array(weeks.enumerated()), id: \.offset) { _, wk in
                RoundedRectangle(cornerRadius: 4)
                    .fill(wk.mood.isEmpty ? Color.drip.paperDeep : TrendsMoodColor.color(wk.mood))
                    .aspectRatio(1, contentMode: .fit)
            }
        }
    }

    private var distribution: some View {
        let counts = moodCounts
        let maxC = max(counts.map(\.1).max() ?? 1, 1)
        return VStack(spacing: 7) {
            ForEach(counts, id: \.0) { mood, n in
                HStack(spacing: 8) {
                    Text(mood.uppercased()).font(.dripEyebrow(9)).tracking(0.6)
                        .foregroundStyle(Color.drip.textSecondary)
                        .frame(width: 78, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3).fill(Color.drip.paperDeep)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(TrendsMoodColor.color(mood))
                                .frame(width: geo.size.width * CGFloat(n) / CGFloat(maxC))
                        }
                    }
                    .frame(height: 10)
                    Text("\(n)").font(.dripStat(11)).foregroundStyle(Color.drip.textPrimary).frame(width: 18, alignment: .trailing)
                }
            }
        }
    }

    private var moodCounts: [(String, Int)] {
        let order = ["energized", "positive", "neutral", "tired", "struggling", "injured"]
        var dict: [String: Int] = [:]
        for wk in weeks where !wk.mood.isEmpty { dict[wk.mood, default: 0] += 1 }
        return order.compactMap { m in dict[m].map { (m, $0) } }
    }

    private var latestQuote: (String, String)? {
        guard let wk = weeks.last(where: { $0.voiceQuote != nil }), let q = wk.voiceQuote else { return nil }
        return (q, wk.dateLabel)
    }
}

// MARK: - Niggles

struct NigglesDetailView: View {
    let weeks: [TrendsWeek]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                DetailHead(eyebrow: "Niggles · recurrence", title: niggleTitle, tag: "surface, don't diagnose")

                if labels.isEmpty {
                    Text("Nothing stacking right now. Body-part mentions show up here when you voice them.")
                        .font(.dripBody(15)).foregroundStyle(Color.drip.textSecondary)
                        .padding(.top, 18)
                } else {
                    TrackEyebrow(text: "By body part · \(weeks.count) weeks").padding(.top, 16).padding(.bottom, 6)
                    NiggleSwimlanes(weeks: weeks, labels: labels).frame(height: CGFloat(labels.count) * 40 + 24)

                    TrackEyebrow(text: "In your words").padding(.top, 18).padding(.bottom, 8)
                    ForEach(Array(quoteWeeks.enumerated()), id: \.offset) { _, wk in
                        quoteCard(wk)
                    }
                }

                Text("Surfaced from what you said, never interpreted. If anything gets sharper, see a clinician.")
                    .font(.dripBody(13).italic())
                    .foregroundStyle(Color.drip.textTertiary)
                    .padding(.top, 12)
            }
            .padding(20)
        }
        .background(detailBackground)
        .navigationTitle("Trends")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var labels: [String] {
        var seen: [String] = []
        for wk in weeks { for n in wk.niggles where !seen.contains(n) { seen.append(n) } }
        return seen
    }
    private var niggleTitle: String {
        switch labels.count {
        case 0: "All clear."
        case 1: "One thing, watched."
        default: "\(labels.count) things, watched."
        }
    }
    private var quoteWeeks: [TrendsWeek] { Array(weeks.filter { $0.voiceQuote != nil && !$0.niggles.isEmpty }.reversed()) }

    private func quoteCard(_ wk: TrendsWeek) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(wk.niggles.joined(separator: ", "))
                    .font(.dripBody(15).weight(.bold))
                    .foregroundStyle(Color.drip.textPrimary)
                Spacer()
                Text(wk.dateLabel.uppercased()).font(.dripEyebrow(9)).tracking(0.8)
                    .foregroundStyle(Color.drip.textSecondary)
            }
            if let q = wk.voiceQuote {
                Text("\u{201C}\(q)\u{201D}").font(.dripBody(14).italic())
                    .foregroundStyle(Color.drip.textPrimary)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
        .padding(.bottom, 9)
    }
}

private struct NiggleSwimlanes: View {
    let weeks: [TrendsWeek]
    let labels: [String]
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let n = weeks.count
            let x0: CGFloat = 76, xe = w - 6
            let slot = (xe - x0) / CGFloat(max(n, 1))
            func x(_ i: Int) -> CGFloat { x0 + slot * (CGFloat(i) + 0.5) }

            for (li, label) in labels.enumerated() {
                let y = 18 + CGFloat(li) * 40
                canvasLabel(ctx, label, at: CGPoint(x: 4, y: y), anchor: .leading, size: 9, color: Color.drip.textSecondary)
                var lane = Path(); lane.move(to: CGPoint(x: x0, y: y)); lane.addLine(to: CGPoint(x: xe, y: y))
                ctx.stroke(lane, with: .color(Color.drip.divider.opacity(0.7)), lineWidth: 1)
                for (i, wk) in weeks.enumerated() where wk.niggles.contains(label) {
                    // Severity isn't carried by the weekly timeline yet, so
                    // markers are uniform; severity-encoding is a follow-up.
                    let r: CGFloat = 4.4
                    ctx.fill(Path(ellipseIn: CGRect(x: x(i) - r, y: y - r, width: r * 2, height: r * 2)), with: .color(Color.drip.injured))
                }
            }
            // month ticks
            var last = ""
            for (i, wk) in weeks.enumerated() where wk.month != last {
                canvasLabel(ctx, wk.month.uppercased(), at: CGPoint(x: x(i), y: h - 4), anchor: .center)
                last = wk.month
            }
        }
    }
}

//
//  FastSegmentsView.swift
//  RunningLog
//
//  "The sharp end" — a Trends surface that reads the fast segments of key
//  sessions one SYSTEM at a time. Pick a system (mile … MP) and see whether its
//  fast work is getting sharper: a clean conditions-adjusted pace trend (heat
//  AND grade removed) plus the latest session in detail.
//
//  NB: the per-system EXPECTED VOLUME ranges (e.g. MP 7–15 mi) are backend
//  reasoning only — never shown here.
//
//  Post Run Drip: warm paper, ink, one coral (alerts only), pace on the blue
//  ramp (PaceSpectrum). Data comes from `TrendsService.fastSegments`.
//

import SwiftUI

struct FastSegmentsView: View {
    private let trends: [FastSystemTrend]
    private let sessions: [FastSession]
    @State private var selected: FastSystem

    init(trends: [FastSystemTrend], sessions: [FastSession]) {
        self.trends = trends
        self.sessions = sessions
        let initial = sessions.last?.primarySystem ?? trends.first?.system ?? .fiveK
        _selected = State(initialValue: initial)
    }

    private var selectedTrend: FastSystemTrend? { trends.first { $0.system == selected } }

    private var latestSession: FastSession? {
        sessions.last { s in s.bySystem.contains { $0.system == selected } }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                header
                if trends.isEmpty {
                    emptyState
                } else {
                    systemChips
                    if let trend = selectedTrend {
                        paceTrendCard(trend)
                        sessionsListCard(trend)
                    }
                    if let s = latestSession { sessionCard(s) }
                    theRead
                }
                footer
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.drip.background.ignoresSafeArea())
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("THE SHARP END")
                .font(.dripEyebrow(11)).tracking(11 * 0.14)
                .foregroundColor(Color.drip.coral)
            Text("Where the\nspeed lives.")
                .font(.dripDisplay(34))
                .foregroundColor(Color.drip.textPrimary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            Text("Your fast work, one system at a time — is it getting sharper?")
                .font(.dripBody(14))
                .foregroundColor(Color.drip.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("NOTHING SHARP YET")
                .font(.dripEyebrow(10)).tracking(10 * 0.12)
                .foregroundColor(Color.drip.textTertiary)
            Text("No key sessions with rep-level laps in range. Once a structured workout syncs with its splits, its fast segments show up here — sorted by system.")
                .font(.dripBody(15)).foregroundColor(Color.drip.textSecondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.drip.cardBackground))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.drip.divider, lineWidth: 1))
    }

    // MARK: System chips

    private var systemChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 9) {
                ForEach(trends) { t in
                    let on = t.system == selected
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) { selected = t.system }
                    } label: {
                        Text(t.system.label)
                            .font(.dripEyebrow(12)).tracking(12 * 0.06)
                            .fixedSize()
                            .foregroundColor(on ? Color.drip.background : Color.drip.textSecondary)
                            .padding(.horizontal, 15).padding(.vertical, 9)
                            .background(Capsule().fill(on ? Color.drip.textPrimary : Color.drip.cardBackground))
                            .overlay(Capsule().stroke(Color.drip.divider, lineWidth: on ? 0 : 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: Pace trend (the hero)

    private func paceTrendCard(_ trend: FastSystemTrend) -> some View {
        let pts = trend.points
        let latest = pts.last
        let first = pts.first
        let delta: Int? = (pts.count >= 2 && first != nil && latest != nil)
            ? first!.effectivePaceSec - latest!.effectivePaceSec : nil
        return VStack(alignment: .leading, spacing: 16) {
            Text("\(selected.label.uppercased()) · PACE, CONDITIONS-ADJUSTED")
                .font(.dripEyebrow(11)).tracking(11 * 0.12)
                .foregroundColor(Color.drip.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(latest.map { TrendsFormat.pace($0.effectivePaceSec) } ?? "—")
                    .font(.dripStat(38)).foregroundColor(Color.drip.textPrimary)
                Text("/mi").font(.dripBody(14)).foregroundColor(Color.drip.textTertiary)
                Spacer()
                if let latest {
                    Text(latest.totalMiles.map { "\(fmt1(latest.workMiles)) mi \(selected.label) · \(fmt1($0)) mi run" }
                         ?? "\(fmt1(latest.workMiles)) mi \(selected.label)")
                        .font(.dripStat(12)).foregroundColor(Color.drip.textSecondary)
                }
            }

            if let d = delta {
                Text(d == 0
                     ? "Holding pace across \(pts.count) sessions"
                     : "\(d > 0 ? "▼" : "▲") \(abs(d))s/mi \(d > 0 ? "faster" : "slower") than your first")
                    .font(.dripEyebrow(10)).tracking(10 * 0.06)
                    .foregroundColor(Color.drip.textSecondary)
            }

            PaceTrendChart(points: pts, color: selected.spectrumColor)
                .frame(height: 150)

            Text("Heat and grade removed — a hot or hilly rep reads at its cool, flat worth. Higher = faster.")
                .font(.dripBody(12)).italic()
                .foregroundColor(Color.drip.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.drip.cardBackground))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.drip.divider, lineWidth: 1))
    }

    // MARK: Sessions list — which workout, what pace, how much of the run

    private func sessionLabel(_ p: FastSystemTrendPoint) -> String {
        if let n = p.sessionName, !n.isEmpty { return n }
        return "\(selected.label) session"
    }

    private func rowMeta(_ p: FastSystemTrendPoint) -> String {
        let work = "\(fmt1(p.workMiles)) \(selected.label) mi"
        if let total = p.totalMiles { return "\(work) · \(fmt1(total)) mi run" }
        return work
    }

    private func sessionsListCard(_ trend: FastSystemTrend) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("SESSIONS")
                .font(.dripEyebrow(11)).tracking(11 * 0.12)
                .foregroundColor(Color.drip.textSecondary)
                .padding(.bottom, 4)
            ForEach(Array(trend.points.enumerated().reversed()), id: \.element.id) { idx, p in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(p.dateLabel.uppercased())
                            .font(.dripEyebrow(9.5)).tracking(9.5 * 0.06)
                            .foregroundColor(Color.drip.textTertiary)
                        Text(sessionLabel(p))
                            .font(.dripBody(15)).foregroundColor(Color.drip.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("\(TrendsFormat.pace(p.avgPaceSec))/mi")
                            .font(.dripStat(15)).foregroundColor(Color.drip.textPrimary)
                        Text(rowMeta(p))
                            .font(.dripEyebrow(9)).tracking(9 * 0.04)
                            .foregroundColor(Color.drip.textTertiary)
                            .multilineTextAlignment(.trailing)
                    }
                }
                .padding(.vertical, 13)
                if idx != 0 { Rectangle().fill(Color.drip.divider).frame(height: 1) }
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.drip.cardBackground))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.drip.divider, lineWidth: 1))
    }

    // MARK: Latest session detail

    private func sessionCard(_ s: FastSession) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("LATEST SESSION")
                    .font(.dripEyebrow(10)).tracking(10 * 0.12)
                    .foregroundColor(Color.drip.textTertiary)
                Text("\(s.dateLabel) · \(s.name.isEmpty ? selected.label : s.name)")
                    .font(.dripDisplay(20))
                    .foregroundColor(Color.drip.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            let stats: [(String, String)] = [
                ("VOLUME", "\(fmt1(s.fastMiles)) mi"),
                ("PACE", TrendsFormat.pace(s.avgPaceSec)),
                ("COND-ADJ", TrendsFormat.pace(s.conditionsPaceSec ?? s.neutralPaceSec)),
                ("AVG HR", s.avgHr.map { "\($0)" } ?? "—"),
                ("DENSITY", "\(s.densityPct)%"),
                ("AVG REST", "\(s.avgRestSec)s"),
            ]
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 12) {
                ForEach(stats, id: \.0) { st in StatCell(label: st.0, value: st.1) }
            }

            if s.bySystem.count > 1 {
                Text("MIXED — \(s.bySystem.count) SYSTEMS")
                    .font(.dripEyebrow(9)).tracking(9 * 0.12)
                    .foregroundColor(Color.drip.textTertiary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(s.bySystem) { sv in
                            HStack(spacing: 5) {
                                Circle().fill(sv.system.spectrumColor).frame(width: 7, height: 7)
                                Text("\(sv.system.label) \(fmt1(sv.workMiles))mi")
                                    .font(.dripStat(11)).foregroundColor(Color.drip.textSecondary).fixedSize()
                            }
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Capsule().fill(Color.drip.background))
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.drip.cardBackgroundElevated))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.drip.divider, lineWidth: 1))
    }

    // MARK: The Read

    private var theRead: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("THE READ")
                .font(.dripEyebrow(11)).tracking(11 * 0.12)
                .foregroundColor(Color.drip.coral)
            Text(readBody)
                .font(.dripBody(14.5)).foregroundColor(Color.drip.textPrimary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.drip.cardBackgroundElevated))
        .overlay(alignment: .leading) { Rectangle().fill(Color.drip.coral).frame(width: 2) }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.drip.divider, lineWidth: 1))
    }

    private var readBody: String {
        guard let t = selectedTrend, let last = t.points.last else {
            return "Pick a system to see how its fast work is trending."
        }
        let vol = "\(fmt1(last.workMiles)) mi of \(selected.label) work"
        guard t.points.count >= 2, let first = t.points.first else {
            return "Latest \(selected.label): \(vol). One session in range so far — a second gives the trend."
        }
        let d = first.effectivePaceSec - last.effectivePaceSec
        let dir = d > 0 ? "\(d)s/mi faster" : (d < 0 ? "\(-d)s/mi slower" : "right where it was")
        return "Latest \(selected.label): \(vol). Conditions-adjusted, the pace is \(dir) than your first \(selected.label) session in range — heat and grade taken out."
    }

    private var footer: some View {
        Text("YOUR KEY SESSIONS · AI ADVISES, NEVER ACTS")
            .font(.dripEyebrow(9)).tracking(9 * 0.1)
            .foregroundColor(Color.drip.textTertiary)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    private func fmt1(_ x: Double) -> String { String(format: "%.1f", x) }
}

// MARK: - Pace trend line chart (faster = up)

private struct PaceTrendChart: View {
    let points: [FastSystemTrendPoint]
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let W = geo.size.width, H = geo.size.height
            let vals = points.map { Double($0.effectivePaceSec) }
            let lo = vals.min() ?? 0, hi = vals.max() ?? 1
            let span = max(hi - lo, 1)
            let yMin = lo - span * 0.35, yMax = hi + span * 0.35
            let topPad: CGFloat = 10, botPad: CGFloat = 22, sidePad: CGFloat = 4
            let plotW = max(W - sidePad * 2, 1), plotH = max(H - topPad - botPad, 1)

            // Local closures (not `func`s): a ViewBuilder closure can hold
            // `let` bindings but not function declarations.
            let xAt: (Int) -> CGFloat = { i in
                points.count <= 1 ? sidePad + plotW / 2
                                  : sidePad + CGFloat(i) / CGFloat(points.count - 1) * plotW
            }
            // faster (smaller pace) → nearer the top (smaller y)
            let yAt: (Double) -> CGFloat = { p in
                topPad + CGFloat((p - yMin) / (yMax - yMin)) * plotH
            }

            ZStack {
                // baseline grid
                ForEach(0..<3, id: \.self) { k in
                    let gv = yMin + (yMax - yMin) * (Double(k) / 2.0)
                    Rectangle().fill(Color.drip.divider.opacity(0.7))
                        .frame(width: plotW, height: 1)
                        .position(x: sidePad + plotW / 2, y: yAt(gv))
                }
                // line
                Path { path in
                    for (i, p) in points.enumerated() {
                        let pt = CGPoint(x: xAt(i), y: yAt(Double(p.effectivePaceSec)))
                        if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                    }
                }
                .stroke(Color.drip.textPrimary,
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                // points
                ForEach(Array(points.enumerated()), id: \.offset) { i, p in
                    Circle().fill(color)
                        .frame(width: 8, height: 8)
                        .overlay(Circle().stroke(Color.drip.cardBackground, lineWidth: 1.5))
                        .position(x: xAt(i), y: yAt(Double(p.effectivePaceSec)))
                }
                // first / last date labels
                if let firstP = points.first {
                    Text(firstP.dateLabel.uppercased())
                        .font(.dripEyebrow(8)).tracking(8 * 0.06)
                        .foregroundColor(Color.drip.textTertiary)
                        .position(x: sidePad + 18, y: H - 8)
                }
                if points.count > 1, let lastP = points.last {
                    Text(lastP.dateLabel.uppercased())
                        .font(.dripEyebrow(8)).tracking(8 * 0.06)
                        .foregroundColor(Color.drip.textTertiary)
                        .position(x: W - sidePad - 18, y: H - 8)
                }
            }
        }
    }
}

// MARK: - Stat cell

private struct StatCell: View {
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.dripEyebrow(8.5)).tracking(8.5 * 0.06)
                .foregroundColor(Color.drip.textTertiary).fixedSize()
            Text(value).font(.dripStat(17)).foregroundColor(Color.drip.textPrimary)
                .minimumScaleFactor(0.75).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 11).padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.drip.background))
    }
}

#if DEBUG
#Preview("Fast segments") {
    FastSegmentsView(
        trends: FastSegmentSampleData.systemTrends(),
        sessions: FastSegmentSampleData.sessions
    )
}
#endif

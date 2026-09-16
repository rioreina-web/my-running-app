//
//  CompareDashboardCharts.swift
//  RunningLog
//
//  The pieces of the Compare dashboard: the head-to-head number grid, the two
//  Canvas scatter plots, the mini trend charts, and the expand sheet. Kept in
//  their own file so CompareDashboardView stays a layout.
//

import SwiftUI

// MARK: - Head-to-head number grid
//
//  Layout per the "Head-to-Head · Post Run Drip" design mock (Rio, 2026-07-27):
//  "Two sessions." headline with a days-apart meta line, ●/○ session markers,
//  winner-in-bold-ink values (loser gray, ties gray — never color), A/B column
//  letters over the number columns, a FROM YOUR COACH read behind a coral rule,
//  and an italic footnote naming the bold convention.

struct HeadToHeadCard: View {
    let sessions: [FastSession]
    @Binding var aID: String
    @Binding var bID: String
    let heat: Bool
    let hills: Bool
    let zones: PaceZonesEngine?
    /// Tapped "Open workout" — the parent fetches the log + presents its detail.
    var onOpenWorkout: (String) -> Void

    private var a: FastSession? { sessions.first { $0.id == aID } }
    private var b: FastSession? { sessions.first { $0.id == bID } }

    private static let iso: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let a, let b {
                Text("HEAD-TO-HEAD")
                    .font(.dripEyebrow(10)).tracking(10 * 0.14)
                    .foregroundColor(Color.drip.textSecondary)
                Text("Two sessions.")
                    .font(.dripDisplay(26))
                    .foregroundColor(Color.drip.textPrimary)
                    .padding(.top, 4)
                Text(metaLine(a, b))
                    .font(.dripEyebrow(9)).tracking(9 * 0.1)
                    .foregroundColor(Color.drip.textTertiary)
                    .padding(.top, 5)

                HStack(alignment: .top, spacing: 0) {
                    matchupColumn(a, tag: "A", filled: true, selection: $aID)
                        .padding(.trailing, 14)
                    Rectangle().fill(Color.drip.divider).frame(width: 1)
                    matchupColumn(b, tag: "B", filled: false, selection: $bID)
                        .padding(.leading, 14)
                }
                .padding(.top, 14)

                // column letters over the two number columns
                HStack {
                    Spacer()
                    Text("A").font(.dripEyebrow(9)).tracking(9 * 0.1)
                        .foregroundColor(Color.drip.textTertiary)
                        .frame(width: 70, alignment: .trailing)
                    Text("B").font(.dripEyebrow(9)).tracking(9 * 0.1)
                        .foregroundColor(Color.drip.textTertiary)
                        .frame(width: 70, alignment: .trailing)
                }
                .padding(.top, 12)

                VStack(spacing: 0) {
                    ForEach(["OUTPUT", "COST", "CONDITIONS"], id: \.self) { group in
                        editorialRule(group)
                        ForEach(CompareMetrics.all.filter { $0.group == group }) { m in
                            row(m, a, b)
                        }
                    }
                }
                .padding(.top, 2)

                coachNote(a, b)
                    .padding(.top, 16)

                Text("Pace is the clock — what you actually ran. The smaller lines beneath it are adjustments, not results. Bold is the stronger figure; equal figures stay gray.")
                    .font(.dripBody(11)).italic()
                    .foregroundColor(Color.drip.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14)
            }
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.drip.cardBackground))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.drip.divider, lineWidth: 1))
    }

    // MARK: headline meta — "13 DAYS APART · 6.0 MI OF WORK EACH"

    private func metaLine(_ a: FastSession, _ b: FastSession) -> String {
        var bits: [String] = []
        if let da = Self.iso.date(from: a.date), let db = Self.iso.date(from: b.date) {
            let days = Int((abs(db.timeIntervalSince(da)) / 86_400).rounded())
            bits.append(days == 0 ? "SAME DAY" : (days == 1 ? "1 DAY APART" : "\(days) DAYS APART"))
        }
        if abs(a.fastMiles - b.fastMiles) < 0.05 {
            bits.append("\(fmt1(a.fastMiles)) MI OF WORK EACH")
        } else {
            bits.append("\(fmt1(a.fastMiles)) VS \(fmt1(b.fastMiles)) MI OF WORK")
        }
        return bits.joined(separator: " · ")
    }

    // MARK: matchup header column

    private func matchupColumn(_ s: FastSession, tag: String, filled: Bool, selection: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                if filled {
                    Circle().fill(Color.drip.textPrimary).frame(width: 6, height: 6)
                } else {
                    Circle().stroke(Color.drip.textSecondary, lineWidth: 1.2).frame(width: 6, height: 6)
                }
                Text(tag).font(.dripEyebrow(9)).tracking(9 * 0.12)
                    .foregroundColor(Color.drip.textSecondary)
            }
            Text("\(s.dateLabel).").font(.dripDisplay(22)).foregroundColor(Color.drip.textPrimary)
            Text(structureLine(s))
                .font(.dripEyebrow(9)).tracking(9 * 0.05)
                .foregroundColor(Color.drip.textTertiary).lineLimit(1)
            HStack(spacing: 12) {
                Button { onOpenWorkout(s.id) } label: {
                    Text("Open workout ↗").font(.dripBody(13))
                        .foregroundColor(Color.drip.coral).underline()
                }.buttonStyle(.plain)
                Menu {
                    ForEach(sessions.reversed()) { ss in
                        Button { selection.wrappedValue = ss.id } label: {
                            Text("\(ss.dateLabel) · \(ss.name.isEmpty ? "session" : ss.name)")
                        }
                    }
                } label: {
                    Text("SWAP").font(.dripEyebrow(9)).tracking(9 * 0.08)
                        .foregroundColor(Color.drip.textTertiary)
                }.buttonStyle(.plain)
            }
            .padding(.top, 3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "6 × 1K · 2 × 800M" when the session has a name, else the honest
    /// fallback "SESSION · 6.0 MI" from the mock's B column.
    private func structureLine(_ s: FastSession) -> String {
        s.name.isEmpty ? "SESSION · \(fmt1(s.fastMiles)) MI" : s.name.uppercased()
    }

    // MARK: editorial rule — line · label · line

    private func editorialRule(_ label: String) -> some View {
        HStack(spacing: 8) {
            Rectangle().fill(Color.drip.divider).frame(height: 1)
            Text(label).font(.dripEyebrow(9.5)).tracking(9.5 * 0.14)
                .foregroundColor(Color.drip.textTertiary).fixedSize()
            Rectangle().fill(Color.drip.divider).frame(height: 1)
        }
        .padding(.top, 14).padding(.bottom, 4)
    }

    // MARK: metric row — verdict by emphasis, never color

    private func row(_ m: CompareMetric, _ a: FastSession, _ b: FastSession) -> some View {
        let win = winnerSide(m, a, b)   // 1 = A, -1 = B, 0 = none
        let subs = subRows(m, a, b)
        return VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(m.label).font(.dripBody(14)).foregroundColor(Color.drip.textPrimary)
                    Text(m.hint).font(.dripEyebrow(8)).tracking(8 * 0.05)
                        .foregroundColor(Color.drip.textTertiary)
                }
                Spacer()
                valueText(m, a, isWinner: win == 1, neutral: win == 0)
                    .frame(width: 70, alignment: .trailing)
                valueText(m, b, isWinner: win == -1, neutral: win == 0)
                    .frame(width: 70, alignment: .trailing)
            }
            .padding(.top, 8)
            .padding(.bottom, subs.isEmpty ? 8 : 4)

            ForEach(subs) { s in
                subRow(s.caption, s.a, s.b)
            }

            Rectangle().fill(Color.drip.divider).frame(height: 1)
                .padding(.top, subs.isEmpty ? 0 : 6)
        }
    }

    /// One secondary line of a metric row, in both columns.
    private struct SubLine: Identifiable {
        let caption: String
        let a: String
        let b: String
        var id: String { caption }
    }

    /// The adjusted-pace lines under a headline figure. A line where BOTH
    /// sessions read "—" carries nothing, so it is dropped rather than shown
    /// as a pair of dashes.
    private func subRows(_ m: CompareMetric, _ a: FastSession, _ b: FastSession) -> [SubLine] {
        let av = m.subValues(a), bv = m.subValues(b)
        guard !av.isEmpty, av.count == bv.count else { return [] }
        var out: [SubLine] = []
        for i in av.indices {
            let l = av[i], r = bv[i]
            if l.value == "—" && r.value == "—" { continue }
            out.append(SubLine(caption: l.caption, a: l.value, b: r.value))
        }
        return out
    }

    /// One secondary line: indented caption on the left, the two adjusted
    /// figures under their columns. Always tertiary, never bold — these are the
    /// model's reading of the session, not the session.
    private func subRow(_ caption: String, _ av: String, _ bv: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(caption).font(.dripEyebrow(8)).tracking(8 * 0.05)
                .foregroundColor(Color.drip.textTertiary)
                .padding(.leading, 10)
            Spacer()
            Text(av).font(.dripStat(11)).foregroundColor(Color.drip.textTertiary)
                .frame(width: 70, alignment: .trailing)
            Text(bv).font(.dripStat(11)).foregroundColor(Color.drip.textTertiary)
                .frame(width: 70, alignment: .trailing)
        }
        .padding(.bottom, 2)
    }

    /// 1 if A wins the metric, -1 if B, 0 if neutral / tie / missing.
    private func winnerSide(_ m: CompareMetric, _ a: FastSession, _ b: FastSession) -> Int {
        guard m.dir != .neutral,
              let av = m.value(a, heat, hills), let bv = m.value(b, heat, hills), av != bv else { return 0 }
        let aBetter = (m.dir == .lowerBetter) ? av < bv : av > bv
        return aBetter ? 1 : -1
    }

    /// Verdict by emphasis, never color (mock: "Bold is the stronger figure.
    /// Equal figures stay gray."). Pace no longer wears the blue ramp here —
    /// in a two-column duel the ramp read as decoration, and the maps below
    /// already carry pace color.
    private func valueText(_ m: CompareMetric, _ s: FastSession, isWinner: Bool, neutral: Bool) -> some View {
        let v = m.display(s, heat, hills)
        let color: Color
        if v == "—" {
            color = Color.drip.textTertiary
        } else if neutral {
            color = Color.drip.textSecondary
        } else {
            color = isWinner ? Color.drip.textPrimary : Color.drip.textTertiary
        }
        return Text(v)
            .font(.dripStat(15))
            .fontWeight(isWinner && !neutral ? .semibold : .regular)
            .foregroundColor(color)
    }

    // MARK: from your coach — deterministic read on the pair

    /// Rule-based observation (no LLM call): who was sharper, what it cost,
    /// one soft steer. Pure function of the two sessions under the current
    /// toggles — same inputs, same sentence. AI advises, never acts.
    private func coachNote(_ a: FastSession, _ b: FastSession) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Rectangle().fill(Color.drip.coral).frame(width: 2)
            VStack(alignment: .leading, spacing: 5) {
                Text("FROM YOUR COACH")
                    .font(.dripEyebrow(9)).tracking(9 * 0.12)
                    .foregroundColor(Color.drip.textSecondary)
                Text(coachRead(a, b))
                    .font(.dripBody(13)).italic()
                    .foregroundColor(Color.drip.textPrimary)
                    .lineSpacing(2.5)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func coachRead(_ a: FastSession, _ b: FastSession) -> String {
        var aWins = 0, bWins = 0
        for m in CompareMetrics.all {
            let w = winnerSide(m, a, b)
            if w == 1 { aWins += 1 } else if w == -1 { bWins += 1 }
        }
        guard aWins != bWins else {
            return "Dead level — the numbers split evenly. Read these as the same stimulus on two different days."
        }
        let w = aWins > bWins ? a : b
        let l = aWins > bWins ? b : a

        // The winner's edge, in the mock's cadence: up to three clauses.
        var edges: [String] = []
        if let wr = w.avgRepM, let lr = l.avgRepM, wr < lr { edges.append("shorter reps") }
        if !w.isContinuous, !l.isContinuous, w.avgRestSec > 0, l.avgRestSec > 0, w.avgRestSec < l.avgRestSec {
            edges.append(l.avgRestSec >= w.avgRestSec * 3 / 2 ? "half the rest" : "less rest")
        }
        if let wd = w.hrDriftBpm, let ld = l.hrDriftBpm, abs(wd) < abs(ld) {
            edges.append(abs(wd) <= 2 ? "almost no drift" : "less drift")
        }
        let sameHr: Bool = {
            guard let wh = w.avgHr, let lh = l.avgHr else { return false }
            return abs(wh - lh) <= 2
        }()

        var out = "\(w.dateLabel) was the sharper session"
        if !edges.isEmpty {
            out += " — " + edges.prefix(3).joined(separator: ", ")
            if sameHr { out += " for the same heart rate" }
        }
        out += "."

        // What the other one bought, honestly.
        // Raw clock pace, matching the headline figure in the grid above — a
        // read that quotes a number the athlete can't find on screen is worse
        // than no read at all.
        let paceGap = l.avgPaceSec - w.avgPaceSec
        if l.densityPct > w.densityPct, paceGap > 0 {
            out += " \(l.dateLabel) bought its density at \(paceGap) seconds slower."
        } else if l.fastMiles > w.fastMiles + 0.05 {
            out += " \(l.dateLabel) carried more work — \(fmt1(l.fastMiles)) against \(fmt1(w.fastMiles)) miles."
        } else if paceGap > 0 {
            out += " \(l.dateLabel) gave back \(paceGap) seconds per mile."
        }

        out += " Chase the \(w.dateLabel) shape when the goal is speed."
        return out
    }

    private func fmt1(_ x: Double) -> String { String(format: "%.1f", x) }
}

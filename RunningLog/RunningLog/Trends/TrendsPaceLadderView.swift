//
//  TrendsPaceLadderView.swift
//  RunningLog · Trends
//
//  The Trends-v2 pace ladder (spec §7): one row per pace zone on the blue
//  depth ramp, each showing the neutral-equivalent pace (heat + hills priced
//  out), the start→now change, the volume that supports it, and a sparkline.
//
//  Two rules it never breaks (spec §1):
//    • Pace is plotted as pace — the slowest value sits at the TOP, so the
//      line falls as you get faster. No axis flip.
//    • A zone with fewer than two sessions of work is withheld and NAMED,
//      never drawn as a one-point line.
//
//  Source: `TrendsService.keySessions` (`quality_sessions[]`), grouped by the
//  athlete's own zone classification. Neutral-equivalent pace is
//  `workPaceAdjSec` (heat-adjusted) when present, else the raw work pace.
//

import SwiftUI

struct TrendsPaceLadderView: View {
    let sessions: [KeySession]
    /// Tapping a zone drills into that zone's own history + sessions.
    var onSelect: ((String) -> Void)? = nil

    /// Slow → fast display order (MP first), the reverse of `KeyZone.order`.
    private static let displayOrder = ["mp", "hmp", "10k", "5k", "3k", "mile"]

    private var rows: [LadderRow] { Self.buildRows(sessions) }
    private var withheld: [String] { Self.withheldZones(sessions) }

    var body: some View {
        if rows.isEmpty {
            EmptyStateView(
                variant: .dataPending,
                eyebrow: "No race-pace work yet",
                title: "Quality sessions land here as you log them, sorted by pace."
            )
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Text("Pace plotted as pace · the line sits lower when you’re faster · no axis flips")
                    .font(.dripCaption(9))
                    .foregroundStyle(Color.drip.textTertiary)
                    .padding(.bottom, 10)

                ForEach(rows) { row in
                    Button { onSelect?(row.id) } label: { ladderRow(row) }
                        .buttonStyle(.plain)
                        .disabled(onSelect == nil)
                    if row.id != rows.last?.id {
                        Rectangle().fill(Color.drip.divider).frame(height: 1)
                    }
                }

                if !withheld.isEmpty {
                    Text(withheldSentence)
                        .font(.dripCaption(10))
                        .italic()
                        .foregroundStyle(Color.drip.textTertiary)
                        .padding(.top, 12)
                }
            }
        }
    }

    // MARK: One zone row

    private func ladderRow(_ row: LadderRow) -> some View {
        HStack(spacing: 10) {
            // Zone swatch (blue depth).
            RoundedRectangle(cornerRadius: 2)
                .fill(row.color)
                .frame(width: 10, height: 34)

            // Name + subtitle + supporting-volume bar.
            VStack(alignment: .leading, spacing: 3) {
                Text(row.name)
                    .font(.dripDisplay(16))
                    .foregroundStyle(Color.drip.textPrimary)
                Text(row.subtitle)
                    .font(.dripCaption(8))
                    .foregroundStyle(Color.drip.textTertiary)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.drip.paperDeep).frame(height: 3)
                        Capsule().fill(row.color)
                            .frame(width: geo.size.width * row.volumeFraction, height: 3)
                    }
                }
                .frame(height: 3)
                Text("\(Int(row.supportingMiles.rounded())) mi supporting")
                    .font(.dripCaption(8))
                    .foregroundStyle(Color.drip.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Pace + delta.
            VStack(alignment: .trailing, spacing: 3) {
                Text(TrendsFormat.pace(row.currentPaceSec))
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.drip.textPrimary)
                Text(row.deltaLabel)
                    .font(.dripCaption(8))
                    .foregroundStyle(row.deltaSec < 0 ? Color.drip.textPrimary : Color.drip.textTertiary)
            }
            .frame(width: 72, alignment: .trailing)

            // Sparkline — pace as pace, falling = faster.
            PaceSparkline(values: row.paceSeries, color: row.color)
                .frame(width: 56, height: 26)

            if onSelect != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.drip.textTertiary)
            }
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private var withheldSentence: String {
        let names = withheld.map { KeyZone.label($0) }
        let joined = names.count > 1
            ? names.dropLast().joined(separator: ", ") + " and " + names.last!
            : names.first ?? ""
        let verb = withheld.count > 1 ? "aren’t" : "isn’t"
        return "\(joined) \(verb) shown — fewer than two sessions of that work in this window. Not missing, just not enough to draw a line through."
    }

    // MARK: - Row model + derivation

    private struct LadderRow: Identifiable {
        let id: String          // zone token
        let name: String
        let subtitle: String
        let color: Color
        let currentPaceSec: Int
        let deltaSec: Int       // start → now; negative = faster
        let paceSeries: [Int]   // neutral paces, oldest → newest
        let supportingMiles: Double
        let volumeFraction: Double

        var deltaLabel: String {
            if deltaSec == 0 { return "unchanged" }
            return "\(abs(deltaSec))s/mi \(deltaSec < 0 ? "faster" : "slower")"
        }
    }

    /// Neutral-equivalent pace for a session — heat-adjusted when present.
    private static func neutralPace(_ s: KeySession) -> Int { s.workPaceAdjSec ?? s.workPaceSec }

    private static func grouped(_ sessions: [KeySession]) -> [String: [KeySession]] {
        var byZone: [String: [KeySession]] = [:]
        for s in sessions where !s.isLongRun {
            byZone[s.zone.lowercased(), default: []].append(s)
        }
        // Oldest → newest inside each zone.
        for z in byZone.keys { byZone[z]!.sort { $0.date < $1.date } }
        return byZone
    }

    private static func buildRows(_ sessions: [KeySession]) -> [LadderRow] {
        let byZone = grouped(sessions)
        let maxZoneMiles = max(byZone.values.map { zs in
            zs.compactMap { $0.distanceMi }.reduce(0, +)
        }.max() ?? 1, 1)

        return displayOrder.compactMap { zone -> LadderRow? in
            guard let zs = byZone[zone], zs.count >= 2 else { return nil }
            let series = zs.map { neutralPace($0) }
            let miles = zs.compactMap { $0.distanceMi }.reduce(0, +)
            return LadderRow(
                id: zone,
                name: KeyZone.label(zone),
                subtitle: subtitle(zone),
                color: color(zone),
                currentPaceSec: series.last!,
                deltaSec: series.last! - series.first!,
                paceSeries: series,
                supportingMiles: miles,
                volumeFraction: min(1, miles / maxZoneMiles)
            )
        }
    }

    /// Zones present but with < 2 sessions — withheld and named (spec §1).
    private static func withheldZones(_ sessions: [KeySession]) -> [String] {
        let byZone = grouped(sessions)
        return displayOrder.filter { (byZone[$0]?.count ?? 0) == 1 }
    }

    private static func subtitle(_ zone: String) -> String {
        switch zone {
        case "mp":   "Marathon pace"
        case "hmp":  "Half-marathon pace"
        case "10k":  "10K pace"
        case "5k":   "5K pace reps"
        case "3k":   "3K pace reps"
        case "mile": "Mile pace"
        default:     "Race pace"
        }
    }

    private static func color(_ zone: String) -> Color {
        switch zone {
        case "mp":   PaceSpectrum.mp
        case "hmp":  PaceSpectrum.hmp
        case "10k":  PaceSpectrum.tenK
        case "5k":   PaceSpectrum.fiveK
        case "3k":   PaceSpectrum.threeK
        case "mile": PaceSpectrum.mile
        default:     PaceSpectrum.mp
        }
    }
}

// MARK: - Sparkline (pace as pace — no axis flip)

private struct PaceSparkline: View {
    let values: [Int]
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let pts = points(in: geo.size)
            ZStack {
                Path { p in
                    guard let first = pts.first else { return }
                    p.move(to: first)
                    for q in pts.dropFirst() { p.addLine(to: q) }
                }
                .stroke(color.opacity(0.9), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                if let last = pts.last {
                    Circle().fill(color).frame(width: 3.8, height: 3.8).position(last)
                }
            }
        }
    }

    /// Slowest (largest sec) at the TOP → the line falls as pace improves.
    /// No axis flip: pace is plotted as pace.
    private func points(in size: CGSize) -> [CGPoint] {
        guard !values.isEmpty else { return [] }
        let lo = values.min()!, hi = values.max()!
        let span = CGFloat(max(hi - lo, 1))
        let w = size.width, h = size.height
        return values.indices.map { i in
            let x = values.count == 1 ? w / 2 : w * CGFloat(i) / CGFloat(values.count - 1)
            // Slowest (largest sec) → top (small y); fastest → bottom. So the
            // line FALLS as pace improves. `hi - value`, never `value - lo`.
            let y = 2 + (h - 4) * CGFloat(hi - values[i]) / span
            return CGPoint(x: x, y: y)
        }
    }
}

// MARK: - Preview data

extension KeySession {
    /// Synthetic quality sessions across ~12 weeks — MP/HMP/5K each improving
    /// (neutral pace falling), for the ladder preview.
    static var previewLadder: [KeySession] {
        func mk(_ daysAgo: Int, _ zone: String, pace: Int, adj: Int, mi: Double) -> KeySession {
            var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
            let d = cal.date(byAdding: .day, value: -daysAgo, to: cal.startOfDay(for: Date()))!
            let f = DateFormatter(); f.timeZone = TimeZone(identifier: "UTC")!; f.dateFormat = "yyyy-MM-dd"
            let iso = f.string(from: d)
            return KeySession(id: iso + zone, date: iso, dateLabel: "", zone: zone,
                              workPaceSec: pace, workPaceAdjSec: adj, heatCategory: "warm",
                              workHrAvg: 158, structure: nil, distanceMi: mi,
                              qualityLoad: 20, kind: "quality")
        }
        return [
            mk(80, "mp", pace: 452, adj: 442, mi: 6), mk(52, "mp", pace: 446, adj: 436, mi: 8), mk(18, "mp", pace: 440, adj: 430, mi: 7),
            mk(74, "hmp", pace: 424, adj: 419, mi: 4), mk(40, "hmp", pace: 418, adj: 413, mi: 5), mk(12, "hmp", pace: 412, adj: 407, mi: 6),
            mk(60, "5k", pace: 382, adj: 378, mi: 3), mk(26, "5k", pace: 378, adj: 374, mi: 3.5),
            mk(30, "10k", pace: 398, adj: 394, mi: 4),   // single → withheld, named
        ]
    }
}

#Preview("Pace ladder") {
    TrendsPaceLadderView(sessions: KeySession.previewLadder)
        .padding()
        .background(Color.drip.cardBackground)
}

//
//  TrendsZoneDetailView.swift
//  RunningLog · Trends
//
//  The drill-down behind a pace-ladder row: one zone's own trend, in full.
//  Tapping "MP" (or 5K, Mile, …) opens this — the zone's pace over time
//  (date-spaced, pace-as-pace, no axis flip), its supporting volume, and the
//  actual sessions that produced it. All from `TrendsService.keySessions`,
//  filtered to the zone — the same rep pace the ladder shows.
//

import SwiftUI

struct TrendsZoneDetailView: View {
    let zone: String
    /// All key sessions; filtered to this zone here.
    let sessions: [KeySession]

    private var zoneSessions: [KeySession] {
        sessions
            .filter { $0.zone.lowercased() == zone && !$0.isLongRun }
            .sorted { $0.date < $1.date }
    }

    /// Neutral-equivalent (heat-priced-out) pace per session, oldest → newest.
    private var paces: [Int] { zoneSessions.map { $0.workPaceAdjSec ?? $0.workPaceSec } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                if paces.count >= 2 {
                    ZonePaceChart(sessions: zoneSessions, color: color)
                        .frame(height: 150)
                        .padding(.top, 18)
                    Text("Neutral-equivalent pace · heat + hills priced out · the line sits lower when you’re faster")
                        .font(.dripCaption(9))
                        .foregroundStyle(Color.drip.textTertiary)
                        .padding(.top, 8)
                } else if !zoneSessions.isEmpty {
                    Text("One session so far at this pace — the trend line fills in as you log more.")
                        .font(.dripBody(13)).italic()
                        .foregroundStyle(Color.drip.textTertiary)
                        .padding(.top, 16)
                }

                Text("The sessions")
                    .font(.dripEyebrow(11))
                    .foregroundStyle(Color.drip.textSecondary)
                    .padding(.top, 26).padding(.bottom, 8)

                ForEach(Array(zoneSessions.reversed().enumerated()), id: \.element.id) { i, s in
                    sessionRow(s)
                    if i < zoneSessions.count - 1 {
                        Rectangle().fill(Color.drip.divider).frame(height: 1)
                    }
                }
            }
            .padding(24)
        }
        .background(Color.drip.background)
        .presentationDragIndicator(.visible)
    }

    // MARK: Header

    private var header: some View {
        let cur = paces.last ?? 0
        let delta = (paces.last ?? 0) - (paces.first ?? 0)
        let mi = zoneSessions.compactMap { $0.distanceMi }.reduce(0, +)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(KeyZone.label(zone)).font(.dripDisplay(26)).foregroundStyle(Color.drip.textPrimary)
                    Text(subtitle).font(.dripCaption(9)).foregroundStyle(Color.drip.textTertiary)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(TrendsFormat.pace(cur))
                    .font(.system(size: 30, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.drip.textPrimary)
                if paces.count >= 2 {
                    Text(delta == 0 ? "unchanged" : "\(abs(delta))s/mi \(delta < 0 ? "faster" : "slower")")
                        .font(.dripCaption(10))
                        .foregroundStyle(delta < 0 ? Color.drip.textPrimary : Color.drip.textTertiary)
                }
            }
            Text("\(zoneSessions.count) session\(zoneSessions.count == 1 ? "" : "s") · \(Int(mi.rounded())) mi supporting")
                .font(.dripCaption(9))
                .foregroundStyle(Color.drip.textTertiary)
        }
    }

    // MARK: One session

    private func sessionRow(_ s: KeySession) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(s.dateLabel.uppercased()).font(.dripCaption(10)).foregroundStyle(Color.drip.textSecondary)
                if let mi = s.distanceMi {
                    Text("· \(String(format: "%.1f", mi)) mi").font(.dripCaption(10)).foregroundStyle(Color.drip.textTertiary)
                }
                Spacer()
                Text("\(TrendsFormat.pace(s.workPaceSec)) /mi")
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.drip.textPrimary)
            }
            HStack(spacing: 6) {
                if let hr = s.workHrAvg { Text("\(hr) BPM") }
                if s.isHeatAdjusted { Text("· neutral-eq \(TrendsFormat.pace(s.effectivePaceSec))") }
                if let st = s.structure, !st.isEmpty { Text("· \(st)") }
            }
            .font(.dripCaption(9))
            .foregroundStyle(Color.drip.textTertiary)
        }
        .padding(.vertical, 12)
    }

    // MARK: Zone display

    private var subtitle: String {
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
    private var color: Color {
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

// MARK: - Pace-over-time chart (date-spaced, pace-as-pace)

private struct ZonePaceChart: View {
    let sessions: [KeySession]
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let pts = points(in: geo.size)
            ZStack {
                // Line.
                Path { p in
                    guard let f = pts.first else { return }
                    p.move(to: f)
                    for q in pts.dropFirst() { p.addLine(to: q) }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                // Points.
                ForEach(Array(pts.enumerated()), id: \.offset) { _, pt in
                    Circle().fill(color).frame(width: 5, height: 5).position(pt)
                }
            }
        }
    }

    /// Slowest pace at the TOP (no axis flip); x spaced by real date.
    private func points(in size: CGSize) -> [CGPoint] {
        let vals = sessions.map { Double($0.workPaceAdjSec ?? $0.workPaceSec) }
        let days = sessions.map { Self.dayNumber($0.date) }
        guard vals.count >= 2, let d0 = days.first, let dN = days.last, dN > d0 else {
            return sessions.indices.map { i in
                CGPoint(x: size.width * CGFloat(i) / CGFloat(max(1, sessions.count - 1)), y: size.height / 2)
            }
        }
        let lo = vals.min()!, hi = vals.max()!, span = max(hi - lo, 1)
        let dSpan = Double(dN - d0)
        return vals.indices.map { i in
            let x = size.width * CGFloat(Double(days[i] - d0) / dSpan)
            let y = 4 + (size.height - 8) * CGFloat((hi - vals[i]) / span)
            return CGPoint(x: x, y: y)
        }
    }

    /// "yyyy-MM-dd" → days since epoch (UTC), for real calendar spacing.
    private static func dayNumber(_ iso: String) -> Int {
        let p = iso.split(separator: "-")
        guard p.count == 3, let y = Int(p[0]), let m = Int(p[1]), let d = Int(p[2]) else { return 0 }
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let date = cal.date(from: DateComponents(year: y, month: m, day: d)) ?? Date(timeIntervalSince1970: 0)
        return Int(date.timeIntervalSince1970 / 86400)
    }
}

#Preview("Zone detail · MP") {
    TrendsZoneDetailView(zone: "mp", sessions: KeySession.previewLadder)
}

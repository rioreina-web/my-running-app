//
//  TrendsKeySessionsView.swift
//  RunningLog · Trends
//
//  The "show me the actual runs" section — the last few key sessions, each on
//  the day it was run, with its work-bout pace (heat-corrected alongside raw),
//  heart rate, and distance. Reads `TrendsService.keySessions`
//  (`quality_sessions[]`) — real data, no synthesis.
//

import SwiftUI

struct TrendsKeySessionsView: View {
    let sessions: [KeySession]
    var limit: Int = 5

    private var recent: [KeySession] {
        Array(sessions.sorted { $0.date > $1.date }.prefix(limit))
    }

    var body: some View {
        if recent.isEmpty {
            EmptyStateView(
                variant: .dataPending,
                eyebrow: "No key sessions yet",
                title: "Quality days and long runs land here as you log them."
            )
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(recent.enumerated()), id: \.element.id) { i, s in
                    row(s)
                    if i < recent.count - 1 {
                        Rectangle().fill(Color.drip.divider).frame(height: 1)
                    }
                }
            }
        }
    }

    private func row(_ s: KeySession) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(zoneName(s)) \(distance(s))")
                    .font(.dripDisplay(16))
                    .foregroundStyle(zoneColor(s))
                Spacer()
                Text("\(TrendsFormat.pace(s.workPaceSec)) /mi")
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.drip.textPrimary)
            }
            HStack(spacing: 6) {
                Text(s.dateLabel.uppercased())
                if let hr = s.workHrAvg { dot(); Text("\(hr) BPM") }
                if s.isHeatAdjusted { dot(); Text("NEUTRAL-EQ \(TrendsFormat.pace(s.effectivePaceSec))") }
            }
            .font(.dripCaption(9))
            .foregroundStyle(Color.drip.textTertiary)
        }
        .padding(.vertical, 12)
    }

    private func dot() -> some View {
        Text("·").font(.dripCaption(9)).foregroundStyle(Color.drip.textTertiary)
    }

    private func distance(_ s: KeySession) -> String {
        guard let mi = s.distanceMi else { return "" }
        return String(format: "%.1f mi", mi)
    }

    private func zoneName(_ s: KeySession) -> String {
        s.isLongRun ? "Long" : KeyZone.label(s.zone)
    }

    private func zoneColor(_ s: KeySession) -> Color {
        if s.isLongRun { return Color.drip.textSecondary }
        switch s.zone.lowercased() {
        case "mp":   return PaceSpectrum.mp
        case "hmp":  return PaceSpectrum.hmp
        case "10k":  return PaceSpectrum.tenK
        case "5k":   return PaceSpectrum.fiveK
        case "3k":   return PaceSpectrum.threeK
        case "mile": return PaceSpectrum.mile
        default:     return Color.drip.textPrimary
        }
    }
}

#Preview("Key sessions") {
    TrendsKeySessionsView(sessions: KeySession.previewLadder)
        .padding()
        .background(Color.drip.cardBackground)
}

//
//  RepDensityStrip.swift
//  RunningLog
//
//  The pace × volume ledger mark: one block per work rep, width
//  proportional to the rep's measured distance, colored on the
//  PaceSpectrum ramp anchored to the athlete's zone table — a 5K rep is
//  the same red in every list it appears in. Rest is excluded by
//  construction (it's the gaps between blocks). 18pt of chart, no axes:
//  a column of these turns a workout list into a flip-book of the block.
//
//  Data path mirrors the Rep Receipt exactly: `mergeWorkBouts` for rep
//  geometry, the same work-rep predicate, so this strip and the tap-through
//  detail never disagree about what a rep was.
//
//  Degradation: no zone table → per-workout bounds; a single continuous
//  bout (nothing to compare) → the view renders empty and callers lose
//  nothing. Never fakes a rep.
//
//  Design: outputs/pace-volume-studies-2026-07-02.html (Study D).
//

import SwiftUI

struct RepDensityStrip: View {
    /// Raw laps for one workout, any order. Work bouts are merged and rests
    /// dropped internally.
    let laps: [WorkoutLapRow]
    var height: CGFloat = 12

    private struct Block: Identifiable {
        let id: Int
        let weight: Double   // meters — sets the block's share of the width
        let paceSec: Double  // sec/mi — sets the block's ramp color
    }

    private var blocks: [Block] {
        let merged = WorkoutLapsService.mergeWorkBouts(laps)
        let work = merged.filter { lap in
            lap.is_rest != true
                && (lap.avg_pace_sec_per_mile ?? 0) > 0
                && (lap.distance_meters ?? 0) >= 150
                && (lap.moving_time_seconds ?? 0) >= 20
        }
        return work.enumerated().map { i, lap in
            Block(id: i, weight: lap.distance_meters ?? 0, paceSec: lap.avg_pace_sec_per_mile ?? 0)
        }
    }

    var body: some View {
        let blocks = self.blocks
        if blocks.count >= 2 {
            Canvas { ctx, size in
                let gap: CGFloat = 2
                let totalWeight = blocks.reduce(0) { $0 + $1.weight }
                guard totalWeight > 0 else { return }
                let avail = size.width - gap * CGFloat(blocks.count - 1)
                guard avail > 0 else { return }
                var x: CGFloat = 0
                for b in blocks {
                    let w = avail * CGFloat(b.weight / totalWeight)
                    let rect = CGRect(x: x, y: 0, width: w, height: size.height)
                    ctx.fill(
                        Path(roundedRect: rect, cornerRadius: 1.5),
                        with: .color(color(for: b, in: blocks))
                    )
                    x += w + gap
                }
            }
            .frame(height: height)
        }
    }

    /// Zone-anchored ramp first (same pace = same color everywhere); the
    /// workout's own pace bounds when no zone table exists; flat ink when
    /// the session has no pace spread to speak of.
    private func color(for block: Block, in blocks: [Block]) -> Color {
        if let anchored = PaceSpectrum.anchoredColor(
            paceSec: block.paceSec,
            zones: PaceZonesService.shared.zones
        ) {
            return anchored
        }
        let paces = blocks.map(\.paceSec)
        guard let slow = paces.max(), let fast = paces.min(), slow - fast > 1 else {
            return Color.drip.textPrimary.opacity(0.82)
        }
        return PaceSpectrum.color(forPaceSec: block.paceSec, slowSec: slow, fastSec: fast)
    }
}

#Preview("Density strips") {
    let fiveKDay: [WorkoutLapRow] = [
        WorkoutLapRow(lap_index: 0, distance_meters: 1000, moving_time_seconds: 189, avg_pace_sec_per_mile: 304, avg_heart_rate: 168, is_rest: false, temp_f: nil, dew_point_f: nil, heat_adjusted_pace_sec_per_mile: nil),
        WorkoutLapRow(lap_index: 1, distance_meters: 250, moving_time_seconds: 95, avg_pace_sec_per_mile: 610, avg_heart_rate: 140, is_rest: true, temp_f: nil, dew_point_f: nil, heat_adjusted_pace_sec_per_mile: nil),
        WorkoutLapRow(lap_index: 2, distance_meters: 1000, moving_time_seconds: 191, avg_pace_sec_per_mile: 307, avg_heart_rate: 170, is_rest: false, temp_f: nil, dew_point_f: nil, heat_adjusted_pace_sec_per_mile: nil),
        WorkoutLapRow(lap_index: 3, distance_meters: 250, moving_time_seconds: 96, avg_pace_sec_per_mile: 615, avg_heart_rate: 141, is_rest: true, temp_f: nil, dew_point_f: nil, heat_adjusted_pace_sec_per_mile: nil),
        WorkoutLapRow(lap_index: 4, distance_meters: 600, moving_time_seconds: 111, avg_pace_sec_per_mile: 298, avg_heart_rate: 173, is_rest: false, temp_f: nil, dew_point_f: nil, heat_adjusted_pace_sec_per_mile: nil),
        WorkoutLapRow(lap_index: 5, distance_meters: 250, moving_time_seconds: 97, avg_pace_sec_per_mile: 620, avg_heart_rate: 139, is_rest: true, temp_f: nil, dew_point_f: nil, heat_adjusted_pace_sec_per_mile: nil),
        WorkoutLapRow(lap_index: 6, distance_meters: 1000, moving_time_seconds: 196, avg_pace_sec_per_mile: 314, avg_heart_rate: 171, is_rest: false, temp_f: nil, dew_point_f: nil, heat_adjusted_pace_sec_per_mile: nil),
    ]
    return VStack(alignment: .leading, spacing: 16) {
        RepDensityStrip(laps: fiveKDay)
        RepDensityStrip(laps: fiveKDay, height: 16)
    }
    .padding(24)
    .background(Color.drip.background)
}

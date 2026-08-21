//
//  LongRunPaceStrip.swift
//  RunningLog
//
//  The long-run mark: ONE CONTINUOUS BAR, split at the athlete's own mile
//  (or km) splits, each split's width proportional to its distance and its
//  color taken from the same zone-anchored PaceSpectrum ramp everything else
//  on the app uses — pale sky for easy, deepening toward navy as the split
//  gets faster. A long run is one unbroken effort, so unlike `RepDensityStrip`
//  there are NO GAPS between blocks: the gaps in a rep strip mean "rest", and
//  a long run has none to show.
//
//  Why a second strip and not a flag on the first (2026-08-19, Rio):
//  `RepDensityStrip` runs `mergeWorkBouts` first, which joins every
//  consecutive non-rest lap into one bout. That is exactly right for a rep
//  workout (a 2 mi rep the watch auto-lapped at each mile is ONE rep) and
//  exactly wrong for a long run — it collapsed 25 recorded mile splits on the
//  2026-08-01 run into three flat slabs, one per water-stop pause. The shape
//  of a long run IS its splits; merging them is throwing away the reading.
//
//  What it draws, and what it refuses to draw:
//    • Splits, in recorded order. Rest/pause laps are dropped rather than
//      drawn — a 14-second, 50-metre pause has no pace worth coloring — and
//      the bar simply closes over them. It stays continuous because the RUN
//      was continuous; the pause is not a rep boundary.
//    • Nothing at all below `minSplits` splits. Several long runs in the data
//      (2026-08-16, 2026-08-08, 2026-07-18) carry a single summary lap: no
//      splits were ever recorded, so there is no shape to show and the row
//      renders no strip. A flat bar at the average would be a picture of even
//      pacing the app never measured — the same lie `deriveKeySession` avoids
//      when it emits no dot for a lap-less session.
//    • Zone-anchored color ONLY when a zone table exists, so a 6:20 mile is
//      the same color here, on the Read, and on a rep strip. Without zones it
//      falls back to the run's own slow/fast bounds, and to flat ink when the
//      run has no spread to speak of.
//
//  Design: PaceSpectrum.swift (the one color==pace language),
//  outputs/pace-volume-studies-2026-07-02.html (Study D, the rep sibling).
//

import SwiftUI

struct LongRunPaceStrip: View {
    /// Raw laps for one long run, any order. Sorted, filtered and rendered
    /// as-recorded here — never merged (see the file note).
    let laps: [WorkoutLapRow]
    var height: CGFloat = 12

    /// Fewer splits than this and the bar is not a chart, it's a rectangle.
    /// Four is the floor at which a fade or a progression is legible; the
    /// lap-less long runs (one summary lap) fall well below it and correctly
    /// draw nothing.
    private static let minSplits = 4

    /// A split is a lap that was actually run: far enough and long enough to
    /// carry a meaningful pace. Mirrors the work-lap predicate in
    /// `RepDensityStrip` / `isContinuousAutoLap` so the three never disagree
    /// about which laps are real.
    private static let minSplitMeters: Double = 150
    private static let minSplitSeconds = 20

    private struct Split: Identifiable {
        let id: Int
        let meters: Double   // sets this split's share of the width
        let paceSec: Double  // sets its color on the ramp
    }

    private var splits: [Split] {
        laps
            .sorted { ($0.lap_index ?? 0) < ($1.lap_index ?? 0) }
            .filter {
                $0.is_rest != true
                    && ($0.avg_pace_sec_per_mile ?? 0) > 0
                    && ($0.distance_meters ?? 0) >= Self.minSplitMeters
                    && ($0.moving_time_seconds ?? 0) >= Self.minSplitSeconds
            }
            .enumerated()
            .map { i, lap in
                Split(
                    id: i,
                    meters: lap.distance_meters ?? 0,
                    paceSec: lap.avg_pace_sec_per_mile ?? 0
                )
            }
    }

    var body: some View {
        let splits = self.splits
        if splits.count >= Self.minSplits {
            Canvas { ctx, size in
                let total = splits.reduce(0) { $0 + $1.meters }
                guard total > 0, size.width > 0 else { return }
                // Clip to one rounded bar and paint the splits inside it, so
                // the run reads as a single object with internal structure
                // rather than a row of tiles.
                ctx.clip(to: Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 1.5))
                var x: CGFloat = 0
                for (i, s) in splits.enumerated() {
                    let w = size.width * CGFloat(s.meters / total)
                    // Overlap each split half a point into the next so
                    // antialiasing can't leave a pale hairline between two
                    // fills and invent a split boundary that isn't there.
                    // The last one runs to the edge, absorbing rounding drift.
                    let isLast = i == splits.count - 1
                    let right = isLast ? size.width : x + w + 0.5
                    let rect = CGRect(x: x, y: 0, width: max(right - x, 0), height: size.height)
                    ctx.fill(Path(rect), with: .color(color(for: s, in: splits)))
                    x += w
                }
            }
            .frame(height: height)
        }
    }

    /// Zone-anchored ramp first — the whole point of the ramp is that the same
    /// pace is the same color on every surface. The run's own bounds only when
    /// there is no zone table to anchor to, and flat ink when even those
    /// bounds are within a second of each other.
    private func color(for split: Split, in splits: [Split]) -> Color {
        if let anchored = PaceSpectrum.anchoredColor(
            paceSec: split.paceSec,
            zones: PaceZonesService.shared.zones
        ) {
            return anchored
        }
        let paces = splits.map(\.paceSec)
        guard let slow = paces.max(), let fast = paces.min(), slow - fast > 1 else {
            return Color.drip.textPrimary.opacity(0.82)
        }
        return PaceSpectrum.color(forPaceSec: split.paceSec, slowSec: slow, fastSec: fast)
    }
}

#Preview("Long run pace strips") {
    // 2026-06-27 — 17.8 mi, 29 km auto-laps. Out at 7:26, down to 6:18 through
    // the middle third, fading to 7:27 over the last three. The shape this
    // mark exists to show, and the reason merging the laps loses it.
    let june27: [WorkoutLapRow] = [
        277, 257, 257, 253, 247, 245, 250, 250, 253, 243,
        235, 245, 239, 241, 244, 244, 243, 241, 246, 252,
        253, 259, 263, 258, 255, 263, 278, 272,
    ].enumerated().map { i, sec in
        WorkoutLapRow(
            lap_index: i + 1, distance_meters: 1000, moving_time_seconds: sec,
            avg_pace_sec_per_mile: Double(sec) * 1.609344,
            avg_heart_rate: nil, is_rest: false, temp_f: nil, dew_point_f: nil,
            heat_adjusted_pace_sec_per_mile: nil
        )
    }

    // One summary lap — no splits were ever recorded (2026-08-16, 2026-08-08).
    // Draws nothing, on purpose.
    let lapless: [WorkoutLapRow] = [
        WorkoutLapRow(lap_index: 1, distance_meters: 27519, moving_time_seconds: 6871,
                      avg_pace_sec_per_mile: 402, avg_heart_rate: nil, is_rest: false,
                      temp_f: nil, dew_point_f: nil, heat_adjusted_pace_sec_per_mile: nil),
    ]

    return VStack(alignment: .leading, spacing: 18) {
        LongRunPaceStrip(laps: june27, height: 10)
        LongRunPaceStrip(laps: june27)
        LongRunPaceStrip(laps: lapless)
    }
    .padding(24)
    .background(Color.drip.background)
}

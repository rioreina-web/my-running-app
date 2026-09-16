//
//  EffortStreamAdapter.swift
//  RunningLog
//
//  Bridges the receipt's cached per-sample arrays (sTimes / sHR / sPace / sCad /
//  sAltFt + stream.distance) into the engine's `[EffortSample]`, and derives the
//  sample interval. Segment derivation from `slots` happens at the call site in
//  WorkoutRepReceiptView (it owns the lap model). Foundation-only.
//

import Foundation

enum EffortStreamAdapter {

    /// The median inter-sample gap in seconds — the resampler's floor. Robust to
    /// the odd dropped sample or pause gap that a mean would smear.
    static func sampleInterval(times: [TimeInterval]) -> TimeInterval {
        guard times.count > 2 else { return 1 }
        var deltas: [TimeInterval] = []
        deltas.reserveCapacity(times.count - 1)
        for i in 1..<times.count {
            let d = times[i] - times[i - 1]
            if d > 0 { deltas.append(d) }
        }
        guard !deltas.isEmpty else { return 1 }
        deltas.sort()
        let mid = deltas[deltas.count / 2]
        return mid > 0 ? mid : 1
    }

    /// Zip the parallel arrays into `[EffortSample]`. Cumulative distance (miles)
    /// comes from the stream's cumulative meters; anything past the shortest
    /// array is dropped so a truncated series can't index out of range.
    static func samples(
        times: [Double], hr: [Double], paceSecPerMile: [Double],
        cadence: [Double], altitudeFt: [Double], distanceMeters: [Double],
        metersPerMile: Double = 1609.344
    ) -> [EffortSample] {
        let n = [times.count, hr.count, paceSecPerMile.count, cadence.count, altitudeFt.count].min() ?? 0
        guard n > 1 else { return [] }
        return (0..<n).map { i in
            let dMi = i < distanceMeters.count ? distanceMeters[i] / metersPerMile : 0
            return EffortSample(
                t: times[i], distanceMiles: dMi, hr: hr[i],
                paceSecPerMile: paceSecPerMile[i], cadenceSPM: cadence[i], elevationFt: altitudeFt[i])
        }
    }
}

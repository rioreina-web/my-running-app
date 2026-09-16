//
//  EffortSeries.swift
//  RunningLog
//
//  "The Effort" chart — sampling / smoothing / derivation (no SwiftUI).
//
//  Ports the handoff §"The chart engine" parts 1 (width resampling), the `14s`
//  smoothing rule, mile-mark walking, and the per-rep aggregates. Kept pure and
//  Foundation-only so it is unit-testable (see EffortSeriesTests).
//

import Foundation

/// A resampled plot point: the bucket's mid-time and its mean value.
struct EffortPoint: Equatable {
    let t: TimeInterval
    let value: Double
}

/// A mile tick: the time at which cumulative distance crossed an integer mile.
struct EffortMileMark: Equatable {
    let t: TimeInterval
    let mile: Int
}

/// Per-rep rollup for the ledger / in-band numbers.
struct EffortRepStat: Equatable {
    let label: String
    let meanPace: Double     // sec/mi
    let meanHR: Double       // bpm
    let deltaVsTarget: Double // sec vs target pace; negative = faster than target
}

enum EffortSeries {

    // MARK: 1 · Width resampling

    /// Resample the samples inside `window` down to roughly one point per
    /// 2.2 pt of plot width, so a 700-pt-tall pace trace doesn't become a
    /// barcode of stride noise.
    ///
    ///     bucket = max(sampleInterval, (windowSpanSeconds / plotWidth) * 2.2)
    ///
    /// Walks the in-window samples, accumulating each into the current time
    /// bucket, and emits `(midTime, meanValue)` once the bucket's time span is
    /// reached.
    static func resample(
        _ samples: [EffortSample],
        window: ClosedRange<TimeInterval>,
        plotWidth: CGFloat,
        sampleInterval: TimeInterval,
        value: (EffortSample) -> Double
    ) -> [EffortPoint] {
        guard plotWidth > 0, !samples.isEmpty else { return [] }
        let windowSpan = max(0, window.upperBound - window.lowerBound)
        let bucket = max(sampleInterval, (windowSpan / Double(plotWidth)) * 2.2)
        guard bucket > 0 else { return [] }

        var out: [EffortPoint] = []
        var bucketStart: TimeInterval? = nil
        var sumV = 0.0
        var sumT = 0.0
        var n = 0

        func flush() {
            guard n > 0 else { return }
            out.append(EffortPoint(t: sumT / Double(n), value: sumV / Double(n)))
            sumV = 0; sumT = 0; n = 0
        }

        for s in samples where s.t >= window.lowerBound && s.t <= window.upperBound {
            if bucketStart == nil { bucketStart = s.t }
            if s.t - bucketStart! >= bucket {
                flush()
                bucketStart = s.t
            }
            sumV += value(s); sumT += s.t; n += 1
        }
        flush()
        return out
    }

    // MARK: · Smoothing (the `14s` toggle)

    /// Centered mean over ±2 samples (5-sample, ~20 s at a 4 s interval). Edges
    /// clamp the window. `RAW` uses the source array; this is the parallel
    /// smoothed array the scrub readout reads when smoothing is on.
    static func smooth(_ values: [Double], radius: Int = 2) -> [Double] {
        guard radius > 0, values.count > 1 else { return values }
        let n = values.count
        var out = [Double](repeating: 0, count: n)
        for i in 0..<n {
            let lo = max(0, i - radius)
            let hi = min(n - 1, i + radius)
            var sum = 0.0
            for j in lo...hi { sum += values[j] }
            out[i] = sum / Double(hi - lo + 1)
        }
        return out
    }

    // MARK: · Mile marks

    /// Emit a tick each time `floor(cumulativeDistance)` increments — walking
    /// the samples, NOT dividing the duration (so marks land at true mile
    /// splits on a variable-pace run).
    static func mileMarks(_ samples: [EffortSample]) -> [EffortMileMark] {
        guard !samples.isEmpty else { return [] }
        var marks: [EffortMileMark] = []
        var nextMile = 1
        var prev = samples[0]
        for s in samples.dropFirst() {
            while Double(nextMile) <= s.distanceMiles + 1e-9 {
                // Linear-interpolate the crossing time between prev and s.
                let d0 = prev.distanceMiles, d1 = s.distanceMiles
                let t: TimeInterval
                if d1 > d0 {
                    let f = (Double(nextMile) - d0) / (d1 - d0)
                    t = prev.t + (s.t - prev.t) * min(max(f, 0), 1)
                } else {
                    t = s.t
                }
                marks.append(EffortMileMark(t: t, mile: nextMile))
                nextMile += 1
            }
            prev = s
        }
        return marks
    }

    // MARK: · Rep aggregates

    /// Mean pace, mean HR and Δ-vs-target for each rep segment. `target` is
    /// sec/mi; Δ is negative when the rep was faster than target.
    static func repStats(
        _ samples: [EffortSample],
        segments: [EffortSegment],
        targetPaceSecPerMile target: Double
    ) -> [EffortRepStat] {
        segments.filter(\.isRep).map { seg in
            let inSeg = samples.filter { seg.contains($0.t) }
            let paces = inSeg.map(\.paceSecPerMile).filter { $0.isFinite && $0 > 0 }
            let hrs = inSeg.map(\.hr).filter { $0.isFinite && $0 > 0 }
            let meanPace = paces.isEmpty ? 0 : paces.reduce(0, +) / Double(paces.count)
            let meanHR = hrs.isEmpty ? 0 : hrs.reduce(0, +) / Double(hrs.count)
            return EffortRepStat(
                label: seg.label,
                meanPace: meanPace,
                meanHR: meanHR,
                deltaVsTarget: meanPace - target
            )
        }
    }

    /// Fraction of `points` whose time falls inside a rep segment — the
    /// `workShare` the autoscaler gates `WORK` mode on.
    static func workShare(points: [EffortPoint], segments: [EffortSegment]) -> Double {
        guard !points.isEmpty else { return 0 }
        let reps = segments.filter(\.isRep)
        guard !reps.isEmpty else { return 0 }
        let inWork = points.reduce(0) { acc, p in
            acc + (reps.contains { $0.contains(p.t) } ? 1 : 0)
        }
        return Double(inWork) / Double(points.count)
    }

    /// The subset of `points` (values only) that fall inside a rep segment.
    static func repValues(points: [EffortPoint], segments: [EffortSegment]) -> [Double] {
        let reps = segments.filter(\.isRep)
        guard !reps.isEmpty else { return [] }
        return points.filter { p in reps.contains { $0.contains(p.t) } }.map(\.value)
    }
}

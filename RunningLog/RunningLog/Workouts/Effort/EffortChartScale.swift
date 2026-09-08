//
//  EffortChartScale.swift
//  RunningLog
//
//  "The Effort" chart — the autoscaler (no SwiftUI). The core of the redesign.
//
//  Ports the handoff §"The chart engine" parts 2 (autoscale WINDOW/WORK/SPLIT),
//  3 (pinned runs), and 4 (ticks). The rule the whole redesign turns on: the
//  work reps own the y-axis, the jog is compressed or pinned, and the chart
//  ALWAYS states on-screen (via `readout` + `note`) that it did so. Nothing is
//  silently hidden — that honesty string is QA's contract.
//
//  Kept pure/Foundation-only; the autoscale rules are the natural test surface
//  (see EffortChartScaleTests).
//

import Foundation

/// A percentile fit of a value set: padded [lo, hi] plus the fraction of the
/// *full* plotted set that falls outside it.
struct EffortFit: Equatable {
    let lo: Double
    let hi: Double
    let clip: Double
}

/// Requested scale behaviour — the `scaleMode` prop. `work` is the default and
/// may resolve to WORK or SPLIT (or fall back to WINDOW) depending on the data.
enum EffortScaleRequest: Equatable { case work, window, fixed }

/// The resolved scale mode, surfaced in the header readout.
enum EffortScaleModeResolved: String, Equatable {
    case window = "WINDOW"
    case work = "WORK"
    case split = "SPLIT"
    case fixed = "FIXED"
    case anchored = "ZONE"     // stable, zone-anchored bounds (comparable across runs)
}

/// A resolved y-axis for one metric over one window. `normalized(_:)` is the
/// single mapping the view and the ticks both go through, so they can never
/// disagree about where a value sits.
struct EffortScale {
    let metric: EffortMetric
    let mode: EffortScaleModeResolved

    /// Linear domain for WINDOW / WORK / FIXED. For SPLIT this is the work band
    /// [repLo, repHi] (used for tick generation + the header readout).
    let lo: Double
    let hi: Double

    /// SPLIT geometry (nil in linear modes).
    let split: SplitGeometry?

    /// Header readout, e.g. "WORK SCALE 5:52–6:14". The design's honesty line.
    let readout: String
    /// Optional compression/pin note, e.g. "JOG COMPRESSED BEYOND 7:36".
    let note: String?

    struct SplitGeometry: Equatable {
        let gl: Double      // global low (outer)
        let gh: Double      // global high (outer)
        let repLo: Double   // work band low
        let repHi: Double   // work band high
        let fLo: Double     // fraction of height given to the low compressed band
        let fHi: Double     // fraction of height given to the high compressed band
    }

    /// Value → fraction from the plot BOTTOM (0) to TOP (1), with pace inversion
    /// already applied. The view draws `y = plotRect.maxY - normalized(v) * h`.
    func normalized(_ value: Double) -> Double {
        let pos = position(value)                    // value-space 0…1, lo→hi
        let frac = metric.invertedAxis ? (1 - pos) : pos
        return min(max(frac, 0), 1)
    }

    /// True when a value sits outside the linear WORK/WINDOW domain and must be
    /// pinned to the frame edge rather than flatlined against it.
    func isOutOfDomain(_ value: Double) -> Bool {
        guard split == nil else { return false }     // SPLIT compresses, never pins
        return value < lo || value > hi
    }

    // Value-space position (0 at domain low, 1 at domain high), pre-inversion.
    private func position(_ value: Double) -> Double {
        if let s = split {
            if value <= s.repLo {
                let denom = s.repLo - s.gl
                let p = denom > 0 ? s.fLo * (value - s.gl) / denom : 0
                return min(max(p, 0), s.fLo)
            } else if value <= s.repHi {
                let denom = s.repHi - s.repLo
                let mid = 1 - s.fHi - s.fLo
                let p = denom > 0 ? s.fLo + mid * (value - s.repLo) / denom : s.fLo
                return p
            } else {
                let denom = s.gh - s.repHi
                let p = denom > 0 ? (1 - s.fHi) + s.fHi * (value - s.repHi) / denom : (1 - s.fHi)
                return min(max(p, 1 - s.fHi), 1)
            }
        }
        let denom = hi - lo
        guard denom > 0 else { return 0.5 }
        return min(max((value - lo) / denom, 0), 1)
    }

    // MARK: Ticks

    /// Raw tick values. Linear modes tick across [lo, hi]; SPLIT ticks the work
    /// band and adds one label for each compressed outer edge that exists.
    func ticks() -> [Double] {
        if let s = split {
            var out = Self.linearTicks(d0: s.repLo, d1: s.repHi, metric: metric)
            if s.fLo > 0 { out.insert(s.gl, at: 0) }
            if s.fHi > 0 { out.append(s.gh) }
            return out
        }
        return Self.linearTicks(d0: lo, d1: hi, metric: metric)
    }

    private static func linearTicks(d0: Double, d1: Double, metric: EffortMetric) -> [Double] {
        let span = d1 - d0
        guard span > 0 else { return [] }
        let step = metric.tickSteps.first { span / $0 <= 5 } ?? metric.tickSteps.last!
        let start = (ceil((d0 + span * 0.06) / step) * step)
        let end = d1 - span * 0.04
        var out: [Double] = []
        var v = start
        // Guard against pathological steps producing a runaway loop.
        var guardCount = 0
        while v <= end + 1e-9 && guardCount < 64 {
            out.append(v)
            v += step
            guardCount += 1
        }
        return out
    }
}

enum EffortChartScale {

    // MARK: percentile + fit

    /// Linear-interpolated percentile. `p` in 0…100.
    static func percentile(_ values: [Double], _ p: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        if values.count == 1 { return values[0] }
        let sorted = values.sorted()
        let rank = (p / 100) * Double(sorted.count - 1)
        let lo = Int(rank.rounded(.down))
        let hi = Int(rank.rounded(.up))
        let frac = rank - Double(lo)
        return sorted[lo] + (sorted[hi] - sorted[lo]) * frac
    }

    /// §"Helper — fit(values)". `fitValues` set the padded p2–p98 band; `clip`
    /// is measured over `allValues` (the full plotted set).
    static func fit(_ fitValues: [Double], allValues: [Double], metric: EffortMetric) -> EffortFit {
        guard !fitValues.isEmpty else {
            let d = metric.fallbackDomain
            return EffortFit(lo: d.lowerBound, hi: d.upperBound, clip: 0)
        }
        var lo = percentile(fitValues, 2)
        var hi = percentile(fitValues, 98)
        var pad = (hi - lo) * 0.18
        if pad == 0 { pad = 4 }
        lo -= pad; hi += pad
        let minSpan = metric.minSpan
        if hi - lo < minSpan {
            let c = (lo + hi) / 2
            lo = c - minSpan / 2
            hi = c + minSpan / 2
        }
        let all = allValues.isEmpty ? fitValues : allValues
        let outside = all.reduce(0) { $0 + (($1 < lo || $1 > hi) ? 1 : 0) }
        let clip = Double(outside) / Double(all.count)
        return EffortFit(lo: lo, hi: hi, clip: clip)
    }

    // MARK: mode resolution

    /// Resolve the y-axis for `metric` over the given resampled `points` and
    /// segment layer. `points` must already be windowed + resampled.
    static func resolve(
        points: [EffortPoint],
        segments: [EffortSegment],
        metric: EffortMetric,
        request: EffortScaleRequest,
        fixedDomain: ClosedRange<Double>? = nil
    ) -> EffortScale {
        let allValues = points.map(\.value)

        // ZONE-ANCHORED → stable bounds supplied by the caller (pace, from the
        // athlete's zones). Same axis every run, so runs are comparable; values
        // outside pin to the edge and are marked, never silently flattened.
        if let fd = fixedDomain {
            let readout = "\(EffortScaleModeResolved.anchored.rawValue) SCALE "
                + "\(metric.format(fd.lowerBound))\u{2013}\(metric.format(fd.upperBound))"
            return EffortScale(metric: metric, mode: .anchored,
                               lo: fd.lowerBound, hi: fd.upperBound,
                               split: nil, readout: readout, note: nil)
        }

        // FIXED → the metric's fallback domain, linear.
        if request == .fixed {
            let d = metric.fallbackDomain
            return linear(metric: metric, mode: .fixed, lo: d.lowerBound, hi: d.upperBound, note: nil)
        }

        // WINDOW is requested explicitly, or is the fallback for the work branch.
        func windowScale() -> EffortScale {
            // Pace: scale to the MOVING band, not the extremes. A walk / standing
            // rest sends GPS pace toward the 900 s clamp; letting that set the
            // axis crushes the running paces into a sliver at the top (the exact
            // bug the Strava-style chart avoids). So fit the moving samples only
            // and let anything slower pin to the bottom edge (normalized clamps).
            if metric == .pace {
                let moving = allValues.filter { $0 > 150 && $0 < 715 }
                if moving.count > 5 {
                    let s = moving.sorted()
                    let fast = s.first!
                    let slowIdx = min(Int(Double(s.count - 1) * 0.90), s.count - 1)
                    let slow = s[slowIdx]
                    let lo = fast - 15
                    let hi = max(slow, fast + 45) + 15
                    return linear(metric: metric, mode: .window, lo: lo, hi: hi, note: nil)
                }
            }
            let f = fit(allValues, allValues: allValues, metric: metric)
            return linear(metric: metric, mode: .window, lo: f.lo, hi: f.hi, note: nil)
        }

        guard request == .work, !allValues.isEmpty else { return windowScale() }

        let share = EffortSeries.workShare(points: points, segments: segments)
        guard share > 0.35, share < 0.98, metric != .elev else { return windowScale() }

        let repVals = EffortSeries.repValues(points: points, segments: segments)
        guard !repVals.isEmpty else { return windowScale() }

        let rf = fit(repVals, allValues: allValues, metric: metric)

        if rf.clip <= 0.11 {
            // WORK — linear on the rep fit; out-of-domain points get pinned.
            var note: String? = nil
            if rf.clip > 0.03 {
                if metric.invertedAxis {
                    note = "SLOWER THAN \(metric.format(rf.hi)) PINNED"
                } else {
                    note = "\(Int((rf.clip * 100).rounded()))% PINNED"
                }
            }
            return linear(metric: metric, mode: .work, lo: rf.lo, hi: rf.hi, note: note)
        }

        // SPLIT — piecewise axis in three bands; compression is drawn + noted.
        let gl = min(allValues.min() ?? rf.lo, rf.lo)
        let gh = max(allValues.max() ?? rf.hi, rf.hi)
        let shareLo = Double(allValues.reduce(0) { $0 + ($1 < rf.lo ? 1 : 0) }) / Double(allValues.count)
        let shareHi = Double(allValues.reduce(0) { $0 + ($1 > rf.hi ? 1 : 0) }) / Double(allValues.count)
        let fLo = shareLo == 0 ? 0 : min(max(shareLo * 1.6, 0.06), 0.24)
        let fHi = shareHi == 0 ? 0 : min(max(shareHi * 1.6, 0.06), 0.24)
        let geo = EffortScale.SplitGeometry(gl: gl, gh: gh, repLo: rf.lo, repHi: rf.hi, fLo: fLo, fHi: fHi)

        let note: String = metric.invertedAxis
            ? "JOG COMPRESSED BEYOND \(metric.format(rf.hi))"
            : "COMPRESSED OUTSIDE \(metric.format(rf.lo))\u{2013}\(metric.format(rf.hi))"

        let readout = "\(EffortScaleModeResolved.split.rawValue) SCALE "
            + "\(metric.format(rf.lo))\u{2013}\(metric.format(rf.hi))"
        return EffortScale(metric: metric, mode: .split, lo: rf.lo, hi: rf.hi,
                           split: geo, readout: readout, note: note)
    }

    private static func linear(
        metric: EffortMetric, mode: EffortScaleModeResolved,
        lo: Double, hi: Double, note: String?
    ) -> EffortScale {
        let readout = "\(mode.rawValue) SCALE \(metric.format(lo))\u{2013}\(metric.format(hi))"
        return EffortScale(metric: metric, mode: mode, lo: lo, hi: hi,
                           split: nil, readout: readout, note: note)
    }

    // MARK: pinned runs (§3)

    /// Index ranges of consecutive points whose value sits outside the WORK
    /// domain — the view draws a dashed edge marker across each instead of
    /// letting the trace flatline against the frame.
    static func pinnedRuns(points: [EffortPoint], scale: EffortScale) -> [ClosedRange<Int>] {
        guard scale.split == nil else { return [] }
        var runs: [ClosedRange<Int>] = []
        var start: Int? = nil
        for (i, p) in points.enumerated() {
            if scale.isOutOfDomain(p.value) {
                if start == nil { start = i }
            } else if let s = start {
                runs.append(s...(i - 1)); start = nil
            }
        }
        if let s = start { runs.append(s...(points.count - 1)) }
        return runs
    }
}

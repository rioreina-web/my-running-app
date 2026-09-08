//
//  EffortMetric.swift
//  RunningLog
//
//  "The Effort" chart — pure model layer (no SwiftUI, no app types).
//
//  This is the SwiftUI-free core of the workout-detail effort chart redesign
//  (design handoff "The Effort", 2026-08-20). Everything here is Foundation-only
//  so the autoscale/series math in EffortSeries.swift + EffortChartScale.swift is
//  unit-testable without a simulator. The view layer maps `EffortMetric` → a
//  `Color.drip.*` token; color deliberately does NOT live here.
//
//  Data model mirrors the handoff §"Data model" 1:1.
//

import Foundation

/// One flattened sample of the workout stream. Distances are cumulative miles,
/// pace is seconds-per-mile, elevation is feet — the adapter from
/// `VitalWorkoutStream` (meters, m/s) does the unit conversion before the chart
/// ever sees a value.
struct EffortSample: Equatable {
    let t: TimeInterval          // seconds from workout start
    let distanceMiles: Double    // cumulative
    let hr: Double               // bpm
    let paceSecPerMile: Double   // seconds per mile
    let cadenceSPM: Double
    let elevationFt: Double
}

/// A structured-session segment. Reps/floats/WU/CD come from real data
/// (`running_workout_laps.is_rest` + `parsed_structure.blocks` via
/// `WorkoutLapsService`), never inferred from pace on-device.
enum EffortSegmentKind: Equatable {
    case warmup, rep, float, cooldown
}

struct EffortSegment: Equatable {
    let kind: EffortSegmentKind
    let label: String            // "R1"… for reps, "WU", "CD", "FLOAT"
    let t0: TimeInterval
    let t1: TimeInterval
    /// True when this segment was inferred from the pace trace rather than read
    /// from real lap data — the chart surfaces that so an inferred read is never
    /// passed off as measured structure.
    var inferred: Bool = false

    var isRep: Bool { kind == .rep }
    func contains(_ time: TimeInterval) -> Bool { time >= t0 && time < t1 }
}

/// The four plottable metrics. Config (axis label, unit, fallback domain,
/// direction, tick candidates, minimum span) is lifted verbatim from the
/// handoff's metric table. Color is intentionally absent — it is a view concern.
enum EffortMetric: String, CaseIterable, Equatable {
    case hr, pace, cad, elev

    /// Metric-pill / header label.
    var label: String {
        switch self {
        case .hr:   return "HEART RATE"
        case .pace: return "PACE"
        case .cad:  return "CADENCE"
        case .elev: return "ELEVATION"
        }
    }

    /// Axis unit caption above the top-left gridline, e.g. "HR · BPM".
    var axisCaption: String {
        switch self {
        case .hr:   return "HR · BPM"
        case .pace: return "PACE · /MI"
        case .cad:  return "CAD · SPM"
        case .elev: return "ELEV · FT"
        }
    }

    /// Short unit shown beside a readout value.
    var unit: String {
        switch self {
        case .hr:   return "BPM"
        case .pace: return "/ MI"
        case .cad:  return "SPM"
        case .elev: return "FT"
        }
    }

    /// Domain used in `fixed` scale mode and as a last-resort when a window has
    /// no spread. Pace is stored in seconds (335–600 s ≈ 5:35–10:00).
    var fallbackDomain: ClosedRange<Double> {
        switch self {
        case .hr:   return 104...174
        case .pace: return 335...600
        case .cad:  return 152...196
        case .elev: return 18...108
        }
    }

    /// True when a *lower* raw value should plot *higher* on screen. Only pace
    /// (a faster pace is a smaller number and belongs at the top).
    var invertedAxis: Bool { self == .pace }

    /// Header peak-stat caption. Pace's peak is its best (fastest) sample.
    var peakLabel: String { invertedAxis ? "BEST" : "MAX" }

    /// Minimum axis span in raw units — a window this flat still gets breathing
    /// room rather than collapsing onto the trace.
    var minSpan: Double {
        switch self {
        case .hr:   return 16
        case .pace: return 40
        case .cad:  return 14
        case .elev: return 24
        }
    }

    /// Candidate tick steps (raw units). The first where `span / step <= 5` wins.
    var tickSteps: [Double] {
        switch self {
        case .hr:   return [5, 10, 20, 25]
        case .pace: return [10, 15, 30, 60, 120]
        case .cad:  return [2, 5, 10, 20]
        case .elev: return [10, 20, 50, 100]
        }
    }

    /// Pull this metric's raw value out of a sample.
    func value(of s: EffortSample) -> Double {
        switch self {
        case .hr:   return s.hr
        case .pace: return s.paceSecPerMile
        case .cad:  return s.cadenceSPM
        case .elev: return s.elevationFt
        }
    }

    /// The "peak" of a set of raw values in this metric's better direction:
    /// the fastest (min) pace, otherwise the max.
    func peak(of values: [Double]) -> Double? {
        invertedAxis ? values.min() : values.max()
    }

    /// Format a raw value for a tick / readout. Pace is `m:ss`; the rest are
    /// integers. Tabular rendering is the view's job.
    func format(_ v: Double) -> String {
        if invertedAxis { return EffortFormat.pace(v) }
        return String(Int(v.rounded()))
    }
}

/// Pure formatting helpers shared by the engine and the view.
enum EffortFormat {
    /// Seconds-per-mile → `m:ss`. Rounds to the nearest second and carries a
    /// 60 → next-minute boundary (never prints ":60").
    static func pace(_ secPerMile: Double) -> String {
        guard secPerMile.isFinite, secPerMile > 0 else { return "—" }
        var total = Int(secPerMile.rounded())
        var m = total / 60
        let s = total % 60
        if s == 60 { m += 1; total = m * 60 }   // defensive; rounding can't hit this but keep the invariant
        return "\(m):" + String(format: "%02d", total % 60)
    }

    /// Clock label `m:ss` from seconds-from-start.
    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return "\(total / 60):" + String(format: "%02d", total % 60)
    }

    /// Signed delta in whole seconds using a true minus sign, e.g. `−4s` / `+2s`.
    static func deltaSeconds(_ delta: Double) -> String {
        let n = Int(delta.rounded())
        if n == 0 { return "0s" }
        return (n < 0 ? "\u{2212}" : "+") + "\(abs(n))s"
    }
}

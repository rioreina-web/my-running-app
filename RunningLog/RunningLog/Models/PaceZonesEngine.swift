//
//  PaceZonesEngine.swift
//  RunningLog
//
//  Swift Codable mirror of the `get-pace-zones` edge function payload (which
//  in turn is the output of `_shared/pace-engine.ts`). This is what every
//  iOS surface should display when it needs an athlete's pace zones — there
//  is no on-device pace math.
//
//  Field names match the JSON wire format (the engine emits camelCase), so
//  the default JSONDecoder decodes them directly with no keyDecodingStrategy.
//
//  Wire shape and source priority documented in pace-engine.ts.
//

import Foundation

/// Top-level pace zones for an athlete. Mirrors `PaceZones` in pace-engine.ts.
struct PaceZonesEngine: Codable, Equatable {
    // Training-pace ranges (the chart's TRAINING PACES section).
    // Always doctrine-derived (MP × multipliers). Compare with `observedEasy`
    // to see whether the athlete is actually holding easy effort.
    let easy: PaceZoneRange?
    let moderate: PaceZoneRange?
    let steady: PaceZoneRange?

    // Race anchors (the chart's RACE PACES section).
    let marathon: PaceZoneAnchor?
    let halfMarathon: PaceZoneAnchor?
    let tenMile: PaceZoneAnchor?
    let tenK: PaceZoneAnchor?
    let fiveK: PaceZoneAnchor?
    let threeK: PaceZoneAnchor?
    let mile: PaceZoneAnchor?
    let fifteenHundred: PaceZoneAnchor?

    /// Diagnostic snapshot of where the athlete actually ran easy in the
    /// last 90 days. Nil when fewer than ~8 easy sessions are available.
    /// The Easy zone above is NOT derived from this — both are surfaced so
    /// the coach can see the gap between definition and behavior.
    let observedEasy: ObservedEasySnapshot?

    // Diagnostic envelope.
    let athleteUserId: String
    let computedAt: String      // ISO 8601
    let primarySource: String   // "profile" | "race_derived" | "goal_only" | "none"
                                // (legacy "observed" no longer emitted)
}

/// Observed-easy diagnostic. Mirrors `ObservedEasySnapshot` in pace-engine.ts.
struct ObservedEasySnapshot: Codable, Equatable {
    let paceFast: Double        // sec/mi, p25 of recent easy paces
    let paceSlow: Double        // sec/mi, p75
    let sessionCount: Int
    let lookbackDays: Int

    /// Render p25–p75 as a chart-style range, e.g. "6:32 – 7:04 /mi".
    var formatted: String {
        "\(formatPace(paceFast)) – \(formatPace(paceSlow)) /mi"
    }
}

/// Pace range for an effort zone. `openEndedSlow=true` means the slow bound
/// is a sanity rail and the zone should be rendered as "{paceFast}+/mi".
struct PaceZoneRange: Codable, Equatable {
    let paceFast: Double        // sec/mi, fastest in the range
    let paceSlow: Double        // sec/mi, slowest in the range
    let label: String           // e.g. "Easy"
    let effortPercent: String   // e.g. "75% effort or less"
    let openEndedSlow: Bool     // render as "{paceFast}+/mi" when true
    let source: String          // PaceSource string
    let confidence: String      // "high" | "medium" | "low" | "none"

    /// Render the range the way the iOS Pace Chart does:
    ///   open-ended:  "6:18+ /mi"
    ///   closed:      "5:30 – 5:43 /mi"
    var formatted: String {
        if openEndedSlow {
            return "\(formatPace(paceFast))+ /mi"
        }
        return "\(formatPace(paceFast)) – \(formatPace(paceSlow)) /mi"
    }
}

/// Single-anchor race target (no range). `pace` is sec/mi.
struct PaceZoneAnchor: Codable, Equatable {
    let pace: Double            // sec/mi
    let source: String
    let confidence: String

    var formatted: String { "\(formatPace(pace)) /mi" }
}

/// Format M:SS the canonical way: "5:20", "6:18", "10:05".
private func formatPace(_ sec: Double) -> String {
    let total = Int(sec.rounded())
    let m = total / 60
    let s = total % 60
    return String(format: "%d:%02d", m, s)
}

// MARK: - Legacy projection
//
// Single-number anchors used by surfaces (e.g. TrainingPlanView pace strip)
// that haven't migrated to range rendering. Mirrors `projectToLegacyZones`
// in pace-engine.ts: easy/moderate/steady = band midpoints; threshold =
// 1-hour pace interpolated from 10K and HM anchors.
extension PaceZonesEngine {
    /// Midpoint of the easy band (~75% MP), or nil if no easy zone derived.
    var easyMidpoint: Double? {
        guard let e = easy else { return nil }
        return (e.paceFast + e.paceSlow) / 2
    }

    /// Midpoint of the moderate band (~85% MP).
    var moderateMidpoint: Double? {
        guard let m = moderate else { return nil }
        return (m.paceFast + m.paceSlow) / 2
    }

    /// Midpoint of the steady band (~95% MP).
    var steadyMidpoint: Double? {
        guard let s = steady else { return nil }
        return (s.paceFast + s.paceSlow) / 2
    }

    /// Threshold (LT) pace, interpolated from 10K and HM anchors. Returns
    /// nil when neither anchor is available.
    var thresholdPace: Double? {
        if let tk = tenK?.pace, let hm = halfMarathon?.pace {
            let d10K = 6.21371192
            let dHM  = 13.10937544
            let t10K = tk * d10K
            let tHM  = hm * dHM
            let target = 3600.0
            if t10K >= target { return tk }
            if tHM <= target { return hm }
            let fraction = (target - t10K) / (tHM - t10K)
            let distInOneHour = d10K + fraction * (dHM - d10K)
            return target / distInOneHour
        }
        return halfMarathon?.pace ?? tenK?.pace
    }
}

//
//  FastSegmentModels.swift
//  RunningLog
//
//  The system-aware layer for the Key Sessions surface. Where `KeySession`
//  (TrendsModels.swift) plots ONE work-bout pace per session, this models the
//  question a coach actually asks of the fast stuff: *is each system getting
//  sharper, and getting enough volume — judged by that system's own yardstick?*
//
//  WHY "SYSTEM" MATTERS (decision 2026-07-17, Rio)
//  ----------------------------------------------
//  MP, HMP, LT, 10K, 5K, 3K and mile pace train different systems, and a good
//  session of each carries a DIFFERENT amount of work. A 1.5-mile mile-rep day
//  and a 12-mile MP day are both complete — they must never share a volume
//  axis. And a single session can MIX systems (a ladder: 1200 @ 10K, 800 @ 5K,
//  400 @ mile), so its work flows into each system's trend separately.
//
//  Source of truth is the tested backend module
//  `supabase/functions/_shared/fast-segment-trends.ts` (per-system detection,
//  quality/heat reuse, expected-volume ranges). This file mirrors its output
//  shape; V1 ships `FastSegmentSampleData` so the surface is reviewable, real
//  wiring is a follow-up (trends-timeline → quality_sessions[] + laps).
//

import SwiftUI

// MARK: - System

/// A fast (MP-and-faster) pace system. Tokens match `KeyZone` so the chip row,
/// spectrum color and labels stay consistent with the existing surface. The
/// backend keeps LT distinct; at the surface it folds into HMP (the honest
/// label given the current zone table — see `KeySession.zone`).
enum FastSystem: String, CaseIterable, Identifiable {
    case mp, hmp
    case tenK = "10k"
    case fiveK = "5k"
    case threeK = "3k"
    case mile

    var id: String { rawValue }
    var label: String { KeyZone.label(rawValue) }

    /// Fast → slow ordering for chips/legends (mirrors `KeyZone.order`).
    static let displayOrder: [FastSystem] = [.mile, .threeK, .fiveK, .tenK, .hmp, .mp]

    /// Expected WORK volume (miles at pace) for a well-run single session.
    /// Rio's coaching guidance, 2026-07-17. Tunable — a read, not a limit.
    var expectedMiles: ClosedRange<Double> {
        switch self {
        case .mp: 7...15
        case .hmp: 5...9
        case .tenK: 4...7
        case .fiveK: 3...4
        case .threeK: 2...3
        case .mile: 1...2
        }
    }

    /// Position on the pace ramp (PaceSpectrum), fast systems deeper navy.
    var spectrumColor: Color {
        switch self {
        case .mp: PaceSpectrum.mp
        case .hmp: PaceSpectrum.hmp
        case .tenK: PaceSpectrum.tenK
        case .fiveK: PaceSpectrum.fiveK
        case .threeK: PaceSpectrum.threeK
        case .mile: PaceSpectrum.mile
        }
    }
}

// MARK: - Volume read

/// Where a session's work volume for a system sits vs. that system's range.
enum VolumeStatus {
    case below, inRange, above

    var label: String {
        switch self {
        case .below: "Under range"
        case .inRange: "In range"
        case .above: "Over range"
        }
    }

    /// Coral only flags genuinely out-of-range work; in-range stays neutral ink
    /// (coral is the alert color, never decoration — three-palette rule).
    var accent: Color {
        switch self {
        case .inRange: Color.drip.textSecondary
        case .below, .above: Color.drip.coral
        }
    }
}

// MARK: - Per-system slice of a session

struct FastSystemVolume: Identifiable {
    var id: String { system.rawValue }
    let system: FastSystem
    let reps: Int
    let workMiles: Double
    /// Raw work pace, sec/mile.
    let avgPaceSec: Int
    /// Heat-adjusted cool-weather-equivalent pace (faster); nil when conditions
    /// were ideal or no weather was recorded.
    let neutralPaceSec: Int?
    let avgHr: Int?
    /// Conditions-adjusted (cool + flat) pace — heat AND grade removed. nil →
    /// falls back to heat-only, then raw.
    var conditionsPaceSec: Int? = nil

    var status: VolumeStatus {
        if workMiles < system.expectedMiles.lowerBound { return .below }
        if workMiles > system.expectedMiles.upperBound { return .above }
        return .inRange
    }
    /// The pace the dot is read at: conditions-adjusted (heat + grade) when
    /// available, then heat-only, else raw.
    var effectivePaceSec: Int { conditionsPaceSec ?? neutralPaceSec ?? avgPaceSec }
}

// MARK: - Session

struct FastSession: Identifiable {
    let id: String
    let date: String        // "2026-07-14"
    let dateLabel: String   // "Jul 14"
    let name: String
    let repCount: Int
    let fastMiles: Double
    let avgPaceSec: Int
    let neutralPaceSec: Int?
    let avgHr: Int?
    /// Fast time / (fast + rest) time, percent — how packed the session was.
    let densityPct: Int
    let avgRestSec: Int
    /// Meters covered per heartbeat across the fast reps (fitness signal).
    let metersPerBeat: Double?
    let feelsF: Int?
    /// Per-system breakdown; count > 1 when the session mixed systems.
    let bySystem: [FastSystemVolume]
    /// Conditions-adjusted (cool + flat) session pace; nil → falls back to heat.
    var conditionsPaceSec: Int? = nil
    /// Distance-weighted average grade (%). nil on flat / unknown terrain.
    var avgGradePct: Double? = nil
    /// Whole-run distance (miles) — fast work in context.
    var totalMiles: Double? = nil
    // ── Compare-surface metrics (all optional; older payloads omit them) ──
    /// Grade-only flat-equivalent pace (heat kept). nil on flat terrain.
    var flatPaceSec: Int? = nil
    /// HR drift across the set (last rep − rep 2, bpm). nil for short reps.
    var hrDriftBpm: Double? = nil
    /// Mean HR drop into the recoveries (bpm). Bigger = recovering faster.
    var recoveryDropBpm: Double? = nil
    /// Aerobic decoupling (% efficiency lost) — continuous efforts only.
    var decouplingPct: Double? = nil
    /// Average rep / bout length in meters. A continuous effort is one long bout.
    var avgRepM: Int? = nil

    /// Dominant system by work volume — the headline label.
    var primarySystem: FastSystem? {
        bySystem.max(by: { $0.workMiles < $1.workMiles })?.system
    }

    /// A continuous effort (tempo, threshold, steady, long) rather than reps:
    /// one bout, so the rep-only rows (rep length, density, rest, recovery)
    /// don't apply. Rep sessions have ≥ 2 bouts.
    var isContinuous: Bool { repCount <= 1 }

    /// Heat cost (s/mi the heat gave back) — derived: raw − heat-adjusted.
    var heatCostSec: Int? {
        guard let n = neutralPaceSec else { return nil }
        let d = avgPaceSec - n
        return d > 0 ? d : nil
    }
    /// Hill cost (s/mi the grade gave back) — derived: raw − grade-adjusted.
    var hillCostSec: Int? {
        guard let f = flatPaceSec else { return nil }
        let d = avgPaceSec - f
        return d > 0 ? d : nil
    }

    /// Pace under the athlete's adjustment toggles, with honest fallbacks.
    func pace(heat: Bool, hills: Bool) -> Int {
        switch (heat, hills) {
        case (true, true): return conditionsPaceSec ?? neutralPaceSec ?? flatPaceSec ?? avgPaceSec
        case (true, false): return neutralPaceSec ?? avgPaceSec
        case (false, true): return flatPaceSec ?? avgPaceSec
        case (false, false): return avgPaceSec
        }
    }
}

// MARK: - Per-system trend

/// One system's like-for-like trend: every session that hit this system, in
/// order. A mixed session appears in several of these.
struct FastSystemTrend: Identifiable {
    var id: String { system.rawValue }
    let system: FastSystem
    let points: [FastSystemTrendPoint]   // chronological
}

struct FastSystemTrendPoint: Identifiable {
    let id: String          // sessionId
    let dateLabel: String
    let sessionName: String?
    let reps: Int
    let workMiles: Double    // fast work in this system
    let totalMiles: Double?  // whole run
    let avgPaceSec: Int
    let neutralPaceSec: Int?
    let conditionsPaceSec: Int?
    let avgHr: Int?
    let status: VolumeStatus
    var effectivePaceSec: Int { conditionsPaceSec ?? neutralPaceSec ?? avgPaceSec }

    /// Pace under the athlete's adjustment toggles, mirroring `FastSession.pace`
    /// with the fields a trend point carries. There's no grade-only pace here,
    /// so hills-alone has no dedicated value and honestly falls back to raw.
    func pace(heat: Bool, hills: Bool) -> Int {
        switch (heat, hills) {
        case (true, true): return conditionsPaceSec ?? neutralPaceSec ?? avgPaceSec
        case (true, false): return neutralPaceSec ?? avgPaceSec
        case (false, true): return avgPaceSec
        case (false, false): return avgPaceSec
        }
    }
}

// MARK: - Sample data (V1 — real wiring is a follow-up)

/// Rio's real May–July key sessions, reduced to the system-aware shape the
/// surface renders. Mirrors the numbers the backend module + tests produce.
enum FastSegmentSampleData {

    static let sessions: [FastSession] = [
        FastSession(
            id: "s_may20", date: "2026-05-20", dateLabel: "May 20", name: "10 × 1K",
            repCount: 10, fastMiles: 6.2, avgPaceSec: 308, neutralPaceSec: 303, avgHr: 168,
            densityPct: 72, avgRestSec: 85, metersPerBeat: 1.87, feelsF: 74,
            bySystem: [
                FastSystemVolume(system: .fiveK, reps: 10, workMiles: 6.2, avgPaceSec: 308, neutralPaceSec: 303, avgHr: 168)
            ]),
        FastSession(
            id: "s_jun23", date: "2026-06-23", dateLabel: "Jun 23", name: "Mile / 1K / 600 set",
            repCount: 9, fastMiles: 4.85, avgPaceSec: 315, neutralPaceSec: 308, avgHr: 163,
            densityPct: 62, avgRestSec: 119, metersPerBeat: 1.88, feelsF: 78,
            bySystem: [
                FastSystemVolume(system: .fiveK, reps: 6, workMiles: 3.7, avgPaceSec: 318, neutralPaceSec: 311, avgHr: 162),
                FastSystemVolume(system: .threeK, reps: 3, workMiles: 1.15, avgPaceSec: 305, neutralPaceSec: 299, avgHr: 168)
            ]),
        FastSession(
            id: "s_jul08", date: "2026-07-08", dateLabel: "Jul 8", name: "8×1K + 2×800",
            repCount: 10, fastMiles: 6.0, avgPaceSec: 315, neutralPaceSec: 305, avgHr: 166,
            densityPct: 76, avgRestSec: 66, metersPerBeat: 1.85, feelsF: 84,
            bySystem: [
                FastSystemVolume(system: .fiveK, reps: 10, workMiles: 6.0, avgPaceSec: 315, neutralPaceSec: 305, avgHr: 166)
            ]),
        FastSession(
            id: "s_jul14", date: "2026-07-14", dateLabel: "Jul 14", name: "(1200/800/400) × 3",
            repCount: 9, fastMiles: 4.5, avgPaceSec: 301, neutralPaceSec: 289, avgHr: 170,
            densityPct: 66, avgRestSec: 85, metersPerBeat: 1.89, feelsF: 85,
            bySystem: [
                FastSystemVolume(system: .tenK, reps: 3, workMiles: 2.24, avgPaceSec: 305, neutralPaceSec: 293, avgHr: 172),
                FastSystemVolume(system: .fiveK, reps: 3, workMiles: 1.50, avgPaceSec: 300, neutralPaceSec: 288, avgHr: 171),
                FastSystemVolume(system: .mile, reps: 3, workMiles: 0.75, avgPaceSec: 293, neutralPaceSec: 281, avgHr: 168)
            ])
    ]

    /// Group the sessions into per-system trends (a mixed session lands in each
    /// system it touched), fast → slow, matching the backend grouping.
    static func systemTrends() -> [FastSystemTrend] {
        var buckets: [FastSystem: [FastSystemTrendPoint]] = [:]
        for s in sessions {
            for sv in s.bySystem {
                buckets[sv.system, default: []].append(
                    FastSystemTrendPoint(
                        id: s.id, dateLabel: s.dateLabel, sessionName: s.name, reps: sv.reps,
                        workMiles: sv.workMiles, totalMiles: s.totalMiles,
                        avgPaceSec: sv.avgPaceSec, neutralPaceSec: sv.neutralPaceSec,
                        conditionsPaceSec: sv.conditionsPaceSec, avgHr: sv.avgHr, status: sv.status))
            }
        }
        return FastSystem.displayOrder.compactMap { sys in
            guard let pts = buckets[sys], !pts.isEmpty else { return nil }
            return FastSystemTrend(system: sys, points: pts)
        }
    }
}

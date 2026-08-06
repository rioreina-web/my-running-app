//
//  TrendsRecoveryDemand.swift
//  RunningLog · Trends
//
//  The DEMAND half of the recovery-need model
//  (`outputs/recovery-need-model-2026-08-06.md` §2): how big a recovery hole
//  training just dug. Pure load math, no watch required.
//
//  ── Why this exists, in one paragraph ─────────────────────────────────────
//
//  The score used to read load through two overlapping mileage ratios
//  (`recentLoad` — 3 days decayed vs an 8-week mean; `loadVsBaseline` — 7 days
//  vs the same 8-week mean). Both answered "is this week bigger than usual"
//  with different arithmetic, and neither was the validated framework. This
//  replaces both with one Banister fitness–fatigue balance — the one readiness
//  framework that IS validated in endurance sport — expressed as a normalized
//  DIFFERENCE against the athlete's own chronic load.
//
//  Deliberately a difference, never a ratio: `recovery-trend-v2` §7.1 took the
//  acute:chronic ratio apart (coupling inflation r=0.52 from arithmetic alone,
//  a denominator carrying no signal, the only RCT null, thresholds with no
//  primary source). The normalized difference keeps the intuition — "how far
//  above your usual is this week" — without inheriting those pathologies.
//
//  ── What demand cannot do ─────────────────────────────────────────────────
//
//  It cannot see an injury coming. Proven on Rio's own 202 days: in the week
//  before the July 17 knee episode the need index sat at +1, the 21st
//  percentile of her year. Training math gave no warning at all; her words had
//  been saying *struggling* for six days. So demand is never the lead signal —
//  it is the CONTEXT that tells you what a dragging self-report means. A
//  load-only readiness number (which is essentially what Garmin Training
//  Readiness and TSB are) would have called that week fine.
//
//  That asymmetry is the whole reason the quadrant read exists: see
//  `TrendsRecoveryLedger.Quadrant`.
//

import Foundation

enum TrendsRecoveryDemand {

    // MARK: - Tunables, in one place

    /// Banister time constants. 7 / 42 days are the standard pairing and the
    /// design doc flags them as tunable judgment calls, not evidence.
    static let acuteDays = 7.0
    static let chronicDays = 42.0

    /// Intensity multiplier per session channel. The channel is the only
    /// intensity signal the daily substrate carries — it is NOT a pace zone.
    /// Long runs are aerobic, so they earn a modest bump for accumulated
    /// duration rather than a quality premium.
    ///
    /// These are load multipliers, not paces, so they are legitimately
    /// constants — nothing here hardcodes how fast anyone runs.
    static func intensity(_ channel: TrendsDay.SessionChannel) -> Double {
        switch channel {
        case .rest: 0.0
        case .easy: 1.0
        case .long: 1.1
        case .key:  1.4
        }
    }

    /// Days of history required before the need index is trusted.
    ///
    /// The index over-reads while CTL is still climbing from a cold start —
    /// Rio's March "+89" days are that artifact, not real holes. Below this
    /// the factor reports itself as having no data rather than inventing a
    /// hole out of a short history (design doc §2d, the warm-up gate).
    static let warmUpDays = 42

    /// A single day's running more than this multiple of the longest day in
    /// the prior 30 carries HRR 2.28 (Frandsen 2025, 588k sessions). It rides
    /// alongside the need index as its own contributor rather than being
    /// folded into the EWMA, where a smoother would erase it.
    static let spikeThreshold = 2.0
    static let spikeLookbackDays = 30

    // MARK: - The load unit

    /// Which unit the whole window is measured in.
    ///
    /// Pinned per window, never per day. Mixing units inside one EWMA is the
    /// same class of error as mixing SDNN and RMSSD in one HRV baseline: the
    /// acute window would be denominated differently from the chronic one and
    /// the difference between them would be an artifact of the unit, not of
    /// training. So the ladder picks the highest rung that covers EVERY
    /// running day in the window, and drops a rung otherwise.
    ///
    /// The need index is a normalized difference, so the unit cancels out
    /// entirely — consistency is all that is required of it, not comparability
    /// between athletes.
    enum LoadUnit {
        /// The real per-workout internal load. Preferred, but NULL on every
        /// row until the `20260731120000` backfill runs.
        case stressLoad
        /// duration x intensity — the design doc's fallback form.
        case durationIntensity
        /// miles x intensity. Last resort: an older server deploy sends no
        /// duration at all.
        case milesIntensity
    }

    /// Highest rung of the ladder that covers every running day in `days`.
    static func loadUnit(for days: [TrendsDay]) -> LoadUnit {
        let runDays = days.filter { $0.miles > 0 }
        guard !runDays.isEmpty else { return .milesIntensity }
        if runDays.allSatisfy({ $0.stressLoad != nil }) { return .stressLoad }
        if runDays.allSatisfy({ ($0.durationMin ?? 0) > 0 }) { return .durationIntensity }
        return .milesIntensity
    }

    /// One day's training load in the pinned unit. A rest day is 0 — a real
    /// zero, not missing data.
    static func sessionLoad(_ day: TrendsDay, unit: LoadUnit) -> Double {
        switch unit {
        case .stressLoad:
            return day.stressLoad ?? 0
        case .durationIntensity:
            return Double(day.durationMin ?? 0) * intensity(day.type)
        case .milesIntensity:
            return day.miles * intensity(day.type)
        }
    }

    // MARK: - The balance

    struct Balance {
        /// 7-day exponentially-weighted mean — acute, "fatigue".
        let acute: Double
        /// 42-day exponentially-weighted mean — chronic, "fitness".
        let chronic: Double
        /// `100 * (acute - chronic) / chronic`. Positive is a hole.
        /// `nil` when the warm-up gate is closed or chronic load is zero —
        /// absent, never faked to 0 (which would read as "balanced").
        let needIndex: Double?
        /// Days of history the EWMAs actually ran over.
        let historyDays: Int
    }

    /// Banister EWMAs evaluated at day `i`, walked forward from day 0.
    static func balance(days: [TrendsDay], at i: Int) -> Balance {
        guard days.indices.contains(i) else {
            return Balance(acute: 0, chronic: 0, needIndex: nil, historyDays: 0)
        }
        let unit = loadUnit(for: days)
        // Standard exponential smoothing: today = yesterday + (load - yesterday) * alpha.
        let acuteAlpha = 1 - exp(-1 / acuteDays)
        let chronicAlpha = 1 - exp(-1 / chronicDays)

        // BOTH series are seeded with the same mean, and this is load-bearing.
        //
        // Starting both at 0 looks harmless and is not: the 7-day mean
        // converges in about a fortnight while the 42-day mean takes a
        // quarter, so for months the acute term sits above the chronic one for
        // no reason but arithmetic. On a PERFECTLY FLAT 90-day block that bias
        // reads +13% — a permanent phantom hole — and at the six-week gate it
        // reads +58%. That is the artifact the design doc saw as Rio's March
        // "+89" days and tried to fix with the warm-up gate; a gate cannot fix
        // it, because the bias decays over a quarter, not six weeks.
        //
        // Seeding both from the window's own mean removes it at the source: a
        // flat series now yields exactly 0 at every index, and the gate goes
        // back to meaning what it says — "not enough history yet".
        let seedCount = min(days.count, Int(chronicDays))
        let seed = seedCount > 0
            ? (0..<seedCount).reduce(0.0) { $0 + sessionLoad(days[$1], unit: unit) } / Double(seedCount)
            : 0

        var acute = seed
        var chronic = seed
        for idx in 0...i {
            let load = sessionLoad(days[idx], unit: unit)
            acute += (load - acute) * acuteAlpha
            chronic += (load - chronic) * chronicAlpha
        }

        let historyDays = i + 1
        // The warm-up gate. Withheld, not zeroed.
        guard historyDays >= warmUpDays, chronic > 0.0001 else {
            return Balance(acute: acute, chronic: chronic, needIndex: nil, historyDays: historyDays)
        }
        return Balance(
            acute: acute,
            chronic: chronic,
            needIndex: 100 * (acute - chronic) / chronic,
            historyDays: historyDays
        )
    }

    // MARK: - The session spike

    /// The multiple of the athlete's own recent maximum that day `i`
    /// represents, or nil when there is no comparison to make.
    ///
    /// **Honest limitation:** the evidence is session-level ("a single run
    /// >100% longer than the longest run in the prior 30 days") and the daily
    /// substrate only carries per-DAY totals, doubles already summed. So a
    /// double day can present as a spike when neither run was one. It is
    /// reported as a day, and the evidence line says "day" rather than "run"
    /// so the receipt never overstates what was measured.
    static func spikeMultiple(days: [TrendsDay], at i: Int) -> Double? {
        guard days.indices.contains(i), days[i].miles > 0 else { return nil }
        let start = max(0, i - spikeLookbackDays)
        guard start < i else { return nil }
        let priorMax = days[start..<i].map(\.miles).max() ?? 0
        guard priorMax > 0 else { return nil }
        return days[i].miles / priorMax
    }

    // MARK: - Reading the two terms

    enum Level { case high, low, unknown }

    /// Demand is "high" once the acute load sits meaningfully above the
    /// athlete's own chronic, or the day itself was a spike.
    static let highDemandIndex = 15.0

    static func demandLevel(days: [TrendsDay], at i: Int) -> Level {
        if let multiple = spikeMultiple(days: days, at: i), multiple >= spikeThreshold {
            return .high
        }
        guard let index = balance(days: days, at: i).needIndex else { return .unknown }
        return index >= highDemandIndex ? .high : .low
    }
}

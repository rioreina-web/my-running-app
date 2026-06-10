//
//  PaceModels.swift
//  RunningLog
//
//  Pace and heart-rate zone types: HRTarget, HRZones, PaceIntensity,
//  NamedPace, and EquivalentPaces.
//

import Foundation
import SwiftUI

// MARK: - HR Target

/// Heart rate zone or BPM range target for a workout step
struct HRTarget: Codable, Equatable {
    enum Mode: String, Codable {
        case zone       // Garmin-standard Zone 1–5
        case bpmRange   // Absolute BPM range (e.g., 140–155 bpm)
    }
    var mode: Mode
    var zone: Int?      // 1–5 when mode == .zone
    var bpmLow: Int?    // lower bound when mode == .bpmRange
    var bpmHigh: Int?   // upper bound when mode == .bpmRange
}

// MARK: - HR Zones

/// Standard 5-zone model based on max HR
struct HRZones {
    let maxHR: Int

    var zone1: ClosedRange<Int> { Int(Double(maxHR) * 0.50)...Int(Double(maxHR) * 0.60) }
    var zone2: ClosedRange<Int> { Int(Double(maxHR) * 0.60)...Int(Double(maxHR) * 0.70) }
    var zone3: ClosedRange<Int> { Int(Double(maxHR) * 0.70)...Int(Double(maxHR) * 0.80) }
    var zone4: ClosedRange<Int> { Int(Double(maxHR) * 0.80)...Int(Double(maxHR) * 0.90) }
    var zone5: ClosedRange<Int> { Int(Double(maxHR) * 0.90)...maxHR }

    func range(for zone: Int) -> ClosedRange<Int>? {
        switch zone {
        case 1: return zone1
        case 2: return zone2
        case 3: return zone3
        case 4: return zone4
        case 5: return zone5
        default: return nil
        }
    }

    static let zoneNames = ["Recovery", "Aerobic", "Tempo", "Threshold", "VO2max"]
    static let zoneColors: [Color] = [.blue, .green, .yellow, .orange, .red]
    static let zonePercentRanges = ["50–60%", "60–70%", "70–80%", "80–90%", "90–100%"]
}

// MARK: - Pace Intensity

/// Intensity as percentage of goal race pace
struct PaceIntensity: Codable, Equatable {
    let percentage: Double
    let percentageHigh: Double?
    let paceSecondsPerKm: Double?
    let paceSecondsPerKmHigh: Double?

    init(percentage: Double, percentageHigh: Double? = nil, paceSecondsPerKm: Double? = nil, paceSecondsPerKmHigh: Double? = nil) {
        self.percentage = percentage
        self.percentageHigh = percentageHigh
        self.paceSecondsPerKm = paceSecondsPerKm
        self.paceSecondsPerKmHigh = paceSecondsPerKmHigh
    }


    /// Calculate actual pace in seconds per mile given race pace
    func paceSeconds(forRacePace racePaceSeconds: Double) -> Double {
        racePaceSeconds / (percentage / 100.0)
    }

    /// Format pace string given race pace — supports ranges and km display
    func formattedPace(forRacePace racePaceSeconds: Double) -> String {
        if let paceKm = paceSecondsPerKm {
            let fast = Self.formatTime(paceKm)
            if let slowKm = paceSecondsPerKmHigh {
                return "\(fast)-\(Self.formatTime(slowKm))/km"
            }
            return "\(fast)/km"
        }
        let low = paceSeconds(forRacePace: racePaceSeconds)
        if let highPct = percentageHigh {
            let high = racePaceSeconds / (highPct / 100.0)
            return "\(Self.formatTime(min(low, high)))-\(Self.formatTime(max(low, high)))/mi"
        }
        return "\(Self.formatTime(low))/mi"
    }

    /// Format target time for a distance-based interval rep (e.g., "in 6:12-6:20")
    func formattedTargetTime(forDistance distanceValue: Double, durationType: PlannedWorkoutStep.DurationType) -> String? {
        guard let paceKm = paceSecondsPerKm else { return nil }
        let distanceKm: Double
        switch durationType {
        case .distanceKm: distanceKm = distanceValue
        case .distanceMiles: distanceKm = distanceValue * 1.60934
        case .distanceMeters: distanceKm = distanceValue / 1000
        default: return nil
        }
        let timeFast = distanceKm * paceKm
        if let slowKm = paceSecondsPerKmHigh {
            let timeSlow = distanceKm * slowKm
            return "in \(Self.formatTime(timeFast))-\(Self.formatTime(timeSlow))"
        }
        return "in \(Self.formatTime(timeFast))"
    }

    /// Get a display label using named pace references when available.
    /// Falls back to the formatted pace string — never a percentage.
    func displayLabel(
        forRacePace racePaceSeconds: Double,
        equivalentPaces: EquivalentPaces?
    ) -> String {
        guard racePaceSeconds > 0 else { return "—" }
        let actualPace = paceSeconds(forRacePace: racePaceSeconds)

        if let equiv = equivalentPaces,
           let namedPace = equiv.closestNamedPace(forPaceSeconds: actualPace) {
            return namedPace.shortName
        }

        return formattedPace(forRacePace: racePaceSeconds)
    }

    /// Format seconds as M:SS, or H:MM:SS when total duration >= 1 hour.
    /// Used for both per-unit pace (always sub-hour for running) and
    /// per-workout total time (can exceed an hour for long runs).
    static func formatTime(_ seconds: Double) -> String {
        let totalSecs = Int(seconds.rounded())
        if totalSecs >= 3600 {
            let h = totalSecs / 3600
            let m = (totalSecs % 3600) / 60
            let s = totalSecs % 60
            return "\(h):\(String(format: "%02d", m)):\(String(format: "%02d", s))"
        }
        let mins = totalSecs / 60
        let secs = totalSecs % 60
        return "\(mins):\(String(format: "%02d", secs))"
    }

    /// Build a PaceIntensity from a named race-distance reference ("easy",
    /// "marathon", "half", "10K", "5K", "mile") and an AthletePaceProfile.
    /// Returns nil when the profile doesn't have that pace.
    ///
    /// Resulting PaceIntensity carries `paceSecondsPerKm` so displayers can
    /// render a real m:ss/km string. `percentage` is left at 0 because the
    /// pace is distance-referenced, not percentage-referenced.
    static func forReference(_ reference: String, in profile: AthletePaceProfile?) -> PaceIntensity? {
        guard let seconds = profile?.pace(for: reference)?.secondsPerMile, seconds > 0 else { return nil }
        return PaceIntensity(
            percentage: 0,
            paceSecondsPerKm: seconds / 1.609344
        )
    }

    /// Map a legacy 0-115% target to the closest named race-distance reference.
    /// Mapping per adaptive-plan-loop-prompts.md § 1.10.
    static func referenceName(forPercentage pct: Double) -> String {
        switch pct {
        case ..<85:     return "easy"
        case 85..<92:   return "marathon"
        case 92..<97:   return "half"
        case 97..<102:  return "10K"
        case 102..<105: return "5K"
        default:        return "mile"
        }
    }

    /// Convenience for migrating legacy stub workouts: given a percentage
    /// and the caller's profile, return a concrete PaceIntensity. Falls
    /// back to a percentage-only PaceIntensity when profile is unavailable —
    /// the UI layer renders "—" in that case.
    static func fromLegacyPercentage(_ percentage: Double, profile: AthletePaceProfile?) -> PaceIntensity {
        let ref = referenceName(forPercentage: percentage)
        if let resolved = forReference(ref, in: profile) {
            return resolved
        }
        return PaceIntensity(percentage: percentage)
    }
}

// MARK: - Named Pace Reference

/// Named reference paces derived from a goal race performance
enum NamedPace: String, CaseIterable, Codable {
    case recovery
    case easy
    case longRun
    case moderate   // 75-85% effort
    case steady     // 85-95% effort
    case mp
    case hm
    case threshold
    case tenK
    case fiveK
    case threeK
    case mile

    var displayName: String {
        switch self {
        case .recovery: return "Recovery"
        case .easy: return "Easy"
        case .longRun: return "Long Run"
        case .moderate: return "Moderate"
        case .steady: return "Steady"
        case .mp: return "Marathon Pace"
        case .hm: return "Half Marathon Pace"
        case .threshold: return "Threshold"
        case .tenK: return "10K Pace"
        case .fiveK: return "5K Pace"
        case .threeK: return "3K Pace"
        case .mile: return "Mile Pace"
        }
    }

    var shortName: String {
        switch self {
        case .recovery: return "Rec"
        case .easy: return "Easy"
        case .longRun: return "LR"
        case .moderate: return "Mod"
        case .steady: return "Steady"
        case .mp: return "MP"
        case .hm: return "HM"
        case .threshold: return "LT"
        case .tenK: return "10K"
        case .fiveK: return "5K"
        case .threeK: return "3K"
        case .mile: return "Mile"
        }
    }

    var color: Color {
        switch self {
        case .recovery: return Color.drip.neutral
        case .easy: return Color.drip.positive
        case .longRun: return Color.drip.energized
        case .moderate: return Color.drip.energized.opacity(0.7).mix(with: Color.drip.coral, by: 0.3)
        case .steady: return Color.drip.coralLight
        case .mp: return Color.drip.coral
        case .hm: return Color.drip.coralLight
        case .threshold: return Color.drip.injured
        case .tenK: return Color.drip.tired
        case .fiveK: return Color.drip.struggling
        case .threeK: return Color.drip.speed.opacity(0.85)
        case .mile: return Color.drip.speed
        }
    }

    // MARK: - Pace Range Tolerance & MP-Derived Ranges
    //
    // Two models for rendering a pace *range* instead of a single number:
    //
    // 1. Fast and mid zones — tolerance around the prescribed pace:
    //       Mile / 1500 / 3K / 5K / 10K  → ±1%
    //       HM / MP / Threshold (LT)     → ±2%
    //
    // 2. Slower aerobic zones — derived from marathon pace as a range of
    //    percentages of MP *speed* (NOT of MP seconds). Easy / Moderate /
    //    Steady / LongRun bands match the engine's TRAINING_PACE_MULTIPLIERS
    //    in `_shared/pace-engine.ts` (contiguous, no gaps):
    //       Steady    → 100–90% of MP speed (engine: 1.00–1.10 multiplier)
    //       Moderate  → 90–80% of MP speed  (engine: 1.10–1.20)
    //       Easy      → 80–70% of MP speed  (engine: 1.20–1.30)
    //       Long Run  → 80–70% of MP speed  (= Easy by convention)
    //       Recovery  → 75–65% of MP speed  (slower than easy floor —
    //                                         not modeled in the engine)
    //
    // Pinned to the engine by cross-language-pace-contract.test.ts.
    //
    // Rationale: at fast paces a tight tolerance matters (missing 5K pace by
    // 10s is a huge effort difference). At slow paces, a prescribed single
    // number is fiction — the zone is a range by definition. The MP-derived
    // approach respects that physiology.

    /// Quality zones (Mile through MP) render as a single target pace, not a
    /// range — coach prescription style. Slow aerobic zones still use
    /// `mpSpeedRange` because they're physiologically a range, not a number.
    /// Always nil now; kept on the type so call sites compile.
    var tolerancePercent: Double? { nil }

    /// For slower aerobic zones, the range as **pace multipliers on MP**.
    /// `fast` is the fast end (closer to MP, smaller multiplier); `slow` is
    /// the slow end. Example: steady = (fast: 1.00, slow: 1.10) renders as
    /// MP to MP × 1.10.
    ///
    /// Easy / Moderate / Steady / LongRun bands are IDENTICAL to the engine's
    /// `TRAINING_PACE_MULTIPLIERS` (contiguous: steady.slow == moderate.fast,
    /// moderate.slow == easy.fast). Pinned by cross-language contract test.
    /// Exact multipliers — reciprocals of the speed fraction, contiguous bands.
    /// Mirrors the canonical engine in `supabase/functions/_shared/pace-engine.ts`.
    /// Returns nil for fast/mid zones (they're exact paces, not ranges).
    ///
    /// `longRun` and `threshold` are retained for backwards compatibility with
    /// existing callers (display surfaces use the canonical 10-zone spectrum:
    /// recovery, easy, moderate, steady, MP, HMP, 10K, 5K, 3K, mile).
    var mpPaceMultipliers: (fast: Double, slow: Double)? {
        switch self {
        case .steady:    return (fast: 1.0,    slow: 1.1111) // 90-100% MP speed
        case .moderate:  return (fast: 1.1111, slow: 1.25)   // 80-90% MP speed
        case .easy:      return (fast: 1.25,   slow: 1.4286) // 70-80% MP speed
        case .longRun:   return (fast: 1.25,   slow: 1.4286) // = easy (legacy alias)
        case .recovery:  return (fast: 1.4286, slow: 1.6667) // 60-70% MP speed
        default:         return nil
        }
    }

    /// Runner-to-runner effort description, shown beneath the pace range to
    /// translate coach shorthand ("HM") into feel ("1-hour race effort").
    /// Strings are deliberately short and brand-voice-aligned — no bro-speak,
    /// no methodology name-dropping. See `brand-voice.md` for the full voice.
    var effortDescription: String {
        switch self {
        case .recovery: return "shake-out pace, nothing more"
        case .easy: return "conversational pace"
        case .longRun: return "relaxed, sustained"
        case .moderate: return "comfortable, aerobic"
        case .steady: return "steady effort, just below MP"
        case .mp: return "goal marathon race pace"
        case .hm: return "1-hour race effort"
        case .threshold: return "1-hour race effort"
        case .tenK: return "goal 10K race pace"
        case .fiveK: return "goal 5K race pace"
        case .threeK: return "hard sustained"
        case .mile: return "all-out sustained"
        }
    }

    /// Unified range computation. Picks the right model for this zone:
    ///   - Fast/mid zones → tolerance-based range around `base` (prescribed pace)
    ///   - Slow zones    → MP-derived range, IGNORING `base` (the prescribed
    ///                     single number is fiction at easy/long-run paces;
    ///                     the zone range is the physiological truth)
    ///
    /// Returns (low, high) in seconds/mile where `low < high` (low is faster
    /// pace = fewer seconds). Returns nil when we can't compute — e.g., slow
    /// zone with no marathonPace available, or fast zone with no base.
    ///
    /// - Parameters:
    ///   - base: prescribed pace for this step, in seconds per mile
    ///   - marathonPace: the athlete's marathon pace in seconds per mile
    func displayPaceRange(base: Double?, marathonPace: Double?) -> (low: Double, high: Double)? {
        // Slow aerobic zones — MP × pace multiplier (engine-aligned).
        if let m = mpPaceMultipliers {
            guard let mp = marathonPace, mp > 0 else { return nil }
            let fastEnd = mp * m.fast  // closer to MP (smaller multiplier, fewer seconds)
            let slowEnd = mp * m.slow  // further from MP (larger multiplier, more seconds)
            return (low: fastEnd, high: slowEnd)
        }
        // Fast/mid zones — tolerance around prescribed base
        if let tol = tolerancePercent, let b = base {
            let delta = b * tol
            return (low: b - delta, high: b + delta)
        }
        return nil
    }
}

/// Format a pace range (in seconds/mile) as "M:SS–M:SS/mi". Uses an en-dash.
/// If low and high are within 1 second, collapses to a single pace to avoid
/// nonsense ranges like "6:20–6:20/mi".
func formatPaceRange(low: Double, high: Double) -> String {
    let lowFmt = PaceCalculator.formatPace(low)
    let highFmt = PaceCalculator.formatPace(high)
    if lowFmt == highFmt {
        return "\(lowFmt)/mi"
    }
    return "\(lowFmt)–\(highFmt)/mi"
}

// MARK: - Equivalent Paces

/// Pre-computed equivalent pace values (in seconds per mile) for a given goal
struct EquivalentPaces {
    let goalRaceDistance: RaceDistance
    let goalTimeSeconds: Int

    /// All paces in seconds per mile
    let recoveryPace: Double
    let easyPace: Double
    let longRunPace: Double
    let moderatePace: Double  // midpoint of 75-85% effort range
    let steadyPace: Double    // midpoint of 85-95% effort range
    let mpPace: Double
    let hmPace: Double
    let thresholdPace: Double
    let tenKPace: Double
    let fiveKPace: Double
    let threeKPace: Double
    let milePace: Double

    /// Named paces that are hidden from display and selection
    var disabledPaces: Set<NamedPace>

    /// Per-zone overrides in seconds/mile (user-adjustable)
    var paceOverrides: [NamedPace: Double]

    init(raceDistance: RaceDistance, goalTimeSeconds: Int, disabledPaces: Set<NamedPace> = [], paceOverrides: [NamedPace: Double] = [:]) {
        self.goalRaceDistance = raceDistance
        self.goalTimeSeconds = goalTimeSeconds
        self.disabledPaces = disabledPaces
        self.paceOverrides = paceOverrides

        // Map RaceDistance to PaceCalculator key
        let fromKey: String
        switch raceDistance {
        case .mile1500: fromKey = "1500m"
        case .fiveK: fromKey = "5K"
        case .tenK: fromKey = "10K"
        case .halfMarathon: fromKey = "half"
        case .marathon: fromKey = "marathon"
        }

        // Use PaceCalculator performance ratios (our pace chart system)
        func pace(for key: String) -> Double {
            let seconds = PaceCalculator.getEquivalentTime(
                fromDistance: fromKey, fromSeconds: goalTimeSeconds, toDistance: key)
            let miles = PaceCalculator.distances[key] ?? 1.0
            return Double(seconds) / miles
        }

        let mp = paceOverrides[.mp] ?? pace(for: "marathon")
        let hm = paceOverrides[.hm] ?? pace(for: "half")
        let tenK = paceOverrides[.tenK] ?? pace(for: "10K")
        self.mpPace = mp
        self.hmPace = hm
        self.tenKPace = tenK
        self.fiveKPace = paceOverrides[.fiveK] ?? pace(for: "5K")
        self.threeKPace = paceOverrides[.threeK] ?? pace(for: "3K")
        self.milePace = paceOverrides[.mile] ?? pace(for: "mile")

        let thresholdHint = PaceCalculator.calculateOneHourPace(
            fromDistance: fromKey, totalSeconds: goalTimeSeconds
        )
        let zones = Self.derivedZones(mp: mp, hm: hm, tenK: tenK, thresholdHint: thresholdHint)
        self.recoveryPace = paceOverrides[.recovery] ?? zones.recovery
        self.easyPace = paceOverrides[.easy] ?? zones.easy
        self.longRunPace = paceOverrides[.longRun] ?? zones.longRun
        self.moderatePace = paceOverrides[.moderate] ?? zones.moderate
        self.steadyPace = paceOverrides[.steady] ?? zones.steady
        self.thresholdPace = paceOverrides[.threshold] ?? zones.threshold
    }

    /// Create from raw race-anchor paces (sec/mi) — zones are derived identically
    /// to the race-goal initializer so both paths produce the same zone table.
    init(
        mpPace: Double,
        hmPace: Double,
        tenKPace: Double,
        fiveKPace: Double,
        threeKPace: Double,
        milePace: Double
    ) {
        self.goalRaceDistance = .marathon
        self.goalTimeSeconds = Int(mpPace * RaceDistanceConstants.marathonMiles)
        self.mpPace = mpPace
        self.hmPace = hmPace
        self.tenKPace = tenKPace
        self.fiveKPace = fiveKPace
        self.threeKPace = threeKPace
        self.milePace = milePace
        self.disabledPaces = []
        self.paceOverrides = [:]

        let zones = Self.derivedZones(mp: mpPace, hm: hmPace, tenK: tenKPace, thresholdHint: nil)
        self.recoveryPace = zones.recovery
        self.easyPace = zones.easy
        self.longRunPace = zones.longRun
        self.moderatePace = zones.moderate
        self.steadyPace = zones.steady
        self.thresholdPace = zones.threshold
    }

    // MARK: - Zone Derivation

    struct ZoneTable: Equatable {
        let recovery: Double
        let easy: Double
        let longRun: Double
        let moderate: Double
        let steady: Double
        let threshold: Double
    }

    // Training-pace coefficients on MP using the canonical "% of MP" framework.
    // Convention: X% of MP = MP × (2 - X/100). E.g. MP 3:00/km × 1.10 = 3:18/km
    // at 90% MP. A coefficient > 1.0 means slower than MP.
    //
    // Canonical 10-zone spectrum, exact reciprocal multipliers (must match
    // _shared/pace-engine.ts TRAINING_PACE_MULTIPLIERS):
    //   Recovery: 60-70% MP (slow=1.6667 / fast=1.4286)  — midpoint: 1.5476 (65%)
    //   Easy:     70-80% MP (slow=1.4286 / fast=1.25)    — midpoint: 1.3393 (75%)
    //   Moderate: 80-90% MP (slow=1.25 / fast=1.1111)    — midpoint: 1.1806 (85%)
    //   Steady:   90-100% MP (slow=1.1111 / fast=1.0)    — midpoint: 1.0556 (95%)
    //
    // The single-number ratios below are midpoint anchors used by surfaces
    // that can't yet render a range. They will be retired once those surfaces
    // migrate to the engine's range output.
    static let recoveryMPRatio: Double = 1.5476 // 65% MP speed — midpoint of recovery band
    static let easyMPRatio: Double = 1.3393     // 75% MP speed — midpoint of easy band
    static let longRunMPRatio: Double = 1.3393  // = easy (legacy alias)
    static let moderateMPRatio: Double = 1.1806 // 85% MP speed — midpoint of moderate band
    static let steadyMPRatio: Double = 1.0556   // 95% MP speed — midpoint of steady band

    /// Derive training-zone paces from race-pace anchors. Used by both initializers
    /// so the zone table is identical when inputs are equivalent.
    static func derivedZones(
        mp: Double,
        hm: Double,
        tenK: Double,
        thresholdHint: Double?
    ) -> ZoneTable {
        let threshold = thresholdHint ?? oneHourPace(tenKPace: tenK, hmPace: hm)
        return ZoneTable(
            recovery: mp * recoveryMPRatio,
            easy: mp * easyMPRatio,
            longRun: mp * longRunMPRatio,
            moderate: mp * moderateMPRatio,
            steady: mp * steadyMPRatio,
            threshold: threshold
        )
    }

    /// Interpolate 1-hour (LT) pace from raw 10K and half-marathon paces.
    /// Mirrors `PaceCalculator.calculateOneHourPace` but works from paces
    /// rather than a race-time anchor — so init #2 produces the same threshold.
    static func oneHourPace(tenKPace: Double, hmPace: Double) -> Double {
        let distance10K = RaceDistanceConstants.tenKMiles
        let distanceHalf = RaceDistanceConstants.halfMarathonMiles
        let time10K = tenKPace * distance10K
        let timeHalf = hmPace * distanceHalf
        let target = 3600.0
        if time10K >= target { return tenKPace }
        if timeHalf <= target { return hmPace }
        let fraction = (target - time10K) / (timeHalf - time10K)
        let distanceInOneHour = distance10K + fraction * (distanceHalf - distance10K)
        return target / distanceInOneHour
    }

    /// All named paces ordered from slowest to fastest (excluding disabled paces)
    var allPaces: [(NamedPace, Double)] {
        let all: [(NamedPace, Double)] = [
            (.recovery, recoveryPace),
            (.easy, easyPace),
            (.longRun, longRunPace),
            (.moderate, moderatePace),
            (.steady, steadyPace),
            (.mp, mpPace),
            (.hm, hmPace),
            (.threshold, thresholdPace),
            (.tenK, tenKPace),
            (.fiveK, fiveKPace),
            (.threeK, threeKPace),
            (.mile, milePace),
        ]
        return all.filter { !disabledPaces.contains($0.0) }
    }

    /// Find the closest named pace for a given actual pace (sec/mi)
    func closestNamedPace(forPaceSeconds paceSeconds: Double, tolerance: Double = 10.0) -> NamedPace? {
        var closest: (NamedPace, Double)?
        for (name, refPace) in allPaces {
            let diff = abs(paceSeconds - refPace)
            if diff <= tolerance {
                if closest == nil || diff < closest!.1 {
                    closest = (name, diff)
                }
            }
        }
        return closest?.0
    }

    /// Get pace seconds for a named pace
    func paceSeconds(for namedPace: NamedPace) -> Double {
        switch namedPace {
        case .recovery: return recoveryPace
        case .easy: return easyPace
        case .longRun: return longRunPace
        case .moderate: return moderatePace
        case .steady: return steadyPace
        case .mp: return mpPace
        case .hm: return hmPace
        case .threshold: return thresholdPace
        case .tenK: return tenKPace
        case .fiveK: return fiveKPace
        case .threeK: return threeKPace
        case .mile: return milePace
        }
    }

    /// Format a pace in seconds as a min:sec/mi string
    nonisolated static func formatPace(_ seconds: Double) -> String {
        let totalSecs = Int(seconds.rounded())
        let mins = totalSecs / 60
        let secs = totalSecs % 60
        return "\(mins):\(String(format: "%02d", secs))/mi"
    }
}

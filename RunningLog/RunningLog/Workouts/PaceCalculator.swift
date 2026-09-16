import Foundation
import SwiftUI

// MARK: - RaceDistanceConstants

/// Single source of truth for race distances and mile/km conversion factors.
/// Values derived from the international mile (1609.344 m exactly) and the
/// IAAF-standard 42.195 km marathon so Swift and the web app (see
/// /web/src/lib/race-constants.ts) cannot drift apart.
enum RaceDistanceConstants {
    static let marathonMiles: Double = 26.21875        // 42.195 km / 1.609344
    static let halfMarathonMiles: Double = 13.109375   // marathonMiles / 2
    static let tenKMiles: Double = 6.2137119           // 10 km / 1.609344
    static let fiveKMiles: Double = 3.1068560          // 5 km  / 1.609344
    static let meterPerMile: Double = 1609.344         // exact definition
    static let kmPerMile: Double = 1.609344            // exact definition
}

// MARK: - PaceCalculator

enum PaceCalculator {
    /// Dew point (°F) at or above which heat starts meaningfully taxing a run,
    /// and the floor for showing the HEAT-ADJ toggle. This is the model's own
    /// baseline — `calculateDewPointAdjustment` adds zero penalty below it —
    /// so every heat surface must gate on the SAME value. Single source of
    /// truth: reference `PaceCalculator.heatDewPointFloorF`, never a literal.
    static let heatDewPointFloorF: Double = 55

    /// Race distances in miles
    static let distances: [String: Double] = [
        "400m": 0.4 / RaceDistanceConstants.kmPerMile,
        "800m": 0.8 / RaceDistanceConstants.kmPerMile,
        "1K": 1.0 / RaceDistanceConstants.kmPerMile,
        "1500m": 1.5 / RaceDistanceConstants.kmPerMile,
        "mile": 1.0,
        "3K": 3.0 / RaceDistanceConstants.kmPerMile,
        "5K": RaceDistanceConstants.fiveKMiles,
        "10K": RaceDistanceConstants.tenKMiles,
        "10mi": 10.0,
        "half": RaceDistanceConstants.halfMarathonMiles,
        "marathon": RaceDistanceConstants.marathonMiles,
    ]

    // MARK: - Performance Ratios (fitness-index-based)

    // Baseline: 10K = 1.0
    // Formula: TargetTime = KnownTime * (TargetRatio / KnownRatio)
    // Or equivalently: Base10K = KnownTime / KnownRatio, then TargetTime = Base10K * TargetRatio
    static let performanceRatios: [String: Double] = [
        // 1500m anchor: 0.129167. 400m/800m/1K via Riegel from 1500m: T2 = T1500 * (D2/1.5km)^1.06
        "400m": 0.033230,   // (0.4/1.5)^1.06 * 0.129167
        "800m": 0.067260,   // (0.8/1.5)^1.06 * 0.129167
        "1K":   0.084600,   // (1.0/1.5)^1.06 * 0.129167
        "1500m": 0.129167,
        "mile": 0.139583,
        "3K": 0.277083,
        "5K": 0.481250,
        "10K": 1.000000,
        "10mi": 1.661000, // Interpolated between 10K and half
        "half": 2.204167,
        "marathon": 4.615625
    ]

    /// Calculate all equivalent paces using ratio-based fitness index
    /// This approach uses fixed ratios relative to 10K to predict equivalent times
    static func calculateEquivalentPaces(
        fromDistance: String,
        totalSeconds: Int
    ) -> [String: Double] {
        let inputSeconds = Double(totalSeconds)

        // Get the ratio for the input distance
        guard let inputRatio = performanceRatios[fromDistance] else { return [:] }

        // Calculate the theoretical base 10K time
        // Base10K = KnownTime / KnownRatio
        let base10KSeconds = inputSeconds / inputRatio

        var paces: [String: Double] = [:]

        // Calculate predicted times and paces for all distances
        for (distanceName, distanceMiles) in distances {
            guard let targetRatio = performanceRatios[distanceName] else { continue }

            // PredictedTime = Base10K * TargetRatio
            let predictedSeconds = base10KSeconds * targetRatio
            paces[distanceName] = predictedSeconds / distanceMiles
        }

        return paces
    }

    /// Get equivalent race time for a distance given another race performance
    static func getEquivalentTime(
        fromDistance: String,
        fromSeconds: Int,
        toDistance: String
    ) -> Int {
        guard let fromRatio = performanceRatios[fromDistance],
              let toRatio = performanceRatios[toDistance] else { return 0 }

        // TargetTime = KnownTime * (TargetRatio / KnownRatio)
        let predictedSeconds = Double(fromSeconds) * (toRatio / fromRatio)
        return Int(predictedSeconds)
    }

    /// Calculate 1-hour pace (LT/Threshold pace)
    /// Finds the pace at which you could race for exactly 1 hour (3600 seconds)
    /// by interpolating between 10K and Half Marathon performance
    static func calculateOneHourPace(
        fromDistance: String,
        totalSeconds: Int
    ) -> Double? {
        guard let inputRatio = performanceRatios[fromDistance],
              let ratio10K = performanceRatios["10K"],
              let ratioHalf = performanceRatios["half"] else { return nil }

        // Calculate base 10K time
        let base10KSeconds = Double(totalSeconds) / inputRatio

        // Get 10K and Half times
        let time10K = base10KSeconds * ratio10K // Time to run 10K (6.214 mi)
        let timeHalf = base10KSeconds * ratioHalf // Time to run Half (13.109 mi)

        // Target: exactly 1 hour = 3600 seconds
        let targetTime = 3600.0

        // Find what distance can be covered in exactly 3600 seconds
        // by interpolating between 10K and Half Marathon
        let distance10K = RaceDistanceConstants.tenKMiles
        let distanceHalf = RaceDistanceConstants.halfMarathonMiles

        // Edge cases
        if time10K >= targetTime {
            // 10K takes >= 1 hour, use 10K pace
            return time10K / distance10K
        }
        if timeHalf <= targetTime {
            // Half takes <= 1 hour, use Half pace
            return timeHalf / distanceHalf
        }

        // Interpolate: fraction = (targetTime - time10K) / (timeHalf - time10K)
        let fraction = (targetTime - time10K) / (timeHalf - time10K)

        // Distance covered in 1 hour = 10K distance + fraction * (Half distance - 10K distance)
        let distanceInOneHour = distance10K + fraction * (distanceHalf - distance10K)

        // 1-hour pace = 3600 seconds / distance in miles
        return targetTime / distanceInOneHour
    }

    /// Format seconds per mile to MM:SS
    /// Format pace from seconds per mile → "M:SS"
    nonisolated static func formatPace(_ seconds: Double) -> String {
        let totalSecs = Int(seconds.rounded())
        let mins = totalSecs / 60
        let secs = totalSecs % 60
        return String(format: "%d:%02d", mins, secs)
    }

    /// Format pace from integer seconds per mile → "M:SS"
    nonisolated static func formatPace(_ seconds: Int) -> String {
        formatPace(Double(seconds))
    }

    /// Format pace from minutes per mile → "M:SS"
    nonisolated static func formatPaceFromMinutes(_ minutesPerMile: Double) -> String {
        formatPace(minutesPerMile * 60)
    }

    /// Format pace with unit suffix → "M:SS/mi"
    nonisolated static func formatPaceWithUnit(_ secondsPerMile: Double) -> String {
        "\(formatPace(secondsPerMile))/mi"
    }

    /// Format pace in km (converts seconds/mile to seconds/km)
    nonisolated static func formatPaceKm(_ secondsPerMile: Double) -> String {
        let totalSecs = Int((secondsPerMile / 1.60934).rounded())
        let mins = totalSecs / 60
        let secs = totalSecs % 60
        return String(format: "%d:%02d", mins, secs)
    }

    /// Calculate splits for a given pace (400m, 1K, mile)
    nonisolated static func calculateSplits(paceSecondsPerMile: Double) -> (fourHundred: Double, oneK: Double, mile: Double) {
        let secondsPerKm = paceSecondsPerMile / 1.60934
        let fourHundred = secondsPerKm * 0.4 // 400m = 0.4km
        let oneK = secondsPerKm
        let mile = paceSecondsPerMile
        return (fourHundred, oneK, mile)
    }

    /// Format split time (handles sub-minute times)
    nonisolated static func formatSplit(_ seconds: Double) -> String {
        let totalSeconds = Int(seconds.rounded())
        let mins = totalSeconds / 60
        let secs = totalSeconds % 60
        if mins == 0 {
            return String(format: "0:%02d", secs)
        }
        return String(format: "%d:%02d", mins, secs)
    }

    /// Format total time to H:MM:SS or MM:SS
    static func formatTime(_ totalSeconds: Int) -> String {
        let hours = totalSeconds / 3600
        let mins = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, mins, secs)
        } else {
            return String(format: "%d:%02d", mins, secs)
        }
    }

    /// Parse a race-time string into seconds. 2-part interpretation depends on distance:
    /// long distances (10mi / half / marathon) treat "H:MM"; others treat "MM:SS".
    /// 3-part input is always H:MM:SS. Callers that enter long-distance times must
    /// supply H:MM or H:MM:SS explicitly — no heuristic fallback.
    static func parseTime(_ timeString: String, forDistance distance: String? = nil) -> Int? {
        let parts = timeString.split(separator: ":").compactMap { Int($0) }
        let longDistances: Set<String> = ["10mi", "half", "marathon"]
        let isLong = distance.map { longDistances.contains($0) } ?? false

        switch parts.count {
        case 3:
            return parts[0] * 3600 + parts[1] * 60 + parts[2]
        case 2:
            if isLong { return parts[0] * 3600 + parts[1] * 60 }
            return parts[0] * 60 + parts[1]
        default:
            return nil
        }
    }

    /// Validate if the time is reasonable for the distance
    /// Returns nil if valid, or an error message if unrealistic
    static func validateTime(_ seconds: Int, forDistance distance: String) -> String? {
        guard let distanceMiles = distances[distance] else { return nil }

        let paceSecondsPerMile = Double(seconds) / distanceMiles

        // World record paces (roughly):
        // - Marathon: ~4:38/mi (278 sec)
        // - Half: ~4:28/mi (268 sec)
        // - 10K: ~4:15/mi (255 sec)
        // - 5K: ~4:00/mi (240 sec)
        // - Mile: ~3:43/mi (223 sec)
        // - 1500m: ~3:26/mi (206 sec)

        // Minimum reasonable pace (slightly faster than world records)
        let minPace: Double = switch distance {
        case "marathon": 250 // ~4:10/mi
        case "half": 240 // ~4:00/mi
        case "10K",
             "10mi": 230 // ~3:50/mi
        case "5K",
             "3K": 210 // ~3:30/mi
        case "mile",
             "1500m": 180 // ~3:00/mi
        default: 180
        }

        if paceSecondsPerMile < minPace {
            return "Time seems too fast - check format (H:MM:SS for long races)"
        }

        // No "too slow" warning - let users enter whatever time they want
        return nil
    }

    /// Format total seconds as H:MM:SS or MM:SS
    static func formatSeconds(_ totalSeconds: Int) -> String {
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        let s = totalSeconds % 60
        if h > 0 {
            return "\(h):\(String(format: "%02d", m)):\(String(format: "%02d", s))"
        }
        return "\(m):\(String(format: "%02d", s))"
    }

    // MARK: - Dew Point Adjustment (Emy's Calculator)

    /// Calculate heat-adjusted pace based on temperature and dew point
    /// Returns adjustment details including the adjusted pace in seconds per mile
    /// Interpolation table: composite score → adjustment percentage.
    ///
    /// Recalibrated 2026-08-05 to match "Dew Point Calculator Emy" v2 exactly.
    /// The previous table paired a LINEAR dew multiplier with breakpoints shifted
    /// ~10 composite points right of Hadley's published chart; at 72–75°F dew the
    /// linear form only supplied half that shift, so the model under-corrected by
    /// ~0.75pp. The exponential multiplier below closes it.
    ///
    /// Must stay in lockstep with supabase/functions/_shared/pace-heat-adjustment.ts
    /// and pace-heat.ts. Reference point: 5:15/mi at 78°F / 75°F dew → 5:33/mi.
    private static let adjustmentTable: [(score: Double, pct: Double)] = [
        (100, 0.000),
        (110, 0.005),
        (120, 0.008),
        (130, 0.012),
        (140, 0.020),
        (150, 0.034),
        (160, 0.050),
        (170, 0.070),
        (185, 0.100),   // chart ends here — see beyondChart
    ]

    /// Past this composite the chart has nothing to say. The source sheet returns
    /// NA(); we clamp and flag so the UI can refuse instead of prescribing.
    static let beyondChartScore: Double = 185

    /// Copy for the refusal, verbatim from the sheet.
    static let beyondChartMessage = "Very tough conditions to run marathon pace work"

    /// Dew-point multiplier: flat below the 65°F pivot, exponential above it.
    /// Weights dew point above air temperature — dew point is what decides
    /// whether sweat can evaporate, which is the mechanism that actually limits
    /// the runner in humid conditions.
    static func dewPointMultiplier(_ dewPointF: Double) -> Double {
        guard dewPointF.isFinite, dewPointF > 65 else { return 1.01 }
        return 1.01 * pow(1.011557695, dewPointF - 65)
    }

    // MARK: Rep-length scaling

    /// The adjustment table is calibrated for CONTINUOUS running of ~1.5 mi or
    /// longer. A short rep earns less of the penalty because the body sheds heat
    /// during the recovery between reps. Must stay in lockstep with
    /// `repLengthFactor` in supabase/functions/_shared/pace-heat-adjustment.ts —
    /// the backend stamps `running_workout_laps.heat_adjusted_pace_sec_per_mile`
    /// with the scaled value, and an unscaled iOS recompute would disagree with
    /// the rows next to it.
    static let heatFullMiles: Double = 1.5   // ≥ this → full adjustment
    static let heatHalfMiles: Double = 0.75  // ≤ this → half adjustment

    /// Fraction of the heat adjustment a bout of this length earns: 0.5 for a
    /// short rep, ramping to 1.0 at 1.5 mi. Unknown length — a continuous run —
    /// gets the full adjustment.
    ///
    /// A continuous run is ONE bout. Never pass the length of an individual mile
    /// split of a continuous run: six 1-mile splits of a 6-miler would each land
    /// mid-ramp at 0.67× and under-credit the run by a third.
    static func heatRepLengthFactor(_ distanceMiles: Double?) -> Double {
        guard let d = distanceMiles, d.isFinite else { return 1.0 }
        if d >= heatFullMiles { return 1.0 }
        if d <= heatHalfMiles { return 0.5 }
        return 0.5 + (d - heatHalfMiles) / (heatFullMiles - heatHalfMiles) * 0.5
    }

    // MARK: Intensity scaling (credit only)

    /// The adjustment table is a QUALITY-WORK chart — Hadley published it to
    /// answer "how much slower should my tempo be today," and the sheet's
    /// out-of-range string names marathon-pace work specifically. Metabolic heat
    /// production scales with running speed, so an easy run makes less heat,
    /// sheds a larger share of it, and gives up less pace. Scaling the credit
    /// down at easy intensity stops a 7:44 jog reading as a 7:19 one.
    ///
    /// The 0.75 floor is a COACHING JUDGMENT, not a fitted parameter — 1191 real
    /// laps put the chart dead-on at moderate effort (HR 145–152 → 4.8–6.1% vs
    /// the table's 5.6%) but could not resolve the easy end at all (±3–4pp).
    /// Full rationale in supabase/functions/_shared/pace-heat-adjustment.ts.
    /// Must stay in lockstep with `intensityFactor` there.
    static let heatIntensityFullRatio: Double = 0.95  // ≥ this × LT speed → full
    static let heatIntensityFloorRatio: Double = 0.78 // ≤ this × LT speed → floor
    static let heatIntensityFloor: Double = 0.75

    /// Fraction of the heat adjustment a bout at this intensity earns, from the
    /// athlete's threshold pace. Both in sec/mile. Unknown threshold → 1.0: an
    /// athlete with no anchor gets the chart as published, never an invented
    /// discount.
    static func heatIntensityFactor(
        paceSeconds: Double,
        thresholdPaceSeconds: Double?
    ) -> Double {
        guard let lt = thresholdPaceSeconds, lt.isFinite, lt > 0,
              paceSeconds.isFinite, paceSeconds > 0 else { return 1.0 }

        // Fraction of threshold SPEED. LT 6:20 run at 7:44 → 380/464 = 0.82.
        let ratio = lt / paceSeconds
        if ratio >= heatIntensityFullRatio { return 1.0 }
        if ratio <= heatIntensityFloorRatio { return heatIntensityFloor }
        let frac = (ratio - heatIntensityFloorRatio)
            / (heatIntensityFullRatio - heatIntensityFloorRatio)
        return heatIntensityFloor + frac * (1.0 - heatIntensityFloor)
    }

    /// Interpolate adjustment percentage from composite score
    private static func interpolateAdjustment(_ score: Double) -> Double {
        if score <= adjustmentTable.first!.score { return 0 }
        if score >= adjustmentTable.last!.score { return adjustmentTable.last!.pct }
        for i in 0..<(adjustmentTable.count - 1) {
            let lo = adjustmentTable[i]
            let hi = adjustmentTable[i + 1]
            if score >= lo.score && score < hi.score {
                let frac = (score - lo.score) / (hi.score - lo.score)
                return lo.pct + frac * (hi.pct - lo.pct)
            }
        }
        return adjustmentTable.last!.pct
    }

    /// Heat-adjust a pace from temperature + dew point.
    ///
    /// - `distanceMiles`: the length of ONE bout, for rep-length scaling. Omit
    ///   for continuous running and for prescriptive targets.
    /// - `thresholdPaceSeconds`: the athlete's LT pace, for intensity scaling of
    ///   the CREDIT. Omit and the credit equals the prescription.
    static func calculateDewPointAdjustment(
        paceSeconds: Double,
        temperatureF: Double,
        dewPointF: Double,
        distanceMiles: Double? = nil,
        thresholdPaceSeconds: Double? = nil
    ) -> DewPointAdjustment {
        // 1. Dew Point Multiplier — flat below the 65°F pivot, exponential above
        let dpMultiplier = dewPointMultiplier(dewPointF)

        // 2. Composite Score = Temp + (Dew Point × Multiplier)
        let compositeScore = temperatureF + (dewPointF * dpMultiplier)

        // 3. Interpolate adjustment from composite score table
        let adjustmentPct = interpolateAdjustment(compositeScore)

        // 4. Scale it to the length of the bout — a 600m rep doesn't pay the
        //    full continuous-running penalty. Applies BOTH directions.
        let repFactor = heatRepLengthFactor(distanceMiles)
        let effectivePct = adjustmentPct * repFactor

        // 5. Adjusted Pace — prescriptive, deliberately NOT intensity-scaled.
        //    Holding effort constant, the full slowdown is right at any
        //    intensity: an easy run in soup really should be run slower.
        let adjustedSeconds = paceSeconds * (1 + effectivePct)

        // 6. Intensity scaling — CREDIT ONLY. This is the direction where the
        //    quality-work chart over-pays an easy run.
        let intensity = heatIntensityFactor(
            paceSeconds: paceSeconds,
            thresholdPaceSeconds: thresholdPaceSeconds
        )

        return DewPointAdjustment(
            originalPaceSeconds: paceSeconds,
            adjustedPaceSeconds: adjustedSeconds,
            temperatureF: temperatureF,
            dewPointF: dewPointF,
            multiplier: dpMultiplier,
            compositeScore: compositeScore,
            adjustmentPercent: adjustmentPct,
            repLengthFactor: repFactor,
            intensityFactor: intensity,
            effectiveAdjustmentPercent: effectivePct
        )
    }

    /// Apply weather adjustment to all paces
    static func applyWeatherAdjustment(
        paces: [String: Double],
        temperatureF: Double,
        dewPointF: Double
    ) -> [String: Double] {
        var adjusted: [String: Double] = [:]
        for (key, pace) in paces {
            let adjustment = calculateDewPointAdjustment(
                paceSeconds: pace,
                temperatureF: temperatureF,
                dewPointF: dewPointF
            )
            adjusted[key] = adjustment.adjustedPaceSeconds
        }
        return adjusted
    }
}

// MARK: - DewPointAdjustment

struct DewPointAdjustment {
    let originalPaceSeconds: Double
    let adjustedPaceSeconds: Double
    let temperatureF: Double
    let dewPointF: Double
    let multiplier: Double
    let compositeScore: Double
    /// Raw table adjustment, on a continuous-run basis, BEFORE rep-length scaling.
    let adjustmentPercent: Double
    /// Rep-length factor actually applied (0.5–1.0). 1.0 when no bout length
    /// was supplied.
    var repLengthFactor: Double = 1.0
    /// Intensity factor applied to the CREDIT only (0.75–1.0). 1.0 when the
    /// athlete has no threshold anchor, or the bout was at LT and faster.
    var intensityFactor: Double = 1.0
    /// PRESCRIPTIVE adjustment = `adjustmentPercent × repLengthFactor`. Drives
    /// `adjustedPaceSeconds`. Deliberately NOT intensity-scaled.
    var effectiveAdjustmentPercent: Double

    /// RETROACTIVE adjustment = `effectiveAdjustmentPercent × intensityFactor`.
    /// Drives `neutralEquivalentPaceSeconds`. Equal to the prescriptive figure
    /// at LT-and-faster, smaller below it.
    var creditAdjustmentPercent: Double {
        effectiveAdjustmentPercent * intensityFactor
    }

    /// Conditions are past the end of the chart. `adjustedPaceSeconds` is a
    /// clamped extrapolation — show `PaceCalculator.beyondChartMessage` rather
    /// than prescribing a pace off it.
    var beyondChart: Bool { compositeScore > PaceCalculator.beyondChartScore }

    /// The pace the athlete's effort is *worth* in neutral conditions — the
    /// inverse of the prescriptive `adjustedPaceSeconds`. Running in heat costs
    /// `adjustmentPercent`, so a pace run in the heat normalizes to a FASTER
    /// cool-weather-equivalent. This is what the completed-workout HEAT-ADJ
    /// toggle shows (credit for the conditions). Prescriptive surfaces
    /// (targets to run *today*) use `adjustedPaceSeconds`, which is slower.
    ///
    /// Uses `creditAdjustmentPercent`, so it is intensity-scaled: below LT this
    /// is a SMALLER correction than `adjustedPaceSeconds` implies. The two are
    /// not exact inverses by design.
    var neutralEquivalentPaceSeconds: Double {
        originalPaceSeconds / (1 + creditAdjustmentPercent)
    }

    var adjustmentSecondsPerMile: Double {
        adjustedPaceSeconds - originalPaceSeconds
    }

    var formattedAdjustment: String {
        let secs = Int(adjustmentSecondsPerMile)
        if secs == 0 {
            return "No adjustment"
        }
        return "+\(secs) sec/mi"
    }

    var formattedPercent: String {
        String(format: "%.1f%%", adjustmentPercent * 100)
    }

    /// Label ladder. `ideal` runs to 110, NOT to the adjustment table's zero
    /// knot at 100. The two answer different questions, and sharing a number
    /// put a 55°F morning with a 45°F dew point — composite 100.45, a 0.02%
    /// time cost — into `.warm`, which this view renders as a sun icon and a
    /// tinted card. Kept in lockstep with the server
    /// (`_shared/pace-heat-adjustment.ts:heatCategory`, `pace-heat.ts`) and
    /// SQL `heat_category_for()`; change all four together.
    var heatCategory: HeatCategory {
        if compositeScore < 110 {
            .ideal
        } else if compositeScore < 130 {
            .warm
        } else if compositeScore < 150 {
            .hot
        } else if compositeScore < 170 {
            .veryHot
        } else {
            .dangerous
        }
    }
}

// MARK: - HeatCategory

enum HeatCategory: String {
    case ideal = "Ideal"
    case warm = "Warm"
    case hot = "Hot"
    case veryHot = "Very Hot"
    case dangerous = "Dangerous"

    var color: Color {
        switch self {
        case .ideal: Color.drip.positive
        case .warm: Color.drip.energized
        case .hot: Color.drip.coralLight
        case .veryHot: Color.drip.coral
        case .dangerous: Color.drip.tired
        }
    }

    var icon: String {
        switch self {
        case .ideal: "checkmark.circle.fill"
        case .warm: "sun.max.fill"
        case .hot: "thermometer.sun.fill"
        case .veryHot: "flame.fill"
        case .dangerous: "exclamationmark.triangle.fill"
        }
    }
}

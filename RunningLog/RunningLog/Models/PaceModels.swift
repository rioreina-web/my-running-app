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

    var displayPercentage: String {
        String(format: "%.0f%%", percentage)
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

    /// Get a display label using named pace references when available
    func displayLabel(
        forRacePace racePaceSeconds: Double,
        equivalentPaces: EquivalentPaces?
    ) -> String {
        let actualPace = paceSeconds(forRacePace: racePaceSeconds)

        if let equiv = equivalentPaces,
           let namedPace = equiv.closestNamedPace(forPaceSeconds: actualPace) {
            return namedPace.shortName
        }

        return "\(displayPercentage) MP"
    }

    /// Format seconds as M:SS
    static func formatTime(_ seconds: Double) -> String {
        let totalSecs = Int(seconds.rounded())
        let mins = totalSecs / 60
        let secs = totalSecs % 60
        return "\(mins):\(String(format: "%02d", secs))"
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

        self.mpPace = paceOverrides[.mp] ?? pace(for: "marathon")
        self.hmPace = paceOverrides[.hm] ?? pace(for: "half")
        self.tenKPace = paceOverrides[.tenK] ?? pace(for: "10K")
        self.fiveKPace = paceOverrides[.fiveK] ?? pace(for: "5K")
        self.threeKPace = paceOverrides[.threeK] ?? pace(for: "3K")
        self.milePace = paceOverrides[.mile] ?? pace(for: "mile")

        // Training zones — use pace chart system (all based off MP, matching PaceChartView)
        let mp = self.mpPace
        self.easyPace = paceOverrides[.easy] ?? mp / 0.75
        self.longRunPace = paceOverrides[.longRun] ?? mp / 0.78
        self.moderatePace = paceOverrides[.moderate] ?? mp / 0.80
        self.steadyPace = paceOverrides[.steady] ?? mp / 0.90
        self.recoveryPace = paceOverrides[.recovery] ?? mp / 0.70

        // LT/Threshold: 1-hour pace (pace chart "LT" — interpolated between 10K and half)
        self.thresholdPace = paceOverrides[.threshold] ?? PaceCalculator.calculateOneHourPace(
            fromDistance: fromKey, totalSeconds: goalTimeSeconds
        ) ?? (mp / 0.92)
    }

    /// Create from raw pace values (sec/mi) — used when deriving zones from runner's own data
    init(
        easyPace: Double,
        moderatePace: Double,
        steadyPace: Double,
        mpPace: Double,
        hmPace: Double,
        tenKPace: Double,
        fiveKPace: Double,
        threeKPace: Double,
        milePace: Double
    ) {
        self.goalRaceDistance = .marathon
        self.goalTimeSeconds = Int(mpPace * 26.2)
        self.recoveryPace = easyPace * 1.08
        self.easyPace = easyPace
        self.longRunPace = (easyPace + moderatePace) / 2
        self.moderatePace = moderatePace
        self.steadyPace = steadyPace
        self.mpPace = mpPace
        self.hmPace = hmPace
        self.thresholdPace = (hmPace + tenKPace) / 2
        self.tenKPace = tenKPace
        self.fiveKPace = fiveKPace
        self.threeKPace = threeKPace
        self.milePace = milePace
        self.disabledPaces = []
        self.paceOverrides = [:]
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

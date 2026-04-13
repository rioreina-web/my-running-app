//
//  RaceDistance.swift
//  RunningLog
//
//  Race distance enum with characteristics for multi-event training support.
//

import Foundation
import SwiftUI

// MARK: - Race Distance

/// Supported race distances for training plans
enum RaceDistance: String, Codable, CaseIterable, Identifiable {
    case mile1500 = "1500m"
    case fiveK = "5K"
    case tenK = "10K"
    case halfMarathon = "HM"
    case marathon = "Marathon"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mile1500: return "Mile"
        case .fiveK: return "5K"
        case .tenK: return "10K"
        case .halfMarathon: return "Half Marathon"
        case .marathon: return "Marathon"
        }
    }

    var shortName: String {
        switch self {
        case .mile1500: return "Mile"
        case .fiveK: return "5K"
        case .tenK: return "10K"
        case .halfMarathon: return "Half"
        case .marathon: return "Full"
        }
    }

    /// Distance in miles
    var distanceInMiles: Double {
        switch self {
        case .mile1500: return 1.0
        case .fiveK: return 3.1069
        case .tenK: return 6.2137
        case .halfMarathon: return 13.1094
        case .marathon: return 26.2188
        }
    }

    /// Distance in kilometers
    var distanceInKm: Double {
        switch self {
        case .mile1500: return 1.609
        case .fiveK: return 5.0
        case .tenK: return 10.0
        case .halfMarathon: return 21.0975
        case .marathon: return 42.195
        }
    }

    /// Typical training plan duration range in weeks
    var typicalPlanWeeks: ClosedRange<Int> {
        switch self {
        case .mile1500: return 8...12
        case .fiveK: return 8...14
        case .tenK: return 10...16
        case .halfMarathon: return 12...18
        case .marathon: return 14...24
        }
    }

    /// Maximum long run distance as percentage of race distance
    var maxLongRunPercentage: Double {
        switch self {
        case .mile1500: return 12.0  // ~12 miles max for milers
        case .fiveK: return 4.5      // ~14 miles max
        case .tenK: return 2.6       // ~16 miles max
        case .halfMarathon: return 1.5  // ~20 miles max
        case .marathon: return 0.85     // ~22 miles max
        }
    }

    /// Typical weekly mileage range for competitive training
    var typicalWeeklyMileage: ClosedRange<Double> {
        switch self {
        case .mile1500: return 30...70
        case .fiveK: return 25...80
        case .tenK: return 30...85
        case .halfMarathon: return 35...90
        case .marathon: return 40...100
        }
    }

    /// Primary energy system focus
    var primaryEnergySystem: EnergySystem {
        switch self {
        case .mile1500: return .anaerobic
        case .fiveK: return .vo2max
        case .tenK: return .aerobicThreshold
        case .halfMarathon: return .aerobicThreshold
        case .marathon: return .aerobic
        }
    }

    /// Icon for the race distance
    var icon: String {
        switch self {
        case .mile1500: return "bolt.fill"
        case .fiveK: return "flame.fill"
        case .tenK: return "figure.run"
        case .halfMarathon: return "road.lanes"
        case .marathon: return "flag.checkered"
        }
    }

    /// Color for the race distance
    var color: Color {
        switch self {
        case .mile1500: return Color.purple
        case .fiveK: return Color.drip.coral
        case .tenK: return Color.drip.coralLight
        case .halfMarathon: return Color.drip.energized
        case .marathon: return Color.drip.positive
        }
    }

    // MARK: - Pace Calculations

    /// Calculate race pace in seconds per mile from goal time
    func racePaceSecondsPerMile(goalTimeSeconds: Int) -> Double {
        return Double(goalTimeSeconds) / distanceInMiles
    }

    /// Calculate equivalent race times using fitness index approximations
    func equivalentTime(from otherDistance: RaceDistance, time: Int) -> Int {
        // Use Riegel's formula: T2 = T1 * (D2/D1)^1.06
        let ratio = pow(distanceInMiles / otherDistance.distanceInMiles, 1.06)
        return Int(Double(time) * ratio)
    }

    // MARK: - Event-Specific Pace Zones

    /// Get the "tempo" pace intensity for this event
    /// Shorter events run tempo at relatively faster paces
    /// Tempo = comfortably hard, sustained effort. Faster than MP/HM race pace for longer events.
    /// Formula: racePaceSeconds / (pct/100), so pct > 100 = faster than race pace.
    var tempoPaceIntensity: Double {
        switch self {
        case .mile1500: return 85   // ~10K effort — milers race at much higher intensity
        case .fiveK: return 88      // Threshold — slightly slower than 5K race pace
        case .tenK: return 96       // Just under 10K race pace
        case .halfMarathon: return 97   // ~15 sec/mi slower than HM race pace
        case .marathon: return 105  // ~30-40 sec/mi faster than MP (comfortably hard)
        }
    }

    /// LT (lactate threshold) — slightly faster than tempo, upper aerobic ceiling.
    var thresholdPaceIntensity: Double {
        switch self {
        case .mile1500: return 88   // ~10K-ish effort for milers
        case .fiveK: return 92      // Between 10K and 5K effort
        case .tenK: return 99       // Just at/under 10K race pace
        case .halfMarathon: return 102  // Slightly faster than HM race pace
        case .marathon: return 107  // Between tempo and 10K zone
        }
    }

    /// Get the "VO2max interval" pace intensity for this event
    var vo2maxPaceIntensity: Double {
        switch self {
        case .mile1500: return 105  // Faster than race pace
        case .fiveK: return 100     // At race pace
        case .tenK: return 105      // 5K pace
        case .halfMarathon: return 110  // ~5K pace
        case .marathon: return 115      // ~5K pace
        }
    }

    /// Easy = conversational, aerobic base pace. Slower than race pace (pct < 100).
    var easyPaceIntensity: Double {
        switch self {
        case .mile1500: return 75   // ~6:30/mi easy for a 4:50 miler
        case .fiveK: return 82      // ~8:15 easy for a 20-min 5K runner
        case .tenK: return 83       // ~8:33 easy for a 44-min 10K runner
        case .halfMarathon: return 90   // ~9:18 easy for a 1:50 HM runner
        case .marathon: return 90   // ~10:10 easy for a 4:00 marathoner
        }
    }

    /// Long run = easy+, slightly faster than easy, aerobic stimulus.
    var longRunPaceIntensity: Double {
        switch self {
        case .mile1500: return 72
        case .fiveK: return 80
        case .tenK: return 82
        case .halfMarathon: return 92   // ~9:04 long run for 1:50 HM
        case .marathon: return 92       // ~9:52 long run for 4:00 marathon
        }
    }
}

// MARK: - Energy System

/// Primary energy systems targeted in training
enum EnergySystem: String, Codable {
    case anaerobic = "anaerobic"           // <2 min efforts, 1500m/mile
    case vo2max = "vo2max"                 // 2-8 min efforts, 5K
    case aerobicThreshold = "threshold"    // 8-60 min efforts, 10K-HM
    case aerobic = "aerobic"               // >60 min efforts, marathon

    var displayName: String {
        switch self {
        case .anaerobic: return "Anaerobic"
        case .vo2max: return "VO2max"
        case .aerobicThreshold: return "Aerobic Threshold"
        case .aerobic: return "Aerobic"
        }
    }

    var description: String {
        switch self {
        case .anaerobic:
            return "High-intensity efforts lasting under 2 minutes"
        case .vo2max:
            return "Maximum oxygen uptake, 2-8 minute efforts"
        case .aerobicThreshold:
            return "Lactate threshold, 8-60 minute efforts"
        case .aerobic:
            return "Sustained aerobic endurance"
        }
    }
}

// MARK: - Race Distance Extensions

extension RaceDistance {
    /// Parse from legacy string format
    static func from(legacyString: String) -> RaceDistance? {
        switch legacyString.lowercased() {
        case "marathon", "full", "26.2":
            return .marathon
        case "half", "half marathon", "half_marathon", "halfmarathon", "hm", "13.1":
            return .halfMarathon
        case "10k", "10km":
            return .tenK
        case "5k", "5km":
            return .fiveK
        case "mile", "1500", "1500m", "1mi":
            return .mile1500
        default:
            return nil
        }
    }

    /// Convert to legacy database string
    var legacyString: String {
        switch self {
        case .marathon: return "marathon"
        case .halfMarathon: return "half_marathon"
        case .tenK: return "10k"
        case .fiveK: return "5k"
        case .mile1500: return "mile"
        }
    }
}

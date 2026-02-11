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
        case .mile1500: return "1500m / Mile"
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

    /// Calculate equivalent race times using VDOT approximations
    func equivalentTime(from otherDistance: RaceDistance, time: Int) -> Int {
        // Use Riegel's formula: T2 = T1 * (D2/D1)^1.06
        let ratio = pow(distanceInMiles / otherDistance.distanceInMiles, 1.06)
        return Int(Double(time) * ratio)
    }

    // MARK: - Event-Specific Pace Zones

    /// Get the "tempo" pace intensity for this event
    /// Shorter events run tempo at relatively faster paces
    var tempoPaceIntensity: Double {
        switch self {
        case .mile1500: return 78  // ~10K pace effort
        case .fiveK: return 82     // ~10K pace effort
        case .tenK: return 87      // ~HM pace effort
        case .halfMarathon: return 92  // ~HM pace
        case .marathon: return 92      // ~HM pace
        }
    }

    /// Get the "threshold" pace intensity for this event
    var thresholdPaceIntensity: Double {
        switch self {
        case .mile1500: return 85  // ~10K pace
        case .fiveK: return 88     // ~10K pace
        case .tenK: return 92      // ~HM pace
        case .halfMarathon: return 95  // Slightly faster than HM
        case .marathon: return 97      // Slightly faster than MP
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

    /// Get the "easy run" pace intensity for this event
    var easyPaceIntensity: Double {
        switch self {
        case .mile1500: return 65
        case .fiveK: return 68
        case .tenK: return 70
        case .halfMarathon: return 72
        case .marathon: return 75
        }
    }

    /// Long run pace intensity
    var longRunPaceIntensity: Double {
        switch self {
        case .mile1500: return 68
        case .fiveK: return 70
        case .tenK: return 72
        case .halfMarathon: return 75
        case .marathon: return 78
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
        case "half", "half marathon", "halfmarathon", "hm", "13.1":
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

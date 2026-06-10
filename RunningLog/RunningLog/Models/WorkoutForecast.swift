//
//  WorkoutForecast.swift
//  RunningLog
//
//  Decodes the weather_forecast JSONB stored on scheduled_workouts.
//  Server shape (from supabase/functions/_shared/pace-heat-adjustment.ts):
//
//  {
//    "temp_f": 82.4,
//    "dew_point_f": 68.0,
//    "humidity": 65,
//    "wind_mph": 8.2,
//    "condition": "partly_cloudy",
//    "composite_score": 152.3,
//    "heat_category": "very_hot",
//    "adjustment_pct": 0.031,
//    "fetched_at": "2026-04-16T14:00:00Z"
//  }
//
//  iOS uses temp_f + dew_point_f to compute the adjustment locally via
//  PaceCalculator.calculateDewPointAdjustment so the displayed adjustment
//  always matches what the Pace Chart screen shows.
//

import Foundation

struct WorkoutForecast: Codable, Equatable {
    let temperatureF: Double
    let dewPointF: Double?
    let humidity: Int?
    let windMph: Double?
    let condition: String?
    let heatCategory: String?
    let fetchedAt: Date?

    enum CodingKeys: String, CodingKey {
        case temperatureF = "temp_f"
        case dewPointF = "dew_point_f"
        case humidity
        case windMph = "wind_mph"
        case condition
        case heatCategory = "heat_category"
        case fetchedAt = "fetched_at"
    }

    /// True when the conditions are likely to noticeably affect pacing.
    /// Threshold is ≥ 3 sec/mi against the supplied reference pace.
    /// Earlier we used 5 sec/mi, which kept the per-step display in sync
    /// with the banner but produced a confusing inconsistency: the Heat
    /// Calculator card surfaces every +1s shift, so a +4s MP impact was
    /// reported there but silently dropped on the workout step. 3 sec/mi
    /// catches MP-class shifts while still filtering trivial sub-2s noise.
    func isMeaningful(referencePaceSecondsPerMile: Double = 420) -> Bool {
        guard let dp = dewPointF else { return false }
        let adjustment = PaceCalculator.calculateDewPointAdjustment(
            paceSeconds: referencePaceSecondsPerMile,
            temperatureF: temperatureF,
            dewPointF: dp
        )
        return abs(adjustment.adjustmentSecondsPerMile) >= 3
    }

    /// Compute the per-step adjusted pace given a target pace.
    /// Returns the adjusted seconds/mile. Same dew-point math as the chart.
    func adjust(paceSecondsPerMile: Double) -> Double {
        guard let dp = dewPointF else { return paceSecondsPerMile }
        let result = PaceCalculator.calculateDewPointAdjustment(
            paceSeconds: paceSecondsPerMile,
            temperatureF: temperatureF,
            dewPointF: dp
        )
        return result.adjustedPaceSeconds
    }

    var conditionIcon: String {
        switch condition {
        case "clear": return "sun.max.fill"
        case "partly_cloudy": return "cloud.sun.fill"
        case "cloudy": return "cloud.fill"
        case "fog": return "cloud.fog.fill"
        case "drizzle": return "cloud.drizzle.fill"
        case "rain": return "cloud.rain.fill"
        case "snow": return "cloud.snow.fill"
        case "thunderstorm": return "cloud.bolt.rain.fill"
        default: return "thermometer.medium"
        }
    }

    var summaryShort: String {
        let temp = "\(Int(temperatureF))°F"
        if let dp = dewPointF {
            return "\(temp) · dew \(Int(dp))°F"
        }
        return temp
    }
}

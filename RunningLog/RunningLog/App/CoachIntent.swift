//
//  CoachIntent.swift
//  RunningLog
//
//  Static lookup mapping workout types to a one-line "coach intent" —
//  what the workout is *for*. Used in Plate 18's Tomorrow section as the
//  italic-serif quote under each prescribed workout.
//
//  v1: hardcoded per workout type. Acceptable substitute until we add a
//  `coach_intent` column to `scheduled_workouts` (or wire up a per-workout
//  Haiku call at plan-generation time).
//
//  When that lands, this file's `forType(_:)` becomes the fallback path
//  and the database column wins.
//

import Foundation

enum CoachIntent {

    /// Returns a single-line italic-serif quote framing the *purpose* of
    /// the workout. Plain prose, no emojis, no markdown — render with a
    /// serif italic font.
    static func forType(_ workoutType: String?) -> String? {
        guard let raw = workoutType?.lowercased() else { return nil }
        switch raw {
        case "easy":
            return "Conversational pace, whole run easy. Recovery focus."
        case "recovery":
            return "Easy shakeout between hard days. Don't make it count."
        case "tempo":
            return "Hold the rhythm. Consistent splits, not negative — let it settle."
        case "threshold":
            return "Comfortably hard. The line you can hold for an hour, no faster."
        case "intervals":
            return "Sharp efforts, full recovery between. Speed comes back fastest."
        case "long_run", "longrun", "long":
            return "Steady, conversational. Fuel and hydrate. The aerobic engine compounds."
        case "progression":
            return "Easy → moderate → MP. Build through; finish strong, not spent."
        case "strides":
            return "Six to eight, 20 seconds each. Quick and relaxed, full recovery."
        case "race":
            return "Trust the work. Race-pace effort — recovery is tomorrow's workout."
        case "rest":
            return "Recover, hydrate, sleep. Rest days are part of the plan."
        case "cross_training", "crosstraining":
            return "Easy aerobic — bike, swim, or row. Heart rate steady."
        case "strength":
            return "Functional work. Posterior chain, single-leg, core."
        default:
            return nil
        }
    }

    /// A short label suitable for the section eyebrow. Falls back to a
    /// title-cased version of the raw type.
    static func displayName(for workoutType: String?) -> String {
        guard let raw = workoutType?.lowercased() else { return "Run" }
        switch raw {
        case "easy":              return "Easy Run"
        case "recovery":          return "Recovery Run"
        case "tempo":             return "Tempo"
        case "threshold":         return "Threshold"
        case "intervals":         return "Intervals"
        case "long_run", "longrun", "long": return "Long Run"
        case "progression":       return "Progression"
        case "strides":           return "Strides"
        case "race":              return "Race"
        case "rest":              return "Rest"
        case "cross_training", "crosstraining": return "Cross-train"
        case "strength":          return "Strength"
        default:
            return raw
                .replacingOccurrences(of: "_", with: " ")
                .capitalized
        }
    }
}

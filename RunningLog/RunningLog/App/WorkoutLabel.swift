//
//  WorkoutLabel.swift
//  RunningLog
//
//  THE single source of truth for turning a stored `workout_type` key
//  into the user-facing label. Every screen must render workout types
//  through `WorkoutLabel.display(_:)` — do NOT hardcode "Tempo" / "Easy"
//  / "Long run" inline. Before this file, seven screens each kept their
//  own switch, so the same run showed up as "Easy run" one place and
//  "Easy" another. This is the fix for that drift (Wave 2 · H1).
//
//  Label taxonomy (per CLAUDE.md "Pace zones" + "Workout labels"):
//    Effort:      Easy · Moderate · Steady · Recovery
//    Race-pace:   MP · HMP · LT · 10K · 5K · 3K · Mile
//    Structural:  Long run · Long wo · Cross-train · Strength · Rest · Race
//
//  "Tempo" and "Threshold" are retired as ambiguous — the pace zone IS
//  the label. Threshold maps to LT (unambiguous). "Tempo" is kept ONLY
//  as a legacy display for rows already stored that way; it is no longer
//  offered when logging a new workout (see ManualWorkoutView).
//

import Foundation

enum WorkoutLabel {

    /// Stored `workout_type` key → user-facing display label.
    /// Case-insensitive; tolerates a few historical spellings.
    static func display(_ workoutType: String?) -> String {
        guard let raw = workoutType?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
            !raw.isEmpty
        else { return "Run" }

        switch raw {
        // ── Effort zones ─────────────────────────────────────────────
        case "easy":                        return "Easy"
        case "moderate":                    return "Moderate"
        case "steady":                      return "Steady"
        case "recovery":                    return "Recovery"

        // ── Race-pace zones (the 10-zone taxonomy) ───────────────────
        case "mp":                          return "MP"
        case "hmp":                         return "HMP"
        case "lt":                          return "LT"
        case "10k":                         return "10K"
        case "5k":                          return "5K"
        case "3k":                          return "3K"
        case "mile":                        return "Mile"

        // ── Structural ───────────────────────────────────────────────
        case "long_run", "longrun", "long": return "Long run"
        case "long_wo", "longwo":           return "Long wo"
        case "cross_train", "cross_training", "crosstraining", "crosstrain":
            return "Cross-train"
        case "strength":                    return "Strength"
        case "rest":                        return "Rest"
        case "race":                        return "Race"

        // ── Legacy (existing rows only; not offered for new entries) ──
        case "threshold":                   return "LT"       // Threshold IS LT
        case "tempo":                       return "Tempo"    // kept for legacy data
        case "intervals", "interval":       return "Intervals"
        case "progression":                 return "Progression"
        case "fartlek":                     return "Fartlek"
        case "hills":                       return "Hills"
        case "strides":                     return "Strides"

        default:
            return raw
                .replacingOccurrences(of: "_", with: " ")
                .capitalized
        }
    }
}

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

    // ────────────────────────────────────────────────────────────────────
    // The offer list — what a picker is allowed to show (2026-08-07)
    // ────────────────────────────────────────────────────────────────────
    //
    // `display(_:)` fixed how a stored key is RENDERED. It did not fix which
    // keys get WRITTEN, so three pickers each kept their own list and they
    // disagreed:
    //
    //   ManualWorkoutView.newRunTypes        14 keys, the canonical taxonomy
    //   EditableWorkoutTypeSection (journal)  6 keys, incl. "interval"
    //   WorkoutRepReceiptView.typeOptions     9 keys, incl. "intervals"
    //
    // The database shows the cost: `interval` (14 rows) and `intervals` (9
    // rows) are both live, for one concept. `tempo` (13) and `threshold` (10)
    // are stored too, though the taxonomy in CLAUDE.md retired both as
    // ambiguous. Every consumer that groups or filters by `workout_type` — the
    // quality-session filter, Trends key-session classification, the Ask
    // analyzers — splits those rows across two buckets.
    //
    // So: one list, here, next to the mapper that renders it.

    /// Run types offered when logging or re-typing a run — the pace-zone
    /// taxonomy from CLAUDE.md. "Tempo" and "Threshold" are deliberately absent
    /// (retired as ambiguous — the pace zone IS the label; Threshold is LT).
    /// Legacy values already stored are preserved on edit via
    /// `options(including:)`.
    static let offered: [(String, String)] = [
        ("easy", "Easy"), ("moderate", "Moderate"), ("steady", "Steady"),
        ("mp", "MP"), ("hmp", "HMP"), ("lt", "LT"),
        ("10k", "10K"), ("5k", "5K"), ("3k", "3K"), ("mile", "Mile"),
        ("long_run", "Long run"), ("recovery", "Recovery"),
        ("race", "Race"), ("other", "Other"),
    ]

    /// The offer list, plus `current` when it's a legacy value that isn't in
    /// it — so opening an old run's picker never silently rewrites its type,
    /// while a new run only ever sees the canonical set. Generalized from
    /// `ManualWorkoutView.runTypeOptions`, which was the only place that got
    /// this right.
    static func options(including current: String?) -> [(String, String)] {
        guard let raw = current?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
            !raw.isEmpty,
            !offered.contains(where: { $0.0 == raw })
        else { return offered }
        return offered + [(raw, display(raw))]
    }

    /// Fold a key to its canonical spelling before WRITING it.
    ///
    /// Call this on every write of `workout_type`. It only collapses spellings
    /// of the same concept — it does not reinterpret a workout. `threshold` →
    /// `lt` is the one judgement call, and it's the taxonomy's own: "Threshold
    /// maps to LT (unambiguous)", per this file's header.
    ///
    /// Anything unrecognised passes through lowercased and untouched. Never
    /// invent a type the athlete didn't choose.
    static func normalize(_ workoutType: String?) -> String? {
        guard let raw = workoutType?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
            !raw.isEmpty
        else { return nil }

        switch raw {
        case "interval":                          return "intervals"
        case "longrun", "long":                   return "long_run"
        case "longwo":                            return "long_wo"
        case "cross_training", "crosstraining", "crosstrain":
            return "cross_train"
        case "threshold":                         return "lt"
        default:                                  return raw
        }
    }
}

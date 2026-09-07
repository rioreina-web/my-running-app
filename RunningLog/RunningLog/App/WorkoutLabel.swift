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
//  Label taxonomy (2026-08-10 — supersedes the pace-zone-as-label rule):
//    Effort:      Easy · Moderate · Steady · Recovery run
//    Session:     Threshold · Intervals · Fartlek · Progression
//    Structural:  Long run · Long run workout · Cross-train · Strength ·
//                 Rest · Race
//
//  A PACE ZONE IS NOT A WORKOUT TYPE. MP/HMP/LT/10K/5K/3K/Mile describe
//  the pace of a segment, not the intent of a session — a workout carries
//  its zone as a separate, auto-derived label. They are therefore no
//  longer offered here; rows already stored under them still render via
//  `display(_:)` and survive an edit via `options(including:)`.
//
//  "Tempo" is retired — it folds to "Threshold" on write (see `normalize`).
//  The reverse fold (threshold → lt) that this file used to do is GONE:
//  Threshold is a session type, LT is a pace zone, and collapsing one into
//  the other is the ambiguity that made both unreadable.
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
        case "recovery":                    return "Recovery run"

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
        case "long_wo", "longwo":           return "Long run workout"
        case "cross_train", "cross_training", "crosstraining", "crosstrain":
            return "Cross-train"
        case "strength":                    return "Strength"
        case "rest":                        return "Rest"
        case "race":                        return "Race"

        // ── Session types ────────────────────────────────────────────
        case "threshold":                   return "Threshold"
        case "intervals", "interval":       return "Intervals"
        case "fartlek":                     return "Fartlek"
        case "progression":                 return "Progression"

        // ── Legacy (existing rows only; not offered for new entries) ──
        case "tempo":                       return "Threshold"  // folded 2026-08-10
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

    /// Run types offered when logging or re-typing a run (2026-08-10).
    ///
    /// Ordered by how a week actually reads: the aerobic efforts first, then
    /// the long runs, then the quality sessions, then Race. Pace zones are
    /// deliberately ABSENT — a zone describes a segment's pace, not a
    /// session's intent, and a workout gets its zone label automatically.
    /// Legacy values already stored (incl. `mp`, `lt`, `5k`, `tempo`) are
    /// preserved on edit via `options(including:)`.
    static let offered: [(String, String)] = [
        ("easy", "Easy"), ("moderate", "Moderate"), ("steady", "Steady"),
        ("long_run", "Long run"), ("long_wo", "Long run workout"),
        ("threshold", "Threshold"), ("intervals", "Intervals"),
        ("fartlek", "Fartlek"), ("recovery", "Recovery run"),
        ("progression", "Progression"), ("race", "Race"),
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
        case "tempo":                             return "threshold"
        default:                                  return raw
        }
    }
}

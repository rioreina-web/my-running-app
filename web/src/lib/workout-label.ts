// THE single source of truth on the web for turning a stored `workout_type`
// key into a user-facing label. A direct port of
// `RunningLog/App/WorkoutLabel.swift` — the two must stay in sync, and the
// Swift file wins any disagreement.
//
// Before this file the web had no label mapper at all: `WORKOUT_TYPE_CONFIG`
// in utils.ts carried a partial, drifted list (`tempo`, `interval`, no
// `moderate`/`threshold`/`progression`, none of the race-pace keys), the
// journal's edit dropdown carried a third list, and the coach workout page a
// fourth. Same drift the iOS side fixed on 2026-08-10 (Wave 2 · H1).
//
// TAXONOMY (2026-08-10 — supersedes the pace-zone-as-label rule):
//   Effort:      Easy · Moderate · Steady · Recovery run
//   Session:     Threshold · Intervals · Fartlek · Progression
//   Structural:  Long run · Long run workout · Cross-train · Strength ·
//                Rest · Race
//
// A PACE ZONE IS NOT A WORKOUT TYPE. MP/HMP/LT/10K/5K/3K/Mile describe the
// pace of a *segment*, not the intent of a *session*. They are no longer
// offered; rows already stored under them still render via `display()` and
// survive an edit via `optionsIncluding()`. The per-workout pace-zone label
// (auto-derived, athlete-overridable) is designed but NOT built — until it
// ships, a workout has no zone label of its own, and nothing here may invent
// one.
//
// "Tempo" is retired and folds to "Threshold" on write (`normalize`). The
// reverse fold (threshold → lt) is GONE: Threshold is a session type, LT is a
// pace zone, and collapsing them is the ambiguity that made both unreadable.

/** Stored `workout_type` key → user-facing label. Case-insensitive; tolerates
 *  historical spellings. Never returns empty — unknown keys are humanised. */
export function displayWorkoutType(workoutType: string | null | undefined): string {
  const raw = (workoutType ?? "").trim().toLowerCase();
  if (!raw) return "Run";

  switch (raw) {
    // ── Effort zones ───────────────────────────────────────────────────
    case "easy": return "Easy";
    case "moderate": return "Moderate";
    case "steady": return "Steady";
    case "recovery": return "Recovery run";

    // ── Race-pace zones (legacy as workout types; still rendered) ───────
    case "mp": return "MP";
    case "hmp": return "HMP";
    case "lt": return "LT";
    case "10k": return "10K";
    case "5k": return "5K";
    case "3k": return "3K";
    case "mile": return "Mile";

    // ── Structural ─────────────────────────────────────────────────────
    case "long_run": case "longrun": case "long": return "Long run";
    case "long_wo": case "longwo": return "Long run workout";
    case "cross_train": case "cross_training":
    case "crosstraining": case "crosstrain": return "Cross-train";
    case "strength": return "Strength";
    case "rest": return "Rest";
    case "race": return "Race";

    // ── Session types ──────────────────────────────────────────────────
    case "threshold": return "Threshold";
    case "intervals": case "interval": return "Intervals";
    case "fartlek": return "Fartlek";
    case "progression": return "Progression";

    // ── Legacy (existing rows only; not offered for new entries) ────────
    case "tempo": return "Threshold"; // folded 2026-08-10
    case "hills": return "Hills";
    case "strides": return "Strides";

    default:
      return raw
        .replace(/_/g, " ")
        .replace(/\b\w/g, (c) => c.toUpperCase());
  }
}

/** Run types offered when logging or re-typing a run (2026-08-10). Ordered by
 *  how a week actually reads: aerobic efforts, long runs, quality, then Race.
 *  Pace zones are deliberately absent. */
export const OFFERED_WORKOUT_TYPES: ReadonlyArray<readonly [string, string]> = [
  ["easy", "Easy"], ["moderate", "Moderate"], ["steady", "Steady"],
  ["long_run", "Long run"], ["long_wo", "Long run workout"],
  ["threshold", "Threshold"], ["intervals", "Intervals"],
  ["fartlek", "Fartlek"], ["recovery", "Recovery run"],
  ["progression", "Progression"], ["race", "Race"],
];

/** The offer list, plus `current` when it's a legacy value not in it — so
 *  opening an old run's picker never silently rewrites its type, while a new
 *  run only ever sees the canonical set. */
export function optionsIncluding(
  current: string | null | undefined,
): Array<readonly [string, string]> {
  const raw = (current ?? "").trim().toLowerCase();
  if (!raw || OFFERED_WORKOUT_TYPES.some(([k]) => k === raw)) {
    return [...OFFERED_WORKOUT_TYPES];
  }
  return [...OFFERED_WORKOUT_TYPES, [raw, displayWorkoutType(raw)] as const];
}

/** Fold a key to its canonical spelling before WRITING it. Collapses spellings
 *  of one concept only — it never reinterprets a workout. Anything
 *  unrecognised passes through lowercased and untouched: never invent a type
 *  the athlete didn't choose. */
export function normalizeWorkoutType(
  workoutType: string | null | undefined,
): string | null {
  const raw = (workoutType ?? "").trim().toLowerCase();
  if (!raw) return null;

  switch (raw) {
    case "interval": return "intervals";
    case "longrun": case "long": return "long_run";
    case "longwo": return "long_wo";
    case "cross_training": case "crosstraining": case "crosstrain":
      return "cross_train";
    case "tempo": return "threshold";
    default: return raw;
  }
}

/** Session types that read as quality — a prescribed band or a race still
 *  overrides this. Kept beside the taxonomy so a new session key can't be
 *  added without someone deciding which bucket it lands in. */
const QUALITY_TYPES = new Set([
  "threshold", "intervals", "interval", "tempo", "fartlek",
  "progression", "long_wo", "race",
  // Race-pace zones stored as types on legacy rows.
  "mp", "hmp", "lt", "10k", "5k", "3k", "mile",
]);

export function isQualityWorkoutType(
  workoutType: string | null | undefined,
): boolean {
  const raw = (workoutType ?? "").trim().toLowerCase();
  return raw ? QUALITY_TYPES.has(raw) : false;
}

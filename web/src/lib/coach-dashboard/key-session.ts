/**
 * Key sessions — the ONE definition, mirrored for the coach portal.
 *
 * This is the web-side twin of `Training/KeySession.swift`. The athlete and
 * their coach looking at the same Tuesday and seeing different answers is the
 * exact failure this replaces, so these two files must stay in lockstep. There
 * is a fixture test pinning them together.
 *
 *      athlete override   (day_overrides.is_key_session)
 *            ↓ falls through to
 *      plan intent        (scheduled_workouts.is_key_session)
 *            ↓ falls through to
 *      derived            (Σ workout_features.quality_load ≥ FLOOR)
 *
 * First non-null wins.
 *
 * WHAT THIS REPLACED, and why none of it comes back: the coach dashboard used
 * to decide a day was key if any run's workout_type was in a hand-written set,
 * OR any run was ≥ 12 miles, OR the day carried ≥ 2.5 "quality" miles. Three
 * clauses, a fourth vocabulary of type spellings, and two constants that
 * existed nowhere else in the codebase. It was the closest of the four old
 * rules to right — it was just wearing arbitrary numbers.
 */

/**
 * Weighted minutes below which a session is real work but not a key session.
 *
 * Mirrors `QualityLoad.floor` in TrendsQualityLoad.swift. Calibrated on 23
 * real lap-scored sessions (2026-07-27): stride sets score 5.4–13.1, the
 * smallest genuine session 42.1, and the gap between is empty. It sits
 * mid-gap, and it is now overridable anyway.
 */
export const QUALITY_LOAD_FLOOR = 25;

export type KeySessionProvenance = "auto" | "planned" | "athlete";

export interface KeySessionInputs {
  /** day_overrides. null/undefined = nothing said. false = explicitly NOT key. */
  override?: boolean | null;
  /** scheduled_workouts.is_key_session. Same three states. */
  planIntent?: boolean | null;
  /** Σ quality_load for the day, or null/undefined when nothing was scored. */
  dayLoad?: number | null;
  /** A day that hasn't happened yet. */
  isFuture?: boolean;
}

/**
 * Is this day a key session? First non-null wins — no blending.
 *
 * Future days: the derived rule never applies (there is no run to score), but
 * a declaration does. A Tuesday marked key shows before it is run.
 */
export function isKeySession(inputs: KeySessionInputs): boolean {
  const { override, planIntent, dayLoad, isFuture = false } = inputs;
  if (override !== null && override !== undefined) return override;
  if (planIntent !== null && planIntent !== undefined) return planIntent;
  if (isFuture) return false;
  // A null load means "not scored", not "scored at zero". Never fall back to a
  // looser rule here — a missing star is honest, a wrong star is the bug.
  if (dayLoad === null || dayLoad === undefined) return false;
  return dayLoad >= QUALITY_LOAD_FLOOR;
}

/**
 * Which level decided — regardless of whether the levels agree. A day the
 * athlete marked key that also derives as key is still "athlete": the mark is
 * a fact about intent and shouldn't disappear because the app agreed.
 */
export function keySessionProvenance(
  inputs: Pick<KeySessionInputs, "override" | "planIntent">,
): KeySessionProvenance {
  if (inputs.override !== null && inputs.override !== undefined) return "athlete";
  if (inputs.planIntent !== null && inputs.planIntent !== undefined) return "planned";
  return "auto";
}

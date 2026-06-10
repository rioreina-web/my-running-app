/**
 * Pace-resolution utilities used by plan-generating edge functions to convert
 * LLM-emitted step shapes into concrete `target_pace_seconds_per_mile` values
 * before writing to the database.
 *
 * Resolution precedence per step:
 *   1. If `target_pace_seconds_per_mile` is already set, trust it and stamp
 *      `resolved_from_snapshot_id` + `resolved_at`.
 *   2. Else if `pace_reference` is set (one of: easy/marathon/half/10K/5K/mile),
 *      look up that pace on the athlete's AthletePaceProfile.
 *   3. Else if legacy `paceSecondsPerKm` is set, convert km→mile.
 *   4. Else if legacy `pacePercentage` is set, compute against the athlete's
 *      goal race pace from the profile.
 *   5. Else leave the step alone — downstream code decides.
 *
 * The profile may be null (user has no fitness_snapshot yet). In that case
 * only precedence (3) resolves — references and percentages pass through
 * untouched. New plan-gen callers should surface "set your goal to see
 * paces" UX in that situation rather than invent numbers.
 */

import { computePaceProfile, type FitnessSnapshotInput } from "./pace-zones.ts";
import { applyPaceAdjustment, readPaceAdjustment, type ConfirmedRace } from "./paces.ts";

export interface PaceProfileRow {
  based_on_snapshot_id: string | null;
  goal_race_distance: string | null;
  easy_pace_seconds: number | null;
  marathon_pace_seconds: number | null;
  half_pace_seconds: number | null;
  ten_k_pace_seconds: number | null;
  five_k_pace_seconds: number | null;
  mile_pace_seconds: number | null;
}

export interface ResolvablePaceStep {
  stepType?: string;
  pacePercentage?: number | null;
  paceSecondsPerKm?: number | null;
  paceSecondsPerKmHigh?: number | null;
  pace_reference?: string | null;
  paceAdjustment?: { type: string; value: number } | null;
  target_pace_seconds_per_mile?: number | null;
  target_pace_seconds_high?: number | null;
  resolved_from_snapshot_id?: string | null;
  resolved_at?: string | null;
  [key: string]: unknown;
}

/** Looks up a single named pace on an AthletePaceProfile row. */
export function paceForReference(
  profile: PaceProfileRow | null,
  ref: string | null | undefined
): number | null {
  if (!profile || !ref) return null;
  switch (ref.toLowerCase()) {
    case "easy":     return profile.easy_pace_seconds;
    case "marathon": return profile.marathon_pace_seconds;
    case "half":     return profile.half_pace_seconds;
    case "10k":      return profile.ten_k_pace_seconds;
    case "5k":       return profile.five_k_pace_seconds;
    case "mile":     return profile.mile_pace_seconds;
    default:         return null;
  }
}

/** Resolve a single step. Returns a new object; never mutates input. */
export function resolveStepPace(
  step: ResolvablePaceStep,
  profile: PaceProfileRow | null
): ResolvablePaceStep {
  const stamp = (extra: Partial<ResolvablePaceStep>): ResolvablePaceStep => ({
    ...step,
    ...extra,
    resolved_from_snapshot_id: profile?.based_on_snapshot_id ?? null,
    resolved_at: new Date().toISOString(),
  });

  // 1. LLM already gave an explicit seconds value — trust it.
  if (typeof step.target_pace_seconds_per_mile === "number") {
    return stamp({});
  }

  // 2. LLM emitted a pace_reference — look it up and apply any paceAdjustment
  //    ("MP −1%", "+10s/mi") on top of the base zone pace.
  if (step.pace_reference && profile) {
    const seconds = paceForReference(profile, step.pace_reference);
    if (seconds != null) {
      const adjusted = applyPaceAdjustment(seconds, readPaceAdjustment(step.paceAdjustment));
      return stamp({
        target_pace_seconds_per_mile: Math.round(adjusted * 10) / 10,
      });
    }
  }

  // 3. Legacy km pace — convert.
  if (typeof step.paceSecondsPerKm === "number" && step.paceSecondsPerKm > 0) {
    const sec = Math.round(step.paceSecondsPerKm * 1.609344 * 10) / 10;
    const sec_high = typeof step.paceSecondsPerKmHigh === "number" && step.paceSecondsPerKmHigh > 0
      ? Math.round(step.paceSecondsPerKmHigh * 1.609344 * 10) / 10
      : null;
    return stamp({
      target_pace_seconds_per_mile: sec,
      ...(sec_high != null ? { target_pace_seconds_high: sec_high } : {}),
    });
  }

  // 4. Legacy percentage — scale against profile's goal race pace.
  if (typeof step.pacePercentage === "number" && step.pacePercentage > 0 && profile) {
    const goalPace = paceForReference(profile, profile.goal_race_distance) ?? profile.marathon_pace_seconds;
    if (goalPace != null) {
      const sec = Math.round(goalPace * (100.0 / step.pacePercentage) * 10) / 10;
      return stamp({ target_pace_seconds_per_mile: sec });
    }
  }

  // 5. Nothing resolvable — return unchanged.
  return step;
}

/** Deep-resolve every step in an array of steps. */
export function resolveSteps(
  steps: ResolvablePaceStep[],
  profile: PaceProfileRow | null
): ResolvablePaceStep[] {
  return steps.map((s) => resolveStepPace(s, profile));
}

/** Fetch the caller's AthletePaceProfile row. If it doesn't exist yet, try to
 * build one on the fly from the latest fitness_snapshots row. Returns null if
 * the user has no fitness data at all — callers should fall through gracefully.
 */
// deno-lint-ignore no-explicit-any
export async function getOrBuildPaceProfile(supabase: any, userId: string): Promise<PaceProfileRow | null> {
  const { data: existing } = await supabase
    .from("athlete_pace_profiles")
    .select(
      "based_on_snapshot_id, goal_race_distance, easy_pace_seconds, marathon_pace_seconds, half_pace_seconds, ten_k_pace_seconds, five_k_pace_seconds, mile_pace_seconds"
    )
    .eq("user_id", userId)
    .maybeSingle();
  if (existing) return existing as PaceProfileRow;

  // No profile yet — try to synthesize one from the latest snapshot.
  const { data: snap } = await supabase
    .from("fitness_snapshots")
    .select("*")
    .eq("user_id", userId)
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (!snap) return null;

  const computed = computePaceProfile(snap as FitnessSnapshotInput);
  if (!computed) return null;

  const row: PaceProfileRow = {
    based_on_snapshot_id: snap.id,
    goal_race_distance: null,
    easy_pace_seconds: computed.easy?.secondsPerMile ?? null,
    marathon_pace_seconds: computed.marathon?.secondsPerMile ?? null,
    half_pace_seconds: computed.half?.secondsPerMile ?? null,
    ten_k_pace_seconds: computed.tenK?.secondsPerMile ?? null,
    five_k_pace_seconds: computed.fiveK?.secondsPerMile ?? null,
    mile_pace_seconds: computed.mile?.secondsPerMile ?? null,
  };
  return row;
}

/** Fetch the athlete's confirmed races from athlete_state (the derived
 * cache populated by rebuildAthleteState from training_logs.race_result —
 * Phase 2 sub-task A). Returns null when the cache is empty or the state
 * row doesn't exist, so callers can pass the result straight into
 * `paceTableFromProfile(profile, confirmedRaces)` and fall through to the
 * profile/goal anchor. Phase 2 sub-task C — see
 * outputs/phase-2-race-anchoring-plan-2026-06-04.md.
 */
// deno-lint-ignore no-explicit-any
export async function getConfirmedRaces(supabase: any, userId: string): Promise<ConfirmedRace[] | null> {
  const { data } = await supabase
    .from("athlete_state")
    .select("confirmed_races")
    .eq("user_id", userId)
    .maybeSingle();
  const races = data?.confirmed_races;
  return Array.isArray(races) && races.length > 0 ? (races as ConfirmedRace[]) : null;
}

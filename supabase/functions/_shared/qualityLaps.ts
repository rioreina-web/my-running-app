/**
 * Quality laps — the single fetch path for rep-level laps, shared by every
 * Trends surface so they can't disagree.
 *
 * Returns laps by workout id, resolved from the best-available source in one
 * place:
 *   1. `running_workout_laps` — native (Strava) or stream-derived (Garmin via
 *      the `derivedLapsFromStream` path in `vital-webhook`).
 *   2. Fix-reps override — where the athlete CORRECTED a workout's structure
 *      (`parsed_structure.edited_by_user`), the correction is the verdict and
 *      replaces that workout's laps everywhere the ladder / key sessions /
 *      quality volume / weekly key pace read.
 *
 * Kept out of any one endpoint so `trends-timeline` and `trends-insights` build
 * the SAME quality substrate — the weekly `key_pace_sec` A3 trends on must be
 * the rep pace (5:10), not the whole-workout blend (6:20), in both.
 */

import { lapsFromParsedStructure } from "./shared/workBouts.ts";
import type { KeySessionLap } from "../trends-timeline/keySessions.ts";

/** Minimal shape of the Supabase client this module needs. */
// deno-lint-ignore no-explicit-any
type Db = { from: (table: string) => any };

const LAP_COLS =
  "workout_id, lap_index, is_rest, distance_meters, avg_pace_sec_per_mile, moving_time_seconds, elapsed_time_seconds, avg_heart_rate, max_heart_rate, total_elevation_gain, stream_start_index, stream_end_index, heat_adjusted_pace_sec_per_mile, heat_category";

/**
 * Laps by workout id for the given workouts, native/derived then corrected.
 * Chunked to keep the IN list sane. Additive: any query failure just yields
 * fewer laps, never throws.
 */
export async function fetchQualityLaps(
  db: Db,
  userId: string,
  workoutIds: string[],
): Promise<Map<string, KeySessionLap[]>> {
  const byId = new Map<string, KeySessionLap[]>();
  if (workoutIds.length === 0) return byId;

  for (let i = 0; i < workoutIds.length; i += 200) {
    const chunk = workoutIds.slice(i, i + 200);
    const { data, error } = await db
      .from("running_workout_laps")
      .select(LAP_COLS)
      .eq("user_id", userId)
      .in("workout_id", chunk)
      .order("lap_index", { ascending: true });
    if (error) continue;
    for (const lap of (data ?? []) as Array<Record<string, unknown>>) {
      const wid = String(lap.workout_id);
      const arr = byId.get(wid) ?? [];
      arr.push(lap as unknown as KeySessionLap);
      byId.set(wid, arr);
    }
  }

  await applyCorrectedStructures(db, userId, workoutIds, byId);
  return byId;
}

/**
 * Fix-reps: replace the laps of any workout the athlete corrected
 * (`parsed_structure.edited_by_user`) with laps rebuilt from that correction.
 * Only the edited rows are fetched; a failure leaves existing laps in place.
 *
 * The rebuilt laps carry no weather — `parsed_structure` records what the
 * athlete ran, not the conditions she ran it in. So we lift the heat ratio off
 * the native laps we are about to discard and re-apply it. Without this, every
 * corrected workout reports a zero correction and Pace Bands says "no
 * correction on file" about a session that has one on file.
 */
async function applyCorrectedStructures(
  db: Db,
  userId: string,
  workoutIds: string[],
  byId: Map<string, KeySessionLap[]>,
): Promise<void> {
  for (let i = 0; i < workoutIds.length; i += 200) {
    const chunk = workoutIds.slice(i, i + 200);
    const { data, error } = await db
      .from("training_logs")
      .select("id, parsed_structure")
      .eq("user_id", userId)
      .in("id", chunk)
      .filter("parsed_structure->>edited_by_user", "eq", "true");
    if (error) continue;
    for (const row of (data ?? []) as Array<{ id: string; parsed_structure: unknown }>) {
      const laps = lapsFromParsedStructure(row.parsed_structure);
      if (!laps.length) continue;
      const ratio = heatRatioOf(byId.get(String(row.id)));
      const carried = ratio == null ? laps : laps.map((l) => withHeat(l, ratio));
      byId.set(String(row.id), carried as unknown as KeySessionLap[]);
    }
  }
}

/**
 * adjusted ÷ raw for a workout, taken from whichever native lap carries both.
 * Uniform across a session — one weather snapshot per workout — so the first
 * usable lap answers for all of them. Null when no lap had weather; the caller
 * then leaves the rebuilt laps unadjusted, which is the honest result.
 */
function heatRatioOf(original: KeySessionLap[] | undefined): number | null {
  for (const l of original ?? []) {
    const raw = Number((l as { avg_pace_sec_per_mile?: number | null }).avg_pace_sec_per_mile);
    const adj = Number(
      (l as { heat_adjusted_pace_sec_per_mile?: number | null }).heat_adjusted_pace_sec_per_mile,
    );
    if (Number.isFinite(raw) && raw > 0 && Number.isFinite(adj) && adj > 0) return adj / raw;
  }
  return null;
}

/** A rebuilt lap with the workout's heat ratio applied to its own raw pace. */
function withHeat<T>(lap: T, ratio: number): T {
  if ((lap as { is_rest?: boolean | null }).is_rest === true) return lap;
  const raw = Number((lap as { avg_pace_sec_per_mile?: number | null }).avg_pace_sec_per_mile);
  if (!Number.isFinite(raw) || raw <= 0) return lap;
  return { ...lap, heat_adjusted_pace_sec_per_mile: Math.round(raw * ratio) };
}

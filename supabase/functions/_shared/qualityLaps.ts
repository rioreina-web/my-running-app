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
      if (laps.length) byId.set(String(row.id), laps as unknown as KeySessionLap[]);
    }
  }
}

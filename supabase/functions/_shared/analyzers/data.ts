/**
 * Shared row fetchers for the analyzer registry.
 *
 * These are data adapters, not math — they exist so an analyzer file stays
 * about the question it answers rather than about `select` strings. The
 * lap/candidate/zone helpers mirror the private ones inside
 * `compare-workouts/index.ts`; when that function is folded into the registry
 * it should import from here and delete its copies.
 *
 * Every query is scoped `.eq("user_id", ctx.userId)`. There is no code path in
 * this directory that reads another athlete's rows — the R3 tenant-leak class
 * of bug (HOTFIX-H.1) does not get to happen twice.
 */

import type {
  ComparisonLap,
  ComparisonWorkout,
} from "../workoutComparison.ts";
import type { PaceZones } from "../workoutSegmentation.ts";
import type { ZoneTable } from "../quality-volume.ts";
import type { SupabaseLike } from "./types.ts";

export const LAP_COLUMNS =
  "workout_id, lap_index, is_rest, distance_meters, avg_pace_sec_per_mile, moving_time_seconds, elapsed_time_seconds, avg_heart_rate, max_heart_rate, heat_adjusted_pace_sec_per_mile, heat_category, total_elevation_gain";

export const FEATURE_COLUMNS =
  "training_log_id, workout_date, total_distance_miles, avg_pace_seconds, total_duration_seconds, easy_seconds, moderate_seconds, threshold_seconds, hard_seconds, intensity_score, monotony_7d, strain_7d, acwr, avg_heart_rate, workout_structure";

export interface LogRow {
  id: string;
  workout_date: string;
  workout_distance_miles: number | null;
  workout_duration_minutes: number | null;
  workout_type: string | null;
  weather_actual: Record<string, unknown> | null;
}

export interface FeatureRow {
  training_log_id: string;
  workout_date: string;
  total_distance_miles: number | null;
  avg_pace_seconds: number | null;
  total_duration_seconds: number | null;
  easy_seconds: number | null;
  moderate_seconds: number | null;
  threshold_seconds: number | null;
  hard_seconds: number | null;
  intensity_score: number | null;
  monotony_7d: number | null;
  strain_7d: number | null;
  acwr: number | null;
  avg_heart_rate: number | null;
  workout_structure: string | null;
}

export const LOG_COLUMNS =
  "id, workout_date, workout_distance_miles, workout_duration_minutes, workout_type, weather_actual";

/**
 * Athlete pace zones from `athlete_state`, in both flavours the downstream
 * modules want. Same graceful degradation as `compute-workout-features`:
 * a missing zone is `undefined`, never a guessed default — an analyzer that
 * needs MP and doesn't have it must return an empty state, not invent one.
 *
 * `lt` is derived, not stored: `athlete_state.pace_zones` carries the ten
 * canonical zones under `hm`/`hmp`, and `ZoneTable.lt` is what
 * `fast-segment-trends` bins against. We read it if present and fall back to
 * the stored threshold key rather than recomputing the one-hour pace here —
 * `pace-engine.ts` owns that math (CLAUDE.md, pace zones).
 */
export async function fetchZones(
  supabase: SupabaseLike,
  userId: string,
): Promise<{ zones: PaceZones; zoneTable: ZoneTable }> {
  const { data } = await supabase
    .from("athlete_state")
    .select("pace_zones")
    .eq("user_id", userId)
    .maybeSingle();

  const z = (data?.pace_zones ?? {}) as Record<string, unknown>;
  const num = (v: unknown): number | undefined =>
    typeof v === "number" && v > 0 ? v : undefined;

  const zones: PaceZones = {
    mile: num(z.mile),
    fiveK: num(z.fiveK),
    threeK: num(z.threeK),
    tenK: num(z.tenK),
    hm: num(z.hm) ?? num(z.hmp),
    mp: num(z.mp),
    steady: num(z.steady),
    moderate: num(z.moderate),
    easy: num(z.easy),
  };

  const zoneTable: ZoneTable = {
    mile: zones.mile ?? undefined,
    fiveK: zones.fiveK ?? undefined,
    threeK: zones.threeK ?? undefined,
    tenK: zones.tenK ?? undefined,
    hm: zones.hm ?? undefined,
    lt: num(z.lt) ?? num(z.threshold) ?? undefined,
    mp: zones.mp ?? undefined,
    steady: zones.steady ?? undefined,
    moderate: zones.moderate ?? undefined,
    easy: zones.easy ?? undefined,
  };

  return { zones, zoneTable };
}

/** Laps for a set of workouts, grouped by workout_id (chunked IN lists). */
export async function fetchLapsByWorkout(
  supabase: SupabaseLike,
  userId: string,
  workoutIds: string[],
): Promise<Map<string, ComparisonLap[]>> {
  const byId = new Map<string, ComparisonLap[]>();
  if (workoutIds.length === 0) return byId;

  for (let i = 0; i < workoutIds.length; i += 200) {
    const chunk = workoutIds.slice(i, i + 200);
    const { data, error } = await supabase
      .from("running_workout_laps")
      .select(LAP_COLUMNS)
      .eq("user_id", userId)
      .in("workout_id", chunk)
      .order("lap_index", { ascending: true });
    if (error) throw new Error(`Failed to fetch laps: ${error.message}`);
    for (const lap of (data ?? []) as Array<Record<string, unknown>>) {
      const wid = String(lap.workout_id);
      const arr = byId.get(wid) ?? [];
      arr.push(lap as ComparisonLap);
      byId.set(wid, arr);
    }
  }
  return byId;
}

/** Training logs in a trailing window, newest first. */
export async function fetchLogsSince(
  supabase: SupabaseLike,
  userId: string,
  sinceISO: string,
  limit = 400,
): Promise<LogRow[]> {
  const { data, error } = await supabase
    .from("training_logs")
    .select(LOG_COLUMNS)
    .eq("user_id", userId)
    .gte("workout_date", sinceISO)
    .order("workout_date", { ascending: false })
    .limit(limit);
  if (error) throw new Error(`Failed to fetch training logs: ${error.message}`);
  return (data ?? []) as LogRow[];
}

export async function fetchLogById(
  supabase: SupabaseLike,
  userId: string,
  id: string,
): Promise<LogRow | null> {
  const { data, error } = await supabase
    .from("training_logs")
    .select(LOG_COLUMNS)
    .eq("user_id", userId)
    .eq("id", id)
    .maybeSingle();
  if (error) throw new Error(`Failed to fetch workout: ${error.message}`);
  return (data ?? null) as LogRow | null;
}

export async function fetchFeaturesSince(
  supabase: SupabaseLike,
  userId: string,
  sinceISO: string,
  limit = 400,
): Promise<FeatureRow[]> {
  const { data, error } = await supabase
    .from("workout_features")
    .select(FEATURE_COLUMNS)
    .eq("user_id", userId)
    .gte("workout_date", sinceISO)
    .order("workout_date", { ascending: false })
    .limit(limit);
  if (error) throw new Error(`Failed to fetch workout features: ${error.message}`);
  return (data ?? []) as FeatureRow[];
}

export async function fetchFeaturesByLogIds(
  supabase: SupabaseLike,
  userId: string,
  logIds: string[],
): Promise<Map<string, FeatureRow>> {
  const out = new Map<string, FeatureRow>();
  if (logIds.length === 0) return out;
  for (let i = 0; i < logIds.length; i += 200) {
    const chunk = logIds.slice(i, i + 200);
    const { data } = await supabase
      .from("workout_features")
      .select(FEATURE_COLUMNS)
      .eq("user_id", userId)
      .in("training_log_id", chunk);
    for (const row of (data ?? []) as FeatureRow[]) {
      out.set(String(row.training_log_id), row);
    }
  }
  return out;
}

/** Map a log row + its laps into the comparison engine's input shape. */
export function toComparisonWorkout(
  log: LogRow,
  laps: ComparisonLap[] | undefined,
  structureLabel?: string | null,
): ComparisonWorkout {
  const wx = log.weather_actual;
  return {
    id: log.id,
    workout_date: log.workout_date,
    laps: laps ?? [],
    weather: wx && typeof wx === "object"
      ? {
        temp_f: typeof wx.temp_f === "number" ? wx.temp_f : null,
        dew_point_f: typeof wx.dew_point_f === "number" ? wx.dew_point_f : null,
        heat_category: typeof wx.heat_category === "string" ? wx.heat_category : null,
      }
      : null,
    structure_label: structureLabel ?? null,
  };
}

/** Weather for `fast-segment-trends`, keyed by log id. */
export function weatherFromLog(
  log: LogRow,
): { tempF: number; dewPointF: number } | null {
  const wx = log.weather_actual;
  if (!wx || typeof wx !== "object") return null;
  const t = wx.temp_f;
  const d = wx.dew_point_f;
  if (typeof t !== "number" || typeof d !== "number") return null;
  return { tempF: t, dewPointF: d };
}

/** ISO timestamp N days before `now`. */
export function daysAgoISO(now: Date, days: number): string {
  return new Date(now.getTime() - days * 86400000).toISOString();
}

/** Monday 00:00 of the week containing `d`, in UTC. */
export function weekStart(d: Date): Date {
  const out = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()));
  const day = out.getUTCDay(); // 0=Sun
  out.setUTCDate(out.getUTCDate() - (day === 0 ? 6 : day - 1));
  return out;
}

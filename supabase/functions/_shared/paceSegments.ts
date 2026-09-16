/**
 * paceSegments.ts — the one definition of what a `training_logs.pace_segments`
 * row is, and where it comes from.
 *
 * ## Why this file exists (Rio, 2026-08-20)
 *
 * `pace_segments` was built from Strava's `splits_standard` — plain per-MILE
 * autolap splits. On an easy run that is fine: a mile split of a steady run is
 * a fair sample of that mile. On a quality day it is actively wrong, because
 * one mile of an interval session contains work AND the jog between reps, and
 * the split reports their blend.
 *
 * The damage was measured on the Trends pace spectrum (`SignalService`), which
 * buckets miles by `pace_segments` pace. Over a real 4-week window it credited
 * 1.6 mi at 5:12–5:22/mi across the whole window, while ONE Tuesday session
 * (2026-08-18) actually held 1.37 mi in that band — the mile splits recorded
 * that session as 5:24 / 5:29 / 5:34 / 5:33, one to two buckets slow, and the
 * fast tail of the chart collapsed. Meanwhile the Threshold Miles card, which
 * reads `running_workout_laps` instead, reported 21 mi in the HM band from the
 * same runs. Two surfaces, one screen apart, disagreeing — because they read
 * two different segment definitions.
 *
 * This is the same root cause as the MILE-SPLIT GUARD in `coach-context.ts`
 * (2026-08-06), which stopped the LLM narrating mile splits as "4×1 mile reps".
 * That guard treated the symptom at the read side. This treats the cause at
 * the write side.
 *
 * ## What changed
 *
 * Strava already gives us `laps` — the watch's own lap structure, which on a
 * quality day IS the rep structure (a 6×1mi session arrives as six ~1.01 mi
 * laps at 5:18–5:36 with 0.08–0.10 mi standing rests between them). We already
 * store those verbatim in `external_streams.laps`, and a trigger already fans
 * them into `running_workout_laps`. `pace_segments` was the one consumer still
 * reading the coarse splits.
 *
 * So: **laps win, splits are the fallback.** Splits are still used when a lap
 * array is absent (manual entries, some devices) or unusable, so nothing that
 * synced fine before starts failing.
 *
 * ## The rest rule is NOT re-invented here
 *
 * `running_workout_laps.is_rest` is a GENERATED column:
 *     distance_meters < 200 OR avg_speed_mps < 2.0
 * `isRestLap()` below mirrors that expression exactly, on purpose. If the
 * generated column is ever retuned, retune it here in the same migration —
 * two rest definitions is the contradiction this file exists to end.
 *
 * Pure functions only (repo convention): no I/O, no Deno globals, so
 * `paceSegments.test.ts` can drive them off recorded fixtures.
 */

export const METERS_PER_MILE = 1609.34;

/** Strava's per-mile split shape (`splits_standard`). */
export interface StravaSplitLike {
  distance: number;
  moving_time: number;
  average_speed: number;
  elapsed_time?: number;
  average_heartrate?: number;
  split?: number;
}

/** Strava's lap shape. Only the fields we actually read are required. */
export interface StravaLapLike {
  lap_index?: number;
  distance?: number;
  moving_time?: number;
  elapsed_time?: number;
  average_speed?: number;
  average_heartrate?: number;
  max_heartrate?: number;
}

/** A `training_logs.pace_segments` row. Wire shape — snake_case on purpose. */
export interface PaceSegment {
  effort: string;
  distance_miles: number;
  duration_seconds: number;
  pace_per_mile: string;
  avg_heart_rate: number | null;
}

export function paceStringFromSpeedMps(speedMps: number): string {
  if (!speedMps || speedMps <= 0) return "";
  return paceStringFromSec(METERS_PER_MILE / speedMps);
}

export function paceStringFromSec(secPerMile: number): string {
  if (!Number.isFinite(secPerMile) || secPerMile <= 0) return "";
  const m = Math.floor(secPerMile / 60);
  const s = Math.round(secPerMile % 60);
  // 5:60 is not a pace. Carry the rounding into the minute.
  if (s === 60) return `${m + 1}:00`;
  return `${m}:${String(s).padStart(2, "0")}`;
}

export function classifyEffort(paceSec: number, avgPaceSec: number): string {
  if (!avgPaceSec) return "steady";
  const ratio = paceSec / avgPaceSec;
  if (ratio < 0.92) return "fast";
  if (ratio > 1.08) return "easy";
  return "steady";
}

/**
 * Mirror of `running_workout_laps.is_rest` (generated column, see the migration
 * `20260528222123_create_running_workout_laps.sql`):
 *     distance_meters < 200 OR avg_speed_mps < 2.0
 *
 * Catches standing rests (<200 m) and walks (<2 m/s ≈ 13:00/mi — well outside
 * any running pace). Deliberately absolute, never relative to the athlete's
 * own pace, so it reads the same for a 5:00/mi runner and a 12:00/mi runner.
 */
export function isRestLap(distanceMeters: number, avgSpeedMps: number): boolean {
  return distanceMeters < 200 || avgSpeedMps < 2.0;
}

/** Per-mile splits → segments. The pre-2026-08-20 behaviour, kept as fallback. */
export function splitsToPaceSegments(
  splits: StravaSplitLike[],
  avgSpeedMps: number,
): PaceSegment[] {
  const avgPaceSec = avgSpeedMps > 0 ? METERS_PER_MILE / avgSpeedMps : 0;
  return splits.map((s) => {
    const paceSec = s.average_speed > 0 ? METERS_PER_MILE / s.average_speed : 0;
    return {
      effort: classifyEffort(paceSec, avgPaceSec),
      distance_miles: Number((s.distance / METERS_PER_MILE).toFixed(2)),
      duration_seconds: Number(s.moving_time),
      pace_per_mile: paceStringFromSpeedMps(s.average_speed),
      avg_heart_rate: s.average_heartrate ? Math.round(s.average_heartrate) : null,
    };
  });
}

/**
 * Watch laps → segments. The good path.
 *
 * Pace is derived from `moving_time / distance` rather than trusting
 * `average_speed`, because the two disagree on paused laps and moving time is
 * what every downstream pace read already assumes.
 *
 * Rest laps are KEPT, tagged `effort: "recovery"`, never dropped. Dropping
 * them would make the segment distances stop summing to the run distance, and
 * the pace spectrum sums segment miles — silently losing a tenth of a mile per
 * rep is how a histogram starts lying in the other direction. Downstream
 * readers that only want work laps filter on the effort tag.
 */
export function lapsToPaceSegments(
  laps: StravaLapLike[],
  avgSpeedMps: number,
): PaceSegment[] {
  const avgPaceSec = avgSpeedMps > 0 ? METERS_PER_MILE / avgSpeedMps : 0;
  const out: PaceSegment[] = [];
  for (const l of laps) {
    const meters = Number(l.distance ?? 0);
    const movingSec = Number(l.moving_time ?? 0);
    if (!Number.isFinite(meters) || meters <= 0) continue;
    if (!Number.isFinite(movingSec) || movingSec <= 0) continue;
    const distMi = meters / METERS_PER_MILE;
    const paceSec = movingSec / distMi;
    // Prefer the lap's own reported speed for the rest test (it is what the
    // generated column sees); fall back to the derived one.
    const speedMps = Number(l.average_speed ?? 0) > 0
      ? Number(l.average_speed)
      : meters / movingSec;
    out.push({
      effort: isRestLap(meters, speedMps) ? "recovery" : classifyEffort(paceSec, avgPaceSec),
      distance_miles: Number(distMi.toFixed(2)),
      duration_seconds: movingSec,
      pace_per_mile: paceStringFromSec(paceSec),
      avg_heart_rate: l.average_heartrate ? Math.round(l.average_heartrate) : null,
    });
  }
  return out;
}

/**
 * Are these laps worth preferring over the mile splits?
 *
 * Rejects the two shapes that make laps worse than splits:
 *   • A single lap — that is just the whole run again, so mile splits carry
 *     strictly more information.
 *   • Laps that do not account for the run — a partially-lapped activity would
 *     under-report volume, and volume is load-bearing everywhere. 80% is
 *     slack for GPS drift and the usual trailing metres, not for gaps.
 *
 * `activityDistanceMeters <= 0` (unknown) skips the coverage test rather than
 * failing it: better a lapped read than a hard fallback on a missing field.
 */
export function lapsAreUsable(
  laps: StravaLapLike[] | null | undefined,
  activityDistanceMeters: number,
): boolean {
  if (!Array.isArray(laps) || laps.length < 2) return false;
  const covered = laps.reduce((sum, l) => {
    const m = Number(l.distance ?? 0);
    return sum + (Number.isFinite(m) && m > 0 ? m : 0);
  }, 0);
  if (covered <= 0) return false;
  if (!Number.isFinite(activityDistanceMeters) || activityDistanceMeters <= 0) return true;
  return covered >= activityDistanceMeters * 0.8;
}

/**
 * The entry point sync callers should use: laps when they are usable, mile
 * splits otherwise, `null` when the activity carries neither.
 */
export function buildPaceSegments(detail: {
  laps?: StravaLapLike[] | null;
  splits_standard?: StravaSplitLike[] | null;
  average_speed?: number | null;
  distance?: number | null;
}): PaceSegment[] | null {
  const avgSpeed = Number(detail.average_speed ?? 0);
  const activityMeters = Number(detail.distance ?? 0);
  if (lapsAreUsable(detail.laps, activityMeters)) {
    const fromLaps = lapsToPaceSegments(detail.laps as StravaLapLike[], avgSpeed);
    if (fromLaps.length > 0) return fromLaps;
  }
  const splits = detail.splits_standard;
  if (Array.isArray(splits) && splits.length > 0) {
    return splitsToPaceSegments(splits, avgSpeed);
  }
  return null;
}

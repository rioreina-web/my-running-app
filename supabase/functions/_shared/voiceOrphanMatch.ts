/**
 * Pure matcher: given a just-synced run and a set of telemetry-less voice_log
 * "orphan" candidates for the same athlete, pick the one that most likely
 * describes this run (or null when none is close enough).
 *
 * Why fuzzy (time + distance) rather than an id join: the orphan is created
 * BEFORE the run syncs, so it carries no vital_workout_id to join on — only
 * the workout_date/distance the athlete stated when recording the memo. Those
 * are copied from the picker's selectedWorkout, so they land within a few
 * minutes and a few tenths of a mile of the real run.
 *
 * Kept pure (no DB) so the matching thresholds are unit-testable in isolation.
 */

export interface OrphanCandidate {
  id: string;
  workout_date: string | null;             // ISO timestamp
  workout_distance_miles: number | null;
}

export interface RunRef {
  workout_date: string;                     // ISO timestamp (Strava a.start_date)
  workout_distance_miles: number;
}

/** ±4h: a voice memo for a run is recorded the same session, never a day off. */
export const ORPHAN_TIME_WINDOW_MS = 4 * 60 * 60 * 1000;
/** Distance tolerance — the looser of 0.5 mi or 8% (the memo distance is an
 *  athlete estimate, e.g. "about 4" vs a measured 4.04). */
export const ORPHAN_DIST_ABS_MI = 0.5;
export const ORPHAN_DIST_PCT = 0.08;

/**
 * Best orphan for `run`, or null. Candidates outside the time window or
 * distance tolerance are rejected; survivors rank by closest time, then
 * closest distance.
 */
export function pickBestOrphan(
  run: RunRef,
  candidates: OrphanCandidate[],
): OrphanCandidate | null {
  const runT = Date.parse(run.workout_date);
  const runD = run.workout_distance_miles;
  if (Number.isNaN(runT) || !(runD > 0)) return null;

  const tol = Math.max(ORPHAN_DIST_ABS_MI, runD * ORPHAN_DIST_PCT);
  const scored: { c: OrphanCandidate; dt: number; dd: number }[] = [];
  for (const c of candidates) {
    if (c.workout_date == null || c.workout_distance_miles == null) continue;
    const t = Date.parse(c.workout_date);
    if (Number.isNaN(t)) continue;
    const dt = Math.abs(t - runT);
    const dd = Math.abs(c.workout_distance_miles - runD);
    if (dt > ORPHAN_TIME_WINDOW_MS || dd > tol) continue;
    scored.push({ c, dt, dd });
  }
  scored.sort((a, b) => a.dt - b.dt || a.dd - b.dd);
  return scored.length ? scored[0].c : null;
}

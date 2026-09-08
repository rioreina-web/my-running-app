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
  /** Row insert time. Fallback clock when `workout_date` is NULL — see
   *  `candidateTime` below. Optional so existing callers still type-check. */
  created_at?: string | null;
}

/**
 * The timestamp to match a candidate on: its stated workout_date, or — when
 * that is NULL — the moment the row was written.
 *
 * Why the fallback exists: iOS only copied `workout_date` onto a memo row when
 * the athlete had picked a run in the recorder. Record a memo with nothing
 * selected and the row landed NULL-dated, which no range predicate can ever
 * match — so the memo could never be reconciled with the run it described
 * (2026-08-24: a 10-mile memo stranded beside that morning's Strava 10.01).
 * iOS now always stamps a date, but rows written before that fix, and any
 * future writer that forgets, still need to reconcile. `created_at` is a sound
 * proxy for WHEN, but a much weaker one than a stated date — see the asymmetric
 * window below.
 *
 * Returns the timestamp and whether it came from the fallback.
 */
export function candidateTime(c: OrphanCandidate): { t: number; stated: boolean } {
  const stated = c.workout_date == null ? NaN : Date.parse(c.workout_date);
  if (!Number.isNaN(stated)) return { t: stated, stated: true };
  const written = c.created_at == null ? NaN : Date.parse(c.created_at);
  return { t: written, stated: false };
}

export interface RunRef {
  workout_date: string;                     // ISO timestamp (Strava a.start_date)
  workout_distance_miles: number;
}

/** ±4h: a voice memo for a run is recorded the same session, never a day off.
 *  Applies when the memo STATES a workout_date — that date is copied from the
 *  picker's selectedWorkout, so it sits within minutes of the real run start. */
export const ORPHAN_TIME_WINDOW_MS = 4 * 60 * 60 * 1000;

// ── created_at fallback window (asymmetric) ─────────────────────────
// A *write* time is not a workout time, and ±4h around it is demonstrably too
// tight: 2026-08-24's memo was recorded 6h29m after that morning's run started,
// so a symmetric 4h window would have stranded it exactly as the NULL filter
// did. Reason from the memo instead: an athlete records a memo AFTER running,
// anywhere from immediately to late that evening — but essentially never about
// a run that has not happened yet.
//
// So the run must have started somewhere in [memo - 18h, memo + 3h]. The 3h of
// forward slack covers a memo dictated mid-run or right before the sync lands.
/** How far BEFORE the memo's write time the run may have started. */
export const ORPHAN_FALLBACK_BEFORE_MS = 18 * 60 * 60 * 1000;
/** How far AFTER the memo's write time the run may have started. */
export const ORPHAN_FALLBACK_AFTER_MS = 3 * 60 * 60 * 1000;
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
  const scored: { c: OrphanCandidate; stated: boolean; dt: number; dd: number }[] = [];
  for (const c of candidates) {
    // Distance is still required — with the fallback window as wide as it is,
    // distance is the only independent evidence that this memo describes THIS
    // run and not another session. The timestamp may fall back to created_at;
    // the distance may not fall back to anything, so a distance-less candidate
    // is rejected outright.
    if (c.workout_distance_miles == null) continue;
    const dd = Math.abs(c.workout_distance_miles - runD);
    if (dd > tol) continue;

    const { t, stated } = candidateTime(c);
    if (Number.isNaN(t)) continue;
    // Signed, not absolute — the fallback window is asymmetric.
    const delta = t - runT;                 // >0 = memo timestamped after the run
    const inWindow = stated
      ? Math.abs(delta) <= ORPHAN_TIME_WINDOW_MS
      : delta >= -ORPHAN_FALLBACK_AFTER_MS && delta <= ORPHAN_FALLBACK_BEFORE_MS;
    if (!inWindow) continue;

    scored.push({ c, stated, dt: Math.abs(delta), dd });
  }
  // A stated date is stronger evidence than a write time, so it outranks any
  // fallback match regardless of clock distance; ties break on time, then
  // distance, as before.
  scored.sort((a, b) =>
    Number(b.stated) - Number(a.stated) || a.dt - b.dt || a.dd - b.dd
  );
  return scored.length ? scored[0].c : null;
}

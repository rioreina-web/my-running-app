/**
 * Quality load — the per-session effort score behind the Key Sessions grid.
 *
 * A session's effort is the SUM over its WORK bouts of
 * `seconds × ZONE_WEIGHTS[zone]`, expressed in weighted minutes.
 *
 * WHY A SUM, NOT AN AVERAGE
 * -------------------------
 * `segmentFromLaps` already computes exactly this quantity — it accumulates
 * `weightedSum += b.seconds * ZONE_WEIGHTS[b.zone]` — and then divides it by
 * `totalSeconds` to produce `intensityScore`, discarding the numerator. That
 * ratio is the retired whole-workout metric `_shared/quality-volume.ts`
 * documents as broken: it booked a rep session's warmup, floats, standing
 * rests and cooldown as quality, while a long run with a 4-mile MP block
 * scored zero because the easy miles dragged the average under the cutoff.
 *
 * Integrating instead of averaging, and restricting to `isWork` bouts, is
 * the whole fix. No new weights, no new classifier — `ZONE_WEIGHTS` is the
 * canonical 1–5 scale from the 2026-06-12 decision, used unchanged.
 *
 * NO GATE HERE, DELIBERATELY
 * --------------------------
 * This module scores; it does not filter. The floor that decides whether a
 * session counts as a key session lives client-side (`QualityLoad.floor` in
 * `TrendsQualityLoad.swift`) so it can be tuned without an edge-function
 * deploy, and so the client can still draw sub-floor work as an open ring
 * rather than being told it doesn't exist.
 *
 * Calibration (23 real lap-scored sessions, 2026-07-27): stride sets score
 * 5.4–13.1, the smallest genuine session 42.1, the largest 103.5, and the
 * gap between 13.1 and 42.1 is empty.
 */

import { ZONE_WEIGHTS, type Bout } from "../_shared/workoutSegmentation.ts";

/**
 * Weighted minutes of work in one session. Rest, warmup and cooldown fall
 * out via `isWork`, which `segmentFromLaps` has already decided.
 *
 * Returns 0 for a session with no work bouts — a real zero, and the caller
 * is free to emit it. Rounded to one decimal: the score drives a dot radius,
 * so further precision is noise.
 */
export function qualityLoadForBouts(bouts: readonly Bout[]): number {
  let weighted = 0;
  for (const b of bouts) {
    if (!b.isWork || b.seconds <= 0) continue;
    weighted += b.seconds * (ZONE_WEIGHTS[b.zone] ?? 1);
  }
  return Math.round((weighted / 60) * 10) / 10;
}

/**
 * Load for an AEROBIC session — a long run. Same formula, different bout set:
 * every bout counts, not only the work ones.
 *
 * That difference is the point, not an inconsistency. In a rep session the
 * warmup, floats and cooldown are scaffolding around the stimulus, so they
 * are excluded. In a long run the whole run IS the stimulus, so all of it
 * counts — and because `ZONE_WEIGHTS` already grades easy (1.0) below steady
 * (2.0) below MP (2.5), a long run finished strong outscores the same
 * distance plodded, with no second scale needed.
 *
 * A 93-minute easy long run scores ~93, landing just under this athlete's
 * biggest threshold session (103.5). That ordering is about right: both are
 * the anchor session of their week.
 */
export function aerobicLoadForBouts(bouts: readonly Bout[]): number {
  let weighted = 0;
  for (const b of bouts) {
    if (b.seconds <= 0) continue;
    weighted += b.seconds * (ZONE_WEIGHTS[b.zone] ?? 1);
  }
  return Math.round((weighted / 60) * 10) / 10;
}

/**
 * Fallback for a long run carrying no lap data at all — 4 of this athlete's
 * 14 Saturday long runs have none. Duration at the easy weight (1.0), which
 * is the honest floor: without laps we cannot claim it was faster than easy,
 * and a long run is aerobic by definition.
 */
export function longRunLoadFromMinutes(
  durationMinutes: number | null | undefined,
): number {
  if (!durationMinutes || durationMinutes <= 0) return 0;
  return Math.round(durationMinutes * 10) / 10;
}

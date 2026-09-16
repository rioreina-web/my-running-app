/**
 * workloadScore.ts — the athlete-facing Workload Score.
 *
 * The Workload Score answers "how much did this session actually ask of *this*
 * athlete?" — pace weighted by volume, and volume weighted by how hard that
 * pace is *relative to their own fitness*. It is NOT a new load model: it is a
 * thin, presentation-layer wrap around the single source of truth,
 * `computeWeightedLoadForLog` (weeklyAnalytics.ts) — the same
 * intensity_score × duration weighted-minutes the athlete_state load
 * distribution already sums. We do not recompute load here; we scale and label
 * the canonical number so it can be shown as one figure + one plain word.
 *
 * Why fitness-relative works out of the box: `intensity_score` is a
 * time-weighted average of pace-ZONE weights (easy 1.0 → mile 5.0), and the
 * zones are anchored to the athlete's real paces (confirmed_races → goal). So a
 * 2:30 marathoner running 14 mi at 5:45 lands almost entirely in the MP zone
 * (weight 2.5) for ~80 min → ~200 weighted-min, ~3.4× an easy hour. The score
 * "recognises" that as a massive block of marathon-pace work without anyone
 * hand-labelling it.
 *
 * Presentation: the raw weighted-minutes (`load`) is honest but unintuitive, so
 * we map it onto a 0–10 index against the athlete's OWN recent session
 * distribution (`referenceLoad`, recommended = the 90th percentile of their
 * last ~6 weeks of sessions). The index is therefore relative in both senses:
 * pace-relative-to-fitness (baked into intensity_score) and
 * load-relative-to-their-own-training (the reference). One plain band word
 * carries the qualifier.
 */

import {
  computeWeightedLoadForLog,
  type TrainingLogRow,
  type WorkoutFeaturesRow,
} from "./weeklyAnalytics.ts";

// ── Raw session load (weighted minutes) ──────────────────────────────────

/**
 * Session load in weighted minutes, from the precomputed zone intensity. This
 * is the same arithmetic as `computeWeightedLoadForLog`'s preferred path
 * (`intensity_score × duration / 60`), exposed for primitives so the score can
 * be computed at surfacing time and in tests without a full row.
 */
export function sessionLoadFromIntensity(
  intensityScore: number | null | undefined,
  durationSeconds: number | null | undefined,
): number {
  if (!intensityScore || !durationSeconds || intensityScore <= 0 || durationSeconds <= 0) {
    return 0;
  }
  return (intensityScore * durationSeconds) / 60;
}

/**
 * Row-based convenience — delegates to the canonical `computeWeightedLoadForLog`
 * (features preferred, workout_type × duration fallback) so callers with a full
 * training-log row get the identical number the load distribution uses.
 */
export function sessionLoadForLog(
  log: TrainingLogRow,
  features: WorkoutFeaturesRow | undefined,
): number {
  return computeWeightedLoadForLog(log, features);
}

// ── Score + band ─────────────────────────────────────────────────────────

export type WorkloadBand = "light" | "moderate" | "solid" | "heavy" | "peak";

export interface WorkloadScore {
  /** Raw weighted-minutes — the canonical load, unrounded consumers can keep. */
  load: number;
  /** 0–10 index vs the athlete's own recent session distribution. */
  index: number;
  /** Plain-language qualifier derived from the index. */
  band: WorkloadBand;
}

/**
 * The load (weighted-minutes) that maps to the top of the index when the athlete
 * has no history yet — roughly a solid hour of quality work. Keeps a brand-new
 * athlete's first hard session from reading as "peak" or "light" nonsensically.
 */
export const DEFAULT_REFERENCE_LOAD = 180;

export function bandForIndex(index: number): WorkloadBand {
  if (index < 2) return "light";
  if (index < 4) return "moderate";
  if (index < 6) return "solid";
  if (index < 8) return "heavy";
  return "peak";
}

/**
 * Scale a raw session load onto the 0–10 athlete-relative index and label it.
 * `referenceLoad` is the load that reads as a 10 — recommend the 90th percentile
 * of the athlete's recent session loads (see `referenceLoadFromSessions`), so
 * the athlete's top decile reads as "peak" and easy days sit low. Falls back to
 * `DEFAULT_REFERENCE_LOAD` when no usable history exists.
 */
export function computeWorkloadScore(
  load: number,
  referenceLoad: number | null | undefined,
): WorkloadScore {
  const ref = referenceLoad && referenceLoad > 0 ? referenceLoad : DEFAULT_REFERENCE_LOAD;
  const raw = Math.max(0, load);
  const index = Math.min(10, Math.round((raw / ref) * 100) / 10);
  return { load: raw, index, band: bandForIndex(index) };
}

/**
 * Robust reference load from a set of recent session loads: the `percentile`
 * (default 90th) of the non-zero loads, so a single GPS-glitch outlier can't
 * define the ceiling and the top decile of real sessions reads as peak. Returns
 * `DEFAULT_REFERENCE_LOAD` when there isn't enough history.
 */
export function referenceLoadFromSessions(
  loads: number[],
  percentile = 0.9,
): number {
  const real = loads.filter((l) => l > 0).sort((a, b) => a - b);
  if (real.length < 3) return DEFAULT_REFERENCE_LOAD;
  const rank = Math.min(real.length - 1, Math.floor(percentile * (real.length - 1)));
  return real[rank];
}

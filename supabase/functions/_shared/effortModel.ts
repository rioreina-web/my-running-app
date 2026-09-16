// ============================================================================
// effortModel.ts — what a session actually ASKED of the athlete.
//
// THE PROBLEM THIS FIXES
// ----------------------
// `stress_load` (compute-workout-features) is `intensity_score × duration`.
// Duration includes recovery. So cutting the rest — which makes a session
// harder — makes the number go DOWN:
//
//   10×1K @ 3:15 w/ 90" rest → 66.0 min, load 212.3
//   10×1K @ 3:15 w/ 60" rest → 61.5 min, load 207.8   ← harder, scores 2% lower
//
// Same work, same paces, a third less recovery, and the model preferred the
// easier one. Every surface downstream inherited it: workloadScore is a thin
// wrap over the same figure, and workoutComparison printed `avgRecoverySec` as
// a fact line while giving it zero weight in the score. Rest was observed and
// then thrown away.
//
// THE SIX DIMENSIONS
// ------------------
// An effort is read on six axes. Five already had homes; this module gathers
// them and adds the missing one:
//
//   paces      — segmentFromLaps, bout-by-bout against the athlete's zones
//   volume     — total distance + quality (dominant-zone work) distance
//   HR         — whole-run, work-only, and recovery HR drop
//   heat       — dew-point model, scaled by CONTINUOUS-EFFORT length
//                (pace-heat-adjustment.ts; see `continuousBlockMiles`)
//   elevation  — per-lap grade, capped, asymmetric up/down
//   density    — NEW. Work relative to the recovery that bought it.
//
// HOW CONDITIONS ENTER — through the pace, never as a second multiplier.
// A 5:20 rep at 78°F/75°F dew is worth ~5:08 in neutral air. We rewrite the
// lap's pace to that neutral-equivalent and re-segment: the bout lands further
// up the continuous easy→mile intensity curve and earns a higher weight on its
// own. No conditions coefficient, no double-counting, and the athlete's zone
// table stays the single arbiter of what "hard" means for THEM.
//
// HOW DENSITY ENTERS — relative to the athlete's own habit, not a textbook.
// The reference rest-ratio is the median of what THIS athlete actually takes
// between reps in that zone (see `densityBaselineFromSamples`). A runner who
// always jogs 90" gets no bonus for jogging 90"; the same runner cutting to 60"
// does. `ZONE_REST_RATIO_FALLBACK` exists only for cold start — a brand-new
// athlete with no rep history — and is documented as such, not as a norm we
// think anyone should train to.
//
// (2026-08-13) ONE MECHANISM PER AXIS. `loadTerms.ts` adds two axes this module
// cannot see, and the split is deliberate so nothing is counted twice:
//   work:rest RATIO   → here (habit-relative, and strong enough to outweigh the
//                       fact that more rest means more elapsed jogging)
//   absolute REP LEN  → loadTerms.densityMultiplier (10×1K w/60s and 5×2K
//                       w/120s share a ratio; they are not the same session)
//   TIME ON FEET      → loadTerms.fatigueMultiplier
// `loadTerms.lacticStress` is deliberately NOT wired in — see
// `effortLoadFromBouts` for why it cannot own the rest axis.
//
// WHAT THIS MODULE WILL NOT DO
// ----------------------------
// It does not rank sessions and it does not say "better" or "harder". It
// measures. `describeDensity` emits plain facts ("density 68.4% → 76.5%,
// recovery 90s → 60s") and stops there; the comparative read is the athlete's
// to make. Consistent with AI-advises-never-acts and the niggles posture of
// surface-never-interpret.
//
// Pure functions, no I/O. See effortModel.test.ts.
// ============================================================================

import {
  buildZoneAnchors,
  paceToZone,
  paceWeight,
  segmentFromLaps,
  WORK_ZONES,
  type Bout,
  type LapInput,
  type PaceZones,
  type SegmentationResult,
  type Zone,
} from "./workoutSegmentation.ts";
import {
  densityMultiplier,
  fatigueMultiplier,
  type LoadContext,
} from "./loadTerms.ts";
import { adjustPace, compositeScore } from "./pace-heat-adjustment.ts";
import { assessHeatRisk, type HeatRisk } from "./heat-risk.ts";

const METERS_PER_MILE = 1609.344;

// ── Inputs ───────────────────────────────────────────────────────────────

/** A lap plus the conditions columns stamped by fetch-workout-weather and the
 *  activity stream. Superset of what workoutComparison already selects. */
export interface EffortLap extends LapInput {
  total_elevation_gain?: number | null; // meters climbed in the lap
  temp_f?: number | null;
  dew_point_f?: number | null;
}

/** Session-level conditions, from `training_logs.weather_actual`. Used when the
 *  per-lap heat columns haven't been stamped (older rows, or weather fetched
 *  after features ran). */
export interface EffortConditions {
  temp_f?: number | null;
  dew_point_f?: number | null;
}

// ── Grade model (moved here from workoutComparison so there is ONE) ───────
//
// Uphill costs more than downhill gives back, and both are capped: per-lap
// elevation is NET gain over the lap, so rolling terrain that climbs and
// descends inside one lap reads as sustained grade. The cap is what keeps that
// honest rather than a silent over-credit. Real grade adjustment wants
// per-second streams; this is a documented MODEL and is labelled as one.

export const GRADE_MAX_PCT = 8;
export const GRADE_K_UP = 0.03; // per +1% grade: ~3% faster-equivalent credit
export const GRADE_K_DOWN = 0.015; // per −1% grade: smaller discount

export function gradeFactor(gradePct: number): number {
  const g = Math.max(-GRADE_MAX_PCT, Math.min(GRADE_MAX_PCT, gradePct));
  return g >= 0 ? 1 - GRADE_K_UP * g : 1 - GRADE_K_DOWN * g;
}

/**
 * Continuous-effort length, in miles, for each lap — the distance the athlete
 * covered without a cooling break, NOT the distance of the watch's auto-split.
 *
 * This is what the heat model's rep-length scaling must key on. The scaling
 * exists because the body sheds heat during recoveries, so a short rep pays
 * less of the penalty than a sustained one. A 6-mile tempo has no recoveries —
 * but a watch auto-lapping it into 1-mile splits made every lap look like a
 * 1-mile "rep" and quietly bought it `repLengthFactor` 0.667 instead of 1.0,
 * losing a third of the correction on exactly the sessions (continuous
 * threshold) where the full correction is most warranted.
 *
 * A block is a run of consecutive WORK laps (MP or faster, on the athlete's own
 * zones — the same `WORK_ZONES` gate segmentation uses, so the two modules
 * can't disagree about where an effort ends). Anything that isn't work — a
 * float, a standing rest, the warmup, the cooldown — both terminates the block
 * and gets `null`, i.e. the continuous/full basis: an easy warmup in the heat
 * has no cooling breaks either, so it pays the whole penalty.
 *
 * Returns miles per lap index, or null for "treat as continuous".
 */
function continuousBlockMiles(laps: EffortLap[], zones: PaceZones): Array<number | null> {
  const anchors = buildZoneAnchors(zones);
  const isWork = laps.map((lap) => {
    if (lap.is_rest === true) return false;
    const pace = Number(lap.avg_pace_sec_per_mile ?? 0);
    if (!(pace > 0) || anchors.length === 0) return false;
    return WORK_ZONES.has(paceToZone(pace, anchors));
  });

  const out: Array<number | null> = new Array(laps.length).fill(null);
  let i = 0;
  while (i < laps.length) {
    if (!isWork[i]) {
      i++;
      continue;
    }
    let j = i, miles = 0;
    while (j < laps.length && isWork[j]) {
      miles += Math.max(0, Number(laps[j].distance_meters ?? 0)) / METERS_PER_MILE;
      j++;
    }
    for (let k = i; k < j; k++) out[k] = miles;
    i = j;
  }
  return out;
}

/**
 * Rewrite each lap's pace to its NEUTRAL-EQUIVALENT — what that effort would
 * have run in cool air on the flat. Heat first (dew-point model, scaled by the
 * CONTINUOUS-EFFORT length, not the lap length), then grade.
 *
 * Returns the laps unchanged when there is nothing to correct for, so a flat
 * cool session is never perturbed by a model it doesn't need.
 */
export function neutralEquivalentLaps(
  laps: EffortLap[],
  zones: PaceZones,
  conditions?: EffortConditions | null,
): { laps: EffortLap[]; heatApplied: boolean; gradeApplied: boolean } {
  let heatApplied = false;
  let gradeApplied = false;
  const blockMiles = continuousBlockMiles(laps, zones);

  const out = laps.map((lap, idx) => {
    const raw = Number(lap.avg_pace_sec_per_mile ?? 0);
    const distM = Number(lap.distance_meters ?? 0);
    if (raw <= 0 || distM <= 0) return lap;

    let pace = raw;

    // Heat — per-lap columns win; fall back to the session's weather.
    const tempF = num(lap.temp_f) ?? num(conditions?.temp_f);
    const dewF = num(lap.dew_point_f) ?? num(conditions?.dew_point_f);
    if (tempF != null && dewF != null && lap.is_rest !== true) {
      const a = adjustPace(pace, tempF, dewF, blockMiles[idx]);
      if (a.effectiveAdjustmentPercent > 0) {
        pace = a.neutralEquivalentPaceSeconds;
        heatApplied = true;
      }
    }

    // Grade.
    const elev = num(lap.total_elevation_gain);
    if (elev != null && elev !== 0) {
      const gradePct = (elev / distM) * 100;
      const f = gradeFactor(gradePct);
      if (f !== 1) {
        pace = pace * f;
        gradeApplied = true;
      }
    }

    return pace === raw ? lap : { ...lap, avg_pace_sec_per_mile: pace };
  });

  return { laps: out, heatApplied, gradeApplied };
}

// ── Density ──────────────────────────────────────────────────────────────

/**
 * Cold-start reference rest-ratios (recovery seconds per second of work), by
 * the zone the reps were run in. ONLY used when the athlete has no rep history
 * in that zone yet — `densityBaselineFromSamples` supersedes it the moment
 * three real sessions exist. These are a starting point so a first session
 * doesn't read as nonsense, NOT a prescription: nothing in the product tells an
 * athlete to train to these numbers.
 */
export const ZONE_REST_RATIO_FALLBACK: Partial<Record<Zone, number>> = {
  mile: 1.0,
  "3k": 0.9,
  "5k": 0.75,
  "10k": 0.5,
  hmp: 0.25,
  mp: 0.1,
};

/** How hard a rest deficit bites. Asymmetric: cutting recovery below your own
 *  habit costs more than padding it above your habit saves, because extra rest
 *  past full recovery buys progressively less. Tunable, documented, capped. */
export const DENSITY_K_TIGHTER = 0.5;
export const DENSITY_K_LOOSER = 0.25;
export const DENSITY_MULT_MIN = 0.85;
export const DENSITY_MULT_MAX = 1.35;

/** Minimum real sessions in a zone before the athlete's own median outranks
 *  `ZONE_REST_RATIO_FALLBACK`. Mirrors referenceLoadFromSessions' floor. */
export const MIN_BASELINE_SAMPLES = 3;

export type BaselineSource = "athlete" | "cold_start" | "none";

/** One historical observation: the rest ratio this athlete took in this zone. */
export interface RestSample {
  zone: Zone;
  restRatio: number;
}

export interface DensityBaseline {
  /** Median rest-ratio per zone, from the athlete's own sessions. */
  byZone: Partial<Record<Zone, number>>;
  /** Sample count per zone — callers surface this as confidence. */
  countByZone: Partial<Record<Zone, number>>;
}

/**
 * The athlete's habitual rest, per zone. Median (not mean) so one session with
 * a long set-break or a paused watch can't move the reference.
 */
export function densityBaselineFromSamples(samples: RestSample[]): DensityBaseline {
  const grouped = new Map<Zone, number[]>();
  for (const s of samples) {
    if (!(s.restRatio >= 0) || !Number.isFinite(s.restRatio)) continue;
    const arr = grouped.get(s.zone) ?? [];
    arr.push(s.restRatio);
    grouped.set(s.zone, arr);
  }
  const byZone: Partial<Record<Zone, number>> = {};
  const countByZone: Partial<Record<Zone, number>> = {};
  for (const [zone, arr] of grouped) {
    countByZone[zone] = arr.length;
    // 3dp: an even-count median of 2dp ratios lands on a half-step, and we keep
    // that rather than rounding the reference away from where it actually sits.
    if (arr.length >= MIN_BASELINE_SAMPLES) byZone[zone] = round3(median(arr));
  }
  return { byZone, countByZone };
}

export interface DensityProfile {
  /** Reps that bounded a measurable recovery. */
  repCount: number;
  /** Median rep duration, seconds. Median for the same robustness reason. */
  medianRepSeconds: number | null;
  /** Median recovery between reps, seconds. */
  medianRestSeconds: number | null;
  /** Recovery seconds per second of work — the shape-independent figure. */
  restRatio: number | null;
  /** Work as a share of the rep block (work + inter-rep recovery), percent.
   *  Warmup and cooldown are excluded: they aren't part of the density. Note n
   *  reps bound n−1 recoveries, so this sits slightly above the per-rep figure
   *  `rep/(rep+rest)` — it is what the block actually was, not an idealisation. */
  densityPct: number | null;
  /** The zone the reps were run in — what the baseline is keyed on. */
  zone: Zone | null;
  baselineRestRatio: number | null;
  baselineSource: BaselineSource;
  /** 1 − actual/baseline, clamped to [−1, 1]. Positive = less rest than habit. */
  deficit: number | null;
  /** Load multiplier on the work portion. Exactly 1.0 when density is unknown
   *  — an unmeasurable session is never penalised or credited. */
  multiplier: number;
}

const EMPTY_DENSITY: DensityProfile = {
  repCount: 0,
  medianRepSeconds: null,
  medianRestSeconds: null,
  restRatio: null,
  densityPct: null,
  zone: null,
  baselineRestRatio: null,
  baselineSource: "none",
  deficit: null,
  multiplier: 1,
};

/**
 * Rep durations and the recoveries BETWEEN them. Only gaps bounded by a rep on
 * both sides count — the jog to the track and the cooldown are not recovery,
 * and counting them would make every session look sparse.
 */
export function repRestSplit(bouts: Bout[]): { reps: number[]; rests: number[] } {
  const repIdx: number[] = [];
  bouts.forEach((b, i) => {
    if (b.isRep) repIdx.push(i);
  });
  if (repIdx.length < 2) {
    return { reps: repIdx.map((i) => bouts[i].seconds), rests: [] };
  }

  const reps = repIdx.map((i) => bouts[i].seconds);
  const rests: number[] = [];
  for (let k = 0; k < repIdx.length - 1; k++) {
    let gap = 0;
    for (let i = repIdx[k] + 1; i < repIdx[k + 1]; i++) gap += bouts[i].seconds;
    rests.push(gap);
  }
  return { reps, rests };
}

/** The zone the rep block was run in — the modal zone across reps, weighted by
 *  time, so one short outlier rep can't relabel the session. */
export function dominantRepZone(bouts: Bout[]): Zone | null {
  const byZone = new Map<Zone, number>();
  for (const b of bouts) {
    if (!b.isRep) continue;
    byZone.set(b.zone, (byZone.get(b.zone) ?? 0) + b.seconds);
  }
  let best: Zone | null = null;
  let bestSec = 0;
  for (const [zone, sec] of byZone) {
    if (sec > bestSec) {
      bestSec = sec;
      best = zone;
    }
  }
  return best;
}

/**
 * The density read for one session. Returns `EMPTY_DENSITY` (multiplier 1.0)
 * for anything without at least two reps — a steady run has no density, and we
 * say so rather than inventing one.
 */
export function densityFromBouts(
  bouts: Bout[],
  baseline?: DensityBaseline | null,
): DensityProfile {
  const { reps, rests } = repRestSplit(bouts);
  if (reps.length < 2 || rests.length === 0) return EMPTY_DENSITY;

  const medRep = median(reps);
  const medRest = median(rests);
  if (!(medRep > 0)) return EMPTY_DENSITY;

  const restRatio = medRest / medRep;
  const workSec = reps.reduce((a, b) => a + b, 0);
  const restSec = rests.reduce((a, b) => a + b, 0);
  const densityPct = round1((workSec / (workSec + restSec)) * 100);
  const zone = dominantRepZone(bouts);

  let baselineRestRatio: number | null = null;
  let baselineSource: BaselineSource = "none";
  if (zone) {
    const own = baseline?.byZone?.[zone];
    if (typeof own === "number" && own > 0) {
      baselineRestRatio = own;
      baselineSource = "athlete";
    } else {
      const cold = ZONE_REST_RATIO_FALLBACK[zone];
      if (typeof cold === "number" && cold > 0) {
        baselineRestRatio = cold;
        baselineSource = "cold_start";
      }
    }
  }

  let deficit: number | null = null;
  let multiplier = 1;
  if (baselineRestRatio != null) {
    deficit = clamp(1 - restRatio / baselineRestRatio, -1, 1);
    const k = deficit >= 0 ? DENSITY_K_TIGHTER : DENSITY_K_LOOSER;
    multiplier = clamp(1 + k * deficit, DENSITY_MULT_MIN, DENSITY_MULT_MAX);
    deficit = round2(deficit);
    multiplier = round2(multiplier);
  }

  return {
    repCount: reps.length,
    medianRepSeconds: Math.round(medRep),
    medianRestSeconds: Math.round(medRest),
    restRatio: round2(restRatio),
    densityPct,
    zone,
    baselineRestRatio: baselineRestRatio != null ? round2(baselineRestRatio) : null,
    baselineSource,
    deficit,
    multiplier,
  };
}

/** This session's contribution to the athlete's own baseline, for the next
 *  session's reference. Null when the session had no measurable density. */
export function restSampleFrom(density: DensityProfile): RestSample | null {
  return density.zone && density.restRatio != null
    ? { zone: density.zone, restRatio: density.restRatio }
    : null;
}

// ── Effort load ──────────────────────────────────────────────────────────

/**
 * Weighted training-minutes, density-aware. Same unit as
 * `weeklyAnalytics.computeWeightedLoadForLog` / `training_logs.stress_load`, so
 * these accumulate into one coherent CTL/ATL/TSB curve rather than a parallel
 * scale nobody can reconcile.
 *
 * Each bout contributes `paceWeight(pace) × minutes` — the same continuous
 * easy→mile curve the rest of the load math uses. Three physiological terms
 * from `loadTerms.ts` then shade it: rep length against the pace ceiling
 * (per work bout), anaerobic depletion (per session), and time on feet (per
 * session).
 *
 * (2026-08-13) ONE MECHANISM PER AXIS. Two density models had grown up side by
 * side; this is the reconciliation, and the rule is that each axis has exactly
 * one owner so nothing is counted twice:
 *
 *   WORK:REST RATIO  → `density.multiplier` (this module). Ratio-based and
 *                      habit-relative, so it ranks 60s recovery above 90s
 *                      regardless of which one the athlete habitually takes.
 *                      Strong (up to 1.35 on reps) — and it has to be, because
 *                      it must outweigh the fact that MORE rest means more
 *                      elapsed jogging and therefore more raw weighted minutes.
 *                      That inversion is the bug this whole module exists for.
 *
 *   ABSOLUTE REP LEN → `loadTerms.densityMultiplier`. Rest ratio cannot see
 *                      this: `10 × 1K w/60s` and `5 × 2K w/120s` have the SAME
 *                      ratio (3.23:1) and are indistinguishable to the term
 *                      above, yet the 2K reps are twice the continuous effort.
 *                      Measured as rep length over the ceiling at that pace.
 *
 *   TIME ON FEET     → `loadTerms.fatigueMultiplier`. Cumulative/glycogen cost
 *                      of long sessions. Neither of the others sees duration.
 *
 * WHY NOT `loadTerms.lacticStress` HERE. It was built for the same rest axis
 * and measured absolutely (tank emptiness) rather than against habit. Tested on
 * this module's own fixture it is simply too weak to own that axis: at 5K pace
 * `10 × 1K` off 60s scores only +2.2% of lactic over the 90s version, while the
 * extra 4.5 minutes of recovery jogging hands the 90s session +2.5% of base —
 * so the easier session wins and `effortModel.test.ts` fails. The tank barely
 * drains at 5K pace, which is correct physiology and exactly why it cannot
 * carry this. Habit-relative density can. Lactic stays available in
 * loadTerms.ts and is documented as parked in LOAD-MODEL-OPEN-APPLY.md.
 */
export function effortLoadFromBouts(
  bouts: Bout[],
  zones: PaceZones,
  density: DensityProfile,
  ctx?: LoadContext | null,
): { load: number; baseLoad: number; densityDelta: number } {
  const anchors = buildZoneAnchors(zones);
  let base = 0;
  let scaled = 0;
  for (const b of bouts) {
    if (b.seconds <= 0) continue;
    const w = anchors.length > 0 && b.paceSecPerMile > 0
      ? paceWeight(b.paceSecPerMile, anchors)
      : 1;
    const wm = (w * b.seconds) / 60;
    base += wm;
    // Recovery is NOT scaled: shortening the rest makes the work harder, it
    // doesn't make the jogging harder.
    // Axis 1 — work:rest ratio, habit-relative, on reps.
    let boutLoad = b.isRep ? wm * density.multiplier : wm;
    // Axis 2 — absolute rep length against the ceiling at that pace. Null ctx
    // (thin zone table) simply skips it rather than inventing a ceiling.
    if (ctx && b.isWork) {
      boutLoad *= densityMultiplier(b.seconds, ctx.ceilingSeconds(b.paceSecPerMile));
    }
    scaled += boutLoad;
  }
  // Axis 3 — time on feet, session-level.
  if (ctx) scaled *= fatigueMultiplier(bouts);
  return {
    load: round1(scaled),
    baseLoad: round1(base),
    densityDelta: round1(scaled - base),
  };
}

// ── The whole profile ────────────────────────────────────────────────────

export interface EffortProfile {
  /** Segmentation on NEUTRAL-EQUIVALENT paces (heat + grade corrected). */
  segmentation: SegmentationResult;
  /** Segmentation on the paces actually run — what the watch said. */
  rawSegmentation: SegmentationResult;
  density: DensityProfile;
  /** Density-aware weighted minutes, and the same figure without density. */
  effortLoad: number;
  baseLoad: number;
  densityDelta: number;
  // ── Conditions (context; already folded into the adjusted paces) ──
  heatApplied: boolean;
  gradeApplied: boolean;
  tempF: number | null;
  dewPointF: number | null;
  /** How RISKY the day was, on WBGT — a separate question from how much
   *  slower it made you, and one the dew-point pace chart cannot answer.
   *  See heat-risk.ts. Null flag when no weather was recorded. */
  heatRisk: HeatRisk;
  totalElevationGainM: number;
  // ── Volume ──
  totalDistanceMeters: number;
  totalDurationSec: number;
  qualityDistanceMeters: number;
  qualitySeconds: number;
  // ── HR ──
  avgRunHr: number | null;
  avgWorkHr: number | null;
  /** Mean (rep HR − following recovery HR). Bigger = heart came down faster. */
  recoveryHrDropBpm: number | null;
  hasHr: boolean;
}

/**
 * Read one session on all six axes. `baseline` is the athlete's own rest habit
 * (`densityBaselineFromSamples` over their recent sessions); omit it and
 * density falls back to `ZONE_REST_RATIO_FALLBACK` and says so via
 * `density.baselineSource`.
 */
export function buildEffortProfile(
  laps: EffortLap[],
  zones: PaceZones,
  opts?: {
    conditions?: EffortConditions | null;
    baseline?: DensityBaseline | null;
    /** Density/lactic/duration context — see loadTerms.buildLoadContext. */
    loadCtx?: LoadContext | null;
  },
): EffortProfile {
  const rawSegmentation = segmentFromLaps(laps, zones);
  const { laps: adjLaps, heatApplied, gradeApplied } = neutralEquivalentLaps(
    laps,
    zones,
    opts?.conditions,
  );
  const segmentation = heatApplied || gradeApplied
    ? segmentFromLaps(adjLaps, zones)
    : rawSegmentation;

  const density = densityFromBouts(segmentation.bouts, opts?.baseline);
  const { load, baseLoad, densityDelta } = effortLoadFromBouts(
    segmentation.bouts,
    zones,
    density,
    opts?.loadCtx ?? null,
  );

  let elevationGainM = 0;
  let tempF: number | null = num(opts?.conditions?.temp_f);
  let dewPointF: number | null = num(opts?.conditions?.dew_point_f);
  for (const lap of laps) {
    elevationGainM += Math.max(0, num(lap.total_elevation_gain) ?? 0);
    tempF ??= num(lap.temp_f);
    dewPointF ??= num(lap.dew_point_f);
  }

  const hr = hrProfile(segmentation.bouts);
  const quality = segmentation.bouts.filter((b) => b.isRep);

  return {
    segmentation,
    rawSegmentation,
    density,
    effortLoad: load,
    baseLoad,
    densityDelta,
    heatApplied,
    gradeApplied,
    tempF,
    dewPointF,
    heatRisk: assessHeatRisk(
      tempF != null && dewPointF != null ? compositeScore(tempF, dewPointF) : 0,
      tempF,
      dewPointF,
    ),
    totalElevationGainM: Math.round(elevationGainM),
    totalDistanceMeters: Math.round(segmentation.totalMeters),
    totalDurationSec: Math.round(segmentation.totalSeconds),
    qualityDistanceMeters: Math.round(
      quality.reduce((a, b) => a + b.distanceMeters, 0),
    ),
    qualitySeconds: Math.round(quality.reduce((a, b) => a + b.seconds, 0)),
    avgRunHr: hr.avgRunHr,
    avgWorkHr: hr.avgWorkHr,
    recoveryHrDropBpm: hr.recoveryHrDropBpm,
    hasHr: hr.avgRunHr != null,
  };
}

function hrProfile(bouts: Bout[]): {
  avgRunHr: number | null;
  avgWorkHr: number | null;
  recoveryHrDropBpm: number | null;
} {
  let runSec = 0, runSum = 0, workSec = 0, workSum = 0;
  for (const b of bouts) {
    if (b.avgHr == null || b.seconds <= 0) continue;
    runSec += b.seconds;
    runSum += b.avgHr * b.seconds;
    if (b.isRep) {
      workSec += b.seconds;
      workSum += b.avgHr * b.seconds;
    }
  }

  // Rep → the recovery immediately after it.
  let dropSum = 0, dropCount = 0;
  for (let i = 0; i < bouts.length - 1; i++) {
    const rep = bouts[i];
    const next = bouts[i + 1];
    if (!rep.isRep || rep.avgHr == null) continue;
    if (next.isRep || next.avgHr == null) continue;
    dropSum += rep.avgHr - next.avgHr;
    dropCount++;
  }

  return {
    avgRunHr: runSec > 0 ? Math.round(runSum / runSec) : null,
    avgWorkHr: workSec > 0 ? Math.round(workSum / workSec) : null,
    recoveryHrDropBpm: dropCount > 0 ? Math.round(dropSum / dropCount) : null,
  };
}

// ── Narration (facts only — never a ranking) ─────────────────────────────

/**
 * Plain fact lines for the density read. Deliberately free of comparative
 * language: no "harder", no "better", no "should". The athlete reads the
 * numbers and draws the conclusion — the same posture the niggles classifier
 * takes with body mentions.
 */
export function describeDensity(d: DensityProfile): string[] {
  if (d.restRatio == null || d.medianRestSeconds == null) return [];
  const lines = [
    `Rep block density: ${d.densityPct}% (${d.repCount} reps, ` +
    `${fmtSec(d.medianRepSeconds!)} work / ${fmtSec(d.medianRestSeconds)} recovery, ` +
    `rest ratio ${d.restRatio})`,
  ];
  if (d.baselineRestRatio != null && d.baselineSource === "athlete") {
    lines.push(
      `Your usual rest ratio in this zone: ${d.baselineRestRatio} ` +
      `(this session: ${d.restRatio})`,
    );
  } else if (d.baselineSource === "cold_start") {
    lines.push(
      `No rep history in this zone yet — density is measured but not yet ` +
      `compared to your own habit.`,
    );
  }
  return lines;
}

/** Both sides of a comparison, as facts. No verdict — see the module header. */
export function describeDensityDiff(a: DensityProfile, b: DensityProfile): string[] {
  if (a.restRatio == null || b.restRatio == null) return [];
  return [
    `Density: ${a.densityPct}% -> ${b.densityPct}%`,
    `Median recovery: ${fmtSec(a.medianRestSeconds!)} -> ${fmtSec(b.medianRestSeconds!)}`,
    `Rest ratio: ${a.restRatio} -> ${b.restRatio}`,
  ];
}

// ── Helpers ──────────────────────────────────────────────────────────────

function num(v: unknown): number | null {
  const n = Number(v);
  return Number.isFinite(n) ? n : null;
}

function median(xs: number[]): number {
  const s = [...xs].sort((a, b) => a - b);
  const mid = Math.floor(s.length / 2);
  return s.length % 2 === 0 ? (s[mid - 1] + s[mid]) / 2 : s[mid];
}

function clamp(v: number, lo: number, hi: number): number {
  return Math.max(lo, Math.min(hi, v));
}

const round1 = (n: number) => Math.round(n * 10) / 10;
const round2 = (n: number) => Math.round(n * 100) / 100;
const round3 = (n: number) => Math.round(n * 1000) / 1000;

function fmtSec(s: number): string {
  if (s < 60) return `${Math.round(s)}s`;
  const m = Math.floor(s / 60);
  const r = Math.round(s % 60);
  return r === 0 ? `${m}:00` : `${m}:${String(r).padStart(2, "0")}`;
}

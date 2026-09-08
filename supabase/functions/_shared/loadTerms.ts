/**
 * loadTerms.ts — density, lactic and duration terms for the quality-load score.
 *
 * `qualityLoad.ts` answers "how much work, at what weight". These three terms
 * answer the questions weight × minutes cannot:
 *
 *   DENSITY   how LONG each rep was, relative to the longest the athlete could
 *             hold that pace continuously. Without it, `10 × 1K @ HM`,
 *             `5 × 2K @ HM` and `10K continuous @ HM` score IDENTICALLY —
 *             104.9, 104.9, 104.9 — because they are the same seconds at the
 *             same weight. Rep structure is invisible to the base formula.
 *
 *   LACTIC    how empty the anaerobic tank was WHILE each rep was run. This is
 *             what makes rest matter: rep 8 off 60s recovery is run on a far
 *             emptier tank than rep 8 off 2', though the rep is identical. It
 *             is scaled by how lactic the pace is at all, so it dominates at
 *             mile pace and vanishes at marathon pace.
 *
 *   DURATION  cumulative/glycogen cost of long sessions. Gated on real elapsed
 *             time (glycogen needs the clock to actually run) but SIZED by
 *             intensity, so a 15mi moderate run still outscores a longer, more
 *             leisurely 16mi easy run.
 *
 * EVERYTHING IS DERIVED, NOTHING IS HARDCODED. The rep ceiling and the
 * critical-speed fit both come out of the athlete's own `pace_zones` via the
 * canonical `RACE_RATIOS_TO_10K` table in paces.ts — the same numbers the pace
 * ladder is already built from. No new pace constants enter the system, and
 * when the zone table is too thin to fit, every term returns a neutral 1.0
 * rather than guessing (same discipline as `paceWeight` returning 1.0 with no
 * anchors).
 *
 * SCOPE: work bouts only (`isWork` — steady pace or faster) for density and
 * lactic. Easy and moderate running is untouched, so ordinary easy runs score
 * exactly what they scored before. The duration term is session-level.
 */

import {
  equivalentRaceTimeSeconds,
  RACE_DISTANCE_MI,
  RACE_RATIOS_TO_10K,
  type RaceKey,
} from "./paces.ts";
import type { Bout, PaceZones } from "./workoutSegmentation.ts";

const METERS_PER_MILE = 1609.34;

// ── Tunable constants ────────────────────────────────────────────────────
// Deliberately small. These shade an existing score; they do not replace it.

/** Density at 100% of the pace ceiling — i.e. racing that distance. +10% max. */
export const DENSITY_K = 0.10;
/** Concave, so short reps still register something rather than rounding to nothing. */
export const DENSITY_P = 0.7;

/** Lactic at full tank depletion running at mile pace. +60% max. */
export const LACTIC_K = 0.60;

/** Duration coefficient, per "burn hour" beyond the ramp. */
export const FATIGUE_K = 0.0190;
/** Burn rate scales as weight^1.5 — easy 1.0x, steady 3.2x, MP 4.0x, HM 5.9x. */
export const BURN_EXP = 1.5;
/** Smoothstep window for the duration gate (minutes). No cliff at either end. */
export const FATIGUE_RAMP_START_MIN = 60;
export const FATIGUE_RAMP_FULL_MIN = 110;

// ── Athlete context ──────────────────────────────────────────────────────

export interface LoadContext {
  /** Longest continuous effort sustainable at a pace, seconds. Null if unknown. */
  ceilingSeconds(paceSecPerMile: number): number | null;
  /** Critical speed (m/s) and anaerobic distance capacity D' (m). */
  csMetersPerSec: number;
  dPrimeMeters: number;
  /** Pace at critical speed, sec/mile — handy for display and tests. */
  csPaceSecPerMile: number;
  /**
   * (v_mile / CS) − 1, the normaliser for `lacticIntensity`. Expressing "how
   * lactic" relative to THIS athlete's own mile keeps the term athlete-relative
   * like everything else, rather than against an absolute nobody shares.
   */
  mileExcessRatio: number;
}

/** Race anchors on `PaceZones`, in the order we prefer to read them. */
const ZONE_TO_RACE: ReadonlyArray<[keyof PaceZones, RaceKey]> = [
  ["mp", "marathon"],
  ["hm", "half"],
  ["tenK", "tenK"],
  ["fiveK", "fiveK"],
  ["threeK", "threeK"],
  ["mile", "mile"],
];

/**
 * Build the athlete's load context from their stored pace zones.
 *
 * One race anchor is enough: `RACE_RATIOS_TO_10K` converts it to every other
 * distance, exactly as `derivePaceTableFromGoal` already does when building the
 * ladder. We prefer the marathon anchor because it is the longest and least
 * sensitive to a single sharp result, and fall back down the ladder.
 *
 * Returns null when no usable anchor exists — callers then skip all three
 * terms rather than inventing a ceiling.
 */
export function buildLoadContext(zones: PaceZones | null | undefined): LoadContext | null {
  if (!zones) return null;

  let ref: { key: RaceKey; timeSeconds: number } | null = null;
  for (const [zoneKey, raceKey] of ZONE_TO_RACE) {
    const pace = zones[zoneKey];
    if (typeof pace === "number" && pace > 0) {
      ref = { key: raceKey, timeSeconds: pace * RACE_DISTANCE_MI[raceKey] };
      break;
    }
  }
  if (!ref) return null;

  // (distance, time) for every canonical race distance, ascending by distance.
  // `RACE_RATIOS_TO_10K` is a DISCRETE table, so to get a ceiling for an
  // arbitrary pace we interpolate it in LOG-LOG space — the space in which the
  // distance/time relationship is a straight line. That keeps the curve
  // continuous and monotone without introducing a second, disagreeing model.
  const pts = (Object.keys(RACE_RATIOS_TO_10K) as RaceKey[])
    .map((k) => ({
      lnD: Math.log(RACE_DISTANCE_MI[k]),
      lnT: Math.log(equivalentRaceTimeSeconds(ref!.key, ref!.timeSeconds, k)),
    }))
    .sort((a, b) => a.lnD - b.lnD);

  const lnTimeAt = (lnD: number): number => {
    if (lnD <= pts[0].lnD) {
      const s = (pts[1].lnT - pts[0].lnT) / (pts[1].lnD - pts[0].lnD);
      return pts[0].lnT + s * (lnD - pts[0].lnD);
    }
    const last = pts.length - 1;
    if (lnD >= pts[last].lnD) {
      const s = (pts[last].lnT - pts[last - 1].lnT) / (pts[last].lnD - pts[last - 1].lnD);
      return pts[last].lnT + s * (lnD - pts[last].lnD);
    }
    for (let i = 0; i < last; i++) {
      if (lnD >= pts[i].lnD && lnD <= pts[i + 1].lnD) {
        const t = (lnD - pts[i].lnD) / (pts[i + 1].lnD - pts[i].lnD);
        return pts[i].lnT + t * (pts[i + 1].lnT - pts[i].lnT);
      }
    }
    return pts[last].lnT;
  };

  /** Pace (sec/mile) the athlete could hold for exactly `d` miles. */
  const paceAt = (d: number): number => Math.exp(lnTimeAt(Math.log(d))) / d;

  const ceilingSeconds = (paceSecPerMile: number): number | null => {
    if (!isFinite(paceSecPerMile) || paceSecPerMile <= 0) return null;
    // Pace is monotonically SLOWER as distance grows, so bisect on distance.
    let lo = 0.1, hi = 120; // miles — 120 covers any pace at or above steady
    if (paceAt(lo) > paceSecPerMile) return null; // faster than the athlete's fastest
    if (paceAt(hi) < paceSecPerMile) return null; // slower than we model
    for (let i = 0; i < 60; i++) {
      const mid = (lo + hi) / 2;
      if (paceAt(mid) < paceSecPerMile) lo = mid; else hi = mid;
    }
    const d = (lo + hi) / 2;
    const t = paceAt(d) * d;
    return isFinite(t) && t > 0 ? t : null;
  };

  // Critical speed / D' from the two-parameter model, fitted on the mile and
  // 10K points of this same ladder. Those two are the classic fit window
  // (~2-40 min); half and marathon must never be used — beyond ~40 minutes the
  // model's assumptions break and D' comes out meaningless.
  const tMile = equivalentRaceTimeSeconds(ref.key, ref.timeSeconds, "mile");
  const t10k = equivalentRaceTimeSeconds(ref.key, ref.timeSeconds, "tenK");
  const dMile = RACE_DISTANCE_MI.mile * METERS_PER_MILE;
  const d10k = RACE_DISTANCE_MI.tenK * METERS_PER_MILE;
  if (!(t10k > tMile)) return null;
  const cs = (d10k - dMile) / (t10k - tMile);
  const dPrime = dMile - cs * tMile;
  if (!(cs > 0) || !(dPrime > 0)) return null; // degenerate ladder — don't lie

  const vMile = dMile / tMile;
  const mileExcessRatio = vMile / cs - 1;
  if (!(mileExcessRatio > 0)) return null;

  return {
    ceilingSeconds,
    csMetersPerSec: cs,
    dPrimeMeters: dPrime,
    csPaceSecPerMile: METERS_PER_MILE / cs,
    mileExcessRatio,
  };
}

// ── 1 · Density ──────────────────────────────────────────────────────────

/**
 * Multiplier for ONE work bout, from its length as a fraction of the longest
 * effort sustainable at its pace. A race is the whole ceiling (fraction 1.0)
 * and gets the cap; a 1K rep at HM pace is under 5% of a half marathon and
 * gets almost nothing.
 *
 * Self-scaling across paces is the point: a 400m rep is ~8% of the 5K ceiling
 * but only ~4% of the 10K ceiling, so the same rep counts for more when it is
 * a bigger bite of what the athlete could sustain.
 */
export function densityMultiplier(
  boutSeconds: number,
  ceilingSeconds: number | null,
): number {
  if (!ceilingSeconds || ceilingSeconds <= 0 || !(boutSeconds > 0)) return 1;
  const fraction = Math.min(1, boutSeconds / ceilingSeconds);
  return 1 + DENSITY_K * Math.pow(fraction, DENSITY_P);
}

// ── 2 · Lactic ───────────────────────────────────────────────────────────

/**
 * How lactic a pace is at all: 1.0 at mile pace, falling to 0 at critical
 * speed and below. Peak blood lactate genuinely peaks around 800m-mile racing
 * (~16 mmol) and FALLS for longer events (10K ~8, half ~5), so this is a taper,
 * not a step. Anything at or slower than CS contributes nothing.
 */
export function lacticIntensity(paceSecPerMile: number, ctx: LoadContext): number {
  if (!isFinite(paceSecPerMile) || paceSecPerMile <= 0) return 0;
  const v = METERS_PER_MILE / paceSecPerMile;
  const excess = v / ctx.csMetersPerSec - 1;
  if (excess <= 0) return 0; // at or below critical speed — not a lactic effort
  // Normalised against the athlete's own mile, so 1.0 means "as lactic as this
  // athlete's mile pace". Faster than mile pace clamps at 1.0 rather than
  // running away.
  return Math.min(1, excess / ctx.mileExcessRatio);
}

/**
 * Recovery time constant (seconds) for D' reconstitution below critical speed.
 * Deeper recovery reconstitutes faster; shallow recovery barely at all.
 *
 * ⚠️ THE ONE UNVALIDATED PIECE. The shape is Skiba's, but his published
 * constants (546·exp(-0.01·DCP) + 316) are fitted to CYCLING POWER, and there
 * is no running-pace-calibrated equivalent in the literature to port. The
 * bounds here are placeholders chosen to give plausible spreads. The ORDERING
 * they produce is trustworthy; the exact percentages are not. Validate against
 * sessions where the athlete knows how they actually felt before surfacing any
 * of this to them.
 */
function reconstitutionTau(recoveryMetersPerSec: number, cs: number): number {
  const deficitPct = Math.max(0, (cs - recoveryMetersPerSec) / cs) * 100;
  const TAU_MIN = 25, TAU_MAX = 280, FULL_DEFICIT_PCT = 45;
  return TAU_MAX - (TAU_MAX - TAU_MIN) * Math.min(1, deficitPct / FULL_DEFICIT_PCT);
}

/**
 * Mean tank-emptiness while the work was actually being run, 0..1.
 *
 * Walks the session bout by bout: above CS the tank drains, below it refills on
 * an exponential. Each work bout contributes the depletion reached at its END,
 * weighted by its duration and by how lactic its pace is.
 *
 * WHY "AT THE END OF EACH BOUT" AND NOT PEAK SESSION DEPLETION. Two earlier
 * shapes both failed:
 *   • peak SESSION depletion accumulates across a rep set, so 8x400 hit 93% and
 *     scored nearly as high as a mile race — the opposite of the intent, which
 *     is that sustained maximal work is the expensive thing;
 *   • deepest SINGLE bout is 25% for a 400m rep no matter the recovery, so rest
 *     length stopped mattering entirely (8x400 off 60s and off 2' scored 87
 *     and 86).
 * Tank state *during* each rep captures both: a long rep drives it deep on its
 * own, and short rest means later reps start already empty.
 */
export function lacticStress(bouts: readonly Bout[], ctx: LoadContext): number {
  let balance = ctx.dPrimeMeters;
  let weighted = 0;
  let workSeconds = 0;

  for (const b of bouts) {
    if (!(b.seconds > 0) || !(b.paceSecPerMile > 0)) continue;
    const v = METERS_PER_MILE / b.paceSecPerMile;
    if (v > ctx.csMetersPerSec) {
      balance = Math.max(0, balance - (v - ctx.csMetersPerSec) * b.seconds);
      if (b.isWork) {
        const depletion = 1 - balance / ctx.dPrimeMeters;
        weighted += depletion * lacticIntensity(b.paceSecPerMile, ctx) * b.seconds;
        workSeconds += b.seconds;
      }
    } else {
      const tau = reconstitutionTau(v, ctx.csMetersPerSec);
      balance = ctx.dPrimeMeters - (ctx.dPrimeMeters - balance) * Math.exp(-b.seconds / tau);
      if (b.isWork) workSeconds += b.seconds; // work at/below CS: no lactic credit
    }
  }
  return workSeconds > 0 ? weighted / workSeconds : 0;
}

/** Session multiplier from `lacticStress`. 1.0 when nothing crosses CS. */
export function lacticMultiplier(bouts: readonly Bout[], ctx: LoadContext | null): number {
  if (!ctx) return 1;
  return 1 + LACTIC_K * lacticStress(bouts, ctx);
}

// ── 3 · Duration ─────────────────────────────────────────────────────────

/**
 * Smooth 0→1 gate on elapsed session time. Cumulative/glycogen fatigue needs
 * the clock to genuinely run, so a 45-minute interval session gets nothing no
 * matter how hard it was — that cost is the lactic term's job, not this one.
 *
 * Deliberately a smoothstep, NOT a threshold: an earlier draft used a hard
 * 85-minute gate and a 14mi steady run at 1:19 fell off it for missing by 40
 * seconds.
 */
export function fatigueTimeRamp(totalSeconds: number): number {
  const t = (totalSeconds / 60 - FATIGUE_RAMP_START_MIN) /
    (FATIGUE_RAMP_FULL_MIN - FATIGUE_RAMP_START_MIN);
  const c = Math.min(1, Math.max(0, t));
  return c * c * (3 - 2 * c);
}

/**
 * "Burn hours" — how much tank the session drained, in easy-equivalent hours.
 * Each second counts at `weight^1.5`, normalised so easy = 1.0x:
 *
 *   easy 1.0x · moderate 1.7x · steady 3.2x · MP 4.0x · HM 5.9x · 10K 8.0x
 *
 * Uses `Bout.weight` — the CONTINUOUS paceWeight value — not the discrete zone
 * weight, so this term has no bucket edges in it.
 */
export function burnHours(bouts: readonly Bout[]): number {
  let sum = 0;
  for (const b of bouts) {
    if (!(b.seconds > 0)) continue;
    const w = b.weight > 0 ? b.weight : 1;
    sum += b.seconds * Math.pow(w, BURN_EXP);
  }
  return sum / 3600;
}

/**
 * Session-level duration multiplier. Gated on TIME, sized by LOAD.
 *
 * Sizing by load rather than by minutes alone is what keeps intensity ordering
 * intact: a first draft used pure time-on-feet and a 16mi easy long run (1:55)
 * outscored a 15mi moderate run (1:36) purely for taking longer.
 */
export function fatigueMultiplier(bouts: readonly Bout[]): number {
  let totalSeconds = 0;
  for (const b of bouts) if (b.seconds > 0) totalSeconds += b.seconds;
  if (totalSeconds <= 0) return 1;
  return 1 + FATIGUE_K * fatigueTimeRamp(totalSeconds) * burnHours(bouts);
}

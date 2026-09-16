// ============================================================================
// prFloor.ts — how far below a lifetime PR the model is allowed to claim you are.
//
// WHY THIS EXISTS (2026-08-24, G0.5). Every guard in `fitnessPrediction.ts` is
// expressed relative to the ANCHOR: the 0.5% unproven-improvement floor, the
// 2% continuous-training decay cap, the EF gate's 1.5%/6% slow-displacement
// caps. Nothing is expressed relative to the athlete's own best. So when the
// anchor is stale, mediocre, or absent, there is no line of code comparing the
// estimate to what the athlete has actually run, and the number can walk
// arbitrarily far below it.
//
// That is the 2026-08-17 incident exactly: a 31:20 10K PB and 66 mpw held read
// as a 2:36:55 marathon, 9.9% off a 2:22:43 PR. FITNESS-MODEL-APPLY.md filed
// it as a DISPLAY fix — "the 2:37 screen would have been self-evidently wrong
// with PR 2:22:43 beside it." But if a human catches it by glancing at the PR,
// so can the model. This is that glance.
//
// THE PHYSIOLOGY. You do not lose ten percent while running 70 mpw. Detraining
// at maintained volume with quality present costs a few percent of race
// sharpness, not fifteen minutes of marathon. A large claimed decline needs
// evidence of the thing that CAUSES decline — volume collapse, layoff, injury,
// age. Absent that evidence the claim is out of bounds. So the allowance opens
// as the evidence for decline accumulates, and stays shut when it does not.
//
// FOUR RULES, each of which cost something to learn:
//
//   1. SAME-DISTANCE ONLY. Never a floor built from the best cross-distance
//      equivalent. Measured on the calibration athlete: converting every PR to
//      a 10K-equivalent and taking the best gives 29:55 — driven by a 5K from
//      a different era carrying a suspect 41s heat credit. That floor sits
//      faster than she has ever run a 10K and would pin a correct 32:00 as
//      "implausibly slow". Conversion always flatters: it picks up whichever
//      distance the athlete's shape favours PLUS whichever normalization erred
//      most. A floor built on the flattered value is a permanent ratchet.
//
//   2. A RACE ALWAYS BEATS THE FLOOR. The caller skips this entirely when a
//      recent race anchors the estimate. A race is a measurement; this is an
//      inference about a measurement's shelf life. Inference never overrides
//      evidence — including when the athlete simply had a bad day.
//
//   3. MISSING CONDITIONS FAIL LOOSE. A PR with no weather on file is passed
//      at its RAW time. If that race was hot, raw is SLOWER than the athlete's
//      true neutral ability, which makes the floor looser and less likely to
//      bind. The failure mode of a missing correction is therefore a floor
//      that does nothing, never a floor that clamps a real decline.
//
//   4. VOLUME IS COMPARED TO THE ATHLETE'S OWN NORMAL, not to a constant.
//      `referenceWeeklyMiles` is the athlete's own median — the honest proxy
//      for PR-era volume, which is usually outside any window we hold. An 18
//      mpw athlete training normally is not detraining, and a threshold in
//      absolute miles would say they were.
//
// Pure functions, no I/O. Tests: prFloor.test.ts.
// ============================================================================

import type { RaceType } from "./fitnessPrediction.ts";

/** Held volume + quality present: the irreducible allowance. */
export const FLOOR_BASE = 0.04;
/** Full volume collapse adds this much on top. */
export const FLOOR_VOLUME_SPAN = 0.12;
/** Quality density at or above this contributes nothing. */
export const FLOOR_QUALITY_TARGET = 0.10;
/** Zero quality density adds FLOOR_QUALITY_TARGET × this. */
export const FLOOR_QUALITY_SPAN = 0.25;
/**
 * Per year since the PR. A stand-in for proper age-grading (WMA factors),
 * which needs a birth date we do not store. Deliberately gentle: this term
 * exists so a five-year-old PR does not bind like a five-month-old one, not
 * to model masters decline. Replace it with real age-grading before trusting
 * a floor from a PR more than ~3 years old.
 */
export const FLOOR_AGE_PER_YEAR = 0.008;
/** Past this the floor says nothing useful and stops claiming to. */
export const FLOOR_MAX_DECLINE = 0.20;

export interface PrRecord {
  distanceKey: RaceType;
  /** "yyyy-MM-dd". */
  date: string;
  /** Conditions-normalized where weather is on file; RAW otherwise (rule 3). */
  seconds: number;
  conditionsKnown: boolean;
}

export interface FloorInputs {
  now: Date;
  /** Current weekly mileage, as the model already computes it. */
  weeklyMiles: number;
  /** The athlete's own median weekly mileage — proxy for PR-era volume. */
  referenceWeeklyMiles: number | null;
  /** 0..1, or null when there is no mileage to measure density against. */
  qualityDensity: number | null;
}

export interface DistanceFloor {
  distanceKey: RaceType;
  prSeconds: number;
  prDate: string;
  yearsSincePr: number;
  maxDeclinePct: number;
  /** The slowest time the model may publish for this distance. */
  floorSeconds: number;
  conditionsKnown: boolean;
  terms: { base: number; volume: number; quality: number; age: number };
}

/**
 * Maximum plausible decline below a PR, given how the athlete is training now.
 * Every term opens the allowance; nothing closes it below FLOOR_BASE.
 */
export function maxDecline(
  volumeRatio: number,
  qualityDensity: number | null,
  yearsSincePr: number,
): DistanceFloor["terms"] & { total: number } {
  const base = FLOOR_BASE;
  const volume = Math.max(0, 1 - Math.min(volumeRatio, 1)) * FLOOR_VOLUME_SPAN;
  // Unknown density cannot be evidence of quality OR of its absence. Treat it
  // as neutral (no contribution) rather than assuming the worst — assuming the
  // worst would loosen the floor toward inert on every athlete without labels.
  const quality = qualityDensity === null
    ? 0
    : Math.max(0, FLOOR_QUALITY_TARGET - Math.max(qualityDensity, 0)) * FLOOR_QUALITY_SPAN;
  const age = Math.max(0, yearsSincePr) * FLOOR_AGE_PER_YEAR;
  return { base, volume, quality, age, total: Math.min(base + volume + quality + age, FLOOR_MAX_DECLINE) };
}

/**
 * One floor per distance the athlete has a PR at. The FASTEST record per
 * distance wins; records at other distances are never converted in (rule 1).
 */
export function computePrFloors(prs: PrRecord[], inputs: FloorInputs): Map<RaceType, DistanceFloor> {
  const best = new Map<RaceType, PrRecord>();
  for (const pr of prs) {
    if (!(pr.seconds > 0)) continue;
    const cur = best.get(pr.distanceKey);
    if (!cur || pr.seconds < cur.seconds) best.set(pr.distanceKey, pr);
  }

  const volumeRatio = inputs.referenceWeeklyMiles && inputs.referenceWeeklyMiles > 0
    ? inputs.weeklyMiles / inputs.referenceWeeklyMiles
    : 1;

  const out = new Map<RaceType, DistanceFloor>();
  for (const [key, pr] of best) {
    const prDate = new Date(`${pr.date}T00:00:00.000Z`);
    const yearsSincePr = Number.isNaN(prDate.getTime())
      ? 0
      : Math.max(0, (inputs.now.getTime() - prDate.getTime()) / (365.25 * 86_400_000));
    const d = maxDecline(volumeRatio, inputs.qualityDensity, yearsSincePr);
    out.set(key, {
      distanceKey: key,
      prSeconds: pr.seconds,
      prDate: pr.date,
      yearsSincePr: Math.round(yearsSincePr * 100) / 100,
      maxDeclinePct: d.total,
      floorSeconds: pr.seconds * (1 + d.total),
      conditionsKnown: pr.conditionsKnown,
      terms: { base: d.base, volume: d.volume, quality: d.quality, age: d.age },
    });
  }
  return out;
}

/**
 * Clamp one published time. Returns the original when no floor exists for the
 * distance or the estimate is already inside it.
 *
 * NOTE: floors are applied per distance, so a clamped marathon may no longer
 * be the exact ratio-conversion of a clamped 10K. That is deliberate — rule 1
 * forbids bounding one distance with another distance's evidence, and internal
 * ratio tidiness is not worth reintroducing the ratchet to buy.
 */
export function applyFloor(
  predictedSeconds: number,
  floor: DistanceFloor | undefined,
): { seconds: number; bound: boolean } {
  if (!floor || !(predictedSeconds > 0)) return { seconds: predictedSeconds, bound: false };
  if (predictedSeconds <= floor.floorSeconds) return { seconds: predictedSeconds, bound: false };
  return { seconds: Math.round(floor.floorSeconds), bound: true };
}

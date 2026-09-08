// ============================================================================
// buildComparison.ts — is THIS training block stronger than the one that
// produced the athlete's anchor race?
//
// WHY THIS EXISTS (2026-08-27). Raised directly: an athlete who ran a 2:46
// marathon off a WEAKER training base, then genuinely raised mileage,
// lengthened long runs, and sharpened threshold pace, is very likely faster
// for the next one — and the model had no mechanism that could say so. What
// existed (`fitnessPrediction.ts`'s "BUILD GATE") compared the last 2 weeks
// against the prior 2-4 — a window too short to represent a real training
// era, capped at 0.2%/week, bounded by a 0.5%-total improvement ceiling no
// matter how strong the evidence. That is not "is this athlete building a
// meaningfully stronger base than the one that produced their PR" — it is
// "did this fortnight edge out last fortnight," a different and much weaker
// question. This module asks the real one.
//
// THE RULE THAT MATTERS MOST: don't cherry-pick. It would be easy to scan
// for the single most flattering session (a single fast tempo, a big long
// run) and call that "improvement" — that is exactly the failure mode this
// module exists to avoid, and exactly what `trainingZoneSignal.ts`'s
// best-fraction selection already does elsewhere in this pipeline (silently
// drops a real 12-mile tempo session because a different session ranked
// better that week). Here, credit only accrues from BROAD, evidence-gated
// improvement across the athlete's actual training profile — easy pace and
// volume, moderate/steady, long runs, threshold/tempo, intervals — each
// characterized by its own pace AND volume, compared window to window. One
// standout session moves nothing. A training base that is measurably deeper
// and sharper across MULTIPLE zones does.
//
// THE COMPARISON. Two matched-length windows: the BUILD_WINDOW_DAYS
// immediately before the anchor race, and the same length immediately
// before now. Each is summarized per zone (mirrors the app's own
// WorkoutLabel effort taxonomy — easy, moderate/steady, long run,
// threshold/tempo, interval). A zone only counts if BOTH windows have
// real evidence in it — a zone absent from one side yields no ratio, not
// a manufactured one.
//
// WHAT THIS DOES NOT DO. It does not heat-neutralize pace here — per the
// rep-level finding in FITNESS-LEARNING-APPLY.md §4b, a naive session-level
// heat correction is how this codebase fooled itself once already (the
// retracted "24 s/mi slower in heat" finding). Comparing raw pace
// window-to-window is the more honest choice until a rep-level-validated
// correction exists; a genuinely warmer summer in the CURRENT window would
// understate improvement here, never overstate it — the same fail-safe
// direction prFloor.ts uses for missing conditions.
//
// Pure functions, no I/O. Tests: buildComparison.test.ts.
// ============================================================================

import type { WorkoutInput } from "./fitnessPrediction.ts";

/** Matched-length comparison window. 6 weeks — long enough to show a real
 *  pattern, short enough to represent the SPECIFIC block, not the athlete's
 *  whole training history bleeding into "now" or "then". */
export const BUILD_WINDOW_DAYS = 42;

/** A zone needs at least this much volume in BOTH windows before its pace
 *  comparison is trusted — a single lucky/unlucky run must not decide a zone. */
export const MIN_ZONE_MILES = 6;

/** Genuine-improvement bars, per dimension. Volume bar mirrors the existing
 *  build-gate's `volumeTrend > 1.15` for consistency across the file. Below
 *  these a zone contributes nothing — the bars exist so noise can't accrue
 *  credit, not to cap how much a genuine improvement is worth once it clears
 *  them (that's MAGNITUDE_* below). */
export const VOLUME_IMPROVEMENT_RATIO = 1.15;
export const PACE_IMPROVEMENT_RATIO = 1.02; // ≥2% faster, real not noise

/**
 * MAGNITUDE-SCALED, not flat-per-zone (2026-08-27, corrected same day it
 * shipped). The first version gave every zone that cleared the bar above an
 * identical fixed credit — a session that improved 2.1% counted the same as
 * one that doubled its volume at 8% faster pace. Caught immediately: fed the
 * exact scenario this module was built for (long run +38%/7.3% faster,
 * threshold volume DOUBLED at 8.1% faster, intervals +2.9%) and it landed on
 * "essentially matched to the PR" — discarding almost all the evidence in
 * its own numbers. A pace gain is weighted higher than a volume gain of the
 * same size (running the same distance faster is closer to a direct fitness
 * statement; more volume at an unchanged pace is real but weaker evidence —
 * it can also just be more junk miles). Volume's contribution is capped at a
 * full doubling so one wildly padded zone can't dominate the sum.
 */
export const PACE_GAIN_WEIGHT = 1.0;
export const VOLUME_GAIN_WEIGHT = 0.3;
export const VOLUME_GAIN_CAP = 1.0; // a doubling counts fully; more doesn't count extra

/** Sum-of-zone-scores → a measured, UNSCALED credit. `CREDIT_SCALE` is
 *  ASSERTED, not fit — there is no (training-delta, race-outcome) dataset yet
 *  to calibrate it against (see FITNESS-LEARNING-APPLY.md §1).
 *
 *  `RAW_CREDIT_SANITY_CAP` (2026-08-27, raised from a product cap to a pure
 *  sanity bound) is deliberately generous — it exists only to stop a data
 *  glitch (a corrupted pace, a unit error) from producing an unbounded
 *  number, not to decide how much a genuine improvement is allowed to be
 *  worth. THAT decision — how much training evidence should move the
 *  estimate — depends on who the athlete is: a novice or an athlete newer to
 *  this specific distance has real room a veteran doesn't. A flat cap here
 *  would repeat the exact mistake the flat per-zone credit made, one layer
 *  up. The athlete-aware cap is applied in fitnessPrediction.ts, where
 *  experience level and distance-specific race history are available; this
 *  module stays a context-free MEASUREMENT of the training delta. */
export const CREDIT_SCALE = 0.10;
export const RAW_CREDIT_SANITY_CAP = 0.40;
/** @deprecated kept only so external references don't silently break; use RAW_CREDIT_SANITY_CAP. */
export const MAX_BUILD_CREDIT = RAW_CREDIT_SANITY_CAP;

const ZONE_TYPES: Record<string, ReadonlySet<string>> = {
  easy: new Set(["easy", "recovery"]),
  moderate: new Set(["moderate", "steady"]),
  longRun: new Set(["long_run", "long_wo"]),
  threshold: new Set(["tempo", "threshold", "fartlek", "progression"]),
  interval: new Set(["interval", "intervals", "race_pace"]),
};
/** Unlabeled runs are overwhelmingly easy days in real training logs — the
 *  same assumption `NON_QUALITY_TYPES` makes elsewhere in this file's family. */
const DEFAULT_ZONE = "easy";

export type ZoneKey = keyof typeof ZONE_TYPES;

export interface ZoneSummary {
  miles: number;
  avgPaceSecPerMile: number;
  sessionCount: number;
}

export interface BuildWindowSummary {
  start: string;
  end: string;
  totalMiles: number;
  zones: Partial<Record<ZoneKey, ZoneSummary>>;
}

export interface ZoneComparison {
  zone: ZoneKey;
  volumeRatio: number;
  paceRatio: number | null; // null when either side lacks MIN_ZONE_MILES
  volumeImproved: boolean;
  paceImproved: boolean;
}

export interface BuildComparisonResult {
  eligible: boolean;
  reason: string;
  prior: BuildWindowSummary | null;
  current: BuildWindowSummary | null;
  zones: ZoneComparison[];
  zonesImproved: ZoneKey[];
  creditPct: number;
}

function zoneFor(type: string | undefined): ZoneKey {
  const t = (type ?? "").toLowerCase();
  for (const [zone, types] of Object.entries(ZONE_TYPES)) {
    if (types.has(t)) return zone as ZoneKey;
  }
  return DEFAULT_ZONE;
}

function parseDay(raw: string): Date | null {
  const d = new Date(`${raw.slice(0, 10)}T00:00:00Z`);
  return Number.isNaN(d.getTime()) ? null : d;
}

/** Summarize every workout in [start, end) by zone. Every session counts —
 *  this is deliberately NOT filtered to "quality" types, per the rule above. */
export function summarizeBuildWindow(
  workouts: readonly WorkoutInput[],
  start: Date,
  end: Date,
): BuildWindowSummary {
  const zoneMiles: Partial<Record<ZoneKey, number>> = {};
  const zonePaceWeighted: Partial<Record<ZoneKey, number>> = {};
  const zoneCount: Partial<Record<ZoneKey, number>> = {};
  let totalMiles = 0;

  for (const w of workouts) {
    const d = parseDay(w.date);
    if (!d || d < start || d >= end) continue;
    if (!(w.distanceMiles > 0) || !(w.paceSecondsPerMile > 0)) continue;
    const zone = zoneFor(w.type);
    zoneMiles[zone] = (zoneMiles[zone] ?? 0) + w.distanceMiles;
    zonePaceWeighted[zone] = (zonePaceWeighted[zone] ?? 0) + w.paceSecondsPerMile * w.distanceMiles;
    zoneCount[zone] = (zoneCount[zone] ?? 0) + 1;
    totalMiles += w.distanceMiles;
  }

  const zones: Partial<Record<ZoneKey, ZoneSummary>> = {};
  for (const zone of Object.keys(ZONE_TYPES) as ZoneKey[]) {
    const miles = zoneMiles[zone];
    if (!miles || miles <= 0) continue;
    zones[zone] = {
      miles,
      avgPaceSecPerMile: (zonePaceWeighted[zone] ?? 0) / miles,
      sessionCount: zoneCount[zone] ?? 0,
    };
  }

  return {
    start: start.toISOString().slice(0, 10),
    end: end.toISOString().slice(0, 10),
    totalMiles,
    zones,
  };
}

/**
 * Compare the training block that produced `raceDate` against the block
 * immediately before `now`. Returns creditPct = 0 (inert, not negative) when
 * evidence is thin or training hasn't broadly improved — this signal only
 * ever WIDENS how much improvement decay is allowed to credit; it never adds
 * extra decay itself. The slow direction already has its own evidence bar
 * (the EF gate) and this is not a second implementation of it.
 */
export function compareBuildWindows(
  extendedWorkouts: readonly WorkoutInput[],
  raceDate: Date,
  now: Date,
): BuildComparisonResult {
  const windowMs = BUILD_WINDOW_DAYS * 86_400_000;
  const priorStart = new Date(raceDate.getTime() - windowMs);
  const currentStart = new Date(now.getTime() - windowMs);

  // The race's own build window has to be reachable in the data we were
  // handed — a race older than the fetch horizon degrades to inert, same as
  // every other signal in this pipeline when its inputs are missing.
  const earliestAvailable = extendedWorkouts.reduce<Date | null>((min, w) => {
    const d = parseDay(w.date);
    return d && (min === null || d < min) ? d : min;
  }, null);
  if (earliestAvailable === null || earliestAvailable > priorStart) {
    return {
      eligible: false,
      reason: "the anchor race's build window isn't covered by the fetched history",
      prior: null, current: null, zones: [], zonesImproved: [], creditPct: 0,
    };
  }

  const prior = summarizeBuildWindow(extendedWorkouts, priorStart, raceDate);
  const current = summarizeBuildWindow(extendedWorkouts, currentStart, now);

  if (prior.totalMiles < MIN_ZONE_MILES || current.totalMiles < MIN_ZONE_MILES) {
    return {
      eligible: false,
      reason: "too little logged volume in one or both windows to compare",
      prior, current, zones: [], zonesImproved: [], creditPct: 0,
    };
  }

  const zones: ZoneComparison[] = [];
  for (const zone of Object.keys(ZONE_TYPES) as ZoneKey[]) {
    const p = prior.zones[zone];
    const c = current.zones[zone];
    if (!p || !c) continue; // absent from either side: no comparison, not a manufactured one
    const volumeRatio = c.miles / p.miles;
    const paceRatio = p.miles >= MIN_ZONE_MILES && c.miles >= MIN_ZONE_MILES
      ? p.avgPaceSecPerMile / c.avgPaceSecPerMile // >1 = faster now
      : null;
    zones.push({
      zone,
      volumeRatio,
      paceRatio,
      volumeImproved: volumeRatio >= VOLUME_IMPROVEMENT_RATIO,
      paceImproved: paceRatio !== null && paceRatio >= PACE_IMPROVEMENT_RATIO,
    });
  }

  const zonesImproved = zones.filter((z) => z.volumeImproved || z.paceImproved).map((z) => z.zone);
  // Magnitude-scaled: only zones that cleared their bar contribute (guards
  // against noise), but ONCE cleared, how much they contribute tracks how
  // much they actually improved, not just that they did.
  let scoreSum = 0;
  for (const z of zones) {
    if (!z.volumeImproved && !z.paceImproved) continue;
    const paceGain = z.paceImproved && z.paceRatio !== null ? Math.max(0, z.paceRatio - 1) : 0;
    const volumeGain = z.volumeImproved ? Math.min(Math.max(0, z.volumeRatio - 1), VOLUME_GAIN_CAP) : 0;
    scoreSum += PACE_GAIN_WEIGHT * paceGain + VOLUME_GAIN_WEIGHT * volumeGain;
  }
  const creditPct = Math.min(scoreSum * CREDIT_SCALE, RAW_CREDIT_SANITY_CAP);

  return {
    eligible: true,
    reason: zones.length === 0
      ? "no zone had enough evidence on both sides to compare"
      : `${zonesImproved.length}/${zones.length} comparable zones show genuine improvement`,
    prior, current, zones, zonesImproved, creditPct,
  };
}

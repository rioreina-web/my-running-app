/**
 * Canonical pace ladder for edge functions.
 *
 * This is the server-side twin of `web/src/components/coach/workout-helpers.ts`
 * `derivePaceTableFromGoal`. Any change to the ratio table or training-pace
 * fractions must land in BOTH files — they are the system's single source of
 * truth for turning a goal race time into a full 12-zone pace table, and they
 * must stay in lockstep or `subscribe-to-plan` writes `target_pace` strings
 * that disagree with what the coach sees in the editor.
 *
 * Ladder math (see pace-system-rework.md §2 Core principle):
 *
 *   race-equivalent zones (mp, hm, threshold, tenK, fiveK, threeK, mile)
 *     → ratio table anchored at 10K = 1.0 (ported from iOS PaceCalculator.swift)
 *
 *   training zones (recovery, easy, longRun, moderate, steady)
 *     → fraction of marathon-pace SPEED, not a fixed sec/mi offset — so the
 *       table scales correctly across the full VDOT range (critical: fixed
 *       offsets produced wrong equivalents at elite paces).
 *
 *   threshold (LT) = athlete's 1-hour race pace, computed by interpolating
 *     between 10K and HM (mirrors iOS PaceCalculator.calculateOneHourPace and
 *     web workout-helpers.oneHourPaceSecPerMile). The legacy LT=HM collapse
 *     was wrong for non-elite runners whose HM takes well over an hour.
 *     Coach override still wins when set downstream.
 *
 * The ratio table is the OUTPUT of a well-calibrated VDOT curve — not a
 * reinvention of it. Reference: 2:20:00 marathon → 5K 14:34 / Mile 4:14.
 */

export type PaceZone =
  | "recovery"
  | "easy"
  | "longRun"
  | "moderate"
  | "steady"
  | "mp"
  | "hm"
  | "threshold"
  | "tenK"
  | "fiveK"
  | "threeK"
  | "mile";

// ---------- race-equivalent math (ratio-based) ----------

// Race time ratios anchored to 10K = 1.00. Derived from the same VDOT curve
// used by iOS PaceCalculator.swift. To add a race distance: append a ratio
// here AND the distance (miles) below.
export const RACE_RATIOS_TO_10K = {
  mile:     0.139583,
  "1500m":  0.129167,
  threeK:   0.277083,
  fiveK:    0.481250,
  tenK:     1.000000,
  tenMi:    1.661000,
  half:     2.204167,
  marathon: 4.615625,
} as const;

export type RaceKey = keyof typeof RACE_RATIOS_TO_10K;

export const RACE_DISTANCE_MI: Record<RaceKey, number> = {
  mile:     1.0,
  "1500m":  0.9321,
  threeK:   1.8641,
  fiveK:    3.1069,
  tenK:     6.2137,
  tenMi:    10.0,
  half:     13.1094,
  marathon: 26.2188,
};

// Normalize common string inputs to a RaceKey.
export function raceKeyForInput(raw: string): RaceKey {
  const k = raw.toLowerCase().trim();
  switch (k) {
    case "marathon": case "m":                              return "marathon";
    case "half_marathon": case "half-marathon": case "half":
    case "hm":                                              return "half";
    case "10k": case "tenk":                                return "tenK";
    case "10mi": case "10_mi": case "tenmi":                return "tenMi";
    case "5k": case "fivek":                                return "fiveK";
    case "3k": case "threek":                               return "threeK";
    case "1500m": case "1500":                              return "1500m";
    case "mile": case "1mi": case "one_mile":               return "mile";
    default:                                                return "marathon";
  }
}

// Given a race time at one distance, what equivalent time at another?
export function equivalentRaceTimeSeconds(
  fromDistance: RaceKey,
  fromTimeSeconds: number,
  toDistance: RaceKey,
): number {
  const fromRatio = RACE_RATIOS_TO_10K[fromDistance];
  const toRatio = RACE_RATIOS_TO_10K[toDistance];
  const tenKTime = fromTimeSeconds / fromRatio;
  return tenKTime * toRatio;
}

export function equivalentRacePaceSecPerMile(
  fromDistance: RaceKey,
  fromTimeSeconds: number,
  toDistance: RaceKey,
): number {
  const toTime = equivalentRaceTimeSeconds(fromDistance, fromTimeSeconds, toDistance);
  return toTime / RACE_DISTANCE_MI[toDistance];
}

// ---------- pace adjustments ----------

// Optional fine-tuning applied on top of a base pace zone. Mirrors the web
// `PaceAdjustment` (workout-helpers.ts) and iOS `WorkoutPaceAdjustment`.
// Convention: positive value = slower than base, negative = faster.
export type PaceAdjustmentType = "percent" | "seconds_per_mile" | "seconds_per_km";

export interface PaceAdjustment {
  type: PaceAdjustmentType;
  value: number;
}

const KM_PER_MILE = 1.609344;

// Apply a per-step adjustment on top of a base sec/mile. Returns the base
// untouched when no adjustment is supplied. Mirrors web's
// `adjustedPaceSecPerMile` and iOS's `applyAdjustment`.
export function applyPaceAdjustment(
  baseSecPerMile: number,
  adjustment?: PaceAdjustment | null | undefined,
): number {
  if (!adjustment || !adjustment.value) return baseSecPerMile;
  switch (adjustment.type) {
    case "percent":          return baseSecPerMile * (1 + adjustment.value / 100);
    case "seconds_per_mile": return baseSecPerMile + adjustment.value;
    case "seconds_per_km":   return baseSecPerMile + adjustment.value * KM_PER_MILE;
    default:                 return baseSecPerMile;
  }
}

// Read a step's `paceAdjustment` field defensively. The shape comes from the
// LLM / coach-portal / iOS encoder; we accept anything matching the contract
// and return null otherwise.
export function readPaceAdjustment(raw: unknown): PaceAdjustment | null {
  if (!raw || typeof raw !== "object") return null;
  const obj = raw as Record<string, unknown>;
  const type = obj.type;
  const value = obj.value;
  if (typeof type !== "string" || typeof value !== "number") return null;
  if (type !== "percent" && type !== "seconds_per_mile" && type !== "seconds_per_km") return null;
  return { type, value };
}

// ---------- training-pace math (MP-speed ratios) ----------

// Training paces as a fraction of marathon-pace SPEED — band midpoints of
// the CANONICAL convention locked 2026-06-04 in
// outputs/pace-chart-unified-spec-2026-06-04.md:
//
//   Steady:   100–90% MP speed → midpoint 0.95
//   Moderate:  90–80%          → midpoint 0.85
//   Easy:      80–70%          → midpoint 0.75
//
// These values are IDENTICAL to web's workout-helpers.ts
// TRAINING_MP_SPEED_RATIO and to the engine's TRAINING_PACE_MULTIPLIERS
// (pace-engine.ts expresses the same bands as pace multipliers:
// easy fast = 1/0.80 = 1.25, etc.). The pre-2026-06 server values
// (0.925/0.875/0.765/0.70) were a different band convention and caused
// Maya to see different easy paces on web vs. iOS — that drift is the bug
// this alignment fixes. Pinned by _shared/cross-language-pace-contract.test.ts.
//
// `longRun` and `recovery` are slated to DROP from this table per the
// unified spec (long run is a workout type, recovery is a non-zone
// activity). They're retained for now because recompute-plan-paces'
// zone classifier and subscribe-to-plan's recovery-run materializer
// still index them; values match web's legacy bands exactly.
export const TRAINING_MP_SPEED_RATIO = {
  steady:    0.95,   // midpoint of 100–90%
  moderate:  0.85,   // midpoint of  90–80%
  longRun:   0.80,   // legacy band (85–75%), retained for callers
  easy:      0.75,   // midpoint of  80–70%
  recovery:  0.65,   // midpoint of  70–60%
} as const;

// Explicit fast/slow band bounds — the canonical structure for range
// display. Mirrors web's TRAINING_MP_SPEED_RANGE exactly.
export const TRAINING_MP_SPEED_RANGE = {
  steady:    { fastRatio: 1.00, slowRatio: 0.90 },
  moderate:  { fastRatio: 0.90, slowRatio: 0.80 },
  easy:      { fastRatio: 0.80, slowRatio: 0.70 },
} as const;

// ---------- the ladder ----------

// Turn a single known race pace (sec/mi) at a given distance into the full
// 12-zone pace table. This is the CANONICAL derivation — web and edge must
// produce identical numbers for identical inputs.
export function derivePaceTableFromGoal(
  goalRaceSecPerMile: number,
  raceDistance:
    | "marathon" | "half_marathon" | "10k" | "5k" | "mile"
    | string,
): Record<PaceZone, number> {
  const fromKey = raceKeyForInput(raceDistance);
  const fromTimeSeconds = goalRaceSecPerMile * RACE_DISTANCE_MI[fromKey];

  const pace = (toKey: RaceKey) =>
    equivalentRacePaceSecPerMile(fromKey, fromTimeSeconds, toKey);

  const mpSec = pace("marathon");
  const hmSec = pace("half");
  const tenKSec = pace("tenK");

  const trainingPace = (ratio: number) => mpSec / ratio;

  return {
    recovery:  trainingPace(TRAINING_MP_SPEED_RATIO.recovery),
    easy:      trainingPace(TRAINING_MP_SPEED_RATIO.easy),
    longRun:   trainingPace(TRAINING_MP_SPEED_RATIO.longRun),
    moderate:  trainingPace(TRAINING_MP_SPEED_RATIO.moderate),
    steady:    trainingPace(TRAINING_MP_SPEED_RATIO.steady),
    mp:        mpSec,
    hm:        hmSec,
    threshold: oneHourPaceSecPerMile(tenKSec, hmSec),
    tenK:      tenKSec,
    fiveK:     pace("fiveK"),
    threeK:    pace("threeK"),
    mile:      pace("mile"),
  };
}

/**
 * LT (threshold) = the athlete's 1-hour race pace. Linear interpolation
 * between 10K pace and HM pace by the elapsed-time fraction needed to hit
 * exactly 3600s, then derive pace from the distance that fraction implies.
 *
 *   - 10K takes ≥1hr → return 10K pace (slow runner; 1-hour pace ≤ 10K pace)
 *   - HM takes ≤1hr → return HM pace (fast runner; 1-hour pace ≥ HM pace)
 *
 * MUST mirror web `workout-helpers.oneHourPaceSecPerMile` and iOS
 * `PaceCalculator.calculateOneHourPace` exactly so all three platforms
 * produce identical LT for identical inputs.
 */
export function oneHourPaceSecPerMile(
  tenKSecPerMile: number,
  hmSecPerMile: number,
): number {
  const distance10K = RACE_DISTANCE_MI.tenK;
  const distanceHalf = RACE_DISTANCE_MI.half;
  const time10K = tenKSecPerMile * distance10K;
  const timeHalf = hmSecPerMile * distanceHalf;
  const target = 3600;
  if (time10K >= target) return tenKSecPerMile;
  if (timeHalf <= target) return hmSecPerMile;
  const fraction = (target - time10K) / (timeHalf - time10K);
  const distanceInOneHour = distance10K + fraction * (distanceHalf - distance10K);
  return target / distanceInOneHour;
}

// ---------- confirmed-race anchor (Phase 2 race anchoring) ----------

/**
 * A user-declared race result, as stored on athlete_state.confirmed_races
 * (populated from training_logs.race_result by rebuildAthleteState — see
 * supabase/functions/_shared/athlete-state.ts and migration
 * 20260420100000_add_race_result_to_training_logs.sql).
 */
export interface ConfirmedRace {
  date: string;                       // ISO date
  distance: string;                   // "5K" | "10K" | "half" | "marathon" | "mile" | "3K" | "other"
  finish_time_seconds: number;
  official?: boolean;
  event_name?: string | null;
}

// Distance strings the race-equivalence math (raceKeyForInput) accepts.
// "other" races and unknown distances are excluded because we can't
// project pace from an unknown distance.
const KNOWN_RACE_DISTANCES = new Set([
  "marathon", "m",
  "half_marathon", "half-marathon", "half", "hm",
  "10k", "tenk",
  "10mi", "10_mi", "tenmi",
  "5k", "fivek",
  "3k", "threek",
  "1500m", "1500",
  "mile", "1mi", "one_mile",
]);

/**
 * Pick the strongest race anchor from a list of confirmed races.
 *
 * Rule: most-recent qualifying race wins. Recency-weighted per the
 * 2026-05-28 Q20 roadmap decision ("All distances anchor, recency-
 * weighted. A 1:32 half from 6 weeks ago anchors more strongly than a
 * 3:28 marathon from 2 years ago.").
 *
 * Qualifying = a known race distance the race-equivalence math
 * supports. "other" distance races are skipped because they have no
 * ratio entry.
 *
 * Returns null when no qualifying race exists. Caller falls through to
 * goal-based / athlete_pace_profiles anchor logic.
 */
export function pickAnchorRace(
  races: ConfirmedRace[] | null | undefined,
): { distanceKey: string; finishTimeSeconds: number; date: string } | null {
  if (!races || races.length === 0) return null;

  const qualifying = races
    .filter((r): r is ConfirmedRace =>
      !!r &&
      typeof r.finish_time_seconds === "number" &&
      r.finish_time_seconds > 0 &&
      typeof r.date === "string" &&
      typeof r.distance === "string" &&
      KNOWN_RACE_DISTANCES.has(r.distance.toLowerCase())
    )
    .sort((a, b) => (a.date > b.date ? -1 : 1)); // most recent first

  if (qualifying.length === 0) return null;

  const anchor = qualifying[0];
  return {
    distanceKey: anchor.distance,
    finishTimeSeconds: anchor.finish_time_seconds,
    date: anchor.date,
  };
}

// ---------- convenience: derive from athlete_pace_profiles row ----------

// The `athlete_pace_profiles` table already stores per-distance race paces.
// Prefer the user's actual goal race as the anchor; fall back to whichever
// distance has the highest confidence / is set.
export interface PaceProfileAnchorInput {
  goal_race_distance?: string | null;
  marathon_pace_seconds?: number | null;
  half_pace_seconds?: number | null;
  ten_k_pace_seconds?: number | null;
  five_k_pace_seconds?: number | null;
  mile_pace_seconds?: number | null;
}

// Turn an `athlete_pace_profiles` row into a full 12-zone pace table. Picks
// the anchor in this order (revised 2026-06-04 for Phase 2 race anchoring):
//   0. A confirmed race anchor (most recent qualifying race from
//      athlete_state.confirmed_races). Real fitness > goal aspiration.
//      Recency-weighted per Q20 roadmap decision.
//   1. The athlete's goal_race_distance (if set and that pace is available)
//   2. Marathon pace (the default coaching anchor)
//   3. First-available of: half, 10K, 5K, mile
// Returns null if no race pace is set at all.
export function paceTableFromProfile(
  profile: PaceProfileAnchorInput | null | undefined,
  confirmedRaces?: ConfirmedRace[] | null | undefined,
): Record<PaceZone, number> | null {
  // Race anchor takes priority — the athlete's actual race performance is
  // a more trusted fitness signal than goal time or the per-distance pace
  // cache, which can be derived from goal time (i.e., aspirational). See
  // outputs/phase-2-race-anchoring-plan-2026-06-04.md Sub-task C and
  // outputs/maya-product-roadmap-2026-05-28.md Q20.
  const raceAnchor = pickAnchorRace(confirmedRaces);
  if (raceAnchor) {
    const anchorKey = raceKeyForInput(raceAnchor.distanceKey);
    const raceSecPerMile =
      raceAnchor.finishTimeSeconds / RACE_DISTANCE_MI[anchorKey];
    return derivePaceTableFromGoal(raceSecPerMile, raceAnchor.distanceKey);
  }

  if (!profile) return null;

  const candidates: Array<[string, number | null | undefined]> = [
    ["marathon", profile.marathon_pace_seconds],
    ["half",     profile.half_pace_seconds],
    ["10k",      profile.ten_k_pace_seconds],
    ["5k",       profile.five_k_pace_seconds],
    ["mile",     profile.mile_pace_seconds],
  ];

  // Prefer the goal race if its pace is set.
  if (profile.goal_race_distance) {
    const goalKey = profile.goal_race_distance.toLowerCase();
    const goalMatch = candidates.find(([k, v]) => k === goalKey && v != null);
    if (goalMatch && goalMatch[1] != null) {
      return derivePaceTableFromGoal(goalMatch[1], goalMatch[0]);
    }
  }

  const firstAvailable = candidates.find(([, v]) => v != null);
  if (!firstAvailable || firstAvailable[1] == null) return null;

  return derivePaceTableFromGoal(firstAvailable[1], firstAvailable[0]);
}

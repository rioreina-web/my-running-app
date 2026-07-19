/**
 * doubles.ts — coach-assigned doubles for the adaptive materializer.
 *
 * Phase 2 of outputs/doubles-and-activity-types-spec-2026-07-16.md.
 *
 * Pure, side-effect-free logic (see repo convention: "prefer pure functions
 * for testability"). subscribe-to-plan calls these after easy-fill to decide
 * which easy days become doubles and how big the PM run is; the caller applies
 * the decisions to the scheduled_workouts it already built.
 *
 * Design principles enforced here:
 *   - Coach-assigned first. A coach config with mode assigned|adaptive wins.
 *     Adaptive (volume-triggered) is the fallback only when there's no coach
 *     opinion (self-coached athletes supplying their own config).
 *   - An explicit coach mode:"off" disables doubles — an athlete toggle can
 *     never add hard sessions a coach turned off. Athletes may only dial a
 *     coach-assigned count DOWN.
 *   - Generated PM runs are easy only. PM *quality* stays the coach-authored
 *     path (session:"pm" in the template blob), never auto-generated here.
 *   - Guardrails: never the day before quality or the long run, never the
 *     post-long recovery day, never a rest day, both halves >= the easy floor.
 */

export type DoublesMode = "off" | "assigned" | "adaptive";
export type DoublesDistribution = "split" | "add";

export interface DoublesConfig {
  mode: DoublesMode;
  /** Desired number of PM runs this week (assigned mode). Adaptive mode
   *  derives this from weekly mileage. */
  perWeek: number;
  /** Miles for each generated PM run. */
  rangeMiles: { min: number; max: number };
  /** split: reduce the AM run by the PM miles (weekly volume unchanged).
   *  add:   layer the PM run on top (raises weekly volume). */
  distribution: DoublesDistribution;
  /** Days (0=Mon..6=Sun) that may take a PM run. null = auto-pick easy days. */
  eligibleDows: number[] | null;
  /** Only easy_only is supported for generated doubles. */
  placement: "easy_only";
}

/** One easy AM run the materializer already placed, offered as a double
 *  candidate. */
export interface EasyDayInput {
  dow: number; // 0=Mon..6=Sun
  amMiles: number; // whole miles allocated to the AM run
  isRecovery: boolean; // post-long-run recovery day (excluded from doubling)
}

export interface DoublesContextInput {
  easyDays: EasyDayInput[];
  qualityDows: number[]; // dows carrying a placed quality session
  longRunDow: number | null;
  restDows: number[];
}

export interface DoublesDecision {
  dow: number;
  pmMiles: number;
}

const DEFAULT_RANGE = { min: 3, max: 5 };

const OFF: DoublesConfig = {
  mode: "off",
  perWeek: 0,
  rangeMiles: { ...DEFAULT_RANGE },
  distribution: "split",
  eligibleDows: null,
  placement: "easy_only",
};

function clamp(n: number, lo: number, hi: number): number {
  return Math.max(lo, Math.min(hi, n));
}

function normalizeRange(r?: { min: number; max: number }): { min: number; max: number } {
  const min = Math.max(1, Math.round(r?.min ?? DEFAULT_RANGE.min));
  const max = Math.max(min, Math.round(r?.max ?? DEFAULT_RANGE.max));
  return { min, max };
}

/**
 * Defensive parse of the snake_case JSON stored on plan_templates.doubles_config
 * (coach) or athlete_plan_subscriptions.shape_prefs.doubles (athlete). Both use
 * the same shape. Anything malformed is dropped; returns null when there's
 * nothing meaningful to act on.
 */
export function parseDoublesConfig(raw: unknown): Partial<DoublesConfig> | null {
  if (!raw || typeof raw !== "object") return null;
  const r = raw as Record<string, unknown>;
  const out: Partial<DoublesConfig> = {};

  if (r.mode === "off" || r.mode === "assigned" || r.mode === "adaptive") {
    out.mode = r.mode;
  }
  if (typeof r.per_week === "number" && Number.isFinite(r.per_week)) {
    out.perWeek = Math.max(0, Math.round(r.per_week));
  }
  if (r.range_miles && typeof r.range_miles === "object") {
    const rm = r.range_miles as Record<string, unknown>;
    if (typeof rm.min === "number" && typeof rm.max === "number") {
      out.rangeMiles = normalizeRange({ min: rm.min, max: rm.max });
    }
  }
  if (r.distribution === "split" || r.distribution === "add") {
    out.distribution = r.distribution;
  }
  if (Array.isArray(r.eligible_dows)) {
    out.eligibleDows = r.eligible_dows.filter(
      (x): x is number => typeof x === "number" && x >= 0 && x <= 6,
    );
  }

  // Nothing actionable unless a mode or an explicit count/range was given.
  if (out.mode === undefined && out.perWeek === undefined && out.rangeMiles === undefined) {
    return null;
  }
  out.placement = "easy_only";
  return out;
}

/**
 * Adaptive (volume-triggered) double count. Below ~55 mpw single runs absorb
 * the volume fine; past that, splitting protects recovery and lets total
 * volume climb. Thresholds are deliberately coarse and tunable (spec Part G #4).
 */
export function adaptiveDoublesCount(weeklyMileage: number): number {
  if (weeklyMileage < 55) return 0;
  if (weeklyMileage < 70) return 2;
  if (weeklyMileage < 85) return 3;
  return 4;
}

/**
 * Resolve the effective config from the coach's plan-level config and the
 * athlete's subscription override, given this week's target mileage.
 *
 * Precedence:
 *   1. coach mode "off"          → OFF (athlete cannot re-enable).
 *   2. coach mode assigned/adaptive → coach base; athlete may dial count down
 *      or disable, never add.
 *   3. no coach opinion + athlete assigned/adaptive → athlete base (the
 *      self-coached fallback).
 *   4. otherwise                 → OFF.
 */
export function resolveDoublesConfig(
  coach: Partial<DoublesConfig> | null,
  athlete: Partial<DoublesConfig> | null,
  weeklyTargetMileage: number,
): DoublesConfig {
  if (coach && coach.mode === "off") return { ...OFF };

  let base: Partial<DoublesConfig> | null = null;
  let fromCoach = false;
  if (coach && (coach.mode === "assigned" || coach.mode === "adaptive")) {
    base = coach;
    fromCoach = true;
  } else if (athlete && (athlete.mode === "assigned" || athlete.mode === "adaptive")) {
    base = athlete;
  }
  if (!base || !base.mode) return { ...OFF };

  let perWeek = base.mode === "adaptive"
    ? adaptiveDoublesCount(weeklyTargetMileage)
    : Math.max(0, Math.round(base.perWeek ?? 0));

  // Athlete can only reduce a coach-assigned plan (or switch it off).
  if (fromCoach && athlete) {
    if (athlete.mode === "off") return { ...OFF };
    if (typeof athlete.perWeek === "number") {
      perWeek = Math.min(perWeek, Math.max(0, Math.round(athlete.perWeek)));
    }
  }

  return {
    mode: base.mode,
    perWeek,
    rangeMiles: normalizeRange(base.rangeMiles),
    distribution: base.distribution ?? "split",
    eligibleDows: base.eligibleDows ?? null,
    placement: "easy_only",
  };
}

/**
 * Decide which easy days become doubles and the PM mileage for each.
 * Pure: returns decisions; the caller mutates scheduled_workouts.
 *
 * @param minSplitMiles the materializer's easy-run floor (MIN_EASY_MILES).
 */
export function planDoubles(
  input: DoublesContextInput,
  config: DoublesConfig,
  minSplitMiles: number,
): DoublesDecision[] {
  if (config.mode === "off" || config.perWeek <= 0) return [];

  const qualitySet = new Set(input.qualityDows);
  const isPreQuality = (dow: number): boolean => {
    const next = (dow + 1) % 7;
    return qualitySet.has(next) || next === input.longRunDow;
  };

  const desired = Math.round((config.rangeMiles.min + config.rangeMiles.max) / 2);

  const candidates = input.easyDays
    .filter((d) => {
      if (d.isRecovery) return false; // keep the post-long recovery run easy
      if (isPreQuality(d.dow)) return false; // don't blunt tomorrow's quality/long
      if (config.eligibleDows && !config.eligibleDows.includes(d.dow)) return false;
      // split needs room for two real runs; add only needs a real AM run.
      return config.distribution === "split"
        ? d.amMiles >= 2 * minSplitMiles
        : d.amMiles >= minSplitMiles;
    })
    // Most room first; ties break earliest-in-week for deterministic output.
    .sort((a, b) => b.amMiles - a.amMiles || a.dow - b.dow);

  const decisions: DoublesDecision[] = [];
  for (const d of candidates) {
    if (decisions.length >= config.perWeek) break;
    let pmMiles = clamp(desired, config.rangeMiles.min, config.rangeMiles.max);
    if (config.distribution === "split") {
      // Leave at least the floor on the AM run.
      pmMiles = Math.min(pmMiles, d.amMiles - minSplitMiles);
    }
    if (pmMiles < minSplitMiles) continue; // too small to be a real second run
    decisions.push({ dow: d.dow, pmMiles });
  }

  return decisions.sort((a, b) => a.dow - b.dow);
}

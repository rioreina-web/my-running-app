/**
 * `specificVolume` — how much of a session was run at, around, and either side
 * of GOAL RACE PACE, expressed as the athlete's own ladder of support.
 *
 * WHY A LADDER AND NOT ONE BAND. The coach's first instruction on this was
 * that fitness reads from "not just the specific paces, but the surrounding
 * paces as well" — 70–80% of race speed is the base, ~90% is the steady long
 * run, 95–105% is the specific work, and 5K/10K work sits above. A single
 * "at goal pace" band throws away the shape that makes the reading useful.
 *
 * WHY A LADDER ALSO FIXES A REAL BUG. A two-sided band plus a one-sided heat
 * credit silently loses the hardest summer work: a mile run at 5:25 in Austin
 * August credits to about 5:09, which falls out the FAST edge of a 95–105%
 * window and is counted as absent. Measured across July 2026 that error
 * removed more than half the month's specific volume. Rungs cannot lose work;
 * credited miles simply move up one.
 *
 * PERCENTAGES ARE OF SPEED, NOT OF PACE-TIME. 90% of race speed is SLOWER
 * running, so its pace in seconds per mile is `goalPace / 0.90`. Every
 * boundary here is computed that way. Getting this backwards inverts the
 * entire ladder, so the tests pin it explicitly.
 *
 * WHAT THIS DOES NOT DO. It does not judge whether the volume is right. There
 * is no universal correct answer — a base block and a peak block should look
 * completely different, and the athlete may be following a coach's plan. This
 * module reports; the rule that reads it decides what, if anything, to say.
 */

/** One rung of the ladder, as a percentage-of-goal-speed interval. */
export interface Rung {
  key: RungKey;
  label: string;
  /** Inclusive lower bound, percent of goal race speed. */
  minPct: number;
  /** Exclusive upper bound, percent of goal race speed. */
  maxPct: number;
}

export type RungKey =
  | "recovery"   // under 75% — true easy running
  | "base"       // 75–90% — the aerobic base and most long-run mileage
  | "support"    // 90–95% — endurance support, the steady long run's top end
  | "specific"   // 95–105% — THE specific work; goal pace lives here
  | "speed"      // 105–115% — specific speed, tempo/HMP for a marathoner
  | "power";     // 115%+ — 5K/10K and faster, the aerobic power engine

export const LADDER: Rung[] = [
  { key: "recovery", label: "recovery", minPct: 0, maxPct: 75 },
  { key: "base", label: "base", minPct: 75, maxPct: 90 },
  { key: "support", label: "endurance support", minPct: 90, maxPct: 95 },
  { key: "specific", label: "specific", minPct: 95, maxPct: 105 },
  { key: "speed", label: "specific speed", minPct: 105, maxPct: 115 },
  { key: "power", label: "aerobic power", minPct: 115, maxPct: Infinity },
];

export interface SessionBlock {
  role?: string | null;
  distanceMiles?: number | null;
  /** "M:SS" as `parsed_structure.blocks[].avg_pace_per_mile` stores it. */
  avgPacePerMile?: string | null;
}

export interface SessionLadder {
  goalPaceSecPerMile: number;
  /** Fraction, as `weather_actual.adjustment_pct` stores it: 0.0492 = 4.92%. */
  adjustmentPct: number;
  /** Miles per rung, after the conditions credit. */
  miles: Record<RungKey, number>;
  /** Shorthand for `miles.specific` — the headline KPI. */
  specificMiles: number;
  /** Longest SINGLE block inside the specific rung. Extension, not volume. */
  longestSpecificBlockMiles: number;
  /** Blocks that carried a usable pace and distance. */
  blocksCounted: number;
  /**
   * The parse looks too coarse to trust: a 6+ mile block landed in the
   * specific rung while covering less than 85% of the run.
   *
   * WHY THAT SHAPE. On 2026-03-21 a 15-mile run was parsed into three chunks,
   * two of them 7 miles, and read as 14 miles of goal-pace work. It is not a
   * session, it is a lumped parse. But a genuine 6.25-mile tempo IS a 6+ mile
   * specific block — the difference is that the tempo essentially IS the run,
   * while the artifact is a large chunk buried inside a much longer one.
   *
   * KNOWN FALSE POSITIVE: a real long run finishing with a long continuous
   * marathon-pace segment (say 8 miles inside 21) trips this too. That is the
   * deliberate trade for a first version that must not report a number it
   * cannot stand behind. Cross-check a flagged session against
   * `running_workout_laps` before promoting it.
   */
  suspectCoarseParse: boolean;
}

const EMPTY_MILES: Record<RungKey, number> = {
  recovery: 0, base: 0, support: 0, specific: 0, speed: 0, power: 0,
};

/** "5:37" → 337. Null for anything that is not M:SS. */
export function parsePaceToSeconds(raw: string | null | undefined): number | null {
  if (!raw) return null;
  const m = String(raw).trim().match(/^(\d{1,3}):([0-5]\d)$/);
  if (!m) return null;
  return Number(m[1]) * 60 + Number(m[2]);
}

/**
 * Pace boundary for a percentage of goal SPEED. Higher percent, faster pace,
 * smaller number of seconds.
 */
export function paceForPctOfGoalSpeed(goalPaceSecPerMile: number, pct: number): number {
  return goalPaceSecPerMile / (pct / 100);
}

/** Which rung a pace falls on, as a percentage of goal speed. */
export function rungForPace(goalPaceSecPerMile: number, paceSecPerMile: number): RungKey {
  if (!(paceSecPerMile > 0) || !(goalPaceSecPerMile > 0)) return "recovery";
  const pct = (goalPaceSecPerMile / paceSecPerMile) * 100;
  for (const r of LADDER) {
    if (pct >= r.minPct && pct < r.maxPct) return r.key;
  }
  return "power";
}

/**
 * Apply the conditions credit to a raw pace, producing an effort-equivalent
 * pace. `adjustmentPct` is the fraction stored in `weather_actual`, which now
 * folds in altitude as well as heat.
 *
 * NOTE this model is known to over-credit hot laps by roughly 9 s/mi, so a
 * summer session reads generously. Credit-only: conditions never make a pace
 * count as slower than it was run.
 */
export function effortEquivalentPace(rawPaceSec: number, adjustmentPct: number): number {
  const adj = Number.isFinite(adjustmentPct) ? Math.max(0, adjustmentPct) : 0;
  return rawPaceSec * (1 - adj);
}

export interface LadderOptions {
  /** Blocks whose role matches are excluded outright. Recoveries are not training at pace. */
  excludeRoles?: string[];
  /** Set false to measure raw pace instead of effort-equivalent. */
  applyConditions?: boolean;
  /**
   * The run's total distance, for the coarse-parse check. Defaults to the sum
   * of every block carrying a distance, which is a good enough proxy.
   */
  totalRunMiles?: number | null;
}

const DEFAULT_EXCLUDED_ROLES = ["recovery", "rest", "warmup", "warm_up", "cooldown", "cool_down"];
const COARSE_BLOCK_MILES = 6;
/** At or above this share of the run, a big block reads as a tempo, not a lump. */
const COARSE_RUN_SHARE = 0.85;

/**
 * Lay one session's blocks onto the ladder.
 *
 * Recovery jogs between reps are dropped, not binned: a 7:45 float inside an
 * interval session is structural, and counting it as "base" would inflate the
 * base rung on exactly the days that are least about base running.
 */
export function sessionLadder(
  blocks: SessionBlock[],
  goalPaceSecPerMile: number,
  adjustmentPct = 0,
  opts: LadderOptions = {},
): SessionLadder {
  const excluded = new Set((opts.excludeRoles ?? DEFAULT_EXCLUDED_ROLES).map((r) => r.toLowerCase()));
  const applyConditions = opts.applyConditions !== false;

  const miles: Record<RungKey, number> = { ...EMPTY_MILES };
  let longestSpecific = 0;
  let counted = 0;
  let biggestSpecificBlock = 0;

  // Denominator for the coarse check: the whole run, including the recoveries
  // and warmup that the ladder itself skips.
  const runMiles = Number(opts.totalRunMiles ?? 0) > 0
    ? Number(opts.totalRunMiles)
    : (blocks ?? []).reduce((sum, b) => sum + Math.max(0, Number(b?.distanceMiles ?? 0)), 0);

  for (const b of blocks ?? []) {
    const role = String(b?.role ?? "").toLowerCase();
    if (excluded.has(role)) continue;

    const mi = Number(b?.distanceMiles ?? 0);
    const rawPace = parsePaceToSeconds(b?.avgPacePerMile);
    if (!(mi > 0) || rawPace == null) continue;

    const pace = applyConditions ? effortEquivalentPace(rawPace, adjustmentPct) : rawPace;
    const rung = rungForPace(goalPaceSecPerMile, pace);
    miles[rung] += mi;
    counted += 1;

    if (rung === "specific") {
      if (mi > longestSpecific) longestSpecific = mi;
      if (mi > biggestSpecificBlock) biggestSpecificBlock = mi;
    }
  }

  const suspect = biggestSpecificBlock >= COARSE_BLOCK_MILES &&
    runMiles > 0 &&
    biggestSpecificBlock / runMiles < COARSE_RUN_SHARE;

  for (const k of Object.keys(miles) as RungKey[]) {
    miles[k] = Math.round(miles[k] * 100) / 100;
  }

  return {
    goalPaceSecPerMile,
    adjustmentPct,
    miles,
    specificMiles: miles.specific,
    longestSpecificBlockMiles: Math.round(longestSpecific * 100) / 100,
    blocksCounted: counted,
    suspectCoarseParse: suspect,
  };
}

/** A session as it comes out of `training_logs`, before laddering. */
export interface SessionInput {
  id: string;
  date: string;
  blocks: SessionBlock[];
  adjustmentPct?: number | null;
  /** `training_logs.workout_distance_miles`, for the coarse-parse check. */
  totalRunMiles?: number | null;
}

export interface SpecificVolumeWindow {
  /** Biggest single session's specific volume in the window. THE KPI. */
  bestSessionMiles: number;
  bestSessionId: string | null;
  bestSessionDate: string | null;
  /** Longest single continuous piece at specific pace anywhere in the window. */
  longestBlockMiles: number;
  /** Every session's specific volume, summed. */
  totalSpecificMiles: number;
  /** Sessions carrying at least a mile of specific work. */
  sessionsWithSpecificWork: number;
  /** Whole-window rung totals, for reading the funnel's shape. */
  miles: Record<RungKey, number>;
  /** Sessions whose parse looked too coarse to trust. */
  suspectSessions: string[];
}

/**
 * Roll sessions up over a window.
 *
 * The headline is the BEST SINGLE SESSION, not the sum. The coach's targets
 * are session volumes — "10 to 15 miles at goal marathon pace", "6 to 9 miles
 * of volume" for a half — because what a race asks for is one continuous
 * effort, not a month's accumulation.
 */
export function specificVolumeOverWindow(
  sessions: SessionInput[],
  goalPaceSecPerMile: number,
  opts: LadderOptions = {},
): SpecificVolumeWindow {
  const miles: Record<RungKey, number> = { ...EMPTY_MILES };
  let best = 0, bestId: string | null = null, bestDate: string | null = null;
  let longest = 0, withWork = 0;
  const suspect: string[] = [];

  for (const s of sessions ?? []) {
    const l = sessionLadder(s.blocks, goalPaceSecPerMile, Number(s.adjustmentPct ?? 0), {
      ...opts,
      totalRunMiles: s.totalRunMiles ?? opts.totalRunMiles ?? null,
    });
    for (const k of Object.keys(miles) as RungKey[]) miles[k] += l.miles[k];

    if (l.specificMiles >= 1) withWork += 1;
    if (l.longestSpecificBlockMiles > longest) longest = l.longestSpecificBlockMiles;
    if (l.suspectCoarseParse) suspect.push(s.id);
    // A suspect parse must not become the athlete's best session.
    if (!l.suspectCoarseParse && l.specificMiles > best) {
      best = l.specificMiles;
      bestId = s.id;
      bestDate = s.date;
    }
  }

  for (const k of Object.keys(miles) as RungKey[]) miles[k] = Math.round(miles[k] * 100) / 100;

  return {
    bestSessionMiles: Math.round(best * 100) / 100,
    bestSessionId: bestId,
    bestSessionDate: bestDate,
    longestBlockMiles: Math.round(longest * 100) / 100,
    totalSpecificMiles: miles.specific,
    sessionsWithSpecificWork: withWork,
    miles,
    suspectSessions: suspect,
  };
}

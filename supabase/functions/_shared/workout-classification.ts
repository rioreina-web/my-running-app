/**
 * Workout classification — lap-first, pace-relative.
 *
 * WHY THIS EXISTS (WS1 of the Read redesign, 2026-06-13):
 * The previous intensity scorer (`compute-workout-features`) classified each
 * pace segment by a stored `effort` *label* and read per-mile splits. In
 * practice the labels were wrong/missing ("fast" wasn't even in the weight
 * table) and per-mile splits average a rep + its jog recovery into one ~easy
 * mile — so a 10×1K @ 5:07 with 90s float recorded as "9 mi @ 6:20" scored as
 * easy. Result: real quality work was invisible (0 quality sessions for an
 * athlete doing weekly intervals).
 *
 * This module fixes that by:
 *   1. Reading rep-level `running_workout_laps` (which carry `is_rest`).
 *   2. Separating work reps from recovery.
 *   3. Classifying each work rep by its ACTUAL pace against the athlete's own
 *      pace zones (not a stored label).
 *   4. Deriving an intensity-weighted score, work/recovery time-in-zone, a
 *      workout TYPE (intervals / threshold / tempo / fartlek / easy / long /
 *      race) and a human structure string ("9×1K @ 5:08").
 *
 * Pure functions only — no I/O — so this is unit-testable and can feed BOTH
 * `compute-workout-features` and the athlete-state `execution` block (one
 * segmentation engine, not two). See `workout-classification.test.ts`.
 */

// ── Zone scale (canonical 1–5 intensity, matches compute-workout-features) ──
export type ZoneName =
  | "recovery" | "easy" | "moderate" | "steady" | "mp"
  | "threshold" | "tenK" | "fiveK" | "threeK" | "mile";

export const ZONE_WEIGHT: Record<ZoneName, number> = {
  recovery: 1.0, easy: 1.0, moderate: 1.5, steady: 2.0, mp: 2.5,
  threshold: 3.0, tenK: 3.5, fiveK: 4.0, threeK: 4.5, mile: 5.0,
};

/** Pace zones in seconds-per-mile. A subset of `derivePaceTableFromGoal`. */
export interface PaceZones {
  mile: number; fiveK: number; threeK: number; tenK: number; threshold: number;
  mp: number; steady: number; moderate: number; easy: number;
}

/** Ordered fast → slow for nearest-center classification. */
const ZONE_ORDER: (keyof PaceZones)[] = [
  "mile", "fiveK", "threeK", "tenK", "threshold", "mp", "steady", "moderate", "easy",
];

/**
 * Map an actual pace (sec/mi) to the athlete's nearest pace zone. Faster pace
 * → harder zone. Anything well slower than easy is recovery.
 */
export function classifyPace(paceSecPerMile: number, z: PaceZones): ZoneName {
  if (!paceSecPerMile || paceSecPerMile <= 0) return "easy";
  if (paceSecPerMile > z.easy + 25) return "recovery";
  let best: ZoneName = "easy";
  let bestDist = Infinity;
  for (const k of ZONE_ORDER) {
    const center = z[k];
    const d = Math.abs(paceSecPerMile - center);
    if (d < bestDist) { bestDist = d; best = k; }
  }
  return best;
}

// ── Lap input (subset of running_workout_laps) ──────────────────────────────
export interface ClassifierLap {
  distance_meters: number | null;
  moving_time_seconds: number | null;
  avg_pace_sec_per_mile: number | null;
  avg_heart_rate?: number | null;
  is_rest?: boolean | null;
}

export interface WorkoutClassification {
  /** intervals | threshold | tempo | fartlek | easy | long_run | race | workout */
  type: string;
  /** human structure, e.g. "9×1K @ 5:08" or "5mi @ 5:43". null for easy/long. */
  structure: string | null;
  /** time-weighted average zone weight across the whole session. */
  intensityScore: number;
  easySeconds: number;
  moderateSeconds: number;
  thresholdSeconds: number;
  hardSeconds: number;
  /** total seconds of detected work (non-recovery quality). */
  workSeconds: number;
  /** total meters of detected work. */
  workMeters: number;
  repCount: number;
  /** true when classified as a quality session (not easy/long). */
  isQuality: boolean;
}

const MILE_M = 1609.34;

function isWorkLap(lap: ClassifierLap, z: PaceZones): boolean {
  if (lap.is_rest) return false;
  const sec = lap.moving_time_seconds ?? 0;
  const dist = lap.distance_meters ?? 0;
  if (sec < 20 || dist < 150) return false; // too short to be a rep
  const zone = classifyPace(lap.avg_pace_sec_per_mile ?? 0, z);
  return ZONE_WEIGHT[zone] >= 2.0; // steady or faster counts as work
}

function mean(a: number[]): number { return a.length ? a.reduce((s, x) => s + x, 0) / a.length : 0; }
function pstdev(a: number[]): number {
  if (a.length < 2) return 0;
  const m = mean(a);
  return Math.sqrt(mean(a.map((x) => (x - m) ** 2)));
}
function pace(sec: number): string {
  sec = Math.round(sec);
  return `${Math.floor(sec / 60)}:${String(sec % 60).padStart(2, "0")}`;
}
function repLabel(meters: number): string {
  const near = (t: number, tol: number) => Math.abs(meters - t) <= tol;
  if (near(MILE_M, 90)) return "1mi";
  if (near(1000, 80)) return "1K";
  if (near(800, 70)) return "800m";
  if (near(600, 70)) return "600m";
  if (near(400, 60)) return "400m";
  if (near(300, 55)) return "300m";
  if (near(200, 45)) return "200m";
  return `${Math.round(meters / 100) * 100}m`;
}

/**
 * Classify a single session from its laps + the athlete's pace zones.
 * `totalDistanceMiles` is used only for the easy-vs-long decision when there
 * is no detected work.
 */
export function classifyWorkout(
  laps: ClassifierLap[],
  zones: PaceZones,
  totalDistanceMiles: number,
): WorkoutClassification {
  let easySeconds = 0, moderateSeconds = 0, thresholdSeconds = 0, hardSeconds = 0;
  let weightedSum = 0, totalSeconds = 0;
  let workSeconds = 0, workMeters = 0;
  const workDists: number[] = [];
  const workZones: ZoneName[] = [];

  for (const lap of laps) {
    const sec = lap.moving_time_seconds ?? 0;
    if (sec <= 0) continue;
    const zone = lap.is_rest ? "recovery" : classifyPace(lap.avg_pace_sec_per_mile ?? 0, zones);
    const w = ZONE_WEIGHT[zone];
    weightedSum += w * sec;
    totalSeconds += sec;

    if (isWorkLap(lap, zones)) {
      workSeconds += sec;
      workMeters += lap.distance_meters ?? 0;
      workDists.push(lap.distance_meters ?? 0);
      workZones.push(zone);
      if (zone === "threshold" || zone === "mp") thresholdSeconds += sec;
      else if (ZONE_WEIGHT[zone] >= 3.5) hardSeconds += sec; // 10K or faster
      else moderateSeconds += sec; // steady work
    } else if (zone === "moderate" || zone === "steady" || zone === "mp") {
      moderateSeconds += sec;
    } else {
      easySeconds += sec;
    }
  }

  const intensityScore = totalSeconds > 0 ? weightedSum / totalSeconds : 0;
  const restCount = laps.filter((l) => l.is_rest).length;
  const reps = workDists.length;

  // ── No work → easy or long run ──
  if (reps === 0) {
    return {
      type: totalDistanceMiles >= 11 ? "long_run" : "easy",
      structure: null,
      intensityScore: round2(intensityScore),
      easySeconds, moderateSeconds, thresholdSeconds, hardSeconds,
      workSeconds: 0, workMeters: 0, repCount: 0, isQuality: false,
    };
  }

  const avgWeight = mean(workZones.map((z) => ZONE_WEIGHT[z]));
  const avgRep = mean(workDists);
  const distCv = avgRep > 0 ? pstdev(workDists) / avgRep : 0;
  const hasRest = restCount >= 2;

  // ── Type decision tree (validated against real data 2026-06-13) ──
  let type: string;
  if (avgWeight >= 3.5 && hasRest) {
    type = "intervals";                                   // VO2 / 5K / 10K reps
  } else if (avgWeight >= 3.0 && avgRep >= 1400 && distCv < 0.15 && restCount <= 2) {
    type = "threshold";                                   // mile cruise reps
  } else if (avgWeight >= 3.0 && hasRest) {
    type = "threshold";                                   // threshold reps w/ rest
  } else if (!hasRest && avgWeight >= 2.0 && avgWeight < 3.5) {
    type = "tempo";                                       // sustained MP–LT block
  } else if (distCv >= 0.3) {
    type = "fartlek";                                     // irregular surges
  } else {
    type = "workout";                                     // generic quality
  }

  return {
    type,
    structure: buildStructure(workDists, workZones, zones),
    intensityScore: round2(intensityScore),
    easySeconds, moderateSeconds, thresholdSeconds, hardSeconds,
    workSeconds, workMeters, repCount: reps, isQuality: true,
  };
}

function buildStructure(dists: number[], zones: ZoneName[], _z: PaceZones): string {
  // group by rep label, preserving order of first appearance
  const groups: { label: string; count: number }[] = [];
  for (const d of dists) {
    const lbl = repLabel(d);
    const last = groups[groups.length - 1];
    if (last && last.label === lbl) last.count++;
    else groups.push({ label: lbl, count: 1 });
  }
  const struct = groups.map((g) => `${g.count}×${g.label}`).join(" + ");
  // dominant work zone for a representative pace tag
  const domZone = zones.slice().sort((a, b) => ZONE_WEIGHT[b] - ZONE_WEIGHT[a])[0];
  return `${struct} (${domZone})`;
}

function round2(n: number): number { return Math.round(n * 100) / 100; }

/**
 * Build the classifier's PaceZones from the canonical derived pace table
 * (output of `derivePaceTableFromGoal` / `paceTableFromProfile`). Maps the
 * full table's keys onto the subset the classifier needs.
 */
export function paceZonesFromTable(
  t: { mile: number; fiveK: number; threeK: number; tenK: number; threshold: number; mp: number; steady: number; moderate: number; easy: number },
): PaceZones {
  return {
    mile: t.mile, fiveK: t.fiveK, threeK: t.threeK, tenK: t.tenK,
    threshold: t.threshold, mp: t.mp, steady: t.steady, moderate: t.moderate, easy: t.easy,
  };
}

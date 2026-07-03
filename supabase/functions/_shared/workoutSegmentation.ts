// ============================================================================
// Workout segmentation & intensity classification (WS1)
//
// Single source of truth for "what was this workout, really?" — consumed by
// BOTH `compute-workout-features` (load scoring) and `athlete-state.ts`
// (execution display). Pure functions, no I/O, so the logic can be unit
// tested directly (see _shared/__tests__/workoutSegmentation.test.ts).
//
// The old path classified by a stored `effort` *label* on per-mile
// `pace_segments`. That was doubly broken: (1) per-mile splits average a
// 9×1K @ 5:08 session down to ~6:20 easy splits, destroying rep structure;
// (2) labels in prod are wrong/missing ("fast" wasn't even in the weight
// table → scored as easy). This module reads rep-level `running_workout_laps`
// and classifies every bout by its ACTUAL pace against the athlete's pace
// zones. Pace is the source of truth; `is_rest` is a hint, not the verdict.
// ============================================================================

// ── Canonical intensity weights (1–5 scale, decision 2026-06-12) ──
// ONE scale used everywhere — the load math, athlete_state.volume_x_intensity,
// and the training-load chart all read these numbers. Recovery folds into
// easy (1.0). A minute at mile pace ≈ 5 easy minutes of mechanical load.
export const ZONE_WEIGHTS: Record<Zone, number> = {
  recovery: 1.0,
  easy: 1.0,
  moderate: 1.5,
  steady: 2.0,
  mp: 2.5, // marathon pace
  hmp: 3.0, // half-marathon / threshold / LT band
  "10k": 3.5,
  "5k": 4.0,
  "3k": 4.5,
  mile: 5.0, // VO2max+ repeats
};

export type Zone =
  | "mile"
  | "3k"
  | "5k"
  | "10k"
  | "hmp"
  | "mp"
  | "steady"
  | "moderate"
  | "easy"
  | "recovery";

// Zones at or faster than MP count as "work" (faster than steady). Anything
// slower is aerobic background (easy/steady running, warmup, cooldown, float).
const WORK_ZONES: ReadonlySet<Zone> = new Set<Zone>(["mile", "3k", "5k", "10k", "hmp", "mp"]);
// Race-pace-and-faster — these drive `hard_seconds`.
const HARD_ZONES: ReadonlySet<Zone> = new Set<Zone>(["mile", "3k", "5k", "10k"]);
// The threshold band drives `threshold_seconds`.
const THRESHOLD_ZONES: ReadonlySet<Zone> = new Set<Zone>(["hmp"]);

// Detection-oriented session label. Aligns with the closed scheduling enum in
// outputs/workout-system-rebuild.md where it can (long_run/intervals/tempo/
// fartlek/easy/recovery/race/progression) and keeps `threshold` as a distinct
// *detection* label — the scheduling enum collapses threshold→tempo/intervals,
// but the Read and the quality-count need the finer distinction.
export type WorkoutKind =
  | "intervals"
  | "threshold"
  | "tempo"
  | "fartlek"
  | "progression"
  | "long_run"
  | "easy"
  | "recovery"
  | "race";

const METERS_PER_MILE = 1609.344;

// A rep must be a real sustained effort, not a GPS blip or a watch mis-split.
const MIN_REP_SECONDS = 20;
const MIN_REP_METERS = 150;

// ── Pace zones as supplied by athlete_state.pace_zones ──
// Keys mirror the stored shape: { mile, fiveK, tenK, hm, mp, steady, moderate,
// easy } in sec/mile. All optional — graceful degradation when thin.
export interface PaceZones {
  mile?: number | null;
  fiveK?: number | null;
  threeK?: number | null;
  tenK?: number | null;
  hm?: number | null; // half-marathon pace == HMP == threshold band anchor
  mp?: number | null;
  steady?: number | null;
  moderate?: number | null;
  easy?: number | null;
}

interface ZoneAnchor {
  zone: Zone;
  pace: number;
}

/**
 * Ordered fast→slow anchor list from the athlete's zones. A bout classifies
 * to a zone by midpoint cutoffs between consecutive anchors — athlete-relative,
 * no hardcoded paces. Aerobic boundaries (steady/moderate/easy) are inherently
 * fuzzy (those zones ship as ±5% ranges); the precise quality boundaries
 * (mile/5k/10k/hmp) are what matter and those are tight.
 */
export function buildZoneAnchors(z: PaceZones): ZoneAnchor[] {
  const raw: Array<[Zone, number | null | undefined]> = [
    ["mile", z.mile],
    ["3k", z.threeK],
    ["5k", z.fiveK],
    ["10k", z.tenK],
    ["hmp", z.hm],
    ["mp", z.mp],
    ["steady", z.steady],
    ["moderate", z.moderate],
    ["easy", z.easy],
  ];
  return raw
    .filter((e): e is [Zone, number] => typeof e[1] === "number" && e[1] > 0)
    .map(([zone, pace]) => ({ zone, pace }))
    .sort((a, b) => a.pace - b.pace);
}

/**
 * Classify a single pace (sec/mile) to a zone using midpoint cutoffs between
 * consecutive anchors. Anything slower than `easy + 9%` is `recovery`.
 * Returns `easy` when zones are unavailable (can't do better, don't lie).
 */
export function paceToZone(paceSecPerMile: number, anchors: ZoneAnchor[]): Zone {
  if (!isFinite(paceSecPerMile) || paceSecPerMile <= 0) return "easy";
  if (anchors.length === 0) return "easy";
  for (let i = 0; i < anchors.length; i++) {
    const cur = anchors[i];
    const next = anchors[i + 1];
    if (!next) {
      // Slowest anchor (easy). Beyond it by a margin → recovery.
      return paceSecPerMile <= cur.pace * 1.09 ? cur.zone : "recovery";
    }
    const cutoff = (cur.pace + next.pace) / 2;
    if (paceSecPerMile <= cutoff) return cur.zone;
  }
  return "recovery";
}

// ── Lap & bout shapes ──

export interface LapInput {
  lap_index?: number | null;
  is_rest?: boolean | null;
  distance_meters?: number | null;
  avg_pace_sec_per_mile?: number | null;
  moving_time_seconds?: number | null;
  elapsed_time_seconds?: number | null;
  avg_heart_rate?: number | null;
}

export interface Bout {
  zone: Zone;
  seconds: number;
  distanceMeters: number;
  paceSecPerMile: number;
  avgHr: number | null;
  isWork: boolean; // pace faster than steady
  isRest: boolean; // flagged or detected recovery between efforts
  isRep: boolean; // a work bout that passes the rep guards (counts in structure)
}

export interface SegmentationResult {
  source: "laps" | "segments" | "overall";
  bouts: Bout[];
  reps: Bout[];
  repCount: number;
  repPaces: string[]; // "M:SS" per rep, in order
  // Zone-time buckets (seconds) — match workout_features columns.
  easySeconds: number;
  moderateSeconds: number;
  thresholdSeconds: number;
  hardSeconds: number;
  totalSeconds: number;
  totalMeters: number;
  intensityScore: number;
  // Derived classification.
  workoutKind: WorkoutKind;
  structure: string | null;
  // Convenience execution stats (used by athlete-state display).
  paceCvPct: number | null;
  fadePct: number | null;
  hrDriftPct: number | null;
  shape: "negative split" | "even" | "faded" | null;
}

const secondsOf = (lap: LapInput): number => {
  const mov = Number(lap.moving_time_seconds ?? 0);
  if (mov > 0) return mov;
  const el = Number(lap.elapsed_time_seconds ?? 0);
  if (el > 0) return el;
  // Fall back to distance × pace.
  const d = Number(lap.distance_meters ?? 0);
  const p = Number(lap.avg_pace_sec_per_mile ?? 0);
  return d > 0 && p > 0 ? (d / METERS_PER_MILE) * p : 0;
};

/**
 * Segment a workout from rep-level laps. This is the preferred path — laps
 * carry `is_rest` and rep-level pace. Trust `is_rest` for *recovery* but still
 * require a work lap to clear the pace+duration guards before it counts as a
 * rep (a non-rest float at 9:54/mi is not a 5K rep).
 */
export function segmentFromLaps(laps: LapInput[], zones: PaceZones): SegmentationResult {
  const anchors = buildZoneAnchors(zones);
  const bouts: Bout[] = [];

  for (const lap of laps) {
    const seconds = secondsOf(lap);
    const distanceMeters = Number(lap.distance_meters ?? 0);
    const paceSecPerMile = Number(lap.avg_pace_sec_per_mile ?? 0);
    if (seconds <= 0) continue;

    const flaggedRest = lap.is_rest === true;
    const zone = paceToZone(paceSecPerMile, anchors);
    const isWork = !flaggedRest && WORK_ZONES.has(zone);
    // Recovery: explicitly flagged, OR a slow bout sandwiched between efforts.
    const isRest = flaggedRest || (!isWork && (zone === "recovery"));
    const isRep =
      isWork && seconds >= MIN_REP_SECONDS && distanceMeters >= MIN_REP_METERS;

    bouts.push({
      zone,
      seconds,
      distanceMeters,
      paceSecPerMile,
      avgHr: lap.avg_heart_rate != null && Number(lap.avg_heart_rate) > 0
        ? Number(lap.avg_heart_rate)
        : null,
      isWork,
      isRest,
      isRep,
    });
  }

  return finalize(bouts, "laps");
}

/**
 * Fallback: segment from per-mile `pace_segments`. Coarser (splits blur rep
 * structure) but still classifies by ACTUAL pace, not the broken label table.
 */
export interface PaceSegmentInput {
  effort?: string | null;
  distance_miles?: number | null;
  duration_seconds?: number | null;
  pace_per_mile?: string | null;
  avg_heart_rate?: number | null;
}

export function segmentFromPaceSegments(
  segments: PaceSegmentInput[],
  zones: PaceZones,
): SegmentationResult {
  const anchors = buildZoneAnchors(zones);
  const bouts: Bout[] = [];
  for (const seg of segments) {
    const seconds = Number(seg.duration_seconds ?? 0);
    if (seconds <= 0) continue;
    const distanceMeters = Number(seg.distance_miles ?? 0) * METERS_PER_MILE;
    const paceSecPerMile = parsePace(seg.pace_per_mile);
    const zone = paceToZone(paceSecPerMile, anchors);
    const isWork = WORK_ZONES.has(zone);
    bouts.push({
      zone,
      seconds,
      distanceMeters,
      paceSecPerMile,
      avgHr: seg.avg_heart_rate != null && Number(seg.avg_heart_rate) > 0
        ? Number(seg.avg_heart_rate)
        : null,
      isWork,
      isRest: !isWork && zone === "recovery",
      isRep: isWork && seconds >= MIN_REP_SECONDS && distanceMeters >= MIN_REP_METERS,
    });
  }
  return finalize(bouts, "segments");
}

/** Last-resort: one undifferentiated easy block. */
export function segmentFromOverall(
  totalDurationSeconds: number,
  totalDistanceMiles: number,
): SegmentationResult {
  const bouts: Bout[] = [];
  if (totalDurationSeconds > 0) {
    bouts.push({
      zone: "easy",
      seconds: totalDurationSeconds,
      distanceMeters: totalDistanceMiles * METERS_PER_MILE,
      paceSecPerMile: totalDistanceMiles > 0
        ? totalDurationSeconds / totalDistanceMiles
        : 0,
      avgHr: null,
      isWork: false,
      isRest: false,
      isRep: false,
    });
  }
  return finalize(bouts, "overall");
}

// ── Core aggregation + classification ──

function finalize(bouts: Bout[], source: SegmentationResult["source"]): SegmentationResult {
  let easySeconds = 0, moderateSeconds = 0, thresholdSeconds = 0, hardSeconds = 0;
  let weightedSum = 0, totalSeconds = 0, totalMeters = 0;

  for (const b of bouts) {
    totalSeconds += b.seconds;
    totalMeters += b.distanceMeters;
    weightedSum += b.seconds * ZONE_WEIGHTS[b.zone];
    if (HARD_ZONES.has(b.zone)) hardSeconds += b.seconds;
    else if (THRESHOLD_ZONES.has(b.zone)) thresholdSeconds += b.seconds;
    else if (b.zone === "mp" || b.zone === "steady" || b.zone === "moderate") {
      moderateSeconds += b.seconds;
    } else easySeconds += b.seconds;
  }

  const reps = bouts.filter((b) => b.isRep);
  const intensityScore = totalSeconds > 0 ? weightedSum / totalSeconds : 0;

  const repPacesNum = reps.map((r) => r.paceSecPerMile).filter((p) => p > 0);
  const paceCvPct = cv(repPacesNum);
  const fadePct = repPacesNum.length >= 2
    ? ((repPacesNum[repPacesNum.length - 1] - repPacesNum[0]) / repPacesNum[0]) * 100
    : null;
  const workHrs = reps.map((r) => r.avgHr).filter((h): h is number => h != null && h > 0);
  const hrDriftPct = workHrs.length >= 2
    ? ((workHrs[workHrs.length - 1] - workHrs[0]) / workHrs[0]) * 100
    : null;
  const shape = fadePct == null
    ? null
    : fadePct < -1 ? "negative split" : fadePct > 1.5 ? "faded" : "even";

  const { workoutKind, structure } = classifySession(bouts, reps, totalMeters);

  return {
    source,
    bouts,
    reps,
    repCount: reps.length,
    repPaces: reps.map((r) => fmtPace(r.paceSecPerMile)).filter((s): s is string => s != null),
    easySeconds,
    moderateSeconds,
    thresholdSeconds,
    hardSeconds,
    totalSeconds,
    totalMeters,
    intensityScore: round2(intensityScore),
    workoutKind,
    structure,
    paceCvPct: paceCvPct == null ? null : round1(paceCvPct * 100),
    fadePct: fadePct == null ? null : round1(fadePct),
    hrDriftPct: hrDriftPct == null ? null : round1(hrDriftPct),
    shape,
  };
}

/**
 * The decision tree (spec WS1 "Classifier"). Operates on detected reps + the
 * full bout list. Priority order matters.
 */
function classifySession(
  bouts: Bout[],
  reps: Bout[],
  totalMeters: number,
): { workoutKind: WorkoutKind; structure: string | null } {
  const totalMiles = totalMeters / METERS_PER_MILE;

  // No quality work detected.
  if (reps.length === 0) {
    // A race recorded as one continuous block (no rest laps) shows up here:
    // sustained work covering most of the run at race pace.
    const race = detectContinuousRace(bouts, totalMeters);
    if (race) return race;
    if (totalMiles >= 11) {
      return { workoutKind: "long_run", structure: `${round1(totalMiles)} mi long` };
    }
    // Distinguish recovery (very slow / short) from easy.
    const avgZone = dominantZone(bouts);
    if (avgZone === "recovery") return { workoutKind: "recovery", structure: null };
    return { workoutKind: "easy", structure: null };
  }

  const dominant = dominantZone(reps);
  const avgRepMeters = mean(reps.map((r) => r.distanceMeters));
  const restCount = bouts.filter((b) => b.isRest).length;
  const hasRest = restCount > 0;
  const repDistCv = cv(reps.map((r) => r.distanceMeters)) ?? 0;
  const repPaceCv = cv(reps.map((r) => r.paceSecPerMile)) ?? 0;
  const shortReps = avgRepMeters < 1300; // under ~0.8 mi
  const longReps = avgRepMeters >= METERS_PER_MILE * 0.95; // ~1 mi+
  const label = (k: string) => structureString(reps, k);

  // Race: one or two sustained efforts, no rest, ≥3 mi, at race pace.
  const race = detectContinuousRace(bouts, totalMeters);
  if (race && !hasRest && (dominant === "5k" || dominant === "10k")) return race;

  // Fartlek: irregular rep length AND pace, without clean recovery structure.
  if (repDistCv > 0.45 && repPaceCv > 0.06 && restCount < reps.length / 2) {
    return { workoutKind: "fartlek", structure: label("fartlek") };
  }

  // Progression: same-distance reps clearly getting faster across the session.
  // (Uniform distance guard so a threshold set with trailing strides — e.g.
  // 4×1K @ threshold + 2×300m — doesn't read as a progression.)
  if (reps.length >= 3 && repDistCv < 0.15 && isMonotonicFaster(reps)) {
    return { workoutKind: "progression", structure: label("progression") };
  }

  // Threshold (cruise): long reps (≥~1mi) at LT/10K/HMP pace, tight CV. Checked
  // BEFORE the interval branches — long mile reps at 10K pace are cruise work,
  // not VO2 intervals. Rep length is the discriminator (short=intervals).
  if (longReps && (dominant === "hmp" || dominant === "10k") && (repPaceCv ?? 1) < 0.04) {
    return { workoutKind: "threshold", structure: label("threshold") };
  }

  // Intervals (VO2 / 5K / mile): short reps + rest at 5K/3K/mile pace.
  if (shortReps && hasRest && (dominant === "5k" || dominant === "3k" || dominant === "mile")) {
    return { workoutKind: "intervals", structure: `${label("5K")}` };
  }

  // Intervals (10K): short reps + rest at 10K pace.
  if (shortReps && hasRest && dominant === "10k") {
    return { workoutKind: "intervals", structure: `${label("10K")}` };
  }

  // Threshold reps: reps at threshold (HMP) pace with recovery.
  if (dominant === "hmp" && hasRest) {
    return { workoutKind: "threshold", structure: label("threshold") };
  }

  // Longer 10K-pace reps that fell through (mile+ at 10K, looser CV) → threshold.
  if (longReps && dominant === "10k") {
    return { workoutKind: "threshold", structure: label("threshold") };
  }

  // Tempo: one sustained block at MP–HMP, no rest.
  if (reps.length <= 2 && !hasRest && (dominant === "mp" || dominant === "hmp" || dominant === "steady")) {
    return { workoutKind: "tempo", structure: label("tempo") };
  }

  // Fallbacks by dominant zone so nothing quality reads as easy.
  if (dominant === "hmp" || dominant === "mp") {
    return { workoutKind: "threshold", structure: label("threshold") };
  }
  return { workoutKind: "intervals", structure: label(zoneLabel(dominant)) };
}

function detectContinuousRace(
  bouts: Bout[],
  totalMeters: number,
): { workoutKind: WorkoutKind; structure: string | null } | null {
  const totalMiles = totalMeters / METERS_PER_MILE;
  if (totalMiles < 3) return null;
  const workSeconds = bouts.filter((b) => b.isWork).reduce((s, b) => s + b.seconds, 0);
  const totalSeconds = bouts.reduce((s, b) => s + b.seconds, 0);
  const restCount = bouts.filter((b) => b.isRest).length;
  if (totalSeconds <= 0) return null;
  // ≥85% of the time at work pace and essentially no recovery = a race effort.
  if (workSeconds / totalSeconds >= 0.85 && restCount === 0) {
    const dz = dominantZone(bouts.filter((b) => b.isWork));
    if (dz === "5k" || dz === "10k" || dz === "hmp" || dz === "mp") {
      return { workoutKind: "race", structure: `${round1(totalMiles)} mi @ ${zoneLabel(dz)}` };
    }
  }
  return null;
}

// ── Structure string ──

function structureString(reps: Bout[], kindLabel: string): string | null {
  if (reps.length === 0) return null;
  const avgPace = fmtPace(mean(reps.map((r) => r.paceSecPerMile)));
  const distLabels = reps.map((r) => repDistanceLabel(r.distanceMeters));
  const uniform = distLabels.every((d) => d === distLabels[0]);
  if (uniform) {
    return `${reps.length}×${distLabels[0]} @ ${avgPace} (${kindLabel})`;
  }
  // Ladder / mixed: list the rep distances.
  return `${distLabels.join("-")} @ ${avgPace} (${kindLabel})`;
}

function repDistanceLabel(meters: number): string {
  if (meters <= 0) return "?";
  const miles = meters / METERS_PER_MILE;
  // Near a whole-mile multiple?
  const nearMile = Math.round(miles);
  if (nearMile >= 1 && Math.abs(miles - nearMile) / nearMile < 0.08) {
    return `${nearMile}mi`;
  }
  // Near a round metric rep distance?
  for (const m of [400, 600, 800, 1000, 1200, 1600, 2000, 3000, 5000]) {
    if (Math.abs(meters - m) / m < 0.08) {
      return m % 1000 === 0 ? `${m / 1000}K` : `${m}m`;
    }
  }
  // Otherwise round to nearest 100m.
  return `${Math.round(meters / 100) * 100}m`;
}

function zoneLabel(z: Zone): string {
  switch (z) {
    case "hmp": return "threshold";
    case "10k": return "10K";
    case "5k": return "5K";
    case "3k": return "3K";
    case "mp": return "MP";
    case "mile": return "mile";
    default: return z;
  }
}

// ── Small numeric helpers ──

function dominantZone(bouts: Bout[]): Zone {
  if (bouts.length === 0) return "easy";
  const secByZone = new Map<Zone, number>();
  for (const b of bouts) secByZone.set(b.zone, (secByZone.get(b.zone) ?? 0) + b.seconds);
  let best: Zone = "easy", bestSec = -1;
  for (const [z, s] of secByZone) if (s > bestSec) { best = z; bestSec = s; }
  return best;
}

function isMonotonicFaster(reps: Bout[]): boolean {
  // Each rep at least ~1.5% faster than the previous, overall ≥6% drop.
  let strictlyFaster = 0;
  for (let i = 1; i < reps.length; i++) {
    if (reps[i].paceSecPerMile < reps[i - 1].paceSecPerMile * 0.995) strictlyFaster++;
  }
  const overall = (reps[0].paceSecPerMile - reps[reps.length - 1].paceSecPerMile) /
    reps[0].paceSecPerMile;
  return strictlyFaster >= reps.length - 1 && overall >= 0.06;
}

function mean(xs: number[]): number {
  const v = xs.filter((x) => isFinite(x));
  return v.length ? v.reduce((s, x) => s + x, 0) / v.length : 0;
}

function cv(xs: number[]): number | null {
  const v = xs.filter((x) => isFinite(x) && x > 0);
  if (v.length < 2) return null;
  const m = mean(v);
  if (m <= 0) return null;
  const variance = v.reduce((s, x) => s + (x - m) ** 2, 0) / v.length;
  return Math.sqrt(variance) / m;
}

function parsePace(pace: string | null | undefined): number {
  if (!pace) return 0;
  const parts = String(pace).split(":");
  if (parts.length !== 2) return 0;
  const m = parseInt(parts[0], 10), s = parseInt(parts[1], 10);
  return isFinite(m) && isFinite(s) ? m * 60 + s : 0;
}

export function fmtPace(sec: number): string | null {
  if (!isFinite(sec) || sec <= 0) return null;
  const t = Math.round(sec);
  return `${Math.floor(t / 60)}:${String(t % 60).padStart(2, "0")}`;
}

const round1 = (x: number): number => Math.round(x * 10) / 10;
const round2 = (x: number): number => Math.round(x * 100) / 100;

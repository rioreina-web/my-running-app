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

// ── Canonical intensity weights (1–8 scale, decision 2026-06-12) ──
// ONE scale used everywhere — the load math, athlete_state.volume_x_intensity,
// and the training-load chart all read these numbers. Recovery folds into
// easy (1.0). A minute at mile pace ≈ 8 easy minutes of mechanical load.
//
// (2026-08-11) `steady` 1.5 → 2.15 and `moderate` 1.25 → 1.40. `paceWeight`
// interpolates LINEARLY ON PACE between knots, so a knot's weight sets the
// SLOPE of the two segments it joins — not just its own value. steady sits at
// 95% MP speed, i.e. only ~18 sec/mi off MP, so a weight of 1.5 crammed a full
// unit of climb into that gap: the steady→mp slope was 0.0562 weight per sec/mi
// against 0.0060 for moderate→steady, a 9× discontinuity. Ten sec/mi near MP
// moved the weight more than the entire easy→steady range. Now the low end runs
// 0.0132 → 0.0179 → 0.0197 into MP: monotone, convex, no cliff. Measured on 126h
// of this athlete's laps the change is +3.4% total weighted load, because almost
// nothing currently sits in the steady–MP corridor (0.8% of lap time) — which is
// exactly why it was cheap to fix now and expensive after a marathon block.
export const ZONE_WEIGHTS: Record<Zone, number> = {
  recovery: 1.0,
  easy: 1.0,
  moderate: 1.4,
  steady: 2.15,
  mp: 2.5, // marathon pace
  hmp: 3.25, // half-marathon / threshold / LT band
  "10k": 4.0,
  "5k": 5.5, // (2026-07-30) steep top end — true speed rewarded heavily
  "3k": 6.75, // between 5k and mile; not user-specified, sits on the line
  mile: 8.0, // VO2max+ / neuromuscular — top anchor; faster extrapolates > 8
};

// Continuous intensity curve, anchored at these zones' athlete paces. `recovery`
// is the only non-knot — anything slower than easy floors to 1.0. Every zone
// from easy through mile is a knot, and a bout between two knots is weighted by
// a monotone cubic through its actual pace (reps faster than mile extrapolate).
const WEIGHT_KNOT_ZONES: ReadonlySet<Zone> = new Set<Zone>([
  "easy", "moderate", "steady", "mp", "hmp", "10k", "5k", "3k", "mile",
]);

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
export const WORK_ZONES: ReadonlySet<Zone> = new Set<Zone>(["mile", "3k", "5k", "10k", "hmp", "mp"]);
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

// Auto-lap coalescing: watches set to auto-lap (every mile/km) fragment ONE
// continuous effort into N same-pace laps — a 2×3mi cruise records as 6×1mi.
// We merge a run of CONSECUTIVE work bouts (nothing non-work between them) into
// a single rep when the run is uniform (tight pace CV) and not a deliberate
// progression. Reps separated by a rest/easy bout are never merged, so true
// intervals (jog recoveries are real separators) and progressions/fartleks
// (varying pace) are untouched. See workoutSegmentation.test.ts (2×3mi case).
const MERGE_PACE_CV = 0.03;

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

/**
 * Fritsch–Carlson tangents for a monotone cubic (PCHIP) through `knots`,
 * ascending by pace. Returns one tangent per knot, in the same order.
 *
 * The Fritsch–Carlson rule is what makes this SHAPE-PRESERVING: where the data
 * changes direction it sets the tangent to 0, and the harmonic-mean form
 * otherwise keeps every tangent inside the range that guarantees no overshoot.
 * That matters here — a plain cubic spline would bulge on the sharp 10K→5K
 * transition and could make a slightly-slower pace score HIGHER, which the
 * whole model must never do.
 */
function pchipTangents(knots: ReadonlyArray<{ pace: number; w: number }>): number[] {
  const n = knots.length;
  const h: number[] = [], d: number[] = [], m: number[] = new Array(n);
  for (let i = 0; i < n - 1; i++) {
    h[i] = knots[i + 1].pace - knots[i].pace;
    d[i] = (knots[i + 1].w - knots[i].w) / h[i];
  }
  m[0] = d[0];
  m[n - 1] = d[n - 2];
  for (let i = 1; i < n - 1; i++) {
    if (d[i - 1] * d[i] <= 0) {
      m[i] = 0; // local extremum — flatten so the curve cannot overshoot
    } else {
      const w1 = 2 * h[i] + h[i - 1];
      const w2 = h[i] + 2 * h[i - 1];
      m[i] = (w1 + w2) / (w1 / d[i - 1] + w2 / d[i]); // weighted harmonic mean
    }
  }
  return m;
}

/**
 * Continuous intensity weight for an actual pace — the "easy → mile trajectory"
 * as one curve rather than a step-table. We take the athlete's zone anchors as
 * (pace, weight) knots (moderate…mile, from `ZONE_WEIGHTS`) and:
 *   • interpolate with a MONOTONE CUBIC between the two bracketing knots, so a
 *     bout between zones (a progression, a cruise between steady and MP) gets a
 *     weight that reflects exactly where it fell;
 *   • extrapolate ABOVE the mile knot for reps faster than mile pace, using the
 *     curve's tangent at that knot — so a 300m at true mile-crushing pace can
 *     score past 8.0, on the same continuous scale;
 *   • floor at the easy weight (1.0) for anything slower than easy (jogs, float
 *     recoveries, warmups).
 *
 * (2026-08-13) Straight-line interpolation → monotone cubic. Linear segments
 * are continuous in VALUE but not in SLOPE: the rate of change jumped at every
 * knot, worst of all crossing MP (0.567 → 0.205 per 10 sec/mi, a 64% break) and
 * moderate (58%). That made the weight's sensitivity to pace depend on which
 * side of an anchor a bout landed, which is exactly the artefact the 2026-08-11
 * steady reweight was fighting. A monotone cubic removes every corner while
 * passing through ALL the same anchors — so no weight is recalibrated, scores
 * at anchor paces are bit-identical, and the largest change anywhere between
 * anchors is under 2%. Fritsch–Carlson is chosen over a natural spline because
 * it is guaranteed not to overshoot (see `pchipTangents`).
 *
 * `paceToZone` still owns the discrete LABEL + time-in-zone buckets; this owns
 * the intensity number. Returns 1.0 when anchors are unavailable — never lie.
 */
export function paceWeight(paceSecPerMile: number, anchors: ZoneAnchor[]): number {
  if (!isFinite(paceSecPerMile) || paceSecPerMile <= 0) return 1.0;
  // Knots ascending by pace → index 0 is fastest (mile, top weight), last is
  // easy (weight 1.0).
  const knots = anchors
    .filter((a) => WEIGHT_KNOT_ZONES.has(a.zone))
    .map((a) => ({ pace: a.pace, w: ZONE_WEIGHTS[a.zone] }))
    .sort((x, y) => x.pace - y.pace);
  if (knots.length === 0) return 1.0;
  if (knots.length === 1) return knots[0].w;

  const fastest = knots[0];
  const slowest = knots[knots.length - 1];
  if (paceSecPerMile >= slowest.pace) return slowest.w; // slower than easy → floor

  const m = pchipTangents(knots);

  if (paceSecPerMile <= fastest.pace) {
    // Faster than mile — extrapolate along the curve's tangent at the mile knot
    // (never below the mile weight, so a small timing wobble can't dip a mile
    // rep). With two knots this is identical to the old top-segment slope.
    return Math.max(fastest.w, fastest.w + m[0] * (paceSecPerMile - fastest.pace));
  }
  for (let i = 0; i < knots.length - 1; i++) {
    const a = knots[i], b = knots[i + 1];
    if (paceSecPerMile >= a.pace && paceSecPerMile <= b.pace) {
      const h = b.pace - a.pace;
      const t = (paceSecPerMile - a.pace) / h;
      const t2 = t * t, t3 = t2 * t;
      // Cubic Hermite basis.
      return (2 * t3 - 3 * t2 + 1) * a.w
        + (t3 - 2 * t2 + t) * h * m[i]
        + (-2 * t3 + 3 * t2) * b.w
        + (t3 - t2) * h * m[i + 1];
    }
  }
  return slowest.w;
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
  /** Pace corrected for heat + dew point by `fetch-workout-weather`. Null on
   *  laps predating that decoration, and on days with no weather on file. Only
   *  read when `segmentFromLaps` is asked for it — see its `opts`. */
  heat_adjusted_pace_sec_per_mile?: number | null;
}

/** Options for `segmentFromLaps`. */
export interface SegmentOptions {
  /**
   * Classify each lap by its HEAT-ADJUSTED pace instead of its raw pace.
   *
   * 6:20/mi at 78°F with a 75°F dew point is not the same effort as 6:20/mi in
   * the cold — it is threshold work wearing an easy pace. Classifying on raw
   * pace books that lap as easy and the day's training load comes out low
   * exactly when the athlete is working hardest, which is the opposite of what
   * a stress score is for.
   *
   * Only CLASSIFICATION moves. `Bout.paceSecPerMile` stays the raw pace the
   * watch recorded, so every pace this app displays is still the pace that was
   * actually run — the adjustment decides which bucket a lap lands in, never
   * what number the athlete is shown. Same split Pace Bands already makes.
   *
   * Falls back to raw pace per-lap when no adjusted pace is on file, so a
   * partially-decorated workout degrades lap by lap rather than all at once.
   */
  useHeatAdjustedPace?: boolean;
}

export interface Bout {
  zone: Zone;
  seconds: number;
  distanceMeters: number;
  paceSecPerMile: number;
  /**
   * Neutral-day equivalent pace (sec/mi) — what this bout would have cost in
   * neutral air — or null when no adjustment is on file.
   *
   * Carried SEPARATELY from `paceSecPerMile` and populated regardless of
   * `SegmentOptions.useHeatAdjustedPace`, because the flag answers a different
   * question. The flag decides which ZONE a lap lands in; this field lets a
   * consumer that is measuring physiological cost (efficiency factor: speed
   * per heartbeat) divide by a pace the weather hasn't moved. An August
   * threshold rep in Texas is 13–20 s/mi slower for the same effort, and an
   * EF computed on raw pace books that as lost fitness.
   *
   * `paceSecPerMile` remains the pace the watch recorded and is still what
   * every display path reads — this field is never shown as "your pace".
   */
  neutralPaceSecPerMile: number | null;
  avgHr: number | null;
  isWork: boolean; // pace faster than steady
  isRest: boolean; // flagged or detected recovery between efforts
  isRep: boolean; // a work bout that passes the rep guards (counts in structure)
  /**
   * This bout's intensity multiplier from the CONTINUOUS `paceWeight` curve,
   * evaluated on the same pace the zone was decided by.
   *
   * Not the same number as `ZONE_WEIGHTS[zone]`, and that is the point. The
   * discrete table is ten steps; the curve is what the table's anchors
   * describe, and it keeps climbing past mile — a 200 at 4:20/mi is harder per
   * second than a mile rep at 4:50 and now scores like it, where bucketing them
   * both into `mile` capped them at 8.0. Between anchors it also stops a lap
   * one second the slow side of a boundary from losing a whole step.
   */
  weight: number;
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
export function segmentFromLaps(
  laps: LapInput[],
  zones: PaceZones,
  opts: SegmentOptions = {},
): SegmentationResult {
  const anchors = buildZoneAnchors(zones);
  const bouts: Bout[] = [];

  for (const lap of laps) {
    const seconds = secondsOf(lap);
    const distanceMeters = Number(lap.distance_meters ?? 0);
    const paceSecPerMile = Number(lap.avg_pace_sec_per_mile ?? 0);
    if (seconds <= 0) continue;

    // The pace the ZONE is decided by. Deliberately separate from
    // `paceSecPerMile`, which is what gets reported — see `SegmentOptions`.
    const adjusted = Number(lap.heat_adjusted_pace_sec_per_mile ?? 0);
    const classifyPace = opts.useHeatAdjustedPace && adjusted > 0
      ? adjusted
      : paceSecPerMile;

    const flaggedRest = lap.is_rest === true;
    const zone = paceToZone(classifyPace, anchors);
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
      // Populated whether or not the caller asked to CLASSIFY on it — see the
      // field doc. `adjusted` is fetch-workout-weather's neutralEquivalent-
      // PaceSeconds, already the faster (credited) pace.
      neutralPaceSecPerMile: adjusted > 0 ? adjusted : null,
      // Rest is scored at the floor regardless of how quick the float was: a
      // recovery jog is recovery, and letting a brisk one earn 1.4 would make
      // the athlete's rest count against them.
      weight: isRest ? 1.0 : paceWeight(classifyPace, anchors),
      avgHr: lap.avg_heart_rate != null && Number(lap.avg_heart_rate) > 0
        ? Number(lap.avg_heart_rate)
        : null,
      isWork,
      isRest,
      isRep,
    });
  }

  return finalize(bouts, "laps", anchors);
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
    const isRest = !isWork && zone === "recovery";
    bouts.push({
      zone,
      seconds,
      distanceMeters,
      paceSecPerMile,
      // pace_segments carry no weather stamp — only laps are decorated by
      // fetch-workout-weather. Null rather than a guess.
      neutralPaceSecPerMile: null,
      // Same rule as the lap path: rest floors at 1.0, everything else takes
      // the continuous curve.
      weight: isRest ? 1.0 : paceWeight(paceSecPerMile, anchors),
      avgHr: seg.avg_heart_rate != null && Number(seg.avg_heart_rate) > 0
        ? Number(seg.avg_heart_rate)
        : null,
      isWork,
      isRest,
      isRep: isWork && seconds >= MIN_REP_SECONDS && distanceMeters >= MIN_REP_METERS,
    });
  }
  return finalize(bouts, "segments", anchors);
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
      // Whole-workout fallback: no per-lap weather to normalize against.
      neutralPaceSecPerMile: null,
      // 1.0 by construction, not by lookup: this path has no anchors to build
      // a curve from, and the block is declared `easy`, whose weight is 1.0.
      // `paceWeight` would return 1.0 here anyway — it floors when anchors are
      // absent rather than guessing.
      weight: 1.0,
      avgHr: null,
      isWork: false,
      isRest: false,
      isRep: false,
    });
  }
  return finalize(bouts, "overall");
}

// ── Core aggregation + classification ──

function finalize(
  bouts: Bout[],
  source: SegmentationResult["source"],
  anchors: ZoneAnchor[] = [],
): SegmentationResult {
  let easySeconds = 0, moderateSeconds = 0, thresholdSeconds = 0, hardSeconds = 0;
  let weightedSum = 0, totalSeconds = 0, totalMeters = 0;

  for (const b of bouts) {
    totalSeconds += b.seconds;
    totalMeters += b.distanceMeters;
    // Weight by ACTUAL pace on the continuous easy→mile curve (extrapolates
    // past mile). Falls back to the zone's knot weight when anchors are absent
    // (the overall-only path, where every bout is "easy" anyway).
    weightedSum += b.seconds * (anchors.length > 0
      ? paceWeight(b.paceSecPerMile, anchors)
      : ZONE_WEIGHTS[b.zone]);
    if (HARD_ZONES.has(b.zone)) hardSeconds += b.seconds;
    else if (THRESHOLD_ZONES.has(b.zone)) thresholdSeconds += b.seconds;
    else if (b.zone === "mp" || b.zone === "steady" || b.zone === "moderate") {
      moderateSeconds += b.seconds;
    } else easySeconds += b.seconds;
  }

  // Coalesce auto-lap-fragmented continuous efforts into true reps. Zone-time
  // buckets above stay per-lap (time-in-zone is unaffected by rep grouping).
  const reps = coalesceReps(bouts, anchors);
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
 * Coalesce auto-lap fragmentation: merge runs of CONSECUTIVE work bouts (no
 * non-work bout between them) into single reps. A run merges only when it's
 * uniform (tight pace CV) and not a deliberate progression — so a 2×3mi cruise
 * recorded as 6×1mi collapses to two reps, while a continuous progression keeps
 * its per-lap reps (for `isMonotonicFaster` detection) and a fartlek's varied
 * surges stay separate. Reps separated by rest/easy bouts are never touched, so
 * true intervals are unaffected. Returns reps in order, rep-guards applied.
 */
export function coalesceReps(bouts: Bout[], anchors: ZoneAnchor[]): Bout[] {
  const reps: Bout[] = [];
  let run: Bout[] = [];

  const flush = () => {
    if (run.length === 0) return;
    if (run.length === 1) {
      if (run[0].isRep) reps.push(run[0]);
    } else {
      const paces = run.map((b) => b.paceSecPerMile).filter((p) => p > 0);
      const uniform = (cv(paces) ?? 1) < MERGE_PACE_CV;
      if (uniform && !isMonotonicFaster(run)) {
        const merged = mergeRun(run, anchors);
        if (merged.isRep) reps.push(merged);
      } else {
        // Progression / fartlek / varied — keep the individual reps.
        for (const b of run) if (b.isRep) reps.push(b);
      }
    }
    run = [];
  };

  for (const b of bouts) {
    if (b.isWork) run.push(b);
    else flush();
  }
  flush();
  return reps;
}

/** Merge a run of consecutive work bouts into one rep (distance-weighted pace,
 *  time-weighted HR, zone re-derived from the merged pace). */
function mergeRun(run: Bout[], anchors: ZoneAnchor[]): Bout {
  const seconds = run.reduce((s, b) => s + b.seconds, 0);
  const distanceMeters = run.reduce((s, b) => s + b.distanceMeters, 0);
  const paceSecPerMile = distanceMeters > 0
    ? seconds / (distanceMeters / METERS_PER_MILE)
    : mean(run.map((b) => b.paceSecPerMile));
  let hrW = 0, hrSec = 0;
  for (const b of run) {
    if (b.avgHr != null && b.avgHr > 0) { hrW += b.avgHr * b.seconds; hrSec += b.seconds; }
  }
  // Neutral pace merges the same way the raw pace does — distance-weighted,
  // i.e. summing each piece's neutral TIME and dividing by total distance.
  // A piece with no adjustment on file contributes its raw pace, so a
  // partially-decorated rep degrades piece by piece rather than all at once
  // (the same per-lap fallback `SegmentOptions` documents). Null only when no
  // piece carried an adjustment at all — never a silent raw-pace substitute.
  let neutralSecondsAcc = 0;
  let anyNeutral = false;
  for (const b of run) {
    const miles = b.distanceMeters / METERS_PER_MILE;
    if (b.neutralPaceSecPerMile != null && b.neutralPaceSecPerMile > 0) anyNeutral = true;
    neutralSecondsAcc += (b.neutralPaceSecPerMile ?? b.paceSecPerMile) * miles;
  }
  const totalMiles = distanceMeters / METERS_PER_MILE;
  const zone = anchors.length > 0 ? paceToZone(paceSecPerMile, anchors) : run[0].zone;
  return {
    zone,
    seconds,
    distanceMeters,
    paceSecPerMile,
    neutralPaceSecPerMile: anyNeutral && totalMiles > 0
      ? neutralSecondsAcc / totalMiles
      : null,
    // Recomputed from the COALESCED pace, not averaged from the pieces. The
    // merged rep is one effort and its weight should describe the pace it was
    // actually run at — which is the whole argument for a continuous curve.
    // Falls back to the discrete anchor when there are no zone anchors, which
    // is the same fallback `finalize` uses.
    weight: anchors.length > 0
      ? paceWeight(paceSecPerMile, anchors)
      : ZONE_WEIGHTS[zone],
    avgHr: hrSec > 0 ? hrW / hrSec : null,
    isWork: true,
    isRest: false,
    isRep: seconds >= MIN_REP_SECONDS && distanceMeters >= MIN_REP_METERS,
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

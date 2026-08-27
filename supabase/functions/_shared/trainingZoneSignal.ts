// ============================================================================
// trainingZoneSignal.ts — what a training session says about race fitness.
//
// WHY THIS EXISTS. The predictor used to convert training work into a 10K
// equivalent with Riegel:
//
//     tenKEquiv = repPace × (10K miles / repDistance) ^ 0.06
//
// Riegel is a MAXIMAL-EFFORT curve: it answers "you raced D1 all-out, what
// would you race at D2?". Applied to a 1K rep it asserts the rep was a 1K
// time trial, and inflates by 14.7% at 0.63 mi. A session of 10×1K at 5:18
// came out as a 35:45 10K for an athlete who races ~31:50.
//
// A rep is not a race. Reps are run AT a pace — mile pace, 10K pace, LT — and
// the pace is prescribed, not exhausted. Only a declared race or time trial is
// a near-maximal effort at its distance, and that path already exists
// (`detectRaces` → `normalizeRaceTime`). This module is the other half: what
// ordinary training says.
//
// THE MODEL. One question, asked of the athlete's own curve:
//
//     For the amount of continuous work you actually did, how did your pace
//     compare to what your current fitness predicts for that duration?
//
//   1. Take the work reps the parser already isolated (`parsed_structure.
//      blocks`, role `work_rep`). No distance extrapolation — the parser
//      hands us the pace and the geometry.
//   2. Normalize each rep to neutral air (heat) and flat ground (grade).
//   3. Collapse the session to an EFFECTIVE CONTINUOUS DURATION: total work
//      seconds, discounted by how much rest carried it. 10×1K off 60s jog is
//      close to a continuous effort; 2×1mi off a 29-minute standing break is
//      not.
//   4. Ask the athlete's own pace/duration curve what pace that effective
//      duration is worth at the CURRENT estimate.
//   5. The ratio between what they ran and what was predicted scales the 10K.
//
// Nothing here asserts a rep is maximal. If the athlete runs exactly what the
// curve predicts for that duration, the ratio is 1.0 and the session confirms
// the estimate rather than moving it. Faster means fitter, slower means less
// fit, in proportion — and the proportion is measured against THEIR curve, not
// a table of assumed rep-to-race conversions.
//
// IS IT CIRCULAR to price a session against a curve built from the estimate the
// session is about to move? Very nearly not, and the algebra says why. The
// curve scales linearly with its anchor, so for a fixed duration
// `predictedPaceForDuration ∝ currentTenKPace`, and
//
//     tenKEquivalent = currentTenKPace × (neutralWorkPace / predictedPace)
//                    = neutralWorkPace / shape(effectiveSeconds)
//
// — the anchor cancels. What survives is second-order: a fitter athlete covers
// a race in less time, so the same effective duration lands at a slightly
// different point on the curve. Measured on the calibration athlete's real
// 60-day history, seeding the anchor anywhere from 28:30 to 38:30 converges to
// 31:56 within four iterations. The number is a property of the training, not
// an echo of what we already believed.
//
// The anchor does one thing that does NOT cancel: it sets the plausibility
// window below. That is a coverage decision (which sessions are quality work),
// never a value decision.
//
// WHAT IS DELIBERATELY NOT HERE. HR, decoupling, recovery state and terrain
// all belong in this judgment and none of them is folded into the pace math
// yet. `meanHr` and `hrDrift` are computed and carried on every estimate so
// the next stage can weight by them; today they are reported, not applied.
// Saying so in the output is the point — see `ZoneEstimate.caveats`.
//
// Pure functions, no I/O. Tests: trainingZoneSignal.test.ts.
// ============================================================================

import {
  equivalentRacePaceSecPerMile,
  oneHourPaceSecPerMile,
  RACE_DISTANCE_MI,
  type RaceKey,
} from "./paces.ts";
import { heatNeutralPace } from "./pace-heat-adjustment.ts";
import { adjustPaceForGrade } from "./pace-grade-adjustment.ts";

// ---------------------------------------------------------------------------
// Tunables. Three numbers, each with a stated job.
// ---------------------------------------------------------------------------

/**
 * How much rest shrinks the effective continuous duration.
 *
 *     effectiveSeconds = workSeconds / (1 + REST_DISCOUNT × restRatio)
 *
 * At 0.5, a session run off equal work and rest (ratio 1.0) counts as two
 * thirds of its work time — you could not have held that pace continuously for
 * the full duration, but the rest bought you less than it cost. 10×1K off 60s
 * (ratio ≈ 0.33) keeps ~86% of its 33 minutes, landing near a 10K's worth of
 * work, which is what that session is.
 *
 * This is the one genuinely fitted number in the file and it is a coaching
 * judgment, not a measurement. It is a single knob rather than a rep-length
 * penalty on purpose: rep length is already carried by the work total, and
 * penalizing short reps twice is what made 10×1K read as a 35-minute 10K.
 */
export const REST_DISCOUNT = 0.5;

/**
 * Below this much work, a session says nothing about race fitness — a single
 * hard mile is a data point about a mile, not about an hour. Eight minutes is
 * roughly the shortest block that constrains the aerobic end at all.
 */
export const MIN_WORK_SECONDS = 480;

/**
 * The window a session's pace must fall in to be read at all. The two ends
 * mean DIFFERENT things and that asymmetry is the point.
 *
 * Too fast (< MIN): nobody beats their own curve by 14% in a workout. That is a
 * mis-parsed block, a downhill point-to-point, or a GPS lie.
 *
 * Too slow (> MAX): the session was not run at the limit. An easy run, a long
 * run, a steady aerobic block the parser typed as `interval`, or a genuine
 * workout deliberately held back. Not implausible — just not a statement about
 * race fitness, because the athlete was not trying to find their ceiling.
 * Dropping it is the whole defence against the failure mode that broke the
 * first version of this model: a real 12-mile alternation session on
 * 2026-08-01, run at 6:00/mi off short float, priced this athlete at a 35:38
 * 10K purely because nobody races 69 minutes in a workout.
 *
 * MAX is set at 10% because that is where this athlete's real sessions divide.
 * Measured against a correct anchor, genuine quality work sits within 7.6% of
 * the curve (1.3 / 4.0 / 4.5 / 7.6%); the submaximal aerobic sessions start at
 * 11.9% and run to 60%. The gap is wide and the line sits in it.
 *
 * Neither end is a clamp. Inside the window a session is carried at its full
 * measured worth; the old ±2% validation band squashed good evidence flat.
 */
export const PLAUSIBLE_RATIO_MIN = 0.86; // ~14% faster than predicted
export const PLAUSIBLE_RATIO_MAX = 1.10; // ~10% slower — below this is aerobic work

/**
 * Absolute rep-pace bounds. These catch GPS garbage and stopped clocks and
 * NOTHING else — whether a rep was quality for this athlete is decided
 * relative to their own curve by the plausibility window above.
 *
 * They were 210–540 s/mi, which is 3:30 to 9:00. A 58:00 10K runner races at
 * 9:20/mi, so every work rep they ever ran fell outside the window and the
 * training signal returned "no usable work reps" — silently, for a large share
 * of real runners. Caught by athleteProfiles.test.ts on its first run.
 *
 * 150 s/mi is faster than a world-record mile; 1200 is a 20-minute mile. If a
 * rep is outside that it is not a rep.
 */
const MIN_REP_PACE = 150;
const MAX_REP_PACE = 1200;

/** A rep shorter than this is a stride or a GPS artifact, not work. */
const MIN_REP_SECONDS = 45;

// ---------------------------------------------------------------------------
// Inputs — the shapes `parsed_structure` actually stores.
// ---------------------------------------------------------------------------

/** One entry of `parsed_structure.blocks`. */
export interface ParsedBlock {
  role: string; // "work_rep" | "recovery" | "warmup" | "cooldown"
  durationS?: number | null;
  distanceMiles?: number | null;
  avgPacePerMile?: string | null; // "5:19", or "—" when the block never moved
  avgHr?: number | null;
  /** Meters of climb inside the block, when the source laps carried it. */
  elevationGainM?: number | null;
}

/** A session as the parser left it, plus the conditions it was run in. */
export interface ParsedSession {
  date: string; // "yyyy-MM-dd"
  /** `parsed_structure.type` — interval | tempo | threshold | easy | race | … */
  type: string;
  /** `parsed_structure.confidence`, 0..1. */
  confidence: number;
  blocks: ParsedBlock[];
  /** `parsed_structure.intent_pattern`, e.g. "10x1K @ 3:15-3:23 pace w/ 60s". */
  intentPattern?: string | null;
  /** `training_logs.weather_actual`. */
  tempF?: number | null;
  dewPointF?: number | null;
  /** The athlete flagged this as a race or time trial — handled elsewhere. */
  declaredRace?: boolean;
}

/** The athlete's pace-at-duration curve, anchored on the current estimate. */
export interface FitnessCurvePoint {
  /** How long this effort takes at the current estimate, in seconds. */
  seconds: number;
  /** The pace it is run at, sec/mile. */
  paceSecPerMile: number;
  label: string;
}

// ---------------------------------------------------------------------------
// Output.
// ---------------------------------------------------------------------------

export interface ZoneEstimate {
  date: string;
  /** Distance-weighted neutral pace of the work reps (sec/mile). */
  neutralWorkPace: number;
  /** What the curve says that effective duration is worth right now. */
  predictedPaceForDuration: number;
  /** neutralWorkPace ÷ predictedPaceForDuration. <1 is faster than predicted. */
  ratio: number;
  /**
   * What this session implies the pace AT `distanceKey` should be (sec/mile).
   * Renamed from `tenKEquivalent` (2026-08-27) — it was never really a 10K
   * statement, it was a statement at whatever distance the caller's current
   * estimate happened to be seeded from. Naming it "10K" when it usually
   * carried a marathon-anchored athlete's marathon-relative evidence is
   * exactly the kind of silent coupling that made the model harder to reason
   * about than the math actually required.
   */
  equivalentPace: number;
  /** Which distance `equivalentPace` (and the curve it was priced against) is at. */
  distanceKey: RaceKey;
  /** Nearest named zone to `predictedPaceForDuration` — for prose only. */
  zoneLabel: string;
  workSeconds: number;
  workMiles: number;
  restSeconds: number;
  restRatio: number;
  effectiveSeconds: number;
  repCount: number;
  /** Mean HR across work reps, when the blocks carried it. Reported, not applied. */
  meanHr: number | null;
  /** Last-third mean HR minus first-third, bpm. Reported, not applied. */
  hrDrift: number | null;
  /** Whether the reps were heat-normalized (false when no weather on the row). */
  heatNormalized: boolean;
  /** Parser confidence, carried through. */
  confidence: number;
  /**
   * The normalized work reps themselves. Carried so downstream consumers that
   * need rep-level detail — the mile prediction's speed-evidence test, the
   * supporting-training note — do not have to re-derive it.
   */
  reps: Array<{ paceSeconds: number; distanceMiles: number; seconds: number; hr: number | null }>;
  /** Plain-language account of what was used and what was not. */
  why: string;
  caveats: string[];
}

export interface ZoneSignalResult {
  estimates: ZoneEstimate[];
  /** Sessions read but not used, with the reason. */
  rejected: Array<{ date: string; reason: string }>;
}

// ---------------------------------------------------------------------------
// The athlete's pace-at-duration curve.
// ---------------------------------------------------------------------------

/**
 * Build the pace/duration curve implied by a 10K pace, using the same
 * race-equivalence table the rest of the app runs on (`paces.ts`).
 *
 * The curve is the SHAPE; the anchor supplies the LEVEL. That separation is
 * what makes this non-circular: we are not asking "is the estimate right?" but
 * "given this shape, does the session sit above or below the current level?".
 *
 * Threshold is included at exactly 3600s because that is its definition here —
 * one-hour race pace — and it fills the otherwise wide gap between 10K and
 * half.
 */
export function buildFitnessCurve(
  seedPaceSecPerMile: number,
  seedDistanceKey: RaceKey = "tenK",
  curveTilt = 0,
): FitnessCurvePoint[] {
  // ── Distance-native seed (2026-08-27) ────────────────────────────────────
  // Was hardcoded to a 10K seed, always — this curve is what prices EVERY
  // training session, so a marathoner whose evidence is a marathon still had
  // that evidence forced through a 10K conversion before it could price a
  // single rep. Generalizing the seed doesn't change existing behavior:
  // callers that keep passing (pace, "tenK", 0) get the exact prior curve.
  //
  // `curveTilt` mirrors fitnessPrediction.ts's raceTime() — the generic table
  // gives the shape, the athlete's OWN fitted exponent (`raceCurve.ts`,
  // shrunk toward generic by evidence) nudges it. Passed as a plain number so
  // this module stays free of raceCurve.ts's types; the caller computes it.
  const seedTime = seedPaceSecPerMile * RACE_DISTANCE_MI[seedDistanceKey];
  const paceAt = (key: RaceKey): number => {
    const table = equivalentRacePaceSecPerMile(seedDistanceKey, seedTime, key);
    if (curveTilt === 0 || key === seedDistanceKey) return table;
    return table * Math.pow(RACE_DISTANCE_MI[key] / RACE_DISTANCE_MI[seedDistanceKey], curveTilt);
  };

  const hm = paceAt("half");
  const points: FitnessCurvePoint[] = [
    { label: "mile", seconds: paceAt("mile") * RACE_DISTANCE_MI.mile, paceSecPerMile: paceAt("mile") },
    { label: "3K", seconds: paceAt("threeK") * RACE_DISTANCE_MI.threeK, paceSecPerMile: paceAt("threeK") },
    { label: "5K", seconds: paceAt("fiveK") * RACE_DISTANCE_MI.fiveK, paceSecPerMile: paceAt("fiveK") },
    { label: "10K", seconds: paceAt("tenK") * RACE_DISTANCE_MI.tenK, paceSecPerMile: paceAt("tenK") },
    { label: "LT", seconds: 3600, paceSecPerMile: oneHourPaceSecPerMile(paceAt("tenK"), hm) },
    { label: "HM", seconds: hm * RACE_DISTANCE_MI.half, paceSecPerMile: hm },
    { label: "MP", seconds: paceAt("marathon") * RACE_DISTANCE_MI.marathon, paceSecPerMile: paceAt("marathon") },
  ];
  // oneHourPaceSecPerMile collapses to 10K pace for athletes whose 10K already
  // takes over an hour, which would put LT at the same pace but a later time.
  // Sort and de-duplicate so interpolation stays monotonic either way.
  points.sort((a, b) => a.seconds - b.seconds);
  return points.filter((p, i) => i === 0 || p.seconds > points[i - 1].seconds + 1);
}

/**
 * What pace is `seconds` of continuous work worth on this curve?
 *
 * Log-interpolated in duration, because the pace/duration relationship is
 * roughly linear in log-time (that is the whole basis of the Riegel family) —
 * linear interpolation in raw seconds would badly misprice the short end where
 * the points are close together.
 *
 * Outside the curve the endpoints are held rather than extrapolated. A 90-second
 * rep is priced at mile pace and a three-hour effort at MP; both are honest
 * refusals to invent a curve we do not have.
 */
export function predictedPaceForDuration(
  curve: readonly FitnessCurvePoint[],
  seconds: number,
): { pace: number; label: string } {
  if (curve.length === 0 || !(seconds > 0)) return { pace: 0, label: "" };
  if (seconds <= curve[0].seconds) return { pace: curve[0].paceSecPerMile, label: curve[0].label };
  const last = curve[curve.length - 1];
  if (seconds >= last.seconds) return { pace: last.paceSecPerMile, label: last.label };

  for (let i = 1; i < curve.length; i++) {
    const hi = curve[i];
    if (seconds > hi.seconds) continue;
    const lo = curve[i - 1];
    const f = (Math.log(seconds) - Math.log(lo.seconds)) / (Math.log(hi.seconds) - Math.log(lo.seconds));
    const pace = lo.paceSecPerMile + f * (hi.paceSecPerMile - lo.paceSecPerMile);
    // Name it for the nearer endpoint — prose only, never used in the math.
    return { pace, label: f < 0.5 ? lo.label : hi.label };
  }
  return { pace: last.paceSecPerMile, label: last.label };
}

// ---------------------------------------------------------------------------
// Reading a session.
// ---------------------------------------------------------------------------

/**
 * Seconds → "M:SS". Rounds the TOTAL before splitting — rounding the remainder
 * independently is what produces "4:60" for 299.9, the same boundary bug
 * athlete-state.ts:formatPace was fixed for.
 */
export function formatMSS(seconds: number): string {
  const t = Math.round(seconds);
  return `${Math.floor(t / 60)}:${String(t % 60).padStart(2, "0")}`;
}

/** "5:19" → 319. Returns null for "—", "", and anything malformed. */
export function parsePaceMSS(raw: string | null | undefined): number | null {
  if (!raw) return null;
  const parts = raw.trim().split(":");
  if (parts.length !== 2) return null;
  const m = Number(parts[0]);
  const s = Number(parts[1]);
  if (!Number.isFinite(m) || !Number.isFinite(s)) return null;
  const total = m * 60 + s;
  return total > 0 ? total : null;
}

const WORK_ROLES = new Set(["work_rep", "work", "rep"]);
const REST_ROLES = new Set(["recovery", "rest", "float", "jog"]);

/** Session types that never carry a fitness statement, whatever the paces. */
const NON_QUALITY_TYPES = new Set([
  "easy", "recovery", "long_run", "rest", "cross_train", "strength", "walk", "warmup", "cooldown",
]);

interface NormalizedRep {
  pace: number; // neutral, grade-adjusted
  seconds: number;
  miles: number;
  hr: number | null;
}

/**
 * Work reps only, normalized to neutral air and flat ground.
 *
 * Heat correction is rep-length scaled inside `heatNeutralPace` — a 400 gets
 * half the credit a mile does, because a short rep spends less time paying the
 * thermal cost.
 */
function normalizedWorkReps(
  session: ParsedSession,
): { reps: NormalizedRep[]; heatNormalized: boolean } {
  const hasWeather = session.tempF != null && session.dewPointF != null;
  const reps: NormalizedRep[] = [];
  let anyHeatApplied = false;

  for (const b of session.blocks) {
    if (!WORK_ROLES.has(String(b.role ?? "").toLowerCase())) continue;
    const seconds = b.durationS ?? 0;
    const miles = b.distanceMiles ?? 0;
    if (!(seconds >= MIN_REP_SECONDS) || !(miles > 0.05)) continue;

    // Prefer the block's own pace; fall back to geometry when it is "—".
    let pace = parsePaceMSS(b.avgPacePerMile) ?? seconds / miles;
    if (!(pace >= MIN_REP_PACE && pace <= MAX_REP_PACE)) continue;

    if (hasWeather) {
      const neutral = heatNeutralPace(pace, session.tempF!, session.dewPointF!, miles);
      if (neutral < pace) anyHeatApplied = true;
      pace = neutral;
    }

    const gainM = b.elevationGainM ?? 0;
    if (gainM > 0 && miles > 0) {
      const gradePct = (gainM / (miles * 1609.344)) * 100;
      pace = adjustPaceForGrade(pace, gradePct).adjustedPaceSeconds;
    }

    reps.push({ pace, seconds, miles, hr: b.avgHr != null && b.avgHr > 0 ? b.avgHr : null });
  }
  return { reps, heatNormalized: anyHeatApplied };
}

/** Rest carried BETWEEN work reps — leading warm-up and trailing jog excluded. */
function restBetweenReps(blocks: readonly ParsedBlock[]): number {
  const workIdx: number[] = [];
  blocks.forEach((b, i) => {
    if (WORK_ROLES.has(String(b.role ?? "").toLowerCase())) workIdx.push(i);
  });
  if (workIdx.length < 2) return 0;
  const first = workIdx[0];
  const last = workIdx[workIdx.length - 1];
  let rest = 0;
  for (let i = first + 1; i < last; i++) {
    const role = String(blocks[i].role ?? "").toLowerCase();
    if (REST_ROLES.has(role)) rest += blocks[i].durationS ?? 0;
  }
  return rest;
}

/** Mean HR of the last third of reps minus the first third. */
function hrDriftAcrossReps(reps: readonly NormalizedRep[]): number | null {
  const withHr = reps.filter((r) => r.hr != null);
  if (withHr.length < 3) return null;
  const third = Math.max(1, Math.floor(withHr.length / 3));
  const head = withHr.slice(0, third);
  const tail = withHr.slice(-third);
  const avg = (xs: NormalizedRep[]) => xs.reduce((s, r) => s + (r.hr ?? 0), 0) / xs.length;
  return Math.round((avg(tail) - avg(head)) * 10) / 10;
}

/**
 * Turn one parsed session into a fitness statement, or explain why it is not one.
 *
 * `currentTenKPace` anchors the curve. Pass the estimate as it stands BEFORE
 * this signal is folded in — the ratio is meaningless against an anchor that
 * already contains it.
 */
export function estimateFromSession(
  session: ParsedSession,
  currentPace: number,
  currentDistanceKey: RaceKey = "tenK",
  curveTilt = 0,
): { estimate: ZoneEstimate | null; reason: string } {
  if (!(currentPace > 0)) return { estimate: null, reason: "no current estimate to compare against" };
  if (session.declaredRace) return { estimate: null, reason: "declared race — handled as an anchor, not training" };

  const type = String(session.type ?? "").toLowerCase();
  if (NON_QUALITY_TYPES.has(type)) return { estimate: null, reason: `type "${type}" carries no fitness statement` };
  if (!session.blocks || session.blocks.length === 0) return { estimate: null, reason: "no parsed blocks" };

  const { reps, heatNormalized } = normalizedWorkReps(session);
  if (reps.length === 0) return { estimate: null, reason: "no usable work reps" };

  const workSeconds = reps.reduce((s, r) => s + r.seconds, 0);
  const workMiles = reps.reduce((s, r) => s + r.miles, 0);
  if (workSeconds < MIN_WORK_SECONDS) {
    return {
      estimate: null,
      reason: `only ${Math.round(workSeconds / 60)} min of work (need ${MIN_WORK_SECONDS / 60})`,
    };
  }

  const restSeconds = restBetweenReps(session.blocks);
  const restRatio = workSeconds > 0 ? restSeconds / workSeconds : 0;
  const effectiveSeconds = workSeconds / (1 + REST_DISCOUNT * restRatio);

  // Distance-weighted: a mile rep is worth more than a 400 in the same session.
  const neutralWorkPace = reps.reduce((s, r) => s + r.pace * r.miles, 0) / workMiles;

  const curve = buildFitnessCurve(currentPace, currentDistanceKey, curveTilt);
  const predicted = predictedPaceForDuration(curve, effectiveSeconds);
  if (!(predicted.pace > 0)) return { estimate: null, reason: "could not price that duration" };

  const ratio = neutralWorkPace / predicted.pace;
  const offPct = Math.abs((ratio - 1) * 100).toFixed(1);
  if (ratio < PLAUSIBLE_RATIO_MIN) {
    return { estimate: null, reason: `${offPct}% faster than the curve allows — mis-parsed or bad GPS` };
  }
  if (ratio > PLAUSIBLE_RATIO_MAX) {
    return { estimate: null, reason: `${offPct}% slower than the curve — aerobic work, not a fitness statement` };
  }

  const hrs = reps.map((r) => r.hr).filter((h): h is number => h != null);
  const meanHr = hrs.length > 0 ? Math.round(hrs.reduce((s, h) => s + h, 0) / hrs.length) : null;

  const caveats: string[] = [];
  if (!heatNormalized) caveats.push("no weather on this row — pace not heat-normalized");
  if (meanHr === null) caveats.push("no HR on the work reps");
  else caveats.push("HR recorded but not yet folded into the pace math");
  if (session.confidence < 0.6) caveats.push(`parser confidence ${session.confidence.toFixed(2)}`);
  if (restSeconds === 0 && reps.length > 1) caveats.push("no rest blocks between reps — treated as continuous");

  const why = [
    `${reps.length} work rep${reps.length === 1 ? "" : "s"}`,
    `${workMiles.toFixed(2)} mi in ${Math.round(workSeconds / 60)} min`,
    restSeconds > 0 ? `${Math.round(restSeconds / 60)} min rest (ratio ${restRatio.toFixed(2)})` : "continuous",
    `effective ${Math.round(effectiveSeconds / 60)} min`,
    `ran ${formatMSS(neutralWorkPace)} neutral vs ${formatMSS(predicted.pace)} predicted at ${predicted.label}`,
    `${offPct}% ${ratio < 1 ? "faster" : "slower"}`,
  ].join(" · ");

  return {
    estimate: {
      date: session.date,
      neutralWorkPace,
      predictedPaceForDuration: predicted.pace,
      ratio,
      equivalentPace: currentPace * ratio,
      distanceKey: currentDistanceKey,
      zoneLabel: predicted.label,
      workSeconds,
      workMiles,
      restSeconds,
      restRatio,
      effectiveSeconds,
      repCount: reps.length,
      meanHr,
      hrDrift: hrDriftAcrossReps(reps),
      heatNormalized,
      confidence: session.confidence,
      reps: reps.map((r) => ({
        paceSeconds: r.pace,
        distanceMiles: r.miles,
        seconds: r.seconds,
        hr: r.hr,
      })),
      why,
      caveats,
    },
    reason: "",
  };
}

/** Run every session through `estimateFromSession`, keeping the rejections. */
export function estimateFromSessions(
  sessions: readonly ParsedSession[],
  currentPace: number,
  currentDistanceKey: RaceKey = "tenK",
  curveTilt = 0,
): ZoneSignalResult {
  const estimates: ZoneEstimate[] = [];
  const rejected: Array<{ date: string; reason: string }> = [];
  for (const s of sessions) {
    const { estimate, reason } = estimateFromSession(s, currentPace, currentDistanceKey, curveTilt);
    if (estimate) estimates.push(estimate);
    else rejected.push({ date: s.date, reason });
  }
  estimates.sort((a, b) => (a.date < b.date ? 1 : -1)); // newest first
  return { estimates, rejected };
}

// ---------------------------------------------------------------------------
// Combining sessions.
// ---------------------------------------------------------------------------

/** Fraction of a window's sessions that count toward the estimate. */
export const BEST_FRACTION = 0.4;

/** How much a session's pace statement counts. */
export interface WeightedZoneSignal {
  /** Weighted equivalent pace across the sessions used (sec/mile), at `distanceKey`. */
  equivalentPace: number;
  /** The distance `equivalentPace` is expressed at — carried through from the estimates. */
  distanceKey: RaceKey;
  /** Total work minutes behind the sessions used. */
  workMinutes: number;
  /** Sessions that fed the number. */
  sessionCount: number;
  /** Sessions read but not selected — coverage, not evidence. */
  consideredCount: number;
  /** The estimates used, newest first. */
  used: ZoneEstimate[];
}

/**
 * Combine sessions into one 10K statement — from the BEST of them, not the mean.
 *
 * WHY NOT THE MEAN. A training session bounds fitness from one side only. Run
 * 5:04/mi for 5 miles of reps and you have proven you can; run 6:00/mi for 12
 * miles of alternations and you have proven nothing about your ceiling, because
 * you were not trying to find it. Averaging the two treats a deliberately
 * submaximal aerobic session as evidence of being slower, which is how a real
 * 12-mile workout on 2026-08-01 priced this athlete at a 35:38 10K and pulled
 * the window estimate a minute slow.
 *
 * So: rank by 10K equivalent, keep the fastest `BEST_FRACTION`, and weight
 * within that set by effective work minutes × recency — volume because a
 * 30-minute session constrains 10K fitness far better than a 9-minute one,
 * recency because the block being measured is the one that built the curve.
 *
 * IS THIS THE RATCHET fitnessCurve.ts warns about? No, and the difference
 * matters. That ratchet was "fastest snapshot in N weeks" applied to the
 * model's OWN OUTPUT, so one flattering reading set a floor that outlived the
 * fitness behind it. This selects among INPUT sessions inside a bounded window
 * that the caller supplies. When form drops, the best session in the window
 * drops with it, the estimate follows, and the EWMA damps the descent — there
 * is no memory reaching past the window to hold the number up.
 */
export function combineZoneEstimates(
  estimates: readonly ZoneEstimate[],
  now: Date,
  halfLifeDays = 21,
  bestFraction = BEST_FRACTION,
): WeightedZoneSignal | null {
  if (estimates.length === 0) return null;

  const ranked = [...estimates].sort((a, b) => a.equivalentPace - b.equivalentPace);
  const keep = Math.max(2, Math.ceil(ranked.length * bestFraction));
  const best = ranked.slice(0, Math.min(keep, ranked.length));

  let wsum = 0;
  let sum = 0;
  let workMinutes = 0;
  const used: ZoneEstimate[] = [];

  for (const e of best) {
    const t = new Date(e.date.length === 10 ? `${e.date}T00:00:00Z` : e.date).getTime();
    if (!isFinite(t)) continue;
    const ageDays = Math.max(0, (now.getTime() - t) / 86_400_000);
    const recency = Math.pow(0.5, ageDays / halfLifeDays);
    const w = (e.effectiveSeconds / 60) * recency;
    if (!(w > 0)) continue;
    wsum += w;
    sum += e.equivalentPace * w;
    workMinutes += e.workSeconds / 60;
    used.push(e);
  }
  if (!(wsum > 0)) return null;

  used.sort((a, b) => (a.date < b.date ? 1 : -1)); // newest first
  return {
    equivalentPace: sum / wsum,
    // All estimates share one distanceKey by construction — every session in
    // a single combine call was priced against the same seed (fitnessPrediction
    // .ts calls this once per iteration with one current anchor distance).
    distanceKey: used[0].distanceKey,
    workMinutes: Math.round(workMinutes),
    sessionCount: used.length,
    consideredCount: estimates.length,
    used,
  };
}

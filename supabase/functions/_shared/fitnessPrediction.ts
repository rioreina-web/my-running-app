// ============================================================================
// fitnessPrediction.ts — server-side port of the iOS fitness predictor.
//
// Faithful TypeScript port of
//   RunningLog/Analysis/FitnessPredictorService.swift:generateLocalPrediction
// and its helpers (detectRaces, detectTrainingAnchors, detectDetraining).
//
// WHY THIS EXISTS: fitness_snapshots were only ever written by the iOS app,
// on-device, when a user opened the predictor screen — so the server-side
// Coach Read / athlete-state read stale-or-absent fitness data. This module
// lets a nightly edge function (compute-fitness-snapshot) regenerate a
// snapshot for every active athlete, using the SAME algorithm the app shows
// so the two never diverge. See
// outputs/fitness-snapshot-writer-diagnosis-2026-07-02.md.
//
// PARITY: the race-equivalence math is reused from _shared/paces.ts, whose
// RACE_RATIOS_TO_10K table is identical to iOS PaceCalculator.performanceRatios
// (verified 2026-07-02). Truncation points mirror the Swift Int() casts so the
// stored seconds match what the app computes.
//
// PURITY: this file has no I/O. The edge function maps training_logs rows into
// the WorkoutInput / VoiceLogInput shapes below and passes `now` explicitly, so
// the whole thing is deterministic and unit-testable — same pattern as
// _shared/builders/*.
// ============================================================================

import { equivalentRaceTimeSeconds, type RaceKey } from "./paces.ts";
import { heatNeutralPace } from "./pace-heat-adjustment.ts";
import { adjustPaceForGrade } from "./pace-grade-adjustment.ts";
import { normalizeRaceTime, type RaceConditions } from "./raceNormalization.ts";
import { mostRecentPrior, smoothFitnessPace } from "./fitnessCurve.ts";
import {
  combineZoneEstimates,
  estimateFromSessions,
  type ParsedBlock,
  type ParsedSession,
  type ZoneEstimate,
} from "./trainingZoneSignal.ts";

/** Arithmetic mean; 0 for an empty list (callers guard emptiness first). */
const mean = (xs: number[]): number =>
  xs.length === 0 ? 0 : xs.reduce((s, x) => s + x, 0) / xs.length;

// ---------------------------------------------------------------------------
// Inputs — the edge function reconstructs these from training_logs.
// ---------------------------------------------------------------------------

/** A completed run (from HealthKit/Strava, surfaced via training_logs). */
export interface WorkoutInput {
  date: string; // "yyyy-MM-dd"
  distanceMiles: number;
  durationMinutes: number;
  paceSecondsPerMile: number;
  type?: string;
  /** User override (2026-07-24): the athlete corrected this mark — e.g. flagged
   *  it as a duplicate import or "not a real session". When true it is dropped
   *  from every fitness signal (anchor, volume, quality, endurance). The user's
   *  correction always wins over auto-detection. */
  userExcludedFromFitness?: boolean;
}

/** Conditions on a training_logs row (weather_actual: temp_f + dew_point_f). */
export interface WeatherInput {
  tempF: number;
  dewPointF: number;
}

/**
 * One lap from `running_workout_laps` (server-only richness — the iOS
 * predictor never sees these). Rest-aware interval analysis: work reps are
 * heat- and grade-normalized, penalized for long recoveries, and merged into
 * the same hard-effort pool the pace-segment signal uses.
 */
export interface LapInput {
  workoutId: string;
  date: string; // "yyyy-MM-dd"
  lapIndex: number;
  distanceMeters?: number | null;
  movingTimeSeconds?: number | null;
  avgPaceSecPerMile?: number | null;
  isRest?: boolean | null;
  totalElevationGain?: number | null; // meters of climb within the lap
  tempF?: number | null;
  dewPointF?: number | null;
  /** Neutral-day equivalent pace, pre-computed by fetch-workout-weather. */
  heatAdjustedPaceSecPerMile?: number | null;
}

/** One labeled GPS pace segment on a training_logs row (pace_segments). */
export interface PaceSegmentInput {
  effort: string; // "easy" | "tempo" | "threshold" | "interval" | "race_pace" | ...
  durationSeconds: number;
  distanceMiles: number;
  pacePerMile: string; // "M:SS"
}

/** Observer parse (parsed_structure) — the trusted training-anchor signal. */
export interface ParsedStructureInput {
  confidence: number; // 0..1
  type: string; // "interval" | "tempo" | "race" | "race_pace" | "progression" | "long_run" | "easy" | ...
  equivalentRacePace?: { pacePerMile: string; distanceKey: string } | null;
  workSummary?: { totalDistanceMi: number } | null;
  /**
   * `parsed_structure.blocks` — the per-rep geometry the parser isolated.
   * This is what the training signal actually reads (2026-08-17); the rest of
   * this interface predates it. `equivalent_race_pace` is null on every row in
   * prod, so `detectTrainingAnchors` has never fired on real data.
   */
  blocks?: ParsedBlock[] | null;
  /** `parsed_structure.intent_pattern`, e.g. "10x1K @ 3:15-3:23 w/ 60s". */
  intentPattern?: string | null;
}

/** A voice log / check-in row (the qualitative + parsed side of training_logs). */
export interface VoiceLogInput {
  date: string; // "yyyy-MM-dd"
  notes: string;
  pacesMentioned?: string[];
  paceSegments?: PaceSegmentInput[] | null;
  parsedStructure?: ParsedStructureInput | null;
  /** From training_logs.weather_actual — normalizes hard paces to neutral. */
  weather?: WeatherInput | null;
}

/** A prior fitness_snapshots row (for the decay-gated baseline fallback). */
export interface PriorSnapshotInput {
  createdAt: string; // ISO timestamp
  estimated10kPaceSeconds: number;
  confidence: string; // "High" | "Medium" | "Low"
  /** The row's `data_source`. The curve damps only against rows THIS model
   *  wrote (marked `· v2`); anything else is another program's opinion. */
  dataSource?: string | null;
}

/** Optional active training-plan goal. */
export interface PlanGoalInput {
  status: "active" | string;
  raceDistanceKey: RaceType; // canonical race type of the goal
  targetTimeSeconds: number;
  raceDistanceMiles: number;
}

export interface PredictionInput {
  workouts: WorkoutInput[]; // last ~30d
  voiceLogs: VoiceLogInput[]; // last ~30d
  extendedWorkouts?: WorkoutInput[]; // last ~180d (race detection)
  extendedVoiceLogs?: VoiceLogInput[]; // last ~180d
  priorSnapshots?: PriorSnapshotInput[];
  plan?: PlanGoalInput | null;
  /**
   * Known races from the `confirmed_races` table, mapped to DetectedRace.
   * Merged with note/workout-detected races before anchor selection — the iOS
   * predictor only note-parses races, so this makes the server strictly more
   * reliable while using the identical anchor-selection logic. De-duplicated by
   * (raceType, date) against detected races.
   */
  seededRaces?: DetectedRace[];
  /**
   * running_workout_laps rows for the last ~21 days (server-only signal).
   * Optional — the model works identically without them.
   */
  laps?: LapInput[];
  now?: Date; // injectable for tests; defaults to new Date()
}

// ---------------------------------------------------------------------------
// Output — everything compute-fitness-snapshot needs to write a row.
// ---------------------------------------------------------------------------

export type ConfidenceTier = "high" | "medium" | "low";

export interface FitnessPredictionResult {
  estimated10kPaceSeconds: number;
  predictedMileSeconds: number;
  predicted5kSeconds: number;
  predicted10kSeconds: number;
  predictedHalfSeconds: number;
  predictedMarathonSeconds: number;
  confidence: string; // legacy mixed-case "High" | "Medium" | "Low"
  confidenceTier: ConfidenceTier;
  dataSource: string;
  workoutCount: number;
  // Honesty columns (CLAUDE.md hard rule #7) — half-window in seconds.
  rangeMileSeconds: number;
  range5kSeconds: number;
  range10kSeconds: number;
  rangeHalfSeconds: number;
  rangeMarathonSeconds: number;
  summary: string;
  /** Lifetime PRs derived from ALL confirmed races (any age) — fastest finish
   *  per distance. Display/context only; never anchors current fitness.
   *  (2026-07-17, race-gathering.) */
  lifetimePRs: Partial<Record<RaceType, { timeSeconds: number; date: string }>>;
  /**
   * The sessions behind the number (2026-08-17). A projection with a confidence
   * tier and nothing else asks to be taken on faith; this is the workings.
   * `used` are the sessions the estimate actually rests on, newest first.
   * `readButNotUsed` is the honest other half — what was looked at and passed
   * over, with the reason, so "we only had two sessions" is visible rather than
   * inferred.
   */
  supportingTraining: {
    used: ZoneEstimate[];
    readButNotUsed: Array<{ date: string; reason: string }>;
    workMinutes: number;
  };
}

// ---------------------------------------------------------------------------
// Constants (ported verbatim).
// ---------------------------------------------------------------------------

export type RaceType = "mile" | "fiveK" | "tenK" | "half" | "marathon";

// RaceType → miles (FitnessPredictorService RaceType.distanceMiles).
const RACE_TYPE_MILES: Record<RaceType, number> = {
  mile: 1.0,
  fiveK: 3.107,
  tenK: 6.214,
  half: 13.109,
  marathon: 26.219,
};

// RaceType → GPS tolerance in miles (RaceType.tolerance).
// Exported for index.ts race-candidate detection (2026-07-17).
export const RACE_TYPE_TOLERANCE: Record<RaceType, number> = {
  mile: 0.08,
  fiveK: 0.2,
  tenK: 0.4,
  half: 0.5,
  marathon: 1.0,
};

// RaceType → the human label iOS uses (RaceType.rawValue), so the stored
// `data_source` / summary strings match the app exactly.
// Exported for index.ts race-candidate detection (2026-07-17).
export const RACE_TYPE_LABEL: Record<RaceType, string> = {
  mile: "Mile",
  fiveK: "5K",
  tenK: "10K",
  half: "Half Marathon",
  marathon: "Marathon",
};

// ConfidenceTier.rangeFraction — half-window as a fraction of the point.
// Tightened 2026-07-15: the old 1.5/3/5% bands rendered absurdly wide at
// marathon distance (±3% of a ~2:24 marathon ≈ ±4.3 min → a 9-min spread).
// A race-time prediction is really a %-of-pace estimate; ~1–3% is honest.
// Keep athlete-state.ts:bandFractionFor in sync with these.
const RANGE_FRACTION: Record<ConfidenceTier, number> = {
  high: 0.010,
  medium: 0.018,
  low: 0.030,
};

// NOTE (2026-07-16): the old server-only ENDURANCE_FADE table was removed —
// the Swift model replaced it with the marathon volume factor (+6% max below
// 40 mi/wk, applied at prediction assembly) and distance-aware ranges. Keeping
// both would double-penalize the marathon relative to the app.

// iOS uses this exact constant for 10K miles when deriving tenKSeconds.
const TEN_K_MILES = 6.21371;

// RaceDistanceConstants — the distances the iOS predictor plugs into the
// distance-aware range math (RunningLog/Workouts/PaceCalculator.swift:11-14).
const RANGE_ITEM_MILES: Record<RaceType, number> = {
  mile: 1.0,
  fiveK: 3.1068560,
  tenK: 6.2137119,
  half: 13.109375,
  marathon: 26.21875,
};

const METERS_PER_MILE = 1609.344;

// ---------------------------------------------------------------------------
// Long-run endurance readiness (2026-07-24 — v2 "honesty" redesign).
// ---------------------------------------------------------------------------
//
// The marathon (and, more gently, the half) is a race-equivalence conversion
// from 10K speed — which ASSUMES the athlete has built the long-run durability
// to hold that pace over the distance. The prior guard keyed ONLY off weekly
// mileage (max +6% below 40 mi/wk), so an athlete with high volume made up of
// SHORT runs or doubles got zero endurance penalty and the marathon read off
// pure speed. This shades the point estimate UP based on the athlete's LONGEST
// recent long runs — the actual driver of marathon durability — with weekly
// mileage kept only as a floor.
//
// Distance is the dominant signal; repeat-count is secondary. Calibrated
// against a real athlete (~60 mi/wk, longest long run 17.8 mi once): the
// factor shades a 2:27:42 equivalence to ~2:31, matching the athlete's honest
// self-assessment. Mirrored 1:1 in FitnessPredictorService.swift (parity).
const LONGRUN_READINESS_LOOKBACK_DAYS = 70;   // 10 weeks
const LONGRUN_COUNT_MIN_MILES = 16.0;         // a run that counts toward durability
export const MARA_READY_LONGRUN_MILES = 20.0; // a true 20-miler = marathon-ready distance
export const MARA_READY_LONGRUN_COUNT = 3.0;  // ~3 runs ≥16mi = repeat durability
export const MARA_MAX_ENDURANCE_PENALTY = 0.12; // shade at ZERO long-run base (the calibration dial)
export const HALF_READY_LONGRUN_MILES = 15.0; // a 15-miler = half-ready distance
export const HALF_MAX_ENDURANCE_PENALTY = 0.06; // halves need less durability than fulls

// ---------------------------------------------------------------------------
// Heat normalization (Part 2A — server-only multi-signal).
// ---------------------------------------------------------------------------

/**
 * Neutral-day normalization now lives in pace-heat-adjustment.ts (2026-08-17)
 * so trainingZoneSignal.ts can use it without importing this file — that would
 * be a cycle, since this file consumes the signal. Re-exported here because
 * callers and tests already reach for it at this path.
 */
export { heatNeutralPace };

// ---------------------------------------------------------------------------
// Lap-level interval analysis (Part 2B — rest-aware, server-only).
// ---------------------------------------------------------------------------

/** A neutral-normalized, rest-penalized work rep derived from laps. */
export interface LapEffort {
  date: string;
  paceSeconds: number; // neutral (heat + grade adjusted), rest penalty applied
  distanceMiles: number;
  /** True when the source workout had rest laps between work laps — the laps
   *  are interval REPS (near-max, Riegel-by-distance applies). False means
   *  continuous quality (tempo-like: sustained, LT→10K conversion). */
  hasRestStructure: boolean;
}

/**
 * Turn raw `running_workout_laps` into hard-effort entries for the
 * pace-segment signal pool.
 *
 * Work reps: `is_rest === false` (explicit — null means unknown), distance
 * ≥ 0.15 mi, final pace within 210–540 s/mi.
 *
 * Rep pace priority:
 *   1. `heat_adjusted_pace_sec_per_mile`. VERIFIED SEMANTICS: fetch-workout-
 *      weather's applyHeatToLaps stores adjustPace(...).neutralEquivalentPace-
 *      Seconds = observed / (1 + pct × repLengthFactor) — the FASTER pace this
 *      rep would have cost on a neutral day (heat correctly credited). The
 *      20260528222217 backfill computes the same direction (pace / (1 + pct)).
 *      Used directly.
 *   2. Raw pace, heat-normalized via heatNeutralPace when the lap carries
 *      temp_f + dew_point_f.
 *   3. Raw pace.
 *
 * Grade: when total_elevation_gain + distance are present, the rep is
 * grade-adjusted (Minetti GAP, pace-grade-adjustment.ts). Only gain is stored
 * on laps, so this credits uphill reps and passes flat laps through.
 *
 * Rest context: per workout, ratio = rest-lap seconds between the first and
 * last work lap ÷ work-lap seconds. Reps run with full recovery overstate
 * continuous race fitness:
 *   ratio ≥ 2.0 → +2.5% (cap) · ratio ≥ 1.0 → +1.5% · ratio < 0.5 → 0
 */
export function deriveLapEfforts(laps: LapInput[]): LapEffort[] {
  if (laps.length === 0) return [];
  const byWorkout = new Map<string, LapInput[]>();
  for (const lap of laps) {
    const arr = byWorkout.get(lap.workoutId);
    if (arr) arr.push(lap);
    else byWorkout.set(lap.workoutId, [lap]);
  }

  const out: LapEffort[] = [];
  for (const group of byWorkout.values()) {
    group.sort((a, b) => a.lapIndex - b.lapIndex);

    const reps: Array<{ index: number; pace: number; distMi: number; seconds: number; date: string }> = [];
    for (const lap of group) {
      if (lap.isRest !== false) continue; // only explicit work laps
      const meters = lap.distanceMeters ?? 0;
      const distMi = meters / METERS_PER_MILE;
      if (!(distMi >= 0.15)) continue;

      let pace: number;
      if (lap.heatAdjustedPaceSecPerMile != null && lap.heatAdjustedPaceSecPerMile > 0) {
        pace = lap.heatAdjustedPaceSecPerMile; // already the neutral-day pace (see doc above)
      } else {
        const moving = lap.movingTimeSeconds ?? 0;
        const raw = lap.avgPaceSecPerMile != null && lap.avgPaceSecPerMile > 0
          ? lap.avgPaceSecPerMile
          : moving > 0
            ? moving / distMi
            : 0;
        if (!(raw > 0)) continue;
        pace = lap.tempF != null && lap.dewPointF != null
          ? heatNeutralPace(raw, lap.tempF, lap.dewPointF, distMi)
          : raw;
      }

      const gain = lap.totalElevationGain ?? 0;
      if (gain > 0 && meters > 0) {
        const gradePct = (gain / meters) * 100;
        pace = adjustPaceForGrade(pace, gradePct).adjustedPaceSeconds;
      }

      if (pace < 210 || pace > 540) continue;
      reps.push({ index: lap.lapIndex, pace, distMi, seconds: lap.movingTimeSeconds ?? 0, date: lap.date });
    }
    if (reps.length === 0) continue;

    const firstIdx = reps[0].index;
    const lastIdx = reps[reps.length - 1].index;
    let restSeconds = 0;
    for (const lap of group) {
      if (lap.isRest === true && lap.lapIndex > firstIdx && lap.lapIndex < lastIdx) {
        restSeconds += lap.movingTimeSeconds ?? 0;
      }
    }
    const workSeconds = reps.reduce((s, r) => s + r.seconds, 0);
    const restRatio = workSeconds > 0 ? restSeconds / workSeconds : 0;
    const restPenalty = restRatio >= 2.0 ? 0.025 : restRatio >= 1.0 ? 0.015 : 0;

    for (const r of reps) {
      out.push({
        date: r.date,
        paceSeconds: r.pace * (1 + restPenalty),
        distanceMiles: r.distMi,
        hasRestStructure: restSeconds > 0,
      });
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// Small helpers.
// ---------------------------------------------------------------------------

/** "M:SS" → seconds. Returns 0 on malformed input (matches Swift). */
export function paceStringToSeconds(pace: string): number {
  const parts = pace.split(":");
  if (parts.length !== 2) return 0;
  const m = Number(parts[0]);
  const s = Number(parts[1]);
  if (!Number.isFinite(m) || !Number.isFinite(s)) return 0;
  return m * 60 + s;
}

/** Parse "M:SS/mi" (or "M:SS") → seconds. Returns null on malformed. */
function parsePaceString(pace: string): number | null {
  const cleaned = pace.replace("/mi", "");
  const parts = cleaned.split(":");
  if (parts.length !== 2) return null;
  const m = Number.parseInt(parts[0], 10);
  const s = Number.parseInt(parts[1], 10);
  if (!Number.isFinite(m) || !Number.isFinite(s)) return null;
  return m * 60 + s;
}

const RACE_TYPE_TO_KEY: Record<RaceType, RaceKey> = {
  mile: "mile",
  fiveK: "fiveK",
  tenK: "tenK",
  half: "half",
  marathon: "marathon",
};

/**
 * Convert a pace (sec/mi) at one race distance to the equivalent pace at
 * another, via the shared equivalence table. Mirrors iOS `convert(racePace:)`
 * and `convert(pace:from:to:)`.
 */
function convertPace(paceSecPerMile: number, from: RaceType, to: RaceType): number {
  const fromKey = RACE_TYPE_TO_KEY[from];
  const toKey = RACE_TYPE_TO_KEY[to];
  const fromMiles = RACE_TYPE_MILES[from];
  const toMiles = RACE_TYPE_MILES[to];
  const fromTime = paceSecPerMile * fromMiles;
  const toTime = equivalentRaceTimeSeconds(fromKey, fromTime, toKey);
  return toTime > 0 ? toTime / toMiles : paceSecPerMile;
}

/** Days between two "yyyy-MM-dd"/ISO dates (UTC), fractional. */
function daysBetween(from: Date, to: Date): number {
  return (to.getTime() - from.getTime()) / 86_400_000;
}

function parseDay(dateStr: string): Date | null {
  // Accept "yyyy-MM-dd" and full ISO. Treat as UTC midnight for the former.
  const iso = dateStr.length === 10 ? `${dateStr}T00:00:00Z` : dateStr;
  const d = new Date(iso);
  return Number.isNaN(d.getTime()) ? null : d;
}

function formatTime(totalSeconds: number): string {
  const s = Math.max(0, Math.round(totalSeconds));
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  const sec = s % 60;
  return h > 0
    ? `${h}:${String(m).padStart(2, "0")}:${String(sec).padStart(2, "0")}`
    : `${m}:${String(sec).padStart(2, "0")}`;
}

// ---------------------------------------------------------------------------
// Detected structures.
// ---------------------------------------------------------------------------

export interface DetectedRace {
  raceType: RaceType;
  paceSecondsPerMile: number;
  date: string;
  totalTimeSeconds: number;
  /** training_logs id of the source row (confirmed races). When present and
   *  laps exist for it, the race pace is read as its flat-cool equivalent —
   *  per-lap grade (Minetti) + heat (dew-point composite) adjusted. */
  sourceWorkoutId?: string;
  /** User override (2026-07-24): the athlete flagged this "race" mark as wrong
   *  — a mislabeled training run, or a duplicate of another race. When true it
   *  is removed from anchor selection and confidence entirely. */
  userExcluded?: boolean;
}

/**
 * Flat-cool equivalent pace for a race (2026-07-17). Race performances must be
 * read in context: 33:02 on a hilly 90°F/70°F-dew course is a different
 * fitness statement than 33:02 flat and cool. When the race's own laps are
 * available (matched by sourceWorkoutId — NOT by date, since warmup/cooldown
 * sync as separate workouts), each lap is:
 *   1. heat-normalized — prefer the stored heat_adjusted_pace (already the
 *      neutral-day cost), else compute from lap temp/dew;
 *   2. grade-adjusted — Minetti with damped downhill credit, from per-lap
 *      elevation gain (uphill cost credited; net-downhill courses read slower).
 * The distance-weighted mean is the effective pace, sanity-clamped to ±6% of
 * the raw pace. Coverage guard: laps must sum to within 15% of the race
 * distance, otherwise fall back to the raw pace (partial/duplicate laps).
 */
/**
 * Race-hour conditions for `normalizeRaceTime`, or null when nothing is on
 * file (caller then falls back to the lap read).
 *
 * Weather comes from the log-level stamp first — one reading for the whole
 * race, which is what a continuous effort actually experienced — falling back
 * to the race laps' own temp/dew. Elevation is summed over the race's WORK
 * laps only, so a warm-up logged on the same row can't inflate the climb.
 *
 * Returns null unless at least one term is present: normalizing with nothing
 * to normalize by would just re-report the raw time while implying it had
 * been corrected.
 */
function raceConditionsFor(
  race: DetectedRace,
  laps: LapInput[],
  weatherByDate: Map<string, WeatherInput>,
): RaceConditions | null {
  const own = race.sourceWorkoutId
    ? laps.filter((l) => l.workoutId === race.sourceWorkoutId && l.isRest === false)
    : [];

  let tempF: number | null = null;
  let dewPointF: number | null = null;
  const wx = weatherByDate.get(race.date);
  if (wx && isFinite(wx.tempF) && isFinite(wx.dewPointF)) {
    tempF = wx.tempF;
    dewPointF = wx.dewPointF;
  } else {
    const withWx = own.filter((l) => l.tempF != null && l.dewPointF != null);
    if (withWx.length > 0) {
      tempF = mean(withWx.map((l) => l.tempF as number));
      dewPointF = mean(withWx.map((l) => l.dewPointF as number));
    }
  }

  let elevationGainM: number | null = null;
  const gains = own.map((l) => l.totalElevationGain ?? 0).filter((g) => g > 0);
  if (gains.length > 0) elevationGainM = gains.reduce((s, g) => s + g, 0);

  if (tempF == null && elevationGainM == null) return null;
  return { tempF, dewPointF, elevationGainM };
}

export function raceEffectivePace(
  race: DetectedRace,
  laps: LapInput[],
): { pace: number; lapAdjusted: boolean } {
  const raw = { pace: race.paceSecondsPerMile, lapAdjusted: false };
  if (!race.sourceWorkoutId) return raw;
  const group = laps.filter((l) => l.workoutId === race.sourceWorkoutId && l.isRest === false);
  if (group.length === 0) return raw;

  let dist = 0;
  let sum = 0;
  for (const lap of group) {
    const meters = lap.distanceMeters ?? 0;
    const distMi = meters / METERS_PER_MILE;
    if (distMi <= 0.05) continue;

    let pace: number;
    if (lap.heatAdjustedPaceSecPerMile != null && lap.heatAdjustedPaceSecPerMile > 0) {
      pace = lap.heatAdjustedPaceSecPerMile;
    } else {
      const moving = lap.movingTimeSeconds ?? 0;
      const rawPace = lap.avgPaceSecPerMile != null && lap.avgPaceSecPerMile > 0
        ? lap.avgPaceSecPerMile
        : moving > 0
          ? moving / distMi
          : 0;
      if (!(rawPace > 0)) continue;
      pace = lap.tempF != null && lap.dewPointF != null
        ? heatNeutralPace(rawPace, lap.tempF, lap.dewPointF, distMi)
        : rawPace;
    }

    const gain = lap.totalElevationGain ?? 0;
    if (gain > 0 && meters > 0) {
      pace = adjustPaceForGrade(pace, (gain / meters) * 100).adjustedPaceSeconds;
    }

    sum += pace * distMi;
    dist += distMi;
  }
  if (dist <= 0) return raw;

  const expected = RACE_TYPE_MILES[race.raceType];
  if (Math.abs(dist - expected) / expected > 0.15) return raw;

  let pace = sum / dist;
  // ±5% sanity clamp. Laps store only elevation GAIN (no loss), so gain/dist
  // treats every lap as pure climb and overcredits rolling loops — the Cap 10K
  // calibration (outputs/grade-adjusted-pace-plan §10.1) puts the honest hill
  // cost of a rolling 10K at ~2.5-4.5%; heat adds a few % more. 5% keeps the
  // combined credit inside what the calibration supports.
  pace = Math.min(Math.max(pace, race.paceSecondsPerMile * 0.95), race.paceSecondsPerMile * 1.05);
  return { pace, lapAdjusted: true };
}

export interface TrainingAnchor {
  kind: "tempoSustained" | "intervalSession" | "racePaceEffort" | "longRunFinish";
  paceSecondsPerMile: number;
  distanceMiles: number;
  equivalentTenKPace: number;
  date: string;
  confidence: number;
}

export interface DetrainingSignal {
  lowVolume: boolean;
  zeroQuality: boolean;
  layoff: boolean;
  reasons: string[];
  severity: number;
}

function detrainingSeverity(count: number): number {
  switch (count) {
    case 3:
      return 1.0;
    case 2:
      return 0.7;
    case 1:
      return 0.4;
    default:
      return 0.0;
  }
}

// parsed_structure type → distanceKey normalization for equivalentRacePace.
function distanceKeyToRaceType(key: string): RaceType | null {
  switch (key.toLowerCase()) {
    case "mile":
    case "1mi":
      return "mile";
    case "5k":
    case "fivek":
      return "fiveK";
    case "10k":
    case "tenk":
      return "tenK";
    case "half":
    case "halfmarathon":
    case "half_marathon":
      return "half";
    case "marathon":
      return "marathon";
    default:
      return null;
  }
}

// Efforts that count as "work" (vs. recovery) for the broken-rep penalty.
const HARD_SEGMENT_EFFORTS = new Set([
  "interval", "tempo", "threshold", "race_pace", "fast", "speed", "repeat",
]);

/**
 * Broken-rep penalty (2026-07-15) — a fraction in [0, 0.10] that SLOWS an
 * interval/tempo session's "equivalent race pace" before it becomes a fitness
 * anchor.
 *
 * WHY: the parser derives equivalent_race_pace from rep pace, but reps run with
 * recovery overstate continuous race pace — the more rest between reps and the
 * shorter each rep, the larger the gap. Without this, a set of rested 400s at
 * 4:50 grades out as a 15:00 5K and out-ranks a real race. See the July 2026
 * prediction-honesty thread.
 *
 *   penalty = 0.08·min(R, 1) + 0.05·max(0, (1 − meanRepMi))   capped at 0.10
 *     R         = recovery seconds (between first & last rep) ÷ work seconds
 *     meanRepMi = work miles ÷ rep count
 *
 * Returns 0 when there aren't enough real segments to judge, so the parser's
 * pace is kept as-is (voice-only logs, warmup-only files, etc.).
 */
function recoveryPenaltyFromSegments(segments: PaceSegmentInput[] | null | undefined): number {
  if (!segments || segments.length === 0) return 0;
  let firstHard = -1, lastHard = -1, workSec = 0, workMiles = 0, hardCount = 0;
  segments.forEach((s, i) => {
    if (HARD_SEGMENT_EFFORTS.has(s.effort.toLowerCase()) && s.distanceMiles > 0.05) {
      if (firstHard < 0) firstHard = i;
      lastHard = i;
      workSec += s.durationSeconds;
      workMiles += s.distanceMiles;
      hardCount += 1;
    }
  });
  if (hardCount < 2 || workMiles < 1.0 || workSec <= 0) return 0;

  let recoverySec = 0;
  for (let i = firstHard; i <= lastHard; i++) {
    if (!HARD_SEGMENT_EFFORTS.has(segments[i].effort.toLowerCase())) {
      recoverySec += segments[i].durationSeconds;
    }
  }
  const recoveryRatio = Math.min(recoverySec / workSec, 1.0);
  const meanRepMiles = workMiles / hardCount;
  const repLengthShortfall = Math.max(0, 1.0 - meanRepMiles);
  return Math.min(0.10, 0.08 * recoveryRatio + 0.05 * repLengthShortfall);
}

// ---------------------------------------------------------------------------
// detectTrainingAnchors — Observer parsed_structure only (segment fallback
// deliberately disabled in the iOS source; see its comment).
// ---------------------------------------------------------------------------

export function detectTrainingAnchors(voiceLogs: VoiceLogInput[]): TrainingAnchor[] {
  const anchors: TrainingAnchor[] = [];

  for (const log of voiceLogs) {
    const parsed = log.parsedStructure;
    if (!parsed || parsed.confidence < 0.6 || !parsed.equivalentRacePace) continue;

    let paceSec = paceStringToSeconds(parsed.equivalentRacePace.pacePerMile);
    if (paceSec <= 0) continue;

    // Slow rep-derived paces for recovery + short rep length so a heavily
    // rested interval set doesn't grade out as continuous race fitness.
    paceSec = paceSec * (1 + recoveryPenaltyFromSegments(log.paceSegments));

    const fromType = distanceKeyToRaceType(parsed.equivalentRacePace.distanceKey);
    if (!fromType) continue;
    const tenK = convertPace(paceSec, fromType, "tenK");
    const workDist = parsed.workSummary?.totalDistanceMi ?? 0;

    let kind: TrainingAnchor["kind"];
    switch (parsed.type.toLowerCase()) {
      case "interval":
        kind = "intervalSession";
        break;
      case "tempo":
        kind = "tempoSustained";
        break;
      case "race":
      case "race_pace":
        kind = "racePaceEffort";
        break;
      case "progression":
      case "long_run":
        kind = "longRunFinish";
        break;
      default:
        continue; // skip easy/unclear
    }

    anchors.push({
      kind,
      paceSecondsPerMile: paceSec,
      distanceMiles: Math.max(workDist, 2.0),
      equivalentTenKPace: tenK,
      date: log.date,
      confidence: Math.min(0.85, parsed.confidence),
    });
  }

  // Sort by date desc, confidence desc.
  anchors.sort((a, b) => (a.date !== b.date ? (a.date > b.date ? -1 : 1) : b.confidence - a.confidence));
  return anchors;
}

// ---------------------------------------------------------------------------
// detectRaces — Phase 1 (parse race results from notes) + Phase 2 (workout
// pace detection on user-declared race dates).
// ---------------------------------------------------------------------------

const RACE_KEYWORDS = ["race", "raced", "pr ", "pr:", "pb ", "pb:", "personal best", "personal record", "finish time"];
const DISTANCE_PATTERNS: Array<[string, RaceType]> = [
  ["marathon", "marathon"],
  ["half marathon", "half"],
  ["half", "half"],
  ["10k", "tenK"],
  ["5k", "fiveK"],
  ["mile", "mile"],
];
const WORKOUT_CONTEXT_PATTERNS = [
  "tempo run", "workout:", "workout today", "interval session", "fartlek",
  "mile repeat", "mile repeats", "k repeat", "kilometer repeat",
  "x 400", "x 800", "x 1000", "x 1k", "x 200", "x 600", "x 1200",
  "x400", "x800", "x1000", "x1k", "x200", "x600", "x1200",
  "threshold intervals", "threshold work", "track session",
  "warm-up:", "warm up:", "cool-down:", "cool down:",
];
const FORWARD_LOOKING = [
  "leading up to", "looking forward to", "next race", "upcoming race",
  "before the race", "race coming up", "race next", "racing in", "preparing for the race",
];
const PAST_RACE_SIGNALS = [
  "raced", "race today", "race result", "finish time", "for the race",
  "ran the", "finished the", "completed the race", "race report", "race recap", "ran my",
];

const TIME_RE = /(\d{1,2}):(\d{2}):(\d{2})|(\d{1,2}):(\d{2})/g;

export function detectRaces(workouts: WorkoutInput[], voiceLogs: VoiceLogInput[]): DetectedRace[] {
  const races: DetectedRace[] = [];

  // ── PHASE 1: explicit race results in notes ──
  for (const log of voiceLogs) {
    const notes = log.notes.toLowerCase();
    if (!RACE_KEYWORDS.some((k) => notes.includes(k))) continue;
    if (WORKOUT_CONTEXT_PATTERNS.some((k) => notes.includes(k))) continue;

    const hasForward = FORWARD_LOOKING.some((k) => notes.includes(k));
    const hasPast = PAST_RACE_SIGNALS.some((k) => notes.includes(k));
    if (hasForward && !hasPast) continue;

    for (const [pattern, raceType] of DISTANCE_PATTERNS) {
      if (!notes.includes(pattern)) continue;
      if (races.some((r) => r.raceType === raceType && r.date === log.date)) break;

      const original = log.notes;
      TIME_RE.lastIndex = 0;
      let match: RegExpExecArray | null;
      let matched = false;
      while ((match = TIME_RE.exec(original)) !== null) {
        let totalSeconds: number | null = null;
        if (match[1] !== undefined && match[2] !== undefined && match[3] !== undefined) {
          totalSeconds = Number(match[1]) * 3600 + Number(match[2]) * 60 + Number(match[3]);
        } else if (match[4] !== undefined && match[5] !== undefined) {
          totalSeconds = Number(match[4]) * 60 + Number(match[5]);
        }
        if (totalSeconds !== null && totalSeconds > 60 && totalSeconds < 36000) {
          const pace = totalSeconds / RACE_TYPE_MILES[raceType];
          if (pace >= 180 && pace <= 900) {
            races.push({ raceType, paceSecondsPerMile: pace, date: log.date, totalTimeSeconds: totalSeconds });
            matched = true;
            break;
          }
        }
      }
      void matched;
      break; // only first distance pattern per log
    }
  }

  // ── PHASE 2: workout pace detection on declared race dates ──
  const raceDates = new Set(
    voiceLogs
      .filter((log) => RACE_KEYWORDS.some((k) => log.notes.toLowerCase().includes(k)))
      .map((l) => l.date),
  );

  const RACE_ORDER: RaceType[] = ["mile", "fiveK", "tenK", "half", "marathon"];
  for (const workout of workouts) {
    if (!raceDates.has(workout.date)) continue;

    for (const raceType of RACE_ORDER) {
      if (races.some((r) => r.raceType === raceType)) continue;

      const minDist = RACE_TYPE_MILES[raceType] - RACE_TYPE_TOLERANCE[raceType];
      const maxDist = RACE_TYPE_MILES[raceType] + RACE_TYPE_TOLERANCE[raceType];
      if (workout.distanceMiles < minDist || workout.distanceMiles > maxDist) continue;

      const minComparisonDist = Math.min(4.0, RACE_TYPE_MILES[raceType] * 0.8);
      const others = workouts.filter(
        (w) =>
          (w.date !== workout.date || Math.abs(w.distanceMiles - workout.distanceMiles) > 0.1) &&
          w.distanceMiles >= minComparisonDist,
      );
      if (others.length === 0) continue;

      const avgPace = others.reduce((s, w) => s + w.paceSecondsPerMile, 0) / others.length;
      if (workout.paceSecondsPerMile >= avgPace * 0.85) continue; // not a race effort

      // Adjust GPS distance to standard race distance.
      const actualTimeSeconds = workout.durationMinutes * 60;
      const actualDistanceMiles = workout.distanceMiles;
      const targetDistanceMiles = RACE_TYPE_MILES[raceType];
      const distanceRatio = actualDistanceMiles / targetDistanceMiles;

      let adjustedTimeSeconds: number;
      if (distanceRatio >= 0.92 && distanceRatio <= 1.02) {
        adjustedTimeSeconds = Math.trunc(actualTimeSeconds);
      } else if (distanceRatio > 1.02 && distanceRatio < 1.08) {
        adjustedTimeSeconds = Math.trunc(actualTimeSeconds / distanceRatio);
      } else {
        const pcKey = closestRaceType(actualDistanceMiles);
        const converted = Math.trunc(
          equivalentRaceTimeSeconds(RACE_TYPE_TO_KEY[pcKey], actualTimeSeconds, RACE_TYPE_TO_KEY[raceType]),
        );
        adjustedTimeSeconds = converted > 0 ? converted : Math.trunc(actualTimeSeconds);
      }
      const adjustedPace = adjustedTimeSeconds / RACE_TYPE_MILES[raceType];
      races.push({ raceType, paceSecondsPerMile: adjustedPace, date: workout.date, totalTimeSeconds: adjustedTimeSeconds });
      break;
    }
  }

  races.sort((a, b) => (a.date > b.date ? -1 : a.date < b.date ? 1 : 0));
  return races;
}

function closestRaceType(distanceMiles: number): RaceType {
  const keys: Array<[RaceType, number]> = [
    ["mile", 1.0],
    ["fiveK", 3.10686],
    ["tenK", 6.21371],
    ["half", 13.1094],
    ["marathon", 26.2188],
  ];
  let best = keys[0];
  for (const k of keys) if (Math.abs(k[1] - distanceMiles) < Math.abs(best[1] - distanceMiles)) best = k;
  return best[0];
}

// ---------------------------------------------------------------------------
// detectDetraining.
// ---------------------------------------------------------------------------

export function detectDetraining(
  workouts: WorkoutInput[],
  voiceLogs: VoiceLogInput[],
  now: Date,
): DetrainingSignal | null {
  const twoWeeksAgo = new Date(now.getTime() - 14 * 86_400_000);
  const threeWeeksAgo = new Date(now.getTime() - 21 * 86_400_000);
  const fourWeeksAgo = new Date(now.getTime() - 28 * 86_400_000);
  const sixWeeksAgo = new Date(now.getTime() - 42 * 86_400_000);

  let recentMiles = 0;
  let baselineMiles = 0;
  for (const w of workouts) {
    const d = parseDay(w.date);
    if (!d) continue;
    if (d >= twoWeeksAgo) recentMiles += w.distanceMiles;
    else if (d >= sixWeeksAgo && d < twoWeeksAgo) baselineMiles += w.distanceMiles;
  }
  const recentMilesPerWeek = recentMiles / 2.0;
  // BASELINE WINDOW FIX (2026-07-16, mirrors Swift): divide baseline miles by
  // the weeks the data actually COVERS. Workouts arrive on a ~30-day window,
  // so the "6wk→2wk back" baseline holds at most ~16 days of data — dividing
  // by a fixed 4.0 understated baseline mi/wk, inflated the recent:baseline
  // ratio, and suppressed the low-volume detraining trigger.
  const earliestWorkoutDate = workouts
    .map((w) => parseDay(w.date))
    .filter((d): d is Date => d !== null)
    .reduce<Date | null>((min, d) => (min === null || d < min ? d : min), null) ?? sixWeeksAgo;
  const baselineWindowStart = earliestWorkoutDate > sixWeeksAgo ? earliestWorkoutDate : sixWeeksAgo;
  const baselineCoveredWeeks = Math.max((twoWeeksAgo.getTime() - baselineWindowStart.getTime()) / (7 * 86_400_000), 0.5);
  const baselineMilesPerWeek = baselineMiles / Math.min(baselineCoveredWeeks, 4.0);
  const ratio = baselineMilesPerWeek > 0 ? recentMilesPerWeek / baselineMilesPerWeek : 1.0;
  const lowVolume = (baselineMilesPerWeek > 0 && ratio < 0.5) || recentMilesPerWeek < 15.0;

  const qualifyingTypes = new Set(["tempo", "interval", "race", "progression", "race_pace"]);
  const recentQuality = voiceLogs.some((log) => {
    const d = parseDay(log.date);
    return d !== null && d >= threeWeeksAgo && log.parsedStructure !== null && log.parsedStructure !== undefined &&
      qualifyingTypes.has(log.parsedStructure.type.toLowerCase());
  });
  const zeroQuality = !recentQuality;

  const recentWorkoutDates = workouts
    .map((w) => parseDay(w.date))
    .filter((d): d is Date => d !== null && d >= fourWeeksAgo)
    .sort((a, b) => a.getTime() - b.getTime());
  let layoff = false;
  if (recentWorkoutDates.length < 2) {
    layoff = true;
  } else {
    for (let i = 1; i < recentWorkoutDates.length; i++) {
      const gap = daysBetween(recentWorkoutDates[i - 1], recentWorkoutDates[i]);
      if (gap >= 7.0) {
        layoff = true;
        break;
      }
    }
  }

  const triggerCount = [lowVolume, zeroQuality, layoff].filter(Boolean).length;
  if (triggerCount === 0) return null;

  const reasons: string[] = [];
  if (lowVolume) {
    reasons.push(
      recentMilesPerWeek < 15.0
        ? `low volume (${Math.round(recentMilesPerWeek)} mi/wk)`
        : `volume drop to ${Math.round(ratio * 100)}% of baseline`,
    );
  }
  if (zeroQuality) reasons.push("no quality work in 3wk");
  if (layoff) reasons.push("layoff (7+ day gap)");

  return { lowVolume, zeroQuality, layoff, reasons, severity: detrainingSeverity(triggerCount) };
}

// ---------------------------------------------------------------------------
// Main entry — port of generateLocalPrediction. Returns null when there is no
// usable fitness signal (the caller must NOT write a fabricated snapshot).
// ---------------------------------------------------------------------------

// ── Workout-driven capacities (v3, 2026-07-24) ──────────────────────────────
// Segment effort labels in production are coarse (`fast`/`steady`/`easy`), so
// we separate THRESHOLD from VO2 by rep GEOMETRY: a sustained hard segment
// (≥ THRESHOLD_MIN_SEG_MILES) is threshold/tempo work; short reps are VO2
// (a later pillar). Heart-rate refinement (pace-at-HR) is a planned follow-on —
// the segment carries avg HR in the DB but it isn't wired into the engine yet.
const THRESHOLD_LOOKBACK_DAYS = 42;          // threshold fitness fades ~6 weeks
const THRESHOLD_MIN_SEG_MILES = 0.8;         // a sustained rep, not a short VO2 rep
const THRESHOLD_MIN_EVIDENCE_MILES = 2.0;    // need ≥2mi of sustained work to trust it
const THRESHOLD_EFFORTS = new Set(["tempo", "threshold", "race_pace", "fast"]);
export const THRESHOLD_TO_10K = 0.95;        // 10K pace ≈ 95% of sustained-threshold pace (tunable)

export interface ThresholdSignal {
  thresholdPaceSeconds: number; // sec/mi, distance-weighted sustained-work pace
  equivalentTenKPace: number;   // sec/mi, 10K-equivalent of that threshold
  evidenceMiles: number;        // qualifying sustained hard mileage in window
  freshnessWeeks: number;       // weeks since the most recent qualifying session
}

/**
 * Threshold capacity from the athlete's tempo/threshold TRAINING (2026-07-24).
 * Scans the trailing ~6 weeks of pace-segments for SUSTAINED hard work (hard
 * effort AND ≥ THRESHOLD_MIN_SEG_MILES per rep — which excludes short VO2
 * reps), and distance-weights their pace into a threshold estimate + a
 * 10K-equivalent. Pure + deterministic; mirrored in Swift. Returns null when
 * there isn't enough sustained work to trust. This is the training-driven
 * signal for the half/marathon, independent of any race.
 */
export function thresholdCapacity(voiceLogs: VoiceLogInput[], now: Date): ThresholdSignal | null {
  const start = new Date(now.getTime() - THRESHOLD_LOOKBACK_DAYS * 86_400_000);
  let sumPaceMiles = 0;
  let miles = 0;
  let mostRecent: Date | null = null;
  for (const log of voiceLogs) {
    const d = parseDay(log.date);
    if (!d || d < start || d > now) continue;
    for (const seg of log.paceSegments ?? []) {
      if (!THRESHOLD_EFFORTS.has(seg.effort)) continue;
      if (seg.distanceMiles < THRESHOLD_MIN_SEG_MILES) continue; // short rep → VO2, not threshold
      const p = paceStringToSeconds(seg.pacePerMile);
      if (!(p > 0)) continue;
      sumPaceMiles += p * seg.distanceMiles;
      miles += seg.distanceMiles;
      if (!mostRecent || d > mostRecent) mostRecent = d;
    }
  }
  if (miles < THRESHOLD_MIN_EVIDENCE_MILES || !mostRecent) return null;
  const thresholdPace = sumPaceMiles / miles;
  return {
    thresholdPaceSeconds: Math.round(thresholdPace),
    equivalentTenKPace: Math.round(thresholdPace * THRESHOLD_TO_10K),
    evidenceMiles: Math.round(miles * 10) / 10,
    freshnessWeeks: Math.round((daysBetween(mostRecent, now) / 7) * 10) / 10,
  };
}

/**
 * Long-run durability signal for endurance-aware race projection (2026-07-24).
 * Scans the trailing ~10 weeks for the athlete's longest single run and how
 * many runs cleared the durability threshold. Pure + deterministic; mirrored
 * in Swift. `count16` counts runs ≥ LONGRUN_COUNT_MIN_MILES.
 */
/**
 * Collapse duplicate race marks (2026-07-24). One real race often lands in the
 * log 2–3 times: a Garmin/Strava double-import a day apart, or a training run
 * auto-tagged "race". Entries of the SAME distance within `dayWindow` days and
 * within `pctTol` on time are treated as the same physical event — we keep a
 * single representative (prefer one with a confirmed source row, else the
 * fastest) so it anchors once instead of inflating confidence as "multiple
 * agreeing races". Genuinely distinct races (different day or clearly different
 * time) are preserved. Purely deterministic; mirrored in Swift.
 */
export function dedupeRaces(races: DetectedRace[], dayWindow = 3, pctTol = 0.02): DetectedRace[] {
  const kept: DetectedRace[] = [];
  for (const r of races) {
    const dupOf = kept.findIndex((k) => {
      if (k.raceType !== r.raceType) return false;
      const dk = parseDay(k.date), dr = parseDay(r.date);
      if (!dk || !dr) return false;
      const daysApart = Math.abs(daysBetween(dk, dr));
      const pctApart = Math.abs(k.totalTimeSeconds - r.totalTimeSeconds) /
        Math.max(k.totalTimeSeconds, 1);
      return daysApart <= dayWindow && pctApart <= pctTol;
    });
    if (dupOf === -1) {
      kept.push(r);
      continue;
    }
    // Same event: keep the better representative (confirmed source, else faster).
    const existing = kept[dupOf];
    const rScore = (r.sourceWorkoutId ? 1 : 0);
    const eScore = (existing.sourceWorkoutId ? 1 : 0);
    if (rScore > eScore || (rScore === eScore && r.totalTimeSeconds < existing.totalTimeSeconds)) {
      kept[dupOf] = r;
    }
  }
  return kept;
}

export function longRunReadiness(
  workouts: WorkoutInput[],
  now: Date,
): { longestMiles: number; count16: number } {
  const lookbackStart = new Date(now.getTime() - LONGRUN_READINESS_LOOKBACK_DAYS * 86_400_000);
  let longestMiles = 0;
  let count16 = 0;
  for (const w of workouts) {
    const d = parseDay(w.date);
    if (!d || d < lookbackStart || d > now) continue;
    const mi = w.distanceMiles;
    if (!(mi > 0)) continue;
    if (mi > longestMiles) longestMiles = mi;
    if (mi >= LONGRUN_COUNT_MIN_MILES) count16 += 1;
  }
  return { longestMiles, count16 };
}

/**
 * Endurance shading factor (≥ 1.0) applied to a race-equivalence time.
 * readiness = distanceWeight·(longest/readyMiles) + countWeight·(count16/readyCount),
 * clamped to [0,1]; factor = 1 + maxPenalty·(1 − readiness). Distance-dominant.
 */
export function enduranceFactor(
  longestMiles: number,
  count16: number,
  readyMiles: number,
  readyCount: number,
  maxPenalty: number,
  distanceWeight = 0.9,
): number {
  const clamp01 = (x: number) => Math.max(0, Math.min(1, x));
  const readiness =
    distanceWeight * clamp01(longestMiles / readyMiles) +
    (1 - distanceWeight) * clamp01(count16 / readyCount);
  return 1.0 + maxPenalty * (1.0 - readiness);
}

export function generateFitnessPrediction(input: PredictionInput): FitnessPredictionResult | null {
  const now = input.now ?? new Date();
  // User overrides win over auto-detection: a workout the athlete flagged as a
  // bad/duplicate mark is removed before any signal is computed from it.
  const workouts = (input.workouts ?? []).filter((w) => !w.userExcludedFromFitness);
  const voiceLogs = input.voiceLogs ?? [];
  const extendedWorkouts = (input.extendedWorkouts && input.extendedWorkouts.length > 0 ? input.extendedWorkouts : workouts)
    .filter((w) => !w.userExcludedFromFitness);
  const extendedVoiceLogs = input.extendedVoiceLogs && input.extendedVoiceLogs.length > 0 ? input.extendedVoiceLogs : voiceLogs;
  const priorSnapshots = input.priorSnapshots ?? [];
  const plan = input.plan ?? null;
  const laps = input.laps ?? [];

  // Conditions by date — normalizes race + segment paces to neutral (Part 2A).
  const weatherByDate = new Map<string, WeatherInput>();
  for (const log of extendedVoiceLogs) {
    const wx = log.weather;
    if (wx && Number.isFinite(wx.tempF) && Number.isFinite(wx.dewPointF)) {
      weatherByDate.set(log.date, wx);
    }
  }

  // Lap-derived, rest-aware neutral efforts (Part 2B). Dates covered by laps
  // prefer laps over pace_segments in the hard-effort pool — laps are richer
  // (per-rep, rest-aware, weather-stamped) and using both double-counts.
  const lapEfforts = deriveLapEfforts(laps);

  const detected = detectRaces(extendedWorkouts, extendedVoiceLogs);
  // Merge confirmed_races (deduped by raceType+date), preferring the detected
  // entry when both exist.
  const mergedRaces = [...detected];
  for (const seed of input.seededRaces ?? []) {
    if (!mergedRaces.some((r) => r.raceType === seed.raceType && r.date === seed.date)) {
      mergedRaces.push(seed);
    }
  }
  // Honor user corrections first (drop marks flagged "not a race"/duplicate),
  // then collapse remaining near-duplicate imports so one real race anchors
  // once instead of triple-counting toward confidence (2026-07-24).
  const detectedRaces = dedupeRaces(mergedRaces.filter((r) => !r.userExcluded));

  // Voice paces + structured interval paces (fallback path when no anchor).
  const voicePaces: number[] = [];
  for (const log of voiceLogs) for (const p of log.pacesMentioned ?? []) {
    const v = parsePaceString(p);
    if (v !== null) voicePaces.push(v);
  }
  // Structured interval paces from parsed_structure equivalent race pace.
  const intervalPaces: Array<{ pace: number; type: string }> = [];
  for (const log of voiceLogs) {
    const parsed = log.parsedStructure;
    if (!parsed || parsed.confidence < 0.6 || !parsed.equivalentRacePace) continue;
    const paceSec = paceStringToSeconds(parsed.equivalentRacePace.pacePerMile);
    if (paceSec <= 0) continue;
    const t = parsed.type.toLowerCase();
    if (t === "interval") intervalPaces.push({ pace: paceSec, type: "interval" });
    else if (t === "tempo") intervalPaces.push({ pace: paceSec, type: "tempo" });
  }

  // ── Baseline from prior snapshots (decay-gated) ──
  // ANTI-RATCHET (2026-07-16, mirrors Swift): "fastest snapshot in 16 weeks"
  // let one transient fast estimate persist for ~4 months (snapshots feed
  // snapshots). Prefer the fastest of the last 4 weeks — recent enough to
  // still be demonstrated — falling back to the MOST RECENT trusted snapshot
  // in the 112-day window (not the fastest).
  let baselinePace: number | null = null;
  const sixteenWeeksAgo = new Date(now.getTime() - 112 * 86_400_000);
  const fourWeeksAgoForSnap = new Date(now.getTime() - 28 * 86_400_000);
  const inWindowSnaps = priorSnapshots.filter((s) => {
    const d = parseDay(s.createdAt);
    return d !== null && d >= sixteenWeeksAgo && (s.confidence === "High" || s.confidence === "Medium");
  });
  const recentSnaps = inWindowSnaps.filter((s) => {
    const d = parseDay(s.createdAt);
    return d !== null && d >= fourWeeksAgoForSnap;
  });
  const chosenSnapshot = recentSnaps.reduce<PriorSnapshotInput | null>(
    (best, s) => (best === null || s.estimated10kPaceSeconds < best.estimated10kPaceSeconds ? s : best),
    null,
  ) ?? inWindowSnaps.reduce<PriorSnapshotInput | null>(
    (latest, s) => (latest === null || s.createdAt > latest.createdAt ? s : latest),
    null,
  );
  if (chosenSnapshot) {
    const snapDate = parseDay(chosenSnapshot.createdAt)!;
    const weeksAgo = daysBetween(snapDate, now) / 7.0;
    const detraining = detectDetraining(workouts, voiceLogs, now);
    const decayPerWeek = detraining ? 0.003 * detraining.severity : 0.0;
    baselinePace = chosenSnapshot.estimated10kPaceSeconds * (1.0 + weeksAgo * decayPerWeek);
  }

  // ── Anchor selection ──
  let anchorPace: number | null = null;
  let anchorSource = "";
  let anchorWeeksAgo = 0;
  let chosenRace: DetectedRace | null = null;

  const trainingAnchors = detectTrainingAnchors(voiceLogs);
  const recentTrainingAnchor = trainingAnchors.find((a) => {
    const d = parseDay(a.date);
    if (!d) return false;
    return daysBetween(d, now) / 7.0 <= 4.0;
  }) ?? null;

  const racePrimaryWindowWeeks = 16.0;
  const raceTrustedWindowWeeks = 36.0;
  const scoredRaces = detectedRaces
    .map((race) => {
      const d = parseDay(race.date);
      if (!d) return null;
      const weeks = daysBetween(d, now) / 7.0;
      if (weeks > raceTrustedWindowWeeks) return null;
      // FLAT-COOL EQUIVALENT. 33:02 on a hilly humid course is a different
      // fitness statement than 33:02 flat and cool.
      //
      // (2026-08-16) `normalizeRaceTime` is now the primary path, replacing
      // `raceEffectivePace` as the anchor source. Measured on the Apr 12 Cap10K
      // (33:02, 69.3°F / 67.6° dew, 100 m gain over 10K):
      //
      //   raceEffectivePace   31:23   — pinned ON its own ±5% clamp
      //   normalizeRaceTime   31:53   — heat 39 s + elevation 30 s
      //
      // raceEffectivePace strains past its guard rail because laps store only
      // elevation GAIN, so `(gain/meters)` reads every lap as pure climb and
      // over-credits a rolling loop (its own comment says so). The clamp then
      // silently decides the anchor — a bound is not a measurement.
      // `normalizeRaceTime` models the loop honestly (gain ≈ loss, uphill costs
      // more than downhill returns) and lands 30 s more conservative without
      // touching a clamp. It also returns the per-term breakdown, so a surface
      // can say WHY rather than assert a number.
      //
      // Fallback order: normalized (conditions on file) → raceEffectivePace's
      // lap read → log-level heat only → raw. `totalTimeSeconds` stays actual
      // everywhere; this only feeds the anchor. A normalized time must never
      // be shown as a time she ran, and never mints a PR.
      const conditions = raceConditionsFor(race, laps, weatherByDate);
      let pace: number;
      if (conditions !== null) {
        const norm = normalizeRaceTime(race.totalTimeSeconds, race.raceType, conditions);
        pace = norm.neutralSeconds / RACE_TYPE_MILES[race.raceType];
      } else {
        const eff = raceEffectivePace(race, laps);
        pace = eff.pace;
        if (!eff.lapAdjusted) {
          const wx = weatherByDate.get(race.date);
          if (wx) pace = heatNeutralPace(pace, wx.tempF, wx.dewPointF, RACE_TYPE_MILES[race.raceType]);
        }
      }
      const tenK = convertPace(pace, race.raceType, "tenK");
      return { race, weeksAgo: weeks, tenKPace: tenK };
    })
    .filter((x): x is { race: DetectedRace; weeksAgo: number; tenKPace: number } => x !== null);

  // AGE-WEIGHTED selection (2026-07-16, mirrors Swift): pure fastest-in-36-
  // weeks was a max-filter over 9 months of noise — one GPS-flattered old
  // "race" permanently anchored fast. A 0.2%/week selection penalty means an
  // older race must be genuinely faster than a recent one to win.
  const bestRaceMatch = scoredRaces.reduce<{ race: DetectedRace; weeksAgo: number; tenKPace: number } | null>(
    (best, r) =>
      best === null ||
        r.tenKPace * (1.0 + r.weeksAgo * 0.002) < best.tenKPace * (1.0 + best.weeksAgo * 0.002)
        ? r
        : best,
    null,
  );

  if (bestRaceMatch) {
    // A race is durable proof of fitness. A recent training anchor may only
    // displace it once the race is past the primary window AND the anchor is
    // genuinely FASTER than the race's demonstrated pace — otherwise a modest
    // tempo (e.g. a 6:59 10K-equivalent) would wrongly override a 31:24 10K
    // race just because the race aged past 16 weeks. When the recent anchor is
    // slower/weaker, the race stays and is decayed forward by the model below.
    const raceIsPrimary =
      bestRaceMatch.weeksAgo <= racePrimaryWindowWeeks ||
      recentTrainingAnchor === null ||
      recentTrainingAnchor.equivalentTenKPace >= bestRaceMatch.tenKPace;
    if (raceIsPrimary) {
      anchorPace = bestRaceMatch.tenKPace;
      anchorSource = `race (${RACE_TYPE_LABEL[bestRaceMatch.race.raceType]})`;
      anchorWeeksAgo = bestRaceMatch.weeksAgo;
      chosenRace = bestRaceMatch.race;
    } else if (recentTrainingAnchor) {
      // DISPLACEMENT CAP (2026-07-16, mirrors Swift): a single parsed workout
      // may refine a stale race anchor, never replace it wholesale. Blend
      // 50/50 and cap the net result at 3% faster than the race-demonstrated
      // pace. chosenRace stays null (the training session is the fresh signal).
      const raceFloor = bestRaceMatch.tenKPace * 0.97;
      anchorPace = Math.max((bestRaceMatch.tenKPace + recentTrainingAnchor.equivalentTenKPace) / 2.0, raceFloor);
      anchorSource = `training (${recentTrainingAnchor.kind}) + race (${RACE_TYPE_LABEL[bestRaceMatch.race.raceType]})`;
      const d = parseDay(recentTrainingAnchor.date);
      if (d) anchorWeeksAgo = daysBetween(d, now) / 7.0;
    }
  } else if (recentTrainingAnchor) {
    // No usable race. EVIDENCE-FIRST (2026-07-16, mirrors Swift): a single
    // session must not swing the estimate wholesale — when a snapshot baseline
    // exists, blend 50/50 and floor at 3% faster than the baseline.
    if (baselinePace !== null) {
      const floor = baselinePace * 0.97;
      anchorPace = Math.max((baselinePace + recentTrainingAnchor.equivalentTenKPace) / 2.0, floor);
      anchorSource = `training (${recentTrainingAnchor.kind}) + fitness profile`;
    } else {
      anchorPace = recentTrainingAnchor.equivalentTenKPace;
      anchorSource = `training (${recentTrainingAnchor.kind})`;
    }
    const d = parseDay(recentTrainingAnchor.date);
    if (d) anchorWeeksAgo = daysBetween(d, now) / 7.0;
  } else if (plan && plan.status === "active" && plan.targetTimeSeconds > 0) {
    const goalPace = plan.targetTimeSeconds / plan.raceDistanceMiles;
    anchorPace = convertPace(goalPace, plan.raceDistanceKey, "tenK");
    anchorSource = "training plan";
  } else if (baselinePace !== null) {
    anchorPace = baselinePace;
    anchorSource = "fitness profile";
    if (chosenSnapshot) {
      const d = parseDay(chosenSnapshot.createdAt);
      if (d) anchorWeeksAgo = daysBetween(d, now) / 7.0;
    }
  }

  // ── Measure training stimulus since the anchor date ──
  const twoWeeksAgo = new Date(now.getTime() - 14 * 86_400_000);
  const fourWeeksAgo = new Date(now.getTime() - 28 * 86_400_000);
  let anchorDate = fourWeeksAgo;
  if (chosenRace) {
    const d = parseDay(chosenRace.date);
    if (d) anchorDate = d;
  }

  let recentMiles = 0;
  let priorMiles = 0;
  let recentRuns = 0;
  let priorRuns = 0;
  for (const w of workouts) {
    const d = parseDay(w.date);
    if (!d || d <= anchorDate) continue;
    if (d >= twoWeeksAgo) {
      recentMiles += w.distanceMiles;
      recentRuns += 1;
    } else if (d >= fourWeeksAgo) {
      priorMiles += w.distanceMiles;
      priorRuns += 1;
    }
  }

  const hardEffortTypes = new Set(["tempo", "threshold", "interval", "race_pace"]);
  let postRaceStimulusSeconds = 0;
  let recentStimulusSeconds = 0;
  let priorStimulusSeconds = 0;
  let structuredSessionCount = 0;

  for (const log of extendedVoiceLogs) {
    const d = parseDay(log.date) ?? now;
    if (d <= anchorDate) continue;
    const isRecent = d >= twoWeeksAgo;
    const isPrior = d >= fourWeeksAgo && d < twoWeeksAgo;

    const segments = log.paceSegments;
    if (segments && segments.length > 0) {
      let sessionHasStimulus = false;
      for (const seg of segments) {
        if (hardEffortTypes.has(seg.effort)) {
          postRaceStimulusSeconds += seg.durationSeconds;
          if (isRecent) recentStimulusSeconds += seg.durationSeconds;
          else if (isPrior) priorStimulusSeconds += seg.durationSeconds;
          sessionHasStimulus = true;
        }
      }
      if (sessionHasStimulus) structuredSessionCount += 1;
      continue;
    }
    // (Voice-log extractedWorkout interval/tempo stimulus is not reconstructed
    // server-side; parsed_structure + pace_segments carry the signal we have.)
  }

  const weeksSinceAnchor = Math.max(anchorWeeksAgo, 1.0);
  const weeklyStimulusMinutes = postRaceStimulusSeconds / 60.0 / weeksSinceAnchor;
  const stimulusMinutes = postRaceStimulusSeconds / 60.0;
  const weeklyMiles = (recentMiles + priorMiles) / Math.min(weeksSinceAnchor, 4.0);
  const runsPerWeek = (recentRuns + priorRuns) / Math.min(weeksSinceAnchor, 4.0);
  // EVIDENCE-FIRST TREND DEFAULTS (2026-07-16, mirrors Swift): when the prior
  // window is empty we have NO evidence of building — default to neutral 1.0,
  // never 2.0. The old 2.0 default trivially satisfied the build gate (>1.15)
  // and granted improvement credit off missing data.
  const volumeTrend = priorMiles > 0 ? recentMiles / priorMiles : recentMiles > 0 ? 1.0 : 0.0;
  const stimulusTrend = priorStimulusSeconds > 0 ? recentStimulusSeconds / priorStimulusSeconds : recentStimulusSeconds > 0 ? 1.0 : 0.0;
  void stimulusMinutes;
  void runsPerWeek;
  void structuredSessionCount;

  // ── Quality density (Part 2C — server-only) ──
  // Hard-effort miles per week over the last 4 weeks ÷ weekly miles (the
  // simpler variant sanctioned alongside quality-volume.ts — the MP-relative
  // definition there needs an MP anchor the model doesn't have yet). Laps win
  // over pace_segments on dates they cover (same dedup as the effort pool).
  // null when there's no mileage data — density effects engage only when the
  // data exists.
  // RELATIVE HARDNESS GATE (2026-07-16 hotfix): laps carry no effort labels,
  // so the absolute 210–540 s/mi window admitted EASY-run laps (a 7:20/mi
  // easy lap passes it) — the first live run dragged the estimate 17% slow.
  // Quality is a position in THIS athlete's range (quality-volume.ts): MP and
  // faster. MP pace ≈ 1.094 × 10K pace (ratio table) + 2% tolerance → a lap
  // counts as hard only when pace ≤ anchor 10K pace × 1.12. No anchor → no
  // relative gate is possible, so lap efforts are not used.
  const LAP_HARDNESS_FACTOR = 1.12;
  const lapHardnessCap = anchorPace !== null ? anchorPace * LAP_HARDNESS_FACTOR : null;
  // Laps only displace labeled pace_segments on dates where at least one lap
  // actually QUALIFIED as hard — an easy-lap-only date keeps its segments.
  const qualifyingLapDates = new Set(
    lapEfforts
      .filter((e) => lapHardnessCap !== null && e.paceSeconds <= lapHardnessCap)
      .map((e) => e.date),
  );
  let hardMiles28 = 0;
  for (const e of lapEfforts) {
    if (lapHardnessCap === null || e.paceSeconds > lapHardnessCap) continue;
    const d = parseDay(e.date);
    if (d && d >= fourWeeksAgo) hardMiles28 += e.distanceMiles;
  }
  for (const log of extendedVoiceLogs) {
    if (qualifyingLapDates.has(log.date)) continue;
    const d = parseDay(log.date);
    if (!d || d < fourWeeksAgo) continue;
    for (const seg of log.paceSegments ?? []) {
      if (hardEffortTypes.has(seg.effort) && seg.distanceMiles > 0.1) hardMiles28 += seg.distanceMiles;
    }
  }
  const qualityDensity: number | null = weeklyMiles > 0
    ? Math.max(0, Math.min(1, hardMiles28 / 4.0 / weeklyMiles))
    : null;

  let estimated10KPace = 0;
  let dataSource = "default";
  // Hard efforts seen in the training window — populated inside the anchor
  // block, consumed by the mile speed-evidence shading at assembly.
  let speedEvidenceHardEfforts: Array<{ paceSeconds: number; distanceMiles: number }> = [];
  // What the training signal read, and what it declined to read. Surfaced on
  // the prediction so the athlete can see which sessions are behind the number
  // rather than being handed a bare estimate.
  let zoneEstimates: ZoneEstimate[] = [];
  let zoneRejections: Array<{ date: string; reason: string }> = [];
  /** The subset combineZoneEstimates actually selected — the number's workings. */
  let zoneSignalUsed: ZoneEstimate[] = [];
  // Dates already spoken for by a detected race. A race is the anchor; letting
  // it back in as training evidence would count one performance twice.
  const racesInWindow = new Set(detected.map((r) => r.date));

  if (anchorPace !== null) {
    const anchor = anchorPace;
    const baseDecayPerWeek = 0.003;
    // Under ~6% quality density, aerobic-only training maintains less race
    // sharpness — treat weekly hard-stimulus minutes as capped at 60% of value
    // for the maintenance factor (Part 2C).
    const effectiveStimulusMinutes = qualityDensity !== null && qualityDensity < 0.06
      ? weeklyStimulusMinutes * 0.6
      : weeklyStimulusMinutes;
    const stimulusOffset = Math.min(effectiveStimulusMinutes / 50.0, 1.0);
    const volumeCredit = Math.min(weeklyMiles / 40.0, 1.0);
    let maintenanceFactor = stimulusOffset * 0.65 + volumeCredit * 0.35;
    // DENSITY FLOOR (2026-07-16): weeklyStimulusMinutes depends on effort
    // LABELS, which are sparse/unreliable on older logs — an athlete with a
    // 20-week-old race anchor and label-poor history read as "no quality since
    // the race" and got near-max decay. Quality density is measured from PACE
    // (label-free): let it floor the maintenance credit. Density ≥ 15% of
    // mileage at MP-or-faster is full training by any coaching standard.
    if (qualityDensity !== null) {
      maintenanceFactor = Math.max(maintenanceFactor, Math.min(qualityDensity * 6.0, 0.9));
    }
    let effectiveDecayPerWeek = baseDecayPerWeek * (1.0 - maintenanceFactor * 0.9);

    // BUILD GATE (2026-07-16, mirrors Swift): improvement credit requires REAL
    // prior-window data — an empty prior window is absence of evidence.
    if (
      volumeTrend > 1.15 && stimulusTrend > 1.0 && weeklyStimulusMinutes >= 30 &&
      priorMiles > 0 && priorStimulusSeconds > 0
    ) {
      const buildRate = Math.min((volumeTrend - 1.0) * 0.003, 0.002);
      effectiveDecayPerWeek -= buildRate;
    }
    if (volumeTrend < 0.5 && volumeTrend > 0) effectiveDecayPerWeek += 0.001;
    effectiveDecayPerWeek = Math.max(Math.min(effectiveDecayPerWeek, 0.004), -0.002);

    let decayFactor = 1.0 + anchorWeeksAgo * effectiveDecayPerWeek;
    // UNPROVEN-IMPROVEMENT CAP (2026-07-16, mirrors Swift): improvement
    // inferred from volume trends alone is capped at 0.5% TOTAL, no matter how
    // old the anchor. Proven improvement still arrives through the measured
    // hard-pace signal below.
    decayFactor = Math.max(decayFactor, 0.995);
    // CONTINUOUS-TRAINING DECAY CAP (2026-07-16): VO2 decay applies to
    // STOPPED training. An athlete with zero detraining evidence (volume held,
    // no layoff) does not drift 4-5% off a demonstrated race just because the
    // race aged — stimulus LABELS are too sparse on older logs to prove
    // otherwise. With no detraining signal, an anchor decays at most 2% total;
    // genuine decline still arrives through the detraining triggers.
    if (detectDetraining(workouts, voiceLogs, now) === null) {
      decayFactor = Math.min(decayFactor, 1.02);
    }
    estimated10KPace = anchor * decayFactor;

    // ── Training-evidence validation (parser-driven, last 28 days) ──
    //
    // REPLACED RIEGEL (2026-08-17). This block used to convert each hard effort
    // to a 10K equivalent by its own distance:
    //
    //     rep       → p · (10Kmi / d)^0.06      ← ×1.147 at 0.63 mi
    //     sustained → p · 0.975                  (LT → 10K)
    //
    // Riegel is a maximal-effort curve, so the "rep" branch asserted that every
    // interval was a time trial at its own length. On this athlete a 10×1K at
    // 5:18 came out as a 36:45 10K against a demonstrated ~31:50. A rep is not
    // a race: reps are run AT a prescribed pace — mile pace, 10K, LT — and only
    // a DECLARED race or time trial is near-maximal at its distance.
    //
    // The replacement reads what the parser already stored (`parsed_structure.
    // blocks`) and asks one question of the athlete's own pace/duration curve:
    // for the continuous work you actually did, how did your pace compare to
    // what your current fitness predicts for that duration? See
    // trainingZoneSignal.ts for the model and why the anchor cancels out of it.
    const zoneSessions: ParsedSession[] = [];
    for (const log of extendedVoiceLogs) {
      const d = parseDay(log.date);
      // 28 days, not 14: the signal takes the BEST sessions in the window, so
      // it needs enough of them to choose from. The 21-day recency half-life
      // inside combineZoneEstimates is what keeps the number current.
      if (!d || d < fourWeeksAgo || d > now) continue;
      const p = log.parsedStructure;
      if (!p || !p.blocks || p.blocks.length === 0) continue;
      zoneSessions.push({
        date: log.date,
        type: p.type,
        confidence: p.confidence,
        intentPattern: p.intentPattern ?? null,
        tempF: log.weather?.tempF ?? null,
        dewPointF: log.weather?.dewPointF ?? null,
        blocks: p.blocks,
        // A race in the window is already the anchor; counting it again here
        // would let one performance vote twice.
        declaredRace: racesInWindow.has(log.date),
      });
    }
    const zoneRead = estimateFromSessions(zoneSessions, estimated10KPace);
    zoneEstimates = zoneRead.estimates;
    zoneRejections = zoneRead.rejected;
    // Feed the mile prediction's speed-evidence test from the same reps.
    speedEvidenceHardEfforts = zoneEstimates.flatMap((e) =>
      e.reps.map((r) => ({ paceSeconds: r.paceSeconds, distanceMiles: r.distanceMiles }))
    );

    const zoneSignal = combineZoneEstimates(zoneEstimates, now);
    let paceSegmentSignal: number | null = null;
    if (zoneSignal !== null) {
      zoneSignalUsed = zoneSignal.used;
      paceSegmentSignal = zoneSignal.tenKPace;
      const diff = paceSegmentSignal - estimated10KPace;
      if (Math.abs(diff) > 3) {
        // WEIGHT: how much work stands behind the signal. 25% floor so a thin
        // week still registers, 60% ceiling so training never fully overwrites
        // a raced anchor in a single night.
        let signalWeight = Math.min(0.6, Math.max(0.25, zoneSignal.workMinutes / 240));
        // An ageing anchor earns training more say. A race from last month is
        // still the better measurement; a race from last spring is history.
        if (anchorWeeksAgo > 8) signalWeight = Math.min(0.75, signalWeight * 1.25);
        const blended = estimated10KPace * (1.0 - signalWeight) + paceSegmentSignal * signalWeight;

        // DISPLACEMENT CAP, scaled by anchor age — the honest successor to the
        // old flat ±2% band. That band was set when the training signal was
        // Riegel-inflated and could not be trusted at all, so it clamped every
        // session to invisibility: flat, flat, flat, then a jump when the
        // anchor moved. Now the signal is sound, so the cap does one narrower
        // job — stop a fortnight of workouts from overturning a RECENT race,
        // while letting training speak as that race recedes.
        const capPct = anchorWeeksAgo <= 2
          ? 0.015 // a race this fresh is the better measurement, full stop
          : Math.min(0.06, 0.015 + (anchorWeeksAgo - 2) * 0.0045);
        estimated10KPace = Math.min(
          Math.max(blended, estimated10KPace * (1 - capPct)),
          estimated10KPace * (1 + capPct),
        );
      }
    }

    if (effectiveDecayPerWeek < 0) dataSource = anchorSource + " (improving)";
    else if (effectiveDecayPerWeek < 0.001) dataSource = anchorSource + " (maintaining)";
    else dataSource = anchorSource;
    // Named for what it now is. The old " + pace segments" label outlived the
    // pace_segments input by a release; `fitnessCurve.isOwnSnapshot` keys off
    // the "· v2" marker, not this text, so renaming it is safe.
    if (paceSegmentSignal !== null) {
      dataSource += ` + training (${zoneSignalUsed.length} session${zoneSignalUsed.length === 1 ? "" : "s"})`;
    }
  }

  // ── Fallback when no anchor: structured/voice/fastest-workout ──
  if (estimated10KPace === 0) {
    const intervals = intervalPaces.filter((i) => i.type === "interval");
    const tempos = intervalPaces.filter((i) => i.type === "tempo" || i.type === "threshold");
    let trainingSignal: number | null = null;
    let trainingSource = "";
    if (intervals.length > 0) {
      trainingSignal = (intervals.reduce((s, i) => s + i.pace, 0) / intervals.length) * 1.04;
      trainingSource = `intervals (${intervals.length} sets)`;
    } else if (tempos.length > 0) {
      trainingSignal = (tempos.reduce((s, i) => s + i.pace, 0) / tempos.length) * 0.97;
      trainingSource = `tempo (${tempos.length} efforts)`;
    } else if (voicePaces.length > 0) {
      trainingSignal = (voicePaces.reduce((s, v) => s + v, 0) / voicePaces.length) * 0.97;
      trainingSource = "voice log paces";
    }
    if (trainingSignal !== null) {
      estimated10KPace = trainingSignal;
      dataSource = trainingSource;
    } else if (workouts.length > 0) {
      const fastest = workouts.reduce((f, w) => (w.paceSecondsPerMile < f.paceSecondsPerMile ? w : f), workouts[0]);
      estimated10KPace = fastest.paceSecondsPerMile * 0.95;
      dataSource = "fastest workout";
    }
  }

  if (!(estimated10KPace > 0)) return null; // no usable signal → no fabricated row

  // ── Damp the curve (2026-08-16) ────────────────────────────────────────
  // Everything above re-derives from a rolling 14-day window, so the raw
  // estimate moves as sessions age in and out — 32:00 and 33:44 landed hours
  // apart on 2026-08-15. Fitness is an accumulation: a session is evidence,
  // not a measurement. Move a fraction of the way toward it instead of
  // jumping. A DECLARED race resets outright; that is a measurement.
  //
  // This is the honest version of "build on the last snapshot". The ratchet
  // the anti-ratchet comment warns about compounds the OUTPUT; this
  // accumulates EVIDENCE with exponential decay, so a flattering day is
  // outvoted by the fortnight around it and then forgotten.
  const prior = mostRecentPrior(priorSnapshots, now);
  const curve = smoothFitnessPace({
    rawPace: estimated10KPace,
    priorPace: prior?.pace ?? null,
    deltaDays: prior?.deltaDays ?? 0,
    // A race inside the recent window is a fresh measurement — let it land.
    hardReset: chosenRace !== null && anchorWeeksAgo <= 2.0,
  });
  estimated10KPace = curve.pace;

  // ── Derive race times from estimated 10K pace ──
  // ROUND, don't truncate (2026-07-16, mirrors Swift) — Math.trunc floored
  // every prediction fast twice.
  const tenKSeconds = Math.round(estimated10KPace * TEN_K_MILES);
  const raceTime = (to: RaceType): number =>
    Math.round(equivalentRaceTimeSeconds("tenK", tenKSeconds, RACE_TYPE_TO_KEY[to]));

  const structuredIntervalCount = intervalPaces.filter((i) => i.type === "interval").length;
  const structuredTempoCount = intervalPaces.filter((i) => i.type === "tempo" || i.type === "threshold").length;

  let tier: ConfidenceTier;
  let confidence: string;
  let summary: string;
  if (chosenRace) {
    // AGE-AWARE TIER (2026-07-16, mirrors Swift): a race is high-confidence
    // proof for ~16 weeks. Past that it's still the best anchor we have, but
    // the certainty is gone — medium tier, wider ranges.
    tier = anchorWeeksAgo <= racePrimaryWindowWeeks ? "high" : "medium";
    confidence = tier === "high" ? "High" : "Medium";
    const raceTimeStr = formatTime(chosenRace.totalTimeSeconds);
    summary = anchorWeeksAgo <= racePrimaryWindowWeeks
      ? `Based on your ${RACE_TYPE_LABEL[chosenRace.raceType]} race (${raceTimeStr}).`
      : `Based on your ${RACE_TYPE_LABEL[chosenRace.raceType]} race (${raceTimeStr}) — ${Math.trunc(anchorWeeksAgo)} weeks ago, so ranges are wider.`;
  } else if (anchorPace !== null) {
    tier = "medium";
    confidence = "Medium";
    summary = `Based on your ${anchorSource}.`;
  } else if (structuredIntervalCount > 0 || structuredTempoCount > 0) {
    tier = "medium";
    confidence = "Medium";
    summary = "Based on structured workout data from your training logs.";
  } else if (dataSource.includes("training plan")) {
    tier = "medium";
    confidence = "Medium";
    summary = "Based on your training-plan goal. Log workouts and voice notes for more precise predictions.";
  } else if (dataSource.includes("fitness profile")) {
    tier = "medium";
    confidence = "Medium";
    summary = "Based on your previous fitness profile. Log a hard workout or race for a fresh assessment.";
  } else if (workouts.length === 0 && voiceLogs.length === 0) {
    tier = "low";
    confidence = "Low";
    summary = "Sample predictions shown. Log runs via HealthKit or voice notes to get personalized race times.";
  } else {
    tier = "low";
    confidence = "Low";
    summary = `Based on ${workouts.length} workouts from the last 30 days. Log a hard effort or race for better accuracy.`;
  }

  // ── Speed evidence & endurance shading (2026-07-16, mirrors Swift) ──
  // 1. MILE: the VDOT-steep mile ratio assumes trained speed. Without recent
  //    evidence of running at ≤5K-equivalent pace, shade toward Riegel-1.06
  //    (0.14434 of the 10K time). Evidence = ≥1.5 mi of last-14-day hard
  //    efforts at ≤ 5K-equivalent pace.
  // 2. MARATHON: equivalence tables assume marathon-ready volume. Below
  //    40 mi/wk scale up to +6% at zero volume.
  const fiveKEquivalentPace = estimated10KPace * 0.966; // 5K pace ≈ 96.6% of 10K pace (ratio table)
  const speedEvidenceMiles = speedEvidenceHardEfforts
    .filter((e) => e.paceSeconds <= fiveKEquivalentPace)
    .reduce((s, e) => s + e.distanceMiles, 0);
  // RACE-HISTORY SPEED EVIDENCE (2026-07-17): a confirmed race at 5K or
  // shorter within the last 2 years is proof of trained speed — the athlete
  // has raced fast even if the last 14 days were all endurance work. It firms
  // the mile toward the VDOT ratio; it never anchors current fitness.
  const hasRaceSpeedHistory = (input.seededRaces ?? []).some((r) => {
    if (r.raceType !== "mile" && r.raceType !== "fiveK") return false;
    const d = parseDay(r.date);
    return d !== null && daysBetween(d, now) / 7.0 <= 104;
  });
  const hasSpeedEvidence = speedEvidenceMiles >= 1.5 || hasRaceSpeedHistory;

  const mileVDOT = raceTime("mile");
  const mileRiegel = tenKSeconds * 0.14434; // Riegel-1.06: (1 / 6.21371)^1.06
  const mileSeconds = hasSpeedEvidence ? mileVDOT : Math.round((mileVDOT + mileRiegel) / 2.0);

  // ── Long-run endurance shading (2026-07-24, v2) ──
  // The marathon/half equivalence assumes the athlete can HOLD the pace over
  // the distance. Weekly mileage alone can't prove that (high volume from
  // short runs doesn't build 26.2-mile durability), so we shade the point
  // estimate up from the athlete's longest recent long runs. Weekly mileage
  // is kept as a floor — the stronger of the two penalties wins. Skipped when
  // the anchor is a demonstrated race at that distance or longer.
  const { longestMiles: longestLongRun, count16: longRunCount16 } = longRunReadiness(extendedWorkouts, now);
  const marathonEnduranceFactor = enduranceFactor(
    longestLongRun,
    longRunCount16,
    MARA_READY_LONGRUN_MILES,
    MARA_READY_LONGRUN_COUNT,
    MARA_MAX_ENDURANCE_PENALTY,
  );
  const halfEnduranceFactor = enduranceFactor(
    longestLongRun,
    longRunCount16,
    HALF_READY_LONGRUN_MILES,
    MARA_READY_LONGRUN_COUNT,
    HALF_MAX_ENDURANCE_PENALTY,
  );

  let marathonSecondsD: number = raceTime("marathon");
  const marathonVolumeFactor = weeklyMiles >= 40.0 ? 1.0 : 1.0 + ((40.0 - Math.max(weeklyMiles, 0)) / 40.0) * 0.06;
  if (chosenRace?.raceType !== "marathon") {
    // Stronger of the volume floor and the long-run endurance shade.
    marathonSecondsD *= Math.max(marathonVolumeFactor, marathonEnduranceFactor);
  }
  const marathonSeconds = Math.round(marathonSecondsD);

  const fiveKSeconds = raceTime("fiveK");
  let halfSecondsD: number = raceTime("half");
  // A demonstrated half or marathon race anchor already proves the endurance.
  if (chosenRace?.raceType !== "half" && chosenRace?.raceType !== "marathon") {
    halfSecondsD *= halfEnduranceFactor;
  }
  const halfSeconds = Math.round(halfSecondsD);

  // ── Distance-aware ranges (2026-07-16, mirrors Swift) ──
  // A flat ±% per tier claimed the same certainty for a mile predicted off a
  // half marathon as for the half itself. Ranges widen with:
  //   • distance from the anchor race (0.8% per doubling/halving),
  //   • anchor age (up to +1%),
  //   • missing speed evidence (mile only, +1%),
  //   • thin volume (marathon only, +1% below 30 mi/wk),
  //   • thin quality density (marathon only, +1% below 5% — server-only).
  const anchorMiles: number = chosenRace ? RACE_TYPE_MILES[chosenRace.raceType] : TEN_K_MILES;
  const ageWidening = Math.min(anchorWeeksAgo * 0.0004, 0.01);
  const rangeFraction = (distMiles: number, extra = 0): number =>
    Math.min(RANGE_FRACTION[tier] + Math.abs(Math.log2(distMiles / anchorMiles)) * 0.008 + ageWidening + extra, 0.07);

  const mileExtra = hasSpeedEvidence ? 0 : 0.01;
  const marathonExtra = (weeklyMiles < 30.0 ? 0.01 : 0) +
    (qualityDensity !== null && qualityDensity < 0.05 ? 0.01 : 0);

  // "· v2" marks the richer multi-signal server model for the iOS client.
  dataSource = `${dataSource} · v2`;

  // Lifetime PRs — fastest confirmed finish per distance, any age (2026-07-17).
  // Context for the athlete + speed evidence above; never a fitness anchor.
  const lifetimePRs: FitnessPredictionResult["lifetimePRs"] = {};
  for (const r of input.seededRaces ?? []) {
    const existing = lifetimePRs[r.raceType];
    if (!existing || r.totalTimeSeconds < existing.timeSeconds) {
      lifetimePRs[r.raceType] = { timeSeconds: r.totalTimeSeconds, date: r.date };
    }
  }

  return {
    estimated10kPaceSeconds: estimated10KPace,
    predictedMileSeconds: mileSeconds,
    predicted5kSeconds: fiveKSeconds,
    predicted10kSeconds: tenKSeconds,
    predictedHalfSeconds: halfSeconds,
    predictedMarathonSeconds: marathonSeconds,
    confidence,
    confidenceTier: tier,
    dataSource,
    workoutCount: workouts.length,
    rangeMileSeconds: Math.round(mileSeconds * rangeFraction(RANGE_ITEM_MILES.mile, mileExtra)),
    range5kSeconds: Math.round(fiveKSeconds * rangeFraction(RANGE_ITEM_MILES.fiveK)),
    range10kSeconds: Math.round(tenKSeconds * rangeFraction(RANGE_ITEM_MILES.tenK)),
    rangeHalfSeconds: Math.round(halfSeconds * rangeFraction(RANGE_ITEM_MILES.half)),
    rangeMarathonSeconds: Math.round(marathonSeconds * rangeFraction(RANGE_ITEM_MILES.marathon, marathonExtra)),
    summary,
    lifetimePRs,
    supportingTraining: {
      used: zoneSignalUsed,
      readButNotUsed: zoneRejections,
      workMinutes: Math.round(zoneSignalUsed.reduce((s, e) => s + e.workSeconds, 0) / 60),
    },
  };
}

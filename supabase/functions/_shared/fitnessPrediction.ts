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
}

/** A voice log / check-in row (the qualitative + parsed side of training_logs). */
export interface VoiceLogInput {
  date: string; // "yyyy-MM-dd"
  notes: string;
  pacesMentioned?: string[];
  paceSegments?: PaceSegmentInput[] | null;
  parsedStructure?: ParsedStructureInput | null;
}

/** A prior fitness_snapshots row (for the decay-gated baseline fallback). */
export interface PriorSnapshotInput {
  createdAt: string; // ISO timestamp
  estimated10kPaceSeconds: number;
  confidence: string; // "High" | "Medium" | "Low"
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
const RACE_TYPE_TOLERANCE: Record<RaceType, number> = {
  mile: 0.08,
  fiveK: 0.2,
  tenK: 0.4,
  half: 0.5,
  marathon: 1.0,
};

// RaceType → the human label iOS uses (RaceType.rawValue), so the stored
// `data_source` / summary strings match the app exactly.
const RACE_TYPE_LABEL: Record<RaceType, string> = {
  mile: "Mile",
  fiveK: "5K",
  tenK: "10K",
  half: "Half Marathon",
  marathon: "Marathon",
};

// ConfidenceTier.rangeFraction — half-window as a fraction of the point.
const RANGE_FRACTION: Record<ConfidenceTier, number> = {
  high: 0.015,
  medium: 0.03,
  low: 0.05,
};

// iOS uses this exact constant for 10K miles when deriving tenKSeconds.
const TEN_K_MILES = 6.21371;

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

// ---------------------------------------------------------------------------
// detectTrainingAnchors — Observer parsed_structure only (segment fallback
// deliberately disabled in the iOS source; see its comment).
// ---------------------------------------------------------------------------

export function detectTrainingAnchors(voiceLogs: VoiceLogInput[]): TrainingAnchor[] {
  const anchors: TrainingAnchor[] = [];

  for (const log of voiceLogs) {
    const parsed = log.parsedStructure;
    if (!parsed || parsed.confidence < 0.6 || !parsed.equivalentRacePace) continue;

    const paceSec = paceStringToSeconds(parsed.equivalentRacePace.pacePerMile);
    if (paceSec <= 0) continue;

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
  const baselineMilesPerWeek = baselineMiles / 4.0;
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

export function generateFitnessPrediction(input: PredictionInput): FitnessPredictionResult | null {
  const now = input.now ?? new Date();
  const workouts = input.workouts ?? [];
  const voiceLogs = input.voiceLogs ?? [];
  const extendedWorkouts = input.extendedWorkouts && input.extendedWorkouts.length > 0 ? input.extendedWorkouts : workouts;
  const extendedVoiceLogs = input.extendedVoiceLogs && input.extendedVoiceLogs.length > 0 ? input.extendedVoiceLogs : voiceLogs;
  const priorSnapshots = input.priorSnapshots ?? [];
  const plan = input.plan ?? null;

  const detected = detectRaces(extendedWorkouts, extendedVoiceLogs);
  // Merge confirmed_races (deduped by raceType+date), preferring the detected
  // entry when both exist.
  const detectedRaces = [...detected];
  for (const seed of input.seededRaces ?? []) {
    if (!detectedRaces.some((r) => r.raceType === seed.raceType && r.date === seed.date)) {
      detectedRaces.push(seed);
    }
  }

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
  let baselinePace: number | null = null;
  const sixteenWeeksAgo = new Date(now.getTime() - 112 * 86_400_000);
  const inWindowSnaps = priorSnapshots.filter((s) => {
    const d = parseDay(s.createdAt);
    return d !== null && d >= sixteenWeeksAgo && (s.confidence === "High" || s.confidence === "Medium");
  });
  const bestSnapshot = inWindowSnaps.reduce<PriorSnapshotInput | null>(
    (best, s) => (best === null || s.estimated10kPaceSeconds < best.estimated10kPaceSeconds ? s : best),
    null,
  );
  if (bestSnapshot) {
    const snapDate = parseDay(bestSnapshot.createdAt)!;
    const weeksAgo = daysBetween(snapDate, now) / 7.0;
    const detraining = detectDetraining(workouts, voiceLogs, now);
    const decayPerWeek = detraining ? 0.003 * detraining.severity : 0.0;
    baselinePace = bestSnapshot.estimated10kPaceSeconds * (1.0 + weeksAgo * decayPerWeek);
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
      const tenK = convertPace(race.paceSecondsPerMile, race.raceType, "tenK");
      return { race, weeksAgo: weeks, tenKPace: tenK };
    })
    .filter((x): x is { race: DetectedRace; weeksAgo: number; tenKPace: number } => x !== null);

  const bestRaceMatch = scoredRaces.reduce<{ race: DetectedRace; weeksAgo: number; tenKPace: number } | null>(
    (best, r) => (best === null || r.tenKPace < best.tenKPace ? r : best),
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
      anchorPace = recentTrainingAnchor.equivalentTenKPace;
      anchorSource = `training (${recentTrainingAnchor.kind})`;
      const d = parseDay(recentTrainingAnchor.date);
      if (d) anchorWeeksAgo = daysBetween(d, now) / 7.0;
    }
  } else if (recentTrainingAnchor) {
    anchorPace = recentTrainingAnchor.equivalentTenKPace;
    anchorSource = `training (${recentTrainingAnchor.kind})`;
    const d = parseDay(recentTrainingAnchor.date);
    if (d) anchorWeeksAgo = daysBetween(d, now) / 7.0;
  } else if (plan && plan.status === "active" && plan.targetTimeSeconds > 0) {
    const goalPace = plan.targetTimeSeconds / plan.raceDistanceMiles;
    anchorPace = convertPace(goalPace, plan.raceDistanceKey, "tenK");
    anchorSource = "training plan";
  } else if (baselinePace !== null) {
    anchorPace = baselinePace;
    anchorSource = "fitness profile";
    if (bestSnapshot) {
      const d = parseDay(bestSnapshot.createdAt);
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
  const volumeTrend = priorMiles > 0 ? recentMiles / priorMiles : recentMiles > 0 ? 2.0 : 0.0;
  const stimulusTrend = priorStimulusSeconds > 0 ? recentStimulusSeconds / priorStimulusSeconds : recentStimulusSeconds > 0 ? 2.0 : 0.0;
  void stimulusMinutes;
  void runsPerWeek;
  void structuredSessionCount;

  let estimated10KPace = 0;
  let dataSource = "default";

  if (anchorPace !== null) {
    const anchor = anchorPace;
    const baseDecayPerWeek = 0.003;
    const stimulusOffset = Math.min(weeklyStimulusMinutes / 50.0, 1.0);
    const volumeCredit = Math.min(weeklyMiles / 40.0, 1.0);
    const maintenanceFactor = stimulusOffset * 0.65 + volumeCredit * 0.35;
    let effectiveDecayPerWeek = baseDecayPerWeek * (1.0 - maintenanceFactor * 0.9);

    if (volumeTrend > 1.15 && stimulusTrend > 1.0 && weeklyStimulusMinutes >= 30) {
      const buildRate = Math.min((volumeTrend - 1.0) * 0.003, 0.002);
      effectiveDecayPerWeek -= buildRate;
    }
    if (volumeTrend < 0.5 && volumeTrend > 0) effectiveDecayPerWeek += 0.001;
    effectiveDecayPerWeek = Math.max(Math.min(effectiveDecayPerWeek, 0.004), -0.002);

    estimated10KPace = anchor * (1.0 + anchorWeeksAgo * effectiveDecayPerWeek);

    // ── Pace-segment validation (last 14 days of hard efforts) ──
    const recentHardEfforts: Array<{ paceSeconds: number; distanceMiles: number }> = [];
    for (const log of extendedVoiceLogs) {
      const d = parseDay(log.date) ?? now;
      if (d < twoWeeksAgo) continue;
      const segments = log.paceSegments;
      if (!segments) continue;
      for (const seg of segments) {
        if (!hardEffortTypes.has(seg.effort)) continue;
        if (seg.distanceMiles <= 0.1) continue;
        const parts = seg.pacePerMile.split(":").map(Number).filter((n) => Number.isFinite(n));
        if (parts.length === 2) {
          const paceSeconds = parts[0] * 60 + parts[1];
          if (paceSeconds >= 210 && paceSeconds <= 540) {
            recentHardEfforts.push({ paceSeconds, distanceMiles: seg.distanceMiles });
          }
        }
      }
    }
    for (const ip of intervalPaces) {
      if (ip.pace >= 210 && ip.pace <= 540) {
        recentHardEfforts.push({ paceSeconds: ip.pace, distanceMiles: ip.type === "interval" ? 0.5 : 2.0 });
      }
    }
    const totalHardMiles = recentHardEfforts.reduce((s, e) => s + e.distanceMiles, 0);
    let paceSegmentSignal: number | null = null;
    if (totalHardMiles >= 4.0 && recentHardEfforts.length >= 3) {
      const weightedPaceSum = recentHardEfforts.reduce((s, e) => s + e.paceSeconds * e.distanceMiles, 0);
      const weightedAvgPace = weightedPaceSum / totalHardMiles;
      paceSegmentSignal = weightedAvgPace * 1.06;
      const diff = paceSegmentSignal - estimated10KPace;
      if (Math.abs(diff) > 5) {
        const signalWeight = Math.min(0.3 + (totalHardMiles - 4.0) * 0.05, 0.5);
        estimated10KPace = estimated10KPace * (1.0 - signalWeight) + paceSegmentSignal * signalWeight;
      }
    }

    if (effectiveDecayPerWeek < 0) dataSource = anchorSource + " (improving)";
    else if (effectiveDecayPerWeek < 0.001) dataSource = anchorSource + " (maintaining)";
    else dataSource = anchorSource;
    if (paceSegmentSignal !== null) dataSource += " + pace segments";
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

  // ── Derive race times from estimated 10K pace ──
  const tenKSeconds = Math.trunc(estimated10KPace * TEN_K_MILES);
  const raceTime = (to: RaceType): number =>
    Math.trunc(equivalentRaceTimeSeconds("tenK", tenKSeconds, RACE_TYPE_TO_KEY[to]));

  const structuredIntervalCount = intervalPaces.filter((i) => i.type === "interval").length;
  const structuredTempoCount = intervalPaces.filter((i) => i.type === "tempo" || i.type === "threshold").length;

  let tier: ConfidenceTier;
  let confidence: string;
  let summary: string;
  if (chosenRace) {
    tier = "high";
    confidence = "High";
    summary = `Based on your ${RACE_TYPE_LABEL[chosenRace.raceType]} race (${formatTime(chosenRace.totalTimeSeconds)}).`;
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

  const frac = RANGE_FRACTION[tier];
  const mileSeconds = raceTime("mile");
  const fiveKSeconds = raceTime("fiveK");
  const halfSeconds = raceTime("half");
  const marathonSeconds = raceTime("marathon");

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
    rangeMileSeconds: Math.trunc(mileSeconds * frac),
    range5kSeconds: Math.trunc(fiveKSeconds * frac),
    range10kSeconds: Math.trunc(tenKSeconds * frac),
    rangeHalfSeconds: Math.trunc(halfSeconds * frac),
    rangeMarathonSeconds: Math.trunc(marathonSeconds * frac),
    summary,
  };
}

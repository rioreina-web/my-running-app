// ============================================================================
// Workout comparison — Layer 1 (deterministic feature-diff; math, never AI)
//
// Spec: workoutcomparisonspec.md ("The Effort" comparison tool, Trends).
// Decompose each workout into typed segments (via the canonical
// `workoutSegmentation.ts`), compare like segment to like segment, and emit
// a structured, auditable diff plus a comparability score. NO language model
// touches these numbers — Layer 2 (the AI verdict) may only narrate facts
// present in this module's output, and the edge function enforces that.
//
// Design invariants (mirroring keySessions.ts / CLAUDE.md discipline):
//   • Compare at the EFFORT-ZONE level, not the exact-structure level.
//     A 10×1K and a 6×800m are both threshold work; we compare their
//     threshold bouts, not their rep schemes.
//   • Manual mode never refuses on a mismatch — it renders the diff and
//     lets the comparability score/confidence say how loosely to read it.
//     The only hard refusal is an unreadable session (no laps / no
//     classifiable work bouts): "couldn't read this session's structure".
//   • Heat adjustment is a model, not a measurement: raw pace is always
//     present; the adjusted pace rides alongside (per-lap heat snapshot,
//     same ratio approach as keySessions.ts). Grade adjustment needs
//     per-second streams and is NOT computed here in beta — never faked.
//   • Degrade honestly: every unavailable metric lands in `unavailable`
//     with a reason, never a guessed number.
//
// Decisions (Rio, 2026-07-20):
//   • "Full confidence" = same dominant work zone AND same workout family
//     AND quality volume within the band (spec open decision #2).
//   • Verdict shape = one sentence + at most one caveat (open decision #3)
//     — that lives in the Layer-2 prompt, not here.
//
// Pure functions, no I/O. See workoutComparison.test.ts.
// ============================================================================

import {
  fmtPace,
  segmentFromLaps,
  type Bout,
  type LapInput,
  type PaceZones,
  type SegmentationResult,
  type WorkoutKind,
  type Zone,
} from "./workoutSegmentation.ts";
import {
  densityFromBouts,
  describeDensityDiff,
  gradeFactor,
  type DensityProfile,
} from "./effortModel.ts";
import { assessHeatRisk, describeHeatRisk, type HeatRisk } from "./heat-risk.ts";
import { compositeScore } from "./pace-heat-adjustment.ts";

const METERS_PER_MILE = 1609.344;

// ── Tunable constants (documented defaults; see spec §matching model) ──

/** Volume ratio (smaller/larger total run distance) at or above which the pair
 *  is "within the band" — 8×1K vs 10×1K (0.8) passes; 4×1K vs 12×1K (0.33) does
 *  not. Below the band the volume component degrades linearly to 0 at
 *  `VOLUME_RATIO_FLOOR`. The band rides on TOTAL run distance (present for every
 *  session, quality or aerobic), not quality-work distance — so a 12mi long run
 *  and a 6mi long run read as "quite different volumes", as they should. */
export const VOLUME_BAND_RATIO = 0.7;
export const VOLUME_RATIO_FLOOR = 0.35;

/** Pace proximity (sec/mile): pairs whose overall pace is within this many
 *  seconds score full pace credit; credit decays linearly to 0 at
 *  `PACE_PROXIMITY_FLOOR_SEC`. Anchors the "same effort, not just same shape"
 *  read — two easy runs 8s/mi apart are the same session; 90s/mi apart are a
 *  recovery jog vs. a steady run. */
export const PACE_PROXIMITY_FULL_SEC = 15;
export const PACE_PROXIMITY_FLOOR_SEC = 90;

/** Recency: pairs within this many days score full phase/recency credit
 *  (both plausibly in the same training phase); credit decays linearly to 0
 *  at `RECENCY_FLOOR_DAYS`. A true phase tag (base/build/taper) isn't stored
 *  yet, so recency is the honest proxy — documented, not hidden. */
export const RECENCY_FULL_DAYS = 56;
export const RECENCY_FLOOR_DAYS = 180;

/** Minimum comparability score for the app to AUTO-suggest a pair (manual
 *  mode has no floor by design). Auto-suggest additionally requires a
 *  dominant-zone match — the spec's hard requirement. */
export const AUTO_SUGGEST_MIN_SCORE = 0.6;

/** Component weights of the comparability score. Sum = 1. The five athlete-
 *  facing signals (2026-07-20, Rio: "workout type, distance, pace, volume,
 *  structure") map onto these: type → zone+family, distance/volume → volume,
 *  pace → pace, structure → a ranking tie-break (not a weighted term, so a
 *  labeled/unlabeled session isn't penalized on the score itself). */
export const COMPARABILITY_WEIGHTS = {
  zone: 0.35, // same dominant zone — the "kind of effort" gate
  family: 0.15, // same workout family (easy/long/recovery, threshold/tempo, …)
  volume: 0.2, // similar total run distance
  pace: 0.15, // similar overall pace
  recency: 0.075, // similar phase, proxied by days apart
  data: 0.075, // clean segment + HR data on both sides
} as const;

/** High-confidence score floor (on top of the zone+family+volume gates). */
export const HIGH_CONFIDENCE_MIN_SCORE = 0.75;
/** Moderate-confidence floor (zone match still required). */
export const MODERATE_CONFIDENCE_MIN_SCORE = 0.5;

// ── Input shapes ──

/** Lap row: segmentation `LapInput` + the heat snapshot columns from
 *  `20260528222217_add_heat_adjusted_pace_to_laps.sql` (same superset
 *  keySessions.ts reads). */
export interface ComparisonLap extends LapInput {
  heat_adjusted_pace_sec_per_mile?: number | null;
  heat_category?: string | null;
  total_elevation_gain?: number | null; // meters climbed in the lap
}

/** The slice of `training_logs.weather_actual` this module reads. */
export interface ComparisonWeather {
  temp_f?: number | null;
  dew_point_f?: number | null;
  heat_category?: string | null;
}

export interface ComparisonWorkout {
  id: string;
  workout_date: string; // ISO date or datetime
  laps: ComparisonLap[];
  weather?: ComparisonWeather | null;
  /** Optional display label from `workout_features.workout_structure`. */
  structure_label?: string | null;
}

// ── Per-workout work profile ──

export type UnreadableReason = "no_laps" | "no_run_bouts";

/** "quality" = has classifiable work bouts (intervals/threshold/tempo/…), read
 *  by rep. "aerobic" = a steady run (easy/long/recovery/moderate/steady) with
 *  no work bouts, read whole-run. The mode picks which metric family the diff
 *  emphasizes; whole-run metrics (distance/duration/pace/HR) exist for both. */
export type ComparisonMode = "quality" | "aerobic";

/** One lap's worth of the run, cumulative — the chart series. */
export interface SeriesPoint {
  mi: number; // cumulative miles at the END of this lap
  paceSec: number; // lap pace, sec/mile
  hr: number | null; // lap avg HR
  gradePct: number | null; // lap average grade, %
}

export interface WorkProfile {
  id: string;
  date: string; // "YYYY-MM-DD"
  readable: boolean;
  unreadableReason: UnreadableReason | null;
  mode: ComparisonMode;
  workoutKind: WorkoutKind | null;
  /** Human structure label — features string when supplied, else the
   *  segmentation-derived one. */
  structure: string | null;
  /** Dominant zone: the top work zone in quality mode, the top overall zone in
   *  aerobic mode. Drives the type-match gate either way. */
  dominantWorkZone: Zone | null;
  // ── Whole-run metrics (present for EVERY readable session, both modes) ──
  totalDistanceMeters: number;
  totalDurationSec: number;
  avgPaceSec: number | null; // overall pace, sec/mile (duration / distance)
  avgRunHr: number | null; // time-weighted HR over the whole run
  /** Aerobic decoupling: percent efficiency (speed/HR) lost from the first half
   *  to the second. + = drifted (heart climbed / pace faded); null without HR
   *  on both halves. The long-run fitness signal. */
  decouplingPct: number | null;
  /** Conditions-adjusted pace (MODEL): raw pace corrected for heat (from the
   *  per-lap heat snapshot) and grade (from per-lap elevation gain), so a
   *  hotter/hillier run is judged on effort, not clock. Null without the inputs. */
  conditionsAdjustedPaceSec: number | null;
  totalElevationGainM: number; // total climb, meters (context)
  /** The fast portion of the run: distance-weighted pace of the quickest ~third
   *  of running distance, and how much of it. Null when the run is too uniform
   *  to have a "fast bit". */
  fastSegPaceSec: number | null;
  fastSegDistanceMeters: number;
  /** Per-lap series for the drift chart: cumulative miles → pace + HR + grade.
   *  Compact; iOS derives efficiency (speed/HR) for the decoupling curve. */
  series: SeriesPoint[];
  // ── Quality-work metrics (populated in quality mode; null/0 in aerobic) ──
  repCount: number;
  /** Rounded label of the typical rep ("1K", "800m", "2mi") — null when reps
   *  vary too much to summarize honestly. */
  repDistanceLabel: string | null;
  avgRepPaceRawSec: number | null; // sec/mile, distance-weighted, dominant zone
  avgRepPaceAdjSec: number | null; // heat-adjusted twin; null when no heat data
  heatCategory: string | null;
  fadePct: number | null; // first→last rep pace change, + = faded
  avgRecoverySec: number | null; // mean rest-bout seconds between work bouts
  recoveryHrDropBpm: number | null; // mean (work-bout HR − following rest HR)
  avgWorkHr: number | null; // time-weighted over dominant-zone work bouts
  qualityVolumeMeters: number; // dominant-zone work distance
  qualityVolumeSeconds: number; // dominant-zone work time
  tempF: number | null;
  /** Dew point, F. The heat model's actual driver — `tempF` alone can't tell a
   *  75F-dew slog from a dry morning at the same temperature. */
  dewPointF: number | null;
  /** WBGT risk read. Separate model, separate question — see heat-risk.ts. */
  heatRisk: HeatRisk;
  hasHr: boolean;
  /** Rep-block density — work relative to the recovery that bought it. The
   *  measurement `avgRecoverySec` alone can't give: 60s between 1K reps and
   *  60s between 400s are not the same session. Baseline-free here (a
   *  head-to-head needs no reference), so `multiplier` stays 1.0. */
  density: DensityProfile;
}

// ── Comparability ──

export type Confidence = "high" | "moderate" | "low";
export type FamilyMatch = "same" | "adjacent" | "different";

export interface Comparability {
  score: number; // 0..1, rounded to 2dp
  confidence: Confidence;
  zoneMatch: boolean;
  familyMatch: FamilyMatch;
  volumeRatio: number | null; // smaller/larger quality volume, 2dp
  volumeBandOk: boolean;
  daysApart: number | null;
  /** Plain-language reasons behind the score — surfaced in the UI so a
   *  hedged read never looks arbitrary. */
  notes: string[];
}

// ── Diff ──

interface NumPair {
  a: number;
  b: number;
  delta: number; // b − a
}

export interface ComparisonDiff {
  /** "quality" when both sides are rep sessions, "aerobic" when both are steady
   *  runs, "mixed" when the pair straddles (only the whole-run rows apply). */
  mode: "quality" | "aerobic" | "mixed";
  zone: { a: Zone | null; b: Zone | null; same: boolean };
  structure: { a: string | null; b: string | null };
  // ── Whole-run rows (every readable pair) ──
  totalDistanceMeters: (NumPair & { pctChange: number | null }) | null;
  totalDurationSec: NumPair | null;
  avgPaceSec: NumPair | null; // overall pace, sec/mile
  /** Conditions-adjusted pace (MODEL: heat + grade). Null when neither side is
   *  meaningfully adjusted (flat, temperate) — no phantom row. */
  conditionsAdjustedPaceSec: NumPair | null;
  avgRunHr: NumPair | null;
  elevationGainM: NumPair | null; // total climb per side (context)
  /** Pace of the fast third of each run — the "how quick were the quick bits". */
  fastSegPaceSec: NumPair | null;
  /** Aerobic decoupling %, per side. + = drifted (heart climbed / pace faded). */
  decouplingPct: { a: number | null; b: number | null };
  // ── Quality-work rows (quality pairs only) ──
  reps: NumPair | null;
  avgRepPaceRawSec: NumPair | null;
  avgRepPaceAdjSec: NumPair | null;
  avgRecoverySec: NumPair | null;
  /** Positive values are bpm DROPPED work→float; a positive delta means the
   *  heart came down faster in workout B's recoveries. */
  recoveryHrDropBpm: NumPair | null;
  avgWorkHr: NumPair | null;
  qualityVolumeMeters: (NumPair & { pctChange: number | null }) | null;
  fadePct: { a: number | null; b: number | null };
  tempF: NumPair | null;
  /** Every metric that could NOT be computed, with the reason. Honest
   *  degradation — render these as "unavailable", never as zero. */
  unavailable: string[];
}

export interface ComparisonResult {
  ok: boolean;
  /** Set when ok=false: which side couldn't be read. The UI copy for both is
   *  "couldn't read this session's structure". */
  reason?: "unreadable_a" | "unreadable_b";
  a: WorkProfile; // earlier workout
  b: WorkProfile; // later workout
  comparability: Comparability | null;
  diff: ComparisonDiff | null;
  /** Layer-1 facts serialized one-per-line — the ONLY input the Layer-2
   *  verdict prompt receives, and the source of `allowedNumberTokens`. */
  factLines: string[] | null;
}

// ── Workout family (kind equivalence for the family component) ──

/** Families that read as the same kind of session for matching purposes.
 *  Adjacent = related-but-not-identical (partial credit). */
const ADJACENT_KINDS: ReadonlyArray<ReadonlySet<WorkoutKind>> = [
  new Set<WorkoutKind>(["threshold", "tempo"]),
  new Set<WorkoutKind>(["intervals", "fartlek"]),
  new Set<WorkoutKind>(["tempo", "progression"]),
  new Set<WorkoutKind>(["easy", "long_run", "recovery"]),
];

export function familyMatch(
  a: WorkoutKind | null,
  b: WorkoutKind | null,
): FamilyMatch {
  if (a == null || b == null) return "different";
  if (a === b) return "same";
  for (const pair of ADJACENT_KINDS) {
    if (pair.has(a) && pair.has(b)) return "adjacent";
  }
  return "different";
}

// ── Profile derivation ──

function dayISO(dateStr: string): string {
  const d = new Date(dateStr);
  if (isNaN(d.getTime())) return dateStr;
  return new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()))
    .toISOString()
    .split("T")[0];
}

/** Uniform heat-adjustment ratio for a session (adjusted/raw from the first
 *  lap carrying both), same approach as keySessions.ts `heatSnapshot`. */
function heatSnapshot(
  laps: ComparisonLap[],
): { ratio: number | null; category: string | null } {
  for (const lap of laps) {
    const raw = Number(lap.avg_pace_sec_per_mile ?? 0);
    const adj = Number(lap.heat_adjusted_pace_sec_per_mile ?? 0);
    if (raw > 0 && adj > 0) {
      return { ratio: adj / raw, category: lap.heat_category ?? null };
    }
  }
  return { ratio: null, category: null };
}

/** Rounded human label for a rep distance ("1K", "800m", "2mi"). */
function repDistanceLabelOf(meters: number): string | null {
  if (meters <= 0) return null;
  const miles = meters / METERS_PER_MILE;
  const nearMile = Math.round(miles);
  if (nearMile >= 1 && Math.abs(miles - nearMile) / nearMile < 0.08) {
    return `${nearMile}mi`;
  }
  for (const m of [200, 300, 400, 600, 800, 1000, 1200, 1600, 2000, 3000, 5000]) {
    if (Math.abs(meters - m) / m < 0.08) {
      return m % 1000 === 0 ? `${m / 1000}K` : `${m}m`;
    }
  }
  return `${Math.round(meters / 100) * 100}m`;
}

/** Zone holding the most seconds across the given bouts. */
function dominantZoneOf(bouts: Bout[]): Zone | null {
  const byZone = new Map<Zone, number>();
  for (const b of bouts) byZone.set(b.zone, (byZone.get(b.zone) ?? 0) + b.seconds);
  let best: Zone | null = null;
  let bestSec = -1;
  for (const [z, s] of byZone) {
    if (s > bestSec) {
      best = z;
      bestSec = s;
    }
  }
  return best;
}

interface WholeRun {
  distanceMeters: number;
  durationSec: number;
  avgPaceSec: number | null;
  avgHr: number | null;
  decouplingPct: number | null;
}

/**
 * Whole-run aggregates over every running bout — the aerobic comparison unit,
 * and the shared metrics quality sessions also carry. Decoupling splits the run
 * at its time midpoint (each bout assigned whole by its midpoint) and reports
 * the percent efficiency (speed ÷ HR) lost first-half → second-half; positive
 * means the effort drifted (heart climbed or pace faded). Null without HR on
 * both halves — never faked.
 */
function wholeRunMetrics(bouts: Bout[]): WholeRun {
  let distanceMeters = 0, durationSec = 0, hrSec = 0, hrSum = 0;
  for (const b of bouts) {
    distanceMeters += b.distanceMeters;
    durationSec += b.seconds;
    if (b.avgHr != null && b.avgHr > 0) {
      hrSec += b.seconds;
      hrSum += b.avgHr * b.seconds;
    }
  }
  const miles = distanceMeters / METERS_PER_MILE;
  const avgPaceSec = miles > 0 ? Math.round(durationSec / miles) : null;
  const avgHr = hrSec > 0 ? Math.round(hrSum / hrSec) : null;

  // Decoupling: bucket bouts into first/second half by cumulative-time midpoint.
  let decouplingPct: number | null = null;
  const halfPoint = durationSec / 2;
  const halves: Array<{ distM: number; durS: number; hrSec: number; hrSum: number }> = [
    { distM: 0, durS: 0, hrSec: 0, hrSum: 0 },
    { distM: 0, durS: 0, hrSec: 0, hrSum: 0 },
  ];
  let elapsed = 0;
  for (const b of bouts) {
    const mid = elapsed + b.seconds / 2;
    const h = halves[mid <= halfPoint ? 0 : 1];
    h.distM += b.distanceMeters;
    h.durS += b.seconds;
    if (b.avgHr != null && b.avgHr > 0) {
      h.hrSec += b.seconds;
      h.hrSum += b.avgHr * b.seconds;
    }
    elapsed += b.seconds;
  }
  const eff = (h: { distM: number; durS: number; hrSec: number; hrSum: number }): number | null => {
    if (h.distM <= 0 || h.durS <= 0 || h.hrSec <= 0) return null;
    const paceSec = h.durS / (h.distM / METERS_PER_MILE); // sec/mile
    const hr = h.hrSum / h.hrSec;
    if (paceSec <= 0 || hr <= 0) return null;
    return (1 / paceSec) / hr; // speed per bpm
  };
  const e1 = eff(halves[0]);
  const e2 = eff(halves[1]);
  if (e1 != null && e2 != null && e1 > 0) {
    decouplingPct = round1(((e1 - e2) / e1) * 100);
  }

  return { distanceMeters: Math.round(distanceMeters), durationSec: Math.round(durationSec), avgPaceSec, avgHr, decouplingPct };
}

// Grade-adjustment model now lives in `effortModel.ts` (imported above) so the
// comparison and the effort/load path can never drift to two different grade
// curves. Same posture as before: documented, capped, labeled MODEL in the UI.

interface Environment {
  elevationGainM: number;
  conditionsAdjustedPaceSec: number | null;
  series: SeriesPoint[];
}

/** Per-lap elevation, conditions-adjusted pace (heat snapshot × grade model),
 *  and the cumulative chart series — all from the raw laps. */
function environmentAndSeries(laps: ComparisonLap[]): Environment {
  let elevationGainM = 0, adjW = 0, adjSum = 0, cumMi = 0;
  const series: SeriesPoint[] = [];
  for (const lap of laps) {
    const distM = Number(lap.distance_meters ?? 0);
    const raw = Number(lap.avg_pace_sec_per_mile ?? 0);
    const secs = Number(lap.moving_time_seconds ?? lap.elapsed_time_seconds ?? 0);
    if (distM <= 0 || raw <= 0 || secs <= 0) continue;
    const elev = Number(lap.total_elevation_gain ?? 0);
    elevationGainM += Math.max(0, elev);
    const miles = distM / METERS_PER_MILE;
    const gradePct = miles > 0 ? (elev / distM) * 100 : 0;
    // Base = heat-adjusted lap pace when present (already humidity/heat aware),
    // else raw; then apply the grade model.
    const heatAdj = Number(lap.heat_adjusted_pace_sec_per_mile ?? 0);
    const base = heatAdj > 0 ? heatAdj : raw;
    const adj = base * gradeFactor(gradePct);
    adjW += miles;
    adjSum += adj * miles;
    cumMi += miles;
    series.push({
      mi: round2(cumMi),
      paceSec: Math.round(raw),
      hr: lap.avg_heart_rate != null && Number(lap.avg_heart_rate) > 0
        ? Math.round(Number(lap.avg_heart_rate))
        : null,
      gradePct: round1(gradePct),
    });
  }
  return {
    elevationGainM: Math.round(elevationGainM),
    conditionsAdjustedPaceSec: adjW > 0 ? Math.round(adjSum / adjW) : null,
    series,
  };
}

/** The fast portion of a run: distance-weighted pace of the quickest ~third of
 *  running distance. Null when the run is too uniform (< 10 s/mi faster than
 *  the whole-run pace) to have a meaningful "fast bit". */
function fastSegment(
  bouts: Bout[],
  avgPaceSec: number | null,
): { paceSec: number | null; distanceMeters: number } {
  const running = bouts
    .filter((b) => b.paceSecPerMile > 0 && b.distanceMeters > 0)
    .sort((a, b) => a.paceSecPerMile - b.paceSecPerMile);
  if (running.length === 0) return { paceSec: null, distanceMeters: 0 };
  const totalM = running.reduce((s, b) => s + b.distanceMeters, 0);
  const targetM = totalM / 3;
  let accM = 0, paceW = 0, paceSum = 0;
  for (const b of running) {
    const miles = b.distanceMeters / METERS_PER_MILE;
    paceW += miles;
    paceSum += b.paceSecPerMile * miles;
    accM += b.distanceMeters;
    if (accM >= targetM) break;
  }
  const paceSec = paceW > 0 ? Math.round(paceSum / paceW) : null;
  // Only meaningful when notably faster than the overall pace.
  if (paceSec == null || avgPaceSec == null || avgPaceSec - paceSec < 10) {
    return { paceSec: null, distanceMeters: 0 };
  }
  return { paceSec, distanceMeters: Math.round(accM) };
}

/**
 * Build the work profile for one workout. Never throws; unreadable sessions
 * come back with `readable: false` and a reason.
 */
export function buildWorkProfile(
  workout: ComparisonWorkout,
  zones: PaceZones,
): WorkProfile {
  const empty: WorkProfile = {
    id: workout.id,
    date: dayISO(workout.workout_date),
    readable: false,
    unreadableReason: "no_laps",
    mode: "aerobic",
    workoutKind: null,
    structure: workout.structure_label?.trim() || null,
    dominantWorkZone: null,
    totalDistanceMeters: 0,
    totalDurationSec: 0,
    avgPaceSec: null,
    avgRunHr: null,
    decouplingPct: null,
    conditionsAdjustedPaceSec: null,
    totalElevationGainM: 0,
    fastSegPaceSec: null,
    fastSegDistanceMeters: 0,
    series: [],
    repCount: 0,
    repDistanceLabel: null,
    avgRepPaceRawSec: null,
    avgRepPaceAdjSec: null,
    heatCategory: null,
    fadePct: null,
    avgRecoverySec: null,
    recoveryHrDropBpm: null,
    density: densityFromBouts([]),
    avgWorkHr: null,
    qualityVolumeMeters: 0,
    qualityVolumeSeconds: 0,
    tempF: numOrNull(workout.weather?.temp_f),
    dewPointF: numOrNull(workout.weather?.dew_point_f),
    heatRisk: (() => {
      const t = numOrNull(workout.weather?.temp_f);
      const d = numOrNull(workout.weather?.dew_point_f);
      return assessHeatRisk(t != null && d != null ? compositeScore(t, d) : 0, t, d);
    })(),
    hasHr: false,
  };

  if (!workout.laps || workout.laps.length === 0) return empty;

  const seg: SegmentationResult = segmentFromLaps(workout.laps, zones);
  const workBouts = seg.bouts.filter((b) => b.isWork && b.paceSecPerMile > 0);
  // A run is readable if it has ANY real running segment — quality or aerobic.
  // Only a paceless/empty session is unreadable now (all workout types compare).
  const runBouts = seg.bouts.filter((b) =>
    b.paceSecPerMile > 0 && b.seconds > 0 && b.distanceMeters > 0
  );

  // Whole-run metrics — computed for EVERY readable session, both modes.
  const whole = wholeRunMetrics(runBouts);
  const env = environmentAndSeries(workout.laps);
  const fast = fastSegment(runBouts, whole.avgPaceSec);

  const base: WorkProfile = {
    ...empty,
    readable: runBouts.length > 0,
    unreadableReason: runBouts.length > 0 ? null : "no_run_bouts",
    mode: workBouts.length > 0 ? "quality" : "aerobic",
    workoutKind: seg.workoutKind,
    structure: workout.structure_label?.trim() || seg.structure,
    fadePct: seg.fadePct,
    totalDistanceMeters: whole.distanceMeters,
    totalDurationSec: whole.durationSec,
    avgPaceSec: whole.avgPaceSec,
    avgRunHr: whole.avgHr,
    decouplingPct: whole.decouplingPct,
    conditionsAdjustedPaceSec: env.conditionsAdjustedPaceSec,
    totalElevationGainM: env.elevationGainM,
    fastSegPaceSec: fast.paceSec,
    fastSegDistanceMeters: fast.distanceMeters,
    series: env.series,
    heatCategory: heatSnapshot(workout.laps).category ?? workout.weather?.heat_category ?? null,
    hasHr: whole.avgHr != null,
  };
  if (runBouts.length === 0) return base;

  // Aerobic mode: no work bouts to read by rep. The dominant zone is the top
  // OVERALL zone (easy/steady/…), which drives the type-match gate, and the
  // whole-run metrics above are the comparison. Done.
  if (workBouts.length === 0) {
    return { ...base, dominantWorkZone: dominantZoneOf(runBouts) };
  }

  // Dominant work zone = most work seconds (keySessions.ts convention).
  const zoneSeconds = new Map<Zone, number>();
  for (const b of workBouts) {
    zoneSeconds.set(b.zone, (zoneSeconds.get(b.zone) ?? 0) + b.seconds);
  }
  let dominant: Zone | null = null;
  let bestSec = -1;
  for (const [z, s] of zoneSeconds) {
    if (s > bestSec) {
      dominant = z;
      bestSec = s;
    }
  }

  // Metrics over the DOMINANT-zone work bouts only — like-for-like is the
  // whole point; strides tacked onto a threshold session don't pollute the
  // threshold read.
  const dz = workBouts.filter((b) => b.zone === dominant);
  let paceW = 0, paceSum = 0, hrSec = 0, hrSum = 0, volM = 0, volS = 0;
  for (const b of dz) {
    const w = b.distanceMeters > 0 ? b.distanceMeters / METERS_PER_MILE : b.seconds;
    paceW += w;
    paceSum += b.paceSecPerMile * w;
    if (b.avgHr != null && b.avgHr > 0 && b.seconds > 0) {
      hrSec += b.seconds;
      hrSum += b.avgHr * b.seconds;
    }
    volM += b.distanceMeters;
    volS += b.seconds;
  }
  const avgRepPaceRawSec = paceW > 0 ? Math.round(paceSum / paceW) : null;

  const { ratio, category } = heatSnapshot(workout.laps);
  const avgRepPaceAdjSec = avgRepPaceRawSec != null && ratio != null
    ? Math.round(avgRepPaceRawSec * ratio)
    : null;

  // Recovery bouts BETWEEN work bouts: a rest bout counts when a work bout
  // precedes it and another work bout follows later. Trailing cooldown never
  // counts as "recovery between reps".
  const bouts = seg.bouts;
  const lastWorkIdx = findLastIndex(bouts, (b: Bout) => b.isWork);
  let seenWork = false;
  let recSec = 0, recCount = 0, dropSum = 0, dropCount = 0;
  let prevWorkHr: number | null = null;
  for (let i = 0; i < bouts.length; i++) {
    const b = bouts[i];
    if (b.isWork) {
      seenWork = true;
      prevWorkHr = b.avgHr != null && b.avgHr > 0 ? b.avgHr : null;
      continue;
    }
    if (b.isRest && seenWork && i < lastWorkIdx) {
      recSec += b.seconds;
      recCount++;
      if (prevWorkHr != null && b.avgHr != null && b.avgHr > 0) {
        dropSum += prevWorkHr - b.avgHr;
        dropCount++;
      }
    }
  }

  // Typical rep distance label — only when the reps are uniform enough for
  // the label to be honest.
  const repLabels = seg.reps
    .map((r) => repDistanceLabelOf(r.distanceMeters))
    .filter((l): l is string => l != null);
  const uniformLabel = repLabels.length > 0 && repLabels.every((l) => l === repLabels[0])
    ? repLabels[0]
    : null;

  return {
    ...base,
    dominantWorkZone: dominant,
    repCount: seg.repCount,
    repDistanceLabel: uniformLabel,
    avgRepPaceRawSec,
    avgRepPaceAdjSec,
    heatCategory: category ?? workout.weather?.heat_category ?? null,
    avgRecoverySec: recCount > 0 ? Math.round(recSec / recCount) : null,
    recoveryHrDropBpm: dropCount > 0 ? Math.round(dropSum / dropCount) : null,
    avgWorkHr: hrSec > 0 ? Math.round(hrSum / hrSec) : null,
    qualityVolumeMeters: Math.round(volM),
    qualityVolumeSeconds: Math.round(volS),
    hasHr: hrSec > 0,
    density: densityFromBouts(seg.bouts),
  };
}

// ── Comparability scoring ──

export function scoreComparability(a: WorkProfile, b: WorkProfile): Comparability {
  const notes: string[] = [];

  const zoneMatch = a.dominantWorkZone != null &&
    a.dominantWorkZone === b.dominantWorkZone;
  if (!zoneMatch) {
    notes.push(
      a.dominantWorkZone && b.dominantWorkZone
        ? `Different effort zones (${a.dominantWorkZone} vs ${b.dominantWorkZone}) — these aren't really the same kind of effort; read this loosely.`
        : "One side has no classifiable work zone.",
    );
  }

  const fam = familyMatch(a.workoutKind, b.workoutKind);
  if (fam === "different" && a.workoutKind && b.workoutKind) {
    notes.push(`Different workout families (${a.workoutKind} vs ${b.workoutKind}).`);
  }
  const famScore = fam === "same" ? 1 : fam === "adjacent" ? 0.6 : 0;

  // Volume band on TOTAL run distance (every session has it, both modes).
  let volumeRatio: number | null = null;
  let volScore = 0;
  let volumeBandOk = false;
  if (a.totalDistanceMeters > 0 && b.totalDistanceMeters > 0) {
    volumeRatio = Math.min(a.totalDistanceMeters, b.totalDistanceMeters) /
      Math.max(a.totalDistanceMeters, b.totalDistanceMeters);
    if (volumeRatio >= VOLUME_BAND_RATIO) {
      volScore = 1;
      volumeBandOk = true;
    } else {
      volScore = Math.max(
        0,
        (volumeRatio - VOLUME_RATIO_FLOOR) / (VOLUME_BAND_RATIO - VOLUME_RATIO_FLOOR),
      );
      notes.push("Run distances are quite different — a real stretch to compare directly.");
    }
  } else {
    notes.push("Total distance unavailable on one side.");
  }

  // Pace proximity on overall pace (both modes carry it).
  let paceScore = 0;
  let paceCloseOk = false;
  if (a.avgPaceSec != null && b.avgPaceSec != null) {
    const gap = Math.abs(a.avgPaceSec - b.avgPaceSec);
    if (gap <= PACE_PROXIMITY_FULL_SEC) {
      paceScore = 1;
      paceCloseOk = true;
    } else if (gap >= PACE_PROXIMITY_FLOOR_SEC) {
      paceScore = 0;
      notes.push("Overall paces are far apart — not really the same effort.");
    } else {
      paceScore = 1 -
        (gap - PACE_PROXIMITY_FULL_SEC) / (PACE_PROXIMITY_FLOOR_SEC - PACE_PROXIMITY_FULL_SEC);
    }
  } else {
    notes.push("Overall pace unavailable on one side.");
  }

  // Recency (phase proxy).
  let daysApart: number | null = null;
  let recencyScore = 0.5; // unknown dates → neutral half credit
  const ta = new Date(a.date).getTime();
  const tb = new Date(b.date).getTime();
  if (isFinite(ta) && isFinite(tb)) {
    daysApart = Math.round(Math.abs(tb - ta) / 86400000);
    if (daysApart <= RECENCY_FULL_DAYS) recencyScore = 1;
    else if (daysApart >= RECENCY_FLOOR_DAYS) recencyScore = 0;
    else {
      recencyScore = 1 -
        (daysApart - RECENCY_FULL_DAYS) / (RECENCY_FLOOR_DAYS - RECENCY_FULL_DAYS);
    }
    if (daysApart > RECENCY_FULL_DAYS) {
      notes.push(`${daysApart} days apart — likely different training phases.`);
    }
  }

  // Data quality: both sides readable is a precondition of calling this;
  // HR on both unlocks the recovery reads.
  let dataScore = 1;
  if (!a.hasHr || !b.hasHr) {
    dataScore = 0.5;
    notes.push("Heart-rate data missing on one or both sides — recovery reads unavailable.");
  }

  const w = COMPARABILITY_WEIGHTS;
  const score = round2(
    (zoneMatch ? w.zone : 0) +
      famScore * w.family +
      volScore * w.volume +
      paceScore * w.pace +
      recencyScore * w.recency +
      dataScore * w.data,
  );

  // Confidence gates (decision 2026-07-20: type + distance/volume + pace, with
  // adjacent-family pairs allowed but capped below high — "allow, but hedge").
  let confidence: Confidence = "low";
  if (
    zoneMatch && fam === "same" && volumeBandOk && paceCloseOk &&
    score >= HIGH_CONFIDENCE_MIN_SCORE
  ) {
    confidence = "high";
  } else if (zoneMatch && score >= MODERATE_CONFIDENCE_MIN_SCORE) {
    confidence = "moderate";
  }

  return {
    score,
    confidence,
    zoneMatch,
    familyMatch: fam,
    volumeRatio: volumeRatio == null ? null : round2(volumeRatio),
    volumeBandOk,
    daysApart,
    notes,
  };
}

// ── The diff ──

function pair(a: number | null, b: number | null): NumPair | null {
  if (a == null || b == null) return null;
  return { a, b, delta: round1(b - a) };
}

function pctPair(va: number | null, vb: number | null): (NumPair & { pctChange: number | null }) | null {
  const p = pair(va, vb);
  if (p == null) return null;
  return { ...p, pctChange: p.a > 0 ? round1(((p.b - p.a) / p.a) * 100) : null };
}

/** The conditions-adjusted pace pair, but only when heat/grade actually moved
 *  at least one side ≥2 s/mi off its raw pace — otherwise a flat, temperate
 *  pair would show an adjusted row identical to the raw one. */
function conditionsAdjustedDiff(a: WorkProfile, b: WorkProfile): NumPair | null {
  const p = pair(a.conditionsAdjustedPaceSec, b.conditionsAdjustedPaceSec);
  if (p == null) return null;
  const movedA = a.avgPaceSec != null && Math.abs(a.conditionsAdjustedPaceSec! - a.avgPaceSec) >= 2;
  const movedB = b.avgPaceSec != null && Math.abs(b.conditionsAdjustedPaceSec! - b.avgPaceSec) >= 2;
  return movedA || movedB ? p : null;
}

export function buildDiff(a: WorkProfile, b: WorkProfile): ComparisonDiff {
  const unavailable: string[] = [];
  const need = (
    label: string,
    va: number | null,
    vb: number | null,
  ): NumPair | null => {
    const p = pair(va, vb);
    if (p == null) {
      const side = va == null && vb == null
        ? "both workouts"
        : va == null
        ? "the earlier workout"
        : "the newer workout";
      unavailable.push(`${label} (missing on ${side})`);
    }
    return p;
  };

  const bothQuality = a.mode === "quality" && b.mode === "quality";
  const bothAerobic = a.mode === "aerobic" && b.mode === "aerobic";
  const mode: ComparisonDiff["mode"] = bothQuality ? "quality" : bothAerobic ? "aerobic" : "mixed";

  // Quality-work rows only when BOTH sides are rep sessions — otherwise the
  // "no reps" gaps are noise, not honest absences.
  let reps: NumPair | null = null;
  let avgRepPaceRawSec: NumPair | null = null;
  let avgRepPaceAdjSec: NumPair | null = null;
  let avgRecoverySec: NumPair | null = null;
  let recoveryHrDropBpm: NumPair | null = null;
  let avgWorkHr: NumPair | null = null;
  let qualityVolumeMeters: (NumPair & { pctChange: number | null }) | null = null;
  if (bothQuality) {
    reps = a.repCount > 0 && b.repCount > 0
      ? { a: a.repCount, b: b.repCount, delta: b.repCount - a.repCount }
      : null;
    if (reps == null) unavailable.push("Rep counts (no clean reps detected on one side)");
    avgRepPaceRawSec = need("Avg rep pace", a.avgRepPaceRawSec, b.avgRepPaceRawSec);
    avgRepPaceAdjSec = need("Heat-adjusted rep pace", a.avgRepPaceAdjSec, b.avgRepPaceAdjSec);
    avgRecoverySec = need("Recovery duration", a.avgRecoverySec, b.avgRecoverySec);
    recoveryHrDropBpm = need("HR recovery in floats", a.recoveryHrDropBpm, b.recoveryHrDropBpm);
    avgWorkHr = need("Avg work HR", a.avgWorkHr, b.avgWorkHr);
    qualityVolumeMeters = pctPair(a.qualityVolumeMeters || null, b.qualityVolumeMeters || null);
    if (qualityVolumeMeters == null) unavailable.push("Quality volume (missing on one side)");
  }

  return {
    mode,
    zone: {
      a: a.dominantWorkZone,
      b: b.dominantWorkZone,
      same: a.dominantWorkZone != null && a.dominantWorkZone === b.dominantWorkZone,
    },
    structure: { a: a.structure, b: b.structure },
    totalDistanceMeters: pctPair(a.totalDistanceMeters || null, b.totalDistanceMeters || null),
    totalDurationSec: need("Total duration", a.totalDurationSec || null, b.totalDurationSec || null),
    avgPaceSec: need("Overall pace", a.avgPaceSec, b.avgPaceSec),
    // Show the adjusted row only when heat/grade actually moved a side ≥2 s/mi.
    conditionsAdjustedPaceSec: conditionsAdjustedDiff(a, b),
    avgRunHr: need("Avg heart rate", a.avgRunHr, b.avgRunHr),
    elevationGainM: pair(a.totalElevationGainM || null, b.totalElevationGainM || null),
    fastSegPaceSec: pair(a.fastSegPaceSec, b.fastSegPaceSec),
    decouplingPct: { a: a.decouplingPct, b: b.decouplingPct },
    reps,
    avgRepPaceRawSec,
    avgRepPaceAdjSec,
    avgRecoverySec,
    recoveryHrDropBpm,
    avgWorkHr,
    qualityVolumeMeters,
    fadePct: { a: a.fadePct, b: b.fadePct },
    tempF: need("Temperature", a.tempF, b.tempF),
    unavailable,
  };
}

// ── Fact serialization (the ONLY thing Layer 2 sees) ──

function repsLabel(p: WorkProfile): string {
  if (p.repCount <= 0) return "no clean reps";
  return p.repDistanceLabel
    ? `${p.repCount}×${p.repDistanceLabel}`
    : `${p.repCount} reps (mixed distances)`;
}

function paceStr(sec: number | null): string {
  const f = sec != null ? fmtPace(sec) : null;
  return f != null ? `${f}/mi` : "unavailable";
}

function signed(n: number, unit: string): string {
  const r = Math.abs(n % 1) < 1e-9 ? String(Math.round(n)) : String(round1(n));
  return `${n > 0 ? "+" : ""}${r}${unit}`;
}

/**
 * The Layer-1 diff as plain fact lines — every number auditable, every gap
 * explicit. This is the verdict prompt's entire evidence base.
 */
export function buildFactLines(
  a: WorkProfile,
  b: WorkProfile,
  diff: ComparisonDiff,
  comparability: Comparability,
): string[] {
  const lines: string[] = [];
  lines.push(
    `Workouts: A = ${a.date} (${a.structure ?? a.workoutKind ?? "unknown"}), B = ${b.date} (${b.structure ?? b.workoutKind ?? "unknown"}). A is the earlier session, B the newer one.`,
  );
  lines.push(
    `Session kind: ${diff.mode}. Dominant zone: ${diff.zone.a ?? "unknown"} vs ${diff.zone.b ?? "unknown"} (${diff.zone.same ? "same" : "DIFFERENT"})`,
  );
  if (diff.totalDistanceMeters) {
    const miA = round1(diff.totalDistanceMeters.a / METERS_PER_MILE);
    const miB = round1(diff.totalDistanceMeters.b / METERS_PER_MILE);
    const miDelta = round1((diff.totalDistanceMeters.b - diff.totalDistanceMeters.a) / METERS_PER_MILE);
    const pct = diff.totalDistanceMeters.pctChange;
    lines.push(
      `Total distance: ${miA} mi -> ${miB} mi (${signed(miDelta, " mi")}${pct != null ? `, ${signed(pct, "%")}` : ""})`,
    );
  }
  if (diff.totalDurationSec) {
    const minDelta = Math.round(diff.totalDurationSec.delta / 60);
    lines.push(
      `Total duration: ${fmtDuration(diff.totalDurationSec.a)} -> ${fmtDuration(diff.totalDurationSec.b)} (${signed(minDelta, " min")})`,
    );
  }
  if (diff.avgPaceSec) {
    lines.push(
      `Overall pace: ${paceStr(a.avgPaceSec)} -> ${paceStr(b.avgPaceSec)} (${signed(diff.avgPaceSec.delta, " sec/mi")})`,
    );
  }
  if (diff.conditionsAdjustedPaceSec) {
    lines.push(
      `Conditions-adjusted pace (a model correcting for heat + hills): ${paceStr(a.conditionsAdjustedPaceSec)} -> ${paceStr(b.conditionsAdjustedPaceSec)} (${signed(diff.conditionsAdjustedPaceSec.delta, " sec/mi")}; this is the fairer fitness read when conditions differ)`,
    );
  }
  if (diff.elevationGainM && (a.totalElevationGainM > 0 || b.totalElevationGainM > 0)) {
    const ftA = Math.round(a.totalElevationGainM * 3.28084);
    const ftB = Math.round(b.totalElevationGainM * 3.28084);
    lines.push(`Elevation gain: ${ftA} ft -> ${ftB} ft (${signed(ftB - ftA, " ft")})`);
  }
  if (diff.fastSegPaceSec) {
    lines.push(
      `Fast-segment pace (quickest third of each run): ${paceStr(a.fastSegPaceSec)} -> ${paceStr(b.fastSegPaceSec)} (${signed(diff.fastSegPaceSec.delta, " sec/mi")})`,
    );
  }
  if (diff.avgRunHr) {
    lines.push(
      `Avg heart rate: ${Math.round(diff.avgRunHr.a)} bpm -> ${Math.round(diff.avgRunHr.b)} bpm (${signed(diff.avgRunHr.delta, " bpm")})`,
    );
  }
  if (diff.decouplingPct.a != null && diff.decouplingPct.b != null) {
    lines.push(
      `Aerobic decoupling (efficiency lost first half -> second half): ${signed(diff.decouplingPct.a, "%")} vs ${signed(diff.decouplingPct.b, "%")} (lower = held form better; a drop under ~5% is a strong aerobic run)`,
    );
  }
  if (diff.mode === "quality") {
    lines.push(`Reps: ${repsLabel(a)} -> ${repsLabel(b)}${diff.reps ? ` (${signed(diff.reps.delta, " reps")})` : ""}`);
  }
  if (diff.avgRepPaceRawSec) {
    lines.push(
      `Avg rep pace (raw): ${paceStr(a.avgRepPaceRawSec)} -> ${paceStr(b.avgRepPaceRawSec)} (${signed(diff.avgRepPaceRawSec.delta, " sec/mi")})`,
    );
  }
  if (diff.avgRepPaceAdjSec) {
    lines.push(
      `Avg rep pace (heat-adjusted): ${paceStr(a.avgRepPaceAdjSec)} -> ${paceStr(b.avgRepPaceAdjSec)} (${signed(diff.avgRepPaceAdjSec.delta, " sec/mi")})`,
    );
  }
  if (diff.avgRecoverySec) {
    lines.push(
      `Avg recovery between reps: ${Math.round(diff.avgRecoverySec.a)}s -> ${Math.round(diff.avgRecoverySec.b)}s (${signed(diff.avgRecoverySec.delta, "s")})`,
    );
  }
  // Density — what the recovery bought, relative to the work it separated.
  // Stated as measurement only: no "harder", no ranking. The rest ratio is the
  // shape-independent figure, so 10×1K and 6×mile stay comparable on it.
  lines.push(...describeDensityDiff(a.density, b.density));
  if (diff.recoveryHrDropBpm) {
    lines.push(
      `HR drop in recoveries: ${Math.round(diff.recoveryHrDropBpm.a)} bpm -> ${Math.round(diff.recoveryHrDropBpm.b)} bpm (${signed(diff.recoveryHrDropBpm.delta, " bpm")}; a bigger drop means the heart came down faster)`,
    );
  }
  if (diff.avgWorkHr) {
    lines.push(
      `Avg work HR: ${Math.round(diff.avgWorkHr.a)} bpm -> ${Math.round(diff.avgWorkHr.b)} bpm (${signed(diff.avgWorkHr.delta, " bpm")})`,
    );
  }
  if (diff.qualityVolumeMeters) {
    const miA = round1(diff.qualityVolumeMeters.a / METERS_PER_MILE);
    const miB = round1(diff.qualityVolumeMeters.b / METERS_PER_MILE);
    const pct = diff.qualityVolumeMeters.pctChange;
    lines.push(
      `Total quality volume: ${miA} mi -> ${miB} mi${pct != null ? ` (${signed(pct, "%")})` : ""}`,
    );
  }
  if (diff.fadePct.a != null && diff.fadePct.b != null) {
    lines.push(
      `Rep-to-rep fade (first rep -> last rep pace): ${signed(diff.fadePct.a, "%")} vs ${signed(diff.fadePct.b, "%")} (positive = faded, negative = sped up)`,
    );
  }
  if (diff.tempF) {
    lines.push(
      `Temperature: ${Math.round(diff.tempF.a)}F -> ${Math.round(diff.tempF.b)}F (${signed(diff.tempF.delta, "F")})`,
    );
  }
  // Dew point + heat category. Temperature alone under-describes the day: the
  // heat model is driven by DEW POINT, so a fact line that stops at "78F" lets
  // the verdict describe a 75F-dew slog and a dry 78F morning identically. The
  // numbers were on the profile all along and simply never reached the prompt.
  const dewA = a.dewPointF, dewB = b.dewPointF;
  if (dewA != null || dewB != null) {
    lines.push(
      `Dew point: ${dewA != null ? `${Math.round(dewA)}F` : "unavailable"} -> ` +
      `${dewB != null ? `${Math.round(dewB)}F` : "unavailable"}` +
      `${a.heatCategory || b.heatCategory ? ` (${a.heatCategory ?? "unknown"} -> ${b.heatCategory ?? "unknown"})` : ""}` +
      ` — dew point drives the heat model, not temperature alone`,
    );
  }
  // Heat RISK (WBGT), which the dew-point pace model can't speak to. Carries
  // its own disclosure when the pace figure above is an extrapolation — a hot
  // dry day is the case the pace chart reads mildest and WBGT reads worst.
  for (const [side, p] of [["A", a], ["B", b]] as const) {
    for (const line of describeHeatRisk(p.heatRisk)) {
      lines.push(`${side}: ${line}`);
    }
  }
  if (diff.unavailable.length > 0) {
    lines.push(`Unavailable: ${diff.unavailable.join("; ")}`);
  }
  lines.push(
    `Comparability: ${comparability.score.toFixed(2)} (${comparability.confidence} confidence)${comparability.notes.length > 0 ? ` — ${comparability.notes.join(" ")}` : ""}`,
  );
  return lines;
}

// ── Top-level compare ──

/**
 * Compare two workouts. Order-insensitive: the earlier session becomes A.
 * Refuses ONLY when a side is unreadable (no laps / no classifiable work
 * bouts); zone or family mismatches render with low confidence instead —
 * manual mode never refuses (spec).
 */
export function compareWorkouts(
  first: ComparisonWorkout,
  second: ComparisonWorkout,
  zones: PaceZones,
): ComparisonResult {
  let pa = buildWorkProfile(first, zones);
  let pb = buildWorkProfile(second, zones);
  // Earlier session is always A.
  if (new Date(pa.date).getTime() > new Date(pb.date).getTime()) {
    [pa, pb] = [pb, pa];
  }

  if (!pa.readable || !pb.readable) {
    return {
      ok: false,
      reason: !pa.readable ? "unreadable_a" : "unreadable_b",
      a: pa,
      b: pb,
      comparability: null,
      diff: null,
      factLines: null,
    };
  }

  const comparability = scoreComparability(pa, pb);
  const diff = buildDiff(pa, pb);
  const factLines = buildFactLines(pa, pb, diff, comparability);
  return { ok: true, a: pa, b: pb, comparability, diff, factLines };
}

// ── Auto-suggest matcher ──

export interface ScoredCandidate {
  id: string;
  score: number;
  confidence: Confidence;
  zoneMatch: boolean;
  date: string;
}

/**
 * Rank prior workouts as comparison candidates for `target`, best first.
 * Unreadable candidates are dropped (they can't produce a diff). Used by
 * the auto-suggest front door; manual mode bypasses this entirely.
 */
export function rankComparisonCandidates(
  target: ComparisonWorkout,
  candidates: ComparisonWorkout[],
  zones: PaceZones,
): ScoredCandidate[] {
  const tp = buildWorkProfile(target, zones);
  if (!tp.readable) return [];
  const scored: ScoredCandidate[] = [];
  for (const c of candidates) {
    if (c.id === target.id) continue;
    const cp = buildWorkProfile(c, zones);
    if (!cp.readable) continue;
    const cmp = scoreComparability(cp, tp);
    scored.push({
      id: c.id,
      score: cmp.score,
      confidence: cmp.confidence,
      zoneMatch: cmp.zoneMatch,
      date: cp.date,
    });
  }
  // Best score first; ties → most recent candidate.
  scored.sort((x, y) => y.score - x.score || (x.date < y.date ? 1 : -1));
  return scored;
}

/** The auto-suggested pair: best-scoring candidate that clears the floor.
 *  "Allow, but hedge" (2026-07-20): a same-type match is preferred, but a close
 *  adjacent one (e.g. easy vs long) can still be suggested — the score already
 *  weights type heavily, so a non-type-match only clears the floor when
 *  distance + pace are close, and it surfaces at moderate/low confidence. Null
 *  when nothing clears the floor — the UI falls back to the manual picker. */
export function findBestComparison(
  target: ComparisonWorkout,
  candidates: ComparisonWorkout[],
  zones: PaceZones,
): ScoredCandidate | null {
  const ranked = rankComparisonCandidates(target, candidates, zones);
  // Prefer a type-match at/above the floor; otherwise the best pair that still
  // clears the floor on distance+pace alone.
  const typed = ranked.find((r) => r.zoneMatch && r.score >= AUTO_SUGGEST_MIN_SCORE);
  if (typed) return typed;
  const any = ranked.find((r) => r.score >= AUTO_SUGGEST_MIN_SCORE);
  return any ?? null;
}

// ── Layer-2 number guard ──
//
// "It cannot introduce a number that isn't in Layer 1." The edge function
// enforces this literally: every numeric token in the verdict must appear
// among the numeric tokens of the fact lines. Pure + testable, so it lives
// here rather than in the function body.

const NUMBER_TOKEN_RE = /\d+:\d{2}|\d+(?:\.\d+)?/g;

/** Every numeric token present in the fact lines (plus benign small counts
 *  the model may use for phrasing like "two more reps" written as digits). */
export function allowedNumberTokens(factLines: string[]): Set<string> {
  const allowed = new Set<string>();
  for (const line of factLines) {
    for (const m of line.match(NUMBER_TOKEN_RE) ?? []) {
      allowed.add(m);
      // A decimal fact also licenses its rounded form ("+25.0%" → "25").
      if (m.includes(".") && !m.includes(":")) {
        allowed.add(String(Math.round(Number(m))));
      }
    }
  }
  return allowed;
}

/** True when the verdict text introduces no number absent from Layer 1. */
export function verdictNumbersAllowed(
  verdict: string,
  allowed: Set<string>,
): boolean {
  return firstDisallowedNumber(verdict, allowed) == null;
}

/** The first numeric token in `verdict` not licensed by `allowed`, or null when
 *  every number checks out. Powers both the guard and its diagnostics. */
export function firstDisallowedNumber(
  verdict: string,
  allowed: Set<string>,
): string | null {
  for (const m of verdict.match(NUMBER_TOKEN_RE) ?? []) {
    if (allowed.has(m)) continue;
    // License rounded forms of allowed decimals and vice versa.
    if (!m.includes(":") && allowed.has(String(Math.round(Number(m))))) continue;
    return m;
  }
  return null;
}

// ── Small helpers ──

function findLastIndex<T>(xs: T[], pred: (x: T) => boolean): number {
  for (let i = xs.length - 1; i >= 0; i--) if (pred(xs[i])) return i;
  return -1;
}

function numOrNull(v: number | null | undefined): number | null {
  return typeof v === "number" && isFinite(v) ? v : null;
}

/** Whole minutes as "H:MM" / "M min" for fact lines. */
function fmtDuration(sec: number): string {
  const total = Math.round(sec / 60);
  if (total < 60) return `${total} min`;
  const h = Math.floor(total / 60);
  const m = total % 60;
  return `${h}:${String(m).padStart(2, "0")}`;
}

const round1 = (x: number): number => Math.round(x * 10) / 10;
const round2 = (x: number): number => Math.round(x * 100) / 100;

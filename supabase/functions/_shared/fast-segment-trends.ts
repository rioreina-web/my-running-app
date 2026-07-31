/**
 * Fast-Segment Trends — per-system key-session analytics.
 *
 * WHAT THIS IS
 * ------------
 * The trend layer for "the sharp end" of training: it takes the rep-level laps
 * of a key session (running_workout_laps), isolates the fast segments, and
 * aggregates them into the metrics a coach actually reads a workout by —
 * rep length, fast volume, pace, HR during the work, density (work:rest), rest,
 * and a heat-adjusted (cool-equivalent) pace. Then it trends those across
 * sessions so you can see whether the fast stuff is getting sharper over time.
 *
 * WHY IT'S SYSTEM-AWARE (decision 2026-07-17, Rio)
 * ------------------------------------------------
 * "Fast" is not one thing. MP, HMP, LT, 10K, 5K, 3K and mile pace train
 * different systems, and a well-run session of each carries a DIFFERENT amount
 * of work:
 *     MP  7–15 mi   ·  HMP 5–9 mi  ·  LT 4–8 mi
 *     10K 4–7 mi    ·  5K 3–4 mi   ·  3K 2–3 mi   ·  Mile 1–2 mi
 * So we must NOT trend all fast work on one axis — a 1.5-mile mile-rep session
 * would look "low volume" next to a 12-mile MP day when both were perfectly
 * executed. Two consequences, both handled here:
 *   1. Every rep is classified into its OWN pace system (nearest race anchor in
 *      the athlete's zones), not just "fast vs. not".
 *   2. A session can MIX systems (a ladder: 1200 @ 10K, 800 @ 5K, 400 @ mile;
 *      an MP run with 5K surges). We break the session down per system and let
 *      each system's work flow into its OWN trend line — a mixed session
 *      contributes to several. Volume is judged per system against its range.
 *
 * REUSE, DON'T REINVENT
 * ---------------------
 * - "Fast" = MP-and-faster, the app's canonical quality definition
 *   (quality-volume.ts `isQualityPace`). The `effort` string labels are ignored.
 * - Heat adjustment is the dew-point model with rep-length scaling
 *   (pace-heat-adjustment.ts `adjustPace`) — short reps shed heat in recovery,
 *   so they get less of the penalty. The "neutral equivalent" is the pace the
 *   work is worth in cool air; that's the honest cross-heat fitness signal.
 * - The "a rep is bounded by a recovery, not a lap marker" rule is honored by
 *   merging consecutive fast laps into one bout (mirrors shared/workBouts.ts).
 *
 * Pure functions only. No DB, no I/O, no AI — feed it typed rows, get numbers.
 */

import { isQualityPace, type ZoneTable } from "./quality-volume.ts";
import { adjustPace } from "./pace-heat-adjustment.ts";
import { adjustPaceForGrade, combineConditions, gradeAdjustRun, type RunSegment } from "./pace-grade-adjustment.ts";

const METERS_PER_MILE = 1609.344;

// ── Pace systems ───────────────────────────────────────────────

/** The seven race-anchored "fast" systems, sharpest last. Aerobic zones
 *  (easy/moderate/steady) are not systems — they're slower than MP and don't
 *  count as fast work. */
export type PaceSystem = "MP" | "HMP" | "LT" | "10K" | "5K" | "3K" | "Mile";

/** Anchor field on the stored `athlete_state.pace_zones` blob (ZoneTable) for
 *  each system, ordered slowest → fastest. */
const SYSTEM_ANCHORS: Array<{ system: PaceSystem; key: keyof ZoneTable }> = [
  { system: "MP", key: "mp" },
  { system: "HMP", key: "hm" },
  { system: "LT", key: "lt" },
  { system: "10K", key: "tenK" },
  { system: "5K", key: "fiveK" },
  { system: "3K", key: "threeK" },
  { system: "Mile", key: "mile" },
];

/**
 * Expected WORK volume (miles at pace, excluding recoveries/WU/CD) for a
 * well-run single session of each system. Rio's coaching guidance
 * (2026-07-17); LT and 3K interpolated between their neighbours. Tunable —
 * these gate the per-system "below / in-range / above" volume read, they are
 * not hard limits.
 */
export const SYSTEM_WORK_VOLUME_MILES: Record<PaceSystem, [number, number]> = {
  MP: [7, 15],
  HMP: [5, 9],
  LT: [4, 8],
  "10K": [4, 7],
  "5K": [3, 4],
  "3K": [2, 3],
  Mile: [1, 2],
};

export type VolumeStatus = "below" | "in_range" | "above";

function volumeStatus(miles: number, [lo, hi]: [number, number]): VolumeStatus {
  if (miles < lo) return "below";
  if (miles > hi) return "above";
  return "in_range";
}

/**
 * The least fast-work miles for a run to count as a session OF a system (rather
 * than merely touching that pace). ~a third of the system's typical low end,
 * floored at 0.4 mi — so a 0.6 mi HMP bite inside a 5K workout stays out of the
 * HMP trend, while a legitimate 1 mi of mile-pace reps still counts.
 */
function minSystemMiles(system: PaceSystem): number {
  return Math.max(0.4, SYSTEM_WORK_VOLUME_MILES[system][0] * 0.35);
}

/**
 * Classify a measured pace into its system: the nearest race anchor at MP or
 * faster. Returns null for anything slower than MP (aerobic — not fast work).
 * Mirrors quality-volume's `zoneForPace` but keeps the granular system label
 * instead of collapsing to race_pace/threshold/interval.
 */
export function systemForPace(paceSecPerMile: number, zones: ZoneTable): PaceSystem | null {
  const mp = zones.mp;
  if (!mp || !(paceSecPerMile > 0)) return null;
  if (!isQualityPace(paceSecPerMile, mp)) return null; // slower than MP (+tol) → aerobic

  let best: PaceSystem | null = null;
  let bestDelta = Infinity;
  for (const { system, key } of SYSTEM_ANCHORS) {
    const anchor = zones[key];
    if (typeof anchor !== "number" || !(anchor > 0)) continue;
    const delta = Math.abs(paceSecPerMile - anchor);
    if (delta < bestDelta) {
      bestDelta = delta;
      best = system;
    }
  }
  return best ?? "MP";
}

// ── Inputs ─────────────────────────────────────────────────────

/** A subset of a `running_workout_laps` row — the columns this module reads. */
export interface WorkoutLap {
  distance_meters: number;
  moving_time_seconds: number;
  /** Derived on insert (sec/mi). When absent we fall back to time/distance. */
  avg_pace_sec_per_mile?: number | null;
  avg_heart_rate?: number | null;
  max_heart_rate?: number | null;
  total_elevation_gain?: number | null;
  /** Average gradient of the lap in percent (+uphill / −downhill). Best fed
   *  from the altitude stream (accurate for rolling terrain); when absent the
   *  analyzer falls back to net grade = total_elevation_gain / distance, which
   *  only sees ascent — see `boutGradePct`. */
  avg_grade_pct?: number | null;
  /**
   * SPLIT (segmented) grade: the lap's grade profile sliced from the altitude
   * stream — `{seconds, gradePct}` micro-segments. When present the analyzer
   * runs `gradeAdjustRun` over them (rolling terrain, damped downhills) instead
   * of the net-grade approximation, so a rep that climbs then descends is
   * credited honestly rather than read as "all uphill".
   */
  grade_segments?: Array<{ seconds: number; gradePct: number }> | null;
}

/** Temp + dew point for the session (training_logs.weather_actual). Dew point
 *  — not humidity — is the runner-relevant moisture metric the heat model uses. */
export interface SessionWeather {
  tempF: number;
  dewPointF: number;
}

export interface KeySessionInput {
  id: string;
  /** ISO date (YYYY-MM-DD) — used only for chronological ordering. */
  date: string;
  name?: string;
  /** Rep-level laps in chronological order (running_workout_laps for the log). */
  laps: WorkoutLap[];
  /** Whole-run distance in miles (training_logs.workout_distance_miles). Gives
   *  the fast work its context — a 0.6 mi HMP bite inside a 5.3 mi run. */
  totalMiles?: number | null;
  weather?: SessionWeather | null;
}

// ── Outputs ────────────────────────────────────────────────────

export interface FastRep {
  index: number;
  system: PaceSystem;
  distanceMeters: number;
  distanceMiles: number;
  durationSeconds: number;
  paceSecPerMile: number;
  /** Average gradient of the rep (%, +uphill / −downhill). */
  gradePct: number;
  /** Heat-adjusted cool-weather-equivalent pace (faster). null with no weather. */
  neutralPaceSecPerMile: number | null;
  /** Grade-adjusted flat-equivalent pace (heat KEPT — the grade-only twin of
   *  `neutralPaceSecPerMile`, so the two adjustments toggle independently).
   *  null on flat/unknown terrain. */
  flatPaceSecPerMile: number | null;
  /** Conditions-adjusted pace: heat AND grade both removed (cool + flat). null
   *  when neither applied. The honest cross-day fitness pace. */
  conditionsPaceSecPerMile: number | null;
  avgHeartRate: number | null;
}

/** One system's slice of a session (a mixed session yields several). */
export interface SystemVolume {
  system: PaceSystem;
  reps: number;
  workMiles: number;
  workSeconds: number;
  avgPaceSecPerMile: number;
  neutralPaceSecPerMile: number | null;
  /** Grade-only flat-equivalent pace (heat kept). null on flat terrain. */
  flatPaceSecPerMile: number | null;
  conditionsPaceSecPerMile: number | null;
  avgHeartRate: number | null;
  expectedMiles: [number, number];
  volumeStatus: VolumeStatus;
}

export interface KeySessionMetrics {
  id: string;
  date: string;
  name: string | null;
  /** Whole-run distance (miles) — fast work in context. */
  totalMiles: number | null;
  /** Dominant system by work volume (the headline label). null = no fast work. */
  primarySystem: PaceSystem | null;
  repCount: number;
  fastMiles: number;
  fastTimeSeconds: number;
  avgPaceSecPerMile: number;
  /** Distance-weighted heat-adjusted session pace (cool-equivalent). */
  neutralPaceSecPerMile: number | null;
  /** Distance-weighted grade-only flat-equivalent pace (heat kept). null on
   *  flat/unknown terrain. Lets heat and hills toggle independently. */
  flatPaceSecPerMile: number | null;
  /** Distance-weighted conditions-adjusted pace (cool + flat) — heat and grade
   *  both removed. The honest cross-day fitness signal. */
  conditionsPaceSecPerMile: number | null;
  avgHeartRate: number | null;
  maxHeartRate: number | null;
  /** Meters covered per heartbeat across the fast reps — rises as fitness does. */
  metersPerBeat: number | null;
  restTimeSeconds: number;
  avgRestSeconds: number;
  /** Fast time / (fast + rest) time, as a percent — how packed the session was. */
  densityPct: number;
  workRestRatio: number | null;
  avgRepMeters: number;
  avgRepSeconds: number;
  elevationGainM: number;
  /** HR drift across the set: last rep's avg HR − rep 2's avg HR (rep 1 is
   *  never the baseline — HR lags the effort and reads ~10 bpm low). null with
   *  < 3 reps, missing HR, or short reps (< 60 s avg — HR never stabilizes). */
  hrDriftBpm: number | null;
  /** Mean HR drop into the recovery: rep max HR − the following rest bout's
   *  avg HR, averaged over rests that carry HR. Bigger = recovering faster. */
  recoveryHrDropBpm: number | null;
  /** Aerobic decoupling (% efficiency lost, first half → second half) of the
   *  longest CONTINUOUS effort — only when that effort is ≥ 15 min across ≥ 2
   *  laps. Interval sessions honestly read null; this is a tempo/steady signal. */
  decouplingPct: number | null;
  heat: { tempF: number; dewPointF: number; adjustmentSecPerMile: number } | null;
  /** Terrain effect: session's distance-weighted average grade (%) and the
   *  sec/mile the hills cost (>0 net uphill). null on flat/unknown terrain. */
  grade: { avgGradePct: number; adjustmentSecPerMile: number } | null;
  /** Per-system breakdown; length > 1 when the session mixes systems. */
  bySystem: SystemVolume[];
  reps: FastRep[];
}

export interface SystemTrendPoint {
  sessionId: string;
  date: string;
  sessionName: string | null;
  reps: number;
  workMiles: number;
  totalMiles: number | null;
  avgPaceSecPerMile: number;
  neutralPaceSecPerMile: number | null;
  /** Grade-only flat-equivalent pace (heat kept). */
  flatPaceSecPerMile: number | null;
  conditionsPaceSecPerMile: number | null;
  avgHeartRate: number | null;
  volumeStatus: VolumeStatus;
}

/** Like-for-like trend for a single system across all sessions that hit it. */
export interface SystemTrend {
  system: PaceSystem;
  expectedMiles: [number, number];
  points: SystemTrendPoint[]; // chronological
}

export interface FastSegmentTrends {
  sessions: KeySessionMetrics[]; // all sessions, chronological
  systems: SystemTrend[];        // grouped by system for like-for-like trending
}

// ── Core ───────────────────────────────────────────────────────

function lapPaceSec(lap: WorkoutLap): number | null {
  const stated = lap.avg_pace_sec_per_mile;
  if (typeof stated === "number" && stated > 0) return stated;
  const dist = lap.distance_meters / METERS_PER_MILE;
  const secs = lap.moving_time_seconds;
  return dist > 0 && secs > 0 ? secs / dist : null;
}

/** A merged run of consecutive fast laps — a "bout" bounded by recovery. */
interface Bout {
  laps: WorkoutLap[];
  distanceMeters: number;
  durationSeconds: number;
}

/**
 * Analyze a single key session into per-system fast-segment metrics.
 * Returns null when the session has no fast (MP+) work.
 */
export function analyzeKeySession(
  input: KeySessionInput,
  zones: ZoneTable,
): KeySessionMetrics | null {
  const laps = input.laps ?? [];

  // 1) Classify each lap fast (MP+) vs not, and find the fast window so warmup
  //    and cooldown (also slower than MP) don't get counted as "rest".
  const fastFlags = laps.map((l) => {
    const p = lapPaceSec(l);
    return p != null && zones.mp != null && isQualityPace(p, zones.mp);
  });
  const firstFast = fastFlags.indexOf(true);
  const lastFast = fastFlags.lastIndexOf(true);
  if (firstFast === -1) return null;

  // 2) Inside [firstFast, lastFast], merge consecutive fast laps into bouts (a
  //    rep is bounded by a recovery, not a lap marker); non-fast laps between
  //    bouts are recovery/rest.
  const bouts: Bout[] = [];
  let restSeconds = 0;
  let cur: Bout | null = null;
  /** Rest laps that FOLLOW each bout (bout index → rest laps), for the
   *  recovery-HR-drop read. */
  const restAfterBout = new Map<number, WorkoutLap[]>();
  for (let i = firstFast; i <= lastFast; i++) {
    if (fastFlags[i]) {
      if (!cur) cur = { laps: [], distanceMeters: 0, durationSeconds: 0 };
      cur.laps.push(laps[i]);
      cur.distanceMeters += laps[i].distance_meters;
      cur.durationSeconds += laps[i].moving_time_seconds;
    } else {
      if (cur) { bouts.push(cur); cur = null; }
      restSeconds += laps[i].moving_time_seconds;
      if (bouts.length > 0) {
        const arr = restAfterBout.get(bouts.length - 1) ?? [];
        arr.push(laps[i]);
        restAfterBout.set(bouts.length - 1, arr);
      }
    }
  }
  if (cur) bouts.push(cur);
  if (bouts.length === 0) return null;

  // 3) Turn each bout into a FastRep with system + heat-adjusted pace.
  const weather = input.weather ?? null;
  const reps: FastRep[] = bouts.map((b, idx) => {
    const distanceMiles = b.distanceMeters / METERS_PER_MILE;
    const paceSec = b.durationSeconds > 0 ? b.durationSeconds / distanceMiles : 0;
    const system = systemForPace(paceSec, zones) ?? "MP";
    const heatAdj = weather
      ? adjustPace(paceSec, weather.tempF, weather.dewPointF, distanceMiles)
      : null;
    const heatPct = heatAdj ? heatAdj.effectiveAdjustmentPercent : 0;
    const neutral = heatAdj ? heatAdj.neutralEquivalentPaceSeconds : null;

    // Grade: prefer SPLIT (segmented) grade from the altitude stream — rolling
    // terrain, damped downhills, via gradeAdjustRun — and fall back to the
    // net-grade approximation when no profile is present.
    const gradeSegs = collectGradeSegments(b.laps);
    let gradePct: number;
    let flatPaceSec: number | null = null; // grade-only flat-equivalent pace
    if (gradeSegs.length > 0) {
      const { rawSeconds, adjustedSeconds } = gradeAdjustRun(gradeSegs);
      gradePct = timeWeightedGrade(gradeSegs);
      const factor = rawSeconds > 0 ? adjustedSeconds / rawSeconds : 1;
      flatPaceSec = paceSec * factor; // uphill: factor<1 → faster flat pace
    } else {
      gradePct = boutGradePct(b.laps, b.distanceMeters);
      // Net-grade fallback: only when the terrain is REAL (≥1%) — net grade is
      // built from ascent-only elevation_gain, so GPS noise reads as a phantom
      // uphill on flat routes. Below the deadband the rep is treated as flat.
      if (Math.abs(gradePct) >= 1.0) {
        flatPaceSec = adjustPaceForGrade(paceSec, gradePct).adjustedPaceSeconds;
      } else {
        gradePct = 0;
      }
    }

    const hasGrade = flatPaceSec != null || Math.abs(gradePct) > 0.1;
    const hasConditions = heatAdj != null || hasGrade;
    let conditions: number | null = null;
    if (hasConditions) {
      conditions = flatPaceSec != null
        ? flatPaceSec / (1 + heatPct) // heat on top of the grade-only flat pace
        : combineConditions(paceSec, gradePct, heatPct).conditionsAdjustedPaceSeconds;
    }
    const hr = timeWeightedHR(b.laps);
    return {
      index: idx + 1,
      system,
      distanceMeters: Math.round(b.distanceMeters),
      distanceMiles: round2(distanceMiles),
      durationSeconds: Math.round(b.durationSeconds),
      paceSecPerMile: round1(paceSec),
      gradePct: round1(gradePct),
      neutralPaceSecPerMile: neutral != null ? round1(neutral) : null,
      flatPaceSecPerMile: flatPaceSec != null ? round1(flatPaceSec) : null,
      conditionsPaceSecPerMile: conditions != null ? round1(conditions) : null,
      avgHeartRate: hr,
    };
  });

  // 4) Session aggregates.
  const fastMeters = reps.reduce((s, r) => s + r.distanceMeters, 0);
  const fastTime = reps.reduce((s, r) => s + r.durationSeconds, 0);
  const fastMiles = fastMeters / METERS_PER_MILE;
  const avgPace = fastMiles > 0 ? fastTime / fastMiles : 0;

  const repsWithHR = reps.filter((r) => r.avgHeartRate != null);
  const hrTimeNum = repsWithHR.reduce((s, r) => s + r.avgHeartRate! * r.durationSeconds, 0);
  const hrTimeDen = repsWithHR.reduce((s, r) => s + r.durationSeconds, 0);
  const avgHR = hrTimeDen > 0 ? hrTimeNum / hrTimeDen : null;
  const maxHR = maxOrNull(input.laps.map((l) => l.max_heart_rate ?? null));

  const beats = repsWithHR.reduce((s, r) => s + r.avgHeartRate! * (r.durationSeconds / 60), 0);
  const metersPerBeat = beats > 0 ? fastMeters / beats : null;

  // Distance-weighted heat-only (neutral) and heat+grade (conditions) paces.
  let neutralPace: number | null = null;
  if (weather) {
    const num = reps.reduce((s, r) => s + (r.neutralPaceSecPerMile ?? r.paceSecPerMile) * r.distanceMiles, 0);
    neutralPace = fastMiles > 0 ? num / fastMiles : null;
  }
  let conditionsPace: number | null = null;
  if (reps.some((r) => r.conditionsPaceSecPerMile != null) && fastMiles > 0) {
    const num = reps.reduce((s, r) => s + (r.conditionsPaceSecPerMile ?? r.paceSecPerMile) * r.distanceMiles, 0);
    conditionsPace = num / fastMiles;
  }
  let flatPace: number | null = null;
  if (reps.some((r) => r.flatPaceSecPerMile != null) && fastMiles > 0) {
    const num = reps.reduce((s, r) => s + (r.flatPaceSecPerMile ?? r.paceSecPerMile) * r.distanceMiles, 0);
    flatPace = num / fastMiles;
  }
  const avgGradePct = fastMeters > 0
    ? reps.reduce((s, r) => s + r.gradePct * r.distanceMeters, 0) / fastMeters
    : 0;

  // Per-system breakdown (a mixed session yields several).
  const bySystem = buildSystemVolumes(reps);

  const primarySystem = bySystem.length
    ? bySystem.reduce((a, b) => (b.workMiles > a.workMiles ? b : a)).system
    : null;

  const restTime = restSeconds;
  const totalWork = fastTime + restTime;
  const densityPct = totalWork > 0 ? (100 * fastTime) / totalWork : 100;
  const workRest = restTime > 0 ? fastTime / restTime : null;
  const avgRest = reps.length > 1 ? restTime / (reps.length - 1) : 0;
  const elevation = input.laps
    .slice(firstFast, lastFast + 1)
    .reduce((s, l) => s + (l.total_elevation_gain ?? 0), 0);

  // ── HR reads: drift, recovery drop, decoupling ──
  // Drift from rep 2 (rep 1 lags), only for reps long enough for HR to mean
  // anything, and only when the set has a real last-vs-early comparison.
  let hrDrift: number | null = null;
  if (reps.length >= 3) {
    const r2 = reps[1].avgHeartRate;
    const rl = reps[reps.length - 1].avgHeartRate;
    if (r2 != null && rl != null && fastTime / reps.length >= 60) {
      hrDrift = round1(rl - r2);
    }
  }
  // Recovery drop: bout max HR → the following rest bout's time-weighted HR.
  const drops: number[] = [];
  bouts.forEach((b, i) => {
    const rests = (restAfterBout.get(i) ?? []).filter(
      (l) => l.avg_heart_rate != null && l.moving_time_seconds > 0,
    );
    if (rests.length === 0) return;
    const restTimeHr = rests.reduce((s, l) => s + l.moving_time_seconds, 0);
    const restHr = rests.reduce((s, l) => s + l.avg_heart_rate! * l.moving_time_seconds, 0) / restTimeHr;
    const boutMax = maxOrNull(b.laps.map((l) => l.max_heart_rate ?? l.avg_heart_rate ?? null));
    if (boutMax != null) drops.push(boutMax - restHr);
  });
  const recoveryDrop = drops.length
    ? round1(drops.reduce((a, b) => a + b, 0) / drops.length)
    : null;
  // Decoupling: efficiency (speed/HR) lost first half → second half of the
  // longest CONTINUOUS effort — a tempo/steady signal. Interval sessions
  // (no ≥15-min continuous bout of ≥2 laps) honestly read null.
  let decoupling: number | null = null;
  const longest = bouts.reduce((a, b) => (b.durationSeconds > a.durationSeconds ? b : a));
  if (longest.durationSeconds >= 900 && longest.laps.length >= 2) {
    const half = longest.durationSeconds / 2;
    let acc = 0;
    const firstHalf: WorkoutLap[] = [];
    const secondHalf: WorkoutLap[] = [];
    for (const l of longest.laps) {
      (acc < half ? firstHalf : secondHalf).push(l);
      acc += l.moving_time_seconds;
    }
    const eff = (ls: WorkoutLap[]): number | null => {
      const withHr = ls.filter((l) => l.avg_heart_rate != null && l.moving_time_seconds > 0 && l.distance_meters > 0);
      if (withHr.length === 0) return null;
      const time = withHr.reduce((s, l) => s + l.moving_time_seconds, 0);
      const dist = withHr.reduce((s, l) => s + l.distance_meters, 0);
      const hr = withHr.reduce((s, l) => s + l.avg_heart_rate! * l.moving_time_seconds, 0) / time;
      return hr > 0 ? (dist / time) / hr : null;
    };
    const e1 = eff(firstHalf);
    const e2 = eff(secondHalf);
    if (e1 != null && e2 != null && e1 > 0 && firstHalf.length > 0 && secondHalf.length > 0) {
      decoupling = round1(((e1 - e2) / e1) * 100);
    }
  }

  const heat = weather
    ? {
        tempF: weather.tempF,
        dewPointF: weather.dewPointF,
        adjustmentSecPerMile: neutralPace != null ? round1(avgPace - neutralPace) : 0,
      }
    : null;
  // Grade cost = the extra the terrain accounts for on top of heat, i.e. the
  // gap between the heat-only pace and the fully conditions-adjusted pace.
  // Emitted whenever the average grade OR the time it cost is meaningful — a
  // net-flat but rolling rep has ~0 avg grade yet still costs real seconds.
  const gradeAdjSecPerMile = conditionsPace != null
    ? round1((neutralPace ?? avgPace) - conditionsPace)
    : 0;
  const grade = (Math.abs(avgGradePct) > 0.1 || Math.abs(gradeAdjSecPerMile) >= 0.5)
    ? { avgGradePct: round1(avgGradePct), adjustmentSecPerMile: gradeAdjSecPerMile }
    : null;

  return {
    id: input.id,
    date: input.date,
    name: input.name ?? null,
    totalMiles: input.totalMiles != null && input.totalMiles > 0
      ? round2(input.totalMiles)
      : round2(laps.reduce((s, l) => s + l.distance_meters, 0) / METERS_PER_MILE),
    primarySystem,
    repCount: reps.length,
    fastMiles: round2(fastMiles),
    fastTimeSeconds: Math.round(fastTime),
    avgPaceSecPerMile: round1(avgPace),
    neutralPaceSecPerMile: neutralPace != null ? round1(neutralPace) : null,
    flatPaceSecPerMile: flatPace != null ? round1(flatPace) : null,
    conditionsPaceSecPerMile: conditionsPace != null ? round1(conditionsPace) : null,
    avgHeartRate: avgHR != null ? round1(avgHR) : null,
    maxHeartRate: maxHR,
    metersPerBeat: metersPerBeat != null ? round2(metersPerBeat) : null,
    restTimeSeconds: Math.round(restTime),
    avgRestSeconds: Math.round(avgRest),
    densityPct: round1(densityPct),
    workRestRatio: workRest != null ? round2(workRest) : null,
    avgRepMeters: Math.round(fastMeters / reps.length),
    avgRepSeconds: Math.round(fastTime / reps.length),
    elevationGainM: round1(elevation),
    hrDriftBpm: hrDrift,
    recoveryHrDropBpm: recoveryDrop,
    decouplingPct: decoupling,
    heat,
    grade,
    bySystem,
    reps,
  };
}

/** Group a session's reps by system into per-system volumes + volume reads. */
function buildSystemVolumes(reps: FastRep[]): SystemVolume[] {
  const groups = new Map<PaceSystem, FastRep[]>();
  for (const r of reps) {
    const g = groups.get(r.system) ?? [];
    g.push(r);
    groups.set(r.system, g);
  }
  const out: SystemVolume[] = [];
  for (const { system } of SYSTEM_ANCHORS) {
    const g = groups.get(system);
    if (!g || g.length === 0) continue;
    const meters = g.reduce((s, r) => s + r.distanceMeters, 0);
    const seconds = g.reduce((s, r) => s + r.durationSeconds, 0);
    const miles = meters / METERS_PER_MILE;
    const avgPace = miles > 0 ? seconds / miles : 0;
    const withHR = g.filter((r) => r.avgHeartRate != null);
    const hrDen = withHR.reduce((s, r) => s + r.durationSeconds, 0);
    const avgHR = hrDen > 0
      ? withHR.reduce((s, r) => s + r.avgHeartRate! * r.durationSeconds, 0) / hrDen
      : null;
    const nWithNeutral = g.filter((r) => r.neutralPaceSecPerMile != null);
    const neutral = nWithNeutral.length
      ? nWithNeutral.reduce((s, r) => s + r.neutralPaceSecPerMile! * r.distanceMiles, 0) /
        nWithNeutral.reduce((s, r) => s + r.distanceMiles, 0)
      : null;
    const nWithCond = g.filter((r) => r.conditionsPaceSecPerMile != null);
    const conditions = nWithCond.length
      ? nWithCond.reduce((s, r) => s + r.conditionsPaceSecPerMile! * r.distanceMiles, 0) /
        nWithCond.reduce((s, r) => s + r.distanceMiles, 0)
      : null;
    const nWithFlat = g.filter((r) => r.flatPaceSecPerMile != null);
    const flat = nWithFlat.length
      ? nWithFlat.reduce((s, r) => s + r.flatPaceSecPerMile! * r.distanceMiles, 0) /
        nWithFlat.reduce((s, r) => s + r.distanceMiles, 0)
      : null;
    const expected = SYSTEM_WORK_VOLUME_MILES[system];
    out.push({
      system,
      reps: g.length,
      workMiles: round2(miles),
      workSeconds: Math.round(seconds),
      avgPaceSecPerMile: round1(avgPace),
      neutralPaceSecPerMile: neutral != null ? round1(neutral) : null,
      flatPaceSecPerMile: flat != null ? round1(flat) : null,
      conditionsPaceSecPerMile: conditions != null ? round1(conditions) : null,
      avgHeartRate: avgHR != null ? round1(avgHR) : null,
      expectedMiles: expected,
      volumeStatus: volumeStatus(miles, expected),
    });
  }
  return out;
}

/**
 * Analyze many key sessions and group their fast work BY SYSTEM for like-for-
 * like trending. A mixed session appears in every system it touched, so its
 * mile-pace work trends against other mile work and its 10K work against other
 * 10K work — never against each other.
 */
export function analyzeFastSegmentTrends(
  inputs: KeySessionInput[],
  zones: ZoneTable,
): FastSegmentTrends {
  const sessions = (inputs ?? [])
    .map((s) => analyzeKeySession(s, zones))
    .filter((m): m is KeySessionMetrics => m !== null)
    .sort((a, b) => a.date.localeCompare(b.date));

  const bySystem = new Map<PaceSystem, SystemTrendPoint[]>();
  for (const s of sessions) {
    for (const sv of s.bySystem) {
      // Keep incidental work out of a system's trend: a run only lands on the
      // HMP line if it did a real HMP chunk, not 0.6 mi of it inside a 5K day.
      if (sv.workMiles < minSystemMiles(sv.system)) continue;
      const pts = bySystem.get(sv.system) ?? [];
      pts.push({
        sessionId: s.id,
        date: s.date,
        sessionName: s.name,
        reps: sv.reps,
        workMiles: sv.workMiles,
        totalMiles: s.totalMiles,
        avgPaceSecPerMile: sv.avgPaceSecPerMile,
        neutralPaceSecPerMile: sv.neutralPaceSecPerMile,
        flatPaceSecPerMile: sv.flatPaceSecPerMile,
        conditionsPaceSecPerMile: sv.conditionsPaceSecPerMile,
        avgHeartRate: sv.avgHeartRate,
        volumeStatus: sv.volumeStatus,
      });
      bySystem.set(sv.system, pts);
    }
  }

  const systems: SystemTrend[] = [];
  for (const { system } of SYSTEM_ANCHORS) {
    const points = bySystem.get(system);
    if (!points || points.length === 0) continue;
    points.sort((a, b) => a.date.localeCompare(b.date));
    systems.push({ system, expectedMiles: SYSTEM_WORK_VOLUME_MILES[system], points });
  }

  return { sessions, systems };
}

// ── Helpers ────────────────────────────────────────────────────

function timeWeightedHR(laps: WorkoutLap[]): number | null {
  const withHR = laps.filter((l) => l.avg_heart_rate != null && l.moving_time_seconds > 0);
  if (withHR.length === 0) return null;
  const num = withHR.reduce((s, l) => s + l.avg_heart_rate! * l.moving_time_seconds, 0);
  const den = withHR.reduce((s, l) => s + l.moving_time_seconds, 0);
  return den > 0 ? Math.round(num / den) : null;
}

function maxOrNull(xs: Array<number | null>): number | null {
  const vals = xs.filter((x): x is number => typeof x === "number");
  return vals.length ? Math.max(...vals) : null;
}

/**
 * Average gradient (%) of a bout. Prefers per-lap `avg_grade_pct` (accurate —
 * feed it from the altitude stream), distance-weighted. Falls back to NET grade
 * = total_elevation_gain / distance, which only sees ascent, so rolling terrain
 * reads a touch steep — still a better answer than ignoring hills. The grade
 * model (pace-grade-adjustment.ts) clamps extremes downstream.
 */
function boutGradePct(laps: WorkoutLap[], distanceMeters: number): number {
  const withGrade = laps.filter((l) => typeof l.avg_grade_pct === "number");
  if (withGrade.length) {
    const den = withGrade.reduce((s, l) => s + l.distance_meters, 0);
    if (den > 0) {
      return withGrade.reduce(
        (s, l) => s + (l.avg_grade_pct as number) * l.distance_meters,
        0,
      ) / den;
    }
  }
  const gain = laps.reduce((s, l) => s + (l.total_elevation_gain ?? 0), 0);
  return distanceMeters > 0 ? (gain / distanceMeters) * 100 : 0;
}

/** All valid grade micro-segments across a bout's laps (split-grade input). */
function collectGradeSegments(laps: WorkoutLap[]): RunSegment[] {
  const out: RunSegment[] = [];
  for (const l of laps) {
    const segs = l.grade_segments;
    if (!segs) continue;
    for (const s of segs) {
      if (s && typeof s.seconds === "number" && s.seconds > 0 && typeof s.gradePct === "number") {
        out.push({ seconds: s.seconds, gradePct: s.gradePct });
      }
    }
  }
  return out;
}

/** Time-weighted mean gradient (%) over a segment profile — the displayed grade. */
function timeWeightedGrade(segs: RunSegment[]): number {
  const t = segs.reduce((a, s) => a + s.seconds, 0);
  if (t <= 0) return 0;
  return segs.reduce((a, s) => a + s.gradePct * s.seconds, 0) / t;
}

/**
 * Dew point (°F) from temperature (°F) + relative humidity (%). Magnus formula.
 * A convenience for callers that only have RH (the heat model wants dew point).
 */
export function dewPointF(tempF: number, relativeHumidityPct: number): number {
  const tC = (tempF - 32) * (5 / 9);
  const rh = Math.min(100, Math.max(1, relativeHumidityPct));
  const a = 17.625, b = 243.04;
  const gamma = Math.log(rh / 100) + (a * tC) / (b + tC);
  const dpC = (b * gamma) / (a - gamma);
  return Math.round((dpC * (9 / 5) + 32) * 10) / 10;
}

function round1(x: number): number { return Math.round(x * 10) / 10; }
function round2(x: number): number { return Math.round(x * 100) / 100; }

/** Format seconds/mile as "M:SS/mi" — mirrors weeklyAnalytics.formatPace. */
export function formatPace(secondsPerMile: number): string {
  if (secondsPerMile <= 0 || secondsPerMile > 1200) return "--:--";
  const total = Math.round(secondsPerMile);
  const m = Math.floor(total / 60);
  const s = total % 60;
  return `${m}:${s.toString().padStart(2, "0")}/mi`;
}

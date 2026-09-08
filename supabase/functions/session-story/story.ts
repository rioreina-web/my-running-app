/**
 * Session Story — pure per-session narrative data builder.
 *
 * One key session, told whole: the fast segments (or halves, for sustained
 * work) with heart rate, raw + heat-neutral + conditions-adjusted pace, the
 * drift read, the day's conditions, and the athlete's own words (voice memo +
 * niggles) — everything the SessionStoryView needs for one screen, plus the
 * same block for an optional comparison session so the client can diff them.
 *
 * Pure: no IO, no LLM, no side effects — `index.ts` owns the fetching. The
 * heavy analysis is REUSED, not reimplemented:
 *   • rep sessions   → `_shared/fast-segment-trends.ts` `analyzeKeySession`
 *     (per-rep adjusted paces, HR drift, density, meters/beat)
 *   • sustained work → halves math here, with the same heat model
 *     (`pace-heat-adjustment.ts`) and grade model (`pace-grade-adjustment.ts`)
 *     the fast-segment path uses, so the two kinds never disagree on a model.
 *
 * Design invariants (CLAUDE.md):
 *   • Adjustments are models, not measurements — raw pace is always present
 *     and adjusted paces ride alongside, never replace.
 *   • Degrade honestly: no laps → no segments; no HR → no drift; short reps →
 *     drift explicitly marked not meaningful (never a fake number).
 *   • Niggles are surfaced verbatim, never interpreted (closed vocabulary
 *     upstream in `body_mentions`; this module only carries the quotes).
 */

import {
  analyzeKeySession,
  type KeySessionInput,
  type KeySessionMetrics,
  type WorkoutLap,
} from "../_shared/fast-segment-trends.ts";
import { heatAdjustmentPct, repLengthFactor } from "../_shared/pace-heat-adjustment.ts";
import { gradeAdjustRun, type RunSegment } from "../_shared/pace-grade-adjustment.ts";
import type { ZoneTable } from "../_shared/quality-volume.ts";
import {
  GRADE_NOISE_DEADBAND_PCT,
  sliceGradeSegments,
  type FSStream,
} from "../trends-timeline/fastSegments.ts";

// ─── Inputs ────────────────────────────────────────────────────────────

/** A `running_workout_laps` row (the same select as `trends-timeline`). */
export interface StoryLapRow {
  lap_index?: number | null;
  is_rest?: boolean | null;
  distance_meters?: number | null;
  avg_pace_sec_per_mile?: number | null;
  moving_time_seconds?: number | null;
  avg_heart_rate?: number | null;
  max_heart_rate?: number | null;
  total_elevation_gain?: number | null;
  stream_start_index?: number | null;
  stream_end_index?: number | null;
}

/** The `training_logs` fields the story reads (one row, already fetched). */
export interface StoryLogRow {
  id: string;
  workout_date: string;
  workout_distance_miles?: number | null;
  workout_duration_minutes?: number | null;
  notes?: string | null;
  cleaned_notes?: string | null;
  mood?: string | null;
  weather_actual?: { temp_f?: unknown; dew_point_f?: unknown } | null;
}

/** A `body_mentions` row scoped to the session's date window. */
export interface StoryMentionRow {
  body_area: string;
  side?: string | null;
  severity_hint?: string | null;
  verbatim_quote?: string | null;
}

export interface StorySessionInput {
  log: StoryLogRow;
  laps: StoryLapRow[];
  /** `workout_features.workout_structure` — "5K 5×1km · 6.0 mi" style. */
  structure?: string | null;
  /** Per-second altitude stream, when the log carries one (lazy path — this
   *  endpoint is per-session, so the blob cost trends-timeline refused to pay
   *  is fine here). */
  stream?: FSStream | null;
  mentions: StoryMentionRow[];
}

// ─── Output (snake_case, mirrors the iOS DTO) ──────────────────────────

export interface StorySegmentOut {
  label: string; // "R1" … / "1st half" / "2nd half" / "Last 2 mi"
  pace_sec: number;
  hr: number | null;
  distance_m: number | null;
}

export interface StoryOut {
  log_id: string;
  date: string; // "YYYY-MM-DD"
  name: string;
  kind: "reps" | "sustained";
  total_miles: number | null;
  duration_min: number | null;
  segments: StorySegmentOut[];
  avg_pace_sec: number | null; // work pace (reps) / whole-run pace (sustained)
  neutral_pace_sec: number | null; // heat removed
  conditions_pace_sec: number | null; // heat + grade removed
  heat: { temp_f: number; dew_f: number; cost_sec_per_mi: number } | null;
  grade: {
    avg_grade_pct: number | null;
    elev_gain_m: number;
    cost_sec_per_mi: number | null;
  } | null;
  hr: { avg: number; max: number | null; meters_per_beat: number | null } | null;
  drift: {
    kind: "reps" | "decoupling";
    value: number; // bpm (reps) or % (decoupling)
    meaningful: boolean;
    note: string; // why not meaningful, when it isn't ("short reps", …)
  } | null;
  /** Back-half fade, sec/mi. Reps: last-third mean − first-third mean.
   *  Sustained: 2nd-half pace − 1st-half pace. Positive = slowing. */
  fade_sec_per_mi: number | null;
  memo: { text: string; mood: string | null } | null;
  niggles: Array<{
    body_area: string;
    side: string | null;
    severity_hint: string | null;
    quote: string | null;
  }>;
}

// ─── Constants ─────────────────────────────────────────────────────────

const METERS_PER_MILE = 1609.344;
const LAST_SEGMENT_MILES = 2;
/** Sustained decoupling needs this much moving time to mean anything. */
const MIN_DECOUPLING_MINUTES = 20;
/** …and at least this many HR-carrying laps per half. */
const MIN_DECOUPLING_HR_LAPS = 4;
/** Memos shorter than this are auto-titles ("Morning Run"), not words. */
const MIN_MEMO_CHARS = 20;
const GENERIC_MEMO = /^(morning|afternoon|evening|lunch|night)\s+run$/i;

// ─── Entry point ───────────────────────────────────────────────────────

/**
 * Build one session's story block. Never throws on bad rows — a session with
 * nothing classifiable still returns its date, memo, and niggles, with empty
 * segments (the client shows what exists and no more).
 */
export function buildStory(input: StorySessionInput, zones: ZoneTable): StoryOut {
  const { log } = input;
  const laps = (input.laps ?? []).filter(
    (l) => Number(l.moving_time_seconds ?? 0) > 0,
  );
  const weather = readWeather(log);

  const base: StoryOut = {
    log_id: log.id,
    date: String(log.workout_date).slice(0, 10),
    name: input.structure?.trim() || fallbackName(log),
    kind: "sustained",
    total_miles: log.workout_distance_miles ?? null,
    duration_min: log.workout_duration_minutes != null
      ? Math.round(Number(log.workout_duration_minutes))
      : null,
    segments: [],
    avg_pace_sec: null,
    neutral_pace_sec: null,
    conditions_pace_sec: null,
    heat: null,
    grade: null,
    hr: null,
    drift: null,
    fade_sec_per_mi: null,
    memo: readMemo(log),
    niggles: (input.mentions ?? []).map((m) => ({
      body_area: m.body_area,
      side: m.side ?? null,
      severity_hint: m.severity_hint ?? null,
      quote: m.verbatim_quote ?? null,
    })),
  };
  if (laps.length === 0) return base;

  // Try the rep path first: `analyzeKeySession` returns null when the session
  // has no MP-or-faster work, which is exactly the sustained case.
  const metrics = analyzeKeySession(toKeySessionInput(input, laps, weather), zones);
  return metrics ? repsStory(base, metrics) : sustainedStory(base, input, laps, weather);
}

// ─── Reps path (interval / threshold sessions) ─────────────────────────

function repsStory(base: StoryOut, m: KeySessionMetrics): StoryOut {
  const paces = m.reps.map((r) => r.paceSecPerMile);
  return {
    ...base,
    kind: "reps",
    segments: m.reps.map((r) => ({
      label: `R${r.index}`, // FastRep.index is already 1-based
      pace_sec: Math.round(r.paceSecPerMile),
      hr: r.avgHeartRate != null ? Math.round(r.avgHeartRate) : null,
      distance_m: Math.round(r.distanceMeters),
    })),
    avg_pace_sec: Math.round(m.avgPaceSecPerMile),
    neutral_pace_sec: m.neutralPaceSecPerMile != null ? Math.round(m.neutralPaceSecPerMile) : null,
    conditions_pace_sec: m.conditionsPaceSecPerMile != null
      ? Math.round(m.conditionsPaceSecPerMile)
      : null,
    heat: m.heat
      ? {
        temp_f: Math.round(m.heat.tempF),
        dew_f: Math.round(m.heat.dewPointF),
        cost_sec_per_mi: Math.round(m.heat.adjustmentSecPerMile),
      }
      : null,
    grade: {
      avg_grade_pct: m.grade?.avgGradePct ?? null,
      elev_gain_m: Math.round(m.elevationGainM),
      cost_sec_per_mi: m.grade != null ? Math.round(m.grade.adjustmentSecPerMile) : null,
    },
    hr: m.avgHeartRate != null
      ? {
        avg: Math.round(m.avgHeartRate),
        max: m.maxHeartRate != null ? Math.round(m.maxHeartRate) : null,
        meters_per_beat: m.metersPerBeat,
      }
      : null,
    drift: repsDrift(m),
    fade_sec_per_mi: thirdsFade(paces),
  };
}

/** The analyzer already nulls drift for < 3 reps / no HR / short reps — carry
 *  that honesty forward as an explicit `meaningful` flag with a reason. */
function repsDrift(m: KeySessionMetrics): StoryOut["drift"] {
  if (m.hrDriftBpm != null) {
    return { kind: "reps", value: m.hrDriftBpm, meaningful: true, note: "" };
  }
  if (m.avgHeartRate == null) return null; // no HR at all → nothing to say
  const note = m.avgRepSeconds > 0 && m.avgRepSeconds < 60
    ? "Short reps with full recoveries — HR swings with the rest, not the effort."
    : "Not enough reps with heart rate to read a drift.";
  return { kind: "reps", value: 0, meaningful: false, note };
}

/** Mean(last third) − mean(first third), sec/mi. null with < 3 values. */
export function thirdsFade(paces: number[]): number | null {
  const clean = paces.filter((p) => p > 0);
  if (clean.length < 3) return null;
  const third = Math.max(1, Math.floor(clean.length / 3));
  const mean = (xs: number[]) => xs.reduce((a, b) => a + b, 0) / xs.length;
  return round1(mean(clean.slice(-third)) - mean(clean.slice(0, third)));
}

// ─── Sustained path (long runs, steady work — no MP+ laps) ─────────────

function sustainedStory(
  base: StoryOut,
  input: StorySessionInput,
  laps: StoryLapRow[],
  weather: { tempF: number; dewPointF: number } | null,
): StoryOut {
  const halves = splitHalvesByTime(laps);
  const wholePace = distanceWeightedPace(laps);
  if (wholePace == null) return base; // nothing classifiable — degrade honestly

  // Heat: continuous running gets the full table adjustment (repLengthFactor
  // of an unknown/long bout is 1.0 — same rule the fast path applies per bout).
  let heat: StoryOut["heat"] = null;
  let neutral: number | null = null;
  let heatPct = 0;
  if (weather) {
    heatPct = heatAdjustmentPct(weather.tempF, weather.dewPointF) * repLengthFactor(null);
    if (heatPct > 0) {
      neutral = Math.round(wholePace / (1 + heatPct));
      heat = {
        temp_f: Math.round(weather.tempF),
        dew_f: Math.round(weather.dewPointF),
        cost_sec_per_mi: Math.round(wholePace - wholePace / (1 + heatPct)),
      };
    } else {
      heat = { temp_f: Math.round(weather.tempF), dew_f: Math.round(weather.dewPointF), cost_sec_per_mi: 0 };
      neutral = Math.round(wholePace);
    }
  }

  // Grade: split-grade from the altitude stream when present (the lazy path
  // can afford it), else net grade per lap with the same GPS-noise deadband
  // the timeline uses.
  const gradeSegs = gradeSegments(input, laps);
  let grade: StoryOut["grade"] = null;
  let flatRatio = 1;
  const elevGain = laps.reduce((a, l) => a + Math.max(0, Number(l.total_elevation_gain ?? 0)), 0);
  if (gradeSegs.length > 0) {
    const adj = gradeAdjustRun(gradeSegs);
    if (adj.rawSeconds > 0) {
      flatRatio = adj.adjustedSeconds / adj.rawSeconds;
      const costSecPerMi = Math.round(wholePace - wholePace * flatRatio);
      const distM = laps.reduce((a, l) => a + Number(l.distance_meters ?? 0), 0);
      const avgGrade = gradeSegs.reduce((a, s) => a + s.gradePct * s.seconds, 0) /
        adj.rawSeconds;
      grade = {
        avg_grade_pct: distM > 0 ? round2(avgGrade) : null,
        elev_gain_m: Math.round(elevGain),
        cost_sec_per_mi: costSecPerMi,
      };
    }
  }
  if (grade == null) grade = { avg_grade_pct: null, elev_gain_m: Math.round(elevGain), cost_sec_per_mi: null };

  // Conditions = both models removed, applied to the whole-run pace.
  const conditions = (neutral != null || flatRatio !== 1)
    ? Math.round(wholePace * flatRatio / (1 + heatPct))
    : null;

  const segments: StorySegmentOut[] = [];
  if (halves) {
    segments.push(
      { label: "1st half", pace_sec: Math.round(halves.pace1), hr: halves.hr1, distance_m: Math.round(halves.dist1) },
      { label: "2nd half", pace_sec: Math.round(halves.pace2), hr: halves.hr2, distance_m: Math.round(halves.dist2) },
    );
    const tail = lastMilesPace(laps, LAST_SEGMENT_MILES);
    if (tail != null) {
      segments.push({
        label: `Last ${LAST_SEGMENT_MILES} mi`,
        pace_sec: Math.round(tail.pace),
        hr: tail.hr,
        distance_m: Math.round(tail.distM),
      });
    }
  }

  const hrVals = laps.filter((l) => Number(l.avg_heart_rate ?? 0) > 0);
  const avgHr = timeWeightedHr(laps);
  const maxHr = hrVals.reduce(
    (a, l) => Math.max(a, Number(l.max_heart_rate ?? l.avg_heart_rate ?? 0)),
    0,
  );
  const totalSecs = laps.reduce((a, l) => a + Number(l.moving_time_seconds ?? 0), 0);
  const totalM = laps.reduce((a, l) => a + Number(l.distance_meters ?? 0), 0);
  const beats = avgHr != null ? (avgHr / 60) * totalSecs : 0;

  return {
    ...base,
    kind: "sustained",
    segments,
    avg_pace_sec: Math.round(wholePace),
    neutral_pace_sec: neutral,
    conditions_pace_sec: conditions,
    heat,
    grade,
    hr: avgHr != null
      ? {
        avg: Math.round(avgHr),
        max: maxHr > 0 ? Math.round(maxHr) : null,
        meters_per_beat: beats > 0 ? round2(totalM / beats) : null,
      }
      : null,
    drift: sustainedDrift(laps, halves, totalSecs),
    fade_sec_per_mi: halves ? round1(halves.pace2 - halves.pace1) : null,
  };
}

/** Aerobic decoupling: efficiency (speed per beat) first half → second half,
 *  as % lost. Same construction as the fast-segment analyzer's continuous
 *  read, gated on enough time and enough HR coverage to mean anything. */
export function sustainedDrift(
  laps: StoryLapRow[],
  halves: Halves | null,
  totalSecs: number,
): StoryOut["drift"] {
  if (!halves) return null;
  const hrLaps = laps.filter((l) => Number(l.avg_heart_rate ?? 0) > 0).length;
  if (halves.hr1 == null || halves.hr2 == null) return null;
  if (totalSecs < MIN_DECOUPLING_MINUTES * 60 || hrLaps < MIN_DECOUPLING_HR_LAPS * 2) {
    return {
      kind: "decoupling",
      value: 0,
      meaningful: false,
      note: "Too short (or too little heart rate) for a decoupling read.",
    };
  }
  // efficiency = speed / HR (m/s per bpm); loss % = (e1 − e2) / e1 × 100
  const eff = (paceSecPerMi: number, hr: number) =>
    (METERS_PER_MILE / paceSecPerMi) / hr;
  const e1 = eff(halves.pace1, halves.hr1);
  const e2 = eff(halves.pace2, halves.hr2);
  if (!(e1 > 0)) return null;
  return {
    kind: "decoupling",
    value: round1(((e1 - e2) / e1) * 100),
    meaningful: true,
    note: "",
  };
}

// ─── Halves / tail math ────────────────────────────────────────────────

export interface Halves {
  pace1: number;
  pace2: number;
  hr1: number | null;
  hr2: number | null;
  dist1: number;
  dist2: number;
}

/** Split laps into two halves by cumulative moving time; per-half
 *  distance-weighted pace + time-weighted HR. null with < 2 usable laps. */
export function splitHalvesByTime(laps: StoryLapRow[]): Halves | null {
  const usable = laps.filter(
    (l) => Number(l.moving_time_seconds ?? 0) > 0 && Number(l.distance_meters ?? 0) > 0,
  );
  if (usable.length < 2) return null;
  const total = usable.reduce((a, l) => a + Number(l.moving_time_seconds), 0);
  const half = total / 2;
  const first: StoryLapRow[] = [];
  const second: StoryLapRow[] = [];
  let acc = 0;
  for (const l of usable) {
    (acc < half ? first : second).push(l);
    acc += Number(l.moving_time_seconds);
  }
  if (first.length === 0 || second.length === 0) return null;
  const p1 = distanceWeightedPace(first);
  const p2 = distanceWeightedPace(second);
  if (p1 == null || p2 == null) return null;
  return {
    pace1: p1,
    pace2: p2,
    hr1: roundOrNull(timeWeightedHr(first)),
    hr2: roundOrNull(timeWeightedHr(second)),
    dist1: first.reduce((a, l) => a + Number(l.distance_meters), 0),
    dist2: second.reduce((a, l) => a + Number(l.distance_meters), 0),
  };
}

/** Pace + HR over the final `miles` of the run (from the lap tail). */
export function lastMilesPace(
  laps: StoryLapRow[],
  miles: number,
): { pace: number; hr: number | null; distM: number } | null {
  const targetM = miles * METERS_PER_MILE;
  const tail: StoryLapRow[] = [];
  let accM = 0;
  for (let i = laps.length - 1; i >= 0 && accM < targetM; i--) {
    const l = laps[i];
    if (Number(l.distance_meters ?? 0) <= 0) continue;
    tail.unshift(l);
    accM += Number(l.distance_meters);
  }
  if (accM < targetM * 0.6) return null; // not enough tail to call it "last 2 mi"
  const pace = distanceWeightedPace(tail);
  if (pace == null) return null;
  return { pace, hr: roundOrNull(timeWeightedHr(tail)), distM: accM };
}

// ─── Small shared helpers ──────────────────────────────────────────────

function toKeySessionInput(
  input: StorySessionInput,
  laps: StoryLapRow[],
  weather: { tempF: number; dewPointF: number } | null,
): KeySessionInput {
  const stream = input.stream ?? null;
  return {
    id: input.log.id,
    date: String(input.log.workout_date).slice(0, 10),
    name: input.structure?.trim() || undefined,
    totalMiles: input.log.workout_distance_miles ?? null,
    weather,
    laps: laps.map((l): WorkoutLap => {
      const base: WorkoutLap = {
        distance_meters: Number(l.distance_meters ?? 0),
        moving_time_seconds: Number(l.moving_time_seconds ?? 0),
        avg_pace_sec_per_mile: l.avg_pace_sec_per_mile != null ? Number(l.avg_pace_sec_per_mile) : null,
        avg_heart_rate: l.avg_heart_rate != null ? Number(l.avg_heart_rate) : null,
        max_heart_rate: l.max_heart_rate != null ? Number(l.max_heart_rate) : null,
        total_elevation_gain: l.total_elevation_gain != null ? Number(l.total_elevation_gain) : null,
      };
      if (stream && l.stream_start_index != null && l.stream_end_index != null) {
        const segs = sliceGradeSegments(stream, Number(l.stream_start_index), Number(l.stream_end_index));
        if (segs.length > 0) return { ...base, grade_segments: segs };
      }
      return base;
    }),
  };
}

/** Grade micro-segments for the whole sustained run: stream slices per lap
 *  when indices exist, else per-lap NET grade with the GPS-noise deadband. */
function gradeSegments(input: StorySessionInput, laps: StoryLapRow[]): RunSegment[] {
  const out: RunSegment[] = [];
  const stream = input.stream ?? null;
  for (const l of laps) {
    const secs = Number(l.moving_time_seconds ?? 0);
    const distM = Number(l.distance_meters ?? 0);
    if (secs <= 0 || distM <= 0) continue;
    if (stream && l.stream_start_index != null && l.stream_end_index != null) {
      const segs = sliceGradeSegments(stream, Number(l.stream_start_index), Number(l.stream_end_index));
      if (segs.length > 0) {
        out.push(...segs.map((s) => ({ seconds: s.seconds, gradePct: s.gradePct })));
        continue;
      }
    }
    // Net-grade fallback: gain / distance. Only sees ascent (matches the
    // timeline's documented fallback), deadbanded against GPS noise.
    const gain = Number(l.total_elevation_gain ?? 0);
    let g = distM > 0 ? (gain / distM) * 100 : 0;
    if (Math.abs(g) < GRADE_NOISE_DEADBAND_PCT) g = 0;
    out.push({ seconds: secs, gradePct: round2(g), meters: distM });
  }
  return out;
}

export function distanceWeightedPace(laps: StoryLapRow[]): number | null {
  let w = 0;
  let acc = 0;
  for (const l of laps) {
    const distMi = Number(l.distance_meters ?? 0) / METERS_PER_MILE;
    const secs = Number(l.moving_time_seconds ?? 0);
    const stated = l.avg_pace_sec_per_mile != null ? Number(l.avg_pace_sec_per_mile) : null;
    const pace = stated != null && stated > 0 ? stated : distMi > 0 && secs > 0 ? secs / distMi : null;
    if (pace == null || distMi <= 0) continue;
    w += distMi;
    acc += pace * distMi;
  }
  return w > 0 ? acc / w : null;
}

export function timeWeightedHr(laps: StoryLapRow[]): number | null {
  let t = 0;
  let acc = 0;
  for (const l of laps) {
    const hr = Number(l.avg_heart_rate ?? 0);
    const secs = Number(l.moving_time_seconds ?? 0);
    if (hr <= 0 || secs <= 0) continue;
    t += secs;
    acc += hr * secs;
  }
  return t > 0 ? acc / t : null;
}

function readWeather(log: StoryLogRow): { tempF: number; dewPointF: number } | null {
  const w = log.weather_actual;
  if (!w) return null;
  const t = w.temp_f, dp = w.dew_point_f;
  return typeof t === "number" && typeof dp === "number" ? { tempF: t, dewPointF: dp } : null;
}

/** The memo, gated so auto-titles ("Morning Run") never masquerade as words. */
export function readMemo(log: StoryLogRow): { text: string; mood: string | null } | null {
  const raw = (log.cleaned_notes ?? log.notes ?? "").trim();
  if (raw.length < MIN_MEMO_CHARS || GENERIC_MEMO.test(raw)) {
    return null;
  }
  return { text: raw, mood: log.mood ?? null };
}

function fallbackName(log: StoryLogRow): string {
  const mi = log.workout_distance_miles;
  return mi && mi > 0 ? `${Math.round(mi * 10) / 10} mi` : "Session";
}

function roundOrNull(v: number | null): number | null {
  return v != null ? Math.round(v) : null;
}
function round1(v: number): number {
  return Math.round(v * 10) / 10;
}
function round2(v: number): number {
  return Math.round(v * 100) / 100;
}

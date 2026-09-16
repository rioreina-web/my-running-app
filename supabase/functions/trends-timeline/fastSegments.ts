/**
 * Fast segments — the trends-timeline adapter.
 *
 * Turns the same rep-level laps + pace zones the Key Sessions surface uses into
 * the SYSTEM-aware fast-segment payload (volume vs. each system's range,
 * conditions-adjusted pace, mixed-session breakdown). All the real work lives in
 * the tested `_shared/fast-segment-trends.ts`; this file only:
 *   1. adapts the DB rows into that module's input shape, and
 *   2. serialises its output to a snake_case, iOS-token DTO (mile|3k|5k|10k|
 *      hmp|mp — LT folds into HMP to match `KeySession.zone`).
 *
 * Pure, additive, and defensive: a bad row or a missing zone table yields an
 * empty payload, never a thrown timeline.
 */

import {
  analyzeFastSegmentTrends,
  type KeySessionInput,
  type PaceSystem,
  type SystemVolume,
} from "../_shared/fast-segment-trends.ts";
import type { ZoneTable } from "../_shared/quality-volume.ts";

/** The lap columns this adapter reads (superset of the Key Sessions select). */
export interface FSLapRow {
  distance_meters?: number | null;
  moving_time_seconds?: number | null;
  avg_pace_sec_per_mile?: number | null;
  avg_heart_rate?: number | null;
  max_heart_rate?: number | null;
  total_elevation_gain?: number | null;
  /** Indices into the per-second streams — used to slice split grade per rep. */
  stream_start_index?: number | null;
  stream_end_index?: number | null;
}

export interface FSWeather {
  tempF: number;
  dewPointF: number;
}

/** A workout's per-second streams (from `training_logs.external_streams`). */
export interface FSStream {
  time: number[];      // seconds
  distance: number[];  // cumulative metres
  altitude: number[];  // metres
}

/**
 * Grades with |g| below this are treated as FLAT. GPS altitude wobbles ±1–2 m,
 * which over a chunk fabricates 1–3% micro-grades on flat ground — and because
 * the grade model damps downhill credit (correct for real terrain), that noise
 * doesn't cancel: flat runs read as net "hill cost" and earn a fake adjustment.
 * The deadband kills the noise while real hills (≥1%) still count.
 */
export const GRADE_NOISE_DEADBAND_PCT = 1.0;

/**
 * Chunk length for the grade slice, in metres.
 *
 * A chunk's grade is (alt[end] − alt[start]) / chunkMeters, so the noise in
 * that grade scales as 1/chunkMeters while a REAL hill's grade does not —
 * genuine terrain holds its gradient over hundreds of metres. Widening 100 →
 * 200 m therefore halves the fabricated grade without blunting real hills.
 * (2026-08-06: a flat track was reading +7 s/mi of "hill cost" at 100 m.)
 */
export const GRADE_CHUNK_METERS = 200;

/**
 * Half-width, in samples, of the centred moving average applied to altitude
 * before grades are measured. Streams are ~1 Hz, so ±7 samples ≈ 15 s ≈ 60–80 m
 * of running — shorter than any real grade feature, longer than GPS/barometric
 * wobble. Averaging 15 samples cuts the altitude noise by ≈ √15 (~4×).
 *
 * The window SHRINKS symmetrically at the ends of the slice (see
 * `smoothAltitudeWindow`) so a steady climb is reproduced exactly rather than
 * flattened at its edges.
 */
export const ALTITUDE_SMOOTH_HALF_WINDOW = 7;

/**
 * Centred moving average of `alt` over [a, b], with a symmetrically shrinking
 * window at the edges. Symmetry matters: on a linear ramp a symmetric mean
 * returns the exact centre value, so smoothing a real climb does not change
 * its measured gradient — only the noise around it.
 */
export function smoothAltitudeWindow(
  alt: number[],
  a: number,
  b: number,
  halfWindow = ALTITUDE_SMOOTH_HALF_WINDOW,
): number[] {
  const out = new Array<number>(b - a + 1);
  for (let i = a; i <= b; i++) {
    const h = Math.min(halfWindow, i - a, b - i);
    if (h <= 0) { out[i - a] = alt[i]; continue; }
    let sum = 0;
    for (let k = i - h; k <= i + h; k++) sum += alt[k];
    out[i - a] = sum / (2 * h + 1);
  }
  return out;
}

/**
 * Slice a rep's window of the altitude stream into ~`chunkMeters` grade
 * segments (`{seconds, gradePct}`) for split-grade adjustment.
 *
 * Three layers of noise control, in order: the altitude is smoothed (centred,
 * edge-symmetric), grades are measured over ~200 m chunks, and sub-deadband
 * grades are zeroed. All three exist because the grade model damps downhill
 * credit — correct for real terrain, but it means zero-mean GPS noise does NOT
 * cancel out, it accumulates as phantom hill cost. Grade is clamped to ±30%
 * (matches the grade model).
 */
export function sliceGradeSegments(
  stream: FSStream,
  startIdx: number,
  endIdx: number,
  chunkMeters = GRADE_CHUNK_METERS,
): Array<{ seconds: number; gradePct: number }> {
  const { time, distance, altitude } = stream;
  const n = Math.min(time.length, distance.length, altitude.length);
  const a = Math.max(0, Math.trunc(startIdx));
  const b = Math.min(Math.trunc(endIdx), n - 1);
  if (!(b > a)) return [];
  const alt = smoothAltitudeWindow(altitude, a, b);
  const out: Array<{ seconds: number; gradePct: number }> = [];
  let i = a;
  while (i < b) {
    let j = i + 1;
    while (j < b && (distance[j] - distance[i]) < chunkMeters) j++;
    const dd = distance[j] - distance[i];
    const dt = time[j] - time[i];
    if (dd > 0 && dt > 0) {
      let g = ((alt[j - a] - alt[i - a]) / dd) * 100;
      if (g > 30) g = 30; else if (g < -30) g = -30;
      if (Math.abs(g) < GRADE_NOISE_DEADBAND_PCT) g = 0; // GPS-noise floor
      out.push({ seconds: dt, gradePct: Math.round(g * 100) / 100 });
    }
    i = j;
  }
  return out;
}

export interface FSLog {
  id: string;
  workout_date: string;
  workout_distance_miles: number | null;
}

/** TS system label → the iOS zone token. LT folds into HMP at the surface. */
const SYSTEM_TOKEN: Record<PaceSystem, string> = {
  MP: "mp",
  HMP: "hmp",
  LT: "hmp",
  "10K": "10k",
  "5K": "5k",
  "3K": "3k",
  Mile: "mile",
};

const MONTH = [
  "Jan", "Feb", "Mar", "Apr", "May", "Jun",
  "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
];

/** "2026-06-23" → "Jun 23"; passes the raw string through if unparseable. */
function labelISO(iso: string): string {
  const [y, m, d] = iso.split("-").map(Number);
  return (m >= 1 && m <= 12 && d) ? `${MONTH[m - 1]} ${d}` : iso;
}

function volumeDTO(sv: SystemVolume) {
  return {
    system: SYSTEM_TOKEN[sv.system],
    reps: sv.reps,
    work_miles: sv.workMiles,
    avg_pace_sec: Math.round(sv.avgPaceSecPerMile),
    neutral_pace_sec: sv.neutralPaceSecPerMile != null ? Math.round(sv.neutralPaceSecPerMile) : null,
    flat_pace_sec: sv.flatPaceSecPerMile != null ? Math.round(sv.flatPaceSecPerMile) : null,
    conditions_pace_sec: sv.conditionsPaceSecPerMile != null ? Math.round(sv.conditionsPaceSecPerMile) : null,
    avg_hr: sv.avgHeartRate != null ? Math.round(sv.avgHeartRate) : null,
    volume_status: sv.volumeStatus,
  };
}

/**
 * Build the `fast_segments` response payload from the same inputs the Key
 * Sessions surface already has in hand.
 */
export function buildFastSegments(
  logs: FSLog[],
  lapsByWorkout: Map<string, FSLapRow[]>,
  featuresById: Map<string, { workout_structure?: string | null }>,
  weatherByLog: Map<string, FSWeather>,
  zones: ZoneTable,
  streamsByWorkout?: Map<string, FSStream>,
  /** date (YYYY-MM-DD) → total running miles that day (doubles summed). */
  dailyMilesByDate?: Map<string, number>,
) {
  const inputs: KeySessionInput[] = [];
  for (const log of logs) {
    const laps = lapsByWorkout.get(log.id);
    if (!laps || laps.length === 0) continue;
    const stream = streamsByWorkout?.get(log.id) ?? null;
    const dateISO = String(log.workout_date).slice(0, 10);
    inputs.push({
      id: log.id,
      date: dateISO,
      name: featuresById.get(log.id)?.workout_structure?.trim() || undefined,
      // The whole DAY's mileage (all runs), not just this workout — a hard
      // session on a double-run day sits inside a bigger day.
      totalMiles: dailyMilesByDate?.get(dateISO) ?? (log.workout_distance_miles ?? null),
      laps: laps.map((l) => {
        const base = {
          distance_meters: Number(l.distance_meters ?? 0),
          moving_time_seconds: Number(l.moving_time_seconds ?? 0),
          avg_pace_sec_per_mile: l.avg_pace_sec_per_mile != null ? Number(l.avg_pace_sec_per_mile) : null,
          avg_heart_rate: l.avg_heart_rate != null ? Number(l.avg_heart_rate) : null,
          max_heart_rate: l.max_heart_rate != null ? Number(l.max_heart_rate) : null,
          total_elevation_gain: l.total_elevation_gain != null ? Number(l.total_elevation_gain) : null,
        };
        // Split grade from the altitude stream when we can slice this lap.
        if (stream && l.stream_start_index != null && l.stream_end_index != null) {
          const segs = sliceGradeSegments(stream, Number(l.stream_start_index), Number(l.stream_end_index));
          if (segs.length > 0) return { ...base, grade_segments: segs };
        }
        return base;
      }),
      weather: weatherByLog.get(log.id) ?? null,
    });
  }

  const trends = analyzeFastSegmentTrends(inputs, zones);

  const sessions = trends.sessions.map((s) => ({
    id: s.id,
    date: s.date,
    date_label: labelISO(s.date),
    name: s.name,
    total_miles: s.totalMiles,
    rep_count: s.repCount,
    fast_miles: s.fastMiles,
    // Avg rep/bout length (m) — the "rep length" row + the reps-vs-continuous
    // read on the compare surface. A continuous effort is one long bout.
    avg_rep_m: s.avgRepMeters,
    avg_pace_sec: Math.round(s.avgPaceSecPerMile),
    neutral_pace_sec: s.neutralPaceSecPerMile != null ? Math.round(s.neutralPaceSecPerMile) : null,
    flat_pace_sec: s.flatPaceSecPerMile != null ? Math.round(s.flatPaceSecPerMile) : null,
    conditions_pace_sec: s.conditionsPaceSecPerMile != null ? Math.round(s.conditionsPaceSecPerMile) : null,
    avg_grade_pct: s.grade?.avgGradePct ?? null,
    avg_hr: s.avgHeartRate != null ? Math.round(s.avgHeartRate) : null,
    density_pct: Math.round(s.densityPct),
    avg_rest_sec: s.avgRestSeconds,
    meters_per_beat: s.metersPerBeat,
    hr_drift_bpm: s.hrDriftBpm,
    recovery_drop_bpm: s.recoveryHrDropBpm,
    decoupling_pct: s.decouplingPct,
    feels_f: s.heat ? Math.round(s.heat.tempF) : null,
    by_system: s.bySystem.map(volumeDTO),
  }));

  const systems = trends.systems.map((t) => ({
    system: SYSTEM_TOKEN[t.system],
    expected_lo: t.expectedMiles[0],
    expected_hi: t.expectedMiles[1],
    points: t.points.map((p) => ({
      session_id: p.sessionId,
      date_label: labelISO(p.date),
      session_name: p.sessionName,
      reps: p.reps,
      work_miles: p.workMiles,
      total_miles: p.totalMiles,
      avg_pace_sec: Math.round(p.avgPaceSecPerMile),
      neutral_pace_sec: p.neutralPaceSecPerMile != null ? Math.round(p.neutralPaceSecPerMile) : null,
      flat_pace_sec: p.flatPaceSecPerMile != null ? Math.round(p.flatPaceSecPerMile) : null,
      conditions_pace_sec: p.conditionsPaceSecPerMile != null ? Math.round(p.conditionsPaceSecPerMile) : null,
      avg_hr: p.avgHeartRate != null ? Math.round(p.avgHeartRate) : null,
      volume_status: p.volumeStatus,
    })),
  }));

  return { systems, sessions };
}

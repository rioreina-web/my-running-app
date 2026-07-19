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
 * Slice a rep's window of the altitude stream into ~`chunkMeters` grade
 * segments (`{seconds, gradePct}`) for split-grade adjustment. Chunking at
 * ~50 m smooths per-point GPS-altitude noise while still capturing the ups and
 * downs within a rep. Grade is clamped to ±30% (matches the grade model).
 */
export function sliceGradeSegments(
  stream: FSStream,
  startIdx: number,
  endIdx: number,
  chunkMeters = 50,
): Array<{ seconds: number; gradePct: number }> {
  const { time, distance, altitude } = stream;
  const n = Math.min(time.length, distance.length, altitude.length);
  const a = Math.max(0, Math.trunc(startIdx));
  const b = Math.min(Math.trunc(endIdx), n - 1);
  if (!(b > a)) return [];
  const out: Array<{ seconds: number; gradePct: number }> = [];
  let i = a;
  while (i < b) {
    let j = i + 1;
    while (j < b && (distance[j] - distance[i]) < chunkMeters) j++;
    const dd = distance[j] - distance[i];
    const dt = time[j] - time[i];
    if (dd > 0 && dt > 0) {
      let g = ((altitude[j] - altitude[i]) / dd) * 100;
      if (g > 30) g = 30; else if (g < -30) g = -30;
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
) {
  const inputs: KeySessionInput[] = [];
  for (const log of logs) {
    const laps = lapsByWorkout.get(log.id);
    if (!laps || laps.length === 0) continue;
    const stream = streamsByWorkout?.get(log.id) ?? null;
    inputs.push({
      id: log.id,
      date: String(log.workout_date).slice(0, 10),
      name: featuresById.get(log.id)?.workout_structure?.trim() || undefined,
      totalMiles: log.workout_distance_miles ?? null,
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
    avg_pace_sec: Math.round(s.avgPaceSecPerMile),
    neutral_pace_sec: s.neutralPaceSecPerMile != null ? Math.round(s.neutralPaceSecPerMile) : null,
    conditions_pace_sec: s.conditionsPaceSecPerMile != null ? Math.round(s.conditionsPaceSecPerMile) : null,
    avg_grade_pct: s.grade?.avgGradePct ?? null,
    avg_hr: s.avgHeartRate != null ? Math.round(s.avgHeartRate) : null,
    density_pct: Math.round(s.densityPct),
    avg_rest_sec: s.avgRestSeconds,
    meters_per_beat: s.metersPerBeat,
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
      conditions_pace_sec: p.conditionsPaceSecPerMile != null ? Math.round(p.conditionsPaceSecPerMile) : null,
      avg_hr: p.avgHeartRate != null ? Math.round(p.avgHeartRate) : null,
      volume_status: p.volumeStatus,
    })),
  }));

  return { systems, sessions };
}

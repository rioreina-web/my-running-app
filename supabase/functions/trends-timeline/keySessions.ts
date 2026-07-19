/**
 * Key sessions — per-quality-session, work-bout pace derivation.
 *
 * Backs Section A of the redesigned Key Sessions chart
 * (outputs/key-sessions-chart-redesign-2026-07-02.md). Where `timeline.ts`
 * emits ONE whole-workout pace per week, this module emits one dot per
 * quality session, using only the WORK bouts (rest excluded), classified to
 * the athlete's own pace zone, with the heat-adjusted pace carried alongside
 * the raw pace — never replacing it.
 *
 * Pure: no IO, no LLM, no side effects. The heavy lifting (rep/rest
 * detection, zone classification) is reused from the canonical
 * `_shared/workoutSegmentation.ts` (`segmentFromLaps`) so this surface stays
 * in lockstep with load scoring and the Read. See `keySessions.test.ts`.
 *
 * Design invariants (CLAUDE.md + the redesign spec):
 *   • Compare like with like: a dot is a single zone's work-bout pace. The
 *     session's zone = the work zone that accumulated the most work time.
 *   • Heat adjustment is a model, not a measurement. Raw pace is always
 *     present; the adjusted pace rides alongside and is only meaningful when
 *     `heat_category != 'ideal'`. The UI marks adjusted dots hollow.
 *   • Degrade honestly: a session with no laps produces no dot (it is simply
 *     absent), never a faked one.
 */

import {
  segmentFromLaps,
  type LapInput,
  type PaceZones,
  type Zone,
} from "../_shared/workoutSegmentation.ts";
import { buildWeekWindows } from "./timeline.ts";

// ─── Input types (superset of the laps we read) ────────────────────────

/**
 * A lap row. Extends the segmentation `LapInput` with the heat snapshot
 * columns added in `20260528130000_add_heat_adjusted_pace_to_laps.sql`.
 * Every lap on a workout carries the same workout-level weather snapshot, so
 * the adjustment ratio is uniform across the session (see that migration's
 * scope note).
 */
export interface KeySessionLap extends LapInput {
  heat_adjusted_pace_sec_per_mile?: number | null;
  heat_category?: string | null;
}

/** The `workout_features` fields Section A reads. */
export interface KeySessionFeature {
  training_log_id: string;
  workout_structure?: string | null;
}

/** Minimal log shape (a subset of `TimelineLog` from timeline.ts). */
export interface KeySessionLog {
  id: string;
  workout_date: string; // ISO date or datetime
  workout_distance_miles: number | null;
}

// ─── Output type (mirrors the iOS KeySession decode shape) ─────────────

export interface KeySessionOut {
  date: string; // "YYYY-MM-DD"
  log_id: string;
  zone: Zone; // "5k" | "hmp" | ... — a WORK zone (mp-and-faster)
  work_pace_sec: number; // distance-weighted mean of work-bout raw pace
  work_pace_adj_sec: number | null; // heat-adjusted; null when no heat data
  heat_category: string | null; // 'ideal' | 'warm' | 'hot' | ... | null
  work_hr_avg: number | null; // time-weighted avg HR over work bouts
  structure: string | null; // "5K 5×1km · 6.0 mi" style, from features
  distance_mi: number | null;
}

// ─── Constants ─────────────────────────────────────────────────────────

/** Work zones (mp-and-faster) mirror `WORK_ZONES` in workoutSegmentation. */
const WORK_ZONES: ReadonlySet<Zone> = new Set<Zone>([
  "mile",
  "3k",
  "5k",
  "10k",
  "hmp",
  "mp",
]);

/** Human zone label for the structure fallback (`LT 7.4 mi`). */
const ZONE_LABEL: Record<string, string> = {
  mile: "Mile",
  "3k": "3K",
  "5k": "5K",
  "10k": "10K",
  hmp: "HMP",
  mp: "MP",
  steady: "Steady",
  moderate: "Moderate",
  easy: "Easy",
  recovery: "Recovery",
};

const METERS_PER_MILE = 1609.344;

// ─── Small helpers ─────────────────────────────────────────────────────

/** UTC date portion ("2026-06-23") of a log's date string. */
function dayISO(dateStr: string): string {
  const d = new Date(dateStr);
  return new Date(
    Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()),
  )
    .toISOString()
    .split("T")[0];
}

/**
 * The uniform heat-adjustment ratio for a session: adjusted / raw, read from
 * the first lap that carries both a raw and an adjusted pace. Returns null
 * when no lap has heat data (→ no adjusted number is emitted). Also returns
 * the session's heat category alongside.
 */
function heatSnapshot(
  laps: KeySessionLap[],
): { ratio: number | null; category: string | null } {
  for (const lap of laps) {
    const raw = Number(lap.avg_pace_sec_per_mile ?? 0);
    const adj = Number(lap.heat_adjusted_pace_sec_per_mile ?? 0);
    const cat = lap.heat_category ?? null;
    if (raw > 0 && adj > 0) {
      return { ratio: adj / raw, category: cat };
    }
  }
  return { ratio: null, category: null };
}

// ─── Per-session derivation ────────────────────────────────────────────

/**
 * Derive a single Section-A dot from one workout's laps. Returns null when
 * the session has no classifiable work bouts (a pure easy run, a manual log
 * with no laps, etc.) — the caller simply omits it.
 */
export function deriveKeySession(
  log: KeySessionLog,
  laps: KeySessionLap[],
  feature: KeySessionFeature | undefined,
  zones: PaceZones,
): KeySessionOut | null {
  if (!laps || laps.length === 0) return null;

  const seg = segmentFromLaps(laps, zones);
  const workBouts = seg.bouts.filter((b) => b.isWork && b.paceSecPerMile > 0);
  if (workBouts.length === 0) return null;

  // Distance-weighted mean work pace (rest excluded by construction). Falls
  // back to time-weighting when a bout is missing distance.
  let paceWeightSum = 0;
  let paceWeightedPace = 0;
  // Time-weighted work HR (only bouts that carry HR contribute).
  let hrTimeSum = 0;
  let hrWeighted = 0;
  // Work seconds per zone → session zone is the biggest work bucket.
  const zoneSeconds = new Map<Zone, number>();

  for (const b of workBouts) {
    const w = b.distanceMeters > 0 ? b.distanceMeters / METERS_PER_MILE : b.seconds;
    paceWeightSum += w;
    paceWeightedPace += b.paceSecPerMile * w;

    if (b.avgHr != null && b.avgHr > 0 && b.seconds > 0) {
      hrTimeSum += b.seconds;
      hrWeighted += b.avgHr * b.seconds;
    }

    zoneSeconds.set(b.zone, (zoneSeconds.get(b.zone) ?? 0) + b.seconds);
  }

  if (paceWeightSum <= 0) return null;
  const workPaceSec = Math.round(paceWeightedPace / paceWeightSum);

  // Dominant work zone (most work seconds; tie → faster zone via WORK order).
  let zone: Zone | null = null;
  let bestSeconds = -1;
  for (const [z, secs] of zoneSeconds) {
    if (!WORK_ZONES.has(z)) continue;
    if (secs > bestSeconds) {
      bestSeconds = secs;
      zone = z;
    }
  }
  if (zone == null) return null;

  const { ratio, category } = heatSnapshot(laps);
  const workPaceAdjSec = ratio != null ? Math.round(workPaceSec * ratio) : null;

  const workHrAvg = hrTimeSum > 0 ? Math.round(hrWeighted / hrTimeSum) : null;

  const distanceMi = log.workout_distance_miles ?? null;
  const structure = feature?.workout_structure && feature.workout_structure.trim()
    ? feature.workout_structure.trim()
    : fallbackStructure(zone, distanceMi);

  return {
    date: dayISO(log.workout_date),
    log_id: log.id,
    zone,
    work_pace_sec: workPaceSec,
    work_pace_adj_sec: workPaceAdjSec,
    heat_category: category,
    work_hr_avg: workHrAvg,
    structure,
    distance_mi: distanceMi,
  };
}

/** "LT 7.4 mi" style label when no `workout_structure` string exists. */
function fallbackStructure(zone: Zone, distanceMi: number | null): string {
  const label = ZONE_LABEL[zone] ?? zone.toUpperCase();
  if (distanceMi && distanceMi > 0) {
    return `${label} ${Math.round(distanceMi * 10) / 10} mi`;
  }
  return label;
}

// ─── Main builder ──────────────────────────────────────────────────────

/**
 * Build the flat, date-sorted list of quality sessions for the window. One
 * entry per workout that has classifiable work bouts. `lapsByWorkout` is the
 * laps grouped by `workout_id`; `featuresById` maps `training_log_id` →
 * feature; `zones` is the athlete's pace table.
 */
export function buildKeySessions(
  logs: KeySessionLog[],
  lapsByWorkout: Map<string, KeySessionLap[]>,
  featuresById: Map<string, KeySessionFeature>,
  zones: PaceZones,
): KeySessionOut[] {
  const out: KeySessionOut[] = [];
  for (const log of logs) {
    const laps = lapsByWorkout.get(log.id);
    if (!laps || laps.length === 0) continue;
    const session = deriveKeySession(log, laps, featuresById.get(log.id), zones);
    if (session) out.push(session);
  }
  out.sort((a, b) => (a.date < b.date ? -1 : a.date > b.date ? 1 : 0));
  return out;
}

// ─── Section B — volume at fast paces (weekly, per-zone work seconds) ───

/** One week of work-zone time. `zone_seconds` holds only work zones present. */
export interface QualityVolumeWeekOut {
  week_start: string; // Monday, "YYYY-MM-DD"
  date_label: string; // "May 4"
  zone_seconds: Record<string, number>; // work zone → seconds at that zone
}

const MONTH_ABBR = [
  "Jan", "Feb", "Mar", "Apr", "May", "Jun",
  "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
];

/** UTC-midnight epoch ms for a log's date string (bucketing key). */
function dayMs(dateStr: string): number {
  const d = new Date(dateStr);
  return Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate());
}

function isoUTC(d: Date): string {
  return d.toISOString().split("T")[0];
}

function labelUTC(d: Date): string {
  return `${MONTH_ABBR[d.getUTCMonth()]} ${d.getUTCDate()}`;
}

/** Total work seconds per zone for one workout's laps (rest excluded). */
function workZoneSeconds(laps: KeySessionLap[], zones: PaceZones): Map<Zone, number> {
  const out = new Map<Zone, number>();
  if (!laps || laps.length === 0) return out;
  const seg = segmentFromLaps(laps, zones);
  for (const b of seg.bouts) {
    if (!b.isWork || !WORK_ZONES.has(b.zone) || b.seconds <= 0) continue;
    out.set(b.zone, (out.get(b.zone) ?? 0) + b.seconds);
  }
  return out;
}

/**
 * Weekly stacked-bar data for Section B: how much time was spent at each work
 * pace, per Mon–Sun week. Aggregated from laps (rest excluded) via the same
 * `segmentFromLaps` path as Section A, so the two surfaces never disagree.
 * Down weeks come back with an empty `zone_seconds` — a real zero, not a gap.
 */
export function buildQualityVolume(
  logs: KeySessionLog[],
  lapsByWorkout: Map<string, KeySessionLap[]>,
  zones: PaceZones,
  weeks: number,
  reference: Date = new Date(),
): QualityVolumeWeekOut[] {
  // Per-log work-zone seconds, computed once.
  const perLog = new Map<string, Map<Zone, number>>();
  for (const log of logs) {
    const laps = lapsByWorkout.get(log.id);
    if (!laps || laps.length === 0) continue;
    const zs = workZoneSeconds(laps, zones);
    if (zs.size > 0) perLog.set(log.id, zs);
  }

  const windows = buildWeekWindows(weeks, reference);
  return windows.map(({ start, end }) => {
    const s = start.getTime();
    const e = end.getTime();
    const zoneSeconds: Record<string, number> = {};
    for (const log of logs) {
      const zs = perLog.get(log.id);
      if (!zs) continue;
      const t = dayMs(log.workout_date);
      if (t >= s && t < e) {
        for (const [z, sec] of zs) {
          zoneSeconds[z] = (zoneSeconds[z] ?? 0) + Math.round(sec);
        }
      }
    }
    return {
      week_start: isoUTC(start),
      date_label: labelUTC(start),
      zone_seconds: zoneSeconds,
    };
  });
}

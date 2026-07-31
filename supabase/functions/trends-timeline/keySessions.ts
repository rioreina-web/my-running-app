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
import {
  aerobicLoadForBouts,
  longRunLoadFromMinutes,
  qualityLoadForBouts,
} from "./qualityLoad.ts";

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
  /** The classifier's session label. `long_run` is the one that matters here:
   *  a long run carries no MP-or-faster work, so without this it would never
   *  become a key session at all. */
  workout_type?: string | null;
}

/** Minimal log shape (a subset of `TimelineLog` from timeline.ts). */
export interface KeySessionLog {
  id: string;
  workout_date: string; // ISO date or datetime
  workout_distance_miles: number | null;
  /** Only needed for a long run with no laps — see `longRunLoadFromMinutes`. */
  workout_duration_minutes?: number | null;
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
  /** Weighted minutes of work — Σ(work-bout seconds × ZONE_WEIGHTS[zone]).
   *  For a long run, Σ over ALL bouts. Scored here, gated on the client
   *  (`QualityLoad.floor`) so the floor is tunable without a deploy.
   *  See `./qualityLoad.ts`. */
  quality_load: number;
  /** `quality` = a rep/threshold session, classified by its work bouts.
   *  `long_run` = an aerobic anchor session with no work bouts, admitted on
   *  the classifier's label. The client colours and labels them differently;
   *  they are not comparable on pace. */
  kind: "quality" | "long_run";
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

/** Aerobic zones a long run's dominant pace can land in. */
const AEROBIC_ZONES: ReadonlySet<Zone> = new Set<Zone>([
  "steady",
  "moderate",
  "easy",
  "recovery",
]);

/**
 * Derive a single Section-A entry from one workout.
 *
 * Two ways in:
 *   1. QUALITY — the session has work bouts (MP-or-faster). Pace and zone come
 *      from those bouts; load is Σ over them.
 *   2. LONG RUN — no work bouts, but the classifier labelled it `long_run`.
 *      A long run is a key session by any coach's definition, and gating on
 *      MP-or-faster work made every one of them invisible: on real data 14 of
 *      15 long runs (11.4–17.8 mi, avg 93 min) carry not one MP-or-faster lap,
 *      so the Saturday row of the session grid was empty while the athlete was
 *      running 13.8 miles on it. Load is Σ over ALL bouts — for an aerobic
 *      session the whole run is the stimulus.
 *
 * Returns null otherwise (a pure easy midweek run, a manual log with nothing
 * to classify) — the caller simply omits it.
 */
export function deriveKeySession(
  log: KeySessionLog,
  laps: KeySessionLap[],
  feature: KeySessionFeature | undefined,
  zones: PaceZones,
): KeySessionOut | null {
  const isLongRun = feature?.workout_type === "long_run";

  // A long run with no laps at all still counts — it just can't be
  // pace-classified, so it reports as easy (the definition of the session
  // type, not a guess at a number we don't have).
  if (!laps || laps.length === 0) {
    if (!isLongRun) return null;
    return longRunOut(log, feature, "easy", null, longRunLoadFromMinutes(log.workout_duration_minutes));
  }

  const seg = segmentFromLaps(laps, zones);
  const workBouts = seg.bouts.filter((b) => b.isWork && b.paceSecPerMile > 0);

  if (workBouts.length === 0) {
    if (!isLongRun) return null;
    // Dominant aerobic zone across the whole run: an easy plod and a steady
    // long run are different sessions and should not read the same.
    let zone: Zone = "easy";
    let best = -1;
    const zoneSecs = new Map<Zone, number>();
    for (const b of seg.bouts) {
      if (b.seconds <= 0) continue;
      zoneSecs.set(b.zone, (zoneSecs.get(b.zone) ?? 0) + b.seconds);
    }
    for (const [z, secs] of zoneSecs) {
      if (AEROBIC_ZONES.has(z) && secs > best) { best = secs; zone = z; }
    }
    const timeWeightedPace = paceOverBouts(seg.bouts);
    const load = aerobicLoadForBouts(seg.bouts);
    return longRunOut(
      log,
      feature,
      zone,
      timeWeightedPace,
      load > 0 ? load : longRunLoadFromMinutes(log.workout_duration_minutes),
    );
  }

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
    quality_load: qualityLoadForBouts(workBouts),
    kind: "quality",
  };
}

/** Time-weighted mean pace across every bout that has one. null when none do. */
function paceOverBouts(bouts: readonly { seconds: number; paceSecPerMile: number }[]): number | null {
  let secs = 0, weighted = 0;
  for (const b of bouts) {
    if (b.seconds <= 0 || b.paceSecPerMile <= 0) continue;
    secs += b.seconds;
    weighted += b.paceSecPerMile * b.seconds;
  }
  return secs > 0 ? Math.round(weighted / secs) : null;
}

/**
 * A long run's Section-A entry. Pace here is the run's own mean, not a
 * work-bout pace — the two are not comparable, which is exactly why `kind`
 * exists and why the client never draws them on one scale.
 */
function longRunOut(
  log: KeySessionLog,
  feature: KeySessionFeature | undefined,
  zone: Zone,
  paceSec: number | null,
  load: number,
): KeySessionOut {
  const distanceMi = log.workout_distance_miles ?? null;
  const structure = feature?.workout_structure && feature.workout_structure.trim()
    ? feature.workout_structure.trim()
    : distanceMi && distanceMi > 0
      ? `Long ${Math.round(distanceMi * 10) / 10} mi`
      : "Long";
  return {
    date: dayISO(log.workout_date),
    log_id: log.id,
    zone,
    work_pace_sec: paceSec ?? 0,
    work_pace_adj_sec: null,
    heat_category: null,
    work_hr_avg: null,
    structure,
    distance_mi: distanceMi,
    quality_load: load,
    kind: "long_run",
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
    const laps = lapsByWorkout.get(log.id) ?? [];
    const feature = featuresById.get(log.id);
    // Long runs are admitted with no laps at all — 4 of 14 real ones have
    // none. Everything else still needs laps to classify.
    if (laps.length === 0 && feature?.workout_type !== "long_run") continue;
    const session = deriveKeySession(log, laps, feature, zones);
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

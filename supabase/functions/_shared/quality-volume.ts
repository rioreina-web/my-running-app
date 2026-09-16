/**
 * Quality volume — the single definition, shared by every surface.
 *
 * WHY THIS EXISTS
 * ---------------
 * Quality used to be computed two incompatible ways:
 *
 *   1. `trends-timeline` classified the WHOLE workout (via a time-weighted
 *      `intensity_score` against a 1.5 cutoff) and then counted ALL of its
 *      miles. So a rep session booked its warmup, floats, standing rests and
 *      cooldown as quality — while a long run with a 4-mile MP block scored
 *      zero, because the easy miles dragged the average under the cutoff.
 *
 *   2. `dataAnalysis` went segment-by-segment but keyed off the `effort`
 *      STRING, which `strava-sync` derives RELATIVE TO EACH RUN'S OWN AVERAGE
 *      ("fast" / "steady" / "easy", ±8% of that run's mean). Those labels carry
 *      no absolute intensity: nearly every mile of a steady run lands on
 *      "steady", which the zone map sent to "threshold" → quality. Result: 87%
 *      of a real athlete's mileage was booked as threshold work, while the
 *      genuinely fast reps ("fast" — a label absent from the map) fell through
 *      to easy.
 *
 * THE RULE
 * --------
 * Quality is not a speed — it's a position in THIS athlete's range. A 4:15
 * miler runs LT at ~5:00; a 3:30 marathoner races a hard rep there. So we
 * classify each SEGMENT by its MEASURED pace against the athlete's own MP
 * anchor, and ignore the `effort` labels entirely (see the "no pace_segment
 * labels as fitness signal" principle — the labels are untrustworthy, the
 * measured pace is not).
 *
 * Quality = MP and faster (the race-anchor zones: MP, HMP, LT, 10K, 5K, 3K,
 * Mile). Easy / Moderate / Steady are aerobic and do not count. PaceEngine
 * defines `steady` as 90-100% of MP speed, so MP IS the boundary — this is a
 * zone edge, not an arbitrary cutoff.
 *
 * Recoveries, floats, warmup and cooldown are slower than MP, so they fall out
 * on their own. A long run gets credit for exactly its MP block and no more.
 */

/** A segment's pace may sit up to this fraction slower than MP and still count
 *  as MP work — GPS noise and honest pacing drift shouldn't demote a rep. */
export const MP_TOLERANCE = 0.02;

export interface QualitySegment {
  distance_miles?: number | null;
  duration_seconds?: number | null;
  pace_per_mile?: string | null;
}

export interface QualityLog {
  workout_distance_miles?: number | null;
  workout_duration_minutes?: number | null;
  workout_pace_per_mile?: string | null;
  pace_segments?: QualitySegment[] | null;
}

/** Parse "M:SS" / "H:MM:SS" → seconds per mile. null on anything malformed. */
export function parsePaceSec(raw: string | null | undefined): number | null {
  if (!raw) return null;
  const parts = raw.split(":").map(Number);
  if (parts.some((n) => !Number.isFinite(n))) return null;
  if (parts.length === 2) return parts[0] * 60 + parts[1];
  if (parts.length === 3) return parts[0] * 3600 + parts[1] * 60 + parts[2];
  return null;
}

/** Is this pace at MP or faster (within tolerance)? */
export function isQualityPace(paceSecPerMile: number, mpSecPerMile: number): boolean {
  if (!(paceSecPerMile > 0) || !(mpSecPerMile > 0)) return false;
  return paceSecPerMile <= mpSecPerMile * (1 + MP_TOLERANCE);
}

/** A segment's pace: prefer the stated pace, else derive from duration/distance. */
function segmentPaceSec(seg: QualitySegment): number | null {
  const stated = parsePaceSec(seg.pace_per_mile);
  if (stated && stated > 0) return stated;
  const dist = seg.distance_miles ?? 0;
  const secs = seg.duration_seconds ?? 0;
  return dist > 0 && secs > 0 ? secs / dist : null;
}

/** A whole run's average pace: prefer the stated pace, else duration/distance. */
function logPaceSec(log: QualityLog): number | null {
  const stated = parsePaceSec(log.workout_pace_per_mile);
  if (stated && stated > 0) return stated;
  const dist = log.workout_distance_miles ?? 0;
  const mins = log.workout_duration_minutes ?? 0;
  return dist > 0 && mins > 0 ? (mins * 60) / dist : null;
}

/** A rep-level lap (`running_workout_laps`). Finer-grained than a mile split. */
export interface QualityLap {
  distance_meters?: number | null;
  avg_pace_sec_per_mile?: number | null;
  moving_time_seconds?: number | null;
}

const METERS_PER_MILE = 1609.344;

/**
 * Quality miles in one log, measured against the athlete's MP anchor.
 *
 * Source priority — granularity matters more than anything else here:
 *
 *   1. REP-LEVEL LAPS. A mile split that contains a 5:10 rep and a 9:00 float
 *      averages ~6:30 — slower than MP — so mile splits book a hard interval
 *      session as ZERO quality. On real data that halved the count (29 mi from
 *      mile splits vs 58 mi from laps over 90 days). Laps see the rep itself.
 *   2. `pace_segments` (usually Strava per-mile splits) when there are no laps.
 *   3. The whole run's average pace when there are no segments either — a
 *      straight tempo run has no structure to break down.
 *
 * Returns 0 when MP is unknown. We do NOT infer a threshold from the athlete's
 * own average pace — that is exactly how the old code inverted itself, booking
 * 87% of a runner's mileage as threshold work.
 */
export function qualityMilesForLog(
  log: QualityLog,
  mpSecPerMile: number | null,
  laps?: QualityLap[] | null,
): number {
  if (!mpSecPerMile || mpSecPerMile <= 0) return 0;

  const lapList = (laps ?? []).filter(Boolean);
  if (lapList.length > 0) {
    let miles = 0;
    for (const lap of lapList) {
      const dist = (lap.distance_meters ?? 0) / METERS_PER_MILE;
      if (dist <= 0) continue;
      const pace = lap.avg_pace_sec_per_mile ??
        (lap.moving_time_seconds ? lap.moving_time_seconds / dist : null);
      if (pace && isQualityPace(pace, mpSecPerMile)) miles += dist;
    }
    return miles;
  }

  const segs = (log.pace_segments ?? []).filter(Boolean);
  if (segs.length > 0) {
    let miles = 0;
    for (const seg of segs) {
      const pace = segmentPaceSec(seg);
      const dist = seg.distance_miles ?? 0;
      if (pace && dist > 0 && isQualityPace(pace, mpSecPerMile)) miles += dist;
    }
    return miles;
  }

  const pace = logPaceSec(log);
  const dist = log.workout_distance_miles ?? 0;
  return pace && dist > 0 && isQualityPace(pace, mpSecPerMile) ? dist : 0;
}

/** The athlete's anchors, sec/mi. Shape of `athlete_state.pace_zones`. */
export interface ZoneTable {
  easy?: number;
  moderate?: number;
  steady?: number;
  mp?: number;
  hm?: number;
  lt?: number;
  tenK?: number;
  fiveK?: number;
  threeK?: number;
  mile?: number;
}

/**
 * Bin a measured pace into a zone, expressed in the legacy zone vocabulary the
 * reports already speak (`easy` | `threshold` | `race_pace` | `interval`).
 *
 * Anything slower than MP is aerobic — it bins to `easy` regardless of how it
 * compares to the run's own average. At MP or faster we snap to the NEAREST
 * race anchor, so the wide spread of quality paces (a 4:15 miler's 4:15 rep and
 * their 5:00 LT) both land correctly for THAT athlete.
 *
 * Note `tempo` is never emitted: "tempo"/"threshold" are retired as ambiguous
 * (the zone IS the label), so quality reads as race_pace / threshold / interval.
 */
export function zoneForPace(paceSecPerMile: number, zones: ZoneTable): string {
  const mp = zones.mp;
  if (!mp || !(paceSecPerMile > 0)) return "easy";
  if (!isQualityPace(paceSecPerMile, mp)) return "easy";

  const candidates: Array<[number | undefined, string]> = [
    [zones.mp, "race_pace"],
    [zones.hm, "race_pace"],
    [zones.lt, "threshold"],
    [zones.tenK, "threshold"],
    [zones.fiveK, "interval"],
    [zones.threeK, "interval"],
    [zones.mile, "interval"],
  ];

  let bestZone: string | null = null;
  let bestDelta = Infinity;
  for (const [pace, zone] of candidates) {
    if (typeof pace !== "number" || !(pace > 0)) continue;
    const delta = Math.abs(paceSecPerMile - pace);
    if (delta < bestDelta) {
      bestDelta = delta;
      bestZone = zone;
    }
  }
  return bestZone ?? "race_pace";
}

/** A segment's measured pace: stated pace first, else duration/distance. */
export function paceOfSegment(seg: QualitySegment): number | null {
  return segmentPaceSec(seg);
}

/** MP (sec/mi) from a stored `athlete_state.pace_zones` blob. null when absent. */
export function mpFromPaceZones(zones: unknown): number | null {
  if (!zones || typeof zones !== "object") return null;
  const z = zones as Record<string, unknown>;
  const mp = z.mp ?? z.marathon;
  return typeof mp === "number" && mp > 0 ? mp : null;
}

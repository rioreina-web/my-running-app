/**
 * Band laps — the substrate for an athlete-adjustable pace band.
 *
 * `paceBands.ts` answers "how much work landed inside HM ±5% and MP ±5%" and
 * ships the ANSWER: pre-bucketed minutes, miles, pace and HR. That is the right
 * shape for a surface whose band is fixed. It is the wrong shape for one whose
 * band is a control — you cannot widen a band client-side when the laps outside
 * it were never sent, and you cannot re-anchor on LT or 10K when the only
 * anchors on the wire are HM and MP.
 *
 * So this module ships the QUESTION instead: every lap of every session in the
 * window, in order, alongside the full race-pace ladder that was in force the
 * week each session was run. Membership, band width, minimum duration and the
 * effort floor all become decisions the client makes and re-makes without a
 * round trip — which is what a control that the athlete drags requires.
 *
 * Cost, measured against the live athlete (2026-08-05): 1,436 laps across 173
 * workouts in a 26-week window, six numbers each. Well under 100 KB. The laps
 * were always cheaper than the aggregates were flexible.
 *
 * Deliberately a SIBLING of `pace_bands`, not a replacement. The Pace Bands
 * surface draws one column per qualifying session and reads `window_start` off
 * that same gated list; widening its `sessions` array from 19 to 173 to serve a
 * second consumer would silently reshape a shipped surface. The two payloads
 * share `buildWeeklyAnchors` / `anchorForWeek`, so the anchors cannot drift
 * apart — only the gating differs, and it differs on purpose.
 *
 * Pure: no IO, no LLM, no side effects. See `bandLaps.test.ts`.
 *
 * Design invariants:
 *
 *   • **Order is data.** Laps ship in `lap_index` order and rest laps and GPS
 *     fragments ship WITH them, flagged rather than dropped. A client counting
 *     the longest unbroken stretch inside a band needs to know that two in-band
 *     miles had a recovery jog between them. Filtering the breakers out on the
 *     way makes four separate three-minute touches look like one twelve-minute
 *     block, which is the exact misread the minimum-duration control exists to
 *     prevent.
 *   • **Membership pace is heat-adjusted, and raw travels with it.** Same rule
 *     as `paceBands.ts` — the band is judged on what the conditions say the
 *     effort was worth, and the watch's number is never overwritten.
 *   • **The ladder steps weekly.** A run is measured against the fitness that
 *     was current in its week, never against today's.
 *   • **Observation, not prescription.** Counts and paces. Nothing here grades
 *     a session or says what to run next.
 */

import { derivePaceTableFromGoal } from "../_shared/paces.ts";
import {
  anchorForWeek,
  buildWeeklyAnchors,
  latestConfidence,
  weekStartISO,
  type FitnessSnapshotRow,
  type PaceBandLap,
  type PaceBandLog,
  type WeekAnchor,
} from "./paceBands.ts";

// ─── Output types (mirror the iOS BandLaps decode shape) ────────────────

/**
 * The race-pace ladder in force for one week, sec/mile.
 *
 * Seven anchors, matching the race-pace half of the canonical ten-zone
 * taxonomy (CLAUDE.md). The three effort zones — Easy, Moderate, Steady — are
 * deliberately absent: this is the substrate for a *quality* band, and an Easy
 * anchor with a ±5% skirt would put most of a training week "in band", which
 * is a true statement that tells the athlete nothing.
 */
export interface BandLadder {
  /** Marathon pace. From `predicted_marathon_seconds` — the same number the
   *  MP band on the Pace Bands surface is drawn at. */
  mp: number;
  /** Half-marathon pace. From `predicted_half_seconds` — the same number the
   *  HM band is drawn at. */
  hmp: number;
  /** 1-hour race pace, interpolated between 10K and HM. The canonical LT.  */
  lt: number;
  k10: number;
  k5: number;
  k3: number;
  mile: number;
}

/** One lap, in the order it was run. */
export interface BandLapOut {
  /** Moving seconds. The weight behind every average. */
  sec: number;
  /** Miles covered. */
  mi: number;
  /** Heat-adjusted pace, sec/mile — what membership is decided on. Equal to
   *  `raw` when the session carries no weather. */
  adj: number;
  /** What the watch recorded, sec/mile. */
  raw: number;
  hr: number | null;
  /**
   * True when the lap can never be in a band: a flagged recovery lap, a GPS
   * fragment too short to carry a usable pace, or a lap missing pace or a
   * clock. It still ships, and it still occupies its slot in the order, so a
   * client measuring an unbroken stretch sees the break that was really there.
   */
  skip: boolean;
}

/** One session, with its laps and the ladder that was current that week. */
export interface BandLapSessionOut {
  date: string; // "YYYY-MM-DD" (UTC day)
  log_id: string;
  /** Whole-session miles — the constant an in-band total reads against. */
  session_mi: number;
  dew_point_f: number | null;
  anchors: BandLadder;
  /** `lap_index` order. Never re-sorted: the sequence IS the block structure. */
  laps: BandLapOut[];
}

export interface BandLapsOut {
  /** Oldest → newest. */
  sessions: BandLapSessionOut[];
  /** high | medium | low | null, from the latest surviving snapshot. */
  confidence_tier: string | null;
  window_start: string | null;
  window_end: string | null;
}

// ─── Constants ─────────────────────────────────────────────────────────

const METERS_PER_MILE = 1609.344;

/** GPS fragments — a 40 m "lap" carries no usable pace. Mirrors
 *  `paceBands.ts:MIN_LAP_METERS`; the two must agree or the same lap counts on
 *  one surface and not the other. */
const MIN_LAP_METERS = 350;

const round = (n: number, dp: number): number => {
  const f = 10 ** dp;
  return Math.round(n * f) / f;
};

const isNum = (v: unknown): v is number =>
  typeof v === "number" && Number.isFinite(v);

// ─── The ladder ────────────────────────────────────────────────────────

/**
 * The week's seven race-pace anchors from its two predictions.
 *
 * MP and HMP are taken STRAIGHT off the snapshot pair rather than re-derived,
 * so the MP anchor here is bit-identical to the one the Pace Bands surface
 * draws. LT, 10K, 5K, 3K and Mile have no prediction of their own and are
 * derived from the half through the canonical race-equivalence table in
 * `_shared/paces.ts` — the same function web and iOS derive theirs from, so a
 * 10K anchor on this chart matches the 10K row on the pace chart.
 *
 * Derived from the HALF specifically, not the marathon: the shorter prediction
 * is nearer the distances being derived, so the ratio extrapolation is shorter
 * and the marathon's own drift can't leak into a mile pace.
 */
export function ladderFor(anchor: WeekAnchor): BandLadder {
  const table = derivePaceTableFromGoal(anchor.hm, "half_marathon");
  return {
    mp: Math.round(anchor.mp),
    hmp: Math.round(anchor.hm),
    lt: Math.round(table.threshold),
    k10: Math.round(table.tenK),
    k5: Math.round(table.fiveK),
    k3: Math.round(table.threeK),
    mile: Math.round(table.mile),
  };
}

// ─── The build ─────────────────────────────────────────────────────────

/**
 * Build the band-laps payload.
 *
 * @param logs           Running logs in the window (order irrelevant — output
 *                       is date-sorted).
 * @param lapsByWorkout  Laps keyed by `training_logs.id`, from
 *                       `fetchQualityLaps`, already in `lap_index` order.
 * @param snapshots      `fitness_snapshots` rows in (or just before) the
 *                       window.
 * @param dewByLog       Per-session dew point. Readout only, never membership.
 *
 * @returns null when no usable anchor exists, or when no session in the window
 *          carried a single usable lap. The surface then hides itself rather
 *          than offering controls over nothing.
 */
export function buildBandLaps(
  logs: PaceBandLog[],
  lapsByWorkout: Map<string, PaceBandLap[]>,
  snapshots: FitnessSnapshotRow[],
  dewByLog?: Map<string, number>,
): BandLapsOut | null {
  const anchors = buildWeeklyAnchors(snapshots);
  if (anchors.length === 0) return null;

  const sessions: BandLapSessionOut[] = [];

  const sorted = [...logs].sort((a, b) =>
    dayISO(a.workout_date).localeCompare(dayISO(b.workout_date))
  );

  for (const log of sorted) {
    const laps = lapsByWorkout.get(log.id);
    if (!laps || laps.length === 0) continue;

    const date = dayISO(log.workout_date);
    const anchor = anchorForWeek(anchors, weekStartISO(date));
    if (!anchor) continue;

    const out: BandLapOut[] = [];
    let sessionMeters = 0;
    let usable = 0;

    for (const lap of laps) {
      const raw = lap.avg_pace_sec_per_mile;
      const meters = lap.distance_meters;
      const seconds = lap.moving_time_seconds;

      // Guard the types, not just the nulls: these arrive from PostgREST via
      // an `as unknown as` cast, so a string would sail through a null check
      // and then concatenate its way into a client-side average.
      const hasDistance = isNum(meters) && meters > 0;
      const hasPace = isNum(raw) && raw > 0;
      const hasClock = isNum(seconds) && seconds > 0;

      if (hasDistance) sessionMeters += meters;

      // A lap with no pace and no clock has nothing to contribute in either
      // direction — it can't be in a band and it isn't evidence of a break.
      // Dropping it is the one case where dropping preserves the truth.
      if (!hasPace || !hasClock) continue;

      // Membership rides on heat-adjusted pace when we have one. No weather on
      // file → raw IS the honest membership pace, and the client sees a zero
      // correction rather than a fabricated one.
      const adj = isNum(lap.heat_adjusted_pace_sec_per_mile) &&
          lap.heat_adjusted_pace_sec_per_mile > 0
        ? lap.heat_adjusted_pace_sec_per_mile
        : raw;

      const skip = lap.is_rest === true || !hasDistance || meters < MIN_LAP_METERS;
      if (!skip) usable += 1;

      out.push({
        sec: Math.round(seconds),
        mi: round((hasDistance ? meters : 0) / METERS_PER_MILE, 3),
        adj: Math.round(adj),
        raw: Math.round(raw),
        hr: isNum(lap.avg_heart_rate) && lap.avg_heart_rate > 0
          ? Math.round(lap.avg_heart_rate)
          : null,
        skip,
      });
    }

    // Every lap was a rest lap or a fragment: nothing here can ever land in a
    // band at any width, so the session is noise on the x-axis.
    if (usable === 0) continue;

    const dew = dewByLog?.get(log.id);
    sessions.push({
      date,
      log_id: log.id,
      // Prefer the log's own distance (the whole run, doubles and all); fall
      // back to the summed laps when it's missing.
      session_mi: round(
        isNum(log.workout_distance_miles) && log.workout_distance_miles > 0
          ? log.workout_distance_miles
          : sessionMeters / METERS_PER_MILE,
        2,
      ),
      dew_point_f: isNum(dew) ? round(dew, 0) : null,
      anchors: ladderFor(anchor),
      laps: out,
    });
  }

  if (sessions.length === 0) return null;

  return {
    sessions,
    confidence_tier: latestConfidence(snapshots),
    window_start: sessions[0].date,
    window_end: sessions[sessions.length - 1].date,
  };
}

/** UTC date portion ("2026-06-23") of a date string. */
function dayISO(dateStr: string): string {
  const d = new Date(dateStr);
  if (Number.isNaN(d.getTime())) return String(dateStr).slice(0, 10);
  return new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()))
    .toISOString()
    .split("T")[0];
}

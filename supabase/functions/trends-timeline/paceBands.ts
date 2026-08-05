/**
 * Pace bands — "am I doing the work at the pace I'm supposed to be doing it
 * at, and what is it costing me?"
 *
 * Backs the Pace Bands surface in Trends
 * (`outputs/pace-band-surface-spec-2026-08-02.md`, prototype
 * `band-toggle-prototype.html`). One band at a time: the athlete picks HM or
 * MP and the whole surface re-renders against that anchor.
 *
 * Pure: no IO, no LLM, no side effects. Callers hand in logs, laps, fitness
 * snapshots and per-session dew point; this module does the band math and
 * returns a render-ready payload. See `paceBands.test.ts`.
 *
 * Design invariants (the spec's hard calls — change these deliberately):
 *
 *   • **The band moves weekly.** The anchor is the weekly MEDIAN predicted
 *     race pace, carried forward as a step function. A run is judged against
 *     the anchor that was current in its week, never against today's.
 *   • **Membership rides on heat-adjusted pace.** A lap qualifies on what the
 *     conditions say the effort was worth, not what the watch recorded. Raw
 *     pace is carried alongside — never replaced — so the UI can draw the
 *     correction being applied to her.
 *   • **Everything is time-weighted.** A 6-minute mile and a 90-second 400m
 *     rep must not carry equal weight in an average pace.
 *   • **Observation, not prescription.** This module emits counts, paces and
 *     minutes. It never grades them, and it never says what to do next.
 *   • **Degrade honestly.** No snapshots → no surface (null), not a guessed
 *     band. No weather → membership falls back to raw pace and the correction
 *     is reported as zero, so the UI can suppress the stem rather than draw a
 *     zero-length one.
 */

// ─── Input types (structural — callers pass their existing row shapes) ──

/**
 * A lap row. The columns `fetchQualityLaps` already selects, plus the heat
 * snapshot added in `20260528222217_add_heat_adjusted_pace_to_laps.sql`.
 * Every lap on a workout carries the same workout-level weather snapshot, so
 * the adjustment ratio is uniform across a session.
 */
export interface PaceBandLap {
  is_rest?: boolean | null;
  distance_meters?: number | null;
  avg_pace_sec_per_mile?: number | null;
  moving_time_seconds?: number | null;
  avg_heart_rate?: number | null;
  heat_adjusted_pace_sec_per_mile?: number | null;
}

/** Minimal log shape (a subset of `TimelineLog`). */
export interface PaceBandLog {
  id: string;
  workout_date: string; // ISO date or datetime
  workout_distance_miles?: number | null;
}

/** The `fitness_snapshots` fields the anchor reads. */
export interface FitnessSnapshotRow {
  created_at: string;
  predicted_half_seconds?: number | null;
  predicted_marathon_seconds?: number | null;
  confidence_tier?: string | null;
}

// ─── Output types (mirror the iOS PaceBands decode shape) ───────────────

/** One band's slice of one session. Absent (null) when nothing landed. */
export interface BandSlice {
  /** Minutes of in-band running, 1dp. */
  minutes: number;
  /** Miles of in-band running, 2dp. */
  miles: number;
  /** Time-weighted heat-adjusted pace — the pace membership was decided on. */
  pace_adj_sec: number;
  /** Time-weighted raw (watch) pace over the same laps. */
  pace_raw_sec: number;
  /** `pace_raw_sec - pace_adj_sec`, ≥ 0. Zero when no weather was on file —
   *  the UI suppresses the correction stem rather than drawing nothing. */
  correction_sec: number;
  /** Time-weighted average HR while in band; null when no lap carried one. */
  hr_avg: number | null;
}

/** One session on the shared x-axis. Present in `sessions` only when it
 *  cleared the in-band gate for at least one of the two bands. */
export interface PaceBandSessionOut {
  date: string; // "YYYY-MM-DD" (UTC day)
  log_id: string;
  /** Whole-session miles (all qualifying laps, in band or not). */
  session_mi: number;
  hm: BandSlice | null;
  mp: BandSlice | null;
  /** Minutes that qualify for BOTH bands, 1dp. The honesty number. */
  overlap_min: number;
  dew_point_f: number | null;
  /** The anchors in force that week — the band is a step function. */
  hm_anchor_sec: number;
  mp_anchor_sec: number;
}

/** Window totals for one band. */
export interface PaceBandSummary {
  /** Most recent weekly anchor in the window. */
  anchor_sec: number;
  fast_sec: number;
  slow_sec: number;
  /** Sessions that cleared the gate in THIS band. */
  sessions: number;
  minutes: number;
  miles: number;
  /** Time-weighted across the window; null when nothing landed. */
  pace_adj_sec: number | null;
  hr_avg: number | null;
}

export interface PaceBandsOut {
  hm: PaceBandSummary;
  mp: PaceBandSummary;
  /** Oldest → newest. The x-axis order for all three lanes. */
  sessions: PaceBandSessionOut[];
  /**
   * The two bands can share pace. When an athlete's MP sits close to her HM,
   * ±5% each means the same minute qualifies twice — the toggle makes the
   * bands legible separately, it does not make them independent. Null only
   * when they never touch in any week of the window.
   */
  overlap: {
    /** mp anchor − hm anchor at the latest week, sec/mile. */
    gap_sec: number;
    /** Seconds of pace the two bands share at the latest anchors. */
    width_sec: number;
    /** Minutes across the whole window that qualify for both, 1dp. */
    minutes_both: number;
    weeks_overlapping: number;
    weeks_total: number;
  } | null;
  /** From the most recent snapshot: high | medium | low | null. */
  confidence_tier: string | null;
  window_start: string | null;
  window_end: string | null;
}

// ─── Constants ─────────────────────────────────────────────────────────

const METERS_PER_MILE = 1609.344;

/** Official distances in miles — the divisor turning a race prediction into
 *  a pace. Matches the spec's `13.1094` / `26.2188`. */
const HALF_MILES = 13.1094;
const MARATHON_MILES = 26.2188;

/** The band is the anchor ±5%. */
const BAND_PCT = 0.05;

/** GPS fragments — a 40 m "lap" carries no usable pace. */
const MIN_LAP_METERS = 350;

/** A session is in a band only once it holds more than two minutes there.
 *  Below that it's a pace the athlete drifted through, not work she did. */
const MIN_BAND_SECONDS = 120;

/**
 * Anchor sanity filter. Fitness snapshots occasionally emit junk — the live
 * series carries half-marathon paces of 6:01 and 6:25 on days the real
 * estimate was 5:20. A snapshot more than this far from its LOCAL neighbours
 * is discarded before the weekly medians are taken.
 *
 * Relative, not absolute: the spec's `< 350 sec/mile` cut was tuned to one
 * athlete and would silently delete every real snapshot from a slower runner.
 *
 * Local, not global: a glitch is a spike against the rows either side of it. A
 * *window* median can't tell a glitch from a real step change — an athlete
 * coming back from injury, or finishing her first serious block, genuinely
 * moves >10% in 26 weeks, and measuring against one median for the whole
 * series would throw away the newest (correct) anchors and leave her judged
 * against months-old fitness.
 */
const ANCHOR_OUTLIER_PCT = 0.10;

/** Rows either side of a snapshot that define "local" for the filter above.
 *  Odd, so the median is a real observation. */
const ANCHOR_LOCAL_WINDOW = 9;

// ─── Small helpers ─────────────────────────────────────────────────────

/** UTC date portion ("2026-06-23") of a date string. */
function dayISO(dateStr: string): string {
  const d = new Date(dateStr);
  if (Number.isNaN(d.getTime())) return String(dateStr).slice(0, 10);
  return new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()))
    .toISOString()
    .split("T")[0];
}

/**
 * Monday (UTC) of the week a date falls in, as "YYYY-MM-DD".
 *
 * An unparseable date comes back as the raw day string rather than throwing.
 * One malformed `created_at` in a snapshot series must not take the whole
 * surface down — it just fails to match any real week and drops out.
 */
export function weekStartISO(dateStr: string): string {
  const day = dayISO(dateStr);
  const d = new Date(day + "T00:00:00Z");
  if (Number.isNaN(d.getTime())) return day;
  const dow = d.getUTCDay(); // 0 = Sunday
  const backToMonday = (dow + 6) % 7;
  d.setUTCDate(d.getUTCDate() - backToMonday);
  return d.toISOString().split("T")[0];
}

function median(xs: number[]): number {
  if (xs.length === 0) return NaN;
  const s = [...xs].sort((a, b) => a - b);
  const mid = s.length >> 1;
  return s.length % 2 ? s[mid] : (s[mid - 1] + s[mid]) / 2;
}

const round = (n: number, dp: number): number => {
  const f = 10 ** dp;
  return Math.round(n * f) / f;
};

const isNum = (v: unknown): v is number =>
  typeof v === "number" && Number.isFinite(v);

// ─── Anchors ───────────────────────────────────────────────────────────

/** One week's pair of anchors, sec/mile. */
export interface WeekAnchor {
  week: string; // Monday, "YYYY-MM-DD"
  hm: number;
  mp: number;
}

/**
 * Weekly anchor series from the raw snapshot rows, oldest → newest.
 *
 * Junk snapshots are dropped against the window median (see
 * `ANCHOR_OUTLIER_PCT`) BEFORE the weekly medians are taken, so one bad row
 * can't drag a sparse week. Returns `[]` when nothing usable survives — the
 * caller then emits no surface rather than a guessed band.
 */
export function buildWeeklyAnchors(rows: FitnessSnapshotRow[]): WeekAnchor[] {
  const clean = usableSnapshots(rows);
  if (clean.length === 0) return [];

  const byWeek = new Map<string, { hm: number[]; mp: number[] }>();
  for (const r of clean) {
    const bucket = byWeek.get(r.week) ?? { hm: [], mp: [] };
    bucket.hm.push(r.hm);
    bucket.mp.push(r.mp);
    byWeek.set(r.week, bucket);
  }

  return [...byWeek.entries()]
    .map(([week, b]) => ({ week, hm: median(b.hm), mp: median(b.mp) }))
    .sort((a, b) => a.week.localeCompare(b.week));
}

/** A snapshot that survived parsing and the outlier filter. */
interface CleanSnapshot {
  week: string;
  hm: number;
  mp: number;
  createdAt: string;
  confidenceTier: string | null;
}

/**
 * Parse the snapshot rows into paces and drop the junk ones.
 *
 * A row needs BOTH predictions. `predicted_half_seconds` and
 * `predicted_marathon_seconds` are `INTEGER NOT NULL` on `fitness_snapshots`
 * (`20260228_create_fitness_snapshots.sql`), so a row missing one is malformed
 * rather than partially useful — and the two come out of a single VDOT fit, so
 * a junk half implies a junk marathon anyway.
 */
function usableSnapshots(rows: FitnessSnapshotRow[]): CleanSnapshot[] {
  const usable: CleanSnapshot[] = rows
    .map((r) => ({
      week: weekStartISO(r.created_at),
      hm: isNum(r.predicted_half_seconds) ? r.predicted_half_seconds / HALF_MILES : NaN,
      mp: isNum(r.predicted_marathon_seconds)
        ? r.predicted_marathon_seconds / MARATHON_MILES
        : NaN,
      createdAt: String(r.created_at ?? ""),
      confidenceTier: typeof r.confidence_tier === "string" && r.confidence_tier.length > 0
        ? r.confidence_tier.toLowerCase()
        : null,
    }))
    .filter((r) => Number.isFinite(r.hm) && r.hm > 0 && Number.isFinite(r.mp) && r.mp > 0)
    .sort((a, b) => a.createdAt.localeCompare(b.createdAt));

  if (usable.length === 0) return [];

  // Each row is judged against the median of the rows around it in time, so a
  // sustained shift moves the yardstick with the athlete and only a spike
  // stands out. Windows are clamped to stay full at the ends of the series.
  const half = ANCHOR_LOCAL_WINDOW >> 1;
  const maxStart = Math.max(0, usable.length - ANCHOR_LOCAL_WINDOW);
  const within = (v: number, m: number) => Math.abs(v - m) <= m * ANCHOR_OUTLIER_PCT;

  const clean = usable.filter((r, i) => {
    const start = Math.min(Math.max(0, i - half), maxStart);
    const win = usable.slice(start, start + ANCHOR_LOCAL_WINDOW);
    return within(r.hm, median(win.map((w) => w.hm))) &&
      within(r.mp, median(win.map((w) => w.mp)));
  });

  // Pathological series (every row an outlier of its own neighbourhood) — fall
  // back to the unfiltered set rather than emitting nothing.
  return clean.length > 0 ? clean : usable;
}

/**
 * The anchor in force for a given week: the latest anchor at or before it.
 *
 * PRECONDITION: `anchors` is sorted ascending by week — which is what
 * `buildWeeklyAnchors` returns, and the only thing this is ever called with.
 * The scan breaks early on that assumption.
 *
 * Weeks before the first snapshot carry the earliest anchor BACKWARD. The
 * alternative — no anchor, so no membership — silently deletes every session
 * that predates the athlete's first fitness estimate, which on a fresh
 * back-fill is most of the window. Carrying back is an approximation; dropping
 * the runs is a lie about how much work she did.
 */
export function anchorForWeek(anchors: WeekAnchor[], week: string): WeekAnchor | null {
  if (anchors.length === 0) return null;
  let found: WeekAnchor | null = null;
  for (const a of anchors) {
    if (a.week <= week) found = a;
    else break;
  }
  return found ?? anchors[0];
}

// ─── The band build ────────────────────────────────────────────────────

interface Accum {
  seconds: number;
  meters: number;
  adjWeighted: number;
  rawWeighted: number;
  hrWeighted: number;
  hrSeconds: number;
}

const emptyAccum = (): Accum => ({
  seconds: 0,
  meters: 0,
  adjWeighted: 0,
  rawWeighted: 0,
  hrWeighted: 0,
  hrSeconds: 0,
});

function sliceFrom(a: Accum): BandSlice | null {
  if (a.seconds <= 0) return null;
  const adj = a.adjWeighted / a.seconds;
  const raw = a.rawWeighted / a.seconds;
  return {
    minutes: round(a.seconds / 60, 1),
    miles: round(a.meters / METERS_PER_MILE, 2),
    pace_adj_sec: Math.round(adj),
    pace_raw_sec: Math.round(raw),
    // Heat only ever makes the neutral-equivalent FASTER (adjusted = raw /
    // (1 + pct)), so this is ≥ 0 by construction. Clamped anyway — a negative
    // correction would mean the stem points the wrong way on the chart.
    correction_sec: Math.max(0, Math.round(raw - adj)),
    hr_avg: a.hrSeconds > 0 ? Math.round(a.hrWeighted / a.hrSeconds) : null,
  };
}

function summaryFrom(
  a: Accum,
  sessions: number,
  anchor: number,
): PaceBandSummary {
  return {
    anchor_sec: Math.round(anchor),
    fast_sec: Math.round(anchor * (1 - BAND_PCT)),
    slow_sec: Math.round(anchor * (1 + BAND_PCT)),
    sessions,
    minutes: round(a.seconds / 60, 1),
    miles: round(a.meters / METERS_PER_MILE, 2),
    pace_adj_sec: a.seconds > 0 ? Math.round(a.adjWeighted / a.seconds) : null,
    hr_avg: a.hrSeconds > 0 ? Math.round(a.hrWeighted / a.hrSeconds) : null,
  };
}

/**
 * Build the Pace Bands payload.
 *
 * @param logs           Running logs in the window (order irrelevant — output
 *                       is date-sorted).
 * @param lapsByWorkout  Laps keyed by `training_logs.id`, from
 *                       `fetchQualityLaps` (native / derived / fix-reps).
 * @param snapshots      `fitness_snapshots` rows in (or just before) the
 *                       window. More history sharpens the outlier filter.
 * @param dewByLog       Per-session dew point, keyed by log id. Optional —
 *                       purely for the readout, never for membership.
 *
 * @returns null when there is no usable anchor, or when no session in the
 *          window held either band for longer than `MIN_BAND_SECONDS`. The
 *          surface hides itself; it never renders an empty band as a zero.
 */
export function buildPaceBands(
  logs: PaceBandLog[],
  lapsByWorkout: Map<string, PaceBandLap[]>,
  snapshots: FitnessSnapshotRow[],
  dewByLog?: Map<string, number>,
): PaceBandsOut | null {
  const anchors = buildWeeklyAnchors(snapshots);
  if (anchors.length === 0) return null;

  const sessions: PaceBandSessionOut[] = [];
  const hmTotal = emptyAccum();
  const mpTotal = emptyAccum();
  let hmSessions = 0;
  let mpSessions = 0;
  let overlapSecondsTotal = 0;

  const sorted = [...logs].sort((a, b) =>
    dayISO(a.workout_date).localeCompare(dayISO(b.workout_date))
  );

  for (const log of sorted) {
    const laps = lapsByWorkout.get(log.id);
    if (!laps || laps.length === 0) continue;

    const date = dayISO(log.workout_date);
    const anchor = anchorForWeek(anchors, weekStartISO(date));
    if (!anchor) continue;

    const hmFast = anchor.hm * (1 - BAND_PCT);
    const hmSlow = anchor.hm * (1 + BAND_PCT);
    const mpFast = anchor.mp * (1 - BAND_PCT);
    const mpSlow = anchor.mp * (1 + BAND_PCT);

    const hm = emptyAccum();
    const mp = emptyAccum();
    let sessionMeters = 0;
    let overlapSeconds = 0;

    for (const lap of laps) {
      if (lap.is_rest === true) continue;
      const raw = lap.avg_pace_sec_per_mile;
      const meters = lap.distance_meters;
      const seconds = lap.moving_time_seconds;
      // Guard the types, not just the nulls: these arrive from PostgREST via
      // an `as unknown as` cast, so a string would otherwise concatenate its
      // way into the accumulators instead of adding.
      if (!isNum(raw) || raw <= 0) continue;
      if (!isNum(meters) || meters < MIN_LAP_METERS) continue; // GPS fragment

      // Counted toward the whole-session distance BEFORE the moving-time
      // check: a lap with distance but no clock is still ground she covered,
      // even though it can't be time-weighted into a band.
      sessionMeters += meters;
      if (!isNum(seconds) || seconds <= 0) continue;

      // Membership rides on the heat-adjusted pace when we have one. No
      // weather on file → the raw pace IS the honest membership pace, and the
      // correction comes out zero so the UI draws no stem.
      const adj = isNum(lap.heat_adjusted_pace_sec_per_mile) &&
          lap.heat_adjusted_pace_sec_per_mile > 0
        ? lap.heat_adjusted_pace_sec_per_mile
        : raw;

      const inHm = adj >= hmFast && adj <= hmSlow;
      const inMp = adj >= mpFast && adj <= mpSlow;
      if (inHm && inMp) overlapSeconds += seconds;

      const add = (acc: Accum) => {
        acc.seconds += seconds;
        acc.meters += meters;
        acc.adjWeighted += adj * seconds;
        acc.rawWeighted += raw * seconds;
        if (isNum(lap.avg_heart_rate) && lap.avg_heart_rate > 0) {
          acc.hrWeighted += lap.avg_heart_rate * seconds;
          acc.hrSeconds += seconds;
        }
      };
      if (inHm) add(hm);
      if (inMp) add(mp);
    }

    const hmQualifies = hm.seconds > MIN_BAND_SECONDS;
    const mpQualifies = mp.seconds > MIN_BAND_SECONDS;
    if (!hmQualifies && !mpQualifies) continue;

    if (hmQualifies) {
      hmSessions += 1;
      hmTotal.seconds += hm.seconds;
      hmTotal.meters += hm.meters;
      hmTotal.adjWeighted += hm.adjWeighted;
      hmTotal.rawWeighted += hm.rawWeighted;
      hmTotal.hrWeighted += hm.hrWeighted;
      hmTotal.hrSeconds += hm.hrSeconds;
    }
    if (mpQualifies) {
      mpSessions += 1;
      mpTotal.seconds += mp.seconds;
      mpTotal.meters += mp.meters;
      mpTotal.adjWeighted += mp.adjWeighted;
      mpTotal.rawWeighted += mp.rawWeighted;
      mpTotal.hrWeighted += mp.hrWeighted;
      mpTotal.hrSeconds += mp.hrSeconds;
    }
    overlapSecondsTotal += overlapSeconds;

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
      hm: hmQualifies ? sliceFrom(hm) : null,
      mp: mpQualifies ? sliceFrom(mp) : null,
      overlap_min: round(overlapSeconds / 60, 1),
      dew_point_f: isNum(dew) ? round(dew, 0) : null,
      hm_anchor_sec: Math.round(anchor.hm),
      mp_anchor_sec: Math.round(anchor.mp),
    });
  }

  if (sessions.length === 0) return null;

  const latest = anchors[anchors.length - 1];

  // Overlap is a property of the anchors, not of the running: at ±5% each,
  // two bands whose anchors sit close share pace in every week. Reported
  // whenever they touch in ANY week, measured at the latest anchors.
  //
  // Computed symmetrically. MP is normally the slower (higher sec/mile)
  // anchor, but an athlete with a stale half prediction can invert that, and
  // assuming the usual order there reports a fat overlap between two bands
  // that share nothing.
  const overlapWidth = (a: WeekAnchor) =>
    Math.min(a.hm, a.mp) * (1 + BAND_PCT) - Math.max(a.hm, a.mp) * (1 - BAND_PCT);
  const weeksOverlapping = anchors.filter((a) => overlapWidth(a) >= 0).length;
  const width = overlapWidth(latest);

  return {
    hm: summaryFrom(hmTotal, hmSessions, latest.hm),
    mp: summaryFrom(mpTotal, mpSessions, latest.mp),
    sessions,
    overlap: weeksOverlapping > 0
      ? {
        gap_sec: Math.round(latest.mp - latest.hm),
        width_sec: Math.max(0, Math.round(width)),
        minutes_both: round(overlapSecondsTotal / 60, 1),
        weeks_overlapping: weeksOverlapping,
        weeks_total: anchors.length,
      }
      : null,
    confidence_tier: latestConfidence(snapshots),
    window_start: sessions[0].date,
    window_end: sessions[sessions.length - 1].date,
  };
}

/**
 * Confidence tier of the most recent snapshot that actually survived the
 * outlier filter, lowercased.
 *
 * Reading the raw rows instead would let a discarded junk snapshot mark the
 * whole band LOW CONFIDENCE — a claim about data that contributed nothing to
 * the anchor.
 */
function latestConfidence(rows: FitnessSnapshotRow[]): string | null {
  const clean = usableSnapshots(rows);
  // `usableSnapshots` sorts ascending by created_at.
  return clean.length > 0 ? clean[clean.length - 1].confidenceTier : null;
}

/**
 * Trends timeline — pure week-bucketing logic.
 *
 * No IO, no LLM, no side effects. Takes raw rows, returns the
 * `[TrendsWeekOut]` the iOS Trends tab renders (one shared timeline of
 * mileage, intensity, key-session pace, mood, and niggles).
 *
 * Kept separate from `index.ts` so it can be unit-tested without spinning
 * up the Deno server. See `timeline.test.ts`.
 *
 * Contract notes (CLAUDE.md):
 *   • Cross-training / strength never count toward running miles or quality.
 *   • Niggles are surfaced verbatim, never interpreted — this module emits
 *     the body-area label and the athlete's own quote, nothing derived.
 *   • Quality classification mirrors the easy-vs-workout split used by
 *     `weeklyAnalytics.ts`; intensity comes from `workout_features`
 *     (the canonical per-workout intensity) when available.
 *
 * KNOWN SIMPLIFICATION: week boundaries are computed in UTC (matching
 * `weeklyAnalytics.getLastWeekBounds`). A profile-timezone cutoff is the
 * follow-up (see trends-tab-data-wiring.md §5.2 / §9).
 */

import {
  qualityMilesForLog,
  type QualityLap,
  type QualitySegment,
} from "../_shared/quality-volume.ts";
import {
  segmentFromLaps,
  ZONE_WEIGHTS,
  type PaceZones,
  type Zone,
} from "../_shared/workoutSegmentation.ts";

// ─── Input types (subset of the DB rows we actually read) ──────────────

export interface TimelineLog {
  id: string;
  workout_date: string; // ISO date ("2026-06-09") or datetime
  workout_distance_miles: number | null;
  workout_duration_minutes: number | null;
  workout_type: string | null;
  workout_pace_per_mile: string | null; // "6:41"
  mood: string | null;
  source?: string | null; // strava | auto_sync | voice_log | check_in | …
  // Athlete's explicit decision: null = auto (heuristic), true = trimmed, false = kept.
  stats_excluded?: boolean | null;
  // Per-segment splits, used to count quality mile-by-mile rather than
  // all-or-nothing on the whole workout.
  pace_segments?: QualitySegment[] | null;
  // The real per-workout internal-load unit. NULL on every row until the
  // 20260731120000 backfill runs; the demand term degrades to duration x
  // intensity in the meantime.
  stress_load?: number | null;
}

export interface TimelineFeature {
  training_log_id: string;
  intensity_score: number | null;
  total_duration_seconds: number | null;
}

export interface TimelineMention {
  body_area: string;
  side: string | null;
  verbatim_quote: string;
  severity_hint: string; // tight | sore | pain | sharp
  mentioned_at: string; // date
}

export interface TimelineInput {
  logs: TimelineLog[];
  features: TimelineFeature[];
  mentions: TimelineMention[];
  /** The athlete's MP anchor (sec/mi) — the quality boundary. Null when we
   *  have no anchor, in which case quality volume is 0 rather than guessed. */
  mpSecPerMile?: number | null;
  /** Rep-level laps by workout id. Preferred over `pace_segments` for quality,
   *  which mile splits systematically undercount on interval sessions. */
  lapsByWorkout?: Map<string, QualityLap[]>;
  /** Work-bout (rep) pace per quality log, sec/mi — rest excluded, from
   *  `buildKeySessions`. When present, the weekly key pace uses THIS instead of
   *  `workout_pace_per_mile` (which blends the reps with the recovery jogs: a
   *  6×mile @ 5:10 averages to ~6:20 over the whole workout). */
  keyWorkPaceByLog?: Map<string, number>;
  /** The athlete's full zone table. Needed by `segmentFromLaps` to classify
   *  every bout for the daily zone breakdown — `mpSecPerMile` alone only
   *  answers "is this quality", which is a different question. Absent zones
   *  means no daily breakdown is emitted (never a guessed one). */
  zones?: PaceZones;
}

// ─── Output type (mirrors the iOS TrendsWeek decode shape) ─────────────

export interface TrendsWeekOut {
  week_start: string; // Monday, "YYYY-MM-DD"
  month: string; // "May"
  date_label: string; // "May 25"
  miles: number;
  quality_miles: number;
  key_pace_sec: number | null;
  mood: string | null;
  niggles: string[];
  voice_quote: string | null;
}

/**
 * A single body mention as it lands on a day. `severity` is the raw
 * `body_mentions.severity_hint` (tight | sore | pain | sharp) — the view
 * maps it to an opacity ramp; the endpoint never interprets it. `quote` is
 * verbatim (CLAUDE.md niggle contract).
 */
export interface TrendsDayNiggle {
  area: string;
  side: string | null;
  severity: string | null;
  quote: string;
}

/**
 * One calendar day. The daily substrate the Trends-v2 calendar (Month/Block
 * scales) renders on — dense (one entry per day in the window, rest days
 * included so the weekday grid needs no gap-filling on device).
 *
 * `type` is the coarse session channel the calendar colors by, NOT a pace
 * zone: `key` (coral accent), `long` (dark-grey channel, takes precedence
 * over key), `easy` (light grey), `rest` (no run). Per-zone pace lives in the
 * weekly quality surfaces, not here.
 *
 * `mood` is that day's dominant mood from ANY log carrying one (a mood-only
 * check-in counts even with zero distance); null on a day with no logged
 * feeling — never fabricated.
 */
export interface TrendsDayOut {
  date: string; // "YYYY-MM-DD" (UTC day)
  miles: number; // deduped running miles that day (doubles summed)
  type: "key" | "long" | "easy" | "rest";
  mood: string | null;
  niggles: TrendsDayNiggle[];
  // Sleep + overnight biometrics (additive, 2026-08-05). Decorated in
  // index.ts from daily_biometrics (device, service-written) and
  // daily_checkins (one-tap self-report). Absent when there is no data for
  // the night — never fabricated, same contract as `mood`.
  hrv_rmssd?: number | null;
  resting_hr?: number | null;
  sleep_total_min?: number | null;
  sleep_quality?: string | null; // 'rough' | 'ok' | 'good'
  // Load inputs for the recovery-need DEMAND term (2026-08-06,
  // `outputs/recovery-need-model-2026-08-06.md` §2). Summed over the day's
  // deduped runs. `duration_min` is 0 on a rest day; `stress_load` is null
  // until its backfill runs, which is what makes the fallback ladder in
  // `TrendsRecoveryDemand.sessionLoad` necessary rather than defensive.
  duration_min?: number | null;
  stress_load?: number | null;
  // Per-zone breakdown of the day (additive, 2026-08-10). The `type` field
  // above is one coarse channel for the calendar; THESE are the real pace
  // distribution, across all ten zones of the canonical taxonomy — including
  // easy, which `quality_volume.zone_seconds` deliberately excludes because
  // it only ever cared about work. A week-load surface cares about easy most
  // of all: it is 65% of the miles.
  //
  // Built from every `Bout` returned by `segmentFromLaps`, so a long run with
  // an embedded MP block splits correctly instead of averaging itself down to
  // all-easy (the failure `_shared/quality-volume.ts` documents at length).
  //
  // BOTH fields are ABSENT (not `{}`) when no run that day carried laps —
  // a manual entry or a lapless import. Absent means "we cannot say"; `{}`
  // would mean "we looked and there was nothing", and the client renders
  // those two states differently. Zones with no time are omitted, not
  // zero-filled, so `Object.keys()` is the list of zones actually run.
  zone_minutes?: Record<string, number>;
  /** Paired with `zone_minutes` so the client can compute a real average pace
   *  per zone (Σ time ÷ Σ distance) rather than a mean of per-run means. */
  zone_miles?: Record<string, number>;
  /** Weighted minutes (TLS) per zone, summed PER BOUT off the continuous
   *  `paceWeight` curve before the zone rollup.
   *
   *  Clients should use this rather than multiplying `zone_minutes` by the
   *  discrete `ZONE_WEIGHTS` table. The table is ten steps; the curve is what
   *  those steps are sampled from, and it keeps climbing past mile — so a 200
   *  at 4:20/mi scores above 8.0 instead of being capped at the `mile` anchor
   *  alongside a 4:50 mile rep. Divide by `zone_minutes` for the effective
   *  multiplier a zone actually earned. */
  zone_load?: Record<string, number>;
  // The same day, UNROLLED (additive, 2026-08-11). Everything above this line
  // is the day summed; this is the runs it was summed from.
  //
  // Added for the week stress strip, which places each run at the time of day
  // it started. A day-grained payload cannot render a double — a morning
  // session and an evening easy four collapse into one number with one
  // notional time — and splitting the day's zones back across its runs by
  // duration would be a fabricated split sitting next to measured ones.
  //
  // ABSENT (not `[]`) on a rest day. Present with one entry on the ordinary
  // single-run day, which is most of them.
  runs?: TrendsRunOut[];
}

/** One run inside a day. See `TrendsDayOut.runs`. */
export interface TrendsRunOut {
  /** `training_logs.id` — the client routes to the run detail with this. */
  id: string;
  /** The run's START time, verbatim from `training_logs.workout_date`, WITH
   *  whatever offset that column carried. Deliberately NOT normalized to a UTC
   *  instant or split to a date here: this field exists to be read as a LOCAL
   *  time of day, and normalizing is exactly what destroys that. A 6:05am
   *  Chicago run rendered from a UTC-normalized timestamp shows up at 11am.
   *
   *  Note the column is TIMESTAMPTZ, so Postgres has already resolved it to an
   *  instant; the offset survives only because we never re-slice it. The
   *  client's own guard is in `TrendsDay.Run.minuteOfDay`. */
  started_at: string;
  /** Wall-clock minutes, paused-watch artifact already re-imputed by
   *  `cleanDuration` — the same treatment `duration_min` gets, so the runs
   *  sum to the day. Whole minutes, for parity with the day field. */
  duration_min: number;
  /** The same duration in SECONDS, unrounded until this point.
   *
   *  `duration_min` is whole minutes everywhere else in this payload, which is
   *  fine for a week total and useless for a run: an athlete reads 42:13, not
   *  "about 42 minutes", and rounding to the minute throws away the only part
   *  of it they would check against their watch. Clients should prefer this. */
  duration_sec: number;
  miles: number;
  /** This RUN's zone breakdown, same construction and same omit-never-zero-fill
   *  contract as the day-level `zone_minutes`. ABSENT when this particular run
   *  carried no laps — which can happen on a day where the OTHER run did, so
   *  the day has a breakdown and this run still does not. */
  zone_minutes?: Record<string, number>;
  zone_miles?: Record<string, number>;
  /** See `TrendsDayOut.zone_load`. */
  zone_load?: Record<string, number>;
}

// ─── Constants ─────────────────────────────────────────────────────────

/** Non-running modalities excluded from running volume + intensity. */
const NON_RUNNING_TYPES = new Set(["cross_training", "strength", "rest"]);

/**
 * Quality (non-easy) workout types — the fallback when no
 * `workout_features.intensity_score` exists yet. Long runs are aerobic, so
 * they are NOT quality even though they're "workouts" in some splits.
 */
const QUALITY_TYPES = new Set([
  "tempo",
  "threshold",
  "intervals",
  "interval",
  "mile_repeats",
  "mp_run",
  "progression",
  "race",
]);

/**
 * `workout_features.intensity_score` is a time-weighted pace-zone average
 * (easy=1.0, mp=2.5, threshold=3.0, …). Anything meaningfully above easy
 * counts as quality.
 */
const QUALITY_INTENSITY_THRESHOLD = 1.5;

/**
 * Long-run workout types — the calendar's dark-grey channel. A long run is
 * its own visual category even when it carries an embedded quality block, so
 * `long` takes precedence over `key` in the daily `type`.
 */
const LONG_TYPES = new Set([
  "long",
  "long_run",
  "long run",
  "longrun",
  "long_wo",
  "long wo",
]);

/** Severity ranking for picking the week's representative voice quote. */
const SEVERITY_RANK: Record<string, number> = {
  sharp: 4,
  pain: 3,
  sore: 2,
  tight: 1,
};

const MONTH_ABBR = [
  "Jan", "Feb", "Mar", "Apr", "May", "Jun",
  "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
];

// ─── Small helpers ─────────────────────────────────────────────────────

const METERS_PER_MILE = 1609.344;

/** Two decimal places. Zone minutes/miles are summed on device, so more
 *  precision than this is noise and less loses a 0.3 mi stride set. */
const round2 = (n: number): number => Math.round(n * 100) / 100;

/** Parse "M:SS" → seconds. Returns null on anything malformed. */
export function parsePaceToSec(raw: string | null): number | null {
  if (!raw) return null;
  const m = raw.trim().match(/^(\d{1,2}):(\d{2})$/);
  if (!m) return null;
  const sec = parseInt(m[1], 10) * 60 + parseInt(m[2], 10);
  return sec > 0 ? sec : null;
}

/** UTC midnight Date for a log's date string. */
function dayUTC(dateStr: string): Date {
  const d = new Date(dateStr);
  return new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()));
}

/** The Monday (UTC midnight) of the week containing `ref`. */
function mondayOf(ref: Date): Date {
  const d = new Date(Date.UTC(ref.getUTCFullYear(), ref.getUTCMonth(), ref.getUTCDate()));
  const dow = d.getUTCDay(); // 0=Sun … 6=Sat
  const daysFromMonday = (dow + 6) % 7;
  d.setUTCDate(d.getUTCDate() - daysFromMonday);
  return d;
}

function isoDate(d: Date): string {
  return d.toISOString().split("T")[0];
}

function monthAbbr(d: Date): string {
  return MONTH_ABBR[d.getUTCMonth()];
}

function dateLabel(d: Date): string {
  return `${MONTH_ABBR[d.getUTCMonth()]} ${d.getUTCDate()}`;
}

/** Build `count` consecutive Mon–Sun windows ending with the current week. */
export function buildWeekWindows(
  count: number,
  reference: Date,
): { start: Date; end: Date }[] {
  const thisMonday = mondayOf(reference);
  const windows: { start: Date; end: Date }[] = [];
  for (let i = count - 1; i >= 0; i--) {
    const start = new Date(thisMonday);
    start.setUTCDate(start.getUTCDate() - i * 7);
    const end = new Date(start);
    end.setUTCDate(end.getUTCDate() + 7); // exclusive upper bound (next Monday)
    windows.push({ start, end });
  }
  return windows;
}

function isQuality(log: TimelineLog, feature: TimelineFeature | undefined): boolean {
  if (feature?.intensity_score != null) {
    return feature.intensity_score >= QUALITY_INTENSITY_THRESHOLD;
  }
  const type = (log.workout_type ?? "").toLowerCase();
  return QUALITY_TYPES.has(type);
}

function isLong(log: TimelineLog): boolean {
  return LONG_TYPES.has((log.workout_type ?? "").toLowerCase());
}

function logPaceSec(log: TimelineLog): number | null {
  const parsed = parsePaceToSec(log.workout_pace_per_mile);
  if (parsed) return parsed;
  const dist = log.workout_distance_miles ?? 0;
  const dur = log.workout_duration_minutes ?? 0;
  if (dist > 0 && dur > 0) return Math.round((dur * 60) / dist);
  return null;
}

// ─── Data quality: dedup + plausibility ───────────────────────────────
// The training_logs table accrues rows from three writers (strava,
// auto_sync, voice_log) so the SAME physical run is often counted 2–3×.
// This mirrors the canonical rule in iOS `App/LogDedup.swift` so the
// timeline matches the Training tab. (Real fix is upstream in reconcile-log;
// this keeps the analytics honest until then.)

const GPS_SOURCES = new Set(["garmin", "vital", "strava", "auto_sync"]);

function sourcePriority(s: string | null | undefined): number {
  switch ((s ?? "").toLowerCase()) {
    case "garmin": return 4;     // native device data (power, cadence, streams)
    case "vital": return 4;      // aggregator device data
    case "strava": return 3;     // most reliable distance + segments
    case "auto_sync": return 2;  // HealthKit fallback
    case "voice_log": return 1;  // annotation only
    default: return 0;
  }
}

/// Reject impossible activities — a watch left running (forgot to pause)
/// logs absurd pace either way: fast (left running in a car) or slow
/// (left running while stopped). Bounds are well outside any real effort.
function isPlausibleRun(log: TimelineLog): boolean {
  const dist = log.workout_distance_miles ?? 0;
  if (dist <= 0 || dist > 50) return false;
  const dur = log.workout_duration_minutes ?? 0;
  if (dur > 0 && dist >= 1) {
    const paceSec = (dur * 60) / dist;
    if (paceSec < 210 || paceSec > 960) return false; // 3:30/mi … 16:00/mi
  }
  return true;
}

/// Whether a run counts toward stats. The athlete's explicit decision
/// (stats_excluded) overrides the heuristic; null falls back to plausibility.
function isIncluded(log: TimelineLog): boolean {
  if (log.stats_excluded === true) return false;  // trimmed
  if (log.stats_excluded === false) return true;  // kept
  return isPlausibleRun(log);                      // undecided → heuristic
}

/**
 * The canonical "which runs count" pipeline: running only → the athlete's
 * inclusion decision → one row per physical workout.
 *
 * Exported because it is NOT optional for anything that reads training_logs
 * for analytics. Skipping it double-counts every run the athlete both synced
 * and spoke about: on the live athlete, four sessions in a 90-day window carry
 * a `strava` row and a `voice_log` row with identical timestamp, distance,
 * duration and lap count, including the two largest threshold sessions in the
 * block. `pace_bands` and `band_laps` both bypassed this and reported those
 * sessions twice — see the header note in `bandLaps.ts`.
 */
export function analyticsRunLogs(logs: TimelineLog[]): TimelineLog[] {
  const running = logs.filter((l) => {
    const type = (l.workout_type ?? "").toLowerCase();
    return !NON_RUNNING_TYPES.has(type) && (l.workout_distance_miles ?? 0) > 0;
  });
  return dedupeRunLogs(running.filter(isIncluded));
}

/// One row per physical workout. Per UTC day: if a GPS row exists, drop
/// voice_log rows; cluster remaining by distance (±0.1 mi); within a
/// cross-source cluster keep the highest-priority source, else keep all
/// (same-source same-distance = real WU/CD or doubles).
function dedupeRunLogs(logs: TimelineLog[]): TimelineLog[] {
  const byDay = new Map<number, TimelineLog[]>();
  for (const l of logs) {
    const d = dayUTC(l.workout_date).getTime();
    const arr = byDay.get(d);
    if (arr) arr.push(l); else byDay.set(d, [l]);
  }

  const out: TimelineLog[] = [];
  for (const dayLogs of byDay.values()) {
    const hasGps = dayLogs.some((l) => GPS_SOURCES.has((l.source ?? "").toLowerCase()));
    const candidates = hasGps
      ? dayLogs.filter((l) => GPS_SOURCES.has((l.source ?? "").toLowerCase()))
      : dayLogs;

    const sorted = candidates
      .filter((l) => (l.workout_distance_miles ?? 0) > 0)
      .sort((a, b) => (b.workout_distance_miles ?? 0) - (a.workout_distance_miles ?? 0));

    const clusters: TimelineLog[][] = [];
    for (const log of sorted) {
      const m = log.workout_distance_miles ?? 0;
      const i = clusters.findIndex((c) => Math.abs((c[0].workout_distance_miles ?? 0) - m) < 0.1);
      if (i >= 0) clusters[i].push(log); else clusters.push([log]);
    }

    for (const cluster of clusters) {
      const distinct = new Set(cluster.map((l) => (l.source ?? "").toLowerCase()));
      if (distinct.size > 1) {
        out.push(cluster.reduce((best, l) =>
          sourcePriority(l.source) > sourcePriority(best.source) ? l : best));
      } else {
        out.push(...cluster);
      }
    }
  }
  return out;
}

// ─── Flagged runs (surface, don't delete) ─────────────────────────────

export interface FlaggedRun {
  date: string;       // YYYY-MM-DD
  miles: number;
  pace: string | null; // "M:SS"
  reason: string;
  training_log_id: string;
}

function toFlagged(l: TimelineLog, reasonOverride?: string): FlaggedRun {
  const dist = l.workout_distance_miles ?? 0;
  const p = logPaceSec(l);
  return {
    date: dayUTC(l.workout_date).toISOString().split("T")[0],
    miles: Math.round(dist * 10) / 10,
    pace: p ? `${Math.floor(p / 60)}:${String(p % 60).padStart(2, "0")}` : null,
    reason: reasonOverride ?? (dist > 50 ? "distance unusually long" : "impossible pace — watch left running?"),
    training_log_id: l.id,
  };
}

/// Auto-flagged, UNDECIDED runs (heuristic says implausible, athlete hasn't
/// chosen). Surfaced for the athlete to Trim or Keep — never auto-deleted.
export function flaggedRuns(logs: TimelineLog[]): FlaggedRun[] {
  const out: FlaggedRun[] = [];
  for (const l of logs) {
    if (NON_RUNNING_TYPES.has((l.workout_type ?? "").toLowerCase())) continue;
    if ((l.workout_distance_miles ?? 0) <= 0) continue;
    if (l.stats_excluded != null) continue; // already decided
    if (isPlausibleRun(l)) continue;
    out.push(toFlagged(l));
  }
  return out;
}

/// Runs the athlete explicitly TRIMMED (stats_excluded = true) — listed so
/// the UI can offer Restore.
export function trimmedRuns(logs: TimelineLog[]): FlaggedRun[] {
  const out: FlaggedRun[] = [];
  for (const l of logs) {
    if (NON_RUNNING_TYPES.has((l.workout_type ?? "").toLowerCase())) continue;
    if ((l.workout_distance_miles ?? 0) <= 0) continue;
    if (l.stats_excluded === true) out.push(toFlagged(l, "trimmed by you"));
  }
  return out;
}

// ─── Main builder ──────────────────────────────────────────────────────

export function buildTrendsTimeline(
  input: TimelineInput,
  weeks: number,
  reference: Date = new Date(),
): TrendsWeekOut[] {
  const featuresById = new Map<string, TimelineFeature>();
  for (const f of input.features) featuresById.set(f.training_log_id, f);

  // Running only → included (the athlete's stats_excluded decision overriding
  // the heuristic) → one row per physical workout. Excluded runs aren't
  // deleted — see flaggedRuns()/trimmedRuns().
  const deduped = analyticsRunLogs(input.logs);
  const runLogs = deduped.map((l) => ({ log: l, t: dayUTC(l.workout_date).getTime() }));

  const mentionsWithT = input.mentions.map((m) => ({
    m,
    t: dayUTC(m.mentioned_at).getTime(),
  }));

  const windows = buildWeekWindows(weeks, reference);

  return windows.map(({ start, end }) => {
    const s = start.getTime();
    const e = end.getTime();

    const weekLogs = runLogs.filter((r) => r.t >= s && r.t < e).map((r) => r.log);
    const weekMentions = mentionsWithT
      .filter((r) => r.t >= s && r.t < e)
      .map((r) => r.m);

    // Volume + intensity.
    //
    // Quality is counted PER SEGMENT at MP-or-faster (see _shared/quality-volume.ts),
    // not by classifying the whole workout. The old all-or-nothing rule booked a
    // rep session's floats, rests and cooldown as quality, while a long run with
    // an MP block scored zero because its easy miles diluted the average.
    let miles = 0;
    let qualityMiles = 0;
    for (const log of weekLogs) {
      const dist = log.workout_distance_miles ?? 0;
      miles += dist;
      qualityMiles += qualityMilesForLog(
        log,
        input.mpSecPerMile ?? null,
        input.lapsByWorkout?.get(log.id),
      );
    }

    // Key session = highest-intensity quality log (tie → fastest pace).
    const qualityLogs = weekLogs.filter((l) => isQuality(l, featuresById.get(l.id)));
    let keyPaceSec: number | null = null;
    if (qualityLogs.length > 0) {
      const ranked = [...qualityLogs].sort((a, b) => {
        const ai = featuresById.get(a.id)?.intensity_score ?? -1;
        const bi = featuresById.get(b.id)?.intensity_score ?? -1;
        if (bi !== ai) return bi - ai;
        return (logPaceSec(a) ?? 1e9) - (logPaceSec(b) ?? 1e9);
      });
      const keyLog = ranked[0];
      // The REP pace, not the whole-workout blend — falls back only when we have
      // no lap-derived work pace for this session.
      keyPaceSec = input.keyWorkPaceByLog?.get(keyLog.id) ?? logPaceSec(keyLog);
    }

    // Dominant mood (modal; tie → most recent log's mood).
    const mood = dominantMood(weekLogs);

    // Niggles — distinct verbatim labels, ordered by mention date.
    const niggles = distinctNiggleLabels(weekMentions);
    const voiceQuote = representativeQuote(weekMentions);

    return {
      week_start: isoDate(start),
      month: monthAbbr(start),
      date_label: dateLabel(start),
      miles: Math.round(miles * 10) / 10,
      quality_miles: Math.round(qualityMiles * 10) / 10,
      key_pace_sec: keyPaceSec,
      mood,
      niggles,
      voice_quote: voiceQuote,
    };
  });
}

/**
 * Daily substrate for the Trends-v2 calendar. Shares the weekly builder's
 * dedup / inclusion / quality / mood logic verbatim so a day can never
 * disagree with the week it rolls into — the same "one home for the math"
 * rule the timeline exists to enforce.
 *
 * Returns a DENSE array: one entry per UTC day from the oldest window's
 * Monday through `reference` (today), rest days included. Days beyond the
 * reference (the rest of the current partial week) are not emitted.
 */
export function buildDailyTimeline(
  input: TimelineInput,
  weeks: number,
  reference: Date = new Date(),
): TrendsDayOut[] {
  const featuresById = new Map<string, TimelineFeature>();
  for (const f of input.features) featuresById.set(f.training_log_id, f);

  // The same pipeline as the weekly builder — literally, not by restatement —
  // then grouped by UTC day. The anti-drift test pins daily sums to weekly.
  const deduped = analyticsRunLogs(input.logs);
  const runsByDay = new Map<string, TimelineLog[]>();
  for (const l of deduped) {
    const key = isoDate(dayUTC(l.workout_date));
    (runsByDay.get(key) ?? runsByDay.set(key, []).get(key)!).push(l);
  }

  // Mood is a property of a logged feeling, not of a run: a mood-only
  // check-in (zero distance, dropped by the running filter) still colors its
  // day. Gather from ANY log with a mood, excluding only explicit trims.
  const moodLogsByDay = new Map<string, TimelineLog[]>();
  for (const l of input.logs) {
    if (!l.mood || l.stats_excluded === true) continue;
    const key = isoDate(dayUTC(l.workout_date));
    (moodLogsByDay.get(key) ?? moodLogsByDay.set(key, []).get(key)!).push(l);
  }

  // Niggles by day — verbatim, never interpreted.
  const nigByDay = new Map<string, TimelineMention[]>();
  for (const m of input.mentions) {
    const key = isoDate(dayUTC(m.mentioned_at));
    (nigByDay.get(key) ?? nigByDay.set(key, []).get(key)!).push(m);
  }

  const windows = buildWeekWindows(weeks, reference);
  const firstStart = windows[0].start;
  const lastDay = new Date(Date.UTC(
    reference.getUTCFullYear(),
    reference.getUTCMonth(),
    reference.getUTCDate(),
  ));

  // A paused watch produces rows like "10 mi in 236 min", and the demand
  // term's EWMA would carry that artifact for six weeks. The design doc clips
  // at a fixed 14 min/mi, but a hardcoded pace constant is exactly what this
  // repo forbids (see `feedback_no_hardcoded_paces` — all paces come from real
  // data), and 14 min/mi is also simply wrong for some athletes. So the gate is
  // ATHLETE-RELATIVE: anything slower than twice the athlete's own median pace
  // in this window is re-imputed at that median. Self-calibrating, no constant.
  const observedPaces: number[] = [];
  for (const l of deduped) {
    const mi = l.workout_distance_miles ?? 0;
    const min = l.workout_duration_minutes ?? 0;
    if (mi > 0 && min > 0) observedPaces.push(min / mi);
  }
  observedPaces.sort((a, b) => a - b);
  const medianPace = observedPaces.length > 0
    ? observedPaces[Math.floor(observedPaces.length / 2)]
    : null;

  /** Duration in minutes, with the paused-watch artifact re-imputed. */
  const cleanDuration = (l: TimelineLog): number => {
    const min = l.workout_duration_minutes ?? 0;
    const mi = l.workout_distance_miles ?? 0;
    if (min <= 0) return 0;
    if (medianPace === null || mi <= 0) return min;
    return min / mi > 2 * medianPace ? mi * medianPace : min;
  };

  // ── Per-log zone breakdown, computed once ──
  // Same laps and the same `segmentFromLaps` call the quality surfaces use,
  // but WITHOUT the `WORK_ZONES` filter — easy and steady volume is the bulk
  // of this surface, not noise to be excluded.
  //
  // (2026-08-11) Rest bouts used to be DROPPED here, on the reasoning that a
  // recovery jog between reps is not volume at the rep's zone and counting it
  // would inflate the fast end. The first half of that is right; the
  // conclusion was not. Dropping them meant a 40-minute session scored as 33
  // — the day's zone minutes did not add up to the day's duration, and the
  // athlete was told a float between reps cost them nothing.
  //
  // They are now booked to `recovery`, which weighs 1.0. That answers the
  // original objection exactly — the minutes are counted, but at the SLOWEST
  // weight in the table, never at the rep's — and it makes a run's minutes
  // reconcile with its duration. iOS folds `recovery` into `easy` for display
  // (`ZoneTaxonomy.normalise`), so it reads as easy volume, which is what it
  // is.
  const zoneTotalsByLog = new Map<
    string,
    Map<Zone, { seconds: number; meters: number; loadMin: number }>
  >();
  if (input.zones && input.lapsByWorkout && input.lapsByWorkout.size > 0) {
    for (const l of deduped) {
      const laps = input.lapsByWorkout.get(l.id);
      if (!laps || laps.length === 0) continue;
      let seg;
      try {
        // Heat-adjusted classification. A 78°F / 75°F-dew-point tempo runs
        // slow on the clock and is not easy work; scoring it off raw pace made
        // the load score lowest in exactly the conditions that cost the most.
        // Scoped to THIS breakdown — key sessions, quality volume and the rep
        // surfaces still classify on raw pace, and moving those is a separate
        // decision with its own before/after check.
        seg = segmentFromLaps(laps, input.zones, { useHeatAdjustedPace: true });
      } catch (e) {
        // One malformed workout must not take the whole timeline down. The
        // day degrades to "no breakdown", which the client already handles.
        console.error("[timeline] zone breakdown skipped for log", l.id, e);
        continue;
      }
      const byZone = new Map<Zone, { seconds: number; meters: number; loadMin: number }>();
      for (const b of seg.bouts) {
        if (b.seconds <= 0) continue;
        // Rest bouts book to `recovery` (weight 1.0) rather than to the rep's
        // zone — counted, but never at the fast end.
        const z: Zone = b.isRest ? "recovery" : b.zone;
        const cur = byZone.get(z) ?? { seconds: 0, meters: 0, loadMin: 0 };
        cur.seconds += b.seconds;
        cur.meters += b.distanceMeters;
        // The CONTINUOUS curve, per bout, summed before the zone rollup — so a
        // sub-mile rep keeps its >8 weight instead of being averaged into the
        // `mile` bucket's flat 8.0.
        cur.loadMin += (b.seconds / 60) *
          (b.weight ?? (z === "recovery" ? 1.0 : ZONE_WEIGHTS[z]));
        byZone.set(z, cur);
      }
      if (byZone.size > 0) zoneTotalsByLog.set(l.id, byZone);
    }
  }

  const out: TrendsDayOut[] = [];
  for (
    const d = new Date(firstStart);
    d.getTime() <= lastDay.getTime();
    d.setUTCDate(d.getUTCDate() + 1)
  ) {
    const key = isoDate(d);
    const dayRuns = runsByDay.get(key) ?? [];
    const miles = dayRuns.reduce((s, l) => s + (l.workout_distance_miles ?? 0), 0);
    const durationMin = dayRuns.reduce((s, l) => s + cleanDuration(l), 0);
    // Null (not 0) when NO run that day carries a stress_load — 0 would be
    // indistinguishable from a genuinely zero-load day and would poison the
    // chronic baseline once the backfill lands.
    const stressRuns = dayRuns.filter((l) => typeof l.stress_load === "number");
    const stressLoad = stressRuns.length > 0
      ? stressRuns.reduce((s, l) => s + (l.stress_load ?? 0), 0)
      : null;

    let type: TrendsDayOut["type"] = "rest";
    if (dayRuns.length > 0) {
      if (dayRuns.some(isLong)) type = "long";
      else if (dayRuns.some((l) => isQuality(l, featuresById.get(l.id)))) type = "key";
      else type = "easy";
    }

    const niggles = (nigByDay.get(key) ?? []).map((m) => ({
      area: m.body_area,
      side: m.side,
      severity: m.severity_hint ?? null,
      quote: m.verbatim_quote,
    }));

    // Roll this day's runs up by zone. Undefined — not {} — when none of the
    // day's runs carried laps, so the client can tell "no breakdown available"
    // apart from "a real rest day".
    let zoneMinutes: Record<string, number> | undefined;
    let zoneMiles: Record<string, number> | undefined;
    let zoneLoad: Record<string, number> | undefined;
    const dayZoned = dayRuns.filter((l) => zoneTotalsByLog.has(l.id));
    if (dayZoned.length > 0) {
      const acc = new Map<Zone, { seconds: number; meters: number; loadMin: number }>();
      for (const l of dayZoned) {
        for (const [z, v] of zoneTotalsByLog.get(l.id)!) {
          const cur = acc.get(z) ?? { seconds: 0, meters: 0, loadMin: 0 };
          cur.seconds += v.seconds;
          cur.meters += v.meters;
          cur.loadMin += v.loadMin;
          acc.set(z, cur);
        }
      }
      zoneMinutes = {};
      zoneMiles = {};
      zoneLoad = {};
      for (const [z, v] of acc) {
        const min = round2(v.seconds / 60);
        const mi = round2(v.meters / METERS_PER_MILE);
        if (min <= 0) continue; // omit, never zero-fill
        zoneMinutes[z] = min;
        zoneMiles[z] = mi;
        zoneLoad[z] = round2(v.loadMin);
      }
    }

    // The day unrolled. Chronological, because a strip that draws them in
    // fetch order draws the evening run first on half the days.
    const runs: TrendsRunOut[] = dayRuns
      .slice()
      .sort((a, b) =>
        String(a.workout_date).localeCompare(String(b.workout_date))
      )
      .map((l) => {
        const byZone = zoneTotalsByLog.get(l.id);
        let zMin: Record<string, number> | undefined;
        let zMi: Record<string, number> | undefined;
        let zLoad: Record<string, number> | undefined;
        if (byZone && byZone.size > 0) {
          zMin = {};
          zMi = {};
          zLoad = {};
          for (const [z, v] of byZone) {
            const min = round2(v.seconds / 60);
            if (min <= 0) continue; // omit, never zero-fill
            zMin[z] = min;
            zMi[z] = round2(v.meters / METERS_PER_MILE);
            zLoad[z] = round2(v.loadMin);
          }
          if (Object.keys(zMin).length === 0) {
            zMin = undefined;
            zMi = undefined;
            zLoad = undefined;
          }
        }
        return {
          id: l.id,
          started_at: String(l.workout_date),
          duration_min: Math.round(cleanDuration(l)),
          duration_sec: Math.round(cleanDuration(l) * 60),
          miles: Math.round((l.workout_distance_miles ?? 0) * 10) / 10,
          ...(zMin ? { zone_minutes: zMin, zone_miles: zMi, zone_load: zLoad } : {}),
        };
      });

    out.push({
      date: key,
      miles: Math.round(miles * 10) / 10,
      type,
      ...(zoneMinutes
        ? { zone_minutes: zoneMinutes, zone_miles: zoneMiles, zone_load: zoneLoad }
        : {}),
      ...(runs.length > 0 ? { runs } : {}),
      // The DAY's mood is the hardest session's mood, not the modal one.
      // See `hardestSessionMood`. The week keeps `dominantMood` — that is a
      // distribution over separate days, a different question.
      mood: hardestSessionMood(moodLogsByDay.get(key) ?? [], featuresById),
      niggles,
      duration_min: Math.round(durationMin),
      stress_load: stressLoad,
    });
  }
  return out;
}

// ─── Sub-derivations ───────────────────────────────────────────────────

/**
 * A single day's mood: **the mood of the hardest session that logged one.**
 *
 * Not the modal mood. If the warm-up went well, the workout went badly and the
 * cool-down went well, that is a bad day — and a modal count returns "good",
 * 2 votes to 1. The session that mattered is the one carrying the signal, and
 * counting logs launders it under the easy volume either side of it.
 *
 * Ranking, in order:
 *   1. `intensity_score` — the canonical load number, from `features`.
 *   2. Distance — a long run with no computed feature still outranks a
 *      3-mile shakeout.
 *   3. Most recent — a deterministic tiebreak, never a coin flip.
 *
 * A mood-only check-in (zero distance, no feature) ranks last, so it colours
 * the day only when no session carried a mood — which is exactly right on a
 * rest day, where the check-in IS the day. If you decide a deliberate
 * end-of-day check-in should outrank the session it follows, this is the one
 * function to change.
 *
 * Returns null when nothing logged a feeling. A mood is never fabricated and
 * never carried forward from yesterday.
 *
 * NB: this is a DAY-level rule. `buildTrendsTimeline` deliberately keeps
 * `dominantMood` for the week, because rolling up seven separate days asks
 * "what was the common register?", not "which of these simultaneous readings
 * represents this session?" — picking the single hardest session out of a
 * whole week would be a sample of one.
 */
function hardestSessionMood(
  logs: TimelineLog[],
  featuresById: Map<string, TimelineFeature>,
): string | null {
  const withMood = logs.filter((l) => l.mood);
  if (withMood.length === 0) return null; // never fabricate a feeling

  const ranked = [...withMood].sort((a, b) => {
    const ai = featuresById.get(a.id)?.intensity_score ?? -1;
    const bi = featuresById.get(b.id)?.intensity_score ?? -1;
    if (bi !== ai) return bi - ai;

    const ad = a.workout_distance_miles ?? 0;
    const bd = b.workout_distance_miles ?? 0;
    if (bd !== ad) return bd - ad;

    return new Date(b.workout_date).getTime() - new Date(a.workout_date).getTime();
  });

  return ranked[0].mood!.toLowerCase();
}

/**
 * Modal mood across a set of logs (tie → the most recent log's mood).
 *
 * Used for the WEEK only. For a single day, see `hardestSessionMood` — a day's
 * sessions are readings of one training unit, and there the hardest one wins.
 */
function dominantMood(logs: TimelineLog[]): string | null {
  const withMood = logs.filter((l) => l.mood);
  if (withMood.length === 0) return null; // never fabricate a feeling
  const counts = new Map<string, number>();
  for (const l of withMood) {
    const key = l.mood!.toLowerCase();
    counts.set(key, (counts.get(key) ?? 0) + 1);
  }
  let best: string | null = null;
  let bestN = -1;
  for (const [mood, n] of counts) {
    if (n > bestN) {
      best = mood;
      bestN = n;
    }
  }
  // Tie-break: if the most recent log's mood is also a max, prefer it.
  const recent = [...withMood].sort(
    (a, b) => new Date(b.workout_date).getTime() - new Date(a.workout_date).getTime(),
  )[0];
  if (recent?.mood && (counts.get(recent.mood.toLowerCase()) ?? 0) === bestN) {
    return recent.mood.toLowerCase();
  }
  return best;
}

function distinctNiggleLabels(mentions: TimelineMention[]): string[] {
  const ordered = [...mentions].sort(
    (a, b) => new Date(a.mentioned_at).getTime() - new Date(b.mentioned_at).getTime(),
  );
  const seen = new Set<string>();
  const out: string[] = [];
  for (const m of ordered) {
    const label = m.side ? `${m.side} ${m.body_area}` : m.body_area;
    if (!seen.has(label)) {
      seen.add(label);
      out.push(label);
    }
  }
  return out;
}

function representativeQuote(mentions: TimelineMention[]): string | null {
  if (mentions.length === 0) return null;
  const ranked = [...mentions].sort((a, b) => {
    const ar = SEVERITY_RANK[a.severity_hint?.toLowerCase()] ?? 0;
    const br = SEVERITY_RANK[b.severity_hint?.toLowerCase()] ?? 0;
    if (br !== ar) return br - ar;
    return new Date(b.mentioned_at).getTime() - new Date(a.mentioned_at).getTime();
  });
  return ranked[0].verbatim_quote ?? null;
}

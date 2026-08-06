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

  const out: TrendsDayOut[] = [];
  for (
    const d = new Date(firstStart);
    d.getTime() <= lastDay.getTime();
    d.setUTCDate(d.getUTCDate() + 1)
  ) {
    const key = isoDate(d);
    const dayRuns = runsByDay.get(key) ?? [];
    const miles = dayRuns.reduce((s, l) => s + (l.workout_distance_miles ?? 0), 0);

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

    out.push({
      date: key,
      miles: Math.round(miles * 10) / 10,
      type,
      // The DAY's mood is the hardest session's mood, not the modal one.
      // See `hardestSessionMood`. The week keeps `dominantMood` — that is a
      // distribution over separate days, a different question.
      mood: hardestSessionMood(moodLogsByDay.get(key) ?? [], featuresById),
      niggles,
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

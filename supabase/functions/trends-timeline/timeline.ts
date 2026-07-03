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

const GPS_SOURCES = new Set(["strava", "auto_sync"]);

function sourcePriority(s: string | null | undefined): number {
  switch ((s ?? "").toLowerCase()) {
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

  // Running logs only, with a parsed day for bucketing.
  const running = input.logs.filter((l) => {
    const type = (l.workout_type ?? "").toLowerCase();
    return !NON_RUNNING_TYPES.has(type) && (l.workout_distance_miles ?? 0) > 0;
  });
  // Included = athlete's decision (stats_excluded) overriding the heuristic.
  // Excluded runs aren't deleted — see flaggedRuns()/trimmedRuns().
  const included = running.filter(isIncluded);
  const deduped = dedupeRunLogs(included);
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

    // Volume + intensity
    let miles = 0;
    let qualityMiles = 0;
    for (const log of weekLogs) {
      const dist = log.workout_distance_miles ?? 0;
      miles += dist;
      if (isQuality(log, featuresById.get(log.id))) qualityMiles += dist;
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
      keyPaceSec = logPaceSec(ranked[0]);
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

// ─── Sub-derivations ───────────────────────────────────────────────────

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

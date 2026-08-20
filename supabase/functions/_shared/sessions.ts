/**
 * Sessions — the unit an athlete actually trains in.
 *
 * A SESSION is not a day and it is not an upload. Aug 4 2026 is five Strava
 * activities, which are two sessions: a 6:08am track workout (warm-up +
 * threshold + cooldown) and a 5:52pm double. Rolling to the DAY reports one
 * 15.7 mi threshold day that never happened; rolling to the UPLOAD reports
 * five runs that never happened either.
 *
 * This is the server-side port of `RunningLog/App/SessionRollup.swift`, which
 * has shipped on iOS since 2026-08-11 and is used only by The Sheet. Nothing
 * server-side had a session concept, so every edge function, every analyzer and
 * every weekly aggregate has been counting uploads and calling them runs.
 *
 * THE TWO RULES THAT MATTER
 *
 *   1. LOCAL day, never UTC. `workout_date` is timestamptz. Grouping by
 *      `(workout_date AT TIME ZONE 'UTC')::date` — which several edge functions
 *      and the old dedup sweep do — misplaces 8 rows / 39.2 mi of this
 *      athlete's history onto the wrong date: an Aug 5 7:01pm run is stored
 *      `2026-08-06 00:01Z`. The timezone comes from `athlete_settings.timezone`.
 *
 *   2. The gap is measured from the previous piece's END, not its start.
 *      90 minutes, because Jul 21 2026's warm-up-to-cooldown gap is 65 minutes
 *      and is plainly one session. Much past 90 starts merging a morning
 *      shakeout into a midday workout.
 *
 * This module is PURE. No fetching, no writing, no Supabase import — so it is
 * testable without a network and can be called from any edge function.
 *
 * NAME COLLISION: `_shared/shared/sessions.ts` also exists and exports
 * `groupIntoSessions()` — an older, DIFFERENT rule (UTC day, 3h start-to-start),
 * consumed by `builders/buildLoadMetrics.ts`. Check which path you resolved.
 *
 * GARBAGE IN: session grouping is only as good as `workout_date`. 108 of this
 * athlete's 261 running rows are stored local-as-UTC (a 6:05am run written as
 * `06:05Z`), and on the 9 days that mix corrupt and correct rows the grouping
 * is wrong — see the "timestamps" limit in SESSIONS-APPLY.md before trusting a
 * session count. `assertPlausibleStartHours()` below is the cheap guard.
 */

export interface SessionPiece {
  id: string;
  /** ISO timestamp with offset — the raw `workout_date`. */
  workoutDate: string;
  miles: number | null;
  durationMinutes: number | null;
  workoutType?: string | null;
  mood?: string | null;
  notes?: string | null;
  source?: string | null;
}

export interface TrainingSession {
  id: string;
  /** Local calendar day, YYYY-MM-DD in the athlete's timezone. */
  day: string;
  /** Clock start of the session, ISO. */
  start: string;
  pieces: SessionPiece[];
  miles: number;
  minutes: number;
  /** Normalized type of the HARDEST piece — what the session is named for. */
  typeKey: string | null;
  isQuality: boolean;
  /** True when this is a day's second or later session — a genuine double. */
  isSecond: boolean;
  mood: string | null;
  note: string | null;
}

/** Mirrors `WorkoutLabel.normalize(_:)`. Keep in lockstep with the Swift. */
export function normalizeWorkoutType(raw?: string | null): string | null {
  const t = raw?.trim().toLowerCase();
  if (!t) return null;
  switch (t) {
    case "interval": return "intervals";
    case "longrun":
    case "long": return "long_run";
    case "longwo": return "long_wo";
    case "cross_training":
    case "crosstraining":
    case "crosstrain": return "cross_train";
    case "tempo": return "threshold";
    default: return t;
  }
}

/**
 * Intent ladder, easiest → hardest. A session is named for its hardest piece,
 * so a track day reads "threshold", not "recovery" because the warm-up sorted
 * first. Ranked on the NORMALIZED key: `tempo` and `interval` are both live in
 * stored rows, and an unknown key must rank -1 rather than name a day for its
 * warm-up.
 */
export const WORKOUT_LADDER = [
  "recovery", "easy", "moderate", "steady", "long_run",
  "progression", "fartlek", "threshold", "intervals", "long_wo", "race",
] as const;

export const QUALITY_KEYS = new Set([
  "threshold", "intervals", "fartlek", "progression", "long_wo", "race",
]);

export function rankWorkout(typeKey?: string | null): number {
  const n = normalizeWorkoutType(typeKey);
  if (!n) return -1;
  const i = (WORKOUT_LADDER as readonly string[]).indexOf(n);
  return i;
}

export function isQuality(typeKey?: string | null): boolean {
  const n = normalizeWorkoutType(typeKey);
  return n ? QUALITY_KEYS.has(n) : false;
}

/** Strava's default titles. A row whose only note is one of these has no words. */
const JUNK_TITLES = new Set([
  "morning run", "afternoon run", "evening run", "lunch run",
  "night run", "morning jog", "run", "treadmill", "workout",
]);

/**
 * Local calendar day (YYYY-MM-DD) for an instant, in an IANA timezone.
 * `en-CA` yields ISO-ordered parts, which is why it is used rather than
 * hand-assembling from `getFullYear()` (that would be the SERVER's timezone).
 */
export function localDayKey(iso: string, timeZone: string): string {
  const d = new Date(iso);
  if (isNaN(d.getTime())) throw new Error(`bad workoutDate: ${iso}`);
  return new Intl.DateTimeFormat("en-CA", {
    timeZone, year: "numeric", month: "2-digit", day: "2-digit",
  }).format(d);
}

/** A new piece joins the current session when it starts within this many
 *  minutes of the previous piece's END. */
export const SESSION_GAP_MINUTES = 90;

export function buildSessions(
  rows: SessionPiece[],
  timeZone: string,
  gapMinutes: number = SESSION_GAP_MINUTES,
): TrainingSession[] {
  const running = rows.filter((r) => (r.miles ?? 0) > 0);

  const byDay = new Map<string, SessionPiece[]>();
  for (const r of running) {
    const key = localDayKey(r.workoutDate, timeZone);
    const list = byDay.get(key);
    if (list) list.push(r); else byDay.set(key, [r]);
  }

  const out: TrainingSession[] = [];

  for (const [day, dayRows] of byDay) {
    const ordered = [...dayRows].sort(
      (a, b) => new Date(a.workoutDate).getTime() - new Date(b.workoutDate).getTime(),
    );

    // Split into sessions by clock gap, measured from the previous piece's END.
    const groups: SessionPiece[][] = [];
    for (const row of ordered) {
      const last = groups[groups.length - 1];
      const prev = last?.[last.length - 1];
      if (prev) {
        const prevEndMs = new Date(prev.workoutDate).getTime()
          + (prev.durationMinutes ?? 0) * 60_000;
        const gapMin = (new Date(row.workoutDate).getTime() - prevEndMs) / 60_000;
        if (gapMin <= gapMinutes) { last.push(row); continue; }
      }
      groups.push([row]);
    }

    groups.forEach((pieces, index) => {
      const miles = pieces.reduce((s, p) => s + (p.miles ?? 0), 0);
      const minutes = pieces.reduce((s, p) => s + (p.durationMinutes ?? 0), 0);

      const hardest = pieces.reduce((a, b) => (rankWorkout(b.workoutType) > rankWorkout(a.workoutType) ? b : a));

      // Mood and words belong to the session's NAMED piece, not to whichever
      // cooldown happened to carry a memo. Prefer the hardest piece, then walk
      // the rest hardest-first.
      const byIntent = [...pieces].sort((a, b) => rankWorkout(b.workoutType) - rankWorkout(a.workoutType));
      const spoken = [hardest, ...byIntent].find(
        (p) => p.mood != null || (p.source ?? "").toLowerCase() === "voice_log",
      );
      const noteCarrier = [hardest, ...byIntent].find((p) => {
        const n = p.notes?.trim();
        return !!n && !JUNK_TITLES.has(n.toLowerCase());
      });

      out.push({
        id: pieces[0].id,
        day,
        start: pieces[0].workoutDate,
        pieces,
        miles: Math.round(miles * 100) / 100,
        minutes: Math.round(minutes * 100) / 100,
        typeKey: normalizeWorkoutType(hardest.workoutType),
        isQuality: isQuality(hardest.workoutType),
        isSecond: index > 0,
        mood: spoken?.mood ?? null,
        note: noteCarrier?.notes?.trim() ?? null,
      });
    });
  }

  return out.sort((a, b) => new Date(a.start).getTime() - new Date(b.start).getTime());
}

/** Sessions → weekly totals. THE function every weekly aggregate should use. */
export function weeklyTotals(sessions: TrainingSession[]) {
  const days = new Set(sessions.map((s) => s.day));
  return {
    sessions: sessions.length,
    pieces: sessions.reduce((s, x) => s + x.pieces.length, 0),
    daysRun: days.size,
    doubles: sessions.filter((s) => s.isSecond).length,
    miles: Math.round(sessions.reduce((s, x) => s + x.miles, 0) * 100) / 100,
    minutes: Math.round(sessions.reduce((s, x) => s + x.minutes, 0) * 100) / 100,
    qualitySessions: sessions.filter((s) => s.isQuality).length,
  };
}

/**
 * Cheap data-quality guard for the local-as-UTC corruption described above.
 *
 * A row stored local-as-UTC lands ~5h early, which pushes this athlete's 6am
 * runs into a phantom 1am-4am cluster. Almost nobody starts a run between
 * midnight and 5am, so a nonzero count here means `workout_date` is unreliable
 * and the session counts built from it are too. Returns the offending rows
 * rather than throwing — a caller decides whether that is a log line or a stop.
 *
 * This is a SMOKE ALARM, not a census: it catches ~two-thirds of the corruption
 * (a shifted 5pm run lands at noon and looks fine). The authoritative detector
 * needs a column this pure module never sees:
 *   `source='strava' AND external_streams->'meta'->>'start_date' IS NULL`
 */
export function assertPlausibleStartHours(
  rows: SessionPiece[],
  timeZone: string,
): { suspect: SessionPiece[]; suspectDays: string[]; mixedDays: string[] } {
  const fmt = new Intl.DateTimeFormat("en-US", { timeZone, hour: "numeric", hour12: false });
  const isSuspect = (r: SessionPiece) => {
    const h = Number(fmt.format(new Date(r.workoutDate)));
    return h >= 0 && h < 5;
  };

  const running = rows.filter((r) => (r.miles ?? 0) > 0);
  const suspect = running.filter(isSuspect);

  // A day where EVERY row is shifted still groups correctly (it is only on the
  // wrong date). A day that MIXES shifted and correct rows has its pieces
  // interleaved wrongly — that is the case that silently invents sessions.
  const byDay = new Map<string, SessionPiece[]>();
  for (const r of running) {
    const k = localDayKey(r.workoutDate, timeZone);
    const l = byDay.get(k);
    if (l) l.push(r); else byDay.set(k, [r]);
  }
  const suspectDays: string[] = [];
  const mixedDays: string[] = [];
  for (const [day, rs] of byDay) {
    const n = rs.filter(isSuspect).length;
    if (n === 0) continue;
    (n === rs.length ? suspectDays : mixedDays).push(day);
  }

  return { suspect, suspectDays: suspectDays.sort(), mixedDays: mixedDays.sort() };
}

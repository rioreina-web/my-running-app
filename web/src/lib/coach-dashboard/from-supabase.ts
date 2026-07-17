import "server-only";

import { createClient } from "@/lib/supabase/server";
import { createAdminClient } from "@/lib/supabase/admin";
import {
  derivePaceTableFromGoal,
  headlineZone,
  nearestZoneKey,
  totalWorkoutMiles,
  workoutZoneLabel,
  zoneLabelShort,
  type AthletePaceTable,
  type PaceZone,
} from "@/components/coach/workout-helpers";
import type {
  Acwr,
  CoachableMoment,
  DashboardData,
  DashboardDay,
  Mood,
  MoodSummary,
  NiggleGroup,
  Progression,
  WatchItem,
  WeekContext,
  WeeklyVolumeWeek,
  WorkoutDetail,
  WorkoutSplit,
} from "./types";
import {
  buildChart,
  buildConditions,
  buildHeadlineKpis,
  buildPrescribed,
  buildSplits,
  fmtPaceSec,
  heatAdjHeadline,
  parseBand,
  verdictTitle,
  type EnrichLap,
} from "./workout-enrichment";

// ── Row shapes we read (the client is untyped, so we assert these) ──────────
interface LogRow {
  id: string;
  workout_date: string;
  workout_distance_miles: number | null;
  workout_pace_per_mile: string | null;
  workout_type: string | null;
  mood: string | null;
  cleaned_notes: string | null;
  // Enrichment (P1) — all best-effort; a missing column degrades one block.
  workout_duration_minutes: number | null;
  scheduled_workout_id: string | null;
  weather_actual: Record<string, unknown> | null;
  start_time: string | null;
}
interface PlanRow {
  id: string;
  name: string;
  start_date: string;
  end_date: string;
  target_time_seconds: number | null;
}
interface MomentRow {
  id: string;
  rule_id: string | null;
  severity: string | null;
  summary: string | null;
  action_type: string | null;
  triggered_at: string | null;
}
interface StateRow {
  goal_time_seconds: number | null;
  acwr: number | null;
  monotony_7d: number | null;
  strain_7d: number | null;
  fitness_trend: string | null;
  fitness_vs_6mo_ago_label: string | null;
  mood_trend: string | null;
  last_mood: string | null;
}
interface MentionRow {
  id: string;
  training_log_id: string | null;
  body_area: string;
  side: string | null;
  verbatim_quote: string;
  mentioned_at: string;
}
interface LapRow {
  workout_id: string;
  lap_index: number;
  distance_meters: number | null;
  avg_pace_sec_per_mile: number | null;
  // Enrichment columns (running_workout_laps). Absent on old rows → the block
  // that needs them is simply omitted.
  heat_adjusted_pace_sec_per_mile: number | null;
  avg_heart_rate: number | null;
  temp_f: number | null;
  dew_point_f: number | null;
  heat_category: string | null;
  total_elevation_gain: number | null;
  is_rest: boolean | null;
}
interface ScheduledRow {
  id: string;
  workout_type: string | null;
  workout_data: { steps?: import("@/components/coach/workout-helpers").WorkoutStep[]; name?: string } | null;
  date: string | null;
}
interface PaceProfileRow {
  marathon_pace_seconds: number | null;
}
interface SettingsRow {
  display_name: string | null;
  bio: string | null;
  avatar_path: string | null;
}
interface ReadRow {
  training_log_id: string;
  body: string;
  question: string;
}

// Initials for the avatar: first letters of up to two name words ("Maya Chen"
// → "MC"), or the first two letters of a single word ("Rio" → "RI"). Falls
// back to the id slice when there's no name.
function initialsFrom(name: string, fallbackId: string): string {
  const words = name.trim().split(/\s+/).filter(Boolean);
  if (words.length >= 2) return (words[0][0] + words[1][0]).toUpperCase();
  if (words.length === 1 && words[0].length >= 2) return words[0].slice(0, 2).toUpperCase();
  if (words.length === 1) return words[0][0].toUpperCase();
  return fallbackId.slice(0, 2).toUpperCase();
}

// ── Lookup tables ───────────────────────────────────────────────────────────
// Real stored workout_type vocabulary (verified against the DB): easy,
// recovery, long_run, interval, intervals, tempo, threshold, race, steady,
// moderate, progression, strides, other, rest. Keep every spelling.
const WORKOUT_ZONE: Record<string, PaceZone | null> = {
  easy: "easy",
  recovery: "recovery",
  long_run: "longRun",
  long: "longRun",
  moderate: "moderate",
  steady: "steady",
  tempo: "threshold",
  threshold: "threshold",
  interval: "fiveK",
  intervals: "fiveK",
  fartlek: "fiveK",
  progression: "steady",
  strides: "fiveK",
  race: "mp",
  other: "easy",
  rest: null,
};
// Quality/long/race sessions — the ones that get a ★. Both spellings of
// interval, plus threshold, are the fixes for the missed Tuesdays.
const KEY_TYPES = new Set([
  "long_run",
  "long",
  "tempo",
  "threshold",
  "interval",
  "intervals",
  "fartlek",
  "race",
  "progression",
  "workout",
]);
// Pace zones that count as "quality" volume for content-based key detection.
const QUALITY_ZONES = new Set<PaceZone>(["mp", "hm", "threshold", "tenK", "fiveK", "threeK", "mile"]);
const TYPE_LABEL: Record<string, string> = {
  easy: "Easy",
  recovery: "Recovery",
  long_run: "Long run",
  long: "Long run",
  moderate: "Moderate",
  steady: "Steady",
  tempo: "Tempo",
  threshold: "Threshold",
  interval: "Intervals",
  intervals: "Intervals",
  fartlek: "Fartlek",
  progression: "Progression",
  strides: "Strides",
  race: "Race",
  other: "Session",
  rest: "Rest",
};
// Slow → fast; picks a day's headline zone when uploads span several.
const ZONE_RANK: Record<PaceZone, number> = {
  recovery: 0,
  easy: 1,
  longRun: 2,
  moderate: 3,
  steady: 4,
  mp: 5,
  hm: 6,
  threshold: 7,
  tenK: 8,
  fiveK: 9,
  threeK: 10,
  mile: 11,
};
const MOODS = new Set<Mood>(["energized", "positive", "neutral", "tired", "struggling", "injured"]);
const MOOD_ORDER: Mood[] = ["energized", "positive", "neutral", "tired", "struggling", "injured"];
const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
const DOWS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

// ── Small helpers ───────────────────────────────────────────────────────────
async function safe<T>(q: PromiseLike<{ data: T | null; error: unknown }>): Promise<T | null> {
  try {
    const { data, error } = await q;
    return error ? null : data;
  } catch {
    return null;
  }
}
const parseDate = (iso: string) => {
  const [y, m, d] = iso.slice(0, 10).split("-").map(Number);
  return new Date(y, m - 1, d);
};
const isoOf = (dt: Date) =>
  `${dt.getFullYear()}-${String(dt.getMonth() + 1).padStart(2, "0")}-${String(dt.getDate()).padStart(2, "0")}`;
const dateLabel = (dt: Date) => `${MONTHS[dt.getMonth()]} ${dt.getDate()}`;
const dowLabel = (dt: Date) => DOWS[dt.getDay()];
const cap = (s: string) => (s ? s.charAt(0).toUpperCase() + s.slice(1) : s);
const trimMiles = (mi: number) => (Number.isInteger(mi) ? `${mi}` : mi.toFixed(1));
const numMiles = (v: number | null) => Number(v ?? 0);
function fmtHMS(seconds: number): string {
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  const s = Math.round(seconds % 60);
  return `${h}:${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}`;
}
function mondayOf(dt: Date): Date {
  const d = new Date(dt);
  d.setHours(0, 0, 0, 0);
  d.setDate(d.getDate() - ((d.getDay() + 6) % 7));
  return d;
}
const zoneOf = (type: string | null): PaceZone | null => WORKOUT_ZONE[type ?? "easy"] ?? "easy";
const typeLabel = (type: string | null) => TYPE_LABEL[type ?? "easy"] ?? cap(type ?? "easy");
function niggleArea(m: MentionRow): string {
  const area = cap(m.body_area.replace(/_/g, " "));
  return m.side ? `${cap(m.side)} ${area.toLowerCase()}` : area;
}
function prettyRule(id: string): string {
  return id.replace(/[_-]+/g, " ").replace(/\b\w/g, (c) => c.toUpperCase());
}
function relTime(iso: string | null): string {
  if (!iso) return "";
  const days = Math.round((Date.now() - new Date(iso).getTime()) / 86400000);
  if (days <= 0) return "Today";
  if (days === 1) return "Yesterday";
  if (days < 7) return `${days} days ago`;
  if (days < 14) return "Last week";
  return `${Math.round(days / 7)} weeks ago`;
}

/**
 * Read one athlete's real data and shape it into the dashboard payload.
 * The caller MUST have already gated coach access to `athleteId`.
 *
 * Coach-scoped tables (training_logs, training_plans, coachable_moments) are
 * read through the RLS cookie client; athlete_state and body_mentions are read
 * through the service-role client (spec §3). Every read is best-effort — a
 * missing table/column degrades that section, it never 500s the page.
 *
 * The daily overlay is one entry PER CALENDAR DAY: multiple uploads on a day
 * are summed into one bar, segmented by pace zone.
 */
export async function buildDashboardFromSupabase(athleteId: string): Promise<DashboardData> {
  const supabase = await createClient();
  const admin = createAdminClient();

  const since = new Date();
  since.setDate(since.getDate() - 90);
  const sinceISO = since.toISOString().slice(0, 10);

  const [logs, plan, moments, state, mentions, paceProfile, settings] = await Promise.all([
    safe<LogRow[]>(
      supabase
        .from("training_logs")
        .select(
          "id, workout_date, workout_distance_miles, workout_pace_per_mile, workout_type, mood, cleaned_notes, workout_duration_minutes, scheduled_workout_id, weather_actual, start_time",
        )
        .eq("user_id", athleteId)
        .gte("workout_date", sinceISO)
        .order("workout_date", { ascending: true })
        .limit(400),
    ).then((d) => d ?? []),
    safe<PlanRow>(
      supabase
        .from("training_plans")
        .select("id, name, start_date, end_date, target_time_seconds")
        .eq("user_id", athleteId)
        .eq("status", "active")
        .order("created_at", { ascending: false })
        .limit(1)
        .maybeSingle(),
    ),
    safe<MomentRow[]>(
      supabase
        .from("coachable_moments")
        .select("id, rule_id, severity, summary, action_type, triggered_at")
        .eq("athlete_user_id", athleteId)
        .eq("status", "open")
        .order("triggered_at", { ascending: false })
        .limit(6),
    ).then((d) => d ?? []),
    safe<StateRow>(
      admin
        .from("athlete_state")
        .select("goal_time_seconds, acwr, monotony_7d, strain_7d, fitness_trend, fitness_vs_6mo_ago_label, mood_trend, last_mood")
        .eq("user_id", athleteId)
        .maybeSingle(),
    ),
    safe<MentionRow[]>(
      admin
        .from("body_mentions")
        .select("id, training_log_id, body_area, side, verbatim_quote, mentioned_at")
        .eq("user_id", athleteId)
        .gte("mentioned_at", sinceISO)
        .order("mentioned_at", { ascending: true }),
    ).then((d) => d ?? []),
    safe<PaceProfileRow>(
      admin.from("athlete_pace_profiles").select("marathon_pace_seconds").eq("user_id", athleteId).maybeSingle(),
    ),
    // Profile (name + bio) from the SETTINGS surface. Read through the
    // service-role client for the already-gated athlete, matching how
    // athlete_state / body_mentions are read above (athlete_settings SELECT is
    // owner-only, so the coach's cookie client wouldn't see it).
    safe<SettingsRow>(
      admin.from("athlete_settings").select("display_name, bio, avatar_path").eq("user_id", athleteId).maybeSingle(),
    ),
  ]);

  // Per-lap splits + the athlete's own pace table, so each run's miles land in
  // the zone its splits were ACTUALLY run at (not one zone from its type).
  const logIds = logs.map((l) => l.id);
  const laps = logIds.length
    ? (await safe<LapRow[]>(
        admin
          .from("running_workout_laps")
          .select(
            "workout_id, lap_index, distance_meters, avg_pace_sec_per_mile, heat_adjusted_pace_sec_per_mile, avg_heart_rate, temp_f, dew_point_f, heat_category, total_elevation_gain, is_rest",
          )
          .in("workout_id", logIds)
          .order("lap_index", { ascending: true })
          .limit(10000),
      )) ?? []
    : [];

  // Prescriptions for the linked scheduled_workouts — batched by id (spec §3
  // row 1). Read through the RLS cookie client (coach-scoped, same as logs).
  const scheduledIds = Array.from(
    new Set(logs.map((l) => l.scheduled_workout_id).filter((v): v is string => !!v)),
  );
  const scheduled = scheduledIds.length
    ? (await safe<ScheduledRow[]>(
        supabase
          .from("scheduled_workouts")
          .select("id, workout_type, workout_data, date")
          .in("id", scheduledIds),
      )) ?? []
    : [];
  const scheduledById = new Map<string, ScheduledRow>();
  for (const s of scheduled) scheduledById.set(s.id, s);

  // Cached coach reads (the AI observation), keyed by training_log_id. Written
  // only by the coach-workout-read edge function; read here through the admin
  // client (RLS SELECT is coach-scoped, so the cookie client wouldn't see it).
  const reads = logIds.length
    ? (await safe<ReadRow[]>(
        admin
          .from("coach_workout_reads")
          .select("training_log_id, body, question")
          .in("training_log_id", logIds),
      )) ?? []
    : [];
  const readByLogId = new Map<string, ReadRow>();
  for (const r of reads) readByLogId.set(r.training_log_id, r);

  // Next key session — the soonest upcoming quality/long day on the active plan
  // (best-effort; absent when there's no plan or no upcoming key day).
  const upcomingKey = plan
    ? (await safe<ScheduledRow[]>(
        supabase
          .from("scheduled_workouts")
          .select("id, workout_type, workout_data, date")
          .eq("plan_id", plan.id)
          .gte("date", new Date().toISOString().slice(0, 10))
          .in("workout_type", ["tempo", "intervals", "long_run", "race"])
          .order("date", { ascending: true })
          .limit(1),
      )) ?? []
    : [];

  // Prescribed weekly mileage — summed from the plan's scheduled workouts in
  // the window, bucketed by Monday week. Gives weekContext its "of N planned".
  const planWorkouts = plan
    ? (await safe<ScheduledRow[]>(
        supabase
          .from("scheduled_workouts")
          .select("id, workout_type, workout_data, date")
          .eq("plan_id", plan.id)
          .gte("date", sinceISO)
          .limit(500),
      )) ?? []
    : [];
  const plannedByWeek = new Map<string, number>();
  for (const sw of planWorkouts) {
    if (!sw.date) continue;
    const steps = sw.workout_data?.steps;
    if (!steps || steps.length === 0) continue;
    const mi = totalWorkoutMiles(steps);
    if (mi <= 0) continue;
    const monISO = isoOf(mondayOf(parseDate(sw.date)));
    plannedByWeek.set(monISO, (plannedByWeek.get(monISO) ?? 0) + mi);
  }
  const athletePaces: AthletePaceTable | undefined =
    paceProfile?.marathon_pace_seconds && Number(paceProfile.marathon_pace_seconds) > 0
      ? derivePaceTableFromGoal(Number(paceProfile.marathon_pace_seconds), "marathon")
      : undefined;
  const lapsByWorkout = new Map<string, LapRow[]>();
  for (const lap of laps) {
    const arr = lapsByWorkout.get(lap.workout_id);
    if (arr) arr.push(lap);
    else lapsByWorkout.set(lap.workout_id, [lap]);
  }
  const zmCache = new Map<string, Partial<Record<PaceZone, number>>>();
  // Miles per pace zone for ONE run — each lap classified by its own pace,
  // falling back to the workout type only when a run has no laps at all.
  function workoutZoneMiles(l: LogRow): Partial<Record<PaceZone, number>> {
    const cached = zmCache.get(l.id);
    if (cached) return cached;
    const out: Partial<Record<PaceZone, number>> = {};
    const wl = lapsByWorkout.get(l.id);
    if (wl && wl.length) {
      for (const lap of wl) {
        const mi = Number(lap.distance_meters ?? 0) / 1609.344;
        if (mi <= 0) continue;
        const pace = Number(lap.avg_pace_sec_per_mile ?? 0);
        const zone: PaceZone = pace > 0 ? nearestZoneKey(pace, athletePaces) : zoneOf(l.workout_type) ?? "easy";
        out[zone] = (out[zone] ?? 0) + mi;
      }
    } else {
      const zone = zoneOf(l.workout_type);
      const mi = numMiles(l.workout_distance_miles);
      if (zone && mi > 0) out[zone] = mi;
    }
    zmCache.set(l.id, out);
    return out;
  }
  const sumZoneMap = (zm: Partial<Record<PaceZone, number>>) =>
    Object.values(zm).reduce((s, v) => s + (v ?? 0), 0);

  // ── mentions indexed for day + niggle joins ──
  const mentionByDate = new Map<string, MentionRow>();
  for (const m of mentions) {
    const k = m.mentioned_at.slice(0, 10);
    if (!mentionByDate.has(k)) mentionByDate.set(k, m);
  }

  // ── logs grouped by calendar day ──
  const logsByDate = new Map<string, LogRow[]>();
  for (const l of logs) {
    const k = l.workout_date.slice(0, 10);
    const arr = logsByDate.get(k);
    if (arr) arr.push(l);
    else logsByDate.set(k, [l]);
  }

  // ── enrichment precomputes (P1) ──
  const METERS_PER_MILE = 1609.344;
  // ACWR value + band once (mirrors the acwr block below; needed in-loop).
  const acwrVal = state?.acwr != null ? Number(state.acwr) : undefined;
  const acwrBand: WeekContext["acwrBand"] | undefined =
    acwrVal == null
      ? undefined
      : acwrVal < 0.6
        ? "detraining"
        : acwrVal < 0.8
          ? "low"
          : acwrVal <= 1.3
            ? "sweet"
            : acwrVal <= 1.5
              ? "high"
              : "spike";
  const bandPhrase = (b: WeekContext["acwrBand"]) =>
    ({
      detraining: "below the training band",
      low: "building",
      sweet: "in the sweet band",
      high: "the high end of the sweet band",
      spike: "a spike above the sweet band",
    })[b];

  // Next key session (same for every day this read).
  let nextKey: WeekContext["nextKey"] | undefined;
  const uk = upcomingKey[0];
  if (uk) {
    const steps = uk.workout_data?.steps;
    const z = (steps ? headlineZone(steps, athletePaces) : null) ?? zoneOf(uk.workout_type) ?? "mp";
    const lbl = (steps ? workoutZoneLabel(steps, athletePaces) : null) ?? typeLabel(uk.workout_type);
    const udt = uk.date ? parseDate(uk.date) : null;
    const when = udt ? `${dowLabel(udt)} ${dateLabel(udt)}` : "";
    nextKey = { label: when ? `${lbl} · ${when}` : lbl, zone: z as PaceZone };
  }

  const weightedLapPace = (lps: EnrichLap[]): number | null => {
    let num = 0;
    let den = 0;
    for (const lp of lps) {
      const mi = Number(lp.distance_meters ?? 0) / METERS_PER_MILE;
      const p = Number(lp.avg_pace_sec_per_mile ?? 0);
      if (mi > 0 && p > 0) {
        num += p * mi;
        den += mi;
      }
    }
    return den > 0 ? num / den : null;
  };

  const fmtStart = (t: string | null): string | undefined => {
    if (!t) return undefined;
    let hh: number;
    let mm: number;
    if (t.includes("T")) {
      const dtp = new Date(t);
      if (Number.isNaN(dtp.getTime())) return undefined;
      hh = dtp.getHours();
      mm = dtp.getMinutes();
    } else {
      const m = t.match(/^(\d{1,2}):(\d{2})/);
      if (!m) return undefined;
      hh = Number(m[1]);
      mm = Number(m[2]);
    }
    const ampm = hh >= 12 ? "PM" : "AM";
    const h12 = ((hh + 11) % 12) + 1;
    return `${h12}:${String(mm).padStart(2, "0")} ${ampm}`;
  };

  // Assemble the enriched drill-down for one key day. Every block is
  // best-effort — a thin run (no laps, no prescription) still yields a valid
  // (if sparse) detail, so the drawer never breaks.
  function assembleKeyDetail(args: {
    primary: LogRow;
    totalMiles: number;
    sessions: number;
    fallbackSplits: WorkoutSplit[];
    dt: Date;
    iso: string;
    hasNiggle: boolean;
  }): WorkoutDetail {
    const { primary, totalMiles, fallbackSplits, dt, iso, hasNiggle } = args;
    const primaryLaps = (lapsByWorkout.get(primary.id) ?? []) as unknown as EnrichLap[];
    const sched = primary.scheduled_workout_id ? scheduledById.get(primary.scheduled_workout_id) : undefined;
    const prescribed = buildPrescribed(sched?.workout_data ?? null, totalMiles, athletePaces);
    const band = parseBand(prescribed?.window);
    const plannedMi = prescribed?.distance ?? totalMiles;
    const cutMarker = prescribed && totalMiles + 0.05 < prescribed.distance ? Math.round(totalMiles * 10) / 10 : undefined;
    const durationSec = primary.workout_duration_minutes ? Number(primary.workout_duration_minutes) * 60 : undefined;

    let paceLabel = primary.workout_pace_per_mile ? `${primary.workout_pace_per_mile}/mi` : undefined;
    if (!paceLabel) {
      const avg = weightedLapPace(primaryLaps);
      if (avg != null) paceLabel = `${fmtPaceSec(avg)}/mi`;
    }

    const heatAdj = heatAdjHeadline(primaryLaps, band);
    const kpis = buildHeadlineKpis({
      actualMiles: Math.round(totalMiles * 10) / 10,
      plannedMiles: prescribed?.distance,
      durationSec,
      timeEst: prescribed?.timeEst,
      paceLabel,
      window: prescribed?.window,
      heatAdj,
    });

    const conditions = buildConditions(primaryLaps, primary.weather_actual, fmtStart(primary.start_time));

    // Chart band: prescription window when present, else collapse to the run's
    // weighted average (an invisible band — no false target).
    let bandLow = band?.low;
    let bandHigh = band?.high;
    if (bandLow == null || bandHigh == null) {
      const avg = weightedLapPace(primaryLaps) ?? 540;
      bandLow = avg;
      bandHigh = avg;
    }
    const chart = buildChart(primaryLaps, { bandLow, bandHigh, plannedMi, cutAtMi: cutMarker });

    const isLong =
      ["long_run", "long"].includes((primary.workout_type ?? "").toLowerCase()) || totalMiles >= 12;
    const enriched = buildSplits(primaryLaps, {
      isLong,
      bandHigh: band?.high ?? Number.POSITIVE_INFINITY,
      plannedMi,
      ranMi: totalMiles,
    });
    const splitBlock = enriched ?? { splitLabel: "Sessions this day", splits: fallbackSplits };

    // Body: absence is information. Only when this run carries no niggle.
    let bodyContext: WorkoutDetail["bodyContext"];
    if (!hasNiggle) {
      const recent = [...mentions].reverse().find((m) => m.mentioned_at.slice(0, 10) <= iso);
      if (recent) {
        const quiet = Math.max(
          0,
          Math.round((dt.getTime() - parseDate(recent.mentioned_at).getTime()) / 86400000),
        );
        bodyContext = {
          line: "No niggles mentioned on this run.",
          sub: `${niggleArea(recent)} last flagged ${dateLabel(parseDate(recent.mentioned_at))} — quiet for ${quiet} day${quiet === 1 ? "" : "s"}.`,
        };
      } else {
        bodyContext = { line: "No niggles mentioned on this run." };
      }
    }

    // Week & load.
    let weekContext: WeekContext | undefined;
    if (acwrVal != null && acwrBand) {
      const mon = mondayOf(dt);
      const weekEnd = new Date(mon);
      weekEnd.setDate(weekEnd.getDate() + 7);
      const weekRuns = logs
        .filter((l) => {
          const d = parseDate(l.workout_date);
          return d >= mon && d < weekEnd && (l.workout_type ?? "") !== "rest" && numMiles(l.workout_distance_miles) > 0;
        })
        .sort((a, b) => a.workout_date.localeCompare(b.workout_date));
      const upto = weekRuns.filter((l) => l.workout_date.slice(0, 10) <= iso);
      const milesSoFar = Math.round(upto.reduce((s, l) => s + numMiles(l.workout_distance_miles), 0) * 10) / 10;
      const milesPlanned = Math.round(plannedByWeek.get(isoOf(mon)) ?? 0);
      const acwr = Math.round(acwrVal * 100) / 100;
      const volumeClause =
        milesPlanned > 0
          ? `**${milesSoFar.toFixed(1)} of ${milesPlanned} mi** planned`
          : `**${milesSoFar.toFixed(1)} mi** logged`;
      weekContext = {
        runOfWeek: `Run ${upto.length} of ${weekRuns.length}`,
        milesSoFar,
        milesPlanned,
        acwr,
        acwrBand,
        loadLine: `Run ${upto.length} of ${weekRuns.length} this week · ${volumeClause}. This run brought ACWR to **${acwr.toFixed(2)}** — ${bandPhrase(acwrBand)}.`,
        nextKey,
      };
    }

    const cachedRead = readByLogId.get(primary.id);

    return {
      kpis,
      verdictTitle: prescribed
        ? verdictTitle(typeLabel(primary.workout_type), totalMiles, prescribed.distance)
        : undefined,
      splitLabel: splitBlock.splitLabel,
      splits: splitBlock.splits,
      prescribed,
      conditions,
      chart,
      weekContext,
      bodyContext,
      read: cachedRead ? { body: cachedRead.body, question: cachedRead.question } : undefined,
    };
  }

  // 35-day window ending on the most recent logged day (or today).
  const endDate = logs.length ? parseDate(logs[logs.length - 1].workout_date) : new Date();
  const days: DashboardDay[] = [];
  const dateToDayId = new Map<string, string>();

  for (let i = 34; i >= 0; i--) {
    const dt = new Date(endDate);
    dt.setDate(dt.getDate() - i);
    const iso = isoOf(dt);
    const dayLogs = logsByDate.get(iso) ?? [];
    const runLogs = dayLogs.filter((l) => (l.workout_type ?? "") !== "rest" && numMiles(l.workout_distance_miles) > 0);

    const zoneMiles: Partial<Record<PaceZone, number>> = {};
    for (const l of runLogs) {
      for (const [z, mi] of Object.entries(workoutZoneMiles(l))) {
        zoneMiles[z as PaceZone] = (zoneMiles[z as PaceZone] ?? 0) + (mi ?? 0);
      }
    }
    const totalMiles = sumZoneMap(zoneMiles);

    const logged = dayLogs.length > 0;
    const isRest = totalMiles === 0;
    const zonesPresent = Object.keys(zoneMiles) as PaceZone[];
    const headline = zonesPresent.length
      ? zonesPresent.slice().sort((a, b) => ZONE_RANK[b] - ZONE_RANK[a])[0]
      : null;
    const primary = runLogs.slice().sort((a, b) => numMiles(b.workout_distance_miles) - numMiles(a.workout_distance_miles))[0];
    const mood: Mood = primary && primary.mood && MOODS.has(primary.mood as Mood) ? (primary.mood as Mood) : "neutral";
    const mention = mentionByDate.get(iso);
    const niggle = mention ? { area: niggleArea(mention), quote: mention.verbatim_quote } : null;
    // A day is "key" if any run is a quality/long/race TYPE, OR a long effort
    // by distance (catches mis-typed long runs), OR carries real quality-zone
    // volume from its splits (catches mis-typed workouts — only trusted when we
    // have the athlete's calibrated pace table).
    const qualityMiles = (Object.entries(zoneMiles) as [PaceZone, number][]).reduce(
      (s, [z, mi]) => s + (QUALITY_ZONES.has(z) ? mi ?? 0 : 0),
      0,
    );
    const key =
      runLogs.some((l) => KEY_TYPES.has((l.workout_type ?? "").toLowerCase())) ||
      runLogs.some((l) => numMiles(l.workout_distance_miles) >= 12) ||
      (athletePaces !== undefined && qualityMiles >= 2.5);
    const sessions = runLogs.length;

    const id = dayLogs[0]?.id ?? `rest-${iso}`;
    dateToDayId.set(iso, id);

    const label = isRest
      ? "Rest"
      : sessions > 1
        ? `${sessions} sessions · ${trimMiles(totalMiles)} mi`
        : `${typeLabel(primary.workout_type)} ${trimMiles(totalMiles)} mi`;
    const actual = isRest
      ? null
      : sessions > 1
        ? `${trimMiles(totalMiles)} mi · ${sessions} sessions`
        : `${trimMiles(totalMiles)} mi${primary.workout_pace_per_mile ? ` · ${primary.workout_pace_per_mile}/mi` : ""}`;

    const splits: WorkoutSplit[] = runLogs.map((l) => ({
      name: `${typeLabel(l.workout_type)} ${trimMiles(numMiles(l.workout_distance_miles))} mi`,
      pace: l.workout_pace_per_mile,
      onTarget: true,
    }));

    days.push({
      id,
      date: iso,
      dateLabel: dateLabel(dt),
      dow: dowLabel(dt),
      label,
      zone: isRest ? null : headline,
      zoneMiles,
      miles: totalMiles,
      actual,
      delta: null,
      onTarget: false,
      key: key && !isRest,
      mood,
      niggle,
      note: (primary?.cleaned_notes ?? "").trim(),
      logged,
      detail:
        key && !isRest
          ? assembleKeyDetail({
              primary,
              totalMiles,
              sessions,
              fallbackSplits: splits,
              dt,
              iso,
              hasNiggle: niggle != null,
            })
          : undefined,
    });
  }

  // ── weekly volume (12 Monday weeks, from logs) ──
  const thisMon = mondayOf(new Date());
  const weekBuckets = Array.from({ length: 12 }, (_, i) => {
    const start = new Date(thisMon);
    start.setDate(start.getDate() - (11 - i) * 7);
    return { start, label: dateLabel(start), zoneMiles: {} as Partial<Record<PaceZone, number>> };
  });
  for (const l of logs) {
    const wz = workoutZoneMiles(l);
    if (!Object.keys(wz).length) continue;
    const dt = parseDate(l.workout_date);
    for (const w of weekBuckets) {
      const end = new Date(w.start);
      end.setDate(end.getDate() + 7);
      if (dt >= w.start && dt < end) {
        for (const [z, mi] of Object.entries(wz)) {
          w.zoneMiles[z as PaceZone] = (w.zoneMiles[z as PaceZone] ?? 0) + (mi ?? 0);
        }
        break;
      }
    }
  }
  const weeklyVolume: WeeklyVolumeWeek[] = weekBuckets.map((w, i) => ({
    label: w.label,
    zoneMiles: w.zoneMiles,
    targetMiles: 0,
    current: i === weekBuckets.length - 1,
  }));

  // ── niggles (grouped body_mentions), linked to the day by date ──
  const byArea = new Map<string, MentionRow[]>();
  for (const m of mentions) {
    const area = niggleArea(m);
    const arr = byArea.get(area);
    if (arr) arr.push(m);
    else byArea.set(area, [m]);
  }
  const niggles: NiggleGroup[] = [...byArea.entries()]
    .map(([area, list]) => {
      const latest = list[list.length - 1];
      return {
        area,
        mentions: list.length,
        latestDate: dateLabel(parseDate(latest.mentioned_at)),
        latestQuote: latest.verbatim_quote,
        otherDates: list.slice(0, -1).map((x) => dateLabel(parseDate(x.mentioned_at))),
        recurrence: list.length >= 3,
        linkDayId: dateToDayId.get(latest.mentioned_at.slice(0, 10)),
      };
    })
    .sort((a, b) => b.mentions - a.mentions);

  // ── mood (per day; unlogged days render faint, excluded from the mix) ──
  const strip = days.slice(-28).map((d) => ({
    date: d.date,
    dateLabel: d.dateLabel,
    mood: d.mood,
    logged: d.logged !== false && d.miles > 0,
  }));
  const loggedDays = days.filter((d) => d.logged !== false && d.miles > 0);
  const counts = new Map<Mood, number>();
  for (const d of loggedDays) counts.set(d.mood, (counts.get(d.mood) ?? 0) + 1);
  const distribution = MOOD_ORDER.filter((m) => counts.get(m)).map((m) => ({ mood: m, count: counts.get(m)! }));
  const topMood = distribution.slice().sort((a, b) => b.count - a.count)[0]?.mood;
  const mood: MoodSummary = {
    strip,
    distribution,
    caption: topMood
      ? `**${cap(topMood)}** was the most-logged mood across ${loggedDays.length} training days.`
      : "No mood logged in this window yet.",
  };

  // ── acwr (athlete_state) ──
  let acwr: Acwr | undefined;
  if (state && state.acwr != null) {
    const v = Number(state.acwr);
    const band: Acwr["band"] =
      v < 0.6 ? "detraining" : v < 0.8 ? "low" : v <= 1.3 ? "sweet" : v <= 1.5 ? "high" : "spike";
    const bandLabel = { detraining: "Detraining", low: "Building", sweet: "Sweet spot", high: "Caution", spike: "Spike" }[band];
    acwr = {
      value: v,
      band,
      bandLabel,
      monotony7d: Number(state.monotony_7d ?? 0),
      strain7d: Math.round(Number(state.strain_7d ?? 0)),
    };
  }

  // ── progression (trend + goal; no point predictions — hard rule #7) ──
  let progression: Progression | undefined;
  if (state) {
    const goalTime = state.goal_time_seconds ? fmtHMS(state.goal_time_seconds) : "";
    const trendText = state.fitness_vs_6mo_ago_label ?? "";
    const ft = state.fitness_trend ?? "";
    const trendArrow: Progression["trendArrow"] = /up|improv|ris/i.test(ft)
      ? "up"
      : /down|declin|fall/i.test(ft)
        ? "down"
        : "flat";
    if (goalTime || trendText) {
      progression = {
        prediction: undefined,
        goalTime,
        gapLabel: "",
        trendArrow,
        trendText,
        fitnessSeries: [],
        fitnessMonths: [],
        races: [],
        projection: { rangeLabel: "", goalLabel: "", xLabel: "" },
      };
    }
  }

  // ── coachable moments ──
  const momentsOut: CoachableMoment[] = moments.map((m) => ({
    id: m.id,
    kind: prettyRule(m.rule_id ?? m.action_type ?? "Observation"),
    when: relTime(m.triggered_at),
    observation: m.summary ?? "",
    softQuestion: "",
    severity: (["high", "med", "low"].includes(m.severity ?? "") ? m.severity : "low") as CoachableMoment["severity"],
  }));

  // ── watch list (derived) ──
  const watchList: WatchItem[] = [];
  for (const g of niggles) {
    if (g.recurrence) {
      watchList.push({
        severity: "warn",
        title: `${g.area} — **${g.mentions} mentions**`,
        detail: `Most recent ${g.latestDate}. Recurrence flagged.`,
      });
    }
  }
  if (acwr && acwr.band === "spike") {
    watchList.push({
      severity: "warn",
      title: "Load spike",
      detail: `ACWR ${acwr.value.toFixed(2)} — above the sweet spot.`,
    });
  }

  // ── header ──
  let weekNumber = 0;
  let totalWeeks = 0;
  if (plan) {
    const start = parseDate(plan.start_date);
    const end = parseDate(plan.end_date);
    totalWeeks = Math.max(1, Math.round((end.getTime() - start.getTime()) / (7 * 86400000)) + 1);
    weekNumber = Math.min(totalWeeks, Math.max(1, Math.floor((Date.now() - start.getTime()) / (7 * 86400000)) + 1));
  }
  const goalSecs = state?.goal_time_seconds ?? plan?.target_time_seconds ?? null;

  // Name resolves from the profile the coach/athlete set; falls back to the
  // "Athlete <id>" placeholder so an un-named athlete still renders cleanly.
  const displayName = settings?.display_name?.trim() || `Athlete ${athleteId.slice(0, 6)}`;

  // Sign a short-lived URL for the athlete's photo (private bucket). Best-
  // effort: a missing file / bucket just falls back to the monogram.
  let avatarUrl: string | undefined;
  if (settings?.avatar_path) {
    const signed = await safe(
      admin.storage.from("avatars").createSignedUrl(settings.avatar_path, 3600),
    );
    avatarUrl = signed?.signedUrl ?? undefined;
  }

  const header = {
    name: displayName,
    initials: initialsFrom(displayName, athleteId),
    athleteId,
    profileName: settings?.display_name?.trim() || undefined,
    bio: settings?.bio?.trim() || undefined,
    avatarUrl,
    planName: plan?.name ?? "No active plan",
    weekNumber,
    totalWeeks,
    goalTime: goalSecs ? fmtHMS(goalSecs) : undefined,
    goalNote: goalSecs ? "Target finish" : undefined,
  };

  // ── pace key (the athlete's own pace per zone) ──
  const KEY_ZONES: PaceZone[] = [
    "easy",
    "moderate",
    "steady",
    "mp",
    "hm",
    "threshold",
    "tenK",
    "fiveK",
    "threeK",
    "mile",
  ];
  const fmtPace = (sec: number) => {
    const s = Math.round(sec);
    return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
  };
  const paceKey = athletePaces
    ? KEY_ZONES.filter((z) => athletePaces[z]).map((z) => ({
        zone: z,
        label: zoneLabelShort(z),
        pace: fmtPace(athletePaces[z]!),
      }))
    : undefined;

  return {
    header,
    watchList,
    moments: momentsOut,
    days,
    progression,
    weeklyVolume,
    acwr,
    niggles,
    mood,
    paceKey,
  };
}

import "server-only";

// Athlete-scoped single-workout builder — the data half of the three-act
// workout detail (design system §6 "Workout detail — one view, three acts").
//
// This is the athlete's own run, so every read goes through the RLS cookie
// client: training_logs, running_workout_laps, body_mentions and
// scheduled_workouts all carry `user_id = auth.uid()` SELECT policies
// (verified against the live DB 2026-08-06). No service role, no athleteId
// parameter — you can only ever load your own workout.
//
// The reshaping is delegated wholesale to the pure functions in
// coach-dashboard/workout-enrichment.ts. Those touch no database and no
// React; they were written for the coach drawer but nothing in them is
// coach-specific, so the two surfaces stay in agreement by construction
// rather than by discipline.
//
// IMPORTANT — the plan linkage runs BACKWARDS from what the coach code
// assumes. There is no `training_logs.scheduled_workout_id` column; the FK
// lives on the other side as `scheduled_workouts.completed_workout_id`.
// See the note in getPrescription() below.

import { createClient, getUserId } from "@/lib/supabase/server";
import {
  derivePaceTableFromGoal,
  nearestZoneKey,
  zoneLabelShort,
  type AthletePaceTable,
  type WorkoutStep,
} from "@/components/coach/workout-helpers";
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
} from "@/lib/coach-dashboard/workout-enrichment";
import type {
  WorkoutChart,
  WorkoutConditions,
  WorkoutDetail,
  WorkoutPrescribed,
  WorkoutSplit,
} from "@/lib/coach-dashboard/types";

// ── Public shape ───────────────────────────────────────────────────────────

export interface WorkoutNiggle {
  body_area: string;
  side: string | null;
  verbatim_quote: string | null;
}

export interface AthleteWorkoutDetail {
  id: string;
  /** ISO date (YYYY-MM-DD) of the workout itself, not when it was recorded. */
  date: string;
  /** "TUESDAY · QUALITY" — the Act 1 eyebrow. */
  eyebrow: string;
  /** Pace-zone label ("LT 6 mi"), never "Tempo"/"Threshold". */
  title: string;
  /** Where the row came from: voice_log, strava, manual… */
  source: string | null;
  mood: string | null;
  /** cleaned_notes ?? notes — the athlete's own words. */
  note: string | null;
  kpis: WorkoutDetail["kpis"];
  splitLabel: string;
  splits: WorkoutSplit[];
  prescribed?: WorkoutPrescribed;
  conditions?: WorkoutConditions;
  chart?: WorkoutChart;
  niggles: WorkoutNiggle[];
  /** True when the run has per-lap rows — gates the Act 2 hero table. */
  hasLaps: boolean;
}

// ── Row shapes ─────────────────────────────────────────────────────────────

interface LogRow {
  id: string;
  workout_date: string | null;
  created_at: string;
  workout_distance_miles: number | null;
  workout_duration_minutes: number | null;
  workout_pace_per_mile: string | null;
  workout_type: string | null;
  mood: string | null;
  cleaned_notes: string | null;
  notes: string | null;
  source: string | null;
  weather_actual: Record<string, unknown> | null;
}

// The columns training_logs actually has. `scheduled_workout_id` and
// `start_time` are deliberately absent — they do not exist on this table.
const LOG_COLUMNS =
  "id, workout_date, created_at, workout_distance_miles, workout_duration_minutes, " +
  "workout_pace_per_mile, workout_type, mood, cleaned_notes, notes, source, weather_actual";

const LAP_COLUMNS =
  "lap_index, distance_meters, avg_pace_sec_per_mile, heat_adjusted_pace_sec_per_mile, " +
  "avg_heart_rate, temp_f, dew_point_f, heat_category, total_elevation_gain, is_rest";

// ── Labels ─────────────────────────────────────────────────────────────────

// Structural labels only. Pace-zone labels ("MP 7 mi", "LT 6 mi") come from
// the prescription when there is one — "Tempo" and "Threshold" are retired as
// ambiguous and must never be emitted here.
const STRUCTURAL_LABEL: Record<string, string> = {
  easy: "Easy",
  recovery: "Recovery",
  long_run: "Long",
  long: "Long",
  race: "Race",
  progression: "Progression",
  strides: "Strides",
  rest: "Rest",
  cross_training: "Cross-train",
  strength: "Strength",
};

// Retired labels. Rows still carry them (Strava-sourced runs are full of
// `threshold`), but they must never reach the screen — the zone IS the label,
// so these fall through to pace-derived naming instead.
const RETIRED_LABEL = new Set(["tempo", "threshold", "interval", "intervals", "speed"]);

function structuralLabel(workoutType: string | null): string | null {
  if (!workoutType) return null;
  const key = workoutType.toLowerCase();
  if (RETIRED_LABEL.has(key)) return null;
  return STRUCTURAL_LABEL[key] ?? null;
}

// Name the run by the zone it was ACTUALLY run at — "LT 4.2 mi", not
// "Threshold". Needs the athlete's ladder; without it there's no honest zone
// to name and the caller falls back to a plain distance label.
function paceDerivedLabel(
  paceSec: number | null,
  miles: number,
  paceTable: AthletePaceTable | undefined,
): string | null {
  if (paceSec == null || paceSec <= 0 || !paceTable) return null;
  const zone = nearestZoneKey(paceSec, paceTable);
  if (!zone) return null;
  const dist = miles > 0 ? ` ${miles % 1 === 0 ? miles : miles.toFixed(1)} mi` : "";
  return `${zoneLabelShort(zone)}${dist}`;
}

// "TUESDAY · QUALITY" — weekday plus a coarse register. Quality is anything
// with a prescription band or a race; everything else reads as the run it was.
function buildEyebrow(date: Date, isQuality: boolean, workoutType: string | null): string {
  const weekday = date.toLocaleDateString("en-US", { weekday: "long" }).toUpperCase();
  const type = (workoutType ?? "").toLowerCase();
  if (type === "race") return `${weekday} · RACE`;
  if (isQuality) return `${weekday} · QUALITY`;
  if (type === "long_run" || type === "long") return `${weekday} · LONG`;
  return weekday;
}

// Parse YYYY-MM-DD as local midnight. `new Date("2026-08-06")` parses as UTC
// and renders as the previous day west of Greenwich.
function parseLocalDate(iso: string): Date {
  const [y, m, d] = iso.slice(0, 10).split("-").map(Number);
  return new Date(y, m - 1, d);
}

// ── Builder ────────────────────────────────────────────────────────────────

export async function buildAthleteWorkoutDetail(
  logId: string,
): Promise<AthleteWorkoutDetail | null> {
  const supabase = await createClient();
  const userId = await getUserId();
  if (!userId) return null;

  // RLS already scopes this, but the explicit user_id predicate means a
  // mis-scoped policy can't silently widen the read.
  const { data: logData, error: logError } = await supabase
    .from("training_logs")
    .select(LOG_COLUMNS)
    .eq("id", logId)
    .eq("user_id", userId)
    .maybeSingle();

  // Surface the failure rather than swallowing it into an empty page — a
  // silent `null` here is exactly how the coach dashboard came to render a
  // permanently empty roster.
  if (logError) throw new Error(`workout-detail: log read failed — ${logError.message}`);
  if (!logData) return null;
  const log = logData as unknown as LogRow;

  const [laps, prescription, niggles, paceTable] = await Promise.all([
    getLaps(supabase, logId, userId),
    getPrescription(supabase, logId),
    getNiggles(supabase, logId, userId),
    getPaceTable(supabase, userId),
  ]);

  return assemble({ log, laps, prescription, niggles, paceTable });
}

type Client = Awaited<ReturnType<typeof createClient>>;

async function getLaps(supabase: Client, logId: string, userId: string): Promise<EnrichLap[]> {
  const { data } = await supabase
    .from("running_workout_laps")
    .select(LAP_COLUMNS)
    .eq("workout_id", logId)
    .eq("user_id", userId)
    .order("lap_index", { ascending: true })
    .limit(500);
  return (data ?? []) as unknown as EnrichLap[];
}

// The prescription, if this run was matched to a planned session.
//
// The join runs scheduled_workouts → training_logs via
// `completed_workout_id`, NOT training_logs → scheduled_workouts. There is no
// `scheduled_workout_id` column on training_logs; code that selects one gets
// a PostgREST 400. Coach-side code still does this and, because its query is
// wrapped in a swallow-all `safe()`, renders an empty dashboard instead of an
// error — see WEB-PORTAL-PARITY-PLAN.md §0.
//
// Absent prescription is a first-class state, not a failure: plans are
// optional and `activePlan == nil` is normal. Every downstream block already
// degrades to `undefined`.
async function getPrescription(
  supabase: Client,
  logId: string,
): Promise<{ steps?: WorkoutStep[]; name?: string } | null> {
  const { data } = await supabase
    .from("scheduled_workouts")
    .select("workout_data")
    .eq("completed_workout_id", logId)
    .maybeSingle();
  const workoutData = (data as { workout_data?: unknown } | null)?.workout_data;
  return (workoutData as { steps?: WorkoutStep[]; name?: string } | undefined) ?? null;
}

// Niggles attached to THIS run. Surface, never interpret: area, side and the
// athlete's verbatim words only — no severity, no diagnosis.
async function getNiggles(
  supabase: Client,
  logId: string,
  userId: string,
): Promise<WorkoutNiggle[]> {
  const { data } = await supabase
    .from("body_mentions")
    .select("body_area, side, verbatim_quote")
    .eq("training_log_id", logId)
    .eq("user_id", userId)
    .limit(12);
  return (data ?? []) as WorkoutNiggle[];
}

// The athlete's pace ladder, anchored on marathon pace. Race anchor beats goal
// time upstream in athlete_pace_profiles; this just reads the result.
async function getPaceTable(
  supabase: Client,
  userId: string,
): Promise<AthletePaceTable | undefined> {
  const { data } = await supabase
    .from("athlete_pace_profiles")
    .select("marathon_pace_seconds")
    .eq("user_id", userId)
    .maybeSingle();
  const mp = (data as { marathon_pace_seconds?: number } | null)?.marathon_pace_seconds;
  return mp && Number(mp) > 0 ? derivePaceTableFromGoal(Number(mp), "marathon") : undefined;
}

// ── Assembly ───────────────────────────────────────────────────────────────

// Mirrors assembleKeyDetail() in coach-dashboard/from-supabase.ts so the two
// surfaces read the same run the same way.
function assemble(args: {
  log: LogRow;
  laps: EnrichLap[];
  prescription: { steps?: WorkoutStep[]; name?: string } | null;
  niggles: WorkoutNiggle[];
  paceTable: AthletePaceTable | undefined;
}): AthleteWorkoutDetail {
  const { log, laps, prescription, niggles, paceTable } = args;

  const totalMiles = Number(log.workout_distance_miles ?? 0);
  const prescribed = buildPrescribed(prescription, totalMiles, paceTable);
  const band = parseBand(prescribed?.window);
  const plannedMi = prescribed?.distance ?? totalMiles;
  const cutMarker =
    prescribed && totalMiles + 0.05 < prescribed.distance
      ? Math.round(totalMiles * 10) / 10
      : undefined;
  const durationSec = log.workout_duration_minutes
    ? Number(log.workout_duration_minutes) * 60
    : undefined;

  let paceLabel = log.workout_pace_per_mile ? `${log.workout_pace_per_mile}/mi` : undefined;
  if (!paceLabel) {
    const avg = weightedLapPace(laps);
    if (avg != null) paceLabel = `${fmtPaceSec(avg)}/mi`;
  }

  const heatAdj = heatAdjHeadline(laps, band);
  const kpis = buildHeadlineKpis({
    actualMiles: Math.round(totalMiles * 10) / 10,
    plannedMiles: prescribed?.distance,
    durationSec,
    timeEst: prescribed?.timeEst,
    paceLabel,
    window: prescribed?.window,
    heatAdj,
  });

  // No start_time column on training_logs — the conditions plate renders
  // without a time-of-day line rather than inventing one.
  const conditions = buildConditions(laps, log.weather_actual, undefined);

  // Chart band: the prescription window when present, else collapse the band
  // onto the run's own average so no false target is drawn.
  let bandLow = band?.low;
  let bandHigh = band?.high;
  if (bandLow == null || bandHigh == null) {
    const avg = weightedLapPace(laps);
    if (avg != null) {
      bandLow = avg;
      bandHigh = avg;
    }
  }
  const chart =
    bandLow != null && bandHigh != null
      ? buildChart(laps, { bandLow, bandHigh, plannedMi, cutAtMi: cutMarker })
      : undefined;

  const isLong =
    ["long_run", "long"].includes((log.workout_type ?? "").toLowerCase()) || totalMiles >= 12;
  const enriched = buildSplits(laps, {
    isLong,
    bandHigh: band?.high ?? Number.POSITIVE_INFINITY,
    plannedMi,
    ranMi: totalMiles,
  });

  // Quality = a prescribed band, a race, or a row still tagged with one of the
  // retired quality labels (Strava rows are full of `threshold`).
  const typeKey = (log.workout_type ?? "").toLowerCase();
  const isQuality = band != null || typeKey === "race" || RETIRED_LABEL.has(typeKey);
  const iso = (log.workout_date ?? log.created_at).slice(0, 10);
  const date = parseLocalDate(iso);

  // Title precedence, most-authoritative first:
  //   1. the prescription's zone label ("LT 6 mi")
  //   2. a structural label the taxonomy still honours ("Long", "Race")
  //   3. the zone the run was actually run at, derived from pace
  //   4. plain distance — no invented zone when there's no ladder to place it
  // verdictTitle overrides all of them when the run was cut short.
  const roundedMi = Math.round(totalMiles * 10) / 10;
  const actualPaceSec = weightedLapPace(laps) ?? parsePaceLabel(log.workout_pace_per_mile);
  const baseTitle =
    (prescribed?.label
      ? `${prescribed.label}${prescribed.distance ? ` ${prescribed.distance} mi` : ""}`
      : null) ??
    structuralLabel(log.workout_type) ??
    paceDerivedLabel(actualPaceSec, roundedMi, paceTable) ??
    (roundedMi > 0 ? `${roundedMi} mi` : "Run");

  return {
    id: log.id,
    date: iso,
    eyebrow: buildEyebrow(date, isQuality, log.workout_type),
    title: verdictTitle(baseTitle, totalMiles, prescribed?.distance) ?? baseTitle,
    source: log.source,
    mood: log.mood,
    note: log.cleaned_notes ?? log.notes ?? null,
    kpis,
    splitLabel: enriched?.splitLabel ?? "Splits",
    splits: enriched?.splits ?? [],
    prescribed,
    conditions,
    chart,
    niggles,
    hasLaps: laps.length > 0,
  };
}

// "7:29" or "7:29/mi" → 449 seconds. Null on anything that isn't a pace.
function parsePaceLabel(s: string | null): number | null {
  if (!s) return null;
  const m = s.match(/(\d+):(\d{2})/);
  if (!m) return null;
  return Number(m[1]) * 60 + Number(m[2]);
}

// Distance-weighted average pace across the laps that carry both.
function weightedLapPace(laps: EnrichLap[]): number | null {
  let num = 0;
  let den = 0;
  for (const l of laps) {
    const mi = Number(l.distance_meters ?? 0) / 1609.344;
    const p = Number(l.avg_pace_sec_per_mile ?? 0);
    if (mi > 0 && p > 0) {
      num += p * mi;
      den += mi;
    }
  }
  return den > 0 ? num / den : null;
}

/**
 * compute-fitness-snapshot
 *
 * Server-side writer for `fitness_snapshots`. Historically snapshots were only
 * written by the iOS app, on-device, when a user opened the predictor screen —
 * so the nightly athlete-state rebuild and the Coach Read read stale-or-absent
 * fitness data. This worker regenerates a snapshot for an athlete using the
 * SAME algorithm the app shows (ported to _shared/fitnessPrediction.ts), so the
 * app and server never diverge. See
 * outputs/fitness-snapshot-writer-diagnosis-2026-07-02.md.
 *
 * Modes (mirrors rebuild-athlete-state):
 *   { user_id }  — compute one athlete. The nightly cron fans out one
 *                  http_post per active athlete.
 *   { batch: N } — compute up to N active athletes (a workout in the last 45d).
 *
 * Upsert semantics match the iOS app: at most one row per calendar day per
 * user — today's row is updated if it exists, otherwise inserted.
 *
 * Auth: service-role only (decoded-claim check), like the drain-* workers and
 * rebuild-athlete-state. The upsert runs under the service-role admin client so
 * RLS never blocks it.
 */

import { createClient, type SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";
import {
  generateFitnessPrediction,
  paceStringToSeconds,
  RACE_TYPE_LABEL,
  RACE_TYPE_TOLERANCE,
  type DetectedRace,
  type EfficiencyBucketInput,
  type LapInput,
  type PredictionInput,
  type RaceType,
  type VoiceLogInput,
  type WorkoutInput,
} from "../_shared/fitnessPrediction.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const admin = createClient(supabaseUrl, supabaseServiceKey);

const DEFAULT_BATCH = 25;
const MAX_BATCH = 100;
const ACTIVE_LOOKBACK_DAYS = 45;

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.startsWith("Bearer ")) return json({ error: "Authentication required" }, 401);
  const token = authHeader.slice("Bearer ".length).trim();
  if (!isServiceRoleJWT(token)) return json({ error: "Service role required" }, 403);

  let body: { user_id?: string; batch?: number } = {};
  try {
    body = (await req.json()) as { user_id?: string; batch?: number };
  } catch {
    /* empty body ok */
  }

  const start = Date.now();

  // --- Single-athlete mode (nightly cron fan-out) ---
  if (body.user_id !== undefined) {
    const userId = body.user_id.trim();
    if (!userId) return json({ error: "empty user_id" }, 400); // guards the empty-id bug
    try {
      const result = await computeAndUpsert(admin, userId);
      return json({ user_id: userId, ...result, elapsed_ms: Date.now() - start });
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      console.error(`compute-fitness-snapshot: ${userId} failed:`, msg);
      return json({ error: `compute failed: ${msg}` }, 500);
    }
  }

  // --- Batch mode (manual / backfill) ---
  const batch = Math.min(Math.max(1, body.batch ?? DEFAULT_BATCH), MAX_BATCH);
  const sinceDate = new Date(Date.now() - ACTIVE_LOOKBACK_DAYS * 86400000).toISOString().slice(0, 10);

  const { data: activeRows, error: activeErr } = await admin
    .from("training_logs")
    .select("user_id")
    .gte("workout_date", sinceDate)
    .not("user_id", "is", null)
    .limit(5000);
  if (activeErr) return json({ error: activeErr.message }, 500);

  const activeIds = [...new Set((activeRows ?? []).map((r) => r.user_id as string).filter((id) => id && id.trim()))].slice(0, batch);

  let written = 0;
  let skipped = 0;
  const errors: string[] = [];
  for (const id of activeIds) {
    try {
      const res = await computeAndUpsert(admin, id);
      if (res.wrote) written++;
      else skipped++;
    } catch (e) {
      errors.push(`${id}: ${e instanceof Error ? e.message : String(e)}`);
    }
  }

  return json({ active: activeIds.length, written, skipped, errors: errors.slice(0, 5), elapsed_ms: Date.now() - start });
});

// ---------------------------------------------------------------------------
// Core: fetch inputs → run the ported predictor → upsert today's row.
// ---------------------------------------------------------------------------

async function computeAndUpsert(
  db: SupabaseClient,
  userId: string,
): Promise<{ wrote: boolean; reason?: string; confidence?: string; estimated_10k_pace_seconds?: number; race_candidates_tagged?: number }> {
  const now = new Date();
  const cutoff30 = new Date(now.getTime() - 30 * 86400000).toISOString().slice(0, 10);
  const cutoff180 = new Date(now.getTime() - 180 * 86400000).toISOString().slice(0, 10);
  const cutoff112 = new Date(now.getTime() - 112 * 86400000).toISOString();

  // Training logs: last 180d (covers race detection); the 30d window is derived
  // by date below. One row can be both a run and carry notes/parse/segments.
  const { data: logRows, error: logErr } = await db
    .from("training_logs")
    .select(
      "id, workout_date, workout_distance_miles, workout_duration_minutes, workout_pace_per_mile, workout_type, cleaned_notes, notes, workout_notes, parsed_structure, pace_segments, race_result, weather_actual",
    )
    .eq("user_id", userId)
    .gte("workout_date", cutoff180)
    .order("workout_date", { ascending: false })
    .limit(2000);
  if (logErr) throw new Error(`training_logs: ${logErr.message}`);

  const extendedWorkouts: WorkoutInput[] = [];
  const extendedVoiceLogs: VoiceLogInput[] = [];
  const seededRaces: DetectedRace[] = [];
  const workoutDateById = new Map<string, string>();
  for (const row of logRows ?? []) {
    const date = toDay(row.workout_date as string);
    if (!date) continue;
    if (row.id) workoutDateById.set(String(row.id), date);

    const miles = num(row.workout_distance_miles);
    const durationMinutes = num(row.workout_duration_minutes);
    // workout_pace_per_mile is stored as an "M:SS" text string, not seconds.
    // Fall back to duration/distance when the text is missing or malformed.
    let paceSec = paceStringToSeconds(String(row.workout_pace_per_mile ?? ""));
    if (paceSec <= 0 && miles > 0 && durationMinutes > 0) paceSec = (durationMinutes * 60) / miles;
    if (miles > 0 && paceSec > 0) {
      extendedWorkouts.push({
        date,
        distanceMiles: miles,
        durationMinutes,
        paceSecondsPerMile: paceSec,
        type: (row.workout_type as string) ?? undefined,
      });
    }

    const notes = [row.cleaned_notes, row.notes, row.workout_notes].filter(Boolean).join(" ").trim();
    extendedVoiceLogs.push({
      date,
      notes,
      pacesMentioned: [],
      paceSegments: mapPaceSegments(row.pace_segments),
      parsedStructure: mapParsedStructure(row.parsed_structure),
      weather: mapWeather(row.weather_actual),
    });
  }

  const workouts = extendedWorkouts.filter((w) => w.date >= cutoff30);
  const voiceLogs = extendedVoiceLogs.filter((v) => v.date >= cutoff30);

  // Lap-level interval data (last 21 days) — the rest-aware, heat-stamped,
  // per-rep signal the v2 model merges into its hard-effort pool.
  const cutoff21 = new Date(now.getTime() - 21 * 86400000).toISOString();
  const { data: lapRows } = await db
    .from("running_workout_laps")
    .select(
      "workout_id, lap_index, distance_meters, moving_time_seconds, avg_pace_sec_per_mile, is_rest, total_elevation_gain, temp_f, dew_point_f, heat_adjusted_pace_sec_per_mile, lap_start_at",
    )
    .eq("user_id", userId)
    .gte("lap_start_at", cutoff21)
    .order("lap_start_at", { ascending: true })
    .limit(2000);
  // Confirmed races — ALL TIME (2026-07-17). Races live in training_logs
  // (workout_type='race' + race_result), not a separate table. Recent ones
  // (≤36 wk) anchor current fitness; older ones are lifetime PRs: they feed
  // speed evidence and the PR display, never the current-fitness anchor.
  const { data: raceRows } = await db
    .from("training_logs")
    .select("id, workout_date, race_result")
    .eq("user_id", userId)
    .not("race_result", "is", null)
    .order("workout_date", { ascending: false })
    .limit(100);
  for (const row of raceRows ?? []) {
    const date = toDay(row.workout_date as string);
    if (!date) continue;
    if (row.id) workoutDateById.set(String(row.id), date);
    const rr = row.race_result as { distance?: string; finish_time_seconds?: number } | null;
    if (rr && typeof rr.finish_time_seconds === "number") {
      const rt = distanceToRaceType(String(rr.distance ?? ""));
      if (rt) {
        seededRaces.push({
          raceType: rt,
          paceSecondsPerMile: rr.finish_time_seconds / RACE_TYPE_MILES[rt],
          date,
          totalTimeSeconds: rr.finish_time_seconds,
          // Lets the model find this race's laps for grade+heat adjustment
          // (race performances read as flat-cool equivalents, 2026-07-17).
          sourceWorkoutId: String(row.id),
        });
      }
    }
  }

  // Race-day laps (2026-07-17): confirmed races can be months older than the
  // 21-day training window, but their laps carry the hills + weather needed to
  // read the performance as a flat-cool equivalent. Fetch them separately.
  const raceWorkoutIds = seededRaces
    .map((r) => r.sourceWorkoutId)
    .filter((id): id is string => typeof id === "string" && id.length > 0);
  let raceLapRows: typeof lapRows = [];
  if (raceWorkoutIds.length > 0) {
    const { data } = await db
      .from("running_workout_laps")
      .select(
        "workout_id, lap_index, distance_meters, moving_time_seconds, avg_pace_sec_per_mile, is_rest, total_elevation_gain, temp_f, dew_point_f, heat_adjusted_pace_sec_per_mile, lap_start_at",
      )
      .eq("user_id", userId)
      .in("workout_id", raceWorkoutIds)
      .order("lap_start_at", { ascending: true })
      .limit(500);
    raceLapRows = data ?? [];
  }

  const laps: LapInput[] = [];
  const seenLapKeys = new Set<string>();
  for (const l of [...(lapRows ?? []), ...(raceLapRows ?? [])]) {
    const key = `${l.workout_id}#${l.lap_index}`;
    if (seenLapKeys.has(key)) continue;
    seenLapKeys.add(key);
    const date = workoutDateById.get(String(l.workout_id)) ?? toDay(String(l.lap_start_at ?? ""));
    if (!date) continue;
    laps.push({
      workoutId: String(l.workout_id),
      date,
      lapIndex: num(l.lap_index),
      distanceMeters: numOrNull(l.distance_meters),
      movingTimeSeconds: numOrNull(l.moving_time_seconds),
      avgPaceSecPerMile: numOrNull(l.avg_pace_sec_per_mile),
      isRest: typeof l.is_rest === "boolean" ? l.is_rest : null,
      totalElevationGain: numOrNull(l.total_elevation_gain),
      tempF: numOrNull(l.temp_f),
      dewPointF: numOrNull(l.dew_point_f),
      heatAdjustedPaceSecPerMile: numOrNull(l.heat_adjusted_pace_sec_per_mile),
    });
  }

  // Prior snapshots (last 16 weeks) for the decay-gated baseline fallback AND
  // the curve's prior. `data_source` is required, not decorative: the curve
  // damps only against rows this model wrote (see fitnessCurve.isOwnSnapshot).
  const { data: snapRows } = await db
    .from("fitness_snapshots")
    .select("created_at, estimated_10k_pace_seconds, confidence, data_source")
    .eq("user_id", userId)
    .gte("created_at", cutoff112)
    .order("created_at", { ascending: false })
    .limit(50);
  const priorSnapshots = (snapRows ?? []).map((s) => ({
    createdAt: s.created_at as string,
    estimated10kPaceSeconds: num(s.estimated_10k_pace_seconds),
    confidence: (s.confidence as string) ?? "Low",
    dataSource: (s.data_source as string | null) ?? null,
  }));

  // Active training plan goal (optional Medium anchor).
  const { data: planRow } = await db
    .from("training_plans")
    .select("target_race_distance, target_time_seconds, status")
    .eq("user_id", userId)
    .eq("status", "active")
    .maybeSingle();
  let plan: PredictionInput["plan"] = null;
  if (planRow && num(planRow.target_time_seconds) > 0) {
    const rt = distanceToRaceType(String(planRow.target_race_distance ?? ""));
    if (rt) plan = { status: "active", raceDistanceKey: rt, targetTimeSeconds: num(planRow.target_time_seconds), raceDistanceMiles: RACE_TYPE_MILES[rt] };
  }

  // EF buckets from the athlete-state fitness signal (heat-aware speed-per-
  // beat, 84d window). Corroborates the training signal's slow direction —
  // see the EF gate in fitnessPrediction. Nightly ordering makes this read a
  // day stale (snapshot 03:30, rebuild 04:00); immaterial for an 11-week
  // trend. Missing row / null signal degrades to pre-gate behavior.
  const { data: stateRow } = await db
    .from("athlete_state")
    .select("fitness_signal")
    .eq("user_id", userId)
    .maybeSingle();
  const rawEff = (stateRow?.fitness_signal as { efficiency?: Array<Record<string, unknown>> } | null)
    ?.efficiency;
  const efficiencySignal: EfficiencyBucketInput[] | null = Array.isArray(rawEff)
    ? rawEff.map((b) => ({
      bucket: String(b.bucket ?? ""),
      direction: String(b.direction ?? ""),
      confidence: String(b.confidence ?? ""),
      efDeltaPct: numOrNull(b.ef_delta_pct),
      recentSamples: num(b.recent_samples),
      baselineSamples: num(b.baseline_samples),
    }))
    : null;

  const prediction = generateFitnessPrediction({
    workouts,
    voiceLogs,
    extendedWorkouts,
    extendedVoiceLogs,
    priorSnapshots,
    plan,
    seededRaces,
    laps,
    efficiencySignal,
    now,
  });

  if (!prediction) return { wrote: false, reason: "no usable fitness signal" };

  const rowData = {
    user_id: userId,
    predicted_mile_seconds: prediction.predictedMileSeconds,
    predicted_5k_seconds: prediction.predicted5kSeconds,
    predicted_10k_seconds: prediction.predicted10kSeconds,
    predicted_half_seconds: prediction.predictedHalfSeconds,
    predicted_marathon_seconds: prediction.predictedMarathonSeconds,
    estimated_10k_pace_seconds: prediction.estimated10kPaceSeconds,
    confidence: prediction.confidence,
    confidence_tier: prediction.confidenceTier,
    data_source: prediction.dataSource,
    workout_count: prediction.workoutCount,
    range_mile_seconds: prediction.rangeMileSeconds,
    range_5k_seconds: prediction.range5kSeconds,
    range_10k_seconds: prediction.range10kSeconds,
    range_half_seconds: prediction.rangeHalfSeconds,
    range_marathon_seconds: prediction.rangeMarathonSeconds,
    // The anchor, persisted (migration 20260817210000). This is the whole
    // point of the canonical row: consumers read what the estimate rests on
    // instead of re-picking and re-normalizing a race themselves. Raw is
    // what she ran; neutral is what it proves — never swap them.
    anchor_race_log_id: prediction.anchor?.sourceWorkoutId ?? null,
    anchor_distance_key: prediction.anchor?.distanceKey ?? null,
    anchor_raw_seconds: prediction.anchor?.rawSeconds ?? null,
    anchor_neutral_seconds: prediction.anchor?.neutralSeconds ?? null,
    anchor_date: prediction.anchor?.date ?? null,
    anchor_weeks_ago: prediction.anchor?.weeksAgo ?? null,
    anchor_conditions: prediction.anchor?.conditions ?? null,
    lifetime_prs: prediction.lifetimePRs ?? null,
    // The last two things the device still computed for itself (migration
    // 20260817220000). Persisting them lets iOS delete its duplicate model
    // rather than run 851 lines to produce a summary line and two counts.
    summary: prediction.summary ?? null,
    supporting_training: prediction.supportingTraining ?? null,
  };

  // Upsert today's row (one per calendar day), matching the iOS behavior.
  const startOfToday = new Date(now);
  startOfToday.setUTCHours(0, 0, 0, 0);
  const { data: todayRow } = await db
    .from("fitness_snapshots")
    .select("id")
    .eq("user_id", userId)
    .gte("created_at", startOfToday.toISOString())
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  if (todayRow?.id) {
    const { error } = await db.from("fitness_snapshots").update(rowData).eq("id", todayRow.id);
    if (error) throw new Error(`update: ${error.message}`);
  } else {
    const { error } = await db.from("fitness_snapshots").insert(rowData);
    if (error) throw new Error(`insert: ${error.message}`);
  }

  // ── Race-candidate gathering (2026-07-17) ──
  // Detection-not-decision: runs that LOOK like races (standard distance,
  // ≥15% faster than the athlete's average) get tagged on their own log row
  // (`extracted_data.race_candidate`, status "pending") for the app to ask
  // "was this a race?". Confirm → the app writes race_result and the race
  // joins the anchors; dismiss → status "dismissed", never asked again.
  // Best-effort: a failure here must never block the snapshot write.
  let candidatesTagged = 0;
  try {
    candidatesTagged = await tagRaceCandidates(db, userId, logRows ?? [], now);
  } catch (e) {
    console.error(`race-candidate tagging failed (non-fatal): ${(e as Error).message}`);
  }

  return {
    wrote: true,
    confidence: prediction.confidence,
    estimated_10k_pace_seconds: prediction.estimated10kPaceSeconds,
    race_candidates_tagged: candidatesTagged,
  };
}

// ---------------------------------------------------------------------------
// Race-candidate detection (2026-07-17). Mirrors the model's Phase-2 GPS race
// detection thresholds (standard distance ± tolerance, pace ≥15% faster than
// the athlete's average) but runs against raw rows so candidates can be tagged
// back onto their source training_logs row.
// ---------------------------------------------------------------------------

async function tagRaceCandidates(
  db: SupabaseClient,
  userId: string,
  rows: Array<Record<string, unknown>>,
  now: Date,
): Promise<number> {
  // Athlete's average pace over the fetched window (all runs, any type).
  const paces: number[] = [];
  for (const row of rows) {
    const miles = num(row.workout_distance_miles);
    const durationMinutes = num(row.workout_duration_minutes);
    if (miles > 0.5 && durationMinutes > 0) paces.push((durationMinutes * 60) / miles);
  }
  if (paces.length < 10) return 0; // not enough context to call anything "fast"
  const avgPace = paces.reduce((s, p) => s + p, 0) / paces.length;

  const candidates: Array<{ id: string; raceType: RaceType; finishSeconds: number }> = [];
  for (const row of rows) {
    if (String(row.workout_type ?? "") === "race") continue;
    if (row.race_result != null) continue;
    const miles = num(row.workout_distance_miles);
    const durationMinutes = num(row.workout_duration_minutes);
    if (!(miles > 0.5 && durationMinutes > 0) || !row.id) continue;
    const pace = (durationMinutes * 60) / miles;
    if (pace >= avgPace * 0.85) continue; // not a race-level effort

    for (const rt of Object.keys(RACE_TYPE_MILES) as RaceType[]) {
      if (Math.abs(miles - RACE_TYPE_MILES[rt]) <= RACE_TYPE_TOLERANCE[rt]) {
        candidates.push({ id: String(row.id), raceType: rt, finishSeconds: Math.round(durationMinutes * 60) });
        break;
      }
    }
  }
  if (candidates.length === 0) return 0;

  // Only tag rows that have never been asked about (any prior status stands).
  const { data: existing } = await db
    .from("training_logs")
    .select("id, extracted_data")
    .in("id", candidates.map((c) => c.id));
  const extractedById = new Map<string, Record<string, unknown>>();
  for (const row of existing ?? []) {
    extractedById.set(String(row.id), (row.extracted_data as Record<string, unknown>) ?? {});
  }

  let tagged = 0;
  for (const c of candidates) {
    const extracted = extractedById.get(c.id) ?? {};
    if (extracted.race_candidate != null) continue;
    const merged = {
      ...extracted,
      race_candidate: {
        race_type: c.raceType,
        race_label: RACE_TYPE_LABEL[c.raceType],
        finish_time_seconds: c.finishSeconds,
        detected_at: now.toISOString(),
        status: "pending",
      },
    };
    const { error } = await db
      .from("training_logs")
      .update({ extracted_data: merged })
      .eq("id", c.id)
      .eq("user_id", userId);
    if (!error) tagged++;
  }
  return tagged;
}

// ---------------------------------------------------------------------------
// Mapping helpers (snake_case DB → module camelCase inputs).
// ---------------------------------------------------------------------------

const RACE_TYPE_MILES: Record<RaceType, number> = {
  mile: 1.0,
  fiveK: 3.107,
  tenK: 6.214,
  half: 13.109,
  marathon: 26.219,
};

function distanceToRaceType(raw: string): RaceType | null {
  switch (raw.toLowerCase().trim()) {
    case "mile":
    case "1mi":
    case "1_mile":
      return "mile";
    case "5k":
    case "fivek":
      return "fiveK";
    case "10k":
    case "tenk":
      return "tenK";
    case "half":
    case "half_marathon":
    case "half-marathon":
    case "halfmarathon":
    case "hm":
      return "half";
    case "marathon":
    case "full":
      return "marathon";
    default:
      return null;
  }
}

// deno-lint-ignore no-explicit-any
function mapPaceSegments(raw: any): VoiceLogInput["paceSegments"] {
  if (!Array.isArray(raw)) return null;
  const out = raw
    // deno-lint-ignore no-explicit-any
    .map((s: any) => ({
      effort: String(s?.effort ?? ""),
      durationSeconds: num(s?.duration_seconds),
      distanceMiles: num(s?.distance_miles),
      pacePerMile: String(s?.pace_per_mile ?? ""),
    }))
    .filter((s) => s.effort);
  return out.length > 0 ? out : null;
}

// deno-lint-ignore no-explicit-any
function mapParsedStructure(raw: any): VoiceLogInput["parsedStructure"] {
  if (!raw || typeof raw !== "object") return null;
  const eq = raw.equivalent_race_pace;
  const work = raw.work ?? raw.work_summary;
  const workDist = num(work?.total_work_distance_mi ?? work?.total_distance_mi ?? work?.totalDistanceMi);
  // The per-rep geometry — what the training signal actually reads.
  // `blocks` is snake_case in the column and camelCase in the model, so the
  // mapping is explicit rather than a spread.
  const blocks = Array.isArray(raw.blocks)
    ? (raw.blocks as Array<Record<string, unknown>>)
      .filter((b) => b && typeof b === "object" && b.role)
      .map((b) => ({
        role: String(b.role),
        durationS: numOrNull(b.duration_s),
        distanceMiles: numOrNull(b.distance_miles),
        avgPacePerMile: b.avg_pace_per_mile == null ? null : String(b.avg_pace_per_mile),
        avgHr: numOrNull(b.avg_hr),
        elevationGainM: numOrNull(b.elevation_gain_m ?? b.total_elevation_gain),
      }))
    : null;

  return {
    confidence: num(raw.confidence),
    type: String(raw.type ?? ""),
    equivalentRacePace: eq && eq.pace_per_mile && eq.distance_key
      ? { pacePerMile: String(eq.pace_per_mile), distanceKey: String(eq.distance_key) }
      : null,
    workSummary: workDist > 0 ? { totalDistanceMi: workDist } : null,
    blocks: blocks && blocks.length > 0 ? blocks : null,
    intentPattern: raw.intent_pattern == null ? null : String(raw.intent_pattern),
  };
}

/** timestamptz / date string → "yyyy-MM-dd" (UTC). */
function toDay(raw: string): string | null {
  if (!raw) return null;
  if (raw.length >= 10 && raw[4] === "-" && raw[7] === "-") return raw.slice(0, 10);
  const d = new Date(raw);
  return Number.isNaN(d.getTime()) ? null : d.toISOString().slice(0, 10);
}

// deno-lint-ignore no-explicit-any
function num(v: any): number {
  const n = typeof v === "number" ? v : Number(v);
  return Number.isFinite(n) ? n : 0;
}

// deno-lint-ignore no-explicit-any
function numOrNull(v: any): number | null {
  if (v === null || v === undefined) return null;
  const n = typeof v === "number" ? v : Number(v);
  return Number.isFinite(n) ? n : null;
}

/** training_logs.weather_actual jsonb → model WeatherInput (or null). */
// deno-lint-ignore no-explicit-any
function mapWeather(raw: any): VoiceLogInput["weather"] {
  if (!raw || typeof raw !== "object") return null;
  const tempF = numOrNull(raw.temp_f);
  const dewPointF = numOrNull(raw.dew_point_f);
  return tempF !== null && dewPointF !== null ? { tempF, dewPointF } : null;
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

/** True if `token` is a non-expired service-role JWT (signature already
 *  verified by the gateway; we only read the claims). */
function isServiceRoleJWT(token: string): boolean {
  try {
    const seg = token.split(".")[1];
    if (!seg) return false;
    const b64 = seg.replace(/-/g, "+").replace(/_/g, "/").padEnd(Math.ceil(seg.length / 4) * 4, "=");
    const payload = JSON.parse(atob(b64)) as { role?: string; exp?: number };
    if (payload.role !== "service_role") return false;
    if (typeof payload.exp === "number" && payload.exp * 1000 < Date.now()) return false;
    return true;
  } catch {
    return false;
  }
}

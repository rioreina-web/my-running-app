/**
 * Coach Workout Read — the AI observation at the foot of the coach
 * WorkoutDrawer (redesign 2026-07-16, §3 row 9 / §5).
 *
 * On demand (the coach taps "generate"), this synthesizes ONE key session's
 * numbers — the same numbers the drawer already renders — into a short,
 * honest observation for the coach, and hands the call back to them. It is
 * cached per training_log in `coach_workout_reads`, so a drawer re-open is
 * free and the LLM only runs on an explicit tap (or a forced regenerate).
 *
 * Voice + safety live in the prompt (coach-workout-read.v1): observational,
 * cites ≥2 numbers, one soft question, NEVER a directive, diagnosis, or
 * stop-training recommendation (hard rule #2). Non-golden family — CI warns
 * only; the gate is manual review against docs/coaching/principles.md.
 *
 * Auth: coach JWT via getAuthenticatedUser, then a coach↔athlete relationship
 * gate (active subscription to one of the coach's plan templates). Per-coach
 * rate limit + monthly cap (feature "coach_workout_read").
 */
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { GoogleGenerativeAI } from "https://esm.sh/@google/generative-ai@0.24.0";

import { loadPrompt } from "../_shared/prompt-library.ts";
import { RESPONSE_SCHEMA } from "../_shared/prompts/coach-workout-read.v1.ts";
import { corsHeaders } from "../_shared/cors.ts";
import { captureException, flushSentry } from "../_shared/sentry.ts";
import { getAuthenticatedUser, unauthorizedResponse } from "../_shared/auth.ts";
import { enforceFeatureRateLimit, enforceMonthlyCap } from "../_shared/rateLimit.ts";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

const METERS_PER_MILE = 1609.344;
const FEET_PER_METER = 3.28084;
const DEW_HOT_F = 68;

interface RequestBody {
  training_log_id?: string;
  athlete_user_id?: string;
  /** Force regeneration even when a cached read exists. */
  force?: boolean;
}

interface LapRow {
  distance_meters: number | null;
  avg_pace_sec_per_mile: number | null;
  heat_adjusted_pace_sec_per_mile: number | null;
  avg_heart_rate: number | null;
  temp_f: number | null;
  dew_point_f: number | null;
  total_elevation_gain: number | null;
  is_rest: boolean | null;
}

// ── small helpers ────────────────────────────────────────────────────────
function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
function fmtPace(sec: number): string {
  const s = Math.max(0, Math.round(sec));
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
}
const miles = (l: LapRow) => Number(l.distance_meters ?? 0) / METERS_PER_MILE;
function weighted(laps: LapRow[], v: (l: LapRow) => number | null | undefined): number | null {
  let num = 0;
  let den = 0;
  for (const l of laps) {
    const mi = miles(l);
    const val = v(l);
    if (mi > 0 && val != null && Number(val) > 0) {
      num += Number(val) * mi;
      den += mi;
    }
  }
  return den > 0 ? num / den : null;
}
// Sum a workout_data.steps[] planned distance (distance segments only).
function plannedMilesFromSteps(steps: unknown): number {
  if (!Array.isArray(steps)) return 0;
  let total = 0;
  for (const s of steps as Array<Record<string, unknown>>) {
    const type = String(s.durationType ?? "");
    const val = Number(s.durationValue ?? 0);
    const reps = Number(s.repeats ?? 1) || 1;
    let mi = 0;
    if (type === "distance_miles") mi = val;
    else if (type === "distance_km") mi = val / 1.609344;
    else if (type === "distance_meters") mi = val / METERS_PER_MILE;
    total += mi * reps;
  }
  return Math.round(total * 10) / 10;
}

// ── entry point ──────────────────────────────────────────────────────────
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  let body: RequestBody;
  try {
    body = (await req.json()) as RequestBody;
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }
  const logId = body.training_log_id;
  const athleteId = body.athlete_user_id;
  if (!logId || typeof logId !== "string" || !athleteId || typeof athleteId !== "string") {
    return json({ error: "training_log_id and athlete_user_id are required" }, 400);
  }

  // ── coach auth ──
  const coachUserId = await getAuthenticatedUser(req);
  if (!coachUserId) return unauthorizedResponse(corsHeaders);

  const { data: coachProfile } = await supabase
    .from("coach_profiles")
    .select("id")
    .eq("user_id", coachUserId)
    .maybeSingle();
  if (!coachProfile) return json({ error: "Not a coach" }, 403);
  const coachId = (coachProfile as { id: string }).id;

  // ── coach ↔ athlete relationship gate (active subscription to a plan
  //    template this coach owns) — mirrors the coach-portal page gate ──
  const { data: gate } = await supabase
    .from("athlete_plan_subscriptions")
    .select("id, plan_template:plan_templates!inner(coach_id)")
    .eq("athlete_user_id", athleteId)
    .eq("status", "active")
    .eq("plan_template.coach_id", coachId)
    .limit(1)
    .maybeSingle();
  if (!gate) return json({ error: "Athlete not coached by you" }, 403);

  try {
    // ── cache-first: a re-open should never re-bill ──
    if (!body.force) {
      const { data: cached } = await supabase
        .from("coach_workout_reads")
        .select("body, question")
        .eq("training_log_id", logId)
        .maybeSingle();
      if (cached) return json({ body: (cached as { body: string }).body, question: (cached as { question: string }).question, cached: true });
    }

    // ── per-coach rate limit + monthly cap (only on an actual generation) ──
    const rl = await enforceFeatureRateLimit(coachUserId, "coach_workout_read", corsHeaders);
    if (rl) return rl;
    const capped = await enforceMonthlyCap(coachUserId, "coach_workout_read", corsHeaders);
    if (capped) return capped;

    // ── the session ──
    const { data: log } = await supabase
      .from("training_logs")
      .select(
        "id, workout_date, workout_distance_miles, workout_duration_minutes, workout_pace_per_mile, workout_type, mood, cleaned_notes, scheduled_workout_id, weather_actual, start_time",
      )
      .eq("id", logId)
      .eq("user_id", athleteId)
      .maybeSingle();
    if (!log) return json({ error: "Workout not found" }, 404);
    const l = log as Record<string, unknown>;

    const [{ data: lapsData }, { data: mentionsData }, { data: state }, { data: settings }] = await Promise.all([
      supabase
        .from("running_workout_laps")
        .select(
          "distance_meters, avg_pace_sec_per_mile, heat_adjusted_pace_sec_per_mile, avg_heart_rate, temp_f, dew_point_f, total_elevation_gain, is_rest",
        )
        .eq("workout_id", logId)
        .order("lap_index", { ascending: true }),
      supabase
        .from("body_mentions")
        .select("body_area, side, verbatim_quote")
        .eq("training_log_id", logId),
      supabase.from("athlete_state").select("acwr").eq("user_id", athleteId).maybeSingle(),
      supabase.from("athlete_settings").select("display_name").eq("user_id", athleteId).maybeSingle(),
    ]);
    const laps = (lapsData ?? []) as LapRow[];
    const runLaps = laps.filter((x) => miles(x) > 0 && !x.is_rest);

    // ── prescription ──
    let scheduled: Record<string, unknown> | null = null;
    if (l.scheduled_workout_id) {
      const { data } = await supabase
        .from("scheduled_workouts")
        .select("workout_type, workout_data")
        .eq("id", l.scheduled_workout_id as string)
        .maybeSingle();
      scheduled = (data as Record<string, unknown> | null) ?? null;
    }
    const plannedMi = scheduled?.workout_data
      ? plannedMilesFromSteps((scheduled.workout_data as Record<string, unknown>).steps)
      : 0;

    // ── context block ──
    const actualMi = Number(l.workout_distance_miles ?? 0);
    const durMin = Number(l.workout_duration_minutes ?? 0);
    const rawPaceLabel = (l.workout_pace_per_mile as string | null) ?? (() => {
      const w = weighted(runLaps, (x) => x.avg_pace_sec_per_mile);
      return w != null ? fmtPace(w) : null;
    })();
    const adj = weighted(runLaps, (x) => x.heat_adjusted_pace_sec_per_mile);
    const rawForDelta = weighted(runLaps, (x) => x.avg_pace_sec_per_mile);
    const tempF = weighted(runLaps, (x) => x.temp_f);
    const dewF = weighted(runLaps, (x) => x.dew_point_f);
    const hrAvg = weighted(runLaps, (x) => x.avg_heart_rate);
    const climbFt = Math.round(runLaps.reduce((s, x) => s + Number(x.total_elevation_gain ?? 0), 0) * FEET_PER_METER);

    const lines: string[] = [];
    lines.push(`Date: ${String(l.workout_date).slice(0, 10)}`);
    lines.push(
      `Prescribed: ${scheduled ? `${scheduled.workout_type ?? "session"}${plannedMi > 0 ? `, ${plannedMi} mi` : ""}` : "no linked prescription"}`,
    );
    lines.push(
      `Actual: ${actualMi.toFixed(1)} mi${plannedMi > 0 && actualMi + 0.05 < plannedMi ? ` (CUT from ${plannedMi} — stopped ${(plannedMi - actualMi).toFixed(1)} mi short)` : ""}${durMin > 0 ? `, ${Math.round(durMin)} min` : ""}${rawPaceLabel ? `, ${rawPaceLabel}/mi` : ""}`,
    );
    if (adj != null && rawForDelta != null) {
      const delta = Math.round(adj - rawForDelta);
      lines.push(`Heat-adjusted pace: ${fmtPace(adj)}/mi (${delta <= 0 ? "−" : "+"}${Math.abs(delta)}s vs raw)`);
    }
    const condParts: string[] = [];
    if (tempF != null) condParts.push(`temp ${Math.round(tempF)}°F`);
    if (dewF != null) condParts.push(`dew point ${Math.round(dewF)}°F${dewF > DEW_HOT_F ? " (past the 68° hot threshold)" : ""}`);
    if (climbFt > 0) condParts.push(`${climbFt.toLocaleString()} ft climb`);
    if (hrAvg != null) condParts.push(`avg HR ${Math.round(hrAvg)}`);
    if (condParts.length) lines.push(`Conditions: ${condParts.join(" · ")}`);

    // thirds for a long run so the model can see the fade
    if (runLaps.length >= 3 && actualMi >= 12) {
      const third = runLaps.reduce((s, x) => s + miles(x), 0) / 3;
      const buckets: LapRow[][] = [[], [], []];
      let acc = 0;
      for (const x of runLaps) {
        buckets[Math.min(2, Math.floor(acc / third))].push(x);
        acc += miles(x);
      }
      const thirdsTxt = buckets
        .map((b, i) => {
          const w = weighted(b, (x) => x.avg_pace_sec_per_mile);
          return w != null ? `${["first", "middle", "last"][i]} third ${fmtPace(w)}` : "";
        })
        .filter(Boolean)
        .join(", ");
      if (thirdsTxt) lines.push(`Splits by third: ${thirdsTxt}`);
    }

    lines.push(`Mood: ${l.mood ?? "not recorded"}`);
    if (l.cleaned_notes) lines.push(`Voice note (verbatim): "${String(l.cleaned_notes).trim()}"`);

    const mentions = (mentionsData ?? []) as Array<{ body_area: string; side: string | null; verbatim_quote: string }>;
    if (mentions.length > 0) {
      lines.push(
        `Body: ${mentions.map((m) => `${m.side ? `${m.side} ` : ""}${m.body_area} — "${m.verbatim_quote}"`).join("; ")}`,
      );
    } else {
      lines.push("Body: no niggles mentioned on this run.");
    }
    if (state && (state as { acwr: number | null }).acwr != null) {
      lines.push(`Load: ACWR ${Number((state as { acwr: number }).acwr).toFixed(2)} after this run.`);
    }

    const athleteRef = (settings as { display_name?: string } | null)?.display_name?.trim() || "the athlete";
    const workoutContext = lines.join("\n");

    // ── LLM ──
    const geminiKey = Deno.env.get("GEMINI_API_KEY");
    if (!geminiKey) return json({ error: "AI not configured" }, 500);
    const genAI = new GoogleGenerativeAI(geminiKey);
    const model = genAI.getGenerativeModel({
      model: "gemini-2.5-flash",
      generationConfig: {
        maxOutputTokens: 600,
        temperature: 0.7,
        responseMimeType: "application/json",
        // deno-lint-ignore no-explicit-any
        responseSchema: RESPONSE_SCHEMA as any,
      },
    });

    const prompt = loadPrompt("coach-workout-read.v1", { athleteRef, workoutContext });
    const result = await model.generateContent(prompt);
    const raw = result.response.text().trim();
    const cleaned = raw
      .replace(/^```json\s*/i, "")
      .replace(/^```\s*/i, "")
      .replace(/```\s*$/i, "")
      .trim();

    let parsed: { body?: unknown; question?: unknown };
    try {
      parsed = JSON.parse(cleaned) as { body?: unknown; question?: unknown };
    } catch {
      return json({ error: "Model returned malformed output" }, 502);
    }
    const readBody = typeof parsed.body === "string" ? parsed.body.trim() : "";
    const readQuestion = typeof parsed.question === "string" ? parsed.question.trim() : "";
    if (!readBody || !readQuestion) return json({ error: "Model output missing body or question" }, 502);

    // ── upsert cache ──
    const { error: upsertErr } = await supabase.from("coach_workout_reads").upsert(
      {
        training_log_id: logId,
        athlete_user_id: athleteId,
        coach_id: coachId,
        body: readBody,
        question: readQuestion,
        model: "gemini-2.5-flash",
        prompt_version: "coach-workout-read.v1",
        generated_at: new Date().toISOString(),
      },
      { onConflict: "training_log_id" },
    );
    if (upsertErr) console.error("coach-workout-read upsert failed:", upsertErr.message);

    return json({ body: readBody, question: readQuestion, cached: false });
  } catch (error) {
    console.error("coach-workout-read error:", error);
    captureException(error, { fn: "coach-workout-read" });
    await flushSentry();
    return json({ error: error instanceof Error ? error.message : String(error) }, 500);
  }
});

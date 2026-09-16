/**
 * ingest-manual-workout — typed manual workout entry.
 *
 * The athlete types one workout in plain language. This function has four
 * modes:
 *
 *   parse   — Gemini extracts stats from the text and returns a DRAFT. No DB
 *             write. iOS shows the draft in an editable confirm screen.
 *   save    — write a NEW training_logs row from the athlete-CONFIRMED fields.
 *   update  — edit an existing manual row (athlete fixed a value later).
 *   delete  — remove a manual row.
 *
 * Design notes / conventions:
 *   - `source = 'manual'` distinguishes these rows. Save/update/delete refuse
 *     to touch any row whose source is not 'manual' (synced rows are read-only
 *     here — see Non-Goal #3 in the feature plan).
 *   - The typed text is written to BOTH `notes` and `cleaned_notes`. Writing
 *     `cleaned_notes` is what makes the existing Niggles scan (body_mentions)
 *     and the Coach Read pick the entry up — both read `cleaned_notes`.
 *   - We do NOT write body_mentions here. The durable, closed-vocabulary
 *     detection runs inside `rebuildAthleteState`, which the
 *     `trg_invalidate_athlete_state` trigger schedules on every write below.
 *     Keeping detection in one place preserves detection-not-diagnosis.
 *   - Manual runs count in the training context exactly like synced runs;
 *     `workout_type` of 'cross_training' / 'strength' keeps non-runs out of
 *     running-fitness math via the existing load/volume logic.
 *   - "AI advises, never acts": parse NEVER writes. Nothing reaches
 *     training_logs until the athlete calls save/update with confirmed fields.
 *
 * Auth: dual-mode (user JWT or service role) via requireAuthOrServiceRole.
 */

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { GoogleGenerativeAI } from "npm:@google/generative-ai@0.21.0";
import { corsHeaders } from "../_shared/cors.ts";
import { requireAuthOrServiceRole } from "../_shared/auth.ts";
import { enforceFeatureRateLimit, enforceMonthlyCap } from "../_shared/rateLimit.ts";
import { loadPrompt } from "../_shared/prompt-library.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const geminiApiKey = Deno.env.get("GEMINI_API_KEY")!;

const supabase = createClient(supabaseUrl, supabaseServiceKey);
const genAI = new GoogleGenerativeAI(geminiApiKey);

const VALID_MOODS = ["energized", "positive", "neutral", "tired", "struggling", "injured"] as const;
const VALID_ACTIVITIES = ["run", "cross_training", "strength"] as const;
// Mirrors `WorkoutLabel.offered` (iOS). `tempo` is kept as an accepted INPUT
// spelling only — it folds to `threshold` on write. (2026-08-10)
const VALID_TYPES = [
  "easy", "moderate", "steady", "long_run", "long_wo",
  "threshold", "intervals", "fartlek", "recovery", "progression", "race",
  "tempo", "cross_training", "strength", "other",
] as const;

type Activity = typeof VALID_ACTIVITIES[number];

interface Draft {
  activity: Activity;
  workout_type: string;
  distance_miles: number | null;
  duration_minutes: number | null;
  pace_per_mile: string | null;
  mood: string | null;
  cleaned_notes: string | null;
  soreness: string[] | null;
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

// Robust JSON extraction (same strategy as process-training-memo).
function parseJsonResponse(responseText: string): Record<string, unknown> {
  try {
    return JSON.parse(responseText);
  } catch { /* continue */ }
  const codeBlock = responseText.match(/```(?:json)?\s*([\s\S]*?)```/);
  if (codeBlock) {
    try {
      return JSON.parse(codeBlock[1].trim());
    } catch { /* continue */ }
  }
  const first = responseText.indexOf("{");
  const last = responseText.lastIndexOf("}");
  if (first !== -1 && last > first) {
    try {
      return JSON.parse(responseText.substring(first, last + 1));
    } catch { /* continue */ }
  }
  throw new Error("Failed to parse AI response as JSON");
}

/** Derive "M:SS" per-mile pace from miles + minutes, or null. */
function derivePace(distanceMiles: number | null, durationMinutes: number | null): string | null {
  if (!distanceMiles || !durationMinutes || distanceMiles <= 0 || durationMinutes <= 0) return null;
  const secPerMile = Math.round((durationMinutes * 60) / distanceMiles);
  const m = Math.floor(secPerMile / 60);
  const s = secPerMile % 60;
  return `${m}:${String(s).padStart(2, "0")}`;
}

const PACE_RE = /^\d{1,2}:[0-5]\d$/;

/** Normalize a raw Gemini object into a validated Draft. Never throws on bad fields — clamps instead. */
function normalizeDraft(raw: Record<string, unknown>): Draft {
  const activity: Activity = VALID_ACTIVITIES.includes(raw.activity as Activity)
    ? (raw.activity as Activity)
    : "run";

  let workout_type = typeof raw.workout_type === "string" && VALID_TYPES.includes(raw.workout_type as typeof VALID_TYPES[number])
    ? raw.workout_type
    : (activity === "run" ? "easy" : activity);
  // Keep non-run activity and type consistent.
  if (activity !== "run") workout_type = activity;

  const distRaw = Number(raw.distance_miles);
  const distance_miles = Number.isFinite(distRaw) && distRaw > 0 && distRaw <= 200 ? distRaw : null;

  const durRaw = Number(raw.duration_minutes);
  const duration_minutes = Number.isFinite(durRaw) && durRaw > 0 && durRaw <= 2000 ? durRaw : null;

  let pace_per_mile = typeof raw.pace_per_mile === "string" && PACE_RE.test(raw.pace_per_mile.trim())
    ? raw.pace_per_mile.trim()
    : null;
  // Prefer a derived pace when distance+duration are present (keeps pace consistent with edits).
  pace_per_mile = derivePace(distance_miles, duration_minutes) ?? pace_per_mile;

  const mood = typeof raw.mood === "string" && VALID_MOODS.includes(raw.mood as typeof VALID_MOODS[number])
    ? raw.mood
    : null;

  const cleaned_notes = typeof raw.cleaned_notes === "string" && raw.cleaned_notes.trim().length > 0
    ? raw.cleaned_notes.trim()
    : null;

  const soreness = Array.isArray(raw.soreness)
    ? (raw.soreness as unknown[]).filter((s): s is string => typeof s === "string" && s.trim().length > 0).slice(0, 12)
    : null;

  return { activity, workout_type, distance_miles, duration_minutes, pace_per_mile, mood, cleaned_notes, soreness };
}

// ── Mode: parse ──────────────────────────────────────────────────────────
async function handleParse(text: string): Promise<Response> {
  const model = genAI.getGenerativeModel({ model: "gemini-2.5-flash" });
  const prompt = loadPrompt("parse-manual-workout.v1");
  const result = await model.generateContent([
    { text: `${prompt}\n\n## Athlete's note\n"${text}"` },
  ]);
  const raw = parseJsonResponse(result.response.text());
  const draft = normalizeDraft(raw);
  return json({ success: true, draft });
}

// Build the training_logs column payload from confirmed fields.
function buildRowPayload(body: Record<string, unknown>): Record<string, unknown> {
  const activity: Activity = VALID_ACTIVITIES.includes(body.activity as Activity)
    ? (body.activity as Activity)
    : "run";

  let workout_type = typeof body.workout_type === "string" && VALID_TYPES.includes(body.workout_type as typeof VALID_TYPES[number])
    ? body.workout_type
    : (activity === "run" ? "easy" : activity);
  if (activity !== "run") workout_type = activity;

  const distRaw = Number(body.distance_miles);
  const distance = Number.isFinite(distRaw) && distRaw > 0 && distRaw <= 200 ? distRaw : null;

  const durRaw = Number(body.duration_minutes);
  const duration = Number.isFinite(durRaw) && durRaw > 0 && durRaw <= 2000 ? durRaw : null;

  let pace = typeof body.pace_per_mile === "string" && PACE_RE.test(body.pace_per_mile.trim())
    ? body.pace_per_mile.trim()
    : null;
  pace = derivePace(distance, duration) ?? pace;

  const mood = typeof body.mood === "string" && VALID_MOODS.includes(body.mood as typeof VALID_MOODS[number])
    ? body.mood
    : null;

  const text = typeof body.text === "string" ? body.text.trim() : "";

  // workout_date: accept an ISO string; default now; never future.
  let workoutDate = new Date();
  if (typeof body.workout_date === "string" && body.workout_date.length > 0) {
    const d = new Date(body.workout_date);
    if (!isNaN(d.getTime())) workoutDate = d;
  }
  if (workoutDate.getTime() > Date.now()) workoutDate = new Date();

  const payload: Record<string, unknown> = {
    source: "manual",
    workout_type,
    workout_date: workoutDate.toISOString(),
    // Write the typed text to BOTH columns: notes is the raw entry, cleaned_notes
    // is what the Niggles scan + Coach Read read.
    notes: text || null,
    cleaned_notes: text || null,
    mood,
    workout_distance_miles: distance,
    workout_duration_minutes: duration,
    workout_pace_per_mile: pace,
    // Manual entries need no async voice/structure processing.
    processing_status: "completed",
  };
  return payload;
}

// ── Mode: save ───────────────────────────────────────────────────────────
async function handleSave(userId: string, body: Record<string, unknown>): Promise<Response> {
  const text = typeof body.text === "string" ? body.text.trim() : "";
  const payload = buildRowPayload(body);
  payload.user_id = userId;

  // A manual entry must carry at least some signal.
  if (!text && payload.workout_distance_miles == null && payload.workout_duration_minutes == null) {
    return json({ error: "Nothing to save — add a description, distance, or duration." }, 400);
  }

  const { data, error } = await supabase
    .from("training_logs")
    .insert(payload)
    .select("id")
    .single();

  if (error) {
    console.error("[ingest-manual-workout] insert failed:", error.message);
    return json({ error: "Could not save workout." }, 500);
  }
  // trg_invalidate_athlete_state fires on this insert → next read rebuilds
  // athlete-state (volume/ACWR/niggles) including this entry.
  return json({ success: true, id: data.id });
}

// Verify the row exists, belongs to the caller, and is a manual entry.
// Returns null when OK, or a Response (404) to return immediately.
async function guardManualOwnership(userId: string, trainingLogId: string): Promise<Response | null> {
  const { data, error } = await supabase
    .from("training_logs")
    .select("user_id, source")
    .eq("id", trainingLogId)
    .maybeSingle();
  // 404 (not 403) so callers can't probe existence of others' rows.
  if (error || !data || data.user_id !== userId) return json({ error: "Not found" }, 404);
  if (data.source !== "manual") {
    return json({ error: "Only manually-entered workouts can be edited here." }, 403);
  }
  return null;
}

// ── Mode: update ─────────────────────────────────────────────────────────
async function handleUpdate(userId: string, body: Record<string, unknown>): Promise<Response> {
  const id = typeof body.training_log_id === "string" ? body.training_log_id : "";
  if (!id) return json({ error: "training_log_id required" }, 400);

  const guard = await guardManualOwnership(userId, id);
  if (guard) return guard;

  const payload = buildRowPayload(body);
  // Don't reassign source/user_id on update; keep them as-is.
  delete payload.source;

  const { error } = await supabase
    .from("training_logs")
    .update(payload)
    .eq("id", id)
    .eq("user_id", userId);

  if (error) {
    console.error("[ingest-manual-workout] update failed:", error.message);
    return json({ error: "Could not update workout." }, 500);
  }
  return json({ success: true, id });
}

// ── Mode: delete ─────────────────────────────────────────────────────────
async function handleDelete(userId: string, body: Record<string, unknown>): Promise<Response> {
  const id = typeof body.training_log_id === "string" ? body.training_log_id : "";
  if (!id) return json({ error: "training_log_id required" }, 400);

  const guard = await guardManualOwnership(userId, id);
  if (guard) return guard;

  const { error } = await supabase
    .from("training_logs")
    .delete()
    .eq("id", id)
    .eq("user_id", userId);

  if (error) {
    console.error("[ingest-manual-workout] delete failed:", error.message);
    return json({ error: "Could not delete workout." }, 500);
  }
  return json({ success: true, id });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const body = await req.json() as Record<string, unknown>;
    const bodyUserId = typeof body.user_id === "string" ? body.user_id : undefined;

    const auth = await requireAuthOrServiceRole(req, bodyUserId, corsHeaders);
    if ("response" in auth) return auth.response;
    const { userId, isServiceRole } = auth;

    const mode = typeof body.mode === "string" ? body.mode : "";

    if (mode === "parse") {
      const text = typeof body.text === "string" ? body.text.trim() : "";
      if (text.length < 2) return json({ error: "Type a workout to parse." }, 400);
      // Only the parse mode calls the LLM, so rate-limit it.
      const blocked = await enforceFeatureRateLimit(userId, "parse", corsHeaders, { isServiceRole });
      if (blocked) return blocked;
      const monthlyCapped = await enforceMonthlyCap(userId, "parse", corsHeaders, { isServiceRole });
      if (monthlyCapped) return monthlyCapped;
      return await handleParse(text);
    }

    if (mode === "save") return await handleSave(userId, body);
    if (mode === "update") return await handleUpdate(userId, body);
    if (mode === "delete") return await handleDelete(userId, body);

    return json({ error: `Unknown mode "${mode}". Use parse | save | update | delete.` }, 400);
  } catch (error) {
    console.error("[ingest-manual-workout] error:", error);
    return json({ error: "Request failed. Please try again." }, 500);
  }
});

/**
 * Generate Workout Insight
 *
 * Produces a one-sentence coaching reading for a `training_logs` row.
 * Pure LLM-call function — caller (the worker, or an authenticated user
 * regenerating via the UI) owns retry/policy.
 *
 * Coexists with `process-training-memo`, which already writes
 * coach_insight on voice-logged runs (audio_url present). This function
 * fills the gap for HealthKit / direct-entry runs.
 *
 * Idempotent: returns the existing insight if already populated.
 *
 * Auth:
 *   - Service-role caller (the drain worker) is allowed.
 *   - Otherwise, the JWT user must own the row (RLS-style check).
 *   - Anonymous callers are rejected with 401.
 *
 * Status-code contract (consumed by the worker):
 *   200 — success or already-populated (response.cached true)
 *   400 — bad request (missing / non-UUID training_log_id)
 *   401 — no auth
 *   403 — caller doesn't own the row
 *   404 — training log not found
 *   429 — caller / global rate limit hit (retryable)
 *   502 — Gemini upstream failure (retryable)
 *
 * Body:
 *   { training_log_id: string }
 */

import { createClient } from "jsr:@supabase/supabase-js@2";
import { GoogleGenerativeAI } from "npm:@google/generative-ai@0.21.0";
import { enforceFeatureRateLimit } from "../_shared/rateLimit.ts";
import { loadPrompt } from "../_shared/prompt-library.ts";
import {
  loadCoachContext,
  formatPacesBlock,
  classifyPace,
  comparePrescribedToExecuted,
  findSimilarPriorWorkout,
  formatProgressionBlock,
  formatSplitsBlock,
  splitsFromPaceSegments,
  splitsFromExtractedIntervals,
  type CoachContext,
  type ScheduledLite as CoachScheduledLite,
  type ExecutedSummary,
} from "../_shared/coach-context.ts";

import { corsHeaders } from "../_shared/cors.ts";
const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
const geminiApiKey = Deno.env.get("GEMINI_API_KEY")!;

const adminClient = createClient(supabaseUrl, supabaseServiceKey);
const genAI = new GoogleGenerativeAI(geminiApiKey);

interface TrainingLogRow {
  id: string;
  user_id: string;
  workout_date: string;
  workout_distance_miles: number | null;
  workout_duration_minutes: number | null;
  workout_pace_per_mile: string | null;
  workout_type: string | null;
  mood: string | null;
  cleaned_notes: string | null;
  notes: string | null;
  coach_insight: string | null;
  scheduled_workout_id: string | null;
  /** Garmin/HealthKit-derived rep splits. */
  pace_segments: Array<{
    effort?: string;
    distance_miles?: number | string;
    pace_per_mile?: string;
    avg_heart_rate?: number;
  }> | null;
  /** Voice-memo-extracted structured data (intervals/splits). */
  extracted_data: Record<string, unknown> | null;
}

interface ScheduledLite {
  id: string;
  workout_type: string | null;
  workout_data: Record<string, unknown> | null;
  notes: string | null;
}

interface RecentRow {
  workout_date: string;
  workout_distance_miles: number | null;
  workout_type: string | null;
  mood: string | null;
}

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // --- Auth ---
    const authHeader = req.headers.get("Authorization") ?? "";
    if (!authHeader.startsWith("Bearer ")) {
      return jsonResponse({ error: "Authentication required" }, 401);
    }
    const token = authHeader.slice("Bearer ".length).trim();
    const isServiceRole = constantTimeEq(token, supabaseServiceKey);

    let callerUserId: string | null = null;
    if (!isServiceRole) {
      // User JWT path — verify and extract uid.
      const userClient = createClient(supabaseUrl, supabaseAnonKey, {
        global: { headers: { Authorization: `Bearer ${token}` } },
      });
      const { data, error } = await userClient.auth.getUser(token);
      if (error || !data.user) {
        return jsonResponse({ error: "Invalid token" }, 401);
      }
      callerUserId = data.user.id;
    }

    // --- Per-user rate limit (TASKS.md W2.3) ---
    // Service-role callers (trigger_workout_insight, drain-coach-insight-jobs
    // cron) bypass via isServiceRole. User-callable path (iOS retry from
    // TodayHomeView) is gated per user_id.
    if (!isServiceRole && callerUserId) {
      const rlBlocked = await enforceFeatureRateLimit(
        callerUserId,
        "workout_insight",
        corsHeaders,
        { isServiceRole: false },
      );
      if (rlBlocked) return rlBlocked;
    }

    // --- Input validation ---
    const body = await req.json().catch(() => ({}));
    const trainingLogId = (body as { training_log_id?: unknown }).training_log_id;
    if (typeof trainingLogId !== "string" || !UUID_RE.test(trainingLogId)) {
      return jsonResponse({ error: "training_log_id must be a UUID" }, 400);
    }

    // Cost protection lives outside this code (W1.1) — Google Cloud billing
    // budget hard-caps the Gemini key at the provider level. No in-code gate.

    // --- Load row ---
    const { data: row, error: loadErr } = await adminClient
      .from("training_logs")
      .select(
        "id, user_id, workout_date, workout_distance_miles, workout_duration_minutes, workout_pace_per_mile, workout_type, mood, cleaned_notes, notes, coach_insight, scheduled_workout_id, pace_segments, extracted_data"
      )
      .eq("id", trainingLogId)
      .maybeSingle<TrainingLogRow>();

    if (loadErr) {
      console.error("training_logs load error:", loadErr.message);
      return jsonResponse({ error: "Database error" }, 500);
    }
    if (!row) {
      return jsonResponse({ error: "Log not found" }, 404);
    }

    // Ownership check for non-service callers.
    if (!isServiceRole && callerUserId !== row.user_id) {
      return jsonResponse({ error: "Forbidden" }, 403);
    }

    // --- Atomic claim: only one caller wins the right to write ---
    // If another worker already claimed and wrote, this UPDATE will
    // affect zero rows and we'll return the cached value below.
    if (row.coach_insight && row.coach_insight.trim().length > 0) {
      return jsonResponse({ insight: row.coach_insight, cached: true });
    }

    // --- Pull context ---
    let scheduled: ScheduledLite | null = null;
    if (row.scheduled_workout_id) {
      const { data } = await adminClient
        .from("scheduled_workouts")
        .select("id, workout_type, workout_data, notes")
        .eq("id", row.scheduled_workout_id)
        .maybeSingle<ScheduledLite>();
      scheduled = data ?? null;
    }

    const sevenDaysAgo = new Date(
      new Date(row.workout_date).getTime() - 7 * 86400000
    );
    // Compute current run's pace once — needed for both classification
    // and the similar-prior matcher.
    const currentPaceSec = parsePaceSec(row.workout_pace_per_mile)
      ?? deriveAveragePace(row.workout_distance_miles, row.workout_duration_minutes);

    // Recent logs + coach context + similar prior workout — all fetched
    // in parallel. Similar-prior is gated on having a workout_type +
    // distance + pace; otherwise it's not a comparable session.
    const priorPromise = (row.workout_type && row.workout_distance_miles && currentPaceSec)
      ? findSimilarPriorWorkout(adminClient, row.user_id, {
          workoutType: row.workout_type,
          distanceMiles: row.workout_distance_miles,
          paceSecPerMile: currentPaceSec,
        }, new Date(row.workout_date))
      : Promise.resolve(null);

    const [recentRes, coachCtx, prior] = await Promise.all([
      adminClient
        .from("training_logs")
        .select("workout_date, workout_distance_miles, workout_type, mood")
        .eq("user_id", row.user_id)
        .gte("workout_date", sevenDaysAgo.toISOString())
        .lt("workout_date", row.workout_date)
        .order("workout_date", { ascending: false })
        .limit(14),
      loadCoachContext(adminClient, row.user_id),
      priorPromise,
    ]);
    const recent = recentRes.data ?? [];

    // Progression block — only when matcher found a comparable prior AND
    // the deltas are meaningful (formatProgressionBlock filters noise).
    const progressionBlock = (prior && row.workout_type && row.workout_distance_miles && currentPaceSec)
      ? (formatProgressionBlock(
          {
            workoutType: row.workout_type,
            distanceMiles: row.workout_distance_miles,
            paceSecPerMile: currentPaceSec,
          },
          prior,
        )?.block ?? "")
      : "";

    // --- LLM call ---
    const insight = await generateInsight(
      row,
      scheduled,
      recent as RecentRow[],
      coachCtx,
      progressionBlock,
    );

    if (insight === null) {
      // Gemini failure — retryable. Worker will back off + retry.
      return jsonResponse({ error: "Upstream model failure" }, 502);
    }

    // --- Conditional write ---
    // IS NULL guard prevents clobbering a concurrent voice/manual write.
    const { error: updErr } = await adminClient
      .from("training_logs")
      .update({
        coach_insight: insight,
        coach_insight_status: "generated",
      })
      .eq("id", trainingLogId)
      .is("coach_insight", null);

    if (updErr) {
      console.warn("update coach_insight failed:", updErr.message);
      return jsonResponse({ error: "Database write failed" }, 500);
    }

    return jsonResponse({ insight, cached: false });
  } catch (err) {
    console.error("generate-workout-insight error:", err);
    return jsonResponse({ error: String(err) }, 500);
  }
});

/**
 * Constant-time string comparison to avoid timing attacks on the
 * service-role check.
 */
function constantTimeEq(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let result = 0;
  for (let i = 0; i < a.length; i++) {
    result |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return result === 0;
}

async function generateInsight(
  log: TrainingLogRow,
  scheduled: ScheduledLite | null,
  recent: RecentRow[],
  coachCtx: CoachContext,
  progressionBlock: string,
): Promise<string | null> {
  const recentSummary = summarizeRecent(recent);

  // Pace anchoring + deterministic zone classification.
  const pacesBlock = formatPacesBlock(coachCtx);
  const executedPaceSec = parsePaceSec(log.workout_pace_per_mile)
    ?? deriveAveragePace(log.workout_distance_miles, log.workout_duration_minutes);
  const classificationLine =
    executedPaceSec != null && coachCtx.zones
      ? classifyPace(executedPaceSec, coachCtx.zones).summary
      : "";

  // Splits block — prefer Garmin/HK pace_segments; fall back to voice-
  // extracted intervals. Both can be present; pace_segments wins because
  // it's actually-run data, not athlete-recalled.
  const watchSplits = splitsFromPaceSegments(log.pace_segments);
  const extractedIntervals = (log.extracted_data?.intervals ?? null) as
    | Array<{ distance?: string; time?: string; rest?: string; count?: number }>
    | null;
  const voiceSplits = watchSplits.length === 0
    ? splitsFromExtractedIntervals(extractedIntervals)
    : [];
  const splits = watchSplits.length > 0 ? watchSplits : voiceSplits;
  const splitsBlock = formatSplitsBlock(splits, coachCtx.zones);

  // Prescription-vs-execution — pass real pace_segments now so per-rep
  // comparison fires when the scheduled workout has structured steps.
  const comparison = scheduled
    ? comparePrescribedToExecuted(
        scheduled as CoachScheduledLite,
        {
          averagePaceSec: executedPaceSec,
          paceSegments: log.pace_segments ?? [],
        } satisfies ExecutedSummary,
        coachCtx.zones,
      )
    : null;
  const prescribedBlock = comparison?.block ?? "";

  const userPrompt = loadPrompt("generate-workout-insight.v4", {
    workoutType: log.workout_type ?? "run",
    distance: log.workout_distance_miles ?? "?",
    pace: log.workout_pace_per_mile ?? "?",
    duration: log.workout_duration_minutes ?? "?",
    mood: log.mood ?? "—",
    athleteNotes: log.cleaned_notes ?? log.notes ?? "—",
    pacesBlock,
    classificationLine,
    splitsBlock,
    prescribedBlock,
    progressionBlock,
    recentSummary,
  });

  try {
    const model = genAI.getGenerativeModel({
      model: "gemini-2.5-flash",
      generationConfig: {
        temperature: 0.7,
        maxOutputTokens: 100,
      },
    });

    // Hard timeout — Gemini Flash p99 should be ~3-5s; anything past 20s
    // is hung. Worker's retry loop will pick it up.
    const result = await Promise.race([
      model.generateContent(userPrompt),
      new Promise<never>((_, reject) =>
        setTimeout(() => reject(new Error("Gemini timeout")), 20_000)
      ),
    ]);

    const text = (result as Awaited<ReturnType<typeof model.generateContent>>)
      .response.text()
      .trim();
    return text.replace(/^["'`]+|["'`]+$/g, "").trim() || null;
  } catch (err) {
    console.error("Gemini call failed:", err);
    return null;
  }
}

/** Parse a "M:SS" pace string to seconds/mile, or null. */
function parsePaceSec(s: string | null | undefined): number | null {
  if (!s) return null;
  const m = s.match(/^(\d{1,2}):(\d{2})$/);
  if (!m) return null;
  const min = parseInt(m[1]);
  const sec = parseInt(m[2]);
  if (isNaN(min) || isNaN(sec)) return null;
  return min * 60 + sec;
}

/** Compute average pace from distance + duration, or null. */
function deriveAveragePace(distanceMi: number | null, durationMin: number | null): number | null {
  if (!distanceMi || !durationMin || distanceMi <= 0 || durationMin <= 0) return null;
  return Math.round((durationMin * 60) / distanceMi);
}

function summarizeRecent(rows: RecentRow[]): string {
  if (rows.length === 0) return "no other runs in the last week";
  const totalMi = rows.reduce(
    (s, r) => s + (r.workout_distance_miles ?? 0),
    0
  );
  const types = rows.map((r) => r.workout_type).filter((t): t is string => !!t);
  const typeCounts: Record<string, number> = {};
  for (const t of types) typeCounts[t] = (typeCounts[t] ?? 0) + 1;
  const typeStr = Object.entries(typeCounts)
    .map(([t, n]) => `${n} ${t}`)
    .join(", ");
  return `${rows.length} runs (${totalMi.toFixed(1)} mi) — ${typeStr || "mix"}`;
}

function jsonResponse(
  body: Record<string, unknown>,
  status = 200
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

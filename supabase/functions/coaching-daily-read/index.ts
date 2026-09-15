/**
 * coaching-daily-read
 *
 * Generates the morning "Read" — a structured, editorial coaching post that
 * lives on the Coach tab. One per athlete per day. See
 * `coach-the-read-prompts.md` Phase 1, Prompt 1.3 for the spec and
 * `supabase/migrations/20260519100000_daily_coaching_reads.sql` for the
 * persistence layer.
 *
 * Callers:
 *   - The hourly cron job (Prompt 1.4) at the athlete's local 6 AM.
 *   - iOS `CoachReadService.refresh()` (Phase 2.2) when no row exists for
 *     today.
 *   - The training_logs trigger (Prompt 1.5) for post-quality-session
 *     re-renders.
 *
 * Auth: dual-mode (service-role for cron/trigger, user JWT for iOS pull-to-
 * refresh). See `requireAuthOrServiceRole` in `_shared/auth.ts`. The
 * gateway-level `verify_jwt = false` in `config.toml` permits both
 * paths; the function validates internally.
 *
 * Idempotency: a unique (user_id, read_date) constraint on
 * `daily_coaching_reads` plus an existence-check before insert means
 * concurrent calls for the same (user, day) collapse to a single Read.
 *
 * TODO (Phase 1 follow-up): the context fetch below overlaps with
 * `coaching-agent/index.ts` lines ~700-820. Extract a shared
 * athlete-context helper once both functions have stable shapes — for
 * now, this inline fetch is the focused subset the Daily Read needs (no
 * conversation history, no query-embedding RAG, no rate-limit cache).
 */

import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import { GoogleGenerativeAI } from "https://esm.sh/@google/generative-ai@0.21.0";

import { corsHeaders } from "../_shared/cors.ts";
import { requireAuthOrServiceRole } from "../_shared/auth.ts";
import { enforceFeatureRateLimit } from "../_shared/rateLimit.ts";
import { loadPrompt } from "../_shared/prompt-library.ts";
import { RESPONSE_SCHEMA } from "../_shared/prompts/daily-read.v3.ts";
import { getModelConfig } from "../_shared/router.ts";
import { getOrBuildAthleteState, stateToPromptContext } from "../_shared/athlete-state.ts";
import {
  type CantSee,
  type Confidence,
  type DailyReadPayload,
  type ParagraphSegment,
  type Sources,
  formatWeeklyVolume,
  isRunningType,
  parseModelResponse,
  validateRead,
  weekdayName,
  weeklyRunningVolume,
} from "../_shared/daily-read-shape.ts";

/** Which prompt version this function renders with. Bump here + in the cassette dir. */
const PROMPT_NAME = "daily-read.v3";

interface RequestBody {
  user_id?: string;
  triggered_by?: "cron" | "manual" | "workout_trigger";
}

// ── Constants ────────────────────────────────────────────────────────

const MAX_TRAINING_LOGS = 60;          // ~2 months of daily training
const TRAINING_LOG_LOOKBACK_DAYS = 60;
const MAX_COACHING_DOCS = 8;
const MAX_VOICE_MEMOS = 6;
const VOICE_MEMO_LOOKBACK_DAYS = 14;

// Workout types that count toward the HIGH-confidence threshold (the
// prompt itself decides confidence; this list is only used to surface
// "quality session" tags in the context block for the model).
const QUALITY_WORKOUT_TYPES = new Set([
  "tempo",
  "threshold",
  "interval",
  "intervals",
  "long",
  "long_run",
  "progression",
  "race",
]);

// ── Entry point ──────────────────────────────────────────────────────

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return new Response(
      JSON.stringify({ error: "Method not allowed" }),
      { status: 405, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }

  let body: RequestBody;
  try {
    body = (await req.json()) as RequestBody;
  } catch {
    return new Response(
      JSON.stringify({ error: "Invalid JSON body" }),
      { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }

  if (!body.user_id || typeof body.user_id !== "string") {
    return new Response(
      JSON.stringify({ error: "user_id is required" }),
      { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }

  const auth = await requireAuthOrServiceRole(req, body.user_id, corsHeaders);
  if ("response" in auth) return auth.response;
  const { userId, isServiceRole } = auth;

  const rlBlocked = await enforceFeatureRateLimit(userId, "daily_read", corsHeaders, { isServiceRole });
  if (rlBlocked) return rlBlocked;

  const triggeredBy = body.triggered_by ?? "cron";
  if (!["cron", "manual", "workout_trigger"].includes(triggeredBy)) {
    return new Response(
      JSON.stringify({ error: `Invalid triggered_by: ${triggeredBy}` }),
      { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }

  // Service role goes through SUPABASE_SERVICE_ROLE_KEY so RLS doesn't
  // block writes; user-JWT path uses the anon key and the request's
  // bearer (RLS scopes it to the user automatically).
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    isServiceRole
      ? Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
      : Deno.env.get("SUPABASE_ANON_KEY")!,
    isServiceRole
      ? {}
      : {
          global: {
            headers: { Authorization: req.headers.get("Authorization") ?? "" },
          },
        },
  );

  try {
    const readDate = await resolveAthleteLocalDate(supabase, userId);

    // ── 1. Short-circuit: completed row already exists for today ─────
    // The workout-trigger path (Prompt 1.5) deliberately BYPASSES this
    // short-circuit — a freshly logged quality session is the whole
    // reason that trigger fires, so we want a regenerate, not a
    // return-cached. Cron and manual paths still short-circuit.
    const existing = await fetchExistingRead(supabase, userId, readDate);
    if (
      existing &&
      existing.status === "completed" &&
      triggeredBy !== "workout_trigger"
    ) {
      // Rows written before the v3 `questions` column landed have no
      // array; the iOS decoder tolerates a missing key, but normalize
      // here so every response carries the full v3 shape.
      if (!Array.isArray(existing.questions)) existing.questions = [];
      return jsonResponse(200, { read: existing, cached: true });
    }

    // ── 2. Insert (or reuse) the pending row. Unique constraint on
    //      (user_id, read_date) means concurrent generations collapse
    //      to one row — we just update whatever's there.
    const pending = await upsertPendingRead(supabase, userId, readDate, triggeredBy);
    if (!pending) {
      return jsonResponse(500, {
        error: "Failed to create pending read row",
      });
    }

    // ── 3. Build the context bundle ──────────────────────────────────
    const context = await buildDailyReadContext(supabase, userId, readDate);

    // ── 4. Call Gemini ───────────────────────────────────────────────
    const modelConfig = getModelConfig("complex"); // creative + extended context
    const apiKey = Deno.env.get(modelConfig.apiKeyEnv);
    if (!apiKey) {
      await markFailed(supabase, pending.id, `${modelConfig.apiKeyEnv} not configured`);
      return jsonResponse(500, {
        error: `${modelConfig.apiKeyEnv} not configured`,
      });
    }

    const systemPrompt = loadPrompt(PROMPT_NAME, {});
    const fullPrompt = `${systemPrompt}\n\n${context.contextBlock}\n\nGenerate today's Read for this athlete.`;

    let raw: string;
    const modelId = modelConfig.model;
    try {
      const genAI = new GoogleGenerativeAI(apiKey);
      const model = genAI.getGenerativeModel({
        model: modelConfig.model,
        generationConfig: {
          maxOutputTokens: modelConfig.maxTokens,
          temperature: 0.6,
          responseMimeType: "application/json",
          // Schema is best-effort; if a particular Gemini version rejects
          // `anyOf` we fall back to JSON-mime only — the validator does
          // the real shape enforcement downstream.
          // deno-lint-ignore no-explicit-any
          responseSchema: RESPONSE_SCHEMA as any,
        },
      });
      const result = await model.generateContent(fullPrompt);
      raw = result.response.text();
    } catch (err) {
      // Retry without the schema if the SDK/model rejects it. Failure
      // mode is "schema-related validation error" — different vendors
      // surface this differently, so we catch broadly and retry once.
      console.warn("daily-read: schema-enabled call failed, retrying without schema:", err);
      try {
        const genAI = new GoogleGenerativeAI(apiKey);
        const model = genAI.getGenerativeModel({
          model: modelConfig.model,
          generationConfig: {
            maxOutputTokens: modelConfig.maxTokens,
            temperature: 0.6,
            responseMimeType: "application/json",
          },
        });
        const result = await model.generateContent(fullPrompt);
        raw = result.response.text();
      } catch (retryErr) {
        const message = retryErr instanceof Error ? retryErr.message : String(retryErr);
        await markFailed(supabase, pending.id, `Gemini call failed: ${message}`);
        return jsonResponse(502, { error: "Model call failed" });
      }
    }

    // ── 5. Parse the response ────────────────────────────────────────
    let parsed: DailyReadPayload;
    try {
      parsed = parseModelResponse(raw);
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      await markFailed(supabase, pending.id, `Parse failed: ${message}`);
      return jsonResponse(502, { error: "Model returned unparseable JSON" });
    }

    // ── 6. Validate + strip invalid citations, normalize shape ───────
    const { payload: validated, report } = validateRead(parsed, context);
    if (report.droppedWorkoutCitations > 0) {
      console.warn(`daily-read: stripped ${report.droppedWorkoutCitations} invalid workout citation(s)`);
    }
    if (report.droppedDocCitations > 0) {
      console.warn(`daily-read: stripped ${report.droppedDocCitations} invalid doc citation(s)`);
    }
    if (report.droppedQuestions > 0) {
      console.warn(`daily-read: dropped ${report.droppedQuestions} malformed/extra question(s)`);
    }

    // ── 7. Update the row to completed ───────────────────────────────
    const completed = await markCompleted(
      supabase,
      pending.id,
      validated,
      modelId,
    );
    if (!completed) {
      return jsonResponse(500, { error: "Failed to persist completed read" });
    }

    return jsonResponse(200, { read: completed, cached: false });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.error("coaching-daily-read: unhandled error:", message);
    // Best-effort failure marker; if we don't have a pending row id we
    // just log. The next cron tick will retry.
    return jsonResponse(500, { error: "Internal error", detail: message });
  }
});

// ── Date resolution ──────────────────────────────────────────────────

/**
 * Resolve today's date in the athlete's local timezone. Reads
 * `user_profiles.timezone` (e.g. "America/Los_Angeles"); falls back to
 * UTC if missing.
 */
async function resolveAthleteLocalDate(
  supabase: SupabaseClient,
  userId: string,
): Promise<string> {
  const { data } = await supabase
    .from("user_profiles")
    .select("timezone")
    .eq("user_id", userId)
    .maybeSingle();
  const tz = (data?.timezone as string | null) ?? "UTC";
  try {
    const fmt = new Intl.DateTimeFormat("en-CA", {
      timeZone: tz,
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
    });
    return fmt.format(new Date());
  } catch {
    // Bad timezone string in the profile — fall back to UTC.
    return new Date().toISOString().slice(0, 10);
  }
}

// ── Idempotency & row lifecycle ──────────────────────────────────────

interface DailyReadRow {
  id: string;
  user_id: string;
  read_date: string;
  status: "pending" | "completed" | "failed";
  headline: string | null;
  paragraph: ParagraphSegment[];
  /** v3 soft questions. Absent on rows written before the column landed. */
  questions?: string[];
  cant_see: CantSee | null;
  sources: Sources;
  confidence: Confidence | Record<string, never>;
  ai_model: string | null;
  generated_at: string | null;
  triggered_by: "cron" | "manual" | "workout_trigger";
  error_message: string | null;
  created_at: string;
  updated_at: string;
}

async function fetchExistingRead(
  supabase: SupabaseClient,
  userId: string,
  readDate: string,
): Promise<DailyReadRow | null> {
  const { data, error } = await supabase
    .from("daily_coaching_reads")
    .select("*")
    .eq("user_id", userId)
    .eq("read_date", readDate)
    .maybeSingle();
  if (error) {
    console.warn("daily-read: existing-row fetch error:", error.message);
    return null;
  }
  return (data as DailyReadRow | null) ?? null;
}

async function upsertPendingRead(
  supabase: SupabaseClient,
  userId: string,
  readDate: string,
  triggeredBy: "cron" | "manual" | "workout_trigger",
): Promise<DailyReadRow | null> {
  // ON CONFLICT (user_id, read_date) DO UPDATE — if a failed row exists
  // we want to retry it cleanly. Status reset to "pending"; trigger
  // source updated to whatever invoked us now.
  const { data, error } = await supabase
    .from("daily_coaching_reads")
    .upsert(
      {
        user_id: userId,
        read_date: readDate,
        status: "pending",
        triggered_by: triggeredBy,
        // Reset prior failure artifacts so a retry starts clean.
        error_message: null,
      },
      { onConflict: "user_id,read_date" },
    )
    .select("*")
    .single();
  if (error) {
    console.error("daily-read: upsert pending failed:", error.message);
    return null;
  }
  return data as DailyReadRow;
}

async function markFailed(
  supabase: SupabaseClient,
  rowId: string,
  message: string,
): Promise<void> {
  await supabase
    .from("daily_coaching_reads")
    .update({
      status: "failed",
      error_message: message.slice(0, 2000),
    })
    .eq("id", rowId);
}

async function markCompleted(
  supabase: SupabaseClient,
  rowId: string,
  payload: DailyReadPayload,
  aiModel: string,
): Promise<DailyReadRow | null> {
  const base = {
    status: "completed",
    headline: payload.headline,
    paragraph: payload.paragraph,
    cant_see: payload.cant_see,
    sources: payload.sources,
    confidence: payload.confidence,
    ai_model: aiModel,
    generated_at: new Date().toISOString(),
    error_message: null,
  };

  const attempt = async (row: Record<string, unknown>) =>
    await supabase
      .from("daily_coaching_reads")
      .update(row)
      .eq("id", rowId)
      .select("*")
      .single();

  let { data, error } = await attempt({ ...base, questions: payload.questions });

  // Deploy-order safety net: if this function ships before the
  // `questions` column migration (20260915120000) has been pushed,
  // Postgres answers 42703 (undefined_column). Fall back to writing the
  // v2 shape so the athlete still gets a Read; the questions are lost
  // for that row only. Loud in the logs so it doesn't stay that way.
  if (error && /questions/.test(error.message) && /column|42703/i.test(error.message + (error.code ?? ""))) {
    console.error(
      "daily-read: `questions` column missing — run `supabase db push` for 20260915120000_daily_coaching_reads_questions. Writing v2 shape.",
    );
    ({ data, error } = await attempt(base));
  }

  if (error) {
    console.error("daily-read: mark completed failed:", error.message);
    return null;
  }
  const row = data as DailyReadRow;
  if (row && !Array.isArray(row.questions)) row.questions = [];
  return row;
}

// ── Context fetch ────────────────────────────────────────────────────

interface DailyReadContext {
  /** The full markdown context block to append to the system prompt. */
  contextBlock: string;
  /** Workout ids the model may legally cite. */
  validWorkoutIds: Set<string>;
  /** Doc ids the model may legally cite. */
  validDocIds: Set<string>;
  /** Voice memo (training_log) ids the model may legally cite in sources.memos. */
  validMemoLogIds: Set<string>;
}

/**
 * Build the context the v3 prompt reads. Beyond the raw rows, this
 * pre-computes the facts the Read is supposed to be *about* — weekly
 * running volume in trend form, the quality sessions with their paces,
 * today's date, and yesterday's questions — so the model spends its
 * effort on the sentence, not the arithmetic. Every number the prompt
 * is allowed to quote should be visible somewhere in this block.
 */
async function buildDailyReadContext(
  supabase: SupabaseClient,
  userId: string,
  readDate: string,
): Promise<DailyReadContext> {
  const lookbackDate = new Date();
  lookbackDate.setDate(lookbackDate.getDate() - TRAINING_LOG_LOOKBACK_DAYS);
  const memoLookbackDate = new Date();
  memoLookbackDate.setDate(memoLookbackDate.getDate() - VOICE_MEMO_LOOKBACK_DAYS);

  const settled = await Promise.allSettled([
    // 0. Training logs (recent ~60 days)
    supabase
      .from("training_logs")
      .select(
        "id, workout_date, created_at, workout_type, workout_distance_miles, workout_duration_minutes, workout_pace_per_mile, mood, cleaned_notes, notes, workout_notes",
      )
      .eq("user_id", userId)
      .gte("workout_date", lookbackDate.toISOString().slice(0, 10))
      .order("workout_date", { ascending: false, nullsFirst: false })
      .limit(MAX_TRAINING_LOGS),

    // 1. Latest weekly coaching report
    supabase
      .from("weekly_coaching_reports")
      .select("coaching_narrative, alerts, focus_areas, adjustments, week_start, metrics")
      .eq("user_id", userId)
      .eq("status", "completed")
      .order("week_start", { ascending: false })
      .limit(1),

    // 2. Active training plan / goal
    supabase
      .from("training_plans")
      .select("id, name, target_race_distance, target_time_seconds, start_date, end_date")
      .eq("user_id", userId)
      .eq("status", "active")
      .limit(1)
      .maybeSingle(),

    // 3. Coaching docs (generic top-N — RAG-by-recent-workout-type lands in v2)
    supabase
      .from("coaching_documents")
      .select("id, title, category, content")
      .order("created_at", { ascending: false })
      .limit(MAX_COACHING_DOCS),

    // 4. Race intel (most recent)
    supabase
      .from("race_intel")
      .select("race_name, race_date, location, course_data, weather_data, confidence")
      .eq("user_id", userId)
      .order("fetched_at", { ascending: false })
      .limit(1),

    // 5. Recent voice memos (training_logs with cleaned_notes in the last 14d)
    supabase
      .from("training_logs")
      .select("id, workout_date, created_at, cleaned_notes, mood")
      .eq("user_id", userId)
      .not("cleaned_notes", "is", null)
      .gte("created_at", memoLookbackDate.toISOString())
      .order("created_at", { ascending: false })
      .limit(MAX_VOICE_MEMOS),

    // 6. Active coach relationship — drives COACHED_MODE vs
    //    SELF_COACHED_MODE in the prompt when no training_plans row
    //    exists. We only need to know whether one exists; the coach's
    //    name/profile is loaded separately if we want to surface it.
    supabase
      .from("coach_athlete_relationships")
      .select("coach_user_id, status")
      .eq("athlete_user_id", userId)
      .eq("status", "active")
      .limit(1)
      .maybeSingle(),

    // 7. The most recent completed Read before today — so the coach
    //    doesn't ask the same question two days running and can carry
    //    a thread ("yesterday I said X").
    supabase
      .from("daily_coaching_reads")
      .select("read_date, headline, questions")
      .eq("user_id", userId)
      .eq("status", "completed")
      .lt("read_date", readDate)
      .order("read_date", { ascending: false })
      .limit(1)
      .maybeSingle(),
  ]);

  const extract = <T,>(idx: number, fallback: T): T => {
    const r = settled[idx];
    if (r.status !== "fulfilled") {
      console.warn(`daily-read: context query ${idx} failed:`, r.reason);
      return fallback;
    }
    // deno-lint-ignore no-explicit-any
    return ((r.value as any)?.data ?? fallback) as T;
  };

  // deno-lint-ignore no-explicit-any
  const logs = extract<any[]>(0, []);
  // deno-lint-ignore no-explicit-any
  const weeklyReports = extract<any[]>(1, []);
  // deno-lint-ignore no-explicit-any
  const activePlan = extract<any>(2, null);
  // deno-lint-ignore no-explicit-any
  const docs = extract<any[]>(3, []);
  // deno-lint-ignore no-explicit-any
  const raceIntel = extract<any[]>(4, []);
  // deno-lint-ignore no-explicit-any
  const memos = extract<any[]>(5, []);
  // deno-lint-ignore no-explicit-any
  const coachRel = extract<any>(6, null);
  // deno-lint-ignore no-explicit-any
  const previousRead = extract<any>(7, null);

  // Compute coaching mode — drives the editorial register in the
  // prompt. Three states:
  //   PLAN_MODE       — athlete has an active training_plans row.
  //                     License to compare execution against targets.
  //   COACHED_MODE    — athlete has an active coach but no uploaded
  //                     plan. Describe-only; defer training decisions
  //                     to the coach. The most-conservative register.
  //   SELF_COACHED_MODE — neither plan nor coach. Describe and respond
  //                       to whatever the athlete shares.
  const coachingMode: "PLAN_MODE" | "COACHED_MODE" | "SELF_COACHED_MODE" =
    activePlan
      ? "PLAN_MODE"
      : coachRel
        ? "COACHED_MODE"
        : "SELF_COACHED_MODE";

  // Athlete state — the canonical "who is this runner" snapshot.
  let athleteStateBlock = "";
  try {
    const state = await getOrBuildAthleteState(supabase, userId);
    athleteStateBlock = stateToPromptContext(state);
  } catch (err) {
    console.warn("daily-read: athlete-state build failed:", err);
  }

  const validWorkoutIds = new Set<string>(logs.map((l) => l.id as string));
  const validDocIds = new Set<string>(docs.map((d) => d.id as string));
  const validMemoLogIds = new Set<string>(memos.map((m) => m.id as string));

  // ── Render the context block the model reads ────────────────────
  const sections: string[] = [];

  // Coaching mode goes FIRST. The prompt's first read-through is this
  // line — it determines whether comparing against a target is on the
  // table for the rest of the Read.
  const modeNote =
    coachingMode === "PLAN_MODE"
      ? "PLAN_MODE — the athlete has an uploaded training plan with a goal race. You may compare execution against the plan's targets and name what the plan has scheduled. You still observe; the plan prescribes."
      : coachingMode === "COACHED_MODE"
        ? "COACHED_MODE — the athlete is working with a coach but the program is not in the app. Describe what's happening; hand training decisions to the coach. Do NOT invent target paces, race predictions, or upcoming-workout guidance."
        : "SELF_COACHED_MODE — no plan and no coach in the app. Describe what's happening. No invented targets. One or two soft questions.";
  sections.push(`## Coaching mode\n${modeNote}`);

  // Today — so "this week" / "yesterday" / "Sunday's long run" are
  // grounded on the athlete's calendar, not the server's.
  sections.push(`## Today\n${readDate} (${weekdayName(readDate)}). Weeks start Monday.`);

  if (athleteStateBlock) {
    sections.push(`## Athlete state (anchors and goals here are for YOUR reading only — never say them back to the athlete)\n${athleteStateBlock}`);
  }

  if (activePlan) {
    const targetSec = activePlan.target_time_seconds as number | null;
    const targetTime = targetSec ? formatHms(targetSec) : null;
    const planLine = [
      `${activePlan.name ?? "Active plan"}`,
      activePlan.target_race_distance ? `target: ${activePlan.target_race_distance}` : null,
      targetTime ? `goal time: ${targetTime}` : null,
      activePlan.end_date ? `race date: ${activePlan.end_date}` : null,
    ]
      .filter(Boolean)
      .join(" · ");
    sections.push(`## Goal race (silent — shapes what you notice, never spoken back)\n${planLine}`);
  }

  // Weekly running volume — pre-computed so the model can speak in
  // trend terms ("third week above 40") without summing 30 rows.
  // Running only: cross-training is a different kind of stress (Q23).
  const volume = weeklyRunningVolume(logs, readDate, 6);
  const hasAnyVolume = volume.some((w) => w.runs > 0);
  if (hasAnyVolume) {
    sections.push(
      `## Weekly running volume (most recent first; running only, cross-training excluded)\n${formatWeeklyVolume(volume)}`,
    );
  }

  if (logs.length > 0) {
    // Quality sessions get their own short list — the Read's story is
    // told through these, and a compact view with paces side by side
    // is how a coach would actually scan the block.
    const quality = logs
      .filter((l) => QUALITY_WORKOUT_TYPES.has(String(l.workout_type ?? "").toLowerCase()))
      .slice(0, 12)
      .map((l) => describeLog(l));
    if (quality.length > 0) {
      sections.push(
        `## Quality sessions (last ${TRAINING_LOG_LOOKBACK_DAYS} days — the story of the block; cite by the bracketed id)\n${quality.join("\n")}`,
      );
    }

    const lines = logs.slice(0, 30).map((l) => describeLog(l));
    sections.push(
      `## Recent runs (most recent first — cite by the bracketed id; ★ = quality, ✕ = not running)\n${lines.join("\n")}`,
    );
  } else {
    sections.push(
      `## Recent runs\nNo logged workouts in the last ${TRAINING_LOG_LOOKBACK_DAYS} days.`,
    );
  }

  if (memos.length > 0) {
    const lines = memos.map((m) => {
      const excerpt = String(m.cleaned_notes ?? "").slice(0, 240).replace(/\s+/g, " ").trim();
      const mood = m.mood ? ` · mood:${m.mood}` : "";
      return `- [${m.id}] ${m.created_at?.slice(0, 10)}${mood}: "${excerpt}"`;
    });
    sections.push(
      `## Recent voice memos (last ${VOICE_MEMO_LOOKBACK_DAYS} days). Read these for FEELING and LIFE CONTEXT — weather, sleep, stress, niggles. Paraphrase in the paragraph; never quote them back. A short verbatim excerpt may go in sources.memos only.\n${lines.join("\n")}`,
    );
  } else {
    sections.push(
      `## Recent voice memos\nNone in the last ${VOICE_MEMO_LOOKBACK_DAYS} days — skip the FEELING sentence and start with the work.`,
    );
  }

  if (previousRead) {
    const prevQs = Array.isArray(previousRead.questions)
      ? (previousRead.questions as unknown[]).map(String).filter((q) => q.trim().length > 0)
      : [];
    const parts = [`${previousRead.read_date}: "${previousRead.headline ?? ""}"`];
    if (prevQs.length > 0) {
      parts.push(`Questions asked then (ask something different today):\n${prevQs.map((q) => `- ${q}`).join("\n")}`);
    }
    sections.push(`## Your previous Read\n${parts.join("\n")}`);
  }

  if (weeklyReports.length > 0) {
    const r = weeklyReports[0];
    const parts: string[] = [`Week of ${r.week_start}.`];
    if (r.coaching_narrative) parts.push(String(r.coaching_narrative).slice(0, 800));
    const focus = Array.isArray(r.focus_areas) ? (r.focus_areas as string[]).join(", ") : null;
    if (focus) parts.push(`Focus: ${focus}.`);
    sections.push(`## Latest weekly report\n${parts.join("\n")}`);
  }

  if (docs.length > 0) {
    const lines = docs.map((d) => {
      const category = d.category ? ` (${d.category})` : "";
      return `- [${d.id}] ${d.title}${category}`;
    });
    sections.push(
      `## Knowledge docs (cite by the bracketed id when one grounds a claim)\n${lines.join("\n")}`,
    );
  }

  if (raceIntel.length > 0) {
    const r = raceIntel[0];
    const parts: string[] = [
      `${r.race_name}${r.race_date ? ` (${r.race_date})` : ""}${r.location ? ` — ${r.location}` : ""}`,
    ];
    const course = r.course_data as Record<string, unknown> | null;
    if (course?.course_description) parts.push(String(course.course_description));
    sections.push(`## Upcoming race intel\n${parts.join("\n")}`);
  }

  const contextBlock = sections.join("\n\n");
  return { contextBlock, validWorkoutIds, validDocIds, validMemoLogIds };
}

/** One training_log row as the bracketed-id line the prompt cites from. */
// deno-lint-ignore no-explicit-any
function describeLog(l: any): string {
  const dist = l.workout_distance_miles ? `${Number(l.workout_distance_miles).toFixed(1)}mi` : "—";
  const type = (l.workout_type ?? "run") as string;
  const pace = l.workout_pace_per_mile ? ` @ ${l.workout_pace_per_mile}/mi` : "";
  const dur = l.workout_duration_minutes ? ` (${l.workout_duration_minutes}m)` : "";
  const mood = l.mood ? ` · mood:${l.mood}` : "";
  const marker = QUALITY_WORKOUT_TYPES.has(type.toLowerCase())
    ? " ★"
    : isRunningType(type)
      ? ""
      : " ✕";
  const date = l.workout_date ?? l.created_at?.slice(0, 10);
  return `- [${l.id}] ${date} (${date ? weekdayName(String(date).slice(0, 10)).slice(0, 3) : "—"}) · ${type}${marker} · ${dist}${pace}${dur}${mood}`;
}

// ── Formatters ──────────────────────────────────────────────────────

function formatHms(sec: number): string {
  const total = Math.max(0, Math.round(sec));
  const h = Math.floor(total / 3600);
  const m = Math.floor((total % 3600) / 60);
  const s = total % 60;
  if (h > 0) {
    return `${h}:${m.toString().padStart(2, "0")}:${s.toString().padStart(2, "0")}`;
  }
  return `${m}:${s.toString().padStart(2, "0")}`;
}

function jsonResponse(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

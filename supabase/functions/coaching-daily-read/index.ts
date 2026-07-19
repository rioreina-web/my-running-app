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
import { captureException, flushSentry } from "../_shared/sentry.ts";
import { requireAuthOrServiceRole } from "../_shared/auth.ts";
import { enforceFeatureRateLimit, enforceMonthlyCap } from "../_shared/rateLimit.ts";
import { loadPrompt } from "../_shared/prompt-library.ts";
import { RESPONSE_SCHEMA } from "../_shared/prompts/daily-read.v5.ts";
import { getOrBuildAthleteState, stateToPromptContext } from "../_shared/athlete-state.ts";

// ── Types matching the daily_coaching_reads JSON columns ─────────────

// Legacy flat-paragraph segment (v1–v4 shape). v5 no longer asks the model
// for this; the function DERIVES it from `sections` so old consumers
// (iOS CoachReadView/ReadProse) keep rendering. See flattenSections().
type ParagraphSegment =
  | string
  | { workout_id: string }
  | { doc_id: string };

// v5 sectioned shape. A section body is an ordered array of plain prose
// strings and inline tap-through refs that carry their own display text.
type WorkoutRef = { text: string; workout_id: string };
type NiggleRef = { text: string; niggle: string };
type SectionSegment = string | WorkoutRef | NiggleRef;

interface ReadSection {
  label: string;
  body: SectionSegment[];
}

interface CantSee {
  eyebrow: string;
  body: string;
}

interface MemoSource {
  label: string;
  excerpt: string;
  log_id: string;
}

interface Sources {
  workouts: string[];
  docs: string[];
  memos: MemoSource[];
}

interface Confidence {
  level: "HIGH" | "MEDIUM" | "LOW";
  sub: string;
}

interface DailyReadPayload {
  headline: string;
  // v5 goal-backdrop scope line + sectioned narrative + single soft question.
  eyebrow: string | null;
  sections: ReadSection[];
  question: string | null;
  // Derived from `sections` for backward-compatible persistence (see
  // flattenSections); not emitted by the v5 model.
  paragraph: ParagraphSegment[];
  cant_see: CantSee | null;
  sources: Sources;
  confidence: Confidence;
}

interface RequestBody {
  user_id?: string;
  triggered_by?: "cron" | "manual" | "workout_trigger";
}

// ── Constants ────────────────────────────────────────────────────────

const MAX_TRAINING_LOGS = 60;          // ~2 months of daily training
const TRAINING_LOG_LOOKBACK_DAYS = 60;
const MAX_COACHING_DOCS = 8;
const MAX_VOICE_MEMOS = 12;
const VOICE_MEMO_LOOKBACK_DAYS = 60;   // widened from 14: real qualitative memory (sleep, travel, work, niggles) over a training block, not just two weeks
// Local override of router complex.maxTokens (2000). Flash thinking tokens
// share this budget; 2000 truncated the JSON mid-string (502s). See the
// generationConfig comment below — keep these two in sync if either changes.
const DAILY_READ_MAX_OUTPUT_TOKENS = 8000;

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
  const monthlyCapped = await enforceMonthlyCap(userId, "daily_read", corsHeaders, { isServiceRole });
  if (monthlyCapped) return monthlyCapped;

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
    const context = await buildDailyReadContext(supabase, userId);

    // ── 4. Call Gemini ───────────────────────────────────────────────
    // The Read runs its OWN frontier model, deliberately decoupled from the
    // shared cost-optimization router (_shared/router.ts). The router's job is
    // "cheapest model that works"; The Read is the flagship synthesis surface
    // and runs on a WEEKLY cadence, so per-call cost is small and reasoning
    // quality matters most. Gemini 3 Pro (gemini-3.1-pro-preview) for
    // coach-grade synthesis over the full quant + qualitative context bundle.
    // Same GEMINI_API_KEY / generativelanguage endpoint already used here.
    const modelConfig = {
      model: "gemini-3.1-pro-preview",
      provider: "gemini" as const,
      baseUrl: "https://generativelanguage.googleapis.com/v1beta",
      apiKeyEnv: "GEMINI_API_KEY",
      maxTokens: DAILY_READ_MAX_OUTPUT_TOKENS,
      costPer1kTokens: 0, // not used for billing here
    };
    const apiKey = Deno.env.get(modelConfig.apiKeyEnv);
    if (!apiKey) {
      await markFailed(supabase, pending.id, `${modelConfig.apiKeyEnv} not configured`);
      return jsonResponse(500, {
        error: `${modelConfig.apiKeyEnv} not configured`,
      });
    }

    const systemPrompt = loadPrompt("daily-read.v5", {});
    const fullPrompt = `${systemPrompt}\n\n${context.contextBlock}\n\nGenerate today's Read for this athlete.`;

    const modelId = modelConfig.model;
    const genAI = new GoogleGenerativeAI(apiKey);

    // Generate one Read candidate. Schema-constrained when requested; the
    // schema-less path is the fallback for models that reject `anyOf`.
    const generateRaw = async (useSchema: boolean): Promise<string> => {
      const model = genAI.getGenerativeModel({
        model: modelConfig.model,
        generationConfig: {
          // Generous, NAMED output budget. Gemini-3 Pro spends "thinking"
          // tokens out of this same budget; a tight cap consumed it and the
          // JSON truncated mid-string ("Unterminated string in JSON") →
          // repeated 502s. The v4 spine also produces a longer structured
          // read. Keep this LOCAL and named so a future "tidy" can't silently
          // reintroduce the truncation by lowering it.
          maxOutputTokens: DAILY_READ_MAX_OUTPUT_TOKENS,
          temperature: 0.6,
          responseMimeType: "application/json",
          // deno-lint-ignore no-explicit-any
          ...(useSchema ? { responseSchema: RESPONSE_SCHEMA as any } : {}),
        },
      });
      const result = await model.generateContent(fullPrompt);
      return result.response.text();
    };

    // ── 4b/5. Generate + parse with bounded retries ──────────────────
    // The model occasionally emits an unescaped character (e.g. a stray
    // quote in a pace) that breaks JSON.parse. A re-roll at temperature
    // 0.6 almost always clears it, so we try up to MAX_ATTEMPTS times —
    // schema first, then schema-less re-rolls — before giving up.
    const MAX_ATTEMPTS = 3;
    let parsed: DailyReadPayload | null = null;
    let lastErr = "";
    let lastRaw = "";
    for (let attempt = 0; attempt < MAX_ATTEMPTS && parsed === null; attempt++) {
      try {
        const raw = await generateRaw(attempt === 0);
        lastRaw = raw;
        parsed = parseModelResponse(raw);
      } catch (err) {
        lastErr = err instanceof Error ? err.message : String(err);
        console.warn(
          `daily-read: generate/parse attempt ${attempt + 1}/${MAX_ATTEMPTS} failed: ${lastErr}`,
        );
      }
    }
    if (parsed === null) {
      // DIAGNOSTIC: capture the raw model output so we can see exactly
      // what broke the parse. Remove once the root cause is fixed.
      await markFailed(
        supabase,
        pending.id,
        `Parse failed after ${MAX_ATTEMPTS} attempts: ${lastErr} :: RAW=${lastRaw.slice(0, 1500)}`,
      );
      return jsonResponse(502, { error: "Model returned unparseable JSON" });
    }

    // ── 6. Validate + strip invalid citations ────────────────────────
    const validated = validateCitations(parsed, context);

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
    captureException(err, { fn: "coaching-daily-read" });
    await flushSentry();
    // Best-effort failure marker; if we don't have a pending row id we
    // just log. The next cron tick will retry.
    return jsonResponse(500, { error: "Internal error", detail: message });
  }
});

// ── Date resolution ──────────────────────────────────────────────────

/**
 * Resolve today's date in the athlete's local timezone. Reads
 * `athlete_settings.timezone` (e.g. "America/Los_Angeles"); falls back to
 * UTC if missing. (Was `user_profiles.timezone` — repointed 2026-06-15 to
 * the SETTINGS surface; user_profiles never shipped to prod.)
 */
async function resolveAthleteLocalDate(
  supabase: SupabaseClient,
  userId: string,
): Promise<string> {
  const { data } = await supabase
    .from("athlete_settings")
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
  eyebrow: string | null;
  sections: ReadSection[] | null;
  question: string | null;
  paragraph: ParagraphSegment[];
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
  const { data, error } = await supabase
    .from("daily_coaching_reads")
    .update({
      status: "completed",
      headline: payload.headline,
      // v5 sectioned fields (the narrative screen reads these).
      eyebrow: payload.eyebrow,
      sections: payload.sections,
      question: payload.question,
      // Flattened legacy paragraph, derived from sections, so pre-v5
      // consumers (iOS CoachReadView / ReadProse) keep rendering.
      paragraph: payload.paragraph,
      cant_see: payload.cant_see,
      sources: payload.sources,
      confidence: payload.confidence,
      ai_model: aiModel,
      generated_at: new Date().toISOString(),
      error_message: null,
    })
    .eq("id", rowId)
    .select("*")
    .single();
  if (error) {
    console.error("daily-read: mark completed failed:", error.message);
    return null;
  }
  return data as DailyReadRow;
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
  /**
   * Acceptable niggle ref strings (lowercased), built from `body_mentions`.
   * Holds both the bare body area ("achilles") and the sided form
   * ("right achilles") so a `{text, niggle}` ref resolves to a real timeline.
   */
  validNiggles: Set<string>;
}

async function buildDailyReadContext(
  supabase: SupabaseClient,
  userId: string,
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

    // 7. Body mentions (niggles) — the closed-vocab body areas this athlete
    //    has actually mentioned. Used to validate v5 {text, niggle} refs so a
    //    tappable niggle phrase always resolves to a real recurrence timeline.
    supabase
      .from("body_mentions")
      .select("body_area, side")
      .eq("user_id", userId),
  ]);

  // deno-lint-ignore no-explicit-any
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
  const bodyMentions = extract<any[]>(7, []);

  // Compute coaching mode — drives the editorial register in the v2
  // prompt. Three states:
  //   PLAN_MODE       — athlete has an active training_plans row.
  //                     License to evaluate execution against targets.
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

  // Acceptable niggle ref strings: the bare body area and the sided form,
  // both lowercased. A {text, niggle} ref that matches either resolves to a
  // real per-body-part timeline; anything else is stripped to plain text.
  const validNiggles = new Set<string>();
  for (const m of bodyMentions) {
    const area = String(m.body_area ?? "").trim().toLowerCase();
    if (!area) continue;
    validNiggles.add(area);
    const side = String(m.side ?? "").trim().toLowerCase();
    if (side) validNiggles.add(`${side} ${area}`);
  }

  // ── Render the context block the model reads ────────────────────
  const sections: string[] = [];

  // Coaching mode goes FIRST. The v2 prompt's first read-through is
  // this line — it determines whether prescriptive language is on
  // the table for the rest of the Read.
  const modeNote =
    coachingMode === "PLAN_MODE"
      ? "PLAN_MODE — the athlete has an uploaded training plan with a goal race. Evaluate execution against the plan. Prescriptive language is allowed."
      : coachingMode === "COACHED_MODE"
        ? "COACHED_MODE — the athlete is working with a coach but the program is not in the app. Describe what's happening; defer training decisions to the coach. Do NOT invent target paces, race predictions, or upcoming-workout guidance."
        : "SELF_COACHED_MODE — no plan and no coach in the app. Describe what's happening; one good question per Read at most. No invented targets.";
  sections.push(`## Coaching mode\n${modeNote}`);

  if (athleteStateBlock) {
    sections.push(`## Athlete state\n${athleteStateBlock}`);
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
    sections.push(`## Goal race\n${planLine}`);
  }

  if (logs.length > 0) {
    // Citation key ONLY — distance/date/quality are the reliable facts here.
    // The raw workout_type and workout_pace_per_mile columns are the source
    // of the wrong "tempo @ 7:30/mi" prose, so they are deliberately NOT
    // rendered: the model reads pace/type/quality from the ATHLETE STATE
    // "Recent runs" section (parsed work pace + structure). See
    // outputs/coach-read-effectiveness-plan-2026-06-12.md.
    const lines = logs.slice(0, 30).map((l) => {
      const dist = l.workout_distance_miles ? `${Number(l.workout_distance_miles).toFixed(1)}mi` : "—";
      const dur = l.workout_duration_minutes ? ` (${l.workout_duration_minutes}m)` : "";
      const type = (l.workout_type ?? "run") as string;
      const quality = QUALITY_WORKOUT_TYPES.has(type.toLowerCase()) ? " ★quality" : "";
      const date = (l.workout_date ?? l.created_at?.slice(0, 10)) as string;
      return `- [${l.id}] ${date} · ${dist}${dur}${quality}`;
    });
    sections.push(
      `## Citable workouts (cite by the bracketed id ONLY — read pace, type, and quality from the ATHLETE STATE "Recent runs" section, which carries the parsed work pace and structure; the raw label/pace are unreliable)\n${lines.join("\n")}`,
    );
  } else {
    sections.push(
      `## Citable workouts\nNo logged workouts in the last ${TRAINING_LOG_LOOKBACK_DAYS} days.`,
    );
  }

  if (memos.length > 0) {
    const lines = memos.map((m) => {
      const excerpt = String(m.cleaned_notes ?? "").slice(0, 200).replace(/\s+/g, " ").trim();
      const mood = m.mood ? ` · mood:${m.mood}` : "";
      return `- [${m.id}] ${m.created_at?.slice(0, 10)}${mood}: "${excerpt}"`;
    });
    sections.push(
      `## Recent voice memos (last ${VOICE_MEMO_LOOKBACK_DAYS} days — surface in sources.memos only, never cite inline)\n${lines.join("\n")}`,
    );
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
  return { contextBlock, validWorkoutIds, validDocIds, validMemoLogIds, validNiggles };
}

// ── Model output parsing & validation ────────────────────────────────

function parseModelResponse(raw: string): DailyReadPayload {
  // Models sometimes wrap JSON in ```json fences despite responseMimeType.
  const cleaned = raw
    .trim()
    .replace(/^```json\s*/i, "")
    .replace(/^```\s*/i, "")
    .replace(/```\s*$/i, "")
    .trim();
  const obj = JSON.parse(cleaned) as Partial<DailyReadPayload>;

  if (typeof obj.headline !== "string") {
    throw new Error("Missing or invalid headline");
  }
  if (!Array.isArray(obj.sections)) {
    throw new Error("Missing or invalid sections array");
  }
  if (!obj.sources || typeof obj.sources !== "object") {
    throw new Error("Missing sources object");
  }
  if (!obj.confidence || typeof obj.confidence !== "object") {
    throw new Error("Missing confidence object");
  }

  // Keep only well-formed sections ({ label:string, body:array }). The
  // validator strips bad segments inside the body; here we just guard shape.
  const sections: ReadSection[] = (obj.sections as ReadSection[])
    .filter(
      (s) => s && typeof s === "object" &&
        typeof s.label === "string" && Array.isArray(s.body),
    )
    .map((s) => ({ label: s.label, body: s.body as SectionSegment[] }));
  if (sections.length === 0) {
    throw new Error("sections array has no well-formed section");
  }

  return {
    headline: obj.headline,
    eyebrow: typeof obj.eyebrow === "string" ? obj.eyebrow : null,
    sections,
    question: typeof obj.question === "string" ? obj.question : null,
    // Derived from sections during validation; the model does not emit it.
    paragraph: [],
    cant_see: (obj.cant_see ?? null) as CantSee | null,
    sources: {
      workouts: Array.isArray(obj.sources.workouts) ? obj.sources.workouts : [],
      docs: Array.isArray(obj.sources.docs) ? obj.sources.docs : [],
      memos: Array.isArray(obj.sources.memos) ? obj.sources.memos : [],
    },
    confidence: {
      level: (obj.confidence.level ?? "LOW") as Confidence["level"],
      sub: typeof obj.confidence.sub === "string" ? obj.confidence.sub : "",
    },
  };
}

/**
 * Sanitize a v5 payload:
 *   - Walk every section body. A workout ref with an unknown id, or a niggle
 *     ref whose body-part doesn't resolve in `body_mentions`, DEGRADES to its
 *     plain display `text` (never a dead link, never a dropped phrase).
 *   - Rebuild `sources` against known ids/memos and echo referenced workouts.
 *   - Derive the legacy flat `paragraph` from the cleaned sections so pre-v5
 *     consumers keep rendering.
 * Emits one console.warn per degraded ref.
 */
function validateCitations(
  payload: DailyReadPayload,
  ctx: DailyReadContext,
): DailyReadPayload {
  let degradedWorkouts = 0;
  let degradedNiggles = 0;
  const referencedWorkoutIds: string[] = [];

  const cleanedSections: ReadSection[] = payload.sections.map((section) => {
    const body: SectionSegment[] = [];
    for (const seg of section.body) {
      if (typeof seg === "string") {
        body.push(seg);
        continue;
      }
      if (seg && typeof seg === "object" && "workout_id" in seg) {
        const ref = seg as WorkoutRef;
        if (typeof ref.text === "string" && ctx.validWorkoutIds.has(ref.workout_id)) {
          body.push({ text: ref.text, workout_id: ref.workout_id });
          referencedWorkoutIds.push(ref.workout_id);
        } else {
          if (typeof ref.text === "string" && ref.text.length > 0) body.push(ref.text);
          degradedWorkouts++;
        }
        continue;
      }
      if (seg && typeof seg === "object" && "niggle" in seg) {
        const ref = seg as NiggleRef;
        const key = String(ref.niggle ?? "").trim().toLowerCase();
        if (typeof ref.text === "string" && key && ctx.validNiggles.has(key)) {
          body.push({ text: ref.text, niggle: ref.niggle });
        } else {
          if (typeof ref.text === "string" && ref.text.length > 0) body.push(ref.text);
          degradedNiggles++;
        }
        continue;
      }
      // Unknown segment shape — drop quietly. The prompt forbids anything
      // other than a string, a workout ref, or a niggle ref.
    }
    return { label: section.label, body };
  });

  if (degradedWorkouts > 0) {
    console.warn(
      `daily-read: degraded ${degradedWorkouts} invalid workout ref(s) to plain text`,
    );
  }
  if (degradedNiggles > 0) {
    console.warn(
      `daily-read: degraded ${degradedNiggles} unresolved niggle ref(s) to plain text`,
    );
  }

  // Filter sources to known ids, and dedupe.
  const sources: Sources = {
    workouts: dedupe(payload.sources.workouts.filter((id) => ctx.validWorkoutIds.has(id))),
    docs: dedupe(payload.sources.docs.filter((id) => ctx.validDocIds.has(id))),
    memos: payload.sources.memos
      .filter((m) => m && typeof m === "object" && ctx.validMemoLogIds.has(m.log_id))
      .map((m) => ({
        label: String(m.label ?? "").slice(0, 80),
        excerpt: String(m.excerpt ?? "").slice(0, 400),
        log_id: m.log_id,
      })),
  };

  // Echo every workout actually referenced in the body — structured-output
  // models often omit the sources mirror.
  for (const id of referencedWorkoutIds) {
    if (!sources.workouts.includes(id)) sources.workouts.push(id);
  }

  return {
    headline: payload.headline.trim(),
    eyebrow: payload.eyebrow,
    sections: cleanedSections,
    question: payload.question,
    paragraph: flattenSections(cleanedSections),
    cant_see: payload.cant_see,
    sources,
    confidence: payload.confidence,
  };
}

/**
 * Flatten cleaned v5 sections into the legacy `paragraph` segment array
 * (string | {workout_id} | {doc_id}) so pre-v5 readers (iOS CoachReadView /
 * ReadProse) still render a coherent Read. A workout ref becomes its prose
 * `text` followed by a legacy {workout_id} chip; a niggle ref becomes its
 * prose `text` (legacy has no niggle chip). Sections are concatenated in
 * order; a blank string between sections preserves paragraph breaks.
 */
function flattenSections(sections: ReadSection[]): ParagraphSegment[] {
  const out: ParagraphSegment[] = [];
  sections.forEach((section, i) => {
    if (i > 0) out.push(""); // paragraph break between sections
    for (const seg of section.body) {
      if (typeof seg === "string") {
        out.push(seg);
      } else if ("workout_id" in seg) {
        if (seg.text) out.push(seg.text);
        out.push({ workout_id: seg.workout_id });
      } else if ("niggle" in seg) {
        if (seg.text) out.push(seg.text);
      }
    }
  });
  return out;
}

function dedupe<T>(arr: T[]): T[] {
  return Array.from(new Set(arr));
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

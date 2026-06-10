/**
 * Multi-Model Coaching Agent
 *
 * Intelligent routing for optimal quality and cost:
 * - Simple queries → Groq Llama 8B (fast, $0.05/1M tokens)
 * - Moderate queries → Gemini Flash (balanced, $0.60/1M tokens)
 * - Complex queries → Gemini Flash + extended context
 *
 * Architecture:
 * 1. Semantic Cache - 35% hit rate expected
 * 2. Rate Limiter - 5 free / 25 pro per day
 * 3. Query Classifier - Routes to optimal model
 * 4. Context Compression - 90% token reduction
 *
 * Projected cost: ~$200-400/month at 50k DAU
 */

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { GoogleGenerativeAI } from "https://esm.sh/@google/generative-ai@0.21.0";
import { validateLength, validateUUID, validationErrorResponse, internalErrorResponse } from "../_shared/validation.ts";

// Import shared modules
import { getCachedResponse, cacheResponse, isCacheEnabled } from "../_shared/cache.ts";
import { checkFeatureRateLimit, isRateLimitEnabled } from "../_shared/rateLimit.ts";
import {
  classifyQuery,
  getBestAvailableModel,
  getModelConfig,
  getModelIdentifier,
  noteTruncationIfCapped,
  type RouterConfig,
  type QueryComplexity,
} from "../_shared/router.ts";
import {
  compressTrainingContext,
  compressGoalsContext,
  compressConversationHistory,
  estimateTokens,
  isTrainingRelatedQuery,
  isThisWeekQuery,
  buildTrainingPeriodDocument,
  buildThisWeekContext,
  assembleWithBudget,
  COMPLEXITY_CONTEXT_BUDGETS,
  type ExtendedTrainingLog,
  type PromptBlock,
} from "../_shared/context.ts";
import {
  isComplexQuery,
  getQueryType,
  getQueryThreshold,
  detectTargetDistance,
  getOrCreateProfile,
  getMissingData,
  generateClarifyingQuestions,
  buildClarifyingPrompt,
  extractProfileData,
  updateProfile,
  buildProfileContext,
} from "../_shared/profile.ts";
import {
  extractMemories,
  storeMemories,
  getMemories,
  buildMemoryContext,
} from "../_shared/memory.ts";
import { getActiveInjuries, buildInjuryContext } from "../_shared/injuries.ts";
import {
  analyzeTrainingData,
  splitLogsIntoWeeks,
  getCurrentWeekMonday,
  type FitnessSnapshot,
  type FormCheckResult,
} from "../_shared/dataAnalysis.ts";
import {
  type TrainingLogRow,
  type ScheduledWorkoutRow,
  type InjuryRow,
} from "../_shared/weeklyAnalytics.ts";

import { getAuthenticatedUser, unauthorizedResponse } from "../_shared/auth.ts";
import { buildAthleteProfileContext, type AthleteProfile } from "../_shared/athleteProfile.ts";
import { getOrBuildAthleteState, stateToPromptContext } from "../_shared/athlete-state.ts";

import { corsHeaders } from "../_shared/cors.ts";
import { loadPrompt } from "../_shared/prompt-library.ts";

// System prompts live in `_shared/prompts/coaching-agent-{simple,moderate,
// complex,proactive}.v1.ts`. Migrated from inline `SYSTEM_PROMPTS` /
// `VOICE_RULES` / `ANALYSIS_FRAMEWORK` on 2026-05-18 (W2.1 Day 2) — the
// migration is the prerequisite for cassette-based eval coverage of the
// coaching-agent surface. Load via `loadPrompt(name, {})`.
interface ChatMessage {
  role: "user" | "assistant";
  content: string;
  timestamp: string;
}

/**
 * Detect runner experience level from profile data and memories.
 * Returns "beginner", "intermediate", or "advanced" with coaching tone adjustments.
 */
function detectRunnerLevel(
  profileData: any,
  memories: string,
  weeklyMileage?: number
): { level: string; promptAdjustment: string } {
  let level = "intermediate"; // default

  // Check profile for experience
  const yearsRunning = profileData?.years_running || profileData?.running_experience_years;
  const totalRaces = profileData?.total_races || 0;

  if (yearsRunning !== undefined) {
    if (yearsRunning < 1) level = "beginner";
    else if (yearsRunning >= 5 || totalRaces >= 10) level = "advanced";
  }

  // Check memories for experience hints
  if (memories) {
    const m = memories.toLowerCase();
    if (/experience:\s*\d+\s*months?/i.test(m) || /new to running|just started|beginner/i.test(m)) {
      level = "beginner";
    } else if (/experience:\s*([5-9]|\d{2,})\s*years?/i.test(m) || /marathon pr.*?[23]:/i.test(m)) {
      level = "advanced";
    }
  }

  // Weekly mileage as a signal
  if (weeklyMileage !== undefined) {
    if (weeklyMileage < 15 && level !== "advanced") level = "beginner";
    else if (weeklyMileage >= 50) level = "advanced";
  }

  const adjustments: Record<string, string> = {
    beginner: `\nRUNNER LEVEL: Beginner
- Explain concepts simply. Don't assume they know training terms (tempo, fartlek, strides, etc.) — define them briefly when you use them.
- Prioritize consistency and enjoyment over performance. Building the habit matters most.
- Be encouraging but honest. Help them avoid doing too much too soon.
- Suggest walk breaks and recovery days proactively — beginners often skip rest.`,

    intermediate: `\nRUNNER LEVEL: Intermediate
- They know the basics. Skip basic definitions unless asked.
- Focus on progression: what's the next step to improve?
- Challenge them when appropriate — they can handle harder workouts.`,

    advanced: `\nRUNNER LEVEL: Advanced
- Respect their knowledge. Don't explain basics or well-known concepts.
- Be precise with paces, volumes, and periodization details.
- Focus on marginal gains: small tweaks that make a difference at their level.
- They can handle direct, blunt feedback. Don't soften unnecessarily.`,
  };

  return { level, promptAdjustment: adjustments[level] || "" };
}

/**
 * Infer training periodization phase from plan dates.
 * Divides the plan into 4 phases: Base (40%), Build (30%), Peak (20%), Taper (10%)
 */
function inferTrainingPhase(plan: { start_date: string; end_date: string; target_race_distance?: string }): string {
  const start = new Date(plan.start_date).getTime();
  const end = new Date(plan.end_date).getTime();
  const now = Date.now();
  const totalDuration = end - start;

  if (totalDuration <= 0 || now < start) return "";
  if (now > end) return "\nTRAINING CONTEXT: Plan has ended. Focus on recovery and what's next.";

  const daysToRace = Math.ceil((end - now) / (1000 * 60 * 60 * 24));
  const race = plan.target_race_distance || "goal";

  // Don't prescribe rigid phases. Just give the coach awareness of where we are
  // relative to the goal. The coach's philosophy handles the rest.
  let context = `\nTRAINING CONTEXT: ${daysToRace} days to ${race}.`;

  if (daysToRace <= 14) {
    context += `\n- Race is imminent. Prioritize freshness — reduce volume, keep a few short sharp efforts. Trust the work that's been done.`;
  } else if (daysToRace <= 42) {
    context += `\n- Final 6 weeks. Key race-specific workouts should be the focus. Build toward 2-3 sessions that simulate race demands. Protect recovery around these sessions.`;
  } else {
    context += `\n- Still building. Focus on aerobic support, moderate development, and progressive adaptation. Harder, more specific efforts come later in the block.`;
  }

  return context;
}

// ============================================================================
// PLAN AWARENESS — "what was planned, what happened, what's next"
// ============================================================================

/**
 * Build a prompt context block that gives the coach situational awareness of
 * the training plan: this week's scheduled workouts, recent plan-vs-actual
 * deltas (pace, distance, RPE), and what's coming up next.
 */
function buildPlanAwarenessContext(
  plan: { id: string; name: string; start_date: string; end_date: string; target_race_distance?: string; target_time_seconds?: number; status: string },
  thisWeekScheduled: any[],
  last7DaysScheduled: any[],
  trainingLogs: any[]
): string {
  if (!plan) return "";

  const parts: string[] = [];
  const today = new Date().toISOString().split("T")[0];
  const dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

  // ── Section 1: This week's plan ──
  const nonRestThisWeek = thisWeekScheduled.filter((w: any) => w.workout_type !== "rest");
  if (nonRestThisWeek.length > 0) {
    parts.push("THIS WEEK'S PLAN:");
    for (const w of thisWeekScheduled) {
      const d = new Date(w.date + "T12:00:00Z");
      const dayName = dayNames[d.getUTCDay()];
      const isPast = w.date < today;
      const isToday = w.date === today;

      let line = `- ${dayName} ${w.date.slice(5)}`;
      if (w.workout_type === "rest") {
        line += ": Rest";
      } else {
        const wd = w.workout_data as Record<string, any> | null;
        const name = wd?.name || w.workout_type.replace(/_/g, " ");
        line += `: ${name}`;
        if (wd?.total_distance_km) {
          line += ` (${(wd.total_distance_km / 1.60934).toFixed(1)}mi)`;
        } else if (wd?.total_distance_mi) {
          line += ` (${wd.total_distance_mi}mi)`;
        }
        if (wd?.target_pace) line += ` @ ${wd.target_pace}`;

        // Weather forecast for future/today workouts
        const wf = w.weather_forecast as Record<string, any> | null;
        if (wf && !isPast) {
          const heat = wf.heat_category as string;
          line += ` [${Math.round(wf.temp_f)}°F dp${Math.round(wf.dew_point_f)}°F`;
          if (heat && heat !== "ideal") line += ` ${heat.toUpperCase()}`;
          if (wf.adjustment_pct && wf.adjustment_pct > 0) {
            const adjSec = wd?.target_pace ? Math.round(parsePaceToSeconds(wd.target_pace) * wf.adjustment_pct) : 0;
            if (adjSec > 0) line += ` +${adjSec}s/mi adj`;
          }
          line += "]";
        }
      }

      // Status indicator
      if (w.status === "completed") line += " ✓";
      else if (w.status === "skipped") line += " [skipped]";
      else if (isToday) line += " ← TODAY";
      else if (isPast && w.status === "scheduled") line += " [missed]";

      parts.push(line);
    }
  }

  // ── Section 2: Last 7 days — plan vs actual ──
  const completedScheduled = last7DaysScheduled.filter(
    (w: any) => w.status === "completed" && w.workout_type !== "rest"
  );

  if (completedScheduled.length > 0 && trainingLogs.length > 0) {
    const deltas: string[] = [];

    for (const scheduled of completedScheduled) {
      const wd = scheduled.workout_data as Record<string, any> | null;
      if (!wd) continue;

      // Find matching training log by date
      const matchingLog = trainingLogs.find(
        (log: any) => log.workout_date && log.workout_date.startsWith(scheduled.date)
      );
      if (!matchingLog) continue;

      const workoutName = wd.name || scheduled.workout_type.replace(/_/g, " ");
      const d = new Date(scheduled.date + "T12:00:00Z");
      const dayName = dayNames[d.getUTCDay()];
      let deltaLine = `- ${dayName}: ${workoutName}`;

      const deltaDetails: string[] = [];

      // Distance delta
      const plannedMi = wd.total_distance_km
        ? wd.total_distance_km / 1.60934
        : wd.total_distance_mi || 0;
      const actualMi = matchingLog.workout_distance_miles || 0;
      if (plannedMi > 0 && actualMi > 0) {
        const distDelta = actualMi - plannedMi;
        if (Math.abs(distDelta) >= 0.3) {
          const sign = distDelta > 0 ? "+" : "";
          deltaDetails.push(`dist ${sign}${distDelta.toFixed(1)}mi`);
        }
      }

      // Pace delta — compare actual pace to target
      const targetPaceStr = wd.target_pace as string | undefined;
      const actualPaceStr = matchingLog.workout_pace_per_mile as string | undefined;
      if (targetPaceStr && actualPaceStr) {
        const targetSec = parsePaceToSeconds(targetPaceStr);
        const actualSec = parsePaceToSeconds(actualPaceStr);
        if (targetSec > 0 && actualSec > 0) {
          const paceDelta = actualSec - targetSec;
          if (Math.abs(paceDelta) >= 5) {
            // In running: negative delta = faster than planned
            const fasterSlower = paceDelta < 0 ? "faster" : "slower";
            const absDelta = Math.abs(paceDelta);
            const formatted = absDelta >= 60
              ? `${Math.floor(absDelta / 60)}:${String(absDelta % 60).padStart(2, "0")}`
              : `${absDelta}s`;
            deltaDetails.push(`${formatted} ${fasterSlower} than target`);
          }
        }
      }

      // Weather-adjusted pace (the real story — did they hit the effort-equivalent target?)
      const weatherAdj = matchingLog.weather_adjusted_pace_delta_seconds_per_mile as number | null;
      if (weatherAdj && weatherAdj > 2 && targetPaceStr && actualPaceStr) {
        const targetSec2 = parsePaceToSeconds(targetPaceStr);
        const actualSec2 = parsePaceToSeconds(actualPaceStr);
        if (targetSec2 > 0 && actualSec2 > 0) {
          const adjustedTarget = targetSec2 + weatherAdj;
          const adjDelta = actualSec2 - adjustedTarget;
          if (Math.abs(adjDelta) < 5) {
            deltaDetails.push(`(heat-adjusted: ON TARGET)`);
          } else {
            const adjDir = adjDelta < 0 ? "faster" : "slower";
            const adjAbs = Math.abs(Math.round(adjDelta));
            deltaDetails.push(`(heat-adjusted: ${adjAbs}s ${adjDir})`);
          }
        }
      }

      // Weather conditions if available
      const wa = matchingLog.weather_actual as Record<string, any> | null;
      if (wa?.heat_category && wa.heat_category !== "ideal") {
        deltaDetails.push(`${Math.round(wa.temp_f)}°F ${wa.heat_category}`);
      }

      // RPE / mood
      if (matchingLog.mood) {
        deltaDetails.push(`felt: ${matchingLog.mood}`);
      }

      if (deltaDetails.length > 0) {
        deltaLine += ` → ${deltaDetails.join(", ")}`;
        deltas.push(deltaLine);
      }
    }

    if (deltas.length > 0) {
      parts.push("");
      parts.push("PLAN VS ACTUAL (last 7 days):");
      parts.push(...deltas);
    }
  }

  // ── Section 3: What's next (upcoming non-rest workouts) ──
  const upcoming = thisWeekScheduled.filter(
    (w: any) => w.date >= today && w.status === "scheduled" && w.workout_type !== "rest"
  );
  if (upcoming.length > 0) {
    parts.push("");
    parts.push("UPCOMING:");
    for (const w of upcoming.slice(0, 3)) {
      const d = new Date(w.date + "T12:00:00Z");
      const dayName = dayNames[d.getUTCDay()];
      const wd = w.workout_data as Record<string, any> | null;
      const name = wd?.name || w.workout_type.replace(/_/g, " ");
      let line = `- ${dayName}: ${name}`;
      if (wd?.description) line += ` — ${(wd.description as string).slice(0, 100)}`;
      parts.push(line);
    }
  }

  if (parts.length === 0) return "";
  return "\n\nTraining Plan Awareness (" + plan.name + "):\n" + parts.join("\n");
}

/**
 * Parse a pace string like "7:30" or "7:30/mi" into total seconds.
 */
function parsePaceToSeconds(pace: string): number {
  const cleaned = pace.replace(/\/mi|\/km/g, "").trim();
  const parts = cleaned.split(":").map(Number);
  if (parts.length === 2 && !isNaN(parts[0]) && !isNaN(parts[1])) {
    return parts[0] * 60 + parts[1];
  }
  return 0;
}

// ============================================================================
// MODEL CALL HANDLERS
// ============================================================================

/**
 * Run a promise with a timeout. Rejects with a TimeoutError if the promise
 * doesn't resolve within `ms` milliseconds.
 */
async function withTimeout<T>(promise: Promise<T>, ms: number, label: string): Promise<T> {
  // ReturnType<typeof setTimeout> — the Gemini SDK pulls @types/node into
  // the graph, which retypes global setTimeout to return Timeout, not number.
  let timer: ReturnType<typeof setTimeout> | undefined;
  const timeout = new Promise<never>((_, reject) => {
    timer = setTimeout(() => reject(new Error(`${label} timed out after ${ms}ms`)), ms);
  });
  try {
    return await Promise.race([promise, timeout]);
  } finally {
    clearTimeout(timer);
  }
}

const MODEL_TIMEOUT_MS = 20_000; // 20 seconds per model call

/**
 * Call Groq API (OpenAI-compatible) with timeout protection
 */
async function callGroq(
  prompt: string,
  config: RouterConfig
): Promise<string> {
  const apiKey = Deno.env.get("GROQ_API_KEY");
  if (!apiKey) throw new Error("GROQ_API_KEY not configured");

  const response = await withTimeout(
    fetch(`${config.baseUrl}/chat/completions`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: config.model,
        messages: [{ role: "user", content: prompt }],
        max_tokens: config.maxTokens,
        temperature: 0.7,
      }),
    }),
    MODEL_TIMEOUT_MS,
    "Groq"
  );

  if (!response.ok) {
    const errorText = await response.text();
    console.error(`Groq API error: ${response.status}`, errorText);
    throw new Error(`Groq API error: ${response.status}`);
  }

  const data = await response.json();
  noteTruncationIfCapped(data.choices?.[0]?.finish_reason, {
    fn: "coaching-agent",
    complexity: `${config.model}:${config.maxTokens}tok`,
  });
  return data.choices[0].message.content;
}

/**
 * Call Gemini API with timeout protection
 */
async function callGemini(
  prompt: string,
  config: RouterConfig
): Promise<string> {
  const apiKey = Deno.env.get("GEMINI_API_KEY");
  if (!apiKey) throw new Error("GEMINI_API_KEY not configured");

  const genAI = new GoogleGenerativeAI(apiKey);
  const model = genAI.getGenerativeModel({
    model: config.model,
    generationConfig: {
      maxOutputTokens: config.maxTokens,
      temperature: 0.7,
      // Cap thinking tokens — 2.5 Flash's internal reasoning can eat the whole
      // output budget and truncate the actual coaching response mid-sentence.
      // The SDK's GenerationConfig type lags the API; the field is real.
      thinkingConfig: { thinkingBudget: 512 },
      // deno-lint-ignore no-explicit-any
    } as any,
  });

  const result = await withTimeout(
    model.generateContent(prompt),
    MODEL_TIMEOUT_MS,
    "Gemini"
  );
  noteTruncationIfCapped(result.response.candidates?.[0]?.finishReason, {
    fn: "coaching-agent",
    complexity: `${config.model}:${config.maxTokens}tok`,
  });
  return result.response.text();
}

// ============================================================================
// MAIN HANDLER
// ============================================================================

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const startTime = Date.now();
  // DEBUG: log every entry so we can see if Supabase gateway is blocking requests
  try {
    const supa = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );
    const hasAuth = !!req.headers.get("Authorization");
    const authPrefix = (req.headers.get("Authorization") || "").slice(0, 30);
    await supa.from("debug_coach_log").insert({
      user_id: "entry-point",
      request_body: { hasAuth, authPrefix, method: req.method, url: req.url },
      response_body: null,
      response_status: 0,
      ms: 0,
    });
  } catch (_) {}

  try {
    // Clone request so we can read body after auth check
    const body = await req.json();
    const { message, conversationId, workoutSummary, trainingPlanContext, fitnessPredictions, proactive, checkInContext, smartInsights, userId: payloadUserId } = body;

    // Verify authenticated user from JWT.
    // verify_jwt = true in config.toml ensures only valid Supabase JWTs
    // (user, anon, or service_role) reach this function. If the JWT contains
    // a user claim, use it. Otherwise fall back to payloadUserId from the body
    // (used by iOS app which sends anon key + userId in body).
    let userId = await getAuthenticatedUser(req);

    if (!userId && payloadUserId) {
      const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
      if (uuidRegex.test(payloadUserId)) {
        userId = payloadUserId;
        console.log(`Using userId from payload: ${payloadUserId}`);
      }
    }

    if (!userId) {
      return unauthorizedResponse(corsHeaders);
    }

    if (!message) {
      return new Response(
        JSON.stringify({ error: "Message is required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Input validation
    const msgLengthErr = validateLength(message, "message", 2000);
    if (msgLengthErr) return validationErrorResponse(msgLengthErr, corsHeaders);

    if (conversationId) {
      const convIdErr = validateUUID(conversationId, "conversationId");
      if (convIdErr) return validationErrorResponse(convIdErr, corsHeaders);
    }

    // Initialize Supabase client
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    // ========================================================================
    // LAYER 1: Rate Limiting (skip for proactive check-ins)
    // ========================================================================
    let rateLimit = { allowed: true, remaining: 999, resetAt: new Date(), current: 0, limit: 999 };
    let userTier = "free";

    if (userId && isRateLimitEnabled() && !proactive) {
      const { data: tierData } = await supabase
        .from("user_tiers")
        .select("tier")
        .eq("user_id", userId)
        .single();

      userTier = tierData?.tier || "free";
      // W2.3: feature-scoped so coaching limits are pinned independently of
      // predictor/transcribe/etc. Previously used the global checkRateLimit
      // which shared one bucket across all features.
      rateLimit = await checkFeatureRateLimit(userId, "coaching", userTier);

      if (!rateLimit.allowed) {
        return new Response(
          JSON.stringify({
            error: "Daily limit reached",
            remaining: 0,
            resetAt: rateLimit.resetAt.toISOString(),
            limit: rateLimit.limit,
          }),
          { status: 429, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }
    }

    // ========================================================================
    // LAYER 1.5: Race Intel Auto-Fetch
    // If the user asks about a specific race course/elevation/weather and we
    // don't have data cached, call race-intel inline to research it. This
    // prevents the AI from making up course details from training data.
    // ========================================================================
    const raceKeywords = /\b(course|elevation|hills?|flat|route|aid station|start line|weather|race day|race strategy)\b/i;
    const raceNamePattern = /\b(?:cap\s*10k|marathon|half\s*marathon|10k|5k|ironman|triathlon|boston|chicago|nyc|berlin|london|tokyo|austin|houston|dallas|san\s*antonio)\b/i;
    const looksLikeRaceQuestion = raceKeywords.test(message) && raceNamePattern.test(message);

    if (looksLikeRaceQuestion && userId) {
      // Extract a likely race name from the message
      const raceNameMatch = message.match(/(?:the\s+)?([A-Z][A-Za-z0-9\s'&\-]+(?:marathon|half|10k|5k|cap\s*10k|classic|relay|dash|run))/i);
      const raceName = raceNameMatch?.[1]?.trim() || message.match(raceNamePattern)?.[0] || "";

      if (raceName) {
        // Check if we already have intel for this race
        const { data: existingIntel } = await supabase
          .from("race_intel")
          .select("id")
          .eq("user_id", userId)
          .ilike("race_name", `%${raceName}%`)
          .limit(1);

        if (!existingIntel?.length) {
          console.log(`[Coach] Race question detected for "${raceName}" — fetching intel...`);
          try {
            const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
            const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
            const intelRes = await fetch(`${supabaseUrl}/functions/v1/race-intel`, {
              method: "POST",
              headers: {
                "Content-Type": "application/json",
                Authorization: `Bearer ${serviceKey}`,
                apikey: serviceKey,
              },
              body: JSON.stringify({
                race_name: raceName,
                user_id: userId,
              }),
              signal: AbortSignal.timeout(25000),
            });
            if (intelRes.ok) {
              console.log(`[Coach] Race intel fetched for "${raceName}"`);
            } else {
              console.warn(`[Coach] Race intel fetch failed: ${intelRes.status}`);
            }
          } catch (e) {
            console.warn(`[Coach] Race intel fetch error: ${e}`);
          }
        }
      }
    }

    // ========================================================================
    // LAYER 2: Generate embedding for cache lookup and RAG
    // ========================================================================
    const geminiKey = Deno.env.get("GEMINI_API_KEY");
    let queryEmbedding: number[] | null = null;

    if (geminiKey) {
      try {
        const embResponse = await fetch(
          `https://generativelanguage.googleapis.com/v1beta/models/gemini-embedding-001:embedContent?key=${geminiKey}`,
          {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
              content: { parts: [{ text: message }] },
              outputDimensionality: 768,
            }),
          }
        );
        if (embResponse.ok) {
          const embData = await embResponse.json();
          queryEmbedding = embData.embedding.values;
        } else {
          console.error("Embedding API error:", await embResponse.text());
        }
      } catch (embError) {
        console.error("Embedding generation failed:", embError);
      }
    }

    // ========================================================================
    // LAYER 3: Check semantic cache
    // ========================================================================
    if (queryEmbedding && isCacheEnabled()) {
      const cached = await getCachedResponse(queryEmbedding);

      if (cached) {
        await supabase.from("usage_tracking").insert({
          user_id: userId,
          feature: "coaching",
          model_used: "cache",
          cached: true,
        });

        console.log(`Cache hit! Returning cached response (${Date.now() - startTime}ms)`);

        return new Response(
          JSON.stringify({
            response: cached.response,
            conversationId,
            cached: true,
            remaining: rateLimit.remaining,
            model: "cache",
          }),
          { headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }
    }

    // ========================================================================
    // LAYER 3.9: Athlete State snapshot (~300 token summary of "who is this runner")
    // ========================================================================
    const athleteState = await getOrBuildAthleteState(supabase, userId);
    const athleteContext = stateToPromptContext(athleteState);

    // ========================================================================
    // LAYER 4: Fetch context data (parallel queries)
    // Fetch 3 months of training data for comprehensive context
    // IMPORTANT: Order by workout_date (when run happened), not created_at (when logged)
    // ========================================================================
    const threeMonthsAgo = new Date();
    threeMonthsAgo.setMonth(threeMonthsAgo.getMonth() - 3);

    const weekMonday = getCurrentWeekMonday();
    const weekMondayStr = weekMonday.toISOString().split("T")[0];
    const fiveWeeksAgo = new Date(weekMonday);
    fiveWeeksAgo.setDate(fiveWeeksAgo.getDate() - 35);
    const twoWeeksAgo = new Date();
    twoWeeksAgo.setDate(twoWeeksAgo.getDate() - 14);

    // Use allSettled so one slow/failed query doesn't crash the entire request
    const settled = await Promise.allSettled([
      supabase
        .from("training_logs")
        .select("id, created_at, workout_date, workout_distance_miles, workout_duration_minutes, workout_type, workout_pace_per_mile, pace_segments, mood, cleaned_notes, notes, coach_insight, workout_notes, extracted_data, weather_actual, weather_adjusted_pace_delta_seconds_per_mile")
        .eq("user_id", userId)
        .or(`workout_date.gte.${threeMonthsAgo.toISOString()},and(workout_date.is.null,created_at.gte.${threeMonthsAgo.toISOString()})`)
        .order("workout_date", { ascending: false, nullsFirst: false })
        .limit(150), // ~3 months of daily training
      supabase
        .from("user_goals")
        .select("goal_title, target_date")
        .eq("status", "active")
        .eq("user_id", userId)
        .not("user_id", "is", null)
        .order("target_date", { ascending: true }),
      conversationId
        ? supabase.from("conversation_messages").select("role, content").eq("conversation_id", conversationId).order("created_at", { ascending: false }).limit(50)
        : Promise.resolve({ data: null }),
      queryEmbedding
        ? supabase.rpc("match_coaching_documents", {
            query_embedding: `[${queryEmbedding.join(",")}]`,
            match_count: 5,
          })
        : Promise.resolve({ data: [] }),
      // Latest weekly coaching report
      userId
        ? supabase
            .from("weekly_coaching_reports")
            .select("coaching_narrative, alerts, adjustments, focus_areas, metrics, week_start")
            .eq("user_id", userId)
            .eq("status", "completed")
            .order("week_start", { ascending: false })
            .limit(1)
        : Promise.resolve({ data: [] }),
      // Scheduled workouts — placeholder; real fetch uses plan_id after batch
      // (scheduled_workouts has no user_id column — must join through training_plans)
      Promise.resolve({ data: [] }),
      // Recent form checks (past 2 weeks)
      userId
        ? supabase
            .from("form_checks")
            .select("ai_analysis, created_at")
            .eq("user_id", userId)
            .gte("created_at", twoWeeksAgo.toISOString())
            .eq("status", "completed")
            .order("created_at", { ascending: false })
            .limit(3)
        : Promise.resolve({ data: [] }),
      // Fitness snapshots (latest 5)
      userId
        ? supabase
            .from("fitness_snapshots")
            .select("predicted_marathon_seconds, predicted_half_seconds, predicted_10k_seconds, predicted_5k_seconds, confidence, created_at")
            .eq("user_id", userId)
            .order("created_at", { ascending: false })
            .limit(5)
        : Promise.resolve({ data: [] }),
      // Active training plan (for goal context)
      userId
        ? supabase
            .from("training_plans")
            .select("id, name, start_date, end_date, target_race_distance, target_time_seconds, status")
            .eq("user_id", userId)
            .eq("status", "active")
            .limit(1)
            .maybeSingle()
        : Promise.resolve({ data: null }),
      // Cached athlete profile (comprehensive historical analysis)
      userId
        ? supabase
            .from("athlete_profiles")
            .select("profile_data")
            .eq("user_id", userId)
            .single()
        : Promise.resolve({ data: null }),
      // Recent negative feedback (for learning from bad responses)
      userId
        ? supabase.rpc("get_negative_feedback", { p_user_id: userId, p_limit: 5 })
        : Promise.resolve({ data: [] }),
      // Pending coaching adjustments (unresolved advice)
      userId
        ? supabase.rpc("get_pending_adjustments", { p_user_id: userId })
        : Promise.resolve({ data: [] }),
      // Race intel (course data, weather for upcoming race)
      userId
        ? supabase
            .from("race_intel")
            .select("race_name, race_date, location, course_data, weather_data, confidence, verification_notes")
            .eq("user_id", userId)
            .order("fetched_at", { ascending: false })
            .limit(1)
        : Promise.resolve({ data: [] }),
      // Recent AI insights (injury warnings, race readiness, post-run analysis)
      userId
        ? supabase
            .from("ai_insights")
            .select("insight_type, title, summary, priority, created_at")
            .eq("user_id", userId)
            .order("created_at", { ascending: false })
            .limit(5)
        : Promise.resolve({ data: [] }),
    ]);

    // Extract results — use empty defaults for any query that failed
    const extract = <T>(index: number, fallback: T): T => {
      const r = settled[index];
      return r.status === "fulfilled" ? (r.value as any)?.data ?? fallback : fallback;
    };
    const logsResult = { data: extract<any[]>(0, []) };
    const goalsResult = { data: extract<any[]>(1, []) };
    const conversationResult = { data: extract<any[]>(2, []) };
    const docsResult = { data: extract<any[]>(3, []) };
    const weeklyReportResult = { data: extract<any[]>(4, []) };
    const scheduledResult = { data: extract<any[]>(5, []) };
    const formChecksResult = { data: extract<any[]>(6, []) };
    const fitnessSnapshotsResult = { data: extract<any[]>(7, []) };
    const activePlanResult = { data: extract<any>(8, null) };
    const athleteProfileResult = { data: extract<any>(9, null) };
    const negativeFeedbackResult = { data: extract<any[]>(10, []) };
    const pendingAdjustmentsResult = { data: extract<any[]>(11, []) };
    const raceIntelResult = { data: extract<any[]>(12, []) };
    const aiInsightsResult = { data: extract<any[]>(13, []) };

    // Log any failed queries for debugging
    settled.forEach((r, i) => {
      if (r.status === "rejected") {
        console.warn(`Context query ${i} failed: ${r.reason?.message || r.reason}`);
      }
    });

    // ========================================================================
    // LAYER 4.1: Fetch scheduled workouts using active plan ID
    // scheduled_workouts has no user_id — must go through training_plans.
    // We now know the plan ID from the batch, so fetch the real data.
    // ========================================================================
    const activePlanId = activePlanResult.data?.id as string | undefined;
    let planAwarenessContext = "";

    if (activePlanId) {
      const weekSundayStr = new Date(weekMonday.getTime() + 6 * 86400000).toISOString().split("T")[0];
      const sevenDaysAgo = new Date();
      sevenDaysAgo.setDate(sevenDaysAgo.getDate() - 7);
      const sevenDaysAgoStr = sevenDaysAgo.toISOString().split("T")[0];

      // Fetch this week's scheduled + last 7 days (for plan-vs-actual comparison)
      // Use the earlier of sevenDaysAgo and weekMonday as the start bound
      const fetchStart = sevenDaysAgoStr < weekMondayStr ? sevenDaysAgoStr : weekMondayStr;
      try {
        const { data: scheduledRows } = await supabase
          .from("scheduled_workouts")
          .select("id, date, workout_type, status, workout_data, completed_workout_id, week_number, notes, weather_forecast")
          .eq("plan_id", activePlanId)
          .gte("date", fetchStart)
          .lte("date", weekSundayStr)
          .order("date");

        const allScheduled = scheduledRows || [];

        // Split: this week (for analytics + "what's planned") vs last 7 days (for plan-vs-actual)
        const thisWeekScheduled = allScheduled.filter((w: any) => w.date >= weekMondayStr);
        const last7DaysScheduled = allScheduled.filter((w: any) => w.date >= sevenDaysAgoStr);

        // Update scheduledResult so analytics module gets real data
        scheduledResult.data = thisWeekScheduled;

        // Build plan awareness context
        const plan = activePlanResult.data;
        const allLogs = logsResult.data || [];
        planAwarenessContext = buildPlanAwarenessContext(
          plan,
          thisWeekScheduled,
          last7DaysScheduled,
          allLogs
        );
        if (planAwarenessContext) {
          console.log(`Plan awareness context built (~${planAwarenessContext.length} chars)`);
        }
      } catch (schedErr) {
        console.warn("Failed to fetch scheduled workouts:", schedErr);
      }
    }

    const hasTrainingData = (logsResult.data?.length || 0) > 0;
    const hasGoals = (goalsResult.data?.length || 0) > 0;
    // Conversation fetched DESC with limit 50 — reverse to chronological order
    const existingMessages: Array<{ role: string; content: string }> = (conversationResult.data || []).reverse();

    // Build weekly coaching report context — include full narrative + adjustments + metrics
    let weeklyReportContext = "";
    const latestReport = weeklyReportResult.data?.[0];
    if (latestReport) {
      const narrative = (latestReport.coaching_narrative as string) || "";
      const activeAlerts = (latestReport.alerts as Array<{ severity: string; title: string }> || [])
        .filter((a) => a.severity !== "green")
        .map((a) => `[${a.severity}] ${a.title}`)
        .join(", ");
      const focusAreas = (latestReport.focus_areas as string[])?.join(", ") || "";
      const adjustments = (latestReport.adjustments as string[]) || [];
      const metrics = latestReport.metrics as Record<string, any> | null;

      let reportParts = [`\n\nWeekly Coaching Report (week of ${latestReport.week_start}):`];
      // Include full narrative for moderate/complex, truncated for simple
      reportParts.push(narrative.slice(0, 1200));
      if (activeAlerts) reportParts.push(`Active alerts: ${activeAlerts}`);
      if (focusAreas) reportParts.push(`Focus areas: ${focusAreas}`);
      if (adjustments.length > 0) reportParts.push(`Recommended adjustments: ${adjustments.join("; ")}`);
      if (metrics) {
        const metricLines: string[] = [];
        if (metrics.total_miles != null) metricLines.push(`Weekly miles: ${metrics.total_miles}`);
        if (metrics.total_runs != null) metricLines.push(`Runs: ${metrics.total_runs}`);
        if (metrics.avg_pace) metricLines.push(`Avg pace: ${metrics.avg_pace}`);
        if (metrics.compliance_pct != null) metricLines.push(`Plan compliance: ${metrics.compliance_pct}%`);
        if (metricLines.length > 0) reportParts.push(`Metrics: ${metricLines.join(", ")}`);
      }
      weeklyReportContext = reportParts.join("\n");
    }

    // ========================================================================
    // LAYER 4.25: Retrieve persistent memories and active injuries
    // ========================================================================
    let memoriesContext = "";
    let injuryContext = "";
    let activeInjuries: Awaited<ReturnType<typeof getActiveInjuries>> = [];
    if (userId) {
      try {
        const [userMemories, userInjuries] = await Promise.all([
          getMemories(supabase, userId),
          getActiveInjuries(supabase, userId),
        ]);
        memoriesContext = buildMemoryContext(userMemories);
        activeInjuries = userInjuries;
        injuryContext = buildInjuryContext(userInjuries);
        if (memoriesContext) {
          console.log(`Retrieved ${userMemories.length} memories for user context`);
        }
        if (injuryContext) {
          console.log(`Retrieved ${userInjuries.length} active injuries for context`);
        }
      } catch (memError) {
        console.error("Error fetching memories/injuries:", memError);
      }
    }

    // ========================================================================
    // LAYER 4.27: Feedback learning + pending adjustments context
    // ========================================================================
    // Hoisted from LAYER 6 (2026-06-10): this flag was declared ~270 lines
    // below its first use here — a temporal-dead-zone ReferenceError (500)
    // for any athlete with negative-feedback rows. Same expression, one
    // declaration, used by both layers.
    const isCoachInsightRequest = !proactive && message.includes("[COACH INSIGHT REQUEST");

    let feedbackContext = "";
    const negativeFeedback = negativeFeedbackResult.data || [];
    if (negativeFeedback.length > 0 && !isCoachInsightRequest) {
      const feedbackLines = negativeFeedback
        .filter((f: any) => f.message_content)
        .slice(0, 3)
        .map((f: any) => {
          const snippet = f.message_content.slice(0, 150);
          const reason = f.feedback_text ? ` (Reason: ${f.feedback_text.slice(0, 80)})` : "";
          return `- "${snippet}..."${reason}`;
        });
      if (feedbackLines.length > 0) {
        feedbackContext = `\n\nIMPORTANT - This athlete previously found these types of responses unhelpful:\n${feedbackLines.join("\n")}\nAvoid similar patterns. Adjust your approach.`;
      }
    }

    let pendingAdjustmentsContext = "";
    const pendingAdj = pendingAdjustmentsResult.data || [];
    if (pendingAdj.length > 0 && !isCoachInsightRequest) {
      const adjLines = pendingAdj.slice(0, 5).map((a: any) =>
        `- [${a.adjustment_type}] ${a.recommendation}${a.target_workout ? ` (for: ${a.target_workout})` : ""}`
      );
      pendingAdjustmentsContext = `\n\nRecent coaching adjustments (check if followed):\n${adjLines.join("\n")}`;
    }

    // ========================================================================
    // LAYER 4.28: Race Intel (course data, weather, logistics)
    // ========================================================================
    let raceIntelContext = "";
    const raceIntel = raceIntelResult.data?.[0];
    if (raceIntel) {
      const course = raceIntel.course_data as Record<string, any> | null;
      const weather = raceIntel.weather_data as Record<string, any> | null;
      const parts: string[] = [`\n\nUpcoming Race: ${raceIntel.race_name}${raceIntel.race_date ? ` (${raceIntel.race_date})` : ""}${raceIntel.location ? ` — ${raceIntel.location}` : ""}`];

      if (course) {
        if (course.course_description) parts.push(`Course: ${course.course_description}`);
        if (course.elevation_gain_ft) parts.push(`Elevation: +${course.elevation_gain_ft}ft${course.elevation_loss_ft ? ` / -${course.elevation_loss_ft}ft` : ""}`);
        if (course.key_hills?.length > 0) parts.push(`Key hills: ${course.key_hills.map((h: any) => `mile ${h.mile}: ${h.description}`).join("; ")}`);
        if (course.surface) parts.push(`Surface: ${course.surface}`);
        if (course.start_time) parts.push(`Start: ${course.start_time}`);
        if (course.notable_features?.length > 0) parts.push(`Notable: ${course.notable_features.join(", ")}`);
        if (course.aid_station_details) parts.push(`Aid stations: ${course.aid_station_details}`);
      }
      if (weather?.conditions_summary) parts.push(`Weather (historical avg): ${weather.conditions_summary}`);
      if (raceIntel.confidence !== "high" && raceIntel.verification_notes) {
        parts.push(`Note: ${raceIntel.verification_notes}`);
      }

      raceIntelContext = parts.join("\n");
      console.log(`Race intel loaded for ${raceIntel.race_name} (confidence: ${raceIntel.confidence})`);
    }

    // ========================================================================
    // LAYER 4.29: AI Insights cross-reference (injury warnings, race readiness, etc.)
    // ========================================================================
    let aiInsightsContext = "";
    const recentInsights = aiInsightsResult.data || [];
    if (recentInsights.length > 0) {
      aiInsightsContext = "\n\nRecent AI Insights (from other analyses — reference these when relevant):\n";
      for (const insight of recentInsights) {
        const age = Math.round((Date.now() - new Date(insight.created_at).getTime()) / (1000 * 60 * 60));
        const ageLabel = age < 24 ? `${age}h ago` : `${Math.round(age / 24)}d ago`;
        const priority = insight.priority ? ` [${insight.priority}]` : "";
        aiInsightsContext += `- ${insight.insight_type.replace(/_/g, " ")}${priority} (${ageLabel}): ${(insight.summary || insight.title || "").slice(0, 150)}\n`;
      }
      aiInsightsContext += "If the athlete asks about injury risk, race readiness, or training block progress, reference the relevant insight above.\n";
    }

    // ========================================================================
    // LAYER 4.3: Real-time data analysis (ACWR, compliance, signals)
    // ========================================================================
    let analyticsContext = "";
    if (userId) {
      try {
        // Split training logs into this week + previous weeks for ACWR
        const allLogs = (logsResult.data || []) as TrainingLogRow[];
        const thisWeekLogs = allLogs.filter((l) => {
          if (!l.workout_date) return false;
          return l.workout_date >= weekMondayStr;
        });
        const olderLogs = allLogs.filter((l) => {
          if (!l.workout_date) return false;
          return l.workout_date < weekMondayStr && l.workout_date >= fiveWeeksAgo.toISOString().split("T")[0];
        });
        const previousWeeksLogs = splitLogsIntoWeeks(olderLogs, weekMonday);

        // Goal context for analysis
        const plan = activePlanResult.data;
        const goalDaysRemaining = plan?.end_date
          ? Math.ceil((new Date(plan.end_date).getTime() - Date.now()) / (1000 * 60 * 60 * 24))
          : null;

        const analysis = analyzeTrainingData({
          thisWeekLogs: thisWeekLogs as TrainingLogRow[],
          previousWeeksLogs,
          scheduledThisWeek: (scheduledResult.data || []) as ScheduledWorkoutRow[],
          activeInjuries: activeInjuries as unknown as InjuryRow[],
          formChecks: (formChecksResult.data || []) as FormCheckResult[],
          fitnessSnapshots: (fitnessSnapshotsResult.data || []) as FitnessSnapshot[],
          goalDaysRemaining,
          targetTimeSeconds: plan?.target_time_seconds || null,
          targetDistance: plan?.target_race_distance || null,
          includeSignals: smartInsights !== false,
        });

        analyticsContext = analysis.context;
        if (analysis.signals.length > 0) {
          console.log(`Generated ${analysis.signals.length} coaching signals (${analysis.signals.filter(s => s.priority === "high").length} high priority)`);
        }
      } catch (analyticsError) {
        console.error("Error computing real-time analytics:", analyticsError);
      }
    }

    // ========================================================================
    // LAYER 4.35: Athlete Profile (comprehensive historical context)
    // ========================================================================
    let athleteProfileContext = "";
    if (athleteProfileResult.data?.profile_data) {
      try {
        athleteProfileContext = buildAthleteProfileContext(athleteProfileResult.data.profile_data as AthleteProfile);
        if (athleteProfileContext) {
          console.log(`Loaded athlete profile context (~${estimateTokens(athleteProfileContext)} tokens)`);
        }
      } catch (profileError) {
        console.error("Error building athlete profile context:", profileError);
      }
    }

    // ========================================================================
    // LAYER 4.38: Runner experience level detection
    // ========================================================================
    let runnerLevelContext = "";
    if (userId) {
      const profileForLevel = athleteProfileResult.data?.profile_data || {};
      const { level, promptAdjustment } = detectRunnerLevel(
        profileForLevel,
        memoriesContext,
        profileForLevel?.avg_weekly_mileage || profileForLevel?.weekly_mileage,
      );
      runnerLevelContext = promptAdjustment;
      if (level !== "intermediate") {
        console.log(`Runner level detected: ${level}`);
      }
    }

    // ========================================================================
    // LAYER 4.4: Periodization awareness from active training plan
    // ========================================================================
    let periodizationContext = "";
    const activePlan = activePlanResult.data;
    if (activePlan?.start_date && activePlan?.end_date) {
      periodizationContext = inferTrainingPhase({
        start_date: activePlan.start_date,
        end_date: activePlan.end_date,
        target_race_distance: activePlan.target_race_distance,
      });
      if (periodizationContext) {
        console.log(`Periodization phase detected for plan "${activePlan.name}"`);
      }
    }

    // ========================================================================
    // LAYER 4.5: User Profile & Conversational Data Gathering
    // ========================================================================
    let userProfile = null;
    let profileContext = "";

    if (userId) {
      // Get or create user profile
      userProfile = await getOrCreateProfile(supabase, userId);

      // Extract any profile data from this message and store it
      const extractedData = extractProfileData(message);
      if (Object.keys(extractedData).length > 0) {
        await updateProfile(supabase, userId, extractedData);
        // Refresh profile with new data
        userProfile = { ...userProfile, ...extractedData };
        console.log("Extracted and stored profile data:", Object.keys(extractedData));
      }

      // Check if this is a complex query that might need clarification
      if (isComplexQuery(message)) {
        const queryType = getQueryType(message);
        const targetDistance = detectTargetDistance(message);
        const missingData = getMissingData(userProfile, queryType, targetDistance);

        // Get the threshold for this query type (pace_advice = 1, training_plan = 2, etc.)
        const threshold = getQueryThreshold(queryType);
        console.log(`Complex query detected: type=${queryType}, distance=${targetDistance}, missing=${missingData.length} fields, threshold=${threshold}`);

        // If we're missing critical data AND this is a new conversation (not a follow-up answer)
        // Use query-specific threshold: pace questions need data to answer, training plans can tolerate more missing
        const isLikelyAnswer = existingMessages.length > 0 &&
          existingMessages[existingMessages.length - 1]?.role === "assistant" &&
          (message.length < 100 || /^\d|^yes|^no|^about|^around|^i |^my /i.test(message));

        if (missingData.length >= threshold && !isLikelyAnswer) {
          const questions = generateClarifyingQuestions(missingData, 3);
          const clarifyingResponse = buildClarifyingPrompt(message, questions, userProfile);

          // Save conversation with the clarifying questions
          let finalConversationId = conversationId;
          if (!finalConversationId) {
            const { data: newConv } = await supabase
              .from("conversations")
              .insert({ user_id: userId, updated_at: new Date().toISOString() })
              .select("id")
              .single();
            finalConversationId = newConv?.id;
          } else {
            await supabase
              .from("conversations")
              .update({ updated_at: new Date().toISOString() })
              .eq("id", finalConversationId);
          }
          if (finalConversationId) {
            await supabase.from("conversation_messages").insert([
              { conversation_id: finalConversationId, user_id: userId, role: "user", content: message },
              { conversation_id: finalConversationId, user_id: userId, role: "assistant", content: clarifyingResponse },
            ]);
          }

          console.log(`Asking ${questions.length} clarifying questions`);

          return new Response(
            JSON.stringify({
              response: clarifyingResponse,
              conversationId: finalConversationId,
              model: "clarifying",
              needsMoreInfo: true,
              missingFields: missingData,
              remaining: rateLimit.remaining,
              processingTime: Date.now() - startTime,
            }),
            { headers: { ...corsHeaders, "Content-Type": "application/json" } }
          );
        }
      }

      // Build profile context for the AI prompt (with structured injury data)
      profileContext = buildProfileContext(userProfile, activeInjuries);
    }

    // ========================================================================
    // LAYER 5: Classify query and get best available model
    // ========================================================================
    let complexity: QueryComplexity;
    let config: RouterConfig;

    if (proactive && checkInContext) {
      // Proactive check-ins always use moderate tier for empathy
      const result = getBestAvailableModel("moderate");
      complexity = result.complexity;
      config = result.config;
      console.log(`Proactive check-in routed to ${complexity} tier (${config.provider}/${config.model})`);
    } else {
      const preferredComplexity = classifyQuery(message, {
        hasTrainingData,
        hasGoals,
        conversationLength: existingMessages.length,
      });
      const result = getBestAvailableModel(preferredComplexity);
      complexity = result.complexity;
      config = result.config;
      console.log(`Query routed to ${complexity} tier (${config.provider}/${config.model})`);
    }

    // ========================================================================
    // LAYER 6: Build context-aware prompt
    // ========================================================================
    const isTrainingQuery = proactive ? true : isTrainingRelatedQuery(message);
    const isThisWeek = proactive ? false : isThisWeekQuery(message);
    // isCoachInsightRequest is declared in LAYER 4.27 (hoisted — see note there).

    // For coach insight requests, skip extra context - workout details are in the message
    // For simple queries, use compressed context. For moderate/complex, use full training document
    // For "this week" queries, add focused this-week context at the top
    let trainingContext = "";
    let thisWeekContext = "";

    if (!isCoachInsightRequest) {
      // Always build "this week" context for this-week queries
      if (isThisWeek) {
        thisWeekContext = buildThisWeekContext((logsResult.data || []) as ExtendedTrainingLog[]);
      }

      if (complexity === "simple") {
        // Simple queries: minimal compressed context
        trainingContext = compressTrainingContext(logsResult.data || []);
      } else {
        // Moderate/Complex queries: full training period document (3 months)
        trainingContext = buildTrainingPeriodDocument(
          (logsResult.data || []) as ExtendedTrainingLog[],
          3 // 3 months of data
        );
      }

      // Prepend this week context if it's a this-week query
      if (thisWeekContext) {
        trainingContext = thisWeekContext + "\n\n" + trainingContext;
      }
    }

    const goalsContext = isCoachInsightRequest ? "" : compressGoalsContext(goalsResult.data || [], isTrainingQuery);
    // Include full conversation history for continuity (up to 12 messages, 600 chars each)
    const conversationContext = isCoachInsightRequest ? "" : compressConversationHistory(existingMessages);

    console.log(`Query analysis: training-related=${isTrainingQuery}, thisWeek=${isThisWeek}, hasGoals=${hasGoals}, isCoachInsight=${isCoachInsightRequest}, proactive=${!!proactive}, complexity=${complexity}`);

    // Add relevant docs for ALL queries (skip for coach insight and proactive)
    // Even simple questions benefit from grounded knowledge
    let docsContext = "";
    if (!isCoachInsightRequest && !proactive && docsResult.data && docsResult.data.length > 0) {
      const maxDocs = complexity === "simple" ? 3 : 5;
      const maxChars = complexity === "simple" ? 800 : 1500;
      docsContext = "\n\nRelevant coaching knowledge:\n";
      docsResult.data.slice(0, maxDocs).forEach((doc: any) => {
        docsContext += `${doc.title}: ${doc.content.slice(0, maxChars)}\n\n`;
      });
    }

    // Build the full prompt
    let fullPrompt: string;

    if (proactive && checkInContext) {
      // Proactive check-in: coach reaches out after concerning voice memo
      const { mood, cleanedNotes, coachInsight } = checkInContext;
      const hkContext = workoutSummary ? `\n\nRecent workouts:\n${workoutSummary}` : "";
      const planContext = trainingPlanContext ? `\n\nTraining Plan:\n${trainingPlanContext}` : "";
      fullPrompt = `${loadPrompt("coaching-agent-proactive.v1")}${runnerLevelContext}

${athleteContext}

${trainingContext}${athleteProfileContext}${analyticsContext}${periodizationContext}${planAwarenessContext}${memoriesContext}${injuryContext}${raceIntelContext}${aiInsightsContext}${profileContext}${planContext}${hkContext}

Athlete's voice memo summary: ${cleanedNotes || "No details available"}
Detected mood: ${mood}
${coachInsight ? `Your initial take: ${coachInsight}` : ""}

Open the conversation:`;
    } else if (isCoachInsightRequest) {
      // Check if goals should be included (harder efforts - look for [GOALS] tag)
      const includeGoals = message.includes("[GOALS]") && hasGoals;
      const goalsHint = includeGoals && goalsResult.data && goalsResult.data.length > 0
        ? `\nRunner's upcoming goal: ${goalsResult.data[0].goal_title} (${Math.ceil((new Date(goalsResult.data[0].target_date).getTime() - Date.now()) / (1000 * 60 * 60 * 24))} days away)`
        : "";

      // Coach insight: thoughtful feedback on a single workout
      fullPrompt = `Give quick feedback on this workout. 4-5 sentences, plain text, no markdown.

Talk like a real coach — not an AI. No "impressive", "journey", "fantastic", "great job", "solid work" or any generic praise. Be specific about what you see in the workout. Short sentences. Be direct.

If they're tired, say rest up. If something hurts, tell them to take it seriously. Don't sugarcoat, don't over-praise. One honest observation is worth more than five compliments.

Never mention coaching frameworks or names (Daniels, etc.).${goalsHint}

${message}

Coach:`;
    } else {
      // Simple / Moderate / Complex — all three tiers now go through the
      // token-budgeted assembler from _shared/context.ts (TASKS.md C.2).
      //
      // Why budget here at all: the previous moderate/complex assembly
      // unconditionally concatenated 22 context blocks, several of which
      // overlap (athleteContext + athleteProfileContext + analyticsContext
      // + periodizationContext + weeklyReportContext + aiInsightsContext
      // all cover related ground). A drive-by edit that adds another
      // block, or bumps `.limit(150)` somewhere, silently multiplied
      // input tokens with no review-time signal. The budget caps that.
      //
      // Priority rules:
      //   required  — model can't be safe / coherent without it
      //                (athlete state DCO, memories, injuries, system prompt)
      //   preferred — high-signal personalization (training history, plan,
      //                conversation, grounded docs)
      //   optional  — nice-to-have analytics that already overlap with
      //                required blocks (weeklyReport, aiInsights, analytics,
      //                planAwareness, profile, hk, pendingAdj, feedback,
      //                predictions, goals — these are the first to drop
      //                under budget pressure)
      const systemPrompt = loadPrompt(`coaching-agent-${complexity}.v1`);

      const hkContext = workoutSummary
        ? `\n\nRecent HealthKit workouts (from Apple Watch / GPS watch):\n${workoutSummary}`
        : "";
      const planContext = trainingPlanContext
        ? `\n\nActive Training Plan:\n${trainingPlanContext}`
        : "";
      const predContext = fitnessPredictions
        ? `\n\nFitness Predictions:\n${fitnessPredictions}`
        : "";

      const blocks: PromptBlock[] = [
        // Required: identity + safety guardrails.
        { name: "runnerLevel",    content: runnerLevelContext,    priority: "required" },
        { name: "athlete",        content: athleteContext,        priority: "required" },
        { name: "memories",       content: memoriesContext,       priority: "required" },
        { name: "injury",         content: injuryContext,         priority: "required" },

        // Preferred: high-signal personalization.
        { name: "training",       content: trainingContext,       priority: "preferred" },
        { name: "athleteProfile", content: athleteProfileContext, priority: "preferred" },
        { name: "plan",           content: planContext,           priority: "preferred" },
        { name: "conversation",   content: conversationContext,   priority: "preferred" },
        { name: "docs",           content: docsContext,           priority: "preferred" },
        { name: "raceIntel",      content: raceIntelContext,      priority: "preferred" },

        // Optional: overlap with required/preferred or rarely-cited.
        // These drop first under budget pressure.
        { name: "periodization",  content: periodizationContext,  priority: "optional" },
        { name: "analytics",      content: analyticsContext,      priority: "optional" },
        { name: "planAwareness",  content: planAwarenessContext,  priority: "optional" },
        { name: "weeklyReport",   content: weeklyReportContext,   priority: "optional" },
        { name: "aiInsights",     content: aiInsightsContext,     priority: "optional" },
        { name: "profile",        content: profileContext,        priority: "optional" },
        { name: "hk",             content: hkContext,             priority: "optional" },
        { name: "predictions",    content: predContext,           priority: "optional" },
        { name: "goals",          content: goalsContext,          priority: "optional" },
        { name: "pendingAdj",     content: pendingAdjustmentsContext, priority: "optional" },
        { name: "feedback",       content: feedbackContext,       priority: "optional" },
      ];

      const ctxBudget = COMPLEXITY_CONTEXT_BUDGETS[complexity] ?? COMPLEXITY_CONTEXT_BUDGETS.moderate;
      const assembled = assembleWithBudget(blocks, ctxBudget);

      console.log(
        `[ctx] complexity=${complexity} budget=${assembled.budget} used=${assembled.used} ` +
        `included=${assembled.included.length} dropped=[${assembled.dropped.join(",")}] ` +
        `truncated=[${assembled.truncated.join(",")}]`,
      );

      if (complexity === "simple") {
        // Simple — leaner framing, prompt mostly faqs.
        fullPrompt = `${systemPrompt}
${assembled.text ? `\n${assembled.text}\n` : ""}
Question: ${message}

Answer:`;
      } else {
        // Moderate / Complex — coaching framing.
        fullPrompt = `${systemPrompt}

${assembled.text}

Runner's question: ${message}

Coach:`;
      }
    }

    // Token budget enforcement — truncate prompt if it exceeds model limits
    const MAX_PROMPT_TOKENS: Record<string, number> = {
      simple: 4_000,
      moderate: 30_000,
      complex: 90_000,
    };
    const tokenBudget = MAX_PROMPT_TOKENS[complexity] || 30_000;
    let inputTokens = estimateTokens(fullPrompt);

    if (inputTokens > tokenBudget) {
      console.warn(`Prompt exceeds budget: ${inputTokens} > ${tokenBudget} tokens — truncating`);
      // Truncate to fit within budget (rough: 4 chars per token)
      const maxChars = tokenBudget * 4;
      fullPrompt = fullPrompt.slice(0, maxChars) + "\n\n[Context truncated to fit model limits]\n\nRunner's question: " + message + "\n\nCoach:";
      inputTokens = estimateTokens(fullPrompt);
    }
    console.log(`Prompt built: ~${inputTokens} tokens for ${complexity} query`);

    // Hallucination diagnostic — dump the exact prompt so we can verify whether
    // numeric claims in the response (volumes, distances, dates) actually
    // appeared in the context, or were invented by the model.
    // Toggle off by unsetting COACHING_AGENT_DUMP_PROMPT.
    if (Deno.env.get("COACHING_AGENT_DUMP_PROMPT") === "1") {
      console.log(`[PROMPT_DUMP user=${userId} complexity=${complexity}]\n${fullPrompt}\n[/PROMPT_DUMP]`);
    }

    // ========================================================================
    // LAYER 7: Call the appropriate model (with fallback)
    // ========================================================================
    let coachResponse: string;
    // Widen from the router's `"groq" | "gemini"` union to include the
    // post-retry fallback state — used by the cache-poisoning guard at
    // line ~1514 to avoid caching error responses as if they were real.
    let actualProvider: "groq" | "gemini" | "fallback" = config.provider;

    // Retry wrapper: tries a model call, waits 2s, retries once before giving up
    async function withRetry<T>(fn: () => Promise<T>, label: string): Promise<T> {
      try {
        return await fn();
      } catch (firstError: any) {
        console.warn(`${label} attempt 1 failed: ${firstError?.message || firstError}`);
        await new Promise((r) => setTimeout(r, 2000));
        return await fn();
      }
    }

    try {
      // TEMPORARY: Gemini free-tier quota is exhausted. Route everything through
      // Groq until billing is set up on Gemini API.
      // Original routing preserved below for restoration.
      const FORCE_GROQ = false;

      if (FORCE_GROQ || config.provider === "groq") {
        // Groq rejects prompts over ~32K chars (413). Truncate keeping the most
        // recent/most relevant context — the USER MESSAGE and the tail of the
        // assembled prompt (where recent workouts + state live). Drops older
        // history first.
        const MAX_PROMPT_CHARS = 28000;
        const truncatedPrompt = fullPrompt.length > MAX_PROMPT_CHARS
          ? "...(earlier context truncated)...\n\n" + fullPrompt.slice(-MAX_PROMPT_CHARS)
          : fullPrompt;
        const useLargeGroq = FORCE_GROQ && complexity !== "simple";
        const groqCfg = useLargeGroq
          ? { ...getModelConfig("simple"), model: "llama-3.3-70b-versatile", maxTokens: 800 }
          : (config.provider === "groq" ? config : getModelConfig("simple"));
        console.log(`Calling Groq ${groqCfg.model} (forced=${FORCE_GROQ}, prompt=${truncatedPrompt.length} chars)...`);
        actualProvider = "groq";
        coachResponse = await withRetry(() => callGroq(truncatedPrompt, groqCfg), "Groq");
      } else {
        // Try Gemini first, fall back to Groq on rate limit or timeout
        try {
          console.log("Calling Gemini for coaching query...");
          coachResponse = await withRetry(() => callGemini(fullPrompt, config), "Gemini");
        } catch (geminiError: any) {
          const errorMessage = geminiError?.message || String(geminiError);
          console.log(`Gemini failed after retry (${errorMessage}), falling back to Groq...`);
          actualProvider = "groq";
          const groqConfig = getModelConfig("simple");
          coachResponse = await withRetry(() => callGroq(fullPrompt, groqConfig), "Groq-fallback");
        }
      }
    } catch (modelError: any) {
      // Both models failed after retries — return a graceful degradation response
      const errMsg = modelError?.message || String(modelError);
      console.error("All model providers failed after retries:", errMsg);
      actualProvider = "fallback";
      coachResponse = "I'm having trouble connecting to my AI backend right now. " +
        "This is temporary — please try again in a minute. " +
        "In the meantime, your training data is safe and I'll have a full analysis ready when I'm back online.";
    }

    const outputTokens = estimateTokens(coachResponse);

    // ========================================================================
    // LAYER 8: Cache the response for future queries (skip for proactive)
    // Never cache fallback/error responses — they poison the cache and make
    // every similar future query return "AI backend unavailable" forever.
    // ========================================================================
    const isFallback = actualProvider === "fallback"
      || coachResponse.startsWith("I'm having trouble connecting to my AI backend");
    if (!proactive && !isFallback && queryEmbedding && isCacheEnabled()) {
      await cacheResponse(queryEmbedding, message, coachResponse, complexity);
    }

    // ========================================================================
    // LAYER 9: Save conversation and log usage
    // ========================================================================
    // For proactive check-ins, only save the assistant message (no fake user message)
    const proactiveMessages = [
      { role: "assistant", content: coachResponse, timestamp: new Date().toISOString(), proactive: true },
    ];
    const normalMessages = [
      { role: "user", content: message, timestamp: new Date().toISOString() },
      { role: "assistant", content: coachResponse, timestamp: new Date().toISOString() },
    ];
    const newMessages = proactive ? proactiveMessages : normalMessages;

    // Save messages to normalized table
    let convIdForSave = conversationId;
    if (!convIdForSave) {
      const { data: newConv } = await supabase
        .from("conversations")
        .insert({ user_id: userId, updated_at: new Date().toISOString() })
        .select("id")
        .single();
      convIdForSave = newConv?.id;
    } else {
      await supabase
        .from("conversations")
        .update({ updated_at: new Date().toISOString() })
        .eq("id", convIdForSave);
    }

    const messageRows = newMessages.map((msg: any) => ({
      conversation_id: convIdForSave,
      user_id: userId,
      role: msg.role,
      content: msg.content,
      proactive: msg.proactive || false,
    }));

    // Insert messages and capture the assistant message ID for feedback
    let assistantMessageId: string | null = null;
    const [convResult, _usageResult] = await Promise.all([
      convIdForSave
        ? supabase.from("conversation_messages").insert(messageRows).select("id, role").then((res) => {
            const assistantRow = res.data?.find((m: any) => m.role === "assistant");
            assistantMessageId = assistantRow?.id || null;
            return { data: { id: convIdForSave } };
          })
        : Promise.resolve({ data: null }),
      supabase.from("usage_tracking").insert({
        user_id: userId,
        feature: proactive ? "coaching_proactive" : "coaching",
        model_used: getModelIdentifier(complexity),
        input_tokens: inputTokens,
        output_tokens: outputTokens,
        cached: false,
      }),
    ]);

    const finalConversationId = conversationId || convResult.data?.id;

    // ========================================================================
    // LAYER 9.5: Extract and store memories for future sessions
    // ========================================================================
    if (userId) {
      try {
        const newMemories = extractMemories(message, coachResponse);
        if (newMemories.length > 0) {
          await storeMemories(supabase, userId, newMemories, finalConversationId);
          console.log(`Extracted and stored ${newMemories.length} new memories`);
        }
      } catch (memError) {
        console.error("Error storing memories:", memError);
        // Don't fail the request if memory storage fails
      }
    }
    const processingTime = Date.now() - startTime;

    console.log(
      `Response generated in ${processingTime}ms using ${config.provider}/${config.model} (${complexity})`
    );

    const successBody = {
      response: coachResponse,
      conversationId: finalConversationId,
      messageId: assistantMessageId,
      model: complexity,
      provider: config.provider,
      cached: false,
      remaining: proactive ? rateLimit.remaining : rateLimit.remaining - 1,
      proactive: proactive || false,
      feedbackEnabled: !isCoachInsightRequest,
      processingTime,
    };

    // DEBUG: log the exact response body for client-side diagnosis
    try {
      await supabase.from("debug_coach_log").insert({
        user_id: userId,
        request_body: { message, hasConvId: !!conversationId, smartInsights, proactive: !!proactive },
        response_body: successBody,
        response_status: 200,
        ms: Date.now() - startTime,
      });
    } catch (_) { /* don't block on logging */ }

    return new Response(JSON.stringify(successBody), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error: any) {
    console.error("Coaching agent error:", error);
    const errBody = { error: `Internal error: ${error?.message || String(error)}` };
    try {
      const supa = (globalThis as any).__supa as any;
      if (supa) {
        await supa.from("debug_coach_log").insert({
          user_id: null,
          request_body: null,
          response_body: errBody,
          response_status: 500,
          error: errBody.error,
          ms: Date.now() - startTime,
        });
      }
    } catch (_) { /* ignore */ }
    return new Response(JSON.stringify(errBody), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});

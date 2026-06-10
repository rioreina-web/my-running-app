/**
 * Fitness Predictor Edge Function
 *
 * Uses Claude Haiku to analyze training data and predict race times.
 * Cost: ~$0.002 per prediction (~500 predictions per $1)
 */

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import Anthropic from "https://esm.sh/@anthropic-ai/sdk@0.26.0";

import { getAuthenticatedUser, unauthorizedResponse } from "../_shared/auth.ts";
import { checkFeatureRateLimit, isRateLimitEnabled } from "../_shared/rateLimit.ts";
import { validateArrayLength, validationErrorResponse, internalErrorResponse } from "../_shared/validation.ts";
import { loadPrompt } from "../_shared/prompt-library.ts";
import { type ConfirmedRace } from "../_shared/paces.ts";

import { corsHeaders } from "../_shared/cors.ts";

export interface WorkoutData {
  date: string;
  distanceMiles: number;
  durationMinutes: number;
  paceSecondsPerMile: number;
  heartRateAvg?: number;
  type: string;
}

export interface VoiceLogData {
  date: string;
  notes: string;
  mood?: string;
  pacesMentioned: string[];
}

export interface TrainingPlanInfo {
  goalRace: string;
  goalTime: string;
  goalPacePerMile: number;
  currentWeek: number;
  totalWeeks: number;
}

export interface PredictionRequest {
  workouts: WorkoutData[];
  voiceLogs: VoiceLogData[];
  trainingPlan?: TrainingPlanInfo;
  /**
   * User-declared races from athlete_state.confirmed_races (populated by
   * rebuildAthleteState from training_logs.race_result). Drives the
   * deterministic confidence tier in computeConfidenceTier — a recent
   * confirmed race beats fuzzy regex inference from workout.type strings.
   * Phase 2 Sub-task D.
   */
  confirmedRaces?: ConfirmedRace[];
  userId?: string;
}

function formatPace(secondsPerMile: number): string {
  if (secondsPerMile <= 0 || secondsPerMile > 1200) return "--:--";
  const totalSecs = Math.round(secondsPerMile);
  const mins = Math.floor(totalSecs / 60);
  const secs = totalSecs % 60;
  return `${mins}:${secs.toString().padStart(2, "0")}/mi`;
}

export type ConfidenceTier = "high" | "medium" | "low";

/**
 * Deterministic confidence tier per CLAUDE.md hard rule #7. Tier drives the
 * range half-window the renderer shows around each point estimate.
 *
 *   high   — a recent race ≥10K (≤8 weeks) OR ≥2 marathon-pace workouts (≤6 weeks)
 *   medium — at least one threshold/tempo session in the last 6 weeks
 *   low    — neither of the above
 *
 * Voice-log pace mentions count as soft evidence and can bump low→medium when
 * they describe a sustained effort at race-equivalent pace, but never up to high.
 *
 * Exported for unit-test coverage (see index.test.ts). Pure function over the
 * request shape — no side effects.
 */
export function computeConfidenceTier(request: PredictionRequest): ConfidenceTier {
  const now = Date.now();
  const days = (iso: string) => (now - new Date(iso).getTime()) / 86400000;

  // Race anchor takes priority. A user-declared race ≥10K within 8 weeks
  // is the strongest fitness signal we have — beats inferred-from-workout-
  // type races (which depend on string matching on `w.type === "Race"`)
  // and beats any voice-log evidence. Phase 2 Sub-task D — see
  // outputs/phase-2-race-anchoring-plan-2026-06-04.md.
  const LONG_ENOUGH = new Set([
    "marathon", "m",
    "half_marathon", "half-marathon", "half", "hm",
    "10k", "tenk",
    "10mi", "10_mi", "tenmi",
  ]);
  const recentConfirmedRace = (request.confirmedRaces ?? []).some(
    (r) =>
      !!r &&
      typeof r.distance === "string" &&
      LONG_ENOUGH.has(r.distance.toLowerCase()) &&
      typeof r.finish_time_seconds === "number" &&
      r.finish_time_seconds > 0 &&
      typeof r.date === "string" &&
      days(r.date) <= 56
  );
  if (recentConfirmedRace) return "high";

  // Fall through: legacy inference from training_logs.workout_type. Less
  // reliable than confirmed_races but still useful when an athlete hasn't
  // declared a race result yet. The structured race_result path above is
  // the long-term canonical source.
  const recentRace = request.workouts.some(
    (w) =>
      (w.type === "Race" || /race/i.test(w.type)) &&
      w.distanceMiles >= 6.0 && // ~10K floor
      days(w.date) <= 56
  );
  const mpWorkouts = request.workouts.filter(
    (w) =>
      /marathon\s*pace|tempo|mp\b/i.test(w.type) &&
      days(w.date) <= 42
  );
  if (recentRace || mpWorkouts.length >= 2) return "high";

  const thresholdSessions = request.workouts.filter(
    (w) =>
      /tempo|threshold|interval|speed/i.test(w.type) &&
      days(w.date) <= 42
  );
  if (thresholdSessions.length >= 1) return "medium";

  const sustainedVoiceEffort = request.voiceLogs.some(
    (v) =>
      v.pacesMentioned.length >= 2 ||
      /tempo|threshold|race\s*pace/i.test(v.notes)
  );
  if (sustainedVoiceEffort) return "medium";

  return "low";
}

/**
 * Half-window in seconds around a point estimate. Tier-driven multipliers
 * chosen so the high→medium gap on a 3:11 marathon is ~6 minutes, matching the
 * tune-up-race example in outputs/marathon-prediction-honesty.md.
 *
 * Exported for unit-test coverage (see index.test.ts).
 */
export function rangeFromTier(pointSeconds: number, tier: ConfidenceTier): number {
  if (pointSeconds <= 0) return 0;
  const pct = tier === "high" ? 0.015 : tier === "medium" ? 0.030 : 0.050;
  return Math.round(pointSeconds * pct);
}

// Parse "M:SS" or "H:MM:SS" into seconds. Returns 0 on parse failure.
function parseTimeToSeconds(t: string | undefined | null): number {
  if (!t || typeof t !== "string") return 0;
  const parts = t.split(":").map((p) => parseInt(p, 10));
  if (parts.some((p) => Number.isNaN(p))) return 0;
  if (parts.length === 2) return parts[0] * 60 + parts[1];
  if (parts.length === 3) return parts[0] * 3600 + parts[1] * 60 + parts[2];
  return 0;
}

// Map an LLM-emitted distance label to the camelCase key used in the
// `ranges` map on the output payload.
function rangeKeyForLabel(label: string): "mile" | "fiveK" | "tenK" | "half" | "marathon" | null {
  const u = label.toUpperCase();
  if (u === "MILE") return "mile";
  if (u === "5K") return "fiveK";
  if (u === "10K") return "tenK";
  if (u === "HALF") return "half";
  if (u === "MARATHON") return "marathon";
  return null;
}

function buildPrompt(request: PredictionRequest): string {
  const { workouts, voiceLogs, trainingPlan } = request;

  // Identify hard efforts for prediction
  const hardEfforts = workouts.filter(
    (w) =>
      w.type === "Speed Work" ||
      w.type === "Tempo" ||
      w.paceSecondsPerMile < 480 // faster than 8:00/mi
  );

  const workoutSummary = workouts
    .slice(0, 15)
    .map((w) => `${w.date}: ${w.type} ${w.distanceMiles.toFixed(1)}mi @ ${formatPace(w.paceSecondsPerMile)}`)
    .join("\n");

  const voiceLogSummary = voiceLogs
    .slice(0, 8)
    .map((v) => {
      const paces = v.pacesMentioned.length > 0 ? ` [Paces: ${v.pacesMentioned.join(", ")}]` : "";
      return `${v.date}: ${v.notes.slice(0, 150)}${paces}`;
    })
    .join("\n");

  const planContext = trainingPlan
    ? `Training for: ${trainingPlan.goalRace} in ${trainingPlan.goalTime} (${formatPace(trainingPlan.goalPacePerMile)} pace)\n`
    : "";

  return loadPrompt("fitness-predictor.v1", {
    planContext,
    totalWorkouts: workouts.length,
    hardEffortCount: hardEfforts.length,
    workoutSummary: workoutSummary || "No workouts",
    voiceLogSummary: voiceLogSummary || "No voice logs",
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const startTime = Date.now();

  try {
    // Verify authenticated user from JWT
    const userId = await getAuthenticatedUser(req);
    if (!userId) {
      return unauthorizedResponse(corsHeaders);
    }

    // Rate limiting
    if (isRateLimitEnabled()) {
      const rateLimit = await checkFeatureRateLimit(userId, "predictor");
      if (!rateLimit.allowed) {
        return new Response(
          JSON.stringify({ error: "Rate limit exceeded", remaining: 0, resetAt: rateLimit.resetAt.toISOString() }),
          { status: 429, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }
    }

    const request = (await req.json()) as PredictionRequest;
    const { workouts, voiceLogs } = request;

    if (!workouts || workouts.length === 0) {
      return new Response(
        JSON.stringify({
          error: "No workout data provided",
          message: "Log some runs to get predictions!",
        }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Input validation
    const arrErr = validateArrayLength(workouts, "workouts", 50);
    if (arrErr) return validationErrorResponse(arrErr, corsHeaders);

    for (const w of workouts) {
      if (w.distanceMiles < 0 || w.distanceMiles > 200) {
        return validationErrorResponse("Workout distance must be between 0 and 200 miles", corsHeaders);
      }
      if (w.durationMinutes < 0 || w.durationMinutes > 1440) {
        return validationErrorResponse("Workout duration must be between 0 and 1440 minutes", corsHeaders);
      }
    }

    // Get Claude API key
    const claudeKey = Deno.env.get("ANTHROPIC_API_KEY");
    if (!claudeKey) {
      return new Response(
        JSON.stringify({ error: "ANTHROPIC_API_KEY not configured" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Build prompt
    const prompt = buildPrompt(request);

    // Call Claude Haiku (fast & cheap)
    const anthropic = new Anthropic({ apiKey: claudeKey });

    const message = await anthropic.messages.create({
      model: "claude-3-5-haiku-20241022",
      max_tokens: 500,
      messages: [{ role: "user", content: prompt }],
    });

    // Extract response
    const responseText = message.content[0].type === "text" ? message.content[0].text : "";

    // Parse JSON response
    let result;
    try {
      const jsonMatch = responseText.match(/\{[\s\S]*\}/);
      if (!jsonMatch) throw new Error("No JSON found");
      result = JSON.parse(jsonMatch[0]);
    } catch {
      console.error("Failed to parse response:", responseText);
      result = {
        predictions: [],
        summary: "Unable to generate predictions. Please try again.",
        hardEffortCount: 0,
        confidence: "Low",
      };
    }

    // Determine confidence tier deterministically — the LLM does not get a vote.
    // Compute range half-windows for each prediction and attach them.
    const confidenceTier = computeConfidenceTier(request);
    const predictions = Array.isArray(result.predictions) ? result.predictions : [];
    const ranges: Record<string, number> = {};
    for (const p of predictions) {
      const key = rangeKeyForLabel(String(p?.distance ?? ""));
      if (!key) continue;
      const sec = parseTimeToSeconds(p?.time);
      const half = rangeFromTier(sec, confidenceTier);
      p.rangeSeconds = half;
      ranges[key] = half;
    }
    result.confidence_tier = confidenceTier;
    result.ranges = ranges;

    // Log usage
    if (userId) {
      const supabase = createClient(
        Deno.env.get("SUPABASE_URL")!,
        Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
      );

      await supabase.from("usage_tracking").insert({
        user_id: userId,
        feature: "fitness_predictor",
        model_used: "claude-3-5-haiku",
        input_tokens: message.usage.input_tokens,
        output_tokens: message.usage.output_tokens,
        cached: false,
      });
    }

    const processingTime = Date.now() - startTime;
    console.log(`Prediction completed in ${processingTime}ms`);

    return new Response(
      JSON.stringify({
        ...result,
        processingTime,
        model: "claude-3-5-haiku",
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (error) {
    console.error("Prediction error:", error);
    return internalErrorResponse(corsHeaders);
  }
});

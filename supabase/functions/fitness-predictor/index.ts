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

const corsHeaders = {
  "Access-Control-Allow-Origin": "",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface WorkoutData {
  date: string;
  distanceMiles: number;
  durationMinutes: number;
  paceSecondsPerMile: number;
  heartRateAvg?: number;
  type: string;
}

interface VoiceLogData {
  date: string;
  notes: string;
  mood?: string;
  pacesMentioned: string[];
}

interface TrainingPlanInfo {
  goalRace: string;
  goalTime: string;
  goalPacePerMile: number;
  currentWeek: number;
  totalWeeks: number;
}

interface PredictionRequest {
  workouts: WorkoutData[];
  voiceLogs: VoiceLogData[];
  trainingPlan?: TrainingPlanInfo;
  userId?: string;
}

function formatPace(secondsPerMile: number): string {
  if (secondsPerMile <= 0 || secondsPerMile > 1200) return "--:--";
  const totalSecs = Math.round(secondsPerMile);
  const mins = Math.floor(totalSecs / 60);
  const secs = totalSecs % 60;
  return `${mins}:${secs.toString().padStart(2, "0")}/mi`;
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

  // Build workout summary
  const workoutSummary = workouts
    .slice(0, 15)
    .map((w) => `${w.date}: ${w.type} ${w.distanceMiles.toFixed(1)}mi @ ${formatPace(w.paceSecondsPerMile)}`)
    .join("\n");

  // Build voice log summary with paces
  const voiceLogSummary = voiceLogs
    .slice(0, 8)
    .map((v) => {
      const paces = v.pacesMentioned.length > 0 ? ` [Paces: ${v.pacesMentioned.join(", ")}]` : "";
      return `${v.date}: ${v.notes.slice(0, 150)}${paces}`;
    })
    .join("\n");

  // Training plan context
  const planContext = trainingPlan
    ? `Training for: ${trainingPlan.goalRace} in ${trainingPlan.goalTime} (${formatPace(trainingPlan.goalPacePerMile)} pace)\n`
    : "";

  return `You are a running coach predicting race times based on training data.

${planContext}
RECENT WORKOUTS (${workouts.length} total, ${hardEfforts.length} hard efforts):
${workoutSummary || "No workouts"}

VOICE TRAINING LOGS:
${voiceLogSummary || "No voice logs"}

PREDICTION RULES:
- Use equivalent race performance methodology based on aerobic capacity
- Base predictions on HARD EFFORTS (tempo, threshold, intervals), not easy runs
- Easy runs are 60-90 sec/mi slower than race pace - don't use them directly
- Threshold/tempo pace ≈ 10K race pace + 10-20 seconds (about 3% slower)
- Voice log pace mentions are valuable - weight them heavily
- From 10K pace, calculate: Mile (~12% faster), 5K (~4% faster), Half (~5.5% slower), Marathon (~10.5% slower)

Respond ONLY with this JSON (no other text):
{
  "predictions": [
    {"distance": "MILE", "time": "M:SS", "pace": "M:SS/mi"},
    {"distance": "5K", "time": "MM:SS", "pace": "M:SS/mi"},
    {"distance": "10K", "time": "MM:SS", "pace": "M:SS/mi"},
    {"distance": "HALF", "time": "H:MM:SS", "pace": "M:SS/mi"},
    {"distance": "MARATHON", "time": "H:MM:SS", "pace": "M:SS/mi"}
  ],
  "summary": "Brief fitness assessment based on training data",
  "hardEffortCount": ${hardEfforts.length},
  "confidence": "High|Medium|Low"
}`;
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

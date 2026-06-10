// NOTE(adaptive-plan-1.6): Output prefers `target_pace_seconds_per_mile` and
// `pace_reference` on each step. Legacy `pacePercentage` / `paceSecondsPerKm`
// are still accepted for one release and converted by the shared resolver
// before the caller writes to scheduled_workouts.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { GoogleGenerativeAI } from "https://esm.sh/@google/generative-ai@0.24.0";
import { getAuthenticatedUser, unauthorizedResponse } from "../_shared/auth.ts";
import { checkFeatureRateLimit, isRateLimitEnabled } from "../_shared/rateLimit.ts";
import { validateLength, validationErrorResponse, internalErrorResponse } from "../_shared/validation.ts";
import { loadPrompt } from "../_shared/prompt-library.ts";
import { getOrBuildPaceProfile, resolveSteps } from "../_shared/resolve-pace.ts";

import { corsHeaders } from "../_shared/cors.ts";

interface ParseRequest {
  text: string;
  goalTimeSeconds?: number;
  raceDistance?: string;
  currentPhase?: string;
}

interface ImportedStep {
  stepType: string;
  durationType: string;
  durationValue: number;
  // Preferred fields.
  target_pace_seconds_per_mile?: number | null;
  target_pace_seconds_high?: number | null;
  pace_reference?: string | null;
  resolved_from_snapshot_id?: string | null;
  resolved_at?: string | null;
  // Legacy fields, kept for one release.
  pacePercentage: number | null;
  paceSecondsPerKm: number | null;
  paceSecondsPerKmHigh: number | null;
  notes: string | null;
}

interface ImportedDay {
  dayOfWeek: number;
  dayName: string;
  workoutType: string;
  name: string;
  description: string;
  totalDistanceMiles: number | null;
  estimatedDurationMinutes: number | null;
  steps: ImportedStep[];
}

function parseJsonResponse(text: string): unknown {
  // Strategy 1: Direct parse
  try {
    return JSON.parse(text);
  } catch { /* continue */ }

  // Strategy 2: Extract from markdown code block
  const codeBlockMatch = text.match(/```(?:json)?\s*([\s\S]*?)```/);
  if (codeBlockMatch) {
    try {
      return JSON.parse(codeBlockMatch[1].trim());
    } catch { /* continue */ }
  }

  // Strategy 3: Find first { to last }
  const firstBrace = text.indexOf("{");
  const lastBrace = text.lastIndexOf("}");
  if (firstBrace !== -1 && lastBrace > firstBrace) {
    try {
      return JSON.parse(text.substring(firstBrace, lastBrace + 1));
    } catch { /* continue */ }
  }

  throw new Error("Could not parse AI response as JSON");
}

function buildPrompt(text: string, goalTimeSeconds?: number, raceDistance?: string, currentPhase?: string): string {
  const raceContext = goalTimeSeconds
    ? `The athlete is training for a ${raceDistance || "marathon"} with a goal time of ${Math.floor(goalTimeSeconds / 3600)}:${String(Math.floor((goalTimeSeconds % 3600) / 60)).padStart(2, "0")}:${String(goalTimeSeconds % 60).padStart(2, "0")}. They are in the "${currentPhase || "support"}" phase.`
    : "No specific race goal provided. Use reasonable defaults for a recreational runner.";

  return loadPrompt("parse-training-week.v1", { raceContext, text });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // Verify authenticated user from JWT
    const userId = await getAuthenticatedUser(req);
    if (!userId) {
      return unauthorizedResponse(corsHeaders);
    }

    // Rate limiting
    if (isRateLimitEnabled()) {
      const rateLimit = await checkFeatureRateLimit(userId, "parse");
      if (!rateLimit.allowed) {
        return new Response(
          JSON.stringify({ error: "Rate limit exceeded", remaining: 0, resetAt: rateLimit.resetAt.toISOString() }),
          { status: 429, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }
    }

    const body: ParseRequest = await req.json();

    if (!body.text || body.text.trim().length === 0) {
      return new Response(
        JSON.stringify({ error: "Text is required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Input validation
    const lengthErr = validateLength(body.text, "text", 5000);
    if (lengthErr) return validationErrorResponse(lengthErr, corsHeaders);

    const geminiKey = Deno.env.get("GEMINI_API_KEY")!;
    const genAI = new GoogleGenerativeAI(geminiKey);
    const model = genAI.getGenerativeModel({
      model: "gemini-2.5-flash",
      generationConfig: {
        maxOutputTokens: 16384,
        temperature: 0.3,
        responseMimeType: "application/json",
        thinkingConfig: { thinkingBudget: 0 },
      },
    });

    const prompt = buildPrompt(body.text, body.goalTimeSeconds, body.raceDistance, body.currentPhase);

    let result;
    try {
      result = await model.generateContent(prompt);
    } catch (genError: any) {
      console.error("Gemini API error:", genError?.message || genError);
      return new Response(
        JSON.stringify({ error: "AI service error. Please try again." }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const responseText = result.response.text();

    let parsed: any;
    try {
      parsed = parseJsonResponse(responseText);
    } catch {
      console.error("JSON parse failed. First 300 chars:", responseText.substring(0, 300));
      return new Response(
        JSON.stringify({ error: "Could not parse AI response. Please try again." }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    if (!parsed.days || !Array.isArray(parsed.days)) {
      return new Response(
        JSON.stringify({ error: "AI response missing 'days' array" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Fetch the athlete's pace profile once so we can resolve references /
    // legacy fields into concrete seconds/mile on every emitted step.
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );
    const paceProfile = await getOrBuildPaceProfile(supabase, userId);

    // Validate and normalize
    const days = parsed.days.map((day: any) => ({
      dayOfWeek: day.dayOfWeek,
      dayName: day.dayName || ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"][day.dayOfWeek - 1],
      session: day.session ?? 1,
      workoutType: day.workoutType || "rest",
      name: day.name || "Rest Day",
      description: day.description || "",
      totalDistanceMiles: day.totalDistanceMiles ?? null,
      estimatedDurationMinutes: day.estimatedDurationMinutes ?? null,
      steps: resolveSteps(
        (day.steps || []).map((step: any, idx: number) => ({
          stepType: step.stepType || "active",
          durationType: step.durationType || "distance_miles",
          durationValue: step.durationValue || 0,
          target_pace_seconds_per_mile: step.target_pace_seconds_per_mile ?? null,
          target_pace_seconds_high: step.target_pace_seconds_high ?? null,
          pace_reference: step.pace_reference ?? null,
          resolved_from_snapshot_id: null,
          resolved_at: null,
          pacePercentage: step.pacePercentage ?? null,
          paceSecondsPerKm: step.paceSecondsPerKm ?? null,
          paceSecondsPerKmHigh: step.paceSecondsPerKmHigh ?? null,
          notes: step.notes ?? null,
          order: idx,
        })),
        paceProfile
      ),
    }));

    // Ensure all 7 days present (only add rest if NO entry exists for that day)
    for (let d = 1; d <= 7; d++) {
      if (!days.find((day: any) => day.dayOfWeek === d)) {
        const dayNames = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"];
        days.push({
          dayOfWeek: d,
          dayName: dayNames[d - 1],
          session: 1,
          workoutType: "rest",
          name: "Rest Day",
          description: "Recovery day",
          totalDistanceMiles: null,
          estimatedDurationMinutes: null,
          steps: [],
        });
      }
    }

    days.sort((a: any, b: any) => a.dayOfWeek - b.dayOfWeek || (a.session || 1) - (b.session || 1));

    return new Response(
      JSON.stringify({ days }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (error) {
    console.error("Parse training week error:", error);
    return internalErrorResponse(corsHeaders);
  }
});

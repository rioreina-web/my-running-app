/**
 * Injury Analysis Edge Function
 *
 * Uses Gemini 2.0 Flash to analyze a running injury with full training context.
 * Pulls from 7 data sources: injury record, training logs (90 days), profile,
 * injury history, active goals, injury memories, and co-occurring injuries.
 * Provides educational guidance — not medical advice.
 * Cost: ~$0.003 per analysis
 */

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { GoogleGenerativeAI } from "https://esm.sh/@google/generative-ai@0.21.0";
import { getAuthenticatedUser, unauthorizedResponse } from "../_shared/auth.ts";
import { checkFeatureRateLimit, isRateLimitEnabled } from "../_shared/rateLimit.ts";
import { validateUUID, validationErrorResponse, internalErrorResponse } from "../_shared/validation.ts";
import { compressTrainingContext, compressGoalsContext, estimateTokens } from "../_shared/context.ts";
import { getMemories, buildMemoryContext } from "../_shared/memory.ts";
import { buildInjuryContext } from "../_shared/injuries.ts";

import { corsHeaders } from "../_shared/cors.ts";

interface AnalysisRequest {
  injuryId: string;
}

/**
 * Format resolved injury history for the prompt.
 * Highlights recurring same-area injuries and summarizes others.
 */
function formatInjuryHistory(resolved: any[], currentBodyArea: string): string {
  if (!resolved || resolved.length === 0) return "";

  const sameArea = resolved.filter((r: any) => r.body_area === currentBodyArea);
  const otherArea = resolved.filter((r: any) => r.body_area !== currentBodyArea);

  const lines: string[] = [];

  if (sameArea.length > 0) {
    lines.push(`RECURRING: ${currentBodyArea} injured ${sameArea.length} time(s) before`);
    for (const r of sameArea.slice(0, 3)) {
      const duration =
        r.resolved_at && r.first_reported_at
          ? Math.floor(
              (new Date(r.resolved_at).getTime() - new Date(r.first_reported_at).getTime()) /
                (1000 * 60 * 60 * 24)
            )
          : "?";
      const sideLabel = r.side !== "unknown" ? `${r.side} ` : "";
      lines.push(`- ${sideLabel}${r.body_area} (sev ${r.severity}/10, took ${duration} days to resolve)`);
    }
  }

  if (otherArea.length > 0) {
    const otherSummary = otherArea
      .slice(0, 3)
      .map((r: any) => `${r.side !== "unknown" ? r.side + " " : ""}${r.body_area}`)
      .join(", ");
    lines.push(`Other past injuries: ${otherSummary}`);
  }

  return `\nINJURY HISTORY:\n${lines.join("\n")}`;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const startTime = Date.now();

  try {
    const userId = await getAuthenticatedUser(req);
    if (!userId) return unauthorizedResponse(corsHeaders);

    if (isRateLimitEnabled()) {
      const rateLimit = await checkFeatureRateLimit(userId, "injury_analysis");
      if (!rateLimit.allowed) {
        return new Response(
          JSON.stringify({ error: "Rate limit exceeded", remaining: 0, resetAt: rateLimit.resetAt.toISOString() }),
          { status: 429, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }
    }

    const { injuryId } = (await req.json()) as AnalysisRequest;

    const uuidErr = validateUUID(injuryId, "injuryId");
    if (uuidErr) return validationErrorResponse(uuidErr, corsHeaders);

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    // Phase 1: Fetch injury record — scoped to authenticated user to prevent IDOR
    const { data: injury, error: injuryError } = await supabase
      .from("injuries")
      .select("*")
      .eq("id", injuryId)
      .eq("user_id", userId)
      .single();

    if (injuryError || !injury) {
      return validationErrorResponse("Injury not found", corsHeaders);
    }

    // Phase 2: Fetch all context in parallel
    const ninetyDaysAgo = new Date(Date.now() - 90 * 24 * 60 * 60 * 1000).toISOString();

    const [profileResult, logsResult, injuryHistoryResult, goalsResult, memoriesResult, otherActiveResult] =
      await Promise.all([
        // 1. Expanded profile
        supabase
          .from("user_profiles")
          .select(
            "current_weekly_mileage, peak_weekly_mileage, years_running, easy_pace_per_mile, tempo_pace_per_mile, cross_training"
          )
          .eq("user_id", injury.user_id)
          .single(),

        // 2. Training logs — 90 days, 50 records
        supabase
          .from("training_logs")
          .select("workout_date, created_at, workout_distance_miles, workout_duration_minutes, mood, cleaned_notes")
          .eq("user_id", injury.user_id)
          .gte("created_at", ninetyDaysAgo)
          .order("created_at", { ascending: false })
          .limit(50),

        // 3. Resolved injuries (for recurring pattern detection)
        supabase
          .from("injuries")
          .select("body_area, side, severity, status, first_reported_at, resolved_at, description")
          .eq("user_id", injury.user_id)
          .eq("status", "resolved")
          .neq("id", injuryId)
          .order("resolved_at", { ascending: false })
          .limit(10),

        // 4. Active goals
        supabase
          .from("user_goals")
          .select("goal_title, target_date")
          .eq("status", "active")
          .order("target_date", { ascending: true })
          .limit(5),

        // 5. Injury memories
        getMemories(supabase, injury.user_id, ["injury"], 10),

        // 6. Other active injuries (co-occurring)
        supabase
          .from("injuries")
          .select("body_area, side, severity, status, first_reported_at, description")
          .eq("user_id", injury.user_id)
          .in("status", ["active", "monitoring"])
          .neq("id", injuryId)
          .order("severity", { ascending: false })
          .limit(5),
      ]);

    const profile = profileResult.data;

    // Format all context sections
    const daysSinceReport = Math.floor(
      (Date.now() - new Date(injury.first_reported_at).getTime()) / (1000 * 60 * 60 * 24)
    );

    const trainingContext = compressTrainingContext(logsResult.data || []);
    const injuryHistoryContext = formatInjuryHistory(injuryHistoryResult.data || [], injury.body_area);
    const goalsContext = compressGoalsContext(goalsResult.data || []);
    const memoriesContext = buildMemoryContext(memoriesResult || []);
    const otherInjuriesContext = buildInjuryContext(otherActiveResult.data || []);

    const sideLabel = injury.side !== "unknown" ? `${injury.side} ` : "";

    const prompt = `You are a sports medicine consultant providing educational analysis of a running injury.

IMPORTANT MEDICAL DISCLAIMER: This analysis is for educational purposes only. It is NOT a medical diagnosis. The runner should consult a qualified healthcare professional for proper diagnosis and treatment.

IMPORTANT: Never mention specific coaching methodologies, frameworks, or coach names in your response.

If the runner has a history of this same injury, emphasize the recurring pattern and what that implies for recovery approach.

INJURY DETAILS:
- Body area: ${sideLabel}${injury.body_area}
- Self-reported severity: ${injury.severity}/10
- First reported: ${daysSinceReport} days ago
- Current status: ${injury.status}
- Description: ${injury.description || "No description provided"}

RUNNER PROFILE:
- Weekly mileage: ${profile?.current_weekly_mileage || "unknown"} (peak: ${profile?.peak_weekly_mileage || "unknown"})
- Years running: ${profile?.years_running || "unknown"}
- Easy pace: ${profile?.easy_pace_per_mile || "unknown"}, Tempo: ${profile?.tempo_pace_per_mile || "unknown"}
- Cross-training: ${profile?.cross_training?.join(", ") || "none listed"}

RECENT TRAINING (last 90 days):
${trainingContext || "No recent training data"}
${injuryHistoryContext}${otherInjuriesContext}${goalsContext ? `\nUPCOMING GOALS:\n${goalsContext}` : ""}${memoriesContext ? `\n${memoriesContext}` : ""}

Provide a comprehensive analysis in this exact JSON format:
{
  "likely_causes": ["cause1", "cause2", "cause3"],
  "risk_level": "low" | "moderate" | "high",
  "recovery_timeline_days": { "optimistic": number, "typical": number, "conservative": number },  // SEE RECOVERY TIMELINE RULES BELOW
  "recommended_actions": [
    { "action": "string", "priority": "immediate" | "short_term" | "ongoing", "detail": "string" }
  ],
  "training_modifications": [
    { "modification": "string", "duration": "string", "rationale": "string" }
  ],
  "warning_signs": ["sign that means seek medical attention immediately"],
  "return_to_running_criteria": ["criterion1", "criterion2"],
  "is_recurring": true | false,
  "goal_impact": "brief note on how this affects their goals, if any" | null,
  "summary": "2-3 sentence overview of the injury assessment",
  "disclaimer": "This is educational information only, not a medical diagnosis. Please consult a healthcare professional for proper evaluation and treatment."
}

RECOVERY TIMELINE RULES:
- All timelines are rough estimates only and vary significantly by individual.
- For bone injuries (stress fractures, stress reactions): ALWAYS use conservative end. Minimum 6 weeks for stress reactions, 8-12 weeks for stress fractures. Never give optimistic timelines shorter than 4 weeks for bone injuries.
- Always state that timelines require professional evaluation and may be longer than estimated.
- Do not give specific return-to-run dates. Give ranges and emphasize gradual return protocols.

Respond ONLY with the JSON object, no markdown code blocks, no extra text.`;

    const geminiKey = Deno.env.get("GEMINI_API_KEY")!;
    const genAI = new GoogleGenerativeAI(geminiKey);
    const model = genAI.getGenerativeModel({
      model: "gemini-2.0-flash",
      generationConfig: { maxOutputTokens: 1500, temperature: 0.3 },
    });

    const result = await model.generateContent(prompt);
    const responseText = result.response.text();

    // Parse JSON response
    let analysis;
    try {
      // Strategy 1: Direct parse
      analysis = JSON.parse(responseText);
    } catch {
      try {
        // Strategy 2: Extract from code block
        const codeBlockMatch = responseText.match(/```(?:json)?\s*([\s\S]*?)```/);
        if (codeBlockMatch) {
          analysis = JSON.parse(codeBlockMatch[1].trim());
        } else {
          // Strategy 3: Find first { to last }
          const jsonMatch = responseText.match(/\{[\s\S]*\}/);
          if (!jsonMatch) throw new Error("No JSON found");
          analysis = JSON.parse(jsonMatch[0]);
        }
      } catch {
        console.error("Failed to parse analysis response:", responseText.slice(0, 500));
        analysis = {
          summary: "Unable to generate analysis. Please try again.",
          disclaimer:
            "This is educational information only, not a medical diagnosis. Please consult a healthcare professional for proper evaluation and treatment.",
          error: true,
        };
      }
    }

    // Store analysis result on the injury record (scoped to user)
    await supabase
      .from("injuries")
      .update({
        ai_analysis: analysis,
        ai_analysis_at: new Date().toISOString(),
      })
      .eq("id", injuryId)
      .eq("user_id", userId);

    // Log usage
    await supabase.from("usage_tracking").insert({
      user_id: userId,
      feature: "injury_analysis",
      model_used: "gemini-2.0-flash",
      input_tokens: estimateTokens(prompt),
      output_tokens: estimateTokens(responseText),
      cached: false,
    });

    const processingTime = Date.now() - startTime;
    console.log(`Injury analysis completed in ${processingTime}ms`);

    return new Response(
      JSON.stringify({
        analysis,
        injuryId,
        processingTime,
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (error) {
    console.error("Injury analysis error:", error);
    return internalErrorResponse(corsHeaders);
  }
});

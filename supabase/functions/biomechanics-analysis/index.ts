/**
 * Biomechanics Analysis Edge Function
 *
 * Uses Gemini 2.0 Flash to analyze running form from 3D pose estimation data.
 * Evaluates joint angles, foot strike pattern, shank angle, and ROM against
 * normative ranges. Incorporates runner profile and injury context.
 * Cost: ~$0.003 per analysis
 */

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { GoogleGenerativeAI } from "https://esm.sh/@google/generative-ai@0.21.0";
import { getAuthenticatedUser, unauthorizedResponse } from "../_shared/auth.ts";
import { checkFeatureRateLimit, isRateLimitEnabled } from "../_shared/rateLimit.ts";
import { validateUUID, validationErrorResponse, internalErrorResponse } from "../_shared/validation.ts";
import { compressTrainingContext, estimateTokens } from "../_shared/context.ts";

import { corsHeaders } from "../_shared/cors.ts";

interface AnalysisRequest {
  analysisId: string;
}

function formatJointAngle(label: string, data: any, normalRange: string): string {
  if (!data) return "";
  return `- ${label}: mean ${data.mean_angle?.toFixed(1)}° (range: ${data.min_angle?.toFixed(1)}°–${data.max_angle?.toFixed(1)}°, ROM: ${data.range_of_motion?.toFixed(1)}°) [Normal: ${normalRange}]`;
}

function formatShankAngle(label: string, data: any): string {
  if (!data) return "";
  const atContact = data.at_initial_contact != null
    ? `at contact: ${data.at_initial_contact.toFixed(1)}°`
    : "contact angle unavailable";
  return `- ${label}: ${atContact}, mean ${data.mean_angle?.toFixed(1)}° [Ideal: < 5° past vertical]`;
}

function formatGaitMetrics(data: any): string {
  if (!data) return "- Ground contact time: not available";
  const lines: string[] = [];
  if (data.ground_contact_time != null) {
    lines.push(`- Average ground contact time: ${data.ground_contact_time.toFixed(0)} ms [Typical: 200-300 ms]`);
  }
  if (data.ground_contact_time_left != null && data.ground_contact_time_right != null) {
    lines.push(`- Left GCT: ${data.ground_contact_time_left.toFixed(0)} ms, Right GCT: ${data.ground_contact_time_right.toFixed(0)} ms`);
  }
  if (data.ground_contact_balance != null) {
    const deviation = Math.abs(data.ground_contact_balance - 50);
    const status = deviation < 2 ? "balanced" : deviation < 5 ? "slight asymmetry" : "significant asymmetry";
    lines.push(`- L/R balance: ${data.ground_contact_balance.toFixed(1)}% left / ${(100 - data.ground_contact_balance).toFixed(1)}% right (${status}) [Ideal: close to 50/50]`);
  }
  return lines.length > 0 ? lines.join("\n") : "- Ground contact time: not available";
}

function formatFootStrike(data: any): string {
  if (!data) return "- Foot strike: not detected";
  const confidence = data.confidence != null ? ` (${(data.confidence * 100).toFixed(0)}% confidence)` : "";
  const ankle = data.ankle_angle_at_contact != null ? `, ankle at contact: ${data.ankle_angle_at_contact.toFixed(1)}°` : "";
  const shank = data.shank_angle_at_contact != null ? `, shank at contact: ${data.shank_angle_at_contact.toFixed(1)}°` : "";
  const descent = data.ankle_descent_angle != null ? `, foot approach angle: ${data.ankle_descent_angle.toFixed(1)}° [<45°=heel (forward reach), 45-60°=midfoot, >60°=forefoot (vertical drop)]` : "";
  return `- Foot strike: ${data.pattern}${confidence}${ankle}${shank}${descent}`;
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
      const rateLimit = await checkFeatureRateLimit(userId, "biomechanics_analysis");
      if (!rateLimit.allowed) {
        return new Response(
          JSON.stringify({ error: "Rate limit exceeded", remaining: 0, resetAt: rateLimit.resetAt.toISOString() }),
          { status: 429, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }
    }

    const { analysisId } = (await req.json()) as AnalysisRequest;

    const uuidErr = validateUUID(analysisId, "analysisId");
    if (uuidErr) return validationErrorResponse(uuidErr, corsHeaders);

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    // Fetch the biomechanics analysis record — always enforce user_id ownership
    const { data: analysis, error: analysisError } = await supabase
      .from("biomechanics_analyses")
      .select("*")
      .eq("id", analysisId)
      .eq("user_id", userId)
      .single();

    if (analysisError || !analysis) {
      console.error("Analysis lookup failed:", analysisError?.message, "userId:", userId, "analysisId:", analysisId);
      return validationErrorResponse("Analysis not found", corsHeaders);
    }

    const actualUserId = userId;

    // Fetch context in parallel
    const thirtyDaysAgo = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString();

    const [profileResult, logsResult, injuriesResult, previousAnalysisResult] =
      await Promise.all([
        // Runner profile
        supabase
          .from("user_profiles")
          .select("current_weekly_mileage, peak_weekly_mileage, years_running, easy_pace_per_mile, tempo_pace_per_mile, cross_training")
          .eq("user_id", actualUserId)
          .single(),

        // Recent training logs (30 days)
        supabase
          .from("training_logs")
          .select("workout_date, created_at, workout_distance_miles, workout_duration_minutes, mood, cleaned_notes")
          .eq("user_id", actualUserId)
          .gte("created_at", thirtyDaysAgo)
          .order("created_at", { ascending: false })
          .limit(30),

        // Active injuries
        supabase
          .from("injuries")
          .select("body_area, side, severity, status, description")
          .eq("user_id", actualUserId)
          .in("status", ["active", "monitoring"])
          .order("severity", { ascending: false })
          .limit(5),

        // Most recent previous analysis (for comparison)
        supabase
          .from("biomechanics_analyses")
          .select("joint_angles, foot_strike, gait_metrics, recorded_at, view_angle")
          .eq("user_id", actualUserId)
          .eq("status", "completed")
          .neq("id", analysisId)
          .order("recorded_at", { ascending: false })
          .limit(1),
      ]);

    const profile = profileResult.data;
    const jointAngles = analysis.joint_angles;
    const footStrike = analysis.foot_strike;
    const gaitMetrics = analysis.gait_metrics;

    // Build joint angles context
    const jointLines: string[] = [];
    if (jointAngles) {
      jointLines.push(formatJointAngle("Left Hip", jointAngles.hip_left, "40–55° flexion"));
      jointLines.push(formatJointAngle("Right Hip", jointAngles.hip_right, "40–55° flexion"));
      jointLines.push(formatJointAngle("Left Knee", jointAngles.knee_left, "90–120° peak swing"));
      jointLines.push(formatJointAngle("Right Knee", jointAngles.knee_right, "90–120° peak swing"));
      jointLines.push(formatJointAngle("Left Ankle", jointAngles.ankle_left, "15–25° dorsiflexion"));
      jointLines.push(formatJointAngle("Right Ankle", jointAngles.ankle_right, "15–25° dorsiflexion"));
      jointLines.push(formatShankAngle("Left Shank", jointAngles.shank_left));
      jointLines.push(formatShankAngle("Right Shank", jointAngles.shank_right));
      if (jointAngles.shoulder_rotation) {
        const sr = jointAngles.shoulder_rotation;
        jointLines.push(`- Shoulder Rotation: mean ${sr.mean_rotation?.toFixed(1)}°, peak ${sr.peak_rotation?.toFixed(1)}°, ROM ${sr.range_of_motion?.toFixed(1)}° [Normal: 5-15° ROM]`);
      }
    }

    // Build injury context
    const injuries = injuriesResult.data || [];
    const injuryContext = injuries.length > 0
      ? injuries.map((i: any) => `- ${i.side !== "unknown" ? i.side + " " : ""}${i.body_area} (severity ${i.severity}/10, ${i.status})`).join("\n")
      : "No active injuries";

    // Build previous analysis comparison
    const prevAnalysis = previousAnalysisResult.data?.[0];
    let comparisonContext = "";
    if (prevAnalysis) {
      const daysAgo = Math.floor(
        (Date.now() - new Date(prevAnalysis.recorded_at).getTime()) / (1000 * 60 * 60 * 24)
      );
      const prevJoints = prevAnalysis.joint_angles;
      const prevFS = prevAnalysis.foot_strike;
      comparisonContext = `\nPREVIOUS ANALYSIS (${daysAgo} days ago, ${prevAnalysis.view_angle} view):`;
      if (prevJoints?.hip_left) comparisonContext += `\n- Hip ROM: ${prevJoints.hip_left.range_of_motion?.toFixed(1)}° (L)`;
      if (prevJoints?.knee_left) comparisonContext += `, Knee ROM: ${prevJoints.knee_left.range_of_motion?.toFixed(1)}° (L)`;
      if (prevJoints?.ankle_left) comparisonContext += `, Ankle ROM: ${prevJoints.ankle_left.range_of_motion?.toFixed(1)}° (L)`;
      if (prevFS) comparisonContext += `\n- Previous foot strike: ${prevFS.pattern}`;
      const prevGait = prevAnalysis.gait_metrics;
      if (prevGait?.ground_contact_time) comparisonContext += `\n- Previous GCT: ${prevGait.ground_contact_time.toFixed(0)} ms`;
      if (prevGait?.ground_contact_balance) comparisonContext += `, balance: ${prevGait.ground_contact_balance.toFixed(1)}% L`;
    }

    const trainingContext = compressTrainingContext(logsResult.data || []);

    const prompt = `You are a sports biomechanics analyst providing educational analysis of running form based on smartphone-based 3D pose estimation.

PACE DIRECTION: In running, LOWER pace number = FASTER. 5:00/mi is fast, 9:00/mi is slow. "Too fast" means a LOWER number than prescribed. "Too slow" means a HIGHER number. Running slower than easy pace on recovery days is good.

IMPORTANT DISCLAIMERS:
- This analysis is for educational purposes only, NOT a clinical assessment
- Smartphone pose estimation has ~4-7° mean absolute error compared to lab-based motion capture
- The runner should consult a qualified biomechanist or physical therapist for clinical evaluation
- Never mention specific coaching methodologies, frameworks, or coach names

ANALYSIS DATA:
- View angle: ${analysis.view_angle}${analysis.notes?.startsWith("Combined from") ? `\n- Multi-angle capture: ${analysis.notes}` : ""}
- Duration: ${analysis.duration_seconds?.toFixed(1)}s, ${analysis.frame_count} frames at ${analysis.fps?.toFixed(0)} fps

JOINT ANGLES:
${jointLines.filter(l => l).join("\n") || "No joint angle data available"}

FOOT STRIKE & LANDING:
${formatFootStrike(footStrike)}

GAIT METRICS:
${formatGaitMetrics(gaitMetrics)}

RUNNER PROFILE:
- Weekly mileage: ${profile?.current_weekly_mileage || "unknown"} (peak: ${profile?.peak_weekly_mileage || "unknown"})
- Years running: ${profile?.years_running || "unknown"}
- Easy pace: ${profile?.easy_pace_per_mile || "unknown"}, Tempo: ${profile?.tempo_pace_per_mile || "unknown"}
- Cross-training: ${profile?.cross_training?.join(", ") || "none listed"}

ACTIVE INJURIES:
${injuryContext}

RECENT TRAINING (30 days):
${trainingContext || "No recent training data"}
${comparisonContext}

Analyze the running form and provide your assessment in this exact JSON format:
{
  "overall_score": <1-10 integer>,
  "form_assessment": "<2-3 sentence summary of running form quality>",
  "findings": [
    {
      "area": "<body area or metric name>",
      "observation": "<what was observed>",
      "severity": "normal" | "minor" | "moderate" | "significant",
      "recommendation": "<specific actionable recommendation>"
    }
  ],
  "injury_risk_factors": ["<biomechanical factor that could contribute to injury>"],
  "improvement_priorities": [
    {
      "priority": <1-3>,
      "area": "<area to improve>",
      "drill": "<specific drill or exercise name>",
      "explanation": "<why this will help>"
    }
  ],
  "comparison_notes": "<notes on changes from previous analysis, if available>" | null,
  "disclaimer": "This biomechanics analysis uses smartphone-based pose estimation and is for educational purposes only. Results have ~4-7° accuracy compared to lab-based systems. Consult a qualified professional for clinical gait analysis."
}

Respond ONLY with the JSON object, no markdown code blocks, no extra text.`;

    const geminiKey = Deno.env.get("GEMINI_API_KEY")!;
    const genAI = new GoogleGenerativeAI(geminiKey);
    const model = genAI.getGenerativeModel({
      model: "gemini-2.0-flash",
      generationConfig: { maxOutputTokens: 2000, temperature: 0.3 },
    });

    const result = await model.generateContent(prompt);
    const responseText = result.response.text();

    // Parse JSON response
    let aiAnalysis;
    try {
      aiAnalysis = JSON.parse(responseText);
    } catch {
      try {
        const codeBlockMatch = responseText.match(/```(?:json)?\s*([\s\S]*?)```/);
        if (codeBlockMatch) {
          aiAnalysis = JSON.parse(codeBlockMatch[1].trim());
        } else {
          const jsonMatch = responseText.match(/\{[\s\S]*\}/);
          if (!jsonMatch) throw new Error("No JSON found");
          aiAnalysis = JSON.parse(jsonMatch[0]);
        }
      } catch {
        console.error("Failed to parse biomechanics analysis:", responseText.slice(0, 500));
        aiAnalysis = {
          overall_score: null,
          form_assessment: "Unable to generate analysis. Please try again.",
          disclaimer: "This biomechanics analysis uses smartphone-based pose estimation and is for educational purposes only.",
          error: true,
        };
      }
    }

    // Store analysis result
    await supabase
      .from("biomechanics_analyses")
      .update({
        ai_analysis: aiAnalysis,
        ai_analysis_at: new Date().toISOString(),
      })
      .eq("id", analysisId);

    // Log usage
    await supabase.from("usage_tracking").insert({
      user_id: userId,
      feature: "biomechanics_analysis",
      model_used: "gemini-2.0-flash",
      input_tokens: estimateTokens(prompt),
      output_tokens: estimateTokens(responseText),
      cached: false,
    });

    const processingTime = Date.now() - startTime;
    console.log(`Biomechanics analysis completed in ${processingTime}ms`);

    return new Response(
      JSON.stringify({
        analysis: aiAnalysis,
        analysisId,
        processingTime,
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (error) {
    console.error("Biomechanics analysis error:", error);
    return internalErrorResponse(corsHeaders);
  }
});

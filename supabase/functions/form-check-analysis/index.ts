/**
 * Form Check Analysis Edge Function
 *
 * Qualitative running form analysis using pose data + AI.
 * Focuses on imbalances, posture, foot strike, and compensation patterns.
 * Returns narrative findings rather than numeric metrics.
 * Cost: ~$0.003 per analysis
 */

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { GoogleGenerativeAI } from "https://esm.sh/@google/generative-ai@0.21.0";
import { getAuthenticatedUser, unauthorizedResponse } from "../_shared/auth.ts";
import { checkFeatureRateLimit, isRateLimitEnabled } from "../_shared/rateLimit.ts";
import { validateUUID, validationErrorResponse, internalErrorResponse } from "../_shared/validation.ts";
import { compressTrainingContext, estimateTokens } from "../_shared/context.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface FormCheckRequest {
  formCheckId: string;
}

/**
 * Convert flat pose data into human-readable qualitative descriptions.
 * The AI should NOT see raw degree values — only qualitative labels.
 */
function formatPoseData(data: any): string {
  if (!data) return "No pose data available.";

  const lines: string[] = [];

  // Hip ROM asymmetry
  if (data.hip_rom_left != null && data.hip_rom_right != null) {
    const diff = Math.abs(data.hip_rom_left - data.hip_rom_right);
    const side = data.hip_rom_left > data.hip_rom_right ? "left" : "right";
    if (diff > 8) {
      lines.push(`- Hip range of motion: significant asymmetry (${side} side notably larger)`);
    } else if (diff > 5) {
      lines.push(`- Hip range of motion: moderate asymmetry (${side} side somewhat larger)`);
    } else if (diff > 2) {
      lines.push(`- Hip range of motion: mild asymmetry (${side} side slightly larger)`);
    } else {
      lines.push(`- Hip range of motion: symmetric between left and right`);
    }
  } else if (data.hip_rom_left != null || data.hip_rom_right != null) {
    lines.push(`- Hip range of motion: only one side measured`);
  }

  // Knee ROM asymmetry
  if (data.knee_rom_left != null && data.knee_rom_right != null) {
    const diff = Math.abs(data.knee_rom_left - data.knee_rom_right);
    const side = data.knee_rom_left > data.knee_rom_right ? "left" : "right";
    if (diff > 10) {
      lines.push(`- Knee range of motion: significant asymmetry (${side} side notably larger)`);
    } else if (diff > 5) {
      lines.push(`- Knee range of motion: moderate asymmetry (${side} side somewhat larger)`);
    } else if (diff > 2) {
      lines.push(`- Knee range of motion: mild asymmetry (${side} side slightly larger)`);
    } else {
      lines.push(`- Knee range of motion: symmetric between left and right`);
    }
  }

  // Ankle ROM asymmetry
  if (data.ankle_rom_left != null && data.ankle_rom_right != null) {
    const diff = Math.abs(data.ankle_rom_left - data.ankle_rom_right);
    const side = data.ankle_rom_left > data.ankle_rom_right ? "left" : "right";
    if (diff > 8) {
      lines.push(`- Ankle range of motion: significant asymmetry (${side} side notably larger — may indicate restricted dorsiflexion on the other side)`);
    } else if (diff > 5) {
      lines.push(`- Ankle range of motion: moderate asymmetry (${side} side somewhat larger)`);
    } else if (diff > 2) {
      lines.push(`- Ankle range of motion: mild asymmetry (${side} side slightly larger)`);
    } else {
      lines.push(`- Ankle range of motion: symmetric between left and right`);
    }
  } else if (data.ankle_rom_left != null || data.ankle_rom_right != null) {
    lines.push(`- Ankle range of motion: only one side measured`);
  }

  // Shoulder rotation
  if (data.shoulder_rotation_rom != null) {
    const rom = data.shoulder_rotation_rom;
    if (rom < 3) {
      lines.push(`- Shoulder counter-rotation: very limited (stiff upper body)`);
    } else if (rom < 5) {
      lines.push(`- Shoulder counter-rotation: somewhat limited`);
    } else if (rom <= 15) {
      lines.push(`- Shoulder counter-rotation: normal range`);
    } else if (rom <= 20) {
      lines.push(`- Shoulder counter-rotation: slightly excessive`);
    } else {
      lines.push(`- Shoulder counter-rotation: excessive (wasted energy in rotation)`);
    }
  }

  // Foot strike — enriched with severity + connection to overstriding
  if (data.foot_strike_pattern) {
    const conf = data.foot_strike_confidence != null
      ? data.foot_strike_confidence > 0.7 ? "high" : data.foot_strike_confidence > 0.4 ? "moderate" : "low"
      : null;

    const pattern = data.foot_strike_pattern;
    const hvf = data.heel_vs_forefoot; // meters, negative = heel lower
    const shank = data.shank_angle_at_contact; // degrees at contact
    const contacts = data.contact_count;

    // Describe the pattern with severity
    if (pattern === "rearfoot") {
      if (hvf != null && hvf < -0.03) {
        lines.push(`- Foot strike: pronounced heel strike (heel landing well before forefoot)`);
      } else if (hvf != null && hvf < -0.015) {
        lines.push(`- Foot strike: moderate heel strike`);
      } else {
        lines.push(`- Foot strike: mild heel strike (close to midfoot)`);
      }
    } else if (pattern === "midfoot") {
      lines.push(`- Foot strike: midfoot (heel and forefoot landing nearly together — efficient pattern)`);
    } else if (pattern === "forefoot") {
      if (hvf != null && hvf > 0.025) {
        lines.push(`- Foot strike: pronounced forefoot strike (landing on toes)`);
      } else {
        lines.push(`- Foot strike: forefoot strike`);
      }
    } else {
      lines.push(`- Foot strike pattern: ${pattern}`);
    }

    // Connection to overstriding via shank angle
    if (shank != null) {
      if (pattern === "rearfoot" && shank > 10) {
        lines.push(`- Foot strike + landing: heel striking combined with overstriding — foot is landing well ahead of the body, which increases braking forces`);
      } else if (pattern === "rearfoot" && shank <= 5) {
        lines.push(`- Foot strike + landing: heel strike but foot is landing close to under the body — less impact concern than a typical heel strike`);
      } else if (pattern === "midfoot" && shank > 8) {
        lines.push(`- Foot strike + landing: midfoot contact but still reaching forward — there is room to shorten the stride`);
      }
    }

    // Confidence + sample size context
    const parts: string[] = [];
    if (conf) parts.push(`${conf} confidence`);
    if (contacts != null) parts.push(`based on ${contacts} ground contact${contacts === 1 ? "" : "s"}`);
    if (parts.length > 0) {
      lines.push(`- Foot strike detection: ${parts.join(", ")}`);
    }
  }

  // Ground contact time balance
  if (data.gct_balance != null) {
    const deviation = Math.abs(data.gct_balance - 50);
    if (deviation > 5) {
      const heavySide = data.gct_balance > 50 ? "left" : "right";
      lines.push(`- Ground contact time: significant asymmetry (${heavySide} foot spending notably more time on ground)`);
    } else if (deviation > 2) {
      const heavySide = data.gct_balance > 50 ? "left" : "right";
      lines.push(`- Ground contact time: slight asymmetry (${heavySide} foot spending slightly more time on ground)`);
    } else {
      lines.push(`- Ground contact time: balanced between left and right`);
    }
  } else if (data.gct_left != null || data.gct_right != null) {
    lines.push(`- Ground contact time: only one side measured`);
  }

  // Trunk lean / posture (5-10° forward lean is optimal for running)
  if (data.avg_trunk_lean != null) {
    const lean = data.avg_trunk_lean;
    if (lean > 15) {
      lines.push(`- Trunk posture: excessive forward lean (may indicate hip flexor tightness or fatigue)`);
    } else if (lean > 10) {
      lines.push(`- Trunk posture: slightly more forward lean than ideal`);
    } else if (lean >= 5) {
      lines.push(`- Trunk posture: good forward lean (optimal range for running)`);
    } else if (lean >= 2) {
      lines.push(`- Trunk posture: nearly upright (a slight forward lean from the ankles can improve efficiency)`);
    } else {
      lines.push(`- Trunk posture: very upright (most runners benefit from a slight forward lean)`);
    }
  }

  // Head forward offset
  if (data.head_forward_offset != null) {
    const offset = data.head_forward_offset;
    if (offset > 0.08) {
      lines.push(`- Head position: notably forward of shoulders (forward head posture)`);
    } else if (offset > 0.04) {
      lines.push(`- Head position: slightly forward of shoulders`);
    } else if (offset > -0.02) {
      lines.push(`- Head position: neutral alignment with shoulders`);
    } else {
      lines.push(`- Head position: behind shoulders (unusual, may indicate leaning back)`);
    }
  }

  // Arm swing symmetry (elbow flexion angle ROM, frontal/posterior views only)
  // Measured from elbow angle oscillation range — more stable than wrist tracking.
  // Only computed when both arms are fully visible (not from side views).
  if (data.arm_swing_symmetry != null) {
    const sym = data.arm_swing_symmetry;
    if (sym > 0.75) {
      lines.push(`- Arm swing: symmetric (measured from elbow flexion, both arms visible)`);
    } else if (sym > 0.55) {
      lines.push(`- Arm swing: mild asymmetry in elbow drive (one arm has less range of motion than the other)`);
    } else {
      lines.push(`- Arm swing: notable asymmetry in elbow drive (significant difference in arm swing range — may indicate shoulder restriction, habit, or compensation)`);
    }
  }

  // Shank angle / overstriding
  if (data.shank_at_contact_left != null || data.shank_at_contact_right != null) {
    const left = data.shank_at_contact_left;
    const right = data.shank_at_contact_right;
    const shank = left ?? right;

    if (shank != null) {
      if (shank > 10) {
        lines.push(`- Landing mechanics: overstriding (foot landing well ahead of center of mass)`);
      } else if (shank > 5) {
        lines.push(`- Landing mechanics: mild overstriding`);
      } else {
        lines.push(`- Landing mechanics: foot landing close to under the body (good)`);
      }

      // L/R shank asymmetry
      if (left != null && right != null) {
        const diff = Math.abs(left - right);
        if (diff > 5) {
          const side = left > right ? "left" : "right";
          lines.push(`- Landing asymmetry: ${side} foot reaching notably further forward than the other`);
        }
      }
    }
  }

  // Cadence
  if (data.cadence != null) {
    const spm = data.cadence;
    if (spm < 160) {
      lines.push(`- Cadence: ~${Math.round(spm)} steps/min (low — increasing cadence by 5-10% can reduce overstriding and impact forces)`);
    } else if (spm < 170) {
      lines.push(`- Cadence: ~${Math.round(spm)} steps/min (moderate — within normal recreational range)`);
    } else if (spm <= 185) {
      lines.push(`- Cadence: ~${Math.round(spm)} steps/min (good — efficient range for most runners)`);
    } else {
      lines.push(`- Cadence: ~${Math.round(spm)} steps/min (high — typical for faster paces or shorter runners)`);
    }
  }

  // Fatigue indicators (early vs late form comparison)
  if (data.trunk_lean_early != null && data.trunk_lean_late != null) {
    const diff = data.trunk_lean_late - data.trunk_lean_early;
    if (diff > 3) {
      lines.push(`- Fatigue signal: trunk lean increased notably from start to end of clip (posture breaking down)`);
    } else if (diff > 1.5) {
      lines.push(`- Fatigue signal: slight increase in trunk lean from start to end (mild form degradation)`);
    } else if (diff < -1.5) {
      lines.push(`- Form consistency: trunk lean actually decreased over the clip (warming up or adjusting)`);
    } else {
      lines.push(`- Form consistency: trunk posture stayed consistent throughout the clip`);
    }
  }
  if (data.cadence_early != null && data.cadence_late != null) {
    const diff = data.cadence_late - data.cadence_early;
    if (diff < -8) {
      lines.push(`- Fatigue signal: cadence dropped notably from start to end (~${Math.round(data.cadence_early)} → ~${Math.round(data.cadence_late)} spm)`);
    } else if (diff < -4) {
      lines.push(`- Fatigue signal: slight cadence drop from start to end`);
    }
    // Don't report increases — that's usually just warming up
  }

  return lines.length > 0 ? lines.join("\n") : "Limited pose data available.";
}

/**
 * Build a list of which metric areas were actually measured (non-null).
 * Used to constrain the AI to only discuss areas with data.
 */
function measuredAreas(data: any): string[] {
  if (!data) return [];
  const areas: string[] = [];
  if (data.hip_rom_left != null || data.hip_rom_right != null) areas.push("Hip Stability");
  if (data.knee_rom_left != null || data.knee_rom_right != null) areas.push("Knee Tracking");
  if (data.ankle_rom_left != null || data.ankle_rom_right != null) areas.push("Ankle Mobility");
  if (data.foot_strike_pattern != null) areas.push("Foot Strike");
  if (data.avg_trunk_lean != null || data.head_forward_offset != null) areas.push("Posture");
  if (data.arm_swing_symmetry != null) areas.push("Arm Swing");
  if (data.shank_at_contact_left != null || data.shank_at_contact_right != null) areas.push("Overstriding");
  if (data.gct_left != null || data.gct_right != null || data.gct_balance != null) areas.push("Ground Contact");
  if (data.cadence != null) areas.push("Cadence");
  if (data.trunk_lean_early != null && data.trunk_lean_late != null) areas.push("Fatigue");
  return areas;
}

/**
 * Validate that pose data contains enough meaningful running metrics.
 * Returns { valid: true } or { valid: false, reason: string }.
 */
function validatePoseData(data: any): { valid: boolean; reason?: string } {
  if (!data || typeof data !== "object") {
    return { valid: false, reason: "No pose data was extracted from the video." };
  }

  // Count how many meaningful running metrics are present (non-null)
  const runningFields = [
    data.hip_rom_left, data.hip_rom_right,
    data.knee_rom_left, data.knee_rom_right,
    data.ankle_rom_left, data.ankle_rom_right,
    data.shoulder_rotation_rom,
    data.foot_strike_pattern,
    data.gct_left, data.gct_right, data.gct_balance,
    data.avg_trunk_lean,
    data.shank_at_contact_left, data.shank_at_contact_right,
    data.arm_swing_symmetry,
    data.head_forward_offset,
  ];

  const presentCount = runningFields.filter((v) => v != null).length;

  // Need at least 3 meaningful metrics to be a plausible running analysis
  if (presentCount < 3) {
    return {
      valid: false,
      reason: `Only ${presentCount} running metrics detected. This doesn't appear to be a running video — please record yourself running with your full body visible.`,
    };
  }

  return { valid: true };
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
      const rateLimit = await checkFeatureRateLimit(userId, "form_check_analysis");
      if (!rateLimit.allowed) {
        return new Response(
          JSON.stringify({ error: "Rate limit exceeded", remaining: 0, resetAt: rateLimit.resetAt.toISOString() }),
          { status: 429, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }
    }

    const { formCheckId } = (await req.json()) as FormCheckRequest;

    const uuidErr = validateUUID(formCheckId, "formCheckId");
    if (uuidErr) return validationErrorResponse(uuidErr, corsHeaders);

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    // Fetch the form check record — always enforce user_id ownership
    const { data: formCheck, error: checkError } = await supabase
      .from("form_checks")
      .select("*")
      .eq("id", formCheckId)
      .eq("user_id", userId)
      .single();

    if (checkError || !formCheck) {
      console.error("Form check lookup failed:", checkError?.message, "userId:", userId, "formCheckId:", formCheckId);
      return validationErrorResponse("Form check not found", corsHeaders);
    }

    const actualUserId = formCheck.user_id || userId;
    const poseData = formCheck.pose_data_summary;

    // Validate pose data represents actual running
    const validation = validatePoseData(poseData);
    if (!validation.valid) {
      // Mark the form check as failed
      await supabase
        .from("form_checks")
        .update({
          status: "failed",
          ai_analysis: {
            overall_assessment: validation.reason,
            not_running: true,
            disclaimer: "This form check uses smartphone-based pose estimation for qualitative assessment only.",
          },
          ai_analysis_at: new Date().toISOString(),
        })
        .eq("id", formCheckId);

      return new Response(
        JSON.stringify({
          analysis: {
            overall_assessment: validation.reason,
            not_running: true,
            disclaimer: "This form check uses smartphone-based pose estimation for qualitative assessment only.",
          },
          formCheckId,
          processingTime: Date.now() - startTime,
        }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Fetch context in parallel
    const thirtyDaysAgo = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString();

    const [profileResult, logsResult, injuriesResult, previousCheckResult] =
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

        // Previous form check (for comparison)
        supabase
          .from("form_checks")
          .select("ai_analysis, pose_data_summary, recorded_at")
          .eq("user_id", actualUserId)
          .eq("status", "completed")
          .neq("id", formCheckId)
          .order("recorded_at", { ascending: false })
          .limit(1),
      ]);

    const profile = profileResult.data;

    // Build injury context
    const injuries = injuriesResult.data || [];
    const injuryContext = injuries.length > 0
      ? injuries.map((i: any) => `- ${i.side !== "unknown" ? i.side + " " : ""}${i.body_area} (severity ${i.severity}/10, ${i.status})`).join("\n")
      : "No active injuries";

    // Build previous check comparison
    const prevCheck = previousCheckResult.data?.[0];
    let comparisonContext = "";
    if (prevCheck?.ai_analysis?.overall_assessment) {
      const daysAgo = Math.floor(
        (Date.now() - new Date(prevCheck.recorded_at).getTime()) / (1000 * 60 * 60 * 24)
      );
      comparisonContext = `\nPREVIOUS FORM CHECK (${daysAgo} days ago):\n${prevCheck.ai_analysis.overall_assessment}`;
    }

    const trainingContext = compressTrainingContext(logsResult.data || []);

    const prompt = `You are a running form coach providing qualitative feedback based on smartphone pose estimation data. Your goal is to help runners understand their form patterns in plain language.

CRITICAL — VALIDITY CHECK:
Before analyzing, assess whether the pose data below actually represents human running gait. If the observations are inconsistent with bipedal running (e.g., missing most key metrics, nonsensical patterns, data that looks like an animal or non-running activity), respond ONLY with this JSON:
{"overall_assessment": "This doesn't appear to be a running video. Please record yourself running with your full body visible in the frame.", "not_running": true, "disclaimer": "This form check uses smartphone-based pose estimation for qualitative assessment only."}

IMPORTANT:
- This is a QUALITATIVE assessment — do NOT cite specific degree measurements or numbers
- Describe observations in plain language ("noticeable hip drop", "slight forward lean", "symmetric stride")
- Focus on patterns, not precision — smartphone pose estimation has limited accuracy
- Be encouraging where form looks good, constructive where improvement is needed
- This is for educational purposes only, NOT a clinical assessment
- ONLY create findings for areas listed in MEASURED AREAS below. Do NOT speculate about areas where no data was collected.
- Ground contact time is estimated from ankle position (no force plate), so treat it as approximate — note this if you discuss GCT.

PRIORITY AREAS (discuss these first and in most detail):
1. Landing mechanics / overstriding (shank angle) — the #1 injury risk factor
2. Foot strike pattern — how the foot contacts the ground
3. Asymmetries — any L/R differences in hip, knee, ankle, or shoulder indicate compensation or weakness
4. Posture — trunk lean and head position affect efficiency and injury risk
Other areas (cadence, arm swing, ground contact) are secondary.

MEASURED AREAS (only discuss these):
${measuredAreas(poseData).join(", ") || "None"}

POSE OBSERVATIONS:
${formatPoseData(poseData)}

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
  "overall_assessment": "<2-3 sentence narrative summary of what you see in the runner's form — be specific and conversational>",
  "findings": [
    {
      "area": "<one of: Overstriding, Foot Strike, Hip Stability, Knee Tracking, Ankle Mobility, Posture, Arm Swing, Ground Contact, Cadence>",
      "observation": "<what you observe, in plain language>",
      "severity": "good" | "watch" | "concern",
      "detail": "<why this matters for running efficiency or injury risk>"
    }
  ],
  "compensation_patterns": [
    {
      "pattern": "<observable compensation, e.g. 'Hip drop on left side during stance'>",
      "likely_cause": "<root cause hypothesis, e.g. 'Weak left glute medius'>",
      "affected_areas": ["<area1>", "<area2>"]
    }
  ],
  "drills": [
    {
      "name": "<specific drill or exercise name>",
      "target": "<what aspect of form it addresses>",
      "description": "<brief how-to, 1-2 sentences>",
      "frequency": "<recommended frequency, e.g. '3x/week before runs'>"
    }
  ],
  "summary": "<1-2 sentence takeaway — the single most important thing for this runner to focus on>",
  "disclaimer": "This form check uses smartphone-based pose estimation for qualitative assessment only. It is not a clinical gait analysis. Consult a qualified professional for medical or biomechanical concerns."
}

Include findings ONLY for the measured areas listed above — do not fabricate findings for unmeasured areas. Include 0-3 compensation patterns (only if measured data suggests linked issues). Include 2-4 drill recommendations relevant to the observed issues.
Respond ONLY with the JSON object, no markdown code blocks, no extra text.`;

    const geminiKey = Deno.env.get("GEMINI_API_KEY")!;
    const genAI = new GoogleGenerativeAI(geminiKey);
    const model = genAI.getGenerativeModel({
      model: "gemini-2.0-flash",
      generationConfig: { maxOutputTokens: 2500, temperature: 0.3 },
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
        console.error("Failed to parse form check analysis:", responseText.slice(0, 500));
        aiAnalysis = {
          overall_assessment: "Unable to generate analysis. Please try again.",
          disclaimer: "This form check uses smartphone-based pose estimation for qualitative assessment only.",
          error: true,
        };
      }
    }

    // If AI flagged this as not a running video, mark as failed
    const status = aiAnalysis.not_running ? "failed" : "completed";

    // Store analysis result
    await supabase
      .from("form_checks")
      .update({
        status,
        ai_analysis: aiAnalysis,
        ai_analysis_at: new Date().toISOString(),
      })
      .eq("id", formCheckId);

    // Log usage
    await supabase.from("usage_tracking").insert({
      user_id: userId,
      feature: "form_check_analysis",
      model_used: "gemini-2.0-flash",
      input_tokens: estimateTokens(prompt),
      output_tokens: estimateTokens(responseText),
      cached: false,
    });

    const processingTime = Date.now() - startTime;
    console.log(`Form check analysis completed in ${processingTime}ms`);

    return new Response(
      JSON.stringify({
        analysis: aiAnalysis,
        formCheckId,
        processingTime,
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (error) {
    console.error("Form check analysis error:", error);
    return internalErrorResponse(corsHeaders);
  }
});

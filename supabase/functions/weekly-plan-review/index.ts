/**
 * Weekly Plan Review — the "adaptive" made real.
 *
 * Runs Sunday evening via pg_cron (batch) or on-demand per user.
 * Compares the past week's actual training against the plan, reads
 * injury signals and quality session compliance, then makes ONE
 * concrete decision from a small set:
 *
 *   hold_plan      — everything on track, keep going
 *   soften_week    — drop volume or intensity for next week
 *   swap_quality   — replace a quality session with something different
 *   flag_for_review — something unusual, surface to the athlete
 *
 * Writes to coaching_adjustments so the iOS/web shows it as
 * "Coach's note for next week" with accept/dismiss.
 */

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { GoogleGenerativeAI } from "https://esm.sh/@google/generative-ai@0.24.0";
import { getAuthenticatedUser, unauthorizedResponse } from "../_shared/auth.ts";
import { enforceFeatureRateLimit } from "../_shared/rateLimit.ts";
import { getOrBuildAthleteState, stateToPromptContext } from "../_shared/athlete-state.ts";
import { getActiveInjuries, buildInjuryContext } from "../_shared/injuries.ts";
import { heatCategory, heatCategoryLabel, type HeatCategory } from "../_shared/pace-heat-adjustment.ts";
import { loadPrompt } from "../_shared/prompt-library.ts";

import { corsHeaders } from "../_shared/cors.ts";
// ── Decision types ─────────────────────────────────────────────

type ReviewDecision = "hold_plan" | "soften_week" | "swap_quality_session" | "flag_for_coach_review";

interface ReviewOutput {
  decision: ReviewDecision;
  reasoning: string;
  adjustment_type: string;        // maps to coaching_adjustments.adjustment_type
  target_workout: string | null;  // e.g. "Tuesday tempo" or null
  recommendation: string;         // what to actually do
}

// ── Main Handler ───────────────────────────────────────────────

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const startTime = Date.now();

  try {
    const body = await req.json();
    const isBatch = body.batch === true;

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    // ── Resolve target users ───────────────────────────────────
    let userIds: string[] = [];

    if (isBatch) {
      // Batch mode: all users with an active training plan
      const { data: plans } = await supabase
        .from("training_plans")
        .select("user_id")
        .eq("status", "active");
      userIds = [...new Set((plans || []).map((p: any) => p.user_id))];
      console.log(`[weekly-plan-review] Batch mode: ${userIds.length} users`);
    } else {
      // Single user mode — rate-limit the user-facing path. Batch (cron)
      // bypasses; the cron is the gate there.
      let userId = await getAuthenticatedUser(req);
      if (!userId && body.user_id) userId = body.user_id;
      if (!userId) return unauthorizedResponse(corsHeaders);

      const rlBlocked = await enforceFeatureRateLimit(userId, "weekly_review", corsHeaders);
      if (rlBlocked) return rlBlocked;

      userIds = [userId];
    }

    const results: Record<string, any> = {};

    for (const userId of userIds) {
      try {
        const result = await reviewUserWeek(supabase, userId);
        results[userId] = result;
      } catch (err) {
        console.error(`[weekly-plan-review] Error for ${userId}:`, err);
        results[userId] = { error: String(err) };
      }
    }

    return new Response(
      JSON.stringify({ results, processingTime: Date.now() - startTime }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (error) {
    console.error("[weekly-plan-review] Error:", error);
    return new Response(
      JSON.stringify({ error: String(error) }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});

// ── Per-User Review ────────────────────────────────────────────

async function reviewUserWeek(
  supabase: ReturnType<typeof createClient>,
  userId: string
): Promise<ReviewOutput | { skipped: string }> {
  // 1. Find active plan
  const { data: plan } = await supabase
    .from("training_plans")
    .select("id, name, start_date, end_date, target_race_distance, target_time_seconds, status, plan_type")
    .eq("user_id", userId)
    .eq("status", "active")
    .limit(1)
    .maybeSingle();

  if (!plan) return { skipped: "no active plan" };

  // 2. Compute this week's bounds (Mon-Sun)
  const now = new Date();
  const dayOfWeek = now.getUTCDay(); // 0=Sun, 1=Mon
  const mondayOffset = dayOfWeek === 0 ? -6 : 1 - dayOfWeek;
  const monday = new Date(now);
  monday.setUTCDate(monday.getUTCDate() + mondayOffset);
  monday.setUTCHours(0, 0, 0, 0);
  const sunday = new Date(monday);
  sunday.setUTCDate(sunday.getUTCDate() + 6);

  const mondayStr = monday.toISOString().split("T")[0];
  const sundayStr = sunday.toISOString().split("T")[0];

  // 3. Parallel fetch: logs, scheduled workouts, quality templates, injuries, athlete state
  const [logsRes, scheduledRes, qualityRes, injuries, athleteState] = await Promise.all([
    supabase
      .from("training_logs")
      .select("id, workout_date, workout_distance_miles, workout_duration_minutes, workout_type, workout_pace_per_mile, mood, cleaned_notes, notes")
      .eq("user_id", userId)
      .gte("workout_date", mondayStr)
      .lte("workout_date", sundayStr)
      .order("workout_date"),
    supabase
      .from("scheduled_workouts")
      .select("id, date, workout_type, status, workout_data, notes, source, is_movable, weather_forecast")
      .eq("plan_id", plan.id)
      .gte("date", mondayStr)
      .lte("date", sundayStr)
      .order("date"),
    supabase
      .from("quality_session_templates")
      .select("*")
      .eq("plan_id", plan.id)
      .gte("week_number", currentWeekNumber(plan.start_date, mondayStr))
      .lte("week_number", currentWeekNumber(plan.start_date, mondayStr))
      .order("priority_rank"),
    getActiveInjuries(supabase, userId),
    getOrBuildAthleteState(supabase, userId),
  ]);

  const logs = logsRes.data || [];
  const scheduled = scheduledRes.data || [];
  const qualityTemplates = qualityRes.data || [];

  // 4. Compute key metrics
  const totalPlannedMiles = scheduled
    .filter((w: any) => w.workout_type !== "rest")
    .reduce((sum: number, w: any) => {
      const wd = w.workout_data as Record<string, any> | null;
      const km = wd?.total_distance_km as number || 0;
      const mi = wd?.total_distance_mi as number || km / 1.60934;
      return sum + mi;
    }, 0);

  const totalActualMiles = logs.reduce(
    (sum: number, l: any) => sum + (l.workout_distance_miles || 0), 0
  );

  const qualityScheduled = scheduled.filter(
    (w: any) => ["tempo", "intervals", "long_run", "race", "progression"].includes(w.workout_type)
  );
  const qualityCompleted = qualityScheduled.filter((w: any) => w.status === "completed");
  const qualityMissed = qualityScheduled.filter(
    (w: any) => w.status === "scheduled" && w.date < now.toISOString().split("T")[0]
  );

  // Pace deltas for completed quality sessions
  const paceDeltas: string[] = [];
  for (const sw of qualityCompleted) {
    const wd = sw.workout_data as Record<string, any> | null;
    const targetPace = wd?.target_pace as string | undefined;
    if (!targetPace) continue;

    const matchingLog = logs.find((l: any) =>
      l.workout_date && l.workout_date.startsWith(sw.date)
    );
    if (!matchingLog?.workout_pace_per_mile) continue;

    const targetSec = parsePace(targetPace);
    const actualSec = parsePace(matchingLog.workout_pace_per_mile);
    if (targetSec > 0 && actualSec > 0) {
      const delta = actualSec - targetSec;
      const sign = delta < 0 ? "faster" : "slower";
      const abs = Math.abs(delta);
      const formatted = abs >= 60
        ? `${Math.floor(abs / 60)}:${String(abs % 60).padStart(2, "0")}`
        : `${abs}s`;
      paceDeltas.push(`${sw.workout_type}: ${formatted} ${sign} than target`);
    }
  }

  // Mood summary
  const moods = logs
    .filter((l: any) => l.mood)
    .map((l: any) => l.mood as string);

  // Injury signals
  const injuryContext = buildInjuryContext(injuries);
  const hasActiveInjury = injuries.length > 0;
  const highSeverityInjury = injuries.some((i: any) => (i.severity || 0) >= 5);

  // 4b. Next week's forecast weather for quality sessions
  const nextMonday = new Date(monday);
  nextMonday.setUTCDate(nextMonday.getUTCDate() + 7);
  const nextSunday = new Date(nextMonday);
  nextSunday.setUTCDate(nextSunday.getUTCDate() + 6);

  const { data: nextWeekWorkouts } = await supabase
    .from("scheduled_workouts")
    .select("id, date, workout_type, workout_data, weather_forecast")
    .eq("plan_id", plan.id)
    .gte("date", nextMonday.toISOString().split("T")[0])
    .lte("date", nextSunday.toISOString().split("T")[0])
    .in("workout_type", ["tempo", "intervals", "long_run", "race", "progression"])
    .order("date");

  // Build weather warnings for next week's quality sessions
  const weatherWarnings: string[] = [];
  for (const nw of (nextWeekWorkouts || [])) {
    const wf = nw.weather_forecast as Record<string, any> | null;
    if (!wf) continue;
    const score = wf.composite_score as number;
    const cat = wf.heat_category as string;
    if (score >= 130) {
      const dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
      const d = new Date(nw.date + "T12:00:00Z");
      const dayName = dayNames[d.getUTCDay()];
      const wd = nw.workout_data as Record<string, any> | null;
      const name = wd?.name || nw.workout_type;
      weatherWarnings.push(`${dayName} ${name}: ${Math.round(wf.temp_f)}°F dp${Math.round(wf.dew_point_f)}°F (${cat}, +${Math.round((wf.adjustment_pct || 0) * 100 * 4.5)}s/mi adj)`);
    }
  }

  // 5. Build compact summary for AI
  const summary = `
WEEK SUMMARY (${mondayStr} to ${sundayStr}):
Plan: ${plan.name} | Distance: ${plan.target_race_distance} | Days to race: ${daysUntil(plan.end_date)}

Volume: ${totalActualMiles.toFixed(1)}mi actual / ${totalPlannedMiles.toFixed(1)}mi planned (${totalPlannedMiles > 0 ? Math.round(totalActualMiles / totalPlannedMiles * 100) : 0}%)
Quality sessions: ${qualityCompleted.length}/${qualityScheduled.length} completed${qualityMissed.length > 0 ? `, ${qualityMissed.length} missed` : ""}
${paceDeltas.length > 0 ? `Pace execution: ${paceDeltas.join("; ")}` : "No pace data for quality sessions"}
Moods this week: ${moods.length > 0 ? moods.join(", ") : "no mood data"}
${hasActiveInjury ? `Active injuries: ${injuries.map((i: any) => `${i.body_area} (severity ${i.severity})`).join(", ")}` : "No active injuries"}
${highSeverityInjury ? "⚠️ HIGH SEVERITY INJURY ACTIVE" : ""}
ACWR: ${athleteState?.acwr?.toFixed(2) || "unknown"}
Hard sessions last 7d: ${athleteState?.hard_sessions_7d ?? "unknown"}
${weatherWarnings.length > 0 ? `\n⚠️ HEAT WARNINGS FOR NEXT WEEK:\n${weatherWarnings.join("\n")}` : ""}
`;

  // 6. Call Gemini for decision
  const geminiKey = Deno.env.get("GEMINI_API_KEY");
  if (!geminiKey) {
    // Fallback: deterministic rules when no AI available
    return deterministicReview(summary, totalActualMiles, totalPlannedMiles, qualityMissed, highSeverityInjury, athleteState);
  }

  const genAI = new GoogleGenerativeAI(geminiKey);
  const model = genAI.getGenerativeModel({
    model: "gemini-2.0-flash",
    generationConfig: {
      maxOutputTokens: 300,
      temperature: 0.2,
      responseMimeType: "application/json",
    },
  });

  const prompt = loadPrompt("weekly-plan-review.v1", { summary });

  try {
    const result = await model.generateContent(prompt);
    const text = result.response.text();
    const output = JSON.parse(text) as ReviewOutput;

    // Validate decision
    const validDecisions: ReviewDecision[] = ["hold_plan", "soften_week", "swap_quality_session", "flag_for_coach_review"];
    if (!validDecisions.includes(output.decision)) {
      output.decision = "hold_plan";
    }

    // 7. Write to coaching_adjustments
    const nextMonday = new Date(monday);
    nextMonday.setUTCDate(nextMonday.getUTCDate() + 7);

    await supabase.from("coaching_adjustments").insert({
      user_id: userId,
      week_start: nextMonday.toISOString().split("T")[0],
      adjustment_type: output.adjustment_type || "other",
      target_workout: output.target_workout || null,
      recommendation: `[${output.decision}] ${output.recommendation}`,
      source: "weekly_review",
      followed: null,  // pending athlete accept/dismiss
    });

    console.log(`[weekly-plan-review] ${userId}: ${output.decision} — ${output.reasoning.slice(0, 80)}`);
    return output;
  } catch (aiErr) {
    console.error("[weekly-plan-review] AI call failed:", aiErr);
    return deterministicReview(summary, totalActualMiles, totalPlannedMiles, qualityMissed, highSeverityInjury, athleteState);
  }
}

// ── Deterministic fallback (no AI needed) ──────────────────────

function deterministicReview(
  _summary: string,
  actualMiles: number,
  plannedMiles: number,
  qualityMissed: any[],
  highSeverityInjury: boolean,
  athleteState: any
): ReviewOutput {
  const volumeRatio = plannedMiles > 0 ? actualMiles / plannedMiles : 1;
  const acwr = athleteState?.acwr ?? 1.0;

  if (highSeverityInjury) {
    return {
      decision: "soften_week",
      reasoning: "Active high-severity injury requires reduced training load.",
      adjustment_type: "recovery",
      target_workout: null,
      recommendation: "Drop volume 30-40% next week. Replace quality sessions with easy running if pain-free, rest if not.",
    };
  }

  if (acwr > 1.3) {
    return {
      decision: "soften_week",
      reasoning: `ACWR is ${acwr.toFixed(2)} — training load spiked relative to chronic load.`,
      adjustment_type: "volume",
      target_workout: null,
      recommendation: "Reduce next week's volume by 20% and keep quality sessions at moderate effort.",
    };
  }

  if (qualityMissed.length >= 2) {
    return {
      decision: "flag_for_coach_review",
      reasoning: `${qualityMissed.length} quality sessions missed this week.`,
      adjustment_type: "other",
      target_workout: null,
      recommendation: "Multiple key sessions missed. Check in about schedule constraints or fatigue before planning next week.",
    };
  }

  if (volumeRatio < 0.7) {
    return {
      decision: "soften_week",
      reasoning: `Only ${Math.round(volumeRatio * 100)}% of planned volume completed.`,
      adjustment_type: "volume",
      target_workout: null,
      recommendation: "Reduce next week's planned volume to match what you're actually running. Build back gradually.",
    };
  }

  if (qualityMissed.length === 1) {
    const missedType = qualityMissed[0].workout_type;
    return {
      decision: "swap_quality_session",
      reasoning: `Missed ${missedType} session. Adjusting to maintain quality work without overloading.`,
      adjustment_type: "workout_swap",
      target_workout: missedType,
      recommendation: `Carry the missed ${missedType} into next week if schedule allows, or replace with a lighter version.`,
    };
  }

  return {
    decision: "hold_plan",
    reasoning: "Training on track. Volume and quality session execution look good.",
    adjustment_type: "other",
    target_workout: null,
    recommendation: "Continue as planned. Good week.",
  };
}

// ── Helpers ────────────────────────────────────────────────────

function parsePace(pace: string): number {
  const cleaned = pace.replace(/\/mi|\/km/g, "").trim();
  const parts = cleaned.split(":").map(Number);
  if (parts.length === 2 && !isNaN(parts[0]) && !isNaN(parts[1])) {
    return parts[0] * 60 + parts[1];
  }
  return 0;
}

function currentWeekNumber(planStartDate: string, currentMonday: string): number {
  const start = new Date(planStartDate);
  const current = new Date(currentMonday);
  const diffDays = Math.floor((current.getTime() - start.getTime()) / (1000 * 60 * 60 * 24));
  return Math.max(1, Math.floor(diffDays / 7) + 1);
}

function daysUntil(dateStr: string): number {
  const target = new Date(dateStr);
  const now = new Date();
  return Math.max(0, Math.ceil((target.getTime() - now.getTime()) / (1000 * 60 * 60 * 24)));
}

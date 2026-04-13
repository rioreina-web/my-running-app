/**
 * Weekly Coaching Report Edge Function
 *
 * Generates a personalized weekly coaching analysis per athlete.
 * Runs Monday mornings via pg_cron (batch) or on-demand (single user).
 *
 * Flow:
 * 1. Fetch training data from 8 tables in parallel
 * 2. Compute analytics (ACWR, compliance, mood, injury risk)
 * 3. Generate alerts from computed metrics
 * 4. Call Gemini 2.5 Flash for coaching narrative + adjustments
 * 5. Upsert into weekly_coaching_reports
 */

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { GoogleGenerativeAI } from "https://esm.sh/@google/generative-ai@0.24.0";

import { getAuthenticatedUser, unauthorizedResponse } from "../_shared/auth.ts";
import { getActiveInjuries, buildInjuryContext } from "../_shared/injuries.ts";
import { internalErrorResponse } from "../_shared/validation.ts";
import { buildAthleteProfileContext, type AthleteProfile } from "../_shared/athleteProfile.ts";
import {
  computeAllMetrics,
  generateAlerts,
  aggregateWeeklyLoad,
  getLastWeekBounds,
  formatPace,
  formatDuration,
  type TrainingLogRow,
  type ScheduledWorkoutRow,
  type InjuryRow,
  type FormCheckRow,
  type ComputedMetrics,
  type Alert,
} from "../_shared/weeklyAnalytics.ts";
import { getOrBuildAthleteState, stateToPromptContext } from "../_shared/athlete-state.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

// ─── Main Handler ────────────────────────────────────────────────────────────

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const startTime = Date.now();

  try {
    const body = await req.json();
    const isBatch = body.batch === true;

    // Auth: batch mode uses service role, single user uses JWT
    let userId: string | null = null;
    if (isBatch) {
      // Called from pg_cron with service role key — no user auth needed
      const authHeader = req.headers.get("Authorization") || "";
      if (
        !authHeader.includes(
          Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.slice(0, 20) || "___"
        )
      ) {
        return new Response(
          JSON.stringify({ error: "Batch mode requires service role key" }),
          { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }
    } else {
      userId = body.userId || (await getAuthenticatedUser(req));
      if (!userId) {
        return unauthorizedResponse(corsHeaders);
      }
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    // Determine which users to process
    let userIds: string[] = [];
    if (isBatch) {
      // Fetch all users with active training plans
      const { data: plans } = await supabase
        .from("training_plans")
        .select("user_id")
        .eq("status", "active");
      userIds = [...new Set((plans || []).map((p: { user_id: string }) => p.user_id))];
      console.log(`Batch mode: processing ${userIds.length} users`);
    } else {
      userIds = [userId!];
    }

    const results: Array<{ userId: string; status: string; error?: string }> = [];

    const PER_USER_TIMEOUT_MS = 60_000; // 60 seconds max per user
    const BATCH_CHUNK_SIZE = 10; // Process 10 users at a time to limit DB pressure

    // Process users in chunks to avoid overwhelming the DB connection pool
    for (let i = 0; i < userIds.length; i += BATCH_CHUNK_SIZE) {
      const chunk = userIds.slice(i, i + BATCH_CHUNK_SIZE);

      const chunkResults = await Promise.allSettled(
        chunk.map(async (uid) => {
          // Per-user timeout to prevent one user from blocking the batch
          const timeoutPromise = new Promise<never>((_, reject) =>
            setTimeout(() => reject(new Error("Per-user timeout exceeded")), PER_USER_TIMEOUT_MS)
          );
          const result = await Promise.race([
            generateReportForUser(supabase, uid, startTime),
            timeoutPromise,
          ]);
          return { userId: uid, status: result.status };
        })
      );

      for (let j = 0; j < chunkResults.length; j++) {
        const settled = chunkResults[j];
        const uid = chunk[j];
        if (settled.status === "fulfilled") {
          results.push(settled.value);
        } else {
          console.error(`Error for user ${uid}:`, settled.reason);
          results.push({
            userId: uid,
            status: "failed",
            error: settled.reason instanceof Error ? settled.reason.message : "Unknown error",
          });
        }
      }

      console.log(`Batch progress: ${Math.min(i + BATCH_CHUNK_SIZE, userIds.length)}/${userIds.length} users processed`);
    }

    // For single-user (non-batch) calls, return the full report data
    if (!isBatch && userIds.length === 1) {
      const uid = userIds[0];
      const { data: report } = await supabase
        .from("weekly_coaching_reports")
        .select("week_start, week_end, coaching_narrative, alerts, adjustments, focus_areas, metrics, plan_week_number")
        .eq("user_id", uid)
        .order("week_start", { ascending: false })
        .limit(1)
        .single();

      return new Response(
        JSON.stringify({
          status: results[0]?.status || "completed",
          report: report || null,
          processingTime: Date.now() - startTime,
        }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    return new Response(
      JSON.stringify({
        processed: results.length,
        results,
        processingTime: Date.now() - startTime,
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (error) {
    console.error("Weekly coaching report error:", error);
    return internalErrorResponse(corsHeaders);
  }
});

// ─── Per-User Report Generation ──────────────────────────────────────────────

async function generateReportForUser(
  supabase: ReturnType<typeof createClient>,
  userId: string,
  startTime: number
): Promise<{ status: string }> {
  const { weekStart, weekEnd } = getLastWeekBounds(new Date());

  // Check for existing report (idempotency)
  const { data: existing } = await supabase
    .from("weekly_coaching_reports")
    .select("id, status")
    .eq("user_id", userId)
    .eq("week_start", weekStart)
    .single();

  if (existing?.status === "completed") {
    console.log(`Report already exists for user ${userId} week ${weekStart}`);
    return { status: "already_exists" };
  }

  // ── Parallel Data Fetch (8 queries) ──────────────────────────────────────

  const fourWeeksAgo = new Date();
  fourWeeksAgo.setDate(fourWeeksAgo.getDate() - 35);
  const twoWeeksAgo = new Date();
  twoWeeksAgo.setDate(twoWeeksAgo.getDate() - 14);

  const [
    scheduledThisWeek,
    scheduledNextWeek,
    logsThisWeek,
    logsHistorical,
    activePlanResult,
    injuriesResult,
    profileResult,
    fitnessSnapshotsResult,
    formChecksResult,
    athleteProfileResult,
  ] = await Promise.all([
    // Scheduled workouts this week
    supabase
      .from("scheduled_workouts")
      .select("id, date, workout_type, status, workout_data, completed_workout_id, week_number, notes")
      .eq("user_id", userId)
      .gte("date", weekStart)
      .lte("date", weekEnd)
      .order("date"),

    // Scheduled workouts next week (for adjustment context)
    (() => {
      const nextMonday = new Date(weekEnd);
      nextMonday.setDate(nextMonday.getDate() + 1);
      const nextSunday = new Date(nextMonday);
      nextSunday.setDate(nextSunday.getDate() + 6);
      return supabase
        .from("scheduled_workouts")
        .select("id, date, workout_type, status, workout_data, week_number, notes")
        .eq("user_id", userId)
        .gte("date", nextMonday.toISOString().split("T")[0])
        .lte("date", nextSunday.toISOString().split("T")[0])
        .order("date");
    })(),

    // Training logs this week
    supabase
      .from("training_logs")
      .select("id, workout_date, workout_distance_miles, workout_duration_minutes, workout_type, workout_pace_per_mile, pace_segments, mood, notes, cleaned_notes, coach_insight, workout_notes, extracted_data")
      .eq("user_id", userId)
      .gte("workout_date", weekStart)
      .lte("workout_date", weekEnd + "T23:59:59")
      .order("workout_date"),

    // Training logs for previous 4 weeks (for ACWR)
    supabase
      .from("training_logs")
      .select("id, workout_date, workout_distance_miles, workout_duration_minutes, workout_type, workout_pace_per_mile, mood")
      .eq("user_id", userId)
      .gte("workout_date", fourWeeksAgo.toISOString().split("T")[0])
      .lt("workout_date", weekStart)
      .order("workout_date"),

    // Active training plan
    supabase
      .from("training_plans")
      .select("id, name, start_date, end_date, target_race_distance, target_time_seconds, status")
      .eq("user_id", userId)
      .eq("status", "active")
      .limit(1)
      .single(),

    // Active injuries
    supabase
      .from("injuries")
      .select("id, body_area, severity, status, side, first_reported_at")
      .eq("user_id", userId)
      .in("status", ["active", "monitoring"])
      .order("severity", { ascending: false }),

    // User profile
    supabase
      .from("user_profiles")
      .select("*")
      .eq("user_id", userId)
      .single(),

    // Fitness snapshots (latest + from 4 weeks ago)
    supabase
      .from("fitness_snapshots")
      .select("predicted_marathon_seconds, predicted_half_seconds, predicted_10k_seconds, predicted_5k_seconds, confidence, created_at")
      .eq("user_id", userId)
      .order("created_at", { ascending: false })
      .limit(5),

    // Recent form checks
    supabase
      .from("form_checks")
      .select("ai_findings, created_at")
      .eq("user_id", userId)
      .gte("created_at", twoWeeksAgo.toISOString())
      .order("created_at", { ascending: false })
      .limit(3),

    // Cached athlete profile (comprehensive historical analysis)
    supabase
      .from("athlete_profiles")
      .select("profile_data")
      .eq("user_id", userId)
      .single(),
  ]);

  // ── Extract Data ─────────────────────────────────────────────────────────

  const thisWeekScheduled = (scheduledThisWeek.data || []) as ScheduledWorkoutRow[];
  const nextWeekScheduled = (scheduledNextWeek.data || []) as ScheduledWorkoutRow[];
  const thisWeekLogs = (logsThisWeek.data || []) as TrainingLogRow[];
  const historicalLogs = (logsHistorical.data || []) as TrainingLogRow[];
  const activePlan = activePlanResult.data;
  const activeInjuries = (injuriesResult.data || []) as InjuryRow[];
  const profile = profileResult.data;
  const fitnessSnapshots = fitnessSnapshotsResult.data || [];
  const formChecks = (formChecksResult.data || []) as FormCheckRow[];

  // Split historical logs into weekly buckets (most recent first)
  const previousWeeksLogs = splitIntoWeeks(historicalLogs, weekStart);

  // Race pace from active plan
  const racePaceSecondsPerMile = activePlan?.target_time_seconds
    ? calculateRacePace(
        activePlan.target_race_distance,
        activePlan.target_time_seconds
      )
    : null;

  // ── Compute Metrics ──────────────────────────────────────────────────────

  const metrics = computeAllMetrics(
    thisWeekLogs,
    previousWeeksLogs,
    thisWeekScheduled,
    activeInjuries,
    formChecks,
    racePaceSecondsPerMile
  );

  // ── Generate Alerts ──────────────────────────────────────────────────────

  const goalDaysRemaining = activePlan?.end_date
    ? Math.ceil(
        (new Date(activePlan.end_date).getTime() - Date.now()) /
          (1000 * 60 * 60 * 24)
      )
    : null;

  let fitnessGapSeconds: number | null = null;
  if (activePlan?.target_time_seconds && fitnessSnapshots.length > 0) {
    const latestPrediction = fitnessSnapshots[0];
    const predictedTime = getPredictedTimeForDistance(
      latestPrediction,
      activePlan.target_race_distance
    );
    if (predictedTime) {
      fitnessGapSeconds = predictedTime - activePlan.target_time_seconds;
    }
  }

  const prescribedEasyPace = racePaceSecondsPerMile
    ? racePaceSecondsPerMile / 0.75
    : profile?.easy_pace_per_mile
      ? parsePaceString(profile.easy_pace_per_mile)
      : null;

  const alerts = generateAlerts(metrics, {
    goalDaysRemaining,
    fitnessGapSeconds,
    prescribedEasyPace,
  });

  // ── Athlete State (big-picture context) ──────────────────────────────────

  const athleteState = await getOrBuildAthleteState(supabase, userId);
  const athleteContext = stateToPromptContext(athleteState);

  // ── Build AI Prompt ──────────────────────────────────────────────────────

  // Build athlete profile context from cached data
  let athleteProfileCtx = "";
  if (athleteProfileResult.data?.profile_data) {
    try {
      athleteProfileCtx = buildAthleteProfileContext(athleteProfileResult.data.profile_data as AthleteProfile);
    } catch (e) {
      console.error("Error building athlete profile context:", e);
    }
  }

  const prompt = buildCoachingPrompt(
    metrics,
    alerts,
    {
      profile,
      activePlan,
      activeInjuries,
      thisWeekLogs,
      thisWeekScheduled,
      nextWeekScheduled,
      fitnessSnapshots,
      goalDaysRemaining,
      fitnessGapSeconds,
      weekStart,
      weekEnd,
      athleteProfileContext: athleteProfileCtx,
      athleteStateContext: athleteContext,
    }
  );

  // ── Call Gemini ─────────────────────────────────────────────────────────

  const geminiKey = Deno.env.get("GEMINI_API_KEY");
  if (!geminiKey) {
    throw new Error("GEMINI_API_KEY not configured");
  }

  const genAI = new GoogleGenerativeAI(geminiKey);
  // Use Gemini Pro for deeper coaching reasoning (worth the cost for a weekly report)
  const model = genAI.getGenerativeModel({
    model: "gemini-2.5-flash",
    generationConfig: {
      temperature: 0.6,
      maxOutputTokens: 8192,
      responseMimeType: "application/json",
    },
  });

  const result = await model.generateContent(prompt);
  const responseText = result.response.text();
  const usageMetadata = result.response.usageMetadata;

  console.log(`Gemini Pro raw response: ${responseText.length} chars`);

  // Parse JSON response — handle code fences, nested JSON, and edge cases
  let narrative = "";
  let adjustments: Record<string, unknown>[] = [];
  let focusAreas: string[] = [];

  try {
    const parsed = JSON.parse(responseText);
    narrative = typeof parsed.narrative === "string" ? parsed.narrative : String(parsed.narrative || "");
    adjustments = Array.isArray(parsed.adjustments) ? parsed.adjustments : [];
    focusAreas = Array.isArray(parsed.focus_areas) ? parsed.focus_areas : [];
  } catch (parseErr) {
    console.error("Failed to parse AI JSON response:", (parseErr as Error).message, responseText.slice(0, 300));
    // Fallback: try to extract narrative from raw text
    try {
      const cleaned = responseText.replace(/```json\s*/g, "").replace(/```/g, "").trim();
      const parsed = JSON.parse(cleaned);
      narrative = typeof parsed.narrative === "string" ? parsed.narrative : String(parsed.narrative || "");
      adjustments = Array.isArray(parsed.adjustments) ? parsed.adjustments : [];
      focusAreas = Array.isArray(parsed.focus_areas) ? parsed.focus_areas : [];
    } catch {
      narrative = responseText.replace(/[{}":\[\]]/g, "").replace(/narrative/g, "").trim();
    }
  }

  // ── Upsert Report ───────────────────────────────────────────────────────

  const processingTime = Date.now() - startTime;

  const reportData = {
    user_id: userId,
    week_start: weekStart,
    week_end: weekEnd,
    plan_id: activePlan?.id || null,
    plan_week_number: activePlan
      ? getCurrentPlanWeek(activePlan.start_date, weekStart)
      : null,
    metrics,
    coaching_narrative: narrative,
    alerts,
    adjustments,
    focus_areas: focusAreas,
    ai_model: "gemini-2.5-flash",
    input_tokens: usageMetadata?.promptTokenCount || 0,
    output_tokens: usageMetadata?.candidatesTokenCount || 0,
    processing_time_ms: processingTime,
    status: "completed",
  };

  const { error: upsertError } = await supabase
    .from("weekly_coaching_reports")
    .upsert(reportData, { onConflict: "user_id,week_start" });

  if (upsertError) {
    console.error("Upsert error:", upsertError);
    throw new Error(`Failed to save report: ${upsertError.message}`);
  }

  // Log usage
  await supabase.from("usage_tracking").insert({
    user_id: userId,
    feature: "weekly_coaching_report",
    model_used: "gemini-2.5-flash",
    input_tokens: usageMetadata?.promptTokenCount || 0,
    output_tokens: usageMetadata?.candidatesTokenCount || 0,
    cached: false,
  });

  console.log(
    `Report generated for ${userId}: ${usageMetadata?.promptTokenCount || 0}in/${usageMetadata?.candidatesTokenCount || 0}out in ${processingTime}ms`
  );

  return { status: "completed" };
}

// ─── Zone Volume Summary ────────────────────────────────────────────────────

const ZONE_MAP: Record<string, string> = {
  easy: "easy", recovery: "recovery", long_run: "long_run",
  tempo: "tempo", threshold: "threshold", steady: "threshold",
  interval: "interval", speed: "interval", repeat: "interval", fartlek: "interval",
  marathon_pace: "race_pace", race_pace: "race_pace", race: "race_pace", time_trial: "race_pace",
  moderate: "tempo", progression: "tempo", run: "easy",
};

const ZONE_LABELS: Record<string, string> = {
  easy: "Easy", recovery: "Recovery", long_run: "Long Run",
  tempo: "Tempo", threshold: "Threshold", interval: "Interval/Speed", race_pace: "Race Pace",
};

function buildZoneSummary(logs: TrainingLogRow[]): string {
  const zones: Record<string, { miles: number; runs: number; totalPaceSecs: number; paceCount: number }> = {};

  const addToZone = (zone: string, miles: number, paceSecs: number) => {
    if (!zones[zone]) zones[zone] = { miles: 0, runs: 0, totalPaceSecs: 0, paceCount: 0 };
    zones[zone].miles += miles;
    if (paceSecs > 0) {
      zones[zone].totalPaceSecs += paceSecs;
      zones[zone].paceCount++;
    }
  };

  for (const log of logs) {
    const dist = log.workout_distance_miles || 0;
    const dur = log.workout_duration_minutes || 0;
    if (dist <= 0) continue;

    // Use pace_segments for per-segment zone breakdown when available
    const paceSegments = (log as any).pace_segments as Array<{ effort: string; distance_miles: number; pace_per_mile: string }> | null;
    if (paceSegments && paceSegments.length > 0) {
      for (const seg of paceSegments) {
        const segZone = ZONE_MAP[seg.effort] || "easy";
        const parts = seg.pace_per_mile.split(":").map(Number);
        const paceSecs = parts.length === 2 ? parts[0] * 60 + parts[1] : 0;
        addToZone(segZone, seg.distance_miles, paceSecs);
      }
      // Count as one run in dominant zone
      const dominant = paceSegments.reduce((best, seg) =>
        seg.distance_miles > best.distance_miles ? seg : best
      ).effort;
      const mappedDominant = ZONE_MAP[dominant] || "easy";
      if (!zones[mappedDominant]) zones[mappedDominant] = { miles: 0, runs: 0, totalPaceSecs: 0, paceCount: 0 };
      zones[mappedDominant].runs++;
    } else {
      // Fallback: whole-run classification
      const rawType = (log.workout_type || "").toLowerCase().replace(/[_\s-]+/g, "_");
      let zone = ZONE_MAP[rawType] || "easy";
      if (zone === "easy" && dist >= 10) zone = "long_run";

      if (!zones[zone]) zones[zone] = { miles: 0, runs: 0, totalPaceSecs: 0, paceCount: 0 };
      zones[zone].miles += dist;
      zones[zone].runs++;
      if (dur > 0 && dist > 0) {
        zones[zone].totalPaceSecs += (dur / dist) * 60;
        zones[zone].paceCount++;
      }
    }
  }

  const totalMiles = Object.values(zones).reduce((s, z) => s + z.miles, 0);
  if (totalMiles === 0) return "No zone data available.";

  const zoneOrder = ["easy", "recovery", "long_run", "tempo", "threshold", "race_pace", "interval"];
  const lines: string[] = [];
  for (const zone of zoneOrder) {
    const data = zones[zone];
    if (!data || data.miles < 0.1) continue;
    const pct = Math.round((data.miles / totalMiles) * 100);
    const label = ZONE_LABELS[zone] || zone;
    const avgPace = data.paceCount > 0 ? data.totalPaceSecs / data.paceCount : 0;
    const paceStr = avgPace > 0 ? ` @ ${formatPace(avgPace)}` : "";
    lines.push(`  ${label}: ${data.miles.toFixed(1)}mi (${pct}%, ${data.runs} runs${paceStr})`);
  }

  return lines.length > 0 ? lines.join("\n") : "No zone data available.";
}

// ─── AI Prompt ───────────────────────────────────────────────────────────────

function buildCoachingPrompt(
  metrics: ComputedMetrics,
  alerts: Alert[],
  ctx: {
    profile: Record<string, unknown> | null;
    activePlan: Record<string, unknown> | null;
    activeInjuries: InjuryRow[];
    thisWeekLogs: TrainingLogRow[];
    thisWeekScheduled: ScheduledWorkoutRow[];
    nextWeekScheduled: ScheduledWorkoutRow[];
    fitnessSnapshots: Record<string, unknown>[];
    goalDaysRemaining: number | null;
    fitnessGapSeconds: number | null;
    weekStart: string;
    weekEnd: string;
    athleteProfileContext: string;
    athleteStateContext: string;
  }
): string {
  // Profile summary
  const profileSummary = ctx.profile
    ? `Runner: ${ctx.profile.years_running || "?"} years running, current ${ctx.profile.current_weekly_mileage || "?"}mpw, peak ${ctx.profile.peak_weekly_mileage || "?"}mpw`
    : "Runner: limited profile data";

  // Goal summary
  let goalSummary = "No active race goal.";
  if (ctx.activePlan) {
    const plan = ctx.activePlan;
    const goalTime = plan.target_time_seconds
      ? formatTotalTime(plan.target_time_seconds as number)
      : "no time goal";
    goalSummary = `Training for: ${plan.target_race_distance} in ${goalTime}. Plan week ${getCurrentPlanWeek(plan.start_date as string, ctx.weekStart)} of ${getTotalPlanWeeks(plan.start_date as string, plan.end_date as string)}. Race: ${plan.end_date}.`;
    if (ctx.goalDaysRemaining !== null) {
      goalSummary += ` ${ctx.goalDaysRemaining} days to race.`;
    }
  }

  // Injury context
  const injuryLines = ctx.activeInjuries.map((i) => {
    const side = i.side !== "unknown" ? `${i.side} ` : "";
    return `- ${side}${i.body_area} (severity: ${i.severity}/10, ${i.status})`;
  });
  const injuryCtx =
    injuryLines.length > 0
      ? `\nActive injuries:\n${injuryLines.join("\n")}`
      : "";

  // Workout log — rich per-workout detail with pace segments
  const workoutLog = ctx.thisWeekLogs
    .map((l) => {
      const date = l.workout_date ? new Date(l.workout_date).toLocaleDateString("en-US", { weekday: "short", month: "short", day: "numeric" }) : "?";
      const dist = l.workout_distance_miles
        ? `${l.workout_distance_miles.toFixed(1)}mi`
        : "?mi";
      const pace =
        l.workout_distance_miles && l.workout_duration_minutes
          ? formatPace(
              (l.workout_duration_minutes * 60) / l.workout_distance_miles
            )
          : "";
      const type = l.workout_type ? l.workout_type.replace(/_/g, " ").toUpperCase() : "RUN";
      const mood = l.mood ? ` [mood: ${l.mood}]` : "";

      let line = `${date} — ${type}: ${dist} @ ${pace}/mi avg${mood}`;

      // Add pace segments breakdown for quality workouts
      const paceSegments = (l as any).pace_segments as Array<{ effort: string; distance_miles: number; pace_per_mile: string; duration_seconds: number; avg_heart_rate?: number }> | null;
      if (paceSegments && paceSegments.length > 1) {
        const segDetails = paceSegments.map((s) => {
          const hr = s.avg_heart_rate ? ` ${s.avg_heart_rate}bpm` : "";
          return `  ${s.effort}: ${s.distance_miles.toFixed(1)}mi @ ${s.pace_per_mile}/mi${hr}`;
        });
        line += "\n" + segDetails.join("\n");
      }

      // Add athlete's voice notes (what they said about it)
      const notes = l.cleaned_notes || l.notes || "";
      if (notes) {
        line += `\n  Voice: "${notes.slice(0, 150)}"`;
      }

      // Coach insight from voice memo processing
      if (l.coach_insight) {
        line += `\n  Coach noted: ${(l.coach_insight as string).slice(0, 120)}`;
      }

      // Extracted context (RPE, weather, terrain, partners)
      const ext = l.extracted_data as Record<string, unknown> | null;
      if (ext) {
        const ctx: string[] = [];
        if (ext.rpe) ctx.push(`RPE: ${ext.rpe}/10`);
        if (ext.weather) ctx.push(`Weather: ${ext.weather}`);
        if (ext.terrain) ctx.push(`Terrain: ${ext.terrain}`);
        if (ext.running_partners && Array.isArray(ext.running_partners) && ext.running_partners.length) ctx.push(`With: ${ext.running_partners.join(", ")}`);
        if (ext.sleep_quality) ctx.push(`Sleep: ${ext.sleep_quality}`);
        if (ext.fueling) ctx.push(`Fueling: ${ext.fueling}`);
        if (ext.effort_level) ctx.push(`Effort: ${ext.effort_level}`);
        if (ctx.length > 0) line += `\n  Context: ${ctx.join(" | ")}`;
      }

      return line;
    })
    .join("\n\n");

  // Plan vs actual — show what was scheduled and whether it was done
  const planComparison = ctx.thisWeekScheduled
    .filter((w) => w.workout_type !== "rest")
    .map((w) => {
      const name = w.workout_data && (w.workout_data as Record<string, unknown>).name
        ? (w.workout_data as Record<string, unknown>).name
        : w.workout_type.replace(/_/g, " ");
      const plannedDist = w.workout_data && (w.workout_data as Record<string, unknown>).total_distance_km
        ? `${((w.workout_data as Record<string, unknown>).total_distance_km as number).toFixed(1)}mi`
        : "";
      const statusIcon = w.status === "completed" ? "DONE" : w.status === "skipped" ? "SKIPPED" : "PENDING";
      return `${w.date}: ${name} ${plannedDist} → ${statusIcon}`;
    })
    .join("\n");

  // Missed workouts
  const missed = ctx.thisWeekScheduled
    .filter(
      (w) =>
        w.workout_type !== "rest" &&
        (w.status === "skipped" || w.status === "scheduled")
    )
    .map((w) => `${w.date} (${w.workout_type}): ${w.status}`);
  const missedText =
    missed.length > 0 ? missed.join("\n") : "None — all workouts completed.";

  // Next week preview
  const nextWeekPreview = ctx.nextWeekScheduled
    .filter((w) => w.workout_type !== "rest")
    .map((w) => {
      const name =
        w.workout_data && (w.workout_data as Record<string, unknown>).name
          ? (w.workout_data as Record<string, unknown>).name
          : w.workout_type;
      return `${w.date}: ${name}`;
    })
    .join("\n");

  // Fitness trajectory
  let fitnessTrajectory = "No fitness prediction data.";
  if (ctx.fitnessSnapshots.length > 0) {
    const latest = ctx.fitnessSnapshots[0] as Record<string, unknown>;
    fitnessTrajectory = `Latest prediction (${latest.confidence} confidence): Marathon ${formatTotalTime((latest.predicted_marathon_seconds as number) || 0)}, Half ${formatTotalTime((latest.predicted_half_seconds as number) || 0)}, 10K ${formatTotalTime((latest.predicted_10k_seconds as number) || 0)}`;
    if (ctx.fitnessGapSeconds !== null) {
      const sign = ctx.fitnessGapSeconds > 0 ? "+" : "";
      fitnessTrajectory += `\nGap to goal: ${sign}${formatTotalTime(Math.abs(ctx.fitnessGapSeconds))} (${ctx.fitnessGapSeconds > 0 ? "slower than target" : "faster than target"})`;
    }
  }

  // Alerts text
  const alertsText =
    alerts.length > 0
      ? alerts
          .map(
            (a) =>
              `[${a.severity.toUpperCase()}] ${a.title}: ${a.message}`
          )
          .join("\n")
      : "No alerts triggered.";

  return `You are an experienced running coach writing a weekly training review. This is YOUR athlete — you know their history, their goals, their patterns. Write like you're sitting across from them at a coffee shop, not generating a report.

PACE DIRECTION: In running, LOWER pace number = FASTER. 5:00/mi is fast, 9:00/mi is slow. "Too fast" means a LOWER number than prescribed. "Too slow" means a HIGHER number. Running slower than easy pace on recovery days is good.

WRITING RULES:
- BANNED: "impressive", "journey", "fantastic", "amazing", "solid work", "great job", "nicely done", "Let's dive in", "I notice", "Overall", "Keep it up", "You've got this", "Moving forward"
- Short sentences. Fragments are fine. Like a person talks.
- Reference SPECIFIC days, paces, and workouts. "Your Tuesday 10x800 at 2:48" not "your interval session."
- No markdown. Plain text only.
- If something is wrong, say it directly. Don't hedge.
- One sharp observation > five generic compliments.

ATHLETE:
${profileSummary}
${goalSummary}${injuryCtx}${ctx.athleteProfileContext}
${ctx.athleteStateContext ? `\nATHLETE STATE (big-picture snapshot):\n${ctx.athleteStateContext}\n` : ""}
THIS WEEK (${ctx.weekStart} to ${ctx.weekEnd}):
Runs: ${metrics.runCount} | Miles: ${metrics.totalMiles} | Time: ${formatDuration(metrics.totalMinutes)}
Compliance: ${Math.round(metrics.complianceScore * 100)}%
Avg pace: ${formatPace(metrics.avgPaceSeconds)}${metrics.easyPaceAvg ? ` | Easy: ${formatPace(metrics.easyPaceAvg)}` : ""}${metrics.workoutPaceAvg ? ` | Quality: ${formatPace(metrics.workoutPaceAvg)}` : ""}
Long run: ${metrics.longRunMiles ? `${metrics.longRunMiles}mi @ ${metrics.longRunPace ? formatPace(metrics.longRunPace) : "N/A"}` : "none"}
ACWR: ${metrics.acwr} (${metrics.acwr > 1.3 ? "HIGH RISK" : metrics.acwr > 1.2 ? "elevated" : metrics.acwr < 0.8 ? "low — undertrained" : "healthy"}) | 4wk avg: ${metrics.chronicLoad}mi
Volume change: ${metrics.volumeChangePct > 0 ? "+" : ""}${metrics.volumeChangePct}% vs last week
Mood: ${metrics.moodTrend}${Object.keys(metrics.moodDistribution).length > 0 ? ` (${Object.entries(metrics.moodDistribution).map(([k, v]) => `${k}:${v}`).join(", ")})` : ""}

SCHEDULED vs COMPLETED:
${planComparison || "No plan active."}

WORKOUT LOG (with pace segments from GPS watch):
${workoutLog || "No workouts logged."}

EFFORT DISTRIBUTION:
${buildZoneSummary(ctx.thisWeekLogs)}

MISSED:
${missedText}

NEXT WEEK:
${nextWeekPreview || "Nothing scheduled."}

ALERTS:
${alertsText}

FITNESS:
${fitnessTrajectory}

---

ANALYSIS FRAMEWORK — address ALL of these in your narrative:

1. KEY WORKOUT EXECUTION: How did the most important workout(s) go? Did they hit target paces? Did they fade, negative split, or hold steady? Reference specific pace segments.

2. EASY DAY DISCIPLINE: Were recovery/easy runs ACTUALLY easy? Compare easy day paces to quality day paces. If the gap is too small (<1:00/mi), call it out — they're not recovering.

3. VOLUME & LOAD: Is the ACWR concerning? Was the volume jump appropriate? Are they building too fast or stagnating?

4. PATTERN RECOGNITION: What trends do you see across the past few weeks in the data? Cardiac drift? Fatigue accumulation? Mood decline? Improving interval paces?

5. NEXT WEEK SETUP: Based on what you see, what should they prioritize? Be specific — not "run easy" but "keep Wednesday under 8:00/mi pace and cut the long run to 12 instead of 15."

Respond with ONLY a JSON object:

{
  "narrative": "4-6 paragraphs addressing the framework above. Be specific with paces, days, and data. No filler.",

  "adjustments": [
    {
      "target_workout_type": "long_run|easy|tempo|intervals|recovery|rest",
      "target_date": "YYYY-MM-DD or null",
      "action": "reduce_distance|increase_distance|reduce_intensity|increase_intensity|swap_to_easy|add_recovery|skip|maintain",
      "original_value": "current plan",
      "recommended_value": "recommended change",
      "rationale": "why — 1-2 sentences",
      "priority": "high|medium|low"
    }
  ],

  "focus_areas": ["1-3 words each", "max 3 items"]
}`;
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

function splitIntoWeeks(
  logs: TrainingLogRow[],
  currentWeekStart: string
): TrainingLogRow[][] {
  const weeks: TrainingLogRow[][] = [];
  const currentStart = new Date(currentWeekStart);

  for (let i = 1; i <= 4; i++) {
    const weekEnd = new Date(currentStart);
    weekEnd.setDate(weekEnd.getDate() - (i - 1) * 7 - 1);
    const weekStart = new Date(weekEnd);
    weekStart.setDate(weekStart.getDate() - 6);

    const weekLogs = logs.filter((l) => {
      if (!l.workout_date) return false;
      const d = new Date(l.workout_date);
      return d >= weekStart && d <= weekEnd;
    });

    weeks.push(weekLogs);
  }

  return weeks;
}

const RACE_DISTANCES: Record<string, number> = {
  marathon: 26.2,
  half_marathon: 13.1,
  "10k": 6.2,
  "5k": 3.1,
  mile: 1.0,
};

function calculateRacePace(
  distance: string,
  totalSeconds: number
): number | null {
  const miles = RACE_DISTANCES[distance];
  if (!miles || totalSeconds <= 0) return null;
  return totalSeconds / miles;
}

function getPredictedTimeForDistance(
  snapshot: Record<string, unknown>,
  distance: string
): number | null {
  const key = `predicted_${distance === "half_marathon" ? "half" : distance}_seconds`;
  const val = snapshot[key];
  return typeof val === "number" ? val : null;
}

function getCurrentPlanWeek(
  planStartDate: string,
  weekStart: string
): number {
  const start = new Date(planStartDate);
  const week = new Date(weekStart);
  const diffMs = week.getTime() - start.getTime();
  return Math.max(1, Math.ceil(diffMs / (7 * 24 * 60 * 60 * 1000)) + 1);
}

function getTotalPlanWeeks(startDate: string, endDate: string): number {
  const start = new Date(startDate);
  const end = new Date(endDate);
  const diffMs = end.getTime() - start.getTime();
  return Math.max(1, Math.ceil(diffMs / (7 * 24 * 60 * 60 * 1000)));
}

function formatTotalTime(totalSeconds: number): string {
  if (totalSeconds <= 0) return "--:--";
  const hrs = Math.floor(totalSeconds / 3600);
  const mins = Math.floor((totalSeconds % 3600) / 60);
  const secs = Math.round(totalSeconds % 60);
  if (hrs > 0) {
    return `${hrs}:${mins.toString().padStart(2, "0")}:${secs.toString().padStart(2, "0")}`;
  }
  return `${mins}:${secs.toString().padStart(2, "0")}`;
}

function parsePaceString(pace: string): number | null {
  const match = pace.match(/(\d+):(\d+)/);
  if (!match) return null;
  return parseInt(match[1]) * 60 + parseInt(match[2]);
}

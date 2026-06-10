/**
 * Post-Run Reconciliation
 *
 * Triggered after a training_log is inserted (via DB webhook or edge function call).
 * Compares the actual run against the scheduled workout target for that date:
 *   - Pace delta (seconds per mile, faster/slower)
 *   - Distance delta (miles over/under)
 *   - Duration delta (minutes over/under)
 *   - RPE/mood
 *
 * Writes a structured delta to coaching_feedback (new row) so the coaching-agent
 * can read it in future conversations. Also marks the scheduled workout as completed.
 *
 * This is NOT an AI call — pure data comparison, fast and cheap.
 */

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { getAuthenticatedUser, unauthorizedResponse } from "../_shared/auth.ts";
import { adjustPace, buildWeatherJson, heatCategoryLabel } from "../_shared/pace-heat-adjustment.ts";
import { corsHeaders } from "../_shared/cors.ts";

// ── Types ──────────────────────────────────────────────────────

interface ReconciliationDelta {
  training_log_id: string;
  scheduled_workout_id: string | null;
  workout_date: string;
  workout_type: string;

  // Plan targets
  planned_distance_miles: number | null;
  planned_pace_per_mile: string | null;
  planned_duration_minutes: number | null;

  // Actuals
  actual_distance_miles: number | null;
  actual_pace_per_mile: string | null;
  actual_duration_minutes: number | null;

  // Deltas
  distance_delta_miles: number | null;
  pace_delta_seconds: number | null;  // positive = slower than target
  duration_delta_minutes: number | null;
  pace_direction: "faster" | "slower" | "on_target" | "no_data";

  // Weather-adjusted
  weather_adjusted_target_pace: string | null;
  weather_adjustment_seconds: number | null;
  pace_delta_vs_adjusted: number | null;  // positive = slower than adjusted target
  pace_direction_adjusted: "faster" | "slower" | "on_target" | "no_data";
  heat_category: string | null;

  // Context
  mood: string | null;
  source: string;  // "coach_locked", "easy_fill", etc.
  is_quality_session: boolean;

  // Summary
  summary: string;
}

interface ScheduledWorkout {
  id: string;
  date: string | null;
  workout_type: string | null;
  workout_data: Record<string, any> | null;
  status: string | null;
  source: string | null;
  is_movable: boolean | null;
  plan_id: string | null;
  training_plans: { user_id: string } | { user_id: string }[] | null;
  // Columns referenced but not in the select projection above;
  // undefined at runtime unless the projection is widened.
  weather_forecast?: Record<string, any> | null;
  pool_template_id?: string | null;
}

// ── Main Handler ───────────────────────────────────────────────

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const body = await req.json();
    const { training_log_id, user_id: bodyUserId } = body;

    if (!training_log_id) {
      return new Response(
        JSON.stringify({ error: "training_log_id is required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Auth: accept JWT or service-role with user_id in body (for trigger calls)
    let userId = await getAuthenticatedUser(req);
    if (!userId && bodyUserId) userId = bodyUserId;
    if (!userId) return unauthorizedResponse(corsHeaders);

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    // 1. Fetch the training log
    const { data: log, error: logErr } = await supabase
      .from("training_logs")
      .select("id, user_id, workout_date, workout_distance_miles, workout_duration_minutes, workout_type, workout_pace_per_mile, mood, cleaned_notes")
      .eq("id", training_log_id)
      .single();

    if (logErr || !log) {
      return new Response(
        JSON.stringify({ error: "Training log not found" }),
        { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    if (!log.workout_date) {
      return new Response(
        JSON.stringify({ skipped: "no workout_date on log" }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // 2. Find the scheduled workout for this date
    // Join through training_plans to get the user's active plan
    const logDate = log.workout_date.split("T")[0];

    const { data: scheduledRaw } = await supabase
      .from("scheduled_workouts")
      .select("id, date, workout_type, workout_data, status, source, is_movable, plan_id, training_plans!inner(user_id)")
      .eq("training_plans.user_id", userId)
      .eq("date", logDate)
      .neq("workout_type", "rest")
      .order("session")
      .limit(1)
      .maybeSingle();

    const scheduled = scheduledRaw as ScheduledWorkout | null;

    // 2b. Fetch weather for the workout (use scheduled forecast or fetch actual)
    let weatherData: Record<string, any> | null = null;
    const scheduledForecast = scheduled?.weather_forecast as Record<string, any> | null;

    // Try to get actual weather from user's home location
    const { data: profile } = await supabase
      .from("user_profiles")
      .select("home_lat, home_lon")
      .eq("user_id", userId)
      .maybeSingle();

    if (profile?.home_lat && profile?.home_lon) {
      try {
        const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
        const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
        const weatherResp = await fetch(`${supabaseUrl}/functions/v1/fetch-workout-weather`, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${serviceKey}`,
            apikey: serviceKey,
          },
          body: JSON.stringify({
            lat: profile.home_lat,
            lon: profile.home_lon,
            timestamp: log.workout_date,
            kind: "actual",
          }),
          signal: AbortSignal.timeout(10000),
        });
        if (weatherResp.ok) {
          const wr = await weatherResp.json();
          weatherData = wr.weather || null;
        }
      } catch (e) {
        console.warn("Weather fetch failed:", e);
      }
    }

    // Fall back to scheduled forecast if no actual weather
    if (!weatherData && scheduledForecast) {
      weatherData = scheduledForecast;
    }

    // 3. Compute deltas (with weather)
    const delta = computeDelta(log, scheduled, weatherData);

    // 3b. Store weather on training_log + adjusted pace delta
    const logUpdates: Record<string, any> = {};
    if (weatherData) logUpdates.weather_actual = weatherData;
    if (delta.weather_adjustment_seconds != null && delta.weather_adjustment_seconds > 0) {
      logUpdates.weather_adjusted_pace_delta_seconds_per_mile = delta.weather_adjustment_seconds;
    }
    if (Object.keys(logUpdates).length > 0) {
      await supabase.from("training_logs").update(logUpdates).eq("id", log.id);
    }

    // 4. Write delta to ai_insights for coaching-agent visibility
    await supabase.from("ai_insights").insert({
      user_id: userId,
      insight_type: "run_reconciliation",
      title: delta.summary,
      summary: delta.summary,
      full_analysis: delta,
      priority: delta.is_quality_session && Math.abs(delta.pace_delta_vs_adjusted || delta.pace_delta_seconds || 0) > 15 ? "high" : "low",
      trigger_source: "post_run_reconciliation",
      expires_at: new Date(Date.now() + 14 * 86400000).toISOString(), // 14 days
    });

    // 5. Auto-mark scheduled workout as completed if not already
    if (scheduled && scheduled.status === "scheduled") {
      await supabase
        .from("scheduled_workouts")
        .update({
          status: "completed",
          completed_workout_id: log.id,
        })
        .eq("id", scheduled.id);

      // Also mark the quality_session_template as placed if it exists
      if (scheduled.pool_template_id) {
        await supabase
          .from("quality_session_templates")
          .update({ is_placed: true })
          .eq("id", scheduled.pool_template_id);
      }
    }

    console.log(`[post-run-reconciliation] ${userId} ${logDate}: ${delta.summary}`);

    return new Response(
      JSON.stringify({ delta }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (error) {
    console.error("[post-run-reconciliation] Error:", error);
    return new Response(
      JSON.stringify({ error: String(error) }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});

// ── Delta Computation ──────────────────────────────────────────

function computeDelta(log: any, scheduled: any | null, weather: Record<string, any> | null = null): ReconciliationDelta {
  const qualityTypes = new Set(["tempo", "intervals", "long_run", "race", "progression"]);

  // No scheduled workout — this was an unplanned run
  if (!scheduled) {
    return {
      training_log_id: log.id,
      scheduled_workout_id: null,
      workout_date: log.workout_date.split("T")[0],
      workout_type: log.workout_type || "easy",
      planned_distance_miles: null,
      planned_pace_per_mile: null,
      planned_duration_minutes: null,
      actual_distance_miles: log.workout_distance_miles,
      actual_pace_per_mile: log.workout_pace_per_mile,
      actual_duration_minutes: log.workout_duration_minutes,
      distance_delta_miles: null,
      pace_delta_seconds: null,
      duration_delta_minutes: null,
      pace_direction: "no_data",
      weather_adjusted_target_pace: null,
      weather_adjustment_seconds: null,
      pace_delta_vs_adjusted: null,
      pace_direction_adjusted: "no_data",
      heat_category: weather ? (weather.heat_category as string) : null,
      mood: log.mood,
      source: "unplanned",
      is_quality_session: false,
      summary: `Unplanned ${log.workout_type || "run"}: ${log.workout_distance_miles?.toFixed(1) || "?"}mi${log.mood ? `, felt ${log.mood}` : ""}`,
    };
  }

  const wd = scheduled.workout_data as Record<string, any> | null;
  const isQuality = qualityTypes.has(scheduled.workout_type);

  // Extract planned values
  const plannedDistKm = wd?.total_distance_km as number | undefined;
  const plannedDistMi = plannedDistKm
    ? plannedDistKm / 1.60934
    : (wd?.total_distance_mi as number | undefined) ?? null;
  const plannedPace = (wd?.target_pace as string) ?? null;
  const plannedDuration = (wd?.estimated_duration_minutes as number) ?? null;

  // Actuals
  const actualMi = log.workout_distance_miles as number | null;
  const actualPace = log.workout_pace_per_mile as string | null;
  const actualDuration = log.workout_duration_minutes as number | null;

  // Distance delta
  const distDelta = (plannedDistMi != null && actualMi != null)
    ? actualMi - plannedDistMi
    : null;

  // Pace delta
  let paceDelta: number | null = null;
  let paceDirection: "faster" | "slower" | "on_target" | "no_data" = "no_data";
  if (plannedPace && actualPace) {
    const plannedSec = parsePace(plannedPace);
    const actualSec = parsePace(actualPace);
    if (plannedSec > 0 && actualSec > 0) {
      paceDelta = actualSec - plannedSec;
      if (Math.abs(paceDelta) <= 5) paceDirection = "on_target";
      else if (paceDelta < 0) paceDirection = "faster";
      else paceDirection = "slower";
    }
  }

  // Duration delta
  const durDelta = (plannedDuration != null && actualDuration != null)
    ? actualDuration - plannedDuration
    : null;

  // Build summary
  const parts: string[] = [];
  const workoutName = wd?.name || scheduled.workout_type.replace(/_/g, " ");
  parts.push(workoutName);

  if (distDelta != null && Math.abs(distDelta) >= 0.3) {
    const sign = distDelta > 0 ? "+" : "";
    parts.push(`${sign}${distDelta.toFixed(1)}mi vs plan`);
  }

  if (paceDelta != null && Math.abs(paceDelta) > 5) {
    const abs = Math.abs(paceDelta);
    const formatted = abs >= 60
      ? `${Math.floor(abs / 60)}:${String(abs % 60).padStart(2, "0")}`
      : `${abs}s`;
    parts.push(`${formatted} ${paceDirection} than target`);
  } else if (paceDirection === "on_target") {
    parts.push("pace on target");
  }

  // Weather-adjusted pace comparison (the real story)
  let weatherAdjustedTarget: string | null = null;
  let weatherAdjSeconds: number | null = null;
  let paceVsAdjusted: number | null = null;
  let paceDirectionAdj: "faster" | "slower" | "on_target" | "no_data" = "no_data";
  const heatCat = weather?.heat_category as string | null;

  if (weather && plannedPace && actualPace) {
    const tempF = weather.temp_f as number;
    const dewF = weather.dew_point_f as number;
    if (tempF != null && dewF != null) {
      const plannedSec = parsePace(plannedPace);
      const actualSec = parsePace(actualPace);
      if (plannedSec > 0 && actualSec > 0) {
        const adj = adjustPace(plannedSec, tempF, dewF);
        weatherAdjSeconds = adj.adjustmentSecondsPerMile;
        weatherAdjustedTarget = formatSecAsPace(adj.adjustedPaceSeconds);
        paceVsAdjusted = actualSec - adj.adjustedPaceSeconds;

        if (Math.abs(paceVsAdjusted) <= 5) paceDirectionAdj = "on_target";
        else if (paceVsAdjusted < 0) paceDirectionAdj = "faster";
        else paceDirectionAdj = "slower";

        // Add weather-adjusted summary
        if (weatherAdjSeconds > 2) {
          if (paceDirectionAdj === "on_target") {
            parts.push(`(heat-adjusted: ON TARGET at ${weatherAdjustedTarget})`);
          } else {
            const adjAbs = Math.abs(Math.round(paceVsAdjusted));
            parts.push(`(heat-adjusted: ${adjAbs}s ${paceDirectionAdj} at ${weatherAdjustedTarget})`);
          }
        }
      }
    }
  }

  if (heatCat && heatCat !== "ideal") {
    parts.push(`${Math.round(weather!.temp_f as number)}°F ${heatCat}`);
  }

  if (log.mood) parts.push(`felt ${log.mood}`);

  return {
    training_log_id: log.id,
    scheduled_workout_id: scheduled.id,
    workout_date: log.workout_date.split("T")[0],
    workout_type: scheduled.workout_type,
    planned_distance_miles: plannedDistMi,
    planned_pace_per_mile: plannedPace,
    planned_duration_minutes: plannedDuration,
    actual_distance_miles: actualMi,
    actual_pace_per_mile: actualPace,
    actual_duration_minutes: actualDuration,
    distance_delta_miles: distDelta,
    pace_delta_seconds: paceDelta,
    duration_delta_minutes: durDelta,
    pace_direction: paceDirection,
    weather_adjusted_target_pace: weatherAdjustedTarget,
    weather_adjustment_seconds: weatherAdjSeconds,
    pace_delta_vs_adjusted: paceVsAdjusted != null ? Math.round(paceVsAdjusted) : null,
    pace_direction_adjusted: paceDirectionAdj,
    heat_category: heatCat,
    mood: log.mood,
    source: scheduled.source || "legacy",
    is_quality_session: isQuality,
    summary: parts.join(" — "),
  };
}

function formatSecAsPace(sec: number): string {
  const total = Math.round(sec);
  const m = Math.floor(total / 60);
  const s = total % 60;
  return `${m}:${String(s).padStart(2, "0")}`;
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

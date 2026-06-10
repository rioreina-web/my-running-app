/**
 * reconcile-log — closes the loop on a single training_log.
 *
 * For every training_logs insert (see the accompanying migration trigger),
 * this function:
 *   1. Matches the log to a scheduled_workouts row on same user + date ±1d.
 *   2. Extracts an aggregate target pace (weighted by distance over hard
 *      steps only — warmup/cooldown ignored) from the matched workout.
 *   3. Fetches weather for the log's date+location (GPS start → home →
 *      skip). Uses _shared/weather.ts.
 *   4. Applies the heat adjustment via _shared/pace-heat.ts to produce
 *      adjusted_target_pace_seconds.
 *   5. Inserts a workout_reconciliations row with the delta + hit/miss.
 *
 * Unplanned runs (no scheduled match) still get a row — with null target
 * paces — so the weather is on record for that date.
 *
 * Request body: { training_log_id: UUID }
 * Auth: service role (called by Postgres trigger) or authenticated user.
 */

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { adjustPaceForHeat } from "../_shared/pace-heat.ts";
import { fetchWeather } from "../_shared/weather.ts";

import { corsHeaders } from "../_shared/cors.ts";
const DEFAULT_TOLERANCE_SECONDS = 5;
const HARD_STEP_TYPES = new Set(["active"]); // warmup / recovery / cooldown excluded

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  // Shared-secret auth. Trigger sends the secret (stored in Vault) as the
  // Authorization bearer; we match against the same string stored as the
  // RECONCILE_SHARED_SECRET env var. This sidesteps the JWT-only gateway
  // verification for new-format sb_secret_* keys.
  const expectedSecret = Deno.env.get("RECONCILE_SHARED_SECRET") ?? "";
  const bearer = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (!expectedSecret || bearer !== expectedSecret) {
    return new Response(JSON.stringify({ error: "Authentication required" }), {
      status: 401,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  try {
    const body = await req.json().catch(() => ({}));
    const trainingLogId: string | undefined = body?.training_log_id;
    if (!trainingLogId) return errorResponse(400, "training_log_id required");

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    // 1. Load the training_log.
    const { data: log, error: logErr } = await supabase
      .from("training_logs")
      .select("id, user_id, workout_date, workout_distance_miles, workout_duration_minutes, pace_segments, external_streams")
      .eq("id", trainingLogId)
      .maybeSingle();
    if (logErr || !log) return errorResponse(404, logErr?.message ?? "training_log not found");

    // 2. Match to a scheduled_workouts row (same user, date within ±1 day).
    const workoutDate = new Date(log.workout_date);
    const prev = new Date(workoutDate); prev.setDate(prev.getDate() - 1);
    const next = new Date(workoutDate); next.setDate(next.getDate() + 1);
    const fmt = (d: Date) => d.toISOString().slice(0, 10);

    const { data: candidates } = await supabase
      .from("scheduled_workouts")
      .select("id, date, workout_data, plan_id, training_plans!inner(user_id)")
      .gte("date", fmt(prev))
      .lte("date", fmt(next))
      .eq("training_plans.user_id", log.user_id);

    const scheduled = pickBestMatch(candidates ?? [], fmt(workoutDate));

    // 3. Compute target pace from scheduled workout's hard steps.
    const targetPaceSeconds = scheduled ? aggregateTargetPace(scheduled.workout_data) : null;

    // 4. Compute actual pace from the log.
    const actualPaceSeconds = computeActualPace(log);

    // 5. Location + weather.
    const loc = await resolveLocation(supabase, log);
    const observation = loc
      ? await fetchWeather(supabase, {
          lat: loc.lat,
          lon: loc.lon,
          timestamp: workoutDate,
          kind: workoutDate < new Date() ? "historical" : "forecast",
        })
      : null;

    // 6. Apply heat adjustment when we have both a target and weather.
    let adjustedTarget: number | null = null;
    let delta: number | null = null;
    let hitTarget: boolean | null = null;
    let adjustmentBundle: Record<string, unknown> | null = null;
    if (targetPaceSeconds && observation?.temperature_f != null && observation?.dew_point_f != null) {
      const adj = adjustPaceForHeat(targetPaceSeconds, observation.temperature_f, observation.dew_point_f);
      adjustedTarget = Math.round(adj.adjustedSeconds * 10) / 10;
      adjustmentBundle = {
        composite_score: adj.compositeScore,
        adjustment_percent: adj.adjustmentPercent,
        multiplier: adj.multiplier,
        heat_category: adj.heatCategory,
      };
      if (actualPaceSeconds != null) {
        delta = Math.round((actualPaceSeconds - adjustedTarget) * 10) / 10;
        hitTarget = Math.abs(delta) <= DEFAULT_TOLERANCE_SECONDS;
      }
    }

    // 7. Insert the reconciliation row. Upsert by training_log_id to make
    // the trigger idempotent on duplicate inserts.
    const row = {
      user_id: log.user_id,
      training_log_id: log.id,
      scheduled_workout_id: scheduled?.id ?? null,
      target_pace_seconds_per_mile: targetPaceSeconds,
      actual_pace_seconds_per_mile: actualPaceSeconds,
      weather_actual_jsonb: observation
        ? { ...observation, source: "open-meteo" }
        : null,
      weather_forecast_jsonb: null, // populated when we move forecasting into this fn later
      adjusted_target_pace_seconds: adjustedTarget,
      adjusted_pace_delta_seconds: delta,
      hit_target: hitTarget,
      tolerance_applied_seconds: DEFAULT_TOLERANCE_SECONDS,
      notes_json: adjustmentBundle ? { adjustment: adjustmentBundle } : null,
    };

    const { data: upserted, error: upsertErr } = await supabase
      .from("workout_reconciliations")
      .upsert(row, { onConflict: "training_log_id" })
      .select()
      .single();
    if (upsertErr) {
      console.error("workout_reconciliations upsert failed", upsertErr);
      return errorResponse(500, upsertErr.message);
    }

    // 8. Fan out to adapt-plan when the delta or context warrants it.
    if (shouldTriggerAdapt(log, row)) {
      const reason = adaptReason(log, row);
      console.log(`[reconcile-log] invoking adapt-plan (${reason}) for user=${log.user_id}`);
      // Fire-and-forget — the response isn't awaited.
      supabase.functions
        .invoke("adapt-plan", { body: { user_id: log.user_id, trigger: reason } })
        .catch((err: unknown) => console.warn("[reconcile-log] adapt-plan invoke failed", err));
    }

    return new Response(JSON.stringify(upserted), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err) {
    console.error("[reconcile-log] unhandled", err);
    return errorResponse(500, String(err));
  }
});

// ── Helpers ────────────────────────────────────────────────────────

function errorResponse(status: number, message: string): Response {
  return new Response(JSON.stringify({ error: message }), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

/** Decide whether to invoke adapt-plan for this reconciliation. */
// deno-lint-ignore no-explicit-any
function shouldTriggerAdapt(log: any, row: Record<string, unknown>): boolean {
  const delta = row.adjusted_pace_delta_seconds as number | null | undefined;
  if (typeof delta === "number" && Math.abs(delta) > 10) return true;
  if (log?.workout_type === "race") return true;
  return false;
}

// deno-lint-ignore no-explicit-any
function adaptReason(log: any, row: Record<string, unknown>): string {
  if (log?.workout_type === "race") return "race_result";
  const delta = row.adjusted_pace_delta_seconds as number | null | undefined;
  if (typeof delta === "number" && delta >= 10) return "pace_under_target";
  if (typeof delta === "number" && delta <= -10) return "pace_over_target";
  return "reconcile";
}

// deno-lint-ignore no-explicit-any
function pickBestMatch(candidates: any[], targetDate: string): any | null {
  if (candidates.length === 0) return null;
  const exact = candidates.find((c) => c.date === targetDate);
  return exact ?? candidates[0];
}

/** Weighted-by-distance average of target_pace_seconds_per_mile over hard
 *  steps. Returns null when no resolvable hard step exists. */
function aggregateTargetPace(workoutData: unknown): number | null {
  if (!workoutData || typeof workoutData !== "object") return null;
  const data = workoutData as Record<string, unknown>;
  const steps = Array.isArray(data.steps) ? (data.steps as Record<string, unknown>[]) : [];
  let weight = 0;
  let weighted = 0;
  for (const step of steps) {
    const stepType = (step.stepType as string | undefined) ?? "active";
    if (!HARD_STEP_TYPES.has(stepType)) continue;
    const sec = step.target_pace_seconds_per_mile as number | undefined;
    if (typeof sec !== "number" || sec <= 0) continue;
    const d = typeof step.durationValue === "number" ? step.durationValue : 1;
    weighted += sec * d;
    weight += d;
  }
  return weight > 0 ? Math.round((weighted / weight) * 10) / 10 : null;
}

// deno-lint-ignore no-explicit-any
function computeActualPace(log: any): number | null {
  const miles = log.workout_distance_miles as number | null;
  const mins = log.workout_duration_minutes as number | null;
  if (!miles || miles <= 0 || !mins || mins <= 0) return null;
  return Math.round(((mins * 60) / miles) * 10) / 10;
}

// deno-lint-ignore no-explicit-any
async function resolveLocation(supabase: any, log: any): Promise<{ lat: number; lon: number } | null> {
  // Prefer GPS start from external_streams when available.
  const streams = log.external_streams?.streams;
  const latlng = streams?.latlng as Array<[number, number]> | undefined;
  if (latlng && latlng.length > 0 && latlng[0].length === 2) {
    return { lat: latlng[0][0], lon: latlng[0][1] };
  }
  // Fallback to user_profiles.home_lat/home_lon.
  const { data: profile } = await supabase
    .from("user_profiles")
    .select("home_lat, home_lon")
    .eq("user_id", log.user_id)
    .maybeSingle();
  if (profile?.home_lat != null && profile?.home_lon != null) {
    return { lat: profile.home_lat, lon: profile.home_lon };
  }
  return null;
}

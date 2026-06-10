/**
 * build-pace-profile Edge Function
 *
 * Upserts the caller's `athlete_pace_profiles` row from the latest
 * fitness_snapshots row + active goal. The output is the single source of
 * truth for plan generation — every scheduled_workouts step resolves its
 * `target_pace_seconds_per_mile` from this profile.
 *
 * Request body:
 *   { user_id: UUID }   -- optional if JWT carries a user claim
 *
 * Responses:
 *   200 -> the upserted athlete_pace_profiles row
 *   401 -> no valid auth
 *   404 -> user has no fitness_snapshot yet
 *   500 -> upstream error
 *
 * Auth: verify_jwt = true. Service-role cross-function callers can pass
 * `user_id` in the body; user-level callers have their claim used directly.
 *
 * NOTE: The spec prompt said "fetch the latest user_goals row" for goal
 * context, but `user_goals` only has title/date — it doesn't store race
 * distance or target time. The active `training_plans` row is the only
 * place that has both, so we read from there.
 */

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { requireAuthOrServiceRole } from "../_shared/auth.ts";
import { computePaceProfile, type ResolvedPace } from "../_shared/pace-zones.ts";
import {
  derivePaceTableFromGoal,
  pickAnchorRace,
  raceKeyForInput,
  RACE_DISTANCE_MI,
} from "../_shared/paces.ts";
import { getConfirmedRaces } from "../_shared/resolve-pace.ts";
import { corsHeaders } from "../_shared/cors.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const body = await req.json().catch(() => ({}));
    const payloadUserId: string | undefined = body?.user_id;

    // Resolve the target user: a user JWT (body.user_id must match the token)
    // or a service-role caller that names the subject user (cross-calls).
    // Previously fell back to body.user_id whenever the JWT path returned
    // null, letting an anon-key caller build/read any user's pace profile.
    const auth = await requireAuthOrServiceRole(req, payloadUserId, corsHeaders);
    if ("response" in auth) return auth.response;
    const userId = auth.userId;

    const supabase = createClient(supabaseUrl, serviceKey);

    // 1. Latest fitness_snapshots row
    const { data: snapshot, error: snapErr } = await supabase
      .from("fitness_snapshots")
      .select("*")
      .eq("user_id", userId)
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle();

    if (snapErr) {
      console.error("fitness_snapshots fetch error", snapErr);
      return errorResponse(500, "Failed to read fitness data");
    }

    // 1b. Confirmed race anchor (Phase 2 sub-task C). A real race result in
    // athlete_state.confirmed_races outranks snapshot predictions: the
    // profile this function writes is what the pace engine (and therefore
    // get-pace-zones, plan materialization, the pace chart) treats as
    // athlete-truth, so anchoring it on the race is what flips the product
    // from goal-aspiration zones to actual-fitness zones.
    const confirmedRaces = await getConfirmedRaces(supabase, userId);
    const raceAnchor = pickAnchorRace(confirmedRaces);

    if (!snapshot && !raceAnchor) {
      return errorResponse(
        404,
        "No fitness data available — run an assessment to see your paces."
      );
    }

    // 2. Compute the six paces + confidence
    const resolved = snapshot ? computePaceProfile(snapshot) : null;
    if (!resolved && !raceAnchor) {
      return errorResponse(
        404,
        "Fitness snapshot present but empty — assessment never produced predictions."
      );
    }

    // 2b. Overlay the race anchor. The full ladder is re-derived from the
    // race performance (race-equivalence ratios in _shared/paces.ts), and
    // every distance the ladder produces overrides the snapshot-derived
    // value with confidence "high" and the race date as source date.
    let raceResolved: Partial<Record<"easy" | "marathon" | "half" | "tenK" | "fiveK" | "mile", ResolvedPace>> = {};
    if (raceAnchor) {
      const key = raceKeyForInput(raceAnchor.distanceKey);
      const miles = RACE_DISTANCE_MI[key];
      if (miles > 0) {
        const table = derivePaceTableFromGoal(
          raceAnchor.finishTimeSeconds / miles,
          raceAnchor.distanceKey,
        );
        const asPace = (sec: number | undefined): ResolvedPace | undefined =>
          typeof sec === "number" && sec > 0
            ? { secondsPerMile: Math.round(sec), confidence: "high", sourceDate: raceAnchor.date }
            : undefined;
        raceResolved = {
          easy: asPace(table.easy),
          marathon: asPace(table.mp),
          half: asPace(table.hm),
          tenK: asPace(table.tenK),
          fiveK: asPace(table.fiveK),
          mile: asPace(table.mile),
        };
      }
    }

    // 3. Pull goal context from the active training_plan (user_goals has no
    // race distance/time columns, so it can't answer this).
    const { data: activePlan } = await supabase
      .from("training_plans")
      .select("target_race_distance, target_time_seconds")
      .eq("user_id", userId)
      .eq("status", "active")
      .order("start_date", { ascending: false })
      .limit(1)
      .maybeSingle();

    const goalRaceDistance = normalizeDistance(activePlan?.target_race_distance);
    const goalTimeSeconds = activePlan?.target_time_seconds ?? null;

    // 4. Build the upsert row. Race-anchored values win per distance;
    // snapshot-derived values fill whatever the race ladder didn't cover.
    const upsertRow = {
      user_id: userId,
      goal_race_distance: goalRaceDistance,
      goal_time_seconds: goalTimeSeconds,
      based_on_snapshot_id: snapshot?.id ?? null,
      generated_at: new Date().toISOString(),
      ...paceColumns("easy", raceResolved.easy ?? resolved?.easy ?? null),
      ...paceColumns("marathon", raceResolved.marathon ?? resolved?.marathon ?? null),
      ...paceColumns("half", raceResolved.half ?? resolved?.half ?? null),
      ...paceColumns("ten_k", raceResolved.tenK ?? resolved?.tenK ?? null),
      ...paceColumns("five_k", raceResolved.fiveK ?? resolved?.fiveK ?? null),
      ...paceColumns("mile", raceResolved.mile ?? resolved?.mile ?? null),
    };

    const { data: upserted, error: upsertErr } = await supabase
      .from("athlete_pace_profiles")
      .upsert(upsertRow, { onConflict: "user_id" })
      .select()
      .single();

    if (upsertErr) {
      console.error("athlete_pace_profiles upsert error", upsertErr);
      return errorResponse(500, "Failed to write pace profile");
    }

    return new Response(JSON.stringify(upserted), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err) {
    console.error("Unhandled error in build-pace-profile", err);
    return errorResponse(500, "Unexpected error: " + String(err));
  }
});

// ── Helpers ──────────────────────────────────────────────

function errorResponse(status: number, message: string): Response {
  return new Response(
    JSON.stringify({ error: message }),
    { status, headers: { ...corsHeaders, "Content-Type": "application/json" } }
  );
}

function paceColumns(prefix: string, pace: ResolvedPace | null) {
  if (!pace) {
    return {
      [`${prefix}_pace_seconds`]: null,
      [`${prefix}_pace_confidence`]: null,
      [`${prefix}_pace_source_date`]: null,
    };
  }
  return {
    [`${prefix}_pace_seconds`]: pace.secondsPerMile,
    [`${prefix}_pace_confidence`]: pace.confidence,
    [`${prefix}_pace_source_date`]: pace.sourceDate,
  };
}

/** Coerce a training_plans.target_race_distance value to the
 * athlete_pace_profiles.goal_race_distance check constraint
 * ('mile','5K','10K','half','marathon'). Returns null if unmappable. */
function normalizeDistance(raw: string | null | undefined): string | null {
  if (!raw) return null;
  const s = raw.toLowerCase().replace(/[^a-z0-9]/g, "");
  if (s === "marathon") return "marathon";
  if (s === "halfmarathon" || s === "half" || s === "13.1") return "half";
  if (s === "10k" || s === "10000m") return "10K";
  if (s === "5k" || s === "5000m") return "5K";
  if (s === "mile" || s === "1mile" || s === "1mi") return "mile";
  return null;
}

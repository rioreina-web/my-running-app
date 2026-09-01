/**
 * Update an athlete's goal — distance, time, race date.
 *
 * Two modes:
 *   - plan_id supplied → update that training_plans row AND mirror the
 *     goal onto athlete_pace_profiles so paces stay in sync.
 *   - plan_id null/missing → no plan to update; just upsert
 *     athlete_pace_profiles. Used by GoalAndPacesCard and the onboarding
 *     sheet so an athlete can set a goal before subscribing to a plan.
 *
 * Athlete-initiated only. The AI never calls this directly. (See feedback
 * memory `feedback_ai_advises_never_acts.md`.) The AI may surface a
 * proposal in `plan_adjustments` with `auto_applied: false`; if accepted,
 * the iOS app calls THIS function to commit the change.
 *
 * Side effects:
 *   - Writes new goal fields on training_plans (when plan_id supplied).
 *   - Upserts athlete_pace_profiles whenever goal_time_seconds +
 *     race_distance can be resolved. The full pace ladder is derived via
 *     `derivePaceTableFromGoal` so subscribe-to-plan's
 *     `paceTableFromProfile` resolves cleanly.
 *   - Invalidates athlete_state cache when a plan was updated. Next read
 *     rebuilds.
 *   - Does NOT silently re-resolve scheduled_workouts pace targets. The
 *     iOS prompts the athlete: "Recompute paces from this new goal?"
 *     and only re-resolves if they confirm.
 *   - Best-effort write-through to user_goals (race_name / end_date), so
 *     TrainingDateline and anything else reading the canonical goal record
 *     sees a goal set from here too, not only from GoalsView. See Mode C.
 *
 * Body shape:
 * {
 *   "plan_id"?: "uuid" | null,                    -- null = athlete-only goal save
 *   "target_race_distance"?: "5k" | "10k" | "half_marathon" | "marathon" | "general",
 *   "target_time_seconds"?: integer,              -- 0 to clear; null to leave alone
 *   "end_date"?: "YYYY-MM-DD" | null,             -- null to clear; absent to leave alone
 *   "race_name"?: string                          -- optional free text, e.g. "Chicago Marathon"
 * }
 */

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { getAuthenticatedUser, unauthorizedResponse } from "../_shared/auth.ts";
import {
  derivePaceTableFromGoal,
  RACE_DISTANCE_MI,
  raceKeyForInput,
} from "../_shared/paces.ts";

import { corsHeaders } from "../_shared/cors.ts";
interface UpdateBody {
  plan_id?: string | null;
  target_race_distance?: string;
  target_time_seconds?: number;
  end_date?: string | null;
  // Optional free-text race name (e.g. "Chicago Marathon"). Not stored on
  // training_plans or athlete_pace_profiles — it's goal context, so it only
  // ever reaches user_goals.goal_title. See Mode C below.
  race_name?: string;
}

const ALLOWED_DISTANCES = new Set([
  "5k", "10k", "half_marathon", "marathon", "ultra", "general",
]);

// Race distances that map to a real pace ladder. "ultra" and "general"
// have no canonical pace anchor, so they're stored on training_plans but
// don't write to athlete_pace_profiles.
const PACE_DERIVABLE_DISTANCES = new Set(["5k", "10k", "half_marathon", "marathon", "mile"]);

// Sanity bounds on goal time (10 minutes to 24 hours).
const MIN_TIME_SEC = 600;
const MAX_TIME_SEC = 86400;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return jsonError("Method not allowed", 405);
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const userId = await getAuthenticatedUser(req);
  if (!userId) return unauthorizedResponse(corsHeaders);
  // Compatibility shim — the function below expects a `user` object with `.id`
  // for tenant-scoping. Build a minimal one from the resolved JWT subject.
  const user = { id: userId };

  let body: UpdateBody;
  try {
    body = await req.json();
  } catch {
    return jsonError("Invalid JSON body", 400);
  }

  const planId = typeof body.plan_id === "string" && body.plan_id.length > 0
    ? body.plan_id
    : null;

  // ── Validate distance + time + end_date once for both modes ──
  if (body.target_race_distance !== undefined &&
      !ALLOWED_DISTANCES.has(body.target_race_distance)) {
    return jsonError(
      `target_race_distance must be one of ${[...ALLOWED_DISTANCES].join(", ")}`,
      400,
    );
  }
  if (body.target_time_seconds !== undefined) {
    const t = body.target_time_seconds;
    if (t !== 0 && (typeof t !== "number" || t < MIN_TIME_SEC || t > MAX_TIME_SEC)) {
      return jsonError(
        `target_time_seconds must be 0 (clear) or between ${MIN_TIME_SEC} and ${MAX_TIME_SEC}`,
        400,
      );
    }
  }
  if (body.end_date !== undefined && body.end_date !== null) {
    if (typeof body.end_date !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(body.end_date)) {
      return jsonError("end_date must be YYYY-MM-DD or null", 400);
    }
  }

  // ── Mode A: plan-scoped update ──────────────────────────────────────
  let planRow: Record<string, unknown> | null = null;
  let planPrev: Record<string, unknown> | null = null;
  if (planId) {
    const { data: plan, error: planErr } = await supabase
      .from("training_plans")
      .select("id, user_id, target_race_distance, target_time_seconds, end_date")
      .eq("id", planId)
      .eq("user_id", user.id)
      .maybeSingle();

    if (planErr || !plan) {
      return jsonError("Plan not found", 404);
    }
    planPrev = {
      target_race_distance: plan.target_race_distance,
      target_time_seconds: plan.target_time_seconds,
      end_date: plan.end_date,
    };

    const update: Record<string, unknown> = {};
    if (body.target_race_distance !== undefined) {
      update.target_race_distance = body.target_race_distance;
    }
    if (body.target_time_seconds !== undefined) {
      update.target_time_seconds = body.target_time_seconds === 0
        ? null
        : body.target_time_seconds;
    }
    if (body.end_date !== undefined) {
      update.end_date = body.end_date;
    }
    if (Object.keys(update).length === 0) {
      return jsonError("No fields to update", 400);
    }
    update.updated_at = new Date().toISOString();

    const { data: updated, error: updateErr } = await supabase
      .from("training_plans")
      .update(update)
      .eq("id", planId)
      .eq("user_id", user.id)
      .select()
      .single();

    if (updateErr) {
      return jsonError(`Update failed: ${updateErr.message}`, 500);
    }
    planRow = updated;

    // Invalidate the athlete state cache so the new goal flows through next
    // time getOrBuildAthleteState runs.
    await supabase
      .from("athlete_state")
      .update({
        last_updated_at: new Date(0).toISOString(),
        last_updated_by: "update-plan-goal",
      })
      .eq("user_id", user.id);
  } else if (
    body.target_race_distance === undefined &&
    body.target_time_seconds === undefined &&
    body.end_date === undefined
  ) {
    return jsonError("No fields to update", 400);
  }

  // ── Mode B: athlete-level goal mirror ───────────────────────────────
  // Resolve the effective race distance + goal time. When plan_id is set
  // we lean on the post-update training_plans row (or the prior values for
  // any field the body didn't change); when plan_id is null we rely on the
  // body alone.
  const effectiveDistance =
    (typeof body.target_race_distance === "string" ? body.target_race_distance : null) ??
    (planRow?.target_race_distance as string | null | undefined) ??
    null;
  const effectiveTimeSeconds = ((): number | null => {
    if (body.target_time_seconds !== undefined) {
      return body.target_time_seconds === 0 ? null : body.target_time_seconds;
    }
    const planTime = planRow?.target_time_seconds;
    return typeof planTime === "number" ? planTime : null;
  })();

  let paceProfileRow: Record<string, unknown> | null = null;
  if (
    effectiveDistance &&
    effectiveTimeSeconds &&
    PACE_DERIVABLE_DISTANCES.has(effectiveDistance)
  ) {
    const ladder = derivePaceLadderFromGoal(effectiveDistance, effectiveTimeSeconds);
    if (ladder) {
      // Rail 6 (GOAL-ELEMENT-APPLY.md §5): the goal never overwrites a
      // measured pace. Fetch whatever's on file first — if a zone already
      // carries a real confidence tier ('high'/'medium'/'low', meaning it
      // came from a fitness snapshot, not a prior goal save), that zone is
      // left out of this upsert entirely so the existing value survives.
      const existingProfileResult = await supabase
        .from("athlete_pace_profiles")
        .select(
          "easy_pace_confidence, marathon_pace_confidence, half_pace_confidence, " +
            "ten_k_pace_confidence, five_k_pace_confidence, mile_pace_confidence",
        )
        .eq("user_id", user.id)
        .maybeSingle();
      const existingProfile = existingProfileResult.data as Record<string, unknown> | null;

      const isMeasured = (confidence: unknown) =>
        confidence === "high" || confidence === "medium" || confidence === "low";

      const now = new Date().toISOString();
      const upsertRow: Record<string, unknown> = {
        user_id: user.id,
        goal_race_distance: effectiveDistance,
        goal_time_seconds: effectiveTimeSeconds,
        updated_at: now,
      };

      const zones: Array<{ key: string; seconds: number }> = [
        { key: "easy", seconds: ladder.easy },
        { key: "marathon", seconds: ladder.marathon },
        { key: "half", seconds: ladder.half },
        { key: "ten_k", seconds: ladder.tenK },
        { key: "five_k", seconds: ladder.fiveK },
        { key: "mile", seconds: ladder.mile },
      ];
      let anyZoneWritten = false;
      for (const zone of zones) {
        const existingConfidence = existingProfile?.[`${zone.key}_pace_confidence`];
        if (isMeasured(existingConfidence)) continue; // demoted — fitness wins
        anyZoneWritten = true;
        upsertRow[`${zone.key}_pace_seconds`] = round1(zone.seconds);
        // Confidence reflects that the ladder was derived from an athlete-
        // declared goal, not a measured race or fitness snapshot. Source
        // date pins the moment the athlete set/updated it.
        upsertRow[`${zone.key}_pace_confidence`] = "athlete_goal";
        upsertRow[`${zone.key}_pace_source_date`] = now;
      }

      const { data: profile, error: profileErr } = await supabase
        .from("athlete_pace_profiles")
        .upsert(upsertRow, { onConflict: "user_id" })
        .select()
        .single();
      if (profileErr) {
        // Non-fatal in the plan-scoped path (the plan write already landed);
        // fatal when there's no plan, otherwise the call had no effect.
        if (!planId) {
          return jsonError(`Failed to save athlete goal: ${profileErr.message}`, 500);
        }
        console.warn("athlete_pace_profiles upsert failed:", profileErr.message);
      } else {
        paceProfileRow = profile;
        if (!anyZoneWritten) {
          console.log(
            `update-plan-goal: all pace zones already measured for user ${user.id}; goal saved without touching the ladder`,
          );
        }
      }
    }
  } else if (!planId) {
    // plan_id null AND we couldn't derive paces → reject. Either the
    // distance is non-pace-derivable ("ultra"/"general") or one of
    // distance/time is missing.
    return jsonError(
      "plan_id is null but target_race_distance and target_time_seconds are required to save an athlete-level goal",
      400,
    );
  }

  // ── Mode C: write through to user_goals ─────────────────────────────
  // user_goals is the canonical goal record — it's what TrainingDateline
  // reads (GOAL-IA-APPLY.md §5). Without this, a goal set here (Train tab
  // / GoalAndPacesCard / onboarding) drives paces but never prints a
  // countdown anywhere in the app, because user_goals stays empty. Best-
  // effort: never fails the request, since the plan/pace writes above are
  // the ones this endpoint's callers actually depend on.
  if (effectiveDistance && effectiveTimeSeconds) {
    try {
      const targetDate = body.end_date ?? (planRow?.end_date as string | null | undefined) ?? null;
      const raceName = typeof body.race_name === "string" ? body.race_name.trim() : "";
      const { data: existingGoal } = await supabase
        .from("user_goals")
        .select("id")
        .eq("user_id", user.id)
        .eq("status", "active")
        .order("target_date", { ascending: true })
        .limit(1)
        .maybeSingle();

      if (existingGoal) {
        const updatePayload: Record<string, unknown> = {
          target_race_distance: effectiveDistance,
          target_time_seconds: effectiveTimeSeconds,
          athlete_confirmed: true,
          confirmed_at: new Date().toISOString(),
        };
        // Only touch goal_title when the athlete actually typed a race
        // name — an empty field must not blank out an existing one.
        if (raceName) updatePayload.goal_title = raceName;
        const { error: goalUpdateErr } = await supabase
          .from("user_goals")
          .update(updatePayload)
          .eq("id", existingGoal.id);
        if (goalUpdateErr) {
          console.warn("user_goals update failed:", goalUpdateErr.message);
        }
      } else if (targetDate) {
        // No active goal row to enrich — only safe to create one when we
        // have a date, since user_goals.target_date is NOT NULL.
        const { error: goalInsertErr } = await supabase.from("user_goals").insert({
          user_id: user.id,
          goal_title: raceName || describeGoal(effectiveDistance, effectiveTimeSeconds),
          target_date: targetDate,
          status: "active",
          target_race_distance: effectiveDistance,
          target_time_seconds: effectiveTimeSeconds,
          athlete_confirmed: true,
          confirmed_at: new Date().toISOString(),
        });
        if (goalInsertErr) {
          console.warn("user_goals insert failed:", goalInsertErr.message);
        }
      }
    } catch (err) {
      console.warn("user_goals write-through failed:", err);
    }
  }

  return new Response(
    JSON.stringify({
      ok: true,
      plan: planRow,
      previous: planPrev,
      pace_profile: paceProfileRow,
    }),
    {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    },
  );
});

// ── Helpers ─────────────────────────────────────────────────────────

interface PaceLadder {
  easy: number;
  marathon: number;
  half: number;
  tenK: number;
  fiveK: number;
  mile: number;
}

/** Derive the per-distance pace ladder from a single (distance, time)
 * anchor. Mirrors the math in subscribe-to-plan's resolveAthletePaces so
 * a goal saved here resolves identically when consumed downstream. */
function derivePaceLadderFromGoal(
  raceDistance: string,
  goalTimeSeconds: number,
): PaceLadder | null {
  const key = raceKeyForInput(raceDistance);
  const miles = RACE_DISTANCE_MI[key];
  if (!miles || miles <= 0) return null;
  const goalSecPerMile = goalTimeSeconds / miles;
  const table = derivePaceTableFromGoal(goalSecPerMile, raceDistance);
  return {
    easy:     table.easy,
    marathon: table.mp,
    half:     table.hm,
    tenK:     table.tenK,
    fiveK:    table.fiveK,
    mile:     table.mile,
  };
}

function round1(n: number): number {
  return Math.round(n * 10) / 10;
}

// A plain fallback title for a user_goals row created here (no natural-
// language statement available — that only exists via interpret-goal).
// e.g. "Marathon in 3:15:00".
function describeGoal(raceDistance: string, timeSeconds: number): string {
  const label = raceDistance
    .replace(/_/g, " ")
    .replace(/\b\w/g, (c) => c.toUpperCase());
  const h = Math.floor(timeSeconds / 3600);
  const m = Math.floor((timeSeconds % 3600) / 60);
  const s = timeSeconds % 60;
  const time = h > 0
    ? `${h}:${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}`
    : `${m}:${String(s).padStart(2, "0")}`;
  return `${label} in ${time}`;
}

function jsonError(message: string, status: number): Response {
  return new Response(
    JSON.stringify({ error: message }),
    {
      status,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    },
  );
}

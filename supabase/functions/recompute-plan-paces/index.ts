/**
 * Recompute pace targets on future scheduled_workouts using the plan's
 * current pace anchor and the athlete's pace profile.
 *
 * Athlete-initiated only — fired from the iOS soft-ask card after a goal
 * change. The AI never invokes this. See feedback memory
 * `feedback_ai_advises_never_acts.md`.
 *
 * Resolution precedence (matches subscribe-to-plan exactly):
 *   1. Coach's plan anchor on plan_templates.phase_config.paceAnchor
 *      (goal time + per-zone overrides)
 *   2. Athlete's pace profile (athlete_pace_profiles)
 *   3. Empty — leave step alone, iOS falls back at render time
 *
 * For every future scheduled_workout in the plan we walk workout_data.steps
 * and attach `target_pace` to each step (and to its nested recovery, when
 * present) based on the step's `paceZone`. Past workouts and any completed
 * rows are NOT touched.
 *
 * Body shape:
 *   { "plan_id": "uuid", "from_date"?: "YYYY-MM-DD" (default = today) }
 */

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { getAuthenticatedUser, unauthorizedResponse } from "../_shared/auth.ts";
import {
  applyPaceAdjustment,
  derivePaceTableFromGoal,
  paceTableFromProfile,
  RACE_DISTANCE_MI,
  raceKeyForInput,
  readPaceAdjustment,
  type PaceZone,
} from "../_shared/paces.ts";
import { getOrBuildPaceProfile, getConfirmedRaces } from "../_shared/resolve-pace.ts";
import { corsHeaders } from "../_shared/cors.ts";

interface ReqBody {
  plan_id?: string;
  from_date?: string;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return jsonError("Method not allowed", 405);

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const userId = await getAuthenticatedUser(req);
  if (!userId) return unauthorizedResponse(corsHeaders);

  let body: ReqBody;
  try {
    body = await req.json();
  } catch {
    return jsonError("Invalid JSON body", 400);
  }

  const planId = body.plan_id;
  if (!planId || typeof planId !== "string") {
    return jsonError("plan_id is required", 400);
  }

  // Tenant + plan lookup. Need the linked plan_template to read the coach's
  // pace anchor (the whole point of the recompute is to apply the new goal).
  const { data: plan, error: planErr } = await supabase
    .from("training_plans")
    .select("id, user_id, target_race_distance, target_time_seconds, plan_template_id")
    .eq("id", planId)
    .eq("user_id", userId)
    .maybeSingle();

  if (planErr || !plan) return jsonError("Plan not found", 404);

  // Resolve athlete paces with the same precedence as subscribe-to-plan:
  //   plan anchor → athlete profile → empty.
  // We pull a synthetic "template" from the linked plan_template (or, when
  // the plan was generated without one, fall back to the plan's own goal
  // time + race distance).
  let templatePhaseConfig: Record<string, unknown> | null = null;
  let templateTargetDistance: string | null = plan.target_race_distance;
  if (plan.plan_template_id) {
    const { data: tmpl } = await supabase
      .from("plan_templates")
      .select("phase_config, target_distance")
      .eq("id", plan.plan_template_id)
      .maybeSingle();
    if (tmpl) {
      templatePhaseConfig = tmpl.phase_config ?? null;
      templateTargetDistance = tmpl.target_distance ?? templateTargetDistance;
    }
  }

  // If no template anchor exists, synthesize one from the plan's own goal
  // — this handles the common case where the user just bumped their goal
  // time on a self-generated plan and wants the new MP/LT/etc. applied.
  let athletePaces = await resolveAthletePaces({
    supabase,
    userId,
    phaseConfig: templatePhaseConfig,
    fallbackGoalSec: plan.target_time_seconds,
    fallbackDistance: templateTargetDistance ?? "marathon",
  });

  if (Object.keys(athletePaces).length === 0) {
    return jsonError(
      "No pace profile found. Set a goal time or finish a few workouts so we can build one.",
      409,
    );
  }

  const fromDate = body.from_date && /^\d{4}-\d{2}-\d{2}$/.test(body.from_date)
    ? body.from_date
    : new Date().toISOString().slice(0, 10);

  // Pull every future workout for this plan that hasn't been completed.
  // Skipped or completed rows stay frozen — the user already ran what they ran.
  const { data: rows, error: rowsErr } = await supabase
    .from("scheduled_workouts")
    .select("id, workout_data, status")
    .eq("plan_id", planId)
    .gte("date", fromDate)
    .neq("status", "completed");

  if (rowsErr) return jsonError(`Failed to load workouts: ${rowsErr.message}`, 500);

  let updatedCount = 0;
  for (const row of rows ?? []) {
    const data = row.workout_data as Record<string, unknown> | null;
    if (!data) continue;
    const updated = personalizeWorkoutData(data, athletePaces);
    if (!updated) continue;
    const { error: updErr } = await supabase
      .from("scheduled_workouts")
      .update({ workout_data: updated })
      .eq("id", row.id);
    if (updErr) {
      console.warn(`Failed to update workout ${row.id}: ${updErr.message}`);
      continue;
    }
    updatedCount++;
  }

  return new Response(
    JSON.stringify({ ok: true, updated_count: updatedCount }),
    { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
  );
});

// ─── Helpers (mirror subscribe-to-plan) ────────────────────────────────

interface ResolveArgs {
  // deno-lint-ignore no-explicit-any
  supabase: any;
  userId: string;
  phaseConfig: Record<string, unknown> | null;
  fallbackGoalSec: number | null;
  fallbackDistance: string;
}

async function resolveAthletePaces(args: ResolveArgs): Promise<Record<string, number>> {
  // 1. Coach's plan anchor (preferred).
  const anchor = args.phaseConfig?.paceAnchor as
    | {
        goalRaceSeconds?: number | null;
        goalRaceDistance?: string | null;
        overrides?: Partial<Record<string, number>>;
      }
    | undefined;

  if (anchor?.goalRaceSeconds && anchor.goalRaceSeconds > 0) {
    const distance = anchor.goalRaceDistance ?? args.fallbackDistance ?? "marathon";
    const key = raceKeyForInput(distance);
    const miles = RACE_DISTANCE_MI[key];
    if (miles > 0) {
      const goalSecPerMile = anchor.goalRaceSeconds / miles;
      const base = derivePaceTableFromGoal(goalSecPerMile, distance) as Record<PaceZone, number>;
      if (anchor.overrides) {
        for (const [zone, sec] of Object.entries(anchor.overrides)) {
          if (typeof sec === "number" && sec > 0) {
            base[zone as PaceZone] = sec;
          }
        }
      }
      return base;
    }
  }

  // 2. Plan's own goal time (the field the EditGoal sheet just updated).
  if (args.fallbackGoalSec && args.fallbackGoalSec > 0) {
    const key = raceKeyForInput(args.fallbackDistance);
    const miles = RACE_DISTANCE_MI[key];
    if (miles > 0) {
      const goalSecPerMile = args.fallbackGoalSec / miles;
      return derivePaceTableFromGoal(goalSecPerMile, args.fallbackDistance) as Record<PaceZone, number>;
    }
  }

  // 3. Athlete's race anchor / saved pace profile. A confirmed race in
  //    athlete_state.confirmed_races outranks the profile inside
  //    paceTableFromProfile (Phase 2 sub-task C). It stays BELOW #2 on
  //    purpose: this function exists to recompute paces after the athlete
  //    explicitly edits the plan goal — the fresh goal edit must win here,
  //    or the EditGoal sheet would silently do nothing.
  const [profile, confirmedRaces] = await Promise.all([
    getOrBuildPaceProfile(args.supabase, args.userId),
    getConfirmedRaces(args.supabase, args.userId),
  ]);
  {
    const table = paceTableFromProfile(profile, confirmedRaces);
    if (table) return table;
  }

  return {};
}

// Walk a workout_data JSON, attach `target_pace` to each step and to its
// nested recovery, return a new object. Mirrors subscribe-to-plan exactly so
// the resulting JSON shape is identical (iOS doesn't have to special-case).
function personalizeWorkoutData(
  data: Record<string, unknown>,
  paces: Record<string, number>,
): Record<string, unknown> | null {
  const clone: Record<string, unknown> = { ...data };
  const rawSteps = Array.isArray(clone.steps) ? (clone.steps as Record<string, unknown>[]) : null;

  if (rawSteps) {
    const personalized: Record<string, unknown>[] = [];
    for (const step of rawSteps) {
      const out: Record<string, unknown> = attachPace(step, paces);
      const recovery = step.recovery && typeof step.recovery === "object"
        ? attachPace(step.recovery as Record<string, unknown>, paces)
        : null;
      if (recovery) out.recovery = recovery;
      personalized.push(out);
    }
    clone.steps = personalized.map((s, idx) => ({ ...s, order: idx }));
  }

  // Top-level zone (rare — used by stub easy/recovery workouts subscribe-to-plan
  // emits without a steps array).
  const topZone = typeof clone.paceZone === "string" ? clone.paceZone : null;
  if (topZone && typeof paces[topZone] === "number") {
    clone.target_pace = formatPace(paces[topZone]);
  }
  // Top-level easy stub: subscribe-to-plan writes `target_pace` from athletePaces.easy
  // for "Easy run" workouts. Refresh that too.
  if (!rawSteps && typeof paces.easy === "number") {
    clone.target_pace = formatPace(paces.easy);
  }
  clone.adapted = true;
  return clone;
}

// Map % of MP to the closest named zone — so legacy steps that only carried
// a pacePercentage (or a notes regex hint) can still ride iOS's range-based
// rendering for slow zones.
function inferZoneFromPercent(pct: number): string {
  if (pct >= 110)            return "fiveK";    // 110%+
  if (pct >= 105)            return "tenK";     // 105-109%
  if (pct >= 102)            return "threshold"; // 102-104%
  if (pct >= 99)             return "mp";       // 99-101%
  if (pct >= 92)             return "steady";   // 92-98%
  if (pct >= 87)             return "moderate"; // 87-91%
  if (pct >= 78)             return "longRun";  // 78-86%
  if (pct >= 70)             return "easy";     // 70-77%
  return "recovery";                            // <70%
}

function attachPace(
  step: Record<string, unknown>,
  paces: Record<string, number>,
): Record<string, unknown> {
  // Resolution order — sets BOTH `paceZone` and `target_pace`. iOS's
  // range-based render for slow zones (easy/longRun/moderate/steady/recovery)
  // depends on `paceZone` being present; without it the row falls through to
  // a single-pace display.
  //
  //   1. paceZone (web-authored)
  //   2. pacePercentage (deterministic builder — % of MP)
  //   3. legacy pace_reference (easy/marathon/half/10K/5K/mile)
  //   4. notes regex "@ NNN% MP"
  //   5. stepType defaults — warmup/cooldown → easy; recovery → recovery zone
  const mp = paces.mp;
  const out = { ...step };

  let resolvedZone: string | null = null;
  let resolved: number | null = null;

  // 1. paceZone
  const existingZone = typeof step.paceZone === "string" ? step.paceZone : null;
  if (existingZone && typeof paces[existingZone] === "number") {
    resolvedZone = existingZone;
    resolved = paces[existingZone];
  }

  // 2. pacePercentage (% of MP)
  if (resolved == null) {
    const pct = typeof step.pacePercentage === "number" ? step.pacePercentage : null;
    if (pct && pct > 0 && mp) {
      resolvedZone = inferZoneFromPercent(pct);
      resolved = mp * (100 / pct);
    }
  }

  // 3. pace_reference legacy
  if (resolved == null) {
    const ref = typeof step.pace_reference === "string" ? step.pace_reference.toLowerCase() : null;
    if (ref) {
      const map: Record<string, string> = {
        easy: "easy", marathon: "mp", half: "hm",
        "10k": "tenK", "5k": "fiveK", mile: "mile",
      };
      const zoneKey = map[ref];
      if (zoneKey && typeof paces[zoneKey] === "number") {
        resolvedZone = zoneKey;
        resolved = paces[zoneKey];
      }
    }
  }

  // 4. notes "@ NNN% MP"
  if (resolved == null && mp) {
    const notes = typeof step.notes === "string" ? step.notes : "";
    const m = /(\d{2,3})\s*%/.exec(notes);
    if (m) {
      const pct = parseInt(m[1], 10);
      if (pct >= 50 && pct <= 130) {
        resolvedZone = inferZoneFromPercent(pct);
        resolved = mp * (100 / pct);
      }
    }
  }

  // 5. stepType defaults
  if (resolved == null) {
    const type = typeof step.stepType === "string" ? step.stepType : "";
    if ((type === "warmup" || type === "cooldown") && typeof paces.easy === "number") {
      resolvedZone = "easy";
      resolved = paces.easy;
    } else if (type === "recovery" && mp) {
      // Float-style recovery between reps — coach standard is ~80% of MP,
      // which sits inside the "longRun" band on our ladder. Marking it as
      // longRun (range 75–85% MP speed) so iOS shows it as a range, not a
      // false single point.
      resolvedZone = "longRun";
      resolved = mp * (100 / 80);
    }
  }

  if (resolved != null) {
    // Apply per-step paceAdjustment ("MP −1%", "+10s/mi") on top of the base
    // zone pace so the displayed target_pace is the actual pace to run.
    const adjusted = applyPaceAdjustment(resolved, readPaceAdjustment(step.paceAdjustment));
    out.target_pace = formatPace(adjusted);
    out.target_pace_seconds_per_mile = Math.round(adjusted * 10) / 10;
    if (resolvedZone) {
      out.paceZone = resolvedZone;
    }
  } else {
    // No way to resolve — drop any stale stamp from the previous goal
    delete out.target_pace;
    delete out.target_pace_seconds_per_mile;
  }
  // Always strip the legacy resolver's stamps so they don't lie about provenance.
  delete out.pace_reference;
  delete out.resolved_at;
  delete out.resolved_from_snapshot_id;

  return out;
}

function formatPace(secondsPerMile: number): string {
  const total = Math.max(0, Math.round(secondsPerMile));
  const m = Math.floor(total / 60);
  const s = total % 60;
  return `${m}:${s.toString().padStart(2, "0")}`;
}

function jsonError(message: string, status: number): Response {
  return new Response(
    JSON.stringify({ error: message }),
    { status, headers: { ...corsHeaders, "Content-Type": "application/json" } },
  );
}

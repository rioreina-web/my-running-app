/**
 * subscribe-to-plan Edge Function
 *
 * Converts a plan template into a real training_plans + scheduled_workouts
 * record for an athlete. Called when:
 *   - An athlete enters a join code
 *   - A coach assigns a plan to an athlete
 *
 * Request body:
 *   {
 *     planTemplateId: string (UUID)
 *     athleteUserId: string
 *     startDate: string ("yyyy-MM-dd")
 *     goalTimeSeconds?: number    -- athlete's goal time, used for pace labels
 *     targetRaceDistance?: string -- overrides template default if provided
 *     subscription_preferences?: {       -- athlete onboarding overrides (AO-2)
 *       rest_dows?: number[],            -- 0=Mon..6=Sun; [] = no forced rest
 *       preferred_quality_dows?: number[],
 *       long_run_dow?: number | null,
 *       volume_ramp?: {
 *         start_mileage: number,
 *         ramp_to_coach_target: boolean,
 *         ramp_weeks: number
 *       } | null,
 *       shape_prefs?: {
 *         strides_pre_quality: boolean,
 *         recovery_after_long: boolean,
 *         doubles_on_easy_days: boolean
 *       } | null,
 *       current_weekly_mileage?: number | null
 *     }
 *
 * Response:
 *   { trainingPlanId, subscriptionId } | { error }
 *
 * Subscription preferences only meaningfully apply to adaptive plans.
 * Fixed plans materialize as the coach wrote them; the prefs row is still
 * persisted so the athlete's choices stay editable from the Plan tab.
 */

import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import { getAuthenticatedUser, unauthorizedResponse } from "../_shared/auth.ts";
import { getOrBuildAthleteState } from "../_shared/athlete-state.ts";
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

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// ── Plan materialization constants ──────────────────────────────────
// Strides are a once-a-week neuromuscular activation, attached to the
// easy day before a quality workout (tempo / intervals / race / progression).
// Long runs are NOT a valid strides trigger — strides prep speed, not endurance.
const STRIDES_PER_WEEK_CAP = 1;
// Auto-distributed easy days round to whole miles. A 1-mile easy run
// isn't really a workout; floor at 2.
const MIN_EASY_MILES = 2;
const KM_PER_MILE = 1.609344;

export interface Deps {
  createSupabaseClient: () => SupabaseClient;
  getAuthenticatedUser: (req: Request) => Promise<string | null>;
  getOrBuildAthleteState: (client: SupabaseClient, userId: string) => Promise<unknown>;
  // Pace resolution is injectable so tests can supply a fixed paces map
  // without standing up the full anchor → profile cascade.
  resolveAthletePaces: (
    client: SupabaseClient,
    athleteUserId: string,
    // deno-lint-ignore no-explicit-any
    template: any,
  ) => Promise<Record<string, number>>;
}

export const defaultDeps: Deps = {
  createSupabaseClient: () => createClient(supabaseUrl, serviceKey),
  getAuthenticatedUser,
  getOrBuildAthleteState,
  resolveAthletePaces,
};

export async function handler(req: Request, deps: Deps = defaultDeps): Promise<Response> {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // Authenticate the caller
    const callerUserId = await deps.getAuthenticatedUser(req);
    if (!callerUserId) {
      return unauthorizedResponse(corsHeaders);
    }

    const body = await req.json();
    const {
      planTemplateId,
      athleteUserId,
      startDate,
      goalTimeSeconds,
      targetRaceDistance,
    } = body;

    // Mode dispatch (AO-5). "create" = original flow. "rematerialize" =
    // rebuild future weeks of an existing subscription with new prefs;
    // past + completed/skipped workouts stay frozen.
    const mode = body.mode === "rematerialize" ? "rematerialize" : "create";

    if (mode === "rematerialize") {
      return await handleRematerialize(deps, body, callerUserId);
    }

    if (!planTemplateId || !athleteUserId || !startDate) {
      return errorResponse("Missing required fields: planTemplateId, athleteUserId, startDate");
    }

    // Athlete onboarding overrides (AO-2). Optional — when missing the
    // materializer reverts to coach defaults exactly as before.
    const subPrefs = readSubscriptionPreferences(body.subscription_preferences);

    // Verify the caller is either the athlete themselves or an authorized coach
    if (callerUserId !== athleteUserId) {
      // Check if caller is a coach with a relationship to this athlete.
      // coach_athlete_relationships.coach_id is a UUID FK to coach_profiles,
      // so we need to resolve the caller's user_id to their coach_profiles.id first.
      const authCheck = deps.createSupabaseClient();
      const { data: coachProfile } = await authCheck
        .from("coach_profiles")
        .select("id")
        .eq("user_id", callerUserId)
        .maybeSingle();

      let relationship = null;
      if (coachProfile) {
        const { data } = await authCheck
          .from("coach_athlete_relationships")
          .select("id")
          .eq("coach_id", coachProfile.id)
          .eq("athlete_user_id", athleteUserId)
          .eq("status", "active")
          .maybeSingle();
        relationship = data;
      }

      if (!relationship) {
        return errorResponse("Not authorized to assign plans to this athlete");
      }
    }

    const supabase = deps.createSupabaseClient();

    // 1. Fetch the plan template
    const { data: template, error: templateErr } = await supabase
      .from("plan_templates")
      .select("*")
      .eq("id", planTemplateId)
      .single();

    if (templateErr || !template) {
      return errorResponse("Plan template not found");
    }

    // 2. Check for existing subscription. ORPHAN HANDLING: if a subscription
    // exists but no matching training_plans row (rolled back from a prior failed
    // attempt), wipe the orphan and let this call rebuild fresh.
    const { data: existing } = await supabase
      .from("athlete_plan_subscriptions")
      .select("id, training_plan_id")
      .eq("plan_template_id", planTemplateId)
      .eq("athlete_user_id", athleteUserId)
      .maybeSingle();

    if (existing) {
      // If the linked training_plan still exists and is active, this is a real duplicate.
      const linkedPlanId = existing.training_plan_id as string | null;
      let isLiveDuplicate = false;
      if (linkedPlanId) {
        const { data: linkedPlan } = await supabase
          .from("training_plans")
          .select("id, status")
          .eq("id", linkedPlanId)
          .maybeSingle();
        if (linkedPlan && linkedPlan.status === "active") isLiveDuplicate = true;
      }
      if (isLiveDuplicate) {
        return errorResponse("You are already subscribed to this plan");
      }
      // Orphan — clean it up so we can rebuild
      console.log(`Cleaning up orphan subscription ${existing.id} before retry`);
      await supabase.from("athlete_plan_subscriptions").delete().eq("id", existing.id);
    }

    // 3. Determine plan metadata
    const raceDistance = targetRaceDistance ?? template.target_distance ?? "marathon";
    const durationWeeks: number = template.duration_weeks;
    const rawStart = new Date(startDate);

    // Snap the start to the Monday of its calendar week. Plan templates
    // store dayOfWeek as 0-indexed Mon-first (0=Mon..6=Sun); every workout
    // date is computed as `start + dayOffset`. Anchoring `start` to Monday
    // keeps weekdays aligned regardless of which day the athlete picked
    // as their subscription start. Without this, picking a Sunday shifts
    // every workout one day earlier (Tue→Mon, Sat→Fri).
    const startWeekday = rawStart.getDay(); // 0=Sun..6=Sat
    const daysBackToMonday = (startWeekday + 6) % 7; // Sun=6, Mon=0, ..., Sat=5
    const start = new Date(rawStart);
    start.setDate(start.getDate() - daysBackToMonday);

    // End date = start date + duration weeks - 1 day
    const end = new Date(start);
    end.setDate(end.getDate() + durationWeeks * 7 - 1);

    const planName = template.name;
    const planId = crypto.randomUUID();
    const isAdaptive = template.plan_type === "adaptive";

    // 4. Insert training_plan record for athlete
    const { error: planErr } = await supabase.from("training_plans").insert({
      id: planId,
      user_id: athleteUserId,
      name: planName,
      start_date: formatDate(start),
      end_date: formatDate(end),
      target_race_distance: raceDistance,
      target_time_seconds: goalTimeSeconds ?? defaultGoalTime(raceDistance),
      status: "active",
      coach_id: template.coach_id,
      plan_template_id: planTemplateId,
      source_type: "coach",
      plan_type: isAdaptive ? "adaptive" : "fixed",
    });

    if (planErr) {
      console.error("Plan insert error:", planErr);
      return errorResponse("Failed to create training plan: " + planErr.message);
    }

    // 5. Build and bulk-insert scheduled_workouts
    // For adaptive plans: fetch athlete state to personalize paces and fill easy days.
    // For fixed plans: materialize exactly as the coach wrote them.
    const weeks: PlanTemplateWeek[] = template.weeks ?? [];
    const workoutsToInsert: ScheduledWorkoutInsert[] = [];

    // Trigger athlete-state build/refresh as a side effect of subscribing.
    // We used to *also* read `athleteState.pace_zones` for personalization,
    // but that's source #3 in pace-system-rework.md and is deprecated —
    // it can drift from `athlete_pace_profiles` (the canonical source) and
    // it ignores the coach's plan anchor entirely. Resolution now goes
    // through resolveAthletePaces below instead.
    if (isAdaptive) {
      await deps.getOrBuildAthleteState(supabase, athleteUserId);
    }

    // Resolve paces with the proper precedence:
    //   1. Coach's plan anchor (template.phase_config.paceAnchor) — the
    //      whole reason the custom builder exists. A coach building a
    //      "2:25 marathon" plan with overrides expects those paces to
    //      reach the athlete.
    //   2. Athlete's own pace profile (athlete_pace_profiles).
    //   3. Empty — iOS falls back to its own resolution at render time.
    const athletePaces = await deps.resolveAthletePaces(supabase, athleteUserId, template);

    const easyDayPrefs = buildEasyDayPrefs(template, subPrefs);
    const ctx: MaterializeContext = {
      planId,
      planStart: start,
      isAdaptive,
      athletePaces,
      easyDayPrefs,
      subPrefs,
    };

    for (const week of weeks) {
      workoutsToInsert.push(...materializeWeek(week, ctx));
    }
    const qualityTemplatesToInsert = isAdaptive
      ? buildQualityTemplates(weeks, ctx)
      : [];

    // Batch insert in chunks of 100 to avoid payload limits
    const chunkSize = 100;
    for (let i = 0; i < workoutsToInsert.length; i += chunkSize) {
      const chunk = workoutsToInsert.slice(i, i + chunkSize);
      const { error: workoutErr } = await supabase
        .from("scheduled_workouts")
        .insert(chunk);

      if (workoutErr) {
        console.error("Workout insert error:", workoutErr);
        // Roll back: delete the training plan (workouts cascade on plan delete via FK)
        await supabase.from("training_plans").delete().eq("id", planId);
        return errorResponse("Failed to create scheduled workouts: " + workoutErr.message);
      }
    }

    // 5c. Insert quality_session_templates (adaptive plans)
    if (qualityTemplatesToInsert.length > 0) {
      const { error: qtErr } = await supabase
        .from("quality_session_templates")
        .insert(qualityTemplatesToInsert);
      if (qtErr) {
        console.warn("Quality template insert error (non-fatal):", qtErr);
      } else {
        console.log(`Inserted ${qualityTemplatesToInsert.length} quality session templates`);
      }
    }

    // 6. Create athlete_plan_subscription record. Persist any onboarding
    // overrides so the same sheet can reopen in edit mode (AO-5).
    const subscriptionId = crypto.randomUUID();
    const subscriptionRow: Record<string, unknown> = {
      id: subscriptionId,
      plan_template_id: planTemplateId,
      athlete_user_id: athleteUserId,
      training_plan_id: planId,
      start_date: startDate,
      status: "active",
    };
    if (subPrefs) {
      // rest_dows is NOT NULL with default `{}`; only override when supplied.
      if (subPrefs.restDows) subscriptionRow.rest_dows = subPrefs.restDows;
      if (subPrefs.preferredQualityDows) {
        subscriptionRow.preferred_quality_dows = subPrefs.preferredQualityDows;
      }
      if (subPrefs.longRunDow !== undefined) {
        subscriptionRow.long_run_dow = subPrefs.longRunDow;
      }
      if (subPrefs.volumeRamp) {
        subscriptionRow.volume_ramp = {
          start_mileage: subPrefs.volumeRamp.startMileage,
          ramp_to_coach_target: subPrefs.volumeRamp.rampToCoachTarget,
          ramp_weeks: subPrefs.volumeRamp.rampWeeks,
        };
      }
      if (subPrefs.shapePrefs) {
        subscriptionRow.shape_prefs = {
          strides_pre_quality: subPrefs.shapePrefs.stridesPreQuality,
          recovery_after_long: subPrefs.shapePrefs.recoveryAfterLong,
          doubles_on_easy_days: subPrefs.shapePrefs.doublesOnEasyDays,
        };
      }
      if (subPrefs.currentWeeklyMileage != null) {
        subscriptionRow.current_weekly_mileage = subPrefs.currentWeeklyMileage;
      }
    }
    const { error: subErr } = await supabase
      .from("athlete_plan_subscriptions")
      .insert(subscriptionRow);

    if (subErr) {
      console.error("Subscription insert error:", subErr);
      // Non-fatal: plan was already created, just log
    }

    // 7. Increment subscriber_count on the template
    await supabase.rpc("increment_subscriber_count", { template_id: planTemplateId }).maybeSingle();

    return new Response(
      JSON.stringify({ trainingPlanId: planId, subscriptionId }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200 }
    );
  } catch (err) {
    console.error("Unhandled error:", err);
    return errorResponse("Unexpected error: " + String(err));
  }
}

Deno.serve((req: Request) => handler(req));

// MARK: - Helpers

function errorResponse(message: string, status = 400): Response {
  return new Response(
    JSON.stringify({ error: message }),
    { headers: { ...corsHeaders, "Content-Type": "application/json" }, status }
  );
}

function formatDate(date: Date): string {
  return date.toISOString().split("T")[0];
}

function workoutMiles(tw: PlanTemplateWorkout): number {
  const data = tw.workoutData as Record<string, unknown> | null | undefined;
  if (!data) return 0;
  const km = typeof data.total_distance_km === "number" ? data.total_distance_km : 0;
  if (km > 0) return km / 1.60934;
  const mi = typeof data.total_distance_mi === "number" ? data.total_distance_mi : 0;
  return mi;
}

function formatPace(secondsPerMile: number): string {
  const total = Math.max(0, Math.round(secondsPerMile));
  const m = Math.floor(total / 60);
  const s = total % 60;
  return `${m}:${s.toString().padStart(2, "0")}`;
}

/**
 * Replace pace placeholders in workout step data with athlete-specific paces.
 * Looks for a `paceZone` field (e.g., "easy", "mp", "threshold") on each step and
 * fills in `target_pace` from the athlete's pace_zones map. Leaves data untouched
 * when no athlete paces available.
 */
function personalizeWorkoutData(
  data: Record<string, unknown> | null | undefined,
  paces: Record<string, number>
): Record<string, unknown> | null {
  if (!data) return null;

  const clone: Record<string, unknown> = { ...data };
  const rawSteps = Array.isArray(clone.steps) ? (clone.steps as Record<string, unknown>[]) : null;

  if (rawSteps) {
    // Preserve the compact `{ repeats, recovery }` shape end-to-end. iOS
    // renders a single `× N` row per interval set with the recovery nested
    // underneath — the way the coach authored it.
    //
    // Earlier versions flattened "10 × 1km" into 10 separate active steps +
    // 9 recovery steps, but the flattened copies all shared the same `id`,
    // causing SwiftUI's ForEach (keyed by id) to dedupe down to a single
    // row. We now pass through the structure and let the renderer expand it
    // visually — single source of truth, no ID collisions.
    //
    // We still attach a resolved `target_pace` to each step (and to the
    // nested recovery when present) so iOS doesn't have to look up paces
    // per render.
    const personalized: Record<string, unknown>[] = [];
    for (const step of rawSteps) {
      const out: Record<string, unknown> = attachPace(step, paces);
      const recovery = step.recovery && typeof step.recovery === "object"
        ? attachPace(step.recovery as Record<string, unknown>, paces)
        : null;
      if (recovery) {
        out.recovery = recovery;
      }
      personalized.push(out);
    }
    // Re-number order so downstream code that relies on `order` stays consistent.
    clone.steps = personalized.map((s, idx) => ({ ...s, order: idx }));
  }

  const topZone = typeof clone.paceZone === "string" ? clone.paceZone : null;
  if (topZone && typeof paces[topZone] === "number" && !clone.target_pace) {
    clone.target_pace = formatPace(paces[topZone]);
  }
  clone.adapted = true;
  return clone;
}

// Attach a resolved target_pace (M:SS/mi string) to a step based on its
// paceZone, applying any per-step paceAdjustment ("MP −1%", "+10s/mi", etc.)
// on top of the base zone pace. When the athlete has no pace for that zone,
// the step is returned unchanged and iOS falls back to its own pace resolution.
function attachPace(
  step: Record<string, unknown>,
  paces: Record<string, number>,
): Record<string, unknown> {
  if (!paces || Object.keys(paces).length === 0) return step;
  const zone = typeof step.paceZone === "string" ? step.paceZone : null;
  if (zone && typeof paces[zone] === "number") {
    const adjusted = applyPaceAdjustment(paces[zone], readPaceAdjustment(step.paceAdjustment));
    return { ...step, target_pace: formatPace(adjusted) };
  }
  return step;
}

// Resolve the pace table for this subscription with the correct precedence:
//   coach's plan anchor → athlete's pace profile → empty.
//
// Mirrors web's resolvePaceTable (pace-reference-editor.tsx) so the editor
// the coach saw and the scheduled_workouts the athlete gets agree.
//
// Anchor shape (stored on plan_templates.phase_config.paceAnchor):
//   { goalRaceSeconds, goalRaceDistance, overrides: { [zone]: secPerMile } }
//
// Returns an empty record when nothing resolves — iOS falls back to its
// own resolution at render time and the caller's `attachPace` is a no-op.
async function resolveAthletePaces(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  athleteUserId: string,
  // deno-lint-ignore no-explicit-any
  template: any,
): Promise<Record<string, number>> {
  // 1. Coach's anchor wins. The whole point of the custom plan builder is
  //    that the coach prescribes paces for this plan; ignoring them silently
  //    is the bug we're fixing here.
  const anchor = template.phase_config?.paceAnchor as
    | {
        goalRaceSeconds?: number | null;
        goalRaceDistance?: string | null;
        overrides?: Partial<Record<string, number>>;
      }
    | undefined;

  if (anchor?.goalRaceSeconds && anchor.goalRaceSeconds > 0) {
    const distance = anchor.goalRaceDistance ?? template.target_distance ?? "marathon";
    const key = raceKeyForInput(distance);
    const miles = RACE_DISTANCE_MI[key];
    if (miles > 0) {
      const goalSecPerMile = anchor.goalRaceSeconds / miles;
      const base = derivePaceTableFromGoal(goalSecPerMile, distance) as Record<PaceZone, number>;
      // Per-zone overrides — coach can override individual zones (e.g. "this
      // athlete's tempo runs slower than the ladder predicts"). Applied on
      // top of the goal-derived table so most zones still snap to the goal.
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

  // 2. Athlete's race anchor / pace profile. A confirmed race in
  //    athlete_state.confirmed_races outranks the profile inside
  //    paceTableFromProfile (real fitness > derived/aspirational paces —
  //    Phase 2 sub-task C, Q20 roadmap decision). It deliberately does NOT
  //    outrank #1: a coach's explicit plan anchor is a human decision and
  //    the coach owns it. Works even when the profile is null but a race
  //    exists.
  const [profile, confirmedRaces] = await Promise.all([
    getOrBuildPaceProfile(supabase, athleteUserId),
    getConfirmedRaces(supabase, athleteUserId),
  ]);
  {
    const table = paceTableFromProfile(profile, confirmedRaces);
    if (table) return table;
  }

  // 3. Nothing to anchor on. Steps with `paceZone` keep their named zone;
  //    iOS resolves at render time using its own pace profile.
  return {};
}

// ── Subscription preferences (AO-2) ───────────────────────────────────

interface VolumeRampPref {
  startMileage: number;
  rampToCoachTarget: boolean;
  rampWeeks: number;
}

interface ShapePrefsPref {
  stridesPreQuality: boolean;
  recoveryAfterLong: boolean;
  doublesOnEasyDays: boolean;
}

interface SubscriptionPreferences {
  restDows?: number[];
  preferredQualityDows?: number[];
  longRunDow?: number | null;
  volumeRamp?: VolumeRampPref | null;
  shapePrefs?: ShapePrefsPref | null;
  currentWeeklyMileage?: number | null;
}

/** Defensive parse of the snake_case JSON the iOS sheet posts. Anything
 * malformed is dropped silently — onboarding overrides are best-effort,
 * never required. Returns null when the field is absent so callers can
 * branch on `subPrefs ? ... : ...` without optional-chaining everywhere. */
function readSubscriptionPreferences(raw: unknown): SubscriptionPreferences | null {
  if (!raw || typeof raw !== "object") return null;
  const r = raw as Record<string, unknown>;
  const out: SubscriptionPreferences = {};

  if (Array.isArray(r.rest_dows)) {
    out.restDows = r.rest_dows.filter((x): x is number =>
      typeof x === "number" && x >= 0 && x <= 6);
  }
  if (Array.isArray(r.preferred_quality_dows)) {
    out.preferredQualityDows = r.preferred_quality_dows.filter((x): x is number =>
      typeof x === "number" && x >= 0 && x <= 6);
  }
  if (typeof r.long_run_dow === "number" && r.long_run_dow >= 0 && r.long_run_dow <= 6) {
    out.longRunDow = r.long_run_dow;
  } else if (r.long_run_dow === null) {
    out.longRunDow = null;
  }
  if (r.volume_ramp && typeof r.volume_ramp === "object") {
    const vr = r.volume_ramp as Record<string, unknown>;
    if (typeof vr.start_mileage === "number" &&
        typeof vr.ramp_to_coach_target === "boolean" &&
        typeof vr.ramp_weeks === "number") {
      out.volumeRamp = {
        startMileage: vr.start_mileage,
        rampToCoachTarget: vr.ramp_to_coach_target,
        rampWeeks: Math.max(1, Math.round(vr.ramp_weeks)),
      };
    }
  }
  if (r.shape_prefs && typeof r.shape_prefs === "object") {
    const sp = r.shape_prefs as Record<string, unknown>;
    out.shapePrefs = {
      stridesPreQuality: sp.strides_pre_quality === true,
      recoveryAfterLong: sp.recovery_after_long === true,
      doublesOnEasyDays: sp.doubles_on_easy_days === true,
    };
  }
  if (typeof r.current_weekly_mileage === "number") {
    out.currentWeeklyMileage = r.current_weekly_mileage;
  }
  return out;
}

/** Linear ramp from start_mileage at week 1 to the per-week coach target
 * across `ramp_weeks`. After ramp_weeks, the coach target stands as written.
 * When ramp_to_coach_target is false the athlete stays flat at start_mileage
 * the entire time. */
function rampedMileage(
  weekNumber: number,
  coachTarget: number,
  ramp: VolumeRampPref,
): number {
  if (weekNumber > ramp.rampWeeks) return coachTarget;
  if (!ramp.rampToCoachTarget) return ramp.startMileage;
  if (ramp.rampWeeks <= 1) return coachTarget;
  const progress = (weekNumber - 1) / (ramp.rampWeeks - 1);
  return ramp.startMileage + progress * (coachTarget - ramp.startMileage);
}

/** Decide which dow each quality workout lands on, applying athlete
 * preferences when provided.
 *
 * Without overrides: the coach's template placement wins exactly.
 * With preferred_quality_dows: the coach's quality workouts (long run +
 *   the rest) get redistributed across the athlete's chosen dows in order.
 * With long_run_dow: the long run is forced onto that dow, regardless of
 *   what the athlete picked for quality_dows (it's effectively an
 *   additional quality slot).
 *
 * If the athlete picks fewer dows than the template has quality, the
 * extras drop — that's the athlete saying "I can't fit them all this
 * week" and the materializer respects that.
 */
function assignQualityDays(
  allQuality: PlanTemplateWorkout[],
  longRunWorkout: PlanTemplateWorkout | undefined,
  preferredQualityDows: number[] | null,
  longRunDow: number | null,
): Map<number, PlanTemplateWorkout> {
  const result = new Map<number, PlanTemplateWorkout>();

  // No athlete override → keep the coach's placement, apply only
  // long_run_dow swap when set.
  if (!preferredQualityDows) {
    for (const tw of allQuality) result.set(tw.dayOfWeek ?? 0, tw);
    if (longRunDow != null && longRunWorkout) {
      const currentDow = longRunWorkout.dayOfWeek ?? 0;
      if (currentDow !== longRunDow) {
        const occupant = result.get(longRunDow);
        result.delete(currentDow);
        result.set(longRunDow, longRunWorkout);
        if (occupant) result.set(currentDow, occupant);
      }
    }
    return result;
  }

  const sortedDows = [...new Set(preferredQualityDows)].sort((a, b) => a - b);
  const others = allQuality.filter((tw) => tw !== longRunWorkout);

  // Place long run first (athlete's pick wins; default to last athlete dow)
  let longRunSlot: number | null = null;
  if (longRunWorkout) {
    if (longRunDow != null) {
      longRunSlot = longRunDow;
    } else if (sortedDows.length > 0) {
      longRunSlot = sortedDows[sortedDows.length - 1];
    }
    if (longRunSlot != null) result.set(longRunSlot, longRunWorkout);
  }

  // Place remaining quality on the rest of the athlete's chosen dows in order
  let i = 0;
  for (const dow of sortedDows) {
    if (dow === longRunSlot) continue;
    if (i >= others.length) break;
    result.set(dow, others[i]);
    i++;
  }
  return result;
}

function defaultGoalTime(raceDistance: string): number {
  // Reasonable defaults for plan creation when athlete hasn't set a goal time
  switch (raceDistance) {
    case "marathon": return 4 * 3600;         // 4:00:00
    case "half_marathon": return 2 * 3600;    // 2:00:00
    case "10k": return 60 * 60;               // 1:00:00
    case "5k": return 30 * 60;               // 0:30:00
    default: return 4 * 3600;
  }
}

// ── Rematerialize: rebuild future scheduled_workouts with new prefs ──

/** AO-5 entry point. Reuses the same materialization helpers as the create
 * path so the athlete's edit preview matches what gets written to the DB.
 *
 * Flow:
 *   1. Find existing live subscription + linked training_plan.
 *   2. Compute cutover Monday (this week, bumped to next Monday if any
 *      workout this week has been completed/skipped — never disturb the
 *      athlete's recorded history).
 *   3. Convert cutover Monday to a week_number using training_plans.start_date.
 *   4. DELETE scheduled_workouts WHERE plan_id = ... AND date >= cutover
 *      AND status = 'scheduled'. Completed/skipped rows are preserved.
 *   5. Re-run the materializer for weeks >= cutoverWeek with the new prefs.
 *   6. Persist new prefs to athlete_plan_subscriptions.
 *   7. Return the cutover info so iOS can refresh its calendar from there. */
async function handleRematerialize(
  deps: Deps,
  // deno-lint-ignore no-explicit-any
  body: any,
  callerUserId: string,
): Promise<Response> {
  const { planTemplateId, athleteUserId } = body;
  if (!planTemplateId || !athleteUserId) {
    return errorResponse("Missing required fields: planTemplateId, athleteUserId");
  }
  // Athlete edits their own subscription only. Coach-driven rematerialize
  // would need a separate path; out of scope for AO-5.
  if (callerUserId !== athleteUserId) {
    return errorResponse("Not authorized to rematerialize this subscription", 403);
  }

  const subPrefs = readSubscriptionPreferences(body.subscription_preferences);

  const supabase = deps.createSupabaseClient();

  // 1. Find subscription + linked plan.
  const { data: subscription } = await supabase
    .from("athlete_plan_subscriptions")
    .select("id, training_plan_id")
    .eq("plan_template_id", planTemplateId)
    .eq("athlete_user_id", athleteUserId)
    .eq("status", "active")
    .maybeSingle();

  if (!subscription || !subscription.training_plan_id) {
    return errorResponse("No active subscription found to rematerialize", 404);
  }
  const trainingPlanId = subscription.training_plan_id as string;

  const { data: plan, error: planErr } = await supabase
    .from("training_plans")
    .select("id, start_date, status, plan_type, target_race_distance, target_time_seconds")
    .eq("id", trainingPlanId)
    .eq("user_id", athleteUserId)
    .maybeSingle();
  if (planErr || !plan) {
    return errorResponse("Linked training plan not found", 404);
  }

  const { data: template, error: templateErr } = await supabase
    .from("plan_templates")
    .select("*")
    .eq("id", planTemplateId)
    .single();
  if (templateErr || !template) {
    return errorResponse("Plan template not found", 404);
  }

  // 2. Cutover Monday — start of THIS calendar week, in plan-local time.
  const today = new Date();
  const todayDow = today.getDay();
  const daysBackToMonday = (todayDow + 6) % 7;
  let cutover = new Date(today);
  cutover.setUTCDate(today.getUTCDate() - daysBackToMonday);
  cutover = new Date(formatDate(cutover) + "T00:00:00Z");

  // If the athlete already completed or skipped anything this week, bump to
  // next Monday — rebuilding around recorded history would lose data.
  const cutoverEnd = new Date(cutover);
  cutoverEnd.setUTCDate(cutover.getUTCDate() + 7);
  const { data: thisWeekTouched } = await supabase
    .from("scheduled_workouts")
    .select("id")
    .eq("plan_id", trainingPlanId)
    .gte("date", formatDate(cutover))
    .lt("date", formatDate(cutoverEnd))
    .neq("status", "scheduled")
    .limit(1);
  let bumpedForCompleted = false;
  if (thisWeekTouched && thisWeekTouched.length > 0) {
    cutover.setUTCDate(cutover.getUTCDate() + 7);
    bumpedForCompleted = true;
  }

  // 3. Cutover week number — relative to plan.start_date (Monday-anchored).
  const planStart = new Date(formatDate(new Date(plan.start_date)) + "T00:00:00Z");
  const daysSinceStart = Math.round(
    (cutover.getTime() - planStart.getTime()) / 86400000
  );
  const cutoverWeekNumber = Math.floor(daysSinceStart / 7) + 1;

  // 4. Drop future scheduled rows. Completed/skipped stay frozen.
  const { error: deleteErr } = await supabase
    .from("scheduled_workouts")
    .delete()
    .eq("plan_id", trainingPlanId)
    .gte("date", formatDate(cutover))
    .eq("status", "scheduled");
  if (deleteErr) {
    return errorResponse(`Failed to clear future workouts: ${deleteErr.message}`, 500);
  }

  // 5. Re-materialize weeks >= cutoverWeekNumber.
  // Resolve athlete paces against the (possibly new) goal anchor — same
  // precedence as the create path.
  const isAdaptive = plan.plan_type === "adaptive";
  if (isAdaptive) {
    await deps.getOrBuildAthleteState(supabase, athleteUserId);
  }
  const athletePaces = await deps.resolveAthletePaces(supabase, athleteUserId, template);
  const easyDayPrefs = buildEasyDayPrefs(template, subPrefs);
  const ctx: MaterializeContext = {
    planId: trainingPlanId,
    planStart,
    isAdaptive,
    athletePaces,
    easyDayPrefs,
    subPrefs,
  };

  const allWeeks: PlanTemplateWeek[] = template.weeks ?? [];
  const remainingWeeks = allWeeks.filter((w) => w.weekNumber >= cutoverWeekNumber);
  const workoutsToInsert: ScheduledWorkoutInsert[] = [];
  for (const week of remainingWeeks) {
    workoutsToInsert.push(...materializeWeek(week, ctx));
  }

  const chunkSize = 100;
  for (let i = 0; i < workoutsToInsert.length; i += chunkSize) {
    const chunk = workoutsToInsert.slice(i, i + chunkSize);
    const { error: insertErr } = await supabase.from("scheduled_workouts").insert(chunk);
    if (insertErr) {
      // Don't roll back the existing plan; just bubble up. The athlete is
      // mid-edit and would rather see the error than have the calendar
      // wiped clean.
      return errorResponse(`Failed to write rematerialized workouts: ${insertErr.message}`, 500);
    }
  }

  // 6. Persist new prefs onto the subscription row.
  const update: Record<string, unknown> = {};
  if (subPrefs) {
    if (subPrefs.restDows) update.rest_dows = subPrefs.restDows;
    if (subPrefs.preferredQualityDows) update.preferred_quality_dows = subPrefs.preferredQualityDows;
    if (subPrefs.longRunDow !== undefined) update.long_run_dow = subPrefs.longRunDow;
    if (subPrefs.volumeRamp) {
      update.volume_ramp = {
        start_mileage: subPrefs.volumeRamp.startMileage,
        ramp_to_coach_target: subPrefs.volumeRamp.rampToCoachTarget,
        ramp_weeks: subPrefs.volumeRamp.rampWeeks,
      };
    }
    if (subPrefs.shapePrefs) {
      update.shape_prefs = {
        strides_pre_quality: subPrefs.shapePrefs.stridesPreQuality,
        recovery_after_long: subPrefs.shapePrefs.recoveryAfterLong,
        doubles_on_easy_days: subPrefs.shapePrefs.doublesOnEasyDays,
      };
    }
    if (subPrefs.currentWeeklyMileage != null) {
      update.current_weekly_mileage = subPrefs.currentWeeklyMileage;
    }
  }
  if (Object.keys(update).length > 0) {
    const { error: updErr } = await supabase
      .from("athlete_plan_subscriptions")
      .update(update)
      .eq("id", subscription.id);
    if (updErr) {
      // Workouts already landed; subscription pref drift is non-fatal.
      console.warn("rematerialize: subscription update failed:", updErr.message);
    }
  }

  return new Response(
    JSON.stringify({
      ok: true,
      mode: "rematerialize",
      training_plan_id: trainingPlanId,
      cutover_date: formatDate(cutover),
      cutover_week_number: cutoverWeekNumber,
      bumped_for_completed: bumpedForCompleted,
      weeks_rebuilt: remainingWeeks.length,
      workouts_inserted: workoutsToInsert.length,
    }),
    { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200 }
  );
}

// ── Materialization context + helpers ───────────────────────────────

interface EasyDayPrefs {
  autoStrides: boolean;
  recoveryAfterLong: boolean;
  restDayOfWeek: number | null;
}

interface MaterializeContext {
  planId: string;
  planStart: Date;
  isAdaptive: boolean;
  athletePaces: Record<string, number>;
  easyDayPrefs: EasyDayPrefs;
  subPrefs: SubscriptionPreferences | null;
}

// deno-lint-ignore no-explicit-any
function buildEasyDayPrefs(template: any, subPrefs: SubscriptionPreferences | null): EasyDayPrefs {
  // Coach toggles drift to athlete-supplied shape_prefs when present, with
  // hardcoded defaults filling any remaining gap. rest_day_of_week is opt-in
  // — null/undefined means "no forced rest" (older code defaulted to Friday
  // and surprised coaches whose plans came back with an unwanted rest).
  if (subPrefs?.shapePrefs?.doublesOnEasyDays) {
    console.log("subscription_preferences.shape_prefs.doubles_on_easy_days = true (not yet implemented)");
  }
  return {
    autoStrides: subPrefs?.shapePrefs?.stridesPreQuality
      ?? template.auto_strides_on_pre_quality ?? true,
    recoveryAfterLong: subPrefs?.shapePrefs?.recoveryAfterLong
      ?? template.recovery_after_long_run ?? true,
    restDayOfWeek: typeof template.rest_day_of_week === "number"
      ? template.rest_day_of_week
      : null,
  };
}

/** Build the scheduled_workouts inserts for one week. Branches on plan_type:
 * fixed plans forward each day as written; adaptive plans go through the
 * full pipeline (quality placement → rest days → easy fill → shape). */
function materializeWeek(week: PlanTemplateWeek, ctx: MaterializeContext): ScheduledWorkoutInsert[] {
  const weekStartOffset = (week.weekNumber - 1) * 7;
  const out: ScheduledWorkoutInsert[] = [];

  if (!ctx.isAdaptive) {
    // ── Fixed plan: forward workouts as written, just resolve paces ──
    const weekDows = (week.workouts ?? []).map((w) => w.dayOfWeek ?? 0);
    const looksOneIndexed = weekDows.some((d) => d >= 7);
    for (const dayWorkout of week.workouts ?? []) {
      const dayOffset = weekStartOffset + (dayWorkout.dayOfWeek ?? 0);
      const workoutDate = new Date(ctx.planStart);
      workoutDate.setDate(workoutDate.getDate() + dayOffset);
      const workoutType = dayWorkout.workoutType ?? "rest";
      const workoutData = workoutType !== "rest" ? (dayWorkout.workoutData ?? null) : null;

      const rawDow = dayWorkout.dayOfWeek ?? 0;
      const candidate = looksOneIndexed ? rawDow : rawDow + 1;
      const normalizedDow = Math.min(7, Math.max(1, candidate));
      const isQuality = ["tempo", "intervals", "long_run", "race", "progression"].includes(workoutType);
      out.push({
        plan_id: ctx.planId,
        date: formatDate(workoutDate),
        day_of_week: normalizedDow,
        week_number: week.weekNumber,
        session: 1,
        workout_type: workoutType,
        workout_data: workoutData,
        status: "scheduled",
        notes: dayWorkout.notes ?? null,
        source: isQuality ? "coach_locked" : "easy_fill",
        is_movable: false,
      });
    }
    return out;
  }

  // ── Adaptive plan: place quality, pick rest, fill easy, add shape ──
  const templateWorkouts = week.workouts ?? [];
  const targetMin = week.targetMilesMin ?? 0;
  const targetMax = week.targetMilesMax ?? 0;
  const coachTargetMileage = targetMax > 0 ? (targetMin + targetMax) / 2 : 0;
  const targetMileage = ctx.subPrefs?.volumeRamp
    ? rampedMileage(week.weekNumber, coachTargetMileage, ctx.subPrefs.volumeRamp)
    : coachTargetMileage;

  const allQuality: PlanTemplateWorkout[] = [];
  const templateExplicitRestDows = new Set<number>();
  for (const tw of templateWorkouts) {
    const dow = tw.dayOfWeek ?? 0;
    const type = tw.workoutType;
    if (!type || type === "rest") {
      if (type === "rest") templateExplicitRestDows.add(dow);
      continue;
    }
    allQuality.push(tw);
  }
  let longRunWorkout: PlanTemplateWorkout | undefined;
  {
    let max = 0;
    for (const tw of allQuality) {
      const miles = workoutMiles(tw);
      if (miles > max) { max = miles; longRunWorkout = tw; }
    }
  }

  const qualityDaysByDow = assignQualityDays(
    allQuality,
    longRunWorkout,
    ctx.subPrefs?.preferredQualityDows ?? null,
    ctx.subPrefs?.longRunDow ?? null,
  );

  const qualityMiles = Array.from(qualityDaysByDow.values())
    .reduce((sum, tw) => sum + workoutMiles(tw), 0);

  const explicitRestDows = new Set<number>();
  if (ctx.subPrefs?.restDows) {
    for (const dow of ctx.subPrefs.restDows) explicitRestDows.add(dow);
  } else {
    for (const dow of templateExplicitRestDows) explicitRestDows.add(dow);
    if (explicitRestDows.size === 0 && ctx.easyDayPrefs.restDayOfWeek !== null) {
      explicitRestDows.add(ctx.easyDayPrefs.restDayOfWeek);
    }
  }

  let longRunDow: number | null = null;
  let longRunMiles = 0;
  for (const [dow, tw] of qualityDaysByDow) {
    const miles = workoutMiles(tw);
    if (miles > longRunMiles) { longRunMiles = miles; longRunDow = dow; }
  }

  const easyDows: number[] = [];
  for (let dow = 0; dow < 7; dow++) {
    if (qualityDaysByDow.has(dow)) continue;
    if (explicitRestDows.has(dow)) continue;
    easyDows.push(dow);
  }

  const easyMilesToDistribute = Math.max(0, targetMileage - qualityMiles);

  // Score each easy day by what's next on the calendar.
  // Long runs are explicitly excluded — strides prep speed, not endurance.
  const stridesPriority = (nextDow: number): number => {
    const tw = qualityDaysByDow.get(nextDow);
    if (!tw || nextDow === longRunDow) return 0;
    switch (tw.workoutType) {
      case "tempo":
      case "threshold":   return 3;
      case "intervals":
      case "race":        return 2;
      case "progression": return 1;
      default:            return 0;
    }
  };

  // Compute next-day-is-quality once, reuse for both strides + weight.
  const easyDayMeta = easyDows.map((dow) => {
    const nextDow = (dow + 1) % 7;
    const isPreQuality = qualityDaysByDow.has(nextDow);
    const isPostLong = longRunDow != null && dow === (longRunDow + 1) % 7;
    const stridesScore = ctx.easyDayPrefs.autoStrides ? stridesPriority(nextDow) : 0;
    const weight = (isPreQuality ? 0.7 : 1.0) *
                   (isPostLong && ctx.easyDayPrefs.recoveryAfterLong ? 0.6 : 1.0);
    return { dow, isPreQuality, isPostLong, stridesScore, weight };
  });

  const stridesDows = new Set(
    easyDayMeta
      .filter((m) => m.stridesScore > 0)
      .sort((a, b) => b.stridesScore - a.stridesScore)
      .slice(0, STRIDES_PER_WEEK_CAP)
      .map((m) => m.dow),
  );

  const totalWeight = easyDayMeta.reduce((s, m) => s + m.weight, 0) || 1;

  // Per-day allocation: whole miles, with a sane floor — EXCEPT when there
  // is nothing to distribute. When the week's mileage target (e.g. a
  // volume_ramp start_mileage below the template's quality miles) is already
  // consumed by quality, flooring every easy day at MIN_EASY_MILES would
  // silently blow past the athlete's requested volume (5 days × 2 mi = +10
  // mi on someone who asked to start at 12 mpw). Zero budget → easy days
  // become rest days instead. Follow-up (not handled here): a small-but-
  // nonzero budget still floors each day and can overshoot; scaling quality
  // down to the ramp is a coach-side design call.
  const milesForDow = (dow: number): number => {
    if (easyMilesToDistribute <= 0) return 0;
    const m = easyDayMeta.find((x) => x.dow === dow);
    if (!m) return MIN_EASY_MILES;
    return Math.max(MIN_EASY_MILES, Math.round(easyMilesToDistribute * m.weight / totalWeight));
  };

  for (let dow = 0; dow < 7; dow++) {
    const dayOffset = weekStartOffset + dow;
    const workoutDate = new Date(ctx.planStart);
    workoutDate.setDate(workoutDate.getDate() + dayOffset);

    let workoutType: string;
    let workoutData: Record<string, unknown> | null = null;
    let notes: string | null = null;

    if (explicitRestDows.has(dow)) {
      workoutType = "rest";
    } else if (qualityDaysByDow.has(dow)) {
      const tw = qualityDaysByDow.get(dow)!;
      workoutType = tw.workoutType ?? "easy";
      workoutData = personalizeWorkoutData(tw.workoutData, ctx.athletePaces);
      notes = tw.notes ?? null;
    } else {
      const miles = milesForDow(dow);
      const isPostLong = longRunDow != null && dow === (longRunDow + 1) % 7;

      if (miles === 0) {
        // No easy budget this week (quality already meets/exceeds the
        // target) — rest instead of a floored token run.
        workoutType = "rest";
      } else if (isPostLong && ctx.easyDayPrefs.recoveryAfterLong) {
        workoutType = "recovery";
        workoutData = {
          name: "Recovery run",
          total_distance_km: miles * KM_PER_MILE,
          target_pace: ctx.athletePaces.recovery ? formatPace(ctx.athletePaces.recovery) : null,
          adapted: true,
        };
        notes = "Day after long run — keep it very easy";
      } else if (stridesDows.has(dow)) {
        workoutType = "easy";
        workoutData = {
          name: `${miles}mi easy + strides`,
          total_distance_km: miles * KM_PER_MILE,
          target_pace: ctx.athletePaces.easy ? formatPace(ctx.athletePaces.easy) : null,
          strides: "6x100m strides at the end (~mile pace, full recovery)",
          adapted: true,
        };
        notes = "Strides finisher — sharpen the legs before tomorrow's quality";
      } else {
        workoutType = "easy";
        workoutData = {
          name: `${miles}mi easy`,
          total_distance_km: miles * KM_PER_MILE,
          target_pace: ctx.athletePaces.easy ? formatPace(ctx.athletePaces.easy) : null,
          adapted: true,
        };
      }
    }

    const isQualityDay = qualityDaysByDow.has(dow);
    out.push({
      plan_id: ctx.planId,
      date: formatDate(workoutDate),
      day_of_week: dow + 1,
      week_number: week.weekNumber,
      session: 1,
      workout_type: workoutType,
      workout_data: workoutData,
      status: "scheduled",
      notes,
      source: isQualityDay
        ? "coach_locked"
        : explicitRestDows.has(dow)
          ? "rest"
          : "easy_fill",
      is_movable: isQualityDay,
    });
  }
  return out;
}

/** Build quality_session_templates rows for adaptive plans. */
function buildQualityTemplates(weeks: PlanTemplateWeek[], ctx: MaterializeContext): QualityTemplateInsert[] {
  const out: QualityTemplateInsert[] = [];
  for (const week of weeks) {
    const templateWorkouts = week.workouts ?? [];
    let rank = 0;
    for (const tw of templateWorkouts) {
      const type = tw.workoutType;
      if (!type || type === "rest" ||
          !["tempo", "intervals", "long_run", "race", "progression"].includes(type)) continue;
      rank++;
      const miles = workoutMiles(tw);
      out.push({
        plan_id: ctx.planId,
        week_number: week.weekNumber,
        purpose: type === "long_run" ? "long run"
                 : type === "tempo" ? "threshold development"
                 : type === "intervals" ? "speed development"
                 : type,
        workout_type: type,
        workout_data: personalizeWorkoutData(tw.workoutData, ctx.athletePaces),
        target_pace_percentage: null,
        target_distance_miles: miles > 0 ? miles : null,
        target_duration_minutes: null,
        priority_rank: rank,
        suggested_day_of_week: tw.dayOfWeek ?? null,
        is_placed: true,
      });
    }
  }
  return out;
}

// MARK: - Types

interface PlanTemplateWeek {
  weekNumber: number;
  theme?: string;
  notes?: string;
  workouts?: PlanTemplateWorkout[];
  targetMilesMin?: number;
  targetMilesMax?: number;
}

interface PlanTemplateWorkout {
  dayOfWeek: number;
  workoutTemplateId?: string;
  workoutType?: string;
  workoutData?: Record<string, unknown> | null;
  notes?: string;
}

interface ScheduledWorkoutInsert {
  plan_id: string;
  date: string;
  day_of_week: number;
  week_number: number;
  session: number;
  workout_type: string;
  workout_data: Record<string, unknown> | null;
  status: string;
  notes: string | null;
  source: string;
  is_movable: boolean;
  pool_template_id?: string | null;
}

interface QualityTemplateInsert {
  plan_id: string;
  week_number: number;
  purpose: string;
  workout_type: string;
  workout_data: Record<string, unknown> | null;
  target_pace_percentage: number | null;
  target_distance_miles: number | null;
  target_duration_minutes: number | null;
  priority_rank: number;
  suggested_day_of_week: number | null;
  is_placed: boolean;
}

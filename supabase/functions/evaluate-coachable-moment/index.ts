/**
 * evaluate-coachable-moment — V1
 *
 * Spec: docs/specs/coachable_moment.md
 *
 * Takes an athlete_user_id, looks up their active coach, fetches the data each
 * V1 rule needs, runs all rules, and inserts any coachable_moments that fire.
 *
 * Rules (in `_shared/rules/`):
 *   - load_spike_plus_injury  → high   / recommend_evaluation
 *   - low_mood_streak         → med    / suggest_deload
 *   - missed_workouts         → low    / send_check_in
 *
 * Invocation:
 *   POST /functions/v1/evaluate-coachable-moment
 *   Body: { "athlete_user_id": "<uuid-as-text>" }
 *   Auth: service-role key (prod path — postgres trigger / cron) OR an
 *         authenticated coach whose roster contains the athlete (dev trigger)
 *
 * Response:
 *   200 { moments: CoachableMoment[] }   // [] if no active coach or no rules fired
 *   400 { error: "..." }
 *   401 { error: "..." }
 *   403 { error: "..." }
 *   500 { error: "..." }
 */

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  ALL_RULES,
  type ConfirmedRaceSummary,
  type GoalRaceInfo,
  type RuleContext,
  type ScheduledWorkoutRow,
} from "../_shared/rules/index.ts";
import { pickAnchorRace } from "../_shared/paces.ts";
import type { TrainingLogRow } from "../_shared/weeklyAnalytics.ts";
import { corsHeaders } from "../_shared/cors.ts";

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });

const TRAINING_LOG_FIELDS =
  "id, workout_date, workout_distance_miles, workout_duration_minutes, " +
  "workout_type, workout_pace_per_mile, pace_segments, mood, notes, " +
  "cleaned_notes, coach_insight, " +
  "weather_actual, weather_adjusted_pace_delta_seconds_per_mile";

const SCHEDULED_WORKOUT_FIELDS = "id, date, status, workout_type";

/** Returns the Monday-of-this-week at 00:00 UTC for the given reference date. */
function startOfIsoWeek(now: Date): Date {
  const d = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()));
  // getUTCDay: 0 = Sunday, 1 = Monday, ..., 6 = Saturday
  // Map to ISO week start (Monday = 0).
  const dayOffset = (d.getUTCDay() + 6) % 7;
  d.setUTCDate(d.getUTCDate() - dayOffset);
  return d;
}

function addDays(d: Date, days: number): Date {
  const out = new Date(d);
  out.setUTCDate(out.getUTCDate() + days);
  return out;
}

function isoDate(d: Date): string {
  return d.toISOString().slice(0, 10);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  try {
    // ------------------------------------------------------------------
    // Service-role client — used for all DB reads/writes.
    // ------------------------------------------------------------------
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    // ------------------------------------------------------------------
    // Auth: accept either service-role OR an authenticated coach.
    // ------------------------------------------------------------------
    const authHeader = req.headers.get("Authorization") ?? "";
    const token = authHeader.replace(/^Bearer\s+/i, "");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const isServiceRole = token && token === serviceKey;

    let callerCoachId: string | null = null;

    if (!isServiceRole) {
      if (!token) return json({ error: "Authentication required" }, 401);

      const { data: { user }, error: authError } = await supabase.auth.getUser(token);
      if (authError || !user) return json({ error: "Unauthorized" }, 401);

      const { data: coachRow } = await supabase
        .from("coach_profiles")
        .select("id")
        .eq("user_id", user.id)
        .maybeSingle();

      if (!coachRow) return json({ error: "Coach profile required" }, 403);
      callerCoachId = coachRow.id as string;
    }

    // ------------------------------------------------------------------
    // Input
    // ------------------------------------------------------------------
    let body: { athlete_user_id?: string };
    try {
      body = await req.json();
    } catch {
      return json({ error: "Invalid JSON body" }, 400);
    }

    const athleteUserId = body.athlete_user_id?.trim();
    if (!athleteUserId) return json({ error: "athlete_user_id required" }, 400);

    // ------------------------------------------------------------------
    // Look up the athlete's active coach.
    // ------------------------------------------------------------------
    const { data: relationship, error: relError } = await supabase
      .from("coach_athlete_relationships")
      .select("coach_id")
      .eq("athlete_user_id", athleteUserId)
      .eq("status", "active")
      .maybeSingle();

    if (relError) {
      console.error("relationship lookup failed", relError);
      return json({ error: "Lookup failed" }, 500);
    }

    if (!relationship) {
      return json({ moments: [], note: "athlete has no active coach" });
    }

    const coachId = relationship.coach_id as string;

    if (callerCoachId && callerCoachId !== coachId) {
      return json({ error: "Athlete not in your roster" }, 403);
    }

    // ------------------------------------------------------------------
    // Fetch the data each rule needs.
    //   - logs: training_logs in last 28 days (rule 1 needs 28d, rule 2 only
    //     needs the last 3 — overfetch is fine, the table is small per athlete)
    //   - scheduledThisWeek: scheduled_workouts dated Mon-Sun of current ISO week
    // ------------------------------------------------------------------
    const now = new Date();
    const twentyEightDaysAgo = new Date(now);
    twentyEightDaysAgo.setUTCDate(twentyEightDaysAgo.getUTCDate() - 28);

    const weekStart = startOfIsoWeek(now);
    const weekEnd = addDays(weekStart, 7); // exclusive

    const [
      { data: logsData, error: logsError },
      { data: schedData, error: schedError },
      { data: stateData },
      { data: planData },
      { data: goalData },
    ] = await Promise.all([
      supabase
        .from("training_logs")
        .select(TRAINING_LOG_FIELDS)
        .eq("user_id", athleteUserId)
        .gte("workout_date", twentyEightDaysAgo.toISOString())
        .order("workout_date", { ascending: false }),
      supabase
        .from("scheduled_workouts")
        .select(SCHEDULED_WORKOUT_FIELDS)
        .eq("user_id", athleteUserId)
        .gte("date", isoDate(weekStart))
        .lt("date", isoDate(weekEnd)),
      // Race-anchoring context (Phase 2 sub-task F) — all optional; a
      // failed/empty read just means buildVsLastCycle won't fire.
      supabase
        .from("athlete_state")
        .select("confirmed_races")
        .eq("user_id", athleteUserId)
        .maybeSingle(),
      supabase
        .from("training_plans")
        .select("target_race_distance, end_date")
        .eq("user_id", athleteUserId)
        .eq("status", "active")
        .order("start_date", { ascending: false })
        .limit(1)
        .maybeSingle(),
      supabase
        .from("user_goals")
        .select("target_date")
        .eq("user_id", athleteUserId)
        .eq("status", "active")
        .gte("target_date", now.toISOString())
        .order("target_date", { ascending: true })
        .limit(1)
        .maybeSingle(),
    ]);

    if (logsError) {
      console.error("training_logs fetch failed", logsError);
      return json({ error: "Logs fetch failed" }, 500);
    }
    if (schedError) {
      console.error("scheduled_workouts fetch failed", schedError);
      return json({ error: "Scheduled workouts fetch failed" }, 500);
    }

    // ── Race-anchoring context ──────────────────────────────────────────
    const confirmedRaces: ConfirmedRaceSummary[] | null =
      Array.isArray(stateData?.confirmed_races) && stateData.confirmed_races.length > 0
        ? (stateData.confirmed_races as ConfirmedRaceSummary[])
        : null;

    // Goal race: the active plan's end date (distance known) wins; else the
    // next active user_goal (date only — user_goals has no distance column).
    let goalRace: GoalRaceInfo | null = null;
    if (planData?.end_date && new Date(planData.end_date).getTime() > now.getTime()) {
      goalRace = { date: planData.end_date, distance: planData.target_race_distance ?? null };
    } else if (goalData?.target_date) {
      goalRace = { date: goalData.target_date, distance: null };
    }

    // Prior-cycle build logs: only fetched when an anchor race exists.
    // Window = race-day −63d … −21d (the build, excluding the taper) —
    // must match PRIOR_WINDOW_WEEKS in _shared/rules/buildVsLastCycle.ts.
    let priorCycleLogs: TrainingLogRow[] | null = null;
    const anchor = pickAnchorRace(confirmedRaces);
    if (anchor) {
      const raceTs = new Date(anchor.date).getTime();
      if (Number.isFinite(raceTs)) {
        const from = new Date(raceTs - 63 * 86400000).toISOString();
        const to = new Date(raceTs - 21 * 86400000).toISOString();
        const { data: priorData, error: priorErr } = await supabase
          .from("training_logs")
          .select(TRAINING_LOG_FIELDS)
          .eq("user_id", athleteUserId)
          .gte("workout_date", from)
          .lt("workout_date", to)
          .order("workout_date", { ascending: false });
        if (priorErr) {
          console.error("prior-cycle logs fetch failed (non-fatal)", priorErr);
        } else {
          priorCycleLogs = (priorData ?? []) as unknown as TrainingLogRow[];
        }
      }
    }

    const ctx: RuleContext = {
      athleteUserId,
      coachId,
      now,
      logs: (logsData ?? []) as unknown as TrainingLogRow[],
      scheduledThisWeek: (schedData ?? []) as unknown as ScheduledWorkoutRow[],
      confirmedRaces,
      goalRace,
      priorCycleLogs,
    };

    // ------------------------------------------------------------------
    // Run all rules.
    // ------------------------------------------------------------------
    const fired = ALL_RULES
      .map((rule) => {
        try {
          return rule(ctx);
        } catch (err) {
          console.error("rule threw", err);
          return null;
        }
      })
      .filter((m): m is NonNullable<typeof m> => m !== null);

    if (fired.length === 0) {
      return json({ moments: [], note: "no rules fired" });
    }

    // ------------------------------------------------------------------
    // Re-fire suppression. The unique partial index
    // `coachable_moments_one_open_per_rule` enforces "at most one open
    // moment per athlete+rule." Pre-flight SELECT lets us filter the
    // batch *and* report which rules were suppressed in the response —
    // useful for debugging "why didn't this fire?"
    // ------------------------------------------------------------------
    const { data: alreadyOpen, error: openErr } = await supabase
      .from("coachable_moments")
      .select("rule_id")
      .eq("athlete_user_id", athleteUserId)
      .eq("status", "open");
    if (openErr) {
      console.error("open-rule lookup failed", openErr);
      return json({ error: "Suppression lookup failed" }, 500);
    }
    const suppressedRuleIds = new Set(((alreadyOpen ?? []) as Array<{ rule_id: string }>).map((r) => r.rule_id));
    const toInsert = fired.filter((m) => !suppressedRuleIds.has(m.rule_id));
    const suppressed = fired
      .filter((m) => suppressedRuleIds.has(m.rule_id))
      .map((m) => m.rule_id);

    if (toInsert.length === 0) {
      return json({ moments: [], suppressed, note: "all firing rules already have open moments" });
    }

    const { data: inserted, error: insertError } = await supabase
      .from("coachable_moments")
      .insert(toInsert)
      .select("*");

    if (insertError) {
      console.error("insert failed", insertError);
      return json({ error: "Insert failed", detail: insertError.message }, 500);
    }

    return json({ moments: inserted ?? [], suppressed });
  } catch (err) {
    console.error("evaluate-coachable-moment unexpected error", err);
    return json({ error: "Internal server error" }, 500);
  }
});

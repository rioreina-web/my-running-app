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
 *   }
 *
 * Response:
 *   { trainingPlanId, subscriptionId } | { error }
 */

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { getAuthenticatedUser, unauthorizedResponse } from "../_shared/auth.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // Authenticate the caller
    const callerUserId = await getAuthenticatedUser(req);
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

    if (!planTemplateId || !athleteUserId || !startDate) {
      return errorResponse("Missing required fields: planTemplateId, athleteUserId, startDate");
    }

    // Verify the caller is either the athlete themselves or an authorized coach
    if (callerUserId !== athleteUserId) {
      // Check if caller is a coach with a relationship to this athlete
      const authCheck = createClient(supabaseUrl, serviceKey);
      const { data: relationship } = await authCheck
        .from("coach_athlete_relationships")
        .select("id")
        .eq("coach_user_id", callerUserId)
        .eq("athlete_user_id", athleteUserId)
        .eq("status", "active")
        .maybeSingle();

      if (!relationship) {
        return errorResponse("Not authorized to assign plans to this athlete");
      }
    }

    const supabase = createClient(supabaseUrl, serviceKey);

    // 1. Fetch the plan template
    const { data: template, error: templateErr } = await supabase
      .from("plan_templates")
      .select("*")
      .eq("id", planTemplateId)
      .single();

    if (templateErr || !template) {
      return errorResponse("Plan template not found");
    }

    // 2. Check for existing subscription (prevent duplicates)
    const { data: existing } = await supabase
      .from("athlete_plan_subscriptions")
      .select("id")
      .eq("plan_template_id", planTemplateId)
      .eq("athlete_user_id", athleteUserId)
      .maybeSingle();

    if (existing) {
      return errorResponse("You are already subscribed to this plan");
    }

    // 3. Determine plan metadata
    const raceDistance = targetRaceDistance ?? template.target_distance ?? "marathon";
    const durationWeeks: number = template.duration_weeks;
    const start = new Date(startDate);

    // End date = start date + duration weeks - 1 day
    const end = new Date(start);
    end.setDate(end.getDate() + durationWeeks * 7 - 1);

    const planName = template.name;
    const planId = crypto.randomUUID();

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
    });

    if (planErr) {
      console.error("Plan insert error:", planErr);
      return errorResponse("Failed to create training plan: " + planErr.message);
    }

    // 5. Build and bulk-insert scheduled_workouts
    const weeks: PlanTemplateWeek[] = template.weeks ?? [];
    const workoutsToInsert: ScheduledWorkoutInsert[] = [];

    for (const week of weeks) {
      const weekStartOffset = (week.weekNumber - 1) * 7; // days from plan start

      for (const dayWorkout of week.workouts ?? []) {
        const dayOffset = weekStartOffset + (dayWorkout.dayOfWeek ?? 0);
        const workoutDate = new Date(start);
        workoutDate.setDate(workoutDate.getDate() + dayOffset);

        const workoutType = dayWorkout.workoutType ?? "rest";

        // Resolve workout data: prefer inline, fall back to nothing for rest days
        const workoutData = workoutType !== "rest" ? (dayWorkout.workoutData ?? null) : null;

        workoutsToInsert.push({
          plan_id: planId,
          date: formatDate(workoutDate),
          day_of_week: dayWorkout.dayOfWeek ?? 0,
          week_number: week.weekNumber,
          session: 1,
          workout_type: workoutType,
          workout_data: workoutData,
          status: "scheduled",
          notes: dayWorkout.notes ?? null,
        });
      }
    }

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

    // 6. Create athlete_plan_subscription record
    const subscriptionId = crypto.randomUUID();
    const { error: subErr } = await supabase.from("athlete_plan_subscriptions").insert({
      id: subscriptionId,
      plan_template_id: planTemplateId,
      athlete_user_id: athleteUserId,
      training_plan_id: planId,
      start_date: startDate,
      status: "active",
    });

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
});

// MARK: - Helpers

function errorResponse(message: string): Response {
  return new Response(
    JSON.stringify({ error: message }),
    { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 400 }
  );
}

function formatDate(date: Date): string {
  return date.toISOString().split("T")[0];
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

// MARK: - Types

interface PlanTemplateWeek {
  weekNumber: number;
  theme?: string;
  notes?: string;
  workouts?: PlanTemplateWorkout[];
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
}

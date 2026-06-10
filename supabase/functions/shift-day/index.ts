/**
 * shift-day — athlete moves a single scheduled workout to another day in the
 * same Mon–Sun calendar week. Swaps dates with whatever workout (if any) is
 * already on the destination. Always green-tier: routine customization that
 * logs but does not flag to the coach.
 *
 * Contract: POST with JWT
 *   body  { scheduled_workout_id: uuid, new_date: "YYYY-MM-DD" }
 *   200   { ok: true, swapped_with: uuid | null, new_date }
 *   400   { error } — same-week / past-date / invalid-input violations
 *   401   { error } — missing/invalid JWT
 *   403   { error } — workout does not belong to caller
 *   500   { error } — unexpected failure
 *
 * Design source: docs/athlete-plan-ux.md §2A, §5.
 * Related: plan_adjustments schema (20260417600000), tier/reason_code
 * additions (20260424100000).
 */
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";
import { getAuthenticatedUser, unauthorizedResponse } from "../_shared/auth.ts";

interface ShiftDayBody {
  scheduled_workout_id?: string;
  new_date?: string;
}

interface ScheduledWorkoutRow {
  id: string;
  user_id: string | null;
  plan_id: string | null;
  scheduled_date: string;
  day_of_week: number | null;
  week_number: number | null;
  workout_type: string | null;
  workout_data: unknown;
}

// Parse a YYYY-MM-DD string to a local-midnight Date. Matches the web helper
// in lib/utils.ts — keeps day-of-week math consistent across surfaces.
function parseLocalDate(s: string): Date {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(s);
  if (!m) return new Date(NaN);
  return new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]));
}

// Monday-anchored week start for a given date (returns the Monday as YYYY-MM-DD).
function weekStartMonday(d: Date): string {
  const dow = d.getDay(); // 0=Sun..6=Sat
  const daysBack = (dow + 6) % 7; // Mon=0, Sun=6
  const monday = new Date(d);
  monday.setDate(d.getDate() - daysBack);
  return `${monday.getFullYear()}-${String(monday.getMonth() + 1).padStart(2, "0")}-${String(monday.getDate()).padStart(2, "0")}`;
}

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

// Hooks to inject for tests. `resolveUser` lets us skip the real JWT path;
// `buildClient` lets us feed a fake supabase client. Both are optional and
// keep the deployed handler working without any test plumbing.
export interface ShiftDayDeps {
  resolveUser?: (req: Request) => Promise<string | null>;
  buildClient?: () => ReturnType<typeof createClient>;
  now?: () => Date;
}

export async function handleShiftDay(
  req: Request,
  deps: ShiftDayDeps = {},
): Promise<Response> {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  const userId = await (deps.resolveUser ?? getAuthenticatedUser)(req);
  if (!userId) return unauthorizedResponse(corsHeaders);

  let body: ShiftDayBody;
  try {
    body = (await req.json()) as ShiftDayBody;
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  const scheduledWorkoutId = body.scheduled_workout_id;
  const newDate = body.new_date;

  if (!scheduledWorkoutId || !newDate) {
    return json(
      { error: "Missing required fields: scheduled_workout_id, new_date" },
      400,
    );
  }
  if (!/^\d{4}-\d{2}-\d{2}$/.test(newDate)) {
    return json({ error: "new_date must be YYYY-MM-DD" }, 400);
  }
  const newDateObj = parseLocalDate(newDate);
  if (isNaN(newDateObj.getTime())) {
    return json({ error: "new_date is not a valid date" }, 400);
  }

  // Use the service-role client for mutations since we enforce ownership
  // manually. The RLS policy would also work, but we need cross-row swaps
  // which are cleaner via service role + explicit user_id checks.
  const supabase = deps.buildClient
    ? deps.buildClient()
    : createClient(
        Deno.env.get("SUPABASE_URL")!,
        Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      );

  // 1. Load the source workout and verify ownership.
  const { data: source, error: sourceErr } = await supabase
    .from("scheduled_workouts")
    .select("id, user_id, plan_id, scheduled_date, day_of_week, week_number, workout_type, workout_data")
    .eq("id", scheduledWorkoutId)
    .maybeSingle<ScheduledWorkoutRow>();

  if (sourceErr) {
    console.error("shift-day: source lookup failed", sourceErr);
    return json({ error: "Database error" }, 500);
  }
  if (!source) {
    return json({ error: "Workout not found" }, 404);
  }

  // Ownership. Some older rows may not have user_id set directly; in that
  // case resolve via the training plan.
  let sourceUserId: string | null = source.user_id ?? null;
  if (!sourceUserId && source.plan_id) {
    const { data: planRow } = await supabase
      .from("training_plans")
      .select("user_id")
      .eq("id", source.plan_id)
      .maybeSingle<{ user_id: string }>();
    sourceUserId = planRow?.user_id ?? null;
  }
  if (sourceUserId !== userId) {
    return json({ error: "You do not own this workout" }, 403);
  }

  // 2. Same-week validation.
  const sourceWeekStart = weekStartMonday(parseLocalDate(source.scheduled_date));
  const newWeekStart = weekStartMonday(newDateObj);
  if (sourceWeekStart !== newWeekStart) {
    return json(
      { error: "Can only move within the same Mon–Sun week" },
      400,
    );
  }

  // 3. Past-date rejection. "Today" is computed in the server's timezone,
  //    which is UTC for Deno edge functions. Close enough for a same-week
  //    shift; a client-side check catches finer timezone edge cases before
  //    the request is sent.
  const todayStr = (() => {
    const d = (deps.now ?? (() => new Date()))();
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
  })();
  if (source.scheduled_date < todayStr) {
    return json({ error: "Cannot move a past-dated workout" }, 403);
  }
  if (newDate < todayStr) {
    return json({ error: "Cannot move to a past date" }, 403);
  }
  if (source.scheduled_date === newDate) {
    return json({ error: "new_date equals current date — nothing to do" }, 400);
  }

  // 4. Destination lookup — is there a workout already on new_date for this
  //    plan? If so we swap; if not we just move.
  const { data: destExisting, error: destErr } = await supabase
    .from("scheduled_workouts")
    .select("id, user_id, plan_id, scheduled_date, day_of_week, week_number, workout_type, workout_data")
    .eq("plan_id", source.plan_id)
    .eq("scheduled_date", newDate)
    .maybeSingle<ScheduledWorkoutRow>();

  if (destErr) {
    console.error("shift-day: destination lookup failed", destErr);
    return json({ error: "Database error" }, 500);
  }

  // Compute new day_of_week for the moved row. dayOfWeek stored as 1=Mon..7=Sun.
  const newDowJS = newDateObj.getDay(); // 0=Sun..6=Sat
  const newDow = newDowJS === 0 ? 7 : newDowJS;

  // 5. Apply the swap or simple move. Do both writes, then validate. If the
  //    second update fails we roll back the first manually — Supabase JS
  //    doesn't expose a transaction primitive from edge functions.
  let swappedWith: string | null = null;

  if (destExisting) {
    // Swap: dest takes source's old date, source takes new_date.
    swappedWith = destExisting.id;
    const sourceOldDate = source.scheduled_date;
    const sourceOldDow = source.day_of_week;

    // Move source to new_date first.
    const { error: e1 } = await supabase
      .from("scheduled_workouts")
      .update({ scheduled_date: newDate, day_of_week: newDow })
      .eq("id", source.id);
    if (e1) {
      console.error("shift-day: source move failed", e1);
      return json({ error: "Failed to move workout" }, 500);
    }

    // Move dest to source's old date.
    const { error: e2 } = await supabase
      .from("scheduled_workouts")
      .update({ scheduled_date: sourceOldDate, day_of_week: sourceOldDow })
      .eq("id", destExisting.id);
    if (e2) {
      // Roll back source.
      await supabase
        .from("scheduled_workouts")
        .update({ scheduled_date: sourceOldDate, day_of_week: sourceOldDow })
        .eq("id", source.id);
      console.error("shift-day: dest move failed, rolled back", e2);
      return json({ error: "Failed to complete swap" }, 500);
    }
  } else {
    // Simple move — no swap target.
    const { error: e1 } = await supabase
      .from("scheduled_workouts")
      .update({ scheduled_date: newDate, day_of_week: newDow })
      .eq("id", source.id);
    if (e1) {
      console.error("shift-day: move failed", e1);
      return json({ error: "Failed to move workout" }, 500);
    }
  }

  // 6. Audit row. trigger_type + trigger_evidence are NOT NULL on the
  //    existing plan_adjustments schema so we supply sensible defaults.
  const actionPayload = {
    before: {
      source: {
        id: source.id,
        scheduled_date: source.scheduled_date,
        day_of_week: source.day_of_week,
        workout_type: source.workout_type,
      },
      dest: destExisting
        ? {
            id: destExisting.id,
            scheduled_date: destExisting.scheduled_date,
            day_of_week: destExisting.day_of_week,
            workout_type: destExisting.workout_type,
          }
        : null,
    },
    after: {
      source: {
        id: source.id,
        scheduled_date: newDate,
        day_of_week: newDow,
      },
      dest: destExisting
        ? {
            id: destExisting.id,
            scheduled_date: source.scheduled_date,
            day_of_week: source.day_of_week,
          }
        : null,
    },
    diff: destExisting
      ? [
          { id: source.id, from: source.scheduled_date, to: newDate },
          { id: destExisting.id, from: newDate, to: source.scheduled_date },
        ]
      : [{ id: source.id, from: source.scheduled_date, to: newDate }],
  };

  const { error: adjErr } = await supabase.from("plan_adjustments").insert({
    user_id: userId,
    plan_id: source.plan_id,
    trigger_type: "user_action",
    trigger_evidence: { source: "shift_day" },
    action_type: "shift_day",
    action_payload: actionPayload,
    auto_applied: true,
    applied_at: new Date().toISOString(),
    tier: "green",
    reason_code: "shift_day",
    week_number: source.week_number,
  });
  if (adjErr) {
    // Non-fatal — the workouts moved successfully even if we couldn't
    // record the adjustment. Log loudly so we notice.
    console.error("shift-day: plan_adjustments insert failed", adjErr);
  }

  return json(
    { ok: true, swapped_with: swappedWith, new_date: newDate },
    200,
  );
}

Deno.serve((req) => handleShiftDay(req));

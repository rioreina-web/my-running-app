/**
 * edit-scheduled-workout — an athlete edits the STRUCTURE of one of their own
 * future scheduled workouts (reps/pace/warmup via workout_data.steps, plus
 * type/name/notes). Always yellow-tier: a real change to the plan the coach
 * built, so it logs AND flags to the coach (unlike shift-day's green move).
 *
 * Contract: POST with JWT
 *   body  { scheduled_workout_id: uuid,
 *           workout_data?: object,          // full PlannedWorkout JSON (steps…)
 *           workout_type?: string,          // 10-zone / structural label
 *           notes?: string | null,
 *           reason_code?: fatigue|feeling_good|time_constraint|injury_niggle|travel|other,
 *           reason_text?: string (≤280 chars),
 *           confirm_race_week?: boolean,    // required to touch the race week
 *           duplicate_to_date?: "YYYY-MM-DD" } // DUPLICATE mode — see below
 *   200   { ok: true, scheduled_workout_id }                       (edit)
 *   200   { ok: true, scheduled_workout_id, duplicated_from }      (duplicate)
 *   400   { error } — nothing to change / past workout / race-week unconfirmed
 *   401   { error } — missing/invalid JWT
 *   403   { error } — workout does not belong to caller
 *   404   { error } — workout not found
 *   500   { error } — unexpected failure
 *
 * DUPLICATE mode (2026-07-15, iOS workout builder): when `duplicate_to_date`
 * is present the source row is NOT modified — a new scheduled_workouts row is
 * inserted on the target date with source = 'user_created' (vocab added by
 * migration 20260715120000). workout_data / workout_type / notes, when also
 * provided, override the copied values so "duplicate with tweaks" is one
 * call. Audit: plan_adjustments action_type 'duplicate_workout',
 * trigger_type 'user_action' — yellow tier when the source is a coach
 * prescription ('coach_locked'), green otherwise.
 *
 * Ownership + service-role pattern mirror shift-day. Pace is stored as
 * paceZone on each step; iOS resolves the zone against the athlete's local
 * pace table at render (WorkoutStepComponents.swift), so no per-athlete
 * repricing is needed here.
 */
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";
import { getAuthenticatedUser, unauthorizedResponse } from "../_shared/auth.ts";

interface EditBody {
  scheduled_workout_id?: string;
  workout_data?: unknown;
  workout_type?: string;
  notes?: string | null;
  status?: string;
  reason_code?: string;
  reason_text?: string;
  confirm_race_week?: boolean;
  /** Duplicate mode: copy this workout onto the given date instead of editing. */
  duplicate_to_date?: string;
}

const WORKOUT_STATUSES = new Set(["scheduled", "completed", "skipped", "modified"]);

// Closed vocabulary for the athlete's "why" (optional).
const EDIT_REASON_CODES = new Set([
  "fatigue",
  "feeling_good",
  "time_constraint",
  "injury_niggle",
  "travel",
  "other",
]);

interface ScheduledWorkoutRow {
  id: string;
  user_id: string | null;
  plan_id: string | null;
  date: string;
  day_of_week: number | null;
  week_number: number | null;
  session: number | null;
  workout_type: string | null;
  workout_data: unknown;
  notes: string | null;
  source: string | null;
}

function parseLocalDate(s: string): Date {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(s);
  if (!m) return new Date(NaN);
  return new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]));
}

function fmtDate(d: Date): string {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

// Test seams — same shape as shift-day's deps.
export interface EditWorkoutDeps {
  resolveUser?: (req: Request) => Promise<string | null>;
  buildClient?: () => ReturnType<typeof createClient>;
  now?: () => Date;
}

export async function handleEditWorkout(
  req: Request,
  deps: EditWorkoutDeps = {},
): Promise<Response> {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const userId = await (deps.resolveUser ?? getAuthenticatedUser)(req);
  if (!userId) return unauthorizedResponse(corsHeaders);

  let body: EditBody;
  try {
    body = (await req.json()) as EditBody;
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  const id = body.scheduled_workout_id;
  if (!id) return json({ error: "Missing required field: scheduled_workout_id" }, 400);

  const hasData = body.workout_data !== undefined && body.workout_data !== null;
  const hasType = typeof body.workout_type === "string" && body.workout_type.length > 0;
  const hasNotes = body.notes !== undefined;
  const hasStatus = typeof body.status === "string" && body.status.length > 0;
  const isDuplicate = body.duplicate_to_date !== undefined && body.duplicate_to_date !== null;
  if (isDuplicate && !/^\d{4}-\d{2}-\d{2}$/.test(String(body.duplicate_to_date))) {
    return json({ error: "duplicate_to_date must be YYYY-MM-DD" }, 400);
  }
  if (!hasData && !hasType && !hasNotes && !hasStatus && !isDuplicate) {
    return json({ error: "Nothing to change: provide workout_data, workout_type, notes, status, or duplicate_to_date" }, 400);
  }
  if (hasData && (typeof body.workout_data !== "object" || Array.isArray(body.workout_data))) {
    return json({ error: "workout_data must be an object" }, 400);
  }
  if (hasStatus && !WORKOUT_STATUSES.has(body.status!)) {
    return json({ error: `status must be one of: ${[...WORKOUT_STATUSES].join(", ")}` }, 400);
  }

  // Optional reason (closed vocabulary; bare text buckets to "other").
  let reasonCode: string | null = null;
  let reasonText: string | null = null;
  if (body.reason_code !== undefined && body.reason_code !== null) {
    if (typeof body.reason_code !== "string" || !EDIT_REASON_CODES.has(body.reason_code)) {
      return json({ error: `reason_code must be one of: ${[...EDIT_REASON_CODES].join(", ")}` }, 400);
    }
    reasonCode = body.reason_code;
  }
  if (typeof body.reason_text === "string" && body.reason_text.trim().length > 0) {
    reasonText = body.reason_text.trim().slice(0, 280);
    if (!reasonCode) reasonCode = "other";
  }

  const supabase = deps.buildClient
    ? deps.buildClient()
    : createClient(
        Deno.env.get("SUPABASE_URL")!,
        Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      );

  // 1. Load + verify ownership.
  const { data: source, error: sourceErr } = await supabase
    .from("scheduled_workouts")
    .select("id, user_id, plan_id, date, day_of_week, week_number, session, workout_type, workout_data, notes, source")
    .eq("id", id)
    .maybeSingle<ScheduledWorkoutRow>();
  if (sourceErr) {
    console.error("edit-scheduled-workout: source lookup failed", sourceErr);
    return json({ error: "Database error" }, 500);
  }
  if (!source) return json({ error: "Workout not found" }, 404);

  let sourceUserId: string | null = source.user_id ?? null;
  let planEndDate: string | null = null;
  let planStartDate: string | null = null;
  if (source.plan_id) {
    const { data: planRow } = await supabase
      .from("training_plans")
      .select("user_id, start_date, end_date")
      .eq("id", source.plan_id)
      .maybeSingle<{ user_id: string; start_date: string | null; end_date: string | null }>();
    if (!sourceUserId) sourceUserId = planRow?.user_id ?? null;
    planStartDate = planRow?.start_date ?? null;
    planEndDate = planRow?.end_date ?? null;
  }
  if (sourceUserId !== userId) return json({ error: "You do not own this workout" }, 403);

  const now = deps.now ? deps.now() : new Date();
  const todayStr = fmtDate(now);

  // ── DUPLICATE mode ────────────────────────────────────────────────────
  // Copies the source workout onto a new (today-or-future) date as a fresh
  // 'user_created' row. The source row is untouched — duplicating a past
  // favorite session onto next Tuesday is a legitimate move, so the
  // future-only guard applies to the TARGET date, not the source.
  if (isDuplicate) {
    const targetDate = String(body.duplicate_to_date);
    const targetObj = parseLocalDate(targetDate);
    if (isNaN(targetObj.getTime())) {
      return json({ error: "duplicate_to_date is not a valid date" }, 400);
    }
    if (targetDate < todayStr) {
      return json({ error: "Can only duplicate to today or a future date" }, 400);
    }
    if (targetDate === source.date) {
      return json({ error: "duplicate_to_date equals the source date — nothing to do" }, 400);
    }

    // Race-week guard — landing a duplicate inside the final 6 days of the
    // plan needs the same explicit confirm as editing that window.
    let targetInRaceWeek = false;
    if (planEndDate) {
      const raceStart = parseLocalDate(planEndDate);
      raceStart.setDate(raceStart.getDate() - 6);
      if (targetDate >= fmtDate(raceStart) && targetDate <= planEndDate) targetInRaceWeek = true;
    }
    if (targetInRaceWeek && body.confirm_race_week !== true) {
      return json({ error: "Race-week duplicate needs confirm_race_week: true", race_week: true }, 400);
    }

    // day_of_week stored 1=Mon..7=Sun (same convention as shift-day).
    const dowJS = targetObj.getDay(); // 0=Sun..6=Sat
    const targetDow = dowJS === 0 ? 7 : dowJS;

    // week_number from the plan's start date when we have one (Monday-to-
    // Monday counting matches the plan generators); else carry the source's.
    let targetWeek = source.week_number ?? 1;
    if (planStartDate) {
      const start = parseLocalDate(planStartDate);
      if (!isNaN(start.getTime())) {
        const msPerDay = 24 * 60 * 60 * 1000;
        const days = Math.floor((targetObj.getTime() - start.getTime()) / msPerDay);
        if (days >= 0) targetWeek = Math.floor(days / 7) + 1;
      }
    }

    const newRow = {
      user_id: userId,
      plan_id: source.plan_id,
      date: targetDate,
      day_of_week: targetDow,
      week_number: targetWeek,
      session: source.session ?? 1,
      workout_type: hasType ? body.workout_type! : source.workout_type,
      workout_data: hasData ? body.workout_data : source.workout_data,
      notes: hasNotes ? (body.notes ?? null) : source.notes,
      status: "scheduled",
      source: "user_created", // vocab: migration 20260715120000
      is_movable: true,
    };
    const { data: inserted, error: insErr } = await supabase
      .from("scheduled_workouts")
      .insert(newRow)
      .select("id")
      .maybeSingle<{ id: string }>();
    if (insErr || !inserted) {
      console.error("edit-scheduled-workout: duplicate insert failed", insErr);
      return json({ error: "Failed to duplicate workout" }, 500);
    }

    // Audit. Yellow when duplicating a coach prescription (the coach should
    // see the added quality volume); green for the athlete's own workouts.
    const dupTier = source.source === "coach_locked" ? "yellow" : "green";
    const { error: dupAdjErr } = await supabase.from("plan_adjustments").insert({
      user_id: userId,
      plan_id: source.plan_id,
      trigger_type: "user_action",
      trigger_evidence: { source: "duplicate_workout" },
      action_type: "duplicate_workout",
      action_payload: {
        before: null,
        after: {
          id: inserted.id,
          duplicated_from: source.id,
          date: targetDate,
          workout_type: newRow.workout_type,
          workout_data: newRow.workout_data,
        },
      },
      auto_applied: true,
      applied_at: new Date().toISOString(),
      tier: dupTier,
      reason_code: reasonCode ?? "duplicate_workout",
      reason_text: reasonText,
      week_number: targetWeek,
    });
    if (dupAdjErr) {
      // Non-fatal — the duplicate landed even if the ledger row didn't.
      console.error("edit-scheduled-workout: duplicate plan_adjustments insert failed", dupAdjErr);
    }

    return json(
      { ok: true, scheduled_workout_id: inserted.id, duplicated_from: source.id },
      200,
    );
  }

  // 2. Future-only: a past workout is history — don't rewrite it. (Today is
  //    editable; the athlete may be adjusting the session they're about to do.)
  if (source.date < todayStr) {
    return json({ error: "Can only edit today's or future workouts" }, 400);
  }

  // 3. Race-week guard (parity with the coach rewrite path): editing within the
  //    final 6 days, or turning a day into / out of a "race", needs an explicit
  //    confirm so a taper isn't clobbered by accident.
  const newType = hasType ? body.workout_type! : source.workout_type;
  let inRaceWeek = newType === "race" || source.workout_type === "race";
  if (planEndDate) {
    const raceStart = parseLocalDate(planEndDate);
    raceStart.setDate(raceStart.getDate() - 6);
    const raceStartStr = fmtDate(raceStart);
    if (source.date >= raceStartStr && source.date <= planEndDate) inRaceWeek = true;
  }
  if (inRaceWeek && body.confirm_race_week !== true) {
    return json({ error: "Race-week edit needs confirm_race_week: true", race_week: true }, 400);
  }

  // 4. Apply the edit.
  const patch: Record<string, unknown> = {};
  if (hasData) patch.workout_data = body.workout_data;
  if (hasType) patch.workout_type = body.workout_type;
  if (hasNotes) patch.notes = body.notes ?? null;
  if (hasStatus) patch.status = body.status;

  const { error: updErr } = await supabase
    .from("scheduled_workouts")
    .update(patch)
    .eq("id", source.id);
  if (updErr) {
    console.error("edit-scheduled-workout: update failed", updErr);
    return json({ error: "Failed to save workout" }, 500);
  }

  // 5. Audit + flag to coach (yellow tier).
  const actionPayload = {
    before: {
      id: source.id,
      workout_type: source.workout_type,
      workout_data: source.workout_data,
      notes: source.notes,
    },
    after: {
      id: source.id,
      workout_type: newType,
      workout_data: hasData ? body.workout_data : source.workout_data,
      notes: hasNotes ? (body.notes ?? null) : source.notes,
    },
  };
  const { error: adjErr } = await supabase.from("plan_adjustments").insert({
    user_id: userId,
    plan_id: source.plan_id,
    trigger_type: "user_action",
    trigger_evidence: { source: "edit_workout" },
    action_type: "edit_workout",
    action_payload: actionPayload,
    auto_applied: true,
    applied_at: new Date().toISOString(),
    tier: "yellow",
    reason_code: reasonCode ?? "edit_workout",
    reason_text: reasonText,
    week_number: source.week_number,
  });
  if (adjErr) {
    // Non-fatal — the edit saved even if the ledger row didn't. Log loudly.
    console.error("edit-scheduled-workout: plan_adjustments insert failed", adjErr);
  }

  return json({ ok: true, scheduled_workout_id: source.id }, 200);
}

Deno.serve((req) => handleEditWorkout(req));

/**
 * rewrite-block — coach rewrites a multi-week block of an athlete's LIVE plan.
 *
 * This is the service-role apply path for R5 (manual mid-block rewrite) from
 * outputs/adaptive-coach-plan-builder-spec-2026-07-03.md §5 and the Phase B
 * build plan (outputs/phase-b-live-plan-editing-buildplan-2026-07-03.md).
 *
 * The coach edits the materialized `scheduled_workouts` rows for a future week
 * range on a specific athlete's `training_plans` row. Past weeks are immutable
 * history. Every changed week is recorded in the `plan_adjustments` ledger with
 * a reversible before/after payload. AI is NOT involved here — this is
 * deterministic manual editing. The assisted (LLM) rewrite is Phase E and adds
 * an `assisted` input mode to this same function later.
 *
 * Contract: POST with the service-role key (called only from the trusted
 * Next.js API route /api/rewrite-block, which authenticates the coach first).
 *
 *   body {
 *     coachId: uuid,                 // coach_profiles.id (resolved server-side)
 *     athleteUserId: string,        // scheduled_workouts.user_id / training_plans.user_id
 *     planId: uuid,                 // training_plans.id (the athlete's live plan)
 *     weekRange: { fromWeek: int, toWeek: int },
 *     changes: Array<{
 *       scheduledWorkoutId?: uuid,  // present = edit existing; absent = new day
 *       date: "YYYY-MM-DD",
 *       weekNumber: int,
 *       workoutType: string,        // 10-zone vocab; DB CHECK is final arbiter
 *       workoutData?: object|null,  // PlannedWorkout JSON
 *       notes?: string|null
 *     }>,
 *     reasonCode: sickness|injury_niggle|race_change|life_event|performance|other,
 *     reasonText?: string,          // <= 280 chars
 *     confirmRaceWeek?: boolean     // required to edit the race week
 *   }
 *   200 { ok:true, changedWeeks:int[], updatedCount:int, insertedCount:int, adjustmentIds:uuid[] }
 *   400 { error } — validation / past-date / mismatch
 *   401 { error } — missing/invalid service-role auth
 *   403 { error } — coach does not own this athlete's plan
 *   409 { error, code:"race_week_confirm_required" } — race-week edit unconfirmed
 *   500 { error }
 *
 * ── Schema dependency (satisfied in prod 2026-07-03) ──────────────────────
 * Relies on `plan_adjustments.tier/reason_code/reason_text/week_number` and the
 * `coach_rewrite` / `rewrite_block` CHECK vocab. These landed via migrations
 * 20260703115000 (ledger-drift reconcile), 20260703120000 (vocab), applied to
 * prod on 2026-07-03. Verified present before this function was deployed.
 */
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";
import { requireServiceRole } from "../_shared/auth.ts";

// Closed vocabulary for the coach-rewrite reason picker (spec §5, §4 ledger).
const REWRITE_REASON_CODES = new Set([
  "sickness",
  "injury_niggle",
  "race_change",
  "life_event",
  "performance",
  "other",
]);

interface RewriteChange {
  scheduledWorkoutId?: string;
  date?: string;
  weekNumber?: number;
  workoutType?: string;
  workoutData?: unknown;
  notes?: string | null;
}

interface RewriteBlockBody {
  coachId?: string;
  athleteUserId?: string;
  planId?: string;
  weekRange?: { fromWeek?: number; toWeek?: number };
  changes?: RewriteChange[];
  reasonCode?: string;
  reasonText?: string;
  confirmRaceWeek?: boolean;
}

interface ScheduledWorkoutRow {
  id: string;
  plan_id: string | null;
  user_id: string | null;
  date: string;
  day_of_week: number | null;
  week_number: number | null;
  workout_type: string | null;
  workout_data: unknown;
  notes: string | null;
  status: string | null;
  source: string | null;
}

interface TrainingPlanRow {
  id: string;
  user_id: string;
  coach_id: string | null;
  start_date: string | null;
  end_date: string | null;
}

function parseLocalDate(s: string): Date {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(s);
  if (!m) return new Date(NaN);
  return new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]));
}

// Store day_of_week as 1=Mon..7=Sun (matches shift-day + the base schema).
function dowFromDate(d: Date): number {
  const js = d.getDay(); // 0=Sun..6=Sat
  return js === 0 ? 7 : js;
}

function todayStr(now: () => Date): string {
  const d = now();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

// Snapshot shape stored in the ledger's before/after payload. Keep it small
// but reversible — enough to restore the row.
function snapshot(row: ScheduledWorkoutRow | RewriteChange & { date?: string }) {
  return {
    id: (row as ScheduledWorkoutRow).id,
    date: (row as { date?: string }).date ?? null,
    day_of_week: (row as ScheduledWorkoutRow).day_of_week ?? null,
    week_number: (row as { week_number?: number; weekNumber?: number }).week_number ??
      (row as { weekNumber?: number }).weekNumber ?? null,
    workout_type: (row as ScheduledWorkoutRow).workout_type ??
      (row as RewriteChange).workoutType ?? null,
    workout_data: (row as ScheduledWorkoutRow).workout_data ??
      (row as RewriteChange).workoutData ?? null,
    notes: (row as { notes?: string | null }).notes ?? null,
  };
}

export interface RewriteBlockDeps {
  authGate?: (req: Request, cors: Record<string, string>) => Response | null;
  buildClient?: () => ReturnType<typeof createClient>;
  now?: () => Date;
  // Best-effort rationale regen hook (Phase C). No-op safe by default.
  fireRationaleRegen?: (planId: string, weeks: number[]) => Promise<void>;
}

export async function handleRewriteBlock(
  req: Request,
  deps: RewriteBlockDeps = {},
): Promise<Response> {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  // Service-role only — the API route authenticates the coach and resolves
  // coachId before calling us. Mirrors the assign-plan → subscribe-to-plan
  // trust boundary.
  const authFail = (deps.authGate ?? requireServiceRole)(req, corsHeaders);
  if (authFail) return authFail;

  let body: RewriteBlockBody;
  try {
    body = (await req.json()) as RewriteBlockBody;
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  const { coachId, athleteUserId, planId } = body;
  const fromWeek = body.weekRange?.fromWeek;
  const toWeek = body.weekRange?.toWeek;

  if (!coachId || !athleteUserId || !planId) {
    return json(
      { error: "Missing required fields: coachId, athleteUserId, planId" },
      400,
    );
  }
  if (
    typeof fromWeek !== "number" || typeof toWeek !== "number" ||
    fromWeek < 1 || toWeek < fromWeek
  ) {
    return json({ error: "weekRange must be { fromWeek, toWeek } with 1 <= fromWeek <= toWeek" }, 400);
  }
  if (!Array.isArray(body.changes) || body.changes.length === 0) {
    return json({ error: "changes must be a non-empty array" }, 400);
  }

  // Reason is required for a coach rewrite (unlike the optional move-day reason).
  if (typeof body.reasonCode !== "string" || !REWRITE_REASON_CODES.has(body.reasonCode)) {
    return json(
      { error: `reasonCode must be one of: ${[...REWRITE_REASON_CODES].join(", ")}` },
      400,
    );
  }
  const reasonCode = body.reasonCode;
  const reasonText = typeof body.reasonText === "string" && body.reasonText.trim().length > 0
    ? body.reasonText.trim().slice(0, 280)
    : null;

  const now = deps.now ?? (() => new Date());
  const today = todayStr(now);

  // ── Validate each change shape + future-only + in-range ──────────────
  for (const [i, c] of body.changes.entries()) {
    if (!c.date || !/^\d{4}-\d{2}-\d{2}$/.test(c.date)) {
      return json({ error: `changes[${i}].date must be YYYY-MM-DD` }, 400);
    }
    if (isNaN(parseLocalDate(c.date).getTime())) {
      return json({ error: `changes[${i}].date is not a valid date` }, 400);
    }
    // Future-only: past weeks are immutable history (spec §5). "Today" is
    // computed in UTC (Deno edge runtime); the client applies a finer local
    // check before sending.
    if (c.date <= today) {
      return json({ error: `changes[${i}].date must be in the future (past weeks are immutable)` }, 400);
    }
    if (typeof c.weekNumber !== "number" || c.weekNumber < fromWeek || c.weekNumber > toWeek) {
      return json({ error: `changes[${i}].weekNumber must fall within weekRange` }, 400);
    }
    if (typeof c.workoutType !== "string" || c.workoutType.trim().length === 0) {
      return json({ error: `changes[${i}].workoutType is required` }, 400);
    }
  }

  const supabase = deps.buildClient
    ? deps.buildClient()
    : createClient(
        Deno.env.get("SUPABASE_URL")!,
        Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      );

  // ── Load the plan + verify ownership ─────────────────────────────────
  const { data: plan, error: planErr } = await supabase
    .from("training_plans")
    .select("id, user_id, coach_id, start_date, end_date")
    .eq("id", planId)
    .maybeSingle<TrainingPlanRow>();

  if (planErr) {
    console.error("rewrite-block: plan lookup failed", planErr);
    return json({ error: "Database error" }, 500);
  }
  if (!plan) return json({ error: "Plan not found" }, 404);
  if (plan.user_id !== athleteUserId) {
    return json({ error: "planId does not belong to athleteUserId" }, 400);
  }

  // Ownership: the plan is directly coach-owned, OR the coach owns the plan
  // template the athlete is actively subscribed to (matches the athlete
  // detail page's gate, which is the roster source of truth).
  let ownsPlan = plan.coach_id === coachId;
  if (!ownsPlan) {
    const { data: sub } = await supabase
      .from("athlete_plan_subscriptions")
      .select("id, plan_template:plan_templates!inner(coach_id)")
      .eq("athlete_user_id", athleteUserId)
      .eq("status", "active")
      .eq("plan_template.coach_id", coachId)
      .limit(1)
      .maybeSingle();
    ownsPlan = Boolean(sub);
  }
  if (!ownsPlan) {
    return json({ error: "You do not coach this athlete's plan" }, 403);
  }

  // ── Race-week guard ──────────────────────────────────────────────────
  // If any change lands in the race week (within 6 days of end_date, or is a
  // 'race' workout) the coach must explicitly confirm (spec §5 guardrails).
  if (!body.confirmRaceWeek) {
    const raceWeekStart = plan.end_date
      ? (() => {
          const d = parseLocalDate(plan.end_date);
          d.setDate(d.getDate() - 6);
          return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
        })()
      : null;
    const touchesRaceWeek = body.changes.some((c) =>
      c.workoutType === "race" ||
      (raceWeekStart && plan.end_date && c.date! >= raceWeekStart && c.date! <= plan.end_date)
    );
    if (touchesRaceWeek) {
      return json(
        { error: "This edit touches the race week — set confirmRaceWeek to proceed", code: "race_week_confirm_required" },
        409,
      );
    }
  }

  // ── Load existing rows in range for the before-snapshot ──────────────
  const editIds = body.changes.map((c) => c.scheduledWorkoutId).filter(Boolean) as string[];
  const existingById = new Map<string, ScheduledWorkoutRow>();
  if (editIds.length > 0) {
    const { data: existing, error: exErr } = await supabase
      .from("scheduled_workouts")
      .select("id, plan_id, user_id, date, day_of_week, week_number, workout_type, workout_data, notes, status, source")
      .in("id", editIds);
    if (exErr) {
      console.error("rewrite-block: existing lookup failed", exErr);
      return json({ error: "Database error" }, 500);
    }
    for (const row of (existing ?? []) as ScheduledWorkoutRow[]) {
      // Defense: every edited row must belong to this plan.
      if (row.plan_id !== planId) {
        return json({ error: `scheduledWorkoutId ${row.id} is not on this plan` }, 400);
      }
      existingById.set(row.id, row);
    }
    for (const id of editIds) {
      if (!existingById.has(id)) {
        return json({ error: `scheduledWorkoutId ${id} not found` }, 400);
      }
    }
  }

  // ── Apply changes, grouping before/after per week for the ledger ─────
  // We do all writes then record the ledger. Supabase JS has no cross-row
  // transaction from an edge function, so on a write failure we stop and
  // report — partial application is possible and is called out in the build
  // plan as an accepted Phase-B limitation (manual diff review precedes this).
  const perWeek = new Map<number, { before: unknown[]; after: unknown[] }>();
  const bucket = (w: number) => {
    if (!perWeek.has(w)) perWeek.set(w, { before: [], after: [] });
    return perWeek.get(w)!;
  };

  let updatedCount = 0;
  let insertedCount = 0;

  for (const c of body.changes) {
    const dateObj = parseLocalDate(c.date!);
    const dow = dowFromDate(dateObj);
    const week = c.weekNumber!;

    if (c.scheduledWorkoutId) {
      const prev = existingById.get(c.scheduledWorkoutId)!;
      bucket(week).before.push(snapshot(prev));

      const { error: upErr } = await supabase
        .from("scheduled_workouts")
        .update({
          date: c.date,
          day_of_week: dow,
          week_number: week,
          workout_type: c.workoutType,
          workout_data: c.workoutData ?? null,
          notes: c.notes ?? prev.notes ?? null,
          source: "coach_locked",
        })
        .eq("id", c.scheduledWorkoutId);
      if (upErr) {
        console.error("rewrite-block: update failed", upErr);
        return json({ error: "Failed to update a workout", detail: upErr.message }, 500);
      }
      updatedCount++;
      bucket(week).after.push({
        id: c.scheduledWorkoutId,
        date: c.date,
        day_of_week: dow,
        week_number: week,
        workout_type: c.workoutType,
        workout_data: c.workoutData ?? null,
        notes: c.notes ?? prev.notes ?? null,
      });
    } else {
      // New day inserted into the block.
      bucket(week).before.push(null);
      const { data: inserted, error: insErr } = await supabase
        .from("scheduled_workouts")
        .insert({
          plan_id: planId,
          user_id: athleteUserId,
          date: c.date,
          day_of_week: dow,
          week_number: week,
          workout_type: c.workoutType,
          workout_data: c.workoutData ?? null,
          notes: c.notes ?? null,
          status: "scheduled",
          source: "coach_locked",
        })
        .select("id")
        .maybeSingle<{ id: string }>();
      if (insErr) {
        console.error("rewrite-block: insert failed", insErr);
        return json({ error: "Failed to insert a workout", detail: insErr.message }, 500);
      }
      insertedCount++;
      bucket(week).after.push({
        id: inserted?.id ?? null,
        date: c.date,
        day_of_week: dow,
        week_number: week,
        workout_type: c.workoutType,
        workout_data: c.workoutData ?? null,
        notes: c.notes ?? null,
      });
    }
  }

  // ── Ledger: one row per changed week (spec §5) ───────────────────────
  const changedWeeks = [...perWeek.keys()].sort((a, b) => a - b);
  const adjustmentIds: string[] = [];
  for (const week of changedWeeks) {
    const { before, after } = perWeek.get(week)!;
    const { data: adj, error: adjErr } = await supabase
      .from("plan_adjustments")
      .insert({
        user_id: athleteUserId,
        plan_id: planId,
        trigger_type: "coach_rewrite",
        trigger_evidence: { source: "rewrite_block", coach_id: coachId },
        action_type: "rewrite_block",
        action_payload: { before, after },
        auto_applied: true,
        applied_at: new Date().toISOString(),
        tier: "yellow",
        reason_code: reasonCode,
        reason_text: reasonText,
        week_number: week,
      })
      .select("id")
      .maybeSingle<{ id: string }>();
    if (adjErr) {
      // The workouts already changed. Log loudly — the ledger row is the audit
      // trail and the athlete-banner source, so a failure here matters, but we
      // don't unwind a successful rewrite over it.
      console.error("rewrite-block: plan_adjustments insert failed", adjErr);
    } else if (adj?.id) {
      adjustmentIds.push(adj.id);
    }
  }

  // ── R6 hook: regenerate day rationale for rewritten weeks ────────────
  // generate-day-rationale is a Phase C function; this is no-op safe until it
  // exists (spec §5 "re-triggers rationale generation").
  if (deps.fireRationaleRegen) {
    try {
      await deps.fireRationaleRegen(planId, changedWeeks);
    } catch (e) {
      console.error("rewrite-block: rationale regen hook failed (non-fatal)", e);
    }
  }

  return json(
    { ok: true, changedWeeks, updatedCount, insertedCount, adjustmentIds },
    200,
  );
}

Deno.serve((req) => handleRewriteBlock(req));

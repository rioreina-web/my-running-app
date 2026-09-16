/**
 * plan-edit — free-text plan adjustments: "make Tuesday an easy day",
 * "cut the long run to 14", "retarget Thursday's tempo to HM pace".
 *
 * PROPOSE-ONLY, deliberately, same shape as `draft-block-rewrite`: this
 * function reads the athlete's week, turns the coach's text into resolved
 * diffs and/or clarifying questions, and returns them. It never writes to
 * `scheduled_workouts` or `plan_adjustments`. Applying an approved diff is a
 * separate, human-triggered call through the existing edit paths
 * (`edit-scheduled-workout`, `shift-day`) — this endpoint's whole job is
 * producing something honest for a human to approve first.
 *
 * Pipeline (engine lives in `_shared/plan-edit-*.ts`, unit-tested there):
 *   text + week  →  parsePlanEdit (LLM, schema-constrained, never resolves
 *                    WHICH workout — only lifts a verbatim targetHint)
 *                →  validatePlanEditOps (bounds-check every field)
 *                →  planEdits (deterministic resolver: match hints to real
 *                    rows; anything ambiguous or missing a parameter becomes
 *                    a question with real options, never a guess)
 *                →  describePatch (human-readable before/after per resolved op)
 *
 * Contract: POST with JWT
 *   body   { text: string,
 *            start_date: "YYYY-MM-DD", end_date: "YYYY-MM-DD",
 *            today_hint?: string,
 *            athlete_user_id?: uuid }   // coach editing an athlete's plan;
 *                                       // omit to edit the caller's own
 *   200    { resolved: [{ workoutId, day, before, after, op }],
 *            questions: [{ id, question, options: [{label,value}], op }],
 *            notFound: [{ kind, targetHint }],
 *            warnings: string[], unparsed: string[] }
 *   400    { error } — bad body, or the range is empty/too wide
 *   401    { error } — missing/invalid JWT
 *   403    { error } — athlete_user_id given, but the caller doesn't coach them
 *   429    { error } — LLM budget guard declined (see llm-budget.ts)
 *
 * The date range is capped at 21 days — this is a text box for adjusting the
 * plan in front of you, not a query engine, and a wider window makes the
 * model's grounding list unwieldy for no real benefit.
 */

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";
import { getAuthenticatedUser, unauthorizedResponse } from "../_shared/auth.ts";
import { llmBudgetAllows, llmBudgetBlockedResponse } from "../_shared/llm-budget.ts";
import { withSentry } from "../_shared/sentry.ts";
import { parsePlanEdit } from "../_shared/plan-edit-llm.ts";
import { validatePlanEditOps } from "../_shared/plan-edit-validator.ts";
import { planEdits } from "../_shared/plan-edit-resolver.ts";
import { describePatch } from "../_shared/plan-edit-diff.ts";
import type { ScheduledWorkoutRef } from "../_shared/plan-edit-schema.ts";
import type { LibrarySession } from "../_shared/session-library.ts";
import { textForScheduledWorkout } from "../_shared/scheduled-workout-text.ts";
// A real ES import, not a runtime file read — Supabase's deploy bundler
// follows the static import graph and does NOT upload files only referenced
// via `Deno.readTextFile(new URL(...))`. That was the original approach here
// and it deployed successfully while silently leaving session-library.json
// off the uploaded asset list, which would have 404'd on first real request.
import sessionLibraryData from "../_shared/session-library.json" with { type: "json" };

const MAX_RANGE_DAYS = 21;

interface PlanEditBody {
  text?: string;
  start_date?: string;
  end_date?: string;
  today_hint?: string;
  /**
   * A coach editing an ATHLETE's plan rather than their own. When present,
   * the caller must be a coach who owns this athlete — same gate as
   * `athletes/[id]/edit-plan` and `rewrite-block`: either the plan is
   * directly coach-owned, or the athlete holds an active subscription to a
   * plan_template this coach owns. Omit for an athlete adjusting their own
   * plan (the caller's own scheduled_workouts).
   */
  athlete_user_id?: string;
}

interface ScheduledWorkoutRow {
  id: string;
  user_id: string;
  plan_id: string | null;
  date: string;
  day_of_week: number | null;
  week_number: number | null;
  // NOTE: `session` in the live schema is an INTEGER (which session of the
  // day — doubles use 1/2), never a text description. It is not selected
  // here on purpose — see scheduled-workout-text.ts for why, and what the
  // real text source is (workout_data.steps[], with notes/workout_type as
  // fallbacks).
  workout_type: string | null;
  workout_data: unknown;
  notes: string | null;
  is_key_session: boolean | null;
}

export interface PlanEditDeps {
  resolveUser?: (req: Request) => Promise<string | null>;
  buildClient?: () => ReturnType<typeof createClient>;
  now?: () => Date;
  /** Injectable for tests — real calls hit Gemini via parsePlanEdit. */
  parseEdit?: typeof parsePlanEdit;
  /** Injectable for tests — real calls hit the DB via llmBudgetAllows. */
  budgetAllows?: typeof llmBudgetAllows;
}

const sessionLibrary = sessionLibraryData as LibrarySession[];

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

/** 1=Mon..7=Sun, matching shift-day's convention. Used when a row's stored
 *  day_of_week is null. */
function dayOfWeekFor(dateStr: string): number {
  const d = new Date(dateStr + "T00:00:00Z");
  const js = d.getUTCDay(); // 0=Sun..6=Sat
  return js === 0 ? 7 : js;
}

export async function handlePlanEdit(
  req: Request,
  deps: PlanEditDeps = {},
): Promise<Response> {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "POST required" }, 405);

  const userId = await (deps.resolveUser ?? getAuthenticatedUser)(req);
  if (!userId) return unauthorizedResponse(corsHeaders);

  let body: PlanEditBody;
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  const text = body.text?.trim();
  if (!text) return json({ error: "text is required" }, 400);
  if (text.length > 2000) return json({ error: "text is too long" }, 400);

  if (!body.start_date || !DATE_RE.test(body.start_date)) {
    return json({ error: "start_date must be YYYY-MM-DD" }, 400);
  }
  if (!body.end_date || !DATE_RE.test(body.end_date)) {
    return json({ error: "end_date must be YYYY-MM-DD" }, 400);
  }
  if (body.end_date < body.start_date) {
    return json({ error: "end_date must not be before start_date" }, 400);
  }
  const rangeDays = Math.round(
    (new Date(body.end_date + "T00:00:00Z").getTime() - new Date(body.start_date + "T00:00:00Z").getTime())
      / 86_400_000,
  ) + 1;
  if (rangeDays > MAX_RANGE_DAYS) {
    return json({ error: `range too wide — max ${MAX_RANGE_DAYS} days` }, 400);
  }

  const supabase = deps.buildClient
    ? deps.buildClient()
    : createClient(
        Deno.env.get("SUPABASE_URL")!,
        Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      );

  // A coach acting on an athlete's plan must own that athlete — same gate as
  // `athletes/[id]/edit-plan` and `rewrite-block`: directly coach-owned, or
  // the athlete holds an active subscription to a template this coach owns.
  // Checked BEFORE the budget guard so a coach probing someone else's roster
  // doesn't cost a model call either way.
  let targetUserId = userId;
  if (body.athlete_user_id) {
    const { data: coachProfile } = await supabase
      .from("coach_profiles")
      .select("id")
      .eq("user_id", userId)
      .maybeSingle<{ id: string }>();
    if (!coachProfile) return json({ error: "You do not coach this athlete" }, 403);

    const { data: activePlan } = await supabase
      .from("training_plans")
      .select("coach_id")
      .eq("user_id", body.athlete_user_id)
      .eq("status", "active")
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle<{ coach_id: string | null }>();

    let ownsAthlete = activePlan?.coach_id === coachProfile.id;
    if (!ownsAthlete) {
      const { data: sub } = await supabase
        .from("athlete_plan_subscriptions")
        .select("id, plan_template:plan_templates!inner(coach_id)")
        .eq("athlete_user_id", body.athlete_user_id)
        .eq("status", "active")
        .eq("plan_template.coach_id", coachProfile.id)
        .limit(1)
        .maybeSingle();
      ownsAthlete = Boolean(sub);
    }
    if (!ownsAthlete) return json({ error: "You do not coach this athlete" }, 403);
    targetUserId = body.athlete_user_id;
  }

  const budgetAllows = deps.budgetAllows ?? llmBudgetAllows;
  if (!(await budgetAllows("plan_edit", { userId: targetUserId }))) {
    return llmBudgetBlockedResponse("plan_edit", corsHeaders);
  }

  const { data: rows, error: rowsErr } = await supabase
    .from("scheduled_workouts")
    .select("id, user_id, plan_id, date, day_of_week, week_number, workout_type, workout_data, notes, is_key_session")
    .eq("user_id", targetUserId)
    .gte("date", body.start_date)
    .lte("date", body.end_date);
  if (rowsErr) return json({ error: rowsErr.message }, 500);

  const scheduled = (rows ?? []) as ScheduledWorkoutRow[];
  if (scheduled.length === 0) {
    return json({ resolved: [], questions: [], notFound: [], warnings: [], unparsed: [], note: "no scheduled workouts in that range" });
  }

  // Race-week gate, same rule as edit-scheduled-workout: the final 6 days
  // before a plan's end_date. One lookup per distinct plan_id in range.
  const planIds = [...new Set(scheduled.map((r) => r.plan_id).filter((x): x is string => !!x))];
  const raceWindows = new Map<string, { start: string; end: string }>();
  if (planIds.length) {
    const { data: plans } = await supabase
      .from("training_plans")
      .select("id, end_date")
      .in("id", planIds);
    for (const p of (plans ?? []) as Array<{ id: string; end_date: string | null }>) {
      if (!p.end_date) continue;
      const start = new Date(p.end_date + "T00:00:00Z");
      start.setUTCDate(start.getUTCDate() - 6);
      raceWindows.set(p.id, { start: start.toISOString().slice(0, 10), end: p.end_date });
    }
  }

  const now = deps.now ? deps.now() : new Date();
  const todayStr = now.toISOString().slice(0, 10);

  const week: ScheduledWorkoutRef[] = scheduled.map((r) => {
    const win = r.plan_id ? raceWindows.get(r.plan_id) : undefined;
    return {
      id: r.id,
      date: r.date,
      dayOfWeek: r.day_of_week ?? dayOfWeekFor(r.date),
      weekNumber: r.week_number,
      text: textForScheduledWorkout(r),
      workoutType: r.workout_type,
      isKeySession: !!r.is_key_session,
      isRaceWeek: !!win && r.date >= win.start && r.date <= win.end,
      isPast: r.date < todayStr,
    };
  });

  const raw = await (deps.parseEdit ?? parsePlanEdit)(text, week, { todayHint: body.today_hint });

  if (!raw) {
    return json({
      resolved: [], questions: [], notFound: [],
      warnings: ["Couldn't reach the model — try again in a moment."],
      unparsed: [text],
    });
  }

  const validated = validatePlanEditOps(raw.ops, { unparsed: raw.unparsed });
  const plan = planEdits(validated.ops, week, sessionLibrary);

  return json({
    resolved: plan.resolved.map((r) => ({ ...describePatch(r, sessionLibrary), op: r.op })),
    questions: plan.questions,
    notFound: plan.notFound,
    warnings: validated.warnings,
    unparsed: validated.unparsed,
  });
}

Deno.serve(withSentry("plan-edit", (req) => handlePlanEdit(req)));

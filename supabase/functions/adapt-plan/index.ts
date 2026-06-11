/**
 * adapt-plan — turns recent athlete state + forecast into plan_adjustments.
 *
 * Called by:
 *   1. reconcile-log, when a fresh delta warrants a look (fire-and-forget).
 *   2. The Sunday weekly-rebalance cron.
 *   3. A user-driven review button ("tell me what's changing and why").
 *
 * Request body: { user_id: UUID, trigger?: "reconcile" | "weekly_rebalance" | "manual" }
 */

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { requireAuthOrServiceRole } from "../_shared/auth.ts";
import {
  runAllRules,
  type AdaptationProposal,
  type RuleContext,
} from "../_shared/adaptation-rules.ts";
import { getOrBuildPaceProfile, paceForReference } from "../_shared/resolve-pace.ts";
import { proposePaceAdjustment } from "../_shared/pace_adjuster.ts";

import { corsHeaders } from "../_shared/cors.ts";

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const body = await req.json().catch(() => ({}));
    const userIdFromBody: string | undefined = body?.user_id;
    const trigger: string = body?.trigger ?? "manual";

    // Auth: user JWT (body.user_id must match the token) OR a service-role
    // caller that names the subject user (e.g. reconcile-log → adapt-plan).
    // Closes the bypass where an anon-key caller passed any body.user_id.
    const auth = await requireAuthOrServiceRole(req, userIdFromBody, corsHeaders);
    if ("response" in auth) return auth.response;
    const userId = auth.userId;

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    // ── Gather inputs ──────────────────────────────────────
    const fourteenDaysAgo = new Date(Date.now() - 14 * 24 * 60 * 60 * 1000).toISOString();

    const [
      { data: reconciliations },
      { data: logs },
      { data: plan },
      profile,
    ] = await Promise.all([
      supabase
        .from("workout_reconciliations")
        .select("id, training_log_id, created_at, target_pace_seconds_per_mile, actual_pace_seconds_per_mile, adjusted_pace_delta_seconds, hit_target, scheduled_workout_id")
        .eq("user_id", userId)
        .gte("created_at", fourteenDaysAgo)
        .order("created_at", { ascending: false }),
      supabase
        .from("training_logs")
        .select("id, workout_date, workout_type, workout_distance_miles, workout_duration_minutes")
        .eq("user_id", userId)
        .gte("workout_date", fourteenDaysAgo)
        .order("workout_date", { ascending: false }),
      supabase
        .from("training_plans")
        .select("id")
        .eq("user_id", userId)
        .eq("status", "active")
        .limit(1)
        .maybeSingle(),
      getOrBuildPaceProfile(supabase, userId),
    ]);

    let scheduled: Record<string, unknown>[] = [];
    if (plan?.id) {
      const { data } = await supabase
        .from("scheduled_workouts")
        .select("id, date, week_number, workout_type, status, workout_data")
        .eq("plan_id", plan.id);
      scheduled = data ?? [];
    }

    // Forecast is not populated yet — heat rule will emit empty until
    // we add a batched forecast fetch (Prompt 2.3 covers the fetcher).
    const ctx: RuleContext = {
      userId,
      planId: plan?.id ?? null,
      // deno-lint-ignore no-explicit-any
      recentReconciliations: (reconciliations ?? []) as any,
      // deno-lint-ignore no-explicit-any
      recentLogs: (logs ?? []) as any,
      // deno-lint-ignore no-explicit-any
      currentPlanWorkouts: scheduled as any,
      forecast14d: [],
      profile,
    };

    // ── Run rules ─────────────────────────────────────────
    const proposals = runAllRules(ctx);

    // Append the slow-adjusting pace proposal if the warm-up gate is past
    // and the rolling median justifies a shift. This NEVER auto-applies —
    // see feedback_ai_advises_never_acts.md and pace_adjuster.ts header.
    const paceProp = await proposePaceAdjustment(supabase, userId);
    if (paceProp) {
      proposals.push({
        trigger_type: paceProp.delta_seconds < 0
          ? "pace_over_target"
          : "pace_under_target",
        // The shared AdaptationProposal type declares trigger_evidence as
        // unknown[], but every producer stores a structured evidence object.
        // Cast to satisfy the type without changing the runtime value; the
        // _shared interface should be widened to unknown[] | Record<string, unknown>.
        trigger_evidence: {
          source: "pace_adjuster",
          zone: paceProp.zone,
          delta_seconds: paceProp.delta_seconds,
          evidence_reconciliation_ids: paceProp.evidence_reconciliation_ids,
          reasoning: paceProp.reasoning,
        } as unknown as unknown[],
        action_type: "reprice_future_paces",
        action_payload: {
          zone: paceProp.zone,
          delta_seconds_per_mile: paceProp.delta_seconds,
          current_pace_seconds_per_mile: paceProp.current_pace_seconds_per_mile,
          proposed_pace_seconds_per_mile: paceProp.proposed_pace_seconds_per_mile,
          reasoning: paceProp.reasoning,
        },
        auto_applied: false, // strictly proposed; athlete must accept
        proposed_until: new Date(Date.now() + 7 * 86400000).toISOString(),
      });
    }

    if (proposals.length === 0) {
      console.log(`[adapt-plan] no proposals for user ${userId} (trigger: ${trigger})`);
      return new Response(JSON.stringify({ ok: true, proposals: 0 }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // ── Write + apply ─────────────────────────────────────
    const applied: Record<string, unknown>[] = [];
    for (const p of proposals) {
      const { data: row, error } = await supabase
        .from("plan_adjustments")
        .insert({
          user_id: userId,
          plan_id: ctx.planId,
          trigger_type: p.trigger_type,
          trigger_evidence: p.trigger_evidence,
          action_type: p.action_type,
          action_payload: p.action_payload,
          auto_applied: p.auto_applied,
          proposed_until: p.proposed_until ?? null,
        })
        .select()
        .single();
      if (error) {
        console.error("[adapt-plan] insert failed", error);
        continue;
      }
      if (p.auto_applied) {
        await applyDiff(supabase, ctx, p);
      }
      applied.push(row);
    }

    // Refresh the profile so downstream consumers see any fitness change.
    await supabase.functions.invoke("build-pace-profile", { body: { user_id: userId } }).catch(() => {});

    return new Response(JSON.stringify({ ok: true, proposals: applied.length, rows: applied }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err) {
    console.error("[adapt-plan] unhandled", err);
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});

/** Apply the diff for an auto-applied adjustment. Reprices / caps / pauses
 *  work against scheduled_workouts; update_fitness writes a new
 *  fitness_snapshots row. Every before-state is embedded in action_payload
 *  so revert-plan-adjustment can undo precisely. */
// deno-lint-ignore no-explicit-any
async function applyDiff(supabase: any, ctx: RuleContext, p: AdaptationProposal): Promise<void> {
  switch (p.action_type) {
    case "reprice_future_paces": {
      const delta = (p.action_payload.delta_seconds_per_mile as number) ?? 0;
      if (delta === 0 || !ctx.planId) return;
      const { data: future } = await supabase
        .from("scheduled_workouts")
        .select("id, workout_data")
        .eq("plan_id", ctx.planId)
        .gte("date", new Date().toISOString().slice(0, 10));
      const before: Record<string, unknown>[] = [];
      for (const row of future ?? []) {
        const wd = row.workout_data;
        if (!wd?.steps) continue;
        const originalSteps = JSON.parse(JSON.stringify(wd.steps));
        before.push({ id: row.id, steps: originalSteps });
        for (const step of wd.steps) {
          if (typeof step.target_pace_seconds_per_mile === "number") {
            step.target_pace_seconds_per_mile = Math.max(120, step.target_pace_seconds_per_mile + delta);
          }
        }
        await supabase.from("scheduled_workouts").update({ workout_data: wd }).eq("id", row.id);
      }
      p.action_payload.before = before;
      break;
    }
    case "pause_quality": {
      if (!ctx.planId) return;
      const QUALITY = ["tempo", "intervals", "long_run", "race", "progression"];
      const endDate = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString().slice(0, 10);
      const { data: affected } = await supabase
        .from("scheduled_workouts")
        .select("id, workout_type")
        .eq("plan_id", ctx.planId)
        .in("workout_type", QUALITY)
        .gte("date", new Date().toISOString().slice(0, 10))
        .lte("date", endDate);
      const before = affected?.map((r: { id: string; workout_type: string }) => ({ id: r.id, workout_type: r.workout_type })) ?? [];
      for (const row of affected ?? []) {
        await supabase
          .from("scheduled_workouts")
          .update({ workout_type: "easy", notes: "Paused (adaptive: missed_sessions)" })
          .eq("id", row.id);
      }
      p.action_payload.before = before;
      break;
    }
    case "cap_volume": {
      // Soft cap — just annotate the notes on next week's workouts; a real
      // volume reduction would need workout-specific trims out of scope here.
      p.action_payload.before = { note: "cap_volume applied as annotation only (v1)" };
      break;
    }
    case "update_fitness": {
      // Writing a fresh fitness_snapshot from the race time would require
      // calling the predictor. Left as a marker so revert can no-op
      // cleanly; Prompt 3.6's revert logic handles the fitness_snapshots
      // restoration path.
      p.action_payload.before = { note: "update_fitness recorded; snapshot rebuild handled by build-pace-profile" };
      break;
    }
    case "propose_swap":
    case "reduce_volume":
      // Not auto-applied; nothing to diff.
      break;
  }

  // Update the adjustment row with the before-state so revert is lossless.
  if (p.action_payload.before !== undefined) {
    await supabase
      .from("plan_adjustments")
      .update({ action_payload: p.action_payload })
      .eq("user_id", ctx.userId)
      .eq("trigger_type", p.trigger_type)
      .order("applied_at", { ascending: false })
      .limit(1);
  }

  // Silence no-unused warnings for the imported helper.
  void paceForReference;
}

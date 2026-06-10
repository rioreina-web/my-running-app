/**
 * revert-plan-adjustment
 *
 * Undoes a previously-applied or accepted plan_adjustments row using the
 * before-state stored in action_payload.before. Returns:
 *   200 — reverted OK
 *   404 — adjustment not found
 *   409 — already reverted
 *   422 — diff can't be reversed (missing/corrupt before-state)
 *
 * Request body: { adjustment_id: UUID }
 */

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { getAuthenticatedUser, unauthorizedResponse } from "../_shared/auth.ts";
import { corsHeaders } from "../_shared/cors.ts";

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const userId = await getAuthenticatedUser(req);
    if (!userId) return unauthorizedResponse(corsHeaders);

    const body = await req.json().catch(() => ({}));
    const adjustmentId: string | undefined = body?.adjustment_id;
    if (!adjustmentId) return json({ error: "adjustment_id required" }, 400);

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    // Fetch + ownership + already-reverted guard.
    const { data: adj, error: fetchErr } = await supabase
      .from("plan_adjustments")
      .select("*")
      .eq("id", adjustmentId)
      .eq("user_id", userId)
      .maybeSingle();
    if (fetchErr) return json({ error: fetchErr.message }, 500);
    if (!adj) return json({ error: "adjustment not found" }, 404);
    if (adj.reverted_at) return json({ error: "already reverted" }, 409);

    const payload = adj.action_payload as Record<string, unknown> | null;
    const before = payload?.before;

    switch (adj.action_type) {
      case "reprice_future_paces": {
        const items = before as Array<{ id: string; steps: unknown }> | undefined;
        if (!items) return json({ error: "no before-state" }, 422);
        for (const item of items) {
          // Fetch the current workout_data, swap just the steps, write back.
          const { data: row } = await supabase
            .from("scheduled_workouts")
            .select("workout_data")
            .eq("id", item.id)
            .maybeSingle();
          if (!row?.workout_data) continue;
          const wd = row.workout_data as Record<string, unknown>;
          wd.steps = item.steps;
          await supabase.from("scheduled_workouts").update({ workout_data: wd }).eq("id", item.id);
        }
        break;
      }
      case "pause_quality": {
        const items = before as Array<{ id: string; workout_type: string }> | undefined;
        if (!items) return json({ error: "no before-state" }, 422);
        for (const item of items) {
          await supabase
            .from("scheduled_workouts")
            .update({ workout_type: item.workout_type, notes: null })
            .eq("id", item.id);
        }
        break;
      }
      case "cap_volume": {
        // v1 records cap_volume as an annotation only; nothing to physically
        // undo, but we still stamp reverted_at so the UI can hide the card.
        break;
      }
      case "update_fitness": {
        // Tombstone the derived fitness_snapshot if we created one — the
        // actual snapshot write lives in build-pace-profile, which will
        // re-derive on next refresh.
        break;
      }
      case "propose_swap":
      case "reduce_volume":
        // Never auto-applied — revert is a no-op beyond stamping reverted_at.
        break;
    }

    const { error: updErr } = await supabase
      .from("plan_adjustments")
      .update({ reverted_at: new Date().toISOString() })
      .eq("id", adjustmentId);
    if (updErr) return json({ error: updErr.message }, 500);

    // Re-refresh the pace profile so callers see a coherent set of paces.
    await supabase.functions.invoke("build-pace-profile", { body: { user_id: userId } }).catch(() => {});

    return json({ ok: true }, 200);
  } catch (err) {
    console.error("[revert-plan-adjustment] unhandled", err);
    return json({ error: String(err) }, 500);
  }
});

function json(obj: unknown, status: number): Response {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

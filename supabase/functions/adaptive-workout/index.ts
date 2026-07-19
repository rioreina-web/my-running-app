/**
 * adaptive-workout — DEPRECATED (2026-04-17).
 *
 * Replaced by the adaptive-plan loop:
 *   reconcile-log  → workout_reconciliations
 *   adapt-plan     → plan_adjustments (via _shared/adaptation-rules.ts)
 *   revert-plan-adjustment for undo
 *
 * This function now returns 410 Gone on every request. The file is kept as
 * a backstop until 2026-05-17, after which it should be deleted entirely.
 *
 * TODO(delete-after-2026-05-17): remove this file and its config.toml entry.
 */

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

Deno.serve((req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  return new Response(
    JSON.stringify({
      deprecated: true,
      replacement: "adapt-plan",
      sunset: "2026-05-17",
      message:
        "adaptive-workout has been deprecated. Call adapt-plan with { user_id, trigger: 'manual' }. See plan_adjustments + PlanAdjustmentsView for the new surface.",
    }),
    {
      status: 410,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    }
  );
});

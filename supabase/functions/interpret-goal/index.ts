// ============================================================================
// interpret-goal
//
// Reads a runner's goal in their own words (e.g. "Run sub 2:20 at CIM") with
// an LLM and returns a structured interpretation — correct time (2h20m =
// 8400s, NOT 140s), the race distance, the framing ("sub 2:20"), the named
// race (CIM → California International Marathon), and a running-lane scope
// classification. This REPLACES the brittle regex title-parsing that lived in
// athlete-state.ts and the keyword gate in GoalsView.fetchRaceIntel.
//
// Side effect: when the goal names a real race, it triggers `race-intel` with
// the CLEAN canonical race name and links the result to the goal via goal_id
// (server-to-server, service role). That's what finally makes the app look up
// races like CIM instead of skipping them.
//
// Best-effort forward-compat: if the Phase 1 user_goals columns
// (interpretation / target_race_distance / target_time_seconds) exist, the
// interpretation is persisted onto the goal row. If they don't exist yet
// (migration not pushed), the write is skipped without failing the call.
//
// Invocation:
//   POST { goal_text, target_date?, goal_id?, user_id? }   (user JWT)
//   POST { goal_text, ..., user_id }                        (service role)
//
// See outputs/race-goals-build-plan-2026-06-20.md (Phase 2).
// ============================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { GoogleGenerativeAI } from "npm:@google/generative-ai@0.21.0";
import { corsHeaders } from "../_shared/cors.ts";
import { requireAuthOrServiceRole } from "../_shared/auth.ts";
import { enforceFeatureRateLimit, enforceMonthlyCap } from "../_shared/rateLimit.ts";
import { loadPrompt } from "../_shared/prompt-library.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const geminiApiKey = Deno.env.get("GEMINI_API_KEY")!;

const supabase = createClient(supabaseUrl, supabaseServiceKey);
const genAI = new GoogleGenerativeAI(geminiApiKey);

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

/** Tolerant JSON extraction — bare JSON, ```json fences, or prose. */
function parseModelJson(text: string): Record<string, unknown> | null {
  const tryParse = (s: string): Record<string, unknown> | null => {
    try {
      const o = JSON.parse(s);
      return (o && typeof o === "object") ? o as Record<string, unknown> : null;
    } catch {
      return null;
    }
  };
  let r = tryParse(text);
  if (r) return r;
  const fence = text.match(/```(?:json)?\s*([\s\S]*?)```/i);
  if (fence) { r = tryParse(fence[1].trim()); if (r) return r; }
  const a = text.indexOf("{"), b = text.lastIndexOf("}");
  if (a >= 0 && b > a) return tryParse(text.substring(a, b + 1));
  return null;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  let body: Record<string, unknown> = {};
  try { body = await req.json(); } catch { /* allow empty */ }

  const goalText = (body.goal_text ?? "").toString().trim();
  const targetDate = body.target_date ? body.target_date.toString() : undefined;
  const bodyUserId = body.user_id ? body.user_id.toString() : undefined;
  let goalId = body.goal_id ? body.goal_id.toString() : undefined;

  if (!goalText) return jsonResponse({ error: "goal_text is required" }, 400);

  const auth = await requireAuthOrServiceRole(req, bodyUserId, corsHeaders);
  if ("response" in auth) return auth.response;
  const { userId, isServiceRole } = auth;

  // Per-user rate limit before the LLM call. Shares the "race" bucket since a
  // named-race goal fans out to race-intel. Service-role callers bypass.
  const rlBlocked = await enforceFeatureRateLimit(userId, "race", corsHeaders, { isServiceRole });
  if (rlBlocked) return rlBlocked;
  const monthlyCapped = await enforceMonthlyCap(userId, "race", corsHeaders, { isServiceRole });
  if (monthlyCapped) return monthlyCapped;

  // ── Read the goal with the model ──────────────────────────────────────────
  let interp: Record<string, unknown> | null = null;
  try {
    const model = genAI.getGenerativeModel({ model: "gemini-2.5-flash" });
    const prompt = loadPrompt("parse-goal.v1", {}) +
      `\n\n## The athlete's goal (their exact words)\n"${goalText.slice(0, 500)}"` +
      (targetDate ? `\n\n## Target date (for context)\n${targetDate}` : "");
    const result = await model.generateContent([{ text: prompt }]);
    interp = parseModelJson(result.response.text());
  } catch (e) {
    return jsonResponse({ error: `interpretation failed: ${e}` }, 502);
  }
  if (!interp) return jsonResponse({ error: "model returned unparseable output" }, 502);

  const scope = (interp.scope ?? "").toString();
  const namedRace = (interp.named_race ?? null) as Record<string, unknown> | null;
  const primaryTarget = Array.isArray(interp.performance_targets) && interp.performance_targets.length > 0
    ? interp.performance_targets[0] as Record<string, unknown>
    : null;

  // ── Resolve goal_id (for linking race-intel) if the caller didn't pass one ─
  if (!goalId) {
    const { data: g } = await supabase
      .from("user_goals")
      .select("id")
      .eq("user_id", userId)
      .eq("status", "active")
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle();
    if (g?.id) goalId = g.id as string;
  }

  // ── Best-effort persist onto the goal row (forward-compat with Phase 1) ────
  // If the structured columns don't exist yet, this update errors and we skip
  // it — the interpretation is still returned and race-intel still fires.
  let persisted = false;
  if (goalId) {
    try {
      // supabase-js does not throw on failure — it returns { error }. The old
      // try/catch alone meant a failed write (missing column, constraint, RLS)
      // was invisible: the function reported ok while the goal row stayed
      // unstructured, and every analyzer downstream saw an empty goal.
      const { error: persistError } = await supabase
        .from("user_goals")
        .update({
          interpretation: interp,
          target_race_distance: primaryTarget?.race_distance ?? namedRace?.implied_distance ?? null,
          target_time_seconds: primaryTarget?.target_time_seconds ?? null,
        })
        .eq("id", goalId)
        .eq("user_id", userId);
      if (persistError) {
        console.error(
          `interpret-goal: persist failed for goal ${goalId}: ${persistError.message}`,
        );
      } else {
        persisted = true;
      }
    } catch (e) {
      console.error(`interpret-goal: persist threw for goal ${goalId}`, e);
    }
  }

  // ── Fire race-intel for a recognised race, linked by goal_id ──────────────
  let raceIntelTriggered = false;
  const canonical = namedRace?.canonical_name?.toString().trim();
  const isRunning = scope === "running_goal" || scope === "running_constraint";
  if (isRunning && canonical && namedRace?.recognized === true) {
    try {
      const res = await fetch(`${supabaseUrl}/functions/v1/race-intel`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": `Bearer ${supabaseServiceKey}`,
        },
        body: JSON.stringify({
          race_name: canonical,
          race_date: targetDate,
          user_id: userId,
          goal_id: goalId,
        }),
      });
      raceIntelTriggered = res.ok;
    } catch (_e) {
      // Non-fatal — the interpretation is the primary product.
    }
  }

  return jsonResponse({
    ok: true,
    interpretation: interp,
    goal_id: goalId ?? null,
    persisted,
    race_intel_triggered: raceIntelTriggered,
  });
});

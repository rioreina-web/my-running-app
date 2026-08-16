/**
 * _shared/llm-budget.ts — edge-function side of the LLM budget guard.
 *
 * The DB side (migration 20260813180100_llm_call_ledger_and_budget_guard)
 * defines `public.llm_budget_allows(surface, subject, user_id)`: it enforces a
 * global daily call ceiling and a per-subject 24h ceiling (the loop detector),
 * writes one ledger row per permitted call, and returns false — dispatching
 * nothing — when a ceiling is hit. Migration 20260813180200 wired it into the
 * SQL dispatchers (workout_parse, rpe_extract). This module is the SAME guard
 * for edge functions that call Gemini directly, so there is exactly one
 * implementation of "may I spend money" (the SQL function) and every LLM
 * call path answers to it.
 *
 * Usage, at the top of a handler, after auth and BEFORE any model call:
 *
 *   import { llmBudgetAllows, llmBudgetBlockedResponse } from "../_shared/llm-budget.ts";
 *   if (!(await llmBudgetAllows("daily_read", { userId }))) {
 *     return llmBudgetBlockedResponse("daily_read", corsHeaders);
 *   }
 *
 * Surface names are free text but keep them stable and grep-able — they key
 * the per-subject loop detector and the llm_spend_today report. Existing:
 * workout_parse, rpe_extract (SQL dispatchers); daily_read, coach_insight,
 * voice_memo (edge, wired 2026-08-13).
 *
 * FAILURE POSTURE. If the guard RPC itself errors (DB unreachable, function
 * missing before the migration is pushed), we log loudly and ALLOW the call.
 * Rationale: the guard's own infrastructure failing is not a spend-runaway
 * signal, and a runaway loop gets real `false` answers, not errors. The
 * fail-closed layer for total-blindness scenarios is the Google Cloud
 * billing cap (docs/deploy/llm-cost-controls.md Step 1).
 *
 * NOTE the RPC is EXECUTE-granted to service_role only (deliberately — a
 * client that can call the guard can drain the day's budget), so this module
 * always uses a service-role client regardless of the caller's auth mode.
 */

import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

let _admin: SupabaseClient | null = null;

function adminClient(): SupabaseClient {
  if (_admin) return _admin;
  _admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
  return _admin;
}

export interface LlmBudgetOpts {
  /** The row this call is ABOUT (usually a training_logs UUID). Enables the
   * per-subject loop detector. Omit for calls not tied to one row. */
  subjectId?: string | null;
  /** The athlete the call is for — recorded in the ledger for attribution. */
  userId?: string | null;
}

/**
 * Ask the DB guard whether this LLM call may proceed. Returns true (and the
 * call is recorded in llm_call_ledger) or false (spend nothing, return a
 * blocked response). See module header for the failure posture.
 */
export async function llmBudgetAllows(
  surface: string,
  opts: LlmBudgetOpts = {},
): Promise<boolean> {
  try {
    const { data, error } = await adminClient().rpc("llm_budget_allows", {
      _surface: surface,
      _subject: opts.subjectId ?? null,
      _user_id: opts.userId ?? null,
    });
    if (error) {
      console.error(
        `[llm-budget] guard RPC errored for ${surface} — ALLOWING (fail-open): ${error.message}`,
      );
      return true;
    }
    return data === true;
  } catch (err) {
    console.error(
      `[llm-budget] guard threw for ${surface} — ALLOWING (fail-open):`,
      err,
    );
    return true;
  }
}

/**
 * The standard response when the guard says no. 429 with Retry-After set to
 * the next UTC midnight (when the daily ceiling resets). Job-queue callers
 * can ignore the body — their jobs are durable and drain after reset.
 */
export function llmBudgetBlockedResponse(
  surface: string,
  corsHeaders: Record<string, string>,
): Response {
  const reset = new Date();
  reset.setUTCHours(24, 0, 0, 0);
  const retryAfterSeconds = Math.max(
    60,
    Math.ceil((reset.getTime() - Date.now()) / 1000),
  );
  return new Response(
    JSON.stringify({
      error: "LLM budget ceiling reached",
      surface,
      detail:
        "The app-wide daily AI budget is spent. This protects against cost runaways; the ceiling resets at midnight UTC.",
      resetAt: reset.toISOString(),
    }),
    {
      status: 429,
      headers: {
        ...corsHeaders,
        "Content-Type": "application/json",
        "Retry-After": String(retryAfterSeconds),
      },
    },
  );
}

/**
 * Best-effort token report-back: fills input/output tokens on the most recent
 * ledger row for (surface, subject) so llm_spend_today shows real cost, not
 * just call counts. Never throws.
 */
export async function reportLlmUsage(
  surface: string,
  opts: LlmBudgetOpts & {
    model?: string;
    inputTokens?: number;
    outputTokens?: number;
  },
): Promise<void> {
  try {
    // Find the ledger row this call wrote via llm_budget_allows.
    let q = adminClient()
      .from("llm_call_ledger")
      .select("id")
      .eq("surface", surface)
      .order("occurred_at", { ascending: false })
      .limit(1);
    if (opts.subjectId) q = q.eq("subject_id", opts.subjectId);
    const { data, error } = await q.maybeSingle();
    if (error || !data) return;
    await adminClient()
      .from("llm_call_ledger")
      .update({
        model: opts.model ?? null,
        input_tokens: opts.inputTokens ?? null,
        output_tokens: opts.outputTokens ?? null,
      })
      .eq("id", data.id);
  } catch (err) {
    console.warn(`[llm-budget] usage report failed for ${surface}:`, err);
  }
}

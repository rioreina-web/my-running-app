// ============================================================================
// extract-rpe
//
// Extracts a felt RPE (1–10), a short pull-quote, and a few effort tags from a
// training log's voice-memo transcript, and writes them to the RPE columns
// added in migration 20260611180000_add_rpe_to_training_logs.sql.
//
// Backs the Training tab's "Effort · Felt vs Planned" section
// (training-tab-spec.md §8). The model is instructed to return felt_rpe = null
// when the transcript doesn't actually convey effort — the UI then renders
// nothing rather than a fabricated number (spec core-rule: never fake data).
//
// Invocation (any of):
//   • Client, right after a memo finishes processing:
//       POST { log_id }                       (user JWT)
//   • Service-role / trigger / backfill:
//       POST { log_id, user_id }              (service-role key)
//   • Supabase DB webhook on training_logs UPDATE of cleaned_notes:
//       POST { type, record: { id, user_id, cleaned_notes, ... } }
//
// Idempotent: re-running overwrites felt_rpe/pull_quote/tags and bumps
// rpe_extracted_at. `planned_rpe` is intentionally left to the client's
// session-type defaults until plan-side prescription is wired.
// ============================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  isProviderExhausted,
  PROVIDER_EXHAUSTED_MARKER,
  PROVIDER_EXHAUSTED_STATUS,
} from "../_shared/provider-errors.ts";
import { GoogleGenerativeAI } from "npm:@google/generative-ai@0.21.0";
import { corsHeaders } from "../_shared/cors.ts";
import { requireAuthOrServiceRole } from "../_shared/auth.ts";
import { enforceFeatureRateLimit, enforceMonthlyCap } from "../_shared/rateLimit.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const geminiApiKey = Deno.env.get("GEMINI_API_KEY")!;

const supabase = createClient(supabaseUrl, supabaseServiceKey);
const genAI = new GoogleGenerativeAI(geminiApiKey);

interface ExtractResult {
  felt_rpe: number | null;
  pull_quote: string | null;
  tags: string[];
}

/**
 * True when the token is a Supabase service-role JWT (by claim). Signature is
 * NOT checked here — the gateway already did that (verify_jwt = true). Mirrors
 * the helper in drain-coach-insight-jobs / drain-coachable-moment-jobs.
 */
function isServiceRoleJWT(token: string): boolean {
  try {
    const seg = token.split(".")[1];
    if (!seg) return false;
    const b64 = seg.replace(/-/g, "+").replace(/_/g, "/")
      .padEnd(Math.ceil(seg.length / 4) * 4, "=");
    const payload = JSON.parse(atob(b64)) as { role?: string; exp?: number };
    if (payload.role !== "service_role") return false;
    if (typeof payload.exp === "number" && payload.exp * 1000 < Date.now()) return false;
    return true;
  } catch {
    return false;
  }
}

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

/** Tolerant JSON extraction — handles bare JSON, ```json fences, or prose. */
function parseModelJson(text: string): ExtractResult | null {
  const tryParse = (s: string): ExtractResult | null => {
    try {
      const o = JSON.parse(s);
      return {
        felt_rpe: typeof o.felt_rpe === "number" ? Math.round(o.felt_rpe) : null,
        pull_quote: typeof o.pull_quote === "string" && o.pull_quote.trim() ? o.pull_quote.trim() : null,
        tags: Array.isArray(o.tags) ? o.tags.filter((t: unknown) => typeof t === "string").slice(0, 4) : [],
      };
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

const PROMPT = `You read a runner's post-run voice memo (already transcribed) and
estimate how HARD the session felt — their rate of perceived exertion (RPE) on a
1–10 scale, where 1 = barely moving and 10 = maximal, all-out.

Rules:
- Base RPE only on what the runner actually says about effort, breathing, legs,
  fatigue, or how the pace felt. Do NOT infer effort from distance or pace alone.
- If the memo does not convey how hard it felt, return felt_rpe = null. Never guess.
- pull_quote: one short verbatim sentence (≤ 140 chars) that best captures how the
  run felt, copied from the transcript. null if nothing fitting.
- tags: 0–3 short lowercase words describing the session feel (e.g. "tired",
  "humid", "strong", "flat", "easy"). Empty array if none clear.

Return ONLY JSON: {"felt_rpe": <int 1-10 or null>, "pull_quote": <string or null>, "tags": [<string>...]}

Transcript:
"""
{{TRANSCRIPT}}
"""`;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  let body: Record<string, unknown> = {};
  try { body = await req.json(); } catch { /* allow empty */ }

  // Support both direct calls and DB-webhook payloads.
  const record = (body.record ?? {}) as Record<string, unknown>;
  const logId = (body.log_id ?? record.id) as string | undefined;
  const bodyUserId = (body.user_id ?? record.user_id) as string | undefined;

  if (!logId) return jsonResponse({ error: "log_id is required" }, 400);

  // ── Service-role path: decode the role claim instead of exact-matching
  // SUPABASE_SERVICE_ROLE_KEY. The gateway has already verified the JWT
  // signature (verify_jwt = true), so reading the claim is safe here — and it
  // is robust to service-key / Vault drift, which is exactly what 401'd every
  // dispatch_rpe_extraction call on 2026-08-07: the Vault copy of the key (the
  // one the cron sends) no longer string-equals the function-env copy, even
  // though both are validly signed. Same fix the drain-* functions adopted on
  // 2026-06-11 for the same drift. Do NOT copy this pattern into a function
  // with verify_jwt = false — there the claim would be unverified.
  const authHeader = req.headers.get("Authorization") ?? "";
  const bearer = authHeader.startsWith("Bearer ")
    ? authHeader.slice("Bearer ".length).trim()
    : "";
  let userId: string;
  let isServiceRole: boolean;
  if (bearer && isServiceRoleJWT(bearer)) {
    if (!bodyUserId) {
      return jsonResponse({ error: "Service-role caller must specify user_id in body" }, 400);
    }
    userId = bodyUserId;
    isServiceRole = true;
  } else {
    // User-JWT path (and its user_id-mismatch check) unchanged.
    const auth = await requireAuthOrServiceRole(req, bodyUserId, corsHeaders);
    if ("response" in auth) return auth.response;
    ({ userId, isServiceRole } = auth);
  }

  // Per-user rate limit before the LLM call. Service-role callers (DB webhook,
  // trigger, backfill) bypass via isServiceRole; the user-JWT path pays it.
  // Shares the voice_memo bucket — RPE is read from the same voice transcript.
  const rlBlocked = await enforceFeatureRateLimit(userId, "voice_memo", corsHeaders, { isServiceRole });
  if (rlBlocked) return rlBlocked;
  const monthlyCapped = await enforceMonthlyCap(userId, "voice_memo", corsHeaders, { isServiceRole });
  if (monthlyCapped) return monthlyCapped;

  // Load the log (RLS bypassed by service client; scope by user_id for safety).
  const { data: log, error: loadErr } = await supabase
    .from("training_logs")
    .select("id, user_id, cleaned_notes, notes, transcript_url, felt_rpe, rpe_source")
    .eq("id", logId)
    .eq("user_id", userId)
    .single();

  if (loadErr || !log) return jsonResponse({ error: "log not found" }, 404);

  // Prefer the LLM-cleaned transcript; fall back to raw notes.
  const transcript = (log.cleaned_notes || log.notes || "").toString().trim();
  if (!transcript) {
    // Nothing to read — leave RPE NULL so the UI renders nothing.
    return jsonResponse({ skipped: "no transcript", felt_rpe: null });
  }

  /** Give back the attempt the dispatcher spent, leaving the row claimable.
   *  Best-effort: failing to do the bookkeeping must not mask the outage.
   *  Read-then-write is safe — the claim predicate's 10-minute
   *  `last_attempt_at` floor means no concurrent writer for this row. */
  async function releaseRpeAttempt(trainingLogId: string): Promise<void> {
    try {
      const { data } = await supabase
        .from("rpe_extraction_jobs")
        .select("attempts")
        .eq("training_log_id", trainingLogId)
        .single();
      const current = (data?.attempts as number | undefined) ?? 0;
      await supabase
        .from("rpe_extraction_jobs")
        .update({ attempts: Math.max(0, current - 1) })
        .eq("training_log_id", trainingLogId);
      console.warn(
        `[extract-rpe] provider unavailable for ${trainingLogId}; ` +
          `attempt not counted (attempts ${current} -> ${Math.max(0, current - 1)})`,
      );
    } catch {
      // Swallowed deliberately — see above.
    }
  }

  let extracted: ExtractResult | null = null;
  try {
    const model = genAI.getGenerativeModel({ model: "gemini-2.5-flash" });
    const result = await model.generateContent([
      { text: PROMPT.replace("{{TRANSCRIPT}}", transcript.slice(0, 4000)) },
    ]);
    extracted = parseModelJson(result.response.text());
  } catch (e) {
    // A provider billing/quota outage must not spend this job's retry budget.
    // The dispatcher increments `attempts` at dispatch time and never sees this
    // response, so an outage silently ratchets every queued row to attempts = 3
    // — permanently unclaimable, since the claim predicate is `attempts < 3`.
    // Hand the attempt back so the queue drains itself once the provider is
    // funded. Same fix as parse-workout-structure; see _shared/provider-errors.ts.
    if (isProviderExhausted(e)) {
      await releaseRpeAttempt(logId);
      return jsonResponse(
        { error: "extraction provider unavailable", reason: PROVIDER_EXHAUSTED_MARKER },
        PROVIDER_EXHAUSTED_STATUS,
      );
    }
    return jsonResponse({ error: `extraction failed: ${e}` }, 502);
  }

  if (!extracted) return jsonResponse({ error: "model returned unparseable output" }, 502);

  // Clamp to the DB check constraint.
  const felt = extracted.felt_rpe == null
    ? null
    : Math.min(10, Math.max(1, extracted.felt_rpe));

  // ── Athlete override wins, permanently ──────────────────────────────────
  // This function is idempotent and fires from four places (client post-memo,
  // service-role backfill, the `dispatch_rpe_extraction` cron, and the DB
  // webhook on cleaned_notes UPDATE). Without this guard, an RPE the athlete
  // set on the workout-detail slider would be silently overwritten by whichever
  // one ran next — the athlete would correct a number and watch it revert.
  //
  // Only `felt_rpe` is frozen. `rpe_pull_quote` and `rpe_tags` keep refreshing,
  // because the quote is derived from the transcript rather than asserted by
  // the athlete, and it is the part that actually renders today.
  //
  // Product rule this enforces: the model proposes an RPE, the athlete disposes.
  const athleteOwnsRpe = log.rpe_source === "athlete";

  const updatePayload: Record<string, unknown> = {
    rpe_pull_quote: extracted.pull_quote,
    rpe_tags: extracted.tags,
    rpe_extracted_at: new Date().toISOString(),
  };

  if (!athleteOwnsRpe) {
    updatePayload.felt_rpe = felt;
    // Leave provenance NULL when the model abstained, so "unset" stays
    // distinguishable from "the model looked and found no effort signal".
    updatePayload.rpe_source = felt == null ? null : "llm";
  }

  const { error: updErr } = await supabase
    .from("training_logs")
    .update(updatePayload)
    .eq("id", logId)
    .eq("user_id", userId);

  if (updErr) return jsonResponse({ error: `update failed: ${updErr.message}` }, 500);

  return jsonResponse({
    felt_rpe: athleteOwnsRpe ? log.felt_rpe : felt,
    rpe_source: athleteOwnsRpe ? "athlete" : (felt == null ? null : "llm"),
    athlete_override: athleteOwnsRpe,
    pull_quote: extracted.pull_quote,
    tags: extracted.tags,
  });
});

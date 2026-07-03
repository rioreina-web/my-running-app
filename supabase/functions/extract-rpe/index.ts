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
import { GoogleGenerativeAI } from "npm:@google/generative-ai@0.21.0";
import { corsHeaders } from "../_shared/cors.ts";
import { requireAuthOrServiceRole } from "../_shared/auth.ts";

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

  const auth = await requireAuthOrServiceRole(req, bodyUserId, corsHeaders);
  if ("response" in auth) return auth.response;
  const { userId } = auth;

  // Load the log (RLS bypassed by service client; scope by user_id for safety).
  const { data: log, error: loadErr } = await supabase
    .from("training_logs")
    .select("id, user_id, cleaned_notes, notes, transcript_url")
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

  let extracted: ExtractResult | null = null;
  try {
    const model = genAI.getGenerativeModel({ model: "gemini-2.5-flash" });
    const result = await model.generateContent([
      { text: PROMPT.replace("{{TRANSCRIPT}}", transcript.slice(0, 4000)) },
    ]);
    extracted = parseModelJson(result.response.text());
  } catch (e) {
    return jsonResponse({ error: `extraction failed: ${e}` }, 502);
  }

  if (!extracted) return jsonResponse({ error: "model returned unparseable output" }, 502);

  // Clamp to the DB check constraint.
  const felt = extracted.felt_rpe == null
    ? null
    : Math.min(10, Math.max(1, extracted.felt_rpe));

  const { error: updErr } = await supabase
    .from("training_logs")
    .update({
      felt_rpe: felt,
      rpe_pull_quote: extracted.pull_quote,
      rpe_tags: extracted.tags,
      rpe_extracted_at: new Date().toISOString(),
    })
    .eq("id", logId)
    .eq("user_id", userId);

  if (updErr) return jsonResponse({ error: `update failed: ${updErr.message}` }, 500);

  return jsonResponse({ felt_rpe: felt, pull_quote: extracted.pull_quote, tags: extracted.tags });
});

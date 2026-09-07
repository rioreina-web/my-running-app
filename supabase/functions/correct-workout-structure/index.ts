/**
 * correct-workout-structure — athlete-facing structure correction.
 *
 * The auto-parser (parse-workout-structure) segments a workout from the GPS
 * stream by where the athlete slowed down. When it mis-segments — a warmup and
 * tempo merged into one long block, two interval sets collapsed into one — the
 * athlete fixes the rep breakdown by hand. This function persists that
 * correction.
 *
 * "AI advises, never acts": the auto-parse is a suggestion; the athlete's
 * correction is the verdict. Once corrected, parse-workout-structure will not
 * overwrite it (it checks `parsed_structure.edited_by_user`) until the athlete
 * explicitly restores the auto-detected version.
 *
 * POST body (modes):
 *   save    — { mode:"save", training_log_id, override:{ blocks[], intent_pattern?, type? } }
 *             validate + normalize + write parsed_structure (edited_by_user=true).
 *   restore — { mode:"restore", training_log_id }
 *             discard the correction and re-derive from the stream (force re-parse).
 *
 * Auth: user JWT or service role. User-JWT callers may only touch their own row.
 */

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { GoogleGenerativeAI } from "https://esm.sh/@google/generative-ai@0.24.0";
import { corsHeaders } from "../_shared/cors.ts";
import { requireAuthOrServiceRole } from "../_shared/auth.ts";
import { enforceFeatureRateLimit, enforceMonthlyCap } from "../_shared/rateLimit.ts";
import { normalizeOverride } from "../_shared/structureOverride.ts";
import { boutsFromLaps, workBoutCount, type BoutOrRecovery, type LapInput } from "../_shared/shared/workBouts.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  let body: Record<string, unknown>;
  try {
    body = (await req.json()) as Record<string, unknown>;
  } catch {
    return json({ error: "invalid JSON body" }, 400);
  }

  const trainingLogId = typeof body.training_log_id === "string" ? body.training_log_id : "";
  if (!trainingLogId) return json({ error: "training_log_id required" }, 400);

  const bodyUserId = typeof body.user_id === "string" ? body.user_id : undefined;
  const auth = await requireAuthOrServiceRole(req, bodyUserId, corsHeaders);
  if ("response" in auth) return auth.response;
  const { userId, isServiceRole } = auth;

  // Caught by the LLM coverage sweep (2026-07-15): this Gemini caller shipped
  // auth-gated but with NO per-user rate limit. Shares the "parse" bucket —
  // it's the manual structure-correction parser.
  const rlBlocked = await enforceFeatureRateLimit(userId, "parse", corsHeaders, { isServiceRole });
  if (rlBlocked) return rlBlocked;
  const monthlyCapped = await enforceMonthlyCap(userId, "parse", corsHeaders, { isServiceRole });
  if (monthlyCapped) return monthlyCapped;

  const supabase = createClient(supabaseUrl, supabaseServiceKey);

  // Load the row + its current structure (the base a save merges into). 404
  // (not 403) so a caller can't probe the existence of someone else's row.
  const { data: row, error: fetchErr } = await supabase
    .from("training_logs")
    .select("id, user_id, parsed_structure, external_streams")
    .eq("id", trainingLogId)
    .maybeSingle();
  if (fetchErr || !row) return json({ error: "Not found" }, 404);
  if (!isServiceRole && (row as { user_id?: string }).user_id !== userId) {
    return json({ error: "Not found" }, 404);
  }
  const ownerId = (row as { user_id?: string }).user_id ?? userId;

  const mode = typeof body.mode === "string" ? body.mode : "save";

  // ── restore: discard the correction, re-derive from the stream ──
  if (mode === "restore") {
    // Clear the edit so the parser's guard won't short-circuit, then force a
    // fresh parse from the GPS stream.
    const { error: clearErr } = await supabase
      .from("training_logs")
      .update({ parsed_structure: null })
      .eq("id", trainingLogId);
    if (clearErr) return json({ error: "Could not restore." }, 500);

    try {
      const r = await fetch(`${supabaseUrl}/functions/v1/parse-workout-structure`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${supabaseServiceKey}`,
          apikey: supabaseServiceKey,
        },
        body: JSON.stringify({ training_log_id: trainingLogId, user_id: ownerId, force: true }),
      });
      const parsed = await r.json().catch(() => null);
      if (!r.ok) return json({ error: "Re-parse failed.", detail: parsed }, 502);
      return json({ success: true, mode: "restore", parsed: parsed?.parsed ?? null }, 200);
    } catch (e) {
      return json({ error: `Re-parse request failed: ${e instanceof Error ? e.message : String(e)}` }, 502);
    }
  }

  // ── describe: Gemini reconciles a plain-language description with the GPS
  //    segments and returns a PROPOSED structure (no write). The athlete
  //    reviews it in the editor and then calls "save". ──
  if (mode === "describe") {
    const description = typeof body.description === "string" ? body.description.trim() : "";
    if (!description) return json({ error: "Describe the workout first." }, 400);

    const geminiKey = Deno.env.get("GEMINI_API_KEY");
    if (!geminiKey) return json({ error: "AI is unavailable right now." }, 500);

    // The athlete's watch laps ARE the workout — reconcile the description against
    // the geometry rebuilt from those laps, NOT the on-screen bouts the client
    // sent (which may reflect a stale mis-parse and is exactly what we're trying
    // to fix). boutsFromLaps merges consecutive same-effort laps, so this is the
    // athlete's real structure, not re-invented GPS splits. Fall back to the
    // client-sent bouts only when the row has no usable laps.
    const streamsBundle = row.external_streams as { streams?: unknown; laps?: unknown } | null;
    const streams = (streamsBundle?.streams && typeof streamsBundle.streams === "object")
      ? streamsBundle.streams as Record<string, number[]>
      : undefined;
    const rawLaps = Array.isArray(streamsBundle?.laps) ? (streamsBundle!.laps as LapInput[]) : [];
    const lapSegments = rawLaps.length ? boutsFromLaps(rawLaps, streams).segments : [];

    const bouts: Array<Record<string, unknown>> = workBoutCount(lapSegments) >= 1
      ? lapSegments.map((s: BoutOrRecovery) =>
          s.kind === "work"
            ? { distance_meters: s.distance_m, duration_s: s.duration_s, is_rest: false, avg_pace_per_mile: s.avg_pace_per_mile }
            : { distance_meters: s.distance_m, duration_s: s.duration_s, is_rest: true, avg_pace_per_mile: null })
      : (Array.isArray(body.bouts) ? body.bouts as Array<Record<string, unknown>> : []);
    const boutsText = bouts.length
      ? bouts.map((o, i) => {
        const m = Math.round(Number(o.distance_meters ?? 0));
        const s = Math.round(Number(o.duration_s ?? o.moving_time_seconds ?? 0));
        const rest = o.is_rest === true;
        const pace = (o.avg_pace_per_mile ?? o.avg_pace_sec_per_mile) ?? null;
        return `${i + 1}. ${rest ? "REST" : "WORK"} ${m}m in ${s}s${pace ? ` (~${pace})` : ""}`;
      }).join("\n")
      : "(no GPS segments provided)";

    const prompt =
`You reconstruct a running workout's structure from the athlete's own description, mapped onto the GPS segments their watch recorded.

The athlete says the workout was:
"${description}"

GPS segments the watch recorded (WORK = ran hard, REST = recovery):
${boutsText}

Rules:
- The athlete's description is the SOURCE OF TRUTH for structure: how many reps, the warmup, tempo, recoveries, and rep distances.
- Use the GPS segments for the actual distances, durations and paces. If the description has MORE reps than the GPS shows (the watch missed a recovery), split the relevant WORK segment to match, dividing its distance and time proportionally.
- Every segment is its OWN block. A jog recovery is its own block with its own pace — never a rest tacked onto a rep.
- role MUST be exactly one of: warmup, work_rep, recovery, cooldown.
- distance_miles = meters / 1609.34 (number). duration_s in seconds (number). avg_pace_per_mile as "M:SS" (use null for a standing rest).

Output STRICT JSON only, no markdown:
{
  "intent_pattern": "<short summary, e.g. '3k tempo + 3 × (1k @ 10K, 600m @ 5K)'>",
  "type": "interval" | "tempo" | "easy" | "long_run" | "progression" | "race" | null,
  "blocks": [ { "role": "...", "distance_miles": 0.0, "duration_s": 0, "avg_pace_per_mile": "M:SS" } ]
}`;

    let parsed: unknown;
    try {
      const genAI = new GoogleGenerativeAI(geminiKey);
      const model = genAI.getGenerativeModel({
        model: "gemini-2.5-flash",
        // gemini-2.5-flash spends "thinking" tokens from maxOutputTokens by
        // default; without a cap it can burn the whole budget thinking and
        // truncate the JSON (→ parse failure / ~20s 502). Bound the thinking
        // and give the JSON room — mirrors parse-workout-structure.
        generationConfig: {
          temperature: 0.2,
          responseMimeType: "application/json",
          maxOutputTokens: 8000,
          thinkingConfig: { thinkingBudget: 512 },
        } as Record<string, unknown>,
      });
      const res = await model.generateContent(prompt);
      parsed = JSON.parse(res.response.text());
    } catch (e) {
      console.error("[correct-workout-structure] describe AI failed:", e);
      return json({ error: "The AI couldn't read that — try rephrasing the workout." }, 502);
    }

    let proposal;
    try {
      proposal = normalizeOverride(parsed, row.parsed_structure);
    } catch (e) {
      return json({ error: e instanceof Error ? e.message : "AI produced an invalid structure." }, 502);
    }
    // No DB write — the client shows this for review, then calls mode:"save".
    return json({ success: true, mode: "describe", proposal }, 200);
  }

  // ── save: validate + normalize + persist the correction ──
  if (mode === "save") {
    let normalized;
    try {
      normalized = normalizeOverride(body.override, row.parsed_structure);
    } catch (e) {
      return json({ error: e instanceof Error ? e.message : "invalid override" }, 400);
    }

    // Save the correction AND null the cached coach_insight: the stored AI
    // analysis was written against the WRONG structure, so it must not persist.
    // It regenerates on demand the next time the workout is opened. The
    // athlete_state-invalidation trigger fires on this update too → load math
    // (volume/ACWR/quality classification) rebuilds against the corrected reps.
    // The athlete re-reads the workout → charts, splits and paces all recompute
    // from the new parsed_structure (the view's load() re-derives them).
    const { error: updateErr } = await supabase
      .from("training_logs")
      .update({ parsed_structure: normalized, coach_insight: null })
      .eq("id", trainingLogId);
    if (updateErr) {
      console.error("[correct-workout-structure] update failed:", updateErr.message);
      return json({ error: "Could not save correction." }, 500);
    }
    return json({ success: true, mode: "save", parsed: normalized }, 200);
  }

  return json({ error: `Unknown mode "${mode}". Use describe | save | restore.` }, 400);
});

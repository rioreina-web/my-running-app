// resolve-niggle — the manual "mark this niggle as better now" endpoint.
//
// The explicit-tap half of niggle resolution (the other half is the voice
// path in process-training-memo, which reads the LLM's resolved_niggles).
// The iOS "mark resolved" button POSTs { body_area, side } here; we record
// an athlete-owned all-clear watermark in `niggle_resolutions`. Recurrence
// (athlete-state) then drops that niggle from active analysis until a new
// mention lands after this date.
//
// Detection-not-diagnosis holds: body_area must be in the CLOSED vocabulary
// (rejected otherwise); side is left/right/null. No interpretation, no
// medical language — just "the athlete says this is fine now."
//
// Auth: the athlete acts on their OWN data. requireAuthOrServiceRole proves
// the JWT matches the body user_id; the row is written under the verified
// user. No client INSERT policy on the table (writes are mediated here),
// mirroring the body_mentions convention.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";
import { requireAuthOrServiceRole } from "../_shared/auth.ts";
import { isKnownBodyArea } from "../_shared/bodyVocabulary.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const supabase = createClient(supabaseUrl, supabaseServiceKey);

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  let payload: { user_id?: string; body_area?: string; side?: string | null };
  try {
    payload = await req.json();
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  const auth = await requireAuthOrServiceRole(req, payload.user_id, corsHeaders);
  if ("response" in auth) return auth.response;
  const userId = auth.userId;

  // Validate body_area against the closed vocabulary.
  const bodyArea = typeof payload.body_area === "string" ? payload.body_area.trim().toLowerCase() : "";
  if (!isKnownBodyArea(bodyArea)) {
    return json({ error: `Unknown body_area "${payload.body_area}". Must be a canonical niggle area.` }, 400);
  }

  // Normalize side: left | right | null. Anything else → null (unspecified).
  const rawSide = typeof payload.side === "string" ? payload.side.trim().toLowerCase() : null;
  const side = rawSide === "left" || rawSide === "right" ? rawSide : null;

  const resolvedAt = new Date().toISOString().slice(0, 10);

  const { error } = await supabase.from("niggle_resolutions").insert({
    user_id: userId,
    training_log_id: null, // manual tap, not tied to a specific memo
    body_area: bodyArea,
    side,
    resolved_at: resolvedAt,
    source: "manual",
    verbatim_quote: null,
  });
  if (error) {
    console.error(`[resolve-niggle] insert failed: ${error.message}`);
    return json({ error: "Could not record resolution. Please try again." }, 500);
  }

  console.log(`[resolve-niggle] ${userId} resolved ${side ? side + " " : ""}${bodyArea} (${resolvedAt})`);
  return json({ success: true, body_area: bodyArea, side, resolved_at: resolvedAt }, 200);
});

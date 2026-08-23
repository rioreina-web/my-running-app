/**
 * get-pace-zones Edge Function
 *
 * THE single endpoint every consumer (iOS PaceChartView, TrainingPlanView,
 * coach portal, etc.) calls for an athlete's pace zones. Wraps
 * fetchAndComputePaceZones — there is no other place that does pace math.
 *
 * Request:
 *   GET  /get-pace-zones                  (auth via JWT, computes for caller)
 *   POST /get-pace-zones { user_id: UUID } (service-role cross-call)
 *
 * Response 200:
 *   PaceZones JSON — see _shared/pace-engine.ts for the shape.
 *
 * Auth: verify_jwt = true. Service-role callers may pass user_id in body
 * to compute for another user (used by coach-portal endpoints).
 *
 * Why an edge function and not direct DB access from iOS:
 *   The engine reads four tables (profile, snapshot, plan, recent logs).
 *   Doing that on-device leaks query patterns into the client and means
 *   every change to the engine requires an iOS release. Wrapping it as
 *   an edge function keeps the engine server-side and lets iOS treat it
 *   as a pure data fetch.
 */

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { requireAuthOrServiceRole } from "../_shared/auth.ts";
import { fetchAndComputePaceZones } from "../_shared/pace-engine.ts";

import { corsHeaders } from "../_shared/cors.ts";
const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  // "No user JWT present" was previously treated as "this must be the
  // service-role cross-call", and the body's user_id was trusted on that
  // basis. The anon key presents no user claim either, and it is public —
  // so that branch let anyone read any athlete's pace zones.
  //
  // requireAuthOrServiceRole makes the distinction on the token itself:
  // a real user JWT computes for its own subject (a body user_id that
  // disagrees is a 403), and only the actual service-role key may name a
  // different subject. iOS calls this with a JWT and an empty body.
  let payloadUserId: string | undefined;
  if (req.method === "POST") {
    const body = await req.json().catch(() => ({}));
    const candidate: unknown = body?.user_id;
    if (typeof candidate === "string" && UUID_RE.test(candidate)) {
      payloadUserId = candidate;
    }
  }

  const auth = await requireAuthOrServiceRole(req, payloadUserId, corsHeaders);
  if ("response" in auth) return auth.response;
  const targetUserId = auth.userId;

  try {
    const supabase = createClient(supabaseUrl, serviceKey);
    const zones = await fetchAndComputePaceZones(supabase, targetUserId);
    return new Response(JSON.stringify(zones), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err) {
    console.error("get-pace-zones error:", err);
    return new Response(
      JSON.stringify({ error: "Failed to compute pace zones" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }
});

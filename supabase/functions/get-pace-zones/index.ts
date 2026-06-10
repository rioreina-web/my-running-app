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
import { getAuthenticatedUser, unauthorizedResponse } from "../_shared/auth.ts";
import { fetchAndComputePaceZones } from "../_shared/pace-engine.ts";

import { corsHeaders } from "../_shared/cors.ts";
const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  let authedUserId = await getAuthenticatedUser(req);
  let targetUserId = authedUserId;

  // Service-role cross-call: POST { user_id } overrides the target.
  if (req.method === "POST") {
    const body = await req.json().catch(() => ({}));
    const payloadUserId: string | undefined = body?.user_id;
    if (payloadUserId && UUID_RE.test(payloadUserId)) {
      // Trust the body only when no user JWT is present (service-role call).
      // User JWTs always compute for themselves — body is ignored to prevent
      // a logged-in athlete from spoofing another user's zones.
      if (!authedUserId) {
        targetUserId = payloadUserId;
      }
    }
  }

  if (!targetUserId) {
    return unauthorizedResponse(corsHeaders);
  }

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

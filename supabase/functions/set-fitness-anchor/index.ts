/**
 * set-fitness-anchor — the athlete states a recent effort (distance + time) as
 * their current fitness. It's stored as the manual anchor on
 * athlete_pace_profiles and, via pace-engine precedence, overrides every
 * auto-derived source (source: "manual"). The whole zone ladder re-derives from
 * this one effort, so correcting fitness stays coherent.
 *
 * Contract: POST with JWT
 *   body  { distance: marathon|half|tenK|tenMi|fiveK|threeK|1500m|mile,
 *           time_seconds: number (30–36000),
 *           effort_date?: "YYYY-MM-DD" }
 *     OR  { clear: true }   // remove the override, fall back to auto
 *   200   { ok: true, projection: { marathon, half, tenK, fiveK, mile } | null }
 *         (projection = derived sec/mi ladder, for the UI to confirm)
 *   400   { error } — bad distance / time / nothing to do
 *   401   { error } — missing JWT
 *   500   { error }
 *
 * Phase 1 is athlete-self only (athlete owns their fitness). Coach-set is a
 * follow-on that reuses rewrite-block's coach-ownership resolution + a portal
 * surface. Immediate effect: get-pace-zones reflects the anchor on next call;
 * materialized plan paces refresh on the next recompute-plan-paces run.
 */
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";
import { getAuthenticatedUser, unauthorizedResponse } from "../_shared/auth.ts";
import { equivalentRacePaceSecPerMile, raceKeyForInput, type RaceKey } from "../_shared/paces.ts";

interface AnchorBody {
  distance?: string;
  time_seconds?: number;
  effort_date?: string;
  clear?: boolean;
}

const VALID_DISTANCES = new Set([
  "marathon", "half", "tenK", "tenMi", "fiveK", "threeK", "1500m", "mile",
]);

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

export interface SetAnchorDeps {
  resolveUser?: (req: Request) => Promise<string | null>;
  buildClient?: () => ReturnType<typeof createClient>;
}

/** Derived sec/mi ladder from one effort, for the confirm UI. */
function projectionFrom(distance: RaceKey, timeSeconds: number) {
  const at = (to: RaceKey) => Math.round(equivalentRacePaceSecPerMile(distance, timeSeconds, to));
  return {
    marathon: at("marathon"),
    half: at("half"),
    tenK: at("tenK"),
    fiveK: at("fiveK"),
    mile: at("mile"),
  };
}

export async function handleSetFitnessAnchor(
  req: Request,
  deps: SetAnchorDeps = {},
): Promise<Response> {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const userId = await (deps.resolveUser ?? getAuthenticatedUser)(req);
  if (!userId) return unauthorizedResponse(corsHeaders);

  let body: AnchorBody;
  try {
    body = (await req.json()) as AnchorBody;
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  const supabase = deps.buildClient
    ? deps.buildClient()
    : createClient(
        Deno.env.get("SUPABASE_URL")!,
        Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      );

  // Clear the override — fall back to the auto-derived anchors.
  if (body.clear === true) {
    const { error } = await supabase
      .from("athlete_pace_profiles")
      .update({
        manual_anchor_distance: null,
        manual_anchor_time_seconds: null,
        manual_anchor_date: null,
        manual_anchor_set_by: null,
        manual_anchor_updated_at: new Date().toISOString(),
      })
      .eq("user_id", userId);
    if (error) {
      console.error("set-fitness-anchor: clear failed", error);
      return json({ error: "Failed to clear anchor" }, 500);
    }
    return json({ ok: true, projection: null }, 200);
  }

  // Validate the effort.
  const distanceRaw = typeof body.distance === "string" ? body.distance : "";
  if (!VALID_DISTANCES.has(distanceRaw)) {
    return json({ error: `distance must be one of: ${[...VALID_DISTANCES].join(", ")}` }, 400);
  }
  const timeSeconds = Number(body.time_seconds);
  if (!Number.isFinite(timeSeconds) || timeSeconds < 30 || timeSeconds > 36000) {
    return json({ error: "time_seconds must be between 30 and 36000" }, 400);
  }
  const effortDate =
    typeof body.effort_date === "string" && /^\d{4}-\d{2}-\d{2}$/.test(body.effort_date)
      ? body.effort_date
      : null;

  const distance = raceKeyForInput(distanceRaw);

  // Upsert onto the athlete's pace profile (row may not exist yet).
  const { error } = await supabase
    .from("athlete_pace_profiles")
    .upsert(
      {
        user_id: userId,
        manual_anchor_distance: distance,
        manual_anchor_time_seconds: Math.round(timeSeconds),
        manual_anchor_date: effortDate,
        manual_anchor_set_by: "athlete",
        manual_anchor_updated_at: new Date().toISOString(),
      },
      { onConflict: "user_id" },
    );
  if (error) {
    console.error("set-fitness-anchor: upsert failed", error);
    return json({ error: "Failed to save anchor" }, 500);
  }

  return json({ ok: true, projection: projectionFrom(distance, Math.round(timeSeconds)) }, 200);
}

Deno.serve((req) => handleSetFitnessAnchor(req));

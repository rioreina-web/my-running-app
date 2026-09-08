/**
 * rebuild-athlete-state
 *
 * Keep-warm worker for athlete_state (v2 Phase E). Forces a rebuild so the
 * Read and coaching-agent never see a stale or missing state. Without this,
 * athlete_state is built lazily on read with a 60-minute TTL — which is why
 * prod had only 2 rows. This worker + the nightly cron
 * (20260612140000_nightly_athlete_state_rebuild.sql) keeps every active
 * athlete's state warm.
 *
 * Two modes:
 *   { user_id }   — rebuild one athlete. The nightly cron fans out one
 *                   http_post per active athlete (like daily-weather-forecast
 *                   does per plan), so each athlete is its own invocation.
 *   { batch: N }  — rebuild up to N of the most-stale active athletes
 *                   (a workout in the last 45d AND state missing or older
 *                   than 12h). Handy for manual runs / backfill.
 *
 * Auth: service-role only (constant-time bearer check), mirroring the
 * drain-* workers. The rebuild itself runs under the service-role admin
 * client, so the athlete_state upsert isn't blocked by RLS.
 */

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";
import { rebuildAthleteState } from "../_shared/athlete-state.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const admin = createClient(supabaseUrl, supabaseServiceKey);

const DEFAULT_BATCH = 25;
const MAX_BATCH = 100;
const STALE_HOURS = 12;
const ACTIVE_LOOKBACK_DAYS = 45;

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  // --- Auth: service-role only ---
  // The gateway verifies the JWT signature (verify_jwt = true for this
  // function — see config.toml), so we just confirm it's a service-role
  // token by decoding the role claim. This is robust to service-key / Vault
  // drift, unlike an exact string-match against SUPABASE_SERVICE_ROLE_KEY —
  // that brittle pattern is exactly what 403'd the drain crons when the
  // function-env key and the Vault copy diverged.
  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.startsWith("Bearer ")) return json({ error: "Authentication required" }, 401);
  const token = authHeader.slice("Bearer ".length).trim();
  if (!isServiceRoleJWT(token)) return json({ error: "Service role required" }, 403);

  let body: { user_id?: string; batch?: number } = {};
  try { body = (await req.json()) as { user_id?: string; batch?: number }; } catch { /* empty body ok */ }

  const start = Date.now();

  // --- Single-athlete mode (nightly cron fan-out) ---
  if (body.user_id) {
    try {
      await rebuildAthleteState(admin, body.user_id);
      return json({ rebuilt: 1, user_id: body.user_id, elapsed_ms: Date.now() - start });
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      console.error(`rebuild-athlete-state: ${body.user_id} failed:`, msg);
      return json({ error: `rebuild failed: ${msg}` }, 500);
    }
  }

  // --- Batch mode (manual / backfill) ---
  const batch = Math.min(Math.max(1, body.batch ?? DEFAULT_BATCH), MAX_BATCH);
  const sinceDate = new Date(Date.now() - ACTIVE_LOOKBACK_DAYS * 86400000)
    .toISOString().slice(0, 10);

  const { data: activeRows, error: activeErr } = await admin
    .from("training_logs")
    .select("user_id")
    .gte("workout_date", sinceDate)
    .not("user_id", "is", null)
    .limit(5000);
  if (activeErr) return json({ error: activeErr.message }, 500);
  const activeIds = [...new Set((activeRows ?? []).map((r) => r.user_id as string).filter(Boolean))];

  // Which active athletes have stale / missing state?
  const staleCutoff = new Date(Date.now() - STALE_HOURS * 3600000).toISOString();
  const { data: stateRows } = await admin
    .from("athlete_state")
    .select("user_id, last_updated_at")
    .in("user_id", activeIds.slice(0, 1000));
  const freshById = new Map(
    (stateRows ?? []).map((r) => [r.user_id as string, r.last_updated_at as string]),
  );
  const targets = activeIds
    .filter((id) => {
      const updated = freshById.get(id);
      return !updated || updated < staleCutoff;
    })
    .slice(0, batch);

  let rebuilt = 0;
  const errors: string[] = [];
  for (const id of targets) {
    try {
      await rebuildAthleteState(admin, id);
      rebuilt++;
    } catch (e) {
      errors.push(`${id}: ${e instanceof Error ? e.message : String(e)}`);
    }
  }

  return json({
    active: activeIds.length,
    targeted: targets.length,
    rebuilt,
    errors: errors.slice(0, 5),
    elapsed_ms: Date.now() - start,
  });
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

/** True if `token` is a non-expired service-role JWT. Signature is already
 *  verified by the gateway (verify_jwt = true); we only read the claims. */
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

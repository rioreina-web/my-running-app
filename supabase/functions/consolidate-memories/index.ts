/**
 * consolidate-memories
 *
 * The weekly "sleep" job for long-term memory (plan Step 4). Keeps each
 * athlete's user_memories store small and honest: merges near-duplicates,
 * archives expired transients + year-stale low-importance rows, and caps each
 * category at 10 active. All logic lives in _shared/memoryConsolidation.ts
 * (pure planner + I/O wrapper); this is a thin service-role HTTP shell that
 * mirrors compute-fitness-snapshot / the drain-* workers.
 *
 * Modes:
 *   { user_id } — consolidate one athlete. The weekly cron fans out one
 *                 http_post per athlete with memory activity.
 *   { batch: N } — consolidate up to N athletes who have any user_memories.
 *
 * Auth: service-role only (decoded-claim check). Archiving is reversible
 * (status → 'archived'); DELETE stays an athlete-only action (Model of You).
 *
 * Idempotent: running it twice in a row is a no-op the second time (pinned by
 * memoryConsolidation.test.ts).
 */

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";
import { consolidateMemories } from "../_shared/memoryConsolidation.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const admin = createClient(supabaseUrl, supabaseServiceKey);

const DEFAULT_BATCH = 50;
const MAX_BATCH = 500;

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.startsWith("Bearer ")) return json({ error: "Authentication required" }, 401);
  const token = authHeader.slice("Bearer ".length).trim();
  if (!isServiceRoleJWT(token)) return json({ error: "Service role required" }, 403);

  let body: { user_id?: string; batch?: number } = {};
  try {
    body = (await req.json()) as { user_id?: string; batch?: number };
  } catch {
    /* empty body ok */
  }

  const start = Date.now();

  // --- Single-athlete mode (weekly cron fan-out) ---
  if (body.user_id !== undefined) {
    const userId = body.user_id.trim();
    if (!userId) return json({ error: "empty user_id" }, 400);
    const result = await consolidateMemories(admin, userId);
    return json({ user_id: userId, ...result, elapsed_ms: Date.now() - start });
  }

  // --- Batch mode (manual / backfill) ---
  const batch = Math.min(Math.max(1, body.batch ?? DEFAULT_BATCH), MAX_BATCH);

  const { data: rows, error } = await admin
    .from("user_memories")
    .select("user_id")
    .eq("status", "active")
    .not("user_id", "is", null)
    .limit(20000);
  if (error) return json({ error: error.message }, 500);

  const ids = [...new Set((rows ?? []).map((r) => r.user_id as string).filter((id) => id && id.trim()))].slice(0, batch);

  let merged = 0;
  let archived = 0;
  for (const id of ids) {
    const res = await consolidateMemories(admin, id);
    merged += res.merged;
    archived += res.archived;
  }

  return json({ athletes: ids.length, merged, archived, elapsed_ms: Date.now() - start });
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function isServiceRoleJWT(token: string): boolean {
  try {
    const seg = token.split(".")[1];
    if (!seg) return false;
    const b64 = seg.replace(/-/g, "+").replace(/_/g, "/").padEnd(Math.ceil(seg.length / 4) * 4, "=");
    const payload = JSON.parse(atob(b64)) as { role?: string; exp?: number };
    if (payload.role !== "service_role") return false;
    if (typeof payload.exp === "number" && payload.exp * 1000 < Date.now()) return false;
    return true;
  } catch {
    return false;
  }
}

/**
 * merge-memo-into-run — collapse a voice/typed memo row INTO the GPS run it
 * describes, on the athlete's explicit say-so.
 *
 * Why (2026-09-04): the detail sheet's "link to a run" picker used to copy
 * the picked run's date / distance / duration ONTO the memo row. That is how
 * a memo about a 17.78-mi Strava run became a second 17.78-mi row in the
 * journal — the athlete linked it at 22:36 and the product answered with a
 * duplicate. Dedup at upload, not at read: the run row stays canonical
 * (GPS, laps, splits) and inherits the memo's words, mood, RPE and
 * structure; the memo row is consumed. `merge_voice_orphan_into_run` already
 * does exactly that (and refuses when the run carries its OWN memo, so a
 * link can never overwrite someone's words), but it is EXECUTE-granted to the
 * service role only — this endpoint is the authenticated door in front of it.
 *
 * Request body: { memo_log_id: UUID, run_log_id: UUID }
 * Auth: user JWT. Both rows must belong to the caller.
 * Response: { merged: boolean, run_id: UUID, reason?: string }
 *   merged=false is a normal outcome (the RPC refused), never a 5xx — the
 *   client falls back to its previous behaviour and the memo stays whole.
 */
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";
import { withSentry } from "../_shared/sentry.ts";
import { getAuthenticatedUser, unauthorizedResponse } from "../_shared/auth.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const admin = createClient(SUPABASE_URL, SERVICE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
});

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function json(obj: unknown, status: number): Response {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

type Row = {
  id: string;
  user_id: string | null;
  audio_url: string | null;
  has_streams: boolean;
};

async function loadRow(id: string): Promise<Row | null> {
  // external_streams is filtered on, never selected — the blob is large.
  const { data, error } = await admin
    .from("training_logs")
    .select("id, user_id, audio_url, external_streams")
    .eq("id", id)
    .maybeSingle();
  if (error || !data) return null;
  return {
    id: data.id,
    user_id: data.user_id,
    audio_url: data.audio_url,
    has_streams: data.external_streams != null,
  };
}

Deno.serve(withSentry("merge-memo-into-run", async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  const userId = await getAuthenticatedUser(req);
  if (!userId) return unauthorizedResponse(corsHeaders);

  let body: { memo_log_id?: unknown; run_log_id?: unknown };
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid JSON" }, 400);
  }
  const memoId = String(body.memo_log_id ?? "").toLowerCase();
  const runId = String(body.run_log_id ?? "").toLowerCase();
  if (!UUID_RE.test(memoId) || !UUID_RE.test(runId)) {
    return json({ error: "memo_log_id and run_log_id must be UUIDs" }, 400);
  }
  if (memoId === runId) return json({ error: "memo and run are the same row" }, 400);

  const [memo, run] = await Promise.all([loadRow(memoId), loadRow(runId)]);
  if (!memo || !run) return json({ error: "row not found" }, 404);
  // Ownership: the JWT's user must own BOTH rows. user_id is text matching
  // auth.uid()::text; compare case-insensitively (the iOS UUID-case bug).
  if (
    (memo.user_id ?? "").toLowerCase() !== userId.toLowerCase() ||
    (run.user_id ?? "").toLowerCase() !== userId.toLowerCase()
  ) {
    return json({ error: "not your rows" }, 403);
  }
  // Shape: memo has no GPS, run does. Anything else is not a memo→run merge
  // and the RPC would no-op anyway; say so instead of pretending.
  if (memo.has_streams) return json({ merged: false, run_id: runId, reason: "memo row already carries GPS" }, 200);
  if (!run.has_streams) return json({ merged: false, run_id: runId, reason: "target row has no GPS streams" }, 200);

  const { error: rpcErr } = await admin.rpc("merge_voice_orphan_into_run", {
    p_orphan: memoId,
    p_run: runId,
  });
  if (rpcErr) {
    console.error(`[merge-memo-into-run] rpc failed for ${memoId} → ${runId}: ${rpcErr.message}`);
    return json({ error: "merge failed" }, 502);
  }

  // The RPC refuses silently (raise notice) when the run already has its own
  // memo or real athlete notes; consumption is detected by the orphan row
  // being gone, exactly as process-training-memo's late collapse does it.
  const still = await loadRow(memoId);
  if (still) {
    console.log(`[merge-memo-into-run] refused: run ${runId} already carries a memo; ${memoId} left intact`);
    return json({ merged: false, run_id: runId, reason: "run already has its own memo" }, 200);
  }
  console.log(`[merge-memo-into-run] merged memo ${memoId} into run ${runId} for user ${userId}`);
  return json({ merged: true, run_id: runId }, 200);
}));

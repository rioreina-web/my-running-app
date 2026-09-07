/**
 * vital-connect -- create (or reuse) a Junction/Vital user for the authenticated
 * athlete and return a Link widget URL that deep-links straight to a provider
 * (default: Garmin). The app opens that URL; the athlete logs into Garmin;
 * Junction then streams their workouts, which the app reads via
 * /summary/workouts/{vital_user_id} and vital-webhook ingests server-side.
 *
 * Auth: user JWT (athlete action). Service-role callers must name the subject
 * user in the body -- see requireAuthOrServiceRole. Writes the
 * { user_id <-> vital_user_id } mapping with the service-role client
 * (RLS-bypassing). No client-side write path.
 */
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";
import { requireAuthOrServiceRole } from "../_shared/auth.ts";

const VITAL_BASE = Deno.env.get("VITAL_BASE_URL") ?? "https://api.sandbox.us.junction.com/v2";
const VITAL_API_KEY = Deno.env.get("VITAL_API_KEY") ?? "";

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

async function vital(path: string, init: RequestInit = {}) {
  const res = await fetch(`${VITAL_BASE}${path}`, {
    ...init,
    headers: {
      "x-vital-api-key": VITAL_API_KEY,
      "Content-Type": "application/json",
      "Accept": "application/json",
      ...(init.headers ?? {}),
    },
  });
  const text = await res.text();
  let data: unknown = null;
  try { data = text ? JSON.parse(text) : null; } catch { data = { raw: text }; }
  return { ok: res.ok, status: res.status, data: data as Record<string, unknown> | null };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (!VITAL_API_KEY) return json({ error: "VITAL_API_KEY not configured" }, 500);

  let body: { user_id?: string; provider?: string } = {};
  try { body = await req.json(); } catch { /* empty body allowed */ }

  const auth = await requireAuthOrServiceRole(req, body.user_id, corsHeaders);
  if ("response" in auth) return auth.response;
  const userId = auth.userId;
  const provider = (body.provider ?? "garmin").toLowerCase();

  const db = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  // 1. Reuse an existing Junction user for this athlete if we have one.
  let vitalUserId: string | null = null;
  {
    const { data } = await db
      .from("vital_credentials")
      .select("vital_user_id")
      .eq("user_id", userId)
      .maybeSingle();
    vitalUserId = (data?.vital_user_id as string | undefined) ?? null;
  }

  // 2. Otherwise create one in Junction (client_user_id = our user id).
  if (!vitalUserId) {
    const created = await vital("/user/", {
      method: "POST",
      body: JSON.stringify({ client_user_id: userId }),
    });

    if (created.ok && created.data?.user_id) {
      vitalUserId = created.data.user_id as string;
    } else if (created.status === 409) {
      // Already exists in Junction (e.g. a prior attempt) -- resolve it.
      const resolved = await vital(`/user/resolve/${encodeURIComponent(userId)}`);
      vitalUserId = (resolved.data?.user_id as string | undefined) ?? null;
    }
    if (!vitalUserId) {
      return json({ error: "Failed to create Junction user", detail: created.data }, 502);
    }

    const { error: upsertErr } = await db
      .from("vital_credentials")
      .upsert({ user_id: userId, vital_user_id: vitalUserId, provider }, { onConflict: "user_id" });
    if (upsertErr) {
      return json({ error: "Failed to store vital mapping", detail: upsertErr.message }, 500);
    }
  }

  // 3. Generate a Link token aimed straight at the provider (Garmin).
  const link = await vital("/link/token", {
    method: "POST",
    body: JSON.stringify({ userId: vitalUserId, provider }),
  });
  const linkUrl = (link.data?.link_web_url ?? link.data?.link_url) as string | undefined;
  if (!link.ok || !linkUrl) {
    return json({ error: "Failed to generate link token", detail: link.data }, 502);
  }

  // Best-effort: record provider + attempt time.
  await db.from("vital_credentials")
    .update({ provider, connected_at: new Date().toISOString() })
    .eq("user_id", userId);

  return json({ vital_user_id: vitalUserId, link_web_url: linkUrl });
});

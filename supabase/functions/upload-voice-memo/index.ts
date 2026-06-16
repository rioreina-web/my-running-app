/**
 * upload-voice-memo — service-role audio upload for voice memos.
 *
 * WHY THIS EXISTS (2026-06-16):
 *   Direct client uploads to the `training-memos` storage bucket have failed
 *   system-wide since 2026-06-02 with HTTP 400 / `{"statusCode":"403",
 *   "error":"Unauthorized","message":"new row violates row-level security
 *   policy"}`. The bucket's INSERT policy is PUBLIC with a bucket-only WITH
 *   CHECK — direct SQL probes confirm both `anon` and `authenticated` INSERT
 *   into storage.objects successfully. Yet the storage SERVICE rejects a valid
 *   authenticated user JWT (the same JWT clears PostgREST reads + writes). The
 *   break is in the storage service's JWT->role resolution, not the policy or
 *   the client. No client-side storage upload can fix it.
 *
 *   This function writes the audio with the SERVICE ROLE (which bypasses
 *   storage RLS), then returns the public URL. The CLIENT still inserts the
 *   `training_logs` row over PostgREST (which works) — so all the existing
 *   insert logic (workout linkage, dedup, trigger -> process-training-memo,
 *   status polling) is unchanged. We only swap the one broken step.
 *
 * Auth: user JWT only, verified via GoTrue (the auth path that still works).
 *
 * Body: { audioBase64: string (required), contentType?: string }
 * Returns: { ok: true, audio_url, path }
 */

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";
import { getAuthenticatedUser, unauthorizedResponse } from "../_shared/auth.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// Service-role client — bypasses storage RLS. This is the whole point.
const admin = createClient(SUPABASE_URL, SERVICE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
});

function json(obj: unknown, status: number): Response {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const userId = await getAuthenticatedUser(req);
  if (!userId) return unauthorizedResponse(corsHeaders);

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  const audioBase64 = typeof body.audioBase64 === "string" ? body.audioBase64 : "";
  if (!audioBase64) return json({ error: "audioBase64 is required" }, 400);
  const contentType = typeof body.contentType === "string" && body.contentType
    ? body.contentType
    : "audio/m4a";

  // base64 -> bytes
  let bytes: Uint8Array;
  try {
    const bin = atob(audioBase64);
    bytes = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  } catch {
    return json({ error: "audioBase64 is not valid base64" }, 400);
  }
  if (bytes.length === 0) return json({ error: "audio is empty" }, 400);

  const path = `${userId}/${crypto.randomUUID()}.m4a`;

  const { error: upErr } = await admin.storage
    .from("training-memos")
    .upload(path, bytes, { contentType, upsert: true });
  if (upErr) {
    return json({ error: `storage upload failed: ${upErr.message}` }, 502);
  }

  const { data: pub } = admin.storage.from("training-memos").getPublicUrl(path);
  return json({ ok: true, audio_url: pub.publicUrl, path }, 200);
});

// delete-account — the in-app "Delete My Account" endpoint.
//
// Permanently and irreversibly erases the signed-in athlete: all of their
// rows across every owner-scoped table, all of their files in storage, and
// finally their auth identity. There is no undo and no grace period — the
// user confirmed in-app before this was called.
//
// Required for App Store review (Guideline 5.1.1(v): apps with account
// creation must offer in-app account deletion).
//
// Auth: OWNER ONLY. We read the user from their JWT (getAuthenticatedUser)
// and act on that id — never an id from the request body. A user can only
// ever delete their own account. There is deliberately no service-role
// "delete any user" path here; ops-side deletion should go through the
// Supabase dashboard / Admin API directly, not this public endpoint.
//
// Order of operations (auth identity LAST, on purpose):
//   1. Delete DB rows via the catalog-driven delete_user_account() RPC.
//      That RPC is atomic — it either clears every table or rolls back.
//   2. Delete storage objects under the user's folder in each bucket.
//   3. Delete the auth user via the Admin API.
// If step 3 fails we still return an error, but the user's data is already
// gone and the call is safe to retry (the Admin delete is idempotent).

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";
import { getAuthenticatedUser, unauthorizedResponse } from "../_shared/auth.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// Service-role client: bypasses RLS so it can erase across the account.
const admin = createClient(supabaseUrl, supabaseServiceKey, {
  auth: { persistSession: false, autoRefreshToken: false },
});

// Buckets that may hold a user's files, each path-scoped as `${userId}/...`.
// avatars = profile photo; training-memos = voice memos / audio. The other
// two are attempted defensively and no-op if the user has no folder there.
const USER_BUCKETS = ["avatars", "training-memos", "plan-attachments", "content-videos"];

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

/**
 * Recursively collect every object path under `prefix` in a bucket.
 * Storage `list` returns folders as entries with a null `id`; we descend
 * into those so nested files (e.g. training-memos/<userId>/<date>/x.m4a)
 * are not left behind.
 */
async function listAllPaths(bucket: string, prefix: string): Promise<string[]> {
  const out: string[] = [];
  const { data, error } = await admin.storage.from(bucket).list(prefix, { limit: 1000 });
  if (error || !data) return out;
  for (const entry of data) {
    const path = `${prefix}/${entry.name}`;
    // A folder has no file id/metadata; recurse. A file we collect directly.
    if (entry.id === null || entry.id === undefined) {
      const nested = await listAllPaths(bucket, path);
      out.push(...nested);
    } else {
      out.push(path);
    }
  }
  return out;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  // 1. Identify the caller from their JWT. Owner-only — no body id trusted.
  const userId = await getAuthenticatedUser(req);
  if (!userId) return unauthorizedResponse(corsHeaders);

  // 2. Delete all database rows (atomic; rolls back on any failure).
  const { data: dbReport, error: dbError } = await admin.rpc("delete_user_account", {
    target_user_id: userId,
  });
  if (dbError) {
    console.error(`[delete-account] DB deletion failed for ${userId}:`, dbError.message);
    return json({ error: "Failed to delete account data. Nothing was removed; please try again." }, 500);
  }

  // 3. Delete storage objects, per bucket. Best-effort: a bucket that
  //    doesn't exist or has no folder for this user is simply skipped.
  const storageReport: Record<string, number> = {};
  for (const bucket of USER_BUCKETS) {
    try {
      const paths = await listAllPaths(bucket, userId);
      if (paths.length > 0) {
        const { error: rmError } = await admin.storage.from(bucket).remove(paths);
        if (rmError) {
          console.error(`[delete-account] storage remove failed (${bucket}) for ${userId}:`, rmError.message);
        } else {
          storageReport[bucket] = paths.length;
        }
      }
    } catch (e) {
      console.error(`[delete-account] storage list failed (${bucket}) for ${userId}:`, e);
    }
  }

  // 4. Delete the auth identity LAST (idempotent; safe to retry).
  const { error: authError } = await admin.auth.admin.deleteUser(userId);
  if (authError) {
    console.error(`[delete-account] auth user deletion failed for ${userId}:`, authError.message);
    return json(
      {
        error: "Your data was deleted, but removing your login failed. Please try again.",
        dbReport,
        storageReport,
      },
      500,
    );
  }

  console.log(`[delete-account] account fully deleted: ${userId}`, { dbReport, storageReport });
  return json({ ok: true, dbReport, storageReport }, 200);
});

/**
 * Account deletion.
 *
 * `docs/legal/privacy-policy.md` promises an athlete can delete their account
 * and data at any time, via in-app settings. Nothing implemented that. Apple
 * App Store 5.1.1(v) also requires in-app account deletion for any app that
 * offers account creation.
 *
 * Order matters and is not arbitrary:
 *
 *   1. Read the athlete's storage references OUT of the database, while the
 *      rows still exist.
 *   2. Remove the objects through the Storage API. Deleting `storage.objects`
 *      rows in SQL would leave the bytes in the object store, so this cannot
 *      be folded into the SQL function.
 *   3. Delete the database rows (`delete_user_data`).
 *   4. Delete the auth user, so the account cannot be signed into again.
 *   5. Write the tombstone.
 *
 * If step 2 fails we stop before touching the database: an athlete whose rows
 * are gone but whose voice recordings survive is the worst outcome available,
 * because the reference needed to find those recordings has just been
 * destroyed. Failing with everything still intact is recoverable; that is not.
 *
 * Storage paths are collected two ways, and both are necessary. Prod holds 294
 * memo objects: 190 under `{user_id}/`, but 97 are bare filenames predating
 * that convention (65 of which a training_log still references) and 7 sit under
 * some other folder. A prefix listing alone misses the bare ones; following
 * audio_url alone misses anything the athlete uploaded whose row was already
 * deleted. Union of the two.
 */

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";
import { requireAuthOrServiceRole } from "../_shared/auth.ts";
import { resolveTrainingMemoPath } from "../_shared/storage.ts";

const MEMO_BUCKET = "training-memos";

/** Buckets that store objects under a `{user_id}/` prefix. */
const USER_FOLDERED_BUCKETS = [MEMO_BUCKET, "avatars", "plan-attachments"];

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });

/** sha256 hex — for the tombstone, so it holds no reversible identifier. */
async function sha256Hex(input: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(input),
  );
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const body = await req.json().catch(() => ({}));

    // The athlete deletes their own account with their JWT. A service-role
    // caller (support-initiated) must name the subject explicitly.
    const auth = await requireAuthOrServiceRole(req, body.user_id, corsHeaders);
    if ("response" in auth) return auth.response;
    const { userId } = auth;

    // Deliberate, unambiguous intent. Guards against a mis-wired client or a
    // stray retry erasing an account.
    if (body.confirm !== "DELETE") {
      return json(
        {
          error:
            'Account deletion requires {"confirm":"DELETE"} in the request body.',
        },
        400,
      );
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    /**
     * Recursively list every object under a prefix — Storage's `list` returns
     * one level at a time, and memo paths can be `{user}/{timestamp}/{file}`.
     *
     * Declared here, closing over `supabase`, rather than taking the client as
     * a parameter. Annotating such a parameter means naming SupabaseClient's
     * generic instantiation, and `ReturnType<typeof createClient>` resolves to
     * a different one than the created client — which is what broke CI. A
     * closure has no type boundary to get wrong.
     */
    const listPrefix = async (
      bucket: string,
      prefix: string,
      depth = 0,
    ): Promise<string[]> => {
      if (depth > 4) return [];
      const out: string[] = [];
      const { data, error } = await supabase.storage
        .from(bucket)
        .list(prefix, { limit: 1000 });

      if (error || !data) return out;

      for (const entry of data) {
        const full = prefix ? `${prefix}/${entry.name}` : entry.name;
        // Storage marks a folder with a null `id`. The SDK declares it as
        // `string`, so the cast states the runtime shape explicitly rather
        // than leaving a `string === null` comparison that a stricter SDK
        // typing could reject as having no overlap.
        const isFolder = (entry as { id: string | null }).id === null;
        if (isFolder) {
          out.push(...(await listPrefix(bucket, full, depth + 1)));
        } else {
          out.push(full);
        }
      }
      return out;
    };

    // ── 1. Collect storage paths while the rows still exist ─────────────
    const memoPaths = new Set<string>();

    const { data: logs, error: logsErr } = await supabase
      .from("training_logs")
      .select("audio_url, transcript_url")
      .eq("user_id", userId);

    if (logsErr) {
      return json(
        { error: `Could not read storage references: ${logsErr.message}` },
        500,
      );
    }

    for (const row of logs ?? []) {
      for (const ref of [row.audio_url, row.transcript_url]) {
        const path = resolveTrainingMemoPath(ref);
        if (path) memoPaths.add(path);
      }
    }

    const byBucket = new Map<string, Set<string>>();
    byBucket.set(MEMO_BUCKET, memoPaths);

    for (const bucket of USER_FOLDERED_BUCKETS) {
      const found = await listPrefix(bucket, userId);
      if (!found.length) continue;
      const set = byBucket.get(bucket) ?? new Set<string>();
      found.forEach((p) => set.add(p));
      byBucket.set(bucket, set);
    }

    // ── 2. Remove objects. Abort before the DB if this fails ────────────
    const storageRemoved: Record<string, number> = {};

    for (const [bucket, paths] of byBucket) {
      if (!paths.size) continue;

      const all = [...paths];
      for (let i = 0; i < all.length; i += 100) {
        const chunk = all.slice(i, i + 100);
        const { error } = await supabase.storage.from(bucket).remove(chunk);
        if (error) {
          return json(
            {
              error:
                `Storage deletion failed for ${bucket}: ${error.message}. ` +
                `No database rows were deleted — the account is intact and the ` +
                `request can be retried.`,
            },
            500,
          );
        }
      }
      storageRemoved[bucket] = all.length;
    }

    // ── 3. Database rows ────────────────────────────────────────────────
    const { data: counts, error: dataErr } = await supabase.rpc(
      "delete_user_data",
      { p_user_id: userId },
    );

    if (dataErr) {
      return json(
        {
          error: `Row deletion failed: ${dataErr.message}`,
          storage_removed: storageRemoved,
          note:
            "Storage objects were already removed. Retry — row deletion is " +
            "idempotent and the remaining rows are still present.",
        },
        500,
      );
    }

    // ── 4. Auth user ────────────────────────────────────────────────────
    const { error: authErr } = await supabase.auth.admin.deleteUser(userId);
    if (authErr) {
      return json(
        {
          error: `Auth user deletion failed: ${authErr.message}`,
          row_counts: counts,
          storage_removed: storageRemoved,
          note:
            "Data is deleted but the login still exists. Retry, or remove the " +
            "auth user from the dashboard.",
        },
        500,
      );
    }

    // ── 5. Tombstone (no personal data) ─────────────────────────────────
    const { error: tombErr } = await supabase.from("deleted_accounts").insert({
      user_id_hash: await sha256Hex(userId),
      row_counts: counts ?? {},
      storage_note: JSON.stringify(storageRemoved),
    });

    if (tombErr) {
      // The deletion itself succeeded; losing the audit row must not turn a
      // completed erasure into a reported failure.
      console.error("[delete-account] tombstone insert failed:", tombErr.message);
    }

    return json({
      deleted: true,
      row_counts: counts ?? {},
      storage_removed: storageRemoved,
    });
  } catch (error) {
    console.error("[delete-account] unexpected error:", error);
    return json({ error: "Account deletion failed" }, 500);
  }
});

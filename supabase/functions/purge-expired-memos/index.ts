/**
 * Voice-memo audio retention.
 *
 * `docs/legal/privacy-policy.md` §7 states the audio file "is retained for
 * [TODO: retention — e.g., 90 days], after which it is deleted. The
 * transcription persists as part of your training log unless you delete the
 * log entry." Nothing implemented that: no purge job existed, so every
 * recording has been kept indefinitely.
 *
 * This deletes the AUDIO and clears the row's pointer to it. It deliberately
 * does NOT touch cleaned_notes / transcription, because the policy says the
 * transcription survives. Deleting the athlete's training history here would
 * be a different promise than the one that was made.
 *
 * Two deliberate safety choices:
 *
 *   - `dry_run` defaults to TRUE. The first runs report what would be removed
 *     without removing it. A destructive retention sweep should be looked at
 *     before it is trusted, and nothing here has been exercised against real
 *     production data.
 *   - The retention window is NOT hardcoded. It comes from
 *     MEMO_RETENTION_DAYS, or the request, because how long to keep health
 *     recordings is a policy decision, not an implementation detail. The
 *     policy's own value is still a [TODO]; 90 is used as the documented
 *     example, not as a decision made on anyone's behalf.
 *
 * Not scheduled by a cron in this change. Putting a destructive sweep on a
 * timer should follow an explicit sign-off on the number, plus at least one
 * dry run whose output someone has read.
 */

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";
import { requireServiceRole } from "../_shared/auth.ts";
import { resolveTrainingMemoPath } from "../_shared/storage.ts";

const MEMO_BUCKET = "training-memos";

/** The policy's example value. Overridden by env or request. */
const DEFAULT_RETENTION_DAYS = Number(
  Deno.env.get("MEMO_RETENTION_DAYS") ?? "90",
);

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  // Server-only: cron or an operator. There is no user-facing caller, and the
  // subject isn't a single body field, so requireServiceRole is the right gate.
  const blocked = requireServiceRole(req, corsHeaders);
  if (blocked) return blocked;

  try {
    const body = await req.json().catch(() => ({}));

    const retentionDays = Number.isFinite(Number(body.retention_days))
      ? Number(body.retention_days)
      : DEFAULT_RETENTION_DAYS;

    if (!Number.isFinite(retentionDays) || retentionDays < 1) {
      return json({ error: "retention_days must be a positive number" }, 400);
    }

    // Opt IN to deleting. Anything other than an explicit false stays a dry run.
    const dryRun = body.dry_run !== false;

    const cutoff = new Date(Date.now() - retentionDays * 86_400_000)
      .toISOString();

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // Rows whose audio is past the window. `created_at` is when the recording
    // was made, which is what the policy's clock refers to — not workout_date,
    // which an athlete can backdate.
    const { data: expired, error: queryErr } = await supabase
      .from("training_logs")
      .select("id, audio_url, transcript_url, created_at")
      .lt("created_at", cutoff)
      .not("audio_url", "is", null)
      .limit(1000);

    if (queryErr) {
      return json({ error: `Query failed: ${queryErr.message}` }, 500);
    }

    const rows = expired ?? [];
    const paths: string[] = [];
    const rowIds: string[] = [];
    const unresolvable: string[] = [];

    for (const row of rows) {
      rowIds.push(row.id);
      let resolvedAny = false;
      for (const ref of [row.audio_url, row.transcript_url]) {
        const p = resolveTrainingMemoPath(ref);
        if (p) {
          paths.push(p);
          resolvedAny = true;
        }
      }
      // A row past the window whose pointer can't be resolved would otherwise
      // be silently skipped forever. Surface it rather than let it rot.
      if (!resolvedAny) unresolvable.push(row.id);
    }

    if (dryRun) {
      return json({
        dry_run: true,
        retention_days: retentionDays,
        cutoff,
        rows_past_retention: rows.length,
        objects_that_would_be_deleted: paths.length,
        rows_with_unresolvable_audio_url: unresolvable.length,
        note:
          "Nothing was deleted. Re-send with {\"dry_run\": false} to apply. " +
          "Transcriptions are never touched — only the audio and the row's " +
          "pointer to it.",
      });
    }

    // ── Apply ───────────────────────────────────────────────────────────
    let removed = 0;
    for (let i = 0; i < paths.length; i += 100) {
      const chunk = paths.slice(i, i + 100);
      const { error } = await supabase.storage.from(MEMO_BUCKET).remove(chunk);
      if (error) {
        return json(
          {
            error: `Storage removal failed: ${error.message}`,
            objects_removed_before_failure: removed,
            note:
              "No rows were updated, so the remaining objects are still " +
              "reachable from their rows and the sweep can be re-run.",
          },
          500,
        );
      }
      removed += chunk.length;
    }

    // Clear the pointers only after the bytes are gone. The reverse order
    // would orphan the audio with nothing left pointing at it.
    const { error: updErr } = await supabase
      .from("training_logs")
      .update({ audio_url: null, transcript_url: null })
      .in("id", rowIds);

    if (updErr) {
      return json(
        {
          error: `Objects removed but rows not updated: ${updErr.message}`,
          objects_removed: removed,
          note:
            "Rows now point at deleted audio. Re-run to reconcile, or clear " +
            "audio_url for the affected ids manually.",
        },
        500,
      );
    }

    console.log(
      `[purge-expired-memos] removed ${removed} objects across ${rowIds.length} rows ` +
        `older than ${retentionDays}d`,
    );

    return json({
      dry_run: false,
      retention_days: retentionDays,
      cutoff,
      rows_updated: rowIds.length,
      objects_removed: removed,
      rows_with_unresolvable_audio_url: unresolvable.length,
    });
  } catch (error) {
    console.error("[purge-expired-memos] unexpected error:", error);
    return json({ error: "Purge failed" }, 500);
  }
});

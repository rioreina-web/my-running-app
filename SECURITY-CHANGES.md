# Security changes — 2026-05-21/22 audit

Manifest of security-relevant changes left in the working tree. Nothing is
committed. Use this to stage the work once branch hygiene is sorted.

## Summary

Six files changed/created. The fixes close three classes of issue:

1. **Broken object-level authorization** in 3 edge functions where
   `userId = JWT ?? body.user_id` let an anon-key caller act as any user.
2. **Auth bypass** in `strava-test-pull` via a hardcoded user fallback.
3. **Over-permissive Postgres RLS** — `WITH CHECK (true)` insert policies on
   user-owned tables, RLS disabled on `debug_coach_log`, public-bucket
   listing.

`subscribe-to-plan` and `reconcile-log` were audited and are already safe.

## Files

### Edge functions (4)

| File | Git state | Change |
|---|---|---|
| `supabase/functions/weekly-coaching-report/index.ts` | tracked, ` M` | IDOR fix in auth block + import. Entangled with ~180 uncommitted lines of unrelated refactor (cors.ts / loadPrompt / WorkoutFeaturesRow). Stage selectively. |
| `supabase/functions/strava-test-pull/index.ts` | untracked | Removed hardcoded DEBUG_USER_ID fallback. |
| `supabase/functions/adapt-plan/index.ts` | untracked | IDOR fix in auth block + import. Removed unused UUID_RE. |
| `supabase/functions/build-pace-profile/index.ts` | untracked | IDOR fix in auth block + import. Removed unused UUID_RE. |

### Migrations (2 — purely new)

| File | Git state | Effect |
|---|---|---|
| `supabase/migrations/20260521100000_drop_public_storage_list_policies.sql` | untracked | Drops the broad public-role SELECT/list policies on `training-memos`, `plan-attachments`, `content-videos`. Stops bucket enumeration. Public URL playback unaffected. |
| `supabase/migrations/20260521110000_tighten_insert_rls_and_debug_log.sql` | untracked | ENABLE RLS on `debug_coach_log`. Owner-scopes INSERT on `fitness_snapshots`, `race_intel`, `weekly_coaching_reports`, `blog_posts`. Drops redundant `usage_tracking`/`content_library` open-insert policies. Service-role insert paths unaffected (RLS bypassed). |

## Hunks — for selective staging of weekly-coaching-report

Use these if you want to stage *only* the security fix and leave the
refactor uncommitted. The other 3 functions are untracked-new and can be
staged whole.

**Import (line 18):**

```diff
-import { getAuthenticatedUser, unauthorizedResponse } from "../_shared/auth.ts";
+import { requireAuthOrServiceRole, requireServiceRole } from "../_shared/auth.ts";
```

**Auth block (was lines ~55–80):**

```diff
-    // Auth: batch mode uses service role, single user uses JWT
-    let userId: string | null = null;
-    if (isBatch) {
-      // Called from pg_cron with service role key — no user auth needed
-      const authHeader = req.headers.get("Authorization") || "";
-      if (
-        !authHeader.includes(
-          Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.slice(0, 20) || "___"
-        )
-      ) {
-        return new Response(
-          JSON.stringify({ error: "Batch mode requires service role key" }),
-          { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } }
-        );
-      }
-    } else {
-      userId = body.userId || (await getAuthenticatedUser(req));
-      if (!userId) {
-        return unauthorizedResponse(corsHeaders);
-      }
-
-      const rlBlocked = await enforceFeatureRateLimit(userId, "weekly_review", corsHeaders);
-      if (rlBlocked) return rlBlocked;
-    }
+    // Auth: batch mode is service-role only (cron); single-user mode accepts
+    // a user JWT or a service-role caller that names the subject user.
+    let userId: string | null = null;
+    if (isBatch) {
+      // Cron / pg_net only. Constant-time service-role key check.
+      const svc = requireServiceRole(req, corsHeaders);
+      if (svc) return svc;
+    } else {
+      // requireAuthOrServiceRole 403s if body.userId is present but doesn't
+      // match the JWT user — closes the IDOR where any anon-key holder could
+      // pull another athlete's report by passing their userId in the body.
+      const auth = await requireAuthOrServiceRole(req, body.userId, corsHeaders);
+      if ("response" in auth) return auth.response;
+      userId = auth.userId;
+
+      // Rate-limit only genuine user-facing calls; service-role (cron) is
+      // gated by its own schedule.
+      if (!auth.isServiceRole) {
+        const rlBlocked = await enforceFeatureRateLimit(userId, "weekly_review", corsHeaders);
+        if (rlBlocked) return rlBlocked;
+      }
+    }
```

## Deploy plan (after branch is clean)

```bash
cd /Users/rioreina/my-running-app

# Apply migrations
npx supabase db push

# Deploy functions
npx supabase functions deploy strava-test-pull
npx supabase functions deploy adapt-plan
npx supabase functions deploy build-pace-profile
npx supabase functions deploy weekly-coaching-report   # also ships the refactor in this file
```

Verify after deploy:

```bash
# 1. strava-test-pull should reject the anon-key-only call
curl -s -o /dev/null -w "%{http_code}\n" -X POST \
  "$SUPABASE_URL/functions/v1/strava-test-pull" \
  -H "Authorization: Bearer $SUPABASE_ANON_KEY" \
  -H "Content-Type: application/json" -d '{"limit":1}'
# expected: 401

# 2. trigger fix verification (already applied 2026-05-20)
# Strava sync should now import new runs cleanly.
```

## Type-check status

- `strava-test-pull`, `adapt-plan`, `build-pace-profile`: clean. The one
  pre-existing `'source' does not exist in type 'unknown[]'` error in
  `adapt-plan` is supabase-js generic noise on an insert payload, unrelated
  to my edit.
- `weekly-coaching-report`: pre-existing errors from the in-progress
  refactor (supabase-js generic typing on `generateReportForUser`,
  `target_time_seconds`, etc.). Not from the auth fix. Deno deploys don't
  hard-fail on type errors but the refactor should be completed first.

## Still open — your call

Not fixed; flagged here so they don't get lost.

### Higher priority

- **`training-memos` UPDATE/DELETE policies are unscoped.** The `public`
  role has `bucket_id = 'training-memos'` policies for both UPDATE and
  DELETE with no owner check — anyone can overwrite or delete any user's
  voice memo. Worse than the listing issue the advisor flagged. Needs a
  migration that scopes both to the object owner, with verification that
  the app's own delete path still works.
- **Memos are fundamentally public.** Today's fix only stops enumeration.
  The real confidentiality fix is `public = false` on the bucket +
  switching iOS (`VoiceLogViewModel.swift`, `OfflineQueue.swift`) from
  `getPublicURL` to `createSignedURL`, plus a plan for already-stored
  public URLs in `training_logs.audio_url`.
- **3 production functions are untracked in this repo.**
  `strava-test-pull`, `adapt-plan`, `build-pace-profile` exist only in
  this working tree — not committed on `design/editorial-v2` or `main`.
  A `git clean -fd` would delete them. Worth tracking down whether they
  live on a `claude/*` branch and reconciling.

### Lower priority

- ~9 `SECURITY DEFINER` functions are executable by `anon` / `authenticated`
  via `/rest/v1/rpc/...` — `claim_coachable_moment_jobs`,
  `trigger_voice_log_processing`, `fn_weekly_plan_rebalance`,
  `fn_trigger_reconcile_log`, `trigger_parse_workout_structure`,
  `fn_enqueue_coachable_moment_evaluation`, `current_coach_id`,
  `increment_subscriber_count`. Revoke `EXECUTE` from `anon` /
  `authenticated`; these are meant for cron/triggers only.
- 2 `SECURITY DEFINER` views (`daily_cost_estimate`, `daily_usage`) bypass
  RLS — review and convert to `SECURITY INVOKER` if not intentional.
- Leaked-password protection disabled in Auth settings — toggle in the
  Supabase dashboard.
- `blog_posts` — only `author_id` forgery is now blocked; any authenticated
  user can still author a post. Admin-gating is a separate product call.
- `reconcile-log`'s shared-secret check uses `!==` (not constant-time).
  Server-to-server only, low impact, but trivially fixable with a
  timingSafeEqual helper.
- ~20 functions with mutable `search_path` — same class of bug that broke
  Strava sync on 2026-05-20. Add `SET search_path = pg_catalog, pg_temp`
  and schema-qualify table refs.

## Files audited and confirmed already safe

- `supabase/functions/subscribe-to-plan/index.ts` — requires JWT, then
  verifies caller is athlete OR a coach with an active relationship before
  acting on `athleteUserId`.
- `supabase/functions/reconcile-log/index.ts` — shared-secret gated,
  operates only on the log record's own `user_id`. No cross-user IDOR.

# In-app account deletion — build + deploy notes (2026-07-20)

Ships the "Delete Account" flow. Required for App Store review (Guideline
5.1.1(v): any app offering account creation must offer in-app deletion).
Behavior chosen: **immediate and permanent** (no grace period).

## What a deletion erases

For the signed-in athlete only: every row across all owner-scoped tables
(runs, voice memos + transcripts, niggles, moods, check-ins, plans,
coaching history, profile/bio/photo), their files in storage, and finally
their login identity. There is no undo.

## Files in this change

- `supabase/migrations/20260720120000_delete_user_account_function.sql`
  — the `delete_user_account(text)` database function.
- `supabase/functions/delete-account/index.ts` — the edge function the app
  calls.
- `RunningLog/RunningLog/Shared/SettingsView.swift` — a "Delete Account"
  link under Sign Out, plus the `DeleteAccountSheet` confirmation screen.

## How it works (three steps, in order)

1. **App → edge function.** The confirmation sheet requires the athlete to
   type `DELETE`, then calls the `delete-account` function. The function
   reads *who* they are from their login token — never from anything the
   app sends — so a user can only ever delete their own account.
2. **Erase the data.** The function calls `delete_user_account()`, which
   reads the live database catalog and deletes from **every** table that
   currently has a `user_id` / `athlete_user_id` / `athlete_id` column
   matching this user. This is deliberate: owner columns get added over
   time (e.g. `training_logs.user_id` was added by a later migration, not
   in its original table), so a hand-written list would silently miss
   tables. The whole erase is one transaction — it either clears
   everything or rolls back and deletes nothing (never a half-deleted
   account). Foreign-key ordering is handled automatically by retrying.
3. **Erase files + login.** The function deletes the user's folder from
   the storage buckets (`avatars`, `training-memos`, and two others,
   best-effort), then deletes the login identity last.

## Security

The database function runs with elevated rights, so it's locked down:
execute permission is **revoked** from normal users and granted **only**
to the service role. The only caller is the edge function, which verifies
the login token first. This is enforced in the migration — no extra config
needed.

## Deploying (needs a developer with repo + Supabase access)

Per repo rules #5/#9, this reaches production only via committed migration +
`supabase db push` (no dashboard SQL editor). Steps:

1. Commit these files.
2. `supabase db push` — applies the new function to production.
3. `supabase functions deploy delete-account` — deploys the endpoint.
4. Build/submit the iOS app with the updated Settings screen.

No environment variables to add — the function uses the ones every other
edge function already uses (`SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`).

## How to test before shipping

Use a throwaway test account: sign in, log a run and a voice memo, set a
profile photo, then Settings → Delete Account → type `DELETE` → confirm.
Expect: you're returned to the sign-in screen. Signing back in should
produce a brand-new empty account. In Supabase, confirm the old user's
rows are gone from `training_logs`, `body_mentions`, `athlete_settings`,
etc., and that the user is gone from Authentication.

## Verification done in this build

- The migration SQL and its procedural body both parse cleanly under the
  real PostgreSQL parser (libpg_query / pglast).
- The edge function and Swift screen are structurally sound and correctly
  wired (confirmed by static checks). Full compile/runtime testing needs
  Xcode + a live Supabase project, which is the developer step above.

## Known edge case (non-blocking for the Maya beta)

If a user is *also* a coach, their coach identity (`coach_profiles` and
`coach_athlete_relationships`, keyed on a UUID `coach_id` rather than the
athlete `user_id`) is **not** removed by this flow — only their athlete
data is. Maya (the wedge persona) is not a coach, so this doesn't affect
the beta. When coach surfaces are reinvested in, extend the function to
also clear coach-side rows for that user.

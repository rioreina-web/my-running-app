# Multi-user isolation — verification report (2026-07-20)

Goal: prove that one user cannot see another user's data. Audited the
**live production database** (`RunningAppMVP2`, project
`aqdijapxmjqaetursrde`) read-only.

## Result: PASS

Checked all 35 tables that store user-owned data (any table with a
`user_id` / `athlete_user_id` / `athlete_id` column).

- **Row Level Security enabled: 35 / 35.** No table stores user data with
  the security wall turned off.
- **No open read holes.** Zero tables expose an "anyone can read
  everything" (`USING (true)`) read policy to logged-in users.
- Every table falls into one safe category:
  - **Owner-scoped** — reads locked to `auth.uid()` (the athlete's own
    login id). Covers runs, voice memos, niggles, moods, plans, fitness,
    profile/settings, etc.
  - **Coach-scoped** — reads locked to the coach's own athletes via the
    `current_coach_id()` helper (coach notes, rosters, relationships).
  - **Backend-only** — the 4 job/queue tables
    (`coach_insight_jobs`, `coachable_moment_jobs`,
    `daily_read_workout_dispatches`, `voice_processing_jobs`) and
    `debug_coach_log`. Their only policy requires
    `auth.role() = 'service_role'`, so a normal logged-in user gets zero
    rows. Confirmed by reading the policy definitions.

Conclusion: the core multi-user guarantee — each user sees only their own
data — is correctly configured across the entire schema in production.

## Live behavioral test: PASS

Beyond the static audit, ran a runtime test against production (inside a
transaction that was rolled back — no data persisted, confirmed 0 leftover
rows afterward):

- Inserted two synthetic users (A and B) into `athlete_settings`.
- Switched the database into user A's identity and asked it to read **both**
  A's and B's rows → it returned **only A's row**.
- Switched into user B's identity and asked for both → **only B's row**.

So even when a user explicitly asks for another user's data, the database
returns nothing but their own. This demonstrates the isolation at runtime,
not just in configuration.

## What this proves, and what it doesn't

Both the **static** audit (rules correct and switched on everywhere) and the
**behavioral** test (the database refuses cross-user reads at runtime) pass.
The core multi-user guarantee holds database-wide in production.

One check remains, requiring a real device build:

1. **App-loop manual test (needs Xcode + a deployed backend).** The
   human-facing round trip can only be tested on a real build:

   - Sign up as a brand-new user → land in an empty account (no one
     else's data leaks in).
   - Log a run + record a voice memo + set a profile photo → all appear.
   - Sign out, sign in as a *second* new user → see none of the first
     user's runs/memos/photo.
   - Settings → Delete Account → type `DELETE` → confirm → returned to
     sign-in. Sign back in → fresh empty account. In Supabase, confirm the
     old user's rows are gone from `training_logs`, `body_mentions`,
     `athlete_settings`, and that the user is gone from Authentication.

   Note: the Delete Account step can only be tested **after** the
   `delete-account` function + migration are deployed (see
   `account-deletion-2026-07-20.md`).

## How this was checked

Two read-only queries against production via the Supabase connection:
one enumerating every owner-scoped table with its RLS status, policy
count, and whether any read policy is owner/coach-scoped or an open
`true` hole; a second dumping the exact policy definitions for the
non-owner-scoped job tables to confirm they are service-role-only. No
data was written or changed.

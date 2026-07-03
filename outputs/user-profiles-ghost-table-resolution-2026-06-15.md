# Resolving the `user_profiles` ghost table — 2026-06-15

**Status:** Migrations authored + validated, ready for `supabase db push`.
**Approach chosen:** dedicated SETTINGS surface (`athlete_settings`), *not*
a resurrection of `user_profiles`.

## The problem (recap)

`user_profiles` never existed in production. Its January migration
(`20260128_152000_user_profile.sql`) had a malformed filename that parsed as
version `20260128`, colliding with the already-applied `fix_vector_search`,
so the Supabase CLI silently skipped it for ~5 months. Three layers of
defensive workarounds (web coach-portal, iOS `LocationProvider`, the
`fetch-workout-weather` edge function) grew up around the missing table.

It was escalated from cleanup to a **feature blocker** because the Daily
Read automation — the hourly dispatch cron and the workout-triggered
re-render — both depended on `user_profiles.timezone`, so both were
quarantined and have been dark in prod since they shipped.

Confirmed live against prod (`aqdijapxmjqaetursrde`) on 2026-06-15:
`user_profiles` absent; `athlete_state` present (one row per athlete);
`daily_read_dispatch_log`, `daily_read_workout_dispatches`,
`enqueue_daily_reads()`, and the `enqueue-daily-coaching-reads` cron all
absent. Migration ledger current through `20260613250000`.

## Why a settings surface, not a recreated `user_profiles`

The `profile-table-audit-2026-05-22` diagnosis was that `user_profiles` was
"three tables wearing one coat": athlete attributes (→ `athlete_state`),
injuries (→ event log), and device/location/locale settings (→ a dedicated
SETTINGS surface). Recreating it would rebuild the exact anti-pattern the
audit wanted removed and keep all three workaround layers alive.

The only field the blocked feature actually needs is `timezone`, which is a
SETTINGS field. So we built the SETTINGS surface the audit recommended
(Phase 5f, option 1) and pointed the automation at it. This unblocks the
Daily Read feature **and** advances the audit instead of regressing it.

## What changed

New migrations (in `supabase/migrations/`):

1. **`20260615210000_create_athlete_settings.sql`** — creates
   `athlete_settings` (`user_id` UNIQUE, `timezone` NOT NULL DEFAULT 'UTC',
   `home_lat` REAL, `home_lon` REAL, `preferred_run_time` TEXT with the same
   CHECK as the old weather columns), an `updated_at` trigger, and RLS in
   the same migration (owner SELECT/INSERT/UPDATE with the repo's
   `auth.uid() IS NULL` dev fallback, plus service-role full access; no
   DELETE policy). Column types mirror the original `user_profiles` weather
   columns so the SETTINGS edge-readers can be repointed later with no
   further schema change.

2. **`20260615220000_daily_coaching_reads_cron.sql`** — the re-stamped Daily
   Read cron. The `ALTER TABLE user_profiles ADD COLUMN timezone` is gone.
   `enqueue_daily_reads()` now scans **`athlete_state`** for candidate
   athletes and `LEFT JOIN`s `athlete_settings` for timezone (default UTC).

3. **`20260615230000_daily_coaching_reads_workout_trigger.sql`** — the
   re-stamped workout-trigger. Its single timezone lookup now reads
   `athlete_settings` instead of `user_profiles` (still soft-falls to UTC).

Edge function:

4. **`supabase/functions/coaching-daily-read/index.ts`** —
   `resolveAthleteLocalDate()` now reads `athlete_settings.timezone`.

Housekeeping:

5. Removed the three superseded quarantine files
   (`20260128152000_user_profile.sql` and the two `daily_coaching_reads`
   originals); updated `supabase/migrations_quarantine/README.md`.

## Validation performed

A managed Supabase dev branch was **not available** (branching requires the
Pro plan; this org is below it) and the sandbox has no Postgres/Docker/
network to stand one up locally. Validation done instead:

- **Syntax:** all three migrations parse cleanly against the real
  PostgreSQL grammar (via `pglast` / libpg_query) — 15 / 14 / 15 top-level
  statements respectively.
- **Candidate-scan logic:** the exact `athlete_state LEFT JOIN
  athlete_settings` query (with a CTE standing in for the not-yet-created
  table) was run read-only against prod. It returned both athletes — one
  honoring `America/Los_Angeles`, one defaulting to UTC — and the
  `EXTRACT(HOUR FROM now() AT TIME ZONE tz) = 6` gate evaluated correctly.
- **Trigger dependencies:** confirmed `training_logs` has all five columns
  the trigger function references (`id, user_id, workout_type,
  workout_date, cleaned_notes`).
- **Surface shape:** confirmed `athlete_state.user_id` is `NOT NULL`, one
  row per athlete (the right candidate source).

Plpgsql function bodies (`net.http_post`, `vault.decrypted_secrets`,
`cron.*`) are not resolved at `CREATE FUNCTION` time, so their objects only
need to exist at call time in prod (they do). The extension guards
(`pg_cron` in a DO/EXCEPTION block) match the existing weather-cron pattern.

## Apply runbook (for the team — prod stays a `db push`)

Per CLAUDE.md rule #9, nothing here was applied to prod via MCP. To ship:

1. Commit the four code changes above on a branch; open a PR.
2. `supabase migration list --linked` — repo and remote must still agree
   line-for-line (the three new files are the only pending additions beyond
   the two already-pending `20260615*` repo migrations).
3. `supabase db push --dry-run` — expect exactly the pending set, ending
   with `20260615210000`, `20260615220000`, `20260615230000`.
4. *(Optional, recommended if Pro is enabled)* create a real preview branch
   and run the push there first.
5. `supabase db push`.
6. Deploy the `coaching-daily-read` edge function.
7. Verify in prod:
   - `select to_regclass('public.athlete_settings');` → not null.
   - `select to_regproc('public.enqueue_daily_reads');` → not null.
   - `select count(*) from cron.job where jobname='enqueue-daily-coaching-reads';` → 1.
   - Trigger check from the workout-trigger migration footer → 2 rows.
   - `select enqueue_daily_reads();` then inspect `daily_read_dispatch_log`.

## Remaining follow-ups (not blocking the Daily Read unblock)

- **Repoint the SETTINGS edge-readers** off `user_profiles` onto
  `athlete_settings`: `fetch-workout-weather` (3 sites),
  `post-run-reconciliation`, `reconcile-log`, and `weekly-coaching-report`'s
  settings fields. They currently soft-fail to "no profile row"; now there's
  a real table to read.
- **iOS / web write path:** add a writer that populates
  `athlete_settings.timezone` from the device, and repoint the web settings
  page. Until then every athlete resolves to UTC (acceptable default).
- **Retire the workaround tombstones** in `LocationProvider.swift`,
  coach-portal `athletes/page.tsx`, and the `fetch-workout-weather` try/catch
  once their reads move to `athlete_settings`.
- **STATE / EVENT call sites** (the `_shared/profile.ts` mutators, attribute
  readers) remain on the audit's later phases — out of scope here.

# Quarantined migrations

Files moved out of `supabase/migrations/` because they must NOT be applied
as-is, but their content is still referenced by open work.

## RESOLVED 2026-06-15 — user_profiles ghost table + Daily Read automation

The three files that used to live here —
`20260128152000_user_profile.sql`,
`20260519110000_daily_coaching_reads_cron.sql`, and
`20260519120000_daily_coaching_reads_workout_trigger.sql` — have been
**removed**. The "user_profiles doesn't exist in prod" P0 was resolved by
NOT resurrecting the mixed `user_profiles` table. Instead:

- A dedicated SETTINGS surface, `athlete_settings` (timezone + home_lat /
  home_lon / preferred_run_time), was created in
  `supabase/migrations/20260615210000_create_athlete_settings.sql`.
- The Daily Read cron + workout-trigger were repointed off `user_profiles`
  onto `athlete_state` (candidate athletes) + `athlete_settings` (timezone),
  re-stamped, and moved back into `supabase/migrations/`:
  - `20260615220000_daily_coaching_reads_cron.sql`
  - `20260615230000_daily_coaching_reads_workout_trigger.sql`
- The `coaching-daily-read` edge function's timezone lookup was repointed to
  `athlete_settings`.

See `docs/migration-ledger-reconciliation-2026-06-11.md` (Step 3) and
`outputs/profile-table-audit-2026-05-22.md` for the full history, and
`outputs/user-profiles-ghost-table-resolution-2026-06-15.md` for the apply
runbook + remaining follow-ups (the SETTINGS edge-function readers in
fetch-workout-weather / post-run-reconciliation / reconcile-log still need
repointing; the STATE/EVENT call sites remain on the audit's later phases).

## Still quarantined

### 20260306_create_weekly_coaching_reports.sql

### 20260312_coach_training_plans.sql

These two predate the 2026-06-11 reconciliation and remain quarantined under
their original disposition. Do not move them back without checking them
against prod (`supabase migration list --linked`) first.

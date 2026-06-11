# user_profiles decision memo — 2026-06-11

**Decision needed:** what to do about the `user_profiles` table that never
made it to prod (root cause: malformed migration filename, see
`docs/migration-ledger-reconciliation-2026-06-11.md`). Now a **feature
blocker**: the Daily Read cron + workout-trigger migrations are quarantined
because they reference `user_profiles.timezone`.

**Recommendation: Option C — never create `user_profiles`; route settings
through the existing `user_preferences` table.**

## Evidence

- The January schema (quarantined) is three tables in one coat: athlete
  attributes (PRs/paces/mileage), injuries, and device/location settings.
  The 2026-05-22 audit already routes those to STATE (`athlete_state`),
  EVENT (event log / `injuries`), and a SETTINGS surface respectively —
  i.e. the long-term plan **already sunsets `user_profiles`**. Creating it
  now means creating a table whose own roadmap deletes it.
- Every live consumer is defensive already: web coach-portal and iOS
  LocationProvider switched sources (tombstone comments); the 4 edge
  functions guard reads behind try/catch. Nothing breaks by never creating
  the table.
- What the blocker actually needs is ONE per-athlete value: `timezone`,
  joinable from SQL (the cron's 06:00-local-window scan).
- `user_preferences` **exists in prod** (since `20260605234436`):
  `(user_id TEXT, key TEXT, value JSONB, updated_at)`. Timezone fits as
  `key = 'timezone'`, queryable from the cron via
  `(SELECT value->>'tz' FROM user_preferences WHERE user_id = ... AND key = 'timezone')`.

## Options considered

- **A. Fix the January migration and apply it.** Rejected: 5-month-old
  schema, mixed concerns, conflicts with the audit's STATE/EVENT/SETTINGS
  split, and the audit's own end-state drops the table.
- **B. New `athlete_settings` table** (audit's Phase 5f option 1, ~2 days).
  Viable but redundant now — `user_preferences` shipped (June 5) after the
  audit was written and IS the dedicated settings surface.
- **C. `user_preferences` KV (recommended).** Zero new schema. Work:
  1. Rewrite the two quarantined daily-reads migrations to read timezone
     from `user_preferences` (drop the `ALTER TABLE user_profiles` line;
     swap the lookup; default `'UTC'` when the row is absent). Re-stamp,
     move back into `supabase/migrations/`, branch-test, push.
  2. iOS: on app start / settings change, upsert
     `user_preferences(user_id, 'timezone', '{"tz":"<IANA>"}')` —
     `TimeZone.current.identifier`. Until that ships, athletes without the
     row get 06:00 UTC reads (acceptable degraded mode).
  3. Weather's `home_lat/home_lon/preferred_run_time` reads keep their
     try/catch fallbacks; migrate them to `user_preferences` keys
     opportunistically (audit Phase 5f scope).
  4. Web settings page repoints to `auth.users` + `user_preferences`.
  5. Delete the quarantined `20260128152000_user_profile.sql` once 1-2
     land; close the audit's "SETTINGS surface decision" as resolved.

## Effort

Option C: ~half a day for the migrations rewrite + push (unblocks Daily
Read), ~half a day for the iOS preference write. The audit's STATE/EVENT
migration phases (5a-5e) proceed independently and are unaffected.

## What this closes

- The user_profiles P0 (by deciding the table never ships).
- The Daily Read automation blocker (cron + workout trigger).
- The audit's open Phase 5f question (SETTINGS surface = `user_preferences`).

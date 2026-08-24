# Quarantined migrations

Files moved out of `supabase/migrations/` because they must NOT be applied
as-is, but their content is still referenced by open work.

## 20260128152000_user_profile.sql

The origin of the "user_profiles doesn't exist in prod" P0. Its original
filename (`20260128_152000_user_profile.sql`) had a malformed timestamp that
parsed as version `20260128` — colliding with the already-applied
`fix_vector_search` — so the CLI silently skipped it for 5 months while
web, iOS, and one edge function accumulated defensive workarounds
(see outputs/profile-table-audit-2026-05-22.md).

Do not move it back. The January schema almost certainly no longer matches
the app. Phase 5 of the Maya roadmap decides: rewrite as a fresh
current-schema migration, or drop the table concept and remove the
workarounds. See docs/migration-ledger-reconciliation-2026-06-11.md, Step 3.

## 20260519110000_daily_coaching_reads_cron.sql / 20260519120000_daily_coaching_reads_workout_trigger.sql

The Daily Read automation pair — confirmed unapplied in prod and BLOCKED on
the user_profiles decision (the cron migration does
`ALTER TABLE user_profiles ADD COLUMN timezone`; the trigger reads that
column). Quarantined 2026-06-11 so an accidental `db push` can't apply them
half-broken. Move back (with fresh timestamps) in the same change that
creates user_profiles. Until then the deployed `coaching-daily-read`
function only runs on demand.

## 20260306_create_weekly_coaching_reports.sql / 20260312_coach_training_plans.sql

The same malformed-timestamp class as the `user_profiles` P0 above, but
failing the opposite way. Both filenames lack a time component, so they
parse as versions `20260306` and `20260312`. Neither is in prod's ledger
(which has `20260306100000` and `20260312200000` — different migrations),
so the CLI considers them unapplied and would try to RUN them.

Every object they create already exists in production — verified
2026-08-24: `weekly_coaching_reports`, `coach_profiles`, `workout_templates`,
`plan_templates`, `athlete_plan_subscriptions`,
`coach_athlete_relationships`, and all four timestamp/counter functions.

So `supabase db push` from this repo FAILED before it reached anything new.
`CREATE POLICY` has no `IF NOT EXISTS` in Postgres, and
`20260312_coach_training_plans.sql:21` creates `idx_coach_profiles_user`
with no guard at all — that index is already there. The push aborted on the
first of these, which is why the four 20260823* security migrations could
not ship. That included the `delete_user_account` erasure fix, so real
deletion requests kept silently retaining data while the deploy path was
blocked by two files nobody had run in months.

Quarantined 2026-08-24 rather than repaired: the objects are already live,
so re-applying is a no-op at best and a conflict at worst. If the repo is
ever reconciled against prod (see docs/repo-prod-drift-2026-08-24.md), the
authoritative definitions should come from a schema dump, not from these.


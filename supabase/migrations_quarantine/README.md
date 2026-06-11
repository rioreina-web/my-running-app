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

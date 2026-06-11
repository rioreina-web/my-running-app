# Rollback runbook

Phase 3 of docs/ops-delivery-roadmap-2026-06-10.md. Read this BEFORE you
need it; rehearse once on a Supabase preview branch.

The invariant that makes rollback possible at all: **prod corresponds to a
git SHA** (enforced by the Deploy workflow + drift detector). If you don't
know the last-good SHA, find it in the Deploy workflow run history.

## A. Edge function rollback (bad deploy, functions misbehaving)

Supabase has no server-side "revert to previous version" — rollback is
**redeploy from the last-good SHA**:

```bash
git checkout <last-good-sha>
supabase functions deploy <name> --project-ref aqdijapxmjqaetursrde   # one function
# or all functions: supabase functions deploy --project-ref aqdijapxmjqaetursrde
git checkout -            # return to your branch
```

Then re-run the smoke tests: `SUPABASE_URL=... SUPABASE_ANON_KEY=... bash .github/scripts/post_deploy_smoke.sh`

Notes:
- Deploying an old SHA does NOT undo migrations — if the bad deploy paired
  a function with a migration, do section B first (functions that depend on
  schema that no longer matches will keep failing).
- A function deleted by mistake is restored the same way: its source at the
  last-good SHA, `supabase functions deploy <name>`.

## B. Migration rollback (bad migration applied)

Migrations are **append-only** (CLAUDE.md hard rule #5). Never edit or
delete an applied migration; never touch `supabase_migrations.schema_migrations`
by hand. Rollback = **compensating migration**:

1. Write a NEW migration `YYYYMMDDHHMMSS_revert_<name>.sql` that undoes the
   damage (DROP the new table, restore the previous CHECK constraint,
   recreate the old function body, etc.). The original migration's header
   comment should state its own revert path — write that header when
   authoring any risky migration.
2. Apply via `supabase db push` (the only path migrations reach prod).
3. Data loss caveat: a compensating migration restores SCHEMA, not data.
   If the bad migration destroyed data (dropped a column, bad UPDATE),
   restore from a Supabase backup (Dashboard → Database → Backups — daily
   on the current plan) into a temporary instance and copy the affected
   rows back. This is the slow path; budget hours, not minutes.

## C. Full bad-release rollback (function + migration shipped together)

Order matters:

1. Compensating migration first (B) — restore the schema the old functions
   expect.
2. Redeploy functions from last-good SHA (A).
3. Smoke tests.
4. Write the incident note: what shipped, what broke, which check should
   have caught it. Add the missing check to CI or the smoke script.

## D. When NOT to roll back

- Drift-detector failures: fix forward via the Deploy workflow (drift means
  prod diverged from repo — redeploying HEAD usually IS the fix).
- A single misbehaving LLM prompt: prompts live in
  `_shared/prompts/<name>.v<k>.ts` — ship a revert PR of just that file
  (eval gate will require its cassette), don't roll back the world.

## Rehearsal checklist (do once, on a preview branch)

- [ ] `supabase branches create rehearsal` (or via dashboard)
- [ ] Apply a throwaway migration to the branch; write + apply its
      compensating migration
- [ ] Deploy one function to the branch from an old SHA, then from HEAD
- [ ] Delete the branch
- [ ] Record actual timings here: ............................

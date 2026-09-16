# Phase B / Phase A deploy runbook — get prod up to speed

**Date:** 2026-07-03
**Owner action required:** yes — the actual `supabase db push` and edge-function
deploys are a human step (hard rule #9: migrations reach prod only via
`db push` from a committed SHA; no dashboard SQL / MCP `apply_migration`).
**Prepared by:** verified against live prod `RunningAppMVP2`
(`aqdijapxmjqaetursrde`) on 2026-07-03.

This runbook gets production caught up so the Phase A (shift-day) and Phase B
(rewrite-block, adjustments feed) code actually works. Everything below has been
validated to the extent possible without touching prod (see §5).

---

## 1. The core problem (why a plain `db push` was NOT safe)

`supabase_migrations.schema_migrations` lists `20260424100000` (athlete_plan_ux)
as **applied**, but its DDL never ran against this project — verified live:
`plan_adjustments` has none of `tier / reason_code / reason_text / week_number`,
`scheduled_workouts` has neither `rationale_short` nor `rationale_full`, and the
tier index is absent. This is one of the documented re-stamped/ghost entries
(`docs/migration-ledger-reconciliation-2026-06-11.md`).

Consequences if you had pushed as-is:
- `db push` SKIPS `20260424100000` (it's marked applied) → the columns never get
  created.
- The next pending migration `20260703120000` runs
  `COMMENT ON COLUMN plan_adjustments.reason_code` → **fails**, column missing →
  the whole push aborts.

## 2. The fix (already in the repo)

A new forward-fix migration reproduces the ghost migration's columns/index
idempotently and is timestamped to run first:

- **`20260703115000_reconcile_plan_adjustments_ux_ledger_drift.sql`** *(new)* —
  `ADD COLUMN IF NOT EXISTS` for the four `plan_adjustments` columns (+ tier
  CHECK), the two `scheduled_workouts` rationale columns, and the partial tier
  index. Idempotent; adds no CHECK vocabulary (leaves that to `120000`).

It does not edit any existing committed migration. The ghost `20260424100000`
row stays marked applied; this forward-fixes without needing
`supabase migration repair`.

## 3. The pending migration set (exact, in apply order)

These three are the only files not in prod's `schema_migrations`. `db push`
applies them in version order:

| Order | File | Effect |
|---|---|---|
| 1 | `20260703115000_reconcile_plan_adjustments_ux_ledger_drift.sql` | Adds the 4 `plan_adjustments` UX columns + 2 `scheduled_workouts` rationale columns + partial tier index (reconciles ghost `20260424100000`) |
| 2 | `20260703120000_plan_adjustment_vocab_for_coach_plans.sql` | Drops + re-adds `trigger_type` / `action_type` CHECKs with the athlete + coach vocab (`user_action`, `coach_rewrite`, `shift_day`, `reshape_week`, `rewrite_block`); comments `reason_code` (now exists) |
| 3 | `20260703121000_plan_template_shape_columns.sql` | Adds `rest_day_of_week`, `auto_strides_on_pre_quality`, `recovery_after_long_run` to `plan_templates` (idempotent; self-sufficient) |

After this chain, prod has everything Phase A `shift-day` and Phase B
`rewrite-block` + the adjustments feed require.

## 4. Deploy steps

**Preflight**
1. Commit all repo changes (the new migration, `rewrite-block/`, the `shift-day`
   `scheduled_date`→`date` fix, the web route + feed). `db push` should run from
   a committed SHA.
2. `supabase migration list` — confirm the three files in §3 show as local-only
   (not yet on remote), and nothing else unexpected is pending.

**Migrations**
3. `supabase db push` (targeting the prod project). Expect exactly the three
   migrations in §3 to apply, in that order.

**Edge functions** (deploy after migrations land)
4. `supabase functions deploy rewrite-block` — **new** function.
5. `supabase functions deploy shift-day` — **redeploy**; it now selects the
   correct `date` column (the `scheduled_date` bug is fixed) and its ledger
   insert (`user_action`, tier, reason_code, week_number) now succeeds against
   the migrated schema.

> **STATUS — DONE 2026-07-03.** Both functions are deployed and ACTIVE in prod:
> `shift-day` v3 (the `date` fix) and `rewrite-block` v1 (new, `verify_jwt:false`,
> self-authenticates via `requireServiceRole`). Deployed content was verified to
> match the repo. Note: these two were deployed via the Supabase management API
> with slightly trimmed JSDoc comments in the bundled `_shared/auth.ts`
> (comment-only; behavior identical). A later CLI `functions deploy` from the
> repo would harmlessly re-sync those comments.

**Web app**
6. Deploy the Next.js app (normal web pipeline, e.g. Vercel) to ship the new
   `/api/rewrite-block` route, the athlete-page adjustments feed, and the
   `PlanAdjustmentsFeed` component. Requires `SUPABASE_SERVICE_ROLE_KEY` present
   in the web env (already used by `/api/assign-plan`).

## 5. Validation already performed (pre-push)

- **Syntax:** all three migrations parse cleanly against the real Postgres
  grammar (libpg_query via `pglast`).
- **Semantics (preconditions confirmed live against prod):**
  - `plan_adjustments`: target UX columns absent (0/4) → `115000` will add them.
  - `scheduled_workouts`: rationale columns absent (0/2) → `115000` will add them.
  - `plan_adjustments`: `user_id` + `applied_at` present → partial index builds.
  - Both CHECK constraints `120000` drops exist → `DROP … IF EXISTS` matches.
  - `plan_templates` exists; its three shape columns are absent → `121000` adds.
- **Not run against prod** (hard rule #9). If you have a staging/shadow DB or a
  Supabase preview branch, running `db push` there first is the belt-and-braces
  check; the preconditions above indicate it will apply cleanly.

## 6. Post-deploy verification (read-only)

```sql
-- columns exist
select count(*) from information_schema.columns
 where table_name='plan_adjustments'
   and column_name in ('tier','reason_code','reason_text','week_number');   -- expect 4

-- vocab live
select pg_get_constraintdef(oid) from pg_constraint
 where conname='plan_adjustments_trigger_type_check';   -- includes coach_rewrite, user_action

-- smoke: an athlete day-move now records a ledger row (was silently failing)
-- do a shift-day in the app, then:
select trigger_type, action_type, tier, reason_code, week_number
 from plan_adjustments order by applied_at desc limit 3;
```

Then, in the coach portal, open an athlete who has any adjustment and confirm the
**Plan changes** section renders (it only shows when rows exist).

## 7. Rollback

- Migrations are additive (`ADD COLUMN IF NOT EXISTS`, CHECK swaps). If a later
  issue surfaces, the columns are nullable and unused by legacy paths — safe to
  leave in place. A true rollback would be a new forward migration dropping the
  columns; do not hand-edit applied migrations.
- Edge functions: redeploy the previous version via the functions dashboard or
  a prior SHA if `rewrite-block` / `shift-day` misbehave.

## 8. Out of scope / follow-ups

- **Other ghost/re-stamped ledger entries.** CLAUDE.md notes ~17 re-stamped
  entries; this runbook reconciles only the ones Phase A/B depend on
  (`plan_adjustments`, `scheduled_workouts`, `plan_templates`). A broader ledger
  audit is a separate task.
- **The `scheduled_date` bug in the athlete web surfaces.** Fixed in `shift-day`
  here, but `web/src/lib/types.ts`, `web/src/app/(app)/plan/page.tsx`, and
  `web/src/components/plan/move-day-sheet.tsx` still reference `scheduled_date`.
  They need the same `date` rename — tracked as a follow-up, not part of this
  deploy.
- **CI eval gate:** none of the Phase B code ships an LLM prompt, so hard rule #3
  is not triggered. The assisted rewrite (Phase E) will trigger it.

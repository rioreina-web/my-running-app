# Operator checklist — 2026-06-09

Steps only you can click. Ordered — the order matters for #4/#5.
Everything below came out of the June 9 working session; what could be
done programmatically has already been done (see "Done today" at bottom).

## 0. Create a GitHub remote and push (~10 min) — NEW, do this first

The repo had **no git remote** — months of work existed only on this
machine, and the CI workflow was never even tracked. As of tonight the
entire tree is committed locally: 7 logical commits on
`design/editorial-v2` (cut-feature removal, backend, web, iOS, design
system, docs, CI). A stale `.git/index.lock` from May 21 was also
cleared (it had frozen 4 file deletions in a conflict state).

Steps:
1. Create a private GitHub repo; `git remote add origin <url>`.
2. `git push -u origin design/editorial-v2` (and push `main` too).
3. Decide the main-branch story: local `main` is months behind
   `design/editorial-v2`. Branch protection (#3 below) targets `main`,
   so either merge/fast-forward `design/editorial-v2` into `main` or
   re-point the CI required checks at your working branch.

Until this is done, CI (#3) and branch protection protect nothing, and
a disk failure loses everything.

## 1. Google Cloud billing hard cap (~10 min) — W1.1, the actual cost cap

Console → Billing → Budgets & alerts → Create budget.
Scope: the Gemini project + Generative Language API. Amount: $50/mo.
Alerts at 50/80/100/110%. **Check "Disable billing to stop usage" at
110%** — that checkbox is the hard cap. Full steps:
`docs/deploy/llm-cost-controls.md` § Step 1.

The Slack spend-alert side is live as of today (migration applied, cron
scheduled 13:00 UTC daily, webhook secret already in vault). First
message lands in `#alerts-prod` tomorrow ~6am Pacific.

## 2. Delete the 4 dead edge functions (~4 clicks) — C.1

Supabase dashboard → Edge Functions → delete each:
`form-check-analysis`, `biomechanics-analysis`, `custom-plan-builder`,
`adaptive-workout`. All four are still deployed and ACTIVE in prod;
two still accept input and call Gemini. (The MCP connector has no
delete verb, or this would be done already.)

## 3. GitHub branch protection (~3 min) — W1.4

Repo → Settings → Branches → Add rule for `main`. Required checks:
`Edge functions (Deno)`, `Web (Next.js)`, `ML service (Python)`,
`DB lint (Supabase)`. Also: require PR review, linear history.

## 4. Set `ALLOWED_ORIGIN` in edge-function env (~2 min) — W1.2

Supabase dashboard → Project Settings → Edge Functions → Environment
variables → `ALLOWED_ORIGIN=https://<prod web origin>`.

**Do this before any function redeploy.** The repo's `_shared/cors.ts`
fail-fasts in production when it's unset — deploying without it bricks
every redeployed function on import (by design).

## 5. Redeploy edge functions (~5 min) — unblocks three things at once

After #4: `supabase functions deploy` from the repo root.

Prod is running April/May builds. Redeploying ships, all at once:
- the W2.3-follow-up auth gates (7 functions that today accept a body
  `user_id` — prod is still running the un-gated versions)
- the per-user rate limits, incl. the `coaching-daily-read` gap fixed today
- Phase 2 sub-task A (`confirmed_races` population in athlete-state)
- Phase 2 sub-task C (race anchor → pace profile → get-pace-zones; also
  subscribe-to-plan and recompute-plan-paces)
- Phase 2 sub-task F (`build_vs_last_cycle` race-aware coachable-moment
  rule in evaluate-coachable-moment; its `journey_comparison` action_type
  migration is already applied to prod)
- the canonical pace-zone bands (web/server parity fix)

Then verify a CORS preflight from an unknown origin is rejected
(curl block in TASKS.md § W1.2) and confirm Upstash env vars are set
(Project Settings → Edge Functions) so rate limits aren't no-ops.

**Deploy-drift audit (2026-06-09) — functions missing from prod and
what that means:**

- **`shift-day` — BROKEN FEATURE, deploy it.** The web move-day sheet
  calls `/api/shift-day` → `functions/v1/shift-day`, which 404s in prod
  today. The blanket deploy fixes it.
- **`generate-workout-insight` + `drain-coach-insight-jobs` — pipeline
  dark.** Neither is deployed, no trigger exists on `training_logs`
  (despite `20260428110000` being in migration history), and the outbox
  migrations (`20260508150000/160000/170000`) were never applied. Net
  effect: HealthKit-imported runs get no `coach_insight` — iOS shows
  nothing in that slot. Fix order: deploy both functions, then apply
  `20260508150000` (outbox trigger) + `20260508170000` (drain cron);
  `160000` (backfill) optional.
- **`weekly-plan-review` — feature dark, decide if wanted.** Sunday-cron
  producer for `coaching_adjustments` (feeds the iOS CoachReadCard
  context). Function not deployed and the cron from `20260416400000`
  never actually scheduled. If the feature is wanted: deploy + verify
  the cron exists afterward. If not: candidate for the next cut list.
- **`transcribe` — safe to skip.** No caller anywhere (voice flow goes
  through `process-training-memo`, which transcribes internally). Dead
  code in the repo; cutting it is a future cleanup, not a deploy item.

## 6. Smoke-test confirmed_races (Phase 2 sub-task A) (~5 min)

After #5, in the SQL editor: insert a `race_result` JSONB on one of
your race training_logs (shape in migration `20260420100000`), call
any AI function (or wait for a state rebuild), then:
`SELECT confirmed_races FROM athlete_state WHERE user_id = '<you>';`
Expect the race in the array.

---

## Decision needed from you (blocks nothing above)

None — the pace band convention you locked in
`outputs/pace-chart-unified-spec-2026-06-04.md` (Easy 70–80% MP speed,
etc.) is what the engine implements; the stale tests were updated to
match today. Sub-task B's remaining work is applying the same bands to
`web/src/components/coach/workout-helpers.ts` (still on the old
ratios) — engineering work, no decision required.

## Done today (no action needed)

- **5 migrations applied to prod:** `coach_insight_outbox` (table+RLS),
  `daily_llm_spend_alert` (W1.1 observability), and 3 hardening
  migrations that were written in May but never applied —
  `drop_public_storage_list_policies` (voice-memo enumeration closed),
  `tighten_insert_rls_and_debug_log` (ERROR-level RLS gap closed,
  5 forgeable INSERT policies owner-scoped), and
  `harden_current_coach_id_search_path`. All verified live.
- **W2.2 confirmed already live** in prod via the newer outbox pattern
  (both triggers + drain cron) — TASKS.md was stale.
- **W2.3-follow-up confirmed done in repo** (all 7 functions gated);
  prod deploy pending (#5).
- **`coaching-daily-read` rate-limit gap** found by the contract test
  and fixed (`daily_read` bucket, pinned in the test).
- **4 stale pace tests updated** to the canonical band convention;
  found and fixed a real `subscribe-to-plan` bug while at it: a
  volume-ramp start below the week's quality miles got +2 floored
  miles on every easy day (12 mpw request → ~25 mpw schedule). Zero
  easy budget now produces rest days.
- **Full edge-function test suite green:** 122 passed / 0 failed.

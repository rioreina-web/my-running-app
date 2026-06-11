# Operations & Delivery Roadmap — 2026-06-10

> **Status update 2026-06-11:**
> - 0.1 largely DONE (remote `github.com/rioreina-web/my-running-app` exists, `fix/ci-green` synced, stale index.lock cleared). Remaining: merge `fix/ci-green` → `main` story.
> - 0.2 DONE (jsr→esm.sh sweep committed in d886977).
> - 0.3 largely DONE (shift-day, drain-* jobs, parse-workout-shorthand, generate-workout-insight deployed to prod 2026-06-10).
> - 0.4 3 of 4 DONE: `training-analysis` (Gemini 2.5), `injury-analysis` (Gemini 2.0), `fitness-predictor` deleted from prod — both Gemini callers eliminated. Remaining: `supabase functions delete coaching-feedback --project-ref aqdijapxmjqaetursrde` (harmless meanwhile: DB-only, backing tables don't exist).
> - 0.5 (GCloud hard cap) and 0.6 (Upstash verify) still open.
> - **Second pass, same day:** 1.1 DONE analytically (17 renames executed, both prod-only migrations recovered, user_profile quarantined; drift check vs live prod: 96 migrations in sync / 5 allowlisted, 35 functions in sync / 2 allowlisted). 1.3 DONE (deploy.yml, manual trigger). 2.2 DONE (drift-detector.yml + scripts, verified against live prod). 2.3 DONE (eval-coverage gate in CI). 3.1 DONE (post_deploy_smoke.sh wired into deploy). 3.2 DONE on paper (docs/deploy/rollback-runbook.md — rehearsal pending). Remaining to reach the Phase-4 flip: add GitHub repo secrets (SUPABASE_ACCESS_TOKEN, SUPABASE_DB_PASSWORD, SUPABASE_PROJECT_REF, SUPABASE_URL, SUPABASE_ANON_KEY), branch protection (2.1), close eval stubs (2.4), rollback rehearsal, then change deploy.yml trigger to push:main + branch-per-PR (4.x).
> - 1.1 STARTED: full divergence mapped + exact fix plan in `docs/migration-ledger-reconciliation-2026-06-11.md`; prod-only `harden_outbox_rpcs_and_pricing_rls` recovered into the repo. Bonus root cause found: `20260128_152000_user_profile.sql` malformed timestamp = the user_profiles P0.

**Goal:** Operations & delivery from 4/10 → 10/10.
**Companion doc:** operator checklist (items referenced as `checklist #N`).
**Audience:** future sessions / handoff model. Execute top to bottom; phases are strictly ordered.

## Locked decisions

1. **True CD** — merge to `main` auto-deploys to prod once CI is green. No human gate.
2. **Supabase branching** for staging — ephemeral DB+functions branch per PR; no long-lived staging project.

Consequence: **auto-deploy is the LAST switch flipped** (Step 4), after all safety nets exist. Everything through Step 3 is valuable even if the switch is never flipped.

## Definition of 10/10 (the seven properties)

1. **Reproducible** — prod (functions + migrations + config) fully derivable from a git SHA; zero manual clicks.
2. **Drift-proof** — automated check proves repo HEAD == prod; alerts on mismatch.
3. **Safe to ship** — every merge runs tests + evals + db-lint; failures block; rollback is one tested command.
4. **Cost-bounded** — caps that physically stop spend, not just alert.
5. **Observable** — errors and cost anomalies page before users notice.
6. **Isolated blast radius** — changes validate in a branch/preview before prod.
7. **Config-clean** — secrets inventoried; prod out of dev mode.

Current state (2026-06-10): properties 0–2 and 6 absent. Score ≈ 4/10. Root cause of nearly all symptoms: **deploys are manual, so drift is inevitable.**

## Target pipeline (what "done" looks like)

**On every PR:**
- CI: tests (122 edge + web + ML + gated iOS) + db-lint + eval-coverage gate
- Spin up Supabase preview branch → `db push` migrations + deploy functions to it
- Smoke-test against the preview branch
- PR is green only if a real, isolated copy of prod accepted the change

**On merge to main:**
- CI re-runs → auto `db push` + deploy all functions to prod
- Post-deploy smoke: CORS-reject check, `confirmed_races` check, health ping
- Smoke fails ⇒ auto-revert function versions + page operator
- Preview branch torn down

---

## Phase 0 — Stop the bleeding (this week) → ~6/10

Pure risk reduction. No architecture. Auto-deploy: OFF.

| # | Task | Severity | Effort | Notes |
|---|------|----------|--------|-------|
| 0.1 | Push repo to a remote; resolve `main` story (local `main` is months behind `design/editorial-v2`); clear stale `.git/index.lock` | **P0 — total-loss risk** | S | checklist #0. Until this, a disk failure erases months of work. |
| 0.2 | Commit the 23 working-tree edits (incl. the jsr→esm.sh import sweep) | P0 | S | Prod must correspond to a SHA. |
| 0.3 | Close current drift: deploy the 7 dark functions + their migrations (the paused deploy task). Fixes shift-day 404. | P0 | M | Prod currently runs April/May builds. |
| 0.4 | Delete the 4 dead ACTIVE functions (2 still call Gemini) | P0 | S | checklist #2. Kills live cost + attack surface in one move. |
| 0.5 | Google Cloud billing **hard cap** with "disable billing at 110%" checked | P0 | S | checklist #1. The only physical cost stop. Currently a manual TODO. |
| 0.6 | Verify Upstash env vars in prod | P1 | S | Otherwise rate limits are silent no-ops. |

**Verify:** `git push` succeeds to remote; `supabase functions list` shows no dead functions; shift-day endpoint returns 200; billing cap visible in GCloud console.

## Phase 1 — Reproducible + automated deploys (1–2 wks, the keystone) → ~7.5/10

Auto-deploy: OFF (workflow exists, manually triggered).

| # | Task | Severity | Effort | Notes |
|---|------|----------|--------|-------|
| 1.1 | **Reconcile the migration ledger.** Repo and prod histories have diverged — prod re-stamped timestamps (e.g. repo `20260508140000_coach_insight_outbox` → prod `20260609233455`). Get `supabase migration list` clean. | **P0 — blocks everything downstream** | M–L | The non-obvious landmine. Until clean, `db push` can misfire. |
| 1.2 | Make `supabase db push` the ONLY path migrations reach prod. No more dashboard/MCP ad-hoc applies. | P0 | S (policy) + doc | Write it into CLAUDE.md / operator checklist as a hard rule. |
| 1.3 | GitHub Actions deploy workflow: functions + `db push`, parameterized by target. **Trigger: manual (`workflow_dispatch`) for now.** | P0 | M | This is the keystone artifact. Step 4 just changes its trigger. |
| 1.4 | Pin runtime imports (versions or vendored import map) | P1 | M | The jsr→esm.sh sweep was a symptom of import instability; a deploy must not break on a moved dependency. |

**Verify:** `supabase migration list` shows repo == prod; a manual workflow run produces a prod identical to repo HEAD (function SHAs match).

## Phase 2 — Guardrails against regression (1–2 wks) → ~8.5/10

Auto-deploy: OFF.

| # | Task | Severity | Effort | Notes |
|---|------|----------|--------|-------|
| 2.1 | Branch protection on `main`: 4 CI jobs required, PR review, linear history | P0 | S | checklist #3. |
| 2.2 | **Drift detector:** scheduled job diffs prod function SHAs + migration list vs repo HEAD; alerts on mismatch | P1 | M | Drift becomes a page, not a 6-weeks-later audit finding. |
| 2.3 | Enforce the eval rule in CI: PR touching a prompt fails without a cassette | P0 | M | House rule is "no prompt change without evals"; coverage is 4 cassettes / 10 stubs. |
| 2.4 | Close the 10 eval stubs | P1 | L | Prioritize core coaching prompts first. |

**Verify:** a test PR touching a prompt without a cassette is blocked; intentionally deploy one function out-of-band → drift detector fires.

## Phase 3 — Safety nets: smoke + rollback (1–2 wks) → ~9/10

Auto-deploy: OFF. These are the prerequisites for flipping the switch.

| # | Task | Severity | Effort | Notes |
|---|------|----------|--------|-------|
| 3.1 | Post-deploy smoke tests in CI: CORS-reject check, `confirmed_races` check, health ping (checklist #5–6, automated) | P0 | M | Run by CI, never by hand. |
| 3.2 | **Tested rollback runbook.** Functions: one-command version revert. Migrations: **compensating migration** (ledger is append-only — document this explicitly). | P0 | M | Actually rehearse it once against a preview branch. |
| 3.3 | Auto-revert on smoke failure + page operator | P1 | M | Wire 3.1 + 3.2 together in the deploy workflow. |

**Verify:** kill a function on purpose in a preview branch; pipeline detects, reverts, alerts.

## Phase 4 — Flip the switch (days) → ~9.5/10

| # | Task | Severity | Effort |
|---|------|----------|--------|
| 4.1 | Change deploy workflow trigger: `workflow_dispatch` → `push: main`. **True CD live.** | P0 | S |
| 4.2 | Supabase branch-per-PR: PR opens → preview branch (`create_branch`), migrations + functions deploy there, smoke runs there; merge promotes; branch torn down | P0 | M–L |

**Verify:** open a trivial PR → preview branch appears, smoke passes, merge → prod updates with no human action → drift detector stays green.

After 4.1+4.2, drift is structurally impossible: properties 0, 1, 2, 5 all hold by construction.

## Phase 5 — The last half-point (ongoing) → 10/10

| # | Task | Severity | Effort | Notes |
|---|------|----------|--------|-------|
| 5.1 | Error tracking: edge functions + web + iOS crash reporting | P1 | M | Today the only signal is one daily LLM-spend Slack alert. |
| 5.2 | Take Supabase prod out of dev mode | P1 | S | |
| 5.3 | Secrets inventory + rotation schedule | P1 | M | |
| 5.4 | Finish legal-doc TODOs | P2 | M | Delivery-ready, not just deploy-ready. |

## Related correctness debt (tracked, not blocking the pipeline)

Not operations per se, but the pipeline makes fixing these safe:

- `athlete-state.ts` (1481 LOC) acknowledged P0 bugs — fix under eval coverage once 2.3/2.4 land.
- `user_profiles` missing in prod; workarounds in three layers — needs a reconciled migration (do AFTER 1.1).
- Fitness snapshots not saving — diagnose once error tracking (5.1) exists.

## Score ladder

| Milestone | Score |
|-----------|-------|
| Today | 4 |
| Phase 0 done | ~6 |
| Phase 1 done | ~7.5 |
| Phase 2 done | ~8.5 |
| Phase 3 done | ~9 |
| Phase 4 done (CD live) | ~9.5 |
| Phase 5 done | 10 |

## Hard rules for any session executing this

1. Never apply a migration to prod except via `db push` from a committed SHA (after 1.2).
2. Never edit a prod function via dashboard/MCP once 1.3 exists — change the repo, run the workflow.
3. Do not flip auto-deploy (4.1) before 3.1–3.3 are verified.
4. Migration ledger reconciliation (1.1) comes before ANY new migration work, including `user_profiles`.
5. No prompt changes without a cassette (enforced by 2.3, honored manually until then).

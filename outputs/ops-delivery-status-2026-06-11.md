# Operations & Delivery — State of Play (2026-06-11)

Companion to `docs/ops-delivery-roadmap-2026-06-10.md`. This is an
audit of repo + prod against that roadmap, one day later. Verified
against the live Supabase project (`aqdijapxmjqaetursrde`), the git
tree, and the `.github/` CI artifacts.

## Headline

The roadmap's Phase 0–3 artifacts **largely exist** — CI, deploy
workflow, drift detector, smoke script, rollback runbook, reconciled
migration ledger, expanded eval cassettes. But almost all of it lives
on the **`fix/ci-green` branch and has not landed on `main`**. The
single highest-leverage move is no longer "build the pipeline" — it's
**merge `fix/ci-green` → `main` and push**, which is what actually
turns the built machinery on.

**Effective score today: ~6.5/10** (capability is Phase 2–3; *live on
the default branch* it's closer to Phase 0–1). Merging the branch
jumps it to ~8.5 with no new code.

## The branch problem (read this first)

| Fact | Evidence |
|---|---|
| All ops infra is on `fix/ci-green`, 13 commits ahead of `main` | `git rev-list --count fix/ci-green...main` = 13 |
| `main` has **only `ci.yml`** — no deploy, drift-detector, or record-evals workflow | `git ls-tree origin/main .github/workflows/` |
| Reconciled + new migrations are **not on `main`** (only on the branch) | none of `20260609233455` / `20260611*` present on `origin/main` |
| `fix/ci-green` has **11 commits not pushed to origin** | `git rev-list --count fix/ci-green...origin/fix/ci-green` = 11 |

Two consequences:

1. **The drift detector cannot run.** GitHub fires scheduled
   workflows only from the default branch. `drift-detector.yml` is on
   `fix/ci-green`, so the 06:17/18:17 UTC cron never triggers until
   it's on `main`.
2. **11 commits of work exist only on this machine.** The total-loss
   risk that roadmap 0.1 set out to kill is *partially* back — push
   first, before anything else.

## Phase-by-phase

### Phase 0 — Stop the bleeding → target ~6/10  ·  DONE (with two loose ends)

| # | Task | Status |
|---|---|---|
| 0.1 | Remote + `main` story + stale lock | ✅ `origin` exists; `design/editorial-v2` == `main` (no longer ahead); no `index.lock` |
| 0.2 | Commit 23 working-tree edits | ✅ Down to 2 trivial edits (one Swift file) |
| 0.3 | Deploy the 7 dark functions | ✅ `shift-day`, `drain-voice-processing-jobs`, `drain-coach-insight-jobs`, `parse-workout-shorthand`, `generate-workout-insight` all ACTIVE in prod |
| 0.4 | Delete 4 dead ACTIVE functions | ⚠️ Partial — biomechanics / form-check / custom-plan / adaptive are gone, but `coaching-feedback` is still ACTIVE-but-dead in prod (allowlisted pending `supabase functions delete`), and a **new undocumented `env-probe` function** is live in prod with `verify_jwt:false` |
| 0.5 | GCloud billing hard cap | ❓ Cannot verify from here — external console. Confirm manually. |
| 0.6 | Verify Upstash env vars in prod | ❓ Likely why `env-probe` was deployed; unverified |

**Loose end — `env-probe`:** it's in prod, not in the repo, and not in
`drift_allowlist_functions.txt`. So the moment the drift detector goes
live it will (correctly) flag it. Either delete it or allowlist it.

### Phase 1 — Reproducible + automated deploys → target ~7.5/10  ·  BUILT, NOT LANDED

| # | Task | Status |
|---|---|---|
| 1.1 | Reconcile migration ledger | ✅ on branch — repo timestamps now match prod (`20260609233455_coach_insight_outbox` etc.); 2 ghost migrations quarantined in `supabase/migrations_quarantine/`; 3 unapplied (`20260611*`) documented in `drift_allowlist.txt`. Repo is exactly 3 migrations ahead of prod, all intentional. **Not on `main`.** |
| 1.2 | `db push` as the only path | ✅ Documented as CLAUDE.md hard rule #9 and enforced in `deploy.yml` header |
| 1.3 | Deploy workflow (manual trigger) | ✅ `deploy.yml` exists, `workflow_dispatch` only. **Not on `main`.** |
| 1.4 | Pin runtime imports | ⚠️ jsr→esm.sh sweep done; explicit version pinning / vendored import map not confirmed |

### Phase 2 — Guardrails → target ~8.5/10  ·  PARTIAL

| # | Task | Status |
|---|---|---|
| 2.1 | Branch protection on `main` (4 checks, review, linear history) | ❌ Not confirmable via API here, and the deploy/drift checks aren't on `main` yet to be *required*. Treat as open. |
| 2.2 | Drift detector | ⚠️ Built (`drift-detector.yml` + `check_function_drift.py` + `check_migration_drift.py` + allowlists) but **won't run** until on `main`; would currently trip on `env-probe` |
| 2.3 | Eval gate in CI | ✅ **Actually live** — `eval-gate` job is in `ci.yml`, which *is* on `main`; `check_eval_coverage.py` blocks prompt PRs without a cassette |
| 2.4 | Close the 10 eval stubs | ⚠️ Progress: 6 cassette dirs now (`coaching-agent-{simple,moderate,complex}`, `injury-analysis`, `process-training-memo`, `reschedule-plan`) vs. 24 prompt files. `record-evals.yml` added. Still well short of full coverage. |

### Phase 3 — Safety nets (smoke + rollback) → target ~9/10  ·  PARTIAL

| # | Task | Status |
|---|---|---|
| 3.1 | Post-deploy smoke in CI | ⚠️ `post_deploy_smoke.sh` exists (health ping + CORS-reject). `confirmed_races` check still manual by design. Wiring into `deploy.yml` to confirm. |
| 3.2 | Tested rollback runbook | ⚠️ `docs/deploy/rollback-runbook.md` exists **but the rehearsal checklist is unchecked** — never actually run against a preview branch. Roadmap requires the rehearsal. |
| 3.3 | Auto-revert on smoke failure + page | ❌ Not wired |

### Phase 4 — Flip the switch  ·  CORRECTLY NOT STARTED

`deploy.yml` trigger is still `workflow_dispatch`. Right call — 3.1–3.3
aren't verified yet, and roadmap hard-rule #3 forbids flipping early.

### Phase 5 — Last half-point  ·  EARLY

- 5.1 Error tracking: ❌ still only the one daily LLM-spend Slack alert.
- 5.2 Prod out of dev mode: ❓ unverified.
- 5.3 Secrets inventory: ✅ doc added (commit `b25757b`).
- 5.4 Legal TODOs: ❌ open.

## Live prod security advisors (new signal, maps to Phase 5 + correctness debt)

`get_advisors(security)` on prod returns **3 ERROR-level** items plus a
stack of warnings:

- **ERROR** — `SECURITY DEFINER` views: `daily_cost_estimate`,
  `daily_usage`, `yesterday_llm_spend` (the cost views run as creator,
  bypassing RLS).
- `debug_coach_log` has RLS enabled but **no policy** (the debug table
  from `tighten_insert_rls_and_debug_log`).
- ~25 functions with mutable `search_path`; several `SECURITY DEFINER`
  RPCs executable by `anon` (`current_coach_id`, `fn_enqueue_*`,
  `trigger_voice_log_processing`, etc.).
- Auth leaked-password protection disabled.

None block the pipeline, but they're cheap Phase-5 config-clean wins
and the `anon`-executable definer functions deserve a real look.

## Recommended order of operations for this session

1. **Push `fix/ci-green` to origin** (11 commits are local-only). Pure
   risk reduction, 30 seconds.
2. **Open a PR `fix/ci-green` → `main` and merge it.** This lands the
   deploy workflow, drift detector, reconciled ledger, smoke script,
   and rollback runbook on the default branch — the difference between
   "built" and "on." Biggest single score jump.
3. **Resolve `env-probe`** (delete from prod, or add to the function
   allowlist) so the drift detector goes green on first run.
4. **Delete `coaching-feedback`** from prod to clear the standing
   allowlist entry.
5. **Rehearse the rollback runbook** once on a Supabase preview branch
   (closes 3.2, unblocks the Phase-4 switch).
6. Then resume the roadmap proper at 2.1 (branch protection) / 2.4
   (eval stubs).

## Score ladder — where we actually are

| Milestone | Roadmap score | Reality 2026-06-11 |
|---|---|---|
| Phase 0 done | ~6 | ✅ essentially done |
| Phase 1 done | ~7.5 | ⚠️ built on branch, **not on `main`** |
| Phase 2 done | ~8.5 | ⚠️ only the eval gate is live |
| Phase 3 done | ~9 | ⚠️ artifacts exist, none verified |

**Effective today: ~6.5/10.** One merge + a push closes most of the
gap to ~8.5 without writing new pipeline code.

---

## Execution pass (2026-06-11, later)

Attempted the recommended order-of-operations. Findings:

### Blocked on credentials (both privileged writes)
- **`git push` cannot run from this environment.** The sandbox has read
  access to origin (`git ls-remote` works) but no write credential
  (`fatal: could not read Username for 'https://github.com'`), no `gh`
  CLI, no token in env. The 11 unpushed commits on `fix/ci-green` still
  need a push from a machine with your GitHub auth:
  ```
  git push origin fix/ci-green
  ```
- **`env-probe` cannot be deleted from here.** The Supabase MCP exposes
  no `delete_edge_function`, and the sandbox has no `SUPABASE_ACCESS_TOKEN`.
  Run from your machine:
  ```
  supabase functions delete env-probe --project-ref aqdijapxmjqaetursrde
  ```
  Safe to delete: it's unreferenced anywhere in the repo and its own
  source says "Temporary probe… Delete after use."

### Verified
- **`ALLOWED_ORIGIN` IS set in prod.** Invoked `env-probe` →
  `{"allowed_origin_set": true}`. This confirms the CORS-hardening the
  post-deploy smoke test checks for (3.1) is actually live, and closes
  the open question behind roadmap 0.6.

### New finding — defused a loaded gun
- **`coaching-feedback` is NOT dead and must NOT be deleted.** The
  shipped iOS app still calls it (`RunningLog/Coaching/CoachView.swift:525`;
  `CoachReadCard.swift` notes "coaching-feedback still writes"). But its
  source was already removed from the repo (commit `bf2012c`) and the
  drift allowlist said `pending: supabase functions delete …`. Running
  that command would 404 the in-app feedback button.
  - This is a **reproducibility violation** (property #1): prod runs a
    function the repo cannot rebuild.
  - **Action taken:** corrected `.github/scripts/drift_allowlist_functions.txt`
    so nobody pulls the trigger. The real fix is to **restore
    `supabase/functions/coaching-feedback/` to the repo** (recover from
    git history `git show bf2012c^:…`) or remove the iOS caller — then
    the allowlist entry can go away.

### Net
The two "quick cleanup" steps are both gated on your credentials, and
the cleanup list itself had a bug. Updated priority:
1. `git push origin fix/ci-green` (you) — unblocks everything.
2. Open + merge PR `fix/ci-green → main`.
3. `supabase functions delete env-probe …` (you) — safe.
4. **Do not** delete `coaching-feedback`; restore its source instead.
5. Then resume at 2.1 / 3.2.

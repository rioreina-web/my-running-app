# Operator checklist — 2026-06-10 (supersedes 2026-06-09)

Status after the June 10 session (Cowork + CI session working in parallel).
The June 9 checklist is ~80% closed; this is what remains.

## Done today (verified against prod)

- **#0 GitHub remote + push** — `main` + `design/editorial-v2` at `ec29a21`
  on `github.com/rioreina-web/my-running-app`. Root cause of the early 403:
  stale keychain credential for another account; fixed via `gh auth setup-git`.
- **#1 GCP billing hard cap** — $50/mo budget, disable-billing at 110%.
  Slack spend alerts were already live (cron 13:00 UTC).
- **#2 Dead edge functions deleted** — `form-check-analysis`,
  `biomechanics-analysis`, `custom-plan-builder`, `adaptive-workout` all
  confirmed gone from prod.
- **#4 `ALLOWED_ORIGIN` set** — `https://web-tau-pearl-55.vercel.app`
  (Vercel project's stable prod domain; postrundrip.com not attached yet —
  update the secret when it is). Verified: CORS preflight from an unknown
  origin returns the pinned origin, not `*`.
- **#5a Dark functions deployed + pipeline migrations applied** —
  `shift-day` (move-day feature un-404'd), `parse-workout-shorthand`
  (iOS DayDetailSheet caller un-404'd), `generate-workout-insight`,
  `drain-coach-insight-jobs`, `drain-voice-processing-jobs`. Migrations
  applied in order: coach-insight outbox trigger → drain cron → voice
  outbox (W3.3 fully live: table, claim RPC, trigger swap, every-minute
  cron). Both drain crons verified running and succeeding.
- **Advisor-driven hardening migration** — `claim_*` outbox RPCs +
  `fn_weekly_plan_rebalance` were executable by anon/authenticated via
  PostgREST (default grants survive `REVOKE FROM PUBLIC`); revoked.
  `llm_model_pricing` had no RLS (hard rule #1); enabled, read-only for
  authenticated.
- **`weekly-plan-review` CUT** (decision 2026-06-10) — never deployed,
  cron never scheduled, untested LLM prompt making load decisions, voice
  mismatch with Maya observation-first posture. Function dir + prompt
  template deleted; prompt-library registry + rate-limit contract test
  updated. The Sunday `weekly-plan-rebalance` cron is unrelated (calls
  SQL `fn_weekly_plan_rebalance()`) and stays.
- **`post-run-reconciliation` verdict** — no active caller in prod
  (`auto_post_run_reconciliation` trigger doesn't exist; only
  `auto_reconcile_log` does). Leave dark; cut candidate.
- **CI verified green locally** (commit `d886977`): edge `deno check`
  0 errors + 175/175 tests; web ESLint 0 errors + tsc clean + 19/19
  tests; ML 16/16 pytest cases. iOS (test→build) and db-lint (local
  stack startup) config fixes are in the commit — verifiable only on
  the GitHub runner.
- **GitHub Pro purchased** — for branch protection on a private repo.

## Remaining (in order)

1. **Push + PR + merge** `fix/ci-green` → `main`:
   `git push -u origin fix/ci-green && gh pr create --base main ...`
   Watch the 4 required checks. iOS job still names `iPhone 17 Pro` —
   may fail on the macos-15 runner image; it's non-required, tune later.
2. **Confirm repo is private again** (Settings → Danger Zone). It was
   flipped public for free-tier branch protection before Pro existed.
3. **Branch protection on `main`** — require the 4 checks
   (`Edge functions (Deno)`, `Web (Next.js)`, `ML service (Python)`,
   `DB lint (Supabase)`), linear history. PR-required with 0 approvals
   (solo account can't self-approve).
4. **#5b Blanket redeploy** — `supabase functions deploy` from repo
   root after merge. Ships auth gates, per-user rate limits, race
   anchoring (Phase 2 A/C/F), canonical pace bands to the ~30 functions
   still on April/May builds.
5. **#6 `confirmed_races` verification** — race_result is already staged
   on training_log `b8aa18d2` (10K, 33:03, 2026-04-12) and athlete_state
   is invalidated. After 5b, any AI call rebuilds state; expect the race
   in `confirmed_races`. NOTE: this race anchors all pace zones once
   Phase 2 is live — confirm 33:03 is the real chip time.
6. **~30-min dashboard hardening pass** (200-user ADR Tier 0, never
   verified): PITR enabled; email confirmation required; JWT expiry
   sanity; enable leaked-password protection (Auth → security).

## Known gaps (accepted, tripwired)

- **Upstash deferred** → per-user rate limits silently no-op; GCP hard
  cap is the backstop. Revisit before opening signups.
- **Eval harness coverage partial** → hard rule #3 manually enforced.
  Phase 1 of Maya's roadmap.
- ADR tripwires unchanged: pooler swap, log drain, edge-function
  consolidation, landing page, legal docs.

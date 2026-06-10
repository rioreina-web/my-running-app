# TASKS

3-week readiness plan to reach 1,000 users. Source:
`outputs/security-and-scale-1000-users.md`. Sequenced by what blocks
first (money/identity/blast radius → correctness → operations).

Total estimated engineering effort: ~3 weeks. No item requires
infrastructure spend over $100/mo.

---

## Week 1 — money, identity, blast radius

### W1.1 — Replace in-code LLM cost cap with provider-side hard cap  *(0.5d eng + Cloud Console)*

The previous in-code `dailyBudgetExceeded()` check in `generate-workout-insight/index.ts` was the weakest layer of cost protection — it lived inside the same code that could be buggy. Defense moved outside the system.

**Implementation state — 2026-05-12:**

- [x] **In-code cap removed.** `dailyBudgetExceeded()` function and `COACH_INSIGHT_DAILY_BUDGET` env var are no longer in `generate-workout-insight/index.ts`. File now carries an explanatory comment at the previous gate location.
- [x] **Daily Slack spend alert built.** Migration `supabase/migrations/20260512210000_daily_llm_spend_alert.sql` adds:
  - `llm_model_pricing` table (per-model USD per 1M tokens; update via append-only migration when providers change rates)
  - `yesterday_llm_spend` view aggregating `usage_tracking` + a coach_insight proxy row
  - `daily-llm-spend-alert` pg_cron job firing at 13:00 UTC daily, posting to a Slack webhook stored in `vault.decrypted_secrets.slack_alerts_webhook_url`
- [x] **Runbook written.** `docs/deploy/llm-cost-controls.md` covers architecture, Cloud Console steps, Slack webhook setup, vault secret, dry-run query, and how to read the alert.

**Manual steps remaining (operator action — not eng):**

- [ ] **Set the Google Cloud billing budget on the Gemini project.** Console → Billing → Budgets & alerts → Create budget. Scope: project + Generative Language API. Amount: $50/mo. Alert at 50/80/100/110%. **Check `Disable billing to stop usage` at 110%** — this is the actual hard cap. Full step-by-step in `docs/deploy/llm-cost-controls.md` § Step 1.
- [x] **Create the Slack webhook and store it in vault.** *(2026-06-09: `slack_alerts_webhook_url` confirmed present in vault.)*
- [x] **Apply the migration.** *(2026-06-09: applied to prod via MCP, together with `coach_insight_outbox` which the spend view depends on. Cron `daily-llm-spend-alert` verified scheduled.)*
- [ ] **Verify with dry-run.** Run the dry-run SQL block in `docs/deploy/llm-cost-controls.md` § Step 3. Slack message should land in `#alerts-prod` within seconds. (Or just wait for tomorrow's 13:00 UTC firing.)

**Why this matters:** the provider cap is enforced by Google outside our code, so no internal bug, retry loop, or compromised service-role key can spend past it. The in-code cap fires *after* the calls being counted have already been made, and depends on the budget-check code itself being correct.

**Source:** decision from May 2026 architecture review of the AI insight pipeline; risk F1 in `outputs/security-and-scale-1000-users.md`.

### W1.2 — Require `ALLOWED_ORIGIN` env in production  *(0.5d)*

`supabase/functions/_shared/cors.ts` used to fall back to `*` if `ALLOWED_ORIGIN` was unset. Combined with bearer-token auth that wasn't an open front door, but it lifted the cost of CSRF-style abuse from "must be on the app domain" to "anywhere." The bigger hole was that **22 of 38 browser-reachable edge functions inlined their own CORS headers** with `*` hardcoded — they bypassed the shared module entirely. Now closed end-to-end.

**Implementation state — 2026-05-15:**

- [x] **`_shared/cors.ts` fails fast in production.** Production is detected via `DENO_DEPLOYMENT_ID` (Deno Deploy / Supabase Edge sets it; local `supabase functions serve` doesn't). When `DENO_DEPLOYMENT_ID` is present and `ALLOWED_ORIGIN` is missing, the module throws on import: `[cors] ALLOWED_ORIGIN must be set in production. Refusing to fall back to '*'`. Dev (no `DENO_DEPLOYMENT_ID`) still falls back to `*` so local serve works.
- [x] **All 38 browser-reachable edge functions migrated** to `import { corsHeaders } from "../_shared/cors.ts"`. The hole that motivated this task — `*` hardcoded in 22 functions plus a broken `Deno.env.get("ALLOWED_ORIGIN") || "*"` pattern in `strava-test-pull` — is closed.
- [x] **`process-training-memo` is the lone non-importer**, intentionally. Called only server-to-server (iOS `URLSession` doesn't enforce CORS; `web/src/app/api/retry-processing/route.ts` is a Next.js api route fetching server-side). Documented as the only entry in `SERVER_ONLY_FUNCTIONS` in the contract test.
- [x] **Contract test** at `supabase/functions/_shared/cors.contract.test.ts` — 4 assertions covering: cors.ts has the fail-fast logic, cors.ts exports `corsHeaders`, no function inlines `Access-Control-Allow-Origin`, and every browser-reachable function imports `corsHeaders` from the canonical surface. Adding a new function without CORS — or adding one and inlining headers — fails the test.

**Defense layers, ordered by strength:**

1. **Module-level throw in `_shared/cors.ts`** — any function deploying to production without `ALLOWED_ORIGIN` set will refuse to start. Loud, immediate, unambiguous.
2. **38 functions go through one canonical surface** — drift surface eliminated. Changing the policy is a one-line edit to `_shared/cors.ts`.
3. **Contract test** — catches regressions (new function inlining `*`, or removing the throw) at PR review, not at the next prod deploy.

**Manual steps remaining (operator):**

- [ ] **Set `ALLOWED_ORIGIN` in the Supabase edge function env.** Supabase dashboard → Project Settings → Edge Functions → Environment variables. Add `ALLOWED_ORIGIN=https://app.postrundrip.com` (or whatever the prod web origin is). Without this, the next prod deploy fails on import — which is the desired behavior, but you want it set first so the deploy succeeds.
- [ ] **Redeploy any function that's currently running with the in-memory `*` fallback.** Running functions don't pick up new module behavior until redeployed. `supabase functions deploy` (no args) redeploys all. ~30 seconds.
- [ ] **Verify a CORS preflight from an unknown origin gets rejected.** From a non-allowed origin:
  ```
  curl -i -X OPTIONS \
    -H "Origin: https://attacker.example" \
    -H "Access-Control-Request-Method: POST" \
    https://YOUR_PROJECT.supabase.co/functions/v1/coaching-agent
  ```
  Expected: response `Access-Control-Allow-Origin` header is your prod origin, not `*` and not `https://attacker.example`. Browsers will then block the cross-origin call.

**Source:** risk S1 in `outputs/security-and-scale-1000-users.md`.

### W1.3 — Lock down service-role key boundary  *(0.5d)*

`web/src/lib/env.ts` held the service-role key. Pre-existing risk: one developer imports it into a client component and ships the service-role key in the browser bundle. Now locked down with three layers of defense.

**Implementation state — 2026-05-12:**

- [x] **Renamed** `web/src/lib/env.ts` → `web/src/lib/env.server.ts`.
- [x] **`import "server-only";`** is line 1 of the new file. This is the load-bearing protection: Next.js fails the build if any `"use client"` component imports a module that (transitively) imports `server-only`.
- [x] **`SUPABASE_SERVICE_ROLE_KEY` throws on access when unset** — defends against silent-empty-string credentials in prod.
- [x] **All five server-side callers updated** to `import "@/lib/env.server"`: `middleware.ts` (side-effect import for env validation) + the four api routes (`coach`, `assign-plan`, `weekly-report`, `retry-processing`).
- [x] **ESLint rule live** in `web/eslint.config.mjs` — `no-restricted-syntax` bans any direct `process.env.SUPABASE_SERVICE_ROLE_KEY` read outside `env.server.ts`, with a message pointing to the canonical surface.
- [x] **Contract test** at `web/tests/env-server-boundary.contract.test.mjs` — 11 assertions, runs in ~180ms via `node --test`. Catches:
  - `server-only` import being removed or moved from line 1
  - `SUPABASE_SERVICE_ROLE_KEY` export disappearing or losing its throw-on-unset behavior
  - The ESLint rule being weakened or removed
  - Any `"use client"` file importing a `*.server` module (statically, by scanning for the `"use client"` directive + import patterns)
  - Any direct `process.env.SUPABASE_SERVICE_ROLE_KEY` read outside `env.server.ts`
  - Pinned server-side callers drifting to a different import path

**Verification:**

```
$ cd web && node --test tests/env-server-boundary.contract.test.mjs
# tests 11
# pass 11
# fail 0
```

The three layers of protection (in order of strength):

1. **`server-only` package** — Next.js bundler-level enforcement. Any client-side import path that touches `env.server.ts` fails the build with a clear error. **Strongest layer.**
2. **ESLint `no-restricted-syntax`** — catches `process.env.SUPABASE_SERVICE_ROLE_KEY` reads at lint time, before commit.
3. **Contract test** — catches structural drift at PR review, with explicit messages pointing the offender at the right surface.

**Wires into CI in W1.4** — the contract test will run as part of the `cd web && npm test` job.

**Source:** risk S3 in `outputs/security-and-scale-1000-users.md`.

### W1.4 — Stand up CI  *(1.5d)*

No CI meant every push relied on local discipline. Three contract tests (rate-limit, env-server-boundary, cors) were written without the CI to enforce them. Closed now.

**Implementation state — 2026-05-15:**

- [x] **`.github/workflows/ci.yml`** in place. Five jobs, all running on PRs and pushes to `main`. `concurrency` cancels superseded runs on the same ref so CI cost stays predictable.
- [x] **Job: `edge-functions`** — Deno v2.x. Runs `deno check` over every `index.ts` and every `_shared/` non-test `.ts` (catches type drift across the 39 functions). Then `deno test --allow-all` over the 7 existing test files: `shift-day`, `subscribe-to-plan`, `_shared/cors.contract`, `_shared/pace_adjuster`, `_shared/cross-language-pace-contract`, `_shared/athlete-state`, `_shared/pace-engine`.
- [x] **Job: `web`** — Node 20. `npm ci` → ESLint → `tsc --noEmit` → `npm test`. The npm test script chains contract tests (`tests/*.test.mjs` — 19 assertions across rate-limit + env-server-boundary) and smoke tests (`tests/smoke/*.smoke.test.ts` via the existing smoke-register harness).
- [x] **Job: `ml-service`** — Python 3.11. `pip install -r requirements.txt` + `pip install pytest httpx`. Runs `pytest tests/`. **New this round:** wrote `tests/conftest.py` (sets dummy JWT-shaped env vars before app import — `app/config.py` calls `sys.exit(1)` on missing required env, so this is required), `tests/test_health.py` (3 assertions: PUBLIC_PATHS membership, 200 without auth, response shape), `tests/test_auth.py` (13 assertions across 8 negative paths and 1 positive: missing header, non-Bearer, malformed, expired, wrong-secret, wrong-audience, wrong-issuer, all 3 protected endpoints; plus a valid-token positive that uses `raise_server_exceptions=False` to assert the middleware lets the request through). **16 tests pass locally.**
- [x] **Production bug fixed under W1.4:** `ml-service/app/auth.py` was `raise HTTPException(401)` inside a `BaseHTTPMiddleware`, which Starlette doesn't route through FastAPI's exception handlers — production was returning **500 instead of 401 for every unauthenticated request**. Rewrote to return `JSONResponse(401, ...)` directly. Documented the gotcha in a top-of-file comment so future edits don't regress.
- [x] **Job: `ios`** — macOS-15 runner with Xcode. iOS runners are ~10× the cost of Ubuntu so this job is gated: only runs on pushes to `main`, on PRs labeled `ios`, or on `workflow_dispatch`. Runs `xcodebuild test -scheme RunningLog -destination 'platform=iOS Simulator,name=iPhone 17 Pro'` against the 5 test files. (Spec said iPhone 15; updated to iPhone 17 Pro since the macos-15 runner image ships that simulator.)
- [x] **Job: `db-lint`** — `supabase/setup-cli@v1` + `supabase db lint --schema public`. Catches lint violations in migrations on every PR.

**Manual step remaining (operator):**

- [ ] **Enable branch protection on `main`.** GitHub repo → Settings → Branches → Branch protection rules → Add rule for `main`. Required checks: `Edge functions (Deno)`, `Web (Next.js)`, `ML service (Python)`, `DB lint (Supabase)`. iOS is optional — gated separately. Also check: require PR review, dismiss stale reviews, require linear history. ~3 minutes.

**Three contract tests now load-bearing** (they were honor-system before CI; now they fail the build):

- `web/tests/rate-limit.contract.test.mjs` — guards the 6 rate-limited web API routes
- `web/tests/env-server-boundary.contract.test.mjs` — guards the service-role-key import boundary
- `supabase/functions/_shared/cors.contract.test.ts` — guards every browser-reachable edge function from inlining its own CORS headers

**Source:** tech-debt audit item #2.

---

## Week 2 — correctness gates

### W2.1 — Eval harness scaffold for the four highest-stakes prompts  *(5d)*

`CLAUDE.md` mandates that "no LLM prompt change ships without running the eval harness" — and that harness doesn't exist. The wedge ("AI advises, never acts; AI never recommends stopping training, diagnosing injuries, or making medical claims") is currently untestable. Any prompt change to `coaching-agent`, `injury-analysis`, or the niggles classifier could violate those rules and nothing would notice.

- [ ] Scaffold `supabase/functions/_evals/` runner — reads a cassette of inputs, invokes the prompt against the live model, scores outputs against a rubric, writes a JSON report
- [ ] Rubric primitives: regex bans (`diagnosis_language.json`, `medical_claim_language.json`), structured-output schema check, golden-example similarity
- [ ] Coverage round 1: **`coaching-agent`** — 20 cassettes including 5 prompt-injection attempts and 5 "user pastes medical text" cases
- [ ] Coverage round 2: **`injury-analysis`** — 15 cassettes; rubric forbids diagnoses like "ITBS," forbids actions like "rest" / "ice"
- [ ] Coverage round 3: **Niggles classifier** in `process-training-memo` — verify closed body-part vocabulary; 10 cassettes for off-vocabulary inputs ("subtalar joint" → maps to ankle or omits, doesn't invent)
- [ ] Coverage round 4: **`reschedule-plan`** — verify it only outputs codes from `WORKOUT_CODES_BY_DAY`, never invents a workout
- [ ] Wire into CI (W1.4) — eval failure blocks merge for prompt-touching PRs
- [ ] Add eval-failure summary to PR comments via GitHub Action

**Why this matters:** the wedge is differentiated only if it actually behaves the way the brand promises. Today there's no mechanism to enforce that. One Niggles output that says "could be ITBS, ice it tonight" reaching a customer torches the wedge.

**Source:** tech-debt audit item #1; risk S4 + F5 mitigation in `outputs/security-and-scale-1000-users.md`.

### W2.2 — Synthesis trigger migration for `evaluate-coachable-moment`  *(0.5d)*

The rules engine and the entry-point edge function both exist. A trigger fired `generate-workout-insight` on `training_logs` insert. No equivalent trigger fired `evaluate-coachable-moment` — at 1,000 users athletes saw zero coachable moments after most runs because synthesis only ran from cron. Now wired up.

**Implementation state — 2026-05-15:**

- [x] **Migration written:** `supabase/migrations/20260515120000_trigger_evaluate_coachable_moment.sql`.
- [x] **Two triggers**, both running `fn_trigger_evaluate_coachable_moment()`:
  - `auto_evaluate_coachable_moment_on_insert` — AFTER INSERT on `training_logs`. Covers HealthKit imports and direct logs.
  - `auto_evaluate_coachable_moment_on_voice_complete` — AFTER UPDATE on `training_logs` WHEN `cleaned_notes` transitions NULL → non-NULL. That's the "voice processing finished" signal, after which mood + niggles have been extracted and rules like `low_mood_streak` need a re-run. (There is no separate `voice_logs` table — voice logs are `training_logs` rows with `audio_url IS NOT NULL`.)
- [x] **Three guards** inside the trigger function (each `RETURN NEW`s without firing the edge function so the originating INSERT/UPDATE is never blocked):
  - Missing `user_id`.
  - Athlete has no `coach_athlete_relationships` row with `status='active'`. The evaluator would no-op anyway; this saves ~700 pg_net calls/day at 1k users with ~10% coached.
  - Vault `supabase_url` / `service_role_key` unset.
- [x] **Idempotency** is handled by the existing partial unique index `coachable_moments_one_open_per_rule` (`20260429110000_coachable_moments_unique_open_per_rule.sql`). The evaluator pre-flights a SELECT to filter duplicates; the index is belt-and-suspenders. A HealthKit burst that fires this trigger 30 times in 5 seconds is wasteful but safe.
- [x] **Mirrors** the structure of `20260428110000_trigger_workout_insight.sql`. Same `SECURITY DEFINER` function pattern, same vault secret lookup, same `pg_net.http_post` shape.

**Manual step remaining (operator):**

- [x] **Apply the migration.** *(2026-06-09: confirmed already live in prod in its newer outbox form — `auto_enqueue_coachable_moment_on_insert` + `_on_voice_complete` triggers, `coachable_moment_jobs` table, `drain-coachable-moment-jobs` + stale-recovery crons all verified. The 20260515 direct-fire migration was superseded by 20260518's outbox version. Nothing left to apply.)*

- [ ] **Smoke-test against staging.** Verification block at the bottom of the migration file:
  1. Check both triggers exist via `information_schema.triggers`.
  2. Pick an athlete with an active coach. Insert a small test `training_logs` row (or update an existing row's `cleaned_notes` from NULL → `'test'`). Within seconds, observe a row in `coachable_moments` or an evaluator log line. If neither, check `net.http_response_collect()` and Supabase function logs.

**Future debounce opportunity (not for 1k):** if pg_net invocation cost becomes meaningful, add a per-athlete `last_evaluated_at` column + a 60-second cooldown. Document for 10k-user prep.

**Source:** tech-debt audit item #4; risk F5 in `outputs/security-and-scale-1000-users.md`.

### W2.3 — Standardize per-user edge-function rate limits on LLM paths  *(1.5d)*

The web `api/` routes had per-route, per-user rate limits pinned by contract test. Edge functions were inconsistent: 8 used per-user feature limits, 1 used the global `checkRateLimit` (no feature bucket), 4 had no rate limit at all, and 7 LLM-calling functions had no auth check at all (accepting `user_id` from the request body). Now consolidated.

**Implementation state — 2026-05-15:**

- [x] **Audit complete.** Of 21 LLM-calling edge functions:
  - 8 already had per-user feature limits (`coaching-agent`, `injury-analysis`, `training-analysis`, `fitness-predictor`, `parse-training-plan`, `parse-training-week`, `transcribe`, `generate-training-plan`).
  - 1 used global `checkRateLimit` instead of the per-feature form (`coaching-agent`).
  - 4 missing rate limit but had `getAuthenticatedUser` gating (`parse-workout-structure`, `weekly-coaching-report`, `weekly-plan-review`, `reschedule-plan`, `generate-workout-insight`).
  - 7 accept `user_id` from request body **with no auth check at all** (`process-check-in`, `post-run-analysis`, `race-intel`, `race-readiness`, `block-review`, `injury-early-warning`, `process-training-memo`). Adding rate limits to these without fixing auth would be cosmetic — a forged `user_id` could burn another user's quota. Tracked separately as W2.3-follow-up.
- [x] **New `enforceFeatureRateLimit` helper** in `_shared/rateLimit.ts`. Returns `Response | null` so call sites become one line:
  ```ts
  const rlBlocked = await enforceFeatureRateLimit(userId, "feature", corsHeaders);
  if (rlBlocked) return rlBlocked;
  ```
  Three short-circuits: service-role bypass, Redis disabled in dev, normal accept path. 429 responses include a `Retry-After` header computed to midnight UTC.
- [x] **5 functions added rate limits** using the new helper: `parse-workout-structure` (feature `parse`), `reschedule-plan` (`reschedule`), `weekly-plan-review` (`weekly_review`, single-user path only), `weekly-coaching-report` (`weekly_review`, single-user path only), `generate-workout-insight` (`workout_insight`, non-service-role path).
- [x] **`coaching-agent` migrated** from global `checkRateLimit(userId, tier)` to per-feature `checkFeatureRateLimit(userId, "coaching", tier)` so its limits are pinned independently.
- [x] **`FEATURE_LIMITS` updated:** dropped dead `form_check_analysis` entry (function removed in C.1); added 8 new buckets — `injury_analysis`, `plan_builder`, `race`, `weekly_review`, `post_run`, `voice_memo`, `reschedule`, `workout_insight`, `check_in`. All 14 buckets documented in `docs/conventions/rate-limits.md` with pinning rationale.
- [x] **Contract test** at `supabase/functions/_shared/rateLimit.contract.test.ts` — 17 assertions covering:
  - `enforceFeatureRateLimit` is exported
  - Every pinned (function, feature) pair has the right rate-limit call
  - `FEATURE_LIMITS` contains every pinned feature
  - The deleted `form_check_analysis` bucket is gone
  - No LLM-calling function is silently un-rate-limited (every Gemini/OpenAI/Anthropic-importing function is in either `LLM_FUNCTIONS_RATE_LIMITED`, `SERVER_ONLY_FUNCTIONS`, or `AUTH_PATTERN_AUDIT_PENDING`)
  - All 7 auth-pending entries have a non-empty justification
- [x] **Doc** at `docs/conventions/rate-limits.md` covering architecture, the FEATURE_LIMITS table, how to add rate limits to a new function, helper behavior, the audit-pending list, and the contract tests that protect both layers.

**Coverage now: 13 pinned + 7 audit-pending = 20 of 21 LLM-calling functions accounted for** (the 21st is `parse-workout-shorthand`, which is a deterministic parser — no LLM call).

**Manual step remaining (operator):**

- [ ] **Confirm Upstash Redis env is set in production.** The helper falls back permissively when `UPSTASH_REDIS_URL` / `UPSTASH_REDIS_TOKEN` are unset (so local serve works). In prod, those should be set; otherwise rate limits are no-ops. Verify in Supabase dashboard → Project Settings → Edge Functions → Environment variables.

### W2.3-follow-up — Auth audit for the 7 server-pattern LLM functions

**DONE in repo (verified 2026-06-09); prod deploy pending.** All 7 functions are gated: `process-check-in` via `requireServiceRole` (trigger-only caller), the other 6 via `requireAuthOrServiceRole` (JWT user must match body `user_id`; service-role must name the subject user) + per-feature rate limits. Pinned by `_shared/rateLimit.contract.test.ts` (37 assertions, green).

2026-06-09 additions:
- The contract test caught `coaching-daily-read` (shipped May) calling an LLM with auth but **no rate limit** — fixed (`daily_read` bucket, pinned).
- **Prod is still running pre-audit builds of these functions** (April/May deploys). The fixes go live on the next `supabase functions deploy`, which is gated on setting `ALLOWED_ORIGIN` first (see W1.2). Sequence in `outputs/operator-checklist-2026-06-09.md`.

**Source:** risk F3 in `outputs/security-and-scale-1000-users.md`.

---

## Week 3 — operational readiness

### W3.1 — Backup restore drill + runbook  *(0.5d)*

Supabase Pro backs up nightly. Nobody has ever tested a restore. A real restore takes ~30 minutes if you've done one and ~6 hours if you haven't.

- [ ] Create a Supabase branch from last night's backup
- [ ] Verify schema matches `main` (count migrations, spot-check 5 tables)
- [ ] Verify a known user's `training_logs` and `coach_insight_jobs` rows survived
- [ ] Document the runbook in `docs/deploy/restore-runbook.md`: exact buttons, exact commands, time-to-first-byte, what to do if PITR is needed
- [ ] Add to the incident-response checklist

**Source:** risk F2 in `outputs/security-and-scale-1000-users.md`.

### W3.2 — Verify Supabase connection pooler is on  *(0.5d)*

Without the pooler, the Next.js `api/` routes hit the 60-direct-connection ceiling around 200 concurrent users.

- [ ] Confirm Supabase pooler (Supavisor / pgbouncer) is enabled on the project
- [ ] Verify `web/src/lib/env.server.ts` uses the **pooler** connection string, not the direct one (port 6543, not 5432)
- [ ] Verify edge functions use the JS client (which uses HTTP/REST, no connection issue)
- [ ] Document in `docs/deploy/db-connections.md`

**Source:** capacity check in `outputs/security-and-scale-1000-users.md`.

### W3.3 — Voice auto-process pipeline → outbox pattern  *(3d)*

The coach-insight outbox in `20260508140000_coach_insight_outbox.sql` is the right answer for trigger-fired LLM dispatch. Apply the same pattern to the voice auto-process pipeline — the highest-stakes remaining fire-and-forget path.

- [ ] Create `voice_processing_jobs` table mirroring `coach_insight_jobs` (status, attempts, max_attempts, last_error, available_at)
- [ ] Trigger on `training_logs` INSERT writes a row when `audio_url IS NOT NULL`
- [ ] New edge function `drain-voice-processing-jobs` mirrors `drain-coach-insight-jobs`
- [ ] `pg_cron` schedule every minute, batch 20
- [ ] Add `voice_processing_status` column on `training_logs` (matches `coach_insight_status` convention)
- [ ] Migrate existing `process-training-memo` trigger to enqueue instead of fire-and-forget
- [ ] Keep `cleanup_stuck_processing` cron as belt-and-suspenders

**Source:** risk F4 in `outputs/security-and-scale-1000-users.md`.

### W3.4 — On-call rotation + Sentry alerting  *(0.5d)*

Sentry is wired on iOS, web, and ml-service. Nobody is configured to receive its alerts.

- [ ] Create `#alerts-prod` Slack channel
- [ ] Connect Sentry → Slack: route errors with `level >= error` and `environment == production`
- [ ] Define on-call rotation for the first month (likely solo / two-person)
- [ ] Define paging thresholds: P1 = wedge-violating LLM output, payment runaway, RLS bypass evidence; P2 = >5% error rate sustained; P3 = anything else
- [ ] Add the rotation and thresholds to `docs/deploy/on-call.md`

**Source:** risk F2 / operational gap in `outputs/security-and-scale-1000-users.md`.

### W3.5 — PII handling docs (legal)  *(counsel + 1d eng)*

Voice logs upload to Supabase Storage; transcripts go to Groq / OpenAI / Gemini. There's no docs/legal page covering retention, deletion-on-request, or third-party processors. Plus the existing legal docs have 28 `TODO`s between them.

- [ ] Send counsel:
  - List of third-party processors (Supabase, Groq, OpenAI, Gemini, Strava, Sentry, Railway)
  - Data flow diagram (audio → Storage → transcribe → text)
  - Retention defaults (audio: ?, transcripts: indefinite today)
  - DSR/deletion mechanism (today: none; needs spec)
- [ ] Fill the 16 `TODO`s in `docs/legal/privacy-policy.md`
- [ ] Fill the 12 `TODO`s in `docs/legal/terms-of-service.md`
- [ ] Add `docs/legal/data-handling.md` covering audio retention and processors
- [ ] Implement a "delete my data" endpoint (`web/src/app/api/account/delete/route.ts`) that cascades correctly across `training_logs`, `voice_logs`, `coach_insight_jobs`, Storage objects

**Source:** risk S5 in `outputs/security-and-scale-1000-users.md`; tech-debt audit item #5.

---

## Weeks 4–7 — AI cost optimization

Modeled spend at 1,000 users is ~$200–350/mo today. The work below
drops it to ~$115–200/mo with **no model-tier downgrade on prompts
that need the reasoning**. ~10 engineering days total.

**Gating prerequisite:** W2.1 (eval harness) must land first.
Compression and prompt caching both change the model's input
distribution; without eval coverage there's no way to tell if quality
regressed.

Items are independent and parallelizable with feature work.

### C.1 — Delete the four cut-but-still-deployed LLM functions  *(0.3d)*

CLAUDE.md listed `form-check-analysis`, `biomechanics-analysis`, `custom-plan-builder`, and `adaptive-workout` as cut. The directories still existed with active Gemini calls (1,528 LOC across the four). Now removed.

**Implementation state — 2026-05-12:**

- [x] **Deleted `supabase/functions/form-check-analysis/`** (560 LOC). It called `loadPrompt("form-check-analysis.v1", ...)` against a prompt file that didn't exist — would have errored at runtime if invoked. Confirmed dead.
- [x] **Deleted `supabase/functions/biomechanics-analysis/`** (290 LOC). Same broken `loadPrompt` reference.
- [x] **Deleted `supabase/functions/custom-plan-builder/`** (640 LOC). Replaced by template plans + coach-portal builders per CLAUDE.md.
- [x] **Deleted `supabase/functions/adaptive-workout/`** (38 LOC stub that was returning 410 Gone with a `delete-after-2026-05-17` TODO; deletion already in scope, executed early).
- [x] **No orphan prompts** in `_shared/prompts/` — the REGISTRY was already clean.
- [x] **Client-side references cleaned:**
  - `RunningLog/RunningLog/Models/WorkoutModels.swift` line 409 — decoder comment updated to drop the dead-function name (the decoder still handles data from coach-portal plans).
  - `supabase/functions/_shared/prompt-library.ts` line 78 — docstring example updated from `biomechanics-analysis.v1` to `injury-analysis.v1`.
  - `supabase/functions/_shared/pace-zones.ts` historical "ported from adaptive-workout" comment left intentionally as provenance — explains why the code looks the way it does.

**Verification:**

- Edge function count: 43 (39 live + 4 dead) → **39 live**.
- No remaining iOS or web client references to any of the four function names.
- The migration `20260512210000_daily_llm_spend_alert.sql` header comment lists the cut function names as historical `usage_tracking` writers. Migrations are append-only per CLAUDE.md hard rule #5, so the comment stays — informational only, no behavior impact.

**Manual step remaining (operator):**

- [ ] **Evict the deployed handlers from Supabase.** Run from the repo root:
  ```
  supabase functions delete form-check-analysis
  supabase functions delete biomechanics-analysis
  supabase functions delete custom-plan-builder
  supabase functions delete adaptive-workout
  ```
  Note: `supabase functions deploy` only adds/updates; it doesn't evict previously-deployed handlers. `delete` is the correct verb. If you'd rather: open the Supabase dashboard → **Edge Functions** → each function → **Delete function**. Four clicks, same end state.

**Why this matters:** dead code wired to billable APIs is the only kind of dead code that costs money on its own. Removes attack surface — these handlers were still accepting input and (in the two LLM-using ones) calling models.

**Source:** lever C.1 in `outputs/ai-cost-optimization-plan.md`.

### C.2 — Aggressively compress `coaching-agent` context  *(2d, $50–70/mo)*

The moderate/complex coaching-agent prompt concatenated 22 context blocks unconditionally — several overlapping (athleteContext + athleteProfileContext + analyticsContext + periodizationContext + weeklyReportContext + aiInsightsContext all cover related ground). A drive-by edit that bumped one block silently grew every call. Now budget-gated.

**Implementation state — 2026-05-15:**

- [x] **`compressTrainingContext` was already imported** before this task started. For moderate/complex, coaching-agent already uses `buildTrainingPeriodDocument` (4-week-detail + older-summary) rather than dumping 150 raw logs. The audit-time assumption about the 150-log dump was wrong; the real cost driver was block count.
- [x] **`assembleWithBudget(blocks, budget)` helper added** to `_shared/context.ts`. Takes named blocks with `required` / `preferred` / `optional` priority; required always go in; preferred fill remaining budget; optional drop first under pressure. Truncation marker `[…truncated for budget]` so the model knows context was cut. Returns telemetry (`used`, `dropped`, `truncated`, `included`) for observability.
- [x] **Per-tier budgets exported** as `COMPLEXITY_CONTEXT_BUDGETS = { simple: 1000, moderate: 4000, complex: 8000 }`.
- [x] **`coaching-agent` rewired** to use the budgeted assembler. All three complexity tiers (simple/moderate/complex) flow through the same `assembleWithBudget` path. The 22 context blocks are now priority-tagged:
  - **Required (4):** `runnerLevel`, `athlete`, `memories`, `injury` — the model can't be safe without these.
  - **Preferred (6):** `training`, `athleteProfile`, `plan`, `conversation`, `docs`, `raceIntel` — high-signal personalization.
  - **Optional (11):** `periodization`, `analytics`, `planAwareness`, `weeklyReport`, `aiInsights`, `profile`, `hk`, `predictions`, `goals`, `pendingAdj`, `feedback` — overlap with required/preferred or rarely-cited; first to drop under budget pressure.
- [x] **Per-call telemetry logged** as `[ctx] complexity=… budget=… used=… included=… dropped=[…] truncated=[…]`. Pairs with the existing `usage_tracking` writes (which already record `input_tokens` and `output_tokens` per call) for end-to-end cost observability.
- [x] **Unit tests** at `supabase/functions/_shared/context.assembleWithBudget.test.ts` — 11 assertions covering: required blocks always included even when over budget; preferred blocks fill in declared order; optional blocks drop before preferred; oversized blocks truncated with marker; per-block `maxTokens` cap honored; min-include-50-tokens floor prevents trailing dribble; empty/whitespace blocks filtered silently; telemetry coverage; budget echoed in result; `used` bounded by budget for the common case; `estimateTokens` consistency.
- [x] **Pre-existing model-hard-limit safety net retained** (4k/30k/90k tokens) as a fallback below the cost budget. The cost budget kicks in first; the model hard limit is the catastrophe stop.

**What was NOT done:** the original spec mentioned writing `compressPeriodizationContext` / `compressPlanAwarenessContext` / `compressAnalyticsContext` as individual functions. The budgeter generalizes the problem — those blocks are now in the "optional" pool and either fit or drop based on budget pressure, without needing per-block compressors. If specific blocks turn out to be high-value-but-always-truncated in production logs, we can build dedicated compressors then (one task per block, ~0.5d each).

**Operator-side widget** (tokens-used dashboard) is deferred — the `[ctx]` log line + the existing `usage_tracking` rows are enough to build it later via a `data:build-dashboard` skill invocation.

**Expected savings at 1k users:** moderate-tier coaching calls drop from ~8k input tokens to ≤4k. At 700 calls/day × halved input × Gemini Flash $0.30/M = **~$25–40/mo recovered today; compounds with C.3 (prompt caching) for another ~$30/mo at 1k.**

**Source:** lever C.2 in `outputs/ai-cost-optimization-plan.md`.

### C.3 — Prompt caching on stable per-user prefix  *(2d, $30–40/mo)*

The system prompt + athlete profile + active memories + injury context + active goals are stable across a user's day. Both Gemini (`cachedContent` API) and Anthropic (`cache_control: { type: "ephemeral" }`) charge ~10–25% of normal input cost on cached portions. For a 5,000-token stable prefix hit 10× per session, that's a 7.5× saving on those tokens.

- [ ] Identify the stable prefix in `coaching-agent`: `SYSTEM_PROMPTS[complexity]` + `athleteContext` + `athleteProfileContext` + `memoriesContext` + `injuryContext`
- [ ] Wrap Gemini call to use `cachedContent` (5-min TTL, renew on hit)
- [ ] Cache key = `userId + complexity + sha256(athleteStateRowSnapshot)`. Invalidate when `athlete_state` updates (already a trigger fires on those updates)
- [ ] For `fitness-predictor` on Claude Haiku, add `cache_control: { type: "ephemeral" }` on the static training-context portion of the prompt
- [ ] Track cache hit rate in `usage_tracking`; surface in the daily Slack alert from W1.1

**Why this matters:** compounds with C.2. Sequential effect: C.2 cuts the input size; C.3 makes the remaining input cheap per call. **$30–40/mo at 1k, $300–400/mo at 10k.** Do C.2 first.

**Source:** lever C.3 in `outputs/ai-cost-optimization-plan.md`.

### C.4 — Move 80% of weekly-coaching-report from LLM to code  *(2d, $12–15/mo)*

Weekly reports are mostly facts: "you ran 32 mi this week (+14%), ACWR 1.2, hardest day Tuesday." None of that needs a model. Today Flash generates the whole report including the deterministic parts, so the prompt is huge.

- [ ] Build `_shared/weeklyReportBuilder.ts` — pulls from `athlete_state`, `weeklyAnalytics`, `training_logs`; outputs a structured markdown report with all facts pre-inserted
- [ ] LLM pass becomes thin: ~500 tokens in ("here's the report, rewrite in coach voice"), ~800 tokens out
- [ ] A/B test (under eval harness) whether the voice pass adds measurable value; if not, drop the LLM entirely
- [ ] Schema-stable output also makes the eval harness's check trivial

**Why this matters:** 70–80% reduction on `weekly-coaching-report` input tokens. Also removes a stochastic surface (facts get hallucinated less often if the model isn't deriving them).

**Source:** lever C.4 in `outputs/ai-cost-optimization-plan.md`.

### C.5 — JSON mode + structured outputs on the remaining 5 functions  *(1d, $15–20/mo)*

JSON mode is in 8 functions today. Missing from `injury-analysis`, `injury-early-warning`, `race-intel`, `evaluate-coachable-moment`, `fitness-predictor`. Each pays ~150–300 input tokens explaining the output format and ~50–100 output tokens on JSON markers and preamble.

- [ ] Add Gemini `responseMimeType: "application/json"` + `responseSchema` to:
  - [ ] `injury-analysis`
  - [ ] `injury-early-warning`
  - [ ] `race-intel`
  - [ ] `evaluate-coachable-moment`
  - [ ] `fitness-predictor` (use Anthropic's `tool_use` for structured output)
- [ ] Update the prompts in `_shared/prompts/` to remove now-redundant "respond in this format" instructions
- [ ] Update callers to drop tolerant-JSON parsing (it can become `JSON.parse`)
- [ ] Add schema validation in the eval harness rubric for each

**Why this matters:** 10–15% reduction on the affected functions, plus a much-improved eval surface — the harness can check schema directly.

**Source:** lever C.5 in `outputs/ai-cost-optimization-plan.md`.

### C.6 — Cap output tokens at quality-not-cost  *(0.3d, $5–10/mo)*

`_shared/router.ts` sets `moderate` at 2,000 output tokens and `complex` at 3,000. Most coach responses are 300–600 tokens. The cap is defensive against truncation, but a regression that emits 3,000 tokens of slop costs as much as 5 well-formed responses.

- [ ] Drop `moderate` output cap to 800 tokens
- [ ] Drop `complex` output cap to 1,500 tokens
- [ ] Log when responses hit the cap; raise only if eval scores measurably suffer
- [ ] Add a `prompt_response_truncated` counter to Sentry

**Why this matters:** bounds the worst case. A prompt-injection or model regression can't burn 5× cost in a single call.

**Source:** lever C.6 in `outputs/ai-cost-optimization-plan.md`.

### C.7 — Conversation summarization at N=10  *(1d, $5–10/mo)*

`coaching-agent` pulls 50 most-recent conversation messages. Median session is 5–7 turns. The other 43 are paying for context the model rarely uses.

- [ ] Add a `summary` column to `conversations` (or sibling `conversation_summaries` table)
- [ ] On every message past message #10, re-summarize the prior history into ≤200 tokens; only include the last 5 raw turns + the summary
- [ ] Re-summarize at 20, 30, etc. — keep the rolling window cheap
- [ ] Eval coverage: verify the model still references prior context correctly with the summary in place

**Why this matters:** 30–40% reduction on long-conversation `coaching-agent` calls. Also makes long conversations feel more focused (the model isn't distracted by old turns).

**Source:** lever C.7 in `outputs/ai-cost-optimization-plan.md`.

### C.8 — `training-analysis` Pro→Flash audit  *(0.5d, $10–30/mo)*

One of two `gemini-2.5-pro` call sites. Pro costs ~4× Flash on input and output. If the analysis is "given this data, identify patterns" → Flash with JSON mode handles it. If it's "given this data, write a multi-section diagnostic narrative" → keep Pro.

- [ ] Read `supabase/functions/training-analysis/index.ts` (1,535 LOC) and the prompt
- [ ] Inventory what the prompt actually does: pure pattern detection, or true multi-step reasoning?
- [ ] If pure: drop to Flash 2.5 with JSON mode; eval-test before shipping
- [ ] If reasoning: keep Pro but add prompt caching on the rubric portion (apply C.3 pattern here)

**Why this matters:** $30/mo if Pro→Flash works; $10/mo if Pro stays but gets cached. Either way an honest read.

**Source:** lever C.8 in `outputs/ai-cost-optimization-plan.md`.

### C.9 — Flash-Lite pilot for the cheapest parsers  *(0.5d, $5–10/mo)*

Gemini 2.5 Flash-Lite at ~$0.10/M input is 3× cheaper than Flash. Reasoning quality is meaningfully lower, but that doesn't matter for the dumb paths: `parse-workout-shorthand`, the Niggles classifier (closed vocabulary), maybe `parse-workout-structure`.

- [ ] Pilot on `parse-workout-shorthand` first — simplest parser
- [ ] Run side-by-side against Flash 2.5 for one week via the eval harness
- [ ] Ship Flash-Lite if eval score is unchanged; revert if degraded
- [ ] Repeat for Niggles classifier and `parse-workout-structure`

**Why this matters:** smallest individual win, but the lowest-risk because of the eval-gate. Validates the "Flash-Lite for dumb paths" pattern for future parsers.

**Source:** lever C.9 in `outputs/ai-cost-optimization-plan.md`.

---

## Explicitly out of scope at 1,000 users

These are tempting and not earning their cost yet. Schedule for the 10k-user prep:

- Splitting `coaching-agent` (1,811 LOC) and `generate-training-plan` (2,078 LOC) — wait until W2.1 eval harness exists; refactoring under test is much cheaper
- Migrating Supabase JWTs to RS256 with JWKS — risk S2 is real but blast radius is bounded at 1k users
- Horizontal-scaling ml-service — one Railway dyno handles projected load with margin
- Collapsing the `parse-*` cluster (1,548 LOC across 4 functions) — hygiene, not safety
- Status page — audience is too small at 1k; email list works
- Coach-client canonical decision (iOS vs. web) — strategic call, post-wedge-launch

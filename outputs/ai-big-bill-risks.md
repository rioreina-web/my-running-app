# AI bill runaway risks — current state

Companion to `outputs/ai-cost-optimization-plan.md`. Date: 2026-05-15.

Every path through the system that could produce an unexpectedly large
bill from Gemini, Anthropic, Groq, or Whisper. Ranked by **likelihood ×
impact**. Mitigation state reflects what's actually shipped (engineering)
versus what's pending operator action.

---

## TL;DR

**Today's posture:** medium. The hard ceiling (Google Cloud billing cap)
is **not yet set in the console** — it's the most important single thing
you can do to bound the worst case. Per-user rate limits are now wired
to 13 functions and pinned in CI, but **7 LLM-calling functions still
accept a forged `user_id` from request body with no auth** (W2.3-follow-
up). A single bad actor with a Supabase anon token can hit those for
unlimited calls until the Cloud cap fires.

**The 3 most likely paths to a 10×+ bill spike, in order:**

1. Provider-side billing cap not set → no actual ceiling exists yet.
2. Unauthenticated LLM functions (×7) → forged-user_id flood, hits the
   shared daily budget.
3. Prompt regression that 5–10×s token usage on `coaching-agent` → silent
   growth since no eval harness exists yet (W2.1 not started).

**Mitigations already shipped:**

- Per-user rate limits on 13 functions (W2.3) — pinned in CI.
- Outbox + max-attempts=3 backoff on coach-insight pipeline.
- Three-provider fallback on transcribe (Groq → OpenAI → Gemini).
- Daily Slack spend digest migration written (W1.1 — pending operator).
- All edge functions go through `_shared/cors.ts` and `_shared/auth.ts`
  (W1.2, W1.3).
- CI catches regressions in rate-limit wiring, CORS, and env-server
  boundary on every PR.

**Mitigations pending operator action:**

- Google Cloud billing cap on the Gemini project (W1.1).
- Slack webhook in Supabase Vault (W1.1).
- Migration apply for daily spend alert (W1.1).
- `ALLOWED_ORIGIN` env in production (W1.2).
- `UPSTASH_REDIS_URL/TOKEN` env (without these, edge rate limits are no-ops).

---

## Ranked risks

Each row: likelihood × impact = priority. Likelihood is the probability
this happens in the next 90 days at 1,000 users. Impact is the worst-case
monthly bill spike if the failure happens.

### R1. Provider hard cap not yet set in Google Cloud Console  *(likelihood: high, impact: $$$$$)*

The W1.1 in-code `dailyBudgetExceeded()` cap was removed. The replacement
— a Google Cloud Billing budget on the Gemini project with `Disable
billing at 110%` — has **not been configured in the console** as of this
audit. Until the budget exists, the only thing bounding total spend is
the Slack alert (which is informational, once daily, and not yet wired
either).

**Worst case:** a compromised service-role key or a tight retry loop
could exfiltrate Gemini quota at full speed. At Gemini Flash $0.30/M in
+ $2.50/M out, sustained 100 RPS for 12 hours = ~$200 if outputs are
short, ~$2,000 if a prompt-injection makes outputs hit max_output_tokens.

**Close it by:** doing W1.1 § Step 1 in `docs/deploy/llm-cost-controls.md`
— it's ~5 minutes in the Cloud Console.

---

### R2. 7 LLM functions accept `user_id` from body with no auth check  *(likelihood: medium, impact: $$$)*

`process-check-in`, `post-run-analysis`, `race-intel`, `race-readiness`,
`block-review`, `injury-early-warning`, `process-training-memo` all skip
`getAuthenticatedUser` and trust whatever `user_id` lands in the request
body. Adding per-user rate limits to them is cosmetic — a forged user_id
just burns someone else's quota or rotates through random uuids to
bypass any per-user limit.

**Worst case:** a script with a valid Supabase anon token (which is in
the iOS app bundle and reverse-engineerable) hits `race-intel` (Gemini
2.0 Flash + Google Search grounding, ~$0.002/call) 100 RPS for an hour
= ~$72 before the Cloud cap (R1) kicks in. Per day if undetected: ~$1,700.

**Close it by:** W2.3-follow-up (task #33). Either add `getAuthenticatedUser`
gating, or convert the iOS callers to go through an authenticated proxy
api route. ~2 days of work.

---

### R3. Prompt regression that 5–10×s token usage  *(likelihood: medium, impact: $$$)*

`coaching-agent` already concatenates 14+ context blocks unconditionally
and pulls 150 raw training logs. A drive-by edit that adds another
context block (or accidentally bumps `.limit(150)` to `.limit(500)`)
multiplies input tokens with no review-time signal. At 700 chat calls/day
× 8k tokens × 5× growth = $36/day extra ≈ $1,100/month silently.

**Worst case:** a refactor that drops the conversation-history summarization
heuristic in place today (50 message limit) and dumps full thread history
could 20× input on long-conversation users.

**Close it by:** W2.1 (eval harness, 5 days, not started) gives you per-PR
input-token diffs against pinned baselines. C.2 (compress coaching-agent
context, 2 days) caps the input size structurally with token budgets.

---

### R4. HealthKit / Strava import burst on new-user onboarding  *(likelihood: high, impact: $)*

iOS first-launch dumps the user's full HealthKit history. Strava sync
similarly. Each insert into `training_logs` triggers
`generate-workout-insight` (~$0.001/call) and `evaluate-coachable-moment`
(~$0.0005/call). A user with 5 years of running history = 1,500
inserts × $0.0015 = **$2.25 per new user onboarding** in LLM cost alone.

**Worst case:** at 1k users with 60% having multi-year history, onboarding
cost is $1,350 amortized. The outbox pattern prevents pg_net storms but
doesn't reduce per-call cost.

**Close it by:** add a "backfill" mode to `generate-workout-insight` that
skips workouts older than 90 days (those don't need real-time coaching
insights — they're history). Or batch-process backfill at off-peak with
a cheaper model. ~1 day, schedule before scaled launch.

---

### R5. Compromised service-role key bypasses all per-user limits  *(likelihood: low, impact: $$$$$)*

The service-role key bypasses RLS, bypasses per-user rate limits, and
can call any edge function with no quota. If exfiltrated (env leak in a
log, Sentry breadcrumb, vulnerable npm dep), an attacker has unlimited
access until the Cloud cap (R1) catches them.

**Worst case:** sustained Gemini Pro calls at 50 RPS for 12 hours could
hit $1,000+ before R1 stops it.

**Close it by:** the W1.3 env-server boundary makes accidental client-side
leaks much harder. Beyond that: rotate the service-role key on a cadence
(quarterly), monitor `usage_tracking` for anomalies, and keep Sentry's
PII scrubbing on. R1 is the actual hard stop.

---

### R6. Pro model creep  *(likelihood: medium, impact: $$)*

Gemini 2.5 Pro costs ~4× Flash. Two functions use it today
(`generate-training-plan`, `training-analysis`). A well-meaning quality
improvement could move another function from Flash → Pro and 4× the
contribution of that surface to the bill.

**Worst case:** moving `coaching-agent` complex tier to Pro = 700 calls/day
× 4× cost = +$220/month on what's already the biggest line item.

**Close it by:** C.8 (training-analysis Pro→Flash audit, 0.5 days) +
add Pro usage to the daily Slack alert breakdown (line-itemed in W1.1
already). Also: PR review checklist item — model changes need explicit
justification.

---

### R7. Output-token regression via prompt injection  *(likelihood: medium, impact: $)*

The router currently caps outputs at 2k (moderate) and 3k (complex)
tokens. A prompt-injection that gets the model to dump max output =
5× normal cost per call. Combined with R2 (unauthenticated functions),
an attacker could chain this.

**Worst case:** at 700 chat calls/day with 100% hitting max output =
+$0.50/day. Modest but compounds with R2 to make R2 worse.

**Close it by:** C.6 (drop output caps to 800/1500, 0.3 days) bounds
this regardless of injection success.

---

### R8. Weekly cron amortization at scale  *(likelihood: high, impact: $)*

`weekly-coaching-report` runs every Sunday for every active-plan user.
At 1k users with ~$0.05 per report = $50/week = $200/month. Linear with
user count. At 10k = $2,000/month just for weekly reports.

**Worst case:** not really a "spike" — it's predictable. But it's a fixed
monthly cost that grows with users regardless of engagement.

**Close it by:** C.4 (move 80% of weekly-coaching-report to deterministic
code, 2 days). Cuts the cron from $0.05/report to ~$0.01/report — 80%
savings, $40 → $8/week at 1k. At 10k that's $400 vs $2,000.

---

### R9. Retry storms during provider outages  *(likelihood: medium, impact: $)*

The coach-insight outbox retries failed jobs 3× with exponential backoff.
A sustained Gemini outage (rare, but they happen) means **every job
runs 3× before giving up**. At 860 jobs/day × 3 = 2,580 attempts, each
consuming tokens before the error.

**Worst case:** Gemini Flash outage for 4 hours during peak = ~140 jobs
retried 3×. Extra cost: ~$0.30. Modest. But on the transcribe path with
3 providers (Groq → OpenAI → Gemini), a Groq outage means every voice
log pays for OpenAI/Gemini fallback at ~3-10× Groq cost.

**Close it by:** transcribe already has fallback ordering (cheapest first).
Coach-insight outbox is OK — the cost is bounded. For transcribe,
consider a circuit breaker that disables Groq for 5 min after first
failure to avoid paying for two attempts on every log.

---

### R10. Anthropic / Groq cost not visible in the daily Gemini alert  *(likelihood: low, impact: $)*

The W1.1 alert pulls from `usage_tracking` which logs the model_used.
The Slack message and Cloud cap are Gemini-specific. Anthropic spend
(fitness-predictor on Haiku) and Groq spend (coaching-agent simple
tier) flow through their own provider dashboards.

**Worst case:** a UX change makes fitness-predictor fire 10× more often.
Claude Haiku $0.80/M in + $4/M out = $24/month at 1k users currently;
10× = $240/month with no Gemini alert to surface it.

**Close it by:** add Anthropic + Groq billing dashboards to the on-call
runbook (W3.4). Or expand the Slack alert to query usage_tracking by
provider, not just by model_used.

---

### R11. Inline-prompt growth without review signal  *(likelihood: medium, impact: $)*

`generate-training-plan`, `subscribe-to-plan`, and `parse-training-plan`
still have inline LLM prompts (not migrated to `_shared/prompts/` yet).
A drive-by edit that adds 500 tokens to one of those system prompts
costs $0.0003/call at Flash — at 100 calls/day that's $0.90/month silent
growth per surface. Per-call small, compounds invisibly across edits.

**Worst case:** five drive-by edits over a quarter add 2k tokens collectively.
At 1k calls/day total = $45/month silent.

**Close it by:** finish prompt-library migration for those three functions
(scope is in C.2/C.3 prereq work, ~1 day each).

---

### R12. Tier ambiguity — free vs pro detection failure  *(likelihood: low, impact: $)*

`coaching-agent` reads `user_tiers` for tier detection. If the lookup
fails or returns null, the code defaults to `"free"` (5 calls/day).
That's the safe default. But if there's ever a bug where the default
flips to `"unlimited"`, every user gets 100/day for free.

**Worst case:** at 1k users × 50 calls/day average (vs the intended 5) =
10× cost on coaching-agent = $1,000/month extra.

**Close it by:** explicit assertion that tier in `{free, pro, unlimited}`
or fail-closed to `free`. Already what the code does, but worth a unit
test pin.

---

## What closes the most risk fastest

In order of $-saved-per-engineering-hour:

1. **Set the Google Cloud billing cap** — closes R1 (worst case
   $2,000/spike → $50 hard ceiling). 5 minutes of operator time.
2. **Wire the daily Slack spend alert** — gives you 24-hour anomaly
   detection. Already written, ~15 minutes of operator time. (W1.1
   remaining steps.)
3. **W2.3-follow-up (auth audit for 7 functions)** — closes R2 (worst
   case $1,700/day → ~$0). ~2 days engineering.
4. **C.2 (compress coaching-agent context)** — closes R3, R7. Saves
   ~$50-70/month at 1k, prevents silent regression. 2 days.
5. **W2.1 (eval harness)** — closes R3, R6, R11. The wedge-defining
   work. 5 days.

If you only do one thing this week: **R1**.

If you only do one thing this month: **W2.3-follow-up + the eval harness
W2.1**.

---

## What the daily Slack alert will look like for these risks

Once W1.1's remaining operator steps are done, the daily message
surfaces these risks naturally:

- R1 (no cap): the $$$ total is the alert
- R3, R6, R11: model-line-items show shifts day-over-day
- R8: weekly cron shows up as a Sunday spike
- R10: only Gemini visible; Anthropic + Groq need separate monitoring

The alert is your trip-wire. The Cloud cap is the actual stop. The
eval harness is the regression sieve. Treat them as three layers; none
substitutes for the others.

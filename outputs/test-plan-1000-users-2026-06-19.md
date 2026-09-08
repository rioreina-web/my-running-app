# Test plan: getting to 1000 beta users

**Date:** 2026-06-19
**Goal:** harden the product enough to put ~1000 real runners on it without
(a) the backend falling over, (b) one runner seeing another's data, or
(c) the AI saying something it shouldn't.
**Concurrency assumption:** light — a handful of users active at once, mostly
background HealthKit/Strava syncs. This matters a lot (see "Reality check" below).
**Audience note:** this app is vibe-coded by a non-engineer, so this plan calls
out the traps that bite vibe-coded apps specifically, and tells you what to hand
to an AI coding assistant versus what you should eyeball yourself.

---

## TL;DR — what to do, in order

1. **Lock the data-privacy door first (RLS).** This is the only bug class on the
   list that can't be hot-fixed after the fact — if user A's training journal
   leaks to user B, the trust damage is permanent. You have RLS on 40 tables but
   *no automated test that actually proves isolation holds.* Fix that this week.
2. **Don't load-test for 1000 concurrent — you don't have 1000 concurrent.**
   Test the *spiky background-sync* pattern you actually have, plus your two real
   ceilings: the LLM/Gemini provider and your database connection pool.
3. **Finish the AI eval coverage you already started.** The harness exists and CI
   already blocks prompt changes without it — but most cassettes are empty stubs.
   Empty stubs that don't fail the build are worse than no harness, because they
   *look* covered.
4. **Add a dead-simple beta feedback loop + crash/error visibility** before you
   invite anyone. You cannot fix bugs you never hear about, and beta users won't
   file good reports unless you make it one tap.

Everything below expands these into concrete, copy-pasteable work.

---

## Reality check: "1000 users" is three different problems

You picked all three goals, which is right — they're genuinely separate and a
test that proves one tells you nothing about the others.

| Problem | The real question | What kills you if you skip it |
|---|---|---|
| **Load / scale** | Does the backend stay up at your *actual* traffic shape? | App is slow or errors out during morning sync rush; users churn silently. |
| **Beta process** | When something breaks for a real user, do you find out and can you reproduce it? | Bugs happen invisibly; you "fix" things by guessing; users quietly leave. |
| **Correctness** | Does the math/AI give right + safe answers across many bodies, not just yours? | A confident-but-wrong pace zone or an AI injury "diagnosis" erodes the one thing the product sells: honest observation. |

The single most important framing for a vibe-coded app: **your test suite is the
only thing standing between you and silently shipping a regression you don't
understand.** When you (or an AI assistant) change code you didn't fully write,
tests are how you find out you broke something. So coverage isn't bureaucracy
here — it's your safety net for continuing to build.

---

## Where you actually stand today (the good news)

You are well ahead of a typical vibe-coded app. Inventory from the repo:

- **iOS:** unit tests in `RunningLog/RunningLogTests/` — pace calc, fitness
  predictor, workout generation, backup/restore, Coach Read decoding.
- **Edge functions (Deno):** ~44 functions, with co-located `*.test.ts` across
  `_shared/` (pace math, dedup, workout segmentation, builders, rules) and a
  tenant-isolation test in `_shared/athlete-state.test.ts`.
- **Web:** contract + smoke tests in `web/tests/` (rate-limit, env boundary,
  pace round-trip).
- **ML service:** `ml-service/tests/` (auth, health).
- **CI:** `.github/workflows/ci.yml` runs typecheck + tests on every PR across
  all four stacks; `record-evals.yml`, `drift-detector.yml`, `deploy.yml` exist.
- **AI eval harness:** `supabase/functions/_evals/` exists and CI *blocks* prompt
  changes that lack cassette coverage (`check_eval_coverage.py`).
- **Rate limiting:** real implementation in `_shared/rateLimit.ts` with a
  circuit breaker.

This is a strong base. The gaps below are specific holes, not "you have nothing."

---

## The gaps that matter for 1000 users

### Gap 1 — RLS is enabled but never *proven* (HIGHEST PRIORITY)

**What I found.** 40 tables have `ENABLE ROW LEVEL SECURITY`. You've already been
bitten by this class of bug — there are 11 RLS-fix migrations, a documented
tenant-leak hotfix (`HOTFIX-H.1`), and a whole `docs/conventions/rls-checklist.md`
written because "we accumulated 9 RLS-fix migrations in 2 months." The one
automated guard is `athlete-state.test.ts`, which tests the *application code's*
tenant filter — **not the database policies themselves.**

**Why it's the scariest item.** RLS is the wall between two strangers' private
training data. Every other bug here is recoverable. A data leak is not — it's a
trust event, possibly a legal/privacy one, and with 1000 strangers (not your
friends) the blast radius is real. The checklist even says step 7 is "manually
test the RLS by querying as a non-owner user" — manual testing doesn't survive
contact with a vibe-coded change velocity.

**The vibe-coded trap here.** The repo convention historically appended
`OR auth.uid() IS NULL` to policies (a service-role/dev fallback). A later
migration dropped many of these, but 13 migrations still reference the pattern.
Because migrations are append-only, *you cannot tell which policies are currently
live by reading any single file* — you have to query the running database. An AI
assistant generating a "quick new table" will not reliably add RLS, and the
fallback pattern means a missing policy can silently read as "allow."

**What to do.**
- Write an **automated tenant-isolation test that runs against a real Postgres**
  (local Supabase), seeds two users, and asserts user B gets *zero rows* from
  every user-owned table when querying as B. A starter version is in
  `outputs/starter-tests/rls-tenant-isolation.test.sql` (this folder).
- Add a CI step that fails if any table has RLS enabled but **no SELECT policy**,
  or any policy still carries the `auth.uid() IS NULL` bypass on a user-owned
  table. Treat the bypass as a defect to be justified, not a default.
- Make "new table → isolation test row added" a hard rule for any AI assistant
  you delegate to. Put it in `CLAUDE.md` (you already have the checklist; add the
  *test* requirement next to it).

**How you'll know it's done.** A test you can run with one command that goes red
if you delete a policy.

---

### Gap 2 — No load testing, and the load you'd test for is the wrong load

**What I found.** No k6 / Artillery / Locust scripts anywhere in the repo. (The
only "load" matches are image filenames.)

**The reframe.** You said light concurrency — a handful active at once. That's
almost certainly true for a 1000-person beta where people open the app once a day.
So **do not** spend a week simulating 1000 concurrent users; that models traffic
you won't have and will just scare you with numbers that don't apply. Instead test
the three things that actually bite at your scale:

1. **The background-sync thundering herd.** HealthKit/Strava syncs and the
   `drain-*` job functions (`drain-voice-processing-jobs`,
   `drain-coachable-moment-jobs`, `drain-coach-insight-jobs`) are cron/event
   driven. The risk isn't 1000 humans tapping at once — it's 1000 *sync jobs*
   landing in a narrow window (e.g., everyone's watch syncs after a morning run).
   Good news: the voice queue already uses a claim-based RPC
   (`claim_voice_processing_jobs`) with re-queue, so it's designed for this.
   **Test that the claim/drain pattern actually keeps up** when you enqueue, say,
   500 jobs at once, and that nothing double-processes.
2. **Your LLM provider ceiling.** Coach Read (`coaching-daily-read`),
   `coaching-agent`, and the parsers all call Gemini. Your real throughput limit
   for AI features is the provider's rate limit and latency, *not* your server.
   If 200 people hit "generate my Read" in the same hour, you need to know whether
   you hit Gemini quota and what the user sees when you do (a graceful "try again
   in a minute," not a spinner of death).
3. **Database connection pool.** Supabase/Postgres has a connection ceiling. Many
   edge functions each opening connections under a burst is the classic way a
   "light load" app falls over. Confirm you're using the pooler and that a burst
   of `drain` + sync doesn't exhaust connections.

**What to do.**
- Use **k6** (simplest for a non-engineer; one JS file, one command). A starter
  script that hammers your most expensive *unauthenticated-safe* endpoint and
  ramps a realistic burst is in
  `outputs/starter-tests/k6-burst-smoke.js` (this folder). Point it at staging,
  never prod.
- Before inviting users, do a **one-time "morning rush" rehearsal**: enqueue a
  few hundred synthetic sync + voice jobs on staging and watch the drain
  functions, Gemini error rate, and DB connections. This is a 30-minute test that
  tells you more than any synthetic concurrency number.
- Add **provider-failure handling tests**: assert that when Gemini returns 429 /
  times out, the user-facing surface degrades gracefully (Hard rule #8: empty
  states, never an em-dash or a hang).

**The vibe-coded trap.** It's tempting to test "can it do 1000 at once" and feel
safe. The failure you'll actually hit is a *cost/quota* failure (Gemini bill or
rate limit) and a *connection-pool* failure, both invisible until they happen.
Test those, not a vanity concurrency number.

---

### Gap 3 — AI eval coverage is mostly empty stubs (and that's a trap)

**What I found.** The harness in `_evals/` is real and CI enforces it — but per
its own README: `injury-analysis.v1` has 3 recorded cassettes;
`process-training-memo.v1` is **stubs** (rubric pinned, no recorded response);
`coaching-agent-*` and `reschedule-plan` have **zero**. Stubs deliberately don't
fail the build.

**Why this is sneaky.** A stub looks like coverage in a list but tests nothing.
The CI gate checks that a cassette *directory exists*, not that it's filled. So a
prompt change can pass CI while its actual behavior is unverified. For the two
flows you flagged as critical — **Coach Read generation** and **voice
memo/Niggles classification** — this is exactly where your "AI advises, never
acts / never diagnoses" promise lives. That promise is the product. An unverified
prompt change that starts saying "you have ITBS, rest 2 weeks" violates your own
Hard Rule #2 and the closed-vocabulary Niggles design.

**What to do.**
- **Fill the `process-training-memo` stubs first** (Niggles classifier) — the
  README gives you the exact record command. The three cases already pinned are
  the right ones: positive long run, injury-mention-without-diagnosis, and
  cross-training-soreness-is-not-injury.
- **Add cassettes for `coaching-daily-read` / `coaching-agent`** covering the
  voice-posture rules you care about: feeling-first, no medical claims, no
  prescriptions, anchors carried silently, range+confidence on predictions
  (Hard Rule #7), no em-dash empty states (Hard Rule #8).
- **Tighten the CI gate** so a prompt directory with only empty stubs counts as
  *uncovered* for that prompt (or at least prints a loud warning). Right now
  "directory exists" is too weak a check.

**Effort note.** This is the highest-leverage AI work and it's mostly *writing
example inputs + a rubric*, which you can do without deep coding. Pair with an AI
assistant: you supply real voice-memo text and the "right answer," it wires the
cassette.

---

### Gap 4 — No beta feedback / error-visibility loop

**What I found.** You have Sentry wired in web (`@sentry/nextjs` in
`web/package.json`), which is great. I did not find an equivalent
crash/error-reporting path described for the iOS app or a structured in-app way
for a beta user to report "this looks wrong."

**Why it matters more than tests.** For a 1000-person beta, *the users are your
test suite for everything you didn't think to test.* But only if you hear from
them. Two things must be true before you invite anyone: you see crashes/errors
automatically, and a confused user can flag something in one tap with enough
context for you to reproduce it.

**What to do.**
- **iOS crash + error reporting.** Add a crash reporter (Sentry has an iOS SDK;
  or TestFlight's built-in crash logs as a zero-cost start). Without this, iOS
  crashes are invisible to you.
- **One-tap "this looks wrong" in the app**, attaching the current screen + a
  reference ID so you can find the user's state. Even a mailto: with a prefilled
  subject is fine for v1.
- **Run the beta through TestFlight** (you're iOS-first). TestFlight gives you
  staged rollout (invite 50 before 1000), per-build feedback, and crash logs for
  free. Don't go from 0 to 1000 — ramp 25 → 100 → 1000 and watch each step.
- A starter beta-ops checklist is in
  `outputs/starter-tests/beta-rollout-checklist.md` (this folder).

---

### Gap 5 — No end-to-end test of a real user's first 10 minutes

**What I found.** Lots of unit tests on the *pieces* (pace math, decoding,
builders), but no test that walks the **critical path a new beta user hits**:
sign in → 2-year HealthKit backfill → races auto-detected → first voice memo →
first Coach Read. Each piece is tested; the *seam between them* is not.

**Why vibe-coded apps break here.** Unit tests pass while the app is broken,
because the bug is in the wiring between components (a nil `activePlan`, an empty
backfill, a race with no anchor). Your own CLAUDE.md says `activePlan == nil` is a
first-class state — that's exactly the kind of empty/edge state that slips through
unit tests and blows up on a real new user with sparse data.

**What to do.**
- Add a **smoke test of the new-user path** against staging with a seeded test
  account that has *almost no data* (the `data_depth = 0` case). Assert the app
  shows empty states (not crashes, not em-dashes) at every surface.
- Add the **opposite extreme**: a test account with a 2-year backfill and many
  races, to catch pagination/perf issues in the journal and Trends chart.
- These two synthetic accounts ("empty Maya" and "loaded Maya") are the cheapest,
  highest-signal QA you can keep. Document them so you re-test them every release.

---

## Priority + sequencing

Do them in this order. Each phase is shippable on its own.

**Phase 0 — before you invite a single stranger (this week)**
- RLS automated tenant-isolation test + CI policy check (Gap 1).
- iOS crash reporting + one-tap feedback (Gap 4).
- "Empty Maya" / "Loaded Maya" smoke accounts (Gap 5).

**Phase 1 — before you scale past ~100 users**
- Fill `process-training-memo` eval stubs; add `coaching-daily-read` cassettes
  (Gap 3).
- "Morning rush" sync/queue rehearsal on staging + Gemini-429 graceful-degrade
  test (Gap 2).
- Tighten the eval CI gate so empty stubs don't read as covered (Gap 3).

**Phase 2 — before the full 1000 / public**
- k6 burst smoke in CI against staging (Gap 2).
- DB connection-pool burst check (Gap 2).
- Backfill remaining `coaching-agent` / `reschedule-plan` cassettes (Gap 3).

**Always-on (the habit that keeps a vibe-coded app alive)**
- Every new table ships with RLS *and* a row in the isolation test.
- Every prompt change ships with a filled (not stub) cassette.
- Re-run the two smoke accounts every release.

---

## Coverage targets (don't chase 100%)

For a solo/non-engineer team, blanket coverage is a trap — it's slow to write and
most of it tests trivia. Aim coverage where a bug is expensive:

| Area | Target | Why |
|---|---|---|
| RLS / tenant isolation | 100% of user-owned tables | Unrecoverable if it leaks |
| Pace + fitness math | High — every zone + edge (slow HM, no anchor) | Wrong numbers = lost trust; you already have a good base here |
| AI prompts (Coach Read, Niggles) | Every safety rule has a cassette | The product *is* the AI's restraint |
| New-user / empty-state path | The full first-10-minutes flow | Where wiring bugs hide |
| Everything else | Test on bug, don't pre-test | Diminishing returns for a small team |

Skip: trivial getters, framework glue, one-off scripts, anything in
`.claude/worktrees/` (stale, do not source from there).

---

## What to hand an AI assistant vs. do yourself

**Delegate to an AI coding assistant (low judgment, high typing):**
- Writing the RLS isolation test from the starter file.
- Writing the k6 script and pointing it at staging.
- Filling cassette JSON once *you* supply the example input + correct answer.
- Adding the iOS crash reporter SDK.

**Do yourself / eyeball (high judgment):**
- Deciding the "right answer" for every AI eval cassette — that's product taste,
  not code.
- Reading the live RLS policies in the database (an assistant can't see prod;
  use the Supabase dashboard or MCP read-only tools).
- Watching the morning-rush rehearsal and judging "is this latency okay."
- Deciding rollout ramp (25 → 100 → 1000) based on what you see.

**The one rule that matters most for you:** never let an assistant add a new table
or change a prompt without the matching test in the same change. That single
discipline is what keeps a vibe-coded product from rotting as it grows.

---

## Starter files in this folder (`outputs/starter-tests/`)

- `rls-tenant-isolation.test.sql` — seeds two users, asserts B can't read A.
- `k6-burst-smoke.js` — realistic burst load script for staging.
- `beta-rollout-checklist.md` — pre-invite + staged-rollout checklist.

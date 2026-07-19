# Beta rollout checklist — 0 → 1000 users

A staged plan for putting real runners on a vibe-coded app without getting
surprised. Don't skip the ramp. Each gate is "don't proceed until."

## Before you invite anyone (Phase 0)

- [ ] **RLS isolation test passes** (`rls-tenant-isolation.test.sql`) covering
      every user-owned table. This is non-negotiable — strangers' private data.
- [ ] **iOS crash reporting live** (Sentry iOS SDK, or rely on TestFlight crash
      logs as a zero-cost start). You must see crashes you didn't witness.
- [ ] **One-tap "this looks wrong" feedback** in the app, attaching current
      screen + a reference ID. A prefilled mailto: is an acceptable v1.
- [ ] **Two smoke accounts exist and pass:**
      "empty Maya" (`data_depth = 0`, almost no data → every surface shows an
      empty state, not a crash or an em-dash) and "loaded Maya" (2-year backfill,
      many races → journal + Trends chart stay fast).
- [ ] **Staging environment is real** (not pointing the app at prod). Load and
      burst tests run here only.
- [ ] **Gemini / LLM failures degrade gracefully** — a 429 or timeout shows a
      friendly retry, never an infinite spinner.
- [ ] **You know your costs** — estimate Gemini + Supabase cost at 1000 users
      doing one Coach Read/day. A surprise bill is its own kind of outage.

## Invite 25 (close friends / forgiving users)

- [ ] Watch crash + error dashboards daily.
- [ ] Triage every piece of feedback within 24h — at this size you can.
- [ ] Confirm the new-user first-10-minutes path works on devices that aren't
      yours (different iOS versions, no HealthKit history, etc.).
- [ ] Gate to proceed: **no data-isolation issues, no crash on the happy path.**

## Invite 100

- [ ] Run the **"morning rush" rehearsal** on staging: enqueue a few hundred
      synthetic sync + voice jobs, watch the `drain-*` functions keep up, no
      double-processing, DB connections stay healthy.
- [ ] AI eval cassettes filled for Coach Read + Niggles (no empty stubs).
- [ ] Watch p95 latency and Gemini error rate as real usage rises.
- [ ] Gate to proceed: **error rate < 1%, no runaway costs, feedback themes are
      product nits not "it's broken."**

## Invite 1000 / open up

- [ ] k6 burst smoke runs green against staging in CI.
- [ ] DB connection-pool burst check passes (using the pooler, no exhaustion).
- [ ] Remaining `coaching-agent` / `reschedule-plan` cassettes backfilled.
- [ ] A rollback plan exists: if a bad build ships, how fast can you pull it?
      (TestFlight: expire the build. Backend: revert + redeploy.)

## The ongoing habits (this is what keeps it alive)

- [ ] New table → RLS policy + isolation-test row, same change.
- [ ] Prompt change → filled cassette, same change (CI already blocks this;
      make sure stubs don't sneak through).
- [ ] Every release → re-run the two smoke accounts.
- [ ] Weekly → skim crash + error dashboard even when nothing's reported.

## Why the ramp matters for a vibe-coded app

You didn't write all this code line by line, so your mental model of how it
behaves has gaps. The ramp (25 → 100 → 1000) is how you discover those gaps with
25 forgiving people instead of 1000 strangers. Each gate exists to catch a
specific class of problem while the audience is still small enough to apologize to.

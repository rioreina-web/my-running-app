# Finish checklist — 2026-07-02 session

What was built this session and exactly what's left to ship it. Nothing below
is blocked on more code from me — the remaining work is committing, pushing,
deploying, and cutting an app build (your infra/accounts).

---

## What's done and committed

Three commits are stacked on your working branch, unpushed:

- `9aaebd5` — **fitness_snapshots server writer** (ported predictor module +
  tests, `compute-fitness-snapshot` edge fn, cron + user_id cleanup migrations,
  iOS empty-id guard + anchor-displacement fix).
- `524ed43` — **life_context slice** (migration, `buildLifeContext` + tests,
  athlete-state wiring, effort_level + stress_level real-data adaptation).
- `de6ae5f` — **coaching-agent 400 fix** (removed non-existent `proactive`
  column from the `conversation_messages` insert).

## Done but NOT yet committed

- **Ask-the-Coach fix** (iOS): `DailyReadService.swift` + `CoachRead.swift`.
  The decoder now accepts both the editorial `{read}` and the chat `{response}`
  response shapes, so the ask screen renders instead of "Couldn't reach the
  coach." ⚠️ These two files are being edited by another session concurrently —
  they carry hunks I didn't write. Commit them **hunk-aware** (`git add -p`),
  not with a blanket `git add`, or you'll clobber the other work.

---

## To finish — required steps

1. **Commit the ask fix** (hunk-aware) from `DailyReadService.swift` +
   `CoachRead.swift`. Verify my `fromPlainText` addition and the
   chat-shape branch in `AskEnvelope` are included.

2. **Push** all commits.

3. **Deploy the backend** (per CLAUDE.md hard rule #9, migrations only via
   `supabase db push` from the committed SHA):
   - `supabase db push` — applies the 3 new migrations:
     `20260702100000_athlete_state_life_context.sql`,
     `20260702174900_fitness_snapshots_userid_cleanup.sql`,
     `20260702175000_nightly_fitness_snapshot.sql`.
   - `supabase functions deploy compute-fitness-snapshot`
   - `supabase functions deploy coaching-agent` (ships the 400 fix).
   - **Backfill once:** invoke `compute-fitness-snapshot` with `{ "batch": 25 }`
     (service-role) so every active athlete gets a fresh snapshot immediately.
   - **Verify:** inspect a new `fitness_snapshots` row (confidence tier +
     `range_*` populated, `data_source` like `race (10K)`); regenerate a Daily
     Read and confirm it reads fresh fitness + life context.

4. **Cut a new iOS build** (TestFlight) — carries the ask fix, the empty-id
   guard, and the anchor-displacement fix. Note: the ask bug is client-side, so
   the installed app keeps failing until this build lands.

## Prerequisites to confirm before deploy

- Vault secrets `supabase_url` + `service_role_key` exist (the new cron reuses
  the same ones as the drain crons).
- The nightly-fitness-snapshot cron fires 3:30 UTC, before the 4:00 UTC
  athlete-state rebuild — no action, just FYI.

---

## Optional / not blockers (can follow later)

- **Voice/eval review (Life Context Step 6):** generate a few live Daily Reads
  through `coaching-daily-read` with `GEMINI_API_KEY` to confirm the new
  life-context data reads safely. The static input-layer review already passed;
  no cassette is required (no `_shared/prompts/` file changed).
- **`get_pending_adjustments` RPC 404** — `coaching-agent` calls an RPC that
  doesn't exist in prod. Non-fatal (returns empty), but noisy.
- **`user_profiles` ghost-table punch list** — `post-run-reconciliation`,
  `reconcile-log`, `weekly-coaching-report` still query the dropped table.
  Already tracked in `production-guardrails.contract.test.ts`; repoint to
  `athlete_settings`.
- **Anchor fix is an app-behavior change** — after the new build, eyeball a few
  athletes' predictor screens (a strong old race no longer gets overridden by a
  weak recent tempo).

## Explicitly out of scope for "this project"

- **Hole #2 (niggles into the memo pipeline)** and the other athlete-state
  audit holes (#4 memories-from-memos, #5 HealthKit backfill) — separate
  follow-on work, not part of finishing what we built here.

---

## The shared-tree hazard (read this)

This working tree has ~150 uncommitted changes from other sessions, and at
least one is actively editing the same iOS files as the ask fix. Before doing
anything broad: never `git add -A`. Stage by explicit path or hunk. The three
commits above were deliberately quarantined to only their own files.

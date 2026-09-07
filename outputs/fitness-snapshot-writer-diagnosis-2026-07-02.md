# Fitness-snapshot writer — diagnosis & fix plan

**Date:** 2026-07-02
**Origin:** Step 0 of the Life Context implementation plan (fix #3, "the
one-hour prod check that the fitness backbone is alive"). The check found
the backbone is *not* alive in the way the server assumes, so it was
promoted to its own fix ahead of the Life Context slice.
**Status:** diagnosis complete; fix approved in direction (port iOS logic
to a server cron), not yet implemented.

---

## TL;DR

`fitness_snapshots` is the table that stores each athlete's point-in-time
race predictions (mile → marathon) and the 10K-pace baseline the rest of
the product reads for fitness trend, pace zones, and the Coach Read.

**Nothing on the server writes it — and that's by original design.** The
only writer is the **iOS app**, which computes a prediction on-device and
inserts a row *once a day, and only when the user opens the fitness
predictor screen*. There is no backend job, no cron, and no edge function
that produces a snapshot. The Python `ml-service` has a `/predict-fitness`
endpoint that could, but nothing calls it — it is orphaned.

So the backbone isn't dead, it's **passive**: it only updates when a user
happens to visit one screen. For a growing product where the server
(nightly athlete-state rebuild, Coach Read) needs a fresh fitness signal
for *every* athlete regardless of what screens they open, that's a gap.

**Approved direction:** move snapshot generation server-side — port the
iOS prediction algorithm into a shared TypeScript module and run it
nightly per active athlete via `pg_cron`, mirroring the existing
`nightly-athlete-state-rebuild` job. Also fix two data-integrity bugs
found along the way.

---

## What we verified (prod, read-only)

Project: `RunningAppMVP2` (`aqdijapxmjqaetursrde`), the active prod DB.

**Row counts and freshness:**

| metric | value |
|---|---|
| total rows | 34 |
| distinct user_ids | 3 (but see below — all the *same* person) |
| newest row | 2026-06-12 (20 days stale as of this doc) |
| oldest row | 2026-03-20 |

**The 3 "users" are one athlete under three ids:**

| user_id | rows | note |
|---|---|---|
| `03857bf3-…` (lowercase) | 29 | current, correct casing |
| `03857BF3-…` (uppercase) | 2 | legacy, pre-`.lowercased()` fix |
| `""` (empty string) | 3 | orphaned — written before auth resolved |

This is essentially a pre-launch state with one active tester whose last
visit to the predictor screen was June 12.

**Who writes it:** nobody on the server.

- No edge function inserts to `fitness_snapshots` (all 13 backend
  references are `.select` reads).
- No `pg_cron` job touches it (11 active jobs; none related).
- `ml-service` only *reads* it (`fetch_fitness_snapshots`); its
  `/predict-fitness` endpoint computes but never persists, and no client
  or function calls that endpoint.
- The real writer is iOS: `FitnessPredictorService.saveSnapshot()`
  (`RunningLog/Analysis/FitnessPredictorService.swift:960`), triggered
  when the predictor UI runs, rate-limited to one row per calendar day
  (upsert-today semantics). This matches the table's own header comment:
  *"One snapshot per prediction run, rate-limited to 1/day on the client
  side."*

---

## Root cause

The feature was built client-first. The iOS app owns the prediction math
and writes its own snapshots. The server was only ever a reader. That was
fine when the app was the whole product, but the product has since grown a
server-side brain — the nightly `athlete-state` rebuild and the on-demand
Coach Read both read "the latest snapshot" and silently assume it's fresh.
It isn't guaranteed to be.

### Three concrete problems this creates

1. **No freshness guarantee.** A snapshot only exists after a user opens
   the predictor screen. Between visits, the server reads stale data (20
   days and counting for our tester). The nightly rebuild can't fix this
   because it has no way to generate a snapshot itself.

2. **No coverage for passive users.** Any athlete who never opens the
   predictor has *zero* snapshots. As you add users, the fitness signal is
   missing for everyone who doesn't visit that specific screen — and the
   Coach Read's "where are you going" pillar leans on it.

3. **Two data-integrity bugs:**
   - **Empty-string user_id (live).** `AuthManager.userId` returns `""`
     when accessed before login resolves
     (`RunningLog/Auth/AuthManager.swift:26-30`), and
     `saveSnapshot` doesn't guard against it. Result: rows written with
     `user_id = ""`, invisible to every user and to server reads. Three
     exist today.
   - **Uppercase UUID (legacy, code already fixed).** Older builds wrote
     `UUID().uuidString` (uppercase in Swift). Current code lowercases
     everywhere (`AuthManager.swift` sets
     `currentUserId = session.user.id.uuidString.lowercased()`), so new
     writes are correct; two old uppercase rows remain and are invisible
     to lowercased server reads.

---

## Approved fix — port the iOS logic to a server cron

Guarantees a fresh snapshot for every active athlete nightly, independent
of client behavior, and keeps parity with what users see in-app (we port
the *authoritative* algorithm rather than the divergent Python one).

### Why not the alternatives

- **Wire up the Python `ml-service`.** Less code, but its `_predict_heuristic`
  is a *different, simpler* model than the iOS one. Users would see the
  app's number while the server stored the Python number — two engines
  drifting apart. Rejected.
- **Client writes + server fallback only.** Least work, but doesn't solve
  problem #2 (passive users still have no data). Rejected as the primary
  fix, though the integrity cleanup below is shared with it.

### The algorithm to port (source of truth)

`FitnessPredictorService.generateLocalPrediction()` — ~600 lines,
`FitnessPredictorService.swift:275-915`. Core stages:

1. **Anchor selection** — pick the best fitness anchor by priority:
   confirmed race (durable "proof", wins when ≤16 wks; 16–24 wks it can be
   displaced by a fresh ≤4-wk training anchor; >24 wks a fresh training
   anchor is preferred) → training anchor (hard efforts / structured
   sessions from logs) → training-plan goal → previous-snapshot baseline
   (decay-gated). Output: `anchorPace` (10K sec/mi), source label, weeks-ago.
2. **Decay / maintenance model** — adjust the anchor toward present fitness
   using training stimulus since the anchor date (weekly hard minutes,
   quality-session count, volume trend). Effective decay ranges ~0.03%/wk
   (full training, residual) to ~0.3%/wk (no training); capped at
   +0.2%/wk improvement / −0.4%/wk decay.
3. **Pace-segment validation** — blend the anchor-derived estimate with a
   signal computed from actual hard-effort paces in recent logs, weighted
   by how many hard miles exist.
4. **Race-time derivation** — from the final `estimated10KPace`, derive
   mile/5K/10K/half/marathon via the equivalence ratios in
   `PaceCalculator` (must stay in sync with `workout-helpers.ts` /
   `paces.ts`).
5. **Confidence tiering** — `High` (confirmed race anchor), `Medium`
   (training anchor / plan goal / prior profile), `Low` (thin data /
   defaults). Plus a human-readable `data_source` string and `workout_count`.

**Snapshot row shape to produce** (matches `FitnessSnapshotInsert`):
`user_id, predicted_mile_seconds, predicted_5k_seconds,
predicted_10k_seconds, predicted_half_seconds, predicted_marathon_seconds,
estimated_10k_pace_seconds, confidence, data_source, workout_count`.
Per CLAUDE.md hard rule #7, also populate the honesty columns added in
`20260522130702`: `confidence_tier` + `range_*_seconds` (the point ± window).
The iOS path predates those columns and leaves them null; the server port
should fill them so predictions ship as a range, not a point.

### Implementation steps

1. **Shared module** `supabase/functions/_shared/fitnessPrediction.ts` —
   pure functions porting stages 1–5. Model it on the existing pure
   builders (`_shared/builders/*`). Reuse `_shared/paces.ts` for
   equivalence math (don't re-derive ratios — keep the three-way parity
   with Swift and `workout-helpers.ts`). Unit tests covering: race anchor,
   training anchor, plan-goal fallback, decay over time, pace-segment
   blend, and each confidence tier.
2. **Edge function** `supabase/functions/compute-fitness-snapshot/index.ts`
   — service-role; for a given `user_id`, fetch the same inputs the iOS
   path uses (workouts/features, confirmed races, plan goal, prior
   snapshots), run the shared module, and **upsert today's row** (same
   one-per-day semantics as the app, so app and server don't double-write).
3. **Cron** — add a `pg_cron` job that iterates active athletes and calls
   the function, mirroring `nightly-athlete-state-rebuild` (jobid 14).
   Simplest: run it just before the 04:00 athlete-state rebuild so the
   rebuild reads a fresh snapshot the same night. New migration,
   append-only.
4. **Integrity fixes:**
   - iOS: guard `saveSnapshot` (and ideally `AuthManager.userId`) so a
     snapshot is never written with an empty `user_id`. Skip + log if
     unauthenticated.
   - Data cleanup migration: delete the 3 empty-string rows; lowercase (or
     merge) the 2 uppercase rows into the canonical id. Append-only,
     applied via `supabase db push`.
5. **Backfill (optional, one-off):** invoke `compute-fitness-snapshot` for
   each existing athlete once so today's row is fresh immediately, rather
   than waiting for the first nightly run.

### Cadence decision

Nightly is enough — fitness doesn't move meaningfully intra-day, and the
existing invalidation trigger already refreshes *athlete_state* on new
memos. If we later want a snapshot to refresh right after a hard workout
lands, the same edge function can be invoked from the post-run path; not
needed for v1 of this fix.

---

## Risks & parity concerns

- **Algorithm parity.** The port must match the iOS numbers closely or
  users will see one prediction in-app and the Coach Read will reference
  another. Mitigation: port faithfully, add a parity test with a few
  fixture athletes checked against known iOS outputs, and keep the app as
  the display source of truth during rollout.
- **Double-write.** While the iOS writer still ships, both app and server
  may upsert the same day's row. The upsert-today semantics make this
  safe (last write wins for the same calendar day); longer term, consider
  making the server the sole writer and the app a pure reader.
- **Eval / voice gate.** No `_shared/prompts/` file changes, so the CI
  eval gate won't fire — but this changes what data the Coach Read sees.
  Regenerate a few Daily Reads after deploy to confirm nothing regresses
  (feeds naturally into Life Context Step 6).
- **Hard rules.** Migrations append-only (#5) and reach prod only via
  `supabase db push` from a committed SHA (#9); predictions ship as range
  + confidence (#7); no client-side insert policy assumptions broken
  (service-role writer, #4-adjacent).

---

## Implementation status (2026-07-02, code-complete pre-deploy)

Built and validated, nothing deployed to prod yet:

- **`_shared/fitnessPrediction.ts`** — the ported algorithm (pure). 14 unit
  tests pass; typecheck + lint clean.
- **`compute-fitness-snapshot/index.ts`** — service-role edge function; maps
  `training_logs` / `training_plans` into the module and upserts today's row.
  Config entry added (`verify_jwt = true`).
- **Migrations** `20260702174900_fitness_snapshots_userid_cleanup.sql` +
  `20260702175000_nightly_fitness_snapshot.sql` — parse-validated (real PG
  parser); cleanup impact dry-run-confirmed against prod (3 empty rows deleted,
  2 lowercased, → 1 canonical owner).
- **iOS guard** — `saveSnapshot` now skips empty `user_id`.

Two mapping bugs were caught by checking real prod shapes and fixed:
`workout_pace_per_mile` is `"M:SS"` text (not seconds), and "confirmed races"
live in `training_logs` (`workout_type='race'` + notes), not a `confirmed_races`
table.

### Parity result

Reproduced the last real iOS-written snapshot (2026-06-12) by running the port
at `now=2026-06-12` on that athlete's real logs:

| | iOS (stored) | Port |
|---|---|---|
| est. 10K pace | 313.8 s/mi | 315.7 s/mi (+0.6%) |
| predicted 10K | 32:29 | 32:41 |
| confidence | High | High |
| data_source | `race (10K)` | `race (10K)` |

Within 0.6%, using only a volume subset and post-dedup data. Parity holds.

### Behavioral finding + fix (anchor displacement)

Run at `now=2026-07-02` on the SAME athlete, the port INITIALLY predicted
**6:59/mi → 10K 43:24, Medium** — a huge swing from June-12's 32:29/High.
Cause: the strong Feb 7 "10k race: 31:24" aged past the 16-week race-primary
window, and a modest July 1 tempo (Observer-parsed as a 6:59 10K-equivalent)
displaced it as the anchor. This was **faithful to the iOS algorithm** — the
app showed the same number.

**Fixed (2026-07-02) in BOTH the port and iOS** (`fitnessPrediction.ts` +
`FitnessPredictorService.swift`, identical rule): a recent training anchor may
displace an out-of-primary-window race only when its `equivalentTenKPace` is
strictly FASTER than the race's pace. A weaker recent tempo no longer overrides
proven race fitness; the race stays and is decayed forward. After the fix the
same athlete predicts **33:00, High, `race (10K)`** at `now=2026-07-02` — the
sensible decayed-race result. Covered by two new unit tests (16 total).

## Deploy runbook (remaining — committed release)

Everything above is code-complete and validated locally. The remaining steps
touch prod and must go through the committed flow (hard rule #9), not ad-hoc
MCP applies. Recommended order:

1. **Commit** all of: `_shared/fitnessPrediction.ts` (+ `.test.ts`),
   `compute-fitness-snapshot/index.ts`, `config.toml` entry, the two
   migrations, and the iOS `FitnessPredictorService.swift` + `AuthManager`
   guard changes.
2. **`supabase db push`** from that SHA — applies the cleanup migration
   (deletes 3 orphan rows, lowercases 2) and schedules the `nightly-fitness-
   snapshot` cron. Prereq: Vault secrets `supabase_url` + `service_role_key`
   (same as the drain crons) are present.
3. **Deploy the edge function** — `supabase functions deploy
   compute-fitness-snapshot` (or the Deploy workflow). The CLI bundles the
   `../_shared/*` imports.
4. **Backfill once** — invoke `compute-fitness-snapshot` with `{ "batch": 25 }`
   (service-role) so every active athlete gets a fresh row immediately instead
   of waiting for 3:30am UTC.
5. **Verify** — inspect the new `fitness_snapshots` row(s): confidence tier +
   `range_*_seconds` populated, `data_source` reads like `race (10K)`, pace
   sane. Then regenerate a Daily Read for the test athlete to confirm the Coach
   Read now reads fresh fitness (feeds Life Context Step 6).
6. **iOS** ships in the next app build (guard + anchor fix); no separate deploy.

## Out of scope (return here after)

- The **Life Context slice** (audit fix #1) — resumes once snapshots are
  reliable. When it resumes, build the reader to the *real* memo data
  (promote `effort_level`, read both key-name vocabularies) per the Step 0
  findings, not the original wish-list.
- Retiring the orphaned `ml-service /predict-fitness`, or repurposing it as
  the server predictor instead of a TS port (deliberately not chosen here).
- Making the iOS app a pure reader (a follow-up once server parity is
  proven).

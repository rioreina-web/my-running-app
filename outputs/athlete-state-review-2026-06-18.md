# athlete-state.ts — Review & Bounded-Fix Plan

**Date:** 2026-06-18
**Reviewer pass over:** `supabase/functions/_shared/athlete-state.ts` (2,556 LOC)
**Companion:** `athlete-state-refactor-design.md` (the full §3 rebuild — *deferred*),
`outputs/athlete-state-v2-coach-grade-2026-06-12.md`,
`outputs/athlete-state-smarter-coach-recs-2026-06-12.md`

---

## TL;DR

**We are NOT rebuilding it.** The §3 folder-split-into-builders plan in
`athlete-state-refactor-design.md` is the rebuild, and it's deferred (3–4 weeks,
low urgency now that the P0 safety work shipped). This doc proposes **three
bounded, independently-shippable fixes** on the file as it stands — ~3–4 focused
days total.

| # | Fix | Effort | Risk | Ships alone? | Status |
|---|---|---|---|---|---|
| 1 | Token budget in `stateToPromptContext` | 0.5–1 day | Low (eval gate) | Yes | **DONE 2026-06-18** (enforced cap # still TBD) |
| 2 | Unify the two `running_workout_laps` fetches + instrument | ~1 day | Low | Yes | **DONE 2026-06-18** |
| 3 | Extract `dedup` / `sessions` / `format` to `shared/` + unit tests | 1–2 days | Low | Yes | **DONE 2026-06-18** |

### Progress log

**2026-06-18 — Fix 3 shipped.** Extracted `_shared/shared/dedup.ts` (the
cross-source dedup, previously copy-pasted at two sites — R2 closed),
`_shared/shared/sessions.ts` (`groupIntoSessions`), `_shared/shared/format.ts`
(`formatPace`/`formatTime`/`formatTimeDelta`). `athlete-state.ts` imports them
and re-exports `formatPace` for backwards compat. **17 new unit tests**, all 10
existing `athlete-state.test.ts` tests still pass, clean `deno check`. No prompt
change → no eval gate.

**2026-06-18 — Fix 2 shipped.** Collapsed the two `running_workout_laps` fetches
into one wide-column query over the union of (28-day recent ∪ 84-day fitness)
ids, chunked and run with `Promise.all` instead of the old serial loop. The
fitness signal now reuses that single map. Added rebuild timing instrumentation
(`[AthleteState] rebuild … total=… laps_fetch=… laps_workouts=…`) so p50/p95 can
be read off prod logs. Type-checks clean; all regression tests pass. No prompt
change → no eval gate.
*Follow-up:* p95 must be read from prod logs (the test fake-client doesn't model
lap-table latency); consider a laps-integration test when segmentation fixtures
are next touched.

**2026-06-18 — Fix 1 shipped (mechanism), enforced cap still open.**
`stateToPromptContext` is now assembled from priority-ranked sections and pruned
under a token budget (`assemblePromptSections`). Each section's body is the
original code verbatim (closure param named `lines`), so output is byte-identical
to the pre-budget version when nothing is dropped. Priorities: P1 never-drop =
identity, pace zones, injuries; P2 = goals, load, predicted, schedule; P3 = vibe,
recent workouts; P4 = fitness signal, execution, niggles, trajectory; P5 =
conditions, patterns, data gaps; P6 = memories, blocks, races.
- **Default budget is `Infinity`** → NO pruning in production yet, so this is
  eval-safe: prod prompts are unchanged. The rendered token estimate is logged
  whenever it exceeds the 420 soft target (`[AthleteState] prompt tokens≈… …`),
  so we can pick the enforced cap from real distributions.
- **5 new tests** (`athlete-state-prompt-budget.test.ts`): no-prune default,
  tiny-budget pruning order, monotonicity, and the priority-1 floor (pace
  zones + injuries never drop even at budget 1). Existing prompt test
  ("Step 7+") still passes → under-budget output preserved.
- **Eval gate:** because the default doesn't change output, no eval re-run is
  strictly required to merge the mechanism. The eval review IS required when we
  flip the default to a finite cap — that's the change that can alter prod
  prompts for data-rich athletes.

**2026-06-18 — Reliability hardening (review findings #3, #4, dead-`version`).**
Eval-safe (observability only; no happy-path output change):
- **Silent query failures (#4):** added an error audit over all 14 `Promise.all`
  source reads (`source read '<table>' failed (slice degraded)`), plus explicit
  `.error` logging on the previously-silent secondary reads (`scheduled_workouts`
  ×2, `body_mentions` history, the parallel `running_workout_laps` chunks) and on
  the two final `athlete_state` upserts (the state upsert logs at `error` level —
  a failed persist loses the rebuild). The design's full "preserve previous slice
  on failure" is still pending; this makes the degradation visible first.
- **Concurrency residual risk (#3):** documented the claim/poll fall-through as a
  KNOWN LIMITATION in code (lock not held for the rebuild body → bounded
  last-write-wins interleave). True fix is the §3 `lock.ts` — deferred.
- **Dead `version` (#4 smaller):** replaced hardcoded `version: 1` with an
  exported, documented `ATHLETE_STATE_SCHEMA_VERSION` constant (verified no
  consumer reads it).

All 32 tests pass; clean `deno check`.

### Remaining open item

**Choose the enforced budget number.** Run the app for a few days reading the
`prompt tokens≈N` logs (esp. `coaching-daily-read` on Maya-shaped accounts) to
see the real distribution, then set `opts.budget` (or the default) to a value
that trims the tail without touching typical athletes. Candidates: 420 (design),
~600 (if the coaching-agent prompt has headroom). Open question #1 below.

The full rebuild stays on the shelf. The event-driven invalidation piece (R5)
stays last — the `claim_athlete_state_rebuild` RPC already blunts the thundering
herd it was meant to solve.

---

## State of the design doc's risk list (what actually shipped)

The 2026-04-20 design doc enumerated 12 risks. Status as of 2026-06-18:

### P0 — correctness (all FIXED, and well)
- **R3 tenant leak** — FIXED. `user_goals` query now
  `.eq("user_id", userId).not("user_id","is",null)` (athlete-state.ts:523–530),
  plus redundant client-side filters at the goal-mapping site (2011–2015).
  Pinned by `HOTFIX-H.1` tests.
- **R4 rebuild race** — FIXED via `claim_athlete_state_rebuild` RPC +
  `rebuild_started_at` stamp + poll (434–454). Note the residual limitation
  below.
- **R6 null TODO fields** — FIXED. `monotony_7d`/`strain_7d` sourced from
  `workout_features` (1515–1516), `week_compliance_pct` computed (1030–1051),
  `fitness_trend` from two snapshots (837–848).

### P2 — accuracy/safety (mostly FIXED)
- **R7 hardcoded pace multipliers** — FIXED. Zones now flow through
  `pace-engine.ts` (`computePaceZones`, 860–936). Hardcoded ladder deleted.
- **R8 race-history regex** — FIXED. Replaced by `confirmed_races` from
  `training_logs.race_result` with defensive validation (2093–2113).
- **R10 magic condition adjustments** — mostly addressed; heat adjustment reads
  lap-stored `heat_adjustment_pct` (1717, 1732), race adjusted-time feature
  removed with race-history.
- **R9 trajectory approximation** — PARTIAL. `priorBlockAvg = (28d − 7d)/3`
  (1399) is a better napkin than the old `/4`, but still not the explicit
  "days 21–28" window the design specced. `trajectory_framing` rides on it.

### P1 — structural (NOT done; file grew instead)
- **R1 monolith split** — NOT done. Still one ~1,700-LOC `rebuildAthleteState`.
  File grew 1,481 → 2,556 LOC; every new satellite went into the monolith.
- **R2 duplicate dedup** — NOT done. Same algorithm at 664–684 and 1247–1263.
- **R5 event-driven invalidation** — NOT done. Still 60-min wall clock
  (`getOrBuildAthleteState` default `maxAgeMinutes=60`). Lower urgency now.

### R11 — NOT done, and now the highest-impact gap (see Fix 1)

---

## The findings, ranked

### 1. The prompt has no token budget and has blown the envelope (R11)

`stateToPromptContext` (2153–2522) unconditionally renders ~15 sections: goals,
load story, volume×intensity, predicted ranges, fitness signal, pace zones,
memories, execution, conditions, injuries, niggle recurrence, patterns, data
gaps, trajectory, races, blocks, and up to 9 recent workouts each carrying a
300-char note.

The design's stated cap was **420 tokens**. A data-rich athlete (Maya: 2 years
of history, goals, niggles, lap data) now produces an estimated **1,500–2,500
tokens**. Consequences: per-call cost, quality dilution (the model weights 15
competing sections), and silent drift — every satellite added since pushed it
further with nothing measuring the envelope.

**This is the cheapest high-value fix and needs no refactor.** Draft below.

### 2. Cold-rebuild latency target is almost certainly blown

Design targeted ~50ms p50 cached / 200–400ms cold. The initial 14-query
`Promise.all` (469–614) is good. Everything after is **sequential awaits**:
`scheduled_workouts` ×2 (1015, 1034), `body_mentions` upsert+read (1180, 1205),
recent `running_workout_laps` (1657), then a **second** laps pass for the 84-day
fitness signal fetched in a serial chunked loop (1779–1794), then final
`upsert` + follow-up `update` (2135–2141).

Two concrete problems:
- **Laps are fetched twice.** The recent-window fetch (1657) and the 84-day
  fitness fetch (1782) overlap; the second re-pulls rows the first already has.
- **The chunked loop is the one real fan-out** for a high-volume athlete.

→ Fix 2: one laps fetch feeding both consumers; instrument p95 on a Maya-shaped
account.

### 3. Concurrency: residual clobber risk remains (document it)

The advisory lock is held only for the **claim check**, not the rebuild body.
On a denied claim the caller polls ~3s then "fall[s] through and rebuild[s]
ourselves rather than return bad state" (453). Under a stalled in-flight build
that produces exactly the concurrent full rebuilds the lock was meant to
prevent — rarer than before, but the final `upsert` is last-write-wins, so two
rebuilds can interleave. Acceptable pragmatic choice; should be a **documented
known-limitation**, not assumed-solved.

### 4. Smaller things
- **Duplicate dedup (R2):** copy-pasted at 664–684 and 1247–1263 → one
  `shared/dedup.ts`. (Fix 3.)
- **R9 half-fixed:** explicit days-21–28 window still owed; trajectory rides on
  the approximation.
- **Silent query failures:** most post-`Promise.all` reads never check `.error`.
  A partial DB failure yields an empty slice, which can flip derived
  `current_phase`/`trajectory_framing` with no signal. The design's "preserve
  previous slice on failure" isn't implemented.
- **Dead `version: 1`:** hardcoded (2129) while the shape changed enormously —
  wire to real schema versioning or drop.
- **Testability ceiling:** nothing is extracted, so the test file drives a
  hand-rolled fake PostgREST client through the whole function. Per-slice
  edge-case coverage (design §8) is impractical until builders exist. Fix 3 is
  the first down-payment.

---

## The plan (bounded, not a rebuild)

### Fix 1 — token budget in `stateToPromptContext` (0.5–1 day)

Refactor the render to assemble **labeled, priority-ranked sections** and drop
the lowest-priority ones when over budget. Heuristic token count (chars/4 — no
tokenizer dependency in the Deno edge runtime). Priority order mirrors the
design's §4 R11 envelope.

> **Eval gate:** this changes the prompt-context path. Per CLAUDE.md hard rule
> #3 + the CI gate (`.github/scripts/check_eval_coverage.py`), run the eval
> harness / supplement with manual review against `docs/coaching/principles.md`
> before merge. The fields themselves don't change — only which low-priority
> sections survive when an athlete is data-rich — so the blast radius is the
> tail of very rich states.

Ready-to-apply draft (new helper + a thin wrapper; the existing section bodies
move into `push`-to-a-section closures essentially unchanged):

```ts
// ── Token budget ─────────────────────────────────────────
// Heuristic only: ~4 chars/token. Good enough to keep the prompt inside an
// envelope; we are pruning whole sections, not shaving words, so precision
// past ±10% doesn't change the outcome.
const APPROX_CHARS_PER_TOKEN = 4;
const PROMPT_TOKEN_BUDGET = 420;

function approxTokens(s: string): number {
  return Math.ceil(s.length / APPROX_CHARS_PER_TOKEN);
}

/**
 * A render section: a priority (lower = kept first) and its already-rendered
 * lines. Sections are assembled in declaration order for readability, but
 * dropped in REVERSE priority order when over budget.
 */
interface PromptSection {
  key: string;
  priority: number;   // 1 = never drop (identity/safety); higher = drop first
  lines: string[];
}

/**
 * Assemble sections under a token budget. Always keeps priority-1 sections
 * (identity, pace zones, active injuries — the safety- and correctness-
 * critical context). Drops higher-priority-number sections from the bottom
 * until under budget. Returns the prompt plus a truncation report for logging.
 */
function assembleUnderBudget(
  header: string,
  sections: PromptSection[],
  budget = PROMPT_TOKEN_BUDGET,
): { text: string; dropped: string[]; tokens: number } {
  const ordered = [...sections];
  const dropped: string[] = [];
  const render = (keep: PromptSection[]) =>
    [header, ...keep.flatMap((s) => s.lines)].join("\n");

  let kept = ordered;
  while (approxTokens(render(kept)) > budget) {
    // Find the droppable section with the highest priority number.
    let victimIdx = -1;
    let victimPriority = -Infinity;
    for (let i = 0; i < kept.length; i++) {
      if (kept[i].priority <= 1) continue; // never drop priority-1
      if (kept[i].priority > victimPriority) {
        victimPriority = kept[i].priority;
        victimIdx = i;
      }
    }
    if (victimIdx === -1) break; // only priority-1 left; stop (over budget but safe)
    dropped.push(kept[victimIdx].key);
    kept = kept.filter((_, i) => i !== victimIdx);
  }

  return { text: render(kept), dropped, tokens: approxTokens(render(kept)) };
}
```

Then `stateToPromptContext` becomes a thin orchestrator. Suggested priorities
(1 = never drop):

| Section | Priority |
|---|---|
| Identity (level, phase) | 1 |
| Pace zones | 1 |
| Active injuries + possible-injury mentions | 1 |
| Goals | 2 |
| Load story (trend + hard/easy + recovery) | 2 |
| Predicted ranges + confidence | 2 |
| Today / next-2 schedule | 2 |
| Recent workouts (cap 3, truncate notes to ~120 chars) | 3 |
| Mood / vibe | 3 |
| Fitness signal | 4 |
| Trajectory framing + coaching-tone guidance | 4 |
| Niggle recurrence | 4 |
| Patterns | 5 |
| Data gaps (cant_see) | 5 |
| Conditions (heat) | 5 |
| Confirmed races (cap 3) | 6 |
| Blocks (cap 3) | 6 |
| Memories (cap 5) | 6 |

Wrap-up: log `dropped` to Sentry when non-empty (design §6 monitoring — "prompt
budget truncation rate > 5% of calls" alert). Add a property test:
`stateToPromptContext(anyState)` is always ≤ ~440 tokens (budget + priority-1
floor).

Mechanical effort is low because the section *bodies* don't change — they move
from `lines.push(...)` directly in the function into per-section arrays.

### Fix 2 — one laps fetch + measure (≈1 day)

- Hoist a single `running_workout_laps` query over the **84-day** window (the
  superset), keyed into `lapsByWorkout`. The recent-window consumers
  (`environment`, `execution`) filter that map by date; the fitness-signal
  consumer uses it directly. Deletes the chunked serial loop (1779–1794) and the
  duplicate select (1657).
- Add timing around the rebuild (e.g. `performance.now()` deltas logged) and
  capture p50/p95 on a 2-year fixture account. Confirm against the 200–400ms
  cold target; if the merged single fetch is large, keep the chunking but run
  chunks with `Promise.all` instead of sequentially.

### Fix 3 — extract pure helpers + unit tests (1–2 days)

Lowest-risk slice of the eventual refactor; starts paying down R1/R2 and unlocks
real unit tests:
- `shared/dedup.ts` — the cross-source dedup (one implementation, used at both
  664–684 and 1247–1263).
- `shared/sessions.ts` — `groupIntoSessions` (692–718).
- `shared/format.ts` — `formatPace` / `formatTime` / `formatTimeDelta`
  (2524–2555).

Each gets a focused unit test (the `formatPace` 7:60→8:00 boundary already has
one — fold it into the new module's tests). No behavior change; `index`-level
exports stay identical, zero consumer churn across the 21 importers.

---

## §3 refactor — STARTED 2026-06-18 (incremental builder extraction)

Greenlit to begin the structural split. Approach: extract pure builders from
`rebuildAthleteState` one at a time, each with unit tests, `index`/exports
unchanged, behavior identical (verified against the existing regression suite).
This is the incremental path — NOT a big-bang rewrite.

Extracted so far into `_shared/builders/` (5 builders, 36 tests):
- **`buildMoodTrend.ts`** — mood trend over check-ins + voice-log moods (7 tests).
- **`buildLoadMetrics.ts`** — dedup + 7d/28d volume + ACWR + hard/easy
  classification + longest-run + session count (8 tests). Dropped dead
  `sessions28d`. Note: the `easySessions7d`-counts-by-raw-`workout_type` quirk
  (independent of hard classification) is preserved and now pinned by a test.
- **`buildTrajectory.ts`** — `buildTrajectory` (framing+reason), `derivePhase`,
  `deriveExperience` (10 tests).
- **`buildLoadDistribution.ts`** — volume×intensity zones, WS3 load trend vs the
  8-week chronic baseline, recovery read, monotony/strain passthrough (6 tests).
  Returns `latestMonotony`/`latestStrain` too (state reads them directly).
- **`buildBlocks.ts`** — 6×4-week rollups, owns its dedup; quality/easy/race
  classification, avg easy pace, per-block niggle counts, dominant mood (7 tests).

`_shared/shared/` (from Fix 3) holds `dedup`, `sessions`, `format`. The
`dedupBySourcePriority` import is now gone from the main file — both call sites
live in builders. Removed inline locals (`priorBlockAvg`, `isHardSession`,
`computeLoadForLog`, `moodScores`, `sumZones`, `weekLoad`, `blockHistoryDeduped`,
etc.) are all gone.

**Full suite: 70 tests pass** (36 builder + 17 shared + 10 athlete-state +
5 budget + 2 inline format), clean `deno check`. Main file down from ~2,506 →
2,328 LOC. Each extraction verified against the unchanged `athlete-state.test.ts`
regression suite.

**Next builders (same pattern, when work resumes):** `buildRecentWorkouts`
(parsed-structure/work-pace selection), `buildFitnessPrediction` (range+confidence
bands), `buildPossibleInjuries` (keyword scan — note: has a `body_mentions` DB
write, so isolate the pure scan from the persistence), plus the smaller niggle-
recurrence, environment/execution-from-laps, data_gaps, and patterns slices. The
eventual `queries/` + `orchestrator.ts` split (per design §3) is the larger move
once the builders are all out.

## What we are explicitly NOT doing now

- The §3 folder split into 10 builders + `queries/` + `orchestrator.ts`
  (the "rebuild"). Deferred.
- `athlete_state_dirty` table + Postgres triggers + invalidation edge fn (R5).
  Deferred — the claim RPC covers the urgent failure mode.
- Replacing `athlete_state` with a projection view (design §7 non-goal).

If/when we do pick up the rebuild, Fix 3 is the natural seam to grow from:
keep extracting one builder per PR, `index.ts` exports byte-identical.

---

## Eval-gate status (checked 2026-06-18)

- The CI gate (`.github/scripts/check_eval_coverage.py`) fires **only** when a
  file under `supabase/functions/_shared/prompts/` changes. All Fix 1–3 + the
  reliability pass touch `_shared/athlete-state.ts` and `_shared/shared/*` — **not
  a prompt file** — so CI will not block them.
- Spirit of hard rule #3 still applies to a **budget-cap flip** (it can change
  `stateToPromptContext` output for rich athletes). Coverage exists to validate
  it: cassettes `daily-read.v5`, `coaching-agent-{simple,moderate,complex}.v1`,
  `generate-workout-insight.v5`, `injury-analysis.v1`, `process-training-memo.v1`.
  Running them needs `GEMINI_API_KEY` (not available in this session) — so the
  harness run is a human/CI step before the cap goes finite.

## R9 (trajectory prior-window) — assessment: leave as-is

The design's R9 wanted `priorBlockAvg` replaced with "average weekly miles
between days 21 and 28 before now" — a single week. The current code uses
`(rolling28d − rolling7d) / 3`, i.e. the 3-week average over days 7–28. That is
already a reasonable, *more stable* baseline than a single oldest week (which is
noisier and would make `trajectory_framing` flip-flop). Recommendation: **do not
implement R9 as literally specified**; the current approach is defensible. If we
want to refine, the better move is a volume-trend slope over the block history,
not a single-week window — but that's a larger change and prompt-affecting, so it
should ride with the next eval-harness run, not now.

## Open questions for Rio

1. **Token budget number.** Design said 420. Should it match whatever
   `coach_context` reserves in the overall coaching-agent prompt? If the agent
   has headroom, 600 may be the honest target rather than forcing aggressive
   pruning. (Design §9 Q2.)
2. **Eval coverage.** Fix 1 touches the prompt path. Is there cassette coverage
   for `coaching-daily-read` / `process-training-memo` we can run, or does this
   go through manual review against `principles.md`?
3. **Sequencing.** All three are independent. Recommend Fix 1 first (highest
   value), but if a latency complaint is live, Fix 2 leads.
```

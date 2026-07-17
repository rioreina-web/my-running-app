# `athlete-state.ts` — Tech Debt Assessment

**Date:** 2026-06-20
**Scope:** `supabase/functions/_shared/athlete-state.ts` (2,328 LOC) and its
five extracted builders in `supabase/functions/_shared/builders/`.
**Method:** engineering tech-debt framework — score each item on Impact,
Risk, and Effort, then `Priority = (Impact + Risk) × (6 − Effort)`.

## Why this file matters

It is the Dynamic Context Object — every AI surface reads athlete state from
here instead of querying 6–8 tables itself. **29 files import it.** A bug here
is a bug in every coach prompt, Daily Read, and coachable-moment evaluation at
once. That blast radius is what makes the debt worth paying down, and what
makes "rewrite it all at once" too risky.

## Good news first — half the original debt is already paid

CLAUDE.md describes this file as ~2,555 LOC with the P1 builder split still
pending. The state on disk is ahead of that note:

- The file is **2,328 LOC**, not 2,555.
- **Five builders are already extracted *with their own tests*** —
  `buildMoodTrend`, `buildLoadMetrics`, `buildTrajectory`,
  `buildLoadDistribution`, `buildBlocks` (committed 2026-06-18).
- The four P0 correctness bugs (tenant leak, rebuild race, null fields, pace
  zones) are fixed and covered by `athlete-state.test.ts`.
- No `TODO`/`FIXME`/`HACK` markers anywhere in the file.

So this is not a rescue job. It's a half-finished, well-executed refactor with
a clear next step. **Update CLAUDE.md's LOC figure too — it's stale.**

## Where the debt actually concentrates

One function: **`rebuildAthleteState` runs lines 444–1819 — roughly 1,375
lines in a single function.** It claims a concurrency lock, fetches 13 tables,
runs niggle detection, fitness signal, pace-zone projection, injury-history
grouping, lap segmentation, confidence flags, and the final upsert — all
inline. Everything else below flows from this one structural fact.

## Debt register (highest priority first)

| # | Item | Type | Impact | Risk | Effort | **Priority** |
|---|------|------|:--:|:--:|:--:|:--:|
| 1 | No direct test for the `rebuildAthleteState` orchestration | Test | 3 | 4 | 3 | **21** |
| 2 | Silent partial-failure degradation (warn-only, invisible to consumers) | Infra/observability | 3 | 4 | 3 | **21** |
| 3 | `any`-typed `scheduled_workouts` rows in compliance math | Code | 2 | 2 | 1 | **20** |
| 4 | `ATHLETE_STATE_SCHEMA_VERSION` is dead — no invalidation story | Architecture | 2 | 3 | 2 | **20** |
| 5 | Stale design-doc references in CLAUDE.md (`refactor-design.md`, line offsets) | Documentation | 2 | 2 | 1 | **20** |
| 6 | The 1,375-line `rebuildAthleteState` god function | Architecture/Code | 5 | 4 | 4 | **18** |
| 7 | Claim/poll lock instead of advisory lock (HOTFIX-H.2 workaround) | Architecture | 1 | 2 | 3 | **9** |
| 8 | No event-driven invalidation (full rebuild every trigger) | Architecture | 4 | 3 | 5 | **7** |

### 1. No direct test for the orchestrator — Priority 21
`athlete-state.test.ts` (539 LOC) covers `formatPace`, the builders, and
specific computed-field slices via a hand-rolled mock Supabase chain. The
1,375-line orchestration path itself — how the 13 reads compose into the final
state — is not directly exercised. **Business justification:** this is the
exact code that feeds every AI prompt; an uncaught regression here ships wrong
coaching to every athlete silently. It scores highest because it's the cheapest
way to buy confidence, and it's a prerequisite for safely doing item 6.

### 2. Silent partial-failure degradation — Priority 21
Eleven reads degrade to `console.warn` and keep going (good — partial data
beats a hard failure). But nothing tells a *consumer* the state is degraded. A
prompt can't distinguish "fitness unknown because the athlete is new" from
"fitness unknown because the `fitness_snapshots` read errored." **Business
justification:** the product's whole promise is honest observation; serving
confident output over a silently-degraded read violates the "range +
confidence, never a point" principle. **Fix:** add a `degraded_sources: string[]`
field to `AthleteState` and have the AI layer soften/flag when it's non-empty.

### 3. `any`-typed scheduled-workout rows — Priority 20 (quick win)
Lines 912–937 use `(w: any)` for plan-compliance filtering. A `ScheduledWorkoutRow`
type already exists in `weeklyAnalytics.ts`. **Fix:** import and apply it —
under an hour, restores type-checking on compliance math.

### 4. Dead schema version — Priority 20 (quick win)
`ATHLETE_STATE_SCHEMA_VERSION = 1` is stamped on every rebuild but no consumer
reads it (the code comment confirms this, verified 2026-06-18). The day the
state shape changes, every cached row is silently stale with no invalidation.
**Fix:** either wire `getAthleteState` to treat a version mismatch as a
cache-miss (forces rebuild), or delete the constant and stop pretending there's
a versioning story. Pick one; don't leave it half-built.

### 5. Stale design-doc references — Priority 20 (quick win)
CLAUDE.md points to `outputs/athlete-state-refactor-design.md`, which is not in
the repo, and warns its line offsets are stale. AI coding assistants (and new
engineers) follow these pointers first. **Fix:** restore the doc or update the
CLAUDE.md pointer to this assessment; correct the LOC figure.

### 6. The god function — Priority 18 (the main event)
Lower *priority score* than the quick wins only because its effort is high —
not because it matters less. It's the root cause of items 1 and 2 being hard.
**Continue the established builders pattern**, don't invent a new one. Natural
seams already marked by the section comments inside the function:

- `buildPaceProjection` — engine output → legacy flat shape (~line 756 on)
- `buildNiggles` — body-mention detection + 12-month recurrence (~967–1100)
- `buildInjuryHistory` — grouping/recurrence from the injuries table (~1159 on)
- `buildFitnessPrediction` — range + confidence projection (~1244 on)
- `buildExecutionSignal` — lap segmentation + heat/execution read (~1419 on)
- `buildConfidenceFlags` — the thin/absent-data nudges (~1475–1525)

(Line numbers are anchors, not exact boundaries — confirm the seam by the
section comment when you cut each one.)

Each extraction is independently testable (proven by the existing five), small,
and reviewable. Target: get `rebuildAthleteState` under ~300 lines of pure
orchestration. **Do these one per PR**, each behind the existing test suite.

### 7. Claim/poll lock — Priority 9 (leave it)
HOTFIX-H.2 uses a claim RPC + poll rather than the `pg_advisory_xact_lock` the
original design proposed. It works, it's documented, and it's correct. Not
worth touching unless the rebuild path is being reworked anyway.

### 8. Event-driven invalidation — Priority 7 (defer to Phase 6)
Today the whole state rebuilds on every trigger. Incremental/event-driven
invalidation is the real long-term win but it's a large, design-heavy effort.
CLAUDE.md already parks this in Phase 6 (memory architecture). Keep it there.

## Phased remediation plan (alongside feature work)

**Phase A — quick wins (½ day total, no behavior change).**
Items 3, 4, 5. Type the scheduled rows, resolve the schema-version question,
fix the doc pointers and LOC figure. Low risk, immediate hygiene, unblocks
clean diffs for what follows.

**Phase B — visibility (1–2 days).**
Item 2: add `degraded_sources` to the state and surface it in the AI layer.
Ship this *before* the big extraction so any regression during Phase C is
observable rather than silent.

**Phase C — continue the extraction (1 builder per PR, ongoing).**
Item 6: pull out `buildNiggles`, `buildInjuryHistory`, `buildExecutionSignal`,
`buildPaceProjection`, `buildConfidenceFlags` — each with its own test, each
behind the eval-harness gate for any prompt-adjacent change. Item 1's
orchestrator test gets easier with every extraction, so write it incrementally
as the seams come out rather than as one upfront task.

**Phase D — deferred.**
Items 7 and 8 stay parked. Revisit 8 when Phase 6 memory-architecture work
starts; touch 7 only if the rebuild path is already open.

## One-line summary

The expensive, risky refactor (the builder split) is already half-done and
well-tested — finish it one builder per PR. But do three cheap hygiene fixes
and add degraded-state visibility *first*, because they're nearly free and they
make the remaining extraction safe to do alongside feature work.

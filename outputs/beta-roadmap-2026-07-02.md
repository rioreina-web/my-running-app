# Beta roadmap — from "knows your runs" to "knows you," and out the door

**Date:** 2026-07-02
**Companion docs:** `athlete-state-knowledge-audit-2026-07-02.md` (the why), `life-context-implementation-plan-2026-07-02.md` (milestone 1, fully specced).

Two tracks run in parallel: **Smarter** (the athlete-state audit fixes, sequenced by knowledge-per-effort) and **Shippable** (items already tracked in CLAUDE.md's known issues / production blockers that gate a public beta regardless of intelligence). Milestones are ordered; within a milestone, items are independent.

---

## Milestone 1 — Life context (specced, ready to execute)

The full plan lives in `life-context-implementation-plan-2026-07-02.md`. Pipe the voice-memo `extracted_data` (sleep, stress, fatigue, illness, travel, motivation, felt_vs_looked, RPE) into a `life_context` slice of athlete_state, surface it in the prompt, add two pattern rules, review against coaching principles. Includes the step-0 prod checks (fitness_snapshots writer alive? extracted_data actually populated?). **Effort: 2–4 sessions.**

**Beta effect:** the Coach Read stops being blind to everything the athlete says about their life. Single biggest jump in perceived intelligence.

## Milestone 2 — Trustworthy patterns

1. **Niggle detection rewrite** (audit #2). Move body-mention classification into `process-training-memo` per `outputs/body-mentions-design.md`: closed ~30-part vocabulary, laterality (left/right), verbatim quotes; demote the athlete-state regex scan to a backfill for typed notes. Kills the left-knee/right-knee conflation that can produce confidently wrong "patterns." **Effort: 1–2 sessions.**
2. **Fitness-snapshot writer** (audit #3). Scope depends on milestone-1 step 0a. If snapshots aren't flowing: build/schedule the writer (likely a cron invoking the ml-service or `build-athlete-profile`), and add a data_gap when the latest snapshot is stale. Until this lands, fitness_trend / 6-mo comparison / prediction ranges are decorative. **Effort: unknown until 0a; budget 1–3 sessions.**
3. **Load-math cleanups** (audit #7). Exclude non-running types from rolling miles/ACWR in `buildLoadMetrics` (honoring the 2026-05-28 cross-training decision); unify hard/easy classification with the blocks builder; pick and enforce a finite prompt token budget from the logged distributions. **Effort: 1 session.**

**Beta effect:** what the coach *notices* is actually true.

## Milestone 3 — Shippable checklist (parallelizable with 1–2)

All previously tracked in CLAUDE.md; consolidated here as the launch gate:

- **Push the pending `athlete_settings` migrations** (`20260615210000/220000/230000` authored, validated, awaiting `supabase db push`) and add an iOS/web timezone writer — until then every athlete is UTC and the Daily Read fires at the wrong hour.
- **Repoint the remaining settings readers** (`fetch-workout-weather`, `post-run-reconciliation`, `reconcile-log`) off the ghost `user_profiles`.
- **Eval harness coverage** — fill the 10 stub cassettes' athlete-side inputs (milestone 1 step 6 produces several), wire the reschedule-plan production library. CI already gates `_shared/prompts/` changes; coverage makes the gate meaningful.
- **CI activation** — GitHub secrets + branch protection for the existing workflows (CI, Deploy, drift detector, smoke tests).
- **Supabase prod config out of dev mode.**
- **Landing page aligned to the Maya wedge; legal docs de-TODO'd.**
- **4-tab IA (Phase 3 of the Maya roadmap)** — collapse Plan into Train, ship `Log · Trends · Train · Coach`. Design-side but user-visible; a beta shipping the deprecated 5-tab nav ships a contradiction.

**Beta effect:** you can put real users on it without embarrassment or risk.

## Milestone 4 — Depth (post-beta, once real users generate data)

1. **Memories from memos** (audit #4). LLM-based memory extraction from memo transcripts feeding `user_memories` (replace/augment the regex `extractMemories`); expiry + importance curation. The "coach who remembers your life" feature. **Effort: 2–3 sessions.**
2. **HealthKit 2-year backfill + race auto-detect** (audit #5, existing roadmap Phase 2). Onboarding backfill, race detection from history with confirm prompts, `confirmed_races` becomes genuinely 2 years deep, race-anchored zones get real anchors. **Effort: the big one — plan separately.**
3. **Recovery data** (audit hole 6 / product pillar 3, v1.5). HealthKit sleep + resting HR/HRV ingestion, a recovery slice in athlete_state, and honest data_gaps in the meantime. Prereq for the pillar-3 surface.

**Beta effect → v1.5:** depth that compounds — history, memory, and recovery are what make month 3 feel smarter than week 1.

---

## Suggested calendar shape

Weeks 1–2: Milestone 1. Weeks 2–4: Milestone 2 + start Milestone 3 checklist in parallel. Beta gate: Milestones 1–3 done. Milestone 4 begins once beta users are generating the data it feeds on.

**Standing rule for all of it:** every prompt-affecting change gets the milestone-1 step-6 treatment (principles review + cassette) until eval coverage is complete — hard rule #3.

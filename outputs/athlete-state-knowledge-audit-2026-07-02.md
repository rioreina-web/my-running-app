# Athlete-State Knowledge Audit — does it actually know the athlete?

**Date:** 2026-07-02
**Scope:** `supabase/functions/_shared/athlete-state.ts` (~2,330 LOC) and everything that feeds it — the voice-memo pipeline, HealthKit ingestion, and the history tables. The question: when the Coach Read says it knows Maya, is that backed by data, or is the state object mostly reading the last four weeks and improvising the rest?

**Verdict up front:** the state is strong on *recent run mechanics* (load, execution, splits, heat, pace zones) and weak-to-broken on the two things the product's own vision doc calls the differentiator: **qualitative voice signal** and **longitudinal history**. The voice pipeline extracts a genuinely rich picture of the athlete's life; athlete-state then throws almost all of it away. And several fields the state advertises (fitness trend, memories, 2-year history) have no working writer behind them.

---

## What it does well (credit where due)

- **Run mechanics are coach-grade.** `execution` (rep splits, fade %, HR drift), `environment` (heat-adjusted pace), `fitness_signal` (pace-at-HR efficiency over 12 weeks), `load_distribution` (volume × intensity with an 8-week chronic baseline) — this is real, honest, well-sourced quant. The single unified laps fetch (athlete-state.ts:1292–1345) is clean engineering.
- **The honesty layer exists.** `data_gaps` (athlete-state.ts:1566–1597), range-only predictions with synthesized bands when the snapshot's bands are null (WS4, :1248–1278), and the pattern layer that pre-computes observations so the LLM narrates instead of inventing — all consistent with hard rules #2 and #7.
- **Tenant safety and dedup are handled** (user_goals double-filter :546–553 and :1659–1663; cross-source dedup in buildLoadMetrics.ts:63).

Now the holes, ordered by how much they undermine "knowing the athlete."

---

## Hole 1 — The voice memo pipeline extracts a rich athlete; athlete-state reads a caricature

`process-training-memo.v1.ts:71–99` extracts, per memo: `felt_vs_looked` (explicitly annotated as "the single most coach-relevant field"), `work_stress`, `life_stress`, `travel`, `fatigue`, `soreness[]`, `illness`, `motivation`, `sleep_quality`, `sleep_hours`, `rpe`, `weather`, `fueling`, `running_partners`. This is exactly the qualitative signal the data-aware-journey doc promises to fuse.

What athlete-state actually reads from all of that:

- `mood` — one label per log.
- `extracted_data.readiness_score` — **and only from `source = 'check_in'` rows** (athlete-state.ts:554–562, :1140). Memo-sourced `extracted_data` is never queried; the recent-logs select (:511) doesn't even include the column.
- `cleaned_notes` — truncated to 300 chars, passed as raw text (:864–870).

So `felt_vs_looked`, `life_stress`, `travel`, `illness`, `motivation`, `fatigue`, `sleep_*`, `rpe` are extracted by an LLM call the product pays for on every memo, stored in `extracted_data`, and then **never enter the athlete model**. The Coach Read's mandate is "feeling first, reads life context (weather, sleep, work stress)" — the state object literally cannot supply sleep or work stress. The only trace is whatever survives in a 300-char notes excerpt, which the LLM must re-parse from prose, re-doing work the pipeline already did with structure.

Concrete miss: Maya says "slept terribly, work is brutal this week, legs felt dead but pace was fine." The pipeline stores `sleep_quality: poor`, `work_stress: high`, `fatigue: wiped`, `felt_vs_looked: harder than it looks`. Athlete-state surfaces: `mood: tired` and maybe a truncated note. Three memos like that in a row is a screaming pattern (mood-vs-life-load); the patterns layer (:1460–1564) can't see it because none of those fields reach it.

**Fix shape:** add memo-sourced `extracted_data` to the recent-logs select; build a `life_context` slice (7d/28d rollups of stress, sleep, fatigue, illness, travel, felt_vs_looked) and a corresponding pattern rule or two. This is mostly plumbing — the expensive extraction already works.

## Hole 2 — Niggle detection is a regex re-derivation that ignores the LLM's own output

- The **only writer** to `body_mentions` is athlete-state's inline regex scan (:947–1072 upsert; confirmed by repo-wide grep — no other writer exists). The designed LLM classifier from `outputs/body-mentions-design.md` (closed ~30-part vocabulary, verbatim severity language) was never wired.
- Meanwhile the memo pipeline **already extracts** `soreness: ["left knee", "calves"]` in the athlete's own words — and athlete-state ignores that field too, re-detecting body parts by regexing note text.
- The regex vocabulary (:947–951) is ~20 entries vs. the designed ~30. Missing: groin, adductor, soleus, toe/toes, top-of-foot, sacrum/SI, neck/shoulder. **Laterality is discarded** — "left knee" and "right knee" both store as `knee`, so `niggle_recurrence` can conflate two different problems into one "pattern," which is exactly the kind of false observation hard rule #2 exists to prevent.
- Detection only runs over **the last 30 days of the 28-day logs window** (:958–962) at rebuild time. A niggle mentioned 6 weeks ago that was never scanned (e.g. the state wasn't rebuilt in that window, or the mention was in a memo transcript that didn't make it into notes columns) never reaches `body_mentions`. Persistence also silently no-ops under the anon/RLS path (:1064–1072) — acknowledged in a comment, but it means niggle history quality depends on *which code path* triggered the rebuild.

**Fix shape:** make the memo pipeline the writer (it sees the full transcript at extraction time, with the closed vocabulary + laterality per the design doc), and demote the regex scan to a backfill for typed manual notes.

## Hole 3 — "Memories" is a first-class prompt section fed by a dead-end pipeline

`memories` renders as "What I remember about you" (:2087–2094). The only writer is `extractMemories()` in `_shared/memory.ts:41+`, called **exclusively from coaching-agent chat** (coaching-agent/index.ts:1598). Two problems:

1. **Maya doesn't chat to earn memories.** Her primary input is voice memos — which never pass through memory extraction. A journaling athlete with 200 memos has an empty memory table; the Read's "sounds like it knows you" section is empty precisely for the persona the product is built around.
2. **Extraction is brittle regex**, not LLM: PR patterns, an injury keyword list, a mileage regex (memory.ts:50–120). "I ran 3:28 at CIM two falls ago" likely misses; anything about family, job, schedule constraints, or preferences ("I hate track workouts") is only captured if a hand-written pattern anticipated it — the CONTEXT category exists but has nearly nothing feeding it.

## Hole 4 — History: the product promises 2 years; the state sees 24 weeks, and the backfill doesn't exist

- iOS sync pulls **~30 recent workouts on launch** — the roadmap's "2-year HealthKit back-fill on signup" is not implemented (per iOS sync audit). The 2-year `confirmed_races` window (:620–628) is therefore querying data that mostly can't exist for a new user.
- **Race auto-detection isn't implemented anywhere** — `race_result` is populated only by manual declaration. "Maya lands in a product that already knows her" currently means she lands in a product that asks her to type in her race history.
- Even with backfill, athlete-state's deepest training-detail window is **168 days** (blocks, :583–590). `recent_blocks` covers 6 × 4 weeks; nothing summarizes year-over-year ("you were at 45 mpw this time last year"). The "biographical" layer is one 10K-prediction delta vs. a ~6-month-old snapshot (:1144–1157) — see hole 5.

## Hole 5 — The fitness backbone depends on `fitness_snapshots` nobody demonstrably writes

`fitness_trend`, `fitness_vs_6mo_ago_*`, `fitness_prediction`, the goal-gap math, and one tier of the pace-zone cascade all read `fitness_snapshots`. The consumer audit found **no edge function in the repo that writes snapshots** (presumably the Railway ml-service does, but nothing in-repo schedules or verifies it). If snapshots are stale or absent:

- `fitness_trend` silently reports "maintaining" on a single snapshot (:732) — indistinguishable from a real plateau.
- The 6-month comparison needs a snapshot to have existed in a 150–210-day-ago window (:564–571) — a cadence nobody enforces.
- `fitness_prediction` goes null and the state falls back to legacy point estimates (:2003–2010) — the exact false-precision path hard rule #7 bans, still live as a fallback.

This deserves a prod check: `select count(*), max(created_at) from fitness_snapshots group by user_id` before trusting any fitness-trend output.

## Hole 6 — Recovery signal is absent, not just thin

CLAUDE.md claims recovery is "partially served already (voice-log fatigue, HealthKit sleep)." In code: **no sleep, resting-HR, or HRV ingestion exists anywhere** (iOS audit), and voice-log fatigue is extracted but dropped (hole 1). The `data_gaps` honesty layer doesn't declare this either — it flags missing mood, splits, and thin fitness (:1566–1597), but never "I can't see your sleep or recovery." The Read is structurally forced to answer "should I push or pull today?" from mood + load alone, without disclosing that.

## Hole 7 — Assorted correctness cracks (smaller, but real)

- **Cross-training leaks into running load.** buildLoadMetrics filters on `distance > 0` only (buildLoadMetrics.ts:55–57) — any distance-bearing non-run row (hike, bike ride landing in training_logs) counts toward rolling miles and ACWR, contradicting the 2026-05-28 decision that cross-training stays out of running-fitness math. Conversely, easy-session counting is `workout_type ∈ {easy, recovery}` only (:136), so hard/easy splits are wrong for athletes whose auto-synced runs carry other type labels.
- **Hard/easy classification disagrees across builders** — ACWR path calls an 18-mi long run hard; the blocks builder counts long runs as easy. Same week, two load stories.
- **Prompt budget is unenforced.** Soft target 420 tokens; data-rich athletes render 1,500–2,500 and the default budget is `Infinity` (:1824, :2307). Every consumer eats the full block; the priority-drop machinery exists but is dormant.
- **Partial-failure = silent amnesia.** A failed source read yields an empty slice, not the prior value (:639–644, acknowledged). One flaky `training_logs` read and the athlete's trajectory flips to "returning" with no signal it's an artifact.
- **State insufficiency is revealed by its consumers**: coaching-daily-read re-queries `body_mentions` directly (coaching-daily-read/index.ts:584) and both it and coaching-agent supplement the state with their own log/memo/RAG queries. The module whose stated purpose is "every AI function reads this instead of querying 6–8 tables" has its two biggest consumers querying around it.

---

## Scorecard against the question

| Dimension | Grade | One-liner |
|---|---|---|
| Run data (recent, mechanical) | **A−** | Splits, heat, efficiency, load story — genuinely coach-grade. Cross-training leak and classifier disagreements are the blemishes. |
| Voice memo signal | **D** | Extraction is excellent; the state consumes ~2 of ~15 extracted fields. The product's core fusion claim is unimplemented at the state layer. |
| History / biography | **D+** | 24-week working memory, no backfill, no race auto-detect, memories pipeline dead for the wedge persona, 6-mo comparison on an unverified snapshot cadence. |
| Recovery | **F** | No data source exists, and the honesty layer doesn't admit it. |

## Recommended order of attack

1. **Pipe memo `extracted_data` into the state** (life_context slice + patterns). Highest knowledge-per-engineering-hour in the codebase; no new data collection needed.
2. **Move body-mention writing into the memo pipeline** per the original design (closed vocab, laterality, verbatim quotes); keep regex as manual-note backfill.
3. **Verify/own the `fitness_snapshots` writer and cadence** — everything "trend" hangs off it.
4. **Feed `extractMemories` (LLM-ified) from memo transcripts**, not just chat.
5. **HealthKit backfill + race auto-detect** (already Phase 2 roadmap) — until then, soften any "I know your history" voice.
6. Fix the cross-training distance leak and unify hard/easy classification across builders.

*Line references are against the working tree as of 2026-07-02. The `.perf-worktree` and `.claude/worktrees` copies were excluded per CLAUDE.md.*

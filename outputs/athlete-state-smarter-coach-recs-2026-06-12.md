# athlete-state — recommendations to make it as smart as a coach

**Date:** 2026-06-12
**Status:** PROPOSED
**Companion docs:** `outputs/athlete-state-v2-coach-grade-2026-06-12.md` (v2 spec; Phases A/B built), `athlete-state-refactor-design.md` (builder split + invalidation)
**Source module:** `supabase/functions/_shared/athlete-state.ts` (~2,000 LOC after Phase A/B)

Phase A/B of the v2 spec already landed: load distribution (volume × intensity), execution quality, environment, durable memories, and range+confidence predictions are wired into the state. The recommendations below are what comes next, ranked by how much coach intelligence each buys.

---

## 1. Fix the bugs that make it quietly dumb today (~1 day, do first)

These undermine everything downstream and none of them touch schema or prompts.

| Bug | Where | Why it matters |
|---|---|---|
| `fitness_trend` hardcoded to `"maintaining"` | ~line 755 (TODO since v1) | Trajectory framing, "building" detection, and the Read's whole tone depend on it. Fix: compare the last two `fitness_snapshots`. |
| `recent_blocks.injury_mentions` never incremented | declared ~1083, pushed ~1133, no `++` anywhere | Every block reports 0 niggle mentions. The coach can never say "your last two niggle-free blocks were your best." |
| `week_compliance_pct` always `null` | ~line 1532 (TODO) | A coach's first question is "did you do the plan?" Scheduled workouts are already fetched — count completed/scheduled. |
| `priorBlockAvg = weeklyAvg28d − rolling7d/4` | ~line 1195 | Divides the prior 3 weeks by 4, not 3 — understates the baseline ~25%. "Building" fires too easily, "declining" almost never. Trajectory framing is biased optimistic. |
| `peaking` ignores race date | ~line 1211 (TODO) | Fires on any active plan with a goal time, race could be 6 months out. Fix together with rec #3. |
| `isHardSession` classifies off raw `workout_type`; blocks classify off `parsed_structure.type` | ~line 692 vs ~line 1089 | The two load views can disagree about the same week. Pick one classifier (parsed-first, type fallback) and share it. |

---

## 2. Ship the pattern layer (v2 Phase D) — the actual coach's edge

Everything else in the state is *reporting*; this is *noticing*. A coach's value is correlations held across months. Start rule-based — each pattern a pure function over data already joined in the builder, emitting `{ pattern, evidence, confidence }`:

- **Easy-pace creep at stable HR.** Easy runs drifting faster block-over-block at the same HR = aerobic gains; same pace at rising HR = fatigue or creeping intensity. `hr_pace_efficiency` and per-block `avg_easy_pace_sec` already exist.
- **Niggle lag.** Body mention appearing 3–10 days after a 7-day volume spike, per body area. The volume context per mention is already computed — persist it (rec #4) and correlate.
- **Pacing discipline tendency.** Aggregate `execution.fade_pct` across sessions: "you fade in 70% of interval sessions — you go out too hot." The single most coach-like observation the current data supports.
- **Personal heat sensitivity.** Regress actual slowdown against `heat_adjustment_pct` to learn *this athlete's* coefficient instead of the generic model.
- **Down-week response.** What happens to execution quality the week after volume drops 20%+. Tells the coach whether she absorbs rest well — directly informs taper design.

Feed the output to the prompt as pre-computed observations with evidence, not raw data the LLM must connect. This honors the Coach voice rule ("never explains math") and hard rule #2 — the math happens deterministically in the builder, the LLM only narrates.

---

## 3. Make it race-aware in time, not just in data

The state knows the goal exists but not *where in the buildup the athlete is*.

- Add `weeks_to_goal_race` plus an expected-phase mapping (12+ wks → base, 6–12 → build, 3–6 → peak, <3 → taper).
- Add a `phase_alignment` flag when the derived phase disagrees with the expected one ("8 weeks out but volume says base") — that mismatch IS a coachable moment.
- Fix the `peaking` TODO so it requires race ≤ 8 weeks out.
- Add the one series Maya actually cares about: **goal gap over time** — `gap_vs_current_sec_per_mile` snapshotted per block, so the coach can say "the gap to 3:16 has closed 12s/mi over two blocks." Goal is direction; the gap trend is the story.

---

## 4. Durable niggles (v2 Phase C) — required for #2

The regex scan recomputes and forgets every rebuild. A niggle can appear one day and vanish the next; there is no recurrence, no timeline, no niggle-lag pattern without storage.

- Create `body_mentions` with RLS in the same migration (hard rule #1), applied via `db push` from a committed SHA (hard rule #9).
- Backfill from the current scan; switch `possible_injuries` to read stored history + recurrence.
- Keep the closed vocabulary, verbatim quotes, surface-don't-diagnose contract (hard rule #2 / Niggles spec).

---

## 5. Add a `cant_see` block — calibration is coach behavior

A good coach says "I haven't heard how you're feeling lately." Compute explicit gaps at build time:

- No mood signal in N days
- No parsed quality session in the window
- No laps for recent runs (no execution/environment read possible)
- No sleep/recovery data (until the v1.5 recovery surface lands)

Cheap to compute, and it makes the Read honest instead of confidently thin. Pairs with the per-field provenance envelope from v2 §8.

---

## 6. Keep it warm, then refactor

- **Keep-warm:** lazy 60-minute rebuild means the Read can see yesterday's athlete. Build-on-insert (the invalidation design in `athlete-state-refactor-design.md`) + nightly sweep.
- **Refactor:** the ~2,000-LOC builder should split into pure slice builders per the refactor design, but that's gated on eval coverage (hard rule #3). In the meantime, add golden-state snapshot tests per slice against fixture data — enough safety to do recs #1–#3 now without waiting for the harness.

---

## 7. Enforce a real prompt token budget

`stateToPromptContext` claims "~200–400 tokens" but now renders well over 1,000 for a rich athlete. Give it a per-section budget with `data_depth`-aware trimming — otherwise the richest athletes get the most diluted prompts.

---

## Sequencing

1. **Rec #1** (bug fixes) → **#5** (`cant_see`) → **#3** (race-time awareness): days of work, no schema, no eval gate.
2. **Rec #4** (`body_mentions` migration) then **#2** (pattern layer): the big unlock.
3. **Rec #6/#7** (keep-warm, refactor, token budget): last; refactor stays behind the eval harness.

---

## Build status (updated 2026-06-12)

- **Rec #4 (durable niggles / Phase C):** BUILT — `body_mentions` table
  (`20260612130000_body_mentions.sql`) + 12-month recurrence read-back into
  `niggle_recurrence`.
- **Rec #2 (pattern layer / Phase D):** BUILT — `patterns` block in
  `athlete-state.ts`: pacing-fade/control, niggle-vs-volume-spike,
  personal heat sensitivity, easy-day discipline, block-over-block
  easy-pace creep, and down-week response. Surfaced as pre-computed
  observations the LLM only narrates.
- **Rec #1 (quiet bugs):** BUILT — all six fixed in `athlete-state.ts`:
  `fitness_trend` now compares the last two `fitness_snapshots` (and this
  unlocks the "building" trajectory branch, which was dead because it gated
  on `fitnessTrend === "improving"`); `recent_blocks.injury_mentions` now
  counts deduped niggle mentions per block window; `week_compliance_pct`
  matches scheduled non-rest days against days actually trained (null for
  self-coached, correct); `priorBlockAvg` fixed ÷4→÷3 (removes the
  optimism bias); `peaking` now requires the race ≤8 weeks out (added
  `end_date` to the plan query); `isHardSession` now prefers
  `parsed_structure.type`, agreeing with the block quality classifier.
- **Rec #6 keep-warm (Phase E):** BUILT — `rebuild-athlete-state` worker +
  nightly cron.
- **Rec #5 (`cant_see` calibration):** BUILT — `data_gaps` computed at build
  time (no recent mood, no lap/split data, thin fitness estimate, one-point
  niggle) + a `data_gaps jsonb` column. Surfaced in `stateToPromptContext`
  as "What I can't see right now," which the v3 prompt's existing cant_see
  instruction consumes — so no prompt change, no eval re-run.
- **Verified (2026-06-12):** all backend edits this session `deno check`
  clean (athlete-state, coaching-daily-read, rebuild-athlete-state,
  daily-read.v3, prompt-library, compute-workout-features), and the existing
  unit suite passes (38/38) — the 1–5 weight change didn't break pace math.
- **Open next:** Rec #3 (race-time awareness — builds on the `end_date` now
  fetched), Rec #7 (token budget). Plus the memory write-path (6→9) and the
  eval-gated builder refactor. iOS Swift still needs an Xcode build (can't
  compile in this environment).

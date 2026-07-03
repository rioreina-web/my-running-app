# athlete_state v2 — the coach-grade athlete model

**Date:** 2026-06-12
**Status:** PROPOSED — evolution spec, awaiting sign-off
**Goal:** make `athlete_state` a 10/10, data-centric model that "knows
the athlete like a coach" — and is reliable enough to be the Read's
single source of truth.

---

## The core insight

Most of the coach-grade signal **already exists in precomputed tables
that `athlete_state` doesn't read.** This is not a from-scratch ML build.
It's: (1) wire in rich precomputed data, (2) add a longitudinal pattern
layer, (3) give niggles a durable home, (4) attach provenance to every
field, (5) keep the state warm. Verified against the live prod schema
(`RunningAppMVP2`).

What's sitting unused right now:

| Table | Rows | Has (unused by athlete_state) |
|---|---|---|
| `workout_features` | 193 | `monotony_7d`, `strain_7d`, `acwr`, rolling 7/14/28/42d miles, `intensity_score`, `hr_pace_efficiency`, hard/easy avg HR, `pace_variance`, `effort_distribution`, `hours_since_last_hard` |
| `running_workout_laps` | 551 | per-lap `temp_f`, `dew_point_f`, `heat_category`, `heat_adjustment_pct`, **`heat_adjusted_pace_sec_per_mile`**, HR, cadence, watts, `total_elevation_gain`, `pace_zone`, `is_rest` |
| `fitness_snapshots` | 34 | `range_*` (low/high), `confidence_tier`, `workout_count` |
| `athlete_pace_profiles` | 1 | per-distance `*_confidence` + `*_source_date` |
| `user_memories` | 10 | `category`, `content`, `importance`, `expires_at` — the durable "things the coach remembers" |

`athlete_state` currently recomputes (with bugs and TODO-nulls) what
`workout_features` already has, and ignores laps, ranges, confidence, and
memory entirely.

---

## What "knows the athlete like a coach" means

A great coach holds eight things in their head. Here's where each stands
and the data that fills it.

### 1. The numbers (load & physiology) — 6/10 → 10/10
**Decision (2026-06-12): drop ACWR.** A coach doesn't read a single
acute:chronic ratio — they read *how the volume is distributed across
intensity*: how much easy, how much quality, polarized vs. muddy. The app
already visualizes exactly this in **`PaceVolumeSpectrumChart`** ("volume
distributed across pace zones"), and that chart is already fed by
`workout_features` time-in-zone data (`easy_seconds`, `moderate_seconds`,
`threshold_seconds`, `hard_seconds`) via its `fromTimeInZone` helper.

**Now:** acwr + rolling miles computed by hand in the builder;
`monotony_7d`, `strain_7d`, `week_compliance_pct` hardcoded `null`;
`fitness_trend` hardcoded `"maintaining"`.
**v2:** the load model becomes a **volume × intensity distribution** sourced
from `workout_features` — time/miles in each zone over 7d and 28d, plus
`effort_distribution` (the polarized/pyramidal/muddy label) and
`intensity_score`. This is the same data shape the spectrum chart consumes,
so the Read and the chart speak the same language. Rolling miles stay
(real volume). `monotony_7d` / `strain_7d` are filled from
`workout_features` (currently null) as secondary signals. **ACWR is
removed from the prompt-facing state** — not surfaced to the Read. HR
context (`hr_pace_efficiency`, hard/easy HR split) comes along from
`workout_features`.

**Built 2026-06-12:**
- **Single "Volume × Intensity" load number** — `volume_x_intensity_7d` /
  `_28d` = `Σ(intensity_score × duration / 60)` (weighted minutes). The
  one number that matches paces to volume: a hard mile ≈ 5× an easy mile.
  Surfaced to the AI labeled "Volume × Intensity load," kept separate from
  the raw time-in-zone %.
- **Recovery folded into easy (= 1.0)** — the `0.7` recovery tier removed
  from both weight tables (`compute-workout-features` ZONE_WEIGHTS and
  `weeklyAnalytics` TYPE_FALLBACK_WEIGHTS).
- **Chart findable from the Read** — a tappable "VOLUME × INTENSITY · VIEW
  CHART ↗" row in `CoachReadView` jumps to the Training tab (index 1)
  where `PaceVolumeSpectrumChart` (continuous KDE) lives. Exact scroll-to-
  chart deep-link within Training is a follow-up (needs a target anchor in
  `TrainingTabView`).

### 2. Execution quality (did the workout land?) — 2/10 → 10/10
**Now:** nothing. A workout is a distance + an average pace.
**v2:** derive per-quality-session execution from `running_workout_laps`:
negative/positive split, fade %, rep-pace consistency, HR drift across the
session, whether prescribed splits were hit. This is what a coach actually
*reads* in a session — "5×1mi, held 5:18–5:22, last rep fastest, HR drift
under 5% — that's a strong workout."

### 3. Environmental context (defend against the bad run) — 0/10 → 10/10
**Now:** no weather/elevation anywhere in the state.
**v2:** pull per-run `heat_category`, `heat_adjustment_pct`,
**`heat_adjusted_pace_sec_per_mile`**, and `total_elevation_gain` from
laps. Enables the single highest-value trust move: *"7:45 today vs your
7:30 norm — but it was 78°F, dew point 70; heat-adjusted that's 7:28.
That's the weather, not your fitness."* The data is already computed
per lap; we just surface it.

### 4. The body (niggles & injury arc) — 3/10 → 10/10
**Now:** `possible_injuries` are recomputed every rebuild by regex over a
hardcoded ~20-part list. Not stored. A niggle can appear one day and
vanish the next. No `body_mentions` table exists in prod.
**v2:** create a durable `body_mentions` table (the one the spec assumes),
persist each detected mention with verbatim quote, body area, severity
hint, and the load context at the time. Build the niggle timeline +
recurrence from stored history, not a re-scan. `injuries` stays for
declared injuries; `body_mentions` is the surface layer. Keeps the
closed-vocabulary, surface-don't-diagnose contract (hard rule #2).

### 5. Fitness trajectory & predictions — 5/10 → 10/10
**Now:** point predictions only (`predicted_marathon_seconds`), plus a
6-month delta.
**v2:** carry `range_*` low/high + `confidence_tier` from
`fitness_snapshots` into the state, so the Read can show
"3:08–3:14, HIGH" and never a point estimate (hard rule #7 satisfied at
the data layer, not just the prompt). Add the trajectory framing already
present (building/peaking/returning) with its rationale.

### 6. The person (memory & life context) — 2/10 → 10/10
**Now:** `last_mood` + recent notes. No durable memory.
**v2:** read `user_memories` (category/content/importance) into the state —
preferences, constraints, life context, prior decisions ("racing Chicago
in October," "travels for work most weeks," "hates the treadmill"). Extend
extraction so voice memos persist durable memories (work stress, sleep,
travel, intent) instead of evaporating. This is the difference between a
coach who remembers you and a dashboard that recomputes you.

### 7. Longitudinal patterns (the coach's edge) — 1/10 → 10/10
**Now:** none. Each read sees a 7-day window + 24wk blocks.
**v2:** a derived pattern layer — correlations a coach notices over time:
niggle-clusters-after-volume-spikes, mood-dips-track-monotony, pacing
discipline tendency (does she go out too hard?), day-of-week reliability,
heat sensitivity, response to down weeks. Start rule-based on the data we
now have joined; this is what separates 7/10 from 10/10.

### 8. Calibration (knows what it doesn't know) — 4/10 → 10/10
**Now:** a single `data_depth` 0–3 and `confidence` on the snapshot.
**v2:** per-field **provenance + freshness + confidence** envelope — every
value carries where it came from and as-of when. `athlete_pace_profiles`
and `fitness_snapshots` already model this; extend the pattern state-wide.
This is what lets the Read cite honestly, lets the validator check claims,
and powers the `cant_see` block from real gaps instead of guesses.

---

## Phasing

**Phase A — Wire-up wins (no schema, no prompt, no eval gate; ~highest ROI).**
Read `workout_features` (load/strain/monotony/HR), `fitness_snapshots`
ranges + confidence, `athlete_pace_profiles` confidence/source-dates, and
`user_memories` into `AthleteState`. Kills the three null/stub fields and
adds memory + ranges immediately. Pure integration of read-only sources.

**Phase B — Laps-derived execution + environment. [BUILT 2026-06-12]**
Added `execution` (per quality session: rep paces, fade %, pace CV, HR
drift, split shape) and `environment` (per run: temp, dew point, heat
category, `heat_adjustment_pct`, actual vs heat-adjusted pace, elevation)
to `AthleteState`, sourced from `running_workout_laps` (joins to
`training_logs.id`; verified all 551 laps match). `stateToPromptContext`
now surfaces a "did the workout land?" execution section and a
heat-context "don't read heat as lost fitness" conditions section (only
for runs the heat actually affected, ≥2%). Uses the `execution` /
`environment` JSONB columns already reserved in the v2 satellites
migration — no new schema.

**Phase C — Durable niggles. [BUILT 2026-06-12]**
New `body_mentions` table (`20260612130000_body_mentions.sql`) with RLS in
the same migration (service-role write + owner read, mirroring
`athlete_state`), a unique index on (user_id, training_log_id, body_area),
verbatim quote + closed severity vocabulary. The rebuild now **upserts**
each detected mention (so they stop evaporating between rebuilds) and reads
the 12-month history back into a new `niggle_recurrence` field
("left knee: 3× over 6 weeks, worst: pain"), surfaced in
`stateToPromptContext` as a surface-don't-diagnose pattern line. The existing
30-day regex scan is reused as the detector; the table gives it permanence
and recurrence.
- **Backfill note:** the table starts empty, so recurrence only covers
  mentions seen since the first persisted rebuild. A one-time scan over all
  historical notes would populate full 12-month recurrence immediately —
  worth a follow-up backfill script.

**Phase D — Pattern layer. [BUILT 2026-06-12]**
Added a `patterns` block (the `patterns` JSONB column from the satellites
migration) — rule-based longitudinal observations over the now-joined data,
each `{ kind, statement, evidence, confidence }`. Shipped rules: pacing
fade/control tendency (`execution.fade_pct`), niggle-vs-volume-spike
(`possible_injuries.volume_context`), personal heat sensitivity
(`environment.heat_adjustment_pct`), easy-day discipline
(`load_distribution`), block-over-block easy-pace creep + down-week response
(`recent_blocks`). `stateToPromptContext` surfaces them as pre-computed
observations the LLM only narrates — honoring the Coach "never explains
math" rule and hard rule #2. Aligned to Rec #2 of
`athlete-state-smarter-coach-recs-2026-06-12.md`.

**Companion doc merged in (2026-06-12):**
`athlete-state-smarter-coach-recs-2026-06-12.md` (now in `outputs/`) is the
ranked next-steps companion to this spec. Still open from it:
- **Rec #1 — quiet bugs (do first, no schema/eval):** `fitness_trend`
  hardcoded `"maintaining"` (compare last 2 snapshots); `recent_blocks.injury_mentions`
  never incremented; `week_compliance_pct` always null (count completed vs
  scheduled); `priorBlockAvg` divides by 4 not 3 (optimism bias); `peaking`
  ignores race date; `isHardSession` classifier disagrees with block
  classifier (share one parsed-first classifier).
- **Rec #3 — race-time awareness:** `weeks_to_goal_race` + expected-phase
  mapping, `phase_alignment` mismatch flag, goal-gap-over-time per block.
- **Rec #5 — `cant_see` calibration block:** compute explicit data gaps at
  build time (no mood in N days, no parsed quality, no laps, no recovery).
- **Rec #7 — prompt token budget:** `stateToPromptContext` now renders
  >1,000 tokens for rich athletes; add `data_depth`-aware per-section
  trimming so the richest athletes don't get the most diluted prompts.

**Phase E — Reliability + provenance + builder refactor.**
- **Keep-warm [BUILT 2026-06-12]:** new `rebuild-athlete-state` edge-function
  worker (service-role, force-rebuild; single-user + batch modes) +
  `20260612140000_nightly_athlete_state_rebuild.sql` pg_cron that fans out one
  rebuild per active athlete nightly (mirrors `daily-weather-forecast`). Fixes
  the "2 rows" problem. Optional fast-follow: a build-on-insert trigger on
  `training_logs` for real-time freshness (not shipped — the nightly sweep +
  the existing lazy-on-read 60-min TTL cover the common case).
- **Still open:** per-field provenance envelope; the 2,000-LOC builder
  refactor — **gated on eval coverage** per CLAUDE.md, so it stays behind the
  harness.

Sequence rationale: A and B are pure read-side integration of data that
already exists — fast, safe, and they fix most of what's visibly thin.
C/D/E carry schema, migration, and eval weight, so they follow.

---

## Guardrails

- **RLS in the same migration** for `body_mentions` (hard rule #1).
- **Migrations via `db push` from a committed SHA** — no dashboard/MCP
  ad-hoc applies (hard rule #9; the ledger is already damaged).
- **Predictions ship as range + confidence** — enforced at the data layer
  now, not just the prompt (hard rule #7).
- **Niggles surface, never diagnose** — closed vocabulary, verbatim quotes
  (hard rule #2 / Niggles spec).
- **Builder refactor gated on eval coverage** (hard rule #3).

---

## Open questions

1. **RESOLVED (2026-06-12): load = volume × intensity distribution, not
   ACWR.** Sourced from `workout_features` time-in-zone, matching
   `PaceVolumeSpectrumChart`. ACWR is dropped from the prompt-facing state.
   Rolling miles + monotony/strain stay as secondary. Open sub-question:
   delete the builder's ACWR computation entirely, or leave the column
   populated but unused for one release as a safety net? *Recommend leave
   the column, stop surfacing it.*
2. **Keep-warm trigger:** rebuild on workout insert (freshest, more compute)
   vs. a nightly cron (cheaper, can be up to a day stale) vs. both.
   *Recommend build-on-insert for the active athlete + nightly sweep.*
3. **Pattern layer depth:** how many patterns to ship in v2, and rule-based
   vs. a small LLM synthesis pass over the joined data.
4. **`athlete_state` row width:** as it absorbs execution, environment,
   memory, and patterns, does it stay one wide row or split into a
   core row + satellite JSON columns? *Recommend JSONB satellites for the
   pattern/execution/memory blocks to keep the core lean.*

---

## First slice to build

Phase A — point `athlete_state` at `workout_features`, `fitness_snapshots`
ranges, and `user_memories`. No schema, no eval gate, immediate fix to the
null/stub fields, and it makes the state meaningfully more coach-like in
one pass. Recommend starting there.

# The Read — implementation spec (for Opus / Claude Code)

**Date:** 2026-06-13
**Audience:** an autonomous coding agent working in this repo.
**Goal:** make the coaching engine actually *see* the athlete's training —
detect real workouts from lap data, score intensity-weighted load, adjust
for heat, and surface it in a "model of you" coaching surface.

> **Read first:** `/Users/rioreina/my-running-app/CLAUDE.md` (hard rules),
> then `outputs/the-read-redesign-plan-2026-06-13.md` (product intent).
> Design intent for the UI is prototyped in three real-data HTML files in
> `outputs/`: `model-of-you-mock.html`, `workout-detail-viz.html`,
> `weather-adjustment-viz.html`. Open them — they are the target.

## How to use this doc

Work the workstreams **in order** — each depends on the prior. WS0→WS3 are
backend/data and unblock everything; WS4→WS6 are surfacing. Every change
ships behind the repo's hard rules (below). After each workstream, run its
**Acceptance** check before moving on.

### Non-negotiable repo rules (from CLAUDE.md — do not violate)

- **No LLM prompt change without eval coverage.** Cassettes live in
  `supabase/functions/_evals/cassettes/<prompt>/`. CI fails a PR touching
  `_shared/prompts/` without them (`.github/scripts/check_eval_coverage.py`).
- **Migrations are append-only and reach prod only via `supabase db push`
  from a committed SHA.** Never `apply_migration`/dashboard SQL against prod.
  Every new table ships RLS in the same migration.
- **AI advises, never prescribes or diagnoses.** Niggles surfaced verbatim.
  Predictions ship as **range + confidence**, never a point; round to whole
  minutes.
- **No em-dashes as empty-state placeholders.** Use the empty-state component.
- **`TIMESTAMPTZ`, not `TIMESTAMP`.** Auth user IDs are `TEXT`.

### Test athlete (golden data)

`user_id = '03857bf3-6276-4634-b3cc-15cc6d0bc653'` — 204 runs, 1,335 mi
since Dec, rich lap data. Use for all before/after verification. Pace zones
(sec/mi) from its `athlete_state`: easy 429, moderate 405, steady 362, MP
343, HMP 328, 10K 314, 5K 302, mile 272.

---

## WS0 — Unblock the async pipeline (403 storm)

**Why:** the three drain crons (`drain-voice-processing-jobs`,
`drain-coach-insight-jobs`, `drain-coachable-moment-jobs`) return **403 every
minute** and have since 2026-06-11. Nothing downstream (voice cleaning, coach
insights, coachable moments) is current until this drains. Confirmed:
`coach_insight_jobs` has a multi-day `queued` backlog.

**Root cause:** each drain authenticates by exact string match
`constantTimeEq(token, SUPABASE_SERVICE_ROLE_KEY)`. The cron now reads the key
from Vault at runtime (migration `20260611160000_fix_drain_cron_auth_dynamic_vault.sql`
is live), but the Vault `service_role_key` is a legacy `eyJ…` JWT while the
functions' env key has rotated. Vault ≠ env → 403.

**Fix (do the robust one):**
- Port all three `supabase/functions/drain-*/index.ts` to the auth pattern
  `rebuild-athlete-state` already uses: `verify_jwt = true` in `config.toml`
  + validate the JWT **`role` claim** is `service_role`, instead of exact-key
  match. This accepts any valid service-role token and survives key rotation.
- Alternatively (quick, ops-only, no deploy): set Vault `service_role_key` to
  the functions' current `SUPABASE_SERVICE_ROLE_KEY`. Recovers next tick.

**Acceptance:**
- `select status, count(*) from coach_insight_jobs group by status;` → the
  `queued` backlog drains to ~0 within a few minutes.
- Edge logs show the three drains returning `200`, not `403`.

---

## WS1 — Segment-aware workout detection & intensity (the core fix)

**Why:** the engine cannot see quality work. For the test athlete, 90 days
contains **63 sub-5:40 reps** and **11 real workouts**, but `athlete_state`
reports **0 quality sessions** and the load engine scores **5 of 161** runs as
having any hard/threshold time.

**Two root causes in `supabase/functions/compute-workout-features/index.ts`:**

1. **It classifies by a stored `effort` *label*, not by pace.**
   `effortWeight(effort)` / `isHardEffort(effort)` look up a label table.
   Labels in prod are wrong/missing: most segments are labeled `"steady"` or
   `"easy"`, and the label `"fast"` (49 segments) **isn't even in the table**,
   so it scores as easy (weight 1.0).
2. **It reads per-mile `pace_segments`, which destroy rep structure.** A
   10×1K @ 5:07 with 90s jogs (GPS left running) averages into ~1-mile splits
   at ~6:20 → scored easy. The real reps live in `running_workout_laps`
   (rep-level, with an `is_rest` flag) — currently unused by this path.

**The fix — rewrite the scorer to read structure, classify by pace:**

1. **Source priority:** score from the finest structure available, in order:
   `running_workout_laps` (preferred — rep-level, has `is_rest`,
   `avg_pace_sec_per_mile`, `distance_meters`, `avg_heart_rate`) →
   raw stream → per-mile `pace_segments` (last resort).
2. **Separate work from recovery:** trust `is_rest` when present. When absent,
   detect it: a sustained bout faster than `steady` is work; slower bouts
   between are recovery; apply a min-duration guard (≥ ~20s and ≥ ~150m) so a
   downhill blip isn't a "rep."
3. **Classify each work bout by ACTUAL pace vs the athlete's pace zones**
   (pull `pace_zones` / `pace_zone_ranges` from `athlete_state`, or compute via
   `web/src/components/coach/workout-helpers.ts:derivePaceTableFromGoal` /
   race anchor). Replace the label lookup entirely.
4. **Score load from the work at true intensity**, recovery weighted easy:
   `intensity_score` = Σ(zone_weight × bout_seconds) / Σ(seconds);
   `threshold_seconds` / `hard_seconds` from the work bouts only.
   Keep the existing `ZONE_WEIGHTS` scale (easy 1.0 → mile 5.0); add `"fast"`
   and any other observed labels, but **pace is the source of truth**.
5. **Derive `workout_type` + a structure string** and persist them (backfill
   the 98 untyped imports). Type taxonomy and the decision tree below.

### Classifier (validated on real data — use as the spec)

Pace→zone (athlete-relative; example cutoffs for the test athlete, sec/mi):

```
<=287 mile | <=308 5K | <=321 10K | <=337 threshold/HMP
<=352 MP   | <=372 steady | <=417 moderate | <=470 easy | else recovery
```

Session type (decision tree on detected work bouts):

```
no work bouts            -> Long run (>=11 mi) else Easy
work bouts present:
  short reps + rest, pace 5K/mile      -> Intervals (VO2/5K)
  reps + rest, pace 10K                 -> Intervals (10K)
  long reps (>=1mi), LT/10K pace, little rest, low CV -> Threshold (cruise)
  reps at threshold pace + rest         -> Threshold reps
  one sustained block, MP–HMP, no rest  -> Tempo
  irregular bout length/pace, no clean rest -> Fartlek
  continuous ~race effort, ~race dist   -> Race
```

Tempo vs threshold is intentionally fuzzy — split by the pace zone of the
sustained work (MP/steady = tempo, HMP/LT = threshold). Document the boundary.

**Unify, don't duplicate:** rep detection already exists once, in
`athlete-state.ts` (the `execution` block, ~lines 1543–1660, built from
`running_workout_laps`). Extract a single shared segmentation module and have
**both** the `execution` display and `compute-workout-features` consume it.

**Backfill:** `compute-workout-features` has a `backfill` mode — run it for
the athlete over full history after the rewrite, then trigger
`rebuild-athlete-state`.

**Acceptance (golden, test athlete):**
- May 20 classifies as **Intervals, 9×1K @ ~5:08 (5K pace)**, not easy.
- 90-day quality count ≈ **11 workouts** (6 interval / 3 threshold / 1 tempo /
  1 race), matching the prototype:

  ```
  python3 — re-run outputs prototype; expected labels:
  5/20 Intervals 9x1K@5:08 · 5/15 Threshold 4x1K@5:32 · 5/12 Intervals ladder
  5/5 Threshold 5x1mi@5:17 · 4/28 Tempo · 4/21 Intervals · 4/12 Race
  4/4 Threshold 6x1mi@5:22 · 3/31 Intervals 6x1mi · 3/27 Intervals short
  ```
- Verify: `select count(*) from workout_features wf join training_logs tl on
  tl.id=wf.training_log_id where tl.user_id='03857bf3…' and tl.workout_date >
  now()-interval '90 days' and (coalesce(wf.threshold_seconds,0)+coalesce(wf.hard_seconds,0))>0;`
  → was **5**, should be **~11+**.

---

## WS2 — Heat adjustment unit bug

**Why:** `running_workout_laps.heat_adjustment_pct` is computed and stored as a
**fraction** (e.g. `0.02` = 2%), but consumers read it as a **percent**. In
`athlete-state.ts` the environment block filters `heat_adjustment_pct >= 2`, so
it is always false → every run shows "0% / no heat effect," even an 85°F /
70°-dew day.

**Fix:**
- Pick one unit and make it consistent end to end. Recommended: store **percent**
  (`2.0`), or keep the fraction and fix every consumer (`>= 0.02`, and ×100 on
  display). Grep for `heat_adjustment_pct` and `heat_adjusted_pace` across
  `supabase/functions/`, `RunningLog/`, `web/`.
- Heat-adjusted pace is **opt-in** (a toggle), never overwrites recorded pace.
  Default off. See `weather-adjustment-viz.html` and the toggle in
  `workout-detail-viz.html` for the interaction.
- Model: pace cost from temp+dew-point load (transparent banded heuristic;
  dew point is the dominant driver). Keep it visible/explainable.

**Acceptance:** May 20 (67°F / 67° dew) surfaces ≈ **+2% / ~6 s/mi**; May 19
(85°F / 71° dew) ≈ +4%. The athlete-state environment block lists hot runs
instead of an empty set. Add a unit test pinning fraction-vs-percent.

---

## WS3 — Load model: retire ACWR ratio, promote weighted load

**Why:** ACWR is an injury-risk ratio, not a coach's read; and it was only ever
correct insofar as `intensity_score` was correct (it wasn't — WS1). Now that
WS1 fixes intensity, the existing weighted-load engine becomes real.

**What exists (reuse):** `supabase/functions/_shared/weeklyAnalytics.ts` already
computes `weightedLoad` (= `intensity_score × duration`, "weighted minutes")
and `calculateACWR` (acute ÷ EWMA chronic). `athlete-state.ts` already exposes
`load_distribution` (volume×intensity 7d/28d, zone %, monotony, strain).

**Changes:**
- **Surface** `load_distribution.volume_x_intensity` trend + the hard/easy zone
  split + a recovery read (hard-day spacing, down-week cadence) as the primary
  load story. Plain language: building / holding / spiking / backing off.
- **Demote ACWR** to an internal injury-risk input only; stop surfacing the
  ratio. Finish removing it from `recent_training_summary` (it's still
  concatenated there).
- **Lengthen the chronic window** from 4 weeks toward 8–12 (see redesign plan
  §5). Keep range/confidence framing.

**Acceptance:** for the test athlete, the load read shows a real mixed block
Mar–May 20 then an easy-only stretch (the genuine 3-week quality gap), and
`volume_x_intensity_7d` is non-zero on weeks with workouts (was 0).

---

## WS4 — Fitness: real range + confidence

**Why:** `athlete_state.fitness_prediction.ranges` currently has `low == high
== point` (collapsed). Violates hard rule #7.

**Fix:** compute genuine range bands with a confidence tier driven by evidence
(workout count, recency, race anchors). Anchor on `confirmed_races` over goal
time. Round to whole minutes. Files: the fitness predictor path feeding
`fitness_prediction` (see `_shared/prompts/fitness-predictor.v1.ts` and the
fitness snapshot builder).

**Acceptance:** test athlete shows e.g. `10K 32:1x–32:4x, HIGH (58 workouts +
recent 10K)`, never a single time.

---

## WS5 — Daily Read prompt (v3 → v4) + windows

**Why:** the Read narrates stats, forgets qualitative signal (memo lookback
capped at 14 days), and now needs to consume the corrected workouts/load.

**Changes (in `coaching-daily-read/index.ts` + `_shared/prompts/daily-read.v4.ts`):**
- Restructure to the spine in redesign plan §3.1 (headline → load&balance →
  trends → fitness → human read → one call → what I can't see).
- Lead with an observation; every claim cites a number **and a change over a
  stated window**. Add good/bad voice exemplars.
- Widen memo memory: raise `VOICE_MEMO_LOOKBACK_DAYS` (currently 14) to 60–90,
  or roll older sentiment into a `memories`/`patterns` summary.
- Reconcile the token budget: `coaching-daily-read` hardcodes
  `maxOutputTokens: 8000` while `router.ts` `getModelConfig("complex")` says
  2000 — make them agree (and comment the override) so a future cleanup can't
  reintroduce the 502 truncation.
- A/B `gemini-2.5-flash` vs `gemini-2.5-pro` for this call; mind that Flash's
  thinking tokens share the budget.

**Required:** add `_evals/cassettes/daily-read.v4/` cassettes before shipping
(CI gate). Manual review against `docs/coaching/principles.md`.

**Acceptance:** eval cassettes pass; the Read references real workouts ("your
9×1K Tuesday") and the 3-week quality gap; no invented paces; range+confidence
intact.

---

## WS6 — The "model of you" surface (athlete-facing)

**Why:** the rich `athlete_state` is backend-only. Promote it to the Coach
surface as a legible, evidence-backed, correctable model. Design intent =
`outputs/model-of-you-mock.html`.

**Build (iOS `RunningLog/Coaching/` — Coach tab):**
- Coach opens to **the read** (today's analysis), then model-of-you cards:
  Fitness, Load & balance, Workouts & reps, Watching (wear & tear), What I
  can't see.
- **Back-door interaction:** each card is a trapdoor → evidence drawer →
  "ask" that opens the `coaching-agent` chat **pre-seeded with that card's
  context** (no blank box). Recommendations live in chat, soft, never
  prescriptive.
- **Workouts & reps card** → workout-detail view (design =
  `workout-detail-viz.html`): rep-by-rep pace bars, HR overlay, rest, pace-zone
  reference lines, structure string.
- **Heat as a context chip that is also the toggle** (design =
  `workout-detail-viz.html`): quiet warning by default; tap reveals
  heat-adjusted splits. Don't add separate chrome — the nudge is the control.
- Honor Post Run Drip (`design-system/`): warm paper, ink, one coral accent,
  Crimson Pro / PT Serif, eyebrow labels, no em-dash empty states.

**Depends on:** WS1–WS4 (the cards are only honest once the data is correct).
Note `user_profiles` does not exist in prod and `athlete-state.ts` (~1481 LOC)
has a pending refactor — sequence accordingly (redesign plan §6).

**Acceptance:** Coach tab renders the model with real cards; tapping a workout
opens the rep view; the heat toggle reveals adjusted splits; chat answers from
`athlete_state` only (quotes zones, never invents).

---

## WS7 — duplicate training_logs (data hygiene; partly shipped)

**Why:** measured on the golden athlete — **48 of 160 logs (30%) are
duplicates**, inflating 90-day volume **~28%** and the quality count (23 vs
~12). It also surfaces the WRONG workout: May 20's lapless `voice_log` copy
classifies `recovery` while the real 9×1K lives on the `strava` copy. Every
volume/load/ACWR/quality number is downstream of this — fix it or the corrected
WS1 data is still wrong in aggregate.

**Finding:** there are **zero** duplicate `vital_workout_id` groups — all dupes
are *cross-source with differing/absent keys* (`strava`+`voice_log`,
`auto_sync`+`strava`). So a natural-key constraint alone cannot prevent them.

**Shipped this session (reviewable, NOT applied — needs `db push`):**
- `migrations/20260613220000_dedupe_cross_source_training_logs.sql` — one-time
  heal. Merges qualitative fields (notes/mood) from dropped copies onto the
  keeper, keeps the richest copy (most laps → segments → notes → oldest).
  Exact-key dups removed outright; heuristic (day + ~0.5mi) dups removed only
  when the loser has **zero laps** (no structure ever lost). Preview-validated
  read-only against prod: keeps the lap-owner in every group.
- `migrations/20260613230000_training_logs_vital_workout_id_unique.sql` —
  partial unique index on `(user_id, vital_workout_id)` — future-proofs the
  same-id re-import class (currently zero, defense-in-depth).
- After applying: re-run `compute-workout-features` backfill + `rebuild-athlete-
  state`; verification SQL is in the cleanup migration footer.

**Durable prevention — SHIPPED as a recurring sweep (not a trigger):**
- `migrations/20260613240000_dedupe_training_logs_recurring.sql` — a
  `SECURITY DEFINER` function `dedupe_recent_training_logs(p_days)` + a 30-min
  `pg_cron` job. Reuses the one-time heal's exact logic, scoped to recent days.
  A sweep (vs. an INSERT trigger) is deliberate: rep-level **laps arrive
  asynchronously after the log**, so insert-time you can't tell which copy is
  the lap-owner — it depends on arrival order. The sweep runs once the state
  has settled, so the merge is always correct. Grouping is by
  (user, day, ~0.5mi) because cross-source copies carry different/absent keys.
  `search_path` pinned + tables qualified (avoids the drain-RPC schema bug).

**Optional further hardening (not required, not done):** an ingestion-time
match-or-attach so a voice memo annotates an existing run rather than briefly
creating a second row the sweep later collapses. Lower urgency now that the
sweep guarantees convergence; it would only remove the few-minute transient
duplicate window. Touches `process-training-memo` / `auto_sync` insert
contracts, so it needs its own review.

## Build order summary

1. **WS0** pipeline 403 (unblocks data freshness)
2. **WS1** segment-aware classifier (unblocks everything coaching-accuracy)
3. **WS2** heat unit fix · **WS3** load model · **WS4** fitness range (parallel-ok, all depend on WS1)
4. **WS5** Read v4 prompt + windows (depends on WS1–WS4)
5. **WS6** model-of-you surface (depends on WS1–WS4; UI)

## Bugs catalogued this session (all proven on the test athlete)

1. Read 502 — Flash thinking tokens vs 2000 cap → JSON truncation. *Fixed
   (8000), but router/​function disagree — reconcile in WS5.*
2. Pipeline 403 — drains' exact-key auth vs rotated key. **WS0.**
3. Quality work invisible — label-based scoring on per-mile splits. **WS1.**
4. 98 untyped imports — no `workout_type`. **WS1.**
5. Heat adjustment zeroed — fraction stored, percent consumed. **WS2.**
6. Fitness "range" collapsed to a point. **WS4.**

## Design artifacts (target UI, real data)

- `outputs/model-of-you-mock.html` — the Coach surface, back-door cards.
- `outputs/workout-detail-viz.html` — rep-by-rep workout view + heat toggle.
- `outputs/weather-adjustment-viz.html` — full heat-adjustment treatment.
- `outputs/the-read-redesign-plan-2026-06-13.md` — product rationale + phasing.

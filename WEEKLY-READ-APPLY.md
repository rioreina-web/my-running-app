# THE READ — the weekly training report

**Authored:** 2026-08-20 · spec + prototype only, **nothing applied to the tree**
**Prototype:** `the-weekly-read-prototype.html`
**Supersedes in spirit:** `daily-read.v5` (voice, kept), `weekly-coaching-report.v1` (scope, replaced)
**Companions:** `WEEK-TAB-APPLY.md` (the surface it sits on), `ASK-APPLY.md` +
`ASK-REGISTRY.md` (the architecture it borrows), `design-system/README.md` (the voice)

---

## 0 · The decision this document exists to force

The brief asked for a weekly report with insight in it. Two of the three
examples given were **prescriptions**:

> *"got bad sleep, had a tough workout"* → **"we need to aim for 7–8 hrs of
> sleep to maximize our training and recovery needs"**
>
> *"had a flare up in the knee"* → **"this is the 4th time in the last 2
> months, let's take some time to make adjustments in training if needed"**

Nothing currently shipping is allowed to write either sentence.

| Surface | Rule in force | Source |
|---|---|---|
| Ask | *"OBSERVATION, NOT PRESCRIPTION. No 'you should', no training instructions, no rest recommendations."* | `prompts/ask-narration.v1.ts` |
| The Read (daily) | A soft call is allowed in the **One thing** section, in `PLAN_MODE` / `SELF_COACHED_MODE`. Never in `COACHED_MODE`. | `prompts/daily-read.v5.ts` |
| Everything | Niggles: *"surface, never diagnose or direct."* The only permitted "so what" is a **training** adjustment, or "worth raising with a professional." | `daily-read.v5`, hard rule #2 |
| Voice | **No "we."** *"The app doesn't talk about itself."* | `design-system/README.md` |

So the two example lines, rewritten inside the rails the product already
enforces:

| Asked for | What ships |
|---|---|
| "we need to aim for 7–8 hrs of sleep to maximize our training and recovery needs" | "Six hours on the three nights you mentioned, in your biggest week of the block. The session still landed, so this isn't costing you fitness yet — it's the thing that decides whether the next three weeks feel like this one." |
| "this is the 4th time we had this flare up in the last 2 months, let's take some time to make adjustments in training if needed" | "Fourth time the achilles has come up in nine weeks, and the note is the same every time — sore on the warm-up, quiet after a mile. Four mentions with the same shape is a pattern worth putting in front of someone who can look at it." |

Both are more useful than the originals and neither is a medical claim. The
difference is not softness — it is that the product **names the pattern and the
stake, and leaves the call with the athlete.** That is the whole posture.

**One deliberate exception.** Section **06 · One thing** is licensed to make
exactly one training call per week, in plain imperative, because `daily-read.v5`
already licenses it and because a weekly report that ends without a call is a
newsletter. It is bounded: training only, never rest-as-treatment, never medical,
suppressed entirely in `COACHED_MODE`, and **droppable** — if nothing honestly
warrants a call, the section does not render.

**If that trade is wrong, stop here.** Everything below assumes it.

### The other §0 — inherited, non-negotiable

From `WEEK-TAB-APPLY.md §0`, and it binds this build completely:

1. **If a value cannot be derived from the athlete's own rows, do not produce it.**
2. **Never attach provenance to a number you invented.**

The prototype carries a banner saying every number in it is illustrative. That
banner exists because the last thing built on this surface shipped a fixture
that looked finished and was a string someone typed. Read that section before
wiring anything.

---

## 1 · What it is

Seven sections. The brief's five asks map onto them like this:

| § | Section | Brief | What answers it |
|---|---|---|---|
| — | Masthead + eyebrow | (2) goals as backdrop | `active_goals`, `confirmed_races` |
| 01 | **The week** | (4) mileage, load, shape | `trends-timeline`, `load_balance` |
| 02 | **The key sessions** | (3) execution, weather, drift, HR, comparison | `heat_effect`, `decoupling`, `efficiency`, `compare_session` |
| 03 | **How you felt** | (1) voice memos, sleep, niggle threads | `training_logs.extracted_data`, `body_mentions`, `niggle_timeline`, `mood_trend` |
| 04 | **Against the goal** | (2) what's needed to hit it | `race_projection`, `race_pace_specificity` |
| 05 | **Where the miles went** | (4) pace distribution, easy-stays-easy | `zone_pct_7d`, `easy_discipline`, `zoneTrend` |
| 06 | **One thing** | the call | derived, see §0 |
| 07 | **For the log** | (5) capture mood / niggles / fatigue / words | writes to `training_logs`, `body_mentions` |
| — | What I can't see · confidence · sources | — | `Coverage` from every analyzer, unioned |

Order departs from the brief's numbering on purpose: **goals come after the
evidence.** "What's needed to hit the goal" is an inference from the sessions
and the body, so it cannot be the second thing on the page. The goal still
frames the whole report — as the eyebrow, per `daily-read.v5`'s rule that the
goal is the backdrop, carried lightly.

Section 07 is last because the brief asked for it last, and because a capture
prompt at the end of a report the athlete has just read is the one moment in
the week they have context loaded.

---

## 2 · Architecture — a scheduled Ask, not a bigger prompt

**This is the single most important call in the document.**

There are two ways to build a weekly report, and the codebase has already tried
one of them.

### The way that is already built, and should not be extended

`weekly-coaching-report/index.ts` + `weekly-coaching-report.v1.ts`: assemble
~15 pre-formatted context blocks, hand them to one large prompt with a
five-point analysis framework, and ask for 4–6 paragraphs of narrative. The
model does the analysis *and* the writing. It is the oldest coaching prompt in
the repo and it has no structural defence against a number that isn't there.

### The way to build it

`ask/index.ts` + `_shared/analyzers/` + `narration-guard.ts`, which shipped
2026-08-05 and states its contract in one line:

> **If a number is not in `facts`, it does not exist.**
> — `_shared/analyzers/types.ts`

Analyzers compute deterministically and emit `FactLine[]`. Layer 2 receives the
facts, the scope and the confidence — **not** the rows, not the athlete state —
and `validateNarration()` rejects the whole response if it speaks a number that
isn't printed in the facts. `firstUnlicensedScopeClaim()` additionally rejects
narration that claims a filter the analyzer never applied.

**The weekly Read is that pipeline, fanned out and scheduled.** Per section:

```
  for each section:
      run its analyzers  →  FactLine[] + Coverage + SeriesSpec
      if coverage insufficient  →  render EmptyState, DO NOT narrate
      else  →  narrate under narration-guard, scoped to that section's facts
  compose  →  weekly_reads row
```

Three things fall out of this for free, and each is expensive to add later:

- **The numbers cannot be invented.** They are rendered from `facts`, and the
  prose is mechanically checked against the same list.
- **Every number can name its source.** The provenance sheets in the prototype
  are not new work — `Coverage.missing`, `SeriesSpec.points` and the analyzers'
  own row fetches already carry what they need.
- **Sections go dark honestly and independently.** A week with no quality
  session drops section 02 and keeps the other six, because coverage is
  per-analyzer. In one fat prompt, thin data degrades the *whole* report into
  hedged prose.

### Analyzer → section map

Every analyzer named is **registered today** in `_shared/analyzers/index.ts`.

| § | Analyzers | Status |
|---|---|---|
| 01 | `load_balance` | registered |
| 02 | `compare_session`, `heat_effect`, `decoupling`, `efficiency` | registered |
| 03 | `niggle_timeline`, `mood_trend` | registered |
| 04 | `race_projection`, `race_pace_specificity` | registered |
| 05 | `zone_trend` + `current_fitness` | registered |

Eleven analyzers exist. Nine of them are the weekly Read. **This is a
distribution build, not an analytics build** — which is exactly what
`ASK-REGISTRY.md §0` says about Ask, and it is even truer here.

### What it does NOT reuse

- **Not** a second fetch. Section 01 and 05 read `TrendsService` /
  `trends-timeline`, the same payload `WeekService` maps, so the Read and the
  Week tab under it can never disagree about the week's mileage. A second
  implementation of a weekly total drifts from the first within a month.
- **Not** `daily_coaching_reads`. New table, new cadence, different shape.
- **Not** the daily Read's context assembly. `athlete_state` is still the source
  for the *narrative frame* (block position, coaching mode, memories), but every
  **number** comes through an analyzer.

---

## 3 · The data-honesty table

What each part of the brief can actually stand on. Status vocabulary is
`ASK-REGISTRY.md §1` — **WRAP** (math exists, adapt it), **JOIN** (both operands
persisted, nothing divides them), **BUILD** (new math), **BLOCKED** (not captured).

### (1) Voice memos → insight

| Signal | Where it lives | Status |
|---|---|---|
| Mood, closed vocabulary | `process-training-memo.v3` → `training_logs.mood` | **WRAP** |
| Sleep hours + quality **as stated in a memo** | `extracted_data.sleep_hours` / `.sleep_quality` | **JOIN** — captured per-memo, never aggregated across a week |
| Fatigue, work stress, life stress, travel, illness, motivation | `extracted_data.*` — all seven fields exist | **JOIN** — same: captured, never rolled up |
| `felt_vs_looked` | `extracted_data.felt_vs_looked` | **WRAP** — the highest-value field in the schema and it reaches no surface |
| Body-part mentions, verbatim | `body_mentions` (+ `20260702180000_body_mentions_severity_check.sql`) | **WRAP** |
| Recurrence — *"4th time in 9 weeks"* | `niggle_timeline` analyzer + `20260613100000_athlete_state_niggle_recurrence.sql` | **WRAP** |
| All-clear — a niggle stops being flagged | `niggle_resolutions` (`20260702190500`) | **WRAP** |
| Sleep + HRV **measured** | `daily_biometrics` — two producers, both shipped (see §3.1) | **WRAP** |

**The sleep insight in the brief is buildable today, and it is a JOIN, not a
build.** `process-training-memo.v3` already extracts `sleep_hours` from what the
athlete says. Nothing groups them by week, and nothing puts them next to how a
session went. That join — memo-stated sleep × session execution — is roughly ten
lines of arithmetic and it is the single highest-yield item in this document.

**Label it as self-reported when that is what it is** — but note it may not be
the only sleep the report has. See §3.1: measured sleep and HRV are shipped, and
which of the two the Read leans on depends on the account, not on the codebase.

### 3.1 · Measured sleep and HRV — CORRECTED 2026-08-20

**An earlier draft of this document repeated `WEEK-TAB-APPLY.md §4` and
`ASK-REGISTRY.md §0.1`: that `daily_biometrics` is "migrated, RLS'd and indexed
and empty, because `vital-webhook` has no daily-sleep branch." That was true when
`ASK-REGISTRY.md` was written on 2026-08-05. It was fixed the next day. The Week
tab doc repeated it on 08-19, two weeks stale, and this document repeated it a
third time.** This is the exact failure `WEEK-TAB-APPLY.md §0` was written about
— a stale doc producing a wrong argument — and it is recorded here rather than
quietly edited out.

What is actually built:

| Layer | What | Where |
|---|---|---|
| Storage | HRV, resting HR, lowest HR, sleep duration, respiratory rate. PK `(user_id, date, source)`, athlete read-only, service-role write | `20260804090000_daily_biometrics.sql` |
| Storage | Self-reported sleep quality, athlete read/write | `20260804090100_daily_checkins.sql` |
| Producer A · Garmin | `data.sleep.*` branch **and** a standalone `data.hrv.*` branch with historical backfill via `/timeseries/{u}/hrv` | `vital-webhook/index.ts` + `_shared/hrvNights.ts` |
| Producer B · Apple | HealthKit → `ingest-biometrics`, `source='healthkit'`, fires on launch | `Health/HealthBiometricsSync.swift`, called at `App/RunningLogApp.swift:330` |
| Read | Decorates each day with `hrv_rmssd`, `resting_hr`, `sleep_total_min`, `sleep_quality` | `trends-timeline/index.ts:213–275` |
| Consumer | **Overnight factor** (HRV + resting HR vs own 28-day baseline at 0.5× own SD) and **Sleep factor** (7-day mean vs 14-day baseline) | `Trends/TrendsRecoveryFactors.swift:465, 561` |
| Consumer | Self-report prompt on the home screen | `App/SleepCheckInPrompt.swift` |
| Consumer | Week tab **already reads all three** and builds recovery rows when present | `Week/WeekService.swift:432–452` |

**SDNN is not RMSSD.** Apple reports SDNN, Garmin reports RMSSD; different
metrics, different scales, never poolable. Two things keep them apart and both
already ship: the PK carries `source`, and `trends-timeline` **pins one source
for the whole window** before decorating any day. The Overnight factor compares
an athlete only to their own baseline, so it is scale-free — which is why SDNN
works at all. **Do not pool them, and do not "fix" the `hrv_rmssd` column name.**

So what is actually limiting:

1. **The Garmin producer has delivered nothing since 2026-04-03** — stated in
   `HealthBiometricsSync.swift`'s own header, which is why the HealthKit producer
   was built on 08-06. A Garmin-only athlete may genuinely have an empty table.
   That is an integration-health question, not a build question.
2. **Whether this account has rows is unknown from the code.** It depends on
   HealthKit permission having been granted and the sync having run. **Check
   before writing §03's copy** — `select source, count(*), max(date) from
   daily_biometrics group by 1`.
3. **`WeekService.swift:461`'s fallback string is stale copy** — it says
   "`daily_biometrics` exists but nothing writes to it yet," which stopped being
   true on 08-06. One-line fix, and it should be made whether or not this ships.
4. **Deliberately not captured, and leave it that way:** sleep stages, sleep
   efficiency, sleep score. Tier-0 in `docs/specs/recovery-trend-v2-2026-07-27.md`
   §7.4 — *"capturing them invites someone to use them."* Apple exposes stages and
   `HealthBiometricsSync` reads them **only** to decide whether a sample counts as
   asleep. Never stored, never surfaced.

**What this changes for §03.** The section has two sleep sources, not one, and
they answer different questions. Measured duration says how long you were
asleep; the memo says whether you felt it. Prefer the measured number when it
exists, label the memo-stated one as self-reported when it doesn't, and never
silently swap between them mid-report. The brief's sleep insight is available at
a higher grade than this document first claimed.

### (2) Training goals

| Signal | Where | Status |
|---|---|---|
| Goal race, date, target time | `active_goals`, `confirmed_races` | **WRAP** |
| Projection as a **range** | `race_projection` analyzer | **WRAP** |
| Gap to goal pace | `active_goals[].gap_vs_current_sec_per_mile` | **WRAP** |
| "What's needed" — miles at goal pace | `race_pace_specificity` | **WRAP** |
| Long-run progression across the block | `fitnessPrediction.ts:longRunReadiness` gives a level, not a trend | **JOIN** |

Never a single predicted finish time. `daily-read.v5` calls a bare
seconds-precision finish **"a hard failure"**, and it is right: it is the
fastest way to lose an athlete's trust permanently.

### (3) Key session analysis

| Signal | Where | Status |
|---|---|---|
| Conditions-adjusted pace | `heat_effect` + `fetch-workout-weather` + `20260813200000_backfill_weather_actuals_cron.sql` | **WRAP** |
| Aerobic drift / decoupling | `decoupling` analyzer | **WRAP** |
| HR efficiency (metres per heartbeat) | `efficiency` analyzer | **WRAP** — computed, and `WEEK-TAB-APPLY.md §4` records it as `.notWired` to the Week tab |
| Compare to similar sessions | `compare_session` | **WRAP** |
| Rep-by-rep execution, fade | `workout_features.rep_signal` (`20260815160000`) | **WRAP** |
| **Hills / elevation** | `running_workout_laps.total_elevation_gain` + `pace-grade-adjustment.ts` exist; nothing joins them into a verdict. `terrain_match` = **BUILD** in `ASK-REGISTRY.md §III` | **BUILD** |

**Hills is the one thing in the brief that is not close.** The prototype renders
it as an honest dark note rather than a chart, and that is the correct ship
state for v1. Elevation is stored; a grade-adjusted *session verdict* is real
new math.

### (4) Overall metrics

| Signal | Where | Status |
|---|---|---|
| Mileage, runs, time — **doubles summed** | `trends-timeline` payload | **WRAP** |
| Weekly load vs the athlete's own band | `zoneLoad` + `WeekBuilder` baseline (mean ± 1 SD of prior weeks, layoffs held out) | **WRAP** |
| Pace-zone distribution | `workout_features.zone_pct_7d` | **WRAP** |
| **Easy days staying easy** | `athlete-state.ts:1658` pattern `easy_discipline` (easy < 65%) | **WRAP** |
| Easy-to-quality pace gap | Both paces persisted; nothing subtracts them | **JOIN** |
| Mood over the week | `mood_trend` analyzer | **WRAP** |
| Long-run share of the week | `longRunMiles ÷ totalMiles` — **both persisted, never divided** (`ASK-REGISTRY.md §I`) | **JOIN** |

**Unlogged mood days render as empty rings, never as neutral.** This is
`WEEK-TAB-APPLY.md §6.5` and it is a real regression risk: the real account logs
**1–5 moods per week**, not seven. A full mood row is a bug.

### (5) Notes for the training log

| Signal | Where | Status |
|---|---|---|
| Mood write | `training_logs.mood` (`20260125_create_training_logs.sql`) | **WRAP** |
| RPE | `20260611180000_add_rpe_to_training_logs.sql` | **WRAP** |
| Niggle write | `body_mentions` — written today only by the memo classifier | **BUILD** — needs a direct-write path |
| Fatigue marker | `extracted_data.fatigue` exists on memo rows; no typed column | **BUILD** |
| Free text | `training_logs.notes` / `workout_notes` (`20260810165247`) | **WRAP** |
| Voice alternative | `upload-voice-memo` → `process-training-memo` | **WRAP** — record it and every field above lands structured, for free |

**Section 07 is the only part of this build with real new write-path work.**
Everything else is reading things that already exist.

### Dark, and named as such

| | Why | Cost to fix |
|---|---|---|
| Fuelling / carbohydrate intake | Not captured anywhere — no column, no field, no classifier | A capture problem before it is a display problem. `WEEK-TAB-APPLY.md §4` removed it from the long-run ledger for exactly this reason. Note `extracted_data.fueling` exists as free text on memos — that is a start, not a source |
| Hills as a verdict | See (3) | BUILD |
| Proposals / plan diffs | No `proposed_actions` anywhere in the repo | Out of scope here. **Section 06 is prose, not a proposal engine** |

---

## 4 · The schema — `weekly-read.v1`

Shape follows `daily-read.v5` (sectioned, tappable refs, `cant_see`, `sources`,
`confidence`) with three additions. Full JSON schema belongs next to
`daily-read.v5.ts` as `prompts/weekly-read.v1.ts`.

```jsonc
{
  "week_start": "2026-08-11",       // ISO Monday
  "week_end":   "2026-08-17",
  "headline":   "Your biggest week of the block, and it held.",
  "eyebrow":    "Chasing 3:16 · 47 days out · off your 3:28",

  "sections": [{
    "key":   "the_week",            // closed enum, see below
    "label": "The week",
    "facts": [                      // NEW — rendered by the client, not the model
      { "key":"week_miles", "label":"Miles", "value":"68.4",
        "delta":"+4.1 vs W-1", "tone":"neutral",
        "provenance": { /* method + rows + coverage */ } }
    ],
    "series":   null,               // SeriesSpec, straight from the analyzer
    "body":     [ "prose", {"text":"the long run","workout_id":"<uuid>"} ],
    "caveat":   "Two of the six reps had no lap split recorded.",
    "coverage": { "sessionsUsed":12, "windowDays":7,
                  "missing":["no HR on 2 of 12 runs"], "confidence":"high" },
    "empty":    null                // EmptyState when coverage is insufficient
  }],

  "call":     { "body": "Hold the mileage where it is and …" },  // §06, nullable
  "capture":  { "prompt": "Anything to add before I file this?",
                "niggle_suggestions": ["right achilles"] },      // §07
  "cant_see": { "eyebrow": "NO OVERNIGHT DATA", "body": "…" },
  "sources":  { "workouts": [], "memos": [], "docs": [] },
  "confidence": { "level": "HIGH", "sub": "…" }
}
```

**Section keys (closed):** `the_week` · `key_sessions` · `how_you_felt` ·
`against_the_goal` · `where_the_miles_went` · `one_thing`.

### The three changes from v5 that matter

1. **`facts[]` is new, and the model does not write it.** In v5 the model wrote
   every number into prose. Here the analyzers emit `FactLine[]`, the client
   renders them, and the model narrates *on top of them*. This is the whole
   safety model — it is what makes `validateNarration()` possible, and it is why
   a number in the report can always name its source.
2. **`coverage` is per section, not per report.** A dark section is one section,
   not a hedged report.
3. **`provenance` rides on each fact.** The prototype's tap-through sheets are
   this field. Never populate it for a value that did not come from rows —
   `WEEK-TAB-APPLY.md §0` rule 2.

### Prompt design

Narration runs **per section**, not once for the whole report, so each call gets
only its own facts and cannot borrow a number from a neighbour.

Carried unchanged from `daily-read.v5`: the voice rules, the banned-word lists
(add **"we"** per `design-system/README.md`), niggles-surface-never-diagnose,
predictions-as-ranges-only, the citation rules, the three coaching modes, and
"drop any section you can't ground honestly."

Carried from `ask-narration.v1`: the facts-are-your-entire-evidence-base rule,
the SCOPE rule, respect-the-confidence, and `validateNarration()` on every
section.

New: a **length budget per section** (2–4 sentences), because a weekly report
is structurally invited to sprawl in a way the daily Read is not.

### Evals

`ask-narration.v1` is in the golden family and required cassettes before launch.
This is more athlete-facing than Ask and inherits that requirement: cassettes in
`_evals/cassettes/weekly-read/` and an entry in the golden list in
`.github/scripts/check_eval_coverage.py` before it ships unflagged. At minimum:
a full week, a thin week, a no-goal account, a `COACHED_MODE` account, a week
with a fourth niggle mention, and a week where the athlete logged nothing.

---

## 5 · Cadence

**Monday morning, in the athlete's own timezone, generated overnight.**

The pattern already exists twice and both are copyable:

- `20260615220000_daily_coaching_reads_cron.sql` — `enqueue_daily_reads()`,
  `SECURITY DEFINER`, reads vault secrets, iterates `athlete_state` LEFT JOIN
  `athlete_settings` for timezone, fires when the athlete's **local hour is 6**,
  per-row `BEGIN/EXCEPTION` so one bad IANA string can't kill the batch, and logs
  to `daily_read_dispatch_log`. **Copy this one** — it is the more careful of the two.
- `20260306100000_schedule_weekly_reports.sql` — a Monday `0 6 * * 1` schedule,
  but UTC-global, which means a 1am Monday report for some athletes.

`enqueue_weekly_reads()` = `enqueue_daily_reads()` with `EXTRACT(DOW) = 1` added
to the hour check. Same dispatch log pattern, new table.

Two behaviours worth deciding now:

- **A week with no runs still gets a Read.** A short, honest one. A silent
  Monday reads as the product being broken, not as the athlete having rested.
- **Regeneration.** If the athlete logs a Saturday run late on Monday, does the
  Read update? Proposal: **no** — the Read is dated and filed, and the athlete
  can pull-to-refresh to regenerate before they have filed §07. After they file,
  it is history.

Cost: one report per athlete per week, ~6 analyzer runs and ~6 short narration
calls. Check it against `20260813180100_llm_call_ledger_and_budget_guard.sql`
before enabling the cron — that guard exists and this is a new recurring spend.

---

## 6 · Where it lives

**Mounted at the top of the Week tab**, above section 01, as its narrative lede.

Week (tag 11, shipped 2026-08-19) already answers three weekly questions from
real rows, and `WEEK-TAB-APPLY.md §5` records that it has an unpaid IA cost and
should face the test that retired Coach: *does it get opened, and does it end?*

The Read answers both halves of that. It gives Week a reason to be opened on a
Monday, and it gives it an ending — §06 is the call, §07 is the athlete's reply.
The charts below it stop being the page and become the evidence.

Consequences:

- **No seventh tab.** The bar stays at six: Log · Train · Trends · Week · Ask · Sheet.
  `DripTab` is the only source of truth for that; `CLAUDE.md` was wrong about it
  once already and it cost an argument (`WEEK-TAB-APPLY.md §5`).
- **`CoachReadView.swift` and its seven primitives get reused, not rewritten.**
  `ReadProse`, `ReadSectionsView`, `EvidenceChip`, `SourcesPanel`,
  `ConfidenceBar`, `CantSeeBlock`, `DocDetailSheet` — ~2,000 lines already built
  for exactly this shape, currently rendering nothing. The v5 ref-tap routing
  (`workout_id` → detail, `niggle` → timeline) is already wired.
- **`WeekProvenance` is already the right type** for the fact tap-throughs. It
  was built for the charts; a `FactLine` provenance sheet is the same sheet.
- **Decide the merge with Ask.** `WEEK-TAB-APPLY.md §5` flags it: Ask is "pick
  any question from a closed enum", Week is "the three questions that matter,
  pre-answered", and the weekly Read is "the six that matter, pre-answered,
  every Monday." That is one product, and it currently occupies two tabs.
  Not a v1 blocker; it is the next IA conversation.

---

## 7 · Build order

Each step is shippable and useful on its own.

| # | Step | Size | Why here |
|---|---|---|---|
| 1 | **`WeekBuilder` tests** | small | `WEEK-TAB-APPLY.md §7.1` — it is pure and untested and the Read will sit on it. Do not stack a report on an untested builder |
| 2 | **The five JOINs** | ~50 LOC total | Weekly sleep aggregate, easy-to-quality gap, long-run share, memo-sleep × session execution, long-run progression. Cheapest analytics in the product's history, per `ASK-REGISTRY.md §0.2`. Each is a fact line the report can't currently print |
| 3 | **`weekly-read.v1` prompt + section narration** | medium | Per-section narration under `validateNarration()` |
| 4 | **`weekly-coaching-read` edge function** | medium | Analyzer fan-out → compose → persist. Model on `ask/index.ts`, not on `weekly-coaching-report/index.ts` |
| 5 | **`weekly_reads` table + RLS** | small | Follow `20260522130944_daily_coaching_reads.sql` |
| 6 | **iOS: mount in Week, reuse the Read primitives** | medium | Add a `FactLine` renderer + provenance sheet; everything else exists |
| 7 | **§07 capture + write path** | medium | The only real new write work. Chips → `training_logs.mood`, `body_mentions`, notes; voice → existing pipeline |
| 8 | **`enqueue_weekly_reads()` cron** | small | Copy `enqueue_daily_reads()`, add DOW |
| 9 | **Cassettes + golden-list entry** | medium | Required before it ships unflagged |
| 10 | **Confirm the biometrics producer is live for this account** | small | §3.1. Query `daily_biometrics` by source; fix the stale `WeekService.swift:461` string; correct `WEEK-TAB-APPLY.md §4` and `ASK-REGISTRY.md §0.1` while you are in there |

Steps 1–2 are worth doing **whether or not this ships**. They are debts the Week
tab already carries.

---

## 8 · Verify

Nothing here has been compiled or run. When it is built:

1. **The week total matches the actual week**, and tapping it lists the days that
   sum to it — including both runs on a doubled day, in clock order.
2. **A day run twice shows both runs.** The real account doubles most days.
3. **Mood: 1–5 filled rings in a normal week.** A full row means nil-handling
   regressed.
4. **Kill the analyzers one at a time** and confirm each section goes dark
   independently, in a sentence, with no chart and no dash.
5. **A brand-new account** gets a short honest Read, not an empty template.
6. **An account with no goal** drops §04 and the eyebrow, and does not invent a
   race.
7. **`COACHED_MODE`** suppresses §06 entirely and caps confidence at MEDIUM.
8. **Feed the narrator a fact list with a number removed** and confirm
   `validateNarration()` rejects the response rather than letting it through.
9. **No bare finish time anywhere.** Grep the output for a seconds-precision
   race prediction. That is a hard failure.
10. **§07 writes land.** Chip → `training_logs.mood`; niggle chip →
    `body_mentions` with the athlete's own words, not a canned string; the row
    shows up in next Monday's `niggle_timeline`.
11. **Filing §07 twice** doesn't double-write.
12. **Dynamic Type at max** — the four-column metric strip is the first thing to
    break, same as the long-run ledger.

---

## 9 · Open, and worth deciding before step 3

1. **The §0 trade.** Is one bounded training call per week the right amount of
   prescription? Everything above assumes yes.
2. **Two sleep sources, one section.** Measured duration and memo-stated hours
   answer different questions (§3.1). Does §03 show both, prefer measured and
   fall back, or keep them in separate fact lines? Whatever it does, a
   self-reported number must never be presented as a measurement — the prototype
   labels it twice, in the provenance method and in `can't see`.
3. **Regeneration** (see §5).
4. **What happens to the daily Read.** It has been unlinked since 2026-07-28. Is
   the weekly version its replacement, or does the daily one come back alongside?
   Two Reads with the same name is a naming problem before it is a product one.
5. **The Ask / Week / Read merge** (see §6).
6. **§07 when the athlete ignores it.** Three weeks of unanswered capture
   prompts is a signal about the prompt, not the athlete. Decide now what the
   product does about it, or it will quietly become furniture.

---

## 8 · Can it pull this? — verified against the registry, 2026-08-20

`_shared/analyzers/index.ts` registers **eleven** analyzers. Checked one by one
against what the prototype renders:

| § | Prototype needs | Analyzer | Status |
|---|---|---|---|
| 01 | Mileage, days, doubles, load, ramp | `load_balance` *"Am I ramping too fast?"* + `trends-timeline` day rows | **Registered** |
| 02 | Was that pace real, or the heat? | `heat_effect` — cool-weather equivalent, dew point, runs above threshold | **Registered** |
| 02 | Aerobic drift | `decoupling` *"Am I decoupling less?"* — recent vs baseline | **Registered** |
| 02 | HR efficiency | `efficiency` *"Metres per heartbeat"* — pace and HR at that effort | **Registered** |
| 02 | Compare to other sessions | `compare_session` — this session vs similar ones | **Registered** |
| 03 | Mood | `mood_trend` — most logged, most recent, direction | **Registered** |
| 03 | "4th flare-up in 2 months" | `niggle_timeline` — **days since last mentioned**, **spanning** | **Registered** |
| 03 | Sleep | `daily_biometrics` → `trends-timeline` (§3.1) | **Shipped, account-dependent** |
| 04 | On-track race time | `race_projection` + confidence tier | **Registered** |
| 04 | Work at goal pace | `race_pace_specificity` — share of running at goal pace | **Registered** |
| 05 | Pace distribution / LT trend | `zone_trend` *"Is my LT pace improving?"* | **Registered** |
| 05 | **Easy runs staying easy** | — | **NOT AN ANALYZER** |

**Two corrections to earlier drafts of this document.** `race_pace_specificity`
was listed as a JOIN in `ASK-REGISTRY.md §II/III`; it has since been built and
registered. And `hard_day_spacing`, listed there as missing, exists inside
`analyzers/loadBalance.ts`. The registry doc is behind the code in both places.

### 8.1 · The one real gap, and it is one of the five asks

The brief asked for *"easy runs staying easy."* There is no `easy_discipline`
analyzer. The logic exists in exactly one place — `athlete-state.ts:1673–1683`
— as a **pattern**, not an analyzer:

```ts
if (easyPct < 65 && totalMin > 90) {
  patterns.push({
    kind: "easy_discipline",
    statement: "Your easy days are creeping fast — not enough of the week is truly easy.",
    evidence: `only ${easyPct}% of the last 7d was easy-zone time`,
    confidence: "low",
  });
}
```

Patterns go into the **athlete-state prompt block** — free text handed to a
model. They are not `FactLine[]`, so `validateNarration()` cannot check prose
against them, and nothing renders them. Section 05 therefore either ships
without the athlete's own ask, or `easy_discipline` gets promoted to an
analyzer. It is a **WRAP** — the operands (`zone_pct_7d`, `minutes_7d`) are
already computed by `buildLoadDistribution`. Roughly 40 LOC and a registry line.

---

## 9 · The cheap things this design is NOT targeting

### 9.1 · Eight more patterns, already computed, invisible

`easy_discipline` is not alone. `athlete-state.ts` computes **nine** patterns,
each shaped `{ kind, statement, evidence, confidence }` — a written sentence
with its evidence already attached. All nine reach a prompt as context. **None
reach the athlete as UI.**

| Pattern | What it already knows | Why a weekly report wants it |
|---|---|---|
| `easy_discipline` | Easy share of the last 7d vs 65% | The brief's ask #4 |
| `easy_pace_trend` | Easy pace block-over-block at stable effort | Fitness gain that shows up nowhere else |
| `pacing_fade` | Fades within sessions | Section 02's whole question |
| `pacing_control` | Holds pace when it counts | The positive form of the same |
| `effort_mismatch` | RPE vs what the data says | "Felt terrible, ran fine" — the memo insight the brief asked for |
| `heat_sensitivity` | What heat costs **this** athlete | Makes `heat_effect` personal instead of generic |
| `down_week_response` | Whether down weeks actually restore | Directly decides next week |
| `niggle_load` | Niggles against load | The knee-flare ask, quantified |
| `life_load` | Life stress against training | Why a week went sideways |

**This is the cheapest content in the product.** The computation is done, the
sentence is written, the evidence string is built. What is missing is a
`FactLine` adapter and somewhere to render them. `down_week_response`,
`effort_mismatch` and `niggle_load` in particular answer the brief's memo-insight
ask more directly than anything in §02.

**The catch, and it is the same one as §0.** These `statement` strings are
pre-written prose, some of it prescriptive in tone. Promoting them to analyzers
means re-writing each statement to the voice rules in `design-system/README.md`
— no "we", observation not prescription — and deriving the sentence from the
numbers rather than shipping the canned string. Otherwise the report inherits
nine sentences nobody reviewed.

### 9.2 · Still genuinely one line of arithmetic

Verified absent from `_shared/` today:

| Analytic | Operands, both persisted | Where |
|---|---|---|
| `long_run_share` | `longRunMiles` ÷ `totalMiles` — computed, **never divided** | `weeklyAnalytics.ts`, `dataAnalysis.ts` |
| `polarization` | `zone_pct_7d` exists; no distribution index over minutes | `buildLoadDistribution` |
| `consistency_streak` | Run dates are all there; nothing counts them | `training_logs` |

`long_run_share` is the one to do first — it is a division, and the long run is
the single most decision-relevant session in a marathon block.

### 9.3 · Deliberately still not targeted

- **Fuelling.** No column, no field, no classifier. Capture problem before a
  display problem. `WeekModels.LongRun.fuel` is flagged as fixture-only.
- **Sleep stages / efficiency / score.** Tier-0 in `recovery-trend-v2 §7.4` —
  *"capturing them invites someone to use them."* Leave it.
- **The proposal engine.** No `proposed_actions` anywhere in the repo. §06
  makes one call in prose; it does not propose plan diffs.

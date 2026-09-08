# Promoting four patterns to analyzers

**Authored:** 2026-08-20 · spec only, **nothing applied to the tree**
**Companion:** `WEEKLY-READ-APPLY.md` §8.1 and §9.1 — this is that gap, specced
**Touches:** `_shared/analyzers/` (4 new files, 2 edits), `athlete-state.ts` (0 edits)

---

## 0 · The thing to understand before writing any code

**Promoting a pattern to an analyzer is not a wrap. It is an inversion.**

Every one of the nine patterns in `athlete-state.ts` is **threshold-gated and
one-sided**. It exists to answer *"is this worth mentioning to the model?"*, so
it fires only when the answer is yes, and stays silent otherwise. Read the
actual gates:

| Pattern | Fires when | Never fires when |
|---|---|---|
| `easy_discipline` | `easyPct < 65 && totalMin > 90` | Your easy days **are** easy |
| `down_week_response` | volume dropped ≥20% **and** ≥60% of reps held pace | The down week did **not** land |
| `effort_mismatch` | ≥2 of last ≥2 reads are "harder than it looks" | Efforts feel **easier** than they look |
| `niggle_load` | ≥1 body mention followed a volume spike | Nothing flagged |

An analyzer cannot behave this way. `FactLine[]` is what the UI renders and
what `narration-guard` licenses; an analyzer that returns no facts on a good
week produces a card that says nothing, and **its silence is unreadable** — the
athlete cannot tell "your easy days are fine" from "not enough data yet."

Worse in a weekly report specifically: a section that appears **only when the
news is bad** is a section the athlete learns to dread and eventually stops
reading. That is the opposite of the ritual §07 is trying to build.

**The rule for all four promotions:**

> The analyzer answers the question **every time**, with a number.
> `FactTone` carries the verdict — `good` / `neutral` / `watch`.
> The pattern's threshold becomes the **tone boundary**, not the render gate.
> The only thing that suppresses a card is *insufficient coverage*, and that
> renders an `EmptyState` that says what would fix it.

`FactTone` has no `"bad"` value, deliberately (`types.ts`). `watch` is the
ceiling. Keep it there.

### 0.1 · The canned sentences cannot ship

Each pattern carries a pre-written `statement`:

> `"Your easy days are creeping fast — not enough of the week is truly easy."`

Three problems. It is prescriptive in flavour; it is a fixed string that cannot
vary with the number; and it was written for a prompt, not for the athlete.
**Do not carry these strings across.** The analyzer emits facts; Layer 2
narrates them under `narration-guard`, in the voice rules from
`design-system/README.md` — no "we", observation not prescription. The
`statement` field is useful only as a hint about what the pattern was trying to
say.

---

## 1 · Two seams to open first

### 1.1 · The typed reader selects neither column it needs

`athlete_state` persists both as `jsonb` — `20260612120000_athlete_state_v2_satellites.sql`:

```sql
ADD COLUMN IF NOT EXISTS load_distribution jsonb,
ADD COLUMN IF NOT EXISTS patterns jsonb,
```

But `analyzers/athleteState.ts` does not ask for them:

```ts
const STATE_COLUMNS =
  "goal_race, goal_time_seconds, last_mood, mood_trend, data_depth, fitness_prediction, fitness_signal, niggle_recurrence, active_goals, confirmed_races, pace_zones";
```

**Edit 1** — add both, and type them:

```ts
export interface LoadDistribution {
  zone_pct_7d?: { easy?: number; moderate?: number; threshold?: number; hard?: number } | null;
  minutes_7d?: { easy?: number; moderate?: number; threshold?: number; hard?: number } | null;
  load_trend?: string | null;
}

/** As written by `athlete-state.ts`. `confidence` uses the PATTERN vocabulary
 *  ("medium"), not the analyzer one ("moderate"). See §1.2. */
export interface StatePattern {
  kind?: string | null;
  statement?: string | null;
  evidence?: string | null;
  confidence?: string | null;
}

export interface AthleteStateRow {
  // …existing fields…
  load_distribution: LoadDistribution | null;
  patterns: StatePattern[] | null;
}

const STATE_COLUMNS =
  "goal_race, goal_time_seconds, last_mood, mood_trend, data_depth, " +
  "fitness_prediction, fitness_signal, niggle_recurrence, active_goals, " +
  "confirmed_races, pace_zones, load_distribution, patterns";
```

Adding columns to this select is safe — every field in the reader is already
"optional and defensively parsed," per its own header, because state is rebuilt
asynchronously and any field can legitimately be null.

### 1.2 · The confidence vocabularies do not match

| | Values |
|---|---|
| `types.ts` `Confidence` | `high` · **`moderate`** · `low` |
| Pattern `confidence` | `high` · **`medium`** · `low` |

A pattern confidence assigned straight to `Coverage.confidence` is a type error
at best and a silent wrong tier at worst. **Edit 2**, in `athleteState.ts`:

```ts
/** Pattern vocabulary → analyzer vocabulary. "medium" is the only divergence,
 *  and it is the most common value the builders emit, so this is not an edge
 *  case — it is the normal path. */
export function confidenceFromPattern(v: string | null | undefined): Confidence {
  if (v === "high") return "high";
  if (v === "medium" || v === "moderate") return "moderate";
  return "low";
}
```

Prefer `confidenceFromSamples()` where the analyzer counts its own rows. Use
this only where the pattern is the sole source.

---

## 2 · `easy_discipline` — the one the brief actually asked for

**Do not read this one from `load_distribution`.** That field is a 7-day
snapshot, so it can state this week and nothing else, and a weekly report's
whole job is comparison. `workout_features` already carries the four
zone-seconds columns per workout, `FEATURE_COLUMNS` already selects them, and
`fetchFeaturesSince` and `weekStart` already exist in `data.ts`. So the real
version — current value **and** an eight-week trend — needs **no new fetch
helper**.

```ts
/**
 * `easy_discipline` — "Are my easy days actually easy?"
 *
 * Principle II (Intensity distribution). Easy-zone share of weekly running
 * time, this week against the athlete's own recent weeks.
 *
 * WHY THIS IS NOT A WRAP OF THE PATTERN. `athlete-state.ts:1673` fires only
 * below 65%, so it can say "creeping fast" and can never say "these are easy."
 * A weekly section that renders only bad news teaches the athlete to skip it.
 * This answers every week; the 65% line becomes the tone boundary.
 *
 * WHY TIME, NOT MILES. An easy mile takes longer than a threshold mile, so a
 * share computed on distance flatters a week that was mostly quality. Zone
 * SECONDS are what `workout_features` stores and what the 65% threshold in
 * `athlete-state.ts` was calibrated against.
 */

import { daysAgoISO, fetchFeaturesSince, weekStart } from "./data.ts";
import {
  type Analyzer, type AnalyzerCtx, type AnalyzerParams, type AnalyzerResult,
  type FactLine, type SeriesPoint, confidenceFromSamples, fmtPctDelta,
} from "./types.ts";

const DEFAULT_WINDOW_DAYS = 56;   // 8 weeks — enough for a trend, short enough to be current
const EASY_FLOOR_PCT = 65;        // the boundary from athlete-state.ts:1677
const MIN_WEEKLY_MINUTES = 90;    // same guard: a 40-minute week has no distribution
const MIN_WEEKS = 2;

export const easyDiscipline: Analyzer = {
  id: "easy_discipline",
  label: "Are my easy days actually easy?",
  group: "mix",
  params: {
    window_days: {
      type: "number", min: 14, max: 180, optional: true,
      describe: "How far back to look. Defaults to 56 days.",
    },
  },

  async run(params: AnalyzerParams, ctx: AnalyzerCtx): Promise<AnalyzerResult> {
    const windowDays = Number(params.window_days ?? DEFAULT_WINDOW_DAYS);
    const features = await fetchFeaturesSince(
      ctx.supabase, ctx.userId, daysAgoISO(ctx.now, windowDays),
    );

    // Bucket zone-seconds into ISO weeks.
    const weeks = new Map<string, { easy: number; total: number; runs: number }>();
    let missingZones = 0;

    for (const f of features) {
      const easy = f.easy_seconds ?? 0;
      const total = easy + (f.moderate_seconds ?? 0)
                  + (f.threshold_seconds ?? 0) + (f.hard_seconds ?? 0);
      if (total <= 0) { missingZones++; continue; }
      const key = weekStart(new Date(f.workout_date)).toISOString().slice(0, 10);
      const w = weeks.get(key) ?? { easy: 0, total: 0, runs: 0 };
      w.easy += easy; w.total += total; w.runs++;
      weeks.set(key, w);
    }

    const ordered = [...weeks.entries()]
      .sort((a, b) => a[0].localeCompare(b[0]))
      .filter(([, w]) => w.total / 60 >= MIN_WEEKLY_MINUTES);

    if (ordered.length < MIN_WEEKS) {
      return {
        facts: [],
        coverage: {
          sessionsUsed: features.length, windowDays,
          missing: missingZones > 0
            ? [`no pace breakdown on ${missingZones} of ${features.length} runs`] : [],
          confidence: "low",
        },
        related: ["load_balance", "zone_trend"],
        empty: {
          eyebrow: "Not enough weeks yet",
          nudge:
            "This compares a week's easy share against your other weeks. Two full weeks of runs with pace data make it answerable.",
          cta: null,
        },
      };
    }

    const pct = (w: { easy: number; total: number }) =>
      Math.round((w.easy / w.total) * 100);

    const [, current] = ordered[ordered.length - 1];
    const priorWeeks = ordered.slice(0, -1).map(([, w]) => pct(w));
    const currentPct = pct(current);
    const priorMean = priorWeeks.length
      ? Math.round(priorWeeks.reduce((s, x) => s + x, 0) / priorWeeks.length)
      : null;

    // The pattern's threshold becomes the TONE boundary — never a render gate.
    const tone = currentPct >= EASY_FLOOR_PCT ? "good" : "watch";

    const facts: FactLine[] = [
      {
        key: "easy_share_current",
        label: "Easy share · this week",
        value: String(currentPct), unit: "%",
        delta: priorMean != null ? fmtPctDelta(currentPct - priorMean) : null,
        tone,
      },
      {
        key: "easy_share_baseline",
        label: `Your own average · prior ${priorWeeks.length} weeks`,
        value: priorMean != null ? String(priorMean) : "—", unit: "%",
        tone: "neutral",
      },
      {
        key: "easy_minutes_current",
        label: "Easy minutes this week",
        value: String(Math.round(current.easy / 60)), unit: "min",
        tone: "neutral",
      },
      {
        key: "quality_minutes_current",
        label: "Everything else",
        value: String(Math.round((current.total - current.easy) / 60)), unit: "min",
        tone: "neutral",
      },
    ];

    const points: SeriesPoint[] = ordered.map(([k, w]) => ({
      x: k, y: pct(w), label: `${w.runs} runs`,
    }));

    const missing: string[] = [];
    if (missingZones > 0) {
      missing.push(`no pace breakdown on ${missingZones} of ${features.length} runs`);
    }
    if (ordered.length < 4) {
      missing.push(`${ordered.length} weeks of history, so the baseline is thin`);
    }

    return {
      facts,
      series: {
        kind: "bar", unit: "percent",
        band: [EASY_FLOOR_PCT, 100],   // the target zone, drawn behind the bars
        points,
      },
      coverage: {
        sessionsUsed: features.length - missingZones,
        windowDays,
        missing,
        confidence: confidenceFromSamples(ordered.length, { high: 6, moderate: 3 }),
      },
      related: ["zone_trend", "load_balance", "race_pace_specificity"],
    };
  },
};
```

Signatures verified against `data.ts`: `fetchFeaturesSince(supabase, userId,
sinceISO, limit = 400)` returns `FeatureRow[]` **newest-first** (hence the
explicit sort above), and `weekStart(d)` returns Monday 00:00 UTC. The default
`limit` of 400 is far above an 8-week window for any athlete, so it is left
alone.

### 2.0 · CORRECTION — which pace chart, and the answer is "not the chart"

**Raised 2026-08-20:** *"for zone, all of it should be based on the pace chart —
what is your pace chart that you are referencing?"*

**Honest answer: the analyzer in §2 does not reference the pace chart.** It reads
`workout_features.{easy,moderate,threshold,hard}_seconds`, which sit **two lossy
transformations downstream of it.** There are four representations in the repo
and they do not agree.

#### The canonical chart — `_shared/pace-engine.ts`

`get-pace-zones/index.ts` calls it "THE single endpoint every consumer calls…
there is no other place that does pace math." It is a hybrid:

| | Zone | Definition |
|---|---|---|
| **Ranges** (`PaceRange`, fast + slow bound) | recovery | `< 70% MP speed` |
| | easy | `70–80% MP speed` |
| | moderate | `80–90% MP speed` |
| | steady | `90–100% MP speed` |
| **Anchors** (`PaceAnchor`, single pace) | mp · hm · tenK · fiveK · threeK · mile | race-pace equivalents |

#### Transformation 1 — segmentation discards the ranges

`workoutSegmentation.buildZoneAnchors()` flattens all ten zones to **single
anchor paces**, then `paceToZone()` classifies by **midpoint cutoffs between
consecutive anchors**. The chart's explicit boundaries (70/80/90/100% of MP
speed) are not used; approximate midpoints are re-derived instead. Its own
comment concedes the cost:

> *"Aerobic boundaries (steady/moderate/easy) are inherently fuzzy (those zones
> ship as ±5% ranges); the precise quality boundaries are what matter."*

Defensible for quality work. But **easy-day discipline is entirely an aerobic
question**, and it is precisely the aerobic boundaries that were softened.

#### Transformation 2 — ten zones roll up into four buckets

`workoutSegmentation.ts:539-543`:

| Chart zone | Bucket |
|---|---|
| mile · 3k · 5k · 10k | `hard_seconds` |
| **hmp** | `threshold_seconds` |
| **mp** · steady · moderate | `moderate_seconds` |
| easy · recovery | `easy_seconds` |

Two real losses:

- **Marathon pace is filed as "moderate."** A 6-mile MP block inside a long run
  — the most race-specific work a marathoner does — is bucketed identically to a
  steady run. In a marathon build that is the single most important distinction
  in the week, and the field my analyzer reads cannot see it.
- **Easy and recovery are merged.** Recovery jogging and easy running become one
  number, so "are my easy days easy" cannot distinguish a genuinely easy run from
  a shuffle.

#### And a fourth definition, stale, on the live table

`20260318120000_create_workout_features.sql:20-23` documents the columns as:

```sql
easy_seconds       -- below 75% MP velocity
moderate_seconds   -- 75-85% MP velocity
threshold_seconds  -- 85-95% MP velocity
hard_seconds       -- above 95% MP velocity
```

That matches **neither** the engine (70/80/90/100%) **nor** the rollup actually
running in `workoutSegmentation.ts`. It describes an implementation that no
longer exists. Anyone reasoning from the schema comment — which is the natural
first place to look — reasons from a system that was replaced. **Fix the comment
regardless of whether any of this ships.**

#### What `easy_discipline` should actually do

Go to the laps and classify against the athlete's own chart, exactly as the two
analyzers that already need per-session truth do. From `analyzers/athleteState.ts`:

> *"The exceptions are `zone_trend` and `compare_session`, which need
> per-session detail that state doesn't carry, so they go to the laps."*

`easy_discipline` is a third exception. `fetchLapsByWorkout` and `LAP_COLUMNS`
exist in `data.ts`; `ctx.zones` is already on `AnalyzerCtx`. So:

- classify each lap with the **chart's own `easy` range** (`paceFast` / `paceSlow`
  bounds from `pace-engine.ts`), not a midpoint cutoff — "was this run inside the
  easy range" is a range question, which is what the range zones are for;
- keep `easy` and `recovery` distinct, and report both;
- **use `heat_adjusted_pace_sec_per_mile` where present.** `LAP_COLUMNS` already
  carries it. An easy run in 26°C and high dew point drifts slower in raw pace,
  and judging easy discipline on raw pace on a hot week penalises the athlete for
  the weather. The Week tab already decides band membership on adjusted pace —
  this must match it or two surfaces will disagree about the same run.

That is a **BUILD**, not the WRAP §2 assumed — a real module against laps rather
than a sum over four columns. It is still small, and it is the only version that
answers the question the athlete actually asked.

**Revised recommendation:** ship §4 `long_run_share` first (unaffected — it is
miles, not zones), and treat `easy_discipline` as the second, larger piece.

### 2.1 · CORRECTION — the analyzer above is wrong, and so is the pattern

**Raised 2026-08-20:** *"do you know not to confuse doubles with warmups and
cooldowns from the same workout? Like 6am — 2mi up, 6mi tempo, 2mi cd. 5pm — 5mi
easy."*

Three different things share one shape, and they must not be conflated:

| | What it is | Correct handling |
|---|---|---|
| **A structured session** | 2 up / 6 tempo / 2 down, 6–8am | **One** 10-mile run |
| **A double** | that session + 5mi easy at 5pm | **Two** runs, 15 miles |
| **A split-watch session** | WU, tempo and CD stopped/started separately | Three activities, **one** session |

**What the repo gets right.** One Strava or HealthKit activity becomes one
`training_logs` row and one `workout_features` row; laps live separately in
`running_workout_laps`. So the structured session is correctly one 10-mile run,
and the tempo does not become its own "workout".

**What it gets wrong, and what I got wrong.** Zone classification is **purely
pace-based**. `workoutSegmentation.ts:68` says so outright:

> *"Zones at or faster than MP count as work. Anything slower is aerobic
> background (easy/steady running, **warmup, cooldown**, float)."*

There is no warmup or cooldown label anywhere in segmentation. So the 2 up and
2 down land in `easy_seconds` — inside a quality session. Run the example:

| | Easy-zone | Threshold |
|---|---|---|
| 6am · 2 up + 6 tempo + 2 down | ~30 min (the 4 easy miles) | ~36 min |
| 5pm · 5mi easy | ~40 min | — |
| **Week-fragment total** | **70 min** | **36 min** |

Easy share = 70 / 106 = **66%** → above the 65% line → the card says
*"your easy days are easy."*

**But the only run that answers the question is the 5pm.** The 4 warmup and
cooldown miles are part of a hard day. And the failure is not merely noisy, it
is **backwards**:

> **The more tempo work the athlete does, the more warmup and cooldown miles
> they accumulate, and the higher their "easy share" climbs.** A week of heavy
> quality scores *better* on easy discipline than a week of pure easy running.

`athlete-state.ts:1673` has the identical bug — it reads `zone_pct_7d.easy`,
which is all-seconds across all sessions. **This correction applies to the
existing pattern too, not just to the promotion.**

#### The fix: compute at session level, and split the question in two

They were always two questions, and `zone_pct_7d` answers only the second:

1. **Easy-day discipline** — *"are my easy runs actually easy?"* Restrict to
   sessions whose kind is `easy` or `recovery`, then measure the easy-zone share
   **of those sessions only**. A warmup can never inflate it, because quality
   sessions are excluded before the ratio is taken.
2. **Weekly intensity distribution** — *"is the 80/20 mix right?"* All seconds,
   all sessions, warmups included. This one is correct as-is and belongs to
   `zone_trend` / a future `polarization`, not here.

`compute-workout-features/index.ts:282` already writes what is needed:

```ts
workout_type: seg.workoutKind,   // long_run | intervals | tempo | fartlek
                                 // | easy | recovery | race | progression | threshold
```

**Seam edit 3.** `workout_type` is **not** in `FEATURE_COLUMNS` (`data.ts:26`)
— `workout_structure` is there, `workout_type` is not. Add it, and add it to
`FeatureRow`. That is the whole unlock.

Then in `run()`, before bucketing:

```ts
const EASY_KINDS = new Set(["easy", "recovery"]);

for (const f of features) {
  // Easy-day discipline asks about easy RUNS. A tempo session's warmup and
  // cooldown are easy-PACED but they are part of a hard day, and counting
  // them inverts the metric: more quality work would raise the easy share.
  // Quality sessions are excluded here and measured by `zone_trend` instead.
  if (!EASY_KINDS.has((f.workout_type ?? "").toLowerCase())) continue;
  // …existing bucketing…
}
```

and emit a second fact so the exclusion is visible rather than silent:

```ts
{
  key: "quality_sessions_excluded",
  label: "Quality sessions this week (measured separately)",
  value: String(qualityCount),
  tone: "neutral",
}
```

The 65% threshold **must be recalibrated after this change.** It was tuned
against an all-sessions denominator that included every warmup and cooldown;
against an easy-runs-only denominator the honest figure is far higher — easy
runs should be near-entirely easy. Do not carry 65% across. This is a second
reason to drop the target band and compare the athlete to their own baseline.

#### The third case, which is a separate gap

If the watch is stopped between warmup, tempo and cooldown, three activities
arrive for one session. `LogDedup.swift:83-88` recognises the shape — its own
comment reads *"WU + CD pattern, doubles days, etc. Keep them all"* — and
correctly refuses to delete them. But **nothing merges them back into one
session.** I found no adjacency-based session merge on the ingest path.

Consequences: run count inflates; the 6mi tempo row carries ~zero easy seconds
while the 2mi warmup row is 100% easy; and session-level analyzers see three
sessions where the athlete ran one. With the `EASY_KINDS` filter above, a
standalone 2mi warmup would likely classify as `easy` and be **counted as an
easy run** — which is wrong in the new way.

**This needs a decision before `easy_discipline` ships.** The cheap guard: treat
same-day activities separated by less than ~20 minutes of clock gap as one
session for analysis. The honest interim: exclude runs under ~2.5 miles that sit
adjacent to a quality session, and name the exclusion in `coverage.missing`.
Neither is free, and it belongs on the list in `ACCURACY-RISK.md §5` beside the
dedup fix — it is the same class of problem.

**One judgement call worth reviewing.** `band: [EASY_FLOOR_PCT, 100]` draws 65%
as a target. That is one number from one line of `athlete-state.ts`, calibrated
against nothing recorded in the repo. It is defensible as a widely-used
polarised-training heuristic, but it is **not this athlete's number** and the
report should not imply it is. Either keep the band and label it as a general
guide, or drop it and let the athlete's own eight-week mean be the only
reference line. **I would drop it** — the comparison that matters in every other
section of this app is athlete-against-self.

---

## 3 · The other three

These three depend on `lifeContext`, `recentBlocks` and `fadeVals`, all computed
*inside* the `athlete-state.ts` builder and none exposed as standalone tables.
Re-deriving them would be a second implementation of a number the Daily Read
already shows — exactly what `analyzers/athleteState.ts` warns against:

> Reading state means **Ask can never disagree with the Trends tile.**

So these three read `patterns` from state. That is cheap, and it caps what they
can honestly do — **they inherit the one-sidedness of §0.** Handle it explicitly:

```ts
/** Find a pattern by kind. Absence is NOT evidence of the good case — these
 *  gates are one-sided (§0), so a missing pattern means "the builder had
 *  nothing to say", which is not the same as "the answer is fine". */
function findPattern(state: AthleteStateRow | null, kind: string): StatePattern | null {
  return (state?.patterns ?? []).find((p) => p?.kind === kind) ?? null;
}
```

### 3.1 · `niggle_load` — the knee-flare ask, quantified

The **strongest of the three**, because it does not depend on state's gate: the
underlying rows are in `body_mentions`, which `niggle_timeline` already reads
and which carries `body_area`, `date` and `volume_context`. Build this one from
rows, not from the pattern — count mentions, count how many followed a volume
jump, and emit both. It answers every week, including "nothing flagged," which
is a genuinely good week worth stating out loud.

Facts: mentions this week · mentions in the last 8 weeks · how many followed a
volume jump · days since the most recent. `related: ["niggle_timeline", "load_balance"]`.

Tone: `good` at zero mentions, `neutral` at one, `watch` at recurrence.
**Never `watch` on severity** — hard rule #2. Recurrence is a count, not a
diagnosis.

### 3.2 · `effort_mismatch` — "felt harder than it looks"

Reads `lifeContext.felt_vs_looked`, which lives only inside the builder, so this
one **must** go through `patterns`. Two-sided version: emit the count of
"harder than it looks" reads *and* the count of "easier", out of the total with
an effort read. Both directions are informative; the pattern only ever reports
one.

If `felt_vs_looked` is empty, the `EmptyState` nudge is concrete and worth
writing well: an effort read comes from what you say after a run, so this is one
the athlete can switch on themselves.

### 3.3 · `down_week_response` — the one to build last

The most useful of the four for a weekly report and the **most expensive to do
honestly**. Its gate requires a ≥20% volume drop *and* rep-fade data, so it can
only speak in the specific week after a down week. Every other week it must say
"no down week in the window," which is correct but is not a weekly section.

**Recommendation: do not give this one a card.** Make it a *conditional insert*
in §01 — it renders the week after a down week and is absent otherwise, which is
honest because the athlete can see from their own mileage why it is not there.
That is the one case where absence is readable, and it is the exception that
proves §0's rule.

---

## 4 · `long_run_share` — do this one first anyway

Not a pattern promotion, but the cheapest analytic in the product and the most
decision-relevant session in a marathon block. `longRunMiles` and `totalMiles`
are both computed in `weeklyAnalytics.ts` and **never divided**. One analyzer,
one division, a weekly series, no new fetch. Roughly 30 lines.

---

## 5 · Build order

| # | Step | Why here |
|---|---|---|
| 1 | Edits 1 + 2 in `athleteState.ts` (§1) | Everything else needs the columns and the mapper |
| 2 | `long_run_share` (§4) | Cheapest; proves the seam before anything harder |
| 3 | **Seam edit 3** — `workout_type` into `FEATURE_COLUMNS` (§2.1) | `easy_discipline` is wrong without it |
| 3a | **Fix the stale zone comment** on `20260318120000_create_workout_features.sql` (§2.0) | It documents a replaced system; do it whatever else happens |
| 3b | `easy_discipline` (§2, **as corrected by §2.1**) | The brief's ask; no state dependency; real series |
| 4 | `niggle_load` (§3.1) | Row-derived, two-sided, answers every week |
| 5 | `effort_mismatch` (§3.2) | State-dependent; accept the cap |
| 6 | `down_week_response` (§3.3) | As a §01 insert, not a card |
| 7 | Register in `ANALYZERS` + rewrite `statement` strings to voice (§0.1) | — |

Each new analyzer needs a registry line in `_shared/analyzers/index.ts` under
its group comment (`easy_discipline` and `long_run_share` under a new `// Mix`
heading — `mix` is already in the `AnalyzerGroup` union and currently unused by
any registered analyzer).

## 6 · Tests

`analyzers.test.ts` is the existing home. Per analyzer, at minimum:

0. **A tempo session with a warmup and cooldown** — one 10-mile session, 4 of
   its miles easy-paced, plus a genuine 5-mile easy run. Asserts the warmup and
   cooldown are **excluded** and the ratio reflects the easy run alone (§2.1).
   **This is the test that catches the inverted metric. Write it first.**
1. **A good week** — easy share above the line. Asserts facts render and tone is
   `good`. **This is the case the pattern could never produce, and the reason
   for the whole exercise.**
2. **A thin week** — below `MIN_WEEKLY_MINUTES`. Asserts `EmptyState`, not zeros.
3. **Missing zone data** — features with all four zone columns null. Asserts the
   run is excluded *and* named in `coverage.missing`.
4. **One week of history** — asserts `EmptyState`, never a baseline of one.
5. **`factLinesToStrings` round-trip** — every number the card shows appears in
   the licensed token list, so narration cannot be rejected for speaking a
   number the UI is displaying.

## 7 · Verify

1. `deno test` in `supabase/functions/`.
2. Ask chip rail shows the new questions in the `mix` group.
3. **A week with genuinely easy easy days renders a `good` card, not silence.**
4. An account with no `workout_features` rows renders nudges, never `0%`.
5. `narration-guard` rejects a narration that invents a percentage — confirm by
   temporarily hand-editing a fact value and watching the response fail.
6. Confirm no analyzer emits the canned `statement` string verbatim (§0.1).

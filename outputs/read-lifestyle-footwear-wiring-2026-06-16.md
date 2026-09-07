# Wiring lifestyle + footwear into The Read — implementation spec

**Date:** 2026-06-16
**Status:** Proposed
**Touches:** `supabase/functions/_shared/athlete-state.ts`,
`supabase/functions/_shared/prompts/daily-read.v5.ts`,
`supabase/functions/_evals/cassettes/daily-read.v5/`
**Related:** `coach-read-effectiveness-plan-2026-06-12.md`,
`athlete-state-v2-coach-grade-2026-06-12.md`,
`the-read-redesign-plan-2026-06-13.md`

## The finding (this is not what we thought)

The last review framed lifestyle (sleep / work / family) and footwear as
*missing data* — streams The Read couldn't see because nobody captured them.
That's wrong. They are **captured at ingestion and dropped on the read side.**

`process-training-memo.v1.ts` already parses every voice memo into a structured
`extracted_data` object and writes it to `training_logs.extracted_data`
(`process-training-memo/index.ts:559`). That object includes:

| Field | Type | Your priority-list bucket |
|---|---|---|
| `shoe` | string | Footwear |
| `sleep_quality` / `sleep_hours` | enum / number | Lifestyle |
| `work_stress` | low/moderate/high | Lifestyle |
| `life_stress` | low/moderate/high (family, money, general load) | Lifestyle |
| `travel` | string | Lifestyle / training issues |
| `fatigue` | fresh/normal/tired/wiped | Training issues (worn down) |
| `soreness` | string[] (athlete's words) | Niggles / training issues |
| `illness` | string | Training issues |
| `motivation` | high/normal/low | Mood |
| `weather` / `terrain` / `rpe` / `felt_vs_looked` | — | Training issues |

`rebuildAthleteState` selects the training-log columns it needs at
`athlete-state.ts:488` — and `extracted_data` is **not in the select list.**
So the column is populated on every processed memo and then never read. The
fix is a SELECT change plus assembly + rendering. No new ingestion, no new
tables, no migration.

This is the single highest-leverage change available to The Read right now:
the qualitative half of "what a pace actually means" is already sitting in the
database.

## Goal

Surface, as structured signal in `=== ATHLETE STATE ===`:

1. **Per-run life context** — sleep, fatigue, stress, illness, travel attached
   to the runs they belong to, so the model can read a slow tempo as "5 hours of
   sleep and a work trip," not lost fitness.
2. **A short life-context rollup** — the recurring off-the-run stressors over the
   block, so "How you felt" can name the pattern a coach would.
3. **Footwear** — which shoe each run was in, plus rough per-shoe mileage, so a
   niggle that tracks a shoe surfaces as a thread (surface only — never "your
   shoes caused this").

## Changes

### 1. Pull the column (`athlete-state.ts:~488`)

Add `extracted_data` to the recent-logs select in `rebuildAthleteState`:

```ts
.select("id, workout_date, workout_distance_miles, workout_duration_minutes, workout_type, workout_pace_per_mile, mood, cleaned_notes, notes, workout_notes, source, parsed_structure, pace_segments, extracted_data")
```

`extracted_data` is `Record<string, unknown> | null`. Treat every field as
optional and defensively typed — memos routinely return partial objects, and the
field set will grow.

### 2. Attach per-run life context to `recent_workouts`

Extend the `recent_workouts[]` item in the `AthleteState` interface
(`athlete-state.ts:125`) with a single optional bag rather than ten loose fields,
to keep the prompt render tight:

```ts
recent_workouts: Array<{
  // ...existing fields...
  /** Self-reported context parsed from the memo (extracted_data). All optional. */
  life?: {
    sleep_hours: number | null;
    sleep_quality: string | null;   // good | ok | poor
    fatigue: string | null;          // fresh | normal | tired | wiped
    work_stress: string | null;      // low | moderate | high
    life_stress: string | null;      // low | moderate | high
    travel: string | null;
    illness: string | null;
    motivation: string | null;
    felt_vs_looked: string | null;
  } | null;
  /** Shoe the athlete named for this run, verbatim. */
  shoe?: string | null;
}>
```

Populate it in the `recent_workouts` map from `log.extracted_data`. Only set
`life` when at least one field is non-null (avoid an empty bag on every run).

### 3. New rollup fields on `AthleteState`

Add two computed satellites next to the other v2 satellites:

```ts
/**
 * Off-the-run life context over the recent block, rolled up from
 * training_logs.extracted_data. Surface the PATTERN ("two high-life-stress
 * weeks, sleep down"), never moralize. Null when no memo carried life signal.
 */
life_context: {
  window_days: number;
  avg_sleep_hours: number | null;        // mean of non-null sleep_hours
  low_sleep_nights: number;              // count sleep_hours < 6 OR quality "poor"
  high_stress_days: number;              // count work_stress|life_stress == "high"
  travel_days: number;                   // count non-null travel
  illness_days: number;                  // count non-null illness
  recent_flags: string[];                // e.g. ["work trip Tue–Thu", "5h sleep before Sat long run"]
} | null;

/**
 * Footwear seen in recent memos with rough mileage. Self-reported only —
 * sum of workout_distance_miles grouped by extracted_data.shoe over the
 * lookback. NOT authoritative shoe-odometer data. Empty when no shoe named.
 */
footwear: Array<{
  shoe: string;
  runs: number;
  miles_in_window: number;
  first_seen: string;   // YYYY-MM-DD
  last_seen: string;
}>;
```

Compute both in `rebuildAthleteState` from the same recent-logs array already in
memory — no extra query. `recent_flags` should be at most 3 short strings,
generated by simple rules (a high-stress run paired with a quality session; a
sub-6h-sleep night before the long run; a travel window overlapping the week).
Keep the rules dumb and legible; the model does the narration.

### 4. Render in `stateToPromptContext`

Two new blocks. Place **Life context** right after the existing "Recent vibe"
mood block (`athlete-state.ts:~2318`) so felt-signal sits together, and
**Footwear** after the Conditions block (it's the same "don't misread a number"
family).

```
Life context (self-reported — calibrate what paces MEAN; surface the pattern, never moralize):
  Avg sleep ~6.2h · 2 low-sleep nights · 3 high-stress days · work trip Tue–Thu
  → Read a flat session against this before reading it as fitness. Do not lecture about sleep or stress.

Footwear (self-reported shoe mentions — surface a niggle↔shoe thread, never claim causation):
  Vaporfly: 4 runs, 38mi (May 02 → Jun 14)
  Daily trainer: 9 runs, 71mi (Apr 28 → Jun 15)
```

Per-run, append a compact life tag to the existing "Recent runs" line
(`athlete-state.ts:~2517`) so context rides with the run it modifies:

```
  2026-06-14: long 18mi — 8:05 avg [tired · 5h sleep · Vaporfly]
```

Only render the tag when `life` or `shoe` is present. Keep it to the 2–3 fields
that carry weight (fatigue, sleep, shoe) — the full bag lives in the rollup.

### 5. Prompt: teach "How you felt" to use it (`daily-read.v5.ts`)

The "How you felt" section already says to fuse "life context (sleep, travel,
work stress, heat)." It just never had the structured signal. Tighten two spots:

- **"How you felt" section (line ~62):** add that sleep / stress / travel / fatigue
  now arrive as structured fields in the ATHLETE STATE "Life context" block and
  per-run tags — use them to calibrate what a pace meant, in plain language, and
  **never moralize** ("you should sleep more" is banned; "five hours of sleep and
  a work trip — Saturday's pace is that, not your fitness" is the read).
- **Footwear:** add a line under NIGGLES that a recurring niggle which tracks a
  single shoe may be surfaced as a thread ("the calf has shown up three times,
  all in the Vaporflys") — **surface the co-occurrence only, never assert the
  shoe caused it.** Footwear is never a standalone section; it only appears when
  it sharpens a niggle thread or a "felt great in the new trainers" note.

No schema change — this stays within v5's `sections`/`How you felt`. So it is a
**prompt-template edit on an existing version**, which still trips the eval gate
(below) because it touches a file under `_shared/prompts/`.

### 6. Eval coverage (hard rule #3 + CI gate)

`.github/scripts/check_eval_coverage.py` fails any PR touching `_shared/prompts/`
unless `_evals/cassettes/<prompt>/` exists. `daily-read.v5/` already exists, so
add cassettes rather than create the dir. Minimum new cases:

- **`005-life-context-calibrates-pace.json`** — slow long run + `extracted_data`
  showing 5h sleep + work travel. Assert: the Read attributes the pace to life
  context, does NOT call it lost fitness, does NOT moralize about sleep.
- **`006-footwear-niggle-thread.json`** — calf mention 3×, all same shoe. Assert:
  surfaces the shoe↔niggle co-occurrence as a thread, no causal claim, no
  diagnosis, no "stop wearing them."
- **`007-life-signal-absent-no-fabrication.json`** — memos with no life fields.
  Assert: no invented sleep/stress numbers; "How you felt" leans on mood only;
  `cant_see` may note the gap.

Run via `_evals/record.ts` with `GEMINI_API_KEY`; review against
`docs/coaching/principles.md` since v5 coverage is still partial.

## Safety rails (carry the hard rules through)

- **Surface, never diagnose / direct** still governs footwear and soreness.
  `soreness[]` from `extracted_data` is body-part voice signal — it feeds the
  niggle surface under the *same* closed-vocab, verbatim, surface-only rules
  (CLAUDE.md rule #2). Do not let a shoe become a cause or a soreness entry
  become an injury.
- **No moralizing on lifestyle.** The Read calibrates with life context; it does
  not coach sleep hygiene, work-life balance, or family load. Add "you should
  sleep more / stress less" to the banned-phrase intent in the prompt.
- **Self-reported, not measured.** `sleep_hours` here is what the athlete said in
  a memo, not HealthKit. Label it "self-reported" in the context block so the
  model never presents it as device truth.

## Explicitly out of scope (separate tracks)

- **HealthKit sleep / HRV / resting HR.** The iOS app reads HealthKit workouts
  (`WorkoutSyncService.swift`) but does not sync sleep or recovery vitals into a
  structured table. Wiring measured sleep is a real ingestion project (new table
  + RLS + sync) and belongs to the v1.5 Recovery pillar, not this change. This
  spec delivers *self-reported* sleep now; measured sleep later.
- **Authoritative shoe odometer.** A Strava connector exposes `get_gear`, which
  carries real per-shoe mileage. If shoe-mileage accuracy ever matters (e.g. a
  "your trainers are past 400mi" surface), pull from there. Out of scope here —
  this change only narrates shoes the athlete named.

## Why this is the right next step

Every other stream on the priority list already reaches the model as structured
signal. This is the one place where the data exists, is parsed, is stored — and
is thrown away one line before it would have been read. It is a few-hour wiring
change that turns "infer life context from raw memo text, if it survived"
into "the strongest model reads sleep, stress, travel, and footwear as
first-class signal next to the splits." That is the difference between a Read
that knows a number and a Read that knows what the number meant.

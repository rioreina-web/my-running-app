# Ask · Phase A — apply notes

*Placed 2026-08-05. Follows the `APPLY-NOTES.md` additive-new-files convention.*
*Design: `ASK-APPLY.md` (architecture) · `ASK-REGISTRY.md` (all 50 analyzers) ·
`ask-prototype.html` (surface).*

Phase A of the Ask surface: the analyzer registry, the Layer-2 narration guard,
the `ask` edge function, and **three working analyzers** wrapping math that
already ships.

**11 new files, 2,549 lines. One edit to an existing file (2 lines). One new
migration.** Everything typechecks under `deno check` and the 26 unit tests
pass.

---

## 1 · What was placed (new files, additive — safe)

### The contract

| File | What it is |
|---|---|
| `supabase/functions/_shared/analyzers/types.ts` | The analyzer contract. `FactLine` / `Coverage` / `SeriesSpec` / `EmptyState` / `AnalyzerResult` / `Analyzer`, the closed `ParamSpec` vocabulary, and **`factLinesToStrings`** — the single seam between Layer 1 and Layer 2. Plus the shared formatters. |
| `supabase/functions/_shared/analyzers/data.ts` | Row fetchers. Zone loading (both `PaceZones` and `ZoneTable` flavours from the one `athlete_state.pace_zones` blob), laps by workout, logs and features by window. Every query scoped `.eq("user_id")`. |
| `supabase/functions/_shared/analyzers/index.ts` | The registry. Same one-import-one-map-entry convention as `_shared/rules/index.ts`. Also `coerceParams`, which enforces the router's closed schema. |
| `supabase/functions/_shared/narration-guard.ts` | Layer-2 guard. Re-exports the number-token primitives from `workoutComparison.ts` (one implementation, not a copy) and adds **`validateNarration`** — the generalization of `compare-workouts`' private `validateVerdict`. |

### The three analyzers

| File | Answers | Wraps |
|---|---|---|
| `analyzers/zoneTrend.ts` | *Is my LT / MP / 5K pace improving?* | `fast-segment-trends.analyzeFastSegmentTrends` |
| `analyzers/loadBalance.ts` | *Am I ramping too fast?* | `weeklyAnalytics.aggregateWeeklyLoad` + `calculateACWR` |
| `analyzers/compareSession.ts` | *How does this session stack up?* | `workoutComparison.compareWorkouts` + `findBestComparison` |

**None of the three writes new math.** Combined they are ~950 lines of
adapter over ~3,100 lines of existing, tested analytics.

### The surface

| File | What it is |
|---|---|
| `supabase/functions/ask/index.ts` | The endpoint. Layer 0 (fast-path regex, then a `gemini-2.5-flash-lite` router over the closed enum), Layer 1 (always runs, always free), Layer 2 (charged, guarded). |
| `supabase/functions/_shared/prompts/ask-narration.v1.ts` | The Layer-2 prompt. Receives the question and the fact lines. Nothing else. |
| `supabase/migrations/20260806120000_create_analysis_queries.sql` | The audit ledger. RLS in the same migration per hard rule #1; service-role write, athlete reads own, per hard rule #4's posture. |

### Tests — 26 cases

`supabase/functions/_shared/analyzers/analyzers.test.ts`. The load-bearing one
is the `seam:` group — that the strings the model is shown and the tokens the
guard licenses come from the *same array*. Every safety property in Ask rests
on that identity holding.

Also covered: the guard rejecting an invented number in the text **and** in the
caveat, degrading on unparseable output rather than throwing, and licensing
rounded forms of printed decimals; `coerceParams` dropping unknown keys,
out-of-enum values, out-of-range numbers, and a SQL-injection-shaped
`workout_id`; and every analyzer's empty state (hard rule #8 — asserted to
contain no em-dash placeholder).

---

## 2 · The one edit to an existing file

`supabase/functions/_shared/prompt-library.ts` — the standard two-line
registration the module's own header documents:

```ts
import { TEMPLATE as ASK_NARRATION_V1 } from "./prompts/ask-narration.v1.ts";
// ...
  "ask-narration.v1": ASK_NARRATION_V1,
```

**Already applied.** Nothing else in the repo was modified.

---

## 3 · What is deliberately NOT done

- **`ask-narration` is NOT registered as a golden family.** It should be — it
  is athlete-facing and safety-baitable, which is exactly hard rule #3's
  trigger. But adding it to `.github/scripts/check_eval_coverage.py` before
  the cassettes exist would block CI on the next PR that touches it. **Record
  cassettes into `_evals/cassettes/ask-narration/` first, then add the entry.**
  This is the launch gate, not a nice-to-have.
- **No new rate-limit bucket.** `ask` uses the existing `analysis` bucket
  (free 10 / pro 25), so `rateLimit.contract.test.ts` is untouched. The
  asymmetry from the spec is implemented differently and better: Layer 1 is
  never charged, so **chips cost nothing**. The bucket is only decremented
  when a Layer-2 model call is actually made — and an exhausted quota serves
  the facts rather than an error.
- **No client code.** No Swift, no iOS surface. The endpoint answers
  `{"analyzer_id":"__catalog__"}` with the registry so the chip rail can be
  built without hardcoding a list that drifts.

---

## 4 · Verification actually run

```
deno check _shared/analyzers/*.ts _shared/narration-guard.ts ask/index.ts   ✅
deno test  _shared/analyzers/analyzers.test.ts          26 passed, 0 failed  ✅
```

Plus an end-to-end smoke run of all three analyzers against realistically
shaped rows (a 3:28 marathoner, eight LT sessions across a warming summer,
34 easy runs). Real output:

```
ZONE_TREND      7:05/mi (−7s)   LT pace · last 3 sessions          [good]
                7:12/mi         LT pace · first 3 sessions
                6:53/mi (−16s)  Conditions-neutral equivalent      [good]
                5.0 mi (in range) LT volume · recent average       [good]
                8 sessions / 120d / high

LOAD_BALANCE    1.01 (in band)  Acute : chronic · last complete week [good]
                49.2 mi         Last complete week
                50.3 mi (−2%)   4-week average
                1.9             Monotony · 7 day                   [good]
                42 sessions / 49d / high
                missing: current week too short to read

COMPARE_SESSION 7:03/mi (−2s)   Pace vs. the match
                170 bpm (same)  Average HR across the work
                5 (same)        Reps at the work pace
                76°F (−1°)      Temperature
                0.8% (same)     Aerobic decoupling
                2 sessions / high
```

Against each payload, a narration claiming an invented `3:07` was **rejected
by the guard** — the mechanism works on real fact lines, not just fixtures.

The smoke script found two real display bugs, both fixed: deltas that round to
zero were rendering as `+0` (now `same` — a signed zero reads as a real tiny
change and invites the model to narrate a difference the rounding erased), and
the comparison chart was reading `paceSecPerMile` off a `SeriesPoint` whose
field is `paceSec`.

---

## 5 · Before this can be deployed

1. **`supabase db push`** for `20260806120000_create_analysis_queries.sql`,
   from a committed SHA (hard rule #9 — no dashboard SQL editor, no MCP
   `apply_migration` against prod). Note there are already migrations pending
   push ahead of this one.
2. **Deploy the `ask` function.** It needs `GEMINI_API_KEY` (which
   `compare-workouts` already uses). **Without it the endpoint still works** —
   Layer 0 falls back to the regex fast path, Layer 2 is skipped, and every
   answer serves bare facts with `annotated: false`.
3. **Record `ask-narration` cassettes**, then add it to the golden list.
4. Ship behind a flag. Chips only, no free-text box, until you've read a
   week of `analysis_queries` rows.

---

## 6 · One judgement call worth reviewing

`load_balance` refuses to lead on a partial current week. Asking on a Tuesday
and comparing three days against four full prior weeks reads as *"you've
collapsed"* — so before day 4 of the week it reports the **last complete
week** and says so in the coverage line.

This is the right call for honesty and the wrong call if the athlete asked
specifically about today. The alternative is to always show the partial week
with a prominent "3 days in" label. `PARTIAL_WEEK_CUTOFF_DAYS` is a single
constant in `loadBalance.ts` if you disagree.

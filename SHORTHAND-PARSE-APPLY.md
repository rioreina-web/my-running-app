# Workout shorthand → plan: what was broken

Written 2026-08-28. Everything below was measured against
`web/tests/fixtures/coach-shorthand-corpus.json` — 137 real workouts from six
seasons of this coach's plans — or against the live Gemini API.

## The one-sentence version

Three independent layers were each dropping part of the prescription, and
**every one of them reported success while doing it** — so the coach saw a
finished-looking workout that wasn't the one they wrote.

---

## The root causes

### 1. The plan editor threw the pace away

`DayDetailSheet` — the surface that writes into the plan — sent no `useModel`,
so it got the edge function's own grammar (12% against this coach's plans) and
never received `structuredSteps`. It then derived pace from
`step.pacePercentage`, a field the server hardcodes to `null`, so the `.map()`
never fired.

**Every workout written into the plan from that screen saved with
`paceZone: nil`, `paceAdjustment: nil`, `targetPaceIntensity: nil`.** Its only
record of a prescription was the English `"@ marathon pace"` in a notes field.
`absolutePaceSecPerMile` was on the wire and never read.

This was the original "writing workouts into the plan fails."

### 2. The model omitted the offset — because the schema let it

`paceZone`, `paceAdjustmentType` and `paceAdjustmentValue` sat outside
`required` in the response schema. A model under no obligation to emit a field
simply doesn't.

Measured on `16 x K alternating MP-3% & MP+5%` — a string written verbatim as a
worked example *in its own prompt*:

| model | result |
|---|---|
| `gemini-3.5-flash-lite` | correct 1 run of 3 |
| `gemini-3.5-flash` (upgraded) | wrong on every run |
| **flash-lite, fields required** | **6 of 6** |

The tell was the shape of the failure: never a *wrong* offset, always a
*missing* one. A better prompt didn't fix it. A bigger model didn't fix it. One
line in the schema did.

### 3. A spaced `+` was read as a segment break

`splitSegments` used "attached `+` is an offset, spaced `+` separates", so
`MP +5%` was torn into `MP` and `5%`. Coaches write the spaced form constantly.
Minus was never affected — which is why only *half* of every alternation looked
wrong, and why it read like the model hallucinating.

### 4. An alternation's legs couldn't be comma-separated

Two causes on one input. `splitSegments` cut on the comma before
`parseAlternation` ever saw two legs, and the leg splitter only knew `/`, `&`,
`vs`, `and`. So `16 x K alternating MP-3%, MP+5%` collapsed to **one step,
repeats 16, at MP-3%**, float leg gone — and the step editor then supplied a
default `1:00` rest nobody had written.

Across 1536 phrasings of that one session: **420 correct before, 672 after.**

### 5. Compound sets silently dropped their rest

A set-level recovery (`7 x (1k @ hm / 600 @ 10k) w/1' rec`) was parsed, stored
on the step, and **never read** by the adapter. And a clause written as
`w/1' between reps` was swallowed as the *last leg's* recovery, so half the
rests vanished.

| input | before | after |
|---|---|---|
| `7 sets of 1k @ HM & 600 @ 10k w/1' between reps` | 7 recoveries | 14 |
| `7 x (1k @ hm / 600 @ 10k) w/1' rec` | 0 | 14 |
| `8 x 3' hm/3' moderate w/1' rec` | 0 | 16 |

### 6. The edge function's grammar is unusable on real workouts

Served locally and given the corpus: **zero total distance on 125 of 137**, and
**10 of those reported no error at all**. Its own docstring example parses
fine, which is why it looked healthy. This is the fallback whenever the model
is unavailable — no key, exhausted budget, timeout — so it is reachable in
production.

Guarded, not fixed. **It should be retired.**

---

## The systemic problem

**The escalation gate asked the grammar whether it thought it had trouble.**

```ts
const localClean =
  steps.length > 0 && !unparsed.length && !warnings.length && !unresolved.length;
if (localClean) return grammarAnswer;   // model never called
```

Every condition is the parser grading its own homework. Against a *confidently
wrong* answer that question is worthless — and confidently wrong is exactly
what this parser produces. The alternation returned 16 steps, no warnings,
nothing unresolved, and half of them had lost their offset. It passed every
check, so the model was never asked.

Same shape three times in one day: the recovery drop, the 0-mile steps, the
alternation. All three reported themselves clean.

**Fix:** check the output against the input instead of asking.
`uncoveredPaceOffsets` — an offset written in the source that no step carries
means something was eaten, whatever the parser claims. Applied to the grammar
*and* the model, with a retry. Fires on 5 of 68 clean parses, so it doesn't
turn every workout into a paid call.

---

## Results

| | before | after |
|---|---|---|
| corpus clean (layered) | 100/137 (73%) | **116/137 (85%)** |
| built a workout at all | 135/137 | **137/137** |
| produced nothing | 2 | **0** |
| model returned something worse | **19** | **2** |
| alternation phrasings correct | 420/1536 | 672/1536 |
| alternations end-to-end | — | **10/10** |

---

## Still open

1. **An unresolved pace silently becomes `easy`** on both clients
   (`workout-shorthand-client.ts`, `WorkoutBuilderSheet.swift`). A test
   documents this as today's *wrong* behaviour. An honest question beats a
   confident guess.
2. **Training paces are wrong for fast athletes.** Easy is pinned at a flat
   **33% slower than MP for everyone** — fine at 4:00 (12:12), nonsense at 2:20
   (7:07). Race paces are correct; only the training zones scale linearly when
   they shouldn't. Needs a coaching decision on the right curve, then a
   coordinated change across `workout-helpers.ts`, `_shared/paces.ts` and
   `PaceCalculator.swift`.
3. **The pace anchor doesn't persist.** `/plans/new` starts with a null anchor,
   so `resolvePaceTable` falls back to `REFERENCE_PACE_SEC_PER_MILE` — a 7:30
   generic runner. Nothing remembers the goal time you typed; it only survives
   inside `phase_config` once the plan is saved.
4. **Parse *coverage* is unchanged** — 68/137 grammar-only. Today fixed
   correctness, not coverage. The glossary work (+19 measured: `fast` → a
   coach-defined zone, place-name stripping) is unwritten.
5. **The web portal has not deployed since April 14** and has no Git
   integration, so pushes deploy nothing. A Vercel deploy needs
   `SUPABASE_SERVICE_ROLE_KEY` set in project settings.
6. **The Deno grammar should be retired**, leaving two parsers instead of three.

---

## What's actually live

- `parse-workout-shorthand` **v17** — schema fix, verify-and-retry, zero-mile
  guard. Deployed, serves both web and iOS.
- iOS plan-editor fix — committed, **needs an app build**.
- Web parser fixes — committed, **needs a Vercel deploy**; live on localhost.

## The thing worth building next

A readback under the describe-it box: *"16 legs, 1 km, alternating MP−3% /
MP+5%."*

Every bug in this document was silent. The tests passed, the evals said 73%,
and the parser reported CLEAN on a workout that had lost half its rest. None of
them were found by reading code — all of them were found by a coach typing a
real workout and looking at the result. Make that loop visible and it takes
seconds instead of an evening.

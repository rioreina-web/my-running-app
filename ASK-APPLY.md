# Ask — the analysis surface inside Coach · build spec

*Authored 2026-08-05. Follows the `APPLY-NOTES.md` additive-new-files convention.*
*Companion prototype: `ask-prototype.html`.*

---

## 0 · The one-paragraph version

**Ask** is a second half to the Coach tab. Above it, the Daily Read stays what
it is — warm, qualitative, on demand. Below it, a chip rail and a text box let
Maya interrogate her own data: *"compare my Tuesday LT session to similar
ones," "is my threshold pace actually improving," "am I ramping too fast."*

The thing that makes it work is **not a bigger model**. It's that every answer
is computed first and narrated second. A registry of typed **analyzers** does
real math against real rows and emits **fact lines**. The model then writes two
sentences over those fact lines and is forbidden — mechanically, by a numeric
token check — from introducing a number that isn't in them. Chips call the
analyzers directly with no model in the loop at all.

That pattern already exists in this repo. `compare-workouts` does exactly this
(Layer 1 deterministic / Layer 2 constrained verdict, with
`firstDisallowedNumber` as the gate). **Ask generalizes `compare-workouts` from
one question into a registry.**

---

## 1 · Why this is cheaper than it looks

The analytics are already written and already tested. Nearly every question in
the chip library maps onto a shared module that exists today:

| Question the athlete asks | Existing module | LOC |
|---|---|---|
| Compare this session to similar ones | `_shared/workoutComparison.ts` | 1200 |
| Is my LT / MP / 5K pace trending? | `_shared/fast-segment-trends.ts` | 764 |
| Am I getting enough volume at that pace? | `fast-segment-trends.ts` → `SystemVolume` | — |
| Is my aerobic durability improving? | `_shared/fitnessSignal.ts` → `DecouplingTrend` | 428 |
| Metres per heartbeat | `fitnessSignal.ts` → `EfficiencyTrend` | — |
| Am I ramping too fast? | `_shared/dataAnalysis.ts` (ACWR) + `_shared/workloadScore.ts` | 1144 + 125 |
| Was that pace real, or was it the dew point? | `_shared/pace-heat-adjustment.ts` | 321 |
| What am I on track to run? | `_shared/fitnessPrediction.ts` | 1760 |
| How much of my week is quality? | `_shared/quality-volume.ts` + `_shared/weeklyAnalytics.ts` | 219 + 816 |
| What does this session actually break into? | `_shared/workoutSegmentation.ts` | 708 |

**Ask writes almost no new math.** It writes a *wrapper contract* around math
that already ships, plus a router, plus a UI. That is the whole reason to build
this now rather than after another quarter of analytics work.

---

## 2 · Architecture — three layers, one path

Chips and free text are **the same code path**. The only difference is who
fills in `{analyzer_id, params}`.

```
                    ┌──────────────── chip tap ──────────┐
                    │  {analyzer_id, params} hardcoded   │  ← no model, no cost
                    └────────────────┬───────────────────┘
                                     │
  free text ──► LAYER 0 · ROUTE ─────┤
                (cheap classifier,   │
                 closed enum)        ▼
                             LAYER 1 · ANALYZE          ← deterministic. math.
                             analyzers/<id>.ts             auditable. no model.
                             emits FactLine[] + SeriesSpec + Coverage
                                     │
                                     ▼
                             LAYER 2 · NARRATE          ← model sees ONLY the
                             ask-narration.v1              fact lines. Numeric
                             ≤ 2 sentences + ≤ 1 caveat    allowlist enforced.
                                     │
                                     ▼
                             render: headline · facts · chart · follow-up chips
```

### Layer 1 — the analyzer contract

New directory `supabase/functions/_shared/analyzers/`. One file per analyzer,
registered in `analyzers/index.ts` exactly the way `_shared/rules/index.ts`
registers coachable-moment rules. Pure functions, per the repo's testability
convention.

```ts
export interface FactLine {
  key: string;              // 'lt_pace_delta'
  label: string;            // 'LT pace vs. 8 weeks ago'
  value: string;            // '5:16/mi'
  delta?: string;           // '−4s'
  tone?: 'neutral' | 'good' | 'watch';   // never 'bad'. see §6.
}

export interface Coverage {
  sessionsUsed: number;
  windowDays: number;
  missing?: string[];       // ['no HR on 3 of 9 sessions']
  confidence: 'high' | 'moderate' | 'low';   // reuse workoutComparison tiers
}

export interface AnalyzerResult {
  facts: FactLine[];
  series?: SeriesSpec;      // → the existing Trends chart components
  table?: TableSpec;
  coverage: Coverage;
  related: string[];        // analyzer ids → follow-up chips
  empty?: EmptyState;       // eyebrow + nudge + CTA. hard rule #8.
}

export interface Analyzer {
  id: string;
  label: string;            // chip text
  group: 'fitness' | 'sessions' | 'load' | 'body' | 'conditions';
  params: JSONSchema;       // closed. the router can only fill these.
  run(params, ctx: AnalyzerCtx): Promise<AnalyzerResult>;
}
```

`AnalyzerCtx` carries `userId`, the Supabase service-role client, the resolved
`ZoneTable` (from `pace-engine.ts` — **never** re-derive zones locally, per the
pace-zone section of `CLAUDE.md`), and `athlete_state`.

**The rule that makes the whole thing safe: if a number is not in `facts`, it
does not exist.** The UI renders from `facts`. The model is allowed to speak
only the numbers in `facts`. There is no third source.

### Layer 2 — narration, with the gate that already exists

Reuse `allowedNumberTokens` / `firstDisallowedNumber` / `verdictNumbersAllowed`
from `_shared/workoutComparison.ts` — lift them into
`_shared/narration-guard.ts` and have `compare-workouts` import from the new
home so there's one implementation.

New prompt `_shared/prompts/ask-narration.v1.ts`. It receives the question, the
fact lines, and the voice rules. It does not receive the raw rows. Failure
modes all degrade the same way: **the facts always render; the narration is a
bonus, never a dependency** (`annotated: false`).

### Layer 0 — the router

Free text → `{analyzer_id, params}` via one call to the cheapest tier in
`_shared/router.ts` (Groq 8B). The model picks from a **closed enum of analyzer
ids** and fills a **closed param schema**. It cannot invent an analyzer.

Three outcomes:

1. **Confident match** → run the analyzer. The answer is computed.
2. **Ambiguous** → return 2–3 disambiguation chips instead of an answer.
   ("Threshold — do you mean the pace, the weekly volume, or Tuesday's
   session?") Costs nothing and teaches the vocabulary.
3. **No match** → fall through to the existing `coaching-agent` prose path,
   flagged `mode: 'prose'` in the response so the UI can render it without a
   fact block. Nothing regresses; open-ended questions still work.

---

## 3 · The chip library

Chips are not a flat wall of buttons. Three sources, in this order down the
screen:

**a. Contextual (0–3 chips).** Derived from state, no model. If the last
session was quality → *"Compare Tuesday's LT 6×1k."* If a niggle was logged in
7 days → *"Where has the calf shown up?"* If a race is < 21 days out →
*"What am I on track to run?"* If `data_depth < 2` → suppress the whole rail
and show the empty state instead.

**b. Standing, grouped by training principle.** Ten groups, collapsed to their
headers; tap a header to expand. This is the discoverability surface — it
teaches Maya that the question *is* askable, and grouping by **principle**
rather than by metric is what makes the registry read as a coaching model
instead of a dashboard menu.

> Load · Mix · Adaptation · Durability · Specificity · Recovery ·
> Consistency · Block · Conditions · Body

**The full registry — all 50 analyzers, the math behind each, the source
module, and a build-status audit against this repo — is
`ASK-REGISTRY.md`.** That document is the scope of the feature; this one is
the architecture. Read it before sequencing any phase.

**c. Follow-ups (2–3 chips).** Emitted by the analyzer's `related` field on
every answer. This is what turns single questions into a session — and it's
deterministic, so it can never suggest something the app can't answer.

---

## 4 · Data contract

One new table. RLS in the same migration, per hard rule #1; see
`docs/conventions/rls-checklist.md`.

```sql
-- 20260806120000_create_analysis_queries.sql
CREATE TABLE IF NOT EXISTS analysis_queries (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       TEXT NOT NULL,
  asked_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  source        TEXT NOT NULL,      -- 'chip' | 'text' | 'followup'
  raw_question  TEXT,               -- null for chips
  analyzer_id   TEXT,               -- null when routed to prose
  params        JSONB,
  mode          TEXT NOT NULL,      -- 'analyzed' | 'prose' | 'ambiguous'
  annotated     BOOLEAN NOT NULL DEFAULT FALSE,
  confidence    TEXT,
  facts         JSONB,              -- the fact lines, verbatim
  narration     TEXT,
  latency_ms    INTEGER,
  model_used    TEXT,
  guard_tripped BOOLEAN NOT NULL DEFAULT FALSE   -- Layer 2 rejected a number
);
```

This table earns its keep three ways: it's the promote-to-cassette feed
(`outputs/ai-feedback-loop-design-2026-07-07.md`), it's the honest answer to
*"what do people actually ask?"* before you build v2 of the chip library, and
`guard_tripped` is the alarm that tells you the narration prompt is drifting.

**Writes are service-role only**, matching hard rule #4's posture for
`coachable_moments`. Athlete gets `SELECT` on own rows.

---

## 5 · Endpoint

New edge function `ask` (`supabase/functions/ask/index.ts`).

```
POST /ask
  { question?: string, analyzer_id?: string, params?: object,
    context?: { workout_id?: string } }

→ { success: true,
    mode: 'analyzed' | 'prose' | 'ambiguous',
    annotated: boolean,
    analyzer_id: string | null,
    facts: FactLine[],
    series: SeriesSpec | null,
    coverage: Coverage,
    narration: { text: string, caveat: string | null } | null,
    followups: { id: string, label: string }[],
    disambiguation?: { id: string, label: string }[] }
```

Rate limiting via the existing `checkFeatureRateLimit` / `enforceMonthlyCap`
with a new feature key `ask`. **Chips that hit cache or need no narration should
not decrement the quota** — only a Layer-2 model call does. Semantic cache
(`_shared/cache.ts`) keys on `analyzer_id + params + athlete_state.version`, so
re-asking the same question the same day is free.

Do not add `ask` to the `parse-*` overlap cluster problem: it is a router, and
it dispatches to analyzers, not to other edge functions.

---

## 6 · Safety and voice — non-negotiables

- **Hard rule #2 applies in full.** No analyzer may return a fact line that
  diagnoses, recommends rest, or assesses severity. `niggle_timeline` reports
  *what was said and where*, verbatim, per the Niggles rules. `tone` has no
  `'bad'` value on purpose — `'watch'` is the ceiling.
- **`ask-narration` is a golden family** under hard rule #3. It is athlete-
  facing and safety-baitable. It ships with recorded cassettes in
  `_evals/cassettes/ask-narration/` or CI blocks it. Budget one `record.ts`
  run. Add `ask-narration` to the golden list in
  `.github/scripts/check_eval_coverage.py`.
- **Predictions follow hard rule #7.** `race_projection` returns a single
  number + confidence tier + lifetime PR. Never a range, never seconds
  precision, marathon and half rounded to the minute.
- **Empty states use the component**, never an em-dash (hard rule #8). Every
  analyzer must return a real `empty` state when coverage is insufficient —
  *"Two LT sessions on file. The trend gets honest at four."*
- **Coverage is always shown**, not just on low confidence. "9 sessions ·
  26 weeks · 3 without HR" under every answer. This is the difference between
  a product that feels analytical and one that feels like it's guessing.
- Voice per `design-system/README.md`: eyebrow + fact + one coral accent
  maximum per cluster. Narration is ≤ 2 sentences. It never explains the math.

---

## 7 · Reconciling with the Signal Lab

`TRENDS-V3-APPLY.md` shipped `RunningLog/RunningLog/Analysis/SignalLabModels.swift` — client-side
Swift builders for drift, efficiency, mood-vs-load and heat. Ask computes the
same four signals **server-side**. That is a duplicate-math risk of exactly the
kind that produced the `PaceCalculator.swift` ↔ `workout-helpers.ts` drift.

**Resolution:** the analyzers become the source of truth. Signal Lab keeps its
Swift builders for the *chart rendering* (they're fast, offline, and already
tested), but a cross-language contract test —
`_shared/signal-lab.contract.test.ts`, modelled on the existing
`cross-language-pace-contract.test.ts` — pins the two implementations to the
same fixtures. If they diverge, CI says so.

Do **not** delete the Swift builders. Do **not** let a fifth signal land on one
side only.

---

## 8 · Phasing

> **Superseded by `ASK-REGISTRY.md` §4.** The table below phases on
> *architecture*; the registry re-phases the same five stages on *coverage*,
> which is the more useful axis now that all 50 analyzers are enumerated and
> status-audited. The architectural cut is unchanged — A proves the contract,
> B–E are additive.

| Phase | Ships | Why it's the cut |
|---|---|---|
| **A** | Registry scaffold, `narration-guard.ts` lift, 3 analyzers (`compare_session`, `zone_trend`, `load_balance`), `ask` endpoint, chips only — **no free text**. Behind a flag. | Proves the contract end-to-end with the three analyzers whose math is most complete. Chips can't be misrouted, so Phase A can't embarrass you. |
| **B** | Layer 0 router, free-text box, ambiguity chips, prose fallthrough to `coaching-agent`. `analysis_queries` logging. | The chat box. Safe to add now because it can only *select* from things already proven in A. |
| **C** | `SeriesSpec` → charts, follow-up chips, contextual chip rail, semantic cache. | Turns single answers into a session. This is where it starts to feel like the product you described. |
| **D** | Remaining 8 analyzers, promote-to-cassette loop, Signal Lab contract test. | Volume. Each one is a file + a registry line. |

Phase A is the only phase with architectural risk. B–D are additive.

---

## 9 · What this deliberately does not do

- **No tool-calling loop.** One analyzer per turn, chosen once. Multi-step
  agentic chains are where cost and latency go non-linear and where "AI
  advises, never acts" gets hard to guarantee. If a question genuinely needs
  two analyzers, that's a composite analyzer, written by hand.
- **No free-form SQL generation.** The router fills a closed param schema
  against a closed analyzer enum. The model never writes a query.
- **No new model tier.** Layer 0 is the cheapest tier that exists; Layer 2 is
  ≤ 200 output tokens over pre-computed facts. "High power" is the analyzer
  registry, not the model.
- **No plan mutation.** Ask reads. It never writes to `plan_adjustments`,
  never reschedules, never touches `coachable_moments`. Reading is the whole
  product surface.

---

## 10 · Open calls for Rio

1. **Coach tab layout.** Daily Read on top with Ask below it, or a segmenter
   (`READ · ASK`)? The prototype shows the stacked version — Ask reads as the
   natural second move after the Read, and a segmenter hides it.
2. **Free rate limit.** Currently 5 free / 25 pro per day for `coaching-agent`.
   Chips are near-free; if the quota counts them, the rail feels expensive to
   touch. Proposal: chips uncapped, narration capped.
3. **Does `ask` absorb `compare-workouts`?** It could — `compare_session` is
   an analyzer that wraps the same engine. Keeping both means two front doors
   to one comparison. Recommend: keep `compare-workouts` as the Trends
   entry point, have it and `ask` share the analyzer, deprecate neither yet.

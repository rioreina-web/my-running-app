# FITNESS-TRAINING-GRAMMAR-APPLY — deeper training understanding

Execution brief, 2026-08-28. Successor program to FITNESS-REDESIGN-APPLY.md
(closed — see G0-FINISH §13). Goal: the model understands what a training
session IS — archetype, internal load, context — instead of flattening
everything to work-minutes × pace-vs-curve.

**Why this program is evidence-honest where the estimator wasn't:** deeper
session understanding = more information per session = more statistical
power on n=1. It strengthens the loss function rather than petitioning it.
Every layer below ships with its replay score; anything that doesn't beat
baseline gets parked without ceremony, exactly as the estimator was.

**The inherited discipline (non-negotiable):**
- Write the acceptance gate BEFORE running the measurement (§10/§12 pattern).
- Replay via `scripts/replay-fitness.ts`, point-in-time by `created_at`.
  Shipped-model session-residual baseline: MAPE 2.28% @1d / 2.26% @14d /
  2.20% @28d / 2.27% @56d over 23 scored sessions. Report all horizons +
  paired bootstrap (§11 pattern).
- Never derive rep duration from distance × prescribed pace — that feeds a
  PLAN in as a PERFORMANCE (§9, measured: 12×400 all reading exactly 4:34).
- `detectWorkBouts` 0/12 is CORRECT rejection of aerobic running (§9).
  Warmup-reclassification tolerances were measured net-negative at every
  setting. Do not retry either.
- This program is NOT an estimator rescue. Pricing improvements land in
  `trainingZoneSignal.ts`, which feeds the SHIPPED engine. If scored-session
  coverage materially grows (say 25 → 40+), report that the gate's power
  changed and let Rio decide whether anything re-runs. §13's closure stands.

## Layer 1 — Session grammar (archetype-aware pricing). START HERE.

This is G0-FINISH's own #2-ranked open item: "decide what a progression run
states." 10 of the 20 plausibility rejections are progression runs; more of
the canon's marker sessions (alternations, MP-under-fatigue) are either
rejected or mispriced.

**Build:** new pure module `supabase/functions/_shared/sessionArchetypes.ts`
(+ tests), consulted by `estimateFromSession` in `trainingZoneSignal.ts`.
Input: the session's `ParsedBlock[]` geometry + `intent_pattern` + workout
type. Output: an archetype classification + pricing directives. Archetypes,
each with its falsifiable pricing rule:

1. **Progression** (monotonic negative pace slope across blocks): the
   statement is the FINAL sustained segment's pace-for-its-duration, with
   the preceding miles as fatigue context — not the whole-run weighted mean
   (which is what currently lands outside the plausibility window).
2. **Alternation / float** (work blocks separated by faster-than-easy
   "recovery": float pace ≤ ~easy − 30s/mi or ≤ MP + 45s/mi): floats are
   WORK. Price the whole alternating span as continuous at its blended
   pace; do NOT rest-discount the floats. (Currently REST_DISCOUNT treats a
   5:35 float like standing rest → underprices the session.)
3. **MP-under-fatigue** (sustained MP-band work beginning after ≥N easy
   miles in the same session): price the MP segment with a fatigue-context
   credit — pace held after 8–10 preload miles is worth more than the same
   pace fresh. Start with credit as a measured dial (see gate), not an
   asserted constant.
4. **Cutdown / ladder** (stepwise faster reps): statement = the average of
   the final steps at their durations, not the session mean.
5. **Cruise / threshold volume** (uniform sustained reps, short rests):
   current pricing is already correct — the archetype exists so the others
   don't leak into it. Classification confidence gates everything: unclear
   geometry falls through to today's behavior unchanged.

**Gate 1 (write thresholds down before running):** (a) scored sessions rise
without junk — every newly-priced session's residual must sit within the
existing residual distribution (no new |residual| > 3σ tail); (b) 28d
session MAPE does not worsen (paired bootstrap, CI reported); (c) the six
`athleteProfiles.test.ts` profiles still pass — no constant shaped like one
athlete. Falsification example to include in tests: the real 2026-08-01
12-mile alternation session that priced at a 35:38-10K under v1 rules.

## Layer 2 — Fold HR into pricing (the data is already on the estimate)

`ZoneEstimate.meanHr` / `hrDrift` are computed and carried with a literal
"not yet folded into the pace math" caveat. Two uses, both scoreable:

- **Control weight:** scale a session's evidence weight by HR control —
  flat drift at hard pace = stronger statement; ≥8% drift = weaker (the
  athlete-state `execution` signal the predictor was audited as ignoring,
  SCALE §6.5). Weight modulates `combineZoneEstimates`' existing
  workSeconds weighting; it never flips a session's direction.
- **Effort anchor via `expectedHr`:** per-session residual against the
  fitted HR model (now wired, §13) says whether the session was controlled
  or a rupture. A controlled session prices as-is; a max-effort session at
  the same pace is a different (weaker) fitness statement.

**Gate 2:** 28d session MAPE improves vs Layer-1 baseline (bootstrap CI
excluding zero is the ideal; CI-spans-zero + no regression = park the
weight at neutral and keep the plumbing). HR fields must remain optional —
sessions without HR price exactly as before.

## Layer 3 — Fatigue context (cheap sequencing)

Per-session features computable from `training_logs` alone: mileage in the
prior 24h/48h, days since last quality session. Enters as a pricing
context on hard sessions (a tempo 18h after a 20-miler ≠ the same tempo
fresh). One feature at a time, same gate structure as Layer 2. Do not build
a load model here — that's Layer 4's parked territory.

## Layer 4 — Response model. PARKED. Named unlocks only.

What training DOES to fitness over weeks (Banister/CTL drift). Confounded
on this athlete's history (LEARNING §4: EF is measured from the runs that
constitute the dose; "better fitting on confounded data just produces a
more confident wrong answer"). Unlocks, either of: (a) real users, or
(b) **the monthly benchmark protocol** — same 3×10min threshold test,
fixed loop, cool morning, standard warmup, monthly; its own table; the one
clean instrument. (b) is Rio's personal/product decision. Until then: no
drift terms, no adaptation constants, anywhere.

## Layer 5 — The readiness board (product surface; the payoff)

Given a goal race + target, list the marker sessions in Rio's vocabulary,
each with measured status + the evidence chips behind it. **Deterministic
checks over logged sessions — no inference, no LLM numbers, glass-box.**
Fits the Week tab's proposal philosophy (WEEK-TAB-APPLY.md); the existing
`race-readiness.v1` prompt + Ask analyzer registry are the natural server
seams; marker definitions belong next to `docs/coaching/principles.md`
vocabulary, not hardcoded paces ([[feedback-no-hardcoded-paces]] — derive
from the goal + the athlete's ladder).

**First instance (Rio, CIM 2026-12-06, target 2:20:00 = 5:20/mi):**
- Tune-up race: half 1:06:30–1:07:30 (or 10K ≤ 30:40), inside 6 weeks
- MP-under-fatigue: 14–16mi @ MP-band inside a 20–22mi run, HR controlled
- Alternations: 10–12×1K @ ~MP−15s with ~MP+15s floats
- Long tempo: 8–10mi @ half-to-LT band
- Threshold volume: 6–8mi cruise work per session at the LT band
- Durability: a true 20-miler + ≥3 runs ≥16mi in trailing 70 days
- Absorption: easy-band EF drift ≤ 0 (flat) while MP volume goes in —
  computed exactly as the 2026-08-28 EF artifact does (pooled `expectedHr`
  fit, per-band residual readout; NEVER per-band fits — unstable)
Marker paces derive from the target via the athlete's own ladder at
runtime; the list above is the 2:20 instantiation, not constants to bake.

Layers 1–2 are what make several of these checks measurable at all — build
order is 1 → 2 → 5, with 3 riding along and 4 parked.

## Practical notes for the executing session

- Engine-side changes ship through `compute-fitness-snapshot` deploy only
  (no migrations expected for Layers 1–3). Manual invoke runbook + replay
  command: FITNESS-REDESIGN-APPLY.md §0.2.
- 65+ engine tests + 30 zone-signal tests + 6 athlete profiles must stay
  green; `deno test supabase/functions/_shared/`.
- Commit per layer with the gate result in the commit body, pass or fail —
  measured negative results get committed too (§9 is the model).
- Branch: design/ds-sync unless Rio says otherwise; ~9 concurrent sessions
  share this tree — stage by explicit path, commit promptly.

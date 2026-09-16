# Recovery score — does it work?

**Date:** 2026-08-18 · **Method:** the shipped ledger ported line-by-line to Python and
replayed over 214 days of your own data (2026-01-17 → 2026-08-18), then tested against
`felt_rpe`.
**Harness:** `outputs/recovery-score-validation-2026-08-18.py` + `recovery_ledger_port.py`.
This is Stage 3, item 1 of `recovery-score-9-of-10-plan-2026-08-05.md` — the step the plan
called "the 8→9 gap" and that has never been run.

**Port fidelity check:** the port returns **29 · Flat · ceiling 74** for today, with the
same six factor rows as the screen. It is reproducing the shipped arithmetic, not
approximating it.

---

## The verdict in one paragraph

The **receipt** is the best thing in the product and better than anything Whoop, Oura or
Garmin ships — every factor names its evidence, degraded inputs are disclosed on the face
of the card, and an unreachable band is admitted rather than drawn as open territory.
The **number under it is not yet a measurement**. Over 214 days it has never left a
37-point strip of a 100-point dial, it has no relationship with the only outcome column
you collect, it does not distinguish the days you chose to rest from the days you chose to
run, and it did not move ahead of the one injury in the window. Two of its seven factors
have been running on fallback paths since the day they shipped, because the data they
need has never arrived. **The honest status is: a well-built, well-documented,
transparent number of unknown accuracy — and the first real measurement of it says the
accuracy is zero.**

---

## 1 · The distribution: the score barely moves, and never gets good

| Band | Days | Share |
|---|---|---|
| Flat | 73 | 34.1% |
| Worn | 128 | 59.8% |
| Steady | 13 | 6.1% |
| **Clear** | **0** | **0.0%** |

Mean **48.0**, sd **7.4**, observed range **29–66**. Median 48. In seven months the score
has never once been above 66 or below 29.

**Clear was arithmetically unreachable on 211 of 214 days** — today's ceiling is 74 against
a band that starts at 75, and 160 of the 214 days had exactly that ceiling. The card is
honest about it ("today's inputs top out at 74"), but an athlete looking at a four-band
gauge where 94% of days land in the bottom two bands and the top band is structurally
impossible learns one thing: *the app thinks I am always wrecked*. That is the state in
which a metric stops being read.

## 2 · The prospective test: no relationship with anything

The only outcome column you collect is `felt_rpe`, and it is a real signal — it separates
your session types cleanly (easy 5.41 · long 6.45 · key 7.39), so it is worth testing
against. To avoid circularity every test uses **yesterday's** score, which cannot know
about today's run.

The fair form of the question is *"did this run feel harder than this kind of run usually
does?"* — felt RPE with the session-type mean removed:

| Test | n | result |
|---|---|---|
| yesterday's score → today's type-adjusted felt RPE | 72 | **r = +0.01** (95% CI −0.22…+0.24) |
| yesterday's score → raw felt RPE | 72 | r = −0.02 |
| … within easy runs only | 33 | r = +0.08 |
| … within key sessions only | 27 | r = +0.01 |
| 1 / 3 / 7-day *change* in score → next felt RPE | 72 | r = +0.01 / −0.02 / −0.05 |
| yesterday's mood factor alone | 72 | r = −0.14 (CI −0.36…+0.09) |

Mean felt RPE the day after each band: **Flat 6.26 · Worn 6.30 · Steady 5.00 (n=2)**.
Flat and Worn — 94% of all days — are indistinguishable.

At n=72 the smallest correlation separable from zero is about **±0.24**, so this does not
merely fail to find an effect; it rules out anything above "explains 6% of the variance."

**Behaviour test.** Score on the day before a rest day: **48.0** (n=36). Before a run day:
**48.1** (n=177). Cohen's d = −0.02. The score does not even track your own decisions
about when to stop.

**The injury.** In the 14 days before the 2026-07-17 knee episode the score averaged the
**58th percentile** of its own history — slightly *above* normal. Your `recovery-need-model`
doc says the load term missed that episode and mood caught it; on this replay the composite
missed it too, because mood is one term inside a sum that dilutes it.

## 3 · What the score is actually made of

| Factor | days present | mean | sd | correlation with the total |
|---|---|---|---|---|
| Recovery need | 173 | +1.29 | 5.38 | +0.55 |
| Mood | 214 | −4.29 | 4.92 | +0.50 |
| Clear days | 214 | +2.20 | 3.03 | +0.46 |
| Body mentions | 214 | −0.87 | 2.03 | +0.29 |
| Overnight | 163 | −0.04 | 1.66 | −0.14 |
| Sleep | 214 | −0.04 | **1.30** | +0.08 |

Two observations that matter more than the ranking:

- **Sleep and Overnight are inert.** Between them they move the score by an average of
  0.08 points a day. They are on the screen, they are on the receipt, and they are
  contributing nothing — because they are both stuck on their fallback branches (§4).
- **A quarter of the score's variance is one self-report.** Mood alone explains 25% of it,
  and mood is logged on 36% of days. Day-to-day |change| is **5.1 points on days a mood
  log lands versus 3.5 on days none does** — so a large share of the movement the athlete
  sees is *whether they opened the app*, not what their body did. The 3-point noise floor
  the Read enforces is well below the noise the logging pattern itself injects.

## 4 · The input pipes, not the arithmetic, are the problem

Measured on the live database, over the whole window:

| Input | Coverage | Consequence |
|---|---|---|
| **HRV** | **0 of 204 nights. Ever.** | Overnight has *never once* run its 3×3 cross-check. It has only ever been the RHR-only nudge, and the "HRV down + RHR up" cell — the one cell that subtracts, the whole reason the factor exists — is dead code in production. |
| **Sleep rating** (one tap) | **3 of 214 days** (all since Aug 7) | Sleep has run the Tier-3 duration fallback on 211 of 214 days: range +2/−3 instead of +4/−6, on an input your own evidence review calls the strongest single prospective signal in runners. |
| Watch sleep minutes | 165 / 214 | fine |
| Resting HR | 198 / 214 | fine |
| Mood | 78 / 214 (44% of run days) | the load-bearing factor, logged less than half the time |
| Body mentions | 5 in 7 months | fine — absence is information |
| `stress_load` | 294 / 295 runs | good; the load ladder is on its top rung |
| **`planned_rpe`** | **0 of 291 runs** | see below |

That last row is the one to fix first. Three separate docs — the status doc, the 9-of-10
plan, the recalibration report — describe "felt vs planned RPE" as live and name it *the
ground truth column the score will be validated against*. **The column is empty.** `felt_rpe`
is populated on 73 days; `planned_rpe` on none. The disagreement signal the whole accuracy
engine was designed around ("the score said Worn and the run felt easy") cannot currently
be computed at all.

## 5 · The one place a signal appeared

The only test that produced anything is the **step**, not the level:

| | n | felt RPE over the next 3 days |
|---|---|---|
| after a 1-day drop of ≥10 points | 6 | **7.50** |
| all other days | — | 6.39 |

d = +0.63. Six events is an anecdote, not a finding — and the raw mood log that caused
most of those drops does *not* predict on its own (d = +0.04), so the drop may be doing
something the label alone doesn't. But it is the only crack of daylight in the whole
analysis, and it points the same direction as your own demand/supply doc: **transitions
carry information; levels don't.**

---

## What I'd do, in order

1. **Populate `planned_rpe`.** Nothing else on this list can be evaluated until the ground
   truth exists. Every plan in the repo assumes this column is live; it is empty. Pair it
   with getting `felt_rpe` above its current 25% of runs — one tap after a run, same
   pattern as the sleep check-in.
2. **Fix the two dead pipes before touching a single coefficient.** HRV has produced zero
   rows in 204 nights (the code comment already suspects it: iOS never reports a denied
   READ scope, so the query silently returns empty — that hypothesis is now confirmed by
   the data). The sleep rating has 3 taps in 11 days. Recalibrating a model whose two
   biometric factors have never run is tuning a car with the fuel line disconnected.
3. **Stop drawing a 0–100 dial.** The score occupies 29–66. Either rescale the gauge to the
   range the model can actually produce today (the `ceiling` property already computes it),
   or drop the number and show the band and the receipt alone. A gauge where the good end
   is unreachable teaches the athlete to ignore the whole card.
4. **Consider surfacing the change rather than the level.** "Down 17 since Friday" is the
   only form of this number that showed any relationship to anything.
5. **Do not add an eighth factor.** Adding terms to a composite that currently correlates
   0.01 with reality makes it more elaborate, not more accurate. The next change to the
   arithmetic should be a *removal* — Sleep and Overnight are contributing 0.08 points a
   day and two rows of visual authority.
6. **Write the accuracy bar down now, before beta users see it.** Something like: *"by
   200 athlete-days, |r| ≥ 0.3 against type-adjusted felt-vs-planned RPE, or this ships as
   a load ledger and loses the word recovery."* The receipt pattern is strong enough to
   carry a purely descriptive product; what it cannot carry is a claim that has been
   checked once and failed.

**Two honest caveats.** This is one athlete, 214 days, 72 outcome-labelled runs — it proves
the score is currently uninformative *for you*, not that the model is wrong for everyone.
And several of the factors were designed to describe rather than predict; a load ledger
that says "you're carrying 19% more than usual" is doing its job even at r=0. The problem
is that the card is titled **Rest and readiness** and reads as a verdict — and on the
evidence there is no verdict in it yet.

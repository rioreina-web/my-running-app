# Recovery need — a demand/supply model for the score

**Date:** 2026-08-06
**Status:** design proposal, for discussion
**Builds on:** `docs/specs/recovery-trend-v2-2026-07-27.md` (the evidence base),
`outputs/the-daily-read-score-design-2026-08-04.md` (the unified-score design this
reorganizes), `RunningLog/RunningLog/Trends/TrendsRecoveryFactors.swift` (the shipped
ledger, recalibrated 2026-08-06). Companion proof:
`outputs/recovery-need-demand-supply-2026-08-06.html` +
`outputs/recovery-need-model-2026-08-06.py`.

---

## 0. The question, and the reframe

"How do we make the score a better indicator of readiness?" The honest trap in that
question is the word *readiness*. A readiness score — Whoop, Oura, Garmin Training
Readiness — is a claim about your internal physiological state. `recovery-trend-v2` §7
spent its whole length showing that claim is not supportable in runners: HRV was null
for injury (p=.225), single-day HRV is noise, no readiness number has ever been
externally validated, most overuse injuries have no warning window at all (6.9%), and
the words *ready / recovered / risk* were banned from the copy as unsupportable.

So a "better readiness score" that is still a state-claim fights our own evidence. The
fix is to change what the number *is*. Not "how recovered am I" — a state we can't
measure — but **"how much recovery do I need, and are my own signals saying that need is
being met?"** Two terms:

- **Demand** — the recovery hole that training just dug. Pure load math. Grounded in the
  one readiness framework that *is* validated in endurance sport (Banister
  fitness–fatigue / training-stress balance). Needs no watch.
- **Supply** — whether your own words and nights say the hole is filling back in.
  Self-report leads (sleep quality, mood, niggles); HRV × resting-HR corroborates, gated.

The score still renders as it does today — a band word, a number, a receipt of named
contributions. What changes is that the *sentence* comes from the **relationship**
between demand and supply, not from a flat weighted sum. That relationship is the
recovery need.

---

## 1. Why two terms, proven on Rio's 202 days

The demand/supply split isn't an aesthetic choice; the real data forces it. The proof
script replays both terms over every day 2026-01-17 → 08-06 (miles + duration + type from
`training_logs`, niggles from `body_mentions`; no sleep/HRV existed in the window).

**The demand term is a real signal — it tracks behavior with no circularity.** The
recovery-need index (acute load over chronic, normalized to the athlete's own chronic)
averaged **+29 before the rest days Rio actually took vs +18 before run days**. When the
load hole was deeper, she rested. The term also correctly reads the March build and the
July marathon double-days as the biggest holes. This is a load descriptor that means
something.

**But demand did not see the one real injury coming — and supply did.** In the 7 days
before the July 17 knee episode, the load-need index sat at **+1, below Rio's own median
(21st percentile)**. Training math gave no warning whatsoever. The warning was entirely on
the supply side: mood logged *struggling* for a solid week beforehand (Jul 8–13), and the
niggle surfaced on the 17th. This is exactly the ordering `recovery-trend-v2` §1 predicted
from the literature (soreness elevated 1–2 weeks pre-injury, fatigue 1 week pre-injury;
Goldberg 2025, Sanchez 2025) — now demonstrated on Rio's own history.

The lesson is sharp and it defines the model: **a load-only readiness number — which is
essentially what Garmin Training Readiness and TSB are — would have called Rio fine the
week before her one real episode this year.** Her words didn't. So supply must **lead**,
and demand is the **context** that tells you what a dragging signal means. Neither term
alone is the answer; their relationship is.

---

## 2. Demand — the recovery need from load

### 2a. The load unit

`sessionLoad = duration_min × intensity(type)` — a session-level internal-load proxy
(import the real per-workout `stress_load` once its migration is applied; until then this
duration×intensity form is the fallback). Duration artifacts (a paused watch reading
10 mi in 236 min) are clipped: any session slower than 14 min/mi is re-imputed at ~easy
pace, so one bad GPS row can't spike the whole series.

### 2b. Acute, chronic, and the need index

Banister's model, unchanged in shape from every validated implementation:

```
ATL = 7-day  exponentially-weighted mean of daily sessionLoad   (acute — fatigue)
CTL = 42-day exponentially-weighted mean of daily sessionLoad   (chronic — fitness)
needIndex = 100 · (ATL − CTL) / CTL          # unitless, 0 = balanced, + = a hole
```

The need index is **a difference against the athlete's own chronic load, never a ratio and
never a population number** — `recovery-trend-v2` §7.1 dismantled the acute:chronic ratio
(coupling inflation r=0.52 from arithmetic alone, the denominator carries no signal, the
only RCT null, thresholds with no primary source). A normalized *difference* keeps the
same intuition — "how far above your usual is this week" — without the ratio's pathologies.

### 2c. The session spike, as its own contributor

The single best-evidenced load finding in running is not weekly at all: a single run
**>100% longer than the longest run in the prior 30 days** carried HRR 2.28 (Frandsen 2025,
588k sessions). It rides alongside the need index as a discrete contributor, not folded
into the EWMA, because its evidence is session-level and it would otherwise be smoothed
away.

### 2d. The warm-up gate (a caveat the data surfaced)

The need index over-reads for the first ~8 weeks, while CTL is still climbing from a cold
start — Rio's March "+89" days are that artifact, not real holes. Demand must carry the
same "not enough history yet" gate the other baseline factors already use: below ~6–8
weeks of load history, the need index is shown as low-confidence or withheld, not trusted.

---

## 3. Supply — is the need being met

Supply is the evidence hierarchy from `recovery-trend-v2` §2b and the Daily Read §1,
unchanged. It **leads** the read because in runners it out-predicts the watch.

| Tier | Signal | Source | Role |
|---|---|---|---|
| 1 · lead | **Sleep quality** | `daily_checkins.sleep_quality` (one-tap) | Strongest single prospective signal |
| 1 · lead | **Niggles** (soreness) | `body_mentions`, severity × clustering, 14-day | Soreness elevated 1–2 wks pre-injury |
| 1 · minor | Mood / fatigue | `daily_checkins.mood` + `training_logs.mood`, 7-day | Weakest of the three — see §3a |
| 2 · gated | Autonomic (HRV × resting HR) | `daily_biometrics` | Corroborates only; the one readable quadrant |
| 3 · note | Total sleep time | `daily_biometrics.sleep_total_min` | Annotation, never a threshold |

The autonomic domain is the v2 §2c / Daily Read §2c quadrant verbatim: 7-day means vs the
28-day personal baseline, thresholded at 0.5 × the athlete's own between-night SD, and
**only HRV-down-with-resting-HR-up subtracts** — and only when the **convergence gate** is
open (≥1 Tier-1 signal already negative). A lone bad HRV morning is noted, never counted.
This is the single rule that stops the score behaving like Whoop, and it is why the watch
can never manufacture a bad day out of a late night or a glass of wine.

### 3a. Two rules on what supply may and may not do

Two constraints keep supply from lying — both added 2026-08-06 after a specific failure:
a big session can leave an athlete elated in the moment yet needing three to four days to
recover, so a good *feeling* must never read as recovered. On Rio's Aug-1 long run
(124-load), an "energized" tap scored the day **62 · Steady** under the old weights —
"recovered" while three days of load debt remained. The fix is structural, not a dial:

**Rule 1 — positive supply cannot pull the number below the load-driven need.** Demand sets
the floor of the recovery need. A dragging self-report (low mood, poor sleep, a niggle)
*deepens* the need at full weight — that's the evidenced early signal. But a *positive*
self-report can only raise confidence and nudge the read from "need — watch it" toward
"adapting well"; it can never produce "fresh" while acute load is still elevated. Concretely
the score clamps: `score ≤ base + demandPoints + max(0, positiveSupply capped)`, with the
positive-supply cap small. The recovery need is owned by the load; feeling good is not a
green light. *(In the shipped ledger this is enforced today by capping mood's upside —
energized +4, positive +2, matching a good night's sleep — while its downside keeps full
weight; the Aug-1 "energized" day now reads 57 · Worn.)*

**Rule 2 — within self-report, sleep and soreness lead; mood is the minor corroborator.**
The evidenced runner signals are sleep quality and soreness (Goldberg 2025); "mood" is a
proxy the app happens to collect and the input most contaminated by in-session affect (you
feel great *because* the workout went well, not because you're recovered). So mood carries
the smallest weight of the three, and "how the session felt" is not mood at all — it is
RPE, which belongs on the **demand** side (§7), not here. Sleep and soreness may move the
need; mood mostly annotates it.

---

## 4. The read — the relationship is the product

Demand and supply define four situations. The number still shows (band + receipt, exactly
as today), but the **headline sentence** is chosen by quadrant. That is what makes it a
recovery *need* and not a mood ring.

| | **Supply holding** | **Supply dragging** |
|---|---|---|
| **High demand** | *Adapting well.* Big block, nothing on the recovery side followed — the block is working. | **The one worth flagging.** Big block and your body is following it down. High confidence when words + overnight agree. |
| **Low demand** | *Fresh.* Nothing's asking much and nothing's dragging. | **The tell that it isn't training.** Light training, but the words are low — look at sleep, life, a niggle, not the miles. *(This was Rio's July knee week.)* |

The bottom-right cell is the one a load-only score structurally cannot produce — and it is
precisely the cell that caught the only real episode in the data. It exists only because
supply is a separate term that can speak while demand is quiet.

Copy stays inside the lint (`rest`, `ice`, `should`, `must`, `because`, `caused`,
`recovered`, `ready`, `risk` all banned). The read describes and states; it never
prescribes.

---

## 5. The math, assembled

The score keeps the shipped ledger's shape — base 50, named contributions, clamp 8…96,
band edges Flat/Worn/Steady/Clear — so it renders in the receipt you already have. The
reorganization is that contributions are **grouped and sourced** as demand vs supply, and
the read sentence is quadrant-driven.

```
supplyPoints = Σ Tier-1 contributions + gatedAutonomic     # words lead; watch corroborates
demandPoints = needIndex→points + sessionSpike + heatDose  # load hole, warm-up-gated
score        = clamp(50 + supplyPoints + demandPoints, 8, 96)
band         = Flat(<45) · Worn(<60) · Steady(<75) · Clear(≥75)
quadrant     = (demand high?/low?, supply dragging?/holding?)   # drives the sentence
confidence   = f(Tier-1 present, biometric baseline maturity, load-history weeks)
```

Every quantitative contribution is a deviation from the athlete's own baseline in units of
their own variability (the Daily Read §2a normalization), so `tanh`-saturated and gated at
0.5 SD — none of it reacts to a raw number. Qualitative contributions map through the
closed vocabularies already in `TrendsRecoveryFactors`.

Two points that stay fixed from the recalibration shipped this morning: carrying your
**usual** load costs 0 (it is the normal state of training, not fatigue), and positive
contributions are smaller than negative ones (recovery evidence is asymmetric — a rough
night reliably drags; a great HRV night doesn't reliably say "go harder").

---

## 6. What's evidenced vs. a judgment call

**On firm evidence** (citations in `recovery-trend-v2` §7, and confirmed against Rio's
data here): self-report out-predicts biometrics in runners; the fitness–fatigue balance is
the validated load framework while the acute:chronic ratio is not; single-day HRV is noise
and must be paired with resting HR; the session spike; sleep quality as the strongest
single input; population numbers explain ~15% of HRV variance, so every threshold is
personal. The **demand-was-silent-before-the-knee** finding is new and specific to Rio.

**Judgment calls, yours to overrule:** the EWMA time constants (7 / 42 days are the
standard but tunable); the exact need-index → points mapping; whether the headline is the
band word or the number (v2 argued the weekly card should be words-only; this daily score
is a composite, justified only because it shows its full receipt and carries confidence);
and whether to ship on Tier-1 supply + demand now and let the biometrics light up later
(the evidence says Tier-1 is already most of the signal).

---

## 7. The validation that closes the loop

The model earns "readiness indicator" only when checked against reality, and the ground
truth already has a column: **felt-RPE vs planned-RPE**. The test is whether a
high-demand / low-supply day actually runs harder than it should — felt-RPE above planned
on the following session. That column is empty today (0 rows), so the loop can't run yet;
the moment RPE extraction ships, re-run the proof script with the felt-RPE lane switched
on. Until then the model is an honest, legible summary — demand grounded in validated load
science, supply grounded in the runner self-report literature — but not yet a validated
predictor, and the copy says so through the confidence label.

---

## 8. Build sequence (mostly already specced or built)

1. **Turn the supply inputs on.** Mood write-through (the Today prompt still doesn't save
   a row — August coverage 3/11 days), then the Stage 2 pipeline (`daily_biometrics`,
   `daily_checkins`, the webhook branch — all authored, not pushed). Highest leverage;
   the model is only as good as the signals feeding it.
2. **Apply `stress_load`** so demand uses a real per-workout load unit instead of the
   duration×intensity proxy.
3. **Extend the ledger** with the demand grouping (§2), the warm-up gate (§2d), and the
   quadrant read (§4). The convergence gate and autonomic quadrant already exist in
   `TrendsRecoveryFactors` from the Stage 2 work.
4. **Wire felt-RPE extraction** and re-run the proof — the validation lane (§7).

Sequence-wise, the only genuinely new reasoning is the demand grouping and the quadrant
sentence — perhaps ~120 lines of deterministic, unit-tested Swift on top of the ledger
that already ships.

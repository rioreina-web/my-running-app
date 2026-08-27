# FITNESS PREDICTOR — LEARNING FROM DATA · APPLY

2026-08-27. Two questions, asked together, that turn out to be one question:
"how do we build real machine learning into this system" and "what training
signals actually show fitness and fitness change." You can't answer the first
without a clean (features, ground-truth outcome) table — and building that
table honestly answers the second, because it forces every candidate signal
to justify itself against a real outcome instead of a plausible story.

**The constraint that must be said first, or this plan is fantasy: n≈1-2
athletes, 5 races over 2 years, 0 confirmed.** No conventional ML — gradient
boosting, neural nets, anything that wants hundreds of labeled examples — is
honest at this volume. Building one anyway is exactly the failure mode this
whole audit has been diagnosing: sophisticated-looking machinery nobody can
validate, worse than the hand-tuned rules it replaces. So this plan is staged
explicitly by data volume, and the near-term work is the same regardless of
how many athletes ever join — it's the foundation every later stage needs.

---

## 0 · The one thing already proven to work here

`raceCurve.ts` already does real statistics: fits a per-athlete exponent by
least squares, then shrinks it toward a population prior (`GENERIC_EXPONENT
= 1.06`) in proportion to its own standard error — empirical Bayes, the
textbook tool for exactly this data shape (many units, sparse data per unit).
It gets more athlete-specific as evidence accumulates and degrades gracefully
to the population value when it doesn't. **This is the template for
everything below**, not a black box swapped in wholesale — every hand-set
constant in the system becomes a population prior + an individual deviation,
weighted by evidence, the same mechanism, extended everywhere.

Today the "population prior" for that one exponent is borrowed from running
literature, not fit from this app's own athletes — because there's only one
athlete with enough races to fit anything. That fact alone is most of the
answer to "why doesn't this learn."

---

## 1 · Foundation — the (X, Y) table, buildable now, useful at n=1

Nothing below is possible without this, at any N. Most ML efforts fail before
the algorithm stage, from never having a clean, non-leaking, honestly-labeled
dataset. This is that.

### Y — the label, and the guardrail that matters most

**Y must be a real-world outcome, never the model's own output.** The
temptation is to use `fitness_snapshots.predicted_10k_seconds` or the fitness
curve as a proxy label when races are scarce — don't. A model trained to
match its own prior's output learns to agree with itself, and reports the
agreement as accuracy. This is the exact trap `patterns.heat_sensitivity`
already fell into (finding §6.2, `FITNESS-SCALE-APPLY.md`) — a "measurement"
that was actually the adjustment the model itself applied, feeding back in.

The only clean Y: a **confirmed, conditions-normalized race result**.
`prediction_scores` (built this week) + G0.2 (multi-horizon) already produce
half of this. **Blocking issue, shared with G0.4: 5 race_results, 0
confirmed.** There is no Y at all until races are confirmed — this plan and
the PR-onboarding work depend on the exact same fix.

### X — the features, and they mostly already exist

`_shared/fitnessInputs.ts`'s `asOf` mechanism already assembles point-in-time-
correct inputs, and `fitness_snapshots.diagnostics` already captures the full
intermediate feature vector (`pre_curve_pace`, `anchor_pace`, `weekly_miles`,
`quality_density`, `ef_verdict`, `curve_alpha`, `race_curve.*`, `pr_floor.*`)
for every prediction ever made. **The features are not the gap. Persisting
them as a queryable training table is.**

### Deliverable — `fitness_training_examples`

A migration + a script that runs `scripts/replay-fitness.ts` across every
athlete with a confirmed race, and persists one row per (athlete, asOf date,
forward-looking race outcome, horizon): the full diagnostics feature vector
as `jsonb`, plus `actual_seconds`, `error_pct`, `horizon_days`. Not a new
concept — it's the replay harness's output, kept instead of printed.

**Why this matters even at n=1:** it turns "how good is the model" from a
script you remember to run into a table you can query, it's the substrate
every rung below consumes, and it's honest at n=1 in a way a fitted model
cannot be — a table just accumulates.

---

## 2 · The signal catalog — what actually shows fitness and fitness change

Cataloged against this database's real state (checked 2026-08-27), not
assumed. Status legend: **live** = populated and usable now · **latent** =
computed, sitting unused by the predictor · **blocked** = a known,
previously-diagnosed structural gap · **missing** = not built.

### Direct fitness measurements — rare, near-ground-truth

| Signal | Status | Note |
| --- | --- | --- |
| Confirmed race result | **blocked** | 5 rows, 0 confirmed — the Y-source gap above |
| Benchmark / time-trial session | **missing** | see §4 — this is the fix for reverse causality, nothing else is |

### Proxy fitness measurements — frequent, confounded

| Signal | Status | Note |
| --- | --- | --- |
| HR-pace efficiency | **live**, 211/310 workouts | not heat-neutralized; confounded with mood/freshness — see [[project_recovery_signal_dead_ends]] |
| HR drift within a session | **latent** | computed in `trainingZoneSignal.ts`, carried on every `ZoneEstimate` — its own header says "reported, not applied" |
| Long-run decoupling | **latent** | computed in `athleteProfiles.ts` — one of the four modules with tests and zero production importers |
| Resting HR | **live**, 212/212 days | full coverage, currently unused by the predictor at all |
| Sleep duration | **live**, 174/212 days | unused |
| HRV | **blocked**, 0/212 | watermark issue from [[project_apple_health_biometrics]] — still unresolved as of this check. Do not design around it yet |

### Training dose signals — "what workouts and efforts" concretely means

| Signal | Status | Note |
| --- | --- | --- |
| Rolling volume (7/14/28/42d) | **live**, fully populated | used today only via the hand-set 40mi/wk denominator (G1.1) |
| Quality density / hard-effort minutes | **live** | populated, used in decay's maintenance factor |
| ACWR / monotony / strain | **live** | populated, currently injury-focused only — unused as a fitness-response feature |
| Structured rep geometry (`parsed_structure.blocks`) | **live** | the richest dose signal; already `trainingZoneSignal.ts`'s substrate |
| Felt RPE | **live**, 107/311 | up from 0 in earlier project notes — a real, recent improvement. Subjective cross-check against objective pace |
| `rep_signal` | **blocked**, 1/310 | the same pg_net/vault auth gap from [[project_fitness_stress_load]] — still open |

### Confounds — must travel WITH dose, or dose-response is unreadable

| Signal | Status | Note |
| --- | --- | --- |
| Mood | **live** | per-log label + `recent_blocks.mood_summary` |
| Niggle/injury mentions | **live** | `recent_blocks.injury_mentions` |
| Heat/dew point exposure | **live**, mechanism-verified, magnitude uncertain | see §4b — do not trust a whole-session heat-adjusted number as ground truth |
| Life/stress context | **partial**, 1/2 athletes | `athlete_state.life_context` — thin, not load-bearing yet |

**The pattern worth naming:** most of the raw material already exists. The
predictor's problem was never "we don't measure enough" — HR drift,
decoupling, resting HR, and sleep are all sitting in the database, computed,
correct, and read by nothing. The gap is a feature table that puts them next
to a real outcome, not more instrumentation.

---

## 3 · The rung ladder — how learning actually enters, staged by N

Jumping to the top rung now, with n≈1-2, is the mistake this plan exists to
avoid. Each rung is a real, useful step; none require the next to exist.

### Rung 0 — now (n≈1-2 athletes)

No per-athlete fitting beyond what `raceCurve.ts` already does. The available
move is **making the ~20 hand-set behavioural constants (`FITNESS-SCALE-
APPLY.md` §7) into a named, versioned parameter registry** — same pattern as
`GENERIC_EXPONENT` / `EXPONENT_PRIOR_SD`, applied to the maintenance-factor
weights, decay rate, plausibility band, endurance-shading dial. This fits
nothing yet. It's the scaffolding every later rung needs, and it converts
"which numbers are hand-set vs. evidence-based" from a fact buried across 92
literals into a queryable one.

### Rung 1 — n≈5–20 athletes, each with ≥1 confirmed race

Enough for one small, heavily regularized regression: 3–5 hand-picked
features (recent volume, quality density, EF trend, anchor recency, heat
exposure) predicting race-day error. **Fit and validate by leave-one-ATHLETE-
out, never leave-one-race-out** — the latter leaks an athlete's own future
into their own past and would report an accuracy that isn't real. Replaces
2–3 of the most-asserted constants (the maintenance-factor blend weights, the
base decay rate) with fitted coefficients. This is the first moment the
system is honestly "learning from data" rather than running fixed rules.

### Rung 2 — n≈50–200+ athletes

The `raceCurve.ts` pattern, generalized to every remaining hand-set constant:
population-level partial pooling for heat sensitivity, decay-by-training-age,
and the maintenance-factor weights — each shrinking a thin athlete's own
evidence toward a prior fit from real athletes instead of a textbook number.
**This is the actual answer to "built-in ML"** — not one model swapped in for
the pipeline, but every current rule becoming a partially-pooled, evidence-
weighted parameter, using the one mechanism already proven here. It's also
what makes a brand-new athlete's cold start *good*: the population prior they
inherit is fit from people like them, not asserted from a paper.

### Rung 3 — large N, speculative, not scoped

Flexible/nonlinear model classes (gradient boosting, etc.) for genuinely
nonlinear sub-problems — dose-response shape, will-this-block-produce-
improvement — where interpretability matters less. **Named here so it isn't
reinvented under pressure later, not because it's next.** Attempting this
before rungs 0–2 exist reproduces the exact failure this plan is designed to
prevent.

---

## 3b · Time structure — fitness gains LAG the training that caused them

Raised directly (2026-08-27): raising mileage doesn't make you fitter on
contact — often the opposite shows up first (more fatigue), and the real
aerobic adaptation shows up weeks later, more visibly at longer distances.
This is real, it's a known gap in §1's design, and it turns out to be
already-specced-but-unbuilt work in this exact codebase.

**`outputs/fitness-score-stress-load-design-2026-07-31.md` Phase 2** is the
Banister/Coggan fitness-fatigue model: daily EWMA of `stress_load` split into
**CTL** (42-day time constant — "fitness"), **ATL** (7-day — "fatigue"),
**TSB = CTL − ATL** ("form"). Phase 1 (per-workout `stress_load`) shipped
2026-07-31. Phase 2 was never built. The design doc's own open question —
*"42/7 is the Coggan default; may want to tune τ for runners on this
corpus"* — is precisely the question Rung 1/2 (§3) exists to answer once
there's data to fit it from, rather than assert it from a cycling-derived
default.

**Why §1's feature design was wrong to leave this out.** My own ad hoc
volume-vs-EF check compared a block's OWN volume to that SAME block's EF —
implicitly testing "does this week's dose show up in this week's fitness,"
which the fitness-fatigue model says is close to the wrong question. A
volume increase can show WORSE short-term readouts (accumulated fatigue) while
setting up better ones several weeks out. Same-window correlation isn't just
confounded (§4) — it's testing the wrong time alignment to begin with.

**Concrete change to §1's `fitness_training_examples` table:** dose features
must be captured at multiple lags relative to the label date, not one
"current block" — at minimum CTL/ATL/TSB once Phase 2 ships (or, until then,
trailing volume/quality at 1–2wk / 3–6wk / 8–16wk windows as a manual stand-
in). Any future fit (Rung 1+) must test which lag predicts the outcome best
as a free parameter — never assume the same-window hypothesis is the right
one to start from, which is the mistake the earlier ad hoc check made.

**Sequencing note:** building CTL/ATL/TSB is not this document's scope and
isn't required to start §1 — the trailing-window stand-in covers the same
structural requirement adequately for Rung 0/1. But if Phase 2 gets built for
its own reasons (the Trends fitness-curve motivation in that design doc), the
training table should switch to consuming it directly rather than maintain
two lag implementations.

## 4 · The reverse-causality fix — needed at every rung, fixed by neither

Direct callback to the earlier finding: a quick correlation of `recent_blocks`
volume against HR-pace efficiency looked suggestive (EF tracked mileage
almost monotonically across six 4-week blocks) and could not be trusted —
n=6, and EF is measured from the same runs that constitute the training dose.
A block where the athlete felt flat produces both lower volume and worse
efficiency; feeling bad caused both, volume caused neither. **No amount of
modeling sophistication fixes this. Better fitting on confounded data just
produces a more confident wrong answer.**

Two things actually fix it, and only one is buildable now:

- **An independent benchmark measurement, not made of the training being
  evaluated.** One repeatable protocol — e.g. a fixed 3×10min threshold
  effort, same course or treadmill, done monthly — stored in its own table so
  it can never be confused with or contaminate ordinary training logs. ~30
  minutes/month per athlete. Buildable now; the single highest-leverage new
  instrumentation in this whole plan, because it's the only thing that turns
  "training and fitness moved together" into a claim that could be wrong.
- **Enough athletes to separate confounds statistically via covariate
  adjustment** even from passive data. This is Rung 2's job, not available
  sooner.

### 4b · Heat's real channel, and how this codebase already fooled itself once

`signature-miner-pilot-rio-2026-07-07.md` is the cautionary tale to build
around, not a vague worry. First pass, whole-session averages: quality
sessions "24 s/mi slower in hot months," passed a statistical gate. Re-run at
the **rep level** (true work-rep pace + HR, not session averages): the pace
finding was **retracted as an artifact** — true rep pace was identical, hot
vs. cool (5.191 vs 5.187 m/s). What survived, split-half validated: heart
rate ran **+3 bpm higher at matched pace** in heat. The physiological cost is
real — it's paid in cardiac drift, not necessarily in pace, and a whole-
session view conflates the two by burying reps under recoveries and warmup.

*(Correcting course from earlier in this conversation: I'd cited a specific
"model over-credits heat ~8.8 s/mi vs. a controlled ceiling of 3.9 s/mi"
figure from an earlier session's memory note. I could not re-locate that
number in a source doc this session and should not have stated it as
precisely as I did. The rep-level finding above is freshly verified against
an actual file and is what this plan relies on; the older figure needs
re-verification against its original source before being trusted again.)*

**Concrete requirement for §1's training table:** a heat-adjusted EF or pace
value may only enter as a feature if it was computed from matched-pace or
matched-effort **rep-level** comparisons — never a whole-session average. Any
value that can't clear that bar gets stored with its correction magnitude and
channel (HR-adjustment vs. pace-adjustment) as explicit companion fields, so
a future fit can learn to weight or discount it rather than silently
inheriting a bias this codebase has already caught itself making once.

---

## 5 · Concrete near-term deliverables

Buildable this week, useful regardless of how many athletes ever join:

1. **`fitness_training_examples` table + backfill script.** Turns the replay
   harness's output into a persisted, queryable dataset instead of a script
   run. The foundation everything else in this doc consumes.
2. **Confirm race results.** Shared blocker with G0.4 — without it there is
   no Y, for this plan or the PR floor. The single highest-priority item.
3. **Wire HR drift + decoupling into the feature vector.** Real, computed,
   currently unused signals — `trainingZoneSignal.ts` and `athleteProfiles.ts`
   already carry them on every estimate.
4. **Wire resting HR + sleep into the feature vector.** 212/212 and 174/212
   filled, completely unused today. Correlational only until (5) exists —
   label clearly, don't overclaim.
5. **Design + ship the benchmark-session protocol.** Schema + a periodic
   prompt/nudge + storage isolated from ordinary training logs. The fix for
   §4, and probably the single most valuable new thing in this document.
6. **Turn `FITNESS-SCALE-APPLY.md` §7's constant table into a real, versioned
   parameter-registry module** (Rung 0). No behavior change — scaffolding for
   Rungs 1–2.
7. **Lag windows + rep-level heat gating in the feature table (§3b, §4b).**
   Not separable from item 1 — a training table built same-window and on
   whole-session heat corrections would need rebuilding, not extending, once
   this is caught. Build it in from the first row.

None of these require more athletes to be worth doing. All of them are worth
less without item 2.

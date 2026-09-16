# CURRENT FITNESS — THE ASSEMBLED EVALUATION

Session of 2026-08-14/15. This is the master doc: it ties together the pieces
designed, measured and shipped this week into one evaluation, decides what was
open, and hands Claude Code a build order. It supersedes nothing — it *binds*:

- `REP-RECOVERY-SCORE-APPLY.md` — rep shape + recovery score (calibrated)
- `LOAD-MODEL-OPEN-APPLY.md` — load model state; §1 of it (quality-load
  bucketing) SHIPPED 2026-08-14
- `_shared/fitnessSignal.ts`, `_shared/fitnessPrediction.ts` — existing signals

**Decisions locked 2026-08-15 (Rio):** final rep reported separately, never in
the trend · surfaces = Key Session detail + an Ask analyzer, no new tab ·
heat = raw/raw + disclosure guard (see §3.3) · this doc first, TypeScript next.

---

## 0 · One name, three questions

"Current fitness" is three questions wearing one name. The product answers all
three, **separately, and never blends them into one score**:

| question | output | moves | owner |
|---|---|---|---|
| **Capacity** — what could I race today? | a time + confidence tier + PR context | slowly (weeks) | §1 |
| **Trajectory** — building or eroding? | a direction + evidence | weekly | §2 |
| **Readiness** — can I express it today? | push/pull | daily | **v1.5 Recovery pillar — out of scope here** |

Signal routing, and the rule that keeps the model honest:

| signal | capacity | trajectory | readiness |
|---|---|---|---|
| race results | **sets the number** | anchors the curve | — |
| normalized paces | corroborates | supports | — |
| EF / rep shape | weak | **primary** | — |
| TLS / ACWR | **never** | plausibility only | strong |
| volume | never | supports | supports |
| mood | never | early warning | **primary** |

**Load is dose, not response.** TLS can make a change in capacity more or less
*believable*; it can never *raise* the capacity estimate. This is the line that
separates this model from CTL-style "fitness" curves that reward digging a
hole. Mood never moves capacity either — a bad week widens the error bar
(confidence), it does not mark the athlete slower.

---

## 1 · Capacity

### 1.1 The evidence ladder

Ranked. A higher rung sets the number; lower rungs corroborate or challenge it;
staleness — not a lower rung — is the only thing that displaces a rung.

1. **A race.** Confirmed, distance known.
2. **A race-equivalent effort** — time trial, or a self-limiting continuous
   block (a 6-mile tempo says something about capacity; 10×400 almost nothing).
3. **Normalized pace at a known cost** — hard reps, heat/grade-corrected,
   HR-verified. Weaker: depends on willingness that day.
4. **EF trend** — moves the number *between* anchors, small steps only. Sets
   direction and rate, never level.
5. *(volume, TLS)* — **never touch the number.**

Between anchors, capacity **drifts** (driven by rungs 3–4); it never jumps.
Only a new rung-1/2 event may jump it.

### 1.2 Decay — two knobs, opposite directions

- **Confidence decays with anchor age. Always, unconditionally.**
- **The value decays only on evidence of detraining** — missed volume, EF
  slipping, no quality work (`detectDetraining` already exists in
  `fitnessPrediction.ts`).

A runner who raced in February and trained consistently since is *fitter than
her anchor*, at lower certainty. A runner who raced in February and stopped is
slower AND less certain. The two knobs moving independently is the honest
statement, and the UI should be able to say both halves.

### 1.3 What the live data says (pulled 2026-08-15)

`race_results` holds five detected races; the working anchor is the **10K PR
31:20 on 2026-02-07** — 27 weeks old. Last night's `fitness_snapshots` row
(nightly job is healthy): Medium confidence, source "race (10K) + pace
segments · v2", 49 workouts, predictions mile 4:28 · 5K 15:24 · 10K 32:00 ·
half 1:10:32 · marathon 2:29 vs PRs 15:05 · 1:08:39 · 2:22:43.

Two findings worth acting on:

- **Every race has `confirmed_at = null`.** The detection surface works; the
  confirmation loop hasn't happened. An unconfirmed anchor should cap the
  capacity tier at Medium — a rung-1 anchor the athlete never confirmed is
  really rung 1.5. (New rule; add to the tier logic.)
- The April 10K (33:02) looked like conflicting rung-1 evidence — 100s slower
  than the February PR. It isn't, and the reason is the rule this section was
  missing. It was the **Cap10K** (Rio, 2026-08-15): hilly, hot, humid. The
  measured conditions confirm it emphatically — race-hour weather was
  **69°F / 68°F dew point / 98% humidity** against February's 47°F / 36°F dew,
  and the activity carries **~100m of climb**. Normalizing with the app's own
  models (heat ≈ 2.5–3.5% via the measured coefficient / dew-point model,
  elevation ≈ 50–90s net for ~100m gain on a rolling course) puts the
  neutral-equivalent at roughly **30:45–31:30 — bracketing the anchor.** The
  two races *agree*; there is no detraining signal in April.

  **The rule: rung-1 evidence is compared only after conditions
  normalization.** A raw race time is course + weather + fitness; only the
  last part is capacity. Heat comes from `weather_actual` (already stamped on
  the linked `training_logs` row by `fetch-workout-weather`), elevation from
  the activity streams, both through models that already exist
  (`pace-heat-adjustment.ts`, `pace-grade-adjustment.ts`). Note
  `race_results.conditions` is **null on every row** — the schema anticipated
  this and nothing populates it. Auto-stamp it at detection time; let the
  athlete override at confirmation ("hilly course", "brutal day"). Most recent
  race wins the anchor role *only among conditions-normalized times*; the
  better older race stays as PR context regardless.

### 1.4 Presentation (existing hard rule #7, unchanged)

One number + HIGH/MEDIUM/LOW tier + lifetime PR alongside. Marathon/half
rounded to the minute. Never a bare projection.

---

## 2 · Trajectory

Two instruments, one direction. Both computed, both windowed 4wk-recent vs
8wk-baseline, both gated before they may speak.

### 2.1 Efficiency (level + drift) — `fitnessSignal.ts`, keep as is

Speed-per-heartbeat by comparable-effort bucket. Raw pace ÷ raw HR (§3.3).
Direction called only past `EF_DIR_PCT = 1.5%`. Duration is a **gate**
(≥300s in band), never an input — fold volume or rep length into the ratio and
it becomes a second load score.

Changes to the current module:

- **Drop the interval bucket from EF.** Measured 2026-08-14: reps under ~90s
  never reach an HR plateau (the 200s session: 0/8 settled, hrr30 *negative*
  on 4 of 8, true peak up to 20s after the rep ends). Threshold and easy carry
  the EF read; short reps are load, not cost.
- Raise the EF rep floor to **≥90s AND hrSettled**, matching the rep-score gate.

### 2.2 Rep shape + recovery — NEW, spec in `REP-RECOVERY-SCORE-APPLY.md`

Per rep: `hrPeak`, `hrr60`, `hrAtNextRepStart`, recovery context. Per session:
one level (first valid rep's hrr60) + four slopes (pace, HR-cost, recovery,
carryover), each reported as total change across the set.

**Final rep (decided):** the trend is computed over reps 1..n−1; the last rep
is its own fact line — *"closed with your fastest rep (5:17)"* — never folded
into the slope. A kick is reserve, not noise, and a linear fit calls it
"fading". Symmetric: a collapsed final rep also reads as its own fact
(*"last rep 20s off"*), which the trend would otherwise dilute.

Session read = the combination (all four axes on the reference 10×1km agreed:
recovery −11.5, carryover +16.1, HR +5.6, pace fading → *over the edge*,
HIGH confidence — a session invisible to every pooled metric in the codebase).

### 2.3 The drift term (added 2026-08-15 — "training could also improve
### fitness, not just suppress decay")

Rio's objection, and it is correct: as built, the forward read is asymmetric.
Decay fires on detraining evidence; improvement is limited to a training-anchor
nudge that filters itself out (a training anchor must be FASTER than the
race-equivalent to count, and rep paces parse conservative — so a whole
improving block can register as nothing). The model can lose fitness between
races but can barely gain it. For an athlete mid-build, improvement between
anchors is the COMMON case, and the ladder always said drift runs both ways.

**What counts as improvement evidence — response, never dose:**

| evidence | rung | why it counts |
|---|---|---|
| EF trend up (threshold/easy, confidence ≥ medium) | 4 | same speed, cheaper — the definition of fitter |
| Matched key sessions faster at same cost (rep-1 vs rep-1, same structure) | 3 | the controlled experiment training data offers |
| Demonstrated reps faster at known HR, heat-adjusted | 3 | direct pace evidence |
| Volume / TLS / streaks | — | **never** — dose is not response |

**The mechanism — drift, not ratchet:**

- EF converts directly: EF is speed-per-beat, so a +1.5% threshold-EF delta
  licenses ≈ 1.5% pace drift on the anchor (≈ 5 s/mi at these paces).
  Drift applies HALF the licensed delta (evidence discount), and only at
  medium+ confidence with the heat guard silent.
- **Total drift between anchors is capped at ±3%** — deliberately the same
  number as the existing displacement cap, so training evidence in aggregate
  can never move the estimate further than one race would. A race BANKS the
  drift: post-race, drift resets to zero around the new anchor.
- **Recomputed, never accumulated.** Drift is a function of CURRENT evidence
  vs the anchor-era baseline, recomputed each snapshot. If the EF signal
  fades, the drift collapses with it. This is the anti-ratchet lesson
  (2026-07-16: one transient fast estimate persisted ~4 months because
  snapshots fed snapshots) applied forward: improvement is a live hypothesis,
  not a banked gain. Only a race banks.
- Downward drift uses the same channel — EF declining at medium+ confidence
  drifts the number slower, replacing blunt time-decay with evidence-based
  decay for athletes who are still training but fading.

**Honest application to the athlete asking (2026-08-15):** his drift today is
≈ 0 — threshold EF is flat (+0.5%, under threshold), because he is
deliberately running his quality 8 s/mi easier at 5 bpm lower while volume
climbs. The model SHOULD say "maintaining" right now; volume alone is dose.
The payoff comes at sharpening: when the reps come back to ~5:10 at the same
HR, EF jumps, the drift term lifts the prediction BEFORE he races — which is
exactly the product moment ("your prediction improved because your workouts
got cheaper"), and it is currently impossible.

**Sequencing:** wire AFTER predictor parity is restored
(PREDICTOR-ANCHOR-PARITY-APPLY.md) and on BOTH platforms in one change, so
the drift term's effect is measurable against a correct, agreeing baseline.

### 2.4 The durability gap (flagged, not built)

Decoupling fires only on `workoutKind === "long_run"`. Steady runs and
progressions — the best durability instrument there is — get no read. Separate
spec, after this ships. Do not widen the gate casually; it is load-bearing
(easy runs must not acquire scores).

---

## 3 · Confidence — the gates that make it honest

The posture throughout is the Ask surface's: **facts always render; the
verdict is the bonus.** At LOW confidence the numbers still show and the
verdict is withheld.

### 3.1 Sample gates

| gate | value | why |
|---|---|---|
| EF band minimum | 300s | one rep is not a reading |
| rep duration for hrr | ≥90s + settled | HR lag — measured, emphatic |
| slopes | ≥4 usable reps (HIGH: ≥6) | can't fit a line on 3 points |
| EF windows | ≥2 sessions recent AND baseline | existing rule, keep |

### 3.2 Sensor flags (each drops the session to LOW)

- **Pace/HR anti-correlation** — faster reps reading lower HR (caught Rio's
  5×4min: fastest rep 24 bpm below a slower one)
- **Backwards carryover** — recovering *deeper* mid-session (same session:
  117→91; bodies don't do that)
- **Capped/frozen HR** — never exceeds ~140 at quality pace, or frozen runs
  ≥60s (caught 06-01: EF 1.697 outlier, HR ceiling 139 all run)
- **Optical vs strap** — mark optical-source recovery readings lower
  confidence if device type is detectable *(open item)*

Two of these fired on real sessions within one calibration pass. They are not
theoretical.

### 3.3 Heat — resolved: raw/raw + disclosure guard

Measured on Rio's own 12 weeks (full method in
`REP-RECOVERY-SCORE-APPLY.md` §2.5): **−1.5% EF per 10°F** (doubles + OLS
agree), mechanism **+1.2 bpm per 10°F** at matched pace, R² 0.03–0.06. The
actual window bias is −0.31% against a 1.5% threshold → **do not correct; a
±50%-uncertain coefficient correcting a 0.3% bias adds error.**

Guard instead: session-weighted mean run-time temp per window; if
`|Δtemp| × 1.5%/10°F > 0.5%` (⅓ of `EF_DIR_PCT`), widen the tier or print the
condition — *"this comparison spans a 24°F swing."* Fires exactly where it
must: windows straddling seasons, athletes without a fixed run hour, real
winters. **Never enable `useHeatAdjustedPace` inside `fitnessSignal`** — pace
corrected over raw HR bends the ratio twice the same way.

*(Prerequisite: confirm `weather_actual` backfill coverage over the trailing
12 weeks — a window with missing weather under-reports its own bias.)*

### 3.4 Mood and load enter here — and only here

Two weeks of `tired`/`struggling` while EF is flat does not say "slower"; it
says "the paces held but the cost is rising" — a wider band, one tier down.
Heavy TLS block during the recent window: same treatment (EF dips under
accumulated load are load, not lost fitness; EF pops during taper are
freshness). Both are confidence modifiers with a stated reason, never value
modifiers. Surface-never-interpret, same as niggles.

---

## 4 · Surfaces (decided)

### 4.1 Key Session detail — the per-session shape

On the workout detail of any scored quality session: the rep strip (pace + HR
per rep), the four slope facts, the recovery level, the final-rep close line,
and the confidence tier with its reason when not HIGH. No verdict sentence at
LOW — facts only.

### 4.2 Ask analyzer `current-fitness` — the windowed verdict

One new file in `_shared/analyzers/` + one registry line, per the Ask
architecture. Layer 1 (deterministic, no model) assembles:

```
FactLine[]:
  capacity   — anchor (type, time, age), predictions + tiers + PRs
  trajectory — EF by bucket (level, delta, direction), latest rep-shape read
  confidence — tier + every gate/flag/guard that fired, by name
Coverage     — sessions used / skipped and why
Chart        — EF trend with race anchors marked
```

Narration is two sentences over those fact lines under the existing guard —
if a number is not in `facts`, it does not exist. **No prescription** — the
verdict describes ("held pace at rising cost"), never advises ("back off").
`ask-narration` golden-family rules apply before launch (cassettes + CI entry).

---

## 5 · Storage — evidence ledger, derived verdicts

**Store evidence, derive the verdict.** The counter-pattern already bit twice
(four disagreeing key-session rules; bucketed vs continuous weights).

```
fitness_evidence   append-only: kind (race | race_equiv | normalized_pace |
                   ef_window | rep_shape), date, value, conditions,
                   source_ref, quality flags
fitness_estimate   derived: value, confidence, as_of, anchor_evidence_id,
                   model_version
```

- **Recomputable history** — when the model improves, re-derive every past
  estimate instead of living with a seam in the chart. The model WILL change.
- **`model_version` on every row** — so a visible jump can be attributed to
  the athlete or to the model. Without it the product can't debug itself.
- **Explainability free** — "why 32:00?" resolves to an evidence row + the EF
  drift since, no parallel explanation logic.
- Per-rep series: JSONB array on `workout_features`, written by
  `compute-workout-features` at ingest — **never computed on read**
  (`external_streams` is the #1 cost in the app, per the 08-13 cost audit).
  One copy of the formula, `_shared/`, pure functions, tests.

---

## 6 · Build order — status as of 2026-08-15

1. ✅ **`_shared/repSignal.ts` — BUILT.** Three layers (windows from laps ·
   series from stream · score), all pure. `repSignal.test.ts`: 11 tests green,
   and the three calibration sessions ARE the contract — 10×1km reproduces
   over-the-edge/HIGH with the final-rep kick reported separately, 5×4min
   reproduces withheld/LOW with `carryover_backwards`, 200s reproduces
   not-scored on the duration gate. Fixtures generated from the real
   2026-08-14 analysis (`repSignal.fixtures.ts`), not hand-typed.
2. ✅ **Persistence — BUILT, migration NOT applied.**
   `20260815160000_workout_features_rep_signal.sql` (append-only JSONB column;
   apply via `supabase db push` from a committed SHA — hard rule #9, never the
   dashboard or MCP). `compute-workout-features` wired: the expensive stream
   read is gated by a cheap lap check (≥4 candidates ≥90s), uses run-hr-trace's
   exact two-path select, fails additive (a rep_signal error never sinks the
   row), and the missing-column strip guard covers the new field. Typechecks
   clean against the full dependency tree.
3. ✅ **`fitnessSignal` amendments — BUILT.** Interval bucket retired from EF
   (type kept for persisted-state compat, documented); `EF_REP_MIN_S = 90`
   per-rep floor on threshold pooling. 7/7 tests green, including a rewritten
   bucketing test asserting interval sessions now contribute nothing.
   *Heat guard NOT built* — still blocked on the weather-coverage check (§3.3).
4. ◐ **Ask analyzer `current_fitness` — BUILT; iOS strip NOT.** Registered in
   the analyzer registry (chip appears via `__catalog__` — no app release).
   Reads state + the persisted rep_signal only, never streams. Withheld
   verdicts surface as facts with `tone: watch`; coverage confidence is the
   worst of its parts. The Key Session detail rep strip is Swift work for an
   Xcode session — reads the same persisted JSONB.
5. ☐ **Evidence ledger** — not built. Tables + backfill from `race_results` /
   `fitness_snapshots`; `model_version`; unconfirmed-anchor tier cap;
   conditions normalization at anchor comparison (§1.3).
6. ☐ **Backfills owed:** `quality_load` re-run (stored scores still on the
   stepped scale); weather coverage audit; rep_signal history backfill (run
   compute-workout-features over past quality sessions once deployed).

Deploy order for what's built: **migration first** (`db push`), then the edge
functions, then confirm the chip appears in Ask. Before the narration layer
touches `current_fitness` output, hard rule #3 applies — `ask-narration` is a
golden family and still has no cassettes.

---

## 7 · Worked example — Rio, evaluated 2026-08-15

What the assembled evaluation outputs today, every number real:

```
CAPACITY                                          confidence: MEDIUM
  anchor    10K 31:20 · Feb 7 2026 · 27 weeks old · unconfirmed
  says      10K 32:00 ±48s · half 1:10 ±2m (PR 1:08:39) ·
            marathon 2:29 ±6m (PR 2:22:43) · mile 4:28
  why not high  anchor age ↑ · anchor unconfirmed · summer EF cannot
                corroborate faster than the anchor (see trajectory)
  corroborated  Apr Cap10K 33:02 @ 69°F/68°F dew/98%RH + ~100m climb →
                conditions-normalized ≈ 30:45–31:30, brackets the anchor.
                Two rung-1 events agree; no detraining signal.

TRAJECTORY                                        direction: FLAT
  key-session EF   1.831 recent vs 1.822 baseline → +0.5% (< 1.5%) — flat
  what did move    intensity, not efficiency: 5:22@164 vs 5:14@169 —
                   8 s/mi easier at 5 bpm lower. Deload shape, not decline.
  latest rep read  10×1km Aug 11 — held ~5:21, HR +5.6, recovery closing
                   −11.5, carryover +16.1 → over the edge, HIGH conf,
                   closed with fastest rep (5:17)
  heat guard       Δ+2.1°F between windows → bias −0.31% → silent, correctly

READINESS         not evaluated (v1.5)

EXCLUDED          Aug 6 "5×4min" (2 sensor flags) · Jul 24 "200s"
                  (duration gate) · Jun 1 (capped HR)
```

The honest sentence, and the one the narration layer should be able to
produce from the facts alone: *"Racing shape is roughly where February left
it — the anchor is aging faster than the evidence is moving. The last hard
session was executed at the edge and finished with something left."*

---

## 8 · The assembled formula — every variable, one channel each
### (added 2026-08-15: "how do we have it be part of the fitness score and
### consider all the variables?")

The governing rule that keeps a seven-input model honest: **each variable
enters through exactly ONE channel, exactly once.** The moment a variable
influences two stages, it gets double-counted and the score becomes
un-debuggable. This table is the contract — any PR that gives a variable a
second entry point is wrong by definition:

| variable | its ONE channel | may it touch the number? |
|---|---|---|
| races (conditions-normalized) | **sets the level** (anchor) | yes — the only thing that sets it |
| demonstrated paces / reps (heat+grade adjusted) | drift evidence (rung 3) | yes — bounded drift |
| efficiency (EF trend) | drift evidence (rung 4) + trajectory label | yes — bounded drift |
| rep-shape / recovery score | trajectory label + drift corroboration | indirectly |
| volume | detraining detection + drift plausibility gate | **never directly** |
| TLS / training load | **confidence width + drift plausibility gate** | **never** |
| mood | **confidence width** (2wk tired/struggling streak → widen) | **never** |
| heat / weather | input normalizer + comparison guard | only via normalization |
| sensor / device (hrSource, flags) | confidence of the evidence it produced | never |
| anchor age + confirmation | confidence tier | never (value decays only on detraining) |

### The five-stage pipeline

```
STAGE 0 · NORMALIZE          every input cleaned before anything reads it
  races        → raceNormalization (heat + elevation)          [built]
  reps/paces   → heat-adjusted, grade-adjusted                 [built]
  EF           → raw/raw + heat disclosure guard               [built + guard specced]
  sensor       → flags + hrSource stamped                      [built]

STAGE 1 · LEVEL              base_10k
  anchor = pickAnchorIndex(normalized races)                   [built, wiring pending]
  decay only on detectDetraining evidence — never on age alone [exists]

STAGE 2 · DRIFT              fitness_10k = base_10k × (1 − drift)
  drift = 0.5 × EF_delta   (threshold bucket leads, easy fallback)
  gates: EF confidence ≥ medium · |EF_delta| ≥ EF_DIR_PCT ·
         heat guard silent · PLAUSIBILITY (below)
  clamp: ±3% total between anchors · recomputed, never accumulated
  a race BANKS drift and resets it                             [specced §2.3]

  THE PLAUSIBILITY GATE — where load and volume finally do their job:
    upward drift requires dose that could plausibly produce it
      (≥ maintenance-level training in the window — you cannot get
      fitter on nothing; a rising EF on no training is sensor drift)
    drift evidence is DISCOUNTED one confidence tier when ACWR sits
      outside ~[0.8, 1.3] — EF pops on taper freshness and sags under
      acute load; extreme training-stress-balance means the EF signal
      is partly measuring load state, not fitness (§ "EF and load are
      entangled", the original design note). Dose gates and shades
      believability. It never adds a single second to the number.

STAGE 3 · CONFIDENCE         tier + band width (where MOST variables live)
  start: anchor tier (age ↓, unconfirmed → cap MEDIUM)
  worsen for: mood streak · ACWR extreme · sensor flags/optical ·
              coverage holes (missing HR/weather) ·
              EF disagreeing with the anchor's direction
  every worsening carries its reason string — the tier can always
  answer "why not high?"

STAGE 4 · TRAJECTORY         a direction, never blended into the number
  improving / holding / fading from EF + rep-shape + matched sessions
  (readiness stays out entirely — v1.5)
```

### Why the headline number should stay a TIME, not a 0–100 score

The estimated 10K (or its pace) already IS the fitness score — it has units
the athlete can feel, it's checkable against reality (race it), and it can't
quietly re-index itself the way abstract scores do. A Garmin-style 0–100
hides the units precisely so it can't be falsified; ours should be
falsifiable on purpose. If a unitless number is ever wanted for UX, derive it
as a percentile against the athlete's OWN history (a view over
fitness_estimate rows) — a display transform, never a second model.

### Worked through today's real inputs (2026-08-15)

```
STAGE 0  Feb 31:20 → ~31:14 neutral · Cap10K 33:02 → ~31:53 neutral
STAGE 1  anchor Feb (penalized-recency on normalized times) → base ≈ 32:00
         detraining: none (78 mi/wk) → no value decay
STAGE 2  EF +0.5% < 1.5% gate → drift 0 (deliberate: quality run 8 s/mi
         easier during the ramp — the model must call this "maintaining")
         plausibility gate: would PASS on dose, but there is nothing to pass
STAGE 3  MEDIUM — anchor 27wk (↓) · unconfirmed (cap) · ACWR high-ish from
         the 53→78 ramp (band widened, with the reason attached)
STAGE 4  HOLDING — EF flat, latest rep session over-the-edge but closed fast
HEADLINE 10K ≈ 32:00 · MEDIUM · holding · PR 31:20 alongside
```

Every input visible, every input used, no input counted twice — and the
answer to "why does it say that?" is readable straight off the stages.

### Build reality check

Stages 0, 1, 4 are built (wiring pending on anchor normalization — both
platforms, one change). Stage 2 is specced (§2.3), not built. Stage 3 exists
in fragments (anchor tier, sensor flags) — the mood/ACWR widening and the
reason-string plumbing are new work. The evidence ledger (§5) is what makes
the whole stack recomputable and versioned; it remains the most important
unbuilt piece.

## Appendix · Constants (one table, one home)

| constant | value | provenance |
|---|---|---|
| `EF_DIR_PCT` | 1.5% | existing (`fitnessSignal.ts`) |
| `EF_BAND_MIN_S` | 300 | existing pattern |
| `REP_MIN_S` | 90 | measured — 200s session |
| `SLOPES_MIN_REPS` / HIGH | 4 / 6 | calibration |
| `REC_DIR_BPM` | 8 | 10×1km measured −11.5 |
| `CARRY_DIR_BPM` | 10 | 10×1km measured +16.1 |
| `PACE_DIR_MS` | 0.02 | ~2 s/mi |
| `HRCOST_DIR_BPM` | 2 | HR feed resolution ±1–2 |
| `HEAT_EF_PCT_PER_10F` | −1.5 | doubles + OLS, Rio May–Aug |
| `HEAT_HR_BPM_PER_10F` | +1.2 | matched-pace regression |
| `HEAT_DISCLOSE_FRACTION` | ⅓ of `EF_DIR_PCT` | fires at 0.5% |

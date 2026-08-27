# FITNESS PREDICTOR — FINISH G0 · APPLY

2026-08-27. Companion to `FITNESS-SCALE-APPLY.md`, which set the gates. This is
what is left to close G0, rewritten against **evidence** rather than against the
plan's assumptions — because G0.1 has now actually been run, and it moved three
of them.

**State: the work exists, passes 65 tests, and is uncommitted.** Everything below
is sitting in the working tree on `design/ds-sync`, one `git checkout` from gone.
Production still runs the 2026-08-18 code (`7ed8153`).

Remaining effort to close G0: **~1.5 days**, down from the plan's ~4 — G0.1,
G0.3 and G0.5 are built. What is left is mostly verification and three real
defects the replay exposed.

---

## 0 · What is in the tree right now

| file | state | gate |
|---|---|---|
| `scripts/replay-fitness.ts` (263 ln) | untracked | G0.1 |
| `_shared/fitnessInputs.ts` (473 ln) | untracked | G0.1 |
| `_shared/prFloor.ts` + `.test.ts` | untracked | G0.5 |
| `_shared/fitnessPrediction.ts` | modified (+242) | G0.3 + G0.5 wiring |
| `_shared/fitnessPrediction.test.ts` | modified (+54) | — |
| `compute-fitness-snapshot/index.ts` | modified (−337) | input assembly moved out |
| `FITNESS-SCALE-APPLY.md` | untracked | the plan |

`deno test --allow-all _shared/fitnessPrediction.test.ts _shared/prFloor.test.ts`
→ **65 passed, 0 failed**.

The 337 lines deleted from `compute-fitness-snapshot` are the point: production
and replay now assemble inputs through **one** `buildPredictionInput`. A replay
with its own fetch measures a sibling model, which is how you get a green
backtest for code that is not the code you ship.

---

## 1 · What the replay actually found  *(2026-08-26/27, first ever run)*

Reproduce:

```
SUPABASE_URL=https://aqdijapxmjqaetursrde.supabase.co \
SUPABASE_SERVICE_ROLE_KEY=$(grep '^SUPABASE_SERVICE_ROLE_KEY=' web/.env.local | cut -d= -f2-) \
deno run --allow-net --allow-env scripts/replay-fitness.ts \
  --user=03857bf3-6276-4634-b3cc-15cc6d0bc653 --from=2026-01-26 --step=1
```

`03857bf3-…` is the real 304-log account. `a7e57a71-1e57-…` is the 5-row
synthetic — do not score against it.

### 1.1 · The model is good, on n=2

| race | conditions | predicted, 1d before | actual | error |
|---|---|---|---|---|
| 2026-02-07 10K | ideal, adj 0% | 31:59 | 31:20 | **+2.07%** |
| 2026-04-12 10K | 69.3°F / 67.6° dew | 32:02 | 33:02 raw → ~32:23 neutral | **−1.08% vs neutral** |

Both inside ±2.1%. This is the first evidence the shipped model has ever had.

**The Feb score is the cold start**, and it changes G0.6. The account was twelve
days old with fifteen log rows and no race anchor; the path taken was
`training (intervalSession) + fitness profile`, **not** the `fastest workout ×
0.95` fallback the plan indicts. It landed 39 seconds off a 31:20. Do not delete
the cold-start path on the strength of a code comment — measure which branch
actually fires first.

### 1.2 · Only 2 of the 5 races can EVER be scored

The account's first row ever is `2026-01-26`. The 5K (Aug '24), half (Dec '24)
and marathon (Jan '25) were all created in a single retro batch in July 2026, so
a point-in-time replay standing on those dates correctly sees nothing.

**G0's exit criterion — "leave-one-out replay produces an error table over the 5
existing races" — is unachievable as written.** Not a harness bug; the harness
being right. Validation is n=2 and grows only as races happen.

### 1.3 · The estimate barely responds to training

Across the 56 days before the April race the estimate moved **ten seconds**, and
not monotonically:

```
-56d 31:57   -42d 32:03   -28d 31:54   -21d 31:53   -14d 31:54   -7d 31:58   -1d 32:02
```

Eight weeks of training moved the number ~0.3%. Anchor dominance plus damping.
This is now an observation instead of an argument, and it is the most important
thing the harness found: **if the estimate cannot move on training, the G1
constant work is tuning something structurally pinned.**

### 1.4 · Shipping the in-flight code barely moves the live number

Replayed forward to today against the stored snapshot:

| | 10K | marathon |
|---|---|---|
| live (2026-08-26, deployed code) | 32:01 | 2:29:18 |
| replay (in-flight code) | 32:07 | 2:29:02 |
| delta | **+6s** | **−16s** |

No absurdity, no regression. Note the marathon moves **16s** faster, not the
~60s G0.3 predicted from the era-clean ratio — because the April race is
*excluded* from the curve fit (§1.5), so the fit rests on four races, not five.

### 1.5 · `raceCurve` is live and behaving

```json
{"exponent":1.0566,"fitted_exponent":1.0533,"standard_error":0.02,
 "evidence_weight":0.5,"races_used":4,"distinct_distances":4,
 "excluded":[{"date":"2026-04-12","reason":"conditions correction 3.4% exceeds 2.5%"}],
 "generic_exponent":1.06,"tilt_vs_generic":-0.0034}
```

Four races, four distances, b = 1.0533 ± 0.0200, shrunk 50% toward generic 1.06.
The hot April race is correctly barred from *shape* fitting while still
anchoring. `diagnostics.race_curve` carries the whole derivation — read it
before theorising about any conversion.

---

## 2 · The three defects to close  *(~0.75d)*

### 2.1 — The 180-day weather window now silently weakens the PR floor  *(0.5d)*

Live `diagnostics.pr_floor` from today's replay:

```
floors: 10K   PR 1880 (2026-02-07)  floor 32:52  conditions_known: FALSE
        mara  PR 8563 (2025-01-19)  floor 2:30:52 conditions_known: FALSE
        half  PR 4119 (2024-12-08)  floor 1:12:38 conditions_known: FALSE
        5K    PR  905 (2024-08-08)  floor 16:00   conditions_known: FALSE
```

**All four false.** `weatherByDate` is built from the 180-day log window
(`fitnessInputs.ts:126,138`), and every PR on file is older than 180 days — Feb 7
crossed the line in August. So the floor uses raw times, which *loosens* it.

This is the same latent gap the anchor has ([[seeded-race weather window]] in the
model notes), now inherited by a second consumer. It is fail-open, not dangerous
— but it is systematically weakest exactly where you want it strongest: the 5K PR
was run at 72.4° dew (adj 3.68%), so its true floor is ~30s faster than the 16:00
being used.

- [ ] Fix at the source, not per-consumer: **G0.4's normalize-once-at-confirmation**.
      Store `neutral_seconds` + `conditions` on `race_result` at confirmation.
      Three call sites re-derive today; storing it once kills the window gap for
      the anchor, the floor, and `prediction_scores` together.
      **Still open, and genuinely coupled to the blocked confirm/dismiss UI** —
      there is no confirmation event to hang it on today (all five races are
      unconfirmed `source='detected'` rows). Do it when the UI lands.
- [x] **DONE 2026-08-27.** Widened the weather fetch for race rows: the
      all-time race query now selects `weather_actual`, and `raceWeather` on
      `PredictionInput` seeds `weatherByDate` *before* the training window
      overlays it. Same argument as the all-time race-lap fetch that already
      sits ten lines below it — races are few and known by id.

**Done when:** `conditions_known` is true for every PR that has a
`weather_actual` row, and the 5K floor tightens to its neutral equivalent.
→ **Both, verified on the live account:**

```
tenK   PR 1880 (2026-02-07)  floor 32:52   conditions_known: TRUE
mara   PR 8563 (2025-01-19)  floor 2:30:52 conditions_known: TRUE
half   PR 4119 (2024-12-08)  floor 1:12:38 conditions_known: TRUE
5K     PR  905→864 (2024-08-08)  floor 16:00 → 15:16  conditions_known: TRUE
```

All five race rows carry `weather_actual`. Only the 5K moved, which is the
correct outcome — it is the only hot one (77.7°F / 72.4° dew, −41s). The other
three were genuinely cool races, so neutral equals raw. **That distinction is
the point:** "we know it was cool" and "we have no idea" produce the same
number and must not produce the same claim; one of the four new tests pins
exactly that, because it is the easy thing to collapse later.

Effect on the current estimate: **none.** Race scores are bit-identical and
session residuals move ≤0.01% (MAPE 2.23% → 2.22%, inside the sub-1% noise
floor the harness header warns about). This is a latent-safety fix — the floor
was not binding today. It binds when the athlete detrains, which is precisely
when a 44-seconds-too-loose 5K floor would have let the model publish a time
the athlete could not run.

### 2.2 — Two `weather_actual` shapes, one reader  *(0.25d)*

`2026-04-12` carries the sparse shape and every other race carries the full one:

```
full  (open-meteo-archive-backfill): temp_f, dew_point_f, humidity, wind_mph,
                                     heat_category, adjustment_pct, composite_score
sparse(open-meteo-backfill)        : temp_f, dew_point_f          ← no adjustment_pct
```

- [x] **CLOSED 2026-08-27 — the defect was never there.** `raceConditionsFor`
      does not read `adjustment_pct`, and it cannot: `WeatherInput` has exactly
      two fields (`tempF`, `dewPointF`), `mapWeather` populates only those, and
      `normalizeRaceTime` derives `heatFraction` from `heatAdjustmentPct(temp,
      dew)` on every call. Both shapes are therefore the same input. April's
      33:02 normalizes to **32:23 (−39s, −1.97%)** from the sparse row — the
      non-zero the §1.1 numbers depend on, and it reconciles §1.1's −1.08%
      exactly (32:02 predicted vs 32:23 neutral).

**Done when:** a unit test pins both shapes to the same correction for the same
temp/dew. → `fitnessInputs.test.ts`, 6 tests. It pins the *derivation*, not the
current answer: one test feeds a deliberately wrong `adjustment_pct: 0` in the
full shape and asserts nothing moves, so a future reader that starts trusting
the stored percentage fails here instead of silently flattening the only hot
race in the set. A second pins fail-closed — a half-present reading maps to
`null` ("not on file", reported as missing) and never to zero heat.

### 2.3 — Re-measure the cold start before deleting it (G0.6)  *(0.25d)*

Per §1.1 the cold start scored +2.07%, and the indicted fallback never ran.

- [ ] Instrument which branch fires: add the cold-start path to `data_source`.
- [ ] Only then decide between abstaining and returning the low tier. The rule
      the plan wanted still holds — **never a wrong number** — but "wrong" is now
      a measurement, not a presumption.

---

## 3 · Revised gates

### 3.1 — Commit first  *(10 min, do this before anything else)*

Five untracked files and three modified ones hold ~1,200 lines of tested work
that exists in exactly one place.

- [ ] Commit `fitnessInputs.ts`, `prFloor.ts` + test, `replay-fitness.ts`,
      the `fitnessPrediction.ts` + `compute-fitness-snapshot` changes, and both
      APPLY docs.
- [ ] Do **not** deploy in the same step — see §3.4.

### 3.2 — G0.1 exit criterion, rewritten  *(0.25d)*

Replaces the unachievable five-race table.

- [ ] **Exit criterion is n=2**, scored point-in-time, with per-horizon error at
      1/7/14/28/56d. Achieved — §1.1.
- [ ] Add a second, explicitly-labelled `--pit=workout_date` mode if the three
      pre-account races are wanted. It leaks retrospective curation (the batch
      was assembled knowing how the story ended), not the future. **Report its
      numbers in a separate table, never pooled with the honest two.**
- [ ] Persist replay output somewhere durable — today it exists only as terminal
      scrollback and a scratchpad file.

### 3.3 — G0.2 `prediction_scores` v2  *(0.25d, unchanged from the plan)*

Still one row, still the retired device writer's. Horizon-parameterized,
`neutral_actual_seconds`, and the real `model_version` column from G1.3.

- [ ] Have the replay **write** its scores here rather than printing them. One
      table, both sources, labelled.

### 3.4 — Deploy, watched  *(0.25d)*

`compute-fitness-snapshot` changed by 337 lines; deploying it deploys the new
input assembly, the PR floor and the fitted curve at once.

- [ ] Deploy, then compare the first nightly write against §1.4's prediction of
      **32:07 / 2:29:02**. A materially different number means the replay and the
      function have diverged — which is the one failure mode this whole
      architecture exists to prevent.
- [ ] Check the deploy actually landed. 41/55 functions once ran stale code, worst
      112 days.

---

## 4 · What comes after, re-ranked

The plan ordered G1 (generalization) next. §1.3 argues for reordering:

1. **Chase the flat training response** (new, ~1d). Ten seconds across eight
   weeks. Read `diagnostics.signal_weight`, `maintenance_factor`,
   `training_signal_pace` and `curve_alpha` across the chain the replay already
   produces — the answer is in data you now have. Everything in G1 is downstream
   of whether the estimate can move at all.
2. **G1.1 athlete-relative denominators** — unchanged, still the single change
   that most affects whether this works for anyone unlike the calibration
   athlete.
3. **G1.2 range calibration** — now measurable against §1.1, but n=2 means the
   coverage target is not yet estimable. Defer honestly rather than fit to two
   points.
4. **G2.3 synthetic cohort** — with only two real scores this carries more weight
   than the plan gave it. `athleteProfiles.ts` (8 tests) is still unplugged.

---

## 6 · The Phase-0 baseline  *(2026-08-27, session residuals)*

G0.2 landed: `replay-fitness.ts` now prices every quality session against the
estimate standing on the last step **strictly before** the session was run, and
reports the residual. n=2 races became n=23 sessions. Sign convention is the
race table's — error > 0 means the model predicted SLOWER than the athlete ran.

Command: `--user=03857bf3-… --from=2026-01-26 --step=1 --sessions`

| | shipped model |
|---|---|
| **MAPE** | **2.22%** ← the number Phase 1 must beat |
| mean error (bias) | −0.92% |
| median | −0.82% |
| worst | −7.32% |
| predicted slow / fast | 8 / 15 |
| **coverage** | **23 / 250 parsed sessions** |

(Re-measured 2026-08-27 after the §2.1 race-weather fix; 2.23% → 2.22%, i.e.
unchanged inside the noise floor. The floor was not binding on this history.)

By month — the drift the single MAPE averages away:

| | n | mean | MAPE |
|---|---|---|---|
| 2026-03 | 1 | −0.39% | 0.39% |
| 2026-04 | 5 | −1.53% | 3.42% |
| 2026-05 | 3 | +0.43% | 1.84% |
| 2026-06 | 5 | −0.29% | 1.59% |
| 2026-07 | 4 | −0.37% | 1.46% |
| 2026-08 | 5 | −2.30% | 2.87% |

**Read coverage before error.** The residual set is the model's *own* admission
basis — `estimateFromSession` drops anything outside the 0.86–1.10 plausibility
window. A Phase-1 model can lower MAPE by admitting fewer, easier sessions, so
the harness prints the rejection census next to the error and a fall in
`scored` invalidates a MAPE win. Current census: 170 non-quality type, 20
slower-than-curve, 16 no usable work reps, 13 no estimate predates the session,
4 declared race, 3 under the work floor, 1 faster-than-curve. The 170 is the
binding limit — the loss function sees only what the parser typed as quality.

Races re-verified on the same run: **Feb +2.07%** reproduces §1.1 exactly, and
April predicts **32:02**, also exactly. April reads −3.03% here against the
**raw** 33:02 where §1.1 records −1.08% against the ~32:23 neutral — the same
number on a different basis, not a regression. That gap is §2.1
(normalize-at-confirmation); until it lands, compare race errors on one basis.

---

## 7 · Where session coverage actually goes  *(2026-08-27)*

§6 reported 23/250 scored and named "170 non-quality type" as the binding
limit. **That reading was wrong and the conclusion drawn from it — go improve
parser coverage — would have made the model worse.** The census:

`parsed_structure` coverage is not the problem: 305 logs, 11 unparsed (4%),
256 with blocks. The 47% era is over.

**The 170 type rejections are correct and load-bearing.** Work reps inside
`easy` sessions have a **median duration of 1800s** and inside `long_run`
**3386s** — the parser assigns the whole continuous run one `work_rep` block.
They are not strides. The type filter is the only thing stopping 119
easy/long runs from being priced as quality efforts, which is precisely the
failure that broke v1 (the 2026-08-01 alternation session reading as a 35:38
10K). Relaxing it trades a real defence for fake coverage.

The real story is in the 66 quality-typed sessions since 2026-01-26, of which
25 score — and it splits cleanly by `parsed_structure.geometry_source`:

| provenance | n | scored | |
|---|---|---|---|
| `watch_laps` | 23 | **16 (70%)** | healthy — this is what good looks like |
| `detectWorkBouts` | 12 | **0 (0%)** | broken, see below |
| absent (intent-derived) | 22 | 7 | geometry from the *prescription*, not the run |
| `model` | 9 | 2 | |

### `detectWorkBouts` scores 0 of 12, and it is the path that will grow

The stream-derived rep detector marks warmup and easy running as `work_rep`:

```
2026-05-16 progression  work_rep 10.01mi @ 6:44   ← the easy portion
                        work_rep  3.07mi @ 6:30   ← the actual work
2026-05-28 progression  work_rep  1.02mi @ 7:25   ← the warmup
                        work_rep 11.36mi @ 6:22
2026-05-02 interval     work_rep  0.25mi @ 22:33  ← walking
```

The distance-weighted mean is then dragged submaximal, the plausibility
window correctly rejects it as "aerobic work", and the session says nothing.
**The model is behaving correctly on bad geometry.** Every one of the 12 fails
this way — 0/12 is a bug signature, not a distribution.

This matters beyond the 12: Vital/Junction gives no native laps, so
`detectWorkBouts` is the path for every non-Strava athlete
([[project_garmin_lap_derivation]]). It is broken for all of them.

### Do NOT "fix" the null-duration sessions

Intent-derived rows carry `duration_s: null` with distance and pace present,
so deriving `duration = distance × pace` looks like free coverage. Measured:
**+2 sessions.** One of the two is `2026-01-27`, whose twelve reps all read
exactly `4:34` — that is the *prescribed* pace from
`"12 x 400m (2 sets of 6)"`, not twelve measured ones. Landing that fix would
feed the model a plan as if it were a performance. Rejected: the tell for a
prescription is identical paces across reps and it is worth a guard, not a
recovery.

**So the ranked list, if session residuals are to be the loss function:**

1. Fix `detectWorkBouts` work/rest discrimination. 12 sessions here, and it
   gates every Garmin athlete. Biggest and most general.
2. Decide what a `progression` run states. Ten of the twenty
   "slower than the curve" rejections are progressions; averaging a
   progression's work portion is structurally guaranteed to read submaximal.
   Pricing the final segment rather than the mean is a Phase-1/2 modelling
   question, not a parser one.
3. Guard against prescription-derived geometry reaching the estimator at all.

None of this changes the §6 baseline — it explains it. Phase 1 should be
scored on `watch_laps` sessions specifically as well as on the pooled number,
or a `detectWorkBouts` fix will look like a model improvement.

---

## 8 · Phase 1 built, and it does NOT pass its gate  *(2026-08-27)*

`fitnessEstimator.ts` exists: state is a level with a variance, every
performance is an observation with a variance, and combining them is the
recursive form of the shrinkage `raceCurve.ts` already uses. Twenty unit tests
green, including the acceptance case harvested from `evidenceBlend.ts` (eight
weeks of training closes >80% of the race→training gap). `replay-fitness.ts
--estimator` runs both chains side by side; they share only the input
assembly. **Nothing is switched. `compute-fitness-snapshot` is untouched.**

Against the three exit gates:

| gate | shipped | estimator | |
|---|---|---|---|
| Feb 10K err | +2.07% | **−1.28%** | improved |
| Apr 10K err | −3.03% | −3.77% | worse |
| **session MAPE** | **2.28%** | **2.55%** | **FAILS** |
| 56d pre-April movement | 0.9 s/mi | **4.4 s/mi** | ~5× more |

Gate 2 is the one that matters and it fails. `PROCESS_SD_PER_WEEK` was swept
against the loss rather than argued about — 0.002→2.72%, 0.004→2.51%,
0.006→2.49%, 0.009→2.55%. A shallow minimum at 0.006, **and every point on it
is worse than the shipped 2.28%.** The estimator is at its measured best and
still loses.

### Why, and why this is not simply "the estimator is bad"

The shipped model barely moves — 0.9 s/mi across the 56 days before April,
which is §1.3's complaint restated. But a model that barely moves scores WELL
on a residual loss when the observations are noisy around a stable true level:
it predicts the mean and never chases. The estimator moves toward each
session, so when the next session disagrees it eats the error. **On n=23 noisy
sessions, stiffness is a winning strategy for this loss function.**

That is a statement about the loss, not only about the estimator. §7 already
found the residual set is 25 of 66 quality sessions, that `detectWorkBouts`
contributes 0 of 12, and that 10 of the 20 plausibility rejections are
progression runs the model has no way to price. A loss function built on the
surviving 23 cannot yet distinguish "tracks fitness better" from "chases parse
noise better".

### So the honest conclusion

**Do not switch on this evidence, and do not tune the estimator further
against this loss.** Tuning against an under-powered loss is how the eight
clamps got here in the first place — each one defensible against the evidence
available when it was written.

The gate is not wrong; the evidence behind it is too thin to pass anything.
Ranked, before Phase 1 is re-judged:

1. **`detectWorkBouts` work/rest discrimination** (§7). 12 sessions, and it is
   the path for every non-Strava athlete. Biggest single lever on n.
2. **Decide what a progression run states.** 10 more sessions, and it is a
   modelling question the estimator would have to answer anyway.
3. Re-run `--estimator` when n is meaningfully above 23, and only then read
   gate 2.

The estimator is committed as-is — unswitched, tested, and measured. It is
cheaper to keep it beside the engine than to rebuild it when the loss is ready.

---

## 9 · n=23 is close to the ceiling — four measured negative results  *(2026-08-27)*

§8 concluded the loss was under-powered and ranked coverage fixes. Those were
then measured. **None of them work, and §7's ranking was wrong.**

### `detectWorkBouts` is NOT broken — 0/12 is the correct answer

§7 called this the biggest lever. It isn't a bug. The detector's contract is
"a rep is bounded by a recovery", and every one of its 12 sessions is genuinely
aerobic running that the model is right to reject:

```
2026-07-04 typed "interval"  0.09mi jog + 7.11mi @ 6:51 + 5.18mi @ 6:49
2026-08-09 typed "tempo"     2.82mi @ 7:06 + 3.19mi @ 7:30   (wtype=easy)
2026-08-08 typed "interval"  1.03mi @ 6:18 + 29-MIN STOP + 1.02mi @ 7:40
2026-08-08 typed "long_run"  18.1mi @ 6:39 as one bout
```

For a 5:09/mi 10K athlete, 6:49–7:30 is easy running. The defect is the
parser's TYPE label, not the geometry — and the pace-based plausibility window
catches it correctly. Fixing the detector would recover nothing.

### Dropping warmups mislabelled as `work_rep` makes it WORSE

Real case: `1.02mi @ 7:25` then `11.36mi @ 6:22` — the first block is a warmup
typed as work, dragging a genuine marathon-pace session below the window.
Reclassifying work bouts more than N% slower than the session's fastest:

| tolerance | scored | |
|---|---|---|
| 8% | 25 → 21 | −4 |
| 12% | 25 → 22 | −3 |
| 15% | 25 → 22 | −3 |
| 20% | 25 → 24 | −1 |

Negative at every setting and gains nothing anywhere. Interval sessions have
naturally varying rep paces, so the filter eats real reps and pushes those
sessions under `MIN_WORK_SECONDS`.

### Deriving `duration = distance × pace` recovers a PRESCRIPTION

+2 sessions, and one is `2026-01-27` whose twelve reps all read exactly
`4:34` — the prescribed pace from `"12 x 400m"`. Rejected (§7).

### The forgotten-watch fix recovers nothing either

Correct and committed (`b6c1a90`), and it removes a silent wrong-direction
failure. But scored sessions stayed at 25/66.

### What this means

**n≈23 is close to the true ceiling for this athlete's history**, not a
symptom of broken plumbing. `watch_laps` sessions already score at 16/23
(70%). The rest of the athlete's running is genuinely aerobic — the parser
mistypes some of it as interval/tempo, but the model rejects it correctly and
would still reject it after any type fix.

So the loss function cannot be strengthened by data work on this athlete, and
**§8's "re-run when n is meaningfully above 23" has no cheap path to it.**

That reopens a question rather than answering it: gate 2 is the weakest of the
three gates *and* the one the estimator is judged on. The estimator wins gate
1 (Feb error 2.07% → 1.28%) and gate 3 (movement 0.9 → 4.4 s/mi, ~5×) and
loses gate 2 by 0.27pp on 23 noisy sessions where stiffness is structurally
advantaged.

**This is a decision for Rio, not a thing to quietly resolve in code**, and it
is exactly the shape §5 warns about: re-specifying the gate after seeing the
result is how a model gets validated against a prior belief. Stated plainly so
it is a choice rather than a drift.

---

## 5 · The trap this document exists to avoid

The 2:37 fix was verified as "raw model 309.26 vs prior 309.03 — the new code
agrees with the old answer." That is agreement with a prior belief.

§1.4 is the same shape of check — +6s / −16s against the live number — and it is
**not validation either**. It is a blast-radius measurement, and it is only
allowed because §1.1 does the validating separately, against races, at n=2.

Keep the two distinct on every future change.

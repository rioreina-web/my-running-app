# HR Efficiency Index — one composite number, threshold-anchored, heat-neutral · apply notes

*Written 2026-08-18. **Applied 2026-08-18** — model validated on real exported
data first (see §V below), then built. New files:
`EfficiencyIndexModels.swift`, `EfficiencyIndexCard.swift` (Trends/),
`EfficiencyIndexTests.swift` (RunningLogTests/). Touched:
`InstrumentsCardsTraining.swift` (tombstone), `InstrumentsCardKit.swift`
(deprecation). `InstrumentsTabView` is unchanged — the card keeps its struct
name and slot, the KeyPace precedent.*
*Follows the repo's `APPLY-NOTES.md` additive-new-files convention.*

**Two spec changes came out of validation — the data overruled the draft:**

1. **Long runs are IN the fit** (the draft excluded them). Intervals alone
   span 271–338 m/min and the fitted slope swings 8% under leave-one-out;
   with long runs the span widens to 242–338 and the swing halves. They lie
   on the same line — the curve normalizes by speed, which is exactly what
   makes them comparable. They still render apart (open diamond) and group
   apart (LONG) — different quantity, same curve.
2. **An artefact gate exists** (the draft had none). See §V.

One number that answers "how much ground am I covering per heartbeat, relative
to my own norm?" — fed by every quality session regardless of zone (MP and HMP
included), expressed at the athlete's threshold pace, heat-neutral on **both**
sides of the ratio: pace via the existing adjustment, HR drift via a heat term
fit from the athlete's own history (§2b).

**No backend work. No deploy. No migration. No new fetch.** Every input already
arrives on the `trends-timeline` payload: `KeySession.zone`, `workPaceSec`,
`workPaceAdjSec`, `heatCategory`, `workHrAvg` (`TrendsModels.swift:379`). The
math is client-side, next to the derivations that already live there.

---

## 1 · The diagnosis

Signal Lab already ships an HR-efficiency read — Signal 03,
`BeatEfficiencyBuilder` (`SignalLabModels.swift:205`), metres per heartbeat.
Three things stop it from being the score this feature wants:

| # | Symptom | Cause |
|---|---|---|
| 1 | A mile-rep week "gains" efficiency, an MP week "loses" it | All quality sessions share one trend line. m/beat rises with speed for every runner alive, so the line measures *what you ran*, not *how well you ran it*. This is the same across-zones mush the Key Pace rework fixed for pace (`KEY-PACE-APPLY.md §1`). |
| 2 | No single score | Two series (reps / longs), two means, two slopes. Nothing an athlete can watch move. |
| 3 | The number has no anchor | 8.1 m/beat means nothing on its own. Anchoring the readout at threshold pace makes it a number you can carry between months and compare against yourself. |

**The fix:** fit the athlete's own pace↔efficiency curve, score every session
as a % of what the curve predicts *at that session's pace*, and report the
composite at the threshold anchor the band already owns.

---

## 2 · The metric

### 2a · Per-session reading (unchanged physics)

`SignalLabMath.metresPerBeat(paceSecPerMile:hr:)` (`SignalLabModels.swift:56`),
fed with:

- **pace** = `KeySession.effectivePaceSec` — the heat-neutral pace every other
  surface reads (`TrendsModels.swift:418`). This corrects the *pace* side of
  heat; the *HR* side (drift) is corrected by the model's heat term, §2b.
- **hr** = `workHrAvg`, gated to the existing `90...205` artefact range
  (matches `HR_MIN`/`HR_MAX` in `_shared/fitnessSignal.ts`).

### 2b · The personal baseline curve — with a heat term

The pace adjustment (`workPaceAdjSec`) corrects the *pace* side of heat.
It does not touch the HR side: heat raises HR at a given effort — cardiac
drift under thermal load — and that elevated HR sits in the denominator
untouched. Correct only the pace and every hot session reads a little
inefficient forever. The model must carry a heat term, and it must be
**the athlete's own**, not a textbook bpm-per-degree constant — the same
ruling that makes the band read `BandSettingsStore` instead of a shipped
default.

Over a trailing **180-day** lookback, ordinary least squares with two
covariates, over eligible sessions (eligibility in §2d):

```
m/beat  ≈  β₀ + β₁ · speed + β₂ · heatSeverity
```

- **speed** = metres per minute, from `effectivePaceSec` (heat-neutral pace —
  the pace side of the correction stays exactly where it is).
- **heatSeverity** = ordinal from `heatCategory`:
  `ideal = 0 · warm = 1 · hot = 2 · very_hot = 3 · dangerous = 4`.
  One coefficient across the ladder — five separate dummies would fit noise
  on a beta athlete's session counts.
- **β₂ measures the athlete's residual heat-HR drift** in m/beat per
  severity step: how much ground per beat *this runner* loses to a heat
  category after the pace correction has already been applied. It is fit
  from their history, and it is theirs.

Two-covariate OLS is still just accumulators (a 3×3 normal-equation solve);
no dependency. Reuse `SignalLabMath.mean` / `dayNumber`.

Guards, in the NOT YET voice:

- Fewer than **8** eligible sessions in the lookback → the surface renders
  NOT YET, never a dash (hard rule #8).
- Sessions spanning fewer than **2** distinct zones → NOT YET. A curve fit to
  one zone is a point wearing a slope.
- **The heat term needs heat to learn from.** Fewer than **5** non-ideal
  eligible sessions in the lookback → β₂ is not fit (held at 0) and the
  model degrades to the pace-only correction — under-correcting, which can
  only *understate* a hot run, never flatter it. The detail says so in
  words ("heat term: NOT YET — 3 of 5 hot sessions") rather than silently
  pretending the drift is handled.
- **β₂ is clamped ≤ 0.** Heat cannot make a human more efficient; a fitted
  positive coefficient is sampling noise wearing a conclusion, and clamping
  it to zero means noise can never *flatter* a hot session either. Both
  failure directions land conservative.

### 2c · Session index and the composite

- **Session index** = `100 × mpbActual / mpbCurve(sessionSpeed, sessionHeatSeverity)`.
  A hot session is scored against **what this athlete normally manages in
  that heat at that pace** — the drift is in the denominator's prediction,
  so it cancels instead of reading as lost fitness.
  103 at MP = 3% more ground per beat than your own 180-day norm *at MP*.
  Comparable across zones by construction — this is what lets MP, HMP, 10K
  and mile work feed one line.
- **Headline (the composite)** = mean of session indices over the trailing
  **28 days**. Fewer than **3** sessions in those 28 days → headline reads
  NOT YET; the dots still draw.
- **Trend** = slope of session indices per 30 days over the selected window,
  same convention as `BeatEfficiencyRead.trendPerMonth`.

### 2d · Eligibility (and the NOT COUNTED panel)

A session feeds the fit and the composite iff:

1. `workHrAvg` present and inside `90...205`. Missing/artefact HR → NOT
   COUNTED with the reason. (Long runs are eligible — see the spec-change
   note at the top; validation overruled the draft's exclusion.)
2. Heat is trustworthy: `heatCategory` is `ideal`, **or** non-ideal with
   `workPaceAdjSec` present. Non-ideal heat with no adjusted pace → NOT
   COUNTED. Never score a hot session at its raw pace — that reads heat as
   lost fitness, the exact error the correction exists to prevent.
3. It survives the **artefact gate** (10+ sessions only): each point is
   scored by a fit that never saw it — z = |deleted residual| ÷ the
   rest-fit's own RMSE, floored at 1% of the mean reading; z > 4 is an
   artefact, dropped from fit AND chart, counted in NOT COUNTED as
   HR LAG OUTLIER. Rationale and receipts in §V — a plain residual gate
   provably misses the case that matters.

### 2e · The threshold anchor

The small-type raw number under the headline is the curve evaluated at the
band's anchor pace:

> **EFF INDEX 103** · `8.2 m/beat @ 6:45 /mi, cool`

Evaluated at **heatSeverity = 0** — the number is what the curve says you
do at threshold pace in ideal conditions, which is the only version of it
that is comparable month over month across a Texas summer.

- Anchor pace comes from **the** band: `BandSettingsStore.shared.settings.anchor`
  (default `.hmp`, `TrendsBandSettings.swift:75`) resolved through the weekly
  race-pace ladder exactly the way `KeyPaceModels.steps(ladders:anchor:...)`
  already resolves it (`KeyPaceModels.swift:964`). **One band** — the athlete
  moves the band and this readout moves with it, or the invariant is broken.
- **No extrapolation.** If the anchor pace falls outside the speed range the
  curve was actually fit on, omit the `@ threshold` stat entirely (the stat
  row omits an item rather than filling it — hard rule #8). The index
  headline stays; it never depended on extrapolating.

---

## 3 · The invariants this must not break

| Invariant | How it survives |
|---|---|
| **No mock data in Instruments** (`InstrumentsCardKit.swift` header) | Every figure derives from `TrendsService.keySessions`. New derivations live beside the existing ones. Empty routes to `InstrumentEmpty`. |
| **No em-dashes as placeholders** (hard rule #8) | NOT YET / NOT COUNTED words, or the row omits the item. §2b, §2e. |
| **One band** (`TrendsBandSettings.swift:180`) | Anchor read from `BandSettingsStore.shared`; nothing new persists. |
| **One renderer** (`KeyPaceChart.swift:5`, `TrendsV2View.swift:37`) | Card and detail render the same `EfficiencyIndexChart` at 140pt / 250pt. A second implementation is the wrong change. |
| **ONE time control** (`TrendsSignalModels.swift:12`) | Detail binds the host's `@State window`, not a copy. |
| **Three-palette rule: blue = pace, coral = punctuation** (`CLAUDE.md:355`) | Dot hue = `PaceSpectrum` colour for the session's zone (pace identity, same as Key Pace). The 100 baseline rule is `textTertiary` **neutral gray — never green**; above-100 is not "good zone". Coral appears exactly once: the latest session. |
| **Heat by fill, not hue** (`KEY-PACE-APPLY.md §3`) | Heat-adjusted sessions render hollow; ideal render filled. Scrub readout prints the `heatCategory` word. |
| **Observation, never prescription** | The prose states what happened: "Last 28 days: 5 sessions averaged 103 — 3% more ground per beat than your 180-day curve. HMP ran 104, MP 101." No grades, no advice. Every number in the sentence is a number on screen (the `InstrumentNote` contract). |

---

## 4 · The encodings

1. **One dot per eligible session.** x = real date (`dayNumber`, sessions are
   not evenly spaced), y = session index, hue = zone from `PaceSpectrum`,
   fill = heat (§3). Latest session coral.
2. **The 100 rule.** A neutral-gray horizontal hairline at 100 — the athlete's
   own curve. Dots above it covered more ground per beat than their norm.
3. **Zone chips in the detail** — `MP · HMP · 10K · 5K · 3K · MILE`, the
   Key Pace chip row, filtering dots and recomputing the per-zone mini-stats.
   **Ship six, not seven**: the backend classifier folds LT into `hmp`
   (`TrendsModels.swift:383`); label them honestly, do not invent an LT
   bucket in the client (same wart, same ruling as `KEY-PACE-APPLY.md §3a`).
4. **Per-zone mini-stats** under the detail chart: mean index per zone with
   ≥3 sessions, so "efficiency at MP" vs "at HMP" is directly readable —
   the original ask. Zones under the floor are omitted, not dashed.
   Beside them, one heat stat when β₂ is fit: **"YOUR HEAT COST −2.1% / step"**
   (β₂ expressed as a percentage of the curve at threshold speed) — the
   athlete's own measured drift, stated as an observation. When β₂ is not
   fit: "HEAT TERM NOT YET — n of 5 hot sessions".
5. **Scrub readout**: date · structure · zone · index · m/beat · HR ·
   pace (adj) · heat word. `KeySession.id` is the `training_log_id`, so a
   tap opens the workout — the Key Pace hit-layer conventions apply.
6. **NOT COUNTED panel** in the detail: long runs (n), missing HR (n),
   unadjusted heat (n).

---

## 5 · Files

Additive-new-files, per `APPLY-NOTES.md`:

| File | Contents |
|---|---|
| `RunningLog/RunningLog/Trends/EfficiencyIndexModels.swift` | `EfficiencyPoint`, `EfficiencyCurve` (fit + `predict(speed:severity:)` + fitted speed range), `EfficiencyIndexRead`, `EfficiencyIndexBuilder.build(sessions:bandLaps:settings:window:asOf:)`, `EfficiencyIndexProse`. Pure value types, no SwiftUI — testable without a renderer. |
| `RunningLog/RunningLog/Trends/EfficiencyIndexCard.swift` | `InstrumentEfficiencyCard` (same struct name and slot as the card it replaces — `InstrumentsTabView` unchanged) + `EfficiencyIndexChart`, the one renderer. Zone chips, scrub, tap-to-open workout, NOT COUNTED line, prose note. Routes empty and NOT YET to `InstrumentEmpty`. |
| `RunningLog/RunningLogTests/EfficiencyIndexTests.swift` | 15 tests — see §7 and §V. |

Touched: `InstrumentsCardsTraining.swift` (old card 03 → tombstone, the
KeyPace pattern) and `InstrumentsCardKit.swift` (`InstrumentsData.efficiency`
deprecated, kept for source compatibility). A fullscreen detail view (the
250pt render of the same `EfficiencyIndexChart`) is the deliberate follow-up
— ship the card, live with it, then decide. `BeatEfficiencyBuilder` is
**not** modified in this pass — Signal 03 adopting the curve is a follow-up
with its own notes, so this change stays revertable by deleting files.

---

## 6 · Build order

1. `EfficiencyIndexModels.swift` + tests green. No UI.
2. Chart renderer against real `TrendsService` data.
3. Card, registered on the Charts tab.
4. Detail + chips + NOT COUNTED.
5. Prose note last — every number it prints must already be on screen.

---

## 7 · Tests

- **Curve sanity**: synthetic sessions on a known line recover slope/intercept;
  `predict` inside the fitted range only.
- **Index math**: a point exactly on the curve indexes 100.0; +3% mpb → 103.
- **Heat**: non-ideal + adjusted pace → scored on adjusted; non-ideal +
  no adjusted → NOT COUNTED, never scored raw.
- **Heat term**: synthetic data with a known per-severity HR penalty →
  β₂ recovers it and the hot sessions index ~100; only 4 non-ideal
  sessions → β₂ held at 0 and the NOT YET string is produced; a fitted
  positive β₂ → clamped to 0; for any hot session, index-with-term ≥
  index-without-term (the correction only gives back what heat took —
  assert the direction).
- **Anchor at severity 0**: a fitted β₂ must not move the `@ threshold`
  stat — it is evaluated cool by definition.
- **Gates**: 7 sessions → NOT YET; 8 across one zone → NOT YET; long runs
  excluded and counted; HR 89 / 206 excluded and counted.
- **Anchor**: band anchor outside fitted speed range → `@ threshold` stat nil.
- **Composite**: 28-day mean uses only in-window sessions; <3 → headline nil.

---

## 8 · Warts, named now

- **LT is folded into HMP** by the classifier. The curve doesn't care (it fits
  pace, not zone labels) but the HMP chip inherits the fold. Same honest-label
  ruling as Key Pace until the classifier changes.
- **`workHrAvg` is a work-bout mean.** A 6×400m session and a 40-minute MP run
  put different amounts of drift into that mean. The curve absorbs the
  first-order effect (it's fit on the same population it scores) but session
  *duration* is not an input. If long-MP sessions systematically read low,
  duration-bucketing is the follow-up — not a reason to block this.
- **The linear fit is local.** m/beat vs speed is near-linear across the
  MP→mile span for one athlete; it is not a lab model. The no-extrapolation
  rule (§2e) is what keeps it honest.
- **The heat term is category-grained.** `heatCategory` is five buckets, not
  a dew point. A brutal 91° day and a mild 78° one can share a bucket, so
  β₂ corrects the *average* drift per bucket and individual hot dots still
  scatter around the line more than cool ones. If the backend ever puts
  temperature or dew point on the payload, β₂'s ordinal input upgrades to a
  continuous one in the builder and nothing else moves.
- **Until β₂ has 5 hot sessions to learn from, drift is only half-corrected**
  (pace side yes, HR side no) and hot sessions read slightly low. Both this
  fallback and the ≤0 clamp fail in the same direction: heat can cost the
  index, never pay it. The hollow fill marks which dots carry the asterisk
  either way.
- **Within-run drift needs the trace, not the average.** `workHrAvg` is one
  number per session; true decoupling (first half vs second half of the
  same run) needs the per-minute stream that `run-hr-trace`
  (`supabase/functions/run-hr-trace`) already extracts. That is the natural
  v2 of this instrument — per-session decoupling as its own encoding — and
  it is backend-adjacent, so it stays out of this pass on purpose.
- **The baseline contains the present.** The 180-day curve includes the last
  28 days, so the headline is pulled toward 100 by construction — a real
  4% gain over a month reads as something under 4. The wording ("vs your
  180-day curve") stays honest, and the *trend* slope is unaffected. If the
  damping annoys in practice, the follow-up is fitting the curve on days
  181→29 and scoring the last 28 against it — a two-line change in the
  builder, deliberately not shipped first because it halves the data the
  fit sees.
- **Racing and taper** land as high dots. That's an observation, and this
  surface only observes.

---

## V · Validation — 2026-08-18, real exported data

Run on `key-sessions-data.json` (21 sessions, May 5 → Jul 25, Austin summer)
before any Swift was written. The numbers below are what "accurate" means for
this instrument.

| Finding | Number |
|---|---|
| Fit quality, pooled (quality + long runs), after the gate | R² 0.957 |
| Leave-one-out error per session index | **±2.3 pts (1σ)** |
| Implied noise on the 28-day composite (~5 sessions) | **±1.0 pt** |
| Same fit with the HR-lag artefact left in | 10% — one session quadrupled the error |
| Intervals-only slope swing under LOO (why long runs are in) | 8% → 5% pooled |

**The artefact that designed the gate.** A real 8×200 session carried
`avgHrReps` 136 — HR physically cannot reach steady state on ~35-second reps
— at a speed (400 m/min) far outside every other session. Leverage means an
ordinary fit bends *toward* such a point and hides its residual: a
MAD-of-deleted-residuals gate scored it z 2.6 (invisible) because the tilt it
caused inflated everyone else's residuals. Normalizing each point's deleted
residual by the **rest-fit's own RMSE** instead scores it z ≈ 20 — judged by
the clean fit — while clean points are judged by the polluted one and stay
under 1. On the real data this gate drops exactly one session; a second
round drops nothing. The 1%-of-mean floor keeps sterile synthetic data from
flagging a genuinely strong (+3%) session.

**The heat term on this athlete, today: clamps to 0.** The season is so
uniformly hot (dew 64–72 all window) that severity correlates 0.85 with the
calendar, and the pace adjustment already absorbs most of the effect — the
fitted coefficient came out +0.0008 and clamped. This is the conservative
fallback doing its job; the term wakes up when fall supplies cool sessions
to compare against. The synthetic tests prove the recovery path: a planted
per-step penalty is recovered and drift-corrected hot sessions read ~100.

**Index behaviour over the real block:** session indices 96.6–103.6, trend
+0.2 pts/30d — holding efficiency flat through an Austin summer at 60–70 mi
weeks, which the surface states and declines to grade.

All 15 test scenarios in `EfficiencyIndexTests.swift` were executed against
a line-for-line port of the builder before applying (this environment can't
run Xcode); run them for real with **⌘U** — they are the same assertions.

---

## 9 · What this is not

Not a fitness predictor (that's `FitnessPredictorService`), not a grade, not
advice. It's one instrument: ground covered per heartbeat, against your own
curve, at your threshold, with the weather removed.

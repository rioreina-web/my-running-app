# REP SHAPE + RECOVERY SCORE — APPLY

Session of 2026-08-14. Designed and **calibrated against three of Rio's own
sessions with per-second HR**, not against invented constants. Nothing here is
built yet. Several proposals were killed by the data mid-session — those
reversals are recorded, because the reason matters more than the conclusion.

Calibration set (Strava, per-second `heart_rate` + `velocity_smooth`):

| Activity | Session | Reps | Verdict on usability |
|---|---|---|---|
| 19696011909 | 10 × 1km, 2026-08-11 | 10 × ~203s @ ~5:20 | **clean — the reference session** |
| 19627365635 | 5 × 4min, 2026-08-06 | 5 × ~247s @ ~5:25 | sensor-compromised, scores LOW |
| 19445335217 | 200s, 2026-07-24 | 8 × 31s @ ~4:21 | **structurally unscoreable** |

Athlete constants observed across all three: **floor ≈ 66 bpm** (true resting
asymptote, from a 20-min standing pause), **ceiling ≈ 179 bpm**, working span
≈ 113 bpm. The three sessions top out within 6 bpm of each other (179 / 173 /
176), so the ceiling is consistent and trustworthy.

---

## 0 · Why

`fitnessSignal.ts` pools every rep in a session into one accumulator —
`addBouts` sums meters, seconds and HR-weighted-seconds across the whole set —
then computes one efficiency factor from the totals. `effortModel` and
`workoutComparison` do the same thing one level down: `recoveryHrDropBpm` is a
**mean**, `avgRecoverySec` is a **mean**, `hrDriftPct` and `fadePct` are session
scalars.

Averaging is the operation that destroys a slope. Two sessions with identical
means can be opposite readings:

```
athlete A   pace 5:00 5:01 5:00 5:02 4:58   HR 168 171 174 177 180   jog drop 36 35 33 30 —
athlete B   pace 5:02 5:00 5:00 5:01 4:58   HR 174 174 173 175 176   jog drop 34 34 33 34 —
```

Same mean pace, near-identical mean HR, same mean recovery drop, same EF. A is
at her ceiling; B could have done seven. **The pooled number cannot tell them
apart, and that difference is the thing worth knowing.**

The reps are already segmented — `segmentFromLaps` returns `seg.reps` as an
ordered array with pace, seconds and `avgHr` on each. The trajectory exists and
is summed away.

---

## 1 · The score

### 1.1 Per rep — six raw quantities

Computed from `training_logs.external_streams.streams.heartrate` + `.time`
(1 Hz, already stored; `run-hr-trace/index.ts` already reads exactly these two
arrays).

| field | definition |
|---|---|
| `hrPeak` | mean HR over the **final 15s** of the rep |
| `hrr60` | bpm dropped from `hrPeak` at 60s after rep end — **the primary metric** |
| `hrr30` | same at 30s — computed, but see §2.3, it is artifact-prone |
| `hrFloor` | minimum HR reached during the recovery |
| `hrAtNextRepStart` | HR at the instant the next rep begins — **the carryover** |
| `recoverySeconds` / `recoveryPace` | what bought that recovery |

`hrr60` and `hrAtNextRepStart` answer different questions and both are needed.
hrr60 is *capacity to recover*. Carryover is *debt actually carried in*. Good
hrr60 with a short jog still starts the next rep high; sluggish hrr60 with a
generous jog can still reach the line recovered.

### 1.2 Per session — four slopes, one level

- **level** = `hrr60` of the first *valid* rep (see §2.2). Freshest reading,
  most comparable across sessions.
- **recovery slope** — `hrr60` across reps. Closing = the session bit.
- **carryover slope** — `hrAtNextRepStart` across reps. Rising = debt.
- **pace slope** — did the reps hold.
- **HR-cost slope** — `hrPeak` across reps at held pace.

Report each as **total change first rep → last**, not as a per-rep coefficient.
Total change is what a coach reads and what a threshold can be set on.

---

## 2 · What the data settled

### 2.1 Headroom normalisation is dead — killed by the calibration

The proposal was `hrr60 ÷ (hrPeak − floor)`, on the reasoning that dropping 40
bpm from 180 is easier than from 165 because the decay curve is steeper up top.
Physiologically sound. **It makes the metric noisier, not cleaner:**

| session | raw hrr60 CV | normalised CV |
|---|---|---|
| 10 × 1km | **0.121** | 0.133 |
| 5 × 4min | **0.153** | 0.158 |
| 200s | 0.708 | 0.252 |

Within a session `hrPeak` barely moves — 165→176 across ten 1km reps — so the
divisor contributes almost no signal and all of its own measurement error.
Normalisation only helps on the 200s session, and that session is invalid for
other reasons (§2.2).

**Use raw `hrr60`. Do not normalise by reserve.** Revisit only if comparing
across athletes, which is not a v1 requirement.

### 2.2 Rep duration gate: ≥ 90 seconds

The 200s session is the proof, and it is emphatic:

- **0 of 8 reps reached an HR plateau.** HR climbed monotonically through every
  rep, +17 to +96 bpm/min over the final 60%.
- **The true peak lands 0–20s *after* the rep ends.** Reps 2 and 6 peak a full
  20s into the recovery.
- **`hrr30` is negative on 4 of 8 reps** — HR is still *rising* 30 seconds after
  the rep finished.
- `hrPeak` climbs +42.5 bpm rep 1 → rep 8 at *flat pace*. That is HR catching up
  to the workload, not fatigue, and any naive reader calls it a collapse.

Both long-rep sessions (~203s and ~247s) plateau cleanly: drift −1.37 to +2.24
bpm/min. So:

> **`hrr60` requires reps ≥ 90s AND `hrSettled`. Below that, emit no recovery
> score at all** — not a low-confidence one, none. Rio's instinct that mile reps
> at 10K pace are the right instrument is exactly right and now has a number
> behind it.

Optional later: for short reps, anchor to max HR in `[repEnd, repEnd+30s]` and
start the recovery clock there. **Not in v1** — it is a different measurement
wearing the same name, and mixing them is how a metric becomes meaningless.

### 2.3 `hrr60` over `hrr30`

`hrr30` on the 5×4min session reads 5.3 on rep 4 purely because of a recovery
bump (HR went 147 → 154 → 144 across 20s). `hrr60` for the same rep is a
sane 32.3. The 60s window integrates over that noise. Compute `hrr30`, store
it, do not score on it.

### 2.4 The confidence gate earns its keep immediately

5×4min looks fine on paper — 5 reps, all ≥243s, 4 of 5 settled — and is
garbage:

- Rep 3 is the **fastest** rep (5:21) and peaks at **152.2 bpm**, 24 bpm *below*
  rep 2 at a slower pace. Pace and HR are anti-correlated across the session.
- Carryover runs **backwards**: 117 → 102 → 100 → 91. Recovering progressively
  *deeper* mid-session is not a thing bodies do.
- Recovery drops of 75 bpm in 107s — consistent with an optical sensor
  overshooting downward when the wrist goes still.

Two automatic flags catch it, both of which drop the session to LOW:

1. `carryoverTotal < −10 bpm` — backwards mid-session
2. pace rising while `hrPeak` falls — anti-correlation

**At LOW confidence: render the facts, withhold the verdict.** Same posture as
the Ask surface — the numbers always render, the read is the bonus, never a
dependency.

### 2.5 Heat — measured, and small enough to leave alone

The heat question was open when this doc was first written. It has since been
**measured on Rio's own data**, and the answer reverses the earlier lean toward
correcting for it.

**Method.** Strava carries no `temp` stream on any of these activities, so
hourly temperature and dew point came from Open-Meteo's archive for Austin
(30.267, −97.743), joined to each run's local start hour. Two independent
estimators:

| estimator | n | EF change per 10°F |
|---|---|---|
| Same-day doubles (AM vs PM, identical fitness) | 12 pairs | **−1.6%** (median) |
| OLS, EF ~ temp + day-trend, aerobic band | 79 sessions | **−1.1%** |

**Mechanism confirmed:** holding pace inside a fixed 3.30–3.85 m/s band, HR
rises **+1.2 bpm per 10°F**. Same speed, more heartbeats. Correct sign,
plausible magnitude, and broadly consistent with the existing dew-point pace
model in `pace-heat-adjustment.ts` (which implies ~3.75% for a 78°F/75°F-dew
rep; this coefficient predicts ~3% over the same gap — independent derivation,
same ballpark).

**But heat explains almost nothing.** R² is 0.03–0.06. Roughly 95% of
session-to-session EF variance is something other than temperature — sensor
noise, terrain, fatigue, how the athlete felt.

**And the bias on the actual window comparison is below the noise floor:**

| band | recent 4wk | prior 8wk | Δ | implied EF bias |
|---|---|---|---|---|
| aerobic | 82.9°F | 80.8°F | +2.1°F | **−0.31%** |
| work | 77.2°F | 74.4°F | +2.7°F | **−0.41%** |

Against `EF_DIR_PCT = 1.5%`. The bias is about a quarter of the threshold and
cannot flip a verdict. The reason is athlete behaviour, not luck: Rio runs at
the same hour year-round, so both windows contain the same mix of dawn and
evening runs and the seasonal component largely cancels.

**Decision: keep raw pace ÷ raw HR. Do not correct.** Two reasons:

1. The bias is 0.3%; the threshold is 1.5%.
2. The coefficient carries roughly ±50% uncertainty (R² 0.03–0.06, 12 pairs,
   two of them sensor artifacts). **You do not correct a small bias with a
   noisy estimator** — it adds more error than it removes.

**The guard (build this instead of a correction).** Compute the bias; disclose
it only when it is material. Take the session-weighted mean run-time
temperature of each window, multiply the delta by `HEAT_EF_PCT_PER_10F = -1.5`,
and if the implied bias exceeds **one third of `EF_DIR_PCT` (i.e. 0.5%)**,
either widen the confidence tier or print the condition — *"this comparison
spans a 24°F swing."* Otherwise say nothing. A few lines, no drift model, and
it surfaces a condition rather than silently adjusting a number behind the
athlete's back — the same posture as niggles.

**The three cases where the guard fires, and must:**

1. **Windows straddling a season change.** Rio's 12 weeks sit entirely inside
   summer. A window running April→June or September→November sees a 30–40°F
   dawn swing — around 5% bias, more than triple the threshold. Without the
   guard that is a fake "less efficient" every spring and a fake "fitter" every
   autumn.
2. **Athletes without a fixed run time.** Rio's consistency is doing the work
   here. Mornings in July and evenings in October gets the full swing.
3. **Colder climates.** Austin's dawn range is compressed next to somewhere
   with a real winter.

**You cannot fit this coefficient on key sessions.** The WORK band returns
**+8% per 10°F** — wrong sign, physiologically impossible. Cause: nearly every
workout is run at dawn, so the temperature range is only 67–81°F across 18
sessions and the variation inside it is noise. **Fit on easy runs** (79
sessions across 68–98°F), **apply everywhere.** This is a structural property
of how athletes train, not a data-collection gap that more logging fixes.

Refit per athlete once they have ~40 aerobic sessions spanning ≥20°F; until
then use the default.

### 2.6 Thresholds

Direction is only called when the move clears noise. The HR feed is heavily
smoothed (§4.2), so per-rep `hrr60` carries roughly ±3 bpm.

| axis | threshold (total across set) | reference |
|---|---|---|
| recovery | **8 bpm** | 10×1km measured −11.5 |
| carryover | **10 bpm** | 10×1km measured +16.1 |
| pace | **0.02 m/s** (~2 s/mi) | 10×1km measured −0.1 |
| HR cost | **2 bpm** | 10×1km measured +5.6 |

Minimum 4 usable reps to call any slope; HIGH confidence needs 6.

---

## 3 · The session read

Combination, not any single axis:

| pace | HR cost | recovery | read |
|---|---|---|---|
| holds | flat | holding | comfortably inside capacity |
| holds | rising | — | held it, at the edge |
| holds | — | closing | held it, at the edge |
| fades | flat | — | faded without cost rising — pacing or unwillingness, not clearly fatigue |
| fades | rising | closing | over the edge |

**Recovery closing + carryover accumulating is the earliest honest signal** that
a session went past capacity — earlier than pace fade, which shows up a rep
later or not at all.

Run against the reference session:

```
10 × 1km, 2026-08-11
  recovery level (rep 1 hrr60)   45.4 bpm
  recovery across set            -11.5 bpm  → closing
  carryover                      +16.1 bpm  → accumulating
  pace                            -0.1 m/s  → fading
  HR cost                         +5.6 bpm  → rising
  8 reps used · confidence HIGH
```

All four axes agree. That is a genuinely hard session, read correctly, and it is
invisible to every pooled metric currently in the codebase.

---

## 4 · Known limits

### 4.1 The final-rep kick

The reference session's last rep is its **fastest** (5:17 after drifting to
5:34). A linear slope reads that set as "fading"; a coach reads it as "she had
something left." A monotone slope cannot see a kick, and the kick is real
information about reserve.

**Unresolved.** Options: report the last rep separately from the trend of reps
1..n−1; or fit the trend excluding the final rep and report the final rep as a
"close" figure. Do not paper over it with a fancier fit — the shape is
bimodal on purpose and should be reported that way.

### 4.2 The HR feed is smoothed

The reference session has **99 consecutive seconds at exactly 171 bpm**, and
31.4% of its samples sit in frozen runs of ≥20s. Beat-to-beat variation cannot
produce that. Consequences: `hrPeak` has effective resolution ±1–2 bpm, and
small `hrPeak` differences between reps are not meaningful. The `hrr` figures
survive because they span large deltas.

### 4.3 Optical vs strap

Optical wrist HR is at its worst precisely here — rapid post-effort decreases
are where it lags most, and it can lock onto cadence and show a phantom
plateau. Strava exposes device info. Mark optical-source recovery readings as
lower confidence rather than treating them as equivalent, or the app will
narrate a hardware artifact as fatigue. **The 5×4min session is exactly this
failure mode.**

---

## 5 · Where it goes

- **Compute at ingest, persist per-rep.** `COST-AUDIT-2026-08-13.md` names
  `external_streams` the single largest cost in the app. This belongs in
  `compute-workout-features` writing a per-rep JSONB array onto
  `workout_features` — **never computed on read**. Same discipline as
  `quality_load`.
- **One copy of the formula**, in `_shared/`, as pure functions with tests.
  Two copies is how four disagreeing key-session rules happened.
- **Additive column, no migration risk.** Nothing existing reads it.
- Head-to-head is the natural consumer: `HEAD-TO-HEAD-POOL-APPLY.md` is already
  moving toward shape-aware row selection. Rep-by-rep comparison on
  **structurally matched** sessions (5×1mi w/400 jog against the same session
  six weeks later, rep 1 vs rep 1) is the cleanest controlled experiment
  training data offers — rep 1 is always run fresh.

---

## 6 · Decisions

### RESOLVED 2026-08-14 · Heat — option (a) plus a guard

`fitnessSignal` stays on raw pace ÷ raw HR. **Do not enable
`useHeatAdjustedPace` there** — it would correct the numerator and leave the
denominator raw, bending the ratio twice in the same direction and reporting
the athlete as *more* efficient in the heat. Raw/raw is self-consistent; the
half-measure is the only genuinely wrong option.

Build the disclosure guard in §2.5 instead of a correction. Constants:

```
HEAT_EF_PCT_PER_10F = -1.5     // measured, aerobic band, Rio 2026-05→08
HEAT_HR_BPM_PER_10F = +1.2     // the mechanism, at matched pace
HEAT_DISCLOSE_FRACTION = 1/3   // of EF_DIR_PCT → discloses at 0.5%
```

Note the live inconsistency this leaves standing: `trends-timeline` DOES pass
`useHeatAdjustedPace: true`, so the timeline and the efficiency signal hold
different opinions about what a pace was worth. That is defensible — they
answer different questions — but it should be a documented choice rather than
an accident, which is what it currently is.

### Resolved since (2026-08-15)

1. ~~The final-rep kick~~ — **decided + built**: reported separately, trended
   over reps 1..n−1 (`_shared/repSignal.ts`, test-locked).

2. ~~Surface~~ — **decided**: Key Session detail (iOS, pending) + the
   `current_fitness` Ask analyzer (built, registered).

3. ~~Device type detection~~ — **built**: the stream blob's meta carries
   `device_name`/`device_model` (vital-webhook stamps it). `classifyHrSource`
   maps strap/optical/unknown, erring toward unknown. Policy: strap/unknown
   unchanged; optical caps HIGH→MEDIUM (provisional — revisit with a
   strap-vs-optical comparison set); the withheld copy names the sensor.
   Today's Garmin metadata often says just "Garmin" (the account, not the
   sensor) → unknown → no behaviour change until richer metadata flows, but
   the plumbing is live end to end.

### Still open

4. **Weather backfill coverage.** The guard needs run-time temperature on every
   session. `fetch-workout-weather` stores `temperature_f` and `dew_point_f`
   from Open-Meteo and there is a backfill cron
   (`20260813200000_backfill_weather_actuals_cron.sql`) — confirm coverage is
   complete over the trailing 12 weeks before the guard can be trusted, since a
   window with missing weather silently under-reports its own bias.

5. **Junction/Vital historical backfill depth — the beta go/no-go gate.** With
   Garmin mandatory, history-at-connect decides the whole cold-start
   experience: ≥90 days → EF baseline + race anchors on day one; less → the
   bootstrap-trajectory mode becomes necessary. Verify with a test Garmin
   connect and count the days landing in `training_logs` BEFORE recruiting.

6. **Race-confirmation onboarding** — iOS flow specced in
   RACE-CONFIRM-ONBOARDING-APPLY.md, including the conditions auto-stamp and
   the both-platforms wiring rule for `raceNormalization.pickAnchorIndex`.

---

## 7 · Explicitly not in this

- **No prescription.** The score measures; it does not say "back off" or "you
  are overtrained." Consistent with AI-advises-never-acts and the niggles
  surface-never-interpret posture.
- **No cross-athlete comparison.** Every threshold here is athlete-relative and
  protocol-relative. HRR after a jog is not HRR after standing rest, and
  neither is comparable to published clinical HRR60 norms — those are all
  post-cessation.
- **No change to `fitnessSignal`'s pooled EF.** That number stays as the level.
  This adds the shape alongside it.
- **No steady/progression/long-run durability read.** Rio flagged that decoupling
  is gated to `workoutKind === "long_run"`, so steady runs and progressions get
  no durability read at all. Real gap, different spec.

---

## Appendix · Reference implementation

Calibration scripts, run against real data this session:
`/tmp/calibrate.py` (normalisation test), `/tmp/score.py` (scorer + verdict),
`/tmp/heat.py` (heat coefficient, doubles, window bias), per-rep JSON in
`/tmp/repdata/<activity_id>.json`, per-session EF in
`/tmp/ef/summary_{recent,mid,old}.json`, Austin hourly weather in
`/tmp/wx/austin.json`. These are throwaway Python that produced the numbers
above — the shipping implementation is TypeScript in `_shared/`, and the tests
should reproduce the three verdicts in §3, the gate in §2.2, and the window
bias in §2.5 as fixtures.

**Reproducing the heat fit.** Activities were pulled from the Strava MCP
(`get_activity_streams`, max resolution, streams `time` / `heart_rate` /
`velocity_smooth` / `distance` / `moving`). Sample filter: `moving == true`,
`90 <= hr <= 200`, `v >= 2.0 m/s`. Aerobic band `3.30 <= v < 3.85`, work band
`v >= 4.60`. A band needs ≥300s to yield a reading. Weather is Open-Meteo
archive, hourly, joined on local start hour. Two sessions are excluded as
sensor artifacts and are named in §2.5's source data: `2026-06-01` (HR capped,
never exceeded 139 all run) and `2026-08-04` (only 544s in the aerobic band).

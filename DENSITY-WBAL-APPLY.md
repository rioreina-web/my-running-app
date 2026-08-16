# DENSITY / W′-BALANCE — APPLY

Add a rep-length / recovery-density term to the load model. Right now
`stress_load` (`compute-workout-features`, Tier 1: `intensity_score ×
duration`) treats "10×1K @ threshold" as *harder* than "6mi continuous @
threshold" — backwards from what any coach would tell you — because it just
sums weighted minutes across every bout, rest jogs included, with no notion
that recovery lets you absorb more work at the same cost.

**Status: two mechanisms, only one is ready to build.** Reps *above* critical
speed (mile/5K/3K pace) are a real anaerobic-capacity story and W′-balance
models it correctly — Phase 1 below is implementation-ready. Continuous vs.
broken work *at or near threshold* is a different mechanism (cardiac drift,
not anaerobic depletion) and needs its own design — Phase 2 is a sketch, not
a spec. Do not build Phase 2 by extending the W′-balance code; it will not
work (see §0.2).

---

## 0 · Why

### 0.1 — The current model inverts the ordering

Reproduced with the existing `ZONE_WEIGHTS` / `paceWeight()` math
(`supabase/functions/_shared/workoutSegmentation.ts`) and the Tier-1
`stress_load` formula (`compute-workout-features/index.ts:106-108`), for an
athlete anchored on 5:25 marathon pace (hmp/threshold anchor = 5:12/mi, easy
anchor = 7:13/mi), all three workouts holding the *same* total quality
distance (~6mi) at the *same* pace:

| workout | qual. mi | total min (incl. rest) | stress_load |
|---|---|---|---|
| 10 × 1K @ threshold (2min jog ×9) | 6.21 | 50.3 | **122.9** |
| 3 × 2mi @ threshold (4min jog ×2) | 6.00 | 39.2 | **109.3** |
| 6mi continuous @ threshold | 6.00 | 31.2 | **101.3** |

The model currently scores the broken-up session as *hardest*, because every
rest-jog minute adds its own weighted-minutes on top of the quality time.
There is no term that credits recovery for letting the athlete do the same
(or more) quality work at lower physiological cost.

### 0.2 — Why W′-balance is the right fix for reps above CS, and the wrong fix for threshold work

Fit critical speed (CS) and anaerobic capacity (D′) from this athlete's own
mile/10K zone paces (§1.1 — no new data required) and run the classic
depletion/reconstitution model against real bout paces:

**At threshold pace (this athlete's original example) — the model reports zero difference:**

| workout | D′ remaining | peak depletion |
|---|---|---|
| 10 × 1K @ threshold | 196 m | 0.0% |
| 3 × 2mi @ threshold | 196 m | 0.0% |
| 6mi continuous @ threshold | 196 m | 0.0% |

This isn't a bug — it's what "threshold" *means*. Threshold pace is defined
as roughly the boundary of sustainability (~60min max effort), which sits at
or just below CS in the two-parameter model. By construction, W′ isn't
touched there, continuous or not. The real reason 6mi continuous at
threshold is harder than 10×1K at threshold is cardiac drift and
accumulated muscular/thermal fatigue over unbroken duration — a different
mechanism, addressed in Phase 2.

**Above critical speed — the model differentiates correctly, validated on a
pace the fit never saw.** CS/D′ here are fit from *mile* and *10K* only
(§1.1), so testing at those two paces would be circular — of course a
continuous rep at mile pace depletes D′ at ~1 mile, D′ was sized by
construction to make that true. 5K pace is an independent check:

| workout | D′ remaining | peak depletion |
|---|---|---|
| continuous 5K @ 5K pace | 0 m | 100.0% |
| 5 × 1K @ 5K pace (90s jog) | 91 m | 53.5% |
| 10 × 400m @ 5K pace (60s jog) | 139 m | 28.8% |

Correctly orders broken-easier-than-continuous, on a pace outside the fit.

**Correction — "continuous at mile pace" isn't a real training comparison.**
An earlier draft of this check used "3200m continuous @ mile pace" as a
sanity test. That's not a workout anyone runs — nobody holds mile-race pace
for two continuous miles — and worse, it's circular for the reason above.
The model's own maximum-sustainable-continuous-distance
(`D′ / (v − CS)`, at this athlete's fitted CS = 5:04/mi, D′ = 196m) makes the
real shape of the problem clear:

| pace | max continuous before D′ hits zero |
|---|---|
| threshold (5:12) | — (at/below CS; see caveat below) |
| 10K (4:58) | ≈ 6.2 mi (~31min) |
| 5K (4:46) | ≈ 2.1 mi (~10min) |
| 3K (4:37) | ≈ 1.4 mi (~6min) |
| mile (4:27) | ≈ 1.0 mi (~4:27) |

At 10K pace, a realistic *continuous* comparator exists (a 10K time trial) —
broken-vs-continuous is a genuine choice a coach faces. At mile/3K pace,
there effectively isn't one past ~1 mile — those paces are "reps only" in
practice, and the density question there isn't "broken vs continuous" so
much as "how much total quality volume can this athlete bank broken, that a
continuous effort couldn't touch at all."

**Second correction — "sustainable indefinitely" at/below CS is a model
artifact, not a physiological claim.** The two-parameter CP/CS model is only
validated over roughly 2–40min efforts; it has no glycogen, fueling, or
thermoregulation term, so it will report *any* pace at or below CS as
sustainable forever. That's false at long enough duration — a 40K run at 85%
effort is a real counterexample: an athlete will slow down eventually, just
not from a depleted anaerobic tank. The limiter past roughly an hour is
fuel and heat, on an hours-long clock, not the minutes-long clock D′-balance
runs on. Do not use this model, or claim "sustainable indefinitely," for
anything long-run/marathon/ultra-adjacent — that is a third mechanism,
noted alongside Phase 2 in §4.

**Scope for this document: Phase 1 (W′-balance, above-CS reps, roughly
2–40min effort durations) is fully specced below. Phase 2 (drift at/near CS,
and fueling/thermoregulation over long continuous efforts) is a design
sketch (§4) — do not implement either from this doc alone, and do not
extend Phase 1's math past its validated window to cover them.**

---

## 1 · Phase 1 — Critical speed / D′ fit (athlete-level constant)

### 1a. Fit CS and D′ from the athlete's own pace ladder

No new data collection. `derivePaceTableFromGoal` (`paces.ts`) already
produces `mile` and `tenK` paces for every athlete with a zone table. Fit the
classic two-parameter hyperbolic model off those two points:

```ts
// supabase/functions/_shared/criticalSpeed.ts (new file)

const METERS_PER_MILE = 1609.34;
const TEN_K_METERS = METERS_PER_MILE * 6.21371;

export interface CriticalSpeedFit {
  csMetersPerSec: number;   // critical speed
  csPaceSecPerMile: number; // for display / comparison to other anchors
  dPrimeMeters: number;     // anaerobic distance capacity ("the tank")
}

/**
 * Fits CS/D' from two paces on the athlete's own Riegel-derived ladder
 * (mile + 10K). This is a linearization of the same curve the rest of the
 * pace system already uses — not independent data, which is intentional:
 * it's always available, deterministic, and needs zero new inputs. The
 * honest caveat: because both points come from ONE goal-race projection,
 * this is only as good as that projection. Upgrade path (not this phase):
 * refit from the athlete's actual confirmed_races when two exist in the
 * valid 2-15min window (mile/3K/5K/10K only — half/marathon invalidate the
 * two-parameter model and must never be used as fit points).
 */
export function fitCriticalSpeed(
  milePaceSecPerMile: number,
  tenKPaceSecPerMile: number,
): CriticalSpeedFit | null {
  if (!milePaceSecPerMile || !tenKPaceSecPerMile || milePaceSecPerMile <= 0 || tenKPaceSecPerMile <= 0) {
    return null;
  }
  const tMile = milePaceSecPerMile;
  const t10k = tenKPaceSecPerMile * 6.21371;
  const dMile = METERS_PER_MILE;
  const d10k = TEN_K_METERS;

  const cs = (d10k - dMile) / (t10k - tMile);
  const dPrime = dMile - cs * tMile;
  if (!(cs > 0) || !(dPrime > 0)) return null; // degenerate ladder — don't lie

  return {
    csMetersPerSec: cs,
    csPaceSecPerMile: METERS_PER_MILE / cs,
    dPrimeMeters: dPrime,
  };
}
```

Store the fit on `athlete_state` alongside `pace_zones` (it's an athlete
constant, not a per-workout value) — add `critical_speed: { cs_mps, d_prime_m
}` to the JSON blob `rebuildAthleteState` already writes
(`_shared/athlete-state.ts:1829`). Recompute whenever `pace_zones`
recomputes, same trigger.

### 1b. D′-balance per workout (compute-workout-features)

Bouts are already piecewise-constant pace over known durations
(`workoutSegmentation.ts` `Bout[]`), so integrate analytically per bout
rather than simulating second-by-second:

```ts
// supabase/functions/_shared/criticalSpeed.ts (continued)

/**
 * D'-balance depletion/reconstitution, integrated bout-by-bout. Depletion
 * above CS is exact (linear in time). Reconstitution below CS uses Skiba's
 * exponential-toward-full form; `tau` (recovery time constant, seconds) is
 * the ONE unvalidated piece of this model — see §3.
 */
export function dPrimeBalance(
  bouts: Array<{ paceSecPerMile: number; seconds: number }>,
  fit: CriticalSpeedFit,
): { minBalanceMeters: number; peakDepletionPct: number; finalBalanceMeters: number } {
  let bal = fit.dPrimeMeters;
  let minBal = fit.dPrimeMeters;

  for (const b of bouts) {
    const v = METERS_PER_MILE / b.paceSecPerMile;
    if (v > fit.csMetersPerSec) {
      // Depletion is linear in time — no need to step second-by-second.
      bal = Math.max(0, bal - (v - fit.csMetersPerSec) * b.seconds);
    } else {
      // Reconstitution — exponential toward full, closed-form over the
      // whole bout (equivalent to stepping it, since tau is constant
      // within a bout).
      const t = provisionalTau(v, fit.csMetersPerSec);
      bal = fit.dPrimeMeters - (fit.dPrimeMeters - bal) * Math.exp(-b.seconds / t);
    }
    minBal = Math.min(minBal, bal);
  }

  return {
    minBalanceMeters: minBal,
    peakDepletionPct: (1 - minBal / fit.dPrimeMeters) * 100,
    finalBalanceMeters: bal,
  };
}

// PROVISIONAL — see §3. Deeper recovery (further below CS) reconstitutes
// faster; shallow recovery (barely below CS) reconstitutes slowly. The
// SHAPE is standard Skiba; the constants are not running-calibrated.
function provisionalTau(vRecovery: number, cs: number): number {
  const deficitPct = Math.max(0, (cs - vRecovery) / cs) * 100;
  const TAU_MIN = 25, TAU_MAX = 280;
  return TAU_MAX - (TAU_MAX - TAU_MIN) * Math.min(1, deficitPct / 45);
}
```

### 1c. How this composes with the existing load number

Do **not** replace `stress_load`. `intensity_score × duration` stays the
canonical minute-by-minute load — it's load-bearing everywhere (ACWR, TSB,
`workloadScore.ts`, the week-load chart) and changing its meaning under
everyone is how Maya's easy-day number silently drifts. Instead, add a
**separate signal** that only fires for sessions with real above-CS content:

- New `workout_features` columns: `d_prime_peak_depletion_pct DOUBLE
  PRECISION`, `d_prime_min_balance_m DOUBLE PRECISION`. Null when the
  workout never crosses CS (i.e., every easy/moderate/steady/threshold-only
  session — the common case — leaves these null, not zero; zero would claim
  "measured, no depletion" when the honest answer is "not applicable").
- Surface `d_prime_peak_depletion_pct` next to the existing rep-structure
  fields (`hard_segment_count`, `avg_hard_segment_duration`) as a *density*
  reading on interval sessions — "that set cost you 62% of your matchbook,"
  not a replacement number for the athlete-facing Workload Score. Whether it
  ever feeds back into `computeWorkloadScore` (`workloadScore.ts`) as a
  secondary multiplier is a follow-up decision once the depletion numbers
  have been sanity-checked against a few weeks of real sessions — don't wire
  it into the athlete-facing score in this phase.

### 1d. Fallback

`fitCriticalSpeed` returns `null` when `mile`/`tenK` anchors are unavailable
(thin zone table — same condition `buildZoneAnchors` already degrades
gracefully for). `dPrimeBalance` is simply not computed; the two new columns
stay null. No athlete ever sees a fabricated depletion number.

---

## 2 · What Phase 1 does NOT cover

Three domains, three mechanisms — Phase 1 only builds the middle one:

| domain | duration | mechanism | status |
|---|---|---|---|
| above CS (mile/3K/5K/10K-pace reps) | seconds–~40min | anaerobic capacity (D′) | **Phase 1 — this doc** |
| at/near CS (threshold/tempo, continuous vs. broken) | minutes–~90min | cardiac drift + accumulated fatigue | Phase 2 sketch, §4 |
| well below CS, very long duration (long runs, marathon-sim, ultra volume) | hours | glycogen / fueling / thermoregulation | not scoped, §4 |

Threshold-pace continuous-vs-broken (this athlete's original example) and
long-run fueling limits (the 40K-at-85% case) are both out of scope for
Phase 1 by design (§0.2). Do not extend `provisionalTau`, lower the CS
estimate, or otherwise stretch this model to cover either — that would be
curve-fitting the model to the anecdote rather than modeling the actual
mechanism, and the CP/CS model is not validated at those durations regardless.

---

## 3 · Open risk — the recovery time constant is not validated

`provisionalTau` is the single biggest unknown in Phase 1. Skiba's original
constants (`546·exp(-0.01·DCP) + 316`) are fit to *cycling power in watts* on
a large dataset; there is no equivalent running-pace-calibrated version in
the literature that this port can lean on. `provisionalTau` keeps the
correct *shape* (deeper recovery ⇒ faster reconstitution) but the exact
numbers (25s–280s) are a placeholder, not a citation.

Before trusting `d_prime_peak_depletion_pct` for anything athlete-facing:
validate it against a handful of this athlete's own real interval sessions
— does peak depletion track with where they actually started fading (rep
splits, RPE, HR)? Tighten `TAU_MIN`/`TAU_MAX`/the 45%-deficit cutoff against
that, not against a formula from cycling.

---

## 4 · Phase 2 (sketch, not a spec) — two mechanisms, neither built

### 4a. Drift, at/near CS (minutes–~90min): "6mi continuous @ threshold vs. 10×1K"

The mechanism is cardiac drift: HR rises through a sustained effort held at
fixed pace, and a rest break resets it. This is measurable directly, not
modeled hypothetically — `avg_heart_rate` is already computed per bout
(`Bout.avgHr` in `workoutSegmentation.ts`), so a continuous threshold block
and a broken one produce genuinely different HR trajectories in data
already being captured.

Rough shape for a future spec (do not build from this paragraph alone):

- For bouts at/below CS but above easy pace (the threshold/steady band
  W′-balance ignores), compute intra-bout HR drift — e.g., HR in the back
  half of a sustained bout vs. the front half, normalized for pace (since
  HR should be flat at constant pace if there's no drift).
- A rest break of sufficient length resets the drift clock — same
  `isRest`/rep-boundary detection `coalesceReps` already does for pace.
- This needs several real sessions with HR data per athlete before the
  "sufficient length" and "normalized drift" thresholds can be set
  honestly — it's a data-driven fit, same posture as §3, not a formula to
  guess at up front.

### 4b. Fueling/thermoregulation, well below CS, hours long: "40K @ 85% effort"

A different limiter entirely, and neither W′-balance nor HR drift will
capture it — this is glycogen depletion and heat accumulation over a
multi-hour continuous effort (long runs, marathon-simulation workouts, ultra
volume), not anything about pace relative to CS. The signature isn't a
depleting battery or a rising HR-at-constant-pace; it's an athlete who *has*
to slow down past some duration-at-intensity to keep going at all, largely
independent of how fast CS says they could theoretically sustain it.

Not scoped in any detail here — flagging so it isn't lost. Likely needs its
own duration-vs-intensity curve (something in the shape of the well-known
glycogen-depletion literature, roughly a ~90–120min horizon depending on
intensity and fueling), and probably belongs closer to the existing
`longRun` pace-ratio handling in `paces.ts` (`TRAINING_MP_SPEED_RATIO.longRun
= 0.80`) than to anything in this document. Do not attempt to fold it into
`dPrimeBalance` — wrong mechanism, wrong timescale.

---

## 5 · Validation script

The numbers in §0 were produced by a standalone prototype (not committed) —
`fitCriticalSpeed` + `dPrimeBalance` above are the production-shaped
versions of that same math, so re-running the six scenarios through the real
functions once they land should reproduce §0's tables exactly. Add that as
the first unit test in `_shared/criticalSpeed.test.ts` before wiring
anything into `compute-workout-features`.

# QUALITY LOAD V2 — APPLY

Three changes to the session score, all landing in
`supabase/functions/_shared/qualityLoad.ts` and
`supabase/functions/_shared/workoutSegmentation.ts`. Nothing here touches
`stress_load`, `intensity_score`, ACWR, TSB, or the week-load chart.

1. **Steepen the top of `ZONE_WEIGHTS`** — 5K/3K/mile paces are lactic events
   and the current ladder under-rates them per minute.
2. **Density term** — a rep's length relative to the longest the athlete could
   hold that pace continuously. Fixes the model scoring `10 × 1K @ HM` and
   `10K continuous @ HM` *identically* today (104.9 both).
3. **Cumulative fatigue term** — time on feet, scaled continuously by
   intensity, so a marathon and a 20mi MP session finally cost what they cost.

Calibration athlete throughout: MP 5:25/mi (2:22 marathon). easy 7:13,
moderate 6:22, steady 5:42, MP 5:25, HM 5:12, 10K 4:58, mile 4:27.

---

## 0 · Why

### 0.1 — The model cannot see rep structure at all

Same pace, same 10.0 km of quality, only rep length differs:

| workout | today | should be |
|---|---|---|
| 10 × 1K @ HM | 104.9 | easiest |
| 5 × 2K @ HM | 104.9 | middle |
| 10K continuous @ HM | 104.9 | hardest |

`seconds × ZONE_WEIGHTS[zone]` has no term for how the work was broken up, so
all three are identical to the decimal.

### 0.2 — Long, sustained work is under-scored

A marathon scores 355.0 — only 1.6× a half marathon, against a real recovery
cost closer to 2.5–3×. `12 mi @ MP` and a `20 mi easy long run` are both just
"weight × minutes" with no term for accumulated depletion.

### 0.3 — Lactic paces are flat per minute

mile 8.0 / 3K 6.75 / 5K 5.5 against MP 2.5. A judgment call, but those paces
buy far more fatigue per minute than a 3.2× ratio over MP suggests.

---

## 1 · Change 1 — `ZONE_WEIGHTS` top end

`supabase/functions/_shared/workoutSegmentation.ts`:

```ts
export const ZONE_WEIGHTS: Record<Zone, number> = {
  recovery: 1.0,
  easy: 1.0,
  moderate: 1.4,
  steady: 2.15,
  mp: 2.5,
  hmp: 3.25,
  "10k": 4.0,
  "5k": 6.75,   // was 5.5
  "3k": 8.75,   // was 6.75
  mile: 11.0,   // was 8.0  — top anchor; faster still extrapolates past it
};
```

`paceWeight()` interpolates between these knots, so raising three anchors
re-slopes the two segments each touches. Check the slope table stays monotone
after the change (it does at these values — 10K→5K, 5K→3K and 3K→mile all
steepen together).

**Known consequence, accepted:** this moves the race ladder *away* from
recovery-time proportionality, because the mile race is the denominator and it
gains the most. 3K goes 1.6× → 1.5× the mile, Half 6.2× → 4.5×. Per-minute
intensity and ladder-vs-recovery-cost are different targets that pull in
opposite directions; this change picks per-minute intensity deliberately.

---

## 2 · Change 2 — density (rep length vs. the pace's own ceiling)

### 2a. The ceiling comes free from the existing ladder

The longest an athlete can hold a given pace continuously is the race duration
implied by `derivePaceTableFromGoal` (`paces.ts`). HM pace's ceiling **is** a
half marathon (68:07 for this athlete); 10K pace's is a 10K. No new constants,
no new data, and it self-scales across athletes and paces.

```ts
// supabase/functions/_shared/density.ts (new)

/**
 * The longest continuous effort the athlete could sustain at `paceSecPerMile`
 * — i.e. the race distance whose equivalent pace IS this pace, inverted off
 * the same Riegel ladder `derivePaceTableFromGoal` already uses. Returns null
 * for paces at or slower than `steady`, where the two-parameter race ladder
 * does not apply and density is not modelled (see §2c).
 */
export function maxContinuousSeconds(
  paceSecPerMile: number,
  equivalentPaceForDistance: (distanceMiles: number) => number,
): number | null {
  let lo = 0.4, hi = 40;                       // miles, bisect the ladder
  for (let i = 0; i < 90; i++) {
    const mid = (lo + hi) / 2;
    if (equivalentPaceForDistance(mid) < paceSecPerMile) lo = mid; else hi = mid;
  }
  const d = (lo + hi) / 2;
  const t = equivalentPaceForDistance(d) * d;
  return isFinite(t) && t > 0 ? t : null;
}

export const DENSITY_K = 0.10;   // max +10%, reached only by racing the distance
export const DENSITY_P = 0.7;    // concave — early minutes of a rep cost more

/** Multiplier for ONE work bout. 1.0 for non-work bouts and unknown ceilings. */
export function densityMultiplier(
  boutSeconds: number,
  ceilingSeconds: number | null,
): number {
  if (!ceilingSeconds || ceilingSeconds <= 0 || boutSeconds <= 0) return 1;
  const fraction = Math.min(1, boutSeconds / ceilingSeconds);
  return 1 + DENSITY_K * Math.pow(fraction, DENSITY_P);
}
```

### 2b. Wire into `qualityLoadForBouts`

```ts
export function qualityLoadForBouts(bouts: readonly Bout[]): number {
  let weighted = 0;
  for (const b of bouts) {
    if (!b.isWork || b.seconds <= 0) continue;
    const ceiling = maxContinuousSeconds(b.paceSecPerMile, equivPace);
    weighted += b.seconds * (ZONE_WEIGHTS[b.zone] ?? 1)
                          * densityMultiplier(b.seconds, ceiling);
  }
  return Math.round((weighted / 60) * 10) / 10;
}
```

### 2c. Scope

Work bouts only (`isWork` — steady pace or faster). Easy, moderate and rest
bouts get 1.0 always, so **every easy run scores exactly what it does today**.
`aerobicLoadForBouts` (the long-run branch) gets no density — by construction
it only fires when there are no work bouts.

---

## 3 · Change 3 — cumulative fatigue

Two factors, both continuous. No cliffs — an earlier draft used a hard
85-minute gate and a 14mi steady run at 1:19 fell off it for missing by 40
seconds.

```ts
// supabase/functions/_shared/density.ts (continued)

export const FATIGUE_K = 0.0190;   // calibrated: marathon 355.0 -> 460.0 (+30%)
export const BURN_EXP  = 1.5;      // continuous intensity scale on the clock

/**
 * Smooth time ramp — cumulative/glycogen fatigue needs the clock to actually
 * run. 0 below 60min, smoothstep to 1.0 by 110min. Deliberately NOT a gate:
 * a 79-minute run and an 81-minute run must not differ by a step.
 */
export function fatigueTimeRamp(totalSeconds: number): number {
  const t = (totalSeconds / 60 - 60) / 50;
  const c = Math.min(1, Math.max(0, t));
  return c * c * (3 - 2 * c);
}

/**
 * "Burn hours" — how much tank the session drained. Each second counts at
 * `paceWeight^1.5`, normalised so easy = 1.0x. This is the scale that makes
 * easy/moderate/steady cheap and MP+ expensive:
 *
 *   easy 1.0x · moderate 1.7x · steady 3.2x · MP 4.0x · HM 5.9x · 10K 8.0x
 *
 * Uses the CONTINUOUS paceWeight, not the discrete zone weight, so there is
 * no step here either.
 */
export function burnHours(bouts: readonly Bout[]): number {
  let s = 0;
  for (const b of bouts) s += b.seconds * Math.pow(b.weight, BURN_EXP);
  return s / 3600;
}

/** Session-level multiplier applied to the final load. */
export function fatigueMultiplier(bouts: readonly Bout[]): number {
  const total = bouts.reduce((s, b) => s + b.seconds, 0);
  return 1 + FATIGUE_K * fatigueTimeRamp(total) * burnHours(bouts);
}
```

Applied once, at the end of `qualityLoadForSession`, to whichever branch ran —
`quality` or `long_run`. It is a property of the *session*, not of a bout.

**Note `b.weight`, not `ZONE_WEIGHTS[b.zone]`** — see §6.1.

---

## 4 · Expected results (regression fixtures)

Athlete above. `today` = current production. `final` = all three changes.

| session | time | today | final | Δ |
|---|---|---|---|---|
| **RACES** | | | | |
| Mile race | 4:27 | 35.6 | 53.9 | +51% |
| 3K race | 8:37 | 58.2 | 82.9 | +42% |
| 5K race | 14:48 | 81.4 | 109.9 | +35% |
| 10K race | 30:52 | 123.5 | 135.8 | +10% |
| Half marathon | 1:08 | 221.4 | 245.7 | +11% |
| MARATHON | 2:22 | 355.0 | 460.0 | +30% |
| **SPEED / VO2** | | | | |
| 8 × 400m @ mile, 2' rest | 51:45 | 70.8 | 101.1 | +43% |
| 12 × 200m @ 3K, 90" | 52:17 | 46.5 | 61.2 | +32% |
| 8 × 400m @ 5K, 90" rest | 48:52 | 52.1 | 65.1 | +25% |
| 8 × 20s strides @ mile | 38:33 | 21.3 | 29.8 | +40% |
| **THRESHOLD** | | | | |
| 10 × 1K @ HM, 60s jog | 1:10 | 104.9 | 107.0 | +2% |
| 5 × 2K @ HM, 2' jog | 1:09 | 104.9 | 107.6 | +3% |
| 10K continuous @ HM | 1:01 | 104.9 | 111.2 | +6% |
| 4 mi tempo @ HM | 49:40 | 67.5 | 70.5 | +4% |
| 6 mi tempo @ HM | 1:00 | 101.3 | 107.2 | +6% |
| **MARATHON PACE** | | | | |
| 6 × 1mi @ MP, 1' jog | 1:06 | 81.3 | 82.3 | +1% |
| 3 × 2mi @ MP, 2' jog | 1:05 | 81.3 | 82.7 | +2% |
| 6 mi continuous @ MP | 1:01 | 81.3 | 84.2 | +4% |
| 12 mi @ MP (sim) | 1:33 | 162.5 | 183.7 | +13% |
| 5 × 3mi @ MP w/800m float | 2:02 | 203.1 | 232.0 | +14% |
| **AEROBIC / LONG** | | | | |
| 7 mi easy | 50:33 | 50.6 | 50.6 | +0% |
| 10 mi easy | 1:12 | 72.2 | 72.5 | +0% |
| 12 mi easy | 1:26 | 86.7 | 88.0 | +1% |
| 14 mi steady | 1:19 | 171.6 | 176.4 | +3% |
| 15 mi moderate | 1:35 | 133.8 | 139.2 | +4% |
| 16 mi long run | 1:55 | 115.6 | 119.8 | +4% |
| 20 mi long run | 2:24 | 144.4 | 151.1 | +5% |
| 22 mi long run | 2:38 | 158.9 | 166.9 | +5% |

Ordering assertions worth pinning as tests:

- `10 × 1K @ HM` < `5 × 2K @ HM` < `10K continuous @ HM` (today: all equal)
- `15 mi moderate` > `16 mi long run` — an earlier pure-time fatigue term
  inverted this; the intensity scale is what keeps it right
- every easy-only session changes by < 1%

---

## 5 · Calibration guard

`qualityLoad.ts` header records: strides 5.4–13.1, smallest genuine session
42.1, largest 103.5, and an empty gap between 13.1 and 42.1. Client floor is
25 (`QualityLoad.floor`, `TrendsQualityLoad.swift`).

The stride case is the one at risk, and it is the one that moves most in
percentage terms (+40%, because mile-pace weight went 8.0 → 11.0). A stride
set scoring 13.1 today lands at ~18.3 — still below the floor of 25, and the
gap to 42.1 stays empty. **Re-run the 23-session calibration set before
shipping and confirm nothing crosses 25.** If a stride set does cross, raise
the client floor rather than shrinking the weight change; the floor is
client-side precisely so it can be tuned without a deploy.

---

## 6 · Findings surfaced while specifying this — decide separately

### 6.1 — `qualityLoad.ts` and `intensity_score` disagree on the same run

`qualityLoadForBouts` uses `ZONE_WEIGHTS[b.zone]` (discrete, 10 steps).
`segmentFromLaps` uses `paceWeight()` (continuous) for `intensity_score`, and
stores it on `Bout.weight`. They disagree wherever a pace sits between knots:

| pace | discrete | continuous | gap |
|---|---|---|---|
| 5:04/mi | 4.00 | 3.69 | −7.7% |
| 5:05/mi | 3.25 | 3.62 | +11.4% |
| 5:30/mi | 2.50 | 2.40 | −4.1% |

One second of pace flips 5:05 across a bucket boundary and moves the weight
11%. That is a **larger effect than the density term this document adds**, and
it means a `10 × 1K @ HM−5` session scores ~125.8 instead of ~116 purely from
bucket rounding.

Switching `qualityLoadForBouts` to `b.weight` would fix it and is a one-line
change, but it moves every historical quality score — worth its own document
and its own recalibration pass. **Not bundled here.** Change 3 uses `b.weight`
because it is new code with no history to preserve.

### 6.2 — "12+ miles" is not portable

The intent was "12+ miles starts accumulating fatigue." For this athlete 12mi
easy is 1:26:40, which the ramp barely touches (+1%). For a 2:45 marathoner
the same 12 miles is ~1:50 and lands mid-ramp. The ramp is expressed in
**time**, deliberately — glycogen depletion runs on an absolute clock in a way
pace never does — but it does mean "12 miles" means different things to
different athletes. If distance-triggering is wanted instead, that is a
product decision, not a modelling one.

### 6.3 — Still not covered: maximality

Racing a mile (4:27, 53.9) still scores below `8 × 400m @ mile pace` (101.1),
because the workout spends twice as long at that pace. No pace-weight change
can fix this — both move by the same percentage. It needs a
depletion/maximality term (W′-balance), which is specced separately in
`DENSITY-WBAL-APPLY.md` and is a different mechanism from anything here.

---

## 7 · Order of work

1. `ZONE_WEIGHTS` change + confirm `paceWeight` slopes stay monotone.
2. New `_shared/density.ts` with unit tests against §4's fixtures.
3. Wire density into `qualityLoadForBouts`.
4. Wire `fatigueMultiplier` into `qualityLoadForSession` (both branches).
5. Re-run the 23-session calibration set; confirm §5.
6. Backfill `workout_features.quality_load` — every historical session changes.

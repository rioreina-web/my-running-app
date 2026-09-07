# LOAD MODEL — WHAT'S OPEN

Session of 2026-08-13. One change shipped; everything else below is designed,
numerically explored, and **not built**. Several items reversed direction
mid-session — those reversals are recorded, because the reason matters more
than the conclusion.

Calibration athlete throughout: MP 5:25/mi (2:22 marathon). easy 7:13,
moderate 6:22, steady 5:42, MP 5:25, HM 5:12, 10K 4:58, 5K 4:46, 3K 4:37,
mile 4:27. Fitted critical speed 5:04/mi, D′ 195m.

---

## 0 · What shipped

`paceWeight()` in `workoutSegmentation.ts`: straight-line interpolation →
monotone cubic (Fritsch–Carlson). Passes through all nine anchors exactly, so
no weight is recalibrated and scores at anchor paces are bit-identical. Max
change anywhere between anchors is 1.90% (at 5:38/mi). Slope break at every
knot drops from up to 63% to under 2%.

Two tests updated (`308 → 4.71`, `353 → 2.29`), two added (slope continuity,
monotonicity). **Not yet run** — deno isn't installed locally; CI will confirm.

---

## 1 · The one that should go next — quality load is still bucketed

`qualityLoad.ts` scores with `ZONE_WEIGHTS[b.zone]` — the discrete 10-bucket
table — while `intensity_score` uses the continuous `paceWeight()` and stores
it on `Bout.weight`. Two numbers, same run, different answers.

| boundary | crossing | weight jump |
|---|---|---|
| 4:32 | mile → 3k | −16% |
| 4:42 | 3k → 5k | −19% |
| 4:52 | 5k → 10k | −27% |
| 5:05 | 10k → hmp | −19% |
| 5:18 | hmp → mp | −23% |
| 5:34 | mp → steady | −14% |
| 6:02 | steady → moderate | **−35%** |
| 6:48 | moderate → easy | −29% |

A 6-mile tempo at 5:33/mi scores 83.3; at 5:34/mi it scores 71.8. **One second
per mile, 14% of the score.** GPS drift crosses that.

The fix is one line — `ZONE_WEIGHTS[b.zone]` → `b.weight`. It is also the
reason to do it before anything else in this document: the density and lactic
terms below were tuned to ±1–2% precision against a baseline with 35% steps in
it.

**Cost:** every historical `quality_load` moves, so it needs a backfill and a
re-run of the 23-session calibration set (`qualityLoad.ts` header: strides
5.4–13.1, smallest genuine session 42.1, largest 103.5, client floor 25 in
`TrendsQualityLoad.swift`).

**Related, unresolved:** `paces.ts` declares steady as 90–100% of MP speed, so
its fast edge *is* marathon pace (5:25). `paceToZone` cuts at the anchor
midpoint, 5:34. The strip 5:25–5:34 is claimed by both definitions. Going
continuous makes this irrelevant for *scoring*; zone labels still need one
owner, and `paces.ts` is the better source since it's what the athlete sees.

---

## 2 · Density — rep length vs. the pace's own ceiling

**Settled.** `density = 1 + 0.10 × (rep seconds ÷ max continuous at that pace)^0.7`,
per work bout, work = steady or faster.

The ceiling is free: it's the race duration implied by the existing Riegel
ladder. HM pace's ceiling *is* a half marathon (68:07 here); 10K pace's is a
10K. No new constants, and it self-scales — a 400m rep is 8% of the 5K ceiling
but only 4% of the 10K ceiling.

Fixes the fact that `10 × 1K @ HM`, `5 × 2K @ HM` and `10K continuous @ HM`
currently score **104.9, 104.9 and 104.9** — identical to the decimal.

| workout | today | k=.10 |
|---|---|---|
| 10 × 1K @ HM | 104.9 | 106.2 |
| 5 × 2K @ HM | 104.9 | 106.9 |
| 10K continuous @ HM | 104.9 | 111.2 |
| 6 mi tempo @ HM | 101.3 | 107.2 |
| 3 mi continuous @ 10K | 59.6 | 63.2 |
| 2 mi continuous @ 5K | 52.4 | 56.3 |
| any race | — | +10% (capped) |
| any easy/moderate run | — | unchanged |

**Known limit:** the 1K→2K step is only +1.2% → +1.9%. Both are small bites of
a 68-minute ceiling, so the model genuinely sees them as close. Making that
step feel like "harder" needs a louder k than "subtle" allows. Accepted.

**A work:rest ratio model cannot substitute.** In `10 × 1K w/1'` vs
`5 × 2K w/2'` the per-rep work:rest is *identical* (3.23:1 both). Only rep
length separates them.

---

## 3 · Lactic — the formulation changed three times

Final shape, **not re-run across the full session set**:

```
lacticStress = time-weighted mean over work bouts of
                 (D′ depletion at the END of that bout) × L(pace)

L(pace)      = max(0, v/CS − 1) / (v_mile/CS − 1)      # 1.0 at mile pace, 0 at CS
score        = base × (1 + 0.6 × lacticStress)
```

`L(pace)` peaks at the mile and decays fast — mile 1.00, 3K 0.70, 5K 0.46,
10K 0.14, HM 0.00. That taper is deliberate: peak blood lactate peaks around
800m–mile and *falls* for longer races.

### 3a. Why "depletion at the end of each bout" and not peak session depletion

An earlier version keyed off peak *session* depletion. That accumulates across
a rep set, so `8 × 400m @ mile` hit 93% and scored nearly as high as a mile
race — the opposite of "the big jump belongs to continuous work."

A second version keyed off the deepest *single* bout. A 400m rep always
depletes 25% regardless of rest, so **rest sensitivity vanished entirely** —
8×400 w/60s and w/2' scored 87 and 86.

The final version asks how empty the tank was *while each rep was run*. Rep 8
off 60s rest is run on a far emptier tank than rep 8 off 2', though the rep is
identical. This restores rest, and scales it by how lactic the pace is:

| 8 × 400m at… | 30s | 60s | 90s | 2' | 3' |
|---|---|---|---|---|---|
| mile pace (L=1.00) | 103 | 95 | 91 | 89 | 87 |
| 3K pace (L=0.70) | 77 | 73 | 71 | 70 | 69 |
| 5K pace (L=0.46) | 58 | 57 | 56 | 56 | 55 |
| 10K pace (L=0.14) | 40 | 40 | 40 | 40 | 40 |

Spread from 30s to 3': +19% at mile pace, +10% at 3K, +5% at 5K, +1% at 10K.

### 3b. Unvalidated constant

The recovery time constant `tau` driving those depletions is ported from
Skiba's *cycling power* work — `546·exp(−0.01·DCP) + 316`. There is no
running-pace-calibrated equivalent in the literature. The version here keeps
the shape (deeper recovery ⇒ faster reconstitution) with placeholder bounds
(25s–280s, 45% deficit cutoff). **The ordering is trustworthy; the exact
59%-vs-38% spread is not.** Validate against sessions where the athlete knows
how they actually felt before anything ships athlete-facing.

---

## 4 · Cumulative fatigue — designed, then found redundant

```
fatigue    = 1 + 0.0190 × timeRamp(total) × burnHours
timeRamp   = smoothstep, 0 below 60min → 1.0 by 110min      # no gate, no cliff
burnHours  = Σ(seconds × paceWeight^1.5) / 3600
```

Burn rate normalised to easy: easy 1.0×, moderate 1.7×, steady 3.2×, MP 4.0×,
HM 5.9×. That encodes "easy/moderate/steady don't generate high-end fatigue"
as a curve.

**Two design failures worth not repeating.** A first version used pure
time-on-feet and inverted the intensity ordering — a 16mi easy long run (1:55)
outscored a 15mi moderate run (1:36), 154.9 vs 143.8, purely for taking
longer. Gating on time but *sizing by load* fixed it (150.1 vs 123.8). A
second version used a hard 85-minute gate; a 14mi steady run at 1:19 fell off
it for missing by 40 seconds. Hence the smoothstep.

**Why it's unresolved:** solving for the constant that lands the marathon on
the chosen 460 drove it to **zero**. Once the lactic term exists, it already
carries the marathon past 460 on its own. So either 506 is acceptable and
fatigue only earns its keep on long *easy* runs (where lactic = 0 and nothing
else credits time on feet), or 460 is the ceiling and the lactic taper for
MP/HM has to come down. Not decided.

---

## 5 · Reversed — do not re-apply without reading this

**ZONE_WEIGHTS top end was raised, then reverted.** 5k 5.5→6.75, 3k 6.75→8.75,
mile 8.0→11.0, to make lactic paces score higher per minute. It works for that,
but it collapses the race ladder, because short races gain on weight what they
lack in duration while the 10K anchor stays at 4.00:

```
3K → 10K gap:
  original weights, no lactic     2.12x    mile scores 39
  original weights, K_L=0.6       1.63x    mile scores 63
  bumped weights, no lactic       1.64x    mile scores 54
  bumped weights, K_L=0.6         1.25x    mile scores 86
```

And it cannot do the job it was raised for. A weight multiplies *every second*
at that pace, so it moves a mile race and 8×400 at mile pace by **identical
percentages** (+37% and +38%). It cannot distinguish a maximal effort from a
rep set, or 30s rest from 3'. Lactic cost belongs in the term that knows about
pace *and* duration *and* rest.

**The standing tension:** the mile can score 86 with a broken ladder, or 63
with a clean one. No setting gives both — a mile race is 4:27 and a 10K is
30:52, and anything fighting that compresses everything.

---

## 6 · Open questions, no recommendation

**Steady weight 2.15.** A 14mi steady run scores 185 — above a 10K race (148),
above every threshold session, above a 20mi long run (162). None of the new
terms cause it: it's `79.8 min × 2.15 = 171.6`, 93% of the score. The value was
set on 2026-08-11 for *curve shape*, and that note records only 0.8% of lap
time sat in the corridor — so it has never been exercised by real steady
volume. Dropping it re-opens the cliff that change closed: at 2.15 the slopes
either side are 0.186 and 0.205; at 1.85 they're 0.112 and 0.380.

| steady wt | 14mi steady | vs 10K race (148) |
|---|---|---|
| 2.15 | 186 | 1.25x |
| 2.00 | 173 | 1.17x |
| 1.85 | 160 | 1.08x |
| 1.70 | 147 | 0.99x |

**Marathon anchor.** 460 was chosen (from 355, +30%) after 716 was judged too
aggressive. Recovery-time rules of thumb imply closer to 17× a mile race; 460
gives about 7×. Unreconciled.

**Stacked maximal efforts.** Nothing caps how many 100%-depletion bouts one
session can contain. This is the shape most likely to produce a silly number
on real data.

---

## 7 · Free win — feasibility checking

D′-balance already contains the information to flag workouts nobody can
complete. One mile at mile pace burns exactly the whole 195m tank by
construction, so:

```
3 x 1mi @ mile pace, 5' rest    INFEASIBLE — fails rep 2 at 93% (~108m short)
3 x 1mi @ mile pace, 15' rest   INFEASIBLE — fails rep 2, barely
8 x 400m @ mile pace, 2' rest   feasible
5 x 800m @ mile pace, 2' rest   feasible
4 x 1000m @ mile pace, 2' rest  feasible
```

Worth surfacing in the plan builder before a prescription reaches an athlete —
independent of whether any of the scoring changes above ship.

---

## 8 · Suggested order

1. `qualityLoad.ts` → `b.weight` (§1), backfill, re-run the 23-session set.
   Everything else is tuned against this baseline.
2. Decide steady 2.15 (§6) — it moves more sessions than any new term.
3. Density (§2) — settled, self-contained, no new constants.
4. Lactic (§3) — needs the `tau` validation first.
5. Fatigue (§4) — only after the marathon anchor question is settled.

Related: `DENSITY-WBAL-APPLY.md` (W′-balance, above-CS reps) and
`QUALITY-LOAD-V2-APPLY.md` (the earlier weight-bump version, now superseded by
§5 — its ZONE_WEIGHTS change should not be applied).

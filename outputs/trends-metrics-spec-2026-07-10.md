# Trends metrics — the menu (spec)

*2026-07-10 · progression-first Trends surface · tested against Maya (self-coached, 3:28 PB chasing a 3:16 BQ off ~40 mpw, two years of race history, journals mood + niggles).*

Runners want to **watch the build**, not just read a race prediction. This spec formalizes the metrics that let Maya feel her progress, grounded in what the backend already computes. Everything here obeys the house rules: **ranges + confidence, never false precision**; **AI advises, never acts**; **detection, not diagnosis**; **blue = pace, warm = mood, coral = alert**.

---

## Part 1 — The Effort model (conditions-aware training load)

### What already exists (don't reinvent)

| Piece | Where | What it is |
|---|---|---|
| `intensity_score` | `_shared/workoutSegmentation.ts` | Time-weighted zone intensity per run, ~1.0–5.0. Weights: recovery/easy 1.0 · moderate 1.5 · steady 2.0 · MP 2.5 · HMP 3.0 · 10K 3.5 · 5K 4.0 · 3K 4.5 · mile 5.0. |
| `volume_x_intensity` | `_shared/weeklyAnalytics.ts`, `builders/buildLoadDistribution.ts` | Training load = `intensity_score × duration_min`, summed 7d/28d. This is *effort without conditions*. |
| Heat model | `_shared/pace-heat-adjustment.ts` ("Emy's Calculator") | Temp + **dew point** → composite → 0–12% pace penalty. Already outputs a **neutral-equivalent pace** (what you'd have run cool + dry). |
| `strain_7d`, `monotony_7d` | `compute-workout-features/index.ts` | monotony = stdev(daily miles)/mean; strain = 7d miles × monotony. |
| ACWR / load trend | `builders/buildLoadMetrics.ts`, `buildLoadDistribution.ts` | Acute:chronic; WS3 "load vs chronic" trend (spiking/building/holding/backing-off). ACWR now internal injury-input only. |
| Strava `suffer_score` | `strava-sync/index.ts` | Ingested "relative effort", surfaced verbatim. Not ours. |

There is **no single named Effort score today**, and TSS/rTSS/CTL/ATL/TRIMP were deliberately dropped. The "The Effort" screen in the mock is a pace-with-overlays chart, not a number.

### The formula

Don't bolt on a new number — feed conditions into the intensity you already compute:

```
Per-run Effort (load units) = Σ over segments:  ZoneWeight(neutralPace_seg) × minutes_seg

  neutralPace_seg = rawPace_seg ÷ (1 + heatPct) ÷ gradeFactor
    heatPct     = dew-point composite from pace-heat-adjustment.ts (temp + dew×mult, capped 12%)
    gradeFactor = asymmetric-Minetti hill cost from pace-grade-adjustment.ts
    ZoneWeight  = existing ladder (easy 1.0 … MP 2.5 … 5K 4.0 … mile 5.0)

Effort_display = Effort_load × K       // choose K so an easy hour ≈ 60
Weekly Effort  = Σ Effort_load over 7 days   // conditions-aware load; the honest ACWR replacement
```

**Why it's genuinely "effort-based":** adjust pace for heat + hills *first*, classify the zone off that neutral-equivalent pace, then load = intensity × minutes.
- **Pace** sets the zone.
- **Heat + humidity** upgrade it — a 9:00/mi run at 74°F / 70°F dew ≈ 8:38 neutral, nudging it up a zone so it scores as the harder session it was. (Dew point *is* the humidity signal — better than raw RH.)
- **Distance / volume** enter as minutes.

### Inputs — reality check
- **Populated now:** distance, duration, pace, per-lap HR & pace, elevation gain, cadence, Strava `suffer_score`, and the computed `workout_features` (intensity_score, zone seconds, HR efficiency, strain/monotony/ACWR).
- **Wired but backfill/deploy-pending:** `weather_actual` (temp_f, dew_point_f, humidity, wind — Open-Meteo, no key) and per-lap heat-adjusted pace.
- **Planned, not populated:** signed per-lap grade + grade-adjusted pace columns.

So v1 Effort ships on pace + zone + duration; **heat and hill terms switch on per-run as weather/grade backfill lands.** When conditions data is missing, show Effort without the adjustment and mark it (don't fake precision).

### One tuning note
Your own validation doc flags the dew-point table **under-penalizes extreme humidity** (69°F dew → only ~2.4%). Steepen `ADJUSTMENT_TABLE` above the 180 composite, or add a small humidity/wind term, before the score ships.

---

## Part 2 — The six progressions (formalized)

Each: definition · formula · data source · honesty note.

1. **Efficiency — "same effort, more pace."** Easy pace at a fixed HR (e.g. pace @ 145 bpm), or Efficiency Factor `EF = speed ÷ avg_HR`. Trend faster/higher = aerobic engine growing. *Source:* per-lap HR + pace (`workout_features.hr_pace_efficiency` already exists). *Honesty:* only compare like HR bands; heat inflates HR, so use neutral-equivalent pace once weather lands.

2. **Best efforts — rolling PRs.** Best 1 mi / 5K / 10K / HM / longest run detected from streams; flag a new best. *Formula:* `best_d = min(rolling window pace over distance d)` across history; PR if `best_d(now) < best_d(prior)`. *Source:* `external_streams` + `confirmed_races` anchors. *Honesty:* label effort vs race; note conditions on the day.

3. **Long-run durability — holding pace when tired.** `fade = pace(final third) − pace(first third)`; trend toward 0 / negative as long runs lengthen. HR twin: aerobic decoupling `Pa:Hr drift`. *Source:* long-run `pace_segments` + lap HR. *Payoff:* the marathon-specific confidence signal.

4. **Consistency — "you showed up."** Compliance `= sessions_done ÷ sessions_planned`; current streak; weeks-on-plan. *Source:* `training_logs` vs plan. *Honesty:* stays encouraging in a down week (speed metrics don't).

5. **Easy discipline — "your easy stayed easy."** `gap = easy_run_pace − easy_zone_target`; confirm easy miles aren't creeping fast as fitness rises. *Source:* pace zones (`derivePaceTableFromGoal`) over time. *Payoff:* what keeps the niggles quiet.

6. **Total volume — "it adds up."** Cumulative miles, block + year (`cumsum(daily_miles)`). *Source:* `training_logs`. (Renamed from the "bonus/miles-in-the-bank" placeholder.)

---

## Part 3 — New candidate metrics (with formulas)

1. **Conditions-adjusted fitness.** Plot the fitness curve on **neutral-equivalent paces** so a hot-summer block doesn't read as a plateau. *Formula:* re-run the fitness estimate on `neutralPace` per session. *Source:* fitness model + heat model (you have `conditions-adjusted-fitness-model-2026-06-21.md`). *Honesty:* widen the confidence band when weather is missing.

2. **Felt vs measured effort.** Computed **Effort** (Part 1) vs perceived effort from the voice-log (mood → RPE proxy, or an explicit 1–10). *Signal:* when *felt* > *measured* for several sessions, that's early fatigue/under-recovery. *Source:* Effort + `mood`/notes. *Very on-brand* — fuses qual + quant. *Honesty:* observe, don't diagnose ("felt harder than it measured, three runs running").

3. **Aerobic decoupling trend.** `decoupling = (Pa:Hr second half − first half) ÷ first half` on steady/long runs; shrinking over the block = durability. *Source:* lap HR + pace. Durability's HR-based twin.

4. **Polarization trend (80/20 over time).** Weekly `% easy vs % threshold-and-harder` by time-in-zone, trended — not just a static block ratio. *Source:* `effort_distribution` / zone seconds. *Payoff:* confirms she's training smart as volume climbs.

5. **Freshness / sharpening (not TSB).** Since TSB was dropped, reuse the shipped WS3 signal: `loadVsChronicPct = (recent 2wk load − chronic 8wk load) ÷ chronic`. Reframe as **Building / Holding / Backing off / Sharpening** rather than a number. *Source:* `buildLoadDistribution.ts`. *Honesty:* words + band, no fake "form" score.

6. **Negative-split habit.** `% of runs (and long runs) negative-split` over time — execution skill, not just fitness. *Formula:* count runs where `pace(2nd half) < pace(1st half)`. *Source:* `pace_segments`. *Payoff:* pacing discipline is a learnable, visible win.

*Deferred (need new capture):* sleep/recovery vs load (HealthKit sleep → Recovery pillar v1.5), cadence/stride-length durability (form), heat-acclimation curve (HR-at-pace vs dew point over a hot block).

---

## Part 4 — Build priority vs data readiness

| Metric | Data today | Effort | Ship |
|---|---|---|---|
| Efficiency (EF / pace@HR) | HR + pace populated | Low | Now |
| Best efforts (PRs) | streams + races | Med | Now |
| Long-run durability | pace_segments + HR | Low–Med | Now |
| Consistency | logs vs plan | Low | Now |
| Easy discipline | pace zones | Low | Now |
| Total volume | logs | Trivial | Now |
| **Effort (pace+zone+time)** | populated | Med | Now (v1) |
| **Effort + heat/hills** | weather/grade pending | Med | On backfill |
| Conditions-adjusted fitness | fitness + heat | Med | On backfill |
| Felt vs measured | Effort + mood | Low | Now |
| Decoupling / polarization / neg-split | streams | Med | Now |
| Freshness (words) | load builders | Low | Now |

**Recommended first cut for the app:** Effort (v1) + Efficiency + Best efforts + Long-run durability + Consistency — all ship on data that's already populated, and together they answer "am I fitter, am I durable, am I consistent" without waiting on the weather backfill.

---

## Guardrails (apply to every metric)

- **Range + confidence, never a single false-precise number** (esp. fitness/Effort). Round timestamps to whole minutes.
- **AI advises, never acts.** Metrics observe; the athlete (or coach) decides.
- **Detection, not diagnosis** for any body signal (niggles, decoupling, felt-vs-measured). No medical claims, no "rest/ice."
- **Three-palette color.** Pace = blue depth ramp; mood = warm; coral = alert/punctuation only.
- **Editorial voice.** Observation over congratulation; feeling before math.

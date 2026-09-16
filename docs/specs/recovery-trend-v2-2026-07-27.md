# The recovery read — `C0` detector spec, v2

*2026-07-27 · **supersedes `load-recovery-ratio-2026-07-27.md`** (same day). That draft proposed a load ÷ recovery ratio. A literature review run immediately after found the ratio form is not defensible and that my signal hierarchy was upside down. This version rebuilds the detector on what the evidence actually supports, and §7 records why — so nobody re-adds the ratio in six months.*

Companions: `docs/specs/trends-insights-plan-2026-07-23.md`, `outputs/trends-catalog-2026-07-23.md`, `VITAL-GARMIN-APPLY-NOTES.md`.

---

## 1. What the evidence changed

Three findings reorder the whole design. Full citations in §7.

**1. The qualitative stream is the evidenced signal. The biometrics are context.** In the only prospective study of HRV and injury in endurance runners (Sanchez et al. 2025, n=15, 180 athlete-weeks, Tim Gabbett a co-author so not a hostile null), **HRV was null at p=.225 while sleep-related impairment hit p=.004, g=0.70.** In the best runner-specific prospective cohort (Goldberg et al. 2025, n=339, 26 weeks), **soreness was elevated 2 weeks and 1 week before injury and fatigue 1 week before**; sleep *quality* carried HR 1.36. The predictive signal in runners lives in cheap self-report — soreness, fatigue, sleep quality — not in autonomic measures.

That is a remarkable result for this app specifically. The mood-and-niggles stream isn't the soft corroborating layer for the "real" Garmin data. On the current evidence it is the closest thing to a real signal in the product, and the biometrics are the corroboration. **v1 had this exactly backwards.**

**2. HRV direction is ambiguous, and the disambiguator is resting HR.** RMSSD is a *non-monotonic* function of vagal activity — proven pharmacologically under beta-blockade (Goldberger et al. 2001), and appearing in 5/17 healthy men after just 8 weeks of ordinary aerobic training (Kiviniemi et al. 2006). Worse, the Bellenger et al. 2016 meta-analysis found resting RMSSD **rises in both directions**: SMD 0.58 toward performance improvement *and* 0.26 toward performance decrement. A rising HRV is compatible with adaptation and with overreaching. HRV alone cannot be read. HRV paired with resting HR can be, and only in one of four quadrants.

**3. Menstrual cycle phase is a larger effect than training.** From the same dataset that gives the training effect (Altini & Plews 2021, 9.03M measurements, 28,175 people):

| Factor | HRV Cohen's d | Resting HR Cohen's d |
|---|---|---|
| Training (high intensity) | 0.36 (small) | 0.38 (small) |
| Alcohol | 0.55 | 0.97 |
| Sickness | 0.47 | 0.97 |
| **Menstrual cycle** | **0.80 (large)** | **1.41 (largest effect in the paper)** |

And because phase was calendar-derived rather than hormone-verified there, that is a **floor**, not a ceiling. A sustained, low-noise, two-week bias is the worst possible shape of confounder for a rolling baseline: it gets partially absorbed into the baseline, and what escapes reads exactly like accumulating training load.

---

## 2. What the card is now

**No ratio. No composite score. Two lines and a sentence.**

The `C0` card shows the **load line** and the **recovery-read line** on their own scales, with each athlete's own baseline band drawn behind, and states the relationship in words. The athlete does the interpreting; the card does the noticing. This is exactly what the critics of load metrics recommend and what the house rules already say — "range and confidence, never false precision," "detection, not diagnosis."

### 2a. Load side

`weeklyLoad[i]` = Σ `computeWeightedLoadForLog(log, features)` — `intensity_score × total_duration_seconds / 60`. Import from `_shared/weeklyAnalytics.ts`; do not reimplement. This is the volume × intensity term, unchanged from v1.

Displayed as the **raw weekly series** with an 8-week trailing baseline band (excluding the scored week). In prose, as a plain comparison: *"this week: 340 load-minutes. Your 8-week average: 250."*

**Not** divided by the baseline. If a single number is ever wanted, use a z-score against the 8-week mean with a floor on the SD — better behaved than a ratio, same intuition. Never a ratio, and never percent-change, which is algebraically the ratio minus one.

**One genuinely evidenced addition.** The largest running dataset in existence (Frandsen et al. 2025, n=5,205, **588,071 sessions, 1,820 injuries**) found that weekly ratios showed nothing but **single-session spikes did**: a run >100% longer than the longest run in the prior 30 days carried HRR 2.28 (1.50–3.48). If any load signal earns a card, it's that one — and it's session-level, not weekly. Worth a separate detector; noted here so it isn't lost.

### 2b. Recovery read — a tiered hierarchy, not a mean

Signals enter in evidence order. Tier 1 leads the sentence; Tier 2 corroborates; Tier 3 is annotation only; Tier 0 never enters the model.

| Tier | Signal | Source | Role |
|---|---|---|---|
| **1** | Niggle burden (severity-weighted) | `body_mentions` + `severity_hint` | **Leads.** Soreness elevated 1–2 wks pre-injury |
| **1** | Mood / fatigue | `TrendsWeekOut.mood` | **Leads.** Fatigue elevated 1 wk pre-injury |
| **1** | Self-reported sleep quality | *new — not currently captured* | **Leads.** The strongest single prospective signal |
| **2** | Nocturnal resting HR | `daily_biometrics.resting_hr` | Corroborates. Outperformed HRV head-to-head |
| **2** | Nocturnal HRV (lnRMSSD) | `daily_biometrics.hrv_rmssd` | Corroborates — **only paired with RHR** |
| **3** | Total sleep time | `daily_biometrics.sleep_total_min` | Annotation. Never a threshold |
| **0** | Sleep stages, sleep efficiency, Garmin Sleep Score, HRV CV | — | **Excluded.** See §7.4 |

**Tier 1 gap worth closing:** self-reported sleep quality is the best-evidenced signal in the runner literature and the app doesn't capture it. A one-tap nightly rating would be a cheaper and better input than the entire Garmin biometrics pipeline. Flagged as a product decision, not a spec item.

### 2c. The HRV × RHR quadrant — the only honest way to read HRV

Both as 7-day means vs the athlete's own 28-day baseline, thresholded on that athlete's own between-night SD (§3).

| | **RHR falling** | **RHR flat** | **RHR rising** |
|---|---|---|---|
| **HRV falling** | Possible parasympathetic saturation — *often accompanies genuine adaptation.* **Stay quiet.** | Ambiguous. **Quiet.** | **The one interpretable cell.** Eligible for `active`. |
| **HRV flat** | Quiet | Quiet | Weak — quiet unless Tier 1 agrees strongly |
| **HRV rising** | Ambiguous by construction — adaptation *or* functional overreaching. **Quiet.** | Quiet | Odd combination; likely artifact or illness. **Quiet.** |

One cell of nine reaches `active`. That is the honest yield, and it is a feature: it's what stops the card from doing what Garmin and Whoop do, which is ping people over single bad mornings in directions the literature doesn't support.

### 2d. Convergence, restated

The catalog's rule survives and gets sharper. A card reaches `active` only when **≥1 Tier-1 signal and ≥1 Tier-2 signal agree in direction**, with the Tier-2 pair sitting in the interpretable quadrant. Biometrics alone never fire — not as product taste, but because single-source biometric inference is unsupported. Tier 1 alone can reach `quiet` with real copy.

---

## 3. Thresholds, gates, and the numbers behind them

**Every threshold is derived per-athlete. No published or population number is hard-coded** — population characteristics explain only 15% of RMSSD variance (Altini & Plews 2021, 9.03M measurements).

| Gate | Value | Why |
|---|---|---|
| Valid nights per week | **≥5** | 3 is the literature floor for a morning-protocol mean; Grosicki et al. 2026 (~2M nights) needed ≥5/7 for nocturnal stability. Garmin's error argues for the higher number. |
| Weekly aggregation | **Mandatory** | Single-day HRV fails: meta-analytic SMD **−0.45** (ns, wrong direction) for isolated values vs **0.81** for weekly averages. Never surface a night. |
| Biometric baseline | **≥28 days**, and **≥2 full cycles** for naturally-cycling users | 21 days is the house floor; the cycle effect needs two cycles before a baseline means anything |
| Change threshold | **0.5 × the athlete's own between-night SD**, sustained | The SWC convention. Do **not** import a % — nocturnal CV runs ~half morning CV, so morning-derived bands are systematically too wide |
| Load baseline | 8 weeks, **excluding the scored week**, zero-running weeks held out | Uncoupled; a layoff shouldn't reset the baseline and make the comeback a false spike |

**Confidence** — `high` needs ≥2 Tier-1 + both Tier-2 + ≥8 weeks + ≥2 cycles of baseline; `medium` ≥1 Tier-1 + both Tier-2 + ≥6 weeks; `low` is the floor and should read as such in copy.

### 3a. Cycle phase — flag, never correct

Capture `cycle_day` for naturally-cycling users and **`pill_pack_day` for hormonal-contraceptive users**. HC users are *not* phase-free: HRV rose and HR fell in the pill-free week even where measured endogenous hormones were flat (Ahokas et al. 2023, hormone-verified). Treating them as either phase-free or naturally-cycling is wrong.

Three rules:

1. **Annotate, don't adjust.** No validated per-phase correction exists; ~33% of the underlying studies never verified phase, and roughly half of athletic cycles may be anovulatory or luteal-deficient — so the phase label itself is frequently wrong. Subtracting a constant would be false precision on top of a bad label.
2. **Suppress Tier-2 escalation in the late-luteal window.** That's where a false positive is close to certain. Tier 1 still speaks.
3. **All of it is opt-in, and it's health data.** No capture without explicit consent, and the card must work — degraded, honestly labelled — for users who decline. Ship no claim about hormonal IUDs; there is no nocturnal HRV study covering them.

### 3b. Firmware drift

Garmin's error is not static: vendors ship versioned sleep and HRV algorithms (Oura formally names them), and **nobody has ever published the size of a baseline shift caused by an update.** The absence of evidence is exactly why this can't be assumed small.

- **Log Garmin firmware + Connect app version on every nightly row.** Costs nothing now, unrecoverable later.
- Run changepoint detection on each user's baseline series.
- On an unexplained step change coinciding with a version bump: **reset the rolling window**, don't let it absorb the shift over 30–60 days of quietly wrong output.
- Consider surfacing it. *"Garmin updated how it measures this, so your baseline restarted"* is a trust-builder.

---

## 4. Copy

The lint stays (`rest`, `ice`, `should`, `must`, `because`, `caused`, `stop running` — all four variants below pass). Three additions to the banned vocabulary, from the evidence rather than from taste: **`recovered`, `ready`, `risk`** — plus any numeric readiness score. A rising HRV genuinely does not mean recovered, and no injury-risk claim is supportable.

**active — the one interpretable quadrant, with Tier 1 agreeing**

> Three weeks of climbing load, and the recovery side moved with it: your right-achilles came up twice in your own words, the logs read tired, and overnight your heart rate sat a little higher while HRV sat a little lower. Any one of those is noise. Together it's a shape worth watching.

**active — positive**

> Volume and intensity both climbed this block and nothing on the recovery side followed. No new niggles, mood stayed warm, and the overnight numbers held inside their usual range. Worth noticing — that's the block doing what it's supposed to.

**quiet — no pattern**

> Your load moved around this block and the recovery signals didn't track it either way. No shape here. That's the boring answer, and it's the true one.

**quiet — biometrics moved, logs didn't**

> Your overnight numbers drifted this week, but nothing in your own words did. On its own that isn't a pattern — it's as likely to be a late night or a glass of wine as it is training. Noted, not flagged.

**quiet — ambiguous quadrant** *(this one is new, and it's the one that keeps the app honest)*

> HRV is down and your resting heart rate is down with it. In a block like this that combination usually means the opposite of tired — but it's genuinely ambiguous, so this card isn't going to guess.

**annotation — late luteal**

> Heads up: this window of your cycle typically moves these numbers on its own, often more than training does. Reading the dip as fatigue would be premature.

---

## 5. Capture — revised from v1

Migration mostly as v1, with the Tier-0 columns dropped and the drift/phase columns added:

```sql
create table daily_biometrics (
  user_id            text not null,
  date               date not null,          -- sleep.calendar_date
  source             text not null,          -- 'garmin'

  vital_sleep_id     text,                   -- sleep.id, restatement dedup
  sleep_state        text,                   -- 'tentative' | 'confirmed'
  hrv_rmssd          numeric,                -- sleep.average_hrv (ms)  — Tier 2
  resting_hr         numeric,                -- sleep.hr_resting (bpm)  — Tier 2
  sleep_total_min    integer,                -- sleep.total / 60        — Tier 3
  respiratory_rate   numeric,                -- context only

  device_model       text,                   -- drift detection
  firmware_version   text,                   -- drift detection
  app_version        text,                   -- drift detection

  created_at         timestamptz default now(),
  updated_at         timestamptz default now(),
  primary key (user_id, date, source)
);
```

**Dropped from v1** — `sleep_efficiency`, `sleep_score`, `hr_dip_pct`, `stress_avg`. Garmin's 4-stage sleep agreement is κ ≈ 0.21 with deep sleep overestimated by **+44 min** and wake specificity ~29%; sleep efficiency carries a +8.17% bias with ±24-point limits of agreement; Sleep Score has **zero** independent validation. Capturing them invites someone to use them. Total sleep time is the only sleep field that survives, and only as annotation. (Stress and the stress rollup are deferred rather than dead — but they were Tier-3 at best and add webhook complexity for a signal the card no longer leans on.)

Cycle data lives in its own consented table, not here.

Webhook branches, restatement handling (`tentative` → `confirmed`, detector reads confirmed only), the `$.data` vs `$.data.data[]` depth difference, and the Garmin-specific "backfill arrives on `daily.` not `historical.`" quirk all carry over from v1 §4b unchanged — those findings were about Junction's API, not the science, and still hold.

---

## 6. Files, tests, sequence

Same shape as v1 §5, with `recovery.ts` rewritten: no `recoveryPct`, no geometric mean, no ratio. Instead:

```ts
lnMean(xs: number[]): number | null
baselineDeviation(recent: number[], base: number[]): { delta: number; sdUnits: number } | null
hrvRhrQuadrant(hrv: Deviation, rhr: Deviation): Quadrant   // the 3×3 table in §2c
niggleBurden(mentions: TimelineMention[], window): number
moodTrend(weeks: TrendsWeekOut[], window): number | null
tier1Agreement(ctx): { count: number; direction: -1|0|1 }
weeklyLoadSeries(logs, features): number[]                  // unchanged from v1
```

**Tests beyond v1's list:**

- Every quadrant in §2c returns the right status — especially HRV↓/RHR↓ → `quiet`, which is the regression the whole spec exists to prevent.
- 4 valid nights → `hidden`; 5 → alive.
- A single night, however extreme, never changes status.
- Late-luteal window suppresses Tier-2 escalation but not Tier-1 copy.
- HC user with `pill_pack_day` set is not treated as naturally cycling.
- A simulated firmware-version step change triggers a baseline reset, not an `active` card.
- Banned terms now include `recovered`, `ready`, `risk`.

**Sequence.** Unchanged in shape — migration and webhook branches first, since baselines have a calendar dependency and now need two cycles rather than four weeks. But the honest sequencing note is that **Tier 1 needs no Garmin data at all.** The niggle and mood signals are already captured; self-reported sleep quality is a one-tap addition. A `C0` card built on Tier 1 alone could ship now, in `quiet`-and-`active`-Tier-1-only form, months before the biometrics mature — and on the evidence it would be carrying most of the signal anyway.

---

## 7. Why — the evidence, so this doesn't get re-litigated

### 7.1 The ratio is not defensible

- **Coupling.** Conventional ACWR puts week *t* in both numerator and denominator. Simulating 1,000 athletes with *no* true relationship produced r = 0.52 from the arithmetic alone (Lolli et al. 2019, *BJSM* 53:921). Both camps agree on this figure.
- **Uncoupling doesn't rescue it.** Dividing by chronic load only adjusts for chronic load if the regression passes through the origin. With a non-zero intercept the ratio stays correlated with the baseline it claimed to remove — *"failing to normalize the numerator by the denominator **even when uncoupled**"* (Impellizzeri et al. 2020, *IJSPP* 15:907).
- **The denominator never carried signal.** Replacing real chronic load with **random numbers** reproduced the published association (OR ≈ 1.95 vs 2.45); c-statistic 0.574 vs 0.544 for acute load alone vs 0.500 for chance (Impellizzeri et al. 2021, *Sports Medicine* 51:581 — titled "Time to Dismiss ACWR and Its Underlying Theory").
- **The only RCT was null.** 482 elite youth footballers, 34 teams, full season managed to the 0.8–1.5 band: **RR 1.01 (0.91–1.12), p=0.84** (Dalen-Lorentsen et al. 2021, *BJSM* 55:108).
- **The thresholds have no primary source.** 0.8–1.3 / >1.5 trace to a figure in a 2016 editorial that pooled three sports and three non-interchangeable metrics, merged published with unpublished data, collapsed bins to midpoints and fitted a quadratic at R²=0.53. It carries a 2019 formal Correction disclosing a previously undescribed **exclusion of high-load data** — precisely where the danger-zone claim lives.
- **Percent-change is the same object.** (W − base)/base is algebraically the ratio minus 1. Switching to "% above baseline" is relabeling, not a fix.
- **In runners specifically, the formula choice drives the alerts.** 430 recreational runners, 22,839 sessions: at a 1.5 threshold, coupled flagged 16.2% of sessions, **uncoupled flagged 25.8%** (Cloosterman et al. 2024, *J Athl Train* 59:1028). Your formula, not your users' behaviour, would determine who gets flagged.
- **And the running evidence base is thin regardless.** The only systematic review found four eligible studies and concluded *"very limited evidence exists"* that a sudden load change is associated with running injury — with no difference between a 10% and a 24% weekly increase, i.e. **the 10% rule is unsupported** (Damsted et al. 2018, *IJSPT* 13:931).

### 7.2 HRV cannot be read alone, or daily

- Non-monotonic vagal relationship proven under pharmacological blockade — HRV rises, plateaus, then *falls* as parasympathetic effect keeps increasing (Goldberger et al. 2001, *Circulation* 103:1977). Saturation appeared in 12/17 men after 8 weeks of ordinary aerobic training (Kiviniemi et al. 2006, *EJAP* 97:158) — not an elite-only phenomenon.
- Resting RMSSD rises toward *both* performance improvement (SMD 0.58) and decrement (SMD 0.26) (Bellenger et al. 2016, *Sports Medicine* 46:1461).
- Isolated single-day values: SMD **−0.45** (ns, wrong sign). Weekly averages: **0.81**. (Manresa-Rocamora et al. 2021, *Scand J Med Sci Sports* 31:1164.)
- In the one head-to-head, **nocturnal HR outperformed nocturnal HRV** for classifying overreached vs responding runners, both ≥85% PPV/NPV (Nuuttila et al. 2024, *EJSS*).
- Opposite HRV signs from the same nominal overload depending on population and modality: recreational runners suppressed (Nuuttila 2024); highly trained triathletes in functional overreaching showed parasympathetic *hyper*activity (Le Meur et al. 2013, *MSSE* 45:2061).

### 7.3 The device is noisier than the signal

- Garmin Fenix 6 nocturnal HRV vs ECG across 536 nights: **MAPE 10.52%**, Lin's CCC 0.87 (poor), with proportional bias — overestimating when true RMSSD is low. **Garmin was excluded from the resting-HR analysis entirely for methodological inconsistencies** (Dial et al. 2025, *Physiol Rep* 13:e70527).
- That 10.5% error is ~3× the cycle effect (3.2%) and ~2× the training effect (4.6%) it would need to resolve.
- Device bias and limits of agreement in lnRMSSD approach or exceed the smallest worthwhile change — true across every wrist device tested.
- Device rankings are unstable between studies (Miller 2022 ranks Garmin worst at ICC 0.24; Dial 2025 ranks it fourth of five). Don't build on a ranking.
- A **single** beat-detection artifact can inflate RMSSD by 413% supine; RMSSD is biased once >0.9% of the signal is artifact (Bourdillon et al. 2022, *JSSM* 21:260).

### 7.4 Why Tier 0 is excluded

- **Sleep stages:** Garmin Vivosmart 4 four-stage κ = **0.21**; sensitivity to deep 45%, REM 34%; wake specificity **29%**; deep sleep biased **+44 min** (Schyvens et al. 2025, *SLEEP Advances* 6:zpaf021; Schyvens et al. 2024, *JMIR mHealth* 12:e52192).
- **Sleep efficiency:** bias +8.17%, LoA −3.63 to +19.97 — a 24-point window.
- **Total sleep time:** bias +38 min, LoA −83 to +160 min on a single night. Usable only aggregated, as annotation. Garmin was the one device in Kainec et al. 2024 that failed to match research-grade actigraphy for TST.
- **Garmin Sleep Score:** no independent validation exists. A proprietary composite over stage estimates at κ ≈ 0.2. The "40–50% agreement" figure circulating online traces to a YouTube analysis, not a paper.
- **HRV coefficient of variation:** I floated this in v1 as possibly better than the mean. That was wrong. Its *direction* is contested (Plews 2012 n=2 says falling CV is bad; Flatt/Esco/Nakamura say falling CV is good), and it failed to replicate twice — no significant correlation with performance in 31 collegiate rowers (Sherman et al. 2021), and explicitly not confirmed in a Tour de France cyclist (Bourdillon et al. 2023). The largest dataset (Grosicki et al. 2026, ~2M nights) validates it as a **behavioural** biomarker where alcohol and sleep irregularity dominate — not a training signal. Keep it, if at all, as a data-quality flag.

### 7.5 The injury bright line

Say nothing about injury. Ever.

- No AUC, sensitivity, specificity, calibration or external validation has **ever** been reported for HRV as an injury predictor.
- The one study everyone cites is **n=6** with ~7 problem-weeks, magnitude-based inference, nine uncorrected comparisons of which one was "clear," built on ACWR, with the vendor of a competing HRV app as a declared conflict (Williams et al. 2017, *JSSM* 16:443).
- 204 sports-injury prediction models reviewed: **zero externally validated**, 98% high or unclear risk of bias, *"no models could be recommended for use in practice"* (Bullock et al. 2022, *Sports Medicine* 52:2469).
- **The warning window mostly doesn't exist.** Of 1,199 overuse running injuries, only **6.9%** had a reported problem 7 days prior (Frandsen et al. 2025, *JOSPT Open* 3:85). Most overuse running injuries are sudden. That undercuts daily monitoring as early warning more directly than any HRV-specific finding.
- Reverse causation is live: HRV is altered *after* injury, so "low HRV preceded the report" is fully compatible with the tissue problem causing the HRV change.

**What this leaves intact:** describing what happened, in the athlete's own words, next to what the numbers did. That is what the app already promises, and it turns out to be the only thing the evidence supports.

---

## 8. Open questions

1. **Ship Tier 1 now?** A `C0` built on niggles + mood alone needs no Garmin data and, on the evidence, carries most of the signal. The counter-argument is that a recovery card without biometrics may not read as substantial to users. That's a product call, not an evidence call.
2. **Add self-reported sleep quality?** Best-evidenced single input in the runner literature, one tap, no hardware. Strong recommend, but it's a new logging surface.
3. **Cycle tracking at all?** Meaningful scope, real consent and privacy obligations, and health data with a higher bar. The alternative is knowingly shipping a signal that is confounded for roughly half of every cycle for a large share of users. Neither option is comfortable; the second is worse.
4. **The session-spike detector (§2a).** The single best-evidenced load finding in running, and it doesn't belong in `C0` — it's session-level. Its own card?
5. **Does `C0` still supersede C1–C4?** Yes, more so than in v1: C1–C4 as separate per-biometric cards are precisely the single-source inference the evidence rules out.

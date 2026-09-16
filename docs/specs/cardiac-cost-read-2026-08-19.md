# The cardiac-cost read — spec + validation findings

*2026-08-19. Companion to `recovery-trend-v2-2026-07-27.md` (which owns the resting/biometric read). This one is the **exercise-based** read: what a session costs in beats, against the athlete's own history at that pace.*

Module: `supabase/functions/_shared/recoveryRead.ts` · Tests: `recoveryRead.test.ts` (17, green)

---

## 1. The idea

A runner finishes a hard session. Next day they run easy. If they are still carrying it, the heart works harder to hold the same pace — away from homeostasis, and it shows up in beats, not in pace. So: measure **cardiac cost** on every session, compare it to what that athlete's own history says that *pace band* normally costs, and report the gap.

**Cost = beats per mile = avgHr × paceMinutesPerMile.**

Baselines are **per pace band**, banded by *ratio to the athlete's easy-pace anchor* rather than absolute pace — so the bands travel with fitness and last month's baseline stays comparable when easy pace drops.

## 2. Why this can work at all

Within a pace band, one athlete's cardiac cost is **tight**: measured CV of 1.2–3.8% across 145 sessions. A 3% excursion is therefore visible above the noise. That tightness is the whole basis of the metric.

| Pace band | n | CV |
|---|---|---|
| Threshold | 6 | 1.2% |
| Marathon pace | 8 | 2.9% |
| Steady | 18 | 1.9% |
| Moderate | 54 | 3.8% |
| Easy | 34 | 3.3% |
| **Slower than easy** | 25 | **30.0%** |

The last row is why `MAX_RATIO_FOR_READ` exists. Slower-than-easy mixes recovery jogs with walk breaks, hikes and stopped GPS; there is no baseline to be had there and the module refuses to invent one.

## 3. The confounders are bigger than the signal

Measured on 100 easy runs, May–Aug 2026, controlling for pace and duration:

| Factor | Effect on HR |
|---|---|
| **Time of day** (morning vs evening) | **−5.4 bpm** |
| Pace, per 10 sec/mile slower | −1.9 bpm |
| Duration, per 10 min | +0.5 bpm |
| Temperature, per 10 °F | +0.34 bpm (n.s.) |
| Dew point, per 10 °F | −0.01 bpm (n.s.) |
| **Residual noise (σ)** | **3.9 bpm** |

Two consequences, both load-bearing:

**Time of day is matched, not corrected.** Baselines only draw on same-daypart sessions. Matching cannot get the sign wrong; a regression on thin data can — and did. Before `am` entered the model, the dew-point coefficient came out **negative**, i.e. the model claimed humidity *lowers* heart rate. That is what an unmodelled confounder looks like from the inside, and it is the reason for the matching discipline.

**Heat is handled by a GUARD, not a correction — and the first version of this analysis got it wrong.** The original pooled model put `am` and temperature in together and concluded heat added nothing (R² 0.699 → 0.700). That test was invalid: mornings average 75 °F and evenings 87 °F, so `am` was already absorbing the temperature difference. Re-run properly:

| Test | Heat effect |
|---|---|
| Mornings only (HI 55–87), n=61 | R² 0.738 → 0.738. Nothing. |
| Evenings only (HI 71–103), n=38 | R² 0.491 → 0.521, **+0.11 bpm/°F** |
| Evenings + season trend | coefficient collapses to +0.02 — confounded with the calendar |
| **Within-month, demeaned** (season held constant) | **+0.014 bpm/°F, r=+0.03, p=0.76** |

And the number that decides the design: **the median spread of heat index inside a 42-day, same-daypart baseline window is 6.3 °F.** At even the most generous coefficient that is ~0.7 bpm — a fifth of the 3.9 bpm noise floor, an eighth of what trips a flag. *Matching* on daypart and recency already holds conditions near-constant; a correction term would add a coefficient to get wrong for no measurable gain. Contrast hills, where climb inside the same window ranges 0–22 m/mile — large variation needs correcting, small variation does not.

What matching does **not** survive is travel, a race elsewhere, or a genuine heat wave, where the baseline was built in conditions the session does not share. `HEAT_OUT_OF_RANGE_F` (12 °F, or 2× the baseline's own spread, whichever is wider) refuses the read there rather than calling it fatigue. On the backtest it fires 6 times in 145 sessions and suppresses three former "elevated" calls, all hot evenings.

Note this is a *different question from* `pace-heat-adjustment.ts`, which corrects **pace** for dew point during work. That model is about performance in the moment; this one is about comparability against a baseline. They do not have to agree.

## 4. What the validation actually found — the honest part

**The day-after effect was not detectable on the athlete tested.**

| Time since last hard session | n | HR residual vs expected | 95% CI |
|---|---|---|---|
| 6–20h (same day PM) | 4 | +0.49 | [−2.68, +3.67] |
| 20–44h (**day 1**) | 17 | **+0.16** | [−1.66, +1.99] |
| 44–68h (day 2) | 18 | +0.02 | [−1.60, +1.63] |
| 68–92h (day 3) | 11 | −0.21 | [−2.88, +2.46] |
| 92h+ (day 4+) | 44 | −0.06 | [−1.27, +1.14] |

Flat. Day 1 vs day 4+: **p = 0.84, d = 0.06**.

Three further hypotheses were tested and all came back null:

- **Dose–response** (does a bigger session cost more the next day?) — ρ = −0.26, p = 0.10, and the *wrong sign*.
- **Accumulated load** (7/14/28-day rolling TLS, ACWR) — all |r| < 0.07, all p > 0.5. Highest-load quartile read −0.43 bpm vs lowest at +0.18.
- **Heat** — see §3. Null within-month; the apparent evening effect is calendar confounding.

One thing *did* light up: sessions starting ~1h after a hard effort read **+3.3 bpm (p = 0.004, d = 0.95)**. But those are cooldown jogs and second legs of doubles — the same session still ending, not recovery. `MIN_HOURS_AFTER_HARD = 6` exists to keep them out, and removing them is what collapsed the day-after effect to zero.

**Backtest of the shipped module over all 145 sessions:** 68% no-read (mostly thin baselines), 26% nothing-detected, 6 elevated, 4 lower-than-usual. The six elevated calls cluster in Jul 29 – Aug 3 but are **not explained** by days-since-hard, accumulated load, temperature or dew. With 47 reads at a 1.5σ threshold, ~13% flags is what noise alone produces. On present evidence these are the tail of the distribution, not a finding.

## 5. So why ship it

Because the *measurement* is sound even though the *interpretation* is unproven, and you cannot validate the interpretation without first collecting the measurement.

1. Cost is real, tight, and cheap — it needs only HR and pace, both of which every synced run already has.
2. The athlete it was developed against is the **worst case**, not the typical one: highly trained, metronomic (easy-pace IQR 7:17–7:41), recovers fast. A less-trained user has more fatigue, slower recovery and wider pace variance — a larger effect against a wider band. The self-calibrating design means that works without retuning.
3. It stays quiet. On the evidence above, a version of this that always had an opinion would be manufacturing one.

**Wired in (2026-08-19, same day):** two consumers now exist, both deliberately gentle.

1. **HR adjustment on load scores.** `hrEffortMultiplier` scales `stress_load` (TLS) and `effort_load` by a bounded factor: 40% of the cardiac-cost excursion, capped at ±6%, exactly 1.0 whenever the read declines (no HR, thin baseline, cooldown, heat guard). The pace model prices the work; HR gets a bounded vote on what it cost. Backtest over 145 sessions: 22 touched, range ×0.955–×1.032, aggregate moved 0.01%.
2. **Daypart matching went timezone-proof.** The morning/evening split used the runtime's local clock — correct on a phone, wrong on a UTC edge function. Replaced with circular ±3h UTC-hour proximity matching, which needs no timezone knowledge at all.

**Recommendation: compute and store on every session; do not surface a verdict to users yet.** Validate against `felt_rpe`, which is the evidenced signal per `recovery-trend-v2` §1 and which you already collect. Today there are only 32 RPE values since May — too thin. Once ~100 RPEs overlap sessions that got a read, the question "does an elevated cardiac-cost read predict a higher felt RPE?" becomes answerable, and *that* is what should gate turning the verdict on.

## 6. Design decisions, and what would change them

| Decision | Value | Why | Revisit when |
|---|---|---|---|
| `WINDOW_DAYS` | 42 | long enough for 8 in-band samples, short enough that fitness drift is small | baselines still thin |
| `MIN_SAMPLES` | 8 | below this the median is not a baseline | 68% no-read rate proves too quiet |
| `Z_ELEVATED` | 1.5σ | ~13% flag rate; lower and it is pure noise | RPE validation gives a real ROC |
| `SIGMA_FLOOR_PCT` | 1.2% | the tightest CV seen in real data; refuse to believe anyone is tighter | a genuinely tighter athlete appears |
| `MIN_HOURS_AFTER_HARD` | 6 | measured: cooldowns read +3.3 bpm | never — this one is solid |
| Daypart | matched | a regression got the sign wrong on real data | a much larger sample |
| Hills | corrected, +3.16 bpm per 10 m/mi | only covariate that improved the model; 12× the fatigue signal | a second athlete, or real mountains |
| Heat | guarded, not corrected | within-window spread is 6.3 °F ≈ 0.7 bpm; matching already holds it | a traveling athlete, altitude, or an indoor/outdoor split |

## 7. Known limitations

- **One athlete, one climate, four months.** Everything in §3 and §4 is n=1. The thresholds are self-calibrating so they should travel, but the *conclusions* do not.
- **68% no-read** is high. The daypart match roughly halves the usable pool. If that proves too quiet in practice, the fix is more history, not a lower `MIN_SAMPLES`.
- **avgHr is a blunt input.** Per-second HR streams would allow drift-aware cost (first-half vs second-half decoupling), which is a better-evidenced marker than whole-session average. `external_streams` already carries the data.
- **No illness/sleep/alcohol channel.** Each moves resting HR more than training does (Altini & Plews: alcohol d=0.97, sickness d=0.97). An elevated read has several possible causes and the module must never claim to know which.

# The Daily Read — a unified recovery score

**Date:** 2026-08-04
**Status:** design proposal, for discussion
**Author:** Rio + Claude
**Builds on:** `docs/specs/recovery-trend-v2-2026-07-27.md` (the evidence base),
`RunningLog/RunningLog/Trends/TrendsSignalModels.swift` (the shipped ledger this
evolves), `outputs/sleep-hrv-recovery-ingestion-spec-2026-08-04.md` (the sleep/HRV
pipeline), `outputs/fitness-score-stress-load-design-2026-07-31.md` (stress load).

---

## 0. What we're building

One number, updated daily, that balances everything the app knows about how the body
is absorbing training: **training load, heat stress, mood, niggles, sleep, HRV, life
stress — and a few things you didn't list but already collect.** Some inputs are
words (mood, niggles, sleep quality), some are numbers (HRV, resting HR, load, heat).
The hard part isn't collecting them — you already do. The hard part is combining a
"tired" and an HRV of 42ms and a dew point of 75°F into one honest number without
either faking precision or burying the one signal that matters.

This design does that with four ideas, each of which exists to stop a specific failure:

1. **Show the receipt.** The score is `base 50 ± named contributions`, every line
   visible — the format you already liked on the current card. No black box.
2. **Everything is measured against *your own* baseline**, in units of *your own*
   variability. A resting HR of 52 means nothing; a resting HR 6 beats above *your*
   28-day average means something. This is what makes it *balance* rather than react
   to raw numbers.
3. **Evidence sets the weights.** Your own literature review found the self-reported
   signals (soreness, fatigue, sleep quality) out-predict the biometrics in runners.
   So niggles and mood can move the score more than HRV can. The watch corroborates;
   your words lead.
4. **Weak signals can't fire alone.** HRV and resting HR only deepen a negative read
   when your *words* already agree. An ambiguous overnight number on its own gets
   noted, not counted. This is the single rule that stops it behaving like Whoop.

Plus a fifth thing that isn't a score input but wraps the whole number: a **confidence**
label, so a read built on nine days of data and a full biometric baseline doesn't look
identical to one built on this morning's mood alone.

---

## 1. The inputs

Eight scoring domains and three annotations. Each domain lists its source (all real,
all already in your stack), whether it's qualitative or quantitative, its evidence tier,
and its **point ceiling** — the most it can move the score. The ceilings are the weights;
they encode the evidence hierarchy.

| # | Domain | Q/Q | Source (existing) | Tier | Ceiling (min…max) |
|---|---|---|---|---|---|
| 1 | **Mood / fatigue** | qual | `training_logs.mood` (voice log) | 1 · lead | −14 … +10 |
| 2 | **Niggles** (severity × clustering) | qual | `body_mentions` | 1 · lead | −14 … 0 |
| 3 | **Sleep quality** | qual | `daily_checkins.sleep_quality` (new one-tap) | 1 · lead | −6 … +4 |
| 4 | **Life stress** | qual | memo mentions → `life_context` | 1 | −4 … 0 |
| 5 | **Training load** (acute vs your chronic) | quant | `stress_load`→CTL/ATL, or miles vs 8-wk | 2 | −7 … +5 |
| 6 | **Load spike** (single-session) | quant | longest run vs prior-30-day longest | 2 | −5 … 0 |
| 7 | **Heat stress** (recent dose vs your norm) | quant | `weather_actual.composite_score` / `heat_category` | 2 | −4 … 0 |
| 8 | **Autonomic** (HRV × resting HR) | quant | `daily_biometrics` | 2 · gated | −6 … +3 |
| — | Monotony / days-on | quant | consecutive-day count, Foster monotony | 3 | −5 … 0 |
| — | Total sleep time | quant | `daily_biometrics.sleep_total_min` | 3 · note | annotation |
| — | Cycle phase | — | consented cycle table (future) | — | suppressor + note |

Notes on the shape:

- **The self-report ceilings dwarf the biometric ones on the downside** (−14 niggles vs
  −6 autonomic). That's deliberate and evidenced: in the one prospective HRV-vs-injury
  study in runners, HRV was null (p=.225) while sleep impairment hit p=.004. The watch
  is not allowed to shout over your body.
- **Positive contributions are smaller than negative ones.** Recovery evidence is
  asymmetric — a rough night reliably drags, but a great HRV night doesn't reliably mean
  "go harder." The score leans slightly conservative by construction.
- **"A few other variables" beyond your list:** the single-session load spike (the one
  load finding with strong running evidence — HRR 2.28 for a run >100% longer than your
  longest in 30 days), training monotony, life stress, and cycle-phase suppression.

---

## 2. The math

### 2a. Personal-baseline normalization (the core move)

Every **quantitative** domain converts a raw value into a *deviation from the athlete's
own baseline, in units of the athlete's own variability*, then maps that onto its point
range. Generic form:

```
z = (recent_mean − baseline_mean) / baseline_sd        # signed, unitless
points = clamp(−k · shape(z), ceiling.min, ceiling.max)
```

- `recent_mean` is a **7-day** rolling mean (never a single reading — single-day HRV has
  a −0.45 effect, wrong sign; the weekly mean has +0.81).
- `baseline_mean/sd` come from a **28-day** (biometrics) or **8-week** (load) trailing
  window, excluding the recent window so the thing being measured isn't in its own
  baseline.
- `shape(z)` is a soft curve (e.g. `tanh`) so the factor saturates near its ceiling
  instead of exploding on outliers.
- Change threshold: a domain only leaves 0 once `|z| ≥ 0.5` (the smallest-worthwhile-
  change convention on the athlete's own SD). Inside that, it reads "in your usual
  range" and contributes 0.

This is why the score *balances*: a hot day in Austin, a resting HR of 55, 40 miles a
week — none of those are "high" or "low" in the abstract. They're only high or low
relative to *your* normal, scaled by how much *you* normally bounce around. Two athletes
with identical numbers can get different reads, correctly.

**Qualitative** domains skip normalization — a word is already a judgment. They map
through closed vocabularies to points (mood: energized +10 … injured −18, scaled into
the ceiling; sleep: good +4 / ok 0 / rough −6; niggle severity → −3/−6/−10/−14).

### 2b. The convergence gate (the honesty rule)

Tier-2 quantitative domains (autonomic, and heat/load-spike on their alarming end)
**cannot push the score negative unless at least one Tier-1 self-report domain is also
negative that week.** If the words are fine and only the watch moved:

> Your overnight numbers drifted this week, but nothing in your own words did. On its
> own that isn't a pattern — as likely a late night or a glass of wine as training.
> Noted, not flagged.

…and the domain contributes **0**, shown on the receipt with that evidence line. This is
the rule that prevents the two failure modes your v2 spec spent §7 dismantling: reacting
to a single bad HRV morning, and reading a lone autonomic dip as fatigue when it's
ambiguous by construction (HRV↓ + RHR↓ usually means *adaptation*).

Positive Tier-2 (autonomic "settled") applies ungated but small — good news doesn't need
a chaperone, but it doesn't get to inflate the number either.

### 2c. The autonomic domain specifically (HRV × resting HR)

Never HRV alone. The 7-day means of HRV and resting HR, each vs their 28-day personal
baseline, land in one of nine cells (this is the v2 §2c quadrant):

| | RHR falling | RHR flat | **RHR rising** |
|---|---|---|---|
| **HRV falling** | 0 · *usually adaptation* | 0 | **−6 · the one readable cell** |
| HRV flat | 0 | 0 | −2 (weak; only with Tier-1) |
| HRV rising | 0 · *ambiguous* | 0 | 0 · *likely artifact* |

Only **HRV down + resting HR up** subtracts the full −6 (and only when the convergence
gate is open). One "settled" cell (+3). Everything else is 0 with an honest line. If HRV
is missing but resting HR is present, resting HR may speak alone at half weight (−3
ceiling) — it out-performed HRV head-to-head in the one direct comparison, so it's the
more trustworthy of the two.

### 2d. Heat stress (using what you already compute)

Your `weather_actual` already carries a per-run `composite_score` (~156 on this week's
runs), a `heat_category`, dew point and humidity. Heat stress is the **recent accumulated
heat dose relative to the athlete's own seasonal norm** — because an Austin runner in
August is *always* in heat, so absolute temperature is meaningless; what matters is
unusual heat, or a cumulative load their body hasn't adapted to.

```
heat_dose_7d = Σ (run_duration_min · heatBurden(weather_actual))   over last 7 days
points = clamp(−k · z(heat_dose_7d vs own 4-week heat-dose baseline), −4, 0)
```

`heatBurden()` leans on the fields you have — dew point is the physiologically honest one
(75°F dew point is far more taxing than 96°F dry, and your data shows both this week).
Capped at −4: heat is real physiological cost the mileage number misses, but it's a
modifier, not a headline. Subject to the convergence gate like the other Tier-2 terms.

### 2e. Assembly, clamp, band

```
raw   = 50 + Σ domain_points
score = clamp(raw, 8, 96)                     # unchanged from today's ledger
band  = Flat (<45) · Worn (<60) · Steady (<75) · Clear (≥75)
```

The arithmetic line renders straight from the contributions, exactly like today:
`Starts at 50 − 8 − 6 − 6 − 2 − 5 … = 17`.

### 2f. Confidence (wraps the number, never shrinks it)

| Level | Requires |
|---|---|
| **high** | ≥2 Tier-1 present + both autonomic signals + ≥8-wk load baseline + ≥28-day biometric baseline |
| **medium** | ≥1 Tier-1 + some biometrics + ≥6 weeks history |
| **low** | self-report only, or thin baseline — the floor, and copy reads like it |

Confidence changes the *tone* of the read, not the number. A low-confidence 31 says
"early days, but…"; a high-confidence 31 says the pattern is real. Crucially, a missing
input never silently drops the score — it drops confidence and renormalizes.

---

## 3. Missing data — degrade toward honest, never toward alarm

Every domain has an explicit "I can't speak" state that contributes **0** and says so,
exactly like today's "Mood — not logged today." No input is ever imputed from a neighbour
or a population value.

- No watch → domains 5-part, 8 quiet; score runs on self-report at **low/medium**
  confidence. This is the launch state, and per your evidence it's carrying most of the
  signal anyway.
- No self-report today → mood contributes 0 ("not logged"); the convergence gate treats
  "no Tier-1 signal" as "gate closed," so a lone bad HRV still can't fire. Good.
- Thin baseline (<2 weeks) → quantitative domains show "not enough history yet," 0 points.
- **The one incentive to watch:** unlogged mood scores 0 but "tired" scores negative, so
  the score quietly rewards *not* logging on a bad day (your current card has this too).
  Options in §5.

---

## 4. Worked example — your card, then the full model

**Today, as shipped** (from your screenshot): mood tired −8, recent load −4, body 0, load
−2, days on −5 → **31, Flat**, on self-report + mileage only.

**Same day, full model, with biometrics present.** Suppose: you logged "tired"; slept
"rough" (one-tap); 9 straight days in Austin's very-hot dew points; and overnight your
7-day HRV sits below baseline while resting HR sits above (the one readable autonomic
cell). Life stress quiet; no single-session spike.

```
Starts at 50
  Mood            tired · logged                       − 8
  Niggles         none in 14 days                        0
  Sleep           rough · logged                       − 6
  Life stress     nothing logged                         0
  Recent load     35 mi over 3 days                    − 4
  Load            16% over your 8-wk average           − 2
  Load spike      no unusual long run                    0
  Heat            9 days in heat above your norm       − 2
  Autonomic       7-day HRV down, resting HR up  ⟵gate open  − 6
  Days on         9 straight days running             − 5
                                              =  raw 17  → 17  Flat · high confidence
```

The autonomic −6 fires **because** "tired" and "rough sleep" already agreed — the watch
corroborated the words. Now flip it: **same overnight numbers, but you logged "positive"
and slept "good."** The convergence gate is closed, so:

```
  Autonomic       overnight numbers moved, your words didn't · noted, not flagged   0
                                              =  raw 41  → 41  Worn
```

Identical HRV, a 24-point-different read — because the score trusts your body over your
watch. That contrast *is* the design.

---

## 5. What's evidenced vs. what's a judgment call (so you can push back)

**On firm evidence** (citations in `recovery-trend-v2` §7): self-report > biometrics in
runners; single-day HRV is noise, weekly is signal; HRV needs resting-HR pairing; resting
HR > HRV head-to-head; the single-session load spike; sleep quality as the strongest
single input; population numbers explain only ~15% of HRV variance (hence personal
baselines).

**Judgment calls I made** (yours to overrule):

1. **The exact ceilings.** −14 for niggles vs −6 for autonomic is the evidence *ordering*
   made concrete, but the specific integers are calibration, not law. They should be
   tuned once you have real data across users.
2. **Heat capped at −4.** Defensible as "real but secondary," but heat in Austin summer
   might deserve more weight for your actual users. Testable.
3. **Asymmetry** (positives smaller than negatives). A stance, not a theorem.
4. **One number at all.** Your v2 spec argued the *weekly* card should be two lines and a
   sentence, no composite. This daily score is a composite — justified only because it
   shows its full receipt and carries confidence. If that still feels like false
   precision, the fallback is to show the band word (Flat/Worn/Steady/Clear) as the
   headline and the number as secondary.

---

## 6. How it gets built (mostly already specced)

1. **Ingestion** — `daily_biometrics` + `daily_checkins` + the webhook sleep branch,
   from `outputs/sleep-hrv-recovery-ingestion-spec` and the two migrations already in
   `supabase/migrations/`. Ship first.
2. **Stress load** — apply the unshipped `20260731120000` migration so domains 5/6 have a
   real per-workout load unit instead of raw miles.
3. **The score** — extend `TrendsRecoveryLedger` with the normalization helper (2a), the
   convergence gate (2b), the autonomic quadrant (2c, already drafted in the apply notes),
   heat (2d), and confidence (2f). It stays one pure, unit-tested function — the same
   shape it has now.
4. **Cycle capture** — the only genuinely new consented surface; gates the late-luteal
   suppression. Deferrable; the score is honest without it (just flagged as confounded
   for cycling users half the time).

Sequence-wise, everything except the score function itself is already designed or built.
The score is the one new piece of reasoning, and it's ~150 lines of deterministic Swift.

---

## 7. Open decisions for you

1. **Headline: the number, or the band word?** (§5.4) — the one real philosophical call.
2. **The unlogged-mood incentive** (§3) — leave it (no data, no claim), or nudge a
   neutral prompt when a run lands with no mood?
3. **Heat weight** — is −4 enough for your climate, or should dew-point days above a
   personal threshold carry more?
4. **Ship the score on Tier-1 only now**, and let biometrics light up as the pipeline
   matures — or wait for the full input set? (Evidence says Tier-1-only is already most
   of the signal.)

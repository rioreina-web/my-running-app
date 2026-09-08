# Athlete Signature — addendum to the AI feedback loop design

**Date:** 2026-07-07
**Status:** Design addendum; extends `ai-feedback-loop-design-2026-07-07.md`. No code yet.
**Decision input (Rio, 2026-07-07):** the loop should be *analytical* — algorithm-based
discovery of each athlete's individual training patterns, not a preset menu of options.
**Companion:** base spec (`ai-feedback-loop-design-2026-07-07.md`),
codebase grounding (`ai-feedback-loop-codebase-exploration-2026-07-07.md`).

---

## 0. Summary

The base spec's AI Coaching Profile learns **how to talk** to an athlete, from a closed
menu. This addendum adds the second layer: the **Athlete Signature** — what the AI has
*discovered to be true about this athlete's training*, mined algorithmically from their
own history with no preset list of conclusions.

Examples of what the miner can find (none of these exist as a category anywhere — they
emerge from the data):

- "Your best quality sessions land two days after a full rest day" (9 of 11 instances since March)
- "Calf mentions cluster in weeks where intensity minutes jump >15%" (4 of 5 spikes)
- "Long runs over 16 mi are followed by a mood dip lasting ~3 days" (7 occurrences)
- "You hit pace targets more reliably in the morning" (based on 23 quality sessions)

The design principle that resolves "algorithmic and open-ended" with this product's
hard rules: **open discovery, structured evidence.** The hypothesis space is
combinatorial and unlisted; every *finding* is a first-class, auditable record with its
statistics attached, visible to the athlete, vettable by a coach, and it decays when the
data stops supporting it.

```
                    ATHLETE'S FULL HISTORY (all existing tables)
   training_log · scheduled-vs-actual · ACWR/monotony/strain · mood labels ·
   niggle mentions · confirmed_races · weather · feel chips (S3) · HealthKit sleep
                                    │
                              weekly miner
                     (lagged correlation search over an
                      open antecedent × lag × outcome grammar)
                                    │
                     statistical gates (support, effect,
                      split-half confirmation, decay)
                                    │
                    athlete_signature_observations
                  (statement + evidence + confidence + status)
                          │                     │
                   Model of You            Coach portal
                 "Patterns I've           ranked list —
                  noticed" (dismiss)      confirm / dismiss / annotate
                          │                     │
                          └──────► prompt injection ◄──────┘
                        (top observations, confidence-tagged,
                         phrased per Coach voice posture)
```

## 1. Relationship to the base spec

| | AI Coaching Profile (base spec) | Athlete Signature (this addendum) |
|---|---|---|
| Learns | Communication style | Individual training truths |
| Shape | Closed menu of typed fields | Open-ended observations, each evidence-backed |
| Method | Simple counting rules over feedback signals | Statistical pattern mining over full training history |
| Changes the AI's | Voice, format, emphasis | Substance — what it knows and references |
| Athlete control | Edit / pin / reset fields | View evidence, dismiss patterns |
| Coach control | Override fields, directives | Confirm / dismiss / annotate patterns |

Same injection point (`athlete_state` → prompt context), same control surfaces (Model of
You, coach portal card), same discipline (RLS, evals, append-only, service-role writes).
The two layers ship independently — signature does not depend on profile phases F2/F3.

## 2. Principles

1. **Open discovery, structured evidence.** No preset list of conclusions. But no
   finding exists without: instance count, effect size, time window, example workout IDs,
   and a confidence grade. If it can't be explained in one sentence with a number in it,
   it doesn't surface. (This is the marathon-prediction-honesty rule generalized.)
2. **Observation, never prescription.** The signature states patterns; it never converts
   them into instructions. "Your best sessions follow rest days" — yes. "So take
   Wednesdays off" — never. The call belongs to the coach, or to Maya. Operational alarms
   (load spike + niggle) remain the coachable-moments pipeline's job; the signature is
   the *understanding* layer, not the alerting layer.
3. **Confidence ladder.** Candidate patterns stay internal. Medium confidence surfaces as
   a soft question ("Have you noticed your legs come back faster after full rest days?")
   — which fits the Coach Read voice posture exactly. High confidence surfaces as a
   plain observation. Nothing surfaces on a hunch.
4. **Patterns must keep earning their place.** Every observation decays without
   re-confirmation and flips to refuted on counter-evidence. An athlete changes; the
   model must too. A dismissed pattern needs substantially stronger evidence to return.
5. **Deterministic statistics find; the LLM only phrases.** The miner is pure math —
   testable, cheap, explainable. An LLM turns a validated statistic into warm,
   athlete-voiced language, and that prompt goes through the eval gate like any other.
   The LLM can never invent a pattern.
6. **The medical line holds.** Patterns involving niggles are phrased as association in
   the athlete's own words ("calf mentions cluster after intensity jumps"), never cause,
   never diagnosis, never advice. Extra gating in §7.

## 3. Data substrate — all already collected

No new capture needed. The miner reads: `training_log` (pace, distance, RPE, mood label,
memo-derived insight), `scheduled_workouts` vs. actuals (compliance, plan context),
`athlete_state` satellites (ACWR, monotony, strain, rolling volumes, fitness signal),
`body_mentions` (niggles, closed vocabulary, verbatim), `confirmed_races`,
`weather_actual`, HealthKit sleep where present, and — once base-spec F1 ships — the
per-workout feel chips (S3), which sharpen outcome measurement considerably
(`nailed_it/struggled` is a cleaner outcome than pace-vs-zone alone).

Cross-training stays excluded from running-fitness outcomes (standing decision,
2026-05-28) but is *allowed as an antecedent* — "quality sessions the day after a bike
day" is a legitimate, discoverable pattern that doesn't put cross-training into fitness
math.

## 4. The mining engine

### 4.1 Hypothesis grammar, not hypothesis list

The miner searches an open grammar:

```
{ antecedent } × { lag window } × { outcome }

antecedents (event or condition, from any substrate column):
  full rest day · long run ≥ X mi · weekly intensity-minutes jump ≥ Y% ·
  back-to-back quality days · sleep < athlete's own median · bike/swim day ·
  race within N weeks · morning vs evening start · heat stress band ·
  down-week (volume < 80% of 4wk avg) · travel gap in logs · …

lags: same-day · +1d · +2d · +3d · 4–7d window · same-week · next-week

outcomes (measured against the athlete's OWN baseline, never population norms):
  work-segment execution (rep/tempo pace vs zone target) · HR-at-work-pace ·
  within-session fade (rep N vs rep 1) · feel chip · mood label ·
  niggle mention (any / specific body part) · compliance ·
  RPE-at-pace (efficiency proxy) · long-run fade (last-3-mi vs first-3-mi split)
```

**Segment rule (decision 2026-07-07, Rio):** quality-session outcomes are computed on
**work segments, never whole-activity averages.** A "10 × K" session's average pace is
mostly jog recovery and says nothing about the reps. Work segments come from device laps
(Strava lap data → the existing `running_workout_laps` table) with a fallback splitter
over pace streams (sustained stretches ≥ 350 m above the athlete's threshold band).
Per-segment pace + HR is the unit of analysis; whole-activity averages are valid only
for easy/long runs. The pilot proved this matters: Rio's Jan 20 K-session averaged
4.82 m/s as an activity but 5.21 m/s (3:12/K) at the rep level — and a hot-vs-cool
contrast that looked like a 24 s/mi slowdown at the activity level *vanished* at the
rep level (see pilot doc §segment pass).

```
(grammar, continued)
```

The cross-product is thousands of candidate patterns per athlete. That's the
"not standardized ahead of time" property: nobody enumerates the conclusions; the grammar
generates them. New antecedents/outcomes extend the grammar in code (one pure function
each), which widens discovery without redesign.

### 4.2 Statistical discipline — the part that keeps this honest

Thousands of hypotheses tested on months of data for one human is a spurious-correlation
machine unless gated hard. Non-negotiable gates, applied in order:

1. **Support floor:** ≥ 6 instances of the antecedent in the window (12 weeks min
   history; below that the athlete isn't mined at all).
2. **Effect floor:** conditional outcome rate must differ from the athlete's own base
   rate by a meaningful margin (per-outcome thresholds, e.g. ≥ 20-point rate difference
   or ≥ 0.5 athlete-personal SDs for continuous outcomes).
3. **Split confirmation:** the effect must hold in both halves of the history window
   independently. Kills most flukes.
4. **Survivorship re-test:** a candidate only becomes `active` after the *next* weekly
   run re-confirms it on data that includes at least one new instance.
5. **Cap:** at most 12 `active` observations per athlete, ranked by
   confidence × recency × distinctiveness (prefer patterns that aren't near-duplicates
   of each other — same near-dup logic idea as `memoryWriter`).

Scoring output: `confidence ∈ {low, medium, high}` from support × effect × stability.
`low` never leaves the database.

### 4.3 Weather is first-class (decision 2026-07-07, Rio)

Every workout gets **temperature, relative humidity, and dew point** attached at ingest
(the `fetch-workout-weather` edge function + `weather_actual` path already exist — extend
them to store dew point and humidity, not just conditions). From these, a per-workout
**heat-stress band** (dew point °F: <55 comfortable · 55–65 moderate · 65–70 humid ·
≥70 oppressive, temperature-adjusted). Heat enters the miner twice:

1. **As an antecedent** — patterns like "quality sessions degrade ≥ X% in the oppressive
   band" are discoverable per athlete (heat tolerance is strongly individual).
2. **As a baseline adjuster** — pace/effort outcomes are compared against the athlete's
   own baseline *within the same heat band*, so a July tempo isn't judged against a
   January one. Without this, every hot-climate athlete's summer looks like lost fitness.
   This adjustment also feeds the Coach Read ("6:20s in a 74° dew point is stronger than
   5:56s in January") and pairs with HR/effort, RPE, and mood/stress once app-side
   logging supplies them — effort-at-pace in heat is the cleanest cardiac-strain signal
   available without a lab. A pilot run on Rio's own Strava data (2026-07-07) validated
   the approach: see `signature-miner-pilot-rio-2026-07-07.md`.

### 4.4 Phrasing

New prompt `phrase-signature-observation.v1`: input = the validated statistic + athlete
context; output = one warm sentence in the product voice, citing the number
(the depth-2+ pull-quote rule applies — every surfaced statement carries a specific
number). Cassettes before ship (hard rule #3), including adversarial cases:

- niggle-association stat → phrasing must be associative, athlete's words, no cause, no
  advice, no diagnosis;
- a marginal stat sneaked in → phrasing must not overstate ("always", "definitely" banned);
- prescription bait ("clearly she should rest more") → observation only.

## 5. Storage

### `athlete_signature_observations`

| Column | Type | Notes |
|---|---|---|
| `id` | UUID PK | |
| `user_id` | TEXT | `auth.uid()::text` |
| `pattern_key` | TEXT | Canonical machine form, e.g. `rest_day→quality_exec@+2d`. Unique per (user, key) — re-detections update, never duplicate |
| `category` | closed vocab: `performance \| recovery \| load_response \| mood \| niggle_assoc \| schedule \| environment` | For display grouping + the niggle gate (§7) |
| `statement` | TEXT | Athlete-facing phrasing (LLM output, regenerated when evidence updates) |
| `evidence` | JSONB | `{n, base_rate, conditional_rate, effect, window_start/end, example_log_ids[], last_instance_at}` |
| `confidence` | `low \| medium \| high` | |
| `status` | `candidate \| active \| fading \| refuted \| athlete_dismissed \| coach_confirmed \| coach_dismissed` | |
| `coach_id` / `coach_note` | UUID / TEXT, NULL | Set on coach vet actions |
| `first_detected_at` / `last_confirmed_at` | TIMESTAMPTZ | |
| `created_at` / `updated_at` | TIMESTAMPTZ | |

Status transitions append to `athlete_signature_events` (same shape as
`athlete_ai_profile_events` in the base spec — field/old/new/source/evidence/actor).

RLS in the same migration: athlete SELECT own rows + UPDATE limited to the dismiss
transition via edge function; coach SELECT/UPDATE via `current_coach_id()`; miner writes
service-role only. Migrations append-only, prod via `db push` (hard rules #1, #5, #9).

## 6. Lifecycle

Weekly, appended to the Sunday processing window (`mine-athlete-signature` edge function
+ pg_cron migration):

```
candidate ──(re-confirmed next run)──► active ──(8 wks no new support)──► fading
    │                                    │  ▲                                │
    (fails re-test → dropped)            │  └──(new support)─────────────────┘
                                         │
              (counter-evidence: effect reverses in recent window) ──► refuted
```

`athlete_dismissed` and `coach_dismissed` are sticky: the pattern_key is suppressed and
may only return as `candidate` with ≥ 2× the original support. `coach_confirmed` pins
the observation: exempt from fading (coach judgment outranks decay), still refutable by
strong counter-evidence — with the refutation surfaced to the coach rather than applied
silently.

## 7. Surfacing

**Prompt injection.** New `buildSignature()` in `athlete-state.ts`: top 3–5 active
observations, ≤ 100 tokens, confidence-tagged, coach-confirmed first. Read/agent prompts
bump versions with a `{{signature}}` placeholder + cassettes. Medium confidence renders
as material for a *soft question* (fits the existing "ends with 1–2 soft questions"
posture); high confidence as observation. The Coach tab's lens queries ("how does
fitness compare to last cycle?") get the full active list as context.

**Model of You — "Patterns I've noticed."** Each active observation with its
plain-language evidence ("seen 9 times since March — tap to see the runs") linking to
the actual workouts. Swipe to dismiss, same grammar as memories. Ships in the same phase
as the first injection — visibility before or with use, never after.

**Coach portal — "Signature" section on the AI Coaching Profile card** (base spec §7):
ranked list *including candidates* (coaches see further down the funnel than athletes),
confirm / dismiss / annotate. A confirmed pattern with a coach note ("real — we found
this in her 2024 block too") is the strongest context the AI gets. This is the
guided-by-real-coaches piece applied to substance: a coach curates what the AI believes
about their athlete in under a minute a week.

**The niggle gate.** `niggle_assoc` observations get special handling:
- Coached athlete: surface to the **coach first**; reaches the athlete only after
  coach confirmation.
- Self-coached (Maya): only at high confidence, phrased as an associative soft question,
  never causal, never advisory. The existing injury-language guardrails apply on top.

## 8. Why not a full ML model

A gradient-boosted or neural per-athlete model was considered and rejected for now:
per-athlete n is small (months of data, dozens of quality sessions), opaque weights
can't satisfy the auditability principle (Model of You can't render a weight matrix),
and failure modes are silent. The grammar-miner gets the property Rio asked for —
algorithmic, individual, emergent, no preset conclusions — while every output stays
explainable to the athlete in one sentence. Revisit at real scale, where population
priors ("runners like you") become both possible and a separate consent conversation.

## 9. Phasing (interleaves with base-spec F-phases)

- **S1 — Miner + storage + visibility.** Grammar v1 (≈ 8 antecedents × 7 lags × 6
  outcomes), gates, tables + RLS, weekly cron, Model of You "Patterns I've noticed."
  Runs dark for ≥ 2 weeks first: mine, log, surface nothing — then review precision on
  Rio's own data + any beta athletes before enabling display.
- **S2 — Injection.** `buildSignature()`, `phrase-signature-observation.v1` + cassettes,
  Read/agent prompt bumps + cassettes.
- **S3 — Coach vetting.** Portal signature section, confirm/dismiss/annotate, niggle
  gate routing. (Depends on base-spec F3's card existing; otherwise ships its own card.)
- **S4 — Grammar expansion.** Sleep, weather, race-proximity antecedents; long-run fade
  and RPE-efficiency outcomes; cycle-over-cycle patterns (generalizing the hand-authored
  `buildVsLastCycle` rule, which is one point in this grammar — eventually unify).

**Success measures:** coach confirm-rate on surfaced patterns (target: most confirmed or
plausible, few dismissed-as-nonsense), athlete dismiss-rate (low), and at least one
pattern per active athlete that a human coach calls genuinely useful. If the dark-run
precision review fails, tighten gates before anything surfaces — the fastest way to lose
trust is one dumb "pattern."

## 10. Open questions

- **Q1 — multiple-comparison method.** Split-half + re-test is pragmatic; a formal FDR
  correction (Benjamini-Hochberg across the candidate set) may be warranted once the
  grammar grows. Decide during S1 with real precision numbers.
- **Q2 — minimum history.** 12 weeks proposed; the 2-year HealthKit back-fill
  (onboarding decision, 2026-05-28) means many athletes qualify on day one. Confirm the
  back-fill's data quality is sufficient for mining (paces yes; mood/niggles obviously
  absent pre-signup — outcome availability varies by window).
- **Q3 — signature vs. memories boundary.** An athlete *saying* "I always run better
  after rest days" is a memory (their belief, their words). The miner independently
  finding it is a signature observation (the data's claim). When both exist they should
  cross-reference ("you've said this too") — small, delightful, deferred.
- **Q4 — token budget.** Profile (~80) + signature (~100) + memories inside the ~400
  token context is getting tight. May need the context budget raised to ~500 or a
  per-surface allocation (Read gets signature-heavy, memo-parse gets none). Decide at S2.

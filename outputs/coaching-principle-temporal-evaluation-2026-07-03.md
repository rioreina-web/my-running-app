# Coaching principle — how to evaluate an athlete across time

*First real principle captured from Rio (a coach), 2026-07-03. Feeds both the
Coach's prompt grounding and the multi-horizon trend system
(longitudinal-trends-system-design-2026-07-03.md). In the coach's own framing.*

---

## The core idea: attention is an inverted pyramid over time

A coach looks at every horizon, but weights them very differently. The recent
window is evaluated the heaviest (it's where the athlete *is*); the long window
is there to *learn from*. Each horizon has a distinct job.

## Long-term (multi-year) — learning & development

Every year holds relevant data — most durably through **races and the
progression of paces** (the performance through-line that never stops
mattering, even years back). When you've worked with an athlete for years, look
at how they developed across whole seasons: how **weekly mileage, workout
structure, volume, and paces** progressed. Most importantly, look at what each
training block *produced*:

- Did that block lead to **injuries, setbacks, or overtraining symptoms**? Learn
  from it — don't repeat the training that broke them.
- Did they **succeed and progress**? Then develop them further — a more
  progressive program with **more volume or faster paces** to reach higher goals.

Purpose: use the past to build **smarter, more effective** future training.
Progressive overload, informed by history. Long-term is the **lowest evaluation
weight but never zero** — races and pace progression keep it in the picture.

## Medium-term (6 months – 1 year) — healthy progression

Here you're confirming the athlete is **progressing — and it doesn't have to be
linear.** You want:

- Good signs of progression; the athlete **training within themselves**.
- Consistency of **greens** (feeling good) over **reds** (struggling, hurting,
  fatigue, lots of injury mentions).
- A **positive trend** across the 6-month–1-year window.

Purpose: make sure the athlete is developing healthily and trending up, mostly
green, not breaking down.

## Short-term (final 3 months → final month → current) — the sharp end

This is **the most important and the most heavily evaluated.** Workout structure
and volume matter most here.

- Are they hitting the **key workouts and key paces** for their goal (if they
  have one)?
- Where is their **current fitness** — where is the athlete *right now*?

Purpose: race-specific readiness and execution of the key sessions.

## The weighting (how much each horizon counts)

Strict descending order — most weight on the present, decaying out, but the long
tail never hits zero:

**1 month  >  3 months  >  6 months  >  1 year  >  longer term**

| Horizon | Job | Weight |
|---|---|---|
| **1 month** | current fitness, key workouts/paces, where they are *now* | **highest** |
| 3 months | the sharp end of the current block — hitting the goal work | high |
| 6 months | healthy, mostly-green progression check | medium |
| 1 year | year-over-year development, "this time last year" | lower |
| longer term | learning from past blocks; races + pace progression | lowest (never zero) |

## Green vs red (the qualitative trend)

- **Green** = feeling good, consistent, training within themselves.
- **Red** = struggling, hurting, fatigue, injury mentions.
- Over 6 mo–1 yr, you want the balance **trending green**.
- (Maps directly to the app's `life_context` + niggles — mood, fatigue, "felt
  harder than it looked", body mentions.)

## The learning loop (what makes this coaching, not just charts)

Tie **training patterns to outcomes**: which blocks / volumes / workout
structures led to **red** (injury, overtraining) vs **green** (progress). Use
that to build the next block smarter — ease off what broke them, progress what
worked. This is the intelligence the multi-year horizon exists to produce.

---

## Reading trends is not reading a slope — classify the situation

The **current state is the most important thing**, and progression is **not
linear** — so a raw trend line lies exactly when it matters most. You need
**rules that recognize what situation the athlete is in**, and read the trend
*through* that situation. Candidate states:

- **Building** — volume/quality rising, consistent.
- **Peaking / sharpening** — quality high, volume leveling, near a goal.
- **Maintaining** — steady, flat.
- **Detraining** — volume *and* quality genuinely fading (the real concern).
- **Layoff / gap** — a break: ~10+ days no running, or a collapse to near-zero.
- **Comeback / returning** — running resumed after a gap, ramping from a low base.
- **Overreached** — load high *and* reds piling up (fatigue, niggles).

### The hard case: injury gap → fast comeback

Someone is injured, doesn't run for ~3 months, then rebuilds to a high level in
2–3 months. This is tough to read and it happens often. Rules:

1. **Detect the gap** — near-zero running for ~10+ days. Don't treat pre-gap
   fitness as "current," and don't let the gap poison the trend slope.
2. **Mark them *returning*** — running resumed and ramping. Flips the label from
   "declining" to "rebuilding."
3. **Anchor to the ceiling, weight the recent slope** — a returning runner
   regains prior fitness *faster* than a novice builds it. Anchor to the
   demonstrated pre-gap ceiling; weight the **since-return** trajectory (rising),
   not the gap-spanning one (falsely down).
4. **Be honestly uncertain** — how fast/far they come back depends on gap length,
   injury vs. choice, age, history. Recognize the comeback pattern and **widen
   the range / lower the confidence** rather than guess a precise number. Name
   the situation, hedge the prediction.

*(This is the situation-classifier layer sitting on top of the fitness
predictor's existing detraining detection + anchor decay.)*

## Design implications for the trend system

1. **Weight recent horizons heaviest** in what reaches the coach — 3-mo, 1-mo,
   current fitness are primary; 6-mo–1-yr is a progression check; multi-year is
   context/learning, not equal-weight data.
2. **Medium-horizon = a green/red progression score** over 6-mo–1-yr, computed
   from the life_context + niggle buckets.
3. **Long-horizon = cause→effect learning** — attribute outcomes (injury,
   overtraining, breakthrough) to the training that preceded them, so the coach
   can reason "last time you built like this, X happened."
4. **Goal-aware short horizon** — when a goal exists, the 3-mo/1-mo evaluation
   centers on hitting the key workouts and paces for it.

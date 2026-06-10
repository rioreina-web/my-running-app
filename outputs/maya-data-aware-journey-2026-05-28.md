# Maya's Data-Aware Training Journey

**Last updated:** 2026-05-28
**Status:** Foundational doc. Read before any design or engineering
decision that touches Maya's experience.
**Companion to:**
- `outputs/product-state-2026-05-28.md` (the product as a whole)
- `outputs/maya-product-roadmap-2026-05-28.md` (decisions and phases)

This doc is about what the product *is* at the experience level. The
roadmap is what we ship and when. The product-state doc is what's
there today. This is what we're actually building.

---

## What the journey is

The journey is Maya's training arc as a continuous, narrative thing.
Not a list of workouts. Not a chart of metrics. One through-line she
can see, scroll, and feel.

It runs from her last race (the 3:28 marathon) through her current
build toward her next race (BQ at 3:16) and beyond. It contains:
hundreds of runs, hundreds of voice memos, weeks of stacked volume,
niggles that came and went, weeks where life pushed back, races she
ran along the way, mood patterns, recovery weeks, peaks, valleys.

**The journey is not the data. The journey is what the data MEANS
when you read it as a story.**

---

## Two signal streams, fused

The product runs on two streams. Either alone is partial. Fused, they
reveal what neither shows on its own.

### Qualitative stream — what she said

- Voice memos in her own words (transcribed, cleaned)
- Mood label per memo — closed vocabulary: *energized, positive,
  neutral, tired, struggling, injured*
- Body-part mentions — niggles, closed vocabulary, verbatim quoting
- Life context she mentions inline — weather, sleep, work, stress,
  family, travel, life events

### Quantitative stream — what she did

- Workouts: pace zone label (Easy / Moderate / Steady / MP / HMP / LT
  / 10K / 5K / 3K / Mile + Long / Long wo), distance, splits, pace
- Weekly mileage rollups
- Time spent at each pace zone (pace × volume distribution)
- ACWR (acute:chronic load ratio)
- Fitness curves with range + confidence
- Race anchors — date, distance, finish time, official/unofficial
- HealthKit-sourced cross-training, strength sessions

### What becomes visible when they fuse

Neither stream tells the truth alone. The product's job is to fuse
them honestly.

- *A 7:29 tempo with "felt easy" is a different journey moment than a
  7:29 tempo with "had to dig the last 2 miles."* Same quantitative
  data; different story.
- *A 42 mpw week with positive mood every day* differs from *a 42 mpw
  week with three "tired" labels and a niggle mention.* Same volume;
  different journey.
- *A 14 mi long run after a "got 4 hours of sleep" note* shouldn't
  be compared to last cycle's 14 mi without that context. The
  quantitative says one thing; the journey says another.
- *Right hamstring on three Tuesdays* requires both streams to surface:
  Tuesdays = tempo (quantitative), hamstring mention = qualitative.
  Neither alone gets there.

This is the wedge under maximum pull. Pure-data competitors miss the
qualitative. Pure-journal competitors miss the analytics. We do both,
and the AI reads them together.

---

## Life is part of the journey

Training doesn't happen in a vacuum. Maya's journey includes
everything that shapes her training — not just the runs.

- **Weather** — a 92°F humid tempo and a 55°F tempo are not the same
  workout. Pace is meaningless without weather context.
- **Sleep** — a 16-mile long run on five hours of sleep means
  something different than the same run on eight.
- **Work stress** — a hard week with a deployment crunch and a 42 mpw
  total is not the same week as a calm 42 mpw.
- **Family and life events** — a wedding weekend, a sick parent, a
  travel week.
- **Recovery and life choices** — a Friday-night party, a clean-eating
  stretch, a hydration habit she's been working on.

**Two implications:**

1. The product must let her capture these signals. Voice memos
   already do — when she says them. We should make it easier to
   capture them without forcing it into the journaling habit. A
   light-touch quick-capture for weather, sleep, life context would
   reduce friction.
2. The AI must comprehend them when reading her journey. *"The 18
   felt tough; she'd also flagged 4 hours of sleep that night.
   That's the context for the 'tough,' not a fitness signal."* That
   kind of reading is what makes the AI feel like an attentive
   coach instead of a data analyzer.

---

## How the journey shows up in the product

The journey manifests in three primary forms, mapped to three surfaces.

### As record — the Log/Journal tab

The 6-month diary. Voice memos in italic, mood pills, niggle chips,
quantitative workout data, life context inline. **Pure record. No AI
commentary.** Her own story, told by her, with the data woven in.

This is the place where the journey lives most literally. Scrolling
back is scrolling back through her actual training. Tap an entry,
see the full memo and workout detail. Search by body part, by mood,
by date range.

### As trajectory — the Trends tab

The 5-second view of where she is and where she's heading. Race-
anchored fitness range with confidence, volume trend, ACWR, niggles
tile, **26-week fitness chart with her races plotted as anchors on
the timeline.**

The Trends tab is the journey *as analytics*. The chart shows the
arc visually — fitness building from her 3:28 PB through this build
toward her 3:16 target. Niggle markers, mood density, life-context
markers (if captured) can overlay the chart so the journey reads as
one frame.

### As observation — the Coach tab

The AI's read of her journey, on demand. When she taps generate,
Coach surfaces an editorial paragraph that fuses both streams and
reads her life context. **Feeling first. Then workouts. Then
mileage.** Encouragement with warmth, never toxic positivity. Ends
with 1-2 soft questions for her to sit with.

She can ask Coach to read the journey through specific lenses:
*"How does my fitness compare to last cycle?"* *"Anything I should
pay attention to with the hamstring?"* *"Read this week through the
recovery lens."* The AI carries her journey and answers from it.

---

## How the AI reads the journey

The AI's job is not to project fitness, prescribe workouts, or
diagnose niggles. It's to be the attentive coach who has read her
journey carefully and surfaces what an athlete might miss.

**Voice principles for reading Maya's journey:**

1. **Read the hard days first. Quality work is the story.** A real
   coach weights tempos, thresholds, intervals, and long run workouts
   more heavily than easy mileage. The story of a week is told by
   what happened in the quality sessions (MP / HMP / LT / 10K / 5K /
   3K / Mile / Long wo). Easy days are connective tissue, not
   narrative. *"The Tuesday tempo locked in at 7:29 — four weeks ago
   that was 7:35"* is the story. *"Wednesday's easy run felt easy"*
   is filler.
2. **Default to good or neutral feedback. Most training is just
   training.** Typically all training is hard — *hard is the norm,
   not a problem.* Don't manufacture drama. Don't probe for issues
   that aren't there. *"You're in rhythm — three weeks above 40"* is
   the right register for an unremarkable solid week.
3. **Fitness gains are read from pace trends, not volume numbers.**
   Easy paces creeping down is aerobic improvement. MP pace dropping
   at the same effort is fitness building. Quality pace stable at
   lower HR is adaptation. The AI reads these trends and surfaces
   them in plain language without explaining the math.
4. **Volume in trend context, not absolutes.** *"Holding at 42"* is
   a fact. *"Three weeks above 40 now, which is settling into
   rhythm"* is the story. Volume gets meaning from direction and
   duration, not from a single number.
5. **Struggle recognition is SPECIFIC, not generic.** Don't
   generalize a "tired" memo into a fatigue narrative. The AI
   distinguishes between:
   - **Injury** — niggle clusters, body part patterns, severity
     language in memos
   - **Overtraining** — load spike + fatigue language + pace decay
     at the same effort
   - **Heat / weather** — weather mentions in memos + pace shifts
     correlated with conditions
   - **Recovery deficit** — sluggish language + sleep mentions +
     repeated low mood without injury or load explanation
   Each gets named specifically. Generic "you're tired" is wrong.
6. **Feeling shows up at the start as context, not as headline.**
   The voice memo language for the week ("smooth," "in rhythm,"
   "had to dig") opens the Read as orientation. But the *story*
   gets told through the workouts.
7. **Warm encouragement, not toxic positivity, never negativity.**
   Three registers exist, and the AI lives in only one of them:
   - **Negative** (wrong): *"A 12-minute PR is ambitious. 3:20 might
     be more achievable."* Kicks her goal down. Often wrong —
     athletes surprise themselves. Dampens the journey.
   - **Hype man** (wrong): *"You got this! 3:16 is yours!"*
     Performative cheerleading. Empty. She knows it's not honest.
   - **Real coach** (right): *"Four weeks in. Volume settling above
     40, tempos coming down. The work is real."* Trusts her goal,
     shows her the data, lets her own the conclusion.

   Four sub-principles inside this:
   - **Trust the goal. Don't grade it.** Her stated ambition is hers.
     The AI's job is to show her what her training is doing, not to
     assess whether the goal is "realistic." Even a big jump gets
     met with *"what does the build to get there look like?"* not
     *"that's unrealistic."*
   - **Encourage without hype.** Warmth is honoring the work she's
     actually doing. Hype is empty.
   - **Keep her safe without being preachy.** Niggle patterns, load
     spikes + fatigue, recurring injuries — surfaced clearly but
     gently. *"Right hamstring keeps showing up — worth watching"*
     not *"you should rest"* (directive) and not *"this could be
     serious"* (catastrophizing).
   - **Enjoy the journey.** Running is supposed to be enjoyable.
     Voice memo language tells you when joy is intact and when it's
     fraying. The AI notices both — and reflects the good moments
     back without making everything about race-day performance.
     *"You've been smiling in your memos this week"* is a real
     observation; not every observation needs to be about fitness.
8. **Read the life context.** Weather, sleep, stress, recovery — if
   she mentioned it, the AI accounts for it. A 7:35 tempo in 92°F
   humidity is not a 7:35 tempo in 60°F.
9. **Anchors and goals are silent.** The 3:28 Houston PB and the
   3:16 December goal shape what the AI notices. They are never
   spoken back to her.
10. **Soft questions to engage her thinking.** End with 1-2 things
    to sit with. Never directives. Never *"you should."*
11. **She can ask for specific lenses.** Coach isn't a fixed
    monologue. She can ask Coach to read her journey from a specific
    angle (recovery, fitness, niggle, comparison), and the AI
    answers from her journey.
12. **Recency dominates for current capability — but ceilings stay
    sticky.** The AI fuses three weighting types: time-decayed
    signals for current capability (last 2 months heaviest), sticky
    facts that never decay (PRs, peak workouts ever, career bests),
    and patterns that accumulate over years (niggle history, weather
    preferences, cycle templates). A workout from 18 months ago
    doesn't predict current capability, but Maya's PR is forever a
    fact. Layoffs reduce current capability, not ceiling — comeback
    timelines are shorter than initial-build timelines because the
    body remembers. Predictions during comeback periods should
    reference both current trajectory and personal ceiling honestly.
    *"Range 3:35 – 3:45 right now; trajectory toward 3:28 PR within
    8-12 weeks if build holds"* is a real coach observation. A pure
    decay-curve prediction would miss the ceiling and read her as
    permanently regressed, which she isn't.
13. **Fitness is multi-signal, not single-number.** Mileage alone
    doesn't measure fitness. The honest fitness picture fuses seven
    signal types, all read together:
    1. *Quality-work pace trends* — MP / HMP / LT efforts locking in
       faster at the same effort
    2. *Volume + absorption* — current mpw plus how she's handling
       it (mood, recovery, freshness)
    3. *Pace distribution health* — appropriate time across zones,
       not grinding everything middle-pace
    4. *Recovery quality* — mood arc, sluggish vs. fresh signals,
       bounce-back day-to-day
    5. *Injury / niggle status* — clean or carrying, recurring
       patterns reactivating
    6. *Race-effort evidence* — recent races, tune-up efforts,
       sustained race-pace work
    7. *Training-life integration* — running fit despite life stress
       is itself a fitness signal
    The CONFIDENCE on a fitness range depends on how many signals
    agree, not on data volume alone. All signals aligned → HIGH
    confidence, tighter range. Signals in tension → LOW confidence,
    wider range. *"Hard to predict, but the signals point toward..."*
    is a real coach acknowledging that fitness isn't deterministic.
    When signals disagree, the AI surfaces the tension explicitly:
    *"Pace work is locking in, volume is climbing, but you've
    mentioned 'sluggish' three times this week and the right hamstring
    keeps coming up — the body might be saying something the workouts
    aren't yet."* That's the multi-signal read.

**What the AI never does:**

- Quote her voice memos verbatim back to her (paraphrase patterns
  instead — Q16)
- Explain its math out loud (*"based on your 3:28 PB and your 3:16
  goal..."* is exactly what it never says)
- Prescribe workouts, recommend stopping training, diagnose niggles,
  recommend medical action
- Restate her goal as if she didn't know it
- Pretend the data tells a complete story when life context is
  missing

---

## What this framing makes us see

### What's working

- Voice memo capture works (Log tab, transcription, mood/niggle
  extraction)
- Closed vocabularies hold (mood, niggles)
- Race history infrastructure exists (`confirmed_races` table)
- Quantitative analytics infrastructure exists (ACWR, fitness curves,
  pace tables, weekly rollups)
- Coach Read concept exists in code (CoachReadView.swift)

### What's missing

- **Life context isn't structured input.** Voice memos catch some of
  it. The product doesn't prompt for it or surface it as a separate
  signal. The AI can read what's in the memos but doesn't have a
  reliable channel for weather, sleep, life events.
- **The journey isn't visible AS a journey anywhere.** The journal is
  a list of entries. Trends is a tile dashboard. Coach is a paragraph.
  No single surface SHOWS the arc — fitness curve + races + niggles
  + moods + life events in one frame.
- **The AI doesn't currently fuse the two streams systematically.** It
  looks at data for fitness prediction. It looks at memos for niggles.
  It doesn't always read them together when generating observations.
  Cross-stream reading is the whole wedge.
- **Coach Read is currently too structured for what it needs to be.**
  The PlateStrip + Byline + Signature + Sources + ConfidenceBar
  scaffolding is heavier than the minimal "one prose paragraph +
  soft questions" we've decided on.
- **No "ask Coach for a specific lens" capability.** Currently Coach
  Read is a fixed-shape morning generation, not a conversational
  surface Maya can query.

### What to redesign around

1. **The journey overview is the foundation of Trends.** Trends
   becomes "the journey as analytics" — the 26-week fitness arc with
   races, niggles, mood density, life-event markers overlaid. One
   frame that shows the arc.
2. **Structured life-context capture.** Beyond voice memo, a light-
   touch quick-capture for weather / sleep / stress / life. Could
   be a small chip-row in the Log tab, or a prompt after voice memo
   ("anything else to note?"). Reduces friction; gets it in the data.
3. **Cross-stream reading is the Coach Read system prompt's
   primary job.** Every generation explicitly reads both streams,
   weaves them together, and surfaces the cross-stream pattern as
   the lead.
4. **Coach Read as conversational surface.** Default Read on demand
   (per the 2026-05-28 decision). Plus the ability for Maya to ask
   Coach to read her journey through a specific lens.
5. **The journal entry visualizes life context.** When a voice memo
   mentions weather or sleep or stress, the journal entry surfaces
   that as a small chip alongside the mood and niggle chips. Maya
   can see her own context at a glance.

---

## What we deprioritize

- Surfaces that show one stream alone in isolation. A niggles-only
  screen that doesn't connect to training load is a partial read of
  the journey.
- "Pure" analytics without journey framing. The data is useless
  without her story attached.
- Coach Read versions that don't read life context. If the AI can't
  comprehend that training is part of life, it isn't doing the job.
- Prescriptive features. Plans, recommended workouts, "you should
  do X today" — all out. Maya owns decisions; the AI observes.

---

## Open questions

These are questions the journey framing surfaces. They aren't all
v1 questions. They're flagged here so they don't disappear.

1. **Life-context capture UX.** How do we let Maya tag weather /
   sleep / stress without making journaling feel like a chore? Auto-
   pull weather from HealthKit / location? Light chip-row on Log?
   Voice memo post-prompt?
2. **The journey-as-one-frame viz.** What's the right shape? A
   horizontal timeline with markers? A 26-week chart with overlaid
   density? Multiple stacked panes? This is design work that needs
   exploration.
3. **AI life-context depth.** Weather, sleep, stress, recovery — clear
   signals. Caffeine, supplements, hydration, social life — could
   become surveillance. Where's the line?
4. **Shared and social signals.** Running with a friend, group long
   runs, race-day support crew — these are part of her journey.
   Currently nowhere in the data.
5. **Multi-year journey visibility.** Maya's history goes back 2
   years (her last marathon was that long ago). What's the right
   way to show 2 years vs. 6 months vs. since last race?
6. **The cycle comparison feature.** "Compared to last cycle" is the
   sharpest journey-reading the AI can do. It requires cold-tier
   block summaries (Phase 6, memory architecture). When does this
   ship and what's the minimum viable version?

---

## How to use this doc

- **Before any design or engineering decision touching Maya's
  experience**, read sections 1–4 (what the journey is, the two
  streams, life as part of the journey, how it shows up).
- **When designing a surface,** ask: how does this surface honor
  the journey? Does it show fused signal or single-stream? Does it
  account for life context?
- **When designing AI behavior,** ask: does this read both streams?
  Does it read life context when present? Does it lead with feeling?
- **When prioritizing,** ask: does this build the journey, or build
  a side surface? Journey-building work wins.

This doc gets updated as the journey concept sharpens. Open questions
get answered (and the answer + date logged in the roadmap's decisions
log). New observations about the journey get added here.

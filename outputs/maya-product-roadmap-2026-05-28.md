# Maya's Product Roadmap

**Last updated:** 2026-05-28
**Status:** Living doc. Read at the start of every session focused on
Maya's experience. Update at the end.
**Companion to:** `outputs/product-state-2026-05-28.md` (which holds
Maya's persona definition).

---

## Decisions log

Track decisions as they're made. Don't delete entries — show the call
and when it happened.

- **2026-05-28** · *Structural shift confirmed.* The product moves
  from plan-centric to journal-centric architecture. `activePlan ==
  nil` is a first-class state, not a failure mode. Plan surfaces are
  not deleted; they stop being where new investment goes.
- **2026-05-28** · *Goal is first-class, fitness is the fallback
  lens.* A stated goal (race time, target date) is the preferred lens
  for every observation. When no goal is set, the system reframes
  around "current fitness" — where she is, what her trajectory looks
  like — without inventing a target. Goals are stored independent of
  plan subscription.
- **2026-05-28** · *Q8 — Journal as pull-down from Log.* Log tab is
  voice-first at the top; the journal becomes the default scrolled-
  down view. One tab, two surfaces. Keeps the 5-tab IA. Maya sees
  the journal every time she records a memo.
- **2026-05-28** · *Q12 — New Train tab replaces TrainingTabView for
  everyone.* Maya's journal-centric Train tab becomes THE Train tab.
  Plan context (week N of M, block totals) layers on top as a header
  strip for plan-using athletes, but the core surface is journal-
  native. One codebase, one UX.
- **2026-05-28** · *Q17 — Coachable moments surface to self-coached
  Maya directly.* Framed as observations, not directives. Stays
  within voice principle (AI advises, never acts). The next sub-call
  is which *kinds* of moments surface to her vs. stay coach-only.
- **2026-05-28** · *Q4 — Goal entry lives inline on Trends.* The
  GOAL 3:16 line at the bottom of Trends becomes tappable. Tap to
  set, edit, add another goal. Goals are surfaced where they're
  being used.
- **2026-05-28** · *Q2 — 2-year HealthKit back-fill on first launch.*
  Maya signs up, grants HealthKit, app pulls 2 years of runs in the
  background. Journal is pre-populated. Race detection runs over the
  back-fill. She lands in a product that already knows her.
- **2026-05-28** · *Q9 — Journal includes all HealthKit workouts +
  voice memos.* Runs, bikes, swims, hikes, strength all appear with
  appropriate framing. Voice memos attach to any of them. ACWR and
  fitness math still computed from running only, but the diary is
  honest about everything she did.
- **2026-05-28** · *Q11 — Default journal time window: last 6
  months.* Long enough to feel like a real diary, short enough to
  load fast. Infinite scroll back for anything older.
- **2026-05-28** · *Q17 follow-up — Pattern observations only.* Mood
  arcs, niggle clusters, fitness-trend observations surface to Maya.
  Operational moments (load spike + injury risk, low compliance)
  stay coach-only or surface in softer 'something to think about'
  framing. Two-tier system.
- **2026-05-28** · *Q1 — Onboarding sequence: HealthKit → races →
  goal.* Sign in. Grant HealthKit (back-fill starts). 'We found
  these recent races — confirm or edit.' Optional 'what are you
  training for?' goal-set. Friction front-loaded; payoff is Maya
  lands in a journal that already knows her.
- **2026-05-28** · *Q3 — Goal optional during onboarding.* Maya can
  skip. If she skips, fitness-only lens activates. Goal entry stays
  accessible inline on Trends (per Q4). No nag screens.
- **2026-05-28** · *Q19 — Auto-detect races, prompt to confirm.* On
  back-fill, system scans for workouts tagged Race or matching known
  race distances at race pace. Surfaces 'we found these — confirm or
  edit.' Maya owns the final confirmation; system does the work.
- **2026-05-28** · *Q22 — AI can connect niggles to training load
  as pattern observation.* 'Right hamstring mentions cluster on
  Tuesdays — your tempo day.' Surfaces correlation as observation,
  doesn't diagnose, doesn't recommend action. Stays within the
  wedge — noticing a pattern, not interpreting medically.
- **2026-05-28** · *Q15 — Daily Coach Read on app open.* The Read
  regenerates if it's a new day. Backend cost: ~1 generation/day/user.
  Matches the daily-check-in rhythm of journaling.
- **2026-05-28** · *Q16 — Coach Read paraphrases, doesn't quote
  memos verbatim.* The AI summarizes themes ('tightness keeps
  showing up on the right hamstring side this week') rather than
  quoting her words back. Her own words live in the journal view;
  Coach Read is observation, not playback.
- **2026-05-28** · *Q23 — Cross-training stays out of running-fitness
  math because running and cross-training are different KINDS of
  stress, not different amounts.* Running carries mechanical/impact
  load (wear and tear). A 2-hour run and a 4-hour bike ride are
  cardiovascularly comparable but mechanically very different.
  ACWR, fitness prediction, and pace × volume are running-only.
  Cross-training shows in the journal (Q9: all HealthKit workouts
  appear) but does not move the running-load needle.
  **Sub-question opened:** should cross-training surface somewhere
  in the load picture — e.g. a separate 'total active hours' metric,
  or a 'cardio load' surface independent of running ACWR — so the
  diary feels honest about everything the body's doing? Not for v1
  but worth flagging.
- **2026-05-28** · *Q25 — Cold-tier block summary is rich.* Each
  block record contains: date range, average mpw, peak mpw, # of
  workouts at MP / tempo / threshold, race result (if any), key
  workouts. Enables 'compared to last cycle at this point you were
  at 35 mpw' observations. Schema designed during Phase 6.
- **2026-05-28** · *Q10 — Journal is pure record, no AI annotation
  inline.* Workouts, voice memos, mood, niggles render as Maya's
  diary without AI commentary. AI observation lives on Coach Read.
  Journal stays uncluttered; observation stays in one place.
- **2026-05-28** · *Q13 — Default rolling window for Train 'current':
  last 7 days.* Tightest, most current. Maya can swap to longer
  windows (4/8/12 weeks) for context via the segmenter.
- **2026-05-28** · *Q20 — All race distances anchor fitness, recency-
  weighted.* A 1:32 half from 6 weeks ago anchors more strongly than
  a 3:28 marathon from 2 years ago. Race-equivalence math (already
  in derivePaceTableFromGoal) projects all distances to marathon-
  equivalent. Recency wins, but every race matters.
- **2026-05-28** · *Q24 — Sleep, HRV, weight stay out of v1.* Per
  CLAUDE.md, recovery is a v1.5 pillar. v1 reads voice-log fatigue
  and HealthKit sleep as background signal but doesn't surface them.
  Recovery becomes a first-class surface in v1.5. Weight tracking
  needs careful design when introduced (eating disorder risk).
- **2026-05-28** · *Q5 — Multi-goal: one primary, multiple secondary.*
  Maya can have a 3:16 marathon as primary AND a sub-1:30 half tune-up
  as secondary. Primary anchors the fitness lens. Secondaries surface
  on Trends as 'also working toward' chips. Matches how serious
  athletes actually train multi-distance cycles.
- **2026-05-28** · *Q6 — Goal change: recompute everything, log the
  change.* Moving the goal from 3:16 to 3:20 recomputes pace zones,
  reframes fitness range, shifts Coach Read voice. The change lands
  in goal history ('changed from 3:16 to 3:20 on June 15'). Honest —
  nothing is lost, nothing is hidden.
- **2026-05-28** · *Q14 — 'Compared to last cycle' surfaces auto when
  history supports it.* If Maya has a prior block of comparable length
  and goal-distance in cold tier, cycle-comparison observations
  surface on Coach Read automatically. Quiet when history is sparse.
  No toggle — smart presence.
- **2026-05-28** · *Q21 — Niggles surface: inline journal chips +
  dedicated Niggles section.* Body-part mentions tag journal entries
  with a small chip ('right hamstring'). Trends has a NIGGLES tile
  showing active mentions. Maya taps in to see the full timeline of a
  body part. Honors detection-not-diagnosis. No standalone tab.
- **2026-05-28** · *Q7 — Training goals and race goals are one
  concept, different shapes.* All goals have: name, target, target
  date, success criteria. Race goal = '3:16 marathon by March 1.'
  Training goal = 'consistent 6 days/week through fall' or 'first
  50-mile week by August.' Same data model, different lens for
  progress tracking.
- **2026-05-28** · *Q18 — Race-entry edit happens on the journal
  entry.* If a workout was auto-detected as a race, the journal entry
  has an 'edit race details' affordance — tap to confirm/edit
  distance, finish time, event name. Edit happens where Maya sees the
  race. Discoverable.
- **2026-05-28** · *Q27 — Full data export ships in v1.* CSV/JSON
  bundle of workouts + voice memos + cleaned notes + race history at
  any time. Trust requirement when she's putting 6 months of life
  into the product. Legal teams require this regardless.
- **2026-05-28** · *Q28 — Voice memos queue locally when offline.*
  Audio saves with a 'will sync when online' indicator. Transcription
  + Gemini processing happen automatically when connection returns.
  Critical for trail/rural athletes.
- **2026-05-28** · *Q26 — Decay weighting math deferred to Phase 6
  design.* The math for how race anchors decay over time (a 1:32 half
  6 weeks ago vs a 3:28 marathon 2 years ago) is engineering work that
  belongs in the memory-architecture phase. Flagged here so it doesn't
  get lost.
- **2026-05-28** · *Editorial style AND analytical depth — both
  first-class.* The journal is the heart, but Trends and Train ship
  with serious data viz: pace × volume distributions, fitness arcs,
  race anchors plotted on timelines, ACWR bars, cycle-comparison
  overlays. Not editorial flourish on thin data. Editorial framing
  *around* real analytical depth. Both, not either.
- **2026-05-28** · *Q12 amended — Train tab supports calendar view
  as a viewing mode.* Original decision held (journal-centric Train
  replaces plan-centric one). Amendment: calendar view is one of
  Train's viewing modes — shows past completed workouts and
  forward-looking planned workouts together. Works for athletes with
  coach-issued plans AND for athletes who self-plan ("Thursday will
  be a tempo, Saturday will be a long run"). Maya can use the
  calendar view to look forward at her own intentions even without
  a coach.
- **2026-05-28** · *Workout type vocabulary needs to be specific.*
  Generic "Easy / Tempo / Long" is not enough. Real coach-level
  distinctions matter — *very easy* is different from *easy*, *long
  run* is different from *long run workout* (long run with embedded
  quality). Full vocabulary in 'Workout taxonomy' section below.
- **2026-05-28** · *Calendar mode shows actual training first, plan
  if available.* The calendar's spine is what Maya has actually done
  (past completed workouts auto-populated from HealthKit) plus her
  own self-planned future workouts (tap a future day to add a planned
  workout — "Thursday · Tempo 7 mi"). If she happens to be on a
  coach-issued plan, that layers in as supplementary context. Plan
  is never the primary axis; her own training is.
- **2026-05-28** · *Steady is its own workout type.* Distinct
  zone — marathon-prep moderate-aerobic work. Different from "easy
  on the harder side." Coaches who care about this distinction
  (Canova lineage) get it as a named label.
- **2026-05-28** · *Long run workout is its own type.* A 16 mi @ easy
  is Long run. A 16 mi with 8 @ MP is Long run workout. Two labels,
  two arrows on the pace × volume distribution. The distinction
  matters for analytics and for cycle comparison.
- **2026-05-28** · *Pace zone taxonomy is 10 zones, not workout
  structures.* "Tempo" and "Threshold" are ambiguous labels for what
  is honestly MP, HMP, or LT work. The zone IS the label. Ten zones:
  Easy / Moderate / Steady (three effort tiers) + MP / HMP / LT / 10K
  / 5K / 3K / Mile (seven race-pace zones). Adds Moderate, HMP, and
  3K to the canonical seven. Engineering work in Phase 2 to extend
  `derivePaceTableFromGoal`.
- **2026-05-28** · *IA shift — 4-tab nav, Plan into Train.* Tab count
  drops from 5 to 4 (`Log · Train · Trends · Coach`). Plan is a
  subset of Train, not its own tab. Plan-using athletes see coach-
  issued workouts in Train's calendar with distinct visual treatment;
  self-planners (Maya) tap-to-add their own future workouts in the
  same calendar. Plan-related infrastructure survives at the data
  layer — coach plans still exist — but the standalone Plan tab is
  gone.
- **2026-05-28** · *Tab order swap.* New IA order: `Log · Trends ·
  Train · Coach`. Mental flow: input → overview → detail → synthesis.
  Trends moves from tab 3 → tab 2. Train moves from tab 2 → tab 3.
- **2026-05-28** · *"Long run wo" — long run workouts don't carry
  precise pace prescriptions.* A long run workout is a long run with
  embedded *references* — "the last 6 miles steady," "build to MP,"
  "4 mi HMP toward the end." The zone work is captured inside the
  workout (notes, structure metadata), not as part of the workout
  label. Calendar label is just `Long wo` (or `Long+`). The structural
  precision of `MP 7 mi` doesn't apply to `Long wo`; that's a feature
  of how long runs actually work.
- **2026-05-28** · *Coach surface — framing needs refinement.* The
  Daily Read concept holds (editorial observation surface), but the
  current shape (PlateStrip + Dateline + Byline + Headline + Prose +
  Signature + Sources + ConfidenceBar + Ask bar from CoachReadView.swift)
  may be too structured for what Maya actually needs. Specific
  refinement direction TBD — open question for next session.
- **2026-05-28** · *Coach voice posture: observation + soft
  questions.* The Read isn't pure passive observation — it ends with
  1-2 soft questions for Maya to sit with. *"How did the 18 feel
  relative to last cycle's?"* *"Is the right hamstring pattern
  getting your attention, or are we both just noticing it?"* Engages
  her in her own thinking. Never prescribes. Stays within "AI
  advises, never acts."
- **2026-05-28** · *Coach format: minimal — one prose paragraph +
  questions.* Drop most of the editorial scaffolding (PlateStrip,
  Byline, Signature, ConfidenceBar). Keep: small eyebrow date,
  headline, 2-4 observation sentences as prose, italic soft questions
  at the end, source references inline as tappable chips. Clean
  editorial feel without the layout overhead.
- **2026-05-28** · *Coach role: on-demand only. Q15 reversed.* The
  earlier decision (daily Read on app open) is replaced. Coach Read
  does not auto-generate each morning. Maya taps "generate" when she
  wants one. Lower backend cost. Higher intentionality. The Coach tab
  shows her last generated Read until she requests a fresh one.
  Aligns better with "AI advises, never acts" — the AI doesn't
  proactively give her opinions, she invites them.
- **2026-05-28** · *Coach voice — feeling first, then workouts, then
  mileage; warm encouragement, not toxic; reads life context.* The
  AI Read leads with how Maya is feeling (qualitative), then how
  recent workouts went, then how the mileage is moving. Encourages
  smart progression with positivity. Doesn't just look at data —
  comprehends that training is part of life. Reads weather (hot &
  humid), sleep, work stress, recovery, life events when she's
  mentioned them. Never toxic-positive ("you got this!"); warm and
  real instead ("you're trending the right way").
- **2026-05-28** · *Maya can ask Coach for specific lenses.* The Read
  isn't a fixed monologue. She can ask: "How does my fitness compare
  to last cycle?" "Anything I should pay attention to with the
  hamstring?" "Read this week through the recovery lens." The AI
  carries her journey and answers from it. Conversational on top of
  the default Read.
- **2026-05-28** · *Reframe — journey-centric, not surface-centric.*
  The product creates a data-aware journey by fusing qualitative
  (voice memos, mood, niggles, life context) with quantitative
  (mileage, workouts, paces, races). See
  `outputs/maya-data-aware-journey-2026-05-28.md` for the
  foundational doc.
- **2026-05-28** · *Maya's specifics get concrete.*
  - **PB: 3:28 at the Houston Marathon, January 2026** — 5 months
    ago. Recent fitness anchor, not a stale 2-year-old PB. The cycle
    she's currently in is the immediate post-Houston build.
  - **Goal: BQ 3:16 by December 7, 2026** — ~193 days out as of
    2026-05-28. Roughly a 27-week build window.
  - **Journal density: ~5 entries/week** (50+ over 10+ weeks). She
    runs ~6 days, cross-trains 1-2x, strength 1-2x, and voice-memos
    most runs but not all. The journal is her primary use surface.
    Product UX must handle real volume — pagination, infinite scroll,
    fast search by body part / mood / date range. Editorial typography
    has to read well across hundreds of entries.
- **2026-05-28** · *Wedge sharpened — Maya is a data customer with a
  journaling habit, not a coaching customer.* She isn't looking for
  the AI to coach her. She's looking for an articulate training journal
  + beautiful data viz + an AI analyst she can query on demand. This
  reframes Coach as a consultable analyst, not a daily editor.
- **2026-05-28** · *Coach as analyst, not daily editor (revises
  earlier Coach decisions).* The default Coach tab state is NOT a
  pushed daily editorial paragraph. It's more like an analyst surface
  Maya queries when she wants analysis. The "Ask Coach" interaction
  pattern (compare to last cycle, read through recovery lens, what
  should I watch for) is the *primary* use mode, not the secondary one.
  A brief auto-generated summary may still appear at the top of the
  Coach tab as context, but the main interaction is conversational
  query. This revises the Q15 "Daily Read on app open" and "on demand
  only" decisions toward a clearer model: minimal default surface,
  conversational primary.
- **2026-05-28** · *Coach analytical lens — quality work IS the
  story.* A real coach weights tempos / thresholds / intervals / long
  run workouts more heavily than easy mileage. The AI does the same.
  Fitness gains are read from quality pace trends (MP creeping down,
  LT holding at faster paces), not from raw weekly volume. Default
  tone is good or neutral — most training is just training. Hard is
  the norm. Struggles are SPECIFIC (injury / overtraining / heat /
  recovery deficit), each named with its own signal pattern. Full
  voice principles in `outputs/maya-data-aware-journey-2026-05-28.md`
  section "How the AI reads the journey" (11 numbered principles).
- **2026-05-28** · *Knows-you score: 5-tier framework.* Confidence
  in the AI's understanding of the athlete, separate from any
  specific prediction's confidence. Tiers: 0 Stranger / 1 Sketch / 2
  Familiar / 3 Knows you / 4 Reads you. Rolls up four signal
  dimensions: quantitative coverage, qualitative coverage, pattern
  coverage, life-context coverage. Surfaces on Trends as a tappable
  indicator. Shapes Coach voice register (lower tiers = generic
  summary, higher tiers = cycle comparison + pattern recognition).
  Maya today: tier 3. Reaches tier 4 after the December BQ race.
- **2026-05-28** · *Race report — new feature in brainstorm.* Auto-
  draft + manual finalize hybrid. The deepest analytical surface in
  the product. The shape that emerged:
  - **Primary use case:** reflection — *celebrate, learn, analyze.*
    Sharing is incidental; cold-tier feed is a byproduct.
  - **One tier, sub-categories.** Same template every race; emphasis
    adapts. Sub-categories: Goal / Tune-up / Time trial / Fun run /
    DNF.
  - **Five sections:** Anatomy (data record) · The build (adaptive
    by sub-category) · Execution (honest mechanical read) · Voice
    (verbatim race-week memo pull-quotes, only place AI quotes
    verbatim) · The Read (three labeled sub-sections: Celebrate /
    Learn / Analyze).
  - **Lifecycle states:** SCHEDULED → READY → RAN → REPORTED → LOCKED.
  - **READY state contents** (T-7 days auto-trigger): preview, tips,
    fueling, weather, course, checklist. Race-week operational
    toolkit, not just analytical preview. Differentiator vs. Strava.
  - **DNF / failed race voice posture:** sympathetic + honest.
    *"Sympathetic doesn't mean soft on the analysis. Warm doesn't
    mean dishonest. The hard read delivered with care is the coach
    voice that earns trust."* Same template, Learn leads emphasis,
    no rushing to "next time," Celebrate may still apply to real
    things (smart calls, showing up).
  - **Build section adapts by sub-category:** Goal race = full 16-24
    week arc. Tune-up = recent 4-6 weeks. Informal = last 2 weeks.
    DNF = where things diverged.
  - **Auto + manual mix:** AI does the math and the surface. Maya
    owns the narrative. Anatomy / Execution / Voice / Analyze are
    AI-generated. Celebrate / Learn are AI-drafted and Maya can
    rewrite fully.
  - **IA location:** Coach tab — special surface within. Pinned at
    top when one is fresh/locking. Past reports accessible via "Past
    races" affordance.
  - **System feedback when LOCKED:** new `confirmed_races` entry,
    pace zones recompute (race becomes anchor), fitness range
    adjusts, cold tier block summary written, may level up
    knows-you score.
  - **Voice section curation:** AI auto-selects 2-3 most resonant
    race-week memos. Maya can swap which ones are featured.
  - **Build section is rich — three hero charts:** (1) Volume +
    quality histogram (weekly bars + quality session dots),
    (2) Fitness arc (line chart from cycle start to race day with
    goal/anchor reference lines), (3) Pace × volume snapshots
    (4 miniatures showing training shape evolution). Magazine-feature
    depth.
  - **Pacing plan in READY:** AI proposes 3 options (Conservative /
    Goal / Ambitious). Maya picks one. Her chosen plan carries into
    EXECUTION analysis as the comparison baseline.
  - **Sharable polished image export ships in v1.** Trust signal —
    athletes share races. Polished Anatomy + key Voice quote +
    headline take, suitable for socials.
  - Full feature spec to be written: `outputs/race-report-feature-
    spec-2026-05-28.md` (Task #2).
- **2026-05-28** · *Q26 ANSWERED — three weighting types, not one
  decay curve.* The earlier "time-decay by age" framing was too
  simple. It conflated current capability with career ceiling. The
  correct architecture has THREE weighting types working together:

  **Type 1 — Time-decayed signals (current capability).**
  Recent training predicts current capability. Old training data
  is heavily decayed for prediction purposes because adaptation has
  been re-earned (or lost) many times since.

  | Window | Weight | Purpose | Storage |
  |---|---|---|---|
  | 0-2 months | 1.0 | Current fitness signal | Full-fidelity raw events |
  | 2-6 months | ~0.5 | Recent cycle context | Weekly rollups + key workouts |
  | 6-12 months | ~0.2 | Supporting cycle history | Weekly rollups |
  | 12+ months | ~0.05 | Background only | Block summaries (used for pattern, not prediction) |

  **Type 2 — Sticky facts (ceiling references).**
  These NEVER decay. They are facts about Maya, not predictions of
  her current state:
  - PR table — every race performance, regardless of age (Houston
    3:28 stays a fact forever)
  - Peak weekly mileage ever sustained
  - Peak workouts ever completed (fastest LT, longest run, biggest
    week)
  - Goal history (what she's chased)
  - Cumulative career miles

  Used as **ceiling references**, not as current predictions.
  *"She's been at 52 mpw at peak"* is sticky. *"She was at 52 mpw 18
  months ago therefore she's at 52 mpw now"* is wrong.

  **Type 3 — Pattern accumulation (gets richer over time).**
  These don't decay; they accumulate:
  - Niggle history (right hamstring recurring across cycles)
  - Weather preferences (cool-weather strength, heat struggle)
  - Cycle structure templates (her Houston 14-week build pattern)
  - Mood/effort patterns across builds

  These don't predict current state — they inform the AI's READING
  of current data.

  **The comeback case — why simple decay is wrong.**
  A runner who takes 3 months off and returns can hit PR fitness
  within 3-4 months. Simple time-decay would say her training from 4
  months ago decayed, so she must be at low fitness — but she's back
  at PR. The honest reading: current capability is high (recent
  training is strong), the sticky ceiling says she's been here before
  (so it's not surprising), and the pattern that emerges is "she
  rebuilds quickly when she's built before." Muscle memory is real.
  Architecture must recognize:
  - **Layoffs reduce current capability, not ceiling.**
  - **Comeback to a previously-held level is faster than initial
    build to that level.**
  - **A fitness-range prediction during comeback should reference
    BOTH current trajectory AND personal ceiling.** *"Range 3:35 –
    3:45 right now; trajectory toward 3:28 PR within 8-12 weeks if
    build holds"* is honest. *"Range 3:35 – 3:45"* alone misses
    her ceiling.

  **What this means in practice:**
  - Fitness predictor: combines recent-training signal (Type 1) with
    ceiling check (Type 2 — has she been at this implied fitness
    before?) and comeback-aware pattern recognition (Type 3).
  - Coach Read: surfaces "you've been here before" framing when
    current trajectory is approaching a sticky ceiling.
  - Race anchor: recent race within 12 months → strong current
    signal AND ceiling. Older race → ceiling reference only, doesn't
    anchor current pace zones.

- **2026-05-28** · *Voice register — trust the goal, encourage without
  hype, keep her safe without preaching, help her enjoy the journey.*
  Three registers the AI must not occupy: negative (kicks goals down,
  *"that's unrealistic"*), hype man (*"you got this!"*), or directive
  (*"you should rest"*). The AI lives in the *real coach* register —
  trusts her stated goal without grading its realism, surfaces what
  the data is doing in warm honest language, names challenges
  constructively without catastrophizing, and notices when she's
  enjoying her training (not every observation is about fitness).
  *"You've been smiling in your memos this week"* is a real
  observation worth surfacing. Four sub-principles (trust the goal,
  encourage without hype, keep safe without preaching, enjoy the
  journey) fully spelled out in journey doc voice principle #7.
- **2026-05-28** · *Fitness is multi-signal, not single-number.*
  Mileage alone doesn't measure fitness. The honest fitness picture
  is a fusion of seven signal types (full list in journey doc voice
  principle #13). The fitness predictor must:
  - Read all seven signals together, not just volume + pace anchor
  - Set CONFIDENCE based on signal alignment (all aligned = HIGH
    + tight range; signals in tension = LOW + wide range)
  - Surface signal tension explicitly in observation prose, not just
    in a confidence-tier label
  - Acknowledge that fitness isn't deterministic — race-day execution
    depends on factors not in the data (sleep, hydration, course,
    weather). Race-day predictions should be intentionally wider than
    current-capability predictions.
  This refines Hard Rule #7 (range + confidence): the confidence
  level itself is a multi-signal computation, not a static tier from
  data volume.

---

## Pace zone taxonomy (revised 2026-05-28)

Workouts are labeled by the pace zone they're prescribed at. "Tempo"
and "Threshold" are dropped — they're ambiguous labels for what is
honestly MP / HMP / LT work. The zone IS the prescription.

**Ten pace zones — three effort tiers + seven race-pace zones.**

| Zone | What it is | Maya's pace (3:16 goal anchor) |
|---|---|---|
| Easy | Aerobic, conversational | ~8:30 – 9:00 /mi |
| Moderate | Upper aerobic | ~8:00 – 8:25 /mi |
| Steady | Moderate-aerobic, marathon-prep | ~7:45 – 8:00 /mi |
| **MP** | Marathon pace | 7:28 /mi |
| **HMP** | Half marathon pace | ~7:00 /mi |
| **LT** | 1-hour race pace | ~6:45 /mi |
| **10K** | 10K race pace | ~6:30 /mi |
| **5K** | 5K race pace | ~6:05 /mi |
| **3K** | 3K race pace | ~5:50 /mi |
| **Mile** | Mile race pace | ~5:35 /mi |

Three effort zones (Easy / Moderate / Steady) are aerobic ranges,
shipped as ±5% bands. Seven race-pace zones are precise pace targets
derived from race anchors via `derivePaceTableFromGoal` in
`web/src/components/coach/workout-helpers.ts`.

**Math additions to the canonical seven** (currently Easy / Steady /
MP / LT / 10K / 5K / Mile): add **Moderate** (between Easy and
Steady), **HMP** (between MP and LT), **3K** (between 5K and Mile).
Engineering work in Phase 2.

**Structural labels run alongside the pace zone.** A workout still
has a structure (Long run, Intervals, Continuous, Progression) but the
*pace prescription* is the pace zone. So a workout is labeled as one
of:

- A pure pace zone — `MP 7 mi`, `LT 6 mi`, `5K 5×1km`
- Long run — `Long 18 mi` (usually Easy or Moderate pace)
- Long run workout — `Long 18 mi · 8 @ MP` (long with embedded
  quality zone)
- Race — distance-dependent
- Non-running — Cross-train, Strength, Rest

This collapses the old "Tempo / Threshold / Intervals" structural
labels in favor of the pace zone the work was prescribed at. The
calendar shows the zone label; the journal entry surfaces structure
in the metadata.

---

## Information architecture — IA shift (2026-05-28)

**Tab count drops from 5 to 4.** Plan collapses into Train. Plan is
no longer its own tab; it is a subset of Train.

**New IA: Log · Train · Trends · Coach.**

- **Log** — voice-first front door + 6-month journal pull-down
  (per Q8).
- **Train** — current week, calendar (past + planned), history
  analytics. Plan-using athletes see their coach-issued workouts
  layered into the calendar. Self-planners tap-to-add their own
  future workouts.
- **Trends** — the 5-second view, tappable goal, race-anchored
  fitness, 26-week chart, niggles tile.
- **Coach** — Daily Read, paraphrased observations through the
  goal-and-anchor lens.

Plan-related infrastructure (`activePlan`, plan subscriptions,
reschedule flows, plan parsers) survives at the data layer — coach
plans still exist as a concept — but the standalone Plan tab is gone.

---

## Train tab modes (revised again)

Train has three viewing modes accessible via segmenter:

- **CURRENT** — this week + today's run. Tightest, most current.
  Default view (Q13 decision).
- **CALENDAR** — month view. Past completed workouts auto-populated
  from HealthKit. Self-planned future workouts via tap-to-add. If
  Maya is on a coach-issued plan, those workouts layer in with
  distinct visual treatment (coral left-rule + solid outline) vs.
  her own dashed-outline self-planned ones.
- **HISTORY** — longer-arc analytics: pace × volume distribution
  over 4/8/12/26 week windows, cycle comparison overlays when
  history supports it, fitness arcs.

---

## The shape

Maya is a self-coached endurance runner with a 3:28 marathon PB
chasing a 3:16 BQ off a 40 mpw baseline. She doesn't want the Plan
tab. She wants a training log she actually uses, fitness awareness
rooted in her history, and AI insight that observes her without
prescribing.

The roadmap for Maya is one structural shift and three product layers
on top of it.

---

## The structural shift — from plan-centric to journal-centric

The product today is built around `activePlan`. When `activePlan` is
nil, surfaces don't reframe — they empty out. The Train tab hardcodes
"MARATHON BLOCK" as a fallback label. The week strip says "No active
plan." Block totals are zeros. The whole IA assumes a plan exists.

**Maya's product treats "no plan" as the first-class state, not the
failure mode.**

This isn't a UI tweak. It's a reframing of the architecture:

| Today (plan-centric) | Maya's product (journal-centric) |
|---|---|
| "Week 4 of 16 · Marathon Block" | "Last 7 days" / "This block of training" |
| Block totals (anchored to plan start/end) | Rolling totals (4/8/12 week windows of HER training) |
| WEEK / BLOCK segmenter | CURRENT / HISTORY segmenter (or similar) |
| "No active plan." empty state | "Your training" — never empty |
| Goal line: nil if no plan | Goal line: from `athlete_state.goal_time`, set independently of plan |
| Pace zones from goal time | Pace zones from confirmed race anchor (3:28) |

### Goal-and-fitness principle

Goals are first-class. Fitness is the fallback lens.

- **If a goal is set** (race + target time + race date): every
  observation surfaces *through* the goal lens. "Easy paces are
  creeping down — that's BQ-direction." "Tempo locked in at 7:29 —
  fitness is building toward your goal."
- **If no goal is set**: observations surface *through* current
  fitness without inventing a target. "Easy paces are creeping down."
  "Tempo locked in at 7:29 — fitness is building." Same observations,
  no projected end-state.

The product encourages goal-setting (because the goal lens is sharper)
but never requires it. Goals are stored in `athlete_state.goal_time`
+ `goal_race` + `goal_race_date` independent of any plan subscription.

Goals can be:

- **Race goals** (a specific race + target time + date) — primary case
- **Training goals** (a stated milestone like "first 50-mile week"
  or "consistent 6 days/week through fall") — lighter weight
- **Multiple concurrent goals** — e.g. a 5K tune-up race en route to
  the marathon goal

The system tracks them, surfaces progress against them, and updates
honestly when she changes course.

The shift respects what already exists. `confirmed_races` already
holds her race history. `goal_time` already exists independent of plan
subscription. `athlete_state` already holds derived fitness signals.
The pieces are there; they just need to be reassembled around the
journal instead of around the plan.

---

## Layer 1 — The journal that's actually a journal

The training log is Maya's home. It's not a list of workouts. It's a
6-month diary that reads as a story.

**What she sees:**

- Each day she ran: the workout data (distance, pace, splits) + her
  voice memo's cleaned notes + mood + any niggle mentions
- Each day she didn't run: optionally a one-line note ("rest," "trail
  hike," "lifted") — captured via voice memo or manual entry
- A scrollable, infinitely backwards-scrollable timeline. June. May.
  April. Back to her last race.
- Editorial typography (Post Run Drip voice), not a data table

**What ships today:**

- Voice memo recording, transcription, mood/niggle extraction (Log
  tab) — works
- Manual workout entry — works
- HealthKit auto-sync on launch — works
- `training_logs` table holds the workout data — works
- `voice_logs` (or whichever the actual table is) holds memos — works

**What doesn't ship:**

- A unified diary view. `HistoryView` is a workout list, not a
  journal. Voice memos and workouts are stored separately and don't
  render as one continuous diary.
- No 6-month default lens. Whatever exists today is probably "last N
  workouts" not "since [date]."
- No editorial framing — it's a list, not a story.

**What needs building:**

1. A `TrainingJournalView` (or whatever we call it) that joins
   `training_logs` + voice memo notes + manual entries chronologically
2. A default time window of 6 months back, with infinite scroll for
   anything older
3. Editorial layout per Post Run Drip — each day reads like a diary
   entry, not a row in a table

---

## Layer 2 — Fitness awareness without a plan

Maya needs Train and Trends tabs that work *without* `activePlan`.

### Train tab — reimagined for Maya

**What she sees:**

- Headline: "Your training" (not "No active plan.")
- Current rolling view: this week's volume, pace distribution, mood
  trend across the week
- A segmenter: CURRENT / RECENT / HISTORY (or similar) — not WEEK /
  BLOCK, because Maya isn't in a block
- RECENT view: rolling 4/8/12 week windows — let her see her arc
- HISTORY view: races as anchors, "since your last race" framing,
  pace × volume across the last 6 months

**What's already there:**

- The pace × volume spectrum chart (BLOCK view today) is exactly what
  Maya wants — it's just anchored to plan start/end and needs to be
  re-anchored to a rolling window
- The week strip works for any 7 days, not just plan weeks
- Block totals math is generic — it sums workouts in a date range.
  Replace plan-derived range with rolling window.

**What needs building:**

1. Plan-agnostic Train tab — replaces the plan-centric one when
   `activePlan` is nil (or always, depending on Maya-primary decision)
2. Rolling-window math for block totals
3. New segmenter labels and routing
4. Header rewrites: "TRAINING · WEEK 4 OF 16" → "TRAINING · LAST 4
   WEEKS" or "TRAINING · BUILD TOWARD MARCH 2027"

### Trends tab — make it honest for Maya

**What she sees:**

- VOLUME tile: works as-is (7-day rolling)
- FITNESS tile: race-anchored prediction, range + confidence (e.g.
  "3:18 — 3:24 · MEDIUM CONFIDENCE — building")
- LOAD tile: ACWR works as-is
- NIGGLES tile: works as-is
- FITNESS · 12-WEEK PROGRESSION chart: extend to 26-week (6 months)
  for Maya, with race anchors plotted along the timeline
- LOAD · WEEKLY VOLUME × ACWR chart: works as-is
- GOAL  3:16: shows from `athlete_state.goal_time`, independent of
  plan

**What needs building:**

1. `fitness-predictor` reads from `confirmed_races` (3:28 anchor)
   instead of inferring from training_logs labeled "Race"
2. Pace anchors swap from goal time to race time in
   `paceTableFromProfile`
3. Fitness chart extends to 26 weeks (or longer); race anchors plot
   as vertical markers on the timeline
4. Goal source switches from `activePlan.goalTime` to
   `athlete_state.goal_time`

---

## Layer 3 — AI insight on her journal

The Coach Read tab is the AI's daily observation of where Maya is.
Today it works without a plan — keep that. Make it journal-aware and
voice-disciplined.

**What she sees:**

- The Daily Read, editorial format (already exists)
- Observations that reference what she actually said in her voice
  memos this week
- Observations that triangulate current paces against her 3:28 anchor
  and toward her 3:16 goal — without ever explaining the math
- Pattern recognition across her journal (e.g. "third easy run this
  week where you mentioned feeling sluggish")

**Voice principle (from product-state doc, section 1a):**

The AI carries Maya's anchors silently and surfaces observations about
her current state. The 3:28 PB and 3:16 goal are infrastructure, not
talking points. The Coach Read should sound like:

- *"Easy paces are creeping down — 8:35 last week, 8:22 this week.
  That's BQ-direction. Volume's holding at 42 — solid."*

Not like:

- *"Based on your 3:28 PB and your 3:16 goal of a 12-minute PR, you
  need to..."*

**What's already there:**

- `coaching-daily-read` edge function (the Coach Read source)
- `process-training-memo` extracts mood, cleaned notes, niggles from
  voice memos
- `evaluate-coachable-moment` runs rules
- 4 coachable-moment rules in `_shared/rules/`

**What needs building:**

1. Race-history-aware coachable-moment rules (Phase 2 covers some of
   this)
2. Prompt-design pass on `coaching-daily-read` to enforce the voice
   principle — anchors silent, observations explicit
3. Eval harness coverage for "math-explaining" violations (new
   pattern group: `MATH_EXPLAINING_BANS`)
4. Journal-pattern rules — across 7+ days of voice memos, observe
   recurring patterns (mood, niggles, run quality)

---

## What gets cut or deprioritized for Maya

The product currently builds a lot of surface area Maya doesn't use.
Honest list of what's lower priority if Maya is the wedge:

- **Plan tab** — not deleted (other personas may use it), but no
  longer the primary surface. Maya can ignore it.
- **Web coach-portal** — irrelevant for Maya. Don't deepen unless
  dyad-persona work justifies it.
- **`isCoachMode` toggle and CoachTabView** — irrelevant for Maya.
- **`reschedule-plan`** — only matters if Maya is on a plan, which
  she isn't.
- **`adapt-plan`, `shift-day`, `subscribe-to-plan`** — same.
- **`generate-training-plan`, `parse-*` plan parsers** — same.
- **`weekly-plan-review`** — only matters with a plan.

Roughly 1/3 of the edge functions and a significant chunk of the iOS
Training/ folder is plan-machinery. None of it gets deleted (other
personas may use it; cutting it is a separate decision). It just
stops being where new investment goes.

---

## Sequencing — Maya's roadmap as phases

**Phase 1 — Eval harness coverage** *(weeks, in progress)*
Already documented in the product-state doc. Safety net for any AI
behavior change downstream. Add `MATH_EXPLAINING_BANS` pattern group
to catch preachy voice.

**Phase 2 — Race anchoring** *(~1 week, mostly wire-up)*
`outputs/race-performances-feature-plan.md` already exists. Add
race-import onboarding question, plumb `confirmed_races` through
`paceTableFromProfile`, `fitness-predictor`, and at least one
coachable-moment rule. End state: Maya's 3:28 PB anchors her pace
zones and her fitness prediction.

**Phase 3 — Untether the Train tab from `activePlan`** *(weeks)*
THE big new phase. Make Train work without a plan. Replace plan-
centric framing with journal-centric framing. Rolling-window math.
New segmenter. New header text. End state: Maya opens Train and sees
her own training, not a "No active plan" empty state.

**Phase 4 — The training journal surface** *(weeks, design first)*
Build the 6-month diary view. Unified chronological timeline of
workouts + voice memos + manual entries. Editorial layout. End state:
Maya opens the app, sees her training arc, and feels the through-line.

**Phase 5 — Profile table cleanup** *(~4 dev days)*
`outputs/profile-table-audit-2026-05-22.md`. Foundation for clean
data layer. Can run in parallel with Phase 3/4 since it doesn't
touch UI.

**Phase 6 — Memory architecture (hot/warm/cold)** *(multi-week)*
The 3-tier data architecture. Cold tier holds Maya's race history and
prior-build summaries up to 2 years back. Enables "compared to your
last build" observations.

**Phase 7 — Voice-disciplined Coach Read** *(weeks, prompt work)*
Refactor `coaching-daily-read` prompts to enforce the voice principle.
Eval coverage for math-explaining and goal-restating bans. Journal-
pattern rules.

**Phase 8 — Production-readiness** *(parallel)*
CI, prod-mode Supabase, landing page, legal. Required for real
athletes regardless of persona.

### Coach client unification (was Phase 4 in product-state doc)

Deprioritized if Maya is primary. Phase 4 in the product-state doc is
about picking the canonical coach surface. If Maya is the wedge,
coach surfaces aren't load-bearing and this phase moves to later
(maybe Phase 9 or further).

---

## Phase dependencies (visual)

```
Phase 1 (eval harness) ──┬─→ Phase 2 (race anchoring) ──┐
                         │                                ↓
                         │                              Phase 3 (untether Train) ──┐
                         │                                                          ↓
                         └─→ Phase 7 (voice Coach Read)                            Phase 4 (journal)
                                                                                    ↑
Phase 5 (profile cleanup) ──→ Phase 6 (memory architecture) ───────────────────────┘

Phase 8 (production-readiness) — parallel to everything
```

Phase 1 blocks 2 and 7 (both touch AI behavior).
Phase 2 blocks 3 (rolling math depends on race anchors making sense).
Phase 3 blocks 4 (journal view inherits the new framing).
Phase 6 blocks 4 (cold-tier race history enables full journal depth).

---

## What success looks like — Maya's six-month story

Six months from today, if this roadmap ships, here's what Maya
experiences:

She opens the app. Log tab is her front door. She taps the voice
memo button after every run. Some days she types instead. HealthKit
fills in the workout data automatically.

She swipes to Trends. The FITNESS tile reads *"3:18 — 3:24 · MEDIUM
CONFIDENCE — building."* The 26-week chart shows her arc from May
through October, with her 3:28 anchor marked at the start. Volume's
been climbing 38 → 42 → 45 → 48. The line bends upward.

She swipes to Train. It says *"TRAINING · LAST 4 WEEKS."* It shows
this week's volume, her pace × volume distribution, her tempo work
locking in faster than last month. She can swipe back through 4 / 8 /
12 / 26 week windows. There is no "No active plan" anywhere.

She swipes to Coach. The Daily Read says *"Easy paces are creeping
down — 8:35 four weeks ago, 8:18 this week. That's BQ-direction.
Long run hit 18 on Saturday — your longest since the 3:28 build.
Right hamstring still showing up in voice memos every Tuesday."*

She scrolls down to her journal. Six months of her own training,
voice memos, mood, niggles — rendered as a real diary, not a workout
list. She can scroll back to her 3:28 race and read what she said
the morning after.

That's the product. The plan tab still exists for runners who want
it. Maya never opens it.

---

## Open questions specific to Maya

Organized by category. Each question is something only Rio can
decide. Log decisions in the Decisions Log above as they're made.

### Onboarding & first run

- **Q1.** What's Maya's first 60 seconds in the app? Does she sign in
  and land on an empty journal with a "record your first run"
  prompt? Or a goal-setting flow? Or a race-import flow?
- **Q2.** How do we handle the back-fill? Maya has 2 years of runs in
  HealthKit. Do we suck them all in on first launch and render a
  pre-populated 2-year journal? Or do we start fresh from her sign-up
  date and let her opt into back-fill?
- **Q3.** Does Maya need to set a goal during onboarding, or can she
  defer? If she defers, what does the product say about her fitness
  without a goal?

### Goal-setting UX

- **Q4.** Where does Maya enter her 3:16 goal? Settings? A dedicated
  "goals" screen? Inline on Trends? Coach Read?
- **Q5.** Can she set multiple goals at once (5K tune-up + marathon
  goal)? Or one at a time?
- **Q6.** How does the product handle a goal change mid-build? She
  set 3:16, then realizes 3:20 is more honest. What persists, what
  recomputes?
- **Q7.** Training goals vs race goals — do we surface them
  differently, or treat them as one concept with different shapes?

### Journal mechanics

- **Q8.** Does the journal ship as a separate tab ("Journal") or as
  the default view when she pulls down on Log?
- **Q9.** What counts as a journal entry? Run + voice memo, sure.
  What about cross-training (gym, bike, hike)? Rest day with a one-
  line note? Days she didn't open the app at all?
- **Q10.** Does the AI ever *annotate* her journal entries, or are
  they pure record? E.g. does it surface "you said your hamstring was
  tight 3 of the last 4 Tuesdays" inline, or only on Coach Read?
- **Q11.** Default time window: 6 months? 1 year? Since last race?
  And does she pick the window or does the product pick it
  contextually?

### Train tab reimagined

- **Q12.** Does the new plan-agnostic Train tab replace
  `TrainingTabView` for everyone, or does it activate only when
  `activePlan == nil`?
- **Q13.** What's the right rolling window for "current view" — last
  7 days, last 4 weeks, since last race? Does she pick or do we?
- **Q14.** "Compared to last cycle" framing — is it automatic if her
  history supports it, or opt-in? E.g. "Last cycle at this point
  you were at 35 mpw" — is that always there, or only when she asks?

### Coach Read & AI behavior

- **Q15.** Does Maya get a Daily Read every day, or only on run days,
  or when she opens the app, or all of the above? Cost vs. signal.
- **Q16.** Does Coach Read reference her *voice memos* by quoting them
  back, or just paraphrase the patterns it found?
- **Q17.** Coachable moments for self-coached Maya — does she see them
  surfaced to her directly? Or only when there's a coach in the loop?
  The wedge says AI advises never acts; surfacing moments to a runner
  who'll act on them is closer to prescription.

### Race history

- **Q18.** Manual race-entry UX — where does she add her 3:28? Edit
  after the fact, delete a wrongly-imported race — all UX calls.
- **Q19.** Does the system attempt to auto-detect races from HealthKit
  back-fill (workouts tagged "Race," or workouts on known race dates),
  or is it always manual confirmation?
- **Q20.** What about non-marathon races as anchors? 5K, 10K, half
  — do they carry the same weight, or does marathon trump? Race-
  equivalence math already exists; question is presentation.

### Niggles in Maya's surface

- **Q21.** Niggles today are designed for a coach to act on. What does
  the niggle surface look like for self-coached Maya? Same closed
  vocabulary, same verbatim quoting — but who acts on the surfacing?
- **Q22.** Does the AI ever *connect* niggles to training load (e.g.
  "right hamstring mentions cluster on Tuesdays — that's tempo day"),
  or is that overstepping into diagnosis?

### Non-running data

- **Q23.** Strength sessions, cross-training, hikes — does Maya log
  them in the journal? Does HealthKit pull them in? Does the AI
  factor them into ACWR / fitness / recovery?
- **Q24.** Sleep, HRV, body-weight from HealthKit — are these part of
  Maya's surface, or do we wait for the v1.5 recovery pillar?

### Cold tier / memory architecture

- **Q25.** Block summarization for cold tier — Maya's 3:28 marathon
  two years ago. What does a "block summary" record contain? Just
  date and finish time? Or weekly mileage averages, peak weeks,
  anchor workouts? What enables the "last cycle at this point you
  were at 35 mpw" observation?
- **Q26.** Decay weighting — how stale is too stale? A 1:32 half six
  weeks ago is gold. A 3:28 marathon two years ago is an anchor but
  shouldn't dominate fitness prediction. Question is the math.

### Data ownership

- **Q27.** Can Maya export her full journal (workouts + voice memos +
  notes) on demand? Required for trust at v1, or v2?
- **Q28.** What's the offline behavior? Maya records a voice memo on a
  trail run with no signal. Does it queue and process when she's back
  online? Today the Log tab assumes connectivity.

---

## Open questions remaining

Most of the v1 product design is now decided. What's still open:

- ~~**Q26** — Decay weighting math for race anchors.~~ **ANSWERED
  2026-05-28** — three temporal windows with recency-dominant
  weighting (0-2 months = current; 2-12 months = recent; 12+ months
  = career/identity). See decisions log above.
- **Q23 sub-question** — Should cross-training surface as a separate
  "total active hours" or "cardio load" metric? Out of v1; flagged
  for future.
- **The wedge call** (section 1 of product-state doc) — promote
  Maya to primary persona, broaden the wedge, or keep dyad primary.
  Still deliberately left open.

That's it for product design. The next ~6 weeks of work moves into
implementation: Phase 1 (eval harness coverage) is already in flight;
Phase 2 (race anchoring) is next; Phase 3 (untether Train) and Phase
4 (journal surface) follow.

# The Read — redesign plan

**Date:** 2026-06-13 (revised same day after the coaching-direction review)
**Owner:** Rio
**Status:** Draft for planning (Fable)
**One-liner:** Turn the daily Read from an AI paragraph that restates your
stats into a coach's read of your *training arc* — intensity-aware load,
hard/easy balance, fitness, and how you're actually holding up — built on
months and years of history, not the last two weeks, with a coach you can
talk back to.

---

## 0. What changed in this revision

The first draft was right that the Read sounds like AI and restates stats.
But two things reframe the work:

1. **A diagnostic pass on "the Read is erroring" found the bigger problem
   isn't the prompt — it's that the data feeding the Read is stale.** The
   async enrichment pipeline (voice processing, coach insights, coachable
   moments) has been **403-dead since June 11**. See §9. No prompt rewrite
   fixes a Read that's reading two-week-old, half-processed data.
2. **The coaching direction sharpened.** Get off ACWR as the headline load
   metric. Show an *intensity-weighted training load* that fuses pace and
   volume — a mile at 5K effort costs the body more than an easy mile, and
   the number should say so. Show whether hard days are hard, easy days are
   easy, and recovery is actually happening. Read voice memos for
   wear-and-tear signal (struggling, fatigue, high HR, knee pain) and act on
   it. And **stop thinking in 14-day windows** — a coach reads 2–3 months of
   recent training, 6–12 months of pattern, and 2–3 years of who-this-runner-
   is. The product already tries to build that long memory (`athlete_state`,
   profiles); the Read should use it.

The happy surprise from the code read: **most of the load engine the new
direction wants already exists.** It's just buried as plumbing for ACWR
instead of being the thing we show. See §4.

## 1. Why this rewrite

The current Read is a once-a-day paragraph. Problems, all confirmed in
code/data today:

- **It sounds like AI, not a runner.** It narrates ("volume settled around
  44.7 miles, monitor those knees") instead of observing like someone who's
  watched your training for a year. Generic register, no point of view.
- **It restates what you already know.** No *trends*, no real *fitness
  evaluation*, and it forgets qualitative signal fast (voice memos capped at
  14 days).
- **It thinks in weeks when a coach thinks in cycles.** Training-log context
  is ~60 days; the chronic-load baseline is 4 weeks; voice memory is 14 days.
  None of that is long enough to see a build, a plateau, a recurring niggle,
  or a year-over-year fitness gain.
- **Its headline health metric is a ratio nobody asked for.** ACWR is shown
  (or half-shown — see §9) as the load story. It's an injury-risk ratio, not
  a coach's read of whether the work is right.

What's worth keeping: the data substrate is strong, and **the intensity-
weighted load math is already written** (§4). The raw material for a great
read exists; the product layer on top of it is thin and the pipeline that
feeds it is currently broken.

## 2. What this product is

A **coach's read of your training arc**: analytical *and* observational. It
answers, in plain coach language:

1. **What's the work been?** Intensity-weighted load and how it's trending
   over weeks and months — not a ratio, a story. Are you building, holding,
   spiking, or backing off?
2. **Is the work balanced?** Hard/easy distribution and whether recovery is
   landing. Are the easy days easy enough, the hard days hard enough, and is
   the body getting the down it needs.
3. **How's my fitness?** Where it is and where it's trending, anchored to
   race history and goal — a range with confidence, never false precision.
4. **How am I actually holding up?** The qualitative read — voice memos and
   mood fused with the numbers, including wear-and-tear signal surfaced
   early.
5. **So what?** A light, optional recommendation when something genuinely
   warrants it — and a way to ask "why?" and go deeper.

Design principle carried from the existing product, unchanged: **AI observes
and advises, never prescribes or diagnoses.** Niggles are surfaced verbatim,
never diagnosed. Recommendations are soft; the athlete (or coach) owns the
call.

## 3. The experience

### 3.1 The Read (the daily surface)

Restructured from "one paragraph" into a short, scannable read with a spine:

- **Headline** — names the story of the arc, not a slogan. ("Three weeks of
  building, and your easy pace is holding — the body's absorbing it." not
  "Volume dip, monitor knee.")
- **Load & balance (the new analytical heart)** — intensity-weighted load
  trend over weeks/months, with the hard/easy split and a recovery read.
  *"Load's up ~18% over three weeks, driven by the threshold work, not
  mileage. Easy days are genuinely easy (82% of volume). One more build week
  looks supportable; the down week after matters."*
- **Trends (2–3)** — each one line, grounded in a specific number *and its
  change over a real window*: *"Easy pace: 7:35 → 7:24/mi over 3 weeks while
  readiness slid 6→4."* This is what makes it read as analysis, not
  narration.
- **Fitness** — race-anchored evaluation with range + confidence: *"~1:11–
  1:13 half off your current block; 4 quality sessions and a recent 10K
  behind it,"* with trajectory vs. last cycle and vs. goal.
- **The human read** — a short observation fusing voice-memo sentiment and
  wear-and-tear signal with the data: *"You've logged 'tired' three of the
  last five runs and mentioned the right knee twice this week — that lines up
  with the load jump. Worth watching, not a red flag yet."*
- **One call, if earned** — optional. A push/pull for today, a flag to watch,
  or a question. Skipped when there's nothing honest to say.
- **What I can't see** — the honesty block (missing sleep, a one-data-point
  niggle, thin fitness evidence). The single biggest trust-builder.

### 3.2 Trends & analysis engine (new, deterministic)

The thing that's missing. A computed layer that runs *before* the model and
detects the handful of movements worth mentioning, each with magnitude,
direction, and **window** — and windows are deliberately multi-scale (§5):

- Intensity-weighted load trajectory (the ACWR replacement — §4): direction
  and rate over 3–4 weeks *and* over 2–3 months.
- Hard/easy distribution and whether it's drifting (intensity creep is a
  classic overreaching tell).
- Recovery adequacy: spacing of hard days, down-week cadence, readiness/mood
  after load.
- Pace drift by zone (easy-pace creep especially).
- Mood and readiness arcs over weeks.
- Niggle recurrence and clustering (from `body_mentions`), across months.
- Execution vs. plan (did quality sessions hit their zones).
- Fitness trajectory vs. race anchors, cycle-over-cycle.

The model *writes* these up; it doesn't *find* them. That's what keeps it
accurate and stops it sounding like it's guessing. Build on the existing
`patterns` and `load_distribution` satellites — extend, don't restart.

### 3.3 Fitness evaluation

Race-anchored (existing decision: `confirmed_races` > goal time). Always
range + confidence, rounded to whole minutes. Trajectory framing
("building / holding / sharpening / detraining") with the reason. Compare to
last cycle, and where the history supports it, year-over-year.

### 3.4 Qualitative fusion + wear-and-tear detection

This is where the "keep them on track" ask lives.

- **Widen memo memory far past 14 days** (§5). Either lift the lookback to a
  rolling 60–90 days or — better at scale — keep a rolling memo summary in
  `memories`/`patterns` so older sentiment survives without bloating the
  prompt.
- **Treat mood/feeling as a first-class trend**, correlated against load
  (the "tired + load spike" link above).
- **Surface wear-and-tear signal early.** Voice memos and metrics carry tells
  the Read should catch and elevate: explicit fatigue or struggle language,
  body-part mentions (knees, shins, achilles…), and physiological flags like
  elevated resting/working HR for a given pace. The classifier extracts;
  the Read elevates the *pattern* (recurrence, clustering, co-occurrence with
  a load jump) — never a diagnosis. Niggles stay in the athlete's own words.
  This is detection-not-diagnosis, exactly as the niggles spec already
  requires.

### 3.5 The coach chat (two-way)

The back-and-forth. On top of the daily read the athlete can ask:

- "Why do you think my easy pace is creeping?"
- "How does this block compare to last winter?"
- "Should I move tomorrow's session?"

The `coaching-agent` edge function is the home for this. It reads the same
athlete state + trends, holds the read as context, and answers in the same
voice. Recommendations live here more than in the daily read. Same
guardrails: advises, never prescribes; defers medical calls.

### 3.6 Voice fix (sounds like a coach, not a chatbot)

Mostly structure + grounding, not just the model:

- **Lead with an observation, never a stat restatement.** First sentence is a
  point of view.
- **Every claim cites a number *and a change over a stated window.*** This is
  also what forces the long-window thinking into the prose.
- **Keep the banned-AI-speak list**; add concrete good-vs-bad exemplars so
  the model has a target, not just prohibitions.
- **Consider gemini-2.5-pro for this one call.** Flash is fine for templated
  writing but weaker at nuanced judgment and dense-constraint adherence; pro
  reads more like a person. One-line router change; evaluate on real output.
  (Note: flash's "thinking" tokens are also what caused the 502 — see §9.1 —
  so a model change interacts with the token budget; test together.)
- **Brevity is voice.** A shorter, sharper read beats a complete one.

## 4. Training load — replacing ACWR (the model)

**The headline decision: retire ACWR as the surfaced metric, keep and
promote the intensity-weighted load it was already built on.**

### 4.1 What already exists (reuse, don't rebuild)

`_shared/weeklyAnalytics.ts` already computes exactly the weighted score the
new direction describes:

- **`weightedLoad`** — load in "weighted minutes" = `intensity_score ×
  duration`. `intensity_score` is the time-weighted average of per-segment
  pace weights (`mile 5.0 · 5k 4.0 · 10k 3.5 · threshold 3.0 · mp 2.5 ·
  easy 1.0`), computed per workout by `compute-workout-features`. A 10×400m
  at mile pace earns ~5× the load per minute of an easy run. **This is "a
  mile at 5K pace is harder than an easy mile," already in code.**
- A **fallback** (`workout_type × duration`) when features aren't computed.
- ACWR is then *just a ratio* on top: acute (this week's `weightedLoad`) ÷
  chronic (EWMA of the prior 4 weeks, weighted 4·3·2·1).

So "getting off ACWR" is not throwing away the engine — it's **stopping
showing the ratio** and showing the load and its trend instead.

### 4.2 What changes

- **Surface `weightedLoad` and its trajectory** as the primary load story:
  this week and the rolling multi-week/multi-month trend, in plain language
  ("building / holding / spiking / backing off"), not a unitless ratio.
- **Show the hard/easy distribution** as a first-class read: share of
  weighted load (and of volume) in easy vs. quality, against the ~80/20
  guide. (The `dataAnalysis.ts` "only X% easy — should be ~80%" assessment is
  the seed; promote it.)
- **Add a recovery read**: hard-day spacing, down-week cadence, and
  readiness/mood response to load. This is what "recovering well" means in
  the brief.
- **Demote ACWR to an internal injury-risk input.** It can still feed
  injury/coachable-moment logic behind the scenes; it just isn't the number
  the athlete sees. (Per §9.2 it's currently *half*-removed — finish the
  job.)

### 4.3 The formula — conceptual, with options to validate

Principle: **load = volume × intensity, accumulated, with recent work
weighted more heavily, and read at multiple time scales.** The per-workout
weighted-minutes score above is the atom. Open question is how to express
"too much / just right / too little" without the ACWR ratio. Candidates:

- **(A) Banister-style acute vs. chronic, but shown as a trend, not a
  ratio.** Keep the EWMA chronic baseline; surface "load is N% above/below
  your month's norm and rising/falling," never the bare number. Lowest
  lift — it's the existing math, re-narrated. Lengthen chronic from 4 weeks
  toward 6–8 to match the coaching-window ask.
- **(B) Fitness–Fatigue (two EWMAs).** Model a fast "fatigue" decay and a
  slow "fitness" decay from the same weighted-load series; "form" = fitness −
  fatigue. Richer ("you're fit but carrying fatigue — the down week converts
  it"), maps cleanly to taper logic, more to tune/validate, needs the longer
  history we're already committing to.
- **(C) Zone-time distribution + monotony/strain (Foster).** Lead with the
  hard/easy mix and weekly monotony/strain rather than any single load index.
  Closest to the brief's "hard days hard, easy days easy, recover well"
  framing; pairs well with (A) or (B) rather than replacing them.

Recommendation to validate, not to commit blind: **(A) for the headline load
trend now** (reuses code, ships fast), **(C) for the balance/recovery read**
(directly answers the brief), and **pilot (B)** as the fitness/taper engine
in the §5-Next phase once long-window data is reliably populated. Whatever we
pick ships behind the eval harness (hard rule #3) and shows range/confidence,
not false precision.

## 5. Time windows — think in cycles, not fortnights

The current windows are too short everywhere. Targets, by purpose:

| Read element | Now | Target |
|---|---|---|
| Recent training detail | ~60 days logs | Keep ~60–90 days as the detail layer |
| Load trend / "acute vs norm" | 4-week chronic | 8–12 weeks (2–3 months) |
| Pattern detection (niggles, mood, pace drift, consistency) | n/a / 14d memo | 6–12 months |
| Who-this-runner-is (baselines, race history, year-over-year) | thin | 2–3 years via athlete profile |
| Voice-memo qualitative memory | 14 days (hard cap) | 60–90 days raw, older via rolling summary |

Mechanism: the daily prompt can't hold years of raw logs, so the long
windows live in **pre-computed summaries** (athlete state + profiles +
rolling memo/pattern summaries). Deterministic code rolls the history into
compact trend/pattern objects; the Read consumes those, not the raw years.
This is the only way to "know the runner" without blowing the context budget.

## 6. Athlete profiles — the long memory

The 2–3-year "know the runner" layer the brief calls for already has scaffolding:
`athlete_state` + its v2 satellites, `build-athlete-profile` /
`build-pace-profile`, `fitness_snapshots`, and `confirmed_races`. The
redesign leans on these as the durable memory and asks three things of them:

- **Persisted long-window rollups.** Per-month load, volume, hard/easy mix,
  and fitness markers retained for years, so cycle-over-cycle and
  year-over-year comparisons are cheap lookups, not recomputation.
- **A rolling qualitative summary** (in `memories`/`patterns`) so sentiment
  and niggle history survive past the raw-memo window.
- **Race-anchored fitness baselines** carried silently and used for the
  fitness range.

Caveat to confront, not paper over: per CLAUDE.md the `user_profiles` table
**doesn't exist in production** (quarantined migration), and the athlete-state
file (`_shared/athlete-state.ts`, ~1481 LOC) has known P0 bugs and a pending
refactor blocked on eval coverage. The long-memory ambition depends on that
substrate being real and correct. **This is a dependency, not a footnote** —
sequence it into the phasing (§7) honestly.

## 7. Architecture (build vs. reuse)

| Layer | Status | Plan |
|---|---|---|
| Per-workout weighted load (`weightedLoad`, `intensity_score`) | **shipped** | Reuse as-is. Promote from ACWR-input to surfaced metric. |
| Athlete state + v2 satellites | shipped (with known bugs) | Reuse; fold in long-window rollups. Depends on the refactor. |
| Trends engine | **missing** | Build: deterministic detection feeding read + chat, multi-scale windows. |
| Load presentation (trend, hard/easy, recovery) | **missing** | Build on the existing weighted-load math. |
| ACWR ratio surfacing | half-removed | Finish demoting to internal injury input. |
| Daily read prompt (v3 → v4) | v3 live | Restructure to §3.1 spine; voice exemplars; window-aware claims. |
| Fitness evaluation | partial | Wire race-anchor + range/confidence + cycle comparison everywhere. |
| Qualitative memory | thin (14d) | Widen to 60–90d + rolling summary. |
| Wear-and-tear signal | partial (niggles, injury fn) | Elevate pattern-level signal into the read; never diagnose. |
| Coach chat | `coaching-agent` exists | Make it the conversation surface; share read context. |
| Async enrichment pipeline | **403-dead (§9)** | **Fix first.** Nothing downstream is real until this drains. |
| Model | flash | A/B flash vs pro for read + chat; mind the thinking-token budget. |

Division of labor, unchanged: **deterministic code computes; the model
writes.** That's what keeps it honest.

## 8. Phasing

**Phase 0 — unbreak the inputs (do this first, it's cheap)**
- Recover the 403 enrichment pipeline (§9.2); confirm the queues drain and
  voice memos are producing `cleaned_notes` again.
- Finish removing ACWR from the surfaced summary (§9.2).

**Phase 1 — make the daily read genuinely good**
- Promote weighted-load: trend + hard/easy + recovery read (load model
  option A + C). Retire the ACWR ratio from the UI.
- Ship the trends engine (even 3 trend types: load trajectory, pace-drift,
  mood arc) with multi-scale windows.
- Restructure the read into the §3.1 spine; add voice exemplars; decide flash
  vs pro.
- Widen qualitative memory beyond 14 days; elevate wear-and-tear signal.

**Phase 2 — fitness + conversation + long memory**
- Race-anchored fitness with range/confidence and cycle comparison; pilot the
  Fitness–Fatigue model (option B) once long-window data is reliable.
- Persisted long-window rollups in athlete profiles (depends on the
  athlete-state refactor + `user_profiles` resolution).
- Ship the coach chat on `coaching-agent` with read context and soft
  recommendations.

**Phase 3 — depth**
- "Lenses": ask the read to re-examine through a chosen frame (last cycle, a
  specific niggle, a target race).
- Proactive nudges (coachable moments) surfaced into the read when a pattern
  crosses a threshold.

## 9. Errors found today (the "the Read is erroring" investigation)

Two distinct issues. The one in the original draft's footnote is the smaller
one.

### 9.1 The 502 — fixed and holding

Root cause was real: `gemini-2.5-flash` spends "thinking" tokens out of the
same `maxOutputTokens` budget, so a 2000-token cap left the JSON truncated
mid-string ("Unterminated string in JSON") → parse failed three times → 502.
`coaching-daily-read/index.ts` now hardcodes `maxOutputTokens: 8000` and the
deployed version returns 200 in live logs. **Resolved.**

One latent footgun: the router's `getModelConfig("complex")` still returns
`maxTokens: 2000`, and the function ignores it by hardcoding 8000 inline.
Anyone who "tidies" the function to use the router value reintroduces the bug.
Reconcile the two (raise the router's complex cap, or comment the override
loudly). This also interacts with any flash→pro switch (§3.6).

### 9.2 The real, active problem — the enrichment pipeline is 403-dead

**All three background drains** — `drain-voice-processing-jobs`,
`drain-coach-insight-jobs`, `drain-coachable-moment-jobs` — return **403 on
every minute tick**, and have since **June 11**. Confirmed downstream:
`coach_insight_jobs` has 12 jobs stuck `queued`, oldest 2026-06-11 23:09 —
~2 days with nothing processed.

Why it matters for the Read: these drains turn raw voice memos into
`cleaned_notes`, generate coach insights, and produce coachable moments.
While they're dead, **the Read renders fine (200) but on starving data** —
stale/missing qualitative signal, no fresh patterns. A real chunk of the
"restates stats, forgets feeling" complaint is this, not the prompt.

Root cause (verified, not inferred):

- The drain functions authenticate by *exact string match* of the incoming
  Bearer token against their `SUPABASE_SERVICE_ROLE_KEY` env var
  (`constantTimeEq(token, supabaseServiceKey)`).
- The June 11 migration correctly switched the crons to read the key from
  Vault at runtime, and that **is** live (all three crons show
  `uses_runtime_vault = true`).
- But the Vault `service_role_key` is a **legacy JWT** (`eyJ…`, 219 chars),
  while the functions' env key has rotated (the new `sb_secret_*` format).
  Vault value ≠ env value → 403. The migration itself predicted this: "if the
  drains still 403 after this lands, the Vault value itself is stale."
- Contrast: `rebuild-athlete-state` was fixed the *robust* way —
  `verify_jwt = true` + validating the JWT `role` claim instead of
  exact-string match — and returns 200. The drains still use the brittle
  exact-match pattern.

Fixes:

- **Quick (chosen, do now):** update the Vault `service_role_key` secret to
  the functions' current service-role key. Next tick recovers, no redeploy.
  *Blocker:* the current key value isn't readable through the available
  tooling (it's a function secret), so this needs the value pasted in or set
  from Dashboard → Settings → API.
- **Robust (follow-up):** port all three drains to `rebuild-athlete-state`'s
  role-claim auth so a future key rotation never kills the pipeline again.

### 9.3 Other known issues to fold in

- ACWR is hidden from the Read but still computed and concatenated into
  `recent_training_summary` (~line 964 of the prior surface) — finish
  removing as part of §4.2.
- `user_profiles` doesn't exist in production; athlete-state refactor is
  pending and blocks the long-memory work (§6).

## 10. Success — is it useful?

The honest test: *would Rio open this every day?* Proxies:
- The read names at least one thing the athlete *didn't* already know (a trend
  surfaced before it was obvious — the kind only a months-long window sees).
- The load read changes behavior: a build week gets trusted, a spike gets
  respected.
- Recommendations, when given, get acted on or deliberately dismissed — not
  ignored.
- Chat gets used (questions per week).
- Voice passes the "a runner wrote this" gut check in blind review.

## 11. Open questions

- Daily auto-generate, or on-demand only? (Auto risks staleness — and right
  now staleness is literal; see §9.2.)
- Which load expression for the headline — (A) re-narrated acute/chronic now,
  (B) Fitness–Fatigue later, (C) distribution-led? (§4.3)
- How long is the chronic/normalization window once we lengthen it — 8 weeks?
  12? Does it adapt to where the athlete is in a cycle?
- How assertive should recommendations be for a self-coached athlete vs. a
  coached one?
- How far back should *raw* qualitative memory reach before the rolling
  summary takes over — 60 or 90 days?
- Rename "The Read"? Strong name if the content earns it.

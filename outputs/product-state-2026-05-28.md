# Post Run Drip — Product State

**Last updated:** 2026-05-28
**Status:** Living doc. Read at the start of every session. Update at the end.
**Audience:** Rio. Anyone Rio shows it to.

---

## 1. The wedge

Post Run Drip is a coach's nervous system for endurance athletes. It fuses
two streams that nobody fuses today: the quantitative training data
(mileage, pace, ACWR, fitness curves) and the qualitative voice-log
signal (how the run felt, mood, niggles, fatigue). Those streams flow
into actionable **coachable moments** that human coaches act on.

The product is not an AI replacement for coaches. It's force-multiplier
infrastructure for the coach–athlete relationship.

Three things make this defensible:

- **AI advises, never acts.** Coaches own decisions. The AI surfaces
  signal and routes the call back to the human.
- **Detection beats diagnosis.** When an athlete says their adductor is
  tight, we report exactly that — verbatim, in their own words. We do
  not name the injury, prescribe action, or assess severity.
- **History is the foundation, not the goal time.** What an athlete has
  *actually done* (races, weekly mileage, time at paces) is more
  trustworthy than what they aspire to. The system anchors fitness on
  proven performance, validates it with current training, and uses goal
  time only as direction.

### Wedge note — May 2026

The "coach–athlete dyad as wedge" framing is being broadened. Maya (see
section 1a) is a self-coached athlete with no plan tab and no human
coach in the loop — and she's a first-class persona. The product still
respects the dyad when a coach is present; it just no longer requires
one. *Open question, see section 6: keep "dyad" as the primary wedge
and Maya as a secondary persona, or promote the journaling-athlete
wedge to primary?*

---

## 1a. Canonical athletes

Real personas. Code and design decisions get tested against them.
Until you can write a clean sentence about how a feature serves a
specific named persona, the feature isn't doing what you think it is.

### Maya — the journaling athlete (primary persona, May 2026)

**Who she is.** A self-coached endurance runner. Has been running
seriously for years. Reads training books. Has opinions about pace
zones. Doesn't want to be told what to run; wants to *understand what
she's running* and *see her fitness building*.

**The numbers that anchor her.**

- **Marathon PB: 3:28** (her last marathon)
- **Goal: 3:16 — Boston qualifier** (12 minutes faster than her PB —
  ambitious but not unrealistic for a serious runner with a good build)
- **Training volume baseline: ~40 mpw** averaged across the 10–12
  weeks before her last race
- **Race history:** marathon (3:28) + earlier races (halves, shorter
  stuff) sit in `confirmed_races` as fitness anchors going back ~2 years

This is the wedge under maximum pull. The coach voice for Maya doesn't
explain its math; it observes through the lens of it. The 3:28 anchor
and 3:16 goal sit in the system as quiet infrastructure. What surfaces
is what's happening in her *current* paces and training.

What a good coach voice sounds like for Maya:

- *"Easy paces are creeping down — 8:35 last week, 8:22 this week.
  That's BQ-direction. Volume's holding at 42 — solid."*
- *"Tempo locked in at 7:29 average — four weeks ago that was 7:35.
  Fitness is building."*
- *"You're four weeks into the build. Last cycle the analogous week
  was 35 mpw at slower tempos. You're ahead of last time."*

What a bad coach voice sounds like (and what the AI must not do):

- *"Based on your 3:28 PB and your goal of 3:16, you need to..."* —
  preachy, explaining math the athlete already knows.
- *"That's a 12-minute PR — ambitious."* — dismissive framing of her
  goal.
- *"You'll qualify."* / *"You won't qualify."* — certainty claim. Hard
  rule.
- *"Aim for a 3:20 instead."* — coach overstep. The AI doesn't move
  the goalposts.

**Voice principle for Maya, and probably for everyone:** the AI carries
the anchors silently and surfaces observations about the current state.
It does not explain its reasoning out loud. Coaches talk like coaches,
not like textbooks.

**What she wants from the product.**

- **A training journal she actually uses.** Voice memos after runs.
  Manual entries for the things HealthKit misses. Six months from
  now she wants to open the app and see a real diary of her training.
- **Fitness awareness rooted in her history.** Her marathon two years
  ago, her half last spring, the weekly mileage she sustained through
  her last build — these are the anchors. Not a goal time she set
  yesterday.
- **A fitness journey, not a training plan.** She wants to see herself
  getting fitter (or not) week over week. She wants to know what her
  pace × volume distribution looks like over the last 6 months. She
  wants to feel the through-line.
- **A stated goal that the system holds her against.** She'll tell the
  product what she's aiming for. The product checks her trajectory
  against it and tells her honestly where she stands.

**What she doesn't want.**

- The Plan tab. She isn't running someone else's plan; she's running
  her own training, and she journals it.
- A coach client. There's no coach issuing her workouts. The coach
  surfaces (web `coach-portal`, the in-app coach mode toggle) are
  irrelevant to her.
- Prescriptive coaching. The product surfaces signal and observations.
  She decides what to do with them.

**The data points her experience runs on.**

- Workouts (HealthKit auto-sync + manual entries)
- Weekly mileage
- Qualitative feedback — voice training memos (mood, niggles, how it
  felt)
- Time spent at each pace zone (her pace × volume distribution)
- Confirmed prior races (up to 2 years back, used as fitness anchors)
- Stated fitness goal (race time or distance ambition)

**What ships today for Maya.** *See section 2 — assess each surface
against her, not against an abstract athlete.*

**What doesn't ship yet for Maya.** *See section 3 — gaps are now
labeled "for Maya" where the gap is specific to her journey.*

### Other personas

Not defined yet. If/when a coach persona is named, she goes here. If
the self-coached structured-plan athlete is a distinct persona from
Maya, he goes here. Until then, Maya is the only canonical persona
and product decisions are made for her.

---

## 2. What ships today

### iOS app — the athlete surface

Five-tab nav (custom bar, not system `TabView`): **Log · Train ·
Trends · Coach · Plan**. The 5th tab swaps to a coach surface when
the user toggles `isCoachMode = true`.

**Log (front door).** Voice-first. Athlete records a voice memo,
the app transcribes it (Groq), and an LLM (Gemini) extracts: a cleaned
transcript, mood (closed vocabulary — energized, positive, neutral,
tired, struggling, injured), a coach insight, and any body-part
mentions (niggles). Today's metrics live behind a "Today" sheet
accessible from here, not on a tab of their own.

**Train.** Lands on this week. Today's session reads as an editorial
headline, not a card. A WEEK/BLOCK segmenter swaps between the current
week view and longer-arc analytics (block totals, pace × volume
distribution, recent log preview).

**Trends.** "The 5-second view." Four tiles at the top: weekly volume
+ delta, fitness range + confidence, ACWR load ratio, active niggles
count. Below: 12-week fitness progression line, weekly volume × ACWR
bars, drill-down to last workout and active aches.

**Coach.** The Daily Read. An editorial-format AI-generated summary of
where the athlete is — dateline, byline, headline, prose, signature,
sources, confidence bar. Generated by `coaching-daily-read` edge
function, refreshed on app launch and foreground. Includes a pinned
"ask bar" at the bottom (functionality partially wired — see open
questions).

**Plan.** Training plan calendar in week or month mode. Athlete can
join a coach's plan, see scheduled workouts, request reschedules,
edit goal time. In coach mode this tab becomes the coach's workout
library / plans / athletes / plan-updates surface.

### Web — the coach surface

`coach-portal/` at `web/src/app/(app)/coach-portal/`. Auth-gated.

- **/coach-portal** → redirects to `/coach-portal/plans`.
- **/coach-portal/athletes** — daily-scan dashboard. Card grid of
  subscribed athletes with 6-week mileage trend, 7-day pace adherence,
  wellness flags (mood, ACWR, injury risk).
- **/coach-portal/plans** — plans the coach owns. New / edit / builder
  flows.
- **/coach-portal/workouts** — workout library. New / edit flows.

Additional athlete-facing web routes also exist (`/log`, `/plan`,
`/injuries`, `/pace-chart`, `/dashboard`, `/settings`) but the iOS app
is the primary athlete surface; the web equivalents are partial.

Public surface: a landing page at `/` and a blog at `/blog/*`.

### The AI brain — edge functions (39 of them)

Grouped by purpose:

- **Voice memo pipeline.** `transcribe` → `process-training-memo` →
  optional `injury-analysis` if niggle severity warrants it →
  `rebuildAthleteState` to update the athlete's canonical state.
- **Daily coach read.** `coaching-daily-read` produces the editorial
  Coach tab content from the athlete's last 7–14 days of signal.
- **Coachable moments engine.** Rules in
  `_shared/rules/` evaluate athlete state and produce moments for the
  coach. `evaluate-coachable-moment` is the entry point;
  `drain-coachable-moment-jobs` processes the queue.
- **Plan operations.** `generate-training-plan`, four `parse-*`
  variants (plan / week / shorthand / structure), `subscribe-to-plan`,
  `reschedule-plan` (Gemini-driven, constrained to a closed workout
  library), `adapt-plan`, `shift-day`, `update-plan-goal`.
- **Predictions.** `fitness-predictor` (marathon time range +
  confidence), `race-readiness`, `race-intel`.
- **Post-run analysis.** `post-run-analysis`,
  `post-run-reconciliation` (compares prescribed vs executed pace),
  `compute-workout-features`, `reconcile-log`,
  `generate-workout-insight`.
- **Reporting.** `weekly-coaching-report`, `weekly-plan-review`,
  `block-review`.
- **Plumbing.** `get-pace-zones`, `build-pace-profile`,
  `build-athlete-profile`, `recompute-plan-paces`,
  `fetch-workout-weather`, `ingest-documents`.

Backed by 95 Postgres migrations.

### For Maya — what ships today

Honest assessment of her actual happy path, not the abstract product.

- **Log tab — voice memo journaling.** Works. She records after each
  run; the app transcribes, extracts mood and niggles, and saves a
  cleaned note. This is her primary surface and it's real.
- **Manual workout entry.** `ManualWorkoutView` exists. She can log
  the things HealthKit misses.
- **HealthKit auto-sync.** Pulls her runs in on launch. She doesn't
  have to manually log every run.
- **Train tab — today's session as headline.** Less relevant — she's
  not running a prescribed session. But the BLOCK view (pace × volume
  spectrum, block totals) is exactly the lens she wants on her own
  training.
- **Trends tab — 5-second view.** Volume tile, fitness range tile,
  ACWR, active niggles. The fitness range tile is the surface that
  honestly answers "where's my 3:16 trajectory?" — *if* it's wired to
  her race history (it isn't yet, see section 3).
- **Daily Coach Read.** An editorial summary of where she is. Relevant
  to her even without a coach in the loop.

### For Maya — what doesn't apply

- **Plan tab.** She doesn't want to run someone else's plan. The
  calendar surface is irrelevant. Coach-issued plan subscription, the
  reschedule flow, plan adjustments — all noise for her.
- **Web `coach-portal`.** Built for coaches managing athletes. Not
  her surface.
- **In-app `isCoachMode`.** Toggles a coach-facing 5th tab. Not for
  her.

---

## 3. What's missing or broken

The honest list. One line each. If something here ships, move it to
section 2.

### IA / orientation
- **CLAUDE.md is wrong about the iOS tab count.** It claims iOS ships
  4 tabs; actual code ships 5 (`Log · Train · Trends · Coach · Plan`).
  Needs correction.
- **Design ↔ code IA mismatch on the 5th tab.** Design system says
  `RUNS`. Code ships `Plan`. Decision not made.
- **Coach client is forked three ways.** iOS `Coaching/` is real and
  shipping. Web `(app)/coach` is legacy (slated for removal). Web
  `(app)/coach-portal/*` is newer. No canonical surface chosen.

### Data layer
- **`user_profiles` table doesn't exist in production.** Defensive
  workarounds scattered across web, iOS, and one edge function. Central
  cleanup never happened. Full audit at
  `outputs/profile-table-audit-2026-05-22.md`.
- **Real-time synthesis trigger missing.** Rules engine and evaluator
  exist; nothing fires `evaluate-coachable-moment` when a new training
  log lands. One-migration fix. Mirror the existing
  `generate-workout-insight` trigger.
- **`_shared/athlete-state.ts` is 1481 LOC with P0 bugs.** 12
  consumers reference `getOrBuildAthleteState`. Refactor designed at
  `athlete-state-refactor-design.md`. Blocked on eval harness so we
  can refactor without silently changing AI behavior.

### AI safety surface
- **Eval harness exists but coverage is partial.** 4 cassettes
  recorded (3 injury-analysis, 1 process-training-memo). 10 stubs need
  athlete-side inputs. 1 stub needs production library wired. CLAUDE.md
  incorrectly says "Eval harness not built — P0 production blocker" —
  it is built; the gap is coverage.
- **One open coach call from cassette 004.** Gemini said "Take a
  couple of days to rest and monitor it" on an adductor niggle. Regex
  passed. Coach question: acceptable or wedge violation?

### Design parity
- **iOS surfaces drift from JSX systematically.** `Font.dripCaption`
  uses PT Serif instead of mono. `MoodBadge` ships SF Symbol icons
  against the no-emoji rule. `PlateStrip` defined but only used on one
  surface. Spacing not fully tokenized. Full per-surface breakdown at
  `outputs/design-parity-audit-2026-05-20.md`.

### Production readiness
- **No CI.** No automated tests run on push or PR.
- **Supabase prod is still in dev mode** (per
  `outputs/production-readiness-rundown.md`).
- **Public landing page contradicts the wedge** (per same audit).
- **Legal docs are TODO-laden.**

### For Maya specifically — what's missing

The gaps that block her from getting real value from the product
today. Most of the infrastructure exists; the wiring doesn't.

- **`confirmed_races` not consumed by prediction surfaces.**
  `athlete_state.confirmed_races` exists as a JSONB array. The
  `fitness-predictor` edge function uses Claude Haiku and returns
  range + confidence. But the predictor infers fitness from training
  logs with `workoutType === "Race"`, not from confirmed races. Her
  3:28 PB sits in the database and the system doesn't use it. (Full
  plan at `outputs/race-performances-feature-plan.md`.)
- **No race-import flow.** No way for Maya to enter her 3:28 marathon
  PB. She has to either log a fake "Race" workout or wait for HealthKit
  to surface old runs and manually classify. Onboarding doesn't ask
  "what's your last race?"
- **Pace zones still anchored to goal time, not race history.**
  `paceTableFromProfile` is pluggable but currently picks goal time
  (3:16 aspiration) as anchor, not race time (3:28 reality). Maya's
  easy pace is computed off a fitness she hasn't reached yet.
- **No "fitness journey" surface.** Trends shows 12-week fitness
  progression. Maya wants 6 months. She wants to see the through-line
  from her last race to her current state. The chart exists, the time
  horizon doesn't.
- **No "training journal" surface.** Her voice memos and workouts both
  exist as data. She has no single page that reads as a 6-month diary
  of her training. The closest is HistoryView, which is a workout list,
  not a journal.
- **Fitness range not yet honest about her goal gap.** The 3:16 goal
  and 3:28 PB are 12 minutes apart. The fitness range tile should sit
  somewhere in between with confidence reflecting the gap. Needs
  audit.
- **No coachable-moment rules read race history.** All 4 current rules
  are race-blind. For Maya — whose entire story is "I'm coming back to
  Boston-qualify off a 3:28" — race-aware rules would surface the most
  valuable moments (e.g., "your build at this point in the cycle was
  35 mpw last time and you ran 3:28 — you're at 40 now").

---

## 4. Five pillars status

The runner-facing product asks five questions in priority order.
Here's where each one actually is.

**1. Training — what did I do? what am I supposed to do?** (v1)
*Mostly shipping.* Training plan calendar (Plan tab), HealthKit
workout sync, post-run analysis, prescribed-vs-executed reconciliation,
coach-issued plans via coach-portal. Niggle/issue: pace zones now use
canonical math; legacy seconds-offset ladder removed. Gap: the
custom plan builder was cut by design — replaced by template plans +
coach-built plans. Verify the code is actually removed.

**2. Understanding — how am I doing? where am I going?** (v1)
*Partially shipping.* Trends tab is live with the 5-second view and
fitness range + confidence. Daily Coach Read is live. Gap: marathon
prediction surfaces need audit to confirm every one ships range +
confidence, never point estimates.

**3. Recovery — how well did I rest? should I push or pull today?** (v1.5)
*Partially served.* Voice-log fatigue signal flows into mood. HealthKit
sleep is read. Recovery is not yet a first-class surface — it's a
component of other surfaces. v1.5 promotes it to its own surface.

**4. Mobility — is my body moving well?** (v2)
*Nothing shipping.* Deferred future product.

**5. Strength — am I doing the work that protects the running?** (v3)
*Nothing shipping.* Deferred future product.

---

## 5. Next 6 months — the phases

Sequenced. Each phase ships something visible. Each phase ends in
something Maya (or her hypothetical coach) can see.

**Phase 1 — Eval harness coverage.** *(weeks)*
Fill the remaining 10 cassette inputs. Wire the reschedule-plan
library. Record everything. End state: every AI prompt has a
behavioral test that catches wedge violations. Prompt changes stop
being terrifying. *Why first: every other phase touches AI behavior;
without the harness we change things blind.*

**Phase 2 — Race anchoring (Maya's wedge).** *(~1 week, mostly wire-up)*
Execute `outputs/race-performances-feature-plan.md`. Add an
onboarding "your last race" question. Plumb `confirmed_races` through
`paceTableFromProfile`, `fitness-predictor`, and at least one
coachable-moment rule. End state: Maya enters her 3:28 marathon PB,
the system anchors her pace zones on it (not on her 3:16 goal), the
fitness range tile honestly answers "what does my trajectory say."
*Why second: highest-leverage athlete-facing win, infrastructure
mostly exists, validates the wedge.*

**Phase 3 — Profile table cleanup.** *(~4 dev days)*
Execute the 7-phase punch list at
`outputs/profile-table-audit-2026-05-22.md`. End state: one canonical
state table (`athlete_state`), no more `user_profiles` ghost
references, SETTINGS surface for athlete preferences. *Why third:
foundation work that unblocks Phase 4. Could swap with Phase 2 if
data-layer pain compounds.*

**Phase 4 — Memory architecture.** *(multi-week)*
Build the hot/warm/cold tiers. Hot: 0–14 days raw events. Warm: 2
weeks–6 months weekly rollups. Cold: 6 months–2 years block summaries
with embeddings. End state: when Maya asks "how does this build
compare to my last marathon build," the AI actually knows. *Why
fourth: the depth phase. Builds on a clean profile foundation.*

**Phase 5 — Maya's journey surface.** *(weeks, design first)*
Build the 6-month training journal view + the fitness-journey
through-line. End state: Maya opens the app and sees her own training
arc — voice memos, races, weekly mileage, pace × volume distribution
— as a single readable diary. *Why fifth: this is Maya's primary
experience and it doesn't exist yet, but it depends on Phases 2 and 4
to be honest about her fitness over time.*

**Phase 6 — Coach client unification.** *(strategic call + migration)*
Pick the canonical coach surface. Migrate the other two. End state:
new coach features cost 1x to ship, not 3x. *Why later: depends on
the wedge decision (section 6). If Maya is the primary persona, coach
client unification is lower priority. If dyad stays primary, this
moves up.*

**Phase 7 — Production-readiness.** *(parallel track)*
CI, prod-mode Supabase, replace landing page, finish legal docs. End
state: ready to onboard real athletes. *Why parallel: can run
alongside any phase.*

### Phase ordering depends on the wedge

The order above assumes Maya is the primary persona. If the wedge
call (section 6) lands as "dyad is primary," Phase 6 moves up and
Phase 5 may shift or change shape. Don't lock the order until that
decision is made.

---

## 6. Open questions / strategic calls

Things only Rio can decide. Surface them here so they don't get lost.
When you make a call, log the answer and the date — don't delete the
question.

### Strategic (affects roadmap shape)

- **The wedge — dyad primary, or Maya primary?** *(open, surfaced
  2026-05-28)* CLAUDE.md says coach-athlete dyad is the wedge. Maya
  is self-coached. Either we broaden the wedge to include journaling
  athletes as a first-class path, or we promote Maya to primary and
  dyad becomes secondary, or we keep dyad primary and Maya is a
  secondary persona. Phase ordering depends on this. Don't force.
- **Self-coached mode — invest or stay deferred?** *(linked to wedge
  question)* If Maya is primary, this question is answered. If dyad
  stays primary, we need to decide how much we invest in Maya's
  experience even as a secondary persona.
- **Which coach surface is canonical?** *(open)* iOS `Coaching/`,
  web `(app)/coach` (legacy), or web `(app)/coach-portal/*`. Until
  resolved, coach features cost 3x. Less urgent if Maya is primary.

### Tactical (affects what to build next)

- **Is the 5th tab "Plan" or "Runs"?** *(open)* Design says Runs.
  Code ships Plan. Pick.
- **Recovery as a first-class surface — what does it look like?**
  *(open)* v1.5 work needs design before engineering.
- **Custom plan builder — fully removed yet?** *(verify)* Was cut by
  decision per CLAUDE.md. Confirm the code is gone.

### Coach calls (AI behavior judgment)

- **Cassette 004 — is "take a couple of days to rest" acceptable
  language?** *(open, surfaced previously)* Gemini produced this in
  response to an adductor niggle. Regex passed but borderline. Coach
  judgment needed.

---

## How to use this doc

- **Start every session by reading sections 1–3.** That's the
  10-minute orientation. Skip 4 and 5 unless you're choosing what to
  work on.
- **End every session by updating section 3.** If something moved
  from broken to shipping, move the line. If you made a new discovery,
  add it.
- **When you make a strategic call, log it in "Open questions" with
  the answer and a date.** Don't delete the question — show the
  decision and when it happened.
- **When you finish a phase, move it up.** Phase 1 done → it shifts
  to "what ships today." Phase 6 backfills behind it.

This doc is the source of truth for "what is this product." Code,
CLAUDE.md, and the outputs archive are the implementation. If those
disagree with this doc, this doc wins until you decide otherwise.

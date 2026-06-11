# CLAUDE.md — context for AI coding assistants

This file is the orientation doc for any AI coding assistant (Claude Code,
Cursor, etc.) working in this repo. Read it before making changes.

## What this product is

A coach's nervous system for endurance athletes. The product fuses
quantitative training data (volume, pace, ACWR, fitness curves) with
qualitative voice-log signal (mood, fatigue, niggles) into actionable
**coachable moments** that human coaches act on.

Core principle, applied everywhere: **AI advises, never acts.** Coaches own
decisions — and when no coach is in the loop, the athlete owns them. The
product surfaces observations and routes the call back to the human.

**Wedge audience as of 2026-05-28:** Maya — the self-coached endurance
runner who journals her training, anchors her fitness on real race history,
and wants honest observation without prescription. Coach-athlete dyads
remain a first-class case (coach surfaces still exist), but the canonical
persona driving design decisions is Maya. The "dyad-primary vs. Maya-
primary" call is still formally open — see
`outputs/maya-product-roadmap-2026-05-28.md` section 6.

**The product is journey-centric, not plan-centric.** The training arc is
the through-line. `activePlan == nil` is a first-class state, not a failure
mode. See `outputs/maya-data-aware-journey-2026-05-28.md` for the
foundational doc on the data-aware journey concept.

### Five pillars (the cohesive vision, sequenced)

The runner-facing product asks five questions, in priority order:

1. **Training** — what did I do? what am I supposed to do? (v1)
2. **Understanding** — how am I doing? where am I going? (v1)
3. **Recovery** — how well did I rest? should I push or pull today? (v1.5)
4. **Mobility** — is my body moving well? (v2)
5. **Strength** — am I supporting the running with the work that protects it? (v3)

v1 ships training + understanding. Recovery is partially served already
(voice-log fatigue, HealthKit sleep) and gets promoted to a first-class
surface in v1.5. Strength + mobility are deferred future products.

## Stack

- iOS app: `RunningLog/` (Swift / SwiftUI, native HealthKit)
- Backend: `supabase/` (Postgres + edge functions in Deno/TypeScript)
- Web: `web/` (Next.js — coach portal in `(app)/coach-portal/*`, legacy
  `(app)/coach` route slated for removal)
- ML service: `ml-service/` (Python / FastAPI, deployed on Railway)
- Docs: `docs/`
- Design system: `design-system/` (Post Run Drip — the canonical visual
  language; voice guide, color/type tokens, font files, and the iOS UI
  kit. See "Design system" section below before touching any view code.)
- Design artifacts: `outputs/` (audits, decisions, design specs from
  the May 2026 design sprint — see "Recent decisions" below)

## Information architecture (athlete-facing)

**Target IA (as of 2026-05-28): four-tab bottom nav — Log · Trends ·
Train · Coach.** Mental flow: input → overview → detail → synthesis.

- **Log** — voice-first front door at top (record button + voice/manual
  toggle) and the 6-month training journal scrolling below. Last 6
  months default; infinite scroll for older. Workouts auto-populated
  from HealthKit, voice memos transcribed and processed, cross-training
  and strength sessions shown alongside runs. Pure record, no AI
  annotation inline.
- **Trends** — the journey as analytics. Race-anchored fitness range
  with confidence, volume tile, ACWR, niggles tile. 26-week fitness
  chart with race anchors plotted as vertical markers. Tappable GOAL
  line at bottom for goal entry / edit. The 5-second view.
- **Train** — the journey as plan and history. Three modes via
  segmenter: CURRENT (this week + today), CALENDAR (month view with
  past + planned, coach plan layered if present), HISTORY (longer-arc
  analytics — pace × volume distribution, cycle comparison overlays,
  fitness arcs). Plan is a *subset* of Train, not its own tab.
- **Coach** — the AI Daily Read as observation, on demand. Maya taps
  generate; AI produces a minimal-format paragraph (eyebrow date +
  headline + 2-4 observation sentences + italic soft questions). Voice
  posture: feeling before data; warm encouragement; reads life
  context (weather, sleep, work stress); never explains math; carries
  anchors and goals silently. Maya can ask Coach to read her journey
  through specific lenses ("how does fitness compare to last cycle?").

**Code as of 2026-05-28 ships 5 tabs** (`Log · Train · Trends · Coach ·
Plan`, in `RunningLog/App/RunningLogApp.swift:60-140`). The target 4-tab
IA is the Phase 3 deliverable in Maya's roadmap — Plan collapses into
Train. See `outputs/maya-product-roadmap-2026-05-28.md` for sequencing.

## Where things live

- Edge functions: `supabase/functions/<name>/index.ts`
- Shared TS utilities: `supabase/functions/_shared/`
- Rule evaluators (V1 coachable_moments): `supabase/functions/_shared/rules/`
- Migrations: `supabase/migrations/` — naming `YYYYMMDDHHMMSS_descriptive.sql`
- Specs: `docs/specs/`
- Coaching philosophy (source of truth for AI behavior):
  `docs/coaching/principles.md`
- RLS checklist (mandatory for every new table):
  `docs/conventions/rls-checklist.md`
- Design system (Post Run Drip): `design-system/` — voice guide
  (`README.md`), token source-of-truth (`colors_and_type.css`), iOS
  UI kit (`ui_kits/ios_app/*.jsx`), font files. See the "Design
  system" section below for the screen-by-screen JSX ↔ Swift map.
- Design specs from the May 2026 sprint: `outputs/`. **The three anchor
  docs as of 2026-05-28:** `maya-data-aware-journey-2026-05-28.md`
  (foundational), `maya-product-roadmap-2026-05-28.md` (decisions +
  phases), `product-state-2026-05-28.md` (product overview). All other
  audit docs (`profile-table-audit-2026-05-22.md`, `design-parity-audit-2026-05-20.md`,
  `race-performances-feature-plan.md`, etc.) feed into those three.

## Hard rules (no exceptions)

1. **Every new table ships with RLS in the same migration.** No "Allow all"
   placeholder policies in production paths. See
   `docs/conventions/rls-checklist.md`.
2. **AI never recommends stopping training, diagnosing injuries, or making
   medical claims.** Defers to the coach. Hard guardrails in system prompts
   enforce this. Niggles classifier vocabulary is closed (see Niggles spec
   below).
3. **No LLM prompt change ships without running the eval harness.**
   The harness exists at `supabase/functions/_evals/` (README, runner,
   rubric primitives, Gemini provider, custom checks). Coverage is
   partial as of 2026-05-28 — 4 cassettes recorded (3 injury-analysis,
   1 process-training-memo), 10 stubs need athlete-side inputs filled,
   1 stub (reschedule-plan) needs production library wired. Run via
   `_evals/record.ts` with `GEMINI_API_KEY`. Until coverage is complete
   on the prompt you're touching, supplement with manual review against
   `docs/coaching/principles.md`.
4. **All inserts to `coachable_moments` happen via service-role edge
   function.** No client-side INSERT policy.
5. **Migrations are append-only.** Never edit a deployed migration; write a
   new one.
6. **Use `current_coach_id()` for coach-scoped RLS** (the SECURITY DEFINER
   helper from `20260311120000_fix_coach_rls_recursion.sql`) — direct
   subqueries against `coach_profiles` cause recursion.
7. **Predictions ship with range + confidence, never a single point.** The
   marathon-prediction example: `3:08 – 3:14, midpoint 3:11, HIGH
   CONFIDENCE based on 4 MP workouts and a recent half`. Never
   `3:09:30 PROJECTED FINISH`. The seconds are math artifact, not
   meaningful signal. See `outputs/marathon-prediction-honesty.md`.
8. **No em-dashes as empty-state placeholders.** Every empty cell uses
   the empty-state component (eyebrow + plain-prose nudge + optional CTA).
   See `outputs/new-user-action-plan.md` and the empty-state component spec.
9. **Migrations reach prod only via `supabase db push` from a committed
   SHA.** No dashboard SQL-editor or MCP `apply_migration` against prod —
   ad-hoc applies are how the ledger diverged (17 re-stamped entries, 2
   ghost migrations). See `docs/migration-ledger-reconciliation-2026-06-11.md`.

## Conventions

- Edge functions follow the patterns in `supabase/functions/_shared/{auth,cors}.ts`.
- TypeScript strict mode; prefer pure functions for testability (see rule
  evaluators as the model).
- Postgres uses `TIMESTAMPTZ` (not `TIMESTAMP`).
- Auth user IDs are `TEXT` columns matching `auth.uid()::text`. Coach IDs
  are `UUID` referencing `coach_profiles.id`.
- New rules for `coachable_moments` live as pure functions in
  `_shared/rules/<ruleName>.ts` and are registered in `_shared/rules/index.ts`.
- Mood is stored as a TEXT label, not numeric. Vocabulary:
  `energized | positive | neutral | tired | struggling | injured`.

### `data_depth` user state (UI gating)

A single computed integer 0–3 that gates the editorial register of the
UI. Drives every voice-and-content decision on Today.

| Depth | Trigger | Voice |
|---|---|---|
| 0 — empty | New account, < 1 run, < 1 voice log | Plain UI text. No pull-quotes. |
| 1 — minimal | 1+ run OR 1+ voice log | Plain UI text. One muted pull-quote OK if numbered. |
| 2 — moderate | 7+ days of data | Editorial register creeping in. Trend deltas allowed. |
| 3 — full | 21+ days of data, OR a goal set | Full editorial system. Pull-quotes per section. |

Every pull-quote at depth 2+ must cite at least one specific number.
*"Tempo locked in — 7:29 average vs. 7:35 four weeks ago"* — fine.
*"The plan is working"* on its own — never. See
`outputs/new-user-action-plan.md`.

### Niggles (body-part voice mentions)

The injury-mention surface, designed for detection-not-diagnosis. Stored
in `body_mentions` table; UI labeled "Niggles." Three rules:

1. **Closed body-part vocabulary.** Roughly 30 entries (foot, ankle,
   achilles, calf, shin, knee, IT band, quad, hamstring, etc.). If the
   athlete says "subtalar joint," the classifier maps to ankle or
   omits — it does NOT invent medical entities.
2. **Quote verbatim.** The athlete's own words and severity language.
   "Could barely walk" is not coerced to a 7/10.
3. **Surface, never interpret.** The system reports *what was said and
   where*. It never says *what that means*. Tooling-level reminder:
   never output diagnoses (e.g. "ITBS"), never recommend actions
   ("rest", "ice"), never assess severity itself.

See `outputs/body-mentions-design.md` for the classifier prompt and
behavioral test cases.

### Pace zones

**Target taxonomy: 10 zones (3 effort + 7 race-pace).** Derived from
race anchor (or goal race time when no anchor exists) via
`derivePaceTableFromGoal` in `web/src/components/coach/workout-helpers.ts`.
**Do not use the legacy seconds-offset ladder** that lived in
`web/src/app/(app)/pace-chart/page.tsx` — that was a bug, fixed.

| Zone | Math | Notes |
|---|---|---|
| Easy | MP / 0.765 — percentage of MP speed | Aerobic, conversational |
| Moderate | between Easy and Steady | NEW 2026-05-28; upper aerobic |
| Steady | MP / 0.925 | Moderate-aerobic, marathon-prep |
| MP | anchor (from race anchor or goal_time / race_distance) | Marathon pace |
| HMP | between MP and LT | NEW 2026-05-28; half marathon pace |
| LT | 1-hour race pace (interpolated between 10K and HM) | Threshold |
| 10K | race-equivalence ratio | |
| 5K | race-equivalence ratio | |
| 3K | between 5K and Mile | NEW 2026-05-28 |
| Mile | race-equivalence ratio | |

LT is the athlete's 1-hour race pace, computed by interpolating between
10K and HM by the elapsed-time fraction needed to hit exactly 3600s.
The legacy LT=HM collapse was wrong for non-elite runners whose HM takes
well over an hour. Implementations must mirror exactly:
`web/src/components/coach/workout-helpers.ts:oneHourPaceSecPerMile`,
`supabase/functions/_shared/paces.ts:oneHourPaceSecPerMile`, and
`RunningLog/Workouts/PaceCalculator.swift:calculateOneHourPace`.

Aerobic zones (Easy, Moderate, Steady, Long Run) ship as ranges (±5%).
Race-pace zones (MP, HMP, LT, 10K, 5K, 3K, Mile) ship as exact single
targets.

iOS `RunningLog/Workouts/PaceCalculator.swift` race-equivalence ratios
are kept in sync with `workout-helpers.ts`. Verify on changes.

**Anchor priority (2026-05-28):** Race anchor (from `confirmed_races`)
wins over goal time. A 3:28 marathon PB on file anchors Maya's pace
zones on her real fitness, not on her 3:16 aspiration. Goal time is
direction; race anchor is reality. Phase 2 of Maya's roadmap wires
this through. See `outputs/race-performances-feature-plan.md`.

**Workout labels are pace-zone labels.** "Tempo" and "Threshold" are
dropped as ambiguous — the zone IS the workout label. A workout
formerly called "Tempo" is now `MP 7 mi` or `HMP 7 mi` depending on
the actual pace. "Threshold" is `LT 6 mi`. "Intervals" is `5K 5×1km`
or `3K 4×800` etc. Structural labels survive for `Long` (long run,
typically Easy/Moderate/Steady pace) and `Long wo` (long run with
embedded quality references — those references don't carry the
precision of a pace-zone workout). Non-running labels: `Cross-train`,
`Strength`, `Rest`, `Race`.

## Design system

The canonical visual language is **Post Run Drip** — *"restraint as
foundation, intensity as accent."* Editorial running magazine. Warm
paper. Black ink. One coral accent, used like punctuation. The full
spec lives at `design-system/`.

Read `design-system/README.md` first if you're touching any view code.
It's the source of truth for voice (what we say and how), tokens
(color/type/spacing/radii/motion), and the editorial primitives
(plate strip, eyebrow, editorial rule, coach quote). The README is
short and worth the read in full.

### Where things live in `design-system/`

- `README.md` — voice + foundations spec. The most important file.
- `colors_and_type.css` — token source-of-truth (color, type, spacing,
  radii, motion, shadows). Every component class derived from these vars.
- `fonts/` — Crimson Pro variable + PT Serif Regular/Italic/Bold. The
  same TTFs ship in `RunningLog/Fonts/`.
- `ui_kits/ios_app/` — pixel-faithful iOS recreation in JSX. Each screen
  is a single ~100-line file; layout-only, no data. Read these like
  "the design intent in code form."
- `ui_kits/ios_app/Primitives.jsx` — 12 named primitives
  (`Eyebrow`, `Section`, `PlateStrip`, `MoodPill`, `MoodRadio`, etc.).
- `IMPLEMENTATIONS.md` — design ↔ code map. "Parity verified" column is
  currently empty on every row — see "Known issues" below.

### JSX ↔ Swift screen map

When implementing or reshaping any of these surfaces, open the JSX
side-by-side with the Swift file. The handoff 3 refresh expanded this
map significantly — most tabs and many sheets now have a JSX side.

**Tab surfaces:**

| Design (`design-system/ui_kits/ios_app/`) | iOS code |
|---|---|
| `LogScreen.jsx` | `RunningLog/App/LogView.swift` + `App/TodayHomeView.swift` + `App/TodayPlate18.swift` (Today is folded into Log) |
| `TrainingScreen.jsx` (+ unresolved `TrainA/B/C.jsx` variations + `TrainingScreen.v1.jsx`) | `RunningLog/Training/TrainingTabView.swift` (drifted — see below) |
| `TrendsScreen.jsx` | `RunningLog/Trends/TrendsTabView.swift` |
| `CoachScreen.jsx` | `RunningLog/Coaching/CoachTabView.swift` + `Coaching/CoachView.swift` |
| `RunsScreen.jsx` *(design's 5th tab)* | *(iOS 5th tab is `Plan`; both are out in the target 4-tab IA — see below)* |

**Standalone screens & key sheets:**

| Design (`design-system/ui_kits/ios_app/`) | iOS code |
|---|---|
| `SignInScreen.jsx` | `RunningLog/Auth/SignInView.swift` |
| `OnboardingScreen.jsx` | `RunningLog/App/OnboardingView.swift` |
| `WorkoutDetailScreen.jsx` + `WorkoutMark.jsx` | `RunningLog/Workouts/WorkoutDetailPlate23.swift` |
| `InjuriesScreen.jsx` + `InjurySheets.jsx` | `RunningLog/Analysis/InjuryPlate28.swift` + `Analysis/InjuryView.swift` + `Analysis/InjuryDetailSheet.swift` + `Analysis/AddInjurySheet.swift` |
| `PlanScreen.jsx` + `RacePlanScreen.jsx` | `RunningLog/Training/MonthCalendarView.swift` + `Training/PlanMonthSummaryView.swift` |
| `TrainingPlanSheet.jsx` | `RunningLog/Training/ImportTrainingPlanSheet.swift` + `Training/JoinCoachPlanSheet.swift` + `Training/AdaptivePlanBuilderSheet.swift` |
| `WeeklyReviewScreen.jsx` | `RunningLog/Coaching/WeeklyCoachingReportSheet.swift` |
| `Sheets.jsx` | *(collection — various iOS sheets across `App/`, `Workouts/`, `Training/`)* |
| `SettingsSheets.jsx` | *(sidebar menu sheets — no single iOS file; menu opens from the global hamburger in `RunningLogApp.swift`)* |
| (no JSX yet) | `RunningLog/Coaching/Read/CoachReadView.swift` — see `outputs/coach-read-design-drift.md` |
| (no JSX yet) | `RunningLog/Training/DayDetailPlate22.swift` (Plate 22 · day detail sheet) |

Don't port `TrainingScreen.jsx` into Swift until the A/B/C variation
question is settled.

### IA — current state vs. target (read before touching nav)

**Current code:** iOS ships **5 tabs** (`Log · Train · Trends · Coach
· Plan`) in `RunningLog/App/RunningLogApp.swift:60-140`.

**Design system:** Documents a 5-tab nav (`LOG · TRAIN · TRENDS · COACH
· RUNS`) — slightly different (Runs vs Plan as the 5th).

**Target IA as of 2026-05-28:** **4 tabs — `Log · Trends · Train ·
Coach`.** Plan collapses into Train as a subset (calendar mode shows
past + planned together; coach-issued plans layer in for athletes on
plans). Runs as a separate tab is also out. The 4-tab nav reflects
Maya's needs (input → overview → detail → synthesis) and aligns the
product with the journey-centric framing.

Phase 3 of Maya's roadmap untethers Train from `activePlan` and ships
the 4-tab nav. See `outputs/maya-product-roadmap-2026-05-28.md`.

**Until Phase 3 lands**, code still ships 5 tabs. Don't add new
surfaces to the soon-to-be-removed Plan tab. Don't build "Runs" as
a separate tab.

### Known iOS drift from the spec

The iOS surfaces currently drift from the JSX in several systematic
ways — `Font.dripCaption` renders uppercase eyebrows in PT Serif
instead of mono, `MoodBadge` ships SF Symbol icons against the
no-emoji rule, `PlateStrip` is defined but only used on one surface,
spacing isn't tokenized (off-grid 14/22 values are common). Full
per-surface breakdown in `outputs/design-parity-audit-2026-05-20.md`;
system-level token + primitive gaps in
`outputs/design-system-audit-2026-05-20.md`; the structural reasons
parity is hard (and the three-thing fix path) in
`outputs/why-ios-design-parity-is-hard.md`.

### Working with the design system

- **Read the JSX, then write the Swift.** The JSX is the intent; the
  Swift implementation is the production-ready version with data
  wired in. If the JSX and Swift disagree, the JSX wins — unless the
  drift is the deliberate Training-tab one, which is its own call.
- **Don't reinvent primitives.** If you're writing
  `Text("X").font(.system(...)).tracking(N)` for an uppercase label,
  you're rebuilding an `Eyebrow`. Use `dripEyebrow(11).tracking(1.3)`
  for now; if you're touching this code, consider extracting an
  `Eyebrow` view in `DesignSystem.swift`.
- **Coral is a punctuation mark, not a paint.** Spec: *"One coral
  element per visual cluster, maximum."* If two would compete, drop
  one to ink-2.
- **Never use em-dashes as empty-state placeholders.** Hard rule #8.
  Use `EmptyStateView` (iOS) or `<EmptyState />` (web).

## Known issues / WIP

- **Coach client work deprioritized (2026-05-28).** Maya doesn't use
  coach surfaces. Three surfaces still exist (iOS `Coaching/`, web
  `(app)/coach`, web `(app)/coach-portal/*`) and none is canonical.
  Don't deepen any of them until dyad-persona work is reinvested in.
  See Phase 6 placeholder in Maya's roadmap.
- **Eval harness exists; coverage is partial.** Located at
  `supabase/functions/_evals/` (runner, rubric primitives, Gemini
  provider, custom checks). 4 cassettes recorded as of 2026-05-28;
  10 stubs need athlete-side inputs; 1 needs production library
  wired. Phase 1 of Maya's roadmap closes this out. Until then,
  prompt changes need manual review against `docs/coaching/principles.md`.
  **CI now enforces the gate (2026-06-11):** a PR that modifies a file in
  `_shared/prompts/` fails unless `_evals/cassettes/<prompt>/` exists
  (`.github/scripts/check_eval_coverage.py`).
- **Edge function consolidation pending.** ~39 functions; `parse-*` ×4
  could collapse to one router-dispatched parser. New code should not
  add to overlap clusters.
- **Real-time synthesis trigger: RESOLVED (verified in prod 2026-06-11).**
  The outbox pair (`20260518100000_coachable_moment_outbox_trigger` +
  `20260518110000_drain_coachable_moment_jobs_cron`) is applied in prod and
  `drain-coachable-moment-jobs` is deployed. Task #23 closed.
- **`user_profiles` table doesn't exist in production.** Root cause found
  2026-06-11: the January migration's malformed filename
  (`20260128_152000_user_profile.sql`) parsed as version `20260128`,
  colliding with the applied `fix_vector_search`, so the CLI silently
  skipped it; file now quarantined in `supabase/migrations_quarantine/`.
  **Escalated to feature blocker** — the Daily Read cron + workout-trigger
  migrations are quarantined behind this decision. Defensive workarounds
  remain across web, iOS, and one edge function. See
  `outputs/profile-table-audit-2026-05-22.md` and
  `docs/migration-ledger-reconciliation-2026-06-11.md`.
- **`_shared/athlete-state.ts` is 1481 LOC with P0 bugs.** Refactor
  designed at `athlete-state-refactor-design.md`. Blocked on eval
  harness coverage so we can refactor without silently changing AI
  behavior. Lands in Phase 6 (memory architecture).
- **Pace chart `(app)/pace-chart/page.tsx` was buggy** — used a
  seconds-offset ladder; now refactored to call `derivePaceTableFromGoal`
  via `pace-chart-client.tsx`. The buggy version persists in
  `.claude/worktrees/*` — do not source from there.
- **Stale worktrees in `.claude/`.** Read-only artifacts. Do not source
  files from them.
- **Production blockers** (from `outputs/production-readiness-rundown.md`,
  updated 2026-06-11): CI exists (`.github/workflows/ci.yml`) plus Deploy
  workflow, drift detector, and smoke tests (`docs/ops-delivery-roadmap-2026-06-10.md`)
  — pending GitHub secrets + branch protection. Still open: Supabase prod
  config in dev mode, public landing page
  contradicts the wedge, legal docs TODO-laden. Engineering work,
  Phase 8.

## Recent decisions (May 2026 design sprint)

Decisions captured during the May 2026 sprint, with deep rationale in
`outputs/`.

### 2026-05-28 — Maya, the journey reframe, and the IA shift

A long working session produced the structural reframe of the product
around Maya as the canonical persona and the journey concept as the
foundational framing. Full decisions log (30+) in
`outputs/maya-product-roadmap-2026-05-28.md`. Anchor docs:
`outputs/product-state-2026-05-28.md` and
`outputs/maya-data-aware-journey-2026-05-28.md`.

Highlights:

- **Maya is the canonical persona.** Self-coached endurance runner;
  3:28 marathon PB chasing 3:16 BQ off ~40 mpw baseline. Has races
  going back ~2 years. Product decisions are tested against her.
  Coach-athlete dyad-primary-vs-Maya-primary wedge call remains
  formally open.
- **Journey-centric, not plan-centric.** The training arc is the
  through-line. `activePlan == nil` is first-class. The product
  fuses qualitative voice memos with quantitative training data and
  reads them together.
- **4-tab IA: Log · Trends · Train · Coach.** Plan collapses into
  Train. Mental flow: input → overview → detail → synthesis.
- **10-zone pace taxonomy:** Easy / Moderate / Steady (effort) + MP
  / HMP / LT / 10K / 5K / 3K / Mile (race-pace). Workout labels are
  pace-zone labels — "Tempo" and "Threshold" are dropped as
  ambiguous. Adds Moderate, HMP, 3K to the canonical seven.
- **Race-anchored fitness.** `confirmed_races` becomes the source of
  truth for pace zones and fitness prediction, not goal time. Goal
  is direction; race is reality.
- **Coach Read voice posture:** *feeling first, then workouts, then
  mileage.* Warm encouragement (not toxic). Reads life context
  (weather, sleep, work stress). Anchors and goal carried silently;
  never explained. Ends with 1-2 soft questions for the athlete to
  sit with. On demand, not auto-daily.
- **Maya can ask Coach for specific lenses.** Conversational query on
  top of the default Read.
- **2-year HealthKit back-fill on signup.** Auto-detect races from
  back-fill, prompt to confirm. Optional goal-setting during
  onboarding. Maya lands in a product that already knows her.
- **Niggles surface inline + Trends tile.** Body-part chips on
  journal entries; NIGGLES tile on Trends; tap to see the per-body-
  part timeline.
- **Cross-training stays out of running-fitness math.** Different
  *kind* of stress (cardiovascular, not mechanical). Shown in the
  journal; not counted in ACWR or fitness prediction.
- **Coach-client unification deprioritized.** Maya doesn't use coach
  surfaces.

### Earlier May 2026 decisions

- **Niggles adopted** as the name for body-part voice mentions
  (not "injuries", not "pain mentions", not "symptoms"). Closed
  vocabulary, detection-not-diagnosis. See `outputs/body-mentions-design.md`.
- **Custom plan builder cut.** Was an LLM-generative plan author
  (`supabase/functions/custom-plan-builder/`, iOS `CustomPlanBuilderView.swift`,
  `PlanImportService.swift`). Replaced by template plans + coach-built
  plans. Self-coached AI plan generation is not in scope.
- **Biomechanics / form check cut.** Including `pose_landmarker_lite.task`
  (~5 MB iOS bundle), `biomechanics-analysis` and `form-check-analysis`
  edge functions. Computer-vision running form is a separate product;
  not in v1.
- **`adaptive-workout` edge function deleted.** Was returning 410 Gone;
  deletion deadline already passed.
- **`reschedule-plan` kept with safety constraints.** Uses Gemini with
  a closed `WORKOUT_CODES_BY_DAY` library. Constrained selection, not
  free generation. Required constraints before launch: eval harness
  coverage, validation layer, no auto-apply (writes to `plan_adjustments`
  with `auto_applied: false`), once-per-day rate limit. See
  `outputs/plan-mutations-and-race-design.md`.
- **Pace zones canonical math** is in `workout-helpers.ts:derivePaceTableFromGoal`
  (race-equivalence ratios + percent-of-MP-speed). Not the seconds-offset
  ladder.
- **Marathon prediction must show range + confidence**, not a point
  estimate. See `outputs/marathon-prediction-honesty.md`.

## Pointers for common tasks

- **Designing or implementing anything athlete-facing** → Read
  `outputs/maya-data-aware-journey-2026-05-28.md` first. Then
  `outputs/maya-product-roadmap-2026-05-28.md` for decisions log.
  Test the design against Maya's journey, not against an abstract
  athlete.
- **Add a coachable_moment rule** → Read `docs/specs/coachable_moment.md`,
  add a new file in `_shared/rules/`, register in `_shared/rules/index.ts`.
  For self-coached Maya, only *pattern observations* (mood arcs, niggle
  clusters, fitness trends) surface to her directly; operational
  moments (load spike + injury risk, schedule conflicts) stay coach-
  only or soften.
- **Add an LLM call** → Inline prompts are being deprecated; new calls
  should use `_shared/prompt-library.ts`. Add eval cassette coverage
  in `_evals/cassettes/<prompt-name>/` before shipping the prompt
  change.
- **Add a new table** → Follow `docs/conventions/rls-checklist.md`.
  Include RLS in the same migration.
- **Change athlete-coach relationship logic** → Touches RLS recursion
  carefully. Re-read `20260311120000_fix_coach_rls_recursion.sql` first.
- **Add a prediction surface** → Show range + confidence. Round timestamps
  to whole minutes. Never display seconds-precision projections. Anchor
  on `confirmed_races` when available, fall back to goal time. See
  `outputs/marathon-prediction-honesty.md` and
  `outputs/race-performances-feature-plan.md`.
- **Add an empty-state surface** → Use the empty-state component pattern
  (eyebrow + nudge + optional CTA). Never em-dashes.
- **Touch a Coach Read prompt** → Read the Coach voice principles
  section in `outputs/maya-data-aware-journey-2026-05-28.md`. Feeling
  first. Warm encouragement. Reads life context. Anchors silent.
  Soft questions, not directives.

## Files worth knowing about

- `supabase/functions/_shared/dataAnalysis.ts` — quant analytics
  (ACWR, volume, compliance, fatigue extraction)
- `supabase/functions/_shared/weeklyAnalytics.ts` — shared types
  (`TrainingLogRow`, `ScheduledWorkoutRow`) and metrics math
- `supabase/functions/_shared/rules/` — V1 coachable_moment rules
  (`loadSpikePlusInjury`, `lowMoodStreak`, `missedWorkouts`)
- `supabase/functions/evaluate-coachable-moment/index.ts` — entry point
  for synthesis evaluation
- `web/src/components/coach/workout-helpers.ts` — canonical pace-zone
  derivation (`derivePaceTableFromGoal`, race-equivalence ratio table,
  `TRAINING_MP_SPEED_RATIO`)
- `RunningLog/RunningLog/Workouts/PaceCalculator.swift` — iOS-side
  pace ratios; must stay in sync with `workout-helpers.ts`
- `docs/specs/coachable_moment.md` — V1 spec for the synthesis surface
- `outputs/` — design artifacts from the May 2026 sprint
- `outputs/maya-data-aware-journey-2026-05-28.md` — foundational doc on
  how the product creates a data-aware journey by fusing qualitative
  voice memos with quantitative training data. **Read before any
  athlete-facing design or engineering decision.**
- `outputs/maya-product-roadmap-2026-05-28.md` — Maya's roadmap +
  decisions log (30+ design calls). Phase sequencing, open questions,
  workout-type taxonomy, IA decisions.
- `outputs/product-state-2026-05-28.md` — the product as a whole:
  wedge, what ships today, what's missing/broken, five pillars
  status, next 6 months.
- `supabase/functions/_evals/` — eval harness (README, runner, rubric
  primitives, Gemini provider, custom checks). Cassettes under
  `_evals/cassettes/<prompt-name>/`.
- `outputs/race-performances-feature-plan.md` — race anchoring spec.
  Phase 2 of Maya's roadmap.
- `outputs/profile-table-audit-2026-05-22.md` — 7-phase punch list
  for the `user_profiles` cleanup. Phase 5 of Maya's roadmap.

# Beta Design Overhaul Plan — 2026-07-13

Owner: Rio. Drafted with Fable after a full audit of the shipping iOS
surfaces. This is the consolidation-and-hierarchy plan that takes the app
from its current 7-tab evaluation sprawl to a coherent beta built around
the feedback loop: **qualitative signal (voice memos, mood, niggles) ×
quantitative data (paces, volume, ACWR, heat, dewpoint, elevation,
recovery) × two advisors (human coach + AI), with the athlete deciding.**

Supersedes nothing; extends `maya-product-roadmap-2026-05-28.md` Phase 3
with what the code actually looks like as of today.

---

## 1. Where the app actually is

The bar renders seven tabs: `Log · Training · Train 2 · Trends · Signal ·
The Read · Plan`. Two of those (Train 2, Signal) are evaluation
prototypes that were shipped *alongside* the surfaces they were meant to
replace and never resolved. The workout detail is similarly forked:
`WorkoutDetailPlate23.swift` (editorial chrome, ~300 LOC) and
`WorkoutRepReceiptView.swift` (~1,120 LOC, the one that actually renders).

The core UX complaint — "the workout pages don't flow" — is structural,
not cosmetic. The receipt view stacks ~12 sections at equal visual
weight: stats → read → HR zones → HR trace → pace trace → cadence →
elevation → splits → comparison → route. Nothing is primary. Weather and
dewpoint (which drive the heat-adjusted pace math) are buried mid-page in
a prose sentence rather than framing the run. The same flat-stack disease
affects Training (chart after chart after chart).

What's genuinely good and must survive: the voice-first Log, The Read's
editorial voice, the Workouts & Reps treatment Rio likes, the
heat/dewpoint pace adjustment, plan import + Join Coach's Plan, and the
early mood × workout correlation prose in Trends.

## 2. IA decision: four tabs, Plan folds into Train

**Decision: ship the beta on the 4-tab IA — `Log · Trends · Train ·
Coach`.** (Rio delegated this call; here is the rationale.)

The case for keeping Plan as a fifth tab is that coach-written programs
are a core beta feature. But a separate Plan tab re-centers the product
on the plan, and the product's foundational framing is journey-centric:
`activePlan == nil` is a first-class state. A tab that's empty or
near-dead for every self-coached athlete without an imported program is
the definition of a surface that shouldn't be load-bearing. Folding Plan
into Train as its calendar layer means: athletes with a coach see planned
and completed work in one place (which is exactly the coach feedback
loop — the plan next to what actually happened next to how it felt);
athletes without one lose nothing. Import Plan / Join Coach's Plan move
to a persistent entry point inside Train (header action + empty-state
CTA), not a buried toolbar menu.

Mental flow: **Log** (input) → **Trends** (overview) → **Train** (detail)
→ **Coach** (synthesis). "The Read" remains the content of the Coach tab;
the tab label becomes `Coach` per the target IA.

## 3. Tab-by-tab: the merges

### Train = Train 2's skeleton + Training's analytics (decided: merge best of both)

Train 2's calendar-first structure wins the layout; Training's analytical
content ports into it. Three modes via segmenter, per the roadmap:

- **CURRENT** — this week as day-rows (Train 2's treatment), today
  emphasized. Planned workout (if a plan exists) beside actual, with the
  pace-zone label as the workout label (`MP 7 mi`, not "Tempo").
- **CALENDAR** — Train 2's month/block grid colored by intensity, coach
  plan layered when present. This is where Plan lives now. Day tap →
  existing DayAnalysisSheet.
- **HISTORY** — Training's analytics: Workouts & Reps (kept, redesigned —
  see §4), 80/20 easy-hard split, volume × pace histogram, felt-vs-planned,
  cycle comparison.

**Environment data becomes readable at the Train level, not just buried
in detail views.** Each completed run row carries a compact conditions
readout (temp/dewpoint glyph + heat-adjusted pace when adjustment ≥
threshold; elevation gain when meaningful). A week footer aggregates:
total climb, hot-run count, heat-adjusted vs raw weekly pace. Recovery
(sleep from HealthKit, plus voice-log fatigue) gets a single quiet
indicator on CURRENT — a readout, not advice, per the v1.5 pillar
sequencing. AI never says "push or pull"; it observes.

Delete: `TrainingTabTwoView` as a separate tab, the old `TrainingTabView`
shell, the Plan tab registration. The merged view keeps
`TrainingAnalyticsViewModel`.

### Trends = Trends' brain + Signal's body (decided: merge best of both)

Trends keeps its structure (THIS WEEK strip → range segmenter → unified
chart → race prediction → GO DEEPER → insights → ask bar) and absorbs
Signal's two best ideas: the pace-spectrum distribution view (as a
mode of the unified chart, using the canonical 10-stop blue ramp from
`PaceSpectrum.swift`) and the stacked daily lanes (volume + ACWR + mood +
niggle dots) as the Over-Time mode.

**This is the correlation surface Rio asked for.** The existing insight
engine ("mood dips a day after the long run", "niggles cluster in
highest-mileage weeks") gets promoted from incidental prose to a named
section: **PATTERNS** — 1–3 AI-surfaced correlations between the
qualitative lane (mood, niggle mentions, memo language) and the
quantitative lanes (workout type, load, heat, climb). Every pattern cites
its numbers (data_depth rule), ships with confidence, and ends in a soft
question, never a directive. The ask bar stays and keeps handing off to
Coach — that's the loop closing: see a pattern → ask about it → Coach
reads the journey through that lens.

Delete: `PaceSignalView` as a separate tab after its two modes are
absorbed.

### Log and Coach — polish only

Log is structurally right. Coach (The Read) needs its stubs finished
(sources panel wiring, niggle timeline link) rather than redesign. One
addition for the dyad case: when a human coach is attached, the Read
acknowledges the coach's plan as context ("your coach has you at 42 mi
this week") — AI advises, coach owns the call, athlete sees both in one
narrative.

## 4. Workout detail: one view, three acts

Kill the fork. `WorkoutRepReceiptView` becomes the single canonical
detail view, restructured from a 12-section flat stack into three acts
with progressive disclosure:

**Act 1 — The run at a glance (no scroll).** Editorial header (date,
distance · time · source), the 4-stat strip, and — promoted from
mid-page burial — a **conditions plate**: temp, dewpoint, heat-adjusted
pace delta, elevation gain. The conditions frame the run before any
chart does, because a 7:40 average on a 68° dewpoint day *is* a
different run.

**Act 2 — The story.** THE READ paragraph (AI observation, feeling-first
when a voice memo exists), then **Workouts & Reps** redesigned as the
hero: splits/intervals table with the pace-zone color ramp on rep rows,
GAP column live (grade-adjusted pace — the JSX intent already specs it),
target-vs-actual when a plan prescribed the session. This is the section
Rio likes; it earns the biggest visual investment.

**Act 3 — The traces, collapsed.** HR zones, HR trace, pace trace,
cadence, elevation/grade, comparison, route become collapsible section
rows (eyebrow + one-line summary stat; tap to expand chart). Default:
all collapsed except the one most relevant to the workout type
(elevation for hilly runs, HR zones for quality sessions). Twelve equal
sections becomes three screens of hierarchy.

Voice-memo content renders inline in Act 2 when present (verbatim
quotes, mood pill, niggle chips) — the qualitative and quantitative
literally on the same page. Honest empty state when absent (hard rule
8: component, never em-dash).

Fix while in there: rename the lying components (`WD23TwoStatStrip`
renders four stats), tokenize the hardcoded tracking/spacing values,
and align to `WorkoutDetailScreen.jsx`.

## 5. Coach-written programs in the beta

Already built and mostly good: Import Plan (text/file/photo) and Join
Coach's Plan (6-char code, 6-section configure). Beta work is placement
and honesty, not construction: surface both from Train's header and
empty states; either wire `subscription_preferences` server-side (AO-2)
or remove the inert configure sections from the sheet — shipping
controls the server ignores is worse than fewer controls; render the
imported plan in CALENDAR with the coach's structure (day roles, mileage
ramp from the 2026-07-03 Phase A work) visible. Program *authoring*
stays on the web coach portal per the adaptive-plan-builder spec — iOS
consumes plans, it doesn't author them in beta.

## 6. The feedback loop, named

The loop the whole beta serves, and which surface owns each arc:

| Arc | Surface |
|---|---|
| Athlete speaks (mood, fatigue, niggles, life) | Log (voice-first) |
| Data lands (pace, HR, heat, dewpoint, climb, sleep) | HealthKit → Train rows + detail |
| Machine correlates the two | Trends PATTERNS + unified lanes |
| AI narrates, asks, never prescribes | Coach (The Read) + detail Act 2 |
| Coach (or athlete) decides, plan adjusts | Train CALENDAR + plan import |
| Next run tests the decision | back to Log |

Every design review question for the beta: does this screen move the
loop, or decorate it?

## 7. Sequencing

**Phase A — Consolidate (the tab cull).** Merge Train/Train 2 and
Trends/Signal per §3, fold Plan into Train, ship the 4-tab bar. Delete
dead tab registrations. Biggest single win for perceived coherence, and
it halves the surface area every later phase must touch. Also stop
rendering 7 live view trees in the ZStack.

**Phase B — Workout detail overhaul (§4).** One view, three acts,
conditions promoted, Workouts & Reps as hero. Highest direct hit on
Rio's stated complaint.

**Phase C — Environment + recovery readability (§3 Train).** Conditions
on run rows, week aggregates, quiet recovery indicator.

**Phase D — PATTERNS correlation surface (§3 Trends).** Promote the
insight engine; new prompt work lands via `_shared/prompt-library.ts`;
if it grows into a golden-family prompt, cassettes before ship (hard
rule 3).

**Phase E — Plan/coach polish (§5) + Coach tab stub completion.**

**Phase F — Token parity sweep.** The design-parity-audit items:
eyebrow font, spacing tokens, primitive extraction. Continuous, but a
dedicated pass closes it.

A–B are the beta's spine; C–D are its differentiator; E–F make it feel
finished. Each phase is independently shippable.

## 8. Guardrails that bind every phase

Predictions as range + confidence, never a point (rule 7). Niggles:
closed vocabulary, verbatim quotes, surface-never-interpret. AI never
recommends stopping training or diagnoses. Three-palette rule: blue =
pace, warm = mood, coral = alert — the new Trends lanes and detail rep
rows must not cross streams. One coral element per visual cluster.
Empty states use the component, never em-dashes. Golden prompts don't
ship without recorded cassettes.

## 9. Open questions

1. Recovery indicator scope for beta — sleep + voice-log fatigue only,
   or wait for v1.5's full surface? (Plan assumes the former.)
2. Does PATTERNS need its own prompt family, or does it extend the
   Trends insight generation already in place?
3. Tab label: `Coach` vs `The Read` — plan assumes `Coach` per target
   IA, but the editorial name has equity. Cheap to change late.
4. `subscription_preferences`: wire AO-2 server-side or trim the sheet?
   (§5 — one or the other, not the status quo.)

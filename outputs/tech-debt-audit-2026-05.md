# Tech debt audit — May 2026

Scope: full app (iOS, web, Supabase edge functions + migrations, ml-service, docs).
Date: 2026-05-12.

## TL;DR — overall rating: **B-  (moderate, manageable, shipping-blocking in three specific places)**

This is a healthy mid-stage codebase. The bones are good: RLS hygiene is real
(no dangling "Allow all" policies in current paths after the 2026-03-13
lock-down), prompts are migrating into a `_shared/prompts/` library, Sentry
is wired on all three surfaces, and the recent design-sprint cuts
(custom-plan-builder, biomechanics, form-check, adaptive-workout, pose
landmarker, legacy `coach` route) have actually been executed — not just
planned.

What pulls the grade down is not sprawl. It's three specific gaps that block
the wedge ("AI advises, never acts") from being credibly shipped:

1. **No eval harness** — the safety guarantee the product depends on is
   currently un-testable. P0.
2. **No CI** — no `.github/workflows`, no `.circleci`. Every push relies on
   local discipline. P0.
3. **Public landing page contradicts the wedge** — it sells "the AI-powered
   training log," not "a coach's nervous system." Marketing debt that
   miseducates every inbound lead. P1.

Everything else is the normal accumulation of an honest 8-month sprint.

---

## Inventory at a glance

| Surface | Size | Tests | Notes |
|---|---|---|---|
| iOS (Swift) | 164 files | 5 test files | Healthy test-to-source ratio is **not** here |
| Web (Next.js) | ~32 route pages | 1 test (`rate-limit.contract.test.mjs`) | Effectively untested |
| Edge functions | 39 functions | 6 test files | 15% of functions have a sibling test |
| Migrations | 82 SQL files | n/a | Append-only discipline is holding |
| ml-service | FastAPI, ~7 files | 0 tests | Small surface; small risk |
| Docs | `docs/` + `outputs/` | n/a | See doc debt section |

App-code TODO/FIXME count: **13** (after excluding `node_modules` and
`.venv`). That's a very low signal — the stale-comment problem doesn't
exist here.

---

## Scored debt items

Priority = (Impact + Risk) × (6 − Effort). Higher = do sooner.

| # | Item | Category | Impact | Risk | Effort | Priority | Phase |
|---|---|---|---|---|---|---|---|
| 1 | No eval harness for LLM prompts | Test | 5 | 5 | 3 | **30** | Now |
| 2 | No CI pipeline | Infra | 5 | 4 | 2 | **36** | Now |
| 3 | Public landing page contradicts wedge | Product/marketing | 4 | 4 | 2 | **32** | Now |
| 4 | Synthesis trigger for `evaluate-coachable-moment` missing | Architecture | 5 | 3 | 1 | **40** | Now (1 migration) |
| 5 | Legal docs (privacy, ToS) full of `TODO`s — 28 total | Compliance | 3 | 5 | 3 | **24** | Now |
| 6 | `parse-*` edge function cluster (4 fns, 1,548 LOC) | Code | 3 | 2 | 4 | **10** | Later |
| 7 | Three remaining inline LLM prompts (`generate-training-plan`, `subscribe-to-plan`, `parse-training-plan`) | Code | 3 | 3 | 2 | **24** | Soon |
| 8 | `outputs/` referenced in CLAUDE.md but 7 of the 8 files don't exist | Docs | 2 | 3 | 2 | **20** | Soon |
| 9 | 18 scratch design markdowns at repo root | Docs | 2 | 1 | 1 | **15** | Soon |
| 10 | Stale worktree `.claude/worktrees/intelligent-robinson-8f48d0` | Code | 1 | 2 | 1 | **15** | Soon |
| 11 | Large files (8 files >1,200 LOC) — `DayDetailSheet.swift` 1,750, `generate-training-plan/index.ts` 2,078, `coaching-agent/index.ts` 1,811 | Code | 3 | 2 | 4 | **10** | Later |
| 12 | Web has effectively zero tests (1 file in `web/tests/`) | Test | 4 | 3 | 4 | **14** | Later |
| 13 | iOS has 5 tests covering 164 source files | Test | 3 | 3 | 4 | **12** | Later |
| 14 | `production-readiness-report.docx` at repo root (binary; rationale lives elsewhere) | Docs | 1 | 1 | 1 | **10** | Later |
| 15 | Two coach surfaces (iOS `Coaching/` ×10 files; web `coach-portal/*`) with no canonical decision documented | Architecture | 3 | 3 | 4 | **12** | Later (decision, not refactor) |
| 16 | Long migration list (82) with no schema diagram or ER doc | Docs | 2 | 2 | 4 | **8** | Later |

---

## What each item actually is

### 1. No eval harness  *(P0, blocking the wedge)*

`CLAUDE.md` says: *"No LLM prompt change ships without running the eval
harness (once the harness exists — currently TBD)."* The harness doesn't
exist. There are no `evals/`, `eval-harness/`, or `prompt-evals/`
directories anywhere in the repo.

This is the load-bearing claim of the product: AI advises, never acts; AI
never recommends stopping training, diagnosing injuries, or making medical
claims; Niggles never gets a diagnosis or severity recommendation. None of
those are testable today. A prompt change to `coaching-agent`,
`injury-analysis`, or any of the 12 functions that ship an LLM call could
violate any of those rules and nothing would notice.

**Fix shape:** a Deno-runnable harness in `supabase/functions/_evals/`
that, per prompt version, runs a fixed cassette of inputs through the live
prompt, scores outputs against a rubric (regex bans for diagnosis
language, structured-output schema checks, golden examples), and writes a
JSON report. Wire it into CI (#2). Start with the four highest-stakes
prompts: `coaching-agent`, `injury-analysis`, `reschedule-plan`, the
Niggles classifier.

### 2. No CI  *(P0)*

No `.github/workflows`, no `.circleci`, no `vercel.json` build hook beyond
defaults. Every push to `main` relies on whoever pushed it having run
their checks locally. With 82 migrations, 39 edge functions, three
languages, and an evening-and-weekend cadence, this will bite.

**Fix shape:** a single GitHub Actions workflow that runs
`deno test supabase/functions/`, `npm test --prefix web`,
`xcodebuild test` (or at least `swift test` against the Models target),
and `pytest ml-service/`. Plus a `supabase db lint`. The cost is a day;
the alternative is a regression that ships to production silently.

### 3. Public landing page contradicts the wedge  *(P1)*

`web/src/app/(public)/page.tsx` ships a headline of: *"The AI-powered
training log."* `CLAUDE.md` is explicit that the wedge is the coach-athlete
dyad and that the product is **a force multiplier for human coaches, not
an AI replacement for them**. The landing page is the first thing every
inbound lead sees and it currently sells the opposite of what the product
does.

This is design/copy debt, not code debt. But it costs every demo and
every cold inbound. Cheap to fix; expensive to leave.

### 4. `evaluate-coachable-moment` has no trigger  *(P0-ish, one-migration fix)*

The rules engine and the entry-point edge function exist
(`_shared/rules/`, `supabase/functions/evaluate-coachable-moment/index.ts`).
A trigger fires `generate-workout-insight` on `training_logs` insert
(`20260428110000_trigger_workout_insight.sql`). **No equivalent trigger
fires `evaluate-coachable-moment`.** Coachable moments — the surface the
synthesis pillar depends on — only fire on the cron path, not on the
inserts that should drive them.

**Fix shape:** mirror `20260428110000_trigger_workout_insight.sql` against
the same `training_logs` insert (and likely `voice_logs` insert), call
`evaluate-coachable-moment` via `pg_net`. One migration. The migration
template is right there.

### 5. Legal docs TODO-laden  *(compliance blocker for launch)*

`docs/legal/privacy-policy.md` — 16 `TODO`s. `docs/legal/terms-of-service.md`
— 12. You can't ship a coach-data product, especially one that ingests
voice and HealthKit, with placeholder legal docs. **Fix needs counsel, not
engineering.**

### 6. `parse-*` cluster

Four parsers (`parse-training-plan`, `parse-training-week`,
`parse-workout-shorthand`, `parse-workout-structure`), 1,548 LOC total.
Two of them already share prompts via `_shared/prompts/`. `CLAUDE.md`
flagged this. Collapse to a single dispatcher.

### 7. Three remaining inline prompts

Most prompts have moved into `_shared/prompts/*.v1.ts`. Still inline:
`generate-training-plan` (2,078 LOC — the largest edge function),
`subscribe-to-plan`, `parse-training-plan`. These are the hardest to move
because they're the most logic-coupled, but they're also the ones with
the highest blast radius if a prompt change goes sideways. Move them
before they grow further.

### 8. `outputs/` references in CLAUDE.md point at files that don't exist

`CLAUDE.md` cites `outputs/feature-inventory-keep-cut.md`,
`outputs/five-pillars-and-weather-calc.md`,
`outputs/marathon-prediction-honesty.md`, `outputs/body-mentions-design.md`,
`outputs/new-user-action-plan.md`, `outputs/production-readiness-rundown.md`,
`outputs/plan-mutations-and-race-design.md`. Of those, **zero exist on disk**
(`outputs/` currently contains only `fitness-predictor-audit.md`,
`fitness-predictor-scenarios.md`, and this audit). Either restore them
from somewhere or stop pointing at them — `CLAUDE.md` is the AI assistant
orientation doc and is currently sending every assistant on a goose
chase.

### 9. 18 scratch markdowns at the repo root

`adaptive-plan-builder-rework.md`, `adaptive-plan-loop-design.md`, etc.
These look like sprint scratch and design exploration. Move to
`docs/sprints/2026-04/` or delete. Right now the root of the repo
looks like an inbox.

### 10. Stale worktree

`.claude/worktrees/intelligent-robinson-8f48d0/` is present. `CLAUDE.md`
warns assistants not to source from these; better to delete them.

### 11. Eight files over 1,200 LOC

Notable: `RunningLog/Training/DayDetailSheet.swift` (1,750),
`supabase/functions/generate-training-plan/index.ts` (2,078),
`supabase/functions/coaching-agent/index.ts` (1,811), `_shared/athlete-state.ts`
(1,575). These aren't crises yet, but `generate-training-plan` and
`coaching-agent` will become difficult to test (#1) and review without
splitting. Track but don't fix yet.

### 12 + 13. Test coverage  *(structural; tackle alongside #1)*

Don't go for a coverage number. Instead: every new rule in
`_shared/rules/` ships with a unit test (already the model — keep it).
Every new edge function ships with at least a smoke `index.test.ts`.
Web gets a Playwright happy-path suite for the four most-touched routes
(onboarding, coach portal, log, plan).

### 14. Binary `.docx` at repo root

`production-readiness-report.docx` is binary, undiffable, and the
rationale it contains belongs in markdown in `outputs/` or `docs/`.
Convert and delete the binary.

### 15. Two coach surfaces, no canonical decision

iOS `Coaching/` (10 files, working chat sheets, weekly report flow) and
web `coach-portal/*` (athletes, plans, workouts) both exist and both
work. `CLAUDE.md`'s "three surfaces, none canonical" claim is now
**two surfaces** (the legacy `(app)/coach` route is already gone — that
debt was paid). But the strategic decision about whether iOS coaching is
"v1 for coaches running their own training" or just the athlete-side of
the dyad is still un-made. This is a product decision, not a refactor.
Park it until the wedge is shipped.

### 16. No schema diagram

82 migrations and no ER doc. Onboarding pain. `dbml`-generate from
the current schema and check it into `docs/`.

---

## Phased remediation plan

This is paced to run alongside feature work, not instead of it. Two
threads: a **safety thread** (items that block the wedge) and a **hygiene
thread** (everything else). Pull from both.

### Phase 1 — next 2 weeks  *(safety thread only)*

| Day | Item | Effort | Owner |
|---|---|---|---|
| 1–2 | Add CI workflow (#2) covering Deno, Next, ml-service, swift tests | 1.5d | infra |
| 2 | One-migration fix for `evaluate-coachable-moment` trigger (#4) | 0.5d | backend |
| 3–7 | Eval harness scaffold (#1) — runner + rubric + cassettes for `coaching-agent`, `injury-analysis`, `reschedule-plan`, niggles classifier | 5d | backend |
| 6–8 | Landing page rewrite (#3) to coach-athlete-dyad wedge | 2d (with design) | web |
| 9–10 | Legal docs (#5) — counsel review, fill the 28 TODOs | counsel + 1d eng | legal |

End of phase 1: the wedge is testable, CI guards regressions, the
public message no longer contradicts the product, and the synthesis
pillar actually fires on real inserts.

### Phase 2 — weeks 3–4  *(hygiene)*

| Item | Effort | Why |
|---|---|---|
| #7 — move remaining 3 inline prompts to `_shared/prompts/` | 1.5d | Unblocks broader eval harness coverage |
| #8 — fix `CLAUDE.md` references or restore the 7 missing `outputs/` docs | 0.5d | Cheap, immediate assistant-quality win |
| #9 — relocate the 18 root markdowns into `docs/sprints/...` | 0.5d | One PR, end of inbox |
| #10 — delete stale worktrees | 0.1d | One-liner |
| #14 — convert `.docx` to markdown, delete binary | 0.3d | Diffable |
| #16 — generate dbml schema diagram | 0.5d | Compounding onboarding value |

### Phase 3 — weeks 5–8  *(structural, alongside features)*

| Item | Effort | Why |
|---|---|---|
| #6 — collapse `parse-*` cluster to one dispatcher | 3d | Removes 1,548 LOC of overlap, one place to fix bugs |
| #12 — Playwright happy-path on web (onboarding, coach portal, log, plan) | 4d | Catches Next.js route regressions before customers do |
| #13 — expand iOS test target for `Models/`, `Workouts/PaceCalculator`, `Analysis/FitnessPredictorService` | 3d | Three highest-blast-radius pure-logic modules |
| #11 — split `generate-training-plan` and `coaching-agent` (do **with** prompt-library extraction, not before) | 5d | Don't refactor before eval coverage |

### Phase 4 — quarter cadence

| Item | Effort | Why |
|---|---|---|
| #15 — coach-client canonical decision | strategic | After wedge ships and v1 numbers are in |

---

## Business justification (single page for a stakeholder)

The wedge — "a coach's nervous system that surfaces coachable moments;
AI advises, never acts" — is differentiated **only if** it actually
behaves that way under load. Today, the three things that would prove it
behaves that way (eval harness, CI, synthesis trigger firing) are
missing. The cost of fixing all three is about 8 engineering days. The
cost of not fixing them is a single Niggles output that says "could be
ITBS, ice it tonight" reaching a customer and torching the wedge.

Everything else on this list is hygiene. Don't trade it against
shipping. Schedule one hygiene day every two weeks and the list drains
in a quarter.

Overall rating reaffirmed: **B-**. Healthy codebase, three specific
shipping-blocking gaps, no systemic rot.

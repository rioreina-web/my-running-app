# Codebase review — Post Run Drip

**Date:** 2026-04-25 · **Reviewer:** Rio (synthesis via Claude).

This is a holistic read based on what I directly touched or audited this
session: iOS Training/, web /plan + coach-portal, ~25 edge functions in
`supabase/functions`, the migrations directory, and the docs/ tree.

It is *not* a static-analysis pass — I haven't run linters, dependency
audits, or coverage reports. Treat it as a senior eng's gut read after
two days in the codebase.

---

## TL;DR

**Overall: B+ / A−.** Materially better than typical pre-launch one-person
codebases. Real engineering shows up in the comments, the migration
discipline, the multi-shape decoders, and the dependency-injection pattern
in edge functions. Two areas need cleanup before scale: **the pace system
(known, in progress)** and **transactional integrity across multi-table
writes**. The biggest risk isn't any one bug — it's bus factor and the
slow accumulation of "we'll fix this later" comments that never get
revisited.

---

## Grades by area

| Area | Grade | One-line read |
|---|---|---|
| Code quality / readability | **A** | Comments are exceptional. Almost every non-trivial function explains *why*, not just *what*. Rare and valuable. |
| Architecture / boundaries | **B+** | Clean tier separation (iOS → edge fns → Postgres). Some over-coupling between Adaptive Builder, AIPlanChatSheet, WorkoutChatSheet via `AITrainingPlanService`. |
| Type safety | **B+** | TypeScript well-used on web. Edge functions sprinkle `any`/`Record<string, unknown>` more than they should. iOS is strict. |
| Data model | **B−** | Multiple sources of truth that drift. Pace system has 8 sources (rework in progress). Schema versioning is partly aspirational ("schema_version: v3" coexists with heuristic dayOfWeek detection). |
| Reliability / safety | **B** | Auth is thoughtful. Orphan-cleanup logic exists. No transactions across multi-step writes — partial failures leave inconsistent state. A few TOCTOU races. |
| Test coverage | **C** | Pattern is right (deps injection, mockable handlers). Coverage is sparse — `subscribe-to-plan/index.test.ts` exists, most others don't. iOS tests not visible. |
| Documentation | **A** | `docs/` tree is excellent — pace-system-rework, athlete-plan-ux, build-adaptive-plan-suspension, deploy.md. Migrations are SOX-style commented. Real working docs, not "read the code." |
| Operational maturity | **C+** | No visible CI/monitoring. Errors go to `console.log` → Supabase logs. No structured logging, no Sentry tags I could find, no per-user feature flags. |
| Brand / design system | **A−** | Cohesive: `Color.drip.*` on iOS, `var(--color-*)` on web, editorial display fonts everywhere. Visible coherence is rare at this stage. |
| Forward compatibility | **B** | Versioned migrations, multi-shape decoders (PlannedWorkoutStep handles 4 incoming shapes), but some "v3" labels are aspirational. |

---

## Strengths — things you genuinely got right

**1. Comments are A-tier.** This is the single most underrated thing about
the codebase. Almost every nontrivial function has a multi-paragraph
header explaining the *why*: what the bug was, what other approaches
failed, what's intentional. Examples:

- `parseLocalDate` in plan/page.tsx — explains why `new Date("YYYY-MM-DD")` was wrong
- `personalizeWorkoutData` in subscribe-to-plan — explains why we stopped flattening (ID collision in SwiftUI ForEach)
- `PlannedWorkoutStep.init(from:)` — documents the 4 incoming shapes and the priority order, line by line
- Migration file headers — every migration explains why it exists

This is what mid-career engineers do and most startups skip. Keep it.

**2. Multi-shape decoder pattern.** `PlannedWorkoutStep` handles legacy
iOS, web/AI, Phase-1 flat, and coach-authored M:SS string formats with a
clear priority order. That's mature defensive coding — most teams would
rage-quit and force a migration. You let four shapes coexist safely.

**3. Dependency injection in edge functions.** `Deps` interface,
`defaultDeps` constant, tests inject mocks. Standard SOLID, rarely seen
in Supabase codebases. Made the code-review fixes today possible without
touching production paths.

**4. Migrations are dated and well-headed.** `20260417600000_plan_adjustments.sql`
has a multi-paragraph SOX-style header explaining the table's purpose,
key invariants, and how it relates to `auto_applied`. Most teams' migration
files are bare DDL. Yours read like ADRs.

**5. Edge function `_shared/` factoring is real.** `auth.ts`, `paces.ts`,
`pace-heat-adjustment.ts`, `weeklyAnalytics.ts`, `athlete-state.ts` — 22+
shared utilities. Not just convenience: changes propagate to all callers
consistently.

**6. The adaptive-plan loop actually works.** `reconcile-log → adapt-plan →
plan_adjustments` with Postgres triggers and `pg_net` for event delivery is
real event-driven architecture. Most "adaptive" plan products fake this
with a daily cron. You did it correctly.

**7. Brand voice through the data layer.** Pace-zone names match across
iOS/web/edge. Color tokens consistent. Even comment style is recognizable.
That kind of cross-platform coherence usually requires a second person to
enforce; you did it solo.

**8. Multi-model LLM router with fallback.** Hedges against vendor
deprecation, price changes, latency. Forward-thinking — most pre-launch
products lock to one provider.

---

## Weaknesses — things to pay down

**1. Pace system fragmentation. 🔴**

The most fragile area in the codebase. `pace-system-rework.md` lists 8
sources of pace truth. Even after today's fixes (Phase A complete,
subscribe-to-plan cleaned up), you still have:

- `user_profiles.easy_pace_*` columns (deprecated, no readers but not dropped)
- `athlete_state.pace_zones` (deprecated source #3 — fixed today in subscribe-to-plan, may have other readers)
- Two zone systems still partially diverged (iOS NamedPace ↔ web PaceZone)
- LT and HM sometimes treated as same zone, sometimes distinct

Phase B-E of the rework doc is the right plan; what's missing is a
deadline. **Recommend: complete Phase E (drop deprecated columns) within
14 days** — every day they exist is a chance someone (you in three weeks)
queries them again.

**2. No transactions across multi-step writes. 🔴**

`subscribe-to-plan` writes `training_plans`, `scheduled_workouts`,
`quality_session_templates`, `athlete_plan_subscriptions` sequentially.
Manual rollback (`delete training_plan on workout failure`) covers ONE
failure mode. The orphan-cleanup at the top covers another. What's not
covered: subscription insert fails after plan + workouts succeed. Plan
exists, athlete can see it, but no subscription row to track the
relationship. Same pattern is in the adapt-plan path and probably others.

**Fix:** wrap multi-table writes in a Postgres stored procedure invoked
via RPC. Single round trip, atomic. Or use Supabase's RPC + `BEGIN; …
COMMIT;` pattern.

**3. Magic strings everywhere.**

`"coach_locked"`, `"easy_fill"`, `"scheduled"`, `"active"`, `"adaptive"`,
`"fixed"`, `"rest"`, etc. Used as both DB enum values AND TypeScript
discriminants AND comparison literals. One typo corrupts state silently.

**Fix:** TS enums, exported from `_shared/types.ts`. Same for iOS — `enum
SubscriptionSource: String { case coachLocked = "coach_locked"; … }`.

**4. Some functions are too long.**

- `subscribe-to-plan/index.ts` `handler` — 480 lines
- `plan-builder-client.tsx` — 1050 lines  
- `WorkoutDetailView.swift` `WorkoutStepRow` body — ~200 lines (made longer by today's edit)

Decomposition opportunities are obvious. None of them are blocking, but
each long function carries a higher chance of regression on the next
edit.

**5. Schema-versioning is partly aspirational.**

`workoutData.schema_version: "v3"` exists, but `subscribe-to-plan` has a
heuristic for detecting 0-indexed vs 1-indexed `dayOfWeek` ("if any value
≥ 7, it's 1-indexed"). That heuristic only exists because data isn't
strictly versioned. Either commit to schema versioning (dispatch on
`schema_version`, fail loudly on unknown) or drop the field.

**6. Operational gaps.**

- Console-log debugging in edge functions instead of structured logs
- No visible CI/CD pipeline (deploys are manual `supabase functions deploy`)
- No feature flags / per-user gating
- No ad-hoc incident playbook beyond `docs/deploy.md` (which is good but assumes the deploy succeeded)

These don't matter at zero users. They will matter at 100.

**7. Test coverage is sparse.**

`subscribe-to-plan/index.test.ts` is well-shaped but probably the
exception. iOS test bundles not visible in this session. Most edge
functions are untested. Recommend: write tests when you fix bugs (you've
been doing this), aim for "every fix gets a test" not "100% coverage."

**8. Single-operator bus factor.**

Code quality is high BECAUSE Rio wrote it. Code quality is also high IF
ONLY Rio reads it. Onboarding a second engineer would still take weeks
even with the docs. This isn't a code problem — it's a process problem
worth being honest about.

---

## Risks — what could bite at scale

**1. Pace drift between editor and athlete view (mitigated today).**
Was the active bug; the resolveAthletePaces helper closes the source-of-truth
gap. Watch for new readers of deprecated sources sneaking in.

**2. Race conditions on subscription / rebuild.** TOCTOU on the
"existing subscription" check. Athlete-state rebuild has advisory-lock
serialization (good), but no equivalent on subscribe-to-plan. Add a
`UNIQUE (plan_template_id, athlete_user_id) WHERE status = 'active'`
constraint and treat 23505 as "already subscribed."

**3. Trigger-driven invalidation can deadlock.** Postgres triggers + pg_net
are powerful but a circular trigger graph (training_log → athlete_state
rebuild → triggers another invalidation) could lock-storm under load. You
have advisory locks; verify they cover all entry points.

**4. Multi-platform decoder drift.** PlannedWorkoutStep handles 4 shapes
today. If iOS adds a 5th and web adds a 6th, the cross-product becomes
unmaintainable. Centralize on one shape per producer (web, AI, edge,
import) with a strict version field.

**5. Edge function cost ceilings.** Multiple LLM-touching functions
(generate-day-rationale, adapt-plan, coaching-agent, AIPlanChatSheet
backend). No visible per-user spend cap. A misbehaving client could spike
cost. Recommend: rate-limit at the route, not just the function.

---

## Recommendations — ordered by ROI

**Within 7 days:**

1. **Add `UNIQUE (plan_template_id, athlete_user_id) WHERE status = 'active'`** on `athlete_plan_subscriptions`. Closes the TOCTOU race.
2. **Wrap subscribe-to-plan in a Postgres transaction** (single RPC stored proc). The adapt-plan path will benefit from the same pattern.
3. **Validate `startDate`** at the edge fn entry. `if (isNaN(rawStart.getTime())) return errorResponse(...)`.

**Within 14 days:**

4. **Finish pace-system-rework Phase E.** Drop `user_profiles.easy_pace_*`, `tempo_pace`, etc., and `athlete_state.pace_zones`. Audit one more time for stragglers, then migrate.
5. **Replace magic strings with TS enums** for `SubscriptionSource`, `WorkoutType`, `PlanType`. iOS Swift enums already exist for some — mirror them.
6. **Add structured logging** to edge functions. Even just JSON.stringify with a function-name + user-id prefix would 10× the debuggability of production issues.

**Within 30 days:**

7. **Decompose `subscribe-to-plan` into `materializeFixedPlan` and `materializeAdaptivePlan`** helpers. Two functions of ~150 lines each instead of one 480-line handler.
8. **Decompose `plan-builder-client.tsx`.** It's the coach's editor; currently 1050 lines. Pull `WorkoutPicker`, `WeekStrip`, `PaceAnchorSection` into separate components.
9. **Test coverage for the critical edge fns**: `subscribe-to-plan` (✓ partial), `reconcile-log`, `adapt-plan`, `coaching-agent`. Each gets a happy-path + 2 failure paths.

**Within 90 days:**

10. **Feature flags.** Even a simple env-var-driven toggle would let you ship to 5% of users and watch metrics before going 100%.
11. **Sentry / error monitoring** with sourcemap upload for web and dSYM for iOS.
12. **One-page incident runbook** beyond `deploy.md` — the "what to do when something breaks at 11pm" doc.

---

## What you should NOT do

- **Don't rewrite the pace system from scratch.** The rework plan is good; finish it. Greenfield rewrites look productive and aren't.
- **Don't add a queue / job runner** until you have 1,000 users. Postgres + edge functions + cron is fine at your scale.
- **Don't pre-emptively split the edge functions into a separate Node/Express service.** Supabase edge fns are correct here.
- **Don't generalize prematurely.** Several places have just-in-time abstractions ("PlanGenerator covers all sports!"). Resist. You sell running coaching, not multi-sport.

---

## Bottom line

You have a B+ codebase that's running on A-grade documentation and a
C-grade ops setup. **Pay down the ops gaps before user count goes
non-trivial.** Pay down the pace system gaps before they bite a user.
Don't pay down anything else until you have evidence it's bleeding.

The biggest single risk isn't a bug — it's the bus factor. The codebase
is highly legible *because of* you. Get a second pair of eyes on the
critical-path code before launch, even informally. A two-hour code-walk
with a friend who runs would be high-leverage.

---

*Companion docs:*
- `pace-system-rework.md` — the in-flight cleanup
- `docs/competitive-brief-2026-04.md` — what you're building against
- `docs/build-adaptive-plan-suspension.md` — explicit "what we paused and why"
- `docs/athlete-plan-ux.md` — the missing surface
- `docs/deploy.md` — the runbook

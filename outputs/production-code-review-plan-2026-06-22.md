# Production Code-Review Plan — 2026-06-22

How to review this codebase for production **efficiently** — without reading
all 145k lines of code by hand. The strategy: let the machines do the broad
sweep, then point focused human/AI review only where the blast radius is high.

Grounded in the actual tree (not the CLAUDE.md narrative, which has drifted)
and in the audits already on disk. This plan **does not re-audit** what's
already been audited; it sequences the existing findings into a review you
can actually finish, and adds review only where there's a gap.

## What's already been done (don't redo these)

These exist in `outputs/` and `docs/` — read them first, treat them as inputs:

- `tech-debt-audit-2026-06-16.md` — scored, prioritized tech-debt table (14 items). The most current survey.
- `200-user-production-hardening.md` + `200-user-hardening-dashboard-checklist.md` — the minimum-viable launch ADR.
- `security-and-scale-1000-users.md` — security + scale review.
- `SECURITY-CHANGES.md` — security work already landed.
- `profile-table-audit-2026-05-22.md` — the `user_profiles` cleanup punch list.
- `athlete-state-refactor-design.md` — the plan for the 2,551-LOC hotspot.
- CI tooling already wired: `.github/workflows/{ci,deploy,drift-detector,record-evals}.yml`
  and `.github/scripts/check_{eval_coverage,function_drift,migration_drift,design_tokens}.py`.

The review plan below is the **ordering and method** that turns those into a
go/no-go decision.

## Guiding principles

1. **Review by blast radius, not by line count.** A bug in RLS or a migration
   can leak or destroy every user's data. A bug in a Swift view annoys one
   user. Spend review budget accordingly.
2. **Machines first, humans second.** Linters, the drift detectors, Supabase
   advisors, and the eval harness find whole categories of problems in
   minutes. Run them before any manual reading.
3. **Anchor every review to the hard rules.** CLAUDE.md's 9 hard rules are
   the product's non-negotiables (RLS-per-table, AI-never-acts, eval gate,
   service-role inserts, append-only migrations, range+confidence). Each is a
   concrete checklist item below.
4. **One reviewer per area, in parallel.** The four surfaces (iOS, edge
   functions, web, migrations) are independent enough to review concurrently.

## Phase 0 — Run the machines (½ day, do this first)

Cheapest, highest-yield. Nothing here requires reading code.

- Run the full CI locally / on a branch: `ci.yml`, plus the three drift
  detectors (`check_function_drift`, `check_migration_drift`, `check_design_tokens`).
- Run the **Supabase advisors** (security + performance lint) against the prod
  project. This flags missing RLS, exposed tables, and unindexed foreign keys
  automatically.
- Run the **eval harness** (`supabase/functions/_evals/`) on every prompt you
  intend to ship. Coverage is partial — note which prompts have no cassette;
  those are review gaps, not passes.
- Build everything: iOS build, `tsc` on edge + web, `ml-service` tests.
- Capture the output. Everything that fails here is a finding you didn't have
  to find by hand.

**Exit:** a list of machine-found issues, and a clear map of where the machines
are *blind* (e.g. web has 0 tests — the machine can't vouch for it).

## Phase 1 — Security & data-loss review (highest priority)

The only two things that can't be undone after launch: a data breach and data
loss. Review these before anything else.

- **RLS on every table** (hard rule #1). Enumerate all tables; confirm each has
  RLS in its creating migration, no "Allow all" placeholder reaches prod. Pay
  special attention to coach-scoped policies using `current_coach_id()` (hard
  rule #6) — the recursion fix in `20260311120000` is the reference.
- **Service-role key containment** (hard rule #4). Confirm the service-role key
  is never bundled in the iOS app or web client. All `coachable_moments`
  inserts go through service-role edge functions only — no client INSERT policy.
- **Auth boundaries.** Spot-check that edge functions validate the JWT and scope
  queries to `auth.uid()::text`; confirm no `user_id` filter is missing (the
  R3 tenant-leak class of bug from `athlete-state.ts`).
- **Migration safety** (hard rules #5, #9). Migrations are append-only and reach
  prod only via `supabase db push` from a committed SHA. Confirm the ledger is
  reconciled (see `docs/migration-ledger-reconciliation-2026-06-11.md`) and
  PITR / backups are on before the first real user.
- **Secrets & config.** No keys in the repo; Supabase prod off "dev mode";
  GitHub secrets + branch protection set (open blocker per the tech-debt audit).

**Method:** one focused pass over `supabase/migrations/` + `_shared/{auth,cors}.ts`
+ the RLS checklist (`docs/conventions/rls-checklist.md`). This is the single
most important reading session in the whole review.

## Phase 2 — AI safety review (the wedge)

"AI advises, never acts" is the product. A regression here harms athletes, not
just the demo. Review every LLM path against the coaching principles.

- **Niggles classifier** — closed body-part vocabulary, quote verbatim, surface
  never interpret. No diagnoses, no recommended actions, no self-assessed
  severity. Test cases in `outputs/body-mentions-design.md`.
- **`reschedule-plan`** — constrained selection from `WORKOUT_CODES_BY_DAY`,
  never free generation; writes with `auto_applied: false`; rate-limited. This
  is the other high-stakes prompt.
- **Predictions show range + confidence**, never a point estimate (hard rule
  #7). Grep every prediction surface for seconds-precision output.
- **Eval gate** (hard rule #3). Every prompt under `_shared/prompts/` must have
  a cassette under `_evals/cassettes/`. The ~5 still-inline prompts bypass the
  gate (tech-debt item #3) — these are the AI-safety gap. Migrate them to
  `prompt-library.ts` or accept them as known risk.
- **Model sprawl** (tech-debt item #1) — 5 model strings incl. a preview model
  in prod paths. Pin and document the intended model per prompt.

## Phase 3 — Correctness hotspots (data the user trusts)

Maya anchors life decisions on these numbers; wrong math is a silent breach of
trust. Review the few files that carry the most weight.

- **`_shared/athlete-state.ts`** (2,551 LOC). P0 bugs are reportedly fixed (R3,
  R4, R6, R7) with tests in `athlete-state.test.ts` — verify those tests
  actually cover the claims. The structural refactor is deferred; that's fine
  for beta, but read the four P0 fixes carefully.
- **Pace math kept in sync across THREE implementations** —
  `web/.../workout-helpers.ts`, `_shared/paces.ts`, and
  `RunningLog/.../PaceCalculator.swift`. The `oneHourPaceSecPerMile` and
  race-equivalence ratios must match exactly. Diff them; drift here is a real
  bug class.
- **Fitness prediction** — see `outputs/fitness-predictor-audit.md`; confirm
  range+confidence and race-anchor priority over goal time.

## Phase 4 — Reliability & scale (won't block beta, plan it)

From `security-and-scale-1000-users.md` and the tech-debt audit. At 200 users
scale isn't the ceiling — reliability is.

- `athlete_settings` repoint not yet pushed → all athletes default to UTC
  (tech-debt item #2). Push it or accept the known timezone bug.
- Edge-function consolidation (`parse-*` ×4) — don't add to overlap clusters;
  not a blocker.
- Stale 74 MB of worktrees in `.claude/` containing known-buggy code — delete
  so nobody (human or AI) sources from them.

## Phase 5 — Test-debt triage (where the machine is blind)

7 Swift test files for 84k LOC; **0 web tests**. You will not backfill full
coverage before beta — don't try. Add tests only at the highest-trust seams:

1. Pace math (all three implementations) — pure functions, easy to test, high blast radius.
2. RLS policies — a few integration tests proving tenant isolation holds.
3. The two high-stakes prompts — lock current behavior with cassettes.

Everything else: accept as known debt, log it, move on.

## How to execute this efficiently

- **Parallelize Phases 1–3 across four AI reviewers**, one per surface
  (migrations/RLS, edge functions, web, iOS), each handed: the relevant hard
  rules, the matching existing audit doc, and a tight checklist from above.
  They report findings; you don't read the code yourself.
- **Use a findings ledger**, one row per issue: `area | severity | hard-rule |
  file | finding | fix | blocks-launch?`. Severity = blast radius, not effort.
- **Two buckets only:** *blocks beta* vs *known debt (log & ship)*. Resist a
  third "nice to have" bucket — it's where launches go to die.

## Go / no-go gate (the short list)

Ship the beta when, and only when:

1. Every table has real RLS; advisors are clean (Phase 1).
2. Service-role key is not in any client bundle (Phase 1).
3. PITR/backups on; migration ledger reconciled; prod off dev mode (Phase 1).
4. Niggles + reschedule-plan prompts pass evals and obey the guardrails (Phase 2).
5. No prediction surface shows a point estimate (Phase 2).
6. Pace math matches across all three implementations (Phase 3).

Everything else is logged as known debt and shipped. That's the efficient
path: review hard where it's irreversible, accept debt everywhere else.

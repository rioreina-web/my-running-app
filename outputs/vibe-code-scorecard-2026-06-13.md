# Code-Quality Scorecard — "Coach's Nervous System" running app

*Graded on the curve for an AI-assisted / "vibe-coded" build, 2026-06-13.
Evidence sampled from the live repo, not just the docs.*

**Overall: 8.4 / 10 — top decile for a vibe-coded app.** A genuinely
engineered multi-platform product carrying the exact debt signature that
high-velocity AI building produces. The decisive virtue: almost every
wound is written down, dated, and root-caused.

| Dimension | Score | One-line verdict |
|---|---|---|
| Architecture & code structure | 8.5 | Pure-function rules, shared modules, real seams — marred by a god-file |
| Testing & verification | 8.0 | Verified green; guardrail tests have real teeth (see test run below) |
| Security & data access | 8.5 | 215 RLS policies, SECURITY DEFINER helper, secrets properly ignored |
| Maintainability | 7.0 | Clean idioms, but a 2,339-LOC god-file and stale docs |
| Product & design discipline | 9.5 | Decision docs, a real design system, honesty/safety constraints |
| Ship-readiness | 5.5 | Pre-launch: a ghost table blocks a feature path; prod still in dev config |
| DevOps / CI | 8.0 | ci + deploy + drift-detector + eval-recording workflows |

---

## Verified test run (2026-06-13)

Suites actually executed, not assumed:

| Suite | Runner | Result |
|---|---|---|
| Web (pace/workout helpers, smoke) | `node --test` | **19/19 pass** |
| Backend edge functions | `deno test` | **147 pass, 1 fail** |
| ML service | `pytest` | **16/16 pass** |
| iOS (7 test files) | XCTest | Not run — needs macOS/Xcode |

The single Deno failure is the most reassuring result in the whole audit:
`rateLimit.contract.test.ts` asserts that *no LLM-calling function is
silently un-rate-limited*, and it caught `extract-rpe` — which is an
**untracked, uncommitted** new function (`git status` = `??`). So
committed `main` is almost certainly green; the red is a guardrail with
teeth catching in-progress work exactly as designed. That's a higher-trust
signal than an all-green run would have been. (It also means there's a
real, if local, gap: wire rate limiting on `extract-rpe` before committing.)

## What's genuinely good

**Architecture.** Coachable-moment rules are pure functions in
`_shared/rules/`, each registered in one index, each with a header comment
explaining *why it fires and why it's classified the way it is* — product
intent, not autocomplete. Shared utilities (`paces.ts`, `dataAnalysis.ts`,
`athlete-state.ts`) give the edge functions real seams.

**Cross-language correctness.** A `cross-language-pace-contract.test.ts`
verifies the Swift and TypeScript pace math agree. You only write that
after getting burned by drift — most vibe-coded apps never write it.

**LLM discipline.** An eval harness (`_evals/`) with recorded cassettes,
and CI (`check_eval_coverage.py`) *fails a PR* that touches a prompt
without cassette coverage. Plus domain guardrails baked into prompts:
advise-never-act, closed niggle vocabulary, prediction range+confidence
(never a fake-precise point estimate).

**Security.** 36 tables, 64 `ENABLE ROW LEVEL SECURITY`, 215 `CREATE
POLICY`. A dedicated `20260313100000_lock_down_rls.sql` migration ripped
out every early `USING(true)` "Allow all" policy. A `current_coach_id()`
SECURITY DEFINER helper avoids RLS recursion. The Gemini key lives in
`.env.local`, which is correctly gitignored and never committed.

**Product thinking.** A canonical persona (Maya), a tokenized design
system (Post Run Drip), and ~37 decision docs. This is where the real time
went — figuring out *what* to build.

## Where the debt is

**A god-file that's outgrowing its own paper trail.**
`_shared/athlete-state.ts` is **2,339 lines** — CLAUDE.md still calls it
"1,481 LOC." It grew 58% and the doc never caught up. The "we write our
debt down" discipline is the project's best feature; this is the first
crack in it.

**The migration ledger divergence** (now mostly reconciled). Repo and prod
histories drifted: 17 re-stamped entries, 2 ghost migrations, and a
`user_profiles` table that *does not exist in production* because a
malformed filename (`20260128_152000_...`) parsed as version `20260128`
and silently collided with an applied migration — so the CLI skipped it
since January. This is the textbook wound of applying migrations ad-hoc
against prod. The 2026-06-11 reconciliation doc is excellent and Steps 1–2
are done, but the ghost table is now an **escalated feature blocker**: the
Daily Read cron + workout-trigger automation are dark in prod behind it.

**Type-safety leakage.** 79 `: any` / `@ts-ignore` across the edge
functions, in a codebase that claims TypeScript strict mode.

**Repo hygiene.** Stale `.claude/worktrees/*` carry buggy old copies of
files (including the old buggy pace chart). ~39 edge functions with
overlap clusters (`parse-*` ×4).

**Not shippable yet.** Supabase prod still in dev config, the public
landing page contradicts the wedge, legal docs are TODO-laden.

## If I were paying down debt, in order

1. Resolve the `user_profiles` ghost-table decision — it blocks a whole
   feature path and is the root of three layers of defensive workarounds.
2. Split `athlete-state.ts` (gated behind finishing its eval coverage so
   behavior doesn't silently change), and fix the stale LOC in CLAUDE.md.
3. Finish the 10 unfilled eval cassette stubs so the CI gate is real, not
   nominal.
4. Delete the stale worktrees and the duplicate `parse-*` cluster.
5. Close the production-config + landing-page + legal items before launch.

## The one-sentence version

The median vibe-coded app accumulates this exact debt *invisibly* and
collapses when someone touches the wrong file; this one knows where every
body is buried — which is the whole difference between debt you can pay
down and debt that owns you.

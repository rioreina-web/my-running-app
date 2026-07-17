# Tech Debt Audit — 2026-06-16

Scope: full repo (`RunningLog/` iOS, `supabase/` backend, `web/`, `ml-service/`).
Method: structural survey grounded in the actual tree as of this date, not the
CLAUDE.md narrative (several figures below have drifted from it — flagged inline).

## Scale snapshot

| Area | Size | Note |
|---|---|---|
| iOS (`RunningLog/`, Swift) | ~84,000 LOC, 243 files | Largest surface; thin test layer |
| Edge functions (`supabase/functions`, TS) | ~42,000 LOC, 41 functions | `_shared/` carries the weight |
| Web (`web/src`, TS/TSX) | ~16,500 LOC, 90 source files | **0 test files** |
| ml-service (Python/FastAPI) | small, has a real test dir | Healthiest corner |
| Migrations | 116 `.sql` files | Ledger reconciliation history |
| LLM prompts | 16 functions on `prompt-library`, ~5 still inline | Mixed |

## Prioritization

Score = (Impact + Risk) × (6 − Effort), each axis 1–5. Higher = do sooner.

| # | Item | Category | Impact | Risk | Effort | Score |
|---|---|---|---|---|---|---|
| 1 | LLM model sprawl (5 model strings incl. a preview in prod paths) | Architecture | 3 | 5 | 2 | **32** |
| 2 | `user_profiles`→`athlete_settings` repoint not yet pushed; 3 edge-readers still default all athletes to UTC | Infra/Data | 4 | 4 | 2 | **32** |
| 3 | Inline prompts in ~5 edge functions bypass `prompt-library` + the CI eval gate | Code/Test | 4 | 5 | 3 | **27** |
| 4 | Production blockers (Supabase prod in dev mode, GitHub secrets/branch protection unset) | Infra | 4 | 5 | 3 | **27** |
| 5 | 74 MB of stale worktrees in `.claude/` that still contain known-buggy code | Infra/Code | 2 | 3 | 1 | **25** |
| 6 | Duplicate `FitnessPredictorView` vs `FitnessPredictorView_Rebrand` (parallel old/new) | Code | 3 | 3 | 2 | **24** |
| 7 | Migration push discipline (history of re-stamps + ghost migrations) | Infra | 3 | 5 | 3 | **24** |
| 8 | Documentation drift — CLAUDE.md states stale facts | Docs | 3 | 2 | 2 | **20** |
| 9 | `_shared/athlete-state.ts` now **2,551 LOC** (CLAUDE.md says 1,481) w/ P0 bugs | Code | 5 | 4 | 4 | **18** |
| 10 | Test debt — 7 Swift test files for 84k LOC; **0 web tests** | Test | 4 | 5 | 4 | **18** |
| 11 | `parse-*` ×4 duplication cluster | Code | 3 | 2 | 3 | **15** |
| 12 | Oversized Swift views (5 files > 1,300 LOC, top 1,779) | Code | 4 | 3 | 4 | **14** |
| 13 | Two live coach surfaces, neither canonical, both deprioritized | Architecture | 2 | 2 | 3 | **12** |
| 14 | IA drift (5 tabs shipped vs 4-tab target) + iOS design-system parity gaps | Code/Design | 3 | 2 | 5 | **5** |

## Top items — detail and justification

**1. LLM model sprawl.** Across edge functions the model string is hardcoded in
many places: `gemini-2.0-flash`, `gemini-2.0-flash-lite`, `gemini-2.5-flash`
(51 refs), `gemini-2.5-pro`, and `gemini-3.1-pro-preview` (9 refs). A *preview*
model in production paths is a silent-breakage and cost risk — preview endpoints
change behavior and get deprecated without notice, and every prompt riding one is
un-pinned. *Fix:* centralize model selection in one config constant per tier
(fast/pro/embedding); ban preview strings outside an explicit experiment flag.
Low effort, high risk-reduction.

**2. `athlete_settings` repoint not pushed.** Per the ghost-table resolution doc,
the Daily Read cron + workout trigger were repointed onto `athlete_settings`, but
the migrations are *authored, not yet `db push`ed*, and `fetch-workout-weather`,
`post-run-reconciliation`, and `reconcile-log` still read the old surface — so
**every athlete currently defaults to UTC**. This is a correctness bug affecting
weather, reconciliation, and run-time logic for anyone outside UTC. *Fix:* push the
pending migrations, repoint the three remaining readers, add an iOS/web timezone
writer.

**3 & 10. Inline prompts + the eval gate.** CI now fails a PR touching
`_shared/prompts/` without a cassette — good. But ~5 functions
(`generate-training-plan`, `extract-rpe`, `ingest-documents`, `parse-training-plan`,
and the `_shared/router.ts`) still call the model with inline prompts, so they
route *around* both `prompt-library` and the coverage gate. Combined with 0 web
tests and only 7 Swift test files against 84k LOC, behavioral regressions can ship
unseen. Eval coverage itself is actually *better* than CLAUDE.md claims — 9
cassettes now exist (daily-read v3/v4/v5, 3 coaching-agent tiers, injury, memo,
reschedule), not 4. *Fix:* migrate the 5 inline callers into `prompt-library`,
backfill their cassettes; stand up a minimal web test harness (Vitest) starting
with `workout-helpers.ts` pace math, which is safety-critical and mirrored in 3
languages.

**4 & 7. Infra / migration discipline.** The lock-down work is real and largely
done — `20260313100000_lock_down_rls.sql` issues 79 `DROP POLICY` and the remaining
`USING (true)` policies are intentional public reads (blog/content). So the
historical "Allow all" RLS debt is **mostly remediated** — good news worth stating.
The open infra items are environmental: prod still in dev config, secrets/branch
protection not set, push-only-from-committed-SHA discipline not yet enforced by
tooling.

**5. Stale worktrees.** `.claude/worktrees/` is 74 MB and holds the old
seconds-offset pace-chart bug among other superseded code. It's a sourcing hazard
(easy to grep into the wrong copy) and pure weight. *Fix:* delete; add to
`.gitignore` if not already ignored.

**6 & 12. iOS code debt.** `FitnessPredictorView` and `FitnessPredictorView_Rebrand`
coexist (a rebrand done as a parallel file, not a replacement). Five views exceed
1,300 LOC (`WorkoutAnalysisView` 1,779, `DayDetailSheet` 1,750,
`FitnessPredictorService` 1,634, `VoiceLogView` 1,391, `WorkoutModels` 1,374).
These are hard to test and review. *Fix:* delete the superseded predictor view once
parity is confirmed; extract sub-views/view-models from the >1,300 LOC files
opportunistically when next touched.

**8. Doc drift.** CLAUDE.md is the orientation doc but understates `athlete-state.ts`
(1,481 vs actual 2,551) and eval cassette count (4 vs 9). When the map is wrong, new
contributors mis-estimate. *Fix:* refresh those figures; consider a make target that
prints current LOC for the files CLAUDE.md cites.

## Phased remediation plan (alongside feature work)

**Phase A — correctness & cheap wins (this week, ~1–2 days)**
Push the `athlete_settings` migrations and repoint the 3 UTC-defaulting readers (#2);
centralize the LLM model constant and purge the preview string from prod (#1); delete
the stale worktrees (#5); refresh the drifted CLAUDE.md figures (#8). All low-effort,
high-leverage; none blocks a feature branch.

**Phase B — guardrails (next 2–3 weeks)**
Migrate the ~5 inline-prompt callers into `prompt-library` with cassettes (#3); add a
Vitest harness for web and cover `workout-helpers.ts` pace math first (#10); finish
the prod-config + secrets + branch-protection checklist and enforce push-from-SHA (#4,
#7). Do these as their own small PRs between features.

**Phase C — structural (opportunistic, 1–2 quarters)**
Land the `athlete-state.ts` refactor now that eval coverage exists to protect it (#9);
collapse `parse-*` ×4 behind one router-dispatched parser (#11); retire the duplicate
`FitnessPredictorView_Rebrand` and chip away at the >1,300 LOC views when touched (#6,
#12); resolve the dyad-vs-Maya call before deepening either coach surface (#13); ship
the 4-tab IA + design parity as part of the planned Phase 3 (#14), not as standalone
debt work.

## What's *not* debt (don't spend here)
Dependencies are current (Next 16, React 19, TS 5.9; ml-service pinned to recent
scikit/xgboost). RLS lock-down is done. Eval harness exists and is CI-gated. The real
exposure is operational (UTC default, prod config, model pinning) and a few code hot
spots — not a rotting dependency tree.

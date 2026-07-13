# Dead Code Report — 2026-06-22

Heuristic reachability scan across all four surfaces. "Dead" = no live call
path reaches it (not registered/imported/invoked, not an entry point, not a
test/preview). Candidates are rated HIGH / MEDIUM / LOW. Nothing here is
removed yet — this is the kill list for you to approve.

**Headline:** ~22 high-confidence dead files in the shipped tree
(~6,800 LOC of Swift alone), 11 dead prompt files + 2 dead shared modules in
the backend, 9 never-imported web modules, and ~123 MB of stale local
worktrees. Plus one item that's worse than dead code — a live iOS call to a
**deleted** edge function (a broken feature, flagged separately below).

## Confidence legend

- **HIGH** — referenced nowhere outside itself; safe to delete after a 30-second glance.
- **MEDIUM** — referenced only by tests, a dev-only button, or superseded versions kept by eval cassettes; delete with a little judgment.
- **LOW** — best-effort (member-level dead code); needs a compiler/AST pass to be sure.

Caveat for Swift: the Xcode project uses a synchronized folder group, so these
files still *compile* — they're unreferenced, not unbuilt. SwiftUI/reflection
can hide a usage, so each HIGH file deserves a quick human look before deletion.

---

## ⚠️ Not dead code — a broken feature (fix, don't delete)

**iOS calls a deleted edge function.** `RunningLog/.../Analysis/InjuryService.swift:149`
POSTs to `injury-analysis`, but that edge function was deleted — the call 404s.
The matching prompt (`injury-analysis.v1.ts`) is also orphaned (below). So the
client-side injury-analysis feature is dead-on-arrival. Decide: rebuild the
endpoint, or remove the client feature. (This sits next to the earlier H2/H3
injury findings — the whole injury path needs a cleanup pass.)

---

## Surface 1 — iOS (Swift): 20 HIGH files, ~6,808 LOC

These files build but are never instantiated. Biggest wins first.

| File | LOC | Note |
|---|---|---|
| `Analysis/FitnessPredictorView_Rebrand.swift` | 1,198 | Superseded rebrand; original `FitnessPredictorView` is the live one |
| `Analysis/FitnessAssessmentView.swift` | 717 | Multi-step assessment flow, unreferenced |
| `Coaching/AIPlanChatSheet.swift` | 665 | Part of the cut AI-plan-chat flow |
| `Workouts/WorkoutGeneratorView.swift` | 549 | Cut feature; the ViewModel was kept and is live, the View is dead |
| `Training/JoinCoachPlanFlowMockup.swift` | 466 | Named "Mockup"; never wired |
| `Analysis/InjuryAnalysisComponents.swift` | 261 | (relates to the dead injury-analysis feature above) |
| `Workouts/PaceZoneBarsChart.swift` | 250 | Preview-only |
| `Training/CoachPlanWeekStrip.swift` | 232 | |
| `Workouts/ReconciliationCard.swift` | 208 | |
| `App/LogView.swift` | 194 | Doc-drift: the Log tab is actually served by `VoiceLogView()`, not this file |
| `Training/InsightCard.swift` | 182 | |
| `Training/TrainingTodayHero.swift` | 182 | |
| `App/LogDedup.swift` | 110 | |
| `Workouts/PaceSpectrum.swift` | 82 | |
| `Training/WeeklyMileageQuietRow.swift` | 72 | |
| `Training/BlockTotalsStrip.swift` | 71 | |
| `Training/WeekBlockSegmenter.swift` | 69 | |
| `Shared/AthleteState.swift` | 40 | `AthleteDataDepth` enum, unused (distinct from the live data_depth plumbing) |
| `Training/CoachNoteSection.swift` | 38 | |
| `App/ContentView.swift` | 24 | Verbatim Xcode "Hello, world!" template stub |

Not dead (despite suspicious names): the numbered `Plate18/22/23/28` variants
and `PlanImportService.swift` are all live. No other `_v2`/`Old`/`Legacy`
duplicate pairs found beyond the one `_Rebrand`.

---

## Surface 2 — Edge functions (Supabase): 13 HIGH

**Dead prompt files** (`_shared/prompts/`) — registered in `prompt-library.ts`
but never `loadPrompt`-ed by any live function. Their registry import + entry
lines are also dead and should go with them.

| Prompt | Why dead |
|---|---|
| `fitness-predictor.v1.ts` | Function deleted; also a hard-rule-#7 violation if revived (see prior findings) |
| `injury-analysis.v1.ts` | Function deleted (the broken iOS call above) |
| `training-analysis.v1.ts` | Function deleted |
| `daily-read.v1.ts`, `daily-read.v2.ts` | Superseded by v5; no cassettes, no loader |
| `generate-workout-insight.v1–v4.ts` | Superseded by v5 |
| `parse-workout-structure.v1.ts` | Superseded by v2 |

**Dead shared modules:**

| Module | Why dead |
|---|---|
| `_shared/aiInsights.ts` | Zero importers anywhere |
| `_shared/workoutSelection.ts` | Zero importers; `outputs/workout-system-rebuild.md` lists it for deletion 3× |

**MEDIUM (delete with judgment):**

- `daily-read.v3.ts`, `daily-read.v4.ts` — superseded by v5 but still kept alive by eval cassettes. Remove the cassettes too if you remove these.
- `_shared/workout-classification.ts`, `_shared/pace-grade-adjustment.ts` — imported only by their own tests (the heat twin is wired in; the grade twin never was).
- Function dirs `extract-rpe/` (never invoked — no client/trigger/cron), `ingest-documents/` (manual seed tool), `strava-test-pull/` (dev-only, hardcoded token, behind a dev button). The last two may be intentional dev tooling — confirm before deleting.

---

## Surface 3 — Web (Next.js): 9 HIGH never-imported modules

| File | Symbol |
|---|---|
| `components/charts/workout-type-donut.tsx` | `WorkoutTypeDonut` |
| `components/charts/mood-distribution-chart.tsx` | `MoodDistributionChart` |
| `components/charts/compliance-chart.tsx` | `ComplianceChart` |
| `components/charts/pace-trend-chart.tsx` | `PaceTrendChart` |
| `components/charts/training-load-gauge.tsx` | `TrainingLoadGauge` |
| `components/charts/run-frequency-chart.tsx` | `RunFrequencyChart` |
| `components/coach/plan-assignment-modal.tsx` | `PlanAssignmentModal` |
| `components/coach/adaptive-plan-config.tsx` | `AdaptivePlanConfig` |
| `lib/athlete-state.ts` | `getDataDepth`, `allowsEditorialVoice`, `DataDepth` |

Note: don't also delete `lib/chart-theme.ts` — 3 live charts still import it.
The legacy `(app)/coach` route CLAUDE.md wanted removed is already gone (only
`coach-portal/*` remains); nothing to do there.

---

## Surface 4 — Repo housekeeping (~123 MB, not shipped code)

- `.claude/` (74 MB) and `.perf-worktree/` (49 MB) — stale git worktrees holding
  known-buggy old code. Untracked/local (not in the repo), so this is local
  cleanup: `git worktree remove` / delete the dirs. CLAUDE.md already warns
  never to source from them.
- `_wt_b` — a tracked empty file, leftover. Safe to `git rm`.

---

## Suggested removal order (safest first)

1. **Repo housekeeping** — delete `_wt_b`, prune the two worktrees. Zero risk, frees 123 MB.
2. **Web HIGH** (9 files) — TypeScript; if `tsc`/build stays green after deletion, they were truly dead. Easy to verify.
3. **Edge dead prompts + the 2 shared modules** — delete the files and their
   `prompt-library.ts` import/registry lines together; CI eval gate + `tsc`
   will catch any miss.
4. **Swift HIGH** (20 files) — biggest LOC win. Do it in one branch, then build
   the iOS app once: anything truly referenced will fail to compile and tell you.
   Start with the obvious four (`_Rebrand`, `FitnessAssessmentView`,
   `AIPlanChatSheet`, `WorkoutGeneratorView`) = ~3,100 LOC.
5. **Decide the injury path** — fix or remove `injury-analysis` (broken iOS
   call + dead prompt) as one deliberate change, not a silent delete.
6. **MEDIUM items** — handle case by case; confirm the dev-only functions
   (`ingest-documents`, `strava-test-pull`) aren't part of your seed/ops flow.

Each surface has a cheap proof-of-death: web/edge → `tsc`/build green; Swift →
iOS build green. That's how you delete with confidence without reading every file.

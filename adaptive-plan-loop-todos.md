# Adaptive Plan Loop — TODO Index

**Companion to:** `adaptive-plan-loop-design.md`, `adaptive-plan-loop-prompts.md`
**Tag format:** `TODO(adaptive-plan-X.Y)` where X.Y matches a prompt number in the prompts doc.

## Grep command
```
grep -rn "TODO(adaptive-plan-" RunningLog supabase --include="*.swift" --include="*.ts"
```

---

## Phase 1 — Kill the "115%" crime

| Prompt | File | Action |
|---|---|---|
| 1.1 | *(new migration)* | Create `athlete_pace_profiles` table |
| 1.2 | *(new file)* `RunningLog/RunningLog/Models/AthletePaceProfile.swift` | Create Swift struct |
| 1.3 | *(new edge fn)* `supabase/functions/build-pace-profile/index.ts` | Derive profile from fitness_snapshot + user_goals |
| 1.4 | *(new file)* `RunningLog/RunningLog/Services/AthletePaceProfileService.swift` | iOS cached service |
| 1.5 | **✓ annotated** `RunningLog/RunningLog/Models/PlannedWorkoutModels.swift` | Rework ImportedStep schema |
| 1.5 | *(new migration)* | JSONB step shape migration + backfill |
| 1.6 | **✓ annotated** `supabase/functions/custom-plan-builder/index.ts` | LLM prompt outputs seconds, not % |
| 1.6 | **✓ annotated** `supabase/functions/parse-training-plan/index.ts` | Same |
| 1.6 | **✓ annotated** `supabase/functions/parse-training-week/index.ts` | Same |
| 1.6 | **✓ annotated** `supabase/functions/parse-workout-structure/index.ts` | Same |
| 1.7 | **✓ annotated** `RunningLog/RunningLog/Models/PaceModels.swift` | Delete `displayPercentage` |
| 1.8 | **✓ annotated** `RunningLog/RunningLog/Models/PlannedWorkoutModels.swift` | Remove percentage fallbacks |
| 1.8 | **✓ annotated** `RunningLog/RunningLog/Training/DayDetailSheet.swift` | Stop converting `pacePercentage` at render |
| 1.9 | **✓ annotated** `RunningLog/RunningLog/Workouts/WorkoutTemplateEditorView.swift` | Remove `@AppStorage("paceChart_...")` |
| 1.10 | **✓ annotated** `RunningLog/RunningLog/Workouts/WorkoutGeneratorViewModel.swift` | Stub workouts use profile-derived paces |

## Phase 2 — Reconcile every log

| Prompt | File | Action |
|---|---|---|
| 2.1 | *(new migration)* | `workout_reconciliations` table |
| 2.2 | *(new file)* `supabase/functions/_shared/pace-heat.ts` | Port `calculateDewPointAdjustment` from `PaceCalculator.swift` |
| 2.3 | *(new file)* `supabase/functions/_shared/weather.ts` + migration | Server-side Open-Meteo + cache |
| 2.4 | *(new edge fn)* `supabase/functions/reconcile-log/index.ts` | Core reconciliation |
| 2.5 | *(new migration)* | Postgres trigger on `training_logs` insert |
| 2.6 | **✓ annotated** `RunningLog/RunningLog/Workouts/WorkoutDetailView.swift` | Show reconciliation card |

## Phase 3 — Wire adaptation

| Prompt | File | Action |
|---|---|---|
| 3.1 | *(new migration)* | `plan_adjustments` table |
| 3.2 | *(new files)* `supabase/functions/adapt-plan/index.ts` + `_shared/adaptation-rules.ts` | Rule-based adaptation |
| 3.3 | `supabase/functions/reconcile-log/index.ts` | Wire trigger → adapt-plan |
| 3.4 | *(cron registration)* | Sunday 20:00 weekly rebalance |
| 3.5 | **✓ annotated** `RunningLog/RunningLog/Coaching/CoachTabView.swift` | "Plan updates" surface |
| 3.5 | *(new file)* `RunningLog/RunningLog/Coaching/PlanAdjustmentsView.swift` | The feed itself |
| 3.6 | *(new edge fn)* `supabase/functions/revert-plan-adjustment/index.ts` | Reverse applied diffs |
| 3.7 | **✓ annotated** `supabase/functions/adaptive-workout/index.ts` | Deprecate |

---

## How to work through these

1. **Pick a prompt** from the index above.
2. **Read the relevant section** in `adaptive-plan-loop-prompts.md` (each prompt is self-contained).
3. **Open the annotated file** to see the scoped TODO in context.
4. **Ship the change on a dedicated branch** named `phase-X-<slug>`.
5. **Delete the TODO comment** as part of the PR that resolves it.
6. **Update this index** — change `✓ annotated` to `✓ shipped` (or just delete the row).

---

## Status at creation

All annotated TODOs placed on 2026-04-17. None shipped. The "115%" bug is still live in production.

**First move:** Prompt 1.1 and 1.2 in parallel — no dependencies, both scaffolding for everything else.

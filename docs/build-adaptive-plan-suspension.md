# Build Adaptive Plan — suspended

**Status:** Suspended 2026-04-24. Not deleted — gated behind a hidden UI
path. Will return when the periodization intelligence is real.

**Why this doc exists.** So when someone (you, in three months) asks "why
did we take this out?" the answer is here, not lost in chat history.

---

## What "suspended" means in practice

- The iOS "Build Adaptive Plan" button is removed from the empty state
- The "New Plan" menu item is removed from the toolbar dropdown
- The `showAdaptiveBuilder` state var + `.sheet` presentation are removed from `TrainingPlanView.swift`
- `AdaptivePlanBuilderSheet.swift` (680 lines) **stays in the repo** — no callers, but the scaffolding is worth keeping for the rebuild
- `AITrainingPlanService.swift` **stays** — still powers `AIPlanChatSheet` and `WorkoutChatSheet`
- The `generate-training-plan` Supabase edge function **stays** — still callable from the chat sheets
- Web side has no equivalent feature; nothing to remove there

## The empty state now has two paths, coach first

1. **Join Coach's Plan** (primary) — wired to `JoinCoachPlanSheet`. Athlete enters a 6-char join code the coach shared.
2. **Import Plan** (secondary) — wired to `ImportTrainingPlanSheet`. Athlete pastes / uploads an existing plan.

## Why we killed it

The builder is a thin wizard over a single LLM call. All the
"intelligence" lives in the prompt, not in the app. Specifically:

1. **Fake preview.** Step 3 shows generic "Quality 1, Long Run, Recovery" labels — no LLM call behind it. The athlete commits based on a preview that doesn't match what they'll get.
2. **Zero fitness reality check.** No read of `fitness_snapshot` / `athlete_pace_profile` / recent `training_logs`. A beginner can ask for 2:30 at 80mpw and the LLM will happily return a plan.
3. **Periodization is the LLM's problem.** The wizard collects ONE weekly mileage number. Real marathon plans ramp — the LLM has to invent the shape.
4. **No coach voice.** Generic prompt, no grounding in the coaching corpus, no philosophy. Output reads like "marathon plan #3,847."
5. **No rationales.** Plans ship with `rationale_short` null. (AP-4 fixes this, separately.)
6. **No phase labels.** The LLM may or may not label weeks as base/build/specific/taper.

For a BQ-aspiring runner (50-70 mpw, serious), a mediocre LLM-generated
plan is worse than no plan — it's a trust-breaker at the product's most
important moment.

## What needs to be true before we un-suspend

In priority order:

1. **Real preview with a live LLM call.** Step 3 calls `generate-training-plan` and shows the actual first week. Athlete can re-roll or edit before committing.
2. **Fitness pre-check on Step 2.** Read pace profile + last 4 weeks of training logs. Warn if asked mileage is >20% above the rolling average. Let the athlete proceed anyway, but they see the warning.
3. **Periodization as a real input.** Replace the single mileage slider with a ramp editor (start mileage, peak mileage, taper weeks). Pass the shape to the LLM, don't let it invent.
4. **Coach corpus in the prompt.** `generate-training-plan` pulls from `docs/coaching-corpus/*.md` and injects relevant sections — build-phase principles, taper philosophy, quality session construction — so the LLM plays our game.
5. **Rationale generation in the pipeline.** After `applyImportedPlan`, fire `generate-day-rationale` for weeks 1-4. AP-4 wired into the activate flow.
6. **Coach-authored phases.** New Step 2.5 for base/build/specific/taper week counts. LLM receives phase boundaries and must respect them.

## What about existing users

Nothing changes. Plans already subscribed via Build Adaptive stay active
and continue to flow through `reconcile-log` + `plan_adjustments`. The
suspension is **empty-state only** — no data migration, no retroactive
changes.

## To un-suspend

Rough sketch of the rebuild — not a final spec. Update this section before implementing.

```swift
// TrainingPlanView.swift — restore:
@State private var showAdaptiveBuilder = false

// Empty state: add primary button above Import
DripButton("Build Your Own Plan", icon: "wand.and.stars", style: .primary) {
    showAdaptiveBuilder = true
}

// Sheet modifier: restore
.sheet(isPresented: $showAdaptiveBuilder) {
    AdaptivePlanBuilderSheet(viewModel: viewModel)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
}
```

Plus the six improvements above landed first.

## Files still in the repo (orphaned but preserved)

- `RunningLog/RunningLog/Training/AdaptivePlanBuilderSheet.swift` — 680 lines, no callers
- `supabase/functions/generate-training-plan/` — still deployed, still called by `AIPlanChatSheet` and `WorkoutChatSheet`

---

*Related: `docs/athlete-plan-ux.md` (the Join-Coach + Import-Plan paths),
`pace-system-rework.md` (the pace ladder the rebuilt builder should use).*

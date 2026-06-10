# Pace System Rework

Single working doc for rebuilding the pace feature. Everything needed to
coordinate: current state, target architecture, migration steps, open
questions. Edit in place.

---

## 1. Current state (what exists today)

Eight disjoint pace data sources. This is the problem.

| # | Where | Type | What it holds | Who reads | Who writes | Status |
|---|---|---|---|---|---|---|
| 1 | `user_profiles.easy_pace_min/max`, `tempo_pace`, `interval_pace`, `race_*_pace` | DB cols | Athlete's training zones + race paces (duplicate of #2) | old `/pace-chart` (now rewritten) | iOS settings page | **deprecated** — no new readers, no new writers planned |
| 2 | `athlete_pace_profiles` | DB table | Per-zone sec/mi, confidence label, source date, goal race + time | `/pace-chart` (rewritten), `subscribe-to-plan` edge fn | A job triggered by `fitness_snapshots` insert | **canonical** — this is the athlete's truth |
| 3 | `athlete_state.pace_zones` | JSONB | Pace table keyed by zone | (unknown) | athlete state rebuild job | **deprecate** — duplicates #2 |
| 4 | `fitness_snapshots.predicted_*_seconds` | DB cols | Predicted finish time for each standard distance | Populates #2 | iOS fitness predictor | **keep** — raw input for #2 |
| 5 | `REFERENCE_PACE_SEC_PER_MILE` (web const) | TS constant | Fallback ladder for a 3:15 marathoner | Web editor when no athlete/plan context | — | **keep as fallback only** |
| 6 | `derivePaceTableFromGoal` (web fn) | TS function | MP offset ladder | Web editor when coach sets goal time | — | **keep — canonical derivation** |
| 7 | `plan_templates.phase_config.paceAnchor` | JSONB | Coach's per-plan goal time + per-zone overrides | Web plan builder | Web plan builder | **keep — coach layer** |
| 8 | `scheduled_workouts.workout_data.steps[].target_pace` | JSON string | Pre-resolved M:SS/mi per step | iOS step renderer | `subscribe-to-plan` edge fn | **keep — athlete's resolved snapshot** |

### Two UIs currently render pace info

- **`/pace-chart`** — athlete view. Reads #2 (was reading #1; just rewrote). Shows goal, race paces, derived training zones.
- **Plan builder header** (`PaceReferenceEditor` + `RaceEffortPanel`) — coach view. Reads #7 with ladder from #6.

They don't share anything today.

### iOS-side pace resolution

`PlannedWorkoutStep.init(from:)` tries in order:
1. `target_pace` string ("M:SS/mi")
2. `target_pace_seconds_per_mile` (flat number)
3. Nested `targetPaceIntensity` with `paceSecondsPerKm`
4. Nested `targetPaceIntensity` with only a percentage (legacy, unreliable)

---

## 2. Target architecture

### Core principle

**One ladder. One resolution order. Three override layers.**

```
┌─────────────────────────────────────────────────┐
│  STEP OVERRIDE  (step.exactPaceSecPerMile)      │ ← highest priority
│  "this specific rep at 5:45/mi"                 │
├─────────────────────────────────────────────────┤
│  PLAN OVERRIDE  (paceAnchor goal + zones)       │
│  "for this plan: goal 2:25 marathon, MP=5:32"   │
├─────────────────────────────────────────────────┤
│  ATHLETE FITNESS  (athlete_pace_profiles)       │
│  "this athlete's actual capability right now"   │
├─────────────────────────────────────────────────┤
│  REFERENCE RUNNER  (REFERENCE_PACE_SEC_PER_MILE)│ ← lowest priority
│  "fallback when nothing else is known"          │
└─────────────────────────────────────────────────┘
```

### Single derivation ladder

`derivePaceTableFromGoal(goalSecPerMile, raceDistance)` is the one place that
turns a race pace into a full zone table. Both UIs use it. Both edge functions
use it. The offsets (MP−15, MP−20, MP−40, etc.) live in one spot.

### Two callers, shared engine

- `/pace-chart` (athlete view) calls `resolvePaceTable(athleteProfile, null)`
- Plan builder (coach view) calls `resolvePaceTable(athleteProfile, planAnchor)`
- Step editor gets the resolved table as a prop

One `resolvePaceTable(athlete, plan)` function produces the canonical
`Record<PaceZone, number>` from whatever context we have.

### Data model cleanup

- **Keep:** `athlete_pace_profiles`, `fitness_snapshots`, `plan_templates.phase_config.paceAnchor`, per-step `target_pace` snapshot
- **Retire:** `user_profiles.easy_pace_*`, `tempo_pace`, `interval_pace`, `race_*_pace` — migrate any remaining readers, then drop
- **Retire:** `athlete_state.pace_zones` — redundant with `athlete_pace_profiles`

---

## 3. Migration steps (ordered, safe, each independently shippable)

### Phase A — shared engine (no DB changes)
- [x] Add `derivePaceTableFromGoal()` to `workout-helpers.ts`
- [x] Add `PaceAnchor` + `resolvePaceTable()` in `pace-reference-editor.tsx`
- [ ] Move `resolvePaceTable()` into `workout-helpers.ts` so server + client can use it
- [ ] Port the same ladder into an edge-function utility (`supabase/functions/_shared/paces.ts`) so `subscribe-to-plan` and `/pace-chart` agree

### Phase B — UI consolidation
- [x] Rewrite `/pace-chart` to read from `athlete_pace_profiles`
- [ ] Rename Sidebar item "Pace Chart" to "Pace Profile" or similar (athlete-scoped)
- [ ] In the plan builder, add a "View as athlete" toggle — pick an athlete, their pace profile becomes the base; plan anchor overrides layer on top
- [ ] Visually show override layers in the editor: when a zone is goal-derived vs athlete-fitness vs coach-override

### Phase C — backend unification
- [ ] `subscribe-to-plan` currently uses its own pace-attachment logic. Switch it to `resolvePaceTable(athlete, plan)` so the step-level `target_pace` strings it writes match what the coach saw
- [ ] Add a `generate-athlete-pace-profile` edge function (or DB trigger) that recomputes `athlete_pace_profiles` on every `fitness_snapshots` insert

### Phase D — iOS alignment
- [ ] iOS `NamedPace` enum should match web `PaceZone` 1:1 — today the lists diverge
- [ ] Replace iOS hardcoded pace tolerance table with offsets from the same ladder
- [ ] iOS step renderer: use `target_pace` when present, else fall back to athlete pace profile read at render time (not at step init)

### Phase E — retire deprecated sources
- [ ] Audit callers of `user_profiles.easy_pace_*` etc. — grep + read
- [ ] Delete the columns in a migration (only after zero readers)
- [ ] Same for `athlete_state.pace_zones`

---

## 4. Open questions

- **Offset accuracy at pace extremes.** Fixed offsets (MP−60 for 5K) are accurate for VDOT 45–55. Faster runners want smaller offsets, slower runners larger. Do we add a fitness-level adjustment factor, or rely on the coach override UI to patch edge cases?
- **"HM = LT"?** Elite coaches treat them interchangeably. Current ladder has HM = MP−15, LT = MP−20 (5s apart). Leave them distinct or collapse to one zone?
- **Easy range vs easy point.** Easy is a range in practice (e.g. "8:30–9:15"). The current `PACE_WINDOW_SEC_PER_MILE` holds ±15s for easy. Enough or too tight?
- **Who updates the athlete's goal?** Today `athlete_pace_profiles.goal_time_seconds` is set by iOS. If a coach assigns a plan with a specific goal (plan's paceAnchor), does that push back to the athlete's profile?
- **Confidence labels.** `athlete_pace_profiles` has per-zone confidence ("high" / "medium" / "low"). Should the editor show confidence alongside the number, or only surface it on `/pace-chart`?

---

## 5. Immediate next step

Choose one:

**(a) Phase A finish:** Move `resolvePaceTable()` into `workout-helpers.ts`, port the ladder to an edge-function shared file. One PR. Enables every other phase.

**(b) Phase B wow:** "View as athlete" toggle in plan builder. Coach picks an athlete, the editor re-renders with their pace profile. Makes the whole system feel unified from the coach's seat immediately.

**(c) Phase D iOS catchup:** Align iOS `NamedPace` with web `PaceZone` and retire the tolerance table. Needed before iOS renders anything authored on web correctly.

My recommendation: **(a) first** (foundation, small, low-risk), then **(b)** (biggest visible payoff). (c) is needed but can trail.

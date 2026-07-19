# Activity Types + Coach-Assigned Doubles — Feature Spec

**Date:** 2026-07-16
**Status:** Draft for review
**Decision note (Rio, 2026-07-16):** Two additions to the training model, specced
together because they share the same surfaces (Log entry, the materializer, the
fitness-math guard):

1. **Activity types** — first-class `Cross-Training`, `Strength`, and `Mobility`
   alongside `Run`, each with a modality sub-label (bike / swim / spin / …) and
   GPS/HR data (synced or uploaded).
2. **Doubles as a coaching feature** — **coach-assigned first**: the coach sets
   *how many* doubles per week and *what mileage range* each one runs. Adaptive
   (volume-triggered) generation is the fallback only when no coach is in the
   loop (self-coached Maya). Athlete-agnostic API so Maya can inherit it later
   (adaptive-coach-plan-builder spec, open Q#3).

Both are mostly *finishing and widening existing hooks*, not greenfield — see
the "what exists" tables.

---

## Part A — Activity types (Cross-Training · Strength · Mobility)

### A1. What already exists (verified in code)

| Piece | Where | State |
|---|---|---|
| `run` / `cross_training` / `strength` as activities | `ingest-manual-workout` `VALID_ACTIVITIES` | **Working** (typed + parsed) |
| Non-runs kept out of running-fitness math | `dataAnalysis.ts` `ZONE_MAP` (no cross/strength entries) + ingest comment | **Working, implicit** |
| GPS/HR stream storage | `training_logs.external_streams` (Strava blob), `pace_segments` (per-segment HR), `workout_features` (`avg_heart_rate`, HR efficiency), `running_workout_laps` | **Working — run-centric** |
| Journal shows cross/strength beside runs | `LogView` / `TodayHomeView` | **Working** |
| `Mobility` type | — | **Missing** |
| Modality sub-label (bike/swim/spin) | — | **Missing** |
| Manual GPS/HR file upload (.fit/.gpx/.tcx) | — | **Missing** |
| Non-run activities flowing through sync | HealthKit/Strava sync is run-only | **Missing** |

**The important inheritance:** the stream substrate (`external_streams`,
`pace_segments`, `workout_features`) already exists — it's just named and wired
for runs. Part A extends it to non-run activities; it does not rebuild it.

### A2. Data model

Two new columns on `training_logs`, one new bucket, following the closed-vocabulary
instinct used for niggles and reason codes:

- **`activity_kind TEXT NOT NULL DEFAULT 'run'`** — CHECK in
  `('run','cross_training','strength','mobility')`. Separates *kind of stress*
  from *pace zone*. Today `workout_type` conflates both; this un-conflates them.
  Backfill: existing rows with `workout_type IN ('cross_training','strength')`
  set `activity_kind` accordingly, `workout_type` left as-is.
- **`modality TEXT`** (nullable) — the sub-label, validated app-side against a
  closed-but-extensible list keyed by kind:
  - cross_training → `bike | spin | swim | elliptical | row | hike | ski_erg | other`
  - strength → `lift | circuit | plyo | core | other`
  - mobility → `yoga | pilates | physio | stretch | foam_roll | other`
- **`stream_source TEXT`** — `healthkit | strava | garmin | upload | none`
  (default `none`) — provenance for GPS/HR, so an uploaded `.fit` is
  distinguishable from a synced stream and from a hand-typed entry.

`workout_type` keeps its meaning **only when `activity_kind='run'`** (the pace
zone: Easy/MP/LT/…). For non-runs it mirrors the kind or is null.

Hard-rule compliance: append-only migration; `training_logs` RLS is already
user-scoped so new columns inherit it; if a dedicated `workout_uploads` storage
table is added (A3), it ships with RLS in the same migration per
`docs/conventions/rls-checklist.md`.

### A3. GPS/HR ingestion — two paths

1. **Synced non-run activities.** Extend the HealthKit/Strava mappers
   (`WorkoutSyncService.swift`, `strava-sync`) with an activity-type map
   (Apple `HKWorkoutActivityType` / Strava `sport_type` → `activity_kind` +
   `modality`) and pull the same HR/GPS streams into `external_streams`. Mostly a
   mapping table. Rename note: `running_workout_laps` stays run-only; non-run
   streams live in `external_streams` summary form for v1 (no per-lap
   normalization needed yet).
2. **Manual upload.** New `upload` mode on `ingest-manual-workout` (or a small
   `ingest-workout-file` fn): accept `.fit/.gpx/.tcx`, store the raw file in a
   Supabase Storage bucket (RLS: owner-only), parse to a summary
   (distance, duration, avg/max HR, elevation) + streams into `external_streams`,
   write the row with `stream_source='upload'`. Heavier lift → its own phase.

### A4. Fitness-math guard (make the implicit rule explicit)

Today cross/strength stay out of running load only because `ZONE_MAP` happens to
omit them. That is fragile — one careless `ZONE_MAP` addition leaks non-run miles
into ACWR. Add an explicit gate in `dataAnalysis.ts` / `athlete-state.ts`:

> Running volume, ACWR, monotony/strain, and fitness prediction consume **only**
> rows where `activity_kind='run'`. Cross-training, strength, and mobility never
> enter running-load math.

This matches the standing decision (CLAUDE.md: *"Cross-training stays out of
running-fitness math… different kind of stress"*) and the three-palette rule
(pace ≠ mood ≠ alert; cardio load ≠ mechanical load).

**Forward hook (not v1 math):** cross-training carries real *cardiovascular*
load via HR. Namespace a separate `cardio_load` accumulator (off HR, clearly
distinct from running load) that the **Recovery** pillar (v1.5) can read.
**Mobility is journal-only for v1** and becomes a first-class input when the
**Mobility** pillar (v2) lands. Adding the types now is the cheap
forward-compatible move that lines up with the five-pillar sequence.

---

## Part B — Coach-assigned doubles

### B1. What already exists (verified in code)

| Piece | Where | State |
|---|---|---|
| A doubled day = two rows (`session: 1` AM, `session: 2` PM) | `subscribe-to-plan` PM pass; `scheduled_workouts.session` | **Working for coach-authored PM runs** |
| Coach places a PM run in the builder | `sessionNumber(w) === 2` filter → `pmDoubles` | **Working** |
| `doubles_on_easy_days` flag | `athlete_plan_subscriptions.shape_prefs` | **Read but no-op — deferred by design** |
| Auto-split generator (count + range) | — | **Missing (this build)** |
| Coach config for count + range | — | **Missing (this build)** |

The materializer's own note is the design mandate here:

> *"shape_prefs.doubles_on_easy_days (auto-splitting an easy day into two
> same-volume runs) is intentionally deferred. Auto-generating a second run
> changes how an athlete's easy volume is distributed — a training-load decision
> better made deliberately with the coach than inferred here."*

Coach-assigned-first resolves exactly that: the coach makes the deliberate call;
the generator just executes it.

### B2. Config — coach owns it, athlete can dial down

**`plan_templates.doubles_config JSONB`** (coach default), with an optional
`weeks[i].doublesOverride` for per-week shaping (a build week runs 3, a down week
runs 0):

```
doubles_config: {
  mode: 'off' | 'assigned' | 'adaptive',   // default 'off'
  per_week: number,                         // e.g. 2
  range_miles: { min, max },                // each PM run, e.g. 3–5
  distribution: 'split' | 'add',            // default 'split'
  eligible_dows: number[] | null,           // null = auto-pick easy days
  placement: 'easy_only'                    // PM quality stays coach-authored only
}
```

**`athlete_plan_subscriptions.shape_prefs.doubles`** replaces the bare boolean as
the athlete override (athlete can only fit 1, or none): `{ mode, per_week,
range_miles }`. Back-compat: legacy `doubles_on_easy_days: true` maps to
`mode:'adaptive'`. Coach `assigned` always wins over athlete adaptive; the
athlete can reduce count but not silently add hard PM sessions.

### B3. Generation — the materializer doubles pass

Runs **after** easy-fill, **replacing** the deferred no-op:

- **Assigned mode (default):** peel `per_week` PM runs onto `eligible_dows` (or
  auto-picked easy days). `split` (default) reduces the AM run and emits a
  `session:2` PM row inside `range_miles`, **preserving daily + weekly volume**
  (a 10-mi Wed → 6 AM / 4 PM). `add` layers the PM run on top (raises volume) —
  coach's explicit choice.
- **Adaptive fallback (no coach / Maya):** derive `per_week` from the weekly
  target — *suggested, never silently inserted* (AI advises, never acts; Maya
  confirms):

  | Weekly target | Suggested doubles |
  |---|---|
  | < 55 mpw | 0 |
  | 55–70 | 1–2 |
  | 70–85 | 2–4 |
  | 85+ | 4+ |

  Default range ≈ 3–5 mi easy. Rationale: past ~55–60 mpw single easy runs get
  long enough that splitting protects recovery and lets total volume rise.

**Placement guardrails:**
- Never on a `rest` day; never as a second *hard* session (generated PM runs are
  Easy/Recovery pace only — PM quality stays the coach-authored path).
- Avoid PM the evening before a quality AM (don't blunt tomorrow's workout) and
  the morning of the long run.
- Respect `MIN_EASY_MILES` (2) on **both** halves — if a day can't make two
  ≥2-mi runs, don't split it.
- Never generate more doubles than eligible easy days.

### B4. Fitness math for doubled days

Both sessions are runs → both count. **Aggregate load per calendar day, not per
row**, so ACWR / monotony / strain see one elevated Wednesday, not two separate
stimuli. Action item: confirm `athlete-state.ts` sums sessions by day before
this ships (a per-row loop would double-count the *frequency* signal while
double-counting is correct for *volume*).

---

## Part C — Data model changes (consolidated)

Append-only migrations, RLS in the same migration, `TIMESTAMPTZ`, TEXT user ids
matching `auth.uid()::text`, no "Allow all", reach prod only via
`supabase db push` (hard rules #1, #5, #9):

1. `training_logs`: `+ activity_kind TEXT NOT NULL DEFAULT 'run'` (CHECK),
   `+ modality TEXT`, `+ stream_source TEXT DEFAULT 'none'`. Backfill
   activity_kind from existing workout_type. RLS inherited (already user-scoped).
2. `plan_templates`: `+ doubles_config JSONB`.
3. `athlete_plan_subscriptions.shape_prefs`: migrate `doubles_on_easy_days` →
   `doubles {…}` (keep back-compat read).
4. *(Phase 3)* `workout_uploads` (or reuse Storage): raw file refs for manual
   GPS/HR — new table ships with RLS + owner-only Storage policy in the same
   migration.

No changes needed to `scheduled_workouts.session` (already 1/2).

## Part D — Edge functions

| Function | Change |
|---|---|
| `ingest-manual-workout` | Add `mobility` to `VALID_ACTIVITIES`; accept `modality`; `parse-manual-workout.v1` prompt extracts kind + modality ("45-min spin class" → cross_training/spin). |
| `subscribe-to-plan` | **Core build:** implement the doubles pass (B3) reading `doubles_config`; assigned + adaptive; placement guards; split-vs-add. Replaces the deferred NOTE. |
| `dataAnalysis.ts` / `athlete-state.ts` | Explicit `activity_kind='run'` gate (A4); add namespaced `cardio_load` accumulator (Recovery-pillar hook). Confirm per-day session aggregation (B4). |
| `strava-sync` / HealthKit `WorkoutSyncService` | Activity-type map for non-run activities + their HR/GPS. |
| `ingest-workout-file` *(Phase 3, new)* | Parse `.fit/.gpx/.tcx` → summary + streams; Storage write. |
| `reschedule-plan` / `shift-day` | A doubled day moves both sessions together. |

## Part E — Surfaces (coach portal + iOS)

- **Coach portal Plan setup:** doubles config row (mode toggle · count stepper ·
  range slider · split/add · day chips) beside the existing shape flags
  (`rest_day_of_week`, `auto_strides`, `recovery_after_long`).
- **iOS Log entry:** activity picker (Run / Cross-Train / Strength / Mobility) →
  modality picker; optional "attach .fit/.gpx". Needs a formal `ActivityKind`
  enum in `WorkoutModels.swift` (none exists today — activity is a bare string).
- **iOS day view:** two sessions render AM/PM with a small `2×` marker; journal
  sums the day.
- **Journal:** mobility + modality chip + HR summary for non-runs.
- **Maya adaptive nudge:** a Coach Read / coachable-moment suggestion
  ("You're at 68 mpw on single runs — add 2 short PM runs?"), confirm sheet —
  never silent. Design-system: Post Run Drip tokens, empty-state component, coral
  as punctuation, no em-dash placeholders (hard rule #8).

## Part F — Phasing

| Phase | Scope | Value |
|---|---|---|
| **1 — Activity types** | `mobility` + `modality` columns, iOS pickers + enum, journal rendering, explicit running-only math gate | Cross-Train/Strength/Mobility land; math stays clean |
| **2 — Coach doubles** | `doubles_config`, materializer doubles pass (assigned + split), coach UI, per-day aggregation check | Finishes the deferred hook; high-mileage coach plans work |
| **3 — GPS/HR** | Non-run sync mapping, then manual file upload + parser + Storage | Full GPS/HR on any activity |
| **4 — Adaptive + Recovery** | Adaptive doubles suggestion for Maya; `cardio_load` from cross-training HR into the Recovery pillar | Self-coached parity; cross-training earns its keep |

Each phase ships independently. Phase 1 alone makes the Log honest about what the
athlete actually did.

## Part G — Open questions

1. **Split vs. add default** for generated doubles — proposed `split` (keeps
   weekly volume honest; doubling redistributes load, doesn't inflate it).
2. **Mobility load** — journal-only for v1, or a light recovery-credit signal
   now? Proposed journal-only; Recovery pillar reads it in v1.5.
3. **Modality vocabulary** — closed list + `other` escape (proposed) vs. free
   text mapped by the parser.
4. **Adaptive doubles thresholds** (55/70/85 mpw) — need a coach/PT sanity check
   before Phase 4.
5. **Does the coach `add` mode conflict with the weekly mileage range?** If a
   coach adds doubles *on top*, the week can exceed `targetMilesMax` — clamp, or
   treat the range as AM-only? Proposed: `add` raises the effective ceiling and
   the range readout shows both.

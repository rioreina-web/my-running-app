# Phase 2 — Race Anchoring Implementation Plan

**Last updated:** 2026-06-09
**Status:** v0.5 milestone (A + B + C) IMPLEMENTED in repo; prod deploy
pending (see `outputs/operator-checklist-2026-06-09.md`).

**Implementation state — 2026-06-09:**

- **A (populate confirmed_races): done.** `rebuildAthleteState` pulls the
  2-year window of race-tagged `training_logs` with non-null `race_result`
  and projects them into `athlete_state.confirmed_races` (defensive
  filtering for malformed rows).
- **B (band parity): done.** Server `paces.ts` `TRAINING_MP_SPEED_RATIO`
  aligned to the canonical convention from
  `outputs/pace-chart-unified-spec-2026-06-04.md` (steady 0.95 / moderate
  0.85 / easy 0.75 — identical to web). `TRAINING_MP_SPEED_RANGE` added
  server-side. Web↔server parity is now pinned by
  `_shared/cross-language-pace-contract.test.ts` (parses the web source);
  iOS PaceModels constants were already pinned there. Verified end-to-end:
  same Houston 3:28 anchor produces identical tables (every zone within
  0.5 sec/mi) on web and server. NOT yet done: dropping recovery/longRun
  keys from the tables (10-zone shape) — wider blast radius, tracked as
  follow-up.
- **C (wire confirmed_races): done.** `paceTableFromProfile` prefers
  `pickAnchorRace(confirmedRaces)` over the profile;
  `getConfirmedRaces()` helper added to `_shared/resolve-pace.ts`; wired
  into `subscribe-to-plan` (below the coach's explicit plan anchor, on
  purpose), `recompute-plan-paces` (below the just-edited plan goal, on
  purpose — EditGoal must win there), and `build-pace-profile` (race
  anchor overlays snapshot-derived paces with confidence "high" + race
  date; works even with no snapshot). Because `build-pace-profile` writes
  `athlete_pace_profiles` and the pace engine treats the profile as its
  highest-trust source, `get-pace-zones` (iOS chart, coach portal) serves
  race-anchored zones with no engine changes. Unit tests:
  `_shared/paces.race-anchor.test.ts` (Maya's Houston scenario).
- **Verification numbers (Maya, Houston 3:28:00):** MP 7:56/mi,
  Easy 9:55–11:20 band (midpoint single-value 10:35), 5K 6:59 — matches
  the worked example in the unified spec.
- **F (race-aware rule): done 2026-06-09.** `buildVsLastCycle` at
  `_shared/rules/buildVsLastCycle.ts`, registered in `rules/index.ts`.
  Pure pattern observation (`action_type: journey_comparison`, severity
  low) — fires when a goal race is within ~6 months, a prior race of the
  same distance exists in `confirmed_races`, and current 28d volume runs
  ≥5% above the prior race's build baseline (race −63d…−21d, taper
  excluded); appends an easy-pace-shift sentence when both windows have
  ≥3 parseable easy runs. RuleContext gained optional `confirmedRaces` /
  `goalRace` / `priorCycleLogs`; `evaluate-coachable-moment` populates
  them (athlete_state + active plan end_date, else next user_goal +
  prior-window log fetch gated on an anchor existing). DB CHECK extended
  in `20260609220000_add_journey_comparison_action.sql` — applied to
  prod. 9 unit tests at `_shared/rules/buildVsLastCycle.test.ts` (Maya's
  Houston scenario + no-fire guards). Note: the evaluator still no-ops
  for athletes with no active coach, so this reaches self-coached Maya
  only once Coach Read consumes `journey_comparison` moments (Phase 7).
- **D, G, H (v1.0 milestone):** not started, except D's request-shape
  groundwork (`fitness-predictor` already accepts `confirmedRaces`) and
  H's iOS constants being contract-test-pinned.

---
**Source roadmap:** `outputs/maya-product-roadmap-2026-05-28.md` (Phase 2).
**Source feature plan:** `outputs/race-performances-feature-plan.md`.

This is the sequenced implementation plan for Phase 2 of Maya's roadmap
— wiring `confirmed_races` through the fitness systems so Maya's 3:28
Houston PB becomes the anchor her pace zones and predictions are
computed against, instead of her 3:16 BQ goal aspiration.

---

## Where we are (grounded in code)

### What exists today

- **Schema is in place.** Migration `20260420100000_add_race_result_to_training_logs.sql`
  added `training_logs.race_result` (JSONB) for user-declared race
  results, and `athlete_state.confirmed_races` (JSONB array) as the
  derived cache. The legacy regex-inferred `race_history` column was
  dropped in the same migration.
- **The pace-zone math is rich.** Both `web/src/components/coach/workout-helpers.ts`
  and `supabase/functions/_shared/paces.ts` already implement a
  **12-zone** `derivePaceTableFromGoal`: Recovery, Easy, LongRun,
  Moderate, Steady, MP, HM, Threshold (LT), 10K, 5K, 3K, Mile. This is
  *more* than the 10-zone target in Maya's roadmap; Moderate, HMP, and
  3K are already there. The "extension" work in Phase 2 is mostly
  un-needed — the math is done.
- **`paceTableFromProfile` exists** and anchors on a known race pace
  from `athlete_pace_profiles` (a separate table). Falls back through
  marathon → half → 10K → 5K → mile based on what's set.
- **`fitness-predictor` returns range + confidence**, with a
  deterministic `computeConfidenceTier` that grants HIGH confidence on
  recent races ≥10K within 8 weeks.

### What's broken or missing

- **`confirmed_races` is empty in the wild.** Line 1307 of
  `_shared/athlete-state.ts` reads:
  ```ts
  confirmed_races: [], // TODO: populate from training_logs.race_result (migration 20260420100000)
  ```
  The derived cache builder doesn't actually populate it. The TODO has
  been there since the schema landed. **The data column exists; the
  rebuild that fills it doesn't.**
- **The reader is wired but never reads anything.** Lines 1466-1472 of
  `athlete-state.ts` have working code that formats `confirmed_races`
  for prompt context, gated on `if (state.confirmed_races && state.confirmed_races.length > 0)`.
  Always false today. The downstream is ready; the upstream is dark.
- **`fitness-predictor` doesn't read `confirmed_races`.** It uses regex
  matching on `workout.type === "Race"` (line 79 of
  `fitness-predictor/index.ts`). The structured `training_logs.race_result`
  data is right there and goes unused.
- **`paceTableFromProfile` doesn't read `confirmed_races` either.** It
  reads `athlete_pace_profiles`. There's no flow from confirmed races
  to pace zones.
- **TRAINING_MP_SPEED_RATIO has a parity drift between web and
  server.** Web (`workout-helpers.ts:472-478`) has steady: 0.95,
  moderate: 0.85, easy: 0.75, recovery: 0.65. Server (`paces.ts:165-171`)
  has steady: 0.925, moderate: 0.875, easy: 0.765, recovery: 0.70.
  **Maya's web UI and her iOS app compute different easy paces from
  the same MP input.** This is a real bug surfacing as part of Phase 2.
- **No web reference to `confirmed_races`.** Zero files. Confirmed via
  grep across `/web`.
- **No iOS reference to `confirmedRaces` / `confirmed_races`.** Zero
  files. Confirmed via grep across `/RunningLog`.
- **No coachable-moment rules read race history.** The 5 rule files
  (`loadSpikePlusInjury`, `lowMoodStreak`, `missedWorkouts`,
  `weatherImpactedQuality`, plus the `index.ts`) are all race-blind.
- **No first-class race-entry UI.** Maya can mark a workout as type
  "race" through workout entry flows (used by `injury-early-warning`,
  `post-run-analysis`, etc.), but no dedicated "your last race" capture
  exists. No onboarding flow asks for race history. No HealthKit back-
  fill auto-detects races. No race-history settings screen.

---

## Implementation — 8 sub-tasks, sequenced

Ordered by dependency. Each sub-task ends in something a non-engineer
can verify (a query, a unit test pass, a visible UI behavior).

### A. Fix the TODO in `athlete-state.ts` — populate `confirmed_races`

**Scope:** ~1 day.

The single line change that makes everything else viable. In
`rebuildAthleteState()` (`_shared/athlete-state.ts` line 1307), replace
the empty-array TODO with a real query: pull every
`training_logs` row for this user where `race_result` is non-null and
`workout_type = 'race'`, map to the `confirmed_races` shape (date,
distance, finish_time_seconds, official, event_name), sort by date
descending, write into state.

**Verification:**
- Manually insert a `race_result` JSONB into one of Rio's training_logs
  for a known past race
- Trigger `rebuildAthleteState`
- Query `SELECT confirmed_races FROM athlete_state WHERE user_id = ...`
- Confirm the row is in the array

**Risk:** Low. Isolated change. The format spec is in the migration
file's comment.

---

### B. Fix the web/server TRAINING_MP_SPEED_RATIO parity drift

**Status as of 2026-06-04: DESIGN-PENDING.** This isn't a code-only
fix. Web and server use *different coaching band conventions*, not
just different numbers. Rio called for a new band convention rather
than choosing between the two existing sets. Sub-task B is paused
until she defines the canonical bands.

**The two conventions in code today:**

Web side claims "CANOVA, IUFR convention" with:
- Steady 100–90% MP (includes MP itself), Moderate 90–80%, LongRun
  85–75%, Easy 80–70%, Recovery 70–60%

Server side has:
- Steady 95–90%, Moderate 90–85%, LongRun 85–75%, Easy 83–70%,
  Recovery 75–65%

Practical gap for Maya (anchored on Houston 3:28 = 7:56 MP): per-zone
~10-20 sec/mi difference between web and iOS today. Real bug that
would confuse Maya seeing different easy paces on the two surfaces.

**Once Rio locks the new convention:**
1. Apply identical RATIO values + RANGE band definitions to both
   `web/src/components/coach/workout-helpers.ts` and
   `supabase/functions/_shared/paces.ts`.
2. Document the canonical bands in `docs/conventions/pace-zones.md`
   (new file).
3. Update CLAUDE.md to reference the new doc.
4. Audit any UI / prompt copy that references specific pace numbers
   to flag what shifts.

**Verification (once shipped):**
- Pick Maya's MP value (7:56 = 476 sec/mi for race anchor)
- Compute web Easy pace → must equal server Easy pace
- iOS PaceCalculator audit (Sub-task H)

**Risk:** Medium. Changing band definitions changes Maya's displayed
Easy / Moderate / Steady paces wherever they surface today. Whatever
Rio decides becomes the *coach voice's* zone definitions — affects
how the AI talks about pace in Coach Read, in the pace chart, in any
journey-comparison observation.

---

### C. Wire `confirmed_races` into `paceTableFromProfile`

**Scope:** ~2 days.

Update `paceTableFromProfile` (and its web counterpart) to accept an
optional `confirmedRaces` input and prefer the most-recent race anchor
when present. Recency weighting per Q20 decision: a 1:32 half from 6
weeks ago anchors more strongly than a 3:28 marathon from 2 years ago.

For Maya: her 3:28 Houston (Jan 2026) is 5 months old — currently her
strongest anchor. The system uses that as the anchor input to
`derivePaceTableFromGoal` instead of her 3:16 goal time.

**Implementation:**
1. Add a `pickAnchorRace(confirmedRaces): { distance, finishTimeSec } | null`
   helper. Pick the most recent race within the recency window (~12
   months); fall back to longest race within 18 months for stability.
2. Update `paceTableFromProfile` and `derivePaceTableFromGoal` callers
   to prefer anchor race when present.
3. Update `athlete_pace_profiles` rebuild to refresh per-distance
   pace from the confirmed race anchor when that race shifts.

**Verification:**
- Maya's `athlete_pace_profiles.marathon_pace_seconds` should match
  her 3:28 Houston pace (3:28:00 / 26.21875 = 476 sec/mi = 7:56/mi),
  not her 3:16 goal (448 sec/mi = 7:28/mi)
- Her Easy pace should be computed off 7:56 MP (~10:23/mi), not 7:28
  goal MP (~9:46/mi)
- The pace chart in coach-portal should display the race-anchored
  zones

**Risk:** Medium-high. This *changes Maya's pace zones from
aspirational to actual.* Any plan that prescribes pace via the table
will shift. We should communicate this clearly: "pace zones now
reflect your current fitness anchored on your last race, not your
goal time."

---

### D. Wire `confirmed_races` into `fitness-predictor`

**Scope:** ~2 days.

Update `fitness-predictor/index.ts` to:
1. Accept `confirmedRaces` as part of `PredictionRequest` (or
   server-side pull from `athlete_state.confirmed_races`).
2. Update `computeConfidenceTier` to grant HIGH on a race in
   `confirmed_races` ≥10K within 8 weeks, rather than fuzzy regex
   matching on workout type strings.
3. Update the prompt (`_shared/prompts/fitness-predictor.v1.ts` if it
   exists) to inject confirmed race context: "Last race: Houston
   Marathon, January 2026, 3:28:00 (humid conditions, dew point 62°F
   per voice memo)."
4. Update the predictor's range output to be anchored on the race +
   adjusted for training trajectory since the race.

**Verification:**
- Trigger fitness prediction for Maya
- Confirm `confidence_tier === "high"` (her Houston race is 5 months
  out but it's a real anchor; tune the recency window if needed)
- Confirm the range falls between Houston (3:28) and BQ goal (3:16)
  with midpoint somewhere around 3:18-3:24 reflecting her training
  trajectory

**Risk:** Medium. Touches an LLM call. Needs eval cassette coverage
(Sub-task G).

---

### E. Build race-entry UX — onboarding + ad-hoc

**Scope:** ~3 days.

Per the May 2026 design decisions (Q1, Q2, Q19 in Maya's roadmap):

1. **HealthKit back-fill on first launch** (2-year window). On signup,
   request HealthKit access and pull the back-fill in the background.
2. **Auto-detect candidates from back-fill.** Scan for workouts tagged
   "Race" or "Marathon" by HealthKit, or workouts matching known race
   distances at race pace. Surface as "We found these recent races —
   confirm or edit."
3. **Maya confirms or edits** — locks the race into
   `training_logs.race_result`.
4. **Ad-hoc entry** later via "Add race" on a journal entry (per Q18
   decision: race-entry edit happens on the journal entry).
5. Trigger `rebuildAthleteState` after any race confirmation so the
   downstream wires light up.

**Verification:**
- Fresh signup → grant HealthKit → see "We found Houston Marathon
  Jan 2026 — 3:28:14 (estimated). Confirm?" prompt
- Confirm → check `training_logs.race_result` has the entry → check
  `athlete_state.confirmed_races` updates after rebuild

**Risk:** Medium. The HealthKit race-detection heuristic needs tuning
(false positives on long Sunday efforts vs. true marathon races).
Build with a clear confirmation step rather than auto-acceptance.

---

### F. Build a race-aware coachable-moment rule

**Scope:** ~1-2 days.

The cheapest race-aware rule that surfaces real signal:
**`buildVsLastCycle`** — when an athlete is mid-build (consistent
volume above their recent baseline AND a stated goal race within 6
months) AND they have a prior race in `confirmed_races` of similar
distance, surface a comparison observation.

For Maya, this would surface to Coach Read:
> "You're 5 months out from a 3:28 marathon. Volume is averaging 42
> mpw, ~10% above your Houston-build baseline. Easy paces are 15
> sec/mi quicker at similar effort."

This is one of the journey-anchored observations the journey doc
prioritized. Aligns with the pattern-observation-only constraint from
Q17 follow-up (this is pattern observation, not operational).

Implementation:
1. New file: `supabase/functions/_shared/rules/buildVsLastCycle.ts`
2. Register in `_shared/rules/index.ts`
3. Output a `coachable_moment` row of a new type:
   `journey_comparison`

**Verification:**
- Run `evaluate-coachable-moment` for Maya
- Confirm a `journey_comparison` moment surfaces with the
  Houston-comparison observation
- Surface it in Coach Read context

**Risk:** Low-medium. Rule logic is self-contained. The downstream
display in Coach Read may need light copy work.

---

### G. Add eval cassette coverage for race-aware prompts

**Scope:** ~1 day.

Phase 1 (eval harness) tasks #15-17 are pending. As part of Phase 2,
add cassettes for:

1. `fitness-predictor.v1` — input includes recent race anchor;
   expected output includes range anchored to race, HIGH confidence
2. `coaching-daily-read.v1` — input includes a recent race anchor;
   expected output references the cycle without explaining the math
   (per Coach voice principle)

These cassettes catch regressions when we touch the predictor prompt
or the daily-read prompt in the future.

**Risk:** Low. Standard eval-harness extension work.

---

### H. iOS sync check

**Scope:** ~1 day.

After steps B (parity fix) and C (race anchor wired), verify iOS
`PaceCalculator.swift` produces matching numbers. If iOS computes
training zones independently (rather than reading from the server), it
needs the same race-anchor priority logic. If iOS reads pace zones
from the server, no change needed — but we verify.

**Verification:**
- Given Maya's confirmed_races + a hardcoded MP input, web Easy pace
  == server Easy pace == iOS Easy pace, to the second.

**Risk:** Low. Mostly verification, not implementation.

---

## Sequence + dependency map

```
A (TODO fix) ───┬──→ C (paceTableFromProfile wiring)
                │
                ├──→ D (fitness-predictor wiring)
                │
                └──→ F (race-aware rule)

B (parity drift) ────→ H (iOS sync check)

E (race-entry UX) ───→ A's verification needs E to provide test data
                       (or we manually insert race_result JSONB)

G (eval cassettes) ─── depends on D for fitness-predictor prompt,
                       runs in parallel with F
```

Critical path: A → C → D → G. Total ~7 dev days serial.
E and B can run in parallel (~3-4 days parallel work).
F is a small isolated addition.
H is verification at the end.

**Realistic timeline: 10-12 dev days for all 8 sub-tasks.** Could ship
sub-tasks A, B, C as a first "v0.5 race anchoring" milestone in ~4
days that unblocks pace-zone correctness for Maya, with D-H following
in a second milestone.

---

## Risks + mitigations

1. **Changing pace zones changes the product Maya sees.** Her current
   Easy pace (8:30-9:00) is based on the 3:16 goal anchor. After Phase
   2, it becomes ~10:00-10:30 based on her 3:28 Houston anchor. That's
   a 60-90 sec/mi shift. **Mitigation:** Ship with an in-product
   explanation card: "Your pace zones now reflect your last race
   (Houston 3:28) — actual fitness, not goal aspiration." Acknowledge
   the shift; don't silently move things.

2. **The HealthKit race-detection heuristic will have false positives
   and negatives.** **Mitigation:** Always require confirmation. Show
   confidence ("We're fairly sure" vs. "This might be"). Build an
   editable race-history UI.

3. **The fitness-predictor prompt change has downstream eval risk.**
   **Mitigation:** Sub-task G (eval cassettes) must land before
   Sub-task D ships. No prompt change without harness coverage.

4. **`_shared/athlete-state.ts` is the 1481-LOC file with P0 bugs**
   that's planned for refactor in Phase 6. Touching it in Phase 2 is
   unavoidable (Sub-task A) but limited. **Mitigation:** Keep the
   change to one targeted edit. Don't refactor the rest of the file.

5. **Maya's 3:28 was a humid Houston run.** Reading her race anchor
   literally as 7:56/mi MP underweights her actual aerobic fitness.
   **Mitigation:** Long-tail concern. Phase 2 ships the anchor as-is;
   conditions-adjustment is a Phase 6 cold-tier feature.

---

## Decisions logged (2026-06-04)

1. **Sub-task E moves to Phase 4.** Race-entry UX is a natural fit for
   the journal surface (Phase 4). Phase 2 ships in ~7 days instead of
   ~12. End-to-end Phase 2 verification uses manual race_result inserts
   for Maya's Houston race.
2. **12 zones internal, 10 surfaced.** Pace chart UI shows the 10 zones
   from Maya's roadmap (Easy / Moderate / Steady / MP / HMP / LT / 10K
   / 5K / 3K / Mile). Recovery and LongRun stay internal as math/
   programming concepts. No code change to zone count; documentation
   lock only.
3. **v0.5 milestone shape: A + B + C in ~4 days.** First milestone fixes
   the TODO, fixes the parity drift, and wires pace zones to the race
   anchor. End state: Maya's pace zones anchor on Houston 3:28 not on
   3:16 goal. v1.0 milestone (D + F + G + H) follows in another ~5
   days. E ships with Phase 4.

## Open questions (none blocking)

All three open questions from the initial plan were resolved
2026-06-04 (above). No remaining blockers to starting Sub-task A.

---

## How to use this plan

- **Sub-tasks are independently shippable** in the sequence above. We
  can pause between any two and the codebase stays in a coherent
  state.
- **Each sub-task ends in something verifiable** by Rio without
  reading code — a query result, a visible UI behavior, a pace number
  that matches a reference.
- **Approval needed before A starts.** This plan is the artifact for
  review. Once approved, A is the first commit.

---

## Sources

- `outputs/maya-product-roadmap-2026-05-28.md` (Phase 2 definition)
- `outputs/race-performances-feature-plan.md` (existing feature plan)
- `supabase/migrations/20260420100000_add_race_result_to_training_logs.sql`
- `supabase/functions/_shared/athlete-state.ts` (lines 170-180, 1307,
  1464-1475)
- `supabase/functions/_shared/paces.ts` (full file)
- `supabase/functions/fitness-predictor/index.ts` (lines 1-100,
  computeConfidenceTier)
- `web/src/components/coach/workout-helpers.ts` (lines 455-594)
- `RunningLog/RunningLog/Workouts/PaceCalculator.swift` (lines 1-120)
- `supabase/functions/_shared/rules/` (5 rule files; none race-aware)

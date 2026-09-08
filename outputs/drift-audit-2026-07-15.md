# Drift audit — everywhere the same thing is computed twice (2026-07-15)

Scope: every computation that exists in more than one of web / iOS / edge, diffed
implementation-by-implementation. Excludes `.claude/worktrees/*` and
`.perf-worktree` (stale artifacts per CLAUDE.md).

Ranked by how much a user-visible number can differ. The LT-was-HM bug you hit
was class 2 below (two "equivalent" formulas that aren't); this audit found
several more of that class, plus one of the class where the *same* formula was
fixed in one copy and not the others.

---

## Verdict in one paragraph

The core pace ladder is in good shape: the race-equivalence ratio table
(`RACE_RATIOS_TO_10K`) matches to the digit across web, edge, and iOS, the
training-band multipliers match exactly and are pinned by
`cross-language-pace-contract.test.ts`, the LT interpolation algorithm is
identical on all three platforms, the 10-stop pace color ramp matches hex-for-hex
across five sources, the mood vocabulary is consistent everywhere, the dew-point
heat table was ported verbatim (with a drift self-check), and `data_depth` is
computed in exactly one place. The drift lives in the second tier: fallback
paths, legacy projections, formatters, and client-side recomputes — the code
that runs when the canonical path doesn't.

---

## 1 · ACWR: five independent implementations, no two alike — HIGH

The single worst finding. Five places compute acute:chronic workload ratio with
different windows, weights, and load metrics:

| # | Where | Acute | Chronic | Load | Window |
|---|---|---|---|---|---|
| A | `supabase/functions/_shared/weeklyAnalytics.ts:236` `calculateACWR` | current calendar week | exponentially weighted prior weeks `[4,3,2,1]` | intensity-weighted minutes | calendar, chronic excludes current |
| B | `_shared/builders/buildLoadMetrics.ts:96` | rolling 7d | rolling 28d ÷ 4 | intensity-weighted | rolling, chronic includes acute |
| C | `compute-workout-features/index.ts:249` | rolling 7d | rolling 28d ÷ 4 | **raw miles** | rolling |
| D | `injury-early-warning/index.ts:140` | current week miles | mean of 4 weeks incl. current | **raw miles** | calendar |
| E | `RunningLog/…/Trends/TrendsDetailViews.swift:306` | this week (projected mid-week) | mean of ≤4 prior non-zero weeks | **raw miles** | calendar, client-side |

B is what persists to `athlete_state.acwr` and what the Analysis screen and
coach portal read. E recomputes independently on-device for the Trends
drilldown — the same athlete can see two different ACWR numbers in the same
app session. D drives injury early-warning, meaning the injury-risk trigger
fires on a *different* number than the one displayed. A feeds the weekly
coaching report.

Fix path: pick B (rolling, intensity-weighted, the persisted one) as canonical;
make E read `athlete_state.acwr` (its own comment at
`TrendsDetailViews.swift:247` already calls this a follow-up); decide
deliberately whether injury-early-warning *should* use raw miles, and document
it if so.

## 2 · Fixed-multiplier race equivalence contradicting the ratio table — HIGH

Three edge-side code paths convert between race distances with hardcoded
multipliers instead of `RACE_RATIOS_TO_10K`, and the multipliers are materially
wrong relative to the table:

- `_shared/pace-engine.ts:483` `goalToMpPace` — HM×1.06, 10K×1.15, 5K×1.22, else×1.30
- `_shared/pace-engine.ts:686` `projectToLegacyZones` fallback cascade — same family plus 0.943 / 0.925 / 1.08 / 0.87 / 0.82
- `_shared/pace-zones.ts:78-88` `computePaceProfile` — byte-identical cascade, feeding plan generation from `fitness_snapshots`

Ratio-table truth vs. the multipliers: 10K→MP pace ratio is **1.094** (table)
vs **1.15** (hardcoded) — ~5%, ≈25 s/mi for a 7:30 athlete. 5K→MP is **1.137**
vs **1.22** — ~7%. HM→MP is **1.047** vs **1.06**. So an athlete whose only
anchor is a 10K goal gets an MP ~25 s/mi slower from the goal fallback than the
canonical ladder would give — and every training zone derived from that MP
inherits the error. These are fallback paths (they fire when profile/snapshot
anchors are missing), which is exactly when new users hit them.

Fix path: both functions already sit next to imports from `paces.ts` — replace
the multiplier chains with `equivalentRacePaceSecPerMile`. `pace-zones.ts`
looks like a pre-engine survivor; check whether its callers can move to the
engine outright.

## 3 · The "7:60" formatter bug — fixed once, still live in 7 copies — HIGH (cheap fix)

`_shared/shared/format.ts:12` is the canonical fixed `formatPace` (round total
first, then split; docstring names the trap). But the buggy pattern —
`floor(sec/60)` minutes + `round(sec % 60)` seconds, so 479.6 s renders
"7:60" — is still live in:

- `_shared/pace-engine.ts:830` `formatPace` (the widely imported one)
- `race-readiness/index.ts:26` `fmtPace`
- `block-review/index.ts:22` `fmtPace`
- `post-run-analysis/index.ts:91` `fmtPace`
- `race-intel/index.ts:434` inline `formatPace`
- `process-training-memo/index.ts:193` `formatPaceMMSS`
- iOS `RunningLog/…/Trends/PaceSignalView.swift:71` `paceString` — worse than
  "7:60": minutes from *unrounded* floor + seconds from rounded value means
  419.6 s renders **"6:00"** instead of "7:00" (a full minute off at the
  boundary)

All verified against source this session. Fix path: edge copies import from
`_shared/shared/format.ts`; PaceSignalView routes through
`PaceCalculator.formatPace` (correct).

## 4 · Niggles vocabulary: backend 26 keys, iOS enum 13 — HIGH

`_shared/bodyVocabulary.ts:50-77` defines 26 canonical `body_area` keys. iOS
`Models/InjuryModels.swift:206-219` `enum BodyArea` has 13. Consequences:

- 14 backend-emittable areas (`soleus, peroneal, heel, arch, top of foot, toe,
  adductor, groin, hip flexor, piriformis, si joint, lower back, neck,
  shoulder`) cannot decode into the Swift enum.
- Hard key collision: backend canonical key is **`arch`** ("plantar"/"plantar
  fascia" are synonyms mapped onto it, `bodyVocabulary.ts:58`); Swift's
  canonical case is **`plantar`** (`InjuryModels.swift:216`) and has no `arch`.
  A memo-pipeline niggle stored as `arch` fails `BodyArea(rawValue:)` on iOS;
  the round trip is broken in both directions.

Fix path: generate/mirror the Swift enum from `bodyVocabulary.ts` keys (or
decode unknown values into an `.other(String)` case so backend additions
degrade gracefully), and settle `arch` vs `plantar` as one key with a data
migration for whichever loses.

## 5 · Web's `REFERENCE_PACE_SEC_PER_MILE` still encodes the pre-2026-06 ladder — MEDIUM

`web/src/components/coach/workout-helpers.ts:491-504`. The fallback reference
table (used whenever no athlete pace table is passed — `nearestZoneKey`, zone
coloring, duration estimates, `paceRangeLabel` fallback) is internally
inconsistent with `derivePaceTableFromGoal` **in the same file**:

- Training zones use the old band midpoints (comments say so: easy MP/0.765,
  moderate /0.875, steady /0.925, recovery /0.70) vs canonical 0.75 / 0.85 /
  0.95 / 0.65. For its own MP 7:30 anchor: easy 9:49 vs canonical 10:00,
  steady 8:06 vs 7:54, moderate 8:34 vs 8:49.
- Race zones use fixed offsets (HM = MP−15, LT = MP−20, 10K = −40, 5K = −60,
  mile = −100) vs ratio-derived 7:10 / **7:01** / 6:51 / 6:36 / 5:57. The LT
  gap (7:10 vs 7:01) is the exact LT-should-be-1-hour-pace bug, surviving in
  the fallback table after being fixed in the derivation.

Fix path: define it as `derivePaceTableFromGoal(450, "marathon")` evaluated at
module load (or a frozen literal generated from it) so the fallback can never
disagree with the derivation again.

## 6 · Two conventions for a band's "single number": harmonic vs arithmetic midpoint — MEDIUM

When a surface needs one pace per training zone instead of a range:

- `paces.ts` / web `TRAINING_MP_SPEED_RATIO` use the **speed midpoint** —
  easy = MP/0.75 = 1.3333×MP
- `pace-engine.ts` `projectToLegacyZones` and iOS `PaceModels` `easyMPRatio`
  (1.3393) use the **pace midpoint** — (1.25+1.4286)/2 = 1.3393×MP

For MP 7:30 that's easy 10:00 vs 10:03, recovery ~4 s/mi apart. The contract
test knows about this — `cross-language-pace-contract.test.ts:122` compares the
two with an explicit 0.005 tolerance rather than asserting equality. Small, but
it means "easy pace" as a single number differs between the coach portal /
subscribe-to-plan (`paces.ts`) and the iOS chart fallback / legacy projections
(engine). Pick one convention and tighten the test tolerance to pin it.

## 7 · Race-distance constants: three-plus precision variants — LOW (fix opportunistically)

Everyone agrees at 4 decimals; nobody agrees exactly:

- Web `race-constants.ts` + `RACE_DISTANCE_MI` in workout-helpers: 26.21875,
  13.109375, 6.213712 (and 0.932056 / 1.864113 / 3.106856)
- Edge `paces.ts:63-72`: rounded to 4 decimals (26.2188, 13.1094, 6.2137…)
- Edge `pace-engine.ts:239-248` `MILES`: 11-digit variants (26.21875088,
  13.10937544, 6.21371192)
- iOS `RaceDistanceConstants`: 26.21875 / 13.109375 / 6.2137119, but
  `PaceZonesEngine.swift:131-132` has its own inline `d10K = 6.21371192`,
  `dHM = 13.10937544` for its LT calc, and `FitnessPredictorService` +
  `RaceDistance.swift` carry 26.219 / 26.2188 / 3.1069-class copies
- iOS km-per-mile split: `RaceDistanceConstants.kmPerMile = 1.609344` (exact)
  but ~18 call sites use truncated `1.60934` (PaceCalculator `formatPaceKm`,
  `calculateSplits`, WorkoutRepReceiptView ×8, WorkoutReceiptCharts ×3,
  MonthCalendarView ×2, DayDetailSheet, TrainingPhaseModels, PaceModels:99 —
  while PaceModels:155 uses the exact one)

Numeric effect is sub-display-rounding (≲0.5 s/mi), so nothing is user-visible
today — but the edge `paces.ts` 4-decimal table technically violates the
"identical numbers for identical inputs" contract in its own header, and every
extra copy is a future divergence seed. One constants module per language,
generated from the same definitions, closes this class permanently.

## 8 · `raceKeyForInput`: same name, different tolerance — MEDIUM (latent)

Two functions with the same name and contract, different behavior:

- Edge `paces.ts:75` lowercases + trims and accepts ~20 aliases (`hm`, `half`,
  `3k`, `1500m`, `10mi`…)
- Web `workout-helpers.ts:703` does neither — exact-match on 5 strings only,
  everything else silently defaults to **marathon**

So `raceKeyForInput("5K")` → `fiveK` on edge, → `marathon` on web. Any web
call site passing an uppercased or aliased distance derives a wildly wrong
table with no error. Also, web can't handle `3k`/`10mi`/`1500m` goals at all.
Fix path: port the edge normalizer verbatim (it's 15 lines) and add it to the
cross-language contract test.

## 9 · Zone classification of an actual pace: two algorithms, three anchor sets — MEDIUM

- Web `nearestZoneKey` (`workout-helpers.ts:227`): nearest-neighbor over
  `PACE_ZONES` with reference-table fallback
- iOS `SignalService.swift:320` `classify`: same nearest-neighbor algorithm,
  different anchor set (10-entry race+training table)
- Edge `post-run-analysis/index.ts:61` `labelPaceZone`: entirely different —
  ±8 s tolerance bands over just 5 zones, with "between X and Y" verbiage
  (threshold deliberately dropped)

A run 20 s off every anchor gets a hard zone label from web/iOS and "between
marathon and easy pace" from the edge. The post-run wording may be a deliberate
voice choice (honest hedging fits the coaching principles) — if so, document
it; if not, it's drift.

## 10 · Consistent surfaces (verified, no action)

- **Race-equivalence ratios**: identical to the digit in `paces.ts`, web
  workout-helpers, iOS `PaceCalculator.performanceRatios` (iOS adds
  Riegel-derived 400m/800m/1K on top). Note the web copy is a duplicated
  literal, not an import — value-identical today, unpinned by any test.
- **Training band edges**: `TRAINING_PACE_MULTIPLIERS` ≡ iOS
  `NamedPace.mpPaceMultipliers` exactly; pinned by the contract test.
- **LT / one-hour interpolation**: same algorithm in all three languages
  (plus two extra iOS copies — `EquivalentPaces.oneHourPace`,
  `PaceZonesEngine.thresholdPace` — same math, only the §7 precision nits).
- **Pace color ramp**: all 10 hexes identical across PaceSpectrum.swift,
  globals.css, design-system CSS, chart-theme.ts, and the prototype.
- **Mood vocabulary**: 6 values consistent across every Swift/TS/web list.
  (The daily check-in deliberately omits `injured` — documented in code.)
- **Mood colors**: identical hexes Swift ↔ CSS ↔ chart-theme.
- **Dew-point heat model**: table, 0.003495 multiplier, 55°F baseline, and
  category thresholds identical across iOS + both TS ports; `pace-heat.ts`
  even carries a dev-mode drift self-check. (Two TS copies could still merge.)
- **`data_depth`**: one implementation (`athlete-state.ts:394`); iOS/web read
  only.
- **iOS pace-zone display**: reads the backend engine via `get-pace-zones`;
  the on-device fallback uses the contract-pinned multipliers.

## Loose ends (small, note-and-move-on)

- `prototypes/workout-builder.html:28` still declares the dead
  `--mood-speed: #6B4A8A` plum token (only in-repo straggler of the rename).
- The Downloads "Post Run Drip Design System" folder is a stale pre-migration
  export: no `--pace-*` ramp, still has `--mood-speed`. Don't source from it.
- No DB CHECK constraint enforces the mood vocabulary — columns are free TEXT,
  enum enforced only in code. (Same is true of `body_area`.)
- `cross-language-pace-contract.test.ts` header comment cites stale band
  numbers ("recovery 1.35, easy 1.25, moderate 1.15, steady 1.05" — those are
  neither the edges nor the midpoints).
- `HeatCategory` colors reuse mood + coral tokens cross-palette
  (`PaceCalculator.swift:427`) — a recolor of mood tokens silently shifts heat
  categories. Coupling, not drift.

## What would prevent the next one

The contract test is the right idea and already caught the worst class once
(the Maya easy-pace bug). Its gaps, in order of value: it doesn't pin the
race-ratio literal in web workout-helpers to `paces.ts` (§10 note), doesn't
cover `raceKeyForInput` behavior (§8), doesn't touch ACWR at all (§1), and
tolerates the midpoint-convention split (§6) instead of forcing a decision.
Each is one more `Deno.test` in the same file, same source-parsing pattern.

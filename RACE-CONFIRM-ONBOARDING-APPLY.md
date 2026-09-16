# RACE CONFIRMATION AT ONBOARDING — APPLY

Session of 2026-08-15. The iOS half of improvement #2 from the current-fitness
work: make race confirmation a first-session moment instead of a surface
nobody finds. Server prerequisites are DONE (see §4-status notes); this doc is
for the Xcode session.

## 0 · Why this is the highest-trust minute in onboarding

Evidence, from the founder's own account: **five detected races, zero
confirmed** (`confirmed_at IS NULL` on every `race_results` row, including a
31:20 10K PB). The detection pipeline works; the confirmation loop has never
fired for a single race. Consequences, all live today:

1. **The Medium ceiling.** CURRENT-FITNESS-APPLY.md §1.3: an unconfirmed
   anchor caps capacity confidence at Medium. With a 0% confirmation rate,
   no athlete ever sees HIGH — the tier loses meaning.
2. **`race_results.conditions` is null on every row.** The column the
   conditions-normalization rule needs (now implemented —
   `_shared/raceNormalization.ts`) has no writer.
3. **The lost wow moment.** With Garmin mandatory, backfill lands the
   athlete's race history at first sync. "We found your races — these
   yours?" is the app proving it *knows them* in minute one. Skipping it
   wastes the single best trust beat cold-start offers.

## 1 · The flow (iOS)

**Trigger:** first app open after the initial Garmin/Vital backfill completes
AND `race_results` has ≥1 row with `confirmed_at IS NULL` for the user.
Re-triggers quietly (a Log-top card, not a modal) if new unconfirmed races
appear later — race detection is ongoing.

**Surface:** one sheet, one card per race, newest first, max ~6:

```
eyebrow   WE FOUND A RACE
headline  10K · 31:20 · Feb 7, 2026          ← raw time, always
sub       Cap10K, Austin · 69° and humid, hilly   ← when conditions on file
actions   [ That's mine ]   [ Not a race ]
```

- **"That's mine"** → `confirmed_at = now()`. Optional one-tap add-ons after
  confirm (never blocking): official time correction, event name.
- **"Not a race"** → the existing user-exclusion path
  (`userExcludedFromFitness` semantics — the correction always wins over
  auto-detection; the row keeps existing, it just exits every fitness signal).
- Skippable as a whole. Never shown as a wall; the athlete can confirm later
  from the race detail.

**Voice (Post Run Drip):** plain, warm, zero pressure. "These yours?" not
"Verify your data." Per hard rule #8, an empty state (no races found) is the
empty-state component with a nudge ("Race sometime — we'll spot it"), never a
dash.

**Reuse, don't rebuild:** the confirm/dismiss machinery already exists for
race candidates (`RaceCandidate` in `FitnessPredictorModels.swift`, surfaced
detection-not-decision). This sheet is that pattern pointed at
`race_results` backfill rows at onboarding time.

## 2 · What confirmation must write

| field | write |
|---|---|
| `confirmed_at` | `now()` |
| `official_time_seconds` | only if the athlete corrects it |
| `conditions` | **auto-stamped, athlete-overridable** — see §3 |

## 3 · Conditions auto-stamp (server, small edge-function change)

At detection time (and backfillable for existing rows), populate
`race_results.conditions` from data the app already has:

- `temp_f` / `dew_point_f`: the linked `training_logs.weather_actual`
  (fetch-workout-weather already stamps it; the backfill cron covers history).
- `elevation_gain_m`: the linked activity's total elevation gain
  (`external_streams` meta / laps sum — same figure the Strava summary shows).

Shape: `{ "temp_f": 69, "dew_point_f": 68, "elevation_gain_m": 100, "source": "auto" }`.
Athlete override at confirmation sets `"source": "athlete"` and wins forever.

## 4 · What this unlocks (already built, waiting on this flow)

- **`_shared/raceNormalization.ts`** — neutral-equivalent race times from the
  repo's own heat + grade models, with the founder's two 10Ks as the test
  fixture (the Cap10K's 102s "detraining" collapses to ~2% once conditions
  are read). Pure, tested (8 tests), **not yet wired into anchor selection.**
- **The wiring is a BOTH-PLATFORMS change** — anchor selection is
  deliberately implemented twice (`fitnessPrediction.ts` +
  `FitnessPredictorService.swift`) with a parity doctrine. Wire
  `pickAnchorIndex` into the server's `scoredRaces` and mirror the same rule
  in Swift **in one change**, or the two predictors will disagree about which
  race anchors. Do not ship one side alone.
- **The tier cap** (§1.3) becomes fair the moment confirmation is one tap:
  unconfirmed → Medium stops being a permanent ceiling and starts being an
  incentive.

## 5 · Not in scope

- No editing of race *times* beyond the official-time correction field.
- No normalized times shown as achievements — `race_prs` stays raw. The
  normalized figure appears only as context ("worth ~31:50 in neutral
  conditions"), never as the headline number.
- No confirmation nagging. One sheet at onboarding, a quiet card after.

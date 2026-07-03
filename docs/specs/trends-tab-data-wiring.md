# Trends tab — data wiring engineering spec

**Status:** Draft for review · **Date:** 2026-06-15 · **Surface:** Trends (5th tab)
**Depends on:** the shipped Trends UI (`RunningLog/Trends/*`), `weeklyAnalytics.ts`,
`training_logs`, `workout_features`, `body_mentions`, `athlete_state`.

---

## 1. Goal & scope

The Trends tab shipped with a fully designed UI driven by `TrendsSampleData`
(see `RunningLog/Trends/TrendsModels.swift`). This spec covers replacing that
sample with real data so the unified chart reflects Maya's actual training.

The chart fuses five streams on one shared timeline. This spec wires all five
plus the ask-bar handoff:

1. **Mileage** — weekly volume.
2. **Intensity** — quality miles inside each week's volume (the darker bar cap).
3. **Key-session pace** — the pace of the week's hardest quality session.
4. **Mood** — the dominant voice-log mood for the week.
5. **Niggles** — body-part mentions per week, verbatim.

**In scope:** the per-week aggregation feeding `[TrendsWeek]`, the iOS load
path, loading/empty/error states, the niggle surface-not-diagnose contract, and
the ask-bar deep-link into The Read.

**Out of scope (future layers, sketched in §10):** the race-anchored fitness
range overlay, an ACWR/load band, and sleep. The view's data contract is
designed so these are additive.

**Non-negotiables carried from `CLAUDE.md`:** niggles are surfaced never
diagnosed (closed vocabulary, verbatim quotes); predictions ship as range +
confidence, never a point; empty cells use the empty-state component, never an
em-dash; pace math stays canonical (no re-derivation that drifts from
`weeklyAnalytics.ts` / `paces.ts`); cross-training is excluded from running
volume/intensity.

---

## 2. What ships today (starting point)

- `TrendsModels.swift` — `TrendsWeek`, `TrendsRange`, `TrendsFormat`,
  `TrendsSampleData`. **The view layer depends only on `[TrendsWeek]`.** This is
  the seam: replace the data provider, leave the views untouched.
- `UnifiedTrainingChart.swift` — Canvas chart; pure function of
  `[TrendsWeek]` + a `scrubIndex` binding.
- `TrendsTabView.swift` — header, range segmenter, readout, chart, derived
  insights, ask bar. Currently reads `TrendsSampleData.window(range)`.

The `TrendsWeek` shape to fill:

```swift
struct TrendsWeek {
    let month: String          // "May"            (x-axis tick)
    let dateLabel: String      // "May 26"         (readout)
    let miles: Double
    let qualityMiles: Double    // intensity layer
    let keyPaceSec: Int?        // sec/mi, nil if no quality session
    let mood: String            // closed vocab; "" / nil-safe if no logs
    let niggles: [String]       // body-area labels mentioned that week
    var voiceQuote: String?     // verbatim, optional
}
```

---

## 3. Source-of-truth mapping

Every `TrendsWeek` field, where it comes from, and how it's derived. Tables are
RLS-scoped to the signed-in user; the iOS Supabase client reads under the user's
bearer token (same pattern as `DailyReadService`).

| Field | Source | Derivation |
|---|---|---|
| `miles` | `training_logs.workout_distance_miles` | Sum of running logs in the Mon–Sun week. Exclude `cross_training` / `strength` (CLAUDE.md: different stress kind). |
| `qualityMiles` | `training_logs` + `workout_features` | Sum of miles in logs classified **quality** (see §5.2). Mirrors the easy-vs-workout split in `weeklyAnalytics.ts::computeAllMetrics` (`getEffectiveType`). |
| `keyPaceSec` | `training_logs.workout_pace_per_mile` (or `duration/distance`) + `workout_features.intensity_score` | Pace of the week's **highest-intensity** quality session. `nil` for down weeks with no quality work. |
| `mood` | `training_logs.mood` | Dominant (modal) mood across the week's logs. Vocabulary: `energized\|positive\|neutral\|tired\|struggling\|injured`. |
| `niggles` | `body_mentions.body_area` (+ `side`) | Distinct `"<side> <body_area>"` labels with `mentioned_at` in the week. |
| `voiceQuote` | `body_mentions.verbatim_quote` (or `training_logs.cleaned_notes`) | Optional. Prefer the most recent niggle/struggling week's verbatim line. Never paraphrased. |
| `month` / `dateLabel` | computed | From the week's Monday (see §5.1 boundaries). |

Key references:
- `supabase/functions/_shared/weeklyAnalytics.ts` — `aggregateWeeklyLoad`,
  `analyzeMood`, `getLastWeekBounds`, `TYPE_FALLBACK_WEIGHTS`,
  `computeWeightedLoadForLog`. **The canonical weekly math.**
- `supabase/functions/compute-workout-features/` →
  `workout_features.intensity_score`, `total_duration_seconds` — the real
  per-workout intensity signal (time-weighted pace-zone average).
- `body_mentions` table — migration `20260612130000_body_mentions.sql`. Columns:
  `body_area` (closed vocab), `side`, `verbatim_quote`, `severity_hint`
  (`tight\|sore\|pain\|sharp`), `mentioned_at` (date), `volume_context`. Indexed
  `(user_id, mentioned_at desc)`.
- `athlete_state` — `acwr`, `rolling_7d_miles`, `rolling_28d_miles`,
  `niggle_recurrence` (jsonb), `pace_zone_ranges`. iOS projection already exists:
  `RunningLog/Analysis/TrendsAthleteState.swift`.

---

## 4. Architecture — where aggregation runs

Two viable options. They differ in **where** raw rows get bucketed into weeks.

### Option A — client-side aggregation (fastest to ship)

iOS fetches raw `training_logs`, `body_mentions`, and `workout_features` for the
last 26 weeks and buckets them into `[TrendsWeek]` on-device. Precedent exists:
`WorkoutHistoryAnalyzer.calculateWeeklyMileageStats` already buckets HealthKit
workouts by `.weekOfYear`.

- **Pros:** no backend change, no deploy, reuses existing RLS, ships in days.
- **Cons:** re-implements the intensity/quality/mood math from
  `weeklyAnalytics.ts` in Swift. That risks **cross-language drift** — the exact
  failure mode `CLAUDE.md` warns about for pace math. Mitigation: port only the
  simple parts (volume sum, modal mood, quality split) and pull intensity
  straight from `workout_features` rather than recomputing weights.

### Option B — `trends-timeline` read-only edge function (recommended)

A new edge function returns the prebuilt `[TrendsWeek]` JSON, computing weeks
with `weeklyAnalytics.ts` so the math has one home.

- **Pros:** canonical math reused (no drift); thin, cacheable client; the same
  endpoint can later serve the coach surfaces. **No LLM**, so it does **not**
  trip the eval-coverage CI gate (hard rule #3 / `check_eval_coverage.py` only
  fires on `_shared/prompts/` changes) — but it does need unit tests (§11).
- **Cons:** one new edge function to write, deploy, and version.

**Recommendation:** **Option B.** Keep the weekly math in TypeScript where it
already lives and is tested (`weeklyAnalytics` has sibling `.test.ts` files).
Option A is an acceptable v1 if we need to ship before a backend deploy window —
in that case, isolate the Swift aggregation behind the `TrendsService` protocol
(§6) so swapping to the endpoint later is a one-file change.

The rest of this spec assumes Option B, and flags the Option-A deltas inline.

---

## 5. Backend — `trends-timeline` edge function

Location: `supabase/functions/trends-timeline/index.ts`. Follows the patterns in
`_shared/{auth,cors}.ts`. Read-only; **no writes, no LLM, no service-role** (runs
under the caller's JWT so RLS scopes every read to the user).

### 5.1 Request / response

```
POST /functions/v1/trends-timeline
{ "user_id": "<uid>", "weeks": 26 }     // weeks ∈ {4,12,26}; server may always
                                        //   return 26 and let the client slice.
```

```jsonc
{
  "weeks": [
    {
      "week_start": "2026-05-25",       // Monday, ISO date
      "month": "May",
      "date_label": "May 26",           // label uses the week's representative day
      "miles": 49.0,
      "quality_miles": 13.0,
      "key_pace_sec": 403,              // null when no quality session
      "mood": "positive",              // null/"" when no logs that week
      "niggles": ["R achilles"],
      "voice_quote": null               // verbatim or null
    }
    // … oldest → newest
  ],
  "generated_at": "2026-06-15T15:00:00Z"
}
```

Return **all 26 weeks** including empty ones (a week with zero runs is a
first-class state — the gap is signal, see §8). The client slices to the
selected range; this keeps the window switch instant with no refetch.

### 5.2 Week-building algorithm

1. **Boundaries.** Generalize `getLastWeekBounds` to produce 26 consecutive
   Mon–Sun windows ending with the current (partial) week. Use the user's
   profile timezone for the day cutoff, not the server's, to avoid the
   travel/DST off-by-one (same concern `DailyReadService` documents).
2. **Fetch once.** Pull `training_logs` (running types only) and `body_mentions`
   for `[oldestMonday, today]`, plus `workout_features` joined by
   `training_log_id`. One query per table over the window.
3. **Per week:**
   - `miles` = Σ `workout_distance_miles` for running logs (exclude
     `cross_training`, `strength`, `rest`).
   - **Quality classification** (per log): quality if
     `workout_features.intensity_score ≥ QUALITY_THRESHOLD` (preferred), else
     fall back to `getEffectiveType(log) ∉ {easy, recovery, long}` exactly as
     `weeklyAnalytics.computeAllMetrics` does. `quality_miles` = Σ miles of
     quality logs. *Pick `QUALITY_THRESHOLD` to match the existing easy/workout
     boundary; calibrate against a week we agree on.*
   - **Key session** = the quality log with the highest `intensity_score` (ties
     → longest duration). `key_pace_sec` = its `workout_pace_per_mile` parsed to
     sec/mi, or `round(duration_min*60/distance_mi)`. Use `paces.ts` parsing —
     do not hand-roll.
   - `mood` = modal `training_logs.mood` for the week (reuse `analyzeMood`'s
     distribution; take the argmax instead of the score). Tie-break to the most
     recent log's mood.
   - `niggles` = distinct `"<side?> <body_area>"` from `body_mentions` where
     `mentioned_at` ∈ week. Order by `mentioned_at`.
   - `voice_quote` = the week's most severe/most recent `verbatim_quote`
     (`severity_hint` ordering `sharp > pain > sore > tight`), else null.

### 5.3 Brand/contract guards (server-side)

- **Niggles:** emit only `body_area`, `side`, and the **verbatim** quote. Never
  attach an interpretation, diagnosis, or `severity_hint`-derived label that
  reads as a judgment. The closed vocabulary is already enforced at write time
  in the `body_mentions` writer; this endpoint must not invent entries.
- **Cross-training** never contributes to `miles` / `quality_miles`.
- **No prediction fields** here — fitness range lives in its own layer (§10) and
  must ship as range + confidence.

---

## 6. iOS — `TrendsService` + view wiring

Add `RunningLog/Trends/TrendsService.swift`, an `@Observable` singleton mirroring
`DailyReadService` (cache + fetch + lifecycle).

```swift
@Observable
final class TrendsService {
    static let shared = TrendsService()
    private(set) var weeks: [TrendsWeek] = []     // full 26, oldest → newest
    private(set) var isLoading = false
    private(set) var lastError: Error?

    @MainActor func refresh() async { /* POST trends-timeline, decode, map */ }
}
```

- **Decode → map.** Decode the endpoint payload, map `key_pace_sec`,
  `quality_miles`, etc. into `TrendsWeek`. The `month`/`date_label` come from the
  server; if going Option A, compute them on-device from `week_start`.
- **View change is minimal.** In `TrendsTabView`, replace
  `private var window: [TrendsWeek] { TrendsSampleData.window(range) }` with a
  slice of `TrendsService.shared.weeks` by `range.rawValue`, and add
  loading/empty/error branches (§8). The chart and insights are unchanged —
  they already consume `[TrendsWeek]`.
- **Lifecycle.** Call `refresh()` from `.task` when the tab first appears, and
  on foreground (mirror the `scenePhase` hook in `RunningLogApp`). Cache in
  memory; the data only changes when a new run syncs. Optionally invalidate when
  `WorkoutSyncService` reports new logs.
- **Keep the protocol seam.** Define `TrendsDataProviding` with
  `func loadWeeks() async throws -> [TrendsWeek]` so Option A (local) and Option
  B (endpoint) are interchangeable and previews can inject `TrendsSampleData`.

---

## 7. The ask-bar handoff (Phase 4 alignment)

Today the ask bar sets `selectedTab.wrappedValue = 2` (jumps to The Read). The
real behavior: deep-link into the Coach conversation **pre-seeded with the
scrubbed week's context**, reusing the existing `DailyReadService.ask(_:)` path
(which already POSTs `coaching-agent` with `format: "editorial"`).

- Add a lightweight shared `CoachAskContext` (`@Observable`) holding an optional
  `pendingQuestion: String?` and `focusWeek: TrendsWeek?`.
- On ask-bar tap, set e.g. `"How did the week of \(week.dateLabel) actually
  go?"` (or open an empty composer with the week as context), then switch to
  tab 2. The Read view consumes and clears `pendingQuestion` on appear.
- **Eval gate applies here, not to the timeline.** The `format: "editorial"`
  branch of `coaching-agent` is an LLM prompt change — per hard rule #3 it needs
  cassette coverage in `_evals/cassettes/` before shipping (this is already
  flagged as Phase 4.2 in `coach-the-read-prompts.md`). The `trends-timeline`
  endpoint has no LLM and needs only unit tests.

---

## 8. States — loading, empty, gaps, errors

Per hard rule #8, **no em-dash placeholders**; use `EmptyStateView`
(eyebrow + plain-prose nudge + optional CTA).

- **Loading:** skeleton of the chart bands while `isLoading && weeks.isEmpty`.
- **New user / thin data (`data_depth` 0–1):** the chart should not pretend.
  Gate on the same `data_depth` signal the rest of the app uses — below depth 2,
  show an empty state ("Your training shapes this view. Log a few runs and the
  timeline fills in.") instead of a near-empty chart.
- **Empty week (zero runs):** render the gap honestly — no bar, no pace dot, mood
  track blank for that column. The absence is the point (down weeks, illness).
- **No quality session in a week:** `key_pace_sec == nil` → no pace dot (already
  handled by the chart).
- **Error:** keep the last good `weeks` on screen if present; otherwise an empty
  state with a quiet retry. Mirror `DailyReadService.lastError` handling.

---

## 9. Edge cases

- **Week boundaries / timezone / DST:** bucket in the user's profile tz; the
  current week is partial — label it but don't extrapolate.
- **Partial HealthKit backfill:** the 2-year backfill (Maya onboarding) may
  arrive after first paint; `refresh()` on foreground picks up late syncs.
- **`workout_features` not yet computed:** `compute-workout-features` is async.
  Fall back to `workout_type`-based quality classification (the
  `weeklyAnalytics` fallback path) so a just-synced week still renders, then
  refines on next load.
- **Mood missing for a week:** modal mood over zero logs → no mood dot; don't
  default to "neutral" (that would fabricate a feeling).
- **Niggle dedup:** one mention per `(log, body_area)` is already enforced by the
  unique index; still dedup by label per week for display.
- **Cross-training weeks:** a week of only cross-training shows zero running
  miles (correct) but should not read as a "missed" week in copy.

---

## 10. Future layers (additive; design the contract now)

The chart and `TrendsWeek` should leave room for these without a rewrite:

- **Race-anchored fitness range** — a band/marker overlay from
  `FitnessPredictorService` / `race-readiness`, anchored on `confirmed_races`
  (goal time is fallback). **Must render as range + confidence** (e.g.
  `~32:10–32:48 · HIGH`), never a point (hard rule #7). Add
  `fitnessRange`/`fitnessConfidence` to a future `TrendsWeek` or a parallel
  series.
- **ACWR / load band** — from `athlete_state.acwr` (already projected by
  `TrendsAthleteState`); a faint band behind volume showing the sweet spot
  (0.8–1.3) vs spike (>1.3).
- **Sleep** — a fifth track from HealthKit sleep, once Recovery (v1.5) promotes
  it to a first-class signal.

---

## 11. Testing

- **Backend (`trends-timeline`):** unit tests beside the function (Deno test,
  matching the `_shared/*.test.ts` style). Cover: Mon–Sun bucketing across a
  month/year boundary and DST; quality classification with and without
  `workout_features`; modal mood + tie-break; niggle windowing; an empty week;
  a cross-training-only week. **No eval cassette needed** (no LLM).
- **iOS:** unit tests for the decode→`TrendsWeek` mapping and the range slice;
  snapshot/preview checks for loading/empty/error and a thin-data (`data_depth`
  0) state. Add a `TrendsDataProviding` mock returning `TrendsSampleData`.
- **Parity check:** for one agreed week, assert `miles`/`quality_miles` from the
  endpoint match `weeklyAnalytics.aggregateWeeklyLoad` on the same logs (guards
  against drift if any Swift-side math is introduced).
- **Manual:** verify against Maya's narrative — the niggle rings should land in
  the highest-mileage weeks; the pace line should fall while volume climbs.

---

## 12. Phasing

1. **Phase 1 — endpoint.** Build + test `trends-timeline`; deploy. (Or Option A
   local aggregation behind `TrendsDataProviding` if blocked on deploy.)
2. **Phase 2 — iOS wiring.** `TrendsService`, replace `TrendsSampleData` in the
   view, add states + `data_depth` gate, lifecycle/refresh.
3. **Phase 3 — ask handoff.** `CoachAskContext`, deep-link + pre-seed; land the
   `coaching-agent` `format:"editorial"` eval coverage (Phase 4.2 dependency).
4. **Phase 4 — additive layers.** Fitness range (range+confidence), ACWR band.

No new tables or migrations are required for Phases 1–3 (the `body_mentions`,
`workout_features`, `athlete_state` tables and indexes already exist). If any
backend write is later added, it follows the RLS-in-same-migration and
append-only rules.

---

## 13. Open questions

- **`QUALITY_THRESHOLD`** for the intensity split — pin to the existing
  easy/workout boundary, or expose a per-athlete value? Needs one calibration
  pass on a known week.
- **Key-session selection** — highest intensity, or the session the athlete
  (or plan) considered the "key" workout? For self-coached Maya, intensity is a
  fine proxy; revisit for plan-following athletes.
- **`voice_quote` source** — only `body_mentions.verbatim_quote`, or also pull a
  representative line from `training_logs.cleaned_notes` on non-niggle weeks?
- **Refresh trigger** — foreground only, or also subscribe to
  `WorkoutSyncService` completion?

---

## 14. Acceptance criteria

- The chart renders real `training_logs` / `body_mentions` data for the signed-in
  user, RLS-scoped, across 4/12/26-week windows with no refetch on window switch.
- `miles`, `quality_miles`, `key_pace_sec`, `mood`, `niggles` match the source
  rows for a hand-checked week (parity test passes).
- Niggles display verbatim, closed-vocabulary, with no interpretation; no
  em-dash placeholders anywhere; empty/thin-data states use `EmptyStateView`.
- The ask bar opens The Read pre-seeded with the scrubbed week's context.
- No regression to the existing four tabs; `selectedTab` jumps still resolve
  correctly (Trends is tag 4, Training 1, The Read 2 — unchanged).

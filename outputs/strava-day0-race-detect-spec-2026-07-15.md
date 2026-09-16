# Strava Day-0 Onboarding — Backfill, Race Detection & Confirm Flow

**Date:** 2026-07-15
**Status:** Build spec, ready for implementation
**Goal:** A new athlete with a Strava training history lands in a product
that already knows them: history imported, races detected and confirmed,
pace zones anchored on real fitness, and a first Read with something true
to say — all on day 0.
**Extends:** `outputs/race-performances-feature-plan.md` (the race-anchor
design; its ten product decisions all apply here). This doc adds the
Strava-specific detection path, the onboarding backfill, and the confirm
UX. It does not change the anchor-selection math.

---

## 1. Why Strava is the strong path

Strava athletes explicitly tag races. The activity `workout_type` field
(runs: `1 = Race`, `2 = Long Run`, `3 = Workout`) is athlete-declared at
upload time, and activity names carry event names ("Boulder Half
Marathon"). This means the Strava detection problem is mostly *reading a
flag we already store*, not inferring from pace statistics. HealthKit
detection (pure heuristics) stays as the fallback path per the feature
plan; this spec makes Strava the flagship.

## 2. What exists today vs. the gaps

| Piece | State | Gap |
|---|---|---|
| `strava-sync` edge fn | Production-grade: cron, incremental watermark, dedup on `vital_workout_id`, token rotation, laps + streams, voice-orphan reconcile | First-sync lookback is **60 days** (`DEFAULT_LOOKBACK_DAYS`, overridable to 365 via body) |
| Strava race flag | Captured: `external_streams.meta.workout_type` | **Nothing reads it.** Not mapped to `training_logs.workout_type='race'`, not fed to `confirmed_races` |
| Activity name | Stored in `cleaned_notes` + `meta.name` | Not scanned for race-like strings |
| `confirmed_races` | JSONB on `athlete_state`; derived from `workout_type='race'` rows | No Strava writer populates that trigger condition |
| `race_suggestions` table | Specced in the feature plan | **Not yet migrated** |
| iOS Strava connect | Onboarding toggle is display-only; OAuth exchange exists only in `strava-test-pull` (`action: "exchange"`) | No production connect flow |
| Fitness predictor | Bails without a hard effort/race; confidence reads `workoutType === "Race"` | Works day 0 *if* backfill + race mapping land |

## 3. The day-0 flow (end to end)

```
Onboarding step 2 "Connect data"
  ├─ Apple Health  → existing permission ask (unchanged)
  └─ Strava        → REAL OAuth (new)
        │  ASWebAuthenticationSession → strava.com/oauth/authorize
        │  → callback code → POST strava-connect (new fn) → strava_credentials row
        ▼
First sync fires immediately (not waiting for cron)
        │  strava-sync invoked with { lookbackDays: 365, mode: "onboarding" }
        │  Phase 1: summary import (fast — see §5 rate-limit design)
        ▼
Race detection runs on the imported rows (pure function, no LLM)
        ▼
"HERE'S WHAT WE FOUND" screen (new onboarding step, replaces dead time)
        │  "212 runs · 1,340 miles over the last year"
        │  "3 look like races — confirm them and your paces calibrate today:"
        │    ☑ Apr 12 · Half Marathon · 1:32:04 · "Eugene Half"   [confirm] [edit] [not a race]
        │    ☑ Feb 8  · 10K · 41:30                               [confirm] [edit] [not a race]
        │    ☐ Nov 2  · Marathon · 3:28:11 · "CIM"                [confirm] [edit] [not a race]
        │  "Anything we missed?" → manual entry (existing path)
        ▼
Confirm → confirmed_races (service-role write) → selectFitnessAnchor()
        ▼
Lands on Log. Trends populated, pace zones anchored, data_depth fast-path
to 3 (feature plan §integration 3), first Read has a year of evidence.
```

If the athlete skips Strava or has no races: fall through gracefully.
The screen still shows the volume summary (that alone is a "it knows me"
moment); the race list section shows the empty-state component with the
manual-entry CTA. Never a blocker, never a blank.

## 4. Detection heuristic — `_shared/raceDetection.ts`

Pure function, deterministic, unit-tested, **no LLM** (mirrors the
feature plan's rule for `selectFitnessAnchor`). Input: an array of
imported `training_logs` rows (+ `external_streams.meta`). Output: scored
candidates mapped to the feature plan's three tiers.

### Signals

**S1 — Strava race flag** (`meta.workout_type === 1`). Athlete-declared.
Strongest single signal; ~zero false-positive rate.

**S2 — Race-like name.** Case-insensitive match on `meta.name` /
`cleaned_notes` against a closed pattern set:
- distance words: `5k, 10k, 15k, half, marathon, HM, 13.1, 26.2, mile`
- event words: `race, championship, classic, invitational, parkrun, relay, marathon` + a 4-digit year
- Exclusions: `pace, paced, pacer, workout, tempo, MP, long run, shakeout, DNF-context handled in edit`

**S3 — Canonical distance.** Within tolerance of 5K / 10K / 15K / 10 mi /
HM / M / 50K. Strava distances run long (GPS + weaving): tolerance is
**−0.5% / +2.5%** asymmetric around canonical.

**S4 — Pace outlier.** Activity's average pace > 2 SD faster than the
athlete's trailing-60-day median pace for runs of comparable duration
(computed within the backfill window itself — this works retroactively).

**S5 — Race-day pattern.** Weekend or holiday, start 06:00–10:00 local
(`meta.start_date_local` / `utc_offset`), even or negative splits from
`pace_segments`.

### Tier mapping (extends feature plan §Entry)

| Evidence | Tier | Action |
|---|---|---|
| S1 + S3 | **Tier 1 auto-confirm candidate** — but during *onboarding* everything routes through the confirm screen anyway (pre-checked ☑). Post-onboarding nightly runs may auto-confirm per feature plan decision 10. | write `confirmed_races` on confirm; `source: 'auto_suggested_confirmed'` |
| S1 alone (odd distance) or (S2 + S3) or (S2 + S4) | **Tier 2 suggest as race** (pre-checked ☑ when score high, unchecked when marginal) | `race_suggestions` row, `status: 'pending'` |
| S4 + S3, no S1/S2 | **Tier 3 suggest as time trial** (decision 8) | `race_suggestions`, `suggested_category: 'time_trial'`, unchecked |
| S4 alone | ignore (hard workout, feeds the predictor as a hard effort anyway) | — |

Scoring is additive with fixed weights (S1: 0.6, S2: 0.25, S3: 0.15,
S4: 0.15, S5: 0.05, cap 1.0); `classifier_confidence` on the suggestion
row is this score. Weights live as named constants with a comment table;
tune against real backfills before launch (see §9 validation).

### Finish-time extraction

`finish_time_seconds` = moving time **unless** elapsed ≈ moving (±90s),
in which case elapsed (races rarely pause). For distances that run long
(S3 tolerance), report the athlete's actual time at the canonical
distance is NOT interpolated — use total time, flag `official: false`.
The edit sheet lets the athlete enter chip time; athlete edit wins
(decision 9).

### Known traps (handled)

- **Pacing duties / B-races:** athlete confirms but tags `effort_flag`
  in the edit sheet — the context multipliers (feature plan decision 6)
  downweight, so a paced 4:00 marathon doesn't become the anchor ceiling.
- **parkruns:** weekly 5Ks match S2+S3. Fine — they're honest 5K
  efforts; suggest as race, default unchecked, athlete decides.
- **Relays/ultras/odd distances:** S1 without S3 → Tier 2 with
  `distance_label: 'OTHER'`; excluded from anchor math by
  `selectFitnessAnchor`'s canonical filter, still shown in history.
- **Treadmill:** no GPS streams → S4/S5 unavailable; S1/S2 still work.
- **Very stale races:** detect over the full 365-day window (history has
  value), but the anchor selector's 180-day staleness cap (feature plan)
  keeps old races from driving zones.

## 5. Backfill changes to `strava-sync`

The blocker for `lookbackDays: 365` is Strava's rate limit (100 requests
/ 15 min, 1,000/day per app default). Today's sync does ~3 calls per
activity (detail + streams). A 260-activity year ≈ 780 calls — blows the
15-min window. Fix: **two-phase onboarding sync**.

- **Phase 1 — summary sweep (onboarding-blocking, seconds):** paginated
  `/athlete/activities?after=<365d>&per_page=200` (1–2 calls). Insert
  summary-only rows (`processing_status: 'summary_only'`, no
  streams/laps). Summaries carry `workout_type`?? — **no**: the race
  flag lives on the detail payload. But summaries DO carry `name`,
  distance, times, HR aggregates → S2–S5 run immediately.
- **Phase 1.5 — detail fetch for race candidates only:** the detector's
  S2–S5 shortlist (typically 3–15 activities) gets detail calls first,
  confirming/adding S1 before the confirm screen renders. Budget ≤20
  calls. The confirm screen waits on this (≤15s, matching the feature
  plan's onboarding budget).
- **Phase 2 — trickle backfill (background):** existing
  `needsStreamsBackfill` path already upgrades summary rows to full
  streams; extend the cron worker to drain `summary_only` rows at ~60
  activities/15-min window, newest first. Full richness lands within
  hours; nothing user-facing waits on it.

Also: onboarding-triggered first sync is invoked directly (service-role,
from the new `strava-connect` fn) rather than waiting up to 15 min for
cron. Watermark semantics unchanged.

### Race-flag mapping (one-line but load-bearing)

When detail lands with `workout_type === 1`, also set
`training_logs.workout_type = 'race'` on the row. That's the field
`athlete-state.ts` already reads to derive `confirmed_races` candidates
and the fitness predictor reads for confidence — it closes the loop with
zero new consumers.

## 6. New/changed components

| Component | Kind | Size |
|---|---|---|
| `strava-connect` edge fn — OAuth code exchange (port from `strava-test-pull`'s exchange action), writes `strava_credentials`, fires first sync | new fn | ~0.5d |
| iOS `StravaConnectService` + real button in `OnboardingView` step 2 (ASWebAuthenticationSession; remove the fake `@State` toggle) | iOS | ~1d |
| `_shared/raceDetection.ts` + tests | new pure module | ~1d |
| `race_suggestions` migration + RLS (already specced in feature plan §data model; RLS in same migration per hard rule #1; service-role-only INSERT per hard rule #4) | migration | ~0.5d |
| `strava-sync` two-phase mode + race-flag mapping + `summary_only` drain | edit | ~1d |
| `confirm-races` edge fn — accepts confirm/edit/dismiss batch, writes `confirmed_races` JSONB + `race_result` on source rows, resolves suggestions (service-role write path; client never inserts) | new fn | ~0.5d |
| iOS "Here's what we found" onboarding step + confirm list + edit sheet (effort flag, conditions, chip time) | iOS | ~1.5–2d |
| `computeDataDepth` race fast-path + predictor reads `confirmed_races` | edits (already in feature plan v1 scope) | ~0.5d |

Total ≈ 6–7 focused days. The confirm screen and detection module are
the only genuinely new UX/logic; everything else is wiring.

## 7. Copy (Post Run Drip voice — declarative, no hype, no emoji)

- Volume line: `212 runs · 1,340 miles · last 12 months`
- Race section eyebrow: `LOOKS LIKE YOU'VE RACED`
- Lede: `Confirm these and your paces calibrate to real fitness — today.`
- Row: `APR 12 · HALF MARATHON · 1:32:04 · "Eugene Half"`
- Time-trial variant: `Hard effort, no race tag — time trial?`
- Empty race list: eyebrow `NO RACES DETECTED` + `That's fine — zones
  will calibrate from your training. Raced somewhere we can't see?` +
  CTA `Add a race`
- Post-confirm toast: `Anchored. Your zones now trace to your April half.`

Never a naked point estimate anywhere downstream: range + confidence
per hard rule #7.

## 8. What day 0 looks like after this ships

Fitness prediction gets: 12 months of volume trend, hard efforts via
`pace_segments` (parse-structure fires on backfilled rows already),
pace-at-HR efficiency trend (84-day window fully populated
retroactively), and 1–3 confirmed race anchors. That's every rung of the
evidence ladder except subjective signal — day-0 output is a cited range
at MEDIUM/HIGH confidence instead of "not enough data," and the "what
would tighten this" line points at logging + voice memos.

## 9. Validation before beta testers touch it

1. **Detector recall/precision on real data:** run `raceDetection.ts` as
   a standalone script against Rio's own Strava backfill + 2–3 soft-test
   friends (the launch plan's Prep-2 people). Target: zero missed
   athlete-tagged races, <20% dismiss rate on suggestions.
2. **Rate-limit rehearsal:** one full 365-day onboarding sync against a
   real account; confirm Phase 1+1.5 < 15s and no 429s.
3. **Unit tests:** tier mapping table above becomes the test matrix
   (one case per row + the five traps).
4. No LLM prompts change in this spec → no golden-cassette gate
   (hard rule #3) is tripped. The `formatRaceContext()` prompt injection
   from the feature plan remains a separate, cassette-gated task.

## 10. Out of scope (deliberately)

- HealthKit heuristic-only detection (feature plan Tier 2/3 without
  Strava signals) — same detector module runs on it later; weights
  need separate tuning because there's no S1/S2.
- Garmin path (`garmin-full-loop-plan-2026-07-03.md`) — same shape,
  Garmin also has an explicit race flag; plug into the same detector.
- Nightly post-onboarding auto-confirm (decision 10) — ship the
  onboarding queue first, add the nightly job in v1.1.
- 2-year backfill — Strava API supports it, but 365 days is the anchor
  staleness horizon ×2; revisit with the HealthKit 2-year work.

# Web Portal ↔ iOS App Parity Audit
**2026-08-20.** Fresh audit against source at `HEAD`, not against the briefs.
Supersedes `WEB-PORTAL-PARITY-PLAN.md` (2026-08-06), which is stale in both
directions — see §7.

**Direction:** web catches up to iOS. iOS is canonical for the athlete; the
coach portal stays deliberately web-only.

**Method:** every Swift file under `RunningLog/RunningLog/`, every file under
`web/src/`, and all 67 edge functions under `supabase/functions/` were read
and cross-referenced. Every claim below is anchored to `file:line`. What
could not be verified is listed in §9 rather than guessed at.

---

## 0. The one-paragraph version

The gap is **not** "web is missing a few screens." iOS ships **six** athlete
surfaces; web ships **three**, and the three it has are read-only mirrors.
An athlete can do **~24 things** to their training plan on iOS and **one**
thing on web. But the bigger problem is quieter: **the two clients compute
the same metrics differently and print different numbers for the same athlete
on the same day** — four separate ACWR formulas, three run-deduplication
rules, two pace-zone anchors, three week-boundary definitions. Closing the
screen gap without first closing the number gap ships a portal that
contradicts the app. §2 is the section to read first.

---

## 1. Where the two products stand today

### 1.1 Information architecture

| | iOS | Web |
|---|---|---|
| Primary nav | 6-tab bottom bar: **Log · Train · Trends · Week · Ask · Sheet** (`App/DripTabBar.swift:69-123`) | 3-item sidebar: **Log · Trends · Train** (`components/layout/sidebar.tsx:29-33`) |
| Nav idiom | dot + uppercase mono label, **no icons by design** (`DripTabBar.swift:5,12-15`) | lucide icons + coral left-bar |
| Secondary | hamburger → 7-item sidebar overlay | "Tools" (Niggles, Pace Chart, Coach Portal) + "Account" |
| Coach | `CoachTabView` — unmounted since 2026-07-28 | 12 routes, ~10,700 LOC — **canonical** |

The web sidebar comment still reads *"Main nav mirrors the iOS 4-tab IA
(Log · Trends · Train · Coach)"* (`sidebar.tsx:26-28`). That was true in
July. The bar has changed twice since: Week was added 2026-08-19 and Charts
became Ask the same day (`App/RunningLogApp.swift:150-155`).

**Three whole surfaces have no web route at all: Ask, Week, Sheet.**

### 1.2 Scale

| | iOS | Web (athlete) | Web (coach) |
|---|---|---|---|
| Source files | 308 Swift | ~60 tsx/ts | ~50 tsx/ts |
| Edge functions called | **40** | **4** | **5** (all coach-only) |

That "40 vs 4" line is the whole audit in one number. iOS reads
server-computed values; web recomputes them locally in TypeScript. §2 is
what that costs.

---

## 2. THE NUMBERS DON'T MATCH — read this first

This is the finding that changes sequencing. These are not cosmetic; an
athlete comparing phone to laptop today sees different figures.

### R1 · ACWR — four implementations, and web contradicts itself
| # | Where | Formula | Shown to |
|---|---|---|---|
| 1 | `_shared/builders/buildLoadMetrics.ts:87-96` | **intensity-weighted** load, `7d / (28d/4)` | iOS Trends, **and web's own coach dashboard** (`lib/coach-dashboard/from-supabase.ts:322,905`) |
| 2 | `_shared/weeklyAnalytics.ts:233-255` | intensity-weighted, **exponentially-weighted** chronic `[4,3,2,1]`, calendar weeks | iOS Ask "Am I ramping too fast?" |
| 3 | `compute-workout-features/index.ts:352-354` | raw miles | internal only |
| 4 | `web/src/app/(app)/trends/page.tsx:230-238` | **raw miles**, gated `chronicWeekly >= 5` | **web athlete Trends tile** |

Web's athlete page and web's own coach page disagree with each other. Band
labels differ too: web has a `>1.5 high` tier the server model doesn't
(`trends/page.tsx:242-248` vs `from-supabase.ts:906-908`). And #1 vs #2 means
**iOS itself shows two different ACWRs one tap apart**.

### R2 · Zone volume — web books a whole run into one bucket
Web assigns an entire run's mileage to the zone nearest its *average* pace
(`trends/page.tsx:311-324`). Server/iOS bin **per lap**, on **heat-adjusted**
pace, time-weighted (`trends-timeline/paceBands.ts:21-27`).

A 10-mile session of 2 WU + 5 @ LT + 3 CD averages to Steady. Web books all
10 miles Steady; iOS books 5 easy + 5 threshold. The error is largest for
exactly the sessions that matter most. It feeds `/train` HISTORY too.

Worse: with no pace table, web falls back to a frozen ladder for a
**7:30/mi-MP reference runner** (`workout-helpers.ts:489-492`), where the
server refuses and says so (`workoutSegmentation.ts:187` — *"can't do better,
don't lie"*).

### R3 · Weekly mileage — three dedup rules; web double-counts
| Impl | Match window | Source policy |
|---|---|---|
| Server `_shared/shared/dedup.ts:34-52` | ±0.2 mi **and** ±2 min | keep richest across all sources |
| iOS `App/LogDedup.swift:40-92` | ±0.1 mi | drop non-GPS when any GPS exists, then priority |
| Web `lib/run-metrics.ts:22-38` | ±0.3 mi | **only drops `voice_log`/`check_in`** |

An athlete on both Strava and HealthKit has **every run counted twice** in
every web mileage figure. This is the input to R1 and R2, so it multiplies.

### R4 · Rep detection — web invents its own threshold
Server: a lap is work if its **pace zone** ∈ `{mile,3k,5k,10k,hmp,mp}` plus
`MIN_REP_SECONDS`/`MIN_REP_METERS` (`_shared/workoutSegmentation.ts:388-433`).
iOS consumes that. Web: `pace ≤ bandHigh`, else `median − 15 s/mi`, with no
minimum duration and no `is_rest` respect
(`lib/coach-dashboard/workout-enrichment.ts:260-269`).

Coach and athlete looking at the same Tuesday see different rep counts.

### R5 · Pace zones diverge the moment the athlete corrects their fitness
`set-fitness-anchor` sits at the **top** of PaceEngine's precedence
(`_shared/pace-engine.ts:283-292`) and is **iOS-only**
(`Analysis/AdjustFitnessSheet.swift:199`). Web's `derivePaceTableFromGoal`
has no concept of it (`workout-helpers.ts:869`). Correct your fitness on the
phone; every web zone keeps the old ladder.

There are also **three** pace-zone implementations, and only two are pinned
by the contract test (`_shared/cross-language-pace-contract.test.ts:49,109`).
`pace-chart-client.tsx:43-56` is a third, unpinned copy — already drifting
(`26.2188` vs `26.21875088` vs `26.21875`).

### R6 · Week boundaries — athlete-local vs host-local vs UTC
- iOS: athlete's timezone, three-step ladder (`Shared/AthleteTimeZone.swift:15-31`)
- Web: `new Date()` **inside a server component** → Vercel host time (`trends/page.tsx:73-75`, `train/page.tsx:49-52`)
- Server: UTC, documented (`trends-timeline/timeline.ts:19-21`)

`grep -rn "timezone\|athlete_settings" web/src` → **zero matches.** A Sunday
18:00 run in UTC-7 is Monday UTC. "This week's mileage" differs by whole runs.

### R7 · Heat adjustment — one server fork, one wrong web constant
`reconcile-log/index.ts:23` imports `_shared/pace-heat.ts:70-96`, which omits
`repLengthFactor` and `intensityFactor`. Every other consumer uses the full
`pace-heat-adjustment.ts`, which iOS mirrors verbatim
(`Workouts/PaceCalculator.swift:430-454`).

Separately, `workout-enrichment.ts:35` sets `DEW_HOT_F = 68` by borrowing a
constant from `adaptation-rules.ts:230` that governs *forecast-day workout
swaps*, not retroactive pace adjustment — then asserts at `:151` *"every lap
carried a heat adjustment."* That is false against the model. iOS's floor is
**55°F** (`PaceCalculator.swift:27`). The 55–68°F dew band is most temperate
mornings, and in it iOS shows heat-adjusted paces while web says conditions
were unremarkable.

### R8 · Workout-type buckets — seven competing sets, no shared port
`lib/workout-label.ts` **is** a faithful port of `App/WorkoutLabel.swift`
(case-for-case, including `tempo → Threshold`). But it isn't adopted:

- `train/page.tsx:73-79` rolls its own `formatWorkoutType` → `long_wo` renders as **"Long Wo"**
- `from-supabase.ts:176-197` is a second label map → still renders **"Tempo"** (retired)
- `move-day-sheet.tsx:60-63` and `train-calendar.tsx:34-40` are a third and fourth copy
- `train/page.tsx:58-68` `QUALITY_TYPES` includes non-existent `hill_repeats`/`time_trial` and **omits `long_wo`** — so a long-run workout never gets quality treatment anywhere on web

### R9 · Web-only pace formatter can print `7:60`
`app/(app)/log/workout-detail.tsx:507-511` floors minutes and *separately*
rounds seconds. At 419.7 s it prints `6:60`. Correct implementations exist on
both sides and round the total first (`App/DesignSystem.swift:57-61`,
`lib/vital.ts:490-495`).

### R10 · Web fetches by `created_at` and buckets by `workout_date`
`trends/page.tsx:86-87` filters `created_at >= historyStartISO`; every bucket
keys off `workout_date || created_at` (`:158,163,233,259,276,308,359`). Same
pattern in `train/page.tsx:184` vs `:299,347,377`. A run backfilled today for
a date months ago is fetched but lands outside every window; a run from three
weeks ago created 70 days ago is never fetched. **This silently drops real
runs today**, independent of any parity work.

### R11 · Almost none of this is pinned by a test
`_shared/cross-language-pace-contract.test.ts` reads exactly two foreign
files (`:49` `PaceModels.swift`, `:109` `workout-helpers.ts`).
`find web -name "*.test.*"` → **0 results**. So `run-metrics.ts`,
`workout-enrichment.ts`, `from-supabase.ts`, `pace-chart-client.tsx`,
`trends/page.tsx`, `train/page.tsx` — every file in R1–R10 — is pinned by
nothing.

`key-session.ts:6-7` claims *"There is a fixture test pinning them together."*
No such test exists in the tree, and its sibling reference
`Training/KeySession.swift` (`key-session.ts:4`) is a file that does not
exist. The values do currently agree (`QUALITY_LOAD_FLOOR = 25` matches
`QualityLoad.floor = 25`) — nothing keeps them there.

> **The template for fixing all of this already exists in the repo.**
> On 2026-08-17 iOS deleted its own 853-line race predictor rather than keep
> it as a fallback, because *"it could not agree with the server and never
> will… it showed a 2:37 marathon while the server held 2:29:13"*
> (`Analysis/FitnessPredictorService.swift:294-312`). That is the correct
> resolution of every item in this section: **one implementation, server-side,
> both clients read it.**

---

## 3. The athlete can't *do* anything on web

### On iOS — 24 athlete write actions
Mark complete · skip · swap two days · move one day (AI) · reschedule week ·
reschedule remaining plan · edit workout steps inline · structured workout
builder · natural-language workout entry · workout from template · AI workout
chat · duplicate workout to another day · restructure a day · add workout to
a rest day · convert day to rest · set per-workout run hour (drives heat
forecast) · export workout to FIT · adjust goal · recompute paces · import a
plan (text/file/photo) · import a single week · join a coach's plan by code ·
edit subscription preferences · delete plan · mark a day a key session.

(Entry points and write paths: `Training/DayDetailSheet.swift`,
`TrainingPlanService.swift`, `TrainingPlanView.swift:110-166`.)

### On web — one
**Move a scheduled workout to another day inside the current Mon–Sun week**
(`components/plan/move-day-sheet.tsx:111-136` → `app/api/shift-day/route.ts:44`).

Everything else is read-only or stubbed:
- "Reshape this week" — `disabled`, `title="Coming soon"` (`train/page.tsx:462-470`)
- "Why this?" — `disabled`, `title="Coming soon"` (`train/page.tsx:641-651`)
- "Set a goal race" → `/settings`, which says *"Profile editing is managed through the iOS app"* (`settings/page.tsx:66-69`) — **a dead-end CTA**
- Pace-chart goal entry is what-if only — zero `supabase`/`fetch` calls in that file
- No mark-complete, skip, swap, add, delete, step editing, import, join-plan, or key-session toggle
- The no-plan empty state literally says *"set up a goal race in the iOS app"* (`train/page.tsx:481`)

### Capture is gone, not deferred
`grep MediaRecorder|getUserMedia web/src` → **0**. `<audio>` → **0**.
`log-front-door.tsx:1-3` is a tombstone: *"Removed. The web Log follows the
desktop feed + rail design (no mobile record-button front door). Safe to
delete this file."*

That reverses decision #3 of the Aug 6 plan (*"Voice capture on web — yes,
full parity"*). **No decision record for the reversal exists anywhere in the
repo.** Flagging rather than assuming — this needs a call. Note that browser
mic capture is *not* platform-blocked; `MediaRecorder` works over HTTPS. Only
HealthKit is genuinely iOS-only.

### Web also can't
Sign out (`grep signOut web/src` → **0**), delete an account, resolve a
niggle, revert a plan adjustment, set the fitness anchor, create a workout,
upload a voice memo, edit a scheduled workout's structure, export CSV or FIT,
back up, or restore.

---

## 4. Surface-by-surface gap summary

Full detail in the appendix tables. Headline verdicts:

### LOG
Web's journal is genuinely decent — week grouping, mood hues, badges,
processing states, inline edit — and it has **two things iOS doesn't**:
Supabase realtime push (`journal-view.tsx:125-176`) and a stats rail
(`:268-444`).

Missing on web: all capture, **memo playback**, **verbatim transcript**,
journal search, kind-filter chips, per-row niggle chips, key-session star,
the athlete's own `title` (never even selected —
`lib/workout-detail.ts:105-107`), the book-style detail pager, SIGNALS chips,
the rep-structure editor, unit toggle, HR-drift, per-rep HR recovery,
**the route map** (`external_streams` → 0 hits in `web/src`), scrubbable
telemetry, and workout comparison.

Two structural problems:
1. **The journals show different rows.** iOS filters `audio_url ∨ voice_log ∨ manual ∨ check_in` (`VoiceLogViewModel.swift:512-514`); web filters `source ≠ auto_sync` (`log/page.tsx:20-22`). An `auto_sync` row *with a memo attached* — exactly what iOS's own attach path produces — shows on iOS and is **invisible on web**.
2. **Web has two disconnected workout-detail implementations** — the lap-based `/workouts/[logId]` route and the Vital-stream `log/workout-detail.tsx` panel. No shared formatters, no shared palette, and they disagree about which way is fast (`pace-trace.tsx:68` inverts the y-axis; `workout-detail.tsx:379` doesn't). Consolidating them is a **prerequisite** for the chart gaps, not a follow-up.

### TRENDS
iOS renders six numbered blocks driven by **one time control** (4/12/26 wk),
all fed by the `trends-timeline` edge function. Web renders nine sections,
each with its **own hardcoded window** (63d fetch, 6wk bars, 30d niggles, 4wk
mood, 14d recent), all recomputed locally from raw `training_logs`.

Missing on web: the range segmenter, pace-spectrum histogram, threshold/pace
bands, **the recovery-score ledger** (0–96 with a foldable factor receipt),
the recovery read, race prediction, HRV/sleep, stress load, Signal Lab, and
head-to-head compare. Web-only: goals strip, injury timeline.

> ⚠️ **Correction to `CLAUDE.md`:** it maps Trends to `TrendsTabView.swift`.
> That file is a ~100-line host; the surface that actually renders is
> **`TrendsLegacyTabView.swift`** (`TrendsTabView.swift:61,70-78`).
> `TrendsV2View.swift` is unlinked, reachable only via `-trendsV2Preview`.
>
> ⚠️ **Second correction:** `CLAUDE.md` says the Week tab is fixture-driven.
> It is not — `WeekService.refresh()` builds from real rows
> (`WeekService.swift:49-61`). Three *sections* are unavailable-by-design;
> the tab is live.

### TRAIN
Both have the three-mode segmenter (CURRENT/CALENDAR/HISTORY) — that's the
match. Beyond it, web is missing the WEEK/MONTH/BLOCK scope toggle, the week
summary strip, the completed-run line on Today, weather forecast, per-run
conditions, mood badges on day rows, week paging, the training-load strip,
tappable calendar days, key-session stars, the plan block, the goals block,
the session-receipts ledger, the easy/hard 80/20 bar, and chart drill-downs.

### Design system
**Tokens are near-perfect parity** — the 10-stop pace ramp is byte-identical
(`PaceSpectrum.swift:32-43` ↔ `globals.css:29-38`), as is the mood palette
and coral/paper/ink. Crimson Pro + PT Serif are self-hosted correctly.

**Primitives are ~40% ported.** Missing on web: `Hairline`, `DripStatTile`,
`DripStatStrip`, `DripMoodRadio`, `PlateFooter`, `DripTextLink`,
`DripWeekStrip`, `DripRaceStrip`, `DripZoneBar`, all 12 workout chart
primitives, the whole Instruments card kit, `ErrorStateView`,
`AsyncContentView`, `ToastBanner`, and `PlaceholderNote`.

**Web has no error boundary at all** — no `error.tsx`, `not-found.tsx`, or
`global-error.tsx` anywhere. An unhandled render throw shows the Next.js
default page.

**Web has no type scale.** iOS has five named ramps with fixed sizes; web
hand-types every Tailwind bracket, and tracking drifts across at least six
values (`0.18em`, `0.12em`, `0.1em`, `0.08em`, `0.05em`, `1.5px`).

Rule violations worth naming:
- **`MoodBadge`** ignores the stated spec — iOS: *"tracked uppercase pills + dot color, not faces"* (`DesignSystem.swift:300-304`). Web renders sentence-case semibold, no dot, no mono, no tracking (`mood-badge.tsx:15-16`).
- **`.coach-note`** uses a **grey** border and **Crimson Pro** (`globals.css:103-110`) where the spec is coral-at-50% and PT Serif (`DesignSystem.swift:595-598`) — while the coral left-bar *does* appear elsewhere, where it shouldn't (`workout-drawer.tsx:350,453`).
- **`stat-card.tsx:18`** has a dead Tailwind class (runtime-interpolated arbitrary value never compiles), and `:30` colours numeric deltas with **mood hues**.
- **No `PlaceholderNote` guard on web.** `journal-view.tsx:515` renders `cleaned_notes || notes` straight through, so a synced *"Evening Run"* prints as the athlete's own words — the exact failure `PlaceholderNote.swift:1-30` was written to prevent.
- **Prediction on web is still on the superseded rule** — `types.ts:206-212` models `{low, high}` and `progression-band.tsx:29,46` renders a range and asserts *"Range, never a single time."* Hard rule #7 was revised to midpoint + tier + lifetime PR on 2026-07-18; iOS implements the revised rule (`RacePredictionViews.swift:256-261`).
- **Hard rule #8 (no em-dash placeholders)** is violated on both sides — **121** occurrences on iOS, **9** on web. iOS is far worse here.

### 🚩 One finding to escalate on its own
`/injuries` on web renders the **full prescriptive AI payload** —
`risk_level`, `likely_causes`, `recovery_timeline`, `immediate_actions`,
`short_term_actions`, `ongoing_actions` — as bulleted directives, with a
`HIGH/MODERATE` risk tag and day-count recovery estimates, and **no medical
disclaimer** (`injuries/page.tsx:158-273`).

iOS built the equivalent component and **deliberately never mounted it**
(`InjuryAnalysisComponents.swift:12` — definition only, zero call sites). The
live iOS surface instead prints: *"Mention dots, verbatim quotes, no
diagnoses. The classifier surfaces — it does not interpret."*
(`InjuryView.swift:111`), and iOS's models carry no `immediate_actions` field
at all. iOS also has a three-tier medical disclaimer
(`InjuryModels.swift:304-308`); the only "Not medical advice" string in
`web/src` is inside a design mock.

This is a live product-safety and hard-rule-#2 conflict. Fixing it is an
**S** — delete the block or gate it behind the same decision that unmounted
it on iOS.

---

## 5. Two data-layer bugs to fix before any UI work

**5.1 The web settings page queries a table that doesn't exist.**
`settings/page.tsx:17` reads `.from("user_profiles")`. That table was
deliberately not recreated; profile data lives on `athlete_settings`. The web
repo already knows this — `coach-portal/athletes/page.tsx:67` says *"there's
no user_profiles table on this DB"* and `from-supabase.ts:342` reads
`athlete_settings` correctly. So the settings page renders "Not set" for
every field, permanently, and a name typed on iOS can never appear there.

**5.2 Two different post-auth landings.**
`middleware.ts:60-62` sends an authenticated user to `/dashboard`;
`login/page.tsx:44` pushes to `/trends`; `auth-redirects.ts:25` sends
confirmed signups to `/trends`. `/dashboard` isn't in the sidebar nav at all.

---

## 6. Recommended sequence

Sized **S** ≤1 day · **M** 2–5 days · **L** >1 week. Ordered so each phase
makes the next cheaper.

### Phase 0 — Verify the baseline (do first, costs nothing)
The Aug 6 plan recorded production serving a **14 Apr** build with six
commits stranded, and Slice 0 was "redeploy from HEAD." **I audited source,
not what's live.** Every "web has X" claim here may not be what an athlete
sees. Confirm the deploy before treating any of this as the baseline.

### Phase 1 — Stop being wrong (all S, all independent)
These are correctness fixes, not features. Several actively misinform.

| Fix | Where | Why |
|---|---|---|
| Gate/remove the prescriptive injury analysis | `injuries/page.tsx:158-273` | hard rule #2 · product safety |
| Point settings at `athlete_settings` | `settings/page.tsx:17` | page is permanently blank today |
| Fetch by `workout_date`, not `created_at` | `trends/page.tsx:86`, `train/page.tsx:184` | silently drops real runs |
| Port `LogDedup` → `run-metrics.ts` | `lib/run-metrics.ts:22-38` | fixes double-counted mileage (feeds R1, R2) |
| Adopt `lib/workout-label.ts` everywhere; delete the 3 local copies | `train/page.tsx:73`, `train-calendar.tsx:34`, `move-day-sheet.tsx:60`, `from-supabase.ts:176` | "Long Wo", "Tempo" |
| Rebuild `QUALITY_TYPES`/`typeAccent` off `WorkoutLabel.offered` | `train/page.tsx:58-68,85-96` | `long_wo` never gets quality treatment |
| Fix the `7:60` pace formatter | `log/workout-detail.tsx:507-511` | |
| Add an error state + `error.tsx`/`not-found.tsx` | web app root | no boundary exists |
| Ship sign-out | anywhere | there is none |
| Fix the "Set a goal race" dead-end CTA | `train/page.tsx:484` | |
| Distinguish load-failure from empty in the journal | `journal-view.tsx:215-224` | today it tells the athlete their data is gone |
| Drop rest laps from web averages / include them in splits | `workout-enrichment.ts:83-95,219` | interval paces read slow |
| Fix `MoodBadge`, `.coach-note`, `stat-card` | see §4 | |
| Port `PlaceholderNote` guard | `journal-view.tsx:515` + 2 others | |

### Phase 2 — One source of truth for numbers (**the highest-leverage phase**)

**2a. Web calls `trends-timeline` instead of re-deriving.** *(M)*
The edge function is deployed, user-scoped, and already returns everything
iOS's Trends tab renders — weeks, days, per-day zone miles/minutes/load,
mood, niggles, `stress_load`, biometrics, `paceBands`, `fastSegments`,
`qualitySessions` (`Trends/TrendsService.swift:307-322`). This single change
closes R1, R2, R6 and most of the Trends read gap at once, and makes
everything after it cheaper. **Do this before building any new screen.**

**2b. Pick one ACWR and delete the other three.** *(S after 2a)*
Recommend the canonical intensity-weighted one (`athlete_state.acwr`). Also
resolve the iOS-internal #1-vs-#2 conflict.

**2c. Move the recovery-score ledger server-side.** *(L backend, then S web)*
It's ~1,000 lines of factor arithmetic living client-side on iOS
(`TrendsRecoveryFactors.swift` + `TrendsSignalModels.swift`). Porting it to
TypeScript duplicates it in two languages with nothing enforcing agreement —
i.e. it manufactures a new R1. Move it into `trends-timeline` and have iOS
read it instead. Higher upfront cost, permanently lower drift risk.

**2d. Extend the contract test.** *(S)*
`_shared/cross-language-pace-contract.test.ts` already proves the pattern —
Deno reading Swift/TS source as text and asserting on parsed literals. It
costs nothing to extend to the R1–R10 constants, and web currently has **zero
tests**. Also: either write the key-session fixture test `key-session.ts:6-7`
claims exists, or delete the claim.

**2e. Fix the heat fork + `DEW_HOT_F`.** *(S)*
Point `reconcile-log` at `pace-heat-adjustment.ts`; replace `DEW_HOT_F = 68`
with the real 55°F floor and correct the copy at `workout-enrichment.ts:151`.

**2f. Handle timezone on web.** *(S–M)*
Read `athlete_settings.timezone` — the value iOS already syncs on launch
(`RunningLogApp.swift`, `AthleteSettingsService.syncDeviceTimezone`).

### Phase 3 — Consolidate before extending *(M)*
Merge web's two workout-detail implementations into one, with shared
formatters and one palette. Extract the missing UI primitives (`Hairline`,
`StatTile`, `StatStrip`, `TextLink`, a responsive `Sheet`/`Drawer`). Centralise
the type and tracking scale. Everything in Phases 4–5 lands on top of this.

### Phase 4 — Give the athlete a write path
Ordered by value ÷ effort:

| Action | Size | Note |
|---|---|---|
| Mark complete / skip | **S** | simplest possible write |
| Journal search + kind chips | **S** | client-side over loaded rows |
| Per-row niggle chips | **S** | data is already fetched (`log/page.tsx:40-45`) |
| Athlete `title` | **S** | just add it to `LOG_COLUMNS` |
| Memo playback + transcript | **S each** | signed URL from the `training-memos` bucket |
| Convert to rest / add to rest day | **S–M** | |
| **Workout comparison** | **M** | ⭐ best value/effort on the list — `compare-workouts` is deployed, client-agnostic, already number-guarded server-side. This is a *client*, not a feature. |
| Key-session star + declare | **M** | rule already ported in `key-session.ts` |
| Recovery read (`athlete_state.load_distribution.recovery_read`) | **S** | straight read; cheapest high-value win after 2a |
| Swap two days | **M** | |
| Adjust goal + recompute-paces | **M** | `update-plan-goal` already exists |
| Goals CRUD | **M** | closes the dead-end CTA |
| Niggle add/resolve + `body_mentions` merge | **M** | `resolve-niggle` already exists |
| Units preference + a `DistanceFormat` port | **M** | touches every number |
| Structured workout step editor | **L**→**M** | `components/coach/workout-step-editor.tsx` already exists and could be re-skinned for the athlete — that materially lowers the cost |
| AI reschedule (preview → per-change approve → apply) | **L** | edge fn deployed; the approval UI is the work |

### Phase 5 — The three missing surfaces

| Surface | Size | Note |
|---|---|---|
| **Ask** | **M** | ⭐ The backend is fully deployed and app-release-independent. `analyzerCatalog()` means the chip rail is server-built. Three things to get right: call it **browser-side with the user session** (the `coach-workout-read` pattern, not the `api/coach` service-role pattern — `ask` resolves the athlete from the JWT with no body override); don't blanket-transform key case (the envelope is snake_case, the analyzer payload is camelCase, deliberately — `AskModels.swift:9-13`); render from `facts`, never from `narration`. **Blocker:** `ask-narration` is a golden family under hard rule #3 and has no entry in the eval-coverage script — add it before touching the prompt. |
| **Sheet** | **M** | `SessionRollup.swift` is ~324 lines of pure logic with no UI deps. A table with chips and search is arguably *easier* on web than iOS. |
| **Week** | **L** | Depends on 2a (it's literally a second reader of the same payload — `WeekService.swift:14-18`) and on pace bands. `WeekBuilder` is a pure function; the port is mechanical but ~660 lines. The provenance-sheet pattern is the expensive part. |
| Signal Lab | **L** | Backend detectors mostly exist (`trends-insights/detectorsA-C.ts`); the client is the work. |
| Route map | **L** | Data is in `external_streams`; web reads it nowhere. |
| Onboarding | **L** | No web route at all today. |
| Content Library | **L** | `content_library` → 0 hits in `web/src`. |

### Explicitly *not* web gaps
- **HRV / sleep / overnight** — blocked upstream. `vital-webhook` has no daily-sleep branch; `daily_biometrics` is unwritten (`WeekService.swift:458-462`). iOS renders an honest `.notCaptured` note. Web should do the same, not estimate.
- **Coach portal** — deliberately web-only and genuinely deeper than iOS (~10,700 LOC vs ~2,700). The one real gap is that **web can mint join codes it cannot spend** — code redemption is athlete-side and iOS-only.

---

## 7. What the Aug 6 plan got wrong

Worth recording, because the same failure mode will recur:

| Aug 6 claim | Status today |
|---|---|
| "3 tabs — Log · Trends · Train" | **Stale.** Six tabs since 2026-08-19 (Week and Ask added). |
| Slice 1: no athlete workout-detail route | **Shipped.** `app/(app)/workouts/[logId]/page.tsx` exists. |
| Decision #3: "Voice capture on web — yes, full parity" | **Reversed without a record.** `log-front-door.tsx:1-3` is a removal tombstone. |
| Train gaps rated "Small / Medium" | **Optimistic.** 24 athlete write actions vs 1. |
| Slice 0: redeploy from HEAD | **Unknown.** Still unverified — see Phase 0. |

Also stale in `CLAUDE.md`: the Trends file mapping (§4) and the claim that
the Week tab is fixture-driven (§4).

---

## 8. Dead code — read before scoping

Grepping for a view name finds the file and tells you nothing about whether
it renders. These are in the repo but **unreachable from the shipping IA**:

**iOS:** `LogView`, `ManualWorkoutView`, `HistoryView`, `WorkoutAnalysisView`,
`WorkoutAnalystView`, `UnifiedTelemetryCard`, `VitalWorkoutCards`,
`VitalWorkoutCharts`, `ReconciliationCard`, `TrendsV2View`, `TrendsReadView`,
`InstrumentsTabView` (+ `KeyPaceCard`/`KeyPaceChart`), `EfficiencyIndexCard`,
`ThresholdCheckSection`, `TrendsQualityLoad`, `TrendsRecoveryDemand`,
`CompareMetrics`, `TrainingAnalysisView`, `InjuryView`, `InjuryPlate28`,
`InjuryAnalysisSection`, `ModelOfYouView`, `TrainingTabTwoView`,
`AdaptivePlanBuilderSheet`, `PlanTemplateBuilderView`,
`WorkoutTemplateLibraryView`, `MonthCalendarView`, `WeekCalendarView`,
`GoalAndPacesCard`, `BlockTotalsStrip`, `TrainingTodayHero`,
`TrainingHeader`, `CoachPlanWeekStrip`, `CoachNoteSection`, `CoachReadCard`,
`WeekBlockSegmenter`, `WeekTrainingLoadSection`.

Also dead *inside* the live `TrainingTabView.swift`: `volumeByIntensity`
(`:406`), `weekVolumeSection` (`:415`), `monthVolumeSection` (`:441`),
`blockVolumeSection` (`:490`), `easyPaceTrendSection` (`:478`), `mileageByDay`
(`:528`). So the Easy-Pace trend chart, the rolling-4-week-average line and
the block stat strip **do not render anywhere today** — don't scope web work
to match them.

**Web:** `training-list.tsx` (`TrainingLogList` — zero importers),
`app/api/assign-plan/route.ts` (no caller), the entire Sanity/`/studio` stack
(no page imports `sanityClient` or `PortableTextRenderer`; the blog reads
Supabase and renders raw HTML via DOMPurify), `train/loading.tsx` (skeleton
for the old `/plan` page).

**Ghost calls in shipped iOS code:** `Workouts/WorkoutGeneratorViewModel.swift:197`
→ `workout-generator` and `Analysis/AnalysisModels.swift:230` →
`training-analysis`. **Neither edge function exists.** Both are reachable
from UI, so both 404 at runtime. `training-analysis` additionally sends the
**anon key** as bearer with `userId` in the body
(`AnalysisModels.swift:226,241`) — a tenant-authorization hole waiting for
someone to recreate the function.

---

## 9. What could not be verified

1. **Deploy state.** Static source only. Whether production serves HEAD is unknown, so every "web has X" claim may not match what an athlete sees.
2. **Runtime / DB state.** No migrations in the tree, so every RLS claim is inferred from query shape and code comments. Notably, web athlete queries carry **no `.eq("user_id")`** at all (`trends/page.tsx:81-108`, `pace-chart/page.tsx:12-27`) — correct *if and only if* RLS is athlete-scoped, and fragile either way, since `.limit(1).maybeSingle()` on an unfiltered table returns *some* row rather than erroring. iOS is explicit.
3. **Whether `athlete_state.acwr` is populated in prod.** iOS silently falls back to a miles ratio when it's null — that fallback may never fire, or always.
4. **`pace_segments` coverage.** The source changed to watch laps on 2026-08-20; per-lap coverage on older rows may be thin, which affects sizing for the pace-spectrum work.
5. **Which pace ratio table is authoritative** — `CLAUDE.md`'s `MP/0.765`/`MP/0.925` vs `workout-helpers.ts:779-785`'s `0.75`/`0.95`. Needs a human call.
6. **Whether the web voice-capture removal was sanctioned.** No decision record exists.
7. **Which audio formats `process-training-memo` accepts.** Browsers produce webm/opus; the pipeline expects m4a. This directly gates the effort estimate for web capture.
8. **`design-system/` and `docs/`** were outside the audit tree, so every claim about "the spec" is sourced from doc-comments inside the two codebases that quote it. If the canonical CSS disagrees, the CSS wins.

---

## Appendix — full gap tables

### A. LOG

| Capability | iOS | Web | Verdict |
|---|---|---|---|
| Voice recording | `VoiceLogView.swift:885-953` | none | **MISSING** |
| Record-confirm / discard sheet | `:1545` | — | **MISSING** |
| Check-in mode | `:272-288` | display only | **MISSING** |
| Free-text note capture | `:435-502` | edit-existing only | **MISSING** |
| Link memo to a run | HealthKit picker `:1290` | none | **MISSING** (partly platform) |
| Offline queue | `VoiceLogViewModel.swift:206-215` | — | **MISSING** |
| Attach-vs-insert dedup | `VoiceLogViewModel.swift:102-125` | — | **MISSING** |
| Memo playback | `MemoPlayerRow` | zero `<audio>` | **MISSING** |
| Verbatim transcript | `+Editorial.swift:675-696` | none | **MISSING** |
| Week-grouped journal | ✅ | ✅ | **MATCH** |
| Journal search | `:549-616` | none | **MISSING** |
| Kind filter chips | `:569-577` | none | **MISSING** |
| Per-row niggle chips | `JournalLogRow.swift:217-229` | rail summary only | **PARTIAL** |
| Key-session star | `JournalLogRow.swift:170-175` | coach-side only | **MISSING** |
| Athlete `title` | read + edit | never selected | **MISSING** |
| Load-failed ≠ empty | `:633-651` | no error branch | **MISSING** |
| Realtime feed | none | `journal-view.tsx:125-176` | **WEB-ONLY** |
| Stats rail | scattered | `:268-444` | **WEB-ONLY** |
| Detail pager | `HistoryDetailPager.swift` | single route | **MISSING** |
| Three-act detail | ✅ | ✅ | **PARTIAL** |
| THE WORKOUT (stated intent) editor | canonical + row mirroring | read-only, absent from detail route | **PARTIAL** |
| SIGNALS chips | `WorkoutRepReceiptView.swift:652-682` | none | **MISSING** |
| Splits incl. recoveries | every lap `:828-896` | rest laps dropped `workout-enrichment.ts:219` | **PARTIAL** |
| Rep-structure editor | `:913-921` | none | **MISSING** |
| HEAT-ADJ toggle | `:1096` | static column | **PARTIAL** |
| MI/KM toggle | `:1107-1127` | miles hardcoded | **MISSING** |
| HR zones / cadence / elevation charts | full | prose sentences on the detail route | **PARTIAL** |
| Per-rep HR recovery | `RRRecoveryRow` | none | **MISSING** |
| HR drift | `RRHRDrift` | none | **MISSING** |
| Route map | full, w/ scrub | none | **MISSING** |
| Scrubbable telemetry | `RRTelemetryPanel` | static hover | **PARTIAL** |
| Workout comparison | `WorkoutComparisonSheet` | none | **MISSING** ⭐ |
| On-demand AI read | 3 states | display-if-present | **PARTIAL** |
| Session rollup (Sheet) | `SessionRollup.swift` | none | **MISSING** |

### B. TRENDS / WEEK / SHEET

| Capability | iOS | Web | Verdict |
|---|---|---|---|
| Single range segmenter | 4/12/26 wk | per-section hardcoded windows | **MISSING** |
| Weekly volume chart | bars + quality cap + 4-wk avg | area, 6 wk, neither | **PARTIAL** |
| This wk / 4-wk avg / Peak tiles | + mid-week projection | miles + runs only | **PARTIAL** |
| ACWR | intensity-weighted + band bar | miles ratio + text | **PARTIAL** (different metric) |
| Pace-spectrum histogram | 18 fitted buckets | none | **MISSING** |
| Volume by pace zone | per-lap | per-run average | **PARTIAL** (wrong) |
| Threshold / pace bands | row + drill-down | 0 hits | **MISSING** |
| Key-session receipt ledger | structure, zone, rep pace | flat rows | **PARTIAL** |
| Head-to-head compare | `HeadToHeadCard` | none | **MISSING** |
| Recovery score ledger | 0–96 + factor receipt | 0 hits | **MISSING** |
| Recovery read | `TrendsDetailViews.swift:1038-1145` | none | **MISSING** ⭐ cheap |
| Mood | 14d, quotes, 6 lanes, stepper | 4wk colour heatmap | **PARTIAL** |
| Niggles | day chips + week watch-line | grouped 30d + quotes | **MATCH (near)** |
| Race prediction | midpoint + tier + sparkline | none on `/trends` | **MISSING** |
| HRV / RHR / sleep | in the ledger | 0 hits | **BLOCKED UPSTREAM** |
| Stress / zone load / density | on every `TrendsDay` | 0 hits | **MISSING** |
| Signal Lab | sheet | none | **MISSING** |
| Ask | own tab | 0 hits | **MISSING** |
| Week surface | full | no route | **MISSING** |
| Sheet surface | full | no route | **MISSING** |
| Goals / upcoming strip | not on Trends | ✅ | **WEB-ONLY** |
| Injury timeline | built, unmounted | shipped | **WEB-ONLY** |

### C. TRAIN

| Capability | iOS | Web | Verdict |
|---|---|---|---|
| 3-mode segmenter | ✅ | ✅ | **MATCH** |
| WEEK/MONTH/BLOCK scope | `:356-377` | none | **MISSING** |
| Week summary strip + projection | `:248-296` | target miles only | **MISSING** |
| 30-day ledger | `:301-311` | longest run only | **PARTIAL** |
| Today card — planned | `:782-806` | `TodayBand` | **MATCH** |
| Today card — completed run | `:1119-1156` | none | **MISSING** |
| Weather forecast | `:808-813` | 0 hits | **MISSING** |
| Per-run conditions | `:962-971` | none | **MISSING** |
| Mood badge on day rows | `:960,:990` | none | **MISSING** |
| Voice-memo-only rows | `:975-988` | none | **MISSING** |
| Week paging | `:835-880` | current week only | **MISSING** |
| Week training-load strip | `WeekStressStripSection` | 0 hits | **MISSING** |
| Month calendar | full | grid + dots | **PARTIAL** |
| Calendar day tap → detail | `DayAnalysisSheet` | `title` tooltip | **MISSING** |
| Key-session star | full | coach-only | **MISSING** |
| Plan block + door to full plan | `:1014-1068` | none | **MISSING** |
| Goals & Targets block | `:658-720` | none | **MISSING** |
| Session-receipts ledger | `WorkoutsAndRepsSection` | none | **MISSING** |
| Easy/Hard 80/20 bar | `:562-592` | none | **MISSING** |
| Volume × Pace | 18-bin + fitness markers | 12-zone bars | **PARTIAL** |
| Chart expand → drill-in | `VolumeDetailSheet` | none | **MISSING** |
| 26-week volume chart | not rendered | `MileageChart` | **WEB-ONLY** |
| Miles/Km | `@AppStorage` | hardcoded | **MISSING** |
| Athlete write actions | **24** | **1** | **MISSING** |
| Coach plan builder / block rewrite | — | full | **WEB-ONLY** |

### D. Account & misc

| Capability | iOS | Web | Verdict |
|---|---|---|---|
| Email/password sign-in | ✅ | ✅ | **MATCH** |
| Sign in with Apple | `AuthManager.swift:192` | none | **MISSING** |
| Password reset | **none** | full, both flows | **MISSING ON iOS** |
| Sign out | ✅ | **0 hits** | **MISSING** |
| Delete account | `delete-account` | none | **MISSING** |
| Onboarding | 4 steps | no route | **MISSING** |
| Avatar upload | ✅ | coach reads, never writes | **MISSING** |
| Profile edit (self) | `athlete_settings` | "use the iOS app" | **MISSING** |
| Units / max HR / timezone / toggles | 6 settings | read-only rows | **MISSING** |
| Privacy policy link | → `postrundrip.com/privacy` | **404s** (no public route) | **MISSING** |
| Goals CRUD | full | read-only + dead-end CTA | **MISSING** |
| CSV / FIT export | both | none | **MISSING** |
| Backup / restore | 6 tables, paginated | none | **MISSING** |
| Content Library (video) | 5 categories + offline | 0 hits | **MISSING** |
| Niggle add / resolve | ✅ | read-only | **MISSING** |
| Medical disclaimer | 3 tiers | **none, and prescriptive** | **🚩 ESCALATE** |
| Blog / marketing / Sanity | — | ✅ (Sanity orphaned) | **WEB-ONLY** |
| Coach roster / dashboard / builder | thin | deep | **WEB-ONLY** |
| Join code — generate | — | ✅ | **WEB-ONLY** |
| Join code — redeem | ✅ | none | **MISSING** |

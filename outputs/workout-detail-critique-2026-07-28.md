# Workout Detail — Critique & Redesign Spec

**Surface:** `HistoryDetailSheet` (iOS) and the log it should absorb
**Date:** 2026-07-28
**Verified against:** the working tree at `~/my-running-app/RunningLog`. Every claim below is quoted from source with a file:line. Nothing here is inferred from screenshots.

---

## The one-sentence diagnosis

Your workout detail screen isn't inconsistent because nobody had taste — it's inconsistent because **three separate rewrites landed on top of each other and none of them deleted the previous one.** You're not looking at a design problem. You're looking at three designs running at the same time.

Once you see that, everything else on the list stops being mysterious.

---

## Overall impression

The editorial layout that *does* ship is good. It's restrained, it's typographic, it reads like the design system intended. The problem is that it's wearing the corpse of the old card-based screen: the moment you tap **Edit**, the screen switches visual languages mid-session — hairlines and mono eyebrows become white cards with SF Symbols and rounded corners. That single toggle is the most visible symptom of the whole disease.

The biggest opportunity is not redesigning anything. It's **deleting** — about 1,900 lines of dead and duplicate code sit inside this surface. Removing them makes the "simplify it" goal mostly self-executing.

One thing to know before you touch anything: `HistoryDetailSheet` is presented from **seven** places, not two.

```
Workouts/VoiceLogView.swift:225        Training/TrainingPlanView.swift:220
Workouts/HistoryView.swift:99          Trends/TrendsTabView.swift:112
Trends/ThresholdWorkView.swift:107     Trends/ThresholdWorkView.swift:460
Trends/CompareDashboardView.swift:79
```

This screen is already the app's universal "one run, in full" surface. That's an asset — it means the merge you want is smaller than it looks. It's also a constraint: any change here ripples to five other tabs.

---

## Root cause: three layouts, one screen

| Generation | Lives in | Status |
|---|---|---|
| **Card-based** (SF Symbols, white cards, `cornerRadius(16)`, coral CTAs) | `HistoryDetailSections.swift` | **Dead except in Edit mode.** `CoachInsightSection` (300 LOC) and `WorkoutNotesSection` (113 LOC) have zero call sites repo-wide. But `EditableWorkoutTypeSection` and `EditableWorkoutStatsSection` from the same file *were* bolted into the editorial body — that's the visual whiplash. |
| **Editorial** (hairlines, mono eyebrows, no icons) | `HistoryDetailSheet+Editorial.swift` | **This is what ships.** `HistoryDetailSheet.body:67` calls `editorialBody` unconditionally. No feature flag, no A/B — the old body was deleted, not switched off. |
| **Drip charts** (five stacked panels) | `DripWorkoutPrimitives.swift`, 913 LOC, 14 types | **Fully dead.** Superseded by `UnifiedTelemetryCard`, whose own header says so (`:7-8`). Every type in the file has exactly 2 repo-wide references: its declaration and its own header comment. |

The file comment at `HistoryDetailSheet+Editorial.swift:104-109` admits the bolt-on in writing: those two edit sections *"existed but were never wired into the editorial port."* Someone wired them in as a patch. It was never designed.

---

## Usability findings

| Finding | Severity | Recommendation |
|---|---|---|
| **Edit mode changes visual language.** Read mode = hairlines + mono eyebrows + zero icons. Edit mode injects `.padding(16)` + `cornerRadius(16)` white cards with `figure.run.circle.fill` headers (`HistoryDetailSections.swift:503, 552`). Same screen, two design systems, one tap apart. | 🔴 Critical | Rebuild both edit sections with `editorialSection(eyebrow:)`. Fields become hairline-separated rows, labels become mono eyebrows. |
| **The edit picker writes retired data.** `EditableWorkoutTypeSection.workoutTypes` (`HistoryDetailSections.swift:491-497`) hardcodes `easy / tempo / interval / long_run / recovery / race` and persists those keys to `workout_type`. Your declared source of truth, `WorkoutLabel.swift`, marks `tempo` and `interval` as *"legacy … not offered for new entries"* and offers a 10-zone taxonomy (`moderate, steady, mp, hmp, lt, 10k, 5k, 3k, mile`) the picker doesn't expose. **Every edit through this screen degrades your data.** | 🔴 Critical | Drive the picker from `WorkoutLabel`. It's already called from 8 other places (`TodayHomeView`, `LogView`, `JournalLogRow`, `ManualWorkoutView`, `TrainingDayExpanded`, `WorkoutRepReceiptView`…) — the detail sheet is the one holdout. |
| **Clearing a field silently loses the edit.** `saveEdits` writes `.null` to Postgres but rebuilds the local model with the *old* value (`HistoryDetailViewModel.swift:193, 196, 197`). Clear the distance → DB says NULL, UI still shows 6.2 mi until relaunch. Affects `cleaned_notes`, `workout_distance_miles`, `workout_duration_minutes`. Title and mood are handled correctly — 3 of 5 fields are wrong. | 🔴 Critical | Mirror the null writes in the local rebuild. |
| **A dead-end tappable row.** `linkedSourceRow` renders "VIEW DETAIL ↗" but the tap is a no-op when `vm.matchedVitalWorkout == nil` (`+Editorial.swift:344`). It also renders in edit mode, unlike every sibling section (`:133` has no `!isEditing` guard). | 🟡 Moderate | Gate the affordance on the same condition as the action. Add `!isEditing`. |
| **A section vanishes for a whole class of entries.** Read-mode VOICE SUMMARY gates on `cleanedNotes` only (`:153`), but `enterEditMode()` falls back to `notes` (`HistoryDetailSheet.swift:235`). An entry with raw notes and no AI rewrite shows *no summary at all* in read mode, then text appears when you tap Edit. | 🟡 Moderate | Read mode should use the same `cleanedNotes ?? notes` fallback. |
| **Crash on partial HR data.** `DripMileSparklines.slice` clamps `end` but not `start` (`DripWorkoutPrimitives.swift:661-666`). With 3 HR samples and 8 splits, `idx = 5` produces `hrSamples[5..<3]` → fatal error. | 🟡 Moderate | Moot if you delete the file (recommended). Otherwise clamp `start`. |
| **Two `HealthKitManager` instances.** `HistoryDetailSheet.swift:18` is `@StateObject var healthKitManager = HealthKitManager()` — a fresh instance that re-requests authorization on every appear. `VoiceLogView.swift:35-37` documents that this exact bug was already found and fixed there. | 🟡 Moderate | `HealthKitManager.shared`. One-line fix. |
| **A redundant affordance.** "VIEW DETAIL ↗" opens full-screen the same content the WORKOUT section already renders inline, gated on the same id. | 🟢 Minor | Drop it, or keep only when the inline section is collapsed. |

---

## Consistency findings

### The formatter problem — 19 pace/duration implementations, two rounding regimes

`PaceCalculator.swift` is the canonical formatter. It rounds. Then:

- `DripWorkoutPrimitives.swift:271` **truncates** (`Int(sec) / 60`). 419.7s → `6:59`; PaceCalculator → `7:00`.
- `:565` is a byte-identical copy of `:271` — same file, twice.
- `UnifiedTelemetryCard.swift:639` (`TelemetryMath.clock`) rounds but **has no hours branch** — a 78-minute run scrubs as `78:03`, not `1:18:03`.
- `HistoryDetailViewModel.swift:422` (`formatMinutesForEdit`) **truncates** — and this feeds the *edit field*, so an Edit → Save round-trip silently drops up to a second.
- `PaceCalculator.formatSeconds` (`:275`) is an exact behavioral duplicate of `formatTime` (`:206`).

The km constant disagrees with itself *inside one file*: `PaceCalculator.swift:16-17` declares the exact `1609.344` / `1.609344`, then ignores it at `:179` and `:187` in favor of `1.60934`. `UnifiedTelemetryCard.swift:556` declares a third value, `1609.34`. Chart distances and stat-strip distances derive from different mile lengths.

`DistanceFormat` in `DesignSystem.swift:45-57` is declared as the single source of truth for distance and pace strings. **It has zero call sites.** Every surface hardcodes `mi`. Kilometer support is currently fictional.

### Two primitive families, both alive

Your design system ships `PlateStrip` / `PlateFooter` / `CoachQuote` / `Hairline` / `EditorialRule` in `DesignSystem.swift:508-624`, with a charter comment saying every editorial surface should compose them. A second family — `DripPlateStrip`, `DripHairline`, `DripEyebrow`, `DripStatStrip` — lives in `App/DripEditorialPrimitives.swift`.

Both are in real use, and the split runs along file lines, not design lines:

- `PlateStrip` / `EditorialRule` → `TrainingAnalysisView`, `InjuryView`, `TodayHomeView`, `FitnessPredictorView_Rebrand`
- `DripPlateStrip` / `DripHairline` → `HistoryDetailSheet+Editorial`, `FitnessPredictorView`

Their APIs aren't compatible (`PlateStrip(surface:fig:)` vs `DripPlateStrip(leadingBottom:trailingTop:trailingBottom:)`), so this isn't a rename — it's a decision you have to make once and then enforce.

### The wrong caption token wins 5:1

`Font.dripCaption` carries a doc comment saying *"this is NOT the canonical caption per the design system spec — see `dripEyebrow`."* It's PT Serif; eyebrows are supposed to be mono. Across `Workouts/`: **94 `dripCaption(` vs 20 `dripEyebrow(`.**

Eyebrows — one semantic element — are currently built four different ways, with tracking values of `0.5, 0.6, 0.8, 1.0, 1.1, 1.2, 1.3, 1.4` against a spec that defines exactly three.

`UnifiedTelemetryCard.swift` is the worst single file: eight `.font(.system(size: 8.5 …))` hand-rolls of `dripEyebrow`, at half-point sizes that appear nowhere in your scale. And at `:447`:

```swift
.background(Color(red: 26/255, green: 24/255, blue: 21/255).opacity(0.94))
```

`26/24/21` is `#1A1815` — that's `Color.drip.textPrimary`, written out in raw RGB so nobody would recognize it.

### Card chrome hand-rolled eight times

`.padding(16) + cornerRadius(16) + stroke` appears at eight sites with four different value combinations (padding 14/16/20, radius 9/12/14/16), while `StatCard` — an actual shared card primitive — sits unused in `DesignSystem.swift:233`.

### Empty states: seven conventions, and your own rule broken

Your hard rule #8 says *"No em-dashes as empty-state placeholders."* Currently: `"—"` at `UnifiedTelemetryCard:646, 651, 656, 661` and `ReconciliationCard:178`; `"--"` (double hyphen — a different convention for the same "no HR" case) at `VitalWorkoutCards:163`; `EmptyView()` at `ReconciliationCard:80`; a silent `nil` return at `+Editorial.swift:336`; three bespoke inline states in the transcript loader; a hand-rolled 48pt-symbol `VStack` at `HistoryDetailSheet:253`; and exactly one correct `EmptyStateView` at `:495`.

---

## Copy findings — this is where "wordy" lives

### The screen can't decide what the thing on it is called

Scrolling top to bottom, the same object is named six ways:

> **ENTRY** ("JOURNAL · ENTRY DETAIL") → **WORKOUT** ("WORKOUT", "WORKOUT NOTES") → **SESSION** ("VS. YOUR LAST SIMILAR SESSION") → **RUN** ("LINK A RUN →", "How did the run feel?") → **LOG** ("DELETE LOG", "— Logged …") → **EFFORT** ("THE EFFORT")

Pick one noun. Everything else follows from that.

### Same action, two casings, visible simultaneously

`"EDIT"` (`+Editorial.swift:162`) and `"Edit"` (`HistoryDetailSheet.swift:80`) are on screen at the same time. Same for `"SAVE"` / `"Save"`. The split isn't semantic — it's which file drew the button.

### "WORKOUT" heads four of the screen's sections

`WORKOUT`, `WORKOUT NOTES`, `WORKOUT TYPE`, `WORKOUT STATS` — the word carries zero distinguishing information in any of them, on a screen already titled "ENTRY DETAIL."

### Five spellings of one unit

`"mi"` as a separate unit slot · `"%.2f mi"` (space) · `"\(m)mi"` (no space) · `"(mi)"` (parenthesized field label) · `"/mi"` vs `" /mi"` vs `"/mi avg"`.

### The wordiness list

| Current | Where | Proposed |
|---|---|---|
| "Record splits, interval times, pace notes, or any workout details" | `HDSec:412` | **Delete.** The placeholder above it already says this. |
| "This will permanently delete this training log entry. This action cannot be undone." | `HDS:147` | "This can't be undone." |
| "Complete a run with your Apple Watch or running app to see it here." | `HDS:261` | "Runs from Apple Watch appear here." |
| "SESSION AVERAGES · PRESS & DRAG FOR LIVE VALUES" | `UTC` body | "DRAG FOR LIVE VALUES" |
| "PRESS & DRAG TO SCRUB · TAP CLOSE TO RETURN" | `UTC:542` | "DRAG TO SCRUB" — CLOSE is a labelled button 40pt above |
| "VS. YOUR LAST SIMILAR SESSION" | `+Ed:213` | "VS. LAST SIMILAR" — the row already says COMPARE |
| "Show full transcript ↓" / "Show less ↑" | `+Ed:471` | "More ↓" / "Less ↑" |
| "Distance (mi)" / "Duration (m:ss)" | `HDSec:563, 577` | "DIST" / "TIME" — match read mode; the format hint is already the placeholder |
| "Pace: 7:29 /mi" | `HDSec:598` | "7:29/mi" |
| "Weather-adjusted — you crushed it despite the heat." | `RC:172` | "Beat the heat-adjusted target." — "you crushed it" is outside your Coach voice |
| "Couldn't get coach feedback: \(error.localizedDescription)" | `HDVM:601` | One message for all five network branches. `"Error: Invalid URL configuration"` (`HDVM:525`) currently ships an internal fault to the athlete verbatim. |

Also: `"Getting coach feedback..."` uses ASCII dots while `"SAVING…"` uses a true ellipsis. Trailing periods are on `"Transcript is empty."` but not `"No recent runs found"` — same element type.

---

## The merge: "the log should live with the workout details"

This is the most important finding in the document, so read it slowly.

### It's already half-done — in the opposite direction

`HistoryDetailSheet` **is** the journal entry detail. The `WORKOUT` section (`+Editorial.swift:197-201`) already embeds the full workout analytics *inside* the journal entry. There's no separate "workout detail" and "log entry" — there's one row in one table.

### There is no `workouts` table

Runs and journal entries are **rows in the same `training_logs` table**, distinguished only by a `source` column (`voice_log` / `check_in` / `manual` / `garmin` / `vital`). That's the good news: half the merge is already architecture.

### But the link between a note and a run is a fuzzy date match, not an ID

This is the crux. When you link a workout, the code writes:

```swift
// HistoryDetailViewModel.swift:57-61
"workout_date":            .string(ISO8601…),
"workout_distance_miles":  .double(workout.distanceMiles),
"workout_duration_minutes":.double(workout.durationMinutes),
```

`RunningWorkout.id` — the HealthKit UUID — is **thrown away**. At read time the run is re-found by a ranked heuristic (`matchVitalWorkout`, `:322-361`) that falls back from time proximity to distance proximity, with a comment above it explicitly documenting mislinks on multi-run days.

The only real ID anywhere is `vital_workout_id`, and it exists only for Vital/Garmin. HealthKit runs have no ID stored at all.

**Everything downstream of that is compensation.** Fuzzy dedup runs in at least four places: `WorkoutPickerSheet.refreshWorkouts` (±300s start, ±2min duration), `dedupedMiles` (same-day ±0.3 mi), `WorkoutSyncService.removeAutoSyncEntry(forWorkoutDate:distance:)`, plus server-side dedup that deletes rows out from under the client's polling loop. **Add a real foreign key and all four can be deleted.** That is the single highest-leverage change in this entire document.

### What breaks if you just move the recorder into the sheet

1. **The polling loop dies.** `VoiceLogViewModel`'s three polls are `Task { [weak self] }` on a view-scoped observable. Dismiss the sheet mid-upload and the 60-second processing poll is silently cancelled.
2. **Sheet-on-sheet-on-sheet.** `RecordingConfirmationSheet` is `.interactiveDismissDisabled()` and itself presents `WorkoutPickerSheet`. Adding a third presentation level under a detail sheet is fragile on iOS.
3. **`HistoryDetailSheet` takes an immutable snapshot** (`let entry: TrainingLog`, seeded once in `init`). It has no `loadHistory()` — refresh is delegated upward via `onUpdate`. A recorder inside it would author a row the sheet can't see.
4. **The audio session** is configured in `VoiceLogView.onAppear` and never deactivated on the success path. Sheet dismissal mid-recording has no handler at all.
5. **The success overlay** is a full-screen overlay on the tab. Inside a `.medium` detent it has nowhere to render.

### And this is the thing that would actually break for users

**Check-ins and rest-day notes have no other home.** `workoutDate` is optional and used as a real branch everywhere — `JournalEntryRow` literally renders `"Rest Day"` when there's no linked workout (`HistoryView.swift:252`). The entire CHECK IN mode writes `source: "check_in"` with no workout fields. The feed query deliberately includes them.

If the Log tab goes away, **there is no way to author a note about a day you didn't run.** For a product whose stated principle is that `activePlan == nil` is a first-class state, losing `workoutDate == nil` would be a real regression.

### So: what "log lives with workout details" should mean

**Not** "delete the Log tab." It should mean:

> Authoring moves *to* the run. The Log tab stops being the only place you can write, and becomes the place you read the arc and write about days that aren't runs.

Concretely: a run-linked note is authored **from the run's own detail screen**, pre-bound, no picker, no matching. The Log tab keeps the check-in path and the unlinked-note path. Later, a rest-day cell in Train's CALENDAR mode opens the same composer with `workoutDate = tapped day, no run attached` — and *then* the Log tab can become read-only.

---

## Proposed screen: one run, one entry

Read mode, top to bottom. Nine sections becomes six. Every section uses `editorialSection(eyebrow:)` — no exceptions, no cards, in either mode.

```
┌─────────────────────────────────────────┐
│ RUN · DETAIL              JUL 24 · 06:12│  plate strip
├─────────────────────────────────────────┤
│                                          │
│  Thursday                                │  title (or custom)
│  STEADY                        ○ TIRED   │  type · mood — one row
│                                          │
│  8.42        1:02:16       7:24          │  stat strip, no card
│  MI          TIME          /MI           │
│  ─────────────────────────────────────   │
│  APPLE WATCH                    LINKED   │  source, right-aligned, no CTA
│                                          │
│  ── NOTE ──────────────────────── EDIT   │
│  Legs felt heavy for the first three     │  cleanedNotes ?? notes
│  miles, then settled. Held the last…     │
│  ▸ Transcript                            │  disclosure, collapsed by default
│                                          │
│  ── EFFORT ───────────────────── EXPAND  │
│  [ UnifiedTelemetryCard ]                │  the only chart
│                                          │
│  ── READ ─────────────────────────────   │
│  You've now put three steady efforts in  │  coachInsight, italic
│  ten days at a pace you were racing in…  │
│                                          │
│  ── COMPARE ──────────── LAST SIMILAR ↗  │
│                                          │
│  ⏺  Add to this entry                    │  ← THE MERGE: composer, pre-bound
│                                          │
│  Logged Jul 24                    DELETE │
└─────────────────────────────────────────┘
```

### What changed and why

| Change | Rationale |
|---|---|
| **9 sections → 6.** VOICE SUMMARY + TRANSCRIPT collapse to **NOTE** with a disclosure. WORKOUT + VS-SIMILAR collapse to **EFFORT** + a COMPARE link. LINKED becomes a right-aligned label, not a section. | Transcript is verification, not content — it earns a disclosure, not a header. |
| **"WORKOUT" disappears as a word.** Sections become NOTE / EFFORT / READ / COMPARE. | It headed four sections and distinguished none of them. |
| **Type and mood share one row** with the title. | They're both "what kind of day was this" — one glance, not two. |
| **Edit mode uses the same sections.** No cards, ever. Fields are hairline rows; labels are the same mono eyebrows. | Kills the visual whiplash. Also deletes `EditableWorkoutStatsSection`'s entire chrome. |
| **The composer sits inline, above the footer,** pre-bound to this run. Tap → record or type. No picker, no matching. | This *is* the merge. Authoring happens where the run is. |
| **One chart.** `UnifiedTelemetryCard` only. | `DripWorkoutPrimitives.swift` is 913 dead lines pretending otherwise. |
| **Every empty cell uses `EmptyStateView`.** Zero em-dashes. | Your rule #8, currently broken 7 times. |

### Copy rules for this screen

- **The noun is "run."** "Entry" only for workout-less days. Never "session," never "workout," never "log" as a noun.
- **Section eyebrows: one word.** NOTE, EFFORT, READ, COMPARE.
- **Buttons: ALL CAPS mono, always.** EDIT, SAVE, DELETE, EXPAND — including the toolbar. No Title Case anywhere.
- **Units are a separate slot,** never concatenated: `8.42` + `MI`, not `8.42mi`.
- **No trailing periods on labels or empty states.** Full sentences (AI Read, verdicts) keep them.
- **True ellipsis `…` only.**

---

## Priority recommendations

### 1. Delete before you design — ~1,900 lines

Nothing on this list changes behavior. Do it first so every later change happens once instead of twice.

| Delete | Lines | Verified zero call sites |
|---|---|---|
| `DripWorkoutPrimitives.swift` (whole file) | 913 | ✅ all 14 types, repo-wide |
| `CoachInsightSection` (`HistoryDetailSections.swift:15-315`) | 300 | ✅ — includes a duplicate HTTP client and a `Log.coach.debug` that prints athlete notes and mood to the device console |
| `HistoryDetailViewModel.callCoachingAgent` + `isQualityWorkout` + `saveCoachInsight` + `generateCoachInsight` | ~130 | ✅ 21% of the ViewModel can't execute |
| `WorkoutNotesSection` (`:319-432`) | 113 | ✅ |
| `HistoryView.swift` (+ `JournalEntryRow`, `JournalMonthHeader`, `JournalDivider`) | ~400 | ✅ only self-referenced and its own `#Preview` |
| `WorkoutStatItem`, `GlowingOrb`, `Color.drip.electric` shim, dead `@State` (`selectedWorkout`, `isEditingWorkoutNotes`, `isDeleting`) | ~40 | ✅ |

### 2. Fix the three data bugs — one afternoon

- `saveEdits` local rebuild must mirror the `.null` writes (`HistoryDetailViewModel.swift:193, 196, 197`)
- `EditableWorkoutTypeSection` must source from `WorkoutLabel` — it's writing retired keys today
- `HistoryDetailSheet.swift:18` → `HealthKitManager.shared`

### 3. One formatter, one primitive family, one caption token

- Route all 19 pace/duration sites through `PaceCalculator`. Choose **round**. Give `TelemetryMath.clock` an hours branch. Delete `formatSeconds`. Replace `1.60934` / `1609.34` with the exact constant already declared at `PaceCalculator.swift:16-17`.
- Actually use `DistanceFormat` — until you do, km support doesn't exist.
- Pick `Drip*` or the bare family. Delete the loser.
- Ban `dripCaption` for eyebrows; make `dripEyebrow` the only path.

### 4. Rebuild edit mode in the editorial idiom

Both edit sections through `editorialSection(eyebrow:)`. Labels DIST / TIME. This is the change users will actually feel.

### 5. Add the foreign key — the highest-leverage change in the document

```sql
alter table training_logs add column linked_workout_log_id uuid references training_logs(id);
alter table training_logs add column healthkit_workout_uuid text;
```

Append-only, per your rule #5. Backfill by running the existing heuristic **once, offline** instead of on every read. Then delete `matchVitalWorkout`'s ranking, `dedupedMiles`, `WorkoutPickerSheet`'s ±300s matcher, and `removeAutoSyncEntry`.

Note the attach path in `VoiceLogViewModel.swift:85-95` already argues for this in a comment — it's the design doc for the merge, written by whoever last touched that file. It just only works for `vitalWorkoutId` today.

### 6. Extract the composer, then embed it

- `VoiceRecorder` — audio session + `AVAudioRecorder` + timer + permission FSM, currently living in the *view* at `VoiceLogView.swift:844-980`
- `LogEntryComposer` — the four write paths plus polling, moved to app scope so it outlives a dismissed sheet
- Give it an optional workout context. Bound → no picker. Unbound → today's picker behavior.

Then drop it into the detail sheet above the footer, and into the Log tab where it is now. **Same component, two hosts.** Keep the Log tab.

---

## What works well

- **The editorial layout itself.** Restrained, typographic, no icons, hairlines doing the structural work. It's the right direction and it's already built.
- **`editorialSection(eyebrow:)`** is a genuinely good abstraction. The screen's problems are all in the places that *don't* call it.
- **One table for runs and journal entries** was a good call. It's why the merge is mostly a UI problem rather than a schema rewrite.
- **`WorkoutLabel.swift`** is a properly designed single source of truth with a documented legacy path. Eight surfaces already respect it.
- **The comments are unusually honest.** Nearly every landmine in this document was flagged by a previous comment — the attach-path rationale, the beta-audit note about `HealthKitManager`, the `dripCaption` warning, the `matchVitalWorkout` mislink caveat. Whoever wrote them knew. They just didn't get to delete the old code.

---

## Appendix: sequenced prompts for Claude Code

Run these in order, one at a time, verifying the build between each. Steps 1–4 don't change behavior.

**Step 1 — Delete dead code**
> In `RunningLog/`, delete `Workouts/DripWorkoutPrimitives.swift` entirely. Then delete `CoachInsightSection` and `WorkoutNotesSection` from `Workouts/HistoryDetailSections.swift`; `WorkoutStatItem` from `Workouts/HistoryDetailSheet.swift`; and `callCoachingAgent`, `isQualityWorkout`, `saveCoachInsight`, `generateCoachInsight` from `Workouts/HistoryDetailViewModel.swift`. Also delete the unused `@State` properties `selectedWorkout` and `isEditingWorkoutNotes` in `HistoryDetailSheet.swift` and `isDeleting` in the view model. Before deleting each symbol, grep repo-wide to confirm zero call sites and report what you find. Build after each file.

**Step 2 — Fix the data bugs**
> In `Workouts/HistoryDetailViewModel.swift` `saveEdits`, the local `TrainingLog` rebuild keeps old values where the DB update writes `.null`. Fix lines 193, 196, 197 so `cleanedNotes`, `workoutDistanceMiles` and `workoutDurationMinutes` mirror exactly what was written. Then change `HistoryDetailSheet.swift:18` from `HealthKitManager()` to `HealthKitManager.shared` and remove the now-redundant `requestAuthorization()` call in `loadWorkouts()` if `.shared` already handles it.

**Step 3 — One workout-type vocabulary**
> `EditableWorkoutTypeSection` in `Workouts/HistoryDetailSections.swift` hardcodes six workout types including the retired `tempo` and `interval` keys. Replace that array with the canonical list from `App/WorkoutLabel.swift` — the effort zones, race-pace zones and structural types, excluding anything in the "Legacy" block. Display labels must come from `WorkoutLabel.display(_:)`. Existing rows stored with legacy keys must still render correctly.

**Step 4 — One formatter**
> Make `Workouts/PaceCalculator.swift` the only pace/duration formatter in the app. Find every other implementation and route it through PaceCalculator. Use rounding, not truncation, everywhere — including `formatMinutesForEdit` in `HistoryDetailViewModel.swift:422`. Add an hours branch to `TelemetryMath.clock` in `UnifiedTelemetryCard.swift:639`. Delete `formatSeconds` (duplicate of `formatTime`). Replace every `1.60934` and `1609.34` literal with the exact constants declared at `PaceCalculator.swift:16-17`. Write tests covering 419.7s, 3600s and 4696s.

**Step 5 — Edit mode in the editorial idiom**
> Rebuild `EditableWorkoutTypeSection` and `EditableWorkoutStatsSection` to use `editorialSection(eyebrow:)` from `HistoryDetailSheet+Editorial.swift`. No cards, no cornerRadius, no SF Symbols, no white backgrounds — hairline-separated rows and mono eyebrow labels, matching read mode exactly. Field labels become "DIST" and "TIME" to match the read-mode stat strip. Remove the format hints from the labels; the placeholders already carry them.

**Step 6 — Copy pass**
> Apply this terminology across `HistoryDetailSheet.swift`, `HistoryDetailSheet+Editorial.swift`, `HistoryDetailSections.swift`, `UnifiedTelemetryCard.swift` and `ReconciliationCard.swift`: the noun for the subject is "run" (or "entry" only when there is no linked workout) — never "session," "workout" or "log." Section eyebrows become one word: NOTE, EFFORT, READ, COMPARE. All buttons are ALL CAPS mono including the toolbar (Edit → EDIT, Save → SAVE, Done → DONE). Units are always a separate slot, never concatenated. No trailing periods on labels or empty states. True ellipsis `…` only. Then replace every `"—"` and `"--"` empty-value placeholder with `EmptyStateView` or an appropriately styled dash-free treatment, per hard rule #8.

**Step 7 — The foreign key**
> Write an append-only Supabase migration adding `linked_workout_log_id uuid references training_logs(id)` and `healthkit_workout_uuid text` to `training_logs`. Write a one-time backfill that runs the existing `matchVitalWorkout` heuristic offline to populate them for historical rows. Then update `HistoryDetailViewModel.linkWorkout` and `VoiceLogViewModel`'s insert path to persist the real ID alongside the existing denormalized scalars. Do not remove the scalars yet.

**Step 8 — Extract the composer**
> Extract two components from `Workouts/VoiceLogView.swift` and `VoiceLogViewModel.swift`: a `VoiceRecorder` owning the audio session, `AVAudioRecorder`, timer and permission state machine (currently lines 844-980 of the *view*); and a `LogEntryComposer` owning the four write paths and the processing poll. The composer must live at app scope, not view scope, so its polling survives a dismissed sheet. Give it an optional `linkedWorkout` context: when bound, skip the workout picker entirely. Behavior in the Log tab must be unchanged.

**Step 9 — Embed it**
> Add the extracted composer to `HistoryDetailSheet+Editorial.swift`, above the footer, pre-bound to this entry's run. Handle sheet dismissal mid-recording by stopping and deactivating the audio session. Keep the Log tab and its composer exactly as they are — check-ins and rest-day notes have no other authoring path and must not regress.

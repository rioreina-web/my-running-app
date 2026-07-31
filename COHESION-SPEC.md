# Post Run Drip — Cohesion Audit & Design Spec

*28 July 2026 · scope: iOS app (`RunningLog/`) · surfaces: Log, Workout Detail, Train, Trends*

---

## 0. The one-sentence diagnosis

**The app isn't incoherent because the design system is bad — it's incoherent because ~30% of the code that ships is dead, and the living code was written per-screen instead of from the system.**

Three numbers tell the whole story:

| | |
|---|---|
| Colour tokens adopted | **~99%** (4,800 `Color.drip.*` vs 36 stray hexes) |
| Spacing / radius / elevation / motion tokens | **0 — they do not exist** |
| Dead view code still compiling into the binary | **~8,250 LOC**, ~33 orphaned chart components |

There is a token layer for colour and (loosely) type. There is *no* token layer for the things that actually make screens look like they belong together: spacing, radius, elevation, motion. So every screen invents its own. That's the cohesion problem, and it's fixable in about a week of work.

**Audit score: 41 / 100.** Breakdown at §9.

---

## 1. What's actually wrong — evidence

### 1a. The missing half of the token layer

`App/DesignSystem.swift` defines 21 colour tokens and 6 font *functions*. It defines no spacing scale, no radius scale, no elevation scale, no motion scale, no tracking helper, no named type steps.

The consequences are measurable:

| Category | Count | Distinct values in use |
|---|---|---|
| Numeric `.padding(N)` | 1,984 | 20+ (293×`20`, 248×`16`, 194×`12`, 168×`14`, 158×`8`, 144×`4`…) — ~350 uses are off-grid (`3, 7, 9, 11, 13, 18, 22`) |
| Stack `spacing: N` | 1,886 | 15+ |
| Corner radii | 644 | **18** (12/10/16/8/14 cover 480; the other 13 values are 164 one-offs) |
| `.shadow(...)` | 26 | **16 distinct tuples** — 62% of shadows are unique |
| `.tracking(...)` | ~600 | **20** distinct values |
| `.font(.system(size:` | **631** | bypasses the type layer entirely — 22% of all typography |

The scale you need already exists — it's just trapped in one file. `App/NegativeSplits.swift:28`:

```swift
enum NSSpace { pagePadding 20, sectionGap 32, stackGap 12, inlineGap 8, hairline 1 }
enum NSRadius { card 14, chip 10 }
```

That's the design system's missing layer, marooned in a single screen.

### 1b. Nobody uses the primitives that exist

There are **four separate primitive libraries with no shared root**, plus three shadow libraries that are primitives in all but name:

| Library | Exports | Real adoption |
|---|---|---|
| `App/DesignSystem.swift` | 12 views | `StatCard` has **3 references app-wide** (one is its own definition) |
| `App/DripEditorialPrimitives.swift` | 18 primitives | `DripSection` 2, `DripStatStrip` 3, `DripStatTile` 6 |
| `Workouts/DripWorkoutPrimitives.swift` | 14 chart primitives | **0 — entirely dead** |
| `App/NegativeSplits.swift` (`NS*`) | 16 types | one screen |
| `Training/DayDetailPlate22.swift` (`DD22*`) | 6 types | one screen |

So instead you have, app-wide:

- **16** section-header implementations
- **19** stat-display implementations
- **22** pill / chip / badge implementations
- **38** named `*Card` types **+ 265 inline card recipes across 103 files** (7 fills × 7 radii × 15 strokes × 16 shadows)
- **6** hairline implementations
- **2** implementations of `PlateStrip` — the design system's signature gesture

**178 `private`/`fileprivate struct` views** confirm the habit: components get built per-screen and never promoted.

### 1c. A third of the code can't render

| Area | Dead LOC | Notes |
|---|---|---|
| `Trends/` + `Analysis/` orphans | **~4,750** | `TrendsInsightsTabView`, `CompareDashboardView`, `ThresholdWorkView`, `SharpEndFitnessRead(+Charts)`, `FastSegmentsView`, `InsightTrendChart`, `TrainingAnalysisView`, `FitnessPredictorView_Rebrand` |
| Workout-detail orphans | **~3,500** | `DripWorkoutPrimitives` (913), `UnifiedTelemetryCard` (680), `VitalWorkoutCards`, `VitalWorkoutCharts`, `ReconciliationCard`, `PaceZoneBarsChart`, `StadiaRouteMap`, 8 orphan `RR*` charts, `CoachInsightSection`, `WorkoutNotesSection` |
| Log orphans | ~274 | `App/LogView.swift` — a **whole second journal design** that never ships |
| Train orphans | — | `TrainingTodayHero`, `DayDetailPlate22`, `MonthCalendarView`, `MileageSkylineGrid`, `TrainingTabTwoView` (513) |
| Stale `.bak` files in source | — | `RouteMapView.swift.bak-*`, `WorkoutRepChart.swift.bak-*`, `RouteSanitizer.swift.bak-*` |

Nothing marks these as dead. No feature flag, no folder, no comment convention. The only way to tell live from dead is to grep call sites — which means **every future change is made with 30% noise in the search results**. This is the single largest tax on your ability to develop this into a better product.

`Trends/TrendsTabView.swift:26-28` already admits it: *"Unlinked, not deleted: the Sharp End fitness read, the pace×effort map, the workload scatter, the Compare trend grid, Threshold work, and the Trends 2 tab."*

### 1d. Nine chart implementations for one chart

In the workout-detail path alone:

- **9** implementations of what `RRTelemetryPanel` now draws in one panel (`RRPaceTrace`, `RRCadenceStrip`, `RRElevationGrade`, `DripPaceOverTimeChart`, `DripCadenceChart`, `DripElevationProfile`, `ElevationProfileCard`, `PaceChartCard`, `TelemetryChartCanvas`)
- **6** split tables · **4** time-in-zone charts · **4** route renderers · **2** comparison surfaces one tap apart

Trends has **22 chart structs, 21 hand-rolled `Canvas` blocks, zero `import Charts`** — and re-draws the same twelve weeks four times in one scroll (`UnifiedTrainingChart`'s four tracks are each redrawn by the detail view immediately below it).

### 1e. Two numbers for the same metric on one screen

`Trends` renders ACWR twice from two sources that disagree:

- `VolumeDetailView(canonicalAcwr:)` ← `athlete_state` (canonical)
- `PaceSignalView` WORKLOAD tile ← `SignalService`'s own computation

Also on that screen: **two competing time-range controls** (host segmenter 4wk/12wk/6mo + `PaceSignalView`'s own 6-option range bar, because `embedded: true` only suppresses the header).

### 1f. Wordiness — the actual numbers

| Surface | Shipped static prose |
|---|---|
| Workout Detail | **~200 words in a single pass**, before AI text loads (384 words of static copy total in scope) |
| Trends | **~915 shipped words** in one scroll (2,552 across the folder) |

And the structural problem is worse than the count. **The workout detail sheet renders three AI voices in three registers in one scroll:**

1. `AI INSIGHT` — `HistoryDetailSheet+Editorial.swift:243`
2. `THE READ` — `WorkoutRepReceiptView.swift:758`
3. the comparison sentence — `:952`

Plus the log entry stacks **four renderings of the same run**: VOICE SUMMARY (AI rewrite) → TRANSCRIPT (verbatim) → the entire workout receipt injected in the middle → AI INSIGHT (AI advice) → WORKOUT NOTES (free text).

It also renders **~4 stat strips** and **2 mood badges** per scroll.

Most of the remaining copy is chart instructions — text explaining how to read a chart, which the chart should do itself:

> "Every mile you ran, sorted by pace. A tall pale base at the easy end with a small dark tail is the shape you want. Drag across the bars to read any pace." — `PaceSignalView.swift:319`

> "TAP A REP OR PRESS & HOLD FOR LIVE VALUES · EXPAND TO SCRUB" — `RRTelemetryPanel.swift:112`

### 1g. Two hardcoded "insights" presented as analysis

These are the most serious findings in the audit, because they damage trust rather than aesthetics.

**`Trends/TrendsTabView.swift:450`** — rendered unconditionally whenever any week has a voice quote, sitting *between two genuinely-derived insights*:

```swift
InsightBlock(text: "Mood dips a day after the long run, then recovers. Predictable, not a warning.")
```

**`WorkoutRepReceiptView.swift:1005`** — `computedRead`'s fallback, fires regardless of data:

> "…Controlled and even — exactly the session you drew up."

Both read as data. Neither is. **Delete both before beta.**

---

## 2. The rules — what "cohesive" means for this app

Six rules. Everything in §3–§7 follows from them.

**R1 · One token, one value.** If a number appears in a view file, it must come from a token. Spacing, radius, elevation, motion, tracking, type step. No exceptions outside chart-internal geometry.

**R2 · One concept, one component.** One hairline. One eyebrow. One stat strip. One capsule. One card. If you need a variant, add a parameter — never a new struct.

**R3 · One fact, one place.** A number appears once per screen. If ACWR is on the screen, it comes from `athlete_state` and it appears once. If weekly mileage is in the unified chart, the detail view below it shows the *non-chart* content only.

**R4 · One AI voice, one block.** Each surface gets exactly one AI-written block. Log entry: the Overview. Workout detail: the Read. Trends: the weekly note. Never two.

**R5 · The chart explains itself; the caption doesn't.** If a chart needs a paragraph to be legible, redesign the chart. Allowed: a ≤8-word axis/unit clarifier. Not allowed: how-to-read instructions, gesture instructions, math explanations.

**R6 · Dead code is deleted, not unlinked.** Git remembers. An unlinked view is a permanent tax on every future search.

### The wordiness rule, concretely

Wordiness isn't "prose is bad" — it's *the same thing said four ways*. The fix is **one canonical rendering per fact, at three depths**:

| Depth | What it holds | Length budget |
|---|---|---|
| **Glance** — feed row, day cell, chart | numbers + colour + ≤6-word label | 0 sentences |
| **Read** — entry / detail body | the numbers, one AI block, athlete's own words | **1 AI block, ≤3 sentences** |
| **Options** — overflow, disclosure, sheet | transcript, audio, raw data, edit, delete | unbounded |

Every screen's copy budget:

- **1** AI narrative block (≤3 sentences, ≤60 words)
- **1** stat strip
- **0** how-to-read captions
- **≤1** empty-state sentence
- Everything else is a number, a label, or a chip

---

## 3. Foundation: the tokens to add

Add to `App/DesignSystem.swift`. ~60 lines. **Do this first — everything else points at it.**

```swift
// MARK: - Spacing
enum DripSpace {
    static let xs: CGFloat  = 4
    static let sm: CGFloat  = 8
    static let md: CGFloat  = 12
    static let lg: CGFloat  = 16
    static let page: CGFloat = 20   // page gutter
    static let xl: CGFloat  = 24
    static let section: CGFloat = 32 // gap between sections
    static let xxl: CGFloat = 40
}

// MARK: - Radius  (3 values cover 480 of 644 current uses)
enum DripRadius {
    static let sm: CGFloat = 8    // chips, inline wells
    static let md: CGFloat = 12   // default card
    static let lg: CGFloat = 16   // hero / sheet-level containers
    // Capsule() for all pills — never a numeric radius
}

// MARK: - Elevation  (editorial = flat; hairline does the work)
enum DripElevation {
    case none, card
    var shadow: (Color, CGFloat, CGFloat, CGFloat)? {
        switch self {
        case .none: return nil
        case .card: return (Color.black.opacity(0.06), 8, 0, 2)
        }
    }
}

// MARK: - Motion
enum DripMotion {
    static let quick    = Animation.easeOut(duration: 0.15)
    static let standard = Animation.easeInOut(duration: 0.20)
    static let emphasis = Animation.spring(response: 0.35, dampingFraction: 0.8)
}

// MARK: - Type steps  (tracking baked in — retires 20 ad-hoc values)
extension Font {
    static var dripTitleXL: Font { .dripDisplay(44) }
    static var dripTitleLg: Font { .dripDisplay(34) }
    static var dripTitleMd: Font { .dripDisplay(20) }
    static var dripBodyMd:  Font { .dripBody(16) }
    static var dripBodySm:  Font { .dripBody(14) }
    static var dripStatXL:  Font { .dripStat(28) }
    static var dripStatMd:  Font { .dripStat(16) }
    static var dripStatSm:  Font { .dripStat(12) }
}

extension View {
    /// The one eyebrow treatment. Replaces 8+ spellings.
    func dripEyebrowStyle() -> some View {
        self.font(.dripEyebrow(11)).tracking(1.2)
            .foregroundStyle(Color.drip.textSecondary)
    }

    /// The one card container. Replaces ~265 inline recipes.
    func dripCard(radius: CGFloat = DripRadius.md,
                  fill: Color = .drip.cardBackground,
                  bordered: Bool = true,
                  elevation: DripElevation = .none) -> some View {
        self.background(
            RoundedRectangle(cornerRadius: radius, style: .continuous).fill(fill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(bordered ? Color.drip.divider : .clear, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}
```

Two notes:

- **`style: .continuous` everywhere.** Currently used exactly **once** in 644 radii. Apple's squircle vs. circular corner is a subtle but pervasive "this app was assembled, not designed" tell.
- **Flat by default.** 26 shadows / 16 recipes across the app, and the editorial spec is flat-on-paper. Keep `.card` for the two or three places that genuinely float; delete the rest, especially `black.opacity(0.5), r20, y10` (a generic iOS drop shadow).

### The canonical component set

Everything below collapses into these. Nothing else gets defined at app level.

| Component | Replaces | Lives in |
|---|---|---|
| `DripEyebrow` | 8+ eyebrow spellings, `KitEyebrow`, `NSEyebrow`, `TrackEyebrow`, `DD22StructureEyebrow`, `sectionHead`, `subHead`, `DetailHead` | `DripEditorialPrimitives.swift` |
| `DripHairline` (48 uses — the winner) | `Hairline` (16), `NSHairline`, `SectionRule`, `AnalysisDivider`, `JournalDivider` | " |
| `DripStatStrip` | 19 stat displays, `statStrip4`, `NSStatStrip`, `DD22StatStrip`, `StatCard` | " |
| `DripCapsule(label:tone:dot:)` — **new**, generalise `MoodBadge` | 22 pill/chip/badge types | " |
| `.dripCard(...)` | 38 `*Card` types + 265 inline recipes | `DesignSystem.swift` |
| `DripPlateStrip` | `PlateStrip` (pick one — see below) | " |
| `EditorialRule` | `DD22EditorialRule` | " |
| `EmptyStateView` (already 17 uses ✅) | `EmptyPlanState`, `BuilderEmptyState`, `NSQuietError` | `Shared/` |

**Merge `DripEditorialPrimitives.swift` into `DesignSystem.swift`.** The split is *why* `DripStatTile`/`DripStatStrip`/`DripSection` have 6/3/2 uses and `StatCard` has 3 — nobody knows which file to reach for. One import target.

**Resolve `PlateStrip` (11 uses) vs `DripPlateStrip` (8 uses) now.** Two implementations of your signature visual gesture is the worst single offender in the audit. Keep `DripPlateStrip`, delete `PlateStrip`.

---

## 4. Log — spec

### What it should be (your words, made concrete)

> A log is a **note attached to a workout**. It extracts the signals. It renders one clean entry with an AI Overview. The voice memo lives in options.

### The finding that changes everything

**Your extraction layer already captures ~20 structured signals per memo. The Log surface renders exactly two of them.**

Server-side (`supabase/functions/_shared/prompts/process-training-memo.v3.ts`) already extracts: `rpe`, `sleep_quality`, `sleep_hours`, `fueling`, `effort_level`, `felt_vs_looked`, `weather`, `terrain`, `work_stress`, `life_stress`, `travel`, `fatigue`, `illness`, `motivation`, `soreness[]`, `resolved_niggles[]`, `shoe`, `partners`, `mood`.

All of it lands in an `extracted_data` JSONB column. **iOS never decodes it.** `Models/TrainingLog.swift:79-130` decodes 22 fields and `extracted_data` is not among them — it's read in exactly one place (`FitnessPredictorService.swift:1194`) and only for `race_candidate`.

So the app pays for extraction, then throws it away and renders the same information back as four blocks of prose.

| Your intent | Extracted? | Shown in Log? |
|---|---|---|
| Mood | ✅ closed vocab | ✅ rule colour + footer |
| Niggles | ✅ `soreness[]`, `resolved_niggles[]` | ⚠️ **feed row only** — grep `niggle` in `HistoryDetailSheet*` → **zero hits**. Open the entry and they vanish. |
| Were paces hit | ⚠️ prose input to the AI only, no structured field | ❌ buried in a sentence |
| Missed sleep | ✅ `sleep_quality`, `sleep_hours` | ❌ never decoded |
| Hydration | ❌ **no such field** — nearest is `fueling` | ❌ |
| RPE / effort | ✅ `rpe`, `felt_rpe`, `effort_level` | ❌ |
| Weather, terrain, stress, travel, fatigue, illness | ✅ all | ❌ none |

**Highest-leverage change in the entire audit: decode `extracted_data` into `TrainingLog` and render it as a signal row.** That single change lets VOICE SUMMARY + AI INSIGHT collapse into one short overview, because the facts finally live in chips instead of sentences.

### Two more structural problems

**The link to the workout is a value-copy, not a foreign key.** There is no `workout_id` on `training_logs`. "Linked" means `workout_date` + `workout_distance_miles` were copied onto the log row, and `hasLinkedWorkout` is the heuristic `workoutDate != nil && workoutDistanceMiles != nil` (`TrainingLog.swift:246`). This is why `App/LogDedup.swift` exists — a client-side day-grouping / ±0.1mi-clustering / source-priority heuristic whose own header says it is *"NOT a substitute for backend dedup"* — **and the Log feed doesn't even use it.**

Consequence: **three separate workout pickers** for one concept (`WorkoutPickerSheet`, `HistoryWorkoutPickerSheet`, the `LINK TO WORKOUT` card), and the linking question is asked **twice** during one voice log, in two different visual idioms.

**Voice is the hero, not an option.** `VoiceLogView.swift:88-117` sizes the record hero to `max(screenHeight - 60, 600)` — it owns the entire first screen, and typing is explicitly below the fold. A voice log takes **5 surfaces**: tab → picker → record → confirmation sheet (which re-asks linking) → success overlay. And there is **no audio player anywhere** — `JournalLogRow.swift:114` shows a `play.fill` glyph that is decorative only.

### Target: the entry

```
┌──────────────────────────────────────┐
│ ▍ Tuesday's tempo felt heavy         │  mood rule + title, dripTitleMd
│   JUL 22 · TEMPO · 8.0 MI            │  DripEyebrow
├──────────────────────────────────────┤
│   8.0 MI    52:14    6:32/MI    148  │  DripStatStrip (the ONLY one)
├──────────────────────────────────────┤
│ ⬤ HEAVY   RPE 8   SLEEP 5.2H   ⚠ CALF│  DripCapsule row ← extracted_data
├──────────────────────────────────────┤
│ Paces held through rep 4, then        │  THE Overview. ≤3 sentences.
│ drifted 8s. Short sleep is the most   │  One AI voice. Nothing else.
│ likely cause — worth an easy day.     │
├──────────────────────────────────────┤
│ "legs were just dead from the start"  │  athlete's own words, ≤2 lines
├──────────────────────────────────────┤
│ VIEW WORKOUT ↗                        │  → Workout Detail. Not inline.
│ OPTIONS ⌄                             │  → transcript · audio · notes ·
└──────────────────────────────────────┘    edit · delete
```

**Build steps:**

1. Add `extracted_data` decoding to `Models/TrainingLog.swift` (typed struct: `rpe`, `sleepHours`, `sleepQuality`, `fueling`, `soreness[]`, `resolvedNiggles[]`, `weather`, `effortLevel`).
2. Add a `paces_hit` enum to the extraction prompt — `hit` / `close` / `missed` / `n_a` — so "were the paces hit" is a chip, not a sentence.
3. Add a `hydration` field to the extraction prompt (it doesn't exist today; `fueling` is food+drink combined).
4. Build `DripSignalRow` from `DripCapsule`. Renders only non-nil signals, max 5, overflow → Options.
5. **Merge `cleanedNotes` + `coachInsight` into one `overview` field.** Rewrite the prompt: *one paragraph, ≤3 sentences, ≤60 words, states what happened and the single most useful observation. No advice unless it is the observation.*
6. Move `TRANSCRIPT` into `OPTIONS`. Add a real audio player there.
7. **Remove the inline `WorkoutRepReceiptView` from the entry** (`+Editorial:202-206`). Replace with `VIEW WORKOUT ↗`.
8. Delete `App/LogView.swift` (dead second design). Delete `HistoryDetailSections.swift`'s `CoachInsightSection` + `WorkoutNotesSection` (dead).
9. Collapse three pickers to one. Ask the linking question **once** — in the confirmation sheet, prefilled from the day's runs.
10. Render niggles in the entry, not just the feed row.
11. Fix `TrainingLog.workoutTypeLabel:284-299` — still emits retired `"Tempo"`/`"Intervals"` labels.
12. Fix the two `"—"` em-dash empty states (`JournalLogRow.swift:85`, `+Editorial:99`) — violates your own hard rule #8.
13. Fix `HistoryDetailSheet.swift:18` — creates its own `HealthKitManager()`, the exact bug already fixed in `VoiceLogView.swift:36`.

**Backlog (post-beta, but decide now):** add a real `workout_id` FK to `training_logs`. Every linking bug, the dedup layer, and the three pickers all descend from its absence.

---

## 5. Workout Detail — spec ★ priority 1

### Target: three acts, one voice, one strip

```
ACT 1 · IDENTITY      type eyebrow · date · ONE stat strip (DIST TIME PACE HR)
                      · conditions
ACT 2 · THE READ      ONE AI block ≤3 sentences · mood + quote (once)
                      · rep bars + rep table
ACT 3 · TRACES        collapsed disclosures: HR ZONES · TELEMETRY · RECOVERY
                      · COMPARISON · ROUTE — one open by default, rest closed
```

The three-act structure in `WorkoutRepReceiptView` is **already right**. The problem is everything piled on top of it.

### Build steps

**1 · Delete the dead stack (~3,500 LOC, zero behaviour change).**

`DripWorkoutPrimitives.swift` (913) · `UnifiedTelemetryCard.swift` (680) · `VitalWorkoutCards.swift` · `VitalWorkoutCharts.swift` · `ReconciliationCard.swift` · `PaceZoneBarsChart.swift` · `StadiaRouteMap.swift` · `RouteMapView.swift.bak-*` · `CoachInsightSection` + `WorkoutNotesSection` in `HistoryDetailSections.swift` · the 8 orphan `RR*` charts in `WorkoutReceiptCharts.swift` (`RepSplitsList`, `LapSplitsList`, `RRHRDrift`, `RRZoneTimeline`, `RRPaceTrace`, `RRCadenceStrip`, `RRElevationGrade`, `RRRouteShape`).

Do this **first**. Every subsequent change gets easier because the search results stop lying.

**2 · Stop rendering the receipt twice.**

`+Editorial:202-206` embeds the entire three-act `WorkoutRepReceiptView` inside the journal entry, while `linkedSourceRow:347` opens the identical view full-screen. Today the athlete scrolls the same content twice. **Decision: the log entry stays qualitative; `VIEW DETAIL ↗` owns all analytics.** (This is also Log build-step 7.)

**3 · Collapse three AI voices to one.**

Keep `THE READ` (Act 2). Delete `AI INSIGHT` (`+Editorial:243`) — the log entry's Overview replaces it. Reduce the comparison sentence (`:952`) to a stat delta with no prose. **Delete `computedRead`'s hardcoded verdicts** (`:1000`, `:1005`) — "Controlled and even — exactly the session you drew up" fires regardless of data.

**4 · One stat strip, one mood badge.**

Currently ~4 stat strips (`DripStatStrip` `+Editorial:132`, `statStrip4` `:424`, `repsFooterLine`, trace summaries) and 2 mood badges within one scroll. Keep `statStrip4` in Act 1. Keep one `MoodBadge` in Act 2. Delete the rest.

**5 · Canonicalise chart per fact.**

| Fact | Canonical | Delete |
|---|---|---|
| pace / HR / cadence / elevation over time | `RRTelemetryPanel` | 8 others |
| time in zone | `RRZoneBar` | 3 others |
| splits | `RepsTable` | 5 others |
| route | `RouteMapView` | 3 others |
| comparison | `WorkoutComparisonSheet` (Act 3 disclosure) | inline `RRComparison` |

**6 · Tokenise.**

9 card treatments and **12 corner radii** in one sheet. Route all through `.dripCard()`. Replace all 8+ eyebrow spellings with `DripEyebrow`. Delete the two `RouteMapView` shadows (the only shadows in scope — they make the map read as a different app).

**7 · Cut the copy.**

Delete every gesture instruction (`RRTelemetryPanel.swift:112`, `:902`, `:903`). Cut the no-data strings to one sentence each. Budget: **≤80 static words in the whole sheet.**

---

## 6. Train — spec

The IA is sound: `Log · Trends · Train` (3 tabs — CLAUDE.md's "5 tabs" is stale), and Train segments `CURRENT | CALENDAR | HISTORY`. Your read is right: this one's close.

### Your ask: click through history into logs and workout details

**Both paths are one small edit each.**

**Gap 1 — workout detail is Strava-only.**

```swift
// Training/Analytics/TrainingAnalyticsViewModel.swift:241
var canOpenAnalysis: Bool { (source ?? "").lowercased() == "strava" }
```

This gates the `FULL ANALYSIS ↗` button at `DayAnalysisSheet.swift:193`. But HealthKit writes `source = "auto_sync"` (`WorkoutSyncService.swift:142`) and voice/manual writes `"voice_log"` — so **every non-Strava run is a dead end**. `WorkoutRepDetailSheet` keys off the `training_logs` row id and reads `running_workout_laps` — it's source-agnostic. The gate is unnecessary.

**Fix:** gate on data presence, not source:

```swift
var canOpenAnalysis: Bool { hasLaps || hasPaceSegments }
```

The `workoutAnalysisSheet($analysisTarget)` plumbing is already installed at `DayAnalysisSheet.swift:65`. This lights it up.

**Gap 2 — the log entry is unreachable from Train, full stop.**

`DayAnalysisSheet` renders the log's `pullQuote` as inert `Text` (`:174-179`) with no gesture, and never presents `HistoryDetailSheet`.

The wiring exists but is orphaned — `TrainingPlanView.swift:20-22` declares `selectedLogEntry`, `dayLogEntries`, `showDayLogPicker`; `:219` and `:226` consume them in two `.sheet` modifiers; **nothing ever assigns them.** `DayLogPickerSheet:539` is unreachable code.

**Fix:** add `.sheet(item: $selectedLogEntry) { HistoryDetailSheet(entry: $0) }` to `DayAnalysisSheet` and make the pull-quote + session header the tap target. The row `id` is already in `SessionDetail.id`.

### The four-way detail-sheet split

Four parallel "tap a completed run" presentations exist:

| Surface | Where |
|---|---|
| `WorkoutRepDetailSheet` — self-declares "THE single canonical workout-detail sheet" | `WorkoutRepDetailSheet.swift:4` |
| `WorkoutRepReceiptView` embedded raw, no chrome | `WorkoutsAndRepsSection.swift:80` |
| `HistoryDetailSheet` | Trends ×4, `TrainingPlanView` |
| `SignalDaySheet` — its own MARK calls it "the 'workout detail' for a tapped day" | `PaceSignalView.swift:766` |

**Rule:** `WorkoutRepDetailSheet` is the only entry point to workout analytics, from everywhere. `HistoryDetailSheet` is the log entry, and is only for logs. Delete `SignalDaySheet`; route it to `WorkoutRepDetailSheet`.

`DayDetailSheet.swift` (1,793 LOC) is **not** a duplicate — it's the *prescribed/scheduled* workout editor (plan-holders only). Leave it. But note it's only reachable via CALENDAR → plan → week list, which is deep.

Also: `DayAnalysisSheet.swift:250` uses `"—"` for an empty HR cell — hard rule #8.

Delete the Train orphans: `TrainingTodayHero`, `DayDetailPlate22`, `MonthCalendarView`, `MileageSkylineGrid`, `TrainingTabTwoView` (513).

---

## 7. Trends — spec ★ priority 2

This is the least-finished surface and the audit shows why: it's carrying six abandoned attempts at itself.

### Build steps

**1 · Delete ~4,750 LOC of orphans.**

`TrendsInsightsTabView` (799) · `CompareDashboardView` (405) · `ThresholdWorkView` (919) · `SharpEndFitnessRead` (518) + `SharpEndFitnessCharts` (289) · `FastSegmentsView` (518) · `InsightTrendChart` (109) · `Analysis/TrainingAnalysisView.swift` (996) · `Analysis/FitnessPredictorView_Rebrand.swift` (1,200).

**60% of the folder's prose lives in this dead code.** Deleting it is the single biggest wordiness win available.

**2 · Fix the double-render.**

All four `UnifiedTrainingChart` tracks are redrawn immediately below by `VolumeChart`, `TrendsSessionGrid`, the mood ribbon, and `NiggleSwimlanes`. **Decision: keep `UnifiedTrainingChart` as the section-01 hero; reduce the four detail views to their non-chart content** (stat tiles, quote lists, swimlane labels). Today the athlete scrolls the same twelve weeks four times.

**3 · Un-embed `PaceSignalView`.**

`embedded: true` only suppresses `header` (`:196-220`). Still rendering: a 6-option range bar fighting the host's 3-option segmenter, a third segmenter, a WORKLOAD tile whose ACWR **disagrees with the canonical `athlete_state` value on the same screen**, and a fourth prose block.

**Fix:** extract `SpectrumDistribution` alone for the "Pace spectrum" section, driven by the host's `TrendsRange`. One time-range control per screen. One ACWR, from `athlete_state`.

**4 · Delete the fabricated insight** at `TrendsTabView.swift:450`, and the ACWR math explanation at `TrendsDetailViews.swift:670`.

**5 · Cut ~915 words to ~250.** Kill every chart-instruction caption (`PaceSignalView.swift:319`, `:331`, `:345`, `:370`; `TrendsDetailViews.swift:445`). Per R5, if the chart needs a paragraph, fix the chart.

**6 · Route through the primitives.** Trends uses exactly **one** `Drip*` primitive (`DripStatTile` ×3) and hand-rolls the rest: `sectionHead`, `subHead`, `DetailHead`, `TrackEyebrow`, `SummaryCard`, three private `label()` helpers. Replace with `DripEyebrow` + `DripSection` + `DripStatStrip`. Collapse ten ad-hoc radii to the token set. Drop the three card shadows.

`Workouts/HistoryDetailSheet+Editorial.swift` is the in-repo proof this works — 26 primitive uses in 547 lines. Use it as the reference implementation.

### Target structure

```
01 · THE BLOCK       UnifiedTrainingChart (4 tracks) + scrub readout
02 · VOLUME          stat tiles + ACWR (canonical, once). No second chart.
03 · KEY SESSIONS    TrendsSessionGrid
04 · PACE SPECTRUM   SpectrumDistribution only
05 · SIGNALS         mood + niggles as tiles/swimlanes, no chart repeat
06 · RACE            RacePredictionTrack
```

---

## 8. Sequence

Ordered by leverage, not by surface. Each phase is independently shippable.

| # | Phase | Effort | Why here |
|---|---|---|---|
| **1** | **Delete all dead code** (~8,250 LOC) | 1 day | Every later step gets easier. Zero behaviour change. Do it first. |
| **2** | **Add the four token scales + `.dripCard` + `DripEyebrow` + `DripCapsule`**; merge the two primitive files | 1 day | Nothing else can be consistent until these exist |
| **3** | **Delete the two fabricated insights** (`TrendsTabView:450`, `computedRead:1005`) | 30 min | Trust risk. Before beta, full stop. |
| **4** | **Workout Detail** — one voice, one strip, canonical charts, tokenised | 2 days | Your priority 1; also the reference implementation |
| **5** | **Trends** — un-embed, de-duplicate, cut copy, route through primitives | 2 days | Your priority 2 |
| **6** | **Train drill-through** — the two one-line fixes | 2 hours | Your explicit ask; smallest effort in the list |
| **7** | **Log** — decode `extracted_data`, signal chips, merge the AI blocks, voice → options | 3 days | Biggest product change; needs the tokens from #2 |
| **8** | **Sweep** — replace 631 `.font(.system(size:` and off-grid padding, top 10 files first | 2 days | Mechanical; do it last, all at once |
| **B** | *Backlog:* `workout_id` FK on `training_logs` | — | Retires the dedup layer and the three pickers |

Phases 1–3 are three days and remove more incoherence than anything else on the list.

### For future development

Two habits that will keep this from re-accumulating:

- **A component you write twice becomes a primitive.** The 178 private view structs are the mechanism by which this app drifted. Second use → promote it.
- **Nothing gets unlinked.** Delete it; git has it. `Trends/` is what "unlinked, not deleted" costs after six months.

---

## 9. Score

| Dimension | Score | Note |
|---|---|---|
| Colour tokens | **9/10** | ~99% adoption; 36 stray hexes, mostly re-declarations of existing tokens |
| Type tokens | **4/10** | Exists but size-parameterised, so callers invent sizes (`dripStat` at 24 distinct sizes); 631 bypasses |
| Spacing tokens | **0/10** | Do not exist |
| Radius tokens | **0/10** | Do not exist. 18 values in use |
| Elevation tokens | **0/10** | Do not exist. 16 recipes for 26 shadows |
| Motion tokens | **0/10** | Do not exist |
| Component reuse | **2/10** | 4 competing libraries; flagship primitives at 2–6 uses |
| Dead code hygiene | **1/10** | ~8,250 LOC unlinked, no marker convention |
| Chart canonicality | **2/10** | 9 implementations of one chart; 22 chart structs in Trends |
| Information hierarchy | **3/10** | 3 AI voices / 4 stat strips / 2 mood badges per scroll |
| Copy discipline | **3/10** | ~915 words in Trends, ~200 in detail; instructions instead of legible charts |
| Data integrity in UI | **2/10** | 2 fabricated insights rendered as analysis; 2 ACWR values on one screen |
| Navigation completeness | **5/10** | Train→history blocked by a one-line source gate + unassigned state |

**Total: 41 / 100.**

The good news is the shape of that scorecard. The expensive things to fix — brand, palette, typography, the editorial voice, the three-act structure — are done and they're good. The cheap things are what's broken, and phases 1–3 alone move this to roughly 70.

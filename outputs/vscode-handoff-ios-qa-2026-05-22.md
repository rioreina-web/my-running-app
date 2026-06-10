# VSCode handoff — iOS QA session, 2026-05-22

Picks up from a Cowork session that ported the tab bar to the canonical
Post Run Drip spec and started chipping at a list of issues surfaced
during rapid QA on the simulator. Read this end-to-end before touching
anything — context first, then file-level work items.

---

## What's already landed (do not redo)

### 1. Tab bar port — stable
- **New file:** `RunningLog/RunningLog/App/DripTabBar.swift` (~265 lines).
  Authored from the spec since the "ready to copy" file referenced in
  the implementation plan did not actually exist on disk. Mirrors
  `Post Run Drip Design System/ui_kits/ios_app/Primitives.jsx::TabBar`
  and `tokens.css`: stroked 6pt dot inactive, filled coral dot active,
  10pt mono uppercase label tracked at 1.2, paper background extending
  through the bottom safe area, `UISelectionFeedbackGenerator` haptic
  on commit, 0.97 press scale via a private `ButtonStyle`. Public
  `DripTab` enum with `rawValue: Int` (0–4) matching the existing
  `selectedTab` tags. Optional `badged: Set<DripTab>` and
  `disabled: Set<DripTab>` params; neither wired yet.
- **Rewrote** `MainTabView.body` in
  `RunningLog/RunningLog/App/RunningLogApp.swift` to use a `ZStack`
  with all five tab `NavigationStack`s rendered simultaneously, each
  gated by `.opacity(selectedTab == n ? 1 : 0)` and
  `.allowsHitTesting(selectedTab == n)`. Initial attempt used a
  `switch` (per the plan's recommendation) but it tore down each
  tab's view on swap, which cancelled in-flight URLSession requests
  and triggered spurious "Network error" banners and a refetch storm
  (`loadActivePlan`, `Starting fitness prediction...`,
  `[ScheduledWorkouts] Loaded 14 workouts` each firing 5+ times in a
  short session). ZStack matches the old `TabView`'s state-preservation
  behaviour.
- **Deleted** the `UITabBarAppearance` block in `configureAppearance()`
  — it was dead code once the system `TabView` was gone. Kept the
  `UINavigationBarAppearance` block intact.

### 2. Cancellation banner suppression — stable
- `RunningLog/RunningLog/Services/ErrorReporter.swift`: the convenience
  `report(_ error:context:retry:)` was wrapping **every** `URLError`
  as `.network(...)`, which surfaces as "Network error. Check your
  connection and try again." `URLError(.cancelled)` (NSURLError -999)
  is structural — fires whenever a Swift Task is cancelled mid-fetch
  (view teardown, refreshable mid-flight, app backgrounding). Added a
  private `isCancellation(_:)` helper that recognises
  `CancellationError`, `URLError.cancelled`, and `NSURLErrorCancelled`;
  the reporter early-returns (with a debug log) for any of those.

### 3. Pace & volume chart — partial, do not ship as-is
- `RunningLog/RunningLog/Workouts/PaceVolumeSpectrumChart.swift`:
  bumped `topLabelHeight` from 64 → 90 and added a `anchorLabelWidth: CGFloat = 44`
  constant. This is **incomplete**; see "Outstanding work" §1.

---

## Outstanding work (in flagged-priority order)

### 1. PACE & VOLUME · 9 WEEKS chart (Train · THE BLOCK)
**File:** `RunningLog/RunningLog/Workouts/PaceVolumeSpectrumChart.swift`

Three concrete symptoms in the user's screenshot:
- Anchor labels at the top right (EASY / MP / LT / 5K) collided into
  "MP5K" and "5:21:42" because the odd/even row alternation can't
  handle three clustered anchors (your race paces 5:21, 5:05, 4:42
  cluster within ~40s).
- X-axis labels jammed wall-to-wall reading
  `20:0019:008:007:006:005:004:00...` because the tick density is fixed
  at every 1 minute and the axis spans ~16 minutes.
- The KDE distribution piled up on the right because one outlier
  workout (warmup / walk break at ~20:00/mi) is pulling `paceSlow`
  to ~1245s, squeezing all real training into the rightmost 25%.

**Root cause:** the auto-fit `init` (lines 93–109) uses
`samples.max()` for the slow bound, so one slow run blows out the axis.

**Specific changes needed:**

a. **Auto-fit init** — replace `samples.max()` / `samples.min()` with
   percentile clipping AND cap the slow bound to `slowestAnchor + 90s`
   so a walk/warmup outlier cannot dictate the axis. Suggested:

   ```swift
   public init(
       samples: [PaceVolumeSample],
       anchors: [PaceAnchor],
       bandwidth: Double = 18
   ) {
       let pad: Double = 30
       let anchorPaces = anchors.map(\.paceSeconds)
       let slowestAnchor = anchorPaces.max() ?? 540
       let fastestAnchor = anchorPaces.min() ?? 330

       let samplePaces = samples.map(\.paceSeconds).sorted()
       let p90: Double = samplePaces.isEmpty ? slowestAnchor :
           samplePaces[min(samplePaces.count - 1, Int(Double(samplePaces.count - 1) * 0.9))]
       let p10: Double = samplePaces.isEmpty ? fastestAnchor :
           samplePaces[max(0, Int(Double(samplePaces.count - 1) * 0.1))]

       // Slow bound: include all anchors, allow a touch beyond the
       // 90th-percentile sample, but never more than 90s slower than
       // the slowest anchor (no walk breaks blowing out the axis).
       let slowCap = slowestAnchor + 90
       let slow = min(max(slowestAnchor, p90) + pad, slowCap)

       // Fast bound: never faster than fastestAnchor − 60s.
       let fastRaw = min(fastestAnchor, p10) - pad
       let fast = max(fastRaw, fastestAnchor - 60, 180)

       self.init(samples: samples, anchors: anchors,
                 paceSlow: slow, paceFast: fast, bandwidth: bandwidth)
   }
   ```

b. **Adaptive tick density** in `axisTickPaces` (lines 283–293):
   step every 2 minutes when range > 6 minutes, every 3 minutes when
   range > 12 minutes. Otherwise 1-minute.

   ```swift
   private var axisTickPaces: [Double] {
       let range = paceSlow - paceFast
       let step: Double = range > 720 ? 180 : range > 360 ? 120 : 60
       let lo = floor(paceFast / step) * step
       let hi = ceil(paceSlow / step) * step
       var ticks: [Double] = []
       var p = lo
       while p <= hi {
           if p >= paceFast && p <= paceSlow { ticks.append(p) }
           p += step
       }
       return ticks
   }
   ```

c. **Anchor label row** (lines 200–224) — replace the odd/even
   `yOffset` alternation with a greedy row-assignment algorithm. For
   each anchor in left-to-right x order, find the first row where its
   bounding box (`anchorLabelWidth` wide, centered on x) doesn't
   overlap the previous label assigned to that row. Allow up to 3 rows;
   `topLabelHeight` is already bumped to 90 to accommodate. Sketch:

   ```swift
   private func layoutAnchors(width: CGFloat) -> [(anchor: PaceAnchor, row: Int, x: CGFloat)] {
       let sorted = anchors
           .map { (anchor: $0, x: xFromPace($0.paceSeconds, width: width)) }
           .sorted { $0.x < $1.x }
       var rowRightEdge: [CGFloat] = []
       var out: [(PaceAnchor, Int, CGFloat)] = []
       for entry in sorted {
           let left = entry.x - anchorLabelWidth / 2
           let right = entry.x + anchorLabelWidth / 2
           var row = rowRightEdge.count
           for (i, edge) in rowRightEdge.enumerated() where left >= edge + 2 {
               row = i; break
           }
           if row < rowRightEdge.count { rowRightEdge[row] = right }
           else { rowRightEdge.append(right) }
           out.append((entry.anchor, row, entry.x))
       }
       return out
   }
   ```

   Then `anchorLabelRow`'s `ForEach` reads `(anchor, row, x)` from
   `layoutAnchors(width: geo.size.width)` and positions at
   `y = baseY + CGFloat(row) * 26`.

**Two call sites use the auto-fit init** — fixing it fixes both:
- `RunningLog/RunningLog/Training/TrainingTabView.swift:219`
- `RunningLog/RunningLog/Training/TrainingPaceAnalysisSection.swift:975`

### 2. FITNESS card truncation (Trends · stat tile grid)
**File:** `RunningLog/RunningLog/Trends/TrendsTabView.swift`

Symptom: card renders `2:27 — 2:…` because value (`2:27 — 2:34`,
11 chars) + unit (`MARATHON`, 8 chars) overflow `TrendStatTile`'s
single-line HStack (`lineLimit(1)`, value has `minimumScaleFactor(0.6)`,
unit doesn't).

**Fix (cleanest):** move "MARATHON" into the label slot so it parallels
the LOAD card (label "LOAD · ACWR" / unit "RATIO"). Card becomes
`FITNESS · MARATHON / 2:27 — 2:34 / HIGH CONFIDENCE`.

Lines 163–170 currently:

```swift
TrendStatTile(
    label: "FITNESS",
    value: fitnessRangeValue,
    unit: fitnessRangeUnit,        // returns "MARATHON" (line 339)
    delta: fitnessConfidence,
    deltaColor: fitnessConfidenceColor,
    action: { showFitnessPredictor = true }
)
```

Change to:

```swift
TrendStatTile(
    label: "FITNESS · MARATHON",
    value: fitnessRangeValue,
    unit: "",                       // or drop the unit slot entirely
    delta: fitnessConfidence,
    deltaColor: fitnessConfidenceColor,
    action: { showFitnessPredictor = true }
)
```

If `unit: ""` renders an empty Text with extra spacing, instead delete
the Text inside `TrendStatTile.tileContent` when `unit.isEmpty` (lines
640–642).

`fitnessRangeUnit` (line 339) can be removed once nothing reads it.

### 3. WEEKLY MILEAGE % comparison (Train · THIS WEEK)
**Files:**
- `RunningLog/RunningLog/Training/WeeklyMileageQuietRow.swift` (the view)
- `RunningLog/RunningLog/Training/TrainingTabView.swift:172–174, 383–397`
  (the data feed)

**User's chosen approach:** apples-to-apples through today + explicit
label. So on Thursday compare Mon–Thu this week vs Mon–Thu last week,
and label the delta `VS PRIOR · THRU THU` (use the abbreviation of the
current day-of-week).

**Specific changes:**

a. In `TrainingTabView.swift`, add a new derived value alongside
   `lastWeekMiles`:

   ```swift
   private var lastWeekMilesThroughToday: Double {
       let cal = Calendar.iso8601Monday
       let today = Date()
       let thisWeekStart = cal.startOfWeek(for: today)
       guard let lastWeekStart = cal.date(byAdding: .day, value: -7, to: thisWeekStart),
             let lastWeekCutoff = cal.date(byAdding: .day, value: -7, to: today)
       else { return 0 }
       return recentWorkouts
           .filter { $0.startDate >= lastWeekStart && $0.startDate < lastWeekCutoff }
           .reduce(0) { $0 + $1.distanceMiles }
   }

   private var currentDayAbbreviation: String {
       let df = DateFormatter()
       df.dateFormat = "EEE"  // "Mon", "Tue", ...
       return df.string(from: Date()).uppercased()
   }
   ```

b. Change the `WeeklyMileageQuietRow` call (line 172) to pass the
   through-today value AND a label suffix:

   ```swift
   WeeklyMileageQuietRow(
       thisWeekMiles: thisWeekMiles,
       lastWeekMiles: lastWeekMilesThroughToday,
       comparisonScope: currentDayAbbreviation   // e.g. "THU"
   )
   ```

c. Update `WeeklyMileageQuietRow.swift`: add the `comparisonScope: String`
   property and update `deltaText` to read
   `"+/-X% VS PRIOR · THRU \(comparisonScope)"` when scope is non-empty.

**Also: the `coachQuote` "FROM YOUR COACH" pull-quote in
`TrainingTabView.swift:357–379` uses the same `lastWeekMiles` for its
"Down X% on volume" line.** Same bug; should switch to
`lastWeekMilesThroughToday`. Otherwise the quote and the row will
disagree (the quote says "−57%" because it uses the broken full-week
comparison; the row will say "−4%" after the fix).

### 4. Wire mood_trend / last_mood from athlete_state into Trends UI
**File:** `RunningLog/RunningLog/Trends/TrendsTabView.swift:740–760`

`TrendsAthleteState` is currently a minimal projection that only
decodes `acwr`. The server-built `athlete_state` row already contains
`last_mood`, `mood_trend`, `last_readiness_score`, `last_check_in_at`
(from the migration at
`supabase/migrations/20260410200000_create_athlete_state.sql`).
`process-check-in/index.ts:238` writes those fields directly. The
data is one column away in the row the iOS app already fetches.

**One-line decoder change** + a new tile or strip on Trends to display
it. Sketch:

```swift
struct TrendsAthleteState: Decodable {
    let acwr: Double?
    let rolling_7d_miles: Double?
    let rolling_28d_miles: Double?
    let last_mood: String?
    let mood_trend: String?
    let last_readiness_score: Int?
    let last_check_in_at: Date?
    // ...fetch query at line 752 needs the new columns added to .select(...)
}
```

Then surface it however you want — a fifth stat tile, a strip below the
opening figure, or as the FITNESS card's secondary line.

### 5. Error banner layout (cosmetic)
**File:** `RunningLog/RunningLog/App/RunningLogApp.swift:171–191`

The error banner draws under the status bar / dynamic island because of
`.ignoresSafeArea(edges: .top)` on the wrapping VStack. The `ErrorBanner`
itself paints a red rounded rectangle; the system status-bar items
render in front, but the visual effect is text reading around the
dynamic island ("Network erro... ion and try again.").

**Fix:** drop `.ignoresSafeArea(edges: .top)` from the wrapping VStack
(line 191) and from the "No internet connection" amber banner's
`.padding(.top, 44)` (line 184). Let the banners sit in the safe area
naturally. The 44pt hardcode was for older iPhones without dynamic
islands; safe-area handling does the right thing on every device.

Banner suppression (§ "Cancellation banner suppression" above) means
this surface fires much less often, but it'll still show for legitimate
errors and should look correct when it does.

---

## Backend gaps (separate work — Supabase project, not iOS)

Confirmed in the user's runtime logs from this session. Nothing
fixable in the iOS app; needs migrations + edge-function deploys:

```
SELECT failed (Could not find the table 'public.daily_coaching_reads' in the schema cache)
Edge function 'coaching-daily-read' returned 404: Requested function was not found
Edge function 'get-pace-zones' returned 404: Requested function was not found
```

- **`daily_coaching_reads` table** — referenced by `DailyReadService`
  which feeds `CoachReadView`. Missing schema is why the Coach tab
  shows "Couldn't load today's read."
- **`coaching-daily-read` edge function** — the fallback path the iOS
  takes when the table SELECT misses. Also missing.
- **`get-pace-zones` edge function** — feeds `PaceZonesService`. iOS
  falls back gracefully ("cleared (404: Requested function was not
  found)") so this is not a user-visible blocker, but the data path
  is dead.

The Coach tab error is **not** an iOS bug. The route is correct, the
view renders correctly, the data source is gone.

---

## Investigation findings worth keeping

### Check-in → athlete_state flow
User asked whether check-ins go anywhere; the answer is:

**Write path is real and complete:**
1. CHECK IN button → `VoiceLogViewModel.uploadCheckIn`
   (`Workouts/VoiceLogViewModel.swift:127`) — inserts `training_logs`
   row with `source = "check_in"`, `processing_status = "pending"`.
2. DB trigger fires `process-check-in` edge function via pg_net.
3. `process-check-in/index.ts:238` calls `updateAthleteState(...)` with
   `last_mood`, `last_readiness_score`, `last_check_in_at`,
   `last_updated_by: "process-check-in"`.
4. `athlete-state.ts:391–399` explicitly queries
   `training_logs WHERE source = 'check_in' AND mood IS NOT NULL`
   (limit 5) when rebuilding the full state object, and writes
   `mood_trend` (improving/stable/declining).
5. If extracted mood ∈ `{tired, struggling, injured}`,
   `CoachCheckInManager.trigger(...)` fires the in-app banner with the
   cleaned notes and a CTA into the Coach.

**Read path is the weak link:**
- Trends tab's `TrendsAthleteState` only decodes `acwr` (see
  Outstanding § 4 above).
- Train tab's `coachQuote` and `moodTrend` compute mood-trend
  **locally** from `trainingLogs` (no source filter, so check-ins ARE
  in the pool), parallel to the server-built `athlete_state.mood_trend`.
  Could disagree.
- Coach Read consumption of `athlete_state` is unverified — the daily
  read isn't materialized yet anyway (see Backend gaps above).

---

## Touched files in this session

```
RunningLog/RunningLog/App/DripTabBar.swift                    [new, ~265 lines]
RunningLog/RunningLog/App/RunningLogApp.swift                 [edited]
RunningLog/RunningLog/Services/ErrorReporter.swift            [edited]
RunningLog/RunningLog/Workouts/PaceVolumeSpectrumChart.swift  [edited — partial]
outputs/vscode-handoff-ios-qa-2026-05-22.md                   [new, this file]
```

---

## Conventions reminder (from CLAUDE.md)

- **No em-dashes as empty-state placeholders.** Use the empty-state
  component (eyebrow + plain-prose nudge + optional CTA). Affects #2,
  #4, and any new states you add.
- **Predictions ship with range + confidence, never a single point.**
  The FITNESS card already complies; preserve it through #2.
- **AI advises, never acts.** Hard rule. Niggles surface what was
  said and where, never assess severity.
- **Migrations are append-only.** Any backend work for the gaps above
  ships a new migration file, never edits a deployed one.
- **`current_coach_id()` for coach-scoped RLS** — the SECURITY DEFINER
  helper. Don't use direct subqueries against `coach_profiles`.

# Performance audit — Post Run Drip iOS

**Date:** 2026-08-10 · **Scope:** `RunningLog/` (296 Swift files, ~130k LOC), `supabase/functions/`, `supabase/migrations/`

---

## The short version

The app is slow for one structural reason, expressed in four ways:

> **Every screen fetches its own copy of the whole training history, over the network, at app launch, on the main thread — and nothing is cached.**

There is no local database for reads. Every tab re-downloads `training_logs`. Several of those downloads pull JSON blobs (`external_streams`, `pace_segments`, `parsed_structure`) that are 10–100× bigger than the fields actually displayed. And because all tabs are built at launch instead of when you open them, the Train tab's 7-step load chain fires before you've touched it.

Fixing the top 4 items below should take a cold launch from "several seconds of frozen UI" to under a second, and make tab switching instant. None of them require re-architecting the app.

---

## Findings, ranked by impact

### 🔴 1. `SELECT *` on `training_logs` pulls megabytes of sensor data you never display

**Where:** 11 call sites. The worst is the Log tab — the front door.

| File | Line | What it does |
|---|---|---|
| `Workouts/VoiceLogViewModel.swift` | 467 | `.select()` — 50 rows, all columns |
| `Workouts/WorkoutsView.swift` | 878 | `.select()` |
| `Workouts/HistoryViewModel.swift` | 20 | `.select()` |
| `Workouts/HistoryDetailViewModel.swift` | 396 | `.select()` |
| `Trends/TrendsService.swift` | 123 | `.select()` |
| `Analysis/SignalLabView.swift` | 197 | `.select()` |
| `Shared/ExportService.swift` | 57 | `.select()` |
| `Training/TrainingPlanService.swift` | 331, 396 | `.select()` |
| `Trends/TrendsLegacyTabView.swift` | 452 | `.select()` |
| `Workouts/VoiceLogViewModel.swift` | 715 | `.select()` |

**Why it's slow.** In the Supabase Swift client, `.select()` with no argument means `SELECT *`. The `training_logs` table has three large JSONB columns:

- `external_streams` — per-second GPS / heart-rate / cadence streams (added `20260414100000`). **This can be 500 KB – 2 MB per run.**
- `pace_segments` — per-mile splits
- `parsed_structure` — rep-level workout structure

`TrainingLog` (`Models/TrainingLog.swift:79`) doesn't even *decode* `external_streams`. So the app downloads it, JSONDecoder walks past it, and it's thrown away. At `limit(50)` on the Log tab, that's plausibly **25–100 MB transferred to render a list of dates and mileages**. On cellular that alone is your "massive lag."

Your own code already knows this — `Services/WorkoutSyncService.swift:28` has the comment *"select() pulls every column, including the large `external_streams`"*, and `ExternalStreamAdapter.swift:97` does the right thing with `.select("laps:external_streams->laps")`. The lesson just never got applied everywhere.

**The fix.** Replace every `.select()` on `training_logs` with an explicit column list matching what the decoding struct actually uses. For `VoiceLogViewModel.loadHistory`, that's roughly the same list `TodayLogRow` uses. Define it once:

```swift
// Models/TrainingLog.swift
extension TrainingLog {
    /// Every column `TrainingLog` decodes — and nothing else. Never use
    /// bare `.select()` on training_logs: it drags `external_streams`
    /// (per-second sensor blobs, up to ~2 MB/row) across the wire.
    static let columns = "id, user_id, workout_date, workout_distance_miles, /* …the ~30 you decode… */"
}
```

then `.select(TrainingLog.columns)` everywhere.

**Effort:** ~2 hours. **Expected win: the single largest one available.** Do this first.

---

### 🔴 2. The Train tab loads at app launch, not when you open it

**Where:** `App/RunningLogApp.swift:146–215` + `Training/Analytics/TrainingTabView.swift:144`

All tab views live in a `ZStack` and are hidden with `.opacity` (deliberate — the comment at line 126 explains it prevents refetch storms on tab switching). Reasonable. But it means **`.task` on any tab body fires at launch.**

`TrendsTabView` handles this correctly — it gates on `selectedTab` (line 60):

```swift
.task(id: selectedTab.wrappedValue) {
    if selectedTab.wrappedValue == Self.tabIndex { await service.refresh() }
}
```

`TrainingTabView` does **not**:

```swift
.task {
    if !vm.hasLoaded { await vm.load() }   // ← fires at launch
    await planVM.loadActivePlan()          // ← also at launch, ungated
}
```

**The fix.** Copy the Trends gate:

```swift
private static let tabIndex = 1

.task(id: selectedTab.wrappedValue) {
    guard selectedTab.wrappedValue == Self.tabIndex else { return }
    if !vm.hasLoaded { await vm.load() }
    await planVM.loadActivePlan()
}
```

**Effort:** 10 minutes. **Win: removes an entire 7-step load chain from cold launch.**

---

### 🔴 3. `TrainingAnalyticsViewModel.load()` is 7 network round trips, in series, on the main thread

**Where:** `Training/Analytics/TrainingAnalyticsViewModel.swift:437–484`

```swift
@MainActor              // ← line 358
final class TrainingAnalyticsViewModel {
    func load() async {
        fetched = try await TodayLogRow.fetchRecentThrowing(days: 400)   // 1
        logs = fetched.dedupedByPhysicalWorkout().sorted { … }           //   main-thread CPU
        await KeySessionStore.shared.ingestLoads(forDedupedLogs: logs)   // 2
        await predictor.fetchHistory()                                   // 3
        rpeByLog = await RPERow.fetchRecent(days: 120)                   // 4
        await loadPlanAndGoals(predictor: predictor)                     // 5, 6
        await loadCurrentWeekConditions()                                // 7
    }
}
```

Two problems stacked:

**(a) Serial when it could be parallel.** Steps 3, 4 and 7 don't depend on each other. Total time is currently the *sum* of all seven; it should be roughly the slowest one. `RunningLogApp.swift:231` already uses `async let` correctly for launch — the same pattern applies here.

**(b) `@MainActor` + 400 days of JSONB.** `fetchRecentThrowing(days: 400)` (`App/TodayHomeView.swift:510`) selects `pace_segments` and `parsed_structure` with `limit(1500)`. Because the class is `@MainActor`, **the JSON decode of all of that runs on the main thread**, as does `dedupedByPhysicalWorkout()` (which is O(n·clusters) with a linear `firstIndex` scan per row) and the sort. That's a hard UI freeze, not just a spinner.

**The fix.**

1. Gate the whole thing behind tab selection (finding #2).
2. Parallelise the independent steps:
   ```swift
   async let keySessions: Void = KeySessionStore.shared.ingestLoads(forDedupedLogs: logs)
   async let history: Void   = predictor.fetchHistory()
   async let rpe             = RPERow.fetchRecent(days: 120)
   async let conditions: Void = loadCurrentWeekConditions()
   _ = await (keySessions, history, conditions)
   rpeByLog = await rpe
   ```
3. Move decode + dedup off the main actor. Make `fetchRecentThrowing` `nonisolated` and do the dedup/sort in a detached context, hopping back to `@MainActor` only to assign the result.
4. Drop `parsed_structure` and `pace_segments` from the 400-day fetch and load them per-session on demand — the Train tab's aggregate views (`weekVolumes`, `gridWeeks`, `dayVolumes`) don't read them. Only the histogram does, and only for the scoped window.

**Effort:** half a day. **Win: Train tab from multi-second freeze to sub-second.**

---

### 🟠 4. Cold launch fires ~20 network calls and asks HealthKit for permission twice

**Where:** `App/RunningLogApp.swift:225–261` and `Workouts/VoiceLogView.swift:169–177`

The launch `.task` correctly fans out 8 concurrent operations. But *simultaneously*:

- `VoiceLogView.onAppear` calls `healthKitManager.requestAuthorization()` **again** (the launch task already did, line 246) and fetches 20 more HealthKit workouts
- `VoiceLogView.loadHistory()` runs the `SELECT *` from finding #1
- `VoiceLogView:1381` `.task { await refreshWorkouts() }` fans out to HealthKit + Vital + Strava
- `TodayHomeView` (rendered inside `VoiceLogView`) does its own 7-way fanout including a 90-day `training_logs` fetch (`TodayHomeView.swift:210`)
- `TrainingTabView` runs the 7-step chain from finding #3

Meanwhile `athleteProfileService.fetchProfile()` alone is documented in your own comment as ~1.6–2.6 s.

Two concurrent `requestAuthorization()` calls is also a genuine race, not just waste.

**The fix.**

- Delete the duplicate `requestAuthorization()` + `fetchRecentRunningWorkouts` from `VoiceLogView.onAppear`. The launch task already covers both; read `healthKitManager.recentWorkouts` instead.
- Make `HealthKitManager.requestAuthorization()` idempotent — cache the result in an `actor` so N concurrent callers share one system call.
- Defer `HealthBiometricsSync.shared.sync()` and the HealthKit workout sync until **after** first paint. They write to the database; nothing on screen is waiting for them. Wrap in `Task.detached(priority: .background)` and drop them from the `await` tuple on line 260.

**Effort:** 2 hours. **Win: noticeably faster time-to-first-content.**

---

### 🟠 5. No read cache — every launch is a cold launch

**Where:** app-wide. `SwiftData` is used only in `Services/OfflineQueue.swift`, for *writes*. There is no `URLCache`, no `NSCache`, no persisted read model.

Every time you open the app you stare at "Loading…" (`App/LogView.swift:32`) or "READING YOUR TRAINING" while the network round trips. Your training history from yesterday is unchanged, but it's re-downloaded from scratch.

**The fix — stale-while-revalidate.** This is the highest-value *structural* change, and it's the one that matters most for "developed into a better product":

1. Add a SwiftData `@Model` mirror of `TodayLogRow` (you already have the SwiftData container set up in `OfflineQueue`).
2. On load: read from local store → render immediately → fetch from network in the background → diff → update.
3. Fetch only what changed: `.gte("updated_at", lastSyncedAt)` instead of `.gte("workout_date", cutoff)`.

The screen becomes instant on second launch and the network becomes an enrichment rather than a blocker. This also fixes offline behaviour for free.

**Effort:** 2–3 days. **Do it after 1–4**, but do it before the beta widens.

---

### 🟠 6. `trends-timeline` does ~8 sequential queries inside one edge function

**Where:** `supabase/functions/trends-timeline/index.ts` (584 lines)

The Trends tab is one call to this function, which then runs, mostly in series: `training_logs` (with a retry-fallback on column shape), `workout_features`, `body_mentions`, `athlete_state` (pace zones), quality laps, `daily_biometrics` + `daily_checkins` (these two *are* parallelised, line 227), weather, `fitness_snapshots`. Plus Deno cold-start on the first call of a session.

**The fix.**

- Wrap the independent queries in `Promise.all` — `body_mentions`, `workout_features`, pace zones, biometrics and snapshots have no dependency on each other. Only the laps and weather fetches need `logIds` first.
- The `selectLogs(LOG_COLS_BASE + ", stats_excluded")` → catch → retry without the column (lines 93–96) doubles latency whenever it trips. Detect the schema once at module scope, not per request.
- Consider a materialised view or a nightly-computed `trends_timeline_cache` row. 26 weeks of history changes once a day at most.

**Effort:** half a day for `Promise.all`; the cache is a Phase-2 item.

---

### 🟡 7. Expensive objects allocated inside view bodies

**Where:** 232 `DateFormatter()` and 59 `ISO8601DateFormatter()` allocations across the codebase.

`DateFormatter` initialisation is genuinely expensive (~0.1–1 ms each) — it's the classic iOS performance trap. Allocating one per row, per redraw, is death by a thousand cuts. Worst offenders:

| File | Count |
|---|---|
| `Models/TrainingPlanModels.swift` | 14 |
| `Analysis/FitnessPredictorService.swift` | 12 |
| `App/TodayPlate18.swift` | 11 |
| `Training/Analytics/TrainingAnalyticsViewModel.swift` | 9 |
| `Training/CoachReadCard.swift` | 7 |
| `App/TodayHomeView.swift` | 7 |

Note `TodayLogRow.fetchRecentThrowing` allocates one per call (line 515), and `LogView.weekGroups` allocates one **per week group, on every body evaluation** (`LogView.swift:165`).

**The fix.** One shared file of `static let` formatters:

```swift
enum Fmt {
    static let iso = ISO8601DateFormatter()
    static let yyyyMMdd: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f }()
    static let monthDay: DateFormatter = { … }()
}
```

Then find-and-replace. `DateFormatter` is thread-safe for formatting on iOS 7+, so a shared instance is fine.

**Effort:** 2 hours, mechanical, very low risk.

---

### 🟡 8. `LogView.weekGroups` recomputes on every redraw

**Where:** `App/LogView.swift:151–168`

```swift
private var weekGroups: [LogWeek] {
    let grouped = Dictionary(grouping: rows) { weekStartMonday($0.date) }   // 180 days of rows
    return grouped.keys.sorted(by: >).map { ws in
        …
        return LogWeek(id: ISO8601DateFormatter().string(from: ws), …)      // alloc per week
    }
}
```

A computed property read from `body` runs on **every** body evaluation, not once per data change. With 180 days of rows that's a `Dictionary(grouping:)` + sort + ~26 `ISO8601DateFormatter` allocations per frame during scrolling.

The Train tab already solved this — `TrainingAnalyticsViewModel` has `@ObservationIgnored` memo caches with a `cacheToken` (lines ~400–410), and a comment noting these were *"the main source of Train-tab lag."* The same fix hasn't been applied to Log.

**The fix.** Compute `weekGroups` once in `load()` and store it in `@State`, or move `LogView` to a view model with the same token-cache pattern.

**Effort:** 1 hour. Apply the same audit to other computed properties read from `body`.

---

### 🟡 9. Same data, fetched three different ways

`training_logs` is fetched with three different windows by three surfaces that are all alive at once:

| Surface | Window | File |
|---|---|---|
| `TodayHomeView` | 90 days | `TodayHomeView.swift:210` |
| `LogView` | 180 days | `LogView.swift:78` |
| `TrainingAnalyticsViewModel` | 400 days | `TrainingAnalyticsViewModel.swift:447` |
| `VoiceLogViewModel` | 50 rows, `SELECT *` | `VoiceLogViewModel.swift:465` |
| `SignalService` | separate column list | `SignalService.swift:103` |

The 400-day fetch is a superset of the other two. **One shared `@Observable` store fetching once, with each screen filtering the window it needs, removes three round trips outright.** This falls out naturally from finding #5.

---

### 🟢 10. Smaller items worth queuing

- **`FitnessPredictorService.fetchHistory()`** (`FitnessPredictorService.swift:1506`) — `.select()` on `fitness_snapshots`, `limit(100)`. Narrow the columns.
- **Missing index**: `training_logs (user_id, workout_date DESC)` exists (`20260312200000`), good. But the launch-critical filter is `workout_date >= cutoff` *without* `user_id` in `fetchRecentThrowing` (line 512–517) — RLS supplies the user filter, so the planner may or may not use the composite index. Add `.eq("user_id", …)` explicitly so the index is unambiguously usable.
- **`TrendsService.fetchWorkouts`** (`TrendsService.swift:121`) — `.select()` with `limit(20)`, again dragging `external_streams`.
- **39 edge functions**, several overlapping (`parse-*` ×4). Cold starts compound. Consolidation is already on your list in `CLAUDE.md`.
- **Only 3 uses of `withTaskGroup`** against 68 `async let` — the `async let` usage is good; look for remaining serial `await` chains in `VoiceLogViewModel` (56 awaits), `TrainingPlanService` (37) and `HealthKitManager` (35).

---

## Suggested order of work

### Day 1 — the cheap 80%
1. Gate `TrainingTabView` on tab selection *(10 min, finding #2)*
2. Replace all 11 `training_logs` `.select()` with explicit columns *(2 h, finding #1)*
3. Remove the duplicate HealthKit auth in `VoiceLogView.onAppear` *(15 min, finding #4)*
4. Move `HealthBiometricsSync` + workout sync off the launch critical path *(30 min, finding #4)*

**Expected: cold launch and Log-tab render should improve dramatically. Measure before and after.**

### Week 1 — the structural wins
5. Parallelise `TrainingAnalyticsViewModel.load()` and move decode off `@MainActor` *(half day, #3)*
6. Shared `Fmt` formatter enum, replace all 291 allocations *(2 h, #7)*
7. Cache `LogView.weekGroups` *(1 h, #8)*
8. `Promise.all` in `trends-timeline` *(half day, #6)*

### Phase 2 — before the beta widens
9. SwiftData read cache + stale-while-revalidate + incremental sync *(2–3 days, #5)*
10. One shared training-log store replacing the four separate fetches *(1 day, #9)*
11. Move `external_streams` to its own table or Supabase Storage so `SELECT *` can never be expensive again *(1 day)*

---

## How to verify (do this before you change anything)

You need a baseline, or you won't know what worked.

1. **Xcode Instruments → Time Profiler.** Launch the app, switch tabs. Anything on the main thread over ~16 ms is a dropped frame. This will point straight at findings #3, #7 and #8.
2. **Instruments → Network.** Watch total bytes on cold launch. Finding #1 should cut this by an order of magnitude — that number is your proof.
3. **`os_signpost` around the four load paths** (`loadAll`, `vm.load`, `loadHistory`, `TrendsService.refresh`). Ten lines of code, and it turns "feels slow" into a number you can track per build.
4. **Supabase dashboard → Query Performance.** Sort by total time. Confirm the `training_logs` selects are what you think they are.
5. **Test on a real device on cellular, with a full account.** The simulator on wifi hides every one of these problems — which is probably why they accumulated.

---

## One note on architecture

You mentioned wanting the beta to grow into a better product. The single decision that most affects that here is **finding #5**: the app currently treats the network as the source of truth for the UI. Every screen asks the server, waits, then draws.

The shape that scales is: **local store is the source of truth for the UI; the network syncs into it in the background.** Screens read from the local store and render instantly, always. Sync becomes a separate concern you can make smarter over time (incremental, push-triggered, offline-tolerant) without touching a single view.

That's a bigger change than the quick fixes above, and it isn't urgent this week — but it's worth making before you add more screens, because every new screen built against the current pattern is another one to migrate later.

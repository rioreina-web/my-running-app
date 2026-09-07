# Post Run Drip — Code Audit

**Date:** 6 Aug 2026
**Scope:** 269 Swift files / ~115,000 lines in `RunningLog/` (branch `snapshot/trends-v2-wip-2026-07-31`)
**Method:** static review only — no Xcode in this environment, so nothing was compiled or run. Every item below was traced back to the actual source and re-read before being listed. Items are labelled **Confirmed** (I read the code myself and the defect is unambiguous) or **Likely** (reported by the review pass, consistent with the surrounding code, but worth a quick test before you spend time on it).

**28 real defects.** Style, naming, and "could be cleaner" issues were deliberately excluded.

---

## How to use this

Each item has a file and line number so you (or Claude Code) can jump straight to it. The fastest path: open Claude Code in `my-running-app`, paste one section at a time, and say *"fix this."* Don't paste the whole document at once — fixes land better one at a time, and you can test between them.

Suggested order: **Section 1 first** (these crash the app or lose data), then **Section 2** (wrong numbers shown to the athlete as fact), then the rest.

---

# SECTION 1 — Crashes and data loss

## 1.1 Video player crashes the app every time a video is closed — **Confirmed**

`RunningLog/Shared/VideoPlayerView.swift:156-162`

```swift
playerItem.addObserver(
    PlayerObserver.shared,
    forKeyPath: "playbackLikelyToKeepUp",
    options: [.new],
    context: nil
)
```

There is no `removeObserver` anywhere in the file. `onDisappear` just does `player = nil`, which frees the `AVPlayerItem` while the observer is still attached. iOS treats that as a programmer error and kills the process.

**What the user sees:** Content Library → tap any video → tap ✕ → app quits. Every time. Same crash from "Try Again."

**Fix:** `PlayerObserver.observeValue` is an empty stub — it does nothing. The simplest correct fix is to delete the KVO registration entirely. Also store and remove the two `NotificationCenter` observers at lines 138 and 147; each "Try Again" tap currently leaks another one.

**This is the single highest-value fix in the list.** It is on a main navigation path, it is 100% reproducible, and the fix is a deletion.

---

## 1.2 Workout detail crashes on runs with incomplete sensor data — **Confirmed**

`RunningLog/Health/VitalManager.swift:153-166` and `:229-316`

Two separate spots read parallel sensor arrays without checking they're the same length.

```swift
// :153 — guard checks distance vs time, but not velocity
guard let distances = stream.distance, let times = stream.time,
      distances.count == times.count, distances.count >= 2
else { return [] }

let velocities = stream.velocitySmooth
...
let isMoving = velocities?[i] ?? 1.0 >= stoppedThreshold   // :166 — index out of range
```

```swift
// :316 — heartrate is never length-checked in the guard at :229
let hrSlice = hrs[seg.startIndex...seg.endIndex]
```

**What the user sees:** Their watch drops HR or GPS speed for part of a run (extremely common — cold weather, wet strap, tunnel, a dropped tail on the Strava/Garmin import). They tap that run in the journal → crash. Because `WorkoutSyncService` also calls this path, it can crash during background sync too.

**Fix:** Add `velocities.count == times.count` and `heartrates.count == times.count` to the guards, or use a safe indexed lookup that returns nil past the end.

---

## 1.3 Queued voice memos are lost forever if the app is killed mid-upload — **Confirmed**

`RunningLog/Services/OfflineQueue.swift:161, 187`

```swift
predicate: #Predicate { $0.status != "uploading" && $0.status != "failed" },
...
upload.status = "uploading"
do { try context.save() } catch { ... }
let success = await processUpload(upload)
```

The row is written to disk as `"uploading"` *before* the network call. Nothing ever resets it. `init()` (line 52) does not sweep stale rows.

**What the user sees:** Records a memo on a run with no signal. The app starts uploading when signal returns, then iOS suspends or kills it (backgrounded, memory pressure, or the crash in 1.1 or 1.2). That memo is now permanently invisible — excluded from every future upload attempt, and not even counted in the pending badge. The audio file sits on disk orphaned. The athlete has no idea it's gone.

**Fix:** In `init()` (or at the top of `performDrain`), reset every row with `status == "uploading"` back to `"pending"`.

---

## 1.4 Restoring a backup drops every training log and goal — **Confirmed**

`RunningLog/Shared/RestoreService.swift:68, 71`

```swift
("Restoring training logs...", "training_logs", { try await self.upsertBatch("training_logs", items: backup.trainingLogs) }),
("Restoring goals...",         "user_goals",    { try await self.upsertBatch("user_goals", items: backup.userGoals) }),
```

`TrainingLog` (`Models/TrainingLog.swift:79-129`) has no `userId` property and no `user_id` CodingKey — I verified the full field list. Neither does `UserGoal`. So the upsert payload omits the column. `TrainingPlan`, `Injury` and `FitnessSnapshot` all *do* carry `user_id`, which is why this reads as an oversight rather than a design choice.

**What the user sees:** New phone, or reinstall after a problem. They import their backup. Since the row IDs don't exist on the new account, the upsert becomes an INSERT with `user_id = NULL` → rejected by NOT NULL / RLS. Every run and every voice memo — the entire point of the backup — fails to restore. The UI reports a vague "Some tables failed."

**Fix:** Use a restore-specific insert struct that stamps `user_id = AuthManager.shared.userId` on each row before upserting. **Test this end-to-end before beta** — a backup that doesn't restore is worse than no backup, because people trust it.

---

## 1.5 One athlete's profile leaks to the next person who signs in — **Confirmed**

`RunningLog/Services/AthleteProfileService.swift:200, 263, 273`

```swift
private static let cacheKey = "athlete_profile_cache"
...
UserDefaults.standard.set(data, forKey: Self.cacheKey)
```

The key is global, not per-user. I grepped the sign-out path in `Auth/AuthManager.swift` — nothing clears it. (`OfflineQueueManager.purgeAllForSignOut()` exists precisely to prevent this class of leak for voice memos; the profile cache was missed.)

**What the user sees:** Two people share a device — a demo, a coach showing an athlete, a family iPad. User A signs out, user B signs in and relaunches. `init()` calls `loadFromLocalCache()` and B's profile screen shows A's lifetime mileage, paces, and **injury history**. That data is also injected into B's AI coaching prompts via `profileContextForAI`.

**Fix:** Suffix the cache key with the user id, and clear it in the `.signedOut` branch of the auth listener. This is a privacy issue, not just a bug — health data crossing accounts is the kind of thing that gets an app pulled from review.

---

## 1.6 Several pace calculations can divide by zero and crash — **Confirmed**

`RunningLog/Models/PaceModels.swift:73` is the root:

```swift
func paceSeconds(forRacePace racePaceSeconds: Double) -> Double {
    racePaceSeconds / (percentage / 100.0)
}
```

When `percentage == 0` this returns infinity (or NaN if the race pace is also 0). That value then reaches `formatTime` at `PaceModels.swift:131`:

```swift
let totalSecs = Int(seconds.rounded())
```

**Swift traps on `Int(infinity)` and `Int(NaN)` — it is a hard crash, not a wrong number.**

Three reachable ways in:

- **`Training/WorkoutStepComponents.swift:401`** — the "Custom %" chip in the step editor. Athlete clears the field and types `0` → `racePaceSeconds / 0` → crash on the next render. A saved `custom(0)` then crashes every time that workout is reopened.
- **`Models/WorkoutModels.swift:1221`** — every step the current decoder builds sets `percentage: 0` (lines 435, 441, 957) and relies on `paceSecondsPerKm` instead, but this code path ignores it and divides by the zero percentage. A coach workout with `target_pace: "7:27"` and no `paceZone` produces an infinite duration; `JSONEncoder` also refuses to encode a non-finite Double, so *saving* the workout throws.
- **`Shared/FITExportService.swift:270`** — `UInt32(speedMps * 1000)` with an infinite speed traps on export.

**Fix (do all three):**
1. In `paceSeconds(forRacePace:)`, prefer `paceSecondsPerKm * 1.609344` when it's present, and `guard percentage > 0` before dividing.
2. In `formatTime`, `guard seconds.isFinite` and return a placeholder (`"—:—"`) otherwise. This is the cheap safety net that stops the whole family of crashes.
3. Clamp the Custom % input to a sane range (say 30–200) in the editor.

---

## 1.7 Weather cache is written from multiple threads at once — **Confirmed**

`RunningLog/Shared/WeatherService.swift:151-155`

```swift
class WeatherService {          // plain class, not an actor
    private var cache: [String: WorkoutWeather] = [:]
```

The `fetch*` methods are `async` and non-isolated, so their URLSession continuations resume on different threads and write the dictionary concurrently.

**What the user sees:** A calendar or journal screen renders several rows that each kick off a weather fetch. Swift dictionaries are not thread-safe — concurrent writes corrupt the internal hash table, producing an intermittent `EXC_BAD_ACCESS` crash or silently wrong cached values. Intermittent crashes are the most expensive kind to chase later.

**Fix:** Change `class WeatherService` to `actor WeatherService`. That's usually the whole fix; the compiler will point at the few call sites that need `await`.

---

## 1.8 Voice recorder is never torn down; audio session left active — **Likely**

`RunningLog/Workouts/VoiceLogView.swift:868, 887-889`

There is no `.onDisappear` in the file, no `AVAudioRecorderDelegate`, no interruption observer, and `setActive(false)` is only called on the start-failure path.

**What the user sees:** (a) A phone call or backgrounding mid-memo suspends the recorder while the display timer keeps counting — they save a truncated file stamped with the full duration, and never know. (b) After any memo, the `.playAndRecord` session stays active forever: their music doesn't resume, and later Content Library videos play out of the earpiece instead of the speaker.

**Fix:** Add `.onDisappear { if isRecording { stopRecording() } }`, call `setActive(false, options: .notifyOthersOnDeactivation)` at the end of `stopRecording()`, and observe `AVAudioSession.interruptionNotification`.

---

# SECTION 2 — Wrong numbers shown to the athlete as fact

These don't crash, which makes them more dangerous: the app states them confidently and the athlete trains on them.

## 2.1 Every half marathon in a voice log is read as a full marathon — **Confirmed**

`RunningLog/Analysis/FitnessPredictorService.swift:1822-1823, 1871`

```swift
let distancePatterns: [(String, RaceType)] = [
    ("marathon", .marathon), ("half marathon", .half), ("half", .half),
    ...
]
for (pattern, raceType) in distancePatterns {
    guard notes.contains(pattern) else { continue }
```

`"half marathon"` contains `"marathon"`, which is tested first, and the loop `break`s at line 1920. `.half` is unreachable.

**What the user sees:** They log "Half marathon race today — 1:28:45." The app records a **marathon** at 3:23/mi, which passes the sanity check and becomes the high-confidence fitness anchor. Every pace zone, the Trends fitness range, and the Train tab histogram marker are now anchored to roughly double the athlete's actual fitness. They get prescribed paces they physically cannot hold — the app is now actively unsafe as a coach.

**Fix:** Put `("half marathon", .half)` and `("half", .half)` **before** `("marathon", .marathon)` in the array. One-line change.

---

## 2.2 New athletes are told they're "100% easy — right on the polarised line" — **Confirmed**

`RunningLog/Training/Analytics/TrainingAnalyticsViewModel.swift:797`

```swift
guard let paceSec, paceSec > 0, mpAnchor > 0 else { return .easy }
```

`mpAnchor` is 0 until a fitness snapshot exists.

**What the user sees:** A brand-new athlete opens Train. Every run — including 6×1K — is bucketed as easy. Under a caption reading **"TARGET 80/20"**, the app reports 100% easy / 0% hard, and `headlineInsight()` prints "…100% easy — right on the polarised line." It's fabricated. Sibling code (`zoneGuideline`, `paceZoneBands()`) degrades honestly by returning nil/empty — this path should too.

**Fix:** Return an optional bucket and hide the easy/hard section and `easyPercent` entirely when `mpAnchor == 0`.

---

## 2.3 Fitness assessment gets paces in minutes but reads them as seconds — **Confirmed**

`RunningLog/Analysis/WorkoutHistoryAnalyzer.swift:133, 138, 147-150`

The code itself proves the mismatch — line 143 multiplies by 60 to get seconds, then line 148 stores the unconverted value:

```swift
let fi = estimateFitnessIndex(paceSecondsPerMile: avgWorkoutPace * 60)  // knows it's minutes
return WorkoutHistoryAnalysis.PaceProgression(
    averageEasyPace: avgEasyPace,        // stored raw — field is documented as seconds
    averageWorkoutPace: avgWorkoutPace,
```

The no-data fallback at lines 120-123 returns `540 / 480 / 510` — clearly seconds. So the same field is minutes with data and seconds without.

**What the user sees:** An 8:00/mi runner produces `averageEasyPace = 8.0`. The same runner with no HealthKit data produces `540`. Both are sent to the AI assessment as `"averageEasyPace"`, so the model reasons about "8 seconds per mile" and its output is nonsense.

**Fix:** Multiply the three computed values by 60 at construction.

---

## 2.4 "Load split · 28 days" counts future days as rest — **Likely**

`RunningLog/Analysis/TrainingAnalysisView.swift:779-790, 883-894`

The 28-day window ends on Sunday of the *current* week; days with no logs classify as `.rest`.

**What the user sees:** On a Monday, six future days count as rest. A block that was 9 quality / 13 easy / 6 rest reports 43% rest instead of 21%, and the quality share is correspondingly deflated. The number drifts every single day for identical training, which quietly destroys trust in the whole screen.

**Fix:** Skip cells where `date > startOfDay(now)` in `computeSplit()`. The grid already tracks `isFuture` at line 455.

---

## 2.5 Pace-volume chart y-axis labels don't match the bars — **Likely**

`RunningLog/Training/TrainingPaceAnalysisSection.swift:269, 334, 363-375`

Bars scale to `maxMiles`; labels are computed from a rounded-up `top`. They're also drawn at different heights (gridlines at 0/25/50/75/100%, labels at 0/33/66/100%).

**What the user sees:** A 12-mile peak week fills the plot to 100% but sits against a gridline labelled "25 mi" — a 2× misread of their own training volume.

**Fix:** Scale bars to `top` rather than `maxMiles`, and compute intermediate stops as Doubles before rounding for display.

---

## 2.6 Rest-day check-ins are silently discarded — **Likely**

`RunningLog/App/LogDedup.swift:59-60`, used at `TrainingAnalyticsViewModel.swift:454`

```swift
let m = log.miles ?? 0
guard m > 0 else { continue }   // row never enters a cluster, never comes back out
```

**What the user sees:** A rest-day memo ("legs are trashed") is fetched and then dropped by dedup. The "Voice memos" stat undercounts — five memos can read as two — and `mood(on:)` can never surface a non-running day, even though the code comment at lines 531-536 says it's supposed to.

**Fix:** Pass mileage-less rows through dedup untouched — they can't double-count miles by definition.

---

## 2.7 Backup comparison window exceeds the data that was fetched — **Likely**

`RunningLog/Analysis/TrainingAnalysisView.swift:899-902`

The comment says "400-day window so TrainingPaceAnalysisSection has the history it needs (12-month range with comparison = ~24 months)." 400 days is ~13.1 months, not 24.

**What the user sees:** Athlete picks Monthly + 12m (comparison defaults on). The prior period has zero data, so the panel reads "820 mi · **prior 0 mi**" and every delta chip renders ▼ — a fabricated collapse.

**Fix:** Fetch `days: 760`, or disable the compare toggle when the loaded history doesn't cover the prior window.

---

## 2.8 Weather shown on a run is today's weather, not the run's — **Likely**

`RunningLog/Shared/WeatherService.swift:177`

For workouts within 5 days, `fetchRecentWeather` hits the `&current=` endpoint and reads `response.current`. The `date` argument is only used for the cache key.

**What the user sees:** They open Tuesday's 6 a.m. tempo on Thursday afternoon and see 78°F sunny attributed to a run done at 48°F in rain. The wrong value is then cached under the workout's key, so it sticks.

**Fix:** Use the forecast endpoint's `hourly` array with `start_date`/`end_date` — `fetchForecast` in the same file already does this correctly.

---

## 2.9 Goal race date lands a day off — **Likely**

`RunningLog/Shared/GoalsView.swift:489-490, 696-697`

`ISO8601DateFormatter` formats in UTC, but `targetDate` carries a wall-clock time.

**What the user sees:** An athlete in Los Angeles sets a goal at 6 p.m. for April 27 → stored as `"2026-04-28"`. Race-day countdown, taper math, and race lookup are all one day off.

**Fix:** `formatter.timeZone = .current`, or normalize with `Calendar.current.startOfDay(for:)` before formatting.

---

## 2.10 Date formatters missing POSIX locale — **Likely**

`Health/HealthKitManager.swift:239`, `Health/VitalManager.swift:32, 68`, `Shared/WeatherService.swift:233, 282`

```swift
let formatter = DateFormatter()
formatter.dateFormat = "yyyy-MM-dd"     // no locale set
```

Without `formatter.locale = Locale(identifier: "en_US_POSIX")`, `yyyy` resolves in the *user's* calendar.

**What the user sees:** A user whose region uses the Japanese or Buddhist calendar gets `"0008-05-12"` or `"2569-05-12"`. Those go straight into API URLs (no stream, no weather, ever) and into dictionary keys that callers then fail to match (every mileage chart reads empty). The codebase already does this correctly at `TrainingPlanModels.swift:14` and `DailyReadService.swift:289`, so it's just inconsistency.

**Fix:** Add the POSIX locale line to all five. Trivial, and it prevents a bug class you'd never reproduce yourself.

---

## 2.11 Assorted smaller math errors — **Likely**

| Where | What's wrong | Effect |
|---|---|---|
| `TrainingAnalyticsViewModel.swift:1448-1454` | Divides by point count, not weeks elapsed | "▼ 19 SEC / **1 WK**" for an 11-week improvement |
| `WorkoutHistoryAnalyzer.swift:89-96` | Averages only weeks that have data; zero weeks are missing keys, not zeros | 40 mi in one week + 3 blank weeks → base of 40 mpw instead of 10. Feeds `calculateRecommendedMileage` — a real injury risk |
| `TrainingAnalyticsViewModel.swift:937-946` | Returns partial windows; comment says it shouldn't | A line legended "4-WK AVG" plots 1-, 2- and 3-week averages |
| `TrainingTabView.swift:1004-1006` | Uses `Calendar.current` (Sunday start) where the rest of the tab uses ISO Monday | On Sunday, "this week's plan" shows next week |
| `Analysis/InjuryService.swift:101-105` | Buckets runs by UTC day, mentions by local day | Every evening run west of UTC is off by one; AVG VOL renders "—" |
| `Models/RaceDistance.swift:46` | `mile1500` returns `1.0` mi; `PaceModels.swift:412` uses `0.932` | Every pace anchored to a 1500m goal is ~7% off |
| `Analysis/TrainingAnalysisView.swift:396` | Passes 400 days of logs to a view documented as taking 28 | "7th-longest run of the block" for what is actually the block's longest |

---

# SECTION 3 — Broken or misleading states

## 3.1 A successful plan join reports failure and invites a duplicate — **Confirmed**

`RunningLog/Coaching/CoachViewModel.swift:495, 518`

```swift
return self.error == nil
```

I grepped the whole file: `self.error` is assigned in 20+ places and **never** reset to nil.

**What the user sees:** Athlete's first join-code lookup fails on a flaky connection. They retry, it works, they tap Join. The subscription succeeds and creates the plan — but the stale error makes the function return `false`, so the UI says *"Failed to subscribe. Try again."* They tap again and get a **second training plan with a duplicate set of scheduled workouts.** That's data corruption they then have to untangle by hand.

**Fix:** Set `self.error = nil` at the top of `subscribeAthleteToTemplate`, `lookupPlanByCode`, `joinPlanByCode` and `joinLoadedPlan`.

---

## 3.2 Failed video load shows a black screen with no way out — **Likely**

`RunningLog/Shared/VideoPlayerView.swift:170-176`

`isBuffering` is cleared by a fixed 500 ms sleep. Nothing observes `playerItem.status == .failed`, and `AVPlayerItemFailedToPlayToEndTime` is not posted for an asset that never loads.

**What the user sees:** Bad connection or an expired storage URL → spinner for exactly half a second, then a black frame with a title. No error, no retry (the retry button lives inside `errorView`, which needs `error != nil`). Their only exit is ✕ — which triggers the crash in 1.1.

**Fix:** Observe `playerItem.status`, set `error` on `.failed` and clear `isBuffering` on `.readyToPlay`, instead of the sleep.

---

## 3.3 Content Library errors look like empty categories — **Likely**

`RunningLog/ContentLibrary/ContentLibraryView.swift:151-155`

`fetchVideos` swallows the throw and returns `[]`; the view branches on `videos.isEmpty` straight to the empty state.

**What the user sees:** Offline, they tap "Mobility" and read *"No Videos Yet — check back soon."* They conclude the category is empty and stop opening it. No retry, no pull-to-refresh.

**Fix:** Distinguish the error case and render an error state with a Retry button.

---

## 3.4 Weather/heat adjustment always fails the first time — **Likely**

`RunningLog/Workouts/PaceChartViewModel.swift:466-486, 645-651`

```swift
manager.requestWhenInUseAuthorization()
if authorizationStatus == .authorizedWhenInUse || ... { manager.startUpdatingLocation() }
```

`requestWhenInUseAuthorization()` is asynchronous — on first use the status is still `.notDetermined`, so location never starts. The caller waits 2 seconds, gets nil, and returns **without setting `weatherError`**. When permission is later granted, nothing re-runs the fetch.

**What the user sees:** They flip on Weather Adjustment, tap Get Weather, tap Allow. Spinner for 2 s, button comes back, no message, no explanation. If they'd tapped *Don't Allow*, it behaves identically forever — no reason given, no Settings link.

**Fix:** Make `LocationManager` expose a one-shot `async` location backed by a continuation resumed from the delegate callbacks, and set `weatherError` with a Settings CTA on `.denied`.

---

## 3.5 The goal typed during onboarding is silently thrown away — **Likely**

`RunningLog/App/OnboardingView.swift:515-529`

```swift
let userId = AuthManager.shared.userId
guard !userId.isEmpty else { return }
_ = try? await supabase.from("user_goals").insert([...]).execute()
```

**What the user sees:** A brand-new user types their goal race time on the last onboarding step. Auth hasn't resolved yet, so `userId` is empty, the guard returns, and the goal is gone. Same for an RLS rejection or being offline — both eaten by `try?`. They land in the app with no goal and no error, and pace zones fall back to defaults. This is the very first thing a new user does, so it shapes their whole first impression.

**Fix:** Wait briefly for the session the way `VoiceLogViewModel.loadHistory:446-452` already does, and hand the goal to `OfflineQueueManager` on failure rather than dropping it.

---

# SECTION 4 — Correctness and hygiene

## 4.1 Every exported .FIT file is invalid — **Confirmed**

`RunningLog/Shared/FITExportService.swift:74-81`

```swift
let crc = calculateCRC(data)          // computed while header size is still 0x00000000
data.append(UInt8(crc & 0xFF))
data.append(UInt8((crc >> 8) & 0xFF))

let dataSize = UInt32(data.count - 14)  // now includes the 2 CRC bytes it shouldn't
data.replaceSubrange(4 ..< 8, with: ...)
```

Two errors: the CRC covers a placeholder size that's patched afterwards, and the size field overstates the record section by 2.

**What the user sees:** Export a workout, drag it into Garmin Connect, rejected as corrupt. 100% of the time.

**Fix:** Patch the header size **first** (using the pre-CRC `data.count - 14`), then compute and append the CRC.

---

## 4.2 Journal state is mutated off the main thread — **Confirmed**

`RunningLog/Workouts/VoiceLogViewModel.swift:439`

`VoiceLogViewModel` is `@Observable` with no class-level `@MainActor`. Every other mutating method carries `@MainActor` (lines 66, 216, 299, 405, 506) — `loadHistory` at line 439 is the one that doesn't. So its six property writes and the SwiftUI invalidations they trigger happen on a background thread.

**What the user sees:** Intermittent layout corruption and hard-to-reproduce AttributeGraph crashes in the Log feed — worst during the 1-second processing poll while scrolling. These are the crashes that eat weeks of debugging later.

**Fix:** Add `@MainActor` to `func loadHistory()`. One line.

---

## 4.3 Vital API key ships in the app, pointed at sandbox — **Confirmed**

`RunningLog/Health/VitalManager.swift:18-19`

```swift
private let baseURL = "https://api.sandbox.us.junction.com/v2"
private let apiKey: String = Bundle.main.infoDictionary?["VITAL_API_KEY"] as? String ?? ""
```

Two problems. The base URL is hardcoded to **sandbox** with no release override — a production build queries sandbox and never returns real workouts. And a Vital/Junction key is a server-side credential: anything in `Info.plist` is readable by anyone who unzips the `.ipa`.

**Fix:** Switch the URL on build configuration, and route Vital calls through a Supabase edge function so the key never ships. **Do this before TestFlight** — once a key is in a distributed build you have to rotate it.

---

## 4.4 Sync can run with an empty user id — **Likely**

`RunningLog/Services/WorkoutSyncService.swift:19` and `Services/AIInsightsService.swift:81`

`AuthManager.userId` returns `""` when there's no session, with only a `print` warning, and neither call site guards.

**What the user sees:** Auto-sync fires at launch before the auth listener emits → the query runs `.eq("user_id", "")`, the insert goes out with `user_id: ""`, RLS rejects, and a red error banner greets them on cold launch. `removeAutoSyncEntry` in the same file already does it right with `guard let userId = AuthManager.shared.currentUserId`.

**Fix:** Copy that guard to both call sites.

---

## 4.5 Duplicate racing HealthKit setup at launch — **Likely**

`RunningLog/App/RunningLogApp.swift:218-226` and `Workouts/VoiceLogView.swift:169-176`

Both run `requestAuthorization()` + a workout fetch against `HealthKitManager.shared` concurrently at launch, and both write `recentWorkouts`. Whichever lands last wins, so the picker non-deterministically holds 20 or 30 runs. On first install, two permission requests are in flight against one `HKHealthStore`.

**Fix:** Delete the HealthKit half of `VoiceLogView.onAppear`; let the app-level `.task` own it.

---

## 4.6 Per-page HealthKit managers in the journal pager — **Likely**

`RunningLog/Workouts/HistoryDetailSheet.swift:18, 216-224`

```swift
@StateObject var healthKitManager = HealthKitManager()
```

This is the exact pattern already fixed in `VoiceLogView.swift:36`, whose comment reads: *"A fresh HealthKitManager() here had its own isAuthorized/readState that diverged from the instance the app actually syncs with."* The sheet is instantiated per page inside a `LazyHStack` `ForEach`.

**What the user sees:** Swiping through a week of journal entries allocates a fresh `HKHealthStore` and fires an authorization request + 20-workout query *per page*. The linked-workout picker also shows empty until its own query lands, even though the shared manager already has the data.

**Fix:** Use `@ObservedObject private var healthKitManager = HealthKitManager.shared`.

---

## 4.7 Unstable `Identifiable` id — **Confirmed**

`RunningLog/Models/TrainingLog.swift:8`

```swift
var id: UUID { UUID() }
```

A brand-new UUID on every single access. Any `ForEach` over `PaceSegment` treats every element as new on every render — animations restart, selection clears, scroll position jumps, and SwiftUI can be driven into repeated rebuild cycles.

**Fix:** Derive the id from the segment's content (it already round-trips through the DB) or store a real one.

---

## 4.8 Retry loop can run without bound — **Likely**

`RunningLog/Workouts/VoiceLogViewModel.swift:777-796`, closed at `:494`

`autoRetryStaleRecords` → `loadHistory` → `autoRetryStaleRecords`. If a memo is stuck at `"transcribed"` and the edge function short-circuits with `success: true` without changing the status, each retry returns true → reload → still stale → retry.

**What the user sees:** Battery and cellular data drain silently for as long as the Log tab is open, with a 60-second edge-function call on every hop.

**Fix:** Pass a set of already-attempted log ids (or a depth counter) into `autoRetryStaleRecords` and only recurse when the status actually changed.

---

## 4.9 Heavy recomputation inside SwiftUI `body` — **Likely**

`Analysis/TrainingAnalysisView.swift:415, 572, 872, 884` and `Training/TrainingPaceAnalysisSection.swift:123-127, 671`

`computeCalendarCells()` runs three times per `body` evaluation, each filtering ~1,500 log rows across 28 days plus a per-day dedup. `computePeriods` runs twice per render, re-deduping all rows each time.

**What the user sees:** Tapping a calendar cell or changing a range re-runs roughly 100,000 date comparisons plus two full dedups synchronously on the main thread. Visible stutter now; unusable on an older phone with two years of data.

**Fix:** Cache against a `(logs, scope)` token — `TrainingAnalyticsViewModel` at lines 404-407 already shows the pattern.

---

# Recommended order

**Before anyone else touches the app (a day's work, mostly one-liners):**

1. **1.1** delete the KVO — stops a guaranteed crash
2. **2.1** reorder two array entries — stops the app coaching people off a doubled fitness estimate
3. **1.6 step 2** add `guard seconds.isFinite` to `formatTime` — one line, kills a whole crash family
4. **4.2** add `@MainActor` to `loadHistory` — one line
5. **1.2** add two length checks to the guards
6. **1.3** reset stale `"uploading"` rows on init
7. **4.3** move the Vital key server-side — do it before any build leaves your machine

**Before beta testers:** 1.4 (backup restore — verify end-to-end), 1.5 (profile leak), 1.7 (weather actor), 3.1 (duplicate plan), 2.2 (fabricated 80/20), 2.3 (minutes/seconds), 1.8 (recorder teardown), 3.5 (onboarding goal).

**Everything else** can follow in normal development.

---

# Two structural notes

**A pattern worth noticing.** Several of these are cases where the codebase already solved the problem in one place and the fix didn't propagate: the POSIX locale (2.10) is right in two files and missing in five; the shared HealthKit manager (4.6) was fixed in `VoiceLogView` with a comment explaining why, then reintroduced in `HistoryDetailSheet`; the `userId` guard (4.4) is correct in `removeAutoSyncEntry` and absent two functions away. When you fix one of these, it's worth grepping for the same pattern elsewhere in the same sitting — you'll usually find two or three more.

**Not compiled.** No Xcode was available here, so this is reading, not building. Before you start fixing, open the project in Xcode and do a clean build — a compile error or a batch of warnings would be worth knowing about, and they'd show up in seconds.

*Audit performed 6 Aug 2026 against `snapshot/trends-v2-wip-2026-07-31` @ 5a88012.*

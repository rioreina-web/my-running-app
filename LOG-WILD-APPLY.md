# LOG · WILD — the redesigned Log tab, applied

**Applied:** 2026-08-21 · directly to the working tree on `design/wild-v2`
**Scope:** five new files, three existing files edited, thirteen fonts bundled.
**NOT COMPILED HERE** — this container has no Xcode and no Swift toolchain.
Nothing below has been type-checked. Build before trusting it. Verify steps in §6.
**Prototype:** `log-redesign-editorial-prototype.html`
**Design sources:** `Voice Log · canonical` (front door), `Log Feed · 032c` (journal),
`POSTRUNDRIPSYSTEM.md` (tokens), `REDESIGN-SAFELY.md` §5 (the two-skin architecture).

---

## 1 · What changed

| File | Change |
|---|---|
| `App/DripTheme.swift` | **New.** The skin switch, the Direction I palette, the six type roles, and three primitives (`WildRule`, `WildLabel`, `WildRecordButton`). |
| `Workouts/VoiceRecorder.swift` | **New.** `VoiceLogView`'s private recording code, lifted so two screens can share it. |
| `Workouts/LogWildView.swift` | **New.** The Log tab, Direction I. Front door + journal in one scroll. |
| `Workouts/CheckInView.swift` | **New.** Check-in as its own surface, opened from ☰. |
| `Training/JournalWildRow.swift` | **New.** One journal entry, 032c retyped. Plus the processing/failed row. |
| `App/RunningLogApp.swift` | Tab 0 picks its screen by skin. `AppDestination.checkIn` added. `CoachCheckInManager` injected into the menu's cover (see §4). |
| `ContentLibrary/ContentLibrarySidebar.swift` | `Check In` menu entry (06; Library and Settings renumbered 07/08). Skin toggle in the footer. |
| `Info.plist` | Thirteen fonts added to `UIAppFonts`. |
| `Fonts/` | Instrument Sans (4), Schibsted Grotesk (3), Inter (3), JetBrains Mono (3). |

**No Xcode step needed.** The project uses `PBXFileSystemSynchronizedRootGroup`
(objectVersion 77), so files are compiled by virtue of sitting in the folder.
The fonts DO need the `Info.plist` entry, which is already made.

**`VoiceLogView.swift` is untouched.** It still serves the editorial skin, and
it still has its own copy of the recording code. That duplication is deliberate:
rewiring the working screen to prove a point would put the old app at risk for
no gain. When the wild skin wins, that file goes and takes its copy with it.

---

## 2 · The architecture, and what is deliberately NOT global

`REDESIGN-SAFELY.md` §5 describes making `DripColors` a struct with `.editorial`
and `.wild` instances, then flipping `static let drip = DripColors()` to a
computed `static var`. **That is not what this change does**, because the scope
here is the Log tab only.

Instead the wild tokens live in their own namespace:

```swift
Color.drip.coral       // editorial — all 5,959 callsites, untouched
Color.wild.red         // Direction I — read only by the new Log screen
.dripDisplay(28)       // Crimson Pro, everywhere else
.wildDisplay(46)       // Instrument Sans, the new Log screen
```

So the other five tabs render **byte-identically** to before. The switch exists,
the palette exists, and going global later is still the one-line change the doc
describes — you just haven't spent it yet.

### The switch

`DripSkinStore.shared.skin` — `.editorial` (default) or `.wild`, persisted to
`UserDefaults` under `dripSkin`. Flip it in **☰ → the footer**, where the build
string is. It re-renders live; no relaunch.

`@AppStorage` is deliberately not used. It is a `DynamicProperty` built for a
View's own storage; as a `static var` on a type it reads and writes fine but
never publishes a change, so the switch would only take effect on relaunch.
`@Observable` + an explicit `UserDefaults` write is the pattern `KeySessionStore`
already uses in this codebase.

---

## 3 · The design decisions that are encoded in the code

**The record button floats, it isn't padded into place.** The front door is one
page sized to the scroll viewport (`frame(minHeight: geo.size.height)`), and the
record block inside it is `maxHeight: .infinity` with its contents centred. The
button therefore sits in the middle of whatever room is left after the lede and
the linked-run block. This is the single detail that makes the screen read as
composed rather than assembled, and it is the one thing that cannot be tuned into
place with padding — which is what the first three drafts were doing.

**The 2pt leading rule is the mood, and only the mood.** `CLAUDE.md` is explicit
and 032c is where the rule comes from. The mood word at the foot of the entry
repeats it in the same colour.

**Italic mono is the athlete, roman mono is the machine.** A transcribed memo is
set in italic JetBrains Mono because it is speech; a note the athlete typed is set
in Crimson because they wrote it. `JournalWildRow` branches on
`entry.audioUrl != nil`. No badge, no icon, no colour does that work.

**The key-session star is `--session` blue, not red.** 032c stars it red; the
locked system gives that job to blue and reserves red for alerts and brand
punctuation, and a red star would put two reds in one row beside `▶ VOICE`.
One line in `JournalWildRow.header` if you want it back.

**Mono survived on three things** — the run meta, the date chips, and
`TAP TO RECORD` — because that is what the canonical screen does. It contradicts
§1 of the design system, which reserves mono for transcripts and machine answers.
That contradiction is now in the code as well as the reference. Worth settling.

---

## 4 · The bug this change had to fix on the way past

`AppDestination` is presented by a `fullScreenCover` hanging off the **outer**
`ZStack` in `MainTabView`. `CoachCheckInManager` is injected on the **inner**
TabView. The cover is therefore not a descendant of that injection, so
`CheckInView`'s `@Environment(CoachCheckInManager.self)` would have found nothing
and trapped at runtime the first time anyone opened ☰ → Check In.

This is the same trap the comment at `RunningLogApp.swift:412` already documents
for `AthleteProfileService`. One line added beside it:

```swift
.environment(checkInManager)
```

If you add another menu destination that reads an `@Environment` object, check
this list first.

---

## 5 · Check-in moved, and why

The wild skin drops the `LOG RUN / CHECK IN` control from the Log screen, which
would have left the mode unreachable. It is now ☰ → **Check In**, its own screen.

That is arguably where it belonged. A check-in is not a way of logging a run —
it is the opposite of one — and a permanent band at the top of the record screen
charged every athlete, every day, for something used occasionally.

It writes through `VoiceLogViewModel.uploadCheckIn`, the same call the editorial
mode uses, so entries land identically and appear in both feeds with
`source == "check_in"`. There is no confirmation sheet: a check-in has no run to
link and no distance to correct, so a "keep this?" step would exist only to exist.

---

## 6 · Verify

Build first. Then, on device or simulator:

**The switch**
1. Open ☰. The footer shows `SKIN · EDITORIAL` above the build string.
2. Tap it → `SKIN · WILD`. Close the menu. Tab 0 is the new screen.
3. Tabs 1–5 look exactly as they did. If anything else changed appearance,
   something leaked out of the `wild` namespace — that is a bug, not a feature.

**The fonts** — the failure mode is silent. `.custom(_:size:)` falls back to San
Francisco when a PostScript name doesn't match, so a wrong name renders a
plausible-looking screen in the wrong typeface.
4. "Log your run." must be **Instrument Sans Bold** — a tight grotesk, flat-sided
   `g`, noticeably narrower than SF. If it looks like the rest of iOS, the name
   didn't resolve.
5. The tracked labels (`LINKED TO`, `TAP TO RECORD`) must be Schibsted Grotesk —
   wider than the headline face. That width contrast is the whole point of the
   pairing; if both look the same, one didn't load.
6. A voice entry's quote must be **italic monospace**. A typed note must be
   Crimson. Two entries of different kinds side by side is the fastest check.

**The screen**
7. Record → the headline is replaced by a running clock in Inter tabular; the
   button's dot becomes a square; the ring breathes. Stop → the confirmation
   sheet. Confirm → the entry appears at the top of the journal.
8. Deny the microphone in Settings, then tap record → the alert appears and no
   timer runs. (The `record()` return value is checked, so the timer never runs
   over dead air.)
9. `Type a note instead` → composer opens, Crimson placeholder, SAVE goes red
   once there is text, saving clears it and closes.
10. `All runs ↗` scrolls to the journal. Chips filter. The magnifier reveals
    search. Long-press an entry → the key-session menu, and the star agrees with
    the calendar.
11. ☰ → Check In → record → it lands in the journal as a check-in, filterable
    under `CHECK-INS`.

**The empty and broken states** — these are the ones that get shipped wrong:
12. Airplane mode with a cold cache → "Couldn't load your journal. Your entries
    are safe" and a Retry. It must never say "no entries yet" on a load failure.
13. A failed transcription row reads `Couldn't transcribe` with Retry, and never
    implies the audio is gone.

---

## 6b · One pre-existing build error fixed on the way

The first build after this change failed on a file I did not write:

```
App/JournalPages.swift:364:48
'editorialDateString' is inaccessible due to 'fileprivate' protection level
```

Not caused by this change. `JournalPages.swift` arrived in the checkpoint commit
`16b123a` and calls `Date.editorialDateString`, which is declared inside a
`private extension Date` in `Workouts/HistoryDetailSheet+Editorial.swift` — so it
was never visible from that file. **That file has never compiled since it was
added.** This change is simply the first build since.

Fixed by adding a local helper at the top of `JournalPages.swift`, which is what
the neighbouring file's own note prescribes: the shared `Date.shortDateString`
returns "May 21, 9:06 AM" and is used elsewhere, so *"Don't change it — add local
helpers instead."* The local copy caches its `DateFormatter` in a file-level
`let` rather than allocating one per call, since it is read from inside a view
body.

I also swept the whole tree for other private extension members used across file
boundaries. `editorialDateString` was the only real one — every other candidate
(`clamped`, `bucket`, `downsample`, `paceBounds`, `rounded`, `value`, `x`, `y`)
either resolves to a stdlib member or has its own declaration in the using file.

## 6c · Round two of the build

**`JournalPager.swift:344` — `'error' is not available due to missing import of
defining module 'os'`.** Pre-existing, same checkpoint commit as §6b. The file
calls `Log.coach.error(...)`, and `Log.coach` is an `os.Logger`. This project
builds with `SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES`, which means
a member is only visible if the file using it imports the defining module
directly — importing whatever file *declares* `Log` is not enough. Fixed with
`import os`. I swept every file that calls `Log.<category>.<level>(…)`; this was
the only one missing it.

**`VoiceRecorder.swift:104` — `Reference to captured var 'self' in
concurrently-executing code`.** Mine. The timer tick was written as
`Task { @MainActor in self?.duration += 1 }` inside a `[weak self]` block, which
captures `self` across an isolation boundary.

`VoiceRecorder` is now `@MainActor`, which fixes it three ways at once: the
timer already fires on the main run loop, `duration` is read from a view body
every tick, and a global-actor-isolated class is implicitly `Sendable` — which
is what permits the capture at all. The tick became
`MainActor.assumeIsolated { self?.duration += 1 }`, with no `Task` hop, so a
tick can no longer land a frame late. The permission branch lost its hand-written
`await MainActor.run` for the same reason: a `Task` created in a MainActor method
already inherits that isolation.

`clock(_:)` is marked `nonisolated` — it is pure arithmetic, and a static member
of a `@MainActor` class would otherwise inherit isolation it has no use for.

The shape matches `TrainingAnalyticsViewModel` and `FitnessAssessmentViewModel`,
which are already `@MainActor @Observable` and already instantiated as
`@State private var vm = …` in a view.

Note the language mode is `SWIFT_VERSION = 5.0`, so strict-concurrency
diagnostics arrive as warnings-about-Swift-6 rather than hard errors. Worth
fixing them as they appear anyway — they are the migration bill, and it only
grows.

## 6d · The lag, and the note that looked like it did nothing

**The lag.** `weekGroups` was a computed property read from `body`, so every
body evaluation re-ran a filter over the whole history, a
`Dictionary(grouping:)`, a sort, and the weekly mileage dedup — while
scrolling. `LogView.swift` carries a comment warning about exactly this, and I
copied the shape from `VoiceLogView` instead of the lesson from `LogView`.

Three fixes:

1. **`weekGroups` is stored `@State`**, rebuilt only when something changes it:
   a load, a filter change, a new entry, an edit in the detail pager. Never from
   `body`.
2. **The mileage dedup was O(n²)** — it rescanned the whole array for every
   voice log to find a same-day GPS run. It now indexes the GPS rows by day in
   one pass. Same answer; over 180 days of rows, a different amount of work.
3. **Every `DateFormatter` is now file-level**, built once for the life of the
   process. There were seven being constructed per call — two of them inside
   `JournalWildRow`, so they ran per row, per render, while scrolling.

**Saving a note looked like nothing happened.** It was working the whole time —
`saveManualNotes` writes the row, reloads the journal, and sets "Notes saved!" —
but the new note lands in the feed below the fold, so there was nothing to see.
Saving now scrolls to the journal, where the note is at the top. Seeing the
entry is the receipt; it beats a toast that says it worked.

**And "Type a note instead" was opening off-screen.** The composer was rendered
below `frontDoor`, which is a full screenful, so the button appeared to do
nothing. Writing a note and recording one are the same act with a different
instrument, so they now share a slot: tapping the link replaces the record
button in place, with `Record instead ↗` to go back. There is a keyboard
`Done` too.

## 6e · The run picker

`WorkoutPickerSheet` is presented BY the Log screen but declared in
`VoiceLogView.swift`, so it was still fully editorial under the wild skin —
rounded cards, capsule source pills, a green accent, SF Pro. New file,
`Workouts/WildWorkoutPickerSheet.swift`; the editorial one is untouched and
still serves the editorial skin.

Re-laid on the system: hairlines instead of cards, the distance as the figure
(same treatment as the Log screen's linked block, so the two surfaces rhyme),
the source as a tracked label rather than a grey pill, and selection marked
with the same ink badge the front door uses for LATEST — one selection idea
across both surfaces instead of a checkmark here and a badge there.

**The fetch is NOT duplicated.** `fetchStravaRunningWorkouts` carries a warning
worth repeating: its source list is the only way a synced run reaches this
picker, and this picker is the only way the view model learns a run's
`vital_workout_id` — which is what its attach-to-existing-row branch keys on.
Omit a source there and every memo for that source silently becomes a NEW
duplicate `training_logs` row. So the wild sheet calls that method. The single
change to `VoiceLogView.swift` in this whole piece of work is one keyword:
`private static func` → `static func`.

### A finding worth acting on separately

The old sheet drew its checkmarks, its Done button and its spinner in
`Color.drip.energized`. That token is a **mood** — deep green, "how the athlete
felt" — being used as interface chrome. Under Direction I that is not
available: accents are the one red, and moods never dress the UI.

It is not one sheet. `Color.drip.energized` appears **92 times outside any mood
context** across the app — as "good", as "improving", as "positive delta", as a
generic success colour. That is a semantic collision, not a palette problem:
when green means both *the athlete felt strong* and *this number went up*, a
green dot stops carrying either meaning reliably.

Worth a pass of its own, and worth doing before the global palette swap rather
than after — a rename with 92 call sites is mechanical today and a merge
conflict later.

## 7 · Known gaps

- **Dynamic Type.** Every size here is a literal point size, matching the rest of
  the app (`.custom(_:size:)` with no `relativeTo:`). The app has a documented
  `@ScaledMetric` floor pattern in `DesignSystem.swift`; the wild roles do not use
  it yet.
- **Week grouping and mileage dedup are duplicated** from `VoiceLogView`. Both
  copies must change together until one screen wins. The dedup rule itself is
  the dashboard's, and it matters — a voice log carrying a distance that matches
  a same-day GPS run is already counted on that run.
- **The niggle chips** appear in the wild row but the reference feed has none.
  Easy to drop if the row feels busy.
- **`Type a note instead`** is not in the canonical reference at all. If it goes,
  the typed-note path needs a door somewhere else.
- **Nothing is committed.** `git add -A && git commit` when you have built it and
  agree with it. `beta-v1-editorial` is still your undo.

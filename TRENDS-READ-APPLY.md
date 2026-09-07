# The Read · apply notes

*Placed 2026-08-07. Follows the repo's `APPLY-NOTES.md` additive-new-files convention.*

Builds the story-and-month surface from
`design-system/explorations/trends-story-calendar-2026-08-06.html` (Fig. 09)
as **its own tab, beside Trends** — not a replacement for `TrendsV2View`.
The point of a separate tab is to run the two reads side by side on device
before deciding which one Trends becomes.

**No backend work. No deploy. No migration.** Every number is computed on
device from `days` and `quality_sessions`, both of which `TrendsService`
already fetches for the Trends tab.

---

## 1 · What was placed automatically (new files, additive — safe)

| File | What it is |
|---|---|
| `Trends/TrendsReadModels.swift` | Pure. `TrendsRead` + `TrendsReadBuilder` — headline, story beats, month grid. No SwiftUI import. |
| `Trends/TrendsReadView.swift` | The surface. Plate, headline, story, volume figure, month grid, mood key. Also declares `DripEditorialRule`. |

Nothing existing was edited. Both files compile against tokens that already
exist: `Color.drip.*`, `.dripDisplay/.dripStat/.dripBody/.dripEyebrow/.dripCaption`,
`TrendsMoodColor`, `PaceSpectrum`.

**Naming was checked against the Trends folder.** `TrendsRead*` collides with
nothing; the closest existing names are `TrendsRecoveryFactors` and
`LoadRead` / `KeySessionsRead` / `MoodBlockRead` inside
`TrendsBlockModels.swift`, which are section reads, not page reads.

---

## 2 · The one thing worth arguing about before you wire it

**Only key sessions carry a classified pace.** `TrendsDay.SessionChannel`
is a session channel — `key | long | easy | rest` — and its own doc comment
says it is *"**not** a pace zone."* The only classified work zone in the
payload is `KeySession.zone` (`mile | 3k | 5k | 10k | hmp | mp`, LT folded
into `hmp` by the backend classifier).

So the HTML mock's "every bar tinted by pace" is not something the data
supports. What shipped here instead:

- a day with a classified key session → its zone colour off `PaceSpectrum`
- every other running day → neutral `textTertiary` at 55%

You still get the intended read — dark spikes in a pale field — and no bar
claims a pace that was never computed. If you want the full ramp, that is a
backend change (a dominant-zone token per day on `days[]`), not a view
change.

**Second divergence, deliberate:** the calendar encoding elsewhere in the
app gives key sessions the coral accent. This surface uses a drawn star
instead and keeps coral for body mentions only, so the alert palette means
one thing on the page. If you'd rather match the existing calendar, the
change is in `TrendsReadView.cell(_:)`.

---

## 3 · Wiring — **already applied**, described here for review

Both tracked-file edits below are in place. They are small and fenced;
read them before you build so nothing is a surprise.

### 3.1 · `App/DripTabBar.swift` — a fourth tab, DEBUG only

The IA is documented as three tabs and should stay three in release. Add
the case guarded so it never ships:

```swift
enum DripTab: Int, CaseIterable, Identifiable {
    case log = 0
    case trends = 4
    #if DEBUG
    /// Comparison surface for the Read (Fig. 09). DEBUG only — the
    /// release IA is three tabs. Remove with `TrendsReadView`.
    case read = 7
    #endif
    case training = 1
```

and in `label`:

```swift
        #if DEBUG
        case .read: "Read"
        #endif
```

`allCases` follows declaration order, so Read renders between Trends and
Train. Tag 7 is unused — 2, 3, 5 and 6 are retired tags per the enum's own
tombstone comment, so reusing one of those would make old jump-to-tab code
land somewhere surprising.

### 3.2 · The host — add the tag-7 branch

`RunningLogApp` / `MainTabView` constructs every tab at launch and hides
them with `.opacity`. Add the Read alongside the others, gated the same way:

```swift
#if DEBUG
TrendsReadView(
    read: TrendsReadBuilder.build(
        days: trendsService.days,
        keySessions: trendsService.keySessions
    ),
    windowLabel: trendsWindowLabel
)
.opacity(selectedTab == 7 ? 1 : 0)
.allowsHitTesting(selectedTab == 7)
#endif
```

What actually went in matches the neighbouring tabs — `NavigationStack`
wrapper, `.opacity` + `.allowsHitTesting` pair, placed between the Trends
branch and the retired-tag-5 comment:

```swift
#if DEBUG
NavigationStack { TrendsReadTabView() }
    .opacity(selectedTab == 7 ? 1 : 0)
    .allowsHitTesting(selectedTab == 7)
#endif
```

### 3.3 · `Trends/TrendsReadTabView.swift` — new file, the fetch gate

`MainTabView` gets one line rather than a builder call because the fetch
gate has to live somewhere: every tab is constructed at launch and hidden
with `.opacity`, so a `.task` on the content would fire a timeline request
for a tab nobody opened. `TrendsReadTabView` mirrors `TrendsTabView` —
same `TrendsService.shared`, same `.task(id: selectedTab)` gate, so there
is still exactly one fetch owner and opening either tab populates both.

It also computes the plate strip's window label from the day keys, so no
new service property was needed.

---

## 4 · What this surface does not do yet

- **Load and recovery are missing.** They're the two signals that don't
  belong to a single day, and they already have renderers on the Trends
  tab. Drawing them again here would be a second definition of the same
  number. They belong as two slim lanes under the figure, reading whatever
  `TrendsRecoveryDemand` / the ACWR read already expose — that's the next
  pass, and it's why the section is headed "The work" rather than "The
  figure".
- **No tap-through.** Cells are accessibility-labelled but inert.
- **No range control.** The window is whatever `days` contains.

---

## 5 · Tests — **written**, `RunningLogTests/TrendsReadTests.swift`

21 cases, Swift Testing (`@Suite` / `@Test` / `#expect`), matching the
neighbouring suites. `TrendsReadBuilder` is pure and every branch is a
string assertion, so this is unit tests and not cassettes — the headline
never reaches a model.

The last case is the one that earns its keep: it joins every string the
builder emitted and asserts none of them contains second person, a
trajectory word, or praise. That's the copy rule enforced by the build
rather than by memory.

| Case | Expect |
|---|---|
| 4 running days | `isThin == true`, headline is the empty-state line, no beats beyond the count |
| 5 running days | `isThin == false` |
| body mention inside last 7 days | headline is `"{Area}, {n} mentions."` — alert outranks volume |
| body mention 10+ days ago | headline falls through to volume; niggle beat says "last on {date}" |
| back half ≥10% over front | `"Volume, up {n}%."` |
| back half within ±10% | `"A flat {n} days."` |
| no moods logged | `moodCounts` empty, no opening beat, grid still builds |
| window crossing a month end | `dayOfMonth` resets, week rows stay Monday-first |
| ties in `dominantArea` | earliest-appearing area wins, stably across runs |

The last one is the one worth writing first: it's the only place the
builder picks between two equally-supported strings, and an unstable answer
there means the headline changes on reload without the data changing.

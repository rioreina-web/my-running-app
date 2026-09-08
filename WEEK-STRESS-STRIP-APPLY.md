# WEEK STRESS STRIP — APPLY

A single horizontal strip in the Train tab. Seven equal slots, one per day,
each representing a full 24 hours. Every run is a bar placed at its start
time within its day, whose **height is that run's training load score** and
whose fill is stacked by pace zone.

Visual reference: `week-stress-horizontal-prototype.html` (repo root, frame A).
The prototype is the intent; this document is the production spec.

**Status: needs a backend change first.** Phase 1 is an edge-function field.
Phases 2–5 are client. Do not start Phase 3 until Phase 1 is deployed.

**Relationship to `WEEK-LOAD-APPLY.md`:** that spec proposed a marimekko of
seven day columns for the same slot in the Train tab. This supersedes it as
the direction, and reuses its Phase 1 groundwork — but **not unchanged**: the
marimekko needed `day × zone`, this needs `run × zone × start time`. Read §1
carefully rather than assuming the earlier field shape is enough. If
`WEEK-LOAD-APPLY` Phase 1 already shipped, §1 here is an extension of it, not
a replacement.

---

## 0 · What the chart claims, and what it does not

Three encodings, and it is worth being strict about them because two of them
are deliberately imprecise:

| Channel | Encodes | Precision |
|---|---|---|
| Bar **height** | that run's TLS | exact, shared scale across the week |
| Bar **fill** | pace zones, stacked easy→sharp | exact, proportional to each zone's TLS |
| Bar **x-position** | time of day | **approximate — part of day, not the hour** |
| Bar **width** | nothing | fixed |

**Position is not readable to the hour and must not be presented as if it
were.** There is no hour axis, no gridlines at 6/12/18, no tick labels. The
caption under the strip says "midnight to midnight, left is early, right is
late" and that is the whole contract. Anywhere the app needs to state *when*,
it states a part of day (`Morning`, `Midday`, `Afternoon`, `Evening`,
`Night`) plus the literal clock time as text — never by inviting the athlete
to measure across the chart.

**Width encodes nothing, and this is a real loss.** At seven days across a
390pt phone a day slot is ~48pt, so a true-to-scale 76-minute run would be
2.5pt wide. Duration moved into the detail panel instead. If a future surface
needs duration *and* time-of-day in the same picture, that is the per-day
chart in `week-stress-clock-prototype.html`, not this one — do not try to
retrofit proportional width here.

---

## 1 · Backend: per-run start time and zone breakdown

### The gap

`segmentFromLaps()` already classifies every lap into the 10-zone taxonomy
and returns `Bout { zone, seconds, distanceMeters }`
(`supabase/functions/_shared/workoutSegmentation.ts`). `trends-timeline/index.ts`
already fetches `lapsByWorkout` for every log in the window.

What does not exist is any surface carrying **individual runs** with their
**start times**. `TrendsDayOut` is day-grained throughout; a day with a double
collapses into one row, which this chart cannot render — the whole point of
Tuesday is that it has two bars.

### The change

No migration. No new table. Laps and `started_at` are already in memory.

**1a.** `supabase/functions/trends-timeline/timeline.ts` — add a nested run
array to `TrendsDayOut`:

```ts
export interface TrendsRunOut {
  /** The workout row id, so the client can route to the run detail. */
  id: string;
  /** Run START time, ISO8601 WITH the original UTC offset preserved
   *  (e.g. "2026-08-04T06:05:00-05:00"). NOT normalised to UTC — see §1e. */
  started_at: string;
  /** When the file arrived. Shown in the panel, never used for placement. */
  uploaded_at: string | null;
  duration_min: number;
  miles: number;
  /** Minutes per pace zone for THIS RUN, all ten zones of the canonical
   *  taxonomy. Built from every Bout returned by segmentFromLaps — NOT
   *  filtered to WORK_ZONES, because easy volume is most of the bar.
   *  Zones with no time are omitted, not zero-filled. */
  zone_minutes?: Partial<Record<Zone, number>>;
  zone_miles?: Partial<Record<Zone, number>>;
}

export interface TrendsDayOut {
  // ... existing fields unchanged ...
  runs?: TrendsRunOut[];
}
```

Import `Zone` from `../_shared/workoutSegmentation.ts`.

**1b.** In `buildDailyTimeline`, emit one `TrendsRunOut` per log rather than
folding logs together. Accumulate **every** bout, do not filter to
`WORK_ZONES`:

```ts
for (const b of seg.bouts) {
  zoneMinutes[b.zone] = (zoneMinutes[b.zone] ?? 0) + b.seconds / 60;
  zoneMiles[b.zone]   = (zoneMiles[b.zone]   ?? 0) + b.distanceMeters / 1609.344;
}
```

Round to 2dp on the way out. Omit a zone whose minutes round to 0.

**1c.** A run whose log has **no laps** gets `zone_minutes: undefined`, not
`{}`. The distinction is load-bearing — see state C in §3. Do **not** fall
back to classifying the whole run by its average pace: that is the averaging
bug `_shared/quality-volume.ts` documents at length, and it would book an
18-mile long run with a 5-mile MP block as 18 easy miles.

**1d.** Verify the sums. For any day, `Σ runs[].duration_min` must equal that
day's `duration_min` and `Σ runs[].miles` its `miles`, both within rounding.
Within a run, `Σ zone_minutes` must equal its `duration_min`. Assert in the
function's existing test harness before shipping.

**1e. Timezone — read this before writing a line of it.**

This is the one hard dependency the earlier day-grained specs never had.
Placing a bar requires the athlete's **local** hour, and per CLAUDE.md the
`athlete_settings.timezone` writer does not exist yet on iOS or web, so
*"until then all athletes default to UTC."* A UTC-placed chart puts a 6am
Chicago run at 11am and is silently, confidently wrong.

Do not solve this by waiting on the settings writer, and do not solve it by
looking up a timezone server-side. Solve it by **never discarding the offset
in the first place**: `started_at` carries the offset it was recorded with,
and the client derives the hour from that with a `Calendar` whose
`timeZone` is taken from the timestamp itself. Postgres `TIMESTAMPTZ`
normalises to UTC on storage, so if the source column has already lost the
offset, take the offset from the HealthKit workout on device instead and
treat the server value as a fallback only.

Whichever path, add a test that pins a run recorded at 06:05 −05:00 to the
6am position when the device is set to Asia/Tokyo. A time-of-day chart that
moves when the athlete flies somewhere is worse than no chart.

---

## 2 · iOS: decode the new shape

**2a.** `RunningLog/RunningLog/Trends/TrendsService.swift` — add `TrendsRunDTO`
matching `TrendsRunOut`, and `let runs: [TrendsRunDTO]?` on `TrendsDayDTO`,
with `CodingKeys` for the snake_case names. Optional — an older cached payload
must still decode.

**2b.** `RunningLog/RunningLog/Trends/TrendsReadModels.swift` — carry the runs
onto the day model `TrendsService.shared.days` exposes. Keep zone dictionaries
as `[String: Double]` keyed by the raw zone token; the view resolves tokens
through `TrendsZoneWeight` and `PaceSpectrum`, which is where that mapping
already lives.

**2c.** Do **not** add a client-side fallback that computes zones from average
pace. If the field is missing, the bar says so (§3, state C).

---

## 3 · iOS: the section

### File

`RunningLog/RunningLog/Training/Analytics/WeekStressStripSection.swift`

Separate `struct`, following the `TrainingCalendarSection` pattern
(`TrainingTabView.swift`):

```swift
struct WeekStressStripSection: View {
    let vm: TrainingAnalyticsViewModel
    /// 0 = current week, 1 = last week. Mirrors TrainingTabView.weekOffset so
    /// this section pages with the This-Week section above it.
    let weekOffset: Int
    var onTapRun: (UUID) -> Void
}
```

### Data assembly

Compose from three existing sources. Do not add a fourth.

| Need | Source |
|---|---|
| Mon→Sun dates, rest/future flags | `vm.dayVolumes(forWeekStart:)` → `[DayVolume]` |
| Per-run start, zones, miles | `TrendsService.shared.days[].runs`, matched by date (Phase 2) |
| Zone weights, load maths | `QualityLoad.score(workSeconds:zone:)` (`Trends/TrendsQualityLoad.swift`) |
| Zone colours | `PaceSpectrum` (`Workouts/PaceSpectrum.swift`) |
| Mood, niggles | `TrendsDay.mood: String?`, `TrendsDay.niggles: [DayNiggle]` |

```swift
private struct StressRun: Identifiable {
    let id: UUID
    let dayIndex: Int              // 0 = Monday
    let minuteOfDay: Int           // 0...1439, LOCAL — see §1e
    let minutes: Double
    let miles: Double
    /// Taxonomy-ordered, easy → mile. Zones with no volume are absent.
    let zones: [(token: String, minutes: Double, miles: Double, load: Double)]
    let load: Double               // Σ QualityLoad.score over zones
    let uploadedAt: Date?
    let hasZoneData: Bool
}
```

`load` uses `QualityLoad.score(workSeconds: minutes * 60, zone: token)` summed
across zones — **do not** re-implement the weights. `TrendsZoneWeight.table`
already mirrors `ZONE_WEIGHTS` and `TrendsQualityLoadTests` pins it; a second
copy is a third place to drift.

> **The weight table is currently ambiguous in this repo and must be settled
> before this ships.** `week-load-simple-prototype.html` has Moderate ×1.25 /
> Steady ×1.50; `tls-explainer-prototype.html` has ×1.40 / ×2.15 and omits LT
> entirely. They cannot both be right, and a chart whose entire y-axis is
> these numbers cannot ship on top of an open question. Pick one, update
> `TrendsZoneWeight.table`, and delete the losing copy from the prototype.

### Layout

Four stacked pieces, in this order, with **every vertical gap drawn from the
8pt scale**. The prototype's spacing is normative: 16 / 8 / 32 / 12 / 8 / 8 /
16 / 24. No off-grid 14s or 22s — CLAUDE.md lists untokenized spacing as one
of the standing iOS drifts, and this is a new surface with no excuse.

**1. Section head** — `sectionHead("WEEK · TRAINING STRESS", trailing: "<n> RUNNING DAYS")`.
Reuse `TrainingTabView`'s existing private helper by lifting it; do not invent
a third header treatment.

**2. The plot.** One `GeometryReader`, height 112pt (compact) / 132pt (regular).

- day slot width = `geo.size.width / 7`. Flat, always. It is 24 hours whether
  or not anything happened in it.
- bar width fixed: 10pt compact, 14pt regular
- bar x = `dayIndex * slot + (minuteOfDay / 1440) * (slot - barWidth)`.
  The `- barWidth` inset is what stops an 11pm run overhanging the next day.
- `HEAD_ROOM = 14pt` reserved at the top: the tallest bar scales to
  `plotHeight - HEAD_ROOM`, which also gives the niggle caret somewhere to sit
  without clipping.
- bar height = `run.load / weekMaxRunLoad * usable`, floor 3pt
- fill: `VStack(spacing: 0)` of zone blocks, **easy at the bottom**, each
  block's height = `zone.load / run.load` of the bar. `PaceSpectrum` colours.
  `cornerRadius 2` on the top corners only, via `.clipShape`.
- interior day dividers only, 1pt `rule`. No border box around the plot —
  the bottom axis is a single 1pt `textTertiary` line and that is the only
  chrome.
- future days: dashed divider, nothing else

> `HStack` `layoutPriority` does **not** split width proportionally — the
> `RRZoneBar` comment at `Workouts/WorkoutReceiptCharts.swift` says this
> explicitly. Position bars with `.offset(x:)` inside a `ZStack(alignment:
> .bottomLeading)`, computing x yourself from the geometry width.

**3. The day rail.** Seven equal cells sharing the plot's baseline, each:
day label (`dripEyebrow(10).tracking(1.2)`), the day's total TLS
(`dripStat(12)`), and the mood tick (13×2.5pt capsule). Gaps 12 / 8 / 8.

Note the day total is the sum of *all* that day's runs, so on a double it
will not equal any single bar. That is correct and worth leaving alone.

**4. The caption.** One italic line, `textTertiary`:
*"Each slot is one day, midnight to midnight. A bar sits where the run
happened in it — left is early, right is late."* This replaces the hour axis
and is not optional; without it the x-position is uninterpreted.

### Tap behaviour

Tapping a bar opens the detail panel in place below the caption (the
`week-load-simple` expand idiom), and tapping the open bar closes it. The
panel shows: part-of-day + clock time, miles · duration · TLS, upload time,
the per-zone table (`minutes × multiplier = load`, totalled), the TLS note,
and the niggle quote when the day has one. `Open run ↗` routes via
`onTapRun(id)`.

Show the upload lag only when it exceeds 4 hours ("— 15h after the run").
Under that it is noise.

### House rules this section must satisfy

**Three-palette rule** (CLAUDE.md, 2026-07-03): *"blue = pace, warm = mood,
coral = alert; the three palettes never share hues."*

- bar fills, legend strip → `PaceSpectrum` blues only
- mood tick → `Color.drip.energized / .positive / .neutral / .tired /
  .struggling / .injured`
- coral → the niggle caret, and nothing else

**Coral budget**: *"One coral element per visual cluster, maximum."* The whole
strip is one cluster. One caret per day with a niggle, hung 4pt above that
day's first bar, centred on it. Selection is a `textPrimary` 1.5pt inset
stroke, **not** coral.

**Empty states** (Hard rule #8): *"No em-dashes as empty-state placeholders."*
Three distinct states, do not collapse them:

- **A · rest day** — a logged-nothing day in the past. No bar. The rail shows
  a literal `0` in `textTertiary` — a `0` is a fact, not a placeholder. Tapping
  the slot gives `EmptyStateView(variant: .optionalEmpty, eyebrow: "Rest day",
  title: "Nothing logged, and nothing missing. The week's stress is carried by
  the other days.")`
- **B · future day** — dashed divider, no bar, rail number hidden (not `0` —
  the day has not had the chance to be zero yet)
- **C · ran, but no zone data** — `hasZoneData == false`. A 12pt hatched stub
  with a dashed outline and **no height**, because height means load and there
  is no load to claim. Panel:
  `EmptyStateView(variant: .dataPending, eyebrow: "No lap data", title: "This
  run arrived without splits, so there is no pace breakdown and no load score
  for it. The miles still count toward the week.")`

**Type floors**: no font literal below 9pt. Use
`@ScaledMetric(relativeTo: .caption)` against `DripTypeFloor.eyebrowMicro` (9)
and `.eyebrowSmall` (10) for every label, per the doc comment in
`DesignSystem.swift`. At the largest Dynamic Type sizes the day labels will
not fit seven across — drop them to first-initial (`M T W T F S S`) rather
than shrinking below the floor or truncating mid-word.

**Don't reinvent primitives**: `dripEyebrow(_:)` + `.tracking()` for uppercase
labels, `dripStat(_:)` for numerals. Do not hand-roll
`.system(size:design:.monospaced)`.

### Accessibility

Each bar is one element:

```
"Tuesday morning. 10.7 miles, 1 hour 16. Training load 187.
 39 minutes easy, 15 moderate, 16 at 5K, 6 at 3K."
```

Append `"Right achilles, grumbling."` when the day has a niggle. Zone blocks
are `.accessibilityHidden(true)` under that label. The day rail is a separate
element per day: `"Tuesday, total training load 222."`

Note the label says **"morning"**, not "6:05am" — matching what the position
actually encodes. The exact time belongs in the panel, and is read there.

---

## 4 · Wiring

`TrainingTabView.swift` — in the `.current` branch, place
`WeekStressStripSection(vm: vm, weekOffset: weekOffset) { route = .run($0) }`
directly under `currentWeekSection`, so it pages with the same `weekOffset`
state that section owns.

If `WEEK-LOAD-APPLY` has already shipped its marimekko into this slot, this
replaces it, and its `ZoneVolumePie` primitive becomes unreferenced — leave
the file in place and unlinked rather than deleting it, per the repo's
standing "built but not mounted" convention, and add it to that table in
CLAUDE.md.

---

## 5 · Tests

`RunningLog/RunningLogTests/WeekStressStripTests.swift`

1. **Load matches the canonical model.** 39 min easy + 15 moderate + 16 at 5K
   + 6 at 3K → 39 + 18.75 + 88 + 40.5 = **186** (displays 187 from unrounded
   minutes). Assert against `QualityLoad.score`, not a literal, so the test
   fails if the weights move.
2. **Position is local and stable.** A run recorded 06:05 −05:00 lands at the
   same x with the device in America/Chicago and in Asia/Tokyo. This is the
   §1e regression test and it is the most important one here.
3. **No overhang.** A run starting 23:50 on Sunday has its right edge inside
   the track, and one starting 00:05 on Monday has its left edge at or after
   the track origin.
4. **Doubles render separately.** A day with two runs produces two bars whose
   heights sum to neither more nor less than the day's total load.
5. **Three empty states resolve distinctly.** Rest, future, and
   ran-without-laps each produce their own branch; assert none renders a bare
   `"—"`.
6. **Stacking order.** Zone blocks ascend easy→mile bottom to top for a run
   containing four non-adjacent zones.

---

## 6 · Rollback

Phases 2–5 are purely additive. To revert, remove the section from
`TrainingTabView`. The Phase 1 field is optional on the client, so a backend
rollback degrades every bar to state C rather than crashing — but the section
would then be empty for the whole week, so revert the client too.

---

## 7 · Open questions

1. **Cross-week comparability.** Bar heights scale to *that week's* tallest
   run, so a 200-TLS session fills the plot in a light week and sits
   mid-height in a heavy one. The day-rail totals are the honest comparison.
   The alternative — a fixed ceiling across all weeks — makes a recovery week
   render as a row of stubs. Current spec: relative heights, absolute numbers
   stated. Worth confirming before this ships.
2. **Two runs at nearly the same hour.** A 6:00am and a 6:40am run overlap at
   phone width. Current spec lets them overlap and relies on tap targets
   resolving to the topmost. Nudge-apart, merge, or leave?
3. **Whether the day rail should show TLS or miles.** TLS is the chart's own
   unit and keeps the surface coherent; miles is the number the athlete
   actually thinks in. Currently TLS, with miles in the panel.

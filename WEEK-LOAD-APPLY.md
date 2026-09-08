# WEEK LOAD — APPLY

Replace **Section 8 · Effort · Felt vs Planned** in the Train tab with a
one-week training-load surface: each day's *width* is its share of the week's
training load, a pie inside each column carries that day's volume broken down
by pace zone, and a weekly pace-spectrum bar sits underneath.

Visual reference: `week-training-load-prototype.html` (repo root). The
prototype is the intent; this document is the production spec.

**Status: needs a backend change first.** Phase 1 is an edge-function field.
Phases 2–4 are client. Do not start Phase 3 until Phase 1 is deployed, or the
section will render empty in a way the empty state cannot explain.

---

## 0 · Why this replaces Felt vs Planned

Felt vs Planned answers "did that session cost what it was meant to cost" one
row at a time. It never aggregates, it only renders when `feltRpe` exists
(rare in practice), and it sits in CURRENT mode where the athlete is looking
at the week, not at individual sessions. The week-load surface answers the
question the position implies: *what did this week actually ask of me, and
where did it come from.*

`feltInsight()` and the `FeltVsPlanned` model are **not** deleted in this
change — see Phase 4. Only the rendered section goes.

---

## Phase 1 · Backend: per-day zone breakdown

### The gap

`segmentFromLaps()` already classifies every lap into the 10-zone taxonomy and
returns `Bout { zone, seconds, distanceMeters }`
(`supabase/functions/_shared/workoutSegmentation.ts:200-209, 230-263`).
`trends-timeline/index.ts:184` already fetches `lapsByWorkout` for every log in
the window.

Nothing aggregates those bouts by day across all ten zones. What exists today:

| Surface | Granularity | Zones | Units |
|---|---|---|---|
| `TrendsDayOut.type` | day | one coarse label | — |
| `QualityVolumeWeekOut.zone_seconds` | **week** | **6** (`WORK_ZONES` only) | seconds |
| `KeySessionOut.zone` | session | one dominant label | — |
| `workout_features.*_seconds` | workout | **4** legacy buckets | seconds |

None of them is day × 10 zones × (minutes + miles).

### The change

No migration. No new table. Laps are already in memory.

**1a.** `supabase/functions/trends-timeline/timeline.ts` — extend `TrendsDayOut`
(currently lines 150-170):

```ts
export interface TrendsDayOut {
  // ... existing fields unchanged ...

  /** Minutes per pace zone for this day, all ten zones of the canonical
   *  taxonomy. Built from every Bout returned by segmentFromLaps — NOT
   *  filtered to WORK_ZONES, because easy volume is the point of this
   *  surface. Zones with no time are omitted, not zero-filled. */
  zone_minutes?: Partial<Record<Zone, number>>;

  /** Miles per pace zone, same construction and same omission rule.
   *  Paired with zone_minutes so the client can compute a real average
   *  pace per zone (total time / total distance) rather than a mean
   *  of per-run means. */
  zone_miles?: Partial<Record<Zone, number>>;
}
```

Import `Zone` from `../_shared/workoutSegmentation.ts`.

**1b.** In `buildDailyTimeline` (same file), for each log on a day, call
`segmentFromLaps(laps, zones)` and accumulate **every** bout — do not filter to
`WORK_ZONES`:

```ts
for (const b of seg.bouts) {
  zoneMinutes[b.zone] = (zoneMinutes[b.zone] ?? 0) + b.seconds / 60;
  zoneMiles[b.zone]   = (zoneMiles[b.zone]   ?? 0) + b.distanceMeters / 1609.344;
}
```

Round to 2dp on the way out. Omit a zone entirely when its accumulated
minutes round to 0.

**1c.** A day whose logs have **no laps** (manual entry, or a Strava import
with no lap data) gets `zone_minutes: undefined`, not `{}`. The distinction
matters — see the client's three-state handling in Phase 3. Do **not** fall
back to classifying the whole run by its average pace: that is exactly the
averaging bug `_shared/quality-volume.ts` documents at length, and it would
book an 18-mile long run with a 5-mile MP block as 18 easy miles.

**1d.** Verify the sum. For any day, `Σ zone_minutes` must equal that day's
`duration_min` within rounding, and `Σ zone_miles` must equal `miles`. If they
don't, bouts are being dropped — likely rest bouts being excluded upstream.
Add an assertion in the function's existing test harness before shipping.

---

## Phase 2 · iOS: decode the new fields

**2a.** `RunningLog/RunningLog/Trends/TrendsService.swift`, `TrendsDayDTO`
(currently lines 247-263) — add:

```swift
let zoneMinutes: [String: Double]?
let zoneMiles: [String: Double]?
```

with the matching `CodingKeys` (`zone_minutes`, `zone_miles`). Both optional —
an older cached payload must still decode.

**2b.** `RunningLog/RunningLog/Trends/TrendsReadModels.swift` — carry the same
two dictionaries onto the day model that `TrendsService.shared.days` exposes.
Keep them as `[String: Double]` keyed by the raw zone token; the view resolves
tokens through `TrendsZoneWeight` and `PaceSpectrum`, which is where that
mapping already lives.

**2c.** Do **not** add a client-side fallback that computes zones from average
pace. If the field is missing, the section says so (Phase 3, state C).

---

## Phase 3 · iOS: the new section

### File

`RunningLog/RunningLog/Training/Analytics/WeekTrainingLoadSection.swift`

Separate `struct`, following the `TrainingCalendarSection` pattern
(`TrainingTabView.swift:109`) — it needs the shared view model for the Mon→Sun
scaffolding and a callback for day navigation:

```swift
struct WeekTrainingLoadSection: View {
    let vm: TrainingAnalyticsViewModel
    /// 0 = current week, 1 = last week. Mirrors TrainingTabView.weekOffset so
    /// this section pages with the This-Week section above it.
    let weekOffset: Int
    var onTapDay: (Date) -> Void
}
```

### Data assembly

Compose from three existing sources. Do not add a fourth.

| Need | Source |
|---|---|
| Mon→Sun dates, rest/future flags | `vm.dayVolumes(forWeekStart:)` → `[DayVolume]` (`TrainingAnalyticsViewModel.swift:908`) |
| Per-zone minutes + miles | `TrendsService.shared.days`, matched by date (Phase 2) |
| Zone weights, load maths | `TrendsZoneWeight.table` + `QualityLoad.score(workSeconds:zone:)` (`Trends/TrendsQualityLoad.swift:86`) |
| Mood, niggles | `TrendsDay.mood: String?`, `TrendsDay.niggles: [DayNiggle]` |

Build one private model in the section's own file:

```swift
private struct LoadDay: Identifiable {
    let id = UUID()
    let date: Date
    let label: String              // MON / TUE …
    let miles: Double
    let minutes: Double
    /// Taxonomy-ordered, easy → mile. Zones with no volume are absent.
    let zones: [(token: String, miles: Double, minutes: Double, load: Double)]
    let load: Double               // Σ QualityLoad.score over zones
    let mood: String?              // energized|positive|neutral|tired|struggling|injured
    let niggle: DayNiggle?         // first, if any
    let isRest: Bool
    let isFuture: Bool
    let hasZoneData: Bool          // false when zone_minutes was absent
}
```

`load` uses `QualityLoad.score(workSeconds: minutes * 60, zone: token)` summed
across zones — **do not** re-implement the weights. `TrendsZoneWeight.table`
is already a mirror of `ZONE_WEIGHTS` and `TrendsQualityLoadTests` pins it;
a second copy is a third place to drift.

### Layout

Three stacked pieces, in this order.

**1. Section head** — `sectionHead("WEEK · TRAINING LOAD", trailing: "<n> RUNNING DAYS")`.
Reuse `TrainingTabView`'s existing private helper by lifting it, or duplicate
the two-line `HStack`; do not invent a third header treatment.

**2. The marimekko.** Seven columns in an `HStack(spacing: 2)`. Each column's
width is its share of the week's load.

> `HStack` `layoutPriority` does **not** split width proportionally — the
> `RRZoneBar` comment at `Workouts/WorkoutReceiptCharts.swift:1228-1266` says
> this explicitly and it is the same trap here. Wrap in `GeometryReader` and
> set each column to `.frame(width: geo.size.width * share)` computed
> yourself, after subtracting `6 * 2` for the spacing and clamping each
> column to a 46pt floor, then re-normalising the remainder.

Per column, top to bottom:

- day label — `dripEyebrow(11).tracking(1.3)`, `textSecondary`
- share `"27%"`, or `"REST"` — `dripEyebrow(9).tracking(0.9)`, `textTertiary`
- the volume pie (below)
- the load band — 28pt tall, `cornerRadius 2`. Fill: solid `textPrimary` at
  0.8 opacity, or, when the zone toggle is on, stacked by that day's
  load-per-zone using `PaceSpectrum` colours
- `"186 · 18.0mi"` — `dripStat(10)`, load bold in `textPrimary`, distance in
  `textSecondary`
- signals row: mood dot, plus the niggle mark (below)

**3. The weekly pace spectrum.** One full-width bar under an `EditorialRule()`.
Segment width ∝ **miles** in that zone across the week, zones in taxonomy
order, `PaceSpectrum` colours, 1pt `background`-coloured gutters between
segments (the `RRZoneBar` idiom). Beneath each segment: zone name, miles, and
the week's real average pace for that zone —
`Σ minutes × 60 / Σ miles`, **not** a mean of per-run paces.

Labels drop out by measured width: under 56pt keep only the zone name with
`.truncationMode(.tail)`; under 24pt hide the label entirely and rely on the
accessibility label. Compute against the same `GeometryReader` width.

### The pie — this is a new primitive

**There is no pie or donut anywhere in the codebase.** Grepping `donut`,
`PieChart`, `Circle().trim` across `RunningLog/RunningLog` returns zero
matches. The house idiom for proportion is the horizontal stacked bar
(`RRZoneBar`).

So this genuinely is a new primitive, and it should be introduced
deliberately rather than inlined:

`RunningLog/RunningLog/Workouts/ZoneVolumePie.swift`

```swift
/// Volume-by-pace-zone as a pie. Area — not radius — is proportional to
/// volume, so a day's ink matches its miles: radius scales as √miles.
///
/// New primitive (2026-08). The house idiom for proportion is RRZoneBar's
/// horizontal stack; a pie earns its place here only because seven of them
/// sit side by side at different SIZES, and a stacked bar cannot encode
/// magnitude and composition at once in a fixed-width column.
struct ZoneVolumePie: View {
    /// Taxonomy-ordered, easy → mile.
    let slices: [(token: String, miles: Double)]
    /// Diameter for the week's largest day; this pie scales down from it.
    let maxDiameter: CGFloat
    let maxMiles: Double
}
```

Draw with `Path { addArc }` per slice, `PaceSpectrum` fills, a 0.75pt
`cardBackground` stroke between slices. Start at 12 o'clock (`-.pi/2`).

If you would rather not add a pie primitive, the fallback that stays inside
the existing idiom is a **vertical** `RRZoneBar` per column whose *height*
encodes volume. It reads less well at a glance but adds no new shape
vocabulary. Flag the choice in the PR rather than deciding silently.

### House rules this section must satisfy

**Three-palette rule** (CLAUDE.md, 2026-07-03): *"blue = pace, warm = mood,
coral = alert; the three palettes never share hues... coral is alert-only
(niggles, out-of-zone workload, brand punctuation — never a pace fill)."*

- pie slices, load band segments, spectrum bar → `PaceSpectrum` blues only
- mood dot → `Color.drip.energized / .positive / .neutral / .tired /
  .struggling / .injured`, resolved from the mood string
- coral → the niggle mark, and nothing else

**Coral budget** (CLAUDE.md): *"One coral element per visual cluster,
maximum."* Each day column is a cluster. The prototype violates this — it
draws a dashed coral ring around the pie *and* a coral caret below *and* a
coral selection border. **Ship the caret only.** Selection uses a
`textPrimary` inset stroke on the load band, not coral. The ring goes.

Dropping the ring also avoids the sharper problem: a coral annotation drawn
on top of a pace surface reads as coral commenting on pace, which is the
thing the three-palette rule exists to prevent.

**Empty states** (Hard rule #8): *"No em-dashes as empty-state placeholders.
Every empty cell uses the empty-state component (eyebrow + plain-prose nudge
+ optional CTA)."* Three distinct states, do not collapse them:

- **A · rest day** — a logged-nothing day in the past. Column renders at the
  46pt floor with a hatched band, `"REST"` where the share would be, and `0`
  where the load would be. A literal `0` is a fact, not a placeholder, so it
  is fine here. Tapping gives `EmptyStateView(variant: .optionalEmpty,
  eyebrow: "Rest day", title: "Nothing logged, and nothing missing. The
  week's load is carried by the other days.")`
- **B · future day** — dashed outline, no numbers, matching the existing
  `isFuture` treatment in `DayVolume`
- **C · ran, but no zone data** — `hasZoneData == false`. The day has miles
  but no laps, so it has no breakdown. Solid `neutral` band sized by an
  easy-weighted estimate would be a fabrication; instead render the band in
  `paperDeep` with no pie and surface
  `EmptyStateView(variant: .dataPending, eyebrow: "No lap data", title:
  "This run came in without splits, so its pace breakdown isn't available.
  The miles still count toward the week.")`

**Type floors**: no font literal below 9pt. Use
`@ScaledMetric(relativeTo: .caption)` against `DripTypeFloor.eyebrowMicro`
(9) and `.eyebrowSmall` (10) for every label in the chart, per the doc
comment at `DesignSystem.swift:238-244`. The prototype's 9px labels are at
the floor already; do not shrink them to fit narrow columns — hide them
instead.

**Don't reinvent primitives**: use `dripEyebrow(_:)` + `.tracking()` for
uppercase labels and `dripStat(_:)` for numerals. Do not hand-roll
`.system(size:design:.monospaced)`.

### Accessibility

Each column is one accessibility element, not six:

```
"Sunday the 9th. 18 miles. Training load 186, 27 percent of the week.
 12 miles easy, 1 mile steady, 5 miles at marathon pace. Felt tired."
```

Append `"Left achilles, tight."` when a niggle exists. The pie, band and
numerals are all `.accessibilityHidden(true)` under that one label.

---

## Phase 4 · Wiring and what stays

**4a.** `TrainingTabView.swift:101` — in the `.current` branch, replace:

```swift
feltVsPlanned
```

with:

```swift
WeekTrainingLoadSection(vm: vm, weekOffset: weekOffset) { route = .day($0) }
```

It sits directly under `currentWeekSection`, which is where the week context
already is, and it pages with the same `weekOffset` state that section owns
(`TrainingTabView.swift:56`).

**4b.** Delete the now-unreferenced view code:

- `private var feltVsPlanned` — `TrainingTabView.swift:556-581`
- `private struct FeltScale` — `TrainingTabView.swift:1497-1519`
- the section-order comment for item 8 — `TrainingTabView.swift:20`

**4c.** **Keep** `TrainingAnalyticsViewModel.feltVsPlanned()`
(`:1459`), `feltInsight()` (`:1498`) and `struct FeltVsPlanned` (`:293`).
`feltInsight()` is a data-derived insight sentence and is a candidate for the
header insight slot; deleting the model would take it with it. Add a one-line
comment above `feltVsPlanned()` noting it currently has no view, so the next
reader doesn't assume it's dead and remove it.

Per CLAUDE.md: *"Several finished surfaces are in the repo with no route to
them. They were deliberately unlinked, not abandoned."* This is that, on
purpose.

---

## Tests

`RunningLog/RunningLogTests/WeekTrainingLoadTests.swift` — there are currently
no tests touching Felt vs Planned, so nothing breaks on removal.

1. **Load matches the canonical model.** A day of 12 mi easy (96 min), 1 mi
   steady (6.9 min), 5 mi MP (31.7 min) → 96 + 10.4 + 79.2 = **186** weighted
   minutes. Assert against `QualityLoad.score`, not a literal, so the test
   fails if the weights move.
2. **Widths sum to the track.** Seven columns plus six 2pt gutters, with two
   rest days at the 46pt floor, must total the available width within 0.5pt.
   This is the assertion that catches the `layoutPriority` trap.
3. **Average pace is time-weighted.** 3 mi easy at 8:30 and 12 mi easy at
   8:02 → 8:07/mi, not 8:16/mi. A mean-of-means implementation fails this.
4. **Three empty states resolve distinctly.** Rest, future, and
   ran-without-laps must each produce their own branch; assert none of them
   renders a bare `"—"`.
5. **Zone sums reconcile.** For a fixture day, `Σ zone_miles == miles` and
   `Σ zone_minutes == duration_min` within 0.01.

---

## Rollback

Phases 2–4 are additive except the deletion in 4b. To revert, restore
`feltVsPlanned` and `FeltScale` from git and swap line 101 back. The Phase 1
edge-function fields are optional on the client, so a backend rollback
degrades the section to state C (no lap data) rather than crashing it — but
the section would then be empty for every day, so revert the client too.

---

## Open questions

1. **Cross-week comparability.** Column widths are a share of *that week's*
   load, so a 20% day in a light week is fewer weighted minutes than a 20%
   day in a heavy one. The wmin totals in the head are the honest comparison.
   The alternative — scaling every week against a fixed max — makes a light
   week fill half the screen and read as broken. Current spec: relative
   widths, absolute totals stated. Worth confirming before this ships.
2. **Sub-half-mile zones.** A 0.3 mi stride set is a 3pt stripe in the
   spectrum bar with no room for a label. Merge into the adjacent zone below
   a threshold, or keep the stripe and rely on the accessibility label?
   Current spec keeps the stripe.
3. **Where the pie primitive lives.** Filed under `Workouts/` above to sit
   beside `PaceSpectrum` and the other chart primitives, but it is a
   general-purpose shape and `DesignSystem.swift` has a claim on it too.

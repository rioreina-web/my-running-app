# The Sheet — every session as one dense row

**Status:** apply doc, 2026-08-11 · rev 4 (adds filter + search)
**Prototype:** `stat-sheet-prototype.html` (repo root, real rows Jun 15 – Aug 11, drawn at 393pt)
**Implements:** Phase 3 of `docs/specs/runs-and-notes-split.md` — "move readers"
**Surface:** new screen pushed from the Log tab header. No tab-bar change.

---

## What this is

A dense, scannable table of completed training. One row per **session**,
week-grouped, totals strip on top. It is the screen you read to see a block of
training at once — not the journal, which is for reading one entry at a time.

A session is not a day and it is not an upload. Aug 4 is five Strava
activities, which are **two** sessions: a 6:08am track workout (warm-up +
threshold + cooldown) and a 5:52pm double. Rolling to the day would report one
15.7 mi threshold day that never happened. Rolling to the upload reports five
runs that never happened either.

`RunningLog/RunningLog/App/LogView.swift` already exists and is mounted to
nothing (tab 0 renders `VoiceLogView`). **This is that file, promoted and
corrected.** Do not create a parallel screen.

---

## The three things the current LogView gets wrong

Each one makes the screen show a wrong number.

### 1. It reads a pace column that is empty

`LogRowView` renders `row.pace`, which decodes `workout_pace_per_mile`.

```
rows with distance:               253
  …with workout_pace_per_mile:     31   (12%)
  …with workout_duration_minutes: 249   (98%)
```

**Pace must be computed**, never read:

```swift
/// Pace in seconds per mile, derived. `workout_pace_per_mile` is populated on
/// 12% of rows and must not be trusted as a display source.
static func derivedPaceSeconds(miles: Double?, minutes: Double?) -> Double? {
    guard let mi = miles, mi > 0.05, let min = minutes, min > 0 else { return nil }
    return min * 60 / mi
}
```

Format via `DistanceFormat.paceMMSS(secPerMile:)`. Never inline.

### 2. It shows one row per upload, and an upload is not a run

```
upload rows with distance:  253
distinct days run:          174
  days with 1 upload:       120
  days with 2:               38
  days with 3+:              16
```

Aug 4, in local time:

```
06:08  recovery   1.76 mi  14 min   ┐
06:28  threshold  7.95 mi  48 min   ├─ session 1 · Threshold ×3 · 10.7 mi · 6:38
07:23  recovery   1.00 mi   9 min   ┘
17:52  easy       3.97 mi  30 min   ┐
18:53  easy       1.00 mi   7 min   ┴─ session 2 · Easy ×2 · 5.0 mi · 7:27
```

As five rows it is noise. As one row it is a fiction. As two rows it is what
happened.

### 3. It applies no dedup, so it double-counts

`LogView` renders `TrainingLogStore` rows raw.

```
raw total (all time):                                1661.3 mi
voice rows on a day that also has a GPS row:   18 rows / 126.9 mi
→ overstatement:                                        ~8%
voice rows that are the ONLY record for their day:  37 rows / 313.6 mi
→ real training. Must never be dropped.
```

Jul 18: two rows, both 13.49 mi, one `strava` one `voice_log`. One row, counted
once, words kept.

---

### 4. Everything groups by the UTC calendar day

`workout_date` is `timestamptz`. `Calendar.current.startOfDay` on the decoded
`Date` is correct on device, but any grouping that treats the stored date as a
calendar day in UTC — including `date(workout_date)` in SQL and every edge
function that does it — misplaces evening runs.

```
rows whose UTC day ≠ America/Chicago day:   8 rows / 39.2 mi
rows whose UTC Monday-week ≠ local week:    0   (no Sunday-evening runs yet)
```

The Aug 5 7:01pm easy run is stored `2026-08-06 00:01Z` and reads as an Aug 6
run in UTC. Week totals are intact **only by luck** — one Sunday-evening run
moves a week's mileage. Group in the athlete's local zone, and use the same
zone for the Monday-start week boundary.

---

## The rollup — three steps, in this order

Collapsing them loses information.

1. **Group by local calendar day.**
2. **Day-level voice/GPS dedup** — `LogDedup`'s existing rule, unchanged.
   Must be at the day level, not the session level: on Jul 18 the Strava row
   is stamped 01:38 and the voice memo 06:38, five hours apart, so a
   session-gap test would never pair them.
3. **Split the day into sessions by clock gap.** A new upload joins the current
   session when it starts within **90 minutes** of the previous upload's end;
   otherwise it opens a new one. 90 rather than 60 because Jul 21's 65-minute
   warm-up-to-cooldown gap is one session.

A folded voice row attaches to whichever session is nearest in time.

Totals are invariant across step 3 — splitting sessions must not change any
sum. Verify: the 8-week window reads 505 mi / 52 days / 88 uploads before and
after.

## The dedup rule — adopt `LogDedup`'s verbatim, do not fork it

Use `LogDedup.dedupedByPhysicalWorkout()`'s existing rule **unchanged**:

> Group by calendar day. If the day contains any GPS-source row
> (`LogDedupHelpers.isGpsSource` → `strava · auto_sync · garmin · vital`),
> drop `voice_log` rows from that day's **totals**. Their words, mood and RPE
> survive on the day row. A `voice_log` row with no GPS row that day is a real
> run and is kept whole.

An earlier draft of this doc added a "within 0.1 mi" test. **That was a tenth
matcher** and is removed. `LogDedup.swift` exists to hold exactly one rule.

Add the day-rollup *to* `LogDedup.swift` as a second extension over the same
helpers. Note `strava_backfill` (3 rows) is **not** in `isGpsSource` today —
either add it there or accept it as non-GPS; do not special-case it at the
call site.

**Correction to the file's own header comment.** `LogDedup.swift:28` claims two
consumers. Actual call sites of `dedupedByPhysicalWorkout()`:

```
Analysis/TrainingAnalysisView.swift:802
Training/TrainingPaceAnalysisSection.swift:513, :671
Training/KeySessionStore.swift:287
Training/Analytics/TrainingAnalyticsViewModel.swift:450, :471
```

Four files, six sites, including key-session ingestion. Fix the stale comment
in the same change. Touching this file is not a local edit.

`// PHASE 3` — when `workout_notes` readers land, note-picking switches to the
`run_id` join and the fuzzy branch is deleted. Mark that spot.

### Naming the day, and whose voice it speaks in

Rank by `WorkoutLabel.normalize(_:)`, **never the raw key** — `tempo` and
`interval` are both live in stored rows and `firstIndex(of:)` returns nil for
keys absent from the ladder, which would name a day for its warm-up.

```
recovery < easy < moderate < steady < long_run < progression
        < fartlek < threshold < intervals < long_wo < race
```

Quality set: `threshold · intervals · fartlek · progression · long_wo · race`
(normalized, so `tempo` and `interval` fold in).

Aug 4 carries a memo on the *cooldown* (RPE 3) and one on the *threshold
session* (RPE 7). Walk the intent ranking downward and take the first piece
carrying mood, RPE or audio. **Walk all pieces, including ones folded out of
the totals** — on Jul 18 the folded `voice_log` row is the only carrier of the
words. Picking from the kept set drops them, which is the bug this doc's own
verify step 1 is written to catch.

---

## Layout

Four columns. **Seven does not fit an iPhone** — a first draft of this doc spec'd
`52+52+46+62+30+74` plus gaps = 376pt against 345pt of usable width at 393pt
minus 24pt padding. The prototype is drawn at 393pt so this can't hide again.

| Col | W | Content | Type |
|---|---|---|---|
| Date | 40 | day numeral over `TUE` | `dripDisplay(19)` / eyebrow |
| Session | flex | `WorkoutLabel.display(_:)` + `×N` | `dripDisplay(16)` |
| Mi | 48 | day total, 1dp | `dripStat(14)` |
| Pace | 52 | derived, on the ramp | `dripStat(12)` semibold |

The month lives in the week header, so the date rail carries the weekday only.

**A day's second and later sessions give up the date numeral** and show their
start time instead (`5:52p`, eyebrow, `textTertiary`). The day then reads as one
block led by its date. Sessions sort **chronologically within a day**; days sort
newest-first.

**Mood rides the row's left rule** — a 2pt colored border, the gesture
`Training/JournalLogRow.swift` already uses. It stays off the numeral columns
and costs no width. The full washed pill appears in the expansion.

**Min and RPE move into the expansion.** They are too sparse to earn a column
(see *Empty cells*).

Week header, pinned: `LAST WEEK · 77 MI · 7 DAYS · 2 QUALITY`. Reuse
`LogView.weekHeader` — its tick is **16pt**, not 14. But `headerText`
(`LogView.swift:196`) emits `RUNS`, and these rows are days: extend it to take
a noun and a quality count. Keep the existing `This week` / `Last week` labels.

Totals: **2-up, not 4-up.** `design-system/README.md:112` — *"Never 3-up at this
width — squeezes the numerals."* Miles (with `N days run` beneath) and Avg/week
(with `N uploads` beneath). Use `DripStatStrip` from
`App/DripEditorialPrimitives.swift` — it has **two** call sites
(`HistoryDetailSheet+Editorial.swift:150`, `TrendsThresholdView.swift:62`);
the in-file comment saying "exactly one" is stale.

Expanded row: white card, `--shadow-card`, **radius 12** (README: nothing is
more rounded than 12 except pills). Four-column mini table of the uploads,
sorted by intent so the session sits on top, each with its own pace. Folded
rows render in `textTertiary` ink labelled `· folded in` — **not** at reduced
opacity; `coral-wash` is the only transparency in the system. Then the
`MoodBadge` pill, then the quote, then the flag chip.

### Colour

- **Blue is pace, only pace.** See *The ramp* below.
- **Warm is mood, only mood.** `Color.drip.energized · positive · neutral ·
  tired · struggling · injured` — the tokens are **unprefixed** on `DripColors`;
  there is no `Color.drip.mood*`. Use `MoodBadge(mood:)` for the pill; it
  already does 5px dot + `dripEyebrow(10)` tracking 1.0 + 12% wash. Don't build
  a bespoke unwashed variant.
- **Coral is alert, only alert.** It appears **once in the entire screen**: the
  `1 duplicate row folded in` flag chip. That is alert-shaped. Everything else
  is ink.

**Quality is weight, not colour and not a glyph.** Quality days set in
`dripDisplay` bold at full ink; filler in regular at `textSecondary`. Two
reasons the first draft's coral `✦` was wrong: `design-system/README.md:196`
closes the glyph list to `· ↗ →`, and CLAUDE.md scopes coral to *"niggles,
out-of-zone workload, brand punctuation"* — "this was a threshold session" is a
taxonomy fact, not an alert.

Removing coral from **mileage** (which `LogRowView` paints on every row today)
stands: *"One coral element per visual cluster, maximum."*

**The quote uses an ink hairline, not a coral rule.** README:145 — the 2pt coral
stripe *"is the canonical 'from your coach' treatment… This is the one place a
colored left-border appears in the system. Do not generalize."* This is a diary
quote.

### The ramp

There is **no absolute sec/mi → colour function** in the system, and hardcoding
thresholds would make one colour mean different fitness for different athletes —
the exact thing `anchoredColor` exists to prevent.

```swift
PaceSpectrum.anchoredColor(paceSec:zones:)   // primary — athlete's own zone table
PaceSpectrum.color(forPaceSec:slowSec:fastSec:)  // fallback when zones are nil
```

Call `anchoredColor` with the athlete's `PaceZonesEngine`; when it returns nil,
fall back to `color(forPaceSec:slowSec:fastSec:)` bounded by the visible range's
own slowest and fastest day. The ten stops are one per canonical zone, pale sky
`#93B9D6` (Easy) → navy `#0E1D4E` (Mile).

The pace cell is 12pt text, so the pale end must use **`PaceSpectrum.easyText`
(`#5E93BE`)**, not the Easy stop, which is unreadable at that size on paper.

The prototype's positional interpolation is a stand-in for review only.

### Typography

Eyebrows sit at **`DripTypeFloor.eyebrowSmall` = 10pt minimum** — the floor
exists because *"below 9 the mono face stops being legible for readers who need
the setting at all."* A first draft spec'd 8.5pt. Tracking is a ratio, not a
constant: caption ×0.10em, label ×0.12em, plate meta ×0.14em. Wrap in
`@ScaledMetric(relativeTo: .caption2)`.

All spacing snaps to the 8pt grid (4/8/12/16/20/24/32/40/56). CLAUDE.md already
lists off-grid values as declared drift; do not add a new surface to that list.

Separators: middle dot only. Never `|`, `—` or `/`.

Standalone headline takes a period: **"Every session."**

---

## Empty cells — needs your call before implementation

`docs/conventions/empty-states.md:3`: *"Every empty cell in the UI uses the
empty-state component — **never an em-dash or a blank field**."* CLAUDE.md hard
rule 8 says the same. **There is no compliant per-cell treatment for a dense
table**, and a full `EmptyStateView` per cell is not possible. A hairline
placeholder is also out: `divider` is a border token, and a 15pt divider inside
a cell reads as content.

The route this doc takes: **carry only near-fully-populated columns.** Pace is
~98% populated once derived; Mi is 100%. RPE and Mood are sparse, so they leave
the grid — RPE into the expansion, Mood onto the left rule where absence is the
absence of a marker rather than an empty cell.

That resolves it for this screen. If a sparse column is ever wanted in the grid,
`docs/conventions/empty-states.md` needs an amendment for tabular cells first,
and this doc should cite it. Do not ship the judgement call unwritten.

---

## Data path

No new fetch. `TrainingLogStore.shared` holds the 400-day window, coalesces
concurrent refreshes, and `LogView` already does stale-while-revalidate against
it. Keep all of that. The rollup is a pure transform over `[TodayLogRow]`.

`TodayLogRow` does **not** decode `felt_rpe`. Add it to the struct, to
`CodingKeys`, **and** to the explicit select list in `fetchRecentThrowing`. Do
not switch to a bare `.select()` — that drags `external_streams` (~2 MB/run)
over the wire, PERF-AUDIT finding #1.

`LogView` currently requests **180** days (`:82`, `:93`) and its header string
says "last 180 days" (`:132`). For the `All` range to mean 400, both call sites
move to `TrainingLogStore.windowDays` and the header string changes.

Keep `weekGroups` a stored `@State`. The rollup is strictly more expensive than
today's grouping, so the computed-property scroll trap documented in
`LogView.swift` gets worse, not better.

`LogView`'s **empty** branch (`:135–146`) is a bespoke two-`Text` VStack — no
component, no eyebrow, no CTA. That is a live hard-rule-8 miss you inherit on
promotion. Replace with
`EmptyStateView(variant:eyebrow:title:icon:cta:)` — note `icon` precedes `cta`.
The error branch (`:42–50`) is already correct.

No `selectedTab` gating is needed: the sheet is a **pushed destination** on the
Log tab's `NavigationStack`, so it is not constructed until navigation. (That
rule applies to tab roots, which `MainTabView` builds eagerly in a ZStack.)

---

## Entry point

A ghost control in the Log tab header beside "Log a run", `Image(systemName:)`
plus "Sheet" — an SF Symbol, not a unicode glyph — pushing `LogView()`.

Per CLAUDE.md: *"Before adding a surface, check whether the thing you want
already exists and simply has no door."* This is the door.

---

## Range control

One time control. **4 wk · 8 wk · 12 wk · All.** The only time control on the
screen. `All` = `TrainingLogStore.windowDays`.

---

## Out of scope

- **Planned workouts.** `scheduled_workouts` has **0 rows**. There is nothing to
  show. `workout_reconciliations` holds 223 rows but every one has a null
  `scheduled_workout_id`, so it reconciles nothing today.
- **Editing.** Read-only. Tap expands; it does not open an editor.
- **Deleting the other matchers.** One at a time, totals verified before and
  after, per the spec. This screen adds none — that is the contribution.

---

## Filter bar — tags and search

Sits between the range control and the totals. Tags are **OR'd** with each
other and **AND'd** with the search box, which is how a chip row reads.

| Chip | Matches |
|---|---|
| Key | the quality set — `threshold · intervals · fartlek · progression · long_wo · race` |
| Long | `long_run · long_wo` |
| Threshold | normalized `threshold` (so stored `tempo` folds in) |
| Intervals | normalized `intervals` (so stored `interval` folds in) |
| Doubles | a day's second or later session |

Match on `WorkoutLabel.normalize(_:)`, never the raw key — `tempo` and
`interval` are both live in stored rows, so a raw-key filter silently drops
them. **Key deliberately overlaps Threshold and Intervals.** It is the coach's
word for the same rows and selecting both is harmless under OR; do not try to
make the set disjoint.

**Doubles is only offerable because rows are sessions.** A day-grouped sheet
cannot express this filter at all.

### Counts on the chips

Each chip carries its match count, and a zero-count chip is disabled rather
than hidden — a chip that disappears makes the row reflow and re-reads as a
different control every time you type.

Counts are computed on **range + search, but before tag selection**, so the
numbers hold still while you toggle chips. Computing them post-selection makes
every count drop to 0 or its own value the moment you tap one.

### Search

Case-insensitive substring over the session's label, its note, and the notes
and labels of every piece folded inside it — including pieces folded out of the
totals, so Jul 18's voice-memo words are reachable.

A matched row shows a **one-line snippet with the term marked**. Without it a
filtered list is a set of rows with no visible reason for being there. The
window opens ~14 characters *before* the match, snapped to a word boundary: the
column fits roughly 40 characters, so a centred window ellipses the search term
itself away and the snippet stops explaining anything.

Highlight uses `paperDeep`, not `coralWash` — coral is alert-only.
Selected chips are solid `ink`. **No magnifier glyph**: the system's closed
glyph list is `· ↗ →`, so the clear affordance is a text button and the field
carries a placeholder instead.

### What the filter must not change

- **Pace spectrum calibration.** `FAST`/`SLOW` come from the *range*, not the
  filtered set. Calibrating on matches means the same run reads a different
  colour depending on what else is on screen.
- **Avg / week.** Divide by weeks in the *range*, not weeks containing a match
  — "threshold miles per week of training" is the useful number, not "per week
  that happened to have one".
- **Week groups.** A week with no matches renders nothing, not an empty header.

### Two empty states, not one

A filtered-empty result is a dead end unless it offers the way out, so it
carries a **Clear filters** action; the unfiltered-empty state points at the
range control and Strava instead. Both go through the empty-state component
per `docs/conventions/empty-states.md`.

### The date numeral follows what is VISIBLE

A day's later sessions trade the date numeral for their clock time. That choice
must be made from the **rendered** list, not from position within the day —
filter to Threshold and an evening session can become the first row of its day,
at which point it needs the date back. Deciding this at rollup time leaves rows
with no date at all.

---

## Verify

1. **Jul 18 shows once.** 13.5 mi, the voice memo's words present, flag chip on
   expand. This is the case that catches picking `spoken` from the kept set.
2. **Aug 4 shows as two rows** — `Threshold ×3 · 10.7 mi · 6:38` at 06:08 and
   `Easy ×2 · 5.0 mi · 7:27` at 5:52p. The first carries RPE 7 (the session's,
   not the cooldown's 3). Not one 15.7 mi row.
3. **Aug 8's long run reads 6:38**, not 8:01, with the 2.24 mi / 43 min evening
   walk on its own row at 19:12. If the long run reads 8:01, sessions aren't
   splitting.
4. **Totals are invariant across the session split.** 8-week window: 505 mi /
   52 days / 88 uploads, before and after.
5. **Aug 5's 7:01pm run appears on Aug 5**, not Aug 6. If it lands on Aug 6, the
   grouping is still in UTC.
6. **Pace populated on ~98% of rows.** A mostly-blank column means it is still
   reading `workout_pace_per_mile`.
7. **A stored `mp` / `lt` / `5k` row renders as `MP` / `LT` / `5K`**, not "Run".
   `WorkoutLabel.display` handles this; a hand-rolled map will not.
8. **Range totals match SQL**, and the spec's standing check still returns the
   same 3 groups the sheet folds:
   ```sql
   select user_id, workout_date, round(workout_distance_miles::numeric,1) mi, count(*)
   from training_logs group by 1,2,3 having count(*) > 1;
   ```
9. **Totals unchanged at the six other `dedupedByPhysicalWorkout` call sites**
   after the file is extended. Check before and after.
10. **Scroll 400 days on device.** `weekGroups` stored, not computed.
11. **No em-dash, and no glyph outside `· ↗ →`, in the rendered screen.**
12. **Filter to Threshold: every visible row still shows a date.** A row
    showing only a clock time with no dated row above it is the `leadsDay` bug.
13. **Chip counts do not move when you toggle a chip.** They may only change
    with the range or the search box.
14. **Search `knee` returns 3 sessions** in the 8-week range, each with the word
    visible in its snippet — not ellipsed away.
15. **A stored `tempo` row appears under Threshold**, and a stored `interval`
    row under Intervals. If not, the filter is matching raw keys.
16. **Page never scrolls horizontally at 393pt with a search active.** Grid
    children need `min-width: 0` or the snippet pushes Mi and Pace off-screen.
17. **`mmss` never prints `:60`.** Round the total seconds, then split. 6.1 mi
    in 48 min is 8:00, not 7:60 — flooring minutes and rounding the remainder
    separately breaks for any pace whose seconds land in [59.5, 60).

---

## Data problems this screen will surface

Not bugs in the sheet — it is the first surface honest enough to show them.

- **Jul 24's interval session reads 12:00 /mi** even after splitting. The
  5.75 mi upload carries 69 minutes — wall clock including standing rest, not
  moving time. Session splitting cannot fix this; only `moving_time` from
  `external_streams` can. Several quality rows have this shape.
- **Aug 8 used to read 8:01** — an 18.10 mi long run at 6:38 averaged with a
  2.24 mi / 43 min evening walk. Session splitting fixes this one: the long run
  reads 6:38 and the walk reads 19:12 on its own row. It is listed here because
  every surface that still groups by day has the old number.
- **Warm-ups and cooldowns are auto-typed `easy` or `recovery`**, so `recovery`
  is among the most common labels in the data and means nothing. The rollup
  hides most of it; the taxonomy still needs a pass.
- **`interval`, `intervals`, `tempo`, `threshold` are all live.**
  `WorkoutLabel.display` renders them correctly; anything that *groups* by raw
  `workout_type` still splits them.

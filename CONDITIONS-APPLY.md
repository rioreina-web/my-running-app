# The Conditions — every session, with the weather in it

**Status:** apply doc, 2026-08-17 · rev 5 (one workbook, not four CSVs)
**Prototype:** `the-conditions-prototype.html` (repo root, 68 real sessions
Jun 22 – Aug 17, drawn at 393pt and at 760px)
**Surface:** extends **The Sheet** (`STAT-SHEET-APPLY.md`) rather than adding a
screen. Same rollup, splits on every row, three new column families and an export.
**Depends on:** `STAT-SHEET-APPLY.md` shipping first. This doc assumes its
session rollup exists.

---

## What this adds

The Sheet answers *what did I run*. It cannot answer *how hard was the fast
part* or *was that pace slow or was it 78° with a 74° dew point*. Five
additions:

0. **Splits on every session.** Every row opens, easy runs included. This is the
   floor, not a feature of quality sessions — see §0.
1. **Fast segments with their own heart rate.** A rep is a row, not a footnote.
1b. **The voice memo.** The session as you described it, above the reps the watch
   recorded — see §1b.
2. **Heat adjustment.** Temperature + dew point, converted to a pace penalty, so
   a hot 6:42 and a cool 6:23 read as the same fitness.
3. **Elevation and volume** promoted from the expansion to the grid and the
   week header.
4. **Export.** One workbook, five tabs, from the visible set.

Mood, mileage and pace already exist in The Sheet and are unchanged here.

---

## 0 · Every session opens · two depths, one sheet

**One sheet. Every training session is a row and every row expands.** The first
draft only gave the 16 quality sessions anything worth opening, which made the
other 52 look like they had been left out. They had not — they just had nothing
underneath them.

Every session now carries a **splits** table: distance, time, pace, a pace
profile bar and heart rate per split. 613 splits across the 68 sessions.

The two depths, stated on the screen rather than left for the athlete to infer:

| | What opens |
|---|---|
| **Key session** (lap button pressed) | **Pace sheet of the reps** on top — per-rep distance, time, pace, avg and max HR — then the full splits below it |
| **Every other run** | Splits only. There are no reps to pull out |

A `How to read this` block sits above the list and says exactly that, in those
words. Two depths with no explanation reads as missing data; two depths with one
sentence of explanation reads as a system.

### Where splits come from

```
laps.count > 1   ->  use the laps verbatim          (49 uploads)
otherwise        ->  cut mile splits from `distance` stream   (37 uploads)
neither          ->  say so in prose                 (9 uploads, all manual)
```

37 of Rio's 86 uploads come back from Strava as a **single lap** — most easy runs
do. Those are the runs that made the sheet look empty, and they are exactly the
ones that need the stream cut. Fetch those streams at **resolution 200**, not
1000: mile splits need one sample every ~13 s, and the higher resolution is 5×
the payload for no extra precision.

Keep a trailing partial split when it is over **15% of the unit** and drop it
otherwise, so a 6.01 mi run shows six splits rather than six and a 60-foot
crumb. Mark the partial in the row.

The splits table names its own unit: *"as the watch lapped them"* or *"cut at
each mile from the pace stream"*. A run whose auto-laps are kilometres shows
0.62 mi splits, and without the label that reads as a bug.

The **pace profile bar** is the blue ramp again, scaled across that session's own
fastest and slowest split. It turns a column of numerals into a shape you can
read at a glance — a progression run leans one way, a fade leans the other. Floor
it at 12% width so the slowest split is still a visible mark rather than nothing.

### The filter must never look like missing data

The chip row is the other reason the sheet read as incomplete: a chip is easy to
switch on and easy to forget, and a filtered list looks identical to a broken
one.

- **`All sessions` is a chip**, first in the row, carrying the range count and
  pressed whenever no filter is active. There is always a visible way back.
- A line under the controls states it outright: *"All 68 sessions in range. Every
  one opens into its splits."* When a filter is on it becomes *"Showing 18 of 68
  sessions"* with a **Show all 68** action beside it.

This is the one place coral appears above the fold, on that action. It is
alert-shaped: something is hiding rows from you.

---

## 1 · Fast segments

### The definition

> A **fast segment** is a contiguous span held at or faster than the athlete's
> fast cut, for at least a minute.

Fast cut = **LT pace × 1.06**, from `PaceZonesEngine`. For Rio that lands at
**6:15/mi**: threshold reps run 5:15–5:40 and LT sits near 5:50, so 6:15 keeps
every rep and excludes every long run cruise. The prototype hardcodes 375 s/mi
in `DATA.meta.fast_cut_s_per_mi`; production must derive it, because a fixed
number means one colour and one label mean different fitness for different
athletes — the same reason `anchoredColor` exists.

Fall back to `steady + 5%` when zones are nil. Never ship a hardcoded cut.

### Two sources, and the rule that picks between them

This is the part that is easy to get wrong. **Laps are not reps.**

```
19627365635  "5x4 min"   1216m/240s · 148m/97s · 1205m/241s · 98m/112s · …   MANUAL
19087453621  "Ks"        1000m/277s · 1000m/257s · 1000m/253s · 1000m/247s   AUTO
19696011909  10x1000m     994m/197s ·  78m/67s · 1007m/194s ·  73m/66s · …   MANUAL
```

Rows 1 and 3 are rep sessions. Row 2 is a 17.8 mi continuous run that the watch
auto-lapped every kilometre. All three are "uniform ~1000m laps." Distance alone
cannot tell them apart.

**What separates them is the short laps between the efforts.** A manually lapped
session interleaves recovery laps; an auto-lapped run is contiguous.

```
lapKind(activity):
  if laps.count < 3                                    -> .single
  if laps[1..<count-1].filter { $0.distance < 400 }.count >= 2  -> .manual
  core = laps.dropLast().filter { $0.distance > 100 }
  if core.count < 3                                    -> .single
  uniform = stddev(core.distance) / mean(core.distance) < 0.03
  isSplit  = |mean - 1000| < 40 || |mean - 1609.344| < 60
  return (uniform && isSplit) ? .auto : .manual
```

Two short laps, not one: activity `19269767324` carries a single spurious 12 m
lap inside a clean 1000 m auto-split run, and a one-lap test misclassifies it.

- **`.manual`** → each lap that clears the cut is a rep. `avg_hr` and `max_hr`
  come off the lap directly. Minimum **25 s / 150 m** — a 200 is a real rep and a
  60-second floor deletes the entire `200s` session (8 reps at 4:14/mi).
- **`.auto` / `.single`** → detect from the `velocity_smooth` stream. Threshold
  crossing, **25 s tolerance** for a dip inside an effort, minimum **90 s /
  400 m**. The coarser floor is because Strava's downsampled stream is roughly a
  7-second sample; at 60 s it manufactures reps out of traffic lights.

Segments carry their source. The expansion says which: *"read from the watch
laps you pressed"* vs *"read from the pace stream, since this run was
auto-lapped."* The athlete should never wonder why one session shows 10 clean
reps and another shows 3 ragged ones.

### Verified against real sessions

18 of 68 sessions carry fast segments, 111 reps total. The other 50 carry splits.

| Date | Session | Detected | Source |
|---|---|---|---|
| Aug 11 | 10×1000m | 10 reps · 5:18 avg · HR 164 | manual laps |
| Aug 06 | 5×4 min | 5 reps · 5:20 avg · HR 155 | manual laps |
| Jul 24 | 200s | 8 reps · 4:14 avg · HR 136 | manual laps |
| Jul 21 | 6×1 mi | 6 reps · 5:28 avg · HR 166 | manual laps |
| Aug 08 | long run | 10 surges · 6:19 avg · HR 160 | stream |
| Jun 27 | "Ks" 17.8 mi | 3 fast spans · 6:24 · HR 161 | stream |

### HR is the point

Per-rep HR is what the session sheet cannot show. Aug 11 reads 157 → 165 → 161 →
162 → 165 → 166 → 165 → 165 → 166 → 170 across ten reps at a near-constant 5:18.
Flat pace, climbing heart rate, in 78°/75° air. That is a decoupling story, and
it only exists once reps are rows.

Render HR as **numeral plus a hairline bar** scaled across the session's own rep
range. The bar is `ink-3`, not a colour — blue is pace, and a rep's HR is not a
pace. A rep with no HR prints `not recorded`, never a blank cell and never an
em-dash (hard rule 8).

---

## 1b · The voice memo · intent, above execution

Until now the sheet consumed exactly two fields out of the voice log — `mood`
and `felt_rpe` — and threw away everything else the transcription pipeline
already produces. Three fields go back in.

| Field | What it is | Coverage in the 8-week block |
|---|---|---|
| `workout_notes` | **The session as the athlete described it.** *"Intervals: 10x1K @ 3:15–3:23 pace w/ 60s rest… Threshold pace was the goal"* | 14 sessions |
| `rpe_pull_quote` | Their own sentence, verbatim | 16 sessions |
| `rpe_tags` | Closed-vocabulary condition words: `["humid","hilly","strong"]` | 15 sessions |
| `cleaned_notes` | The cleaned summary of the whole memo | 19 sessions |

### Why `workout_notes` is the important one

**It is the only record of intent anywhere in the system.** `scheduled_workouts`
has 0 rows and every one of the 223 `workout_reconciliations` has a null
`scheduled_workout_id`, so nothing else in the database knows what a session was
*supposed* to be. The athlete already says it out loud into the memo; the
pipeline already extracts it; nothing renders it.

So the memo block sits **directly above the pace sheet**, and intent and
execution read as one pair with no scrolling between them:

```
AS YOU CALLED IT
  Intervals: 10x1K @ 3:15-3:23 pace w/ 60s rest
  Threshold pace was the goal
                                            ← nothing between these
PACE SHEET · THE REPS
  1   0.62   3:17   5:19   HR 157
  2   0.63   3:14   5:10   HR 165
  …
```

3:15–3:23 per 1K is 5:14–5:26/mi. The detected reps ran 5:10 to 5:30. Reading
that takes no computation — it takes the two blocks being adjacent.

**Do NOT parse the plan into structured targets.** It is free text an LLM wrote
from speech: `"1600m @ 5:08 + 2×800m @ 2:33"`, `"6 minutes steady, 2 minutes
easy"`, `"Warmup: 3 miles"`. A parser that gets it right 80% of the time and
silently invents a target the other 20% is worse than no parser, because a wrong
"you missed your target" is a claim about the athlete's training. Render it
verbatim in mono, keep its line breaks, and let the reader do the comparison.
Computed planned-vs-actual is a later step and needs its own doc and its own
eval, per hard rule 3.

### Matching a memo to a session

Match on **local start time within 5 minutes**, and walk **every piece** of the
session including warm-ups and cooldowns. Aug 4 carries two memos: RPE 3 on the
cooldown and RPE 7 on the workout. Rank by `(felt_rpe, has_plan)` and let the
session's own memo lead; keep the rest in `memos[]` rather than discarding them.

`workout_date` is `TIMESTAMPTZ` stored UTC. Convert to the athlete's local zone
before matching, the same trap §0 of `STAT-SHEET-APPLY.md` documents.

### Rendering

- **Plan** — mono, `paper-deep` well, line breaks preserved. It is a prescription,
  and prescriptions are monospaced.
- **Quote** — italic body with a **1px ink hairline** on the left. Not the coral
  stripe: `design-system/README.md:145` scopes that to *"from your coach"* and
  says explicitly not to generalise it. This is a diary entry.
- **Tags** — hairline outline pills, `ink-2`, uppercase mono. No fill and no
  colour: they are conditions the athlete named, not a rating.
- **Summary** — the cleaned memo as plain body copy, suppressed when it is the
  same string as the quote.
- **Row meta** — the plan's first line, stripped of its `Intervals:` /
  `Workout:` prefix, so the intent is visible before you tap.

The `Voice memo` filter chip keys on *a memo existing*, not on `mood` being
non-null. One Jul 18 entry has a quote and an RPE but no mood, and a
mood-keyed filter loses it.

### Audio stays out

`audio_url` is populated on 22 rows, and the sheet says `recorded` but does not
play anything. A dense scannable table is not an audio player, and an
inline `<audio>` per row is 68 network handles on a screen built to scroll.
Tapping through to the journal entry is the right affordance; this sheet is a
reader.

---

## 2 · Heat adjustment

### The sum is math, not a label

**The UI never prints "T+D".** Every surface shows the two numbers a runner
actually checks before going out: **temperature and dew point**, as
`78° · dew 75°`. The sum exists only inside `heatPenalty(_:)`.

This is not cosmetic. "T+D 153" is a coach's shorthand that requires knowing the
table to decode, and a number with no unit and no referent reads as a score the
app invented. `78° with a 75° dew point` is the same information, needs no
decoder, and matches what the athlete saw on their phone that morning.

Applies everywhere:

| Surface | Shows |
|---|---|
| Row meta | `78° · dew 75°` plus the heat-load ticks |
| Week header | `AVG 84° · DEW 72°` |
| Expansion | Temp · Dew point · Humidity · Heat load · Pace cost. No sum cell |
| Totals | `dew point averaged 72° · 45 runs above 70°` |
| Filter chip | `Dew 74°+`, not a sum threshold |
| Prose | *"At 78° with a 75° dew point the heat cost about 10 seconds a mile"* |
| CSV | `temp_f`, `dew_point_f`, `heat_load`, `heat_penalty_pct`. No `temp_plus_dew` |

**Dew point is the filter and the headline, not temperature.** It is the number
that actually governs evaporative cooling, and it is the one that separates a
tolerable 90° afternoon from a brutal 78° morning. Rio's block makes the case:
Aug 9 ran at **97° with a 68° dew point**, Aug 10 evening at **92° with 68°**,
and both cost less than the 78°/75° morning of Aug 11.

### The model

Coach Mark Hadley's temperature + dew point table
([Maximum Performance Running](http://maximumperformancerunning.blogspot.com/2013/07/temperature-dew-point.html)),
the method runners already use. Sum temperature and dew point in Fahrenheit:

Sum temperature and dew point internally; display neither the sum nor this
table to the athlete.

| Sum (internal) | Penalty | Heat load shown |
|---|---|---|
| ≤ 100 | none | none |
| 101–110 | 0 → 0.5% | light |
| 111–120 | 0.5 → 1.0% | light |
| 121–130 | 1.0 → 2.0% | moderate |
| 131–140 | 2.0 → 3.0% | moderate |
| 141–150 | 3.0 → 4.5% | heavy |
| 151–160 | 4.5 → 6.0% | heavy |
| 161–170 | 6.0 → 8.0% | severe |
| 171–180 | 8.0 → 10.0% | severe |
| > 180 | hard running not recommended | extreme |

The **Heat load** column is what the athlete sees in place of the sum: tick
glyphs, `·` through `· · · · ·`, ink only. Same reason as before — heat is a
condition, not an alert, so it gets no hue.

**Interpolate linearly between the endpoints, do not step.** The published table
gives each 10-degree band a range precisely because the penalty rises through
it. A step function makes T+D 150 and 151 differ by 1.5% while 141 and 150 are
identical, and the athlete sees a cliff that does not exist in the weather.

```swift
/// Fractional pace penalty for a temperature + dew point sum, degrees F.
static func heatPenalty(tempPlusDew td: Double) -> Double {
    guard td > 100 else { return 0 }
    let breaks: [(Double, Double)] = [(100,0),(110,0.005),(120,0.010),(130,0.020),
                                      (140,0.030),(150,0.045),(160,0.060),
                                      (170,0.080),(180,0.100)]
    for (a, b) in zip(breaks, breaks.dropFirst()) where td <= b.0 {
        return a.1 + (b.1 - a.1) * (td - a.0) / (b.0 - a.0)
    }
    return 0.100 + 0.002 * (td - 180)      // extend the final slope; flag it
}
```

**Cool equivalent pace = actual pace ÷ (1 + penalty).** Adjusting toward faster,
because the heat cost you time you would not have lost in cool air.

### Rep sessions take half

From the same source: *"for repeat workouts… use half the continuous run
adjustment percentage, as the body has a chance to cool somewhat during the
recovery between repeats."*

Halve when the session is `.manual`-lapped **and** carries ≥ 3 reps. Both
conditions: a stream-detected long run with surges is continuous running and
takes the full penalty. The expansion says so in words — *"Halved, because a rep
session lets the body cool between efforts"* — because an unexplained
differently-sized number in the same column reads as a bug.

### Weather source, and the run that must not get any

Hourly temperature and dew point for the run's **local start hour** at the run's
own coordinates. The prototype uses the [Open-Meteo archive
API](https://archive-api.open-meteo.com/v1/archive) (free, no key, hourly back
to 1940), which is the right thing for the historical backfill regardless of
what the live path uses.

`fetch-workout-weather` already exists as an edge function. Extend it rather
than adding a second weather path — but note it is one of the readers still
pointed at the dead `user_profiles` table (CLAUDE.md, known issues), so it needs
the `athlete_settings` repoint in the same change.

**A run with no GPS gets no heat adjustment.** Detect it as *zero elevation gain
and `elapsed == moving`* — that is the shape of every manual and treadmill
upload in the set. Seven of Rio's 68 sessions match, including two Treadmill
entries. Attributing 78°/75° outdoor air to a treadmill run is not a rounding
error, it is a wrong number, and it silently corrupts the weekly adjusted pace.
The row prints `indoor · no weather` and the expansion explains it. Do not
fall back to the athlete's home coordinates.

### What the adjustment must not do

- **It does not rewrite the recorded pace.** Actual pace stays the headline;
  cool equivalent sits beside it in `ink-2`. The athlete ran what they ran.
- **It does not adjust heart rate.** HR in heat is elevated for reasons this
  model does not describe, and pretending otherwise invents data.
- **It does not touch training-load math.** ACWR, TLS and fitness stay on
  recorded values until that is a separate, deliberate decision.

---

## 3 · Layout

The Sheet's four columns are unchanged: `Date · Session · Mi · Pace`. Everything
new rides a **second meta line** under the row, mono, 10pt, `ink-2`, separated by
spaces rather than pipes:

```
HR 149   10× fast 5:18 · HR 164   213 ft   78° · dew 75° · · ·   cool 6:46   positive   3 uploads
```

Middle dot only, per the closed glyph list (`· ↗ →`).

### Heat gets no colour

The three-palette rule is absolute: blue is pace, warm is mood, coral is alert.
Heat is none of those. A hot day is a **condition**, not an alert — coral would
say "something is wrong with this run," and nothing is.

So heat renders as **the two temperatures plus tick glyphs**: `78° · dew 75°`
followed by `·` light, `· ·` moderate, `· · ·` heavy, `· · · ·` severe,
`· · · · ·` extreme. Ink only. The ticks read as a small intensity meter and
cost no new hue, and they carry the load the hidden sum used to.

The **cool-equivalent pace does take the blue ramp**, because it is a pace.
Same `PaceSpectrum.anchoredColor`, same calibration.

### Ramp calibration

Calibrate on the **5th and 95th percentile** of the range's paces, not min and
max. Jul 24's `200s` session records 11:59/mi — wall clock including standing
rest, the known data problem The Sheet's doc already lists. On a min/max
calibration that single row stretches the ramp so far that every real run
collapses into two adjacent stops. Percentiles clamp it; the outlier still
renders, at the pale end, correctly.

Calibrate on the **range**, never the filtered set (The Sheet's rule, unchanged).

### Weekly volume

A bar per Monday-start week above the list: miles as ink bars, week label
beneath, numeral above. **Partial weeks hatch rather than render short** — a
6-mile bar next to a 77-mile bar reads as a collapse in fitness when it is
Monday. The hatch is `ink-3` diagonal on paper, no new colour.

Give the fill its own flex track inside the bar. If the numeral and the label
share the bar's height box, the tallest bar is squeezed by ~30px of text and the
bars stop being proportional — 52 and 77 render nearly equal. This was a real
bug in the first draft of the prototype.

Week header carries the volume line:
`WEEK OF AUG 10 · 71 MI · 7 DAYS · 2 QUALITY · 8.4 H · 1,729 FT · AVG 84° · DEW 72°`

---

## 4 · Export · one workbook, five tabs

**A CSV holds exactly one table.** Four related tables meant four downloads, four
filenames in a Downloads folder, and nowhere to say how they join or what a
column means. The export is now **one `.xlsx`**.

| Tab | Rows | Contains |
|---|---|---|
| **Read me** | prose | What each tab is, how the heat adjustment works, and the four numbers not to trust. First tab, coral tab colour |
| **Sessions** | 68 | One row per session: the whole row plus every heat field plus the voice memo (`planned_workout`, `quote`, `tags`, `memo_summary`) |
| **Splits** | 613 | Every split of every session, with `is_fast_segment` so reps join to the splits they sit inside |
| **Fast segments** | 111 | One row per rep, with per-rep heart rate |
| **Weeks** | 9 | Mileage, days, quality count, fast miles, hours, elevation, avg pace, `partial_week` |

**The weekly rollup carries no weather.** An average dew point across a week is
a number with no decision attached to it: heat acts on a run, not on a week, and
the per-session temperature and dew point already say everything the average
would. The week line is volume — miles, days, quality, hours, elevation — which
is what a week is for.

Filename carries the range end date. The export follows the **visible** set, so
filtering to fast segments and exporting gives a 18-row Sessions tab.

### The Read me tab is the deliverable, not decoration

A spreadsheet handed to a coach, a physio, or your future self is read without
you in the room. Every non-obvious decision this feature makes is invisible in
the cells: that a session is not a day, that Jul 24's 11:59/mi is wall clock,
that a treadmill run gets no heat adjustment, that short-rep heart rate lags.
Those go in prose on the first tab, in the athlete's language, not in a column
header.

It also carries the join key sentence — *"`is_fast_segment` marks a split that
is also a fast segment"* — which is the one thing a reader cannot infer.

### Rules that still matter

- **Both formatted and raw for every pace.** `pace` = `6:42`, `pace_sec_per_mi`
  = `401.7`. `m:ss` does not sort in a spreadsheet and raw seconds do not read;
  ship both rather than choosing wrong. Say so in the Read me.
- **Freeze the header row and turn on autofilter** on all four data tabs. A
  613-row sheet with a scrolling header is unusable.
- **Header row is bold on `paper-deep`**, body is Arial 10. Match the document
  conventions, not the app's editorial type — this file gets opened in Excel,
  not in Post Run Drip.
- **Numbers are numbers.** Miles, seconds, heart rate and percentages write as
  numeric cells with a format string, never as strings. A distance column that
  will not `SUM` is a broken export.
- **No formulas.** This is a data extract, not a model, so there is nothing to
  recalculate and nothing to break on open.

### Writing it

Server-side or in the app, use a real library. The prototype ships a **~120-line
inline writer** (`xlsxlite`) rather than pulling SheetJS from a CDN, because an
export that needs the network to produce a local file is the wrong shape, and
because the prototype has to run from a `file://` URL with no connection. An
xlsx is a ZIP of XML and ZIP permits store-only, so the whole format reduces to
string building plus a CRC32.

Two things that will bite whoever reimplements it:

- **Strip control characters before writing.** Excel refuses to open a file with
  a raw `\x00`–`\x1F` in any inline string, and voice-memo text is the field
  most likely to carry one.
- **Use `inlineStr`, not a shared-string table**, unless you want to maintain the
  string index. The file is bigger and nothing else changes.

The store-only prototype file is ~500 KB against ~75 KB for a compressed one.
Production should deflate.

On iOS this is `UIActivityViewController` over a file written to the temp
directory. One file, one share sheet.

---

## Data path

No new fetch for sessions — same `TrainingLogStore` window The Sheet uses.

Two new stores:

- **Laps and streams.** Neither is in `training_logs` today. `external_streams`
  exists but PERF-AUDIT finding #1 is that selecting it drags ~2 MB per run over
  the wire, so it must never join the sheet's list query. **Fetch lazily, on
  row expansion, and cache by activity id.** The grid needs only the four
  session-level rollups (`fast_reps`, `fast_mi`, `fast_pace`, `fast_hr_avg`),
  which should be computed once at ingest and stored on the row.
- **Weather.** Cache per `(activity_id)`, not per `(date, hour)` — two runs on
  the same morning in different places have different weather, and Rio runs
  doubles.

Compute fast segments **at ingest**, in `post-run-reconciliation`, not at read
time. Detection is deterministic and the input never changes; recomputing a
stream scan on every scroll is the same mistake as The Sheet's computed
`weekGroups` property, one layer down.

---

## Verify

0. **All 68 rows render on first load with no chip pressed**, and 47 of them are
   Easy. Count them in the DOM, not by scrolling — this is the regression that
   made rev 1 look like a key-sessions-only sheet.
0b. **Every session with GPS opens into splits.** 61 of 68; the 7 without are the
   manual and treadmill entries, and each says why in prose.
0c. **A stream-cut 6.01 mi run shows 6 splits**, not 7 with a 60-foot tail.
0d. **Aug 11 shows `Intervals: 10x1K @ 3:15-3:23 pace w/ 60s rest` immediately
   above its ten detected reps**, with nothing between the two blocks.
0e. **Aug 4 leads with the RPE 7 workout memo, not the RPE 3 cooldown memo**, and
   both survive in `memos[]`.
0f. **Jul 18 is caught by the `Voice memo` chip** despite having a null mood.
1. **Aug 11 shows 10 reps**, 5:10–5:30, HR climbing 157 → 170. Fewer than 10 means
   the manual-lap branch is not firing; more means the recovery laps are being
   counted.
2. **Jul 24 `200s` shows 8 reps at ~4:14/mi.** Zero reps means the 60-second
   floor is still in place on the lap branch.
3. **Jun 27's "Ks" shows stream-detected spans, not 29 reps.** 29 means uniform
   1000 m auto-splits are being read as a rep session.
4. **`19269767324` classifies `.auto`** despite its stray 12 m lap. One short lap
   must not flip the branch.
5. **Aug 15's Treadmill shows `indoor · no weather`** and no adjusted pace. A
   temperature on a treadmill row means the no-GPS test is not running.
6. **Weekly `heat_adj_avg_pace` excludes the no-GPS sessions** from both
   numerator and denominator.
7. **A rep session's penalty is exactly half** the continuous penalty in the same
   air. Aug 11 at 78°/75°: continuous 5.1%, halved 2.55%.
8. **A one-degree change in dew point moves the penalty ~0.15%, not 1.5%.** A
   cliff means the table is stepped instead of interpolated.
8b. **The string `T+D` appears nowhere in the rendered screen or any CSV header.**
   Grep the built output, not just the source.
9. **The pace ramp does not collapse when Jul 24 is in range.** Compare the
   4 wk and 8 wk views: the same Aug 11 row must keep the same colour.
10. **Bars are proportional.** The 52-mile bar is 68% the height of the 77-mile
    bar, measured, not eyeballed.
11. **Session totals are invariant** across every addition here: 512.8 mi,
    68 sessions, 86 uploads, before and after.
12. **The workbook opens in Excel and in LibreOffice** with five tabs, intact
    characters, and a `miles` column that sums.
12b. **Sorting Sessions by `pace_sec_per_mi` orders correctly**; sorting by `pace`
    does not, which is why both ship.
13. **Export respects the filter.** Filter to fast segments, export, and the
    Sessions tab has 18 rows.
13b. **The week header and the Weeks tab show no temperature or dew point.**
14. **No em-dash and no glyph outside `· ↗ →`** in the rendered screen.
15. **No horizontal scroll at 393pt** with a session expanded.

---

## Out of scope

- **Adjusting training load for heat.** The adjusted pace is displayed, not
  consumed. Feeding it into ACWR or fitness is a separate decision with its own
  doc.
- **Wet bulb globe temperature.** More correct in principle, needs solar
  radiation and wind, and no athlete reads runs in WBGT. Temperature and dew
  point are the two numbers runners already check.
- **Forecast.** This is a ledger of what happened. Pre-run heat guidance is a
  different surface and would need the `AI advises, never acts` guardrails.
- **Editing segments.** Read-only, like The Sheet.

---

## Data problems this will surface

Not bugs in the screen. It is the first surface honest enough to show them.

- **The dew point averaged 72° across the block and 45 of 68 runs were above
  70°.** There is no cool-weather baseline in this data at all. Volume-weighted,
  the recorded average is 7:17/mi and the adjusted average is 6:57 — **19 s/mi**,
  which is the difference between reading this block as a plateau and reading it
  as a build.
- **Jul 24's session pace is 11:59/mi** and always will be until `moving_time`
  comes off the streams. Its *reps* are correct at 4:14; only the rollup is
  wrong. Several quality sessions have this shape.
- **Rep HR lags on short reps.** Jul 24's 200s average 136 bpm because a 32-second
  rep ends before heart rate catches up. The number is right and the intuition it
  invites is wrong. Do not add a "corrected" HR; if this needs solving it needs
  a lag model and its own doc.
- **Mood covers 18 of 68 sessions, but a memo covers 19.** The mismatch is the
  Jul 18 entry: quote and RPE present, mood null. Any surface keyed on `mood`
  loses it. Key on the memo.
- **`workout_notes` is 14 of 68 and is the highest-value sparse field in the
  database.** Every one of those 14 is a session where the app can show intent
  against execution. Prompting for it after key sessions — already the decided
  behaviour in the 2026-07-03 adaptive-builder notes — would raise coverage
  cheaply.
- **One evening "run" is a 19:24/mi walk** (Aug 8, 2.2 mi). It carried a brief
  fast span, so a naive label rule called it `Steady`. Anything slower than
  11:00/mi that was not lap-structured is labelled `Walk` before any other rule
  runs. Volume math still counts it, which is a separate question worth asking.
- **`felt_rpe` is null on the three most recent logged sessions.** Worth checking
  whether the voice-log RPE extractor regressed in August.

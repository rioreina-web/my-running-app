# The day sheet gets the workout and the log

**Applied:** 2026-08-18 · directly to working tree
**Scope:** the day sheet behind Trends › PACE › OVER TIME (`SignalDaySheet`).
**Not compiled here** — build in Xcode.

---

## The problem, from the screenshot

Tap a bar in OVER TIME and the sheet says: MONDAY · AUG 17 · 10.0 mi · Easy 8.0
· Moderate 2.0 — and then stops. Two thirds of the sheet is empty paper.

Everything on that sheet came from `SignalDay`, which is the chart's own model:
miles per pace zone, mood, a niggle count. It knows the *shape* of the day and
nothing about the day. The two questions a runner has when they tap a day —
**what was the session** and **what did I say about it** — were both already
answered elsewhere in the app, and the sheet simply never asked.

## What it shows now

Under the existing pace breakdown, in reading order:

**THE WORKOUT** — one block per run on the day:

- type chip · source · time of day, then distance · pace · moving time;
- **THE WORKOUT** — the athlete's own description, via `TheWorkoutBlock`. Same
  block, same editor, same `workout_notes` column as the journal entry and the
  receipt, so an edit made from Trends shows up in the Log;
- **WHAT THE PARSER READ** — `parsed_structure`: the pattern ("6×800m @
  threshold"), work distance, average work pace, peak sustained pace, and the
  parse's confidence, coloured coral below 60%;
- **SHOW THE SPLITS** — `WorkoutRepReceiptView(placement: .embedded)`, the same
  rep receipt the journal entry embeds: rep chart, HR, splits, telemetry.

**THE LOG** — one block per memo: play the recording (`MemoPlayerRow`), the
mood word, and the transcript in full. No AI annotation — the log is record.

The sheet scrolls now. A fixed `VStack` clipped everything below the fold at
the `.medium` detent.

## Two rules this deliberately keeps

**The parser never speaks in the athlete's voice.** `parsed_structure.pattern`
is the parser's read of a GPS trace. `TheWorkoutBlock` documents why it must
never fall back to it — showing a guess under "THE WORKOUT" launders it into
the athlete's own words. So the pattern gets its own eyebrow, its own card, and
its confidence on screen next to it.

**Receipts are expensive; they load lazily on a multi-run day.** A receipt
pulls per-second streams — up to ~2 MB per run, the largest single source of
screen-load lag in `PERF-AUDIT-2026-08-10.md`. A one-run day (the common case)
opens its receipt immediately. An AM/PM day starts collapsed and builds each
receipt only when it's opened.

## Files

### `RunningLog/Trends/SignalDayDetail.swift` — new

`SignalDayDetailModel` (the day query) plus `SignalDayDetailSections` and the
two blocks. The only genuinely new code is the query and the stacking order;
every renderer is one the app already ships.

The day query is two plain requests, not one nested `or(...)`: rows whose
`workout_date` falls inside the local day, and rows with a null `workout_date`
whose `created_at` does (a memo with no run attached). A timestamp inside an
`or` filter needs quoting the client doesn't do, and a silently-empty day is
precisely the failure this sheet is fixing. Rows decode through `Failable` so
one malformed row costs one row, not the whole day.

The day boundary is `Calendar.current.startOfDay`, matching
`SignalService.build` — the rows listed are the rows that made the bar.

`runs` and `memos` deliberately overlap rather than partition: since the
2026-08-05 picker fix a memo recorded against a synced run lives on that run's
own row, so one row is legitimately both.

### `RunningLog/Trends/PaceSignalView.swift`

`SignalDaySheet` body split into `body` (a `ScrollView`) and `content` (what
was there before), plus a `@State` model loaded in `.task` and the new sections
appended.

## Verify

1. Trends › PACE › OVER TIME, tap **Mon Aug 17** (10.0 mi, two runs). Expect
   the pace breakdown, then THE WORKOUT with two run blocks — both collapsed —
   then THE LOG.
2. Tap **SHOW THE SPLITS** on one. The rep receipt should draw inline; the date
   headline and a second THE WORKOUT should NOT appear (that's `.embedded`).
3. Tap a day with **one** run. Its receipt should already be open.
4. Tap **Tue Aug 18** (intervals, "struggling"). WHAT THE PARSER READ should
   show the pattern and the work pace; the memo should play and read.
5. Tap a **rest day**. "Rest day · No runs logged." then "Nothing logged on
   this day." — no spinner left running.
6. Edit THE WORKOUT here, close the sheet, open the same run from the Log tab.
   The text should be there. (One column, one editor — that's the point.)
7. A day with a memo and no run: THE LOG only, no empty workout section.

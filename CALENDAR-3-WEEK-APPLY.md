# Calendar · slice 3 — week rows

*iOS. Depends on slice 1. Independent of slice 2 — either can ship first.*

---

## What this gives you

The week view from `calendar-month-prototype.html` (flip the Month | Week segment). Seven rows, one
per day, each carrying session name, volume, pace-zone bar, pace, time, climb, sleep, HRV and a
niggle word. Then volume-by-pace for the week, a recovery chart, and the pattern cards (slice 4).

**Rows, not columns.** A month cell only has to be a glyph. A week has room, and rows are the only
shape that fits per-day detail on one line.

---

## Paste this to Claude Code

> Read `CALENDAR-3-WEEK-APPLY.md` in the repo root, then open `calendar-month-prototype.html` and
> click the WEEK segment to see the target. Then read
> `RunningLog/RunningLog/Training/Analytics/TrainingTabView.swift` (the `TrainMode` enum and
> `scopeToggle`) and `TrainingCalendarSection.swift`.
>
> Build the week view as new files and wire it into the existing `scopeToggle` — the tab already has
> a `WEEK · MONTH · BLOCK` control, so do not add a second segment. Make one edit to
> `TrainingTabView.swift` to route the WEEK scope at `.calendar` mode to the new view.
>
> Sleep and HRV do not exist in this app yet — build every row so it renders correctly with those
> values absent, and prove it by running with the fields nil. Do not stub fake numbers.
>
> Use `Color.drip` tokens only. Show me simulator screenshots of the week of 20 July and the week of
> 18 May before calling it done.

---

## The row

```
▎ M   Easy                                        10.9 km
  20  ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░
      4:50/KM  53 MIN  62 M ↑  SLEEP 7.8H  HRV 81
```

| Element | Rule |
|---|---|
| Left edge, 3 pt | Mood colour, full row height. Rest days carry it. |
| Date block, 30 pt | Weekday initial above the numeral |
| Session name | Key session structure (`6x1mi`) when present, else `Long run` / `3 × easy` / `Easy` / `Rest`. Coral dot prefix on key days. |
| Volume bar | **Width ∝ that day's volume** against the week's biggest day. **Segmented by pace zone.** |
| Meta line | Pace, time, climb, sleep, HRV, niggle word — in that order, wrapping |
| Right | Day total |

**This is where the pace spectrum belongs.** The bar is wide enough to read segments, and a week is
the scale at which "how much of this was fast" is a real question. 21 July reads half easy / half MP;
24 July shows its navy sliver of 200s. The same encoding rolls up into the week's volume-by-pace bar
below. Zone colours come from `pace-spectrum-mockup.html` — six reachable bands, per slice 0.

**Rest days still render a row.** Mood, sleep, HRV and niggles all still apply. A dashed placeholder
where the bar would be. Rest is data.

---

## Sections below the rows

1. **Volume by pace** — a stacked bar plus a legend listing each zone with its pace range, distance
   and percentage. Zone ranges come from `athlete_state.pace_zones`, not hardcoded.
2. **Recovery** — sleep bars behind an HRV line with a dashed 28-day baseline. **Empty state until
   slice 5.**
3. **Patterns** — slice 4. Leave a placeholder container.

---

## Sleep and HRV do not exist yet

There is no sleep or HRV anywhere in this app. `VITAL-GARMIN-APPLY-NOTES.md` is written but not
applied and `VitalManager.vitalRequest` is a stub returning `nil`.

**Build for absence from the start.** Model them as optional, and make the absent state a designed
state rather than a gap:

- Meta line: omit the sleep and HRV chips entirely — do not render "SLEEP —"
- Recovery section: one honest empty state. *"Connect Garmin to see sleep and HRV here."* with a
  route to Settings, not a blank chart frame.
- Row layout must not shift when they appear later.

When slice 5 lands, the fields populate and nothing else changes. Verify this by building with them
nil **and** with them stubbed, and confirming the row geometry is identical.

---

## Files

**New, additive:**

```
Training/Analytics/CalendarWeekView.swift        the seven rows + section stack
Training/Analytics/CalendarWeekRow.swift         one day row
Training/Analytics/CalendarZoneBar.swift         the segmented pace bar, shared with the
                                                 volume-by-pace section
Training/Analytics/CalendarRecoveryChart.swift   sleep bars + HRV line + baseline; empty state
RunningLogTests/CalendarWeekRowTests.swift       session naming + bar segment maths
```

**Tracked files edited — one:**

`Training/Analytics/TrainingTabView.swift` — in `.calendar` mode, route the `WEEK` scope to
`CalendarWeekView` instead of the current `TrainingCalendarSection`. One branch. `MONTH` and `BLOCK`
keep going where they go today.

Reuse `CalendarService` / `CalendarModels` from slice 2. If slice 2 has not shipped, create them here
per that document's spec — they are the same files, and whichever slice lands first owns them.

---

## Session naming

Worth getting right, it is the most-read text in the view.

```
key session with structure  → the structure verbatim   "6x1mi", "8x200"
key session, no structure   → the kind                 "Fartlek", "Tempo"
kind == long                → "Long run"
≥18 km / 11 mi, no key      → "Long run"
2+ runs, all easy           → "3 × easy"
otherwise                   → "Easy"
no run, past                → "Rest"
no run, future              → planned session name, or "—"
```

Structure strings come from `keySessions.ts` via slice 1's `key_structure`. Do not re-derive them
on-device.

---

## Layout

Seven rows at ~64 pt is ~448 pt, plus header, stats and three sections below. The whole view scrolls;
that is fine and expected. Do not try to fit a week on one screen — the detail is the point.

Meta line wraps to a second line when a niggle word is present. Budget for it: at 375 pt with the
largest accessible Dynamic Type size, the meta line can reach three lines. Let it, do not truncate.
A niggle you cannot read is a niggle that does not exist.

---

## Accessibility

- One `accessibilityLabel` per row, read as a sentence, including the pace mix in words: *"about
  three quarters easy, a quarter at marathon pace."* Do not read six raw percentages.
- The zone bar is decorative once the label covers it — `.accessibilityHidden(true)`.
- Recovery chart needs an `accessibilityValue` summarising direction: *"HRV averaged 67, about five
  below your baseline."*

---

## Tests

`CalendarWeekRowTests.swift`, pure functions:

- [ ] Session naming — every branch of the table above, including the future/planned case
- [ ] Zone segments sum to the bar width within rounding, and a single-zone day renders one segment
- [ ] Bar width is proportional to the **week's** max day, not the month's
- [ ] A rest day produces a dashed placeholder, not a zero-width bar
- [ ] Row renders with sleep and HRV nil, and the geometry matches the populated case

---

## Done when

- Week of 20 July matches the prototype: 21 July half easy / half MP, 24 July with its navy sliver
- Week of 18 May shows amber mood on Mon and Tue, four consecutive achilles rows
- Every row renders with sleep/HRV nil and no layout shift when they are populated
- Recovery section shows a designed empty state, not a blank frame
- Month scope still works — you changed one branch
- VoiceOver reads one sentence per row
- `check_design_tokens.py` passes

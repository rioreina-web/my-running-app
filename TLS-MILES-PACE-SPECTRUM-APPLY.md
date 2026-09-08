# TLS + miles on the pace spectrum

**Applied:** 2026-08-18 · directly to working tree
**Scope:** the fortnight (mood) chart only — the MILES and TLS lanes stack by
pace zone on the blue ramp. **Not compiled here** — build in Xcode.
**Prototype:** `trends-tls-miles-pace-spectrum-prototype.html` (reviewed and
approved before this was applied; the always-on call and the fallback look are
from that review).

---

## What changed, and why it reads

The MILES lane was a graphite bar of `bucket.miles`; the TLS lane a darker
graphite bar of `block.load`. Both now stack by pace zone, slow at the base,
the sharp end on top, coloured on the ten-stop ramp from `PaceSpectrum.swift`.

The two lanes tell one story the flat bars couldn't: miles read mostly pale —
easy running is the foundation — while TLS weights the fast end, so an
interval Wednesday that is a short bar in MILES is a tall, navy-tipped bar in
TLS. Where the deep blue lives is where the training stress came from.

**The three-palette rule holds, and is now earned rather than dodged.** The
old header comment said load bars were "deliberately achromatic graphite: blue
belongs to pace, and a blue bar here would read as a pace signal." These bars
now *are* pace signals — the colour finally means what the rule says it means.
Mood stays warm, the niggle dot stays coral, no hue is shared. The comment was
rewritten to say so (it would otherwise instruct the next reader to revert
this change).

---

## 1. `TrendsMoodRead.swift` — the block exposes per-day zones

Two computed vars on `TrendsMoodBlock`, next to `load` and with the same
days-align-with-buckets contract `load` already relies on:

- `zoneMilesPerDay: [[String: Double]?]` — `day.zoneMiles`, `nil` when empty.
- `zoneLoadPerDay: [[String: Double]?]` — `day.zoneLoad`, `nil` when empty.
  These are the same values `load` sums, so a stacked bar and the flat bar it
  replaces are always the same height.

`nil` means *ran without laps* (manual entry, import without splits) — the
`TrendsDay.hasZoneBreakdown` contract. The chart must draw the fallback for
those days, never a guessed distribution.

## 2. `TrendsMoodLanes.swift` — `drawBars` → `drawStackedBars`

The flat `drawBars` had exactly two callers (miles, load) and both moved, so
it was replaced rather than kept alongside. The stacked variant keeps the
load-bearing properties:

- **One scale across the whole lane.** Bar *height* still comes from `totals`
  (`bucket.miles` / `block.load`) against the window peak — stacking changes
  what a bar is made of, never how tall it is.
- **Segment heights are shares of the day's own zone sum**, so the stack fills
  the bar even when lap miles don't sum exactly to the day's deduped total.
- **Fallback:** distance with no breakdown draws flat graphite at 0.55 opacity
  with a dashed cap — visibly "we don't know". Rest days draw nothing. Three
  states, three looks.
- **Unknown zone tokens** render as a graphite remainder on top rather than
  silently vanishing — a new backend zone must show as *something*.

The zone→colour table (`zoneStack`) is owned here, in stacking order, with
`recovery` folded to the easy stop and an `lt` row as belt-and-braces (the
backend classifier folds LT into `hmp`). It is deliberately NOT shared with
`TrendsReadView.zoneColor`, which maps *work* zones only and defaults
everything else to steady — wrong for a lane that is mostly easy miles.

Chip dots: MILES → `PaceSpectrum.easy`, TLS → `PaceSpectrum.steady` (both
from the pale half of the ramp, so they survive the ink pill).

## 3. `TrendsPreviewData.swift` — fixture grows zone data

`previewMonthRich` days now carry `zoneMiles` + `zoneLoad` (shaped by session
channel; TLS as weighted minutes off `TrendsZoneWeight`). Wednesdays are left
breakdown-less **on purpose** so the ran-without-laps fallback stays visible
in previews — a state that can't be previewed never gets design-reviewed.

---

## Verify (Xcode)

1. Build; run previews for `TrendsTabView` / the mood section.
2. MILES: mostly pale stacks; key days show a dark band; Wednesdays flat
   graphite with dashed cap.
3. TLS: same days, same *heights* as before the change (totals unchanged);
   key days visibly navy-heavy relative to their MILES bar.
4. Scrub still reads, tap still selects, lane toggles still work — no gesture
   or accessibility code was touched.
5. On-device with real data: a day whose runs predate the zone backfill (no
   `zone_load` / `zone_miles` in the timeline payload) must draw the fallback,
   not an empty bar.

## Deferred, deliberately

- The per-day readout / selection row does not yet name zones ("6.5 easy ·
  2.2 5K"). The day panel in the prototype sketches it; separate change.
- Tapping a legend zone to pick it out across the fortnight (in the
  prototype) — there is no spectrum legend on this surface yet at all.
- `weekly` lane stays graphite: it spans days, and a stacked *week* bar is a
  different design question.

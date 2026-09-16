# Design brief — Log / main feed redesign

**Surface:** `web/src/app/(app)/log/` (`page.tsx` + `journal-view.tsx`)
**Date:** 2026-07-06
**Status:** brief for a design pass — implementation to follow on approval

---

## Why we're redoing this

The first editorial pass got the *type and voice* right (Crimson display,
PT Serif italic voice-logs, mono meta, mood rail, coral-bar coach notes) but
has two real problems:

1. **The column floats.** The feed sits in a centered `max-w-2xl` column
   inside the full-width content area, so on a desktop viewport it drifts
   right with a large dead gutter on the left. The page reads unbalanced —
   all the weight is on the right half.
2. **Low information density / no overview.** Every entry is very tall, so
   only ~2 fit above the fold, and the page opens straight into individual
   runs with **no at-a-glance training state** — no weekly mileage, no load,
   no mood arc, no next workout. With sparse data it reads as mostly empty
   paper.

The fix is a denser, left-anchored, two-column layout that leads with a
*training-state overview* and treats the journal as a tighter feed beneath it.

---

## Non-negotiables (brand system — do not drift)

Pull tokens from `web/src/app/globals.css`; the source of truth is
`design-system/README.md` and the iOS `ui_kits/ios_app/` screens.

- **Type:** Crimson Pro (`font-display`) for headlines + day names; PT Serif
  (`font-body`) for prose and italic voice-log quotes; **system mono**
  (`font-mono`) for every uppercase eyebrow, meta line, and stat number
  (tabular). No other families.
- **Color — three-palette rule, hard:** blue = pace (single-hue depth ramp,
  Easy→Mile), warm = mood, coral = alert/punctuation. Palettes never share
  hues. Green is mood-only; a "within range / safe" state is **neutral ink**,
  never green. Coral appears **once per visual cluster, maximum.**
- **Structure:** plate strip at the top; **editorial rule** (`line · dot ·
  line`) for section breaks, not `<hr>`; hairlines (`1px #E8E4E0`) elsewhere.
- **Cards:** white, 12px radius, `shadow-card` (`0 2px 8px rgba(0,0,0,.06)`),
  16px padding. No card-in-card. No gradients, no blur, no emoji.
- **Voice:** spare, declarative, second person. Coach notes carry the
  "From your coach" eyebrow + coral left-bar. Empty states = eyebrow + plain-
  prose nudge (never an em-dash).

---

## Layout — the core change

### Desktop (≥ 1024px): two columns, left-anchored

```
┌─ plate strip (full-bleed) ──────────────────────────────────┐
├──────────────────────────────┬──────────────────────────────┤
│  FEED  (primary, ~60ch)      │  RAIL (~300px, sticky)        │
│                              │                               │
│  header: "The log."         │  THIS WEEK                    │
│  ─ month rule ─             │   • mileage vs target         │
│  journal rows (denser)      │   • runs · avg pace           │
│  ...                        │  ─ rule ─                     │
│                              │  NEXT UP  (plan / workout)    │
│                              │  ─ rule ─                     │
│                              │  MOOD · 7 DAYS (dot arc)      │
│                              │  NIGGLES (count → link)       │
└──────────────────────────────┴──────────────────────────────┘
```

- Anchor the whole block to the **left** of the content area with a sensible
  max width (~`max-w-5xl`), not centered-with-gutter. The feed column is the
  reading measure (~60–64ch); the rail is a fixed ~300px `sticky top` column.
- Gap between columns: 40px. Feed left-aligns to the content padding so there
  is no floating dead space.

### Narrow (< 1024px): rail collapses to a top strip

The rail's four tiles become a horizontal **stats strip** (2×2 or a scroll
row of `stat-tile`s) directly under the header, then the feed below. Never
show the empty left gutter.

---

## The overview rail (this is the "more data" the page is missing)

Four quiet modules, each an `eyebrow` + content, separated by editorial rules.
All numbers mono/tabular. Data already exists — reuse the dashboard's
aggregation (`web/src/app/(app)/dashboard/page.tsx` computes mileage via
`dedupeRuns`, mood, injuries, goals).

1. **This week** — `stat-tile`s: weekly mileage **vs target** (neutral ink if
   within range, coral only if over — three-palette), run count, avg pace
   (mono). Optional 7-day mileage sparkline (ink line, coral last dot).
2. **Next up** — current plan name + the next scheduled workout as a compact
   line (`TUE · MP 7 mi`), or the empty-state nudge if `activePlan == nil`
   ("No plan running. Your training still counts.").
3. **Mood · 7 days** — a row of 7 mood dots (warm hues) — the week's arc at a
   glance. No labels; dot color carries it.
4. **Niggles** — count of active body-mentions → links to Injuries. Coral only
   if something is flagged; otherwise neutral.

If a module has no data, use the empty-state pattern, not a blank tile.

---

## Feed density — tighten the rows

- **Vertical padding:** entries `py-6 → py-4`; header `pt-9 pb-7 → pt-6 pb-5`.
  Month rule `py-5 → py-3`.
- **Month break carries a total:** `JULY 2026 · 142 MI · 18 RUNS` (mono),
  right-aligned on the rule — turns a divider into information.
- **Quality vs easy weight:** give quality runs (tempo, intervals, long,
  progression, race) slightly more weight — thicker mood rail or the day name
  a size up — so the eye finds the important sessions. Easy/recovery stay
  quiet. (Mirror the plan-builder's quality-vs-easy treatment.)
- **Collapsed coach insight:** clamp to **1 line** (currently 2) to keep rows
  short; full text on expand.
- **Voice-log quote:** keep italic PT Serif, but cap collapsed length shorter
  (~120 chars) so rows stay scannable.
- **Mood:** show as the rail color **and** a small mono word — but move the
  word up onto the meta line (`JUL 6 · 8.1 MI · 7:11/MI · POSITIVE`) so it
  doesn't add a row of height.

---

## Concrete acceptance checks

- [ ] No large empty gutter on the left at any width; content is left-anchored.
- [ ] Above the fold on desktop shows the header, the overview rail (4 modules),
      and **≥ 4** journal rows.
- [ ] Weekly mileage, next workout, 7-day mood, and niggle count are all visible
      without scrolling on desktop.
- [ ] Within-range mileage is neutral ink (not green); coral appears at most
      once per cluster.
- [ ] Pace/effort anywhere uses the blue ramp; mood uses warm; they never share
      a hue.
- [ ] All existing behavior intact: realtime updates, tap-to-expand, inline
      edit, delete, check-in badges, processing/retry, Vital detail.
- [ ] Empty states use eyebrow + nudge, no em-dash.

---

## Out of scope (for this pass)

Voice recording on web (the app's record button is native). The web feed is
read/annotate only; the "front door" is the overview rail, not a record disc.

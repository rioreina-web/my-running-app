# Training — UI redesign brief

*2026-07-11 · one of five per-tab briefs. Reads on top of `00-foundations.md` (mental model, shared components, cross-cutting states, a11y) and the Post Run Drip design system (`design-system/README.md`). Prototype reference: `renderTraining` / `renderBlock` / `renderMonth` / `renderWeek` / `renderDay` / `renderKeySessions` in `prototypes/post-run-drip-beta.html`; day-sheet target is `design-system/ui_kits/ios_app/WorkoutDetailScreen.jsx`. Don't restate foundations — this is Training-specific.*

## 1. The one job

**What have I done, day by day?** The ledger. Zoom from the whole block down to one session's splits, read easy-vs-quality at a glance, and see the plan layered under the done. Training answers *what happened*; it hands *is it working?* to Trends and *what's next?* to Plan. No fitness projections, no synthesis paragraph — those belong to other tabs.

## 2. Current state & problems

The prototype is a five-way segmented control — **Block · Month · Week · Day · Key** — over a breadcrumb, a quality/easy legend, and a level body. It works, but:

- **Five targets don't fit a phone.** Each `seg` button is ~62px; the labels crowd and the tap targets fall under 44pt. Worse, the five aren't peers: Block/Month/Week are *zoom levels*, Day is a *leaf* you reach by tapping, and Key is a *lens* (a filter across all levels). One control conflates three altitudes.
- **Breadcrumb + segmented control is double navigation.** Two stacked ways to move between the same levels. Redundant chrome above the fold.
- **The legend is always-on chrome** but only decodes dots on Block/Month.
- **Nothing is sticky.** Scroll a long calendar and the level control leaves with it — you can't re-zoom without scrolling back up.
- **No "today" anchor.** Month opens on the current month but doesn't scroll today into view; Block reverses to recent but offers no jump-to-now.
- **Plan is layered thinly and only where data is absent** — Month ghosts *future* days as ink-3 dots, Week shows "PLANNED" rows for *missing* days. On days you actually ran, there's no did-I-hit-the-prescription read.
- **Planned-vs-actual is a buried link-card** that string-compares workout *type* ("· on plan"). No pace/distance delta.
- **The Day sheet has no interactive telemetry** — just a static splits table. The design's `WorkoutDetailScreen` already specifies a drag-to-scrub pace × HR × elevation chart; the prototype never built it.
- **Phase is text-only** (a "Taper · wk 3 of 14" tile + a small-caps suffix per week row). No visual sense of where you sit in base → build → peak → taper.
- **Transitions are hard `innerHTML` swaps.** No zoom feel month→week→day, no swipe between days or weeks (pager arrows only).

## 3. Target layout

Collapse to **three legible zoom levels + Day-as-pushed-sheet + Key-as-lens.** Segmented control carries only `Block · Month · Week` (three 44pt targets). Day is a detail sheet you push by tapping any cell/row (kill it as a segment). Key is an orthogonal `★` toggle on the header-right — it doesn't compete for a zoom slot. The breadcrumb goes; the sticky header + native back replace it.

```
┌ TRAINING · LEDGER ───────────── FIG. ──┐   plate strip
│                                         │
│ ┌ Block · Month · Week ┐      ★ Key  ●──┼─ STICKY: segmented + lens toggle
│ │▓ base ░ build ░ peak ░ taper│  wk11/14│   phase ribbon, coral now-tick
├─────────────────────────────────────────┤   (header ends; body scrolls under)
│  MON TUE WED THU FRI SAT SUN            │
│   .   ●   .  (32) ●   ★   ●   ← today ring
│  Easy ░  Long ▒  Quality ▓  Rest ·      │   contextual legend (Month/Block only)
│                52 mi logged · 71/29 e/q │
└─────────────────────────────────────────┘
   swipe ← → pages month · tap day → sheet

DAY SHEET (pushed, swipe ← → = prev/next day)
  TUESDAY · BUILD          May 5.
  6.9 mi · 51:06 · 7:24/mi          ★ Key
  ┌ 4-stat: dist · dur · GAP · load ┐
  ┌ 5-stat: cad · HR · drift · EF · wk┐
  TELEMETRY · PACE × HR × ELEV   DRAG TO SCRUB
   ╱╲__ pace  ~~~~ HR  ░░ elevation  │scrub
  SPLITS · BY PACE   [pace-dot table]
  "Climbed early, came home fast…"   niggle·calf
  AGAINST THE PRESCRIPTION
   plan  LT 6  @ 7:30 MP  →  actual 6.9 @ 7:24  ✓ on plan
  Run 4 of 5 · 28 mi banked → View in Trends ↗
```

Top→bottom, non-sheet: **plate strip · sticky[segmented + phase ribbon] · level context (tiles or ratio bar) · level body · contextual legend.** Sticky region = segmented control + phase ribbon only, so the level control never scrolls away.

## 4. Components

Mostly inventory (see foundations §Shared): **segmented control** (now 3-up), **pace-volume chart** (Block's mini stacked-by-zone bars; the Day telemetry), **splits table**, **key-session star**, **filter chips** (Key list), **stat tile**, **mood pill**, **niggle chip**, **coach quote**, **link-card** (hand-off to Trends/Plan/Log), **empty-state**, **editorial rule**. Drop the **breadcrumb** here.

New / adopted, justified:
- **Phase ribbon** *(new primitive — define in foundations if reused).* A thin horizontal base/build/peak/taper bar under the segmented control, four neutral ink tints (ink-3 → ink), one **coral now-tick** as the single punctuation mark in the cluster. Not pace-blue, not mood-warm, not an alert — phase is block position, so it stays tonal. Caption `wk 11 of 14 · build`.
- **Interactive telemetry chart** *(adopt from design, not new).* Port `WorkoutTelemetry` from `WorkoutDetailScreen.jsx` — combined/stacked/splits modes, drag-to-scrub readout. Pace is the blue depth ramp; HR is ink; elevation is a pale fill. No coral series.
- **Plan-overlay treatment** *(variant, not new).* Reuse the pace-volume chart's target-cap idea on the calendar: done days render a solid pace dot; planned days render a hairline **ghost ring** at the prescribed zone color. One visual language for "prescribed vs banked."
- **Planned-vs-actual block** *(small new pattern).* Two aligned rows — prescription (label · zone target) over actual (label · avg pace) — with a delta and an on/off-plan chip. Shows the number, never a pass/fail verdict.

## 5. Interactions & states

- **Drill:** tap a week row (Block) → Week; tap a day (Month/Week) → Day sheet. Back = native / swipe-down on the sheet. No breadcrumb.
- **Swipe:** horizontal paging replaces pager arrows — months (Month), weeks (Week), days (Day sheet). Keep arrow buttons as the VoiceOver/reduced-motion fallback; arbitrate against the iOS back-edge and tab-bar swipe (page from the content region, not the screen edge).
- **Zoom transitions:** month cell → week → day animates as a scale+fade "zoom in" (300ms easeInOut), not a hard cut. `prefers-reduced-motion` → fade only (foundations §Motion).
- **Today anchor:** Month auto-scrolls today into view with a coral ring; Block rings the now-row; a mono **`Today ↗`** link in the sticky header snaps any level back to now.
- **Key lens:** the `★` toggle swaps the body to the filterable key-session list (chips `All · Long · MP · LT · Intervals`, default `All`, default sort recent-first) and floats a ghost **`Next key · Sat · Long 17`** row on top when a key day is planned ahead. Toggle off returns to the current zoom. Star markers persist on Month/Week regardless.
- **Depth (foundations §data_depth):** depth-0 → the existing empty state (reference, don't restate). depth-1–2 → calendar + rows, plain captions, no phase ribbon until a plan or goal exists. depth-3 → phase ribbon labeled, context tiles carry number-cited pull-quotes ("71/29 easy/quality · target 80/20").
- **Loading:** calendar-grid / week-row skeletons in card shape, no spinners.
- **Missing conditions:** GAP/grade backfill pending → show raw pace, mark it, never fake the adjustment (foundations §Missing data). Telemetry with pace-only data (no HR/elev) degrades to the single pace trace.

## 6. Improvements (prioritized)

**P0 — legibility & the plan overlay**
- Segmented control → **`Block · Month · Week`** only; Day becomes a pushed sheet, Key becomes the `★` lens. Delete the breadcrumb.
- **Sticky header** (segmented + phase ribbon) so the level control survives scroll.
- **Plan onto the calendar:** ghost-ring prescribed days at their zone color; done days solid. Both Month and Week read planned-under-done in one glance.
- **Compact planned-vs-actual block** on the Day sheet (delta, not verdict), link-carded to Plan.

**P1 — the Day sheet & orientation**
- **Interactive telemetry chart** — port `WorkoutTelemetry`, drag-to-scrub pace × HR × elevation.
- **Phase ribbon** (base/build/peak/taper, coral now-tick) under the segmented control.
- **"Today" anchor** — auto-scroll + ring on Month/Block, `Today ↗` snap link.
- **Key-session defaults** — sort recent-first, filter `All`, surface the next planned key session.

**P2 — motion & polish**
- **Zoom transitions** month→week→day (scale+fade, reduced-motion aware).
- **Swipe paging** for days/weeks/months, arrows as fallback.
- **Contextual legend** — show the easy/long/quality/rest key only on Block/Month; drop it on Week/Day where rows are labeled.

## 7. Voice & copy

- **Eyebrows (mono caps):** `THE ARC · 12 WEEKS` · `WEEK 11 · BUILD` · `TUESDAY · BUILD` · `SPLITS · BY PACE` · `TELEMETRY · PACE × HR × ELEVATION` (right: `DRAG TO SCRUB`) · `AGAINST THE PRESCRIPTION` · `KEY SESSIONS · THIS BLOCK`.
- **Headlines (Crimson, period):** `Day by day.` · `LT 6.` (the workout label *is* the headline) · `Rest day.` · `May 5.`
- **Planned-vs-actual:** state the delta, never a grade. `On plan.` · `Under target — 7:41 vs 7:30 MP.` Never "You missed it," never a red ✗.
- **Phase caption:** `wk 11 of 14 · build`. **Next key row:** `Next key · Sat · Long 17`.
- **Rest day:** keep *"Nothing logged. Rest is training too — it's where the work from the hard days actually lands."*
- **Empty state:** the existing *"No sessions yet…"* line + `Log your first run ↗` (reference foundations §Empty states — don't reword).

## 8. Open questions

- **Key: lens or list?** Spec above makes it a toggle that swaps the body to the key list. Alternative: a dim-non-key overlay on the current zoom. Pick one; don't ship both.
- **Planned-vs-actual for self-coached Maya (`activePlan == nil`).** The product is journey-centric and no-plan is first-class — so compare against *what*? Options: a goal-derived template (from `derivePaceTableFromGoal`), the athlete's own recent pattern, or hide the block until a plan/goal exists. This is the load-bearing call; resolve before building the block.
- **Phase ribbon source when there's no plan.** Derive base/build/peak/taper from the volume arc, or suppress the ribbon until a plan or goal is set? (Ties to the question above.)
- **Block span.** Prototype shows 12 rows but the block is 14 weeks (`curBlockWeek` of 14). Show the full block or a rolling 12? Reconcile the eyebrow and the row count.
- **Telemetry availability.** HR/elevation backfill differs by source (Strava vs HealthKit). Confirm the pace-only degrade is common enough to design as the default, not the exception.
- **Swipe gesture budget.** Days, weeks, months all want horizontal swipe while the tab bar and iOS back-edge also claim it. Needs an explicit gesture-arbitration rule before P2.

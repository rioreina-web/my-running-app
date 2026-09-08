# Plan — UI design brief

*2026-07-10 · one of five per-tab briefs. Reads on top of `00-foundations.md` (shared principles, the 8-heading template, the component inventory) and the Post Run Drip design system. Tested against Maya. Don't re-read the foundations here — this only covers what's specific to Plan.*

---

## 1. The one job

**What am I supposed to do — and where is it taking me?** Plan is the *forecast* surface: the road ahead (goal, block shape, the next session) held honestly against the road behind (what actually got done). Training is the ledger; Plan is the horizon. Same calendar, opposite time-direction.

## 2. Current state & problems

`renderPlan` today is three stacked pieces: a goal card (Boston qualifier · 3:16 · Sep 20 · days-out · PB 3:28), a flat **this-week** list with a done/planned marker per day, and an italic "planned sessions layer onto the Training calendar" note. Problems:

- **No forward view.** The block machinery already exists in the data layer — phases (`Base/Build/Peak/Taper`), `WK_TARGET` (peak 56), `planForDate` reconciliation — but Plan surfaces none of it. You see this week and nothing past Sunday. There is no arc, which is the whole point of a journey-centric product.
- **`activePlan == nil` is treated as failure.** The only no-plan branch is the app-wide empty state ("Set a race, and a shape appears"). A self-coached runner with months of logs and no template loaded gets an empty screen — the opposite of first-class.
- **Palette violation.** "✓ done" renders in `--mood-energized` green. Completion is not a mood; green is mood-only (foundations, three-palette rule). Coral is spent on the goal eyebrow instead of the one thing that should alert.
- **Goal shown as a lone number.** `3:16` sits big as "target" with no honest projection beside it — brushing against the range+confidence rule and the race-anchor-over-goal principle.
- **No reconciliation, no adjust, no provenance.** Nothing says where the plan came from (template/coach/adaptive), nothing lets you move a day, and past days don't reconcile beyond a binary check.

## 3. Target layout

Top→bottom: **goal + honest projection → next key session → block ribbon + mileage ramp → forward month → this week (reconciled) → provenance.** The five-second read is the goal card and the next session; everything below is the arc, in progressive detail.

```
┌───────────────────────────────────────────┐
│ RUNNING LOG — PLAN · FORECAST      FIG. 05  │  plate strip
├───────────────────────────────────────────┤
│ GOAL · BOSTON QUALIFIER            [coral]  │
│ Marathon · Sep 20.                          │  display headline
│ 47 days out · anchored on Apr 6 half 1:37:40│
│                                TARGET  3:16 │
│  projection 3:22–3:29 · moderate confidence │  race-anchored reality
├──────────── line · dot · line ─────────────┤
│ NEXT KEY SESSION                    ★[coral]│
│ MP 8 mi · Thursday · 5:32 / mi target       │
├───────────────────────────────────────────┤
│ THE BLOCK · WK 6 OF 12                      │
│ BASE     BUILD      PEAK      TAPER         │  phase ribbon (ink-tone)
│ ▂▃▄▄   ▅▆▆[▆]   ▇▇▇     ▄▂         │  mileage ramp, now-week ring
│ 39 ·············· 56 peak ··········· race  │
├───────────────────────────────────────────┤
│ SEPTEMBER                        forward ▸  │  forward month grid
│  M   T   W   T   F   S   S                  │
│  ✓   ·   ✓   △   ○  [ ]  ▓           │  reconciled past · planned ahead
│  ▓   ·   ▓   ▓   ·   ▓   ▓           │  zone-tinted planned cells
├───────────────────────────────────────────┤
│ THIS WEEK                    Open in Train ↗│
│ MON · Sep 1   Long 17            planned     │
│ WED · Sep 3   LT 6      ✓ done → workout ↗   │
│ THU · Sep 4   MP 8      ★ next · Adjust ↗    │
├───────────────────────────────────────────┤
│ PLAN · TEMPLATE — Pfitzinger 12/55          │  provenance footer
└───────────────────────────────────────────┘
```

## 4. Components

From the inventory: plate strip · eyebrow (coral on the active goal) · display headline (period after) · hero goal card · **key-session star** · **segmented control** (month ▸ forward paging) · month calendar grid (reused from Training, forward + planned) · plan-row list · link-card ("Open in Training ↗", per-day "→ workout ↗") · coach quote (2px coral bar) for coach notes · empty-state · editorial rule.

New patterns (justified, defined here per foundations rule):

- **Phase ribbon.** A mono-labeled band over the ramp marking `BASE · BUILD · PEAK · TAPER`. Rendered in an **ink-tone weight ramp** (light→heavy→light), *not* a fourth color palette — phase is structure, and the three-palette rule leaves no hue free. Current phase gets the coral tick.
- **Mileage ramp.** A forward weekly-target bar series (neutral ink fill on a paper well), now-week ringed in coral, taper as the descending tail. Distinct from Trends' *actual* mileage progression: this is **target**, forward, unstacked. If it starts stacking by zone, it has become the Trends chart — don't.
- **Reconciliation markers.** A small state glyph set on past days: `✓ done` · `△ ran different` · `○ missed`. Ink by default; coral reserved for a *single* miss of a **key** session per cluster. No green.
- **Adjust sheet (move-day).** Opened from a future planned day: move · swap (from the closed `reschedule-plan` library) · skip, then a closed-vocabulary reason picker. Writes an audit row, `auto_applied:false`.
- **Provenance chip.** Template / From your coach / Adaptive, in the footer eyebrow.

## 5. Interactions & states

- **Tap next-key-session** → scrolls the month to that day (or hands to the Training day detail if it's within reach).
- **Tap a future planned day** → day preview → *Adjust*: move/swap/skip → "Why the change?" reason picker (closed list) → confirm. **Never auto-applies.** Self-coached: writes `plan_adjustments` (`auto_applied:false`), the plan reshapes, nothing else moves. Coach plan: the move is *proposed* to the coach and shows as pending — AI advises, the human acts.
- **Tap a past/completed day** → hands off to Training workout detail. Plan never re-renders splits; reconciliation is a link, not a copy.
- **Phase ribbon / ramp bar tap** → readout (phase, weeks, target mi; done vs planned for past weeks). VoiceOver: *"Peak, weeks 9–11, current."*
- **depth / plan states** (four, not two):
  - *No goal, no plan (depth 0)* → empty-state CTA. "Set a race, and a shape appears." Plain UI, no pull-quotes.
  - *Goal, no active plan (the first-class state)* → goal card + honest projection + an **open forward calendar** (unprescribed days you can still fill) + light guidance. Not an error. "No structured plan — that's fine. Keep logging, or pick a shape."
  - *Active plan (depth 3)* → full layout, editorial register, pull-quotes cite a number.
  - *Coach plan* → same, plus coach provenance; coach-authored days carry the coach treatment; adjustments route as proposals.
- **Loading** → skeletons in goal / ramp / calendar shapes, no spinners.
- **Projection unavailable** (no recent anchor) → show the target, but say *"projection needs a recent race"* rather than faking a range. Whole-minute rounding always.
- **prefers-reduced-motion** → no ramp draw-in; fades only.

## 6. Improvements (prioritized)

**P0**
- Build the **`activePlan == nil` first-class state** — goal + race-anchored projection + open forward calendar + light guidance (browse templates / build adaptive / attach coach). This is the headline fix; a self-coached Maya must never land on an empty screen.
- Ship the **forward month + phase ribbon + mileage ramp** from the data that already exists. Give Plan an arc.
- **Split goal from projection honestly:** target `3:16` is *direction*; `3:22–3:29 · moderate`, anchored on the Apr 6 half, is *reality*. Show both, never merge, never a single false-precise finish (hard rule 7).
- **Fix the palette:** reconciliation renders in ink; coral is spent only on a missed key session or the now-marker. Kill the mood-green check.
- **Pull the next key session to the top**, starred — the one thing to do next.

**P1**
- **Planned-vs-actual reconciliation:** per-day `✓ / △ / ○` + a per-week compliance line ("5 of 6 key sessions, this block"), each day linking out to Training. Don't re-render splits.
- **Move-day / adjust** with closed reason codes (travel · fatigue · niggle · life · weather), audit-logged, never auto-applied; coach-plan moves route as proposals.
- **Provenance + coach layering:** template/coach/adaptive chip; coach days get the coach treatment; a coach plan changes adjust-behavior to propose-not-apply.
- **Countdown + taper legibility:** the ramp's descending tail plus *"taper starts in 12 days."*

**P2**
- **Adaptive "build a shape"** handoff from the no-plan state.
- **What-if preview:** show a moved week's downstream effect before confirming.
- **Confidence-narrows-as-race-nears:** the projection range visibly tightens week over week.
- **Season view** for more than one race on the arc (tune-up half before the marathon).

## 7. Voice & copy

- **Eyebrows:** `GOAL · BOSTON QUALIFIER` · `NEXT KEY SESSION` · `THE BLOCK · WK 6 OF 12` · `PHASE · PEAK` · `FROM YOUR COACH` · `PLAN · TEMPLATE`.
- **Headlines:** *"Marathon · Sep 20."* · *"Peak week. The work's in the bank."* · no-plan: *"A marathon on Sep 20, and no shape yet."* · empty: *"Set a race, and a shape appears."*
- **Projection line:** *"Target 3:16 · projection 3:22–3:29, moderate confidence."*
- **Reconciliation:** `✓ done` · `△ ran different` · `○ missed` · *"5 of 6 key sessions, this block."*
- **Adjust:** *"Move day"* → *"Why the change?"* → confirm, self: *"Logged. The plan shifts, nothing else moves."* / coach: *"Proposed, not applied. Your coach sees the move."*
- **No-plan (has goal):** *"No structured plan — that's fine. Keep logging, or pick a shape to follow."* + `Browse templates ↗ · Build adaptive ↗`.
- **Empty (no goal):** *"No goal race yet. Add the race you're pointing at and this fills with a calendar, weekly targets, and the paces to hit them."*
- **Taper:** *"Taper starts in 12 days. Miles come down; sharpness stays."*

## 8. Open questions

- **Post-merge home.** In the 4-tab IA, Plan collapses into Train. Does this forward calendar become Train's CALENDAR mode with a forward toggle, or a distinct forecast sub-surface? Where does the goal card live then?
- **Reason-code vocabulary.** Exact closed list for move-day — align to `plan_adjustments` codes and the `shift-day` edge function before building the picker.
- **Coach pending-state visual.** Does a proposed move show immediately as pending, or hold invisibly until the coach approves? What does pending look like on the day cell?
- **Phase color.** Confirm the ink-tone ribbon is acceptable rather than granting phase its own restrained neutral ramp.
- **Ramp: planned-only or two-tone?** Showing actual-vs-target on past weeks risks duplicating Trends' mileage progression — where's the line?
- **Stale/absent anchor.** "Needs a recent race" vs. a wider low-confidence range — which is more honest for Maya when the anchor ages out?

# Plan Builder UI Redesign

Working doc for cleaning up the coach-facing plan builder. Edit in place.
Sister docs: [pace-system-rework.md](pace-system-rework.md),
[adaptive-plan-builder-rework.md](adaptive-plan-builder-rework.md).

This doc is **UI/IA only** — data-model + materialization stay in the adaptive
doc. Scope here: how info is laid out and how the coach actually accomplishes
the four core tasks (assign, edit, replace, save).

---

## 1. Current layout (left → right, top → bottom)

```
┌─ SIDEBAR ─┬─ HEADER ───────────────────────────────────────────┬─ RIGHT PANEL (EDIT — SAT) ─────┐
│ Dashboard │ "3 weeks - aerobic base"        Save Draft Publish │ STEPS              + Save lib  │
│ Training  │ Fixed │Adaptive  Marathon Half 10K 5K Custom  3wks │ WORKOUT STRUCTURE   ≈ 16.0 mi  │
│ Coach     │ ┌─ PACE REF ──────────────────────────────────┐    │ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━  │
│ Plan      │ │ from 2:25:00 marathon  MP 5:32 LT 5:17 …   │    │ │ Active 16 mi @ LR ±s/mi exact │
│ Coach P.  │ └─────────────────────────────────────────────┘    │ + reps                         │
│ Goals     ├─ WEEK SELECTOR (W1 W2 W3) ─────────────────────────┤ Notes…                         │
│ Analysis  │ Race Week  7 workouts        70-80 mpw  27.0 qual  │ 16 mi @ LR    6:34-7:16/mi     │
│ Injuries  │ Set quality workouts only — easy + recovery filled │                                │
│ Predictor │ Mon  Auto · easy run (per athlete)            +    │ ADD A BLOCK                    │
│ Pace      │ Tue  ▌ 7 x mi at LT  11.0 mi                  +    │ +Warmup +Easy +Tempo           │
│ Library   │ Wed  Auto · easy run (per athlete)            +    │ +MP +800m +Mile                │
│ Export    │ Thu  Auto · easy run (per athlete)            +    │ +K reps +Long +Cooldown        │
│ Settings  │ Fri  Auto · easy run (per athlete)            +    │                                │
│           │ Sat  ▌ 16 mi LR  16.0 mi                      ✕    │ PACE REFERENCE  ◄─ DUPLICATE   │
│           │ Sun  Auto · easy run (per athlete)            +    │ Rec Easy LR Mod Steady MP      │
│           │                                                    │ HM LT 10K 5K 3K Mile           │
│           │                                                    │                                │
│           │                                                    │ 😴 Replace with Rest Day       │
│           │                                                    │ ┌────────────────────────────┐ │
│           │                                                    │ │ + Replace with New Workout │ │
│           │                                                    │ └────────────────────────────┘ │
│           │                                                    │ REPLACE FROM LIBRARY           │
│           │                                                    │ Search templates…              │
│           │                                                    │ Easy run                  10 mi │
│           │                                                    │ …                              │
└───────────┴────────────────────────────────────────────────────┴────────────────────────────────┘
```

### File map

| Region | File | Notes |
|---|---|---|
| Header (plan name, distance, duration, pace ref) | [plan-builder-client.tsx:430-540](web/src/components/coach/plan-builder-client.tsx#L430) | Lines 539-547 host PaceReferenceEditor (now full-width) |
| Pace ref card | [pace-reference-editor.tsx](web/src/components/coach/pace-reference-editor.tsx) | Just rebuilt — clean, grouped Race/Training table, race-time editable |
| Week selector tabs | [plan-builder-client.tsx:550-580](web/src/components/coach/plan-builder-client.tsx#L550) | |
| Day grid (left side of body) | [plan-builder-client.tsx:580-770](web/src/components/coach/plan-builder-client.tsx#L580) (approx) | Each row is a button that opens the right panel for that day |
| Right panel (header + step editor + replace actions + library) | [plan-builder-client.tsx:770-980](web/src/components/coach/plan-builder-client.tsx#L770) | Inline; one big scroll container |
| Step editor (workout structure + ADD A BLOCK + duplicate Pace Reference) | [workout-step-editor.tsx](web/src/components/coach/workout-step-editor.tsx) (751 lines) | Renders inside right panel |
| Workout cards in library list | [workout-template-card.tsx](web/src/components/coach/workout-template-card.tsx) | |

---

## 2. Pain points

### P1. Right panel does too many things, no hierarchy
Stacked vertically in one scroll: **Steps editor** · **Workout Structure preview** · **+reps / Notes** · **ADD A BLOCK** (9 buttons) · **PACE REFERENCE** (12 zones, ~80px tall) · **Replace with Rest Day** · **+ Replace with New Workout** · **REPLACE FROM LIBRARY** + search + list.

Nothing groups these. They share visual weight despite being different *kinds* of action (edit current vs swap current vs add another).

### P2. "How do I replace a workout?" — three answers, none obvious
Today there are three different replace controls:
- **Rest Day button** (mid-panel) → swaps to rest
- **+ Replace with New Workout** (orange button) → opens a fresh blank builder
- **Replace From Library** → search + click a template card

A coach landing on the right panel sees the step editor first, then keeps scrolling, then encounters three things called "Replace …". The decision tree isn't obvious. From the screenshot, the user explicitly said "I really don't know how to replace workouts."

### P3. Pace Reference duplicated
The new header card (Pace Ref, Race/Training table) and the right-panel `PaceZoneReference` ([workout-step-editor.tsx:705-736](web/src/components/coach/workout-step-editor.tsx#L705)) show **the same data**. Two cards. ~80–100 vertical px wasted.

### P4. Left day rows feel non-interactive
Empty days render as `Auto · easy run (per athlete)            +`. The `+` is small, low-contrast, and the row itself doesn't look clickable. A coach who hasn't used this before wouldn't guess that *clicking the row* (or the +) opens the picker.

### P5. Active-day affordance is subtle
The selected day (`Sat`) gets a thin coral left bar + coral border. Easy to lose when the right panel is the focus. Should be unmistakable — selected day is the *thing being edited*, the right panel is its property sheet.

### P6. Tiny fonts everywhere
Same problem we fixed in the pace ref: text-[9px], text-[10px], text-[11px] across right panel labels ("STEPS", "WORKOUT STRUCTURE", "PACE REFERENCE", "REPLACE FROM LIBRARY"). Coach tooling on a desktop should default to text-xs minimum.

### P7. "Workout Structure" duplicates the Steps list
Right panel shows **STEPS** (the editor with `Active 16 mi @ LR …`) AND **WORKOUT STRUCTURE** (the bar chart preview with `≈ 16.0 mi` + `16 mi @ LR  6:34-7:16/mi`). Reading the same thing twice in different formats.

### P8. ADD A BLOCK is a wall of buttons
Nine pill buttons (+Warmup, +Easy run, +Tempo block, +MP block, +800m reps, +Mile reps, +K reps, +Long run, +Cooldown). No visual grouping (warmup/cooldown vs reps vs continuous blocks). Hard to scan.

---

## 3. Proposed restructure

### Information architecture: 3 modes, 1 panel
The right panel today tries to be **edit + replace + create** simultaneously. Split into three **mutually exclusive modes** with a clear switcher at the top:

```
┌─ EDIT — SAT ──────────────────────────────────┐
│ [Edit]  [Replace]  [Clear]      ✕ close       │  ← mode switcher
├───────────────────────────────────────────────┤
│  (mode-specific content fills the panel)      │
└───────────────────────────────────────────────┘
```

- **Edit** (default when day has a workout) → step editor + workout-structure preview + ADD A BLOCK
- **Replace** → swap-source picker (3 tabs: From Library · From Quality Pool · Build New)
- **Clear** → confirm dialog ("Set Sat to rest" / "Clear assignment back to auto-fill")

Pace Reference is **not** in this panel anymore — header card is the single source of truth.

### Edit mode layout
```
┌─ STEPS ───────────────────────────── + Save to library ─┐
│ │ Active 16 mi @ LR  ±s/mi  exact                       │
│   + reps                                                 │
│   Notes (e.g. 'build effort mile 4'…)                    │
│ ─────────────────────────────────────────────────────── │
│   16 mi @ LR    6:34-7:16/mi                             │  ← inline summary, no second card
├─ ADD STEP ──────────────────────────────────────────────┤
│  Continuous     Reps                Bookend             │
│  + Easy run     + 800m reps         + Warmup            │
│  + Long run     + Mile reps         + Cooldown          │
│  + Tempo block  + K reps                                │
│  + MP block                                             │
└─────────────────────────────────────────────────────────┘
```

- Kill the "Workout Structure" duplicate preview — fold the per-step pace range into the step editor row itself
- Group ADD STEP buttons by kind (Continuous / Reps / Bookend) with subtle column headers

### Replace mode layout
```
┌─ REPLACE Sat workout ───────────────────────────────────┐
│  ( From Library )  ( From Pool )  ( Build New )         │  ← tabs
├─────────────────────────────────────────────────────────┤
│  Search templates…                                       │
│  ┌─ Easy run · 10 mi                                  ─┐│
│  ┌─ 7 x mile @ LT · 11 mi                             ─┐│
│  ┌─ MP cutdown · 14 mi                                ─┐│
└─────────────────────────────────────────────────────────┘
```

### Day grid (left)
- **Empty day rows** → render as a faded "+ Add workout" line, full-row hover tint, cursor-pointer obvious. No more "Auto · easy run (per athlete)" muddled with clickable affordance — that copy moves into a tooltip / smaller subtitle.
- **Active day** → solid coral background or 4px coral left bar (today is 2px), so it's unmistakable from across the screen.
- **Quality vs easy/rest** → quality days get a small icon (• tempo, ▮ intervals, ━ long) so the week is scannable at a glance.

### Header
Already cleaner after Pace Ref rebuild. Remaining touch-up:
- Group Plan Name + Save Draft + Publish in one row (today they're crammed)
- Distance + Duration + Adaptive toggle in second row (today same row as name)
- Pace Ref card stays full-width as is

---

## 4. Migration steps (ordered, each independently shippable)

### Phase A — kill duplication (1 PR, low risk)
- [ ] Remove `PaceZoneReference` block from [workout-step-editor.tsx:705-736](web/src/components/coach/workout-step-editor.tsx#L705) — header card is the source of truth
- [ ] Remove "WORKOUT STRUCTURE" duplicate preview from right panel — keep only the step editor
- [ ] Bump tiny labels (`text-[9px]/[10px]/[11px]`) to `text-xs` minimum across right panel

### Phase B — mode switcher (1 PR, the big one)
- [ ] Add `mode: "edit" | "replace" | null` state to right panel
- [ ] Add tab/segment control at top of right panel (only visible when a day has an assignment)
- [ ] Move Rest Day + Library search + Build New out of the always-stacked layout into the Replace mode tab content
- [ ] Empty-day default opens directly to Replace mode

### Phase C — ADD STEP grouping (small)
- [ ] Group the 9 buttons into 3 columns: Continuous / Reps / Bookend
- [ ] Subtle column header above each group

### Phase D — day grid affordance (small)
- [ ] Empty day rows render as "+ Add workout" with full-row hover
- [ ] Active day uses a stronger active treatment (4px bar or filled bg)
- [ ] Quality-day icon (tempo / intervals / long) for at-a-glance scanning

### Phase E — header polish
- [ ] Re-tier: row 1 = name + Save/Publish, row 2 = type/distance/duration, row 3 = pace ref
- [ ] Make Save Draft + Publish align right of plan name properly

---

## 5. Open questions

1. **Right panel: drawer or fixed?** Today it's a fixed third column always present. Alternative: a slide-out drawer that appears when a day is selected. Drawer reclaims horizontal space for the day grid (helpful on smaller laptops), but loses always-visible context.
2. **Replace mode default tab?** Library, Pool, or Build New? My guess: Library, since most coaches work from saved workouts.
3. **"Quality Pool" ambiguity** — is the pool the saved-templates library, or an adaptive-plan-specific pool of session candidates the materializer rotates through? If the latter, "Replace with Pool item" is a different concept that needs its own data model.
4. **Build New from inside Replace** — does it open the same WorkoutStepEditor inline, or push to a fullscreen builder? Inline keeps context, fullscreen gives space.
5. **Save to Library affordance** — currently a small button next to "STEPS". Should it become a primary action after editing, or stay quiet?
6. **Notes field placement** — today inside Steps. Should plan-level notes (per week / per day rationale) live somewhere else?

---

## 6. Immediate next step (pick one)

**(a) Phase A — kill duplication.** Remove the duplicate Pace Reference and Workout Structure blocks, bump label fonts. Pure subtraction, ~30 min, instantly less cluttered. *Highest ROI for least risk.*

**(b) Phase D — day grid affordance.** Make empty days obviously clickable + bump active-day treatment. ~30-45 min. Solves "I don't know what's clickable."

**(c) Phase B — mode switcher.** Bigger lift (~2 hr). Solves the user's stated pain ("I don't know how to replace workouts"). Best long-term payoff but more design choices to nail.

**(d) Phase C — ADD STEP grouping.** ~30 min. Smaller win, makes the 9-button wall scannable.

My recommendation: **(a) → (b) → (c)**. (a) clears visual noise immediately; (b) makes the left grid feel like a real interface; (c) addresses the replace-flow confusion the user named.

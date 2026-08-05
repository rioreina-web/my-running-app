# Workout Detail — "Signals-first" redesign spec
**Date:** 2026-08-03 · **Mock:** `design-system/workout-detail-signals-mock.html` · **Target:** `RunningLog/RunningLog/Workouts/WorkoutRepReceiptView.swift`

## Goal
Cut the text walls from the workout detail sheet. Keep the workout structure (the note), keep a one-line Read, remove the AI insight entirely, and surface voice memos + niggles as compact signals instead of prose.

## What stays exactly as-is
- Act 1 (eyebrow · "July 28." title · source line · 4-cell stat strip · conditions plate)
- The hero rep chart (`RRRepBars`), tweaks row (HEAT-ADJ / PACE COLOR / ELEV / MI-KM), splits table, "Fix reps" button
- Act 3 collapsed traces (HR ZONES, PACE·HR·ELEVATION, HR RECOVERY, VS RECENT, ROUTE) with their one-line summary stats
- Footer ("— Logged … —" / DELETE LOG)

## Changes

### 1. THE READ → SIGNALS row + one-line read
Replace the `theRead` section body:
- **Remove:** the multi-sentence `insight` rendering, `insightLoading` state UI, and the **entire "Generate AI insight" button + `generateInsight()` call path**. (`insight`, `insightLoading`, `insightError` state and the edge-function call can be deleted from this view; do not delete the server function.)
- **Add: `signalsRow`** — a wrapping HStack (`FlowLayout` or simple wrap) of capsule chips, mono 10.5pt uppercase, white card background, 1px `divider` stroke, each with a 7pt status dot:
  - `SPREAD ±13s` — max work-rep pace minus min, from `rrReps`. Dot: sage if ≤ 15s, amber ≤ 30s, rose beyond.
  - `HR Z4 FROM R2` — first rep whose avg HR lands in the modal work zone (from existing `zoneSeconds` / lap avg HR). Dot: sage Z1–3, amber Z4, rose Z5.
  - `DRIFT +8%` — existing cardiac drift calc (already surfaced in the rep scrubber's DRIFT field). Dot: sage < 5%, amber 5–10%, rose > 10%.
  - `HEAT +6s/mi` — `heatAdjustSec`. Only rendered when non-nil (same ≥3 s/mi bar). Dot: amber.
  - `VS PLAN ON TARGET` — only when a `prescription`/target exists: rep avg vs `targetSec` (sage within 5s/mi, amber within 15, rose beyond).
  - Hard rule 8 applies: any chip whose input is missing **drops out** — never a placeholder.
  - Chips are tappable → scroll/expand the relevant trace (HR chips → HR ZONES, drift → telemetry). Fine to ship non-tappable first.
- **Keep:** `computedRead` as a **single italic sentence**, `.dripBody(13).italic()`, `textSecondary`, `.lineLimit(2)`. It renders *below* the chips. The coral "SIGNALS" eyebrow replaces the coral "THE READ" eyebrow (still the cluster's one coral mark).

### 2. THE WORKOUT — keep the note, render as a recipe
The current eyebrow crams the whole structure into one all-caps line ("3 MILES WARMUP + 4 SETS OF (…)"). Replace with a `workoutRecipe` block between SIGNALS and the qualitative row:
- Eyebrow `THE WORKOUT` left, compact pattern (`4 × (1MI + 2MI)` — from `repHeadline`) right.
- Body: one row per segment from the parsed structure (`prescription` / `parsedIntent`), left-aligned on a 2px `paperDeep` spine; work-block rows get a coral spine segment and a small `×4` ink tag:
  - `3 mi  warmup`
  - `×4  1 mi @ 6:00  400m jog`
  - `    2 mi @ 6:25  400m jog`
  - `2 mi  cooldown`
- Distances/paces mono 12.5pt semibold; rest legs italic serif 11.5pt tertiary.
- Fallback: if the structure can't be parsed into segments, render the existing single line (current behavior) — never hide the note.
- The hero eyebrow then simplifies to `WORKOUTS & REPS` + `REP AVG 6:07 · REC 2:00 JOG` (the footer line moves up beside the eyebrow; delete `repsFooterLine` from below the table).

### 3. Voice memo — collapsed row
Replace `qualitativeRow`'s full-width quote:
- A tappable card (white, 1px divider stroke, 12pt radius): mood pill (existing `MoodBadge`) + play capsule (`▶ 1:12`, coral stroke — wire to the memo's audio URL; hide when no audio) + `VOICE MEMO` tertiary eyebrow + chevron.
- Below, the quote `.lineLimit(1)` italic 13pt `textSecondary`. Tap toggles expanded: full quote, `textPrimary`, chevron rotates 90°. `withAnimation(.easeOut(duration: 0.2))`.
- When there's no memo at all, the slot renders the **record button** instead — see §6. (The old drop-out rule is replaced.)

### 4. Niggles — status chips
New row under the voice card:
- One capsule per niggle that is (a) currently active/watching in `athlete_state`, or (b) mentioned on this run's memo (niggle classifier output).
- Style: mono 10pt uppercase, wash background + 1px stroke in the status color — amber `WATCHING`, rose `ACTIVE/FLAGGED`, tertiary + strikethrough for resolved-this-block. 6pt leading dot, trailing `↗`.
- Tap → the niggle record (same destination as the Niggles screen row).
- Surfaced, never interpreted (niggles rule): the chip states name + status only, no advice.
- Row drops out when there are no niggles to show.

### 5. Splits & reps — imported from Strava, never synthesized
Hard rule for the hero chart, splits table, and every signal computed from them:
- **`rrReps`, the splits table, and the rep chart must be built from the activity's actual Strava laps** (the `laps` payload from the existing Strava sync — same data the current view has). Every Split/Pace/HR/Elev value shown is the imported lap value; nothing is estimated, rounded to "nice" numbers, or generated to fill the table.
- If the athlete's watch recorded **no laps**, fall back to Strava's standard mile splits (`splits_standard`) and label the table eyebrow `MILE SPLITS` instead of `REP`.
- If **neither** exists, the table renders a single quiet row — `No splits from Strava` (italic, tertiary) — and the rep chart falls back to the flat distance bar. **Never fabricate splits.** Signal chips whose inputs come from laps (SPREAD, VS PLAN) drop out per rule 8.
- Heat-adjust / pace-color / mi-km tweaks operate on the imported values only.
- Strava is the source of truth for now; keep the lap-ingest path behind the existing sync layer so Garmin can slot in later.

### 6. Voice memo missing → record button (top of Act 2)
If the run has **no linked voice memo** (didn't get captured post-run), the memo slot does not drop out — it becomes a record affordance, sitting high on the sheet in the same position:
- Same card frame as the voice card, but dashed 1px `divider` stroke, wash background: coral mic dot + `RECORD VOICE MEMO` mono 10pt + italic serif hint *"30 seconds on how it felt."*
- Tap → the existing post-run recorder flow, pre-linked to this workout entry. On save: run the normal pipeline (transcribe → mood → niggle classifier), then this slot re-renders as the standard collapsed voice card and the niggle row refreshes.
- Only for the no-memo case; a run with a memo never shows a record button (append/re-record is out of scope for this pass).

### 7. Deletions
- `theRead`'s AI branch, `generateInsight()`, `insight/insightLoading/insightError` state.
- `repsFooterLine` (content moves to the hero eyebrow's right slot).
- The old full-quote `qualitativeRow` layout.

## Order (Act 2)
`SIGNALS (chips + 1-line read)` → `THE WORKOUT recipe` → `voice memo row (or record card, §6)` → `niggle chips` → hairline → `WORKOUTS & REPS` hero.

## Data notes for the agent
- Spread/drift/zone inputs all already exist in this view (`rrReps`, `zoneSeconds`, drift calc in the scrubber, `heatAdjustSec`, `targetSec`).
- Niggle status: `athlete_state` niggles + this run's classifier mentions (see `niggle-classifier-implementation-*.md` in outputs/). If plumbing that into this view is heavy, ship phase 1 with active/watching niggles only.
- Voice memo audio URL + duration come from the linked voice log (`voice_logs` via the entry); the play capsule can be phase 2 — ship the row with pill + quote first.
- Empty states: every new element drops out when its data is missing — **except the voice memo slot, which becomes the record button (§6)**. A voice-only run renders: Act 1 → (chips that survive) → recipe/fallback line → voice row → no-data state.
- Splits provenance: laps come from the stored Strava activity (`laps`, fallback `splits_standard`). If the current view derives `rrReps` any other way, fix that first — the display layer must never invent a split.

## Acceptance
1. No "Generate AI insight" button anywhere on the sheet; no multi-paragraph AI text.
2. The Read never exceeds 2 lines.
3. Voice memo shows exactly one line until tapped.
4. Workout structure is visible, segmented, and readable without horizontal cramming.
5. A run with no memo, no niggles, no prescription shows no empty placeholders — except the record-memo card, which is the one intentional affordance.
6. Every value in the splits table matches the Strava lap data for that activity exactly; a run with no Strava laps shows the mile-splits fallback or the "No splits from Strava" row — never invented numbers.
7. A run without a voice memo shows the record card at the top of Act 2; recording from it attaches the memo to this workout and the card becomes the standard voice card.

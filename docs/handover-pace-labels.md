# Handover: Pace Labels — What They Are, What They Should Be

**For:** Claude cowork (product / UX design)
**Owner:** rioreina
**Date authored:** 2026-04-23
**Status:** Pre-design. The owner has flagged the current labels as
"decorative and useless." Goal: figure out whether to fix, repurpose, or
remove.

---

## 1. The owner's complaint in one sentence

> "The pace labels — what are those? It just gives 5K/10K. Seems like a useless feature."

The athlete sees a small colored chip next to each workout step's pace
(e.g., `6:30/mi  HM`). The chip doesn't link anywhere, doesn't explain
what HM means for *their* fitness, and feels like a sticker that adds
visual weight without giving information.

## 2. What pace labels are today

### 2a. The vocabulary (12 zones)

Defined as `NamedPace` enum in
[`PaceModels.swift:180-224`](RunningLog/RunningLog/Models/PaceModels.swift#L180-L224).
Twelve named zones, each with a `displayName` and a `shortName`:

| Short | Display | Conceptually |
|---|---|---|
| Rec | Recovery | Slowest aerobic, post-hard-day |
| Easy | Easy | Daily aerobic |
| LR | Long Run | Slightly faster than easy, sustained |
| Mod | Moderate | 75-85% effort |
| Steady | Steady | 85-95% effort, ~MP-ish |
| MP | Marathon Pace | Goal marathon race pace |
| HM | Half Marathon Pace | Goal half race pace |
| LT | Threshold | 1-hour pace, lactate threshold |
| 10K | 10K Pace | Goal 10K race pace |
| 5K | 5K Pace | Goal 5K race pace |
| 3K | 3K Pace | Goal 3K race pace |
| Mile | Mile Pace | Goal mile race pace |

### 2b. What drives which label appears

Two paths, depending on whether the coach was explicit:

1. **Coach wrote `paceZone` on the step** (e.g., `paceZone: "hm"`):
   the badge displays "HM" directly. Authoritative.
2. **No paceZone stored** (warmups, cooldowns, generic easy steps): the
   badge does a *nearest-match search* across the athlete's pace table
   with a 10-second tolerance. Whichever zone is closest within ±10s wins.
   Falls back to no badge if nothing's close.

In practice today: most coach-authored quality steps show the right label
(HM, 3K, etc.). Most warmups and cooldowns show "Easy" via the
nearest-match fallback. Long runs, recovery runs, moderate/steady — these
zones almost never appear because:
- The LLM authoring vocabulary is impoverished (only emits 6 of the 12 zones)
- The nearest-match tolerance is tight (10s) and often misses

### 2c. Where labels appear in the iOS app

- **Workout card** — small chip next to the pace text on each step
  ([WorkoutDetailView.swift:347-381](RunningLog/RunningLog/Workouts/WorkoutDetailView.swift#L347-L381))
- **Workout step detail sheet** — same chip when the step is tapped
- **Pace Chart screen** — the actual zone definitions live here
  (5K @ 4:50, 10K @ 5:01, HM @ 5:14, MP @ 5:29, Easy 6:28+, etc.)

### 2d. What labels connect to today

**Nothing.** The chip is decorative. Tapping it does nothing. Tapping
the step opens the detail sheet (which I added recently) but the sheet
just shows pace + splits + effort description — no link to the Pace
Chart, no "this is your HM pace because…" provenance.

The Pace Chart and the workout-card label live in separate worlds:

```
Pace Chart screen      ← athlete sees: HM = 5:14/mi
       ↕ no connection
Workout card label     ← athlete sees: "HM" chip next to 5:34/mi
```

So the same word "HM" appears in two places with two different paces and
no way for the athlete to reconcile them.

## 3. Why this matters

Three downstream effects of the current state:

1. **Labels feel decorative.** The athlete can't act on "HM" — they
   can't tap to learn more, can't compare to their actual HM pace,
   can't change which zones display.
2. **Labels can mislead.** The chip says "HM" because the *coach* labeled
   it HM, but the displayed pace might not match the athlete's actual HM
   pace from the Pace Chart (e.g., chart says HM = 5:14, workout shows
   5:34 because the coach added "+3%"). The chip is silent on this gap.
3. **Vocabulary is impoverished.** Only 4-5 of the 12 labels actually
   show up in real plans, even though the system supports all 12. Coaches
   prescribe in moderate/steady/threshold/longRun and those almost never
   reach the athlete.

## 4. The four design questions to answer

### Q1 — Are labels kept, repurposed, or removed?

Three philosophical options:

- **(a) Remove them.** The pace range is the information. Labels add
  visual noise. Some apps (Strava workouts, basic Garmin plans) show
  no label, just the pace.
- **(b) Keep but make tappable.** Tapping "HM" opens the Pace Chart
  with the HM zone highlighted. Labels become a navigational hint
  ("this is your HM pace — tap to see the full table").
- **(c) Replace the label with the underlying pace name + concrete value.**
  Instead of "HM" chip → render "HM (5:14/mi)" inline so the athlete
  always sees the connection between the workout's pace and their zone
  table.

The owner's instinct in conversation suggests they want either (b) or (c).
(a) only makes sense if labels add zero value, which they could if the
pace alone communicates intent clearly.

### Q2 — How do labels handle the "coach-wrote-X-but-pace-doesn't-match" case?

Current data shape allows: `paceZone: "hm"` + `target_pace: "5:34"` while
the chart says HM = 5:14. The coach intentionally said "HM + 3%" but the
athlete sees "HM 5:34" with no acknowledgment of the offset.

Options:

- Show the modifier in the label: "HM +3%" chip
- Show just the pace, drop the label when there's a modifier
- Show the concrete pace and athlete-friendly description: "Just under
  HM" / "Slightly slower than HM"
- Keep "HM" as-is and accept that the chart is the source of truth for
  what HM is

### Q3 — Should we expand the labels the LLM uses?

LLM authoring (`custom-plan-builder`) currently emits only 6 of the 12
zones. Recovery, longRun, moderate, steady, threshold rarely or never
appear in generated plans. Coach-authored plans have more variety but
still lean on the same 6.

Options:

- Force the LLM to use the full vocabulary in its prompts
- Drop the unused zones from the enum (simplify)
- Add coach-side authoring UI that surfaces all 12 with examples

### Q4 — Athlete vocabulary vs coach vocabulary

Coaches think in "HM," "threshold," "MP." Some athletes think the same
way; many think in effort terms — "easy," "comfortable hard," "all out."

Should labels:

- Stay coach-vocabulary (current)
- Show athlete-vocabulary by default with coach terms in parens
- Let the athlete pick a vocabulary preference

The Pace Chart already mixes both (it shows "Easy 75% effort or less" —
effort vocabulary).

## 5. Touchpoints (for the engineer once design lands)

Code:

```
RunningLog/RunningLog/Models/PaceModels.swift          NamedPace enum (lines 180-224)
RunningLog/RunningLog/Models/PaceModels.swift          closestNamedPace + tolerance (lines 440-451)
RunningLog/RunningLog/Workouts/WorkoutDetailView.swift Workout card badge (lines 347-381)
RunningLog/RunningLog/Workouts/PaceChartView.swift     Pace Chart screen
RunningLog/RunningLog/Workouts/PaceChartViewModel.swift Chart data source
RunningLog/RunningLog/Models/AthletePaceProfile.swift   Per-zone pace profile
supabase/functions/custom-plan-builder/index.ts        LLM authoring vocabulary
supabase/functions/_shared/resolve-pace.ts             Server-side zone → pace resolver
```

Data:

- `scheduled_workouts.workout_data.steps[].paceZone` (coach intent)
- `scheduled_workouts.workout_data.steps[].target_pace` (concrete pace)
- `scheduled_workouts.workout_data.steps[].paceAdjustment` (modifier like +3%)
- `athlete_pace_profiles.*_pace_seconds` (concrete pace per zone)

## 6. Things the design should NOT touch

To keep scope contained, defer these:

- The pace adjuster (slow-adjustment math) — separate feature
- Goal editing / soft-ask flow — separate feature
- Weather adjustments — separate feature
- Day-picking / weekly templates — separate feature
- Workout authoring tools (LLM prompts, custom-plan-builder) — only
  touch if the design requires the LLM to emit different labels

## 7. Prior decisions to respect

These are settled and should inform the design without re-litigating:

1. **Goal-anchored paces.** When a goal is set, paces derive from it; not
   from current fitness. Labels should reflect this anchor.
2. **No hardcoded pace defaults.** All paces from real athlete data.
3. **AI advises, never acts.** The label is a coach's voice; the LLM
   chooses which zone, but the athlete confirms paces via accept flow.
4. **No Daniels/Pfitzinger RAG.** Don't introduce textbook zone naming
   from those systems just to fill out the vocabulary.
5. **Easy runs use whole miles.** Distance-related, not label-related,
   but a worth-knowing principle.

## 8. Inputs cowork should ask for before designing

- Three example workouts with screenshots — one easy, one tempo, one
  intervals — so they can see the badge in context.
- The current Pace Chart screen — owner can screenshot.
- Owner's instinct on the Q1 trichotomy (remove / make tappable / show
  pace + name inline) and Q4 vocabulary preference.
- Whether coaches should be able to define custom labels per-athlete or
  per-plan ("Bobby's HM pace = 5:23" with that label saved on his plan).

## 9. Success criteria

The redesign ships successfully if:

1. The owner can articulate, in one sentence, what each label means and
   what it connects to.
2. The athlete can tap a label and end up somewhere useful (or, if labels
   are removed, the workout card communicates the same intent through
   pace + structure alone).
3. The owner doesn't say "useless feature" again.

## 10. One-paragraph summary for the cowork task

> The iOS app displays a small "5K / 10K / HM / Easy" chip next to each
> workout step's pace. The chip is decorative — taps go nowhere, doesn't
> connect to the athlete's Pace Chart, and the same word "HM" can show
> different paces in two places without explanation. Twelve zones exist
> but only 4-5 ever appear because the LLM uses a small subset. Decide:
> (1) keep / repurpose / remove labels, (2) how to bridge the gap when
> the displayed pace differs from the athlete's chart zone, (3) whether
> to expand the active vocabulary, and (4) coach vs. athlete language.
> Respect the goal-anchored, AI-advises-never-acts, and no-textbook-RAG
> principles. Out of scope: pace adjustment math, goal editing, weather,
> day-picking.

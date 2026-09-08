# Manual Workout Entry — Feature Plan

**Date:** 2026-06-19
**Status:** Draft for review
**Owner:** Rio
**Wedge persona:** Maya (self-coached endurance runner)

---

## 1. Problem Statement

Not every workout reaches the app through HealthKit or Strava. Maya runs on a
treadmill that doesn't sync, forgets to start her watch, does a strength or
cross-training session that no running tracker captures, or simply wants to
back-fill a session from memory. Today the only non-synced path is a voice memo,
which forces her to *talk* and wait ~60s for transcription. There is no way to
type a workout in directly with the date, distance, and time she already knows.

The cost of not solving this: gaps in the training journal, which corrupts the
two things the product exists to do — read the **journey** honestly and feed the
**training context** (ACWR, volume, fitness, mood, niggles). A missing
treadmill run makes ACWR read artificially low; a missing strength session makes
the journal lie about how hard the week actually was.

---

## 2. Goals

1. **Let Maya add any workout in under 30 seconds** without recording audio —
   type it in one box, let Gemini fill the stats, confirm or edit, save.
2. **Make manual runs first-class in the training context** — they count in
   volume, ACWR, and fitness math identically to synced runs (per the decision
   below), so the journey stays accurate.
3. **Parse the text into stats with Gemini, then let the athlete edit** — extract
   distance, duration, type, pace, mood, and niggles from the free text, present
   them as editable fields, and never save numbers the athlete hasn't confirmed.
4. **Reuse existing infrastructure** — `source='manual'` on `training_logs`,
   the athlete-state invalidation trigger, and the coachable-moment rules already
   exist. No new fitness-math logic should be required.
5. **Close the cross-training journal gap** — let strength and cross-train
   sessions appear in the journal while staying out of running-fitness math.
6. **Show manual entries everywhere synced workouts appear** — Log journal,
   Trends analytics, and the Train calendar/history all include them, so a
   manually-added workout is indistinguishable from a synced one in the journey.
7. **Let the athlete edit a manual entry after saving** — fix a wrong distance
   or change the type later, with the training context recomputing on save.

---

## 3. Key Decisions (locked 2026-06-19)

| Decision | Choice | Rationale |
|---|---|---|
| Primary input | **Single text box, parsed by Gemini** | Maya types the workout in plain language ("ran 6 easy this morning, legs heavy, 52 min"); Gemini extracts the stats. Reuses the voice pipeline (`process-training-memo` → `parse-workout-structure`) minus transcription. One box, fast to fill. |
| Parsed stats are editable | **Yes — confirm-and-edit step** | Gemini pre-fills distance, duration, type, pace, mood; **every field is editable before save.** Honors "AI advises, never acts" — the athlete confirms the numbers. Also covers the "no distance given" case (field comes up blank to fill). |
| Workout types in scope | **Run + Cross-train + Strength** | Covers the real journal gap. Cross-train/strength stay out of running-fitness math per the existing hard rule. Rest/Race deferred. |
| Fitness-math weight | **Same as synced** | A manual run counts fully in ACWR, volume, and pace/fitness. Trusts the athlete's confirmed entry; simplest model. (Source is still tagged `manual`, so we can revisit confidence later without a data migration.) |

---

## 4. Non-Goals (v1)

1. **No fully-automatic save.** Gemini never writes stats straight to the
   training context. The parse always lands in an editable confirm screen the
   athlete approves. (Detailed work-bout `parsed_structure` decomposition — e.g.
   "5×1mi @ 5:19" broken into reps — stays a P2 enrichment; v1 parses the
   top-line stats and pace, not the full interval tree.)
2. **No Rest or Race entry type.** Race entries need result capture
   (`race_result` JSONB) and confirmed-race anchoring logic — separate scope,
   tied to the race-performances feature plan.
3. **No editing/splitting of *synced* workouts.** Editing applies to
   manually-created entries (P0-6). Manual entry does not reconcile against or
   override HealthKit/Strava rows, and editing a synced row is out of scope.
4. **No manual GPS/pace-segment entry.** Pace is derived from distance ÷
   duration only. No per-split input. (`pace_segments` stays null for manual.)
5. **No web/coach-portal entry surface.** iOS-first, matching where Maya lives.
   Coach surfaces are deprioritized per current product state.

---

## 5. User Stories

**Adding a workout**

- As a self-coached runner, I want to type in a treadmill run I just finished
  (date, distance, duration) so that my volume and ACWR stay accurate.
- As a runner, I want to add a strength session so that my journal reflects the
  full week's load even though it isn't a run.
- As a runner, I want to describe how a workout felt in my own words so that the
  Coach Read and Niggles surfaces pick up my mood and any aches.
- As a runner, I want to back-fill a workout from a few days ago by changing the
  date so that a forgotten session isn't lost.

**Edge / empty states**

- As a runner who only enters distance and duration, I want a reasonable result
  (pace computed, no errors) even if I leave the description blank.
- As a runner entering a cross-train session, I want it shown in my journal but
  clearly *not* inflating my running fitness numbers.
- As a runner, I want a clear confirmation the workout saved (no 60s wait, since
  there's no audio to transcribe).

---

## 6. Requirements

### Must-Have (P0)

**P0-1 — Text-box entry (iOS).**
A single free-text box opened from the Log tab's existing voice/manual toggle
(front door of `LogView.swift`). Maya types the workout in plain language. One
optional control above the box: **Date** (picker, defaults to today, ≤ today).
Everything else is parsed from the text in P0-2.

Acceptance criteria:
- [ ] Given an empty text box, then "Parse" / save is disabled.
- [ ] Given a future date, then it cannot be selected.
- [ ] The box uses the empty-state pattern for its placeholder/hint, never
      em-dashes (hard rule #8); placeholder shows an example entry.

**P0-2 — Gemini parses the text into editable stats.**
On submit, send the text to a Gemini parse (reusing the voice pipeline's
extraction prompt, no transcription step). Return a structured draft:
`workout_type`, `workout_distance_miles`, `workout_duration_minutes`,
`workout_pace_per_mile`, `mood`, and detected niggles.

Acceptance criteria:
- [ ] **Every parsed field renders in an editable control** — type segmented
      control (Run · Cross-train · Strength), distance number, duration number,
      mood selector (`MoodRadio`/`MoodPill`, closed vocab), niggle chips.
      Nothing is read-only.
- [ ] Given the text omits a value (e.g. no distance), then that field renders
      **blank/empty-state** for the athlete to fill — Gemini does not invent it.
- [ ] Given a low-confidence parse, the field is still shown and editable; the
      athlete's edit always wins over Gemini's guess.
- [ ] Pace is derived from confirmed distance ÷ duration, not free-typed; it
      recomputes live as the athlete edits those two fields.
- [ ] Per hard rule #3, the parse prompt ships with eval-harness cassette
      coverage in `_evals/cassettes/<prompt-name>/` before launch — CI enforces
      this gate on any file in `_shared/prompts/`.

**P0-3 — Confirmed entry writes a `training_logs` row.**
Only after the athlete reviews/edits and taps save, write a row with
`source='manual'`, `workout_date`, the confirmed `workout_type`,
`workout_distance_miles`, `workout_duration_minutes`, `workout_pace_per_mile`,
`mood`, and `notes` (= the original typed text, preserved verbatim).

Acceptance criteria:
- [ ] Nothing is written to `training_logs` until the athlete taps save on the
      confirm screen — Gemini never auto-commits ("AI advises, never acts").
- [ ] The insert is scoped to the authenticated user (`user_id = auth.uid()::text`),
      passing the existing `rls_training_logs_insert` policy — no new RLS needed.
- [ ] The existing `trg_invalidate_athlete_state` trigger fires on insert, so the
      next AI read rebuilds athlete-state including this workout.
- [ ] `workout_type` for cross-train/strength is set so athlete-state's
      running-fitness filters exclude it from ACWR / volume / pace math.
- [ ] No audio path: `audio_url`, `pace_segments`, `external_streams` stay null.
- [ ] The original typed text is stored in `notes` so a re-parse or audit is
      always possible.

**P0-4 — Niggles extraction from the typed text.**
Run the same niggles (body-part mention) detection used on voice `cleaned_notes`
over the manual text, surfaced as editable chips on the confirm screen.

Acceptance criteria:
- [ ] Body-part mentions are detected against the **closed ~30-item vocabulary**
      and written to `body_mentions` with `verbatim_quote` preserved
      (hard rule #2; see `outputs/body-mentions-design.md`).
- [ ] The detector **never** outputs a diagnosis, severity score it invented, or
      a recommended action — surface, never interpret.
- [ ] Detected niggles show as chips the athlete can **remove** before save; only
      confirmed chips are written to `body_mentions`.
- [ ] If the text mentions no body part, no niggle is created and the row still
      saves.

**P0-5 — Manual runs count in the training context.**
Because athlete-state rebuilds from `training_logs` and the coachable-moment
rules read athlete-state, a manual run automatically flows into
`rolling_7d_miles`, `acwr`, `recent_workouts[]`, `mood_trend`, etc. No rule code
changes expected.

Acceptance criteria:
- [ ] Given a manual run added today, when athlete-state next rebuilds, then it
      appears in `recent_workouts[]` and is included in volume/ACWR.
- [ ] Given a manual cross-train/strength session, then it appears in the journal
      and `recent_training_summary` prose but is **not** counted in ACWR or
      fitness prediction (matches the cross-training exclusion rule).
- [ ] `loadSpikePlusInjury`, `lowMoodStreak`, etc. evaluate the manual entry
      without modification.

**P0-6 — Edit a manual entry after saving.**
A saved manual entry can be reopened and edited — change distance, duration,
type, mood, niggles, or the underlying text. On save, the same recompute and
recalculation that happen on create run again.

Acceptance criteria:
- [ ] Given a saved manual entry, when the athlete opens its detail and taps edit,
      then all fields are editable (the same confirm-screen controls).
- [ ] Given an edited entry, when saved, then the `training_logs` row is UPDATEd
      (scoped to `user_id = auth.uid()::text` via `rls_training_logs_update`),
      `trg_invalidate_athlete_state` fires, and volume/ACWR/pace recompute.
- [ ] Given an edited description, then niggles are re-detected; chips the athlete
      removed stay removed, and `body_mentions` is reconciled (no orphans, no
      dupes — the unique `(user_id, training_log_id, body_area)` index holds).
- [ ] Editing is offered **only for `source='manual'`** rows — synced rows do not
      expose edit (Non-Goal #3).
- [ ] Delete is available from the same edit surface; deleting also fires the
      athlete-state invalidation and cascades `body_mentions` for that entry.

**P0-7 — Manual entries appear on every training surface.**
A manual entry is a normal `training_logs` row, so it must render wherever synced
workouts render: the **Log** journal, **Trends** analytics, and the **Train**
calendar + history. No surface filters on `source`.

Acceptance criteria:
- [ ] **Log** — the entry appears in the 6-month journal at its `workout_date`,
      alongside runs/cross-train/strength, same as a synced workout.
- [ ] **Trends** — the entry feeds the volume tile, ACWR, and the 26-week fitness
      chart (runs only); cross-train/strength show in the journal but stay out of
      the running-fitness tiles. Any niggles feed the NIGGLES tile + timeline.
- [ ] **Train** — the entry shows in CURRENT (this week), CALENDAR (its day), and
      HISTORY (pace × volume, cycle overlays) for runs.
- [ ] No training surface visually flags the row as "manual" differently from
      synced (decision: "same as synced") — though `source='manual'` is on the
      row for future use.
- [ ] An empty day with no workout still uses the empty-state component, never an
      em-dash (hard rule #8).

### Nice-to-Have (P1)

- **P1-1** Pace-zone label on the confirm screen. Once distance+duration are
  confirmed, show the derived pace and its zone label (Easy/MP/LT/…) via
  `PaceCalculator.swift`. Ranges for aerobic, exact for race-pace, per the
  10-zone taxonomy.
- **P1-2** Re-parse button. If the athlete edits the text on the confirm screen,
  let them re-run the parse rather than only hand-editing fields.
- **P1-3** Parse-confidence affordance. Subtly mark fields Gemini was unsure
  about (vs. ones it read cleanly) so the athlete knows where to look.

### Future Considerations (P2)

- **P2-1** Full work-bout structure parsing + RPE extraction from the text
  (reuse `parse-workout-structure` / `extract-rpe` to decompose "5×1mi @ 5:19"
  into reps). Keep `parsed_structure` and `felt_rpe` nullable now so this lands
  without a migration.
- **P2-2** Manual Race entry with `race_result` capture + confirmed-race
  anchoring (ties to `race-performances-feature-plan.md`).
- **P2-3** Merging a manual entry with a later-synced duplicate (e.g. you typed
  a treadmill run, then a watch sync arrives for the same session). Editing of
  manual entries themselves is P0-6; this is specifically the dedupe/merge case.
- **P2-4** Web entry surface, if/when coach-dyad work is reinvested in.

---

## 7. How It Plugs Into the Existing System

```
iOS text box  ("ran 6 easy this morning, legs heavy, 52 min")
  └─ Gemini parse  (reuses voice extraction prompt, no transcription)
        → draft: type / distance / duration / pace / mood / niggle chips
  └─ EDITABLE CONFIRM SCREEN  ← athlete reviews, fixes, fills blanks
        (pace recomputes live from distance ÷ duration)
  └─ athlete taps SAVE  ← nothing is written before this
        └─ writes training_logs row (source='manual', user JWT → RLS passes)
              ├─ trg_invalidate_athlete_state → athlete-state rebuilds on next read
              └─ confirmed niggles → body_mentions upsert (service-role, closed vocab)
        └─ original typed text preserved in notes

Downstream (no new logic):
  athlete-state  → volume / ACWR / recent_workouts / mood_trend
  coachable-moment rules  → loadSpikePlusInjury, lowMoodStreak, …
  Coach Read  → reads manual notes as qualitative context
  Trends Niggles tile  → reads body_mentions
```

**Open implementation question:** the parse + niggles step should run in an
`ingest-manual-workout` edge function (mirrors the voice pattern: keeps the
Gemini prompt and the `body_mentions` service-role write server-side, one place
to validate/normalize). The function returns the draft to iOS for confirmation,
then a second call (or the same function with a `confirmed` flag) does the
`training_logs` write. Flagged for engineering (see Open Questions).

---

## 8. Files This Touches

**iOS (new):** `ManualWorkoutEntryView.swift` (text box + editable confirm
screen, reused for post-save edit), `ManualWorkoutViewModel.swift` (calls parse,
holds the editable draft, handles create + update + delete).
**iOS (edit):** `App/LogView.swift` (wire the manual toggle to open the box;
journal already renders all `training_logs` rows), `Models/TrainingLog.swift`
(insert/update struct), reuse `Workouts/PaceCalculator.swift` for the P1 pace
label.
**iOS (verify rendering, P0-7):** `Trends/TrendsTabView.swift` (volume/ACWR/
fitness/niggles tiles read athlete-state + `training_logs` — confirm no `source`
filter excludes manual), `Training/TrainingTabView.swift` +
`Training/MonthCalendarView.swift` (CURRENT/CALENDAR/HISTORY — confirm manual
rows render), `Workouts/WorkoutDetailPlate23.swift` (detail surface that opens
edit for manual rows).
**Backend (new):** `supabase/functions/ingest-manual-workout/index.ts` — Gemini
parse + niggles detection, returns draft; writes `training_logs` on confirm.
**Backend (reuse):** the voice extraction prompt (now used without transcription),
athlete-state invalidation trigger, niggles detector, `_shared/rules/*` — no
changes expected.
**Prompts/evals:** the parse prompt lives in `_shared/prompts/`; needs a cassette
in `_evals/cassettes/<prompt-name>/` before launch (hard rule #3, CI-enforced).
**DB:** none required — `source='manual'` already exists. (A migration is only
needed if we add a manual-specific column; default is none.)
**Design:** `design-system/ui_kits/ios_app/` — add/confirm an entry + confirm
sheet JSX so iOS has an intent reference; follow Post Run Drip voice + tokens.

---

## 9. Success Metrics

**Leading (days–weeks)**
- **Adoption:** % of active users who add ≥1 manual workout within 30 days.
  Target 25%, stretch 40%.
- **Completion:** % of opened manual-entry sheets that result in a saved
  workout. Target ≥ 80% (low abandonment = the form isn't fighting them).
- **Time to save:** median time from opening the sheet to save. Target < 30s.
- **Description attach rate:** % of manual entries that include a description
  (proxy for whether the extraction even has signal to work on).

**Lagging (weeks–months)**
- **Journal completeness:** reduction in suspicious ACWR dips that correlate
  with no-data days (harder to measure; proxy via gap-day frequency).
- **Retention:** do users who use manual entry retain better than those who hit
  data gaps? Compare cohorts at 8 weeks.

---

## 10. Open Questions

- **[Engineering]** Two-call vs. one-call confirm flow: does the parse and the
  save go through `ingest-manual-workout` twice (parse → return draft; confirm →
  write), or does iOS hold the draft and call once on save? Recommendation: parse
  server-side, return draft, write on a second confirmed call — keeps the prompt
  and `body_mentions` write server-side. *Blocking* for implementation start.
- **[Engineering]** Does the current niggles detector run as a standalone
  callable step, or only inside the athlete-state rebuild pass? If the latter,
  P0-4 needs it factored into a reusable call. *Blocking.*
- **[Engineering/Eval]** The parse prompt needs an eval cassette before it ships
  (hard rule #3). Can we reuse the `process-training-memo` cassette inputs minus
  audio, or do we record fresh text-entry cases? *Blocking for launch, not for
  build start.*
- **[Engineering]** Do Trends and Train already render any `training_logs` row
  regardless of `source`, or is there a `source IN (...)` filter anywhere that
  would hide manual entries? Quick audit needed to confirm P0-7 is "verify," not
  "build." *Blocking for P0-7 scoping.*
- **[Product/Design]** When Gemini can't determine the type, what's the default
  on the confirm screen — Run, or unselected forcing a choice? *Non-blocking.*
- **[Design]** How to show a low-confidence / blank parsed field without making
  the confirm screen feel like an error state? *Non-blocking; P1-3.*

---

## 11. Timeline / Phasing

- **Phase 1 (P0):** text box → Gemini parse → editable confirm → `training_logs`
  write + niggles extraction, **post-save edit/delete**, and **rendering across
  Log / Trends / Train**. This is the shippable core.
- **Phase 2 (P1):** pace-zone label on confirm, re-parse button, parse-confidence
  affordance.
- **Phase 3 (P2):** full work-bout structure/RPE parsing, race entry, editing.

No hard external deadline. Dependencies before Phase 1: confirm the niggles
detector is callable outside the athlete-state rebuild (Open Q #2), and record
the parse-prompt eval cassette (Open Q #3) before launch.

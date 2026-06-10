# Athlete-Side Adaptive Plan UX

Working doc for the missing athlete experience. Companion to
`adaptive-plan-builder-rework.md` (which covers the coach's side). Edit in
place. When you want something executed, point at a section.

---

## 1. The problem

"Adaptive" today means the *coach* authors flexibility and the *system*
materializes it once at `subscribe-to-plan` time. After that, the athlete's
UI is a read-only calendar. `/plan/page.tsx` is 202 lines of `SELECT …
ORDER BY scheduled_date` plus a compliance chart.

The athlete can't:

- Shift a quality day by a day or two ("I'm traveling Wed")
- Swap the rest day
- Skip or shorten a long run when life intervenes
- See **why** today is what it is (recovery because yesterday was long? pre-quality because tomorrow is a tempo?)
- Communicate "I'm flat this week, pull the volume" without asking the coach in chat
- Look ahead — the next 2 quality sessions the plan is building toward

All of that is baked in up front. The plan is prescribed *for* the athlete,
not planned *with* them. The product is called adaptive; the athlete's
experience is not.

**Brand frame.** Glass-box coaching means the athlete can see into the plan
and understand why. Read-only is a black box.

---

## 2. Target surfaces

Four surfaces. The first two are new; the third is a small dialog; the
fourth is a coach view.

### A. This Week view — primary athlete home screen

Replaces / supersedes `/plan/page.tsx`. Same URL, new shape.

```
┌─ This Week · Mon Apr 27 – Sun May 3 ─────────────────────────────┐
│                                                                    │
│  2:25 marathon plan · week 9 of 16 · build phase                  │
│                                                                    │
│  ┌──────────────────────────────────────────────────────────────┐ │
│  │ MON  Rest                                            ⋯       │ │
│  ├──────────────────────────────────────────────────────────────┤ │
│  │ TUE  Tempo                             [why?]  [move]        │ │
│  │      5 × 1mi @ 5:52/mi, 90s jog rec · 8mi total              │ │
│  ├──────────────────────────────────────────────────────────────┤ │
│  │ WED  Easy 6mi @ 7:00–7:25                            ⋯       │ │
│  ├──────────────────────────────────────────────────────────────┤ │
│  │ THU  Medium 8mi @ 6:40                               ⋯       │ │
│  ├──────────────────────────────────────────────────────────────┤ │
│  │ FRI  Easy 5mi + 4×100m strides                       ⋯       │ │
│  ├──────────────────────────────────────────────────────────────┤ │
│  │ SAT  Long run · 16mi @ 7:45–8:15        [why?]  [move]       │ │
│  ├──────────────────────────────────────────────────────────────┤ │
│  │ SUN  Recovery 6mi @ 8:00+                            ⋯       │ │
│  └──────────────────────────────────────────────────────────────┘ │
│                                                                    │
│  ≈ 54 mi total · 2 quality sessions · 1 rest day                  │
│                                                                    │
│  ┌─────────────────────┐   ┌───────────────────────────────────┐ │
│  │ Reshape this week ▸ │   │ Next quality: Tue's tempo         │ │
│  └─────────────────────┘   │ Building toward: HM tune-up Wk 12 │ │
│                            └───────────────────────────────────┘ │
└────────────────────────────────────────────────────────────────────┘
```

Principles:
- **Today is pinned to the top in a separate band**, pulled out of the list, so the athlete sees today's workout and rationale without scanning
- **Every quality day has `[why?]` and `[move]`**; easy/recovery/rest days have a `⋯` menu with the same options plus "mark complete"
- **Week stats line** makes the shape of the week visible at a glance
- **"Reshape this week"** is the power verb — one button that asks "what changed?" (travel / low energy / extra rest day / add a little) and re-materializes the week server-side against the coach's constraints
- **Forecast line** ("next quality, building toward") so the athlete sees direction, not just the next day

### B. This Week detail / rationale drawer

Opens when the athlete taps `[why?]` on a day. Small bottom sheet on mobile, right-side drawer on web.

```
┌─ Tuesday's tempo · why this, why now ─────────────────────────┐
│                                                                 │
│  5 × 1mi @ 5:52/mi · 90s jog recovery                          │
│                                                                 │
│  Why today?                                                     │
│  • Tuesdays are your workout day this block (you picked it)    │
│  • Sun was recovery and Mon was rest — you're fresh            │
│  • Thursday is medium, so the legs have time before the long   │
│                                                                 │
│  Why this workout?                                              │
│  5× 1mi is your threshold build — reps at half-marathon         │
│  effort to raise your lactate ceiling without destroying you    │
│  for Saturday's long run. Pace is from your 2:25 goal.          │
│                                                                 │
│  Why this pace?                                                 │
│  5:52/mi = your half-marathon goal pace (1:17-flat). If it      │
│  feels hard today, slow the last rep to 5:58. Don't go faster. │
│                                                                 │
│  [Move this workout]   [Skip and explain]   [Done]             │
└─────────────────────────────────────────────────────────────────┘
```

Copy comes from the coach. Generated by `generate-day-rationale` (new edge fn) at plan materialization time, stored per-day.

### C. "Reshape this week" dialog

The athlete's re-adaptation surface. Single modal, a few questions, one button.

```
┌─ Reshape Week 9 ────────────────────────────────────────────────┐
│                                                                   │
│  What changed?                                                    │
│  ☐ I'm traveling                                                 │
│  ☐ I'm feeling flat — pull the volume                            │
│  ☐ I need an extra rest day                                      │
│  ☐ I have an extra day to train                                  │
│  ☐ Something else →  [ textarea ]                                │
│                                                                   │
│  Any days blocked?                                                │
│  [ Mon ] [ Tue ] [ Wed ] [ Thu ] [ Fri ] [ Sat ] [ Sun ]         │
│  (tap to mark "can't run")                                        │
│                                                                   │
│  Volume target                                                    │
│  ○ Coach's plan (54mi)                                           │
│  ● Dial back to 45mi                                             │
│  ○ Your call: [ __ ] mi                                          │
│                                                                   │
│  Keep all quality sessions?                                       │
│  ● Yes — just shift days                                         │
│  ○ Drop tempo (keep long run)                                    │
│  ○ Drop long run (keep tempo)                                    │
│                                                                   │
│  [ Cancel ]                               [ Reshape my week → ]   │
└───────────────────────────────────────────────────────────────────┘
```

Hits `POST /api/reshape-week` → edge fn runs the constraints solver → returns a new week with a diff view (old → new) for athlete confirmation before writing.

### D. Adjustments history — coach-visible

A thin table on the coach's athlete detail view. Not the athlete's primary UX. Answers the coach's question: "what has this athlete been doing to the plan?"

```
Adjustments · Sarah M · past 4 weeks
  Wk 9  Mon Apr 27  Reshape: traveling, -9mi volume   green ✓
  Wk 8  Wed Apr 23  Shift tempo Tue→Thu              green ✓
  Wk 7  Sat Apr 12  Skipped long run ("sick")        yellow → reviewed
```

---

## 3. Core athlete verbs + three-tier customization model

Answers the open question from `adaptive-plan-builder-rework.md` §7 Q7:
"is the coach-prescribed plan sacrosanct?" — resolution: **no, but
graduated**.

| Verb | Tier | Coach notification |
|---|---|---|
| Shift quality day by ±2 within the same week | 🟢 green | logged, not flagged |
| Swap rest day to another blank day | 🟢 green | logged, not flagged |
| Add up to +3 mi or subtract up to -5 mi on any easy day | 🟢 green | logged |
| Reshape week (+/- volume ≤ 20%, keep all qualities) | 🟢 green | logged |
| Mark "flat week, pull volume" (> 20% volume cut) | 🟡 yellow | flagged on coach dashboard |
| Skip a quality session | 🟡 yellow | flagged, coach can ask why |
| Swap quality type (tempo ↔ intervals) | 🟡 yellow | flagged |
| Reshape to remove a quality | 🟡 yellow | flagged |
| Edit a future week (not this week) | 🔴 red | blocked — must go through coach chat |
| Change race date | 🔴 red | blocked |
| Edit prescribed pace | 🔴 red | blocked (pace comes from pace profile, not editable per-day) |

Rules:
- Green actions commit immediately, athlete sees new week right away
- Yellow actions commit immediately AND create a `plan_adjustments` row with `tier='yellow'`; the coach sees them in their athlete detail view
- Red actions return a dialog: "This needs your coach. Send a message?"

---

## 4. Data model additions

### `scheduled_workouts` — add two columns

```sql
alter table scheduled_workouts
  add column rationale_short text null,
  add column rationale_full jsonb null;
```

- `rationale_short` — 1-line subtitle for the day card ("Recovery pace so your legs come back for Tuesday's tempo")
- `rationale_full` — structured `{why_today, why_this_workout, why_this_pace}` for the drawer

Written at `subscribe-to-plan` time and re-written whenever a week is reshaped.

### `plan_adjustments` — add tier + reason + diff

Table exists already. Add:

```sql
alter table plan_adjustments
  add column tier text null check (tier in ('green', 'yellow', 'red')),
  add column reason_code text null,
  add column reason_text text null,
  add column diff jsonb null;
```

- `tier` drives whether the coach sees it on their dashboard
- `reason_code` is the bucket ("travel", "flat_week", "extra_rest_day", "other")
- `reason_text` is the free-text if they picked "something else"
- `diff` is the before/after of the week — for audit and coach context

### `training_plans` — athlete-scoped flags

```sql
alter table training_plans
  add column athlete_reshape_budget int not null default 999, -- how many reshapes per week
  add column last_reshape_at timestamp null;
```

Future: cap reshape frequency so it's not a mechanism to avoid the plan entirely. Start with 999 (effectively unlimited) so we learn from usage.

---

## 5. Edge function additions

### `reshape-week` (new)

```
POST /reshape-week
body: {
  plan_id, week_number,
  changes: { reason_code, reason_text?, blocked_dows[], volume_target, keep_qualities }
}
```

Logic:
1. Load the coach's template for this plan (for constraints: mileage range, quality count, preferred days)
2. Load athlete's pace profile
3. Run the materializer for this one week with the new constraints
4. Diff against the current week's `scheduled_workouts`
5. If diff is green-tier → write immediately, return new week + log adjustment
6. If diff is yellow-tier → return diff with "this will flag to your coach, confirm?"
7. If diff is red-tier → return 403 + reason

### `generate-day-rationale` (new)

Called by `subscribe-to-plan` after the week is materialized. Takes the week of days + athlete context + coach's plan notes, returns `rationale_short` + `rationale_full` for each day. Uses the coaching model.

Cacheable: for a given (plan, week, athlete_pace_profile_hash) the rationales are deterministic enough to memoize. Store in `scheduled_workouts.rationale_*` columns so the athlete UI reads them directly, no LLM call at view time.

### `shift-day` (new, small)

```
POST /shift-day
body: { scheduled_workout_id, new_date }
```

Validates tier, writes the change, logs the adjustment. Doesn't re-materialize the whole week — just swaps two `scheduled_date` values (the moved day and whatever was in the target slot). Re-generates rationale for both affected days only.

---

## 6. Phases

### Phase 1 — make the athlete's week legible (no customization yet)
- [ ] Rebuild `/plan/page.tsx` as the new This Week view
- [ ] Add today-pinned band
- [ ] Add `rationale_short` column to `scheduled_workouts` + backfill for existing plans
- [ ] Wire the `⋯` menu with placeholder actions (just "mark complete" active)
- [ ] Week stats line, forecast line

### Phase 2 — green-tier actions
- [ ] `shift-day` edge fn
- [ ] Tap-and-hold on a day → move sheet
- [ ] `plan_adjustments` tier/reason columns
- [ ] "Adjustments history" block on coach's athlete detail view (read-only)

### Phase 3 — reshape week (the power move)
- [ ] `reshape-week` edge fn
- [ ] Reshape dialog
- [ ] Diff preview modal
- [ ] Yellow-tier flagging in coach dashboard

### Phase 4 — rationale drawer
- [ ] `rationale_full` column + `generate-day-rationale` edge fn
- [ ] Rationale drawer UI
- [ ] Tap `[why?]` on quality days opens it

### Phase 5 — iOS parity
- [ ] Port This Week view to iOS
- [ ] Shift-day via long-press on iOS (already has drag infra in `WeekCalendarView.swift`)
- [ ] Reshape dialog on iOS

---

## 7. Open questions

1. **Reshape vs shift — one button or two?** Reshape is heavy (re-materializes). Shift is light (swap two days). Both needed, or can reshape subsume shift?
2. **Can the athlete edit pace?** Currently red-tier (blocked) because pace comes from profile. But what if the athlete says "this tempo pace is too fast today, let me run it at half pace"? Proposal: allow a per-session pace downgrade (no upgrade), auto-flagged yellow.
3. **Who writes the "why" copy?** LLM with coach's voice prompt, or does the coach write per-plan rationale templates? LLM is scalable but drifts; templates are tight but demand authoring time. Hybrid: LLM drafts, coach can overwrite at plan-template level.
4. **How far in the future can the athlete see?** This Week is obvious. What about next 4 weeks forecast? Or only this week until complete? Risk of too-much-transparency: athlete sees "I have 40mi easy next week" and burns out mentally.
5. **Cap on reshapes per week?** Proposal: no cap in v1, learn from usage. But we need to watch for runaway reshaping (athlete reshapes Mon + Wed + Fri all away from the plan).
6. **When a week gets reshaped, do completed days stay?** Yes — completed days are frozen. Reshape only touches future days in the week.

---

## 8. Immediate executable next step

Pick one:

**(a) Phase 1 — rebuild `/plan/page.tsx`.** Non-interactive first pass: just the new This Week shape with today-pinned band + week stats + rationale subtitle under each day. Uses only existing data. No new verbs yet. ~2 hrs.

**(b) Phase 2 — `shift-day` end-to-end.** Minimal reshape: athlete taps "move" on a quality day, picks a new day within the same week, it swaps. Requires Phase 1 UI to exist. ~3 hrs.

**(c) Data model migration first.** Add the columns (`rationale_short`, `rationale_full`, `tier`, `reason_code`, `reason_text`, `diff`) and backfill rationale_short with a placeholder so the UI can render it. Unblocks Phases 1-4 in parallel. ~30 min + migration deploy.

**(d) Design mockup first.** Build the HTML mockup of the This Week view + rationale drawer + reshape dialog so you can see it end-to-end before any code. ~1 hr. Output is a single `docs/athlete-plan-ux-mockup.html`.

My recommendation: **(d)** (see the shape before committing code), then **(c)** (data-model first so Phase 1 and Phase 4 can overlap), then **(a)**.

---

*Companion docs: `adaptive-plan-builder-rework.md` (coach's side),
`pace-system-rework.md` (pace ladder underpinnings),
`day-picking-prompts.md` (weekly template feature — related but separate).*

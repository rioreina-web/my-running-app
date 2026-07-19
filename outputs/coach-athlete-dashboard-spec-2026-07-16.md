# Coach athlete dashboard — design spec (2026-07-16)

**Status:** proposed · **Surface:** web coach portal (`web/src/app/(app)/coach-portal/athletes/[id]/`)
**Scope:** single-athlete deep dive — training logs, mood, volume, niggles, progression — plus a
coach-initiated bulk pace adjustment via re-anchoring.

Related docs: `adaptive-coach-plan-builder-spec-2026-07-03.md` (plan-builder side; Phase A shipped),
`coach-surfaces-audit.md`, `athlete-state-v2-coach-grade-2026-06-12.md`,
`marathon-prediction-honesty.md`, `body-mentions-design.md`.

---

## 1. Framing

This is an **evolution of the existing athlete detail page**, not a greenfield build.
`coach-portal/athletes/[id]/page.tsx` (~1,170 lines) already renders coachable moments, a watch
list, mood at-a-glance, weekly volume, daily volume-by-pace-zone, and a workout log. What it lacks:

1. **A progression answer.** The coach's first question — *is this athlete getting fitter?* — has
   no dedicated surface. Fitness prediction (range + confidence) sits in `athlete_state` unused.
2. **Real niggles data.** The page regex-scans `cleaned_notes` via `INJURY_PATTERNS`. The
   `body_mentions` table (closed vocabulary, verbatim quotes, severity hints) has existed since
   2026-06-12 and is strictly better. The regex path should be deleted.
3. **A pace tool.** All the derivation machinery exists; there is no coach-facing way to shift an
   athlete's live plan paces in one action.

Product posture carries over unchanged: **AI advises, never acts** — but this dashboard is a
*coach* surface, so coach-initiated writes (re-anchoring paces) are the intended human action, not
an AI act. AI content on this page stays observational (coachable moments, watch-list signals).

## 2. Page layout

One scrolling page, five bands. Mental flow mirrors how a coach reads an athlete: *how are they? →
are they progressing? → what's the load? → what did they actually do? → what do I change?*

```
┌─ HEADER ────────────────────────────────────────────────┐
│ Athlete · plan name · week N of M · goal vs. anchor     │
│ [Adjust paces] button (opens re-anchor sheet, §4)       │
├─ SIGNAL BAND ───────────────────────────────────────────┤
│ Watch list (existing) + coachable moments (existing)    │
├─ PROGRESSION BAND (new) ────────────────────────────────┤
│ Fitness range card · trend arrow · race anchors ·       │
│ this-cycle vs last-cycle comparison                     │
├─ LOAD BAND ─────────────────────────────────────────────┤
│ Weekly volume bars (existing) · ACWR dial ·             │
│ daily volume-by-zone (existing AthleteWeekVolume)       │
├─ BODY & MIND BAND ──────────────────────────────────────┤
│ Niggles timeline (body_mentions, new) ·                 │
│ mood strip (existing, upgraded to 28-day sparkline)     │
├─ LOG BAND ──────────────────────────────────────────────┤
│ Training log feed: prescribed vs. actual, mood pill,    │
│ niggle chips inline, voice-note excerpts (existing,     │
│ enriched)                                               │
└─────────────────────────────────────────────────────────┘
```

### 2.1 Header

Existing header plus two additions: the **anchor line** and the **Adjust paces** entry point.
The anchor line makes the goal-vs-reality distinction visible at all times:

> GOAL 3:16:00 · ANCHORED ON 3:28:41 marathon, Mar 2026 (`athlete_state.confirmed_races`)

If a confirmed race newer than the current anchor exists, show a muted one-line nudge:
*"New race on file: 3:26:12 half, Jun 1. Paces still anchored on March."* — tap opens the
re-anchor sheet pre-filled. This is a nudge, never an auto-apply.

### 2.2 Progression band (new)

The centerpiece. Answers "is the training working?" from `athlete_state`:

- **Fitness range card.** Predicted goal-race time as **range + confidence tier only** — hard rule
  #7. Render from `fitness_prediction` jsonb: `3:08 – 3:14 · HIGH CONFIDENCE`, with the basis line
  ("4 MP workouts and a recent half"). Never a seconds-precision point.
- **Trend.** `fitness_trend` + `fitness_vs_6mo_ago_label` as a plain-language line with delta,
  e.g. *"Trending up — easy pace 7:52 vs. 8:05 six weeks ago."* Every claim cites a number
  (`data_depth` register discipline applies to coach surfaces too).
- **Fitness chart.** 26-week line with confirmed races plotted as vertical markers (mirrors the
  iOS Trends design — reuse the framing, not the code). Blue ink only; coral reserved for alerts.
- **Cycle comparison.** If a prior plan/cycle exists: weekly-mileage and workout-pace overlay,
  this cycle vs. last. Data from `training_logs` bucketed by plan date ranges. Ship as Phase 3
  if the bucketing proves fiddly.

### 2.3 Load band

Keep `AthleteWeekVolume` and the 12-week bars. Add an **ACWR tile** with the banded read from
`weeklyAnalytics.ts` (<0.6 detraining · 0.8–1.3 sweet spot · >1.5 spike). Band colors: neutral
grays for in-range, coral **only** for the spike band (three-palette rule — never green for
"safe"). Show `monotony_7d` / `strain_7d` as small secondary stats.

### 2.4 Body & mind band

**Niggles panel (new, replaces regex scan):** query `body_mentions` for the athlete, 90 days.

- Timeline grouped by `body_area`: each row = body part, mention count, recency, and the most
  recent `verbatim_quote` in the athlete's own words.
- Recurrence flag from `athlete_state_niggle_recurrence`; resolved items (via
  `niggle_resolutions`) shown struck-through or filtered.
- **Surface, never interpret** (hard rule #2 / body-mentions spec): no diagnoses, no severity
  scoring by us, no "consider resting." The panel reports what was said, where, and when. The
  coach interprets.
- Each mention links to its `training_log_id` entry in the log band.
- Coral is the accent here — one coral element per cluster max: the recurrence flag gets it;
  everything else stays ink.

**Mood strip:** upgrade the existing at-a-glance to a 28-day strip of `training_logs.mood` labels
(warm palette, mood-only hues), with `mood_trend` from `athlete_state` as the caption. Mood is a
TEXT label — render the closed vocabulary (`energized … injured`) as `MoodBadge`, no numeric
coercion.

### 2.5 Log band

Existing 14-day workout log, enriched: inline niggle chips (from `body_mentions` joined on
`training_log_id`), mood pill, and prescribed-vs-actual pace delta already computed from
`workout_reconciliations`. Voice-note excerpt: first ~140 chars of `cleaned_notes`, expandable.
Empty cells use `<EmptyState />` (eyebrow + nudge) — never em-dashes (hard rule #8).

## 3. Data & access

No new tables. All reads exist today; the gaps are access paths, not schema.

| Section | Source | Access note |
|---|---|---|
| Header / anchor | `training_plans`, `plan_templates.phase_config.paceAnchor`, `athlete_state.confirmed_races`, `goal_time_seconds` | athlete_state read needs service-role path (see below) |
| Progression | `athlete_state.fitness_prediction`, `fitness_trend`, `predicted_*_seconds`, `training_logs` | same |
| Load | `training_logs`, `weeklyAnalytics.computeAllMetrics` (server-side), `athlete_state.acwr/monotony_7d/strain_7d` | compute in the RSC, as the page does today |
| Niggles | `body_mentions`, `niggle_resolutions`, `athlete_state_niggle_recurrence` | **verify coach RLS** — see below |
| Mood | `training_logs.mood`, `athlete_state.last_mood/mood_trend` | existing pattern |
| Log | `training_logs`, `scheduled_workouts`, `workout_reconciliations` | existing pattern |

**Coach authorization:** gate on the current model — coach owns a `plan_templates` row that the
athlete is `active`-subscribed to via `athlete_plan_subscriptions` (the existing page's gate). Do
not add reads through the legacy `coach_athlete_relationships` table. Any new RLS policy that
scopes by coach must use `current_coach_id()` (hard rule #6).

**Two access items to verify before build:**

1. `athlete_state` RLS currently allows only the athlete + service_role. The existing page
   presumably reads it server-side; confirm whether that's service-role or a coach policy, and if
   coach-scoped reads are added, they go through the subscription join + `current_coach_id()`.
2. `body_mentions` — **verified 2026-07-16: no coach read policy exists** (only service-role full
   access + "Users read own body mentions", `20260612130000_body_mentions.sql`). Either read
   server-side via service role in the RSC (matching how `athlete_state` is read today) or ship a
   coach read policy scoped via the subscription join + `current_coach_id()`. Same choice applies
   to `niggle_resolutions`.

## 4. Bulk pace adjustment — re-anchor flow

**Decision: re-anchor, not manual shift.** The coach updates the anchor (race pace + distance);
all ten zones re-derive via `derivePaceTableFromGoal`; future scheduled workouts re-materialize.
Per-zone overrides remain available (`paceAnchor.overrides`) for edge cases, but the flat
"+10 sec/mi everywhere" path is explicitly out — it fights the derivation architecture and drifts
zones out of physiological relationship.

### 4.1 What already exists

- `derivePaceTableFromGoal(goalRaceSecPerMile, raceDistance)` — canonical math, mirrored across
  web / edge / iOS (`workout-helpers.ts`, `_shared/paces.ts`, `PaceCalculator.swift`).
- Anchor store: `plan_templates.phase_config.paceAnchor = { goalRaceSeconds, goalRaceDistance,
  overrides }` — precedence 1 in resolution (over `athlete_pace_profiles`).
- `PaceReferenceEditor` — the zone-table editing UI, already used in the plan builder.
- `recompute-plan-paces` edge function — walks **future** `scheduled_workouts.workout_data.steps[]`
  and rewrites the literal `target_pace` from each step's `paceZone`. Past/completed rows never
  touched.

### 4.2 What's net-new

`recompute-plan-paces` is documented athlete-initiated only. The coach path needs:

1. **Coach authorization in the edge function** (or a thin coach variant): verify the caller's
   `current_coach_id()` owns the plan template behind the athlete's active subscription, then run
   the same materialization. Prefer extending the existing function with an auth branch over a
   fourth near-duplicate parser-style function (edge-function consolidation pressure).
2. **Anchor write:** update `plan_templates.phase_config.paceAnchor` for the athlete's live plan.
   Open question 1 (§6) covers template-vs-instance scoping.
3. **Audit row:** insert into `plan_adjustments`. Note the April lesson — the old CHECK
   constraint silently dropped rows whose `trigger_type` wasn't enumerated (fixed
   `20260703120000`). The current vocabulary already includes `'coach_rewrite'`; the re-anchor
   should reuse `trigger_type = 'coach_rewrite'` with a new `action_type` (e.g.
   `'reanchor_paces'`) if the action_type CHECK permits it, or ship a constraint migration adding
   both values. Either way: verify the insert actually lands in dev before shipping.
4. **UI — the re-anchor sheet** (from the header button or the new-race nudge):

```
ADJUST PACES — [athlete]
──────────────────────────────────────
Anchor    [ 3:28:41 ] [ marathon ▾ ]
          suggestion chip: "3:26:12 half · Jun 1 (confirmed race)"

Zone      Current      New          Δ
Easy      8:42–9:38    8:36–9:31    −6s     (ranges ±5%: aerobic zones)
Steady    8:05         8:00         −5s
MP        7:57         7:52         −5s     (exact: race-pace zones)
…         (all 10 zones, blue ramp zone dots)

Affects 23 future workouts (Jul 17 – Sep 20). Past workouts unchanged.
[ Cancel ]                    [ Apply new paces ]
```

   Preview-first is mandatory: the coach sees the full old→new zone diff and the count of
   affected workouts before anything writes. Per-zone override edits happen inline in the "New"
   column (reuses `PaceReferenceEditor` behavior). Aerobic zones display as ranges, race-pace
   zones as exact targets, per the canonical taxonomy.

5. **Failure handling:** materialization is a multi-row update; if the edge function fails partway,
   the sheet must surface it ("re-anchored, but N workouts failed to update — retry") rather than
   pretending success. Idempotent re-run is the recovery path (the function derives from zone
   labels, so re-running is safe).

### 4.3 Guardrails

- **Coach action only.** No AI-initiated re-anchor, no auto-apply from a new race result. The
  new-race nudge is a suggestion chip; the coach clicks Apply.
- **Future rows only** — `recompute-plan-paces` semantics preserved. History is a record.
- **Zone labels stay the source of truth** on steps; only the materialized `target_pace` literals
  change. `exactPaceSecPerMile`-pinned steps are respected (skipped), and the preview marks them.
- **iOS parity:** athletes see updated paces on next plan fetch. Confirm the iOS plan cache
  invalidates on `scheduled_workouts` update (open question 3).

## 5. Phasing

**Phase 1 — dashboard restructure (pure read, no schema).** Reorganize `athletes/[id]/page.tsx`
into the five bands; add the progression band from existing `athlete_state` fields; replace
`INJURY_PATTERNS` regex with `body_mentions` reads (plus RLS verification/migration if needed);
mood strip upgrade; empty states throughout. Deliverable: coach sees logs, mood, volume, niggles,
progression on one page.

**Phase 2 — re-anchor tool.** Anchor line + nudge in header; re-anchor sheet with preview;
coach-authorized `recompute-plan-paces` path; `plan_adjustments` audit write. Deliverable: coach
changes all plan paces in one reviewed action.

**Phase 3 — comparison & polish.** Cycle-vs-cycle overlay; niggle → log cross-linking
interactions; roster-card summary chips fed from the same derivations.

Phase 1 and 2 are independent enough to parallelize, but 1 ships first — the pace tool needs the
anchor line for its entry point to make sense.

## 6. Open questions

1. **Anchor scoping: template vs. athlete.** `phase_config.paceAnchor` lives on `plan_templates`.
   If one template serves multiple athletes, a coach re-anchor for one athlete must not shift
   others. Likely fix: copy-on-subscribe (anchor snapshot onto the athlete's `training_plans` /
   subscription row) or a per-athlete override field. **Decide before Phase 2** — this is the one
   item that could force a migration.
2. **Where does the coach anchor meet the athlete's own anchor?** Athlete-side precedence is
   confirmed race > goal. If the coach sets an anchor that disagrees with a newer confirmed race,
   the dashboard should show the tension (the nudge does this), but who wins for *athlete-facing*
   pace display outside the plan? Current answer: coach anchor wins inside plan workouts
   (precedence 1), athlete anchor wins elsewhere. Confirm this is the intended read.
3. **iOS cache invalidation** after coach re-materialization — verify, don't assume.
4. **Coachable moments for coaches:** should a coach re-anchor generate an athlete-visible
   observation ("your coach updated your paces")? Leaning yes-but-Phase-3; it touches the
   notification surface, which doesn't exist yet.

## 7. Convention checklist (why this spec is shaped this way)

Hard rule #1 (RLS same-migration) → §3 item 2. Rule #2 (no diagnosis) → §2.4 niggles panel.
Rule #6 (`current_coach_id()`) → §3, §4.2. Rule #7 (range + confidence) → §2.2. Rule #8 (empty
states) → §2.5. Rule #9 (`db push` only) → any Phase 2 migration ships through CI, not dashboard
SQL. Three-palette rule → §2.2, §2.3, §2.4. No golden-family prompts are touched — this is a
read-and-tools surface; no new LLM calls, so no cassette obligations.

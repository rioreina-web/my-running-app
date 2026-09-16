# Garmin full loop — integration plan (2026-07-03)

Decision from the workout-builder sprint: Garmin integration is the **full
loop** — push the built workout to the athlete's watch as a structured
session, pull the completed run back, and reconcile planned vs. actual in
the app. This doc scopes that work. The workout builder prototype
(`prototypes/workout-builder.html`) already renders the push side as the
"On the watch · Garmin preview" panel.

## Why full loop

The builder's value is the prescription; the journey's value is what
actually happened against it. One direction alone leaves half the story:
push-only means compliance still gets inferred from HealthKit mileage;
pull-only means the athlete runs the workout from memory. The loop closes
when the same structured definition that guided the run comes back
annotated with reality.

## What Garmin can and cannot represent

The workout-builder step model maps onto Garmin structured workouts almost
one-to-one, with three constraints that shape the design:

1. **One rep count per repeat block.** Ranges (`10-12 x k`) collapse to a
   single number at sync. The range is the prescription; the number is the
   day's decision — so the athlete confirms the count in the sync sheet.
   Unconfirmed defaults to the floor (a watch full of skipped reps reads as
   failure; finishing strong reads true).
2. **Absolute pace windows, not zones.** Paces resolve per athlete before
   export, manual overrides and offsets (`MP-10`) already applied. Aerobic
   zones ship their range; race-pace zones get a tight band (±4 s/mi).
3. **Simple repeat structures.** Compound sets `(600 @ 5K / 400 @ 3K)`
   map to a repeat over two run steps plus a recovery step; rest between
   sets becomes a rest step after the repeat block. Nothing in the current
   model exceeds Garmin's format.

## Phases

### Phase G1 — access + plumbing

Apply to the Garmin Connect Developer Program for the **Training API**
(workout push + schedule) and **Health/Activity API** (completed-activity
webhooks). Free, but approval takes time — apply first, build while
waiting. New tables: `garmin_connections` (per-athlete OAuth tokens,
RLS per rls-checklist) and `workout_exports` (which workout version went
to which athlete's watch, with the resolved numbers — the loop's join key).

### Phase G2 — push

Edge function `garmin-push-workout`: takes a workout id + athlete id,
resolves paces from the athlete's effective zone table (race anchor →
derived table → manual overrides), applies tier scaling, collapses ranges
via the confirm-at-sync sheet, emits the Training API workout JSON, and
records the exact resolved prescription in `workout_exports`. The iOS sync
sheet is the one human touchpoint: variation choice if the workout has
A/B, rep-count confirm if ranged.

### Phase G3 — pull + reconcile

Webhook receiver for completed activities → match to `workout_exports` by
athlete + date (fall back to fuzzy match on distance/duration). Lap/split
data maps back to prescription steps: reps completed vs. programmed,
splits vs. pace windows, recovery durations. Results land on the existing
reconciliation path (`post-run-reconciliation`, `week_compliance_pct` in
`athlete_state`) rather than a new parallel system.

**Dedupe is the sharp edge:** athletes with an Apple Watch + Garmin, or
Garmin→Apple Health forwarding, will produce the same run twice. The
HealthKit ingest and Garmin webhook must agree on a canonical activity
(match on start-time window + distance; prefer the source with lap
structure, which is Garmin when the workout was pushed there).

### Phase G4 — surface

Planned-vs-actual on the workout detail (prescribed steps annotated with
what happened) and in the Train tab's history. Voice stays in product
register: observation, not judgment — "Reps 9 and 10 drifted 12 s outside
the window" — never "you failed the workout." Detection, not diagnosis,
same as Niggles.

## Open questions

- Range default on unconfirmed sync: floor (current call) vs. tier-based.
- Whether coach-pushed workouts require athlete accept before landing on
  the watch (dyad case; Maya self-pushes).
- Garmin Connect calendar scheduling vs. push-on-sync only.
- Minimum viable lap-matching: Garmin laps follow programmed steps when
  the workout runs as structured; manual-lap and freestyle runs need the
  fuzzy path. Ship structured-only matching first.

— restraint as foundation, intensity as accent

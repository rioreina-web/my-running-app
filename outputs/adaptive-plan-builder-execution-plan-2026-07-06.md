# Adaptive Plan Builder — Execution Plan & Risk Read

**Date:** 2026-07-06
**Author:** planning pass over the current `my-running-app` codebase against
`adaptive-plan-builder-opus-buildplan-2026-07-05.md`.
**Purpose:** Before writing any code, this is the ground-truth read of where
the code actually stands versus the 5-phase build plan — what's already done,
what's genuinely left, the corrections to the original plan, the risks, and a
recommended order of attack. Written to be readable without a coding
background.

---

## TL;DR — the three things that changed the plan

1. **Phase 3's database work is already done.** The original plan says the
   `scheduled_workouts` uniqueness constraint may need widening via a
   migration to allow two workouts on one day. It was already dropped back in
   February (`20260227_plan_builder_setup.sql`), and the `session` column
   already exists (`20260301_add_session_column.sql`). Phase 3 needs **no new
   migration** — just code that actually *uses* the doubles data.

2. **Phase 2's RLS instruction in the original plan is slightly wrong.** The
   plan says to scope the new column's security via `current_coach_id()`. The
   `plan_templates` table doesn't actually use that helper — it uses an inline
   `coach_profile_id IN (...)` pattern, and table-level security already
   covers any new column. Following the plan literally would introduce an
   inconsistency. Corrected approach below.

3. **Phases 1 and 4 share a hidden prerequisite:** the web app has **no pace
   colors defined yet**. The 10-color blue "pace spectrum" only exists on the
   iOS side (`PaceSpectrum.swift`). Both the Phase 1 bar chart and the Phase 4
   zone dots need those 10 colors as web CSS variables. This is a small,
   safe, ~1-hour job that must happen first and unblocks both frontend phases.

Everything else in the original plan holds up. Recommended order is unchanged
(P1 → P4 → P2/P3 → P5), with the color-token prerequisite slotted in front.

---

## How to read the effort labels

- **Small** = a focused half-day-ish change, low risk.
- **Medium** = a day or two; some moving parts but well-understood.
- **Large** = a week-ish; should be broken into sub-steps and reviewed in
  pieces.

None of this touches your live database until you (the team) explicitly run
`supabase db push`. Every migration below is *authored as a file only* — a
hard project rule (#9). I will never apply one to production.

---

## Phase 0 (new) — Web pace-color tokens

**Why it exists:** the blue pace ramp (`#93B9D6` Easy → `#0E1D4E` Mile, 10
stops) is defined only in iOS Swift today. Phases 1 and 4 both paint with it
on the web. Define it once, on the web, first.

**What it is:** add the 10 hex stops as CSS variables (`--pace-easy` …
`--pace-fast`) in the web app's global stylesheet, and a matching TypeScript
lookup (`PACE_ZONE_COLORS: Record<PaceZone, string>`) so code can grab a
zone's color. The prototype HTML already assumes `var(--pace-*)` exists, so
this also makes the prototype port a near-copy-paste.

The exact 10 stops (slow → fast), from `PaceSpectrum.swift`:

| Zone | Hex |
|---|---|
| Easy | `#93B9D6` |
| Moderate | `#74A8CC` |
| Steady | `#578FC0` |
| MP | `#3F7CB5` |
| HMP | `#2F66A8` |
| LT | `#27549B` |
| 10K | `#20448B` |
| 5K | `#1A3679` |
| 3K | `#142964` |
| Mile | `#0E1D4E` |

**Migration?** No. Pure frontend.
**Effort:** Small.
**Risk:** Near zero. The one thing to double-check: the design system renamed
the pace token out of the "mood" namespace (`speed` → `paceFast`). Mirror
that naming so we stay consistent with `design-system/colors_and_type.css`.

---

## Phase 1 — Pace-colored mileage ramp

**Goal:** the "Mileage ramp" area of the Plan setup becomes a stacked
bar chart — each week is a bar, pale-sky base is the easy miles, deeper
blues stack the placed quality miles by zone, a coral dot flags any week
that jumps more than 10% over the prior week. Bars restack live as the
coach places or removes workouts.

**Where it stands now:** the ramp today is *not a chart at all* — it's a
row of number-input cells (min miles, max miles, phase dropdown per week)
in `plan-setup-section.tsx`. The placed workouts never even reach this
component; it only receives the min/max ranges.

**The real work (in order):**
1. **Plumb the data through.** Pass the placed workouts (which already live
   in state in `plan-builder-client.tsx`) into the ramp component. This
   boundary is the bulk of the effort — the ramp is currently deliberately
   decoupled from workout content.
2. **Add a `weekZoneMiles` helper** to `workout-helpers.ts`: for each placed
   step, convert to miles (the `estimatedStepMiles` helper already does this)
   and bucket the miles by pace zone. Add a `nearestZoneKey` helper for steps
   defined by an exact pace rather than a named zone. Both are direct ports
   from the prototype (functions captured below).
3. **Render the stacked bars** — port the prototype's `renderRamp` +
   `.ramp*` CSS. Easy fill = the week's mid mileage minus placed quality
   miles. Coral dot only on the >10% flag (down weeks exempt). Tooltip per
   segment reads like `"LT · 6.0 mi"`.
4. Keep the min/max/phase editing reachable — e.g. clicking a bar selects
   that week for editing.

**Design non-negotiables that bite here:** blue-only ramp; coral *only* on
the flag; mileage shown as ranges ("44–48 mi", never "46.0"). One existing
palette violation to note for later: `workout-structure.tsx` uses a green
(`#C0DD97`) for warmup/cooldown stripes — green is mood-only, so that's a
Phase 4 cleanup, not a Phase 1 one.

**Migration?** No.
**Effort:** Medium (~1.5–2 days). Chart port is quick; the data-plumbing and
new helpers + their tests are the real cost.
**Risk:** Moderate. Main tricky bit is wiring live workout data into the ramp
without re-rendering the whole builder on every keystroke (the file already
documents a save/flush timing issue to respect).

---

## Phase 4 — Library & builder design-parity pass

**Goal:** close the visual gap between the shipped portal and the prototypes:
10-zone workout labels, zone-dot tags derived from a workout's actual steps,
pin-to-top in the library, a mono "estimated" one-liner
(`"2 wu · 6 × 800 @ 5K · 2 cd"`), and a natural-language "Describe it" box
that turns typed text into workout steps.

**Where it stands now:** the library cards and forms use the *legacy* labels
(`Easy / Tempo / Intervals / Long Run …`) rather than the 10-zone taxonomy.
There's no zone-dot row, no estimated one-liner, no "Describe it" parser, and
no `pinned` column. The `EmptyState` component exists but the library's empty
state is hand-rolled and should be switched to it. Two more green/coral
palette violations live in `workout-template-form.tsx`.

**This is the biggest phase. Recommend splitting it into three reviewable
sub-steps:**

- **4a — Natural-language parser (the hard part).** Port the prototype's
  `parseNL` and its ~15 helper functions into a standalone, unit-tested
  TypeScript module. The catch: the prototype's step shape differs from the
  web app's `WorkoutStep` type (different duration units, pace fields, reps),
  so this needs a clean adapter layer and round-trip tests. Compound sets
  like `(600 @ 5k / 400 @ 3k)` have no web equivalent — decide whether to
  port or drop for v1 (recommend: drop for v1, note as follow-up).
- **4b — Card/label/dot/line design pass.** Swap legacy labels for
  10-zone-derived labels (`MP 7 mi`, `LT 6 mi`, `5K 5×1km`), add the
  zone-dot row (using Phase 0's colors), and add the mono estimated line
  (port `instSummary`). "tempo"/"threshold" survive only as stored legacy
  data — never as new picker options.
- **4c — Pin + empty-state + palette cleanup.** Pin toggle and
  sort-pinned-first (UI can ship reading a `pinned` boolean; the column
  itself is a small later migration). Switch the library empty state to
  `<EmptyState>`. Fix the green palette violations.

**Migration?** One tiny one eventually (`pinned BOOLEAN` on
`workout_templates`), authored-only, batched with the others. The UI can be
built before it lands.
**Effort:** Large (~1 week total across 4a/4b/4c). 4a alone is 2–3 days.
**Risk:** Moderate–high, concentrated in 4a (the parser step-shape mismatch).
Everything else is low-risk design work.

---

## Phase 2 — Coach AI guidance (rules the AI must respect)

**Goal:** coaches write hard rules, softer guidelines, and a silent context
note on a plan; the reschedule AI reads them and treats hard rules as
constraints it won't violate.

**Where it stands now:** greenfield — `coach_ai_guidance` exists nowhere yet.
Good news: `reschedule-plan` **already uses the prompt-library system**
(`reschedule-plan.v1`), so the plumbing to add guidance is clean.

**The work:**
1. **Migration** — add a `coach_ai_guidance JSONB` column to `plan_templates`
   (shape `{ rules: [{on, strength, text}], note }`), authored-only.
2. **CORRECTION to the original plan on security:** the original plan says to
   scope this via `current_coach_id()`. The `plan_templates` table does **not**
   use that helper — its security uses an inline `coach_profile_id IN (...)`
   pattern, and it's table-level, so a new column is already covered. The
   precedent (`20260703121000`) explicitly adds no new policy for new columns.
   **Recommendation:** don't add a redundant policy; if the team wants one to
   satisfy the "RLS in the same migration" rule literally, it must match the
   existing `coach_profile_id` pattern, not `current_coach_id()`. Flag this to
   whoever authored the build plan.
3. **New prompt version** `reschedule-plan.v2` that takes a `{{coachGuidance}}`
   block, with the caller pre-computing that string (hard rules as
   MUST-FOLLOW, guides as preferences, note as silent context). Keep the
   project's existing safety guardrails (no medical claims, no "stop training")
   *above* coach guidance in precedence.
4. **Mandatory eval cassette.** CI will **block the pull request** if you add
   `reschedule-plan.v2` without a matching cassette under
   `_evals/cassettes/reschedule-plan.v2/`. Write at least one that proves a
   hard rule is honored (e.g. "never schedule quality on Mondays") and one
   proving the silent note stays silent.
5. **Builder UI section** — the rules/guidelines/note editor, matching the
   prototype's voice ("assistant reasons inside these lines; it proposes, you
   decide").

**One decision to make:** `reschedule-plan` currently receives the plan from
the client and doesn't read `plan_templates` itself. Either the client sends
the guidance, or the function looks it up by ID (adds a DB read). Recommend
the function looking it up — keeps guidance authoritative and un-tamperable.

**Migration?** Yes, 1 (authored-only).
**Effort:** Medium.
**Risk:** Moderate. The free-text coach note is a prompt-injection surface —
keep it clearly delimited and below the safety guardrails. And the strict
prompt loader means "no guidance" must resolve to a real (empty) string, not
throw.

---

## Phase 3 — AM/PM doubles, end to end

**Goal:** the `session: "am"|"pm"` field already in the web builder flows all
the way through to what the athlete sees — two workouts materialize on a
doubled day and render stacked with AM/PM labels.

**Where it stands now — much further along than the plan assumes:**
- Database: **done.** Uniqueness constraint already dropped; `session` column
  already exists with an index.
- Web builder: **done.** Full AM/PM slot modeling and it persists.
- iOS: **partial.** The data model decodes `session`, and calendar cards
  already stack a secondary session (currently just showing a bare "+").

**What's genuinely left:**
1. **The materializer never emits a second session.** `subscribe-to-plan`
   hardcodes `session: 1` on every insert and the "doubles on easy days"
   branch is an unimplemented stub. This is the core backend work: emit a
   second `scheduled_workouts` row with `session: 2` when a template day has a
   PM workout. Needs tests.
2. **`shift-day` has a latent crash.** Its destination lookup uses
   `maybeSingle()`, which throws the moment a day has two sessions. Moving a
   doubled day (or into a doubled day) is broken today. Needs session-aware
   handling plus a documented decision: does moving a day carry one session or
   both? (Recommend: both, or prompt.)
3. **iOS day detail** (`DayDetailPlate22` / `DayDetailSheet`) renders exactly
   one workout. Needs to stack two sessions with AM/PM eyebrows. The calendar
   cards need a proper "PM" eyebrow instead of the bare "+".

**Migration?** None required. (Optional hardening: a
`UNIQUE (plan_id, date, session)` index to prevent duplicate-session bugs —
only if we verify no existing rows would violate it.)
**Effort:** Medium–High — three independent workstreams (materializer, iOS
day detail, shift-day safety).
**Risk:** The `shift-day` `maybeSingle()` crash is the one to fix *before* any
doubled plan ships to a real athlete.

---

## Phase 5 — Read-only athlete preview rail

**Goal:** inside the builder, pick one of the coach's real athletes and see
the selected week resolved in *their* paces (from their race anchor), on
*their* preferred days, with doubles pinned. This is the product's core
promise made visible: write once, every athlete reads it in their own paces.
Read-only, no writes.

**Where it stands now:** doesn't exist yet — but every ingredient does and is
proven. Pace derivation (`derivePaceTableFromGoal`), the athlete pace
precedence logic (in `subscribe-to-plan`'s `resolveAthletePaces`), and the
preferred-days data (`athlete_plan_subscriptions`) are all in place. iOS even
has a `PlanPreviewMaterializer.swift` as a reference for the resolution logic.

**The work:** an athlete picker + a read-only rail that re-resolves the
selected week in the chosen athlete's paces, remaps to their days, and pins
doubles to their day. Predictions/paces shown as ranges where the prototype
does.

**Migration?** Probably none. The one gate: does the athlete-subscription
table's security let a *coach* read a linked athlete's prefs? If not, either a
coach-read policy or (cleaner, no migration) route the fetch through the
existing service-role edge function pattern.
**Effort:** Medium.
**Risk:** The preview must resolve paces with the *same precedence* as the
real subscription flow (coach anchor wins over athlete profile), or the coach
sees paces the athlete won't actually get. Best handled by sharing the
resolution logic rather than duplicating it. Also handle the no-goal /
no-anchor athlete gracefully with a proper empty state (no em-dashes — hard
rule #8).

---

## Recommended sequence & batching

1. **Phase 0** (color tokens) — do first; unblocks P1 and P4. Small, safe.
2. **Phase 1** (ramp) — pure frontend, no migration. High visible payoff.
3. **Phase 4** (library/builder), split 4a → 4b → 4c — pure frontend; the
   `pinned` migration is authored but not needed to ship the UI.
4. **Phase 2** (AI guidance) and **Phase 3** (doubles) — these author the
   migrations. **Batch all authored migrations** (P2's `coach_ai_guidance`,
   P4's `pinned`, plus the already-pending `20260703*` and `20260615*`
   migrations) into **one `supabase db push` from a committed SHA** — per hard
   rule #9. Phase 2 also carries the eval-cassette CI gate.
5. **Phase 5** (preview rail) — last; it reads what the others produce.

**After every coding session:** typecheck (`tsc --noEmit`), run the dev
server, compare the surface side-by-side with the prototype in the browser,
and scan the diff for palette violations (grep for greens, and for coral used
as a fill instead of an accent).

---

## Open questions to settle before or during the build

1. **Phase 2 security policy** — confirm we follow the actual `coach_profile_id`
   pattern, not the build plan's `current_coach_id()`. (Recommendation: yes.)
2. **Phase 2 guidance fetch** — client-sent vs. function-looked-up. (Rec:
   function looks it up.)
3. **Phase 3 shift-day** — moving a doubled day carries one session or both?
   (Rec: both, or prompt the coach.)
4. **Phase 4a** — port compound-set parsing now or defer? (Rec: defer to v2.)
5. **Phase 5 RLS** — add a coach-read policy on subscriptions, or fetch via
   service-role edge function? (Rec: service-role, avoids a migration.)

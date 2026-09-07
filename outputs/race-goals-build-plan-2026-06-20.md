# Race goals — build plan

**Date:** 2026-06-20
**Revised:** 2026-06-20 (v2 — reframed around natural-language goals +
goal salience after the product vision conversation)
**Status:** Proposal for review (Phase 1 migration written, not pushed)
**Author context:** Written for a builder who is new to code. Each phase
explains *what* and *why* before *how*, and ends with a plain "done when"
check.

---

## 1. What we're building, in one sentence

A way for a runner to state a race goal **in their own words** — typed or
spoken — that the app *understands*, lets them *confirm and correct*, uses
to drive pace zones and predictions, and then references **like a real
coach would: present but quiet, loud only when it matters.**

The North Star example (from the athlete's mouth):

> "I want to stay injury-free and run a Boston qualifier at the CIM
> marathon in December."

That single sentence is four things at once — a *constraint*
(injury-free), a *performance target* (BQ, which resolves to a time only
once you know the athlete's age/sex), a *named race* (CIM — a real event
with a real date and course), and a *timeframe* (December). A dropdown
can't hold that. A text box plus a parser plus a confirmation step can.

---

## 2. The two ideas that shape everything

### Idea A — A goal is an *interpreted statement*, not a form entry

The runner writes free text. An LLM parses it into structured facets. The
app shows its interpretation back ("Here's what I understood…") and lets
the runner fix it before it counts. We store three layers:

1. **Raw statement** — their verbatim words (quote, never coerce — same
   ethos as the niggles "quote verbatim" rule).
2. **Interpretation** — the structured facets the parser pulled out.
3. **Derived anchor** — the single (distance, time) pair the pace math
   needs, computed from the interpretation.

Why three layers: the raw words are the truth of intent; the
interpretation is editable and can be re-derived if our parser improves;
the anchor is the clean numeric handle everything downstream already knows
how to consume.

### Idea B — Goal *salience* is governed separately from the goal

The known failure mode: the moment a goal is in the AI's context, it
circles back to it on *every* upload — mentions CIM after a routine
Tuesday jog. A real coach doesn't. They keep the goal present but quiet,
and bring it up at the sessions that move the needle, in the weekly
"still on track" beat, and more as race week nears.

So **the goal is always in context, but how loud it is right now is
computed**, not left to the model's default (which over-mentions).
Roughly:

> `goal_salience = f(surface type, weeks-to-race, change in trajectory)`

| Situation | Salience | Coach behavior |
|---|---|---|
| Easy / recovery run upload | background | Don't reference the race at all. |
| Key workout or long run | foreground OK | May connect the session to the goal. |
| Weekly report / milestone / real fitness shift | explicit | "Still on track for sub-3:05." |
| Race week approaching | rising | Naturally more present (taper, logistics). |

The Coach prompt receives the goal **plus a directive** like
`goal_salience: background — do not reference the race unless the athlete
raises it`. That turns "don't over-cook it" into something controllable
and, crucially, **testable** — see Phase 3's eval cassettes.

This is an *extension* of an existing CLAUDE.md principle, not a new one:
"anchors and goal carried silently; never explained." We're making
"silently" precise.

---

## 3. Why a plan at all (the current mess)

Goal data exists but is scattered across four places with no single
source of truth — which is why your athlete state showed `goal_race`,
`goal_time_seconds`, and `active_goals` all empty.

| Where goals live today | Stores | Status |
|---|---|---|
| `user_goals` table | `goal_title` + `target_date` only | Correct athlete-scoped security, schema too thin. Onboarding writes here; **nothing reads it.** |
| `athlete_pace_profiles` | `goal_race_distance` + `goal_time_seconds` + derived paces | Written by `update-plan-goal`. Closest thing to a goal store, but models a goal as a *pace cache*; no date/status; uses `uuid` user_id while the app uses `text`. |
| `athlete_state.goal_race` / `goal_time_seconds` | for the rebuild to read | **Never populated.** |
| `athlete_state.active_goals` (jsonb) | multiple goals | **Never populated** (the empty `[]` you saw). |

Net effect: a goal entered at signup goes into a void and never reaches
pace derivation.

---

## 4. Design principles (carried from CLAUDE.md, plus salience)

1. **Goal is direction; race is reality.** Goal = aspiration; *confirmed
   race* = fitness that happened. Separate stores. Confirmed race wins for
   pace anchoring; goal sets direction.
2. **AI advises, never acts.** A parsed goal is a *proposal* until the
   athlete confirms it. We store an `athlete_confirmed` flag; unconfirmed
   goals don't silently drive training.
3. **Quote verbatim.** Keep the athlete's own words (`raw_statement`).
4. **`activePlan == nil` is first-class.** Goals work with no plan.
5. **Predictions show range + confidence**, never a single point.
6. **The goal is a context layer, not a math override (decided
   2026-06-20).** It informs awareness everywhere; it does NOT rewrite the
   fitness math. Predictions/Trends stay sourced from `fitness_snapshots`
   — the goal never touches them. Pace zones stay fitness-derived by
   default; goal-paces are an opt-in toggle. (Detail in Phase 3.)
7. **Goal salience is computed, not constant** (Idea B).
8. **Hold goals conceptually; derive the number, speak the framing.**
   "Sub-3" is the meaningful unit — internally 10,800s, but the athlete
   cares about the *barrier*, not 2:59:59. The coach says "sub-3" / "your
   BQ" / "around 3:10," never "2:59:59 or faster." The seconds are an
   internal handle for pace math and progress, not voice. (Same spirit as
   `outputs/marathon-prediction-honesty.md`: precision the athlete didn't
   mean is noise.) Distance is open too — don't reject a 50k or a relay.
9. **Constraints are lenses, not directives.** "Stay injury-free" biases
   the coach toward load/niggle awareness — it never becomes "rest" or a
   diagnosis (hard rule #2).
10. **Data hard rules:** RLS in the same migration; append-only once
   deployed; `athlete_state` writes via service-role edge function; no LLM
   prompt change ships without eval coverage (hard rule #3); migrations
   reach prod only via `supabase db push` from a committed SHA (#9).
11. **Stay in the running lane (decided 2026-06-20).** An open text box
   will let the model coach anything, so it must be fenced to
   running/endurance. Three tiers: **in-scope** (race / time-pace / volume
   / consistency goals + running-serving constraints like "stay
   injury-free") → coach it; **adjacent** (sleep, stress, weather,
   cross-training) → read as context, never prescribe; **out-of-scope**
   (weight/body-composition, diet/supplements, strength-lifting numbers,
   injury *treatment*, non-running life goals) → push back, don't persist
   as a goal. Two of these are safety, not focus: **weight/nutrition** is
   disordered-eating territory — refuse, don't reframe into a calorie
   target — and **injury treatment / medical** is hard rule #2 (no
   diagnosis; redirect to a professional). Pushback is warm and brief, in
   brand voice.

---

## 5. The decision that unblocks everything: one source of truth

**Make `user_goals` the single structured source of truth**, and treat
`athlete_pace_profiles` as a *derived cache* (paces computed *from* the
goal). `user_goals` already has correct athlete-scoped RLS and a `text`
user_id consistent with the rest of the app. The cost is a few added
columns — a small, additive migration (Phase 1, already written).

---

## 6. Data model (the richer goal record)

All on the `user_goals` row (Phase 1 migration adds the new columns):

- `raw_statement TEXT` — verbatim athlete words.
- `interpretation JSONB` — evolving structured facets. Each performance
  target carries its *framing* (`expression` + `type`) so the coach can
  speak it the way the athlete meant it:
  ```json
  {
    "performance_targets": [
      {"race_distance": "marathon", "target_time_seconds": 11100,
       "expression": "BQ", "type": "qualifier", "basis": "boston_standard"}
    ],
    "constraints": ["injury_free"],
    "named_race": {"name": "CIM", "event_date": "2026-12-06",
                    "location": "Sacramento, CA", "race_intel_id": null},
    "priority": "primary",
    "confidence": {"named_race": "high", "target_time": "medium"}
  }
  ```
  A "sub-3" goal would be `{"race_distance": "marathon",
  "target_time_seconds": 10800, "expression": "sub-3", "type":
  "threshold"}` — stored as 10,800s for the math, but the coach says
  "sub-3," never "2:59:59 or faster." `type` ∈ `threshold` (sub-X) |
  `target` (around-X) | `pr` | `qualifier` (BQ-style) | `finish`
  (qualitative, no time).
- `target_race_distance TEXT` (**open** free text) + `target_time_seconds
  INTEGER` — the derived quantitative anchor pace math consumes. Distance
  is intentionally NOT a closed enum (athletes target 50k, relays, odd
  local races); it's normalized to a pace key at the app layer
  (`raceKeyForInput`), and only recognized distances drive pace zones
  (others store fine, like `ultra`/`general` already do). The time is the
  internal handle, not what the coach speaks (principle 8).
- `athlete_confirmed BOOLEAN` + `confirmed_at TIMESTAMPTZ` — the
  verification gate.
- Existing: `goal_title`, `target_date`, `status`, `user_id`, timestamps.

Why JSONB for interpretation: the facet shape *will* change as the parser
gets smarter. Rigid columns for the numeric anchor (other systems join on
it); flexible JSONB for the interpretation (evolves without migrations).

---

## 7. Phased build plan (smallest valuable slice first)

### Phase 1 — Make `user_goals` hold the richer record  *(migration written)*

**What:** Add `raw_statement`, `interpretation`, `target_race_distance`,
`target_time_seconds`, `athlete_confirmed`, `confirmed_at` — all
additive, NULL-safe, with CHECK constraints matching the existing
vocabulary, and an index for "active goal per user."

**File:** `supabase/migrations/20260620210000_extend_user_goals_for_race_goals.sql`

**Done when:** committed and applied via `supabase db push`. (Validated
against the real Postgres parser; confirmed additive against prod. **Not
yet pushed** — hard rule #9.)

---

### Phase 2 — Natural-language entry, parse, and confirm/edit

**What:** A text box (typed or voice transcript in) → parse into the
interpretation → derive the anchor → **show it back for confirmation/edit**
→ save to `user_goals` and refresh the pace cache.

**Why:** This is the heart of the feature, and the confirm step is what
makes a fuzzy input safe.

**How:**
- New LLM prompt in `_shared/prompt-library.ts` that maps raw text →
  interpretation JSON, **capturing the framing** (`expression` + `type`,
  e.g. "sub-3"/threshold) alongside the derived seconds. Closed, validated
  output. **Ship eval cassettes** (hard rule #3): a clean race statement,
  a multi-intent statement (the CIM example), a "sub-3" threshold, a vague
  one, a non-goal. Resolve BQ → time using age/sex; resolve a named race →
  date (the `race_intel` table can feed this). Lean on the model's
  comprehension here — it understands "sub 2:20 at CIM" natively (race,
  December, ~5:20/mi, elite stretch); do NOT regress to regex title-parsing
  (that's the bug that read "2:20" as 140s).
- **Scope classifier (principle 11).** The same prompt tags each entry
  `running_goal | running_constraint | adjacent_context | out_of_scope`
  with a reason. Only `running_goal`/`running_constraint` persist as
  coachable goals. `out_of_scope` (weight/nutrition, strength numbers,
  injury treatment, non-running life goals) triggers a warm pushback on the
  confirm screen and is NOT saved as an active goal. Weight/nutrition and
  medical get a firm refusal, not a reframe (safety, not focus).
- Derive paces by reusing **`build-pace-profile`** (plan-independent
  derivation — cheaper than reshaping `update-plan-goal`). Note: both that
  function and `update-plan-goal` currently use a *closed* `ALLOWED_DISTANCES`
  set and reject anything else — Phase 2 must relax this so open distances
  (50k, relay) save as non-pace-derivable rather than 400-erroring.
- A confirm/edit screen that renders the interpretation and lets the
  athlete fix any field, then sets `athlete_confirmed = true`.
- Point onboarding (`OnboardingView.swift`) and the edit sheet
  (`EditGoalSheet.swift`) at this path instead of the dead-end
  `user_goals` insert.

**Done when:** typing the CIM sentence yields a correct, *editable*
interpretation; confirming it writes a confirmed `user_goals` row + a
populated `athlete_pace_profiles` row — with no plan required.

---

### Phase 3 — Wire the goal into athlete_state as CONTEXT (not a math override)

**Governing rule (decided 2026-06-20):** the goal is a *context layer the
features are aware of*, not an anchor that rewrites the fitness math.
Concretely:

| athlete_state output | Source | Goal's role |
|---|---|---|
| `predicted_*_seconds`, `fitness_prediction`, `fitness_signal` | `fitness_snapshots` (reality) | **Never written by the goal.** Aspiration must not distort what fitness says. |
| `pace_zones`, `pace_zone_ranges` | PaceEngine / fitness **by default** | Goal-derived zones only via an **opt-in toggle** (`athlete_settings.pace_zone_source`). |
| goal context block (`active_goals`, `goal_race`, `goal_time_seconds`) | the active confirmed goal | This is where the goal lives — awareness for the Coach + UI. |

This corrects the earlier draft's "confirmed race > goal" anchor line:
that priority is about **confirmed races** (reality may anchor pace +
prediction). **Goals never anchor predictions, and anchor pace zones only
when the athlete flips the toggle.**

**What:** Three jobs. (a) The rebuild (`_shared/athlete-state.ts`) reads
the active *confirmed* goal and fills the goal context block. (b) A pace-
zone source toggle. (c) Compute `goal_salience` per surface and hand the
Coach prompt the goal **plus a cadence directive**.

**Why:** makes the goal flow into every feature as context — fixing the
"no race set" Coach Read — without letting it skew predictions or silently
change pace zones.

**How:**
- **Goal context builder** in `athlete-state.ts`: load the latest
  `status='active' AND athlete_confirmed` goal, read its `interpretation`
  (NOT title-parsing — that's the bug that read "2:20" as 140s), and
  populate `active_goals` + `goal_race`/`goal_time_seconds` (display when
  no plan). Carry framing, distance, target time, target date, days-until,
  named race, constraints. Also compute **`gap_vs_fitness`**: the goal
  against `fitness_prediction` (range-aware, honest) so the Coach can say
  "sub-2:20 is ~10 min ahead of your 2:28–2:31 fitness." Context beside
  the prediction, never written into it.
- **Predictions guard:** keep `predicted_*` / `fitness_prediction` sourced
  only from `fitness_snapshots`. Add a unit test in `athlete-state.test.ts`
  asserting the goal builder writes none of them.
- **Pace-zone toggle:** new `athlete_settings.pace_zone_source`
  (`'fitness'` default | `'goal'`). The pace path honors it — `'goal'` +
  a target time → derive via `derivePaceTableFromGoal`; else fitness, as
  today. `pace_zones` carries a `source` label. Default = zero behavior
  change.
- **Salience:** compute from surface type + weeks-to-race + trajectory
  change; pass into the Coach Read prompt as an explicit directive.
- **Stay-in-lane guardrail (principle 11)** in the Coach Read prompt:
  coaches running/endurance only; may read life context (sleep, stress,
  weather) but prescribes nothing outside running — no medical/injury
  diagnosis, no nutrition/diet/weight guidance, no strength programming, no
  general life advice; redirects off-domain asks briefly and warmly.
- **Eval cassettes (hard rule #3):** "easy-run upload → must NOT mention
  the race"; "weekly report → may give an on-track check-in"; "key workout
  → may connect to the goal"; "when surfaced, coach uses the framing
  ('sub-2:20'), never the stiff boundary"; "predictions are unchanged
  whether or not a goal is set"; **lane/safety: a weight-loss goal gets
  pushback and sets no body-comp target; a career goal is politely
  declined; an injury-treatment ask gets no diagnosis and a redirect; a
  normal running goal sails through.**

**Done when:** after confirming a goal, a rebuild fills the goal context
block and the Coach Read references it appropriately; predictions are
byte-for-byte identical with and without a goal; and pace zones only
change when the toggle is set to `'goal'`.

---

### Phase 4 — Surfaces: entry + the Trends GOAL line

**What:** The text-box entry surface, and the designed-but-unbuilt Trends
"GOAL line" (time + "GOAL" label + countdown to the race date; tap to
edit, which reuses Phase 2).

**How:** the Trends design exists at
`design-system/ui_kits/ios_app/TrendsScreen.jsx`; the Swift
`RunningLog/.../Trends/TrendsTabView.swift` has no goal rendering yet. Use
the empty-state component when no goal is set — never an em-dash (hard
rule #8).

**Done when:** Trends shows the goal with a countdown when set, and a
tappable "set a goal" empty state otherwise.

---

## 8. What we are NOT doing yet

- **Not** touching the confirmed-race ("reality") path. The duplicate
  Cap-10K bug lives in the *inferred* `race_history` jsonb — separate fix.
- **Not** auto-generating training plans from the goal (custom plan
  builder was cut).
- **Not** building full multi-goal management UI. `interpretation` and
  `active_goals` can hold several; Phase 1–4 ship one primary active goal.

---

## 9. Open questions for you

1. **BQ resolution** needs the athlete's age/sex. Collect at onboarding,
   or ask when a goal references a standard like "BQ"?
2. **Named-race resolution** ("CIM" → date/course): lean on `race_intel`,
   a static race calendar, or web lookup at parse time?
3. **Salience tuning** — is the surface/weeks/trajectory function enough,
   or do some athletes want a "talk about my goal more/less" preference?
4. **uuid vs text user_id** on `athlete_pace_profiles` — fix the mismatch
   now or leave it (latent bug)?
5. **One primary goal or several** at launch? Plan assumes one primary
   confirmed goal feeds state; others can sit in `interpretation`.

---

## 10. Build order recap

1. **Phase 1** — extend `user_goals` (migration written; commit + push). ←
2. **Phase 2** — NL entry → parse → confirm/edit → save (+ eval cassettes).
3. **Phase 3** — rebuild reads the goal + salience governance (+ evals).
4. **Phase 4** — entry surface + Trends GOAL line.

Phases 1–3 are the spine and are testable from the database + eval
harness. Phase 4 is the visible reward.

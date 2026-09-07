# Adaptive Plan Builder — Opus Build Plan

**Date:** 2026-07-05
**Purpose:** Phased execution prompts for building the adaptive plan builder
out with Claude Opus (Claude Code). Each phase is one Opus session: paste the
prompt, review the diff, ship. Design fidelity is a first-class acceptance
criterion in every phase, not a polish pass at the end.

---

## 0. Sources of truth (Opus must read these before writing code)

| What | Where | Why |
|---|---|---|
| Design intent — plan builder | `prototypes/adaptive-plan-builder.html` | The interactive design reference. When the web code and the prototype disagree, the prototype wins. |
| Design intent — workout builder | `prototypes/workout-builder.html` | Sibling surface; shared patterns (zone tags, preview, NL description). |
| Voice + tokens | `design-system/README.md`, `design-system/colors_and_type.css` | Post Run Drip: restraint as foundation, intensity as accent. |
| Pace color ramp | `RunningLog/RunningLog/Workouts/PaceSpectrum.swift` | Single source of the 10-stop blue ramp. Blue = pace, warm = mood, coral = alert. Never mix. |
| Pace math | `web/src/components/coach/workout-helpers.ts` | `derivePaceTableFromGoal`, race-equivalence ratios. Never reinvent. |
| Feature spec | `outputs/adaptive-coach-plan-builder-spec-2026-07-03.md` | R1–R7 requirements, phasing, decisions. |
| Live-editing plan | `outputs/phase-b-live-plan-editing-buildplan-2026-07-03.md` | Phase B is already planned; don't duplicate it here. |
| Current builder code | `web/src/components/coach/plan-builder-client.tsx` | Already shipped (2026-07-05): always-on library rail, drag-and-drop, tap-to-quick-add, AM/PM doubles, session counter with >7 coral alert. |

### Design non-negotiables (repeat in every prompt)

1. **Three-palette rule.** Pace/intensity is the blue depth ramp only
   (`#93B9D6` Easy → `#0E1D4E` Mile). Coral is alert + punctuation — one
   coral element per visual cluster, maximum. Green never appears for
   "good"; within-range reads as confident ink.
2. **Editorial primitives.** Mono uppercase eyebrows, Crimson Pro display,
   PT Serif body/italic asides, plate strip framing, tabular numerals for
   every number.
3. **Empty states** use eyebrow + plain-prose nudge (+ optional CTA). Never
   an em-dash placeholder (hard rule #8).
4. **Ranges, not points** for anything predictive or mileage (hard rule #7):
   "44–48 mi", never "46.0".
5. **AI advises, never acts.** Any AI-facing surface says so in the copy and
   means it in the code (`auto_applied: false`, review queues, coach confirm).

### Engineering guardrails (hard rules that bite here)

- New tables/columns → migration with RLS in the same file, append-only
  naming `YYYYMMDDHHMMSS_*.sql`; prod apply only via `supabase db push`
  from a committed SHA (hard rules #1, #5, #9).
- Any LLM prompt change lands in `_shared/prompt-library.ts` with eval
  cassettes under `_evals/cassettes/<prompt>/` first — CI enforces this
  (hard rule #3).
- All `coachable_moments` / plan-mutation writes via service-role edge
  functions (hard rule #4).

---

## Phase 1 — Pace-colored mileage ramp in the portal

**Goal:** The Plan setup ramp (adaptive mode) becomes the stacked
pace-colored bar chart from the prototype: each week's bar is its mileage,
pale-sky base = easy fill, deeper blues = placed quality miles by zone,
coral dot when week-over-week min jumps >10% (excluding down weeks).

**Files:** `web/src/components/coach/plan-setup-section.tsx` (ramp lives
here), `workout-helpers.ts` (zone-mile aggregation helper),
`plan-builder-client.tsx` (pass placed workouts into the section).

**Acceptance:**
- Bars restack live as workouts are placed/removed.
- Absolute-pace steps map to nearest zone color via the pace table.
- Tooltip per segment: "LT · 6.0 mi". Bar click selects the week.
- No green anywhere; coral only on the >10% flag.
- Visual parity with `prototypes/adaptive-plan-builder.html` ramp.

**Opus prompt:**
> Read CLAUDE.md, design-system/README.md, prototypes/adaptive-plan-builder.html
> (the `renderRamp`, `weekZoneMiles`, `nearestZoneKey` functions and `.ramp*`
> CSS), and web/src/components/coach/plan-setup-section.tsx. Port the
> prototype's pace-colored stacked mileage ramp into the portal's Plan setup
> section. Compute per-week zone miles from the plan's placed workouts using
> the pace table from pace-reference-editor. Follow the three-palette rule
> exactly (blue ramp from PaceSpectrum.swift stops; coral only for the >10%
> ramp warning). Keep ranges-not-points labeling. Typecheck with tsc and
> describe how you visually verified against the prototype.

---

## Phase 2 — Rules, guidelines & coach notes for the AI

**Goal:** The prototype's "Rules & guardrails" section becomes real: coaches
write hard rules / guidelines / a silent context note on the plan; the AI
reads them when proposing reschedules and block rewrites.

**Data model (migration required):** add `coach_ai_guidance JSONB` to
`plan_templates` — shape `{ rules: [{on, strength: 'hard'|'guide', text}],
note: string }`. RLS in the same migration (coach-scoped via
`current_coach_id()` — re-read `20260311120000_fix_coach_rls_recursion.sql`
first). **Author the migration; do NOT apply to prod** (hard rule #9).

**UI:** New `coach-ai-guidance-section.tsx` in the builder, below the weeks:
toggle rows, hard-rule/guideline select, free-text add, the silent note, and
the "assistant reasons inside these lines; it proposes, you decide" copy —
lifted verbatim in tone from the prototype.

**Wiring:** `reschedule-plan` (and later `rewrite-block`) prompt assembly
reads `coach_ai_guidance` and injects rules as constraints. This is a prompt
change → prompt-library + eval cassette BEFORE ship (hard rule #3). Add a
cassette where a proposal would violate a hard rule and assert the model
refuses/reroutes.

**Opus prompt:**
> Read CLAUDE.md, outputs/adaptive-coach-plan-builder-spec-2026-07-03.md §R5,
> the Rules section of prototypes/adaptive-plan-builder.html, and
> supabase/functions/reschedule-plan. Implement coach AI guidance end to end:
> (1) migration adding coach_ai_guidance JSONB to plan_templates with RLS in
> the same file, authored only — never applied to prod; (2) a builder section
> matching the prototype's rules UI and voice; (3) reschedule-plan reads the
> rules via _shared/prompt-library.ts with a new eval cassette proving a hard
> rule is honored. AI advises, never acts: keep auto_applied false.

---

## Phase 3 — Doubles through the whole pipe

**Goal:** The `session: "am"|"pm"` field (already in the builder as of
2026-07-05) flows through subscription and display instead of being
web-only.

**Touch points:**
- `subscribe-to-plan/index.ts` — materializer must schedule two
  `scheduled_workouts` on a doubled day (verify the unique constraints on
  that table allow it; if there's a `(plan, athlete, date)` uniqueness
  assumption, widen it via migration).
- iOS `Training/` day views + `DayDetailPlate22.swift` — render two sessions
  stacked with AM/PM eyebrows, matching the prototype's preview treatment.
- `shift-day` — moving a doubled day moves both sessions or asks; decide and
  document.
- Cap logic: >7 sessions/week warns (coral) everywhere it's displayed;
  never blocks — coaches outrank the UI.

**Opus prompt:**
> Read CLAUDE.md, the session field in
> web/src/components/coach/plan-builder-client.tsx, and
> supabase/functions/subscribe-to-plan/index.ts. Make AM/PM doubles real:
> materialize both sessions per day, check and if needed migrate uniqueness
> constraints (RLS/migration rules apply), render doubles in the iOS day
> views per the prototype's AM/PM stacked treatment, and define shift-day
> behavior for doubled days. Write tests for the materializer path.

---

## Phase 4 — Library & builder polish (design parity pass)

**Goal:** Close the visual gap between the portal and the prototypes.

- Library rail: pin-to-top (needs `pinned BOOLEAN` on `workout_templates`,
  migration + RLS), zone-dot tags derived from steps (not just
  workout_type), estimated line in mono ("2 wu · 6 × 800 @ 5K · 2 cd").
- Workout labels follow the 10-zone taxonomy: `MP 7 mi`, `LT 6 mi`,
  `5K 5×1km`; "tempo"/"threshold" survive only as legacy data, never new UI
  copy (roadmap decision 2026-05-28).
- Natural-language "Describe it" box from `prototypes/workout-builder.html`
  ported into the portal's new-workout modal (parser already exists in the
  prototype; port as a pure TS module with unit tests).
- Empty states audited against the empty-state component pattern.

**Opus prompt:**
> Read design-system/README.md in full, both prototype files, and the current
> portal workout surfaces (workout-template-card.tsx, workout-template-form.tsx,
> plan-builder-client.tsx). Do a design-parity pass: 10-zone labels, zone-dot
> tags, pinned templates (migration + RLS, authored only), and port the
> workout-builder prototype's natural-language parser into the new-workout
> modal as a tested pure module. List every visual decision you made and the
> prototype line it came from.

---

## Phase 5 — Athlete preview rail

**Goal:** The prototype's "as the athlete runs it" preview inside the portal
builder: pick one of the coach's real athletes (or a sample), see the
selected week resolved — their paces from their race anchor, their preferred
days (`athlete_plan_subscriptions`), doubles pinned, absolute targets
identical for everyone. This is the design's core promise made visible:
write it once, every athlete reads it in their own paces.

**Opus prompt:**
> Read the preview column of prototypes/adaptive-plan-builder.html
> (athleteSessionMap, sessionBodyHTML), athlete_plan_subscriptions usage in
> supabase/functions/subscribe-to-plan, and workout-helpers.ts. Build a
> preview rail in the plan builder that resolves the selected week for a
> chosen athlete: zone paces from their anchor via derivePaceTableFromGoal,
> day remapping from their schedule prefs, AM/PM doubles kept on their day.
> Predictions and paces show as ranges where the prototype does. Read-only;
> no writes.

---

## Sequencing & review

P1 and P4 are pure-frontend and safe to run first (no migrations applied).
P2 and P3 author migrations — batch them for one `supabase db push` from a
committed SHA alongside the pending `20260703*` and `20260615*` migrations.
P5 last; it reads everything the others produce.

After each Opus session: `tsc --noEmit`, run the dev server, compare the
surface side-by-side with the prototype in the browser, and check the diff
for palette violations (grep for greens and for coral used as a fill).

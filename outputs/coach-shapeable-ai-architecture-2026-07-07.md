# Coach-Shapeable AI: Layered Constraint Architecture

**Date:** 2026-07-07
**Status:** Proposed (design doc — no code changes yet)
**Decisions locked in this doc:** coach-authored principles are scoped to the
coach's own athletes only; hard safety rules always win and can never be
overridden by a coach; this is a design doc, implementation phased separately.
**Companions:** this is the umbrella architecture that situates three
existing specs — `athlete-guidance-rules-prd-2026-07-01.md` (Coach Rules:
enforceable doctrine), `ai-feedback-loop-design-2026-07-07.md` (athlete AI
profile / implicit shaping), and `_shared/insight-safety.ts` (the shipped
output guard). Where this doc and those specs describe the same component,
the dedicated spec wins on detail; this doc owns the layering and
precedence model.

---

## 1. The problem

We want an AI that is simultaneously:

1. **Bounded** — never diagnoses, never says "stop training," never invents
   medical entities, never acts without a human decision (hard rule: *AI
   advises, never acts*).
2. **Very helpful** — rich quantitative analysis (ACWR, pace zones, fitness
   trends, compliance) fused with qualitative signal (mood arcs, niggles,
   life context) into observations worth reading.
3. **Coach-shapeable** — a coach can teach the AI *their* running
   philosophy (intensity distribution, deload triggers, injury decision
   trees, voice) and have it apply to their athletes.

These three pull against each other. The naive failure modes: bolt on so
many prompt warnings the AI becomes useless mush ("consult a professional"
for every question); or let coaches free-text the system prompt and watch
one coach's "pain is weakness leaving the body" leak into medical territory.

The resolution is **layering**: different kinds of constraints live at
different layers, enforced by different mechanisms, with an explicit
precedence order. Coaches get a wide, structured surface to shape — but the
surface is *inside* the safety wall, never the wall itself.

## 2. The layer stack

```
┌──────────────────────────────────────────────────────────────┐
│ L0 · STRUCTURAL (code, not prompts)                          │
│ Closed vocabularies · constrained selection · schema         │
│ validation · service-role writes · auto_applied: false       │
├──────────────────────────────────────────────────────────────┤
│ L1 · SAFETY GUARDRAILS (product-owned, immutable by coaches) │
│ Never diagnose · never "stop training" · never medical       │
│ claims · detection-not-diagnosis · range+confidence          │
├──────────────────────────────────────────────────────────────┤
│ L2 · PRODUCT COACHING PRINCIPLES (global, versioned)         │
│ docs/coaching/principles.md · ask-vs-answer · voice defaults │
├──────────────────────────────────────────────────────────────┤
│ L3 · COACH-AUTHORED PRINCIPLES (per-coach, validated)   NEW  │
│ Structured philosophy: intensity, scaling, deload triggers,  │
│ injury tree, never-list, voice examples, forcing questions   │
├──────────────────────────────────────────────────────────────┤
│ L4 · ATHLETE CONTEXT (computed per request)                  │
│ athlete-state.ts quant · voice-log qual · data_depth gating  │
└──────────────────────────────────────────────────────────────┘
```

**Precedence: L0 > L1 > L2 > L3 > L4.** Lower layers are harder. A coach
principle (L3) can *specialize* product defaults (L2) — "my marathoners run
85/15, not 80/20" — but can never *contradict* safety (L1), and nothing in
any prompt can escape structure (L0), because L0 isn't prompt text at all.

The key insight, already proven in this codebase by `reschedule-plan` and
the niggles classifier: **the strongest constraints are the ones the LLM
physically cannot violate.** A model choosing from `WORKOUT_CODES_BY_DAY`
cannot invent a workout. A classifier with a closed 30-entry body-part
vocabulary cannot output "ITBS." Push every constraint as far down the
stack as it will go; use prompt text only for what can't be structural.

## 3. Layer by layer

### L0 — Structural constraints (already largely built)

These live in code and schemas, not prompts. Existing examples, kept and
extended:

- **Constrained selection over free generation.** `reschedule-plan` picks
  from a closed workout-code library. The adaptive plan builder's Phase E
  block-rewrites extend this same pattern. Any new "AI proposes a change"
  feature must be a selection from a validated library, never free text
  that gets parsed into a plan.
- **Closed vocabularies.** Niggles body parts (~30 entries), mood labels
  (6), move-day reason codes, workout labels = pace-zone labels (10-zone
  taxonomy). The classifier maps or omits; it never invents.
- **AI advises, never acts.** All AI-proposed mutations write to
  `plan_adjustments` with `auto_applied: false`. A human (coach, or the
  athlete when self-coached) applies them. No exceptions.
- **Output schema validation.** Every LLM response parses against a strict
  schema (the daily-read v5 schema pattern). Parse failure = no output
  surfaces, not a degraded output.
- **Service-role writes only** for `coachable_moments` (hard rule #4) and
  RLS on every table (hard rule #1).

**The output guard already ships:** `_shared/insight-safety.ts` scans
every generated text before it's persisted — high-precision regexes for
named diagnoses, medical referrals, and stop/rest directives; one
regenerate under `INSIGHT_STRICT_SUFFIX`; if it still trips, fall back to
a deterministic read (never show a degraded output). Keep this exactly as
designed. Two extensions worth adding to the same module:

- **Seconds-precision race projections** (`\d:\d\d:\d\d\s*(PROJECTED|FINISH)`
  shapes) — hard rule #7 currently has no mechanical backstop.
- **Numeric claims cross-check:** any number the output cites must appear
  in the input context — guards against hallucinated stats, and
  mechanically enforces the `data_depth` "every pull-quote cites a real
  number" rule.

### L1 — Safety guardrails (product-owned)

The immutable "never" set. Source of truth is the **"What I want the AI to
NEVER do"** section of `docs/coaching/principles.md` plus hard rules #2 and
#7 in CLAUDE.md. Enforced three ways, redundantly:

1. **Prompt text** — one shared guardrail block, not 35 copies. Today the
   never-rules are (at best) repeated per prompt. Extract them into
   `_shared/prompts/_guardrails.v1.ts` and inject into every generative
   prompt as a `{{guardrails}}` substitution. One place to edit, one
   version to pin, impossible for a new prompt to forget them.
2. **`insight-safety.ts` guard** (L0 above) — deterministic backstop,
   already shipped and unit-tested.
3. **Eval gate** — the harness's named pattern groups (which already
   propagate to all cassettes) assert the never-rules against every
   recorded prompt. CI already blocks prompt changes without cassette
   coverage (`.github/scripts/check_eval_coverage.py`); the guardrail
   block itself gets its own adversarial cassette set (inputs designed to
   bait diagnosis, "should I stop running?", medication questions).

Coaches cannot edit this layer. Full stop. That's the decision Rio locked:
hard rules always win.

### L2 — Product coaching principles (global)

`docs/coaching/principles.md`, versioned (currently v0.2 — mostly still a
skeleton; only the forcing-questions section is filled and prompt-ready).
This is the *default* coaching brain: what the AI believes when no coach
has said otherwise — which is exactly Maya's case, and Maya is the wedge.

Two actions this doc implies:

- **Fill the skeleton.** The template's sections (intensity philosophy,
  scaling by profile, deload signals, injury decision tree, never-list,
  voice + example messages) need real content before L3 makes sense —
  coach principles are *diffs against* these defaults, so the defaults
  must exist. This is product work, not engineering.
- **Inject by section, versioned.** Prompts consume principles as
  precomputed substitution strings (`{{principles_injury}}`,
  `{{principles_voice}}`, …) pinned to a principles version, per the doc's
  own versioning rule. The whole doc is sized to fit a system prompt
  (1-2 pages) so this stays cheap.

### L3 — Coach-authored principles (the heart of the request)

Prior art already covers half of this layer, and covers it well: the
**Coach Rules PRD** (`athlete-guidance-rules-prd-2026-07-01.md`, draft
v2). Its design is adopted here wholesale as L3's *enforceable* half:

- Coach writes doctrine as **plain-English sentences**; the system parses
  each into a **closed constraint taxonomy** (hard-day spacing, volume
  caps, progression limits, periodization cadence, taper doctrine, signal
  responses, workout substitutions) and answers with its interpretation.
  The coach's confirmation is the contract — no silent downgrades.
- Parsed rules are **mechanically enforced**: they filter the AI's choice
  set *before* it chooses (proposals never violate them), validate plans,
  and ground commentary. Sentences that don't parse become **advisory
  rules** — injected as prompt context, honestly labeled as considered-
  not-enforced.
- Same machinery serves self-coached Maya, self-authored.

That PRD owns the data model (`coach_rules`), the parse-and-confirm UX,
and the enforcement points. What this architecture doc adds on top is the
*grounding* half of L3 — the philosophy that isn't a checkable constraint
but should still shape analysis and voice. These map to the sections of
`principles.md`, authored per-coach through the web coach portal (the
canonical coach surface per the 2026-07-03 decision):

- **`intensity_philosophy`** — distribution ("my marathoners run 85/15"),
  long-run-quality vs tempo-volume weighting. Grounds Trends/Read
  commentary about what the athlete's week *should* look like.
- **`athlete_scaling`** — how the coach adjusts for age, history, goal
  aggressiveness. Grounds how the AI frames the same data for different
  athletes.
- **`voice`** — tone descriptor + 3-5 worked example messages (situation →
  message), used as few-shot examples in that coach's athletes' Read and
  report prompts. How the AI starts to *sound like* the coach.
- **`forcing_questions`** — the coach's own additions to the ask-vs-answer
  set in `principles.md` (already the template's strongest section).
- **`never_list`** — the coach's additions to L1 (tighter only; a coach
  can add "never prescribe doubles under 50 mpw," never subtract).
- **`open_questions`** — explicit "defer to me" topics; the AI answers
  these with "your coach will want to weigh in," verbatim per the
  `principles.md` contract.

Storage follows the same discipline as `coach_rules`: coach-scoped rows
(`current_coach_id()` RLS, hard rules #1/#6), **append-only versioning**
(edits insert a new version, mark the old `superseded`), and a `status`
lifecycle of `draft → active | rejected` with a human-readable
`rejection_reason`. Whether grounding sections live as a second table or
as a `grounding` rule-type inside `coach_rules` is an implementation call
for the PRD's build — one system, two kinds of content, is the intent.
Every generated output records which rule/section versions grounded it
(§6, audit trail), so "why did the AI say that?" is always answerable.

Note the dual-use pattern the PRD's taxonomy enables: a structured
"signal response" rule ("niggle mention → 48h easy before quality") can
drive a deterministic evaluator in `_shared/rules/` *and* ground prose —
coach-configured constraints become the highest-leverage, fully-
deterministic form of "shaping the AI," because they operate at L0, not
in prompt text. One real example of grounding content already exists:
Rio's temporal-evaluation principle
(`coaching-principle-temporal-evaluation-2026-07-03.md`) — exactly the
kind of content the grounding sections hold.

#### Write-time validation (where "hard rules win" is enforced)

Coach submissions land as `draft` and pass through a validator edge
function before becoming `active`:

1. **Deterministic checks** — schema shape, closed enums, vocabulary
   membership (body parts must be in the niggles vocabulary), threshold
   sanity ranges (ACWR trigger must be 0.5–2.5), length caps, blocklist
   scan on prose fields.
2. **LLM contradiction check** — a dedicated prompt (in the prompt
   library, with its own cassettes) asks: does this content contradict any
   L1 guardrail? Does it diagnose, prescribe treatment, tell athletes to
   push through pain descriptors that L1 routes to "refer"? Output is a
   structured verdict.
3. **Reject with explanation** — a rejected draft gets a human-readable
   `rejection_reason` shown in the portal ("This reads as prescribing a
   treatment protocol. Rephrase as a monitoring rule — e.g. 'flag calf
   mentions to me after 2 occurrences.'"). The coach edits and resubmits.
   No silent dropping, no silent rewriting of the coach's words.

The validator is itself a prompt, so it goes through the same eval gate as
everything else (hard rule #3), with adversarial cassettes: coaches trying
(innocently or not) to smuggle in medical advice, doubles for a 30 mpw
runner, "ignore previous instructions."

#### Scope

Per the locked decision: a coach's principles apply **only to athletes
with an active relationship to that coach** (existing coach-athlete link,
`current_coach_id()`-style scoping). Self-coached athletes like Maya get
pure L2. No global sharing, no cross-coach leakage — which also keeps the
liability story clean: a coach's philosophy reaches exactly the athletes
who chose that coach.

### L4 — Athlete context (computed, not authored)

Already the strongest part of the system: `_shared/athlete-state.ts`
assembles ACWR, monotony/strain, week compliance, fitness trend, pace
zones (from PaceEngine), niggle history, mood trends. Two rules keep this
layer honest and *are what make the AI quantitatively helpful without
being quantitatively dishonest*:

- **The math is computed in code; the LLM narrates, never calculates.**
  ACWR, pace derivation, fitness prediction all happen deterministically
  (`dataAnalysis.ts`, `workout-helpers.ts`, PaceEngine). The LLM receives
  results and turns them into observation. This kills hallucinated
  arithmetic — the most common way "helpful analysis" goes wrong.
- **Ranges + confidence, never points** (hard rule #7), and every
  editorial claim cites a specific number from context (`data_depth`
  rule). The output lint enforces both mechanically.

Qualitative helpfulness comes from the same fusion the product is built
on: voice-log signal (mood, fatigue, niggles, life context) sits next to
the quant in the assembled state, and the ask-vs-answer forcing-question
pattern (principles.md §"When to ask") governs when the AI probes instead
of pronouncing.

## 4. Prompt assembly (how the layers compose at runtime)

Per generation, the edge function composes — using the existing
`loadPrompt` strict-substitution mechanics, with all conditionals
precomputed by the caller as the library requires:

```
loadPrompt("daily-read.v6", {
  guardrails:        GUARDRAILS_V1,                    // L1, shared block
  principles_voice:  productPrinciples("voice", v),    // L2, version-pinned
  coach_overlay:     coachOverlay(athleteId),          // L3, "" if none
  athlete_state:     buildAthleteState(athleteId),     // L4
  ...
})
```

`coachOverlay()` fetches the athlete's coach's `active` principle rows,
renders each section through a fixed template (coach content is *data
inside* a product-owned frame, never raw prompt text), and prepends an
explicit precedence statement:

> Your coach's philosophy below specializes the default coaching
> principles. Where they conflict, the coach's philosophy wins — except
> for the SAFETY RULES section, which nothing overrides.

For self-coached athletes `coach_overlay` renders as the empty section.
`activePlan == nil` and `coach == nil` are both first-class states.

## 5. The second shaping channel: feedback, not just declaration

Declared principles (L3) are the *explicit* channel. The *implicit*
channel — shaping the AI over time from real usage instead of philosophy
essays — is already specced: **`ai-feedback-loop-design-2026-07-07.md`**.
Its design (thumbs, advice-followed signals, per-workout quick-takes, and
coach corrections/directives distilled by pure-function derivation rules
into a typed, evidence-backed `athlete_ai_profile` that becomes ~80
tokens of prompt context, athlete-visible and coach-overridable) is this
architecture's L3/L4 implicit complement. Two additions this doc layers
onto that spec:

- **Coach edits become few-shot examples.** Beyond the profile's typed
  fields: store (input context → AI draft → coach's rewrite) per coach,
  and surface the coach's last N rewrites as few-shot examples in that
  coach's athletes' prompts, alongside the L3 `voice` examples. A coach's
  rewrite is the highest-signal voice data there is.
- **Rejections become eval cassettes.** A rejected output is, almost by
  definition, a missing test case. A lightweight "promote to cassette"
  path in the review flow turns coach QA into permanent regression
  coverage — non-golden coverage (see §6) grows from real usage instead
  of synthetic authoring, which is the part of cassette work that has
  actually been painful.

No fine-tuning anywhere in this design. Context-shaping (structured
principles + few-shot examples + eval-gated prompts) is auditable,
reversible, per-coach, and cheap. Fine-tuning is none of those; it is
explicitly out of scope.

## 6. Verification and audit (how we know it's working)

- **Eval gate: golden-set policy (revised 2026-07-07).** Full cassette
  coverage of every prompt was the original ambition; in practice it
  produced authoring fatigue, not safety. The revised hard rule #3:
  CI *blocks* only the **golden families** — `daily-read`,
  `injury-analysis`, `reschedule-plan`, `coaching-agent-*` (the
  athlete-facing, safety-baitable surfaces) — and requires *recorded*
  cassettes there, not stubs. Every other prompt family warns only;
  its gate is manual review against `principles.md`, with coverage
  growing from the promote-to-cassette flow (§5). This is safe because
  the runtime layers (L0 `insight-safety.ts`, schema validation, closed
  vocabularies) — not cassettes — are the primary safety enforcement;
  cassettes are regression tests for quality drift, which matters most
  exactly on the golden surfaces. New cassette families this design
  still requires (all within golden or validator scope): guardrail
  adversarial set (L1), validator adversarial set (L3), and
  per-section overlay tests — same input athlete state, with and
  without a coach overlay, asserting the overlay changed tone/emphasis
  *and* the guardrail patterns still pass.
- **Generation audit trail.** Every stored output records: prompt name +
  version, principles doc version (L2), the set of coach rule/section
  row versions in the overlay (L3), and athlete-state snapshot reference
  (L4). One table, written at generation time. This makes coach-visible
  provenance ("the AI flagged this because your deload rule triggered")
  a query, not a reconstruction.
- **Output lint metrics.** Count lint rejections by rule and by prompt
  version. A spike after a prompt change is the canary.

## 7. Phasing

**Phase 1 — consolidate the wall (no new tables).**
Extract the shared guardrail block and wire it into all generative
prompts; verify every athlete-facing generator actually calls
`insight-safety.ts` (it's shared, but coverage should be audited) and add
the two extensions (§3-L0); record the guardrail adversarial cassettes
for the golden families, including finishing the stubs-only golden dirs
(`reschedule-plan`, `coaching-agent-*` — rubrics are authored, each needs
one `record.ts` run). Fill `principles.md` past skeleton (product work —
it gates everything else, since coach content is a diff against these
defaults).

**Phase 2 — Coach Rules, per the PRD.**
Build `athlete-guidance-rules-prd-2026-07-01.md`: `coach_rules` migration
(RLS same migration; `supabase db push` from a committed SHA per hard
rule #9), plain-English parse-and-confirm flow, enforcement at proposals
+ plan validation + commentary. Write-time validator + its adversarial
cassettes. Audit-trail table. Start with the two lowest-risk grounding
sections (`voice`, `never_list`) in the same portal surface.

**Phase 3 — the remaining grounding sections + dual-use rules.**
`intensity_philosophy`, `athlete_scaling`, `forcing_questions`,
`open_questions`; the dual-use path where signal-response rules also
drive deterministic `_shared/rules/` evaluators registered per coach.

**Phase 4 — the feedback loop, per its spec.**
Build `ai-feedback-loop-design-2026-07-07.md`'s phasing, plus this doc's
two additions: per-coach few-shot store from coach edits, and the
promote-to-cassette flow from rejections.

Sequencing note: Phases 2-4 assume the web coach portal work already
greenlit (2026-07-03 adaptive plan builder). The portal editor and the
plan builder's phase/shape config are natural siblings — same surface,
same coach, same "coach teaches the system" gesture. None of this
touches the deprioritized legacy `(app)/coach` route.

## 8. What this deliberately does not do

- **No coach-editable safety layer.** Rejected option, recorded: even
  "certified coach" unlock of return-to-run guidance is out for now.
  Revisit only with legal review.
- **No global coach knowledge base.** Per-coach only. If cross-coach
  sharing ever happens, it needs a curation pipeline that doesn't exist
  and isn't designed here.
- **No free-text system-prompt field for coaches.** Every escape valve of
  this kind eventually gets used, and it converts L3 into an L1 bypass.
- **No fine-tuning.** See §5.
- **No AI autonomy increase.** Everything here shapes what the AI *says*;
  nothing changes what it can *do*. Advises, never acts — unchanged.

---

*Grounding references: `docs/coaching/principles.md` (v0.2),
`supabase/functions/_shared/prompt-library.ts`,
`supabase/functions/_shared/insight-safety.ts`,
`supabase/functions/_shared/rules/`, `supabase/functions/_evals/`,
`supabase/functions/_shared/athlete-state.ts`,
`outputs/athlete-guidance-rules-prd-2026-07-01.md`,
`outputs/ai-feedback-loop-design-2026-07-07.md`,
`outputs/coaching-principle-temporal-evaluation-2026-07-03.md`,
`outputs/body-mentions-design.md`,
`outputs/plan-mutations-and-race-design.md`,
`outputs/adaptive-coach-plan-builder-spec-2026-07-03.md`,
`outputs/marathon-prediction-honesty.md`.*

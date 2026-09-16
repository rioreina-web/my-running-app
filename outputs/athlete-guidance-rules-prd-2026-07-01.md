# Coach Rules — coach-authored training doctrine for the AI

**PRD · 2026-07-01 · Draft v2** *(v1 scoped this to tone/topic steering
of AI prose; reframed after review — training rules are the product,
voice rules are a secondary rule type within the same system.)*

## Problem statement

A coach's training doctrine — how they space hard days, cap long runs,
shape tapers, respond to niggles — lives in their head. The AI knows
none of it, so every proposal it makes (a reschedule, a plan tweak, a
readiness comment) reasons from generic principles, and the coach must
re-check everything. The cost: coaches can't delegate anything to the
AI, athletes get advice their coach would veto, and the product's core
promise — a coach's nervous system — stops at observation.

**Coach Rules** lets a coach write their doctrine once, in plain
English, per athlete or roster-wide. The system then enforces it
everywhere the AI touches training: proposals never violate it, plans
are checked against it, and commentary reasons from it.

## The two rule types

1. **Training rules (the core).** Doctrine about training itself.
   *"Never two hard days back-to-back for her." "Cap his long run at
   2:45 regardless of plan." "She tapers 10 days, not 14." "Any niggle
   mention → 48 hours easy before we discuss quality." "Down-week every
   4th week, −30%." "No track work — hills instead, always."*
   These are **enforced**: parsed into structured constraints the
   system checks mechanically.
2. **Voice rules (secondary).** How the AI talks about the athlete.
   *"Feeling first, no pace talk mid-block." "Stop surfacing the calf —
   it's managed."* These are **advisory**: injected into prompts to
   steer tone and topics. (Fully specced in draft v1; carried forward
   unchanged as the minor sibling.)

The coach writes both the same way — one plain-English sentence. The
system decides which type it is and tells the coach what it understood.

## How a training rule works (in real terms)

**Writing.** The coach types "no back-to-back hard days for Sarah."
The app answers with its interpretation: *"I'll enforce: at least one
easy or rest day between quality sessions. Correct?"* Coach confirms —
that confirmation is the contract. If the sentence doesn't map to a
constraint the system knows how to enforce, the app says so honestly:
*"I can't enforce this mechanically — I'll treat it as standing context
the AI considers when advising."* No silent downgrades.

**The closed constraint taxonomy (v1).** Rules parse into a fixed set
of enforceable shapes — same philosophy as `reschedule-plan`'s closed
workout library: constrained selection, never free interpretation.

| Constraint type | Example rule |
|---|---|
| Hard-day spacing | "Never two quality days in a row" |
| Volume caps | "Long run ≤ 2:45", "weekly mileage ≤ 55" |
| Progression limit | "Never increase weekly volume >10%" |
| Periodization cadence | "Every 4th week is a down week, −30%" |
| Taper doctrine | "10-day taper, last quality 8 days out" |
| Signal response | "Niggle mention → 48h easy before quality" |
| Workout substitution | "No track — hills for VO2 work" |

Anything outside the taxonomy becomes an advisory rule, labeled as such
in the coach's list ("advisory — considered, not enforced").

**Where rules bite (all three in v1):**

1. **Proposals (hard enforcement).** When the AI drafts a reschedule or
   plan adjustment, options violating a rule are never proposed. If a
   missed Tuesday workout can only fit next to Thursday's quality
   session, the AI doesn't bend the rule — it says the rule blocks a
   clean fix and routes the call to the coach. Rules constrain the
   choice set before the AI chooses; the existing
   `plan_adjustments` no-auto-apply flow is unchanged.
2. **Plan validation.** When a plan is imported or a coach publishes
   one, it's checked against the athlete's rules. Violations listed in
   plain terms: *"Week 7 has quality Tue + Wed — violates 'no
   back-to-back hard days.'"* The coach can fix or knowingly override —
   coaches may break their own rules; the AI may not.
3. **Advice and commentary.** Daily Read, weekly report, and race
   readiness reason from the doctrine. Readiness commentary for an
   athlete with a 10-day-taper rule discusses *her coach's* taper, not
   a textbook one. Voice rules apply here too.

**Felt as the athlete:** Sarah misses Tuesday. The reschedule
suggestion she sees already respects her coach's spacing rule — she
never sees an option her coach would veto. Her Read says *"your coach
keeps quality days separated, so the tempo moves to Friday"* — the
doctrine is visible, attributed, human.

## Goals

1. A coach can encode their doctrine without technical skill: ≥80% of
   attempted training rules parse to an enforceable constraint on the
   first or second try.
2. Delegation actually happens: ≥50% of AI reschedule proposals for
   rule-covered athletes get coach approval without edits (vs. baseline
   without rules).
3. Zero rule violations in shipped proposals — mechanically checkable,
   so the target is literal zero.
4. Safety holds: rules cannot make the AI diagnose, prescribe
   medically, or auto-apply changes. "AI advises, never acts."

## Non-goals

- **AI-generated training plans.** The custom plan builder was cut
  deliberately; rules constrain and validate, they don't author.
- **Rules as code / a visible DSL.** Coaches write sentences; the
  structured form is internal (surfaced only as the plain-English
  confirmation).
- **Rules changing computed metrics.** ACWR, pace zones, fitness
  prediction stay rule-independent. Rules govern proposals and prose.
- **Auto-apply.** Confirmed rules filter what's *proposed*; a human
  still approves every plan change.
- **Medical logic.** "Niggle → 48h easy" is a training-load response a
  coach owns. Rules asserting medical judgment ("the knee is fine,
  push through") are rejected at write time, with a plain explanation.

## Users and stories

- As a coach, I want to write my training doctrine once per athlete (or
  once for my whole roster, with per-athlete exceptions) so every AI
  proposal already fits how I coach.
- As a coach, I want the app to tell me exactly what it will enforce
  before a rule goes live, so there are no surprises.
- As a coach, I want plan-vs-rules violations flagged when I build or
  import a plan, so my own plans honor my own doctrine.
- As a coach, I want to be told when a rule blocked the AI from
  solving something, so I make the judgment call.
- As a self-coached athlete (Maya), I want to write my own training
  rules ("never move my long run off Sunday") so the AI's suggestions
  fit my life — same machinery, self-authored.
- As an athlete with a coach, I want to see the rules governing my
  training suggestions, attributed to my coach.

## Data model (sketch, no code)

One table, `coach_rules`, RLS in the same migration (hard rule #1):
athlete it applies to; author (coach via `current_coach_id()` — hard
rule #6 — or the athlete); scope (athlete-specific or roster-default);
the raw sentence; the parsed constraint (typed against the closed
taxonomy) or an advisory marker; confirmation state (rules enforce only
after the coach confirms the interpretation); active flag. Caps: ~15
active enforced rules per athlete to keep conflicts tractable.
Conflicting rules are detected at write time ("this contradicts your
roster rule — which wins for Sarah?").

## Requirements

**P0:** rule table + RLS; sentence → constraint parser with
confirm-before-enforce loop (its own prompt in the library + eval
cassettes — hard rule #3, including adversarial and ambiguous
phrasings); enforcement in reschedule/adjustment proposals; plan
validation on import/publish; rule visibility to the athlete;
write-time rejection of medical assertions; blocked-proposal
escalation to the coach.

**P1:** doctrine injection into Daily Read / weekly report / race
readiness; voice rules (the v1-draft feature, same list UI); quick-add
from coachable-moment cards; roster-level defaults with per-athlete
overrides; "which rule shaped this" attribution on proposals.

**P2:** rule templates from common doctrines; per-rule expiry ("through
this block"); coach-configurable thresholds on coachable-moment rule
evaluators (the original structured-triggers idea).

**Acceptance criteria (core path):**

- Given "no back-to-back hard days," when the coach confirms, then no
  reschedule proposal ever places two quality days adjacent — verified
  mechanically in tests, not by LLM judgment.
- Given an unenforceable sentence ("keep her honest about effort"),
  then the app labels it advisory and never claims enforcement.
- Given a plan with a week violating a confirmed rule, then publishing
  flags the specific week and rule, and proceeding requires explicit
  override.
- Given a rule that blocks every valid reschedule option, then the AI
  proposes nothing, explains which rule blocked it, and notifies the
  coach.
- Given a rule "tell her the knee is fine," then it is rejected with an
  explanation and nothing is stored.

## Coach UI

Same surface as draft v1 — one screen per athlete in the web portal
(`coach-portal/athletes/[id]/`), plus a roster-rules screen. Rule cards
now carry an **Enforced / Advisory** badge and the plain-English
interpretation under the raw sentence. Composer flow: type sentence →
read interpretation → confirm. Quick-add from coachable-moment cards
(P1) remains the primary on-ramp. Athlete iOS view: read-only list of
coach rules + self-authored rules, in the Coach tab.

## Persona and sequencing note

This reframing is explicitly a **coach-dyad bet** — it makes the coach
the primary author and reopens coach-portal work that the May roadmap
deprioritized. Mitigations: the same machinery serves Maya
self-authored (her rules about her own training), so Phase A can still
ship athlete-first if the dyad decision stays open; and the portal
footprint stays at two screens. This PRD is evidence *for* resolving
the open dyad-vs-Maya wedge call — if pilot coaches adopt rules and
approve proposals unedited, the dyad wedge has its differentiator.

## Phasing

- **Phase A — parse + enforce in proposals.** Table, parser +
  confirmation loop, enforcement inside reschedule/adjustments,
  blocked-proposal escalation. Smallest thing a pilot coach can feel.
- **Phase B — plan validation + doctrine in advice.** Import/publish
  checks; Daily Read / readiness reasoning from doctrine; voice rules.
- **Phase C — roster defaults, templates, evaluator thresholds.**

Dependency: eval-harness coverage (Maya roadmap Phase 1) — the parser
prompt and every doctrine-aware prompt version are CI-gated on
cassettes.

## Open questions

1. **Taxonomy completeness** (product+coaching, blocking): interview
   3–5 coaches; what fraction of their real doctrine fits the seven
   constraint types? Target ≥70% before building the parser.
2. **Parser accuracy bar** (engineering, blocking): what
   misinterpretation rate is tolerable given confirm-before-enforce
   catches errors? Proposal: optimize for honest "can't enforce this"
   over confident wrong parses.
3. **Roster vs. athlete precedence** (product, non-blocking):
   athlete-specific overrides roster default — any exceptions?
4. **Does Maya get enforcement or advice-only in Phase A?**
   (product, non-blocking): self-authored rules constraining her own
   reschedules seems right, but validate that self-imposed hard rules
   don't just get overridden into noise.

## Prior art in this codebase

- `reschedule-plan` — the constrained-selection precedent this
  generalizes (closed library, no auto-apply, rate-limited).
- `_shared/rules/` evaluators — the mechanical-check pattern plan
  validation reuses.
- `plan_adjustments` ledger — where enforced proposals already land,
  `auto_applied: false`.
- Draft v1 of this PRD — the voice-rules design, carried as P1.
- `docs/coaching/principles.md` — the guardrails every prompt-side
  injection defers to.

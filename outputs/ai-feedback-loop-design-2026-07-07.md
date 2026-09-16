# AI Feedback Loop — design spec

**Date:** 2026-07-07
**Status:** Design approved for spec; no code yet. Phasing in §10.
**Decision inputs:** athlete-first learning (both athlete + coach signals, athlete drives); structured preference profile (typed fields, not free-text memory); design-only deliverable.
**Companion:** `ai-feedback-loop-codebase-exploration-2026-07-07.md` (what already exists, verified file paths).

---

## 0. Summary

The product already *captures* feedback in five places and already *injects* per-athlete
context into every prompt via `athlete_state`. What's missing is the middle of the loop:
nothing consumes the feedback, distills it into an explicit, auditable picture of *how this
athlete likes to be coached*, and feeds that picture back into the prompts. This spec adds
that middle piece — the **AI Coaching Profile** — plus the coach's steering wheel on top
of it.

```
  SIGNALS (exist today, mostly unconsumed)          THE NEW MIDDLE                 OUTPUT (exists today)
  ─────────────────────────────────────────         ──────────────────────         ─────────────────────
  thumbs on advice (coaching_feedback)      ─┐
  advice followed? (coaching_adjustments)    ├──►  derivation rules          ┌──►  Daily Read
  per-workout quick-take (§R7, ship in F1)   │     (pure fns, weekly cron)   │     Coaching agent chat
  memos → memories (user_memories, live)    ─┤            │                  │     Workout insights
  plan-move ledger (plan_adjustments)        │            ▼                  │
  coach corrections + directives (new, F3)  ─┘     athlete_ai_profile   ─────┘
                                                   (typed, evidence-backed,
                                                    athlete-visible,
                                                    coach-overridable)
```

One sentence: **feedback becomes a typed profile; the profile becomes ~80 tokens of prompt
context; the athlete can see and edit it; the coach can override it; every change carries
its evidence.**

## 1. Principles

1. **AI advises, never acts** (product core principle). The loop tunes *voice, format, and
   emphasis* of AI output. It never changes training prescription, never interprets
   injuries, never touches safety guardrails. A profile can make the Read shorter; it can
   never make the Read skip an active niggle.
2. **Athlete-first, coach-override.** Maya's signals drive derivation. When a coach
   exists, coach-set values win over athlete-set, which win over derived. Precedence is
   absolute and visible.
3. **Structured, not vibes.** Every learnable preference is a typed field with a closed
   vocabulary and a CHECK constraint. No free-text "personality summary" the AI maintains
   about the athlete. (The existing `user_memories` system already covers facts and
   episodes; this profile covers *coaching style*, a different axis.)
4. **Every derived value carries evidence.** A field never changes without an append-only
   event row recording which signals caused it, with what confidence. If Maya asks "why
   did the Read get shorter?", the answer exists in one query.
5. **Nothing personalizes silently.** The profile is visible in Model of You (same
   precedent as memories: visibility + control shipped *with* the feature, not after).
   Derived changes surface as a gentle notice, and any field can be pinned or reset.
6. **Deterministic first, LLM last.** Derivation starts as pure-function rules (the
   `_shared/rules/` pattern — testable, cheap, explainable). LLM-based distillation is a
   Phase 4 option only if rules prove insufficient, and it goes through the eval gate.

## 2. What exists — build on, don't duplicate

Verified in the main tree 2026-07-07 (details + paths in the companion exploration doc):

| Piece | State | Role in the loop |
|---|---|---|
| `coaching_feedback` (thumbs ±1 + text on coaching messages, `20260318100000`) | Live, **unconsumed downstream** | Signal S1 |
| `coaching_adjustments` (suggestion → followed? → outcome, same migration) | Schema live, outcomes never computed | Signal S2 (F4) |
| `scheduled_workouts.athlete_feedback` (RPE + feel chip + comment) | Spec'd in `adaptive-coach-plan-builder-spec-2026-07-03.md` §R7, migration not applied | Signal S3 — **F1 ships it** |
| `user_memories` + memoryWriter/Consolidation/Selection + Model of You | Live (2026-07-02 plan, steps 0–7) | Signal S4 + the pattern to copy (dedup, consolidation cron, athlete control) |
| `plan_adjustments` ledger incl. `user_action` + `coach_rewrite` + reason codes | Live (`20260703120000`) | Signal S5 |
| `athlete_state` + `stateToPromptContext()` (~400-token bounded context) | Live, 12 consumer functions | The injection point |
| `prompt-library.ts` + versioned prompts (`daily-read.v5`, `coaching-agent-*`, `generate-workout-insight.v5`) | Live | The output surfaces |
| Eval harness + CI cassette gate | Live, coverage partial | Ships with every prompt bump (hard rule #3) |
| Coach portal athlete detail page (moments + adjustments feed, note composer) | Live | Home for the coach steering surface (F3) |

The gap, precisely: **no analysis consumes S1–S5; preferences about coaching style have
nowhere typed to live; coaches have no way to steer AI voice per athlete.**

## 3. Signal taxonomy

| # | Signal | Source | Trust | Notes |
|---|---|---|---|---|
| S1 | Thumbs ±1 + optional text on a coaching message | `coaching_feedback` | High when text present; medium alone | Snapshot of message content is stored — rules can correlate reaction with message *properties* (length, data density, question count) |
| S2 | Suggestion followed / not + outcome | `coaching_adjustments` | Medium; `followed` is honest, outcome attribution is noisy | Deferred to F4 — outcome inference is the easiest place to fool ourselves |
| S3 | Per-workout quick-take: RPE + `nailed_it / solid / struggled / cut_short` + comment | `scheduled_workouts.athlete_feedback` (§R7) | High — lowest-friction, highest-frequency signal | Mostly feeds *coach* surfaces per §R7; profile derivation uses only its meta-patterns (e.g., athlete always comments → likes dialogue) |
| S4 | Memo language | `user_memories` (category `preference`) | High — athlete's own words | Already extracted. Rules read `preference` memories mentioning coaching style ("don't sugarcoat it", "I like seeing the splits") |
| S5 | Plan-move ledger | `plan_adjustments` | High for facts, low for style inference | Used sparingly: e.g., athlete repeatedly moves quality days → scheduling preference, which belongs in `athlete_plan_subscriptions`, **not** this profile — route it there |
| S6 | Coach corrections | Coach edits to AI-assisted rewrites (§R5 diff), coach profile overrides, coach directives | Highest weight | New in F3 |
| S7 | Implicit engagement (Read generated but never scrolled, lens queries asked) | app analytics | Low | Explicitly out of scope for derivation — too easy to over-read. Revisit post-beta. |

**A rule about rules:** signals about *training* (struggled on quality days, load spikes)
belong to the existing coachable-moments / coach pipeline. This loop only learns
*communication preferences*. The same S3 chip can feed both — but through different pipes
with different consequences.

## 4. The AI Coaching Profile

### 4.1 Table: `athlete_ai_profile`

One row per athlete. Typed columns, closed vocabularies, conservative defaults matching
the current Coach voice posture (feeling first, warm, two soft questions).

| Column | Type / CHECK | Default | What it tunes |
|---|---|---|---|
| `user_id` | TEXT PK, = `auth.uid()::text` | — | |
| `detail_level` | `brief \| standard \| deep` | `standard` | Read length, insight length |
| `data_appetite` | `feelings_first \| balanced \| numbers_forward` | `feelings_first` | Whether numbers lead or support |
| `encouragement` | `warm \| matter_of_fact` | `warm` | Register. Note: `matter_of_fact` is still kind — "toxic positivity off" is the athlete request this encodes |
| `question_appetite` | `0 \| 1 \| 2` (SMALLINT) | `2` | Soft questions at the end of a Read |
| `episode_callbacks` | BOOLEAN | `true` | "Remember Jan 14, the day it clicked" references |
| `year_ago_arc` | BOOLEAN | `true` | The year-ago comparison line |
| `topic_sensitivities` | TEXT[] closed vocab: `pace_comparisons \| missed_workouts \| race_countdown \| body_composition` | `{}` | Topics to handle with extra care (not silence — see §9) |
| `niggle_acknowledgment` | `always \| when_new` | `always` | The floor is `when_new`. There is deliberately **no `off`** |
| `field_sources` | JSONB — map field → `{source: derived\|athlete\|coach, confidence, updated_at}` | `{}` | Per-field provenance for display + precedence |
| `created_at` / `updated_at` | TIMESTAMPTZ | now() | |

RLS in the same migration (hard rule #1): athlete SELECT own row; athlete UPDATE own row
**via edge function only** for athlete-set fields; coach SELECT/UPDATE via
`current_coach_id()` helper (hard rule #6); derived writes are service-role only.

### 4.2 Table: `athlete_ai_profile_events` (append-only audit)

| Column | Type | Notes |
|---|---|---|
| `id` | UUID PK | |
| `user_id` | TEXT | |
| `field` | TEXT | e.g. `detail_level` |
| `old_value` / `new_value` | TEXT | |
| `source` | `derived \| athlete \| coach \| reset` | |
| `actor_id` | TEXT NULL | coach UUID or athlete uid; NULL for derived |
| `evidence` | JSONB | signal refs: `{rule: "read_length_fatigue", coaching_feedback_ids: [...], window: "28d", signal_count: 4}` |
| `confidence` | `low \| medium \| high` | derived rows only |
| `created_at` | TIMESTAMPTZ | |

This is the "why did the AI change on me?" answer, and the debugging surface when a
derivation rule misfires. Never deleted; RLS: athlete + their coach can SELECT.

### 4.3 Table: `coach_directives` (F3)

Time-boxed structured steering — the coach's "for the next two weeks, ease off" without
editing prompts or profiles field-by-field.

| Column | Type | Notes |
|---|---|---|
| `id` | UUID PK | |
| `athlete_user_id` / `coach_id` | TEXT / UUID | |
| `directive_code` | closed vocab: `emphasize_recovery \| back_off_intensity_talk \| confidence_building \| hold_steady_no_changes \| race_week_protocol \| celebrate_consistency` | The AI acts on the **code**, not free text |
| `note` | TEXT ≤ 200 chars, NULLable | Human phrasing. **Athlete-visible** and quoted in prompt as coach context ("your coach says: …") — quoted, never obeyed as instruction. See open question Q1 |
| `starts_on` / `expires_on` | DATE | `expires_on` required, max 28 days out. Directives decay by design; standing preferences belong in profile fields |
| `status` | `active \| expired \| revoked` | |

RLS: coach full CRUD on own athletes via `current_coach_id()`; athlete SELECT (they see
what's steering their AI — principle 5).

**Why both profile-overrides and directives?** Overrides are *standing* ("this athlete
always wants brevity"); directives are *situational* ("post-injury fortnight, keep it
gentle"). Collapsing them into one mechanism makes coaches choose between permanence and
expressiveness — bad trade both ways.

## 5. Derivation pipeline

### 5.1 Rules

Pure functions in `supabase/functions/_shared/profile-rules/`, registered in an
`index.ts` — deliberately the same shape as `_shared/rules/` so the pattern is already
familiar and already testable. Each rule: `(signals: SignalWindow) → ProfileProposal[]`
where a proposal is `{field, value, confidence, evidence}`.

Launch set (small on purpose — four rules, each falsifiable):

| Rule | Reads | Proposes | Trigger sketch |
|---|---|---|---|
| `read_length_fatigue` | S1 + message snapshots | `detail_level: brief` | ≥3 thumbs-down in 28d on messages in the top length quartile, OR any feedback_text matching too-long language. Reverse rule (`deep`) requires explicit text ("more detail"), never inferred from thumbs-up alone |
| `numbers_appetite` | S4 + S1 text | `data_appetite` | ≥2 `preference` memories or feedback texts asking for splits/paces/data → `numbers_forward`; explicit "stop with the numbers" → `feelings_first` |
| `question_fatigue` | S1 + snapshots | `question_appetite: 1` | thumbs-down concentrated (≥3 in 28d) on Reads containing 2 questions, or explicit text |
| `callback_comfort` | Model of You deletions + S1 | `episode_callbacks: false` | Athlete deletes ≥2 `episode` memories, or any negative feedback on a Read containing an episode callback. **Single strong signal suffices** — feeling surveilled is the one place we react fast and re-enable slowly |

### 5.2 Cadence + hysteresis

- Runs weekly, appended to the existing Sunday 04:30 UTC consolidation window as a
  `derive-ai-profile` edge function + pg_cron entry (reuse the `consolidate-memories`
  deployment pattern; new cron ships via migration per hard rule #9's push discipline).
- **Hysteresis:** max one derived change per field per run; a change needs signals from
  ≥2 distinct weeks unless the rule explicitly says otherwise (`callback_comfort`);
  reverting a derived change requires the *opposite* evidence, not mere absence.
- **Precedence:** a field whose `field_sources` entry says `athlete` or `coach` is
  skipped by derivation entirely (proposals for it are logged to events as
  `suppressed_by_precedence` evidence, value unchanged — useful signal for the coach card).
- **data_depth gate:** derivation runs only at `data_depth ≥ 2`. Below that, defaults
  apply and athlete-set values are honored. No first-week whiplash.

### 5.3 What derivation must never do

Propose values for `niggle_acknowledgment` below its floor; touch anything outside the
profile table; infer from mood (a tired athlete is not asking for a different coach —
mood is state, not preference); infer from S7 engagement analytics.

## 6. Prompt injection

New builder in `athlete-state.ts` (slots into the existing builder list):
`buildCoachingProfile()` → reads `athlete_ai_profile` + active `coach_directives` →
renders a bounded block (~80 tokens, accounted inside the existing ~400-token
`stateToPromptContext()` budget — trimmed from the memories quota if tight, profile wins
over the 12th memory).

Rendered shape (illustrative):

```
How they like to be coached: keep it brief; lead with the numbers; one question max.
Coach directive through Jul 21 — emphasize recovery. Coach's words: "ease her back
in after the calf niggle."
(These tune voice and emphasis only. Safety content — niggles, range-based
predictions — always appears regardless.)
```

Consumer prompts bump versions: `daily-read.v6`, `coaching-agent-*.v2`,
`generate-workout-insight.v6`, each adding a `{{coaching_profile}}` placeholder
(strict substitution will enforce it's provided). Hard rule #3 applies: **each bump ships
with cassettes before the prompt lands** — see §11.

`process-training-memo` and the parsers do **not** get the profile — extraction prompts
must stay preference-neutral (a "brief" profile must never cause the extractor to extract
less).

## 7. Coach guidance layer (F3)

One new card on the coach portal athlete detail page — **"AI Coaching Profile"** —
sitting alongside the existing coachable-moments card and adjustments feed:

- **Read:** current value of every field, its source badge (derived / athlete / coach),
  confidence, and a "why" expander backed by `athlete_ai_profile_events`.
- **Override:** coach sets any field → writes `field_sources[field] = coach`, event row
  with `actor_id`. One tap to release an override back to derived/athlete.
- **Directives:** create / revoke, with the closed vocabulary as chips + optional note.
  Active directive shows its countdown.
- **Correction signal (S6):** when the §R5 assisted-rewrite flow ships, coach edits to
  AI-proposed blocks get diffed; systematic patterns (coach always deletes the AI's
  intensity commentary) surface on this card as *suggested* overrides — suggested, never
  auto-applied, consistent with "AI advises, never acts" applying to coaches too.

Self-coached Maya (`coach_id` null): this card simply doesn't exist anywhere; her
steering surface is Model of You (§8). Nothing in the schema requires a coach.

## 8. Athlete control — Model of You

Extends the existing surface (`RunningLog/Coaching/ModelOfYou/`), same interaction
grammar as memories:

- New section **"How I coach you"** listing each field in plain language ("I keep things
  brief — you asked for this" / "— I noticed this from your reactions").
- Athlete can change any field (writes `source: athlete`, wins over derived), reset a
  field to "let it learn", and see active coach directives (read-only, with the coach's
  note).
- When derivation changes a field, the next Model of You visit shows a one-line notice
  with the plain-language why. No push notification — this is a quiet system.

Ships in **F1**, before any derivation exists — the editor comes first, the learning
second. This mirrors the memory precedent (visibility + delete shipped with extraction)
and means F1 alone already delivers value: explicit athlete preferences, honored
immediately.

## 9. Guardrails + hard-rule compliance

| Concern | Position |
|---|---|
| Medical safety (hard rule #2) | Profile cannot suppress niggle acknowledgment (floor `when_new`, no `off`), cannot alter the closed niggle vocabulary, and the injected block explicitly tells the model safety content is non-negotiable. Adversarial cassettes verify (§11) |
| Prediction honesty (hard rule #7) | Range + confidence framing is not a profile field. `numbers_forward` changes *prominence* of numbers, never *precision* |
| RLS (hard rule #1) | All three tables ship RLS in their migrations; coach access via `current_coach_id()` (hard rule #6); derived writes + athlete-field updates go through service-role edge functions |
| Eval gate (hard rule #3) | Cassettes authored before any prompt version bump; CI gate enforces |
| Migrations (hard rules #5, #9) | Append-only; prod only via `supabase db push` from committed SHA |
| Voice posture | Defaults are the current posture. The profile lets athletes move *away* from defaults, so an untouched profile changes nothing — safe to ship dark |
| `topic_sensitivities` semantics | Sensitivity means *handled with care and athlete's framing*, not omitted. A sensitive `missed_workouts` still appears in compliance math and coach surfaces; the Read just doesn't lead with it or moralize it |
| Scope creep | Scheduling preferences → `athlete_plan_subscriptions`. Facts/episodes → `user_memories`. Training-pattern alarms → coachable moments. This profile is *only* communication style. When in doubt, it goes elsewhere |

## 10. Phasing

**F1 — Capture + explicit preferences** (the beta-worthy slice)
Ship the §R7 per-workout feedback migration (already spec'd); `athlete_ai_profile` +
`athlete_ai_profile_events` migrations with RLS; profile edge function (read/update);
Model of You "How I coach you" section; `buildCoachingProfile()` + injection into
`daily-read.v6` and `generate-workout-insight.v6` with cassettes.
*Value delivered: athletes can tell the AI how to talk to them, and it listens.*

**F2 — Derivation**
`_shared/profile-rules/` (4 launch rules + tests, mirroring `_shared/rules/` structure);
`derive-ai-profile` function + Sunday cron migration; hysteresis + precedence +
data_depth gate; derived-change notices in Model of You.
*Value: the AI starts learning without being told.*

**F3 — Coach layer**
`coach_directives` migration; portal "AI Coaching Profile" card (view/override/directives);
directive rendering in prompt block; S6 correction-signal surfacing once §R5 assisted
rewrites exist.
*Value: a coach can steer the AI per athlete in under a minute.*

**F4 — Outcome-aware (post-beta, evidence-gated)**
Compute `coaching_adjustments.outcome_metrics`; per-athlete coachable-moment rule muting
(coach mutes a rule for an athlete — structured, reversible); evaluate whether an
LLM-distillation pass adds anything the rules miss. Enter F4 only if F2's rules show
measurable lift (thumbs-up ratio, feedback text sentiment) — otherwise stop; four good
rules beat one clever model.

Each phase is independently shippable and independently reversible (feature-flag the
injection block; an empty profile renders nothing).

## 11. Eval plan

New cassette dirs before the corresponding prompt lands:

- `daily-read.v6/`: (a) `brief` profile → Read is materially shorter, all sections
  survive; (b) `numbers_forward` → numbers lead, feelings still present; (c)
  **adversarial:** profile JSON tampered to include `"hide_niggles": true` → niggle still
  acknowledged; (d) directive `emphasize_recovery` active → recovery framing present,
  no training prescription appears; (e) `question_appetite: 0` → no trailing questions,
  no orphaned question scaffolding.
- `generate-workout-insight.v6/`: brief + numbers_forward variants; adversarial
  prediction-precision case (profile can't produce a seconds-precision projection).
- `coaching-agent-*.v2/`: one profile-respecting case per complexity tier.
- Rubric primitives already exist; recording at deploy time with `GEMINI_API_KEY`, per
  the standing harness workflow. Manual review against `docs/coaching/principles.md`
  until cassette coverage on these prompts is complete.

Beyond LLM evals: unit tests for every profile rule (the pure-function shape makes this
cheap), precedence tests (coach > athlete > derived), and hysteresis tests (single noisy
week changes nothing).

## 12. Open questions

- **Q1 — directive `note` in the prompt.** Quoted verbatim ("your coach says: …") is
  transparent but is a free-text channel into the prompt from a semi-trusted role.
  Alternatives: code-only in prompt with note shown only to humans, or a closed set of
  note templates. Leaning verbatim-with-quoting + prompt-injection cassette; decide in F3.
- **Q2 — thumbs UI reach.** `coaching_feedback` exists for coaching chat messages; the
  Daily Read itself has no reaction affordance in iOS today. F1 should probably add a
  minimal one (the Read is the main output — see exploration doc §1). Needs a design pass
  against the editorial layout; a thumbs row under the Read plate is off-voice, a small
  "was this read useful?" ghost row may not be. Park for the next design session.
- **Q3 — event retention.** Events are append-only and low-volume (≤ a few rows/athlete/
  week). Proposal: keep forever; revisit if storage ever matters.
- **Q4 — does `encouragement: matter_of_fact` conflict with the "warm encouragement"
  voice pillar?** Position taken here: warmth is the default and the floor is "kind";
  `matter_of_fact` drops cheerleading, not kindness. Worth a voice-guide addendum in
  `design-system/README.md` when F1 ships.

## 13. Doc trail

- This spec: `outputs/ai-feedback-loop-design-2026-07-07.md`
- **Addendum (2026-07-07):** `ai-feedback-loop-athlete-signature-addendum-2026-07-07.md`
  — the Athlete Signature layer: open-ended algorithmic discovery of individual training
  patterns (evidence-backed observations mined from the athlete's own history), on top of
  the style profile defined here. Read together.
- Codebase grounding: `outputs/ai-feedback-loop-codebase-exploration-2026-07-07.md` +
  `outputs/feedback-tables-quick-reference-2026-07-07.md`
- Upstream decisions honored: `adaptive-coach-plan-builder-spec-2026-07-03.md` (§R5/§R7),
  `long-term-memory-implementation-plan-2026-07-02.md` (memory + Model of You precedent),
  `maya-data-aware-journey-2026-05-28.md` (Coach voice posture),
  `maya-product-roadmap-2026-05-28.md` (Phase 6 memory architecture — F2 here is a
  concrete slice of it).

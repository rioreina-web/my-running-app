# The Read — conversational Q&A

**Feature spec + design handoff**
Author: design session · 2026-07-02
Status: proposed (concept validated via prototype)
Related: `outputs/maya-data-aware-journey-2026-05-28.md`,
`outputs/maya-product-roadmap-2026-05-28.md`, `docs/coaching/principles.md`

---

## 1. Summary

Today **The Read** (the Coach tab, `CoachTabView.swift`) is a one-way
surface: Maya taps generate, the AI produces an editorial paragraph, and the
conversation ends there. This spec turns it into a **two-way conversation** —
Maya can reply to the Read's soft question, tap suggested prompts, or type her
own question, and Coach answers in-voice, grounded in her training data.

This is an extension of the existing vision, not a departure. The journey doc
already states *"Maya can ask Coach to read her journey through specific
lenses"* — this spec makes that concrete. It borrows the chat pattern that
already exists in the design system's `CoachScreen.jsx` (built for the
coach-athlete dyad) and repurposes it for the AI Read.

**Prototypes:** `outputs/the-read-chat-mockup.html` (static, keyword replies)
and `outputs/the-read-chat-artifact.html` (live, real inference). The live
artifact is the reference for intended behavior.

---

## 2. Goals / Non-goals

### Goals

- Let Maya respond to the Read and ask follow-up questions in natural language.
- Answer concrete training questions from her real data ("what's my tempo
  pace?", "how's my fitness trending?").
- Keep the Read's editorial calm — the conversation extends the object, it
  doesn't turn the tab into a generic chatbot.
- Preserve every existing Coach guardrail (observe-not-prescribe, range +
  confidence, no medical claims).

### Non-goals

- **Not** a replacement for the coach-athlete messaging surface (that's the
  dyad's `CoachScreen`; deprioritized per 2026-05-28).
- **Not** a plan-authoring or workout-generating tool. Coach advises; it never
  writes or mutates the plan from chat.
- **Not** a nutrition, medical, or injury-diagnosis product. Out-of-scope
  questions get a light, honest, non-prescriptive answer.
- No always-on push/daily auto-send. The Read stays on-demand.

---

## 3. User experience

### 3.1 Entry

The Read renders as it does today: eyebrow-sectioned editorial paragraph
ending in a coral-barred **soft question**. Below the byline, a new section
opens the conversation:

```
──────────  ASK COACH  ──────────

[ suggested-reply chips ]
[ text input · send ]
```

The soft question at the end of the Read is the natural hook — the first
suggested chips answer it directly.

### 3.2 Suggested chips (quick replies)

Two kinds, generated per-Read:

1. **Answer-the-question chips** — direct responses to the Read's soft
   question (e.g. "It's the heat, mostly" / "Feels deeper than the heat").
2. **Lens chips** — reframes over her journey ("How does this compare to last
   cycle?", "What's my tempo pace?", "Why the 2:28–2:31 range?").

After each Coach reply, chips refresh to context-relevant follow-ups. Chips are
a tap shortcut; anything a chip does, free text can also do.

### 3.3 Free text

Open input. Enter or send submits. Maya can ask anything. Coach interprets and
answers, or gracefully redirects if out of scope.

### 3.4 Message thread

- **Maya's messages:** right-aligned white bubble (`prd-coach__msg-you` in the
  design system).
- **Coach's messages:** left coral-bar quote (`CoachQuote`), body + a soft
  question on its own italic line.
- Timestamps as mono eyebrows above each message.
- **Streaming:** Coach replies stream token-by-token with a typing indicator
  first (matches the artifact prototype).

### 3.5 Decision needed — inline vs. threaded

Two layouts, pick one before build (see Open Questions):

- **Inline (prototype default):** conversation appends below the Read in the
  same scroll. Keeps everything as one calm object.
- **Threaded:** replying opens a dedicated thread view. Feels more like a chat
  app, more room, but adds a navigation layer.

Recommendation: ship **inline** for v1 — it's truer to the editorial framing
and lower-lift.

---

## 4. Voice & content rules

Coach's replies are governed by `docs/coaching/principles.md` and the voice
posture in `maya-data-aware-journey-2026-05-28.md`. The prompt must enforce:

1. **Observe, never prescribe.** No "rest", "stop", "ice", "take a day off",
   no injury diagnosis. If Maya describes a niggle, Coach surfaces her own
   words and hands the decision back — it never names a condition or recommends
   treatment (mirrors the Niggles detection-not-diagnosis rule).
2. **No medical or nutrition prescriptions.** Out-of-scope questions get a
   light, useful, non-prescriptive answer that honestly flags it's outside what
   the training data shows.
3. **Predictions ship as range + confidence, never a single point.** "2:28–2:31,
   high confidence" — never "2:29:30". (Hard rule #7.)
4. **Feeling first, then data.** Warm, plain, encouraging but honest. Reads life
   context (heat, sleep, work). Carries goal + race anchor silently; states
   paces/facts without lecturing on the math.
5. **Length + shape.** 2–4 sentences, then one short soft question. Never a
   directive.
6. **Pace answers** pull the exact zone value and note the app's zone labels —
   "tempo"/"threshold" map to the **LT** zone (per the 10-zone taxonomy).

The full working prompt lives in the artifact prototype's `VOICE` string; that
is the starting draft for the production system prompt.

---

## 5. Data & backend

### 5.1 Context the model reads

Coach answers from the athlete's live state, assembled server-side from
`_shared/athlete-state.ts` (fitness range + confidence, pace zones from
PaceEngine, ACWR, recent runs, mood/niggle signal, goal + race anchor). The
prototype's mock `ATHLETE` object is the shape to replace with real state.

### 5.2 New table — `coach_conversations` (or messages)

Stores the thread so it persists across sessions.

- Ships with **RLS in the same migration** (Hard rule #1; follow
  `docs/conventions/rls-checklist.md`). Athlete-scoped: `user_id TEXT` matching
  `auth.uid()::text`.
- `TIMESTAMPTZ` columns. Append-only migration, `YYYYMMDDHHMMSS_` naming.
- Columns (draft): `id`, `user_id`, `read_id` (which Read it hangs off, nullable
  for standalone questions), `role` (`athlete` | `coach`), `body`, `soft_question`,
  `created_at`.

### 5.3 Edge function

New service-role edge function (e.g. `coach-read-chat`) following
`_shared/{auth,cors}.ts` patterns. It:

1. Loads athlete-state context for the requesting user.
2. Builds the prompt via `_shared/prompt-library.ts` (inline prompts are
   deprecated — new calls use the library).
3. Calls the LLM, streams the reply back.
4. Persists both turns to `coach_conversations`.

### 5.4 Eval coverage — blocking

Per Hard rule #3 and the CI gate (`.github/scripts/check_eval_coverage.py`), a
new prompt in `_shared/prompts/` **cannot ship** without a cassette under
`_evals/cassettes/coach-read-chat/`. Cassettes must cover: a pace question, a
fitness-trend question, a niggle mention (assert no diagnosis / no rest
prescription), an out-of-scope nutrition question (assert honest redirect), and
a prediction question (assert range + confidence, no point estimate).

---

## 6. States & gating

- **`data_depth` gating.** Editorial register follows the athlete's depth
  (0–3). At depth 0–1 the conversation exists but Coach stays plainer and cites
  numbers only when it has them. Full pull-quote voice at depth 2+.
- **Empty state.** Before any exchange, chips + input show with an inviting
  prompt. Never an em-dash placeholder (Hard rule #8) — use the empty-state
  pattern.
- **No recent mood.** The existing "haven't heard how you're feeling in over a
  week" card becomes an entry point: a chip or nudge inviting a voice memo.
- **Error / offline.** Graceful "give it another try" with a soft question, no
  raw errors.

---

## 7. Success metrics

- % of Reads that get at least one reply (engagement with the two-way surface).
- Follow-up depth (messages per conversation).
- Qualitative: does Coach stay in-voice? (spot-check against principles.md +
  eval rubric).
- Guardrail violations = 0 (no prescriptions, no point predictions, no
  diagnoses) — enforced by evals, verified in review.

---

## 8. Phasing

- **v0 — concept (done).** Prototypes built and validated.
- **v1 — inline chat, real data.** Table + RLS, edge function, prompt-library
  entry, eval cassettes, iOS inline thread in `CoachTabView`. Mock data
  replaced with live athlete-state.
- **v1.5 — lenses + mood hook.** Refined lens chips, voice-memo invitation from
  the no-mood card, streaming polish.
- **Later.** Threaded-view option if inline feels cramped; conversation history
  across Reads.

Sequencing note: this rides on top of the Coach Read work already in Maya's
roadmap; slot v1 alongside the Coach Read prompt work (roadmap Phase 1/eval
close-out).

---

## 9. Open questions

1. **Inline vs. threaded** layout (§3.5). Recommend inline for v1.
2. **Conversation persistence scope** — per-Read threads, or one rolling
   conversation? Affects the `read_id` column.
3. **Rate limiting** — do we cap questions/day like `reschedule-plan`? Likely
   yes, to bound cost.
4. **How much athlete-state to pass** — full state is large; may need a trimmed
   context builder to keep prompts lean.
5. **Does the coach-dyad case reuse this surface** when a human coach exists,
   or does Coach defer entirely? (Ties to the open dyad-vs-Maya call.)

---

## 10. Acceptance criteria

- [ ] Maya can reply to a Read via chip or free text and get an in-voice answer.
- [ ] "What's my tempo pace?" returns her LT-zone value with the zone-label note.
- [ ] Any fitness/race answer is a range + confidence; no point estimates.
- [ ] A niggle mention yields no diagnosis and no rest/stop prescription.
- [ ] An out-of-scope (e.g. nutrition) question gets an honest, non-prescriptive
      redirect.
- [ ] Conversation persists (table + RLS) and reloads correctly.
- [ ] Eval cassettes exist and pass for every prompt shipped; CI gate green.
- [ ] Empty, no-mood, and error states use the correct components (no em-dashes).

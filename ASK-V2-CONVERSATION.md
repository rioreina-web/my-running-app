# Ask v2 — the conversation

*Authored 2026-08-07. Extends `ASK-APPLY.md` (architecture) and
`ASK-REGISTRY.md` (the 50 analyzers).*

---

## 0 · What changes

Ask v1 is **stateless Q&A**: ask, compute, forget. Every turn starts cold.

Ask v2 is a **stateful, two-way conversation**: it reads the qualitative side
as well as the quantitative, it remembers what it already told you, and what
you say back can change your record.

Same three-layer engine underneath. Four new pieces on top:

| # | Piece | Why |
|---|---|---|
| 1 | **Qualitative retrieval** | Ask cannot currently read a single voice memo. |
| 2 | **Conversation state** | So it stops repeating itself. |
| 3 | **Surfaced watermark** | The niggle-hammering fix. |
| 4 | **Propose → confirm → write** | Corrections, without the AI inferring them. |

---

## 1 · Qualitative retrieval — the missing half

Every Phase A analyzer reads numbers. None reads what the athlete *said*.
That's backwards for a product whose thesis is the fusion of the two.

**New analyzer group: `voice`.** Same contract as every other analyzer —
deterministic retrieval, fact lines out, narration on top. What's different is
that its "facts" are **verbatim quotes**, not computed numbers.

| Analyzer | Question | Source |
|---|---|---|
| `what_i_said` | What have I been saying about this block? | `training_logs.cleaned_notes` over the window |
| `mood_arc` | How has my mood actually read? | `training_logs.mood` + `daily_checkins.mood` |
| `session_notes` | What did I say about this session? | `cleaned_notes` + `rpe_pull_quote` for one log |
| `theme_scan` | What keeps coming up? | Recurring terms across `cleaned_notes` |

**The quoting rule is the same discipline as the number guard.** A quote is a
fact line. The model may reproduce a quote verbatim or not at all — it may
never paraphrase one into something the athlete didn't say. Extend
`narration-guard.ts` with a `quotedTextAllowed()` check alongside
`allowedNumberTokens()`: same wholesale rejection, same degradation.

That check is the load-bearing new safety property in v2. Numbers were the
only fabrication risk in v1; in v2, putting words in the athlete's mouth is
the worse one.

**Fusion is a composite analyzer, not a prompt instruction.** `zone_trend`
answers "is my LT improving." `what_i_said` answers "what did I say about it."
A composite (`block_read`) runs both and hands Layer 2 both fact sets, so the
narration can say *"the pace came down 9 seconds and you called three of those
sessions 'controlled'"* — with both halves independently auditable.

---

## 2 · Conversation state

New table `ask_threads` + `ask_turns`, or reuse the `conversations` /
`conversation_messages` pair (2 and 4 rows respectively — effectively unused,
and two competing shapes already; **pick one and delete the other** rather
than adding a third).

Each turn stores: question, analyzer id, fact lines, narration, and — the new
part — **what was surfaced**. That last field is what feeds §3.

Layer 2's prompt gains one block: *"You have already told this athlete: …"*
with the last few surfaced claims. Not the whole history — the *claims*.

---

## 3 · The surfaced watermark — the niggle fix

**Why it repeats today.** `athlete_state.niggle_recurrence` is injected into
the prompt on every call. The model sees `left knee · 3 mentions` in its
context every single turn and dutifully raises it every single turn. It isn't
being dumb; it's being handed the same flashcard forever.

**Why prompt-tuning won't hold.** "Don't be repetitive" is a instruction the
model obeys for a few turns and then drifts off. The information is still
there, and anything in context eventually gets said.

**The fix is state, not language.** A `surfaced_at` watermark per (athlete,
body_area, side) — the same shape as the `niggle_resolutions` watermark that
already ships, different trigger:

> A niggle enters the prompt context only if it has **never been surfaced**,
> or something has **changed since** it was: a new body area, escalated
> severity language, or a fresh mention after ≥ N days of silence.
> Otherwise it is withheld from context entirely.

Withheld from *context*, not merely unmentioned — if it isn't in the prompt,
it cannot be repeated. That's the whole trick.

**It stays answerable on demand.** The `body` chip group still queries it
directly, so "where has the calf shown up" always works. The watermark
governs what Ask *volunteers*, never what it will *answer*.

Same principle applies to mood and to any standing observation. Generalize
the table: `ask_surfaced (user_id, subject_kind, subject_key, surfaced_at,
last_signature)` where `last_signature` is what "changed" compares against.

---

## 4 · Corrections — propose, confirm, write

**Decision (Rio, 2026-08-07): propose then one tap.** The chat never writes
on inference alone.

```
athlete: "my knee is feeling good now"
    ↓  Layer 0 · intent detection (closed action enum, same as the analyzer enum)
    ↓  proposed_action: { kind: "resolve_niggle", body_area: "knee", side: "left" }
    ↓  rendered as a chip:  [ Mark left knee resolved ]
    ↓  athlete taps
    ↓  POST resolve-niggle   ← the endpoint that ALREADY EXISTS
    ↓  confirmation line + undo
```

**Everything on the write path already ships.** `resolve-niggle` validates
against the closed body vocabulary, writes an athlete-owned watermark to
`niggle_resolutions`, and athlete-state drops that niggle from active analysis
until a genuinely new mention lands after that date. `process-training-memo`
already does the same from a voice memo via `resolved_niggles`.

**Ask v2 adds no new write capability.** It adds a new *doorway* to writes the
athlete can already make. That is what keeps this inside "AI advises, never
acts" — the AI proposes, the athlete acts, and the executing endpoint is the
same one the button calls.

### The action enum (v1)

| Action | Endpoint | Confirm |
|---|---|---|
| `resolve_niggle` | `resolve-niggle` (exists) | Yes — feeds injury-risk detection |
| `set_mood` | `daily_checkins.mood` upsert | Yes, but a soft one |
| `log_niggle` | `body_mentions` insert via service role | Yes |
| `correct_workout_type` | `edit-scheduled-workout` (exists) | Yes |

Anything not in this enum is not an action. The model cannot invent one, the
same way it cannot invent an analyzer.

### The rule that makes it safe

**Only an explicit, first-person, present-tense claim proposes an action.**

- *"my knee is feeling good"* → propose. Direct claim about current state.
- *"I didn't think about my knee once"* → **no proposal.** Absence of
  complaint is not an all-clear, and this is exactly the inference that would
  silently drop a real niggle out of injury-risk analysis.
- *"knee was sore Tuesday"* → propose `log_niggle`, not `resolve_niggle`.

When it's ambiguous, ask rather than propose. A question costs a turn; a
wrong write costs trust and corrupts the injury signal.

---

## 5 · Phasing

| Phase | Ships | Why here |
|---|---|---|
| **A** | The surfaced watermark (§3) | Smallest piece, fixes the loudest complaint, server-side only, zero client work. Ship it alone and the existing Daily Read gets better too. |
| **B** | `voice` analyzer group + `quotedTextAllowed` guard | The missing half. Read-only, so no new risk surface. |
| **C** | Conversation state + the "already told you" prompt block | Turns four answers into a conversation. |
| **D** | Intent detection + propose/confirm + the action enum | The write path. Last, because it's the only part that can do harm. |

**Do not reorder D earlier.** It is the only phase with a failure mode worse
than a bad answer.

---

## 6 · Open

1. `conversations` vs `conversation_messages` — two half-built shapes. Pick
   one, delete the other, before adding thread state to either.
2. How long is the silence before a niggle may resurface unprompted? 14 days
   is a guess; `body_mentions.mentioned_at` history can answer it properly.
3. Does the Daily Read read the same surfaced watermark? It should — the
   repetition complaint applies there too, and it's the same table.

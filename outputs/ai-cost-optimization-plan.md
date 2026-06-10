# AI cost optimization — keep model quality, kill context cost

Companion to `outputs/tech-debt-audit-2026-05.md` and
`outputs/security-and-scale-1000-users.md`. Date: 2026-05-12.

## TL;DR

The codebase has surprisingly good bones for cost control — a model
router (`_shared/router.ts`) that tiers Groq Llama 8B / Gemini Flash /
Gemini Flash-with-headroom by query complexity, a context compressor
(`_shared/context.ts`, 689 LOC) that already cuts training-log dumps
90%, a deterministic athlete-state DCO (`_shared/athlete-state.ts`,
1,575 LOC) that precomputes derived metrics, and a versioned prompt
library (`_shared/prompts/*.v1.ts`).

What's leaking money:

1. **`coaching-agent` packs 14+ context blocks unconditionally** into
   moderate/complex prompts. The compressor exists but isn't used here.
2. **No prompt caching anywhere.** Both Gemini and Anthropic offer
   prompt-prefix caching at ~10% of normal input cost; the stable
   per-user prefix (system prompt + athlete profile + memories) is
   prime for it.
3. **Four LLM-using edge functions are cuts that never got deleted**:
   `form-check-analysis` (560 LOC), `biomechanics-analysis` (290),
   `custom-plan-builder` (640), `adaptive-workout` (38). Dead code
   still wired to billable APIs.
4. **JSON mode is used in 8 functions, missing from `injury-analysis`,
   `coaching-agent` (where applicable), `race-intel`, and others** —
   so the prompts pay tokens explaining "respond in this format."
5. **Conversation history at 50 raw messages**. Most coach chats fit
   in 5–7 turns; the other 43 are paying for nothing.
6. **`gemini-2.5-pro` use is mostly justified, but `training-analysis`
   is the question mark** — second-largest edge function at 1,535 LOC
   and unclear it needs Pro-level reasoning.
7. **No deterministic-first / LLM-last split on weekly reports.**
   `weekly-coaching-report` generates the whole narrative through
   Flash when 80% of it is "this athlete ran X miles, Y workouts,
   ACWR Z" — pure facts that don't need a model.

The fix is a ladder: cheapest first, biggest impact at the bottom.
Implemented end-to-end, this drops the LLM bill at 1,000 users from
roughly **$60/mo → $15–25/mo** *without* dropping a model tier on any
prompt that needs the smarts.

---

## Today's spend, modeled

Assumptions: 1,000 DAU, ~60% daily-active, average 1 run + 4 voice
logs + 2 coach-chat sessions/week per active user.

| Surface | Calls/day | Avg input tok | Avg output tok | Model | Cost/day | Cost/mo |
|---|---|---|---|---|---|---|
| `generate-workout-insight` | ~860 | 2,500 | 250 | Flash 2.5 | $1.45 | $44 |
| `process-training-memo` (voice) | ~340 | 4,000 | 400 | Flash 2.5 | $0.90 | $27 |
| `coaching-agent` moderate/complex | ~700 | 8,000 | 600 | Flash 2.5 | $3.62 | $109 |
| `coaching-agent` simple | ~300 | 1,500 | 200 | Groq Llama | $0.03 | $1 |
| `weekly-coaching-report` | ~150 | 6,000 | 800 | Flash 2.5 | $0.61 | $18 |
| `injury-analysis` | ~100 | 3,000 | 400 | Flash 2.5 | $0.20 | $6 |
| `evaluate-coachable-moment` | ~860 | 1,500 | 200 | Flash 2.5 | $0.88 | $26 |
| `generate-training-plan` (Pro) | ~30 | 12,000 | 4,000 | Pro 2.5 | $1.20 | $36 |
| `training-analysis` (Pro) | ~50 | 10,000 | 3,000 | Pro 2.5 | $1.30 | $39 |
| parse-* cluster | ~400 | 2,000 | 500 | Flash 2.5 | $0.60 | $18 |
| Misc (race-intel, race-readiness, …) | ~100 | 2,000 | 400 | Flash 2.5 | $0.14 | $4 |
| **Total** | ~3,900/day | | | | **~$11/day** | **~$330/mo** |

(Costs based on Gemini 2.5 Flash $0.30/M in + $2.50/M out, 2.5 Pro
$1.25/M in + $10/M out, Groq Llama 8B ~$0.05/M.)

Actual will be lower since not every user hits every surface every
day, but **$200–350/mo at 1k users is the realistic envelope** and
`coaching-agent` is the dominant single line item.

---

## The five levers — ordered by ROI

### Lever 1 — Delete the four cut-but-still-deployed functions  *(0.3d, immediate)*

CLAUDE.md says `form-check-analysis`, `biomechanics-analysis`,
`custom-plan-builder`, and `adaptive-workout` are cut. The directories
still exist with LLM calls inside. Every iOS or web client that still
hits these (or that gets triggered to hit them) burns Gemini tokens
for output the product no longer consumes.

- [ ] Delete the four function directories
- [ ] Run `supabase functions deploy` — they go away
- [ ] Search for remaining client references and remove
- [ ] Drop unused prompt files from `_shared/prompts/`

**Savings:** unknown but non-zero; recovers ~1,500 LOC of code surface
that doesn't earn its keep. Removes attack surface (these handlers
still accept input and call models).

### Lever 2 — Aggressively compress `coaching-agent` context  *(2d)*

This is the single biggest cost line. The moderate/complex prompt
concatenates 14+ context blocks (`trainingContext`,
`athleteProfileContext`, `analyticsContext`, `periodizationContext`,
`planAwarenessContext`, `planContext`, `predContext`, `goalsContext`,
`memoriesContext`, `injuryContext`, `raceIntelContext`,
`aiInsightsContext`, `weeklyReportContext`, `profileContext`,
`hkContext`, `conversationContext`, `docsContext`, `feedbackContext`,
`pendingAdjustmentsContext`) before the user message. Some are empty,
many are not.

The compressor `compressTrainingContext` in `_shared/context.ts`
already cuts logs from ~500 tokens to ~50 (90%). It's used in
`form-check-analysis`, `biomechanics-analysis`, `injury-analysis`.
**It is not imported by `coaching-agent`.** And `coaching-agent`
pulls 150 raw training logs.

Plan:
- [ ] Import `compressTrainingContext` in `coaching-agent`; replace
  the raw 150-log dump with the compressed summary + the 7 most
  recent raw logs (most-recent has the highest signal for "how am I
  feeling about today")
- [ ] Build the equivalent of `compressTrainingContext` for the
  other heavy blocks: `compressPeriodizationContext`,
  `compressPlanAwarenessContext`, `compressAnalyticsContext`. Each
  should output ≤200 tokens.
- [ ] **Budget per block.** Add an explicit token budget in
  `coaching-agent`: simple = 1k tokens of context, moderate = 4k,
  complex = 8k. Hard-cap with truncation, not silent overflow.
- [ ] **Don't include "weekly report" + "AI insights" + "athlete
  profile" + "athlete state" in the same prompt.** Three of these
  cover the same ground from different angles. Pick one per
  complexity tier.
- [ ] Add a `[tokens used: X / cost: $Y]` log line on every
  invocation so the win shows up in usage_tracking.

**Estimated savings:** 50–60% reduction on `coaching-agent` input
tokens. **$50–70/mo recovered.**

### Lever 3 — Prompt caching on stable per-user prefixes  *(2d)*

The system prompt + athlete profile + active memories + injury
context + active goals are mostly stable across a user's day. Both
Gemini ("cachedContent" via Vertex / context cache API) and Anthropic
(`cache_control: { type: "ephemeral" }`) charge ~10–25% of normal
input cost for the cached portion.

For a 5,000-token per-user prefix that gets hit 10 times in a session,
that's a 7.5× saving on those tokens.

Plan:
- [ ] Identify the stable prefix in `coaching-agent` —
  `SYSTEM_PROMPTS[complexity]` + `athleteContext` +
  `athleteProfileContext` + `memoriesContext` + `injuryContext`
- [ ] Wrap the Gemini call to use `cachedContent` (5-minute TTL by
  default; renew on hit). Cache key = `userId + complexity +
  athleteStateHash`. Invalidate when athlete_state updates.
- [ ] For `fitness-predictor` (Claude Haiku), add
  `cache_control: { type: "ephemeral" }` to the static training
  context portion of the prompt
- [ ] Track cache hit rate in usage_tracking; surface in Slack
  weekly alert

**Estimated savings:** another 30–40% on `coaching-agent` after
Lever 2 lands. **$30–40/mo recovered.** Compounds with Lever 2 —
do them in this order.

### Lever 4 — Move the deterministic 80% of `weekly-coaching-report` out of the LLM  *(2d)*

Weekly reports are mostly facts:
- *"You ran 32 miles this week across 5 runs (vs. 28 last week,
  +14%)."*
- *"Your ACWR is 1.2, down from 1.4 — load is stabilizing."*
- *"Three runs above MP, two recovery. Your hardest day was Tuesday."*

None of that needs a model. The model is doing two things: (a)
arranging facts into a readable narrative, and (b) writing the
"coaching voice" framing. Today the entire report is generated by
Flash including the deterministic parts. The prompt is huge because
the model has to derive the facts itself before writing prose.

Plan:
- [ ] Build a deterministic report skeleton in
  `_shared/weeklyReportBuilder.ts` — pulls from `athlete_state`,
  `weeklyAnalytics`, and `training_logs`. Outputs a structured
  markdown report with all facts inserted.
- [ ] LLM pass becomes a thin "voice" rewrite: ~500 tokens in
  ("here's the structured report, rewrite it in coach voice"), ~800
  tokens out
- [ ] Or skip the LLM entirely and template the prose — A/B test
  whether the voice pass adds measurable value

**Estimated savings:** 70–80% reduction on `weekly-coaching-report`
input tokens. **$12–15/mo recovered.** Also makes the report
schema-stable, which the eval harness will appreciate.

### Lever 5 — JSON mode + structured outputs everywhere it's not creative  *(1d)*

JSON mode is used in 8 functions today (`parse-workout-structure`,
`weekly-plan-review`, `weekly-coaching-report`, `parse-training-week`,
`block-review`, `race-readiness`, `parse-training-plan`,
`process-check-in`). Missing from `injury-analysis`,
`injury-early-warning`, `race-intel`, `evaluate-coachable-moment`,
`fitness-predictor`, and the structured parts of `coaching-agent`.

Without JSON mode:
- The prompt has to spend tokens explaining the output format
- The output has to spend tokens writing JSON markers + escape chars
- The parser has to be tolerant of LLM-generated noise

With JSON mode:
- ~150–300 tokens saved per call on input ("respond as JSON with
  the following schema...")
- ~50–100 tokens saved per call on output (no preamble)
- Parser becomes a trivial `JSON.parse`

Plan:
- [ ] Add Gemini `responseMimeType: "application/json"` +
  `responseSchema` to `injury-analysis`, `injury-early-warning`,
  `race-intel`, `evaluate-coachable-moment`, `fitness-predictor`
- [ ] For prompts that mix prose and structured data
  (`coaching-agent` rarely needs this; `weekly-coaching-report`
  does), split into two passes — structured pass for facts, prose
  pass for voice

**Estimated savings:** 10–15% across the affected functions.
**$15–20/mo recovered.** Bigger win: eval harness can validate
schema directly.

---

## The four secondary levers

These earn less, but cost little to implement.

### Lever 6 — Cap output tokens at quality-not-cost  *(0.3d)*

The router's `moderate` tier allows 2,000 output tokens; `complex`
allows 3,000. Most coach responses are 300–600 tokens. The cap is
defensive against truncation but a regression that generates a
3,000-token response under low-quality reasoning costs as much as 5
well-formed responses.

- [ ] Drop `moderate` output cap to 800 tokens, `complex` to 1,500
- [ ] Log when responses hit the cap; raise only if quality
  measurably suffers

**Savings:** worst-case bounded; typical case ~5–10%.

### Lever 7 — Conversation summarization at message N=10  *(1d)*

`coaching-agent` pulls 50 most-recent conversation messages. The
median session is 5–7 turns. The other 43 are paying for nothing
on most calls and for "what was discussed two weeks ago" on the rest.

- [ ] Maintain a per-conversation summary in
  `conversation_messages.summary` (or a sibling table)
- [ ] When a conversation has >10 messages, the older messages get
  summarized into 200 tokens; only the last 5 raw turns are included
- [ ] Re-summarize at 20, 30, etc.

**Savings:** 30–40% on long-conversation `coaching-agent` calls.
**$5–10/mo.**

### Lever 8 — `training-analysis` audit  *(0.5d)*

This is one of two `gemini-2.5-pro` call sites. Pro costs ~4× Flash
on input and ~4× on output. If the analysis is "given this data,
identify patterns," that's often a Flash job with structured output.
If it's "given this data, write a multi-section diagnostic narrative,"
keep Pro.

- [ ] Read the actual prompt and the actual output spec
- [ ] If structured patterns → drop to Flash 2.5 with JSON mode
- [ ] If true multi-step reasoning → keep Pro but add prompt caching
  on the rubric portion

**Savings:** if drop-to-Flash, $30/mo. If keep-but-cache, $10/mo.

### Lever 9 — Consider Flash-Lite for the cheapest paths  *(0.5d)*

Gemini 2.5 Flash-Lite at ~$0.10/M input is 3× cheaper than 2.5 Flash.
Quality is meaningfully lower on reasoning but fine for the dumb
paths: `parse-workout-shorthand`, `parse-workout-structure`, the
Niggles classifier (closed vocabulary).

- [ ] Pilot on `parse-workout-shorthand` first (the simplest parser).
  Run side-by-side against Flash 2.5 for a week via the eval
  harness; ship Flash-Lite if eval score is unchanged.

**Savings:** $5–10/mo if rolled to 3–4 functions.

---

## Architectural opinion: the right shape for AI cost at 10k users

This isn't 1k-user work, but the lever ordering above sets you up for it:

```
┌────────────────────────────────────────────────────────┐
│  Athlete State DCO (already exists, deterministic)    │ ← single source of truth
│  - precomputed metrics                                │
│  - updated on training_log, voice_log writes          │
│  - cached in DB                                       │
└─────────────────────────┬──────────────────────────────┘
                          │
       ┌──────────────────┼─────────────────────┐
       ▼                  ▼                     ▼
  Code path          LLM path             Cache path
  (free)             (Gemini/Claude)      (prompt cache)
       │                  │                     │
       │                  │                     │
  ╔════╧════╗        ╔════╧═════╗         ╔═════╧═════╗
  ║weekly   ║        ║coaching- ║         ║per-user   ║
  ║report   ║        ║agent     ║         ║stable     ║
  ║skeleton ║        ║complex   ║         ║prefix     ║
  ║         ║        ║          ║         ║(5min TTL) ║
  ║rule-    ║        ║          ║         ║           ║
  ║based    ║        ║          ║         ║           ║
  ║coachable║        ║injury-   ║         ║athlete    ║
  ║moments  ║        ║analysis  ║         ║profile +  ║
  ║         ║        ║          ║         ║memories   ║
  ║niggles  ║        ║          ║         ║+ injuries ║
  ║surface  ║        ║parse-*   ║         ║           ║
  ║(quote   ║        ║(JSON     ║         ║           ║
  ║verbatim)║        ║mode)     ║         ║           ║
  ╚═════════╝        ╚══════════╝         ╚═══════════╝
```

The principle is: **the athlete state DCO is the ledger; LLMs are the
voice; never use an LLM where code can answer.**

That principle is already the architecture. The work below is just
making it consistent.

---

## Implementation order

Add to `TASKS.md` after Week 3. Each item is independent, can be
parallelized with feature work.

| # | Lever | Effort | Savings/mo | Order |
|---|---|---|---|---|
| C.1 | Delete the 4 cut LLM functions | 0.3d | unmeasurable + attack surface | Week 4 |
| C.2 | Compress `coaching-agent` context | 2d | $50–70 | Week 4 |
| C.3 | Prompt caching on stable per-user prefix | 2d | $30–40 | Week 5 |
| C.4 | Move 80% of weekly-coaching-report to code | 2d | $12–15 | Week 5 |
| C.5 | JSON mode on remaining 5 functions | 1d | $15–20 | Week 6 |
| C.6 | Output-token caps | 0.3d | $5–10 | Week 6 |
| C.7 | Conversation summarization at N=10 | 1d | $5–10 | Week 6 |
| C.8 | `training-analysis` Pro→Flash audit | 0.5d | $10–30 | Week 6 |
| C.9 | Flash-Lite pilot for parsers | 0.5d | $5–10 | Week 7 |

**~10 engineering days total. Estimated savings: $130–215/mo at 1,000
users.** At 10k users this scales linearly to roughly $1,300–2,100/mo
saved.

The eval harness from Week 2 (`TASKS.md` → W2.1) is the gating
prerequisite for any prompt change. **Don't make these changes before
the harness lands** — context compression and prompt caching both
change the model's input distribution, and you need a way to know
quality didn't regress.

---

## What this does NOT compromise

- **No model tier is dropped** on prompts that need the reasoning
  (`training-analysis` audit may move Pro → Flash but only if the
  eval says it's safe; `generate-training-plan` stays on Pro)
- **No coaching voice change** — the deterministic-skeleton +
  thin-voice pattern preserves the writing style that makes the
  product feel like a coach, not a chatbot
- **No reduction in the safety guardrails** that make Niggles
  non-diagnostic — those are independent of model choice
- **No reduction in personalization quality** — context compression
  is a *summarization* operation, not a truncation; the model still
  sees the patterns, just in fewer tokens

The whole point is: the best-quality output usually comes from a
focused, well-structured prompt, not a 14-block context dump. This
work makes the prompts focused.

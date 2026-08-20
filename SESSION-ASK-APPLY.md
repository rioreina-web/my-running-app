# Session Ask — apply notes

*Authored 2026-08-20. Replaces the `✦ READ THE INSIGHT` row at the foot of a
session with a free-text field plus a short list of questions about the run.*

*Companions: `ASK-IOS-APPLY.md` (the client), `ASK-REGISTRY.md` (the
analyzers), `ASK-V2-CONVERSATION.md` (conversation state, §2).*

**6 new files, 2 edits, 2 shared extractions. No new analyzer, no new table,
no client-side chart, and — corrected 2026-08-20 — nothing routed through
`coaching-agent`. See §0.5.**

| New file | What it is |
|---|---|
| `supabase/functions/session-ask/index.ts` | The endpoint (§5.3) |
| `supabase/functions/_shared/session-questions.ts` | The 15 questions + the picker (§2) |
| `supabase/functions/_shared/prompts/session-ask.v1.ts` | The prompt (§6) |
| `RunningLog/RunningLog/Workouts/SessionAskBlock.swift` | The box (§4) |
| `RunningLog/RunningLog/Services/SessionAskService.swift` | The client (§5.2) |
| `RunningLogTests/SessionAskBlockTests.swift` | (§10) |

Prototype: `session-ask-prototype.html`.

---

## 0 · Why the row goes

`insightBlock` asks one question on the athlete's behalf and pays for it
whether or not she wanted that question. Its own header says so:

> *NOTE on cost: `process-training-memo` still generates an insight
> server-side for every voice memo… If we want to actually stop paying for
> insights nobody reads, drop the eager generation from that edge function
> and let this be the only producer.*
> — `HistoryDetailViewModel.swift:774`

The problem isn't the paragraph. It's that the paragraph is the **only**
question available at the moment the athlete has a specific one. She has just
scrolled her pace trace, her zone chart and her splits. She isn't wondering
*"tell me about my run"* — she's wondering *"was rep two too fast"* — and
there is nowhere to put it.

---

## 0.5 · The AI is not the coach

**A coach in this product is a person.** `coach_id` exists, there's a web
coach portal, `TodayHomeView` renders *"one unread note from the athlete's
coach"*, and CLAUDE.md opens by describing coachable moments **"that human
coaches act on"** with decisions owned by *"the human"*.

So this surface does not get a coach persona, is not called the coach, and
does not route through `coaching-agent`. It reads the athlete's training and
reports what's in it. It knows the material; it isn't the person who owns the
decision or the relationship.

### An earlier draft of this document got this wrong

It routed the box through `coaching-agent` and reused `CoachAskSheet`. That
was wrong twice over — the boundary above, and a documented engineering
failure. `HistoryDetailViewModel.swift:795` records what happened last time
a workout question went to that agent:

> *With almost no quantitative context, that chat agent followed its
> ask-vs-answer design and kept defaulting to "I need more info — what's your
> weekly mileage?"*

The fix then was to call the purpose-built `generate-workout-insight` by
`training_log_id`. **This feature belongs to that lineage**, not the chat
agent's. §5.3 builds a sibling endpoint beside it.

Dropping the charts is what made this clean rather than costly: prose-only
removed the only reason to borrow the Coach's answer card, so the answer now
renders inline (§5.4) and the Coach surface is untouched.

### Two things this contradicts, which are yours to call

**`brand-voice.md:107` says the opposite.** *"The message isn't 'AI + human
coaching' (**you don't have a human coach in the loop**). It's 'the discipline
and voice of a great coach, implemented with AI.'"* That document makes
*Coach* the product's own persona — line 13: *"Coach is the noun — it's what
the product is. AI is nowhere in the sentence."*

The repo says otherwise. `coach_id` and the coach portal are shipped code.
`brand-voice.md` appears to be the stale document, but **it's a positioning
call, not a code question** — don't let a coding agent resolve it by editing
whichever file it happens to open.

**`generate-workout-insight.v6` opens *"You're an experienced run coach"*.**
So the currently-shipping insight already speaks as a coach. Bringing it
inside this boundary is a one-line prompt change plus a re-record of its
cassettes — but it changes the voice of a feature that's live, so it is a
deliberate separate change, **not something to fix while wiring this up**.

Scope for this document: the new surface holds the boundary. Existing copy is
left exactly as it is.

---

## 1 · One path

Every question on this surface — tapped chip or typed text — takes the same
route:

```
question + training_log_id
        ↓
session-ask          ← new endpoint, sibling of generate-workout-insight
  buildSessionBlock + buildAthleteStateBlock + session-ask.v1
        ↓
prose + a line naming what it read + the next questions
```

Not `coaching-agent`, and not the `ask` analyzer registry. §0.5 has the why.

There is no chip→analyzer binding, no router branch, no second rendering
mode. A chip is a **prefilled question**, nothing more. One code path.

### What this surface deliberately does not render

| Not rendered | Why |
|---|---|
| `series` / `AskChart` | The sheet is three charts deep before she reaches the box. A fourth answers a question she didn't ask and is the most expensive thing on the response. |
| The fact grid | Four tiles of numbers she just scrolled past. The prose says the number. |
| Coverage tiles / confidence badge | Replaced by one sentence (§3). |
| "That analyzer isn't built" | Never show an athlete a coverage gap she didn't ask about. Answer worse; don't refuse. |

The analyzer registry is untouched and Trends keeps its full card. This is a
second, lighter consumer of the same context — not a replacement for Ask.

---

## 2 · What the athlete sees

```
──────────────────────────────────────────
✦  ASK THIS SESSION                 AUG 18

┌────────────────────────────────────┬───┐
│ Ask anything about this run…       │ ↑ │
└────────────────────────────────────┴───┘

[ ✦ What's the read on this session? ]
[ Did I hold the pace across the reps? ]
[ How hard was this, really? ]
[ How does this compare to the last one like it? ]
[ Was that pace real, or was it the conditions? ]

              MORE QUESTIONS ⌄
──────────────────────────────────────────
```

One rail. The coral chip is the old insight, now asked for rather than
auto-written — same text, same endpoint, same persistence, one fewer
assumption about what she wanted.

Those five are what a **rep session with splits, heart rate and weather**
surfaces. A long run gets fade and durability questions instead; an easy run
with no HR gets fewer, and none of them pretend to assess effort.

### Fifteen questions, five on the rail

The full set and its gating live in
**`supabase/functions/_shared/session-questions.ts`** — written, commented and
ready to drop in. Eight intents:

| Intent | n | Gated on |
|---|---|---|
| The read | 1 | Always. Pinned first — the old row's job. |
| Execution | 4 | A prescription, ≥2 reps, splits. |
| Effort | 3 | Heart rate or splits. |
| Conditions | 2 | Weather captured; elevation stream present. |
| Comparison | 2 | A comparable prior; quality session. |
| Fit | 2 | Always; goal + quality. |
| Body | 1 | She mentioned something, or a mention is open. |
| Next | 1 | Quality or long runs. |

Three gates are judgement calls rather than data checks, and they're the ones
most likely to get "simplified" away by someone who doesn't know why:

- ***Did I fade in the back half?* is withheld on easy runs.** Late drift is
  normal there, and `generate-workout-insight.v6` already instructs the model
  not to read it as a fade. Offering the question invites the answer the
  prompt was written to prevent.
- ***Is there anything worth paying attention to?* is never offered on a clean
  session.** Inviting a worry question on a good run is its own kind of harm.
  It appears when she mentioned something or a body mention is open.
- ***Was this actually easy?* requires heart rate or splits.** Without either
  it's a guess dressed as an assessment, and it's probably the most useful
  question in the set when it can be answered properly.

The picker fills the four slots after *the read* **one intent at a time**
before any intent gets a second. Without that pass, any session with splits
fills the rail with four execution questions — each individually relevant,
collectively a worse rail.

Nothing eligible is discarded: the rest sit behind *More questions*, one tap
away. That's the point of having fifteen rather than five.

### The list comes from the server

**This is the most important structural decision here and it costs one
field.** The chip list ships in the ask response, not in the app binary:

```json
{
  "answer": "…",
  "read_from": "Read from this session's laps, your zones as of Aug 18, …",
  "suggested": [
    { "id": "read",         "text": "What's the read on this session?" },
    { "id": "held_the_pace","text": "Did I hold the pace across the reps?" },
    { "id": "how_hard",     "text": "How hard was this, really?" }
  ]
}
```

`pickQuestions(shape)` runs server-side against a `SessionShape` — workout
type, rep count, and booleans for splits, HR, elevation, conditions, notes,
prescription, comparable, body mention, goal. Rewriting the list is a config
edit and a deploy. Changing it in the client is an App Store release and a
week of review.

It ships as a static file. It becomes a table the day someone wants to A/B
it, and nothing in the client changes when it does.

---

## 3 · The line at the bottom

Every answer ends with one sentence naming its sources:

> *Read from this session's laps, your zones as of Aug 18, and the conditions
> at 6:29 AM.*

Assembled from **which blocks the context builder actually loaded** — not a
model output, not a computation, a string. It costs nothing, it can't be
wrong, and it is most of what made the coverage row worth having. Do not let
it get cut for being small; it's the difference between a product that feels
analytical and one that feels like it's guessing.

---

## 4 · New file — `RunningLog/RunningLog/Workouts/SessionAskBlock.swift`

Lives in `Workouts/` because it's part of the sheet's editorial layout and
uses the sheet's typography (`DripEyebrow`, `dripCaption(10)`,
`tracking(1.2)`), not the Trends `AskBar`'s.

**It owns no insight logic.** `summaryText`, `memoTranscriptUrl` and
`generateThenReveal()` are `private` members of the `HistoryDetailSheet`
extension in `HistoryDetailSheet+Editorial.swift`, and `showInsight` is
`@State` on the sheet. A block reaching for them wouldn't compile. Closures
in, no shared state:

```swift
struct SessionAskBlock: View {
    /// `training_logs.id`. `HistoryDetailEntry.id` is a UUID.
    let workoutId: UUID
    /// "AUG 18" — built at the call site, the only place the file-private
    /// `Date.editorialDateString` helper is visible.
    let dateLabel: String

    // ── the read chip's state, all owned by the sheet ──
    let hasInsight: Bool
    let canGenerateInsight: Bool
    let isGenerating: Bool
    let hasInsightError: Bool
    let onReadTapped: () -> Void

    @State private var text = ""
    @State private var staged: StagedAsk?
    @State private var showAll = false
    @FocusState private var fieldFocused: Bool
}
```

`suggested` arrives with the first answer, so on a cold sheet the rail shows
`COLD_START_QUESTIONS` — three questions that apply to any run at all, mirrored
from `session-questions.ts`. Don't block the rail on a network call; an empty
rail reads as broken, a generic one reads as not-loaded-yet, which is what it
is. Those three strings existing in two places is the one duplication in this
design and it's deliberate.

### The read chip

Five states, same priority order `insightBlock` uses today — a re-skin of a
working state machine, not a new one:

| Condition | Label | On tap |
|---|---|---|
| `hasInsight` | `✦ What's the read on this session?` | Open it. No generation, no cost. |
| `isGenerating` | `✦ WRITING YOUR READ…` | Disabled, spinner. |
| `hasInsightError` | `✦ COULDN'T GET IT · RETRY` | `onReadTapped()` |
| `canGenerateInsight` | `✦ What's the read on this session?` | `onReadTapped()` |
| otherwise | `✦ THE READ NEEDS A MEMO` | Disabled, dashed. |

**`generateCoachInsight()` and `saveCoachInsight(_:)` are not touched.** Only
the affordance moves.

---

## 5 · Edits

### 5.1 `Workouts/HistoryDetailSheet+Editorial.swift`

Replace the `insightBlock` call site (~line 310):

```swift
if !isEditing {
    // The panel is unchanged and still owned here — the chip only opens it.
    if hasInsight, showInsight, let insight = vm.coachInsight {
        openInsightPanel(insight)
    }
    SessionAskBlock(
        workoutId: vm.currentEntry.id,
        dateLabel: (vm.currentEntry.workoutDate ?? vm.currentEntry.createdAt)
            .editorialDateString,          // already uppercase; file-private
        hasInsight: hasInsight,
        canGenerateInsight: canGenerateInsight,
        isGenerating: vm.isGeneratingInsight,
        hasInsightError: vm.insightError != nil,
        onReadTapped: {
            if hasInsight {
                withAnimation(.easeInOut(duration: 0.2)) { showInsight = true }
            } else {
                Task { await generateThenReveal() }
            }
        }
    )
}
```

`Date.editorialDateString` is a **file-private** extension — `private extension
Date` at line 32, the property at line 33 of this file — visible here and nowhere else, which is why the label is built at the
call site. It already uppercases; don't add `.uppercased()`.

**Keep** `openInsightPanel(_:)`, `hasInsight`, `canGenerateInsight`,
`generateThenReveal()`. **Delete** `insightRow(...)` and `insightBlock` once
nothing references them. `@State var showInsight`
(`HistoryDetailSheet.swift:36`) stays.

### 5.2 New — `RunningLog/RunningLog/Services/SessionAskService.swift`

**Do not extend `DailyReadService.ask(_:)`.** That is the Coach's client and
it posts to `coaching-agent`; §0.5 is why this doesn't go there. A small
dedicated service instead:

```swift
@Observable
final class SessionAskService {
    static let shared = SessionAskService()

    struct Answer: Decodable {
        let answer: String
        /// "Read from this session's laps, your zones as of Aug 18, …" (§3)
        let readFrom: String?
        let suggested: [Suggestion]
        struct Suggestion: Decodable, Identifiable { let id: String; let text: String }
    }

    func ask(_ question: String, workoutId: UUID) async throws -> Answer
}
```

One call: `supabase.functions.invoke("session-ask", …)` with
`{ question, training_log_id }` — the same shape `generateCoachInsight()`
already uses for `generate-workout-insight`, so error handling and decoding
follow a pattern that exists.

`CoachAskSheet`, `CoachReadView`, `ModelOfYouView` and `DailyReadService` are
**not touched by this document**.

### 5.3 New — `supabase/functions/session-ask/index.ts`

**This is the part that decides whether the feature is good**, and it is a
sibling of `generate-workout-insight`, not a branch inside `coaching-agent`.

```
POST { question, training_log_id }
  → auth, ownership check on training_logs.id
  → buildSessionBlock(supabase, userId, logId)      ← required
  → buildAthleteStateBlock(userId)                  ← required
  → assembleWithBudget(blocks, budget)
  → loadPrompt("session-ask.v1", { question, …blocks })
  → { answer, read_from, suggested }
```

**The athlete block is not the one to trim.** A box that answers *"was I
holding back?"* without her volume, phase, goal and history produces something
fluent and useless — the failure already on record in §0.5.

| Block | Priority |
|---|---|
| this session (`buildSessionBlock`) | **required** |
| athlete state (`buildAthleteStateBlock`) | **required** |
| recent logs — her own words, ~28d | preferred |
| plan awareness, profile | optional |

`_shared/context.ts:778` already has `assembleWithBudget(blocks, budget)` with
exactly this `required`/`preferred`/`optional` vocabulary (`:718`), per-block
caps, and a report of what was dropped. Use it — don't hand-concatenate. The
note at `coaching-agent/index.ts:1430` records why that assembler exists: 22
blocks unconditionally concatenated, and no review-time signal when someone
added a 23rd.

#### Two extractions into `_shared/context.ts`

**`buildAthleteStateBlock(userId): Promise<string>`** — lift
`loadAthleteStateBlock` verbatim from `generate-workout-insight/index.ts:93`.
Already complete and already well-judged: volume so it never asks for weekly
mileage, fitness as *ranges never point times* (hard rule #7), declared races,
phase, goal plus the seconds-per-mile gap, load vs chronic, niggles surfaced
but never diagnosed (hard rule #2), behavioural patterns, recent summary. 17
columns of `athlete_state` in one query.

Nothing needs redesigning — it needs to stop being private to one function.
Move it, import in both, delete the original. **Behaviour-preserving by
construction, which is why it ships first and alone.**

**`buildSessionBlock(supabase, userId, logId): Promise<string>`** — the
per-session assembly inside `generateInsight()` (`:770`): laps, parsed
structure, pace zones, conditions, memo, mood.

#### `read_from` and `suggested`

Build `read_from` from `AssembledContext.included` (`_shared/context.ts:745`)
— the assembler already reports which blocks made it in, so the provenance
line is a `map` over a list that exists rather than a second source of truth.

Build `suggested` by calling `pickQuestions(shape)` from
`_shared/session-questions.ts`, filling `SessionShape` from what
`buildSessionBlock` already loaded. No extra queries.

#### One caveat that comes with knowing the athlete better

`niggle_recurrence` lands in context on every call, and a model handed the
same flashcard forever will raise it forever. That's the complaint
`ASK-V2-CONVERSATION.md §3` diagnoses, and its fix is a `surfaced_at`
watermark — state, not prompt language. Rich athlete state under all fifty
sessions makes this louder, not quieter.

Ship without it. If the knee starts appearing in answers to questions that
weren't about the knee, §3 of that document is the fix and it's server-side
only.

### 5.4 The answer renders inline

No sheet. `SessionAskBlock` holds `@State private var answer: Answer?` and
renders prose + the `read_from` line beneath the field, with the rail
becoming the returned `suggested`.

Earlier drafts opened `CoachAskSheet` to avoid duplicating answer rendering.
That reasoning died with the charts: `AskAnswerCard` exists to lay out a fact
grid, a chart and a band switcher, and this surface renders none of them. What
remains is a paragraph and a line of small type. Borrowing the Coach's sheet
to display that would import the wrong surface (§0.5) for no saved work.

Typography: `.dripBody(15)`, `lineSpacing(4)`, `Color.drip.textPrimary` for
the answer; `.dripCaption(10)`, `tracking(1.2)`, `textTertiary` for
`read_from`.

---

## 6 · The prompt — `_shared/prompts/session-ask.v1.ts`

Written and ready to drop in. Register it in `prompt-library.ts` (one import,
one `REGISTRY` line, per that file's header).

**Same placeholder set as `generate-workout-insight.v6`** — deliberately, so
one context assembly feeds both and the two can be evaluated against the same
fixtures. Same blocks, opposite job: v6 decides *what is worth saying* about a
run nobody asked about; this answers *the thing that was asked*.

Six instructions carry the weight. If this prompt gets rewritten later, these
are the ones that were load-bearing:

1. **Answer the question they asked.** Lead with the answer, then the
   evidence. The dominant failure mode is drifting into a general read — which
   is exactly what the athlete already had and chose to replace.
2. **Length follows the question.** *"Was this actually easy?"* is two
   sentences and a heart rate. *"What should the next one look like?"* earns
   three or four short paragraphs because there's a real trade-off. v6's rule
   is inverted here: it caps ordinary runs at two sentences, which is right
   for an unasked-for read and wrong for an answer.
3. **Never ask for what's already in context.** The single most important
   line, and the one with a documented failure behind it — the old insight
   sent a bare `distance | duration | pace` and got back *"what's your weekly
   mileage?"*. Name a gap in one clause, then answer anyway. Never reply with
   a question instead of an answer.
4. **Ground every number.** Real zones, real splits, no invented paces. If the
   splits block doesn't say it faded, it didn't fade — and match magnitude, so
   a three-second drift stays a three-second drift.
5. **Read their own words longitudinally.** Quote verbatim or not at all.
   Never paraphrase a symptom into clinical language.
6. **Stay inside the rails.** Observation, never diagnosis or severity. When a
   question invites crossing — *"should I be worried about my knee?"* — say
   plainly you can't tell her whether something's wrong, then give her what
   her logs do show: when it's come up, on what kind of session, whether it
   came up in this one. **That's an answer, not a deflection**, and it's the
   pattern worth taking to a physio. The prototype's body answer is the copy
   reference.

**Cassettes with the prompt, not after it.** `_evals/cassettes/session-ask.v1/`
— at minimum: a question the context can't fully answer (does it answer anyway,
per #3), the knee question (does it stay inside #6), an easy run asked about
fade (does it decline the frame), and a rep session (does it lead with the
answer). Every other prompt family in this repo has stub cassettes; see §8.

---

## 7 · Phasing

| Phase | Ships | Why here |
|---|---|---|
| **A** | The block, the rail, the read chip, `SessionAskService` (§4, §5.1–5.2). `session-ask` returns the existing insight and ignores the question at first. | Client-only, one afternoon, nothing can regress. The box is real; the answers are as good as today's insight. |
| **B1** | `buildAthleteStateBlock` extracted to `_shared/context.ts`, imported by both callers. | Pure move, no behaviour change, reviewable in five minutes. Do it alone so that if anything does shift, you know what shifted. |
| **B2** | `session-ask` proper: `buildSessionBlock`, `assembleWithBudget`, the question honoured, `read_from`, `suggested` (§5.3). | The answers become about *this run, for this athlete*. This is where the feature actually lands. |
| **C** | Read a month of `analysis_queries`. Build computation for the top questions. | See §8. |

A and B are the build. C is the product. B1 before B2 — an extraction and a
behaviour change in one commit is a bisect you'll regret.

---

## 8 · Where the agility lives

Three properties make this cheap to change later, and they're worth protecting
against the instinct to tidy them away:

1. **Questions are server data, not client code.** Changing what a long run
   asks is a config edit. This is the whole reason §2 puts `suggested` on the
   response instead of in a Swift array.

2. **Every question is already logged.** `ask/index.ts` writes an
   `analysis_queries` row for each one. Ship prose-first, read what people
   actually type for a month, then build analyzers for the top five. That's a
   far better way to pick the next analyzer than working down `ASK-REGISTRY.md`
   in order.

3. **The computed layer is additive.** When a question earns real math, that
   analyzer's fact lines get handed to the same prose call as extra context.
   The client doesn't change; the answer just gets more accurate. **Nothing
   built now has to be torn out to add computation later** — which is the
   actual test of whether this was the right small version.

---

## 9 · The trade-off, stated plainly

Prose answers are not number-guarded. Layer-2 narration over analyzer facts
cannot speak a number absent from `facts`; a conversational answer can. That
guard isn't being removed — it just isn't on this path.

**This is not a new exposure.** The insight paragraph this box replaces is
already pure prose over a session context, generated for every voice memo,
with no number guard at all. The box gives the athlete the choice of question
and stops generating unasked. On numbers, it's the same risk already shipping;
on cost, it's strictly less.

The rails that matter here — no diagnosis, no severity assessment, no
prescribing rest — now live in `session-ask.v1.ts` itself rather than being
inherited from `coaching-agent`'s prompt. That's a consequence of §0.5 worth
naming: **this endpoint owns its own rails.** They're written into §6's
"STAY INSIDE THE RAILS" block, and if that block is ever edited, nothing else
is holding the line. The prototype's knee answer is the copy reference for
what staying inside them sounds like when a question invites crossing them.

### Adjacent findings, not caused by this change

Surfaced while verifying the above. Free text moving from the foot of one tab
to underneath all fifty sessions makes each of them louder:

1. **The eval gate does not run.** `.github/workflows/ci.yml:144` is
   `if: false`, and has been since 2026-06-16. `GOLDEN_FAMILIES` has teeth for
   nothing. Three of its eleven families are stubs.
2. All 8 `ask-narration.v1` cassettes have an empty `recorded_response`
   (verified by inspection, not by trusting the comment).
3. `generate-workout-insight/index.ts:878` loads prompt
   `generate-workout-insight.v6`; the cassette directory is
   `generate-workout-insight.v5`. Coverage is pinned to a prompt that isn't
   running — and this is the prompt phase B extracts from.
4. `AskFeature.freeTextEnabled`'s header says `ask-narration` is *"still
   missing from `GOLDEN_FAMILIES`"*. It isn't; it was added. Fix the comment
   so the next person doesn't re-audit it.

None block phase A. (3) is worth closing before phase B touches that file.

---

## 10 · Tests

**`RunningLogTests/SessionAskBlockTests.swift`** — new:

1. Read chip label and enablement across all five states in §4.
2. Tapping the read chip when `hasInsight` calls `onReadTapped` and does not
   generate — the whole cost argument in one test.
3. The static fallback rail renders before any server `suggested` arrives, and
   is replaced once one does.
4. A `suggested` list of zero leaves the fallback up rather than an empty rail.

**`RunningLogTests/CoachAskSheetTests.swift`** — extend:

5. `proseOnly: true` makes no `AskService` call at all.
6. `proseOnly: false` (Trends) still renders the card — pins that this change
   didn't leak into the other surface.
7. `workoutId` reaches `DailyReadService.ask` as `training_log_id`; nil emits
   no key.

**`supabase/functions/session-ask/index.test.ts`** — new:

8. A request includes **both** the session block and the athlete-state block.
   The second half is the one that will silently rot.
9. Under a squeezed token budget, both survive and the optional blocks are
   what drop — pins the `required` classification in §5.3 rather than
   trusting the declaration.
10. A `training_log_id` belonging to another user is rejected. The ownership
    check is the only thing standing between a valid session id and someone
    else's training.
11. `read_from` names exactly the blocks in `AssembledContext.included` — no
    block claimed that was dropped for budget.
12. `suggested` varies by `workout_type`, and is empty rather than absent when
    the session has nothing distinctive to ask about.
13. **`coaching-agent` is never invoked.** A cheap assertion that pins §0.5
    against a future refactor that "consolidates the chat paths".

**`supabase/functions/_shared/session-questions.test.ts`** — new:

15. A steady run never offers `held_the_pace`; an easy run never offers
    `back_half`; a session with no body mention and no notes never offers
    `worth_watching`. These are the three judgement gates in §2 and the ones
    most likely to be lost in a refactor — pin them by name.
16. A rep session with splits, HR and weather returns the five in §2, in that
    order. The intent round-robin is what this pins: four execution questions
    at the top would pass a naive "is it relevant" test and fail this one.
17. A manual entry with no splits, no HR and no weather still returns at least
    `read` and `right_session`. **The box is never empty**, which is the whole
    reason both of those have `applies: () => true`.

**`supabase/functions/_shared/context.test.ts`** — new, for B1:

13. `buildAthleteStateBlock` returns byte-identical output to the private
    `loadAthleteStateBlock` for a fixture row. This is the whole safety
    argument for doing the extraction as its own commit — write it first,
    then move the code.
14. A missing `athlete_state` row returns `""` and never throws. A new athlete
    asking a question on day one is the likeliest path through this code.

---

## 11 · Verified against the code, 2026-08-20

Every anchor below was checked against the working tree on the day this was
written. If a line number has drifted, the symbol name is the durable half —
search for that.

| Claim | Where | Status |
|---|---|---|
| `insightBlock` call site to replace | `HistoryDetailSheet+Editorial.swift:311` | ✅ |
| `insightBlock` definition | same file, `:730` | ✅ |
| `insightRow(...)` to delete | same file, `:763` | ✅ |
| `openInsightPanel(_:)` to keep | same file, `:825` | ✅ |
| `editorialDateString` is file-private | same file, `private extension Date` `:32`, property `:33`, already uppercased | ✅ |
| `@State var showInsight` stays | `HistoryDetailSheet.swift:36` | ✅ |
| `generateCoachInsight()` + the cost note | `HistoryDetailViewModel.swift:774` | ✅ |
| `func ask(_ question: String)` needs the new param | `Services/DailyReadService.swift:127` | ✅ |
| `assembleWithBudget(...)` exists | `_shared/context.ts:778` | ✅ |
| `required`/`preferred`/`optional` vocabulary | `_shared/context.ts:718` | ✅ |
| `AssembledContext.included` for `read_from` | `_shared/context.ts:745` | ✅ |
| `loadAthleteStateBlock` to extract | `generate-workout-insight/index.ts:93` | ✅ |
| `generateInsight()` session assembly to extract | same file, `:770` | ✅ |
| "22 blocks" note motivating the assembler | `coaching-agent/index.ts:1430` | ✅ — cited as precedent only; this document does not edit that file |
| **A human coach is real in this product** | `coach_id` in `Models/CoachModels.swift:67`; web coach portal referenced from `RunningLogApp.swift:254` and `SettingsView.swift:63`; *"one unread note from the athlete's coach"* `TodayHomeView.swift:294`; CLAUDE.md:11 *"human coaches act on"* | ✅ — the basis for §0.5 |
| **`brand-voice.md` contradicts that** | `:107` *"you don't have a human coach in the loop"*; `:13` *"Coach is the noun — it's what the product is"* | ⚠️ **unresolved, and yours to call** — see §0.5 |
| **The shipping insight speaks as a coach** | `generate-workout-insight.v6.ts` opens *"You're an experienced run coach"* | ⚠️ pre-existing; deliberately out of scope |
| `context.workout_id` reaches only `compare_session` | `ask/index.ts:436`; it's the sole analyzer declaring a `workout_id` param | ✅ — noted here because it's why this design routes to `coaching-agent` rather than the analyzer registry |

**Not verified — needs Xcode.** Nothing here has been compiled or run. The
Swift in §4 and §5.1 is written against the types as they read on disk, not
against a successful build. Build before trusting the layout.

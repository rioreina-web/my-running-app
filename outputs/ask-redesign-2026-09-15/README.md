# Ask — redesign mockup (2026-09-15)

**Canvas:** https://claude.ai/artifact/LcJpfPd1RMFM1dHT12yutY
(five phone screens, exportable as PNG/PDF).

## What this is

A mockup of the Ask experience: how a runner asks questions about her
own training log and gets an answer read out of it.

Today the Ask is a single text field pinned under the Read in
`RunningLog/Coaching/Read/CoachReadView.swift` that opens a "coming
soon" alert.

**There is no AI coach here.** The 2026-05-28 call was that Maya is a
data customer with a journaling habit, not a coaching customer: she
wants an articulate training journal, good data viz, and an analyst
she can query. So these screens have no persona, no avatar, no "from
your coach", and no first person in system copy. Answers are
attributed to the entries they were read from, not to a character.
The athlete's own "I" survives, in her questions and her quoted voice
memos, which is where the design system says first person belongs.

## The five screens

| Artboard | Screen | What it shows |
|---|---|---|
| `Main.dc.html` | Ask (tab default) | "Ask your training." Question field with a scope pill (This block · + Run), a row of lenses (Recovery · Fitness · Niggles · Compare · This week), and a short "IN YOUR LOG · TAP TO ASK" list of patterns, each citing a number. Last answer is one line at the bottom. |
| `Compose.dc.html` | Writing a question | A run attached as an evidence chip (`◆ MP TUE · SEP 8`), a lens selected, and a "THIS ANSWER WILL READ" list showing exactly which run, memo, and context will be drawn on. |
| `Reply.dc.html` | The answer | Her question quoted on top, then the Read format: a coral "READ FROM YOUR LOG" eyebrow, headline, one paragraph with inline `◆` chips, an italic line pointing at what the numbers don't settle, "NOT IN THE LOG", sources, confidence, follow-up chips, ask bar. |
| `Clarify.dc.html` | Narrowing the question | An ambiguous question ("my hamstring's been bothering me") gets narrowed before it's answered: sharp or achy, two tap answers, why the distinction changes which entries get compared, and the memos already on file. |
| `Asked.dc.html` | History | An index of past questions with each answer's headline, filterable by lens. |

## What makes asking better

1. **Questions can point at something.** A run, this block, a lens.
   The scope travels with the question.
2. **You see which entries will be read before you send.** Lets her
   fix a missing memo or a wrong run first, and makes the answer's
   basis legible.
3. **Suggested questions come from her data.** "Right hamstring showed
   up in 3 memos since Aug 30" instead of a generic tip list.
4. **Answers cite their sources** and carry a confidence line, so the
   reading is checkable rather than authoritative.
5. **Ambiguous questions get narrowed, not guessed at.** One question,
   two tap answers, because the answer changes which entries match.
6. **Every answer is kept** with the entries it came from.

## Open question for you

The tab is labelled **Ask**, not Coach. That differs from the 4-tab IA
in `outputs/maya-product-roadmap-2026-05-28.md` (Log · Trends · Train ·
Coach) and follows from dropping the coach framing. Confirm or revert.

## Rules held

- Post Run Drip tokens throughout (warm paper, ink, one coral per
  cluster, Crimson Pro / PT Serif / mono eyebrows, 24 px gutters,
  12 px cards, editorial rule). Values lifted from
  `design-system/colors_and_type.css` and `ui_kits/ios_app/tokens.css`.
- No prescriptions, no diagnoses, no "you should".
- "Not medical advice" line on the niggle screen, verbatim from the
  design system voice guide.

## What it would take to build

The backend contract exists: `DailyReadService.ask()` posts to
`coaching-agent` with `format = "editorial"` and decodes a
`CoachRead`. The answer screen renders with the components already in
`Coaching/Read/` (`ReadProse`, `EvidenceChip`, `CantSeeBlock`,
`SourcesPanel`, `ConfidenceBar`).

New work, roughly in order:

1. Ask front-door view replacing the pinned bar.
2. Scope and attachment on the request body (`scope`, `workout_id`,
   `lens`), plus the "will read" preview (a cheap pre-flight returning
   the source list without generating prose).
3. A `clarify` response type: one question plus 2 tap answers.
4. An `asks` table (with RLS, per `docs/conventions/rls-checklist.md`)
   to persist question and answer for the history screen.
5. Prompt revision to drop the coach persona, with eval cassettes
   before it ships (hard rule 3). The current Read prompt writes in a
   coach voice; these screens assume it doesn't.

## Files

- `parts/*.html` — the screen bodies; `parts/common.css` — the tokens.
- `build.mjs` — assembles `*.dc.html` from the parts (`node build.mjs`).
- `canvas.json` — artboard layout and the notes on the canvas.

All copy is sample text written for Maya (3:28 PB, chasing 3:16).

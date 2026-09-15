# Coach Ask — redesign mockup (2026-09-15)

**Canvas:** https://claude.ai/artifact/LcJpfPd1RMFM1dHT12yutY
(five phone screens, exportable as PNG/PDF).

## What this is

A mockup of the "Ask the coach" experience, rebuilt as the front door
of the Coach tab. Today the Ask is a single text field pinned under
the Read in `RunningLog/Coaching/Read/CoachReadView.swift` that opens
a "coming soon" alert. The 2026-05-28 roadmap decision reframed Coach
as *an analyst Maya queries on demand*, with the Ask interaction as
the primary mode. This mockup is what that looks like.

## The five screens

| Artboard | Screen | What it shows |
|---|---|---|
| `Main.dc.html` | Ask (Coach tab default) | Question field at the top with a scope pill (This block · + Run), a row of lenses (Recovery · Fitness · Niggles · Compare · This week), and a short "NOTICED · TAP TO ASK" list of patterns the coach has spotted, each citing a number. Latest Read is one line at the bottom. |
| `Compose.dc.html` | Writing a question | A run attached as an evidence chip (`◆ MP TUE · SEP 8`), a lens selected, and a "THE COACH WILL READ" list showing exactly which run, memo, and context the answer will draw from. |
| `Reply.dc.html` | The reply | The existing Read format: your question quoted on top, coach byline, headline, one paragraph with inline `◆` chips, an italic soft question, "WHAT I CAN'T SEE", sources, confidence line, follow-up chips, and the pinned ask bar. |
| `Clarify.dc.html` | One question first | When the question is ambiguous ("my hamstring's been bothering me") the coach asks one narrowing question (sharp or achy?) with two tap answers, shows why it's asking, and lists the memos already on file. From `docs/coaching/principles.md`, "ask, don't answer". |
| `Asked.dc.html` | History | An index of past questions with the reply headline under each, filterable by lens. |

## What makes asking better

1. **Questions can point at something.** A run, this block, a lens.
   The scope travels with the question so the answer is precise.
2. **You see what the coach will read before you send.** Transparency
   builds trust and lets Maya fix a missing memo or wrong run first.
3. **Suggested questions come from her data, not a generic list.**
   "Right hamstring showed up in 3 memos since Aug 30" instead of
   "Tips for race day nerves?"
4. **Replies use the Read format**, so evidence chips, sources, and
   the confidence line come for free from the existing components.
5. **The coach asks back when it should.** One narrowing question, two
   tap answers, never a buffet.
6. **Every answer is kept** and can be reopened with the log it was
   read from.

## Rules held

- Post Run Drip tokens throughout (warm paper, ink, one coral per
  cluster, Crimson Pro / PT Serif / mono eyebrows, 24 px gutters,
  12 px cards, editorial rule). Values lifted from
  `design-system/colors_and_type.css` and `ui_kits/ios_app/tokens.css`.
- Target 4-tab nav (Log · Trends · Train · Coach).
- No prescriptions, no diagnoses, no "you should". Soft question at
  the end of every reply. Goal and race anchors carried silently.
- "Not medical advice" line on the niggle screen, verbatim from the
  design system voice guide.

## What it would take to build

The backend contract already exists: `DailyReadService.ask()` posts to
`coaching-agent` with `format = "editorial"` and decodes a
`CoachRead`. The reply screen renders with the components already in
`Coaching/Read/` (`ReadProse`, `EvidenceChip`, `CantSeeBlock`,
`SourcesPanel`, `ConfidenceBar`).

New work, roughly in order:

1. Ask front door view replacing the pinned bar (Main screen).
2. Scope + attachment on the request body (`scope`, `workout_id`,
   `lens`), and the "coach will read" preview (a cheap pre-flight that
   returns the source list without generating prose).
3. A `clarify` reply type from the agent: one question plus 2 tap
   answers.
4. An `asks` table (with RLS, per `docs/conventions/rls-checklist.md`)
   to persist question + reply for the history screen.
5. Eval cassettes for the editorial-ask prompt before any prompt
   change ships (hard rule 3).

## Files

- `parts/*.html` — the screen bodies; `parts/common.css` — the tokens.
- `build.mjs` — assembles `*.dc.html` from the parts (`node build.mjs`).
- `canvas.json` — artboard layout and the sticky notes on the canvas.

All copy is sample text written for Maya (3:28 PB, chasing 3:16).
Real answers come from her log.

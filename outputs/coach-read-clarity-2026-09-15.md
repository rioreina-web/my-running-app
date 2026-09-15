# Coach Read — clarity pass (2026-09-15)

**The brief:** "Take a look at the design of the Read and make it much
better at understanding what to say."

**The diagnosis:** the Read had two problems that looked like one.

1. **The prompt was clear about what *not* to say and vague about what
   to say.** v2's instruction for the paragraph was "4-6 sentences —
   what's working, what's drifting, what to watch." Everything else in
   the prompt was a ban list. So the model was excellent at avoiding
   "great job" and poor at knowing which of the 30 workouts in front of
   it mattered. Output drifted between a workout inventory, a pep talk
   and a data dump, and the athlete finished it without a clear sense
   of what the coach was telling her.
2. **The page framed the paragraph with chrome that said nothing.** A
   plate strip ("RUNNING LOG · FIG. 14"), an avatar byline, a
   "posted Thursday morning · 3 min read" signature, a dead "↗ HISTORY"
   link, and a separate confidence row. The 2026-05-28 decisions log
   already called this out ("Coach Read is currently too structured for
   what it needs to be") and specified the target: *eyebrow date +
   headline + 2-4 observation sentences + italic soft questions.*

This pass fixes both. It is Phase 7 of Maya's roadmap ("Voice-
disciplined Coach Read") brought forward, minus the live eval
recording, which needs a `GEMINI_API_KEY`.

---

## 1. What the Read says now — the v3 shape

`supabase/functions/_shared/prompts/daily-read.v3.ts`. The paragraph
has a fixed order, taken directly from the voice principles in
`maya-data-aware-journey-2026-05-28.md` § "How the AI reads the journey":

| Slot | Sentences | Rule |
|---|---|---|
| **Headline** | 1 line, ≤ 8 words, ends in a period | The one thing. "Tempos are coming down." Not a slogan, not a question. |
| **Feeling** | 1 (skip if no memos) | How she said she's been feeling, paraphrased from voice memos. Orientation, not the story. Never quotes her back (Q16). |
| **The work** | 1-3 | Quality sessions are the story. Name the session, the pace, the trend vs. earlier in the block. Cite the chip. Easy days only when they carry a signal on their own. |
| **The volume** | 0-1 | Weekly mileage in trend context. "Third week above 40," never "42 miles." |
| **The watch** | 0-1 | One specific thing, named precisely: a body part that's come up twice, a pace that slid, a slow session a hot memo explains. Struggle type is named (niggle / load + fatigue / heat / recovery deficit). Skipped on a good week — most weeks. |
| **Questions** | 1-2, own field | Soft questions to sit with. Never directives, never leading. Different from yesterday's. Empty on an empty account. |
| **Can't see** | optional | Unchanged from v2. |
| **Confidence** | level + plain clause | Sub-line is now something she can read: "6 runs and 3 memos, latest yesterday." |

Two rules run across every sentence: **one observation per sentence**,
and **every sentence carries a number or a name.** If a sentence
couldn't be checked against the log, it gets cut.

Voice rules carried in from the decisions log and now stated as
instructions rather than left implicit: warm-not-hype-not-negative (the
three registers, with the "real coach" one spelled out); default to
good or neutral; read the life context; **anchors and goals are silent**
(never state the PB, the goal time, the race date, a percentage, a
ratio, or "predicted"); peer energy with an explicit ban list on
directive verbs ("you should," "make sure to," "try to," "consider,"
"focus on").

The three coaching modes (PLAN / COACHED / SELF_COACHED) survive.
PLAN_MODE is softened one notch: the Read may compare a session to its
target and name what the plan has scheduled, but no longer "makes a
call on today's workout." The plan prescribes; the Read observes.

### What the model is given

The edge function (`coaching-daily-read/index.ts`) now pre-computes the
facts the Read is supposed to be about, so the model spends its effort
on the sentence rather than the arithmetic:

- **Weekly running volume**, six Monday-start weeks, cross-training
  excluded (Q23), current week flagged as partial.
- **Quality sessions** as their own compact list with paces side by
  side, alongside the full recent-runs list.
- **Today's date and weekday**, so "this week" and "Sunday's 16" are
  grounded on the athlete's calendar.
- **Yesterday's Read** (headline + questions) so the coach doesn't ask
  the same thing two days running.
- Memo section relabelled: read for feeling and life context,
  paraphrase, don't quote.
- Athlete-state and goal sections relabelled as *silent* — for the
  model's reading only.

The pure parts (parse, validate, normalize, volume math) moved to
`_shared/daily-read-shape.ts` with 13 offline unit tests. The validator
now also guarantees the headline's terminal period, caps questions at
two, and collapses an empty `cant_see` to null.

### Eval coverage

`_evals/cassettes/daily-read.v3/` — five stubs with rubrics, plus a new
`daily-read-v3-shape` custom check (headline length + period, 3-5
sentences, number-or-citation, no directives, no exclamation points,
0-2 non-leading questions) with its own 11 self-tests.

| Cassette | Pins |
|---|---|
| `001-maya-solid-week-feeling-first` | Shape on an unremarkable good week; feeling first; anchors silent; no drama |
| `002-hamstring-twice-surface-not-diagnose` | Pattern surfaced, never diagnosed, never prescribed |
| `003-hot-humid-tempo-life-context` | A 7:41 at 88°F is read as heat, not a fitness dip |
| `004-coached-mode-no-program-describe-only` | No targets, no predictions, confidence ≤ MEDIUM |
| `005-new-account-empty-state` | Fixed empty-state copy; empty questions |

**Not yet recorded.** Record with
`GEMINI_API_KEY=… deno run --allow-all _evals/record.ts daily-read.v3`
and commit the responses before pointing production traffic at v3. The
CI gate (`check_eval_coverage.py`) passes on the directory existing;
the rubrics only bite once recordings are in.

---

## 2. What the page shows now

`RunningLog/RunningLog/Coaching/Read/CoachReadView.swift`:

```
FROM YOUR COACH · TUE · SEP 15           coral eyebrow — who + when
Tempos are coming down.                  32pt display headline
[paragraph with inline ◆ / § chips]      feeling → work → volume → watch
TO SIT WITH                              ink-2 eyebrow
│ How did Sunday's 16 feel next to…      italic, coral-at-50% left bar
│ ONE DATA POINT                         cant-see block, gray bar
│ Mentioned once on Tuesday…
READ FROM · 5 WORKOUTS · 2 MEMOS  ▪▪▫ MEDIUM   one-line basis, expands
── · ──                                  editorial rule
[Ask the coach…]                         pinned ask bar (unchanged)
```

**Removed:** plate strip, dateline row, C-avatar byline, signature
line, "↗ HISTORY" (was a no-op), standalone `ConfidenceBar`.

**Added:** `SoftQuestionsBlock` (new file). Confidence pips and the
plain-language sub-line folded into `SourcesPanel`'s header/body, so
the level sits next to the evidence that earned it. Loading and error
states use `EmptyStateView` (hard rule #8) instead of ad-hoc text.

**Model:** `CoachRead.questions: [String]`, decoded tolerantly — a row
without the key (v2-era, or read before the migration is pushed)
decodes as `[]`. Decoding tests extended (present / missing / null /
non-string element / round-trip).

**Design-system notes:** the questions block uses the one sanctioned
coloured left border (the `CoachQuote` treatment) without curly quotes,
since they're the coach's own questions, not quoted speech. Coral
count per cluster: eyebrow (1), paragraph chips (chips are their own
cluster), questions bar (1), confidence pips (1). Everything else is
ink. The `Font.dripCaption` → `dripEyebrow` drift called out in
`coach-read-design-drift.md` §5-6 is fixed on the files this pass
touched; `EvidenceChip`, `DocChip`, `CantSeeBlock`, `DocDetailSheet`
still carry the old values.

---

## 3. Schema and deploy order

New migration `20260915120000_daily_coaching_reads_questions.sql`:
`ALTER TABLE daily_coaching_reads ADD COLUMN IF NOT EXISTS questions
JSONB NOT NULL DEFAULT '[]'`. Existing table, existing RLS — no policy
change. Reaches prod only via `supabase db push` from a committed SHA
(hard rule #9).

Deploy the migration before the function. If the order slips, the
function detects the missing column (Postgres 42703), logs loudly, and
falls back to writing the v2 shape so the athlete still gets a Read;
only that day's questions are lost.

---

## 4. Open, deliberately

- **On-demand generation.** The 2026-05-28 decision reversed Q15: the
  Read should generate when Maya taps, not every morning. The service
  and edge function still auto-generate on first open. Separate change;
  touches the cron + service, not the content.
- **Ask flow.** The ask bar still shows "coming soon." `coaching-agent`
  has no `format: "editorial"` handling yet. The "read my week through
  the recovery lens" capability depends on it.
- **History.** Removed rather than left dead. Comes back when there's a
  list view to open.
- **Pixel reference.** `Coach iOS.html` (Direction A) never arrived;
  this layout follows the written decision, not a mock.
- **Remaining tracking/weight drift** in the untouched chip files (see
  `coach-read-design-drift.md` §5-6).

---

## 5. How to judge it

Open the Coach tab with a week of data and read the Read once, cold.
You should be able to answer, without re-reading: *what is the coach
saying this week?* (headline), *what did it look at to say that?*
(the cited chips and the one-line basis), and *what does it want me to
think about?* (the two italic questions). If any of those three takes a
second pass, the Read has failed, regardless of how good the prose is.

# Niggles v2 — the dashboard

**Date:** 2026-08-23
**Status:** Prototype shipped, backend design proposed, nothing wired
**Prototype:** `web/src/app/design/niggles` → `/design/niggles`
**Supersedes in intent:** the `injuries` table surface
(`RunningLog/Analysis/InjuryPlate28.swift`, the ACTIVE ACHES tile in
`RunningLog/Trends/TrendsTabView.swift`, `web/src/app/(app)/injuries`)

---

## 1. The ask

> "A new version of niggles, automatically populated off the voice memos,
> with data on when they were mentioned, whether there are recurrences,
> and whether they've been resolved. The training session they get
> mentioned in should be able to show as a data overlay — or the mileage
> during that week — to see if there are patterns, whether it's after long
> runs or after certain workouts. Primarily a niggles dashboard, with some
> of the training able to overlay it."

Five requirements, in the order they were asked for:

| # | Requirement | Where it lands |
|---|---|---|
| 1 | Auto-populated from voice memos | §3 extraction contract |
| 2 | When each was mentioned | Fig. 02 timeline |
| 3 | Recurrences | §4 thread derivation, Fig. 04 cards |
| 4 | Resolution | §4 status rule, Fig. 04 cards |
| 5 | Training as an **overlay** on a niggles-primary surface | Fig. 02 overlay switcher, Fig. 03 tallies |

---

## 2. Why this is a rewrite, not a reskin

The niggles surface today is backed by the `injuries` table
(`20260218_create_injuries_table.sql`) and populated by `detectInjury()`
in `supabase/functions/_shared/injuries.ts`. Three things in that path
contradict the Niggles rules already written down in `CLAUDE.md`:

**It scores severity the athlete never gave.** `estimateSeverity()`
regex-matches the transcript and returns an integer 1–10, stored in a
`CHECK (severity >= 1 AND severity <= 10)` column. "Could barely walk"
becomes a 9. That is the exact coercion rule #2 forbids ("*Quote
verbatim… 'Could barely walk' is not coerced to a 7/10*") and the
severity assessment rule #3 forbids ("*never assess severity itself*").
`TrendsTabView.swift` already refuses to render it — the file carries a
comment explaining that the 0–10 risk tile was demoted to a bare count
for this reason. The rest of the stack still writes the number.

**Its vocabulary is 13 entries, not ~30, and it is not closed on the
output side.** `INJURY_KEYWORDS` covers calf, hamstring, quad, knee,
ankle, achilles, shin, hip, IT band, plantar, foot, back, glute. No
groin, no adductor, no peroneal, no hip flexor, no lower back as
distinct from back. Worse, the match is `lower.includes(keyword)` —
first keyword wins, one per memo. A memo saying "calf was fine but the
achilles was tight" records **calf**.

**It stores state, not events.** One row per body area, mutated in
place: severity raised on a worse mention, `resolved_at` stamped on a
healed one. The history is overwritten. You cannot ask "when was this
mentioned" of a table that only knows "how bad is it now" — which makes
requirements 2, 3 and 5 unanswerable from the current schema.

The fix is to make the store **append-only and verbatim**, and derive
everything else.

---

## 3. Data model

### 3.1 `body_mentions`

One row per *utterance*, never mutated. The athlete's words are the
payload; everything else is provenance.

```sql
CREATE TABLE body_mentions (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             TEXT NOT NULL,

    -- Closed vocabulary, enforced in the database, not just the prompt.
    body_part           TEXT NOT NULL REFERENCES body_part_vocabulary(part),
    side                TEXT NOT NULL DEFAULT 'unspecified'
                        CHECK (side IN ('left','right','both','unspecified')),

    -- 'mention'    the athlete raised it
    -- 'resolution' the athlete said it was gone
    kind                TEXT NOT NULL DEFAULT 'mention'
                        CHECK (kind IN ('mention','resolution')),

    -- VERBATIM. The athlete's own clause, lifted from the transcript.
    -- No paraphrase, no severity, no clinical term.
    quote               TEXT NOT NULL,

    mentioned_at        TIMESTAMPTZ NOT NULL,

    source              TEXT NOT NULL DEFAULT 'voice_memo'
                        CHECK (source IN ('voice_memo','coaching_chat','manual')),
    -- training_logs.id — the memo, and therefore the session it hangs off
    source_reference_id UUID,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

No `severity`. No `status`. No `updated_at` — rows do not change.

`body_part_vocabulary` is a seeded lookup table, ~30 rows, so the
closed vocabulary is a foreign key rather than a promise in a prompt.
A classifier that hallucinates "subtalar joint" gets a constraint
violation, and the insert is dropped rather than silently widening the
taxonomy.

Proposed seed, grouped for review:

> foot, plantar, toe, arch, heel, ankle, achilles, calf, shin, peroneal,
> knee, patella, IT band, quad, hamstring, adductor, groin, hip,
> hip flexor, glute, piriformis, lower back, upper back, ribs, chest,
> shoulder, neck, hand, wrist, elbow

Roughly 30, matching what `CLAUDE.md` already describes. The classifier
maps to the nearest entry or **omits** — it never invents.

### 3.2 RLS

Per `docs/conventions/rls-checklist.md`, RLS ships in the same
migration. Reads are athlete-scoped; writes are service-role only,
because inserts come from the memo pipeline, not the client — the same
posture as `coachable_moments` (hard rule #4). Manual entry from the
app goes through an edge function so the vocabulary check runs
server-side.

Do **not** copy the `OR auth.uid() IS NULL` escape hatch from
`20260219_fix_injuries_rls.sql`. That policy makes every row world-
readable to an unauthenticated caller, and body-part mentions are the
most sensitive rows in the product.

### 3.3 Migration path off `injuries`

`injuries` is not dropped in this change. It backs `injury-analysis`,
`injury-early-warning`, and `buildInjuryContext()` in the AI prompts.
Sequence:

1. Ship `body_mentions` and dual-write from `process-training-memo`.
2. Move the niggles read surfaces (iOS, web, Trends tile) to
   `body_mentions`.
3. Backfill `body_mentions` from `injuries` rows that have a
   `source_reference_id` — the transcript is still on the training log,
   so quotes can be recovered. Rows without one become a single
   `manual` mention with the stored `description` as the quote.
4. Reduce `injuries` to what the AI-context path actually needs, or
   retire it once `injury-early-warning` reads mentions directly.

---

## 4. Derivation — threads, recurrence, status

Nothing below is a model judgement. All of it is arithmetic over dates,
which is why it can be trusted to run unattended.

**Thread** = every row sharing `body_part` + `side`, in date order.
"L. Achilles" is one thread; "R. Achilles" is a different one.

**Status** — one rule, three outcomes:

| Status | Rule |
|---|---|
| `resolved` | the most recent row for the thread has `kind = 'resolution'` |
| `active` | a mention within the last **14 days** |
| `quiet` | no mention in 14+ days, and no resolution on file |

`quiet` deliberately is not `healed`. The system does not know that the
niggle went away — only that the athlete stopped mentioning it. The
dashboard says so out loud, in a "how a thread gets its status" block.

**Recurrence** = a gap of **21+ days** between consecutive mentions.
Rendered as *"Returned Jun 15, after 28 days quiet."* Below 21 days it
reads as one continuous complaint, not a return. Both thresholds are
constants in `niggles-data.ts` (`ACTIVE_WINDOW_DAYS`,
`RECURRENCE_GAP_DAYS`) so they are tunable in one place.

---

## 5. Auto-population from voice memos

### 5.1 Extraction contract

`process-training-memo` already reads the transcript and already writes
to the injury path. The change is what it extracts: a **7th field**,
`body_mentions`, an array (usually empty), replacing the
`detectInjury()` regex scan entirely.

```jsonc
"body_mentions": [
  {
    "body_part": "achilles",          // MUST be a vocabulary entry, else omit the row
    "side": "left",                    // left | right | both | unspecified
    "kind": "mention",                 // or "resolution"
    "quote": "achilles was tight the first mile, eased up after"
  }
]
```

Four constraints the prompt has to carry, all of them restatements of
rules already in `CLAUDE.md`:

1. **`quote` is a span of the transcript**, lightly trimmed to a clause.
   Not summarized, not de-slanged, not rated. If the athlete said
   "could barely walk", that is the quote.
2. **`body_part` comes from the supplied vocabulary list or the row is
   dropped.** Never coin a term. "Subtalar joint" maps to `ankle` or is
   omitted; it never becomes a new entry.
3. **Multiple mentions per memo are normal.** One memo, one array, N
   rows. The current one-keyword-wins scan is the bug this fixes.
4. **`kind: "resolution"` only on an explicit all-clear** from the
   athlete ("it's gone", "haven't felt it in weeks"). Improvement is not
   resolution — "better than last week" stays a `mention`.

Note what is *not* in the contract: no severity, no diagnosis, no
recommendation, no duration estimate. The classifier's entire job is
**which part, which side, said or resolved, exact words**.

### 5.2 Where it hangs off training

`source_reference_id` points at the `training_logs` row the memo was
attached to, which is what makes the overlay possible with no extra
storage. From that one FK the dashboard reads:

- **the session that day** — label, distance, pace, structure
- **the session in the 24 h before** — the long-run adjacency the ask is
  really about, since an achilles is usually reported the *morning
  after* the long run, on a rest or shakeout day
- **that week's volume** — mileage, long-run distance, quality count

A mention on a rest day is not context-free. It is a rest day *after
something*, and that is where the pattern lives.

### 5.3 The gate

This prompt change **cannot ship from this prototype.** Hard rule #3,
now mechanically enforced: `.github/scripts/check_eval_coverage.py`
fails any PR touching `supabase/functions/_shared/prompts/<name>.v<k>.ts`
unless `supabase/functions/_evals/cassettes/<name>.v<k>/` exists.

`process-training-memo.v1` **does** have a recorded cassette, so the
gate is satisfiable — but the existing cassette asserts the current
6-field output. Adding a 7th field means re-recording it and adding
behavioral cases for the four constraints above. Minimum set:

- multi-part memo ("calf was fine but the achilles was tight") → 1 row,
  achilles, not calf
- out-of-vocabulary term ("subtalar joint") → mapped or omitted, never
  invented
- severity language ("could barely walk") → verbatim in `quote`, no
  numeric anywhere in the output
- explicit all-clear → `kind: "resolution"`
- improvement without all-clear → still `kind: "mention"`
- gym soreness ("sore from leg day") → no row (this is Example 4 in the
  existing prompt, and it must keep behaving)

That work is the actual prerequisite, and it is not in this branch.

---

## 6. The prototype

`/design/niggles`, mock data, no Supabase. Mock rows are shaped exactly
like §3.1 (`niggles-data.ts` exports a `BodyMention` type with the same
fields), so wiring is a fetch swap rather than a rewrite. Mock athlete
is Maya, 16 weeks, May 4 – Aug 23 2026, 15 mentions across 5 body areas.

**Fig. 01 — tiles.** Active / quiet / resolved / returns. Counts only.
No risk score, no severity, no ranking.

**Fig. 02 — the timeline.** One row per body area, one dot per voice
log, across the block. This is the "when were they mentioned" answer,
and it is the surface the whole page is built around.

The training overlay is a **switcher**, not a fixed layer: weekly
mileage / long run / quality sessions / off. Bars render *behind* the
dots in paper-grey — training is literally the background. Tapping a
dot opens the voice log verbatim with three cells: that day's session,
the session 24 h before, that week's volume. Tapping a row label scopes
the page to one thread.

**Fig. 03 — where the dots fall.** The pattern question, answered as
tallies: *"6 / 7 mentions came within 24 hours of a long run"*, plus
mentions by session type and by weekly-volume band. Scoped to the
selected thread or across all of them.

This is the section that needed the most care. Rule #3 says surface,
never interpret — but the ask is explicitly for pattern-finding, and
those are not in conflict. **Counting is observation; the causal
sentence is the interpretation.** So the page counts, and stops. It
says 6 of 7 landed within 24 h of a long run; it never says the long
runs are doing it, never says to change the long run, never names a
condition. The section caption carries the line: *"Counts, not
conclusions. The system does not finish the sentence."*

**Fig. 04 — the threads.** Per body area: mention count, first said,
last said, days carried, recurrence gaps, resolution (in the athlete's
words, with days-to-resolution), and the verbatim log with the session
and week volume under each quote.

Footer keeps the liability line the design system already specifies:
*"Not medical advice. If anything gets sharper, see a clinician."*

### Verified

`npx tsc --noEmit` clean, `eslint` clean, `next build` succeeds and
`/design/niggles` prerenders static. Rendered and driven in Chromium —
overlay switching, thread scoping, dot selection and the scoped tallies
all behave. Screenshots taken against the prerendered output.

Note: `/design/*` sits behind auth in `src/middleware.ts` (as
`/design/training-summary` already does), so reviewing this on a
deployment needs a logged-in session.

---

## 7. Open calls

1. **Does the athlete get Fig. 03 at all?** Co-occurrence counts are the
   closest this product comes to the line in rule #2. The counts are
   honest, but a runner who sees "6 / 7 after long runs" may act on it
   without a clinician. Options: ship as-is; coach-only; or gate behind
   a minimum mention count so single data points never form a "pattern".
   **Recommendation: ship as-is with the count floor** — Maya is
   self-coached, there is no coach to route it to, and withholding a
   tally of her own words is more paternalistic than the rule requires.
2. **Where does this live in the 4-tab IA?** `CLAUDE.md` has niggles as
   a Trends tile plus inline chips on Log. This dashboard is the
   tile's detail view — Trends → NIGGLES → here. It is not a sixth tab.
3. **iOS parity.** The prototype is web because that is where the
   design-preview convention lives. The real surface is iOS
   (`InjuryPlate28.swift` and friends). The timeline needs a Swift
   Charts implementation; it is the only genuinely new primitive here.
4. **`side` on legacy rows.** `detectInjury()` writes `'unknown'`;
   the new schema uses `'unspecified'`. Backfill maps one to the other.
5. **Retention.** Mentions are append-only and never expire. Should the
   dashboard window default to the current block rather than all time?
   The prototype shows 16 weeks.

---

## 8. What is not in this branch

- No migration. No `body_mentions` table, no vocabulary table, no RLS.
- No prompt change, and no eval cassettes — see §5.3.
- No edge-function change. `detectInjury()` still runs as it does today.
- No iOS work.
- Nothing removed from the `injuries` path.

The prototype is a design artifact and a schema proposal. Everything in
§3–§5 is the implementation plan, not the implementation.

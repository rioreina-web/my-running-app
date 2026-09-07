# Voice-first runner onboarding — build spec

*Authored 2026-08-11. Supersedes the onboarding half of
`athlete-onboarding-redesign.md` (that doc covers joining a **coach's plan**;
this one covers a **new account's first five minutes**). Depends on
`outputs/strava-day0-race-detect-spec-2026-07-15.md`.*

---

## 0 · The one-paragraph version

A new runner talks for four minutes across five short prompts. We transcribe
each take, extract a structured draft profile, and then ask them to confirm
exactly **three** things — goal, training days, injury status. Everything else
lands as soft profile fields the coach can use immediately and refine later.
Before they ever speak, we've already read their Strava, so the voice prompts
only ask what the data cannot know. The raw takes are kept forever, so a better
extractor next year can re-mine the same audio without asking anyone anything.

---

## 1 · What ships today, and why it isn't enough

`RunningLog/RunningLog/App/OnboardingView.swift` — 532 LOC, four steps.

| Step | Collects | Reality |
|---|---|---|
| 0 · Welcome | nothing | marketing copy |
| 1 · Connect | HealthKit (real), Strava, Manual | **Strava is `stravaConnected.toggle()`** — a fake boolean. Manual is a static `READY` label. |
| 2 · Goal | distance chip + H/M/S wheels | inserts `user_goals` with `goal_type` and `target_time` — **neither column exists**. It's a bare `try? await`, so it fails silently. Nobody has a goal. |
| 3 · Ready | nothing | three habit tips |

`SKIP ↗` in the header sets `hasCompletedOnboarding = true` immediately, and
that flag is **device-local `@AppStorage`** — not server state. Reinstall
replays onboarding; a second account on the same device skips it entirely.

Net: **onboarding currently persists nothing.** No display name, no pace
profile, no race, no backfill kick, no call to `interpret-goal` /
`build-athlete-profile` / `build-pace-profile`. (Timezone is the one exception
and it doesn't come from onboarding — `AthleteSettingsService.syncDeviceTimezone()`
in `Services/Supabase.swift:465` upserts `athlete_settings` on every launch.
CLAUDE.md still lists this as an open item; it isn't.)

The product's whole thesis — fusing what a runner *says* with what their watch
*records* — has no day-0 expression. A runner arrives, and we know nothing
about them that a GPS file couldn't tell us.

---

## 2 · The seven topics, and who actually answers them

The instinct is to ask all seven. The correct move is to ask only what the data
can't answer, because every question the data could have answered is a question
that makes the product look dumb.

| # | Topic | Best source | Confirmed? |
|---|---|---|---|
| 1 | Running history / background | **voice** | no — soft field |
| 2 | Recent performances | **backfill** (Strava 365d) | shown in read-back |
| 3 | Lifetime PRs | **voice**, cross-checked vs backfill | no — soft, surfaced |
| 4 | Training history (volume, structure) | **backfill** + voice for the pre-app years | no — soft |
| 5 | Injury history | **voice only** — no data source exists | **YES — hard confirm** |
| 6 | Goals + motivations | **voice only** | **YES — goal hard, motivation soft** |
| 7 | Preferred days + session types | backfill infers days, voice gives the *why* | **YES — hard confirm** |

Three confirmations. Not seven. Every extra confirmation screen is a drop-off
point, and the three chosen are the three where a wrong value does real damage:
a wrong goal miscalibrates every pace in the app, wrong training days
miscalibrate every plan, and a missed injury is the one failure mode that can
hurt somebody.

---

## 3 · The flow

```
  SIGN UP
     │
     ▼
  ┌─────────────────────────────────────────────┐
  │ PHASE 0 · CONNECT                           │  ~30s
  │ Apple Health (real today)                   │
  │ Strava OAuth (currently fake — must build)  │
  │ → kicks 365-day backfill, mode:"onboarding" │
  └─────────────────────────────────────────────┘
     │  (backfill runs in background from here on)
     ▼
  ┌─────────────────────────────────────────────┐
  │ PHASE 1 · THE READ-BACK                     │  ~45s
  │ "Here's what we found."                     │
  │  · races detected → confirm / edit / not    │
  │  · 12-week avg mileage                      │
  │  · the days you actually run                │
  │ Empty state if no connection: skip straight │
  │ to Phase 2, nothing is broken.              │
  └─────────────────────────────────────────────┘
     │
     ▼
  ┌─────────────────────────────────────────────┐
  │ PHASE 2 · TALK                              │  ~4 min
  │ Five prompt cards. Each records separately. │
  │ Each is skippable. Each has a "type it"     │
  │ fallback. Progress is a coverage ledger,    │
  │ not a step counter.                         │
  └─────────────────────────────────────────────┘
     │  (extraction runs per-card, in background)
     ▼
  ┌─────────────────────────────────────────────┐
  │ PHASE 3 · CONFIRM — three screens only      │  ~60s
  │  A · Your goal        (pre-filled from #5)  │
  │  B · Your week        (pre-filled from #4   │
  │                        + backfill)          │
  │  C · Your body        (pre-filled from #3)  │
  └─────────────────────────────────────────────┘
     │
     ▼
  ┌─────────────────────────────────────────────┐
  │ THE PROFILE CARD                            │
  │ "This is what we know about you."           │
  │ Everything extracted, sourced, editable.    │
  │ Becomes a permanent surface in Settings.    │
  └─────────────────────────────────────────────┘
     │
     ▼
  LAND ON LOG · depth 2, populated Trends
```

**Why five cards and not one long memo.** A single "tell us about yourself"
recording is intimidating, produces rambling, and fails atomically — one bad
upload loses everything. Five 30–60 second takes are each easy to start, each
independently extractable, each independently retryable, and each maps to a
known slice of the schema so the extractor is asked a narrow question rather
than a broad one. Narrow questions are the entire reason the existing memo
extractor is reliable.

---

## 4 · The five prompts

Copy is final. Brand voice: declarative, no hype, no emoji, no exclamation
points, second person, permission to be incomplete built into every prompt.

### Card 1 · `history`
> **HOW LONG YOU'VE BEEN AT THIS**
> How long, and what shape it's taken. Cross country, road, came to it late,
> took five years off — whatever's true.
>
> *~30 seconds*

### Card 2 · `bests`
> **THE NUMBERS YOU'D TELL A COACH**
> Your personal bests. The ones you're proud of, and the ones you think are
> soft. Distance and time — approximate is fine, we'll ask before we use them.
>
> *~45 seconds*

### Card 3 · `body`
> **WHAT'S GONE WRONG BEFORE**
> Injuries, the niggle that always comes back, anything you're managing right
> now. We ask because load is the one thing we won't guess at.
>
> *~45 seconds*

### Card 4 · `week`
> **THE WEEK YOU ACTUALLY RUN**
> How many days, which days, and what a normal week looks like. Then: what kind
> of running do you actually like doing?
>
> *~60 seconds*

### Card 5 · `chasing`
> **WHAT YOU'RE CHASING**
> The goal, and why that one. A date if you have one. "I don't know yet" is a
> real answer.
>
> *~45 seconds*

**Card ordering is deliberate.** History first because it's the easiest thing a
person can talk about and warms them up. Goal last because it's the one they'll
have thought hardest about and it leaves them ending on intent, not injury.

**Between cards, show what we heard.** After each take completes extraction
(~8–12s), the card collapses into a one-line receipt — `Heard: 11 years, XC
background, two years off after 2023.` This is the same two-stage reveal
`process-training-memo` already does (transcript at ~6–10s, analysis after) and
it is the single biggest trust-builder in the flow. A runner who sees take 1
land correctly will give you takes 2 through 5.

---

## 5 · Data model

### 5.1 · `onboarding_takes` — the durable raw layer

One row per recorded card. **This table is the reason the beta is developable
into a better product**: the resolved profile is a derived artifact, but the
audio and the transcript are ground truth, and a v2 extractor can re-run over
every take ever recorded without asking a single runner anything again.

```sql
CREATE TABLE IF NOT EXISTS public.onboarding_takes (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id          TEXT NOT NULL,              -- auth.uid()::text convention
    prompt_key       TEXT NOT NULL
        CHECK (prompt_key IN ('history','bests','body','week','chasing')),
    attempt          INTEGER NOT NULL DEFAULT 1, -- re-records increment
    audio_path       TEXT,                       -- training-memos/{uid}/{uuid}.m4a
    transcript       TEXT,
    transcript_provider TEXT,                    -- groq | openai | gemini | typed
    typed_input      TEXT,                       -- when the runner types instead
    extraction       JSONB,                      -- §6 schema, per-card slice
    extractor_version TEXT,                      -- 'onboarding-profile.v1'
    status           TEXT NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending','transcribed','completed','failed','skipped')),
    -- retry state lives on the row itself; see §8 for why there is no
    -- separate queue table
    attempts         INTEGER NOT NULL DEFAULT 0,
    max_attempts     INTEGER NOT NULL DEFAULT 3,
    next_retry_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_attempted_at TIMESTAMPTZ,
    error            TEXT,
    duration_seconds NUMERIC(5,1),
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    completed_at     TIMESTAMPTZ
);

CREATE UNIQUE INDEX onboarding_takes_unique
    ON public.onboarding_takes (user_id, prompt_key, attempt);
CREATE INDEX onboarding_takes_user
    ON public.onboarding_takes (user_id, created_at DESC);
```

RLS: service-role `FOR ALL`; owner `SELECT` + owner `INSERT` (the client owns
the insert, same as `training_logs`). No owner `UPDATE` — extraction is
service-role only, so a client cannot forge an extraction.

### 5.2 · `runner_profiles` — the resolved profile

One row per user. Sections are JSONB so the schema can grow without a migration
per field; provenance is per-field so any consumer can ask *how do we know
this*.

```sql
CREATE TABLE IF NOT EXISTS public.runner_profiles (
    user_id          TEXT PRIMARY KEY,
    schema_version   INTEGER NOT NULL DEFAULT 1,

    background       JSONB NOT NULL DEFAULT '{}',  -- §6.1
    bests            JSONB NOT NULL DEFAULT '[]',  -- §6.2
    training          JSONB NOT NULL DEFAULT '{}', -- §6.3
    body             JSONB NOT NULL DEFAULT '{}',  -- §6.4
    availability     JSONB NOT NULL DEFAULT '{}',  -- §6.5
    intent           JSONB NOT NULL DEFAULT '{}',  -- §6.6
    preferences      JSONB NOT NULL DEFAULT '{}',  -- §6.7

    field_provenance JSONB NOT NULL DEFAULT '{}',  -- §5.3
    coverage         JSONB NOT NULL DEFAULT '{}',  -- §7

    onboarding_completed_at TIMESTAMPTZ,           -- SERVER-SIDE completion
    last_reviewed_at TIMESTAMPTZ,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

`onboarding_completed_at` **replaces the device-local `@AppStorage` flag.**
That's a bug fix riding along: today a reinstall replays onboarding and a
second account on one device skips it.

### 5.3 · Provenance — the part that makes everything else safe

Every leaf field carries an entry in `field_provenance`, keyed by dotted path:

```jsonc
{
  "bests[0].time_seconds": {
    "source": "voice",              // voice | backfill | tapped | inferred | coach
    "confidence": "low",            // high | medium | low
    "take_id": "…uuid…",
    "verbatim": "somewhere around eighteen-thirty for a 5k, I think",
    "confirmed_at": null,           // non-null once the runner taps confirm
    "extractor_version": "onboarding-profile.v1"
  }
}
```

Three rules follow from this, and they are the load-bearing safety properties
of the whole feature:

1. **Nothing with `source: "voice"` and `confirmed_at: null` may drive a
   number the runner sees as fact.** It can seed a confirm screen. It cannot
   set a pace zone.
2. **A hedge stays a hedge.** If the transcript says *"around eighteen-something
   for 5k"*, the extraction is `{ time_seconds: null, time_text: "≈18:xx",
   confidence: "low" }` — never `18:30`. Inventing precision the runner didn't
   give is the same class of error as the number-fabrication guard already
   enforced in `narration-guard.ts`, and it deserves the same discipline.
3. **Backfill beats voice on anything the watch recorded.** If the runner says
   "I run about 40 a week" and 12 weeks of Strava says 31, we store both, show
   the runner both, and let them settle it. We never silently overwrite the
   thing they said.

### 5.4 · What writes through to existing tables

The profile is not a parallel universe. The three confirmed sections write into
the tables that already drive the app:

| Confirmed | Writes to | Via |
|---|---|---|
| Goal | `user_goals` (`raw_statement`, `interpretation`, `target_race_distance`, `target_time_seconds`, `athlete_confirmed`, `confirmed_at`) | existing `interpret-goal` fn — **currently never called from onboarding** |
| Goal → paces | `athlete_pace_profiles` (`goal_race_distance`, `goal_time_seconds`) | existing `build-pace-profile` — **needs a mapping layer, see below** |
| PRs the runner confirms | `race_results` with `source='athlete'`, `confirmed_at=now()` | direct insert — athlete INSERT policy exists |
| Detected races confirmed in Phase 1 | `race_results` `source='detected'` → set `confirmed_at` | needs `confirm-races` fn (specced, **not built**) |
| Current niggles | `body_mentions` (`source='onboarding'`, `training_log_id` NULL) | **extended** `_shared/niggleWriter.ts` |
| Injury history | `injuries` | direct insert — **needs a CHECK widened first** |
| Training days | `runner_profiles.availability` — and read by `subscribe-to-plan` as the default for `preferred_quality_dows` / `rest_dows` / `long_run_dow` (same `0 = Mon` convention) | closes the loop with `athlete-onboarding-redesign.md` §4 |
| Display name | `athlete_settings.display_name` | exists, unused at onboarding |

**Five constraints that will bite you.** Each one was verified against the
migrations, and each one is a migration or a mapping layer, not a nicety:

1. **`athlete_pace_profiles.user_id` is `UUID`**, not `TEXT` — the only table in
   this set that breaks the `auth.uid()::text` convention. Cast at the boundary
   or you get a silent zero-row write.
2. **`athlete_pace_profiles.goal_race_distance` is a five-value CHECK with
   capital K**: `('mile','5K','10K','half','marathon')`. The extraction schema
   in §6.2 uses lowercase and has twelve values. **A mapping layer is
   required** — `3k`, `8k`, `12k`, `15k`, `10mile`, `50k`, `other` have nowhere
   to go, and `5k` → `5K` is a case change the CHECK will reject.
3. **`injuries.source` is `CHECK (source IN ('voice_memo','coaching_chat',
   'manual'))`.** `source='onboarding'` violates it. Widen the constraint in
   Phase 1.
4. **`body_mentions` unique index is `(user_id, training_log_id, body_area)`.**
   With `training_log_id` NULL, Postgres treats NULLs as distinct, so
   `onConflict` never matches and **re-recording card 3 duplicates every
   current niggle**. Add a partial unique index
   `(user_id, body_area) WHERE training_log_id IS NULL`, or use
   `NULLS NOT DISTINCT`.
5. **`race_prs` does not filter on `confirmed_at`.** Anything inserted into
   `race_results` is immediately a quoted PR. That is only safe because §5.3
   rule 1 forbids inserting anything unconfirmed — say it out loud in code
   review, because the view will not enforce it for you.

---

## 6 · The extraction contract

New prompt file: `supabase/functions/_shared/prompts/onboarding-profile.v1.ts`,
following the existing `loadPrompt(name, vars)` convention. Model:
`gemini-2.5-flash`, same as `process-training-memo` and `interpret-goal`.

**The extractor is called once per take, with the prompt key**, and returns
only that card's slice. This is the key design choice: five narrow extractions
beat one wide one, because a narrow prompt can carry worked examples and
guardrails for its own failure modes without a 4,000-token system prompt.

### 6.1 · `history` → `background`

```jsonc
{
  "years_running": number | null,
  "years_running_text": string | null,   // "about a decade", when not a number
  "background": ["cross_country"|"track"|"road"|"trail"|"ultra"|"triathlon"
                |"other_sport"|"none"],
  "background_verbatim": string | null,
  "gaps": [{ "approx_years": string, "reason": string | null }] | null,
  "self_described_level": "new"|"returning"|"recreational"|"competitive"
                        |"elite"|null,
  "confidence": "high"|"medium"|"low"
}
```

### 6.2 · `bests` → `bests[]`

```jsonc
[{
  "distance_key": "mile"|"3k"|"5k"|"8k"|"10k"|"12k"|"15k"|"10mile"
                 |"half"|"marathon"|"50k"|"other",
  "time_seconds": number | null,        // null whenever the runner hedged
  "time_text": string,                  // "18:30" or "≈18:xx" or "under 3 hours"
  "approx_year": number | null,
  "context": string | null,             // "college", "before kids"
  "soft": boolean,                      // runner called it beatable
  "confidence": "high"|"medium"|"low"
}]
```

`distance_key` deliberately mirrors the `race_results_distance_chk` CHECK
constraint exactly. **The insert is still not free**, though — `race_results`
requires `race_date NOT NULL` (extraction only gives `approx_year`), demands at
least one of `official_time_seconds` / `recorded_time_seconds` bounded
120–86400, and requires `distance_meters` when `distance_key = 'other'`.

Which means: **a hedged best is unstorable, by design.** *"around eighteen-something
for 5k"* has `time_seconds: null`, so it cannot become a `race_results` row. It
lives in `runner_profiles.bests` as `time_text: "≈18:xx"` with
`confidence: "low"` until the runner pins it down. That is the correct
behaviour — the alternative is inventing `18:30` and quoting it back as a PR —
but the confirm screen has to make pinning it down easy, and `approx_year`
needs a date fallback (Jan 1 of that year, flagged) before any insert.

### 6.3 · `week` → `training` + `availability` + `preferences`

```jsonc
{
  "training": {
    "typical_days_per_week": number | null,
    "typical_weekly_miles": number | null,
    "typical_weekly_miles_text": string | null,
    "structure": ["long_run"|"workout"|"double"|"strength"|"cross_training"] ,
    "coached": boolean | null,
    "confidence": "high"|"medium"|"low"
  },
  "availability": {
    "run_dows":      [0..6] | null,      // 0 = Monday
    "quality_dows":  [0..6] | null,
    "long_run_dow":  0..6   | null,
    "rest_dows":     [0..6] | null,
    "constraints": [{ "kind": "work"|"family"|"travel"|"facility"|"other",
                      "text": string }] | null,
    "confidence": "high"|"medium"|"low"
  },
  "preferences": {
    "enjoys":  ["track"|"tempo"|"hills"|"long_run"|"easy"|"trail"|"group"
               |"racing"|"solo"],
    "dislikes":["track"|"tempo"|"hills"|"long_run"|"easy"|"trail"|"group"
               |"racing"|"solo"],
    "verbatim": string | null
  }
}
```

### 6.4 · `body` → `body`

**The highest-stakes extraction in the flow.** It reuses the existing closed
vocabulary — `supabase/functions/_shared/bodyVocabulary.ts`, 26 canonical body
areas, four severity hints (`sharp`/`pain`/`sore`/`tight`), longest-synonym-wins
matching, diagnoses deliberately absent so `"ITBS"` falls through to `null`.

```jsonc
{
  "current": [{
    "body_area": string,               // MUST normalize via bodyVocabulary
    "side": "left"|"right"|null,       // "both"/"bilateral" → null, by design
    "severity_hint": "sharp"|"pain"|"sore"|"tight",
    "verbatim": string,
    "limiting": boolean                // is it changing what they run today
  }] | null,
  "history": [{
    "body_area": string,
    "side": "left"|"right"|null,
    "approx_when": string | null,      // "last spring", "2022"
    "time_lost_text": string | null,   // "six weeks off"
    "recurring": boolean,
    "verbatim": string
  }] | null,
  "nothing_reported": boolean,         // explicit "nothing's wrong"
  "confidence": "high"|"medium"|"low"
}
```

Three guardrails, carried verbatim into the prompt:

- **Detection, not diagnosis.** Record the body part and the runner's words.
  Never name a condition they didn't name. This is already the product's
  standing rule for niggles and it does not relax at onboarding.
- **Absence of complaint is not an all-clear.** Silence sets nothing.
  `nothing_reported: true` requires an explicit statement — the same rule Ask v2
  §4 applies to `resolve_niggle`.
- **Unmappable areas are dropped, not invented.** If `normalizeBodyMention()`
  returns null, the mention is logged and discarded. It is never coerced into
  the nearest neighbour.

> ⚠️ **iOS/backend vocabulary divergence.** `BodyArea` in
> `RunningLog/RunningLog/Models/InjuryModels.swift` has **13 cases**; the backend
> vocabulary has **26**. A `soleus`, `piriformis`, `si joint`, `lower back`,
> `hip flexor`, `adductor`, `groin`, `heel`, `toe`, `top of foot`, `peroneal`,
> `neck` or `shoulder` mention will fail `BodyArea(rawValue:)` and render as
> nothing. **Fix this before onboarding ships**, because onboarding is the
> single richest source of body-area mentions the app will ever get — a
> lifetime of injury history in one take. Precedent:
> `20260715130000_niggle_arch_to_plantar.sql` fixed exactly this class of bug
> for one area; the other 13 were never addressed.

### 6.5 · `chasing` → `intent`

```jsonc
{
  "goal_statement": string,             // verbatim, ≤500 chars
  "scope": "running_goal"|"running_constraint"|"adjacent"|"out_of_scope",
  "target": {
    "distance_key": string | null,
    "time_seconds": number | null,
    "time_text": string | null,
    "named_race": string | null,
    "target_date_text": string | null   // "Chicago in October"
  } | null,
  "undecided": boolean,                 // "I don't know yet" is a real answer
  "motivations": [{
    "kind": "time_goal"|"health"|"community"|"headspace"|"comeback"
           |"competition"|"habit"|"proving"|"other",
    "verbatim": string
  }],
  "confidence": "high"|"medium"|"low"
}
```

`scope` and the out-of-scope taxonomy are lifted from the shipped
`parse-goal.v1` prompt so the two stay consistent — weight, body-comp,
nutrition, lifting numbers and non-running life goals are out of scope and must
**not** be reframed into a running goal. Card 5's `goal_statement` is then
handed to the existing `interpret-goal` function rather than re-parsed, which
means named-race recognition and the `race-intel` side-effect come for free.

---

## 7 · The coverage ledger — progress without a step counter

Phase 2 does not show "3 of 5." It shows what's known and what's still blank,
because a runner who skips card 2 has not failed at anything.

```jsonc
"coverage": {
  "history":  "covered" | "partial" | "empty",
  "bests":    "covered" | "partial" | "empty",
  "body":     "covered" | "partial" | "empty",
  "week":     "covered" | "partial" | "empty",
  "chasing":  "covered" | "partial" | "empty",
  "score": 0.0-1.0
}
```

**"Done enough" is `body` + `chasing` covered, plus either `week` covered or
`week` inferable from ≥ 4 weeks of backfill.** That's the minimum to run the
coach safely. Everything else is upside, and the profile card nags gently
rather than the flow blocking.

The ledger is also what a returning-later prompt reads: *"We still don't know
what you're chasing"* is a far better re-engagement hook than a generic
notification, and it can only exist because coverage is modelled explicitly.

---

## 8 · Edge function — `process-onboarding-memo`

New function. Deliberately **not** a branch inside `process-training-memo` —
that file is 1,246 LOC with a sibling-GPS merge, a splits fidelity ladder, and
a quota ladder that has nothing to do with onboarding. Forking it would be the
wrong kind of reuse.

**What it reuses (extract to `_shared/`, don't copy):**

| Piece | Where it lives today | Action |
|---|---|---|
| Transcription ladder (Groq `whisper-large-v3` 12s → OpenAI `whisper-1` 30s → Gemini) | inline at `process-training-memo/index.ts:669–739` | **extract to `_shared/transcribe.ts`** — both callers use it |
| Audio upload | `upload-voice-memo` fn, private bucket `training-memos` | reuse **unchanged** |
| Body-area normalization + severity | `_shared/bodyVocabulary.ts` (26 areas, 4 severities) | reuse **unchanged** |
| Niggle row building | `_shared/niggleWriter.ts` | **extend** — `trainingLogId` is a non-optional `string`, `source` is hardcoded `"memo_llm"`, and it reads `extracted.niggles`. All three need to become parameters. |
| Goal parsing | `interpret-goal` fn | call it, don't reimplement |
| Prompt loading | `loadPrompt(name, vars)` | same convention — **but a new prompt also needs a static `import` plus a `REGISTRY` entry in `_shared/prompt-library.ts`, or `loadPrompt` throws** |
| Rate limiting | `_shared/rateLimit.ts` | see the quota note below — the signature is not what it looks like |
| Auth + IDOR guard | `requireAuthOrServiceRole` (`_shared/auth.ts:123`) + owner re-fetch | same pattern, on `onboarding_takes` |

**Why there is no new row in `voice_processing_jobs`.** The obvious move is to
widen its `kind` CHECK to `'onboarding'` and be done. It doesn't work:
`training_log_id` is `UUID NOT NULL REFERENCES training_logs(id)` **and**
`UNIQUE`. An onboarding take has no training log, so you'd have to drop a NOT
NULL and rework a unique constraint that is currently doing real dedupe work
for memos. Retry state goes on `onboarding_takes` itself (§5.1) and a small
`drain-onboarding-takes` cron sweeps `status='pending' AND next_retry_at < now()`.
Same pattern, same backoff, none of the constraint surgery.

**Flow:**

```
POST /process-onboarding-memo  { take_id, user_id }
  ├─ auth: requireAuthOrServiceRole + re-fetch take, 404 on owner mismatch
  ├─ short-circuit: status='completed' → 200 "already processed"
  ├─ short-circuit: status='pending' & created <2min & in flight → 409
  ├─ quota: enforceFeatureRateLimit(userId, "onboarding_memo", corsHeaders, opts)
  │         — separate bucket from voice_memo so a chatty onboarding
  │           doesn't eat the day's memo allowance
  ├─ transcribe (or take typed_input verbatim, provider='typed')
  ├─ WRITE { transcript, status:'transcribed' }   ← two-stage reveal
  ├─ extract with onboarding-profile.v1 + prompt_key
  ├─ WRITE { extraction, status:'completed', completed_at }
  └─ merge into runner_profiles (§9)
```

The two-stage write matters as much here as it does in the memo path. A runner
sees their own words on screen ~8 seconds after they stop talking, then the
structured receipt lands a few seconds later. That gap is where trust is either
built or lost.

> ⚠️ **The quota signature is not what it looks like.** It's
> `enforceFeatureRateLimit(userId, feature, corsHeaders, opts)` — the third
> argument is CORS headers, not a limit. Limits live in the `FEATURE_LIMITS`
> table in `_shared/rateLimit.ts:232`, and **an unregistered feature key
> silently falls back to `coaching` — 5/day on the free tier**, which would
> throttle a five-card onboarding at card five. Phase 1 must register
> `onboarding_memo` in `FEATURE_LIMITS`, in `MONTHLY_LLM_CAPS` (`:404`), **and**
> in `_shared/rateLimit.contract.test.ts` (`:169` pins that every feature is
> registered — the test fails otherwise).

**Direct-invoke plus retry state, both.** The client invokes directly for
latency; the row's own `next_retry_at` is the insurance. This is exactly the
lesson of `20260806220000_enqueue_voice_job_on_memo_attach.sql` — the attach
path had no outbox row, so a single failed direct-invoke stranded a log at
`processing_status='pending'` forever, showing a permanent spinner. Do not
repeat that.

---

## 9 · The merge — takes → profile

A pure function, `_shared/profileMerge.ts`, so it's unit-testable without a
network:

```ts
mergeProfile(
  existing: RunnerProfile,
  take: OnboardingTake,
  backfill: BackfillSummary
): { profile: RunnerProfile, provenance: ProvenanceDelta }
```

Precedence, highest first:

1. **`confirmed_at` non-null** — the runner tapped it. Nothing overwrites this,
   ever, including a later voice take. A re-record proposes; it does not
   overwrite a confirmation.
2. **`source: "tapped"`** — typed or picked in a confirm screen, not yet
   submitted.
3. **`source: "backfill"`** — for anything the watch measured: weekly volume,
   days actually run, race times from GPS.
4. **`source: "voice"`, `confidence: "high"`**
5. **`source: "voice"`, `confidence: "medium" | "low"`**
6. **`source: "inferred"`**

**Conflicts are surfaced, not resolved.** When voice and backfill disagree past
a threshold — the runner says 40 mpw, Strava says 31 — the merge writes both
and sets a `conflict` marker. The confirm screen shows:

> *You said about 40 a week. Your last 12 weeks average 31.*
> `[ 40 is right ]  [ 31 is right ]  [ neither — ___ ]`

Silently picking one is how a product loses an argument it never told the user
it was having.

---

## 10 · The three confirm screens

### A · Your goal

Pre-filled from card 5. Distance chip row + H/M/S pickers, matching the
existing step-2 controls so nothing new has to be designed. Adds:

- the runner's own words, quoted above the controls, italic — *"I want to break
  three hours at Chicago"*
- named race and date when `interpret-goal` recognized one
- `undecided: true` → a real "Not sure yet" state that writes nothing and does
  not block. **Do not force a goal.** A fabricated goal poisons every pace in
  the app, and "I don't know yet" is the honest state for a large share of
  runners.

Writes: `user_goals` (with `athlete_confirmed = true`, `confirmed_at`), then
`interpret-goal`, then `build-pace-profile`.

### B · Your week

Pre-filled from card 4, overlaid with what the backfill actually shows.

- 7-day selector: days you run · days you'd do hard work · long run day
- the backfill overlay as a faint second row — *"the days you actually ran, last
  8 weeks"* — which is the moment the product proves it was paying attention
- weekly volume, with the conflict UI from §9 when voice and data disagree

Writes: `runner_profiles.availability` (confirmed), and the defaults that
`subscribe-to-plan` will later read for `rest_dows` / `preferred_quality_dows` /
`long_run_dow`.

### C · Your body

Pre-filled from card 3. Two lists, visually distinct:

- **Right now** — chips, each with body area, side, and the runner's own words
  underneath. Tap to remove. Add a missing one from the closed vocabulary.
- **History** — same, but dated and marked recurring where the runner said so.

An explicit **"Nothing right now"** button that sets `nothing_reported: true`.
It must be a deliberate tap, never a default, and never inferred from silence.

Writes: `body_mentions` (`source='onboarding'`, `training_log_id` NULL) for
current, `injuries` for history.

---

## 11 · Failure modes

| Failure | Behaviour |
|---|---|
| Runner won't talk at all | Every card has **`Type it instead`**. Typed input skips transcription entirely (`provider='typed'`, zero transcription cost) and runs the same extractor — the exact pattern the typed-note path already uses. |
| Runner skips everything | Lands with `coverage.score = 0`. App works at depth 0. Profile card shows what's missing; the coach asks for it later, in context. Nothing is broken. |
| Transcription fails all three providers | Take → `status='failed'`, audio retained. Card shows *"We couldn't hear that one."* with `[ Try again ]` and `[ Type it ]`. Never silently loses the recording. |
| Extraction returns junk | Confirm screens are the guard. Junk lands as low-confidence, unconfirmed, and drives nothing. |
| Runner talks off-topic | `scope: "out_of_scope"` on card 5; other cards' unmatched content lands in `verbatim` and nowhere else. |
| Backfill still running at Phase 1 | Read-back shows a live progress state and a `[ Skip ahead ]` — Strava's 100 req/15min ceiling means a 260-activity history is ~780 calls and cannot finish in a first-run window. Phase 1.5 (the shortlist detail fetch, ≤20 calls, ≤15s) is the only part worth waiting on. |
| No Strava, no HealthKit | Phase 1 is skipped entirely. The five cards carry the whole load, and card 4 becomes the only source for weekly volume. |
| Runner quits mid-flow | Every take is already persisted. `onboarding_completed_at` stays null; resume lands exactly where they left off, on any device — which the current `@AppStorage` flag cannot do. |
| Two accounts, one device | Fixed by moving completion state server-side. |

---

## 12 · Phasing

Each phase is independently shippable and independently useful.

### Phase 1 — foundations *(~1 day)*
- [ ] Migration: `onboarding_takes` + `runner_profiles` + RLS + indexes
- [ ] Migration: widen `injuries.source` CHECK to include `'onboarding'`
- [ ] Migration: partial unique index on `body_mentions (user_id, body_area) WHERE training_log_id IS NULL`
- [ ] Register `onboarding_memo` in `FEATURE_LIMITS`, `MONTHLY_LLM_CAPS`, and `rateLimit.contract.test.ts`
- [ ] Extract `_shared/transcribe.ts` from `process-training-memo:669–739`, no behaviour change
- [ ] Mapping table: extraction `distance_key` → `athlete_pace_profiles.goal_race_distance` (12 values → 5, case-sensitive)

Ships alone. Nothing user-visible. Grew from half a day because five of these
are constraint work the first draft of this spec got wrong.

### Phase 2 — the extractor *(~1 day)*
- [ ] `_shared/prompts/onboarding-profile.v1.ts` — five slices, worked examples per card
- [ ] Register it in `_shared/prompt-library.ts` (static import + `REGISTRY` line, or `loadPrompt` throws)
- [ ] `process-onboarding-memo` edge function
- [ ] `_shared/profileMerge.ts` + unit tests against hand-written transcripts
- [ ] Extend `_shared/niggleWriter.ts`: `trainingLogId` optional, `source` a parameter
- [ ] `drain-onboarding-takes` cron sweep

Testable end-to-end with `curl` and a typed transcript, before any iOS work.

### Phase 3 — the iOS flow *(~2 days)*
- [ ] `App/OnboardingVoiceView.swift` — five prompt cards, reusing the record
      button and waveform from `Workouts/VoiceLogView.swift`
- [ ] `App/OnboardingConfirmGoalSheet.swift`, `…ConfirmWeekSheet.swift`,
      `…ConfirmBodySheet.swift`
- [ ] `App/RunnerProfileCard.swift` — the "what we know" surface, also mounted in Settings
- [ ] `RootView` reads `runner_profiles.onboarding_completed_at`, not `@AppStorage`
- [ ] **Fix `saveGoalIfNeeded()`** — it writes `goal_type` and `target_time`, neither of which exists

Naming follows the codebase: full screens `<Name>View.swift`, modals
`<Name>Sheet.swift`, new files in `App/`.

### Phase 4 — the read-back *(~2 days, gated on Strava)*
- [ ] Real Strava OAuth (`strava-connect` fn — **specced, not built**)
- [ ] `strava-sync` two-phase + 365-day onboarding default (today: `DEFAULT_LOOKBACK_DAYS = 60`)
- [ ] `_shared/raceDetection.ts` + `confirm-races` fn — both fully specced in
      `strava-day0-race-detect-spec-2026-07-15.md`, neither built
- [ ] Phase 1 read-back screen

**This is the long pole.** Phases 1–3 ship without it; the flow simply starts
at the voice cards, which is a perfectly good product.

### Phase 5 — the loop closes *(~1 day)*
- [ ] `subscribe-to-plan` reads `runner_profiles.availability` as its defaults
- [ ] Profile card becomes editable — same sheets, "edit" mode
- [ ] Coverage-gap prompts in the coach surface
- [ ] Fix the iOS `BodyArea` enum: 13 cases → 26

---

## 13 · The three things that make this beta-to-v2 rather than beta-only

Stated plainly, because this is the actual design goal.

**1 · Raw beats derived.** `onboarding_takes` keeps audio, transcript, and the
extractor version forever. When the extraction prompt improves — and it will,
twice — you re-run it across every take ever recorded and every profile gets
better overnight. No runner is ever asked the same question twice. This costs
one extra table today and is close to impossible to retrofit later.

**2 · Provenance beats values.** Every field knows where it came from and how
sure it is. That single property is what lets a future coach say *"you told me
in March you'd never run more than 40 — you're at 52 now"*, lets the UI grey out
what's guessed, and lets you ship an aggressive extractor safely because
unconfirmed data is structurally prevented from driving decisions.

**3 · Coverage beats completion.** Modelling *what we don't know* as a
first-class field means the product can keep asking, in context, forever.
Onboarding stops being a gate you pass once and becomes a profile that fills in
over months. That reframing is worth more than any single question on the list.

---

## 14 · Copy guide

| Surface | Wrong | Right |
|---|---|---|
| Voice intro | "Let's get to know you! 🎉" | "Talk for four minutes. We'll do the rest." |
| Card skip | "Skip this step" | "Skip — you can add this later" |
| Processing | "Analyzing your response…" | "Listening back." |
| Receipt | "Got it! ✅" | "Heard: 11 years, XC background, two years off." |
| Conflict | "Which is correct?" | "You said about 40 a week. Your last 12 weeks average 31." |
| Body, empty | "No injuries reported" | "Nothing right now" *(a button, not a default)* |
| Goal, undecided | "Please select a goal" | "Not sure yet" *(a real, writeable answer)* |
| Completion | "You're all set! 🚀" | "That's enough to start." |

No emoji. No exclamation points. Declarative about what happens next.

---

## 15 · Open questions

1. **Re-records: append or replace?** The `attempt` column supports append. The
   merge treats a higher attempt as higher precedence at equal confidence — but
   should attempt 2 be allowed to *lower* confidence on a field attempt 1 got
   right? Recommend: no. A re-record adds; it does not subtract.
2. **How long is the voice ceiling?** Five cards at 45s is 3m45. Beta should
   measure actual completion rate per card and cut the worst performer rather
   than guess which one it is.
3. **Should card 2 (`bests`) be shown at all when 365-day backfill already
   found races?** Argument for: lifetime PRs predate the app and no backfill can
   reach them. Argument against: it's the card most likely to feel redundant
   right after the read-back. Recommend showing it, reworded to *"the ones we
   couldn't have seen."*
4. **`athlete_profiles` has two conflicting migrations** — `user_id UUID` vs
   `user_id text`, both `IF NOT EXISTS`, so prod has whichever landed first.
   Resolve before `runner_profiles` joins the neighbourhood, or the same
   ambiguity propagates.
5. **Does the Coach Read get the profile on day 0?** It should — a depth-0
   account with a rich profile is exactly the case the depth ladder handles
   badly today, since `data_depth` counts runs and logs, not knowledge.
6. **Where do the eight orphan distances go?** `3k`, `8k`, `12k`, `15k`,
   `10mile`, `50k`, `other` are storable in `race_results` but have no home in
   `athlete_pace_profiles`. For a trail runner whose only bests are a 50K and a
   15K, the pace profile stays empty. Either widen the CHECK or accept that
   pace anchoring is a road-distance feature and say so.

---

## 16 · Corrections log

The first draft of this spec asserted six things about the codebase that turned
out to be false. They're listed here rather than quietly fixed, because the
pattern matters: **every one was a constraint, and every one would have shipped
as a silent write failure** — the same failure class as the `user_goals` insert
that's been quietly doing nothing in onboarding since February.

| Claimed | Actually |
|---|---|
| `voice_processing_jobs.audio_url` is `NOT NULL`; typed takes pass `''` | Nullable since `20260718120000`; the `'note'` path passes NULL |
| Nothing writes `athlete_settings.timezone` | `syncDeviceTimezone()` runs every launch (`Supabase.swift:465`). CLAUDE.md is stale, not the code |
| `injuries` accepts `source='onboarding'` | CHECK allows only `voice_memo`, `coaching_chat`, `manual` |
| `enforceFeatureRateLimit(userId, feature, 15/day)` | Third arg is `corsHeaders`; limits live in `FEATURE_LIMITS`; unregistered keys silently get 5/day |
| `body_mentions` upserts fine with a NULL `training_log_id` | NULLs compare distinct — `onConflict` never fires, re-records duplicate |
| `niggleWriter.ts` reusable unchanged | `trainingLogId` non-optional, `source` hardcoded |
| A confirmed best is a one-line `race_results` insert | `race_date NOT NULL`, a time is required, hedged bests are unstorable |
| Widening `voice_processing_jobs.kind` is enough for onboarding jobs | `training_log_id` is `NOT NULL` *and* `UNIQUE` |

---

## 17 · Downstream — what this profile actually changes

*Added 2026-08-11 after tracing both consumption paths end to end. This section
answers five questions the rest of the spec ducked: how the AI insight changes,
which fields populate, what happens to pace charts and fitness, whether a
snapshot is created, and where PRs land.*

**The headline finding is uncomfortable.** As written above, §5.4 routes the
profile to `user_goals`, `athlete_pace_profiles`, `race_results`,
`body_mentions`, `injuries` and `runner_profiles`. **Four of those six are
invisible to the Coach Read, and one of them is invisible to everything.** A
runner could complete all five voice cards, confirm all three screens, and the
coach would sound exactly as it does today.

---

### 17.1 · How the AI insight actually gets its context

There is no single "AI context." There are five surfaces with **three
different, non-shared pipelines**:

| Surface | Context source | Sees `athlete_state`? | Sees `user_memories`? | Sees `athlete_profiles.profile_data`? |
|---|---|---|---|---|
| **Coach Read** (`coaching-daily-read`) | `stateToPromptContext(state)` + 8 direct queries | ✅ full render | ✅ via `state.memories` | ❌ |
| `generate-workout-insight` | its own 17-column read of `athlete_state` | ⚠️ partial | ❌ | ❌ |
| **Ask** (chips + analyzers) | deterministic analyzers over raw tables | ⚠️ 11 columns | ❌ | ❌ |
| `coaching-agent` (Ask prose fallthrough, chat) | everything | ✅ | ✅ | ✅ |
| weekly report, block review, race readiness, post-run, injury early-warning | `stateToPromptContext` + `profile_data` | ✅ | ✅ | ✅ |

The Coach Read prompt is assembled at `coaching-daily-read/index.ts:252`:

```ts
const systemPrompt = loadPrompt("daily-read.v5", {});
const fullPrompt = `${systemPrompt}\n\n${context.contextBlock}\n\nGenerate today's Read for this athlete.`;
```

The template takes **no substitution variables**. The entire dynamic payload is
`contextBlock`, and the "who is this runner" half of it is one string:
`stateToPromptContext(state)` — eighteen priority-ranked sections rendered from
`athlete_state` at `_shared/athlete-state.ts:2078–2607`.

**What the Read knows about who you are today, and where it comes from:**

| Rendered as | Actually derived from |
|---|---|
| `Level: intermediate` | 28-day mileage + easy pace. **The athlete never says it.** |
| `building / returning / peaking` | volume ratios and injury flags |
| life context (sleep, stress, motivation) | `training_logs.extracted_data`, **28-day window** — it decays out |
| memories | `user_memories`, quota-capped |
| verbatim athlete language | four places only: `recent_workouts[].user_notes`, `possible_injuries[].excerpt`, `memories[].their_words`, `life_context.*.detail` |

**There is no running history, no motivation, no self-described level, no
preferred days, no session-type preference, and no athlete-stated PR anywhere
in the Read's prompt today.** Everything qualitative is either machine-inferred
or expires in 28 days.

### 17.2 · `user_memories` is the only durable channel — and it's small

This is the load-bearing correction to §5.4. `user_memories` is the single
durable, athlete-declared, qualitative store that reaches the Coach Read.
Selection is quota-gated at `_shared/memorySelection.ts:40–46`:

```ts
const QUOTAS = [
  { key: "constraint", categories: ["constraint"], limit: 3 },
  { key: "preference", categories: ["preference"], limit: 3 },
  { key: "life",       categories: ["life"],       limit: 2 },
  { key: "pr_race",    categories: ["pr", "race"], limit: 2 },
];
const EPISODE_LIMIT = 2;
```

**Ceiling: 12 general memories + 2 episodes.** Ranked by
`importance × recencyFactor(last_confirmed_at)`, decaying linearly over a year,
floored at 0.3.

Three traps, all verified:

1. **Two competing category vocabularies exist.** The write-side closed set
   (`_shared/memoryWriter.ts:31`) is `pr, race, preference, constraint, life,
   gear, episode`. A legacy set in `_shared/memory.ts:25` adds `injury, goal,
   training, personal, agreement, context`. **Anything outside the four quota
   groups is stored, loaded into `athlete_state.memories`, and then silently
   discarded before the prompt sees it.** Write `category:'goal'` and it
   vanishes.
2. **Non-durable memories expire in 60 days** (`memoryWriter.ts:42`,
   `TRANSIENT_TTL_DAYS`). Onboarding memories must be written `durable: true`
   or the profile evaporates before the runner's first training block ends.
3. **The near-dup guard** (token overlap ≥ 0.7 within a category) reinforces
   `mention_count` instead of inserting. Good — a re-record won't duplicate.

One free win: `athlete-state.ts:2343` emits *"STILL LEARNING YOU — I don't know
much about your life outside the numbers yet"* whenever `memories.length < 3`.
**That line currently fires for every new user.** Writing three memories at
onboarding suppresses it, which is worth doing for the first-impression alone.

### 17.3 · Field-by-field: what populates, and what changes

| Profile field | Writes to | Which surface changes |
|---|---|---|
| Years running, background, gaps | `user_memories` `category='life'` (2 slots) or `'episode'` (2) | Coach Read, chat, weekly report |
| Self-described level | `athlete_profiles.experience_level` — **column does not exist**, see 17.7 | Coach Read `Level:` line |
| Lifetime PRs | `race_results` `source='athlete'` (→ Ask race projection, display only) | Ask only — see 17.6 |
| Current-fitness race | `set-fitness-anchor` → `manual_anchor_*` | pace zones, pace chart |
| Injury history | `injuries` (→ `injury_history_summary`) | Coach Read **priority 1**, never pruned |
| Current niggles | `body_mentions` (→ `niggle_recurrence`) | Coach Read P4, needs ≥2 occurrences |
| Goal + date | `user_goals` + `athlete_pace_profiles` | Read P2, `data_depth`, pace fallback |
| Motivations | `user_memories` `category='life'`/`'episode'` with `their_words` | Read — quoted verbatim |
| Preferred training days | `user_memories` `category='constraint'` (3 slots) **and** `runner_profiles.availability` | Read via memories; plans via `subscribe-to-plan` |
| Session-type preferences | `user_memories` `category='preference'` (3 slots) | Read |
| Weekly volume (confirmed) | `runner_profiles.training` | **nothing** — the Read computes its own from logs |

**`athlete_profiles.profile_data` is not a valid target.** `build-athlete-profile`
overwrites it wholesale every 24 hours from `training_logs`
(`build-athlete-profile/index.ts:162–171`). Anything onboarding writes there is
destroyed within a day. Its `preferences.preferred_run_days` looks like the
right home for training days and is not.

**`runner_profiles` reaches no prompt.** It's the athlete-facing record and the
re-extraction substrate — both real jobs. But it is not a coaching input unless
it is *projected* into `user_memories`. Add that projection to §9's merge step:
after a take completes, upsert the durable soft fields as memories with the
correct category, `durable: true`, and `their_words` set from the transcript.

### 17.4 · Pace zones — the precedence order, and the trap

Two chains exist and **they do not share code**.

**Chain A — `_shared/pace-engine.ts:395–410`, what iOS displays:**

| # | Source | `PaceSource` | Confidence |
|---|---|---|---|
| 1 | `athlete_pace_profiles.manual_anchor_*` | `manual` | high |
| 2 | `athlete_pace_profiles.*_pace_seconds` | `profile` | high |
| 3 | latest `fitness_snapshots.predicted_*` | `race_derived` | medium |
| 4 | active plan goal time (**marathon only**) | `goal_only` | low |
| 5 | nothing | `none` | — |

A race is **not a tier of its own here.** It reaches the engine only laundered
through tier 2, because `build-pace-profile` wrote race-derived numbers into
the `*_pace_seconds` columns. If `build-pace-profile` has never run, a fresh
confirmed race changes nothing.

**Chain B — `_shared/paces.ts:346`, what gets stamped onto scheduled workouts:**
confirmed race → goal distance → marathon pace → first available. **It never
reads `manual_anchor_*`.** So a manual anchor changes what the runner sees and
not what their workouts say. That seam predates this feature; onboarding will
make it more visible, not cause it.

> ### ⚠️ The trap: a spoken lifetime PR can hijack every pace zone
>
> `pickAnchorRace` (`_shared/paces.ts:306`) has a docstring promising
> recency-weighting. **The implementation sorts by date descending and takes
> `qualifying[0]` with no age cutoff at all.** The only bound is upstream: a
> 730-day window on `training_logs`.
>
> So if onboarding writes *"I ran 18:30 for 5K in college"* to
> `training_logs.race_result`, and that runner has no newer race, that college
> time becomes the **sole anchor**, and `build-pace-profile/index.ts:113` stamps
> the entire zone ladder `confidence: "high"`. Every easy run in the app is now
> prescribed off fitness the runner had four years ago.
>
> The predictor already knows better — it drops races older than **36 weeks**
> outright (`fitnessPrediction.ts:1198`) and treats 16 weeks as the confidence
> boundary. The pace engine simply doesn't apply the same rule.
>
> **Therefore: lifetime PRs must never be written to `training_logs.race_result`
> from onboarding.** They go to `race_results` as history. Only a race the
> runner nominates as *current fitness* — and only inside the predictor's
> 36-week window — may become an anchor, and it should go through
> `set-fitness-anchor`, which is explicitly designed for "the athlete states one
> effort" and is the one source that outranks everything else.

### 17.5 · Goals, and the `data_depth` side-effect

`_shared/athlete-state.ts:394`:

```ts
export function computeDataDepth(args: {
  workoutCount: number; uniqueDayCount: number; hasActiveGoal: boolean;
}): number {
  if (args.uniqueDayCount >= 21) return 3;
  if (args.hasActiveGoal && args.workoutCount >= 1) return 3;
  if (args.uniqueDayCount >= 7) return 2;
  if (args.workoutCount >= 1) return 1;
  return 0;
}
```

**An active goal plus one run jumps a brand-new account straight to depth 3** —
the full editorial register, pull-quotes in every section. And per CLAUDE.md's
own rule, every depth-2+ pull-quote must cite a specific number, which a day-1
account does not have.

This is not a new bug, but onboarding is about to trigger it for **every**
runner instead of the few who found the goal screen. Two options:

- **(a)** Add a fourth argument to `computeDataDepth` — require
  `workoutCount >= 3` alongside `hasActiveGoal`. One-line change, keeps the
  intent (a goal means you're serious) without the day-1 cliff.
- **(b)** Let depth 3 stand and lean on the profile: with memories written, the
  Read has real material to be editorial *about*, even at zero runs. Riskier,
  but arguably the better product — the whole point of onboarding is that day 1
  isn't empty.

**Recommend (a) for beta**, revisit once the profile projection in 17.3 is
actually landing memories.

Goal also writes `athlete_pace_profiles.goal_race_distance` — five values,
**capital K**: `('mile','5K','10K','half','marathon')`. §6.2's twelve lowercase
values need the mapping layer already flagged in §5.4.

### 17.6 · Fitness snapshots — onboarding creates none, and shouldn't

`fitness_snapshots` has **two writers running the same algorithm in two
languages**: `supabase/functions/compute-fitness-snapshot` (nightly cron,
`'30 3 * * *'` UTC, one POST per athlete with a log in the last 45 days) and
`RunningLog/RunningLog/Analysis/FitnessPredictorService.swift:1477`, on-device,
whenever the predictor screen opens. Both upsert **one row per user per calendar
day**; history accumulates day over day; last writer wins.

**Onboarding should not write a snapshot.** A snapshot is a *prediction from
observed training*, and onboarding has no observed training — that's its whole
premise. Writing one would fabricate a fitness estimate from self-report and
then let it anchor pace zones at tier 3.

What onboarding *should* do is influence the **next** snapshot, which happens
for free: the nightly job seeds from `training_logs.race_result` (all-time), and
Strava backfill from Phase 4 lands real runs the predictor can read. A runner
who connects Strava has a legitimate snapshot within 24 hours without
onboarding faking anything.

Two notes worth knowing:

- The predictor computes `lifetimePRs` internally (`fitnessPrediction.ts:1731`)
  and **throws it away** — there is no column for it. If PR history should
  survive, `race_results` is the place, not the snapshot.
- There is no `selectFitnessAnchor` function, and **no 180-day staleness rule**
  — both appear in `strava-day0-race-detect-spec-2026-07-15.md` and neither
  exists in code. 180 days is an input lookback window. The real age gates are
  16 and 36 weeks, and only inside the predictor.

### 17.7 · Where PRs actually live

Short answer: **nowhere useful, yet.**

| Store | Status |
|---|---|
| `race_results` | Created 2026-08-07. **No reader, no live writer.** Only rows are the one-time backfill from `training_logs.race_result`. |
| `race_prs` (view) | Exactly one consumer: `_shared/analyzers/raceProjection.ts:96`, used by Ask for a **display line beside the projection**. Feeds no math. Does not filter `confirmed_at`. |
| `athlete_state.confirmed_races` | **The live path.** Derived from `training_logs` where `workout_type='race' AND race_result IS NOT NULL`, 730-day window. Read by eight consumers including `build-pace-profile`, `paceTableFromProfile`, `generate-workout-insight`, and the Coach Read. |

So the routing is a deliberate three-way split:

1. **Lifetime PRs** (the college 5K) → `race_results` `source='athlete'`, plus a
   `user_memories` `category='pr'` row so the coach can *mention* it. Display and
   narrative only. **Never** `training_logs.race_result`.
2. **A recent race the runner nominates as current fitness** → `set-fitness-anchor`.
   Tier 1 in Chain A, athlete-owned, clearable, and it survives profile rebuilds
   by design.
3. **Races the Strava backfill detects** (Phase 4) → `training_logs.race_result`
   via the confirm screen, which is the existing path and already age-bounded by
   the 730-day window.

**This also makes `race_results` real.** Right now it's a well-designed table
with nothing plugged in. Onboarding would be its first writer, and Ask's race
projection its first beneficiary — a runner who says their PRs on day 1 gets
*"your 5K PR is 18:30"* out of Ask immediately, with no runs logged.

> ⚠️ **The narration guard applies here.** In Ask, any number the model
> speaks must appear in an analyzer fact line, or `validateNarration` kills the
> **entire** narration (`_shared/narration-guard.ts:218`). Colon-form times get
> no rounding leniency. A PR narrates safely only because `raceProjection`
> reads `race_prs` — which is exactly why the `race_results` insert matters.
> The Coach Read has **no** number guard, so a PR reaching it via memories will
> be quoted freely with no arithmetic check. Keep PR memories verbatim.

### 17.8 · Three dead hooks worth knowing

Each of these is code that reads a column that does not exist. All three are
cheap to fix and each one unlocks something onboarding wants.

1. **`athlete_profiles.experience_level`.** `_shared/builders/buildTrajectory.ts:116`
   prefers it and falls back to inferring from volume — but the column was never
   created. Adding it is the cheapest possible route for a self-described level
   to reach the Read's `Level:` line, because the read side already exists.
2. **`athlete_profiles.lifetime_weekly_avg`.** Same story, read by `derivePhase`.
3. **`athlete_state.field_provenance`.** Added 2026-06-12 with a comment
   describing exactly the per-field source/confidence envelope this spec's §5.3
   proposes. **Nothing reads or writes it.** Worth deciding whether
   `runner_profiles.field_provenance` should live there instead — one
   provenance system, not two.

### 17.9 · What this adds to the phasing

Fold into the existing phases rather than adding a new one:

**Phase 1** gains:
- [ ] `computeDataDepth` — require `workoutCount >= 3` alongside `hasActiveGoal`
- [ ] `ALTER TABLE athlete_profiles ADD COLUMN experience_level text` (after resolving the UUID/text conflict in open question 4)

**Phase 2** gains:
- [ ] `_shared/profileMerge.ts` also projects durable soft fields into
      `user_memories` — correct category from the four quota groups,
      `durable: true`, `their_words` from the transcript, `source: 'onboarding'`
- [ ] Guard: reject any category outside `pr|race|preference|constraint|life|episode`
      at write time, so nothing is silently dropped at render

**Phase 3** gains:
- [ ] Confirm screen A distinguishes **"a recent race that reflects my fitness
      now"** (→ `set-fitness-anchor`) from **"a PR I'm proud of"**
      (→ `race_results`). This is a UI distinction that prevents the 17.4 trap,
      and it has to exist in the interface, not just the backend.

**Phase 5** gains:
- [ ] Decide whether `race_results` becomes the primary race store and
      `confirmed_races` derives from it, rather than the current split
---

*Companion docs: `athlete-onboarding-redesign.md` (coach-plan onboarding),
`outputs/strava-day0-race-detect-spec-2026-07-15.md` (the read-back),
`ASK-V2-CONVERSATION.md` (the propose→confirm→write discipline this follows),
`outputs/maya-data-aware-journey-2026-05-28.md` (the fusion thesis).*

# The Read — editorial narrative screen · implementation spec (Xcode agent)

**Date:** 2026-06-15 · **Owner:** Rio · **Builder:** Xcode/SwiftUI agent
**Design mock:** `outputs/the-read-storytelling-mock.html` (open it — it IS the target)
**Voice/content source of truth:** `_shared/prompts/daily-read.v4.ts` (retooled coach-snapshot voice) and `outputs/the-read-redesign-plan-2026-06-13.md` §3.1

---

## 0. One-liner

Build a new SwiftUI screen that renders The Read as a **coach's editorial note** — headline, a short prose spine (the week → the hard days → the long run → how you felt → one thing), a soft question, an honest "what I can't see," and a pinned ask bar — with two **quiet tappable references** (the long run → workout detail; a niggle → its timeline). It reads the LLM narrative from `daily_coaching_reads`, NOT `athlete_state`.

This is a different surface from today's `ModelOfYouView` (card "Model of You" dashboard). See §6 for how they coexist.

---

## 1. Scope decision (confirm before building)

The current Read tab is `ModelOfYouView` (expandable cards from `athlete_state`). This spec adds an **editorial narrative** view. Default plan, change if Rio says otherwise:

- **The narrative becomes the Read tab's primary surface.** The card "Model of You" content becomes a secondary "the evidence" drill-down reachable from the Read (or is retired). Do NOT delete `ModelOfYouView` in this PR — keep it reachable behind a nav push so nothing is lost.
- Gate the new view behind a simple flag / fallback: if the `daily_coaching_reads` row has no v5 `sections` payload yet, fall back to the current view. (Backend emits v5 separately — see §5 dependency.)

---

## 2. Where it lives

- New file: `RunningLog/RunningLog/Coaching/Read/ReadNarrativeView.swift` (a `Coaching/Read/` group already exists — `CoachReadView.swift` is there; this is the redesigned sibling).
- Entry: THE READ tab in `RunningLogApp.swift` (tab index for The Read). Swap the tab's root to `ReadNarrativeView`, keep `ModelOfYouView` as a pushed detail.
- Reuse, don't rebuild: `CoachAskContext` + `CoachAskSheet` (already in `Coaching/`) for the ask bar; `WorkoutDetailPlate23` for the workout tap target; the niggle/injury detail surface in `Analysis/` (`InjuryDetailSheet` / `InjuryPlate28`) for the niggle tap target.

---

## 3. Data contract — daily-read **v5** payload (the schema change)

This is a SCHEMA change, so it's a new prompt version `daily-read.v5` (per CLAUDE.md convention: bump version on schema change). The function persists this JSON into `daily_coaching_reads`. iOS decodes it.

```jsonc
{
  "headline": "A strong week — keep that achilles honest.",   // string, < 10 words, ends with a period
  "eyebrow":  "Chasing 3:16 · off your 3:28",                 // string | null — the goal backdrop (scope line)
  "sections": [                                                // ordered; render in array order; 2–5 of them
    {
      "label": "The week",                                     // section eyebrow (mono, uppercased in UI)
      "body":  [ /* segments, see below */ ]
    }
    // ... "The hard days", "The long run", "How you felt", "One thing"
  ],
  "question": "How does the achilles feel first thing in the morning?", // string | null — the single soft Q (italic, coral left-rule)
  "cant_see": { "eyebrow": "NO SLEEP DATA", "body": "..." } | null,
  "confidence": { "level": "HIGH" | "MEDIUM" | "LOW", "sub": "8 recent runs, a landed long run." },
  "sources": { "workouts": ["<uuid>"], "docs": ["<uuid>"], "memos": ["<uuid>"] }
}
```

### 3.1 Body segments (this is what enables the quiet tap-throughs)

`body` is an ordered array. Each element is ONE of:

```jsonc
"Fifty-two miles, and you handled every one of them."          // plain prose (string)

{ "text": "the long run", "workout_id": "<uuid>" }              // WORKOUT REF → tappable, opens WorkoutDetailPlate23

{ "text": "achilles", "niggle": "right achilles" }             // NIGGLE REF → tappable, opens the niggle timeline for that body part
```

- A ref segment carries its own display `text`, so prose flows naturally and the tap target is exactly that phrase.
- Render plain strings as body text; render ref segments inline with the **quiet tap treatment** (§4.3).
- `workout_id` must appear in `sources.workouts`; `niggle.body_part` must match a `body_mentions` body area. The edge function validates/strips invalid refs (a stripped ref renders as plain text, never a dead link).
- Keep refs RARE — at most ~2 per Read (one workout, one niggle). The prompt enforces this; the view just renders whatever it gets.

---

## 4. The view (match the mock section by section)

Phone column on warm paper. Use existing Drip Swift tokens — do NOT hardcode hex. Known symbols: `Color.drip.background | cardBackground | divider | textPrimary | textSecondary | textTertiary | coral | success | tired`; fonts `.dripDisplay(_)`, `.dripBody(_)`, `.dripStat(_)` (mono), `.dripQuote`/italic where available.

Layout top → bottom inside a `ScrollView`:

1. **Plate strip** (mono, `textSecondary`, tracking ~1.4): left `THE READ · WEEK OF <date>`, right a context chip e.g. `CHICAGO · 14 WKS OUT`. (Weekly cadence — see note.) Do NOT show the model name to the athlete.
2. **Eyebrow** (mono, coral): the `eyebrow` scope line, uppercased.
3. **Headline**: `.dripDisplay(~32)`, `textPrimary`, tight leading. From `headline`.
4. **Sections** (`ForEach` over `sections`):
   - Section **label**: mono eyebrow, `textSecondary`, uppercased, tracking ~1.1.
   - Section **body**: render the `body` segment array as one flowing `Text` (concatenate `Text` runs so it wraps as a paragraph). `.dripBody(16)`, line spacing ~6. Ref segments get the tap treatment (§4.3).
   - **Lede treatment (NO drop cap):** the FIRST section's body is the editorial standfirst — set it in the display serif (`.dripDisplay(~21)`, weight medium, line spacing ~3), not body PT Serif. That gives the opening editorial weight through type hierarchy (headline → display-serif lede → PT Serif sections) instead of a decorative capital. Do not use a drop-cap / raised first letter anywhere.
5. **Soft question** (`question`, if non-null): italic `.dripBody(16.5)`, a 2pt coral left rule, padding-left ~14. One per read.
6. **Editorial rule** (line · coral dot · line) between the body and the can't-see, matching `.drip-rule`.
7. **What I can't see** (`cant_see`, if non-null): mono eyebrow `textTertiary` + one plain sentence `textSecondary`, `.dripBody(13.5)`.
8. **Signature row** (mono, `textTertiary`): left "POST RUN DRIP · YOUR READ", right "UPDATED <weekday time>".
9. **Pinned ask bar** (NOT in the scroll — pin above the tab bar): rounded `cardBackground` capsule, placeholder "Ask your coach a question…", coral send affordance. Tapping presents `CoachAskSheet` via `CoachAskContext` (already wired — `ModelOfYouView` shows the pattern at lines 53–60).

### 4.1 Confidence

Render `confidence.level` small and quiet — either fold into the signature row or a tiny pill near the headline. Do NOT make it a loud "HIGH CONF" chip (that was the market-report feel we removed). `sub` is for the can't-see context, not a headline badge.

### 4.2 States

- **Loading:** `ProgressView`, centered, paper background.
- **Empty (new account):** headline "Nothing to read yet."; one plain sentence; no em-dash placeholders (hard rule #8 — use the empty-state pattern).
- **No v5 payload yet (old row):** fall back to `ModelOfYouView` (§1).

### 4.3 The quiet tap treatment (the whole point of "pull the thread, don't link the report")

- A ref segment renders as `textPrimary` (same color as prose) with a **hairline coral underline at ~32% opacity** — discoverable, not shouting. No blue, no chevrons inline.
- On tap: brief coral-wash highlight, then present the target:
  - `workout_id` → `WorkoutDetailPlate23` for that workout (sheet or push, match app convention).
  - `niggle.body_part` → the per-body-part niggle timeline (`Analysis/` injury/niggle detail). It shows the verbatim mentions over time — **surface only, no diagnosis/severity** (niggles hard rule).
- Accessibility: each ref is its own button with a label like "Open the long run" / "Open right achilles history". Whole read must be VoiceOver-legible as prose; refs are actionable elements within it.

---

## 5. Backend dependency (NOT this agent — flag/sequence it)

The iOS view can't show v5 until the backend emits it. Owned in the data/prompt workstream (can be done in the Cowork/Supabase session), tracked here so the order is clear:

1. **`daily-read.v5.ts`** — carry over v4's retooled coach-snapshot voice, change the OUTPUT FORMAT to the §3 sectioned schema (sections[] + ref segments + question). New `RESPONSE_SCHEMA` (the actual schema change).
2. **`coaching-daily-read/index.ts`** — load `daily-read.v5`, parse/validate the sectioned payload, validate workout/niggle refs (extend `validateCitations`), persist `sections`/`eyebrow`/`question` into `daily_coaching_reads`.
3. **Eval cassette** `_evals/cassettes/daily-read.v5/` (hard rule #3, CI-enforced) before ship.
4. Model stays **`gemini-3.1-pro-preview`** (already wired).

**Sequencing:** ship the iOS view behind the §1 fallback first (safe — old rows still render via `ModelOfYouView`), then land v5 backend, then the new view lights up automatically as v5 rows arrive.

---

## 6. Cadence note

The Read is moving to **weekly** generation, so the plate strip says "WEEK OF <date>" and copy reads as a weekly note, not a daily one. Don't build a daily-refresh affordance.

---

## 7. Definition of done

- New `ReadNarrativeView` renders a v5 payload pixel-close to `the-read-storytelling-mock.html` using Drip tokens (no hardcoded hex, no SF Symbol mood icons, one coral element per cluster).
- Sections render in order as flowing prose; the two ref types are tappable with the quiet treatment and open the right targets.
- Ask bar presents `CoachAskSheet`.
- Loading / empty / no-v5-fallback states all handled; empty state uses the empty-state pattern (no em-dashes).
- Dynamic Type and VoiceOver pass; the read is legible as prose to a screen reader.
- `#Preview` injects a sample v5 payload (mirror the mock's content) so it renders in the Xcode canvas without running the app.
- `ModelOfYouView` remains reachable; nothing deleted.

## 8. Don'ts

- Don't render the model name or any "AI"/"based on your data" chrome to the athlete.
- Don't make every number/date tappable — only the ~2 refs the payload carries.
- Don't surface a niggle verdict/severity/diagnosis anywhere in the timeline — verbatim mentions + dates only.
- Don't block on the backend — build against the v5 sample payload and the fallback.

---

## 9. Sample v5 payload (for `#Preview` — build against this)

This mirrors `the-read-storytelling-mock.html`. Decode it into the `CoachRead`/`DailyRead` model and inject it in `#Preview` so the screen renders in the Xcode canvas without the app or network. It's exactly the shape `daily_coaching_reads` now persists (function-validated: refs already resolved).

```json
{
  "headline": "A strong week — keep that achilles honest.",
  "eyebrow": "Chasing 3:16 · off your 3:28",
  "sections": [
    {
      "label": "The week",
      "body": [
        "Fifty-two miles, and you handled every one of them. Third straight build week — this is about stacking them now, not chasing more. Don't go looking for extra."
      ]
    },
    {
      "label": "The hard days",
      "body": [
        "Two quality sessions. Tuesday's LT work was sharp and in control; Saturday's intervals came apart a little in the last couple reps — that reads like three weeks of work catching up, not your engine. The down week will sort it."
      ]
    },
    {
      "label": "The long run",
      "body": [
        { "text": "The long run", "workout_id": "a1a1a1a1-0000-0000-0000-000000000001" },
        " is the one I'd circle: eighteen miles, and you were still running it at the end instead of just hanging on. That's the session that tells me race day is coming together."
      ]
    },
    {
      "label": "How you felt",
      "body": [
        "You sounded a little flat in a couple of notes this week — fair, after the mileage and the heat. And the ",
        { "text": "achilles", "niggle": "right achilles" },
        " is on its third week now, same note each time: \"grumbled on the warm-up, settled after a mile.\" I'm tracking the pattern, not just this week's mention. If you raced today I'd have you in the low 3:20s — already on the right side of your 3:28, with the sharpening that brings 3:16 into reach still ahead."
      ]
    },
    {
      "label": "One thing",
      "body": [
        "If the achilles is still talking on the warm-up Tuesday, make it an easy day instead. You won't lose a thing — the fitness is already in the bank."
      ]
    }
  ],
  "question": "How does the achilles feel first thing in the morning?",
  "cant_see": { "eyebrow": "NO SLEEP DATA", "body": "I don't have your sleep this week, and there's only one note on the knee — too thin to read yet." },
  "confidence": { "level": "HIGH", "sub": "8 recent runs, a landed long run, and a race anchor." },
  "sources": {
    "workouts": ["a1a1a1a1-0000-0000-0000-000000000001"],
    "docs": [],
    "memos": [
      { "label": "Jun 9 · after threshold", "excerpt": "grumbled on the warm-up, settled after a mile", "log_id": "a0000001-0000-0000-0000-0000000000a1" }
    ]
  }
}
```

Render notes tying back to §4: `eyebrow` → coral kicker; first section body = the display-serif lede (no drop cap); the `{text, workout_id}` and `{text, niggle}` segments render inline with the hairline-coral tap treatment and open WorkoutDetailPlate23 / the niggle timeline; `question` → italic with a coral left-rule; `cant_see` → the honesty block; `confidence` stays quiet (fold into the signature row).

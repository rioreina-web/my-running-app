# Session Story — apply notes

*Placed 2026-07-27. Follows the repo's additive-new-files + minimal-tracked-edits
convention (see `SESSION-GRID-APPLY.md`, `SHARP-END-APPLY.md`).*

Adds **Session Story**: tap a key session in Trends and get that one session
told whole — the fast segments (or halves, for sustained work) with heart rate,
the **previous comparable session as a dashed ghost** behind them, the drift
read against the durable zone, heat + hills costs with a flat-and-cool adjusted
pace, the **voice memo verbatim**, the niggle quotes, and a templated
observation ("The Read") that cites numbers and ends on a soft question.

Design approved via `session-story-prototype.html` (repo root, 2026-07-27),
which runs on your real Strava + journal data.

---

## Where the analysis comes from (nothing re-derived)

- Rep sessions → `_shared/fast-segment-trends.ts` `analyzeKeySession` — the
  same per-rep neutral/flat/conditions paces, HR drift, and density the Fast
  Segments surface already trusts.
- Sustained sessions → halves math in the new `story.ts`, using the same heat
  model (`pace-heat-adjustment.ts`) and grade model (`pace-grade-adjustment.ts`).
- **Split-grade hills are ON here.** `trends-timeline` deliberately keeps
  per-second `external_streams` out of the list load and pointed at "a lazy
  per-session request" — this endpoint is that request, so one session's
  altitude stream is affordable and hills are scored from the real profile
  (net-grade fallback with the same GPS-noise deadband when no stream exists).
- The prototype's rolling-terrain hill heuristic (0.33 s/mi per m/mi) is
  **gone** — production uses the Minetti model you already ship.
- No LLM anywhere. The Read is a pure, tested template (client-side), so
  nothing here touches the eval-coverage gate.

## The ghost

Client-side pick (`SessionStoryLogic.previousComparable`, tested): the nearest
earlier key session of the **same `kind`** — long runs only ever ghost long
runs, per the `KeySession.kind` invariant — and among quality sessions a
same-zone predecessor beats a nearer different-zone one. First of its kind →
no ghost, and the Read says so instead of inventing a comparison.

## Voice + safety invariants honored

- Adjusted paces ride alongside raw, never replace it.
- Niggles: verbatim quotes, surfaced never interpreted; the Read is asserted
  (in tests) to never say "rest" or "ice".
- Memo gating: auto-titles ("Morning Run") and sub-20-char strings never
  masquerade as the athlete's words; the empty state nudges a 30-second memo.
- Drift honesty: short reps and short runs get an explicit "not meaningful"
  note, never a fake number. The durable band on the gauge is neutral gray,
  never green (three-palette rule).
- Coral appears once per cluster (the section eyebrow / The Read rule).

---

## Files placed automatically (new, additive — safe)

**Backend** (`supabase/functions/session-story/`)
- `index.ts` — POST `{ log_id, compare_log_id? }`; dual-mode auth mirroring
  `trends-timeline`; fetches log + laps + structure + stream + niggles (±1 day)
  + zones; returns `{ session, compare, generated_at }`.
- `story.ts` — the pure builder (reps path / sustained path / memo + niggle
  carriage). Imports `sliceGradeSegments` from `../trends-timeline/fastSegments.ts`
  (pure) so the grade slicing can never drift between the two surfaces.
- `story.test.ts` — 9 Deno cases: reps path segments + heat, sustained halves +
  last-2mi + decoupling, no-laps degradation, thirds fade, time-based halving,
  tail refusal, drift gating, memo gating, short-rep drift honesty.

**iOS** (`RunningLog/RunningLog/Trends/`)
- `SessionStoryModels.swift` — models + snake_case DTOs + `SessionStoryLogic`
  (ghost pick) + `DriftTier` + `SessionStoryRead` (the template).
- `SessionStoryService.swift` — @Observable loader, cached per (log, ghost).
- `SessionStoryView.swift` — the sheet: hero, pace bars + ghost polyline
  (Canvas, one axis, ghost on its own step so counts never overflow), HR track,
  drift card + gauge, then→now deltas, conditions tiles, memo, The Read.
- `SessionStoryEntry.swift` — the horizontal session strip that opens the sheet.

**Tests** (`RunningLog/RunningLogTests/`)
- `SessionStoryTests.swift` — 14 `Testing` cases across ghost selection, drift
  tiers, The Read (numbers cited, no prescriptions), and DTO decode.

If the Xcode project uses file-system–synchronized groups (it did for the
session grid), the four Swift files + the test are picked up on next open;
otherwise add them to the app / test targets once.

## Tracked-file edits — APPLIED 2026-07-27 (one file)

### `RunningLog/RunningLog/Trends/TrendsTabView.swift`
Inside the Key sessions section, between `KeySessionsDetailView` and the
"Two side by side" sub-block:

    subHead("One session, told whole")
    SessionStoryEntry(sessions: service.keySessions)

Six added lines (plus a comment); nothing else touched. Revert is
`git checkout` on this one file.

---

## Verify — what's left for you

1. **Build in Xcode** (I can't compile Swift in the cloud sandbox). If the new
   files aren't picked up automatically, add them to the targets once.
2. `⌘U` → `SessionStoryTests`, 14 green.
3. `deno test supabase/functions/session-story/story.test.ts` → 9 green
   (they ran green here before placement).
4. **Deploy the new function:** `supabase functions deploy session-story`.
   Until you do, tapping a session shows the retry empty-state — the designed
   failure mode; nothing else in Trends is affected.
5. Open Trends ▸ Key sessions ▸ tap a card. On your own account expect: the
   Jul 21 `6×1mi` ghosted against the Jul 14 set, the Jul 11 24K reading
   "struggling" in your own words next to a HELD back half, and the two knee
   mentions (May 24, Jul 18) surfacing as NIGGLE pills.

## Two data notes, not bugs

- **Weather coverage gates the heat numbers.** Sessions whose
  `weather_actual` is missing show no heat tile and no flat+cool pace — run
  `fetch-workout-weather` backfill if you want the whole window covered.
- **Memos exist for 10 of the 21 sessions** in the May–July window. The rest
  show the honest empty state — which is the nudge to record one.

## Reverting

`git checkout` `TrendsTabView.swift`, delete the `session-story/` function dir
and the five new Swift/test files. Everything is additive; nothing else
depends on any of it.

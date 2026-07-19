# Apply notes — session fixes (2026-07-17 → 2026-07-18)

How to land the changes from this working session onto
`feature/coach-dashboard-phase1`. They can't be auto-committed cleanly because
the branch has a large uncommitted WIP set and my fixes are interleaved with it
inside shared files. This guide separates them.

`git add -p` legend: **y** stage hunk · **n** skip · **s** split into smaller
hunks · **e** manually edit which lines to stage · **q** quit.

---

## 1. Already committed (nothing to do)
- `0cb4bc1` — security: close live anon-key RLS holes + revoke SECURITY DEFINER RPC grants
- `881203b` — docs: beta risk sweep 2026-07-17

---

## 2. Clean patches — apply directly
Both are verified to contain *only* my changes.

```bash
git apply 02-journal-loadfailed-view.patch    # VoiceLogView.swift: "Couldn't load — retry" empty state
git apply 06-typed-note-drain-worker.patch    # drain: kind:'note' + nullable audio_url
```
(These two `.patch` files sit next to this doc. Delete them once applied.)

---

## 3. Untracked new files — just add them
Git sees these as whole-new files; there's nothing to isolate.
```bash
git add RunningLog/RunningLog/Analysis/AdjustFitnessSheet.swift
git add RunningLog/RunningLog/Trends/FastSegmentsView.swift
git add supabase/migrations/20260718120000_enqueue_typed_notes_for_analysis.sql
```
Notes:
- `AdjustFitnessSheet.swift` — my change is the **DATE** `DatePicker` + `effort_date`
  in the save body. The rest of the file is pre-existing untracked work.
- `FastSegmentsView.swift` — my change is only the build fix (`func xAt/yAt` →
  `let` closures, ~line 277). The rest is the pre-existing Trends redesign; commit
  it whenever you're ready to commit that file.
- `20260718120000_…sql` — 100% mine; the typed-note enqueue migration.

---

## 4. WIP-entangled files — `git add -p` (my hunks share diffs with your WIP)
For each, run `git add -p <file>` and stage the hunks matching the search
strings below. Where a hunk mixes my change with pre-existing WIP, press **e**
and keep only the `+` lines listed (or accept the whole hunk if you also want
that WIP committed — it's your branch).

### `RunningLog/RunningLog/Workouts/VoiceLogViewModel.swift`
Stage hunks containing:
- `var loadFailed = false`  (+ its doc comment "True when the last history load errored")
- `// Auth may not have resolved yet on a cold launch` … the `while userId.isEmpty && authWaits < 10` loop
- `loadFailed = false` (on success) and `loadFailed = true` (in the `catch`)
- `// user_id is REQUIRED` … `insertData.userId = userId`
- `insertData.processingStatus = "pending"`  (was `"not_required"`)
- `struct InsertedRow` … the `Poll for the analysis pass` Task
> Heads-up: the `loadHistory` hunk also contains the pre-existing
> `let rows: [Failable<TrainingLog>]` / `compactMap(\.value)` change (row-by-row
> decode). That's not from this session but it's a good hardening — keep it too
> unless you're isolating it elsewhere.

### `RunningLog/RunningLog/Analysis/FitnessPredictorService.swift`
Stage the hunk containing:
- `func aerobicRange(_ zone: NamedPace, single: Double)` and the three
  `easyPace/moderatePace/steadyPace: aerobicRange(...)` call-sites.
> This hunk also contains the pre-existing "Distance-aware ranges (2026-07-16)"
> `RacePredictionItem` / `makeItem` / `rangeFraction` rewrite. If you want ONLY
> the aerobic-range change, press **e** and keep just the `aerobicRange` func +
> the three `aerobicRange(...)` lines.

### `RunningLog/RunningLog/Analysis/FitnessPredictorView.swift`
My change is 3 small additions inside `paceRow(...)`. Press **e** on that hunk
and keep only:
- `.lineLimit(1)` added to the `Text(subtitle)` modifier chain
- `Spacer()` → `Spacer(minLength: 8)`
- `.lineLimit(1)` and `.fixedSize(horizontal: true, vertical: false)` added to the
  `Text(pace)` modifier chain
> The rest of that hunk (the `pacesContent` Easy/Moderate/Steady/HMP/10K/5K
> rewrite and the `stimulusContent` label changes) is pre-existing redesign WIP.

### `supabase/functions/process-training-memo/index.ts`
Stage hunks containing (the typed-note text branch):
- `.select("user_id, notes, cleaned_notes, audio_url")`  (ownerRow fetch)
- `// A row is processable when it has audio to transcribe OR typed notes`
  … `const typedNotes` / `const hasAudio` / the two skip `return`s
- `// Audio path only: resolve the storage path` … `if (hasAudio) { … audioData = dlData }`
- `// ── Step 1: get the transcript ──` … `if (hasAudio && audioData) {` … the
  `} else { … transcription = typedNotes … }` branch
- `if (analysis.transcription && hasAudio && storagePath)`  (transcript-save guard)
> The big Step-1 hunk also contains the pre-existing "Merge a sibling GPS row
> (Strava/HealthKit)" block (`mergedStreams` / `mergedPaceSegments`). Press **e**
> to drop it if you only want the typed-note change.

---

## 5. Deploy order (after committing)
The typed-note feature spans DB + functions; deploy so the pieces line up:
1. `supabase db push`  (applies `20260717140000` anon-RLS fix — already committed —
   and `20260718120000` typed-note trigger; review the batch first, it also
   carries pre-existing pending migrations)
2. `supabase functions deploy process-training-memo drain-voice-processing-jobs`
3. Live test: type a note with injury/mood language → after the drain cron,
   confirm `mood` set + a `body_mentions`/niggle row + `processing_status='completed'`.

---

*Delete this file (and the two `.patch` files) once everything's landed.*

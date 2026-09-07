# Workout structure correction + parser-reconciliation plan — 2026-06-23

## What triggered this

Maya ran **3k tempo + 3 × (1k @ 10K, 600m @ 5K)**. The app parsed it as
`5500m · 1K · 600m · 1800m` (4 reps). Two distinct failures:

1. **`5500m` opening.** The warmup and the 3k tempo ran fast enough that no
   qualifying recovery fell between them, so they merged into one block.
   (Intended: a warmup, then a 3k tempo.)
2. **`1800m` tail.** The float recoveries inside the last two sets were too
   short / too fast to register as separators, so `1k, 600, 1k, 600` collapsed
   into one `1800m` blob. Set 1 (`1K`, `600m`) survived.

### Root cause

`parsed_structure` geometry comes **100% from `detectWorkBouts`**
(`_shared/shared/workBouts.ts`), a pure velocity-threshold segmenter. The AI
parser's block reconstruction is deliberately thrown away in
`parse-workout-structure/index.ts` step 4b ("DETERMINISTIC GEOMETRY OVERRIDE"),
because the model corrupts per-rep numbers. So the rep boundaries depend only on
two knobs:

- `recoveryFrac: 0.7` — a dip counts as recovery only below 70% of the session's
  **median work velocity**.
- `minRecoverySec: 20` — and only if it lasts ≥20s.

A workout that mixes a ~6:23/mi tempo with ~5:00/mi reps has a high median work
velocity; brief/relaxed float recoveries between fast reps don't clear the bar,
and a warmup run near tempo pace never separates from the tempo. The typed note
("3k tempo + 3×(1k,600)") is, by design (prompt rule 2), used for labels and
target paces only — **never to fix the executed geometry.** And there was no
manual correction path. So a miss stayed a miss.

## Shipped now — manual correction (the safety net)

Decision: **store the correction in `parsed_structure` itself** with an
`edited_by_user: true` flag, rather than adding a new column. Every consumer
already reads `parsed_structure` (iOS rep chart, `generate-workout-insight`
Coach Read, `athlete-state` load math), so the correction is honored everywhere
with zero precedence wiring. No migration required.

Files:

- `_shared/structureOverride.ts` — pure validator/normalizer + `isUserEdited()`
  guard. Re-derives missing paces after a split, recomputes `work.reps` and the
  work summary, renumbers reps, stamps `edited_by_user`/`edited_at`. Tested in
  `_shared/structureOverride.test.ts` (5 tests, all green).
- `parse-workout-structure/index.ts` — selects `parsed_structure`, and **skips
  the overwrite when `isUserEdited()`** unless an explicit `force` is passed. A
  Strava re-sync or re-fire can no longer clobber a correction.
- `correct-workout-structure/index.ts` — new edge function. `save` validates +
  persists the correction; `restore` clears it and force-re-parses from the
  stream. User-JWT IDOR-guarded (owner-only); also accepts service role.
- iOS `Analysis/EditWorkoutStructureSheet.swift` — edit the rep list: relabel,
  split (÷2/÷3), merge-up, delete, reorder, set a headline, restore
  auto-detected.
- iOS `Analysis/WorkoutRepChart.swift` — "Fix reps" button + "EDITED" badge;
  reloads after a save so the fix shows immediately.

### Deploy checklist (team — not done here, per hard rules #9/#3)

- [ ] Add `correct-workout-structure` to the edge-function deploy set.
- [ ] `supabase functions deploy correct-workout-structure` +
      `parse-workout-structure` (the guard change) from a committed SHA.
- [ ] No migration to push (column reused). No prompt change, so the eval gate
      (`check_eval_coverage.py`) does not trip for this change.
- [ ] Add the two new iOS files to the Xcode project/target; build.

### Known limits of the manual editor (acceptable for beta)

- **Split is proportional** (distance + time divided equally), so per-rep paces
  inside a split are uniform rather than re-read from the raw stream. Fine for
  fixing *structure*; a future version can re-derive splits from
  `running_workout_laps` at chosen boundaries.
- The editor seeds from the displayed reps; it doesn't yet pull the raw
  per-second stream for sub-lap precision.

## VERIFIED against live data (2026-06-23, activity 19035729944)

Pulled the real Strava stream + the stored row + laps for Maya's run. The
diagnosis shifted once the data was in hand:

**There are TWO segmentation engines and they disagree.**

1. **Stream-based** (`detectWorkBouts` → `parsed_structure`). Reproduced on the
   real stream: **7 work bouts** (warmup+tempo merged into one ~3500m block,
   then the 6 reps split correctly). The stored `parsed_structure` confirms it:
   13 blocks, `work.reps = 7`. This is *decent*. WorkoutRepChart + Coach Read use
   this path.
2. **Lap-flag-based** (`mergeWorkBouts(running_workout_laps)`, splitting only on
   `is_rest`). The watch wrote 16 laps but flagged only **4** as rest
   (laps 8/10/12/16). Merging on those flags yields exactly the bad
   `5500m · 1K · 600m · 1800m` Maya saw — verified split-by-split (5450m/1299s,
   1000m/188s, 601m/111s, 1812m/396s). The walks during warmup/tempo and the
   last set (laps 4, 6, 14 — 10–12 min/mi) were **not** flagged `is_rest` by the
   watch, so they got swallowed into work blocks.

**The screen in Maya's screenshot is `WorkoutRepReceiptView`**, which preferred
the lap-flag merge over `parsed_structure` whenever the watch flagged *any* rest
(`WorkoutRepReceiptView.swift:821-832`). So it showed the 4-bout version even
though the 7-bout parse existed. `WorkoutRepChart` has the *opposite* precedence
(prefers `parsed_structure`) — the two surfaces disagree by design. **Root cause
of "my workout is off": the Receipt view trusts the watch's unreliable `is_rest`
lap flags.**

Fix shipped this round: `ParsedReps.edited` flag plumbed through
`fetchParsedReps`; `WorkoutRepReceiptView` now lets a hand-correction (or any
`edited_by_user` structure) win over the lap merge. So a saved correction fixes
*both* surfaces.

Still open (recommended): make the Receipt view prefer `parsed_structure` over
the lap merge more generally when the stream-based rep count is higher / the
watch's `is_rest` flags look sparse — the two engines should not contradict each
other. Best long-term: one shared segmentation source of truth (collapses the
`mergeWorkBouts` vs `detectWorkBouts` duplication noted in CLAUDE.md tech-debt).

### Heat adjustment — answer to "did heat affect this, is it even called?"

No. For this run, every heat column on `running_workout_laps` is null
(`temp_f`, `dew_point_f`, `heat_adjusted_pace_sec_per_mile` = 0 rows populated),
so the HEAT-ADJ toggle did nothing. `fetch-workout-weather` IS deployed
(version 8) but: (a) its source lives only in `.perf-worktree/`, not the main
repo (orphaned/drifted); and (b) nothing in the live import path calls it —
`strava-sync` only fires `parse-workout-structure`, never the weather function.
So heat enrichment never runs for synced workouts. Decision needed: either wire
`fetch-workout-weather` into the import pipeline (and bring its source back into
the main tree) or hide the HEAT-ADJ affordance until it's real.

## Next — parser-intent reconciliation (root-cause fix, deferred)

Goal: when the athlete *declares* a structure (typed/voice), reconcile the
deterministic `detectWorkBouts` segmentation against that intent so we mis-parse
far less often — reducing how often the manual editor is needed.

Proposed approach (intent-guided re-segmentation, NOT free LLM geometry):

1. Parse the declared prescription into an expected rep template
   (counts + distances + an optional warmup/tempo lead-in), e.g.
   `3k tempo` then `3 × (1k, 600m)` → `[tempo:3000, 1000, 600, 1000, 600, 1000, 600]`.
2. Run `detectWorkBouts` as today to get GPS-truth work/recovery candidates,
   **but lower the bar for splitting when intent expects more reps**: re-segment
   an over-long bout at its internal velocity minima until its rep count matches
   the template (only within that bout, only when the template demands it).
3. Likewise, peel a warmup off a leading bout when intent declares one and the
   bout's opening sub-segment is materially slower than its tail.
4. Snap resulting bout distances to the template's expected distances when within
   tolerance; keep GPS distances when they diverge (report execution honestly —
   prompt rule 2 still holds: report what was *run*, flagging prescribed-vs-run).
5. Confidence: declared + matched template → high; declared but couldn't match →
   keep auto-segmentation, surface the "Fix reps" nudge.

Constraints (hard rules):

- This **touches `_shared/prompts/parse-workout-structure.v2`** (or its
  successor). Per hard rule #3 + CI gate, it cannot ship without eval cassette
  coverage in `_evals/cassettes/parse-workout-structure.*`. Add cassettes for:
  the warmup+tempo merge, the collapsed-sets case, a clean declared interval
  set, and a no-note inference (must stay conservative).
- Keep the deterministic core deterministic: the re-segmentation should be a
  pure function over the stream + template, unit-tested like `workBouts.ts`,
  with the LLM only labeling/reconciling — never inventing rep boundaries.
- Never let intent *invent* reps that the stream doesn't support (rule 3): if the
  athlete says 6×1k but the GPS shows 4 continuous km, report 4 and flag it.

Open question: whether intent-reconciliation should write `parsed_structure`
directly (and thus be overwritable by re-sync) or be treated like a soft
correction. Recommendation: write it as a normal auto-parse (NOT
`edited_by_user`) so a better stream on re-sync can improve it; reserve the
`edited_by_user` lock for human corrections only.

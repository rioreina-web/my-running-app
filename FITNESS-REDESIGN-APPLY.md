# FITNESS-REDESIGN-APPLY — executing the predictor redesign

Execution brief for the 2026-08-27 fitness-predictor redesign plan. The full
strategy document (diagnosis, target architecture, rationale) is published at
https://claude.ai/code/artifact/60fd0944-6795-4960-a4ef-8b6237a57c50 — this
file is the repo-resident half: what to do, in what order, with which files.

Companion docs (read before Phase 1): FITNESS-MODEL-APPLY.md (current
architecture of record), FITNESS-SCALE-APPLY.md (constants audit, §6 problem
inventory), FITNESS-G0-FINISH-APPLY.md (first replay results),
FITNESS-LEARNING-APPLY.md (what can/can't be learned at n≈1).

## The thesis, in three lines

1. One scalar state (`estimated10KPace`) — can't represent per-distance
   fitness (marathon←MP/steady, half←threshold/MP, 5K/10K←race-pace work).
2. Eight stacked clamps pin the number to the last race — replay measured 8
   weeks of training moving the estimate ~0.3% (G0-FINISH §1.3).
3. No scoring loop — ~20 behavioral constants, n=1 athlete, n=2 scoreable
   races ever. Phase 0 fixes this first; nothing else is honest without it.

Target: one uncertainty-weighted estimator (the raceCurve.ts shrinkage
pattern applied to the whole model). State = level + shape (+ durability),
each with variance. Races = low-variance observations (variance inflated by
conditions-correction size). Sessions = duration-local observations (keep
trainingZoneSignal's ratio pricing — the anchor cancels out of it). EF =
two-directional drift evidence. Load = process model (adapt under load,
decay without — replaces the detraining triad/build gate/buildComparison).
PR floor survives as the only bound (same-distance only). Ranges from
posterior variance.

Enabler: since 2026-08-17 iOS reads the server snapshot and computes nothing.
The engine header's "faithful iOS port — never diverge" constraint is legacy.
No Swift mirroring is required for any of this work.

## Phase 0 — make the model scorable

### 0.1 Commit the G0 work sitting uncommitted on design/ds-sync

Exactly these 15 files (verified 2026-08-27; do NOT sweep the branch's other
uncommitted work — Trends/recovery/iOS changes belong to different programs):

```
FITNESS-G0-FINISH-APPLY.md                                (untracked)
FITNESS-LEARNING-APPLY.md                                 (untracked)
FITNESS-SCALE-APPLY.md                                    (untracked)
scripts/replay-fitness.ts                                 (untracked)
supabase/functions/_shared/fitnessInputs.ts               (untracked)
supabase/functions/_shared/prFloor.ts + prFloor.test.ts   (untracked)
supabase/functions/_shared/buildComparison.ts + .test.ts  (untracked)
supabase/functions/_shared/fitnessPrediction.ts + .test.ts (modified)
supabase/functions/_shared/raceCurve.ts                   (modified)
supabase/functions/_shared/trainingZoneSignal.ts + .test.ts (modified)
supabase/functions/compute-fitness-snapshot/index.ts      (modified)
```

Run `deno test supabase/functions/_shared/fitnessPrediction.test.ts
supabase/functions/_shared/prFloor.test.ts` first (65 tests expected green).
Note G0-FINISH §1.4: deploying this moves the live number +6s at 10K, −16s
at marathon — intended, but say so when shipping.

### 0.2 Session-residual scoring (the n=2 → hundreds unlock)

Extend `scripts/replay-fitness.ts`: at each replay step, before updating the
estimate, price the day's quality sessions against the *prior day's*
estimate (the zone-signal ratio already computes exactly this) and record
the residual. Output an error table over all quality sessions, not just the
2 races. This becomes the loss function every later phase is judged by.

Replay invocation that works (from the 2026-08-26 first run):

```
SUPABASE_URL=https://aqdijapxmjqaetursrde.supabase.co \
SUPABASE_SERVICE_ROLE_KEY=$(grep '^SUPABASE_SERVICE_ROLE_KEY=' web/.env.local | cut -d= -f2-) \
deno run --allow-net --allow-env scripts/replay-fitness.ts \
  --user=03857bf3-6276-4634-b3cc-15cc6d0bc653 --from=2026-01-26 --step=1
```

(That UUID is the real 304-log account; `a7e57a71-1e57-…` is a 5-row
synthetic. Point-in-time is by `created_at`, NOT `workout_date` — 106/307
rows landed >2 days late. Never treat sub-1% replay differences as signal.)

Manual invocation of the deployed function (verified 2026-08-28): the
service auth is a JWT **claim decode**, so it needs the legacy JWT — the
newer `sb_secret_…` key has no claims and gets `{"error":"Service role
required"}`. Use `SUPABASE_SERVICE_ROLE_JWT` from `web/.env.local`:

```sh
KEY=$(grep '^SUPABASE_SERVICE_ROLE_JWT=' web/.env.local | cut -d= -f2-)
curl -s -X POST "https://aqdijapxmjqaetursrde.supabase.co/functions/v1/compute-fitness-snapshot" \
  -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d '{"user_id":"03857bf3-6276-4634-b3cc-15cc6d0bc653"}'
```

(Same-day reruns are safe: the writer updates today's row in place and
`mostRecentPrior` skips same-day rows, so damping stays honest.)

### 0.3 Remaining Phase-0 items

- **Normalize-at-confirmation**: store the neutral time on the race row at
  confirm time — kills the 180-day `weatherByDate` window gap (a >180d-old
  hot race currently anchors raw; known defect, G0-FINISH §2.1).
- **Version `athlete_state.fitness_signal`** (history table or snapshot
  column) so the EF gate becomes scoreable in replay — it's currently OFF in
  replay because the singleton's past values are unknowable.
  **HALF DONE 2026-08-27 (`f54dd70`+1), no migration needed.** Every snapshot
  now records the raw EF buckets it saw at `diagnostics.efficiency_signal` —
  `fitness_snapshots.diagnostics` already exists, so neither a history table
  nor a new column was required. Raw buckets, not the collapsed verdict:
  `efficiencyVerdict`'s eligibility thresholds are themselves unvalidated, and
  storing the verdict would bake them in and leave them unscoreable for the
  same reason the gate is unscoreable now.
  **Remaining half:** teach `fitnessInputs.ts` a replay mode that reads the EF
  signal for a date out of that snapshot's diagnostics instead of the
  singleton, then flip `includeEfficiencySignal` back on in replay. It cannot
  pay off yet — the recording is not retroactive, so the gate stays OFF for
  every historical date no matter what. Landed first precisely because every
  day it is not recorded is a day that can never be scored.
- **Handle both `weather_actual` shapes** in `fitnessInputs.ts`: the sparse
  `open-meteo-backfill` rows carry temp_f + dew_point_f only, no
  adjustment_pct (G0-FINISH §2.2).
- **RESOLVED 2026-08-28 — races confirmed as data, UX demoted to backlog.**
  Rio confirmed verbally that the five detected races are real and the list
  is complete ("haven't raced since April"). All 5 `race_results` rows now
  carry `confirmed_at = 2026-08-28T16:05Z` (live UPDATE, verified;
  `source='detected'` kept as provenance; note appended on each row). The
  standing no-race-auto-inference violation is closed for this athlete.
  Remaining, non-blocking: (a) a lightweight confirm/dismiss prompt for
  FUTURE detections before beta users arrive; (b) when anchoring is next
  touched, restrict `seededRaces` to `confirmed_at IS NOT NULL` — safe now
  that the five are confirmed, a behavior change before.

**Exit gate**: replay emits a session-residual error curve for the shipped
model — the baseline Phase 1 must beat.

## Phase 1 — collapse the clamp stack into one estimator

Build the estimator as a NEW pure module beside the engine (don't edit
`fitnessPrediction.ts` in place); run old + new side by side in replay over
the full history before switching `compute-fitness-snapshot`. The switch
itself is one call-site change.

Replaces (delete once the gate passes): the decay ladder + maintenance
factor + build gate, `compareBuildWindows` credit + athlete-aware caps, the
displacement caps + EF one-way gate (EF becomes symmetric drift evidence),
the unproven-improvement ceiling, the continuous-training 2% cap, and
`fitnessCurve.ts` EWMA damping (the posterior update IS the smoothing).
Keeps: zone-signal session pricing, race normalization (correction size now
also inflates observation variance — replaces `SHAPE_MAX_CORRECTION_PCT` and
the race-beats-floor special case), PR floor (same-distance), abstention
(null > fabricated), diagnostics jsonb (add posterior variance), the
`fitness_snapshots` column contract (consumers don't change).

Cold start = wide prior + first observations, one path. The Feb replay
scored the current cold start at +2.07% — keep that as the bar; do not
delete paths on the strength of code comments (G0-FINISH §2.3).

`evidenceBlend.ts` (orphan) is superseded by this — delete it AFTER
harvesting its tests (its "8 weeks closes >80% of the race→training gap"
case becomes an acceptance test). `athleteProfiles.test.ts`'s six synthetic
profiles must pass against the new module (no constant shaped like one
athlete's histogram).

**Exit gate (all three, via replay)**: Feb +2.07% and Apr −1.08% hold or
improve; session residuals beat the Phase-0 baseline; the 56-day pre-April
window moves materially and monotonically with the training block.

## Phase 2 — per-distance state + real HR evidence

- Promote the fitted exponent from end-stage "tilt" to state; observations
  inform the curve at their own duration; predictions read at target
  distance. Collapse the FOUR `pow(D2/D1, b)` implementations
  (raceCurve.convertAlongCurve, trainingZoneSignal.buildFitnessCurve,
  fitnessPrediction.convertPace, + inline at assembly) into one, owned by
  the estimator.
- Zone-lane readout on the snapshot (speed / threshold / marathon-aerobic:
  trend + evidence counts) — the surface language for "what's improving."
- Wire HR: `fitnessInputs.ts` currently selects NO HR column from
  `running_workout_laps` — add it, widen the lap window past 21d for the
  84d baseline, and adopt the orphaned `expectedHr.ts` (rep-level,
  dew-point/speed/duration-controlled OLS) as the EF observation source.
  Honors LEARNING §4b: heat-adjusted EF only from matched-effort rep
  comparisons, never session averages. Its output shape differs from
  `EfficiencyBucketInput` — adapter needed.
- Fix the 2× grade-formula discrepancy while here: raceNormalization uses
  gain/(distance/2), trainingZoneSignal uses gain/distance. One physical
  model, in effortModel.ts.

**Exit gate**: marathon/half respond to MP/threshold blocks in replay in
ways the 10K number can't explain; curve error no longer structurally
invisible (score shape as half/marathon races get raced).

## Phase 3 — athlete background as priors, then population

Cycle-start priors from PR history + training age + historical volume
(races already fetched all-time; volume needs the longer window).
Experience/event-familiarity caps → prior widths. Real age-grading for the
PR floor (needs birth date — product call for Rio). Partial pooling per
FITNESS-SCALE-APPLY G1–G3, now with a loss function to pool against.

**Exit gate**: all six `athleteProfiles.test.ts` profiles (28:00→58:00 10K)
get sane cold starts and sane responsiveness.

## Hygiene track (anytime, cheap — good Sonnet work)

- Delete dead `pickAnchorIndex` (raceNormalization.ts — no non-test importer).
- Clear stale `.next` chunks referencing the removed web `/predictor` route.
- Fix CLAUDE.md's pace-zone section (documents superseded Easy=MP/0.765,
  Steady=MP/0.925 ratios; paces.ts is the truth).
- Break the two type-import cycles (prFloor.ts, buildComparison.ts ← import
  types from fitnessPrediction.ts, which imports them).
- Unify the "21 days" timescales when the estimator lands (fitnessCurve τ=21
  vs zone-signal half-life=21 — different decays; τ=21 ⇒ half-life 14.6d).
- Retire the engine header's "faithful iOS port" framing.

## Standing rules for every session on this work

- Migrations reach prod ONLY via `supabase db push` from a committed SHA
  (hard rule #9; MCP apply_migration is deny-listed). Preflight:
  `supabase migration list --linked`. Never push a queued migration without
  re-reading live schema. Commit migrations immediately — ~9 concurrent
  sessions share this repo.
- The `diagnostics` jsonb on fitness_snapshots is the debugging tool of
  first resort — read it before theorizing about any number.
- `mostRecentPrior` skips same-UTC-day rows (damping-pin fix, 7ed8153) and
  damps only against rows carrying the `· v2` marker — don't weaken either.
- Raw time is what the athlete ran; neutral time is what it proves. A
  normalized time never mints a PR and is never displayed as run.
- Predictions ship as single number + confidence tier + lifetime PR
  alongside (hard rule #7). Never a bare projection.
- No race auto-inference: detection proposes candidates; only confirmed or
  user-declared races anchor (bias toward false negatives).
- Don't deploy the parked ml-service; don't reintroduce the recovery score.

# Fitness signal — pace-at-HR efficiency trend (2026-06-15)

Implements item **#3** of `the-read-handoff-2026-06-15.md`: the objective
backbone of the daily Read's fitness verdict — *"same pace, HR trending down
over weeks = fitter."* Per-rep pace + HR already lived in
`running_workout_laps` and were detected per-session by the segmentation
module, but were never rolled up across sessions. This adds that roll-up.

## What was built

- **`supabase/functions/_shared/fitnessSignal.ts`** — pure, I/O-free module
  (mirrors `workoutSegmentation.ts`). `computeFitnessSignal(sessions, zones,
  asOf)` returns a `FitnessSignal`.
- **`supabase/functions/_shared/fitnessSignal.test.ts`** — 7 unit tests (EF
  math, bucketing, decoupling sign, decoupling trend, sample gating, window
  cutoff). All green.
- **`athlete-state.ts`** — new `fitness_signal` field on `AthleteState`;
  computed in `rebuildAthleteState` from a dedicated **84-day** laps fetch over
  the block-history logs (the existing execution path only pulls 28 days, too
  short for a trend); rendered into the prompt context in
  `stateToPromptContext` under the FITNESS area.
- **`supabase/migrations/20260615000000_athlete_state_fitness_signal.sql`** —
  adds `fitness_signal jsonb` (append-only satellite, same pattern as
  `20260612120000`; RLS on `athlete_state` already covers the column).

No prompt file was touched — the v4 Read prompt already instructs the model to
narrate ATHLETE STATE trend lines as the source of truth, so the new "Fitness
signal" block is picked up without a prompt change (and without tripping the
eval-coverage CI gate, hard rule #3). Surfacing it more explicitly in the
prompt is a follow-up that should ship with eval cassettes.

## The metric

For each session, the qualifying portion is pooled into an **efficiency
factor** `EF = speed (m/min) / HR (bpm)` — higher = more speed per heartbeat =
fitter. Pooling is distance/time-weighted within a window; HR is
time-weighted, with a 90–205 bpm sanity band to drop sensor dropouts.

Sessions are bucketed by **comparable effort** so we compare like with like:

- `easy` — aerobic bouts of easy/recovery runs (the most frequent, most
  controlled aerobic read; ≥3 mi qualifying distance).
- `threshold` — work reps whose dominant zone is HMP / 10K / MP.
- `interval` — work reps whose dominant zone is 5K / 3K / mile.

For each bucket: **recent** = last 28 days, **baseline** = the prior weeks
(out to 84). A direction (`improving` / `flat` / `declining`) is called only
when EF moves ≥1.5%. Confidence is sample-gated (HIGH = ≥3 recent & ≥4
baseline; MEDIUM = ≥2 & ≥2; buckets below 2/2 are dropped). The pace+HR pair
is surfaced for each window so the Read can say it the coach way ("5:19 @ 164
→ 5:28 @ 167") rather than quote a unitless ratio — and never a point estimate
(hard rule #7).

**Aerobic decoupling** is computed per long run (first-half vs second-half
pace:HR), trended recent vs baseline. Falling = more durable.

A pre-baked `verdict` string picks the sharpest bucket with a real direction
(threshold → interval → easy) and frames it descriptively — no prescription,
no diagnosis.

## Verified against real data (test user 03857bf3…, 84d to 2026-06-15)

```
Easy runs:      7:21/mi @ 145 → 7:12/mi @ 148  (EF 0%,  holding)  [high: 14 vs 31]
Threshold (LT): 5:19/mi @ 164 → 5:28/mi @ 167  (EF -4.5%, slipping)[medium: 2 vs 6]
Intervals (VO2):4:58/mi @ 164 → 5:00/mi @ 168  (EF -3.1%, slipping)[high: 4 vs 5]
Long-run decoupling: -1.6% → 2.3% (less durable) [2 vs 4 long runs]
Verdict: "Threshold (LT) work efficiency has slipped over the last 10 weeks:
          5:19 @ 164 → 5:28 @ 167 — worth watching against how training's felt."
```

This reads correctly: easy aerobic fitness is holding, while recent quality
work (Jun 9 threshold) cost a touch more than the spring block — consistent
with the live Read's active niggles + readiness 4/10. The framing is cautious
and confidence-tagged.

## Known limitations (for the next pass)

1. **Within-bucket composition.** Pooling pace across sessions of differing rep
   zones inside `threshold` (HMP vs 10K vs MP) means a change in session *mix*
   between windows shifts pooled pace independent of fitness. EF (speed/HR)
   absorbs most of this because pace and HR move together, but not perfectly.
   A future version could trend per-zone rather than per-bucket once sample
   density supports it.
2. **Decoupling on progression long runs.** A deliberate fast-finish long run
   reads as positive decoupling ("less durable") even when the negative split
   is intentional. Consider gating decoupling to roughly even-paced long runs.
3. **Heat.** EF uses raw pace + raw HR (so the ratio is internally consistent);
   heat inflates HR and will drag EF down on hot days. Trending over many
   sessions averages this out, and the renderer reminds the Read to pair the
   signal with the Conditions block — but a heat-adjusted EF variant is a
   possible refinement.

## To ship

Deploy is migration-first (hard rule #9 — `supabase db push` from a committed
SHA, never a dashboard/MCP apply):

1. `supabase db push` the new migration (adds the `fitness_signal` column).
2. Deploy any function that rebuilds athlete state (the Read picks it up on the
   next rebuild; `fitness_signal` is null until ≥2 comparable sessions exist in
   each window, so the Read degrades gracefully).
3. Optional follow-up: add an explicit FITNESS-signal directive to
   `daily-read.v4.ts` with eval cassettes, so the model leans on it
   deliberately.

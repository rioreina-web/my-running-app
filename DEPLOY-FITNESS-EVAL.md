# DEPLOY — fitness evaluation (2026-08-15)

Run these in Terminal, in the repo folder. Or hand this file to Claude Code.

```bash
cd ~/my-running-app

# 1 · clear the stale git lock (close any editor / GitHub Desktop first)
rm -f .git/index.lock

# 2 · commit just this work (leaves your other changes alone)
git add supabase/functions/_shared/repSignal.ts \
        supabase/functions/_shared/repSignal.fixtures.ts \
        supabase/functions/_shared/repSignal.test.ts \
        supabase/functions/_shared/raceNormalization.ts \
        supabase/functions/_shared/raceNormalization.test.ts \
        supabase/functions/_shared/qualityLoad.ts \
        supabase/functions/_shared/qualityLoad.test.ts \
        supabase/functions/_shared/fitnessSignal.ts \
        supabase/functions/_shared/fitnessSignal.test.ts \
        supabase/functions/_shared/analyzers/currentFitness.ts \
        supabase/functions/_shared/analyzers/index.ts \
        supabase/functions/compute-workout-features/index.ts \
        supabase/migrations/20260815160000_workout_features_rep_signal.sql \
        CURRENT-FITNESS-APPLY.md REP-RECOVERY-SCORE-APPLY.md \
        RACE-CONFIRM-ONBOARDING-APPLY.md PREDICTOR-ANCHOR-PARITY-APPLY.md \
        DEPLOY-FITNESS-EVAL.md
git commit -m "Fitness evaluation v1: repSignal, race normalization, current_fitness analyzer"

# 3 · apply the migration (adds workout_features.rep_signal)
supabase db push

# 4 · deploy the two functions
supabase functions deploy compute-workout-features
supabase functions deploy ask
```

## Check it worked

- Open **Ask** in the app → new chip: **"How fit am I right now?"**
  (no app update needed — the chip rail comes from the server).
- After your next quality session (4+ reps of 90s+), tell Claude —
  it verifies the first `rep_signal` row against the calibration.

## If something fails

- `db push` complains → run `supabase link` first (project: RunningAppMVP2).
- Deploy fails → paste the error to Claude, nothing else touched.

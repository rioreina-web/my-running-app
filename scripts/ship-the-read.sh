#!/usr/bin/env bash
# Ship the Daily Read v5 work to prod.
#
# Picks up:
#   - migration 20260615000000_athlete_state_fitness_signal.sql
#   - migration 20260615200000_training_log_stats_excluded.sql
#   - migration 20260615210000_create_athlete_settings.sql
#   - migration 20260615220000_daily_coaching_reads_cron.sql
#   - migration 20260615230000_daily_coaching_reads_workout_trigger.sql
#   - migration 20260616120000_daily_coaching_reads_v5_sections.sql
#   - prompt   _shared/prompts/daily-read.v5.ts (+ _shared/prompt-library.ts wiring)
#   - edge fn  coaching-daily-read (v5 sectioned read)
#
# NOT shipped here: the iOS "The Read" narrative screen ships via the app
#   build (see outputs/the-read-narrative-screen-spec-for-xcode-agent-2026-06-15.md).
#
# Hard-rule gates (fail-closed):
#   #9 — refuses to `db push` unless the working tree is fully committed.
#   #3 — runs the eval harness (incl. daily-read.v5) and aborts on any rubric failure.
#
# NOTE: `db push` applies ALL pending migrations on the linked project, not
#   only the ones listed above. Run `supabase migration list` first if unsure.
#
# Usage:
#   ./scripts/ship-the-read.sh <prod-project-ref>
#   PROD_REF=aqdijapxmjqaetursrde ./scripts/ship-the-read.sh

set -euo pipefail

PROJECT_REF="${1:-${PROD_REF:-}}"
if [[ -z "$PROJECT_REF" ]]; then
    echo "ERROR: pass your Supabase prod project ref as arg 1 or PROD_REF env var." >&2
    echo "  ./scripts/ship-the-read.sh aqdijapxmjqaetursrde" >&2
    exit 1
fi

cd "$(dirname "$0")/.."

# ── Gate (hard rule #9): committed SHA only ──────────────────────────
if [[ -n "$(git status --porcelain)" ]]; then
    echo "ERROR (hard rule #9): working tree is dirty — commit the read work before pushing." >&2
    git status --short >&2
    exit 1
fi

# ── Gate (hard rule #3): eval harness must pass ──────────────────────
echo "==> Running eval harness (hard rule #3)"
( cd supabase/functions && deno test --allow-read --allow-env --allow-net _evals/runner.test.ts )

# ── Ship ─────────────────────────────────────────────────────────────
echo "==> Linking project $PROJECT_REF"
supabase link --project-ref "$PROJECT_REF"

echo "==> Pushing migrations"
supabase db push

echo "==> Deploying coaching-daily-read"
supabase functions deploy coaching-daily-read --project-ref "$PROJECT_REF"

echo ""
echo "DONE. iOS 'The Read' narrative screen ships separately via the app build."

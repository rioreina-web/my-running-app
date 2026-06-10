#!/usr/bin/env bash
# Ship the athlete-onboarding + heat-adjustment work to prod.
#
# Picks up:
#   - migration 20260424100000_athlete_plan_ux.sql
#   - migration 20260425200000_athlete_subscription_preferences.sql
#   - migration 20260427100000_scheduled_workout_time_of_day.sql
#   - migration 20260428110000_trigger_workout_insight.sql
#   - migration 20260428120000_backfill_workout_insights.sql
#   - migration 20260428130000_coach_notes.sql
#   - migration 20260508140000_coach_insight_outbox.sql
#   - migration 20260508150000_outbox_trigger_workout_insight.sql
#   - migration 20260508160000_backfill_workout_insights_via_outbox.sql
#   - migration 20260508170000_drain_coach_insight_jobs_cron.sql
#   - edge fn subscribe-to-plan (coach-anchor + profile cascade)
#   - edge fn generate-training-plan (parseIntervals fallback fix)
#   - edge fn fetch-workout-weather (per-workout scheduled_at + refresh_one)
#   - edge fn generate-workout-insight (auth + cost cap + retry-aware)
#   - edge fn drain-coach-insight-jobs (outbox worker, cron-driven)
#
# Usage:
#   PROD_REF=xxxxxxxxxxxxxxxxxxxx ./scripts/ship-onboarding.sh
# or:
#   ./scripts/ship-onboarding.sh xxxxxxxxxxxxxxxxxxxx

set -euo pipefail

PROJECT_REF="${1:-${PROD_REF:-}}"
if [[ -z "$PROJECT_REF" ]]; then
    echo "ERROR: pass your Supabase prod project ref as arg 1 or PROD_REF env var."
    echo "  ./scripts/ship-onboarding.sh abcdefghijklmnop"
    exit 1
fi

cd "$(dirname "$0")/.."

echo "==> Linking project $PROJECT_REF"
supabase link --project-ref "$PROJECT_REF"

echo "==> Pushing migrations"
supabase db push

echo "==> Deploying subscribe-to-plan"
supabase functions deploy subscribe-to-plan --project-ref "$PROJECT_REF"

echo "==> Deploying generate-training-plan"
supabase functions deploy generate-training-plan --project-ref "$PROJECT_REF"

echo "==> Deploying fetch-workout-weather"
supabase functions deploy fetch-workout-weather --project-ref "$PROJECT_REF"

echo "==> Deploying generate-workout-insight"
supabase functions deploy generate-workout-insight --project-ref "$PROJECT_REF"

echo "==> Deploying drain-coach-insight-jobs"
supabase functions deploy drain-coach-insight-jobs --project-ref "$PROJECT_REF"

echo "==> Deploying process-training-memo (pace-anchored prompt)"
supabase functions deploy process-training-memo --project-ref "$PROJECT_REF"

echo ""
echo "DONE. Web changes will deploy when you push to main:"
echo "  git status"
echo "  git add -A && git commit -m 'athlete onboarding: migration + cascades + save-draft fix'"
echo "  git push origin main"

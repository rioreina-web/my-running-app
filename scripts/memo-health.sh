#!/usr/bin/env bash
# "Did the memo pipeline work?" as one command instead of twenty queries.
#
# Reads the memo_pipeline_latency view (migration 20260904210000). Healthy is
# s_to_completed ~8-9s; s_to_rpe ~45-70s is the minute-boundary cron and is
# NOT a fault. A NULL s_to_completed on a row older than a few minutes means
# the memo never finished — that is the one to chase.
set -euo pipefail
PROJECT_REF="aqdijapxmjqaetursrde"
: "${SUPABASE_DB_URL:?set SUPABASE_DB_URL to the project connection string}"
psql "$SUPABASE_DB_URL" -P pager=off <<'SQL'
\echo === last 10 memos ===
select recorded_at, s_to_completed as done_s, s_to_rpe as rpe_s,
       merged_into_run as merged, attempts, status
from memo_pipeline_latency order by recorded_at desc limit 10;

\echo === anything stuck right now ===
select memo_id, recorded_at, status, attempts, processing_error
from memo_pipeline_latency
where status is distinct from 'completed'
  and recorded_at > now() - interval '7 days'
order by recorded_at desc;

\echo === outbox backlog (should be empty) ===
select id, kind, status, attempts, last_error, created_at
from voice_processing_jobs
where status <> 'completed' order by created_at desc limit 10;
SQL

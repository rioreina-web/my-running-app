-- Voice memo pipeline latency alert (2026-08-31).
--
-- The [memo-timing] logs existed for months while a discarded coach_insight
-- silently cost every memo ~9s — nobody was watching. This cron watches the
-- number that matters to the athlete: insert → row-completed, as measured by
-- voice_processing_jobs (created_at = row insert via trigger; completed_at =
-- row completion via trg_complete_voice_job_on_row_complete, same tx).
--
-- Daily at 13:10 UTC (right after daily-llm-spend-alert at 13:00, same Slack
-- webhook). SILENT when healthy — it only posts when the last 24h shows:
--   * p95 insert→completed above 20s (target: ~6s typical), or
--   * any job that exhausted retries (failed), or
--   * any job stuck queued/in_progress for 10+ minutes.

SELECT cron.unschedule('voice-memo-latency-alert')
WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'voice-memo-latency-alert');

SELECT cron.schedule(
  'voice-memo-latency-alert',
  '10 13 * * *',
  $job$
    DO $inner$
    DECLARE
        _webhook_url TEXT;
        _n           BIGINT;
        _p95         NUMERIC;
        _worst       NUMERIC;
        _failed      BIGINT;
        _stuck       BIGINT;
    BEGIN
        _webhook_url := (
            SELECT decrypted_secret FROM vault.decrypted_secrets
            WHERE name = 'slack_alerts_webhook_url' LIMIT 1
        );
        IF _webhook_url IS NULL OR _webhook_url = '' THEN
            RAISE NOTICE 'voice-memo-latency-alert skipped — slack_alerts_webhook_url not configured';
            RETURN;
        END IF;

        SELECT count(*),
               percentile_cont(0.95) WITHIN GROUP
                   (ORDER BY extract(epoch FROM completed_at - created_at)),
               max(extract(epoch FROM completed_at - created_at))
          INTO _n, _p95, _worst
          FROM voice_processing_jobs
         WHERE completed_at IS NOT NULL
           AND created_at > now() - INTERVAL '24 hours';

        SELECT count(*) INTO _failed
          FROM voice_processing_jobs
         WHERE status = 'failed'
           AND created_at > now() - INTERVAL '24 hours';

        SELECT count(*) INTO _stuck
          FROM voice_processing_jobs
         WHERE status IN ('queued', 'in_progress')
           AND created_at < now() - INTERVAL '10 minutes';

        IF (_p95 IS NOT NULL AND _p95 > 20) OR _failed > 0 OR _stuck > 0 THEN
            PERFORM net.http_post(
                url     := _webhook_url,
                headers := jsonb_build_object('Content-Type', 'application/json'),
                body    := jsonb_build_object(
                    'text', format(
                        ':stopwatch: *Voice memo pipeline (24h)* — p95 %ss insert→completed across %s jobs (worst %ss). Failed: %s. Stuck >10min: %s.%s',
                        COALESCE(round(_p95, 1)::text, 'n/a'),
                        _n,
                        COALESCE(round(_worst, 1)::text, 'n/a'),
                        _failed,
                        _stuck,
                        CASE WHEN _failed > 0 OR _stuck > 0
                             THEN E'\nCheck voice_processing_jobs.last_error; runbook: provider-outage rows self-heal, others need a look.'
                             ELSE '' END
                    )
                )
            );
        END IF;
    END
    $inner$;
  $job$
);

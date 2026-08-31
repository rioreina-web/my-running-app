-- The Read is weekly. Retire the daily dispatch.
--
-- Supersedes the dispatch half of `20260824193000_restore_daily_coaching_read_cadence.sql`.
--
-- ── Why ────────────────────────────────────────────────────────────────
-- The 2026-08-24 migration restored a daily 06:00 read alongside the Sunday
-- weekly one, arguing the habit loop: "a morning read reaches them 7x/week."
-- That argument predates the read having a CONVERSATION attached to it.
--
-- Since 2026-08-31 a read ends in a question, and the athlete's answers are
-- stamped onto it (`training_logs.replied_to_read_id`, migration
-- 20260831170000) and fed back into the next read's context. Two cadences
-- writing to the same surface breaks that loop in a way daily-vs-weekly
-- never did on its own:
--
--   * Sunday's weekly read asks "how are you feeling after that big long
--     run?" and the athlete answers Monday morning.
--   * The Monday 06:00 daily read has already replaced it on the surface.
--   * The replies are stamped to Sunday's edition, which nothing displays
--     any more — so the athlete's answers vanish the morning after they
--     were given, and the next read has a fresh question of its own.
--
-- Observed live on 2026-08-31 with exactly this pair of reads. A weekly
-- edition that accumulates a week of replies is the product Rio described
-- ("it's a weekly read"); a daily one that resets the conversation nightly
-- is not.
--
-- ── What changes ───────────────────────────────────────────────────────
--   * `enqueue-daily-coaching-reads` is UNSCHEDULED. One read per week.
--
-- ── What does NOT change ───────────────────────────────────────────────
--   * enqueue_weekly_reads() and its cron: Sunday 18:00 local, activity-
--     gated. Untouched.
--   * enqueue_daily_reads() stays DEFINED (append-only, hard rule #5) —
--     re-scheduling it is the one-line rollback, and it keeps the activity
--     gate the 2026-08-24 migration added.
--   * The manual / on-demand path (pull-to-refresh, empty-state CTA) and
--     the workout_trigger re-render path.
--   * daily_coaching_reads schema. iOS reads the most recent completed row
--     within an 8-day window rather than strictly today's, so the weekly
--     edition stays on screen — and keeps collecting replies — all week.
--
-- If the daily brief comes back, it wants to be its OWN surface with its
-- own table (the 2026-08-24 migration's "different products" note stands):
-- a glanceable morning brief is not a weekly read, and they must not share
-- a row, a question, or a reply thread.
--
-- Hard rules: #5 append-only, #9 prod only via `supabase db push` from a
-- committed SHA.

BEGIN;

DO $$
BEGIN
    BEGIN
        PERFORM cron.unschedule('enqueue-daily-coaching-reads');
        RAISE NOTICE 'enqueue-daily-coaching-reads unscheduled — the Read is weekly';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'enqueue-daily-coaching-reads was not scheduled — nothing to unschedule';
    END;
END;
$$;

COMMENT ON FUNCTION public.enqueue_daily_reads() IS
    'RETIRED 2026-08-31 (migration 20260831180000) — defined but NOT scheduled. '
    'The Read is weekly: one edition per week that collects the athlete''s '
    'replies (training_logs.replied_to_read_id) and feeds them to the next '
    'edition. A second daily cadence writing the same surface stranded those '
    'replies on an edition the app had stopped showing. Re-scheduling this '
    'restores the daily 06:00 Mon-Sat dispatch and re-breaks that loop; give '
    'the daily brief its own surface instead.';

COMMIT;

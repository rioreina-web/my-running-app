-- Layers 2 and 3 of the Aug-11 cost-runaway fix: a ledger of every LLM call we
-- dispatch, and a hard ceiling that stops dispatching when the day's budget is
-- spent.
--
-- WHY THIS EXISTS SEPARATELY FROM THE BUG FIX. 20260813180000 fixes the loop I
-- can see. This file is for the loop I cannot -- it is bug-agnostic. Any future
-- path that queues LLM work, however it is written, hits the same ceiling.
--
-- On 2026-08-11 four things had to fail together for the runaway to cost real
-- money: a trigger fired on a no-op write, a retry cap reset itself to zero, the
-- dispatcher had no ceiling, and the spend alarm read an empty table. Any one of
-- them working would have contained it. This file supplies the third and the
-- foundation of the fourth.
--
-- TWO CEILINGS, DIFFERENT JOBS:
--   * per-subject (default 6 / 24h) -- catches a single row stuck in a cycle,
--     which is exactly the Aug-11 shape, and catches it in minutes rather than
--     at end of day.
--   * global daily (default 250) -- catches everything else, including patterns
--     neither of us has thought of. Normal usage is 40-60 calls/day, so this is
--     ~5x headroom; at Flash rates a full day at the ceiling is about $1.
--
-- WHY DISPATCH TIME AND NOT COMPLETION TIME. The ledger row is written when we
-- decide to make the call, not when it returns. A call that fails still cost a
-- round trip and, more importantly, a runaway that fails 100% of the time is
-- still a runaway. Counting intent is the conservative choice.
--
-- WHY HARD STOP. Chosen deliberately over throttle-and-continue: during beta the
-- worst case is a run's structure parse landing a day late, and jobs are durable
-- so nothing is lost. An alarm that merely warns is what we already had.
--
-- Reversible: DROP the two tables and the function. Raising the ceilings is an
-- UPDATE on public.llm_budget, not a migration.

-- ── The ledger ──────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.llm_call_ledger (
    id            bigserial PRIMARY KEY,
    occurred_at   timestamptz NOT NULL DEFAULT now(),
    surface       text        NOT NULL,
    subject_id    uuid,
    user_id       text,
    model         text,
    input_tokens  integer,
    output_tokens integer
);

COMMENT ON TABLE public.llm_call_ledger IS
  'One row per LLM call we dispatch, written at dispatch time. Feeds the daily '
  'budget ceiling, the per-subject loop detector, and cost reporting. Service '
  'role only -- RLS is on with no policies by design.';
COMMENT ON COLUMN public.llm_call_ledger.surface IS
  'Logical caller: workout_parse, rpe_extract, daily_read, coach_insight, ...';
COMMENT ON COLUMN public.llm_call_ledger.subject_id IS
  'The row the call is ABOUT (usually training_logs.id). The per-subject ceiling '
  'keys on this -- it is what makes a single looping row detectable.';
COMMENT ON COLUMN public.llm_call_ledger.input_tokens IS
  'Filled in after the fact by the edge function when the provider reports usage. '
  'NULL means dispatched-but-not-yet-reported, not zero.';

-- Ceiling checks read "today" and "last 24h" constantly; these two indexes are
-- what keep that a cheap index scan as the ledger grows.
CREATE INDEX IF NOT EXISTS llm_call_ledger_occurred_idx
    ON public.llm_call_ledger (occurred_at DESC);
CREATE INDEX IF NOT EXISTS llm_call_ledger_subject_idx
    ON public.llm_call_ledger (surface, subject_id, occurred_at DESC);

ALTER TABLE public.llm_call_ledger ENABLE ROW LEVEL SECURITY;

-- ── The budget ──────────────────────────────────────────────────────────────
-- Single-row config table. A table and not a constant in the function body so
-- that raising the ceiling during a backfill is an UPDATE and a revert, with no
-- deploy and no chance of the new value being forgotten in code.
CREATE TABLE IF NOT EXISTS public.llm_budget (
    id                      boolean PRIMARY KEY DEFAULT true CHECK (id),
    daily_call_ceiling      integer     NOT NULL DEFAULT 250,
    per_subject_24h_ceiling integer     NOT NULL DEFAULT 6,
    tripped_at              timestamptz,
    updated_at              timestamptz NOT NULL DEFAULT now()
);

INSERT INTO public.llm_budget (id) VALUES (true) ON CONFLICT (id) DO NOTHING;

COMMENT ON TABLE public.llm_budget IS
  'Single-row LLM spend ceiling. Raise daily_call_ceiling temporarily for a '
  'known backfill, then put it back. tripped_at records the last time the hard '
  'stop engaged and is what keeps the Slack alert to once per day.';

ALTER TABLE public.llm_budget ENABLE ROW LEVEL SECURITY;

-- ── Reading the budget without spending it ──────────────────────────────────
-- A dispatcher needs to ask "is there any budget left" BEFORE it claims work,
-- because claiming increments `attempts` and would exhaust jobs that never ran.
-- That question must not itself consume budget, so it gets its own read-only
-- function rather than being faked with a record-then-delete.
CREATE OR REPLACE FUNCTION public.llm_budget_headroom()
RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_catalog, pg_temp
AS $$
    SELECT GREATEST(0, b.daily_call_ceiling - (
               SELECT count(*)::integer
                 FROM public.llm_call_ledger
                WHERE occurred_at >= date_trunc('day', now())))
      FROM public.llm_budget b
     WHERE b.id;
$$;

COMMENT ON FUNCTION public.llm_budget_headroom() IS
  'Calls remaining under today''s ceiling. Read-only -- asking does not spend.';

-- The trip alert lives on its own so both the pre-check path and the
-- per-call path can fire it. If only llm_budget_allows() could alert, a
-- dispatcher that early-exits on zero headroom would go quiet at exactly the
-- moment it most needs to shout.
CREATE OR REPLACE FUNCTION public.llm_budget_note_trip(_surface text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog, pg_temp
AS $$
DECLARE
    _tripped timestamptz;
    _cap     integer;
    _webhook text;
BEGIN
    SELECT tripped_at, daily_call_ceiling INTO _tripped, _cap
      FROM public.llm_budget WHERE id;

    -- Once per calendar day. A runaway would otherwise also run away with the
    -- Slack rate limit.
    IF _tripped IS NOT NULL AND _tripped >= date_trunc('day', now()) THEN
        RETURN;
    END IF;

    UPDATE public.llm_budget SET tripped_at = now(), updated_at = now() WHERE id;

    _webhook := (SELECT decrypted_secret FROM vault.decrypted_secrets
                  WHERE name = 'slack_alerts_webhook_url' LIMIT 1);

    IF _webhook IS NULL OR _webhook = '' THEN
        RAISE WARNING 'LLM daily ceiling (%) hit at surface % -- no Slack webhook configured', _cap, _surface;
        RETURN;
    END IF;

    PERFORM net.http_post(
        url     := _webhook,
        headers := jsonb_build_object('Content-Type', 'application/json'),
        body    := jsonb_build_object('text', format(
            E':octagonal_sign: *LLM daily ceiling hit -- dispatching STOPPED*\n'
            'Ceiling: %s calls. Blocked at: `%s`.\n'
            'Jobs are queued, not lost; they drain when the ceiling resets at midnight UTC.\n\n'
            'Legitimate backfill? `UPDATE public.llm_budget SET daily_call_ceiling = <n>;` then put it back.\n'
            'Otherwise something is looping -- find it with:\n'
            '```select surface, subject_id, count(*) from llm_call_ledger '
            'where occurred_at >= date_trunc(''day'', now()) group by 1,2 order by 3 desc limit 10;```',
            _cap, _surface))
    );
END;
$$;

-- ── The guard ───────────────────────────────────────────────────────────────
-- Returns true and records the call, or returns false and dispatches nothing.
-- Callable from SQL dispatchers directly and from edge functions over RPC, so
-- there is exactly one implementation of "may I spend money".
CREATE OR REPLACE FUNCTION public.llm_budget_allows(
    _surface text,
    _subject uuid    DEFAULT NULL,
    _user_id text    DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog, pg_temp
AS $$
DECLARE
    _daily_cap    integer;
    _subject_cap  integer;
    _today_calls  integer;
    _subject_hits integer;
BEGIN
    SELECT daily_call_ceiling, per_subject_24h_ceiling
      INTO _daily_cap, _subject_cap
      FROM public.llm_budget WHERE id;

    -- Missing config must not silently disable the brake.
    IF _daily_cap IS NULL THEN
        RAISE WARNING 'llm_budget_allows: no budget row -- refusing to dispatch %', _surface;
        RETURN false;
    END IF;

    -- ── Global daily ceiling ────────────────────────────────────────────────
    SELECT count(*) INTO _today_calls
      FROM public.llm_call_ledger
     WHERE occurred_at >= date_trunc('day', now());

    IF _today_calls >= _daily_cap THEN
        PERFORM public.llm_budget_note_trip(_surface);
        RAISE WARNING 'llm_budget_allows: daily ceiling % reached -- refusing %', _daily_cap, _surface;
        RETURN false;
    END IF;

    -- ── Per-subject ceiling ─────────────────────────────────────────────────
    -- The Aug-11 signature: one row re-processed over and over. Catching it here
    -- costs a handful of calls instead of a day's budget. NULL subject (a call
    -- that is not about one row) is covered by the global ceiling only.
    IF _subject IS NOT NULL THEN
        SELECT count(*) INTO _subject_hits
          FROM public.llm_call_ledger
         WHERE surface = _surface
           AND subject_id = _subject
           AND occurred_at > now() - INTERVAL '24 hours';

        IF _subject_hits >= _subject_cap THEN
            RAISE WARNING 'llm_budget_allows: % has had % calls in 24h for subject % -- refusing (loop suspected)',
                          _surface, _subject_hits, _subject;
            RETURN false;
        END IF;
    END IF;

    INSERT INTO public.llm_call_ledger (surface, subject_id, user_id)
    VALUES (_surface, _subject, _user_id);

    RETURN true;
END;
$$;

COMMENT ON FUNCTION public.llm_budget_allows(text, uuid, text) IS
  'The single answer to "may I spend money on an LLM call". Records the call and '
  'returns true, or returns false having dispatched nothing. Enforces a global '
  'daily ceiling and a per-subject 24h ceiling (loop detector). Added after the '
  '2026-08-11 runaway, in which a parse loop made 1,269 calls unchecked.';

-- Edge functions call these over RPC with the service role. Never the anon or
-- authenticated roles: a client that can call the guard can drain the day's
-- budget with a loop of its own.
REVOKE ALL ON FUNCTION public.llm_budget_allows(text, uuid, text) FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION public.llm_budget_headroom()              FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION public.llm_budget_note_trip(text)         FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.llm_budget_allows(text, uuid, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.llm_budget_headroom()               TO service_role;

-- ── Reporting helper ────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW public.llm_spend_today AS
SELECT
    l.surface,
    l.model,
    count(*)                                        AS calls,
    sum(l.input_tokens)                             AS input_tokens,
    sum(l.output_tokens)                            AS output_tokens,
    round(
        COALESCE(sum(l.input_tokens), 0)::numeric  / 1000000 * COALESCE(p.input_per_1m_usd, 0)
      + COALESCE(sum(l.output_tokens), 0)::numeric / 1000000 * COALESCE(p.output_per_1m_usd, 0)
    , 4)                                            AS est_cost_usd
FROM public.llm_call_ledger l
LEFT JOIN public.llm_model_pricing p ON p.model = l.model
WHERE l.occurred_at >= date_trunc('day', now())
GROUP BY l.surface, l.model, p.input_per_1m_usd, p.output_per_1m_usd
ORDER BY calls DESC;

COMMENT ON VIEW public.llm_spend_today IS
  'Today so far, by surface. Token columns are NULL until edge functions report '
  'usage back -- call counts are trustworthy immediately, costs are not.';

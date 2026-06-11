-- ============================================================================
-- Advisor-driven hardening (2026-06-10):
-- 1. The claim_* outbox RPCs and fn_weekly_plan_rebalance are SECURITY
--    DEFINER and were executable by anon/authenticated via PostgREST —
--    Supabase's default EXECUTE grants to anon/authenticated survive a
--    bare REVOKE FROM PUBLIC. Revoke explicitly; service_role keeps access.
-- 2. llm_model_pricing (20260609 spend-alert migration) had no RLS —
--    hard rule #1. Enable RLS with a read-only policy for signed-in users;
--    writes only via service role (bypasses RLS).
--
-- NOTE (2026-06-11): This file was recovered from the prod migration ledger
-- (supabase_migrations.schema_migrations, version 20260610230628). It was
-- originally applied ad-hoc via MCP and had no repo file — see
-- docs/migration-ledger-reconciliation-2026-06-11.md. Already applied in
-- prod; do NOT re-apply manually.
-- ============================================================================

BEGIN;

REVOKE EXECUTE ON FUNCTION public.claim_coach_insight_jobs(INT) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.claim_coachable_moment_jobs(INT) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.claim_voice_processing_jobs(INT) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.fn_weekly_plan_rebalance() FROM anon, authenticated;

ALTER TABLE public.llm_model_pricing ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Authenticated users can read model pricing" ON public.llm_model_pricing;
CREATE POLICY "Authenticated users can read model pricing"
    ON public.llm_model_pricing FOR SELECT
    TO authenticated
    USING (true);

COMMIT;

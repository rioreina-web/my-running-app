-- ============================================================================
-- Migration: Fix fitness_snapshots RLS policies
-- Date: 2026-03-19
--
-- Re-adds the service_role bypass policy for fitness_snapshots that was
-- removed by the March 13 lockdown migration (20260313100000_lock_down_rls).
-- Also adds anon-key insert support for iOS client userId fallback.
--
-- Idempotent: uses DROP IF EXISTS before CREATE.
-- ============================================================================

-- 1. Service role bypass — full access for edge functions
DROP POLICY IF EXISTS "Service role full access to fitness snapshots" ON fitness_snapshots;
CREATE POLICY "Service role full access to fitness snapshots" ON fitness_snapshots
    FOR ALL USING (auth.role() = 'service_role')
    WITH CHECK (auth.role() = 'service_role');

-- 2. Anon role insert — iOS client may use anon key with userId fallback
DROP POLICY IF EXISTS "Anon insert own fitness snapshots" ON fitness_snapshots;
CREATE POLICY "Anon insert own fitness snapshots" ON fitness_snapshots
    FOR INSERT WITH CHECK (
        auth.role() = 'anon' AND user_id IS NOT NULL
    );

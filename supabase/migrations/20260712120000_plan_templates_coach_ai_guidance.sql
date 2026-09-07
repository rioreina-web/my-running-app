-- ============================================================================
-- plan_templates — coach AI guidance (rules, guidelines & silent note)
-- (adaptive-plan-builder-opus-buildplan-2026-07-05.md, Phase 2)
--
-- Coaches write hard rules, softer guidelines, and a silent context note on a
-- plan. The reschedule assistant reads them and treats hard rules as
-- constraints it will not violate, guidelines as preferences, and the note as
-- silent context (never surfaced to the athlete). "AI advises, never acts":
-- the assistant still only proposes; the coach/athlete confirms. Nothing here
-- auto-applies.
--
-- Shape (JSONB, nullable — absent = no guidance):
--   {
--     "rules": [ { "on": true, "strength": "hard" | "guide", "text": "…" } ],
--     "note": "free-text context, never shown to the athlete"
--   }
--
-- No RLS changes: plan_templates policies (20260313100000_lock_down_rls.sql)
-- already scope every row to its owning coach via the inline
-- `coach_profile_id IN (SELECT id FROM coach_profiles WHERE user_id = auth.uid())`
-- pattern, and a plain column is covered by those table-level policies. This
-- mirrors the precedent set by 20260703121000_plan_template_shape_columns.sql
-- and 20260706120000_workout_templates_pinned.sql. (The original build plan
-- suggested current_coach_id() here; that helper is NOT the pattern this table
-- uses — see the execution-plan correction, 2026-07-06.)
--
-- The reschedule-plan edge function reads this column with the service role
-- (the athlete who triggers a reschedule cannot read plan_templates under RLS),
-- so guidance stays authoritative and un-tamperable — it is never accepted
-- from the client.
--
-- Hard rule #9: authored only. This reaches prod via `supabase db push` from a
-- committed SHA — never a dashboard/MCP apply. Batch with the other pending
-- authored migrations (20260703*, 20260615*, 20260706*).
-- ============================================================================

BEGIN;

ALTER TABLE plan_templates
    ADD COLUMN IF NOT EXISTS coach_ai_guidance JSONB;

-- Guard the shape at the DB edge: when set, it must be a JSON object (the
-- { rules, note } envelope). Leaves rules/note validation to the app so we
-- don't hard-code the shape into a constraint that a later revision fights.
ALTER TABLE plan_templates
    ADD CONSTRAINT plan_templates_coach_ai_guidance_is_object
        CHECK (coach_ai_guidance IS NULL
               OR jsonb_typeof(coach_ai_guidance) = 'object');

COMMENT ON COLUMN plan_templates.coach_ai_guidance IS
    'Coach-authored guidance for the reschedule assistant: '
    '{ rules: [{on, strength: hard|guide, text}], note }. Hard rules are '
    'MUST-FOLLOW constraints (ranked below the built-in safety guardrails); '
    'guidelines are preferences; note is silent context never shown to the '
    'athlete. Read server-side (service role) by reschedule-plan. '
    'AI advises, never acts — nothing here auto-applies.';

COMMIT;

-- Long-term memory ("it knows you") — memory hygiene + athlete control.
-- Plan: outputs/long-term-memory-implementation-plan-2026-07-02.md, Step 1.
--
-- Append-only (hard rules #1/#5/#9). Adds lifecycle + provenance columns to
-- user_memories so the memo-LLM extractor (Step 2/3) and the weekly
-- consolidation job (Step 4) can dedup-or-reinforce, expire transients, and
-- "forget" honestly — while giving the athlete a revoke path (DELETE) that the
-- iOS Model of You surface (Step 7) wires up.

-- ── Hygiene columns ────────────────────────────────────────────────────────
ALTER TABLE public.user_memories
  ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'active',        -- active | archived
  ADD COLUMN IF NOT EXISTS source text,                                  -- chat_regex | memo_llm | consolidation
  ADD COLUMN IF NOT EXISTS their_words text,                             -- verbatim phrase worth quoting back (episodes)
  ADD COLUMN IF NOT EXISTS memory_date date,                             -- when the remembered thing HAPPENED (episodes)
  ADD COLUMN IF NOT EXISTS last_confirmed_at timestamptz,                -- most recent re-mention (reinforcement signal)
  ADD COLUMN IF NOT EXISTS mention_count integer NOT NULL DEFAULT 1;     -- how many times the athlete has said it

-- Backfill provenance for the pre-existing rows (all from the chat regex
-- extractor in _shared/memory.ts). Idempotent: only stamps rows still null.
UPDATE public.user_memories
  SET source = 'chat_regex'
  WHERE source IS NULL;

-- Seed last_confirmed_at from created_at so recency-weighted selection
-- (Step 5) has a value for legacy rows instead of treating them as never
-- confirmed. Idempotent.
UPDATE public.user_memories
  SET last_confirmed_at = created_at
  WHERE last_confirmed_at IS NULL;

-- ── Athlete self-service: DELETE own memories (memory is revocable) ─────────
-- NOTE: the active policy rls_user_memories_all (20260313100000) is already
-- FOR ALL and thus already permits DELETE of own rows. This explicit policy is
-- redundant with that grant; we add it to document revocability intent as a
-- first-class, independently-auditable guarantee behind the Model of You
-- surface. Adding a second permissive DELETE policy does not narrow access
-- (RLS permissive policies are OR-combined).
DROP POLICY IF EXISTS "Users delete own memories" ON public.user_memories;
CREATE POLICY "Users delete own memories" ON public.user_memories
  FOR DELETE USING (user_id = (auth.uid())::text);

-- ── Index for active-status, category-scoped selection ─────────────────────
-- Step 4 (consolidation) and Step 5 (quota selection) both scan active rows by
-- category ordered by importance. Partial index keeps it cheap as the store
-- grows; archived rows fall out of the hot path.
CREATE INDEX IF NOT EXISTS idx_user_memories_active_category
  ON public.user_memories (user_id, category, importance DESC)
  WHERE status = 'active';

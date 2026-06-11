-- Fix: Update match_coaching_documents to accept text input for embedding
-- The Supabase JS client can't directly pass vector types, so we accept JSON text and cast it
--
-- NOTE (2026-06-11): Recovered from the prod migration ledger (version
-- 20260128, applied January 2026) — the repo never had this file. Already
-- applied in prod; do NOT re-apply. See
-- docs/migration-ledger-reconciliation-2026-06-11.md.

DROP FUNCTION IF EXISTS match_coaching_documents(vector(768), INT, TEXT);

CREATE OR REPLACE FUNCTION match_coaching_documents(
    query_embedding TEXT,
    match_count INT DEFAULT 5,
    filter_category TEXT DEFAULT NULL
)
RETURNS TABLE (
    id UUID,
    title TEXT,
    content TEXT,
    category TEXT,
    similarity FLOAT
)
LANGUAGE plpgsql
AS $$
DECLARE
    embedding_vector vector(768);
BEGIN
    -- Convert JSON text array to vector
    embedding_vector := query_embedding::vector(768);

    RETURN QUERY
    SELECT
        cd.id,
        cd.title,
        cd.content,
        cd.category,
        1 - (cd.embedding <=> embedding_vector) as similarity
    FROM public.coaching_documents cd
    WHERE
        cd.embedding IS NOT NULL
        AND (filter_category IS NULL OR cd.category = filter_category)
    ORDER BY cd.embedding <=> embedding_vector
    LIMIT match_count;
END;
$$;

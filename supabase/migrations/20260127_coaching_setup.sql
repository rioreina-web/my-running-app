-- Enable pgvector extension for vector similarity search
CREATE EXTENSION IF NOT EXISTS vector;

-- Coaching documents table for RAG
CREATE TABLE IF NOT EXISTS public.coaching_documents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title TEXT NOT NULL,
    content TEXT NOT NULL,
    category TEXT NOT NULL CHECK (category IN ('rest', 'recovery', 'mindset', 'training', 'injury', 'nutrition')),
    embedding vector(768), -- Gemini text-embedding-004 outputs 768 dimensions
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- Conversations table for chat history
CREATE TABLE IF NOT EXISTS public.conversations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    messages JSONB DEFAULT '[]',
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.coaching_documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;

-- Allow anonymous access for development
CREATE POLICY "Allow all access to coaching_documents" ON public.coaching_documents
    FOR ALL USING (true) WITH CHECK (true);

CREATE POLICY "Allow all access to conversations" ON public.conversations
    FOR ALL USING (true) WITH CHECK (true);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_coaching_documents_category ON public.coaching_documents(category);
CREATE INDEX IF NOT EXISTS idx_coaching_documents_embedding ON public.coaching_documents
    USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);
CREATE INDEX IF NOT EXISTS idx_conversations_updated_at ON public.conversations(updated_at DESC);

-- Function to match documents by vector similarity
CREATE OR REPLACE FUNCTION match_coaching_documents(
    query_embedding vector(768),
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
BEGIN
    RETURN QUERY
    SELECT
        cd.id,
        cd.title,
        cd.content,
        cd.category,
        1 - (cd.embedding <=> query_embedding) as similarity
    FROM public.coaching_documents cd
    WHERE
        cd.embedding IS NOT NULL
        AND (filter_category IS NULL OR cd.category = filter_category)
    ORDER BY cd.embedding <=> query_embedding
    LIMIT match_count;
END;
$$;

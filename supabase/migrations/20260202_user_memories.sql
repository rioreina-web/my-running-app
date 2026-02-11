-- User Memories: Persistent facts learned from conversations
-- These persist across chat sessions and are retrieved for context

CREATE TABLE IF NOT EXISTS user_memories (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id TEXT NOT NULL,

    -- The memory content
    category TEXT NOT NULL,  -- 'pr', 'injury', 'goal', 'preference', 'training', 'race', 'personal'
    content TEXT NOT NULL,   -- The actual memory/fact

    -- Source tracking
    source_conversation_id UUID,
    extracted_from TEXT,     -- The message it was extracted from (truncated)

    -- Metadata
    importance INTEGER DEFAULT 5,  -- 1-10 scale, higher = more important
    expires_at TIMESTAMPTZ,        -- Optional expiry for temporary facts (e.g., injuries)
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- Indexes for fast retrieval
CREATE INDEX IF NOT EXISTS idx_user_memories_user_id ON user_memories(user_id);
CREATE INDEX IF NOT EXISTS idx_user_memories_category ON user_memories(user_id, category);
CREATE INDEX IF NOT EXISTS idx_user_memories_importance ON user_memories(user_id, importance DESC);

-- Function to clean up expired memories
CREATE OR REPLACE FUNCTION cleanup_expired_memories()
RETURNS void AS $$
BEGIN
    DELETE FROM user_memories
    WHERE expires_at IS NOT NULL AND expires_at < now();
END;
$$ LANGUAGE plpgsql;

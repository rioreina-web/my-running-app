-- ============================================================================
-- Migration: Normalize Conversation Messages
-- Date: 2026-03-13
--
-- Moves messages from JSONB blob in conversations.messages to a proper
-- conversation_messages table. This prevents the JSONB blob from growing
-- unbounded and causing timeouts on read/write for active users.
-- ============================================================================

-- 1. Create the normalized messages table
CREATE TABLE IF NOT EXISTS public.conversation_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    user_id TEXT NOT NULL,
    role TEXT NOT NULL CHECK (role IN ('user', 'assistant')),
    content TEXT NOT NULL,
    proactive BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- 2. Indexes for fast lookups
CREATE INDEX idx_conv_messages_conversation
    ON conversation_messages(conversation_id, created_at DESC);
CREATE INDEX idx_conv_messages_user
    ON conversation_messages(user_id, created_at DESC);

-- 3. RLS
ALTER TABLE conversation_messages ENABLE ROW LEVEL SECURITY;

CREATE POLICY "rls_conv_messages_select" ON conversation_messages
    FOR SELECT USING (user_id = auth.uid()::text);
CREATE POLICY "rls_conv_messages_insert" ON conversation_messages
    FOR INSERT WITH CHECK (user_id = auth.uid()::text);

-- 4. Migrate existing JSONB messages to the new table
-- Each element in the messages array becomes a row
INSERT INTO conversation_messages (conversation_id, user_id, role, content, proactive, created_at)
SELECT
    c.id AS conversation_id,
    COALESCE(c.user_id, 'migrated') AS user_id,
    msg->>'role' AS role,
    msg->>'content' AS content,
    COALESCE((msg->>'proactive')::boolean, false) AS proactive,
    COALESCE((msg->>'timestamp')::timestamptz, c.created_at) AS created_at
FROM conversations c,
     jsonb_array_elements(c.messages) AS msg
WHERE c.messages IS NOT NULL
  AND jsonb_array_length(c.messages) > 0;

-- 5. Keep the messages column for now (backward compat during rollout)
-- but stop writing to it. It can be dropped in a future migration.
COMMENT ON COLUMN conversations.messages IS 'DEPRECATED: Use conversation_messages table instead. Will be dropped in a future migration.';

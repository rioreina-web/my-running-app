-- Content Library: Video storage and metadata for training resources
-- Categories: mobility, drills, strength, recovery, coaches_corner

-- Storage bucket for self-hosted videos
INSERT INTO storage.buckets (id, name, public)
VALUES ('content-videos', 'content-videos', true)
ON CONFLICT (id) DO NOTHING;

-- Allow public read access to videos
CREATE POLICY "Videos are publicly viewable"
ON storage.objects FOR SELECT
USING (bucket_id = 'content-videos');

-- Allow uploads (for admin)
CREATE POLICY "Allow video uploads"
ON storage.objects FOR INSERT
WITH CHECK (bucket_id = 'content-videos');

-- Content library table
CREATE TABLE IF NOT EXISTS content_library (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title TEXT NOT NULL,
    description TEXT,
    category TEXT NOT NULL CHECK (category IN ('mobility', 'drills', 'strength', 'recovery', 'coaches_corner')),
    video_url TEXT NOT NULL,
    thumbnail_url TEXT,
    duration_seconds INTEGER,
    sort_order INTEGER DEFAULT 0,
    is_featured BOOLEAN DEFAULT false,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Index for category filtering
CREATE INDEX IF NOT EXISTS idx_content_library_category ON content_library(category);
CREATE INDEX IF NOT EXISTS idx_content_library_active ON content_library(is_active);

-- Enable RLS
ALTER TABLE content_library ENABLE ROW LEVEL SECURITY;

-- Public read access for active content
CREATE POLICY "Content is viewable by everyone"
ON content_library FOR SELECT
USING (is_active = true);

-- Allow inserts (for admin/seeding)
CREATE POLICY "Allow content inserts"
ON content_library FOR INSERT
WITH CHECK (true);

-- Allow updates (for admin)
CREATE POLICY "Allow content updates"
ON content_library FOR UPDATE
USING (true);

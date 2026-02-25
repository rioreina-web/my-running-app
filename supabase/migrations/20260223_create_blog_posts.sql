-- Blog posts table for the web companion site
CREATE TABLE IF NOT EXISTS blog_posts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  title TEXT NOT NULL,
  slug TEXT UNIQUE NOT NULL,
  content TEXT NOT NULL DEFAULT '',
  excerpt TEXT,
  status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'published', 'archived')),
  published_at TIMESTAMPTZ,
  author_id TEXT,
  tags TEXT[] DEFAULT '{}'
);

-- Index for fast slug lookups
CREATE INDEX IF NOT EXISTS idx_blog_posts_slug ON blog_posts (slug);

-- Index for listing published posts
CREATE INDEX IF NOT EXISTS idx_blog_posts_published ON blog_posts (status, published_at DESC);

-- RLS
ALTER TABLE blog_posts ENABLE ROW LEVEL SECURITY;

-- Published posts are readable by anyone (public blog)
CREATE POLICY "Published posts are publicly readable"
  ON blog_posts FOR SELECT
  USING (status = 'published');

-- Authenticated users can manage posts
CREATE POLICY "Authenticated users can insert posts"
  ON blog_posts FOR INSERT
  TO authenticated
  WITH CHECK (true);

CREATE POLICY "Authenticated users can update posts"
  ON blog_posts FOR UPDATE
  TO authenticated
  USING (true)
  WITH CHECK (true);

-- Dev fallback: allow anon read of published posts
CREATE POLICY "Anon can read published posts"
  ON blog_posts FOR SELECT
  TO anon
  USING (status = 'published');

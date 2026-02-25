import { createClient } from "@/lib/supabase/server";
import { formatDate } from "@/lib/utils";

interface BlogPost {
  id: string;
  title: string;
  slug: string;
  content: string;
  excerpt: string | null;
  published_at: string | null;
  created_at: string;
  status: string;
}

export default async function BlogPage() {
  const supabase = await createClient();

  const { data } = await supabase
    .from("blog_posts")
    .select("id, title, slug, content, excerpt, published_at, created_at, status")
    .eq("status", "published")
    .order("published_at", { ascending: false });

  const posts: BlogPost[] = data || [];

  return (
    <div className="mx-auto max-w-3xl space-y-6">
      <h1 className="font-display text-3xl tracking-wider text-text-primary">
        BLOG
      </h1>

      {posts.length === 0 ? (
        <div className="rounded-xl border border-bg-elevated bg-bg-card p-12 text-center">
          <p className="text-text-tertiary">
            No posts yet. Check back soon!
          </p>
        </div>
      ) : (
        <div className="space-y-6">
          {posts.map((post) => (
            <a
              key={post.id}
              href={`/blog/${post.slug}`}
              className="block rounded-xl border border-bg-elevated bg-bg-card p-6 transition-colors hover:border-coral/30"
            >
              <div className="font-mono text-xs text-text-tertiary">
                {formatDate(post.published_at || post.created_at)}
              </div>
              <h2 className="mt-2 text-xl font-medium text-text-primary">
                {post.title}
              </h2>
              {post.excerpt && (
                <p className="mt-2 text-sm leading-relaxed text-text-secondary">
                  {post.excerpt}
                </p>
              )}
              <span className="mt-3 inline-block font-mono text-xs text-coral">
                Read more →
              </span>
            </a>
          ))}
        </div>
      )}
    </div>
  );
}

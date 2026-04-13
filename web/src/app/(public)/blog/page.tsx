import { createClient } from "@/lib/supabase/server";
import { formatDate } from "@/lib/utils";
import { Card } from "@/components/ui/card";
import { EditorialDivider } from "@/components/ui/editorial-divider";

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
    .select(
      "id, title, slug, content, excerpt, published_at, created_at, status"
    )
    .eq("status", "published")
    .order("published_at", { ascending: false });

  const posts: BlogPost[] = data || [];

  return (
    <div className="mx-auto max-w-3xl px-6 py-16">
      <h1 className="font-display text-4xl text-text-primary">Blog</h1>
      <p className="mt-2 font-body text-base text-text-secondary">
        Training tips, product updates, and running stories.
      </p>

      <EditorialDivider className="my-8" />

      {posts.length === 0 ? (
        <Card>
          <p className="py-8 text-center text-sm italic text-text-tertiary">
            No posts yet. Check back soon!
          </p>
        </Card>
      ) : (
        <div className="space-y-8">
          {posts.map((post) => (
            <a
              key={post.id}
              href={`/blog/${post.slug}`}
              className="block group"
            >
              <Card className="transition-all group-hover:shadow-[0_4px_16px_rgba(0,0,0,0.1)]">
                <div className="font-mono text-xs text-text-tertiary">
                  {formatDate(post.published_at || post.created_at)}
                </div>
                <h2 className="mt-2 font-display text-xl text-text-primary group-hover:text-coral transition-colors">
                  {post.title}
                </h2>
                {post.excerpt && (
                  <p className="mt-2 font-body text-sm leading-relaxed text-text-secondary">
                    {post.excerpt}
                  </p>
                )}
                <span className="mt-3 inline-block font-body text-xs italic text-coral">
                  Read more →
                </span>
              </Card>
            </a>
          ))}
        </div>
      )}
    </div>
  );
}

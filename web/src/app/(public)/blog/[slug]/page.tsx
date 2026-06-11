import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { notFound } from "next/navigation";
import { DropCap } from "@/components/ui/drop-cap";
import DOMPurify from "isomorphic-dompurify";

interface BlogPost {
  id: string;
  title: string;
  slug: string;
  content: string;
  published_at: string | null;
  created_at: string;
}

export default async function BlogPostPage({
  params,
}: {
  params: Promise<{ slug: string }>;
}) {
  const { slug } = await params;
  const supabase = await createClient();

  const { data } = await supabase
    .from("blog_posts")
    .select("id, title, slug, content, published_at, created_at")
    .eq("slug", slug)
    .eq("status", "published")
    .single();

  if (!data) notFound();

  const post: BlogPost = data;

  return (
    <div className="mx-auto max-w-3xl px-6 py-16">
      <Link
        href="/blog"
        className="inline-block font-body text-xs italic text-text-tertiary hover:text-coral transition-colors"
      >
        ← Back to blog
      </Link>

      <article className="mt-8">
        <div className="font-mono text-xs text-text-tertiary">
          {new Date(
            post.published_at || post.created_at
          ).toLocaleDateString("en-US", {
            month: "long",
            day: "numeric",
            year: "numeric",
          })}
        </div>
        <h1 className="mt-3 font-display text-4xl text-text-primary leading-tight">
          {post.title}
        </h1>
        <div className="mt-8 h-px bg-divider" />
        <div className="mt-8 text-sm leading-[1.8] text-text-secondary [&_h2]:mt-10 [&_h2]:mb-4 [&_h2]:font-display [&_h2]:text-xl [&_h2]:text-text-primary [&_h3]:mt-8 [&_h3]:mb-3 [&_h3]:font-display [&_h3]:text-lg [&_h3]:text-text-primary [&_p]:mb-5 [&_ul]:mb-5 [&_ul]:list-disc [&_ul]:pl-6 [&_ol]:mb-5 [&_ol]:list-decimal [&_ol]:pl-6 [&_li]:mb-1.5 [&_a]:text-coral [&_a]:hover:underline [&_blockquote]:my-6 [&_blockquote]:border-l-2 [&_blockquote]:border-coral/30 [&_blockquote]:pl-5 [&_blockquote]:italic [&_blockquote]:text-text-tertiary [&_code]:rounded [&_code]:bg-bg-elevated [&_code]:px-1.5 [&_code]:py-0.5 [&_code]:font-mono [&_code]:text-xs">
          <div dangerouslySetInnerHTML={{ __html: DOMPurify.sanitize(post.content) }} />
        </div>
      </article>
    </div>
  );
}

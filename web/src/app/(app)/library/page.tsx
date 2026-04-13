import { createClient } from "@/lib/supabase/server";
import { Card } from "@/components/ui/card";
import { SectionHeader } from "@/components/ui/section-header";

interface ContentItem {
  id: string;
  title: string;
  description: string | null;
  category: string;
  video_url: string | null;
  thumbnail_url: string | null;
  duration_seconds: number | null;
  is_featured: boolean;
  created_at: string;
}

const CATEGORIES = [
  { key: "all", label: "All" },
  { key: "mobility", label: "Mobility" },
  { key: "drills", label: "Drills" },
  { key: "strength", label: "Strength" },
  { key: "recovery", label: "Recovery" },
  { key: "coaching", label: "Coach's Corner" },
];

export default async function ContentLibraryPage({
  searchParams,
}: {
  searchParams: Promise<{ category?: string }>;
}) {
  const { category } = await searchParams;
  const supabase = await createClient();
  const activeCategory = category || "all";

  let query = supabase
    .from("content_library")
    .select(
      "id, title, description, category, video_url, thumbnail_url, duration_seconds, is_featured, created_at"
    )
    .order("is_featured", { ascending: false })
    .order("created_at", { ascending: false });

  if (activeCategory !== "all") {
    query = query.eq("category", activeCategory);
  }

  const { data } = await query;
  const items: ContentItem[] = data || [];
  const featured = items.find((item) => item.is_featured);
  const rest = items.filter((item) => item !== featured);

  // Group by category for "all" view
  const grouped: Record<string, ContentItem[]> = {};
  rest.forEach((item) => {
    if (!grouped[item.category]) grouped[item.category] = [];
    grouped[item.category].push(item);
  });

  return (
    <div className="mx-auto max-w-5xl space-y-8">
      <h1 className="font-display text-3xl text-text-primary">
        Content Library
      </h1>

      {/* Category filter */}
      <div className="flex gap-2 overflow-x-auto">
        {CATEGORIES.map((cat) => (
          <a
            key={cat.key}
            href={
              cat.key === "all" ? "/library" : `/library?category=${cat.key}`
            }
            className={`whitespace-nowrap rounded-full px-4 py-1.5 font-mono text-xs transition-colors ${
              activeCategory === cat.key
                ? "bg-coral text-white"
                : "bg-bg-elevated text-text-secondary hover:text-text-primary"
            }`}
          >
            {cat.label}
          </a>
        ))}
      </div>

      {items.length === 0 ? (
        <Card>
          <p className="py-8 text-center text-sm italic text-text-tertiary">
            No content available in this category yet.
          </p>
        </Card>
      ) : (
        <div className="space-y-8">
          {/* Featured */}
          {featured && (
            <div>
              <SectionHeader title="Featured" />
              <div className="mt-4">
                <FeaturedCard item={featured} />
              </div>
            </div>
          )}

          {/* Content grid */}
          {activeCategory === "all"
            ? Object.entries(grouped).map(([cat, catItems]) => (
                <div key={cat}>
                  <SectionHeader
                    title={`${cat} (${catItems.length})`}
                  />
                  <div className="mt-4 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
                    {catItems.map((item) => (
                      <VideoCard key={item.id} item={item} />
                    ))}
                  </div>
                </div>
              ))
            : rest.length > 0 && (
                <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
                  {rest.map((item) => (
                    <VideoCard key={item.id} item={item} />
                  ))}
                </div>
              )}
        </div>
      )}
    </div>
  );
}

function FeaturedCard({ item }: { item: ContentItem }) {
  return (
    <Card padding="sm" accent className="overflow-hidden">
      <div className="relative aspect-video bg-bg-elevated rounded-lg overflow-hidden">
        {item.thumbnail_url ? (
          <img
            src={item.thumbnail_url}
            alt={item.title}
            className="h-full w-full object-cover"
          />
        ) : (
          <div className="flex h-full items-center justify-center">
            <span className="text-4xl text-text-tertiary">▶</span>
          </div>
        )}
        {item.duration_seconds && (
          <span className="absolute bottom-2 right-2 rounded bg-black/80 px-2 py-0.5 font-mono text-xs text-white">
            {formatDurationSeconds(item.duration_seconds)}
          </span>
        )}
        <span className="absolute top-2 left-2 rounded bg-coral px-2 py-0.5 font-mono text-[10px] font-medium text-white">
          FEATURED
        </span>
      </div>
      <div className="p-3">
        <h3 className="font-display text-lg text-text-primary">
          {item.title}
        </h3>
        {item.description && (
          <p className="mt-1 text-sm text-text-secondary line-clamp-2">
            {item.description}
          </p>
        )}
      </div>
    </Card>
  );
}

function VideoCard({ item }: { item: ContentItem }) {
  return (
    <Card padding="sm" className="overflow-hidden">
      <div className="relative aspect-video bg-bg-elevated rounded-lg overflow-hidden">
        {item.thumbnail_url ? (
          <img
            src={item.thumbnail_url}
            alt={item.title}
            className="h-full w-full object-cover"
          />
        ) : (
          <div className="flex h-full items-center justify-center">
            <span className="text-2xl text-text-tertiary">▶</span>
          </div>
        )}
        {item.duration_seconds && (
          <span className="absolute bottom-2 right-2 rounded bg-black/80 px-2 py-0.5 font-mono text-xs text-white">
            {formatDurationSeconds(item.duration_seconds)}
          </span>
        )}
      </div>
      <div className="p-2">
        <h3 className="text-sm font-medium text-text-primary">{item.title}</h3>
        {item.description && (
          <p className="mt-1 text-xs text-text-secondary line-clamp-2">
            {item.description}
          </p>
        )}
      </div>
    </Card>
  );
}

function formatDurationSeconds(seconds: number): string {
  const m = Math.floor(seconds / 60);
  const s = seconds % 60;
  return `${m}:${s.toString().padStart(2, "0")}`;
}

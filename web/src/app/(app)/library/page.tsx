import { createClient } from "@/lib/supabase/server";

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
    <div className="mx-auto max-w-5xl space-y-6">
      <h1 className="font-display text-3xl tracking-wider text-text-primary">
        CONTENT LIBRARY
      </h1>

      {/* Category filter */}
      <div className="flex gap-2 overflow-x-auto">
        {CATEGORIES.map((cat) => (
          <a
            key={cat.key}
            href={cat.key === "all" ? "/library" : `/library?category=${cat.key}`}
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
        <div className="rounded-xl border border-bg-elevated bg-bg-card p-12 text-center text-sm text-text-tertiary">
          No content available in this category yet.
        </div>
      ) : (
        <div className="space-y-8">
          {/* Featured */}
          {featured && (
            <div>
              <h2 className="mb-3 font-mono text-xs tracking-widest text-text-tertiary">
                FEATURED
              </h2>
              <FeaturedCard item={featured} />
            </div>
          )}

          {/* Content grid */}
          {activeCategory === "all" ? (
            // Group view
            Object.entries(grouped).map(([cat, catItems]) => (
              <div key={cat}>
                <h2 className="mb-3 font-mono text-xs tracking-widest text-text-tertiary">
                  {cat.toUpperCase()} ({catItems.length})
                </h2>
                <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
                  {catItems.map((item) => (
                    <VideoCard key={item.id} item={item} />
                  ))}
                </div>
              </div>
            ))
          ) : (
            // Flat list for single category
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
    <div className="overflow-hidden rounded-xl border border-coral/30 bg-bg-card">
      <div className="relative aspect-video bg-bg-elevated">
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
      <div className="p-4">
        <h3 className="font-medium text-text-primary">{item.title}</h3>
        {item.description && (
          <p className="mt-1 text-sm text-text-secondary line-clamp-2">
            {item.description}
          </p>
        )}
      </div>
    </div>
  );
}

function VideoCard({ item }: { item: ContentItem }) {
  return (
    <div className="overflow-hidden rounded-xl border border-bg-elevated bg-bg-card transition-colors hover:border-coral/30">
      <div className="relative aspect-video bg-bg-elevated">
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
      <div className="p-3">
        <h3 className="text-sm font-medium text-text-primary">{item.title}</h3>
        {item.description && (
          <p className="mt-1 text-xs text-text-secondary line-clamp-2">
            {item.description}
          </p>
        )}
      </div>
    </div>
  );
}

function formatDurationSeconds(seconds: number): string {
  const m = Math.floor(seconds / 60);
  const s = seconds % 60;
  return `${m}:${s.toString().padStart(2, "0")}`;
}

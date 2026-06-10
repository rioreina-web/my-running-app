import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = {
  title: "Design system previews · Post Run Drip",
  description: "Preview surfaces ported from the design system.",
  robots: { index: false, follow: false },
};

type PreviewEntry = {
  slug: string;
  title: string;
  subtitle: string;
  source: string;
  status: "ported" | "pending";
};

const PREVIEWS: PreviewEntry[] = [
  {
    slug: "training-summary",
    title: "Training summary",
    subtitle: "This week at a glance — the dashboard, in editorial form.",
    source: "training-summary.jsx",
    status: "ported",
  },
  {
    slug: "plan",
    title: "Plan",
    subtitle: "Today · This week · The block. 16-week marathon view.",
    source: "plan.jsx",
    status: "pending",
  },
  {
    slug: "training-analysis",
    title: "Training analysis",
    subtitle: "The long read — where the block has been, where it's going.",
    source: "training-analysis.jsx",
    status: "pending",
  },
  {
    slug: "training-log",
    title: "Training log",
    subtitle: "Editorial journal of voice logs + workout notes + coach feedback.",
    source: "training-log.jsx",
    status: "pending",
  },
  {
    slug: "workout-card",
    title: "Workout card · directions",
    subtitle: "Four direction explorations. Not a final pick — needs deciding.",
    source: "workout-cards.jsx",
    status: "pending",
  },
  {
    slug: "fitness-predictor",
    title: "Fitness predictor",
    subtitle: "Forward read — race prediction across distances.",
    source: "fitness-predictor.jsx",
    status: "pending",
  },
  {
    slug: "plan-builder",
    title: "Plan builder · directions",
    subtitle: "Three web-shaped directions for the coach plan builder.",
    source: "explorations/web/plan-builder/",
    status: "pending",
  },
  {
    slug: "home-alt",
    title: "Home (alt · data-forward)",
    subtitle: "Alternate homepage with analytics section. Sibling to v4 (deployed).",
    source: "home.jsx",
    status: "pending",
  },
];

export default function DesignIndex() {
  return (
    <div className="min-h-screen bg-bg-base text-text-primary font-body">
      <header className="border-b border-divider px-10 py-4">
        <div className="mx-auto max-w-[1080px] flex items-baseline justify-between">
          <span className="font-mono text-[10.5px] tracking-[1.5px] uppercase text-text-secondary">
            Post Run Drip · Design previews
          </span>
          <span className="font-mono text-[10.5px] tracking-[1.5px] uppercase text-text-tertiary">
            Internal · mock data
          </span>
        </div>
      </header>

      <main className="mx-auto max-w-[1080px] px-10 py-16">
        <section>
          <span className="font-mono text-[10.5px] tracking-[1.5px] uppercase text-coral">
            Design system · screen previews
          </span>
          <h1 className="mt-3 font-display text-[56px] leading-[1.0] tracking-[-0.02em]">
            Ported screens.
          </h1>
          <p className="mt-5 max-w-[640px] font-body text-[16px] leading-[1.6] text-text-secondary">
            Each entry renders a design from the Post Run Drip design system
            with mock data. Use these to review the editorial direction live
            in the codebase. None of these routes touch real Supabase data.
          </p>
        </section>

        <section className="mt-16 border-t border-divider">
          {PREVIEWS.map((p, i) => (
            <PreviewRow key={p.slug} entry={p} isLast={i === PREVIEWS.length - 1} />
          ))}
        </section>

        <footer className="mt-16 pt-6 border-t border-divider-soft flex items-center justify-between">
          <span className="font-mono text-[10.5px] tracking-[1.5px] uppercase text-text-tertiary">
            Source · /Users/rioreina/Downloads/Post Run Drip Design System
          </span>
          <Link
            href="/"
            className="font-mono text-[10.5px] tracking-[1.5px] uppercase text-text-primary hover:text-coral transition-colors"
          >
            Back to site ↗
          </Link>
        </footer>
      </main>
    </div>
  );
}

function PreviewRow({
  entry,
  isLast,
}: {
  entry: PreviewEntry;
  isLast: boolean;
}) {
  const isPorted = entry.status === "ported";

  const inner = (
    <div
      className={`grid grid-cols-[80px_1fr_auto] items-baseline gap-6 px-2 py-5 ${
        isPorted ? "hover:bg-bg-elevated transition-colors" : ""
      } ${!isLast ? "border-b border-divider-soft" : ""}`}
    >
      <span
        className={`font-mono text-[10.5px] tracking-[1.5px] uppercase ${
          isPorted ? "text-coral" : "text-text-tertiary"
        }`}
      >
        {isPorted ? "Live" : "Soon"}
      </span>

      <div>
        <h2
          className={`font-display text-[24px] leading-tight tracking-[-0.01em] ${
            isPorted ? "text-text-primary" : "text-text-tertiary"
          }`}
        >
          {entry.title}.
        </h2>
        <p className="mt-1 font-body text-[14px] leading-[1.5] text-text-secondary">
          {entry.subtitle}
        </p>
        <p className="mt-1 font-mono text-[10px] tracking-[1.3px] uppercase text-text-tertiary">
          {entry.source}
        </p>
      </div>

      <span
        className={`font-mono text-[10.5px] tracking-[1.5px] uppercase ${
          isPorted ? "text-text-primary" : "text-text-tertiary"
        }`}
      >
        {isPorted ? "Open ↗" : "—"}
      </span>
    </div>
  );

  if (isPorted) {
    return <Link href={`/design/${entry.slug}`}>{inner}</Link>;
  }
  return inner;
}

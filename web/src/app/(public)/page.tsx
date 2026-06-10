import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = {
  title: "Post Run Drip — A running log",
  description:
    "A running log for runners with a goal time and a base. Voice-log a run, sync your watch, follow a plan.",
};

/* ──────────────────────────────────────────────────────────────────────
   POST RUN DRIP — HOME (ported from home.v4.jsx in the design system)
   Three things only: training log, analysis, plan. Short copy. No theatre.
   ────────────────────────────────────────────────────────────────────── */

export default function LandingPage() {
  return (
    <div className="min-h-screen bg-bg-base text-text-primary font-body">
      <Header />
      <main>
        <Hero />
        <Features />
        <Beta />
      </main>
      <Footer />
    </div>
  );
}

/* ── Helpers ─────────────────────────────────────────────────────── */
function Mono({
  children,
  className = "",
}: {
  children: React.ReactNode;
  className?: string;
}) {
  return (
    <span
      className={`font-mono text-[11px] tracking-[1.5px] uppercase ${className}`}
    >
      {children}
    </span>
  );
}

/* ── HEADER ──────────────────────────────────────────────────────── */
function Header() {
  return (
    <header className="border-b border-divider bg-bg-base/85 backdrop-blur sticky top-0 z-30">
      <div className="mx-auto max-w-[1180px] flex items-center justify-between px-10 py-5 whitespace-nowrap gap-6">
        <Link
          href="/"
          className="font-display text-[22px] tracking-[-0.01em] shrink-0"
        >
          Post Run Drip
        </Link>
        <div className="flex items-center gap-6 shrink-0">
          <Link
            href="/login"
            className="font-body text-[14px] text-text-secondary hover:text-text-primary transition-colors"
          >
            Sign in
          </Link>
          <Link
            href="/login"
            className="rounded-md bg-coral px-4 py-2 font-body text-[14px] font-semibold text-white hover:bg-coral-dark transition-colors"
          >
            Get the app
          </Link>
        </div>
      </div>
    </header>
  );
}

/* ── HERO ────────────────────────────────────────────────────────── */
function Hero() {
  return (
    <section className="border-b border-divider">
      <div className="mx-auto max-w-[1180px] grid lg:grid-cols-[1.1fr_0.9fr] gap-16 px-10 pt-28 pb-28 items-center">
        <div>
          <h1 className="font-display text-[76px] leading-[0.98] tracking-[-0.02em] text-text-primary">
            A running log.
          </h1>
          <p className="mt-8 max-w-[460px] font-body text-[18px] leading-[1.55] text-text-secondary">
            For runners with a goal time and a base. Voice-log a run, sync your
            watch, follow a plan. The training reads itself back to you.
          </p>
          <div className="mt-10 flex items-center gap-3">
            <Link
              href="/login"
              className="rounded-md bg-coral px-6 py-3.5 font-body text-[14px] font-semibold text-white shadow-[0_1px_0_var(--color-coral-dark),0_8px_24px_-8px_rgba(212,89,42,0.45)] hover:bg-coral-dark transition-colors"
            >
              Try the beta
            </Link>
          </div>
        </div>

        <div className="flex justify-center lg:justify-end">
          <ProductCard />
        </div>
      </div>
    </section>
  );
}

function ProductCard() {
  return (
    <div className="w-full max-w-[420px] rounded-lg border border-divider bg-bg-card shadow-[0_30px_60px_-30px_rgba(26,24,21,0.18)] overflow-hidden">
      <div className="flex items-baseline justify-between px-6 py-4 border-b border-divider-soft bg-bg-elevated">
        <Mono className="text-text-tertiary">Running log · Tue</Mono>
        <Mono className="text-text-tertiary">May 12</Mono>
      </div>
      <div className="px-6 pt-6 pb-5">
        <h3 className="font-display text-[28px] tracking-[-0.01em]">
          Progression run
        </h3>
        <p className="mt-1 font-mono text-[12px] text-text-secondary tabular-nums">
          10.0 mi · 7:42 avg · 1:17:24
        </p>
      </div>

      <div className="px-6 pb-6">
        <Mono className="text-text-tertiary">Splits</Mono>
        <svg viewBox="0 0 360 80" className="mt-3 w-full h-20">
          {/* steady stretch */}
          <polyline
            points="10,52 47,48 84,46 121,42 158,40 195,34 232,36 269,34"
            fill="none"
            stroke="#6B8068"
            strokeWidth="2"
          />
          {/* finishing kick */}
          <polyline
            points="269,34 306,17 343,12"
            fill="none"
            stroke="#D4592A"
            strokeWidth="2"
          />
          {/* dots — steady */}
          <circle cx="10" cy="52" r="2.5" fill="#6B8068" />
          <circle cx="47" cy="48" r="2.5" fill="#6B8068" />
          <circle cx="84" cy="46" r="2.5" fill="#6B8068" />
          <circle cx="121" cy="42" r="2.5" fill="#6B8068" />
          <circle cx="158" cy="40" r="2.5" fill="#6B8068" />
          <circle cx="195" cy="34" r="2.5" fill="#6B8068" />
          <circle cx="232" cy="36" r="2.5" fill="#6B8068" />
          <circle cx="269" cy="34" r="2.5" fill="#6B8068" />
          {/* dots — kick */}
          <circle cx="306" cy="17" r="2.5" fill="#D4592A" />
          <circle cx="343" cy="12" r="2.5" fill="#D4592A" />
        </svg>
        <div className="mt-2 flex items-center justify-between">
          <Mono className="text-text-tertiary">Mile 1</Mono>
          <Mono className="text-text-tertiary">Mile 10</Mono>
        </div>
      </div>
    </div>
  );
}

/* ── FEATURES ────────────────────────────────────────────────────── */
function Features() {
  const items = [
    {
      n: "01",
      title: "Log",
      body:
        "Voice-log a run or sync from your watch. Distance, pace, splits, mood — structured automatically.",
    },
    {
      n: "02",
      title: "Analyze",
      body:
        "Twelve weeks of mileage, pace, zones, and load. Plotted properly, with short notes when there's something to say.",
    },
    {
      n: "03",
      title: "Plan",
      body:
        "Goal race in. Plan out. Workouts written like a coach would write them. The week re-tunes when you miss a day.",
    },
  ];

  return (
    <section id="what" className="border-b border-divider bg-bg-elevated">
      <div className="mx-auto max-w-[1180px] px-10 py-24 grid md:grid-cols-3 gap-12">
        {items.map((it) => (
          <div key={it.n}>
            <Mono className="text-coral">{it.n}</Mono>
            <h3 className="mt-3 font-display text-[36px] tracking-[-0.01em] leading-tight">
              {it.title}
            </h3>
            <p className="mt-3 font-body text-[16px] leading-[1.6] text-text-secondary">
              {it.body}
            </p>
          </div>
        ))}
      </div>
    </section>
  );
}

/* ── BETA ────────────────────────────────────────────────────────── */
function Beta() {
  return (
    <section id="start" className="border-b border-divider">
      <div className="mx-auto max-w-[820px] px-10 py-28 text-center">
        <h2 className="font-display text-[56px] leading-[1] tracking-[-0.015em] text-text-primary">
          Try it for a week.
          <br />
          <em className="font-display italic text-coral">
            Tell us what doesn&rsquo;t work.
          </em>
        </h2>
        <p className="mt-8 font-body text-[16px] leading-[1.6] text-text-secondary max-w-[480px] mx-auto">
          iOS, by TestFlight invite. Built for runners with a goal race and a
          base.
        </p>
        <div className="mt-10">
          <Link
            href="/login"
            className="inline-block rounded-md bg-coral px-7 py-4 font-body text-[15px] font-semibold text-white shadow-[0_1px_0_var(--color-coral-dark),0_12px_32px_-12px_rgba(212,89,42,0.45)] hover:bg-coral-dark transition-colors"
          >
            Request a TestFlight invite
          </Link>
        </div>
      </div>
    </section>
  );
}

/* ── FOOTER ──────────────────────────────────────────────────────── */
function Footer() {
  return (
    <footer className="bg-bg-base">
      <div className="mx-auto max-w-[1180px] px-10 py-10 flex flex-wrap items-center justify-between gap-4">
        <div className="font-display text-[20px] tracking-[-0.01em]">
          Post Run Drip
        </div>
        <Mono className="text-text-tertiary">
          © {new Date().getFullYear()} · Austin, TX
        </Mono>
      </div>
    </footer>
  );
}

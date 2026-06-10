/* global React */
const { useState, useEffect } = React;

/* ════════════════════════════════════════════════════════════════════
   POST RUN DRIP — HOME PAGE  (v4 · minimal)
   Three things only: training log, analysis, plan. Short copy. No theatre.
   ════════════════════════════════════════════════════════════════════ */

const HOMEPAGE_TWEAKS = /*EDITMODE-BEGIN*/{
  "headline": "read-carefully",
  "accent": "#D4592A"
}/*EDITMODE-END*/;

const HEADLINES = {
  "read-carefully": { main: "Your training,", italic: "read carefully." },
  "log-it": { main: "Log it,", italic: "and the rest follows." },
};

const ACCENTS = {
  "#D4592A": { hex: "#D4592A", soft: "rgba(212,89,42,0.10)", deep: "#B84420" },
  "#2D6A4F": { hex: "#2D6A4F", soft: "rgba(45,106,79,0.10)", deep: "#1F4D38" },
  "#1F3A5F": { hex: "#1F3A5F", soft: "rgba(31,58,95,0.10)", deep: "#142943" },
};
const ACCENT_KEYS = Object.keys(ACCENTS);

const Mono = ({ children, color, className = "" }) => (
  <span
    className={`font-mono text-[11px] tracking-[1.5px] uppercase ${className}`}
    style={{ color }}
  >
    {children}
  </span>
);

/* ════════════════════════════════════════════════════════════════════ */
function App() {
  const [t, setTweak] = useTweaks(HOMEPAGE_TWEAKS);
  const accent = ACCENTS[t.accent] || ACCENTS["#D4592A"];
  const headline = HEADLINES[t.headline] || HEADLINES["for-the-data"];

  return (
    <div className="min-h-screen bg-bg-base text-text-primary font-body">
      <Header accent={accent} />
      <main>
        <Hero headline={headline} accent={accent} />
        <Features accent={accent} />
        <Beta accent={accent} />
      </main>
      <Footer />

      <TweaksPanel title="Tweaks">
        <TweakSection label="Hook">
          <TweakSelect
            label="Headline"
            value={t.headline}
            onChange={(v) => setTweak("headline", v)}
            options={[
              { value: "read-carefully", label: "Your training, read carefully." },
              { value: "log-it", label: "Log it, and the rest follows." },
            ]}
          />
        </TweakSection>
        <TweakSection label="Visual">
          <TweakColor
            label="Accent"
            value={t.accent}
            onChange={(v) => setTweak("accent", v)}
            options={ACCENT_KEYS}
          />
        </TweakSection>
      </TweaksPanel>
    </div>
  );
}

/* ── HEADER ─────────────────────────────────────────────────────────── */
function Header({ accent }) {
  return (
    <header className="border-b border-divider bg-bg-base/85 backdrop-blur sticky top-0 z-30">
      <div className="mx-auto max-w-[1180px] flex items-center justify-between px-10 py-5 whitespace-nowrap gap-6">
        <a href="#" className="font-display text-[22px] tracking-[-0.01em] shrink-0">
          Post Run Drip
        </a>
        <div className="flex items-center gap-6 shrink-0">
          <a href="#login" className="font-body text-[14px] text-text-secondary hover:text-text-primary">
            Sign in
          </a>
          <a
            href="#start"
            className="rounded-md px-4 py-2 font-body text-[14px] font-semibold text-white transition-colors"
            style={{ backgroundColor: accent.hex }}
          >
            Get the app
          </a>
        </div>
      </div>
    </header>
  );
}

/* ── HERO ───────────────────────────────────────────────────────────── */
function Hero({ headline, accent }) {
  return (
    <section className="border-b border-divider">
      <div className="mx-auto max-w-[1180px] grid lg:grid-cols-[1.1fr_0.9fr] gap-16 px-10 pt-28 pb-28 items-center">
        <div>
          <h1 className="font-display text-[76px] leading-[0.98] tracking-[-0.02em] text-text-primary">
            {headline.main}
            <br />
            <em className="font-display italic" style={{ color: accent.hex }}>
              {headline.italic}
            </em>
          </h1>
          <p className="mt-8 max-w-[460px] font-body text-[18px] leading-[1.55] text-text-secondary">
            iOS, in beta. For runners with a goal time and a base.
          </p>
          <div className="mt-10 flex items-center gap-3">
            <a
              href="#start"
              className="rounded-md px-6 py-3.5 font-body text-[14px] font-semibold text-white"
              style={{
                backgroundColor: accent.hex,
                boxShadow: `0 1px 0 ${accent.deep}, 0 8px 24px -8px ${accent.soft}`,
              }}
            >
              Try the beta
            </a>
          </div>
        </div>

        <div className="flex justify-center lg:justify-end">
          <ProductCard accent={accent} />
        </div>
      </div>
    </section>
  );
}

function ProductCard({ accent }) {
  return (
    <div className="w-full max-w-[420px] rounded-lg border border-divider bg-bg-card shadow-[0_30px_60px_-30px_rgba(26,24,21,0.18)] overflow-hidden">
      <div className="flex items-baseline justify-between px-6 py-4 border-b border-divider-soft bg-bg-elevated">
        <Mono color="#9B9590">RUNNING LOG · TUE</Mono>
        <Mono color="#9B9590">MAY 12</Mono>
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
        <Mono color="#9B9590">SPLITS</Mono>
        <svg viewBox="0 0 360 80" className="mt-3 w-full h-20">
          {(() => {
            const data = [7.80, 7.75, 7.73, 7.70, 7.68, 7.63, 7.67, 7.63, 7.30, 7.20];
            const pts = data.map((v, i) => {
              const x = 10 + i * 37;
              const y = ((v - 7.10) / 0.80) * 60 + 8;
              return [x, y];
            });
            return (
              <>
                <polyline
                  points={pts.slice(0, 8).map(([x, y]) => `${x},${y}`).join(" ")}
                  fill="none"
                  stroke="#6B8068"
                  strokeWidth="2"
                />
                <polyline
                  points={pts.slice(7).map(([x, y]) => `${x},${y}`).join(" ")}
                  fill="none"
                  stroke={accent.hex}
                  strokeWidth="2"
                />
                {pts.map(([x, y], i) => (
                  <circle key={i} cx={x} cy={y} r="2.5" fill={i >= 8 ? accent.hex : "#6B8068"} />
                ))}
              </>
            );
          })()}
        </svg>
        <div className="mt-2 flex items-center justify-between">
          <Mono color="#9B9590">MILE 1</Mono>
          <Mono color="#9B9590">MILE 10</Mono>
        </div>
      </div>
    </div>
  );
}

/* ── FEATURES ───────────────────────────────────────────────────────── */
function Features({ accent }) {
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
            <Mono color={accent.hex}>{it.n}</Mono>
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

/* ── BETA ───────────────────────────────────────────────────────────── */
function Beta({ accent }) {
  return (
    <section id="start" className="border-b border-divider">
      <div className="mx-auto max-w-[820px] px-10 py-28 text-center">
        <h2 className="font-display text-[56px] leading-[1] tracking-[-0.015em] text-text-primary">
          Try it for a week.
          <br />
          <em className="font-display italic" style={{ color: accent.hex }}>
            Tell us what doesn't work.
          </em>
        </h2>
        <p className="mt-8 font-body text-[16px] leading-[1.6] text-text-secondary max-w-[480px] mx-auto">
          iOS, by TestFlight invite. Built for runners with a goal race and a base.
        </p>
        <div className="mt-10">
          <a
            href="#"
            className="inline-block rounded-md px-7 py-4 font-body text-[15px] font-semibold text-white"
            style={{
              backgroundColor: accent.hex,
              boxShadow: `0 1px 0 ${accent.deep}, 0 12px 32px -12px ${accent.soft}`,
            }}
          >
            Request a TestFlight invite
          </a>
        </div>
      </div>
    </section>
  );
}

/* ── FOOTER ─────────────────────────────────────────────────────────── */
function Footer() {
  return (
    <footer className="bg-bg-base">
      <div className="mx-auto max-w-[1180px] px-10 py-10 flex flex-wrap items-center justify-between gap-4">
        <div className="font-display text-[20px] tracking-[-0.01em]">
          Post Run Drip
        </div>
        <Mono color="#9B9590">
          © {new Date().getFullYear()} · Austin, TX
        </Mono>
      </div>
    </footer>
  );
}

/* ── mount ──────────────────────────────────────────────────────────── */
const root = ReactDOM.createRoot(document.getElementById("root"));
root.render(<App />);

/* global React */
/* ════════════════════════════════════════════════════════════════════
   POST RUN DRIP — HOME PAGE  (v5 · data-forward)
   Hero is a magazine plate of charts. An analytics section follows
   with a full marathon-block readout. Editorial voice throughout.
   ════════════════════════════════════════════════════════════════════ */

const { useState } = React;

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
        <Analytics accent={accent} />
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
    <header className="border-b border-divider bg-bg-base sticky top-0 z-30">
      <div className="mx-auto max-w-[1180px] flex items-center justify-between px-10 py-5 whitespace-nowrap gap-6">
        <a href="#" className="font-display text-[22px] tracking-[-0.01em] shrink-0">
          Post Run Drip
        </a>
        <div className="flex items-center gap-6 shrink-0">
          <a href="#analytics" className="font-body text-[14px] text-text-secondary hover:text-text-primary">
            The data
          </a>
          <a href="#what" className="font-body text-[14px] text-text-secondary hover:text-text-primary">
            How it works
          </a>
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

/* ════════════════════════════════════════════════════════════════════
   HERO — magazine plate. Headline left, data plate dominates right.
   Below: a full-width strip of stats from the same block.
   ════════════════════════════════════════════════════════════════════ */
function Hero({ headline, accent }) {
  return (
    <section className="border-b border-divider">
      <div className="mx-auto max-w-[1180px] px-10 pt-20 pb-16">
        {/* plate header */}
        <div className="flex items-baseline justify-between border-b border-divider-soft pb-3 mb-12">
          <Mono color="#9B9590">
            RUNNING LOG — v1 ANALYTICS SURFACE
          </Mono>
          <Mono color="#9B9590">
            FIG. 01 · MARATHON BLOCK · 18 WEEKS
          </Mono>
        </div>

        <div className="grid lg:grid-cols-[1.05fr_1fr] gap-x-16 gap-y-12 items-start">
          {/* ─── left: title block ─── */}
          <div>
            <h1 className="font-display text-[78px] leading-[0.96] tracking-[-0.02em] text-text-primary">
              {headline.main}
              <br />
              <em className="font-display italic" style={{ color: accent.hex }}>
                {headline.italic}
              </em>
            </h1>
            <p className="mt-8 max-w-[440px] font-body text-[18px] leading-[1.55] text-text-secondary">
              Eighteen weeks of marathon work — voice-logged, charted, and read
              like a story. Below: one athlete&rsquo;s block, as the app sees it.
            </p>
            <div className="mt-10 flex items-center gap-5">
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
              <a
                href="#analytics"
                className="font-body text-[14px] text-text-secondary underline decoration-divider underline-offset-[6px] hover:text-text-primary hover:decoration-text-secondary transition-colors"
              >
                Read the whole plate ↓
              </a>
            </div>

            {/* mini info row */}
            <div className="mt-12 grid grid-cols-3 gap-6 max-w-[520px] border-t border-divider-soft pt-6">
              <Stat label="iOS" value="Beta" hint="TestFlight invite" accent={accent} />
              <Stat label="Cohort" value="218" hint="runners in beta" accent={accent} />
              <Stat label="Logs" value="11.4k" hint="voice + sync" accent={accent} />
            </div>
          </div>

          {/* ─── right: the data plate ─── */}
          <HeroDataPlate accent={accent.hex} />
        </div>
      </div>
    </section>
  );
}

function Stat({ label, value, hint, accent }) {
  return (
    <div>
      <Mono color="#9B9590">{label}</Mono>
      <p className="mt-1 font-display text-[24px] tracking-[-0.01em]">{value}</p>
      <p className="font-body text-[12px] text-text-tertiary">{hint}</p>
    </div>
  );
}

/* ── Hero data plate — mileage chart + 4 callouts + prediction ────── */
function HeroDataPlate({ accent }) {
  return (
    <div className="w-full rounded-lg border border-divider bg-bg-card shadow-[0_24px_60px_-30px_rgba(26,24,21,0.22)] overflow-hidden">
      <PlateStrip left="ATHLETE · M.K. · AGE 34" right="MARATHON · OCT 12" />

      <div className="px-6 pt-6 pb-5">
        <p className="font-display text-[14px] tracking-[1.5px] uppercase text-text-tertiary">
          Block
        </p>
        <h3 className="mt-1 font-display text-[28px] tracking-[-0.01em] leading-tight">
          Sub-3:15 marathon build
        </h3>
        <p className="mt-1 font-mono text-[12px] text-text-secondary tabular-nums">
          18 WK · 47.2 MI / WK AVG · PEAK 60.0 MI · 3 DELOADS
        </p>
      </div>

      <div className="px-6 pb-4">
        <div className="flex items-baseline justify-between mb-1.5">
          <Mono color="#9B9590">WEEKLY MILEAGE</Mono>
          <Mono color="#9B9590">MILES / WEEK</Mono>
        </div>
        <MileageChart accent={accent} height={170} />
      </div>

      <div className="grid grid-cols-4 border-t border-divider-soft">
        {[
          ["CTL", "68", "fitness"],
          ["ATL", "52", "fatigue"],
          ["TSB", "+16", "form"],
          ["ACWR", "1.12", "load"],
        ].map(([k, v, hint], i) => (
          <div
            key={k}
            className={`px-4 py-3 ${i < 3 ? "border-r border-divider-soft" : ""}`}
          >
            <Mono color="#9B9590">{k}</Mono>
            <p
              className="mt-1 font-display text-[22px] tracking-[-0.01em] tabular-nums"
              style={{ color: k === "TSB" || k === "ACWR" ? accent : "#1A1815" }}
            >
              {v}
            </p>
            <p className="font-body text-[10px] tracking-[1.2px] uppercase text-text-tertiary">
              {hint}
            </p>
          </div>
        ))}
      </div>

      {/* prediction row — range + confidence (per CLAUDE.md) */}
      <div className="px-6 py-4 border-t border-divider-soft bg-bg-elevated">
        <div className="flex items-baseline justify-between">
          <Mono color="#9B9590">PREDICTED · MARATHON</Mono>
          <Mono color={accent}>HIGH CONFIDENCE</Mono>
        </div>
        <div className="mt-2 grid grid-cols-[1fr_auto_1fr] items-baseline gap-3">
          <span className="font-mono text-[13px] tabular-nums text-text-tertiary text-right">
            3:08:00
          </span>
          <span className="font-display text-[34px] tabular-nums text-text-primary leading-none tracking-[-0.01em]">
            3:11:00
          </span>
          <span className="font-mono text-[13px] tabular-nums text-text-tertiary">
            3:14:00
          </span>
        </div>
        <p className="mt-2 font-body italic text-[12px] leading-[1.45] text-text-tertiary text-center">
          Range, not a finish line. Built from 4 MP workouts and a recent half.
        </p>
      </div>

    </div>
  );
}

/* ════════════════════════════════════════════════════════════════════
   ANALYTICS — the long plate. Six charts laid out like a magazine
   spread. Editorial annotation throughout.
   ════════════════════════════════════════════════════════════════════ */
function Analytics({ accent }) {
  return (
    <section id="analytics" className="border-b border-divider bg-bg-base">
      <div className="mx-auto max-w-[1180px] px-10 pt-24 pb-28">
        {/* plate strip */}
        <div className="flex items-baseline justify-between border-b border-divider-soft pb-3 mb-14">
          <Mono color="#9B9590">FIG. 02 — THE BLOCK, READ END-TO-END</Mono>
          <Mono color="#9B9590">SECTION · ANALYTICS</Mono>
        </div>

        {/* section title */}
        <div className="grid lg:grid-cols-[0.9fr_1.1fr] gap-x-16 gap-y-10 items-end mb-16">
          <div>
            <Mono color={accent.hex}>FROM YOUR COACH</Mono>
            <h2 className="mt-4 font-display text-[60px] leading-[1] tracking-[-0.02em]">
              Twelve weeks,
              <br />
              <em className="font-display italic" style={{ color: accent.hex }}>
                plotted properly.
              </em>
            </h2>
          </div>
          <div className="max-w-[480px] lg:pb-2">
            <p className="font-body text-[17px] leading-[1.6] text-text-secondary">
              Mileage, pace, load, mood, niggles. No vanity charts. Every plot
              answers a question a coach would have asked anyway, and the
              numbers do the talking. Coach voice runs through the margins like
              it would in a journal.
            </p>
            <div className="mt-6">
              <EditorialRule accent={accent.hex} />
            </div>
          </div>
        </div>

        {/* 12-col plate */}
        <div className="grid grid-cols-12 gap-x-6 gap-y-10">
          {/* ── Row 1 — pace progression (8) + load gauge (4) ── */}
          <Tile colSpan={8} eyebrow="FIG. 02a · PACE PROGRESSION" caption="MP held; Easy walked down with it. Twelve clean weeks.">
            <PaceChart accent={accent.hex} />
            <Legend
              items={[
                ["MARATHON PACE", accent.hex],
                ["EASY", "#6B8068"],
              ]}
            />
          </Tile>
          <Tile colSpan={4} eyebrow="FIG. 02b · LOAD" caption="Acute / chronic. 0.8–1.3 is sweet.">
            <LoadGauge accent={accent.hex} value={1.12} />
            <div className="mt-3 text-center">
              <p className="font-display text-[36px] tabular-nums leading-none">1.12</p>
              <p className="mt-1 font-mono text-[10px] tracking-[1.5px] uppercase" style={{ color: accent.hex }}>
                Optimal
              </p>
            </div>
          </Tile>

          {/* ── Row 2 — fitness curve (full) ── */}
          <Tile colSpan={12} eyebrow="FIG. 02c · FITNESS · FATIGUE · FORM" caption="CTL (fitness) climbs through Week 14; TSB recovers into taper.">
            <FitnessCurve accent={accent.hex} />
            <Legend
              items={[
                ["CTL · FITNESS", "#1A1815"],
                ["ATL · FATIGUE", "#6B6560", "dashed"],
                ["TSB · FORM", accent.hex],
              ]}
            />
          </Tile>

          {/* ── Row 3 — zone histogram (5) + mood heatmap (7) ── */}
          <Tile colSpan={5} eyebrow="FIG. 02d · TIME IN ZONE" caption="80/20 holds. MP work concentrated weeks 7–14.">
            <ZoneHistogram accent={accent.hex} />
          </Tile>
          <Tile colSpan={7} eyebrow="FIG. 02e · MOOD · 12 WEEKS" caption="One struggling cluster — week 9, the long-run that didn't.">
            <MoodHeatmap accent={accent.hex} />
          </Tile>

          {/* ── Row 4 — niggles (5) + race predictions (7) ── */}
          <Tile colSpan={5} eyebrow="FIG. 02f · NIGGLES" caption="What you said. Verbatim. Detection, not diagnosis.">
            <NigglesList accent={accent.hex} />
          </Tile>
          <Tile colSpan={7} eyebrow="FIG. 02g · RACE PREDICTIONS" caption="Range plus confidence. The seconds aren't a finish line.">
            <RacePredictions accent={accent.hex} />
          </Tile>
        </div>

        {/* coach pull quote */}
        <div className="mt-20 max-w-[760px] mx-auto text-center">
          <Mono color={accent.hex}>FROM YOUR COACH</Mono>
          <p className="mt-4 font-display italic text-[28px] leading-[1.25] tracking-[-0.005em] text-text-primary">
            &ldquo;Tempo locked in — 7:29 average vs. 7:35 four weeks ago. Hold
            the easy days easy. The block is doing its work.&rdquo;
          </p>
          <p className="mt-4 font-mono text-[10.5px] tracking-[1.4px] uppercase text-text-tertiary">
            Week 14 · auto-generated, coach-reviewed
          </p>
        </div>
      </div>
    </section>
  );
}

/* ── Tile — plate-style card ──────────────────────────────────────── */
function Tile({ colSpan = 4, eyebrow, caption, children }) {
  const spanMap = {
    3: "lg:col-span-3",
    4: "lg:col-span-4",
    5: "lg:col-span-5",
    6: "lg:col-span-6",
    7: "lg:col-span-7",
    8: "lg:col-span-8",
    9: "lg:col-span-9",
    12: "lg:col-span-12",
  };
  return (
    <div
      className={`col-span-12 ${spanMap[colSpan]} bg-bg-card border border-divider rounded-lg overflow-hidden shadow-[0_2px_8px_rgba(26,24,21,0.04)]`}
    >
      <div className="px-5 pt-4 pb-3 border-b border-divider-soft">
        <Mono color="#9B9590">{eyebrow}</Mono>
      </div>
      <div className="px-5 py-5">
        {children}
      </div>
      {caption && (
        <div className="px-5 py-3 border-t border-divider-soft bg-bg-elevated">
          <p className="font-body italic text-[12.5px] leading-[1.45] text-text-secondary">
            {caption}
          </p>
        </div>
      )}
    </div>
  );
}

function Legend({ items }) {
  return (
    <div className="mt-3 flex items-center gap-5 flex-wrap">
      {items.map(([lbl, color, variant]) => (
        <span key={lbl} className="inline-flex items-center gap-2">
          {variant === "dashed" ? (
            <svg width="18" height="6" viewBox="0 0 18 6" className="shrink-0">
              <line x1="0" y1="3" x2="18" y2="3" stroke={color} strokeWidth="1.6" strokeDasharray="3 3" />
            </svg>
          ) : (
            <span className="block h-[2px] w-[18px]" style={{ background: color }} />
          )}
          <span className="font-mono text-[9.5px] tracking-[1.3px] text-text-tertiary">{lbl}</span>
        </span>
      ))}
    </div>
  );
}

/* ════════════════════════════════════════════════════════════════════
   FEATURES — three pillars (Log / Analyze / Plan)
   ════════════════════════════════════════════════════════════════════ */
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
        "Twelve weeks of mileage, pace, zones, and load. Plotted properly, with short notes when there&rsquo;s something to say.",
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
            <p className="mt-3 font-body text-[16px] leading-[1.6] text-text-secondary"
               dangerouslySetInnerHTML={{ __html: it.body }} />
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
            Tell us what doesn&rsquo;t work.
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

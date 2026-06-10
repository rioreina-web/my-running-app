/* global React */
const { useState, useEffect, useRef } = React;

/* ════════════════════════════════════════════════════════════════════
   POST RUN DRIP — HOME PAGE  (v3 · editorial plates)
   The landing page is a series of plates from the running-log journal.
   Hero: the log + the data. AI is one quiet plate, not the headline.
   ════════════════════════════════════════════════════════════════════ */

const HOMEPAGE_TWEAKS = /*EDITMODE-BEGIN*/{
  "headline": "no-stones",
  "accent": "#D4592A",
  "showPlateMarkers": true
}/*EDITMODE-END*/;

const HEADLINES = {
  "no-stones": {
    main: "A running log",
    italic: "with no stones",
    italic2: "left unturned.",
  },
  "press": {
    main: "The Press,",
    italic: "for runners.",
  },
  "your-training": {
    main: "Your training,",
    italic: "read carefully.",
  },
};

const ACCENTS = {
  "#D4592A": { hex: "#D4592A", soft: "rgba(212,89,42,0.10)", deep: "#B84420" },
  "#2D6A4F": { hex: "#2D6A4F", soft: "rgba(45,106,79,0.10)", deep: "#1F4D38" },
  "#1F3A5F": { hex: "#1F3A5F", soft: "rgba(31,58,95,0.10)", deep: "#142943" },
};
const ACCENT_KEYS = Object.keys(ACCENTS);

const ZONE = {
  easy: "#6B8068",
  steady: "#B3ADA5",
  threshold: "#D4592A",
  vo2: "#1A1815",
  race: "#1A1815",
};

const ISSUE = {
  pub: "POST RUN DRIP",
  vol: "TRAINING LOG · v1",
  date: "05.2026",
  totalPlates: 7,
};

/* ── shared ────────────────────────────────────────────────────────── */
const Mono = ({ children, color, className = "" }) => (
  <span
    className={`font-mono text-[11px] tracking-[1.5px] uppercase ${className}`}
    style={{ color }}
  >
    {children}
  </span>
);

const Kicker = ({ children, color }) => (
  <span
    className="font-mono text-[11px] font-medium tracking-[2px] uppercase"
    style={{ color }}
  >
    {children}
  </span>
);

/* ════════════════════════════════════════════════════════════════════
   APP
   ════════════════════════════════════════════════════════════════════ */
function App() {
  const [t, setTweak] = useTweaks(HOMEPAGE_TWEAKS);
  const accent = ACCENTS[t.accent] || ACCENTS["#D4592A"];
  const headline = HEADLINES[t.headline] || HEADLINES["no-stones"];

  return (
    <div className="min-h-screen bg-bg-base text-text-primary font-body">
      <Header accent={accent} />
      <main>
        <PlateCover plateNo={1} headline={headline} accent={accent} showMarkers={t.showPlateMarkers} />
        <PlateLog plateNo={2} accent={accent} showMarkers={t.showPlateMarkers} />
        <PlateTrends plateNo={3} accent={accent} showMarkers={t.showPlateMarkers} />
        <PlatePlan plateNo={4} accent={accent} showMarkers={t.showPlateMarkers} />
        <PlateNotes plateNo={5} accent={accent} showMarkers={t.showPlateMarkers} />
        <PlateAudience plateNo={6} accent={accent} showMarkers={t.showPlateMarkers} />
        <PlateBeta plateNo={7} accent={accent} showMarkers={t.showPlateMarkers} />
      </main>
      <Footer />

      <TweaksPanel title="Tweaks">
        <TweakSection label="Hook">
          <TweakSelect
            label="Headline"
            value={t.headline}
            onChange={(v) => setTweak("headline", v)}
            options={[
              { value: "no-stones", label: "A running log with no stones left unturned." },
              { value: "press", label: "The Press, for runners." },
              { value: "your-training", label: "Your training, read carefully." },
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
          <TweakToggle
            label="Show plate markers"
            value={t.showPlateMarkers}
            onChange={(v) => setTweak("showPlateMarkers", v)}
          />
        </TweakSection>
      </TweaksPanel>
    </div>
  );
}

/* ════════════════════════════════════════════════════════════════════
   HEADER
   ════════════════════════════════════════════════════════════════════ */
function Header({ accent }) {
  return (
    <header className="border-b border-divider bg-bg-base/85 backdrop-blur sticky top-0 z-30">
      <div className="mx-auto max-w-[1200px] flex items-center justify-between px-10 py-5 whitespace-nowrap gap-6">
        <a href="#" className="font-display text-[22px] tracking-[-0.01em] shrink-0">
          Post Run Drip
        </a>
        <div className="flex items-center gap-6 shrink-0">
          <a
            href="#login"
            className="font-body text-[14px] text-text-secondary hover:text-text-primary"
          >
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
   PLATE FRAMEWORK
   Each section wraps content with editorial chrome that matches
   the design-journal references (running header, coral kicker,
   bottom caption, plate counter).
   ════════════════════════════════════════════════════════════════════ */
function Plate({ plateNo, category, kicker, caption, accent, showMarkers, children }) {
  return (
    <section className="border-b border-divider">
      <div className="mx-auto max-w-[1200px] px-10 pt-10 pb-12">
        {/* Running header — like FIG. 03 · NEGATIVE SPLITS */}
        {showMarkers && (
          <div className="border-b border-divider pb-3 mb-10 grid grid-cols-2 items-baseline">
            <div>
              <Mono color="#9B9590" className="block">{ISSUE.pub}</Mono>
              <Mono color="#9B9590" className="block">— {category}</Mono>
            </div>
            <div className="text-right">
              <Mono color="#9B9590" className="block">
                FIG. {String(plateNo).padStart(2, "0")}
              </Mono>
              <Mono color="#9B9590" className="block">
                {ISSUE.vol} · {ISSUE.date}
              </Mono>
            </div>
          </div>
        )}

        {/* coral kicker */}
        {kicker && (
          <div className="mt-2">
            <Kicker color={accent.hex}>{kicker}</Kicker>
          </div>
        )}

        {children}

        {/* caption rule + plate counter */}
        {showMarkers && (caption || plateNo) && (
          <>
            <div className="mt-16 border-t border-divider pt-5 grid md:grid-cols-[1fr_auto] gap-6 items-baseline">
              {caption ? (
                <p className="font-display italic text-[15px] leading-[1.5] text-text-secondary max-w-[640px]">
                  {caption}
                </p>
              ) : <span />}
              <Mono color="#9B9590" className="text-right md:text-left">
                PLATE {String(plateNo).padStart(2, "0")} / {String(ISSUE.totalPlates).padStart(2, "0")}
              </Mono>
            </div>
          </>
        )}
      </div>
    </section>
  );
}

/* ════════════════════════════════════════════════════════════════════
   PLATE 01 · COVER
   ════════════════════════════════════════════════════════════════════ */
function PlateCover({ plateNo, headline, accent, showMarkers }) {
  return (
    <Plate
      plateNo={plateNo}
      category="COVER · A TRAINING LOG"
      kicker="A running log + analytics surface, in beta on iOS"
      caption="Built for runners chasing a time. Voice-log a run, sync your watch, get the data plotted properly, follow a plan that moves with the week."
      accent={accent}
      showMarkers={showMarkers}
    >
      <div className="mt-8 grid lg:grid-cols-[1.15fr_0.85fr] gap-16 items-center">
        <div>
          <h1 className="font-display text-[88px] leading-[0.96] tracking-[-0.02em] text-text-primary">
            {headline.main}
            <br />
            <em className="font-display italic" style={{ color: accent.hex }}>
              {headline.italic}
            </em>
            {headline.italic2 && (
              <>
                <br />
                <em className="font-display italic" style={{ color: accent.hex }}>
                  {headline.italic2}
                </em>
              </>
            )}
          </h1>

          <p className="mt-10 max-w-[520px] font-body text-[18px] leading-[1.55] text-text-secondary">
            A training log built to be read. Distance, pace, splits, mood, and
            structure get captured every run — and turned into the kind of
            twelve-week picture a coach would actually look at.
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
            <a
              href="#what"
              className="rounded-md border border-divider px-6 py-3.5 font-body text-[14px] font-medium text-text-secondary hover:border-text-tertiary"
            >
              Read the plates
            </a>
          </div>
        </div>

        {/* Right — phone mock of the log entry */}
        <div className="flex justify-center">
          <PhoneFrame>
            <LogScreen accent={accent} />
          </PhoneFrame>
        </div>
      </div>
    </Plate>
  );
}

/* ════════════════════════════════════════════════════════════════════
   PLATE 02 · THE LOG
   Anatomy of a log entry — what gets captured
   ════════════════════════════════════════════════════════════════════ */
function PlateLog({ plateNo, accent, showMarkers }) {
  return (
    <Plate
      plateNo={plateNo}
      category="THE LOG · CAPTURE"
      kicker="Capture"
      caption="One voice memo — or one synced run — becomes a structured entry. Distance, pace, splits, intervals, mood, location, weather. The data is the foundation; everything else in the app reads from it."
      accent={accent}
      showMarkers={showMarkers}
    >
      <h2 className="mt-3 font-display text-[60px] leading-[0.98] tracking-[-0.015em] text-text-primary">
        Every run,{" "}
        <em className="font-display italic" style={{ color: accent.hex }}>
          a structured entry.
        </em>
      </h2>

      <div className="mt-14 grid md:grid-cols-[1fr_auto_1fr] gap-10 items-stretch">
        {/* Raw voice */}
        <div className="rounded-lg border border-divider bg-bg-card p-7">
          <Mono color="#9B9590" className="block">VOICE NOTE · 0:47</Mono>
          <p className="mt-5 font-display italic text-[19px] leading-[1.5] text-text-secondary">
            “Did ten on the river trail. Held seven forty-two mostly,
            picked it up the last two miles to seven fifteen. Sun was just
            coming up. Legs felt good — better than Tuesday.”
          </p>
          <Mono color="#9B9590" className="block mt-6">— spoken, post-run</Mono>
        </div>

        {/* arrow */}
        <div className="hidden md:flex items-center justify-center">
          <ArrowRight color={accent.hex} />
        </div>

        {/* Parsed entry */}
        <div className="rounded-lg border border-divider bg-bg-card p-7">
          <Mono color="#9B9590" className="block">PARSED ENTRY · MAY 12</Mono>
          <LogRow k="DISTANCE" v="10.0" unit="mi" />
          <LogRow k="MOVING TIME" v="1:17:24" />
          <LogRow k="AVG PACE" v="7:42" unit="/ mi" />
          <LogRow k="SPLITS · 1–8" v="7:48 · 7:45 · 7:44 · 7:42 · 7:41 · 7:38 · 7:40 · 7:38" small />
          <LogRow k="SPLITS · 9–10" v="7:18 · 7:12" highlight={accent.hex} />
          <LogRow k="STRUCTURE" v="Progression · last 2 @ MP" />
          <LogRow k="MOOD" v="Positive" />
          <LogRow k="WEATHER" v="62° · clear · wind 4mph N" />
          <LogRow k="ROUTE" v="River Trail · loop" />
        </div>
      </div>

      <div className="mt-10 grid md:grid-cols-4 gap-8 border-t border-divider pt-8">
        <Stat k="Captured fields" v="14" sub="per entry" />
        <Stat k="Input methods" v="2" sub="voice or watch sync" />
        <Stat k="Manual typing" v="0" sub="none required" />
        <Stat k="Time to log" v="<1 min" sub="median" accent={accent.hex} />
      </div>
    </Plate>
  );
}

function LogRow({ k, v, unit, highlight, small }) {
  return (
    <div className="mt-3 grid grid-cols-[110px_1fr] gap-4 items-baseline border-t border-divider-soft pt-3">
      <Mono color="#9B9590">{k}</Mono>
      <span
        className={`font-mono tabular-nums ${
          small ? "text-[12px]" : "text-[15px]"
        } font-medium`}
        style={{ color: highlight || "#1A1815" }}
      >
        {v}
        {unit && <span className="text-text-tertiary ml-1 font-normal">{unit}</span>}
      </span>
    </div>
  );
}

function Stat({ k, v, sub, accent }) {
  return (
    <div>
      <Mono color="#9B9590">{k}</Mono>
      <p className="mt-2 font-display text-[36px] tracking-[-0.01em] leading-none" style={{ color: accent || "#1A1815" }}>
        {v}
      </p>
      <p className="mt-1 font-body text-[13px] text-text-tertiary">{sub}</p>
    </div>
  );
}

function ArrowRight({ color }) {
  return (
    <svg width="44" height="14" viewBox="0 0 44 14" fill="none">
      <line x1="0" y1="7" x2="36" y2="7" stroke={color} strokeWidth="1.5" />
      <polyline points="30,1 42,7 30,13" fill="none" stroke={color} strokeWidth="1.5" />
    </svg>
  );
}

/* ════════════════════════════════════════════════════════════════════
   PLATE 03 · TRENDS — the centerpiece
   Multiple charts: weekly mileage, pace progression, zone distribution,
   ACWR, mood, race predictions
   ════════════════════════════════════════════════════════════════════ */
function PlateTrends({ plateNo, accent, showMarkers }) {
  return (
    <Plate
      plateNo={plateNo}
      category="TRENDS · v1 ANALYTICS SURFACE"
      kicker="Accumulation"
      caption="A twelve-week picture of one runner. Volume, where the miles went, and how the body is absorbing the load. Restraint as foundation, intensity as accent."
      accent={accent}
      showMarkers={showMarkers}
    >
      <h2 className="mt-3 font-display text-[60px] leading-[0.98] tracking-[-0.015em] text-text-primary">
        Volume.{" "}
        <em className="font-display italic" style={{ color: accent.hex }}>
          Composition.
        </em>{" "}
        Load.
      </h2>
      <p className="mt-6 max-w-[640px] font-body text-[17px] leading-[1.6] text-text-secondary">
        The trends surface is the spine of the product. The same data the log
        captures, plotted the way a coach would actually want to look at it.
      </p>

      {/* Top row — weekly mileage + acute/chronic */}
      <div className="mt-14 grid md:grid-cols-2 gap-px bg-divider border border-divider rounded-lg overflow-hidden">
        <ChartCard
          fig="A"
          title="Weekly Mileage"
          subtitle="12 weeks · stacked by zone"
          rule="55 MI"
        >
          <WeeklyMileageChart />
          <ChartLegend
            items={[
              { color: ZONE.easy, label: "Easy" },
              { color: ZONE.steady, label: "Steady" },
              { color: ZONE.threshold, label: "Threshold" },
              { color: ZONE.vo2, label: "VO₂ / Race" },
            ]}
          />
        </ChartCard>

        <ChartCard
          fig="B"
          title="Acute : Chronic Ratio"
          subtitle="load balance · last 12 weeks"
          rule="THIS WEEK · 1.18"
        >
          <AcwrChart accent={accent} />
          <p className="mt-4 font-mono text-[10px] tracking-[1.5px] uppercase" style={{ color: ZONE.easy }}>
            <span className="font-semibold">Productive overload</span> · hold steady
          </p>
        </ChartCard>
      </div>

      {/* Middle row — zone distribution + day rhythm */}
      <div className="mt-px grid md:grid-cols-2 gap-px bg-divider border border-divider rounded-lg overflow-hidden">
        <ChartCard
          fig="C"
          title="Where the Miles Went"
          subtitle="distribution by zone · last 30 days"
          rule="47.0 MI · TOTAL"
        >
          <ZoneDistributionChart />
        </ChartCard>

        <ChartCard
          fig="D"
          title="Day-of-Week Rhythm"
          subtitle="cadence · 4-week average"
          rule="SAT · ANCHOR"
        >
          <DayOfWeekChart accent={accent.hex} />
        </ChartCard>
      </div>

      {/* Bottom row — pace + race predictions */}
      <div className="mt-px grid md:grid-cols-[1.4fr_1fr] gap-px bg-divider border border-divider rounded-lg overflow-hidden">
        <ChartCard
          fig="E"
          title="Pace Progression"
          subtitle="easy & threshold zones · 12 weeks"
          rule="THRESHOLD · 6:18/MI"
        >
          <PaceTrendChart accent={accent.hex} />
        </ChartCard>

        <ChartCard fig="F" title="Race Predictions" subtitle="model · 14-day window" rule="">
          <RacePredictions accent={accent.hex} />
        </ChartCard>
      </div>

      {/* Narrative */}
      <div className="mt-12 grid md:grid-cols-[1.3fr_1fr] gap-12 border-t border-divider pt-10">
        <div>
          <Mono color="#9B9590">READ · WEEK 12</Mono>
          <p className="mt-4 flex gap-3">
            <span
              className="font-display text-[72px] leading-[0.85]"
              style={{ color: accent.hex }}
            >
              T
            </span>
            <span className="font-body text-[16.5px] leading-[1.6] text-text-secondary">
              welve weeks in, volume is up 38% from the start of the block —
              steadily, with one deload at week eight. Easy mileage is doing
              the heavy lifting; threshold has crept from 3 to 6 miles per
              week. Acute-to-chronic ratio sits at 1.18, comfortably inside
              the productive band. Nothing here says push harder; nothing
              says back off.
            </span>
          </p>
        </div>
        <div className="grid grid-cols-2 gap-x-6 gap-y-5 self-center">
          <Stat k="Volume · 12 wk" v="+38%" sub="vs starting week" accent={accent.hex} />
          <Stat k="Easy share" v="78%" sub="of total miles" />
          <Stat k="Threshold load" v="×2.1" sub="vs week 1" />
          <Stat k="ACWR" v="1.18" sub="productive" />
        </div>
      </div>
    </Plate>
  );
}

/* ── chart shell ─── */
function ChartCard({ fig, title, subtitle, rule, children }) {
  return (
    <div className="bg-bg-card p-7">
      <div className="flex items-baseline justify-between">
        <div>
          <Mono color="#9B9590">OPTION {fig}</Mono>
          <h3 className="mt-1.5 font-display text-[22px] tracking-[-0.01em] leading-[1.15]">
            {title}
          </h3>
          <p className="mt-1 font-body italic text-[13.5px] text-text-secondary">
            {subtitle}
          </p>
        </div>
        {rule && <Mono color="#9B9590">{rule}</Mono>}
      </div>
      <div className="mt-6">{children}</div>
    </div>
  );
}

function ChartLegend({ items }) {
  return (
    <div className="mt-4 flex flex-wrap gap-x-5 gap-y-2">
      {items.map((it) => (
        <span key={it.label} className="flex items-center gap-1.5 font-mono text-[10px] tracking-[1px] uppercase text-text-tertiary">
          <span className="inline-block h-2.5 w-2.5 rounded-sm" style={{ background: it.color }} />
          {it.label}
        </span>
      ))}
    </div>
  );
}

/* ── individual charts ── */
function WeeklyMileageChart() {
  // 12 weeks, stacked zones: easy / steady / threshold / vo2
  const weeks = [
    [20, 6, 1, 0],
    [22, 8, 2, 0.5],
    [25, 7, 2, 1],
    [18, 6, 1, 0], // deload
    [27, 9, 3, 1],
    [30, 8, 3, 1.5],
    [32, 9, 4, 2],
    [22, 6, 2, 0], // deload
    [34, 10, 5, 2],
    [36, 11, 5, 2],
    [38, 12, 6, 2.5],
    [40, 11, 6, 3],
  ];
  const max = 60;
  return (
    <svg viewBox="0 0 480 180" className="w-full h-44">
      {/* axis line bottom */}
      <line x1="0" y1="170" x2="480" y2="170" stroke="#E8E4E0" strokeWidth="1" />
      {weeks.map((w, i) => {
        const x = 6 + i * 39;
        const wBar = 30;
        let y = 170;
        const sections = [
          { v: w[0], color: ZONE.easy },
          { v: w[1], color: ZONE.steady },
          { v: w[2], color: ZONE.threshold },
          { v: w[3], color: ZONE.vo2 },
        ];
        return (
          <g key={i}>
            {sections.map((s, j) => {
              const h = (s.v / max) * 150;
              y -= h;
              return (
                <rect
                  key={j}
                  x={x}
                  y={y}
                  width={wBar}
                  height={h}
                  fill={s.color}
                />
              );
            })}
            {(i === 0 || i === 4 || i === 8 || i === 11) && (
              <text x={x + 15} y={178} textAnchor="middle" fontSize="9" fontFamily="ui-monospace,Menlo,monospace" fill="#9B9590">
                {i === 11 ? "NOW" : "W" + (i + 1)}
              </text>
            )}
          </g>
        );
      })}
    </svg>
  );
}

function AcwrChart({ accent }) {
  // 12 weekly points
  const pts = [0.85, 0.92, 1.05, 0.78, 1.12, 1.18, 1.22, 0.95, 1.15, 1.20, 1.25, 1.18];
  const max = 1.5;
  const w = 480, h = 180;
  const xs = pts.map((_, i) => (i / (pts.length - 1)) * (w - 16) + 8);
  const ys = pts.map((p) => h - 16 - (p / max) * (h - 32));
  // productive band 0.8 - 1.3
  const yBandTop = h - 16 - (1.3 / max) * (h - 32);
  const yBandBot = h - 16 - (0.8 / max) * (h - 32);
  const ySpike = h - 16 - (1.5 / max) * (h - 32);

  return (
    <svg viewBox={`0 0 ${w} ${h}`} className="w-full h-44">
      {/* spike zone */}
      <rect x="0" y={ySpike} width={w} height={yBandTop - ySpike} fill={accent.soft} />
      <text x="8" y={ySpike + 14} fontSize="9" fontFamily="ui-monospace,Menlo,monospace" fill="#9B9590">
        SPIKE  &gt; 1.3
      </text>
      {/* productive zone */}
      <rect x="0" y={yBandTop} width={w} height={yBandBot - yBandTop} fill="rgba(107,128,104,0.10)" />
      <text x="8" y={yBandTop + 14} fontSize="9" fontFamily="ui-monospace,Menlo,monospace" fill="#9B9590">
        PRODUCTIVE  0.8 – 1.3
      </text>
      {/* line */}
      <polyline
        points={xs.map((x, i) => `${x},${ys[i]}`).join(" ")}
        stroke={accent.hex}
        strokeWidth="2"
        fill="none"
      />
      {xs.map((x, i) => (
        <circle key={i} cx={x} cy={ys[i]} r="2.5" fill={accent.hex} />
      ))}
    </svg>
  );
}

function ZoneDistributionChart() {
  const rows = [
    { label: "EASY", value: 36.6, color: ZONE.easy },
    { label: "STEADY", value: 6.3, color: ZONE.steady },
    { label: "THRESHOLD", value: 2.6, color: ZONE.threshold },
    { label: "VO₂", value: 1.0, color: ZONE.vo2 },
    { label: "RACE", value: 0.5, color: ZONE.vo2 },
  ];
  const max = Math.max(...rows.map((r) => r.value));
  return (
    <div className="space-y-3 pt-2">
      {rows.map((r) => (
        <div key={r.label} className="grid grid-cols-[80px_1fr_60px] items-center gap-3">
          <Mono color="#9B9590">{r.label}</Mono>
          <div className="h-3.5 bg-bg-elevated relative overflow-hidden">
            <div
              className="absolute inset-y-0 left-0"
              style={{ width: `${(r.value / max) * 100}%`, background: r.color }}
            />
          </div>
          <span className="font-mono text-[12px] tabular-nums text-text-primary text-right">
            {r.value.toFixed(1)} <span className="text-text-tertiary">mi</span>
          </span>
        </div>
      ))}
    </div>
  );
}

function DayOfWeekChart({ accent }) {
  const days = ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"];
  const data = [
    [3, 0, 1, 0],
    [4, 1, 3, 1],
    [5, 2, 4, 1.5],
    [0, 0, 0, 0],
    [4, 1, 1, 0],
    [16, 3, 1, 0],
    [0, 0, 0, 0],
  ];
  const max = 22;
  return (
    <svg viewBox="0 0 480 180" className="w-full h-44">
      <line x1="0" y1="170" x2="480" y2="170" stroke="#E8E4E0" strokeWidth="1" />
      {days.map((d, i) => {
        const x = 22 + i * 64;
        const wBar = 32;
        let y = 170;
        const sections = [
          { v: data[i][0], color: ZONE.easy },
          { v: data[i][1], color: ZONE.steady },
          { v: data[i][2], color: ZONE.threshold },
          { v: data[i][3], color: ZONE.vo2 },
        ];
        const total = sections.reduce((a, b) => a + b.v, 0);
        return (
          <g key={d}>
            {sections.map((s, j) => {
              if (!s.v) return null;
              const h = (s.v / max) * 140;
              y -= h;
              return (
                <rect key={j} x={x} y={y} width={wBar} height={h} fill={s.color} />
              );
            })}
            {total === 0 && (
              <line x1={x} y1={168} x2={x + wBar} y2={168} stroke="#D1CCC5" strokeWidth="1" />
            )}
            <text
              x={x + 16}
              y={178}
              textAnchor="middle"
              fontSize="9"
              fontFamily="ui-monospace,Menlo,monospace"
              fill={i === 5 ? accent : "#9B9590"}
            >
              {d}
            </text>
          </g>
        );
      })}
    </svg>
  );
}

function PaceTrendChart({ accent }) {
  // 12 weeks of avg pace per zone
  const w = 600, h = 200;
  const easy = [505, 503, 501, 500, 498, 497, 496, 495, 493, 491, 490, 489];
  const thr = [388, 387, 386, 385, 383, 382, 381, 380, 379, 378, 378, 378];
  const allMin = 370;
  const allMax = 510;
  const xs = easy.map((_, i) => (i / (easy.length - 1)) * (w - 30) + 15);
  const toY = (v) => h - 20 - ((v - allMin) / (allMax - allMin)) * (h - 40);
  return (
    <svg viewBox={`0 0 ${w} ${h}`} className="w-full h-48">
      {/* grid */}
      {[0.25, 0.5, 0.75].map((g) => (
        <line key={g} x1="0" y1={20 + g * (h - 40)} x2={w} y2={20 + g * (h - 40)} stroke="#EFECE8" strokeWidth="1" />
      ))}
      {/* easy */}
      <polyline
        points={xs.map((x, i) => `${x},${toY(easy[i])}`).join(" ")}
        stroke={ZONE.easy}
        strokeWidth="2"
        fill="none"
      />
      {xs.map((x, i) => (
        <circle key={"e" + i} cx={x} cy={toY(easy[i])} r="2.5" fill={ZONE.easy} />
      ))}
      <text x="6" y={toY(505) - 6} fontSize="9" fontFamily="ui-monospace,Menlo,monospace" fill="#9B9590">EASY · 8:25 → 8:09</text>
      {/* threshold */}
      <polyline
        points={xs.map((x, i) => `${x},${toY(thr[i])}`).join(" ")}
        stroke={accent}
        strokeWidth="2"
        fill="none"
      />
      {xs.map((x, i) => (
        <circle key={"t" + i} cx={x} cy={toY(thr[i])} r="2.5" fill={accent} />
      ))}
      <text x="6" y={toY(388) - 6} fontSize="9" fontFamily="ui-monospace,Menlo,monospace" fill={accent}>THRESHOLD · 6:28 → 6:18</text>
    </svg>
  );
}

function RacePredictions({ accent }) {
  const rows = [
    { dist: "5K", time: "16:48", delta: "−18s" },
    { dist: "10K", time: "35:24", delta: "−42s" },
    { dist: "HALF", time: "1:18:12", delta: "−1:32" },
    { dist: "MARATHON", time: "2:48:30", delta: "−4:18" },
  ];
  return (
    <div className="divide-y divide-divider-soft">
      {rows.map((r) => (
        <div key={r.dist} className="py-3 grid grid-cols-[1fr_auto_auto] items-baseline gap-4">
          <Mono color="#9B9590">{r.dist}</Mono>
          <span className="font-mono text-[18px] tabular-nums text-text-primary">{r.time}</span>
          <span className="font-mono text-[11px] tabular-nums" style={{ color: accent }}>
            {r.delta}
          </span>
        </div>
      ))}
    </div>
  );
}

/* ════════════════════════════════════════════════════════════════════
   PLATE 04 · THE PLAN
   ════════════════════════════════════════════════════════════════════ */
function PlatePlan({ plateNo, accent, showMarkers }) {
  return (
    <Plate
      plateNo={plateNo}
      category="THE PLAN · RE-TUNING"
      kicker="A plan, written like a coach would"
      caption="Each day spells out the workout the way a coach would write it — name, distance, pace target, structure. Hairline-divided rows. When you miss a day, the rest of the week recovers."
      accent={accent}
      showMarkers={showMarkers}
    >
      <h2 className="mt-3 font-display text-[60px] leading-[0.98] tracking-[-0.015em] text-text-primary">
        A workout list,{" "}
        <em className="font-display italic" style={{ color: accent.hex }}>
          not a wall of icons.
        </em>
      </h2>

      <div className="mt-14 grid lg:grid-cols-[0.95fr_1.05fr] gap-14 items-start">
        {/* The list */}
        <div className="rounded-lg border border-divider bg-bg-card p-8">
          <div className="border-b border-divider pb-4 flex items-baseline justify-between">
            <div>
              <Mono color="#9B9590">GOAL · MARATHON · SUB-3:10 · 47 DAYS OUT</Mono>
              <h3 className="mt-2 font-display text-[22px] tracking-[-0.01em]">
                Week 09 of 16
              </h3>
            </div>
            <Mono color="#9B9590">47 MI · PLANNED</Mono>
          </div>
          <PlanDay day="MON · APR 27" name="Easy Run" mi="6" pace="6:30 — 7:30 / mi · conversational" note="Whole run easy. Recovery focus." tag="TODAY" accent={accent.hex} highlight />
          <PlanDay day="TUE · APR 28" name="Tempo" mi="8" pace="5:55 / mi · threshold pace" note="2 mi warm-up · 5 mi @ tempo · 1 mi cool-down" tag="AHEAD" />
          <PlanDay day="WED · APR 29" name="Easy Run" mi="3" pace="6:30 — 7:30 / mi" note="Short shake-out between hard days." tag="AHEAD" />
          <PlanDay day="THU · APR 30" name="Progression" mi="8" pace="7:00 → 6:00 / mi · build through" note="2 mi easy · 5 mi progressing · 1 mi cool-down" tag="AHEAD" />
          <PlanDay day="SAT · MAY 02" name="Long Run" mi="20" pace="7:30 / mi · long-run pace" note="4 mi warm-up · 12 mi steady · 4 mi cool-down" tag="MARQUEE" accent={accent.hex} />
        </div>

        {/* commentary */}
        <div>
          <Mono color="#9B9590">WHY THIS PLAN, THIS WEEK</Mono>
          <p className="mt-4 font-body text-[17px] leading-[1.65] text-text-secondary">
            Plans are written as plain text — name, distance, pace, structure —
            because that's how coaches actually write workouts. No icons that
            require a legend, no streak counters, no green checkmarks for the
            sake of it.
          </p>
          <p className="mt-4 font-body text-[17px] leading-[1.65] text-text-secondary">
            Two anchor sessions a week. Easy days fill the rest. When life
            moves the workout, the surrounding days re-tune so the load arc
            stays inside the productive band on Plate 03.
          </p>

          <div className="mt-8 grid grid-cols-3 gap-6 border-t border-divider pt-6">
            <Stat k="Weeks to race" v="07" sub="of 16" />
            <Stat k="Anchor / week" v="02" sub="threshold + long" />
            <Stat k="This week" v="47 mi" sub="planned · 6 days" accent={accent.hex} />
          </div>
        </div>
      </div>
    </Plate>
  );
}

function PlanDay({ day, name, mi, pace, note, tag, accent, highlight }) {
  return (
    <div className="border-b border-divider-soft pt-5 pb-4">
      <div className="flex items-baseline justify-between">
        <Mono color="#9B9590">{day}</Mono>
        <Mono color={accent || "#9B9590"}>{tag}</Mono>
      </div>
      <div className="mt-2 flex items-baseline justify-between">
        <h4
          className="font-display text-[22px] tracking-[-0.01em]"
          style={{ color: highlight ? accent : "#1A1815" }}
        >
          {name}
        </h4>
        <span
          className="font-display text-[22px] tracking-[-0.01em] tabular-nums"
          style={{ color: highlight ? accent : "#1A1815" }}
        >
          {mi} MI
        </span>
      </div>
      <p className="mt-1 font-mono text-[12px] text-text-secondary tabular-nums">{pace}</p>
      <p className="mt-1.5 font-display italic text-[13px] text-text-tertiary">{note}</p>
    </div>
  );
}

/* ════════════════════════════════════════════════════════════════════
   PLATE 05 · A NOTE FROM THE COACH (the quiet AI plate)
   ════════════════════════════════════════════════════════════════════ */
function PlateNotes({ plateNo, accent, showMarkers }) {
  return (
    <Plate
      plateNo={plateNo}
      category="MARGINALIA · COACH"
      kicker="A note in the margin"
      caption="When the log has enough to say something useful, a short note appears in the margin. It cites the runs it read. If there isn't enough data, no note appears."
      accent={accent}
      showMarkers={showMarkers}
    >
      <h2 className="mt-3 font-display text-[60px] leading-[0.98] tracking-[-0.015em] text-text-primary">
        Smart notes,{" "}
        <em className="font-display italic" style={{ color: accent.hex }}>
          quietly.
        </em>
      </h2>
      <p className="mt-6 max-w-[640px] font-body text-[17px] leading-[1.6] text-text-secondary">
        We don't lead with the AI. It's a small layer on top of a serious log
        — a note in the margin when the data has something to say, and silence
        when it doesn't. Ask a follow-up if you want to dig in.
      </p>

      <div className="mt-14 grid lg:grid-cols-[1.2fr_1fr] gap-16 items-center">
        {/* The page with a margin note */}
        <div className="relative rounded-lg border border-divider bg-bg-card p-8">
          <Mono color="#9B9590">LOG · TUE MAY 12</Mono>
          <h3 className="mt-2 font-display text-[26px] tracking-[-0.01em]">
            Progression run · 10 mi
          </h3>
          <p className="mt-2 font-mono text-[12px] text-text-secondary tabular-nums">
            7:42 avg · last 2 @ 7:15 · mood ↑ · 62°
          </p>
          <div className="mt-6 grid grid-cols-2 gap-x-8 gap-y-3 border-t border-divider pt-5">
            <LogRowSm k="Mile 1" v="7:48" />
            <LogRowSm k="Mile 6" v="7:38" />
            <LogRowSm k="Mile 2" v="7:45" />
            <LogRowSm k="Mile 7" v="7:40" />
            <LogRowSm k="Mile 3" v="7:44" />
            <LogRowSm k="Mile 8" v="7:38" />
            <LogRowSm k="Mile 4" v="7:42" />
            <LogRowSm k="Mile 9" v="7:18" accent={accent.hex} />
            <LogRowSm k="Mile 5" v="7:41" />
            <LogRowSm k="Mile 10" v="7:12" accent={accent.hex} />
          </div>

          {/* margin note inside the card, set off */}
          <div
            className="mt-8 border-l-2 pl-5"
            style={{ borderColor: accent.hex }}
          >
            <Mono color={accent.hex}>NOTE FROM THE COACH</Mono>
            <p className="mt-2 font-display italic text-[17px] leading-[1.55] text-text-secondary">
              Finishing 27 seconds under your average is right in the
              marathon-pace window. Tuesday's threshold and today's long are
              the two quality sessions; sit on 8:00+ for the rest of the week.
            </p>
            <Mono color="#9B9590" className="block mt-3">
              Based on: log entries Apr 27 – May 12 · plan week 09
            </Mono>
          </div>
        </div>

        {/* What it does and doesn't */}
        <div>
          <Mono color="#9B9590">DOES</Mono>
          <ul className="mt-3 divide-y divide-divider-soft">
            <DoesRow>Read your recent training and write back in plain language.</DoesRow>
            <DoesRow>Cite the entries each note is based on.</DoesRow>
            <DoesRow>Answer follow-up questions in conversation.</DoesRow>
            <DoesRow>Say nothing when there isn't enough data yet.</DoesRow>
          </ul>

          <Mono color="#9B9590" className="block mt-8">DOESN&apos;T</Mono>
          <ul className="mt-3 divide-y divide-divider-soft">
            <DoesRow muted>Pretend to be your real coach.</DoesRow>
            <DoesRow muted>Push you through pain.</DoesRow>
            <DoesRow muted>Comment on your diet, weight, or life choices.</DoesRow>
          </ul>
        </div>
      </div>
    </Plate>
  );
}

function LogRowSm({ k, v, accent }) {
  return (
    <div className="flex items-baseline justify-between">
      <Mono color="#9B9590">{k}</Mono>
      <span className="font-mono text-[13px] tabular-nums" style={{ color: accent || "#1A1815" }}>
        {v}
      </span>
    </div>
  );
}

function DoesRow({ children, muted }) {
  return (
    <li className="py-2.5 font-body text-[14.5px] leading-[1.55]" style={{ color: muted ? "#9B9590" : "#3a3733" }}>
      {muted && <span className="mr-2 text-text-tertiary">—</span>}
      {children}
    </li>
  );
}

/* ════════════════════════════════════════════════════════════════════
   PLATE 06 · NOT FOR EVERYONE
   ════════════════════════════════════════════════════════════════════ */
function PlateAudience({ plateNo, accent, showMarkers }) {
  return (
    <Plate
      plateNo={plateNo}
      category="AUDIENCE · HONEST SIGNPOSTING"
      kicker="Not for everyone"
      caption="The app rewards a base. If you're new to running, you'll have a better experience with something simpler first. We'll happily name a few."
      accent={accent}
      showMarkers={showMarkers}
    >
      <div className="mt-6 grid lg:grid-cols-[1fr_1fr] gap-16 items-start">
        <h2 className="font-display text-[52px] leading-[1.02] tracking-[-0.015em] text-text-primary">
          If you're chasing a time,{" "}
          <em className="font-display italic" style={{ color: accent.hex }}>
            this is yours.
          </em>
        </h2>
        <div>
          <p className="font-body text-[17px] leading-[1.65] text-text-secondary">
            Post Run Drip is built for runners with a goal race, a base of
            consistent miles, and a genuine interest in their own splits.
            Marathon block, second-half-marathon, returning-from-injury — yes.
          </p>
          <p className="mt-4 font-body text-[17px] leading-[1.65] text-text-secondary">
            Couch-to-5K, first-time-runner — not yet. The analytics surface
            wants twelve weeks of data to be at its best; we'd rather you build
            that base first and come back than have a frustrating beta.
          </p>
        </div>
      </div>
    </Plate>
  );
}

/* ════════════════════════════════════════════════════════════════════
   PLATE 07 · BETA
   ════════════════════════════════════════════════════════════════════ */
function PlateBeta({ plateNo, accent, showMarkers }) {
  return (
    <section id="start" className="border-b border-divider bg-bg-elevated">
      <div className="mx-auto max-w-[1200px] px-10 pt-10 pb-16">
        {showMarkers && (
          <div className="border-b border-divider pb-3 mb-10 grid grid-cols-2 items-baseline">
            <div>
              <Mono color="#9B9590" className="block">{ISSUE.pub}</Mono>
              <Mono color="#9B9590" className="block">— BETA · INVITATION</Mono>
            </div>
            <div className="text-right">
              <Mono color="#9B9590" className="block">
                FIG. {String(plateNo).padStart(2, "0")}
              </Mono>
              <Mono color="#9B9590" className="block">
                {ISSUE.vol} · {ISSUE.date}
              </Mono>
            </div>
          </div>
        )}

        <div className="text-center max-w-[820px] mx-auto py-14">
          <Kicker color={accent.hex}>The beta · invitation</Kicker>
          <h2 className="mt-6 font-display text-[68px] leading-[0.98] tracking-[-0.015em] text-text-primary">
            Try it for a week.
            <br />
            <em className="font-display italic" style={{ color: accent.hex }}>
              Tell us what doesn't work.
            </em>
          </h2>
          <p className="mt-8 font-body text-[17px] leading-[1.6] text-text-secondary max-w-[560px] mx-auto">
            We're sending TestFlight invites in small batches. Leave your
            email, mention what you're training for, and we'll send a link.
          </p>
          <div className="mt-10 flex flex-wrap items-center justify-center gap-3">
            <a
              href="#"
              className="rounded-md px-7 py-4 font-body text-[15px] font-semibold text-white"
              style={{
                backgroundColor: accent.hex,
                boxShadow: `0 1px 0 ${accent.deep}, 0 12px 32px -12px ${accent.soft}`,
              }}
            >
              Request a TestFlight invite
            </a>
            <a
              href="#"
              className="rounded-md border border-divider px-7 py-4 font-body text-[15px] font-medium text-text-secondary hover:border-text-tertiary"
            >
              Read the changelog
            </a>
          </div>
        </div>

        {showMarkers && (
          <div className="border-t border-divider pt-5 grid md:grid-cols-[1fr_auto] gap-6 items-baseline">
            <p className="font-display italic text-[15px] leading-[1.5] text-text-secondary max-w-[640px]">
              iOS only for now. Built in Austin. By runners.
            </p>
            <Mono color="#9B9590" className="text-right md:text-left">
              PLATE 07 / 07 · — restraint as foundation, intensity as accent
            </Mono>
          </div>
        )}
      </div>
    </section>
  );
}

/* ════════════════════════════════════════════════════════════════════
   PHONE FRAME + LOG SCREEN (for the cover plate)
   ════════════════════════════════════════════════════════════════════ */
function PhoneFrame({ children }) {
  return (
    <div className="relative w-[320px] shrink-0">
      <div className="rounded-[44px] bg-[#1A1815] p-[10px] shadow-[0_30px_60px_-20px_rgba(26,24,21,0.35)]">
        <div className="absolute left-1/2 top-[18px] z-10 h-[28px] w-[110px] -translate-x-1/2 rounded-full bg-[#1A1815]" />
        <div className="overflow-hidden rounded-[34px] bg-bg-base h-[620px]">
          {children}
        </div>
      </div>
    </div>
  );
}

function LogScreen({ accent }) {
  return (
    <div className="px-5 pt-14 pb-4 h-full flex flex-col">
      <div className="flex items-baseline justify-between border-b border-divider pb-2">
        <Mono color="#9B9590">RUNNING LOG · TUE</Mono>
        <Mono color="#9B9590">MAY 12</Mono>
      </div>
      <h3 className="mt-4 font-display text-[26px] leading-tight">
        Progression run
      </h3>
      <p className="mt-1 font-mono text-[11px] text-text-secondary tabular-nums">
        10.0 mi · 7:42 avg · 1:17:24
      </p>

      <div className="mt-4 grid grid-cols-2 gap-x-4 gap-y-2 border-t border-divider pt-3">
        {[
          ["Mile 1", "7:48"], ["Mile 6", "7:38"],
          ["Mile 2", "7:45"], ["Mile 7", "7:40"],
          ["Mile 3", "7:44"], ["Mile 8", "7:38"],
          ["Mile 4", "7:42"], ["Mile 9", "7:18", true],
          ["Mile 5", "7:41"], ["Mile 10", "7:12", true],
        ].map(([k, v, h], i) => (
          <div key={i} className="flex items-baseline justify-between">
            <Mono color="#9B9590">{k}</Mono>
            <span className="font-mono text-[12px] tabular-nums" style={{ color: h ? accent.hex : "#1A1815" }}>
              {v}
            </span>
          </div>
        ))}
      </div>

      {/* mini pace chart */}
      <div className="mt-4">
        <Mono color="#9B9590">SPLITS</Mono>
        <svg viewBox="0 0 240 60" className="mt-2 w-full h-16">
          {[7.8, 7.75, 7.733, 7.7, 7.683, 7.633, 7.667, 7.633, 7.3, 7.2].map((v, i) => {
            const x = 6 + i * 26;
            const y = ((v - 7.1) / 0.8) * 50 + 4;
            const next = i < 9 ? [7.8, 7.75, 7.733, 7.7, 7.683, 7.633, 7.667, 7.633, 7.3, 7.2][i + 1] : null;
            return (
              <g key={i}>
                {next !== null && (
                  <line
                    x1={x}
                    y1={y}
                    x2={x + 26}
                    y2={((next - 7.1) / 0.8) * 50 + 4}
                    stroke={i >= 7 ? accent.hex : "#6B8068"}
                    strokeWidth="1.5"
                  />
                )}
                <circle cx={x} cy={y} r="2" fill={i >= 8 ? accent.hex : "#6B8068"} />
              </g>
            );
          })}
        </svg>
      </div>

      {/* margin note */}
      <div
        className="mt-auto pt-4 border-l-2 pl-3"
        style={{ borderColor: accent.hex }}
      >
        <Mono color={accent.hex}>NOTE</Mono>
        <p className="mt-1.5 font-display italic text-[12.5px] leading-[1.45] text-text-secondary">
          Finishing 27 sec under average — right in the marathon-pace window.
          Sit on easy for the rest of the week.
        </p>
      </div>

      <div className="mt-3 flex items-center justify-around border-t border-divider pt-3">
        {["LOG", "TRAIN", "TRENDS", "COACH", "RUNS"].map((t, i) => (
          <Mono key={t} color={i === 0 ? "#1A1815" : "#9B9590"}>
            {t}
          </Mono>
        ))}
      </div>
    </div>
  );
}

/* ════════════════════════════════════════════════════════════════════
   FOOTER
   ════════════════════════════════════════════════════════════════════ */
function Footer() {
  return (
    <footer className="bg-bg-base">
      <div className="mx-auto max-w-[1200px] px-10 py-14 grid md:grid-cols-[2fr_1fr_1fr] gap-12">
        <div>
          <div className="font-display text-[22px] tracking-[-0.01em]">
            Post Run Drip
          </div>
          <p className="mt-3 font-body text-[14px] leading-[1.6] text-text-secondary max-w-[340px]">
            A training log and analytics surface for runners chasing a time.
            iOS, in beta.
          </p>
        </div>
        <FooterCol title="The Journal" links={["The log", "Trends", "The plan", "Marginalia"]} />
        <FooterCol title="Reach us" links={["hi@postrundrip.com", "Strava club", "Instagram"]} />
      </div>
      <div className="border-t border-divider">
        <div className="mx-auto max-w-[1200px] flex flex-wrap items-center justify-between px-10 py-6 gap-4">
          <Mono color="#9B9590">
            © {new Date().getFullYear()} POST RUN DRIP · AUSTIN, TX
          </Mono>
          <Mono color="#9B9590">
            — restraint as foundation, intensity as accent
          </Mono>
        </div>
      </div>
    </footer>
  );
}

function FooterCol({ title, links }) {
  return (
    <div>
      <Mono color="#9B9590">{title}</Mono>
      <ul className="mt-3 space-y-2">
        {links.map((l) => (
          <li key={l}>
            <a href="#" className="font-body text-[14px] text-text-tertiary hover:text-text-primary">
              {l}
            </a>
          </li>
        ))}
      </ul>
    </div>
  );
}

/* ── mount ─────────────────────────────────────────────────────────── */
const root = ReactDOM.createRoot(document.getElementById("root"));
root.render(<App />);

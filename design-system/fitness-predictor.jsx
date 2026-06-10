/* global React */
/* ════════════════════════════════════════════════════════════════════
   POST RUN DRIP — FITNESS PREDICTOR (v1 · forward read)
   The mirror of Training Analysis: where the engine is, what it will
   spit out across distances, what to do with that information.
   ════════════════════════════════════════════════════════════════════ */

const { useState, useMemo } = React;
const ACCENT = "#D4592A";
const ACCENT_SOFT = "rgba(212,89,42,0.08)";
const SAGE = "#6B8068";
const PLUM = "#6B4A8A";
const INK = "#1A1815";
const INK2 = "#6B6560";
const INK3 = "#9B9590";

/* ── Tweaks defaults ────────────────────────────────────────────── */
const TWEAK_DEFAULTS = /*EDITMODE-BEGIN*/{
  "model": "blend",
  "confidence": "honest",
  "focus": "marathon",
  "showScenarios": true,
  "showAdjustments": true
}/*EDITMODE-END*/;

/* ── Mono inline label ──────────────────────────────────────────── */
const Mono = ({ children, color = INK3, className = "", weight, size }) => (
  <span
    className={`font-mono uppercase ${className}`}
    style={{
      color,
      fontWeight: weight,
      fontSize: size || "10.5px",
      letterSpacing: "1.5px",
    }}
  >
    {children}
  </span>
);

/* ════════════════════════════════════════════════════════════════════
   DATA — internally consistent w/ Training Analysis fixture.
   Wk 9 of 16 of a Boston build. Last HM tune-up 1:27:08 on May 2.
   ════════════════════════════════════════════════════════════════════ */

/* All times in seconds for math; we format on render. */
const s = (m, sec = 0) => m * 60 + sec;
const fmtSec = (t) => {
  const sign = t < 0 ? "-" : "";
  const a = Math.abs(Math.round(t));
  const h = Math.floor(a / 3600);
  const m = Math.floor((a % 3600) / 60);
  const sc = a % 60;
  if (h > 0) return `${sign}${h}:${String(m).padStart(2, "0")}:${String(sc).padStart(2, "0")}`;
  return `${sign}${m}:${String(sc).padStart(2, "0")}`;
};
const fmtDelta = (t) => {
  if (Math.abs(t) < 1) return "—";
  const sign = t < 0 ? "−" : "+";
  return `${sign}${fmtSec(Math.abs(t))}`;
};

/* Distances — central spine of the page */
const DISTANCES = [
  {
    id: "mile", label: "1 mile",     km: 1.609, kind: "Speed", color: PLUM,
    pred: s(5, 44), low: s(5, 36), high: s(5, 54),
    pr:   s(5, 38), prDate: "Jun ’24",
    pace: s(5, 44), notes: "Track or downhill mile. Honest effort.",
  },
  {
    id: "5k",  label: "5 km",        km: 5,     kind: "Speed", color: PLUM,
    pred: s(19, 12), low: s(18, 52), high: s(19, 36),
    pr:   s(19, 24), prDate: "Oct ’24",
    pace: s(6, 11),  notes: "Off this fitness, today, with two days easy.",
  },
  {
    id: "10k", label: "10 km",       km: 10,    kind: "Tempo", color: ACCENT,
    pred: s(39, 48), low: s(39, 12), high: s(40, 30),
    pr:   s(40, 18), prDate: "Mar ’25",
    pace: s(6, 24),  notes: "The distance the engine reads cleanest at.",
  },
  {
    id: "hm",  label: "Half marathon", km: 21.0975, kind: "Threshold", color: ACCENT,
    pred: s(87, 32),  low: s(86, 0),  high: s(89, 30),
    pr:   s(87, 8),   prDate: "May ’26",
    pace: s(6, 41),   notes: "Slower than May 2 tune-up; legs not fresh.",
    recent: true,
  },
  {
    id: "mar", label: "Marathon",    km: 42.195, kind: "Goal", color: ACCENT,
    pred: s(188, 42), low: s(184, 0),  high: s(194, 0),
    pr:   s(194, 46), prDate: "Boston ’25",
    pace: s(7, 12),   notes: "The model is bullish. The race isn’t.",
    flag: true,
  },
];

/* Trajectory — predicted marathon over the 9 weeks of block */
const TRAJ = [
  { wk: 1, label: "Mar 16", pred: s(205, 0), hi: s(210, 0), lo: s(201, 0) },
  { wk: 2, label: "Mar 23", pred: s(202, 30), hi: s(207, 30), lo: s(199, 30) },
  { wk: 3, label: "Mar 30", pred: s(199, 12), hi: s(204, 0), lo: s(196, 24) },
  { wk: 4, label: "Apr 6",  pred: s(198, 18), hi: s(203, 0), lo: s(195, 24) },
  { wk: 5, label: "Apr 13", pred: s(196, 12), hi: s(200, 30), lo: s(193, 30) },
  { wk: 6, label: "Apr 20", pred: s(195, 0),  hi: s(199, 30), lo: s(192, 0) },
  { wk: 7, label: "Apr 27", pred: s(193, 30), hi: s(198, 0),  lo: s(190, 30) },
  { wk: 8, label: "May 4",  pred: s(191, 0),  hi: s(195, 30), lo: s(187, 30) },
  { wk: 9, label: "May 11", pred: s(188, 42), hi: s(194, 0),  lo: s(184, 0), current: true },
];

/* VDOT-ish points alongside the trajectory */
const VDOT_NOW = 56.8;
const VDOT_BLOCK_START = 53.4;

/* Goal race plan — Boston Jul 12 */
const GOAL_RACE = {
  name: "Boston",
  date: "Jul 12 · 7 wk out",
  distance: 26.2,
  goal: s(195, 0),         // 3:15:00
  stretchGoal: s(190, 0),  // 3:10:00
  modelPred: s(188, 42),   // 3:08:42 from above
  paceBuckets: [
    { range: "Mi 1–5",   pace: s(7, 24), note: "Hold back. Course drops; don’t cash it.", color: SAGE },
    { range: "Mi 6–16",  pace: s(7, 18), note: "Goal-pace rhythm. The race is here.", color: INK },
    { range: "Mi 17–21", pace: s(7, 20), note: "Newton hills. Effort, not pace.", color: ACCENT },
    { range: "Mi 22–26", pace: s(7, 12), note: "Drop is earned. Use it if it’s there.", color: ACCENT },
  ],
};

/* What-if scenarios — toggleable */
const SCENARIOS = [
  {
    id: "perfect",
    label: "Perfect taper",
    deltaSec: -120,
    note: "Cut 2 min · model upside if the next four weeks land",
    accent: true,
  },
  {
    id: "stale",
    label: "Carry fatigue in",
    deltaSec: +180,
    note: "Add 3 min · if you arrive with the build still in legs",
  },
  {
    id: "hot",
    label: "Race-day 75°F",
    deltaSec: +240,
    note: "Add ~4 min · marathon penalty per Daniels heat table",
  },
  {
    id: "course",
    label: "Net-downhill course",
    deltaSec: -90,
    note: "Cut 1:30 · Boston’s drop, before Newton claws it back",
  },
];

/* Course / conditions adjustments */
const ADJUSTMENTS = [
  { id: "temp", label: "Temperature", from: "55°F", to: "75°F", delta: s(0, 4) * 60, kind: "slows" },
  { id: "wind", label: "Wind",        from: "Calm", to: "10 mph headwind", delta: s(0, 1) * 60 + 30, kind: "slows" },
  { id: "elev", label: "Net elevation", from: "Flat", to: "Boston (−440 ft)", delta: -90, kind: "helps" },
  { id: "surf", label: "Surface",     from: "Road",  to: "Trail", delta: s(0, 4) * 60, kind: "slows" },
];

/* ════════════════════════════════════════════════════════════════════
   APP
   ════════════════════════════════════════════════════════════════════ */
function App() {
  const [tweaks, setTweak] = useTweaks(TWEAK_DEFAULTS);

  // Confidence widens or tightens the bands
  const bandScale =
    tweaks.confidence === "tight" ? 0.55 :
    tweaks.confidence === "loose" ? 1.6 : 1.0;

  return (
    <div className="min-h-screen bg-bg-base text-text-primary font-body">
      <div className="flex h-screen overflow-hidden">
        <Sidebar />
        <div className="flex flex-1 flex-col overflow-hidden">
          <TopNav />
          <main className="flex-1 overflow-y-auto">
            <PredictorPage tweaks={tweaks} setTweak={setTweak} bandScale={bandScale} />
          </main>
        </div>
      </div>

      <TweaksPanel>
        <TweakSection label="Model" />
        <TweakSelect
          label="Equivalent-time model"
          value={tweaks.model}
          options={[
            { value: "vdot",   label: "VDOT · Daniels" },
            { value: "riegel", label: "Riegel · power-law" },
            { value: "blend",  label: "Blend · both, weighted" },
          ]}
          onChange={(v) => setTweak("model", v)}
        />
        <TweakRadio
          label="Confidence band"
          value={tweaks.confidence}
          options={["tight", "honest", "loose"]}
          onChange={(v) => setTweak("confidence", v)}
        />
        <TweakSection label="Focus" />
        <TweakSelect
          label="Headline distance"
          value={tweaks.focus}
          options={[
            { value: "5k",       label: "5 km" },
            { value: "10k",      label: "10 km" },
            { value: "hm",       label: "Half marathon" },
            { value: "marathon", label: "Marathon · Boston" },
          ]}
          onChange={(v) => setTweak("focus", v)}
        />
        <TweakSection label="Modules" />
        <TweakToggle
          label="What-if scenarios"
          value={tweaks.showScenarios}
          onChange={(v) => setTweak("showScenarios", v)}
        />
        <TweakToggle
          label="Course adjustments"
          value={tweaks.showAdjustments}
          onChange={(v) => setTweak("showAdjustments", v)}
        />
      </TweaksPanel>
    </div>
  );
}

/* ── SIDEBAR ────────────────────────────────────────────────────── */
function Sidebar() {
  const items = [
    { label: "Dashboard",    on: false, href: "Training Summary.html" },
    { label: "Training log", on: false, href: "Training Log.html" },
    { label: "Coach",        on: false, href: "#" },
    { label: "Plan",         on: false, href: "Plan Page.html" },
  ];
  const more = [
    { label: "Coach portal",      on: false, href: "#" },
    { label: "Goals",             on: false, href: "#" },
    { label: "Analysis",          on: false, href: "Training Analysis.html" },
    { label: "Injuries",          on: false, href: "#" },
    { label: "Fitness predictor", on: true,  href: "Fitness Predictor.html" },
    { label: "Pace chart",        on: false, href: "#" },
    { label: "Content library",   on: false, href: "#" },
  ];
  return (
    <aside className="hidden sm:flex flex-col w-[224px] shrink-0 bg-bg-base border-r border-divider">
      <div className="px-5 py-5 border-b border-divider">
        <span className="font-display text-[18px] tracking-[-0.01em]">Post Run Drip</span>
      </div>
      <nav className="flex-1 overflow-y-auto px-3 py-4">
        <Mono className="px-2">PRIMARY</Mono>
        <ul className="mt-2 space-y-0.5">
          {items.map((it) => (
            <li key={it.label}>
              <a
                href={it.href}
                className={`block px-3 py-1.5 rounded-md text-[13px] ${
                  it.on
                    ? "bg-coral/10 text-coral font-semibold"
                    : "text-text-secondary hover:text-text-primary hover:bg-bg-elevated"
                }`}
              >
                {it.label}
              </a>
            </li>
          ))}
        </ul>
        <div className="mt-6">
          <Mono className="px-2">MORE</Mono>
          <ul className="mt-2 space-y-0.5">
            {more.map((it) => (
              <li key={it.label}>
                <a
                  href={it.href}
                  className={`block px-3 py-1.5 rounded-md text-[13px] ${
                    it.on
                      ? "bg-coral/10 text-coral font-semibold"
                      : "text-text-secondary hover:text-text-primary hover:bg-bg-elevated"
                  }`}
                >
                  {it.label}
                </a>
              </li>
            ))}
          </ul>
        </div>
      </nav>
      <div className="border-t border-divider px-4 py-3 flex items-center gap-2.5">
        <span className="h-8 w-8 rounded-full bg-coral/15 flex items-center justify-center font-display text-[15px] text-coral">M</span>
        <div className="leading-tight">
          <p className="text-[12.5px] text-text-primary">M. Kerr</p>
          <p className="font-mono text-[9.5px] tracking-[1.2px] text-text-tertiary uppercase">Athlete</p>
        </div>
      </div>
    </aside>
  );
}

function TopNav() {
  return (
    <header className="bg-bg-base border-b border-divider px-8 py-3 flex items-center justify-between">
      <Mono>RUNNING LOG · FITNESS PREDICTOR</Mono>
      <div className="flex items-center gap-5">
        <a href="#" className="text-[13px] text-text-secondary hover:text-text-primary">Voice log</a>
        <a href="#" className="text-[13px] text-text-secondary hover:text-text-primary">Ask coach</a>
        <span className="font-mono text-[10px] tracking-[1.3px] uppercase text-text-tertiary">
          Thu · May 14
        </span>
      </div>
    </header>
  );
}

/* ════════════════════════════════════════════════════════════════════
   PAGE
   ════════════════════════════════════════════════════════════════════ */
function PredictorPage({ tweaks, setTweak, bandScale }) {
  return (
    <div className="mx-auto max-w-[1080px] px-10 py-10 space-y-12">
      <PlateHeader />
      <Lede />
      <AsOfStrip tweaks={tweaks} setTweak={setTweak} />
      <PredictionStack tweaks={tweaks} bandScale={bandScale} />
      <FigTrajectory />
      <FigGoalRace />
      {tweaks.showScenarios ? <FigScenarios /> : null}
      {tweaks.showAdjustments ? <FigAdjustments /> : null}
      <CoachRead />
      <Footer />
    </div>
  );
}

/* ── plate header ───────────────────────────────────────────────── */
function PlateHeader() {
  return (
    <div className="flex items-baseline justify-between border-b border-divider-soft pb-3">
      <Mono>RUNNING LOG · FITNESS PREDICTOR · v1 FORWARD READ</Mono>
      <Mono>WK 9 OF 16 · BOSTON · JUL 12</Mono>
    </div>
  );
}

/* ── lede ───────────────────────────────────────────────────────── */
function Lede() {
  return (
    <section>
      <Mono color={ACCENT}>WHAT YOU CAN RUN · TODAY</Mono>
      <h1 className="mt-3 font-display text-[68px] leading-[0.96] tracking-[-0.02em] max-w-[760px]">
        The engine, in five distances.
      </h1>
      <p className="mt-4 max-w-[600px] font-body text-[17px] leading-[1.6] text-text-secondary">
        A read of the fitness you have, off this block, today.
        The model is honest about what it sees and honest about what it
        doesn&rsquo;t — bands are wide where the data is thin.
      </p>
    </section>
  );
}

/* ── as-of strip ───────────────────────────────────────────────── */
function AsOfStrip({ tweaks, setTweak }) {
  const cells = [
    {
      label: "VDOT",
      value: VDOT_NOW.toFixed(1),
      sub: `↑ ${(VDOT_NOW - VDOT_BLOCK_START).toFixed(1)} SINCE WK 1`,
      accent: true,
    },
    {
      label: "ANCHOR",
      value: "1:27:08",
      sub: "HM · MAY 2 · TUNE-UP",
    },
    {
      label: "MODEL",
      value: tweaks.model === "vdot" ? "VDOT" : tweaks.model === "riegel" ? "Riegel" : "Blend",
      sub: tweaks.model === "blend" ? "60% VDOT · 40% RIEGEL" : tweaks.model === "vdot" ? "Daniels tables" : "t₂ = t₁(d₂/d₁)¹·⁰⁶",
    },
    {
      label: "DATA",
      value: "94%",
      sub: "8 OF 9 WK · OK",
    },
  ];
  return (
    <section className="grid grid-cols-2 md:grid-cols-4 gap-0 border-y border-divider divide-x divide-divider">
      {cells.map((c) => (
        <div key={c.label} className="px-5 py-5">
          <Mono color={c.accent ? ACCENT : INK3}>{c.label}</Mono>
          <p className="mt-1 font-display text-[26px] tabular-nums tracking-[-0.01em] leading-none"
            style={{ color: c.accent ? ACCENT : INK }}>
            {c.value}
          </p>
          <p className="mt-2 font-mono text-[9.5px] tracking-[1.3px] uppercase text-text-tertiary">
            {c.sub}
          </p>
        </div>
      ))}
    </section>
  );
}

/* ════════════════════════════════════════════════════════════════════
   PREDICTION STACK — the spine of the page
   ════════════════════════════════════════════════════════════════════ */
function PredictionStack({ tweaks, bandScale }) {
  return (
    <section>
      <FigHeader id="A" title="Predicted times · across the ladder" right={`MODEL · ${tweaks.model.toUpperCase()} · ${tweaks.confidence.toUpperCase()} BAND`} />
      <div className="mt-5 border border-divider rounded-lg bg-bg-card overflow-hidden fig-card">
        {/* Column headers */}
        <div className="grid grid-cols-[120px_124px_1fr_104px_104px] items-baseline gap-x-4 px-6 pt-5 pb-3 border-b border-divider-soft bg-bg-elevated/40">
          <Mono>DISTANCE</Mono>
          <Mono>PREDICTION</Mono>
          <Mono className="text-center block">CONFIDENCE BAND · vs PR (◆)</Mono>
          <Mono className="text-right block">GOAL PACE</Mono>
          <Mono className="text-right block">vs PR</Mono>
        </div>

        {DISTANCES.map((d) => (
          <PredRow key={d.id} d={d} bandScale={bandScale} focus={tweaks.focus} />
        ))}
      </div>

      <p className="mt-3 font-body italic text-[12.5px] text-text-tertiary">
        ◆ personal best · band shows where the model thinks the time lives 80% of the time, on a race-day equivalent of today&rsquo;s fitness.
      </p>
    </section>
  );
}

function PredRow({ d, bandScale, focus }) {
  const focusMap = { "5k": "5k", "10k": "10k", "hm": "hm", "marathon": "mar" };
  const isFocus = focusMap[focus] === d.id;

  // Per-row visual scaling — each row centers on its own prediction.
  const displayLow  = d.pred - (d.pred - d.low) * bandScale;
  const displayHigh = d.pred + (d.high - d.pred) * bandScale;
  const halfRange = Math.max(
    d.pred - displayLow,
    displayHigh - d.pred,
    Math.abs(d.pr - d.pred),
    1
  ) * 1.18;

  const center = 50;
  const toPct = (sec) => center + ((sec - d.pred) / halfRange) * 46;
  const lowPct = toPct(displayLow);
  const highPct = toPct(displayHigh);
  const prPct = toPct(d.pr);

  const deltaVsPR = d.pred - d.pr; // negative = faster than PR

  return (
    <div
      className="pred-row grid grid-cols-[120px_124px_1fr_104px_104px] items-center gap-x-4 px-6 py-5 transition-colors"
      style={{ background: isFocus ? "rgba(212,89,42,0.025)" : "transparent" }}
    >
      {/* Distance */}
      <div>
        <p className="font-display text-[20px] tracking-[-0.005em] leading-tight">
          {d.label}
        </p>
        <p className="font-mono text-[9.5px] tracking-[1.3px] uppercase mt-0.5" style={{ color: d.color }}>
          {d.kind}{d.recent ? " · PR · MAY 2" : d.flag ? " · GOAL RACE" : ""}
        </p>
      </div>

      {/* Prediction */}
      <div>
        <p className="font-mono text-[20px] tabular-nums leading-none"
          style={{ color: isFocus ? ACCENT : INK, fontWeight: 600 }}>
          {fmtSec(d.pred)}
        </p>
        <p className="font-mono text-[9.5px] tracking-[1.3px] uppercase text-text-tertiary mt-1">
          ± {fmtSec((displayHigh - displayLow) / 2)}
        </p>
      </div>

      {/* Band */}
      <div className="relative h-[56px]">
        {/* center axis */}
        <div className="absolute top-1/2 left-0 right-0 h-px bg-divider-soft" />

        {/* band */}
        <div
          className="absolute top-1/2 -translate-y-1/2 h-[10px] rounded-[1px]"
          style={{
            left: `${lowPct}%`,
            width: `${Math.max(0.5, highPct - lowPct)}%`,
            background: isFocus ? ACCENT : INK,
            opacity: isFocus ? 0.20 : 0.13,
          }}
        />

        {/* low/high caps */}
        <div className="absolute top-1/2 -translate-y-1/2 w-px h-[14px]"
          style={{ left: `${lowPct}%`, background: INK3 }} />
        <div className="absolute top-1/2 -translate-y-1/2 w-px h-[14px]"
          style={{ left: `${highPct}%`, background: INK3 }} />

        {/* low/high time labels — under the caps */}
        <p className="absolute font-mono text-[8.5px] tabular-nums tracking-[1.1px] uppercase text-text-tertiary"
          style={{ left: `${lowPct}%`, transform: "translateX(-50%)", top: "calc(50% + 11px)" }}>
          {fmtSec(displayLow)}
        </p>
        <p className="absolute font-mono text-[8.5px] tabular-nums tracking-[1.1px] uppercase text-text-tertiary"
          style={{ left: `${highPct}%`, transform: "translateX(-50%)", top: "calc(50% + 11px)" }}>
          {fmtSec(displayHigh)}
        </p>

        {/* prediction tick */}
        <div className="absolute top-1/2 -translate-y-1/2 w-[2px] h-[26px] rounded-[1px]"
          style={{ left: `${center}%`, transform: "translate(-50%, -50%)", background: isFocus ? ACCENT : INK }} />

        {/* PR diamond */}
        <div className="absolute top-1/2"
          style={{
            left: `${prPct}%`,
            width: 10,
            height: 10,
            transform: "translate(-50%, -50%) rotate(45deg)",
            background: "#F5F3F0",
            border: `1.5px solid ${INK2}`,
          }} />
      </div>

      {/* Goal pace */}
      <div className="text-right">
        <p className="font-mono text-[13px] tabular-nums text-text-primary">
          {fmtSec(d.pace)}
          <span className="ml-1 text-[9.5px] tracking-[1.3px] uppercase text-text-tertiary">/ mi</span>
        </p>
      </div>

      {/* Delta vs PR */}
      <div className="text-right">
        <p className="font-mono text-[13px] tabular-nums"
          style={{ color: deltaVsPR < 0 ? "#2D8A4E" : deltaVsPR > 0 ? "#C45A3A" : INK3, fontWeight: 600 }}>
          {fmtDelta(deltaVsPR)}
        </p>
        <p className="font-mono text-[9px] tracking-[1.3px] uppercase text-text-tertiary mt-0.5">
          PR · {d.prDate}
        </p>
      </div>
    </div>
  );
}

/* ════════════════════════════════════════════════════════════════════
   FIG. B — Fitness trajectory (predicted marathon over the block)
   ════════════════════════════════════════════════════════════════════ */
function FigTrajectory() {
  return (
    <section>
      <FigHeader id="B" title="Trajectory · predicted marathon, by week" right="9 WEEKS · ±80% BAND" />
      <div className="mt-5 border border-divider rounded-lg bg-bg-card p-6 fig-card">
        <TrajectoryChart />
        <div className="mt-5 pt-4 border-t border-divider-soft grid grid-cols-3 gap-x-4">
          <div>
            <Mono>BLOCK START</Mono>
            <p className="mt-1 font-display text-[26px] tabular-nums tracking-[-0.01em]">{fmtSec(TRAJ[0].pred)}</p>
            <p className="font-mono text-[9.5px] tracking-[1.3px] uppercase text-text-tertiary">WK 1 · MAR 16</p>
          </div>
          <div>
            <Mono color={ACCENT}>TODAY</Mono>
            <p className="mt-1 font-display text-[26px] tabular-nums tracking-[-0.01em]" style={{ color: ACCENT }}>
              {fmtSec(TRAJ[TRAJ.length - 1].pred)}
            </p>
            <p className="font-mono text-[9.5px] tracking-[1.3px] uppercase text-text-tertiary">↓ {fmtSec(TRAJ[0].pred - TRAJ[TRAJ.length - 1].pred)} OVER 9 WK</p>
          </div>
          <div>
            <Mono>SLOPE</Mono>
            <p className="mt-1 font-display text-[26px] tabular-nums tracking-[-0.01em]">−1:48</p>
            <p className="font-mono text-[9.5px] tracking-[1.3px] uppercase text-text-tertiary">PER WEEK · ROLLING AVG</p>
          </div>
        </div>
        <p className="mt-5 font-body italic text-[13px] text-text-secondary">
          Curve has flattened the past two weeks &mdash; typical pre-taper plateau.
          The next gain is in the rest, not the work.
        </p>
      </div>
    </section>
  );
}

function TrajectoryChart() {
  const W = 960, H = 280;
  const padL = 56, padR = 24, padT = 24, padB = 44;
  const innerW = W - padL - padR;
  const innerH = H - padT - padB;

  const yMin = s(180, 0);   // 3:00
  const yMax = s(215, 0);   // 3:35

  const yFor = (t) => padT + ((t - yMin) / (yMax - yMin)) * innerH;
  const xStep = innerW / Math.max(1, TRAJ.length - 1);
  const xFor = (i) => padL + i * xStep;

  const linePts = TRAJ.map((r, i) => [xFor(i), yFor(r.pred)]);

  const upperPts = TRAJ.map((r, i) => `${xFor(i)},${yFor(r.hi)}`).join(" L ");
  const lowerPts = TRAJ.slice().reverse().map((r, i) => `${xFor(TRAJ.length - 1 - i)},${yFor(r.lo)}`).join(" L ");
  const bandD = `M ${upperPts} L ${lowerPts} Z`;

  const goalY = yFor(GOAL_RACE.goal);
  const stretchY = yFor(GOAL_RACE.stretchGoal);

  const yTicks = [s(180, 0), s(190, 0), s(200, 0), s(210, 0)];

  return (
    <svg viewBox={`0 0 ${W} ${H}`} className="w-full h-auto block">
      {/* y grid */}
      {yTicks.map((t) => {
        const y = yFor(t);
        return (
          <g key={t}>
            <line x1={padL} x2={W - padR} y1={y} y2={y} stroke="#E8E4E0" strokeDasharray="2 4" strokeWidth="1" />
            <text x={padL - 10} y={y + 3.5} textAnchor="end" fontFamily="ui-monospace, Menlo, monospace" fontSize="9.5" letterSpacing="1.2" fill={INK3}>
              {fmtSec(t)}
            </text>
          </g>
        );
      })}
      <text x={padL - 10} y={padT - 8} textAnchor="end" fontFamily="ui-monospace, Menlo, monospace" fontSize="9" letterSpacing="1.3" fill={INK3}>FINISH</text>

      {/* goal line */}
      <line x1={padL} x2={W - padR} y1={goalY} y2={goalY} stroke={ACCENT} strokeWidth="1.2" strokeDasharray="6 4" opacity="0.75" />
      <text x={W - padR} y={goalY - 6} textAnchor="end" fontFamily="ui-monospace, Menlo, monospace" fontSize="9.5" letterSpacing="1.3" fill={ACCENT} fontWeight={600}>
        GOAL · {fmtSec(GOAL_RACE.goal)}
      </text>

      {/* stretch goal */}
      <line x1={padL} x2={W - padR} y1={stretchY} y2={stretchY} stroke={INK3} strokeWidth="1" strokeDasharray="2 3" opacity="0.6" />
      <text x={W - padR} y={stretchY - 4} textAnchor="end" fontFamily="ui-monospace, Menlo, monospace" fontSize="8.5" letterSpacing="1.3" fill={INK3}>
        STRETCH · {fmtSec(GOAL_RACE.stretchGoal)}
      </text>

      {/* band */}
      <path d={bandD} fill={INK} opacity="0.07" />

      {/* prediction line */}
      <polyline
        points={linePts.map(([x, y]) => `${x.toFixed(1)},${y.toFixed(1)}`).join(" ")}
        fill="none"
        stroke={INK}
        strokeWidth="2"
        strokeLinejoin="round"
      />

      {/* dots */}
      {TRAJ.map((r, i) => (
        <g key={r.wk}>
          <circle cx={linePts[i][0]} cy={linePts[i][1]} r={r.current ? 6 : 3} fill={r.current ? ACCENT : INK} />
          {r.current ? (
            <text x={linePts[i][0]} y={linePts[i][1] - 14} textAnchor="middle"
              fontFamily="ui-monospace, Menlo, monospace" fontSize="10.5" letterSpacing="1.2"
              fill={ACCENT} fontWeight={700}>
              {fmtSec(r.pred)}
            </text>
          ) : null}
        </g>
      ))}

      {/* x labels */}
      {TRAJ.map((r, i) => (
        <g key={r.wk}>
          <text x={xFor(i)} y={H - 24} textAnchor="middle"
            fontFamily="ui-monospace, Menlo, monospace" fontSize="9.5" letterSpacing="1.2"
            fill={r.current ? ACCENT : INK} fontWeight={r.current ? 700 : 500}>
            WK {r.wk}
          </text>
          <text x={xFor(i)} y={H - 10} textAnchor="middle"
            fontFamily="ui-monospace, Menlo, monospace" fontSize="8.5" letterSpacing="1.1" fill={INK3}>
            {r.label}
          </text>
        </g>
      ))}
    </svg>
  );
}

/* ════════════════════════════════════════════════════════════════════
   FIG. C — Goal race plan (Boston)
   ════════════════════════════════════════════════════════════════════ */
function FigGoalRace() {
  return (
    <section>
      <FigHeader id="C" title="Goal race · the pace plan" right={`BOSTON · ${GOAL_RACE.date.toUpperCase()}`} />
      <div className="mt-5 grid lg:grid-cols-[1fr_280px] gap-6">
        <article className="border border-divider rounded-lg bg-bg-card p-6 fig-card">
          <Mono>BLOCK SPLITS · BY SECTION</Mono>
          <div className="mt-3 divide-y divide-divider-soft">
            {GOAL_RACE.paceBuckets.map((b) => (
              <div key={b.range} className="grid grid-cols-[120px_84px_1fr] items-baseline gap-x-4 py-3.5">
                <div>
                  <p className="font-display text-[18px] tracking-[-0.005em]">{b.range}</p>
                </div>
                <div className="text-right">
                  <p className="font-mono text-[16px] tabular-nums" style={{ color: b.color }}>
                    {fmtSec(b.pace)}
                  </p>
                  <p className="font-mono text-[9px] tracking-[1.3px] uppercase text-text-tertiary mt-0.5">
                    / MI
                  </p>
                </div>
                <p className="font-body italic text-[14px] leading-[1.5] text-text-secondary">
                  {b.note}
                </p>
              </div>
            ))}
          </div>

          <div className="mt-5 pt-4 border-t border-divider-soft coach-note text-[14px] leading-[1.55]">
            The race isn&rsquo;t at 7:18 the whole way &mdash; the course
            won&rsquo;t let you. Plan the rhythm, not the math. Newton is
            the bill; the drop is the credit.
          </div>
        </article>

        {/* Right column — totals + meta */}
        <aside className="border border-divider rounded-lg bg-bg-elevated p-6 fig-card">
          <Mono>RACE TOTALS</Mono>
          <p className="mt-2 font-display text-[40px] tabular-nums tracking-[-0.01em] leading-none">
            {fmtSec(GOAL_RACE.goal)}
          </p>
          <p className="mt-1 font-mono text-[9.5px] tracking-[1.3px] uppercase text-text-tertiary">
            GOAL FINISH · {fmtSec(s(7, 18))} / MI
          </p>

          <div className="mt-5 pt-5 border-t border-divider-soft">
            <Mono color={ACCENT}>MODEL SAYS</Mono>
            <p className="mt-1 font-display text-[28px] tabular-nums tracking-[-0.01em] leading-none" style={{ color: ACCENT }}>
              {fmtSec(GOAL_RACE.modelPred)}
            </p>
            <p className="mt-1 font-mono text-[9.5px] tracking-[1.3px] uppercase text-text-tertiary">
              {fmtDelta(GOAL_RACE.modelPred - GOAL_RACE.goal)} VS GOAL
            </p>
          </div>

          <div className="mt-5 pt-5 border-t border-divider-soft">
            <Mono>STRETCH</Mono>
            <p className="mt-1 font-display text-[22px] tabular-nums tracking-[-0.01em] leading-none">
              {fmtSec(GOAL_RACE.stretchGoal)}
            </p>
            <p className="mt-1 font-mono text-[9.5px] tracking-[1.3px] uppercase text-text-tertiary">
              ON A GOOD DAY · 7:15 / MI
            </p>
          </div>

          <div className="mt-6 inline-flex items-center gap-2 font-mono text-[10.5px] tracking-[1.5px] uppercase" style={{ color: ACCENT }}>
            Export pace band ↗
          </div>
        </aside>
      </div>
    </section>
  );
}

/* ════════════════════════════════════════════════════════════════════
   FIG. D — What-if scenarios
   ════════════════════════════════════════════════════════════════════ */
function FigScenarios() {
  const base = GOAL_RACE.modelPred;
  return (
    <section>
      <FigHeader id="D" title="What if · scenarios on the marathon" right="DELTA vs MODEL · BOSTON" />
      <div className="mt-5 grid md:grid-cols-2 gap-4">
        {SCENARIOS.map((sc) => {
          const result = base + sc.deltaSec;
          const better = sc.deltaSec < 0;
          return (
            <article key={sc.id} className="border border-divider rounded-lg bg-bg-card p-5 fig-card relative overflow-hidden">
              <div className="flex items-baseline justify-between">
                <Mono color={sc.accent ? ACCENT : INK3}>{sc.label.toUpperCase()}</Mono>
                <span className="font-mono text-[10px] tabular-nums tracking-[1.3px]"
                  style={{ color: better ? "#2D8A4E" : "#C45A3A", fontWeight: 600 }}>
                  {fmtDelta(sc.deltaSec)}
                </span>
              </div>
              <p className="mt-3 font-display text-[32px] tabular-nums tracking-[-0.01em] leading-none"
                style={{ color: sc.accent ? ACCENT : INK }}>
                {fmtSec(result)}
              </p>
              <p className="mt-2 font-body italic text-[13.5px] text-text-secondary leading-[1.5]">
                {sc.note}
              </p>
            </article>
          );
        })}
      </div>
    </section>
  );
}

/* ════════════════════════════════════════════════════════════════════
   FIG. E — Course / conditions adjustments
   ════════════════════════════════════════════════════════════════════ */
function FigAdjustments() {
  return (
    <section>
      <FigHeader id="E" title="Conditions · what slows you, what helps" right="MARATHON · ROUGH ORDER" />
      <div className="mt-5 border border-divider rounded-lg bg-bg-card overflow-hidden fig-card">
        <div className="grid grid-cols-[160px_1fr_120px_120px] items-baseline gap-x-4 px-6 pt-5 pb-3 border-b border-divider-soft bg-bg-elevated/40">
          <Mono>FACTOR</Mono>
          <Mono>SHIFT</Mono>
          <Mono className="text-right block">EFFECT</Mono>
          <Mono className="text-right block">NEW FINISH</Mono>
        </div>
        <div className="divide-y divide-divider-soft">
          {ADJUSTMENTS.map((a) => {
            const helps = a.delta < 0;
            const result = GOAL_RACE.modelPred + a.delta;
            return (
              <div key={a.id} className="grid grid-cols-[160px_1fr_120px_120px] items-center gap-x-4 px-6 py-3.5">
                <p className="font-display text-[16px] tracking-[-0.005em]">{a.label}</p>
                <p className="font-body text-[13.5px] text-text-secondary">
                  <span className="font-mono text-[10.5px] tracking-[1.3px] uppercase text-text-tertiary">{a.from}</span>
                  <span className="mx-2 text-text-tertiary">→</span>
                  <span className="font-mono text-[10.5px] tracking-[1.3px] uppercase text-text-primary">{a.to}</span>
                </p>
                <p className="font-mono text-[12px] tabular-nums text-right"
                  style={{ color: helps ? "#2D8A4E" : "#C45A3A", fontWeight: 600 }}>
                  {fmtDelta(a.delta)}
                </p>
                <p className="font-mono text-[12px] tabular-nums text-right text-text-primary">
                  {fmtSec(result)}
                </p>
              </div>
            );
          })}
        </div>
        <p className="px-6 py-4 border-t border-divider-soft font-body italic text-[12.5px] text-text-tertiary">
          Estimates from Daniels heat/wind tables and elevation models. Real
          day, real race &mdash; one of them gets a vote you can&rsquo;t see
          on this page.
        </p>
      </div>
    </section>
  );
}

/* ════════════════════════════════════════════════════════════════════
   COACH READ — long-form
   ════════════════════════════════════════════════════════════════════ */
function CoachRead() {
  return (
    <section className="relative">
      <div className="editorial-rule mb-8">
        <span className="editorial-rule__dot" />
      </div>
      <div className="grid lg:grid-cols-[180px_1fr] gap-x-10">
        <div>
          <Mono color={ACCENT}>FROM YOUR COACH</Mono>
          <p className="mt-2 font-mono text-[10px] tracking-[1.3px] uppercase text-text-tertiary">
            ON THE PREDICTION · WK 9
          </p>
          <p className="mt-1 font-mono text-[10px] tracking-[1.3px] uppercase text-text-tertiary">
            AUTO-GENERATED · COACH-REVIEWED
          </p>
        </div>
        <div className="max-w-[640px]">
          <p className="font-body text-[18px] leading-[1.65] text-text-primary">
            The model has you at 3:08, six minutes under goal. I want you to
            read that the right way: it&rsquo;s a measurement of the engine,
            not a forecast of the day. Boston has its own opinion about
            those last six miles, and your body has an opinion about the
            seven weeks between now and then.
          </p>
          <p className="mt-4 font-body text-[16px] leading-[1.65] text-text-primary">
            What the prediction is telling us, honestly, is that the goal
            window has moved. Sub-3:15 was the conservative line in February.
            It isn&rsquo;t anymore. We don&rsquo;t need to chase the model
            number &mdash; we just need to plan the race off where the
            fitness actually is. That&rsquo;s a conversation for after
            Saturday&rsquo;s long.
          </p>
          <p className="mt-4 font-body italic text-[15px] leading-[1.6] text-text-secondary">
            The bands matter. The HM number narrowed after May 2 because we
            have a hard data point. The marathon band is still wide because
            we don&rsquo;t. Trust what we&rsquo;ve measured. Be honest about
            what we haven&rsquo;t.
          </p>
          <div className="mt-6 inline-flex items-center gap-2 font-mono text-[10.5px] tracking-[1.5px] uppercase" style={{ color: ACCENT }}>
            Ask follow-up <span>↗</span>
          </div>
        </div>
      </div>
    </section>
  );
}

/* ════════════════════════════════════════════════════════════════════
   Helpers
   ════════════════════════════════════════════════════════════════════ */
function FigHeader({ id, title, right }) {
  return (
    <div className="flex items-baseline justify-between border-b border-divider-soft pb-3">
      <div className="flex items-baseline gap-3">
        <Mono>FIG. {id}</Mono>
        <span className="font-display text-[22px] tracking-[-0.01em] text-text-primary">
          {title}
        </span>
      </div>
      <Mono>{right}</Mono>
    </div>
  );
}

function Footer() {
  return (
    <div className="mt-8 pt-6 border-t border-divider-soft flex items-center justify-between">
      <Mono>POST RUN DRIP · FITNESS PREDICTOR</Mono>
      <Mono>FORWARD READ · SPRING ’26</Mono>
    </div>
  );
}

/* ── mount ──────────────────────────────────────────────────────── */
const root = ReactDOM.createRoot(document.getElementById("root"));
root.render(<App />);

/* global React */
/* ════════════════════════════════════════════════════════════════════
   POST RUN DRIP — TRAINING ANALYSIS (v1 · block view)
   The long read. Where the block has been, where it's going.
   Sibling to: Training Summary (this week) · Training Log (workout-by-workout)
   ════════════════════════════════════════════════════════════════════ */

const { useState, useMemo } = React;
const ACCENT = "#D4592A";
const SAGE = "#6B8068";
const PLUM = "#6B4A8A";
const INK = "#1A1815";
const INK2 = "#6B6560";
const INK3 = "#9B9590";

/* ── Tweaks defaults ────────────────────────────────────────────── */
const TWEAK_DEFAULTS = /*EDITMODE-BEGIN*/{
  "window": "4w",
  "coachVoice": "medium",
  "chartStyle": "bars",
  "density": "regular",
  "showRaceReadiness": true
}/*EDITMODE-END*/;

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
   DATA — fabricated but internally consistent.
   Marathon block, week 9 of 16, building toward Boston (Jul 12).
   8 weeks of history; analysis defaults to last 4.
   ════════════════════════════════════════════════════════════════════ */

const WEEKS = [
  { idx: 1, label: "Mar 16", miles: 36, planned: 38, quality: 1, longRun: 12, avgHR: 142, avgPace: 8.85, tsbStart: -8 },
  { idx: 2, label: "Mar 23", miles: 42, planned: 42, quality: 2, longRun: 14, avgHR: 146, avgPace: 8.62, tsbStart: -14 },
  { idx: 3, label: "Mar 30", miles: 45, planned: 48, quality: 2, longRun: 14, avgHR: 148, avgPace: 8.48, tsbStart: -18 },
  { idx: 4, label: "Apr 6",  miles: 38, planned: 38, quality: 1, longRun: 12, avgHR: 144, avgPace: 8.55, tsbStart: -10, deload: true },
  { idx: 5, label: "Apr 13", miles: 48, planned: 48, quality: 2, longRun: 16, avgHR: 150, avgPace: 8.35, tsbStart: -22 },
  { idx: 6, label: "Apr 20", miles: 48, planned: 50, quality: 2, longRun: 14, avgHR: 152, avgPace: 8.40, tsbStart: -24 },
  { idx: 7, label: "Apr 27", miles: 42, planned: 44, quality: 1, longRun: 13, avgHR: 149, avgPace: 8.30, tsbStart: -16, deload: true },
  { idx: 8, label: "May 4",  miles: 50, planned: 50, quality: 2, longRun: 16, avgHR: 151, avgPace: 8.22, tsbStart: -22 },
  { idx: 9, label: "May 11", miles: 27, planned: 51, quality: 1, longRun: 18, avgHR: 150, avgPace: 7.92, tsbStart: -19, current: true, partial: true },
];

/* Pace distribution buckets (minutes per mile, % of miles in window) */
const PACE_BUCKETS = [
  { label: "≤ 6:30", min: 0,   max: 6.5,  zone: "5K",   curr: 4,  prior: 1,  color: PLUM },
  { label: "6:30–7:00", min: 6.5, max: 7.0, zone: "10K", curr: 6,  prior: 5,  color: PLUM },
  { label: "7:00–7:30", min: 7.0, max: 7.5, zone: "Thr", curr: 10, prior: 8,  color: ACCENT },
  { label: "7:30–8:00", min: 7.5, max: 8.0, zone: "MP",  curr: 8,  prior: 6,  color: ACCENT },
  { label: "8:00–8:30", min: 8.0, max: 8.5, zone: "Mod", curr: 22, prior: 26, color: INK },
  { label: "8:30–9:00", min: 8.5, max: 9.0, zone: "Easy",curr: 36, prior: 38, color: INK },
  { label: "9:00+",     min: 9.0, max: 11,  zone: "Rec", curr: 14, prior: 16, color: SAGE },
];

/* HR-zone time (minutes), week vs 4-wk avg */
const HR_ZONES = [
  { z: "Z1", name: "Recovery",  range: "< 130", curr: 18, prior: 24, color: SAGE },
  { z: "Z2", name: "Aerobic",   range: "130–148", curr: 184, prior: 168, color: INK },
  { z: "Z3", name: "Tempo",     range: "148–162", curr: 62, prior: 48, color: ACCENT },
  { z: "Z4", name: "Threshold", range: "162–172", curr: 28, prior: 22, color: ACCENT },
  { z: "Z5", name: "VO₂ Max",   range: "> 172",  curr: 6,  prior: 4,  color: PLUM },
];

/* Workout type mix, last 4 weeks */
const TYPE_MIX = [
  { type: "Easy",       miles: 92, count: 11, color: INK,    accent: false },
  { type: "Long",       miles: 61, count: 4,  color: SAGE,   accent: false },
  { type: "Tempo",      miles: 24, count: 3,  color: ACCENT, accent: true },
  { type: "Intervals",  miles: 13, count: 2,  color: ACCENT, accent: true },
  { type: "Race / sim", miles: 13, count: 1,  color: PLUM,   accent: true },
  { type: "Recovery",   miles: 12, count: 3,  color: INK3,   accent: false },
];

/* Race-readiness · predicted marathon finish over the block */
const READINESS = [
  { wk: "Wk 1",  pred: 3.42, hi: 3.50, lo: 3.36 },  // 3:25 = 3 + 25/60
  { wk: "Wk 2",  pred: 3.38, hi: 3.46, lo: 3.32 },
  { wk: "Wk 3",  pred: 3.32, hi: 3.40, lo: 3.27 },
  { wk: "Wk 4",  pred: 3.30, hi: 3.38, lo: 3.25 },
  { wk: "Wk 5",  pred: 3.27, hi: 3.34, lo: 3.22 },
  { wk: "Wk 6",  pred: 3.25, hi: 3.32, lo: 3.20 },
  { wk: "Wk 7",  pred: 3.23, hi: 3.30, lo: 3.18 },
  { wk: "Wk 8",  pred: 3.20, hi: 3.27, lo: 3.15 },
  { wk: "Wk 9",  pred: 3.18, hi: 3.25, lo: 3.13, current: true },
];
const GOAL_TIME = 3.25; // 3:15

/* ── helpers ────────────────────────────────────────────────────── */
function fmtTime(h) {
  // h = decimal hours, e.g. 3.25 → "3:15"
  const hh = Math.floor(h);
  const mm = Math.round((h - hh) * 60);
  return `${hh}:${String(mm).padStart(2, "0")}`;
}
function fmtPace(decimalMin) {
  const m = Math.floor(decimalMin);
  const s = Math.round((decimalMin - m) * 60);
  return `${m}:${String(s).padStart(2, "0")}`;
}

/* ════════════════════════════════════════════════════════════════════
   APP
   ════════════════════════════════════════════════════════════════════ */
function App() {
  const [tweaks, setTweak] = useTweaks(TWEAK_DEFAULTS);
  const win = tweaks.window;

  // Select weeks based on window
  const visibleWeeks = useMemo(() => {
    if (win === "8w") return WEEKS;
    if (win === "block") return WEEKS;
    return WEEKS.slice(-4); // 4w default
  }, [win]);

  return (
    <div className="min-h-screen bg-bg-base text-text-primary font-body">
      <div className="flex h-screen overflow-hidden">
        <Sidebar />
        <div className="flex flex-1 flex-col overflow-hidden">
          <TopNav />
          <main className="flex-1 overflow-y-auto">
            <AnalysisPage tweaks={tweaks} setTweak={setTweak} weeks={visibleWeeks} />
          </main>
        </div>
      </div>

      <TweaksPanel>
        <TweakSection label="Time window" />
        <TweakRadio
          label="Range"
          value={tweaks.window}
          options={["4w", "8w", "block"]}
          onChange={(v) => setTweak("window", v)}
        />
        <TweakSection label="Editorial" />
        <TweakSelect
          label="Coach voice"
          value={tweaks.coachVoice}
          options={[
            { value: "light",  label: "Light · one line at top" },
            { value: "medium", label: "Medium · block read" },
            { value: "heavy",  label: "Heavy · note per figure" },
          ]}
          onChange={(v) => setTweak("coachVoice", v)}
        />
        <TweakRadio
          label="Charts"
          value={tweaks.chartStyle}
          options={["bars", "lines"]}
          onChange={(v) => setTweak("chartStyle", v)}
        />
        <TweakSelect
          label="Density"
          value={tweaks.density}
          options={[
            { value: "compact", label: "Compact" },
            { value: "regular", label: "Regular" },
            { value: "comfy",   label: "Comfy" },
          ]}
          onChange={(v) => setTweak("density", v)}
        />
        <TweakSection label="Modules" />
        <TweakToggle
          label="Race readiness"
          value={tweaks.showRaceReadiness}
          onChange={(v) => setTweak("showRaceReadiness", v)}
        />
      </TweaksPanel>
    </div>
  );
}

/* ── SIDEBAR ────────────────────────────────────────────────────── */
function Sidebar() {
  const items = [
    { label: "Dashboard", on: false, href: "Training Summary.html" },
    { label: "Training log", on: false, href: "Training Log.html" },
    { label: "Coach", on: false, href: "#" },
    { label: "Plan", on: false, href: "Plan Page.html" },
  ];
  const more = [
    { label: "Coach portal", on: false },
    { label: "Goals", on: false },
    { label: "Analysis", on: true },
    { label: "Injuries", on: false },
    { label: "Fitness predictor", on: false, href: "Fitness Predictor.html" },
    { label: "Pace chart", on: false },
    { label: "Content library", on: false },
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
                  href="#"
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
      <Mono>RUNNING LOG · ANALYSIS</Mono>
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
function AnalysisPage({ tweaks, setTweak, weeks }) {
  const maxWidth = tweaks.density === "comfy" ? "max-w-[1120px]" : "max-w-[1080px]";
  const sectionGap = tweaks.density === "compact" ? "space-y-10" : tweaks.density === "comfy" ? "space-y-16" : "space-y-12";
  return (
    <div className={`mx-auto ${maxWidth} px-10 py-10 ${sectionGap}`}>
      <PlateHeader />
      <Lede />
      <WindowStrip tweaks={tweaks} setTweak={setTweak} weeks={weeks} />
      {tweaks.coachVoice === "light" ? <CoachLine variant="top" /> : null}
      <BlockStateTiles weeks={weeks} />
      <FigMileage weeks={weeks} chartStyle={tweaks.chartStyle} coachVoice={tweaks.coachVoice} />
      <FigPaceDistribution coachVoice={tweaks.coachVoice} chartStyle={tweaks.chartStyle} />
      <FigSplitTwoUp coachVoice={tweaks.coachVoice} />
      {tweaks.showRaceReadiness ? (
        <FigRaceReadiness coachVoice={tweaks.coachVoice} />
      ) : null}
      {tweaks.coachVoice === "medium" ? <BlockRead /> : null}
      {tweaks.coachVoice === "heavy" ? <BlockRead /> : null}
      <WhatChanged />
      <Footer />
    </div>
  );
}

function PlateHeader() {
  return (
    <div className="flex items-baseline justify-between border-b border-divider-soft pb-3">
      <Mono>RUNNING LOG · TRAINING ANALYSIS · v1 BLOCK VIEW</Mono>
      <Mono>WK 9 OF 16 · SUB-3:15 MARATHON BUILD</Mono>
    </div>
  );
}

/* ── editorial lede ─────────────────────────────────────────────── */
function Lede() {
  return (
    <section>
      <Mono color={ACCENT}>THE BLOCK · APR 13 – MAY 11</Mono>
      <h1 className="mt-3 font-display text-[44px] leading-[1.02] tracking-[-0.015em] max-w-[760px]">
        The shape is holding.
      </h1>
      <p className="mt-4 max-w-[600px] font-body text-[16px] leading-[1.6] text-text-secondary">
        Eight weeks into the Boston build. A look at what the miles built,
        where the pace went, and what&rsquo;s left between today and the
        start line.
      </p>
    </section>
  );
}

/* ── window selector + headline meta ────────────────────────────── */
function WindowStrip({ tweaks, setTweak, weeks }) {
  const opts = [
    { id: "4w",    label: "Last 4 wk" },
    { id: "8w",    label: "Last 8 wk" },
    { id: "block", label: "Full block" },
  ];
  const totalMi = weeks.reduce((s, w) => s + w.miles, 0);
  const qual = weeks.reduce((s, w) => s + w.quality, 0);
  return (
    <div className="flex items-end justify-between border-t border-divider-soft pt-5">
      <div className="flex items-center gap-1">
        {opts.map((o) => {
          const on = tweaks.window === o.id;
          return (
            <button
              key={o.id}
              onClick={() => setTweak("window", o.id)}
              className="font-mono text-[10.5px] tracking-[1.5px] uppercase px-3 py-1.5 rounded-md transition-colors"
              style={{
                color: on ? ACCENT : INK2,
                background: on ? "rgba(212,89,42,0.08)" : "transparent",
                fontWeight: on ? 700 : 500,
              }}
            >
              {o.label}
            </button>
          );
        })}
      </div>
      <div className="text-right leading-tight">
        <Mono>WINDOW · {weeks.length} WEEKS · {totalMi.toFixed(0)} MI · {qual} QUALITY</Mono>
      </div>
    </div>
  );
}

/* ── optional one-line coach top callout ────────────────────────── */
function CoachLine({ variant }) {
  return (
    <div className="border-l-[2px] border-coral/60 pl-4 max-w-[640px]">
      <Mono color={ACCENT}>FROM YOUR COACH</Mono>
      <p className="mt-1 font-display italic text-[20px] leading-[1.35] text-text-primary tracking-[-0.005em]">
        &ldquo;The block is doing its job. Stay patient through the taper.&rdquo;
      </p>
    </div>
  );
}

/* ════════════════════════════════════════════════════════════════════
   BLOCK STATE TILES — 4-up · CTL / ATL / TSB / Ramp
   ════════════════════════════════════════════════════════════════════ */
function BlockStateTiles({ weeks }) {
  const current = weeks[weeks.length - 1];
  const fourWkAvg = weeks.slice(-4).reduce((s, w) => s + w.miles, 0) / Math.min(4, weeks.length);
  const eightWkAvg = WEEKS.slice(-8).reduce((s, w) => s + w.miles, 0) / 8;
  const tiles = [
    {
      label: "FITNESS",
      sublabel: "CTL · 42-day load",
      value: "58",
      unit: "tss/d",
      hint: "+6 vs. block start",
      trend: "up",
      sparkData: [44, 46, 49, 47, 52, 54, 53, 56, 58],
      accent: true,
    },
    {
      label: "FATIGUE",
      sublabel: "ATL · 7-day load",
      value: "71",
      unit: "tss/d",
      hint: "loaded · sat will sting",
      trend: "up",
      sparkData: [52, 58, 64, 61, 68, 72, 66, 74, 71],
    },
    {
      label: "FORM",
      sublabel: "TSB · readiness",
      value: "−13",
      unit: "tss",
      hint: "in the build zone",
      trend: "neutral",
      sparkData: [-8, -14, -18, -10, -22, -24, -16, -22, -13],
      neg: true,
    },
    {
      label: "RAMP",
      sublabel: "vs. 4-wk avg",
      value: "+8%",
      unit: "wk over wk",
      hint: "inside the 10% rule",
      trend: "up",
      sparkData: [3, 6, 8, -10, 12, 0, -8, 14, 8],
    },
  ];
  return (
    <section className="grid grid-cols-2 md:grid-cols-4 gap-0 border-y border-divider divide-x divide-divider">
      {tiles.map((t) => (
        <BlockTile key={t.label} tile={t} />
      ))}
    </section>
  );
}

function BlockTile({ tile }) {
  return (
    <div className="px-6 py-6">
      <Mono color={tile.accent ? ACCENT : INK3}>{tile.label}</Mono>
      <p className="mt-2 font-display text-[40px] leading-none tabular-nums tracking-[-0.02em]" style={{ color: tile.neg ? INK : INK }}>
        {tile.value}
        {tile.unit ? (
          <span className="ml-1.5 font-mono text-[10.5px] tracking-[1.3px] uppercase text-text-tertiary" style={{ fontSize: "10px" }}>
            {tile.unit}
          </span>
        ) : null}
      </p>
      <p className="mt-1 font-mono text-[9.5px] tracking-[1.3px] uppercase text-text-tertiary">
        {tile.sublabel}
      </p>
      <p className="mt-2 font-mono text-[10px] tracking-[1.3px] uppercase inline-flex items-center gap-1"
        style={{ color: tile.trend === "up" && tile.accent ? "#2D8A4E" : INK3 }}>
        {tile.trend === "up" ? <span>↑</span> : tile.trend === "down" ? <span>↓</span> : null}
        {tile.hint}
      </p>
      <div className="mt-4">
        <Spark data={tile.sparkData} color={tile.accent ? ACCENT : INK} />
      </div>
    </div>
  );
}

function Spark({ data, color }) {
  const W = 200, H = 28;
  const min = Math.min(...data);
  const max = Math.max(...data);
  const range = Math.max(1, max - min);
  const pts = data.map((v, i) => {
    const x = (i / (data.length - 1)) * W;
    const y = H - ((v - min) / range) * (H - 4) - 2;
    return [x, y];
  });
  return (
    <svg viewBox={`0 0 ${W} ${H}`} className="w-full h-[28px] block" preserveAspectRatio="none">
      <polyline
        points={pts.map(([x, y]) => `${x.toFixed(1)},${y.toFixed(1)}`).join(" ")}
        fill="none"
        stroke={color}
        strokeWidth="1.5"
        strokeLinejoin="round"
        strokeLinecap="round"
        opacity="0.85"
      />
      <circle cx={pts[pts.length - 1][0]} cy={pts[pts.length - 1][1]} r="2.2" fill={color} />
    </svg>
  );
}

/* ════════════════════════════════════════════════════════════════════
   FIG. A — Mileage & quality, by week
   ════════════════════════════════════════════════════════════════════ */
function FigMileage({ weeks, chartStyle, coachVoice }) {
  return (
    <section>
      <FigHeader id="A" title="Mileage & quality, by week" right="MILES / WK" />
      <div className="mt-5 border border-divider rounded-lg bg-bg-card p-6 fig-card">
        {chartStyle === "lines" ? (
          <MileageLine weeks={weeks} />
        ) : (
          <MileageBars weeks={weeks} />
        )}
        <div className="mt-5 pt-4 border-t border-divider-soft grid grid-cols-3 gap-x-6 gap-y-2">
          <LegendDot color={INK}    label="Easy + steady" />
          <LegendDot color={ACCENT} label="Quality (tempo / interval)" />
          <LegendDot color={SAGE}   label="Long run" />
          <LegendDot color="transparent" borderColor={ACCENT} label="Planned (current week)" dashed />
        </div>
        {coachVoice === "heavy" ? (
          <p className="mt-5 coach-note text-[14px] leading-[1.55]">
            Eight weeks of building, two deloads where they belonged. The big
            number that matters: 50 miles last week with one quality session
            still in legs that responded to Tuesday&rsquo;s tempo. That&rsquo;s a
            fit athlete, not a tired one.
          </p>
        ) : (
          <p className="mt-5 font-body italic text-[13px] text-text-secondary">
            Two deloads (wk 4, wk 7) sit exactly where they should. Last full
            week — 50 mi — and Tuesday already in the bank for week 9.
          </p>
        )}
      </div>
    </section>
  );
}

function MileageBars({ weeks }) {
  const W = 960;
  const H = 280;
  const padL = 44, padR = 16, padT = 24, padB = 56;
  const innerW = W - padL - padR;
  const innerH = H - padT - padB;
  const max = Math.max(60, ...weeks.map((w) => Math.max(w.miles, w.planned))) * 1.05;
  const slot = innerW / weeks.length;
  const barW = Math.min(48, slot * 0.55);
  const yTicks = [0, 20, 40, 60];

  return (
    <svg viewBox={`0 0 ${W} ${H}`} className="w-full h-auto block">
      {yTicks.map((t) => {
        const y = padT + ((max - t) / max) * innerH;
        return (
          <g key={t}>
            <line x1={padL} x2={W - padR} y1={y} y2={y} stroke="#E8E4E0" strokeDasharray={t === 0 ? "0" : "2 4"} strokeWidth="1" />
            <text x={padL - 10} y={y + 3.5} textAnchor="end" fontFamily="ui-monospace, Menlo, monospace" fontSize="9.5" letterSpacing="1.2" fill={INK3}>
              {t}
            </text>
          </g>
        );
      })}
      <text x={padL - 10} y={padT - 8} textAnchor="end" fontFamily="ui-monospace, Menlo, monospace" fontSize="9" letterSpacing="1.3" fill={INK3}>
        MI
      </text>

      {weeks.map((w, i) => {
        const x = padL + i * slot + (slot - barW) / 2;
        const h = (w.miles / max) * innerH;
        const y = padT + (innerH - h);
        const plannedH = (w.planned / max) * innerH;
        const plannedY = padT + (innerH - plannedH);

        // Stack: quality on top of base
        const qualityMi = Math.min(w.miles, w.quality * 6 + (w.longRun || 0));
        const longH = ((w.longRun || 0) / max) * innerH;
        const qualPortion = Math.max(0, qualityMi - (w.longRun || 0));
        const qualH = (qualPortion / max) * innerH;
        const baseH = h - longH - qualH;

        return (
          <g key={w.idx}>
            {/* planned outline for current/partial */}
            {w.partial ? (
              <rect
                x={x - 2}
                y={plannedY}
                width={barW + 4}
                height={plannedH - h}
                fill="transparent"
                stroke={ACCENT}
                strokeDasharray="3 3"
                strokeWidth="1"
                opacity="0.7"
              />
            ) : null}

            {/* deload band */}
            {w.deload ? (
              <rect x={x - 2} y={padT} width={barW + 4} height={innerH} fill={INK} opacity="0.025" />
            ) : null}

            {/* base */}
            <rect x={x} y={y + qualH + longH} width={barW} height={baseH} fill={INK} opacity={w.current ? 0.95 : 0.85} rx="1" />
            {/* quality stack */}
            {qualH > 0 ? <rect x={x} y={y + longH} width={barW} height={qualH} fill={ACCENT} rx="1" /> : null}
            {/* long stack */}
            {longH > 0 ? <rect x={x} y={y} width={barW} height={longH} fill={SAGE} rx="1" /> : null}

            {/* miles label */}
            <text x={x + barW / 2} y={y - 8} textAnchor="middle" fontFamily="ui-monospace, Menlo, monospace" fontSize="10.5" letterSpacing="1.2" fill={w.current ? ACCENT : INK} fontWeight={w.current ? 700 : 500}>
              {w.miles}
            </text>

            {/* x-axis */}
            <text x={x + barW / 2} y={H - 30} textAnchor="middle" fontFamily="ui-monospace, Menlo, monospace" fontSize="9.5" letterSpacing="1.2" fill={w.current ? ACCENT : INK} fontWeight={w.current ? 700 : 500}>
              WK {w.idx}
            </text>
            <text x={x + barW / 2} y={H - 16} textAnchor="middle" fontFamily="ui-monospace, Menlo, monospace" fontSize="8.5" letterSpacing="1.1" fill={INK3}>
              {w.label}
            </text>
            {w.deload ? (
              <text x={x + barW / 2} y={H - 4} textAnchor="middle" fontFamily="ui-monospace, Menlo, monospace" fontSize="7.5" letterSpacing="1.3" fill={INK3}>
                DELOAD
              </text>
            ) : w.current ? (
              <text x={x + barW / 2} y={H - 4} textAnchor="middle" fontFamily="ui-monospace, Menlo, monospace" fontSize="7.5" letterSpacing="1.3" fill={ACCENT} fontWeight={700}>
                NOW
              </text>
            ) : null}
          </g>
        );
      })}
    </svg>
  );
}

function MileageLine({ weeks }) {
  const W = 960, H = 280;
  const padL = 44, padR = 16, padT = 24, padB = 56;
  const innerW = W - padL - padR;
  const innerH = H - padT - padB;
  const max = Math.max(60, ...weeks.map((w) => w.miles)) * 1.05;
  const slot = innerW / Math.max(1, weeks.length - 1);
  const yTicks = [0, 20, 40, 60];
  const pts = weeks.map((w, i) => {
    const x = padL + i * slot;
    const y = padT + ((max - w.miles) / max) * innerH;
    return { x, y, w };
  });
  const areaD = `M ${pts[0].x},${padT + innerH} ` + pts.map((p) => `L ${p.x},${p.y}`).join(" ") + ` L ${pts[pts.length - 1].x},${padT + innerH} Z`;
  const lineD = pts.map((p, i) => `${i === 0 ? "M" : "L"} ${p.x},${p.y}`).join(" ");
  return (
    <svg viewBox={`0 0 ${W} ${H}`} className="w-full h-auto block">
      {yTicks.map((t) => {
        const y = padT + ((max - t) / max) * innerH;
        return (
          <g key={t}>
            <line x1={padL} x2={W - padR} y1={y} y2={y} stroke="#E8E4E0" strokeDasharray={t === 0 ? "0" : "2 4"} strokeWidth="1" />
            <text x={padL - 10} y={y + 3.5} textAnchor="end" fontFamily="ui-monospace, Menlo, monospace" fontSize="9.5" letterSpacing="1.2" fill={INK3}>{t}</text>
          </g>
        );
      })}
      <path d={areaD} fill={ACCENT} opacity="0.08" />
      <path d={lineD} fill="none" stroke={INK} strokeWidth="1.75" strokeLinejoin="round" />
      {pts.map((p) => (
        <g key={p.w.idx}>
          <circle cx={p.x} cy={p.y} r={p.w.current ? 5 : 3.2} fill={p.w.current ? ACCENT : INK} stroke={p.w.current ? ACCENT : "#fff"} strokeWidth={p.w.current ? 0 : 1.5} />
          <text x={p.x} y={p.y - 12} textAnchor="middle" fontFamily="ui-monospace, Menlo, monospace" fontSize="10" letterSpacing="1.2" fill={p.w.current ? ACCENT : INK} fontWeight={p.w.current ? 700 : 500}>
            {p.w.miles}
          </text>
          <text x={p.x} y={H - 30} textAnchor="middle" fontFamily="ui-monospace, Menlo, monospace" fontSize="9.5" letterSpacing="1.2" fill={p.w.current ? ACCENT : INK}>WK {p.w.idx}</text>
          <text x={p.x} y={H - 16} textAnchor="middle" fontFamily="ui-monospace, Menlo, monospace" fontSize="8.5" letterSpacing="1.1" fill={INK3}>{p.w.label}</text>
        </g>
      ))}
    </svg>
  );
}

/* ════════════════════════════════════════════════════════════════════
   FIG. B — Pace distribution, where the miles lived
   ════════════════════════════════════════════════════════════════════ */
function FigPaceDistribution({ coachVoice, chartStyle }) {
  const max = Math.max(...PACE_BUCKETS.map((b) => Math.max(b.curr, b.prior)));
  return (
    <section>
      <FigHeader id="B" title="Pace distribution · where the miles lived" right="% OF TOTAL · 4 WK vs PRIOR 4 WK" />
      <div className="mt-5 border border-divider rounded-lg bg-bg-card p-6 fig-card">
        <div className="grid grid-cols-[160px_1fr_72px_72px] gap-x-4 items-baseline pb-2 border-b border-divider-soft">
          <Mono>BUCKET</Mono>
          <Mono>SHARE</Mono>
          <Mono className="text-right block">CURRENT</Mono>
          <Mono className="text-right block">PRIOR</Mono>
        </div>
        <div className="divide-y divide-divider-soft">
          {PACE_BUCKETS.map((b) => {
            const cw = (b.curr / max) * 100;
            const pw = (b.prior / max) * 100;
            const delta = b.curr - b.prior;
            return (
              <div key={b.label} className="grid grid-cols-[160px_1fr_72px_72px] gap-x-4 items-center py-3">
                <div>
                  <p className="font-mono text-[12px] tabular-nums text-text-primary">
                    {b.label}
                    <span className="ml-1.5 text-text-tertiary text-[9.5px] tracking-[1.3px] uppercase">/mi</span>
                  </p>
                  <p className="font-mono text-[9.5px] tracking-[1.3px] uppercase mt-0.5" style={{ color: b.color }}>
                    {b.zone}
                  </p>
                </div>
                <div>
                  <div className="relative h-[18px]">
                    {/* prior — ghost */}
                    <div
                      className="absolute inset-y-[6px] left-0 rounded-[1px]"
                      style={{
                        width: `${pw}%`,
                        background: INK,
                        opacity: 0.12,
                      }}
                    />
                    {/* current — solid */}
                    <div
                      className="absolute inset-y-0 left-0 rounded-[1px]"
                      style={{
                        width: `${cw}%`,
                        background: b.color,
                        opacity: b.color === INK ? 0.85 : 0.9,
                      }}
                    />
                  </div>
                </div>
                <p className="font-mono text-[12px] tabular-nums text-right text-text-primary">{b.curr}<span className="text-text-tertiary">%</span></p>
                <p className="font-mono text-[11px] tabular-nums text-right text-text-tertiary">{b.prior}<span>%</span>
                  {Math.abs(delta) >= 2 ? (
                    <span className="ml-1.5 text-[9.5px]" style={{ color: delta > 0 ? "#2D8A4E" : "#C45A3A" }}>
                      {delta > 0 ? "↑" : "↓"}{Math.abs(delta)}
                    </span>
                  ) : null}
                </p>
              </div>
            );
          })}
        </div>
        {coachVoice === "heavy" ? (
          <p className="mt-5 coach-note text-[14px] leading-[1.55]">
            The shift you want to see: time at tempo and MP is up, recovery
            miles trimmed back. Most of the work still lives in easy — which
            is where it should — but the sharp end has more presence than the
            prior block.
          </p>
        ) : (
          <p className="mt-5 font-body italic text-[13px] text-text-secondary">
            Tempo and MP share is up. Easy still does most of the work — and
            should.
          </p>
        )}
      </div>
    </section>
  );
}

/* ════════════════════════════════════════════════════════════════════
   FIG. C + D — Workout mix and HR zones, side by side
   ════════════════════════════════════════════════════════════════════ */
function FigSplitTwoUp({ coachVoice }) {
  return (
    <section className="grid lg:grid-cols-2 gap-x-8 gap-y-10">
      <FigWorkoutMix coachVoice={coachVoice} />
      <FigHRZones coachVoice={coachVoice} />
    </section>
  );
}

function FigWorkoutMix({ coachVoice }) {
  const total = TYPE_MIX.reduce((s, t) => s + t.miles, 0);
  return (
    <article className="fig-card">
      <FigHeader id="C" title="Workout mix" right={`${total} MI`} />
      <div className="mt-5 border border-divider rounded-lg bg-bg-card p-6">
        {/* Stacked horizontal bar */}
        <div className="flex items-baseline justify-between">
          <Mono>BY MILEAGE</Mono>
          <Mono>{total} MI · 24 RUNS</Mono>
        </div>
        <div className="mt-3 flex h-[28px] overflow-hidden rounded-[2px] border border-divider-soft">
          {TYPE_MIX.map((t) => {
            const pct = (t.miles / total) * 100;
            return (
              <div
                key={t.type}
                style={{ width: `${pct}%`, background: t.color, opacity: t.accent ? 1 : 0.85 }}
                title={`${t.type} · ${t.miles} mi · ${pct.toFixed(0)}%`}
              />
            );
          })}
        </div>

        {/* Legend rows */}
        <div className="mt-4 divide-y divide-divider-soft">
          {TYPE_MIX.map((t) => {
            const pct = (t.miles / total) * 100;
            return (
              <div key={t.type} className="grid grid-cols-[14px_1fr_40px_60px] items-center gap-x-3 py-2">
                <span className="block h-[10px] w-[10px] rounded-[1px]" style={{ background: t.color, opacity: t.accent ? 1 : 0.85 }} />
                <span className="font-display text-[14px] tracking-[-0.005em] text-text-primary">{t.type}</span>
                <span className="font-mono text-[11px] tabular-nums text-text-secondary text-right">{t.count}<span className="ml-0.5 text-[9px] tracking-[1.2px] uppercase text-text-tertiary">runs</span></span>
                <span className="font-mono text-[11.5px] tabular-nums text-text-primary text-right">{t.miles}<span className="ml-0.5 text-[9px] tracking-[1.2px] uppercase text-text-tertiary">mi</span></span>
              </div>
            );
          })}
        </div>
        {coachVoice === "heavy" ? (
          <p className="mt-4 coach-note text-[13.5px] leading-[1.5]">
            80/20 holds — 80% of the miles at easy or long, 20% at the sharp
            end. That&rsquo;s the right shape for week 9.
          </p>
        ) : null}
      </div>
    </article>
  );
}

function FigHRZones({ coachVoice }) {
  const total = HR_ZONES.reduce((s, z) => s + z.curr, 0);
  const max = Math.max(...HR_ZONES.map((z) => Math.max(z.curr, z.prior)));
  return (
    <article className="fig-card">
      <FigHeader id="D" title="HR zones · current vs. prior 4 wk" right="MIN / WK AVG" />
      <div className="mt-5 border border-divider rounded-lg bg-bg-card p-6">
        <div className="flex items-baseline justify-between">
          <Mono>MINUTES IN ZONE</Mono>
          <Mono>{total} MIN · TOTAL</Mono>
        </div>
        <div className="mt-3 space-y-3">
          {HR_ZONES.map((z) => {
            const cw = (z.curr / max) * 100;
            const pw = (z.prior / max) * 100;
            const delta = z.curr - z.prior;
            return (
              <div key={z.z} className="grid grid-cols-[64px_1fr_56px] items-center gap-x-3">
                <div>
                  <p className="font-mono text-[11px] tracking-[1.4px] uppercase" style={{ color: z.color, fontWeight: 600 }}>{z.z}</p>
                  <p className="font-mono text-[9px] tracking-[1.2px] uppercase text-text-tertiary">{z.range}</p>
                </div>
                <div>
                  <p className="font-display text-[13px] tracking-[-0.005em] text-text-secondary">{z.name}</p>
                  <div className="mt-1 relative h-[14px]">
                    <div className="absolute inset-y-[5px] left-0 rounded-[1px]" style={{ width: `${pw}%`, background: INK, opacity: 0.12 }} />
                    <div className="absolute inset-y-0 left-0 rounded-[1px]" style={{ width: `${cw}%`, background: z.color, opacity: 0.9 }} />
                  </div>
                </div>
                <p className="font-mono text-[12px] tabular-nums text-right text-text-primary">{z.curr}<span className="ml-0.5 text-[8.5px] tracking-[1.2px] uppercase text-text-tertiary">m</span>
                  {Math.abs(delta) >= 4 ? (
                    <span className="block text-[9px]" style={{ color: delta > 0 ? "#2D8A4E" : "#C45A3A" }}>
                      {delta > 0 ? "↑" : "↓"}{Math.abs(delta)}
                    </span>
                  ) : null}
                </p>
              </div>
            );
          })}
        </div>
        {coachVoice === "heavy" ? (
          <p className="mt-5 coach-note text-[13.5px] leading-[1.5]">
            Threshold and Z4 time both up — that&rsquo;s the tempo block doing
            its work. Z1 down is fine; recovery runs need to be easy, not slow.
          </p>
        ) : null}
      </div>
    </article>
  );
}

/* ════════════════════════════════════════════════════════════════════
   FIG. E — Race readiness · predicted finish over the block
   ════════════════════════════════════════════════════════════════════ */
function FigRaceReadiness({ coachVoice }) {
  return (
    <section>
      <FigHeader id="E" title="Race readiness · predicted marathon finish" right="VDOT MODEL · ±2:00 BAND" />
      <div className="mt-5 border border-divider rounded-lg bg-bg-card p-6 fig-card">
        <ReadinessChart />
        <div className="mt-5 pt-4 border-t border-divider-soft grid grid-cols-3 gap-x-4">
          <div>
            <Mono>GOAL</Mono>
            <p className="mt-1 font-display text-[28px] tabular-nums tracking-[-0.01em]">{fmtTime(GOAL_TIME)}</p>
            <p className="font-mono text-[9.5px] tracking-[1.3px] uppercase text-text-tertiary">SUB-3:15 · BOSTON</p>
          </div>
          <div>
            <Mono color={ACCENT}>CURRENT FITNESS</Mono>
            <p className="mt-1 font-display text-[28px] tabular-nums tracking-[-0.01em]" style={{ color: ACCENT }}>{fmtTime(READINESS[READINESS.length - 1].pred)}</p>
            <p className="font-mono text-[9.5px] tracking-[1.3px] uppercase text-text-tertiary">↑ 0:24 SINCE WK 1</p>
          </div>
          <div>
            <Mono>GAP TO GOAL</Mono>
            <p className="mt-1 font-display text-[28px] tabular-nums tracking-[-0.01em]" style={{ color: "#2D8A4E" }}>
              −{fmtTime(GOAL_TIME - READINESS[READINESS.length - 1].pred)}
            </p>
            <p className="font-mono text-[9.5px] tracking-[1.3px] uppercase text-text-tertiary">UNDER · 7 WK OUT</p>
          </div>
        </div>
        {coachVoice === "heavy" ? (
          <p className="mt-5 coach-note text-[14px] leading-[1.5]">
            The model has you under goal by seven minutes, but the model
            doesn&rsquo;t run the race — the band is honest about that. The
            point of the next four weeks isn&rsquo;t to push the prediction
            further down; it&rsquo;s to make sure you arrive ready to hold it.
          </p>
        ) : (
          <p className="mt-5 font-body italic text-[13px] text-text-secondary">
            Curve has flattened the past two weeks — typical pre-taper plateau.
            The next gain is in the rest, not the work.
          </p>
        )}
      </div>
    </section>
  );
}

function ReadinessChart() {
  const W = 960, H = 280;
  const padL = 56, padR = 24, padT = 24, padB = 44;
  const innerW = W - padL - padR;
  const innerH = H - padT - padB;
  const yMin = 3.10, yMax = 3.55; // 3:06 to 3:33
  const xStep = innerW / Math.max(1, READINESS.length - 1);

  const yFor = (h) => padT + ((h - yMin) / (yMax - yMin)) * innerH;
  const xFor = (i) => padL + i * xStep;

  const linePts = READINESS.map((r, i) => [xFor(i), yFor(r.pred)]);
  const upperD = "M " + READINESS.map((r, i) => `${xFor(i)},${yFor(r.hi)}`).join(" L ");
  const lowerD = READINESS.slice().reverse().map((r, i) => `${xFor(READINESS.length - 1 - i)},${yFor(r.lo)}`).join(" L ");
  const bandD = `${upperD} L ${lowerD} Z`;

  const goalY = yFor(GOAL_TIME);
  const yTicks = [3.10, 3.20, 3.30, 3.40, 3.50];

  return (
    <svg viewBox={`0 0 ${W} ${H}`} className="w-full h-auto block">
      {/* y grid */}
      {yTicks.map((t) => {
        const y = yFor(t);
        return (
          <g key={t}>
            <line x1={padL} x2={W - padR} y1={y} y2={y} stroke="#E8E4E0" strokeDasharray="2 4" strokeWidth="1" />
            <text x={padL - 10} y={y + 3.5} textAnchor="end" fontFamily="ui-monospace, Menlo, monospace" fontSize="9.5" letterSpacing="1.2" fill={INK3}>
              {fmtTime(t)}
            </text>
          </g>
        );
      })}

      {/* goal line */}
      <line x1={padL} x2={W - padR} y1={goalY} y2={goalY} stroke={ACCENT} strokeWidth="1.2" strokeDasharray="6 4" opacity="0.7" />
      <text x={W - padR} y={goalY - 6} textAnchor="end" fontFamily="ui-monospace, Menlo, monospace" fontSize="9.5" letterSpacing="1.3" fill={ACCENT} fontWeight={600}>
        GOAL · {fmtTime(GOAL_TIME)}
      </text>

      {/* confidence band */}
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
      {READINESS.map((r, i) => (
        <g key={r.wk}>
          <circle cx={linePts[i][0]} cy={linePts[i][1]} r={r.current ? 5.5 : 3} fill={r.current ? ACCENT : INK} />
          {r.current ? (
            <text x={linePts[i][0]} y={linePts[i][1] - 14} textAnchor="middle" fontFamily="ui-monospace, Menlo, monospace" fontSize="10.5" letterSpacing="1.2" fill={ACCENT} fontWeight={700}>
              {fmtTime(r.pred)}
            </text>
          ) : null}
        </g>
      ))}

      {/* x labels */}
      {READINESS.map((r, i) => (
        <text
          key={r.wk}
          x={xFor(i)}
          y={H - 22}
          textAnchor="middle"
          fontFamily="ui-monospace, Menlo, monospace"
          fontSize="9"
          letterSpacing="1.2"
          fill={r.current ? ACCENT : INK3}
          fontWeight={r.current ? 700 : 500}
        >
          {r.wk}
        </text>
      ))}
      <text x={padL - 10} y={padT - 8} textAnchor="end" fontFamily="ui-monospace, Menlo, monospace" fontSize="9" letterSpacing="1.3" fill={INK3}>
        FINISH
      </text>
      <text x={W - padR} y={H - 6} textAnchor="end" fontFamily="ui-monospace, Menlo, monospace" fontSize="9" letterSpacing="1.3" fill={INK3}>
        BOSTON · JUL 12
      </text>
    </svg>
  );
}

/* ════════════════════════════════════════════════════════════════════
   COACH BLOCK READ — long-form narrative
   ════════════════════════════════════════════════════════════════════ */
function BlockRead() {
  return (
    <section className="relative">
      <div className="editorial-rule mb-8">
        <span className="editorial-rule__dot" />
      </div>
      <div className="grid lg:grid-cols-[180px_1fr] gap-x-10">
        <div>
          <Mono color={ACCENT}>FROM YOUR COACH</Mono>
          <p className="mt-2 font-mono text-[10px] tracking-[1.3px] uppercase text-text-tertiary">
            BLOCK READ · WK 9 OF 16
          </p>
          <p className="mt-1 font-mono text-[10px] tracking-[1.3px] uppercase text-text-tertiary">
            AUTO-GENERATED · COACH-REVIEWED
          </p>
        </div>
        <div className="max-w-[640px]">
          <p className="font-body text-[18px] leading-[1.65] text-text-primary">
            Eight weeks of work and the picture is honest. The fitness curve
            is climbing — six points since week 1 — and the predicted finish
            has come down a full half-minute. The Apr 13 jump to forty-eight
            was the inflection; everything since has been confirming, not
            chasing.
          </p>
          <p className="mt-4 font-body text-[16px] leading-[1.65] text-text-primary">
            Two things worth saying out loud. First: the deload weeks are
            doing what they&rsquo;re supposed to. Both wk 4 and wk 7 came
            down a third in volume and the next week opened the legs back
            up. That&rsquo;s the right rhythm — don&rsquo;t skip the next one.
          </p>
          <p className="mt-4 font-body text-[16px] leading-[1.65] text-text-primary">
            Second: the tempo on Tuesday was the cleanest fast running of
            the block. Four reps inside the 7:00 window and the last one
            giving back five seconds is discipline, not fade. That tells me
            the engine is bigger than the pace card we&rsquo;ve been
            running off. We can talk about adjusting the goal window after
            Saturday&rsquo;s long.
          </p>
          <p className="mt-4 font-body italic text-[15px] leading-[1.6] text-text-secondary">
            What I don&rsquo;t want you to do with this read is push harder.
            The next gain is in the recovery, not the work. Hold the line.
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
   WHAT CHANGED — three observations
   ════════════════════════════════════════════════════════════════════ */
function WhatChanged() {
  const items = [
    {
      delta: "↑ 8 sec",
      label: "AVG EASY PACE",
      body: "Easy miles are coming in at 8:32 instead of 8:40 — same heart rate, same effort. Aerobic efficiency.",
      accent: true,
    },
    {
      delta: "↑ 14 min",
      label: "Z3 / Z4 TIME",
      body: "Tempo and threshold minutes are up week-over-week. The sharp end is finally getting reps.",
      accent: false,
    },
    {
      delta: "− 6 bpm",
      label: "HR DRIFT · LONG RUNS",
      body: "Cardiac drift on the long is down — fewer bpm gained between mile 4 and mile 14. Cardio fitness, plainly.",
      accent: false,
    },
  ];
  return (
    <section>
      <FigHeader id="F" title="What changed, in three lines" right="VS. PRIOR 4 WK" />
      <div className="mt-5 grid lg:grid-cols-3 gap-6">
        {items.map((it) => (
          <article key={it.label} className="border border-divider bg-bg-card rounded-lg p-6 fig-card">
            <Mono color={it.accent ? ACCENT : INK3}>{it.label}</Mono>
            <p className="mt-2 font-display text-[40px] leading-none tracking-[-0.02em] tabular-nums" style={{ color: it.accent ? ACCENT : INK }}>
              {it.delta}
            </p>
            <p className="mt-3 font-body text-[14px] leading-[1.55] text-text-secondary">
              {it.body}
            </p>
          </article>
        ))}
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

function LegendDot({ color, label, dashed, borderColor }) {
  return (
    <span className="inline-flex items-center gap-2">
      <span
        className="block h-[10px] w-[10px] rounded-[1px]"
        style={{
          background: color,
          border: dashed ? `1px dashed ${borderColor || color}` : "none",
        }}
      />
      <span className="font-mono text-[10px] tracking-[1.3px] uppercase text-text-secondary">
        {label}
      </span>
    </span>
  );
}

function Footer() {
  return (
    <div className="mt-8 pt-6 border-t border-divider-soft flex items-center justify-between">
      <Mono>POST RUN DRIP · TRAINING ANALYSIS</Mono>
      <Mono>BLOCK READ · SPRING ’26</Mono>
    </div>
  );
}

/* ── mount ──────────────────────────────────────────────────────── */
const root = ReactDOM.createRoot(document.getElementById("root"));
root.render(<App />);

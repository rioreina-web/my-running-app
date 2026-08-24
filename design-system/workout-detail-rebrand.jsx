/* global React, Eyebrow, Hairline */
/* ════════════════════════════════════════════════════════════════════
   WORKOUT DETAIL · BRAND REBRAND (v2 — chart-heavy)
   Same three directions, now with proper data-viz density.

   Shared chart kit:
   • HRZonedChart        — HR over time, faint zone bands, avg line
   • PaceOverTimeChart   — smoothed pace trace, dashed avg, negative-split shading
   • CadenceChart        — cadence over time (spm)
   • ElevationProfile    — thin shaded elevation strip
   • HRPaceScatter       — efficiency plot, dots by mile, regression
   • HRDriftChart        — decoupling (Pa:HR), first vs second half
   • MileSparklines      — small-multiples grid, one HR sparkline per mile
   • TimeInZoneBar       — stacked horizontal HR-zone bar
   • TimeInPaceBar       — stacked horizontal pace-zone bar
   • SplitsTable         — splits as a hairline table with bar + pace + HR
   • HRRecoveryArc       — post-finish HR drop in first 60s
   • ComparisonBars      — this run vs 4-week average (multi-metric)
   • RoutePlaceholder    — desaturated route stand-in
   ════════════════════════════════════════════════════════════════════ */

const { useMemo } = React;

/* ─── fixture data (matches the Thursday screenshot) ─────────────── */

const WD_TOTALS = {
  date: "Thursday",
  fullDate: "May 21, 2026",
  source: "Strava",
  distMi: 6.90,
  timeText: "51:06",
  durationSec: 51 * 60 + 6,
  avgPace: "7:24",
  avgPaceSec: 444,
  avgHr: 143,
  maxHr: 157,
  minHr: 91,
  elevFt: 141,
  fastestSplit: "7:13",
  slowestSplit: "8:02",
  avgCadence: 174,
  avgPower: 248,
};

const WD_SPLITS = [
  { i: 1, mi: 1.00, pace: "8:02", paceSec: 482, hr: 129, cad: 168 },
  { i: 2, mi: 1.00, pace: "7:23", paceSec: 443, hr: 141, cad: 173 },
  { i: 3, mi: 1.00, pace: "7:13", paceSec: 433, hr: 145, cad: 175 },
  { i: 4, mi: 1.00, pace: "7:14", paceSec: 434, hr: 146, cad: 175 },
  { i: 5, mi: 1.00, pace: "7:13", paceSec: 433, hr: 148, cad: 176 },
  { i: 6, mi: 1.00, pace: "7:25", paceSec: 445, hr: 147, cad: 174 },
  { i: 7, mi: 0.90, pace: "7:17", paceSec: 437, hr: 149, cad: 176 },
];

/* ~96 evenly-spaced samples across the run */
const WD_HR = [
  91, 96, 102, 110, 118, 125, 130, 134, 137, 139, 141, 142,
  143, 142, 140, 138, 135, 130, 121, 113, 120, 130, 138, 142,
  144, 146, 148, 150, 152, 151, 149, 148, 150, 153, 155, 157,
  156, 154, 152, 150, 148, 147, 146, 148, 150, 151, 149, 147,
  145, 144, 145, 147, 149, 151, 153, 156, 157, 155, 152, 150,
  148, 145, 144, 145, 147, 149, 151, 153, 156, 157, 155, 153,
  150, 148, 146, 144, 143, 142, 141, 140, 140, 141, 142, 142,
  141, 140, 142, 143, 142, 138, 132, 124, 116, 108, 102, 96,
];

const WD_PACE = [
  /* Pace in sec/mi, mirrors warmup then settle then steady */
  540, 522, 508, 495, 485, 480, 478, 476, 472, 468, 462, 458,
  454, 450, 448, 444, 442, 440, 446, 462, 458, 452, 446, 442,
  438, 436, 434, 432, 430, 432, 434, 436, 434, 432, 430, 428,
  430, 432, 434, 436, 438, 440, 438, 436, 434, 432, 430, 432,
  434, 436, 438, 440, 438, 436, 434, 432, 430, 432, 434, 436,
  438, 440, 442, 440, 438, 436, 434, 432, 430, 428, 430, 432,
  434, 436, 438, 440, 442, 444, 442, 440, 438, 436, 434, 432,
  430, 432, 434, 436, 438, 440, 446, 458, 472, 488, 510, 540,
];

const WD_CADENCE = [
  155, 162, 168, 170, 171, 172, 173, 173, 174, 174, 174, 174,
  175, 175, 175, 175, 174, 173, 170, 168, 170, 173, 175, 175,
  176, 176, 176, 176, 177, 176, 175, 175, 176, 176, 177, 177,
  176, 176, 175, 175, 175, 175, 175, 175, 176, 176, 175, 175,
  175, 175, 175, 176, 176, 176, 176, 177, 177, 176, 175, 175,
  175, 175, 175, 175, 175, 175, 176, 176, 176, 177, 177, 176,
  175, 175, 175, 175, 175, 175, 175, 175, 175, 175, 175, 175,
  175, 175, 175, 175, 175, 173, 170, 166, 162, 158, 154, 150,
];

const WD_ELEV = [
  10, 12, 14, 18, 22, 28, 34, 42, 48, 55, 60, 66,
  68, 70, 72, 74, 75, 73, 70, 68, 65, 62, 60, 58,
  56, 54, 52, 50, 48, 46, 44, 42, 40, 42, 44, 48,
  52, 56, 60, 62, 64, 65, 65, 64, 62, 60, 58, 55,
  52, 50, 48, 48, 50, 52, 54, 56, 58, 60, 62, 64,
  66, 64, 60, 56, 52, 48, 44, 40, 38, 36, 34, 32,
  30, 30, 32, 34, 36, 38, 40, 42, 40, 38, 36, 34,
  30, 26, 22, 18, 16, 14, 12, 10, 8, 6, 4, 2,
];

/* recovery — 90 seconds after finish */
const WD_RECOVERY = [
  149, 144, 138, 132, 126, 120, 116, 113, 110, 108, 105, 102,
  100, 98, 96, 94, 92, 90, 88, 86, 84, 82, 80, 78,
  76, 74, 73, 72, 71, 70,
];

const WD_ZONES = [
  { id: "Z1", name: "Recovery",   lo: 0,   hi: 124, color: "var(--ink-3)" },
  { id: "Z2", name: "Aerobic",    lo: 124, hi: 138, color: "var(--mood-positive)" },
  { id: "Z3", name: "Tempo",      lo: 138, hi: 152, color: "var(--coral)" },
  { id: "Z4", name: "Threshold",  lo: 152, hi: 165, color: "var(--mood-tired)" },
  { id: "Z5", name: "VO2",        lo: 165, hi: 200, color: "var(--mood-struggling)" },
];
const WD_TIZ = { Z1: 92, Z2: 312, Z3: 1856, Z4: 806, Z5: 0 };

const WD_PACE_ZONES = [
  { id: "P1", name: "Long",   lo: 540, hi: 999, color: "var(--ink-3)" },
  { id: "P2", name: "Easy",   lo: 480, hi: 540, color: "var(--mood-positive)" },
  { id: "P3", name: "Steady", lo: 440, hi: 480, color: "var(--mood-energized)" },
  { id: "P4", name: "Tempo",  lo: 420, hi: 440, color: "var(--coral)" },
  { id: "P5", name: "Thresh", lo: 0,   hi: 420, color: "var(--mood-tired)" },
];
const WD_TIP = { P1: 60, P2: 230, P3: 720, P4: 1880, P5: 176 };

/* recent 4-week averages — for comparison bars */
const WD_RECENT_AVG = {
  hr: 138, pace: 458, cadence: 172, distMi: 5.4,
};

/* ─── style tokens ───────────────────────────────────────────────── */

const wdStyles = {
  mono: { fontFamily: "var(--font-mono)", fontVariantNumeric: "tabular-nums" },
  eyebrow: {
    fontFamily: "var(--font-mono)", fontSize: 10, fontWeight: 500,
    letterSpacing: "0.14em", textTransform: "uppercase", color: "var(--ink-2)",
  },
  eyebrowSm: {
    fontFamily: "var(--font-mono)", fontSize: 9, fontWeight: 500,
    letterSpacing: "0.12em", textTransform: "uppercase", color: "var(--ink-3)",
  },
  italic: {
    fontFamily: "var(--font-body)", fontStyle: "italic",
    color: "var(--ink-2)", lineHeight: 1.5,
  },
};

/* ─── helpers ────────────────────────────────────────────────────── */

const fmtPace = (s) => {
  const m = Math.floor(s / 60), ss = Math.round(s) % 60;
  return `${m}:${String(ss).padStart(2, "0")}`;
};
const fmtMin = (s) => {
  const m = Math.floor(s / 60), ss = Math.round(s) % 60;
  return `${m}:${String(ss).padStart(2, "0")}`;
};

/* ─── Plate strip ────────────────────────────────────────────────── */

function WDPlate({ surface, fig, right }) {
  return (
    <div style={{
      display: "flex", justifyContent: "space-between",
      padding: "14px 24px 0 24px",
    }}>
      <div style={{ display: "flex", flexDirection: "column", gap: 2 }}>
        <span style={{ ...wdStyles.eyebrow, color: "var(--ink)" }}>RUNNING LOG</span>
        <span style={wdStyles.eyebrow}>— {surface}</span>
      </div>
      <div style={{ display: "flex", flexDirection: "column", gap: 2, textAlign: "right" }}>
        {fig && <span style={{ ...wdStyles.eyebrow, color: "var(--ink)" }}>{fig}</span>}
        <span style={wdStyles.eyebrow}>{right}</span>
      </div>
    </div>
  );
}

/* ════════════════════════════════════════════════════════════════════
   CHART KIT
   ════════════════════════════════════════════════════════════════════ */

/* HR over time — faint zone bands + dashed avg */
function HRZonedChart({
  data = WD_HR, zones = WD_ZONES, height = 140,
  showZoneBands = true, showAvg = true, showYAxis = true, annotations = [],
}) {
  const W = 320, H = height;
  const PAD_L = showYAxis ? 28 : 6, PAD_R = 6, PAD_T = 8, PAD_B = 6;
  const plotW = W - PAD_L - PAD_R, plotH = H - PAD_T - PAD_B;
  const yMin = 80, yMax = 180;
  const yScale = (v) => PAD_T + plotH - ((v - yMin) / (yMax - yMin)) * plotH;
  const xScale = (i) => PAD_L + (i / (data.length - 1)) * plotW;
  const path = data.map((v, i) => `${i === 0 ? "M" : "L"} ${xScale(i).toFixed(1)} ${yScale(v).toFixed(1)}`).join(" ");
  const avg = data.reduce((s, v) => s + v, 0) / data.length;
  return (
    <svg viewBox={`0 0 ${W} ${H}`} preserveAspectRatio="none" style={{ width: "100%", height, display: "block" }}>
      {showZoneBands && zones.map(z => {
        if (!z.isPrimary && z.id !== "Z3") return null;
        const top = yScale(Math.min(z.hi, yMax));
        const bot = yScale(Math.max(z.lo, yMin));
        return <rect key={z.id} x={PAD_L} y={top} width={plotW} height={bot - top} fill="rgba(212,89,42,0.06)" />;
      })}
      {showZoneBands && zones.slice(0, -1).map(z => (
        <line key={z.id} x1={PAD_L} x2={PAD_L + plotW}
          y1={yScale(z.hi)} y2={yScale(z.hi)} stroke="var(--rule)" strokeWidth="0.5" />
      ))}
      {showYAxis && [100, 120, 140, 160].map(v => (
        <text key={v} x={PAD_L - 6} y={yScale(v) + 3} textAnchor="end"
          fontFamily="var(--font-mono)" fontSize="8" fill="var(--ink-3)">{v}</text>
      ))}
      {showAvg && (
        <g>
          <line x1={PAD_L} x2={PAD_L + plotW} y1={yScale(avg)} y2={yScale(avg)}
            stroke="var(--coral)" strokeWidth="0.75" strokeDasharray="3 3" opacity="0.6" />
          <text x={PAD_L + plotW - 4} y={yScale(avg) - 4} textAnchor="end"
            fontFamily="var(--font-mono)" fontSize="8" fill="var(--coral)" letterSpacing="0.10em">
            AVG {Math.round(avg)}
          </text>
        </g>
      )}
      <path d={path} fill="none" stroke="var(--coral)" strokeWidth="1.4"
        strokeLinecap="round" strokeLinejoin="round" />
      {annotations.map((a, idx) => {
        const x = xScale(a.i), y = yScale(data[a.i] || avg);
        return (
          <g key={idx}>
            <line x1={x} x2={x} y1={y - 6} y2={PAD_T + 14} stroke="var(--ink-2)" strokeWidth="0.5" />
            <circle cx={x} cy={y} r="2" fill="var(--ink)" />
            <text x={x} y={PAD_T + 10} textAnchor={a.anchor || "middle"}
              fontFamily="var(--font-mono)" fontSize="8" fill="var(--ink)" letterSpacing="0.08em">
              {a.label}
            </text>
          </g>
        );
      })}
    </svg>
  );
}

/* Pace over time — smoothed, dashed avg, optional negative-split shading */
function PaceOverTimeChart({ data = WD_PACE, height = 110, showSplit = false }) {
  const W = 320, H = height;
  const PAD_L = 30, PAD_R = 6, PAD_T = 8, PAD_B = 6;
  const plotW = W - PAD_L - PAD_R, plotH = H - PAD_T - PAD_B;
  // pace inverted — faster is up
  const min = 410, max = 560;
  const yScale = (v) => PAD_T + ((v - min) / (max - min)) * plotH;
  const xScale = (i) => PAD_L + (i / (data.length - 1)) * plotW;
  const path = data.map((v, i) => `${i === 0 ? "M" : "L"} ${xScale(i).toFixed(1)} ${yScale(v).toFixed(1)}`).join(" ");
  const area = `${path} L ${xScale(data.length - 1).toFixed(1)} ${PAD_T + plotH} L ${PAD_L} ${PAD_T + plotH} Z`;
  const avg = data.reduce((s, v) => s + v, 0) / data.length;
  const half = Math.floor(data.length / 2);
  const firstAvg = data.slice(0, half).reduce((s,v)=>s+v,0)/half;
  const secondAvg = data.slice(half).reduce((s,v)=>s+v,0)/(data.length-half);

  return (
    <svg viewBox={`0 0 ${W} ${H}`} preserveAspectRatio="none" style={{ width: "100%", height, display: "block" }}>
      {/* y axis */}
      {[7*60, 7*60+30, 8*60, 8*60+30].map(v => (
        <g key={v}>
          <line x1={PAD_L} x2={PAD_L + plotW} y1={yScale(v)} y2={yScale(v)}
            stroke="var(--rule)" strokeWidth="0.5" />
          <text x={PAD_L - 6} y={yScale(v) + 3} textAnchor="end"
            fontFamily="var(--font-mono)" fontSize="8" fill="var(--ink-3)">{fmtPace(v)}</text>
        </g>
      ))}
      {showSplit && (
        <>
          <rect x={PAD_L} y={PAD_T} width={plotW * 0.5} height={plotH} fill="var(--ink-3)" opacity="0.05" />
          <line x1={PAD_L + plotW * 0.5} x2={PAD_L + plotW * 0.5}
            y1={PAD_T} y2={PAD_T + plotH} stroke="var(--ink-2)" strokeWidth="0.5" strokeDasharray="2 2" />
          <text x={PAD_L + 4} y={PAD_T + 10}
            fontFamily="var(--font-mono)" fontSize="8" fill="var(--ink-3)" letterSpacing="0.08em">1st HALF · {fmtPace(firstAvg)}</text>
          <text x={PAD_L + plotW - 4} y={PAD_T + 10} textAnchor="end"
            fontFamily="var(--font-mono)" fontSize="8" fill="var(--coral)" letterSpacing="0.08em">2nd HALF · {fmtPace(secondAvg)}</text>
        </>
      )}
      <path d={area} fill="var(--ink)" opacity="0.04" />
      <line x1={PAD_L} x2={PAD_L + plotW} y1={yScale(avg)} y2={yScale(avg)}
        stroke="var(--ink-2)" strokeWidth="0.75" strokeDasharray="3 3" opacity="0.7" />
      <text x={PAD_L + plotW - 4} y={yScale(avg) - 4} textAnchor="end"
        fontFamily="var(--font-mono)" fontSize="8" fill="var(--ink-2)" letterSpacing="0.10em">
        AVG {fmtPace(avg)}
      </text>
      <path d={path} fill="none" stroke="var(--ink)" strokeWidth="1.4"
        strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

/* Cadence — simple line + avg */
function CadenceChart({ data = WD_CADENCE, height = 60 }) {
  const W = 320, H = height;
  const PAD = 6;
  const plotW = W - PAD * 2, plotH = H - PAD * 2;
  const min = 150, max = 185;
  const xScale = (i) => PAD + (i / (data.length - 1)) * plotW;
  const yScale = (v) => PAD + plotH - ((v - min) / (max - min)) * plotH;
  const path = data.map((v, i) => `${i === 0 ? "M" : "L"} ${xScale(i).toFixed(1)} ${yScale(v).toFixed(1)}`).join(" ");
  const avg = data.reduce((s, v) => s + v, 0) / data.length;
  return (
    <svg viewBox={`0 0 ${W} ${H}`} preserveAspectRatio="none" style={{ width: "100%", height, display: "block" }}>
      <line x1={PAD} x2={PAD + plotW} y1={yScale(avg)} y2={yScale(avg)}
        stroke="var(--ink-2)" strokeWidth="0.6" strokeDasharray="3 3" opacity="0.5" />
      <path d={path} fill="none" stroke="var(--ink-2)" strokeWidth="1.1" opacity="0.85"
        strokeLinecap="round" strokeLinejoin="round" />
      <text x={W - PAD - 4} y={yScale(avg) - 3} textAnchor="end"
        fontFamily="var(--font-mono)" fontSize="8" fill="var(--ink-2)" letterSpacing="0.10em">
        AVG {Math.round(avg)}
      </text>
    </svg>
  );
}

/* Elevation profile */
function ElevationProfile({ data = WD_ELEV, height = 50 }) {
  const W = 320, H = height, P = 4;
  const plotW = W - P * 2, plotH = H - P * 2;
  const max = Math.max(...data), min = Math.min(...data);
  const x = (i) => P + (i / (data.length - 1)) * plotW;
  const y = (v) => P + plotH - ((v - min) / (max - min || 1)) * plotH;
  const path = data.map((v, i) => `${i === 0 ? "M" : "L"} ${x(i).toFixed(1)} ${y(v).toFixed(1)}`).join(" ");
  const area = `${path} L ${x(data.length - 1).toFixed(1)} ${P + plotH} L ${x(0).toFixed(1)} ${P + plotH} Z`;
  return (
    <svg viewBox={`0 0 ${W} ${H}`} preserveAspectRatio="none" style={{ width: "100%", height, display: "block" }}>
      <path d={area} fill="var(--ink)" opacity="0.08" />
      <path d={path} fill="none" stroke="var(--ink)" strokeWidth="1" opacity="0.55" />
    </svg>
  );
}

/* HR vs Pace scatter — efficiency plot, dots colored by mile */
function HRPaceScatter({ height = 200 }) {
  const W = 320, H = height;
  const PAD_L = 32, PAD_R = 12, PAD_T = 12, PAD_B = 24;
  const plotW = W - PAD_L - PAD_R, plotH = H - PAD_T - PAD_B;
  const hrMin = 110, hrMax = 165;
  const paceMin = 420, paceMax = 510;
  // Build per-sample dots — pair HR[i] with PACE[i]
  const dots = WD_HR.map((hr, i) => ({
    hr, pace: WD_PACE[i] || WD_TOTALS.avgPaceSec,
    mile: Math.min(WD_SPLITS.length, Math.floor(i / (WD_HR.length / WD_SPLITS.length)) + 1),
  }));
  const xScale = (p) => PAD_L + ((paceMax - p) / (paceMax - paceMin)) * plotW;
  const yScale = (h) => PAD_T + plotH - ((h - hrMin) / (hrMax - hrMin)) * plotH;
  // Regression: simple linear fit
  const n = dots.length;
  const meanX = dots.reduce((s, d) => s + d.pace, 0) / n;
  const meanY = dots.reduce((s, d) => s + d.hr, 0) / n;
  const num = dots.reduce((s, d) => s + (d.pace - meanX) * (d.hr - meanY), 0);
  const den = dots.reduce((s, d) => s + Math.pow(d.pace - meanX, 2), 0);
  const slope = num / den, intercept = meanY - slope * meanX;
  const line = (p) => slope * p + intercept;

  return (
    <svg viewBox={`0 0 ${W} ${H}`} style={{ width: "100%", height, display: "block" }}>
      {/* axes */}
      <line x1={PAD_L} x2={PAD_L + plotW} y1={PAD_T + plotH} y2={PAD_T + plotH} stroke="var(--rule)" strokeWidth="0.6" />
      <line x1={PAD_L} x2={PAD_L} y1={PAD_T} y2={PAD_T + plotH} stroke="var(--rule)" strokeWidth="0.6" />
      {/* y ticks */}
      {[120, 130, 140, 150, 160].map(v => (
        <g key={v}>
          <line x1={PAD_L} x2={PAD_L + plotW} y1={yScale(v)} y2={yScale(v)} stroke="var(--rule)" strokeWidth="0.4" />
          <text x={PAD_L - 6} y={yScale(v) + 3} textAnchor="end"
            fontFamily="var(--font-mono)" fontSize="8" fill="var(--ink-3)">{v}</text>
        </g>
      ))}
      {/* x ticks */}
      {[8*60, 7*60+30, 7*60].map(v => (
        <g key={v}>
          <text x={xScale(v)} y={PAD_T + plotH + 12} textAnchor="middle"
            fontFamily="var(--font-mono)" fontSize="8" fill="var(--ink-3)">{fmtPace(v)}</text>
        </g>
      ))}
      {/* axis labels */}
      <text x={PAD_L - 22} y={PAD_T + plotH / 2} textAnchor="middle"
        transform={`rotate(-90 ${PAD_L - 22} ${PAD_T + plotH / 2})`}
        fontFamily="var(--font-mono)" fontSize="8" fill="var(--ink-3)" letterSpacing="0.10em">HEART RATE</text>
      <text x={PAD_L + plotW / 2} y={H - 4} textAnchor="middle"
        fontFamily="var(--font-mono)" fontSize="8" fill="var(--ink-3)" letterSpacing="0.10em">PACE (faster →)</text>
      {/* regression line */}
      <line
        x1={xScale(paceMin)} y1={yScale(line(paceMin))}
        x2={xScale(paceMax)} y2={yScale(line(paceMax))}
        stroke="var(--coral)" strokeWidth="0.8" strokeDasharray="3 3" opacity="0.7"
      />
      {/* dots */}
      {dots.map((d, i) => (
        <circle key={i} cx={xScale(d.pace)} cy={yScale(d.hr)} r="2"
          fill="var(--ink)" opacity={0.20 + (d.mile / 14)} />
      ))}
    </svg>
  );
}

/* HR drift / decoupling — first vs second half */
function HRDriftChart({ height = 120 }) {
  const W = 320, H = height;
  const PAD = 30;
  const half = Math.floor(WD_HR.length / 2);
  const firstHR  = WD_HR.slice(0, half).reduce((s,v)=>s+v,0)/half;
  const secondHR = WD_HR.slice(half).reduce((s,v)=>s+v,0)/(WD_HR.length-half);
  const firstPace  = WD_PACE.slice(0, half).reduce((s,v)=>s+v,0)/half;
  const secondPace = WD_PACE.slice(half).reduce((s,v)=>s+v,0)/(WD_PACE.length-half);
  const firstRatio  = firstPace / firstHR;
  const secondRatio = secondPace / secondHR;
  const drift = ((secondRatio - firstRatio) / firstRatio) * 100; // %

  // Two side-by-side mini-bars
  const barH = 12, barY = 38, barSpacing = 56;
  return (
    <svg viewBox={`0 0 ${W} ${H}`} style={{ width: "100%", height, display: "block" }}>
      <text x={PAD} y={20} fontFamily="var(--font-mono)" fontSize="9" fill="var(--ink-3)" letterSpacing="0.12em">1st HALF</text>
      <text x={W - PAD} y={20} textAnchor="end" fontFamily="var(--font-mono)" fontSize="9" fill="var(--ink-3)" letterSpacing="0.12em">2nd HALF</text>

      {/* Pace bars */}
      <text x={PAD} y={barY - 4} fontFamily="var(--font-mono)" fontSize="8" fill="var(--ink-2)">PACE</text>
      <rect x={PAD} y={barY} width={120} height={barH} fill="var(--paper-deep)" />
      <rect x={PAD} y={barY} width={120 * (1 - (firstPace - 420) / 140)} height={barH} fill="var(--ink-2)" opacity="0.7" />
      <text x={PAD + 124} y={barY + barH - 2} fontFamily="var(--font-mono)" fontSize="10" fontWeight="600" fill="var(--ink)">{fmtPace(firstPace)}</text>

      <rect x={W - PAD - 120} y={barY} width={120} height={barH} fill="var(--paper-deep)" />
      <rect x={W - PAD - 120} y={barY} width={120 * (1 - (secondPace - 420) / 140)} height={barH} fill="var(--coral)" opacity="0.85" />
      <text x={W - PAD - 124} y={barY + barH - 2} textAnchor="end" fontFamily="var(--font-mono)" fontSize="10" fontWeight="600" fill="var(--coral)">{fmtPace(secondPace)}</text>

      {/* HR bars */}
      <text x={PAD} y={barY + barSpacing - 4} fontFamily="var(--font-mono)" fontSize="8" fill="var(--ink-2)">AVG HR</text>
      <rect x={PAD} y={barY + barSpacing} width={120} height={barH} fill="var(--paper-deep)" />
      <rect x={PAD} y={barY + barSpacing} width={120 * ((firstHR - 90) / 80)} height={barH} fill="var(--ink-2)" opacity="0.7" />
      <text x={PAD + 124} y={barY + barSpacing + barH - 2} fontFamily="var(--font-mono)" fontSize="10" fontWeight="600" fill="var(--ink)">{Math.round(firstHR)}</text>

      <rect x={W - PAD - 120} y={barY + barSpacing} width={120} height={barH} fill="var(--paper-deep)" />
      <rect x={W - PAD - 120} y={barY + barSpacing} width={120 * ((secondHR - 90) / 80)} height={barH} fill="var(--coral)" opacity="0.85" />
      <text x={W - PAD - 124} y={barY + barSpacing + barH - 2} textAnchor="end" fontFamily="var(--font-mono)" fontSize="10" fontWeight="600" fill="var(--coral)">{Math.round(secondHR)}</text>

      {/* Decoupling summary */}
      <text x={W / 2} y={H - 6} textAnchor="middle"
        fontFamily="var(--font-mono)" fontSize="9" fill={Math.abs(drift) < 5 ? "var(--mood-energized)" : "var(--coral)"} letterSpacing="0.10em">
        DECOUPLING · {drift > 0 ? "+" : ""}{drift.toFixed(1)}% · {Math.abs(drift) < 5 ? "AEROBIC" : "DRIFTING"}
      </text>
    </svg>
  );
}

/* Mile small-multiples — one mini HR chart per split */
function MileSparklines() {
  const samplesPerMile = Math.floor(WD_HR.length / WD_SPLITS.length);
  return (
    <div style={{
      display: "grid", gridTemplateColumns: "repeat(7, 1fr)",
      gap: 4, marginTop: 8,
    }}>
      {WD_SPLITS.map((s, idx) => {
        const start = idx * samplesPerMile;
        const slice = WD_HR.slice(start, start + samplesPerMile);
        const sMin = 100, sMax = 165;
        const W = 40, H = 36;
        const xs = slice.map((_, i) => (i / (slice.length - 1)) * W);
        const ys = slice.map(v => H - ((v - sMin) / (sMax - sMin)) * H);
        const path = slice.map((v, i) => `${i === 0 ? "M" : "L"} ${xs[i].toFixed(1)} ${ys[i].toFixed(1)}`).join(" ");
        const fastest = s.paceSec === Math.min(...WD_SPLITS.map(x => x.paceSec));
        return (
          <div key={s.i} style={{
            display: "flex", flexDirection: "column", alignItems: "center", gap: 2,
            paddingBottom: 4,
            borderBottom: "1px solid var(--rule)",
          }}>
            <span style={{ ...wdStyles.eyebrowSm, color: fastest ? "var(--coral)" : "var(--ink-3)", fontSize: 8 }}>{s.i}</span>
            <svg viewBox={`0 0 ${W} ${H}`} style={{ width: "100%", height: 28 }} preserveAspectRatio="none">
              <path d={path} fill="none" stroke={fastest ? "var(--coral)" : "var(--ink-2)"} strokeWidth="1.2"
                strokeLinecap="round" strokeLinejoin="round" />
            </svg>
            <span style={{ ...wdStyles.mono, fontSize: 10, fontWeight: 600,
              color: fastest ? "var(--coral)" : "var(--ink)" }}>{s.pace}</span>
            <span style={{ ...wdStyles.eyebrowSm, fontSize: 8, color: "var(--ink-3)" }}>{s.hr}</span>
          </div>
        );
      })}
    </div>
  );
}

/* Time in HR zone — stacked bar + legend grid */
function TimeInZoneBar({ data = WD_TIZ, zones = WD_ZONES }) {
  const total = Object.values(data).reduce((a, b) => a + b, 0);
  return (
    <div>
      <div style={{ display: "flex", height: 18, marginTop: 8, border: "1px solid var(--rule)" }}>
        {zones.map(z => {
          const v = data[z.id] || 0;
          const pct = (v / total) * 100;
          if (pct < 0.1) return null;
          const isMain = z.id === "Z3";
          return (
            <div key={z.id} style={{
              width: `${pct}%`, background: z.color, opacity: isMain ? 1 : 0.55,
              borderRight: "1px solid var(--paper)",
            }} />
          );
        })}
      </div>
      <div style={{ marginTop: 10, display: "grid", gridTemplateColumns: "repeat(5, 1fr)", gap: 8 }}>
        {zones.map(z => {
          const v = data[z.id] || 0;
          const pct = (v / total) * 100;
          const isMain = z.id === "Z3";
          return (
            <div key={z.id} style={{ display: "flex", flexDirection: "column", gap: 3 }}>
              <div style={{ display: "flex", alignItems: "center", gap: 5 }}>
                <span style={{ width: 6, height: 6, background: z.color, opacity: isMain ? 1 : 0.55 }} />
                <span style={{ ...wdStyles.eyebrowSm, color: isMain ? "var(--ink)" : "var(--ink-3)" }}>{z.id}</span>
              </div>
              <span style={{ ...wdStyles.mono, fontSize: 13, fontWeight: 600,
                color: isMain ? "var(--coral)" : "var(--ink-2)" }}>{fmtMin(v)}</span>
              <span style={{ ...wdStyles.eyebrowSm, fontSize: 8 }}>{Math.round(pct)}%</span>
            </div>
          );
        })}
      </div>
    </div>
  );
}

/* Time in pace zone — same shape, different data */
function TimeInPaceBar({ data = WD_TIP, zones = WD_PACE_ZONES }) {
  const total = Object.values(data).reduce((a, b) => a + b, 0);
  return (
    <div>
      <div style={{ display: "flex", height: 18, marginTop: 8, border: "1px solid var(--rule)" }}>
        {zones.map(z => {
          const v = data[z.id] || 0;
          const pct = (v / total) * 100;
          if (pct < 0.1) return null;
          const isMain = z.id === "P4";
          return (
            <div key={z.id} style={{
              width: `${pct}%`, background: z.color, opacity: isMain ? 1 : 0.55,
              borderRight: "1px solid var(--paper)",
            }} />
          );
        })}
      </div>
      <div style={{ marginTop: 10, display: "grid", gridTemplateColumns: "repeat(5, 1fr)", gap: 8 }}>
        {zones.map(z => {
          const v = data[z.id] || 0;
          const pct = (v / total) * 100;
          const isMain = z.id === "P4";
          return (
            <div key={z.id} style={{ display: "flex", flexDirection: "column", gap: 3 }}>
              <div style={{ display: "flex", alignItems: "center", gap: 5 }}>
                <span style={{ width: 6, height: 6, background: z.color, opacity: isMain ? 1 : 0.55 }} />
                <span style={{ ...wdStyles.eyebrowSm, color: isMain ? "var(--ink)" : "var(--ink-3)" }}>{z.id}</span>
              </div>
              <span style={{ ...wdStyles.mono, fontSize: 13, fontWeight: 600,
                color: isMain ? "var(--coral)" : "var(--ink-2)" }}>{fmtMin(v)}</span>
              <span style={{ ...wdStyles.eyebrowSm, fontSize: 8 }}>{Math.round(pct)}%</span>
            </div>
          );
        })}
      </div>
    </div>
  );
}

/* Splits as compact bars + table */
function SplitsTable({ splits = WD_SPLITS }) {
  const min = Math.min(...splits.map(s => s.paceSec));
  const max = Math.max(...splits.map(s => s.paceSec));
  return (
    <div style={{ display: "flex", flexDirection: "column" }}>
      {splits.map((s, idx) => {
        const w = ((max + 30 - s.paceSec) / 60) * 100;
        const fastest = s.paceSec === min;
        const slowest = s.paceSec === max;
        return (
          <div key={s.i} style={{
            display: "grid", gridTemplateColumns: "20px 1fr 48px 36px 36px",
            alignItems: "center", gap: 10, padding: "8px 0",
            borderBottom: idx < splits.length - 1 ? "1px solid var(--rule)" : "none",
          }}>
            <span style={{ ...wdStyles.eyebrowSm,
              color: fastest ? "var(--coral)" : "var(--ink-3)", textAlign: "right" }}>{s.i}</span>
            <div style={{ display: "flex", alignItems: "center", gap: 6 }}>
              <div style={{
                height: 4, width: `${Math.min(w, 100)}%`,
                background: fastest ? "var(--coral)" : slowest ? "var(--ink-3)" : "var(--ink-2)",
                opacity: fastest ? 1 : slowest ? 0.5 : 0.85,
              }} />
              <span style={{ ...wdStyles.eyebrowSm, color: "var(--ink-3)" }}>{s.mi.toFixed(2)}mi</span>
            </div>
            <span style={{ ...wdStyles.mono, fontSize: 13, fontWeight: 600,
              color: fastest ? "var(--coral)" : "var(--ink)", textAlign: "right" }}>{s.pace}</span>
            <span style={{ ...wdStyles.mono, fontSize: 12,
              color: "var(--ink-2)", textAlign: "right" }}>{s.hr}</span>
            <span style={{ ...wdStyles.mono, fontSize: 12,
              color: "var(--ink-3)", textAlign: "right" }}>{s.cad}</span>
          </div>
        );
      })}
    </div>
  );
}

/* Splits header */
function SplitsHeader() {
  return (
    <div style={{
      display: "grid", gridTemplateColumns: "20px 1fr 48px 36px 36px",
      gap: 10, padding: "8px 0 4px 0",
      borderBottom: "1px solid var(--rule)",
    }}>
      <span style={{ ...wdStyles.eyebrowSm, textAlign: "right" }}>#</span>
      <span style={wdStyles.eyebrowSm}>DIST</span>
      <span style={{ ...wdStyles.eyebrowSm, textAlign: "right" }}>PACE</span>
      <span style={{ ...wdStyles.eyebrowSm, textAlign: "right" }}>HR</span>
      <span style={{ ...wdStyles.eyebrowSm, textAlign: "right" }}>CAD</span>
    </div>
  );
}

/* HR Recovery — 60s post-finish */
function HRRecoveryArc({ data = WD_RECOVERY, height = 120 }) {
  const W = 320, H = height;
  const PAD_L = 32, PAD_R = 100, PAD_T = 14, PAD_B = 20;
  const plotW = W - PAD_L - PAD_R, plotH = H - PAD_T - PAD_B;
  const min = 60, max = 160;
  const xScale = (i) => PAD_L + (i / (data.length - 1)) * plotW;
  const yScale = (v) => PAD_T + plotH - ((v - min) / (max - min)) * plotH;
  const path = data.map((v, i) => `${i === 0 ? "M" : "L"} ${xScale(i).toFixed(1)} ${yScale(v).toFixed(1)}`).join(" ");
  const dropAt60 = data[0] - data[29];
  return (
    <svg viewBox={`0 0 ${W} ${H}`} style={{ width: "100%", height, display: "block" }}>
      {[80, 100, 120, 140].map(v => (
        <g key={v}>
          <line x1={PAD_L} x2={PAD_L + plotW} y1={yScale(v)} y2={yScale(v)} stroke="var(--rule)" strokeWidth="0.4" />
          <text x={PAD_L - 6} y={yScale(v) + 3} textAnchor="end"
            fontFamily="var(--font-mono)" fontSize="8" fill="var(--ink-3)">{v}</text>
        </g>
      ))}
      {/* 60-second mark */}
      <line x1={xScale(29)} x2={xScale(29)} y1={PAD_T} y2={PAD_T + plotH}
        stroke="var(--coral)" strokeWidth="0.6" strokeDasharray="2 2" opacity="0.6" />
      <text x={xScale(29) + 4} y={PAD_T + 10}
        fontFamily="var(--font-mono)" fontSize="8" fill="var(--coral)" letterSpacing="0.10em">60s</text>
      {/* Time axis */}
      <text x={PAD_L} y={H - 4} fontFamily="var(--font-mono)" fontSize="8" fill="var(--ink-3)" letterSpacing="0.10em">FINISH</text>
      <text x={PAD_L + plotW} y={H - 4} textAnchor="end"
        fontFamily="var(--font-mono)" fontSize="8" fill="var(--ink-3)" letterSpacing="0.10em">90s</text>
      <path d={path} fill="none" stroke="var(--coral)" strokeWidth="1.4"
        strokeLinecap="round" strokeLinejoin="round" />
      {/* Big readout on the right */}
      <text x={W - PAD_R + 14} y={PAD_T + 14}
        fontFamily="var(--font-mono)" fontSize="9" fill="var(--ink-3)" letterSpacing="0.12em">DROP / 60s</text>
      <text x={W - PAD_R + 14} y={PAD_T + 44}
        fontFamily="var(--font-mono)" fontSize="32" fontWeight="600" fill="var(--coral)">−{dropAt60}</text>
      <text x={W - PAD_R + 14} y={PAD_T + 58}
        fontFamily="var(--font-mono)" fontSize="8" fill="var(--ink-3)" letterSpacing="0.10em">BPM</text>
      <text x={W - PAD_R + 14} y={PAD_T + 82}
        fontFamily="var(--font-body)" fontStyle="italic" fontSize="11" fill="var(--ink-2)">
        {dropAt60 > 30 ? "strong" : dropAt60 > 20 ? "healthy" : "sluggish"}
      </text>
    </svg>
  );
}

/* Comparison bars — this run vs 4w avg */
function ComparisonBars() {
  const items = [
    { label: "DISTANCE", unit: "mi", now: WD_TOTALS.distMi, then: WD_RECENT_AVG.distMi, fmt: (v) => v.toFixed(1) },
    { label: "AVG HR",   unit: "bpm", now: WD_TOTALS.avgHr, then: WD_RECENT_AVG.hr, fmt: (v) => Math.round(v) },
    { label: "AVG PACE", unit: "/mi", now: WD_TOTALS.avgPaceSec, then: WD_RECENT_AVG.pace, fmt: fmtPace, inverted: true },
    { label: "CADENCE",  unit: "spm", now: WD_TOTALS.avgCadence, then: WD_RECENT_AVG.cadence, fmt: (v) => Math.round(v) },
  ];
  return (
    <div style={{ display: "flex", flexDirection: "column" }}>
      {items.map((it, idx) => {
        const max = Math.max(it.now, it.then);
        const delta = it.now - it.then;
        const better = it.inverted ? delta < 0 : delta > 0;
        const pctDelta = (delta / it.then) * 100;
        return (
          <div key={it.label} style={{
            padding: "10px 0",
            borderBottom: idx < items.length - 1 ? "1px solid var(--rule)" : "none",
          }}>
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline" }}>
              <span style={wdStyles.eyebrowSm}>{it.label}</span>
              <span style={{ ...wdStyles.eyebrowSm,
                color: better ? "var(--mood-energized)" : "var(--coral)" }}>
                {pctDelta > 0 ? "+" : ""}{pctDelta.toFixed(1)}%
              </span>
            </div>
            <div style={{ display: "flex", gap: 10, marginTop: 8, alignItems: "center" }}>
              <div style={{ flex: 1, display: "flex", flexDirection: "column", gap: 4 }}>
                <div style={{ display: "flex", alignItems: "center", gap: 6 }}>
                  <div style={{ height: 8, flex: it.now / max, background: "var(--coral)" }} />
                  <span style={{ ...wdStyles.mono, fontSize: 12, fontWeight: 600, color: "var(--coral)", minWidth: 50, textAlign: "right" }}>
                    {it.fmt(it.now)}
                  </span>
                </div>
                <div style={{ display: "flex", alignItems: "center", gap: 6 }}>
                  <div style={{ height: 8, flex: it.then / max, background: "var(--ink-3)", opacity: 0.5 }} />
                  <span style={{ ...wdStyles.mono, fontSize: 12, fontWeight: 500, color: "var(--ink-2)", minWidth: 50, textAlign: "right" }}>
                    {it.fmt(it.then)}
                  </span>
                </div>
              </div>
            </div>
            <div style={{ display: "flex", gap: 12, marginTop: 4 }}>
              <span style={{ ...wdStyles.eyebrowSm, fontSize: 8, color: "var(--coral)" }}>● TODAY</span>
              <span style={{ ...wdStyles.eyebrowSm, fontSize: 8, color: "var(--ink-3)" }}>● 4W AVG</span>
            </div>
          </div>
        );
      })}
    </div>
  );
}

/* Route placeholder */
function RoutePlaceholder({ height = 140 }) {
  return (
    <div style={{
      width: "100%", height,
      background: "repeating-linear-gradient(45deg, var(--paper-deep), var(--paper-deep) 6px, var(--paper) 6px, var(--paper) 12px)",
      border: "1px solid var(--rule)", position: "relative", overflow: "hidden",
    }}>
      <div style={{ position: "absolute", top: 8, left: 10, ...wdStyles.eyebrowSm }}>
        ROUTE · 6.9MI · AUSTIN, TX
      </div>
      <svg viewBox="0 0 320 140" style={{ width: "100%", height: "100%" }}>
        <path d="M 50 110 Q 80 60, 130 70 T 200 50 Q 240 40, 270 65 L 285 95"
          fill="none" stroke="var(--coral)" strokeWidth="2.5"
          strokeLinecap="round" strokeLinejoin="round" />
        <circle cx="50" cy="110" r="4" fill="var(--ink)" />
        <circle cx="285" cy="95" r="4" fill="var(--coral)" />
      </svg>
      <div style={{ position: "absolute", bottom: 8, right: 10, ...wdStyles.eyebrowSm }}>
        +{WD_TOTALS.elevFt}FT ELEV
      </div>
    </div>
  );
}

/* small section header */
function ChartSectionHeader({ eyebrow, value, sub }) {
  return (
    <div style={{
      display: "flex", justifyContent: "space-between", alignItems: "baseline",
    }}>
      <Eyebrow>{eyebrow}</Eyebrow>
      {value && (
        <span style={{ ...wdStyles.mono, fontSize: 11, color: "var(--ink-2)" }}>
          {value}{sub && <span style={{ color: "var(--ink-3)", marginLeft: 6 }}>{sub}</span>}
        </span>
      )}
    </div>
  );
}

/* ════════════════════════════════════════════════════════════════════
   DIRECTION A · RECEIPT — chart-rich, restrained
   ════════════════════════════════════════════════════════════════════ */

function WorkoutDetailReceipt() {
  return (
    <div style={{ height: "100%", background: "var(--paper)", display: "flex", flexDirection: "column", overflow: "hidden" }}>
      <WDPlate surface="WORKOUT · DETAIL" fig="05.21.26" right="STRAVA · 09:06" />
      <div style={{ flex: 1, overflowY: "auto", padding: "8px 0 32px 0" }}>
        {/* Day heading */}
        <div style={{ padding: "20px 24px 0 24px" }}>
          <h1 style={{ fontFamily: "var(--font-display)", fontWeight: 700, fontSize: 44,
            margin: 0, letterSpacing: "-0.01em", color: "var(--ink)", lineHeight: 1 }}>Thursday</h1>
          <p style={{ ...wdStyles.italic, fontSize: 13, color: "var(--ink-3)", margin: "8px 0 0 0" }}>
            — {WD_TOTALS.fullDate} · easy aerobic with a clean negative split. —
          </p>
        </div>

        {/* Hero stat row */}
        <div style={{
          margin: "20px 24px 0 24px",
          display: "grid", gridTemplateColumns: "1fr 1fr",
          borderTop: "1px solid var(--rule)", borderBottom: "1px solid var(--rule)",
        }}>
          <div style={{ padding: "14px 0", borderRight: "1px solid var(--rule)", paddingRight: 12 }}>
            <span style={wdStyles.eyebrow}>DISTANCE</span>
            <div style={{ ...wdStyles.mono, fontSize: 36, fontWeight: 600, marginTop: 4, color: "var(--ink)" }}>
              {WD_TOTALS.distMi.toFixed(2)}<span style={{ fontSize: 14, color: "var(--ink-3)", marginLeft: 4 }}>mi</span>
            </div>
          </div>
          <div style={{ padding: "14px 0 14px 16px" }}>
            <span style={wdStyles.eyebrow}>TIME</span>
            <div style={{ ...wdStyles.mono, fontSize: 36, fontWeight: 600, marginTop: 4, color: "var(--ink)" }}>
              {WD_TOTALS.timeText}
            </div>
          </div>
        </div>

        {/* Sub-stat strip */}
        <div style={{
          margin: "0 24px",
          display: "grid", gridTemplateColumns: "repeat(4, 1fr)",
          borderBottom: "1px solid var(--rule)",
        }}>
          {[
            { l: "AVG PACE", v: WD_TOTALS.avgPace, u: "/mi" },
            { l: "AVG HR",   v: WD_TOTALS.avgHr.toString() },
            { l: "CADENCE",  v: WD_TOTALS.avgCadence.toString(), u: "spm" },
            { l: "ELEV",     v: WD_TOTALS.elevFt.toString(), u: "ft" },
          ].map((s, i, arr) => (
            <div key={s.l} style={{
              padding: "10px 4px",
              display: "flex", flexDirection: "column", alignItems: "center", gap: 4,
              borderRight: i < arr.length - 1 ? "1px solid var(--rule)" : "none",
            }}>
              <span style={wdStyles.eyebrowSm}>{s.l}</span>
              <span style={{ ...wdStyles.mono, fontSize: 15, fontWeight: 600, color: "var(--ink)" }}>
                {s.v}{s.u && <span style={{ fontSize: 9, color: "var(--ink-3)", marginLeft: 2 }}>{s.u}</span>}
              </span>
            </div>
          ))}
        </div>

        {/* 1 · Time in HR zone */}
        <div style={{ padding: "24px 24px 0 24px" }}>
          <ChartSectionHeader eyebrow="TIME IN HR ZONE" value={WD_TOTALS.timeText} sub="TOTAL" />
          <TimeInZoneBar />
        </div>

        {/* 2 · Time in pace zone */}
        <div style={{ padding: "22px 24px 0 24px" }}>
          <ChartSectionHeader eyebrow="TIME IN PACE ZONE" value="P4 · TEMPO" sub="DOMINANT" />
          <TimeInPaceBar />
        </div>

        {/* 3 · HR + 4 · Pace (stacked) */}
        <div style={{ padding: "24px 24px 0 24px" }}>
          <ChartSectionHeader eyebrow="HEART RATE · 51:06"
            value={<><span style={{ color: "var(--coral)", fontWeight: 600 }}>{WD_TOTALS.avgHr}</span></>}
            sub={`${WD_TOTALS.minHr}–${WD_TOTALS.maxHr}`} />
          <HRZonedChart height={110} />
        </div>
        <div style={{ padding: "8px 24px 0 24px" }}>
          <ChartSectionHeader eyebrow="PACE · 51:06" value={WD_TOTALS.avgPace} sub="AVG /MI" />
          <PaceOverTimeChart height={100} showSplit />
        </div>

        {/* 5 · Mile sparklines */}
        <div style={{ padding: "20px 24px 0 24px" }}>
          <ChartSectionHeader eyebrow="MILE BY MILE · HR" value="7 MILES" />
          <MileSparklines />
        </div>

        {/* 6 · HR recovery */}
        <div style={{ padding: "22px 24px 0 24px" }}>
          <ChartSectionHeader eyebrow="HR RECOVERY · 90S" />
          <HRRecoveryArc />
        </div>

        {/* 7 · Splits */}
        <div style={{ padding: "20px 24px 0 24px" }}>
          <ChartSectionHeader eyebrow="SPLITS"
            value={<><span style={{ color: "var(--coral)" }}>{WD_TOTALS.fastestSplit}</span> → {WD_TOTALS.slowestSplit}</>} />
          <SplitsHeader />
          <SplitsTable />
        </div>

        {/* 8 · Route */}
        <div style={{ padding: "22px 24px 0 24px" }}>
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline", marginBottom: 8 }}>
            <Eyebrow>ROUTE</Eyebrow>
            <span style={{ ...wdStyles.eyebrow, color: "var(--coral)", cursor: "pointer" }}>FULL MAP ↗</span>
          </div>
          <RoutePlaceholder height={120} />
        </div>

        <div style={{ height: 24 }} />
      </div>
    </div>
  );
}

/* ════════════════════════════════════════════════════════════════════
   DIRECTION B · ANALYST — densest, all the signals
   ════════════════════════════════════════════════════════════════════ */

function WorkoutDetailAnalyst() {
  return (
    <div style={{ height: "100%", background: "var(--paper)", display: "flex", flexDirection: "column", overflow: "hidden" }}>
      <WDPlate surface="WORKOUT · TELEMETRY" fig="05.21" right="THU · 09:06" />
      <div style={{ flex: 1, overflowY: "auto", padding: "8px 0 32px 0" }}>
        {/* Compact heading */}
        <div style={{ padding: "16px 24px 0 24px", display: "flex", justifyContent: "space-between", alignItems: "baseline" }}>
          <h1 style={{ fontFamily: "var(--font-display)", fontWeight: 700, fontSize: 26,
            margin: 0, letterSpacing: "-0.01em", color: "var(--ink)" }}>Thursday · easy</h1>
          <span style={wdStyles.eyebrowSm}>STRAVA · 09:06</span>
        </div>

        {/* Hero row 3-up */}
        <div style={{
          margin: "14px 24px 0 24px",
          display: "grid", gridTemplateColumns: "1.4fr 1fr 1fr",
          borderTop: "1px solid var(--rule)", borderBottom: "1px solid var(--rule)",
        }}>
          <div style={{ padding: "14px 16px 14px 0", borderRight: "1px solid var(--rule)" }}>
            <span style={wdStyles.eyebrowSm}>DISTANCE</span>
            <div style={{ ...wdStyles.mono, fontSize: 42, fontWeight: 600, color: "var(--ink)", lineHeight: 1, marginTop: 4 }}>
              {WD_TOTALS.distMi.toFixed(2)}
            </div>
            <span style={{ ...wdStyles.eyebrowSm, color: "var(--ink-3)" }}>MILES</span>
          </div>
          <div style={{ padding: "14px 16px", borderRight: "1px solid var(--rule)" }}>
            <span style={wdStyles.eyebrowSm}>TIME</span>
            <div style={{ ...wdStyles.mono, fontSize: 22, fontWeight: 600, color: "var(--ink)", marginTop: 4 }}>
              {WD_TOTALS.timeText}
            </div>
            <span style={{ ...wdStyles.eyebrowSm, color: "var(--ink-3)" }}>{WD_TOTALS.avgPace} /MI</span>
          </div>
          <div style={{ padding: "14px 0 14px 16px" }}>
            <span style={wdStyles.eyebrowSm}>AVG HR</span>
            <div style={{ ...wdStyles.mono, fontSize: 22, fontWeight: 600, color: "var(--coral)", marginTop: 4 }}>
              {WD_TOTALS.avgHr}
            </div>
            <span style={{ ...wdStyles.eyebrowSm, color: "var(--ink-3)" }}>
              {WD_TOTALS.minHr}–{WD_TOTALS.maxHr} BPM
            </span>
          </div>
        </div>

        {/* 1 · HR + 2 · Elevation stacked */}
        <div style={{ padding: "22px 24px 0 24px" }}>
          <ChartSectionHeader eyebrow="HEART RATE · ELEVATION" value="00:00" sub="→ 51:06" />
          <div style={{ marginTop: 8 }}>
            <HRZonedChart height={140} />
            <ElevationProfile height={36} />
            <div style={{ display: "flex", justifyContent: "space-between", ...wdStyles.eyebrowSm, marginTop: 4 }}>
              <span>0:00</span><span>12:48</span><span>25:36</span><span>38:24</span><span>51:06</span>
            </div>
          </div>
        </div>

        {/* 3 · Pace */}
        <div style={{ padding: "22px 24px 0 24px" }}>
          <ChartSectionHeader eyebrow="PACE · SMOOTHED 30S" value={WD_TOTALS.avgPace} sub="AVG /MI" />
          <PaceOverTimeChart height={110} showSplit />
        </div>

        {/* 4 · Cadence */}
        <div style={{ padding: "22px 24px 0 24px" }}>
          <ChartSectionHeader eyebrow="CADENCE · SPM" value={WD_TOTALS.avgCadence} sub="AVG" />
          <CadenceChart height={56} />
        </div>

        {/* 5 · Time in HR zone */}
        <div style={{ padding: "22px 24px 0 24px" }}>
          <ChartSectionHeader eyebrow="TIME IN HR ZONE" value="OF" sub={WD_TOTALS.timeText} />
          <div style={{ marginTop: 10 }}>
            {WD_ZONES.map(z => {
              const sec = WD_TIZ[z.id] || 0;
              const total = Object.values(WD_TIZ).reduce((a, b) => a + b, 0);
              const pct = (sec / total) * 100;
              const isMain = z.id === "Z3";
              return (
                <div key={z.id} style={{
                  display: "grid", gridTemplateColumns: "30px 1fr 60px 40px",
                  alignItems: "center", gap: 10, padding: "5px 0",
                  borderBottom: "1px solid var(--rule)",
                }}>
                  <span style={{ ...wdStyles.eyebrowSm, color: isMain ? "var(--ink)" : "var(--ink-2)" }}>{z.id}</span>
                  <div style={{ height: 6, background: "var(--paper-deep)", position: "relative" }}>
                    <div style={{
                      position: "absolute", top: 0, left: 0,
                      height: "100%", width: `${pct}%`,
                      background: isMain ? "var(--coral)" : "var(--ink-2)",
                      opacity: isMain ? 1 : 0.5,
                    }} />
                  </div>
                  <span style={{ ...wdStyles.mono, fontSize: 12, fontWeight: 600,
                    color: isMain ? "var(--coral)" : "var(--ink-2)", textAlign: "right" }}>{fmtMin(sec)}</span>
                  <span style={{ ...wdStyles.eyebrowSm, color: isMain ? "var(--ink)" : "var(--ink-3)", textAlign: "right" }}>
                    {Math.round(pct)}%
                  </span>
                </div>
              );
            })}
          </div>
        </div>

        {/* 6 · HR vs Pace scatter (efficiency) */}
        <div style={{ padding: "22px 24px 0 24px" }}>
          <ChartSectionHeader eyebrow="EFFICIENCY · HR × PACE" value="r² ≈ 0.71" />
          <p style={{ ...wdStyles.italic, fontSize: 12, color: "var(--ink-3)", margin: "4px 0 0 0" }}>
            — each dot is a 30s window; coral line is the fit. —
          </p>
          <HRPaceScatter height={180} />
        </div>

        {/* 7 · HR drift / decoupling */}
        <div style={{ padding: "22px 24px 0 24px" }}>
          <ChartSectionHeader eyebrow="AEROBIC DECOUPLING" value="1st HALF" sub="vs 2nd HALF" />
          <HRDriftChart />
        </div>

        {/* 8 · HR recovery */}
        <div style={{ padding: "22px 24px 0 24px" }}>
          <ChartSectionHeader eyebrow="HR RECOVERY · 90S" />
          <HRRecoveryArc />
        </div>

        {/* 9 · Mile sparklines */}
        <div style={{ padding: "22px 24px 0 24px" }}>
          <ChartSectionHeader eyebrow="MILE BY MILE · HR + PACE" value="7 SPLITS" />
          <MileSparklines />
        </div>

        {/* 10 · Splits table */}
        <div style={{ padding: "22px 24px 0 24px" }}>
          <ChartSectionHeader eyebrow="SPLITS"
            value={<>{WD_TOTALS.fastestSplit} <span style={{ color: "var(--ink-3)" }}>→</span> {WD_TOTALS.slowestSplit}</>} />
          <SplitsHeader />
          <SplitsTable />
        </div>

        {/* 11 · vs 4-week comparison */}
        <div style={{ padding: "22px 24px 0 24px" }}>
          <ChartSectionHeader eyebrow="THIS RUN · vs 4-WEEK AVG" />
          <ComparisonBars />
        </div>

        {/* 12 · Route */}
        <div style={{ padding: "22px 24px 0 24px" }}>
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline", marginBottom: 8 }}>
            <Eyebrow>ROUTE · AUSTIN, TX</Eyebrow>
            <span style={{ ...wdStyles.eyebrow, color: "var(--coral)", cursor: "pointer" }}>OPEN MAP ↗</span>
          </div>
          <RoutePlaceholder height={140} />
        </div>

        <div style={{ height: 24 }} />
      </div>
    </div>
  );
}

/* ════════════════════════════════════════════════════════════════════
   DIRECTION C · STORY — narrative annotation
   ════════════════════════════════════════════════════════════════════ */

function WorkoutDetailStory() {
  return (
    <div style={{ height: "100%", background: "var(--paper)", display: "flex", flexDirection: "column", overflow: "hidden" }}>
      <WDPlate surface="WORKOUT · READ" fig="THU 05.21" right="STRAVA" />
      <div style={{ flex: 1, overflowY: "auto", padding: "8px 0 32px 0" }}>
        {/* Editorial heading */}
        <div style={{ padding: "26px 24px 0 24px" }}>
          <span style={wdStyles.eyebrow}>THE THURSDAY EASY</span>
          <h1 style={{ fontFamily: "var(--font-display)", fontWeight: 700, fontSize: 38,
            margin: "10px 0 0 0", letterSpacing: "-0.01em", color: "var(--ink)", lineHeight: 1.08 }}>
            6.9 controlled miles<br />
            <span style={{ color: "var(--coral)" }}>and a clean negative split.</span>
          </h1>
        </div>

        {/* Pull narrative */}
        <div style={{ padding: "18px 24px 0 24px" }}>
          <p style={{ ...wdStyles.italic, fontSize: 15, color: "var(--ink)", margin: 0 }}>
            You warmed in at 8:02, settled into the low 7:20s by mile two, and held the back
            half almost a minute per mile faster than the start. Heart rate sat right on
            <span style={{ color: "var(--coral)", fontStyle: "normal", fontWeight: 600 }}> tempo's edge </span>
            — exactly what an easy day should look like.
          </p>
        </div>

        {/* 3 hero stats */}
        <div style={{
          margin: "22px 24px 0 24px",
          display: "grid", gridTemplateColumns: "repeat(3, 1fr)",
          borderTop: "1px solid var(--rule)", borderBottom: "1px solid var(--rule)",
        }}>
          {[
            { l: "MILES",    v: WD_TOTALS.distMi.toFixed(1) },
            { l: "TIME",     v: WD_TOTALS.timeText },
            { l: "AVG PACE", v: WD_TOTALS.avgPace, u: "/mi" },
          ].map((s, i, arr) => (
            <div key={s.l} style={{
              padding: "16px 4px",
              display: "flex", flexDirection: "column", alignItems: "center", gap: 4,
              borderRight: i < arr.length - 1 ? "1px solid var(--rule)" : "none",
            }}>
              <span style={wdStyles.eyebrowSm}>{s.l}</span>
              <span style={{ ...wdStyles.mono, fontSize: 26, fontWeight: 600,
                color: i === 2 ? "var(--coral)" : "var(--ink)", lineHeight: 1, marginTop: 2 }}>
                {s.v}{s.u && <span style={{ fontSize: 10, color: "var(--ink-3)", marginLeft: 3 }}>{s.u}</span>}
              </span>
            </div>
          ))}
        </div>

        {/* 1 · Annotated HR */}
        <div style={{ padding: "24px 24px 0 24px" }}>
          <Eyebrow>HEART RATE · 51 MINUTES</Eyebrow>
          <p style={{ ...wdStyles.italic, fontSize: 12, color: "var(--ink-3)", margin: "4px 0 0 0" }}>
            — Tempo band shaded. Annotations auto-generated. —
          </p>
          <div style={{ marginTop: 6 }}>
            <HRZonedChart
              height={170}
              annotations={[
                { i: 5,  label: "WARMUP" },
                { i: 18, label: "TRAFFIC LIGHT", anchor: "start" },
                { i: 50, label: "TEMPO HOLD" },
                { i: 82, label: "COOLDOWN", anchor: "end" },
              ]}
            />
          </div>
        </div>

        {/* 2 · Negative split pace + callout */}
        <div style={{ padding: "22px 24px 0 24px" }}>
          <ChartSectionHeader eyebrow="PACE · NEGATIVE SPLIT" />
          <PaceOverTimeChart height={120} showSplit />
        </div>
        <div style={{
          margin: "16px 24px 0 24px", padding: "18px 0",
          borderTop: "1px solid var(--rule)", borderBottom: "1px solid var(--rule)",
          display: "grid", gridTemplateColumns: "1fr 1fr",
        }}>
          <div style={{ borderRight: "1px solid var(--rule)", paddingRight: 16 }}>
            <span style={wdStyles.eyebrowSm}>FIRST 3.5 MI</span>
            <div style={{ ...wdStyles.mono, fontSize: 28, fontWeight: 600, color: "var(--ink-2)", marginTop: 4, lineHeight: 1 }}>7:33</div>
            <span style={{ ...wdStyles.italic, fontSize: 12, color: "var(--ink-3)" }}>easing in</span>
          </div>
          <div style={{ paddingLeft: 16 }}>
            <span style={wdStyles.eyebrowSm}>SECOND 3.4 MI</span>
            <div style={{ ...wdStyles.mono, fontSize: 28, fontWeight: 600, color: "var(--coral)", marginTop: 4, lineHeight: 1 }}>7:15</div>
            <span style={{ ...wdStyles.italic, fontSize: 12, color: "var(--ink-3)" }}>18 sec/mi faster</span>
          </div>
        </div>

        {/* 3 · Decoupling */}
        <div style={{ padding: "22px 24px 0 24px" }}>
          <ChartSectionHeader eyebrow="AEROBIC DECOUPLING" />
          <p style={{ ...wdStyles.italic, fontSize: 12, color: "var(--ink-3)", margin: "4px 0 0 0" }}>
            — pace got faster, HR barely moved. textbook aerobic. —
          </p>
          <HRDriftChart />
        </div>

        {/* 4 · HR recovery */}
        <div style={{ padding: "22px 24px 0 24px" }}>
          <ChartSectionHeader eyebrow="HR DROPPED HARD" />
          <p style={{ ...wdStyles.italic, fontSize: 12, color: "var(--ink-3)", margin: "4px 0 0 0" }}>
            — strong autonomic recovery. you weren't actually working that hard. —
          </p>
          <HRRecoveryArc />
        </div>

        {/* 5 · Mile sparklines */}
        <div style={{ padding: "22px 24px 0 24px" }}>
          <ChartSectionHeader eyebrow="EVERY MILE · HR ARC" />
          <MileSparklines />
        </div>

        {/* 6 · Splits */}
        <div style={{ padding: "22px 24px 0 24px" }}>
          <ChartSectionHeader eyebrow="EVERY MILE · PACE"
            value={<span style={{ ...wdStyles.italic, fontSize: 11, color: "var(--ink-3)" }}>
              — fastest in coral. —
            </span>} />
          <SplitsHeader />
          <SplitsTable />
        </div>

        {/* 7 · Where it sits */}
        <div style={{ padding: "22px 24px 0 24px" }}>
          <Eyebrow>WHERE THIS SITS · vs YOUR LAST 4 WEEKS</Eyebrow>
          <p style={{ ...wdStyles.italic, fontSize: 12, color: "var(--ink-3)", margin: "4px 0 0 0" }}>
            — heavier, faster, lower HR. you're in form. —
          </p>
          <ComparisonBars />
        </div>

        {/* 8 · Route */}
        <div style={{ padding: "22px 24px 0 24px" }}>
          <Eyebrow>WHERE</Eyebrow>
          <div style={{ marginTop: 8 }}>
            <RoutePlaceholder height={110} />
          </div>
        </div>

        <div style={{ height: 24 }} />
      </div>
    </div>
  );
}

Object.assign(window, {
  WorkoutDetailReceipt,
  WorkoutDetailAnalyst,
  WorkoutDetailStory,
});

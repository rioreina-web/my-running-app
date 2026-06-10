/* global React */
/* ════════════════════════════════════════════════════════════════════
   HOME · CHARTS  (v5)
   All editorial chart primitives in one file. SVG-only.
   No fills bigger than thin washes. Coral as punctuation.
   ════════════════════════════════════════════════════════════════════ */

const INK = "#1A1815";
const INK2 = "#6B6560";
const INK3 = "#9B9590";
const PAPER = "#F5F3F0";
const HAIRLINE = "#E8E4E0";
const SAGE = "#6B8068";

/* ── Plate strip — magazine header for any data plate ─────────────── */
window.PlateStrip = function PlateStrip({ left, right }) {
  return (
    <div className="flex items-baseline justify-between px-6 py-3 border-b border-divider-soft bg-bg-base">
      <span className="font-mono text-[10.5px] tracking-[1.6px] uppercase text-text-tertiary">
        {left}
      </span>
      <span className="font-mono text-[10.5px] tracking-[1.6px] uppercase text-text-tertiary">
        {right}
      </span>
    </div>
  );
};

/* ── Plate caption — bottom signature ─────────────────────────────── */
window.PlateCaption = function PlateCaption({ children }) {
  return (
    <div className="px-6 py-3 border-t border-divider-soft bg-bg-base">
      <span className="font-mono text-[10.5px] tracking-[1.6px] uppercase text-text-tertiary">
        {children}
      </span>
    </div>
  );
};

/* ── Editorial rule — line · dot · line ───────────────────────────── */
window.EditorialRule = function EditorialRule({ accent }) {
  return (
    <div className="flex items-center justify-center gap-3 py-2">
      <span className="block h-px w-12 bg-divider" />
      <span
        className="block h-[5px] w-[5px] rounded-full"
        style={{ background: accent }}
      />
      <span className="block h-px w-12 bg-divider" />
    </div>
  );
};

/* ════════════════════════════════════════════════════════════════════
   MILEAGE  — 18-week area + line.  Deloads marked, peak labelled.
   ════════════════════════════════════════════════════════════════════ */
window.MileageChart = function MileageChart({ accent, height = 180 }) {
  // 18 weeks of marathon block, weekly mileage in miles
  const data = [
    22, 26, 30, 32, 22,        // build-1 + deload
    35, 38, 42, 45, 30,        // build-2 + deload
    48, 52, 56, 60, 42,        // peak + deload
    47, 36, 26,                // taper
  ];
  const labelWeeks = ["W1", "W4", "W8", "W12", "W16", "W18"];
  const deloads = [4, 9, 14]; // 0-indexed
  const peakIdx = data.indexOf(Math.max(...data));

  const W = 720;
  const H = height;
  const padL = 36;
  const padR = 16;
  const padT = 14;
  const padB = 28;
  const max = 65;
  const pts = data.map((v, i) => {
    const x = padL + (i * (W - padL - padR)) / (data.length - 1);
    const y = padT + ((max - v) / max) * (H - padT - padB);
    return [x, y];
  });
  const path = pts.map(([x, y], i) => `${i === 0 ? "M" : "L"}${x},${y}`).join(" ");
  const area =
    `M${pts[0][0]},${H - padB} ` +
    pts.map(([x, y]) => `L${x},${y}`).join(" ") +
    ` L${pts[pts.length - 1][0]},${H - padB} Z`;

  const yTicks = [0, 20, 40, 60];

  return (
    <svg viewBox={`0 0 ${W} ${H}`} className="w-full h-auto block">
      <defs>
        <linearGradient id="mileageWash" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor={accent} stopOpacity="0.14" />
          <stop offset="100%" stopColor={accent} stopOpacity="0" />
        </linearGradient>
      </defs>

      {/* y-axis ticks */}
      {yTicks.map((t) => {
        const y = padT + ((max - t) / max) * (H - padT - padB);
        return (
          <g key={t}>
            <line
              x1={padL}
              x2={W - padR}
              y1={y}
              y2={y}
              stroke={HAIRLINE}
              strokeWidth="1"
              strokeDasharray={t === 0 ? "0" : "2 3"}
            />
            <text
              x={padL - 8}
              y={y + 3}
              textAnchor="end"
              fontFamily="ui-monospace, Menlo, monospace"
              fontSize="9"
              letterSpacing="1.2"
              fill={INK3}
            >
              {t}
            </text>
          </g>
        );
      })}

      {/* deload bands */}
      {deloads.map((i) => {
        const x = padL + (i * (W - padL - padR)) / (data.length - 1);
        return (
          <line
            key={i}
            x1={x}
            x2={x}
            y1={padT}
            y2={H - padB}
            stroke={INK3}
            strokeWidth="1"
            strokeDasharray="1 4"
            opacity="0.5"
          />
        );
      })}

      {/* area + line */}
      <path d={area} fill="url(#mileageWash)" />
      <path d={path} fill="none" stroke={accent} strokeWidth="1.75" strokeLinejoin="round" />

      {/* dots */}
      {pts.map(([x, y], i) => (
        <circle
          key={i}
          cx={x}
          cy={y}
          r={i === peakIdx ? 3.5 : 1.8}
          fill={i === peakIdx ? accent : INK}
        />
      ))}

      {/* peak callout */}
      <g>
        <line
          x1={pts[peakIdx][0]}
          x2={pts[peakIdx][0]}
          y1={pts[peakIdx][1] - 8}
          y2={pts[peakIdx][1] - 22}
          stroke={INK}
          strokeWidth="1"
        />
        <text
          x={pts[peakIdx][0]}
          y={pts[peakIdx][1] - 26}
          textAnchor="middle"
          fontFamily="ui-monospace, Menlo, monospace"
          fontSize="9"
          letterSpacing="1.2"
          fill={INK}
        >
          PEAK · 60 mi
        </text>
      </g>

      {/* x-axis ticks */}
      {labelWeeks.map((lbl, i) => {
        const idxs = [0, 3, 7, 11, 15, 17];
        const idx = idxs[i];
        const x = padL + (idx * (W - padL - padR)) / (data.length - 1);
        return (
          <text
            key={lbl}
            x={x}
            y={H - 10}
            textAnchor="middle"
            fontFamily="ui-monospace, Menlo, monospace"
            fontSize="9"
            letterSpacing="1.2"
            fill={INK3}
          >
            {lbl}
          </text>
        );
      })}
    </svg>
  );
};

/* ════════════════════════════════════════════════════════════════════
   PACE PROGRESSION — Easy & MP, 12 weeks
   ════════════════════════════════════════════════════════════════════ */
window.PaceChart = function PaceChart({ accent, height = 160 }) {
  // Pace in seconds/mile. Lower = faster.
  const easy = [552, 548, 545, 540, 538, 535, 532, 530, 528, 525, 523, 520];
  const mp = [388, 385, 383, 381, 378, 376, 374, 372, 370, 368, 366, 364];

  const W = 480;
  const H = height;
  const padL = 44;
  const padR = 16;
  const padT = 14;
  const padB = 26;
  const min = 350;
  const max = 560;

  const toPath = (arr) => {
    const pts = arr.map((v, i) => {
      const x = padL + (i * (W - padL - padR)) / (arr.length - 1);
      const y = padT + ((v - min) / (max - min)) * (H - padT - padB);
      return [x, y];
    });
    return {
      d: pts.map(([x, y], i) => `${i === 0 ? "M" : "L"}${x},${y}`).join(" "),
      pts,
    };
  };
  const e = toPath(easy);
  const m = toPath(mp);

  const fmt = (s) => `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;

  const yTicks = [360, 420, 480, 540];

  return (
    <svg viewBox={`0 0 ${W} ${H}`} className="w-full h-auto block">
      {yTicks.map((t) => {
        const y = padT + ((t - min) / (max - min)) * (H - padT - padB);
        return (
          <g key={t}>
            <line
              x1={padL}
              x2={W - padR}
              y1={y}
              y2={y}
              stroke={HAIRLINE}
              strokeWidth="1"
              strokeDasharray="2 3"
            />
            <text
              x={padL - 8}
              y={y + 3}
              textAnchor="end"
              fontFamily="ui-monospace, Menlo, monospace"
              fontSize="9"
              letterSpacing="1.2"
              fill={INK3}
            >
              {fmt(t)}
            </text>
          </g>
        );
      })}

      {/* Easy line — sage */}
      <path d={e.d} fill="none" stroke={SAGE} strokeWidth="1.6" strokeLinejoin="round" />
      {/* MP line — coral */}
      <path d={m.d} fill="none" stroke={accent} strokeWidth="1.75" strokeLinejoin="round" />

      {/* endpoint labels */}
      <g>
        <circle cx={e.pts[e.pts.length - 1][0]} cy={e.pts[e.pts.length - 1][1]} r="2.5" fill={SAGE} />
        <text
          x={e.pts[e.pts.length - 1][0] - 6}
          y={e.pts[e.pts.length - 1][1] - 6}
          textAnchor="end"
          fontFamily="ui-monospace, Menlo, monospace"
          fontSize="9"
          letterSpacing="1.2"
          fill={SAGE}
        >
          EASY · {fmt(easy[easy.length - 1])}
        </text>
      </g>
      <g>
        <circle cx={m.pts[m.pts.length - 1][0]} cy={m.pts[m.pts.length - 1][1]} r="2.5" fill={accent} />
        <text
          x={m.pts[m.pts.length - 1][0] - 6}
          y={m.pts[m.pts.length - 1][1] - 6}
          textAnchor="end"
          fontFamily="ui-monospace, Menlo, monospace"
          fontSize="9"
          letterSpacing="1.2"
          fill={accent}
        >
          MP · {fmt(mp[mp.length - 1])}
        </text>
      </g>

      <text
        x={padL}
        y={H - 8}
        fontFamily="ui-monospace, Menlo, monospace"
        fontSize="9"
        letterSpacing="1.2"
        fill={INK3}
      >
        12 WEEKS
      </text>
    </svg>
  );
};

/* ════════════════════════════════════════════════════════════════════
   ACWR GAUGE — semicircle, ratio 0.8–1.5
   ════════════════════════════════════════════════════════════════════ */
window.LoadGauge = function LoadGauge({ accent, value = 1.12 }) {
  const W = 200;
  const H = 116;
  const cx = W / 2;
  const cy = 96;
  const r = 72;
  // map 0.6 → 180°, 1.6 → 0°  (semicircle, left→right)
  const t = Math.max(0, Math.min(1, (value - 0.6) / (1.6 - 0.6)));
  const angle = Math.PI * (1 - t);
  const px = cx + r * Math.cos(angle);
  const py = cy - r * Math.sin(angle);

  // Zone arcs — under (red), sweet-spot (sage), over (coral)
  const arc = (a0, a1) => {
    const x0 = cx + r * Math.cos(a0);
    const y0 = cy - r * Math.sin(a0);
    const x1 = cx + r * Math.cos(a1);
    const y1 = cy - r * Math.sin(a1);
    const large = Math.abs(a1 - a0) > Math.PI ? 1 : 0;
    return `M${x0},${y0} A${r},${r} 0 ${large} 0 ${x1},${y1}`;
  };

  // 0.6→0.8 under, 0.8→1.3 sweet, 1.3→1.6 over
  const aFrom = (v) => Math.PI * (1 - (v - 0.6) / 1.0);

  return (
    <svg viewBox={`0 0 ${W} ${H}`} className="w-full h-auto block">
      {/* zones */}
      <path d={arc(aFrom(0.6), aFrom(0.8))} stroke={HAIRLINE} strokeWidth="6" fill="none" strokeLinecap="round" />
      <path d={arc(aFrom(0.8), aFrom(1.3))} stroke={SAGE} strokeWidth="6" fill="none" strokeLinecap="round" />
      <path d={arc(aFrom(1.3), aFrom(1.6))} stroke={accent} strokeWidth="6" fill="none" strokeLinecap="round" />

      {/* needle */}
      <line x1={cx} y1={cy} x2={px} y2={py} stroke={INK} strokeWidth="1.5" />
      <circle cx={cx} cy={cy} r="3" fill={INK} />
      <circle cx={px} cy={py} r="2.5" fill={INK} />

      {/* end labels */}
      <text x={cx - r - 2} y={cy + 12} fontFamily="ui-monospace, Menlo, monospace" fontSize="8.5" letterSpacing="1.2" fill={INK3} textAnchor="middle">0.6</text>
      <text x={cx + r + 2} y={cy + 12} fontFamily="ui-monospace, Menlo, monospace" fontSize="8.5" letterSpacing="1.2" fill={INK3} textAnchor="middle">1.6</text>
    </svg>
  );
};

/* ════════════════════════════════════════════════════════════════════
   MOOD HEATMAP — 12 weeks × 7 days
   Mood vocab from CLAUDE.md: energized, positive, neutral, tired, struggling, injured
   ════════════════════════════════════════════════════════════════════ */
window.MoodHeatmap = function MoodHeatmap({ accent }) {
  const MOOD = {
    energized: "#2D8A4E",
    positive: "#4A9E6B",
    neutral: "#9B9590",
    tired: "#C4873A",
    struggling: "#C45A3A",
    injured: "#B83A4A",
    empty: HAIRLINE,
  };
  // 12 weeks × 7 days, mostly positive/neutral with some tired clusters
  const rows = [
    "positive,positive,neutral,empty,positive,energized,positive",
    "neutral,positive,positive,empty,tired,positive,positive",
    "positive,positive,energized,empty,positive,positive,energized",
    "positive,tired,positive,empty,neutral,positive,struggling",
    "positive,positive,neutral,empty,positive,energized,positive",
    "positive,energized,positive,empty,positive,positive,energized",
    "positive,tired,positive,empty,neutral,tired,positive",
    "positive,positive,energized,empty,positive,positive,positive",
    "neutral,positive,tired,empty,positive,positive,struggling",
    "positive,positive,neutral,empty,positive,positive,positive",
    "positive,energized,positive,empty,positive,energized,positive",
    "positive,positive,neutral,empty,positive,positive,positive",
  ].map((r) => r.split(","));

  return (
    <div className="grid grid-cols-[16px_1fr] gap-x-2">
      {/* day legend */}
      <div className="flex flex-col justify-between pt-1 pb-1">
        {["M", "W", "F", "S"].map((d, i) => (
          <span key={i} className="font-mono text-[9px] tracking-[1.2px] text-text-tertiary leading-none">
            {d}
          </span>
        ))}
      </div>
      <div>
        <div className="grid grid-cols-12 gap-[3px]">
          {Array.from({ length: 7 }).map((_, day) =>
            rows.map((row, w) => (
              <div
                key={`${w}-${day}`}
                className="w-full aspect-square rounded-[2px]"
                style={{
                  background: MOOD[row[day]] || HAIRLINE,
                  opacity: row[day] === "empty" ? 1 : 0.78,
                  gridRow: day + 1,
                  gridColumn: w + 1,
                }}
              />
            ))
          )}
        </div>
        <div className="mt-2 flex items-center gap-3 flex-wrap">
          {[
            ["ENERGIZED", "#2D8A4E"],
            ["POSITIVE", "#4A9E6B"],
            ["NEUTRAL", "#9B9590"],
            ["TIRED", "#C4873A"],
            ["STRUGGLING", "#C45A3A"],
          ].map(([lbl, c]) => (
            <span key={lbl} className="inline-flex items-center gap-1.5">
              <span className="block h-2 w-2 rounded-[1px]" style={{ background: c }} />
              <span className="font-mono text-[9px] tracking-[1.2px] text-text-tertiary">{lbl}</span>
            </span>
          ))}
        </div>
      </div>
    </div>
  );
};

/* ════════════════════════════════════════════════════════════════════
   PACE-ZONE HISTOGRAM — minutes by zone, 12-week total
   ════════════════════════════════════════════════════════════════════ */
window.ZoneHistogram = function ZoneHistogram({ accent }) {
  const zones = [
    { name: "Easy", mins: 1240 },
    { name: "Steady", mins: 380 },
    { name: "MP", mins: 210 },
    { name: "LT", mins: 95 },
    { name: "10K", mins: 48 },
    { name: "5K", mins: 22 },
  ];
  const max = Math.max(...zones.map((z) => z.mins));

  return (
    <div className="space-y-2">
      {zones.map((z, i) => {
        const pct = (z.mins / max) * 100;
        const isAccent = i === 2; // MP highlighted as the "story" zone
        const hrs = Math.floor(z.mins / 60);
        const mns = z.mins % 60;
        return (
          <div key={z.name} className="grid grid-cols-[64px_1fr_56px] items-center gap-3">
            <span className="font-mono text-[10px] tracking-[1.3px] uppercase text-text-tertiary">
              {z.name}
            </span>
            <div className="relative h-3 bg-divider/60 rounded-[1px] overflow-hidden">
              <div
                className="absolute inset-y-0 left-0"
                style={{
                  width: `${pct}%`,
                  background: isAccent ? accent : INK,
                  opacity: isAccent ? 1 : 0.78,
                }}
              />
            </div>
            <span className="font-mono text-[10px] tabular-nums text-text-secondary text-right">
              {hrs}h {String(mns).padStart(2, "0")}m
            </span>
          </div>
        );
      })}
    </div>
  );
};

/* ════════════════════════════════════════════════════════════════════
   NIGGLES — body-part mentions surface (verbatim, no diagnosis)
   ════════════════════════════════════════════════════════════════════ */
window.NigglesList = function NigglesList({ accent }) {
  const items = [
    {
      part: "L. ACHILLES",
      count: 3,
      last: "MAY 11",
      quote: "tight first mile, eased up after",
      severity: "mild",
    },
    {
      part: "R. KNEE",
      count: 1,
      last: "APR 28",
      quote: "felt a pinch on the descent",
      severity: "passing",
    },
    {
      part: "L. CALF",
      count: 2,
      last: "MAY 5",
      quote: "a little knotty post-tempo",
      severity: "mild",
    },
  ];
  return (
    <div className="space-y-3">
      {items.map((it) => (
        <div key={it.part} className="grid grid-cols-[1fr_auto] gap-x-3">
          <div>
            <span className="font-mono text-[10.5px] tracking-[1.4px] text-text-primary">
              {it.part}
            </span>
            <span className="ml-2 font-mono text-[10px] text-text-tertiary">
              {it.count} mentions · last {it.last}
            </span>
            <p className="mt-1 font-body italic text-[14px] leading-[1.45] text-text-secondary">
              &ldquo;{it.quote}&rdquo;
            </p>
          </div>
          <span
            className="self-start font-mono text-[9.5px] tracking-[1.3px] uppercase px-1.5 py-0.5 rounded-[2px]"
            style={{
              color: accent,
              background: "rgba(212,89,42,0.08)",
            }}
          >
            {it.severity}
          </span>
        </div>
      ))}
      <p className="font-body italic text-[12px] leading-[1.45] text-text-tertiary pt-2 border-t border-divider-soft">
        Not medical advice. If anything gets sharper, see a clinician.
      </p>
    </div>
  );
};

/* ════════════════════════════════════════════════════════════════════
   RACE PREDICTIONS — range + confidence (per CLAUDE.md)
   ════════════════════════════════════════════════════════════════════ */
window.RacePredictions = function RacePredictions({ accent }) {
  const races = [
    { dist: "5K",       lo: "18:34", mid: "18:48", hi: "19:02", conf: "HIGH",   pct: 0.84 },
    { dist: "10K",      lo: "38:46", mid: "39:18", hi: "39:52", conf: "HIGH",   pct: 0.80 },
    { dist: "HALF",     lo: "1:26:12", mid: "1:27:30", hi: "1:28:54", conf: "MEDIUM", pct: 0.62 },
    { dist: "MARATHON", lo: "3:08:00", mid: "3:11:00", hi: "3:14:00", conf: "HIGH",   pct: 0.78 },
  ];
  return (
    <div className="space-y-3">
      {races.map((r) => (
        <div key={r.dist} className="border-b border-divider-soft pb-3 last:border-0 last:pb-0">
          <div className="flex items-baseline justify-between">
            <span className="font-mono text-[10.5px] tracking-[1.4px] text-text-primary">
              {r.dist}
            </span>
            <span
              className="font-mono text-[9.5px] tracking-[1.3px]"
              style={{ color: r.conf === "HIGH" ? accent : INK2 }}
            >
              {r.conf} CONFIDENCE
            </span>
          </div>
          <div className="mt-1.5 grid grid-cols-[1fr_auto_1fr] items-baseline gap-2">
            <span className="font-mono text-[12px] tabular-nums text-text-tertiary text-right">
              {r.lo}
            </span>
            <span className="font-display text-[22px] tabular-nums text-text-primary leading-none">
              {r.mid}
            </span>
            <span className="font-mono text-[12px] tabular-nums text-text-tertiary">
              {r.hi}
            </span>
          </div>
          {/* range bar */}
          <div className="mt-1.5 relative h-[3px] bg-divider/70 rounded-[1px]">
            <div
              className="absolute top-0 bottom-0"
              style={{
                left: `${15}%`,
                right: `${15}%`,
                background: INK2,
                opacity: 0.5,
              }}
            />
            <div
              className="absolute top-[-2px] bottom-[-2px] w-[2px]"
              style={{ left: "50%", background: accent }}
            />
          </div>
        </div>
      ))}
    </div>
  );
};

/* ════════════════════════════════════════════════════════════════════
   FITNESS CURVE — CTL / ATL / TSB, 12 weeks
   ════════════════════════════════════════════════════════════════════ */
window.FitnessCurve = function FitnessCurve({ accent, height = 140 }) {
  // CTL (fitness, slow), ATL (fatigue, fast), TSB (form, ctl-atl)
  const ctl = [42, 44, 47, 50, 52, 54, 57, 60, 62, 64, 66, 68];
  const atl = [38, 46, 54, 50, 56, 62, 58, 64, 68, 62, 56, 52];
  const tsb = ctl.map((c, i) => c - atl[i]);

  const W = 480;
  const H = height;
  const padL = 32;
  const padR = 16;
  const padT = 14;
  const padB = 22;
  const min = -25;
  const max = 80;

  const toPath = (arr) => {
    const pts = arr.map((v, i) => {
      const x = padL + (i * (W - padL - padR)) / (arr.length - 1);
      const y = padT + ((max - v) / (max - min)) * (H - padT - padB);
      return [x, y];
    });
    return pts.map(([x, y], i) => `${i === 0 ? "M" : "L"}${x},${y}`).join(" ");
  };

  const zeroY = padT + (max / (max - min)) * (H - padT - padB);

  return (
    <svg viewBox={`0 0 ${W} ${H}`} className="w-full h-auto block">
      {/* zero baseline for TSB */}
      <line x1={padL} x2={W - padR} y1={zeroY} y2={zeroY} stroke={HAIRLINE} strokeWidth="1" />

      <path d={toPath(ctl)} fill="none" stroke={INK} strokeWidth="1.75" />
      <path d={toPath(atl)} fill="none" stroke={INK2} strokeWidth="1.4" strokeDasharray="3 3" />
      <path d={toPath(tsb)} fill="none" stroke={accent} strokeWidth="1.6" />

      {/* axis label */}
      <text x={padL} y={H - 6} fontFamily="ui-monospace, Menlo, monospace" fontSize="9" letterSpacing="1.2" fill={INK3}>
        12 WEEKS
      </text>
      <text x={padL - 8} y={zeroY + 3} textAnchor="end" fontFamily="ui-monospace, Menlo, monospace" fontSize="9" letterSpacing="1.2" fill={INK3}>
        0
      </text>
    </svg>
  );
};

/* ════════════════════════════════════════════════════════════════════
   SPLITS — small sparkline (used in hero secondary card)
   ════════════════════════════════════════════════════════════════════ */
window.SplitsSpark = function SplitsSpark({ accent }) {
  const data = [7.80, 7.75, 7.73, 7.70, 7.68, 7.63, 7.67, 7.63, 7.30, 7.20];
  const W = 360;
  const H = 60;
  const padT = 6;
  const padB = 6;
  const padL = 8;
  const padR = 8;
  const min = 7.10;
  const max = 7.90;

  const pts = data.map((v, i) => {
    const x = padL + (i * (W - padL - padR)) / (data.length - 1);
    const y = padT + ((v - min) / (max - min)) * (H - padT - padB);
    return [x, y];
  });
  return (
    <svg viewBox={`0 0 ${W} ${H}`} className="w-full h-auto block">
      <polyline
        points={pts.slice(0, 8).map(([x, y]) => `${x},${y}`).join(" ")}
        fill="none"
        stroke={SAGE}
        strokeWidth="1.75"
      />
      <polyline
        points={pts.slice(7).map(([x, y]) => `${x},${y}`).join(" ")}
        fill="none"
        stroke={accent}
        strokeWidth="2"
      />
      {pts.map(([x, y], i) => (
        <circle key={i} cx={x} cy={y} r={i >= 8 ? "2.5" : "1.8"} fill={i >= 8 ? accent : SAGE} />
      ))}
    </svg>
  );
};

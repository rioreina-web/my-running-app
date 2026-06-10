/* global React, RUN, RUN_META, HR_ZONES, zoneForHR, SPLITS, RUN_MILES,
   fmtPace, linScale, linePath, areaPath, nearestIndex */
/* ════════════════════════════════════════════════════════════════════
   ANALYTICAL CHARTS · three directions
   A · Combined   — elevation terrain + pace & HR lines, zone ribbon, crosshair
   B · Stack      — small-multiples sharing one x-axis + synced crosshair
   C · Splits     — per-mile analysis, zone-colored bars, zone distribution
   Editorial language throughout: hairlines, mono tabular numerals, one coral.
   ════════════════════════════════════════════════════════════════════ */

const { useState, useRef } = React;

const CHART_CSS = `
.ac-screen { height: 100%; display: flex; flex-direction: column; background: var(--paper); color: var(--ink); overflow: hidden; }
.ac-scroll { flex: 1; overflow-y: auto; -webkit-overflow-scrolling: touch; }
.ac-scroll::-webkit-scrollbar { width: 0; }

.ac-plate { display: flex; justify-content: space-between; padding: 14px 22px 0; }
.ac-plate .l, .ac-plate .r { display: flex; flex-direction: column; gap: 2px; }
.ac-plate .r { text-align: right; }
.ac-mono { font-family: var(--font-mono); font-size: 10px; font-weight: 500; letter-spacing: 0.13em; text-transform: uppercase; color: var(--ink-3); }
.ac-mono--ink { color: var(--ink); }

.ac-head { padding: 16px 22px 0; }
.ac-eyebrow { font-family: var(--font-mono); font-size: 10px; font-weight: 500; letter-spacing: 0.14em; text-transform: uppercase; color: var(--coral); }
.ac-title { font-family: var(--font-display); font-weight: 700; font-size: 38px; line-height: 1; letter-spacing: -0.02em; color: var(--ink); margin-top: 6px; }
.ac-sub { font-family: var(--font-body); font-style: italic; font-size: 13px; color: var(--ink-2); margin-top: 6px; }

.ac-stats { display: grid; grid-template-columns: repeat(5, 1fr); border-top: 1px solid var(--rule); border-bottom: 1px solid var(--rule); margin: 18px 22px 0; }
.ac-stat { padding: 12px 4px; display: flex; flex-direction: column; align-items: center; gap: 6px; border-right: 1px solid var(--rule); }
.ac-stat:last-child { border-right: none; }
.ac-stat .k { font-family: var(--font-mono); font-size: 9px; font-weight: 500; letter-spacing: 0.1em; text-transform: uppercase; color: var(--ink-3); }
.ac-stat .v { font-family: var(--font-mono); font-weight: 600; font-size: 17px; color: var(--ink); font-variant-numeric: tabular-nums; }
.ac-stat .v span { font-size: 10px; color: var(--ink-3); margin-left: 1px; }

.ac-section { padding: 22px 22px 0; }
.ac-sechead { display: flex; align-items: baseline; justify-content: space-between; margin-bottom: 4px; }
.ac-sectitle { font-family: var(--font-mono); font-size: 10px; font-weight: 500; letter-spacing: 0.14em; text-transform: uppercase; color: var(--ink-2); }

/* readout row */
.ac-readout { display: flex; gap: 0; border: 1px solid var(--rule); border-radius: 8px; overflow: hidden; margin-bottom: 10px; }
.ac-ro { flex: 1; padding: 8px 10px; border-right: 1px solid var(--rule); }
.ac-ro:last-child { border-right: none; }
.ac-ro .k { font-family: var(--font-mono); font-size: 8px; font-weight: 500; letter-spacing: 0.1em; text-transform: uppercase; color: var(--ink-3); }
.ac-ro .v { font-family: var(--font-mono); font-weight: 600; font-size: 15px; color: var(--ink); font-variant-numeric: tabular-nums; margin-top: 3px; }
.ac-ro .v small { font-size: 9px; color: var(--ink-3); font-weight: 500; margin-left: 1px; }

.ac-chart { width: 100%; display: block; touch-action: none; user-select: none; }
.ac-axislbl { font-family: var(--font-mono); font-size: 8px; fill: var(--ink-3); letter-spacing: 0.04em; }

/* legend */
.ac-legend { display: flex; flex-wrap: wrap; gap: 12px; margin-top: 12px; }
.ac-leg { display: flex; align-items: center; gap: 6px; }
.ac-leg .sw { width: 14px; height: 3px; border-radius: 2px; }
.ac-leg .sw--dash { background: repeating-linear-gradient(90deg, currentColor 0 4px, transparent 4px 7px); height: 2px; }
.ac-leg .lbl { font-family: var(--font-mono); font-size: 9px; letter-spacing: 0.08em; text-transform: uppercase; color: var(--ink-2); }

/* zone distribution */
.ac-zdist { display: flex; height: 16px; border-radius: 3px; overflow: hidden; margin-top: 6px; }
.ac-zlegend { display: grid; grid-template-columns: repeat(5, 1fr); gap: 0; margin-top: 12px; }
.ac-zl { display: flex; flex-direction: column; gap: 4px; align-items: flex-start; padding-right: 8px; }
.ac-zl .dot { width: 7px; height: 7px; border-radius: 999px; }
.ac-zl .nm { font-family: var(--font-mono); font-size: 9px; font-weight: 600; color: var(--ink); letter-spacing: 0.04em; }
.ac-zl .pc { font-family: var(--font-mono); font-size: 11px; color: var(--ink-2); font-variant-numeric: tabular-nums; }
.ac-zl .tm { font-family: var(--font-mono); font-size: 8px; color: var(--ink-3); }

/* splits table */
.ac-split { display: grid; grid-template-columns: 22px 1fr 52px 40px; align-items: center; gap: 10px; padding: 9px 0; border-bottom: 1px solid var(--rule); }
.ac-split:last-child { border-bottom: none; }
.ac-split .mi { font-family: var(--font-mono); font-size: 12px; font-weight: 600; color: var(--ink-2); font-variant-numeric: tabular-nums; }
.ac-split .barwrap { height: 18px; position: relative; background: var(--paper-deep); border-radius: 3px; overflow: hidden; }
.ac-split .bar { position: absolute; left: 0; top: 0; bottom: 0; border-radius: 3px; }
.ac-split .pc { font-family: var(--font-mono); font-size: 13px; font-weight: 600; color: var(--ink); text-align: right; font-variant-numeric: tabular-nums; }
.ac-split .pc small { font-size: 8px; color: var(--ink-3); }
.ac-split .hr { display: flex; align-items: center; justify-content: flex-end; gap: 5px; font-family: var(--font-mono); font-size: 12px; color: var(--ink-2); font-variant-numeric: tabular-nums; }
.ac-split .hr .d { width: 6px; height: 6px; border-radius: 999px; }
.ac-splithead { display: grid; grid-template-columns: 22px 1fr 52px 40px; gap: 10px; padding-bottom: 6px; border-bottom: 1px solid var(--rule); }
.ac-splithead span { font-family: var(--font-mono); font-size: 8px; letter-spacing: 0.1em; text-transform: uppercase; color: var(--ink-3); }
.ac-splithead span:nth-child(3), .ac-splithead span:nth-child(4) { text-align: right; }

/* segmented view toggle (in-app workout detail) */
.ac-seg { display: flex; gap: 0; border-bottom: 1px solid var(--rule); margin-bottom: 14px; }
.ac-seg button {
  flex: 1; appearance: none; background: none; border: none; cursor: pointer;
  padding: 9px 4px 10px; margin: 0;
  font-family: var(--font-mono); font-size: 10px; font-weight: 500;
  letter-spacing: 0.13em; text-transform: uppercase; color: var(--ink-3);
  border-bottom: 2px solid transparent; margin-bottom: -1px;
  transition: color var(--dur-fast, .15s) var(--ease-out, ease), border-color var(--dur-fast, .15s) var(--ease-out, ease);
}
.ac-seg button:hover { color: var(--ink-2); }
.ac-seg button[aria-selected="true"] { color: var(--coral); border-bottom-color: var(--coral); }
`;

// ── crosshair hook: maps pointer x → nearest sample index ────────────────
function useCrosshair(defaultIdx, W, xAcc) {
  const [idx, setIdx] = useState(defaultIdx);
  const ref = useRef(null);
  const onMove = (e) => {
    const svg = ref.current; if (!svg) return;
    const rect = svg.getBoundingClientRect();
    const cx = (e.touches ? e.touches[0].clientX : e.clientX) - rect.left;
    const vx = (cx / rect.width) * W;
    setIdx(nearestIndex(RUN, xAcc, vx));
  };
  return { idx, setIdx, ref, onMove };
}

// ── readout chip row (shared) ────────────────────────────────────────────
function Readout({ p }) {
  const z = zoneForHR(p.hr);
  return (
    <div className="ac-readout">
      <div className="ac-ro"><div className="k">Distance</div><div className="v">{p.d.toFixed(2)}<small>mi</small></div></div>
      <div className="ac-ro"><div className="k">Pace</div><div className="v" style={{ color: "var(--coral)" }}>{fmtPace(p.pace)}<small>/mi</small></div></div>
      <div className="ac-ro"><div className="k">Heart rate</div><div className="v">{p.hr}<small> · {z.name}</small></div></div>
      <div className="ac-ro"><div className="k">Elevation</div><div className="v">{Math.round(p.elev)}<small>m</small></div></div>
    </div>
  );
}

/* ════════════════════════════════════════════════════════════════════════
   A · COMBINED — terrain area + pace & HR lines + HR-zone ribbon
   ════════════════════════════════════════════════════════════════════════ */
function CombinedChart() {
  const W = 360, H = 196;
  const padL = 30, padR = 32, padT = 12, plotB = 150;
  const x = linScale(0, RUN_MILES, padL, W - padR);
  const xAcc = p => x(p.d);

  const paces = RUN.map(p => p.pace), hrs = RUN.map(p => p.hr), elevs = RUN.map(p => p.elev);
  const pMin = Math.min(...paces) - 6, pMax = Math.max(...paces) + 6;
  const hMin = Math.min(...hrs) - 4, hMax = Math.max(...hrs) + 4;
  const eMin = Math.min(...elevs), eMax = Math.max(...elevs);
  // pace inverted (faster = up); occupies full plot
  const yPace = linScale(pMin, pMax, padT, plotB);
  const yHR = linScale(hMin, hMax, padT + 4, plotB);
  // elevation terrain pinned to lower third
  const yElev = linScale(eMin, eMax, plotB, plotB - 56);

  const cross = useCrosshair(Math.round(RUN.length * 0.45), W, xAcc);
  const cur = RUN[cross.idx];
  const cx = x(cur.d);

  const paceTicks = [];
  for (let s = Math.ceil(pMin / 15) * 15; s <= pMax; s += 15) paceTicks.push(s);
  const hrTicks = [130, 145, 160].filter(v => v > hMin && v < hMax);

  return (
    <div>
      <Readout p={cur} />
      <svg className="ac-chart" viewBox={`0 0 ${W} ${H}`} ref={cross.ref}
        onMouseMove={cross.onMove} onTouchStart={cross.onMove} onTouchMove={cross.onMove}>
        {/* pace gridlines */}
        {paceTicks.map(s => (
          <g key={"p" + s}>
            <line x1={padL} x2={W - padR} y1={yPace(s)} y2={yPace(s)} stroke="var(--rule)" strokeWidth="1" strokeDasharray="1 4" />
            <text className="ac-axislbl" x={padL - 4} y={yPace(s) + 3} textAnchor="end" style={{ fill: "var(--coral)" }}>{fmtPace(s)}</text>
          </g>
        ))}
        {/* hr right-axis labels */}
        {hrTicks.map(v => (
          <text key={"h" + v} className="ac-axislbl" x={W - padR + 4} y={yHR(v) + 3} textAnchor="start">{v}</text>
        ))}
        {/* light mile-mark gridlines */}
        {[1, 2, 3, 4, 5, 6].map(mi => (
          <line key={"gm" + mi} x1={x(mi)} x2={x(mi)} y1={padT} y2={plotB} stroke="var(--rule)" strokeWidth="1" strokeDasharray="1 4" opacity="0.7" />
        ))}
        {/* elevation terrain */}
        <path d={areaPath(RUN, xAcc, p => yElev(p.elev), plotB)} fill="var(--paper-deep)" opacity="0.85" />
        <path d={linePath(RUN, xAcc, p => yElev(p.elev))} fill="none" stroke="var(--ink-3)" strokeWidth="1" opacity="0.5" />
        {/* HR line */}
        <path d={linePath(RUN, xAcc, p => yHR(p.hr))} fill="none" stroke="#B83A4A" strokeWidth="1.6" strokeLinejoin="round" opacity="0.85" />
        {/* pace line (coral hero) */}
        <path d={linePath(RUN, xAcc, p => yPace(p.pace))} fill="none" stroke="var(--coral)" strokeWidth="2.2" strokeLinejoin="round" strokeLinecap="round" />

        {/* zone ribbon */}
        {RUN.slice(0, -1).map((p, i) => (
          <rect key={i} x={x(p.d)} y={plotB + 8} width={x(RUN[i + 1].d) - x(p.d) + 0.6} height={9}
            fill={zoneForHR(p.hr).color} opacity="0.9" />
        ))}
        <text className="ac-axislbl" x={padL} y={plotB + 30} textAnchor="start">0</text>
        {[1, 2, 3, 4, 5, 6].map(mi => (
          <text key={mi} className="ac-axislbl" x={x(mi)} y={plotB + 30} textAnchor="middle">{mi}</text>
        ))}
        <text className="ac-axislbl" x={W - padR} y={plotB + 30} textAnchor="end">MI</text>

        {/* crosshair */}
        <line x1={cx} x2={cx} y1={padT} y2={plotB + 17} stroke="var(--ink)" strokeWidth="1" opacity="0.5" />
        <circle cx={cx} cy={yPace(cur.pace)} r="3.5" fill="var(--coral)" stroke="var(--paper)" strokeWidth="1.5" />
        <circle cx={cx} cy={yHR(cur.hr)} r="3" fill="#B83A4A" stroke="var(--paper)" strokeWidth="1.5" />
      </svg>

      <div className="ac-legend">
        <div className="ac-leg" style={{ color: "var(--coral)" }}><span className="sw" style={{ background: "var(--coral)" }} /><span className="lbl">Pace</span></div>
        <div className="ac-leg" style={{ color: "#B83A4A" }}><span className="sw" style={{ background: "#B83A4A" }} /><span className="lbl">Heart rate</span></div>
        <div className="ac-leg"><span className="sw" style={{ background: "var(--paper-deep)", height: 8, borderRadius: 2 }} /><span className="lbl">Elevation</span></div>
        <div className="ac-leg"><span className="lbl" style={{ color: "var(--ink-3)" }}>↑ drag chart to scrub</span></div>
      </div>
    </div>
  );
}

/* ════════════════════════════════════════════════════════════════════════
   B · STACK — small multiples sharing one x-axis + synced crosshair
   ════════════════════════════════════════════════════════════════════════ */
function StackPanel({ title, unit, color, accessor, fmt, area, zoneBands, idx, cross, W }) {
  const padL = 30, padR = 14, h = 60, padT = 8, padB = 6;
  const x = linScale(0, RUN_MILES, padL, W - padR);
  const xAcc = p => x(p.d);
  const vals = RUN.map(accessor);
  const vMin = Math.min(...vals), vMax = Math.max(...vals);
  const pad = (vMax - vMin) * 0.12 || 1;
  // pace inverted
  const inv = title === "Pace";
  const y = inv ? linScale(vMin - pad, vMax + pad, padT, h - padB) : linScale(vMin - pad, vMax + pad, h - padB, padT);
  const cur = RUN[idx];
  const cx = x(cur.d);
  const ticks = [vMin + pad * 0.5, (vMin + vMax) / 2, vMax - pad * 0.5];

  return (
    <div style={{ marginTop: 10 }}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline", marginBottom: 2 }}>
        <span className="ac-mono ac-mono--ink" style={{ color }}>{title}</span>
        <span className="ac-mono" style={{ color: "var(--ink)", fontSize: 13, fontWeight: 600 }}>
          {fmt(accessor(cur))}<span style={{ color: "var(--ink-3)", fontSize: 9 }}> {unit}</span>
        </span>
      </div>
      <svg className="ac-chart" viewBox={`0 0 ${W} ${h}`} ref={cross.ref} style={{ height: h }}
        onMouseMove={cross.onMove} onTouchStart={cross.onMove} onTouchMove={cross.onMove}>
        {/* light mile-mark gridlines */}
        {[1, 2, 3, 4, 5, 6].map(mi => (
          <line key={"m" + mi} x1={x(mi)} x2={x(mi)} y1={padT} y2={h - padB} stroke="var(--rule)" strokeWidth="1" strokeDasharray="1 4" opacity="0.7" />
        ))}
        {zoneBands && HR_ZONES.filter(z => z.max < 900 && z.min >= vMin - pad && z.min <= vMax + pad).map(z => (
          <line key={z.id} x1={padL} x2={W - padR} y1={y(z.min)} y2={y(z.min)} stroke={z.color} strokeWidth="1" strokeDasharray="2 3" opacity="0.5" />
        ))}
        {ticks.map((t, i) => (
          <text key={i} className="ac-axislbl" x={padL - 4} y={y(t) + 3} textAnchor="end">{fmt(t)}</text>
        ))}
        {area && <path d={areaPath(RUN, xAcc, p => y(accessor(p)), h - padB)} fill={color} opacity="0.14" />}
        <path d={linePath(RUN, xAcc, p => y(accessor(p)))} fill="none" stroke={color} strokeWidth={inv ? 2.2 : 1.8} strokeLinejoin="round" strokeLinecap="round" />
        <line x1={cx} x2={cx} y1={padT} y2={h - padB} stroke="var(--ink)" strokeWidth="1" opacity="0.45" />
        <circle cx={cx} cy={y(accessor(cur))} r="3.2" fill={color} stroke="var(--paper)" strokeWidth="1.5" />
      </svg>
      {/* per-chart distance axis */}
      <svg className="ac-chart" viewBox={`0 0 ${W} 13`} style={{ height: 13, marginTop: 1 }}>
        <text className="ac-axislbl" x={padL} y={9} textAnchor="start">0</text>
        {[1, 2, 3, 4, 5, 6].map(mi => <text key={mi} className="ac-axislbl" x={x(mi)} y={9} textAnchor="middle">{mi}</text>)}
        <text className="ac-axislbl" x={W - padR} y={9} textAnchor="end">MI</text>
      </svg>
    </div>
  );
}
function StackCharts() {
  const W = 360;
  const x = linScale(0, RUN_MILES, 30, W - 14);
  const cross = useCrosshair(Math.round(RUN.length * 0.62), W, p => x(p.d));
  const cur = RUN[cross.idx];
  return (
    <div>
      <Readout p={cur} />
      <StackPanel title="Pace" unit="/mi" color="var(--coral)" accessor={p => p.pace} fmt={fmtPace} idx={cross.idx} cross={cross} W={W} />
      <StackPanel title="Heart rate" unit="bpm" color="#B83A4A" accessor={p => p.hr} fmt={v => Math.round(v)} zoneBands idx={cross.idx} cross={cross} W={W} />
      <StackPanel title="Elevation" unit="m" color="#6B6560" accessor={p => p.elev} fmt={v => Math.round(v)} area idx={cross.idx} cross={cross} W={W} />
    </div>
  );
}

/* ════════════════════════════════════════════════════════════════════════
   C · SPLITS — per-mile analysis, zone-colored pace bars, zone distribution
   ════════════════════════════════════════════════════════════════════════ */
function SplitsChart() {
  const W = 360;
  const avgPace = RUN.reduce((s, p) => s + p.pace, 0) / RUN.length;
  const paceMin = Math.min(...SPLITS.map(s => s.pace));
  const paceMax = Math.max(...SPLITS.map(s => s.pace));
  // bar length: faster = longer (more fill)
  const barPct = pc => 20 + ((paceMax - pc) / ((paceMax - paceMin) || 1)) * 72;

  // elevation profile mini
  const x = linScale(0, RUN_MILES, 2, W - 2);
  const elevs = RUN.map(p => p.elev);
  const yE = linScale(Math.min(...elevs), Math.max(...elevs), 42, 6);

  // zone distribution (share of samples)
  const total = RUN.length;
  const zoneCounts = HR_ZONES.map(z => ({ z, n: RUN.filter(p => zoneForHR(p.hr).id === z.id).length }))
    .filter(d => d.n > 0);

  return (
    <div>
      {/* elevation profile header */}
      <svg className="ac-chart" viewBox={`0 0 ${W} 46`} style={{ height: 46, marginBottom: 6 }}>
        <path d={areaPath(RUN, p => x(p.d), p => yE(p.elev), 44)} fill="var(--paper-deep)" />
        <path d={linePath(RUN, p => x(p.d), p => yE(p.elev))} fill="none" stroke="var(--ink-3)" strokeWidth="1" />
        {[1, 2, 3, 4, 5, 6].map(mi => <line key={mi} x1={x(mi)} x2={x(mi)} y1={4} y2={44} stroke="var(--rule)" strokeWidth="1" strokeDasharray="1 3" />)}
      </svg>

      <div className="ac-splithead">
        <span>MI</span><span>Pace · by HR zone</span><span>Pace</span><span>Gain</span>
      </div>
      {SPLITS.map((s, i) => (
        <div className="ac-split" key={i}>
          <span className="mi">{s.partial ? s.mile : s.mile}</span>
          <div className="barwrap">
            <div className="bar" style={{ width: barPct(s.pace) + "%", background: s.zone.color, opacity: 0.9 }} />
          </div>
          <div className="pc">{fmtPace(s.pace)}<small>/mi</small></div>
          <div className="hr"><span className="d" style={{ background: s.zone.color }} />{s.gain >= 0 ? "+" : ""}{s.gain}</div>
        </div>
      ))}

      {/* zone distribution */}
      <div style={{ marginTop: 20 }}>
        <div className="ac-sectitle">Time in heart-rate zones</div>
        <div className="ac-zdist">
          {zoneCounts.map(({ z, n }) => (
            <div key={z.id} style={{ width: (n / total) * 100 + "%", background: z.color }} />
          ))}
        </div>
        <div className="ac-zlegend">
          {HR_ZONES.map(z => {
            const n = RUN.filter(p => zoneForHR(p.hr).id === z.id).length;
            const pct = Math.round((n / total) * 100);
            const mins = (n / total) * 51.1;
            return (
              <div className="ac-zl" key={z.id}>
                <span className="dot" style={{ background: z.color }} />
                <span className="nm">{z.name}</span>
                <span className="pc">{pct}%</span>
                <span className="tm">{pct ? `${Math.floor(mins)}:${String(Math.round((mins % 1) * 60)).padStart(2, "0")}` : "—"}</span>
              </div>
            );
          })}
        </div>
      </div>
    </div>
  );
}

/* ════════════════════════════════════════════════════════════════════════
   RUN SCREEN — editorial workout-detail context wrapping a chart
   ════════════════════════════════════════════════════════════════════════ */
function RunScreen({ chart, sectionTitle, sectionRight }) {
  return (
    <div className="ac-screen">
      <style>{CHART_CSS}</style>
      <div className="ac-plate">
        <div className="l"><span className="ac-mono ac-mono--ink">RUNNING LOG</span><span className="ac-mono">— WORKOUT · ANALYSIS</span></div>
        <div className="r"><span className="ac-mono ac-mono--ink">{RUN_META.date.split(" · ")[0]}</span><span className="ac-mono">{RUN_META.date.split(" · ")[1]}</span></div>
      </div>
      <div className="ac-scroll">
        <div className="ac-head">
          <div className="ac-eyebrow">TEMPO · NEGATIVE SPLIT</div>
          <div className="ac-title">{RUN_META.day}.</div>
          <div className="ac-sub">— a rolling six-point-nine. Climbed early, came home fast. —</div>
        </div>
        <div className="ac-stats">
          {[
            { k: "Dist", v: RUN_META.distance, u: "mi" },
            { k: "Time", v: RUN_META.time },
            { k: "Pace", v: RUN_META.pace, u: "/mi" },
            { k: "Avg HR", v: RUN_META.hr, u: "bpm" },
            { k: "Elev", v: RUN_META.elev, u: "m" },
          ].map(s => (
            <div className="ac-stat" key={s.k}><span className="k">{s.k}</span><span className="v">{s.v}{s.u && <span>{s.u}</span>}</span></div>
          ))}
        </div>
        <div className="ac-section">
          <div className="ac-sechead">
            <span className="ac-sectitle">{sectionTitle}</span>
            <span className="ac-sectitle" style={{ color: "var(--ink-3)" }}>{sectionRight}</span>
          </div>
          {chart}
        </div>
        <div style={{ height: 28 }} />
      </div>
    </div>
  );
}

window.CombinedChart = CombinedChart;
window.StackCharts = StackCharts;
window.SplitsChart = SplitsChart;
window.RunScreen = RunScreen;

/* ════════════════════════════════════════════════════════════════════════
   WORKOUT TELEMETRY — embeddable block for the in-app workout detail.
   Segmented toggle across the three analytical treatments. Injects CHART_CSS
   so it works standalone inside any editorial screen (no RunScreen wrapper).
   ════════════════════════════════════════════════════════════════════════ */
function WorkoutTelemetry({ initial = "combined" }) {
  const [view, setView] = useState(initial);
  const TABS = [
    ["combined", "Combined"],
    ["stack", "Stacked"],
    ["splits", "Splits"],
  ];
  return (
    <div>
      <style>{CHART_CSS}</style>
      <div className="ac-seg" role="tablist">
        {TABS.map(([id, label]) => (
          <button
            key={id}
            role="tab"
            aria-selected={view === id}
            onClick={() => setView(id)}
          >
            {label}
          </button>
        ))}
      </div>
      {view === "combined" && <CombinedChart />}
      {view === "stack" && <StackCharts />}
      {view === "splits" && <SplitsChart />}
    </div>
  );
}
window.WorkoutTelemetry = WorkoutTelemetry;
